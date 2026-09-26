export function createFoundationRuntimeDefenceGateV1({maxContextBytes=4096}={}){
  return async function evaluate({envelope,verifiedIdentity,appManifest,resource}={}){
    if(!verifiedIdentity?.shineId||!appManifest?.appId){
      return {decision:'deny',evidenceRef:'shine-defence/foundation-runtime-v1:missing-trust-context'};
    }
    const context=envelope?.permission?.context;
    if(context!==undefined){
      const size=new TextEncoder().encode(JSON.stringify(context)).byteLength;
      if(size>maxContextBytes){
        return {decision:'deny',evidenceRef:'shine-defence/foundation-runtime-v1:context-too-large'};
      }
    }
    if(resource?.sensitivity==='restricted'&&!envelope?.permission?.resourceId){
      return {decision:'deny',evidenceRef:'shine-defence/foundation-runtime-v1:restricted-requires-exact-resource'};
    }
    return {decision:'allow',evidenceRef:'shine-defence/foundation-runtime-v1:pass'};
  };
}
