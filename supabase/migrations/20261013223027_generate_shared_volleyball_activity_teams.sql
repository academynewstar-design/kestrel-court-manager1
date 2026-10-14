CREATE OR REPLACE FUNCTION public.generate_volleyball_activity_teams(p_session_id bigint)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare ids bigint[]; players jsonb; n integer; team_count integer; counts integer[]; skills integer[];
 apply_groups boolean; member record; chosen integer; i integer; weight integer; grouped boolean; group_number integer;
begin
 if not exists(select 1 from sessions s join sports sp on sp.id=s.sport_id join locations l on l.id=s.location_id
  where s.id=p_session_id and sp.name='volleyball'  ) then raise exception 'Volleyball session required'; end if;
 select l.city='Mississauga' into apply_groups from sessions s join locations l on l.id=s.location_id where s.id=p_session_id;
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
 into players from attendees a left join mississauga_volleyball_same_team_members g on apply_groups and g.user_id=a.user_id;
 n:=coalesce(jsonb_array_length(players),0);
 if n<12 then return 0; end if;
 -- Bind an anticipated teammate only when exactly one attending player matches the first name.
 if apply_groups then
 insert into public.mississauga_volleyball_same_team_members(user_id,group_number)
 select matched.user_id,q.group_number from public.mississauga_volleyball_pending_group_members q
 cross join lateral (
  select p.id user_id from jsonb_array_elements(players) item join public.profiles p on p.id=(item->>'user_id')::uuid
  where lower(split_part(trim(regexp_replace(p.full_name,'\\s+',' ','g')),' ',1))=q.first_name
  and (select count(*) from jsonb_array_elements(players) other join public.profiles candidate on candidate.id=(other->>'user_id')::uuid
   where lower(split_part(trim(regexp_replace(candidate.full_name,'\\s+',' ','g')),' ',1))=q.first_name)=1
 ) matched
 on conflict(user_id) do nothing;
 end if;
 select jsonb_agg(jsonb_build_object('user_id',item->>'user_id','player_level',item->>'player_level',
  'grouped',g.user_id is not null,'group_number',coalesce(g.group_number,0))
  order by (g.user_id is not null) desc,g.group_number,
   (case item->>'player_level' when 'advanced' then 3 when 'intermediate' then 2 else 1 end) desc,item->>'user_id')
 into players from jsonb_array_elements(players) item
 left join public.mississauga_volleyball_same_team_members g on apply_groups and g.user_id=(item->>'user_id')::uuid;
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
revoke all on function public.generate_volleyball_activity_teams(bigint) from public,anon,authenticated;
grant execute on function public.generate_volleyball_activity_teams(bigint) to service_role;