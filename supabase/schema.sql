-- Reef Tracker schema for Supabase (Postgres).
-- Run this in the Supabase SQL editor (Dashboard → SQL → New query).
-- It creates all tables and Row Level Security policies so each user can
-- only read/write their own data.

-- ----------------------------------------------------------------------------
-- Tanks
-- ----------------------------------------------------------------------------
create table if not exists public.tanks (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references auth.users (id) on delete cascade,
  name          text not null,
  volume_liters numeric not null check (volume_liters > 0),
  habitat       text not null default 'saltwater', -- freshwater | saltwater | pond
  tank_type     text,
  started_on    timestamptz,
  notes         text,
  created_at    timestamptz not null default now()
);
create index if not exists tanks_user_id_idx on public.tanks (user_id);

-- ----------------------------------------------------------------------------
-- Equipment
-- ----------------------------------------------------------------------------
create table if not exists public.equipment (
  id       uuid primary key default gen_random_uuid(),
  tank_id  uuid not null references public.tanks (id) on delete cascade,
  name     text not null,
  category text not null default 'other',
  brand    text,
  model    text,
  notes    text,
  created_at timestamptz not null default now()
);
create index if not exists equipment_tank_id_idx on public.equipment (tank_id);

-- ----------------------------------------------------------------------------
-- Livestock
-- ----------------------------------------------------------------------------
create table if not exists public.livestock (
  id       uuid primary key default gen_random_uuid(),
  tank_id  uuid not null references public.tanks (id) on delete cascade,
  name     text not null,
  kind     text not null default 'other',
  species  text,
  quantity integer not null default 1 check (quantity > 0),
  added_on timestamptz,
  notes    text,
  created_at timestamptz not null default now()
);
create index if not exists livestock_tank_id_idx on public.livestock (tank_id);

-- ----------------------------------------------------------------------------
-- Dosing schedule
-- ----------------------------------------------------------------------------
create table if not exists public.dosing (
  id               uuid primary key default gen_random_uuid(),
  tank_id          uuid not null references public.tanks (id) on delete cascade,
  product          text not null,
  amount           numeric not null,
  unit             text not null default 'mL',
  frequency        text not null default 'daily',
  target_parameter text,
  notes            text,
  created_at timestamptz not null default now()
);
create index if not exists dosing_tank_id_idx on public.dosing (tank_id);

-- ----------------------------------------------------------------------------
-- Feeding schedule
-- ----------------------------------------------------------------------------
create table if not exists public.feedings (
  id        uuid primary key default gen_random_uuid(),
  tank_id   uuid not null references public.tanks (id) on delete cascade,
  food      text not null,
  amount    text,
  frequency text not null default 'once_daily',
  notes     text,
  created_at timestamptz not null default now()
);
create index if not exists feedings_tank_id_idx on public.feedings (tank_id);

-- ----------------------------------------------------------------------------
-- Custom parameter types (per user). Built-in types live in the app.
-- ----------------------------------------------------------------------------
create table if not exists public.parameter_types (
  id        uuid primary key default gen_random_uuid(),
  user_id   uuid not null references auth.users (id) on delete cascade,
  key       text not null,
  label     text not null,
  unit      text default '',
  ideal_min numeric,
  ideal_max numeric,
  decimals  integer not null default 2,
  created_at timestamptz not null default now(),
  unique (user_id, key)
);
create index if not exists parameter_types_user_id_idx
  on public.parameter_types (user_id);

-- ----------------------------------------------------------------------------
-- Parameter readings (the time-series data we graph)
-- ----------------------------------------------------------------------------
create table if not exists public.parameter_readings (
  id            uuid primary key default gen_random_uuid(),
  tank_id       uuid not null references public.tanks (id) on delete cascade,
  parameter_key text not null,
  value         numeric not null,
  measured_at   timestamptz not null default now(),
  notes         text,
  created_at    timestamptz not null default now()
);
create index if not exists readings_tank_param_idx
  on public.parameter_readings (tank_id, parameter_key, measured_at desc);

