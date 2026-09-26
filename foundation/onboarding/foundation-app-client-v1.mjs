const MAX_RESPONSE_BYTES=64*1024;
const CREDENTIAL_KINDS=new Set(['bearer-jwt','opaque-header']);

const boundedJson=async(response,maxBytes=MAX_RESPONSE_BYTES)=>{
  const declared=Number(response.headers.get('content-length'));
  if(Number.isFinite(declared)&&declared>maxBytes) throw new Error('foundation-response-too-large');
  const raw=await response.text();
  if(new TextEncoder().encode(raw).byteLength>maxBytes) throw new Error('foundation-response-too-large');
  return raw?JSON.parse(raw):{};
};

const cleanBase=value=>{
  const url=String(value??'').replace(/\/$/,'');
  if(!/^https:\/\//.test(url)) throw new TypeError('foundationUrl must be https');
  return url;
};

export function createFoundationAppClient({
  foundationUrl,
  appId,
  appToken,
  userCredentialMode,
  fetchImpl=fetch,
  timeoutMs=15000
}={}){
  const base=cleanBase(foundationUrl);
  if(!/^shine\.[a-z0-9][a-z0-9-]*$/.test(appId??'')) throw new TypeError('invalid appId');
  if(typeof appToken!=='string'||appToken.length<32) throw new TypeError('appToken is required');
  if(!CREDENTIAL_KINDS.has(userCredentialMode)) throw new TypeError('invalid userCredentialMode');
  if(typeof fetchImpl!=='function') throw new TypeError('fetchImpl is required');

  return {
    async evaluate({userCredential,scope,purpose,resourceCategory,resourceId,context}={}){
      if(typeof userCredential!=='string'||!userCredential) throw new TypeError('userCredential is required');
      if(typeof scope!=='string'||!scope||typeof purpose!=='string'||!purpose) throw new TypeError('scope and purpose are required');
      if(!resourceCategory&&!resourceId) throw new TypeError('resourceCategory or resourceId is required');

      const envelope={
        gatewayRequest:'shine-foundation/gateway-request-v2',
        schemaVersion:'2.0.0',
        operation:'access.evaluate',
        traceId:crypto.randomUUID(),
        permission:{
          requestId:crypto.randomUUID(),
          appId,
          scope,
          purpose,
          ...(resourceId?{resourceId}:{}),
          ...(resourceCategory?{resourceCategory}:{}),
          requestedAt:new Date().toISOString(),
          ...(context===undefined?{}:{context})
        }
      };

      const headers={
        'Content-Type':'application/json',
        'X-Shine-App-Token':appToken,
        ...(userCredentialMode==='bearer-jwt'
          ? {Authorization:'Bearer '+userCredential}
          : {'X-Shine-User-Token':userCredential})
      };

      try{
        const response=await fetchImpl(base+'/v1/access/evaluate',{
          method:'POST',
          headers,
          body:JSON.stringify(envelope),
          signal:AbortSignal.timeout(timeoutMs)
        });
        const result=await boundedJson(response);
        if(response.ok&&result.status==='allowed'){
          return {connected:true,status:'allowed',reasonCode:result.reasonCode??'grant-match',httpStatus:response.status};
        }
        if(response.status===403||result.status==='denied'){
          return {connected:true,status:'denied',reasonCode:result.reasonCode??'denied',httpStatus:response.status};
        }
        return {connected:false,status:'unavailable',reasonCode:result.reasonCode??'foundation-unavailable',httpStatus:response.status};
      }catch{
        return {connected:false,status:'unavailable',reasonCode:'foundation-unavailable',httpStatus:null};
      }
    },

    async claimIdentity({userCredential,canonicalJwt}={}){
      if(userCredentialMode!=='opaque-header') throw new TypeError('identity claim requires opaque-header source identity');
      if(typeof userCredential!=='string'||userCredential.length<32) throw new TypeError('userCredential is required');
      if(typeof canonicalJwt!=='string'||!canonicalJwt) throw new TypeError('canonicalJwt is required');

      const envelope={
        identityClaimRequest:'shine-foundation/identity-claim-request-v1',
        schemaVersion:'1.0.0',
        operation:'identity.claim',
        claimId:crypto.randomUUID(),
        requestId:crypto.randomUUID(),
        appId,
        requestedAt:new Date().toISOString()
      };

      try{
        const response=await fetchImpl(base+'/v1/identity/claim',{
          method:'POST',
          headers:{
            'Content-Type':'application/json',
            'X-Shine-App-Token':appToken,
            'X-Shine-User-Token':userCredential,
            Authorization:'Bearer '+canonicalJwt
          },
          body:JSON.stringify(envelope),
          signal:AbortSignal.timeout(timeoutMs)
        });
        const result=await boundedJson(response);
        if(response.ok&&result.status==='linked'){
          return {
            connected:true,status:'linked',
            reasonCode:result.reasonCode??'identity-claim-linked',
            bindingCreated:Boolean(result.bindingCreated),
            httpStatus:response.status
          };
        }
        if(response.status===409||result.status==='conflict'){
          return {connected:true,status:'conflict',reasonCode:result.reasonCode??'identity-claim-conflict',httpStatus:response.status};
        }
        if(response.status===403||result.status==='denied'){
          return {connected:true,status:'denied',reasonCode:result.reasonCode??'identity-claim-rejected',httpStatus:response.status};
        }
        return {connected:false,status:'unavailable',reasonCode:result.reasonCode??'foundation-unavailable',httpStatus:response.status};
      }catch{
        return {connected:false,status:'unavailable',reasonCode:'foundation-unavailable',httpStatus:null};
      }
    }
  };
}
