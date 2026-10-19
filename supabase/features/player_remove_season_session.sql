-- Players may withdraw their own approved weekly Season choice.
-- Keep completed games and independent Drop-in bookings intact.
create schema if not exists kestrel_season;
revoke all on schema kestrel_season from public,anon;
grant usage on schema kestrel_season to authenticated;
create or replace function kestrel_season.remove_my_choice(p_recurring_schedule_id bigint)
returns integer language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid(); sid bigint; affected bigint[]; removed integer;
begin
 if uid is null or not exists(select 1 from public.profiles p where p.id=uid and p.player_type='permanent' and p.player_type_status='approved') then
  raise exception 'An approved Season account is required';end if;
 if uid=any(array['589a03c9-6d1d-4ec9-a1e8-b32feb5c3869','97a515b2-34ca-4205-a0ab-ec9545b79e14','7f285761-7e48-4209-988a-3569eaf9cb82','5bf35749-6689-42f7-b915-c5446a9c4e2a']::uuid[]) then
  raise exception 'Season changes for your account are managed by Admin';end if;
 perform 1 from public.recurring_permanent_requests r where r.user_id=uid and r.recurring_schedule_id=p_recurring_schedule_id and r.status='approved' for update;
 if not found then raise exception 'Choose one of your approved Season sessions';end if;
 -- Lock upcoming courts before releasing assignments or promoting the waitlist.
 perform 1 from public.sessions s where s.recurring_schedule_id=p_recurring_schedule_id
  and ((s.session_date+s.start_time) at time zone 'America/Toronto')>now() order by s.id for update;
 select coalesce(array_agg(s.id order by s.id),'{}'::bigint[]) into affected from public.sessions s
 where s.recurring_schedule_id=p_recurring_schedule_id and ((s.session_date+s.start_time) at time zone 'America/Toronto')>now()
  and (exists(select 1 from public.permanent_assignments a where a.session_id=s.id and a.user_id=uid)
   or exists(select 1 from public.registrations r where r.session_id=s.id and r.user_id=uid and r.registration_type='season'));
 update public.recurring_permanent_requests set status='rejected' where user_id=uid and recurring_schedule_id=p_recurring_schedule_id;
 update public.season_court_change_requests set status='cancelled',updated_at=now()
  where user_id=uid and recurring_schedule_id=p_recurring_schedule_id and status='pending';
 delete from public.permanent_assignments where user_id=uid and session_id=any(affected);
 delete from public.permanent_roster_courts where user_id=uid and session_id=any(affected)
  and not exists(select 1 from public.registrations r where r.session_id=permanent_roster_courts.session_id and r.user_id=uid and r.registration_type in ('dropin','drop-in'));
 delete from public.absences where user_id=uid and session_id=any(affected)
  and not exists(select 1 from public.registrations r where r.session_id=absences.session_id and r.user_id=uid and r.registration_type in ('dropin','drop-in'));
 update public.registrations set status='cancelled' where user_id=uid and session_id=any(affected)
  and (registration_type='season' or registration_type is null) and status in ('confirmed','pending','waitlist');
 delete from public.legacy_court_allocations a using public.profiles p where p.id=uid
  and a.recurring_schedule_id=p_recurring_schedule_id and a.player_name=p.full_name and a.source_sheet='Portal registration';
 foreach sid in array affected loop perform kestrel_groups.promote(sid);end loop;
 removed:=cardinality(affected);return removed;
end $$;
revoke all on function kestrel_season.remove_my_choice(bigint) from public,anon;
grant execute on function kestrel_season.remove_my_choice(bigint) to authenticated;
create or replace function public.remove_my_season_choice(p_recurring_schedule_id bigint)
returns integer language sql security invoker set search_path='' as $$select kestrel_season.remove_my_choice(p_recurring_schedule_id)$$;
revoke all on function public.remove_my_season_choice(bigint) from public,anon;
grant execute on function public.remove_my_season_choice(bigint) to authenticated;
