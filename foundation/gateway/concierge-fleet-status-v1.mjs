const CLIENT=/^[a-z0-9][a-z0-9._:-]*$/;
const PURPOSE=/^[a-z0-9][a-z0-9._:-]*$/;

const response=(status,reasonCode,extra={})=>({
  conciergeFleetStatusResponse:'shine-foundation/concierge-fleet-status-response-v1',
  schemaVersion:'1.0.0',
  status,
  reasonCode,
  ...extra
});

async function verifyPair(adapters,authContext,clientId){
  const client=await adapters.verifyIntegrationClient({authContext,claimedClientId:clientId});
  if(!client?.clientId) return {error:'integration-client-unverified'};
  if(client.clientId!==clientId) return {error:'integration-client-mismatch'};

  if(authContext?.delegationToken){
    const delegated=await adapters.verifyIntegrationDelegation({authContext,claimedClientId:clientId});
    if(!delegated?.shineId) return {error:'delegation-unverified'};
    if(delegated.clientId!==clientId) return {error:'delegation-client-mismatch'};
    return {client,identity:{shineId:delegated.shineId}};
  }

  const identity=await adapters.verifyIntegrationIdentity({authContext});
  if(!identity?.shineId) return {error:'identity-unverified'};
  return {client,identity};
}

export function createConciergeFleetStatusService({adapters}={}){
  for(const name of ['verifyIntegrationClient','verifyIntegrationIdentity','verifyIntegrationDelegation','getConciergeFleetStatus']){
    if(typeof adapters?.[name]!=='function') throw new TypeError('missing concierge fleet adapter: '+name);
  }

  return async function handle({clientId,purpose,authContext}={}){
    if(!CLIENT.test(clientId??'')||!PURPOSE.test(purpose??'')){
      return response('invalid','invalid-concierge-fleet-query');
    }

    let verified;
    try{verified=await verifyPair(adapters,authContext,clientId)}
    catch{return response('unavailable','foundation-dependency-unavailable')}
    if(verified.error) return response('denied',verified.error);

    try{
      const fleet=await adapters.getConciergeFleetStatus({
        ownerShineId:verified.identity.shineId,
        clientId,
        purpose
      });
      if(!fleet||typeof fleet!=='object'||Array.isArray(fleet)){
        return response('unavailable','concierge-fleet-unavailable');
      }
      return response('ok','concierge-fleet-listed',{clientId,purpose,fleet});
    }catch{
      return response('unavailable','concierge-fleet-unavailable');
    }
  };
}
