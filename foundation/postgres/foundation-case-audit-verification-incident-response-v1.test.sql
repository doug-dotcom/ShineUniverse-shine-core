begin;

-- Deterministic Layer-79 summary stub for Layer-80 policy testing.
create or replace function foundation.get_case_audit_verify_incident_summary_v1(
  p_environment text default 'production',
  p_as_of timestamptz default now(),
  p_verification_grace_seconds integer default 300
)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $l80_incident_stub$
declare
  v_state text := coalesce(
    nullif(current_setting('foundation.test_l80_incident_state',true),''),
    'normal'
  );
begin
  return jsonb_build_object(
    'foundationCaseAuditVerificationIncidentSummary',
      'shine-foundation/case-audit-verification-incident-summary-v1',
    'schemaVersion','1.0.0',
    'environment',p_environment,
    'evaluatedAt',p_as_of,
    'state',v_state,
    'activeIncidentCount',case when v_state='critical' then 1 else 0 end,
    'watchCount',case when v_state='watching' then 1 else 0 end,
    'coverageState',
      coalesce(nullif(current_setting('foundation.test_l80_coverage_state',true),''),'normal'),
    'coverageReasonCode',
      coalesce(nullif(current_setting('foundation.test_l80_reason',true),''),'case-audit-safe-response-verification-covered'),
    'automaticVerification',false,
    'automaticRepair',false,
    'targetReexecuted',false,
    'mutatesAuthoritativeTruth',false,
    'mutatesIncidentHistory',false
  );
end;
$l80_incident_stub$;


create or replace function foundation.get_case_audit_safe_response_verification_coverage_v1(
  p_environment text default 'production',
  p_as_of timestamptz default now(),
  p_verification_grace_seconds integer default 300,
  p_limit integer default 50
)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $l80_coverage_stub$
declare
  v_state text := coalesce(
    nullif(current_setting('foundation.test_l80_coverage_state',true),''),
    'normal'
  );
  v_reason text := coalesce(
    nullif(current_setting('foundation.test_l80_reason',true),''),
    'case-audit-safe-response-verification-covered'
  );
  v_unverified integer := coalesce(
    nullif(current_setting('foundation.test_l80_unverified',true),'')::integer,
    0
  );
  v_missing integer := coalesce(
    nullif(current_setting('foundation.test_l80_missing',true),'')::integer,
    0
  );
  v_mismatch integer := coalesce(
    nullif(current_setting('foundation.test_l80_mismatch',true),'')::integer,
    0
  );
  v_invalid integer := coalesce(
    nullif(current_setting('foundation.test_l80_invalid',true),'')::integer,
    0
  );
begin
  return jsonb_build_object(
    'foundationCaseAuditSafeResponseVerificationCoverage',
      'shine-foundation/case-audit-safe-response-verification-coverage-v1',
    'schemaVersion','1.0.0',
    'environment',p_environment,
    'evaluatedAt',p_as_of,
    'state',v_state,
    'reasonCode',v_reason,
    'executionCount',greatest(1,v_unverified+v_missing+v_mismatch+v_invalid),
    'verificationProofCount',greatest(0,v_missing+v_mismatch+v_invalid),
    'verifiedCount',case when v_state='normal' then 1 else 0 end,
    'pendingCount',case when v_state='pending' then 1 else 0 end,
    'unverifiedCount',v_unverified,
    'missingEvidenceCount',v_missing,
    'mismatchCount',v_mismatch,
    'invalidProofCount',v_invalid,
    'problemCount',v_unverified+v_missing+v_mismatch+v_invalid,
    'verificationCoveragePercent',case
      when v_unverified>0 then 0.00 else 100.00
    end,
    'healthyVerificationPercent',case
      when v_state='normal' then 100.00 else 0.00
    end,
    'items','[]'::jsonb,
    'proofIntegrityRecomputed',true,
    'targetReexecuted',false,
    'mutationPerformed',false
  );
end;
$l80_coverage_stub$;


do $l80_normal$
declare
  c jsonb;
  d jsonb;
