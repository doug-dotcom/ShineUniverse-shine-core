import test from 'node:test';
import assert from 'node:assert/strict';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {fileURLToPath} from 'node:url';
const run=promisify(execFile),script=fileURLToPath(new URL('./verify-veteran-care-restored-revocation-v1.mjs',import.meta.url));
test('restored revocation CLI cannot run without isolated CI authority',async()=>{try{await run(process.execPath,[script],{env:{PATH:process.env.PATH},timeout:5000});assert.fail('unguarded restore succeeded');}catch(e){assert.equal(e.code,1);assert.equal(e.stdout,'');assert.match(e.stderr,/no production continuity claimed/);}});
test('revocation proof rejects remote database settings without disclosing secrets',async()=>{try{await run(process.execPath,[script],{env:{PATH:process.env.PATH,CI:'true',GITHUB_ACTIONS:'true',FOUNDATION_VC_SYNTHETIC_RESTORE:'1',FOUNDATION_VC_POSTGRES_CONTAINER:'a'.repeat(64),PGHOST:'production.supabase.co',PGPORT:'5432',PGUSER:'postgres',PGDATABASE:'postgres',PGPASSWORD:'private-secret'},timeout:5000});assert.fail('remote restore succeeded');}catch(e){assert.equal(e.code,1);assert.equal(e.stdout,'');assert.equal(e.stderr.includes('private-secret'),false);assert.equal(e.stderr.includes('production.supabase.co'),false);}});
