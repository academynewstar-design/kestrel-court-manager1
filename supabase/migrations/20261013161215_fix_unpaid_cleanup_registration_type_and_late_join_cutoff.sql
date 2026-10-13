CREATE OR REPLACE FUNCTION public.remove_expired_unpaid_dropins()
RETURNS integer LANGUAGE plpgsql SET search_path TO 'public'
AS $function$
declare n integer;
begin
 update public.registrations r set status='cancelled',payment_status='removed'
 from public.sessions s,public.sports sp
 where r.session_id=s.id and sp.id=s.sport_id
 and r.status='confirmed' and lower(coalesce(r.payment_status,''))='unpaid'
 and (r.registration_type='dropin' or (
  r.registration_type is null and not exists(
   select 1 from public.permanent_assignments pa where pa.session_id=r.session_id and pa.user_id=r.user_id)))
 and ((s.session_date+s.start_time) at time zone 'America/Toronto')>now()
 and (
  ((s.session_date+s.start_time) at time zone 'America/Toronto')<=now()+interval '1 hour'
  or (
   ((s.session_date+s.start_time) at time zone 'America/Toronto')<=now()+
    case when lower(sp.name)='soccer' then interval '24 hours' else interval '18 hours' end
   and r.registered_at<=((s.session_date+s.start_time) at time zone 'America/Toronto')-
    case when lower(sp.name)='soccer' then interval '24 hours' else interval '18 hours' end
  )
 );
 get diagnostics n=row_count;
 return n;
end $function$;
REVOKE ALL ON FUNCTION public.remove_expired_unpaid_dropins() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.remove_expired_unpaid_dropins() TO service_role;
