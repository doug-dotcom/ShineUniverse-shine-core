const UUID=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const TOKEN=/^[a-z0-9][a-z0-9._:-]*$/;
const reply=(e,status,reasonCode,extra={})=>({
  integrationContextPublishResponse:'shine-foundation/integration-context-publish-response-v1',
  schemaVersion:'1.0.0',requestId:e?.requestId??null,status,reasonCode,...extra
});
const fresh=(v,clock)=>{
  const t=Date.parse(v??''),n=Date.parse(clock());
  return Number.isFinite(t)&&Number.isFinite(n)&&t>=n-600000&&t<=n+300000;
};

export function createIntegrationContextPublishService({adapters,clock=()=>new Date().toISOString(),idFactory=()=>crypto.randomUUID()}={}){
  for(const n of ['verifyAppCaller','resolveIntegrationSubjectOwner','getIntegrationContextPublishEvent','publishIntegrationContextSnapshot']){
    if(typeof adapters?.[n]!=='function')throw new TypeError('missing context publish adapter: '+n);
  }
  return async function handle({envelope,authContext}={}){
    if(!envelope||envelope.integrationContextPublish!=='shine-foundation/integration-context-publish-v1'||
      envelope.schemaVersion!=='1.0.0'||!UUID.test(envelope.requestId??'')||
      !TOKEN.test(envelope.appId??'')||
      typeof envelope.subjectId!=='string'||envelope.subjectId.length<1||envelope.subjectId.length>256||
      !TOKEN.test(envelope.contextKind??'')||
      typeof envelope.resourceId!=='string'||envelope.resourceId.length<1||envelope.resourceId.length>256||
      !Number.isSafeInteger(envelope.sourceRevision)||envelope.sourceRevision<1||
      !envelope.payload||typeof envelope.payload!=='object'||Array.isArray(envelope.payload)||
      !fresh(envelope.requestedAt,clock)){
      return reply(envelope,'invalid','invalid-integration-context-publish');
    }
    if(new TextEncoder().encode(JSON.stringify(envelope.payload)).byteLength>1048576){
      return reply(envelope,'invalid','integration-context-payload-too-large');
    }
    let caller;
    try{caller=await adapters.verifyAppCaller({authContext,claimedAppId:envelope.appId})}
    catch{return reply(envelope,'unavailable','app-authentication-unavailable')}
    if(!caller?.appId)return reply(envelope,'denied','app-unverified');
    if(caller.appId!==envelope.appId)return reply(envelope,'denied','app-mismatch');

    let owner;
    try{owner=await adapters.resolveIntegrationSubjectOwner({appId:envelope.appId,subjectId:envelope.subjectId})}
    catch{return reply(envelope,'unavailable','subject-binding-lookup-unavailable')}
    if(owner?.ambiguous)return reply(envelope,'denied','subject-binding-ambiguous');
    if(!owner?.ownerShineId)return reply(envelope,'denied','subject-binding-not-active');

    let prior;
    try{prior=await adapters.getIntegrationContextPublishEvent({requestId:envelope.requestId})}
    catch{return reply(envelope,'unavailable','context-publish-replay-check-unavailable')}
    if(prior){
      if(prior.appId!==envelope.appId||prior.subjectId!==envelope.subjectId||
        prior.contextKind!==envelope.contextKind||prior.resourceId!==envelope.resourceId){
        return reply(envelope,'invalid','integration-context-publish-replay-conflict');
      }
      return reply(envelope,'already-published','integration-context-already-published',{snapshotId:prior.snapshotId??null});
    }

    let result;
    try{result=await adapters.publishIntegrationContextSnapshot({
      eventId:idFactory(),requestId:envelope.requestId,ownerShineId:owner.ownerShineId,
      appId:envelope.appId,subjectId:envelope.subjectId,contextKind:envelope.contextKind,
      resourceId:envelope.resourceId,sourceRevision:envelope.sourceRevision,payload:envelope.payload,
      sourceUpdatedAt:envelope.sourceUpdatedAt??null,occurredAt:clock()
    })}catch{return reply(envelope,'unavailable','context-snapshot-publish-failed')}

    if(result?.outcome==='published')return reply(envelope,'published',result.reasonCode??'context-snapshot-published',{
      snapshotId:result.snapshotId??null,sourceRevision:result.sourceRevision??envelope.sourceRevision,
      contentHash:result.contentHash??null
    });
    return reply(envelope,'denied',result?.reasonCode??'context-snapshot-publish-denied');
  };
}
