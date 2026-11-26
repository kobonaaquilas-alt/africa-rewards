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
  service_fee numeric(14,2) not null check (service_fee >= 100),
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
with check ((select auth.uid()) = id and account_type in ('participant','creator'));

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
  and status = 'draft'
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
  and exists (select 1 from public.campaign_applications a where a.id = application_id and a.campaign_id = participant_payouts.campaign_id and a.participant_id = participant_payouts.participant_id and a.status = 'approved')
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


-- Defense in depth: RLS controls rows; this trigger also protects sensitive columns.
create or replace function private.guard_business_updates()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  actor uuid := (select auth.uid());
  admin boolean := (select private.is_platform_admin());
  campaign_owner uuid;
begin
  if admin then
    return new;
  end if;

  if tg_table_name = 'profiles' then
    if new.id is distinct from old.id
      or new.account_type is distinct from old.account_type
      or new.created_at is distinct from old.created_at then
      raise exception 'Profile identity and account type are immutable by the user';
    end if;
    new.updated_at := now();
    return new;
  elsif tg_table_name = 'campaigns' then
    if old.advertiser_id <> actor
      or new.id is distinct from old.id
      or new.advertiser_id is distinct from old.advertiser_id
      or new.participant_budget is distinct from old.participant_budget
      or new.service_fee is distinct from old.service_fee
      or new.currency is distinct from old.currency
      or new.created_at is distinct from old.created_at then
      raise exception 'Campaign contains fields that the advertiser cannot change';
    end if;
    if old.status not in ('draft','pending_fee_payment')
      or new.status not in ('draft','pending_fee_payment','cancelled') then
      raise exception 'This campaign can no longer be edited by the advertiser';
    end if;
    new.updated_at := now();
    return new;
  elsif tg_table_name = 'platform_fee_payments' then
    raise exception 'Only platform administrators can review service-fee payments';
  elsif tg_table_name = 'campaign_applications' then
    if new.id is distinct from old.id
      or new.campaign_id is distinct from old.campaign_id
      or new.participant_id is distinct from old.participant_id
      or new.applied_at is distinct from old.applied_at then
      raise exception 'Application identity fields are immutable';
    end if;
    select c.advertiser_id into campaign_owner
      from public.campaigns c where c.id = old.campaign_id;
    if old.participant_id = actor then
      if new.status not in ('submitted','withdrawn')
        or new.reviewed_at is distinct from old.reviewed_at then
        raise exception 'Participants may only submit proof or withdraw';
      end if;
    elsif campaign_owner = actor then
      if new.status not in ('accepted','rejected','approved')
        or new.submission_note is distinct from old.submission_note
        or new.proof_reference is distinct from old.proof_reference
        or new.submitted_at is distinct from old.submitted_at then
        raise exception 'Advertisers may only review applications';
      end if;
    else
      raise exception 'Not authorized to update this application';
    end if;
    return new;
  elsif tg_table_name = 'participant_payouts' then
    if new.id is distinct from old.id
      or new.application_id is distinct from old.application_id
      or new.campaign_id is distinct from old.campaign_id
      or new.advertiser_id is distinct from old.advertiser_id
      or new.participant_id is distinct from old.participant_id
      or new.amount is distinct from old.amount
      or new.currency is distinct from old.currency
      or new.payment_method is distinct from old.payment_method
      or new.created_at is distinct from old.created_at then
      raise exception 'Payout identity and amount fields are immutable';
    end if;
    if old.advertiser_id = actor then
      if new.status <> 'marked_paid'
        or new.participant_confirmed_at is distinct from old.participant_confirmed_at
        or new.dispute_note is distinct from old.dispute_note then
        raise exception 'Advertisers may only mark a direct transfer as paid';
      end if;
    elsif old.participant_id = actor then
      if old.status <> 'marked_paid'
        or new.status not in ('confirmed_by_participant','disputed')
        or new.advertiser_proof_reference is distinct from old.advertiser_proof_reference
        or new.marked_paid_at is distinct from old.marked_paid_at then
        raise exception 'Participants may only confirm or dispute a marked payment';
      end if;
    else
      raise exception 'Not authorized to update this payout';
    end if;
    return new;
  end if;

  raise exception 'Unsupported update target';
end;
$$;

revoke all on function private.guard_business_updates() from public, anon, authenticated;

drop trigger if exists guard_profiles_updates on public.profiles;
create trigger guard_profiles_updates before update on public.profiles
for each row execute function private.guard_business_updates();

