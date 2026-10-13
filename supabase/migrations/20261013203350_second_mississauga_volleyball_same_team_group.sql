ALTER TABLE public.mississauga_volleyball_same_team_members ADD COLUMN group_number integer NOT NULL DEFAULT 1 CHECK(group_number IN (1,2));
DO $seed$
DECLARE matched integer;
BEGIN
 INSERT INTO public.mississauga_volleyball_same_team_members(user_id,group_number)
 SELECT id,2 FROM public.profiles WHERE lower(trim(full_name)) IN ('sovan samal','prudhvi raj','puneeth chowdary yadlapalli');
 GET DIAGNOSTICS matched=ROW_COUNT;
 IF matched<>3 THEN RAISE EXCEPTION 'Expected 3 verified second-group members, found %',matched; END IF;
END $seed$;
CREATE OR REPLACE FUNCTION public.generate_mississauga_volleyball_teams(p_session_id bigint)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
declare ids bigint[]; players jsonb; n integer; team_count integer; counts integer[]; skills integer[];
 member record; chosen integer; i integer; weight integer; grouped boolean; group_number integer;
begin
 if not exists(select 1 from sessions s join sports sp on sp.id=s.sport_id join locations l on l.id=s.location_id
  where s.id=p_session_id and sp.name='volleyball' and l.city='Mississauga') then raise exception 'Mississauga Volleyball session required'; end if;
 select activity_ids into ids from public.get_volleyball_activity_capacity(p_session_id);
 perform pg_advisory_xact_lock(71108,ids[1]::integer);
 with candidates as (
  select r.user_id,r.player_level from registrations r where r.session_id=any(ids) and r.status='confirmed'
   and not exists(select 1 from absences a where a.session_id=r.session_id and a.user_id=r.user_id and a.not_coming=true)
  union all
  select a.user_id,coalesce(r.player_level,choice.player_level) from permanent_assignments a join sessions s on s.id=a.session_id
   left join registrations r on r.session_id=a.session_id and r.user_id=a.user_id
   left join recurring_permanent_requests choice on choice.recurring_schedule_id=s.recurring_schedule_id and choice.user_id=a.user_id and choice.status='approved'
   where a.session_id=any(ids)
   and not exists(select 1 from absences ab where ab.session_id=a.session_id and ab.user_id=a.user_id and ab.not_coming=true)
   and coalesce(r.status,'confirmed')<>'cancelled'
 ), attendees as (
  select distinct on (c.user_id) c.user_id,coalesce(c.player_level,'intermediate') player_level
  from candidates c join profiles p on p.id=c.user_id where p.player_type_status='approved'
  order by c.user_id,(c.player_level is not null) desc
 )
 select jsonb_agg(jsonb_build_object('user_id',a.user_id,'player_level',a.player_level,'grouped',g.user_id is not null,'group_number',coalesce(g.group_number,0))
  order by (g.user_id is not null) desc,g.group_number,
  (case a.player_level when 'advanced' then 3 when 'intermediate' then 2 else 1 end) desc,a.user_id)
 into players from attendees a left join mississauga_volleyball_same_team_members g on g.user_id=a.user_id;
 n:=coalesce(jsonb_array_length(players),0);
 if n<12 then return 0; end if;
 team_count:=case when n>=16 then 3 else 2 end;
 counts:=array_fill(0,array[team_count]);skills:=array_fill(0,array[team_count]);
 delete from session_teams where session_id=any(ids);
 for member in select value as data from jsonb_array_elements(players) loop
  grouped:=(member.data->>'grouped')::boolean;
  weight:=case member.data->>'player_level' when 'advanced' then 3 when 'intermediate' then 2 else 1 end;
  group_number:=(member.data->>'group_number')::integer;
  if grouped then chosen:=group_number; else
   chosen:=1;
   for i in 2..team_count loop
    if counts[i]<counts[chosen] or (counts[i]=counts[chosen] and skills[i]<skills[chosen]) then chosen:=i; end if;
   end loop;
  end if;
  counts[chosen]:=counts[chosen]+1;skills[chosen]:=skills[chosen]+weight;
  insert into session_teams(session_id,user_id,team_no)
   select id,(member.data->>'user_id')::uuid,chosen from unnest(ids) id;
 end loop;
 return team_count;
end $function$;
REVOKE ALL ON FUNCTION public.generate_mississauga_volleyball_teams(bigint) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.generate_mississauga_volleyball_teams(bigint) TO service_role;