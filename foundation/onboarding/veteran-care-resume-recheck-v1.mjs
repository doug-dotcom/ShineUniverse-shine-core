import {createVeteranCareSessionIdentityVerifier} from './veteran-care-session-v1.mjs';
import {createVeteranCareRetryIdentityGate} from './veteran-care-retry-identity-v1.mjs';
const UUID=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
const fields=['checkpointId','foundationAppId','ownerShineId','operationId','taskId','memoryId','memoryVersion','preparationId','stage','status','revision','validUntil'];
function capture(v,keys){
  if(!v||Object.getPrototypeOf(v)!==Object.prototype)throw new TypeError();
  const d=Object.getOwnPropertyDescriptors(v);
  if(Reflect.ownKeys(d).length!==keys.length||keys.some(k=>!Object.hasOwn(d,k)||!Object.hasOwn(d[k],'value')))throw new TypeError();
  return Object.freeze(Object.fromEntries(keys.map(k=>[k,d[k].value])));
}
const deny=(status='denied',retrievalPerformed=false)=>({status,reasonCode:'vc-resume-authority-unverified',retrievalPerformed,resultReturned:false,modelDisclosurePermitted:false});
// A checkpoint is server-owned progress metadata, never saved permission.
// Resume looks up an existing retry identity; it cannot mint a replacement.
export function createVeteranCareResumeRecheckGate({getCurrentResumeCheckpoint,getExistingRetryIdentity,readSelectedMemory,resumeClock=()=>Date.now(),...options}={}){
  if(options.appId!=='shine.veteran-care'||[getCurrentResumeCheckpoint,getExistingRetryIdentity,readSelectedMemory,resumeClock].some(f=>typeof f!=='function'))throw new TypeError('current checkpoint, existing retry identity and private read required');
  const verify=createVeteranCareSessionIdentityVerifier(options);
  const existing=async q=>({status:'existing',...capture(await getExistingRetryIdentity(Object.freeze({operationId:q.operationId,foundationAppId:q.binding.foundationAppId,actorShineId:q.binding.actorShineId})),['operationId','fingerprint','binding'])});
  createVeteranCareRetryIdentityGate({...options,bindRetryIdentity:existing,readSelectedMemory});
  return async function resume(input){
    let checkpointId,authContext,companionAuthContext,recipientAuthContext;
    try{
      const i=capture(input,['checkpointId','authContext','companionAuthContext','recipientAuthContext']);checkpointId=i.checkpointId;
      authContext=capture(i.authContext,['appToken','jwt']);companionAuthContext=capture(i.companionAuthContext,['clientToken','userToken']);recipientAuthContext=capture(i.recipientAuthContext,['serviceToken']);
      if(typeof checkpointId!=='string'||!UUID.test(checkpointId)||[...Object.values(authContext),...Object.values(companionAuthContext),recipientAuthContext.serviceToken].some(v=>typeof v!=='string'||!v.length))throw new TypeError();
    }catch{return deny();}
    let performed=false,checkpointRefused=false;
    try{
      let last=resumeClock();if(!Number.isSafeInteger(last)||last<0)throw new TypeError();
      const actor=await verify({authContext});if(actor.status!=='verified')return deny(actor.status);
      const query=Object.freeze({checkpointId,foundationAppId:options.appId,ownerShineId:actor.identity.shineId.toLowerCase()});
      async function current(){
        const c=capture(await getCurrentResumeCheckpoint(query),fields),now=resumeClock();
        if(!Number.isSafeInteger(now)||now<last)throw new TypeError();last=now;
        if(Object.keys(query).some(k=>c[k]!==query[k])||c.stage!=='selected-memory-read'||c.status!=='resumable'||[c.operationId,c.taskId,c.memoryId,c.preparationId].some(v=>typeof v!=='string'||!UUID.test(v))||!Number.isSafeInteger(c.memoryVersion)||c.memoryVersion<1||!Number.isSafeInteger(c.revision)||c.revision<1||typeof c.validUntil!=='string'||!Number.isSafeInteger(Date.parse(c.validUntil))||now>=Date.parse(c.validUntil))return null;
        return c;
      }
      const first=await current();if(!first)return deny();
      const same=c=>c&&fields.every(k=>first[k]===c[k]);
      const retry=createVeteranCareRetryIdentityGate({...options,bindRetryIdentity:existing,readSelectedMemory:async q=>{
        if(!same(await current())||q.ownerShineId!==query.ownerShineId){checkpointRefused=true;throw new Error('checkpoint changed');}
        performed=true;return readSelectedMemory(q);
      }});
      const result=await retry({operationId:first.operationId,taskId:first.taskId,authContext,companionAuthContext,recipientAuthContext,
        request:Object.freeze({operation:'read',memoryId:first.memoryId,memoryVersion:first.memoryVersion,preparationId:first.preparationId})});
      if(checkpointRefused)return deny('denied',performed);
      if(result.status!=='retry-bound-result')return deny(result.status,performed);
      if(!same(await current())||result.recipient.actorShineId!==query.ownerShineId)return deny('denied',performed);
      const deadline=Math.min(Date.parse(first.validUntil),Date.parse(result.recipient.validUntil)),now=resumeClock();
      if(!Number.isSafeInteger(now)||now<last||now>=deadline)return deny('denied',performed);
      return {...result,contract:'shine-foundation/veteran-care-resume-result-v1',status:'resume-rechecked-result',
        recipient:Object.freeze({...result.recipient,validUntil:new Date(deadline).toISOString()}),
        checkpoint:Object.freeze({checkpointId,revision:first.revision,stage:first.stage,validUntil:new Date(deadline).toISOString()}),checkpointAuthorityReused:false,requiresFreshResumeCheck:true};
    }catch{return deny('unavailable',performed);}
  };
}
