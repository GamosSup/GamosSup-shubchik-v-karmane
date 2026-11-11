begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select plan(1);
do $test$

  declare
    a uuid := gen_random_uuid();
    b uuid := gen_random_uuid();
    original jsonb := '{"format":"shubchik-guest","version":1,"tasks":[],"ledger":[]}';
    changed jsonb := '{"format":"shubchik-guest","version":1,"tasks":[{"id":1,"title":"test","done":0}],"ledger":[]}';
  begin
    insert into auth.users(id) values(a), (b);
    set local role authenticated;
    perform set_config('request.jwt.claim.sub', a::text, true);
    if public.save_account_snapshot(0, original) <> 1
      or public.save_account_snapshot(0, original) <> 1
      or public.save_account_snapshot(1, changed) <> 2 then
      raise exception 'Revision did not advance or retry was not idempotent';
    end if;
    begin
      perform public.save_account_snapshot(1, original);
      raise exception 'Stale write succeeded';
    exception when serialization_failure then null;
    end;
    perform set_config('request.jwt.claim.sub', b::text, true);
    if exists(select from public.account_snapshots) then
      raise exception 'Cross-account read succeeded';
    end if;
    begin
      insert into public.account_snapshots(owner_id,revision,payload)
      values(a,1,original);
      raise exception 'Cross-account insert succeeded';
    exception when insufficient_privilege then null;
    end;
  end;
$test$;
reset role;
select pass('Snapshot revision, retry, conflict, and RLS assertions passed');
select * from finish();
rollback;
