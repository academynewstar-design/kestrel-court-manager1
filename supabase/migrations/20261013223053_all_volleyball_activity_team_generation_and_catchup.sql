CREATE OR REPLACE FUNCTION public.generate_session_teams(p_session_id bigint)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare n integer; t integer;
begin
 if auth.uid() is null or not coalesce(public.is_admin(),false) then raise exception 'Admin only'; end if;
 if exists(select 1 from public.sessions s join public.sports sp on sp.id=s.sport_id join public.locations l on l.id=s.location_id where s.id=p_session_id and sp.name='volleyball' ) then
  t:=public.generate_volleyball_activity_teams(p_session_id);
  if t=0 then raise exception 'At least 12 attending players are required'; end if;
  return t;
 end if;
 perform 1 from public.sessions where id=p_session_id for update;
 select count(*) into n from (
 select user_id from public.registrations where session_id=p_session_id and status='confirmed'
 union
 select pa.user_id from public.permanent_assignments pa left join public.absences a on a.user_id=pa.user_id and a.session_id=pa.session_id where pa.session_id=p_session_id and not coalesce(a.not_coming,false)
 ) players;
 if n<12 then raise exception 'At least 12 attending players required; found %',n; end if;
 t:=case when n>=16 then 3 else 2 end;
 delete from public.session_teams where session_id=p_session_id;
 insert into public.session_teams(session_id,user_id,team_no)
 select p_session_id,user_id,1+mod(row_number() over(order by coalesce(player_level,'intermediate'),user_id)::integer-1,t)
 from (
 select distinct on (u.user_id) u.user_id,u.player_level from (
 select user_id,player_level from public.registrations where session_id=p_session_id and status='confirmed'
 union all
 select pa.user_id,r.player_level from public.permanent_assignments pa left join public.absences a on a.user_id=pa.user_id and a.session_id=pa.session_id left join public.registrations r on r.user_id=pa.user_id and r.session_id=pa.session_id where pa.session_id=p_session_id and not coalesce(a.not_coming,false)
 ) u order by u.user_id
 ) players;
 return t;
end $function$;
CREATE OR REPLACE FUNCTION public.auto_generate_due_volleyball_teams()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO public AS $function$
declare x record; ids bigint[]; generated timestamptz;
begin
 for x in
 select min(s.id) id, ((s.session_date+s.start_time) at time zone 'America/Toronto') starts_at
 from sessions s join sports sp on sp.id=s.sport_id
 where sp.name='volleyball'
 and ((s.session_date+s.start_time) at time zone 'America/Toronto') > now()
 and ((s.session_date+s.start_time) at time zone 'America/Toronto') <= now()+interval '1 hour'
 group by s.sport_id,s.location_id,s.session_date,s.start_time,s.end_time
 loop
 select activity_ids into ids from public.get_volleyball_activity_capacity(x.id);
 select min(st.generated_at) into generated from session_teams st where st.session_id=any(ids);
 if generated is null
 or exists(select 1 from unnest(ids) sid where not exists(select 1 from session_teams st where st.session_id=sid))
 or (x.starts_at<=now()+interval '15 minutes' and generated<x.starts_at-interval '15 minutes') then
 perform public.generate_volleyball_activity_teams(x.id);
 end if;
 end loop;
end $function$;
revoke all on function public.auto_generate_due_volleyball_teams() from public,anon,authenticated;
grant execute on function public.auto_generate_due_volleyball_teams() to service_role;