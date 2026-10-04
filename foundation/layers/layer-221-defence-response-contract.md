# Layer 221 — Defence integration response contract

Source complete; deployment pending.

Foundation Gateway now requires Defence to return allow or deny with a non-blank string evidenceRef. Malformed responses return unavailable through the existing auditable dependency-failure path, recording a deny and defence-response-invalid stage. Valid safety decisions remain subject to Foundation permissions and audit persistence.

Validation: 24 Gateway tests passed, including six malformed Defence responses, existing veto and permitted access paths. This validates the adapter boundary; it does not deploy or prove connectivity to an external Defence service. No live grants changed.
