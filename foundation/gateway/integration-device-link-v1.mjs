const UUID=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const CLIENT=/^[a-z0-9][a-z0-9._:-]*$/;
const TOKEN=/^[a-z0-9][a-z0-9._:-]*$/;
const CODE_CHARS='ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

const response=(kind,envelope,status,reasonCode,extra={})=>({
  integrationResponse:kind,
  schemaVersion:'1.0.0',
  requestId:envelope?.requestId??null,
  status,
  reasonCode,
  ...extra
});

const requireAdapter=(adapters,name)=>{
  if(typeof adapters?.[name]!=='function') throw new TypeError('missing device-link adapter: '+name);
};

const randomCode=(length=8)=>{
  const bytes=new Uint8Array(length);
  crypto.getRandomValues(bytes);
  return Array.from(bytes,b=>CODE_CHARS[b%CODE_CHARS.length]).join('');
};

const randomSecret=()=>{
  const bytes=new Uint8Array(32);
  crypto.getRandomValues(bytes);
  return Array.from(bytes,b=>b.toString(16).padStart(2,'0')).join('');
};

const sha256Hex=async value=>{
  const digest=await crypto.subtle.digest('SHA-256',new TextEncoder().encode(value));
  return [...new Uint8Array(digest)].map(b=>b.toString(16).padStart(2,'0')).join('');
};

export function createIntegrationLinkRequestService({adapters,clock=()=>new Date().toISOString()}={}){
  for(const n of ['verifyIntegrationClient','createIntegrationLinkRequest']) requireAdapter(adapters,n);

  return async function handle({envelope,authContext}={}){
    const kind='shine-foundation/integration-link-request-response-v1';
    const caps=envelope?.capabilityIds;
    if(!envelope||envelope.integrationLinkRequest!=='shine-foundation/integration-link-request-v1'||
       envelope.schemaVersion!=='1.0.0'||!UUID.test(envelope.requestId??'')||
       !CLIENT.test(envelope.clientId??'')||!TOKEN.test(envelope.purpose??'')||
       !Array.isArray(caps)||caps.length<1||caps.length>20||
       caps.some(c=>!TOKEN.test(c??''))||new Set(caps).size!==caps.length){
      return response(kind,envelope,'invalid','invalid-integration-link-request');
    }

    let client;
    try{client=await adapters.verifyIntegrationClient({authContext,claimedClientId:envelope.clientId})}
    catch{return response(kind,envelope,'unavailable','foundation-dependency-unavailable')}
    if(!client?.clientId) return response(kind,envelope,'denied','integration-client-unverified');
    if(client.clientId!==envelope.clientId) return response(kind,envelope,'denied','integration-client-mismatch');

    const userCode=randomCode();
    const exchangeSecret=randomSecret();
    const requestedAt=clock();
    const expiresAt=new Date(Date.parse(requestedAt)+10*60*1000).toISOString();

    try{
      const created=await adapters.createIntegrationLinkRequest({
        requestId:envelope.requestId,
        clientId:envelope.clientId,
        purpose:envelope.purpose,
        requestedCapabilities:caps,
        userCodeHash:await sha256Hex(userCode),
        exchangeSecretHash:await sha256Hex(exchangeSecret),
        requestedAt,
        expiresAt
      });
      if(!created) return response(kind,envelope,'unavailable','integration-link-request-write-failed');
      return response(kind,envelope,'created','integration-link-request-created',{
        clientId:envelope.clientId,
        userCode,
        exchangeSecret,
        expiresAt,
        requestedCapabilities:caps,
        purpose:envelope.purpose
      });
    }catch(error){
      const message=String(error?.message??'');
      if(message.includes('replay-conflict')) return response(kind,envelope,'invalid','integration-link-request-replay-conflict');
      return response(kind,envelope,'unavailable','integration-link-request-write-failed');
    }
  };
}

