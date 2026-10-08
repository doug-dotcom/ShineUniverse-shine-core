import {validateVeteranCareCapabilityInput} from './veteran-care-capabilities-v1.mjs';
import {createVeteranCareSessionIdentityVerifier} from './veteran-care-session-v1.mjs';
const UUID=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const denied=reasonCode=>({status:'denied',reasonCode});
const unavailable=()=>({status:'unavailable',reasonCode:'vc-resource-authority-unavailable'});

// Metadata scoping only. The consumer owns authoritative metadata projection,
// current permission/grant checks and execution. No record content is retrieved.
export function createVeteranCareResourceScopeBuilder({getResourceDescriptor,idFactory=()=>crypto.randomUUID(),...options}={}){
  if(typeof getResourceDescriptor!=='function'||typeof idFactory!=='function')
    throw new TypeError('resource metadata authority and request ID factory are required');
  const verifyIdentity=createVeteranCareSessionIdentityVerifier(options);
  const appId=options.appId,slug=appId.slice('shine.'.length);
  const capabilityId=slug+'.selected_record_read',category=slug+'.record';
  return async function build({authContext,request}={}){
    let selected;
    try{
      if(!request||Object.getPrototypeOf(request)!==Object.prototype) throw new TypeError();
      const d=Object.getOwnPropertyDescriptors(request);
      if(Reflect.ownKeys(d).length!==2||!Object.hasOwn(d,'capabilityId')||!Object.hasOwn(d,'input')||
        !Object.hasOwn(d.capabilityId,'value')||!Object.hasOwn(d.input,'value')||d.capabilityId.value!==capabilityId)
        throw new TypeError();
      selected=validateVeteranCareCapabilityInput({appId,capabilityId,input:d.input.value});
    }catch{return denied('vc-resource-request-invalid');}
    const verified=await verifyIdentity({authContext});
    if(verified.status!=='verified') return verified;
    const recordId=selected.recordId.toLowerCase(),recordVersion=selected.recordVersion;
    const ownerShineId=verified.identity.shineId.toLowerCase();
    try{
      const descriptor=await getResourceDescriptor(Object.freeze({appId,ownerShineId,recordId,recordVersion}));
      if(!descriptor||typeof descriptor.resourceId!=='string'||!UUID.test(descriptor.resourceId)||
        descriptor.resourceId.toLowerCase()!==recordId||descriptor.resourceVersion!==recordVersion||
        typeof descriptor.ownerShineId!=='string'||!UUID.test(descriptor.ownerShineId)||
        descriptor.ownerShineId.toLowerCase()!==ownerShineId||descriptor.category!==category)
        return denied('vc-resource-scope-mismatch');
      const requestId=idFactory();
      if(typeof requestId!=='string'||!UUID.test(requestId)) return unavailable();
      return {
        status:'scope-ready',authorizationApplied:false,executionPermitted:false,
        request:Object.freeze({
          contract:'shine-foundation/veteran-care-resource-request-v1',schemaVersion:'1.0.0',
          requestId:requestId.toLowerCase(),appId,shineId:ownerShineId,capabilityId,
          operation:'read',scope:slug+'.record.read',purpose:slug+'.appointment-preparation',
          resourceId:recordId,resourceVersion:recordVersion,resourceCategory:category
        })
      };
    }catch{return unavailable();}
  };
}