drop trigger if exists guard_campaigns_updates on public.campaigns;
create trigger guard_campaigns_updates before update on public.campaigns
for each row execute function private.guard_business_updates();

drop trigger if exists guard_fee_payment_updates on public.platform_fee_payments;
create trigger guard_fee_payment_updates before update on public.platform_fee_payments
for each row execute function private.guard_business_updates();

drop trigger if exists guard_application_updates on public.campaign_applications;
create trigger guard_application_updates before update on public.campaign_applications
for each row execute function private.guard_business_updates();

drop trigger if exists guard_payout_updates on public.participant_payouts;
create trigger guard_payout_updates before update on public.participant_payouts
for each row execute function private.guard_business_updates();

-- Advertisers can only edit campaign content and scheduling, never identity or fee fields.
revoke update on public.campaigns from anon, authenticated;
grant update (title, description, objective, country, participant_reward, participant_slots, start_at, end_at, status, rules_acknowledged, updated_at) on public.campaigns to authenticated;

-- Only admins can update fee-review records; normal users can submit proof once.
revoke update on public.platform_fee_payments from anon, authenticated;
grant update (status, reviewed_by, reviewed_at, review_note) on public.platform_fee_payments to authenticated;

-- Applications have narrowly scoped editable fields; trigger checks who may change them.
revoke update on public.campaign_applications from anon, authenticated;
grant update (status, submission_note, proof_reference, submitted_at, reviewed_at) on public.campaign_applications to authenticated;


-- Calculate the platform service fee on the database, never from a browser-supplied amount.
-- Pricing for the pilot: 10% of the participant budget, minimum 100 XOF.
create or replace function private.set_campaign_service_fee()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    new.status := 'draft';
    new.service_fee := greatest(100::numeric, ceil((new.participant_reward * new.participant_slots) * 0.10));
    return new;
  end if;

  if new.participant_reward is distinct from old.participant_reward
    or new.participant_slots is distinct from old.participant_slots then
    if old.status <> 'draft' then
      raise exception 'Campaign budget and reward are locked after draft';
    end if;
    new.service_fee := greatest(100::numeric, ceil((new.participant_reward * new.participant_slots) * 0.10));
  end if;
  return new;
end;
$$;

revoke all on function private.set_campaign_service_fee() from public, anon, authenticated;
drop trigger if exists set_campaign_service_fee on public.campaigns;
create trigger set_campaign_service_fee
before insert or update on public.campaigns
for each row execute function private.set_campaign_service_fee();

-- Performance indexes for foreign-key lookups.
create index if not exists admin_audit_log_admin_id_idx on public.admin_audit_log(admin_id);
create index if not exists participant_payouts_advertiser_id_idx on public.participant_payouts(advertiser_id);
create index if not exists participant_payouts_campaign_id_idx on public.participant_payouts(campaign_id);
create index if not exists platform_fee_payments_advertiser_id_idx on public.platform_fee_payments(advertiser_id);
create index if not exists platform_fee_payments_reviewed_by_idx on public.platform_fee_payments(reviewed_by);

-- Consolidate update policies to avoid redundant permissive policy evaluation.
drop policy if exists "profiles_update_self" on public.profiles;
drop policy if exists "profiles_admin_update" on public.profiles;
create policy "profiles_update_self_or_admin" on public.profiles
for update to authenticated
using ((select auth.uid()) = id or (select private.is_platform_admin()))
with check (
  (select private.is_platform_admin())
  or ((select auth.uid()) = id and account_type in ('participant','creator'))
);

drop policy if exists "payouts_update_advertiser" on public.participant_payouts;
drop policy if exists "payouts_update_participant" on public.participant_payouts;
drop policy if exists "payouts_update_admin" on public.participant_payouts;
create policy "payouts_update_parties_or_admin" on public.participant_payouts
for update to authenticated
using (
  (select private.is_platform_admin())
  or advertiser_id = (select auth.uid())
  or (participant_id = (select auth.uid()) and status = 'marked_paid')
)
with check (
  (select private.is_platform_admin())
  or (advertiser_id = (select auth.uid()) and status = 'marked_paid')
  or (participant_id = (select auth.uid()) and status in ('confirmed_by_participant','disputed'))
);



