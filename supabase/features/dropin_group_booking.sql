-- Group Drop-in requests: individual participant records preserve capacity, teams and attendance.
create schema kestrel_groups;
revoke all on schema kestrel_groups from public,anon;
grant usage on schema kestrel_groups to authenticated;
create table kestrel_groups.requests(
 id bigint generated always as identity primary key,
 owner_id uuid not null references public.profiles(id) on delete cascade,
 session_id bigint not null references public.sessions(id) on delete cascade,
 guest_names text[] not null check(cardinality(guest_names)>0),
 player_level text not null check(player_level in ('low_intermediate','intermediate','advanced')),
 status text not null default 'pending' check(status in ('pending','approved','rejected','cancelled','expired')),
 created_at timestamptz not null default now(),expires_at timestamptz not null,
 reviewed_at timestamptz,reviewed_by uuid references public.profiles(id),review_note text,
 unit_price numeric(10,2) not null,credit_paid numeric(10,2) not null default 0,
 eligibility_confirmed boolean not null check(eligibility_confirmed)
);
create index group_request_session_active_idx on kestrel_groups.requests(session_id,expires_at) where status='pending';
create index group_request_owner_idx on kestrel_groups.requests(owner_id,created_at);
create unique index group_request_owner_session_active_idx on kestrel_groups.requests(owner_id,session_id) where status in ('pending','approved');
create table kestrel_groups.guest_players(
 owner_id uuid not null references public.profiles(id) on delete cascade,
 full_name text not null,player_id uuid not null unique references public.profiles(id) on delete cascade,
 primary key(owner_id,full_name)
);
create table kestrel_groups.members(
 request_id bigint not null references kestrel_groups.requests(id) on delete cascade,
 player_id uuid not null references public.profiles(id) on delete cascade,
 is_lead boolean not null default false,primary key(request_id,player_id)
);
create index group_member_player_idx on kestrel_groups.members(player_id);
alter table kestrel_groups.requests enable row level security;
alter table kestrel_groups.guest_players enable row level security;
alter table kestrel_groups.members enable row level security;
create policy group_request_owner_read on kestrel_groups.requests for select to authenticated using(owner_id=(select auth.uid()) or (select public.is_admin()));
create policy group_guest_owner_read on kestrel_groups.guest_players for select to authenticated using(owner_id=(select auth.uid()) or (select public.is_admin()));
create policy group_member_owner_read on kestrel_groups.members for select to authenticated using(exists(select 1 from kestrel_groups.requests r where r.id=request_id and (r.owner_id=(select auth.uid()) or (select public.is_admin()))));
revoke all on all tables in schema kestrel_groups from public,anon,authenticated;
revoke all on all sequences in schema kestrel_groups from public,anon,authenticated;

create function kestrel_groups.activity_ids(p_session_id bigint) returns bigint[] language sql stable security definer set search_path='' as $$
 select array_agg(s.id order by s.id) from public.sessions t join public.sports sp on sp.id=t.sport_id
 join public.sessions s on s.id=t.id or (sp.name='volleyball' and s.sport_id=t.sport_id and s.location_id=t.location_id and s.session_date=t.session_date and s.start_time=t.start_time and s.end_time=t.end_time)
 where t.id=p_session_id
$$;
create function kestrel_groups.held(p_session_id bigint) returns integer language sql stable security definer set search_path='' as $$
 select coalesce(sum(cardinality(g.guest_names)+case when exists(select 1 from public.registrations r where r.user_id=g.owner_id and r.session_id=any(kestrel_groups.activity_ids(g.session_id)) and r.status='confirmed') then 0 else 1 end),0)::integer
 from kestrel_groups.requests g where g.session_id=any(kestrel_groups.activity_ids(p_session_id)) and g.status='pending' and g.expires_at>now()
$$;
create function kestrel_groups.lock_activity(p_session_id bigint) returns void language plpgsql security definer set search_path='' as $$
declare ids bigint[];begin
 perform 1 from public.sessions where id=p_session_id for update;
 if not found then raise exception 'Session not found';end if;
 ids:=kestrel_groups.activity_ids(p_session_id);
 perform pg_advisory_xact_lock(71107,ids[1]::integer);
end $$;

