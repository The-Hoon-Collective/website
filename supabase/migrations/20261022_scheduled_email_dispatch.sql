-- THC automatic email dispatcher: checks queue every five minutes.
-- Prerequisites: pg_cron, pg_net, Supabase Vault.
-- Store the dispatch bearer secret in Vault using the Supabase dashboard.
-- Do not put secret values in this migration or GitHub.
-- Vault secret name: thc_email_dispatch_secret
-- Sending remains gated by THC_EMAIL_SENDING_ENABLED in dispatch-email.
create or replace function public.thc_schedule_email_dispatch()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_secret text;
begin
  select decrypted_secret into v_secret
  from vault.decrypted_secrets
  where name = 'thc_email_dispatch_secret'
  order by created_at desc limit 1;

  if v_secret is null or length(v_secret) < 16 then
    raise exception 'Missing thc_email_dispatch_secret in Supabase Vault';
  end if;

  perform net.http_post(
    url := 'https://aqdgadheudbzvsblfvuy.supabase.co/functions/v1/dispatch-email',
    headers := jsonb_build_object(
      'Content-Type','application/json',
      'Authorization','Bearer ' || v_secret
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 10000
  );
end;
$$;
revoke all on function public.thc_schedule_email_dispatch() from public, anon, authenticated;
-- Install only after Vault secret is saved.
select cron.schedule(
  'thc-email-dispatch-every-five-minutes',
  '*/5 * * * *',
  $job$select public.thc_schedule_email_dispatch();$job$
);
