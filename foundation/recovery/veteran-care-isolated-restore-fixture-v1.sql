-- Synthetic CI database only. No production schema or clinical data.
create schema vc_restore;
revoke all on schema vc_restore from public;
create table vc_restore.records(record_id uuid primary key, owner_id uuid not null, version integer not null check(version>0), content text not null);
create table vc_restore.permissions(grant_id uuid primary key, record_id uuid not null references vc_restore.records(record_id), owner_id uuid not null, status text not null check(status in ('active','revoked')), revision integer not null check(revision>0));
create table vc_restore.revocations(grant_id uuid primary key references vc_restore.permissions(grant_id), revision integer not null check(revision>0));
create table vc_restore.tasks(task_id uuid primary key, owner_id uuid not null, status text not null check(status in ('paused','cancelled','completed')));
create table vc_restore.retry_bindings(operation_id uuid primary key, task_id uuid not null references vc_restore.tasks(task_id), record_id uuid not null references vc_restore.records(record_id), owner_id uuid not null);
create table vc_restore.checkpoints(checkpoint_id uuid primary key, operation_id uuid not null references vc_restore.retry_bindings(operation_id), revision integer not null check(revision>0), status text not null check(status in ('resumable','superseded')));
insert into vc_restore.records values
 ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','11111111-1111-4111-8111-111111111111',3,'synthetic owner-one text'),
 ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','22222222-2222-4222-8222-222222222222',1,'synthetic owner-two text');
insert into vc_restore.permissions values ('cccccccc-cccc-4ccc-8ccc-cccccccccccc','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','11111111-1111-4111-8111-111111111111','active',1);
-- The revocation ledger deliberately advances beyond the old grant snapshot.
insert into vc_restore.revocations values ('cccccccc-cccc-4ccc-8ccc-cccccccccccc',2);
insert into vc_restore.tasks values ('dddddddd-dddd-4ddd-8ddd-dddddddddddd','11111111-1111-4111-8111-111111111111','paused');
insert into vc_restore.retry_bindings values ('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee','dddddddd-dddd-4ddd-8ddd-dddddddddddd','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','11111111-1111-4111-8111-111111111111');
insert into vc_restore.checkpoints values ('ffffffff-ffff-4fff-8fff-ffffffffffff','eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',1,'resumable');
alter table vc_restore.records enable row level security;
alter table vc_restore.records force row level security;
create policy selected_owner_read on vc_restore.records for select to __READER_ROLE__ using (owner_id::text=current_setting('vc_restore.shine_id',true));
grant usage on schema vc_restore to __READER_ROLE__;
grant select on vc_restore.records to __READER_ROLE__;
