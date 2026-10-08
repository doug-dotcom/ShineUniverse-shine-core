# VC readiness — layer 26: read-only retrieval

8 October 2026, Brisbane. Baseline 02a4ae810d08687f963132548ab7df2b04ff99c5.
After merge: 26/40 source-verified producer layers; 14 remain (35%).

## Enables VC

createVeteranCareReadOnlyMemoryRetriever joins layer-25 exact memory consent to one trusted private read adapter and a second full permission evaluation before returning content. Missing user identity/link or memory consent stops before content lookup. Write operations, broad searches, caller owner overrides and accessors are rejected. Selected request and credential scalars are captured before asynchronous identity work.

The adapter receives only the verified app/client/owner/link, exact memory ID/version/category, read operation/scope, approved purpose/preparation, grant and permission revision. It receives no raw credentials, arbitrary query or write payload. Its result must be a single plain object containing exactly memoryId,memoryVersion,ownerShineId,category,content. Every identity dimension must match the approved selection, and content must be a nonempty string of at most 16,384 JavaScript UTF-16 code units. Extra fields, other users/versions/categories, non-text and accessor content are withheld. This validates shape and scope; it does not infer or certify the semantics of returned text.

Content is frozen as a scalar snapshot before the second complete scope evaluation. The final decision must equal the initial envelope, including link, grant, permission revision and deadline. Revocation, withdrawn link, newly active replacement grant, changed revision, outage, expiry or clock regression withholds the whole result. Adapter exceptions expose no private message. retrievalPerformed means the adapter was invoked, not successful disclosure or proof of a production read.

Success returns private-memory-read-ready with audience vc-trusted-server and a frozen selected result. modelDisclosurePermitted and memoryWritePermitted stay false; requiresFreshDisclosureCheck is true. This is an internal server read result, never an AI/model prompt, browser response, signed link or external transport grant. It must not be logged or serialised to an external recipient automatically.

## Ownership and interface

Foundation owns the guarded retrieval contract and reuses existing identity/consent checks without counting them again. L owns the real private memory store, selected read adapter and enforced read-only database role. VC Integrations owns protected consumer wiring and recipient/disclosure enforcement. AI owns any external model/context authority; no AI policy is extended.

Input is the exact layer-25 {authContext,companionAuthContext,request:{operation:'read',memoryId,memoryVersion,preparationId}} shape. Required readSelectedMemory(query) must perform a single selected server-private read and return the exact bounded row. This factory cannot sandbox callbacks or prove database read-only privileges: the adapter must not write, perform unrelated reads, transmit content, issue usable URLs, or call a model before the final gate. A callback violating that contract would already have crossed the boundary and cannot be undone by withholding the result.

The result is point-in-time evidence without transaction locks. Later disclosure needs current scope/consent and recipient checks at its real execution boundary. Adapter timeouts, actual L database permissions/queries, bounded network transport and authenticated live evidence remain consumer integration work. No clinical memory is fetched here, no real credential is used, and no database, UI, hosted route or consumer deployment changes. No cross-room acknowledgement is claimed.

## Evidence

10 focused tests cover one immutable selected result and credential-free adapter query; write/search/override/accessor refusal; user/consent denial before retrieval; returned identity/extra-field validation; bounded text and accessor safety; in-flight withdrawal; current revision/link/grant replacement; release expiry/clock failure/regression; private exceptions/final authority failures; and input/result mutation capture.
317/317 local onboarding/runtime tests passed; diff check passed. The suite is registered in Foundation CI; Foundation and independent Defence CI must pass before merge.

Next: layer 27, AI tool authority.
