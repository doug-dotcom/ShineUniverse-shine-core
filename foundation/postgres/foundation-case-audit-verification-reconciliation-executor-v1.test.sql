begin;

insert into foundation.foundation_promoted_release_case_audit_incident_events(
  event_id,incident_key,environment,domain,event_type,source_state,severity,
  reason_code,evidence_fingerprint,case_audit_observation_id,
  detection_started_at,persistence_threshold_seconds,persistence_seconds,
  snapshot,occurred_at,evidence_ref
)
values(
  '86000000-0000-4000-8000-000000000001'::uuid,
  'production:promoted_release_case_audit','production',
  'promoted_release_case_audit','opened','gap','critical',
  'promotion-case-audit-gap',repeat('a',64),null,
  now()-interval '30 minutes',300,1200,'{"test":"layer86"}'::jsonb,
  now()-interval '20 minutes','test:layer86:case-audit-incident'
);

insert into foundation.foundation_promoted_release_case_audit_observations(
  observation_id,environment,audit_state,structural_integrity_pass,incident_state,
  active_incident_event_id,active_incident_handoff_state,case_count,invalid_count,
  active_case_count,pending_case_count,terminal_case_count,historical_case_count,
  semantic_fingerprint,changed_from_previous,snapshot,observed_at
)
values(
  '86000000-0000-4000-8000-000000000010'::uuid,
  'production','idle',true,'normal',null,'not-required',
  0,0,0,0,0,0,
  foundation.foundation_promoted_release_case_audit_semantic_fingerprint_v1(
    '{"overallState":"idle","test":"layer86"}'::jsonb
  ),
  false,'{"overallState":"idle","test":"layer86"}'::jsonb,
  now()-interval '15 minutes'
);

insert into foundation.case_audit_verify_incident_events(
  event_id,incident_key,environment,domain,event_type,source_state,severity,
  reason_code,evidence_fingerprint,detection_started_at,
  persistence_threshold_seconds,persistence_seconds,snapshot,occurred_at,
  evidence_ref
)
values(
  '86000000-0000-4000-8000-000000000201'::uuid,
  'production:case_audit_verification_coverage','production',
  'case_audit_verification_coverage','opened','gap','critical',
  'case-audit-safe-response-verification-overdue',repeat('9',64),
  now()-interval '15 minutes',300,600,'{"test":"layer86"}'::jsonb,
  now()-interval '8 minutes','test:layer86:verification-incident'
);


do $l86_seed_layer76$
declare
  fp text;
  action_result jsonb;
  i integer;
  event_id uuid;
begin
  fp:=foundation.foundation_promoted_release_case_audit_semantic_fingerprint_v1(
    '{"overallState":"idle","test":"layer86"}'::jsonb
  );

  for i in 1..3 loop
    event_id:=(
      '86000000-0000-4000-8000-'||lpad((100+i)::text,12,'0')
    )::uuid;

    action_result:=jsonb_build_object(
      'foundationPromotedReleaseCaseAuditObservationRecord',
        'shine-foundation/promoted-release-case-audit-observation-record-v1',
      'schemaVersion','1.0.0',
      'environment','production',
      'status','recorded-heartbeat',
      'observationId','86000000-0000-4000-8000-000000000010',
      'semanticFingerprint',fp
    );

    insert into foundation.case_audit_safe_response_exec_events(
      event_id,environment,incident_event_id,action_key,cause_class,
      policy_fingerprint,event_type,reason_code,decision_snapshot,
      incident_snapshot,before_snapshot,action_result,after_snapshot,requested_at
    )
    values(
      event_id,'production',
      '86000000-0000-4000-8000-000000000001'::uuid,
      'record-fresh-promotion-case-audit-observation','observer-freshness',
      repeat(i::text,64),'executed','test-layer86-target-executed',
      '{}'::jsonb,'{}'::jsonb,'{}'::jsonb,action_result,'{}'::jsonb,
      now()-interval '15 minutes'
    );
  end loop;
