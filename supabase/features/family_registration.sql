-- Family participants share an account, but retain separate player IDs and roster records.
create schema if not exists kestrel_family;
revoke all on schema kestrel_family from public, anon;
grant usage on schema kestrel_family to authenticated;

alter table public.profiles add column managed_by uuid references auth.users(id) on delete cascade;
alter table public.profiles add column login_identity_id uuid generated always as (case when managed_by is null then id else null end) stored;
alter table public.profiles add constraint profiles_login_identity_fkey foreign key(login_identity_id) references auth.users(id) on delete cascade;
alter table public.profiles drop constraint profiles_id_fkey;
alter table public.profiles add constraint family_profile_not_admin check(managed_by is null or (not is_admin and managed_by<>id));
create index profiles_managed_by_idx on public.profiles(managed_by) where managed_by is not null;

create table kestrel_family.members(
 player_id uuid primary key references public.profiles(id) on delete cascade,
 relationship text not null check(relationship in ('child','spouse','other')),
 age_years integer not null check(age_years between 1 and 120),
 consent_at timestamptz not null default now()
);
alter table kestrel_family.members enable row level security;
create policy family_details_owner_read on kestrel_family.members for select to authenticated
 using(exists(select 1 from public.profiles p where p.id=player_id and p.managed_by=(select auth.uid())) or (select public.is_admin()));
-- Details are returned only by the authenticated, ownership-checked functions below.
revoke all on kestrel_family.members from public,anon,authenticated;

create function kestrel_family.protect_identity() returns trigger language plpgsql set search_path='' as $$
begin
 if TG_OP='UPDATE' and (new.id is distinct from old.id or new.managed_by is distinct from old.managed_by) then
  raise exception 'Player identity and family ownership cannot be changed';
 end if;
 if TG_OP='INSERT' and new.managed_by is not null and current_user in ('anon','authenticated') then
  raise exception 'Use Add family member to create a linked player';
 end if;
 return new;
end $$;
create trigger protect_family_identity before insert or update on public.profiles for each row execute function kestrel_family.protect_identity();

create function kestrel_family.require_owner(p_member_id uuid) returns void language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or not exists(select 1 from public.profiles p where p.id=auth.uid() and p.managed_by is null and p.player_type_status='approved') then
  raise exception 'An active signed-in account is required';
 end if;
 if not exists(select 1 from public.profiles p where p.id=p_member_id and p.managed_by=auth.uid()) then
  raise exception 'This family member does not belong to your account';
 end if;
end $$;

create function kestrel_family.save_member(p_member_id uuid,p_name text,p_relationship text,p_age integer,p_consent boolean) returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid; v_name text:=regexp_replace(btrim(coalesce(p_name,'')),'[[:space:]]+',' ','g');
begin
 if auth.uid() is null or not exists(select 1 from public.profiles where id=auth.uid() and managed_by is null and player_type_status='approved') then raise exception 'An active signed-in account is required'; end if;
 if p_consent is distinct from true then raise exception 'Confirm that you are the guardian or have permission to manage this family member'; end if;
 if p_relationship is null or p_relationship not in ('child','spouse','other') or p_age is null or p_age not between 1 and 120 then raise exception 'Choose a relationship and enter a valid age'; end if;
 if public.classify_player_name(v_name)='invalid' then raise exception 'Enter the family member''s real name using letters, spaces, apostrophes or hyphens'; end if;
 perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text,1726));
 if exists(select 1 from public.profiles where managed_by=auth.uid() and lower(full_name)=lower(v_name) and (p_member_id is null or id<>p_member_id)) then raise exception 'A family member with this name is already listed'; end if;
 if p_member_id is null then
  v_id:=gen_random_uuid();
  insert into public.profiles(id,full_name,managed_by,requested_player_type,player_type_status,preferred_name_completed)
  values(v_id,v_name,auth.uid(),'permanent','approved',true);
  -- Run the normal name classifier after the initial real-name confirmation gate.
  update public.profiles set full_name=v_name where id=v_id;
  insert into kestrel_family.members(player_id,relationship,age_years) values(v_id,p_relationship,p_age);
 else
  perform kestrel_family.require_owner(p_member_id);v_id:=p_member_id;
  if exists(select 1 from kestrel_family.members where player_id=v_id and age_years<>p_age) and exists(select 1 from public.recurring_permanent_requests where user_id=v_id and status='approved') then raise exception 'Contact Admin to correct the age after a Season session has been approved'; end if;
  update public.profiles set full_name=v_name,preferred_name_completed=true where id=v_id;
  update kestrel_family.members set relationship=p_relationship,age_years=p_age,consent_at=now() where player_id=v_id;
 end if;
 return v_id;
