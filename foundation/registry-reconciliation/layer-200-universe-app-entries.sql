begin;
insert into universe.app_registry(app_key,display_name,category,lifecycle,canonical_repo,canonical_repo_status,layer_scheme,current_layer,current_layer_status,build_state,source_of_truth,evidence_note)
values
('atlas','Shine Atlas','product','active','doug-dotcom/shine-Atlas-','confirmed','Atlas layers',null,'ambiguous','planned','canonical GitHub repository','Layer 200: repository existence verified; layer and release readiness not freshly attested.'),
('wellness','Shine Wellness','product','active','doug-dotcom/Shine-Wellness','confirmed','Wellness layers',null,'ambiguous','planned','canonical GitHub repository','Layer 200: standalone repository verified, distinct from Recovery and Shine--wellness; release readiness not freshly attested.'),
('ken_sail','Shine Can Sail / Ken Sail','product','active','doug-dotcom/Shine---Ken-Sail-','confirmed','Ken Sail layers',null,'ambiguous','planned','canonical GitHub repository','Layer 200: repository existence verified; layer and release readiness not freshly attested.')
on conflict(app_key) do nothing;
update universe.app_registry set current_layer=199,current_layer_status='verified',evidence_note=coalesce(evidence_note,'') || E'\nLayer 200 reconciliation: Layer 199 source-recovery audit completed in ledger; this pointer is audit progress, not runtime certification. Historical 110-198 completion gaps remain documented.',updated_at=now(),last_verified_at=now()
where app_key='foundation' and current_layer=58 and exists(select 1 from universe.layer_events where event_key='foundation-layer199-source-recovery-20261004' and event_type='completed');
commit;
