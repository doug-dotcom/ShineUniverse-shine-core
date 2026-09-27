const APP=/^shine\.[a-z0-9][a-z0-9-]*$/;

const response=(status,body={})=>({
  revocationFeedResponse:'shine-foundation/revocation-feed-response-v1',
  schemaVersion:'1.0.0',
  status,
  ...body
});

const requireFunction=(adapters,name)=>{
  if(typeof adapters?.[name]!=='function') throw new TypeError('missing revocation feed adapter: '+name);
};

/** @param {{adapters:any,idFactory?:()=>string,clock?:()=>string}} [options] */
export function createRevocationFeedService({adapters,idFactory=()=>crypto.randomUUID(),clock=()=>new Date().toISOString()}={}){
  for(const name of ['verifyAppCaller','listAppRevocations','getAppRevocationStatus','getAppRevocationHealth','recordAppRevocationDelivery']) requireFunction(adapters,name);

  return async function handleRevocationFeed({appId,afterSequence=0,limit=100,authContext}={}){
    if(!APP.test(appId??'')||
       !Number.isSafeInteger(afterSequence)||afterSequence<0||
       !Number.isSafeInteger(limit)||limit<1||limit>100){
      return response('invalid',{reasonCode:'invalid-revocation-feed-request'});
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
      return response('unavailable',{reasonCode:'revocation-feed-unavailable'});
    }
    if(afterSequence>(status?.checkpointSequence??0)){
      return response('denied',{reasonCode:'revocation-feed-ahead-of-checkpoint'});
    }

    let rows;
    try{
      rows=await adapters.listAppRevocations({
        appId,
        afterSequence,
        limit:limit+1
      });
    }catch{
      return response('unavailable',{reasonCode:'revocation-feed-unavailable'});
    }

    const all=Array.isArray(rows)?rows:[];
    const hasMore=all.length>limit;
    const events=all.slice(0,limit);
    const nextCursor=events.length?events[events.length-1].sequenceNo:afterSequence;
    let deliveryId=null;
    if(events.length){
      deliveryId=idFactory();
      try{
        await adapters.recordAppRevocationDelivery({
          deliveryId,
          appId,
          afterSequence,
          sequenceNos:events.map(event=>event.sequenceNo),
          occurredAt:clock()
        });
      }catch{
        return response('unavailable',{reasonCode:'revocation-delivery-receipt-write-failed'});
      }
    }

    return response('ok',{
      appId,
      afterSequence,
      nextCursor,
      hasMore,
      deliveryId,
      events,
      delivery:{
        checkpointSequence:status?.checkpointSequence??0,
        latestSequence:status?.latestSequence??0,
        pendingCount:status?.pendingCount??0,
        lastAckAt:status?.lastAckAt??null,
        oldestPendingAt:status?.oldestPendingAt??null
      },
      freshness:{
        state:health?.freshnessState??'unknown',
        pendingAgeSeconds:health?.pendingAgeSeconds??0,
        maxPendingAgeSeconds:health?.maxPendingAgeSeconds??900,
        staleAction:health?.staleAction??'observe',
        recommendedAction:health?.recommendedAction??'none'
      }
    });
  };
}
