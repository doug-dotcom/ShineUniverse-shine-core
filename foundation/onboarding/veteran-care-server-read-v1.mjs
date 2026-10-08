import {createVeteranCareCapabilityHealthGate} from './veteran-care-capability-health-v1.mjs';
import {assessVeteranCareProjectBoundary} from './veteran-care-project-boundary-v1.mjs';

export const VETERAN_CARE_SERVER_READ_ADAPTERS=Object.freeze([
  'verifyAppCaller','verifyIdentity','getClaims','getSessionState',
  'verifyIntegrationClient','verifyCompanionUser','getCurrentVCCompanionLink',
  'getMemoryDescriptor','getPreparationContext','getMemoryPermissionContext',
  'getCurrentMemoryPermissionRevision','readSelectedMemory','verifyResultRecipient',
  'getCurrentVCTask','getCurrentResumeCheckpoint','getExistingRetryIdentity',
  'getCurrentCredentialReference','resolveCredentialReference','getCurrentVCCapabilityHealth'
]);
const configurationFields=['mode','issuer','authProjectUrl','databaseProjectUrl','storageProjectUrl'];
const UUID=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
function capture(value,required,optional=[]){
  if(!value||Object.getPrototypeOf(value)!==Object.prototype)throw new TypeError();
  const descriptors=Object.getOwnPropertyDescriptors(value),keys=Reflect.ownKeys(descriptors);
  if(required.some(k=>!Object.hasOwn(descriptors,k))||keys.some(k=>
    ![...required,...optional].includes(k)||!Object.hasOwn(descriptors[k],'value')))throw new TypeError();
  return Object.freeze(Object.fromEntries(keys.map(k=>[k,descriptors[k].value])));
}
const failure=(status='unavailable',retrievalPerformed=false)=>Object.freeze({
  status,reasonCode:'vc-server-read-unavailable',retrievalPerformed,resultReturned:false,
  modelDisclosurePermitted:false,memoryWritePermitted:false,transportPerformed:false
});

// Server composition entry point, not an HTTP handler. Pass only protected,
// independently verified adapters from server code. Configuration status grants
// no authority and proves no live wiring. Each invocation runs the actual fresh
// health/credential/resume/retry/task/recipient/consent/session chain.
export function createVeteranCareServerReadEntryPoint(options={}){
  let configured;
  try{
    const input=capture(options,['configuration','adapters'],['clock']);
    const configuration=capture(input.configuration,configurationFields);
    const adapters=capture(input.adapters,VETERAN_CARE_SERVER_READ_ADAPTERS);
    const clock=Object.hasOwn(input,'clock')?input.clock:()=>Date.now();
    if(assessVeteranCareProjectBoundary(configuration).status!=='ready'||
      typeof clock!=='function'||Object.values(adapters).some(f=>typeof f!=='function'))throw new TypeError();
    const {getClaims,...authority}=adapters;
    configured=Object.freeze({...authority,auth:Object.freeze({getClaims}),configuration,
      appId:'shine.veteran-care',providerId:'supabase:veteran-care',
      clock,bindingClock:clock,memoryClock:clock,releaseClock:clock,audienceClock:clock,
      taskClock:clock,resumeClock:clock,credentialClock:clock,healthClock:clock});
    createVeteranCareCapabilityHealthGate(configured);
  }catch{configured=null;}
  return Object.freeze({
    configurationStatus:configured?'dependencies-configured':'blocked',
    authorityProvided:false,
    async readSelectedMemory(input){
      if(!configured)return failure();
      let request;
      try{
        request=capture(input,['checkpointId','credentialReferenceId','authContext']);
        const authContext=capture(request.authContext,['appToken','jwt']);
        if([request.checkpointId,request.credentialReferenceId].some(v=>typeof v!=='string'||!UUID.test(v))||
          typeof authContext.appToken!=='string'||!authContext.appToken.length||authContext.appToken.length>8192||
          typeof authContext.jwt!=='string'||!authContext.jwt.length||authContext.jwt.length>16384)throw new TypeError();
        request=Object.freeze({...request,authContext});
      }catch{return failure('denied');}
      let performed=false;
      try{
        const gate=createVeteranCareCapabilityHealthGate({...configured,readSelectedMemory:async query=>{
          performed=true;return configured.readSelectedMemory(query);
        }});
        const result=await gate(request);
        if(result.status!=='capability-health-checked-result')
          return failure(result.status==='denied'?'denied':'unavailable',performed);
        // Internal private result only. No JSON response, disclosure callback,
        // log, model call or network transport is introduced by this entry point.
        return Object.freeze({...result,contract:'shine-foundation/veteran-care-server-read-result-v1',
          status:'server-read-result',serverOnly:true,transportPerformed:false});
      }catch{return failure('unavailable',performed);}
    }
  });
}
