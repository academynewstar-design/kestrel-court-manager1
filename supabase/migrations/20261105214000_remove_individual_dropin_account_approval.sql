-- Individual drop-in bookings do not require manual account approval.
-- Preserve account rejection and Auth bans; group requests retain their own review workflow.
create or replace function kestrel_access.can_book(p_user_id uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.profiles p
    join auth.users u on u.id = coalesce(p.login_identity_id, p.id)
    where p.id = p_user_id
      and p.player_type_status <> 'rejected'
      and (u.banned_until is null or u.banned_until <= now())
  );
$$;
revoke all on function kestrel_access.can_book(uuid) from public, anon, authenticated;
