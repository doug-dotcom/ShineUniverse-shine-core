const APP=/^shine\.[a-z0-9][a-z0-9-]*$/;

const response=(status,body={})=>({
  appOperationalStatusResponse:'shine-foundation/app-operational-status-response-v1',
  schemaVersion:'1.0.0',
  status,
  ...body
});

const requireFunction=(adapters,name)=>{
  if(typeof adapters?.[name]!=='function') throw new TypeError('missing app operational status adapter: '+name);
};

export function createAppOperationalStatusService({adapters}={}){
  for(const name of ['verifyAppCaller','getAppOperationalStatus']) requireFunction(adapters,name);

  return async function handleAppOperationalStatus({appId,authContext}={}){
    if(!APP.test(appId??'')){
      return response('invalid',{reasonCode:'invalid-app-operational-status-request'});
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

    let operationalStatus;
    try{
      operationalStatus=await adapters.getAppOperationalStatus({appId});
    }catch{
      return response('unavailable',{reasonCode:'app-operational-status-unavailable'});
    }
    if(!operationalStatus){
      return response('unavailable',{reasonCode:'app-operational-status-unavailable'});
    }

    return response('ok',{appId,operationalStatus});
  };
}
