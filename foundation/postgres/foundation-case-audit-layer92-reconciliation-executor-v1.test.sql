begin;

-- Deterministic Layer-93/94/95 environment for Layer-96 executor acceptance.
create or replace function foundation.get_case_audit_layer92_reconciliation_coverage_v1(
  p_environment text default 'production',
  p_as_of timestamptz default now(),
  p_reconciliation_grace_seconds integer default 300,
  p_limit integer default 50
)
returns jsonb
language sql
stable
security definer
set search_path=''
as $l96_coverage_stub$
  select jsonb_build_object(
    'foundationCaseAuditLayer92ReconciliationCoverage',
      'shine-foundation/case-audit-layer92-reconciliation-coverage-v1',
    'schemaVersion','1.0.0',
    'environment',p_environment,
    'evaluatedAt',p_as_of,
    'reconciliationGraceSeconds',p_reconciliation_grace_seconds,
    'state','gap',
    'reasonCode','case-audit-layer92-overdue',
    'successfulLayer91ExecutionCount',2,
    'layer92ReconciliationRequiredCount',2,
    'layer92ReconciliationReceiptCount',0,
    'reconciledCount',0,
    'pendingCount',1,
    'overdueCount',1,
    'invalidLayer92ReconciliationCount',0,
    'missingLayer87ReceiptCount',0,
    'invalidLayer87ReceiptCount',0,
    'executionReceiptMismatchCount',0,
    'policyDriftCount',0,
    'incidentDriftCount',0,
    'coverageDriftCount',0,
    'problemCount',1,
    'layer92ReconciliationCoveragePercent',0,
    'healthyLayer92ReconciliationPercent',0,
    'items','[]'::jsonb,
    'layer92ProofIntegrityRecomputed',true,
    'linkedLayer87SnapshotRevalidated',true,
    'layer92ReconciliationPerformed',false,
    'layer91RerunPerformed',false,
    'layer87RerunPerformed',false,
    'layer86RerunPerformed',false,
    'layer82RerunPerformed',false,
    'layer81RerunPerformed',false,
    'verificationRerunPerformed',false,
    'evidenceMutationPerformed',false,
    'layer92ReceiptRewritePerformed',false,
    'layer91ReceiptRewritePerformed',false,
    'layer87ReceiptRewritePerformed',false,
    'releaseTruthMutationPerformed',false,
    'incidentHistoryMutationPerformed',false,
    'mutationPerformed',false
  );
$l96_coverage_stub$;


create or replace function foundation.get_case_audit_layer92_coverage_incident_summary_v1(
  p_environment text default 'production',
  p_as_of timestamptz default now(),
  p_reconciliation_grace_seconds integer default 300
)
returns jsonb
language sql
stable
security definer
set search_path=''
as $l96_incident_stub$
  select jsonb_build_object(
    'foundationCaseAuditLayer92CoverageIncidentSummary',
      'shine-foundation/case-audit-layer92-reconciliation-coverage-incident-summary-v1',
    'schemaVersion','1.0.0',
    'environment',p_environment,
    'evaluatedAt',p_as_of,
    'state','critical',
    'activeIncidentCount',1,
    'watchCount',0,
    'coverageState','gap',
    'coverageReasonCode','case-audit-layer92-overdue',
    'successfulLayer91ExecutionCount',2,
    'layer92ReconciliationReceiptCount',0,
    'problemCount',1,
    'layer92ReconciliationCoveragePercent',0,
    'healthyLayer92ReconciliationPercent',0,
    'currentEvent',jsonb_build_object(
      'eventId','96000000-0000-4000-8000-000000000901',
      'incidentKey','production:case_audit_layer92_reconciliation_coverage',
      'eventType','opened',
      'sourceState','gap',
      'severity','critical',
      'reasonCode','case-audit-layer92-overdue',
      'evidenceFingerprint',repeat('9',64),
      'detectionStartedAt',p_as_of-interval '10 minutes',
      'persistenceThresholdSeconds',300,
      'persistenceSeconds',600,
      'occurredAt',p_as_of-interval '1 minute',
      'evidenceRef','test:layer96:coverage-incident'
    ),
    'recommendedAction','investigate-layer92-reconciliation-coverage-failure',
    'automaticLayer92Reconciliation',false,
    'automaticReconciliation',false,
    'automaticRepair',false,
    'layer91RerunPerformed',false,
    'layer87RerunPerformed',false,
    'layer86RerunPerformed',false,
    'layer82RerunPerformed',false,
    'layer81RerunPerformed',false,
    'verificationRerunPerformed',false,
    'mutatesAuthoritativeTruth',false,
    'mutatesIncidentHistory',false
  );