create function kestrel_groups.request(p_session_id bigint,p_guest_names text[],p_level text,p_eligible boolean) returns bigint language plpgsql security definer set search_path='' as $$
declare s public.sessions%rowtype; cap record; ids bigint[]; names text[]; lead_spot integer; result bigint; n text;
begin
 if auth.uid() is null or not exists(select 1 from public.profiles where id=auth.uid() and managed_by is null and player_type_status='approved') then raise exception 'An active signed-in account is required';end if;
 if p_eligible is distinct from true then raise exception 'Confirm that every guest has agreed to attend and meets the activity requirements';end if;
 if p_level is null or p_level not in ('low_intermediate','intermediate','advanced') then raise exception 'Select a valid player level';end if;
 perform kestrel_groups.lock_activity(p_session_id);
 select * into s from public.sessions where id=p_session_id;
 ids:=kestrel_groups.activity_ids(p_session_id);
 if not coalesce(s.dropin_enabled,false) or coalesce(s.dropin_spots,0)<=0 or s.status='closed' or s.availability_status='unavailable' then raise exception 'Drop-in is unavailable';end if;
 if ((s.session_date+s.start_time) at time zone 'America/Toronto')<=now()+interval '1 hour' then raise exception 'Drop-in registration closes 1 hour before the activity';end if;
 if s.registration_open_at>now() and not coalesce(s.registration_open_override,false) then raise exception 'Registration is not open yet';end if;
 if s.registration_deadline<now() then raise exception 'Registration deadline has passed';end if;
 if exists(select 1 from public.permanent_assignments where user_id=auth.uid() and session_id=any(ids)) then raise exception 'Use a different Drop-in activity for a group booking; your Season spot is managed separately';end if;
 update kestrel_groups.requests set status='expired' where owner_id=auth.uid() and session_id=any(ids) and status='pending' and expires_at<=now();
 if exists(select 1 from kestrel_groups.requests where owner_id=auth.uid() and session_id=any(ids) and status in ('pending','approved')) then raise exception 'You already have an active group request for this activity';end if;
 if exists(select 1 from public.registrations where user_id=auth.uid() and session_id=any(ids) and status in ('pending','waitlist')) then raise exception 'Leave your existing waitlist or pending booking before requesting a group';end if;
 if exists(select 1 from public.registrations where user_id=auth.uid() and session_id=any(ids) and status='confirmed' and session_id<>p_session_id) then raise exception 'Use the session where you already hold a spot';end if;
 select array_agg(regexp_replace(btrim(x),'[[:space:]]+',' ','g') order by i) into names from unnest(p_guest_names) with ordinality a(x,i);
 if names is null or cardinality(names)<1 or cardinality(names)>=s.capacity then raise exception 'Enter guest names for a group that fits this activity';end if;
 if (select count(distinct lower(x)) from unnest(names) x)<>cardinality(names) then raise exception 'Enter each guest once';end if;
 foreach n in array names loop
  if n is null or public.classify_player_name(n)='invalid' then raise exception 'Enter a real name for every guest';end if;
  if exists(select 1 from public.profiles where id=auth.uid() and lower(full_name)=lower(n)) then raise exception 'The group total already includes you; enter guests only';end if;
  if exists(select 1 from kestrel_groups.guest_players g join public.registrations r on r.user_id=g.player_id where g.owner_id=auth.uid() and lower(g.full_name)=lower(n) and r.session_id=any(ids) and r.status in ('confirmed','pending','waitlist')) then raise exception '% already has a spot in this activity',n;end if;
 end loop;
 select * into cap from public.get_dropin_session_availability(array[p_session_id]);
 select case when exists(select 1 from public.registrations where user_id=auth.uid() and session_id=p_session_id and status='confirmed') then 1 else 0 end into lead_spot;
 if cap.total_capacity-cap.occupied < cardinality(names)+1-lead_spot then raise exception 'Not enough spots: % available, % required',greatest(cap.total_capacity-cap.occupied,0),cardinality(names)+1-lead_spot;end if;
 insert into kestrel_groups.requests(owner_id,session_id,guest_names,player_level,expires_at,unit_price,eligibility_confirmed)
 values(auth.uid(),p_session_id,names,p_level,least(now()+interval '24 hours',((s.session_date+s.start_time) at time zone 'America/Toronto')-interval '1 hour'),coalesce(s.price,0),true)
 returning id into result;
 return result;
end $$;

