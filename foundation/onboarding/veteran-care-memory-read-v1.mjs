import {createVeteranCareMemoryScopeEvaluator} from './veteran-care-memory-scope-v1.mjs';
function capture(v,keys){
  if(!v||Object.getPrototypeOf(v)!==Object.prototype)throw new TypeError();
  const d=Object.getOwnPropertyDescriptors(v);
  if(Reflect.ownKeys(d).length!==keys.length||keys.some(k=>!Object.hasOwn(d,k)||!Object.hasOwn(d[k],'value')))throw new TypeError();
  return Object.freeze(Object.fromEntries(keys.map(k=>[k,d[k].value])));
}
const refuse=(status='denied',retrievalPerformed=false)=>({status,reasonCode:'vc-memory-read-unavailable',retrievalPerformed,resultReturned:false,modelDisclosurePermitted:false,memoryWritePermitted:false});
// Trusted server-only adapter: one read, no writes, external disclosure or usable
// links. This factory cannot sandbox callbacks; the consumer enforces that boundary.
export function createVeteranCareReadOnlyMemoryRetriever({readSelectedMemory,releaseClock=()=>Date.now(),...options}={}){
  if(typeof readSelectedMemory!=='function'||typeof releaseClock!=='function')throw new TypeError('private read adapter and release clock required');
  const evaluate=createVeteranCareMemoryScopeEvaluator(options);
  return async function retrieve(input){
    let q;
    try{
      const i=capture(input,['authContext','companionAuthContext','request']);
      q=Object.freeze({authContext:capture(i.authContext,['appToken','jwt']),companionAuthContext:capture(i.companionAuthContext,['clientToken','userToken']),request:capture(i.request,['operation','memoryId','memoryVersion','preparationId'])});
      if([...Object.values(q.authContext),...Object.values(q.companionAuthContext)].some(v=>typeof v!=='string')||typeof q.request.memoryId!=='string'||typeof q.request.memoryVersion!=='number'||typeof q.request.operation!=='string'||typeof q.request.preparationId!=='string')throw new TypeError();
    }catch{return refuse();}
    let performed=false;
    try{
      const first=await evaluate(q);if(first.status!=='memory-scope-allowed')return refuse(first.status);
      const e=first.envelope,started=releaseClock();
      if(!Number.isSafeInteger(started)||started<0)throw new TypeError();
      if(started>=Date.parse(e.validUntil))return refuse();
      performed=true;
      const row=capture(await readSelectedMemory(Object.freeze({foundationAppId:e.foundationAppId,clientId:e.clientId,ownerShineId:e.ownerShineId,linkId:e.linkId,linkRevision:e.linkRevision,memoryId:e.memoryId,memoryVersion:e.memoryVersion,category:e.category,operation:'read',scope:e.scope,purpose:e.purpose,preparationId:e.preparationId,grantId:e.grantId,permissionRevision:e.permissionRevision})),['memoryId','memoryVersion','ownerShineId','category','content']);
      if(['memoryId','memoryVersion','ownerShineId','category'].some(k=>row[k]!==e[k])||typeof row.content!=='string'||row.content.length<1||row.content.length>16384)return refuse('denied',true);
      // Capture result before final awaits; no mutable source object is released.
      const result=Object.freeze({...row});
      const final=await evaluate(q);if(final.status!=='memory-scope-allowed')return refuse(final.status,true);
      if(Object.keys(e).some(k=>e[k]!==final.envelope[k]))return refuse('denied',true);
      const now=releaseClock();if(!Number.isSafeInteger(now)||now<started)throw new TypeError();
      if(now>=Date.parse(final.envelope.validUntil))return refuse('denied',true);
      return {contract:'shine-foundation/veteran-care-read-only-memory-result-v1',schemaVersion:'1.0.0',status:'private-memory-read-ready',retrievalPerformed:true,resultReturned:true,
        audience:'vc-trusted-server',modelDisclosurePermitted:false,memoryWritePermitted:false,requiresFreshDisclosureCheck:true,result};
    }catch{return refuse('unavailable',performed);}
  };
}
