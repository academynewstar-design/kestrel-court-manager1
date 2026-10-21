-- One-time manual approval for Drop-in booking access. Existing bookings are retained.
create table public.dropin_account_approvals (
 user_id uuid primary key references public.profiles(id) on delete cascade,
 status text not null default 'pending' check(status in ('pending','approved','rejected')),
 created_at timestamptz not null default now(),
 reviewed_at timestamptz,
 reviewed_by uuid references public.profiles(id)
);
alter table public.dropin_account_approvals enable row level security;
revoke all on public.dropin_account_approvals from anon,authenticated;
grant select,insert,update on public.dropin_account_approvals to authenticated;
create policy approval_read on public.dropin_account_approvals for select to authenticated
 using(user_id=(select auth.uid()) or public.is_admin());
create policy approval_request on public.dropin_account_approvals for insert to authenticated
 with check(user_id=(select auth.uid()) and status='pending' and reviewed_at is null and reviewed_by is null);
create policy approval_review on public.dropin_account_approvals for update to authenticated
 using(public.is_admin()) with check(public.is_admin());

-- Private helper needs Auth ban data, which is deliberately inaccessible to clients.
create schema if not exists kestrel_access;
revoke all on schema kestrel_access from public,anon,authenticated;
create function kestrel_access.can_book(p_user_id uuid) returns boolean
 language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.profiles p join auth.users u on u.id=coalesce(p.login_identity_id,p.id)
 where p.id=p_user_id and p.player_type_status<>'rejected'
 and (u.banned_until is null or u.banned_until<=now())
 and ((p.player_type='permanent' and p.player_type_status='approved')
 or exists(select 1 from public.dropin_account_approvals a where a.user_id=p.id and a.status='approved')))
$$;
revoke all on function kestrel_access.can_book(uuid) from public,anon,authenticated;

create function kestrel_access.guard_booking() returns trigger
 language plpgsql security definer set search_path='' as $$
begin
 -- Admin roster management and scheduled maintenance keep their existing behavior.
 if auth.uid() is null or public.is_admin() then return new; end if;
 if new.status not in ('pending','confirmed','waitlist') then return new; end if;
 if TG_OP='UPDATE' then
  if old.user_id=new.user_id and old.session_id=new.session_id and old.status in ('pending','confirmed','waitlist') then return new; end if;
 end if;
 -- Regular Season attendance is covered by its own approval.
 if exists(select 1 from public.permanent_assignments pa where pa.user_id=new.user_id and pa.session_id=new.session_id) then return new; end if;
 if not kestrel_access.can_book(new.user_id) then
  raise exception 'Drop-in account approval is required. Request approval in Drop-in Games and wait for Admin before joining a game or waitlist.';
 end if;
 return new;
end $$;
revoke all on function kestrel_access.guard_booking() from public,anon,authenticated;
create trigger require_dropin_account_approval before insert or update of status,session_id,user_id
 on public.registrations for each row execute function kestrel_access.guard_booking();

create function kestrel_access.guard_group() returns trigger
 language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or public.is_admin() then return new; end if;
 if new.status in ('pending','approved') and not kestrel_access.can_book(new.owner_id) then
  raise exception 'Drop-in account approval is required before requesting group spots.';
 end if;
 return new;
end $$;
revoke all on function kestrel_access.guard_group() from public,anon,authenticated;
create trigger require_dropin_account_approval before insert or update of status,owner_id,session_id
 on kestrel_groups.requests for each row execute function kestrel_access.guard_group();

create function kestrel_access.stamp_review() returns trigger
 language plpgsql set search_path='' as $$
begin
 new.reviewed_at:=now(); new.reviewed_by:=auth.uid(); return new;
end $$;
revoke all on function kestrel_access.stamp_review() from public,anon,authenticated;
create trigger stamp_review before update on public.dropin_account_approvals
 for each row execute function kestrel_access.stamp_review();
