begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select plan(5);

insert into auth.users (id) values
  ('00000000-0000-4000-8000-000000000001'),
  ('00000000-0000-4000-8000-000000000002');

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-4000-8000-000000000001';
select lives_ok($$ insert into public.profiles (id, display_name)
  values ('00000000-0000-4000-8000-000000000001', 'Owner') $$, 'Owner can create profile');
select lives_ok($$ insert into public.devices (owner_id, label)
  values ('00000000-0000-4000-8000-000000000001', 'Flip7') $$, 'Owner can register a device');
select throws_ok($$ insert into public.devices (owner_id, label)
  values ('00000000-0000-4000-8000-000000000002', 'Wrong owner') $$,
  '42501', null, 'Cannot register a device for another account');

set local request.jwt.claim.sub = '00000000-0000-4000-8000-000000000002';
select is((select count(*) from public.profiles), 0::bigint, 'Other account cannot read profile');
select is((select count(*) from public.devices), 0::bigint, 'Other account cannot read device');

select * from finish();
rollback;
