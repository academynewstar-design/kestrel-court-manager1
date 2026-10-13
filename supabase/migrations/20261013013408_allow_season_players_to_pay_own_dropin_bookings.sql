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
    and player_type in ('dropin','permanent')
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
REVOKE ALL ON FUNCTION public.mark_my_dropin_paid(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.mark_my_dropin_paid(bigint) TO authenticated, service_role;
