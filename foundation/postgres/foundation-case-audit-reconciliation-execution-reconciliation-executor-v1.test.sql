begin;

-- Minimal real dependency chain for three Layer-86 targets.
insert into foundation.foundation_promoted_release_case_audit_incident_events(
  event_id,incident_key,environment,domain,event_type,source_state,severity,
  reason_code,evidence_fingerprint,case_audit_observation_id,
  detection_started_at,persistence_threshold_seconds,persistence_seconds,
  snapshot,occurred_at,evidence_ref
) values (
  '91000000-0000-4000-8000-000000000001'::uuid,
  'production:promoted_release_case_audit','production',
  'promoted_release_case_audit','opened','gap','critical',
  'promotion-case-audit-gap',repeat('1',64),null,
  now()-interval '30 minutes',300,1200,'{"test":"layer91"}'::jsonb,
  now()-interval '20 minutes','test:layer91:case-audit-incident'
);

insert into foundation.case_audit_verify_incident_events(
  event_id,incident_key,environment,domain,event_type,source_state,severity,
  reason_code,evidence_fingerprint,detection_started_at,
  persistence_threshold_seconds,persistence_seconds,snapshot,occurred_at,evidence_ref
) values (
  '91000000-0000-4000-8000-000000000201'::uuid,
  'production:case_audit_verification_coverage','production',
  'case_audit_verification_coverage','opened','gap','critical',
  'case-audit-safe-response-verification-overdue',repeat('2',64),
  now()-interval '20 minutes',300,900,'{"test":"layer91"}'::jsonb,
  now()-interval '15 minutes','test:layer91:verification-incident'
);

do $l91_seed_layer76$
declare i integer;
begin
  for i in 1..3 loop
    insert into foundation.case_audit_safe_response_exec_events(
      event_id,environment,incident_event_id,action_key,cause_class,
      policy_fingerprint,event_type,reason_code,decision_snapshot,
      incident_snapshot,before_snapshot,action_result,after_snapshot,requested_at
    ) values (
      ('91000000-0000-4000-8000-'||lpad((100+i)::text,12,'0'))::uuid,
      'production','91000000-0000-4000-8000-000000000001'::uuid,
      'record-fresh-promotion-case-audit-observation','observer-freshness',
      repeat(i::text,64),'executed','test-layer91-layer76',
      '{}'::jsonb,'{}'::jsonb,'{}'::jsonb,
      jsonb_build_object('status','recorded','test','layer91'),
      '{}'::jsonb,now()-interval '20 minutes'
    );
  end loop;
end;
$l91_seed_layer76$;

do $l91_seed_layer81$
declare i integer;
begin
  for i in 1..3 loop
    insert into foundation.case_audit_verify_exec_events(
      event_id,environment,target_execution_event_id,verification_incident_event_id,
      action_key,cause_class,policy_fingerprint,event_type,reason_code,
      decision_snapshot,incident_snapshot,target_snapshot,before_coverage,
      action_result,after_coverage,requested_at
    ) values (
      ('91000000-0000-4000-8000-'||lpad((300+i)::text,12,'0'))::uuid,
      'production',
      ('91000000-0000-4000-8000-'||lpad((100+i)::text,12,'0'))::uuid,
      '91000000-0000-4000-8000-000000000201'::uuid,
      'run-independent-verification','verification-omission',repeat((i+3)::text,64),
      'executed','case-audit-overdue-verification-layer77-ran',
      '{}'::jsonb,'{}'::jsonb,'{}'::jsonb,'{}'::jsonb,
      jsonb_build_object('status','recorded','test','layer91'),
      '{}'::jsonb,now()-interval '15 minutes'
    );
  end loop;
end;
$l91_seed_layer81$;

insert into foundation.case_audit_verify_reconcile_incident_events(
  event_id,incident_key,environment,domain,event_type,source_state,severity,
  reason_code,evidence_fingerprint,detection_started_at,
  persistence_threshold_seconds,persistence_seconds,snapshot,occurred_at,evidence_ref
) values (
  '91000000-0000-4000-8000-000000000401'::uuid,
  'production:case_audit_verification_reconciliation_coverage','production',
  'case_audit_verification_reconciliation_coverage','opened','gap','critical',
  'case-audit-verify-reconcile-overdue',repeat('8',64),
  now()-interval '15 minutes',300,600,'{"test":"layer91"}'::jsonb,
  now()-interval '10 minutes','test:layer91:reconciliation-incident'
);