$l96_incident_stub$;


create or replace function foundation.evaluate_case_audit_layer92_coverage_incident_response_v1(
  p_action_key text,
  p_environment text default 'production',
  p_as_of timestamptz default now(),
  p_reconciliation_grace_seconds integer default 300
)
returns jsonb
language sql
stable
security definer
set search_path=''
as $l96_policy_stub$
  select jsonb_build_object(
    'foundationCaseAuditLayer92CoverageIncidentResponseDecision',
      'shine-foundation/case-audit-layer92-reconciliation-coverage-incident-response-decision-v1',
    'schemaVersion','1.0.0',
    'environment',p_environment,
    'evaluatedAt',p_as_of,
    'incidentState','critical',
    'causeClass','layer92-reconciliation-omission',
    'actionKey',p_action_key,
    'actionClass','evidence',
    'decision',case
      when p_action_key='run-independent-layer92-reconciliation' then 'admit'
      else 'deny'
    end,
    'requiredControl',case
      when p_action_key='run-independent-layer92-reconciliation'
        then 'layer-92-bounded-reconciler'
      else 'prohibited'
    end,
    'reasonCode','case-audit-layer92-response-run-bounded-reconciliation',
    'boundedReconciler','foundation.run_case_audit_layer91_execution_reconciliation_v1',
    'authorityExpansion',false,
    'automaticLayer92ReconciliationAllowed',false,
    'automaticReconciliationAllowed',false,
    'automaticRepairAllowed',false,
    'layer92ReceiptRewriteAllowed',false,
    'layer91ReceiptRewriteAllowed',false,
    'layer87ReceiptRewriteAllowed',false,
    'historyRewriteAllowed',false,
    'layer91RerunAllowed',false,
    'layer87RerunAllowed',false,
    'layer86RerunAllowed',false,
    'layer82RerunAllowed',false,
    'layer81RerunAllowed',false,
    'verificationRerunAllowed',false,
    'mutatesAuthoritativeTruth',false,
    'mutatesIncidentHistory',false,
    'mutatesLayer92Receipt',false,
    'mutatesLayer91Receipt',false,
    'mutatesLayer87Receipt',false,
    'rerunsLayer91',false,
    'rerunsLayer87',false,
    'rerunsLayer86',false,
    'rerunsLayer82',false,
    'rerunsLayer81',false,
    'rerunsVerification',false,
    'executesAction',false
  );
$l96_policy_stub$;


insert into foundation.foundation_promoted_release_case_audit_incident_events(
  event_id,incident_key,environment,domain,event_type,source_state,severity,
  reason_code,evidence_fingerprint,case_audit_observation_id,
  detection_started_at,persistence_threshold_seconds,persistence_seconds,
  snapshot,occurred_at,evidence_ref
) values (
  '96000000-0000-4000-8000-000000000001'::uuid,
  'production:promoted_release_case_audit','production',
  'promoted_release_case_audit','opened','gap','critical',
  'promotion-case-audit-gap',repeat('1',64),null,
  now()-interval '30 minutes',300,1200,'{"test":"layer96"}'::jsonb,
  now()-interval '20 minutes','test:layer96:case-audit-incident'
);

do $l96_seed_layer76$
declare i integer;
begin
  for i in 1..3 loop
    insert into foundation.case_audit_safe_response_exec_events(
      event_id,environment,incident_event_id,action_key,cause_class,
      policy_fingerprint,event_type,reason_code,decision_snapshot,
      incident_snapshot,before_snapshot,action_result,after_snapshot,requested_at
    ) values(
      ('96000000-0000-4000-8000-'||lpad((100+i)::text,12,'0'))::uuid,
      'production','96000000-0000-4000-8000-000000000001'::uuid,
      'record-fresh-promotion-case-audit-observation','observer-freshness',
      lpad(to_hex(i),64,'0'),'executed','test-layer96-layer76',
      '{}'::jsonb,'{}'::jsonb,'{}'::jsonb,
      jsonb_build_object('status','recorded','test','layer96','chain',i),
      '{}'::jsonb,now()-interval '25 minutes'
    );
  end loop;
end;
$l96_seed_layer76$;

