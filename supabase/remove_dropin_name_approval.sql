create or replace function public.enforce_player_name()
returns trigger language plpgsql set search_path=public as $$
declare result text; season_player boolean;
begin
 season_player:=coalesce(new.player_type='permanent',false) or coalesce(new.requested_player_type='permanent',false);
 if not season_player then new.name_review_status:='approved'; return new; end if;
 if TG_OP='INSERT' then new.name_review_status:='required'; return new; end if;
 if auth.uid() is not null and public.is_admin() then return new; end if;
 new.name_review_status:=old.name_review_status;
 if new.full_name is distinct from old.full_name or old.name_review_status='required'
 or (coalesce(old.player_type,'')<>'permanent' and coalesce(old.requested_player_type,'')<>'permanent') then
  new.full_name:=regexp_replace(btrim(coalesce(new.full_name,'')),'[[:space:]]+',' ','g');
  result:=public.classify_player_name(new.full_name);
  if result='invalid' then raise exception 'Please enter your real name using letters, spaces, apostrophes or hyphens (2–80 characters). Numbers, email addresses and symbols are not accepted.'; end if;
  new.name_review_status:=result;
 end if;
 return new;
end $$;
revoke all on function public.enforce_player_name() from public,anon,authenticated;
create or replace function public.require_accepted_player_name()
returns trigger language plpgsql set search_path=public as $$
begin
 if auth.uid()=new.user_id and not public.is_admin() and new.status in ('pending','confirmed','waitlist')
 and exists(select 1 from public.profiles where id=new.user_id
 and (player_type='permanent' or requested_player_type='permanent') and name_review_status<>'approved') then
 raise exception 'Please confirm your real name and wait for any required admin name approval before joining a session.';
 end if;
 return new;
end $$;
revoke all on function public.require_accepted_player_name() from public,anon,authenticated;
update public.profiles set name_review_status='approved'
where coalesce(player_type,'')<>'permanent' and coalesce(requested_player_type,'')<>'permanent'
and name_review_status<>'approved';
