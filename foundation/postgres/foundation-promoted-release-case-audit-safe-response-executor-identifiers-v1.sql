-- Foundation Layer 76 identifier convergence.
-- PostgreSQL truncates identifiers at 63 bytes. Converge an already-created
-- Layer-76 ledger onto the same short canonical names used by fresh databases.

do $layer76_identifier_convergence$
begin
  if to_regclass(
       'foundation.foundation_promoted_release_case_audit_response_execution_event'
     ) is not null
     and to_regclass(
       'foundation.case_audit_safe_response_exec_events'
     ) is null then

    alter table foundation.foundation_promoted_release_case_audit_response_execution_event
      rename to case_audit_safe_response_exec_events;

    alter sequence foundation.foundation_promoted_release_case_audit_respo_event_sequence_seq
      rename to case_audit_safe_response_exec_events_event_sequence_seq;

    alter table foundation.case_audit_safe_response_exec_events
      rename constraint foundation_promoted_release_case_audit_response_execution__pkey
      to case_audit_safe_response_exec_events_pkey;

    alter table foundation.case_audit_safe_response_exec_events
      rename constraint foundation_promoted_release_case_audit_response_ex_event_id_key
      to case_audit_safe_response_exec_events_event_id_key;

    alter table foundation.case_audit_safe_response_exec_events
      rename constraint foundation_promoted_release_c_incident_event_id_action_key__key
      to case_audit_safe_response_exec_scope_key;

    alter table foundation.case_audit_safe_response_exec_events
      rename constraint foundation_promoted_release_case_audit_r_incident_event_id_fkey
      to case_audit_safe_response_exec_events_incident_event_id_fkey;

    alter table foundation.case_audit_safe_response_exec_events
      rename constraint foundation_promoted_release_case_audit__decision_snapshot_check
      to case_audit_safe_response_exec_events_decision_snapshot_check;

    alter table foundation.case_audit_safe_response_exec_events
      rename constraint foundation_promoted_release_case_audit__incident_snapshot_check
      to case_audit_safe_response_exec_events_incident_snapshot_check;

    alter table foundation.case_audit_safe_response_exec_events
      rename constraint foundation_promoted_release_case_audit_policy_fingerprint_check
      to case_audit_safe_response_exec_events_policy_fingerprint_check;

    alter table foundation.case_audit_safe_response_exec_events
      rename constraint foundation_promoted_release_case_audit_re_before_snapshot_check
      to case_audit_safe_response_exec_events_before_snapshot_check;

    alter table foundation.case_audit_safe_response_exec_events
      rename constraint foundation_promoted_release_case_audit_res_after_snapshot_check
      to case_audit_safe_response_exec_events_after_snapshot_check;

    alter table foundation.case_audit_safe_response_exec_events
      rename constraint foundation_promoted_release_case_audit_resp_action_result_check
      to case_audit_safe_response_exec_events_action_result_check;

    alter table foundation.case_audit_safe_response_exec_events
      rename constraint foundation_promoted_release_case_audit_respon_cause_class_check
      to case_audit_safe_response_exec_events_cause_class_check;

    alter table foundation.case_audit_safe_response_exec_events
      rename constraint foundation_promoted_release_case_audit_respon_environment_check
      to case_audit_safe_response_exec_events_environment_check;

    alter table foundation.case_audit_safe_response_exec_events
      rename constraint foundation_promoted_release_case_audit_respon_reason_code_check
      to case_audit_safe_response_exec_events_reason_code_check;

    alter table foundation.case_audit_safe_response_exec_events
      rename constraint foundation_promoted_release_case_audit_respons_action_key_check
      to case_audit_safe_response_exec_events_action_key_check;

    alter table foundation.case_audit_safe_response_exec_events
      rename constraint foundation_promoted_release_case_audit_respons_event_type_check
      to case_audit_safe_response_exec_events_event_type_check;

    alter table foundation.case_audit_safe_response_exec_events
      rename constraint foundation_promoted_release_case_audit_response_execution_check
      to case_audit_safe_response_exec_events_shape_check;

    alter index foundation.foundation_promoted_release_case_audit_response_execution_incid
      rename to case_audit_safe_response_exec_incident_idx;

    alter index foundation.foundation_promoted_release_case_audit_response_execution_actio
      rename to case_audit_safe_response_exec_action_idx;

    alter trigger foundation_promoted_release_case_audit_response_execution_appen
      on foundation.case_audit_safe_response_exec_events
      rename to case_audit_safe_response_exec_append_only;
  end if;
end;
$layer76_identifier_convergence$;
