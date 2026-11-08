-- PROPOSED ONLY. Do not run until Doug approves a new 30-day VC service-authentication period.
-- Creates a replacement app credential. Does not change user identities, links, grants or scopes.
-- The token stays inside Supabase Vault; neither SQL results nor logs print it.
begin;
do $renew$
declare
  v_secret text;
  v_secret_id uuid;
  v_credential_id uuid:=gen_random_uuid();
  v_now timestamptz:=now();
begin
  if not exists(select 1 from foundation.app_registry where app_id='shine.veteran-care' and status='active') then
    raise exception 'vc-app-not-active';
  end if;
  if not exists(
    select 1 from foundation.app_credentials c
    where c.credential_id='45ac096b-4e32-4bc2-85d8-ba1482306b25'
      and c.app_id='shine.veteran-care' and c.expires_at<v_now
      and not exists(select 1 from foundation.app_credential_revocations r where r.credential_id=c.credential_id)
  ) then raise exception 'old-credential-precondition-failed'; end if;
  if exists(select 1 from vault.secrets where name='vc-foundation-app-live-integration-v2') then
    raise exception 'replacement-already-exists-review-before-retry';
  end if;
  v_secret:=encode(extensions.gen_random_bytes(32),'hex');
  insert into foundation.app_credentials(credential_id,app_id,token_hash,label,issued_at,expires_at)
  values(v_credential_id,'shine.veteran-care',encode(extensions.digest(v_secret,'sha256'),'hex'),
    'VC Foundation live integration v2',v_now,v_now+interval '30 days');
  select vault.create_secret(v_secret,'vc-foundation-app-live-integration-v2',
    'Replacement VC service credential for authorised live Foundation integration testing',null)
    into v_secret_id;
end;
$renew$;
commit;
-- Subsequent verification returns only credential metadata and effective status.
select e.app_id,c.label,e.effective_status,e.issued_at,e.expires_at
from foundation.effective_app_credentials e
join foundation.app_credentials c using(credential_id)
where c.label='VC Foundation live integration v2';
