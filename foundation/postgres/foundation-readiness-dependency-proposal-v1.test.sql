begin;

insert into foundation.service_deployment_receipts(
  receipt_id,service_id,environment,provider,runtime_ref,runtime_version,
  artifact_sha256,runtime_state,source_ref,provider_evidence_ref,
  provider_observed_at,submitted_by,metadata,recorded_at
) values (
  '47000000-0000-4000-8000-000000000001'::uuid,
  'foundation.gateway','production','supabase-edge','supabase://test','47',
  repeat('a',64),'active',
  'github://doug-dotcom/ShineUniverse-shine-core/commit/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  'test:47',now(),'test','{}'::jsonb,now()
);

insert into foundation.service_deployment_receipt_publications(
  publication_id,publication_key,receipt_id,service_id,environment,provider,
  runtime_version,artifact_sha256,source_ref,provider_evidence_ref,
  publication_outcome,submitted_by,transport,transport_run_id,
  transport_run_attempt,transport_event,transport_repository,transport_ref,
  transport_workflow_ref,transport_workflow_sha,rollback,metadata,published_at
) values (
  '47000000-0000-4000-8000-000000000002'::uuid,
  'github-oidc:47:1:47000000-0000-4000-8000-000000000001',
  '47000000-0000-4000-8000-000000000001'::uuid,
  'foundation.gateway','production','supabase-edge','47',repeat('a',64),
  'github://doug-dotcom/ShineUniverse-shine-core/commit/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  'test:47','accepted-new','github-actions-oidc','github-oidc','47','1','push',
  'doug-dotcom/ShineUniverse-shine-core','refs/heads/main','test/workflow@main',
  repeat('4',40),false,'{}'::jsonb,now()
);

insert into foundation.foundation_release_identity_bindings(
  binding_id,release_ref,service_id,environment,foundation_layer,source_ref,
  runtime_version,artifact_sha256,deployment_receipt_id,publication_id,
  publication_assurance,readiness_state_at_bind,readiness_fingerprint_at_bind,
  bound_by,metadata,bound_at
) values (
  '47000000-0000-4000-8000-000000000003'::uuid,
  'foundation:layer-46:aaaaaaaa','foundation.gateway','production',46,
  'github://doug-dotcom/ShineUniverse-shine-core/commit/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  '47',repeat('a',64),
  '47000000-0000-4000-8000-000000000001'::uuid,
  '47000000-0000-4000-8000-000000000002'::uuid,
  'github-oidc','degraded',repeat('1',32),'test','{}'::jsonb,now()
);

insert into foundation.foundation_readiness_drift_observations(
  observation_id,environment,binding_id,release_ref,readiness_state_at_bind,
  readiness_fingerprint_at_bind,current_readiness_state,current_readiness_fingerprint,
  drift_state,deployment_identity_stable,privileged_operations_mode,
  worker_operations_mode,reason_codes,degraded_scopes,guarded_scopes,blocked_scopes,
  snapshot,evidence_fingerprint,condition_fingerprint,observed_at
) values (
  '47000000-0000-4000-8000-000000000101'::uuid,'production',
  '47000000-0000-4000-8000-000000000003'::uuid,'foundation:layer-46:aaaaaaaa',
  'degraded',repeat('1',32),'degraded',repeat('2',32),'stable',true,
  'degraded','degraded','["dependency-degraded"]'::jsonb,
  '["context-operations","protected-operations"]'::jsonb,
  '["identity-operations"]'::jsonb,
  '["protected-operations"]'::jsonb,
  '{"current":{"privilegedOperationsMode":"degraded","workerOperationsMode":"degraded"}}'::jsonb,
  repeat('2',32),repeat('9',32),now()
);

insert into foundation.foundation_readiness_incident_events(
  event_id,incident_key,environment,event_type,readiness_state,drift_state,severity,
  reason_codes,degraded_scopes,guarded_scopes,blocked_scopes,
  readiness_drift_observation_id,evidence_fingerprint,condition_fingerprint,
  detection_started_at,persistence_threshold_seconds,persistence_seconds,
  snapshot,occurred_at
) values (
  '47000000-0000-4000-8000-000000000201'::uuid,'production:readiness',
  'production','opened','degraded','stable','warning',
  '["dependency-degraded"]'::jsonb,
  '["context-operations","protected-operations"]'::jsonb,
  '["identity-operations"]'::jsonb,
  '["protected-operations"]'::jsonb,
  '47000000-0000-4000-8000-000000000101'::uuid,
  repeat('2',32),repeat('9',32),now()-interval '10 minutes',300,600,
  '{"current":{"privilegedOperationsMode":"degraded","workerOperationsMode":"degraded"}}'::jsonb,
  now()
);

do $p$
declare
  v jsonb;
  v2 jsonb;
  s jsonb;
  pid uuid;
  h text;
