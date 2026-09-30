begin;

insert into foundation.foundation_promoted_release_case_audit_incident_events(
  event_id,incident_key,environment,domain,event_type,source_state,severity,
  reason_code,evidence_fingerprint,case_audit_observation_id,
  detection_started_at,persistence_threshold_seconds,persistence_seconds,
  snapshot,occurred_at,evidence_ref
)
values(
  '78000000-0000-4000-8000-000000000001'::uuid,
  'production:promoted_release_case_audit','production',
  'promoted_release_case_audit','opened','gap','critical',
  'promotion-case-audit-gap',repeat('a',64),null,
  now()-interval '20 minutes',300,900,'{"test":"layer78"}'::jsonb,
  now()-interval '15 minutes','test:layer78:incident'
);

do $l78_seed$
declare
  i integer;
  exec_id uuid;
  policy_fp text;
  action_result jsonb;
  proof jsonb;
  proof_hash text;
  verification_state text;
  reason_code text;
  durable_id uuid;
  durable_fp text;
begin
  -- Six successful Layer-76 receipts:
  -- 1 verified, 2 pending, 3 overdue, 4 missing, 5 mismatch, 6 invalid proof.
  for i in 1..6 loop
    exec_id:=('78000000-0000-4000-8000-'||lpad((100+i)::text,12,'0'))::uuid;
    policy_fp:=repeat(i::text,64);
    action_result:=jsonb_build_object(
      'foundationPromotedReleaseCaseAuditObservationRecord',
        'shine-foundation/promoted-release-case-audit-observation-record-v1',
      'schemaVersion','1.0.0',
      'environment','production',
      'status','recorded-heartbeat',
      'observationId',
        ('78000000-0000-4000-8000-'||lpad((200+i)::text,12,'0')),
      'semanticFingerprint',repeat('a',64)
    );

    insert into foundation.case_audit_safe_response_exec_events(
      event_id,environment,incident_event_id,action_key,cause_class,
      policy_fingerprint,event_type,reason_code,decision_snapshot,
      incident_snapshot,before_snapshot,action_result,after_snapshot,requested_at
    )
    values(
      exec_id,'production','78000000-0000-4000-8000-000000000001'::uuid,
      'record-fresh-promotion-case-audit-observation','observer-freshness',
      policy_fp,'executed','test-layer78-executed',
      '{}'::jsonb,'{}'::jsonb,'{}'::jsonb,action_result,'{}'::jsonb,
      case
        when i=2 then now()-interval '1 minute'
        else now()-interval '10 minutes'
      end
    );

    if i in (1,4,5,6) then
      verification_state:=case
        when i=1 then 'verified'
        when i=4 then 'missing'
        when i=5 then 'mismatch'
        else 'verified'
      end;
      reason_code:=case
        when i=1 then 'case-audit-safe-response-observation-durable'
        when i=4 then 'case-audit-safe-response-observation-missing'
        when i=5 then 'case-audit-safe-response-observation-mismatch'
        else 'case-audit-safe-response-observation-durable'
      end;
      durable_id:=case
        when i=4 then null
        else ('78000000-0000-4000-8000-'||lpad((300+i)::text,12,'0'))::uuid
      end;
      durable_fp:=case
        when i=4 then null
        else repeat('b',64)
      end;

      proof:=jsonb_build_object(
        'foundationCaseAuditSafeResponseVerificationProof',
          'shine-foundation/case-audit-safe-response-verification-proof-v1',
        'schemaVersion','1.0.0',
        'executionEventId',exec_id,
        'environment','production',
        'incidentEventId','78000000-0000-4000-8000-000000000001',
        'actionKey','record-fresh-promotion-case-audit-observation',
        'executionPolicyFingerprint',policy_fp,
        'verificationState',verification_state,
        'reasonCode',reason_code,
        'durableEvidenceId',durable_id,
        'durableEvidenceFingerprint',durable_fp,
        'independentDurableEvidenceRead',true,
        'targetReexecuted',false,
        'historyRewritePerformed',false,
        'releaseTruthMutationPerformed',false,
        'incidentHistoryMutationPerformed',false,
        'approvalGranted',false,
        'executionAuthorityGranted',false,
        'mutationPerformed',false,
        'verifiedAt',now()-interval '30 seconds'
      );

      proof_hash:=encode(
        extensions.digest(convert_to(proof::text,'UTF8'),'sha256'),
        'hex'
      );

      insert into foundation.case_audit_safe_response_verifications(
        verification_id,execution_event_id,environment,incident_event_id,
        action_key,execution_policy_fingerprint,verification_state,reason_code,
        durable_evidence_id,durable_evidence_fingerprint,
        durable_evidence_snapshot,execution_action_result,verification_proof,
        verification_proof_sha256,verified_at
      )
      values(
        ('78000000-0000-4000-8000-'||lpad((400+i)::text,12,'0'))::uuid,
        exec_id,'production',
        '78000000-0000-4000-8000-000000000001'::uuid,
        'record-fresh-promotion-case-audit-observation',
        policy_fp,verification_state,reason_code,durable_id,durable_fp,
        case when durable_id is null then null else '{"test":"layer78"}'::jsonb end,
        action_result,proof,
        case when i=6 then repeat('f',64) else proof_hash end,
        now()-interval '30 seconds'
      );
    end if;
  end loop;

  -- Denied Layer-76 receipts never enter verification coverage.
  insert into foundation.case_audit_safe_response_exec_events(
    event_id,environment,incident_event_id,action_key,cause_class,
    policy_fingerprint,event_type,reason_code,decision_snapshot,
    incident_snapshot,before_snapshot,requested_at
  )
  values(
    '78000000-0000-4000-8000-000000000199'::uuid,'production',
    '78000000-0000-4000-8000-000000000001'::uuid,
    'record-fresh-promotion-case-audit-observation','observer-freshness',
    repeat('9',64),'denied','test-layer78-denied',
    '{}'::jsonb,'{}'::jsonb,'{}'::jsonb,now()-interval '20 minutes'
  );
