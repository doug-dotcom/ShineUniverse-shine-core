const JSON_HEADERS={
  'content-type':'application/json; charset=utf-8',
  'cache-control':'no-store'
};

const json=(status,body)=>new Response(JSON.stringify(body),{status,headers:JSON_HEADERS});
const healthPath=p=>p==='/health'||p.endsWith('/foundation-gateway/health');
const evaluatePath=p=>p==='/v1/access/evaluate'||p.endsWith('/foundation-gateway/v1/access/evaluate');
const identityClaimPath=p=>p==='/v1/identity/claim'||p.endsWith('/foundation-gateway/v1/identity/claim');
const grantConsentPath=p=>p==='/v1/grants/consent'||p.endsWith('/foundation-gateway/v1/grants/consent');
const grantRevocationPath=p=>p==='/v1/grants/revoke'||p.endsWith('/foundation-gateway/v1/grants/revoke');
const revocationFeedPath=p=>p==='/v1/revocations'||p.endsWith('/foundation-gateway/v1/revocations');
const revocationAckPath=p=>p==='/v1/revocations/ack'||p.endsWith('/foundation-gateway/v1/revocations/ack');
const revocationStatusPath=p=>p==='/v1/revocations/status'||p.endsWith('/foundation-gateway/v1/revocations/status');
const appStatusPath=p=>p==='/v1/status'||p.endsWith('/foundation-gateway/v1/status');
const capabilityDiscoveryPath=p=>p==='/v1/integration/capabilities'||p.endsWith('/foundation-gateway/v1/integration/capabilities');
const defenceStatusMatch=p=>p.match(/(?:^|\/foundation-gateway)\/v1\/defence\/status\/([a-z0-9][a-z0-9-]{0,63})$/);
const SHA=/^[a-f0-9]{40}$/;

