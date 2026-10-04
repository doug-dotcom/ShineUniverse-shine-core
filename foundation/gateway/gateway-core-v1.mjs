import {
  evaluateAccess,
  appManifestDeclaresPermission
} from '../integration-kit/permission-engine-v1.mjs';

const RESPONSE_VERSION='1.0.0';
const requestVersion=envelope=>{
  if(envelope?.gatewayRequest==='shine-foundation/gateway-request-v1' && envelope?.schemaVersion==='1.0.0') return 1;
  if(envelope?.gatewayRequest==='shine-foundation/gateway-request-v2' && envelope?.schemaVersion==='2.0.0') return 2;
  return 0;
};

const response=(envelope,status,reasonCode,decision)=>({
  gatewayResponse:'shine-foundation/gateway-response-v1',
  schemaVersion:RESPONSE_VERSION,
  traceId:envelope?.traceId??null,
  requestId:envelope?.permission?.requestId??null,
  status,
  ...(reasonCode?{reasonCode}:{}),
  ...(decision?{decision}:{})
});

const requireFunction=(adapters,name)=>{
  if(typeof adapters?.[name]!=='function') throw new TypeError('missing gateway adapter: '+name);
};

const isEnvelopeValid=envelope=>{
  const v=requestVersion(envelope);
  if(!v || envelope.operation!=='access.evaluate' || !envelope.traceId) return false;
  const p=envelope.permission;
  if(!p || !p.requestId || !p.appId || !p.scope || !p.purpose || !p.requestedAt) return false;
  if(v===1 && !p.shineId) return false;
  return Boolean(p.resourceId||p.resourceCategory);
};

const toAuditEvent=({envelope,decision,defenceEvidenceRef,occurredAt,shineId,requestContext})=>({
  event:'shine-foundation/access-audit-event-v1',
  schemaVersion:'1.0.0',
  eventId:envelope.traceId,
  requestId:envelope.permission.requestId,
  appId:envelope.permission.appId,
  shineId:shineId??null,
  scope:envelope.permission.scope,
  purpose:envelope.permission.purpose,
  ...(envelope.permission.resourceId?{resourceId:envelope.permission.resourceId}:{}),
  ...(envelope.permission.resourceCategory?{resourceCategory:envelope.permission.resourceCategory}:{}),
  decision:decision.decision,
  reasonCode:decision.reasonCode,
  ...(decision.grantId?{grantId:decision.grantId}:{}),
  occurredAt,
  ...(defenceEvidenceRef?{defenceEvidenceRef}:{}),
  ...(requestContext&&Object.keys(requestContext).length?{requestContext}:{})
});

