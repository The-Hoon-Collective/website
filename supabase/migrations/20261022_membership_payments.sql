-- Annual THC membership: manual verification of AUD 50 payment.
-- Admin-only RPCs; no public payment collection.
create table if not exists public.thc_membership_payments (
 id uuid primary key default gen_random_uuid(),
 application_id uuid not null references public.membership_applications(id),
 recorded_at timestamptz not null default now(),
 recorded_by uuid not null references auth.users(id),
 amount_cents integer not null check (amount_cents = 5000),
 payment_reference text not null check (length(trim(payment_reference)) between 3 and 120),
 period_start timestamptz not null,
 period_end timestamptz not null,
 constraint thc_payment_dates check (period_end > period_start),
 unique (application_id, payment_reference)
);
alter table public.thc_membership_payments enable row level security;
revoke all on public.thc_membership_payments from public, anon, authenticated;

create or replace function public.thc_admin_record_membership_payment(p_id uuid,p_reference text)
returns timestamptz language plpgsql security definer set search_path = ''
as $$
declare a public.membership_applications%rowtype; v_start timestamptz; v_end timestamptz; v_ref text;
begin
 if not public.thc_is_admin() then raise exception 'Not authorised' using errcode='42501'; end if;
 v_ref:=trim(p_reference);
 if v_ref is null or length(v_ref)<3 or length(v_ref)>120 then raise exception 'A payment reference (3–120 characters) is required' using errcode='22023'; end if;
 select * into a from public.membership_applications where id=p_id for update;
 if not found then raise exception 'Application not found' using errcode='P0002'; end if;
 if a.status<>'approved' then raise exception 'Only approved applicants can activate or renew membership' using errcode='22023'; end if;
 if exists(select 1 from public.thc_membership_payments p where p.application_id=p_id and p.payment_reference=v_ref) then
   raise exception 'Payment reference already recorded for this member' using errcode='23505';
 end if;
 v_start:=greatest(now(),coalesce(a.membership_expires_at,now()));
 v_end:=v_start+interval '12 months';
 insert into public.thc_membership_payments(application_id,recorded_by,amount_cents,payment_reference,period_start,period_end)
 values(p_id,auth.uid(),5000,v_ref,v_start,v_end);
 update public.membership_applications set paid_at=now(),membership_expires_at=v_end where id=p_id;
 return v_end;
end;
$$;
revoke all on function public.thc_admin_record_membership_payment(uuid,text) from public, anon;
grant execute on function public.thc_admin_record_membership_payment(uuid,text) to authenticated;

create or replace function public.thc_admin_list_membership_payments(p_id uuid)
returns table(recorded_at timestamptz,amount_cents integer,payment_reference text,period_start timestamptz,period_end timestamptz)
language plpgsql security definer set search_path = ''
as $$
begin
 if not public.thc_is_admin() then raise exception 'Not authorised' using errcode='42501'; end if;
 return query select p.recorded_at,p.amount_cents,p.payment_reference,p.period_start,p.period_end
 from public.thc_membership_payments p where p.application_id=p_id order by p.recorded_at desc;
end;
$$;
revoke all on function public.thc_admin_list_membership_payments(uuid) from public, anon;
grant execute on function public.thc_admin_list_membership_payments(uuid) to authenticated;
