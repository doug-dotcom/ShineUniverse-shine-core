begin;

-- Layer-74 source incident required by the synthetic Layer-76 receipts.
insert into foundation.foundation_promoted_release_case_audit_incident_events(
  event_id,incident_key,environment,domain,event_type,source_state,severity,
  reason_code,evidence_fingerprint,case_audit_observation_id,
  detection_started_at,persistence_threshold_seconds,persistence_seconds,
  snapshot,occurred_at,evidence_ref
)
values(
  '81000000-0000-4000-8000-000000000001'::uuid,
  'production:promoted_release_case_audit','production',
  'promoted_release_case_audit','opened','gap','critical',
  'promotion-case-audit-gap',repeat('a',64),null,
  now()-interval '20 minutes',300,900,'{"test":"layer81"}'::jsonb,
  now()-interval '15 minutes','test:layer81:case-audit-incident'
);

-- Durable Layer-73 evidence for the eligible Layer-76 receipt.
insert into foundation.foundation_promoted_release_case_audit_observations(
  observation_id,environment,audit_state,structural_integrity_pass,incident_state,
  active_incident_event_id,active_incident_handoff_state,case_count,invalid_count,
  active_case_count,pending_case_count,terminal_case_count,historical_case_count,
  semantic_fingerprint,changed_from_previous,snapshot,observed_at
)
values(
  '81000000-0000-4000-8000-000000000010'::uuid,
  'production','idle',true,'normal',null,'not-required',
  0,0,0,0,0,0,
  foundation.foundation_promoted_release_case_audit_semantic_fingerprint_v1(
    '{"overallState":"idle","test":"layer81"}'::jsonb
  ),
  false,'{"overallState":"idle","test":"layer81"}'::jsonb,
  now()-interval '12 minutes'
);

do $l81_seed_receipts$
declare
  fp text;
  action_result jsonb;
begin
  fp:=foundation.foundation_promoted_release_case_audit_semantic_fingerprint_v1(
    '{"overallState":"idle","test":"layer81"}'::jsonb
  );

  action_result:=jsonb_build_object(
    'foundationPromotedReleaseCaseAuditObservationRecord',
      'shine-foundation/promoted-release-case-audit-observation-record-v1',
    'schemaVersion','1.0.0',
    'environment','production',
    'status','recorded-heartbeat',
    'observationId','81000000-0000-4000-8000-000000000010',
    'semanticFingerprint',fp
  );

  -- Eligible overdue successful receipt.
  insert into foundation.case_audit_safe_response_exec_events(
    event_id,environment,incident_event_id,action_key,cause_class,
    policy_fingerprint,event_type,reason_code,decision_snapshot,
    incident_snapshot,before_snapshot,action_result,after_snapshot,requested_at
  )
  values(
    '81000000-0000-4000-8000-000000000101'::uuid,'production',
    '81000000-0000-4000-8000-000000000001'::uuid,
    'record-fresh-promotion-case-audit-observation','observer-freshness',
    repeat('1',64),'executed','test-layer81-overdue-executed',
    '{}'::jsonb,'{}'::jsonb,'{}'::jsonb,action_result,'{}'::jsonb,
    now()-interval '10 minutes'
  );

  -- Successful but still within the verification grace window.
  insert into foundation.case_audit_safe_response_exec_events(
    event_id,environment,incident_event_id,action_key,cause_class,
    policy_fingerprint,event_type,reason_code,decision_snapshot,
    incident_snapshot,before_snapshot,action_result,after_snapshot,requested_at
  )
  values(
    '81000000-0000-4000-8000-000000000102'::uuid,'production',
    '81000000-0000-4000-8000-000000000001'::uuid,
    'record-fresh-promotion-case-audit-observation','observer-freshness',
    repeat('2',64),'executed','test-layer81-pending-executed',
    '{}'::jsonb,'{}'::jsonb,'{}'::jsonb,action_result,'{}'::jsonb,
    now()-interval '1 minute'
  );

  -- A denied Layer-76 target can never be independently verified.
  insert into foundation.case_audit_safe_response_exec_events(
    event_id,environment,incident_event_id,action_key,cause_class,
    policy_fingerprint,event_type,reason_code,decision_snapshot,
    incident_snapshot,before_snapshot,requested_at
  )
  values(
    '81000000-0000-4000-8000-000000000103'::uuid,'production',
    '81000000-0000-4000-8000-000000000001'::uuid,
    'record-fresh-promotion-case-audit-observation','observer-freshness',
    repeat('3',64),'denied','test-layer81-denied-target',
    '{}'::jsonb,'{}'::jsonb,'{}'::jsonb,
    now()-interval '10 minutes'
  );
