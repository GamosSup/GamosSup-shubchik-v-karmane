create table public.assistant_usage (
  month_start date primary key,
  requests integer not null check (requests between 1 and 1000)
);

alter table public.assistant_usage enable row level security;
revoke all on public.assistant_usage from public, anon, authenticated;
grant select, insert, update on public.assistant_usage to service_role;

create function public.reserve_assistant_request(monthly_limit integer)
returns boolean
language plpgsql
security invoker
set search_path = ''
as $$
declare
  reserved integer;
begin
  if monthly_limit is null or monthly_limit not between 1 and 1000 then
    return false;
  end if;
  insert into public.assistant_usage as usage (month_start, requests)
  values (date_trunc('month', now() at time zone 'UTC')::date, 1)
  on conflict (month_start) do update
    set requests = usage.requests + 1
    where usage.requests < monthly_limit
  returning requests into reserved;
  return reserved is not null;
end;
$$;

revoke all on function public.reserve_assistant_request(integer) from public, anon, authenticated;
grant execute on function public.reserve_assistant_request(integer) to service_role;
