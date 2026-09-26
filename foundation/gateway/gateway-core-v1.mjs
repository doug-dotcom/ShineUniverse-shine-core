import {evaluateAccess} from '../integration-kit/permission-engine-v1.mjs';

const GATEWAY_VERSION='1.0.0';

const response=(envelope,status,reasonCode,decision)=>({
  gatewayResponse:'shine-foundation/gateway-response-v1',
  schemaVersion:GATEWAY_VERSION,
  traceId:envelope?.traceId ?? null,
  requestId:envelope?.permission?.requestId ?? null,
  status,
  ...(reasonCode ? {reasonCode} : {}),
  ...(decision ? {decision} : {})
});

const requireFunction=(adapters,name)=>{
  if(typeof adapters?.[name]!=='function') throw new TypeError('missing gateway adapter: '+name);
};

const isEnvelopeValid=envelope=>{
  if(!envelope || envelope.gatewayRequest!=='shine-foundation/gateway-request-v1') return false;
  if(envelope.schemaVersion!==GATEWAY_VERSION || envelope.operation!=='access.evaluate') return false;
  if(!envelope.traceId) return false;
  const p=envelope.permission;
  if(!p || !p.requestId || !p.appId || !p.shineId || !p.scope || !p.purpose || !p.requestedAt) return false;
  if(!p.resourceId && !p.resourceCategory) return false;
  return true;
};

const toAuditEvent=({envelope,decision,defenceEvidenceRef,occurredAt})=>({
  event:'shine-foundation/access-audit-event-v1',
  schemaVersion:'1.0.0',
  eventId:envelope.traceId,
  requestId:envelope.permission.requestId,
  appId:envelope.permission.appId,
  shineId:envelope.permission.shineId,
  scope:envelope.permission.scope,
  purpose:envelope.permission.purpose,
  ...(envelope.permission.resourceId ? {resourceId:envelope.permission.resourceId} : {}),
  ...(envelope.permission.resourceCategory ? {resourceCategory:envelope.permission.resourceCategory} : {}),
  decision:decision.decision,
  reasonCode:decision.reasonCode,
  ...(decision.grantId ? {grantId:decision.grantId} : {}),
  occurredAt,
  ...(defenceEvidenceRef ? {defenceEvidenceRef} : {})
});

export function createFoundationGateway({adapters,clock=()=>new Date().toISOString()}={}){
  for(const name of [
    'verifyIdentity',
    'getAppManifest',
    'getVaultResource',
    'getEffectiveGrants',
    'evaluateDefence',
    'writeAuditEvent'
  ]) requireFunction(adapters,name);

  return async function handleFoundationRequest({envelope,authContext}={}){
    if(!isEnvelopeValid(envelope)){
      return response(envelope,'invalid','invalid-gateway-request');
    }

    const permission=envelope.permission;
    let verified;
    let manifest;
    let resource;
    let grants;
    let defence;

    try{
      verified=await adapters.verifyIdentity({authContext,claimedShineId:permission.shineId});
      manifest=await adapters.getAppManifest({appId:permission.appId});
      resource=await adapters.getVaultResource({
        resourceId:permission.resourceId,
        resourceCategory:permission.resourceCategory,
        ownerShineId:permission.shineId
      });
      grants=await adapters.getEffectiveGrants({
        shineId:permission.shineId,
        appId:permission.appId,
        scope:permission.scope,
        purpose:permission.purpose
      });
      defence=await adapters.evaluateDefence({
        envelope,
        verifiedIdentity:verified,
        appManifest:manifest,
        resource
      });
    }catch{
      return response(envelope,'unavailable','foundation-dependency-unavailable');
    }

    const now=clock();
    const decision=evaluateAccess({
      request:permission,
      verifiedShineId:verified?.shineId,
      appManifest:manifest,
      resource,
      grants:Array.isArray(grants) ? grants : [],
      now,
      defenceDecision:defence?.decision ?? 'not-evaluated'
    });

    const audit=toAuditEvent({
      envelope,
      decision,
      defenceEvidenceRef:defence?.evidenceRef,
      occurredAt:now
    });

    try{
      await adapters.writeAuditEvent(audit);
    }catch{
      return response(envelope,'unavailable','audit-write-failed');
    }

    return response(
      envelope,
      decision.decision==='allow' ? 'allowed' : 'denied',
      decision.reasonCode,
      {decision:decision.decision,reasonCode:decision.reasonCode}
    );
  };
}
