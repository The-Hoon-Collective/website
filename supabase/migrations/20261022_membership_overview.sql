-- Exact club-wide overview counts, not limited to the latest 200 application records.
create or replace function public.thc_admin_membership_overview()
returns table (pending bigint,prospects bigint,awaiting_payment bigint,active_members bigint,expired_members bigint,renewals_due_30_days bigint,rejected bigint,withdrawn bigint)
language plpgsql stable security definer set search_path = ''
as $$
begin
 if not public.thc_is_admin() then raise exception 'Not authorised' using errcode='42501'; end if;
 return query select
 count(*) filter(where a.status='pending'),
 count(*) filter(where a.status='prospect'),
 count(*) filter(where a.status='approved' and a.membership_expires_at is null),
 count(*) filter(where a.status='approved' and a.membership_expires_at>now()),
 count(*) filter(where a.status='approved' and a.membership_expires_at<=now()),
 count(*) filter(where a.status='approved' and a.membership_expires_at>now() and a.membership_expires_at<=now()+interval '30 days'),
 count(*) filter(where a.status='rejected'),
 count(*) filter(where a.status='withdrawn')
 from public.membership_applications a;
end;
$$;
revoke all on function public.thc_admin_membership_overview() from public, anon;
grant execute on function public.thc_admin_membership_overview() to authenticated;
