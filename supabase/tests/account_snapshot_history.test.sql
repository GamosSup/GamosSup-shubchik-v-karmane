begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select plan(1);
do $test$

  declare
    a uuid := gen_random_uuid();
    b uuid := gen_random_uuid();
    v1 jsonb := '{"format":"shubchik-guest","version":1,"tasks":[],"ledger":[]}';
    v2 jsonb := '{"format":"shubchik-guest","version":1,"tasks":[{"id":1,"title":"first","done":0}],"ledger":[]}';
  begin
    insert into auth.users(id) values (a), (b);
    set local role authenticated;
    perform set_config('request.jwt.claim.sub', a::text, true);
    perform public.save_account_snapshot(0, v1);
    perform public.save_account_snapshot(1, v2);
    perform public.save_account_snapshot(2, v1);
    if (select count(*) from public.account_snapshot_history) <> 1
       or not exists(select from public.account_snapshot_history where revision = 1 and payload = v1) then
      raise exception 'Expected one archived previous version';
    end if;
    perform set_config('request.jwt.claim.sub', b::text, true);
    if exists(select from public.account_snapshot_history) then
      raise exception 'Snapshot history was visible to a different account';
    end if;
  end;
$test$;
reset role;
select pass('Automatic backup and account isolation');
select * from finish();
rollback;
