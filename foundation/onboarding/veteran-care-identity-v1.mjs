// Server-only VC consumer adapter. Configuration must come from Foundation's registry.
// This adapter verifies identity only: it never links accounts or grants Vault access.
const UUID=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const DEDICATED_ISSUER='https://akyzwuvfvugzyauaptsk.supabase.co/auth/v1';
const deny=reasonCode=>({status:'denied',reasonCode});
const unavailable=()=>({status:'unavailable',reasonCode:'vc-identity-authority-unavailable'});

export function createVeteranCareIdentityVerifier({appId,providerId,verifyAppCaller,verifyIdentity}={}){
  if(typeof appId!=='string'||!/^shine\.[a-z0-9][a-z0-9-]*$/.test(appId)) throw new TypeError('registered VC appId is required');
  if(typeof providerId!=='string'||!/^supabase:[a-z0-9][a-z0-9._:-]*$/.test(providerId)) throw new TypeError('registered VC providerId is required');
  if(typeof verifyAppCaller!=='function'||typeof verifyIdentity!=='function') throw new TypeError('Foundation authority adapters are required');
  return async function verifyVeteranCareIdentity({authContext}={}){
    const jwt=authContext?.jwt;
    if(typeof jwt!=='string'||jwt.length>16384||jwt.split('.').length!==3||authContext?.userToken!=null)
      return deny('vc-user-proof-invalid');
    // Untrusted issuer is used only to reject wrong providers before external calls.
    // Actual authentication remains the existing server-side Foundation verifier.
    try{
      const payload=jwt.split('.')[1].replace(/-/g,'+').replace(/_/g,'/');
      const claims=JSON.parse(atob(payload+'='.repeat((4-payload.length%4)%4)));
      if(claims?.iss!==DEDICATED_ISSUER) return deny('vc-identity-provider-mismatch');
    }catch{return deny('vc-user-proof-invalid');}
    const credentials={appToken:authContext?.appToken,jwt};
    let app,identity;
    try{
      app=await verifyAppCaller({authContext:credentials,claimedAppId:appId});
      if(app?.appId!==appId) return deny('vc-app-caller-unverified');
      identity=await verifyIdentity({authContext:credentials,claimedAppId:appId});
    }catch{return unavailable();}
    if(!identity) return deny('vc-user-identity-unverified');
    if(identity.providerId!==providerId) return deny('vc-identity-provider-mismatch');
    if(typeof identity.shineId!=='string'||!UUID.test(identity.shineId)||
       typeof identity.authSubject!=='string'||!UUID.test(identity.authSubject))
      return deny('vc-user-identity-unverified');
    return {status:'verified',identity:{shineId:identity.shineId,authSubject:identity.authSubject,providerId}};
  };
}
