-- Tournament entries are separate from recurring sessions and drop-in cleanup.
alter table public.sports drop constraint sports_name_check;
alter table public.sports add constraint sports_name_check
  check (name in ('badminton','volleyball','soccer','pickleball','basketball'));
create table public.tournament_events (
  id bigint generated always as identity primary key,
  slug text not null unique,
  title text not null,
  sport_id bigint not null references public.sports(id),
  city text not null,
  location_details text not null default 'Inbox for location details',
  starts_at timestamptz not null,
  individual_fee numeric(10,2) not null check (individual_fee >= 0),
  team_fee numeric(10,2) not null check (team_fee >= 0),
  minimum_age integer not null default 16 check (minimum_age >= 0),
  payment_email text,
  status text not null default 'open' check (status in ('open','closed','cancelled')),
  created_at timestamptz not null default now()
);
create table public.tournament_entries (
  id bigint generated always as identity primary key,
  event_id bigint not null references public.tournament_events(id),
  user_id uuid not null references public.profiles(id),
  entry_kind text not null check (entry_kind in ('individual','team')),
  team_name text,
  player_names text[] not null,
  eligibility_confirmed boolean not null check (eligibility_confirmed),
  status text not null default 'registered' check (status in ('registered','cancelled')),
  payment_status text not null default 'unpaid' check (payment_status in ('unpaid','paid')),
  created_at timestamptz not null default now(),
  unique(event_id,user_id),
  check (cardinality(player_names) between 1 and 100),
  check ((entry_kind='individual' and cardinality(player_names)=1 and team_name is null)
    or (entry_kind='team' and team_name is not null and length(btrim(team_name)) between 1 and 100))
);
create index tournament_entries_user_idx on public.tournament_entries(user_id);
alter table public.tournament_events enable row level security;
alter table public.tournament_entries enable row level security;
revoke all on public.tournament_events,public.tournament_entries from anon,authenticated;
grant select on public.tournament_events to authenticated;
grant insert,update,delete on public.tournament_events to authenticated;
grant select,insert,update on public.tournament_entries to authenticated;
grant usage,select on sequence public.tournament_events_id_seq,public.tournament_entries_id_seq to authenticated;
create policy tournament_events_read on public.tournament_events for select to authenticated using (true);
create policy tournament_events_admin on public.tournament_events for all to authenticated
  using ((select public.is_admin())) with check ((select public.is_admin()));
create policy tournament_entries_read on public.tournament_entries for select to authenticated
  using (user_id=(select auth.uid()) or (select public.is_admin()));
create policy tournament_entries_insert on public.tournament_entries for insert to authenticated
  with check (user_id=(select auth.uid()) and exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.player_type_status='approved'));
create policy tournament_entries_update on public.tournament_entries for update to authenticated
  using (user_id=(select auth.uid()) or (select public.is_admin()))
  with check (user_id=(select auth.uid()) or (select public.is_admin()));

-- Validate dates and immutable ownership on the server, including direct API calls.
create function public.validate_tournament_entry() returns trigger language plpgsql
security invoker set search_path=public,pg_temp as $$
declare event_row public.tournament_events; player_name text; admin_actor boolean;
begin
  admin_actor:=coalesce(public.is_admin(),false);
  if TG_OP='UPDATE' and (new.user_id<>old.user_id or new.event_id<>old.event_id or new.created_at<>old.created_at) then
    raise exception 'Entry ownership, event and creation date cannot be changed';
  end if;
  select * into strict event_row from public.tournament_events where id=new.event_id;
  if not admin_actor then
    if auth.uid() is null or new.user_id<>auth.uid() or not exists(select 1 from public.profiles where id=auth.uid() and player_type_status='approved') then
      raise exception 'An active account is required';
    end if;
    if event_row.status<>'open' or event_row.starts_at<=now() then
      raise exception 'Tournament registration is closed. Contact Admin for changes';
    end if;
    if TG_OP='INSERT' then
      new.created_at:=now();
      if new.payment_status<>'unpaid' or new.status<>'registered' then
        raise exception 'Register first, then record payment after sending it';
      end if;
    else
      if old.payment_status='paid' and new.payment_status<>'paid' then
        raise exception 'Contact Admin to change a paid entry';
      end if;
      if old.payment_status='paid' and (new.entry_kind<>old.entry_kind or new.team_name is distinct from old.team_name or new.player_names<>old.player_names) then
        raise exception 'Contact Admin to change a paid entry';
      end if;
      if new.payment_status='paid' and (new.status<>'registered' or old.status<>'registered') and new.payment_status<>old.payment_status then
        raise exception 'Only an active registration can be marked paid';
      end if;
    end if;
  end if;
  foreach player_name in array new.player_names loop
    if player_name is null or length(btrim(player_name)) not between 2 and 100 then
      raise exception 'Enter a real player name for each participant';
    end if;
  end loop;
  return new;
end $$;
revoke all on function public.validate_tournament_entry() from public;
create trigger validate_tournament_entry before insert or update on public.tournament_entries
  for each row execute function public.validate_tournament_entry();

insert into public.sports(name) values ('basketball') on conflict (name) do nothing;
insert into public.tournament_events(slug,title,sport_id,city,starts_at,individual_fee,team_fee,minimum_age)
select 'brampton-basketball-2026-10-30','Brampton Basketball Tournament',id,'Brampton',
  '2026-10-30 18:00:00 America/Toronto'::timestamptz,7,30,16
from public.sports where name='basketball';
