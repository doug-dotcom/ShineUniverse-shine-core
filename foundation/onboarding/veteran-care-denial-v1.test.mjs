import test from 'node:test';
import assert from 'node:assert/strict';
import {projectVeteranCareDenial as project} from './veteran-care-denial-v1.mjs';
test('missing record wrong owner missing ambiguous expired or withdrawn access are indistinguishable',()=>{
 const expected=project({status:'denied',reasonCode:'vc-permission-missing'});
 for(const reasonCode of ['vc-resource-scope-mismatch','vc-purpose-binding-unverified','vc-permission-ambiguous','vc-grant-expired','vc-in-flight-authority-changed','vc-permission-snapshot-stale','vc-delegation-unverified','vc-defence-not-allowed'])assert.deepEqual(project({status:'denied',reasonCode}),expected);
 assert.equal(expected.code,'access-not-confirmed');assert.ok(Object.isFrozen(expected));
});
test('session denial and operation refusal offer bounded concrete actions',()=>{
 assert.equal(project({status:'denied',reasonCode:'vc-session-not-current'}).nextAction,'sign-in');
 assert.equal(project({status:'denied',reasonCode:'vc-read-route-operation-refused'}).nextAction,'review-request');
});
test('all authority outages give one manual retry message without internal stage',()=>{
 const expected=project({status:'unavailable',reasonCode:'vc-audit-not-confirmed'});
 for(const reasonCode of ['vc-token-authority-unavailable','vc-release-clock-unavailable','vc-resource-authority-unavailable','private secret error'])assert.deepEqual(project({status:'unavailable',reasonCode}),expected);
 assert.equal(expected.nextAction,'retry-later');assert.equal(expected.status,'blocked');
});
test('clinical text identifiers tokens HTML and exceptions cannot enter public envelope',()=>{
 const secret='<script>private diagnosis 11111111-1111-4111-8111-111111111111 bearer token</script>';
 const r=project({status:'denied',reasonCode:secret,message:secret,request:{resourceId:secret},authContext:{jwt:secret},stack:secret,result:secret});
 assert.equal(JSON.stringify(r).includes(secret),false);assert.deepEqual(Object.keys(r).sort(),['contract','schemaVersion','status','code','message','nextAction'].sort());
});
test('malformed inherited and accessor outcomes do not evaluate getters or leak values',()=>{
 const fallback=project(null);for(const value of [undefined,{},[],Error('secret'),Object.create({status:'denied',reasonCode:'vc-session-not-current'}),{get status(){throw Error('secret');}},{status:'denied',get reasonCode(){throw Error('secret');}}])assert.deepEqual(project(value),fallback);
});
test('success outcomes are never relabelled as refusal or serialised with private data',()=>{
 for(const status of ['permission-allowed','release-ready','verified','scope-ready','delegated-scope-ready'])assert.equal(project({status,result:'secret'}),null);
 assert.equal(project({status:'denied',decision:'allow',result:'secret'}),null);
});
