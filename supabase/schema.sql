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
  amount      numeric not null default 0
);

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
