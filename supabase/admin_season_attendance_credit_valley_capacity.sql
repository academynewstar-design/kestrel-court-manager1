CREATE OR REPLACE FUNCTION public.admin_manage_roster_attendance(p_registration_id bigint, p_action text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
 target public.registrations%ROWTYPE;
 v_season boolean;
 v_ids bigint[];
BEGIN
 IF auth.uid() IS NULL OR NOT EXISTS(SELECT 1 FROM public.profiles WHERE id=auth.uid() AND is_admin=true) THEN
  RAISE EXCEPTION 'Admin access required';
 END IF;
 IF p_action IS NULL OR p_action NOT IN ('remove','not_going') THEN RAISE EXCEPTION 'Invalid action'; END IF;
 SELECT * INTO target FROM public.registrations WHERE id=p_registration_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Registration not found'; END IF;
 v_season := target.registration_type='season' OR
  (target.registration_type IS NULL AND EXISTS(
   SELECT 1 FROM public.permanent_assignments WHERE user_id=target.user_id AND session_id=target.session_id));
 IF coalesce(v_season,false) THEN
  IF p_action='remove' THEN RAISE EXCEPTION 'Use Season management to remove a Season assignment'; END IF;
  v_ids := ARRAY[target.session_id];
  IF EXISTS(SELECT 1 FROM public.sessions s JOIN public.sports sp ON sp.id=s.sport_id
            WHERE s.id=target.session_id AND sp.name='volleyball') THEN
   SELECT activity_ids INTO v_ids FROM public.get_volleyball_activity_capacity(target.session_id);
   PERFORM pg_advisory_xact_lock(71107,v_ids[1]::integer);
  END IF;
  -- Keep dated and weekly assignments; record absence before releasing the spot.
  INSERT INTO public.absences(user_id,session_id,not_coming)
  SELECT target.user_id,id,true FROM unnest(v_ids) AS ids(id)
  WHERE id=target.session_id OR EXISTS(
   SELECT 1 FROM public.permanent_assignments pa WHERE pa.session_id=id AND pa.user_id=target.user_id)
  ON CONFLICT(user_id,session_id) DO UPDATE SET not_coming=true;
  UPDATE public.registrations SET status='cancelled'
  WHERE user_id=target.user_id AND session_id=ANY(v_ids) AND status IN ('confirmed','pending','waitlist');
 ELSE
  IF p_action='remove' THEN
   DELETE FROM public.registrations WHERE id=p_registration_id;
  ELSE
   UPDATE public.registrations SET status='cancelled' WHERE id=p_registration_id;
  END IF;
 END IF;
END
$function$;
REVOKE ALL ON FUNCTION public.admin_manage_roster_attendance(bigint,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_manage_roster_attendance(bigint,text) TO authenticated;

-- Credit Valley Friday volleyball uses one shared 18-player activity across court records.
UPDATE public.sessions s
SET capacity=18
FROM public.recurring_schedules rs
WHERE rs.id=s.recurring_schedule_id
 AND rs.source_key='credit-valley-volleyball-friday-8-10'
 AND s.session_date >= (now() AT TIME ZONE 'America/Toronto')::date;
-- Fill newly available places in FIFO order using the existing shared-capacity rules.
DO $capacity$
DECLARE v_session bigint; v_ids bigint[]; v_occupied integer; v_capacity integer; v_next bigint;
BEGIN
 FOR v_session IN
  SELECT min(s.id) FROM public.sessions s JOIN public.recurring_schedules rs ON rs.id=s.recurring_schedule_id
  WHERE rs.source_key='credit-valley-volleyball-friday-8-10'
   AND s.status='open' AND s.availability_status='available'
   AND ((s.session_date+s.start_time) AT TIME ZONE 'America/Toronto')>now()
  GROUP BY s.session_date,s.start_time,s.end_time
 LOOP
  SELECT activity_ids INTO v_ids FROM public.get_volleyball_activity_capacity(v_session);
  PERFORM pg_advisory_xact_lock(71107,v_ids[1]::integer);
  LOOP
   SELECT occupied,total_capacity INTO v_occupied,v_capacity FROM public.get_volleyball_activity_capacity(v_session);
   EXIT WHEN v_occupied>=v_capacity;
   SELECT r.id INTO v_next FROM public.registrations r JOIN public.profiles p ON p.id=r.user_id
   WHERE r.session_id=ANY(v_ids) AND r.status='waitlist' AND p.player_type_status='approved'
    AND NOT EXISTS(SELECT 1 FROM public.registrations other
      WHERE other.user_id=r.user_id AND other.session_id=ANY(v_ids) AND other.status='confirmed')
   ORDER BY r.registered_at,r.id LIMIT 1 FOR UPDATE OF r;
   EXIT WHEN v_next IS NULL;
   UPDATE public.registrations SET status='confirmed',payment_status='unpaid' WHERE id=v_next;
  END LOOP;
 END LOOP;
END $capacity$;