end;
$l81_seed_receipts$;


-- Seed the Layer-79 current incident from real Layer-78 coverage.
do $l81_seed_verification_incident$
declare
  coverage jsonb;
  event_id uuid := '81000000-0000-4000-8000-000000000201'::uuid;
begin
  coverage:=foundation.get_case_audit_safe_response_verification_coverage_v1(
    'production',now(),300,100
  );

  if coverage->>'state'<>'gap'
     or coverage->>'unverifiedCount'<>'1'
     or coverage->>'pendingCount'<>'1' then
    raise exception 'Layer 81 seed coverage invalid: %',coverage;
  end if;

  insert into foundation.case_audit_verify_incident_events(
    event_id,incident_key,environment,domain,event_type,source_state,severity,
    reason_code,evidence_fingerprint,detection_started_at,
    persistence_threshold_seconds,persistence_seconds,snapshot,occurred_at,
    evidence_ref
  )
  values(
    event_id,'production:case_audit_verification_coverage','production',
    'case_audit_verification_coverage','opened','gap','critical',
    coverage->>'reasonCode',
    foundation.case_audit_verify_incident_fingerprint_v1(coverage),
    now()-interval '10 minutes',300,600,coverage,
    now()-interval '1 minute','test:layer81:verification-incident'
  );
end;
$l81_seed_verification_incident$;


set local role service_role;

do $l81_execute$
declare
  r jsonb;
  replay jsonb;
  pending_result jsonb;
  denied_result jsonb;
  missing_result jsonb;
  summary jsonb;
  target_count_before bigint;
  target_count_after bigint;
  evidence_count_before bigint;
  evidence_count_after bigint;
begin
  if has_function_privilege(
       'service_role',
       'foundation.run_case_audit_safe_response_verification_v1(uuid,timestamptz)',
       'EXECUTE'
     ) then
    raise exception 'Layer 81 direct Layer-77 bypass still available';
  end if;

  if not has_function_privilege(
       'service_role',
       'foundation.execute_case_audit_overdue_verification_v1(uuid,text,timestamptz,integer)',
       'EXECUTE'
     ) then
    raise exception 'Layer 81 service-role executor unavailable';
  end if;

  select count(*) into target_count_before
  from foundation.case_audit_safe_response_exec_events;
  select count(*) into evidence_count_before
  from foundation.foundation_promoted_release_case_audit_observations;

  r:=foundation.execute_case_audit_overdue_verification_v1(
    '81000000-0000-4000-8000-000000000101'::uuid,
    'production',now(),300
  );

  if r->>'status'<>'executed'
     or r->>'reasonCode'<>'case-audit-overdue-verification-layer77-ran'
     or r#>>'{actionResult,status}'<>'recorded'
     or r#>>'{actionResult,verificationState}'<>'verified'
     or r->>'afterCoverageState'<>'pending'
     or r->>'boundedLayer77VerifierOnly'<>'true'
     or r->>'safeResponseRerunPerformed'<>'false'
     or r->>'evidenceMutationPerformed'<>'false'
     or r->>'verificationProofRewritePerformed'<>'false'
     or r->>'releaseTruthMutationPerformed'<>'false'
     or r->>'incidentHistoryMutationPerformed'<>'false' then
    raise exception 'Layer 81 eligible execution invalid: %',r;
  end if;

  if not exists(
    select 1
    from foundation.case_audit_safe_response_verifications
    where execution_event_id='81000000-0000-4000-8000-000000000101'::uuid
      and verification_state='verified'
  ) then
    raise exception 'Layer 81 did not persist Layer-77 verification proof';
  end if;

  replay:=foundation.execute_case_audit_overdue_verification_v1(
    '81000000-0000-4000-8000-000000000101'::uuid,
    'production',now(),300
  );

  if replay->>'status'<>'existing'
     or replay->>'eventId'<>r->>'eventId'
     or replay#>>'{actionResult,verificationState}'<>'verified' then
    raise exception 'Layer 81 replay did not preserve first execution: %',replay;
  end if;

  pending_result:=foundation.execute_case_audit_overdue_verification_v1(
    '81000000-0000-4000-8000-000000000102'::uuid,
    'production',now(),300
  );

  if pending_result->>'status'<>'denied'
     or pending_result->>'reasonCode'<>'case-audit-overdue-verification-within-grace' then
    raise exception 'Layer 81 grace enforcement invalid: %',pending_result;
  end if;

  denied_result:=foundation.execute_case_audit_overdue_verification_v1(
    '81000000-0000-4000-8000-000000000103'::uuid,
    'production',now(),300
  );

  if denied_result->>'status'<>'denied'
     or denied_result->>'reasonCode'<>'case-audit-overdue-verification-target-not-successful' then
    raise exception 'Layer 81 target event-type enforcement invalid: %',denied_result;
  end if;

  missing_result:=foundation.execute_case_audit_overdue_verification_v1(
    '81000000-0000-4000-8000-000000000999'::uuid,
    'production',now(),300
  );

  if missing_result->>'status'<>'not-applicable'
     or missing_result->>'reasonCode'<>'case-audit-overdue-verification-target-not-found' then
    raise exception 'Layer 81 missing target handling invalid: %',missing_result;
  end if;

  select count(*) into target_count_after
  from foundation.case_audit_safe_response_exec_events;
  select count(*) into evidence_count_after
  from foundation.foundation_promoted_release_case_audit_observations;

  if target_count_after<>target_count_before
     or evidence_count_after<>evidence_count_before then
    raise exception 'Layer 81 reran Layer 76 or mutated durable target evidence';
  end if;

  summary:=foundation.get_case_audit_verify_exec_summary_v1(
    'production',25
  );

  if summary->>'totalCount'<>'3'
     or summary->>'executedCount'<>'1'
     or summary->>'deniedCount'<>'2'
     or summary->>'failedCount'<>'0'
     or summary->>'directLayer77ServiceRoleBypassAllowed'<>'false'
     or summary->>'safeResponseRerunPerformed'<>'false'
     or summary->>'evidenceMutationPerformed'<>'false'
     or summary->>'verificationProofRewritePerformed'<>'false'
     or summary->>'releaseTruthMutationPerformed'<>'false'
     or summary->>'incidentHistoryMutationPerformed'<>'false' then
    raise exception 'Layer 81 executor summary invalid: %',summary;
  end if;