-- Keep the campaign fee and status transitions controlled by the database.
create or replace function private.set_campaign_service_fee()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    new.status := 'draft';
    new.service_fee := greatest(100::numeric, ceil((new.participant_reward * new.participant_slots) * 0.10));
    return new;
  end if;
  if new.participant_reward is distinct from old.participant_reward
    or new.participant_slots is distinct from old.participant_slots then
    if old.status <> 'draft' then
      raise exception 'Campaign budget and reward are locked after draft';
    end if;
    new.service_fee := greatest(100::numeric, ceil((new.participant_reward * new.participant_slots) * 0.10));
  end if;
  if new.status = 'pending_review' and old.status is distinct from 'pending_review'
    and not exists (select 1 from public.platform_fee_payments fp where fp.campaign_id = new.id and fp.status = 'approved') then
    raise exception 'An approved service-fee payment is required before review';
  end if;
  if new.status = 'active' and old.status is distinct from 'active' then
    if old.status not in ('pending_review','paused')
      or not exists (select 1 from public.platform_fee_payments fp where fp.campaign_id = new.id and fp.status = 'approved') then
      raise exception 'Only a reviewed campaign with approved service fees can be activated';
    end if;
  end if;
  return new;
end;
$$;

create or replace function private.guard_business_updates()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  actor uuid := (select auth.uid());
  admin boolean := (select private.is_platform_admin());
  campaign_owner uuid;
begin
  if admin then return new; end if;
  if tg_table_name = 'profiles' then
    if new.id is distinct from old.id or new.account_type is distinct from old.account_type or new.created_at is distinct from old.created_at then
      raise exception 'Profile identity and account type are immutable by the user';
    end if;
    new.updated_at := now();
    return new;
  elsif tg_table_name = 'campaigns' then
    if old.advertiser_id <> actor or new.id is distinct from old.id or new.advertiser_id is distinct from old.advertiser_id
      or new.participant_budget is distinct from old.participant_budget or new.service_fee is distinct from old.service_fee
      or new.currency is distinct from old.currency or new.created_at is distinct from old.created_at then
      raise exception 'Campaign contains fields that the advertiser cannot change';
    end if;
    if old.status not in ('draft','pending_fee_payment') or new.status not in ('draft','pending_fee_payment','cancelled') then
      raise exception 'This campaign can no longer be edited by the advertiser';
    end if;
    new.updated_at := now();
    return new;
  elsif tg_table_name = 'platform_fee_payments' then
    raise exception 'Only platform administrators can review service-fee payments';
  elsif tg_table_name = 'campaign_applications' then
    if new.id is distinct from old.id or new.campaign_id is distinct from old.campaign_id
      or new.participant_id is distinct from old.participant_id or new.applied_at is distinct from old.applied_at then
      raise exception 'Application identity fields are immutable';
    end if;
    select c.advertiser_id into campaign_owner from public.campaigns c where c.id = old.campaign_id;
    if old.participant_id = actor then
      if new.status = 'submitted' then
        if old.status <> 'accepted' or new.proof_reference is null or new.submitted_at is null
          or not exists (select 1 from storage.objects o where o.bucket_id = 'afriareach-proofs'
            and o.name = new.proof_reference and (storage.foldername(o.name))[1] = actor::text
            and (storage.foldername(o.name))[2] = old.id::text) then
          raise exception 'A valid private proof is required after acceptance';
        end if;
      elsif new.status = 'withdrawn' then
        if old.status not in ('applied','accepted') or new.proof_reference is distinct from old.proof_reference
          or new.submission_note is distinct from old.submission_note or new.submitted_at is distinct from old.submitted_at then
          raise exception 'This application cannot be withdrawn now';
        end if;
      else
        raise exception 'Participants may only submit proof or withdraw';
      end if;
      if new.reviewed_at is distinct from old.reviewed_at then raise exception 'Participants cannot set review timestamps'; end if;
    elsif campaign_owner = actor then
      if not ((old.status = 'applied' and new.status in ('accepted','rejected'))
        or (old.status = 'submitted' and new.status in ('approved','rejected')))
        or new.submission_note is distinct from old.submission_note
        or new.proof_reference is distinct from old.proof_reference
        or new.submitted_at is distinct from old.submitted_at then
        raise exception 'Advertisers may only review valid application states';
      end if;
    else
      raise exception 'Not authorized to update this application';
    end if;
    return new;
  elsif tg_table_name = 'participant_payouts' then
    if new.id is distinct from old.id or new.application_id is distinct from old.application_id
      or new.campaign_id is distinct from old.campaign_id or new.advertiser_id is distinct from old.advertiser_id
      or new.participant_id is distinct from old.participant_id or new.amount is distinct from old.amount
      or new.currency is distinct from old.currency or new.payment_method is distinct from old.payment_method
      or new.created_at is distinct from old.created_at then
      raise exception 'Payout identity and amount fields are immutable';
    end if;
    if old.advertiser_id = actor then
      if old.status <> 'awaiting_advertiser_payment' or new.status <> 'marked_paid'
        or new.participant_confirmed_at is distinct from old.participant_confirmed_at
        or new.dispute_note is distinct from old.dispute_note
        or new.advertiser_proof_reference is distinct from old.advertiser_proof_reference then
        raise exception 'Advertisers may only mark an unpaid direct transfer as paid';
      end if;
    elsif old.participant_id = actor then
      if old.status <> 'marked_paid' or new.status not in ('confirmed_by_participant','disputed')
        or new.advertiser_proof_reference is distinct from old.advertiser_proof_reference
        or new.marked_paid_at is distinct from old.marked_paid_at then
        raise exception 'Participants may only confirm or dispute a marked payment';
      end if;
    else
      raise exception 'Not authorized to update this payout';
    end if;
    return new;
  end if;
  raise exception 'Unsupported update target';
