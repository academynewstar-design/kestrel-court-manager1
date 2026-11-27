-- Remove an event from tournament lists while retaining its entry/payment history.
alter table public.tournament_events add column deleted_at timestamptz;
drop policy tournament_events_read on public.tournament_events;
create policy tournament_events_read on public.tournament_events for select to authenticated
 using (deleted_at is null or (select public.is_admin()));
create function public.admin_delete_tournament(p_event_id bigint)
returns void language plpgsql security invoker set search_path=public,pg_temp as $$
begin
 if auth.uid() is null or not coalesce(public.is_admin(),false) then raise exception 'Admin access required'; end if;
 update public.tournament_events set deleted_at=now(),status='closed' where id=p_event_id and deleted_at is null;
 if not found then raise exception 'Tournament not found or already deleted'; end if;
end $$;
revoke all on function public.admin_delete_tournament(bigint) from public;
grant execute on function public.admin_delete_tournament(bigint) to authenticated;
