-- THC retention enforcement: run in Supabase SQL Editor after reviewing.
-- Record when an application enters a final rejected/withdrawn state.
alter table public.membership_applications
 add column if not exists closed_at timestamptz;

create or replace function public.thc_application_closure_timestamp()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
 if new.status in ('rejected','withdrawn') then
   if tg_op = 'INSERT' or old.status is distinct from new.status or old.closed_at is null then
     new.closed_at := now();
   end if;
 else
   new.closed_at := null;
 end if;
 return new;
end;
$$;

drop trigger if exists thc_application_closure_stamp on public.membership_applications;
create trigger thc_application_closure_stamp
before insert or update of status on public.membership_applications
for each row execute function public.thc_application_closure_timestamp();

-- Existing final-status records have no reliable decision timestamp.
-- Do not backdate them from created_at; review them manually.
create or replace function public.thc_delete_expired_applications()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare v_deleted integer;
begin
 delete from public.membership_applications
 where status in ('rejected','withdrawn')
   and closed_at is not null
   and closed_at <= now() - interval '90 days';
 get diagnostics v_deleted = row_count;
 return v_deleted;
end;
$$;
revoke all on function public.thc_delete_expired_applications() from public, anon, authenticated;
grant execute on function public.thc_delete_expired_applications() to service_role;

-- Requires pg_cron enabled in Supabase Dashboard > Database > Extensions.
create extension if not exists pg_cron;
-- Schedule cleanup daily at 03:15 UTC. Run only once; subsequent runs update the job.
do $$
declare v_jobid bigint;
begin
 select jobid into v_jobid from cron.job where jobname='thc-membership-retention';
 if v_jobid is not null then perform cron.unschedule(v_jobid); end if;
 perform cron.schedule('thc-membership-retention','15 3 * * *',
   'select public.thc_delete_expired_applications();');
end;
$$;
