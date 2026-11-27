-- Doubles registration with verified Season identities, separate from drop-ins.
alter table public.tournament_events add column registration_format text not null default 'standard'
  check (registration_format in ('standard','season_badminton_doubles'));
alter table public.tournament_entries
  add column player_id uuid references public.profiles(id),
  add column partner_id uuid references public.profiles(id),
  add column player_level text check (player_level in ('low_intermediate','intermediate')),
  add column partner_level text check (partner_level in ('low_intermediate','intermediate'));

create schema if not exists kestrel_tournaments;
revoke all on schema kestrel_tournaments from public;
grant usage on schema kestrel_tournaments to authenticated;

-- Only names and registration eligibility are returned, never contact details.
create function kestrel_tournaments.season_players()
returns table(id uuid,full_name text,can_register boolean)
language sql stable security definer set search_path=public,pg_temp as $$
  select p.id,p.full_name,coalesce(p.id=auth.uid() or p.managed_by=auth.uid(),false)
  from public.profiles p
  where auth.uid() is not null
    and exists(select 1 from public.profiles actor where actor.id=auth.uid() and actor.player_type_status='approved')
    and p.player_type='permanent' and p.player_type_status='approved'
    and length(btrim(p.full_name))>=2
  order by p.full_name,p.id;
$$;
revoke all on function kestrel_tournaments.season_players() from public;
grant execute on function kestrel_tournaments.season_players() to authenticated;
create function public.get_tournament_season_players()
returns table(id uuid,full_name text,can_register boolean)
language sql stable security invoker set search_path=public,pg_temp as $$
  select * from kestrel_tournaments.season_players();
$$;
revoke all on function public.get_tournament_season_players() from public;
grant execute on function public.get_tournament_season_players() to authenticated;

create function kestrel_tournaments.validate_season_doubles()
returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
declare event_format text; first_name text; second_name text;
begin
  -- Serialize entries at this event so partners cannot be double-booked.
  select registration_format into event_format from public.tournament_events where id=new.event_id for update;
  if event_format<>'season_badminton_doubles' then
    if new.player_id is not null or new.partner_id is not null or new.player_level is not null or new.partner_level is not null then
      raise exception 'Player and partner selections are only supported for Season badminton doubles';
    end if;
    return new;
  end if;
  if auth.uid() is null then raise exception 'Sign in to register'; end if;
  if not public.is_admin() and new.user_id<>auth.uid() then raise exception 'Register from your own account'; end if;
  if new.status='cancelled' then return new; end if;
  if new.entry_kind<>'team' or new.player_id is null or new.partner_id is null or new.player_id=new.partner_id then
    raise exception 'Select two different Season players';
  end if;
  if new.player_level is null or new.partner_level is null
    or new.player_level not in ('low_intermediate','intermediate')
    or new.partner_level not in ('low_intermediate','intermediate') then
    raise exception 'Only Low Intermediate and Intermediate levels are eligible';
  end if;
  if not public.is_admin() and not exists(select 1 from public.profiles p where p.id=new.player_id and coalesce(p.id=auth.uid() or p.managed_by=auth.uid(),false)) then
    raise exception 'Choose your own name or a Season player in your family account';
  end if;
  select full_name into first_name from public.profiles where id=new.player_id and player_type='permanent' and player_type_status='approved';
  select full_name into second_name from public.profiles where id=new.partner_id and player_type='permanent' and player_type_status='approved';
  if first_name is null or second_name is null then raise exception 'Both players must be approved Kestrel Season players'; end if;
  if exists(select 1 from public.tournament_entries e where e.event_id=new.event_id and e.id is distinct from new.id and e.status='registered'
    and (e.player_id in (new.player_id,new.partner_id) or e.partner_id in (new.player_id,new.partner_id))) then
    raise exception 'One of these players is already registered with a partner for this tournament';
  end if;
  new.player_names:=array[first_name,second_name];
  new.team_name:=left(first_name||' / '||second_name,100);
  return new;
end $$;
revoke all on function kestrel_tournaments.validate_season_doubles() from public;
create trigger tournament_season_doubles before insert or update on public.tournament_entries
  for each row execute function kestrel_tournaments.validate_season_doubles();
create index tournament_entries_player_idx on public.tournament_entries(event_id,player_id) where status='registered';
create index tournament_entries_partner_idx on public.tournament_entries(event_id,partner_id) where status='registered';

-- Both participants can view their pair; only its organiser (or Admin) can edit.
drop policy tournament_entries_read on public.tournament_entries;
create policy tournament_entries_read on public.tournament_entries for select to authenticated
  using (user_id=(select auth.uid()) or player_id=(select auth.uid()) or partner_id=(select auth.uid()) or (select public.is_admin()));

