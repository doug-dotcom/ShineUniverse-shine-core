import postgres from 'npm:postgres@3.4.9';
import {createFoundationGateway} from '../../gateway/gateway-core-v1.mjs';
import {createIdentityClaimService} from '../../gateway/identity-claim-v1.mjs';
import {createGrantConsentService} from '../../gateway/grant-consent-v1.mjs';
import {createGrantRevocationService} from '../../gateway/grant-revocation-v1.mjs';
import {createRevocationFeedService} from '../../gateway/revocation-feed-v1.mjs';
import {createRevocationAckService} from '../../gateway/revocation-ack-v1.mjs';
import {createRevocationHealthService} from '../../gateway/revocation-health-v1.mjs';
import {createAppOperationalStatusService} from '../../gateway/app-operational-status-v1.mjs';
import {createCapabilityDiscoveryService} from '../../gateway/capability-discovery-v1.mjs';
import {createIntegrationClientStatusService} from '../../gateway/integration-client-status-v1.mjs';
import {createIntegrationLinkConsentService,createIntegrationCapabilityConsentService,createIntegrationGrantRevocationService,createIntegrationLinkRevocationService,createIntegrationGrantListService} from '../../gateway/integration-user-consent-v1.mjs';
import {createConciergePlanService,createConciergeExecuteService,createConciergeSupersedeService} from '../../gateway/concierge-orchestration-v1.mjs';
import {createIntegrationLinkRequestService,createIntegrationLinkApprovalService,createIntegrationLinkStatusService,createIntegrationLinkExchangeService,createIntegrationLinkPreviewService} from '../../gateway/integration-device-link-v1.mjs';
import {createCapabilityTicketRedeemService} from '../../gateway/capability-ticket-redeem-v2.mjs';
import {createIntegrationDelegationRefreshService} from '../../gateway/integration-delegation-refresh-v1.mjs';
import {createConnectedIntegrationListService,createUserGrantRevocationService,createUserLinkRevocationService,createUserAccessHistoryService,createUserAccessExplanationService,createUserConciergeCancellationService,createUserConciergeJobsService} from '../../gateway/user-integration-controls-v1.mjs';
import {createConciergeRetryService} from '../../gateway/concierge-retry-v1.mjs';
import {createConciergeFleetStatusService} from '../../gateway/concierge-fleet-status-v1.mjs';
import {createFoundationHttpHandler} from '../../gateway/http-handler-v1.mjs';
import {createPublicDefenceStatusService} from '../../gateway/defence-status-v1.mjs';
import {createIntegrationContextPublishService} from '../../gateway/integration-context-publish-v1.mjs';
import {createSupabaseRuntimeAdapters} from '../supabase-runtime-adapters-v1.mjs';
import {createFoundationRuntimeDefenceGateV1} from '../runtime-defence-gate-v1.mjs';
import defenceLedger from '../../../security/shine-defence/ecosystem-profile-ledger-v1.json' with {type:'json'};
import defenceRevocations from '../../../security/shine-defence/revocations-v1.json' with {type:'json'};

const requireEnv=(name:string)=>{
  const value=Deno.env.get(name);
  if(!value) throw new Error('Missing required environment variable: '+name);
  return value;
};

const rawSql=postgres(requireEnv('SUPABASE_DB_URL'),{
  max:1,
  prepare:false,
  idle_timeout:20,
  connect_timeout:10
});

const sql:any=(strings:any,...values:any[])=>rawSql.begin(async(tx:any)=>{
  await tx.unsafe('set local role foundation_gateway');
  return tx(strings,...values);
});

const adapters=createSupabaseRuntimeAdapters({
  sql,
  fetchImpl:fetch,
  defenceGate:createFoundationRuntimeDefenceGateV1()
});

