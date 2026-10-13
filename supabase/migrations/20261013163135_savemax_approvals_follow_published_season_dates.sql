DO $update$
DECLARE v_schedule public.recurring_schedules%rowtype;
BEGIN
 SELECT rs.* INTO STRICT v_schedule FROM recurring_schedules rs JOIN locations l ON l.id=rs.location_id
 JOIN sports sp ON sp.id=rs.sport_id WHERE rs.source_key='soccer_savemax_sat_1615' AND sp.name='soccer' AND l.name ILIKE '%save%';
 UPDATE recurring_schedules SET weekday='Saturday',start_time='16:15',end_time='17:45',
 schedule_label='Saturday 4:15–5:45 PM · Nov 7, 2026–Mar 13, 2027 · First game Sunday Nov 1, 9–10:30 AM'
 WHERE id=v_schedule.id;

 -- Keep old records and their history, but close dates outside the updated season and redundant court records.
 UPDATE sessions SET status='closed',availability_status='unavailable',dropin_enabled=false,dropin_spots=0,capacity=0
 WHERE location_id=v_schedule.location_id AND sport_id=v_schedule.sport_id
 AND session_date>=(now() AT TIME ZONE 'America/Toronto')::date
 AND (session_date<'2026-11-01' OR session_date>'2027-03-13' OR court<>'General');

 INSERT INTO sessions(sport_id,location_id,session_date,start_time,end_time,capacity,price,payment_email,payment_first,
 status,court,recurring_schedule_id,dropin_enabled,dropin_spots,availability_status,registration_open_at,payment_deadline,registration_deadline)
 SELECT v_schedule.sport_id,v_schedule.location_id,d,
 CASE WHEN d='2026-11-01' THEN time '09:00' ELSE time '16:15' END,
 CASE WHEN d='2026-11-01' THEN time '10:30' ELSE time '17:45' END,
 21,16,'academynewstar@gmail.com',false,'open','General',v_schedule.id,true,21,'available',
 ((d+CASE WHEN d='2026-11-01' THEN time '09:00' ELSE time '16:15' END)-interval '6 days') AT TIME ZONE 'America/Toronto',
 ((d+CASE WHEN d='2026-11-01' THEN time '09:00' ELSE time '16:15' END)-interval '24 hours') AT TIME ZONE 'America/Toronto',null
 FROM (SELECT date '2026-11-01' d UNION ALL SELECT generate_series(date '2026-11-07',date '2027-03-13',interval '7 days')::date) dates
 ON CONFLICT(recurring_schedule_id,session_date,court) WHERE recurring_schedule_id IS NOT NULL
 DO UPDATE SET start_time=excluded.start_time,end_time=excluded.end_time,capacity=excluded.capacity,price=excluded.price,
 payment_email=excluded.payment_email,status='open',dropin_enabled=true,dropin_spots=21,availability_status='available',
 registration_open_at=excluded.registration_open_at,payment_deadline=excluded.payment_deadline,registration_deadline=null;

 INSERT INTO permanent_assignments(user_id,session_id)
 SELECT r.user_id,s.id FROM recurring_permanent_requests r JOIN profiles p ON p.id=r.user_id
 JOIN sessions s ON s.recurring_schedule_id=r.recurring_schedule_id AND s.court='General'
 WHERE r.recurring_schedule_id=v_schedule.id AND r.status='approved' AND p.player_type_status='approved'
 AND s.status='open' AND s.availability_status='available' AND s.session_date BETWEEN '2026-11-01' AND '2027-03-13'
 ON CONFLICT DO NOTHING;

 INSERT INTO registrations(user_id,session_id,status,payment_status,registration_type,player_level,registered_at)
 SELECT r.user_id,s.id,'confirmed','paid','season',r.player_level,coalesce(r.reviewed_at,r.created_at,now())
 FROM recurring_permanent_requests r JOIN profiles p ON p.id=r.user_id
 JOIN sessions s ON s.recurring_schedule_id=r.recurring_schedule_id AND s.court='General'
 WHERE r.recurring_schedule_id=v_schedule.id AND r.status='approved' AND p.player_type_status='approved'
 AND s.status='open' AND s.availability_status='available' AND s.session_date BETWEEN '2026-11-01' AND '2027-03-13'
 ON CONFLICT(user_id,session_id) DO NOTHING;
