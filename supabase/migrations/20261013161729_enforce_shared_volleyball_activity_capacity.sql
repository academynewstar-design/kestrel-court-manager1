CREATE OR REPLACE FUNCTION public.get_volleyball_activity_capacity(p_session_id bigint)
RETURNS TABLE(activity_ids bigint[],occupied integer,total_capacity integer)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
with related as (
 select s.id,s.capacity from sessions target join sports sp on sp.id=target.sport_id
 join sessions s on s.id=target.id or (
  sp.name='volleyball' and s.sport_id=target.sport_id and s.location_id=target.location_id
  and s.session_date=target.session_date and s.start_time=target.start_time and s.end_time=target.end_time)
 where target.id=p_session_id
), attendees as (
 select r.user_id from registrations r join related s on s.id=r.session_id
 where r.status='confirmed' and not exists(select 1 from absences a where a.session_id=r.session_id and a.user_id=r.user_id and a.not_coming=true)
 union
 select pa.user_id from permanent_assignments pa join related s on s.id=pa.session_id
 where not exists(select 1 from absences a where a.session_id=pa.session_id and a.user_id=pa.user_id and a.not_coming=true)
 and not exists(select 1 from registrations r where r.session_id=pa.session_id and r.user_id=pa.user_id and r.status='cancelled')
)
select (select array_agg(id order by id) from related),(select count(*)::integer from attendees),(select min(capacity)::integer from related)
$function$;
REVOKE ALL ON FUNCTION public.get_volleyball_activity_capacity(bigint) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.get_volleyball_activity_capacity(bigint) TO service_role;

