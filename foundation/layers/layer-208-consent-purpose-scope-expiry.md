# Layer 208 — Consent purpose, scope and expiry

Completed 4 October 2026. Existing app consent checks exact scope and purpose against the manifest, and capability consent forwards exact capability, purpose and expiry. Capability consent now rejects non-string, unparseable, elapsed or exactly-current explicit expiry before identity verification or grant persistence. Omitted/null expiry retains the existing policy; this change does not impose a new universal grant lifetime.

Verification: 15 local consent service/client tests pass. Added regressions verify no proof or grant write for invalid expiry, exact forwarding of future expiry/capability/purpose, and denial of undeclared scope or purpose. Existing consent boolean, ownership, Defence veto, credential and failure tests pass. Tests run in the existing CI suite.

Source complete; deployment pending. No consent or grant records changed. App access consent and integration capability consent retain their distinct existing contracts; no new expiry field was added to app access consent.
