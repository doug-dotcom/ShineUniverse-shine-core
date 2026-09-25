# Shine Defence integration kit

This directory contains the reusable plumbing for app-level Shine Defence certification.

## Design rule

The shared kit provides **mechanics**, not fake universality. Each Shine app has its own architecture and must supply app-specific evidence for every required control in the canonical baseline contract.

A normal integration has:

1. a pinned local copy of `certifier-v1.mjs`;
2. a local profile that names the app, contract version and any extra controls;
3. an app-specific `scripts/certify-shine-defence.mjs`;
4. certification included in the app's normal test command;
5. a CI gate that runs the certification on pull requests and release branches;
6. the **Protected by Shine Defence** claim only after the exact release revision passes both Defence and the app's existing verification.

## Why the certifier is vendored for now

Shine Core is not yet published as an npm package. Apps therefore vendor the small versioned certifier and record its Core source path/version. This keeps builds deterministic and avoids a remote runtime dependency. A later package can replace the vendored copy once package signing/versioning and update policy are established.

## Common checks supplied by the kit

The kit includes:

- canonical-contract coverage checking;
- result reporting and fail-closed exit status;
- an obvious-secret source scan.

Header policy, request-method restrictions, upload handling, session controls, upstream bounds, AI boundaries and data-access rules remain **app-specific assertions**.

## Badge rule

A passing security script is necessary but not sufficient. The badge applies to a release revision only when:

- all required baseline controls pass;
- the app's pre-existing tests/build verification also pass;
- no declared release-blocking security control is known to be failing.

The badge is a release claim, not a claim that software is invulnerable.
