-- Queue one notification when a drop-in account transitions to rejected.
-- Uses the existing email_notifications delivery pipeline; never sends from the browser.
create or replace function public.queue_dropin_account_rejection_email()
returns trigger language plpgsql security definer set search_path = '' as $$
declare destination text;
begin
 if new.status = 'rejected' and old.status is distinct from 'rejected' then
   select nullif(btrim(p.email),'') into destination
   from public.profiles p where p.id = new.user_id;
   if destination is not null then
     insert into public.email_notifications
       (user_id, notification_type, recipient_email, subject, body, status)
     values (
       new.user_id, 'dropin_account_rejected', destination,
       'Kestrel Sports Club - Registration Requires Correction',
       'Hello,' || chr(10) || chr(10) ||
       'Your drop-in account registration was not approved.' || chr(10) ||
       'If your registration was rejected because of an incomplete or unclear name, please use your proper first and last name, rather than initials or an incomplete name.' || chr(10) ||
       'Please sign in at https://kestrelsports.ca and contact Admin through Messages to request a correction and a new review.' || chr(10) || chr(10) ||
       'Thank you,' || chr(10) || 'Kestrel Sports Club',
       'pending'
     );
   end if;
 end if;
 return new;
end $$;
revoke all on function public.queue_dropin_account_rejection_email() from public, anon, authenticated;
drop trigger if exists queue_dropin_account_rejection_email on public.dropin_account_approvals;
create trigger queue_dropin_account_rejection_email
after update of status on public.dropin_account_approvals
for each row execute function public.queue_dropin_account_rejection_email();
