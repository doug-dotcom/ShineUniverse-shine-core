-- Applied and verified 8 November 2026. Internal tables are postgres-owned,
-- with no runtime/client grants. Enable default-deny RLS; retain owner function access.
alter table foundation.defence_external_dispatcher_heartbeats enable row level security;
alter table foundation.defence_external_dispatch_leases enable row level security;
alter table foundation.defence_external_dispatch_events enable row level security;
alter table foundation.defence_external_dispatcher_readiness_receipts enable row level security;
