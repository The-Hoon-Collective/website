-- THC administrator-only membership workflows.
-- Run in Supabase SQL Editor after reviewing. No admin account is created automatically.
create table if not exists public.thc_admins (
 user_id uuid primary key references auth.users(id) on delete cascade,
 created_at timestamptz not null default now()
);
alter table public.thc_admins enable row level security;
revoke all on public.thc_admins from public, anon, authenticated;

create or replace function public.thc_is_admin()
returns boolean language sql stable security definer set search_path = ''
as $$
 select exists(select 1 from public.thc_admins a where a.user_id = (select auth.uid()));
$$;
revoke all on function public.thc_is_admin() from public, anon;
grant execute on function public.thc_is_admin() to authenticated;

-- Admin-only read interface; service role and table permissions remain private.
create or replace function public.thc_admin_list_applications()
returns table (
 id uuid, created_at timestamptz, full_name text, preferred_name text,
 date_of_birth date, email text, phone text, suburb text, state text,
 vehicle text, interests text, reason text, status text,
 prospect_started_at timestamptz, approved_at timestamptz,
 paid_at timestamptz, membership_expires_at timestamptz, closed_at timestamptz
)
language plpgsql security definer set search_path = ''
as $$
begin
 if not public.thc_is_admin() then raise exception 'Not authorised' using errcode='42501'; end if;
 return query
 select a.id,a.created_at,a.full_name,a.preferred_name,a.date_of_birth,
 a.email,a.phone,a.suburb,a.state,a.vehicle,a.interests,a.reason,a.status,
 a.prospect_started_at,a.approved_at,a.paid_at,a.membership_expires_at,a.closed_at
 from public.membership_applications a order by a.created_at desc limit 200;
end;
$$;
revoke all on function public.thc_admin_list_applications() from public, anon;
grant execute on function public.thc_admin_list_applications() to authenticated;

-- Deliberately restrict transitions. Approval does not collect payment or activate membership.
create or replace function public.thc_admin_set_application_status(p_id uuid, p_status text)
returns void language plpgsql security definer set search_path = ''
as $$
declare v_current text;
begin
 if not public.thc_is_admin() then raise exception 'Not authorised' using errcode='42501'; end if;
 if p_status not in ('prospect','approved','rejected','withdrawn') then
   raise exception 'Unsupported status' using errcode='22023';
 end if;
 select status into v_current from public.membership_applications where id=p_id for update;
 if not found then raise exception 'Application not found' using errcode='P0002'; end if;
 if v_current in ('rejected','withdrawn') then
   raise exception 'Closed applications cannot be reopened through this workflow' using errcode='22023';
 end if;
 if v_current='approved' and p_status <> 'approved' then
   raise exception 'Approved membership changes require a separate workflow' using errcode='22023';
 end if;
 if p_status='prospect' and v_current <> 'pending' then
   raise exception 'Only pending applications can enter prospect status' using errcode='22023';
 end if;
 if p_status='approved' and v_current <> 'prospect' then
   raise exception 'Prospect review is required before approval' using errcode='22023';
 end if;
 update public.membership_applications
 set status=p_status,
     prospect_started_at=case when p_status='prospect' then coalesce(prospect_started_at,now()) else prospect_started_at end,
     approved_at=case when p_status='approved' then coalesce(approved_at,now()) else approved_at end
 where id=p_id;
end;
$$;
revoke all on function public.thc_admin_set_application_status(uuid,text) from public, anon;
grant execute on function public.thc_admin_set_application_status(uuid,text) to authenticated;

-- IMPORTANT: Provision your own Supabase Auth user, then explicitly grant admin:
-- insert into public.thc_admins(user_id)
-- select id from auth.users where email = 'YOUR_VERIFIED_ADMIN_EMAIL';
-- Never put service-role keys in a browser or in GitHub.
