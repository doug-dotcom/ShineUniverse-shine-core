# Supabase support request — prepared, not submitted

Subject: Narrow Auth-schema USAGE grant for metadata-only NOLOGIN reader

Project: raxfwycrnviwxxzykhfq (Project L)
Date: 9 November 2026, Brisbane

Please apply the following narrow grant using the Auth-schema owner's authority, or confirm the supported least-privilege alternative:

```sql
GRANT USAGE ON SCHEMA auth TO vc_foundation_l_identity_reader;
```

Verified diagnostics:
- Connected current_user and session_user: postgres; not a superuser.
- Auth schema owner: supabase_admin.
- postgres has no Auth-schema USAGE WITH GRANT OPTION and cannot SET ROLE supabase_admin.
- Reader's effective Auth-schema USAGE remains false.
- Required column-level metadata SELECT and RLS policies are already installed. A reader-scoped session query fails permission denied for schema auth.
- Reader is NOLOGIN, NOSUPERUSER and NOBYPASSRLS, with no runtime login membership.
- No SELECT on email, passwords or refresh-token values; no session writes.
- Public memory transport remains closed.

We need current session/refresh-revocation metadata for strict per-request session validation. We are not requesting ownership changes, broader role membership, RLS bypass, full-table SELECT or access to credential values.

After the grant, we will verify effective schema USAGE and the existing narrowly scoped session query using a rolled-back test membership/transaction.

Prepared owner operation and verification:
https://github.com/doug-dotcom/ShineUniverse-shine-core/blob/main/foundation/operations/project-l-auth-schema-reader-owner-grant-20261109.sql

This request contains no tokens, credentials, user records or personal grant IDs. No support message has been submitted.
