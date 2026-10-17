-- Run inside a transaction with family_registration.sql; all fixtures are rolled back.
select set_config('family_test.owner',(select id::text from public.profiles where not is_admin and player_type_status='approved' order by id limit 1),true);
select set_config('family_test.other',(select id::text from public.profiles where not is_admin and player_type_status='approved' and id::text<>current_setting('family_test.owner') order by id limit 1),true);
select set_config('family_test.admin',(select id::text from public.profiles where is_admin order by id limit 1),true);
insert into public.recurring_schedules(source_key,sport_id,location_id,weekday,schedule_label,start_time,end_time)
select 'family-integration-validation',sp.id,l.id,'Thursday','Family integration fixture','18:00','20:00' from public.sports sp cross join public.locations l where sp.name='badminton' order by l.id limit 1;
select set_config('family_test.schedule',(select id::text from public.recurring_schedules where source_key='family-integration-validation'),true);
insert into public.sessions(recurring_schedule_id,sport_id,location_id,session_date,start_time,end_time,court,capacity,availability_status,status)
select rs.id,rs.sport_id,rs.location_id,d::date,'18:00','20:00','Court 1',2,case when d::date='2099-01-15' then 'unavailable' else 'available' end,'open' from public.recurring_schedules rs cross join (values('2099-01-01'),('2099-01-08'),('2099-01-15')) dates(d) where rs.id=current_setting('family_test.schedule')::bigint;
select set_config('family_test.session',(select min(id)::text from public.sessions where recurring_schedule_id=current_setting('family_test.schedule')::bigint),true);
select set_config('request.jwt.claim.sub',current_setting('family_test.owner'),true);
set local role authenticated;
select set_config('family_test.member',public.save_my_family_member(null,'Alex Validation','child',12,true)::text,true);
select set_config('family_test.sibling',public.save_my_family_member(null,'Jamie Validation','child',14,true)::text,true);
do $$begin
 assert jsonb_path_exists(public.get_my_family(), '$[*] ? (@.full_name == "Alex Validation")'), 'Owner cannot see saved member';
 begin perform public.save_my_family_member(null,'No Consent','child',12,false);raise exception 'TEST FAILED: no consent accepted';exception when others then if SQLERRM not like 'Confirm that%' then raise;end if;end;
 begin perform public.save_my_family_member(null,'Alex Validation','child',12,true);raise exception 'TEST FAILED: duplicate name accepted';exception when others then if SQLERRM not like 'A family member%' then raise;end if;end;
 begin perform public.get_pending_family_season_requests();raise exception 'TEST FAILED: player can read admin queue';exception when others then if SQLERRM<>'Admin access required' then raise;end if;end;
 begin update public.profiles set managed_by=current_setting('family_test.other')::uuid where id=auth.uid();raise exception 'TEST FAILED: ownership editable';exception when others then if SQLERRM<>'Player identity and family ownership cannot be changed' then raise;end if;end;
end $$;
select public.save_my_family_season_choices(current_setting('family_test.member')::uuid,jsonb_build_array(jsonb_build_object('recurring_schedule_id',current_setting('family_test.schedule')::bigint,'court','Court 1','player_level','intermediate','season_paid',true)));
select public.save_my_family_season_choices(current_setting('family_test.sibling')::uuid,jsonb_build_array(jsonb_build_object('recurring_schedule_id',current_setting('family_test.schedule')::bigint,'court','Court 1','player_level','low_intermediate','season_paid',true)));
select set_config('request.jwt.claim.sub',current_setting('family_test.other'),true);
do $$begin
 assert not jsonb_path_exists(public.get_my_family(), '$[*] ? (@.full_name == "Alex Validation")'), 'Another account can read this family';
 begin perform public.save_my_family_member(current_setting('family_test.member')::uuid,'Alex Validation','child',13,true);raise exception 'TEST FAILED: another owner can edit';exception when others then if SQLERRM<>'This family member does not belong to your account' then raise;end if;end;
 begin perform public.set_my_family_attendance(current_setting('family_test.member')::uuid,current_setting('family_test.session')::bigint,true);raise exception 'TEST FAILED: another owner can change attendance';exception when others then if SQLERRM<>'This family member does not belong to your account' then raise;end if;end;
end $$;
select set_config('request.jwt.claim.sub',current_setting('family_test.admin'),true);
do $$declare request_id bigint;begin
 select id into request_id from public.recurring_permanent_requests where user_id=current_setting('family_test.member')::uuid and recurring_schedule_id=current_setting('family_test.schedule')::bigint;
 begin perform public.admin_review_family_season_request(request_id,true,false);raise exception 'TEST FAILED: eligibility not enforced';exception when others then if SQLERRM not like 'Confirm this member%' then raise;end if;end;
 begin perform public.admin_review_recurring_permanent_request(request_id,'approved');raise exception 'TEST FAILED: generic approval bypass';exception when others then if SQLERRM not like 'Review this request under Family%' then raise;end if;end;
 perform public.admin_review_family_season_request(request_id,true,true);
 select id into request_id from public.recurring_permanent_requests where user_id=current_setting('family_test.sibling')::uuid and recurring_schedule_id=current_setting('family_test.schedule')::bigint;
 perform public.admin_review_family_season_request(request_id,true,true);
 assert (select count(*)=4 from public.registrations where user_id in (current_setting('family_test.member')::uuid,current_setting('family_test.sibling')::uuid)), 'Expected separate weekly registrations';
 assert not exists(select 1 from public.registrations r join public.sessions s on s.id=r.session_id where r.user_id=current_setting('family_test.member')::uuid and s.availability_status='unavailable'), 'Unavailable date registered';
 assert not exists(select 1 from public.registrations where user_id=current_setting('family_test.owner')::uuid and session_id=current_setting('family_test.session')::bigint), 'Parent was registered accidentally';
end $$;
select set_config('request.jwt.claim.sub',current_setting('family_test.owner'),true);
do $$begin
 assert public.set_my_family_attendance(current_setting('family_test.member')::uuid,current_setting('family_test.session')::bigint,true)='not_attending';
 assert public.set_my_family_attendance(current_setting('family_test.member')::uuid,current_setting('family_test.session')::bigint,false)='confirmed';
 assert public.set_my_family_attendance(current_setting('family_test.member')::uuid,current_setting('family_test.session')::bigint,true)='not_attending';
end $$;
reset role;
insert into public.registrations(user_id,session_id,status,payment_status,registration_type) values(current_setting('family_test.other')::uuid,current_setting('family_test.session')::bigint,'confirmed','paid','dropin');
set local role authenticated;
do $$begin assert public.set_my_family_attendance(current_setting('family_test.member')::uuid,current_setting('family_test.session')::bigint,false)='full', 'Full session permitted rejoin';end $$;
reset role;
do $$begin
 assert (select not_coming from public.absences where user_id=current_setting('family_test.member')::uuid and session_id=current_setting('family_test.session')::bigint), 'Failed rejoin reset absence';
 assert not exists(select 1 from public.absences where user_id=current_setting('family_test.sibling')::uuid and session_id=current_setting('family_test.session')::bigint and not_coming), 'Sibling attendance changed';
 assert not has_function_privilege('anon','public.get_my_family()','execute'), 'Anonymous family read allowed';
 assert not has_table_privilege('authenticated','kestrel_family.members','select'), 'Private age details directly exposed';
 assert exists(select 1 from pg_constraint where conrelid='public.profiles'::regclass and conname='profiles_login_identity_fkey'), 'Login foreign key missing';
end $$;
select 'Family integration checks passed: separate rosters, published dates, consent, ownership, admin review, attendance, capacity and private details' as result;
