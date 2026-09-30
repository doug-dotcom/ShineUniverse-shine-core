-- Shine Defence GitHub OIDC replay runtime read policy v1.
-- RLS remains fail-closed for public/application roles while allowing the
-- dedicated Shine Defence runtime role to inspect replay-control evidence.

create policy shine_defence_runtime_github_oidc_operation_bindings_select
on foundation.github_oidc_operation_bindings
for select
to shine_defence_runtime
using (true);

create policy shine_defence_runtime_github_oidc_operation_events_select
on foundation.github_oidc_operation_events
for select
to shine_defence_runtime
using (true);

create policy shine_defence_runtime_github_oidc_replay_alert_events_select
on foundation.github_oidc_replay_alert_events
for select
to shine_defence_runtime
using (true);