do $l96_seed_layer81$
declare i integer;
begin
  for i in 1..3 loop
    insert into foundation.case_audit_verify_exec_events(
      event_id,environment,target_execution_event_id,verification_incident_event_id,
      action_key,cause_class,policy_fingerprint,event_type,reason_code,
      decision_snapshot,incident_snapshot,target_snapshot,before_coverage,
      action_result,after_coverage,requested_at
    ) values(
      ('96000000-0000-4000-8000-'||lpad((300+i)::text,12,'0'))::uuid,
      'production',
      ('96000000-0000-4000-8000-'||lpad((100+i)::text,12,'0'))::uuid,
      null,'run-independent-verification','verification-omission',
      lpad(to_hex(i+3),64,'0'),'executed',
      'case-audit-overdue-verification-layer77-ran',
      '{}'::jsonb,'{}'::jsonb,'{}'::jsonb,'{}'::jsonb,
      jsonb_build_object('status','recorded','test','layer96','chain',i),
      '{}'::jsonb,now()-interval '20 minutes'
    );
  end loop;
end;
$l96_seed_layer81$;

do $l96_seed_layer86$
declare i integer;
begin
  for i in 1..3 loop
    insert into foundation.case_audit_verify_reconcile_exec_events(
      event_id,environment,target_executor_event_id,reconciliation_incident_event_id,
      action_key,cause_class,policy_fingerprint,event_type,reason_code,
      decision_snapshot,incident_snapshot,target_snapshot,before_coverage,
      action_result,after_coverage,requested_at
    ) values(
      ('96000000-0000-4000-8000-'||lpad((700+i)::text,12,'0'))::uuid,
      'production',
      ('96000000-0000-4000-8000-'||lpad((300+i)::text,12,'0'))::uuid,
      null,'run-independent-reconciliation','reconciliation-omission',
      lpad(to_hex(i+6),64,'0'),'executed',
      'case-audit-overdue-reconciliation-layer82-ran',
      '{}'::jsonb,'{}'::jsonb,'{}'::jsonb,'{}'::jsonb,
      jsonb_build_object('status','recorded','test','layer96','chain',i),
      '{}'::jsonb,now()-interval '15 minutes'
    );
  end loop;
end;
$l96_seed_layer86$;

do $l96_seed_layer91$
declare i integer;
begin
  for i in 1..3 loop
    insert into foundation.case_audit_reconcile_exec_reconcile_exec_events(
      event_id,environment,target_layer86_event_id,coverage_incident_event_id,
      action_key,cause_class,policy_fingerprint,event_type,reason_code,
      decision_snapshot,incident_snapshot,target_snapshot,before_coverage,
      action_result,after_coverage,requested_at
    ) values(
      ('96000000-0000-4000-8000-'||lpad((900+i)::text,12,'0'))::uuid,
      'production',
      ('96000000-0000-4000-8000-'||lpad((700+i)::text,12,'0'))::uuid,
      null,'run-independent-layer87-reconciliation',
      'layer87-reconciliation-omission',
      lpad(to_hex(i+9),64,'0'),
      case when i=3 then 'denied' else 'executed' end,
      case when i=3 then 'case-audit-overdue-layer87-reconciliation-policy-not-admitted'
           else 'case-audit-overdue-layer87-reconciliation-ran' end,
      '{}'::jsonb,'{}'::jsonb,
      jsonb_build_object(
        'layer86EventId',
          ('96000000-0000-4000-8000-'||lpad((700+i)::text,12,'0')),
        'targetExecutorEventId',
          ('96000000-0000-4000-8000-'||lpad((300+i)::text,12,'0')),
        'reconciliationIncidentEventId',null,
        'actionKey','run-independent-reconciliation',
        'causeClass','reconciliation-omission',
        'policyFingerprint',lpad(to_hex(i+6),64,'0'),
        'eventType','executed',
        'reasonCode','case-audit-overdue-reconciliation-layer82-ran',
        'requestedAt',(
          select src.requested_at
          from foundation.case_audit_verify_reconcile_exec_events src
          where src.event_id=(
            '96000000-0000-4000-8000-'||lpad((700+i)::text,12,'0')
          )::uuid
        ),
        'layer87ReconciliationAbsent',true
      ),
      '{}'::jsonb,
      case when i=3 then null
           else jsonb_build_object(
             'foundationCaseAuditReconciliationExecutionReconciliation',
               'shine-foundation/case-audit-reconciliation-execution-reconciliation-v1',
             'schemaVersion','1.0.0',
             'status','recorded',
             'test','layer96',
             'chain',i
           ) end,
      case when i=3 then null else '{}'::jsonb end,
      case when i=2 then now()-interval '1 minute'
           else now()-interval '10 minutes' end
    );
  end loop;