end;
$$;

-- Auth signup creates a restricted participant/creator profile automatically.
create or replace function private.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare chosen_name text; chosen_type text;
begin
  chosen_name := left(coalesce(nullif(btrim(new.raw_user_meta_data ->> 'display_name'), ''), split_part(coalesce(new.email, 'membre'), '@', 1)), 90);
  if char_length(chosen_name) < 2 then chosen_name := 'Membre'; end if;
  chosen_type := case when new.raw_user_meta_data ->> 'account_type' = 'creator' then 'creator' else 'participant' end;
  insert into public.profiles (id, display_name, country, account_type)
  values (new.id, chosen_name, coalesce(nullif(btrim(new.raw_user_meta_data ->> 'country'), ''), 'Togo'), chosen_type);
  return new;
end;
$$;
revoke all on function private.handle_new_user() from public, anon, authenticated;
drop trigger if exists on_auth_user_created_afriareach on auth.users;
create trigger on_auth_user_created_afriareach after insert on auth.users for each row execute function private.handle_new_user();
drop policy if exists "profiles_insert_self" on public.profiles;
revoke insert on public.profiles from anon, authenticated;

-- Private storage for proofs (5 MB max; image or PDF only).
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('afriareach-proofs','afriareach-proofs',false,5242880,array['image/jpeg','image/png','image/webp','application/pdf'])
on conflict (id) do update set public=false,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;

drop policy if exists "afriareach_proofs_upload_own" on storage.objects;
create policy "afriareach_proofs_upload_own" on storage.objects for insert to authenticated
with check (bucket_id='afriareach-proofs'
  and (storage.foldername(name))[1]=(select auth.uid())::text
  and (storage.foldername(name))[2] ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
  and exists (select 1 from public.campaign_applications a where a.id::text=(storage.foldername(name))[2]
    and a.participant_id=(select auth.uid()) and a.status='accepted'));

drop policy if exists "afriareach_proofs_read_parties" on storage.objects;
create policy "afriareach_proofs_read_parties" on storage.objects for select to authenticated
using (bucket_id='afriareach-proofs' and (
  (storage.foldername(name))[1]=(select auth.uid())::text
  or (select private.is_platform_admin())
  or exists (select 1 from public.campaign_applications a join public.campaigns c on c.id=a.campaign_id
    where a.id::text=(storage.foldername(name))[2] and c.advertiser_id=(select auth.uid()))
));

-- Admin actions are recorded automatically, without exposing the audit writer to clients.
create or replace function private.write_admin_audit_log()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare actor uuid := (select auth.uid()); entity uuid; old_status text; new_status text;
begin
  if actor is null or not (select private.is_platform_admin()) then return new; end if;
  entity := nullif(to_jsonb(new)->>'id','')::uuid;
  if entity is null then entity := nullif(to_jsonb(new)->>'user_id','')::uuid; end if;
  old_status := to_jsonb(old)->>'status';
  new_status := to_jsonb(new)->>'status';
  insert into public.admin_audit_log(admin_id,action,entity_type,entity_id,details)
  values(actor,tg_table_name||'.'||lower(tg_op),tg_table_name,entity,jsonb_build_object('old_status',old_status,'new_status',new_status));
  return new;