end $$;

create function kestrel_family.overview() returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;
begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 select coalesce(jsonb_agg(jsonb_build_object(
  'id',p.id,'full_name',p.full_name,'relationship',m.relationship,'age_years',m.age_years,
  'name_status',p.name_review_status,'account_status',p.player_type_status,
  'choices',coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'schedule_id',r.recurring_schedule_id,'court',r.court,'level',r.player_level,'status',r.status,'weekday',rs.weekday,'label',rs.schedule_label,'sport',sp.name,'location',l.name,'city',l.city) order by r.created_at)
   from public.recurring_permanent_requests r join public.recurring_schedules rs on rs.id=r.recurring_schedule_id left join public.sports sp on sp.id=rs.sport_id left join public.locations l on l.id=rs.location_id where r.user_id=p.id),'[]'::jsonb),
  'sessions',coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'date',s.session_date,'start_time',s.start_time,'end_time',s.end_time,'court',coalesce(rc.court,s.court),'sport',sp.name,'location',l.name,'city',l.city,'status',r.status,'payment_status',r.payment_status,'not_coming',coalesce(a.not_coming,false)) order by s.session_date,s.start_time)
   from public.permanent_assignments pa join public.sessions s on s.id=pa.session_id left join public.sports sp on sp.id=s.sport_id left join public.locations l on l.id=s.location_id
   left join public.registrations r on r.session_id=s.id and r.user_id=p.id left join public.absences a on a.session_id=s.id and a.user_id=p.id
   left join public.permanent_roster_courts rc on rc.session_id=s.id and rc.user_id=p.id
   where pa.user_id=p.id and s.status='open' and s.availability_status='available' and ((s.session_date+s.start_time) at time zone 'America/Toronto')>now()),'[]'::jsonb)
 ) order by p.created_at),'[]'::jsonb) into result from public.profiles p join kestrel_family.members m on m.player_id=p.id where p.managed_by=auth.uid();
 return result;
end $$;

create function kestrel_family.save_choices(p_member_id uuid,p_choices jsonb) returns void language plpgsql security definer set search_path='' as $$
declare item jsonb; schedule public.recurring_schedules%rowtype; v_court text; v_level text; v_sport text;
begin
 perform kestrel_family.require_owner(p_member_id);
 if not exists(select 1 from public.profiles where id=p_member_id and player_type_status='approved') then raise exception 'This family profile is inactive; contact Admin'; end if;
 if p_choices is null or jsonb_typeof(p_choices)<>'array' or jsonb_array_length(p_choices)<1 or jsonb_array_length(p_choices)>30 then raise exception 'Choose at least one Season session (maximum 30)'; end if;
 for item in select value from jsonb_array_elements(p_choices) loop
  select * into schedule from public.recurring_schedules where id=(item->>'recurring_schedule_id')::bigint and active;
  if not found then raise exception 'This schedule is no longer active'; end if;
  if (item->>'season_paid')::boolean is distinct from true then raise exception 'Confirm Season payment has been made for this family member'; end if;
  v_level:=item->>'player_level';
  if v_level is null or v_level not in ('low_intermediate','intermediate','advanced') then raise exception 'Choose a player level for each session'; end if;
  select name into v_sport from public.sports where id=schedule.sport_id;
  v_court:=case when v_sport='badminton' then coalesce(nullif(item->>'court',''),'Court 1') else 'General' end;
  if v_sport='badminton' and v_court not in ('Court 1','Court 2','Court 3','Court 4','Court 5','Court 6') then raise exception 'Choose a valid court'; end if;
  if schedule.source_key='london-badminton-wednesday-7-9' and v_court not in ('Court 2','Court 3') then raise exception 'London badminton Court 1 is reserved. Choose Court 2 or Court 3'; end if;
  if exists(select 1 from public.recurring_permanent_requests where user_id=p_member_id and recurring_schedule_id=schedule.id and status='approved') then raise exception 'This family member is already approved for that session. Contact Admin for changes'; end if;
  insert into public.recurring_permanent_requests(user_id,recurring_schedule_id,court,status,player_level,reviewed_at,reviewed_by)
  values(p_member_id,schedule.id,v_court,'pending',v_level,null,null)
  on conflict(user_id,recurring_schedule_id) do update set court=excluded.court,status='pending',player_level=excluded.player_level,reviewed_at=null,reviewed_by=null,family_eligibility_confirmed=false;
 end loop;