end;
$l96_seed_layer91$;

insert into foundation.case_audit_layer92_coverage_incident_events(
  event_id,incident_key,environment,domain,event_type,source_state,severity,
  reason_code,evidence_fingerprint,detection_started_at,
  persistence_threshold_seconds,persistence_seconds,snapshot,occurred_at,evidence_ref
) values (
  '96000000-0000-4000-8000-000000000901'::uuid,
  'production:case_audit_layer92_reconciliation_coverage',
  'production','case_audit_layer92_reconciliation_coverage',
  'opened','gap','critical','case-audit-layer92-overdue',repeat('9',64),
  now()-interval '10 minutes',300,600,
  '{"test":"layer96"}'::jsonb,now()-interval '1 minute',
  'test:layer96:coverage-incident'
);


set local role service_role;

do $l96_execute$
declare
  r jsonb;
  replay jsonb;
  pending_result jsonb;
  denied_result jsonb;
  missing_result jsonb;
  summary jsonb;
  l91_before bigint; l91_after bigint;
  l92_before bigint; l92_after bigint;
  l87_before bigint; l87_after bigint;
  l86_before bigint; l86_after bigint;
begin
  if has_function_privilege(
       'service_role',
       'foundation.run_case_audit_layer91_execution_reconciliation_v1(uuid,timestamptz)',
       'EXECUTE'
     ) then
    raise exception 'Layer 96 direct Layer-92 bypass still available';
  end if;

  if not has_function_privilege(
       'service_role',
       'foundation.execute_case_audit_overdue_layer92_reconciliation_v1(uuid,text,timestamptz,integer)',
       'EXECUTE'
     ) then
    raise exception 'Layer 96 service-role executor unavailable';
  end if;

  select count(*) into l91_before
  from foundation.case_audit_reconcile_exec_reconcile_exec_events;
  select count(*) into l92_before
  from foundation.case_audit_reconcile_exec_reconcile_exec_reconciliations;
  select count(*) into l87_before
  from foundation.case_audit_verify_reconcile_exec_reconciliations;
  select count(*) into l86_before
  from foundation.case_audit_verify_reconcile_exec_events;

  r:=foundation.execute_case_audit_overdue_layer92_reconciliation_v1(
    '96000000-0000-4000-8000-000000000901'::uuid,'production',now(),300
  );

  if r->>'status'<>'executed'
     or r->>'reasonCode'<>'case-audit-overdue-layer92-reconciliation-ran'
     or r#>>'{actionResult,status}'<>'recorded'
     or r#>>'{actionResult,reconciliationState}'<>'missing-layer87-receipt'
     or r->>'boundedLayer92ReconcilerOnly'<>'true'
     or r->>'layer91RerunPerformed'<>'false'
     or r->>'layer87RerunPerformed'<>'false'
     or r->>'layer86RerunPerformed'<>'false' then
    raise exception 'Layer 96 eligible execution invalid: %',r;
  end if;

  if not exists(
    select 1
    from foundation.case_audit_reconcile_exec_reconcile_exec_reconciliations
    where layer91_event_id='96000000-0000-4000-8000-000000000901'::uuid
      and reconciliation_state='missing-layer87-receipt'
  ) then
    raise exception 'Layer 96 did not persist Layer-92 receipt';
  end if;

  replay:=foundation.execute_case_audit_overdue_layer92_reconciliation_v1(
    '96000000-0000-4000-8000-000000000901'::uuid,'production',now(),300
  );
  if replay->>'status'<>'existing' or replay->>'eventId'<>r->>'eventId' then
    raise exception 'Layer 96 replay invalid: %',replay;
  end if;

  pending_result:=foundation.execute_case_audit_overdue_layer92_reconciliation_v1(
    '96000000-0000-4000-8000-000000000902'::uuid,'production',now(),300
  );
  if pending_result->>'status'<>'denied'
     or pending_result->>'reasonCode'<>'case-audit-overdue-layer92-reconciliation-within-grace' then
    raise exception 'Layer 96 grace enforcement invalid: %',pending_result;
  end if;

  denied_result:=foundation.execute_case_audit_overdue_layer92_reconciliation_v1(
    '96000000-0000-4000-8000-000000000903'::uuid,'production',now(),300
  );
  if denied_result->>'status'<>'denied'
     or denied_result->>'reasonCode'<>'case-audit-overdue-layer92-reconciliation-target-not-successful' then
    raise exception 'Layer 96 target status enforcement invalid: %',denied_result;
  end if;

  missing_result:=foundation.execute_case_audit_overdue_layer92_reconciliation_v1(
    '96000000-0000-4000-8000-000000000999'::uuid,'production',now(),300
  );
  if missing_result->>'status'<>'not-applicable'
     or missing_result->>'reasonCode'<>'case-audit-overdue-layer92-reconciliation-target-not-found' then
    raise exception 'Layer 96 missing target handling invalid: %',missing_result;
  end if;

  select count(*) into l91_after
  from foundation.case_audit_reconcile_exec_reconcile_exec_events;
  select count(*) into l92_after
  from foundation.case_audit_reconcile_exec_reconcile_exec_reconciliations;
  select count(*) into l87_after
  from foundation.case_audit_verify_reconcile_exec_reconciliations;
  select count(*) into l86_after
  from foundation.case_audit_verify_reconcile_exec_events;

  if l91_after<>l91_before
     or l87_after<>l87_before
     or l86_after<>l86_before
     or l92_after<>l92_before+1 then
    raise exception 'Layer 96 reran upstream controls or produced unexpected receipt count';
  end if;

  summary:=foundation.get_case_audit_layer92_reconcile_exec_summary_v1(
    'production',25
  );
  if summary->>'totalCount'<>'3'
     or summary->>'executedCount'<>'1'
     or summary->>'deniedCount'<>'2'
     or summary->>'failedCount'<>'0'
     or summary->>'directLayer92ServiceRoleBypassAllowed'<>'false' then
    raise exception 'Layer 96 summary invalid: %',summary;
  end if;
