
-- Integration fixtures and every change run inside a transaction that is rolled back.
select set_config('group_test.owner',(select id::text from public.profiles where managed_by is null and not is_admin and player_type_status='approved' order by id limit 1),true);
select set_config('group_test.other',(select id::text from public.profiles where managed_by is null and not is_admin and player_type_status='approved' and id::text<>current_setting('group_test.owner') order by id limit 1),true);
select set_config('group_test.third',(select id::text from public.profiles where managed_by is null and not is_admin and player_type_status='approved' and id::text not in(current_setting('group_test.owner'),current_setting('group_test.other')) order by id limit 1),true);
select set_config('group_test.fourth',(select id::text from public.profiles where managed_by is null and not is_admin and player_type_status='approved' and id::text not in(current_setting('group_test.owner'),current_setting('group_test.other'),current_setting('group_test.third')) order by id limit 1),true);
select set_config('group_test.admin',(select id::text from public.profiles where is_admin order by id limit 1),true);
insert into public.sessions(sport_id,location_id,session_date,start_time,end_time,capacity,price,payment_email,court,dropin_enabled,dropin_spots,status,availability_status,registration_open_at)
select sp.id,l.id,'2099-06-02','18:00','20:00',12,6,'test@example.invalid','Group integration test',true,12,'open','available',now()-interval '1 day'
from public.sports sp cross join public.locations l where sp.name='badminton' order by l.id limit 1;
select set_config('group_test.session',(select max(id)::text from public.sessions where court='Group integration test'),true);
select set_config('request.jwt.claim.sub',current_setting('group_test.owner'),true);
set local role authenticated;
select set_config('group_test.request',public.request_dropin_group(current_setting('group_test.session')::bigint,array['Alex Alpha','Blake Beta','Casey Gamma','Drew Delta','Evan Echo','Frank Foxtrot','Gale Golf','Harper Hotel','Indigo India'],'intermediate',true)::text,true);
do $$declare a record;begin
 select * into a from public.get_dropin_session_availability(array[current_setting('group_test.session')::bigint]);
 assert a.occupied=10 and a.total_capacity=12,'Ten-person request did not reserve ten places';
 assert jsonb_array_length(public.list_dropin_groups())>=1,'Owner cannot see request';
 begin perform public.register_dropin(current_setting('group_test.session')::bigint,'intermediate');raise exception 'TEST FAILED: pending owner booked individually';exception when others then if SQLERRM not like 'Your group request%' then raise;end if;end;
 begin perform public.review_dropin_group(current_setting('group_test.request')::bigint,true,null);raise exception 'TEST FAILED: player approved own request';exception when others then if SQLERRM<>'Admin access required' then raise;end if;end;
 begin perform public.get_grouped_dropin_roster(current_setting('group_test.session')::bigint);raise exception 'TEST FAILED: pending request exposed roster';exception when others then if SQLERRM not like 'You must be attending%' then raise;end if;end;
end $$;
select set_config('request.jwt.claim.sub',current_setting('group_test.other'),true);
do $$begin
 assert not jsonb_path_exists(public.list_dropin_groups(),('$[*] ? (@.id == '||current_setting('group_test.request')||')')::jsonpath),'Other player sees private request';
 begin perform public.request_dropin_group(current_setting('group_test.session')::bigint,array['Jamie Juliet','Kelly Kilo'],'intermediate',true);raise exception 'TEST FAILED: group overbooked';exception when others then if SQLERRM not like 'Not enough spots:%' then raise;end if;end;
 assert public.register_dropin(current_setting('group_test.session')::bigint,'advanced')='confirmed','Regular player cannot use a remaining spot';
end $$;
select set_config('request.jwt.claim.sub',current_setting('group_test.third'),true);
select public.register_dropin(current_setting('group_test.session')::bigint,'intermediate');
select set_config('request.jwt.claim.sub',current_setting('group_test.admin'),true);
select public.review_dropin_group(current_setting('group_test.request')::bigint,true,null);
select set_config('request.jwt.claim.sub',current_setting('group_test.owner'),true);
do $$declare a record;begin
 select * into a from public.get_dropin_session_availability(array[current_setting('group_test.session')::bigint]);
 assert a.occupied=12,'Approved guests not counted as individual participants';
 assert (select max(party_size) from public.get_grouped_dropin_roster(current_setting('group_test.session')::bigint))=10,'Roster did not collapse ten participants';
 assert (select sum(party_size) from public.get_grouped_dropin_roster(current_setting('group_test.session')::bigint))=12,'Grouped roster lost capacity';
 assert exists(select 1 from public.get_grouped_dropin_roster(current_setting('group_test.session')::bigint) where is_me and player_name like '% + 9'),'Roster suffix incorrect';
