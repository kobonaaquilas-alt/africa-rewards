-- AfriReach initial database schema
-- Run once in the Supabase SQL Editor of a DEDICATED AfriReach project.
-- No payment credentials, service-role keys, or money custody are used here.

create extension if not exists pgcrypto;

create schema if not exists private;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null check (char_length(display_name) between 2 and 90),
  country text not null default 'Togo',
  account_type text not null check (account_type in ('advertiser','creator','participant')),
  phone_number text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.platform_admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

create or replace function private.is_platform_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.platform_admins
    where user_id = (select auth.uid())
  );
$$;

revoke all on function private.is_platform_admin() from public, anon;
grant usage on schema private to authenticated;
grant execute on function private.is_platform_admin() to authenticated;

create table if not exists public.campaigns (
  id uuid primary key default gen_random_uuid(),
  advertiser_id uuid not null references public.profiles(id) on delete restrict,
  title text not null check (char_length(title) between 5 and 120),
  description text not null check (char_length(description) between 20 and 3000),
  campaign_type text not null check (campaign_type in ('ad_discovery','survey','product_test','creator_collaboration')),
  channel text not null default 'AfriReach' check (channel in ('AfriReach','TikTok','Instagram','Facebook','YouTube','WhatsApp','Other')),
  objective text not null,
  country text not null default 'Togo',
  participant_reward numeric(12,2) not null check (participant_reward > 0),
  participant_slots integer not null check (participant_slots between 1 and 100000),
  participant_budget numeric(14,2) generated always as (participant_reward * participant_slots) stored,
  service_fee numeric(14,2) not null check (service_fee >= 0),
  currency text not null default 'XOF' check (currency = 'XOF'),
  start_at timestamptz,
  end_at timestamptz,
  status text not null default 'draft' check (status in ('draft','pending_fee_payment','pending_review','active','paused','completed','rejected','cancelled')),
  rules_acknowledged boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (end_at is null or start_at is null or end_at > start_at)
);

create table if not exists public.platform_fee_payments (
  id uuid primary key default gen_random_uuid(),
  campaign_id uuid not null unique references public.campaigns(id) on delete cascade,
  advertiser_id uuid not null references public.profiles(id) on delete restrict,
  amount numeric(14,2) not null check (amount > 0),
  currency text not null default 'XOF' check (currency = 'XOF'),
  payment_method text not null default 'manual_transfer' check (payment_method = 'manual_transfer'),
  sender_reference text,
  proof_reference text,
  status text not null default 'submitted' check (status in ('submitted','approved','rejected')),
  reviewed_by uuid references public.profiles(id),
  reviewed_at timestamptz,
  review_note text,
  created_at timestamptz not null default now()
);

create table if not exists public.campaign_applications (
  id uuid primary key default gen_random_uuid(),
  campaign_id uuid not null references public.campaigns(id) on delete cascade,
  participant_id uuid not null references public.profiles(id) on delete restrict,
  status text not null default 'applied' check (status in ('applied','accepted','submitted','approved','rejected','withdrawn')),
  submission_note text,
  proof_reference text,
  applied_at timestamptz not null default now(),
  submitted_at timestamptz,
  reviewed_at timestamptz,
  unique (campaign_id, participant_id)
);

create table if not exists public.participant_payouts (
  id uuid primary key default gen_random_uuid(),
  application_id uuid not null unique references public.campaign_applications(id) on delete cascade,
  campaign_id uuid not null references public.campaigns(id) on delete cascade,
  advertiser_id uuid not null references public.profiles(id) on delete restrict,
  participant_id uuid not null references public.profiles(id) on delete restrict,
  amount numeric(12,2) not null check (amount > 0),
  currency text not null default 'XOF' check (currency = 'XOF'),
  payment_method text not null default 'direct_manual_transfer' check (payment_method = 'direct_manual_transfer'),
  advertiser_proof_reference text,
  status text not null default 'awaiting_advertiser_payment' check (status in ('awaiting_advertiser_payment','marked_paid','confirmed_by_participant','disputed')),
  marked_paid_at timestamptz,
  participant_confirmed_at timestamptz,
  dispute_note text,
  created_at timestamptz not null default now()
);

