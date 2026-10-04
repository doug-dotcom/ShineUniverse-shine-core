# Layer 210 — Temporary grant expiry

Completed 4 October 2026. Permission engine now denies active grants with supplied, malformed expiresAt or notBefore values as grant-time-invalid. Previously failed Date.parse comparisons could skip these restrictions. Missing/null optional timing retains existing indefinite-grant semantics. Revoked/inactive states retain precedence.

Verification: 39 local permission-engine and Gateway core tests pass. Added boundary tests allow one millisecond before expiry and deny at/after expiry; malformed string/non-string timing is denied. An independent valid matching grant still permits access regardless of invalid-grant ordering. Existing CI executes these suites.

Source complete; deployment pending. No existing grant rows changed. This checks JavaScript temporal enforcement; it does not certify database expiry enforcement or force all grants to have an expiry.