END $update$;
CREATE OR REPLACE FUNCTION public.admin_review_recurring_permanent_request(p_request_id bigint, p_status text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r public.recurring_permanent_requests%rowtype; v_schedule record; v_date date; v_session_id bigint; v_dow integer; v_i integer;
begin
 if auth.uid() is null or not exists(select 1 from profiles where id=auth.uid() and is_admin=true) then raise exception 'Admin access required'; end if;
 if p_status not in ('approved','rejected') then raise exception 'Invalid review status'; end if;
 select * into r from recurring_permanent_requests where id=p_request_id and status='pending' for update;
 if not found then raise exception 'Season request not found or already reviewed'; end if;
 update recurring_permanent_requests set status=p_status,reviewed_at=now(),reviewed_by=auth.uid() where id=r.id;
 if p_status='rejected' then return; end if;
 select * into v_schedule from recurring_schedules where id=r.recurring_schedule_id and active=true;
 if not found then raise exception 'Recurring schedule is no longer active'; end if;
 if v_schedule.source_key='soccer_savemax_sat_1615' then
  update recurring_permanent_requests set court='General' where id=r.id;
  for v_session_id in select s.id from sessions s where s.recurring_schedule_id=v_schedule.id and s.court='General'
   and s.status='open' and s.availability_status='available'
   and ((s.session_date+s.start_time) at time zone 'America/Toronto')>now() order by s.session_date loop
   insert into permanent_assignments(user_id,session_id) values(r.user_id,v_session_id) on conflict do nothing;
   insert into registrations(user_id,session_id,status,payment_status,registration_type,player_level)
   values(r.user_id,v_session_id,'confirmed','paid','season',r.player_level)
   on conflict(user_id,session_id) do update set status='confirmed',payment_status='paid',registration_type='season';
  end loop;
  update profiles set player_type='permanent',requested_player_type='permanent',player_type_status='approved' where id=r.user_id;
  return;
 end if;
 v_dow:=case lower(v_schedule.weekday) when 'sunday' then 0 when 'monday' then 1 when 'tuesday' then 2 when 'wednesday' then 3 when 'thursday' then 4 when 'friday' then 5 when 'saturday' then 6 end;
 v_date:=current_date+((v_dow-extract(dow from current_date)::int+7)%7);
 for v_i in 0..11 loop
   insert into sessions(sport_id,location_id,session_date,start_time,end_time,capacity,price,status,court,recurring_schedule_id)
   values(v_schedule.sport_id,v_schedule.location_id,v_date+(v_i*7),v_schedule.start_time,v_schedule.end_time,18,0,'open',coalesce(nullif(r.court,''),'General'),v_schedule.id)
   on conflict(recurring_schedule_id,session_date,court) where recurring_schedule_id is not null do update set start_time=excluded.start_time,end_time=excluded.end_time returning id into v_session_id;
   insert into permanent_assignments(user_id,session_id) values(r.user_id,v_session_id) on conflict do nothing;
   insert into registrations(user_id,session_id,status,payment_status) values(r.user_id,v_session_id,'confirmed','paid') on conflict(user_id,session_id) do update set status='confirmed',payment_status='paid';
 end loop;
 update profiles set player_type='permanent',requested_player_type='permanent',player_type_status='approved' where id=r.user_id;
end $function$;
CREATE OR REPLACE FUNCTION public.admin_set_permanent_choices(p_user_id uuid, p_choices jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_admin uuid:=auth.uid(); v_item jsonb; v_schedule record; v_date date; v_session_id bigint; v_dow integer; v_i integer; v_court text; v_name text;
begin
 if v_admin is null or not exists(select 1 from profiles where id=v_admin and is_admin=true) then raise exception 'Admin access required'; end if;
 if not exists(select 1 from profiles where id=p_user_id and player_type='permanent' and player_type_status='approved') then raise exception 'Player must be an approved Permanent player'; end if;
 if p_choices is null or jsonb_typeof(p_choices)<>'array' or jsonb_array_length(p_choices)<1 then raise exception 'Choose at least 1 regular activity'; end if;
 select full_name into v_name from profiles where id=p_user_id;
 for v_item in select value from jsonb_array_elements(p_choices) loop
  select * into v_schedule from recurring_schedules where id=(v_item->>'recurring_schedule_id')::bigint and active=true;
  if not found then raise exception 'Invalid recurring schedule'; end if;
  v_court:=case when v_schedule.source_key='soccer_savemax_sat_1615' then 'General' when nullif(v_item->>'court','') is not null then v_item->>'court' else 'Volleyball' end;
  insert into recurring_permanent_requests(user_id,recurring_schedule_id,court,status,reviewed_at,reviewed_by)
   values(p_user_id,v_schedule.id,v_court,'approved',now(),v_admin)
   on conflict(user_id,recurring_schedule_id) do update set court=excluded.court,status='approved',reviewed_at=now(),reviewed_by=v_admin;
  delete from legacy_court_allocations where recurring_schedule_id=v_schedule.id and player_name=v_name and source_sheet='Portal registration';
  insert into legacy_court_allocations(recurring_schedule_id,court,player_name,source_sheet) values(v_schedule.id,v_court,v_name,'Portal registration');
  if v_schedule.source_key='soccer_savemax_sat_1615' then
   for v_session_id in select s.id from sessions s where s.recurring_schedule_id=v_schedule.id and s.court='General'
    and s.status='open' and s.availability_status='available'
    and ((s.session_date+s.start_time) at time zone 'America/Toronto')>now() order by s.session_date loop
    insert into permanent_assignments(user_id,session_id) values(p_user_id,v_session_id) on conflict do nothing;
    insert into registrations(user_id,session_id,status,payment_status,registration_type)
    values(p_user_id,v_session_id,'confirmed','paid','season')
    on conflict(user_id,session_id) do update set status='confirmed',payment_status='paid',registration_type='season';
   end loop;
   continue;
  end if;
  v_dow:=case lower(v_schedule.weekday) when 'sunday' then 0 when 'monday' then 1 when 'tuesday' then 2 when 'wednesday' then 3 when 'thursday' then 4 when 'friday' then 5 when 'saturday' then 6 end;
  v_date:=current_date+((v_dow-extract(dow from current_date)::int+7)%7);
  for v_i in 0..11 loop
   insert into sessions(sport_id,location_id,session_date,start_time,end_time,capacity,price,status,court,recurring_schedule_id)
   values(v_schedule.sport_id,v_schedule.location_id,v_date+(v_i*7),v_schedule.start_time,v_schedule.end_time,18,0,'open',v_court,v_schedule.id)
   on conflict(recurring_schedule_id,session_date,court) where recurring_schedule_id is not null do update set start_time=excluded.start_time,end_time=excluded.end_time returning id into v_session_id;
   insert into permanent_assignments(user_id,session_id) values(p_user_id,v_session_id) on conflict do nothing;
   insert into registrations(user_id,session_id,status,payment_status) values(p_user_id,v_session_id,'confirmed','paid') on conflict(user_id,session_id) do update set status='confirmed',payment_status='paid';
  end loop;
 end loop;
end $function$;