create table if not exists public.admin_audit_log (
  id bigint generated always as identity primary key,
  admin_id uuid not null references auth.users(id),
  action text not null,
  entity_type text not null,
  entity_id uuid,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists campaigns_status_created_idx on public.campaigns(status, created_at desc);
create index if not exists campaigns_advertiser_idx on public.campaigns(advertiser_id, created_at desc);
create index if not exists applications_participant_idx on public.campaign_applications(participant_id, applied_at desc);
create index if not exists applications_campaign_idx on public.campaign_applications(campaign_id, status);
create index if not exists payouts_participant_idx on public.participant_payouts(participant_id, created_at desc);

-- Enable RLS on every exposed table.
alter table public.profiles enable row level security;
alter table public.platform_admins enable row level security;
alter table public.campaigns enable row level security;
alter table public.platform_fee_payments enable row level security;
alter table public.campaign_applications enable row level security;
alter table public.participant_payouts enable row level security;
alter table public.admin_audit_log enable row level security;

-- Profiles: users can read/update their own profile. Account type cannot be changed via the client.
drop policy if exists "profiles_read_self_or_admin" on public.profiles;
create policy "profiles_read_self_or_admin" on public.profiles
for select to authenticated
using ((select auth.uid()) = id or (select private.is_platform_admin()));

drop policy if exists "profiles_insert_self" on public.profiles;
create policy "profiles_insert_self" on public.profiles
for insert to authenticated
with check ((select auth.uid()) = id and account_type in ('participant','creator'));

drop policy if exists "profiles_update_self" on public.profiles;
create policy "profiles_update_self" on public.profiles
for update to authenticated
using ((select auth.uid()) = id)
with check ((select auth.uid()) = id);

drop policy if exists "profiles_admin_update" on public.profiles;
create policy "profiles_admin_update" on public.profiles
for update to authenticated
using ((select private.is_platform_admin()))
with check ((select private.is_platform_admin()));

revoke update on public.profiles from anon, authenticated;
grant update (display_name, country, phone_number, updated_at, account_type) on public.profiles to authenticated;

-- Admin membership is provisioned manually by the project owner in SQL Editor.
drop policy if exists "admins_read_self_or_admin" on public.platform_admins;
create policy "admins_read_self_or_admin" on public.platform_admins
for select to authenticated
using (user_id = (select auth.uid()) or (select private.is_platform_admin()));
revoke insert, update, delete on public.platform_admins from anon, authenticated;

-- Campaigns: active campaigns are discoverable; advertiser sees own; admins see all.
drop policy if exists "campaigns_read_visible" on public.campaigns;
create policy "campaigns_read_visible" on public.campaigns
for select to authenticated
using (status = 'active' or advertiser_id = (select auth.uid()) or (select private.is_platform_admin()));

drop policy if exists "campaigns_insert_advertiser" on public.campaigns;
create policy "campaigns_insert_advertiser" on public.campaigns
for insert to authenticated
with check (
  advertiser_id = (select auth.uid())
  and exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.account_type = 'advertiser')
  and status in ('draft','pending_fee_payment')
);

drop policy if exists "campaigns_update_owner_or_admin" on public.campaigns;
create policy "campaigns_update_owner_or_admin" on public.campaigns
for update to authenticated
using (advertiser_id = (select auth.uid()) or (select private.is_platform_admin()))
with check (
  (advertiser_id = (select auth.uid()) and status in ('draft','pending_fee_payment','cancelled'))
  or (select private.is_platform_admin())
);

-- Service-fee proof: advertiser submits; only admins can approve/reject.
drop policy if exists "fee_payments_read_owner_or_admin" on public.platform_fee_payments;
create policy "fee_payments_read_owner_or_admin" on public.platform_fee_payments
for select to authenticated
using (advertiser_id = (select auth.uid()) or (select private.is_platform_admin()));

drop policy if exists "fee_payments_insert_owner" on public.platform_fee_payments;
create policy "fee_payments_insert_owner" on public.platform_fee_payments
for insert to authenticated
with check (
  advertiser_id = (select auth.uid())
  and exists (select 1 from public.campaigns c where c.id = campaign_id and c.advertiser_id = (select auth.uid()))
  and status = 'submitted'
  and exists (select 1 from public.campaigns c where c.id = campaign_id and c.status = 'pending_fee_payment' and c.service_fee = amount)
);