begin
  v:=foundation.propose_readiness_dependency_remediation_v1('production',now());

  if v->>'proposed'<>'true'
     or v->>'status'<>'generated'
     or v->>'executionAuthorityGranted'<>'false'
     or v->>'approvalGranted'<>'false'
     or not ((v->'proposal'->'prohibitedWork') ? 'mutate-foundation-canonical-truth')
     or not ((v->'proposal'->'affectedScopes') ? 'protected-operations')
     or jsonb_array_length(v->'proposal'->'affectedScopes')<>3
     or v->'proposal'->>'executionAuthorityGranted'<>'false'
     or v->'proposal'->>'approvalGranted'<>'false' then
    raise exception 'proposal invalid: %',v;
  end if;

  if not exists (
    select 1
    from jsonb_array_elements(v->'proposal'->'scopePlan') x
    where x->>'scope'='protected-operations'
      and x->>'disposition'='blocked'
  ) then
    raise exception 'blocked disposition must outrank duplicate degraded scope: %',
      v->'proposal'->'scopePlan';
  end if;

  pid:=(v->>'proposalId')::uuid;

  v2:=foundation.propose_readiness_dependency_remediation_v1(
    'production',now()+interval '1 minute'
  );

  if v2->>'status'<>'existing'
     or v2->>'proposalId'<>pid::text
     or v2->>'proposalSha256'<>v->>'proposalSha256' then
    raise exception 'same incident condition must reuse original proposal: % %',v,v2;
  end if;

  s:=foundation.get_readiness_dependency_proposal_status_v1(pid);

  if s->>'state'<>'current'
     or s->>'usable'<>'true'
     or s->>'integrityVerified'<>'true'
     or s->>'executionAuthorityGranted'<>'false'
     or s->>'approvalGranted'<>'false' then
    raise exception 'proposal status invalid: %',s;
  end if;

  select encode(
    extensions.digest(convert_to(proposal::text,'UTF8'),'sha256'),'hex'
  ) into h
  from foundation.readiness_dependency_remediation_proposals
  where proposal_id=pid;

  if h<>v->>'proposalSha256' then
    raise exception 'stored proposal integrity hash mismatch';
  end if;
end;
$p$;

insert into foundation.foundation_readiness_drift_observations(
  observation_id,environment,binding_id,release_ref,readiness_state_at_bind,
  readiness_fingerprint_at_bind,current_readiness_state,current_readiness_fingerprint,
  drift_state,deployment_identity_stable,privileged_operations_mode,
  worker_operations_mode,reason_codes,degraded_scopes,guarded_scopes,blocked_scopes,
  snapshot,evidence_fingerprint,condition_fingerprint,observed_at
) values (
  '47000000-0000-4000-8000-000000000102'::uuid,'production',
  '47000000-0000-4000-8000-000000000003'::uuid,'foundation:layer-46:aaaaaaaa',
  'degraded',repeat('1',32),'not-ready',repeat('3',32),'not-bindable',true,
  'blocked','blocked','["dependency-blocked"]'::jsonb,
  '[]'::jsonb,'[]'::jsonb,'["protected-operations"]'::jsonb,
  '{"current":{"privilegedOperationsMode":"blocked","workerOperationsMode":"blocked"}}'::jsonb,
  repeat('3',32),repeat('8',32),now()+interval '1 second'
);

insert into foundation.foundation_readiness_incident_events(
  event_id,incident_key,environment,event_type,readiness_state,drift_state,severity,
  reason_codes,degraded_scopes,guarded_scopes,blocked_scopes,
  readiness_drift_observation_id,evidence_fingerprint,condition_fingerprint,
  detection_started_at,persistence_threshold_seconds,persistence_seconds,
  snapshot,occurred_at
) values (
  '47000000-0000-4000-8000-000000000202'::uuid,'production:readiness',
  'production','changed','not-ready','not-bindable','critical',
  '["dependency-blocked"]'::jsonb,'[]'::jsonb,'[]'::jsonb,
  '["protected-operations"]'::jsonb,
  '47000000-0000-4000-8000-000000000102'::uuid,
  repeat('3',32),repeat('8',32),now()-interval '10 minutes',300,601,
  '{"current":{"privilegedOperationsMode":"blocked","workerOperationsMode":"blocked"}}'::jsonb,
  now()+interval '1 second'
);

do $stale$
declare
  pid uuid;
  s jsonb;
begin
  select proposal_id into pid
  from foundation.readiness_dependency_remediation_proposals
  order by proposal_sequence desc limit 1;

  s:=foundation.get_readiness_dependency_proposal_status_v1(pid);

  if s->>'state'<>'stale'
     or s->>'usable'<>'false' then
    raise exception 'old proposal must stale after condition change: %',s;
  end if;
end;
$stale$;

do $security$
begin
  if has_function_privilege(
    'foundation_runtime',
    'foundation.propose_readiness_dependency_remediation_v1(text,timestamptz)',
    'EXECUTE'
  ) then
    raise exception 'runtime must not generate readiness remediation proposals';
  end if;

  if not has_function_privilege(
    'service_role',
    'foundation.propose_readiness_dependency_remediation_v1(text,timestamptz)',
    'EXECUTE'
  ) then
    raise exception 'service_role must generate readiness remediation proposals';
  end if;

  if has_table_privilege(
    'service_role',
    'foundation.readiness_dependency_remediation_proposals',
    'INSERT'
  ) then
    raise exception 'service_role must not bypass proposal generator';
  end if;
end;
$security$;

rollback;
