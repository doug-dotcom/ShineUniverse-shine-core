import {createVeteranCareAICallerBinder} from './veteran-care-ai-caller-v1.mjs';
import {createVeteranCareFreshPermissionEvaluator} from './veteran-care-permission-freshness-v1.mjs';
function data(v,keys){
  if(!v||Object.getPrototypeOf(v)!==Object.prototype)throw new TypeError();
  const d=Object.getOwnPropertyDescriptors(v);
  if(Reflect.ownKeys(d).length!==keys.length||keys.some(k=>!Object.hasOwn(d,k)||!Object.hasOwn(d[k],'value')))throw new TypeError();
  return Object.freeze(Object.fromEntries(keys.map(k=>[k,d[k].value])));
}
const refuse=(status,reasonCode)=>({status,decision:'deny',reasonCode,executionPermitted:false});

// Server-private decision metadata. This is not signed or a portable ticket,
// and never grants the model permission to receive private record content.
export function createVeteranCareAIDecisionBuilder({decisionClock=()=>Date.now(),...options}={}){
  if(typeof decisionClock!=='function')throw new TypeError('server decision clock required');
  const bind=createVeteranCareAICallerBinder(options),evaluate=createVeteranCareFreshPermissionEvaluator(options);
  return async function build(input){
    let authContext,aiCallerProof,request,purposeContext;
    try{
      const captured=data(input,['authContext','aiCallerProof','request','purposeContext']);
      authContext=data(captured.authContext,['appToken','jwt']);aiCallerProof=data(captured.aiCallerProof,['proofRef']);
      const selected=data(captured.request,['capabilityId','input']);
      const record=data(selected.input,['recordId','recordVersion']);purposeContext=data(captured.purposeContext,['preparationId']);
      if([authContext.appToken,authContext.jwt,aiCallerProof.proofRef,selected.capabilityId,record.recordId,purposeContext.preparationId].some(v=>typeof v!=='string')||typeof record.recordVersion!=='number')throw new TypeError();
      request=Object.freeze({...selected,input:record});
    }catch{return refuse('denied','vc-ai-decision-input-invalid');}
    const caller=await bind({authContext,aiCallerProof});
    if(caller.status!=='caller-bound')return refuse(caller.status,caller.reasonCode);
    const permission=await evaluate({authContext,request,purposeContext});
    if(permission.decision!=='allow')return refuse(permission.status,permission.reasonCode);
    if(caller.binding.actorShineId!==permission.request.shineId)return refuse('denied','vc-ai-decision-actor-mismatch');
    try{
      const now=decisionClock(),expires=Date.parse(permission.permissionValidUntil);
      if(!Number.isSafeInteger(now)||now<0||!Number.isSafeInteger(expires))throw new TypeError();
      if(now>=expires)return refuse('denied','vc-grant-expired');
      const r=permission.request,b=caller.binding;
      return {status:'decision-ready',decision:'allow-selected-read',executionPermitted:false,
        envelope:Object.freeze({contract:'shine-foundation/veteran-care-ai-permission-decision-v1',schemaVersion:'1.0.0',
          audience:b.targetServiceAppId,foundationAppId:b.foundationAppId,aiCallerId:b.aiCallerId,
          actorShineId:b.actorShineId,keyId:b.keyId,callerRegistrationRevision:b.revision,callerProofRef:b.proofRef,
          requestId:r.requestId,ownerShineId:r.shineId,resourceId:r.resourceId,resourceVersion:r.resourceVersion,
          capabilityId:r.capabilityId,operation:r.operation,scope:r.scope,purpose:r.purpose,
          preparationId:r.purposeBinding.preparationId,grantId:permission.grantId,validUntil:permission.permissionValidUntil,
          executionPermitted:false,modelDisclosurePermitted:false,requiresFreshExecutionCheck:true})};
    }catch{return refuse('unavailable','vc-ai-decision-clock-unavailable');}
  };
}