create function kestrel_groups.review(p_request_id bigint,p_approve boolean,p_note text) returns void language plpgsql security definer set search_path='' as $$
declare g kestrel_groups.requests%rowtype;s public.sessions%rowtype;cap record;pid uuid;uid uuid;n text;needed integer;credit numeric:=0; ids bigint[];
begin
 if auth.uid() is null or not public.is_admin() then raise exception 'Admin access required';end if;
 if p_approve is null then raise exception 'Choose approve or reject';end if;
 select * into g from kestrel_groups.requests where id=p_request_id;
 if not found then raise exception 'Group request not found';end if;
 perform kestrel_groups.lock_activity(g.session_id);
 select * into g from kestrel_groups.requests where id=p_request_id for update;
 if g.status<>'pending' then raise exception 'This group request has already been reviewed';end if;
 if not p_approve then
  update kestrel_groups.requests set status='rejected',reviewed_by=auth.uid(),reviewed_at=now(),review_note=left(p_note,500) where id=g.id;
  perform kestrel_groups.promote(g.session_id);return;
 end if;
 select * into s from public.sessions where id=g.session_id;
 ids:=kestrel_groups.activity_ids(g.session_id);
 if g.expires_at<=now() or ((s.session_date+s.start_time) at time zone 'America/Toronto')<=now()+interval '1 hour' then raise exception 'This request has expired';end if;
 if not s.dropin_enabled or s.status='closed' or s.availability_status='unavailable' then raise exception 'This session is unavailable';end if;
 if not exists(select 1 from public.profiles where id=g.owner_id and player_type_status='approved' and managed_by is null) then raise exception 'The group organiser account is inactive';end if;
 select cardinality(g.guest_names)+case when exists(select 1 from public.registrations where user_id=g.owner_id and session_id=g.session_id and status='confirmed') then 0 else 1 end into needed;
 if exists(select 1 from public.registrations where user_id=g.owner_id and session_id=g.session_id and status='confirmed' and payment_status='paid') then credit:=coalesce(s.price,0);end if;
 update kestrel_groups.requests set status='approved',unit_price=coalesce(s.price,0),credit_paid=credit,reviewed_by=auth.uid(),reviewed_at=now(),review_note=left(p_note,500) where id=g.id;
 select * into cap from public.get_dropin_session_availability(array[g.session_id]);
 if cap.total_capacity-cap.occupied<needed then raise exception 'There are no longer enough spots for the whole group';end if;
 insert into kestrel_groups.members(request_id,player_id,is_lead) values(g.id,g.owner_id,true);
 foreach n in array g.guest_names loop
  select player_id into pid from kestrel_groups.guest_players where owner_id=g.owner_id and lower(full_name)=lower(n);
  if pid is null then
   pid:=gen_random_uuid();
   insert into public.profiles(id,full_name,managed_by,player_type,requested_player_type,player_type_status,is_admin,preferred_name_completed,whatsapp_contact_completed)
   values(pid,n,g.owner_id,'dropin','dropin','approved',false,true,true);
   insert into kestrel_groups.guest_players(owner_id,full_name,player_id) values(g.owner_id,n,pid);
  end if;
  if exists(select 1 from public.registrations where user_id=pid and session_id=any(ids) and status in ('confirmed','pending','waitlist')) then raise exception '% already has a spot',n;end if;
  insert into kestrel_groups.members(request_id,player_id,is_lead) values(g.id,pid,false);
 end loop;
 for uid in select player_id from kestrel_groups.members where request_id=g.id order by is_lead desc,player_id loop
  insert into public.registrations(user_id,session_id,status,payment_status,registration_type,player_level,registered_at)
  values(uid,g.session_id,'confirmed','unpaid','dropin',g.player_level,now())
  on conflict(user_id,session_id) do update set status='confirmed',payment_status='unpaid',registration_type='dropin',player_level=excluded.player_level,registered_at=now();
 end loop;
end $$;

create function kestrel_groups.cancel(p_request_id bigint) returns void language plpgsql security definer set search_path='' as $$
declare g kestrel_groups.requests%rowtype;
begin
 if auth.uid() is null then raise exception 'Sign in required';end if;
 select * into g from kestrel_groups.requests where id=p_request_id;
 if not found or (g.owner_id<>auth.uid() and not public.is_admin()) then raise exception 'Group request not found';end if;
 perform kestrel_groups.lock_activity(g.session_id);
 select * into g from kestrel_groups.requests where id=p_request_id for update;
 if g.status='approved' then
  update public.registrations set status='cancelled' where session_id=g.session_id and user_id=g.owner_id and status='confirmed';
 elsif g.status='pending' then
  update kestrel_groups.requests set status='cancelled' where id=g.id;
 end if;
 perform kestrel_groups.promote(g.session_id);
end $$;

create function kestrel_groups.list_requests() returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
 if auth.uid() is null then raise exception 'Sign in required';end if;
 select coalesce(jsonb_agg(x order by x->>'created_at' desc),'[]'::jsonb) into result from (
 select jsonb_build_object('id',g.id,'owner_id',g.owner_id,'owner_name',p.full_name,'session_id',g.session_id,
 'guest_names',g.guest_names,'total_people',cardinality(g.guest_names)+1,'status',case when g.status='pending' and g.expires_at<=now() then 'expired' else g.status end,
 'created_at',g.created_at,'expires_at',g.expires_at,'review_note',g.review_note,'unit_price',g.unit_price,
 'total_price',g.unit_price*(cardinality(g.guest_names)+1),'credit_paid',g.credit_paid,'amount_due',greatest(g.unit_price*(cardinality(g.guest_names)+1)-g.credit_paid,0),
 'session_date',s.session_date,'start_time',s.start_time,'end_time',s.end_time,'sport',sp.name,'location',l.name,'court',s.court,
 'player_level',g.player_level,'member_ids',(select coalesce(jsonb_agg(m.player_id),'[]'::jsonb) from kestrel_groups.members m where m.request_id=g.id)) as x
 from kestrel_groups.requests g join public.profiles p on p.id=g.owner_id join public.sessions s on s.id=g.session_id
 join public.sports sp on sp.id=s.sport_id join public.locations l on l.id=s.location_id
 where s.session_date>=(now() at time zone 'America/Toronto')::date and (g.owner_id=auth.uid() or public.is_admin())
 ) q; return result;
