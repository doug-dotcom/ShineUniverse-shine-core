import {createVeteranCareSessionIdentityVerifier} from './veteran-care-session-v1.mjs';
import {createVeteranCareResumeRecheckGate} from './veteran-care-resume-recheck-v1.mjs';
const UUID=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
const fields=['credentialReferenceId','foundationAppId','ownerShineId','purpose','audience','status','revision','validUntil'];
function capture(v,keys){
  if(!v||Object.getPrototypeOf(v)!==Object.prototype)throw new TypeError();
  const d=Object.getOwnPropertyDescriptors(v);
  if(Reflect.ownKeys(d).length!==keys.length||keys.some(k=>!Object.hasOwn(d,k)||!Object.hasOwn(d[k],'value')))throw new TypeError();
  return Object.freeze(Object.fromEntries(keys.map(k=>[k,d[k].value])));
}
const deny=(status='denied',retrievalPerformed=false)=>({status,reasonCode:'vc-credential-reference-unverified',retrievalPerformed,resultReturned:false,modelDisclosurePermitted:false});
// Reference metadata is not a bearer credential. A protected resolver releases
// fresh credentials internally; current session/L/recipient checks still apply.
export function createVeteranCareCredentialReferenceGate({getCurrentCredentialReference,resolveCredentialReference,readSelectedMemory,credentialClock=()=>Date.now(),...options}={}){
  if(options.appId!=='shine.veteran-care'||[getCurrentCredentialReference,resolveCredentialReference,readSelectedMemory,credentialClock].some(f=>typeof f!=='function'))throw new TypeError('protected current credential reference and resolver required');
  const verify=createVeteranCareSessionIdentityVerifier(options);
  createVeteranCareResumeRecheckGate({...options,readSelectedMemory});
  return async function useReference(input){
    let checkpointId,credentialReferenceId,authContext;
    try{
      const i=capture(input,['checkpointId','credentialReferenceId','authContext']);checkpointId=i.checkpointId;credentialReferenceId=i.credentialReferenceId;
      authContext=capture(i.authContext,['appToken','jwt']);
      if([checkpointId,credentialReferenceId].some(v=>typeof v!=='string'||!UUID.test(v))||Object.values(authContext).some(v=>typeof v!=='string'||!v.length))throw new TypeError();
    }catch{return deny();}
    let performed=false,refused=false;
    try{
      let last=credentialClock();if(!Number.isSafeInteger(last)||last<0)throw new TypeError();
      const now=()=>{const t=credentialClock();if(!Number.isSafeInteger(t)||t<last)throw new TypeError();last=t;return t;};
      const actor=await verify({authContext});if(actor.status!=='verified')return deny(actor.status);
      const query=Object.freeze({credentialReferenceId,foundationAppId:options.appId,ownerShineId:actor.identity.shineId.toLowerCase(),purpose:'veteran-care.resume',audience:'vc-trusted-server'});
      const current=async()=>{
        const r=capture(await getCurrentCredentialReference(query),fields),t=now();
        if(Object.keys(query).some(k=>r[k]!==query[k])||r.status!=='active'||!Number.isSafeInteger(r.revision)||r.revision<1||typeof r.validUntil!=='string'||!Number.isSafeInteger(Date.parse(r.validUntil))||t>=Date.parse(r.validUntil))return null;
        return r;
      };
      const first=await current();if(!first)return deny();
      const same=r=>r&&fields.every(k=>r[k]===first[k]);
      const resolved=capture(await resolveCredentialReference(Object.freeze({...query,revision:first.revision})),['credentialReferenceId','revision','companionAuthContext','recipientAuthContext']);
      const companionAuthContext=capture(resolved.companionAuthContext,['clientToken','userToken']),recipientAuthContext=capture(resolved.recipientAuthContext,['serviceToken']);
      if(resolved.credentialReferenceId!==credentialReferenceId||resolved.revision!==first.revision||[...Object.values(companionAuthContext),recipientAuthContext.serviceToken].some(v=>typeof v!=='string'||!v.length))return deny();
      const resume=createVeteranCareResumeRecheckGate({...options,readSelectedMemory:async q=>{
        if(!same(await current())||q.ownerShineId!==query.ownerShineId){refused=true;throw new Error('credential reference changed');}
        performed=true;return readSelectedMemory(q);
      }});
      const result=await resume({checkpointId,authContext,companionAuthContext,recipientAuthContext});
      if(refused)return deny('denied',performed);
      if(result.status!=='resume-rechecked-result')return deny(result.status,performed);
      if(!same(await current())||result.recipient.actorShineId!==query.ownerShineId)return deny('denied',performed);
      const deadline=Math.min(Date.parse(first.validUntil),Date.parse(result.recipient.validUntil));if(now()>=deadline)return deny('denied',performed);
      return {...result,contract:'shine-foundation/veteran-care-credential-reference-result-v1',status:'credential-reference-result',
        recipient:Object.freeze({...result.recipient,validUntil:new Date(deadline).toISOString()}),checkpoint:Object.freeze({...result.checkpoint,validUntil:new Date(deadline).toISOString()}),
        credentialReference:Object.freeze({credentialReferenceId,revision:first.revision,validUntil:new Date(deadline).toISOString()}),credentialsReturned:false,requiresFreshCredentialResolution:true};
    }catch{return deny('unavailable',performed);}
  };
}
