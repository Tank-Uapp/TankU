-- Adds daily tank photos (up to 3 per tank per day, enforced in the app).
-- Photos themselves live in the private `tank-photos` storage bucket; this
-- table stores one row per uploaded object so we can list and delete them.
-- Run this in the Supabase SQL editor on an existing project.
-- (Already included in schema.sql for fresh setups.)

create table if not exists public.tank_photos (
  id           uuid primary key default gen_random_uuid(),
  tank_id      uuid not null references public.tanks (id) on delete cascade,
  storage_path text not null,
  taken_on     date not null default current_date,
  created_at   timestamptz not null default now()
);
create index if not exists tank_photos_tank_idx
  on public.tank_photos (tank_id, taken_on desc);

alter table public.tank_photos enable row level security;

create policy "tank_photos_via_tank" on public.tank_photos
  for all using (
    exists (select 1 from public.tanks t
            where t.id = tank_photos.tank_id and t.user_id = auth.uid())
  ) with check (
    exists (select 1 from public.tanks t
            where t.id = tank_photos.tank_id and t.user_id = auth.uid())
  );

-- ----------------------------------------------------------------------------
-- Storage bucket for the image files. Private: access only via the policies
-- below, which key each object to the uploading user's folder
-- (path layout: {user_id}/{tank_id}/{uuid}.jpg).
-- ----------------------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('tank-photos', 'tank-photos', false)
on conflict (id) do nothing;

create policy "tank_photos_read_own" on storage.objects
  for select using (
    bucket_id = 'tank-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "tank_photos_insert_own" on storage.objects
  for insert with check (
    bucket_id = 'tank-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "tank_photos_delete_own" on storage.objects
  for delete using (
    bucket_id = 'tank-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
