const response=(status,reasonCode,extra={})=>({
  retryResponse:'shine-foundation/concierge-retry-response-v1',
  schemaVersion:'1.0.0',status,reasonCode,...extra
});
export function createConciergeRetryService({adapters,clock=()=>new Date().toISOString(),idFactory=()=>crypto.randomUUID()}={}){
  for(const n of ['verifyIntegrationClient','claimDueConciergeRetry','finishConciergeRetry']){
    if(typeof adapters?.[n]!=='function') throw new TypeError('missing retry adapter: '+n);
  }
  return {
    async claim({clientId,authContext}={}){
      let client;
      try{client=await adapters.verifyIntegrationClient({authContext,claimedClientId:clientId})}
      catch{return response('unavailable','foundation-dependency-unavailable')}
      if(!client?.clientId||client.clientId!==clientId) return response('denied','integration-client-unverified');
      const claimToken=idFactory();
      try{
        const retry=await adapters.claimDueConciergeRetry({eventId:idFactory(),claimToken,clientId,occurredAt:clock()});
        return response('ok',retry?.claimed?'retry-claimed':'no-retry-due',{retry});
      }catch{return response('unavailable','retry-claim-failed')}
    },
    async finish({envelope,authContext}={}){
      let client;
      try{client=await adapters.verifyIntegrationClient({authContext,claimedClientId:envelope?.clientId})}
      catch{return response('unavailable','foundation-dependency-unavailable')}
      if(!client?.clientId||client.clientId!==envelope?.clientId) return response('denied','integration-client-unverified');
      if(!envelope||envelope.retryFinish!=='shine-foundation/concierge-retry-finish-v1'||
         envelope.schemaVersion!=='1.0.0'||!['completed','retry','abandoned'].includes(envelope.outcome)){
        return response('invalid','invalid-retry-finish');
      }
      try{
        const retry=await adapters.finishConciergeRetry({
          eventId:idFactory(),retryJobId:envelope.retryJobId,claimToken:envelope.claimToken,
          outcome:envelope.outcome,reasonCode:envelope.reasonCode??'retry-finished',
          retryAfter:envelope.retryAfter??null,occurredAt:clock()
        });
        return response('ok','retry-finished',{retry});
      }catch{return response('unavailable','retry-finish-failed')}
    }
  };
}
