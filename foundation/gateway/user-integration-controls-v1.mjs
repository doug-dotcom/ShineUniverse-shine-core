const UUID=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const CLIENT=/^[a-z0-9][a-z0-9._:-]*$/;
const response=(kind,status,reasonCode,extra={})=>({
  integrationResponse:kind,schemaVersion:'1.0.0',status,reasonCode,...extra
});
const need=(adapters,name)=>{
  if(typeof adapters?.[name]!=='function') throw new TypeError('missing connection control adapter: '+name);
};

export function createConnectedIntegrationListService({adapters}={}){
  for(const n of ['verifyIntegrationIdentity','listConnectedIntegrations']) need(adapters,n);
  return async function handle({authContext}={}){
    let identity;
    try{identity=await adapters.verifyIntegrationIdentity({authContext})}
    catch{return response('shine-foundation/connected-integrations-response-v1','unavailable','foundation-dependency-unavailable')}
    if(!identity?.shineId) return response('shine-foundation/connected-integrations-response-v1','denied','identity-unverified');
    try{
      const integrations=await adapters.listConnectedIntegrations({ownerShineId:identity.shineId});
      return response('shine-foundation/connected-integrations-response-v1','ok','connected-integrations-listed',{integrations});
    }catch{
      return response('shine-foundation/connected-integrations-response-v1','unavailable','connected-integrations-unavailable');
    }
  };
}

export function createUserGrantRevocationService({adapters,clock=()=>new Date().toISOString(),idFactory=()=>crypto.randomUUID()}={}){
  for(const n of ['verifyIntegrationIdentity','revokeIntegrationClientGrant']) need(adapters,n);
  return async function handle({envelope,authContext}={}){
    const kind='shine-foundation/user-integration-grant-revocation-response-v1';
    if(!envelope||envelope.userIntegrationGrantRevocation!=='shine-foundation/user-integration-grant-revocation-v1'||
       envelope.schemaVersion!=='1.0.0'||!UUID.test(envelope.requestId??'')||
       !UUID.test(envelope.grantId??'')||!CLIENT.test(envelope.clientId??'')||
       envelope.revoke!==true){
      return response(kind,'invalid','invalid-user-grant-revocation');
    }
    let identity;
    try{identity=await adapters.verifyIntegrationIdentity({authContext})}
    catch{return response(kind,'unavailable','foundation-dependency-unavailable')}
    if(!identity?.shineId) return response(kind,'denied','identity-unverified');

    try{
      const result=await adapters.revokeIntegrationClientGrant({
        eventId:idFactory(),revocationId:idFactory(),requestId:envelope.requestId,
        ownerShineId:identity.shineId,clientId:envelope.clientId,
        grantId:envelope.grantId,occurredAt:clock()
      });
      if(!result?.outcome) return response(kind,'unavailable','integration-grant-revocation-write-failed');
      return response(kind,
        result.outcome==='revoked'?'revoked':result.outcome==='already-revoked'?'already-revoked':'denied',
        result.reasonCode,{grantId:result.grantId??envelope.grantId}
      );
    }catch{
      return response(kind,'unavailable','integration-grant-revocation-write-failed');
    }
  };
}

export function createUserLinkRevocationService({adapters,clock=()=>new Date().toISOString(),idFactory=()=>crypto.randomUUID()}={}){
  for(const n of ['verifyIntegrationIdentity','revokeIntegrationClientLink']) need(adapters,n);
  return async function handle({envelope,authContext}={}){
    const kind='shine-foundation/user-integration-link-revocation-response-v1';
    if(!envelope||envelope.userIntegrationLinkRevocation!=='shine-foundation/user-integration-link-revocation-v1'||
       envelope.schemaVersion!=='1.0.0'||!UUID.test(envelope.requestId??'')||
       !UUID.test(envelope.linkId??'')||!CLIENT.test(envelope.clientId??'')||
       envelope.revoke!==true){
      return response(kind,'invalid','invalid-user-link-revocation');
    }
    let identity;
    try{identity=await adapters.verifyIntegrationIdentity({authContext})}
    catch{return response(kind,'unavailable','foundation-dependency-unavailable')}
    if(!identity?.shineId) return response(kind,'denied','identity-unverified');

    try{
      const result=await adapters.revokeIntegrationClientLink({
        eventId:idFactory(),revocationId:idFactory(),requestId:envelope.requestId,
        ownerShineId:identity.shineId,clientId:envelope.clientId,
        linkId:envelope.linkId,occurredAt:clock()
      });
      if(!result?.outcome) return response(kind,'unavailable','integration-link-revocation-write-failed');
      return response(kind,
        result.outcome==='revoked'?'revoked':result.outcome==='already-revoked'?'already-revoked':'denied',
        result.reasonCode,{linkId:result.linkId??envelope.linkId}
      );
    }catch{
      return response(kind,'unavailable','integration-link-revocation-write-failed');
    }
  };
}


