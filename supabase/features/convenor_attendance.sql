-- Location-scoped convenors. Rosters and attendance are exposed only through checked RPCs.
create schema if not exists kestrel_attendance;
revoke all on schema kestrel_attendance from public,anon,authenticated;
create table kestrel_attendance.convenors (
 user_id uuid not null references public.profiles(id) on delete cascade,
 location_id bigint not null references public.locations(id) on delete cascade,
 assigned_at timestamptz not null default now(),
 primary key(user_id,location_id)
);
create table kestrel_attendance.sheets (
 session_id bigint primary key references public.sessions(id),
 revision integer not null default 0,
 marks jsonb not null default '{}'::jsonb,
 roster jsonb,
 updated_by uuid references public.profiles(id),
 updated_at timestamptz not null default now(),
 confirmed_at timestamptz,
 no_show_count integer,
 report_queued boolean not null default false
);
create table kestrel_attendance.history (
 id bigint generated always as identity primary key,
 session_id bigint not null references public.sessions(id),
 actor uuid not null references public.profiles(id),
 revision integer not null,
 marks jsonb not null,
 confirmed boolean not null,
 created_at timestamptz not null default now()
);
alter table kestrel_attendance.convenors enable row level security;
alter table kestrel_attendance.sheets enable row level security;
alter table kestrel_attendance.history enable row level security;
revoke all on all tables in schema kestrel_attendance from public,anon,authenticated;

create function kestrel_attendance.allowed(p_location_id bigint) returns boolean
language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and exists(
  select 1 from public.profiles p join auth.users u on u.id=p.id
  where p.id=auth.uid() and p.player_type_status<>'rejected'
  and (u.banned_until is null or u.banned_until<=now())
  and (p.is_admin or exists(select 1 from kestrel_attendance.convenors c where c.user_id=p.id and c.location_id=p_location_id))
 );
$$;

-- Canonical time-slot ID collapses Season and Drop-in session rows and all courts.
create function kestrel_attendance.anchor(p_session_id bigint) returns bigint
language sql stable set search_path='' as $$
 select min(s.id) from public.sessions a join public.sessions s on
 (s.location_id,s.sport_id,s.session_date,s.start_time,s.end_time)=
 (a.location_id,a.sport_id,a.session_date,a.start_time,a.end_time)
 where a.id=p_session_id and s.status='open' and s.availability_status='available';
$$;
create function kestrel_attendance.roster(p_session_id bigint) returns jsonb
language sql stable set search_path='' as $$
 with activity as (
  select s.* from public.sessions a join public.sessions s on
  (s.location_id,s.sport_id,s.session_date,s.start_time,s.end_time)=
  (a.location_id,a.sport_id,a.session_date,a.start_time,a.end_time)
  where a.id=p_session_id and s.status='open' and s.availability_status='available'
 ), candidates as (
  select a.user_id,s.id,coalesce(c.court,s.court,'General') court,'Season'::text kind,0 priority,
   exists(select 1 from public.registrations r where r.session_id=s.id and r.user_id=a.user_id and r.status='cancelled') cancelled
  from activity s join public.permanent_assignments a on a.session_id=s.id
  left join public.permanent_roster_courts c on c.session_id=s.id and c.user_id=a.user_id
  union all
  select r.user_id,s.id,coalesce(c.court,s.court,'General'),
   case when r.registration_type='season' then 'Season' else 'Drop-in' end,1,false
  from activity s join public.registrations r on r.session_id=s.id and r.status='confirmed'
  left join public.permanent_roster_courts c on c.session_id=s.id and c.user_id=r.user_id
 ), players as (
  select distinct on (c.user_id) c.user_id,coalesce(nullif(btrim(p.full_name),''),'Player') player_name,c.court,c.kind,
   (c.cancelled or exists(select 1 from public.absences a join activity s on s.id=a.session_id where a.user_id=c.user_id and a.not_coming)) not_going
  from candidates c join public.profiles p on p.id=c.user_id
  join auth.users u on u.id=p.id
  where p.player_type_status<>'rejected' and (u.banned_until is null or u.banned_until<=now())
  order by c.user_id,c.priority,c.id
 )
 select coalesce(jsonb_agg(to_jsonb(p) order by p.court,p.player_name,p.user_id),'[]'::jsonb) from players p;
