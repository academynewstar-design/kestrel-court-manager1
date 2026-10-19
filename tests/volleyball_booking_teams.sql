-- Run inside a transaction and roll back generated teams after verification.
do $$
declare activity record; result integer; checked integer:=0; ids bigint[];
begin
 for activity in
  select distinct s.id from public.sessions s join public.sports sp on sp.id=s.sport_id
  where sp.name='volleyball' and s.session_date>=(now() at time zone 'America/Toronto')::date
   and exists(select 1 from kestrel_groups.requests q where q.session_id=s.id and q.status='approved')
 loop
  result:=public.generate_volleyball_activity_teams(activity.id);
  if result=0 then continue;end if;
  checked:=checked+1;
  select activity_ids into ids from public.get_volleyball_activity_capacity(activity.id);
  assert not exists(
   select q.id from kestrel_groups.requests q join kestrel_groups.members m on m.request_id=q.id
    join public.session_teams t on t.user_id=m.player_id and t.session_id=activity.id
   where q.status='approved' and q.session_id=any(ids)
   group by q.id having count(distinct t.team_no)>1
  ),'Approved volleyball booking split across teams';
  assert not exists(
   select g.group_number from public.session_teams t
    join public.mississauga_volleyball_same_team_members g on g.user_id=t.user_id
    join public.sessions s on s.id=t.session_id join public.locations l on l.id=s.location_id
   where t.session_id=activity.id and l.city='Mississauga'
   group by g.group_number having count(distinct t.team_no)>1
  ),'Existing Mississauga teammate rule was split';
  perform public.generate_volleyball_activity_teams(activity.id);
 end loop;
 assert checked>0,'No eligible grouped volleyball activity was tested';
end $$;
select 'Volleyball group team checks passed' as result;
