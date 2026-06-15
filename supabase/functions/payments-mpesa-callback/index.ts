import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

serve(async (req) => {
  try {
    const body = await req.json();
    const callback = body?.Body?.stkCallback;
    if (!callback) return new Response('ok', { status: 200 });

    const checkoutRequestId: string = callback.CheckoutRequestID;
    const resultCode: number = callback.ResultCode;
    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);

    if (resultCode !== 0) {
      await supabase.from('payment_transactions')
        .update({ status: 'failed', metadata: callback })
        .eq('provider_ref', checkoutRequestId);
      return new Response('ok', { status: 200 });
    }

    const { data: tx } = await supabase.from('payment_transactions')
      .select('user_id, tier').eq('provider_ref', checkoutRequestId).single();
    if (!tx) return new Response('transaction not found', { status: 404 });

    const expiresAt = new Date();
    expiresAt.setDate(expiresAt.getDate() + 30);

    await supabase.from('user_subscriptions').upsert({
      user_id: tx.user_id, tier: tx.tier, payment_provider: 'mpesa',
      expires_at: expiresAt.toISOString(), auto_renew: true,
      updated_at: new Date().toISOString(),
    });

    await supabase.from('payment_transactions')
      .update({ status: 'confirmed', metadata: callback })
      .eq('provider_ref', checkoutRequestId);

    return new Response('ok', { status: 200 });
  } catch (err) {
    return new Response(JSON.stringify({ error: String(err) }), {
      status: 500, headers: { 'Content-Type': 'application/json' },
    });
  }
});
