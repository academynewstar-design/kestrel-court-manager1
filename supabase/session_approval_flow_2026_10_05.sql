-- Session-level approval flow applied to the live database on 2026-10-05.
-- Accounts are active immediately; Season and Drop-in choices require admin approval.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path=public
as $$
begin
  insert into public.profiles(id,full_name,email,requested_player_type,player_type_status)
  values(new.id,coalesce(new.raw_user_meta_data->>'full_name','New Player'),new.email,null,'approved');
  return new;
end;
$$;

drop policy if exists "recurring perm own insert" on public.recurring_permanent_requests;
create policy "recurring perm own insert" on public.recurring_permanent_requests
for insert to authenticated
with check ((select auth.uid())=user_id and exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.player_type_status='approved'));

-- register_dropin now accepts any active account and creates a pending registration.
-- save_my_permanent_choices now accepts any active account and creates pending recurring_permanent_requests.
-- Full live function definitions are maintained in the database and should be pulled into the next schema snapshot.
