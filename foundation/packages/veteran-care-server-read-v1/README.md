# Foundation VC server read package

Internal Node ESM package: `@shine-foundation/veteran-care-server-read` v1.0.0.
Requires Node 22 or later. Not published to npm.

From an inspected Core checkout, build outside the source tree:
```sh
node foundation/packages/veteran-care-server-read-v1/build-v1.mjs /tmp/vc-foundation-package
cd /tmp/vc-foundation-package
npm pack --ignore-scripts
```
Install the resulting tarball into a trusted VC Node server using a local file dependency.
Import `createVeteranCareServerReadEntryPoint` and `VETERAN_CARE_SERVER_READ_ADAPTERS`
from `@shine-foundation/veteran-care-server-read`.
Supply server-owned configuration and the 19 protected adapters from the layer-1 consumer contract.

The source lock pins all 15 transitive modules to the layer-1 merged Core commit,
Git blob SHA and SHA-256. Builds reject drift, missing/unreachable modules and unreviewed
external or dynamic imports before creating output. A new reviewed lock/version is required
when producer code changes. Builds refuse an existing output directory; use a fresh path.

The root export is the existing server entry point. This package copies the original modules
without weakening their checks. It has no external npm dependencies or install scripts.
It deliberately retains the transitive runtime adapter module used by the project boundary.

The package is for trusted server composition. It does not protect against a server bundler
putting it in a browser bundle; VC must keep the import in its server mount and verify that boundary.
A missing adapter stays blocked. Configured callbacks supply no authority.
Results remain private to authenticated VC server orchestration; no content logging,
browser/model disclosure, writes or transport is authorised.
No credentials, records, fixtures or database migrations are packaged.

Packaging is source evidence. Live adapter provenance, consumer mount, consented read and
exact deployed-release acceptance remain open.
