-- Foundation Layer 76 function identifier convergence v2.
-- PostgreSQL silently truncates identifiers beyond 63 bytes. Rename the two
-- already-live truncated Layer-76 function identifiers to explicit canonical
-- length-safe names. Fresh databases already create the canonical names.

do $layer76_function_name_convergence$
begin
  if to_regprocedure(
       'foundation.foundation_promoted_release_case_audit_response_policy_fingerpr(jsonb,jsonb)'
     ) is not null
     and to_regprocedure(
       'foundation.case_audit_safe_response_policy_fingerprint_v1(jsonb,jsonb)'
     ) is null then
    alter function foundation.foundation_promoted_release_case_audit_response_policy_fingerpr(jsonb,jsonb)
      rename to case_audit_safe_response_policy_fingerprint_v1;
  end if;

  if to_regprocedure(
       'foundation.get_foundation_promoted_release_case_audit_safe_response_execut(text,integer)'
     ) is not null
     and to_regprocedure(
       'foundation.get_case_audit_safe_response_exec_summary_v1(text,integer)'
     ) is null then
    alter function foundation.get_foundation_promoted_release_case_audit_safe_response_execut(text,integer)
      rename to get_case_audit_safe_response_exec_summary_v1;
  end if;

  if to_regprocedure(
       'foundation.case_audit_safe_response_policy_fingerprint_v1(jsonb,jsonb)'
     ) is null
     or to_regprocedure(
       'foundation.get_case_audit_safe_response_exec_summary_v1(text,integer)'
     ) is null then
    raise exception 'Layer 76 canonical function identifier convergence failed';
  end if;

  if to_regprocedure(
       'foundation.foundation_promoted_release_case_audit_response_policy_fingerpr(jsonb,jsonb)'
     ) is not null then
    drop function foundation.foundation_promoted_release_case_audit_response_policy_fingerpr(jsonb,jsonb);
  end if;

  if to_regprocedure(
       'foundation.get_foundation_promoted_release_case_audit_safe_response_execut(text,integer)'
     ) is not null then
    drop function foundation.get_foundation_promoted_release_case_audit_safe_response_execut(text,integer);
  end if;
end;
$layer76_function_name_convergence$;
