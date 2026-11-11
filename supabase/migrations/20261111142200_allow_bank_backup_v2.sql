alter table public.account_snapshots
  drop constraint account_snapshots_payload_check,
  add constraint account_snapshots_payload_check check (
    octet_length(payload::text) <= 10000000
    and coalesce(payload->>'format' = 'shubchik-guest', false)
    and coalesce(payload->'version' in ('1'::jsonb, '2'::jsonb), false)
    and coalesce(jsonb_typeof(payload->'tasks') = 'array', false)
    and coalesce(jsonb_typeof(payload->'ledger') = 'array', false)
  );
