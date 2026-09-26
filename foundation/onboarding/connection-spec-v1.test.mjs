import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {compileAppendageConnectionSpec,validateAppendageConnectionSpec} from './connection-spec-v1.mjs';

const read=async name=>JSON.parse(await readFile(new URL('./examples/'+name,import.meta.url),'utf8'));

test('Travel example validates and compiles to standalone-safe manifest',async()=>{
  const spec=await read('travel-v1.json');
  assert.equal(validateAppendageConnectionSpec(spec).app.appId,'shine.travel');
  const plan=compileAppendageConnectionSpec(spec);
  assert.equal(plan.appManifest.foundation.standalonePrimaryPurposeAvailable,true);
  assert.equal(plan.identityProvider.kind,'supabase-auth');
  assert.equal(plan.runtime.userCredentialMode,'bearer-jwt');
  assert.deepEqual(plan.requiresLiveProvisioning,[
    'publishable-key','app-credential-secret','canonical-user-binding','pilot-grant'
  ]);
});

test('Dive example validates opaque-vault provider without private user state',async()=>{
  const spec=await read('dive-v1.json');
  const plan=compileAppendageConnectionSpec(spec);
  assert.equal(plan.identityProvider.kind,'supabase-opaque-vault');
  assert.equal(plan.identityProvider.verificationResource,'dive_companions');
  assert.equal(plan.runtime.userCredentialMode,'opaque-header');
  const encoded=JSON.stringify(spec);
  assert.equal(encoded.includes('"shineId"'),false);
  assert.equal(encoded.includes('"appToken"'),false);
});

test('spec rejects personal IDs and secrets',async()=>{
  const spec=await read('travel-v1.json');
  spec.shineId='11111111-1111-4111-8111-111111111111';
  assert.throws(()=>validateAppendageConnectionSpec(spec),/not allowed|private\/live state/);
});

test('identity kind and runtime credential mode must agree',async()=>{
  const spec=await read('dive-v1.json');
  spec.runtime.userCredentialMode='bearer-jwt';
  assert.throws(()=>validateAppendageConnectionSpec(spec),/does not match/);
});

test('pilot purpose must be namespaced to app',async()=>{
  const spec=await read('travel-v1.json');
  spec.pilot.purpose='dive.foundation-pilot';
  assert.throws(()=>validateAppendageConnectionSpec(spec),/namespaced/);
});
