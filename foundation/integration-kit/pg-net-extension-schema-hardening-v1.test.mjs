import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';

const root=fileURLToPath(new URL('../../',import.meta.url));
const collector=readFileSync(root+'foundation/postgres/automatic-health-collector-hosted-v1.sql','utf8');
const hardening=readFileSync(root+'foundation/postgres/pg-net-extension-schema-hardening-v1.sql','utf8');

test('fresh hosted installs place pg_net extension metadata outside public',()=>{
  assert.match(
    collector,
    /create extension if not exists pg_net with schema extensions;/i
  );
  assert.doesNotMatch(
    collector,
    /create extension if not exists pg_net\s*;/i
  );
});

test('existing pg_net hardening is drained, lossless and non-cascading',()=>{
  assert.match(hardening,/pg-net-hardening-not-drained/);
  assert.match(hardening,/lock table net\.http_request_queue in access exclusive mode/i);
  assert.match(hardening,/lock table net\._http_response in access exclusive mode/i);
  assert.match(hardening,/create temporary table pg_net_response_backup/i);
  assert.match(hardening,/create temporary table pg_net_state_backup/i);
  assert.match(hardening,/drop extension pg_net;/i);
  assert.doesNotMatch(hardening,/drop extension pg_net\s+cascade/i);
  assert.match(hardening,/create extension pg_net with schema extensions;/i);
  assert.match(hardening,/insert into net\._http_response/i);
  assert.match(hardening,/select setval\(/i);
  assert.match(hardening,/pg-net-hardening-response-restore-mismatch/);
  assert.match(hardening,/pg-net-hardening-sequence-restore-mismatch/);
  assert.match(hardening,/pg-net-hardening-service-role-privilege-mismatch/);
  assert.doesNotMatch(hardening,/alter extension pg_net set schema/i);
});

test('hardening refuses an already-moved or unexpected extension namespace',()=>{
  assert.match(hardening,/if v_schema<>'public'/);
  assert.match(hardening,/pg-net-hardening-unexpected-extension-schema/);
  assert.match(hardening,/if v_schema<>'extensions'/);
  assert.match(hardening,/pg-net-hardening-schema-verification-failed/);
});
