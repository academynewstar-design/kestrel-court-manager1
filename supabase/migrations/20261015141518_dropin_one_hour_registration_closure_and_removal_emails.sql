-- Keep the existing 16, 8 and 1 hour unpaid checks. Close only Drop-in registration.
do $migration$
declare def text;
begin
 select pg_get_functiondef('public.register_dropin(bigint,text)'::regprocedure) into def;
 def:=replace(def,'if not found then raise exception ''Session not found''; end if;',
 'if not found then raise exception ''Session not found''; end if;
 if ((s.session_date+s.start_time) at time zone ''America/Toronto'')<=now()+interval ''1 hour'' then raise exception ''Drop-in registration closes 1 hour before the activity.''; end if;');
 execute def;
 select pg_get_functiondef('public.rejoin_my_session(bigint)'::regprocedure) into def;
 def:=replace(def,'else
   if not exists(select 1 from public.profiles',
 'else
   if ((v_s.session_date+v_s.start_time) at time zone ''America/Toronto'')<=now()+interval ''1 hour'' then raise exception ''Drop-in registration closes 1 hour before the activity.''; end if;
   if not exists(select 1 from public.profiles');
 execute def;
 select pg_get_functiondef('public.kestrel_promote_waitlist_on_vacancy()'::regprocedure) into def;
 def:=replace(def,'end if; select capacity','end if; if exists(select 1 from public.sessions s where s.id=old.session_id and ((s.session_date+s.start_time) at time zone ''America/Toronto'')<=now()+interval ''1 hour'') then return new; end if; select capacity');
 execute def;
 select pg_get_functiondef('public.process_dropin_payment_cutoffs()'::regprocedure) into def;
 def:=replace(def,'> now()', '> now() + interval ''1 hour''');
 execute def;
end $migration$;

create or replace function public.enforce_dropin_registration_cutoff()
returns trigger language plpgsql set search_path=public as $$
begin
 if auth.uid() is not null and public.is_admin() then return new; end if;
 if new.status in ('confirmed','waitlist','pending') and
 (new.registration_type='dropin' or (new.registration_type is null and not exists(
 select 1 from public.permanent_assignments pa where pa.session_id=new.session_id and pa.user_id=new.user_id)))
 and exists(select 1 from public.sessions s where s.id=new.session_id and ((s.session_date+s.start_time) at time zone 'America/Toronto')<=now()+interval '1 hour') then
 raise exception 'Drop-in registration closes 1 hour before the activity.';
 end if;
 return new;
end $$;
revoke all on function public.enforce_dropin_registration_cutoff() from public,anon,authenticated;
create trigger enforce_dropin_registration_cutoff before insert or update of status on public.registrations
for each row execute function public.enforce_dropin_registration_cutoff();

create or replace function public.queue_unpaid_removal_email()
returns trigger language plpgsql security definer set search_path=public as $$
begin
 if old.status='confirmed' and lower(coalesce(old.payment_status,''))='unpaid'
 and new.status='cancelled' and new.payment_status='removed'
 and (new.registration_type='dropin' or (new.registration_type is null and not exists(
 select 1 from public.permanent_assignments pa where pa.session_id=new.session_id and pa.user_id=new.user_id))) then
  insert into public.email_notifications(user_id,notification_type,registration_id,recipient_email,subject,body)
  select new.user_id,'unpaid_removed',new.id,p.email,
   'Your Drop-in spot was removed - Kestrel Sports',
   'You have lost your spot for '||coalesce(sp.name,'your activity')||' at '||coalesce(l.name,'your location')||
   ' on '||to_char(s.session_date,'FMDay, FMMonth DD, YYYY')||' at '||to_char(s.start_time,'HH12:MI AM')||
   ' (Toronto time) because your payment status showed Unpaid when the system checked.'||chr(10)||chr(10)||
   'Unpaid registrations are checked 16 hours, 8 hours and 1 hour before the activity. Registration and waitlist promotions close 1 hour before the activity.'||chr(10)||chr(10)||
   'If registration is still open, you may join again if a spot is available. After sending payment, tap Mark Paid in the app.'||chr(10)||chr(10)||
   'If you already sent payment, please contact Admin through Messages in the app for help.'||chr(10)||'https://kestrelsports.ca'
  from public.profiles p join public.sessions s on s.id=new.session_id
  left join public.sports sp on sp.id=s.sport_id left join public.locations l on l.id=s.location_id
  where p.id=new.user_id and nullif(btrim(p.email),'') is not null;
 end if;
 return new;
end $$;
revoke all on function public.queue_unpaid_removal_email() from public,anon,authenticated;
create trigger queue_unpaid_removal_email after update of status on public.registrations
for each row when(old.status='confirmed' and new.status='cancelled' and old.payment_status='unpaid' and new.payment_status='removed')
execute function public.queue_unpaid_removal_email();

update public.communications set message='Drop-in players: Unpaid registrations are automatically removed 16, 8 and 1 hour before the activity. Registration closes 1 hour before the activity. Send payment, then tap Mark Paid. Removed players receive an email notification.'
where title='Drop-in payment reminder' and audience='dropin' and not is_archived;
