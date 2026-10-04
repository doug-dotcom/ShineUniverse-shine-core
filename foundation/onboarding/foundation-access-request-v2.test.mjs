import test from 'node:test';
import assert from 'node:assert/strict';
import {buildFoundationAccessRequest as build} from './foundation-access-request-v2.mjs';
test('canonical envelope preserves scope and excludes top-level credentials and claimed identity',()=>{
 const input={appId:'shine.travel',scope:'vault.read',purpose:'travel.plan',resourceCategory:'journey',
 userCredential:'private-user-token',appToken:'private-app-token',shineId:'claimed-user'};
 const r=build(input,{randomUUID:()=> '11111111-1111-4111-8111-111111111111',now:()=>new Date('2026-10-04T05:00:00Z')});
 assert.equal(r.permission.scope,input.scope);assert.equal(r.permission.requestedAt,'2026-10-04T05:00:00.000Z');
 assert.equal(r.gatewayRequest,'shine-foundation/gateway-request-v2');
 assert.equal(JSON.stringify(r).includes('private-'),false);
 assert.equal(Object.hasOwn(r.permission,'shineId'),false);
});
test('resource identifiers and context remain compatible',()=>{
 const r=build({appId:'shine.dive',scope:'vault.read',purpose:'dive.plan',resourceId:'11111111-1111-4111-8111-111111111111',context:{mode:'connected'}});
 assert.equal(r.permission.context.mode,'connected');
 assert.equal(Object.hasOwn(r.permission,'resourceCategory'),false);
});