export function createIntegrationLinkApprovalService({adapters,clock=()=>new Date().toISOString(),idFactory=()=>crypto.randomUUID()}={}){
  for(const n of ['verifyIntegrationIdentity','approveIntegrationLinkRequest']) requireAdapter(adapters,n);

  return async function handle({envelope,authContext}={}){
    const kind='shine-foundation/integration-link-approval-response-v1';
    const caps=envelope?.approvedCapabilityIds;
    const userCode=String(envelope?.userCode??'').trim().toUpperCase();
    if(!envelope||envelope.integrationLinkApproval!=='shine-foundation/integration-link-approval-v1'||
       envelope.schemaVersion!=='1.0.0'||!UUID.test(envelope.requestId??'')||
       envelope.consent!==true||!/^[A-Z2-9]{8}$/.test(userCode)||
       !Array.isArray(caps)||caps.length<1||caps.length>20||
       caps.some(c=>!TOKEN.test(c??''))||new Set(caps).size!==caps.length){
      return response(kind,envelope,'invalid','invalid-integration-link-approval');
    }

    let identity;
    try{identity=await adapters.verifyIntegrationIdentity({authContext})}
    catch{return response(kind,envelope,'unavailable','foundation-dependency-unavailable')}
    if(!identity?.shineId) return response(kind,envelope,'denied','identity-unverified');

    try{
      const status=await adapters.approveIntegrationLinkRequest({
        eventId:idFactory(),
        linkId:idFactory(),
        requestId:envelope.requestId,
        ownerShineId:identity.shineId,
        userCodeHash:await sha256Hex(userCode),
        approvedCapabilities:caps,
        occurredAt:clock()
      });
      if(!status) return response(kind,envelope,'unavailable','integration-link-approval-write-failed');
      return response(kind,envelope,
        status.status==='approved'||status.status==='exchanged'?'approved':'already-approved',
        'integration-link-approved',
        {linkStatus:status}
      );
    }catch(error){
      const message=String(error?.message??'');
      if(message.includes('user-code-mismatch')) return response(kind,envelope,'denied','integration-link-user-code-mismatch');
      if(message.includes('expired')) return response(kind,envelope,'denied','integration-link-request-expired');
      if(message.includes('not-found')) return response(kind,envelope,'invalid','integration-link-request-not-found');
      return response(kind,envelope,'unavailable','integration-link-approval-write-failed');
    }
  };
}

export function createIntegrationLinkStatusService({adapters}={}){
  for(const n of ['verifyIntegrationClient','getIntegrationLinkRequestStatus']) requireAdapter(adapters,n);

  return async function handle({requestId,clientId,authContext}={}){
    const kind='shine-foundation/integration-link-status-response-v1';
    const envelope={requestId};
    if(!UUID.test(requestId??'')||!CLIENT.test(clientId??'')){
      return response(kind,envelope,'invalid','invalid-integration-link-status-request');
    }

    let client;
    try{client=await adapters.verifyIntegrationClient({authContext,claimedClientId:clientId})}
    catch{return response(kind,envelope,'unavailable','foundation-dependency-unavailable')}
    if(!client?.clientId) return response(kind,envelope,'denied','integration-client-unverified');
    if(client.clientId!==clientId) return response(kind,envelope,'denied','integration-client-mismatch');

    try{
      const linkStatus=await adapters.getIntegrationLinkRequestStatus({requestId,clientId});
      if(!linkStatus) return response(kind,envelope,'unavailable','integration-link-status-unavailable');
      return response(kind,envelope,'ok','integration-link-status-read',{linkStatus});
    }catch(error){
      const message=String(error?.message??'');
      if(message.includes('not-found')) return response(kind,envelope,'invalid','integration-link-request-not-found');
      if(message.includes('client-mismatch')) return response(kind,envelope,'denied','integration-link-request-client-mismatch');
      return response(kind,envelope,'unavailable','integration-link-status-unavailable');
    }
  };
}