begin
  perform set_config('foundation.test_l80_incident_state','normal',true);
  perform set_config('foundation.test_l80_coverage_state','idle',true);
  perform set_config(
    'foundation.test_l80_reason',
    'case-audit-safe-response-verification-no-executions',true
  );
  perform set_config('foundation.test_l80_unverified','0',true);
  perform set_config('foundation.test_l80_missing','0',true);
  perform set_config('foundation.test_l80_mismatch','0',true);
  perform set_config('foundation.test_l80_invalid','0',true);

  c:=foundation.get_case_audit_verify_incident_cause_v1(
    'production',now(),300
  );

  if c->>'causeClass'<>'none'
     or c->>'nextEvidenceAction'<>'none'
     or c->>'authorityExpansion'<>'false'
     or c->>'automaticVerificationAllowed'<>'false'
     or c->>'automaticRepairAllowed'<>'false'
     or c->>'verificationProofRewriteAllowed'<>'false'
     or c->>'historyRewriteAllowed'<>'false' then
    raise exception 'Layer 80 normal cause invalid: %',c;
  end if;

  d:=foundation.evaluate_case_audit_verify_incident_response_v1(
    'inspect-verification-coverage','production',now(),300
  );
  if d->>'decision'<>'admit'
     or d->>'requiredControl'<>'read-only'
     or d->>'executesAction'<>'false' then
    raise exception 'Layer 80 coverage inspection invalid: %',d;
  end if;

  d:=foundation.evaluate_case_audit_verify_incident_response_v1(
    'run-independent-verification','production',now(),300
  );
  if d->>'decision'<>'not-applicable'
     or d->>'requiredControl'<>'none' then
    raise exception 'Layer 80 verification normal-state policy invalid: %',d;
  end if;
end;
$l80_normal$;


do $l80_omission$
declare
  c jsonb;
  d jsonb;
begin
  perform set_config('foundation.test_l80_incident_state','critical',true);
  perform set_config('foundation.test_l80_coverage_state','gap',true);
  perform set_config(
    'foundation.test_l80_reason',
    'case-audit-safe-response-verification-overdue',true
  );
  perform set_config('foundation.test_l80_unverified','1',true);
  perform set_config('foundation.test_l80_missing','0',true);
  perform set_config('foundation.test_l80_mismatch','0',true);
  perform set_config('foundation.test_l80_invalid','0',true);

  c:=foundation.get_case_audit_verify_incident_cause_v1(
    'production',now(),300
  );
  if c->>'causeClass'<>'verification-omission'
     or c->>'sourceDomain'<>'layer-77-verification-coverage'
     or c->>'nextEvidenceAction'<>'run-independent-verification'
     or c->>'unverifiedCount'<>'1' then
    raise exception 'Layer 80 omission cause invalid: %',c;
  end if;

  d:=foundation.evaluate_case_audit_verify_incident_response_v1(
    'run-independent-verification','production',now(),300
  );
  if d->>'decision'<>'admit'
     or d->>'requiredControl'<>'layer-77-bounded-verifier'
     or d->>'actionClass'<>'evidence'
     or d->>'automaticVerificationAllowed'<>'false'
     or d->>'executesAction'<>'false'
     or d->>'rerunsSafeResponse'<>'false' then
    raise exception 'Layer 80 bounded verifier admission invalid: %',d;
  end if;

  d:=foundation.evaluate_case_audit_verify_incident_response_v1(
    'inspect-unverified-executions','production',now(),300
  );
  if d->>'decision'<>'admit'
     or d->>'requiredControl'<>'read-only' then
    raise exception 'Layer 80 unverified inspection invalid: %',d;
  end if;
end;
$l80_omission$;


do $l80_missing$
declare
  c jsonb;
  d jsonb;