end;
$l86_seed_layer76$;


-- Real Layer-77 proofs make the Layer-82 call genuinely end-to-end.
do $l86_real_layer77$
declare
  r jsonb;
  i integer;
begin
  for i in 1..2 loop
    r:=foundation.run_case_audit_safe_response_verification_v1(
      (
        '86000000-0000-4000-8000-'||lpad((100+i)::text,12,'0')
      )::uuid,
      now()
    );
    if r->>'status'<>'recorded'
       or r->>'verificationState'<>'verified' then
      raise exception 'Layer 86 Layer-77 seed proof invalid: %',r;
    end if;
  end loop;
end;
$l86_real_layer77$;


do $l86_seed_layer81$
declare
  decision jsonb;
  incident_snapshot jsonb;
  before_coverage jsonb;
  target foundation.case_audit_safe_response_exec_events%rowtype;
  verification foundation.case_audit_safe_response_verifications%rowtype;
  target_snapshot jsonb;
  action_result jsonb;
  policy_fp text;
  i integer;
  executor_event_id uuid;
  requested_at timestamptz;
begin
  decision:=jsonb_build_object(
    'foundationCaseAuditVerificationIncidentResponseDecision',
      'shine-foundation/case-audit-verification-incident-response-decision-v1',
    'schemaVersion','1.0.0',
    'environment','production',
    'incidentState','critical',
    'causeClass','verification-omission',
    'actionKey','run-independent-verification',
    'actionClass','evidence',
    'decision','admit',
    'requiredControl','layer-77-bounded-verifier',
    'reasonCode','case-audit-verification-response-run-bounded-verification',
    'authorityExpansion',false,
    'automaticVerificationAllowed',false,
    'automaticRepairAllowed',false,
    'verificationProofRewriteAllowed',false,
    'historyRewriteAllowed',false,
    'mutatesAuthoritativeTruth',false,
    'mutatesIncidentHistory',false,
    'mutatesVerificationProof',false,
    'rerunsSafeResponse',false,
    'executesAction',false
  );

  incident_snapshot:=jsonb_build_object(
    'state','critical',
    'currentEvent',jsonb_build_object(
      'eventId','86000000-0000-4000-8000-000000000201',
      'eventType','opened',
      'sourceState','gap',
      'evidenceFingerprint',repeat('9',64)
    )
  );

  before_coverage:=
    foundation.get_case_audit_safe_response_verification_coverage_v1(
      'production',now(),300,100
    );

  for i in 1..3 loop
    select * into target
    from foundation.case_audit_safe_response_exec_events
    where event_id=(
      '86000000-0000-4000-8000-'||lpad((100+i)::text,12,'0')
    )::uuid;

    select * into verification
    from foundation.case_audit_safe_response_verifications
    where execution_event_id=target.event_id;

    target_snapshot:=jsonb_build_object(
      'executionEventId',target.event_id,
      'incidentEventId',target.incident_event_id,
      'actionKey',target.action_key,
      'executionPolicyFingerprint',target.policy_fingerprint,
      'executionEventType',target.event_type,
      'executionRequestedAt',target.requested_at,
      'executionAgeSeconds',900,
      'verificationGraceSeconds',300,
      'verificationId',null,
      'verificationState',null,
      'verificationAbsent',true
    );

    action_result:=case
      when verification.verification_id is null then
        jsonb_build_object(
          'foundationCaseAuditSafeResponseVerification',
            'shine-foundation/case-audit-safe-response-verification-response-v1',
          'schemaVersion','1.0.0',
          'status','recorded',
          'verificationId','86000000-0000-4000-8000-000000000999',
          'executionEventId',target.event_id,
          'verificationState','verified',
          'reasonCode','case-audit-safe-response-observation-durable',
          'durableEvidenceId','86000000-0000-4000-8000-000000000010',
          'durableEvidenceFingerprint',repeat('f',64),
          'verificationProofSha256',repeat('f',64),
          'targetReexecuted',false,
          'mutationPerformed',false
        )
      else
        jsonb_build_object(
          'foundationCaseAuditSafeResponseVerification',
            'shine-foundation/case-audit-safe-response-verification-response-v1',
          'schemaVersion','1.0.0',
          'status','recorded',
          'verificationId',verification.verification_id,
          'executionEventId',verification.execution_event_id,
          'verificationState',verification.verification_state,
          'reasonCode',verification.reason_code,
          'durableEvidenceId',verification.durable_evidence_id,
          'durableEvidenceFingerprint',verification.durable_evidence_fingerprint,
          'verificationProofSha256',verification.verification_proof_sha256,
          'targetReexecuted',false,
          'mutationPerformed',false
        )
    end;

    policy_fp:=foundation.case_audit_verify_exec_policy_fp_v1(
      decision,incident_snapshot,target_snapshot
    );

    executor_event_id:=(
      '86000000-0000-4000-8000-'||lpad((300+i)::text,12,'0')
    )::uuid;

    requested_at:=case
      when i=2 then now()-interval '1 minute'
      else now()-interval '10 minutes'
    end;

    insert into foundation.case_audit_verify_exec_events(
      event_id,environment,target_execution_event_id,
      verification_incident_event_id,action_key,cause_class,
      policy_fingerprint,event_type,reason_code,decision_snapshot,
      incident_snapshot,target_snapshot,before_coverage,action_result,
      after_coverage,requested_at
    )
    values(
      executor_event_id,'production',target.event_id,
      '86000000-0000-4000-8000-000000000201'::uuid,
      'run-independent-verification','verification-omission',
      policy_fp,
      case when i=3 then 'denied' else 'executed' end,
      case
        when i=3 then 'case-audit-overdue-verification-policy-not-admitted'
        else 'case-audit-overdue-verification-layer77-ran'
      end,
      decision,incident_snapshot,target_snapshot,before_coverage,
      case when i=3 then null else action_result end,
      case when i=3 then null else before_coverage end,
      requested_at
    );
  end loop;
