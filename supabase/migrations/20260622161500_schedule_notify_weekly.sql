-- Schedule the weekly notification Edge Function via pg_cron + pg_net.
-- Runs every Sunday at 16:00 UTC (19:00 EAT / East Africa Time).

-- Enable required extensions if not already active.
create extension if not exists pg_cron  with schema extensions;
create extension if not exists pg_net   with schema extensions;

-- Remove any existing schedule with the same name (idempotent).
select cron.unschedule('notify-weekly') where exists (
  select 1 from cron.job where jobname = 'notify-weekly'
);

-- Create the weekly schedule.
select cron.schedule(
  'notify-weekly',                       -- job name
  '0 16 * * 0',                          -- every Sunday 16:00 UTC (19:00 EAT)
  $$
  select net.http_post(
    url     := 'https://rrmfxijgcnkjcsmmjkuz.supabase.co/functions/v1/notify-weekly',
    headers := jsonb_build_object(
      'Authorization', 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJybWZ4aWpnY25ramNzbW1qa3V6Iiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc4MTA3NTI1MCwiZXhwIjoyMDk2NjUxMjUwfQ.cFDLD6dlMwlhVRq_LODFplJ0LuzoftksZb5yKFo7ujw',
      'Content-Type', 'application/json'
    ),
    body    := '{}'::jsonb
  ) as request_id;
  $$
);
