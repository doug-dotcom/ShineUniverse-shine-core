-- Historical production backfill: revocation acknowledgement checkpoint v1.
-- Mirrors migration 20260926145550.

create table foundation.app_revocation_checkpoints (
  app_id text primary key references foundation.app_registry(app_id),
  last_sequence_no bigint not null default 0 check (last_sequence_no >= 0),
  last_ack_at timestamptz,
  last_ack_request_id uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table foundation.app_revocation_checkpoints is
  'Current app-scoped revocation delivery checkpoint. Sequence numbers are global outbox cursors; gaps belonging to other apps are valid.';

alter table foundation.app_revocation_checkpoints enable row level security;

create policy foundation_runtime_revocation_checkpoints_select
on foundation.app_revocation_checkpoints
for select
to foundation_runtime
using (true);

revoke all on foundation.app_revocation_checkpoints from public, anon, authenticated;
grant select on foundation.app_revocation_checkpoints to foundation_runtime, service_role;

create table foundation.app_revocation_ack_events (
  ack_id uuid primary key,
  request_id uuid not null unique,
  app_id text not null references foundation.app_registry(app_id),
  sequence_no bigint not null check (sequence_no > 0),
  outcome text not null check (outcome in ('advanced','already-acked','denied')),
  reason_code text not null,
  occurred_at timestamptz not null,
  created_at timestamptz not null default now()
);

comment on table foundation.app_revocation_ack_events is
  'Append-only evidence that an app reported successful processing of revocation events through a global outbox cursor.';

alter table foundation.app_revocation_ack_events enable row level security;

create policy foundation_runtime_revocation_ack_events_select
on foundation.app_revocation_ack_events
for select
to foundation_runtime
using (true);

revoke all on foundation.app_revocation_ack_events from public, anon, authenticated;
grant select on foundation.app_revocation_ack_events to foundation_runtime, service_role;

create index app_revocation_ack_events_app_time_idx
  on foundation.app_revocation_ack_events(app_id, occurred_at desc);

create trigger app_revocation_ack_events_append_only
before update or delete on foundation.app_revocation_ack_events
for each row execute function foundation.reject_append_only_mutation();

create or replace function foundation.ack_app_revocations_v1(
  p_ack_id uuid,
  p_request_id uuid,
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
  checkpoint bigint;
  result_outcome text;
  result_reason text;
begin
  select * into prior
  from foundation.app_revocation_ack_events
  where request_id = p_request_id;

  if found then
    if prior.app_id <> p_app_id
       or prior.sequence_no <> p_sequence_no then
      raise exception 'revocation-ack-replay-conflict' using errcode='23505';
    end if;

    select coalesce(c.last_sequence_no,0) into checkpoint
    from foundation.app_revocation_checkpoints c
    where c.app_id = p_app_id;

    return query
      select prior.outcome, prior.reason_code, coalesce(checkpoint,0);
    return;
  end if;

  if p_app_id is null
     or p_app_id !~ '^shine\.[a-z0-9][a-z0-9-]*$'
     or p_sequence_no is null
     or p_sequence_no <= 0 then
    result_outcome := 'denied';
    result_reason := 'invalid-revocation-ack-request';
    checkpoint := 0;
  elsif not exists (
    select 1
    from foundation.app_registry
    where app_id = p_app_id
      and status = 'active'
  ) then
    result_outcome := 'denied';
    result_reason := 'app-unregistered';
    checkpoint := 0;
  else
    insert into foundation.app_revocation_checkpoints(
      app_id,last_sequence_no,created_at,updated_at
    ) values (
      p_app_id,0,p_occurred_at,p_occurred_at
    )
    on conflict (app_id) do nothing;

    select last_sequence_no into checkpoint
    from foundation.app_revocation_checkpoints
    where app_id = p_app_id
    for update;

    if p_sequence_no < checkpoint then
      result_outcome := 'denied';
      result_reason := 'revocation-checkpoint-regression';
    elsif p_sequence_no = checkpoint then
      result_outcome := 'already-acked';
      result_reason := 'revocation-checkpoint-already-current';
    elsif not exists (
      select 1
      from foundation.revocation_outbox o
      join foundation.access_grants g
        on g.grant_id = o.grant_id
       and g.owner_shine_id = o.owner_shine_id
      where o.sequence_no = p_sequence_no
        and g.app_id = p_app_id
    ) then
      result_outcome := 'denied';
      result_reason := 'revocation-sequence-not-for-app';
    else
      update foundation.app_revocation_checkpoints
      set last_sequence_no = p_sequence_no,
          last_ack_at = p_occurred_at,
          last_ack_request_id = p_request_id,
          updated_at = p_occurred_at
      where app_id = p_app_id;

      checkpoint := p_sequence_no;
      result_outcome := 'advanced';
      result_reason := 'revocation-checkpoint-advanced';
    end if;
  end if;

  insert into foundation.app_revocation_ack_events(
    ack_id,request_id,app_id,sequence_no,outcome,reason_code,occurred_at
  ) values (
    p_ack_id,p_request_id,p_app_id,p_sequence_no,
    result_outcome,result_reason,p_occurred_at
  );

  return query select result_outcome,result_reason,checkpoint;
end;
$function$;

revoke all on function foundation.ack_app_revocations_v1(
  uuid, uuid, text, bigint, timestamptz
) from public, anon, authenticated, service_role;

grant execute on function foundation.ack_app_revocations_v1(
  uuid, uuid, text, bigint, timestamptz
) to foundation_runtime;

create or replace function foundation.get_app_revocation_status_v1(
  p_app_id text
)
returns table(
  checkpoint_sequence bigint,
  last_ack_at timestamptz,
  latest_sequence bigint,
  pending_count bigint,
  oldest_pending_at timestamptz
)
language plpgsql
security definer
set search_path = pg_catalog, foundation
as $function$
declare
  checkpoint bigint;
  acked_at timestamptz;
begin
  if p_app_id is null
     or p_app_id !~ '^shine\.[a-z0-9][a-z0-9-]*$' then
    raise exception 'invalid-revocation-status-request' using errcode='22023';
  end if;

  if not exists (
    select 1 from foundation.app_registry
    where app_id=p_app_id and status='active'
  ) then
    raise exception 'app-unregistered' using errcode='22023';
  end if;

  select c.last_sequence_no,c.last_ack_at
  into checkpoint,acked_at
  from foundation.app_revocation_checkpoints c
  where c.app_id=p_app_id;

  checkpoint := coalesce(checkpoint,0);

  return query
  select
    checkpoint,
    acked_at,
    coalesce(max(o.sequence_no),0)::bigint,
    count(*) filter (where o.sequence_no > checkpoint)::bigint,
    min(o.created_at) filter (where o.sequence_no > checkpoint)
  from foundation.revocation_outbox o
  join foundation.access_grants g
    on g.grant_id=o.grant_id
   and g.owner_shine_id=o.owner_shine_id
  where g.app_id=p_app_id;
end;
$function$;

revoke all on function foundation.get_app_revocation_status_v1(text)
from public, anon, authenticated, service_role;

grant execute on function foundation.get_app_revocation_status_v1(text)
to foundation_runtime;
