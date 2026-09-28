-- Atlas Feed Layer 3 production hardening.
-- Makes the private deny-all RLS stance explicit and adds covering indexes for
-- every composite foreign key surfaced by Supabase advisors.

create policy atlas_feed_events_client_deny
on foundation.atlas_feed_events
as restrictive
for all
to anon,authenticated
using (false)
with check (false);

create policy atlas_feed_receipts_client_deny
on foundation.atlas_feed_persistence_receipts
as restrictive
for all
to anon,authenticated
using (false)
with check (false);

create index atlas_feed_events_source_capability_fk_idx
  on foundation.atlas_feed_events(source_app_id,source_capability_id);

create index atlas_feed_events_publisher_credential_app_fk_idx
  on foundation.atlas_feed_events(publisher_credential_id,source_app_id);

create index atlas_feed_receipts_publisher_capability_fk_idx
  on foundation.atlas_feed_persistence_receipts(publisher_app_id,publisher_capability_id);
