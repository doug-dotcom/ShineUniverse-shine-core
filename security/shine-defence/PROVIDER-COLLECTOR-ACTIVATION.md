# Provider Collector activation

## Current verified position

8 October 2026, Brisbane: run 37643519857 on commit b5eab385c67835057e68fbdbb2c94192a46f057f passed. Its rendered summary reports both provider credentials missing, zero observations collected and zero accepted. Workflow success does not establish provider coverage or certification.

## Account-owner setup

In doug-dotcom/ShineUniverse-shine-core, open Settings → Secrets and variables → Actions → Repository secrets → New repository secret. Install these exact existing workflow secrets using authorised credentials:

| Secret name | Required use |
| --- | --- |
| SHINE_DEFENCE_RAILWAY_WORKSPACE_TOKEN | Railway GraphQL deployment reads across the Railway project/environment/service scopes in security/shine-defence/estate-provider-sources-v1.json |
| SHINE_DEFENCE_SUPABASE_READ_TOKEN | Supabase management API project status reads across the Supabase project refs in the same registry |

Review all registered scopes before issuing credentials. Use the narrowest provider-supported permissions sufficient for those reads. The secret names do not enforce read-only permissions; actual provider grants determine access. A Supabase database anon/service-role key does not replace a management API credential. No credential value belongs in chat, git, screenshots, logs or evidence receipts. Available connectors currently do not expose provider token creation or GitHub secret installation.

## Verify activation

Open Actions → Shine Defence Provider Collector → Run workflow → main. Review its completed summary and logs. Require both credentials configured, evidence for every registered target, and Foundation accepted count matching collected count. A partial provider configuration is partial coverage. A successful zero-observation run refreshes no targets.

Independently read Foundation current target observations and freshness. For railway:dnd, verify its current signed sleeping state and the on-demand control nextAction. Do not treat a provider read as health/admission proof. Request revalidation only when the existing control gates allow it; approval and execution retain their separate roles and single-use expiry controls.

## Implemented preparation

Collector sleeping fallback corrected in commit 411eb0fa94c7f3744514d57c45809ae59b83386d, with sleeping/active fallback regression checks passing locally and in GitHub Actions. Explicit credential/evidence coverage summary added in b5eab385c67835057e68fbdbb2c94192a46f057f and verified rendered in run 37643519857.

This handover is documentation, not a new implementation or verified operational increment. Completed room counts remain 12 implementation + 7 verified operational increments. Whole estate certification remains open.