end;
$l86_seed_layer81$;


do $l86_seed_reconciliation_incident$
declare
  coverage jsonb;
begin
  coverage:=foundation.get_case_audit_verify_reconcile_coverage_v1(
    'production',now(),300,100
  );

  if coverage->>'state'<>'gap'
     or coverage->>'overdueCount'<>'1'
     or coverage->>'pendingCount'<>'1' then
    raise exception 'Layer 86 seed reconciliation coverage invalid: %',coverage;
  end if;

  insert into foundation.case_audit_verify_reconcile_incident_events(
    event_id,incident_key,environment,domain,event_type,source_state,severity,
    reason_code,evidence_fingerprint,detection_started_at,
    persistence_threshold_seconds,persistence_seconds,snapshot,occurred_at,
    evidence_ref
  )
  values(
    '86000000-0000-4000-8000-000000000401'::uuid,
    'production:case_audit_verification_reconciliation_coverage','production',
    'case_audit_verification_reconciliation_coverage','opened','gap','critical',
    coverage->>'reasonCode',
    foundation.case_audit_verify_reconcile_incident_fingerprint_v1(coverage),
    now()-interval '10 minutes',300,600,coverage,
    now()-interval '1 minute','test:layer86:reconciliation-incident'
  );
end;
$l86_seed_reconciliation_incident$;


set local role service_role;

do $l86_execute$
declare
  r jsonb;
  replay jsonb;
  pending_result jsonb;
  denied_result jsonb;
  missing_result jsonb;
  summary jsonb;
  layer81_count_before bigint;
  layer81_count_after bigint;
  verification_count_before bigint;
  verification_count_after bigint;
  reconciliation_count_before bigint;
  reconciliation_count_after bigint;