begin
  perform set_config('foundation.test_l80_incident_state','critical',true);
  perform set_config('foundation.test_l80_coverage_state','gap',true);
  perform set_config(
    'foundation.test_l80_reason',
    'case-audit-safe-response-durable-evidence-missing',true
  );
  perform set_config('foundation.test_l80_unverified','0',true);
  perform set_config('foundation.test_l80_missing','1',true);
  perform set_config('foundation.test_l80_mismatch','0',true);
  perform set_config('foundation.test_l80_invalid','0',true);

  c:=foundation.get_case_audit_verify_incident_cause_v1(
    'production',now(),300
  );
  if c->>'causeClass'<>'durable-evidence-missing'
     or c->>'nextEvidenceAction'<>'inspect-durable-evidence-chain'
     or c->>'missingEvidenceCount'<>'1' then
    raise exception 'Layer 80 missing evidence cause invalid: %',c;
  end if;

  d:=foundation.evaluate_case_audit_verify_incident_response_v1(
    'inspect-durable-evidence-chain','production',now(),300
  );
  if d->>'decision'<>'admit'
     or d->>'requiredControl'<>'read-only' then
    raise exception 'Layer 80 missing evidence inspection invalid: %',d;
  end if;

  d:=foundation.evaluate_case_audit_verify_incident_response_v1(
    'run-independent-verification','production',now(),300
  );
  if d->>'decision'<>'not-applicable' then
    raise exception 'Layer 80 must not reverify known-missing evidence: %',d;
  end if;
end;
$l80_missing$;


do $l80_mismatch$
declare
  c jsonb;
  d jsonb;
begin
  perform set_config('foundation.test_l80_incident_state','critical',true);
  perform set_config('foundation.test_l80_coverage_state','gap',true);
  perform set_config(
    'foundation.test_l80_reason',
    'case-audit-safe-response-durable-evidence-mismatch',true
  );
  perform set_config('foundation.test_l80_unverified','0',true);
  perform set_config('foundation.test_l80_missing','0',true);
  perform set_config('foundation.test_l80_mismatch','1',true);
  perform set_config('foundation.test_l80_invalid','0',true);

  c:=foundation.get_case_audit_verify_incident_cause_v1(
    'production',now(),300
  );
  if c->>'causeClass'<>'durable-evidence-mismatch'
     or c->>'nextEvidenceAction'<>'inspect-durable-evidence-chain'
     or c->>'mismatchCount'<>'1' then
    raise exception 'Layer 80 mismatch cause invalid: %',c;
  end if;

  d:=foundation.evaluate_case_audit_verify_incident_response_v1(
    'inspect-durable-evidence-chain','production',now(),300
  );
  if d->>'decision'<>'admit' then
    raise exception 'Layer 80 mismatch inspection invalid: %',d;
  end if;
end;
$l80_mismatch$;


do $l80_invalid$
declare
  c jsonb;
  d jsonb;
begin
  perform set_config('foundation.test_l80_incident_state','critical',true);
  perform set_config('foundation.test_l80_coverage_state','invalid',true);
  perform set_config(
    'foundation.test_l80_reason',
    'case-audit-safe-response-verification-proof-invalid',true
  );
  perform set_config('foundation.test_l80_unverified','0',true);
  perform set_config('foundation.test_l80_missing','0',true);
  perform set_config('foundation.test_l80_mismatch','0',true);
  perform set_config('foundation.test_l80_invalid','1',true);

  c:=foundation.get_case_audit_verify_incident_cause_v1(
    'production',now(),300
  );
  if c->>'causeClass'<>'verification-proof-integrity'
     or c->>'nextEvidenceAction'<>'inspect-verification-proof'
     or c->>'invalidProofCount'<>'1' then
    raise exception 'Layer 80 invalid proof cause invalid: %',c;
  end if;

  d:=foundation.evaluate_case_audit_verify_incident_response_v1(
    'inspect-verification-proof','production',now(),300
  );
  if d->>'decision'<>'admit'
     or d->>'requiredControl'<>'read-only' then
    raise exception 'Layer 80 proof inspection invalid: %',d;
  end if;
end;
$l80_invalid$;


do $l80_prohibited$
declare
  action_key text;
  d jsonb;
begin
  foreach action_key in array array[
    'rerun-safe-response',
    'manufacture-durable-evidence',
    'repair-durable-evidence',
    'rewrite-verification-proof',
    'delete-verification-proof',
    'repair-verification-ledger',
    'suppress-verification-coverage-incident',
    'delete-verification-coverage-incident-history',
    'mutate-release-truth'
  ]
  loop
    d:=foundation.evaluate_case_audit_verify_incident_response_v1(
      action_key,'production',now(),300
    );

    if d->>'decision'<>'deny'
       or d->>'requiredControl'<>'prohibited'
       or d->>'executesAction'<>'false'
       or d->>'authorityExpansion'<>'false'
       or d->>'automaticVerificationAllowed'<>'false'
       or d->>'automaticRepairAllowed'<>'false'
       or d->>'verificationProofRewriteAllowed'<>'false'
       or d->>'historyRewriteAllowed'<>'false' then
      raise exception 'Layer 80 prohibited action escaped policy: %',d;
    end if;
  end loop;
