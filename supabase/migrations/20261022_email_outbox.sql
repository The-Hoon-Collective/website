-- Private transactional email outbox. Queue only: nothing sends until explicitly configured.
create table if not exists public.thc_email_outbox (
 id uuid primary key default gen_random_uuid(),
 application_id uuid references public.membership_applications(id) on delete set null,
 recipient text not null,
 template text not null check(template in ('application_received','prospect_started','approved','rejected','membership_activated','renewal_reminder')),
 payload jsonb not null default '{}'::jsonb,
 created_at timestamptz not null default now(),
 sent_at timestamptz,
 attempts integer not null default 0,
 last_error text
);
alter table public.thc_email_outbox enable row level security;
revoke all on public.thc_email_outbox from public,anon,authenticated;
create index if not exists thc_email_outbox_pending_idx on public.thc_email_outbox(created_at) where sent_at is null;

create or replace function public.thc_queue_membership_email()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare v_template text;
begin
 if tg_op='INSERT' then v_template:='application_received';
 elsif new.status is distinct from old.status then
   v_template:=case new.status when 'prospect' then 'prospect_started' when 'approved' then 'approved' when 'rejected' then 'rejected' else null end;
 elsif new.membership_expires_at is distinct from old.membership_expires_at and new.membership_expires_at is not null then
   v_template:='membership_activated';
 end if;
 if v_template is not null then
   insert into public.thc_email_outbox(application_id,recipient,template,payload)
   values(new.id,new.email,v_template,jsonb_build_object('name',coalesce(nullif(new.preferred_name,''),new.full_name),'expires_at',new.membership_expires_at,'prospect_started_at',new.prospect_started_at));
 end if;
 return new;
end;
$$;
drop trigger if exists thc_queue_membership_email_trigger on public.membership_applications;
create trigger thc_queue_membership_email_trigger after insert or update on public.membership_applications
for each row execute function public.thc_queue_membership_email();
