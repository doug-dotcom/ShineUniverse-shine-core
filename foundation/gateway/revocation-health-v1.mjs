const APP=/^shine\.[a-z0-9][a-z0-9-]*$/;

const response=(status,body={})=>({
  revocationHealthResponse:'shine-foundation/revocation-health-response-v1',
  schemaVersion:'1.0.0',
  status,
  ...body
});

const requireFunction=(adapters,name)=>{
  if(typeof adapters?.[name]!=='function') throw new TypeError('missing revocation health adapter: '+name);
};

export function createRevocationHealthService({adapters}={}){
  for(const name of ['verifyAppCaller','getAppRevocationStatus','getAppRevocationHealth']) requireFunction(adapters,name);

  return async function handleRevocationHealth({appId,authContext}={}){
    if(!APP.test(appId??'')){
      return response('invalid',{reasonCode:'invalid-revocation-health-request'});
    }

    let verifiedApp;
    try{
      verifiedApp=await adapters.verifyAppCaller({authContext,claimedAppId:appId});
    }catch{
      return response('unavailable',{reasonCode:'foundation-dependency-unavailable'});
    }
    if(!verifiedApp?.appId){
      return response('denied',{reasonCode:'app-caller-unverified'});
    }
    if(verifiedApp.appId!==appId){
      return response('denied',{reasonCode:'app-caller-mismatch'});
    }

    let status,health;
    try{
      [status,health]=await Promise.all([
        adapters.getAppRevocationStatus({appId}),
        adapters.getAppRevocationHealth({appId})
      ]);
    }catch{
      return response('unavailable',{reasonCode:'revocation-health-unavailable'});
    }

    if(!health) return response('unavailable',{reasonCode:'revocation-health-unavailable'});

    return response('ok',{
      appId,
      checkpointSequence:health.checkpointSequence,
      latestSequence:health.latestSequence,
      pendingCount:health.pendingCount,
      oldestPendingAt:health.oldestPendingAt??null,
      pendingAgeSeconds:health.pendingAgeSeconds,
      maxPendingAgeSeconds:health.maxPendingAgeSeconds,
      freshnessState:health.freshnessState,
      staleAction:health.staleAction,
      recommendedAction:health.recommendedAction,
      lastAckAt:status?.lastAckAt??null
    });
  };
}
