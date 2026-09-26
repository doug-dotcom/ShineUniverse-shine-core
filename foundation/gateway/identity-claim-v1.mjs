const RESPONSE_VERSION='1.0.0';

const requestValid=envelope=>{
  if(envelope?.identityClaimRequest!=='shine-foundation/identity-claim-request-v1') return false;
  if(envelope?.schemaVersion!=='1.0.0'||envelope?.operation!=='identity.claim') return false;
  if(!envelope.claimId||!envelope.requestId||!envelope.appId||!envelope.requestedAt) return false;
  if(envelope.shineId!==undefined||envelope.providerSubject!==undefined||envelope.targetProviderId!==undefined) return false;
  return true;
};

const response=(envelope,status,reasonCode,extra={})=>({
  identityClaimResponse:'shine-foundation/identity-claim-response-v1',
  schemaVersion:RESPONSE_VERSION,
  claimId:envelope?.claimId??null,
  requestId:envelope?.requestId??null,
  appId:envelope?.appId??null,
  status,
  ...(reasonCode?{reasonCode}:{}),
  ...extra
});

const requireFunction=(adapters,name)=>{
  if(typeof adapters?.[name]!=='function') throw new TypeError('missing identity-claim adapter: '+name);
};

/**
 * Links an already-verified opaque appendage identity to an existing canonical Shine identity.
 * The request must carry both identity proofs at the same time. No Shine ID or provider subject
 * is accepted from the caller body, and linking does not create a Vault grant.
 */
export function createIdentityClaimService({adapters,clock=()=>new Date().toISOString()}={}){
  for(const name of [
    'verifyAppCaller','verifyOpaqueIdentityProof','verifyCanonicalIdentityProof',
    'completeIdentityClaim'
  ]) requireFunction(adapters,name);

  return async function claimIdentity({envelope,authContext}={}){
    if(!requestValid(envelope)) return response(envelope,'invalid','invalid-identity-claim-request');
    if(!authContext?.appToken||!authContext?.userToken||!authContext?.jwt){
      return response(envelope,'denied','dual-proof-required');
    }

    const requestedAt=Date.parse(envelope.requestedAt);
    const now=Date.parse(clock());
    if(!Number.isFinite(requestedAt)||!Number.isFinite(now)||requestedAt<now-10*60*1000||requestedAt>now+5*60*1000){
      return response(envelope,'invalid','stale-identity-claim-request');
    }

    let verifiedApp;
    try{
      verifiedApp=await adapters.verifyAppCaller({authContext,claimedAppId:envelope.appId});
    }catch{
      return response(envelope,'unavailable','foundation-dependency-unavailable');
    }
    if(!verifiedApp?.appId) return response(envelope,'denied','app-caller-unverified');
    if(verifiedApp.appId!==envelope.appId) return response(envelope,'denied','app-caller-mismatch');

    let source,target;
    try{
      [source,target]=await Promise.all([
        adapters.verifyOpaqueIdentityProof({
          userToken:authContext.userToken,
          claimedAppId:envelope.appId
        }),
        adapters.verifyCanonicalIdentityProof({jwt:authContext.jwt})
      ]);
    }catch{
      return response(envelope,'unavailable','foundation-dependency-unavailable');
    }

    if(!source?.providerId||!source?.providerSubject){
      return response(envelope,'denied','appendage-proof-unverified');
    }
    if(!target?.shineId||!target?.providerId||!target?.authSubject){
      return response(envelope,'denied','canonical-proof-unverified');
    }

    let result;
    try{
      result=await adapters.completeIdentityClaim({
        claimId:envelope.claimId,
        requestId:envelope.requestId,
        appId:envelope.appId,
        sourceProviderId:source.providerId,
        sourceProviderSubject:source.providerSubject,
        targetProviderId:target.providerId,
        targetProviderSubject:target.authSubject,
        targetShineId:target.shineId,
        occurredAt:clock()
      });
    }catch{
      return response(envelope,'unavailable','identity-claim-write-failed');
    }

    if(!result) return response(envelope,'unavailable','identity-claim-write-failed');
    if(result.outcome==='linked'||result.outcome==='already-linked'){
      return response(envelope,'linked',result.reasonCode??'identity-claim-linked',{
        bindingCreated:result.outcome==='linked'
      });
    }
    if(result.reasonCode==='source-already-bound'){
      return response(envelope,'conflict','identity-claim-conflict');
    }
    return response(envelope,'denied',result.reasonCode??'identity-claim-rejected');
  };
}
