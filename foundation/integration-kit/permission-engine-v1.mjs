export const DENY_REASONS = Object.freeze({
  MALFORMED_REQUEST: 'malformed-request',
  IDENTITY_UNVERIFIED: 'identity-unverified',
  IDENTITY_MISMATCH: 'identity-mismatch',
  APP_UNREGISTERED: 'app-unregistered',
  SCOPE_NOT_DECLARED: 'scope-not-declared',
  RESOURCE_OWNER_MISMATCH: 'resource-owner-mismatch',
  NO_MATCHING_GRANT: 'no-matching-grant',
  GRANT_INACTIVE: 'grant-inactive',
  GRANT_NOT_YET_ACTIVE: 'grant-not-yet-active',
  GRANT_EXPIRED: 'grant-expired',
  GRANT_REVOKED: 'grant-revoked',
  SCOPE_MISMATCH: 'scope-mismatch',
  PURPOSE_MISMATCH: 'purpose-mismatch',
  RESOURCE_MISMATCH: 'resource-mismatch',
  DEFENCE_DENIED: 'defence-denied'
});

const deny=(request,reasonCode,extra={})=>({
  requestId:request?.requestId ?? null,
  decision:'deny',
  reasonCode,
  ...extra
});

const resourceMatches=(selector,request,resource)=>{
  if(!selector) return false;
  if(selector.resourceId){
    return selector.resourceId===request.resourceId && (!resource || resource.resourceId===selector.resourceId);
  }
  if(selector.resourceCategory){
    return selector.resourceCategory===(request.resourceCategory ?? resource?.category);
  }
  return false;
};

const grantTimeState=(grant,nowMs)=>{
  if(grant.status==='revoked' || grant.revokedAt) return DENY_REASONS.GRANT_REVOKED;
  if(grant.status!=='active') return DENY_REASONS.GRANT_INACTIVE;
  if(grant.notBefore && Date.parse(grant.notBefore)>nowMs) return DENY_REASONS.GRANT_NOT_YET_ACTIVE;
  if(grant.expiresAt && Date.parse(grant.expiresAt)<=nowMs) return DENY_REASONS.GRANT_EXPIRED;
  return null;
};

const manifestDeclares=(manifest,request)=>{
  if(!manifest || manifest.appId!==request.appId) return false;
  const scopes=manifest.foundation?.requestedScopes;
  if(!Array.isArray(scopes)) return false;
  return scopes.some(entry=>{
    if(entry.scope!==request.scope || entry.purpose!==request.purpose) return false;
    if(entry.resourceCategory && entry.resourceCategory!==(request.resourceCategory)) return false;
    return true;
  });
};

export function evaluateAccess({
  request,
  verifiedShineId,
  appManifest,
  resource,
  grants=[],
  now=new Date().toISOString(),
  defenceDecision='not-evaluated'
}={}){
  if(!request || !request.requestId || !request.appId || !request.shineId || !request.scope || !request.purpose){
    return deny(request,DENY_REASONS.MALFORMED_REQUEST);
  }

  if(!verifiedShineId){
    return deny(request,DENY_REASONS.IDENTITY_UNVERIFIED);
  }

  if(verifiedShineId!==request.shineId){
    return deny(request,DENY_REASONS.IDENTITY_MISMATCH);
  }

  if(!appManifest || appManifest.appId!==request.appId){
    return deny(request,DENY_REASONS.APP_UNREGISTERED);
  }

  if(!manifestDeclares(appManifest,request)){
    return deny(request,DENY_REASONS.SCOPE_NOT_DECLARED);
  }

  if(resource && resource.ownerShineId!==request.shineId){
    return deny(request,DENY_REASONS.RESOURCE_OWNER_MISMATCH);
  }

  const sameIdentityAndApp=grants.filter(g=>g.ownerShineId===request.shineId && g.appId===request.appId);
  if(!sameIdentityAndApp.length) return deny(request,DENY_REASONS.NO_MATCHING_GRANT);

  const sameScope=sameIdentityAndApp.filter(g=>g.scope===request.scope);
  if(!sameScope.length) return deny(request,DENY_REASONS.SCOPE_MISMATCH);

  const samePurpose=sameScope.filter(g=>g.purpose===request.purpose);
  if(!samePurpose.length) return deny(request,DENY_REASONS.PURPOSE_MISMATCH);

  const sameResource=samePurpose.filter(g=>resourceMatches(g.resourceSelector,request,resource));
  if(!sameResource.length) return deny(request,DENY_REASONS.RESOURCE_MISMATCH);

  const nowMs=Date.parse(now);
  if(Number.isNaN(nowMs)) return deny(request,DENY_REASONS.MALFORMED_REQUEST);

  let strongestTemporalReason=DENY_REASONS.GRANT_INACTIVE;
  const temporalRank={
    [DENY_REASONS.GRANT_REVOKED]:4,
    [DENY_REASONS.GRANT_EXPIRED]:3,
    [DENY_REASONS.GRANT_NOT_YET_ACTIVE]:2,
    [DENY_REASONS.GRANT_INACTIVE]:1
  };

  let matchedGrant=null;
  for(const grant of sameResource){
    const state=grantTimeState(grant,nowMs);
    if(!state){ matchedGrant=grant; break; }
    if(temporalRank[state]>temporalRank[strongestTemporalReason]) strongestTemporalReason=state;
  }

  if(!matchedGrant) return deny(request,strongestTemporalReason);

  if(defenceDecision==='deny'){
    return deny(request,DENY_REASONS.DEFENCE_DENIED,{grantId:matchedGrant.grantId});
  }

  return {
    requestId:request.requestId,
    decision:'allow',
    reasonCode:'grant-match',
    grantId:matchedGrant.grantId
  };
}
