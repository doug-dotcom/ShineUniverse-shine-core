begin;

insert into foundation.foundation_promoted_release_case_audit_incident_events(
  event_id,incident_key,environment,domain,event_type,source_state,severity,
  reason_code,evidence_fingerprint,case_audit_observation_id,
  detection_started_at,persistence_threshold_seconds,persistence_seconds,
  snapshot,occurred_at,evidence_ref
)
values(
  '87000000-0000-4000-8000-000000000001'::uuid,
  'production:promoted_release_case_audit','production',
  'promoted_release_case_audit','opened','gap','critical',
  'promotion-case-audit-gap',repeat('a',64),null,
  now()-interval '30 minutes',300,1200,'{"test":"layer87"}'::jsonb,
  now()-interval '20 minutes','test:layer87:case-audit-incident'
);

insert into foundation.foundation_promoted_release_case_audit_observations(
  observation_id,environment,audit_state,structural_integrity_pass,incident_state,
  active_incident_event_id,active_incident_handoff_state,case_count,invalid_count,
  active_case_count,pending_case_count,terminal_case_count,historical_case_count,
  semantic_fingerprint,changed_from_previous,snapshot,observed_at
)
values(
  '87000000-0000-4000-8000-000000000010'::uuid,
  'production','idle',true,'normal',null,'not-required',0,0,0,0,0,0,
  foundation.foundation_promoted_release_case_audit_semantic_fingerprint_v1(
    '{"overallState":"idle","test":"layer87"}'::jsonb
  ),false,'{"overallState":"idle","test":"layer87"}'::jsonb,
  now()-interval '15 minutes'
);

insert into foundation.case_audit_verify_incident_events(
  event_id,incident_key,environment,domain,event_type,source_state,severity,
  reason_code,evidence_fingerprint,detection_started_at,
  persistence_threshold_seconds,persistence_seconds,snapshot,occurred_at,
  evidence_ref
)
values(
  '87000000-0000-4000-8000-000000000201'::uuid,
  'production:case_audit_verification_coverage','production',
  'case_audit_verification_coverage','opened','gap','critical',
  'case-audit-safe-response-verification-overdue',repeat('9',64),
  now()-interval '15 minutes',300,600,'{"test":"layer87"}'::jsonb,
  now()-interval '8 minutes','test:layer87:verification-incident'
);

do $l87_seed_layer76$
declare fp text; action_result jsonb;
begin
  fp:=foundation.foundation_promoted_release_case_audit_semantic_fingerprint_v1(
    '{"overallState":"idle","test":"layer87"}'::jsonb
  );
  action_result:=jsonb_build_object(
    'foundationPromotedReleaseCaseAuditObservationRecord',
      'shine-foundation/promoted-release-case-audit-observation-record-v1',
    'schemaVersion','1.0.0','environment','production',
    'status','recorded-heartbeat',
    'observationId','87000000-0000-4000-8000-000000000010',
    'semanticFingerprint',fp
  );
  insert into foundation.case_audit_safe_response_exec_events(
    event_id,environment,incident_event_id,action_key,cause_class,
    policy_fingerprint,event_type,reason_code,decision_snapshot,
    incident_snapshot,before_snapshot,action_result,after_snapshot,requested_at
  ) values(
    '87000000-0000-4000-8000-000000000101'::uuid,'production',
    '87000000-0000-4000-8000-000000000001'::uuid,
    'record-fresh-promotion-case-audit-observation','observer-freshness',
    repeat('1',64),'executed','test-layer87-target-executed',
    '{}'::jsonb,'{}'::jsonb,'{}'::jsonb,action_result,'{}'::jsonb,
    now()-interval '15 minutes'
  );
end;
$l87_seed_layer76$;

do $l87_real_layer77$
declare r jsonb;
begin
  r:=foundation.run_case_audit_safe_response_verification_v1(
    '87000000-0000-4000-8000-000000000101'::uuid,now()
  );
  if r->>'status'<>'recorded' or r->>'verificationState'<>'verified' then
    raise exception 'Layer 87 seed Layer-77 proof invalid: %',r;
  end if;
