const UUID=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const CLIENT=/^[a-z0-9][a-z0-9._:-]*$/;
const HASH=/^[a-f0-9]{64}$/i;
const response=(version,status,reasonCode,extra={})=>({
  integrationResponse:'shine-foundation/integration-delegation-refresh-response-v'+version,
  schemaVersion:version===2?'2.0.0':'1.0.0',status,reasonCode,...extra
});
const randomSecret=()=>{
  const bytes=new Uint8Array(32); crypto.getRandomValues(bytes);
  return Array.from(bytes,b=>b.toString(16).padStart(2,'0')).join('');
};
const sha256Hex=async value=>{
  const digest=await crypto.subtle.digest('SHA-256',new TextEncoder().encode(value));
  return [...new Uint8Array(digest)].map(b=>b.toString(16).padStart(2,'0')).join('');
};
const validSecret=value=>typeof value==='string'&&value.length>=64&&value.length<=512&&!/\s/.test(value);

export function createIntegrationDelegationRefreshService({adapters,clock=()=>new Date().toISOString(),idFactory=()=>crypto.randomUUID()}={}){
  for(const n of ['verifyIntegrationClient','rotateIntegrationDelegation','rotateIntegrationDelegationV2']){
    if(typeof adapters?.[n]!=='function') throw new TypeError('missing delegation refresh adapter: '+n);
  }
  return async function handle({envelope,authContext}={}){
    const version=envelope?.integrationDelegationRefresh==='shine-foundation/integration-delegation-refresh-v2'&&envelope?.schemaVersion==='2.0.0'?2:
      envelope?.integrationDelegationRefresh==='shine-foundation/integration-delegation-refresh-v1'&&envelope?.schemaVersion==='1.0.0'?1:0;
    if(!version||!UUID.test(envelope?.requestId??'')||!CLIENT.test(envelope?.clientId??'')){
      return response(version||1,'invalid','invalid-delegation-refresh-request');
    }

    if(version===1&&!validSecret(envelope.refreshToken)){
      return response(1,'invalid','invalid-delegation-refresh-request');
    }
    if(version===2&&(
      !validSecret(authContext?.refreshToken)||
      !UUID.test(envelope.newSessionId??'')||
      !UUID.test(envelope.newRefreshId??'')||
      !HASH.test(envelope.newDelegationTokenHash??'')||
      !HASH.test(envelope.newRefreshTokenHash??'')
    )){
      return response(2,'invalid','invalid-delegation-refresh-request');
    }

    let client;
    try{client=await adapters.verifyIntegrationClient({authContext,claimedClientId:envelope.clientId})}
    catch{return response(version,'unavailable','foundation-dependency-unavailable')}
    if(!client?.clientId) return response(version,'denied','integration-client-unverified');
    if(client.clientId!==envelope.clientId) return response(version,'denied','integration-client-mismatch');

    const now=clock();
    const delegationExpiresAt=new Date(Date.parse(now)+24*60*60*1000).toISOString();
    const refreshExpiresAt=new Date(Date.parse(now)+90*24*60*60*1000).toISOString();

    if(version===2){
      try{
        const rotated=await adapters.rotateIntegrationDelegationV2({
          requestId:envelope.requestId,
          eventId:idFactory(),
          oldRefreshTokenHash:await sha256Hex(authContext.refreshToken),
          clientId:envelope.clientId,
          newRefreshId:envelope.newRefreshId,
          newRefreshTokenHash:envelope.newRefreshTokenHash,
          newSessionId:envelope.newSessionId,
          newDelegationHash:envelope.newDelegationTokenHash,
          occurredAt:now,
          delegationExpiresAt,
          refreshExpiresAt
        });
        if(!rotated?.rotated) return response(2,'denied',rotated?.reasonCode??'refresh-credential-invalid');
        return response(2,'refreshed',rotated.reasonCode??'refresh-credential-rotated-v2',{
          requestId:envelope.requestId,
          linkRequestId:rotated.requestId,
          sessionId:rotated.sessionId,
          expiresAt:rotated.delegationExpiresAt,
          refreshId:rotated.refreshId,
          refreshExpiresAt:rotated.refreshExpiresAt,
          refreshGeneration:rotated.refreshGeneration,
          replayed:Boolean(rotated.replayed)
        });
      }catch{
        return response(2,'unavailable','delegation-refresh-failed');
      }
    }

    const delegationToken=randomSecret()+randomSecret();
    const refreshToken=randomSecret()+randomSecret();
    try{
      const rotated=await adapters.rotateIntegrationDelegation({
        eventId:idFactory(),
        oldRefreshTokenHash:await sha256Hex(envelope.refreshToken),
        clientId:envelope.clientId,
        newRefreshId:idFactory(),
        newRefreshTokenHash:await sha256Hex(refreshToken),
        newSessionId:idFactory(),
        newDelegationHash:await sha256Hex(delegationToken),
        occurredAt:now,
        delegationExpiresAt,
        refreshExpiresAt
      });
      if(!rotated?.rotated) return response(1,'denied',rotated?.reasonCode??'refresh-credential-invalid');
      return response(1,'refreshed','delegation-refreshed',{
        requestId:rotated.requestId,
        sessionId:rotated.sessionId,
        delegationToken,
        expiresAt:rotated.delegationExpiresAt,
        refreshToken,
        refreshExpiresAt:rotated.refreshExpiresAt,
        refreshGeneration:rotated.refreshGeneration
      });
    }catch{
      return response(1,'unavailable','delegation-refresh-failed');
    }
  };
}
