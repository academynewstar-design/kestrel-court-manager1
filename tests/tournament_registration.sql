-- Run as the database owner. Everything, including test entries, is rolled back.
begin;
select set_config('test.owner',(select id::text from public.profiles where not is_admin and player_type_status='approved' limit 1),true);
select set_config('test.other',(select id::text from public.profiles where not is_admin and player_type_status='approved' and id::text<>current_setting('test.owner') limit 1),true);
select set_config('test.admin',(select id::text from public.profiles where is_admin limit 1),true);
with e as (
 insert into public.tournament_events(slug,title,sport_id,city,starts_at,individual_fee,team_fee)
 select 'rollback-tournament-test','Rollback test',id,'Brampton',now()+interval '1 day',7,30 from public.sports where name='basketball' returning id
) select set_config('test.event',id::text,true) from e;
set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('test.owner'),true);
insert into public.tournament_entries(event_id,user_id,entry_kind,player_names,eligibility_confirmed)
values(current_setting('test.event')::bigint,auth.uid(),'individual',array['Test Player'],true);
do $$ begin
 if (select count(*) from public.tournament_entries where event_id=current_setting('test.event')::bigint)<>1 then raise exception 'Owner entry not visible'; end if;
 begin
  insert into public.tournament_entries(event_id,user_id,entry_kind,player_names,eligibility_confirmed)
  values(current_setting('test.event')::bigint,auth.uid(),'individual',array['Test Player'],true);
  raise exception 'Duplicate entry accepted';
 exception when unique_violation then null; end;
 begin
  update public.tournament_events set individual_fee=0 where id=current_setting('test.event')::bigint;
  if found then raise exception 'Player changed event fee'; end if;
 end;
end $$;
update public.tournament_entries set payment_status='paid' where event_id=current_setting('test.event')::bigint;
update public.tournament_entries set status='cancelled' where event_id=current_setting('test.event')::bigint;
update public.tournament_entries set status='registered' where event_id=current_setting('test.event')::bigint;
do $$ begin
 if (select payment_status from public.tournament_entries where event_id=current_setting('test.event')::bigint)<>'paid' then raise exception 'Rejoin lost payment'; end if;
 begin
  update public.tournament_entries set payment_status='unpaid' where event_id=current_setting('test.event')::bigint;
  raise exception 'Paid downgrade accepted';
 exception when raise_exception then if SQLERRM<>'Contact Admin to change a paid entry' then raise; end if; end;
end $$;
select set_config('request.jwt.claim.sub',current_setting('test.other'),true);
do $$ begin
 if exists(select 1 from public.tournament_entries where event_id=current_setting('test.event')::bigint) then raise exception 'Other player can read private entry'; end if;
 update public.tournament_entries set status='cancelled' where event_id=current_setting('test.event')::bigint;
 if found then raise exception 'Other player can alter entry'; end if;
 begin
  insert into public.tournament_entries(event_id,user_id,entry_kind,team_name,player_names,eligibility_confirmed)
  values(current_setting('test.event')::bigint,auth.uid(),'team',null,array['Test Player'],true);
  raise exception 'Missing team name accepted';
 exception when check_violation then null; end;
 begin
  insert into public.tournament_entries(event_id,user_id,entry_kind,player_names,eligibility_confirmed,payment_status)
  values(current_setting('test.event')::bigint,auth.uid(),'individual',array['Test Player'],true,'paid');
  raise exception 'Insert as paid accepted';
 exception when raise_exception then if SQLERRM<>'Register first, then record payment after sending it' then raise; end if; end;
end $$;
insert into public.tournament_entries(event_id,user_id,entry_kind,team_name,player_names,eligibility_confirmed)
values(current_setting('test.event')::bigint,auth.uid(),'team','Test Team',array['Test Player','Test Teammate'],true);
select set_config('request.jwt.claim.sub',current_setting('test.admin'),true);
do $$ begin
 if (select count(*) from public.tournament_entries where event_id=current_setting('test.event')::bigint)<>2 then raise exception 'Admin cannot see all entries'; end if;
end $$;
update public.tournament_entries set payment_status='unpaid' where event_id=current_setting('test.event')::bigint;
update public.tournament_events set status='closed' where id=current_setting('test.event')::bigint;
select set_config('request.jwt.claim.sub',current_setting('test.other'),true);
do $$ begin
 begin
  update public.tournament_entries set payment_status='paid' where event_id=current_setting('test.event')::bigint;
  raise exception 'Closed event accepted update';
 exception when raise_exception then if SQLERRM<>'Tournament registration is closed. Contact Admin for changes' then raise; end if; end;
end $$;
reset role;
rollback;
select 'Tournament RLS, fees, duplicate prevention, team validation, payment, rejoin and closure checks passed; test rows rolled back' as result;
