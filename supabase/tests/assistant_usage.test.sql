begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select plan(1);
delete from public.assistant_usage;
do $test$
begin
  begin

    set local role service_role;
    if not public.reserve_assistant_request(2)
       or not public.reserve_assistant_request(2)
       or public.reserve_assistant_request(2)
       or public.reserve_assistant_request(0) then
      raise exception 'Incorrect assistant quota';
    end if;
    set local role authenticated;
    begin
      perform public.reserve_assistant_request(2);
      raise exception 'Authenticated client called service-only function';
    exception when insufficient_privilege then null;
    end;


  end;
end
$test$;
reset role;
select pass('Quota and function permissions');
select * from finish();
rollback;