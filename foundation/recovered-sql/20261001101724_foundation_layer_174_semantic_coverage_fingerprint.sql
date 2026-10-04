
create or replace function foundation.get_case_audit_layer172_coverage_semantic_fingerprint_v1(
  p_coverage jsonb
)
returns text
language plpgsql
immutable
security definer
set search_path=''
as $$
declare
  v_semantic jsonb;
begin
  if p_coverage is null
     or jsonb_typeof(p_coverage)<>'object'
     or p_coverage->>'foundationCaseAuditLayer172ReconciliationCoverage'
          is distinct from
          'shine-foundation/case-audit-layer172-reconciliation-coverage-v1'
     or p_coverage->>'schemaVersion' is distinct from '1.0.0' then
    raise exception 'case-audit-layer172-semantic-fingerprint-input-invalid';
  end if;

  v_semantic:=jsonb_build_object(
    'state',p_coverage->>'state',
    'reasonCode',p_coverage->>'reasonCode',
    'successfulLayer171ExecutionCount',coalesce((p_coverage->>'successfulLayer171ExecutionCount')::integer,0),
    'layer172ReconciliationRequiredCount',coalesce((p_coverage->>'layer172ReconciliationRequiredCount')::integer,0),
    'layer172ReconciliationReceiptCount',coalesce((p_coverage->>'layer172ReconciliationReceiptCount')::integer,0),
    'reconciledCount',coalesce((p_coverage->>'reconciledCount')::integer,0),
    'pendingCount',coalesce((p_coverage->>'pendingCount')::integer,0),
    'overdueCount',coalesce((p_coverage->>'overdueCount')::integer,0),
    'invalidLayer172ReconciliationCount',coalesce((p_coverage->>'invalidLayer172ReconciliationCount')::integer,0),
    'missingLayer167ReceiptCount',coalesce((p_coverage->>'missingLayer167ReceiptCount')::integer,0),
    'executionReceiptMismatchCount',coalesce((p_coverage->>'executionReceiptMismatchCount')::integer,0),
    'admissionValidationDriftCount',coalesce((p_coverage->>'admissionValidationDriftCount')::integer,0),
    'policyDriftCount',coalesce((p_coverage->>'policyDriftCount')::integer,0),
    'incidentIntegrityDriftCount',coalesce((p_coverage->>'incidentIntegrityDriftCount')::integer,0),
    'incidentStateDriftCount',coalesce((p_coverage->>'incidentStateDriftCount')::integer,0),
    'incidentBindingDriftCount',coalesce((p_coverage->>'incidentBindingDriftCount')::integer,0),
    'semanticCurrentnessDriftCount',coalesce((p_coverage->>'semanticCurrentnessDriftCount')::integer,0),
    'problemCount',coalesce((p_coverage->>'problemCount')::integer,0)
  );

  return encode(
    extensions.digest(convert_to(v_semantic::text,'UTF8'),'sha256'),
    'hex'
  );
end $$;

revoke all on function foundation.get_case_audit_layer172_coverage_semantic_fingerprint_v1(
  jsonb
) from public,anon,authenticated,foundation_runtime,foundation_gateway,
       shine_core_control_plane,shine_defence_runtime;

grant execute on function foundation.get_case_audit_layer172_coverage_semantic_fingerprint_v1(
  jsonb
) to service_role;
