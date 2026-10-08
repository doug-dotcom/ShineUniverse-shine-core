import {createVeteranCareSessionIdentityVerifier} from './veteran-care-session-v1.mjs';
const UUID=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const plain=v=>!!v&&Object.getPrototypeOf(v)===Object.prototype&&Reflect.ownKeys(v).every(k=>typeof k==='string'&&Object.hasOwn(Object.getOwnPropertyDescriptor(v,k),'value'));
const refusal=(status,reasonCode)=>({status,reasonCode,executionPermitted:false});

// Both adapters are trusted server authority. proofRef is an opaque lookup
// handle, never proof by itself. AI owns verification of the signed request;
// its adapter must correlate that request to this exact Foundation principal.
export function createVeteranCareAICallerBinder({getAICallerRegistration,resolveVerifiedAICallerProof,...options}={}){
  if(options.appId!=='shine.veteran-care'||typeof getAICallerRegistration!=='function'||typeof resolveVerifiedAICallerProof!=='function')
    throw new TypeError('exact VC identity, caller registry and signed-proof authority required');
  const verify=createVeteranCareSessionIdentityVerifier(options);
  return async function bind(input){
    try{
      if(!plain(input)||Reflect.ownKeys(input).length!==2||!plain(input.authContext)||!plain(input.aiCallerProof)||
        Reflect.ownKeys(input.aiCallerProof).length!==1||typeof input.aiCallerProof.proofRef!=='string'||!UUID.test(input.aiCallerProof.proofRef))
        return refusal('denied','vc-ai-caller-input-invalid');
      const proofRef=input.aiCallerProof.proofRef.toLowerCase(),authContext=Object.freeze({...input.authContext});
      const identity=await verify({authContext});
      if(identity.status!=='verified')return refusal(identity.status,identity.reasonCode);
      const query=Object.freeze({foundationAppId:options.appId,actorShineId:identity.identity.shineId.toLowerCase()});
      const registration=await getAICallerRegistration(query);
      if(!plain(registration)||registration.foundationAppId!==options.appId||registration.aiCallerId!=='shine-veteran-care'||
        registration.targetServiceAppId!=='shine.ai'||registration.status!=='active'||
        !Number.isSafeInteger(registration.revision)||registration.revision<1||
        typeof registration.keyId!=='string'||! /^[a-z0-9][a-z0-9._-]{0,63}$/.test(registration.keyId))
        return refusal('denied','vc-ai-caller-registration-unverified');
      const captured=Object.freeze({foundationAppId:registration.foundationAppId,aiCallerId:registration.aiCallerId,
        targetServiceAppId:registration.targetServiceAppId,keyId:registration.keyId,revision:registration.revision});
      const proof=await resolveVerifiedAICallerProof(Object.freeze({...query,proofRef,aiCallerId:captured.aiCallerId,keyId:captured.keyId}));
      if(!plain(proof)||proof.verified!==true||proof.proofRef!==proofRef||proof.foundationAppId!==query.foundationAppId||
        proof.actorShineId!==query.actorShineId||proof.appId!==captured.aiCallerId||proof.keyId!==captured.keyId)
        return refusal('denied','vc-ai-caller-proof-unverified');
      return {status:'caller-bound',executionPermitted:false,binding:Object.freeze({
        contract:'shine-foundation/veteran-care-ai-caller-binding-v1',schemaVersion:'1.0.0',
        ...captured,actorShineId:query.actorShineId,proofRef})};
    }catch{return refusal('unavailable','vc-ai-caller-authority-unavailable');}
  };
}