end;
$l87_real_layer77$;

do $l87_seed_layer81$
declare
  decision jsonb; incident_snapshot jsonb; before_coverage jsonb;
  target foundation.case_audit_safe_response_exec_events%rowtype;
  verification foundation.case_audit_safe_response_verifications%rowtype;
  target_snapshot jsonb; action_result jsonb; policy_fp text;
begin
  select * into target from foundation.case_audit_safe_response_exec_events
  where event_id='87000000-0000-4000-8000-000000000101'::uuid;
  select * into verification from foundation.case_audit_safe_response_verifications
  where execution_event_id=target.event_id;

  decision:=jsonb_build_object(
    'foundationCaseAuditVerificationIncidentResponseDecision',
      'shine-foundation/case-audit-verification-incident-response-decision-v1',
    'schemaVersion','1.0.0','environment','production','incidentState','critical',
    'causeClass','verification-omission','actionKey','run-independent-verification',
    'actionClass','evidence','decision','admit',
    'requiredControl','layer-77-bounded-verifier',
    'reasonCode','case-audit-verification-response-run-bounded-verification',
    'authorityExpansion',false,'automaticVerificationAllowed',false,
    'automaticRepairAllowed',false,'verificationProofRewriteAllowed',false,
    'historyRewriteAllowed',false,'mutatesAuthoritativeTruth',false,
    'mutatesIncidentHistory',false,'mutatesVerificationProof',false,
    'rerunsSafeResponse',false,'executesAction',false
  );

  incident_snapshot:=jsonb_build_object(
    'state','critical','currentEvent',jsonb_build_object(
      'eventId','87000000-0000-4000-8000-000000000201',
      'eventType','opened','sourceState','gap',
      'evidenceFingerprint',repeat('9',64)
    )
  );

  before_coverage:=foundation.get_case_audit_safe_response_verification_coverage_v1(
    'production',now(),300,100
  );

  target_snapshot:=jsonb_build_object(
    'executionEventId',target.event_id,'incidentEventId',target.incident_event_id,
    'actionKey',target.action_key,'executionPolicyFingerprint',target.policy_fingerprint,
    'executionEventType',target.event_type,'executionRequestedAt',target.requested_at,
    'executionAgeSeconds',900,'verificationGraceSeconds',300,
    'verificationId',null,'verificationState',null,'verificationAbsent',true
  );

  action_result:=jsonb_build_object(
    'foundationCaseAuditSafeResponseVerification',
      'shine-foundation/case-audit-safe-response-verification-response-v1',
    'schemaVersion','1.0.0','status','recorded',
    'verificationId',verification.verification_id,
    'executionEventId',verification.execution_event_id,
    'verificationState',verification.verification_state,
    'reasonCode',verification.reason_code,
    'durableEvidenceId',verification.durable_evidence_id,
    'durableEvidenceFingerprint',verification.durable_evidence_fingerprint,
    'verificationProofSha256',verification.verification_proof_sha256,
    'targetReexecuted',false,'mutationPerformed',false
  );

  policy_fp:=foundation.case_audit_verify_exec_policy_fp_v1(
    decision,incident_snapshot,target_snapshot
  );

  insert into foundation.case_audit_verify_exec_events(
    event_id,environment,target_execution_event_id,verification_incident_event_id,
    action_key,cause_class,policy_fingerprint,event_type,reason_code,
    decision_snapshot,incident_snapshot,target_snapshot,before_coverage,
    action_result,after_coverage,requested_at
  ) values(
    '87000000-0000-4000-8000-000000000301'::uuid,'production',target.event_id,
    '87000000-0000-4000-8000-000000000201'::uuid,
    'run-independent-verification','verification-omission',policy_fp,'executed',
    'case-audit-overdue-verification-layer77-ran',decision,incident_snapshot,
    target_snapshot,before_coverage,action_result,before_coverage,
    now()-interval '10 minutes'
  );
end;
$l87_seed_layer81$;