begin
  if has_function_privilege(
       'service_role',
       'foundation.run_case_audit_verify_exec_reconciliation_v1(uuid,timestamptz,integer)',
       'EXECUTE'
     ) then
    raise exception 'Layer 86 direct Layer-82 bypass still available';
  end if;

  if not has_function_privilege(
       'service_role',
       'foundation.execute_case_audit_overdue_reconciliation_v1(uuid,text,timestamptz,integer,integer)',
       'EXECUTE'
     ) then
    raise exception 'Layer 86 service-role executor unavailable';
  end if;

  select count(*) into layer81_count_before
  from foundation.case_audit_verify_exec_events;
  select count(*) into verification_count_before
  from foundation.case_audit_safe_response_verifications;
  select count(*) into reconciliation_count_before
  from foundation.case_audit_verify_exec_reconciliations;

  r:=foundation.execute_case_audit_overdue_reconciliation_v1(
    '86000000-0000-4000-8000-000000000301'::uuid,
    'production',now(),300,300
  );

  if r->>'status'<>'executed'
     or r->>'reasonCode'<>'case-audit-overdue-reconciliation-layer82-ran'
     or r#>>'{actionResult,status}'<>'recorded'
     or r#>>'{actionResult,reconciliationState}'<>'reconciled'
     or r->>'afterCoverageState'<>'pending'
     or r->>'boundedLayer82ReconcilerOnly'<>'true'
     or r->>'layer81RerunPerformed'<>'false'
     or r->>'verificationRerunPerformed'<>'false'
     or r->>'evidenceMutationPerformed'<>'false'
     or r->>'reconciliationReceiptRewritePerformed'<>'false'
     or r->>'verificationProofRewritePerformed'<>'false'
     or r->>'releaseTruthMutationPerformed'<>'false'
     or r->>'incidentHistoryMutationPerformed'<>'false' then
    raise exception 'Layer 86 eligible execution invalid: %',r;
  end if;

  if not exists(
    select 1
    from foundation.case_audit_verify_exec_reconciliations
    where executor_event_id='86000000-0000-4000-8000-000000000301'::uuid
      and reconciliation_state='reconciled'
  ) then
    raise exception 'Layer 86 did not persist Layer-82 reconciliation receipt';
  end if;

  replay:=foundation.execute_case_audit_overdue_reconciliation_v1(
    '86000000-0000-4000-8000-000000000301'::uuid,
    'production',now(),300,300
  );

  if replay->>'status'<>'existing'
     or replay->>'eventId'<>r->>'eventId'
     or replay#>>'{actionResult,reconciliationState}'<>'reconciled' then
    raise exception 'Layer 86 replay did not preserve first execution: %',replay;
  end if;

  pending_result:=foundation.execute_case_audit_overdue_reconciliation_v1(
    '86000000-0000-4000-8000-000000000302'::uuid,
    'production',now(),300,300
  );

  if pending_result->>'status'<>'denied'
     or pending_result->>'reasonCode'<>'case-audit-overdue-reconciliation-within-grace' then
    raise exception 'Layer 86 reconciliation grace enforcement invalid: %',pending_result;
  end if;

  denied_result:=foundation.execute_case_audit_overdue_reconciliation_v1(
    '86000000-0000-4000-8000-000000000303'::uuid,
    'production',now(),300,300
  );

  if denied_result->>'status'<>'denied'
     or denied_result->>'reasonCode'<>'case-audit-overdue-reconciliation-target-not-successful' then
    raise exception 'Layer 86 target event-type enforcement invalid: %',denied_result;
  end if;

  missing_result:=foundation.execute_case_audit_overdue_reconciliation_v1(
    '86000000-0000-4000-8000-000000000999'::uuid,
    'production',now(),300,300
  );

  if missing_result->>'status'<>'not-applicable'
     or missing_result->>'reasonCode'<>'case-audit-overdue-reconciliation-target-not-found' then
    raise exception 'Layer 86 missing target handling invalid: %',missing_result;
  end if;

  select count(*) into layer81_count_after
  from foundation.case_audit_verify_exec_events;
  select count(*) into verification_count_after
  from foundation.case_audit_safe_response_verifications;
  select count(*) into reconciliation_count_after
  from foundation.case_audit_verify_exec_reconciliations;

  if layer81_count_after<>layer81_count_before
     or verification_count_after<>verification_count_before
     or reconciliation_count_after<>reconciliation_count_before+1 then
    raise exception 'Layer 86 reran upstream controls or produced unexpected reconciliation count';
  end if;

  summary:=foundation.get_case_audit_verify_reconcile_exec_summary_v1(
    'production',25
  );

  if summary->>'totalCount'<>'3'
     or summary->>'executedCount'<>'1'
     or summary->>'deniedCount'<>'2'
     or summary->>'failedCount'<>'0'
     or summary->>'directLayer82ServiceRoleBypassAllowed'<>'false'
     or summary->>'layer81RerunPerformed'<>'false'
     or summary->>'verificationRerunPerformed'<>'false'
     or summary->>'evidenceMutationPerformed'<>'false'
     or summary->>'reconciliationReceiptRewritePerformed'<>'false'
     or summary->>'verificationProofRewritePerformed'<>'false'
     or summary->>'releaseTruthMutationPerformed'<>'false'
     or summary->>'incidentHistoryMutationPerformed'<>'false' then
    raise exception 'Layer 86 executor summary invalid: %',summary;
  end if;
