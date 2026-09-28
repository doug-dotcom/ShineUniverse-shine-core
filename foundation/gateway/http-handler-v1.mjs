const JSON_HEADERS={
  'content-type':'application/json; charset=utf-8',
  'cache-control':'no-store'
};

const json=(status,body)=>new Response(JSON.stringify(body),{status,headers:JSON_HEADERS});
const healthPath=p=>p==='/health'||p.endsWith('/foundation-gateway/health');
const integrationProtocolPath=p=>p==='/v1/integration/protocol'||p.endsWith('/foundation-gateway/v1/integration/protocol');
const evaluatePath=p=>p==='/v1/access/evaluate'||p.endsWith('/foundation-gateway/v1/access/evaluate');
const identityClaimPath=p=>p==='/v1/identity/claim'||p.endsWith('/foundation-gateway/v1/identity/claim');
const grantConsentPath=p=>p==='/v1/grants/consent'||p.endsWith('/foundation-gateway/v1/grants/consent');
const grantRevocationPath=p=>p==='/v1/grants/revoke'||p.endsWith('/foundation-gateway/v1/grants/revoke');
const revocationFeedPath=p=>p==='/v1/revocations'||p.endsWith('/foundation-gateway/v1/revocations');
const revocationAckPath=p=>p==='/v1/revocations/ack'||p.endsWith('/foundation-gateway/v1/revocations/ack');
const revocationStatusPath=p=>p==='/v1/revocations/status'||p.endsWith('/foundation-gateway/v1/revocations/status');
const appStatusPath=p=>p==='/v1/status'||p.endsWith('/foundation-gateway/v1/status');
const capabilityDiscoveryPath=p=>p==='/v1/integration/capabilities'||p.endsWith('/foundation-gateway/v1/integration/capabilities');
const integrationClientStatusPath=p=>p==='/v1/integration/client/status'||p.endsWith('/foundation-gateway/v1/integration/client/status');
const integrationGrantsPath=p=>p==='/v1/integration/grants'||p.endsWith('/foundation-gateway/v1/integration/grants');
const integrationLinkConsentPath=p=>p==='/v1/integration/link/consent'||p.endsWith('/foundation-gateway/v1/integration/link/consent');
const integrationLinkRevokePath=p=>p==='/v1/integration/link/revoke'||p.endsWith('/foundation-gateway/v1/integration/link/revoke');
const integrationDeviceLinkRequestPath=p=>p==='/v1/integration/link/request'||p.endsWith('/foundation-gateway/v1/integration/link/request');
const integrationDeviceLinkApprovePath=p=>p==='/v1/integration/link/approve'||p.endsWith('/foundation-gateway/v1/integration/link/approve');
const integrationDeviceLinkExchangePath=p=>p==='/v1/integration/link/exchange'||p.endsWith('/foundation-gateway/v1/integration/link/exchange');
const integrationDelegationRefreshPath=p=>p==='/v1/integration/delegation/refresh'||p.endsWith('/foundation-gateway/v1/integration/delegation/refresh');
const connectedIntegrationsPath=p=>p==='/v1/integration/connections'||p.endsWith('/foundation-gateway/v1/integration/connections');
const userAccessHistoryPath=p=>p==='/v1/integration/access-history'||p.endsWith('/foundation-gateway/v1/integration/access-history');
const userAccessExplanationPath=p=>p==='/v1/integration/access-history/explain'||p.endsWith('/foundation-gateway/v1/integration/access-history/explain');
const userGrantRevokePath=p=>p==='/v1/integration/connections/grant/revoke'||p.endsWith('/foundation-gateway/v1/integration/connections/grant/revoke');
const userLinkRevokePath=p=>p==='/v1/integration/connections/revoke'||p.endsWith('/foundation-gateway/v1/integration/connections/revoke');
const userConciergeCancelPath=p=>p==='/v1/concierge/cancel'||p.endsWith('/foundation-gateway/v1/concierge/cancel');
const userConciergeJobsPath=p=>p==='/v1/concierge/jobs'||p.endsWith('/foundation-gateway/v1/concierge/jobs');
const conciergeFleetStatusPath=p=>p==='/v1/concierge/fleet'||p.endsWith('/foundation-gateway/v1/concierge/fleet');
const integrationDeviceLinkStatusPath=p=>p==='/v1/integration/link/request/status'||p.endsWith('/foundation-gateway/v1/integration/link/request/status');
const integrationDeviceLinkPreviewPath=p=>p==='/v1/integration/link/preview'||p.endsWith('/foundation-gateway/v1/integration/link/preview');
const integrationGrantConsentPath=p=>p==='/v1/integration/grants/consent'||p.endsWith('/foundation-gateway/v1/integration/grants/consent');
const integrationGrantRevokePath=p=>p==='/v1/integration/grants/revoke'||p.endsWith('/foundation-gateway/v1/integration/grants/revoke');
const conciergePlanPath=p=>p==='/v1/concierge/plan'||p.endsWith('/foundation-gateway/v1/concierge/plan');
const conciergeExecutePath=p=>p==='/v1/concierge/execute'||p.endsWith('/foundation-gateway/v1/concierge/execute');
const conciergeResumePath=p=>p==='/v1/concierge/resume'||p.endsWith('/foundation-gateway/v1/concierge/resume');
const conciergeSupersedePath=p=>p==='/v1/concierge/supersede'||p.endsWith('/foundation-gateway/v1/concierge/supersede');
const conciergeRetryClaimPath=p=>p==='/v1/concierge/retry/claim'||p.endsWith('/foundation-gateway/v1/concierge/retry/claim');
const conciergeRetryFinishPath=p=>p==='/v1/concierge/retry/finish'||p.endsWith('/foundation-gateway/v1/concierge/retry/finish');
const capabilityTicketRedeemPath=p=>p==='/v1/capability/ticket/redeem'||p.endsWith('/foundation-gateway/v1/capability/ticket/redeem');
const integrationContextPublishPath=p=>p==='/v1/integration/context/publish'||p.endsWith('/foundation-gateway/v1/integration/context/publish');
const defenceStatusMatch=p=>p.match(/(?:^|\/foundation-gateway)\/v1\/defence\/status\/([a-z0-9][a-z0-9-]{0,63})$/);
const SHA=/^[a-f0-9]{40}$/;

