-- Include permanent member ID in every paid membership email.
-- The membership-number BEFORE UPDATE trigger runs before the email AFTER UPDATE trigger.
create or replace function public.thc_queue_membership_email()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare v_template text;
begin
 if tg_op='INSERT' then v_template:='application_received';
 elsif new.membership_expires_at is distinct from old.membership_expires_at
       and new.membership_expires_at is not null and new.paid_at is not null then
   v_template:='membership_activated';
 elsif new.status is distinct from old.status then
   v_template:=case new.status when 'prospect' then 'prospect_started' when 'approved' then 'approved' when 'rejected' then 'rejected' else null end;
 end if;
 if v_template is not null then
   insert into public.thc_email_outbox(application_id,recipient,template,payload)
   values(new.id,new.email,v_template,jsonb_build_object(
    'name',new.full_name,'membership_number',new.membership_number,
    'expires_at',new.membership_expires_at,'prospect_started_at',new.prospect_started_at));
 end if;
 return new;
end;
$$;
-- Keep existing trigger, which already calls this function.
