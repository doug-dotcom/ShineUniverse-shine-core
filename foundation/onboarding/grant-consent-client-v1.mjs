const MAX_RESPONSE_BYTES=64*1024;
const boundedJson=async response=>{
  const declared=Number(response.headers.get('content-length'));
  if(Number.isFinite(declared)&&declared>MAX_RESPONSE_BYTES) throw new Error('grant-consent-response-too-large');
  const raw=await response.text();
  if(new TextEncoder().encode(raw).byteLength>MAX_RESPONSE_BYTES) throw new Error('grant-consent-response-too-large');
  return raw?JSON.parse(raw):{};
};

export function createGrantConsentClient({
  foundationUrl,appId,appToken,scope,purpose,resourceCategory,
  fetchImpl=fetch,timeoutMs=15000
}={}){
  const base=String(foundationUrl??'').replace(/\/$/,'');
  if(!/^https:\/\//.test(base)) throw new TypeError('foundationUrl must be https');
  if(!/^shine\.[a-z0-9][a-z0-9-]*$/.test(appId??'')) throw new TypeError('invalid appId');
  if(typeof appToken!=='string'||appToken.length<32) throw new TypeError('appToken is required');
  if(!/^[a-z0-9][a-z0-9._:-]*$/.test(scope??'')) throw new TypeError('invalid scope');
  if(!/^[a-z0-9][a-z0-9._:-]*$/.test(purpose??'')) throw new TypeError('invalid purpose');
  if(!/^[a-z0-9][a-z0-9._-]*$/.test(resourceCategory??'')) throw new TypeError('invalid resourceCategory');
  if(typeof fetchImpl!=='function') throw new TypeError('fetchImpl is required');

  return {
    async consent({userJwt,userToken,resourceId}={}){
      const modes=Number(Boolean(userJwt))+Number(Boolean(userToken));
      if(modes!==1) throw new TypeError('exactly one user credential is required');

      const envelope={
        grantConsent:'shine-foundation/grant-consent-v1',
        schemaVersion:'1.0.0',
        requestId:crypto.randomUUID(),
        appId,scope,purpose,resourceCategory,
        ...(resourceId?{resourceId}:{}),
        consent:true,
        requestedAt:new Date().toISOString()
      };
      const headers={
        'Content-Type':'application/json',
        'X-Shine-App-Token':appToken,
        ...(userJwt?{Authorization:'Bearer '+userJwt}:{}),
        ...(userToken?{'X-Shine-User-Token':userToken}:{})
      };

      try{
        const response=await fetchImpl(base+'/v1/grants/consent',{
          method:'POST',headers,body:JSON.stringify(envelope),signal:AbortSignal.timeout(timeoutMs)
        });
        const result=await boundedJson(response);
        if(response.ok&&(result.status==='granted'||result.status==='already-granted')){
          return {granted:true,status:result.status,reasonCode:result.reasonCode,httpStatus:response.status};
        }
        if(response.status===403||result.status==='denied'){
          return {granted:false,status:'denied',reasonCode:result.reasonCode??'grant-consent-denied',httpStatus:response.status};
        }
        return {granted:false,status:'unavailable',reasonCode:result.reasonCode??'grant-consent-unavailable',httpStatus:response.status};
      }catch{
        return {granted:false,status:'unavailable',reasonCode:'grant-consent-unavailable',httpStatus:null};
      }
    }
  };
}
