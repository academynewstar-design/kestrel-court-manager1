begin;

create table if not exists public.bhakti_ramayana_tunes (
  id bigint generated always as identity primary key,
  title text not null check (length(btrim(title)) between 1 and 160),
  storage_path text not null unique,
  uploaded_by uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

alter table public.bhakti_ramayana_tunes enable row level security;
grant select, insert, delete on public.bhakti_ramayana_tunes to authenticated;
grant usage, select on sequence public.bhakti_ramayana_tunes_id_seq to authenticated;

drop policy if exists bhakti_ramayana_tunes_read on public.bhakti_ramayana_tunes;
create policy bhakti_ramayana_tunes_read
  on public.bhakti_ramayana_tunes for select to authenticated
  using (private.bhakti_allowed());

drop policy if exists bhakti_ramayana_tunes_add on public.bhakti_ramayana_tunes;
create policy bhakti_ramayana_tunes_add
  on public.bhakti_ramayana_tunes for insert to authenticated
  with check (private.bhakti_allowed() and uploaded_by = (select auth.uid()));

drop policy if exists bhakti_ramayana_tunes_delete on public.bhakti_ramayana_tunes;
create policy bhakti_ramayana_tunes_delete
  on public.bhakti_ramayana_tunes for delete to authenticated
  using (private.bhakti_allowed() and (uploaded_by = (select auth.uid()) or private.bhakti_is_admin()));

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'bhakti-ramayana-tunes',
  'bhakti-ramayana-tunes',
  false,
  52428800,
  array['audio/mpeg','audio/mp4','audio/x-m4a','audio/aac','audio/wav','audio/x-wav','audio/ogg','audio/opus','audio/webm']
)
on conflict (id) do update
set public = false,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists bhakti_ramayana_tunes_storage_read on storage.objects;
create policy bhakti_ramayana_tunes_storage_read
  on storage.objects for select to authenticated
  using (bucket_id = 'bhakti-ramayana-tunes' and private.bhakti_allowed());

drop policy if exists bhakti_ramayana_tunes_storage_upload on storage.objects;
create policy bhakti_ramayana_tunes_storage_upload
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'bhakti-ramayana-tunes'
    and private.bhakti_allowed()
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

drop policy if exists bhakti_ramayana_tunes_storage_delete on storage.objects;
create policy bhakti_ramayana_tunes_storage_delete
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'bhakti-ramayana-tunes'
    and private.bhakti_allowed()
    and (
      (storage.foldername(name))[1] = (select auth.uid())::text
      or private.bhakti_is_admin()
    )
  );

commit;