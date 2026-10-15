alter table public.profiles add column name_review_status text not null default 'approved' check(name_review_status in ('required','approved','pending','rejected'));
create or replace function public.classify_player_name(p_name text)
returns text language plpgsql immutable set search_path=public as $$
declare n text:=regexp_replace(btrim(coalesce(p_name,'')),'[[:space:]]+',' ','g');
begin
 if length(n)<2 or length(n)>80 or n !~ '[[:alpha:]]' or n ~ '[[:digit:]@/:]' or n ~ '[^[:alpha:][:space:]''.’·-]' then return 'invalid'; end if;
 if lower(n) in ('lake ontario','new player','test user','test player','john doe','jane doe','anonymous','unknown','no name','fake name') or n !~ '[[:alpha:]][[:alpha:]]' or n !~ '[[:space:]]' then return 'pending'; end if;
 return 'approved';
end $$;
revoke all on function public.classify_player_name(text) from public,anon;
grant execute on function public.classify_player_name(text) to authenticated,service_role;
create or replace function public.enforce_player_name()
returns trigger language plpgsql set search_path=public as $$
declare result text;
begin
 if TG_OP='INSERT' then new.name_review_status:='required'; return new; end if;
 if auth.uid() is not null and public.is_admin() then return new; end if;
 new.name_review_status:=old.name_review_status;
 if new.full_name is distinct from old.full_name or old.name_review_status='required' then
  new.full_name:=regexp_replace(btrim(coalesce(new.full_name,'')),'[[:space:]]+',' ','g');
  result:=public.classify_player_name(new.full_name);
  if result='invalid' then raise exception 'Please enter your real name using letters, spaces, apostrophes or hyphens (2–80 characters). Numbers, email addresses and symbols are not accepted.'; end if;
  new.name_review_status:=result;
 end if;
 return new;
end $$;
revoke all on function public.enforce_player_name() from public,anon,authenticated;
create trigger enforce_player_name before insert or update on public.profiles for each row execute function public.enforce_player_name();

create or replace function public.require_accepted_player_name()
returns trigger language plpgsql set search_path=public as $$
begin
 if auth.uid()=new.user_id and not public.is_admin() and new.status in ('pending','confirmed','waitlist') and not exists(select 1 from public.profiles where id=new.user_id and name_review_status='approved') then
  raise exception 'Please confirm your real name and wait for any required admin name approval before joining a session.';
 end if;
 return new;
end $$;
revoke all on function public.require_accepted_player_name() from public,anon,authenticated;
create trigger require_accepted_player_name before insert or update of status on public.registrations for each row execute function public.require_accepted_player_name();
create trigger require_accepted_player_name before insert or update of status on public.recurring_permanent_requests for each row execute function public.require_accepted_player_name();

create or replace function public.admin_review_player_name(p_user_id uuid,p_approve boolean)
returns void language plpgsql security definer set search_path=public as $$
begin
 if auth.uid() is null or not public.is_admin() then raise exception 'Admin access required'; end if;
 update public.profiles set name_review_status=case when p_approve then 'approved' else 'rejected' end where id=p_user_id and name_review_status='pending';
 if not found then raise exception 'This name is no longer pending. Refresh the list.'; end if;
end $$;
revoke all on function public.admin_review_player_name(uuid,boolean) from public,anon;
grant execute on function public.admin_review_player_name(uuid,boolean) to authenticated;
