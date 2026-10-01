-- Shine Defence authority-sync heartbeat integration v1.
-- Add signed authority-sync freshness to the final estate posture without
-- weakening any existing estate, replay, release or rollback gates.

create or replace function foundation.get_defence_full_estate_summary_v1()
returns jsonb
language plpgsql
volatile
security definer
set search_path = pg_catalog, foundation
as $full_estate_authority_sync$
declare
  v_estate jsonb;
  v_supabase jsonb;
  v_transitions jsonb;
  v_source_heads jsonb;
  v_transition_coverage jsonb;
  v_admission jsonb;
  v_rollback jsonb;
  v_ladder jsonb;
  v_oidc_replay jsonb;
  v_authority_parity jsonb;
  v_authority_sync jsonb;
  v_authority_heartbeat_sentinel jsonb;
  v_correlated_transport_attribution jsonb;
  v_state text;
  v_evaluated_at timestamptz := clock_timestamp();
begin
  v_estate := foundation.get_defence_estate_summary_v1();
  v_supabase := foundation.get_defence_supabase_runtime_receipt_summary_v1();
  v_transitions := foundation.get_defence_railway_transition_summary_v1();
  v_source_heads := foundation.get_defence_release_source_head_summary_v1();
  v_authority_parity := foundation.get_defence_release_authority_parity_summary_v1();
  v_authority_sync := foundation.get_defence_attestation_authority_sync_summary_v1(
    v_evaluated_at,5400
  );
  v_authority_heartbeat_sentinel :=
    foundation.get_defence_attestation_authority_heartbeat_sentinel_v1(
      v_evaluated_at,3600,5400
    );
  v_correlated_transport_attribution :=
    foundation.get_defence_correlated_transport_attribution_v1(
      v_evaluated_at,21600,3,0.5
    );
  v_transition_coverage := foundation.get_defence_release_transition_coverage_v1();
  v_admission := foundation.get_defence_release_admission_summary_v1();
  v_rollback := foundation.get_defence_rollback_readiness_summary_v1();
  v_ladder := foundation.get_defence_rollback_ladder_v1();
  v_oidc_replay := foundation.get_defence_github_oidc_replay_summary_v1(v_evaluated_at,86400);

  v_state := case
    when v_oidc_replay->>'state'='fail'
      or v_estate->>'state'='fail'
      or v_supabase->>'state'='fail'
      or v_transitions->>'state'='fail'
      then 'fail'
    when v_estate->>'state'='warning'
      or v_supabase->>'state'='warning'
      or v_transitions->>'state'='warning'
      or v_source_heads->>'state'='warning'
      or v_authority_parity->>'state'='warning'
      or v_authority_sync->>'state'='warning'
      or v_authority_heartbeat_sentinel->>'state'='warning'
      or v_transition_coverage->>'state'='warning'
      or v_admission->>'state'='warning'
      or v_rollback->>'state'='warning'
      or v_ladder->>'state'='warning'
      then 'warning'
    else 'pass'
  end;

  return jsonb_build_object(
    'defenceFullEstateSummary','shine-defence/full-estate-summary-v1',
    'schemaVersion','1.11.0',
    'state',v_state,
    'estate',v_estate,
    'supabaseRuntimeReceipts',v_supabase,
    'railwayReleaseTransitions',v_transitions,
    'releaseSourceHeads',v_source_heads,
    'releaseAuthorityParity',v_authority_parity,
    'attestationAuthoritySync',v_authority_sync,
    'attestationAuthorityHeartbeatSentinel',v_authority_heartbeat_sentinel,
    'correlatedTransportAttribution',v_correlated_transport_attribution,
    'releaseTransitionCoverage',v_transition_coverage,
    'releaseAdmission',v_admission,
    'rollbackReadiness',v_rollback,
    'rollbackLadder',v_ladder,
    'githubOidcReplay',v_oidc_replay,
    'evaluatedAt',v_evaluated_at
  );
end;
$full_estate_authority_sync$;

revoke all on function foundation.get_defence_full_estate_summary_v1()
  from public,anon,authenticated;
grant execute on function foundation.get_defence_full_estate_summary_v1()
  to foundation_runtime,shine_defence_runtime,service_role;
