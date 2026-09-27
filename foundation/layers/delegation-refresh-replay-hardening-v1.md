# Foundation — Delegation refresh replay hardening v1

**Status:** Production live  
**Scope:** Delegated integration session durability and refresh-token replay defence  
**Gateway:** `foundation-gateway` v60 — no Edge contract change required  
**Database migration:** `foundation_delegation_refresh_replay_hardening_v1`

## Why this increment exists

Foundation already issues short-lived delegation sessions and longer-lived, rotating refresh credentials after an explicit user-approved integration link.

The original refresh rotation function queried the effective refresh view and locked the underlying credential row. The credential's consumed state, however, is recorded separately as an append-only refresh event. Under near-simultaneous requests, that separation could allow two transactions to race before the second statement observed the first rotation event.

A later presentation of an already-rotated refresh credential also returned only a generic invalid result. It did not treat reuse as a security signal or invalidate the descendant delegated credential family.

## Hardened contract

`foundation.rotate_delegation_refresh_v1` keeps its existing signature and public Gateway behaviour, but now:

1. finds and locks the raw refresh credential row first;
2. re-evaluates refresh state only after that lock is held;
3. permits one valid rotation only while the approved integration link is active;
4. treats reuse of an already-rotated credential as `refresh-reuse-detected`;
5. records denied/revoked append-only evidence;
6. revokes every still-active descendant refresh credential for the same approved link/client;
7. revokes every still-active delegation session for that link/client as a `security-event`;
8. remains fail-closed for expired, explicitly revoked, future-dated or link-inactive credentials.

The function remains executable only by `foundation_runtime`; PUBLIC execution is revoked.

## Verification

A rollback-only production proof exercised the complete behaviour without leaving synthetic rows:

- first presentation of a fresh test refresh credential rotated successfully;
- second presentation of the same old credential returned `refresh-reuse-detected`;
- the newly issued child refresh credential was no longer effective;
- the newly issued delegation session was no longer effective;
- the transaction was rolled back.

The change does not expose or persist raw refresh/delegation tokens, does not change the Gateway HTTP contract, does not grant any new scope, and does not affect the standalone operation of connected Shine apps.

## Live-state context

At the time of this hardening, Foundation had one historical delegated session whose 24-hour lifetime had elapsed and one corresponding refresh credential still within its longer refresh window. The hardening protects the next refresh operation without forcing a relink or broadening consent.