/** @param {{adapters:any, clock?:()=>string}} [options] */
export function createFoundationGateway({adapters,clock=()=>new Date().toISOString()}={}){
  for(const name of [
    'verifyAppCaller','verifyIdentity','getAppManifest','getVaultResource',
    'getEffectiveGrants','evaluateDependencyAdmission','evaluateDefence','writeAuditEvent'
  ]) requireFunction(adapters,name);

  return async function handleFoundationRequest({envelope,authContext}={}){
    if(!isEnvelopeValid(envelope)) return response(envelope,'invalid','invalid-gateway-request');

    const permission=envelope.permission;
    const v=requestVersion(envelope);
    const now=clock();

    const persistAndRespond=async(
      decision,
      defenceEvidenceRef,
      shineId=permission.shineId??null,
      requestContext={},
      externalStatus=null
    )=>{
      try{
        await adapters.writeAuditEvent(toAuditEvent({
          envelope,decision,defenceEvidenceRef,occurredAt:now,shineId,requestContext
        }));
      }catch{
        return response(envelope,'unavailable','audit-write-failed');
      }
      if(externalStatus==='unavailable'){
        return response(envelope,'unavailable',decision.reasonCode);
      }
      return response(
        envelope,
        decision.decision==='allow'?'allowed':'denied',
        decision.reasonCode,
        {decision:decision.decision,reasonCode:decision.reasonCode}
      );
    };

    const dependencyFailure=(stage,shineId=null,requestContext={},reasonCode='foundation-dependency-unavailable')=>
      persistAndRespond({decision:'deny',reasonCode},undefined,shineId,
        {...requestContext,dependencyFailure:{stage}},'unavailable');

    let verifiedApp;
    try{
      verifiedApp=await adapters.verifyAppCaller({authContext,claimedAppId:permission.appId});
    }catch{
      return dependencyFailure('app-caller-verification');
    }

    if(!verifiedApp?.appId){
      return persistAndRespond({decision:'deny',reasonCode:'app-caller-unverified'},undefined,null);
    }
    if(verifiedApp.appId!==permission.appId){
      return persistAndRespond({decision:'deny',reasonCode:'app-caller-mismatch'},undefined,null);
    }

    let verified;
    try{
      verified=await adapters.verifyIdentity({authContext,claimedAppId:permission.appId});
    }catch{
      return dependencyFailure('identity-verification');
    }

    if(!verified?.shineId){
      return persistAndRespond({decision:'deny',reasonCode:'identity-unverified'},undefined,null);
    }
    if(v===1 && permission.shineId!==verified.shineId){
      return persistAndRespond({decision:'deny',reasonCode:'identity-mismatch'},undefined,verified.shineId);
    }
    if(v===2 && permission.shineId && permission.shineId!==verified.shineId){
      return persistAndRespond({decision:'deny',reasonCode:'identity-mismatch'},undefined,verified.shineId);
    }

    const effectiveRequest={...permission,shineId:verified.shineId};

    let manifest;
    try{
      manifest=await adapters.getAppManifest({appId:effectiveRequest.appId});
    }catch{
      return dependencyFailure('manifest-lookup',verified.shineId);
    }

    if(!manifest || manifest.appId!==effectiveRequest.appId || !appManifestDeclaresPermission(manifest,effectiveRequest)){
      const decision=evaluateAccess({
        request:effectiveRequest,
        verifiedShineId:verified.shineId,
        appManifest:manifest
      });
      return persistAndRespond(decision,undefined,verified.shineId);
    }

    let dependencyAdmission;
    try{
      dependencyAdmission=await adapters.evaluateDependencyAdmission({
        serviceId:'foundation.gateway',
        environment:'production',
        operation:envelope.operation,
        asOf:now
      });
    }catch{
      return dependencyFailure('dependency-admission',verified.shineId,{},'dependency-admission-unavailable');
    }

    const admissionContext={
      dependencyAdmission:{
        admissionState:dependencyAdmission?.admissionState??'unavailable',
        reasonCode:dependencyAdmission?.reasonCode??'dependency-admission-invalid',
        serviceId:dependencyAdmission?.serviceId??'foundation.gateway',
        environment:dependencyAdmission?.environment??'production',
        operation:dependencyAdmission?.operation??envelope.operation,
        impactScope:dependencyAdmission?.impactScope??null,
        ownState:dependencyAdmission?.ownState??null,
        effectiveState:dependencyAdmission?.effectiveState??null,
        safeMode:dependencyAdmission?.safeMode??null,
        bindingEvidenceRef:dependencyAdmission?.bindingEvidenceRef??null,
        dependencyEvidence:Array.isArray(dependencyAdmission?.dependencyEvidence)
          ?dependencyAdmission.dependencyEvidence:[]
      }
    };

    if(!dependencyAdmission?.admissionState){
      return persistAndRespond(
        {decision:'deny',reasonCode:'dependency-admission-invalid'},
        undefined,
        verified.shineId,
        admissionContext,
        'unavailable'
      );
    }

    if(dependencyAdmission.admissionState==='deny'){
      return persistAndRespond(
        {decision:'deny',reasonCode:dependencyAdmission.reasonCode??'dependency-guarded'},
        undefined,
        verified.shineId,
        admissionContext
      );
    }

    if(dependencyAdmission.admissionState==='unavailable'){
      return persistAndRespond(
        {decision:'deny',reasonCode:dependencyAdmission.reasonCode??'dependency-admission-unavailable'},
        undefined,
        verified.shineId,
        admissionContext,
        'unavailable'
      );
    }

    if(!['admit','admit-degraded'].includes(dependencyAdmission.admissionState)){
      return persistAndRespond(
        {decision:'deny',reasonCode:'dependency-admission-invalid'},
        undefined,
        verified.shineId,
        admissionContext,
        'unavailable'
      );
    }

    let resource,grants;
    try{
      [resource,grants]=await Promise.all([
        adapters.getVaultResource({
          resourceId:effectiveRequest.resourceId,
          resourceCategory:effectiveRequest.resourceCategory,
          ownerShineId:verified.shineId
        }),
        adapters.getEffectiveGrants({
          shineId:verified.shineId,
          appId:effectiveRequest.appId,
          scope:effectiveRequest.scope,
          purpose:effectiveRequest.purpose
        })
      ]);
    }catch{
      return dependencyFailure('resource-and-grant-lookup',verified.shineId,admissionContext);
    }

    // Recheck adapter ownership before passing resource metadata to Defence.
    if(resource && resource.ownerShineId!==verified.shineId){
      return persistAndRespond({decision:'deny',reasonCode:'resource-owner-mismatch'},undefined,verified.shineId,admissionContext);
    }

    let defence;
    try{
      defence=await adapters.evaluateDefence({
        envelope:{...envelope,permission:effectiveRequest},
        verifiedIdentity:verified,
        verifiedApp,
        appManifest:manifest,
        resource
      });
    }catch{
      return dependencyFailure('defence-evaluation',verified.shineId,admissionContext);
    }
    if(!['allow','deny'].includes(defence?.decision)||
       typeof defence?.evidenceRef!=='string'||!defence.evidenceRef.trim()){
      return dependencyFailure('defence-response-invalid',verified.shineId,admissionContext);
    }

    const decision=evaluateAccess({
      request:effectiveRequest,
      verifiedShineId:verified.shineId,
      appManifest:manifest,
      resource,
      grants:Array.isArray(grants)?grants:[],
      now,
      defenceDecision:defence?.decision??'not-evaluated'
    });

    return persistAndRespond(
      decision,
      defence?.evidenceRef,
      verified.shineId,
      admissionContext
    );
  };
}
