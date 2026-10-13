CREATE TABLE public.season_court_change_requests (
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
 recurring_schedule_id bigint NOT NULL REFERENCES public.recurring_schedules(id) ON DELETE CASCADE,
 current_court text NOT NULL,
 requested_court text NOT NULL CHECK(requested_court IN ('Court 1','Court 2','Court 3','Court 4','Court 5','Court 6')),
 status text NOT NULL DEFAULT 'pending' CHECK(status IN ('pending','approved','rejected','cancelled')),
 created_at timestamptz NOT NULL DEFAULT now(),
 updated_at timestamptz NOT NULL DEFAULT now(),
 reviewed_at timestamptz,
 reviewed_by uuid REFERENCES public.profiles(id),
 CHECK(current_court<>requested_court)
);
CREATE UNIQUE INDEX season_court_change_one_pending ON public.season_court_change_requests(user_id,recurring_schedule_id) WHERE status='pending';
CREATE INDEX season_court_change_user ON public.season_court_change_requests(user_id,created_at DESC);
ALTER TABLE public.season_court_change_requests ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.season_court_change_requests FROM anon,authenticated;
GRANT SELECT ON public.season_court_change_requests TO authenticated;
GRANT ALL ON public.season_court_change_requests TO service_role;
CREATE POLICY season_court_change_read ON public.season_court_change_requests FOR SELECT TO authenticated
USING(user_id=(SELECT auth.uid()) OR (SELECT public.is_admin()));

