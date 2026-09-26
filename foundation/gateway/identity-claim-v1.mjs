const UUID=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const APP=/^shine\.[a-z0-9][a-z0-9-]*$/;
const PROVIDER=/^[a-z0-9][a-z0-9._:-]*$/;

const response=(envelope,status,reasonCode)=>({
  identityClaimResponse:'shine-foundation/identity-claim-response-v1',
  schemaVersion:'1.0.0',
  requestId:envelope?.requestId??null,
  status,
  reasonCode
});

const valid=envelope=>{
  if(!envelope||envelope.identityClaim!=='shine-foundation/identity-claim-v1') return false;
  if(envelope.schemaVersion!=='1.0.0') return false;
  if(!UUID.test(envelope.requestId??'')) return false;
  if(!APP.test(envelope.appId??'')) return false;
  if(!PROVIDER.test(envelope.sourceProviderId??'')||!PROVIDER.test(envelope.targetProviderId??'')) return false;
  if(!Number.isFinite(Date.parse(envelope.requestedAt??''))) return false;
  if(envelope.sourceProviderId===envelope.targetProviderId) return false;
  return true;
};

const requireFunction=(adapters,name)=>{
  if(typeof adapters?.[name]!=='function') throw new TypeError('missing identity claim adapter: '+name);
};

/** @param {{adapters:any, clock?:()=>string, idFactory?:()=>string}} [options] */
export function createIdentityClaimService({
  adapters,
  clock=()=>new Date().toISOString(),
  idFactory=()=>crypto.randomUUID()
}={}){
  for(const name of [
    'verifyAppCaller','verifyClaimSource','verifyClaimTarget',
    'getAppManifest','evaluateDefence','completeIdentityClaim'
  ]) requireFunction(adapters,name);

  return async function handleIdentityClaim({envelope,authContext}={}){
    if(!valid(envelope)) return response(envelope,'invalid','invalid-identity-claim-request');

    const requestedAt=Date.parse(envelope.requestedAt);
    const now=Date.parse(clock());
    if(!Number.isFinite(requestedAt)||!Number.isFinite(now)||
       requestedAt<now-10*60*1000||requestedAt>now+5*60*1000){
      return response(envelope,'invalid','stale-identity-claim-request');
    }

    let verifiedApp;
    try{
      verifiedApp=await adapters.verifyAppCaller({
        authContext,
        claimedAppId:envelope.appId
      });
    }catch{
      return response(envelope,'unavailable','foundation-dependency-unavailable');
    }

    if(!verifiedApp?.appId) return response(envelope,'denied','app-caller-unverified');
    if(verifiedApp.appId!==envelope.appId) return response(envelope,'denied','app-caller-mismatch');

    let source;
    try{
      source=await adapters.verifyClaimSource({
        appId:envelope.appId,
        providerId:envelope.sourceProviderId,
        userToken:authContext?.sourceUserToken
      });
    }catch{
      return response(envelope,'unavailable','foundation-dependency-unavailable');
    }
    if(!source?.authSubject||source.providerId!==envelope.sourceProviderId){
      return response(envelope,'denied','source-identity-unverified');
    }

    let target;
    try{
      target=await adapters.verifyClaimTarget({
        appId:envelope.appId,
        providerId:envelope.targetProviderId,
        jwt:authContext?.targetJwt
      });
    }catch{
      return response(envelope,'unavailable','foundation-dependency-unavailable');
    }
    if(!target?.shineId||!target?.authSubject||target.providerId!==envelope.targetProviderId){
      return response(envelope,'denied','target-identity-unverified');
    }

    let manifest;
    try{
      manifest=await adapters.getAppManifest({appId:envelope.appId});
    }catch{
      return response(envelope,'unavailable','foundation-dependency-unavailable');
    }
    if(!manifest||manifest.appId!==envelope.appId){
      return response(envelope,'denied','app-unregistered');
    }

    let defence;
    try{
      defence=await adapters.evaluateDefence({
        envelope:{
          operation:'identity.claim',
          identityClaim:envelope,
          context:{sourceProviderId:source.providerId,targetProviderId:target.providerId}
        },
        verifiedIdentity:{shineId:target.shineId},
        verifiedApp,
        appManifest:manifest,
        resource:null
      });
    }catch{
      return response(envelope,'unavailable','foundation-dependency-unavailable');
    }
    if(defence?.decision==='deny'){
      return response(envelope,'denied','defence-denied');
    }

    let result;
    try{
      result=await adapters.completeIdentityClaim({
        claimId:idFactory(),
        requestId:envelope.requestId,
        appId:envelope.appId,
        sourceProviderId:source.providerId,
        sourceSubject:source.authSubject,
        targetProviderId:target.providerId,
        targetSubject:target.authSubject,
        targetShineId:target.shineId,
        occurredAt:clock()
      });
    }catch{
      return response(envelope,'unavailable','identity-claim-write-failed');
    }

    if(!result?.outcome||!result?.reason_code){
      return response(envelope,'unavailable','identity-claim-write-failed');
    }

    if(result.outcome==='linked') return response(envelope,'linked',result.reason_code);
    if(result.outcome==='already-linked') return response(envelope,'already-linked',result.reason_code);
    return response(envelope,'denied',result.reason_code);
  };
}