/** @param {{gateway:any, authenticate:any, authenticateApp?:any, defenceStatus?:any, identityClaim?:any, authenticateIdentityClaim?:any, grantConsent?:any, grantRevocation?:any, revocationFeed?:any, revocationAck?:any, revocationHealth?:any, appOperationalStatus?:any, capabilityDiscovery?:any, maxBodyBytes?:number}} [options] */
export function createFoundationHttpHandler({
  gateway,
  authenticate,
  authenticateApp,
  defenceStatus,
  identityClaim,
  authenticateIdentityClaim,
  grantConsent,
  grantRevocation,
  revocationFeed,
  revocationAck,
  revocationHealth,
  appOperationalStatus,
  capabilityDiscovery,
  maxBodyBytes=16*1024
}={}){
  if(typeof gateway!=='function') throw new TypeError('gateway must be a function');
  if(typeof authenticate!=='function') throw new TypeError('authenticate must be a function');
  if(authenticateApp!==undefined&&typeof authenticateApp!=='function') throw new TypeError('authenticateApp must be a function');
  if(defenceStatus!==undefined&&typeof defenceStatus!=='function') throw new TypeError('defenceStatus must be a function');
  if(identityClaim!==undefined&&typeof identityClaim!=='function') throw new TypeError('identityClaim must be a function');
  if(authenticateIdentityClaim!==undefined&&typeof authenticateIdentityClaim!=='function') throw new TypeError('authenticateIdentityClaim must be a function');
  if(grantConsent!==undefined&&typeof grantConsent!=='function') throw new TypeError('grantConsent must be a function');
  if(grantRevocation!==undefined&&typeof grantRevocation!=='function') throw new TypeError('grantRevocation must be a function');
  if(revocationFeed!==undefined&&typeof revocationFeed!=='function') throw new TypeError('revocationFeed must be a function');
  if(revocationAck!==undefined&&typeof revocationAck!=='function') throw new TypeError('revocationAck must be a function');
  if(revocationHealth!==undefined&&typeof revocationHealth!=='function') throw new TypeError('revocationHealth must be a function');
  if(appOperationalStatus!==undefined&&typeof appOperationalStatus!=='function') throw new TypeError('appOperationalStatus must be a function');
  if(capabilityDiscovery!==undefined&&typeof capabilityDiscovery!=='function') throw new TypeError('capabilityDiscovery must be a function');

  return async function handle(request){
    const url=new URL(request.url);
    if(request.method==='GET'&&healthPath(url.pathname)){
      return json(200,{service:'shine-foundation-gateway',status:'ok',schemaVersion:'1.0.0'});
    }

    if(request.method==='GET'&&capabilityDiscoveryPath(url.pathname)){
      if(typeof capabilityDiscovery!=='function') return json(404,{error:'not-found'});
      const appId=url.searchParams.get('appId')||null;
      const result=await capabilityDiscovery({appId});
      const status={ok:200,invalid:400,unavailable:503}[result.status]??500;
      return json(status,result);
    }

    const defenceMatch=defenceStatusMatch(url.pathname);
    if(defenceMatch){
      if(request.method!=='GET')return json(405,{error:'method-not-allowed'});
      if(!defenceStatus)return json(404,{error:'not-found'});
      const releaseSha=url.searchParams.get('releaseSha')??'';
      const profileBlobSha=url.searchParams.get('profileBlobSha')??'';
      if(!SHA.test(releaseSha)||!SHA.test(profileBlobSha))return json(400,{error:'invalid-defence-status-query'});
      try{
        return json(200,defenceStatus({appId:defenceMatch[1],releaseSha,profileBlobSha}));
      }catch(error){
        if(error instanceof TypeError)return json(400,{error:'invalid-defence-status-query'});
        return json(503,{error:'defence-status-unavailable'});
      }
    }

    if(request.method==='GET'&&appStatusPath(url.pathname)){
      if(typeof appOperationalStatus!=='function'||typeof authenticateApp!=='function'){
        return json(404,{error:'not-found'});
      }
      const appId=url.searchParams.get('appId')??'';
      let authContext;
      try{ authContext=await authenticateApp(request); }catch{ return json(401,{error:'unauthenticated'}); }
      const result=await appOperationalStatus({appId,authContext});
      const status={ok:200,denied:403,invalid:400,unavailable:503}[result.status]??500;
      return json(status,result);
    }

    if(request.method==='GET'&&revocationStatusPath(url.pathname)){
      if(typeof revocationHealth!=='function'||typeof authenticateApp!=='function'){
        return json(404,{error:'not-found'});
      }
      const appId=url.searchParams.get('appId')??'';
      let authContext;
      try{ authContext=await authenticateApp(request); }catch{ return json(401,{error:'unauthenticated'}); }
      const result=await revocationHealth({appId,authContext});
      const status={ok:200,denied:403,invalid:400,unavailable:503}[result.status]??500;
      return json(status,result);
    }

    if(request.method==='GET'&&revocationFeedPath(url.pathname)){
      if(typeof revocationFeed!=='function'||typeof authenticateApp!=='function'){
        return json(404,{error:'not-found'});
      }
      const appId=url.searchParams.get('appId')??'';
      const afterRaw=url.searchParams.get('after')??'0';
      const limitRaw=url.searchParams.get('limit')??'100';
      if(!/^\d+$/.test(afterRaw)||!/^\d+$/.test(limitRaw)){
        return json(400,{error:'invalid-revocation-feed-query'});
      }
      const afterSequence=Number(afterRaw);
      const limit=Number(limitRaw);
      let authContext;
      try{ authContext=await authenticateApp(request); }catch{ return json(401,{error:'unauthenticated'}); }
      const result=await revocationFeed({appId,afterSequence,limit,authContext});
      const status={ok:200,denied:403,invalid:400,unavailable:503}[result.status]??500;
      return json(status,result);
    }

    const isClaim=identityClaimPath(url.pathname);
    const isGrantConsent=grantConsentPath(url.pathname);
    const isGrantRevocation=grantRevocationPath(url.pathname);
    const isRevocationAck=revocationAckPath(url.pathname);
    const isEvaluate=evaluatePath(url.pathname);
    if(!isClaim&&!isGrantConsent&&!isGrantRevocation&&!isRevocationAck&&!isEvaluate) return json(404,{error:'not-found'});
    if(request.method!=='POST') return json(405,{error:'method-not-allowed'});

    const contentType=request.headers.get('content-type')??'';
    if(!contentType.toLowerCase().startsWith('application/json')){
      return json(415,{error:'unsupported-media-type'});
    }

    const declared=Number(request.headers.get('content-length'));
    if(Number.isFinite(declared)&&declared>maxBodyBytes) return json(413,{error:'request-too-large'});

    let raw;
    try{ raw=await request.text(); }catch{ return json(400,{error:'invalid-body'}); }
    if(new TextEncoder().encode(raw).byteLength>maxBodyBytes) return json(413,{error:'request-too-large'});

    let envelope;
    try{ envelope=JSON.parse(raw); }catch{ return json(400,{error:'invalid-json'}); }

    if(isRevocationAck){
      if(typeof revocationAck!=='function'||typeof authenticateApp!=='function'){
        return json(404,{error:'not-found'});
      }
      let authContext;
      try{ authContext=await authenticateApp(request); }catch{ return json(401,{error:'unauthenticated'}); }
      const result=await revocationAck({envelope,authContext});
      const status={acknowledged:200,'already-acknowledged':200,denied:403,invalid:400,unavailable:503}[result.status]??500;
      return json(status,result);
    }

    if(isClaim){
      if(typeof identityClaim!=='function'||typeof authenticateIdentityClaim!=='function'){
        return json(404,{error:'not-found'});
      }

      let authContext;
      try{ authContext=await authenticateIdentityClaim(request); }catch{ return json(401,{error:'unauthenticated'}); }

      const result=await identityClaim({envelope,authContext});
      const status={
        linked:200,
        'already-linked':200,
        denied:403,
        invalid:400,
        unavailable:503
      }[result.status]??500;
      return json(status,result);
    }

    let authContext;
    try{ authContext=await authenticate(request); }catch{ return json(401,{error:'unauthenticated'}); }

    if(isGrantConsent){
      if(typeof grantConsent!=='function') return json(404,{error:'not-found'});
      const result=await grantConsent({envelope,authContext});
      const status={granted:200,'already-granted':200,denied:403,invalid:400,unavailable:503}[result.status]??500;
      return json(status,result);
    }

    if(isGrantRevocation){
      if(typeof grantRevocation!=='function') return json(404,{error:'not-found'});
      const result=await grantRevocation({envelope,authContext});
      const status={revoked:200,'already-revoked':200,denied:403,invalid:400,unavailable:503}[result.status]??500;
      return json(status,result);
    }

    const result=await gateway({envelope,authContext});
    const status={allowed:200,denied:403,invalid:400,unavailable:503}[result.status]??500;
    return json(status,result);
  };
}
