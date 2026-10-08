# Foundation Live Integration — layer 02/20: server package

Baseline: `1b8098d9580f6633677ef0924690f946840a044a` (layer 1 merged).
Completion: merge this layer after foundation-contracts, registry and persistence pass.
After merge: **2/20 source deliverables complete; 18 remain (90%).**
Historical count: **40/40 + 2 follow-on source increments** retained.

## Delivered

`foundation/packages/veteran-care-server-read-v1/` contains a Node ESM package builder,
source lock, consumer instructions and package acceptance tests.
The internal package is `@shine-foundation/veteran-care-server-read` version 1.0.0,
private and not published to npm, requiring Node >=22.

The root export exposes the unchanged existing server entry point and adapter-name export.
All 15 transitive modules are pinned to the baseline commit, exact Git blobs and SHA-256.
The builder validates their bytes and full static import closure before creating output,
rejects source drift/missing or unreachable modules/unreviewed imports,
and refuses output inside the source tree or an existing output directory.

This is a reviewed source-lock snapshot. Future producer edits require explicit lock/version review.
The lock proves bytes, not current live authorisation or callback provenance.
The transitive runtime adapter module remains included because the project boundary imports it;
there are no external npm dependencies, install scripts, fixtures, credentials, records or migrations in the package.
This change builds a local tarball in tests; it does not publish to a package registry.

## Verification

Four local tests passed:
- real npm tarball packing/extraction and import by the package name through its root export;
  unconfigured entry point refuses reads and preserves no disclosure/write/transport;
  existing output cannot be overwritten;
- changed producer source refuses output before writing;
- missing transitive module refuses output before writing;
- output in the source tree is rejected.

All 15 source-lock Git blobs were independently matched to the inspected baseline tree.
Package tests are explicitly included in Foundation CI.
Existing full Foundation, registry and synthetic persistence/restore checks remain required for merge.
Their actual outcomes are recorded in PR/check history.

## Consumer handover

Build from the pinned inspected Core checkout into a fresh directory outside the source tree,
then `npm pack --ignore-scripts`. Install the tarball as a local file dependency
in a trusted VC Node server. Supply only the server-owned configuration and 19 protected
adapters specified by layer 1. Keep the package out of browser bundles;
the package cannot enforce the consumer bundler boundary itself.

No VC repository mount, protected adapter implementation, private memory read, live database change
or deployment occurred here. **Live VC–L integration remains unverified.**
The next layer adds the VC trusted server integration mount, blocked by default;
its exact consumer repository and mount path must first be inspected and recorded.
