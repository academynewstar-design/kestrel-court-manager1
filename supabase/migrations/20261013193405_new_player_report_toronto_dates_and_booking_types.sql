CREATE OR REPLACE FUNCTION public.admin_new_player_registration_report(p_start_date date,p_end_date date)
RETURNS TABLE(id uuid,full_name text,email text,player_type text,requested_player_type text,player_type_status text,created_at timestamptz,total_bookings bigint,active_bookings bigint,effective_type text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
begin
 if auth.uid() is null or not exists(select 1 from profiles p where p.id=auth.uid() and p.is_admin=true) then raise exception 'Admin access required'; end if;
 if p_start_date is null or p_end_date is null or p_start_date>p_end_date then raise exception 'Choose a valid start and end date'; end if;
 return query
 with selected as (
  select p.* from profiles p
  where p.created_at >= (p_start_date::timestamp at time zone 'America/Toronto')
  and p.created_at < ((p_end_date+1)::timestamp at time zone 'America/Toronto')
 ), counts as (
  select r.user_id,count(*) total,count(*) filter(where r.status in ('confirmed','pending','waitlist')) active,
   bool_or(r.registration_type='dropin') has_dropin,bool_or(r.registration_type='season') has_season
  from registrations r join selected p on p.id=r.user_id group by r.user_id
 )
 select p.id,p.full_name,p.email,p.player_type,p.requested_player_type,p.player_type_status,p.created_at,
 coalesce(c.total,0::bigint),coalesce(c.active,0::bigint),
 coalesce(nullif(p.player_type,''),nullif(p.requested_player_type,''),case when c.has_season then 'permanent' when c.has_dropin then 'dropin' else 'unselected' end)::text
 from selected p left join counts c on c.user_id=p.id order by p.created_at desc,p.id;
end $function$;
REVOKE ALL ON FUNCTION public.admin_new_player_registration_report(date,date) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.admin_new_player_registration_report(date,date) TO authenticated,service_role;