CREATE OR REPLACE FUNCTION public.register_dropin(p_session_id bigint, p_player_level text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare s public.sessions%rowtype; confirmed_count integer; season_count integer; effective_capacity integer; v_ids bigint[];
begin
 if auth.uid() is null then raise exception 'You must be signed in'; end if;
 if p_player_level not in ('low_intermediate','intermediate','advanced') then raise exception 'Please select a valid player level'; end if;
 select * into s from public.sessions where id=p_session_id for update;
 if not found then raise exception 'Session not found'; end if;
 if exists(select 1 from public.sports sp where sp.id=s.sport_id and sp.name='volleyball') then
 select activity_ids into v_ids from public.get_volleyball_activity_capacity(p_session_id);
 perform pg_advisory_xact_lock(71107,v_ids[1]::integer);
 if exists(select 1 from public.registrations r where r.user_id=auth.uid() and r.session_id=any(v_ids) and r.status in ('pending','confirmed','waitlist')) then return 'already_registered'; end if;
 end if;
 if not coalesce(s.dropin_enabled,false) or coalesce(s.dropin_spots,0)<=0 then raise exception 'Drop-in is not available for this session'; end if;
 if s.status='closed' or s.availability_status='unavailable' then raise exception 'This activity is unavailable'; end if;
 if ((s.session_date+s.start_time) at time zone 'America/Toronto')<=now() then raise exception 'This session has already started'; end if;
 if s.registration_open_at is not null and now()<s.registration_open_at and not coalesce(s.registration_open_override,false) then raise exception 'Registration opens at %',to_char(s.registration_open_at at time zone 'America/Toronto','FMDay, FMMonth DD at HH12:MI AM'); end if;
 if s.registration_deadline is not null and now()>s.registration_deadline then raise exception 'Registration deadline has passed'; end if;
 if exists(select 1 from public.registrations where user_id=auth.uid() and session_id=p_session_id and status in ('pending','confirmed','waitlist')) then return 'already_registered'; end if;
 select count(*) into confirmed_count from public.registrations where session_id=p_session_id and status='confirmed';
 select count(*) into season_count from public.permanent_assignments pa left join public.absences a on a.session_id=pa.session_id and a.user_id=pa.user_id where pa.session_id=p_session_id and not coalesce(a.not_coming,false) and not exists(select 1 from public.registrations r where r.session_id=p_session_id and r.user_id=pa.user_id);
 effective_capacity:=least(coalesce(s.capacity,0),coalesce(s.dropin_spots,s.capacity,0)+season_count);
 if exists(select 1 from public.sports sp where sp.id=s.sport_id and sp.name='volleyball') then
 select occupied,total_capacity into confirmed_count,effective_capacity from public.get_volleyball_activity_capacity(p_session_id);
 season_count:=0;
 end if;
 if confirmed_count+season_count>=effective_capacity then
 insert into public.registrations(user_id,session_id,status,payment_status,player_level) values(auth.uid(),p_session_id,'waitlist','unpaid',p_player_level)
 on conflict(user_id,session_id) do update set status='waitlist',payment_status='unpaid',player_level=excluded.player_level;
 return 'waitlist';end if;
 insert into public.registrations(user_id,session_id,status,payment_status,player_level) values(auth.uid(),p_session_id,'confirmed','unpaid',p_player_level)
 on conflict(user_id,session_id) do update set status='confirmed',payment_status='unpaid',player_level=excluded.player_level;
 return 'confirmed';
end $function$;

CREATE OR REPLACE FUNCTION public.rejoin_my_session(p_session_id bigint)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
 v_uid uuid := auth.uid();
 v_s public.sessions%rowtype;
 v_season boolean;
 v_existing text;
 v_occupied integer;
 v_limit integer;
 v_level text; v_ids bigint[];
begin
 if v_uid is null then raise exception 'Sign in required'; end if;
 select * into v_s from public.sessions where id=p_session_id for update;
 if not found then raise exception 'Session not found'; end if;
 if exists(select 1 from public.sports sp where sp.id=v_s.sport_id and sp.name='volleyball') then
 select activity_ids into v_ids from public.get_volleyball_activity_capacity(p_session_id);
 perform pg_advisory_xact_lock(71107,v_ids[1]::integer);
 end if;
 if v_s.session_date < (now() at time zone 'America/Toronto')::date
   or (v_s.session_date = (now() at time zone 'America/Toronto')::date and v_s.start_time <= (now() at time zone 'America/Toronto')::time)
 then raise exception 'Session already started'; end if;
 if v_s.status='closed' or v_s.availability_status='unavailable' then raise exception 'Session unavailable'; end if;
 select exists(select 1 from public.permanent_assignments pa where pa.session_id=p_session_id and pa.user_id=v_uid)
 into v_season;
 select status,player_level into v_existing,v_level from public.registrations
 where session_id=p_session_id and user_id=v_uid for update;
 if v_season then
   if not exists(select 1 from public.profiles where id=v_uid and player_type='permanent' and player_type_status='approved') then
     raise exception 'Season approval required';
   end if;
   if not coalesce((select not_coming from public.absences where user_id=v_uid and session_id=p_session_id),false)
      and coalesce(v_existing,'confirmed')='confirmed' then return 'already_registered'; end if;
 else
   if not exists(select 1 from public.profiles where id=v_uid and player_type='dropin' and player_type_status='approved')
     then raise exception 'Drop-in approval required'; end if;
   if v_existing is null or v_existing not in ('cancelled','removed','not_going')
     then raise exception 'No cancelled registration to rejoin'; end if;
   if not coalesce(v_s.dropin_enabled,false) then raise exception 'Drop-in unavailable'; end if;
   if v_s.registration_open_at is not null and now()<v_s.registration_open_at and not coalesce(v_s.registration_open_override,false)
     then raise exception 'Registration is not open yet'; end if;
   if v_s.registration_deadline is not null and now()>v_s.registration_deadline then raise exception 'Registration deadline has passed'; end if;
 end if;
 select count(*) into v_occupied from (
   select r.user_id from public.registrations r where r.session_id=p_session_id and r.status='confirmed'
   union
   select pa.user_id from public.permanent_assignments pa
     left join public.absences a on a.session_id=pa.session_id and a.user_id=pa.user_id
     where pa.session_id=p_session_id and not coalesce(a.not_coming,false)
       and not exists(select 1 from public.registrations r where r.session_id=p_session_id and r.user_id=pa.user_id and r.status in ('cancelled','removed','not_going'))
 ) occupied;
 v_limit:=greatest(coalesce(v_s.capacity,0),0);
 if v_ids is not null then select occupied,total_capacity into v_occupied,v_limit from public.get_volleyball_activity_capacity(p_session_id); end if;
 if v_occupied>=v_limit then return 'full'; end if;
 if v_season then
   insert into public.absences(user_id,session_id,not_coming) values(v_uid,p_session_id,false)
     on conflict(user_id,session_id) do update set not_coming=false;
   insert into public.registrations(user_id,session_id,status,payment_status,registration_type)
     values(v_uid,p_session_id,'confirmed','paid','season')
     on conflict(user_id,session_id) do update set status='confirmed',registration_type='season',payment_status='paid';
 else
   insert into public.registrations(user_id,session_id,status,payment_status,player_level,registration_type)
     values(v_uid,p_session_id,'confirmed','unpaid',v_level,'dropin')
     on conflict(user_id,session_id) do update set status='confirmed',payment_status='unpaid',registered_at=now();
 end if;
 return 'confirmed';
end $function$;

CREATE OR REPLACE FUNCTION public.admin_add_player_to_activity(p_session_id bigint, p_user_id uuid)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ DECLARE sess public.sessions%ROWTYPE; existing public.registrations%ROWTYPE; active_count integer; result_status text; v_ids bigint[]; BEGIN IF auth.uid() IS NULL OR NOT EXISTS(SELECT 1 FROM public.profiles WHERE id=auth.uid() AND is_admin=true) THEN RAISE EXCEPTION 'Admin access required'; END IF; SELECT * INTO sess FROM public.sessions WHERE id=p_session_id FOR UPDATE; IF NOT FOUND THEN RAISE EXCEPTION 'Activity not found'; END IF; IF NOT EXISTS(SELECT 1 FROM public.profiles WHERE id=p_user_id AND player_type_status='approved') THEN RAISE EXCEPTION 'Player not approved or not found'; END IF; IF EXISTS(select 1 from public.sports sp where sp.id=sess.sport_id and sp.name='volleyball') THEN
 SELECT activity_ids INTO v_ids FROM public.get_volleyball_activity_capacity(p_session_id);
 PERFORM pg_advisory_xact_lock(71107,v_ids[1]::integer);
 IF EXISTS(select 1 from public.registrations r where r.session_id=any(v_ids) and r.user_id=p_user_id and r.status in ('confirmed','pending','waitlist')) THEN RAISE EXCEPTION 'Player is already registered for this activity'; END IF;
 END IF; SELECT * INTO existing FROM public.registrations WHERE session_id=p_session_id AND user_id=p_user_id; IF FOUND AND existing.status IN ('confirmed','pending','waitlist') THEN RAISE EXCEPTION 'Player is already registered for this activity'; END IF; SELECT count(*) INTO active_count FROM public.registrations WHERE session_id=p_session_id AND status='confirmed'; IF v_ids IS NOT NULL THEN SELECT occupied,total_capacity INTO active_count,sess.capacity FROM public.get_volleyball_activity_capacity(p_session_id); END IF; result_status:=CASE WHEN active_count>=sess.capacity THEN 'waitlist' ELSE 'confirmed' END; INSERT INTO public.registrations(user_id,session_id,status,payment_status,registration_type) VALUES(p_user_id,p_session_id,result_status,'unpaid','dropin') ON CONFLICT(user_id,session_id) DO UPDATE SET status=excluded.status,payment_status=excluded.payment_status,registration_type='dropin'; RETURN result_status; END $function$;

CREATE OR REPLACE FUNCTION public.kestrel_promote_waitlist_on_vacancy()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ declare v_capacity integer; v_next bigint; v_occupied integer; v_ids bigint[]; begin if old.status <> 'confirmed' or new.status = 'confirmed' then return new; end if; select capacity into v_capacity from public.sessions where id=old.session_id for update; if v_capacity is null then return new; end if; select array[old.session_id] into v_ids;
 if exists(select 1 from public.sessions s join public.sports sp on sp.id=s.sport_id where s.id=old.session_id and sp.name='volleyball') then
 select activity_ids into v_ids from public.get_volleyball_activity_capacity(old.session_id);
 perform pg_advisory_xact_lock(71107,v_ids[1]::integer);
 select occupied,total_capacity into v_occupied,v_capacity from public.get_volleyball_activity_capacity(old.session_id);
 else select count(*) into v_occupied from public.registrations where session_id=old.session_id and status='confirmed'; end if;
 if v_occupied>=v_capacity then return new; end if; select r.id into v_next from public.registrations r join public.profiles p on p.id=r.user_id where r.session_id=any(v_ids) and r.status='waitlist' and not exists(select 1 from public.registrations other where other.user_id=r.user_id and other.session_id=any(v_ids) and other.status='confirmed') and p.player_type_status='approved' order by r.registered_at,r.id limit 1 for update of r; if v_next is not null then update public.registrations set status='confirmed',payment_status='unpaid' where id=v_next; end if; return new; end; $function$;

CREATE OR REPLACE FUNCTION public.get_dropin_session_availability(p_session_ids bigint[])
 RETURNS TABLE(session_id bigint, occupied integer, total_capacity integer, is_full boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
with relevant as (select id,capacity,dropin_spots from public.sessions where id=any(p_session_ids) and dropin_enabled=true),
counts as (select s.id,
(select count(*) from public.registrations r where r.session_id=s.id and r.status='confirmed')::integer as confirmed,
(select count(*) from public.permanent_assignments pa where pa.session_id=s.id and not exists(select 1 from public.absences a where a.session_id=s.id and a.user_id=pa.user_id and a.not_coming=true) and not exists(select 1 from public.registrations r where r.session_id=s.id and r.user_id=pa.user_id))::integer as season,
s.capacity,s.dropin_spots from relevant s)
select c.id,
 case when sp.name='volleyball' then a.occupied else c.confirmed+c.season end,
 case when sp.name='volleyball' then a.total_capacity else least(coalesce(c.capacity,0),coalesce(c.dropin_spots,c.capacity,0)+c.season) end,
 case when sp.name='volleyball' then a.occupied>=a.total_capacity else c.confirmed+c.season>=least(coalesce(c.capacity,0),coalesce(c.dropin_spots,c.capacity,0)+c.season) end
 from counts c join public.sessions target on target.id=c.id join public.sports sp on sp.id=target.sport_id
 cross join lateral public.get_volleyball_activity_capacity(c.id) a
$function$;