end $$;

-- Every family request must be reviewed in the family approval screen, including eligibility.
alter table public.recurring_permanent_requests add column family_eligibility_confirmed boolean not null default false;
create function kestrel_family.guard_approval() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if exists(select 1 from kestrel_family.members where player_id=new.user_id) and new.status='approved' then
  if new.family_eligibility_confirmed is distinct from true then raise exception 'Review this request under Family Season approvals and confirm age eligibility'; end if;
  if not exists(select 1 from public.profiles where id=new.user_id and name_review_status='approved') then raise exception 'Approve or correct this family member''s real name first'; end if;
 end if;
 return new;
end $$;
create trigger family_season_eligibility before insert or update on public.recurring_permanent_requests for each row execute function kestrel_family.guard_approval();

create function kestrel_family.pending_reviews() returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;
begin
 if auth.uid() is null or not public.is_admin() then raise exception 'Admin access required'; end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',r.id,'member_name',p.full_name,'name_status',p.name_review_status,'age_years',m.age_years,'relationship',m.relationship,'owner_name',owner.full_name,'owner_email',owner.email,'court',r.court,'level',r.player_level,'sport',sp.name,'location',l.name,'city',l.city,'weekday',rs.weekday,'label',rs.schedule_label) order by r.created_at),'[]'::jsonb) into result
 from public.recurring_permanent_requests r join public.profiles p on p.id=r.user_id join kestrel_family.members m on m.player_id=p.id join public.profiles owner on owner.id=p.managed_by
 join public.recurring_schedules rs on rs.id=r.recurring_schedule_id left join public.sports sp on sp.id=rs.sport_id left join public.locations l on l.id=rs.location_id where r.status='pending';
 return result;
end $$;

