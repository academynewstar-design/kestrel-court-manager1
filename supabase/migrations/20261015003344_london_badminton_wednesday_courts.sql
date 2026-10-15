-- London La Pommeraie badminton: Wednesday 7–9 PM, three courts, six players per court.
insert into public.recurring_schedules(source_key,sport_id,location_id,weekday,schedule_label,active,start_time,end_time)
select 'london-badminton-wednesday-7-9',sp.id,l.id,'Wednesday','Wednesday 7:00 PM to 9:00 PM',true,'19:00','21:00'
from public.sports sp cross join public.locations l where sp.name='badminton' and l.name='École élémentaire La Pommeraie' and l.city='London'
on conflict(source_key) do update set active=true,start_time=excluded.start_time,end_time=excluded.end_time;
insert into public.sessions(sport_id,location_id,session_date,start_time,end_time,capacity,price,payment_email,status,court,recurring_schedule_id,dropin_enabled,dropin_spots,registration_open_at,registration_deadline,payment_deadline,availability_status)
select r.sport_id,r.location_id,'2026-10-21'::date+7*w.n,'19:00','21:00',6,6,'academynewstar@gmail.com','open','Court '||c.n,r.id,c.n<>1,case when c.n=1 then 0 else 6 end,null,null,
(('2026-10-21'::date+7*w.n+time '19:00') at time zone 'America/Toronto')-interval '18 hours','available'
from public.recurring_schedules r cross join generate_series(0,11) w(n) cross join generate_series(1,3) c(n)
where r.source_key='london-badminton-wednesday-7-9'
on conflict(recurring_schedule_id,session_date,court) where recurring_schedule_id is not null do nothing;
insert into public.exclusive_court_bookings(session_id,lead_name,guest_count,notes,created_by,previous_dropin_enabled)
select s.id,'Marjoon',0,'Fixed weekly Court 1 reservation. Maximum 6 players; guests not yet provided. Account not linked.',p.id,false
from public.sessions s join public.recurring_schedules r on r.id=s.recurring_schedule_id
cross join public.profiles p
where r.source_key='london-badminton-wednesday-7-9' and s.court='Court 1'
and p.email='academynewstar@gmail.com' and p.is_admin=true
and not exists(select 1 from public.exclusive_court_bookings b where b.session_id=s.id and b.cancelled_at is null);
insert into public.legacy_court_allocations(recurring_schedule_id,court,player_name,source_sheet)
select r.id,'Court 1','Marjoon — fixed full court','Organizer assignment' from public.recurring_schedules r
where r.source_key='london-badminton-wednesday-7-9'
and not exists(select 1 from public.legacy_court_allocations a where a.recurring_schedule_id=r.id and a.court='Court 1' and a.player_name='Marjoon — fixed full court');

-- Enforce London La Pommeraie badminton court choices and expose its group reservations.
DO $patch$
declare definition text; original text; function_name text;
begin
 foreach function_name in array array['save_my_permanent_choices','admin_set_permanent_choices'] loop
  select pg_get_functiondef(p.oid) into definition from pg_proc p where p.pronamespace='public'::regnamespace and p.proname=function_name;
  if definition is null then raise exception 'Missing function %',function_name; end if;
  if position('London badminton: Court 1 is reserved for Marjoon' in definition)=0 then
   original:=definition;
   definition:=replace(definition,'insert into recurring_permanent_requests',
    'if v_schedule.source_key=''london-badminton-wednesday-7-9'' and v_court not in (''Court 2'',''Court 3'') then raise exception ''London badminton: Court 1 is reserved for Marjoon. Choose Court 2 or Court 3.''; end if;
  insert into recurring_permanent_requests');
   if definition=original then raise exception 'Could not locate Season request insert in %',function_name; end if;
   execute definition;
  end if;
 end loop;
 select pg_get_functiondef(p.oid) into definition from pg_proc p where p.pronamespace='public'::regnamespace and p.proname='admin_manage_exclusive_court_booking';
 if position('Kitchener or London badminton court' in definition)=0 then
  original:=definition;
  definition:=replace(definition,
   'if s.location_id<>17 or s.court not in (''Court 1'',''Court 2'',''Court 3'',''Court 4'',''Court 5'',''Court 6'') then raise exception ''This booking feature is currently for Kitchener badminton courts''; end if;',
   'if not exists(select 1 from public.sports where id=s.sport_id and name=''badminton'') or not ((s.location_id=17 and s.court in (''Court 1'',''Court 2'',''Court 3'',''Court 4'',''Court 5'',''Court 6'')) or (s.location_id=3 and s.court in (''Court 1'',''Court 2'',''Court 3''))) then raise exception ''Choose a Kitchener or London badminton court''; end if;');
  if definition=original then raise exception 'Could not locate group court validation'; end if;
  execute definition;
 end if;
 select pg_get_functiondef(p.oid) into definition from pg_proc p where p.pronamespace='public'::regnamespace and p.proname='request_my_season_court_change';
 if position('London badminton: choose Court 2 or Court 3' in definition)=0 then
  original:=definition;
  definition:=replace(definition,'if p_court=coalesce(v_current',
   'if exists(select 1 from recurring_schedules where id=p_recurring_schedule_id and source_key=''london-badminton-wednesday-7-9'') and p_court not in (''Court 2'',''Court 3'') then raise exception ''London badminton: choose Court 2 or Court 3; Court 1 is reserved for Marjoon.''; end if;
 if p_court=coalesce(v_current');
  if definition=original then raise exception 'Could not locate court change validation'; end if;
  execute definition;
 end if;
end $patch$;

-- Keep six-player capacity if an approval creates another dated session later.
DO $capacity$
declare definition text; fn text;
begin
 foreach fn in array array['admin_set_permanent_choices','admin_review_recurring_permanent_request'] loop
  select pg_get_functiondef(p.oid) into definition from pg_proc p where p.pronamespace='public'::regnamespace and p.proname=fn;
  definition:=replace(definition,',18,0,''open'',',',case when v_schedule.source_key=''london-badminton-wednesday-7-9'' then 6 else 18 end,case when v_schedule.source_key=''london-badminton-wednesday-7-9'' then 6 else 0 end,''open'',');
  execute definition;
 end loop;
end $capacity$;
revoke all on function public.save_my_permanent_choices(jsonb),public.admin_set_permanent_choices(uuid,jsonb),public.admin_manage_exclusive_court_booking(bigint,text,integer,text),public.request_my_season_court_change(bigint,text) from public,anon;
grant execute on function public.save_my_permanent_choices(jsonb),public.admin_set_permanent_choices(uuid,jsonb),public.admin_manage_exclusive_court_booking(bigint,text,integer,text),public.request_my_season_court_change(bigint,text) to authenticated,service_role;
