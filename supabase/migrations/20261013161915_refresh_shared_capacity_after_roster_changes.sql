CREATE OR REPLACE FUNCTION public.get_volleyball_activity_capacity(p_session_id bigint)
RETURNS TABLE(activity_ids bigint[],occupied integer,total_capacity integer)
LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path TO 'public'
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