do $l87_seed_reconciliation_incident$
declare coverage jsonb;
begin
  coverage:=foundation.get_case_audit_verify_reconcile_coverage_v1(
    'production',now(),300,100
  );
  if coverage->>'state'<>'gap' or coverage->>'overdueCount'<>'1' then
    raise exception 'Layer 87 seed reconciliation coverage invalid: %',coverage;
  end if;
  insert into foundation.case_audit_verify_reconcile_incident_events(
    event_id,incident_key,environment,domain,event_type,source_state,severity,
    reason_code,evidence_fingerprint,detection_started_at,
    persistence_threshold_seconds,persistence_seconds,snapshot,occurred_at,evidence_ref
  ) values(
    '87000000-0000-4000-8000-000000000401'::uuid,
    'production:case_audit_verification_reconciliation_coverage','production',
    'case_audit_verification_reconciliation_coverage','opened','gap','critical',
    coverage->>'reasonCode',
    foundation.case_audit_verify_reconcile_incident_fingerprint_v1(coverage),
    now()-interval '10 minutes',300,600,coverage,now()-interval '1 minute',
    'test:layer87:reconciliation-incident'
  );
end;
$l87_seed_reconciliation_incident$;

set local role service_role;
do $l87_real_layer86$
declare r jsonb;
begin
  r:=foundation.execute_case_audit_overdue_reconciliation_v1(
    '87000000-0000-4000-8000-000000000301'::uuid,'production',now(),300,300
  );
  if r->>'status'<>'executed'
     or r#>>'{actionResult,reconciliationState}'<>'reconciled' then
    raise exception 'Layer 87 seed Layer-86 execution invalid: %',r;
  end if;
end;
$l87_real_layer86$;
reset role;

set local role service_role;
do $l87_verify$
declare
  exec_id uuid; r jsonb; replay jsonb; e jsonb; s jsonb;
  layer82_before bigint; layer82_after bigint;
  layer81_before bigint; layer81_after bigint;
  layer77_before bigint; layer77_after bigint;
begin
  select event_id into exec_id
  from foundation.case_audit_verify_reconcile_exec_events
  where target_executor_event_id='87000000-0000-4000-8000-000000000301'::uuid
    and event_type='executed';

  select count(*) into layer82_before from foundation.case_audit_verify_exec_reconciliations;
  select count(*) into layer81_before from foundation.case_audit_verify_exec_events;
  select count(*) into layer77_before from foundation.case_audit_safe_response_verifications;

  r:=foundation.run_case_audit_reconcile_exec_verification_v1(exec_id,now());
  if r->>'status'<>'recorded'
     or r->>'verificationState'<>'verified'
     or r->>'reasonCode'<>'case-audit-reconcile-exec-verify-complete'
     or r->>'layer82RerunPerformed'<>'false'
     or r->>'layer81RerunPerformed'<>'false'
     or r->>'verificationRerunPerformed'<>'false'
     or r->>'mutationPerformed'<>'false' then
    raise exception 'Layer 87 verified result invalid: %',r;
  end if;

  e:=foundation.evaluate_case_audit_reconcile_exec_verification_v1(exec_id,now());
  if e->>'verificationState'<>'verified'
     or e->>'policyIntegrityValid'<>'true'
     or e->>'targetSnapshotMatches'<>'true'
     or e->>'incidentSnapshotMatches'<>'true'
     or e->>'reconciliationProofIntegrityValid'<>'true'
     or e->>'receiptMatchesReconciliation'<>'true' then
    raise exception 'Layer 87 evaluator invalid: %',e;
  end if;

  replay:=foundation.run_case_audit_reconcile_exec_verification_v1(exec_id,now());
  if replay->>'status'<>'existing'
     or replay->>'verificationId'<>r->>'verificationId'
     or replay->>'verificationState'<>'verified' then
    raise exception 'Layer 87 replay invalid: %',replay;
  end if;

  select count(*) into layer82_after from foundation.case_audit_verify_exec_reconciliations;
  select count(*) into layer81_after from foundation.case_audit_verify_exec_events;
  select count(*) into layer77_after from foundation.case_audit_safe_response_verifications;
  if layer82_after<>layer82_before or layer81_after<>layer81_before
     or layer77_after<>layer77_before then
    raise exception 'Layer 87 unexpectedly reran upstream controls';
  end if;

  s:=foundation.get_case_audit_reconcile_exec_verification_summary_v1('production',25);
  if s->>'totalCount'<>'1' or s->>'verifiedCount'<>'1'
     or s->>'problemCount'<>'0' or s->>'mutationPerformed'<>'false' then
    raise exception 'Layer 87 summary invalid: %',s;
  end if;