/** @param {{gateway:any, authenticate:any, authenticateApp?:any, authenticateIntegrationClient?:any, authenticateIntegrationUserAndClient?:any, authenticateIntegrationUser?:any, defenceStatus?:any, identityClaim?:any, authenticateIdentityClaim?:any, grantConsent?:any, grantRevocation?:any, revocationFeed?:any, revocationAck?:any, revocationHealth?:any, appOperationalStatus?:any, capabilityDiscovery?:any, integrationClientStatus?:any, integrationLinkConsent?:any, integrationCapabilityConsent?:any, integrationGrantRevocation?:any, integrationLinkRevocation?:any, integrationGrantList?:any, conciergePlan?:any, conciergeExecute?:any, integrationLinkRequest?:any, integrationLinkApproval?:any, integrationLinkStatus?:any, integrationLinkExchange?:any, integrationLinkPreview?:any, capabilityTicketRedeem?:any, integrationDelegationRefresh?:any, connectedIntegrationList?:any, userIntegrationGrantRevocation?:any, userIntegrationLinkRevocation?:any, userAccessHistory?:any, userAccessExplanation?:any, userConciergeCancellation?:any, userConciergeJobs?:any, conciergeRetry?:any, maxBodyBytes?:number}} [options] */
export function createFoundationHttpHandler({
  gateway,
  authenticate,
  authenticateApp,
  authenticateIntegrationClient,
  authenticateIntegrationUserAndClient,
  authenticateIntegrationUser,
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
  integrationClientStatus,
  integrationLinkConsent,
  integrationCapabilityConsent,
  integrationGrantRevocation,
  integrationLinkRevocation,
  integrationGrantList,
  conciergePlan,
  conciergeExecute,
  integrationLinkRequest,
  integrationLinkApproval,
  integrationLinkStatus,
  integrationLinkExchange,
  integrationLinkPreview,
  capabilityTicketRedeem,
  integrationDelegationRefresh,
  connectedIntegrationList,
  userIntegrationGrantRevocation,
  userIntegrationLinkRevocation,
  userAccessHistory,
  userAccessExplanation,
  userConciergeCancellation,
  userConciergeJobs,
  conciergeRetry,
  conciergeFleetStatus,
  integrationContextPublish,
  evaluateOperationPolicy,
  operationPolicyRequired=false,
  maxBodyBytes=16*1024
}={}){
  if(typeof gateway!=='function') throw new TypeError('gateway must be a function');
  if(typeof authenticate!=='function') throw new TypeError('authenticate must be a function');
  if(authenticateApp!==undefined&&typeof authenticateApp!=='function') throw new TypeError('authenticateApp must be a function');
  if(authenticateIntegrationClient!==undefined&&typeof authenticateIntegrationClient!=='function') throw new TypeError('authenticateIntegrationClient must be a function');
  if(authenticateIntegrationUserAndClient!==undefined&&typeof authenticateIntegrationUserAndClient!=='function') throw new TypeError('authenticateIntegrationUserAndClient must be a function');
  if(authenticateIntegrationUser!==undefined&&typeof authenticateIntegrationUser!=='function') throw new TypeError('authenticateIntegrationUser must be a function');
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
  if(integrationClientStatus!==undefined&&typeof integrationClientStatus!=='function') throw new TypeError('integrationClientStatus must be a function');
  for(const [n,v] of Object.entries({integrationLinkConsent,integrationCapabilityConsent,integrationGrantRevocation,integrationLinkRevocation,integrationGrantList,conciergePlan,conciergeExecute,integrationLinkRequest,integrationLinkApproval,integrationLinkStatus,integrationLinkExchange,integrationLinkPreview,capabilityTicketRedeem,integrationDelegationRefresh,connectedIntegrationList,userIntegrationGrantRevocation,userIntegrationLinkRevocation,userAccessHistory,userAccessExplanation,userConciergeCancellation,userConciergeJobs})){
    if(v!==undefined&&typeof v!=='function') throw new TypeError(n+' must be a function');
  }
  if(integrationContextPublish!==undefined&&typeof integrationContextPublish!=='function') throw new TypeError('integrationContextPublish must be a function');
  if(conciergeFleetStatus!==undefined&&typeof conciergeFleetStatus!=='function') throw new TypeError('conciergeFleetStatus must be a function');
  if(conciergeSupersede!==undefined&&typeof conciergeSupersede!=='function') throw new TypeError('conciergeSupersede must be a function');
  if(evaluateOperationPolicy!==undefined&&typeof evaluateOperationPolicy!=='function') throw new TypeError('evaluateOperationPolicy must be a function');
  if(operationPolicyRequired&&typeof evaluateOperationPolicy!=='function') throw new TypeError('operation policy broker is required');
  if(conciergeRetry!==undefined&&(
    !conciergeRetry||
    typeof conciergeRetry.claim!=='function'||
    typeof conciergeRetry.finish!=='function'
  )) throw new TypeError('conciergeRetry must expose claim and finish functions');

  return async function handle(request){
    const url=new URL(request.url);

    if(request.method==='POST'&&operationPolicyRequired){
      let policy;
      try{
        policy=await evaluateOperationPolicy({
          method:'POST',
          path:url.pathname,
          environment:'production',
          asOf:new Date().toISOString()
        });
      }catch{
        return json(503,{error:'operation-policy-unavailable'});
      }

      const policyState=policy?.policyState??'unavailable';
      const reasonCode=policy?.reasonCode??'operation-policy-unavailable';

      if(policyState==='deny'){
        return json(403,{error:'operation-policy-denied',reasonCode});
      }

      if(policyState==='unavailable'){
        return json(503,{error:'operation-policy-unavailable',reasonCode});
      }

      if(!['admit','admit-degraded','worker-only','not-required','not-registered'].includes(policyState)){
        return json(503,{error:'operation-policy-invalid',reasonCode});
      }
    }
    if(request.method==='POST'&&capabilityTicketRedeemPath(url.pathname)){
      if(typeof capabilityTicketRedeem!=='function') return json(404,{error:'not-found'});
      const contentType=request.headers.get('content-type')??'';
      if(!contentType.toLowerCase().startsWith('application/json')){
        return json(415,{error:'unsupported-media-type'});
      }
      const declared=Number(request.headers.get('content-length'));
      if(Number.isFinite(declared)&&declared>4096) return json(413,{error:'request-too-large'});
      let envelope;
      try{ envelope=await request.json(); }catch{ return json(400,{error:'invalid-json'}); }
      const result=await capabilityTicketRedeem({envelope});
      const status={allowed:200,denied:403,invalid:400,unavailable:503}[result.status]??500;
      return json(status,result);
    }

    if(request.method==='POST'&&integrationContextPublishPath(url.pathname)){
      if(typeof integrationContextPublish!=='function'||typeof authenticateApp!=='function') return json(404,{error:'not-found'});
      const contentType=request.headers.get('content-type')??'';
      if(!contentType.toLowerCase().startsWith('application/json')) return json(415,{error:'unsupported-media-type'});
      const limit=1152*1024;
      const declared=Number(request.headers.get('content-length'));
      if(Number.isFinite(declared)&&declared>limit) return json(413,{error:'request-too-large'});
      let raw;
      try{raw=await request.text()}catch{return json(400,{error:'invalid-body'})}
      if(new TextEncoder().encode(raw).byteLength>limit) return json(413,{error:'request-too-large'});
      let envelope;
      try{envelope=JSON.parse(raw)}catch{return json(400,{error:'invalid-json'})}
      let authContext;
      try{authContext=await authenticateApp(request)}catch{return json(401,{error:'unauthenticated'})}
      const result=await integrationContextPublish({envelope,authContext});
      const status={published:200,'already-published':200,denied:403,invalid:400,unavailable:503}[result.status]??500;
      return json(status,result);
    }

    if(request.method==='GET'&&integrationProtocolPath(url.pathname)){
      return json(200,{
        protocol:'shine-foundation/open-integration-v1',
        schemaVersion:'1.0.0',
        companionAgnostic:true,
        principles:{
          nativeCompanionRequired:false,
          userLoginSharedWithCompanion:false,
          explicitUserConsent:true,
          subsetConsent:true,
          revocable:true,
          specialistReceivesDelegationToken:false,
          specialistInvocationProof:'one-time-foundation-ticket-v2',
          userAccessHistory:true,
          explainableAccessDecisions:true,
          explainableDenials:true,
          automaticPermissionExpansion:false,
          technicalCapabilityVersionMayChangeWithoutReconsent:true,
          consentRevisionPinned:true,
          consentRevisionChangeRequiresReview:true,
          consentContractFingerprintPinned:true,
          consentSensitiveChangesRequireRevisionBump:true,
          specialistAdapterAttestationRequired:true,
          adapterAttestationAuthorityKeys:['consentRevision','consentContractFingerprint'],
          adapterAttestationChangesAudited:true,
          specialistHealthCircuitBreaker:true,
          specialistFailureThreshold:3,
          specialistFailureWindowSeconds:300,
          specialistQuarantineSeconds:300,
          specialistQuarantineRevokesConsent:false,
          partialExecutionResumable:true,
          completedSpecialistStepsReusedOnResume:true,
          resumePreservesOriginalConsentAndPurpose:true,
          resumeCheckpointRetentionSeconds:86400,
          resumeCheckpointMaxResultBytes:65536,
          transientRetryQueue:true,
          transientRetryMaxAttempts:3,
          transientRetryWindowSeconds:86400,
          transientRetryStoresSpecialistInputs:false,
          userTaskCentre:true,
          taskCentreStatuses:['planned','ready','running','partial','retry-scheduled','retry-running','completed','failed','blocked','cancelled'],
          taskCentreStoresConversationContent:false,
          taskCentreOrdering:'deterministic-workflow-state',
          taskCentreUsesAiPriorityScore:false,
          taskCentreOrderingTriggersNotification:false,
          userJobCancellation:true,
          cancellationRevokesPermissions:false,
          cancellationBlocksNewSpecialistTickets:true,
          cancellationBlocksTicketRedemption:true,
          cancellationAbandonsPendingRetries:true,
          capabilityChangesAudited:true,
          purposeBoundCapabilityGrants:true,
          accessHistoryStoresConversationContent:false
        },
        limits:{
          maxCapabilitiesPerLinkRequest:20,
          linkRequestLifetimeSeconds:600,
          delegationSessionLifetimeSeconds:86400,
          refreshCredentialLifetimeSeconds:7776000,
          refreshCredentialRotation:true,
          consentLifetime:'until-revoked',
          specialistTicketMaxLifetimeSeconds:60
        },
        endpoints:{
          capabilities:{method:'GET',path:'/v1/integration/capabilities'},
          clientStatus:{method:'GET',path:'/v1/integration/client/status'},
          linkRequest:{method:'POST',path:'/v1/integration/link/request'},
          linkStatus:{method:'GET',path:'/v1/integration/link/request/status'},
          linkPreview:{method:'GET',path:'/v1/integration/link/preview'},
          linkApprove:{method:'POST',path:'/v1/integration/link/approve'},
          linkExchange:{method:'POST',path:'/v1/integration/link/exchange'},
          delegationRefresh:{method:'POST',path:'/v1/integration/delegation/refresh'},
          grants:{method:'GET',path:'/v1/integration/grants'},
          connections:{method:'GET',path:'/v1/integration/connections'},
          accessHistory:{method:'GET',path:'/v1/integration/access-history'},
          explainAccess:{method:'GET',path:'/v1/integration/access-history/explain'},
          userCapabilityRevoke:{method:'POST',path:'/v1/integration/connections/grant/revoke'},
          userDisconnect:{method:'POST',path:'/v1/integration/connections/revoke'},
          grantRevoke:{method:'POST',path:'/v1/integration/grants/revoke'},
          linkRevoke:{method:'POST',path:'/v1/integration/link/revoke'},
          conciergePlan:{method:'POST',path:'/v1/concierge/plan'},
          conciergeExecute:{method:'POST',path:'/v1/concierge/execute'},
          conciergeResume:{method:'POST',path:'/v1/concierge/resume'},
          conciergeSupersede:{method:'POST',path:'/v1/concierge/supersede'},
          conciergeRetryClaim:{method:'POST',path:'/v1/concierge/retry/claim'},
          conciergeRetryFinish:{method:'POST',path:'/v1/concierge/retry/finish'},
          conciergeCancel:{method:'POST',path:'/v1/concierge/cancel'},
          conciergeJobs:{method:'GET',path:'/v1/concierge/jobs'},
          conciergeFleet:{method:'GET',path:'/v1/concierge/fleet'},
          contextPublish:{method:'POST',path:'/v1/integration/context/publish'}
        },
        execution:{
          genericModes:['read','advisory'],
          actionMode:'separate-confirmation-protocol-required'
        }
      });
    }

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

    if(request.method==='GET'&&integrationClientStatusPath(url.pathname)){
      if(typeof integrationClientStatus!=='function'||typeof authenticateIntegrationClient!=='function'){
        return json(404,{error:'not-found'});
      }
      const clientId=url.searchParams.get('clientId')??'';
      let authContext;
      try{authContext=await authenticateIntegrationClient(request)}catch{return json(401,{error:'unauthenticated'})}
      const result=await integrationClientStatus({clientId,authContext});
      const status={ok:200,denied:403,invalid:400,unavailable:503}[result.status]??500;
      return json(status,result);
    }

    if(request.method==='GET'&&conciergeFleetStatusPath(url.pathname)){
      if(typeof conciergeFleetStatus!=='function'||typeof authenticateIntegrationUserAndClient!=='function'){
        return json(404,{error:'not-found'});
      }
      const clientId=url.searchParams.get('clientId')??'';
      const purpose=url.searchParams.get('purpose')??'concierge.cross-project-read';
      let authContext;
      try{authContext=await authenticateIntegrationUserAndClient(request)}catch{return json(401,{error:'unauthenticated'})}
      const result=await conciergeFleetStatus({clientId,purpose,authContext});
      const status={ok:200,denied:403,invalid:400,unavailable:503}[result.status]??500;
      return json(status,result);
    }

    if(request.method==='GET'&&userConciergeJobsPath(url.pathname)){
      if(typeof userConciergeJobs!=='function'||typeof authenticateIntegrationUser!=='function'){
        return json(404,{error:'not-found'});
      }
      let authContext;
      try{authContext=await authenticateIntegrationUser(request)}catch{return json(401,{error:'unauthenticated'})}
      const result=await userConciergeJobs({
        limit:url.searchParams.get('limit')??'50',
        before:url.searchParams.get('before')||null,
        authContext
      });
      const status={ok:200,denied:403,invalid:400,unavailable:503}[result.status]??500;
      return json(status,result);
    }

    if(request.method==='GET'&&userAccessExplanationPath(url.pathname)){
      if(typeof userAccessExplanation!=='function'||typeof authenticateIntegrationUser!=='function'){
        return json(404,{error:'not-found'});
      }
      let authContext;
      try{authContext=await authenticateIntegrationUser(request)}catch{return json(401,{error:'unauthenticated'})}
      const result=await userAccessExplanation({
        accessId:url.searchParams.get('accessId')??'',authContext
      });
      const status={ok:200,denied:403,invalid:400,unavailable:503}[result.status]??500;
      return json(status,result);
    }

    if(request.method==='GET'&&userAccessHistoryPath(url.pathname)){
      if(typeof userAccessHistory!=='function'||typeof authenticateIntegrationUser!=='function'){
        return json(404,{error:'not-found'});
      }
      let authContext;
      try{authContext=await authenticateIntegrationUser(request)}catch{return json(401,{error:'unauthenticated'})}
      const result=await userAccessHistory({
        limit:url.searchParams.get('limit')??'50',
        before:url.searchParams.get('before')||null,
        authContext
      });
      const status={ok:200,denied:403,invalid:400,unavailable:503}[result.status]??500;
      return json(status,result);
    }

    if(request.method==='GET'&&connectedIntegrationsPath(url.pathname)){
      if(typeof connectedIntegrationList!=='function'||typeof authenticateIntegrationUser!=='function'){
        return json(404,{error:'not-found'});
      }
      let authContext;
      try{authContext=await authenticateIntegrationUser(request)}catch{return json(401,{error:'unauthenticated'})}
      const result=await connectedIntegrationList({authContext});
      const status={ok:200,denied:403,unavailable:503}[result.status]??500;
      return json(status,result);
    }

    if(request.method==='GET'&&integrationDeviceLinkPreviewPath(url.pathname)){
      if(typeof integrationLinkPreview!=='function'||typeof authenticateIntegrationUser!=='function'){
        return json(404,{error:'not-found'});
      }
      const userCode=url.searchParams.get('code')??'';
      let authContext;
      try{authContext=await authenticateIntegrationUser(request)}catch{return json(401,{error:'unauthenticated'})}
      const result=await integrationLinkPreview({userCode,authContext});
      const status={ok:200,denied:403,invalid:400,unavailable:503}[result.status]??500;
      return json(status,result);
    }

    if(request.method==='GET'&&integrationDeviceLinkStatusPath(url.pathname)){
      if(typeof integrationLinkStatus!=='function'||typeof authenticateIntegrationClient!=='function'){
        return json(404,{error:'not-found'});
      }
      const requestId=url.searchParams.get('requestId')??'';
      const clientId=url.searchParams.get('clientId')??'';
      let authContext;
      try{authContext=await authenticateIntegrationClient(request)}catch{return json(401,{error:'unauthenticated'})}
      const result=await integrationLinkStatus({requestId,clientId,authContext});
      const status={ok:200,denied:403,invalid:400,unavailable:503}[result.status]??500;
      return json(status,result);
    }

    if(request.method==='GET'&&integrationGrantsPath(url.pathname)){
      if(typeof integrationGrantList!=='function'||typeof authenticateIntegrationUserAndClient!=='function'){
        return json(404,{error:'not-found'});
      }
      const clientId=url.searchParams.get('clientId')??'';
      let authContext;
      try{authContext=await authenticateIntegrationUserAndClient(request)}catch{return json(401,{error:'unauthenticated'})}
      const result=await integrationGrantList({clientId,authContext});
      const status={ok:200,denied:403,invalid:400,unavailable:503}[result.status]??500;
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

    const isUserConciergeCancel=userConciergeCancelPath(url.pathname);
    const isUserGrantRevoke=userGrantRevokePath(url.pathname);
    const isUserLinkRevoke=userLinkRevokePath(url.pathname);
    const isIntegrationDeviceLinkRequest=integrationDeviceLinkRequestPath(url.pathname);
    const isIntegrationDeviceLinkApprove=integrationDeviceLinkApprovePath(url.pathname);
    const isIntegrationDeviceLinkExchange=integrationDeviceLinkExchangePath(url.pathname);
    const isIntegrationDelegationRefresh=integrationDelegationRefreshPath(url.pathname);
    const isConciergePlan=conciergePlanPath(url.pathname);
    const isConciergeExecute=conciergeExecutePath(url.pathname)||conciergeResumePath(url.pathname);
    const isConciergeSupersede=conciergeSupersedePath(url.pathname);
    const isConciergeRetryClaim=conciergeRetryClaimPath(url.pathname);
    const isConciergeRetryFinish=conciergeRetryFinishPath(url.pathname);
    const isIntegrationLinkConsent=integrationLinkConsentPath(url.pathname);
    const isIntegrationLinkRevoke=integrationLinkRevokePath(url.pathname);
    const isIntegrationGrantConsent=integrationGrantConsentPath(url.pathname);
    const isIntegrationGrantRevoke=integrationGrantRevokePath(url.pathname);
    const isClaim=identityClaimPath(url.pathname);
    const isGrantConsent=grantConsentPath(url.pathname);
    const isGrantRevocation=grantRevocationPath(url.pathname);
    const isRevocationAck=revocationAckPath(url.pathname);
    const isEvaluate=evaluatePath(url.pathname);
    if(!isConciergeRetryClaim&&!isConciergeRetryFinish&&!isConciergeSupersede&&!isUserConciergeCancel&&!isUserGrantRevoke&&!isUserLinkRevoke&&!isIntegrationDeviceLinkRequest&&!isIntegrationDeviceLinkApprove&&!isIntegrationDeviceLinkExchange&&!isIntegrationDelegationRefresh&&!isConciergePlan&&!isConciergeExecute&&!isIntegrationLinkConsent&&!isIntegrationLinkRevoke&&!isIntegrationGrantConsent&&!isIntegrationGrantRevoke&&!isClaim&&!isGrantConsent&&!isGrantRevocation&&!isRevocationAck&&!isEvaluate) return json(404,{error:'not-found'});
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

    if(isConciergeRetryClaim||isConciergeRetryFinish){
      if(!conciergeRetry||typeof authenticateIntegrationClient!=='function') return json(404,{error:'not-found'});
      let authContext;
      try{authContext=await authenticateIntegrationClient(request)}catch{return json(401,{error:'unauthenticated'})}
      if(isConciergeRetryClaim){
        const clientId=String(envelope?.clientId??'');
        const result=await conciergeRetry.claim({clientId,authContext});
        const status={ok:200,denied:403,unavailable:503}[result.status]??400;
        return json(status,result);
      }
      const result=await conciergeRetry.finish({envelope,authContext});
      const status={ok:200,denied:403,invalid:400,unavailable:503}[result.status]??500;
      return json(status,result);
    }

    if(isConciergeSupersede){
      if(typeof conciergeSupersede!=='function'||typeof authenticateIntegrationUserAndClient!=='function'){
        return json(404,{error:'not-found'});
      }
      let authContext;
      try{authContext=await authenticateIntegrationUserAndClient(request)}catch{return json(401,{error:'unauthenticated'})}
      const result=await conciergeSupersede({envelope,authContext});
      const status={superseded:200,'already-superseded':200,denied:403,invalid:400,unavailable:503}[result.status]??500;
      return json(status,result);
    }

    if(isUserConciergeCancel){
      if(typeof userConciergeCancellation!=='function'||typeof authenticateIntegrationUser!=='function'){
        return json(404,{error:'not-found'});
      }
      let authContext;
      try{authContext=await authenticateIntegrationUser(request)}catch{return json(401,{error:'unauthenticated'})}
      const result=await userConciergeCancellation({envelope,authContext});
      const status={cancelled:200,'already-cancelled':200,denied:403,invalid:400,unavailable:503}[result.status]??500;
      return json(status,result);
    }

    if(isUserGrantRevoke||isUserLinkRevoke){
      if(typeof authenticateIntegrationUser!=='function') return json(404,{error:'not-found'});
      let authContext;
      try{authContext=await authenticateIntegrationUser(request)}catch{return json(401,{error:'unauthenticated'})}
      const service=isUserGrantRevoke?userIntegrationGrantRevocation:userIntegrationLinkRevocation;
      if(typeof service!=='function') return json(404,{error:'not-found'});
      const result=await service({envelope,authContext});
      const status={revoked:200,'already-revoked':200,denied:403,invalid:400,unavailable:503}[result.status]??500;
      return json(status,result);
    }

    if(isIntegrationDeviceLinkRequest){
      if(typeof integrationLinkRequest!=='function'||typeof authenticateIntegrationClient!=='function'){
        return json(404,{error:'not-found'});
      }
      let authContext;
      try{authContext=await authenticateIntegrationClient(request)}catch{return json(401,{error:'unauthenticated'})}
      const result=await integrationLinkRequest({envelope,authContext});
      const status={created:201,denied:403,invalid:400,unavailable:503}[result.status]??500;
      return json(status,result);
    }

    if(isIntegrationDeviceLinkApprove){
      if(typeof integrationLinkApproval!=='function'||typeof authenticateIntegrationUser!=='function'){
        return json(404,{error:'not-found'});
      }
      let authContext;
      try{authContext=await authenticateIntegrationUser(request)}catch{return json(401,{error:'unauthenticated'})}
      const result=await integrationLinkApproval({envelope,authContext});
      const status={approved:200,'already-approved':200,denied:403,invalid:400,unavailable:503}[result.status]??500;
      return json(status,result);
    }

    if(isIntegrationDelegationRefresh){
      if(typeof integrationDelegationRefresh!=='function'||typeof authenticateIntegrationClient!=='function'){
        return json(404,{error:'not-found'});
      }
      let authContext;
      try{authContext=await authenticateIntegrationClient(request)}catch{return json(401,{error:'unauthenticated'})}
      const result=await integrationDelegationRefresh({envelope,authContext});
      const status={refreshed:200,denied:403,invalid:400,unavailable:503}[result.status]??500;
      return json(status,result);
    }

    if(isIntegrationDeviceLinkExchange){
      if(typeof integrationLinkExchange!=='function'||typeof authenticateIntegrationClient!=='function'){
        return json(404,{error:'not-found'});
      }
      let authContext;
      try{authContext=await authenticateIntegrationClient(request)}catch{return json(401,{error:'unauthenticated'})}
      const result=await integrationLinkExchange({envelope,authContext});
      const status={exchanged:200,denied:403,invalid:400,unavailable:503}[result.status]??500;
      return json(status,result);
    }

    if(isConciergePlan||isConciergeExecute){
      if(typeof authenticateIntegrationUserAndClient!=='function') return json(404,{error:'not-found'});
      let authContext;
      try{authContext=await authenticateIntegrationUserAndClient(request)}catch{return json(401,{error:'unauthenticated'})}
      const service=isConciergePlan?conciergePlan:conciergeExecute;
      if(typeof service!=='function') return json(404,{error:'not-found'});
      const result=await service({envelope,authContext});
      const status={planned:200,ready:202,completed:200,partial:200,failed:502,blocked:409,denied:403,invalid:400,unavailable:503}[result.status]??500;
      return json(status,result);
    }

    if(isIntegrationLinkConsent||isIntegrationLinkRevoke||isIntegrationGrantConsent||isIntegrationGrantRevoke){
      if(typeof authenticateIntegrationUserAndClient!=='function') return json(404,{error:'not-found'});
      let authContext;
      try{authContext=await authenticateIntegrationUserAndClient(request)}catch{return json(401,{error:'unauthenticated'})}

      const service=isIntegrationLinkConsent?integrationLinkConsent:
        isIntegrationLinkRevoke?integrationLinkRevocation:
        isIntegrationGrantConsent?integrationCapabilityConsent:
        integrationGrantRevocation;
      if(typeof service!=='function') return json(404,{error:'not-found'});

      const result=await service({envelope,authContext});
      const status={
        linked:200,'already-linked':200,granted:200,'already-granted':200,
        revoked:200,'already-revoked':200,denied:403,invalid:400,unavailable:503
      }[result.status]??500;
      return json(status,result);
    }

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