drop policy if exists "fee_payments_admin_update" on public.platform_fee_payments;
create policy "fee_payments_admin_update" on public.platform_fee_payments
for update to authenticated
using ((select private.is_platform_admin()))
with check ((select private.is_platform_admin()));

-- Applications: participants apply to active campaigns; advertiser/admin reviews.
drop policy if exists "applications_read_parties" on public.campaign_applications;
create policy "applications_read_parties" on public.campaign_applications
for select to authenticated
using (
  participant_id = (select auth.uid())
  or exists (select 1 from public.campaigns c where c.id = campaign_id and c.advertiser_id = (select auth.uid()))
  or (select private.is_platform_admin())
);

drop policy if exists "applications_insert_participant" on public.campaign_applications;
create policy "applications_insert_participant" on public.campaign_applications
for insert to authenticated
with check (
  participant_id = (select auth.uid())
  and exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.account_type in ('participant','creator'))
  and exists (select 1 from public.campaigns c where c.id = campaign_id and c.status = 'active')
  and status = 'applied'
);

drop policy if exists "applications_update_parties" on public.campaign_applications;
create policy "applications_update_parties" on public.campaign_applications
for update to authenticated
using (
  participant_id = (select auth.uid())
  or exists (select 1 from public.campaigns c where c.id = campaign_id and c.advertiser_id = (select auth.uid()))
  or (select private.is_platform_admin())
)
with check (
  (participant_id = (select auth.uid()) and status in ('submitted','withdrawn'))
  or (exists (select 1 from public.campaigns c where c.id = campaign_id and c.advertiser_id = (select auth.uid())) and status in ('accepted','rejected','approved'))
  or (select private.is_platform_admin())
);

-- Payout records: advertiser marks direct transfer; participant confirms or disputes receipt.
drop policy if exists "payouts_read_parties" on public.participant_payouts;
create policy "payouts_read_parties" on public.participant_payouts
for select to authenticated
using (advertiser_id = (select auth.uid()) or participant_id = (select auth.uid()) or (select private.is_platform_admin()));

drop policy if exists "payouts_insert_advertiser" on public.participant_payouts;
create policy "payouts_insert_advertiser" on public.participant_payouts
for insert to authenticated
with check (
  advertiser_id = (select auth.uid())
  and exists (select 1 from public.campaigns c where c.id = campaign_id and c.advertiser_id = (select auth.uid()))
  and exists (select 1 from public.campaign_applications a where a.id = application_id and a.status = 'approved')
  and exists (select 1 from public.campaigns c where c.id = campaign_id and c.participant_reward = amount)
);

drop policy if exists "payouts_update_parties" on public.participant_payouts;
drop policy if exists "payouts_update_advertiser" on public.participant_payouts;
drop policy if exists "payouts_update_participant" on public.participant_payouts;
drop policy if exists "payouts_update_admin" on public.participant_payouts;
create policy "payouts_update_advertiser" on public.participant_payouts
for update to authenticated
using (advertiser_id = (select auth.uid()))
with check (advertiser_id = (select auth.uid()) and status = 'marked_paid');
create policy "payouts_update_participant" on public.participant_payouts
for update to authenticated
using (participant_id = (select auth.uid()) and status = 'marked_paid')
with check (participant_id = (select auth.uid()) and status in ('confirmed_by_participant','disputed'));
create policy "payouts_update_admin" on public.participant_payouts
for update to authenticated
using ((select private.is_platform_admin()))
with check ((select private.is_platform_admin()));

-- Audit log is visible only to platform admins and cannot be written by normal clients.
drop policy if exists "audit_admin_read" on public.admin_audit_log;
create policy "audit_admin_read" on public.admin_audit_log
for select to authenticated
using ((select private.is_platform_admin()));
revoke insert, update, delete on public.admin_audit_log from anon, authenticated;

-- Restrict default table privileges; explicit grants are required for Data API use.
grant select, insert, update on public.profiles to authenticated;
grant select, insert, update on public.campaigns to authenticated;
grant select, insert, update on public.platform_fee_payments to authenticated;
grant select, insert, update on public.campaign_applications to authenticated;
grant select, insert on public.participant_payouts to authenticated;
grant update (status, advertiser_proof_reference, marked_paid_at, participant_confirmed_at, dispute_note) on public.participant_payouts to authenticated;
grant select on public.platform_admins to authenticated;
grant select on public.admin_audit_log to authenticated;
