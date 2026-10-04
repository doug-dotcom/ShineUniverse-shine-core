const UUID=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const CLIENT=/^[a-z0-9][a-z0-9._:-]*$/;
const TOKEN=/^[a-z0-9][a-z0-9._:-]*$/;

const fresh=(requestedAt,clock)=>{
  const t=Date.parse(requestedAt??'');
  const now=Date.parse(clock());
  return Number.isFinite(t)&&Number.isFinite(now)&&t>=now-10*60*1000&&t<=now+5*60*1000;
};

const requireAdapter=(adapters,name)=>{
  if(typeof adapters?.[name]!=='function') throw new TypeError('missing integration consent adapter: '+name);
};

async function verifyPair(adapters,authContext,clientId){
  const client=await adapters.verifyIntegrationClient({authContext,claimedClientId:clientId});
  if(!client?.clientId) return {error:'integration-client-unverified'};
  if(client.clientId!==clientId) return {error:'integration-client-mismatch'};

  if(authContext?.delegationToken){
    const delegated=await adapters.verifyIntegrationDelegation({authContext,claimedClientId:clientId});
    if(!delegated?.shineId) return {error:'delegation-unverified'};
    if(delegated.clientId!==clientId) return {error:'delegation-client-mismatch'};
    return {
      client,
      identity:{
        shineId:delegated.shineId,
        providerId:'foundation-delegation',
        sessionId:delegated.sessionId
      }
    };
  }

  const identity=await adapters.verifyIntegrationIdentity({authContext});
  if(!identity?.shineId) return {error:'identity-unverified'};
  return {client,identity};
}

const base=(kind,envelope,status,reasonCode,extra={})=>({
  integrationResponse:kind,
  schemaVersion:'1.0.0',
  requestId:envelope?.requestId??null,
  status,
  reasonCode,
  ...extra
});

export function createIntegrationLinkConsentService({adapters,clock=()=>new Date().toISOString(),idFactory=()=>crypto.randomUUID()}={}){
  for(const n of ['verifyIntegrationClient','verifyIntegrationIdentity','verifyIntegrationDelegation','linkIntegrationClient']) requireAdapter(adapters,n);
  return async function handle({envelope,authContext}={}){
    const kind='shine-foundation/integration-link-consent-response-v1';
    if(!envelope||envelope.integrationLinkConsent!=='shine-foundation/integration-link-consent-v1'||
       envelope.schemaVersion!=='1.0.0'||!UUID.test(envelope.requestId??'')||
       !CLIENT.test(envelope.clientId??'')||envelope.consent!==true||
       !fresh(envelope.requestedAt,clock)){
      return base(kind,envelope,'invalid','invalid-integration-link-consent');
    }
    if(envelope.expiresAt!==undefined&&envelope.expiresAt!==null&&!Number.isFinite(Date.parse(envelope.expiresAt))){
      return base(kind,envelope,'invalid','invalid-link-expiry');
    }
    let verified;
    try{verified=await verifyPair(adapters,authContext,envelope.clientId)}catch{return base(kind,envelope,'unavailable','foundation-dependency-unavailable')}
    if(verified.error) return base(kind,envelope,'denied',verified.error);
    let result;
    try{
      result=await adapters.linkIntegrationClient({
        eventId:idFactory(),linkId:idFactory(),requestId:envelope.requestId,
        ownerShineId:verified.identity.shineId,clientId:envelope.clientId,
        expiresAt:envelope.expiresAt??null,occurredAt:clock()
      });
    }catch{return base(kind,envelope,'unavailable','integration-link-write-failed')}
    if(!result?.outcome) return base(kind,envelope,'unavailable','integration-link-write-failed');
    return base(kind,envelope,
      result.outcome==='linked'?'linked':result.outcome==='already-linked'?'already-linked':'denied',
      result.reasonCode,{linkId:result.linkId??null}
    );
  };
}

export function createIntegrationCapabilityConsentService({adapters,clock=()=>new Date().toISOString(),idFactory=()=>crypto.randomUUID()}={}){
  for(const n of ['verifyIntegrationClient','verifyIntegrationIdentity','verifyIntegrationDelegation','grantIntegrationClientCapability']) requireAdapter(adapters,n);
  return async function handle({envelope,authContext}={}){
    const kind='shine-foundation/integration-capability-consent-response-v1';
    if(!envelope||envelope.integrationCapabilityConsent!=='shine-foundation/integration-capability-consent-v1'||
       envelope.schemaVersion!=='1.0.0'||!UUID.test(envelope.requestId??'')||
       !CLIENT.test(envelope.clientId??'')||!TOKEN.test(envelope.capabilityId??'')||
       !TOKEN.test(envelope.purpose??'')||envelope.consent!==true||
       !fresh(envelope.requestedAt,clock)){
      return base(kind,envelope,'invalid','invalid-integration-capability-consent');
    }
    if(envelope.expiresAt!==undefined&&envelope.expiresAt!==null&&
       (typeof envelope.expiresAt!=='string'||!Number.isFinite(Date.parse(envelope.expiresAt))||
        Date.parse(envelope.expiresAt)<=Date.parse(clock()))){
      return base(kind,envelope,'invalid','invalid-grant-expiry');
    }
    let verified;
    try{verified=await verifyPair(adapters,authContext,envelope.clientId)}catch{return base(kind,envelope,'unavailable','foundation-dependency-unavailable')}
    if(verified.error) return base(kind,envelope,'denied',verified.error);
    let result;
    try{
      result=await adapters.grantIntegrationClientCapability({
        eventId:idFactory(),grantId:idFactory(),requestId:envelope.requestId,
        ownerShineId:verified.identity.shineId,clientId:envelope.clientId,
        capabilityId:envelope.capabilityId,purpose:envelope.purpose,
        expiresAt:envelope.expiresAt??null,occurredAt:clock()
      });
    }catch{return base(kind,envelope,'unavailable','integration-capability-grant-write-failed')}
    if(!result?.outcome) return base(kind,envelope,'unavailable','integration-capability-grant-write-failed');
    return base(kind,envelope,
      result.outcome==='granted'?'granted':result.outcome==='already-granted'?'already-granted':'denied',
      result.reasonCode,{grantId:result.grantId??null}
    );
  };
}

