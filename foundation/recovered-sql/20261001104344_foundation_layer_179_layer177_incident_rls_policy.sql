
create policy "service_role_only_layer177_incidents"
on foundation.case_audit_layer177_coverage_incident_events
for all to service_role
using (true) with check (true);
