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
    if (!orderTrackingId || !orderMerchantRef) return new Response('missing params', { status: 400 });

    const tokenResp = await fetch(`${PESAPAL_BASE}/api/Auth/RequestToken`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
      body: JSON.stringify({ consumer_key: PESAPAL_CONSUMER_KEY, consumer_secret: PESAPAL_CONSUMER_SECRET }),
    });
    const { token } = await tokenResp.json();

    const statusResp = await fetch(
      `${PESAPAL_BASE}/api/Transactions/GetTransactionStatus?orderTrackingId=${orderTrackingId}`,
      { headers: { Authorization: `Bearer ${token}`, Accept: 'application/json' } }
    );
    const statusData = await statusResp.json();
    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);

    if (statusData.payment_status_description !== 'Completed') {
      await supabase.from('payment_transactions')
        .update({ status: 'failed', metadata: statusData }).eq('provider_ref', orderMerchantRef);
      return new Response('ok', { status: 200 });
    }

    // Try to match by direct provider_ref first; for recurring charges Pesapal
    // may use a new merchant reference, so also look for the subscription tracking id.
    const { data: tx } = await supabase.from('payment_transactions')
      .select('user_id, tier, metadata')
      .or(`provider_ref.eq.${orderMerchantRef},metadata->>order_tracking_id.eq.${orderTrackingId}`)
      .order('created_at', { ascending: false })
      .limit(1)
      .single();

    if (!tx) return new Response('tx not found', { status: 404 });

    const billingPeriod: string = tx.metadata?.billing_period ?? 'monthly';
    const isYearly = billingPeriod === 'yearly';
    const isUpgrade = tx.metadata?.is_upgrade === true;

    // Calculate expiry date
    let expiresAt: Date;
    if (isUpgrade) {
      // For upgrades, extend from existing subscription expiry
      const { data: existingSub } = await supabase
        .from('user_subscriptions')
        .select('expires_at, pesapal_subscription_id')
        .eq('user_id', tx.user_id)
        .single();
      
      if (existingSub && existingSub.expires_at) {
        expiresAt = new Date(existingSub.expires_at);
        
        // Cancel old Pesapal subscription if subscription_id exists
        if (existingSub.pesapal_subscription_id) {
          try {
            await fetch(`${PESAPAL_BASE}/api/Subscription/CancelSubscription`, {
              method: 'POST',
              headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json', Accept: 'application/json' },
              body: JSON.stringify({ subscription_id: existingSub.pesapal_subscription_id }),
            });
          } catch (cancelErr) {
            console.error('Failed to cancel old Pesapal subscription:', cancelErr);
            // Don't fail the upgrade if cancellation fails
          }
        }
      } else {
        // Fallback to NOW if no existing subscription found
        expiresAt = new Date();
      }
    } else {
      // New subscription: extend from NOW
      expiresAt = new Date();
    }

    // Add the billing period
    if (isYearly) {
      expiresAt.setFullYear(expiresAt.getFullYear() + 1);
    } else {
      expiresAt.setDate(expiresAt.getDate() + 30);
    }

    // Pesapal may return a subscription_id for recurring billing
    const pesapalSubscriptionId: string | null =
      statusData.subscription_id ?? orderMerchantRef ?? null;

    await supabase.from('user_subscriptions').upsert({
      user_id: tx.user_id,
      tier: tx.tier,
      payment_provider: 'pesapal',
      expires_at: expiresAt.toISOString(),
      auto_renew: true,
      billing_period: billingPeriod,
      pesapal_subscription_id: pesapalSubscriptionId,
      updated_at: new Date().toISOString(),
    });

    await supabase.from('payment_transactions')
      .update({ status: 'confirmed', metadata: { ...statusData, billing_period: billingPeriod } })
      .eq('provider_ref', orderMerchantRef);

    return new Response('ok', { status: 200 });
  } catch (err) {
    return new Response(JSON.stringify({ error: String(err) }), {
      status: 500, headers: { 'Content-Type': 'application/json' },
    });
  }
});
