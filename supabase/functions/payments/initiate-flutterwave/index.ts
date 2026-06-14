import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const FW_SECRET_KEY = Deno.env.get('FLUTTERWAVE_SECRET_KEY')!;
const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const APP_REDIRECT_URL = Deno.env.get('APP_REDIRECT_URL') ?? 'https://receiptiq.app/payment-success';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

// Pricing per tier per country (same values as subscription_config.dart)
const PRICES: Record<string, Record<string, { amount: number; currency: string }>> = {
  starter: {
    KE: { amount: 250, currency: 'KES' },
    NG: { amount: 3000, currency: 'NGN' },
    GH: { amount: 30, currency: 'GHS' },
    TZ: { amount: 5000, currency: 'TZS' },
    UG: { amount: 7500, currency: 'UGX' },
    default: { amount: 2, currency: 'USD' },
  },
  pro: {
    KE: { amount: 1000, currency: 'KES' },
    NG: { amount: 12000, currency: 'NGN' },
    GH: { amount: 120, currency: 'GHS' },
    TZ: { amount: 20000, currency: 'TZS' },
    UG: { amount: 30000, currency: 'UGX' },
    default: { amount: 8, currency: 'USD' },
  },
};

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

    const { tier, countryCode } = await req.json();
    const country = (countryCode ?? 'default').toUpperCase();
    const tierPrices = PRICES[tier] ?? PRICES['starter'];
    const price = tierPrices[country] ?? tierPrices['default'];

    const txRef = `receiptiq-${user.id.slice(0, 8)}-${Date.now()}`;

    const fwResp = await fetch('https://api.flutterwave.com/v3/payments', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${FW_SECRET_KEY}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        tx_ref: txRef,
        amount: price.amount,
        currency: price.currency,
        redirect_url: APP_REDIRECT_URL,
        customer: { email: user.email ?? `${user.id}@receiptiq.app` },
        customizations: {
          title: `ReceiptIQ ${tier.charAt(0).toUpperCase() + tier.slice(1)}`,
          description: `Monthly subscription — ${tier} plan`,
          logo: 'https://receiptiq.app/icon.png',
        },
        meta: { user_id: user.id, tier, tx_ref: txRef },
      }),
    });

    const fwData = await fwResp.json();
    if (fwData.status !== 'success') {
      return new Response(JSON.stringify({ error: fwData.message ?? 'Flutterwave error' }), {
        status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const paymentLink = fwData.data.link;

    // Record pending transaction
    await supabase.from('payment_transactions').insert({
      user_id: user.id,
      amount: price.amount,
      currency: price.currency,
      provider: 'flutterwave',
      status: 'pending',
      tier,
      provider_ref: txRef,
    });

    return new Response(JSON.stringify({ paymentLink, txRef }), {
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
