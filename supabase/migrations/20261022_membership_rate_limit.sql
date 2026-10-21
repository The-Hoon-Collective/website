-- Private, atomic per-client submission throttle. Run once in Supabase SQL Editor.
create table if not exists public.membership_submission_limits (
 fingerprint text not null,
 window_start timestamptz not null,
 attempts integer not null default 1,
 primary key (fingerprint, window_start)
);
alter table public.membership_submission_limits enable row level security;
revoke all on public.membership_submission_limits from public, anon, authenticated;
create or replace function public.claim_membership_submission_slot(p_fingerprint text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_window timestamptz := date_trunc('hour', now());
  v_attempts integer;
begin
  if p_fingerprint is null or length(p_fingerprint) <> 64 then
    return false;
  end if;
  insert into public.membership_submission_limits (fingerprint, window_start, attempts)
  values (p_fingerprint, v_window, 1)
  on conflict (fingerprint, window_start)
  do update set attempts = public.membership_submission_limits.attempts + 1
  returning attempts into v_attempts;
  return v_attempts <= 5;
end;
$$;
revoke all on function public.claim_membership_submission_slot(text) from public, anon, authenticated;
grant execute on function public.claim_membership_submission_slot(text) to service_role;
comment on function public.claim_membership_submission_slot(text) is 'Atomic limit: five submission attempts per fingerprint per UTC hour. Service role only.';
-- Old buckets can be removed periodically after a retention policy is approved.
