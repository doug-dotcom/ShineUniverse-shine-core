const CLIENT=/^[a-z0-9][a-z0-9._:-]*$/;

const response=(status,body={})=>({
  integrationClientStatusResponse:'shine-foundation/integration-client-status-response-v1',
  schemaVersion:'1.0.0',
  integrationProtocol:'shine-foundation/open-integration-v1',
  status,
  ...body
});

export function createIntegrationClientStatusService({adapters}={}){
  if(typeof adapters?.verifyIntegrationClient!=='function'){
    throw new TypeError('missing integration client adapter: verifyIntegrationClient');
  }

  return async function handleIntegrationClientStatus({clientId,authContext}={}){
    if(!CLIENT.test(clientId??'')){
      return response('invalid',{reasonCode:'invalid-client-id'});
    }

    let verified;
    try{
      verified=await adapters.verifyIntegrationClient({authContext,claimedClientId:clientId});
    }catch{
      return response('unavailable',{reasonCode:'foundation-dependency-unavailable'});
    }

    if(!verified?.clientId){
      return response('denied',{reasonCode:'integration-client-unverified'});
    }
    if(verified.clientId!==clientId){
      return response('denied',{reasonCode:'integration-client-mismatch'});
    }

    return response('ok',{
      clientId:verified.clientId,
      clientKind:verified.clientKind,
      authenticated:true,
      supportedOperations:['capabilities.discover']
    });
  };
}
