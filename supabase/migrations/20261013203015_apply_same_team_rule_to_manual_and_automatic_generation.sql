CREATE OR REPLACE FUNCTION public.generate_session_teams(p_session_id bigint)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare n integer; t integer;
begin
 if auth.uid() is null or not coalesce(public.is_admin(),false) then raise exception 'Admin only'; end if;
 if exists(select 1 from public.sessions s join public.sports sp on sp.id=s.sport_id join public.locations l on l.id=s.location_id where s.id=p_session_id and sp.name='volleyball' and l.city='Mississauga') then
  t:=public.generate_mississauga_volleyball_teams(p_session_id);
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
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare x record; n integer; t integer;
begin
 for x in select s.id from public.sessions s join public.sports sp on sp.id=s.sport_id where sp.name='volleyball' and (((s.session_date+s.start_time) at time zone 'America/Toronto') between now()+interval '55 minutes' and now()+interval '65 minutes' or ((s.session_date+s.start_time) at time zone 'America/Toronto') between now()+interval '10 minutes' and now()+interval '15 minutes')
 loop
 if exists(select 1 from public.sessions s join public.locations l on l.id=s.location_id where s.id=x.id and l.city='Mississauga') then
  perform public.generate_mississauga_volleyball_teams(x.id);
  continue;
 end if;
 select count(*) into n from (
 select r.user_id from public.registrations r where r.session_id=x.id and r.status='confirmed'
 union
 select pa.user_id from public.permanent_assignments pa left join public.absences a on a.session_id=pa.session_id and a.user_id=pa.user_id where pa.session_id=x.id and not coalesce(a.not_coming,false) and not exists (select 1 from public.registrations r where r.session_id=x.id and r.user_id=pa.user_id and r.status='cancelled')
 ) players;
 if n>=12 then
 t:=case when n>=16 then 3 else 2 end;
 delete from public.session_teams where session_id=x.id;
 insert into public.session_teams(session_id,user_id,team_no)
 select x.id,user_id,1+mod((row_number() over(order by coalesce(player_level,'intermediate'),user_id))::integer-1,t)
 from (
 select distinct on (u.user_id) u.user_id,u.player_level from (
 select r.user_id,r.player_level from public.registrations r where r.session_id=x.id and r.status='confirmed'
 union all
 select pa.user_id,r.player_level from public.permanent_assignments pa left join public.absences a on a.session_id=pa.session_id and a.user_id=pa.user_id left join public.registrations r on r.session_id=pa.session_id and r.user_id=pa.user_id where pa.session_id=x.id and not coalesce(a.not_coming,false) and (r.status is null or r.status<>'cancelled')
 ) u order by u.user_id
 ) players;
 end if;
 end loop;
end $function$;
REVOKE ALL ON FUNCTION public.generate_session_teams(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.generate_session_teams(bigint) TO authenticated,service_role;
REVOKE ALL ON FUNCTION public.auto_generate_due_volleyball_teams() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.auto_generate_due_volleyball_teams() TO service_role;