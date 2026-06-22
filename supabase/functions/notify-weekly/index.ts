/**
 * notify-weekly — Supabase Edge Function (cron)
 *
 * Sends a personalised weekly spending summary push notification to every
 * registered (non-anonymous) user who has scanned at least one receipt in
 * the last 7 days.
 *
 * Schedule: Every Sunday at 19:00 EAT (16:00 UTC)
 * Supabase cron expression: "0 16 * * 0"
 *
 * Required env vars (set in Supabase dashboard → Settings → Edge Functions):
 *   ONESIGNAL_APP_ID   — OneSignal App ID
 *   ONESIGNAL_REST_KEY — OneSignal REST API key
 */

import { serve } from 'https://deno.land/std@0.224.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const ONESIGNAL_API = 'https://onesignal.com/api/v1/notifications';

serve(async (_req) => {
  const appId   = Deno.env.get('ONESIGNAL_APP_ID')!;
  const restKey = Deno.env.get('ONESIGNAL_REST_KEY')!;

  if (!appId || !restKey) {
    return new Response('OneSignal env vars not set', { status: 500 });
  }

  // ── Query last 7 days of receipt data grouped by user ──────────────────────
  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  );

  const since = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString();

  const { data: rows, error } = await supabase
    .from('receipts')
    .select('user_id, total_amount, currency')
    .gte('date', since)
    .not('user_id', 'is', null);

  if (error) {
    return new Response(`DB error: ${error.message}`, { status: 500 });
  }

  // Aggregate total spend per user.
  const totals = new Map<string, { amount: number; currency: string; count: number }>();
  for (const row of rows ?? []) {
    const existing = totals.get(row.user_id) ?? { amount: 0, currency: row.currency ?? 'KES', count: 0 };
    existing.amount += Number(row.total_amount ?? 0);
    existing.count  += 1;
    totals.set(row.user_id, existing);
  }

  if (totals.size === 0) {
    return new Response('No active users this week', { status: 200 });
  }

  // ── Send one notification per user via OneSignal external_id targeting ─────
  const results: { userId: string; status: number }[] = [];

  for (const [userId, { amount, currency, count }] of totals) {
    const formatted = new Intl.NumberFormat('en-KE', {
      style: 'currency',
      currency,
      maximumFractionDigits: 0,
    }).format(amount);

    const body = {
      app_id: appId,
      include_aliases: { external_id: [userId] },
      target_channel: 'push',
      headings: { en: '📊 Your weekly spending summary' },
      contents: {
        en: `You spent ${formatted} across ${count} receipt${count !== 1 ? 's' : ''} this week. Tap to see the breakdown.`,
      },
      data: { route: '/dashboard' },
      android_channel_id: 'weekly_digest',
    };

    const res = await fetch(ONESIGNAL_API, {
      method: 'POST',
      headers: {
        'Authorization': `Key ${restKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(body),
    });

    results.push({ userId, status: res.status });
  }

  return new Response(JSON.stringify({ sent: results.length, results }), {
    headers: { 'Content-Type': 'application/json' },
    status: 200,
  });
});
