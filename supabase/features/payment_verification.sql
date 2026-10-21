-- Verification is independent of the player's Paid claim. Raw evidence stays private.
create schema if not exists kestrel_payments;
revoke all on schema kestrel_payments from public,anon,authenticated;
create table public.payment_reviews (
 registration_id bigint primary key references public.registrations(id) on delete cascade,
 user_id uuid not null references public.profiles(id),
 state text not null default 'pending' check(state in ('pending','verified','needs_review')),
 cycle_started_at timestamptz not null default now(),
 paid_marked_at timestamptz,
 checked_at timestamptz,
 verified_at timestamptz,
 verified_by uuid references public.profiles(id),
 verification_method text check(verification_method in ('deposit','admin')),
 reason text,
 admin_note text,
 conversation_id bigint references public.suggestions(id),
 alert_queued_at timestamptz
);
alter table public.payment_reviews enable row level security;
revoke all on public.payment_reviews from public,anon,authenticated;
grant select on public.payment_reviews to authenticated;
create policy payment_review_read on public.payment_reviews for select to authenticated
using(user_id=(select auth.uid()) or public.is_admin());
create table kestrel_payments.deposit_allocations (
 reference text primary key,
 registration_ids bigint[] not null,
 amount numeric not null check(amount>0),
 evidence jsonb not null,
 created_at timestamptz not null default now()
);
create table kestrel_payments.review_history (
 id bigint generated always as identity primary key,
 registration_id bigint not null, state text not null, actor uuid, note text, created_at timestamptz not null default now()
);
alter table kestrel_payments.deposit_allocations enable row level security;
alter table kestrel_payments.review_history enable row level security;
revoke all on all tables in schema kestrel_payments from public,anon,authenticated;

create function kestrel_payments.eligible(p_registration_id bigint) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.registrations r join public.sessions s on s.id=r.session_id
 join public.locations l on l.id=s.location_id join public.sports sp on sp.id=s.sport_id
 where r.id=p_registration_id and r.registration_type='dropin' and r.status='confirmed' and r.payment_status='paid'
 and s.status='open' and s.availability_status='available' and s.dropin_enabled
 and lower(btrim(s.payment_email))='academynewstar@gmail.com'
 and (s.session_date+s.start_time) at time zone 'America/Toronto'>now()
 and not(lower(l.city)='london' and lower(sp.name)='volleyball')
 and not exists(select 1 from public.permanent_assignments a where a.user_id=r.user_id and a.session_id=s.id)
 and not exists(select 1 from public.recurring_permanent_requests a where a.user_id=r.user_id and a.status='approved'
 and a.recurring_schedule_id=s.recurring_schedule_id and coalesce(a.court,'General')=coalesce(s.court,'General')));
$$;
create function kestrel_payments.track_paid() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if not kestrel_payments.eligible(new.id) then delete from public.payment_reviews where registration_id=new.id;return new;end if;
 if tg_op='INSERT' then
  insert into public.payment_reviews(registration_id,user_id,paid_marked_at) values(new.id,new.user_id,now()) on conflict do nothing;
 elsif old.payment_status is distinct from new.payment_status or old.session_id is distinct from new.session_id or old.status is distinct from new.status or old.registration_type is distinct from new.registration_type then
  insert into public.payment_reviews(registration_id,user_id,paid_marked_at) values(new.id,new.user_id,now())
  on conflict(registration_id) do update set user_id=excluded.user_id,state='pending',cycle_started_at=now(),paid_marked_at=now(),checked_at=null,verified_at=null,verified_by=null,verification_method=null,reason=null,admin_note=null,conversation_id=null,alert_queued_at=null;
 end if;return new;
end $$;
create trigger track_dropin_paid after insert or update of payment_status,session_id,status,registration_type on public.registrations for each row execute function kestrel_payments.track_paid();
-- Historic claims have no reliable Paid timestamp. Start their delay allowance now.
insert into public.payment_reviews(registration_id,user_id) select id,user_id from public.registrations where kestrel_payments.eligible(id) on conflict do nothing;

