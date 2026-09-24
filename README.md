# Shine Universe Core

Shared contracts and platform standards for the Shine Universe.

## Shine Defence

`security/shine-defence/baseline-v1.json` is the canonical minimum security contract for Shine applications.

Individual apps keep a local certification profile that maps these shared controls to app-specific evidence. An app may display **Protected by Shine Defence** only when its release revision passes every required control in its declared profile.

The baseline is deliberately conservative: a control is certified only when there is concrete, testable evidence. New controls can be added without pretending they already exist.