end $$;

-- A cancelled/removed group member releases the whole group; one payment covers the group.
create function kestrel_groups.sync_registration() returns trigger language plpgsql security definer set search_path='' as $$
declare g kestrel_groups.requests%rowtype;
begin
 if tg_op='DELETE' then
  select q.* into g from kestrel_groups.requests q join kestrel_groups.members m on m.request_id=q.id
  where q.status='approved' and q.session_id=old.session_id and m.player_id=old.user_id;
 else
  select q.* into g from kestrel_groups.requests q join kestrel_groups.members m on m.request_id=q.id
  where q.status='approved' and q.session_id=new.session_id and m.player_id=new.user_id;
 end if;
 if not found then
  if tg_op<>'DELETE' and old.status='confirmed' and new.status='cancelled' then
   update kestrel_groups.requests set status='cancelled' where owner_id=new.user_id and session_id=new.session_id and status='pending';
  end if;
  return null;
 end if;
 if tg_op='DELETE' or (old.status='confirmed' and new.status='cancelled') then
  update kestrel_groups.requests set status='cancelled' where id=g.id;
  update public.registrations r set status='cancelled',
   payment_status=case when tg_op<>'DELETE' and new.payment_status='removed' then 'removed' else r.payment_status end
  where r.session_id=g.session_id and r.user_id in(select player_id from kestrel_groups.members where request_id=g.id) and r.status in ('confirmed','pending','waitlist');
 elsif old.payment_status is distinct from new.payment_status and new.payment_status in ('paid','unpaid') then
  update public.registrations r set payment_status=new.payment_status where r.session_id=g.session_id
   and r.user_id in(select player_id from kestrel_groups.members where request_id=g.id) and r.status='confirmed' and r.payment_status is distinct from new.payment_status;
 end if;
 return null;
end $$;
create trigger aa_sync_dropin_group after update of status,payment_status or delete on public.registrations for each row execute function kestrel_groups.sync_registration();

-- Enforce the same held capacity even for legacy or direct registration write paths.
create function kestrel_groups.guard_capacity() returns trigger language plpgsql security definer set search_path='' as $$
declare cap record;ids bigint[];
begin
 if new.status<>'confirmed' then return new;end if;
 if tg_op='UPDATE' and old.status='confirmed' and old.session_id=new.session_id and old.user_id=new.user_id then return new;end if;
 ids:=kestrel_groups.activity_ids(new.session_id);
 if not exists(select 1 from kestrel_groups.requests where session_id=any(ids) and status in ('pending','approved')) then return new;end if;
 perform kestrel_groups.lock_activity(new.session_id);
 select * into cap from public.get_dropin_session_availability(array[new.session_id]);
 if cap.occupied>=cap.total_capacity then raise exception 'No spots available; some spots may be held for group approval';end if;
 return new;
end $$;
create trigger zz_dropin_group_capacity before insert or update of status,session_id on public.registrations for each row execute function kestrel_groups.guard_capacity();

create or replace function kestrel_groups.promote(p_session_id bigint) returns void language plpgsql security definer set search_path='' as $$
declare cap record;rid bigint;ids bigint[];target_id bigint;
begin
 select id into target_id from public.sessions where id=any(kestrel_groups.activity_ids(p_session_id)) and dropin_enabled and status<>'closed' and availability_status='available' and ((session_date+start_time) at time zone 'America/Toronto')>now()+interval '1 hour' order by id limit 1;
 if target_id is null then return;end if;
 perform kestrel_groups.lock_activity(target_id);ids:=kestrel_groups.activity_ids(target_id);
 loop
  select * into cap from public.get_dropin_session_availability(array[target_id]);
  exit when cap.occupied>=cap.total_capacity;
  select r.id into rid from public.registrations r join public.profiles p on p.id=r.user_id where r.session_id=any(ids) and r.status='waitlist' and p.player_type_status='approved'
   and not exists(select 1 from public.registrations other where other.user_id=r.user_id and other.session_id=any(ids) and other.status='confirmed')
   order by r.registered_at,r.id limit 1 for update of r;
  exit when rid is null;
  update public.registrations set status='confirmed',payment_status='unpaid' where id=rid;
 end loop;
end $$;