end;
$l87_verify$;
reset role;

do $l87_nonexecuted$
declare source_event foundation.case_audit_verify_reconcile_exec_events%rowtype; e jsonb;
begin
  select * into source_event from foundation.case_audit_verify_reconcile_exec_events
  where event_type='executed' limit 1;
  insert into foundation.case_audit_verify_reconcile_exec_events(
    event_id,environment,target_executor_event_id,reconciliation_incident_event_id,
    action_key,cause_class,policy_fingerprint,event_type,reason_code,
    decision_snapshot,incident_snapshot,target_snapshot,before_coverage,requested_at
  ) values(
    '87000000-0000-4000-8000-000000000602'::uuid,
    source_event.environment,source_event.target_executor_event_id,
    source_event.reconciliation_incident_event_id,source_event.action_key,
    source_event.cause_class,source_event.policy_fingerprint,'denied',
    'case-audit-overdue-reconciliation-policy-not-admitted',
    source_event.decision_snapshot,source_event.incident_snapshot,
    source_event.target_snapshot,source_event.before_coverage,now()
  );
  e:=foundation.evaluate_case_audit_reconcile_exec_verification_v1(
    '87000000-0000-4000-8000-000000000602'::uuid,now()
  );
  if e->>'status'<>'not-applicable'
     or e->>'reasonCode'<>'case-audit-reconcile-exec-verify-source-not-executed' then
    raise exception 'Layer 87 non-executed handling invalid: %',e;
  end if;
end;
$l87_nonexecuted$;

do $l87_mismatch_cases$
declare source_event foundation.case_audit_verify_reconcile_exec_events%rowtype;
  bad_receipt jsonb; e jsonb;
begin
  select * into source_event from foundation.case_audit_verify_reconcile_exec_events
  where event_type='executed' limit 1;
  drop index foundation.case_audit_verify_reconcile_exec_target_once_idx;

  insert into foundation.case_audit_verify_reconcile_exec_events(
    event_id,environment,target_executor_event_id,reconciliation_incident_event_id,
    action_key,cause_class,policy_fingerprint,event_type,reason_code,
    decision_snapshot,incident_snapshot,target_snapshot,before_coverage,
    action_result,after_coverage,requested_at
  ) values(
    '87000000-0000-4000-8000-000000000603'::uuid,
    source_event.environment,source_event.target_executor_event_id,
    source_event.reconciliation_incident_event_id,source_event.action_key,
    source_event.cause_class,repeat('f',64),'executed',source_event.reason_code,
    source_event.decision_snapshot,source_event.incident_snapshot,
    source_event.target_snapshot,source_event.before_coverage,
    source_event.action_result,source_event.after_coverage,now()
  );
  e:=foundation.evaluate_case_audit_reconcile_exec_verification_v1(
    '87000000-0000-4000-8000-000000000603'::uuid,now()
  );
  if e->>'verificationState'<>'policy-mismatch'
     or e->>'policyIntegrityValid'<>'false' then
    raise exception 'Layer 87 policy mismatch invalid: %',e;
  end if;

  bad_receipt:=jsonb_set(
    source_event.action_result,'{reconciliationState}',to_jsonb('missing-proof'::text)
  );
  insert into foundation.case_audit_verify_reconcile_exec_events(
    event_id,environment,target_executor_event_id,reconciliation_incident_event_id,
    action_key,cause_class,policy_fingerprint,event_type,reason_code,
    decision_snapshot,incident_snapshot,target_snapshot,before_coverage,
    action_result,after_coverage,requested_at
  ) values(
    '87000000-0000-4000-8000-000000000604'::uuid,
    source_event.environment,source_event.target_executor_event_id,
    source_event.reconciliation_incident_event_id,source_event.action_key,
    source_event.cause_class,source_event.policy_fingerprint,'executed',
    source_event.reason_code,source_event.decision_snapshot,
    source_event.incident_snapshot,source_event.target_snapshot,
    source_event.before_coverage,bad_receipt,source_event.after_coverage,now()
  );
  e:=foundation.evaluate_case_audit_reconcile_exec_verification_v1(
    '87000000-0000-4000-8000-000000000604'::uuid,now()
  );
  if e->>'verificationState'<>'receipt-mismatch'
     or e->>'receiptMatchesReconciliation'<>'false' then
    raise exception 'Layer 87 receipt mismatch invalid: %',e;
  end if;
