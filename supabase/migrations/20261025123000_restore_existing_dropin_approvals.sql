-- Restore one-time Drop-in access only for previously approved Drop-in profiles
-- with an established booking history. Never override an explicit rejection,
-- and never restore access for currently banned identities.
insert into public.dropin_account_approvals(user_id,status,reviewed_at)
select p.id,'approved',now()
from public.profiles p
join auth.users u on u.id=coalesce(p.login_identity_id,p.id)
where p.player_type='dropin'
  and p.player_type_status='approved'
  and (u.banned_until is null or u.banned_until<=now())
  and exists (
    select 1 from public.registrations r
    where r.user_id=p.id
      and r.status in ('confirmed','cancelled','removed','waitlist')
  )
  and not exists (
    select 1 from public.dropin_account_approvals a where a.user_id=p.id
  )
on conflict(user_id) do nothing;
