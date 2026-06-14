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

const PRICES: Record<string, { amount: number; currency: string }> = {
  starter: { amount: 250, currency: 'KES' },
  pro: { amount: 1000, currency: 'KES' },
};

async function getPesapalToken(): Promise<string> {
  const resp = await fetch(`${PESAPAL_BASE}/api/Auth/RequestToken`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
    body: JSON.stringify({
      consumer_key: PESAPAL_CONSUMER_KEY,
      consumer_secret: PESAPAL_CONSUMER_SECRET,
    }),
  });
  const data = await resp.json();
  return data.token;
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get('authorization') ?? '';
    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);
    const { data: { user }, error: authError } = await supabase.auth.getUser(
      authHeader.replace('Bearer ', '')
    );
    if (authError || !user) {
      return new Response(JSON.stringify({ error: 'Unauthorized' }), {
        status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const { tier } = await req.json();
    const price = PRICES[tier] ?? PRICES['starter'];
    const token = await getPesapalToken();
    const orderRef = `receiptiq-${user.id.slice(0, 8)}-${Date.now()}`;

    // Register IPN
    const ipnResp = await fetch(`${PESAPAL_BASE}/api/URLSetup/RegisterIPN`, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${token}`,
        'Content-Type': 'application/json',
        Accept: 'application/json',
      },
      body: JSON.stringify({ url: PESAPAL_IPN_URL, ipn_notification_type: 'GET' }),
    });
    const ipnData = await ipnResp.json();
    const ipnId = ipnData.ipn_id;

    // Submit order
    const orderResp = await fetch(`${PESAPAL_BASE}/api/Transactions/SubmitOrderRequest`, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${token}`,
        'Content-Type': 'application/json',
        Accept: 'application/json',
      },
      body: JSON.stringify({
        id: orderRef,
        currency: price.currency,
        amount: price.amount,
        description: `ReceiptIQ ${tier} subscription`,
        callback_url: PESAPAL_CALLBACK_URL,
        notification_id: ipnId,
        billing_address: { email_address: user.email ?? `${user.id}@receiptiq.app` },
      }),
    });
    const orderData = await orderResp.json();

    if (!orderData.redirect_url) {
      return new Response(JSON.stringify({ error: orderData.error?.message ?? 'Pesapal order failed' }), {
        status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    await supabase.from('payment_transactions').insert({
      user_id: user.id,
      amount: price.amount,
      currency: price.currency,
      provider: 'pesapal',
      status: 'pending',
      tier,
      provider_ref: orderRef,
      metadata: { order_tracking_id: orderData.order_tracking_id },
    });

    return new Response(JSON.stringify({ checkoutUrl: orderData.redirect_url }), {
      status: 200,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  } catch (err) {
    return new Response(JSON.stringify({ error: String(err) }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
});
