-- Per-user daily AI usage counter, used by the ai-recommend function to cap how
-- many calls a user can make per day (protects the shared Venice API budget).
-- The edge function writes this with the service role; users may only read their
-- own row (so the app can show "N questions left today").
-- Run this in the Supabase SQL editor on an existing project.
-- (Already included in schema.sql for fresh setups.)

create table if not exists public.ai_usage (
  user_id    uuid not null references auth.users (id) on delete cascade,
  day        date not null default current_date,
  count      integer not null default 0,
  updated_at timestamptz not null default now(),
  primary key (user_id, day)
);

alter table public.ai_usage enable row level security;

-- Read-only for the owner. No insert/update policy: only the edge function
-- (service role, which bypasses RLS) ever writes here.
create policy "ai_usage_read_own" on public.ai_usage
  for select using (auth.uid() = user_id);