do $l91_seed_layer86$
declare i integer;
begin
  for i in 1..3 loop
    insert into foundation.case_audit_verify_reconcile_exec_events(
      event_id,environment,target_executor_event_id,reconciliation_incident_event_id,
      action_key,cause_class,policy_fingerprint,event_type,reason_code,
      decision_snapshot,incident_snapshot,target_snapshot,before_coverage,
      action_result,after_coverage,requested_at
    ) values (
      ('91000000-0000-4000-8000-'||lpad((700+i)::text,12,'0'))::uuid,
      'production',
      ('91000000-0000-4000-8000-'||lpad((300+i)::text,12,'0'))::uuid,
      '91000000-0000-4000-8000-000000000401'::uuid,
      'run-independent-reconciliation','reconciliation-omission',
      repeat((i+6)::text,64),
      case when i=3 then 'denied' else 'executed' end,
      case when i=3 then 'case-audit-overdue-reconciliation-policy-not-admitted'
           else 'case-audit-overdue-reconciliation-layer82-ran' end,
      '{}'::jsonb,'{}'::jsonb,'{}'::jsonb,'{}'::jsonb,
      case when i=3 then null
           else jsonb_build_object('status','recorded','test','layer91') end,
      case when i=3 then null else '{}'::jsonb end,
      case when i=2 then now()-interval '1 minute'
           else now()-interval '10 minutes' end
    );
  end loop;
end;
$l91_seed_layer86$;

do $l91_seed_layer89$
declare coverage jsonb;
begin
  coverage:=foundation.get_case_audit_reconcile_exec_reconciliation_coverage_v1(
    'production',now(),300,100
  );

  if coverage->>'state'<>'gap'
     or coverage->>'overdueCount'<>'1'
     or coverage->>'pendingCount'<>'1' then
    raise exception 'Layer 91 seed Layer-88 coverage invalid: %',coverage;
  end if;

  insert into foundation.case_audit_reconcile_exec_coverage_incident_events(
    event_id,incident_key,environment,domain,event_type,source_state,severity,
    reason_code,evidence_fingerprint,detection_started_at,
    persistence_threshold_seconds,persistence_seconds,snapshot,occurred_at,evidence_ref
  ) values (
    '91000000-0000-4000-8000-000000000901'::uuid,
    'production:case_audit_reconciliation_execution_reconciliation_coverage',
    'production','case_audit_reconciliation_execution_reconciliation_coverage',
    'opened','gap','critical',coverage->>'reasonCode',
    foundation.case_audit_reconcile_exec_coverage_incident_fingerprint_v1(coverage),
    now()-interval '10 minutes',300,600,coverage,
    now()-interval '1 minute','test:layer91:coverage-incident'
  );
end;
$l91_seed_layer89$;

set local role service_role;

do $l91_execute$
declare
  r jsonb;
  replay jsonb;
  pending_result jsonb;
  denied_result jsonb;
  missing_result jsonb;
  summary jsonb;
  l81_before bigint; l81_after bigint;
  l82_before bigint; l82_after bigint;
  l86_before bigint; l86_after bigint;
  l87_before bigint; l87_after bigint;
begin
  if has_function_privilege(
       'service_role',
       'foundation.run_case_audit_verify_reconcile_exec_reconciliation_v1(uuid,timestamptz)',
       'EXECUTE'
     ) then
    raise exception 'Layer 91 direct Layer-87 bypass still available';
  end if;

  if not has_function_privilege(
       'service_role',
       'foundation.execute_case_audit_overdue_layer87_reconciliation_v1(uuid,text,timestamptz,integer)',
       'EXECUTE'
     ) then
    raise exception 'Layer 91 service-role executor unavailable';
  end if;

  select count(*) into l81_before from foundation.case_audit_verify_exec_events;
  select count(*) into l82_before from foundation.case_audit_verify_exec_reconciliations;
  select count(*) into l86_before from foundation.case_audit_verify_reconcile_exec_events;
  select count(*) into l87_before from foundation.case_audit_verify_reconcile_exec_reconciliations;

  r:=foundation.execute_case_audit_overdue_layer87_reconciliation_v1(
    '91000000-0000-4000-8000-000000000701'::uuid,'production',now(),300
  );

  if r->>'status'<>'executed'
     or r->>'reasonCode'<>'case-audit-overdue-layer87-reconciliation-ran'
     or r#>>'{actionResult,status}'<>'recorded'
     or r#>>'{actionResult,reconciliationState}'<>'missing-layer82-receipt'
     or r->>'boundedLayer87ReconcilerOnly'<>'true'
     or r->>'layer86RerunPerformed'<>'false'
     or r->>'layer82RerunPerformed'<>'false'
     or r->>'layer81RerunPerformed'<>'false'
     or r->>'verificationRerunPerformed'<>'false' then
    raise exception 'Layer 91 eligible execution invalid: %',r;
  end if;

  if not exists(
    select 1 from foundation.case_audit_verify_reconcile_exec_reconciliations
    where layer86_event_id='91000000-0000-4000-8000-000000000701'::uuid
      and reconciliation_state='missing-layer82-receipt'
  ) then
    raise exception 'Layer 91 did not persist Layer-87 receipt';
  end if;

  replay:=foundation.execute_case_audit_overdue_layer87_reconciliation_v1(
    '91000000-0000-4000-8000-000000000701'::uuid,'production',now(),300
  );
  if replay->>'status'<>'existing' or replay->>'eventId'<>r->>'eventId' then
    raise exception 'Layer 91 replay invalid: %',replay;
  end if;

  pending_result:=foundation.execute_case_audit_overdue_layer87_reconciliation_v1(
    '91000000-0000-4000-8000-000000000702'::uuid,'production',now(),300
  );
  if pending_result->>'status'<>'denied'
     or pending_result->>'reasonCode'<>'case-audit-overdue-layer87-reconciliation-within-grace' then
    raise exception 'Layer 91 grace enforcement invalid: %',pending_result;
  end if;

  denied_result:=foundation.execute_case_audit_overdue_layer87_reconciliation_v1(
    '91000000-0000-4000-8000-000000000703'::uuid,'production',now(),300
  );
  if denied_result->>'status'<>'denied'
     or denied_result->>'reasonCode'<>'case-audit-overdue-layer87-reconciliation-target-not-successful' then
    raise exception 'Layer 91 target status enforcement invalid: %',denied_result;
  end if;

  missing_result:=foundation.execute_case_audit_overdue_layer87_reconciliation_v1(
    '91000000-0000-4000-8000-000000000999'::uuid,'production',now(),300
  );
  if missing_result->>'status'<>'not-applicable'
     or missing_result->>'reasonCode'<>'case-audit-overdue-layer87-reconciliation-target-not-found' then
    raise exception 'Layer 91 missing target handling invalid: %',missing_result;
  end if;

  select count(*) into l81_after from foundation.case_audit_verify_exec_events;
  select count(*) into l82_after from foundation.case_audit_verify_exec_reconciliations;
  select count(*) into l86_after from foundation.case_audit_verify_reconcile_exec_events;
  select count(*) into l87_after from foundation.case_audit_verify_reconcile_exec_reconciliations;

  if l81_after<>l81_before or l82_after<>l82_before or l86_after<>l86_before
     or l87_after<>l87_before+1 then
    raise exception 'Layer 91 reran upstream controls or produced unexpected receipt count';
  end if;

  summary:=foundation.get_case_audit_reconcile_exec_reconcile_exec_summary_v1('production',25);
  if summary->>'totalCount'<>'3'
     or summary->>'executedCount'<>'1'
     or summary->>'deniedCount'<>'2'
     or summary->>'failedCount'<>'0'
     or summary->>'directLayer87ServiceRoleBypassAllowed'<>'false' then
    raise exception 'Layer 91 summary invalid: %',summary;
  end if;