end;
$$;
revoke all on function private.write_admin_audit_log() from public, anon, authenticated;
drop trigger if exists audit_campaign_admin_updates on public.campaigns;
create trigger audit_campaign_admin_updates after update on public.campaigns for each row execute function private.write_admin_audit_log();
drop trigger if exists audit_fee_admin_updates on public.platform_fee_payments;
create trigger audit_fee_admin_updates after update on public.platform_fee_payments for each row execute function private.write_admin_audit_log();
drop trigger if exists audit_application_admin_updates on public.campaign_applications;
create trigger audit_application_admin_updates after update on public.campaign_applications for each row execute function private.write_admin_audit_log();
drop trigger if exists audit_payout_admin_updates on public.participant_payouts;
create trigger audit_payout_admin_updates after update on public.participant_payouts for each row execute function private.write_admin_audit_log();
drop trigger if exists audit_profile_admin_updates on public.profiles;
create trigger audit_profile_admin_updates after update on public.profiles for each row execute function private.write_admin_audit_log();



-- Admin-configurable transfer and support details for AfriReach.
create table if not exists public.platform_settings (
  id boolean primary key default true check (id = true),
  fee_payment_phone text,
  fee_payment_operator text,
  fee_instructions text,
  support_email text,
  support_phone text,
  updated_at timestamptz not null default now()
);
insert into public.platform_settings (id) values (true) on conflict (id) do nothing;
alter table public.platform_settings enable row level security;
drop policy if exists "platform_settings_read_authenticated" on public.platform_settings;
create policy "platform_settings_read_authenticated" on public.platform_settings for select to authenticated using (true);
drop policy if exists "platform_settings_admin_update" on public.platform_settings;
create policy "platform_settings_admin_update" on public.platform_settings for update to authenticated
using ((select private.is_platform_admin())) with check ((select private.is_platform_admin()));
revoke insert, delete on public.platform_settings from anon, authenticated;
revoke update on public.platform_settings from anon, authenticated;
grant select on public.platform_settings to authenticated;
grant update (fee_payment_phone, fee_payment_operator, fee_instructions, support_email, support_phone, updated_at) on public.platform_settings to authenticated;

drop policy if exists "afriareach_proofs_upload_own" on storage.objects;
create policy "afriareach_proofs_upload_own" on storage.objects for insert to authenticated
with check (
  bucket_id = 'afriareach-proofs' and (
    ((storage.foldername(name))[1] = (select auth.uid())::text
      and (storage.foldername(name))[2] ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
      and exists (select 1 from public.campaign_applications a where a.id::text=(storage.foldername(name))[2]
        and a.participant_id=(select auth.uid()) and a.status='accepted'))
    or
    ((storage.foldername(name))[1] = 'fees'
      and (storage.foldername(name))[2] ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
      and (storage.foldername(name))[3] = (select auth.uid())::text
      and exists (select 1 from public.campaigns c where c.id::text=(storage.foldername(name))[2]
        and c.advertiser_id=(select auth.uid()) and c.status='pending_fee_payment'))
  )
);
drop policy if exists "afriareach_proofs_read_parties" on storage.objects;
create policy "afriareach_proofs_read_parties" on storage.objects for select to authenticated
using (
  bucket_id='afriareach-proofs' and (
    (storage.foldername(name))[1]=(select auth.uid())::text
    or (select private.is_platform_admin())
    or exists (select 1 from public.campaign_applications a join public.campaigns c on c.id=a.campaign_id
      where a.id::text=(storage.foldername(name))[2] and c.advertiser_id=(select auth.uid()))
    or ((storage.foldername(name))[1]='fees' and (storage.foldername(name))[3]=(select auth.uid())::text
      and exists (select 1 from public.campaigns c where c.id::text=(storage.foldername(name))[2]
        and c.advertiser_id=(select auth.uid())))
  )
);
drop policy if exists "fee_payments_insert_owner" on public.platform_fee_payments;
create policy "fee_payments_insert_owner" on public.platform_fee_payments for insert to authenticated
with check (
  advertiser_id=(select auth.uid()) and status='submitted' and proof_reference is not null
  and exists (select 1 from public.campaigns c where c.id=campaign_id and c.advertiser_id=(select auth.uid())
    and c.status='pending_fee_payment' and c.service_fee=amount)
  and exists (select 1 from storage.objects o where o.bucket_id='afriareach-proofs' and o.name=proof_reference
    and (storage.foldername(o.name))[1]='fees' and (storage.foldername(o.name))[2]=campaign_id::text
    and (storage.foldername(o.name))[3]=(select auth.uid())::text)
);