export function createIntegrationGrantRevocationService({adapters,clock=()=>new Date().toISOString(),idFactory=()=>crypto.randomUUID()}={}){
  for(const n of ['verifyIntegrationClient','verifyIntegrationIdentity','verifyIntegrationDelegation','revokeIntegrationClientGrant']) requireAdapter(adapters,n);
  return async function handle({envelope,authContext}={}){
    const kind='shine-foundation/integration-grant-revocation-response-v1';
    if(!envelope||envelope.integrationGrantRevocation!=='shine-foundation/integration-grant-revocation-v1'||
       envelope.schemaVersion!=='1.0.0'||!UUID.test(envelope.requestId??'')||
       !CLIENT.test(envelope.clientId??'')||!UUID.test(envelope.grantId??'')||
       envelope.revoke!==true||!fresh(envelope.requestedAt,clock)){
      return base(kind,envelope,'invalid','invalid-integration-grant-revocation');
    }
    let verified;
    try{verified=await verifyPair(adapters,authContext,envelope.clientId)}catch{return base(kind,envelope,'unavailable','foundation-dependency-unavailable')}
    if(verified.error) return base(kind,envelope,'denied',verified.error);
    let result;
    try{
      result=await adapters.revokeIntegrationClientGrant({
        eventId:idFactory(),revocationId:idFactory(),requestId:envelope.requestId,
        ownerShineId:verified.identity.shineId,clientId:envelope.clientId,
        grantId:envelope.grantId,occurredAt:clock()
      });
    }catch{return base(kind,envelope,'unavailable','integration-grant-revocation-write-failed')}
    if(!result?.outcome) return base(kind,envelope,'unavailable','integration-grant-revocation-write-failed');
    return base(kind,envelope,
      result.outcome==='revoked'?'revoked':result.outcome==='already-revoked'?'already-revoked':'denied',
      result.reasonCode,{grantId:result.grantId??envelope.grantId}
    );
  };
}

export function createIntegrationLinkRevocationService({adapters,clock=()=>new Date().toISOString(),idFactory=()=>crypto.randomUUID()}={}){
  for(const n of ['verifyIntegrationClient','verifyIntegrationIdentity','verifyIntegrationDelegation','revokeIntegrationClientLink']) requireAdapter(adapters,n);
  return async function handle({envelope,authContext}={}){
    const kind='shine-foundation/integration-link-revocation-response-v1';
    if(!envelope||envelope.integrationLinkRevocation!=='shine-foundation/integration-link-revocation-v1'||
       envelope.schemaVersion!=='1.0.0'||!UUID.test(envelope.requestId??'')||
       !CLIENT.test(envelope.clientId??'')||!UUID.test(envelope.linkId??'')||
       envelope.revoke!==true||!fresh(envelope.requestedAt,clock)){
      return base(kind,envelope,'invalid','invalid-integration-link-revocation');
    }
    let verified;
    try{verified=await verifyPair(adapters,authContext,envelope.clientId)}catch{return base(kind,envelope,'unavailable','foundation-dependency-unavailable')}
    if(verified.error) return base(kind,envelope,'denied',verified.error);
    let result;
    try{
      result=await adapters.revokeIntegrationClientLink({
        eventId:idFactory(),revocationId:idFactory(),requestId:envelope.requestId,
        ownerShineId:verified.identity.shineId,clientId:envelope.clientId,
        linkId:envelope.linkId,occurredAt:clock()
      });
    }catch{return base(kind,envelope,'unavailable','integration-link-revocation-write-failed')}
    if(!result?.outcome) return base(kind,envelope,'unavailable','integration-link-revocation-write-failed');
    return base(kind,envelope,
      result.outcome==='revoked'?'revoked':result.outcome==='already-revoked'?'already-revoked':'denied',
      result.reasonCode,{linkId:result.linkId??envelope.linkId}
    );
  };
}

export function createIntegrationGrantListService({adapters}={}){
  for(const n of ['verifyIntegrationClient','verifyIntegrationIdentity','verifyIntegrationDelegation','listIntegrationClientGrants']) requireAdapter(adapters,n);
  return async function handle({clientId,authContext}={}){
    const kind='shine-foundation/integration-grant-list-response-v1';
    const envelope={requestId:null};
    if(!CLIENT.test(clientId??'')) return base(kind,envelope,'invalid','invalid-client-id');
    let verified;
    try{verified=await verifyPair(adapters,authContext,clientId)}catch{return base(kind,envelope,'unavailable','foundation-dependency-unavailable')}
    if(verified.error) return base(kind,envelope,'denied',verified.error);
    try{
      const grants=await adapters.listIntegrationClientGrants({
        ownerShineId:verified.identity.shineId,clientId
      });
      return base(kind,envelope,'ok','integration-grants-listed',{
        clientId,grants:Array.isArray(grants)?grants:[]
      });
    }catch{return base(kind,envelope,'unavailable','integration-grants-unavailable')}
  };
}
