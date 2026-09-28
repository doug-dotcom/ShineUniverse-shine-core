import {validateAtlasFeedEvent} from '../runtime/validate-feed-event-v1.mjs';

const UUID=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const TOKEN=/^[a-z0-9][a-z0-9._:-]*$/;
const PRIVATE_CLASSES=new Set(['personal','sensitive']);
const PERMISSION_KEYS=new Set(['ownerShineId','requiredScope','purpose','resourceId','resourceCategory']);

const response=(envelope,status,reasonCode,extra={})=>({
  atlasFeedPublisherAdmissionResponse:'shine-universe/atlas-feed-publisher-admission-response-v1',
  schemaVersion:'1.0.0',
  requestId:envelope?.requestId??null,
  status,
  reasonCode,
  ...extra
});

const isObject=value=>value!==null&&typeof value==='object'&&!Array.isArray(value);

const fresh=(value,clock)=>{
  const requested=Date.parse(value??'');
  const now=Date.parse(clock());
  return Number.isFinite(requested)&&Number.isFinite(now)&&requested>=now-600000&&requested<=now+300000;
};

const hasOnlyKeys=(value,allowed)=>{
  if(!isObject(value)) return false;
  return Object.keys(value).every(key=>allowed.has(key));
};

const grantMatchesResource=(grant,permission)=>{
  if(permission.resourceId!==undefined){
    if(!UUID.test(permission.resourceId)||grant.resourceId!==permission.resourceId) return false;
  }
  if(permission.resourceCategory!==undefined){
    if(typeof permission.resourceCategory!=='string'||!TOKEN.test(permission.resourceCategory)||
      grant.resourceCategory!==permission.resourceCategory) return false;
  }
  return true;
};

export function createAtlasFeedPublisherAdmissionService({
  adapters,
  clock=()=>new Date().toISOString()
}={}){
  for(const name of [
    'verifyAppCaller',
    'verifyIdentity',
    'getAtlasFeedPublisherCapability',
    'getAtlasFeedGrantContext'
  ]){
    if(typeof adapters?.[name]!=='function'){
      throw new TypeError('missing Atlas Feed publisher admission adapter: '+name);
    }
  }

  return async function admit({envelope,authContext}={}){
    if(!isObject(envelope)||
      envelope.atlasFeedPublishAdmissionRequest!=='shine-universe/atlas-feed-publisher-admission-v1'||
      envelope.schemaVersion!=='1.0.0'||
      !UUID.test(envelope.requestId??'')||
      !fresh(envelope.requestedAt,clock)||
      !isObject(envelope.event)||
      !Object.keys(envelope).every(key=>[
        'atlasFeedPublishAdmissionRequest','schemaVersion','requestId','requestedAt','event','permissionContext'
      ].includes(key))){
      return response(envelope,'invalid','invalid-publisher-admission-request');
    }

    const eventValidation=validateAtlasFeedEvent(envelope.event);
    if(!eventValidation.ok){
      return response(envelope,'invalid','invalid-atlas-feed-event',{
        validationErrors:eventValidation.errors.slice(0,12)
      });
    }

    const permission=envelope.permissionContext??{};
    if(!hasOnlyKeys(permission,PERMISSION_KEYS)){
      return response(envelope,'invalid','invalid-permission-context');
    }

    const appId=envelope.event.source.appId;
    let caller;
    try{
      caller=await adapters.verifyAppCaller({authContext,claimedAppId:appId});
    }catch{
      return response(envelope,'unavailable','app-authentication-unavailable');
    }
    if(!caller?.appId) return response(envelope,'denied','publishing-app-unverified');
    if(caller.appId!==appId) return response(envelope,'denied','publishing-app-mismatch');

    let capability;
    try{
      capability=await adapters.getAtlasFeedPublisherCapability({
        appId,
        capabilityId:envelope.event.source.capabilityId
      });
    }catch{
      return response(envelope,'unavailable','publisher-capability-lookup-unavailable');
    }
    if(!capability) return response(envelope,'denied','publisher-capability-not-registered');
    if(capability.appId!==appId) return response(envelope,'denied','publisher-capability-app-mismatch');
    if(capability.invocationState!=='live') return response(envelope,'denied','publisher-capability-not-live');

    const {mode,dataClass,grantId}=envelope.event.audience;
    const privateData=PRIVATE_CLASSES.has(dataClass);

    if(privateData&&mode==='internal'){
      return response(envelope,'denied','private-internal-audience-not-supported');
    }

    let owner=null;
    if(privateData){
      if(typeof permission.ownerShineId!=='string'||!UUID.test(permission.ownerShineId)){
        return response(envelope,'invalid','private-publication-owner-required');
      }
      try{
        owner=await adapters.verifyIdentity({authContext,claimedAppId:appId});
      }catch{
        return response(envelope,'unavailable','owner-authentication-unavailable');
      }
      if(!owner?.shineId) return response(envelope,'denied','owner-session-unverified');
      if(owner.shineId!==permission.ownerShineId){
        return response(envelope,'denied','owner-identity-mismatch');
      }
    }else if(permission.ownerShineId!==undefined&&
      (typeof permission.ownerShineId!=='string'||!UUID.test(permission.ownerShineId))){
      return response(envelope,'invalid','invalid-owner-shine-id');
    }

    let grant=null;
    if(mode==='grant'){
      if(typeof grantId!=='string'||!UUID.test(grantId)){
        return response(envelope,'invalid','grant-audience-requires-foundation-grant-id');
      }
      if(typeof permission.requiredScope!=='string'||!TOKEN.test(permission.requiredScope)||
        typeof permission.purpose!=='string'||!TOKEN.test(permission.purpose)){
        return response(envelope,'invalid','grant-audience-scope-purpose-required');
      }
      if(permission.resourceId===undefined&&permission.resourceCategory===undefined){
        return response(envelope,'invalid','grant-audience-resource-context-required');
      }
      try{
        grant=await adapters.getAtlasFeedGrantContext({grantId});
      }catch{
        return response(envelope,'unavailable','grant-context-lookup-unavailable');
      }
      if(!grant||grant.effectiveStatus!=='active'){
        return response(envelope,'denied','grant-not-active');
      }
      if(grant.scope!==permission.requiredScope||grant.purpose!==permission.purpose){
        return response(envelope,'denied','grant-scope-purpose-mismatch');
      }
      if(!grantMatchesResource(grant,permission)){
        return response(envelope,'denied','grant-resource-mismatch');
      }
      if(privateData&&grant.ownerShineId!==permission.ownerShineId){
        return response(envelope,'denied','grant-owner-mismatch');
      }
    }else if(
      permission.requiredScope!==undefined||
      permission.purpose!==undefined||
      permission.resourceId!==undefined||
      permission.resourceCategory!==undefined
    ){
      return response(envelope,'invalid','grant-context-without-grant-audience');
    }

    return response(envelope,'admitted','publisher-admission-clear',{
      admission:{
        eventId:envelope.event.eventId,
        appId,
        credentialId:caller.credentialId??null,
        capabilityId:capability.capabilityId,
        capabilityVersion:capability.capabilityVersion??null,
        capabilityState:capability.invocationState,
        audienceMode:mode,
        dataClass,
        ownerShineId:permission.ownerShineId??null,
        grantId:grant?.grantId??null
      }
    });
  };
}
