-- Admin-only school/date availability override
-- Marks every session at a school on a selected date available or unavailable.
create or replace function public.admin_set_school_availability(
  p_location_name text,
  p_session_date date,
  p_availability text
)
returns integer
language plpgsql
security definer
set search_path=public
as $$
declare
  v_location_id bigint;
  v_count integer;
begin
  if not public.is_admin() then
    raise exception 'Only administrators can change school availability';
  end if;
  if p_availability not in ('available','unavailable') then
    raise exception 'Availability must be available or unavailable';
  end if;
  select id into v_location_id from public.locations where name=p_location_name limit 1;
  if v_location_id is null then raise exception 'School/location not found'; end if;
  update public.sessions
     set availability_status=p_availability
   where location_id=v_location_id
     and session_date=p_session_date;
  get diagnostics v_count = row_count;
  if v_count=0 then raise exception 'No sessions found for this school and date'; end if;
  return v_count;
end;
$$;
revoke execute on function public.admin_set_school_availability(text,date,text) from public, anon;
grant execute on function public.admin_set_school_availability(text,date,text) to authenticated;