end;
$l80_prohibited$;


do $l80_plan$
declare
  p jsonb;
begin
  perform set_config('foundation.test_l80_incident_state','critical',true);
  perform set_config('foundation.test_l80_coverage_state','gap',true);
  perform set_config(
    'foundation.test_l80_reason',
    'case-audit-safe-response-verification-overdue',true
  );
  perform set_config('foundation.test_l80_unverified','1',true);
  perform set_config('foundation.test_l80_missing','0',true);
  perform set_config('foundation.test_l80_mismatch','0',true);
  perform set_config('foundation.test_l80_invalid','0',true);

  p:=foundation.get_case_audit_verify_incident_response_plan_v1(
    'production',now(),300
  );

  if p->>'causeClass'<>'verification-omission'
     or p->>'nextEvidenceAction'<>'run-independent-verification'
     or p->>'authorityExpansion'<>'false'
     or p->>'automaticVerificationAllowed'<>'false'
     or p->>'automaticRepairAllowed'<>'false'
     or p->>'verificationProofRewriteAllowed'<>'false'
     or p->>'historyRewriteAllowed'<>'false'
     or jsonb_array_length(p->'actions')<>14
     or not exists(
       select 1
       from jsonb_array_elements(p->'actions') a
       where a->>'actionKey'='run-independent-verification'
         and a->>'decision'='admit'
         and a->>'requiredControl'='layer-77-bounded-verifier'
     )
     or not exists(
       select 1
       from jsonb_array_elements(p->'actions') a
       where a->>'actionKey'='rerun-safe-response'
         and a->>'decision'='deny'
     ) then
    raise exception 'Layer 80 response plan invalid: %',p;
  end if;
end;
$l80_plan$;


do $l80_unknown_action$
declare
  d jsonb;
begin
  d:=foundation.evaluate_case_audit_verify_incident_response_v1(
    'unknown-action','production',now(),300
  );

  if d->>'decision'<>'deny'
     or d->>'requiredControl'<>'prohibited'
     or d->>'actionClass' is not null then
    raise exception 'Layer 80 unknown action must fail closed: %',d;
  end if;
end;
$l80_unknown_action$;


do $l80_privileges$
begin
  if not has_function_privilege(
       'foundation_runtime',
       'foundation.get_case_audit_verify_incident_cause_v1(text,timestamptz,integer)',
       'EXECUTE'
     )
     or not has_function_privilege(
       'service_role',
       'foundation.evaluate_case_audit_verify_incident_response_v1(text,text,timestamptz,integer)',
       'EXECUTE'
     )
     or not has_function_privilege(
       'foundation_gateway',
       'foundation.get_case_audit_verify_incident_response_plan_v1(text,timestamptz,integer)',
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
         and p.proname in (
           'get_case_audit_verify_incident_cause_v1',
           'evaluate_case_audit_verify_incident_response_v1',
           'get_case_audit_verify_incident_response_plan_v1'
         )
         and r.rolname='foundation_gateway'
         and a.privilege_type='EXECUTE'
     )
     or has_function_privilege(
       'shine_core_control_plane',
       'foundation.get_case_audit_verify_incident_response_plan_v1(text,timestamptz,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'shine_defence_runtime',
       'foundation.get_case_audit_verify_incident_response_plan_v1(text,timestamptz,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'anon',
       'foundation.evaluate_case_audit_verify_incident_response_v1(text,text,timestamptz,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'authenticated',
       'foundation.get_case_audit_verify_incident_cause_v1(text,timestamptz,integer)',
       'EXECUTE'
     ) then
    raise exception 'Layer 80 privilege boundary invalid';
  end if;
end;
$l80_privileges$;

rollback;
