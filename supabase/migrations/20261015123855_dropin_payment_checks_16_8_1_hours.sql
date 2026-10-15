CREATE OR REPLACE FUNCTION public.remove_expired_unpaid_dropins()
RETURNS integer LANGUAGE plpgsql SET search_path TO 'public'
AS $function$
declare n integer;
begin
 update public.registrations r set status='cancelled',payment_status='removed'
 from public.sessions s
 where r.session_id=s.id
 and r.status='confirmed' and lower(coalesce(r.payment_status,''))='unpaid'
 and (r.registration_type='dropin' or (
  r.registration_type is null and not exists(
   select 1 from public.permanent_assignments pa where pa.session_id=r.session_id and pa.user_id=r.user_id)))
 and ((s.session_date+s.start_time) at time zone 'America/Toronto')>now()
 and (
  ((s.session_date+s.start_time) at time zone 'America/Toronto')<=now()+interval '1 hour'
  or exists (
   select 1 from (values (interval '16 hours'),(interval '8 hours')) as cutoff(before_start)
   where now()>=((s.session_date+s.start_time) at time zone 'America/Toronto')-cutoff.before_start
   and r.registered_at<=((s.session_date+s.start_time) at time zone 'America/Toronto')-cutoff.before_start
  )
 );
 get diagnostics n=row_count;
 return n;
end $function$;
REVOKE ALL ON FUNCTION public.remove_expired_unpaid_dropins() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.remove_expired_unpaid_dropins() TO service_role;

-- A newly promoted player gets until the next checkpoint to pay,
-- rather than being judged against the time they originally joined the waitlist.
CREATE OR REPLACE FUNCTION public.kestrel_start_promoted_dropin_payment_window()
RETURNS trigger LANGUAGE plpgsql SET search_path TO 'public'
AS $function$
begin
 if old.status='waitlist' and new.status='confirmed'
    and lower(coalesce(new.payment_status,''))='unpaid' then
  new.registered_at=now();
 end if;
 return new;
end $function$;
REVOKE ALL ON FUNCTION public.kestrel_start_promoted_dropin_payment_window() FROM PUBLIC,anon,authenticated;
DROP TRIGGER IF EXISTS kestrel_promoted_dropin_payment_window ON public.registrations;
CREATE TRIGGER kestrel_promoted_dropin_payment_window
 BEFORE UPDATE OF status ON public.registrations
 FOR EACH ROW EXECUTE FUNCTION public.kestrel_start_promoted_dropin_payment_window();
