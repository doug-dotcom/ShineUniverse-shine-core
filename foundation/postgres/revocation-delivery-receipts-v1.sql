-- Historical production backfill: revocation delivery receipts v1.
-- Mirrors migration 20260926221323.

create table foundation.app_revocation_deliveries (
  delivery_id uuid primary key,
  app_id text not null references foundation.app_registry(app_id),
  after_sequence bigint not null check (after_sequence >= 0),
  delivered_sequences bigint[] not null,
  terminal_sequence bigint not null check (terminal_sequence > 0),
  event_count integer not null check (event_count between 1 and 100),
  served_at timestamptz not null,
  created_at timestamptz not null default now(),
  constraint app_revocation_deliveries_count_match
    check (cardinality(delivered_sequences) = event_count),
  constraint app_revocation_deliveries_terminal_match
    check (delivered_sequences[event_count] = terminal_sequence)
);

comment on table foundation.app_revocation_deliveries is
  'Append-only receipts proving which app-scoped revocation batch Foundation actually served.';

alter table foundation.app_revocation_deliveries enable row level security;

create policy foundation_runtime_revocation_deliveries_select
on foundation.app_revocation_deliveries
for select
to foundation_runtime
using (true);

revoke all on foundation.app_revocation_deliveries from public, anon, authenticated;
grant select on foundation.app_revocation_deliveries to foundation_runtime, service_role;

create index app_revocation_deliveries_app_time_idx
  on foundation.app_revocation_deliveries(app_id, served_at desc);

create trigger app_revocation_deliveries_append_only
before update or delete on foundation.app_revocation_deliveries
for each row execute function foundation.reject_append_only_mutation();

create or replace function foundation.record_app_revocation_delivery_v1(
  p_delivery_id uuid,
  p_app_id text,
  p_after_sequence bigint,
  p_sequence_nos bigint[],
  p_occurred_at timestamptz
)
returns table(
  delivery_id uuid,
  terminal_sequence bigint,
  event_count integer
)
language plpgsql
security definer
set search_path = pg_catalog, foundation
as $function$
declare
  expected bigint[];
  n integer;
  terminal bigint;
begin
  n := cardinality(p_sequence_nos);

  if p_delivery_id is null
     or p_app_id is null
     or p_app_id !~ '^shine\.[a-z0-9][a-z0-9-]*$'
     or p_after_sequence is null
     or p_after_sequence < 0
     or p_sequence_nos is null
     or n is null
     or n < 1
     or n > 100 then
    raise exception 'invalid-revocation-delivery-request' using errcode='22023';
  end if;

  if not exists (
    select 1 from foundation.app_registry
    where app_id=p_app_id and status='active'
  ) then
    raise exception 'app-unregistered' using errcode='22023';
  end if;

  if exists (
    select 1
    from generate_subscripts(p_sequence_nos,1) s(i)
    where p_sequence_nos[s.i] <= p_after_sequence
       or (s.i > 1 and p_sequence_nos[s.i] <= p_sequence_nos[s.i-1])
  ) then
    raise exception 'invalid-revocation-delivery-order' using errcode='22023';
  end if;

  select array_agg(x.sequence_no order by x.sequence_no)
  into expected
  from (
    select o.sequence_no
    from foundation.revocation_outbox o
    join foundation.access_grants g
      on g.grant_id=o.grant_id
     and g.owner_shine_id=o.owner_shine_id
    where g.app_id=p_app_id
      and o.sequence_no > p_after_sequence
    order by o.sequence_no
    limit n
  ) x;

  if expected is distinct from p_sequence_nos then
    raise exception 'revocation-delivery-sequence-mismatch' using errcode='22023';
  end if;

  terminal := p_sequence_nos[n];

  insert into foundation.app_revocation_deliveries(
    delivery_id,app_id,after_sequence,delivered_sequences,
    terminal_sequence,event_count,served_at
  ) values (
    p_delivery_id,p_app_id,p_after_sequence,p_sequence_nos,
    terminal,n,p_occurred_at
  );

  return query select p_delivery_id,terminal,n;
end;
$function$;

revoke all on function foundation.record_app_revocation_delivery_v1(
  uuid,text,bigint,bigint[],timestamptz
) from public,anon,authenticated,service_role;

grant execute on function foundation.record_app_revocation_delivery_v1(
  uuid,text,bigint,bigint[],timestamptz
) to foundation_runtime;

alter table foundation.app_revocation_ack_events
  add column delivery_id uuid references foundation.app_revocation_deliveries(delivery_id);

create index app_revocation_ack_events_delivery_idx
  on foundation.app_revocation_ack_events(delivery_id)
  where delivery_id is not null;