create function kestrel_family.review(p_request_id bigint,p_approve boolean,p_eligible boolean) returns void language plpgsql security definer set search_path='' as $$
declare request public.recurring_permanent_requests%rowtype; template public.sessions%rowtype; target public.sessions%rowtype; v_sport text; v_ids bigint[]; occupied integer; lim integer; added integer:=0;
begin
 if auth.uid() is null or not public.is_admin() then raise exception 'Admin access required'; end if;
 select r.* into request from public.recurring_permanent_requests r join kestrel_family.members m on m.player_id=r.user_id where r.id=p_request_id and r.status='pending' for update of r;
 if not found then raise exception 'Family request is no longer pending'; end if;
 if p_approve is null then raise exception 'Choose approve or reject'; end if;
 if p_approve then
  if p_eligible is distinct from true then raise exception 'Confirm this member meets the activity age and participation requirements'; end if;
  if not exists(select 1 from public.profiles p join public.profiles owner on owner.id=p.managed_by where p.id=request.user_id and p.player_type_status='approved' and owner.player_type_status='approved') then raise exception 'Family member or account holder is inactive'; end if;
  update public.recurring_permanent_requests set family_eligibility_confirmed=true where id=request.id;
 end if;
 if not p_approve then
  update public.recurring_permanent_requests set status='rejected',reviewed_at=now(),reviewed_by=auth.uid() where id=request.id;
  return;
 end if;
 if not exists(select 1 from public.recurring_schedules where id=request.recurring_schedule_id and active) then raise exception 'This schedule is no longer active'; end if;
 select sp.name into v_sport from public.recurring_schedules rs join public.sports sp on sp.id=rs.sport_id where rs.id=request.recurring_schedule_id;
 -- Use published available dates; do not invent weekly dates outside school permits.
 for template in select distinct on (s.session_date) s.* from public.sessions s
  where s.recurring_schedule_id=request.recurring_schedule_id and s.status='open' and s.availability_status='available'
   and ((s.session_date+s.start_time) at time zone 'America/Toronto')>now()
  order by s.session_date,s.id loop
  select * into target from public.sessions s where s.recurring_schedule_id=request.recurring_schedule_id and s.session_date=template.session_date
   and (v_sport<>'badminton' or s.court=request.court) and s.status='open' and s.availability_status='available' order by s.id limit 1 for update;
  if not found then
   if v_sport<>'badminton' then continue; end if;
   if exists(select 1 from public.sessions s where s.recurring_schedule_id=request.recurring_schedule_id and s.session_date=template.session_date and s.court=request.court) then continue; end if;
   insert into public.sessions(sport_id,location_id,session_date,start_time,end_time,capacity,price,status,court,recurring_schedule_id,availability_status)
   values(template.sport_id,template.location_id,template.session_date,template.start_time,template.end_time,template.capacity,template.price,'open',request.court,template.recurring_schedule_id,'available') returning * into target;
  end if;
  if exists(select 1 from public.exclusive_court_bookings where session_id=target.id and cancelled_at is null) then raise exception 'This court has a private booking on %. Choose another court',target.session_date; end if;
  if v_sport='volleyball' then
   select activity_ids into v_ids from public.get_volleyball_activity_capacity(target.id);
   perform pg_advisory_xact_lock(71107,v_ids[1]::integer);
   select c.occupied,c.total_capacity into occupied,lim from public.get_volleyball_activity_capacity(target.id) c;
  else
   select count(*) into occupied from (
    select user_id from public.registrations where session_id=target.id and status='confirmed'
    union select pa.user_id from public.permanent_assignments pa where pa.session_id=target.id
    and not exists(select 1 from public.absences a where a.session_id=target.id and a.user_id=pa.user_id and a.not_coming)
    and not exists(select 1 from public.registrations r where r.session_id=target.id and r.user_id=pa.user_id and r.status in ('cancelled','removed','not_going'))
   ) people; lim:=target.capacity;
  end if;
  if occupied>=lim then raise exception 'No Season spot available on % for this court/activity. Resolve capacity before approving',target.session_date; end if;
  insert into public.permanent_assignments(user_id,session_id) values(request.user_id,target.id) on conflict do nothing;
  insert into public.registrations(user_id,session_id,status,payment_status,registration_type,player_level)
  values(request.user_id,target.id,'confirmed','paid','season',request.player_level)
  on conflict(user_id,session_id) do update set status='confirmed',registration_type='season',player_level=excluded.player_level;
  added:=added+1;
 end loop;
 if added=0 then raise exception 'No published available sessions exist for this schedule yet'; end if;
 update public.recurring_permanent_requests set status='approved',reviewed_at=now(),reviewed_by=auth.uid() where id=request.id;
 update public.profiles set player_type='permanent',requested_player_type='permanent',player_type_status='approved' where id=request.user_id;
end $$;

create function kestrel_family.attendance(p_member_id uuid,p_session_id bigint,p_not_coming boolean) returns text language plpgsql security definer set search_path='' as $$
declare s public.sessions%rowtype; ids bigint[]; occupied integer; lim integer;
begin
 perform kestrel_family.require_owner(p_member_id);
 if p_not_coming is null then raise exception 'Choose an attendance status'; end if;
 if not exists(select 1 from public.profiles where id=p_member_id and player_type='permanent' and player_type_status='approved') then raise exception 'Family member must be an approved Season player'; end if;
 select * into s from public.sessions where id=p_session_id for update;
 if not found or not exists(select 1 from public.permanent_assignments where session_id=p_session_id and user_id=p_member_id) then raise exception 'This family member is not assigned to that session'; end if;
 if ((s.session_date+s.start_time) at time zone 'America/Toronto')<=now() or s.status<>'open' or s.availability_status<>'available' then raise exception 'This session has started or is unavailable'; end if;
 if exists(select 1 from public.sports where id=s.sport_id and name='volleyball') then
  select activity_ids into ids from public.get_volleyball_activity_capacity(p_session_id);
  perform pg_advisory_xact_lock(71107,ids[1]::integer);
 end if;
 if p_not_coming then
  insert into public.absences(user_id,session_id,not_coming) values(p_member_id,p_session_id,true) on conflict(user_id,session_id) do update set not_coming=true;
  update public.registrations set status='cancelled' where user_id=p_member_id and session_id=p_session_id and status in ('confirmed','pending');
  return 'not_attending';
 end if;
 if not coalesce((select not_coming from public.absences where user_id=p_member_id and session_id=p_session_id),false) and coalesce((select status from public.registrations where user_id=p_member_id and session_id=p_session_id),'confirmed')='confirmed' then return 'confirmed'; end if;
 if ids is not null then
  select c.occupied,c.total_capacity into occupied,lim from public.get_volleyball_activity_capacity(p_session_id) c;
 else
  select count(*) into occupied from (
   select r.user_id from public.registrations r where r.session_id=p_session_id and r.status='confirmed'
   union
   select pa.user_id from public.permanent_assignments pa where pa.session_id=p_session_id and not exists(select 1 from public.absences a where a.session_id=p_session_id and a.user_id=pa.user_id and a.not_coming)
   and not exists(select 1 from public.registrations r where r.session_id=p_session_id and r.user_id=pa.user_id and r.status in ('cancelled','removed','not_going'))
  ) people;lim:=greatest(coalesce(s.capacity,0),0);
 end if;
 if occupied>=lim then return 'full'; end if;
 insert into public.absences(user_id,session_id,not_coming) values(p_member_id,p_session_id,false) on conflict(user_id,session_id) do update set not_coming=false;
 insert into public.registrations(user_id,session_id,status,payment_status,registration_type) values(p_member_id,p_session_id,'confirmed','paid','season')
 on conflict(user_id,session_id) do update set status='confirmed',payment_status='paid',registration_type='season';
 return 'confirmed';
