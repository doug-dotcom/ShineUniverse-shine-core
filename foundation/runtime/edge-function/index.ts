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
import {createConciergePlanService,createConciergeExecuteService} from '../../gateway/concierge-orchestration-v1.mjs';
import {createIntegrationLinkRequestService,createIntegrationLinkApprovalService,createIntegrationLinkStatusService,createIntegrationLinkExchangeService,createIntegrationLinkPreviewService} from '../../gateway/integration-device-link-v1.mjs';
import {createCapabilityTicketRedeemService} from '../../gateway/capability-ticket-redeem-v2.mjs';
import {createIntegrationDelegationRefreshService} from '../../gateway/integration-delegation-refresh-v1.mjs';
import {createConnectedIntegrationListService,createUserGrantRevocationService,createUserLinkRevocationService,createUserAccessHistoryService,createUserAccessExplanationService,createUserConciergeCancellationService,createUserConciergeJobsService} from '../../gateway/user-integration-controls-v1.mjs';
import {createConciergeRetryService} from '../../gateway/concierge-retry-v1.mjs';
import {createFoundationHttpHandler} from '../../gateway/http-handler-v1.mjs';
import {createPublicDefenceStatusService} from '../../gateway/defence-status-v1.mjs';
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

const gateway=createFoundationGateway({adapters});
const identityClaim=createIdentityClaimService({adapters});
const grantConsent=createGrantConsentService({adapters});
const grantRevocation=createGrantRevocationService({adapters});
const revocationFeed=createRevocationFeedService({adapters});
const revocationAck=createRevocationAckService({adapters});
const revocationHealth=createRevocationHealthService({adapters});
const appOperationalStatus=createAppOperationalStatusService({adapters});
const capabilityDiscovery=createCapabilityDiscoveryService({adapters});
const integrationClientStatus=createIntegrationClientStatusService({adapters});
const integrationLinkConsent=createIntegrationLinkConsentService({adapters});
const integrationCapabilityConsent=createIntegrationCapabilityConsentService({adapters});
const integrationGrantRevocation=createIntegrationGrantRevocationService({adapters});
const integrationLinkRevocation=createIntegrationLinkRevocationService({adapters});
const integrationGrantList=createIntegrationGrantListService({adapters});
const conciergePlan=createConciergePlanService({adapters});
const conciergeExecute=createConciergeExecuteService({adapters});
const integrationLinkRequest=createIntegrationLinkRequestService({adapters});
const integrationLinkApproval=createIntegrationLinkApprovalService({adapters});
const integrationLinkStatus=createIntegrationLinkStatusService({adapters});
const integrationLinkExchange=createIntegrationLinkExchangeService({adapters});
const integrationLinkPreview=createIntegrationLinkPreviewService({adapters});
const capabilityTicketRedeem=createCapabilityTicketRedeemService({adapters});
const integrationDelegationRefresh=createIntegrationDelegationRefreshService({adapters});
const connectedIntegrationList=createConnectedIntegrationListService({adapters});
const userIntegrationGrantRevocation=createUserGrantRevocationService({adapters});
const userIntegrationLinkRevocation=createUserLinkRevocationService({adapters});
const userAccessHistory=createUserAccessHistoryService({adapters});
const userAccessExplanation=createUserAccessExplanationService({adapters});
const userConciergeCancellation=createUserConciergeCancellationService({adapters});
const userConciergeJobs=createUserConciergeJobsService({adapters});
const conciergeRetry=createConciergeRetryService({adapters});
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
  defenceStatus,
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
});

Deno.serve((request:Request)=>handler(request));
