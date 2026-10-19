-- Move confirmed Drop-in bookings between courts of the same dated activity.
-- Keep registration IDs, payment state and approved group membership intact.
create or replace function kestrel_groups.admin_move_court(p_registration_id bigint,p_court text)
returns void language plpgsql security definer set search_path='' as $$
declare r public.registrations%rowtype; source public.sessions%rowtype; target public.sessions%rowtype;
 g kestrel_groups.requests%rowtype; members uuid[]; used integer; allowed integer; original_session bigint;
begin
 if auth.uid() is null or not public.is_admin() then raise exception 'Admin access required';end if;
 select * into r from public.registrations where id=p_registration_id;
 if not found then raise exception 'Registration not found';end if;
 original_session:=r.session_id;
 select * into source from public.sessions where id=r.session_id;
 -- Lock all courts in a consistent order before checking availability.
 perform 1 from public.sessions s where s.location_id=source.location_id and s.sport_id=source.sport_id
  and s.session_date=source.session_date and s.start_time=source.start_time and s.end_time=source.end_time order by s.id for update;
 select * into r from public.registrations where id=p_registration_id for update;
 if r.session_id<>original_session then raise exception 'Booking changed. Refresh the roster and try again';end if;
 if r.status<>'confirmed' then raise exception 'Only attending players can change courts';end if;
 if r.registration_type='season' or (r.registration_type is null and exists(select 1 from public.permanent_assignments where session_id=r.session_id and user_id=r.user_id)) then
  raise exception 'Use the Season court assignment control for this player';end if;
 select * into target from public.sessions s where s.location_id=source.location_id and s.sport_id=source.sport_id
  and s.session_date=source.session_date and s.start_time=source.start_time and s.end_time=source.end_time and s.court=p_court
  order by s.id limit 1;
 if not found then raise exception 'Choose a court from this activity';end if;
 if target.id=source.id then
  delete from public.permanent_roster_courts where session_id=r.session_id and user_id=r.user_id;
  return;
 end if;
 if target.status='closed' or target.availability_status<>'available' then raise exception 'This court is unavailable';end if;
 if exists(select 1 from public.exclusive_court_bookings where session_id=target.id and cancelled_at is null) then
  raise exception 'This court is reserved for a full-court group';end if;
 if exists(select 1 from kestrel_groups.requests q join kestrel_groups.members m on m.request_id=q.id
  where q.session_id=source.id and m.player_id=r.user_id and q.status='pending' and q.expires_at>now()) then
  raise exception 'Review or withdraw the pending group request before moving courts';end if;
 select q.* into g from kestrel_groups.requests q join kestrel_groups.members m on m.request_id=q.id
  where q.session_id=source.id and m.player_id=r.user_id and q.status='approved' for update of q;
 if g.id is null then members:=array[r.user_id];else
  select array_agg(player_id) into members from kestrel_groups.members where request_id=g.id;
  if (select count(*) from public.registrations where session_id=source.id and user_id=any(members) and status='confirmed')<>cardinality(members) then
   raise exception 'Group attendance changed. Refresh and review the group before moving';end if;
 end if;
 if exists(select 1 from public.registrations where session_id=target.id and user_id=any(members)) then
  raise exception 'A player already has a registration on the destination court. Resolve it before moving';end if;
 select count(*) into used from public.registrations where session_id=target.id and status='confirmed';
 used:=used+(select count(*) from public.permanent_assignments pa where pa.session_id=target.id
  and not exists(select 1 from public.absences a where a.session_id=pa.session_id and a.user_id=pa.user_id and a.not_coming)
  and not exists(select 1 from public.registrations x where x.session_id=pa.session_id and x.user_id=pa.user_id));
 used:=used+kestrel_groups.held(target.id);
 allowed:=coalesce(target.capacity,0);
 if used+cardinality(members)>allowed then raise exception 'Not enough places on this court for the player and guests';end if;
 update public.registrations set session_id=target.id where session_id=source.id and user_id=any(members) and status='confirmed';
 if g.id is not null then update kestrel_groups.requests set session_id=target.id where id=g.id;end if;
 delete from public.permanent_roster_courts where session_id=source.id and user_id=any(members);
 perform kestrel_groups.promote(source.id);
end $$;
revoke all on function kestrel_groups.admin_move_court(bigint,text) from public,anon;
grant execute on function kestrel_groups.admin_move_court(bigint,text) to authenticated;
create or replace function public.admin_move_dropin_court(p_registration_id bigint,p_court text)
returns void language sql security invoker set search_path='' as $$select kestrel_groups.admin_move_court(p_registration_id,p_court)$$;
revoke all on function public.admin_move_dropin_court(bigint,text) from public,anon;
grant execute on function public.admin_move_dropin_court(bigint,text) to authenticated;
