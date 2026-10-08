import {classifyCapabilityHealthEvidence} from '../runtime/supabase-runtime-adapters-v1.mjs';
import {createVeteranCareSessionIdentityVerifier} from './veteran-care-session-v1.mjs';
import {createVeteranCareCredentialReferenceGate} from './veteran-care-credential-reference-v1.mjs';
export const VETERAN_CARE_READ_HEALTH_DEPENDENCIES=Object.freeze(['vc-session','companion-link','selected-memory-read','task-authority','resume-checkpoint','retry-identity','credential-reference','result-recipient']);
const capabilityId='veteran-care.selected_memory_read';
const UUID=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
function capture(v,keys){
  if(!v||Object.getPrototypeOf(v)!==Object.prototype)throw new TypeError();
  const d=Object.getOwnPropertyDescriptors(v);
  if(Reflect.ownKeys(d).length!==keys.length||keys.some(k=>!Object.hasOwn(d,k)||!Object.hasOwn(d[k],'value')))throw new TypeError();
  return Object.freeze(Object.fromEntries(keys.map(k=>[k,d[k].value])));
}
const fail=(status='unavailable',retrievalPerformed=false)=>({status,reasonCode:'vc-capability-read-unavailable',retrievalPerformed,resultReturned:false,modelDisclosurePermitted:false});
// Availability evidence is a conservative additional gate, never permission.
// Collector probes must be read-only and must not disclose private user content.
export function createVeteranCareCapabilityHealthGate({getCurrentVCCapabilityHealth,readSelectedMemory,healthClock=()=>Date.now(),...options}={}){
  if(options.appId!=='shine.veteran-care'||[getCurrentVCCapabilityHealth,readSelectedMemory,healthClock].some(f=>typeof f!=='function'))throw new TypeError('current dependency evidence required');
  const verify=createVeteranCareSessionIdentityVerifier(options);
  createVeteranCareCredentialReferenceGate({...options,readSelectedMemory});
  return async function selectedRead(input){
    let request;
    try{
      const i=capture(input,['checkpointId','credentialReferenceId','authContext']),authContext=capture(i.authContext,['appToken','jwt']);
      if([i.checkpointId,i.credentialReferenceId].some(v=>typeof v!=='string'||!UUID.test(v))||Object.values(authContext).some(v=>typeof v!=='string'||!v.length))throw new TypeError();
      request=Object.freeze({...i,authContext});
    }catch{return fail('denied');}
    let performed=false,blocked=false;
    try{
      let last=healthClock();if(!Number.isSafeInteger(last)||last<0)throw new TypeError();
      const now=()=>{const t=healthClock();if(!Number.isSafeInteger(t)||t<last)throw new TypeError();last=t;return t;};
      const actor=await verify({authContext:request.authContext});if(actor.status!=='verified')return fail(actor.status);
      async function health(){
        const evidence=[];
        for(const dependencyId of VETERAN_CARE_READ_HEALTH_DEPENDENCIES){
          const q=Object.freeze({foundationAppId:options.appId,capabilityId,dependencyId});
          const r=capture(await getCurrentVCCapabilityHealth(q),[...Object.keys(q),'healthStatus','lastOutcome','lastEventAt','evidenceRef','evidenceMode']);
          if(Object.keys(q).some(k=>r[k]!==q[k])||r.healthStatus!=='available'||r.lastOutcome!=='success'||typeof r.evidenceRef!=='string'||!UUID.test(r.evidenceRef)||!['live','synthetic'].includes(r.evidenceMode))return null;
          const freshness=classifyCapabilityHealthEvidence(r.lastEventAt,now());if(freshness.evidence_freshness!=='fresh')return null;
          evidence.push(Object.freeze({dependencyId,evidenceRef:r.evidenceRef,evidenceMode:r.evidenceMode,lastEventAt:r.lastEventAt,validUntil:new Date(Date.parse(r.lastEventAt)+freshness.evidence_max_age_ms).toISOString()}));
        }
        const deadline=Math.min(...evidence.map(r=>Date.parse(r.validUntil)));if(now()>=deadline)return null;
        return {evidence:Object.freeze(evidence),deadline};
      }
      if(!await health())return fail();
      const gate=createVeteranCareCredentialReferenceGate({...options,readSelectedMemory:async q=>{
        if(!await health()||q.ownerShineId!==actor.identity.shineId.toLowerCase()){blocked=true;throw new Error('capability unavailable');}
        performed=true;return readSelectedMemory(q);
      }});
      const result=await gate(request);
      if(blocked)return fail('unavailable',performed);
      if(result.status!=='credential-reference-result')return fail(result.status,performed);
      const final=await health();if(!final||result.recipient.actorShineId!==actor.identity.shineId.toLowerCase())return fail('unavailable',performed);
      const deadline=Math.min(final.deadline,Date.parse(result.recipient.validUntil));if(now()>=deadline)return fail('unavailable',performed);
      return {...result,contract:'shine-foundation/veteran-care-capability-health-result-v1',status:'capability-health-checked-result',
        recipient:Object.freeze({...result.recipient,validUntil:new Date(deadline).toISOString()}),checkpoint:Object.freeze({...result.checkpoint,validUntil:new Date(deadline).toISOString()}),
        credentialReference:Object.freeze({...result.credentialReference,validUntil:new Date(deadline).toISOString()}),
        capabilityHealth:Object.freeze({capabilityId,dependencies:final.evidence,validUntil:new Date(deadline).toISOString(),authorityProvided:false}),requiresFreshCapabilityHealthCheck:true};
    }catch{return fail('unavailable',performed);}
  };
}
