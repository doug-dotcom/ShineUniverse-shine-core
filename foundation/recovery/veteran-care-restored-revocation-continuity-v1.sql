-- Isolated synthetic proof schema only, applied after restore parity checks.
-- Current watermark is supplied separately from the old backup by the proof.
create extension if not exists pgcrypto;
create table vc_restore.recovery_watermark(
 singleton boolean primary key check(singleton),
 required_epoch uuid not null, applied_epoch uuid not null,
 required_revision bigint not null check(required_revision>=0),
 applied_revision bigint not null check(applied_revision>=0),
 required_digest text not null check(required_digest ~ '^[0-9a-f]{64}$'),
 applied_digest text not null check(applied_digest ~ '^[0-9a-f]{64}$')
);
create function vc_restore.current_ledger_digest() returns text language sql stable
 security definer set search_path=pg_catalog as $$
 select encode(public.digest(convert_to(coalesce(jsonb_agg(to_jsonb(r) order by grant_id),'[]'::jsonb)::text,'UTF8'),'sha256'),'hex') from vc_restore.revocations r
$$;
create function vc_restore.reconciled_selected_read(selected_record uuid) returns boolean language sql stable
 security definer set search_path=pg_catalog as $$
 select exists(select 1 from vc_restore.recovery_watermark w
  where w.singleton and w.required_epoch=w.applied_epoch
   and w.required_revision=w.applied_revision
   and w.required_digest=w.applied_digest
   and w.required_digest=vc_restore.current_ledger_digest())
 and exists(select 1 from vc_restore.permissions p
  where p.record_id=selected_record and p.status='active'
   and not exists(select 1 from vc_restore.revocations r where r.grant_id=p.grant_id))
$$;
revoke all on function vc_restore.current_ledger_digest() from public;
revoke all on function vc_restore.reconciled_selected_read(uuid) from public;
grant execute on function vc_restore.reconciled_selected_read(uuid) to __READER_ROLE__;
alter policy selected_owner_read on vc_restore.records using
 (owner_id::text=current_setting('vc_restore.shine_id',true) and vc_restore.reconciled_selected_read(record_id));
