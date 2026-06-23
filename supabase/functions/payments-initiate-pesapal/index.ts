import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const PESAPAL_CONSUMER_KEY = Deno.env.get('PESAPAL_CONSUMER_KEY')!;
const PESAPAL_CONSUMER_SECRET = Deno.env.get('PESAPAL_CONSUMER_SECRET')!;
const PESAPAL_IPN_URL = Deno.env.get('PESAPAL_IPN_URL')!;
const PESAPAL_CALLBACK_URL = Deno.env.get('PESAPAL_CALLBACK_URL') ?? 'https://receiptiq.app/payment-success';
const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

const PESAPAL_BASE = 'https://pay.pesapal.com/v3';
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};
type PriceEntry = { amount: number; currency: string };

const PRICES: Record<string, { monthly: PriceEntry; yearly: PriceEntry }> = {
  starter: {
    monthly: { amount: 250,   currency: 'KES' },
    yearly:  { amount: 2500,  currency: 'KES' },
  },
  pro: {
    monthly: { amount: 1000,  currency: 'KES' },
    yearly:  { amount: 10000, currency: 'KES' },
  },
};

async function getPesapalToken(): Promise<string> {
  const resp = await fetch(`${PESAPAL_BASE}/api/Auth/RequestToken`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
    body: JSON.stringify({ consumer_key: PESAPAL_CONSUMER_KEY, consumer_secret: PESAPAL_CONSUMER_SECRET }),
  });
  const data = await resp.json();
  return data.token;
}


serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });

  try {
    const authHeader = req.headers.get('authorization') ?? '';
    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);
    const { data: { user }, error: authError } = await supabase.auth.getUser(authHeader.replace('Bearer ', ''));
    if (authError || !user) {
      return new Response(JSON.stringify({ error: 'Unauthorized' }), {
        status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const { tier, billing_period = 'monthly' } = await req.json();
    const tierPrices = PRICES[tier] ?? PRICES['starter'];
    let price = billing_period === 'yearly' ? tierPrices.yearly : tierPrices.monthly;
    const frequency = billing_period === 'yearly' ? 'ANNUAL' : 'MONTHLY';

    // Check for existing subscription (upgrade scenario)
    const { data: existingSub } = await supabase
      .from('user_subscriptions')
      .select('*')
      .eq('user_id', user.id)
      .single();

    let isUpgrade = false;
    let oldTier = null;
    let proratedCredit = 0;

    if (existingSub && existingSub.tier !== tier && existingSub.expires_at) {
      const now = new Date();
      const expiryDate = new Date(existingSub.expires_at);
      
      // Only calculate proration if subscription is still active
      if (expiryDate > now) {
        isUpgrade = true;
        oldTier = existingSub.tier;
        
        // Calculate remaining days
        const remainingMs = expiryDate.getTime() - now.getTime();
        const remainingDays = remainingMs / (1000 * 60 * 60 * 24);
        
        // Get old tier price
        const oldTierPrices = PRICES[oldTier] ?? PRICES['starter'];
        const oldPrice = existingSub.billing_period === 'yearly' 
          ? oldTierPrices.yearly 
          : oldTierPrices.monthly;
        
        // Calculate prorated credit
        const totalPeriodDays = existingSub.billing_period === 'yearly' ? 365 : 30;
        proratedCredit = Math.floor((remainingDays / totalPeriodDays) * oldPrice.amount);
        
        // Adjust payment amount (ensure minimum of 0)
        price = {
          amount: Math.max(0, price.amount - proratedCredit),
          currency: price.currency,
        };
      }
    }

    const token = await getPesapalToken();
    const orderRef = `receiptiq-${user.id.slice(0, 8)}-${Date.now()}`;

    const ipnResp = await fetch(`${PESAPAL_BASE}/api/URLSetup/RegisterIPN`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json', Accept: 'application/json' },
      body: JSON.stringify({ url: PESAPAL_IPN_URL, ipn_notification_type: 'GET' }),
    });
    const ipnData = await ipnResp.json();

    const orderResp = await fetch(`${PESAPAL_BASE}/api/Transactions/SubmitOrderRequest`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json', Accept: 'application/json' },
      body: JSON.stringify({
        id: orderRef,
        currency: price.currency,
        amount: price.amount,
        description: `ReceiptIQ ${tier} subscription (${billing_period})${isUpgrade ? ' - Upgrade' : ''}`,
        callback_url: PESAPAL_CALLBACK_URL,
        notification_id: ipnData.ipn_id,
        billing_address: { email_address: user.email ?? `${user.id}@receiptiq.app` },
        // subscription_details requires Pesapal recurring billing to be enabled
        // on the merchant account. Contact Pesapal support to activate, then
        // uncomment the block below:
        // subscription_details: {
        //   start_date: isoDate(startDate),
        //   end_date:   isoDate(endDate),
        //   frequency,
        // },
      }),
    });
    const orderData = await orderResp.json();

    if (!orderData.redirect_url) {
      return new Response(JSON.stringify({ error: orderData.error?.message ?? 'Pesapal order failed' }), {
        status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    await supabase.from('payment_transactions').insert({
      user_id: user.id, amount: price.amount, currency: price.currency,
      provider: 'pesapal', status: 'pending', tier, provider_ref: orderRef,
      metadata: {
        order_tracking_id: orderData.order_tracking_id,
        billing_period,
        frequency,
        is_upgrade: isUpgrade,
        old_tier: oldTier,
        prorated_credit: proratedCredit,
      },
    });

    return new Response(JSON.stringify({ 
      checkoutUrl: orderData.redirect_url,
      isUpgrade,
      proratedCredit,
      adjustedAmount: price.amount,
    }), {
      status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  } catch (err) {
    return new Response(JSON.stringify({ error: String(err) }), {
      status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
});
