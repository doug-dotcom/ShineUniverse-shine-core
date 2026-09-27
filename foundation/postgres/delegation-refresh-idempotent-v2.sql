-- Shine Foundation idempotent delegation refresh v2
-- Production migration: foundation_delegation_refresh_idempotent_v2
--
-- A Companion first durably stages its next raw credentials locally, then sends
-- only their SHA-256 hashes plus opaque ids to this v2 contract. The old raw
-- refresh credential is authenticated separately at the HTTP boundary.
--
-- Retrying the exact same request id + staged ids + hashes returns the already
-- committed rotation. Reusing a consumed refresh under a different request is
-- treated as a security replay and revokes the still-active delegated family.

create table if not exists foundation.integration_delegation_refresh_requests (
  request_id uuid primary key,
  client_id text not null references foundation.integration_clients(client_id),
  old_refresh_id uuid not null references foundation.integration_delegation_refresh_credentials(refresh_id),
  new_refresh_id uuid not null unique references foundation.integration_delegation_refresh_credentials(refresh_id),
  new_session_id uuid not null unique references foundation.integration_delegation_sessions(session_id),
  new_refresh_token_hash text not null check (new_refresh_token_hash ~ '^[a-fA-F0-9]{64}$'),
  new_delegation_token_hash text not null check (new_delegation_token_hash ~ '^[a-fA-F0-9]{64}$'),
  refresh_generation integer not null check (refresh_generation >= 2),
  occurred_at timestamptz not null,
  delegation_expires_at timestamptz not null,
  refresh_expires_at timestamptz not null,
  created_at timestamptz not null default now(),
  check (delegation_expires_at > occurred_at),
  check (refresh_expires_at > occurred_at)
);

create index if not exists integration_delegation_refresh_requests_old_idx
  on foundation.integration_delegation_refresh_requests(old_refresh_id,occurred_at desc);
create index if not exists integration_delegation_refresh_requests_client_idx
  on foundation.integration_delegation_refresh_requests(client_id,occurred_at desc);

drop trigger if exists integration_delegation_refresh_requests_append_only
  on foundation.integration_delegation_refresh_requests;
create trigger integration_delegation_refresh_requests_append_only
before update or delete on foundation.integration_delegation_refresh_requests
for each row execute function foundation.reject_append_only_mutation();

revoke all on table foundation.integration_delegation_refresh_requests
  from public,anon,authenticated;

