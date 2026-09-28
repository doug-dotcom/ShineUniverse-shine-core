begin;

do $layer38_baseline$
declare
  v_health jsonb;
  v_inspect jsonb;
  v_repair jsonb;
  v_auto jsonb;
  v_delete jsonb;
begin
  select foundation.get_control_plane_incident_response_policy_health_v1('production')
    into v_health;

  if v_health->>'state' <> 'pass'
     or v_health->>'activeActionCount' <> '11'
     or v_health->>'expectedPolicyCount' <> '44'
     or v_health->>'currentPolicyCount' <> '44'
     or v_health->>'authorityExpansionCount' <> '0'
     or v_health->>'historyMutationNotDeniedCount' <> '0'
     or v_health->>'autoRepairNotDeniedCount' <> '0' then
    raise exception 'Layer 38 policy coverage must be complete and fail-closed: %',v_health;
  end if;

  select foundation.evaluate_control_plane_incident_response_v1(
    'inspect-projection-evidence','production'
  ) into v_inspect;

  if v_inspect->>'incidentState' <> 'normal'
     or v_inspect->>'decision' <> 'admit'
     or v_inspect->>'requiredControl' <> 'read-only'
     or v_inspect->>'authorityExpansion' <> 'false' then
    raise exception 'Normal state should admit read-only inspection: %',v_inspect;
  end if;

  select foundation.evaluate_control_plane_incident_response_v1(
    'apply-registry-repair','production'
  ) into v_repair;

  if v_repair->>'decision' <> 'deny'
     or v_repair->>'requiredControl' <> 'prohibited'
     or v_repair->>'mutatesAuthoritativeTruth' <> 'true' then
    raise exception 'Normal state must deny authoritative registry repair: %',v_repair;
  end if;

  select foundation.evaluate_control_plane_incident_response_v1(
    'auto-repair-authoritative-truth','production'
  ) into v_auto;

  if v_auto->>'decision' <> 'deny' then
    raise exception 'Automatic authoritative repair must always be denied: %',v_auto;
  end if;

  select foundation.evaluate_control_plane_incident_response_v1(
    'delete-control-plane-incident-history','production'
  ) into v_delete;

  if v_delete->>'decision' <> 'deny'
     or v_delete->>'mutatesIncidentHistory' <> 'true' then
    raise exception 'Incident history deletion must always be denied: %',v_delete;
  end if;
end;
$layer38_baseline$;


insert into foundation.foundation_release_projection_observations(
  observation_id,environment,reconciliation_state,evidence_fingerprint,
  reason_codes,snapshot,observed_at,recorded_at
)
values (
  '38000000-0000-4000-8000-000000000001'::uuid,
  'production','unknown',repeat('1',32),
  '["release-identity-health-unknown"]'::jsonb,
  jsonb_build_object(
    'foundationReleaseProjectionHealthResponse',
      'shine-foundation/release-projection-health-response-v1',
    'schemaVersion','1.0.0',
    'environment','production',
    'state','unknown',
    'reasonCodes',jsonb_build_array('release-identity-health-unknown'),
    'evidenceFingerprint',repeat('1',32)
  ),
  now()+interval '1 second',
  now()+interval '1 second'
);

insert into foundation.foundation_control_plane_incident_events(
  event_id,incident_key,environment,domain,event_type,source_state,severity,
  reason_codes,evidence_fingerprint,projection_observation_id,
  detection_started_at,persistence_threshold_seconds,persistence_seconds,
  snapshot,occurred_at,evidence_ref
)
values (
  '38000000-0000-4000-8000-000000000101'::uuid,
  'production:release_projection','production','release_projection',
  'detected','unknown','warning',
  '["release-identity-health-unknown"]'::jsonb,
  repeat('1',32),
  '38000000-0000-4000-8000-000000000001'::uuid,
  now()+interval '1 second',
  300,0,
  (select snapshot from foundation.foundation_release_projection_observations
   where observation_id='38000000-0000-4000-8000-000000000001'::uuid),
  now()+interval '1 second',
  'test:layer38:watch'
);

do $layer38_watching$
declare
  v_collect jsonb;
  v_propose jsonb;
  v_apply jsonb;