const gateway=createFoundationGateway({adapters} as any);
const identityClaim=createIdentityClaimService({adapters} as any);
const grantConsent=createGrantConsentService({adapters} as any);
const grantRevocation=createGrantRevocationService({adapters} as any);
const revocationFeed=createRevocationFeedService({adapters} as any);
const revocationAck=createRevocationAckService({adapters} as any);
const revocationHealth=createRevocationHealthService({adapters} as any);
const appOperationalStatus=createAppOperationalStatusService({adapters} as any);
const capabilityDiscovery=createCapabilityDiscoveryService({adapters} as any);
const integrationClientStatus=createIntegrationClientStatusService({adapters} as any);
const integrationLinkConsent=createIntegrationLinkConsentService({adapters} as any);
const integrationCapabilityConsent=createIntegrationCapabilityConsentService({adapters} as any);
const integrationGrantRevocation=createIntegrationGrantRevocationService({adapters} as any);
const integrationLinkRevocation=createIntegrationLinkRevocationService({adapters} as any);
const integrationGrantList=createIntegrationGrantListService({adapters} as any);
const conciergePlan=createConciergePlanService({adapters} as any);
const conciergeExecute=createConciergeExecuteService({adapters} as any);
const conciergeSupersede=createConciergeSupersedeService({adapters} as any);
const integrationLinkRequest=createIntegrationLinkRequestService({adapters} as any);
const integrationLinkApproval=createIntegrationLinkApprovalService({adapters} as any);
const integrationLinkStatus=createIntegrationLinkStatusService({adapters} as any);
const integrationLinkExchange=createIntegrationLinkExchangeService({adapters} as any);
const integrationLinkPreview=createIntegrationLinkPreviewService({adapters} as any);
const capabilityTicketRedeem=createCapabilityTicketRedeemService({adapters} as any);
const integrationDelegationRefresh=createIntegrationDelegationRefreshService({adapters} as any);
const connectedIntegrationList=createConnectedIntegrationListService({adapters} as any);
const userIntegrationGrantRevocation=createUserGrantRevocationService({adapters} as any);
const userIntegrationLinkRevocation=createUserLinkRevocationService({adapters} as any);
const userAccessHistory=createUserAccessHistoryService({adapters} as any);
const userAccessExplanation=createUserAccessExplanationService({adapters} as any);
const userConciergeCancellation=createUserConciergeCancellationService({adapters} as any);
const userConciergeJobs=createUserConciergeJobsService({adapters} as any);
const conciergeRetry=createConciergeRetryService({adapters} as any);
const conciergeFleetStatus=createConciergeFleetStatusService({adapters} as any);
const integrationContextPublish=createIntegrationContextPublishService({adapters} as any);
const defenceStatus=createPublicDefenceStatusService({
  ledger:defenceLedger,
  revocations:defenceRevocations
});

const handler=createFoundationHttpHandler({
  gateway,
  identityClaim,
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
  conciergeSupersede,
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
  defenceStatus,
  evaluateOperationPolicy:adapters.evaluateGatewayRoutePolicy,
  operationPolicyRequired:true,
  recordOperationAudit:adapters.recordGatewayOperationAuditEvent,
  operationAuditRequired:true,
  maxBodyBytes:16*1024,
  authenticateIntegrationUser:async(request:Request)=>{
    const authorization=request.headers.get('authorization')??'';
    const jwt=authorization.startsWith('Bearer ')?authorization.slice('Bearer '.length):'';
    if(!jwt) throw new Error('missing integration user credential');
    return {jwt};
  },
  authenticateIntegrationUserAndClient:async(request:Request)=>{
    const authorization=request.headers.get('authorization')??'';
    const clientToken=request.headers.get('x-shine-client-token')??'';
    const delegationToken=request.headers.get('x-shine-delegation-token')??'';
    const jwt=authorization.startsWith('Bearer ')?authorization.slice('Bearer '.length):'';
    if(!clientToken||(!jwt&&!delegationToken)) throw new Error('missing integration actor credentials');
    return {clientToken,...(jwt?{jwt}:{}),...(delegationToken?{delegationToken}:{})};
  },
  authenticateIntegrationClient:async(request:Request)=>{
    const clientToken=request.headers.get('x-shine-client-token')??'';
    const refreshToken=request.headers.get('x-shine-refresh-token')??'';
    if(!clientToken) throw new Error('missing integration client credential');
    return {clientToken,...(refreshToken?{refreshToken}:{})};
  },
  authenticateApp:async(request:Request)=>{
    const appToken=request.headers.get('x-shine-app-token')??'';
    if(!appToken) throw new Error('missing app credential');
    return {appToken};
  },
  authenticate:async(request:Request)=>{
    const authorization=request.headers.get('authorization')??'';
    const appToken=request.headers.get('x-shine-app-token')??'';
    const userToken=request.headers.get('x-shine-user-token')??'';
    const jwt=authorization.startsWith('Bearer ')?authorization.slice('Bearer '.length):'';
    if(!appToken||(!jwt&&!userToken)){
      throw new Error('missing runtime credentials');
    }
    return {appToken,...(jwt?{jwt}:{}),...(userToken?{userToken}:{})};
  },
  authenticateIdentityClaim:async(request:Request)=>{
    const authorization=request.headers.get('authorization')??'';
    const appToken=request.headers.get('x-shine-app-token')??'';
    const sourceUserToken=request.headers.get('x-shine-user-token')??'';
    const targetJwt=authorization.startsWith('Bearer ')?authorization.slice('Bearer '.length):'';
    if(!appToken||!sourceUserToken||!targetJwt){
      throw new Error('missing identity claim credentials');
    }
    return {appToken,sourceUserToken,targetJwt};
  }
} as any);

Deno.serve((request:Request)=>handler(request));
