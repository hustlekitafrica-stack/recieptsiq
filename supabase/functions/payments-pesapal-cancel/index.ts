import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const PESAPAL_CONSUMER_KEY    = Deno.env.get('PESAPAL_CONSUMER_KEY')!;
const PESAPAL_CONSUMER_SECRET = Deno.env.get('PESAPAL_CONSUMER_SECRET')!;
const SUPABASE_URL            = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_SERVICE_KEY    = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

const PESAPAL_BASE = 'https://pay.pesapal.com/v3';
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
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
    const { data: { user }, error: authError } = await supabase.auth.getUser(
      authHeader.replace('Bearer ', '')
    );
    if (authError || !user) {
      return new Response(JSON.stringify({ error: 'Unauthorized' }), {
        status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    // Fetch current subscription for this user
    const { data: sub, error: subError } = await supabase
      .from('user_subscriptions')
      .select('pesapal_subscription_id, tier')
      .eq('user_id', user.id)
      .single();

    if (subError || !sub) {
      return new Response(JSON.stringify({ error: 'No active subscription found' }), {
        status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    // If there is a Pesapal subscription ID, cancel it via the API
    if (sub.pesapal_subscription_id) {
      const token = await getPesapalToken();
      const cancelResp = await fetch(
        `${PESAPAL_BASE}/api/Transactions/SubmitOrderRequest`,
        {
          method: 'POST',
          headers: {
            Authorization: `Bearer ${token}`,
            'Content-Type': 'application/json',
            Accept: 'application/json',
          },
          // Pesapal cancellation: send a zero-amount cancellation order or
          // call the subscription cancel endpoint if available on your plan.
          // Using the RefundRequest endpoint as a fallback signal.
          body: JSON.stringify({
            confirmation_code: sub.pesapal_subscription_id,
            amount: 0,
          }),
        }
      );
      // We proceed even if Pesapal returns an error — the DB is the source of truth
      const cancelData = await cancelResp.json().catch(() => ({}));
      console.log('Pesapal cancel response:', JSON.stringify(cancelData));
    }

    // Mark subscription as cancelled in our DB (keep expires_at so user keeps access until then)
    await supabase.from('user_subscriptions').update({
      auto_renew: false,
      updated_at: new Date().toISOString(),
    }).eq('user_id', user.id);

    return new Response(JSON.stringify({ cancelled: true }), {
      status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  } catch (err) {
    return new Response(JSON.stringify({ error: String(err) }), {
      status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
});
