# ADR-001 — Connected by choice, independent by design

**Status:** Accepted  
**Foundation layer:** 1

## Context

The Shine Universe consists of shared Universe systems plus specialised Shine applications. The applications already provide useful standalone capabilities and must not become fragile simply because they later gain shared identity, secure storage or cross-app coordination.

Shine Core, Shine ID and Shine Vault therefore need to enhance applications without turning Foundation into a universal runtime dependency.

## Decision

Every Shine application must support a **standalone mode** for its primary purpose.

Foundation may add:

- shared identity,
- shared permissions,
- protected Vault access,
- cross-app coordination,
- personalisation,
- shared intelligence,
- Universe-level services.

Foundation must not be required for unrelated primary app functionality.

If Foundation is unavailable or a Foundation request is denied, the application must fail closed for the requested shared/private capability while preserving unrelated standalone functionality where technically possible.

## Consequences

- Core cannot become a hidden monolith containing app-specific business logic.
- ID owns canonical identity but does not own each app's domain data.
- Vault access is granular and permissioned rather than Universe-wide.
- Apps need graceful degradation paths for unavailable shared services.
- Cross-app features are additive enhancements, not prerequisites for core use.
- New Shine apps must declare their primary purpose and supported Foundation modes.

## Rationale

This preserves resilience, keeps individual Shine apps useful on their own, reduces ecosystem-wide blast radius and allows the Universe to become more valuable through connection without making connection compulsory.