begin
  select foundation.evaluate_control_plane_incident_response_v1(
    'collect-fresh-evidence','production'
  ) into v_collect;

  if v_collect->>'incidentState' <> 'watching'
     or v_collect->>'decision' <> 'admit'
     or v_collect->>'requiredControl' <> 'evidence-only' then
    raise exception 'Watch state should admit fresh evidence collection: %',v_collect;
  end if;

  select foundation.evaluate_control_plane_incident_response_v1(
    'propose-registry-repair','production'
  ) into v_propose;

  if v_propose->>'decision' <> 'not-applicable' then
    raise exception 'Transient watch should not yet make repair proposal applicable: %',v_propose;
  end if;

  select foundation.evaluate_control_plane_incident_response_v1(
    'apply-registry-repair','production'
  ) into v_apply;

  if v_apply->>'decision' <> 'deny' then
    raise exception 'Transient watch must deny authoritative repair: %',v_apply;
  end if;
end;
$layer38_watching$;


insert into foundation.foundation_control_plane_incident_events(
  event_id,incident_key,environment,domain,event_type,source_state,severity,
  reason_codes,evidence_fingerprint,projection_observation_id,
  detection_started_at,persistence_threshold_seconds,persistence_seconds,
  snapshot,occurred_at,evidence_ref
)
values (
  '38000000-0000-4000-8000-000000000102'::uuid,
  'production:release_projection','production','release_projection',
  'opened','unknown','warning',
  '["release-identity-health-unknown"]'::jsonb,
  repeat('1',32),
  '38000000-0000-4000-8000-000000000001'::uuid,
  now()+interval '1 second',
  300,300,
  (select snapshot from foundation.foundation_release_projection_observations
   where observation_id='38000000-0000-4000-8000-000000000001'::uuid),
  now()+interval '301 seconds',
  'test:layer38:warning'
);

do $layer38_warning$
declare
  v_reattest jsonb;
  v_propose jsonb;
  v_apply jsonb;
  v_auto jsonb;
  v_plan jsonb;
begin
  select foundation.evaluate_control_plane_incident_response_v1(
    'request-release-reattestation','production'
  ) into v_reattest;

  if v_reattest->>'incidentState' <> 'warning'
     or v_reattest->>'decision' <> 'admit'
     or v_reattest->>'requiredControl' <> 'evidence-only' then
    raise exception 'Warning incident should admit re-attestation request: %',v_reattest;
  end if;

  select foundation.evaluate_control_plane_incident_response_v1(
    'propose-registry-repair','production'
  ) into v_propose;

  if v_propose->>'decision' <> 'admit'
     or v_propose->>'requiredControl' <> 'operator-proposal' then
    raise exception 'Warning incident should admit repair proposal only: %',v_propose;
  end if;

  select foundation.evaluate_control_plane_incident_response_v1(
    'apply-registry-repair','production'
  ) into v_apply;

  if v_apply->>'decision' <> 'approval-required'
     or v_apply->>'requiredControl' <> 'external-approval'
     or v_apply->>'authorityExpansion' <> 'false' then
    raise exception 'Warning incident must require external approval for mutation: %',v_apply;
  end if;

  select foundation.evaluate_control_plane_incident_response_v1(
    'auto-repair-authoritative-truth','production'
  ) into v_auto;

  if v_auto->>'decision' <> 'deny' then
    raise exception 'Warning incident must not enable automatic repair: %',v_auto;
  end if;

  select foundation.get_control_plane_incident_response_plan_v1('production')
    into v_plan;

  if v_plan->>'incidentState' <> 'warning'
     or v_plan->>'authorityExpansion' <> 'false'
     or v_plan->>'automaticRepairAllowed' <> 'false'
     or jsonb_array_length(v_plan->'actions') <> 11 then
    raise exception 'Warning response plan must expose complete non-executing policy: %',v_plan;
  end if;
end;
$layer38_warning$;


insert into foundation.foundation_release_projection_observations(
  observation_id,environment,reconciliation_state,evidence_fingerprint,
  reason_codes,snapshot,observed_at,recorded_at
)
values (
  '38000000-0000-4000-8000-000000000002'::uuid,
  'production','fail',repeat('2',32),
  '["registry-release-ref-mismatch"]'::jsonb,
  jsonb_build_object(
    'foundationReleaseProjectionHealthResponse',
      'shine-foundation/release-projection-health-response-v1',
    'schemaVersion','1.0.0',
    'environment','production',
    'state','fail',
    'reasonCodes',jsonb_build_array('registry-release-ref-mismatch'),
    'evidenceFingerprint',repeat('2',32)
  ),
  now()+interval '360 seconds',
  now()+interval '360 seconds'
);

