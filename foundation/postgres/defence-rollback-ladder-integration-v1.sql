-- Shine Defence full-estate integration for rollback readiness v1.

create or replace function foundation.get_defence_full_estate_summary_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, foundation
as $$
declare
  v_estate jsonb;
  v_supabase jsonb;
  v_transitions jsonb;
  v_source_heads jsonb;
  v_transition_coverage jsonb;
  v_admission jsonb;
  v_rollback jsonb;
  v_ladder jsonb;
  v_state text;
begin
  v_estate := foundation.get_defence_estate_summary_v1();
  v_supabase := foundation.get_defence_supabase_runtime_receipt_summary_v1();
  v_transitions := foundation.get_defence_railway_transition_summary_v1();
  v_source_heads := foundation.get_defence_release_source_head_summary_v1();
  v_transition_coverage := foundation.get_defence_release_transition_coverage_v1();
  v_admission := foundation.get_defence_release_admission_summary_v1();
  v_rollback := foundation.get_defence_rollback_readiness_summary_v1();
  v_ladder := foundation.get_defence_rollback_ladder_v1();

  v_state := case
    when v_estate->>'state'='fail'
      or v_supabase->>'state'='fail'
      or v_transitions->>'state'='fail'
      then 'fail'
    when v_estate->>'state'='warning'
      or v_supabase->>'state'='warning'
      or v_transitions->>'state'='warning'
      or v_source_heads->>'state'='warning'
      or v_transition_coverage->>'state'='warning'
      or v_admission->>'state'='warning'
      or v_rollback->>'state'='warning'
      or v_ladder->>'state'='warning'
      then 'warning'
    else 'pass'
  end;

  return jsonb_build_object(
    'defenceFullEstateSummary','shine-defence/full-estate-summary-v1',
    'schemaVersion','1.6.0',
    'state',v_state,
    'estate',v_estate,
    'supabaseRuntimeReceipts',v_supabase,
    'railwayReleaseTransitions',v_transitions,
    'releaseSourceHeads',v_source_heads,
    'releaseTransitionCoverage',v_transition_coverage,
    'releaseAdmission',v_admission,
    'rollbackReadiness',v_rollback,
    'rollbackLadder',v_ladder,
    'evaluatedAt',now()
  );
end;
$$;

revoke all on function foundation.get_defence_full_estate_summary_v1()
  from public,anon,authenticated;
grant execute on function foundation.get_defence_full_estate_summary_v1()
  to foundation_runtime,shine_defence_runtime,service_role;
