# Foundation VC Readiness — layer 02/40: bounded capability declaration

8 October 2026, Brisbane. Base: bdcfa832f4bd1ca4471f3b1c9efafb3e64f594ef. Layer 01 merged as PR165.

## Delivered outcome
A registry-backed declaration builder produces two versioned, non-invocable capabilities: general Adj guidance and exact selected-record read. A missing/substituted registry app or registry outage withholds the declaration. Declared state never authorises execution. Input validation rejects unknown operations, wildcard reads, missing/invalid versions, credentials, caller identity fields and action fields. Returned declarations are fresh objects, so caller mutations cannot promote the next result to live.

This is the Foundation producer-side contract. It does not insert catalogue rows, create permission grants, implement record retrieval, invoke a model or add a competing clinic connector. Registration remains pending and is owned by VC Integrations & Security. The original roadmap's registration row is narrowed to this distinct declaration/validation deliverable under the 8 October overlap check; it must not be reported as completed production registration.

## Consumer handover
Provide the registry-confirmed VC appId and Foundation getAppManifest adapter. Test appId shine.veteran-care is synthetic. Capability IDs and private permission names are derived from the configured app slug. Integrations must review these proposed names, register the exact declarations and mount the input validator before consumer use. Unknown operations are denied.

- Adj guidance takes one question, maximum 2,000 characters. No private record references or authority fields; no passport retrieval implied. Adj owns domain semantics and VC integration; Shine AI owns model execution and its own independent admission.
- Selected-record read takes one record UUID and positive safe-integer version. The declaration requires an explicit namespaced record-read permission for appointment preparation. The consumer must independently verify identity, owner, grant, exact version and current expiry/revocation before reading; this input validator does not supply that authority.
- Output schemas are declarations only. Consumers must validate actual outputs and preserve provenance. A contentRef is not an unrestricted public or signed download URL.
- Registration metadata and schemas contain no live users, credentials or clinical text. General questions may themselves contain user-entered sensitive text; their handling remains the existing Adj/AI boundary, not a guarantee of de-identification.
- No write, DVA submission, clinic transfer, automatic alert or support catalogue is declared. Public Crisis Support keeps its existing independent route.

## Verification
60 focused tests passed locally: 10 declaration/input tests, 10 VC identity tests and 40 existing Foundation runtime tests. After schema-pattern case alignment, the 10 declaration tests were rerun successfully. CI includes both VC suites in its existing runtime test step.
All tests use controlled registry/provider fixtures; no live registry query, provider registration or runtime deployment occurred.

## Progress
02/40 source deliverables once merged and CI verified; 38 remain. Historical 225 remains a separate baseline.
Enables VC: it can prepare exact operation/schema/permission metadata for Foundation onboarding without falsely advertising a working authorised connection.
Next 03/40: dedicated-project boundary, consuming the confirmed identity contract and preserving the VC Integration owner's cutover responsibilities.

## Coordination evidence
Read VC-Seven-Room-Overlap-Check-2026-10-08.txt and current VC-ROOM-INTERFACE-CONTRACT-20261008.md. No acknowledgement or automatic delivery from other rooms is claimed. Touched Core files only: new onboarding module/tests, this receipt and additive Foundation CI test command.