create function kestrel_payments.audit_review() returns trigger language plpgsql security definer set search_path='' as $$
declare v_label text;v_admin uuid;
begin
 if tg_op='INSERT' or old.state is distinct from new.state or old.admin_note is distinct from new.admin_note then
  insert into kestrel_payments.review_history(registration_id,state,actor,note) values(new.registration_id,new.state,auth.uid(),coalesce(new.admin_note,new.reason));
 end if;
 if new.state='needs_review' and new.alert_queued_at is null then
  select p.full_name||' — '||s.session_date||' '||s.start_time||' — '||l.name||' — '||coalesce(s.court,'General')||' — $'||s.price||' CAD'
  into v_label from public.registrations r join public.profiles p on p.id=r.user_id join public.sessions s on s.id=r.session_id join public.locations l on l.id=s.location_id where r.id=new.registration_id;
  select id into strict v_admin from public.profiles where is_admin and lower(email)='academynewstar@gmail.com';
  insert into public.email_notifications(user_id,notification_type,recipient_email,subject,body)
  values(v_admin,'payment_review:'||new.registration_id||':'||extract(epoch from new.cycle_started_at),'academynewstar@gmail.com','Payment needs review — Kestrel Sports',
  v_label||chr(10)||chr(10)||coalesce(new.reason,'Deposit not matched yet.')||chr(10)||'Missing evidence is not proof of nonpayment. Open Admin → Payment Review at https://kestrelsports.ca to investigate and verify manually if appropriate.');
  new.alert_queued_at:=now();
 end if;return new;
end $$;
create trigger payment_review_audit before insert or update on public.payment_reviews for each row execute function kestrel_payments.audit_review();

-- Internal checker entry point. Execute only with a trusted server role or SQL tooling.
create function kestrel_payments.record_result(p_ids bigint[],p_state text,p_reason text,p_reference text default null,p_amount numeric default null,p_evidence jsonb default null)
returns void language plpgsql security definer set search_path='' as $$
declare v_ids bigint[];v_old bigint[];v_old_amount numeric;v_expected numeric;v_group bigint;v_members bigint[];v_id bigint;
begin
 select array_agg(distinct x order by x) into v_ids from unnest(p_ids) x;
 if cardinality(v_ids) is null or p_state not in ('verified','needs_review') then raise exception 'Invalid result';end if;
 perform 1 from public.payment_reviews where registration_id=any(v_ids) order by registration_id for update;
 if (select count(*) from public.payment_reviews where registration_id=any(v_ids))<>cardinality(v_ids) then raise exception 'Review missing';end if;
 foreach v_id in array v_ids loop if not kestrel_payments.eligible(v_id) then raise exception 'Registration no longer eligible';end if;end loop;
 if p_state='verified' then
  if exists(select 1 from public.payment_reviews where registration_id=any(v_ids) and verification_method='admin') then
   if cardinality(v_ids)=1 then return;else raise exception 'Group contains an Admin decision; Admin review required';end if;
  end if;
  if exists(select 1 from public.payment_reviews where registration_id=any(v_ids) and state='verified' and verification_method='deposit') and not exists(select 1 from kestrel_payments.deposit_allocations where reference=btrim(p_reference) and registration_ids=v_ids) then raise exception 'Booking already has a verified deposit';end if;
  if nullif(btrim(p_reference),'') is null or p_amount is null or p_amount<=0 or p_evidence is null or coalesce(p_evidence->>'currency','')<>'CAD' or coalesce(p_evidence->>'authentication','')<>'dkim_and_dmarc_pass' or coalesce(p_evidence->>'deposit_confirmed','')<>'true' or nullif(p_evidence->>'gmail_message_id','') is null then raise exception 'Authenticated deposited CAD evidence required';end if;
  if cardinality(v_ids)>1 then
   select g.id into v_group from kestrel_groups.requests g where g.status='approved' and exists(select 1 from public.registrations r where r.id=v_ids[1] and r.session_id=g.session_id and r.user_id=g.owner_id);
   if v_group is null then raise exception 'Explicit approved group required for shared transfer';end if;
   select array_agg(r.id order by r.id) into v_members from kestrel_groups.members m join kestrel_groups.requests g on g.id=m.request_id join public.registrations r on r.user_id=m.player_id and r.session_id=g.session_id where g.id=v_group and r.status='confirmed';
   if v_members<>v_ids then raise exception 'Group allocation must cover exactly all approved members';end if;
   select (cardinality(g.guest_names)+1)*g.unit_price-g.credit_paid into v_expected from kestrel_groups.requests g where g.id=v_group;
   if coalesce(p_evidence->>'explicit_group_allocation','')<>'true' then raise exception 'Explicit group allocation evidence required';end if;
  else
   if exists(select 1 from kestrel_groups.members m join kestrel_groups.requests g on g.id=m.request_id join public.registrations r on r.session_id=g.session_id and r.user_id=m.player_id where r.id=v_ids[1] and g.status='approved') then raise exception 'Verify approved group together';end if;
   select s.price into v_expected from public.registrations r join public.sessions s on s.id=r.session_id where r.id=v_ids[1];
  end if;
  if p_amount<>v_expected then raise exception 'Amount does not reconcile with booking total';end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(btrim(p_reference),0));
  select registration_ids,amount into v_old,v_old_amount from kestrel_payments.deposit_allocations where reference=btrim(p_reference);
  if v_old is not null and v_old_amount<>p_amount then raise exception 'Existing transfer amount differs';end if;
  if v_old is not null and v_old<>v_ids then raise exception 'Transfer already allocated to another booking';end if;
  insert into kestrel_payments.deposit_allocations(reference,registration_ids,amount,evidence) values(btrim(p_reference),v_ids,p_amount,p_evidence) on conflict do nothing;
 end if;
 update public.payment_reviews set state=p_state,reason=left(p_reason,1000),checked_at=now(),verified_at=case when p_state='verified' then now() else null end,verification_method=case when p_state='verified' then 'deposit' else null end
 where registration_id=any(v_ids) and verification_method is distinct from 'admin'
 and (p_state='verified' or (state<>'verified' and now()>=coalesce(paid_marked_at,cycle_started_at)+interval '60 minutes'));
