import {appManifestDeclaresPermission} from '../integration-kit/permission-engine-v1.mjs';

const UUID=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const APP=/^shine\.[a-z0-9][a-z0-9-]*$/;
const TOKEN=/^[a-z0-9][a-z0-9._:-]*$/;
const CATEGORY=/^[a-z0-9][a-z0-9._-]*$/;

const response=(envelope,status,reasonCode)=>({
  grantConsentResponse:'shine-foundation/grant-consent-response-v1',
  schemaVersion:'1.0.0',
  requestId:envelope?.requestId??null,
  status,
  reasonCode
});

const valid=envelope=>{
  if(!envelope||envelope.grantConsent!=='shine-foundation/grant-consent-v1') return false;
  if(envelope.schemaVersion!=='1.0.0') return false;
  if(!UUID.test(envelope.requestId??'')) return false;
  if(!APP.test(envelope.appId??'')) return false;
  if(!TOKEN.test(envelope.scope??'')||!TOKEN.test(envelope.purpose??'')) return false;
  if(!CATEGORY.test(envelope.resourceCategory??'')) return false;
  if(envelope.resourceId!==undefined&&envelope.resourceId!==null&&!UUID.test(envelope.resourceId)) return false;
  if(envelope.consent!==true) return false;
  if(!Number.isFinite(Date.parse(envelope.requestedAt??''))) return false;
  return true;
};

const requireFunction=(adapters,name)=>{
  if(typeof adapters?.[name]!=='function') throw new TypeError('missing grant consent adapter: '+name);
};

/** @param {{adapters:any, clock?:()=>string, idFactory?:()=>string}} [options] */
export function createGrantConsentService({
  adapters,
  clock=()=>new Date().toISOString(),
  idFactory=()=>crypto.randomUUID()
}={}){
  for(const name of [
    'verifyAppCaller','verifyIdentity','getAppManifest','getVaultResource',
    'evaluateDefence','issueAccessGrant'
  ]) requireFunction(adapters,name);

  return async function handleGrantConsent({envelope,authContext}={}){
    if(!valid(envelope)) return response(envelope,'invalid','invalid-grant-consent-request');

    const requestedAt=Date.parse(envelope.requestedAt);
    const now=Date.parse(clock());
    if(!Number.isFinite(requestedAt)||!Number.isFinite(now)||
       requestedAt<now-10*60*1000||requestedAt>now+5*60*1000){
      return response(envelope,'invalid','stale-grant-consent-request');
    }

    let verifiedApp;
    try{
      verifiedApp=await adapters.verifyAppCaller({authContext,claimedAppId:envelope.appId});
    }catch{
      return response(envelope,'unavailable','foundation-dependency-unavailable');
    }
    if(!verifiedApp?.appId) return response(envelope,'denied','app-caller-unverified');
    if(verifiedApp.appId!==envelope.appId) return response(envelope,'denied','app-caller-mismatch');

    let verifiedIdentity;
    try{
      verifiedIdentity=await adapters.verifyIdentity({authContext,claimedAppId:envelope.appId});
    }catch{
      return response(envelope,'unavailable','foundation-dependency-unavailable');
    }
    if(!verifiedIdentity?.shineId) return response(envelope,'denied','identity-unverified');

    let manifest;
    try{
      manifest=await adapters.getAppManifest({appId:envelope.appId});
    }catch{
      return response(envelope,'unavailable','foundation-dependency-unavailable');
    }
    if(!manifest||manifest.appId!==envelope.appId) return response(envelope,'denied','app-unregistered');

    const permission={
      requestId:envelope.requestId,
      appId:envelope.appId,
      shineId:verifiedIdentity.shineId,
      scope:envelope.scope,
      purpose:envelope.purpose,
      resourceCategory:envelope.resourceCategory,
      ...(envelope.resourceId?{resourceId:envelope.resourceId}:{})
    };
    if(!appManifestDeclaresPermission(manifest,permission)){
      return response(envelope,'denied','scope-not-declared');
    }

    let resource;
    try{
      resource=await adapters.getVaultResource({
        resourceId:envelope.resourceId,
        resourceCategory:envelope.resourceCategory,
        ownerShineId:verifiedIdentity.shineId
      });
    }catch{
      return response(envelope,'unavailable','foundation-dependency-unavailable');
    }
    if(!resource) return response(envelope,'denied','resource-not-found');
    if(resource.ownerShineId!==verifiedIdentity.shineId){
      return response(envelope,'denied','resource-owner-mismatch');
    }
    if(resource.category!==envelope.resourceCategory){
      return response(envelope,'denied','resource-mismatch');
    }

    let defence;
    try{
      defence=await adapters.evaluateDefence({
        envelope:{operation:'grant.consent',grantConsent:envelope,permission},
        verifiedIdentity,verifiedApp,appManifest:manifest,resource
      });
    }catch{
      return response(envelope,'unavailable','foundation-dependency-unavailable');
    }
    if(defence?.decision==='deny') return response(envelope,'denied','defence-denied');

    let result;
    try{
      result=await adapters.issueAccessGrant({
        consentId:idFactory(),
        grantId:idFactory(),
        requestId:envelope.requestId,
        ownerShineId:verifiedIdentity.shineId,
        appId:envelope.appId,
        scope:envelope.scope,
        purpose:envelope.purpose,
        resourceId:envelope.resourceId??null,
        resourceCategory:envelope.resourceCategory,
        occurredAt:clock()
      });
    }catch{
      return response(envelope,'unavailable','grant-consent-write-failed');
    }

    if(!result?.outcome||!result?.reason_code){
      return response(envelope,'unavailable','grant-consent-write-failed');
    }
    if(result.outcome==='granted') return response(envelope,'granted',result.reason_code);
    if(result.outcome==='already-granted') return response(envelope,'already-granted',result.reason_code);
    return response(envelope,'denied',result.reason_code);
  };
}