end;
$l91_execute$;

reset role;

do $l91_privileges$
begin
  if has_function_privilege(
       'foundation_runtime',
       'foundation.execute_case_audit_overdue_layer87_reconciliation_v1(uuid,text,timestamptz,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'foundation_gateway',
       'foundation.execute_case_audit_overdue_layer87_reconciliation_v1(uuid,text,timestamptz,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'shine_core_control_plane',
       'foundation.execute_case_audit_overdue_layer87_reconciliation_v1(uuid,text,timestamptz,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'shine_defence_runtime',
       'foundation.execute_case_audit_overdue_layer87_reconciliation_v1(uuid,text,timestamptz,integer)',
       'EXECUTE'
     )
     or has_table_privilege(
       'service_role','foundation.case_audit_reconcile_exec_reconcile_exec_events','INSERT'
     )
     or not has_function_privilege(
       'foundation_runtime',
       'foundation.get_case_audit_reconcile_exec_reconcile_exec_summary_v1(text,integer)',
       'EXECUTE'
     )
     or not has_function_privilege(
       'foundation_gateway',
       'foundation.get_case_audit_reconcile_exec_reconcile_exec_summary_v1(text,integer)',
       'EXECUTE'
     )
     or not pg_has_role('foundation_gateway','foundation_runtime','MEMBER')
     or exists(
       select 1
       from pg_proc p
       join pg_namespace n on n.oid=p.pronamespace
       cross join lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a
       join pg_roles r on r.oid=a.grantee
       where n.nspname='foundation'
         and p.proname='get_case_audit_reconcile_exec_reconcile_exec_summary_v1'
         and r.rolname='foundation_gateway'
         and a.privilege_type='EXECUTE'
     )
     or has_function_privilege(
       'anon',
       'foundation.execute_case_audit_overdue_layer87_reconciliation_v1(uuid,text,timestamptz,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'authenticated',
       'foundation.get_case_audit_reconcile_exec_reconcile_exec_summary_v1(text,integer)',
       'EXECUTE'
     ) then
    raise exception 'Layer 91 privilege boundary invalid';
  end if;
end;
$l91_privileges$;

do $l91_append_only$
declare id uuid;
begin
  select event_id into id
  from foundation.case_audit_reconcile_exec_reconcile_exec_events
  where event_type='executed' limit 1;

  begin
    update foundation.case_audit_reconcile_exec_reconcile_exec_events
    set reason_code='mutation' where event_id=id;
    raise exception 'Layer 91 executor history unexpectedly mutated';
  exception when sqlstate '55000' then
    null;
  end;
end;
$l91_append_only$;

rollback;