create function kestrel_groups.roster(p_session_id bigint) returns table(player_name text,is_me boolean,party_size integer) language plpgsql stable security definer set search_path='' as $$
declare ids bigint[];
begin
 ids:=kestrel_groups.activity_ids(p_session_id);
 if auth.uid() is null or not (
  exists(select 1 from public.registrations where session_id=any(ids) and user_id=auth.uid() and status='confirmed')
  or exists(select 1 from public.permanent_assignments pa where session_id=any(ids) and user_id=auth.uid()
   and not exists(select 1 from public.absences a where a.session_id=pa.session_id and a.user_id=pa.user_id and a.not_coming)
   and not exists(select 1 from public.registrations r where r.session_id=pa.session_id and r.user_id=pa.user_id and r.status='cancelled'))
 ) then raise exception 'You must be attending this activity to view its roster';end if;
 return query with attendees as (
  select r.user_id from public.registrations r where r.session_id=any(ids) and r.status='confirmed'
   and not exists(select 1 from public.absences a where a.session_id=r.session_id and a.user_id=r.user_id and a.not_coming)
  union select pa.user_id from public.permanent_assignments pa where pa.session_id=any(ids)
   and not exists(select 1 from public.absences a where a.session_id=pa.session_id and a.user_id=pa.user_id and a.not_coming)
   and not exists(select 1 from public.registrations r where r.session_id=pa.session_id and r.user_id=pa.user_id and r.status='cancelled')
 ), grouped as (
  select coalesce(g.owner_id,a.user_id) as lead_id,count(*)::integer as size
  from attendees a left join kestrel_groups.members m on m.player_id=a.user_id
   and exists(select 1 from kestrel_groups.requests q where q.id=m.request_id and q.status='approved' and q.session_id=any(ids))
  left join kestrel_groups.requests g on g.id=m.request_id and g.status='approved' and g.session_id=any(ids)
  group by coalesce(g.owner_id,a.user_id)
 )
 select (coalesce(nullif(p.full_name,''),'Player')||case when g.size>1 then ' + '||(g.size-1)::text else '' end)::text,
 (g.lead_id=auth.uid()),g.size from grouped g join public.profiles p on p.id=g.lead_id order by (g.lead_id=auth.uid()) desc,p.full_name;
end $$;

create function public.request_dropin_group(p_session_id bigint,p_guest_names text[],p_level text,p_eligible boolean) returns bigint language sql security invoker set search_path='' as $$select kestrel_groups.request(p_session_id,p_guest_names,p_level,p_eligible)$$;
create function public.review_dropin_group(p_request_id bigint,p_approve boolean,p_note text default null) returns void language sql security invoker set search_path='' as $$select kestrel_groups.review(p_request_id,p_approve,p_note)$$;
create function public.cancel_dropin_group(p_request_id bigint) returns void language sql security invoker set search_path='' as $$select kestrel_groups.cancel(p_request_id)$$;
create function public.list_dropin_groups() returns jsonb language sql security invoker set search_path='' as $$select kestrel_groups.list_requests()$$;
create function public.get_grouped_dropin_roster(p_session_id bigint) returns table(player_name text,is_me boolean,party_size integer) language sql security invoker set search_path='' as $$select * from kestrel_groups.roster(p_session_id)$$;
revoke all on all functions in schema kestrel_groups from public,anon,authenticated;
grant execute on function kestrel_groups.request(bigint,text[],text,boolean),kestrel_groups.review(bigint,boolean,text),kestrel_groups.cancel(bigint),kestrel_groups.list_requests(),kestrel_groups.roster(bigint) to authenticated;
revoke all on function public.request_dropin_group(bigint,text[],text,boolean),public.review_dropin_group(bigint,boolean,text),public.cancel_dropin_group(bigint),public.list_dropin_groups(),public.get_grouped_dropin_roster(bigint) from public,anon;
grant execute on function public.request_dropin_group(bigint,text[],text,boolean),public.review_dropin_group(bigint,boolean,text),public.cancel_dropin_group(bigint),public.list_dropin_groups(),public.get_grouped_dropin_roster(bigint) to authenticated;

-- Existing registration entry points account for pending group holds.

CREATE OR REPLACE FUNCTION public.get_volleyball_activity_capacity(p_session_id bigint)
 RETURNS TABLE(activity_ids bigint[], occupied integer, total_capacity integer)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
