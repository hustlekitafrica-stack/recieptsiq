import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const DARAJA_CONSUMER_KEY = Deno.env.get('DARAJA_CONSUMER_KEY')!;
const DARAJA_CONSUMER_SECRET = Deno.env.get('DARAJA_CONSUMER_SECRET')!;
const DARAJA_SHORTCODE = Deno.env.get('DARAJA_SHORTCODE')!;
const DARAJA_PASSKEY = Deno.env.get('DARAJA_PASSKEY')!;
const DARAJA_CALLBACK_URL = Deno.env.get('DARAJA_CALLBACK_URL')!;
const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

const TIER_AMOUNTS: Record<string, number> = { starter: 250, pro: 1000 };

serve(async (_req) => {
  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);

  // Find subscriptions expiring within the next 24 hours with auto_renew=true
  const renewBefore = new Date();
  renewBefore.setHours(renewBefore.getHours() + 24);

  const { data: subs, error } = await supabase
    .from('user_subscriptions')
    .select('user_id, tier, phone_number')
    .eq('payment_provider', 'mpesa')
    .eq('auto_renew', true)
    .lte('expires_at', renewBefore.toISOString())
    .gt('expires_at', new Date().toISOString());

  if (error) {
    return new Response(JSON.stringify({ error: error.message }), { status: 500 });
  }

  if (!subs || subs.length === 0) {
    return new Response(JSON.stringify({ renewed: 0 }), { status: 200 });
  }

  // Get Daraja token
  const tokenResp = await fetch(
    'https://api.safaricom.co.ke/oauth/v1/generate?grant_type=client_credentials',
    {
      headers: {
        Authorization: 'Basic ' + btoa(`${DARAJA_CONSUMER_KEY}:${DARAJA_CONSUMER_SECRET}`),
      },
    }
  );
  const { access_token } = await tokenResp.json();

  let renewed = 0;
  for (const sub of subs) {
    if (!sub.phone_number) continue;
    const amount = TIER_AMOUNTS[sub.tier] ?? TIER_AMOUNTS['starter'];
    const timestamp = new Date().toISOString().replace(/\D/g, '').slice(0, 14);
    const password = btoa(`${DARAJA_SHORTCODE}${DARAJA_PASSKEY}${timestamp}`);

    try {
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
            PartyA: sub.phone_number,
            PartyB: DARAJA_SHORTCODE,
            PhoneNumber: sub.phone_number,
            CallBackURL: DARAJA_CALLBACK_URL,
            AccountReference: `ReceiptIQ-renew-${sub.tier}`,
            TransactionDesc: `ReceiptIQ ${sub.tier} renewal`,
          }),
        }
      );
      const stkData = await stkResp.json();
      if (stkData.ResponseCode === '0') {
        // Record pending renewal transaction
        await supabase.from('payment_transactions').insert({
          user_id: sub.user_id,
          amount,
          currency: 'KES',
          provider: 'mpesa',
          status: 'pending',
          tier: sub.tier,
          provider_ref: stkData.CheckoutRequestID,
          metadata: { renewal: true },
        });
        renewed++;
      }
    } catch (_e) {
      // Continue with other subs even if one fails
    }
  }

  return new Response(JSON.stringify({ renewed }), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
  });
});
