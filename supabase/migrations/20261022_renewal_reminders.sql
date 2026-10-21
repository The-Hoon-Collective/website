-- Queue one renewal reminder per membership expiry, 30 days before expiry.
-- This function does NOT send email; the separately gated dispatcher handles delivery.
alter table public.thc_email_outbox
 add column if not exists reminder_expiry timestamptz;

create unique index if not exists thc_one_reminder_per_expiry
 on public.thc_email_outbox(application_id,template,reminder_expiry)
 where template='renewal_reminder';

create or replace function public.thc_queue_renewal_reminders()
returns integer language plpgsql security definer set search_path = ''
as $$
declare queued integer;
begin
 -- Only service-role workflows or the Supabase SQL/cron owner may run this.
 if current_user <> 'postgres' and auth.role() <> 'service_role' then
   raise exception 'Not authorised' using errcode='42501';
 end if;
 with inserted as (
  insert into public.thc_email_outbox
   (application_id,recipient,template,payload,reminder_expiry)
  select a.id,a.email,'renewal_reminder',
   jsonb_build_object('name',coalesce(nullif(a.preferred_name,''),a.full_name),
                      'expires_at',a.membership_expires_at),
   a.membership_expires_at
  from public.membership_applications a
  where a.status='approved'
    and a.membership_expires_at > now()
    and a.membership_expires_at <= now()+interval '30 days'
  on conflict do nothing
  returning id
 )
 select count(*)::integer into queued from inserted;
 return queued;
end;
$$;
revoke all on function public.thc_queue_renewal_reminders() from public,anon,authenticated;
grant execute on function public.thc_queue_renewal_reminders() to service_role;

-- pg_cron is already used for THC retention. This only queues reminders.
do $$
begin
 if exists(select 1 from cron.job where jobname='thc-renewal-reminder-queue') then
   perform cron.unschedule('thc-renewal-reminder-queue');
 end if;
 perform cron.schedule('thc-renewal-reminder-queue','30 3 * * *',
   'select public.thc_queue_renewal_reminders();');
end $$;