create or replace function foundation.ack_app_revocations_v2(
  p_ack_id uuid,
  p_request_id uuid,
  p_delivery_id uuid,
  p_app_id text,
  p_sequence_no bigint,
  p_occurred_at timestamptz
)
returns table(
  outcome text,
  reason_code text,
  checkpoint_sequence bigint
)
language plpgsql
security definer
set search_path = pg_catalog, foundation
as $function$
declare
  prior foundation.app_revocation_ack_events%rowtype;
  delivery foundation.app_revocation_deliveries%rowtype;
  checkpoint bigint;
  result_outcome text;
  result_reason text;
  uncovered_count bigint;
begin
  select * into prior
  from foundation.app_revocation_ack_events
  where request_id=p_request_id;

  if found then
    if prior.app_id <> p_app_id
       or prior.sequence_no <> p_sequence_no
       or prior.delivery_id is distinct from p_delivery_id then
      raise exception 'revocation-ack-replay-conflict' using errcode='23505';
    end if;

    select coalesce(c.last_sequence_no,0) into checkpoint
    from foundation.app_revocation_checkpoints c
    where c.app_id=p_app_id;

    return query
      select prior.outcome,prior.reason_code,coalesce(checkpoint,0);
    return;
  end if;

  insert into foundation.app_revocation_checkpoints(
    app_id,last_sequence_no,created_at,updated_at
  )
  select p_app_id,0,p_occurred_at,p_occurred_at
  where exists (
    select 1 from foundation.app_registry
    where app_id=p_app_id and status='active'
  )
  on conflict (app_id) do nothing;

  select coalesce(c.last_sequence_no,0) into checkpoint
  from foundation.app_revocation_checkpoints c
  where c.app_id=p_app_id
  for update;

  checkpoint := coalesce(checkpoint,0);

  select * into delivery
  from foundation.app_revocation_deliveries
  where delivery_id=p_delivery_id;

  if p_app_id is null
     or p_app_id !~ '^shine\.[a-z0-9][a-z0-9-]*$'
     or p_delivery_id is null
     or p_sequence_no is null
     or p_sequence_no <= 0 then
    result_outcome := 'denied';
    result_reason := 'invalid-revocation-ack-request';
  elsif delivery.delivery_id is null then
    result_outcome := 'denied';
    result_reason := 'revocation-delivery-not-found';
  elsif delivery.app_id <> p_app_id then
    result_outcome := 'denied';
    result_reason := 'revocation-delivery-app-mismatch';
  elsif delivery.terminal_sequence <> p_sequence_no then
    result_outcome := 'denied';
    result_reason := 'revocation-delivery-terminal-mismatch';
  elsif p_sequence_no < checkpoint then
    result_outcome := 'denied';
    result_reason := 'revocation-checkpoint-regression';
  elsif p_sequence_no = checkpoint then
    result_outcome := 'already-acked';
    result_reason := 'revocation-checkpoint-already-current';
  else
    select count(*) into uncovered_count
    from foundation.revocation_outbox o
    join foundation.access_grants g
      on g.grant_id=o.grant_id
     and g.owner_shine_id=o.owner_shine_id
    where g.app_id=p_app_id
      and o.sequence_no > checkpoint
      and o.sequence_no <= p_sequence_no
      and not (o.sequence_no = any(delivery.delivered_sequences));

    if uncovered_count > 0 then
      result_outcome := 'denied';
      result_reason := 'revocation-delivery-does-not-cover-pending';
    else
      update foundation.app_revocation_checkpoints
      set last_sequence_no=p_sequence_no,
          last_ack_at=p_occurred_at,
          last_ack_request_id=p_request_id,
          updated_at=p_occurred_at
      where app_id=p_app_id;

      checkpoint := p_sequence_no;
      result_outcome := 'advanced';
      result_reason := 'revocation-checkpoint-advanced';
    end if;
  end if;

  insert into foundation.app_revocation_ack_events(
    ack_id,request_id,app_id,sequence_no,outcome,reason_code,
    occurred_at,delivery_id
  ) values (
    p_ack_id,p_request_id,p_app_id,p_sequence_no,result_outcome,
    result_reason,p_occurred_at,p_delivery_id
  );

  return query select result_outcome,result_reason,checkpoint;
end;
$function$;

revoke all on function foundation.ack_app_revocations_v1(
  uuid,uuid,text,bigint,timestamptz
) from foundation_runtime;

revoke all on function foundation.ack_app_revocations_v2(
  uuid,uuid,uuid,text,bigint,timestamptz
) from public,anon,authenticated,service_role;

grant execute on function foundation.ack_app_revocations_v2(
  uuid,uuid,uuid,text,bigint,timestamptz
) to foundation_runtime;
