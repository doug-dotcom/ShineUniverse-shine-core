const UUID=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const APP=/^shine\.[a-z0-9][a-z0-9-]*$/;

const response=(envelope,status,reasonCode)=>({
  grantRevokeResponse:'shine-foundation/grant-revoke-response-v1',
  schemaVersion:'1.0.0',
  requestId:envelope?.requestId??null,
  status,
  reasonCode
});

const valid=envelope=>{
  if(!envelope||envelope.grantRevoke!=='shine-foundation/grant-revoke-v1') return false;
  if(envelope.schemaVersion!=='1.0.0') return false;
  if(!UUID.test(envelope.requestId??'')) return false;
  if(!APP.test(envelope.appId??'')) return false;
  if(!UUID.test(envelope.grantId??'')) return false;
  if(!Number.isFinite(Date.parse(envelope.requestedAt??''))) return false;
  return true;
};

const requireFunction=(adapters,name)=>{
  if(typeof adapters?.[name]!=='function') throw new TypeError('missing grant revoke adapter: '+name);
};

export function createGrantRevokeService({
  adapters,
  clock=()=>new Date().toISOString(),
  idFactory=()=>crypto.randomUUID()
}={}){
  for(const name of ['verifyAppCaller','verifyIdentity','revokeAccessGrant']) requireFunction(adapters,name);

  return async function handleGrantRevoke({envelope,authContext}={}){
    if(!valid(envelope)) return response(envelope,'invalid','invalid-grant-revoke-request');

    const requestedAt=Date.parse(envelope.requestedAt);
    const now=Date.parse(clock());
    if(!Number.isFinite(requestedAt)||!Number.isFinite(now)||
       requestedAt<now-10*60*1000||requestedAt>now+5*60*1000){
      return response(envelope,'invalid','stale-grant-revoke-request');
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

    let result;
    try{
      result=await adapters.revokeAccessGrant({
        revocationId:idFactory(),
        grantId:envelope.grantId,
        ownerShineId:verifiedIdentity.shineId,
        appId:envelope.appId,
        revokedAt:clock()
      });
    }catch{
      return response(envelope,'unavailable','grant-revoke-write-failed');
    }

    if(!result?.outcome||!result?.reason_code){
      return response(envelope,'unavailable','grant-revoke-write-failed');
    }
    if(result.outcome==='revoked') return response(envelope,'revoked',result.reason_code);
    if(result.outcome==='already-revoked') return response(envelope,'already-revoked',result.reason_code);
    return response(envelope,'denied',result.reason_code);
  };
}
