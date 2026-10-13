CREATE OR REPLACE FUNCTION public.get_my_confirmed_session_roster(p_session_id bigint)
RETURNS TABLE(player_name text,is_me boolean)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
declare v_ids bigint[];
begin
 if auth.uid() is null or not (
  exists(select 1 from public.registrations r where r.session_id=p_session_id and r.user_id=auth.uid() and r.status='confirmed')
  or exists(select 1 from public.permanent_assignments pa where pa.session_id=p_session_id and pa.user_id=auth.uid()
   and not exists(select 1 from public.absences a where a.session_id=p_session_id and a.user_id=auth.uid() and a.not_coming=true)
   and not exists(select 1 from public.registrations r where r.session_id=p_session_id and r.user_id=auth.uid() and r.status='cancelled'))
 ) then raise exception 'You must be attending this session to view its roster'; end if;
 select array_agg(s.id) into v_ids
 from public.sessions target join public.sports sp on sp.id=target.sport_id
 join public.sessions s on s.id=target.id or (
  sp.name='volleyball' and s.sport_id=target.sport_id and s.location_id=target.location_id
  and s.session_date=target.session_date and s.start_time=target.start_time and s.end_time=target.end_time)
 where target.id=p_session_id;
 return query
 with attendees as (
  select r.user_id from public.registrations r where r.session_id=any(v_ids) and r.status='confirmed'
   and not exists(select 1 from public.absences a where a.session_id=r.session_id and a.user_id=r.user_id and a.not_coming=true)
  union
  select pa.user_id from public.permanent_assignments pa where pa.session_id=any(v_ids)
   and not exists(select 1 from public.absences a where a.session_id=pa.session_id and a.user_id=pa.user_id and a.not_coming=true)
   and not exists(select 1 from public.registrations r where r.session_id=pa.session_id and r.user_id=pa.user_id and r.status='cancelled')
 )
 select coalesce(nullif(p.full_name,''),'Player')::text,(p.id=auth.uid())
 from attendees x join public.profiles p on p.id=x.user_id order by (p.id=auth.uid()) desc,p.full_name;
end $function$;
REVOKE ALL ON FUNCTION public.get_my_confirmed_session_roster(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_my_confirmed_session_roster(bigint) TO authenticated,service_role;

CREATE OR REPLACE FUNCTION public.get_my_session_going_names(p_session_ids bigint[])
RETURNS TABLE(session_id bigint,user_id uuid,full_name text)
LANGUAGE sql SECURITY DEFINER SET search_path TO 'public'
AS $function$
with allowed as (
 select s.* from public.sessions s where s.id=any(p_session_ids)
 and auth.uid() is not null
 and ((s.session_date+s.start_time) at time zone 'America/Toronto') between now() and now()+interval '8 hours'
 and (exists(select 1 from public.registrations r where r.session_id=s.id and r.user_id=auth.uid() and r.status='confirmed')
 or exists(select 1 from public.permanent_assignments pa where pa.session_id=s.id and pa.user_id=auth.uid()
  and not exists(select 1 from public.absences ab where ab.session_id=pa.session_id and ab.user_id=pa.user_id and ab.not_coming=true)
  and not exists(select 1 from public.registrations r where r.session_id=pa.session_id and r.user_id=pa.user_id and r.status='cancelled')))
), related as (
 select a.id as requested_id,s.id from allowed a join public.sports sp on sp.id=a.sport_id
 join public.sessions s on s.id=a.id or (
  sp.name='volleyball' and s.sport_id=a.sport_id and s.location_id=a.location_id
  and s.session_date=a.session_date and s.start_time=a.start_time and s.end_time=a.end_time)
), attendees as (
 select a.requested_id,r.user_id from related a join public.registrations r on r.session_id=a.id
 where r.status='confirmed' and not exists(select 1 from public.absences ab where ab.session_id=r.session_id and ab.user_id=r.user_id and ab.not_coming=true)
 union
 select a.requested_id,pa.user_id from related a join public.permanent_assignments pa on pa.session_id=a.id
 where not exists(select 1 from public.absences ab where ab.session_id=pa.session_id and ab.user_id=pa.user_id and ab.not_coming=true)
 and not exists(select 1 from public.registrations r where r.session_id=pa.session_id and r.user_id=pa.user_id and r.status='cancelled')
)
select x.requested_id,x.user_id,coalesce(p.full_name,'Player') from attendees x join public.profiles p on p.id=x.user_id
$function$;
REVOKE ALL ON FUNCTION public.get_my_session_going_names(bigint[]) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_my_session_going_names(bigint[]) TO authenticated,service_role;
