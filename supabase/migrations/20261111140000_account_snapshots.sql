create table public.account_snapshots (
  owner_id uuid primary key references auth.users(id) on delete cascade,
  revision bigint not null check (revision > 0),
  payload jsonb not null check (
    octet_length(payload::text) <= 10000000
    and coalesce(payload->>'format' = 'shubchik-guest', false)
    and coalesce(payload->'version' = '1'::jsonb, false)
    and coalesce(jsonb_typeof(payload->'tasks') = 'array', false)
    and coalesce(jsonb_typeof(payload->'ledger') = 'array', false)
  ),
  updated_at timestamptz not null default now()
);

alter table public.account_snapshots enable row level security;
revoke all on public.account_snapshots from public, anon, authenticated;
grant select, insert, update, delete on public.account_snapshots to authenticated;

create policy snapshots_own_rows on public.account_snapshots
  for all to authenticated
  using (owner_id = (select auth.uid()))
  with check (owner_id = (select auth.uid()));

create function public.save_account_snapshot(expected_revision bigint, backup jsonb)
returns bigint
language plpgsql
security invoker
set search_path = ''
as $$
declare
  account_id uuid := auth.uid();
  saved_revision bigint;
begin
  if account_id is null then
    raise insufficient_privilege;
  end if;

  if expected_revision = 0 then
    insert into public.account_snapshots(owner_id, revision, payload)
    values (account_id, 1, backup)
    on conflict (owner_id) do nothing
    returning revision into saved_revision;
  elsif expected_revision > 0 then
    update public.account_snapshots
    set revision = revision + 1, payload = backup, updated_at = now()
    where owner_id = account_id and revision = expected_revision
    returning revision into saved_revision;
  end if;

  if saved_revision is null then
    select revision into saved_revision
    from public.account_snapshots
    where owner_id = account_id
      and revision = expected_revision + 1
      and payload = backup;
  end if;

  if saved_revision is null then
    raise exception using errcode = '40001', message = 'Account snapshot revision changed';
  end if;
  return saved_revision;
end;
$$;

revoke all on function public.save_account_snapshot(bigint, jsonb) from public, anon, authenticated;
grant execute on function public.save_account_snapshot(bigint, jsonb) to authenticated;
