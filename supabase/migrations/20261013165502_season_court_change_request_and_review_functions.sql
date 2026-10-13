CREATE OR REPLACE FUNCTION public.request_my_season_court_change(p_recurring_schedule_id bigint,p_court text)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
declare v_uid uuid:=auth.uid(); v_current text; v_id bigint;
begin
 if v_uid is null or not exists(select 1 from profiles where id=v_uid and player_type='permanent' and player_type_status='approved') then raise exception 'An approved Season account is required'; end if;
 if p_court is null or p_court not in ('Court 1','Court 2','Court 3','Court 4','Court 5','Court 6') then raise exception 'Choose a valid court'; end if;
 select r.court into v_current from recurring_permanent_requests r join recurring_schedules s on s.id=r.recurring_schedule_id join sports sp on sp.id=s.sport_id
 where r.user_id=v_uid and r.recurring_schedule_id=p_recurring_schedule_id and r.status='approved' and s.active and sp.name='badminton' for update of r;
 if not found then raise exception 'Choose one of your approved Badminton schedules'; end if;
 if p_court=coalesce(v_current,'General') then raise exception 'Choose a different court'; end if;
 insert into season_court_change_requests(user_id,recurring_schedule_id,current_court,requested_court)
 values(v_uid,p_recurring_schedule_id,coalesce(v_current,'General'),p_court)
 on conflict(user_id,recurring_schedule_id) where status='pending'
 do update set current_court=excluded.current_court,requested_court=excluded.requested_court,updated_at=now()
 returning id into v_id;
 return v_id;
end $function$;

CREATE OR REPLACE FUNCTION public.admin_review_season_court_change(p_request_id bigint,p_status text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
declare change public.season_court_change_requests%rowtype; source public.sessions%rowtype;
 reg public.registrations%rowtype; target_id bigint; v_count integer; v_limit integer; v_name text;
begin
 if auth.uid() is null or not exists(select 1 from profiles where id=auth.uid() and is_admin=true) then raise exception 'Admin access required'; end if;
 if p_status not in ('approved','rejected') then raise exception 'Invalid review status'; end if;
 select * into change from season_court_change_requests where id=p_request_id and status='pending' for update;
 if not found then raise exception 'Court change request is no longer pending'; end if;
 perform 1 from recurring_permanent_requests where user_id=change.user_id and recurring_schedule_id=change.recurring_schedule_id and status='approved' for update;
 if not found then raise exception 'The Season schedule is no longer approved'; end if;
 if p_status='approved' then
  for source in select s.* from sessions s join permanent_assignments a on a.session_id=s.id
   where a.user_id=change.user_id and s.recurring_schedule_id=change.recurring_schedule_id
   and ((s.session_date+s.start_time) at time zone 'America/Toronto')>now()
   and s.court is distinct from change.requested_court order by s.session_date,s.id loop
   insert into sessions(sport_id,location_id,session_date,start_time,end_time,capacity,price,payment_email,payment_first,
    registration_open_at,registration_deadline,payment_deadline,status,court,recurring_schedule_id,dropin_enabled,availability_status)
   values(source.sport_id,source.location_id,source.session_date,source.start_time,source.end_time,source.capacity,source.price,
    source.payment_email,source.payment_first,source.registration_open_at,source.registration_deadline,source.payment_deadline,
    source.status,change.requested_court,source.recurring_schedule_id,false,source.availability_status)
   on conflict(recurring_schedule_id,session_date,court) where recurring_schedule_id is not null do nothing;
   select id,capacity into target_id,v_limit from sessions where recurring_schedule_id=source.recurring_schedule_id
    and session_date=source.session_date and court=change.requested_court for update;
   if exists(select 1 from exclusive_court_bookings b where b.session_id=target_id and b.cancelled_at is null) then raise exception 'Court % is privately reserved on %',change.requested_court,source.session_date; end if;
   select count(*) into v_count from (
    select r.user_id from registrations r where r.session_id=target_id and r.status='confirmed'
    union select a.user_id from permanent_assignments a where a.session_id=target_id
     and not exists(select 1 from absences ab where ab.session_id=a.session_id and ab.user_id=a.user_id and ab.not_coming=true)
     and not exists(select 1 from registrations r where r.session_id=a.session_id and r.user_id=a.user_id and r.status='cancelled')
   ) occupied where user_id<>change.user_id;
   if v_count>=v_limit then raise exception 'Court % is full on %',change.requested_court,source.session_date; end if;
   select * into reg from registrations where session_id=source.id and user_id=change.user_id;
   insert into permanent_assignments(user_id,session_id) values(change.user_id,target_id) on conflict do nothing;
   insert into absences(user_id,session_id,not_coming)
   select user_id,target_id,not_coming from absences where user_id=change.user_id and session_id=source.id
   on conflict(user_id,session_id) do update set not_coming=absences.not_coming or excluded.not_coming;
   insert into registrations(user_id,session_id,status,payment_status,registration_type,player_level,registered_at)
   values(change.user_id,target_id,coalesce(reg.status,'confirmed'),coalesce(reg.payment_status,'paid'),'season',reg.player_level,coalesce(reg.registered_at,now()))
   on conflict(user_id,session_id) do update set status=excluded.status,payment_status=excluded.payment_status,registration_type='season',player_level=excluded.player_level;
   delete from permanent_roster_courts where user_id=change.user_id and session_id in (source.id,target_id);
   delete from permanent_assignments where user_id=change.user_id and session_id=source.id;
   update registrations set status='cancelled' where user_id=change.user_id and session_id=source.id and status is distinct from 'cancelled';
  end loop;
  update recurring_permanent_requests set court=change.requested_court where user_id=change.user_id and recurring_schedule_id=change.recurring_schedule_id;
  select full_name into v_name from profiles where id=change.user_id;
  update legacy_court_allocations set court=change.requested_court where recurring_schedule_id=change.recurring_schedule_id and player_name=v_name;
 end if;
 update season_court_change_requests set status=p_status,reviewed_at=now(),reviewed_by=auth.uid(),updated_at=now() where id=change.id;
end $function$;
REVOKE ALL ON FUNCTION public.request_my_season_court_change(bigint,text) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.admin_review_season_court_change(bigint,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.request_my_season_court_change(bigint,text) TO authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.admin_review_season_court_change(bigint,text) TO authenticated,service_role;
CREATE INDEX season_court_change_schedule ON public.season_court_change_requests(recurring_schedule_id);
CREATE INDEX season_court_change_reviewer ON public.season_court_change_requests(reviewed_by);