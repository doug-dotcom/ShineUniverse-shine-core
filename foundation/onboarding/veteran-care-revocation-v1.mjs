import {createVeteranCareSessionIdentityVerifier} from './veteran-care-session-v1.mjs';
import {createGrantRevocationService} from '../gateway/grant-revocation-v1.mjs';
const UUID=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const refuse=(status,reasonCode)=>({status,reasonCode,propagationStatus:'not-verified',consumerEnforcementVerified:false});
function plain(value){
  return !!value&&Object.getPrototypeOf(value)===Object.prototype&&Reflect.ownKeys(value).every(k=>
    typeof k==='string'&&Object.hasOwn(Object.getOwnPropertyDescriptor(value,k),'value'));
}
function id(value){if(typeof value!=='string'||!UUID.test(value))throw new TypeError('invalid server identifier');return value.toLowerCase();}

// Server producer only. The write authority must enforce ownership again and
// confirm durable withdrawal AND the existing app-scoped outbox in one outcome.
export function createVeteranCareRevocationService({getGrantDescriptor,revokeAccessGrant,revocationClock=()=>Date.now(),idFactory=()=>crypto.randomUUID(),...options}={}){
  if([getGrantDescriptor,revokeAccessGrant,revocationClock,idFactory].some(fn=>typeof fn!=='function'))
    throw new TypeError('grant metadata, durable revocation authority, clock and ID factory are required');
  const verify=createVeteranCareSessionIdentityVerifier(options),appId=options.appId,slug=appId.slice('shine.'.length);
  return async function revoke({authContext,request}={}){
    let grantId;
    try{
      if(!plain(request)||Reflect.ownKeys(request).length!==2||request.revoke!==true)throw new TypeError();
      grantId=id(request.grantId);
    }catch{return refuse('denied','vc-revocation-request-invalid');}
    const verified=await verify({authContext});
    if(verified.status!=='verified')return refuse(verified.status,verified.reasonCode);
    const ownerShineId=verified.identity.shineId.toLowerCase();
    let requestId,confirmed=false;
    try{
      const descriptor=await getGrantDescriptor(Object.freeze({appId,ownerShineId,grantId}));
      if(!plain(descriptor)||id(descriptor.grantId)!==grantId||descriptor.appId!==appId||
        id(descriptor.ownerShineId)!==ownerShineId||descriptor.scope!==slug+'.record.read'||
        descriptor.purpose!==slug+'.appointment-preparation')return refuse('denied','vc-revocation-target-unverified');
      requestId=id(idFactory());
      const clock=()=>{const ms=revocationClock();if(!Number.isSafeInteger(ms)||ms<0)throw new TypeError();return new Date(ms).toISOString();};
      const service=createGrantRevocationService({clock,idFactory:()=>id(idFactory()),adapters:{
        // Verified values are private to this invocation; caller values cannot
        // replace them. Generic Foundation mutation and event semantics reused.
        verifyAppCaller:async()=>({appId}),verifyIdentity:async()=>({shineId:ownerShineId}),
        revokeAccessGrant:async args=>{
          const outcome=await revokeAccessGrant(Object.freeze({...args}));
          if(!plain(outcome)||id(outcome.grantId)!==grantId||id(outcome.requestId)!==requestId||
            outcome.outboxRecorded!==true||!['revoked','already-revoked'].includes(outcome.outcome)||
            typeof outcome.reason_code!=='string'||!outcome.reason_code||outcome.reason_code.length>128)
            throw new TypeError('unconfirmed durable withdrawal');
          confirmed=true;return outcome;
        }
      }});
      const result=await service({authContext,envelope:{grantRevocation:'shine-foundation/grant-revocation-v1',schemaVersion:'1.0.0',
        requestId,appId,grantId,revoke:true,requestedAt:clock()}});
      if(!confirmed||!['revoked','already-revoked'].includes(result.status))
        return refuse(result.status==='denied'?'denied':'unavailable','vc-revocation-not-confirmed');
      return {contract:'shine-foundation/veteran-care-revocation-response-v1',schemaVersion:'1.0.0',
        requestId,status:result.status,reasonCode:'vc-grant-withdrawal-recorded',
        propagationStatus:'outbox-recorded',consumerEnforcementVerified:false};
    }catch{return refuse('unavailable','vc-revocation-authority-unavailable');}
  };
}