export function createUserAccessHistoryService({adapters}={}){
  for(const n of ['verifyIntegrationIdentity','listUserAccessHistory']) need(adapters,n);
  return async function handle({limit=50,before=null,authContext}={}){
    let identity;
    try{identity=await adapters.verifyIntegrationIdentity({authContext})}
    catch{return response('shine-foundation/user-access-history-response-v1','unavailable','foundation-dependency-unavailable')}
    if(!identity?.shineId) return response('shine-foundation/user-access-history-response-v1','denied','identity-unverified');

    const parsedLimit=Number(limit);
    if(!Number.isInteger(parsedLimit)||parsedLimit<1||parsedLimit>100){
      return response('shine-foundation/user-access-history-response-v1','invalid','invalid-history-limit');
    }
    if(before!==null&&!Number.isFinite(Date.parse(before))){
      return response('shine-foundation/user-access-history-response-v1','invalid','invalid-history-cursor');
    }

    try{
      const history=await adapters.listUserAccessHistory({
        ownerShineId:identity.shineId,limit:parsedLimit,before
      });
      return response('shine-foundation/user-access-history-response-v1','ok','user-access-history-listed',history);
    }catch{
      return response('shine-foundation/user-access-history-response-v1','unavailable','user-access-history-unavailable');
    }
  };
}


export function createUserAccessExplanationService({adapters}={}){
  for(const n of ['verifyIntegrationIdentity','explainCapabilityAccess']) need(adapters,n);
  return async function handle({accessId,authContext}={}){
    const kind='shine-foundation/user-access-explanation-response-v1';
    if(!UUID.test(accessId??'')) return response(kind,'invalid','invalid-access-id');

    let identity;
    try{identity=await adapters.verifyIntegrationIdentity({authContext})}
    catch{return response(kind,'unavailable','foundation-dependency-unavailable')}
    if(!identity?.shineId) return response(kind,'denied','identity-unverified');

    try{
      const explanation=await adapters.explainCapabilityAccess({
        ownerShineId:identity.shineId,ticketId:accessId
      });
      if(!explanation) return response(kind,'invalid','access-record-not-found');
      return response(kind,'ok','access-explanation-ready',{explanation});
    }catch(error){
      const message=String(error?.message??'');
      if(message.includes('not-found')) return response(kind,'invalid','access-record-not-found');
      return response(kind,'unavailable','access-explanation-unavailable');
    }
  };
}


export function createUserConciergeCancellationService({adapters,clock=()=>new Date().toISOString(),idFactory=()=>crypto.randomUUID()}={}){
  for(const n of ['verifyIntegrationIdentity','cancelConciergeRequest']) need(adapters,n);
  return async function handle({envelope,authContext}={}){
    const kind='shine-foundation/user-concierge-cancel-response-v1';
    if(!envelope||envelope.userConciergeCancel!=='shine-foundation/user-concierge-cancel-v1'||
       envelope.schemaVersion!=='1.0.0'||!UUID.test(envelope.requestId??'')||
       !CLIENT.test(envelope.clientId??'')||envelope.cancel!==true){
      return response(kind,'invalid','invalid-concierge-cancellation');
    }
    let identity;
    try{identity=await adapters.verifyIntegrationIdentity({authContext})}
    catch{return response(kind,'unavailable','foundation-dependency-unavailable')}
    if(!identity?.shineId) return response(kind,'denied','identity-unverified');

    try{
      const result=await adapters.cancelConciergeRequest({
        eventId:idFactory(),requestId:envelope.requestId,
        ownerShineId:identity.shineId,clientId:envelope.clientId,
        reasonCode:'user-cancelled',occurredAt:clock()
      });
      if(!result?.status) return response(kind,'unavailable','concierge-cancellation-write-failed');
      return response(kind,result.status,result.reasonCode??'user-cancelled',{
        requestId:envelope.requestId,cancelledAt:result.cancelledAt??null
      });
    }catch(error){
      const message=String(error?.message??'');
      if(message.includes('not-found')) return response(kind,'invalid','concierge-request-not-found');
      if(message.includes('owner-mismatch')) return response(kind,'denied','concierge-request-owner-mismatch');
      if(message.includes('client-mismatch')) return response(kind,'denied','concierge-request-client-mismatch');
      return response(kind,'unavailable','concierge-cancellation-write-failed');
    }
  };
}


export function createUserConciergeJobsService({adapters}={}){
  for(const n of ['verifyIntegrationIdentity','listUserConciergeJobs']) need(adapters,n);
  return async function handle({limit=50,before=null,authContext}={}){
    const kind='shine-foundation/user-concierge-jobs-response-v1';
    const parsedLimit=Number(limit);
    if(!Number.isInteger(parsedLimit)||parsedLimit<1||parsedLimit>100){
      return response(kind,'invalid','invalid-jobs-limit');
    }
    if(before!==null&&!Number.isFinite(Date.parse(before))){
      return response(kind,'invalid','invalid-jobs-cursor');
    }

    let identity;
    try{identity=await adapters.verifyIntegrationIdentity({authContext})}
    catch{return response(kind,'unavailable','foundation-dependency-unavailable')}
    if(!identity?.shineId) return response(kind,'denied','identity-unverified');

    try{
      const jobs=await adapters.listUserConciergeJobs({
        ownerShineId:identity.shineId,limit:parsedLimit,before
      });
      return response(kind,'ok','concierge-jobs-listed',jobs);
    }catch{
      return response(kind,'unavailable','concierge-jobs-unavailable');
    }
  };
}
