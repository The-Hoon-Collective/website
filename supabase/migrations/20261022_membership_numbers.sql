-- THC membership numbers: immutable, unique, assigned on first verified payment.
-- Uses a database sequence so concurrent activations cannot receive the same number.
create sequence if not exists public.thc_membership_number_seq as bigint start with 1 increment by 1;
revoke all on sequence public.thc_membership_number_seq from public,anon,authenticated;

alter table public.membership_applications
 add column if not exists membership_number text;

create unique index if not exists thc_membership_number_unique
 on public.membership_applications(membership_number)
 where membership_number is not null;

create or replace function public.thc_assign_membership_number()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
 if old.membership_number is not null and new.membership_number is distinct from old.membership_number then
   raise exception 'Membership numbers are permanent' using errcode='23514';
 end if;
 if new.membership_number is not null and old.membership_number is null then
   raise exception 'Membership numbers are assigned automatically' using errcode='23514';
 end if;
 if old.membership_number is null and new.status='approved' and new.paid_at is not null and new.membership_expires_at is not null then
   new.membership_number:='THC-'||extract(year from new.paid_at at time zone 'Australia/Sydney')::integer||'-'||lpad(nextval('public.thc_membership_number_seq')::text,5,'0');
 end if;
 return new;
end;
$$;

drop trigger if exists thc_assign_membership_number_trigger on public.membership_applications;
create trigger thc_assign_membership_number_trigger
 before update on public.membership_applications
 for each row execute function public.thc_assign_membership_number();

-- Backfill any already-paid members; existing numbers are never changed.
update public.membership_applications
set membership_expires_at=membership_expires_at
where status='approved' and paid_at is not null
 and membership_expires_at is not null and membership_number is null;

-- Update the admin listing so membership numbers are visible to the existing dashboard.
drop function if exists public.thc_admin_list_applications();
create function public.thc_admin_list_applications()
returns table (
 id uuid, created_at timestamptz, full_name text, preferred_name text,
 date_of_birth date, email text, phone text, suburb text, state text,
 vehicle text, interests text, reason text, status text,
 prospect_started_at timestamptz, approved_at timestamptz,
 paid_at timestamptz, membership_expires_at timestamptz, closed_at timestamptz,
 membership_number text
)
language plpgsql security definer set search_path = ''
as $$
begin
 if not public.thc_is_admin() then raise exception 'Not authorised' using errcode='42501'; end if;
 return query select a.id,a.created_at,a.full_name,a.preferred_name,a.date_of_birth,
 a.email,a.phone,a.suburb,a.state,a.vehicle,a.interests,a.reason,a.status,
 a.prospect_started_at,a.approved_at,a.paid_at,a.membership_expires_at,a.closed_at,
 a.membership_number
 from public.membership_applications a order by a.created_at desc limit 200;
end;
$$;
revoke all on function public.thc_admin_list_applications() from public,anon;
grant execute on function public.thc_admin_list_applications() to authenticated;
