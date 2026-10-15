create or replace function public.queue_private_message_notification()
returns trigger language plpgsql security definer set search_path=public as $function$
declare recipient uuid; destination text; admin_sender boolean; owner_id uuid; sender_name text; topic text;
begin
 select user_id,category into owner_id,topic from public.suggestions where id=new.suggestion_id;
 if owner_id is null then return new; end if;
 select coalesce(is_admin,false),full_name into admin_sender,sender_name from public.profiles where id=new.sender_id;
 if not found then return new; end if;
 if not admin_sender and new.sender_id=owner_id then
  -- The verified club admin mailbox receives every new player message and reply.
  select id,email into recipient,destination from public.profiles
   where is_admin and lower(email)='academynewstar@gmail.com' limit 1;
  if recipient is null then return new; end if;
  insert into public.email_notifications(user_id,notification_type,recipient_email,subject,body,status)
  values(recipient,'admin_player_message',destination,'New player message - Kestrel Sports',
   'You have a new message from '||coalesce(nullif(btrim(sender_name),''),'a player')||
   case when nullif(btrim(topic),'') is not null then ' about '||topic else '' end||'.'||chr(10)||chr(10)||
   'Sign in at https://kestrelsports.ca and open Admin → Messages → Player messages to read and reply.'||chr(10)||chr(10)||
   'Please reply through Messages in the app, rather than replying to this notification email.','pending');
 elsif admin_sender and new.sender_id<>owner_id then
  recipient:=owner_id;
  select email into destination from public.profiles where id=recipient;
  if nullif(btrim(destination),'') is null then return new; end if;
  insert into public.email_notifications(user_id,notification_type,recipient_email,subject,body,status)
  values(recipient,'private_message',destination,'New message from Kestrel Sports Club',
   'You have a new private message from Kestrel Sports Club. Sign in at https://kestrelsports.ca and open Messages to read and reply. Please do not reply to this email. Reply through Messages on kestrelsports.ca.','pending');
 end if;
 return new;
end $function$;
-- Called only by the existing AFTER INSERT trigger.
revoke all on function public.queue_private_message_notification() from public,anon,authenticated;