with related as (
 select s.id,s.capacity from sessions target join sports sp on sp.id=target.sport_id
 join sessions s on s.id=target.id or (
  sp.name='volleyball' and s.sport_id=target.sport_id and s.location_id=target.location_id
  and s.session_date=target.session_date and s.start_time=target.start_time and s.end_time=target.end_time)
 where target.id=p_session_id
), attendees as (
 select r.user_id from registrations r join related s on s.id=r.session_id
 where r.status='confirmed' and not exists(select 1 from absences a where a.session_id=r.session_id and a.user_id=r.user_id and a.not_coming=true)
 union
 select pa.user_id from permanent_assignments pa join related s on s.id=pa.session_id
 where not exists(select 1 from absences a where a.session_id=pa.session_id and a.user_id=pa.user_id and a.not_coming=true)
 and not exists(select 1 from registrations r where r.session_id=pa.session_id and r.user_id=pa.user_id and r.status='cancelled')
)
select (select array_agg(id order by id) from related),((select count(*)::integer from attendees)+kestrel_groups.held(p_session_id)),(select min(capacity)::integer from related)
$function$;


CREATE OR REPLACE FUNCTION public.get_dropin_session_availability(p_session_ids bigint[])
 RETURNS TABLE(session_id bigint, occupied integer, total_capacity integer, is_full boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
with relevant as (select id,capacity,dropin_spots from public.sessions where id=any(p_session_ids) and dropin_enabled=true),
counts as (select s.id,
(select count(*) from public.registrations r where r.session_id=s.id and r.status='confirmed')::integer as confirmed,
(select count(*) from public.permanent_assignments pa where pa.session_id=s.id and not exists(select 1 from public.absences a where a.session_id=s.id and a.user_id=pa.user_id and a.not_coming=true) and not exists(select 1 from public.registrations r where r.session_id=s.id and r.user_id=pa.user_id))::integer as season,
s.capacity,s.dropin_spots from relevant s)
select c.id,
 case when sp.name='volleyball' then a.occupied else c.confirmed+c.season+kestrel_groups.held(c.id) end,
 case when sp.name='volleyball' then a.total_capacity else least(coalesce(c.capacity,0),coalesce(c.dropin_spots,c.capacity,0)+c.season) end,
 case when sp.name='volleyball' then a.occupied>=a.total_capacity else c.confirmed+c.season+kestrel_groups.held(c.id)>=least(coalesce(c.capacity,0),coalesce(c.dropin_spots,c.capacity,0)+c.season) end
 from counts c join public.sessions target on target.id=c.id join public.sports sp on sp.id=target.sport_id
 cross join lateral public.get_volleyball_activity_capacity(c.id) a
$function$;


CREATE OR REPLACE FUNCTION public.register_dropin(p_session_id bigint, p_player_level text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare s public.sessions%rowtype; confirmed_count integer; season_count integer; effective_capacity integer; v_ids bigint[];
begin
 if auth.uid() is null then raise exception 'You must be signed in'; end if;
 if exists(select 1 from kestrel_groups.requests where owner_id=auth.uid() and session_id=any(kestrel_groups.activity_ids(p_session_id)) and status='pending' and expires_at>now()) then raise exception 'Your group request is awaiting Admin approval';end if;
 if p_player_level not in ('low_intermediate','intermediate','advanced') then raise exception 'Please select a valid player level'; end if;
 select * into s from public.sessions where id=p_session_id for update;
 if not found then raise exception 'Session not found'; end if;
 if ((s.session_date+s.start_time) at time zone 'America/Toronto')<=now()+interval '1 hour' then raise exception 'Drop-in registration closes 1 hour before the activity.'; end if;
 if exists(select 1 from public.sports sp where sp.id=s.sport_id and sp.name='volleyball') then
 select activity_ids into v_ids from public.get_volleyball_activity_capacity(p_session_id);
 perform pg_advisory_xact_lock(71107,v_ids[1]::integer);
 if exists(select 1 from public.registrations r where r.user_id=auth.uid() and r.session_id=any(v_ids) and r.status in ('pending','confirmed','waitlist')) then return 'already_registered'; end if;
 end if;
 if not coalesce(s.dropin_enabled,false) or coalesce(s.dropin_spots,0)<=0 then raise exception 'Drop-in is not available for this session'; end if;
 if s.status='closed' or s.availability_status='unavailable' then raise exception 'This activity is unavailable'; end if;
 if ((s.session_date+s.start_time) at time zone 'America/Toronto')<=now() then raise exception 'This session has already started'; end if;
 if s.registration_open_at is not null and now()<s.registration_open_at and not coalesce(s.registration_open_override,false) then raise exception 'Registration opens at %',to_char(s.registration_open_at at time zone 'America/Toronto','FMDay, FMMonth DD at HH12:MI AM'); end if;
 if s.registration_deadline is not null and now()>s.registration_deadline then raise exception 'Registration deadline has passed'; end if;
 if exists(select 1 from public.registrations where user_id=auth.uid() and session_id=p_session_id and status in ('pending','confirmed','waitlist')) then return 'already_registered'; end if;
 select count(*)+kestrel_groups.held(p_session_id) into confirmed_count from public.registrations where session_id=p_session_id and status='confirmed';
 select count(*) into season_count from public.permanent_assignments pa left join public.absences a on a.session_id=pa.session_id and a.user_id=pa.user_id where pa.session_id=p_session_id and not coalesce(a.not_coming,false) and not exists(select 1 from public.registrations r where r.session_id=p_session_id and r.user_id=pa.user_id);
 effective_capacity:=least(coalesce(s.capacity,0),coalesce(s.dropin_spots,s.capacity,0)+season_count);
 if exists(select 1 from public.sports sp where sp.id=s.sport_id and sp.name='volleyball') then
 select occupied,total_capacity into confirmed_count,effective_capacity from public.get_volleyball_activity_capacity(p_session_id);
 season_count:=0;
 end if;
 if confirmed_count+season_count>=effective_capacity then
 insert into public.registrations(user_id,session_id,status,payment_status,player_level) values(auth.uid(),p_session_id,'waitlist','unpaid',p_player_level)
 on conflict(user_id,session_id) do update set status='waitlist',payment_status='unpaid',player_level=excluded.player_level,registration_type='dropin',registered_at=now();
 return 'waitlist';end if;
 insert into public.registrations(user_id,session_id,status,payment_status,player_level) values(auth.uid(),p_session_id,'confirmed','unpaid',p_player_level)
 on conflict(user_id,session_id) do update set status='confirmed',payment_status='unpaid',player_level=excluded.player_level,registration_type='dropin',registered_at=now();
 return 'confirmed';
end $function$;


CREATE OR REPLACE FUNCTION public.rejoin_my_session(p_session_id bigint)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
 v_uid uuid := auth.uid();
 v_s public.sessions%rowtype;
 v_season boolean;
 v_existing text;
 v_occupied integer;
 v_limit integer;
 v_level text; v_ids bigint[];
begin
 if v_uid is null then raise exception 'Sign in required'; end if;
 select * into v_s from public.sessions where id=p_session_id for update;
 if not found then raise exception 'Session not found'; end if;
 if exists(select 1 from public.sports sp where sp.id=v_s.sport_id and sp.name='volleyball') then
 select activity_ids into v_ids from public.get_volleyball_activity_capacity(p_session_id);
 perform pg_advisory_xact_lock(71107,v_ids[1]::integer);
 end if;
 if v_s.session_date < (now() at time zone 'America/Toronto')::date
   or (v_s.session_date = (now() at time zone 'America/Toronto')::date and v_s.start_time <= (now() at time zone 'America/Toronto')::time)
 then raise exception 'Session already started'; end if;
 if v_s.status='closed' or v_s.availability_status='unavailable' then raise exception 'Session unavailable'; end if;
 select exists(select 1 from public.permanent_assignments pa where pa.session_id=p_session_id and pa.user_id=v_uid)
 into v_season;
 select status,player_level into v_existing,v_level from public.registrations
 where session_id=p_session_id and user_id=v_uid for update;
 if v_season then
   if not exists(select 1 from public.profiles where id=v_uid and player_type='permanent' and player_type_status='approved') then
     raise exception 'Season approval required';
   end if;
   if not coalesce((select not_coming from public.absences where user_id=v_uid and session_id=p_session_id),false)
      and coalesce(v_existing,'confirmed')='confirmed' then return 'already_registered'; end if;
 else
   if ((v_s.session_date+v_s.start_time) at time zone 'America/Toronto')<=now()+interval '1 hour' then raise exception 'Drop-in registration closes 1 hour before the activity.'; end if;
   if not exists(select 1 from public.profiles where id=v_uid and player_type_status='approved')
     then raise exception 'Drop-in approval required'; end if;
   if v_existing is null or v_existing not in ('cancelled','removed','not_going')
     then raise exception 'No cancelled registration to rejoin'; end if;
   if not coalesce(v_s.dropin_enabled,false) then raise exception 'Drop-in unavailable'; end if;
   if v_s.registration_open_at is not null and now()<v_s.registration_open_at and not coalesce(v_s.registration_open_override,false)
     then raise exception 'Registration is not open yet'; end if;
   if v_s.registration_deadline is not null and now()>v_s.registration_deadline then raise exception 'Registration deadline has passed'; end if;
 end if;
 select count(*) into v_occupied from (
   select r.user_id from public.registrations r where r.session_id=p_session_id and r.status='confirmed'
   union
   select pa.user_id from public.permanent_assignments pa
     left join public.absences a on a.session_id=pa.session_id and a.user_id=pa.user_id
     where pa.session_id=p_session_id and not coalesce(a.not_coming,false)
       and not exists(select 1 from public.registrations r where r.session_id=p_session_id and r.user_id=pa.user_id and r.status in ('cancelled','removed','not_going'))
 ) occupied;
 v_limit:=greatest(coalesce(v_s.capacity,0),0);
 if v_ids is not null then select occupied,total_capacity into v_occupied,v_limit from public.get_volleyball_activity_capacity(p_session_id); else v_occupied:=v_occupied+kestrel_groups.held(p_session_id);end if;
 if v_occupied>=v_limit then return 'full'; end if;
 if v_season then
   insert into public.absences(user_id,session_id,not_coming) values(v_uid,p_session_id,false)
     on conflict(user_id,session_id) do update set not_coming=false;
   insert into public.registrations(user_id,session_id,status,payment_status,registration_type)
     values(v_uid,p_session_id,'confirmed','paid','season')
     on conflict(user_id,session_id) do update set status='confirmed',registration_type='season',payment_status='paid';
 else
   insert into public.registrations(user_id,session_id,status,payment_status,player_level,registration_type)
     values(v_uid,p_session_id,'confirmed','unpaid',v_level,'dropin')
     on conflict(user_id,session_id) do update set status='confirmed',payment_status='unpaid',registered_at=now();
 end if;
 return 'confirmed';
end $function$;


CREATE OR REPLACE FUNCTION public.admin_add_player_to_activity(p_session_id bigint, p_user_id uuid)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ DECLARE sess public.sessions%ROWTYPE; existing public.registrations%ROWTYPE; active_count integer; result_status text; v_ids bigint[]; BEGIN IF auth.uid() IS NULL OR NOT EXISTS(SELECT 1 FROM public.profiles WHERE id=auth.uid() AND is_admin=true) THEN RAISE EXCEPTION 'Admin access required'; END IF; SELECT * INTO sess FROM public.sessions WHERE id=p_session_id FOR UPDATE; IF NOT FOUND THEN RAISE EXCEPTION 'Activity not found'; END IF; IF NOT EXISTS(SELECT 1 FROM public.profiles WHERE id=p_user_id AND player_type_status='approved') THEN RAISE EXCEPTION 'Player not approved or not found'; END IF; IF EXISTS(select 1 from public.sports sp where sp.id=sess.sport_id and sp.name='volleyball') THEN
 SELECT activity_ids INTO v_ids FROM public.get_volleyball_activity_capacity(p_session_id);
 PERFORM pg_advisory_xact_lock(71107,v_ids[1]::integer);
 IF EXISTS(select 1 from public.registrations r where r.session_id=any(v_ids) and r.user_id=p_user_id and r.status in ('confirmed','pending','waitlist')) THEN RAISE EXCEPTION 'Player is already registered for this activity'; END IF;
 END IF; SELECT * INTO existing FROM public.registrations WHERE session_id=p_session_id AND user_id=p_user_id; IF FOUND AND existing.status IN ('confirmed','pending','waitlist') THEN RAISE EXCEPTION 'Player is already registered for this activity'; END IF; SELECT count(*)+kestrel_groups.held(p_session_id) INTO active_count FROM public.registrations WHERE session_id=p_session_id AND status='confirmed'; IF v_ids IS NOT NULL THEN SELECT occupied,total_capacity INTO active_count,sess.capacity FROM public.get_volleyball_activity_capacity(p_session_id); END IF; result_status:=CASE WHEN active_count>=sess.capacity THEN 'waitlist' ELSE 'confirmed' END; INSERT INTO public.registrations(user_id,session_id,status,payment_status,registration_type) VALUES(p_user_id,p_session_id,result_status,'unpaid','dropin') ON CONFLICT(user_id,session_id) DO UPDATE SET status=excluded.status,payment_status=excluded.payment_status,registration_type='dropin'; RETURN result_status; END $function$;


CREATE OR REPLACE FUNCTION public.kestrel_promote_waitlist_on_vacancy() returns trigger language plpgsql security definer set search_path='' as $$
begin if old.status='confirmed' and new.status is distinct from old.status then perform kestrel_groups.promote(old.session_id);end if;return new;end $$;
CREATE OR REPLACE FUNCTION public.process_dropin_payment_cutoffs() returns void language plpgsql security definer set search_path='' as $$
declare s record;begin
 update kestrel_groups.requests set status='expired' where status='pending' and expires_at<=now();
 perform public.remove_expired_unpaid_dropins();
 for s in select distinct se.id from public.sessions se join public.registrations r on r.session_id=se.id and r.status='waitlist'
 where se.dropin_enabled and ((se.session_date+se.start_time) at time zone 'America/Toronto')>now()+interval '1 hour'
 loop perform kestrel_groups.promote(s.id);end loop;
end $$;
CREATE OR REPLACE FUNCTION public.get_my_confirmed_session_roster(p_session_id bigint) returns table(player_name text,is_me boolean) language sql stable security definer set search_path='' as $$
select r.player_name,r.is_me from kestrel_groups.roster(p_session_id) r
$$;


