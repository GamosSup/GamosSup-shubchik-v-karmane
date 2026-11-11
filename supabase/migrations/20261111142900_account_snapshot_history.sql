create table public.account_snapshot_history (
  owner_id uuid not null references auth.users(id) on delete cascade,
  backed_up_on date not null,
  revision bigint not null check (revision > 0),
  payload jsonb not null check (octet_length(payload::text) <= 10000000),
  primary key (owner_id, backed_up_on)
);

alter table public.account_snapshot_history enable row level security;
revoke all on public.account_snapshot_history from public, anon, authenticated;
grant select, insert, delete on public.account_snapshot_history to authenticated;

create policy snapshot_history_own_rows on public.account_snapshot_history
  for all to authenticated
  using (owner_id = (select auth.uid()))
  with check (owner_id = (select auth.uid()));

create function public.archive_previous_snapshot()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  today date := (now() at time zone 'UTC')::date;
begin
  insert into public.account_snapshot_history(owner_id, backed_up_on, revision, payload)
  values (old.owner_id, today, old.revision, old.payload)
  on conflict (owner_id, backed_up_on) do nothing;
  delete from public.account_snapshot_history
  where owner_id = old.owner_id and backed_up_on < today - 6;
  return new;
end;
$$;

revoke all on function public.archive_previous_snapshot() from public, anon, authenticated;

create trigger archive_account_snapshot
after update of payload on public.account_snapshots
for each row
when (old.payload is distinct from new.payload)
execute function public.archive_previous_snapshot();
