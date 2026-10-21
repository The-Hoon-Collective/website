-- Enforce the 30-calendar-day prospect period on the database, not only the dashboard.
-- Supersedes the original admin status function. Execute in Supabase SQL Editor.
create or replace function public.thc_admin_set_application_status(p_id uuid, p_status text)
returns void language plpgsql security definer set search_path = ''
as $$
declare v_current text; v_started timestamptz;
begin
 if not public.thc_is_admin() then raise exception 'Not authorised' using errcode='42501'; end if;
 if p_status not in ('prospect','approved','rejected','withdrawn') then raise exception 'Unsupported status' using errcode='22023'; end if;
 select status, prospect_started_at into v_current,v_started from public.membership_applications where id=p_id for update;
 if not found then raise exception 'Application not found' using errcode='P0002'; end if;
 if v_current in ('rejected','withdrawn') then raise exception 'Closed applications cannot be reopened' using errcode='22023'; end if;
 if v_current='approved' and p_status<>'approved' then raise exception 'Approved membership changes require a separate workflow' using errcode='22023'; end if;
 if p_status='prospect' and v_current<>'pending' then raise exception 'Only pending applications can enter prospect status' using errcode='22023'; end if;
 if p_status='approved' then
   if v_current<>'prospect' then raise exception 'Prospect review required before approval' using errcode='22023'; end if;
   if v_started is null or now()<v_started+interval '30 days' then
     raise exception 'The full 30-day prospect period must finish before approval' using errcode='22023';
   end if;
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