insert into foundation.foundation_control_plane_incident_events(
  event_id,incident_key,environment,domain,event_type,source_state,severity,
  reason_codes,evidence_fingerprint,projection_observation_id,
  detection_started_at,persistence_threshold_seconds,persistence_seconds,
  snapshot,occurred_at,evidence_ref
)
values (
  '38000000-0000-4000-8000-000000000103'::uuid,
  'production:release_projection','production','release_projection',
  'changed','fail','critical',
  '["registry-release-ref-mismatch"]'::jsonb,
  repeat('2',32),
  '38000000-0000-4000-8000-000000000002'::uuid,
  now()+interval '1 second',
  300,359,
  (select snapshot from foundation.foundation_release_projection_observations
   where observation_id='38000000-0000-4000-8000-000000000002'::uuid),
  now()+interval '360 seconds',
  'test:layer38:critical'
);

do $layer38_critical$
declare
  v_apply_registry jsonb;
  v_apply_ledger jsonb;
  v_rebind jsonb;
  v_suppress jsonb;
  v_delete jsonb;
begin
  select foundation.evaluate_control_plane_incident_response_v1(
    'apply-registry-repair','production'
  ) into v_apply_registry;

  select foundation.evaluate_control_plane_incident_response_v1(
    'apply-release-ledger-repair','production'
  ) into v_apply_ledger;

  select foundation.evaluate_control_plane_incident_response_v1(
    'rebind-release-identity','production'
  ) into v_rebind;

  if v_apply_registry->>'incidentState' <> 'critical'
     or v_apply_registry->>'decision' <> 'approval-required'
     or v_apply_ledger->>'decision' <> 'approval-required'
     or v_rebind->>'decision' <> 'approval-required' then
    raise exception 'Critical incident may require repair, but must not auto-admit mutation: %, %, %',
      v_apply_registry,v_apply_ledger,v_rebind;
  end if;

  select foundation.evaluate_control_plane_incident_response_v1(
    'suppress-control-plane-incident','production'
  ) into v_suppress;

  select foundation.evaluate_control_plane_incident_response_v1(
    'delete-control-plane-incident-history','production'
  ) into v_delete;

  if v_suppress->>'decision' <> 'deny'
     or v_delete->>'decision' <> 'deny' then
    raise exception 'Critical severity must not permit hiding incident history: %, %',
      v_suppress,v_delete;
  end if;
end;
$layer38_critical$;


do $layer38_unknown_action$
declare
  v jsonb;
begin
  select foundation.evaluate_control_plane_incident_response_v1(
    'invented-repair-action','production'
  ) into v;

  if v->>'decision' <> 'deny'
     or v->>'reasonCode' <> 'response-action-not-registered' then
    raise exception 'Unknown response actions must fail closed: %',v;
  end if;
end;
$layer38_unknown_action$;


do $layer38_security$
begin
  if not has_function_privilege(
    'foundation_runtime',
    'foundation.evaluate_control_plane_incident_response_v1(text,text)',
    'EXECUTE'
  ) then
    raise exception 'foundation_runtime must evaluate incident response policy';
  end if;

  if not has_function_privilege(
    'foundation_runtime',
    'foundation.get_control_plane_incident_response_plan_v1(text)',
    'EXECUTE'
  ) then
    raise exception 'foundation_runtime must read incident response plan';
  end if;

  if has_table_privilege(
    'foundation_runtime',
    'foundation.control_plane_incident_response_policies',
    'INSERT'
  ) or has_table_privilege(
    'foundation_runtime',
    'foundation.control_plane_incident_response_actions',
    'INSERT'
  ) then
    raise exception 'foundation_runtime must not mutate response policy/catalogue';
  end if;

  if has_function_privilege(
    'anon',
    'foundation.evaluate_control_plane_incident_response_v1(text,text)',
    'EXECUTE'
  ) or has_function_privilege(
    'authenticated',
    'foundation.evaluate_control_plane_incident_response_v1(text,text)',
    'EXECUTE'
  ) then
    raise exception 'public API roles must not evaluate internal incident response policy';
  end if;
end;
$layer38_security$;

rollback;