create or replace function private.touch_platform_settings()
returns trigger language plpgsql security invoker set search_path = ''
as $$ begin new.updated_at := now(); return new; end; $$;
revoke all on function private.touch_platform_settings() from public, anon, authenticated;
drop trigger if exists touch_platform_settings_updated_at on public.platform_settings;
create trigger touch_platform_settings_updated_at before update on public.platform_settings for each row execute function private.touch_platform_settings();

create or replace function private.log_platform_settings_update()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare actor uuid := (select auth.uid());
begin
  if actor is not null and (select private.is_platform_admin()) then
    insert into public.admin_audit_log(admin_id,action,entity_type,entity_id,details)
    values(actor,'platform_settings.update','platform_settings',null,jsonb_build_object('updated_at',new.updated_at));
  end if;
  return new;
end;
$$;
revoke all on function private.log_platform_settings_update() from public, anon, authenticated;
drop trigger if exists audit_platform_settings_update on public.platform_settings;
create trigger audit_platform_settings_update after update on public.platform_settings for each row execute function private.log_platform_settings_update();



-- Record explicit acceptance of the current terms and privacy notice at signup.
alter table public.profiles
  add column if not exists terms_accepted_at timestamptz not null default now(),
  add column if not exists privacy_accepted_at timestamptz not null default now(),
  add column if not exists terms_version text not null default '2026-11-26',
  add column if not exists privacy_version text not null default '2026-11-26';

create or replace function private.handle_new_user()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare chosen_name text; chosen_type text;
begin
  if new.raw_user_meta_data ->> 'legal_acceptance' is distinct from 'true' then
    raise exception 'You must accept AfriReach terms and privacy policy before creating an account';
  end if;
  chosen_name := left(coalesce(nullif(btrim(new.raw_user_meta_data ->> 'display_name'), ''), split_part(coalesce(new.email, 'membre'), '@', 1)), 90);
  if char_length(chosen_name) < 2 then chosen_name := 'Membre'; end if;
  chosen_type := case when new.raw_user_meta_data ->> 'account_type' = 'creator' then 'creator' else 'participant' end;
  insert into public.profiles (id,display_name,country,account_type,terms_accepted_at,privacy_accepted_at,terms_version,privacy_version)
  values (new.id,chosen_name,coalesce(nullif(btrim(new.raw_user_meta_data ->> 'country'), ''),'Togo'),
    chosen_type,now(),now(),'2026-11-26','2026-11-26');
  return new;
end;
$$;



alter table public.profiles add column if not exists age_confirmed_at timestamptz not null default now();

create or replace function private.handle_new_user()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare chosen_name text; chosen_type text;
begin
  if new.raw_user_meta_data ->> 'legal_acceptance' is distinct from 'true' then
    raise exception 'You must accept AfriReach terms and privacy policy before creating an account';
  end if;
  if new.raw_user_meta_data ->> 'age_confirmation' is distinct from 'true' then
    raise exception 'AfriReach accounts are restricted to adults aged 18 or older';
  end if;
  chosen_name := left(coalesce(nullif(btrim(new.raw_user_meta_data ->> 'display_name'), ''), split_part(coalesce(new.email, 'membre'), '@', 1)), 90);
  if char_length(chosen_name) < 2 then chosen_name := 'Membre'; end if;
  chosen_type := case when new.raw_user_meta_data ->> 'account_type' = 'creator' then 'creator' else 'participant' end;
  insert into public.profiles (id,display_name,country,account_type,terms_accepted_at,privacy_accepted_at,terms_version,privacy_version,age_confirmed_at)
  values (new.id,chosen_name,coalesce(nullif(btrim(new.raw_user_meta_data ->> 'country'), ''),'Togo'),
    chosen_type,now(),now(),'2026-11-26','2026-11-26',now());
  return new;
end;
$$;



