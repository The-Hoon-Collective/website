-- THC membership applications: private by default
create extension if not exists pgcrypto;
create table if not exists public.membership_applications (
 id uuid primary key default gen_random_uuid(),
 created_at timestamptz not null default now(),
 full_name text not null check (char_length(full_name) between 2 and 150),
 preferred_name text,
 date_of_birth date not null,
 email text not null,
 phone text not null,
 suburb text not null,
 state text not null check (state in ('NSW','VIC','QLD','SA','WA','TAS','ACT','NT')),
 vehicle text,
 interests text,
 reason text not null,
 prospect_terms_accepted boolean not null check (prospect_terms_accepted),
 conduct_accepted boolean not null check (conduct_accepted),
 accuracy_confirmed boolean not null check (accuracy_confirmed),
 status text not null default 'pending' check (status in ('pending','prospect','approved','rejected','withdrawn')),
 prospect_started_at timestamptz,
 approved_at timestamptz,
 paid_at timestamptz,
 membership_expires_at timestamptz,
 constraint membership_dates_valid check (membership_expires_at is null or paid_at is not null)
);
alter table public.membership_applications enable row level security;
revoke all on public.membership_applications from anon, authenticated;
create index if not exists membership_applications_status_idx on public.membership_applications(status,created_at desc);
comment on table public.membership_applications is 'Private THC applications. Access only through authorised server-side service role workflows.';
