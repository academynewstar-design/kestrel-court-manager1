CREATE TABLE public.mississauga_volleyball_same_team_members (
 user_id uuid PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE
);
ALTER TABLE public.mississauga_volleyball_same_team_members ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.mississauga_volleyball_same_team_members FROM anon,authenticated;
GRANT SELECT ON public.mississauga_volleyball_same_team_members TO authenticated;
GRANT ALL ON public.mississauga_volleyball_same_team_members TO service_role;
CREATE POLICY mississauga_same_team_admin_read ON public.mississauga_volleyball_same_team_members FOR SELECT TO authenticated USING((SELECT public.is_admin()));
DO $seed$
DECLARE matched integer;
BEGIN
 INSERT INTO public.mississauga_volleyball_same_team_members(user_id)
 SELECT id FROM public.profiles
 WHERE lower(trim(full_name)) IN ('ishu ramphul','shreyas ramphul','sanjeev ramphul','arjun','joshua maben','jacob kemp','anthony tedja','steven h');
 GET DIAGNOSTICS matched=ROW_COUNT;
 IF matched<>8 THEN RAISE EXCEPTION 'Expected exactly 8 verified group members, found %',matched; END IF;
END $seed$;