import {createHash} from 'node:crypto';
import {createVeteranCareSessionIdentityVerifier} from './veteran-care-session-v1.mjs';
import {createVeteranCareTaskAuthorityGate} from './veteran-care-task-authority-v1.mjs';
const UUID=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
function capture(v,keys){
  if(!v||Object.getPrototypeOf(v)!==Object.prototype)throw new TypeError();
  const d=Object.getOwnPropertyDescriptors(v);
  if(Reflect.ownKeys(d).length!==keys.length||keys.some(k=>!Object.hasOwn(d,k)||!Object.hasOwn(d[k],'value')))throw new TypeError();
  return Object.freeze(Object.fromEntries(keys.map(k=>[k,d[k].value])));
}
const deny=(status='denied')=>({status,reasonCode:'vc-retry-identity-unverified',retrievalPerformed:false,resultReturned:false,modelDisclosurePermitted:false});
// bindRetryIdentity must atomically insert once or return the original immutable
// binding. A matching retry still runs all current authority checks; no result cache.
export function createVeteranCareRetryIdentityGate({bindRetryIdentity,readSelectedMemory,...options}={}){
  if(options.appId!=='shine.veteran-care'||typeof bindRetryIdentity!=='function'||typeof readSelectedMemory!=='function')throw new TypeError('atomic retry identity registry and private read required');
  const verify=createVeteranCareSessionIdentityVerifier(options);
  createVeteranCareTaskAuthorityGate({...options,readSelectedMemory});
  return async function retry(input){
    let operationId,selected;
    try{
      const i=capture(input,['operationId','taskId','authContext','companionAuthContext','request','recipientAuthContext']);operationId=i.operationId;
      selected=Object.freeze({taskId:i.taskId,authContext:capture(i.authContext,['appToken','jwt']),companionAuthContext:capture(i.companionAuthContext,['clientToken','userToken']),request:capture(i.request,['operation','memoryId','memoryVersion','preparationId']),recipientAuthContext:capture(i.recipientAuthContext,['serviceToken'])});
      const r=selected.request;
      if([operationId,selected.taskId,r.memoryId,r.preparationId].some(v=>typeof v!=='string'||!UUID.test(v))||r.operation!=='read'||!Number.isSafeInteger(r.memoryVersion)||r.memoryVersion<1||[...Object.values(selected.authContext),...Object.values(selected.companionAuthContext),selected.recipientAuthContext.serviceToken].some(v=>typeof v!=='string'||!v.length))throw new TypeError();
    }catch{return deny();}
    try{
      const identity=await verify({authContext:selected.authContext});if(identity.status!=='verified')return deny(identity.status);
      const binding=Object.freeze({foundationAppId:options.appId,actorShineId:identity.identity.shineId.toLowerCase(),clientId:'shine.companion',taskId:selected.taskId,
        memoryId:selected.request.memoryId,memoryVersion:selected.request.memoryVersion,preparationId:selected.request.preparationId,operation:'read',
        scope:'veteran-care.memory.read',purpose:'veteran-care.appointment-preparation',audience:'vc-trusted-server'});
      const fingerprint=createHash('sha256').update(JSON.stringify(binding)).digest('hex');
      const stored=capture(await bindRetryIdentity(Object.freeze({operationId,fingerprint,binding})),['status','operationId','fingerprint','binding']);
      const original=capture(stored.binding,Object.keys(binding));
      if(!['bound','existing'].includes(stored.status)||stored.operationId!==operationId||stored.fingerprint!==fingerprint||Object.keys(binding).some(k=>binding[k]!==original[k]))return deny();
      const gate=createVeteranCareTaskAuthorityGate({...options,readSelectedMemory:async q=>{
        if(q.ownerShineId!==binding.actorShineId)throw new Error('retry actor changed');
        return readSelectedMemory(q);
      }});
      const result=await gate(selected);
      if(result.status!=='task-bound-result')return result;
      if(result.recipient.actorShineId!==binding.actorShineId)return {...deny(),retrievalPerformed:result.retrievalPerformed};
      return {...result,contract:'shine-foundation/veteran-care-retry-identity-result-v1',status:'retry-bound-result',
        retry:Object.freeze({operationId,fingerprint,identityReused:stored.status==='existing',authorityRechecked:true,resultReused:false})};
    }catch{return deny('unavailable');}
  };
}