end;
$l78_seed$;


do $l78_coverage$
declare
  r jsonb;
  idle jsonb;
begin
  r:=foundation.get_case_audit_safe_response_verification_coverage_v1(
    'production',now(),300,50
  );

  if r->>'state'<>'invalid'
     or r->>'reasonCode'<>'case-audit-safe-response-verification-proof-invalid'
     or r->>'executionCount'<>'6'
     or r->>'verificationRequiredCount'<>'6'
     or r->>'verificationProofCount'<>'4'
     or r->>'verifiedCount'<>'1'
     or r->>'pendingCount'<>'1'
     or r->>'unverifiedCount'<>'1'
     or r->>'missingEvidenceCount'<>'1'
     or r->>'mismatchCount'<>'1'
     or r->>'invalidProofCount'<>'1'
     or r->>'problemCount'<>'4'
     or r->>'verificationCoveragePercent'<>'66.67'
     or r->>'healthyVerificationPercent'<>'16.67'
     or r->>'onlyExecutedReceiptsRequireVerification'<>'true'
     or r->>'proofIntegrityRecomputed'<>'true'
     or r->>'targetReexecuted'<>'false'
     or r->>'mutationPerformed'<>'false' then
    raise exception 'Layer 78 verification coverage invalid: %',r;
  end if;

  if not exists(
    select 1
    from jsonb_array_elements(r->'items') item
    where item->>'coverageState'='pending'
      and item->>'reasonCode'=
        'case-audit-safe-response-verification-within-grace'
  )
  or not exists(
    select 1
    from jsonb_array_elements(r->'items') item
    where item->>'coverageState'='unverified'
      and item->>'reasonCode'=
        'case-audit-safe-response-verification-overdue'
  )
  or not exists(
    select 1
    from jsonb_array_elements(r->'items') item
    where item->>'coverageState'='invalid'
      and item->>'proofIntegrityVerified'='false'
  ) then
    raise exception 'Layer 78 item classification invalid: %',r;
  end if;

  idle:=foundation.get_case_audit_safe_response_verification_coverage_v1(
    'staging',now(),300,50
  );

  if idle->>'state'<>'idle'
     or idle->>'executionCount'<>'0'
     or idle->>'verificationCoveragePercent'<>'100.00'
     or idle->>'healthyVerificationPercent'<>'100.00' then
    raise exception 'Layer 78 idle coverage invalid: %',idle;
  end if;
end;
$l78_coverage$;


do $l78_privileges$
begin
  if not has_function_privilege(
       'foundation_runtime',
       'foundation.get_case_audit_safe_response_verification_coverage_v1(text,timestamptz,integer,integer)',
       'EXECUTE'
     )
     or not has_function_privilege(
       'service_role',
       'foundation.get_case_audit_safe_response_verification_coverage_v1(text,timestamptz,integer,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'foundation_gateway',
       'foundation.get_case_audit_safe_response_verification_coverage_v1(text,timestamptz,integer,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'shine_core_control_plane',
       'foundation.get_case_audit_safe_response_verification_coverage_v1(text,timestamptz,integer,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'shine_defence_runtime',
       'foundation.get_case_audit_safe_response_verification_coverage_v1(text,timestamptz,integer,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'anon',
       'foundation.get_case_audit_safe_response_verification_coverage_v1(text,timestamptz,integer,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'authenticated',
       'foundation.get_case_audit_safe_response_verification_coverage_v1(text,timestamptz,integer,integer)',
       'EXECUTE'
     ) then
    raise exception 'Layer 78 verification coverage privilege boundary invalid';
  end if;
end;
$l78_privileges$;

rollback;
