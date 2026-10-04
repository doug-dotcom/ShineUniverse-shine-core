import test from 'node:test';
import assert from 'node:assert/strict';
import {createCapabilityTicketRedeemService} from './capability-ticket-redeem-v2.mjs';
const envelope={capabilityTicketRedeem:'shine-foundation/capability-ticket-redeem-v2',schemaVersion:'2.0.0',
 ticketId:'11111111-1111-4111-8111-111111111111',stepId:'22222222-2222-4222-8222-222222222222',capabilityId:'travel.plan_trip'};
const authorised={allowed:true,reasonCode:'ticket-consumed',ticketId:envelope.ticketId,capabilityId:envelope.capabilityId,stepId:envelope.stepId,
 ownerShineId:'33333333-3333-4333-8333-333333333333',appId:'shine.travel',purpose:'travel.plan'};
const service=result=>createCapabilityTicketRedeemService({adapters:{redeemCapabilityInvocationTicket:async()=>result},
 idFactory:()=>envelope.ticketId,clock:()=> '2026-10-04T06:00:00Z'});
test('exact capability and step binding passes through',async()=>{
 let call;
 const handle=createCapabilityTicketRedeemService({adapters:{redeemCapabilityInvocationTicket:async args=>{call=args;return authorised}},
 idFactory:()=>envelope.ticketId});
 const r=await handle({envelope});assert.equal(r.status,'allowed');assert.equal(r.capabilityId,envelope.capabilityId);
 assert.equal(call.capabilityId,envelope.capabilityId);assert.equal(call.stepId,envelope.stepId);
});
test('another capability or step cannot supply permission for this request',async()=>{
 for(const override of [{ticketId:envelope.stepId},{ticketId:undefined},{capabilityId:'travel.book_trip'},{stepId:envelope.ticketId},{capabilityId:undefined},{stepId:undefined}]){
  const r=await service({...authorised,...override})({envelope});
  assert.equal(r.status,'unavailable');assert.equal(r.reasonCode,'capability-ticket-binding-mismatch');
  assert.equal(Object.hasOwn(r,'ownerShineId'),false);
 }
});
test('denial remains denial without leaking capability grant context',async()=>{
 const r=await service({...authorised,allowed:false,reasonCode:'capability-grant-required'})({envelope});
 assert.equal(r.status,'denied');assert.equal(Object.hasOwn(r,'ownerShineId'),false);
});

test('a fresh service never turns durable consumed-ticket denial into permission',async()=>{
 let consumed=false,calls=0;
 const adapters={redeemCapabilityInvocationTicket:async()=>{
  calls++;
  if(consumed)return {allowed:false,reasonCode:'invocation-ticket-already-consumed'};
  consumed=true;return authorised;
 }};
 const make=()=>createCapabilityTicketRedeemService({adapters,idFactory:()=>envelope.stepId});
 assert.equal((await make()({envelope})).status,'allowed');
 const replay=await make()({envelope});
 assert.equal(replay.status,'denied');assert.equal(replay.reasonCode,'invocation-ticket-already-consumed');
 assert.equal(Object.hasOwn(replay,'ownerShineId'),false);assert.equal(calls,2);
});
