
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



do $$begin
 assert (select count(*) from public.registrations r join kestrel_groups.members m on m.player_id=r.user_id where m.request_id=current_setting('group_test.request')::bigint and r.session_id=current_setting('group_test.session')::bigint and r.payment_status='paid')=10,'Group payment did not cover every guest';
 assert (select count(*) from public.registrations where session_id=current_setting('group_test.session')::bigint and status='confirmed')=12,'Guest rows missing';
end $$;
set local role authenticated;
select public.cancel_my_dropin(current_setting('group_test.session')::bigint);
reset role;
do $$begin
 assert (select count(*) from public.registrations where session_id=current_setting('group_test.session')::bigint and status='confirmed')=2,'Group cancellation did not release all ten places';
 assert (select status from kestrel_groups.requests where id=current_setting('group_test.request')::bigint)='cancelled','Group status not cancelled';
end $$;
-- Reuse the same activity for a paid individual upgrading to a four-person group.
select set_config('request.jwt.claim.sub',current_setting('group_test.other'),true);
set local role authenticated;
select public.mark_my_dropin_paid(current_setting('group_test.session')::bigint);
select set_config('group_test.upgrade',public.request_dropin_group(current_setting('group_test.session')::bigint,array['Jamie Juliet','Kelly Kilo','Logan Lima'],'intermediate',true)::text,true);
do $$declare a record;begin select * into a from public.get_dropin_session_availability(array[current_setting('group_test.session')::bigint]);assert a.occupied=5,'Upgrade reserved organiser twice';end $$;
select set_config('request.jwt.claim.sub',current_setting('group_test.admin'),true);
select public.review_dropin_group(current_setting('group_test.upgrade')::bigint,true,'Existing payment retained as credit');
reset role;
do $$begin assert (select credit_paid from kestrel_groups.requests where id=current_setting('group_test.upgrade')::bigint)=6,'Existing payment credit lost';end $$;
select set_config('request.jwt.claim.sub',current_setting('group_test.other'),true);
set local role authenticated;
select public.mark_my_dropin_paid(current_setting('group_test.session')::bigint);
select public.cancel_dropin_group(current_setting('group_test.upgrade')::bigint);
reset role;
-- A pending request occupies the final two spaces and releases them on rejection.
update public.sessions set capacity=3,dropin_spots=3 where id=current_setting('group_test.session')::bigint;
select set_config('request.jwt.claim.sub',current_setting('group_test.owner'),true);
set local role authenticated;
select set_config('group_test.reject',public.request_dropin_group(current_setting('group_test.session')::bigint,array['Morgan Mike'],'intermediate',true)::text,true);
select set_config('request.jwt.claim.sub',current_setting('group_test.other'),true);
do $$begin assert public.register_dropin(current_setting('group_test.session')::bigint,'intermediate')='waitlist','Pending hold failed to protect capacity';end $$;
select set_config('request.jwt.claim.sub',current_setting('group_test.admin'),true);
select public.review_dropin_group(current_setting('group_test.reject')::bigint,false,'Rejected integration fixture');
reset role;
do $$begin assert exists(select 1 from public.registrations where user_id=current_setting('group_test.other')::uuid and session_id=current_setting('group_test.session')::bigint and status='confirmed'),'Rejection did not promote waitlist';end $$;
-- Unpaid cutoff cancels all participants atomically.
update public.sessions set capacity=12,dropin_spots=12 where id=current_setting('group_test.session')::bigint;
select set_config('request.jwt.claim.sub',current_setting('group_test.owner'),true);
set local role authenticated;
select set_config('group_test.cutoff',public.request_dropin_group(current_setting('group_test.session')::bigint,array['Alex Alpha','Blake Beta'],'intermediate',true)::text,true);
select set_config('request.jwt.claim.sub',current_setting('group_test.admin'),true);
select public.review_dropin_group(current_setting('group_test.cutoff')::bigint,true,null);
reset role;
update public.registrations set status='cancelled',payment_status='removed' where session_id=current_setting('group_test.session')::bigint and user_id=current_setting('group_test.owner')::uuid;
do $$begin assert not exists(select 1 from public.registrations r join kestrel_groups.members m on m.player_id=r.user_id where m.request_id=current_setting('group_test.cutoff')::bigint and r.session_id=current_setting('group_test.session')::bigint and r.status='confirmed'),'Unpaid cutoff left guests in roster';end $$;
-- Expired holds are excluded and cannot be approved; no expired data is made public.
select set_config('request.jwt.claim.sub',current_setting('group_test.owner'),true);
set local role authenticated;
select set_config('group_test.expired',public.request_dropin_group(current_setting('group_test.session')::bigint,array['Nico November'],'intermediate',true)::text,true);
reset role;
update kestrel_groups.requests set expires_at=now()-interval '1 second' where id=current_setting('group_test.expired')::bigint;
select set_config('request.jwt.claim.sub',current_setting('group_test.admin'),true);
set local role authenticated;
do $$begin
 begin perform public.review_dropin_group(current_setting('group_test.expired')::bigint,true,null);raise exception 'TEST FAILED: expired request approved';exception when others then if SQLERRM<>'This request has expired' then raise;end if;end;
