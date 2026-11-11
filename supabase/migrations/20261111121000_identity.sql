create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text check (char_length(display_name) <= 100),
  created_at timestamptz not null default now()
);

create table public.devices (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  label text not null check (char_length(label) between 1 and 100),
  created_at timestamptz not null default now()
);

create index devices_owner_id_idx on public.devices (owner_id);

alter table public.profiles enable row level security;
alter table public.devices enable row level security;

revoke all on public.profiles, public.devices from public, anon, authenticated;
grant select, delete on public.profiles, public.devices to authenticated;
grant insert (id, display_name), update (display_name) on public.profiles to authenticated;
grant insert (id, owner_id, label), update (label) on public.devices to authenticated;

create policy profiles_own_rows on public.profiles
  for all to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

create policy devices_own_rows on public.devices
  for all to authenticated
  using (owner_id = (select auth.uid()))
  with check (owner_id = (select auth.uid()));