end $$;

create function kestrel_family.withdraw_choice(p_member_id uuid,p_request_id bigint) returns void language plpgsql security definer set search_path='' as $$
begin
 perform kestrel_family.require_owner(p_member_id);
 update public.recurring_permanent_requests set status='rejected' where id=p_request_id and user_id=p_member_id and status='pending';
 if not found then raise exception 'Only a pending choice can be withdrawn. Contact Admin to change an approved session'; end if;
end $$;

-- Thin invoker wrappers keep privileged implementation outside the exposed schema.
create function public.save_my_family_member(p_member_id uuid,p_name text,p_relationship text,p_age integer,p_consent boolean) returns uuid language sql security invoker set search_path='' as $$select kestrel_family.save_member(p_member_id,p_name,p_relationship,p_age,p_consent)$$;
create function public.get_my_family() returns jsonb language sql security invoker set search_path='' as $$select kestrel_family.overview()$$;
create function public.save_my_family_season_choices(p_member_id uuid,p_choices jsonb) returns void language sql security invoker set search_path='' as $$select kestrel_family.save_choices(p_member_id,p_choices)$$;
create function public.set_my_family_attendance(p_member_id uuid,p_session_id bigint,p_not_coming boolean) returns text language sql security invoker set search_path='' as $$select kestrel_family.attendance(p_member_id,p_session_id,p_not_coming)$$;
create function public.withdraw_my_family_choice(p_member_id uuid,p_request_id bigint) returns void language sql security invoker set search_path='' as $$select kestrel_family.withdraw_choice(p_member_id,p_request_id)$$;
create function public.get_pending_family_season_requests() returns jsonb language sql security invoker set search_path='' as $$select kestrel_family.pending_reviews()$$;
create function public.admin_review_family_season_request(p_request_id bigint,p_approve boolean,p_eligible boolean) returns void language sql security invoker set search_path='' as $$select kestrel_family.review(p_request_id,p_approve,p_eligible)$$;
revoke all on all functions in schema kestrel_family from public,anon;
grant execute on all functions in schema kestrel_family to authenticated;
revoke execute on function public.save_my_family_member(uuid,text,text,integer,boolean),public.get_my_family(),public.save_my_family_season_choices(uuid,jsonb),public.set_my_family_attendance(uuid,bigint,boolean),public.withdraw_my_family_choice(uuid,bigint),public.get_pending_family_season_requests(),public.admin_review_family_season_request(bigint,boolean,boolean) from public,anon;
grant execute on function public.save_my_family_member(uuid,text,text,integer,boolean),public.get_my_family(),public.save_my_family_season_choices(uuid,jsonb),public.set_my_family_attendance(uuid,bigint,boolean),public.withdraw_my_family_choice(uuid,bigint),public.get_pending_family_season_requests(),public.admin_review_family_season_request(bigint,boolean,boolean) to authenticated;
notify pgrst,'reload schema';