export function createIntegrationLinkExchangeService({adapters,clock=()=>new Date().toISOString(),idFactory=()=>crypto.randomUUID()}={}){
  for(const n of ['verifyIntegrationClient','exchangeIntegrationLinkRequest']) requireAdapter(adapters,n);

  return async function handle({envelope,authContext}={}){
    const kind='shine-foundation/integration-link-exchange-response-v1';
    if(!envelope||envelope.integrationLinkExchange!=='shine-foundation/integration-link-exchange-v1'||
       envelope.schemaVersion!=='1.0.0'||!UUID.test(envelope.requestId??'')||
       !CLIENT.test(envelope.clientId??'')||
       typeof envelope.exchangeSecret!=='string'||envelope.exchangeSecret.length<32){
      return response(kind,envelope,'invalid','invalid-integration-link-exchange');
    }

    let client;
    try{client=await adapters.verifyIntegrationClient({authContext,claimedClientId:envelope.clientId})}
    catch{return response(kind,envelope,'unavailable','foundation-dependency-unavailable')}
    if(!client?.clientId) return response(kind,envelope,'denied','integration-client-unverified');
    if(client.clientId!==envelope.clientId) return response(kind,envelope,'denied','integration-client-mismatch');

    const delegationToken=randomSecret()+randomSecret();
    const refreshToken=randomSecret()+randomSecret();
    const now=clock();
    const sessionExpiresAt=new Date(Date.parse(now)+24*60*60*1000).toISOString();
    const refreshExpiresAt=new Date(Date.parse(now)+90*24*60*60*1000).toISOString();

    try{
      const session=await adapters.exchangeIntegrationLinkRequest({
        eventId:idFactory(),
        sessionId:idFactory(),
        refreshId:idFactory(),
        requestId:envelope.requestId,
        clientId:envelope.clientId,
        exchangeSecretHash:await sha256Hex(envelope.exchangeSecret),
        delegationTokenHash:await sha256Hex(delegationToken),
        refreshTokenHash:await sha256Hex(refreshToken),
        sessionExpiresAt,
        refreshExpiresAt,
        occurredAt:now
      });
      if(!session) return response(kind,envelope,'unavailable','integration-link-exchange-failed');
      return response(kind,envelope,'exchanged','integration-link-exchanged',{
        sessionId:session.sessionId,
        delegationToken,
        expiresAt:session.expiresAt,
        refreshToken,
        refreshExpiresAt:session.refreshExpiresAt
      });
    }catch(error){
      const message=String(error?.message??'');
      if(message.includes('not-approved')) return response(kind,envelope,'denied','integration-link-request-not-approved');
      if(message.includes('already-exchanged')) return response(kind,envelope,'denied','integration-link-request-already-exchanged');
      if(message.includes('exchange-secret-mismatch')) return response(kind,envelope,'denied','integration-link-exchange-secret-mismatch');
      if(message.includes('expired')) return response(kind,envelope,'denied','integration-link-request-expired');
      return response(kind,envelope,'unavailable','integration-link-exchange-failed');
    }
  };
}


export function createIntegrationLinkPreviewService({adapters}={}){
  for(const n of ['verifyIntegrationIdentity','resolveIntegrationLinkApproval']) requireAdapter(adapters,n);

  return async function handle({userCode,authContext}={}){
    const kind='shine-foundation/integration-link-preview-response-v1';
    const envelope={requestId:null};
    const normalized=String(userCode??'').trim().toUpperCase();

    if(!/^[A-Z2-9]{8}$/.test(normalized)){
      return response(kind,envelope,'invalid','invalid-integration-link-user-code');
    }

    let identity;
    try{identity=await adapters.verifyIntegrationIdentity({authContext})}
    catch{return response(kind,envelope,'unavailable','foundation-dependency-unavailable')}
    if(!identity?.shineId) return response(kind,envelope,'denied','identity-unverified');

    try{
      const descriptor=await adapters.resolveIntegrationLinkApproval({
        userCodeHash:await sha256Hex(normalized)
      });
      if(!descriptor) return response(kind,envelope,'unavailable','integration-link-preview-unavailable');
      return response(kind,{requestId:descriptor.requestId},'ok','integration-link-preview-ready',{
        descriptor
      });
    }catch(error){
      const message=String(error?.message??'');
      if(message.includes('not-found')) return response(kind,envelope,'invalid','integration-link-request-not-found');
      if(message.includes('expired')) return response(kind,envelope,'denied','integration-link-request-expired');
      if(message.includes('not-approvable')) return response(kind,envelope,'denied','integration-link-request-not-approvable');
      return response(kind,envelope,'unavailable','integration-link-preview-unavailable');
    }
  };
}
