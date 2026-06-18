
-- ───────────────────────────────────────────────────────────────────────────
-- Storage bucket for temporary OCR uploads (auto-deleted by scan/ocr function)
-- ───────────────────────────────────────────────────────────────────────────
insert into storage.buckets (id, name, public)
values ('ocr-temp', 'ocr-temp', false)
on conflict (id) do nothing;

drop policy if exists "ocr_temp_insert_own" on storage.objects;
drop policy if exists "ocr_temp_delete_own" on storage.objects;

create policy "ocr_temp_insert_own" on storage.objects
  for insert with check (
    bucket_id = 'ocr-temp' and (storage.foldername(name))[1] = auth.uid()::text
  );
create policy "ocr_temp_delete_own" on storage.objects
  for delete using (
    bucket_id = 'ocr-temp' and (storage.foldername(name))[1] = auth.uid()::text
  );

-- ───────────────────────────────────────────────────────────────────────────
-- Subscriptions
-- ───────────────────────────────────────────────────────────────────────────

create table if not exists public.user_subscriptions (
  user_id                  uuid primary key references auth.users (id) on delete cascade,
  tier                     text not null default 'free',
  payment_provider         text,
  expires_at               timestamptz,
  auto_renew               boolean not null default false,
  phone_number             text,
  country_code             text,
  provider_ref             text,
  billing_period           text not null default 'monthly',
  pesapal_subscription_id  text,
  updated_at               timestamptz not null default now()
);

alter table public.user_subscriptions
  add column if not exists billing_period          text not null default 'monthly';
alter table public.user_subscriptions
  add column if not exists pesapal_subscription_id text;
-- ReceiptIQ — Supabase schema
-- Run this in the Supabase SQL Editor (Dashboard -> SQL -> New query -> paste -> Run).
-- Safe to re-run: uses IF NOT EXISTS / CREATE OR REPLACE where possible.

-- ───────────────────────────────────────────────────────────────────────────
-- Extensions
-- ───────────────────────────────────────────────────────────────────────────
create extension if not exists "pgcrypto";

-- ───────────────────────────────────────────────────────────────────────────
-- Tables
-- ───────────────────────────────────────────────────────────────────────────

create table if not exists public.businesses (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references auth.users (id) on delete cascade,
  name          text not null default 'My Money',
  base_currency text not null default 'KES',
  created_at    timestamptz not null default now()
);

create table if not exists public.receipts (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null references auth.users (id) on delete cascade,
  business_id    uuid,
  merchant       text not null default 'Unknown',
  date           timestamptz not null default now(),
  total_amount   numeric not null default 0,
  total_currency text not null default 'KES',
  vat_amount     numeric,
  vat_currency   text,
  category       text not null default 'other',
  image_url      text,
  raw_text       text,
  notes          text,
  created_at     timestamptz not null default now()
);

create table if not exists public.line_items (
  id          uuid primary key default gen_random_uuid(),
  receipt_id  uuid not null references public.receipts (id) on delete cascade,
  user_id     uuid not null references auth.users (id) on delete cascade,
  name        text not null default '',
  quantity    numeric not null default 1,
  unit_price  numeric not null default 0,
  amount      numeric not null default 0,
  category    text not null default 'other'
);

alter table public.line_items
  add column if not exists category text not null default 'other';

create table if not exists public.budgets (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references auth.users (id) on delete cascade,
  category      text not null,
  limit_amount  numeric not null default 0,
  currency      text not null default 'KES',
  unique (user_id, category)
);

create index if not exists receipts_user_date_idx on public.receipts (user_id, date desc);
create index if not exists line_items_receipt_idx on public.line_items (receipt_id);

-- ───────────────────────────────────────────────────────────────────────────
-- Row Level Security: each user can only see/modify their own rows
-- ───────────────────────────────────────────────────────────────────────────
alter table public.businesses enable row level security;
alter table public.receipts   enable row level security;
alter table public.line_items enable row level security;
alter table public.budgets    enable row level security;

do $$
declare t text;
begin
  foreach t in array array['businesses','receipts','line_items','budgets'] loop
    execute format('drop policy if exists "owner_all_%1$s" on public.%1$s;', t);
    execute format($f$
      create policy "owner_all_%1$s" on public.%1$s
        for all
        using (user_id = auth.uid())
        with check (user_id = auth.uid());
    $f$, t);
  end loop;
end $$;

-- ───────────────────────────────────────────────────────────────────────────
-- Storage bucket for receipt images (private; users manage their own folder)
-- ───────────────────────────────────────────────────────────────────────────
insert into storage.buckets (id, name, public)
values ('receipts', 'receipts', false)
on conflict (id) do nothing;

drop policy if exists "receipts_read_own" on storage.objects;
drop policy if exists "receipts_write_own" on storage.objects;
drop policy if exists "receipts_update_own" on storage.objects;
drop policy if exists "receipts_delete_own" on storage.objects;

-- Files are stored under "<auth.uid()>/<filename>", so the first path
-- segment must equal the user's id.
create policy "receipts_read_own" on storage.objects
  for select using (
    bucket_id = 'receipts' and (storage.foldername(name))[1] = auth.uid()::text
  );
create policy "receipts_write_own" on storage.objects
  for insert with check (
    bucket_id = 'receipts' and (storage.foldername(name))[1] = auth.uid()::text
  );
create policy "receipts_update_own" on storage.objects
  for update using (
    bucket_id = 'receipts' and (storage.foldername(name))[1] = auth.uid()::text
  );
create policy "receipts_delete_own" on storage.objects
  for delete using (
    bucket_id = 'receipts' and (storage.foldername(name))[1] = auth.uid()::text
  );

create table if not exists public.payment_transactions (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references auth.users (id) on delete cascade,
  amount       numeric not null,
  currency     text not null,
  provider     text not null,
  status       text not null default 'pending',
  tier         text not null,
  provider_ref text,
  metadata     jsonb,
  created_at   timestamptz not null default now()
);

create index if not exists payment_tx_user_idx on public.payment_transactions (user_id, created_at desc);

alter table public.user_subscriptions    enable row level security;
alter table public.payment_transactions  enable row level security;

drop policy if exists "owner_all_user_subscriptions"   on public.user_subscriptions;
drop policy if exists "owner_all_payment_transactions" on public.payment_transactions;

create policy "owner_all_user_subscriptions" on public.user_subscriptions
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy "owner_all_payment_transactions" on public.payment_transactions
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());
