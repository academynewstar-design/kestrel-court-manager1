-- Private screenshot attachments for player/admin conversations.
alter table public.suggestion_messages add column if not exists attachment_path text;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values ('message-screenshots','message-screenshots',false,5242880,array['image/png','image/jpeg','image/webp'])
on conflict(id) do update set public=false,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;

create policy "conversation screenshot upload" on storage.objects for insert to authenticated
with check (bucket_id='message-screenshots'
 and (storage.foldername(name))[2]=(select auth.uid())::text
 and exists(select 1 from public.suggestions s where s.id::text=(storage.foldername(name))[1]
 and (s.user_id=(select auth.uid()) or (select public.is_admin()))));

create policy "conversation screenshot read" on storage.objects for select to authenticated
using (bucket_id='message-screenshots'
 and exists(select 1 from public.suggestions s where s.id::text=(storage.foldername(name))[1]
 and (s.user_id=(select auth.uid()) or (select public.is_admin()))));

create policy "conversation screenshot cleanup" on storage.objects for delete to authenticated
using (bucket_id='message-screenshots'
 and (storage.foldername(name))[2]=(select auth.uid())::text
 and exists(select 1 from public.suggestions s where s.id::text=(storage.foldername(name))[1]
 and (s.user_id=(select auth.uid()) or (select public.is_admin()))));

alter table public.suggestion_messages add constraint message_attachment_conversation_path
check (attachment_path is null or (attachment_path like suggestion_id::text||'/'||sender_id::text||'/%' and attachment_path !~ '\.\.'));