$$;

create function public.get_my_convenor_locations() returns table(location_id bigint,location_name text,city text)
language sql stable security definer set search_path='' as $$
 select l.id,l.name,l.city from public.locations l where kestrel_attendance.allowed(l.id) order by l.city,l.name;
$$;
create function public.get_convenor_activities() returns jsonb
language sql stable security definer set search_path='' as $$
 with activities as (
  select min(s.id) session_id,s.location_id,s.sport_id,s.session_date,s.start_time,s.end_time
  from public.sessions s where kestrel_attendance.allowed(s.location_id)
  and s.status='open' and s.availability_status='available'
  and s.session_date between (now() at time zone 'America/Toronto')::date-7 and (now() at time zone 'America/Toronto')::date+7
  group by s.location_id,s.sport_id,s.session_date,s.start_time,s.end_time
 )
 select coalesce(jsonb_agg(jsonb_build_object('session_id',a.session_id,'location',l.name,'city',l.city,'sport',sp.name,
 'session_date',a.session_date,'start_time',a.start_time,'end_time',a.end_time,'confirmed_at',sh.confirmed_at)
 order by a.session_date,a.start_time,l.name,sp.name),'[]'::jsonb)
 from activities a join public.locations l on l.id=a.location_id join public.sports sp on sp.id=a.sport_id
 left join kestrel_attendance.sheets sh on sh.session_id=a.session_id;
$$;
create function public.get_convenor_attendance(p_session_id bigint) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare s public.sessions; sh kestrel_attendance.sheets; sid bigint; players jsonb; starts timestamptz; ends timestamptz;
begin
 select * into s from public.sessions where id=p_session_id;
 if not found or not kestrel_attendance.allowed(s.location_id) then raise exception 'Convenor access required for this location'; end if;
 if s.status<>'open' or s.availability_status<>'available' or s.session_date not between (now() at time zone 'America/Toronto')::date-7 and (now() at time zone 'America/Toronto')::date+7 then raise exception 'Session is unavailable for attendance';end if;
 sid:=kestrel_attendance.anchor(s.id);
 select * into sh from kestrel_attendance.sheets where session_id=sid;
 players:=coalesce(sh.roster,kestrel_attendance.roster(sid));
 starts:=(s.session_date+s.start_time) at time zone 'America/Toronto';
 ends:=(s.session_date+s.end_time+case when s.end_time<=s.start_time then interval '1 day' else interval '0 day' end) at time zone 'America/Toronto';
 return jsonb_build_object('session_id',sid,'players',players,'roster_token',md5(players::text),'marks',coalesce(sh.marks,'{}'::jsonb),
 'revision',coalesce(sh.revision,0),'confirmed_at',sh.confirmed_at,'no_show_count',sh.no_show_count,'report_queued',coalesce(sh.report_queued,false),
 'can_save',now()>=starts-interval '1 hour' and now()<=ends+interval '7 days' and sh.confirmed_at is null,
 'can_confirm',now()>=ends and now()<=ends+interval '7 days' and sh.confirmed_at is null);
end $$;

create function public.save_convenor_attendance(p_session_id bigint,p_marks jsonb,p_roster_token text,p_revision integer,p_confirm boolean default false) returns jsonb
language plpgsql security definer set search_path='' as $$
declare s public.sessions; sh kestrel_attendance.sheets; sid bigint; players jsonb; starts timestamptz; ends timestamptz;
 missing_count integer; report text; recipient uuid; convenor_name text;
