import {createVeteranCareSessionIdentityVerifier} from './veteran-care-session-v1.mjs';
import {createVeteranCareMemoryScopeEvaluator} from './veteran-care-memory-scope-v1.mjs';
import {createVeteranCareReadOnlyMemoryRetriever} from './veteran-care-memory-read-v1.mjs';
const audience='vc-trusted-server';
const recipientFields=['verified','audience','appId','actorShineId','servicePrincipalId','revision','validUntil'];
function capture(v,keys){
  if(!v||Object.getPrototypeOf(v)!==Object.prototype)throw new TypeError();
  const d=Object.getOwnPropertyDescriptors(v);
  if(Reflect.ownKeys(d).length!==keys.length||keys.some(k=>!Object.hasOwn(d,k)||!Object.hasOwn(d[k],'value')))throw new TypeError();
  return Object.freeze(Object.fromEntries(keys.map(k=>[k,d[k].value])));
}
const deny=(status='denied',retrievalPerformed=false)=>({status,reasonCode:'vc-result-audience-unverified',retrievalPerformed,resultReturned:false,modelDisclosurePermitted:false});
// The sole permitted destination is authenticated VC server orchestration.
// Transport, browser delivery and model disclosure remain separate boundaries.
export function createVeteranCareResultAudienceGate({verifyResultRecipient,readSelectedMemory,audienceClock=()=>Date.now(),...options}={}){
  if(options.appId!=='shine.veteran-care'||[verifyResultRecipient,readSelectedMemory,audienceClock].some(f=>typeof f!=='function'))throw new TypeError('VC recipient authority and private read adapter required');
  const verify=createVeteranCareSessionIdentityVerifier(options),evaluate=createVeteranCareMemoryScopeEvaluator(options);
  return async function release(input){
    let selected,recipientAuthContext;
    try{
      const i=capture(input,['authContext','companionAuthContext','request','recipientAuthContext']);
      const authContext=capture(i.authContext,['appToken','jwt']),companionAuthContext=capture(i.companionAuthContext,['clientToken','userToken']);
      const request=capture(i.request,['operation','memoryId','memoryVersion','preparationId']);
      recipientAuthContext=capture(i.recipientAuthContext,['serviceToken']);
      if([...Object.values(authContext),...Object.values(companionAuthContext),recipientAuthContext.serviceToken].some(v=>typeof v!=='string'||!v.length)||typeof request.operation!=='string'||typeof request.memoryId!=='string'||typeof request.memoryVersion!=='number'||typeof request.preparationId!=='string')throw new TypeError();
      selected=Object.freeze({authContext,companionAuthContext,request});
    }catch{return deny();}
    let readScope;
    try{
      const started=audienceClock();if(!Number.isSafeInteger(started)||started<0)throw new TypeError();
      const actor=await verify({authContext:selected.authContext});if(actor.status!=='verified')return deny(actor.status);
      const query=Object.freeze({authContext:recipientAuthContext,audience,appId:options.appId,actorShineId:actor.identity.shineId.toLowerCase()});
      const recipient=capture(await verifyResultRecipient(query),recipientFields);
      if(recipient.verified!==true||recipient.audience!==audience||recipient.appId!==query.appId||recipient.actorShineId!==query.actorShineId||typeof recipient.servicePrincipalId!=='string'||! /^[a-z0-9][a-z0-9._:-]{0,127}$/.test(recipient.servicePrincipalId)||!Number.isSafeInteger(recipient.revision)||recipient.revision<1||typeof recipient.validUntil!=='string'||!Number.isSafeInteger(Date.parse(recipient.validUntil))||started>=Date.parse(recipient.validUntil))return deny();
      const checked=audienceClock();
      if(!Number.isSafeInteger(checked)||checked<started||checked>=Date.parse(recipient.validUntil))return deny();
      // Local scope capture is isolated per invocation, including concurrent calls.
      const retrieve=createVeteranCareReadOnlyMemoryRetriever({...options,readSelectedMemory:async q=>{readScope=q;return readSelectedMemory(q);}});
      const prepared=await retrieve(selected);
      if(prepared.status!=='private-memory-read-ready')return deny(prepared.status,prepared.retrievalPerformed);
      if(prepared.result.ownerShineId!==recipient.actorShineId)return deny('denied',true);
      const currentRecipient=capture(await verifyResultRecipient(query),recipientFields);
      if(recipientFields.some(k=>recipient[k]!==currentRecipient[k]))return deny('denied',true);
      // Recipient verification is asynchronous: recheck memory authority after it.
      const final=await evaluate(selected);if(final.status!=='memory-scope-allowed')return deny(final.status,true);
      if(!readScope||Object.keys(readScope).some(k=>readScope[k]!==final.envelope[k])||final.envelope.actorShineId!==recipient.actorShineId)return deny('denied',true);
      const deadline=Math.min(Date.parse(recipient.validUntil),Date.parse(final.envelope.validUntil)),now=audienceClock();
      if(!Number.isSafeInteger(now)||now<checked||now>=deadline)return deny('denied',true);
      return {contract:'shine-foundation/veteran-care-result-audience-v1',schemaVersion:'1.0.0',status:'audience-bound-result',retrievalPerformed:true,resultReturned:true,
        audience,recipient:Object.freeze({appId:recipient.appId,actorShineId:recipient.actorShineId,servicePrincipalId:recipient.servicePrincipalId,revision:recipient.revision,validUntil:new Date(deadline).toISOString()}),
        modelDisclosurePermitted:false,memoryWritePermitted:false,transportPerformed:false,requiresFreshDisclosureCheck:true,result:prepared.result};
    }catch{return deny('unavailable',Boolean(readScope));}
  };
}
