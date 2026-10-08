import {createVeteranCareSessionIdentityVerifier} from './veteran-care-session-v1.mjs';
const UUID=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const plain=v=>!!v&&Object.getPrototypeOf(v)===Object.prototype&&Reflect.ownKeys(v).every(k=>typeof k==='string'&&Object.hasOwn(Object.getOwnPropertyDescriptor(v,k),'value'));
const uuid=v=>typeof v==='string'&&UUID.test(v);
const positive=v=>Number.isSafeInteger(v)&&v>0;
const refuse=(status,reasonCode)=>({status,reasonCode,acknowledgementVerified:false,consumerEnforcementVerified:false});

// Read-only owner projection. A recorded app acknowledgement is not independent
// proof that caches, in-flight work or previously delivered copies were cleared.
export function createVeteranCareRevocationStatusReader({getGrantRevocationEvidence,...options}={}){
  if(typeof getGrantRevocationEvidence!=='function')throw new TypeError('authoritative grant revocation evidence is required');
  const verify=createVeteranCareSessionIdentityVerifier(options),appId=options.appId,slug=appId.slice('shine.'.length);
  return async function read({authContext,request}={}){
    let grantId;
    try{
      if(!plain(request)||Reflect.ownKeys(request).length!==1||!uuid(request.grantId))return refuse('denied','vc-revocation-status-request-invalid');
      grantId=request.grantId.toLowerCase();
    }catch{return refuse('denied','vc-revocation-status-request-invalid');}
    const identity=await verify({authContext});
    if(identity.status!=='verified')return refuse(identity.status,identity.reasonCode);
    const ownerShineId=identity.identity.shineId.toLowerCase();
    try{
      const evidence=await getGrantRevocationEvidence(Object.freeze({appId,ownerShineId,grantId}));
      if(!plain(evidence)||evidence.complete!==true||!uuid(evidence.grantId)||evidence.grantId.toLowerCase()!==grantId||
        evidence.appId!==appId||!uuid(evidence.ownerShineId)||evidence.ownerShineId.toLowerCase()!==ownerShineId||
        evidence.scope!==slug+'.record.read'||evidence.purpose!==slug+'.appointment-preparation')
        return refuse('denied','vc-revocation-status-target-unverified');
      const withdrawal=evidence.withdrawal,delivery=evidence.delivery,ack=evidence.acknowledgement;
      if(!plain(withdrawal))throw new TypeError();
      let status='not-recorded';
      if(withdrawal.status==='not-recorded'){
        if(Reflect.ownKeys(withdrawal).length!==1||delivery!==null||ack!==null)throw new TypeError();
      }else{
        if(withdrawal.status!=='recorded'||!positive(withdrawal.sequenceNo))throw new TypeError();
        status='withdrawal-recorded';
        if(delivery!==null){
          if(!plain(delivery)||!uuid(delivery.deliveryId)||delivery.appId!==appId||
            !Number.isSafeInteger(delivery.afterSequence)||delivery.afterSequence<0||
            !Array.isArray(delivery.sequenceNos)||delivery.sequenceNos.length<1||delivery.sequenceNos.length>100)throw new TypeError();
          // Sparse global sequences are valid; app-specific delivery must still
          // be strictly ordered, include this event and end at the ack target.
          const sequenceNos=Array.from(delivery.sequenceNos);
          if(sequenceNos.some((n,i)=>!positive(n)||n<=(i?sequenceNos[i-1]:delivery.afterSequence))||
            !sequenceNos.includes(withdrawal.sequenceNo))throw new TypeError();
          status='delivered';
          if(ack!==null){
            if(!plain(ack)||ack.appId!==appId||!uuid(ack.deliveryId)||ack.deliveryId.toLowerCase()!==delivery.deliveryId.toLowerCase()||
              !uuid(ack.requestId)||!['advanced','already-acked'].includes(ack.outcome)||
              ack.sequenceNo!==sequenceNos.at(-1)||!positive(ack.checkpointSequence)||ack.checkpointSequence<ack.sequenceNo)throw new TypeError();
            status='acknowledged';
          }
        }else if(ack!==null)throw new TypeError();
      }
      return {contract:'shine-foundation/veteran-care-revocation-status-v1',schemaVersion:'1.0.0',status,
        reasonCode:'vc-revocation-status-verified',acknowledgementVerified:status==='acknowledged',consumerEnforcementVerified:false};
    }catch{return refuse('unavailable','vc-revocation-evidence-unavailable');}
  };
}