end;
$l86_execute$;

reset role;


do $l86_privileges$
begin
  if has_function_privilege(
       'foundation_runtime',
       'foundation.execute_case_audit_overdue_reconciliation_v1(uuid,text,timestamptz,integer,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'foundation_gateway',
       'foundation.execute_case_audit_overdue_reconciliation_v1(uuid,text,timestamptz,integer,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'shine_core_control_plane',
       'foundation.execute_case_audit_overdue_reconciliation_v1(uuid,text,timestamptz,integer,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'shine_defence_runtime',
       'foundation.execute_case_audit_overdue_reconciliation_v1(uuid,text,timestamptz,integer,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'anon',
       'foundation.execute_case_audit_overdue_reconciliation_v1(uuid,text,timestamptz,integer,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'authenticated',
       'foundation.execute_case_audit_overdue_reconciliation_v1(uuid,text,timestamptz,integer,integer)',
       'EXECUTE'
     )
     or has_table_privilege(
       'service_role',
       'foundation.case_audit_verify_reconcile_exec_events',
       'INSERT'
     )
     or not has_function_privilege(
       'foundation_runtime',
       'foundation.get_case_audit_verify_reconcile_exec_summary_v1(text,integer)',
       'EXECUTE'
     )
     or not has_function_privilege(
       'foundation_gateway',
       'foundation.get_case_audit_verify_reconcile_exec_summary_v1(text,integer)',
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
         and p.proname='get_case_audit_verify_reconcile_exec_summary_v1'
         and r.rolname='foundation_gateway'
         and a.privilege_type='EXECUTE'
     )
     or has_function_privilege(
       'shine_core_control_plane',
       'foundation.get_case_audit_verify_reconcile_exec_summary_v1(text,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'shine_defence_runtime',
       'foundation.get_case_audit_verify_reconcile_exec_summary_v1(text,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'anon',
       'foundation.get_case_audit_verify_reconcile_exec_summary_v1(text,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'authenticated',
       'foundation.get_case_audit_verify_reconcile_exec_summary_v1(text,integer)',
       'EXECUTE'
     ) then
    raise exception 'Layer 86 privilege boundary invalid';
  end if;
end;
$l86_privileges$;


do $l86_append_only$
declare
  id uuid;
begin
  select event_id into id
  from foundation.case_audit_verify_reconcile_exec_events
  where event_type='executed'
  limit 1;

  begin
    update foundation.case_audit_verify_reconcile_exec_events
    set reason_code='mutation'
    where event_id=id;
    raise exception 'Layer 86 executor history unexpectedly mutated';
  exception when sqlstate '55000' then
    null;
  end;
end;
$l86_append_only$;

rollback;
