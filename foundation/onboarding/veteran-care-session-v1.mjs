import {createVeteranCareAudienceIdentityVerifier} from './veteran-care-audience-v1.mjs';
const UUID=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const denied=()=>({status:'denied'});
const unavailable=()=>({status:'unavailable'});
const validTime=seconds=>Number.isSafeInteger(seconds)&&seconds>0&&Number.isSafeInteger(seconds*1000);
const validClock=ms=>Number.isSafeInteger(ms)&&ms>=0;

// getSessionState is a server-owned, uncached dedicated-project lookup. It must
// return effective session policy (including idle/time-box limits), not merely
// token validity or a browser session. Missing/revoked rows are never active.
export function createVeteranCareSessionAuthority({getSessionState,clock=()=>Date.now()}={}){
  if(typeof getSessionState!=='function'||typeof clock!=='function')
    throw new TypeError('current session authority and server clock are required');
  return async function verify({sessionProof,identity,appId,issuer}={}){
    try{
      const {sessionId,expiresAt,notBefore}=sessionProof??{};
      const startedAt=clock();
      if(!validClock(startedAt)) return unavailable();
      if(typeof sessionId!=='string'||!UUID.test(sessionId)||!validTime(expiresAt)||
        expiresAt*1000<=startedAt||
        (notBefore!==undefined&&(!validTime(notBefore)||notBefore*1000>startedAt))) return denied();
      const state=await getSessionState(Object.freeze({
        sessionId,authSubject:identity.authSubject,providerId:identity.providerId,appId,issuer
      }));
      const completedAt=clock();
      if(!validClock(completedAt)||completedAt<startedAt) return unavailable();
      if(!state||state.status!=='active'||state.sessionId!==sessionId||
        state.authSubject!==identity.authSubject||state.issuer!==issuer||
        (state.expiresAt!==null&&!validTime(state.expiresAt))) return denied();
      // Recheck after the asynchronous authority call. null explicitly means
      // no session time-box; undefined or malformed expiry is not accepted.
      if(expiresAt*1000<=completedAt||
        (state.expiresAt!==null&&state.expiresAt*1000<=completedAt)) return denied();
      return {status:'current'};
    }catch{return unavailable();}
  };
}

export function createVeteranCareSessionIdentityVerifier({getSessionState,clock,...options}={}){
  return createVeteranCareAudienceIdentityVerifier({
    ...options,verifyCurrentSession:createVeteranCareSessionAuthority({getSessionState,clock})
  });
}