create or replace function foundation.rotate_delegation_refresh_v2(
  p_request_id uuid,
  p_event_id uuid,
  p_old_token_hash text,
  p_client_id text,
  p_new_refresh_id uuid,
  p_new_token_hash text,
  p_new_session_id uuid,
  p_new_delegation_hash text,
  p_occurred_at timestamptz,
  p_delegation_expires_at timestamptz,
  p_refresh_expires_at timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','foundation'
as $function$
declare
  oldr foundation.integration_delegation_refresh_credentials%rowtype;
  prior foundation.integration_delegation_refresh_requests%rowtype;
begin
  if p_new_token_hash !~ '^[a-fA-F0-9]{64}$'
     or p_new_delegation_hash !~ '^[a-fA-F0-9]{64}$'
     or p_old_token_hash !~ '^[a-fA-F0-9]{64}$'
     or p_delegation_expires_at<=p_occurred_at
     or p_delegation_expires_at>p_occurred_at+interval '24 hours'
     or p_refresh_expires_at<=p_occurred_at
     or p_refresh_expires_at>p_occurred_at+interval '90 days' then
    raise exception 'invalid-refresh-rotation-v2' using errcode='22023';
  end if;

  select r.* into oldr
  from foundation.integration_delegation_refresh_credentials r
  where r.token_hash=p_old_token_hash and r.client_id=p_client_id
  for update;

  if not found then
    return jsonb_build_object('rotated',false,'reasonCode','refresh-credential-invalid');
  end if;

  select q.* into prior
  from foundation.integration_delegation_refresh_requests q
  where q.request_id=p_request_id;

  if found then
    if prior.client_id=p_client_id
       and prior.old_refresh_id=oldr.refresh_id
       and prior.new_refresh_id=p_new_refresh_id
       and prior.new_session_id=p_new_session_id
       and prior.new_refresh_token_hash=p_new_token_hash
       and prior.new_delegation_token_hash=p_new_delegation_hash then
      if not exists (
        select 1 from foundation.effective_integration_client_links l
        where l.link_id=oldr.link_id and l.effective_status='active'
      ) then
        return jsonb_build_object('rotated',false,'reasonCode','integration-link-inactive');
      end if;

      return jsonb_build_object(
        'rotated',true,'replayed',true,'reasonCode','refresh-request-replayed',
        'requestId',oldr.request_id,'sessionId',prior.new_session_id,
        'delegationExpiresAt',prior.delegation_expires_at,
        'refreshId',prior.new_refresh_id,
        'refreshGeneration',prior.refresh_generation,
        'refreshExpiresAt',prior.refresh_expires_at
      );
    end if;

    return jsonb_build_object('rotated',false,'reasonCode','refresh-request-conflict');
  end if;

  if exists (
    select 1 from foundation.integration_delegation_refresh_events e
    where e.refresh_id=oldr.refresh_id and e.event_type='rotated'
  ) then
    insert into foundation.integration_delegation_refresh_events(
      event_id,refresh_id,event_type,reason_code,occurred_at
    ) values (
      p_event_id,oldr.refresh_id,'denied','refresh-reuse-detected',p_occurred_at
    ) on conflict (event_id) do nothing;

    insert into foundation.integration_delegation_refresh_events(
      event_id,refresh_id,event_type,reason_code,occurred_at
    )
    select pg_catalog.gen_random_uuid(),e.refresh_id,'revoked',
           'refresh-family-revoked-after-reuse',p_occurred_at
    from foundation.effective_integration_delegation_refresh_credentials e
    where e.link_id=oldr.link_id
      and e.client_id=p_client_id
      and e.effective_status='active';

    insert into foundation.integration_delegation_revocations(
      revocation_id,session_id,owner_shine_id,revoked_at,reason,detail
    )
    select pg_catalog.gen_random_uuid(),s.session_id,s.owner_shine_id,p_occurred_at,
           'security-event','refresh-reuse-detected'
    from foundation.effective_integration_delegation_sessions s
    where s.link_id=oldr.link_id
      and s.client_id=p_client_id
      and s.effective_status='active'
    on conflict (session_id) do nothing;

    return jsonb_build_object('rotated',false,'reasonCode','refresh-reuse-detected');
  end if;

  if exists (
    select 1 from foundation.integration_delegation_refresh_events e
    where e.refresh_id=oldr.refresh_id and e.event_type='revoked'
  )
  or oldr.expires_at<=p_occurred_at
  or p_occurred_at<oldr.issued_at
  or not exists (
    select 1 from foundation.effective_integration_client_links l
    where l.link_id=oldr.link_id and l.effective_status='active'
  ) then
    return jsonb_build_object('rotated',false,'reasonCode','refresh-credential-invalid');
  end if;

  insert into foundation.integration_delegation_refresh_events(
    event_id,refresh_id,event_type,reason_code,occurred_at
  ) values (
    p_event_id,oldr.refresh_id,'rotated','refresh-credential-rotated-v2',p_occurred_at
  );

  insert into foundation.integration_delegation_sessions(
    session_id,request_id,link_id,owner_shine_id,client_id,token_hash,issued_at,expires_at
  ) values (
    p_new_session_id,oldr.request_id,oldr.link_id,oldr.owner_shine_id,p_client_id,
    p_new_delegation_hash,p_occurred_at,p_delegation_expires_at
  );

  insert into foundation.integration_delegation_refresh_credentials(
    refresh_id,request_id,link_id,owner_shine_id,client_id,token_hash,generation,
    issued_at,expires_at,parent_refresh_id
  ) values (
    p_new_refresh_id,oldr.request_id,oldr.link_id,oldr.owner_shine_id,p_client_id,
    p_new_token_hash,oldr.generation+1,p_occurred_at,p_refresh_expires_at,oldr.refresh_id
  );

  insert into foundation.integration_delegation_refresh_requests(
    request_id,client_id,old_refresh_id,new_refresh_id,new_session_id,
    new_refresh_token_hash,new_delegation_token_hash,refresh_generation,
    occurred_at,delegation_expires_at,refresh_expires_at
  ) values (
    p_request_id,p_client_id,oldr.refresh_id,p_new_refresh_id,p_new_session_id,
    p_new_token_hash,p_new_delegation_hash,oldr.generation+1,
    p_occurred_at,p_delegation_expires_at,p_refresh_expires_at
  );

  return jsonb_build_object(
    'rotated',true,'replayed',false,'reasonCode','refresh-credential-rotated-v2',
    'requestId',oldr.request_id,'sessionId',p_new_session_id,
    'delegationExpiresAt',p_delegation_expires_at,'refreshId',p_new_refresh_id,
    'refreshGeneration',oldr.generation+1,'refreshExpiresAt',p_refresh_expires_at
  );
end;
$function$;

revoke all on function foundation.rotate_delegation_refresh_v2(
  uuid,uuid,text,text,uuid,text,uuid,text,timestamptz,timestamptz,timestamptz
) from public;

grant execute on function foundation.rotate_delegation_refresh_v2(
  uuid,uuid,text,text,uuid,text,uuid,text,timestamptz,timestamptz,timestamptz
) to foundation_runtime;
