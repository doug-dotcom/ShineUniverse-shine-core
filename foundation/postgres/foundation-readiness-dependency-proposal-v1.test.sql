begin;

do $contract$
declare a foundation.readiness_incident_response_actions%rowtype;
begin
 select * into a from foundation.readiness_incident_response_actions
 where action_key='propose-dependency-remediation';
 if a.action_key is null or a.action_class<>'proposal'
    or a.mutates_authoritative_truth then
  raise exception 'Layer 47 requires non-mutating proposal action registration';
 end if;
 if has_table_privilege('foundation_runtime','foundation.readiness_dependency_remediation_proposals','INSERT')
    or has_table_privilege('foundation_gateway','foundation.readiness_dependency_remediation_proposals','INSERT') then
  raise exception 'Runtime/gateway must not directly insert dependency proposals';
 end if;
 if not has_function_privilege('service_role','foundation.propose_readiness_dependency_remediation_v1(text,timestamp with time zone)','EXECUTE')
    or has_function_privilege('foundation_gateway','foundation.propose_readiness_dependency_remediation_v1(text,timestamp with time zone)','EXECUTE') then
  raise exception 'Proposal execution grants invalid';
 end if;
end;
$contract$;

rollback;