-- ----------------------------------------------------------------------------
-- Health journal (1-10 rating + notes over time)
-- ----------------------------------------------------------------------------
create table if not exists public.health_logs (
  id          uuid primary key default gen_random_uuid(),
  tank_id     uuid not null references public.tanks (id) on delete cascade,
  rating      integer not null check (rating between 1 and 10),
  notes       text,
  observed_at timestamptz not null default now(),
  created_at  timestamptz not null default now()
);
create index if not exists health_logs_tank_idx
  on public.health_logs (tank_id, observed_at desc);

-- ----------------------------------------------------------------------------
-- Daily tank photos (up to 3 per tank per day, enforced in the app). The image
-- files live in the private `tank-photos` storage bucket; each row points to one.
-- ----------------------------------------------------------------------------
create table if not exists public.tank_photos (
  id           uuid primary key default gen_random_uuid(),
  tank_id      uuid not null references public.tanks (id) on delete cascade,
  storage_path text not null,
  taken_on     date not null default current_date,
  created_at   timestamptz not null default now()
);
create index if not exists tank_photos_tank_idx
  on public.tank_photos (tank_id, taken_on desc);

-- ----------------------------------------------------------------------------
-- Row Level Security
-- ----------------------------------------------------------------------------
alter table public.tanks              enable row level security;
alter table public.equipment          enable row level security;
alter table public.livestock          enable row level security;
alter table public.dosing             enable row level security;
alter table public.feedings           enable row level security;
alter table public.parameter_types    enable row level security;
alter table public.parameter_readings enable row level security;
alter table public.health_logs        enable row level security;
alter table public.tank_photos        enable row level security;

-- Tanks: owner-only.
create policy "tanks_owner" on public.tanks
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- Parameter types: owner-only.
create policy "parameter_types_owner" on public.parameter_types
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- Helper: a row in a child table is accessible when its tank belongs to the user.
create policy "equipment_via_tank" on public.equipment
  for all using (
    exists (select 1 from public.tanks t
            where t.id = equipment.tank_id and t.user_id = auth.uid())
  ) with check (
    exists (select 1 from public.tanks t
            where t.id = equipment.tank_id and t.user_id = auth.uid())
  );

create policy "livestock_via_tank" on public.livestock
  for all using (
    exists (select 1 from public.tanks t
            where t.id = livestock.tank_id and t.user_id = auth.uid())
  ) with check (
    exists (select 1 from public.tanks t
            where t.id = livestock.tank_id and t.user_id = auth.uid())
  );

create policy "dosing_via_tank" on public.dosing
  for all using (
    exists (select 1 from public.tanks t
            where t.id = dosing.tank_id and t.user_id = auth.uid())
  ) with check (
    exists (select 1 from public.tanks t
            where t.id = dosing.tank_id and t.user_id = auth.uid())
  );

create policy "feedings_via_tank" on public.feedings
  for all using (
    exists (select 1 from public.tanks t
            where t.id = feedings.tank_id and t.user_id = auth.uid())
  ) with check (
    exists (select 1 from public.tanks t
            where t.id = feedings.tank_id and t.user_id = auth.uid())
  );

create policy "readings_via_tank" on public.parameter_readings
  for all using (
    exists (select 1 from public.tanks t
            where t.id = parameter_readings.tank_id and t.user_id = auth.uid())
  ) with check (
    exists (select 1 from public.tanks t
            where t.id = parameter_readings.tank_id and t.user_id = auth.uid())
  );

create policy "health_logs_via_tank" on public.health_logs
  for all using (
    exists (select 1 from public.tanks t
            where t.id = health_logs.tank_id and t.user_id = auth.uid())
  ) with check (
    exists (select 1 from public.tanks t
            where t.id = health_logs.tank_id and t.user_id = auth.uid())
  );

create policy "tank_photos_via_tank" on public.tank_photos
  for all using (
    exists (select 1 from public.tanks t
            where t.id = tank_photos.tank_id and t.user_id = auth.uid())
  ) with check (
    exists (select 1 from public.tanks t
            where t.id = tank_photos.tank_id and t.user_id = auth.uid())
  );

-- ----------------------------------------------------------------------------
-- Storage bucket for tank photos (private; access keyed to the user's folder,
-- path layout {user_id}/{tank_id}/{uuid}.jpg).
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
