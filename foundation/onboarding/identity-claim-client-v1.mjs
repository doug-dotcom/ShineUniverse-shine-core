const MAX_RESPONSE_BYTES=64*1024;

const boundedJson=async response=>{
  const declared=Number(response.headers.get('content-length'));
  if(Number.isFinite(declared)&&declared>MAX_RESPONSE_BYTES) throw new Error('claim-response-too-large');
  const raw=await response.text();
  if(new TextEncoder().encode(raw).byteLength>MAX_RESPONSE_BYTES) throw new Error('claim-response-too-large');
  return raw?JSON.parse(raw):{};
};

export function createIdentityClaimClient({
  foundationUrl,
  appId,
  appToken,
  sourceProviderId,
  targetProviderId,
  fetchImpl=fetch,
  timeoutMs=15000
}={}){
  const base=String(foundationUrl??'').replace(/\/$/,'');
  if(!/^https:\/\//.test(base)) throw new TypeError('foundationUrl must be https');
  if(!/^shine\.[a-z0-9][a-z0-9-]*$/.test(appId??'')) throw new TypeError('invalid appId');
  if(typeof appToken!=='string'||appToken.length<32) throw new TypeError('appToken is required');
  if(!/^[a-z0-9][a-z0-9._:-]*$/.test(sourceProviderId??'')) throw new TypeError('invalid sourceProviderId');
  if(!/^[a-z0-9][a-z0-9._:-]*$/.test(targetProviderId??'')) throw new TypeError('invalid targetProviderId');
  if(sourceProviderId===targetProviderId) throw new TypeError('claim providers must differ');
  if(typeof fetchImpl!=='function') throw new TypeError('fetchImpl is required');

  return {
    async claim({sourceUserToken,targetJwt}={}){
      if(typeof sourceUserToken!=='string'||!sourceUserToken) throw new TypeError('sourceUserToken is required');
      if(typeof targetJwt!=='string'||!targetJwt) throw new TypeError('targetJwt is required');

      const envelope={
        identityClaim:'shine-foundation/identity-claim-v1',
        schemaVersion:'1.0.0',
        requestId:crypto.randomUUID(),
        appId,
        sourceProviderId,
        targetProviderId,
        requestedAt:new Date().toISOString()
      };

      try{
        const response=await fetchImpl(base+'/v1/identity/claim',{
          method:'POST',
          headers:{
            'Content-Type':'application/json',
            'X-Shine-App-Token':appToken,
            'X-Shine-User-Token':sourceUserToken,
            Authorization:'Bearer '+targetJwt
          },
          body:JSON.stringify(envelope),
          signal:AbortSignal.timeout(timeoutMs)
        });
        const result=await boundedJson(response);

        if(response.ok&&(result.status==='linked'||result.status==='already-linked')){
          return {
            linked:true,
            status:result.status,
            reasonCode:result.reasonCode,
            httpStatus:response.status
          };
        }
        if(response.status===403||result.status==='denied'){
          return {
            linked:false,
            status:'denied',
            reasonCode:result.reasonCode??'identity-claim-denied',
            httpStatus:response.status
          };
        }
        return {
          linked:false,
          status:'unavailable',
          reasonCode:result.reasonCode??'identity-claim-unavailable',
          httpStatus:response.status
        };
      }catch{
        return {
          linked:false,
          status:'unavailable',
          reasonCode:'identity-claim-unavailable',
          httpStatus:null
        };
      }
    }
  };
}
