-- Historical production backfill: Foundation grant revocation flow v1.
-- Mirrors migration 20260926143428 plus advisor indexes 20260926143628.
-- Production already has this schema; this file keeps the Core repository honest.

create table foundation.grant_revocation_events (
  event_id uuid primary key,
  request_id uuid not null unique,
  requested_grant_id uuid not null,
  owner_shine_id uuid not null references foundation.shine_identities(shine_id),
  app_id text not null references foundation.app_registry(app_id),
  outcome text not null check (outcome in ('revoked','already-revoked','denied')),
  reason_code text not null,
  revocation_id uuid null references foundation.grant_revocations(revocation_id),
  occurred_at timestamptz not null,
  created_at timestamptz not null default now()
);

comment on table foundation.grant_revocation_events is
  'Append-only user consent withdrawal decisions for Foundation access grants.';

alter table foundation.grant_revocation_events enable row level security;

create policy foundation_runtime_revocation_events_select
on foundation.grant_revocation_events
for select
to foundation_runtime
using (true);

revoke all on foundation.grant_revocation_events from public, anon, authenticated;
grant select on foundation.grant_revocation_events to foundation_runtime, service_role;

create index grant_revocation_events_owner_time_idx
  on foundation.grant_revocation_events(owner_shine_id, occurred_at desc);

create index grant_revocation_events_grant_idx
  on foundation.grant_revocation_events(requested_grant_id);

create index grant_revocation_events_app_id_idx
  on foundation.grant_revocation_events(app_id);

create index grant_revocation_events_revocation_id_idx
  on foundation.grant_revocation_events(revocation_id)
  where revocation_id is not null;

create trigger grant_revocation_events_append_only
before update or delete on foundation.grant_revocation_events
for each row execute function foundation.reject_append_only_mutation();

create or replace function foundation.revoke_access_grant_v1(
  p_event_id uuid,
  p_revocation_id uuid,
  p_request_id uuid,
  p_requested_grant_id uuid,
  p_owner_shine_id uuid,
  p_app_id text,
  p_occurred_at timestamptz
)
returns table(outcome text, reason_code text, revocation_id uuid)
language plpgsql
security definer
set search_path = pg_catalog, foundation
as $function$
declare
  prior foundation.grant_revocation_events%rowtype;
  target_grant foundation.access_grants%rowtype;
  existing_revocation foundation.grant_revocations%rowtype;
  result_outcome text;
  result_reason text;
  result_revocation_id uuid;
begin
  select * into prior
  from foundation.grant_revocation_events
  where request_id = p_request_id;

  if found then
    if prior.requested_grant_id <> p_requested_grant_id
      or prior.owner_shine_id <> p_owner_shine_id
      or prior.app_id <> p_app_id then
      raise exception 'grant-revocation-replay-conflict' using errcode='23505';
    end if;

    return query
      select prior.outcome, prior.reason_code, prior.revocation_id;
    return;
  end if;

  select * into target_grant
  from foundation.access_grants
  where grant_id = p_requested_grant_id
  for update;

  if not found then
    result_outcome := 'denied';
    result_reason := 'grant-not-found';
  elsif target_grant.owner_shine_id <> p_owner_shine_id then
    result_outcome := 'denied';
    result_reason := 'grant-owner-mismatch';
  elsif target_grant.app_id <> p_app_id then
    result_outcome := 'denied';
    result_reason := 'grant-app-mismatch';
  else
    select * into existing_revocation
    from foundation.grant_revocations
    where grant_id = p_requested_grant_id;

    if found then
      result_outcome := 'already-revoked';
      result_reason := 'grant-already-revoked';
      result_revocation_id := existing_revocation.revocation_id;
    else
      insert into foundation.grant_revocations(
        revocation_id,
        grant_id,
        owner_shine_id,
        revoked_at,
        reason,
        detail
      ) values (
        p_revocation_id,
        p_requested_grant_id,
        p_owner_shine_id,
        p_occurred_at,
        'user-revoked',
        'foundation-gateway-consent-withdrawal'
      );

      result_outcome := 'revoked';
      result_reason := 'grant-revoked-by-user';
      result_revocation_id := p_revocation_id;
    end if;
  end if;

  insert into foundation.grant_revocation_events(
    event_id,
    request_id,
    requested_grant_id,
    owner_shine_id,
    app_id,
    outcome,
    reason_code,
    revocation_id,
    occurred_at
  ) values (
    p_event_id,
    p_request_id,
    p_requested_grant_id,
    p_owner_shine_id,
    p_app_id,
    result_outcome,
    result_reason,
    result_revocation_id,
    p_occurred_at
  );

  return query
    select result_outcome, result_reason, result_revocation_id;
end;
$function$;

revoke all on function foundation.revoke_access_grant_v1(
  uuid, uuid, uuid, uuid, uuid, text, timestamptz
) from public, anon, authenticated, service_role;

grant execute on function foundation.revoke_access_grant_v1(
  uuid, uuid, uuid, uuid, uuid, text, timestamptz
) to foundation_runtime;
