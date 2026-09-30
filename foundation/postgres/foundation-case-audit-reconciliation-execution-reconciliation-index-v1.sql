-- Foundation Layer 87 supporting index.
-- Covers the Layer-87 foreign key back to the exact Layer-82 reconciliation
-- receipt used to independently prove the Layer-86 execution claim.

create index if not exists case_audit_verify_reconcile_exec_reconcile_layer82_idx
  on foundation.case_audit_verify_reconcile_exec_reconciliations(
    layer82_reconciliation_id
  );
