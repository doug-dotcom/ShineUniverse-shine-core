import {appManifestDeclaresPermission} from '../integration-kit/permission-engine-v1.mjs';

const RESPONSE_VERSION='1.0.0';
const requestValid=envelope=>{
  if(envelope?.identityClaimRequest!=='shine-foundation/identity-claim-request-v1') return false;
  if(envelope?.schemaVersion!=='1.0.0'||envelope?.operation!=='identity.claim') return false;
  if(!envelope.claimId||!envelope.appId||!envelope.requestedAt) return false;
  if(envelope.shineId!==undefined||envelope.providerSubject!==undefined) return false;
  const p=envelope.permission;
  if(!p?.scope||!p?.purpose||!p?.resourceCategory) return false;
  return true;
};

const response=(envelope,status,reasonCode,extra={})=>({
  identityClaimResponse:'shine-foundation/identity-claim-response-v1',
  schemaVersion:RESPONSE_VERSION,
  claimId:envelope?.claimId??null,
  appId:envelope?.appId??null,
  status,
  ...(reasonCode?{reasonCode}:{}),
  ...extra
});

const requireFunction=(adapters,name)=>{
  if(typeof adapters?.[name]!=='function') throw new TypeError('missing identity-claim adapter: '+name);
};

/**
 * Links an already-verified opaque appendage identity to an already-existing canonical Shine identity.
 * Both proofs must be present in the same request. The caller never supplies a Shine ID.
 */
export function createIdentityClaimService({adapters}={}){
  for(const name of [
    'verifyAppCaller','verifyOpaqueIdentityProof','verifyCanonicalIdentityProof',
    'getAppManifest','claimIdentityAndGrant'
  ]) requireFunction(adapters,name);

  return async function claimIdentity({envelope,authContext}={}){
    if(!requestValid(envelope)) return response(envelope,'invalid','invalid-identity-claim-request');
    if(!authContext?.appToken||!authContext?.userToken||!authContext?.jwt){
      return response(envelope,'denied','dual-proof-required');
    }

    let verifiedApp;
    try{
      verifiedApp=await adapters.verifyAppCaller({authContext,claimedAppId:envelope.appId});
    }catch{
      return response(envelope,'unavailable','foundation-dependency-unavailable');
    }
    if(!verifiedApp?.appId) return response(envelope,'denied','app-caller-unverified');
    if(verifiedApp.appId!==envelope.appId) return response(envelope,'denied','app-caller-mismatch');

    let opaque,canonical;
    try{
      [opaque,canonical]=await Promise.all([
        adapters.verifyOpaqueIdentityProof({
          userToken:authContext.userToken,
          claimedAppId:envelope.appId
        }),
        adapters.verifyCanonicalIdentityProof({jwt:authContext.jwt})
      ]);
    }catch{
      return response(envelope,'unavailable','foundation-dependency-unavailable');
    }

    if(!opaque?.providerId||!opaque?.providerSubject){
      return response(envelope,'denied','appendage-proof-unverified');
    }
    if(!canonical?.shineId){
      return response(envelope,'denied','canonical-proof-unverified');
    }

    let manifest;
    try{ manifest=await adapters.getAppManifest({appId:envelope.appId}); }
    catch{ return response(envelope,'unavailable','foundation-dependency-unavailable'); }

    const permission={
      appId:envelope.appId,
      scope:envelope.permission.scope,
      purpose:envelope.permission.purpose,
      resourceCategory:envelope.permission.resourceCategory,
      requestedAt:envelope.requestedAt
    };
    if(!manifest||manifest.appId!==envelope.appId||!appManifestDeclaresPermission(manifest,permission)){
      return response(envelope,'denied','permission-not-declared');
    }

    let linked;
    try{
      linked=await adapters.claimIdentityAndGrant({
        claimId:envelope.claimId,
        appId:envelope.appId,
        providerId:opaque.providerId,
        providerSubject:opaque.providerSubject,
        shineId:canonical.shineId,
        scope:permission.scope,
        purpose:permission.purpose,
        resourceCategory:permission.resourceCategory,
        requestedAt:envelope.requestedAt
      });
    }catch{
      return response(envelope,'unavailable','identity-claim-write-failed');
    }

    if(linked?.outcome==='conflict'){
      return response(envelope,'conflict','identity-claim-conflict');
    }
    if(linked?.outcome!=='linked'){
      return response(envelope,'denied','identity-claim-rejected');
    }

    return response(envelope,'linked','identity-linked',{
      bindingCreated:Boolean(linked.bindingCreated),
      grantCreated:Boolean(linked.grantCreated)
    });
  };
}
