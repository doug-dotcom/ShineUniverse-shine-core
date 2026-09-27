-- Shine Foundation delegation refresh replay hardening v1
-- Production migration: foundation_delegation_refresh_replay_hardening_v1
--
-- Hardens the existing v1 refresh contract without changing its HTTP shape.
-- The raw refresh row is locked before state is re-checked so concurrent
-- refresh requests cannot both rotate the same credential. Reuse of an
-- already-rotated credential is treated as a replay signal and fails closed:
-- all still-active descendant refresh credentials and delegation sessions for
-- the same approved client link are revoked.

create or replace function foundation.rotate_delegation_refresh_v1(
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
begin
  select r.* into oldr
  from foundation.integration_delegation_refresh_credentials r
  where r.token_hash=p_old_token_hash
    and r.client_id=p_client_id
  for update;

  if not found then
    return jsonb_build_object('rotated',false,'reasonCode','refresh-credential-invalid');
  end if;

  if exists (
    select 1
    from foundation.integration_delegation_refresh_events e
    where e.refresh_id=oldr.refresh_id
      and e.event_type='rotated'
  ) then
    insert into foundation.integration_delegation_refresh_events(
      event_id,refresh_id,event_type,reason_code,occurred_at
    ) values (
      p_event_id,oldr.refresh_id,'denied','refresh-reuse-detected',p_occurred_at
    )
    on conflict (event_id) do nothing;

    insert into foundation.integration_delegation_refresh_events(
      event_id,refresh_id,event_type,reason_code,occurred_at
    )
    select
      pg_catalog.gen_random_uuid(),
      e.refresh_id,
      'revoked',
      'refresh-family-revoked-after-reuse',
      p_occurred_at
    from foundation.effective_integration_delegation_refresh_credentials e
    where e.link_id=oldr.link_id
      and e.client_id=p_client_id
      and e.effective_status='active';

    insert into foundation.integration_delegation_revocations(
      revocation_id,session_id,owner_shine_id,revoked_at,reason,detail
    )
    select
      pg_catalog.gen_random_uuid(),
      s.session_id,
      s.owner_shine_id,
      p_occurred_at,
      'security-event',
      'refresh-reuse-detected'
    from foundation.effective_integration_delegation_sessions s
    where s.link_id=oldr.link_id
      and s.client_id=p_client_id
      and s.effective_status='active'
    on conflict (session_id) do nothing;

    return jsonb_build_object('rotated',false,'reasonCode','refresh-reuse-detected');
  end if;

  if exists (
    select 1
    from foundation.integration_delegation_refresh_events e
    where e.refresh_id=oldr.refresh_id
      and e.event_type='revoked'
  )
  or oldr.expires_at<=p_occurred_at
  or p_occurred_at<oldr.issued_at
  or not exists (
    select 1
    from foundation.effective_integration_client_links l
    where l.link_id=oldr.link_id
      and l.effective_status='active'
  ) then
    return jsonb_build_object('rotated',false,'reasonCode','refresh-credential-invalid');
  end if;

  if p_new_token_hash !~ '^[a-fA-F0-9]{64}$'
     or p_new_delegation_hash !~ '^[a-fA-F0-9]{64}$'
     or p_delegation_expires_at<=p_occurred_at
     or p_delegation_expires_at>p_occurred_at+interval '24 hours'
     or p_refresh_expires_at<=p_occurred_at
     or p_refresh_expires_at>p_occurred_at+interval '90 days' then
    raise exception 'invalid-refresh-rotation' using errcode='22023';
  end if;

  insert into foundation.integration_delegation_refresh_events(
    event_id,refresh_id,event_type,reason_code,occurred_at
  ) values (
    p_event_id,oldr.refresh_id,'rotated','refresh-credential-rotated',p_occurred_at
  );

  insert into foundation.integration_delegation_sessions(
    session_id,request_id,link_id,owner_shine_id,client_id,
    token_hash,issued_at,expires_at
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

  return jsonb_build_object(
    'rotated',true,
    'reasonCode','refresh-credential-rotated',
    'requestId',oldr.request_id,
    'sessionId',p_new_session_id,
    'delegationExpiresAt',p_delegation_expires_at,
    'refreshId',p_new_refresh_id,
    'refreshGeneration',oldr.generation+1,
    'refreshExpiresAt',p_refresh_expires_at
  );
end;
$function$;

revoke all on function foundation.rotate_delegation_refresh_v1(
  uuid,text,text,uuid,text,uuid,text,timestamptz,timestamptz,timestamptz
) from public;

grant execute on function foundation.rotate_delegation_refresh_v1(
  uuid,text,text,uuid,text,uuid,text,timestamptz,timestamptz,timestamptz
) to foundation_runtime;
