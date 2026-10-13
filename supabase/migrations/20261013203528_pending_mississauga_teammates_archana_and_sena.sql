CREATE TABLE public.mississauga_volleyball_pending_group_members(
 first_name text PRIMARY KEY CHECK(first_name=lower(first_name)),
 group_number integer NOT NULL CHECK(group_number IN (1,2))
);
ALTER TABLE public.mississauga_volleyball_pending_group_members ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.mississauga_volleyball_pending_group_members FROM anon,authenticated;
GRANT SELECT ON public.mississauga_volleyball_pending_group_members TO authenticated;
GRANT ALL ON public.mississauga_volleyball_pending_group_members TO service_role;
CREATE POLICY pending_same_team_admin_read ON public.mississauga_volleyball_pending_group_members FOR SELECT TO authenticated USING((SELECT public.is_admin()));
INSERT INTO public.mississauga_volleyball_pending_group_members(first_name,group_number) VALUES('archana',2),('sena',2);