end $$;
reset role;
-- Volleyball aliases share one capacity pool, and every approved guest receives a team slot.
insert into public.sessions(sport_id,location_id,session_date,start_time,end_time,capacity,price,court,dropin_enabled,dropin_spots,status,availability_status)
select sp.id,l.id,'2099-06-09','18:00','20:00',14,6,c.name,true,14,'open','available'
from public.sports sp cross join (select id from public.locations order by id limit 1) l cross join (values('Group volleyball A'),('Group volleyball B')) c(name) where sp.name='volleyball';
select set_config('group_test.volley_a',(select id::text from public.sessions where court='Group volleyball A'),true);
select set_config('group_test.volley_b',(select id::text from public.sessions where court='Group volleyball B'),true);
select set_config('request.jwt.claim.sub',current_setting('group_test.owner'),true);
set local role authenticated;
select set_config('group_test.volley_request',public.request_dropin_group(current_setting('group_test.volley_a')::bigint,array['Alex Alpha','Blake Beta','Casey Gamma','Drew Delta','Evan Echo','Frank Foxtrot','Gale Golf','Harper Hotel','Indigo India'],'intermediate',true)::text,true);
do $$declare a record;begin select * into a from public.get_dropin_session_availability(array[current_setting('group_test.volley_b')::bigint]);assert a.occupied=10 and a.total_capacity=14,'Volleyball alias ignored group capacity hold';end $$;
select set_config('request.jwt.claim.sub',current_setting('group_test.other'),true);
select public.register_dropin(current_setting('group_test.volley_b')::bigint,'advanced');
select set_config('request.jwt.claim.sub',current_setting('group_test.third'),true);
select public.register_dropin(current_setting('group_test.volley_b')::bigint,'intermediate');
select set_config('request.jwt.claim.sub',current_setting('group_test.admin'),true);
select public.review_dropin_group(current_setting('group_test.volley_request')::bigint,true,null);
select public.generate_session_teams(current_setting('group_test.volley_a')::bigint);
reset role;
do $$begin
 assert (select count(distinct user_id) from public.session_teams where session_id=current_setting('group_test.volley_a')::bigint)=12,'Guest participants omitted from team generation';
 assert (select count(*) from public.session_teams t join kestrel_groups.members m on m.player_id=t.user_id where m.request_id=current_setting('group_test.volley_request')::bigint and t.session_id=current_setting('group_test.volley_a')::bigint)=10,'Group did not receive ten team slots';
end $$;

-- A vacancy on a Season-only volleyball alias still promotes the shared Drop-in waitlist.
update public.sessions set capacity=12 where id in(current_setting('group_test.volley_a')::bigint,current_setting('group_test.volley_b')::bigint);
select set_config('request.jwt.claim.sub',current_setting('group_test.fourth'),true);
set local role authenticated;
do $$begin assert public.register_dropin(current_setting('group_test.volley_b')::bigint,'intermediate')='waitlist','Expected a full shared volleyball activity';end $$;
reset role;
update public.sessions set capacity=13 where id in(current_setting('group_test.volley_a')::bigint,current_setting('group_test.volley_b')::bigint);
update public.sessions set dropin_enabled=false where id=current_setting('group_test.volley_b')::bigint;
select kestrel_groups.promote(current_setting('group_test.volley_b')::bigint);
do $$begin assert exists(select 1 from public.registrations where user_id=current_setting('group_test.fourth')::uuid and session_id=current_setting('group_test.volley_b')::bigint and status='confirmed'),'Season alias vacancy did not promote the shared waitlist';end $$;

-- Endpoint permissions and cross-account mutation are denied.
select set_config('request.jwt.claim.sub',current_setting('group_test.third'),true);
set local role authenticated;
do $$begin
 begin perform public.cancel_dropin_group(current_setting('group_test.volley_request')::bigint);raise exception 'TEST FAILED: cross-account cancellation accepted';exception when others then if SQLERRM<>'Group request not found' then raise;end if;end;
end $$;
reset role;
set local role anon;
do $$begin
 begin perform public.list_dropin_groups();raise exception 'TEST FAILED: anonymous access accepted';exception when insufficient_privilege then null;end;
 begin perform public.request_dropin_group(current_setting('group_test.volley_a')::bigint,array['Unauthorized Guest'],'intermediate',true);raise exception 'TEST FAILED: anonymous mutation accepted';exception when insufficient_privilege then null;end;
end $$;
reset role;