-- Permit a new fee-proof submission after a rejection, but never allow duplicate pending/approved payments.
alter table public.platform_fee_payments drop constraint if exists platform_fee_payments_campaign_id_key;
drop policy if exists "fee_payments_insert_owner" on public.platform_fee_payments;
create policy "fee_payments_insert_owner" on public.platform_fee_payments
for insert to authenticated
with check (
  advertiser_id=(select auth.uid()) and status='submitted' and proof_reference is not null
  and exists (select 1 from public.campaigns c where c.id=campaign_id and c.advertiser_id=(select auth.uid())
    and c.status='pending_fee_payment' and c.service_fee=amount)
  and not exists (select 1 from public.platform_fee_payments fp where fp.campaign_id=platform_fee_payments.campaign_id
    and fp.status in ('submitted','approved'))
  and exists (select 1 from storage.objects o where o.bucket_id='afriareach-proofs' and o.name=proof_reference
    and (storage.foldername(o.name))[1]='fees' and (storage.foldername(o.name))[2]=campaign_id::text
    and (storage.foldername(o.name))[3]=(select auth.uid())::text)
);



-- Advertiser transfer proofs are stored privately under payouts/<payout UUID>/<advertiser UUID>/<file>.
drop policy if exists "afriareach_proofs_upload_own" on storage.objects;
create policy "afriareach_proofs_upload_own" on storage.objects for insert to authenticated
with check (bucket_id='afriareach-proofs' and (
  ((storage.foldername(name))[1]=(select auth.uid())::text
    and (storage.foldername(name))[2] ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
    and exists (select 1 from public.campaign_applications a where a.id::text=(storage.foldername(name))[2] and a.participant_id=(select auth.uid()) and a.status='accepted'))
  or ((storage.foldername(name))[1]='fees'
    and (storage.foldername(name))[2] ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
    and (storage.foldername(name))[3]=(select auth.uid())::text
    and exists (select 1 from public.campaigns c where c.id::text=(storage.foldername(name))[2] and c.advertiser_id=(select auth.uid()) and c.status='pending_fee_payment'))
  or ((storage.foldername(name))[1]='payouts'
    and (storage.foldername(name))[2] ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
    and (storage.foldername(name))[3]=(select auth.uid())::text
    and exists (select 1 from public.participant_payouts p where p.id::text=(storage.foldername(name))[2] and p.advertiser_id=(select auth.uid()) and p.status='awaiting_advertiser_payment'))
));
drop policy if exists "afriareach_proofs_read_parties" on storage.objects;
create policy "afriareach_proofs_read_parties" on storage.objects for select to authenticated
using (bucket_id='afriareach-proofs' and (
  (storage.foldername(name))[1]=(select auth.uid())::text
  or (select private.is_platform_admin())
  or exists (select 1 from public.campaign_applications a join public.campaigns c on c.id=a.campaign_id where a.id::text=(storage.foldername(name))[2] and c.advertiser_id=(select auth.uid()))
  or ((storage.foldername(name))[1]='fees' and (storage.foldername(name))[3]=(select auth.uid())::text
    and exists (select 1 from public.campaigns c where c.id::text=(storage.foldername(name))[2] and c.advertiser_id=(select auth.uid())))
  or ((storage.foldername(name))[1]='payouts'
    and exists (select 1 from public.participant_payouts p where p.id::text=(storage.foldername(name))[2]
      and (p.advertiser_id=(select auth.uid()) or p.participant_id=(select auth.uid()))))
));
drop policy if exists "payouts_insert_advertiser" on public.participant_payouts;
create policy "payouts_insert_advertiser" on public.participant_payouts for insert to authenticated
with check (
  advertiser_id=(select auth.uid()) and status='awaiting_advertiser_payment' and advertiser_proof_reference is null
  and exists (select 1 from public.campaigns c where c.id=campaign_id and c.advertiser_id=(select auth.uid()))
  and exists (select 1 from public.campaign_applications a where a.id=application_id and a.campaign_id=participant_payouts.campaign_id
    and a.participant_id=participant_payouts.participant_id and a.status='approved')
  and exists (select 1 from public.campaigns c where c.id=campaign_id and c.participant_reward=amount)
);

