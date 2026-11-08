begin;

create table if not exists public.bhakti_programs (
  id bigint generated always as identity primary key,
  title text not null check (length(btrim(title)) between 1 and 120),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

alter table public.bhakti_programs enable row level security;
grant select, insert, update on public.bhakti_programs to authenticated;
grant usage, select on sequence public.bhakti_programs_id_seq to authenticated;

drop policy if exists bhakti_programs_read on public.bhakti_programs;
create policy bhakti_programs_read
  on public.bhakti_programs for select to authenticated
  using (private.bhakti_allowed());

drop policy if exists bhakti_programs_add on public.bhakti_programs;
create policy bhakti_programs_add
  on public.bhakti_programs for insert to authenticated
  with check (private.bhakti_allowed() and created_by = (select auth.uid()));

drop policy if exists bhakti_programs_update on public.bhakti_programs;
create policy bhakti_programs_update
  on public.bhakti_programs for update to authenticated
  using (private.bhakti_allowed())
  with check (private.bhakti_allowed());

insert into public.bhakti_programs (title)
select 'Kirtan Program'
where not exists (select 1 from public.bhakti_programs);

alter table public.bhakti_program_items
  add column if not exists program_id bigint references public.bhakti_programs(id) on delete cascade;

update public.bhakti_program_items
set program_id = (select id from public.bhakti_programs order by id limit 1)
where program_id is null;

alter table public.bhakti_program_items
  alter column program_id set not null;

create index if not exists bhakti_program_items_program_position_idx
  on public.bhakti_program_items (program_id, position, id);

commit;