end;
$l81_execute$;

reset role;


do $l81_privileges$
begin
  if has_function_privilege(
       'foundation_runtime',
       'foundation.execute_case_audit_overdue_verification_v1(uuid,text,timestamptz,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'foundation_gateway',
       'foundation.execute_case_audit_overdue_verification_v1(uuid,text,timestamptz,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'shine_core_control_plane',
       'foundation.execute_case_audit_overdue_verification_v1(uuid,text,timestamptz,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'shine_defence_runtime',
       'foundation.execute_case_audit_overdue_verification_v1(uuid,text,timestamptz,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'anon',
       'foundation.execute_case_audit_overdue_verification_v1(uuid,text,timestamptz,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'authenticated',
       'foundation.execute_case_audit_overdue_verification_v1(uuid,text,timestamptz,integer)',
       'EXECUTE'
     )
     or has_table_privilege(
       'service_role',
       'foundation.case_audit_verify_exec_events',
       'INSERT'
     )
     or not has_function_privilege(
       'foundation_runtime',
       'foundation.get_case_audit_verify_exec_summary_v1(text,integer)',
       'EXECUTE'
     )
     or not has_function_privilege(
       'foundation_gateway',
       'foundation.get_case_audit_verify_exec_summary_v1(text,integer)',
       'EXECUTE'
     )
     or not pg_has_role(
       'foundation_gateway','foundation_runtime','MEMBER'
     )
     or exists(
       select 1
       from pg_proc p
       join pg_namespace n on n.oid=p.pronamespace
       cross join lateral aclexplode(
         coalesce(p.proacl,acldefault('f',p.proowner))
       ) a
       join pg_roles r on r.oid=a.grantee
       where n.nspname='foundation'
         and p.proname='get_case_audit_verify_exec_summary_v1'
         and r.rolname='foundation_gateway'
         and a.privilege_type='EXECUTE'
     )
     or has_function_privilege(
       'shine_core_control_plane',
       'foundation.get_case_audit_verify_exec_summary_v1(text,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'shine_defence_runtime',
       'foundation.get_case_audit_verify_exec_summary_v1(text,integer)',
       'EXECUTE'
     ) then
    raise exception 'Layer 81 privilege boundary invalid';
  end if;
end;
$l81_privileges$;


do $l81_append_only$
declare
  id uuid;
begin
  select event_id into id
  from foundation.case_audit_verify_exec_events
  where event_type='executed'
  limit 1;

  begin
    update foundation.case_audit_verify_exec_events
    set reason_code='mutation'
    where event_id=id;
    raise exception 'Layer 81 executor history unexpectedly mutated';
  exception when sqlstate '55000' then
    null;
  end;
end;
$l81_append_only$;

rollback;