alter table public.tournament_events
  add column intermediate_capacity integer not null default 20 check (intermediate_capacity>=0),
  add column low_intermediate_capacity integer not null default 20 check (low_intermediate_capacity>=0);

-- Allocation is private so a client cannot grant itself a confirmed place.
create table kestrel_tournaments.allocations (
 entry_id bigint primary key references public.tournament_entries(id) on delete cascade,
 confirmed boolean not null default false
);
alter table kestrel_tournaments.allocations enable row level security;
revoke all on kestrel_tournaments.allocations from public,anon,authenticated;

create function kestrel_tournaments.rebalance_doubles()
returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
declare event_row public.tournament_events; candidate record;
 used_intermediate integer:=0; used_low integer:=0; need_intermediate integer; need_low integer; has_room boolean;
begin
 select * into event_row from public.tournament_events where id=new.event_id for update;
 if event_row.registration_format<>'season_badminton_doubles' then return new; end if;
 -- Keep already-confirmed paid pairs in place, then consider the waitlist in registration order.
 for candidate in
  select e.*,coalesce(a.confirmed,false) as was_confirmed
  from public.tournament_entries e left join kestrel_tournaments.allocations a on a.entry_id=e.id
  where e.event_id=new.event_id
  order by coalesce(a.confirmed,false) desc,e.created_at,e.id
 loop
  need_intermediate:=(case when candidate.player_level='intermediate' then 1 else 0 end)+(case when candidate.partner_level='intermediate' then 1 else 0 end);
  need_low:=(case when candidate.player_level='low_intermediate' then 1 else 0 end)+(case when candidate.partner_level='low_intermediate' then 1 else 0 end);
  has_room:=candidate.status='registered' and candidate.payment_status='paid'
    and used_intermediate+need_intermediate<=event_row.intermediate_capacity
    and used_low+need_low<=event_row.low_intermediate_capacity;
  insert into kestrel_tournaments.allocations(entry_id,confirmed) values(candidate.id,has_room)
    on conflict(entry_id) do update set confirmed=excluded.confirmed;
  if has_room then used_intermediate:=used_intermediate+need_intermediate; used_low:=used_low+need_low; end if;
 end loop;
 return new;
end $$;
revoke all on function kestrel_tournaments.rebalance_doubles() from public;
create trigger tournament_doubles_allocation after insert or update on public.tournament_entries
 for each row execute function kestrel_tournaments.rebalance_doubles();

create function kestrel_tournaments.doubles_status(p_event_id bigint)
returns jsonb language plpgsql stable security definer set search_path=public,pg_temp as $$
declare result jsonb;
begin
 if auth.uid() is null or not exists(select 1 from public.profiles where id=auth.uid() and player_type_status='approved') then raise exception 'An active signed-in account is required'; end if;
 select jsonb_build_object(
  'intermediate_capacity',ev.intermediate_capacity,'low_intermediate_capacity',ev.low_intermediate_capacity,
  'intermediate_confirmed',(select coalesce(sum((case when e.player_level='intermediate' then 1 else 0 end)+(case when e.partner_level='intermediate' then 1 else 0 end)),0) from public.tournament_entries e join kestrel_tournaments.allocations a on a.entry_id=e.id where e.event_id=ev.id and a.confirmed),
  'low_intermediate_confirmed',(select coalesce(sum((case when e.player_level='low_intermediate' then 1 else 0 end)+(case when e.partner_level='low_intermediate' then 1 else 0 end)),0) from public.tournament_entries e join kestrel_tournaments.allocations a on a.entry_id=e.id where e.event_id=ev.id and a.confirmed),
  'entries',(select coalesce(jsonb_agg(jsonb_build_object('entry_id',e.id,'allocation_status',case when e.status='cancelled' then 'cancelled' when a.confirmed then 'confirmed' else 'waitlist' end)),'[]'::jsonb)
    from public.tournament_entries e left join kestrel_tournaments.allocations a on a.entry_id=e.id where e.event_id=ev.id
    and (e.user_id=auth.uid() or e.player_id=auth.uid() or e.partner_id=auth.uid() or public.is_admin()))
 ) into result from public.tournament_events ev where ev.id=p_event_id and ev.registration_format='season_badminton_doubles';
 return result;
end $$;
revoke all on function kestrel_tournaments.doubles_status(bigint) from public;
grant execute on function kestrel_tournaments.doubles_status(bigint) to authenticated;
create function public.get_badminton_tournament_status(p_event_id bigint)
returns jsonb language sql stable security invoker set search_path=public,pg_temp as $$
 select kestrel_tournaments.doubles_status(p_event_id);
$$;
revoke all on function public.get_badminton_tournament_status(bigint) from public;
grant execute on function public.get_badminton_tournament_status(bigint) to authenticated;
