alter table public.user_subscriptions
  add column if not exists billing_period          text not null default 'monthly';

alter table public.user_subscriptions
  add column if not exists pesapal_subscription_id text;