end;
$l96_execute$;

reset role;


do $l96_privileges$
begin
  if has_function_privilege(
       'foundation_runtime',
       'foundation.execute_case_audit_overdue_layer92_reconciliation_v1(uuid,text,timestamptz,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'foundation_gateway',
       'foundation.execute_case_audit_overdue_layer92_reconciliation_v1(uuid,text,timestamptz,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'shine_core_control_plane',
       'foundation.execute_case_audit_overdue_layer92_reconciliation_v1(uuid,text,timestamptz,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'shine_defence_runtime',
       'foundation.execute_case_audit_overdue_layer92_reconciliation_v1(uuid,text,timestamptz,integer)',
       'EXECUTE'
     )
     or has_table_privilege(
       'service_role','foundation.case_audit_layer92_reconcile_exec_events','INSERT'
     )
     or not has_function_privilege(
       'foundation_runtime',
       'foundation.get_case_audit_layer92_reconcile_exec_summary_v1(text,integer)',
       'EXECUTE'
     )
     or not has_function_privilege(
       'foundation_gateway',
       'foundation.get_case_audit_layer92_reconcile_exec_summary_v1(text,integer)',
       'EXECUTE'
     )
     or not pg_has_role('foundation_gateway','foundation_runtime','MEMBER')
     or exists(
       select 1
       from pg_proc p
       join pg_namespace n on n.oid=p.pronamespace
       cross join lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a
       join pg_roles rr on rr.oid=a.grantee
       where n.nspname='foundation'
         and p.proname='get_case_audit_layer92_reconcile_exec_summary_v1'
         and rr.rolname='foundation_gateway'
         and a.privilege_type='EXECUTE'
     )
     or has_function_privilege(
       'anon',
       'foundation.execute_case_audit_overdue_layer92_reconciliation_v1(uuid,text,timestamptz,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'authenticated',
       'foundation.get_case_audit_layer92_reconcile_exec_summary_v1(text,integer)',
       'EXECUTE'
     ) then
    raise exception 'Layer 96 privilege boundary invalid';
  end if;
end;
$l96_privileges$;


do $l96_append_only$
declare id uuid;
begin
  select event_id into id
  from foundation.case_audit_layer92_reconcile_exec_events
  where event_type='executed' limit 1;

  begin
    update foundation.case_audit_layer92_reconcile_exec_events
    set reason_code='mutation' where event_id=id;
    raise exception 'Layer 96 executor history unexpectedly mutated';
  exception when sqlstate '55000' then
    null;
  end;
end;
$l96_append_only$;

rollback;