begin
 select * into s from public.sessions where id=p_session_id;
 if not found or not kestrel_attendance.allowed(s.location_id) then raise exception 'Convenor access required for this location'; end if;
 if s.status<>'open' or s.availability_status<>'available' then raise exception 'Session is unavailable for attendance';end if;
 starts:=(s.session_date+s.start_time) at time zone 'America/Toronto';
 ends:=(s.session_date+s.end_time+case when s.end_time<=s.start_time then interval '1 day' else interval '0 day' end) at time zone 'America/Toronto';
 if now()<starts-interval '1 hour' or now()>ends+interval '7 days' then raise exception 'Attendance can be saved from one hour before play until seven days after';end if;
 if p_confirm is null then raise exception 'Choose save or confirm';end if;
 if p_confirm and now()<ends then raise exception 'Confirm attendance after the session ends';end if;
 sid:=kestrel_attendance.anchor(s.id);
 -- The canonical sheet lock serializes drafts and prevents duplicate report emails.
 insert into kestrel_attendance.sheets(session_id) values(sid) on conflict do nothing;
 select * into sh from kestrel_attendance.sheets where session_id=sid for update;
 if sh.confirmed_at is not null then return public.get_convenor_attendance(sid);end if;
 if p_revision is distinct from sh.revision then raise exception 'Attendance changed in another window. Reload before saving.';end if;
 players:=kestrel_attendance.roster(sid);
 if p_roster_token is distinct from md5(players::text) then raise exception 'Roster changed. Reload and review the players before saving.';end if;
 if p_marks is null or jsonb_typeof(p_marks)<>'object' then raise exception 'Invalid attendance marks';end if;
 if exists(select 1 from jsonb_each(p_marks) m where jsonb_typeof(m.value)<>'boolean' or not exists(select 1 from jsonb_array_elements(players) p where p->>'user_id'=m.key)) then raise exception 'Attendance contains an invalid player or mark';end if;
 if p_confirm and exists(select 1 from jsonb_array_elements(players) p where not (p_marks ? (p->>'user_id'))) then raise exception 'Review every player before confirming attendance';end if;
 select count(*)::integer,string_agg((p->>'player_name')||' — '||(p->>'court')||coalesce(' — '||pr.email,'')||' — User '||(p->>'user_id'),chr(10) order by p->>'court',p->>'player_name')
 into missing_count,report from jsonb_array_elements(players) p
 left join public.profiles pr on pr.id=(p->>'user_id')::uuid
 where p_marks->>(p->>'user_id')='false' and not (p->>'not_going')::boolean;
 if p_confirm and missing_count>0 then
  select id into strict recipient from public.profiles where is_admin and lower(email)='academynewstar@gmail.com';
  select full_name into convenor_name from public.profiles where id=auth.uid();
  insert into public.email_notifications(user_id,notification_type,recipient_email,subject,body)
  select recipient,'convenor_attendance:'||sid,'academynewstar@gmail.com',
   'Attendance report — '||l.name||' — '||s.session_date,
   'Confirmed by: '||convenor_name||chr(10)||'Location: '||l.name||', '||l.city||chr(10)||
   'Game: '||sp.name||' — '||s.session_date||' '||s.start_time||'–'||s.end_time||' (Toronto)'||chr(10)||chr(10)||
   'Absent without Not Going ('||missing_count||'):'||chr(10)||report||chr(10)||chr(10)||
   'Attendance was explicitly confirmed after the session ended. Players marked Not Going and cancelled Drop-in bookings are excluded. Please review before taking any account action.'
  from public.locations l join public.sports sp on sp.id=s.sport_id where l.id=s.location_id;
 end if;
 update kestrel_attendance.sheets set marks=p_marks,revision=revision+1,updated_by=auth.uid(),updated_at=now(),
  confirmed_at=case when p_confirm then now() end,roster=case when p_confirm then players end,
  no_show_count=case when p_confirm then missing_count end,report_queued=p_confirm and missing_count>0 where session_id=sid;
 insert into kestrel_attendance.history(session_id,actor,revision,marks,confirmed) values(sid,auth.uid(),sh.revision+1,p_marks,p_confirm);
 return public.get_convenor_attendance(sid);
end $$;
revoke all on all functions in schema kestrel_attendance from public,anon,authenticated;
revoke all on function public.get_my_convenor_locations(),public.get_convenor_activities(),public.get_convenor_attendance(bigint),public.save_convenor_attendance(bigint,jsonb,text,integer,boolean) from public,anon,authenticated;
grant execute on function public.get_my_convenor_locations(),public.get_convenor_activities(),public.get_convenor_attendance(bigint),public.save_convenor_attendance(bigint,jsonb,text,integer,boolean) to authenticated;
notify pgrst,'reload schema';