end;
$l87_mismatch_cases$;

do $l87_missing_reconciliation$
declare
  source_target foundation.case_audit_verify_exec_events%rowtype;
  source_exec foundation.case_audit_verify_reconcile_exec_events%rowtype; e jsonb;
begin
  -- Test-only: allow a second successful Layer-81 event for the same Layer-76
  -- target so Layer 87 can prove it detects a Layer-86 success claim whose exact
  -- Layer-81 event has no Layer-82 receipt. Transaction rollback restores the
  -- production uniqueness invariant.
  drop index foundation.case_audit_verify_exec_target_once_idx;

  select * into source_target from foundation.case_audit_verify_exec_events
  where event_id='87000000-0000-4000-8000-000000000301'::uuid;

  insert into foundation.case_audit_verify_exec_events(
    event_id,environment,target_execution_event_id,verification_incident_event_id,
    action_key,cause_class,policy_fingerprint,event_type,reason_code,
    decision_snapshot,incident_snapshot,target_snapshot,before_coverage,
    action_result,after_coverage,requested_at
  ) values(
    '87000000-0000-4000-8000-000000000399'::uuid,
    source_target.environment,source_target.target_execution_event_id,
    source_target.verification_incident_event_id,source_target.action_key,
    source_target.cause_class,source_target.policy_fingerprint,'executed',
    source_target.reason_code,source_target.decision_snapshot,
    source_target.incident_snapshot,source_target.target_snapshot,
    source_target.before_coverage,source_target.action_result,
    source_target.after_coverage,now()
  );

  select * into source_exec from foundation.case_audit_verify_reconcile_exec_events
  where event_type='executed' limit 1;

  insert into foundation.case_audit_verify_reconcile_exec_events(
    event_id,environment,target_executor_event_id,reconciliation_incident_event_id,
    action_key,cause_class,policy_fingerprint,event_type,reason_code,
    decision_snapshot,incident_snapshot,target_snapshot,before_coverage,
    action_result,after_coverage,requested_at
  ) values(
    '87000000-0000-4000-8000-000000000605'::uuid,source_exec.environment,
    '87000000-0000-4000-8000-000000000399'::uuid,
    source_exec.reconciliation_incident_event_id,source_exec.action_key,
    source_exec.cause_class,source_exec.policy_fingerprint,'executed',
    source_exec.reason_code,source_exec.decision_snapshot,
    source_exec.incident_snapshot,
    jsonb_set(source_exec.target_snapshot,'{executorEventId}',
      to_jsonb('87000000-0000-4000-8000-000000000399'::uuid)),
    source_exec.before_coverage,source_exec.action_result,
    source_exec.after_coverage,now()
  );
  e:=foundation.evaluate_case_audit_reconcile_exec_verification_v1(
    '87000000-0000-4000-8000-000000000605'::uuid,now()
  );
  if e->>'verificationState'<>'missing-reconciliation'
     or e->>'reconciliationId' is not null then
    raise exception 'Layer 87 missing reconciliation invalid: %',e;
  end if;
end;
$l87_missing_reconciliation$;

