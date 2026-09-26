import {createFoundationAppClient} from './foundation-app-client-v1.mjs';

export function createIdentityClaimClient({
  foundationUrl,
  appId,
  appToken,
  fetchImpl=fetch,
  timeoutMs=15000
}={}){
  const foundation=createFoundationAppClient({
    foundationUrl,
    appId,
    appToken,
    userCredentialMode:'opaque-header',
    fetchImpl,
    timeoutMs
  });

  return {
    async claim({sourceUserToken,targetJwt}={}){
      const result=await foundation.claimIdentity({
        userCredential:sourceUserToken,
        canonicalJwt:targetJwt
      });
      return {
        linked:result.status==='linked',
        status:result.status,
        reasonCode:result.reasonCode,
        bindingCreated:Boolean(result.bindingCreated),
        httpStatus:result.httpStatus
      };
    }
  };
}
