import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const FW_SECRET_HASH = Deno.env.get('FLUTTERWAVE_SECRET_HASH')!;
const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

serve(async (req) => {
  try {
    // Verify Flutterwave webhook signature
    const hash = req.headers.get('verif-hash');
    if (hash !== FW_SECRET_HASH) {
      return new Response('Unauthorized', { status: 401 });
    }

    const payload = await req.json();
    if (payload.event !== 'charge.completed' || payload.data?.status !== 'successful') {
      return new Response('ok', { status: 200 });
    }

    const meta = payload.data?.meta ?? {};
    const userId: string = meta.user_id;
    const tier: string = meta.tier ?? 'starter';
    const txRef: string = meta.tx_ref ?? payload.data?.tx_ref;

    if (!userId) {
      return new Response('missing user_id in meta', { status: 400 });
    }

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);

    const expiresAt = new Date();
    expiresAt.setDate(expiresAt.getDate() + 30);

    await supabase.from('user_subscriptions').upsert({
      user_id: userId,
      tier,
      payment_provider: 'flutterwave',
      expires_at: expiresAt.toISOString(),
      auto_renew: false,
      updated_at: new Date().toISOString(),
    });

    await supabase
      .from('payment_transactions')
      .update({ status: 'confirmed' })
      .eq('provider_ref', txRef);

    return new Response('ok', { status: 200 });
  } catch (err) {
    return new Response(JSON.stringify({ error: String(err) }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    });
  }
});