end $$;

create function public.admin_verify_payment(p_registration_id bigint,p_note text) returns void language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or not public.is_admin() then raise exception 'Admin only';end if;
 if length(btrim(coalesce(p_note,'')))<5 then raise exception 'Add a verification note (at least 5 characters)';end if;
 if not kestrel_payments.eligible(p_registration_id) then raise exception 'Booking is no longer eligible';end if;
 update public.payment_reviews set state='verified',verification_method='admin',verified_by=auth.uid(),verified_at=now(),checked_at=now(),admin_note=left(btrim(p_note),1500),reason='Manually verified by Admin' where registration_id=p_registration_id;
 if not found then raise exception 'Review not found';end if;
end $$;
create function public.submit_payment_review_message(p_registration_id bigint,p_details text) returns bigint language plpgsql security definer set search_path='' as $$
declare v_review public.payment_reviews;v_id bigint;v_label text;
begin
 if auth.uid() is null then raise exception 'Sign in required';end if;
 select * into v_review from public.payment_reviews where registration_id=p_registration_id and user_id=auth.uid() for update;
 if not found or v_review.state<>'needs_review' then raise exception 'No flagged payment on your account';end if;
 if length(btrim(coalesce(p_details,'')))<15 or length(p_details)>1800 then raise exception 'Provide the sender name, email, amount, date and reference';end if;
 select s.session_date||' '||s.start_time||' — '||l.name||' — '||coalesce(s.court,'General') into v_label from public.registrations r join public.sessions s on s.id=r.session_id join public.locations l on l.id=s.location_id where r.id=p_registration_id;
 v_id:=v_review.conversation_id;
 if v_id is null then
  insert into public.suggestions(user_id,note,category,status) values(auth.uid(),'Payment review for booking '||p_registration_id||': '||v_label,'Payment Review','new') returning id into v_id;
  update public.payment_reviews set conversation_id=v_id where registration_id=p_registration_id;
 end if;
 insert into public.suggestion_messages(suggestion_id,sender_id,message) values(v_id,auth.uid(),'Payment review — booking '||p_registration_id||chr(10)||v_label||chr(10)||btrim(p_details));
 update public.suggestions set status='in_progress',updated_at=now() where id=v_id;
 return v_id;
end $$;
revoke all on all functions in schema kestrel_payments from public,anon,authenticated;
grant usage on schema kestrel_payments to service_role;
grant execute on function kestrel_payments.record_result(bigint[],text,text,text,numeric,jsonb) to service_role;
revoke all on function public.admin_verify_payment(bigint,text),public.submit_payment_review_message(bigint,text) from public,anon,authenticated;
grant execute on function public.admin_verify_payment(bigint,text),public.submit_payment_review_message(bigint,text) to authenticated;