do $l87_invalid_reconciliation_proof$
declare exec_id uuid; rid uuid; e jsonb;
begin
  select x.event_id,r.reconciliation_id into exec_id,rid
  from foundation.case_audit_verify_reconcile_exec_events x
  join foundation.case_audit_verify_exec_reconciliations r
    on r.executor_event_id=x.target_executor_event_id
  where x.event_type='executed'
    and x.event_id not in (
      '87000000-0000-4000-8000-000000000603'::uuid,
      '87000000-0000-4000-8000-000000000604'::uuid,
      '87000000-0000-4000-8000-000000000605'::uuid
    ) limit 1;

  alter table foundation.case_audit_verify_exec_reconciliations
    disable trigger case_audit_verify_reconcile_append_only;
  update foundation.case_audit_verify_exec_reconciliations
  set reconciliation_proof_sha256=repeat('f',64)
  where reconciliation_id=rid;

  e:=foundation.evaluate_case_audit_reconcile_exec_verification_v1(exec_id,now());
  if e->>'verificationState'<>'invalid-reconciliation-proof'
     or e->>'reconciliationProofIntegrityValid'<>'false' then
    raise exception 'Layer 87 invalid reconciliation proof invalid: %',e;
  end if;
end;
$l87_invalid_reconciliation_proof$;

do $l87_privileges$
begin
  if not has_function_privilege('service_role',
       'foundation.run_case_audit_reconcile_exec_verification_v1(uuid,timestamptz)','EXECUTE')
     or has_function_privilege('foundation_runtime',
       'foundation.run_case_audit_reconcile_exec_verification_v1(uuid,timestamptz)','EXECUTE')
     or has_function_privilege('foundation_gateway',
       'foundation.run_case_audit_reconcile_exec_verification_v1(uuid,timestamptz)','EXECUTE')
     or has_function_privilege('shine_core_control_plane',
       'foundation.run_case_audit_reconcile_exec_verification_v1(uuid,timestamptz)','EXECUTE')
     or has_function_privilege('shine_defence_runtime',
       'foundation.run_case_audit_reconcile_exec_verification_v1(uuid,timestamptz)','EXECUTE')
     or has_table_privilege('service_role',
       'foundation.case_audit_verify_reconcile_exec_verifications','INSERT')
     or not has_function_privilege('foundation_runtime',
       'foundation.evaluate_case_audit_reconcile_exec_verification_v1(uuid,timestamptz)','EXECUTE')
     or not has_function_privilege('foundation_runtime',
       'foundation.get_case_audit_reconcile_exec_verification_summary_v1(text,integer)','EXECUTE')
     or not has_function_privilege('foundation_gateway',
       'foundation.get_case_audit_reconcile_exec_verification_summary_v1(text,integer)','EXECUTE')
     or not pg_has_role('foundation_gateway','foundation_runtime','MEMBER')
     or exists(
       select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
       cross join lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a
       join pg_roles r on r.oid=a.grantee
       where n.nspname='foundation'
         and p.proname in (
           'evaluate_case_audit_reconcile_exec_verification_v1',
           'get_case_audit_reconcile_exec_verification_summary_v1'
         )
         and r.rolname='foundation_gateway' and a.privilege_type='EXECUTE'
     )
     or has_function_privilege('shine_core_control_plane',
       'foundation.get_case_audit_reconcile_exec_verification_summary_v1(text,integer)','EXECUTE')
     or has_function_privilege('shine_defence_runtime',
       'foundation.evaluate_case_audit_reconcile_exec_verification_v1(uuid,timestamptz)','EXECUTE')
     or has_function_privilege('anon',
       'foundation.get_case_audit_reconcile_exec_verification_summary_v1(text,integer)','EXECUTE')
     or has_function_privilege('authenticated',
       'foundation.evaluate_case_audit_reconcile_exec_verification_v1(uuid,timestamptz)','EXECUTE')
  then raise exception 'Layer 87 privilege boundary invalid'; end if;
end;
$l87_privileges$;

do $l87_append_only$
declare id uuid;
begin
  select verification_id into id
  from foundation.case_audit_verify_reconcile_exec_verifications limit 1;
  begin
    update foundation.case_audit_verify_reconcile_exec_verifications
    set reason_code='mutation' where verification_id=id;
    raise exception 'Layer 87 verification history unexpectedly mutated';
  exception when sqlstate '55000' then null;
  end;
end;
$l87_append_only$;

rollback;