create or replace function private.guard_business_updates()
returns trigger language plpgsql security invoker set search_path = ''
as $$
declare actor uuid := (select auth.uid()); admin boolean := (select private.is_platform_admin()); campaign_owner uuid;
begin
  if admin then return new; end if;
  if tg_table_name='profiles' then
    if new.id is distinct from old.id or new.account_type is distinct from old.account_type or new.created_at is distinct from old.created_at then raise exception 'Profile identity and account type are immutable by the user'; end if;
    new.updated_at:=now(); return new;
  elsif tg_table_name='campaigns' then
    if old.advertiser_id<>actor or new.id is distinct from old.id or new.advertiser_id is distinct from old.advertiser_id
      or new.participant_budget is distinct from old.participant_budget or new.service_fee is distinct from old.service_fee
      or new.currency is distinct from old.currency or new.created_at is distinct from old.created_at then raise exception 'Campaign contains fields that the advertiser cannot change'; end if;
    if old.status not in ('draft','pending_fee_payment') or new.status not in ('draft','pending_fee_payment','cancelled') then raise exception 'This campaign can no longer be edited by the advertiser'; end if;
    new.updated_at:=now(); return new;
  elsif tg_table_name='platform_fee_payments' then raise exception 'Only platform administrators can review service-fee payments';
  elsif tg_table_name='campaign_applications' then
    if new.id is distinct from old.id or new.campaign_id is distinct from old.campaign_id or new.participant_id is distinct from old.participant_id or new.applied_at is distinct from old.applied_at then raise exception 'Application identity fields are immutable'; end if;
    select c.advertiser_id into campaign_owner from public.campaigns c where c.id=old.campaign_id;
    if old.participant_id=actor then
      if new.status='submitted' then
        if old.status<>'accepted' or new.proof_reference is null or new.submitted_at is null
          or not exists (select 1 from storage.objects o where o.bucket_id='afriareach-proofs' and o.name=new.proof_reference and (storage.foldername(o.name))[1]=actor::text and (storage.foldername(o.name))[2]=old.id::text) then raise exception 'A valid private proof is required after acceptance'; end if;
      elsif new.status='withdrawn' then
        if old.status not in ('applied','accepted') or new.proof_reference is distinct from old.proof_reference or new.submission_note is distinct from old.submission_note or new.submitted_at is distinct from old.submitted_at then raise exception 'This application cannot be withdrawn now'; end if;
      else raise exception 'Participants may only submit proof or withdraw'; end if;
      if new.reviewed_at is distinct from old.reviewed_at then raise exception 'Participants cannot set review timestamps'; end if;
    elsif campaign_owner=actor then
      if not ((old.status='applied' and new.status in ('accepted','rejected')) or (old.status='submitted' and new.status in ('approved','rejected')))
        or new.submission_note is distinct from old.submission_note or new.proof_reference is distinct from old.proof_reference or new.submitted_at is distinct from old.submitted_at then raise exception 'Advertisers may only review valid application states'; end if;
    else raise exception 'Not authorized to update this application'; end if;
    return new;
  elsif tg_table_name='participant_payouts' then
    if new.id is distinct from old.id or new.application_id is distinct from old.application_id or new.campaign_id is distinct from old.campaign_id
      or new.advertiser_id is distinct from old.advertiser_id or new.participant_id is distinct from old.participant_id
      or new.amount is distinct from old.amount or new.currency is distinct from old.currency or new.payment_method is distinct from old.payment_method
      or new.created_at is distinct from old.created_at then raise exception 'Payout identity and amount fields are immutable'; end if;
    if old.advertiser_id=actor then
      if old.status<>'awaiting_advertiser_payment' or new.status<>'marked_paid' or new.participant_confirmed_at is distinct from old.participant_confirmed_at
        or new.dispute_note is distinct from old.dispute_note or new.advertiser_proof_reference is null
        or not exists (select 1 from storage.objects o where o.bucket_id='afriareach-proofs' and o.name=new.advertiser_proof_reference
          and (storage.foldername(o.name))[1]='payouts' and (storage.foldername(o.name))[2]=old.id::text and (storage.foldername(o.name))[3]=actor::text) then
        raise exception 'A private transfer proof is required before marking the payout paid'; end if;
    elsif old.participant_id=actor then
      if old.status<>'marked_paid' or new.status not in ('confirmed_by_participant','disputed')
        or new.advertiser_proof_reference is distinct from old.advertiser_proof_reference or new.marked_paid_at is distinct from old.marked_paid_at then raise exception 'Participants may only confirm or dispute a marked payment'; end if;
    else raise exception 'Not authorized to update this payout'; end if;
    return new;
  end if;
  raise exception 'Unsupported update target';
end;
$$;


create index if not exists platform_fee_payments_campaign_status_idx on public.platform_fee_payments(campaign_id,status);
