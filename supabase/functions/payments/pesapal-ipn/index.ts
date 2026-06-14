import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const PESAPAL_CONSUMER_KEY = Deno.env.get('PESAPAL_CONSUMER_KEY')!;
const PESAPAL_CONSUMER_SECRET = Deno.env.get('PESAPAL_CONSUMER_SECRET')!;
const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

const PESAPAL_BASE = 'https://pay.pesapal.com/v3';

serve(async (req) => {
  try {
    const url = new URL(req.url);
    const orderTrackingId = url.searchParams.get('OrderTrackingId');
    const orderMerchantRef = url.searchParams.get('OrderMerchantReference');

    if (!orderTrackingId || !orderMerchantRef) {
      return new Response('missing params', { status: 400 });
    }

    // Get fresh Pesapal token
    const tokenResp = await fetch(`${PESAPAL_BASE}/api/Auth/RequestToken`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
      body: JSON.stringify({
        consumer_key: PESAPAL_CONSUMER_KEY,
        consumer_secret: PESAPAL_CONSUMER_SECRET,
      }),
    });
    const { token } = await tokenResp.json();

    // Query transaction status
    const statusResp = await fetch(
      `${PESAPAL_BASE}/api/Transactions/GetTransactionStatus?orderTrackingId=${orderTrackingId}`,
      {
        headers: { Authorization: `Bearer ${token}`, Accept: 'application/json' },
      }
    );
    const statusData = await statusResp.json();

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);

    if (statusData.payment_status_description !== 'Completed') {
      await supabase
        .from('payment_transactions')
        .update({ status: 'failed', metadata: statusData })
        .eq('provider_ref', orderMerchantRef);
      return new Response('ok', { status: 200 });
    }

    // Find the pending transaction
    const { data: tx } = await supabase
      .from('payment_transactions')
      .select('user_id, tier')
      .eq('provider_ref', orderMerchantRef)
      .single();

    if (!tx) return new Response('tx not found', { status: 404 });

    const expiresAt = new Date();
    expiresAt.setDate(expiresAt.getDate() + 30);

    await supabase.from('user_subscriptions').upsert({
      user_id: tx.user_id,
      tier: tx.tier,
      payment_provider: 'pesapal',
      expires_at: expiresAt.toISOString(),
      auto_renew: false,
      updated_at: new Date().toISOString(),
    });

    await supabase
      .from('payment_transactions')
      .update({ status: 'confirmed', metadata: statusData })
      .eq('provider_ref', orderMerchantRef);

    return new Response('ok', { status: 200 });
  } catch (err) {
    return new Response(JSON.stringify({ error: String(err) }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    });
  }
});
