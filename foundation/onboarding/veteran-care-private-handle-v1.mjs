import {randomUUID} from 'node:crypto';
import {createVeteranCareAIDecisionBuilder} from './veteran-care-ai-decision-v1.mjs';
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
const contract='shine-foundation/veteran-care-private-resource-handle-v1';
const fields=['audience','foundationAppId','aiCallerId','actorShineId','keyId','callerRegistrationRevision','ownerShineId','resourceId','resourceVersion','capabilityId','operation','scope','purpose','preparationId','grantId'];
const refuse=(status='denied')=>({status,reasonCode:'vc-private-handle-unavailable',executionPermitted:false});
function capture(v,keys){
  if(!v||Object.getPrototypeOf(v)!==Object.prototype)throw new TypeError();
  const d=Object.getOwnPropertyDescriptors(v);
  if(Reflect.ownKeys(d).length!==keys.length||keys.some(k=>!Object.hasOwn(d,k)||!Object.hasOwn(d[k],'value')))throw new TypeError();
  return Object.freeze(Object.fromEntries(keys.map(k=>[k,d[k].value])));
}
// Registry adapters must be server-private, atomic insert-only, and keyed by an
// unpredictable identifier. Handles carry no read or model disclosure authority.
export function createVeteranCarePrivateHandleService({insertPrivateHandle,getPrivateHandle,handleClock=()=>Date.now(),handleIdFactory=randomUUID,handleTtlMs=300000,...options}={}){
  if([insertPrivateHandle,getPrivateHandle,handleClock,handleIdFactory].some(f=>typeof f!=='function')||!Number.isSafeInteger(handleTtlMs)||handleTtlMs<1||handleTtlMs>300000)throw new TypeError('private registry adapters and bounded lifetime required');
  const build=createVeteranCareAIDecisionBuilder(options);
  const now=()=>{const n=handleClock();if(!Number.isSafeInteger(n)||n<0)throw new TypeError();return n;};
  return Object.freeze({
    async mint(input){
      try{
        const started=now(),decision=await build(input);
        if(decision.status!=='decision-ready')return refuse(decision.status);
        const e=decision.envelope,id=handleIdFactory();
        if(typeof id!=='string'||!uuid.test(id))throw new TypeError();
        const expiresAt=Math.min(Date.parse(e.validUntil),started+handleTtlMs),checked=now();
        if(!Number.isSafeInteger(expiresAt)||checked<started||checked>=expiresAt)return refuse();
        const binding=Object.freeze(Object.fromEntries(fields.map(k=>[k,e[k]])));
        const row=Object.freeze({contract,schemaVersion:'1.0.0',handleId:id,issuedAt:started,expiresAt,binding});
        const ack=capture(await insertPrivateHandle(row),['status','handleId']);
        const completed=now();
        if(ack.status!=='inserted'||ack.handleId!==id||completed<checked||completed>=expiresAt)return refuse();
        return {status:'handle-ready',handle:Object.freeze({contract,schemaVersion:'1.0.0',handleId:id,validUntil:new Date(expiresAt).toISOString()}),executionPermitted:false,modelDisclosurePermitted:false};
      }catch{return refuse('unavailable');}
    },
    async resolve(input){
      try{
        const q=capture(input,['handleId','decisionInput']);
        if(typeof q.handleId!=='string'||!uuid.test(q.handleId))return refuse();
        // Start fresh authorisation synchronously so its input is captured before
        // registry awaits. Even a known handle never substitutes for credentials.
        const started=now(),decision=await build(q.decisionInput);
        if(decision.status!=='decision-ready')return refuse(decision.status);
        const e=decision.envelope;
        const row=capture(await getPrivateHandle(q.handleId),['contract','schemaVersion','handleId','issuedAt','expiresAt','binding']);
        const binding=capture(row.binding,fields),checked=now();
        if(row.contract!==contract||row.schemaVersion!=='1.0.0'||row.handleId!==q.handleId||!Number.isSafeInteger(row.issuedAt)||row.issuedAt<0||!Number.isSafeInteger(row.expiresAt)||row.expiresAt<=row.issuedAt||row.expiresAt-row.issuedAt>handleTtlMs||row.issuedAt>started||checked<started||checked>=row.expiresAt||checked>=Date.parse(e.validUntil)||fields.some(k=>binding[k]!==e[k]))return refuse();
        return {status:'handle-resolved',handleId:q.handleId,envelope:Object.freeze({...e,validUntil:new Date(Math.min(row.expiresAt,Date.parse(e.validUntil))).toISOString()}),executionPermitted:false,modelDisclosurePermitted:false,requiresFreshExecutionCheck:true};
      }catch{return refuse('unavailable');}
    }
  });
}
