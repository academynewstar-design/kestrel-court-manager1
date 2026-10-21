-- Run as SQL tooling in a single transaction. All fixtures and queued test emails roll back.
begin;
create temp table attendance_fixture(id bigint);
with s as (
 insert into public.sessions(location_id,sport_id,session_date,start_time,end_time,court,status,availability_status,capacity,price,dropin_enabled)
 select l.id,sp.id,(now() at time zone 'America/Toronto')::date+1,'00:01','00:02','Attendance test','open','available',18,6,false
 from public.locations l cross join public.sports sp where l.city='Oakville' and l.name='Gaetan Gervais' and sp.name='badminton'
 returning id
) insert into attendance_fixture select id from s;
select set_config('attendance.test_id',(select id::text from attendance_fixture),true);
insert into public.permanent_assignments(user_id,session_id)
select p.id,f.id from public.profiles p cross join attendance_fixture f where p.email in ('senthil.s911@gmail.com') or p.id in ('e3cb27c3-ea69-43d9-8cec-f48d8c0fdaa1','f18a0904-d94b-4271-b8bb-5b5dc0026d6e');
insert into public.registrations(user_id,session_id,status,registration_type,payment_status)
select p.id,f.id,case when p.id='8d18910a-200f-4d2b-8594-e3f26f2697e3' then 'cancelled' else 'confirmed' end,'dropin','unpaid'
from public.profiles p cross join attendance_fixture f where p.email='senthil.s911@gmail.com' or p.id='8d18910a-200f-4d2b-8594-e3f26f2697e3';
insert into public.absences(user_id,session_id,not_coming)
select 'f18a0904-d94b-4271-b8bb-5b5dc0026d6e',id,true from attendance_fixture;
update public.sessions set session_date=(now() at time zone 'America/Toronto')::date-1 where id=(select id from attendance_fixture);
select set_config('request.jwt.claims','{"sub":"12c044dc-56f8-44fc-bc3d-f6aad11e4e35","role":"authenticated"}',true);
set local role authenticated;
do $$ declare sid bigint:=current_setting('attendance.test_id')::bigint; x jsonb; marks jsonb; err boolean;
begin
 x:=public.get_convenor_attendance(sid);
 if jsonb_array_length(x->'players')<>3 then raise exception 'Duplicate or cancelled player in roster';end if;
 if (select count(*) from jsonb_array_elements(x->'players') p where (p->>'not_going')::boolean)<>1 then raise exception 'Not Going classification failed';end if;
 marks:='{"12c044dc-56f8-44fc-bc3d-f6aad11e4e35":true,"e3cb27c3-ea69-43d9-8cec-f48d8c0fdaa1":false,"f18a0904-d94b-4271-b8bb-5b5dc0026d6e":false}';
 err:=false;begin perform public.save_convenor_attendance(sid,marks,'stale-token',0,false);exception when others then err:=sqlerrm like 'Roster changed%';end;if not err then raise exception 'Stale roster accepted';end if;
 err:=false;begin perform public.save_convenor_attendance(sid,'{}'::jsonb,x->>'roster_token',0,true);exception when others then err:=sqlerrm like 'Review every player%';end;if not err then raise exception 'Incomplete confirmation accepted';end if;
 err:=false;begin perform public.save_convenor_attendance(sid,marks||'{"00000000-0000-0000-0000-000000000000":true}',x->>'roster_token',0,false);exception when others then err:=sqlerrm like 'Attendance contains%';end;if not err then raise exception 'Unknown player accepted';end if;
 x:=public.save_convenor_attendance(sid,marks,x->>'roster_token',0,false);
 if (x->>'revision')::int<>1 or x->>'confirmed_at' is not null then raise exception 'Draft save failed';end if;
 err:=false;begin perform public.save_convenor_attendance(sid,marks,x->>'roster_token',0,false);exception when others then err:=sqlerrm like 'Attendance changed%';end;if not err then raise exception 'Stale revision accepted';end if;
 x:=public.save_convenor_attendance(sid,marks,x->>'roster_token',1,true);
 if (x->>'no_show_count')::int<>1 or not (x->>'report_queued')::boolean or x->>'confirmed_at' is null then raise exception 'Confirmation or report failed';end if;
 -- A retry must return the frozen sheet, without incrementing the revision or emailing again.
 x:=public.save_convenor_attendance(sid,marks,x->>'roster_token',1,true);
 if (x->>'revision')::int<>2 then raise exception 'Confirmation retry was not idempotent';end if;
 err:=false;begin perform public.get_convenor_attendance(2402);exception when others then err:=sqlerrm like 'Convenor access required%';end;if not err then raise exception 'Other location exposed';end if;
 err:=false;begin perform public.save_convenor_attendance(1075,'{}',null,0,true);exception when others then err:=sqlerrm like 'Attendance can be saved%' or sqlerrm like 'Confirm attendance after%';end;if not err then raise exception 'Early confirmation accepted';end if;
end $$;
reset role;
do $$ declare sid bigint:=current_setting('attendance.test_id')::bigint; body_text text; n int;
begin
 select count(*),max(body) into n,body_text from public.email_notifications where notification_type='convenor_attendance:'||sid;
 if n<>1 or body_text not like '%faqruddin sheik%' or body_text like '%anoop madhavan%' or body_text like '%sanjeev raju%' then raise exception 'Email did not contain exactly the unexcused player';end if;
 if (select count(*) from kestrel_attendance.history where session_id=sid)<>2 then raise exception 'Audit history missing';end if;
 if has_schema_privilege('authenticated','kestrel_attendance','USAGE') or has_function_privilege('anon','public.get_convenor_attendance(bigint)','EXECUTE') or has_function_privilege('anon','public.save_convenor_attendance(bigint,jsonb,text,integer,boolean)','EXECUTE') then raise exception 'Privileges too broad';end if;
end $$;
select set_config('request.jwt.claims','{"sub":"cfe0f840-47df-4d0c-af84-5939b1a4a0ba","role":"authenticated"}',true);
set local role authenticated;
do $$ declare err boolean:=false;
begin
 if exists(select 1 from public.get_my_convenor_locations()) or jsonb_array_length(public.get_convenor_activities())<>0 then raise exception 'Ordinary player got convenor access';end if;
 begin perform public.get_convenor_attendance(1075);exception when others then err:=sqlerrm like 'Convenor access required%';end;if not err then raise exception 'Ordinary player read roster';end if;
 err:=false;begin perform public.save_convenor_attendance(1075,'{}',null,0,false);exception when others then err:=sqlerrm like 'Convenor access required%';end;if not err then raise exception 'Ordinary player saved attendance';end if;
end $$;
reset role;
select 'Attendance authorization, roster, drafts, confirmation, exclusions, audit and email checks passed; rolled back' result;
rollback;
