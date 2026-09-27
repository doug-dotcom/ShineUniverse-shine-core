const APP=/^shine\.[a-z0-9][a-z0-9-]*$/;

const response=(status,body={})=>({
  capabilityDiscoveryResponse:'shine-foundation/capability-discovery-response-v1',
  schemaVersion:'1.0.0',
  integrationProtocol:'shine-foundation/open-integration-v1',
  status,
  companionAgnostic:true,
  executionRequiresAuthorization:true,
  ...body
});

export function createCapabilityDiscoveryService({adapters}={}){
  if(typeof adapters?.listDiscoverableCapabilities!=='function'){
    throw new TypeError('missing capability discovery adapter: listDiscoverableCapabilities');
  }

  return async function handleCapabilityDiscovery({appId=null}={}){
    if(appId!==null&&!APP.test(appId)){
      return response('invalid',{reasonCode:'invalid-app-id'});
    }

    try{
      const capabilities=await adapters.listDiscoverableCapabilities({appId});
      return response('ok',{
        appId,
        capabilities:Array.isArray(capabilities)?capabilities:[]
      });
    }catch{
      return response('unavailable',{reasonCode:'capability-catalogue-unavailable'});
    }
  };
}
