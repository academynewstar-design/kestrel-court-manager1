CREATE OR REPLACE FUNCTION public.cancel_my_dropin(p_session_id bigint)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ declare v_uid uuid:=auth.uid(); v_status text; v_kind text; begin if v_uid is null then raise exception 'You must be signed in'; end if; if not exists(select 1 from public.profiles where id=v_uid and player_type_status='approved') then raise exception 'Your account is not approved'; end if; select status,registration_type into v_status,v_kind from public.registrations where user_id=v_uid and session_id=p_session_id for update; if v_status is null or v_status not in ('confirmed','waitlist','pending') then return 'not_registered'; end if; if exists(select 1 from public.profiles where id=v_uid and player_type='permanent') and coalesce(v_kind,'') not in ('dropin','drop-in') then raise exception 'Use Not Going in My Season Games for your permanent session'; end if; update public.registrations set status='cancelled' where user_id=v_uid and session_id=p_session_id; return 'cancelled'; end; $function$;

CREATE OR REPLACE FUNCTION public.mark_my_dropin_paid(p_session_id bigint)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
 v_uid uuid:=auth.uid();
 v_kind text;
begin
 if v_uid is null then raise exception 'You must be signed in'; end if;
 if not exists (
  select 1 from public.profiles
  where id=v_uid and player_type_status='approved'
 ) then raise exception 'Your account is not approved'; end if;

 select coalesce(r.registration_type,
  case when exists (
   select 1 from public.permanent_assignments a
   where a.user_id=v_uid and a.session_id=p_session_id
  ) then 'season' else 'dropin' end)
 into v_kind
 from public.registrations r
 where r.user_id=v_uid and r.session_id=p_session_id
 for update;

 if v_kind is null then raise exception 'No unpaid confirmed reservation found'; end if;
 if v_kind not in ('dropin','drop-in') then
  raise exception 'Payment for your Season games is managed separately';
 end if;

 update public.registrations set payment_status='paid'
 where user_id=v_uid and session_id=p_session_id
   and status='confirmed' and payment_status='unpaid';
 if not found then raise exception 'No unpaid confirmed reservation found'; end if;
end
$function$;