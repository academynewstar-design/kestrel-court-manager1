create or replace function public.admin_unpaid_dropin_report(p_date date)
returns table(registration_id bigint,player_name text,player_email text,sport_id bigint,location_id bigint,sport text,location text,city text,session_date date,start_time time,end_time time,court text,price numeric,starts_at timestamptz)
language plpgsql security invoker set search_path=public as $$
begin
if auth.uid() is null or not public.is_admin() then raise exception 'Admin access required'; end if;
return query select r.id,p.full_name,p.email,s.sport_id,s.location_id,sp.name,l.name,l.city,s.session_date,s.start_time,s.end_time,s.court,s.price,
(s.session_date+s.start_time) at time zone 'America/Toronto'
from public.registrations r join public.profiles p on p.id=r.user_id
join public.sessions s on s.id=r.session_id join public.sports sp on sp.id=s.sport_id join public.locations l on l.id=s.location_id
where r.status='confirmed' and lower(coalesce(r.payment_status,''))='unpaid'
and (r.registration_type='dropin' or (r.registration_type is null and not exists(select 1 from public.permanent_assignments pa where pa.user_id=r.user_id and pa.session_id=r.session_id)))
and s.status<>'closed' and s.availability_status<>'unavailable' and s.session_date=p_date order by s.start_time,l.name,p.full_name;
end $$;
revoke all on function public.admin_unpaid_dropin_report(date) from public,anon;
grant execute on function public.admin_unpaid_dropin_report(date) to authenticated;

create schema if not exists kestrel_private;
revoke all on schema kestrel_private from public,anon,authenticated;
create unique index if not exists email_unpaid90_activity_unique on public.email_notifications(notification_type) where notification_type like 'unpaid90:%';
create or replace function kestrel_private.queue_unpaid_dropin_reports()
returns integer language plpgsql security definer set search_path=public as $$
declare admin_id uuid; destination text; activity record; queued integer:=0; inserted integer;
begin
select id,email into admin_id,destination from public.profiles where is_admin and lower(email)='academynewstar@gmail.com' limit 1;
if admin_id is null then raise exception 'Report admin mailbox not found'; end if;
for activity in with unpaid(registration_id,player_name,player_email,sport_id,location_id,sport,location,city,session_date,start_time,end_time,court,price,starts_at) as (
select r.id,p.full_name,p.email,s.sport_id,s.location_id,sp.name,l.name,l.city,s.session_date,s.start_time,s.end_time,s.court,s.price,
(s.session_date+s.start_time) at time zone 'America/Toronto'
from public.registrations r join public.profiles p on p.id=r.user_id
join public.sessions s on s.id=r.session_id join public.sports sp on sp.id=s.sport_id join public.locations l on l.id=s.location_id
where r.status='confirmed' and lower(coalesce(r.payment_status,''))='unpaid'
and (r.registration_type='dropin' or (r.registration_type is null and not exists(select 1 from public.permanent_assignments pa where pa.user_id=r.user_id and pa.session_id=r.session_id)))
and s.status<>'closed' and s.availability_status<>'unavailable' and s.session_date between (now() at time zone 'America/Toronto')::date and (now() at time zone 'America/Toronto')::date+1)
select sport_id,location_id,sport,location,city,session_date,start_time,starts_at,count(*) as player_count,
string_agg(player_name||' <'||player_email||'> — '||coalesce(court,'General')||' — $'||price||' — Unpaid',chr(10) order by player_name,registration_id) as players
from unpaid where starts_at<=now()+interval '90 minutes' and starts_at>now()+interval '60 minutes'
group by sport_id,location_id,sport,location,city,session_date,start_time,starts_at
loop
insert into public.email_notifications(user_id,notification_type,recipient_email,subject,body,status)
values(admin_id,'unpaid90:'||activity.sport_id||':'||activity.location_id||':'||activity.session_date||':'||activity.start_time,destination,
'Unpaid Drop-ins — '||activity.location||' — '||activity.session_date||' '||to_char(activity.start_time,'HH24:MI'),
activity.sport||' — '||activity.location||' — '||coalesce(activity.city,'')||chr(10)||
activity.session_date||' '||to_char(activity.start_time,'HH24:MI')||' (Toronto time)'||chr(10)||chr(10)||
'90-minute payment review: '||activity.player_count||' confirmed Drop-in player(s) are unpaid.'||chr(10)||chr(10)||
activity.players||chr(10)||chr(10)||
'Unpaid removal is scheduled 1 hour before the game ('||to_char((activity.starts_at at time zone 'America/Toronto')-interval '1 hour','HH24:MI')||').'||chr(10)||
'This is a snapshot. Check Admin → Reports → Unpaid Drop-ins at https://kestrelsports.ca for current status.','pending')
on conflict do nothing;
get diagnostics inserted=row_count; queued:=queued+inserted;
end loop;
return queued;
end $$;
revoke all on function kestrel_private.queue_unpaid_dropin_reports() from public,anon,authenticated;
grant usage on schema kestrel_private to service_role;
grant execute on function kestrel_private.queue_unpaid_dropin_reports() to service_role;
select cron.schedule('kestrel-unpaid-dropin-90-minute-report','* * * * *','select kestrel_private.queue_unpaid_dropin_reports();');
