-- Foundation Layer 109 hosted wiring.
-- Reuse the existing five-minute Foundation coverage-incident cron slot rather
-- than adding another concurrent job. Layer-94, Layer-99, Layer-104 and
-- Layer-109 sentinels execute sequentially and are failure-isolated inside one
-- owner-private wrapper.

create or replace function foundation.run_case_audit_coverage_incident_sentinels_hosted_v1()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $layer109_hosted$
declare
  v_observed_at timestamptz := now();
  v_layer94 jsonb;
  v_layer99 jsonb;
  v_layer104 jsonb;
  v_layer109 jsonb;
  v_layer94_error text;
  v_layer99_error text;
  v_layer104_error text;
  v_layer109_error text;
begin
  begin
    v_layer94 := foundation.run_case_audit_layer92_coverage_incident_sentinel_v1(
      'production',v_observed_at,300,300
    );
  exception when others then
    v_layer94_error := sqlerrm;
    raise warning 'Layer-94 coverage incident sentinel failed: %',v_layer94_error;
  end;

  begin
    v_layer99 := foundation.run_case_audit_layer97_coverage_incident_sentinel_v1(
      'production',v_observed_at,300,300
    );
  exception when others then
    v_layer99_error := sqlerrm;
    raise warning 'Layer-99 coverage incident sentinel failed: %',v_layer99_error;
  end;

  begin
    v_layer104 := foundation.run_case_audit_layer102_coverage_incident_sentinel_v1(
      'production',v_observed_at,300,300
    );
  exception when others then
    v_layer104_error := sqlerrm;
    raise warning 'Layer-104 coverage incident sentinel failed: %',v_layer104_error;
  end;

  begin
    v_layer109 := foundation.run_case_audit_layer107_coverage_incident_sentinel_v1(
      'production',v_observed_at,300,300
    );
  exception when others then
    v_layer109_error := sqlerrm;
    raise warning 'Layer-109 coverage incident sentinel failed: %',v_layer109_error;
  end;

  return jsonb_build_object(
    'foundationCaseAuditCoverageIncidentHostedSentinels',
      'shine-foundation/case-audit-coverage-incident-hosted-sentinels-v1',
    'schemaVersion','1.2.0',
    'observedAt',v_observed_at,
    'layer94',v_layer94,
    'layer94Error',v_layer94_error,
    'layer99',v_layer99,
    'layer99Error',v_layer99_error,
    'layer104',v_layer104,
    'layer104Error',v_layer104_error,
    'layer109',v_layer109,
    'layer109Error',v_layer109_error,
    'additionalCronJobCreated',false
  );
end;
$layer109_hosted$;

revoke all on function foundation.run_case_audit_coverage_incident_sentinels_hosted_v1()
  from public,anon,authenticated,foundation_runtime,foundation_gateway,
       shine_core_control_plane,shine_defence_runtime,service_role;

select cron.schedule(
  'shine-foundation-case-audit-layer92-coverage-incident-5m',
  '1,6,11,16,21,26,31,36,41,46,51,56 * * * *',
  $$select foundation.run_case_audit_coverage_incident_sentinels_hosted_v1();$$
);
