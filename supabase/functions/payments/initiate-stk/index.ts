import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const DARAJA_CONSUMER_KEY = Deno.env.get('DARAJA_CONSUMER_KEY')!;
const DARAJA_CONSUMER_SECRET = Deno.env.get('DARAJA_CONSUMER_SECRET')!;
const DARAJA_SHORTCODE = Deno.env.get('DARAJA_SHORTCODE')!;
const DARAJA_PASSKEY = Deno.env.get('DARAJA_PASSKEY')!;
const DARAJA_CALLBACK_URL = Deno.env.get('DARAJA_CALLBACK_URL')!;
const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    // Authenticate calling user from JWT
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

    const { phone, tier, amount, currency } = await req.json();

    // Get Daraja OAuth token
    const tokenResp = await fetch(
      'https://api.safaricom.co.ke/oauth/v1/generate?grant_type=client_credentials',
      {
        headers: {
          Authorization: 'Basic ' + btoa(`${DARAJA_CONSUMER_KEY}:${DARAJA_CONSUMER_SECRET}`),
        },
      }
    );
    const { access_token } = await tokenResp.json();

    // Generate password (base64 of shortcode + passkey + timestamp)
    const timestamp = new Date().toISOString().replace(/\D/g, '').slice(0, 14);
    const password = btoa(`${DARAJA_SHORTCODE}${DARAJA_PASSKEY}${timestamp}`);

    // Initiate STK Push
    const stkResp = await fetch(
      'https://api.safaricom.co.ke/mpesa/stkpush/v1/processrequest',
      {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${access_token}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          BusinessShortCode: DARAJA_SHORTCODE,
          Password: password,
          Timestamp: timestamp,
          TransactionType: 'CustomerPayBillOnline',
          Amount: amount,
          PartyA: phone,
          PartyB: DARAJA_SHORTCODE,
          PhoneNumber: phone,
          CallBackURL: DARAJA_CALLBACK_URL,
          AccountReference: `ReceiptIQ-${tier}`,
          TransactionDesc: `ReceiptIQ ${tier} subscription`,
        }),
      }
    );
    const stkData = await stkResp.json();

    if (stkData.ResponseCode !== '0') {
      return new Response(
        JSON.stringify({ error: stkData.ResponseDescription ?? 'STK Push failed' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    const checkoutRequestId = stkData.CheckoutRequestID;

    // Record pending transaction
    await supabase.from('payment_transactions').insert({
      user_id: user.id,
      amount: Number(amount),
      currency: currency ?? 'KES',
      provider: 'mpesa',
      status: 'pending',
      tier,
      provider_ref: checkoutRequestId,
      metadata: { phone, timestamp },
    });

    return new Response(JSON.stringify({ checkoutRequestId }), {
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
