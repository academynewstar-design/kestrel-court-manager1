-- Run inside a transaction; all choice and attendance changes are rolled back.
select set_config('season_remove.user',r.user_id::text,true),set_config('season_remove.schedule',r.recurring_schedule_id::text,true)
from public.recurring_permanent_requests r join public.profiles p on p.id=r.user_id
where r.status='approved' and p.player_type='permanent' and p.player_type_status='approved'
 and r.user_id not in ('589a03c9-6d1d-4ec9-a1e8-b32feb5c3869'::uuid,'97a515b2-34ca-4205-a0ab-ec9545b79e14'::uuid,'7f285761-7e48-4209-988a-3569eaf9cb82'::uuid,'5bf35749-6689-42f7-b915-c5446a9c4e2a'::uuid)
 and exists(select 1 from public.permanent_assignments a join public.sessions s on s.id=a.session_id where a.user_id=r.user_id and s.recurring_schedule_id=r.recurring_schedule_id and ((s.session_date+s.start_time) at time zone 'America/Toronto')>now())
order by r.id limit 1;
create temp table season_remove_preserved as
 select 'assignment' as kind,to_jsonb(a) as original from public.permanent_assignments a join public.sessions s on s.id=a.session_id
 where a.user_id=current_setting('season_remove.user')::uuid and ((s.session_date+s.start_time) at time zone 'America/Toronto')<=now()
 union all
 select 'registration',to_jsonb(r) from public.registrations r join public.sessions s on s.id=r.session_id
 where r.user_id=current_setting('season_remove.user')::uuid and (r.registration_type in ('dropin','drop-in') or ((s.session_date+s.start_time) at time zone 'America/Toronto')<=now());
-- The API accepts only a schedule ID, never another user's ID.
select set_config('request.jwt.claim.sub','',true);
set local role authenticated;
do $$begin
 begin perform public.remove_my_season_choice(current_setting('season_remove.schedule')::bigint);raise exception 'TEST FAILED: anonymous removal';
 exception when others then if SQLERRM<>'An approved Season account is required' then raise;end if;end;
end $$;
select set_config('request.jwt.claim.sub',current_setting('season_remove.user'),true);
select public.remove_my_season_choice(current_setting('season_remove.schedule')::bigint) as released_games;
reset role;
do $$begin
 assert not exists(select 1 from public.recurring_permanent_requests where user_id=current_setting('season_remove.user')::uuid and recurring_schedule_id=current_setting('season_remove.schedule')::bigint and status='approved'),'Recurring approval still active';
 assert not exists(select 1 from public.permanent_assignments a join public.sessions s on s.id=a.session_id where a.user_id=current_setting('season_remove.user')::uuid and s.recurring_schedule_id=current_setting('season_remove.schedule')::bigint and ((s.session_date+s.start_time) at time zone 'America/Toronto')>now()),'Future assignment not released';
 assert not exists(select 1 from public.season_court_change_requests where user_id=current_setting('season_remove.user')::uuid and recurring_schedule_id=current_setting('season_remove.schedule')::bigint and status='pending'),'Court change remained pending';
 assert not exists(select 1 from season_remove_preserved x where (kind='assignment' and not exists(select 1 from public.permanent_assignments a where to_jsonb(a)=x.original)) or (kind='registration' and not exists(select 1 from public.registrations r where to_jsonb(r)=x.original))),'Past game or Drop-in booking changed';
end $$;
select 'Season removal integration checks passed' as result;