end $$;
select public.mark_my_dropin_paid(current_setting('group_test.session')::bigint);
reset role;
-- Add empty destination courts using the same dated activity.
insert into public.sessions(sport_id,location_id,session_date,start_time,end_time,capacity,price,payment_email,court,dropin_enabled,dropin_spots,status,availability_status,registration_open_at)
select sport_id,location_id,session_date,start_time,end_time,12,price,payment_email,'Move destination',true,12,'open','available',registration_open_at from public.sessions where id=current_setting('group_test.session')::bigint;
select set_config('group_test.target',(select id::text from public.sessions where court='Move destination' order by id desc limit 1),true);
select set_config('group_test.registration',(select id::text from public.registrations where session_id=current_setting('group_test.session')::bigint and user_id=current_setting('group_test.owner')::uuid),true);
-- Ordinary users cannot move courts.
select set_config('request.jwt.claim.sub',current_setting('group_test.owner'),true);
set local role authenticated;
do $$begin
 begin perform public.admin_move_dropin_court(current_setting('group_test.registration')::bigint,'Move destination');raise exception 'TEST FAILED: nonadmin moved group';
 exception when others then if SQLERRM<>'Admin access required' then raise;end if;end;
end $$;
reset role;
select set_config('request.jwt.claim.sub',current_setting('group_test.admin'),true);
-- An exclusive reservation prevents the move.
insert into public.exclusive_court_bookings(session_id,lead_name,guest_count,created_by,previous_dropin_enabled)
values(current_setting('group_test.target')::bigint,'Reserved test group',4,current_setting('group_test.admin')::uuid,true);
set local role authenticated;
do $$begin
 begin perform public.admin_move_dropin_court(current_setting('group_test.registration')::bigint,'Move destination');raise exception 'TEST FAILED: moved to exclusive court';
 exception when others then if SQLERRM<>'This court is reserved for a full-court group' then raise;end if;end;
end $$;
reset role;
delete from public.exclusive_court_bookings where session_id=current_setting('group_test.target')::bigint;
update public.sessions set capacity=6 where id=current_setting('group_test.target')::bigint;
set local role authenticated;
do $$begin
 begin perform public.admin_move_dropin_court(current_setting('group_test.registration')::bigint,'Move destination');raise exception 'TEST FAILED: group exceeded capacity';
 exception when others then if SQLERRM<>'Not enough places on this court for the player and guests' then raise;end if;end;
end $$;
reset role;
update public.sessions set capacity=12 where id=current_setting('group_test.target')::bigint;
-- Move one individual, then the ten-person paid group.
select set_config('group_test.individual',(select id::text from public.registrations where session_id=current_setting('group_test.session')::bigint and user_id=current_setting('group_test.other')::uuid),true);
set local role authenticated;
select public.admin_move_dropin_court(current_setting('group_test.individual')::bigint,'Move destination');
select public.admin_move_dropin_court(current_setting('group_test.registration')::bigint,'Move destination');
reset role;
do $$begin
 assert exists(select 1 from public.registrations where id=current_setting('group_test.individual')::bigint and session_id=current_setting('group_test.target')::bigint and status='confirmed'),'Individual move failed';
 assert (select count(*) from public.registrations r join kestrel_groups.members m on m.player_id=r.user_id where m.request_id=current_setting('group_test.request')::bigint and r.session_id=current_setting('group_test.target')::bigint and r.payment_status='paid' and r.status='confirmed')=10,'Group or payment lost on move';
 assert (select session_id from kestrel_groups.requests where id=current_setting('group_test.request')::bigint)=current_setting('group_test.target')::bigint,'Group session did not move';
 assert exists(select 1 from public.registrations where id=current_setting('group_test.registration')::bigint and session_id=current_setting('group_test.target')::bigint),'Registration ID changed';
end $$;
select 'Court move integration checks passed' as result;
