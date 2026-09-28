const first=rows=>Array.isArray(rows)&&rows.length?rows[0]:null;

export async function sha256Hex(value){
  if(typeof value!=='string'||!value) return null;
  const digest=await crypto.subtle.digest('SHA-256',new TextEncoder().encode(value));
  return [...new Uint8Array(digest)].map(b=>b.toString(16).padStart(2,'0')).join('');
}

function decodeJwtPayload(jwt){
  try{
    const part=String(jwt||'').split('.')[1];
    if(!part) return null;
    const normalized=part.replace(/-/g,'+').replace(/_/g,'/');
    const padded=normalized+'='.repeat((4-normalized.length%4)%4);
    const binary=atob(padded);
    const bytes=Uint8Array.from(binary,c=>c.charCodeAt(0));
    return JSON.parse(new TextDecoder().decode(bytes));
  }catch{
    return null;
  }
}

const toIso=v=>v==null?undefined:(v instanceof Date?v.toISOString():String(v));

const mapResource=row=>row?{
  resourceId:String(row.resource_id),
  ownerShineId:String(row.owner_shine_id),
  category:String(row.category),
  sensitivity:String(row.sensitivity),
  ...(row.content_type?{contentType:String(row.content_type)}:{}),
  ...(row.storage_ref?{storageRef:String(row.storage_ref)}:{})
}:null;

const mapGrant=row=>({
  grantId:String(row.grant_id),
  ownerShineId:String(row.owner_shine_id),
  appId:String(row.app_id),
  scope:String(row.scope),
  purpose:String(row.purpose),
  resourceSelector:row.resource_id?{resourceId:String(row.resource_id)}:{resourceCategory:String(row.resource_category)},
  status:row.effective_status==='revoked'?'revoked':'active',
  issuedAt:toIso(row.issued_at),
  ...(row.not_before?{notBefore:toIso(row.not_before)}:{}),
  ...(row.expires_at?{expiresAt:toIso(row.expires_at)}:{}),
  ...(row.revoked_at?{revokedAt:toIso(row.revoked_at)}:{})
});

const sameAudit=(row,event)=>{
  const eq=(a,b)=>String(a??'')===String(b??'');
  return eq(row.app_id,event.appId)&&eq(row.shine_id,event.shineId)&&
    eq(row.scope,event.scope)&&eq(row.purpose,event.purpose)&&
    eq(row.resource_id,event.resourceId)&&eq(row.resource_category,event.resourceCategory)&&
    eq(row.decision,event.decision)&&eq(row.reason_code,event.reasonCode)&&
    eq(row.grant_id,event.grantId);
};

/** @param {{sql:any, defenceGate:any, fetchImpl?:typeof fetch}} [options] */
export function createSupabaseRuntimeAdapters({sql,defenceGate,fetchImpl=fetch}={}){
  if(typeof sql!=='function') throw new TypeError('sql must be a Postgres.js-compatible tag');
  if(typeof defenceGate!=='function') throw new TypeError('defenceGate is required');
  if(typeof fetchImpl!=='function') throw new TypeError('fetchImpl is required');

  return {
    async verifyIntegrationClient({authContext,claimedClientId}={}){
      const token=authContext?.clientToken;
      if(!token||!claimedClientId) return null;
      const tokenHash=await sha256Hex(token);
      const rows=await sql`
        select credential_id::text,client_id,client_kind
        from foundation.effective_integration_client_credentials
        where token_hash=${tokenHash}
          and effective_status='active'
        limit 1
      `;
      const row=first(rows);
      return row?{
        clientId:String(row.client_id),
        credentialId:String(row.credential_id),
        clientKind:String(row.client_kind)
      }:null;
    },

    async verifyAppCaller({authContext,claimedAppId}={}){
      const token=authContext?.appToken;
      if(!token||!claimedAppId) return null;
      const tokenHash=await sha256Hex(token);
      const rows=await sql`
        select credential_id::text, app_id
        from foundation.effective_app_credentials
        where token_hash=${tokenHash} and effective_status='active'
        limit 1
      `;
      const row=first(rows);
      return row?{appId:String(row.app_id),credentialId:String(row.credential_id)}:null;
    },

    async verifyIdentity({authContext,claimedAppId}={}){
      if(!claimedAppId) return null;

      const jwt=authContext?.jwt;
      if(jwt){
        const untrusted=decodeJwtPayload(jwt);
        if(!untrusted?.iss) return null;

        const providers=await sql`
          select p.provider_id, p.kind, p.project_url, p.publishable_key
          from foundation.identity_providers p
          join foundation.app_identity_providers a on a.provider_id=p.provider_id
          where p.kind='supabase-auth'
            and p.issuer=${String(untrusted.iss)}
            and p.status='active'
            and a.app_id=${claimedAppId}
            and a.status='active'
          limit 1
        `;
        const provider=first(providers);
        if(!provider) return null;

        const verification=await fetchImpl(String(provider.project_url).replace(/\/$/,'')+'/auth/v1/user',{
          method:'GET',
          headers:{apikey:String(provider.publishable_key),Authorization:'Bearer '+jwt},
          signal:AbortSignal.timeout(10000)
        });
        if(!verification.ok) return null;

        let user;
        try{user=await verification.json()}catch{return null}
        if(!user?.id) return null;

        const rows=await sql`
          select b.shine_id::text as shine_id
          from foundation.identity_bindings b
          join foundation.shine_identities i on i.shine_id=b.shine_id
          where b.provider=${String(provider.provider_id)}
            and b.provider_subject=${String(user.id)}
            and b.verified_at is not null
            and i.account_state='active'
          limit 1
        `;
        const row=first(rows);
        return row?{
          shineId:String(row.shine_id),
          authSubject:String(user.id),
          providerId:String(provider.provider_id),
          ...(untrusted.session_id?{sessionId:String(untrusted.session_id)}:{})
        }:null;
      }

      const userToken=authContext?.userToken;
      if(typeof userToken!=='string'||userToken.length<32||userToken.length>2048) return null;

      const providers=await sql`
        select p.provider_id,p.kind,p.project_url,p.publishable_key,
               p.verification_resource,p.subject_field,p.token_header
        from foundation.identity_providers p
        join foundation.app_identity_providers a on a.provider_id=p.provider_id
        where p.kind='supabase-opaque-vault'
          and p.status='active'
          and a.app_id=${claimedAppId}
          and a.status='active'
        limit 2
      `;
      if(!Array.isArray(providers)||providers.length!==1) return null;
      const provider=providers[0];
      const subject=await sha256Hex(userToken);
      if(!subject) return null;

      const url=new URL('/rest/v1/'+String(provider.verification_resource),String(provider.project_url));
      url.search=new URLSearchParams({
        [String(provider.subject_field)]:'eq.'+subject,
        select:String(provider.subject_field),
        limit:'1'
      }).toString();

      const verification=await fetchImpl(url,{
        method:'GET',
        headers:{
          apikey:String(provider.publishable_key),
          [String(provider.token_header)]:userToken
        },
        signal:AbortSignal.timeout(10000)
      });
      if(!verification.ok) return null;

      let verifiedRows;
      try{verifiedRows=await verification.json()}catch{return null}
      if(!Array.isArray(verifiedRows)||verifiedRows.length!==1||String(verifiedRows[0]?.[provider.subject_field])!==subject) return null;

      const bindings=await sql`
        select b.shine_id::text as shine_id
        from foundation.identity_bindings b
        join foundation.shine_identities i on i.shine_id=b.shine_id
        where b.provider=${String(provider.provider_id)}
          and b.provider_subject=${subject}
          and b.verified_at is not null
          and i.account_state='active'
        limit 1
      `;
      const row=first(bindings);
      return row?{
        shineId:String(row.shine_id),
        authSubject:subject,
        providerId:String(provider.provider_id)
      }:null;
    },
    async verifyClaimSource({appId,providerId,userToken}={}){
      if(!appId||!providerId||typeof userToken!=='string'||userToken.length<32||userToken.length>2048) return null;

      const providers=await sql`
        select p.provider_id,p.kind,p.project_url,p.publishable_key,
               p.verification_resource,p.subject_field,p.token_header
        from foundation.identity_providers p
        join foundation.app_identity_providers a on a.provider_id=p.provider_id
        where p.provider_id=${providerId}
          and p.kind='supabase-opaque-vault'
          and p.status='active'
          and a.app_id=${appId}
          and a.status='active'
        limit 1
      `;
      const provider=first(providers);
      if(!provider) return null;

      const subject=await sha256Hex(userToken);
      if(!subject) return null;

      const url=new URL('/rest/v1/'+String(provider.verification_resource),String(provider.project_url));
      url.search=new URLSearchParams({
        [String(provider.subject_field)]:'eq.'+subject,
        select:String(provider.subject_field),
        limit:'1'
      }).toString();

      const verification=await fetchImpl(url,{
        method:'GET',
        headers:{
          apikey:String(provider.publishable_key),
          [String(provider.token_header)]:userToken
        },
        signal:AbortSignal.timeout(10000)
      });
      if(!verification.ok) return null;

      let rows;
      try{rows=await verification.json()}catch{return null}
      if(!Array.isArray(rows)||rows.length!==1||String(rows[0]?.[provider.subject_field])!==subject) return null;

      return {
        providerId:String(provider.provider_id),
        authSubject:subject
      };
    },

    async verifyClaimTarget({appId,providerId,jwt}={}){
      if(!appId||!providerId||typeof jwt!=='string'||!jwt) return null;
      const untrusted=decodeJwtPayload(jwt);
      if(!untrusted?.iss) return null;

      const providers=await sql`
        select p.provider_id,p.kind,p.project_url,p.publishable_key
        from foundation.identity_providers p
        join foundation.app_claim_identity_providers c
          on c.provider_id=p.provider_id
        where p.provider_id=${providerId}
          and p.kind='supabase-auth'
          and p.issuer=${String(untrusted.iss)}
          and p.status='active'
          and c.app_id=${appId}
          and c.status='active'
        limit 1
      `;
      const provider=first(providers);
      if(!provider) return null;

      const verification=await fetchImpl(String(provider.project_url).replace(/\/$/,'')+'/auth/v1/user',{
        method:'GET',
        headers:{
          apikey:String(provider.publishable_key),
          Authorization:'Bearer '+jwt
        },
        signal:AbortSignal.timeout(10000)
      });
      if(!verification.ok) return null;

      let user;
      try{user=await verification.json()}catch{return null}
      if(!user?.id) return null;

      const bindings=await sql`
        select b.shine_id::text as shine_id
        from foundation.identity_bindings b
        join foundation.shine_identities i on i.shine_id=b.shine_id
        where b.provider=${String(provider.provider_id)}
          and b.provider_subject=${String(user.id)}
          and b.verified_at is not null
          and i.account_state='active'
        limit 1
      `;
      const row=first(bindings);
      return row?{
        providerId:String(provider.provider_id),
        authSubject:String(user.id),
        shineId:String(row.shine_id)
      }:null;
    },

    async completeIdentityClaim({
      claimId,requestId,appId,
      sourceProviderId,sourceSubject,
      targetProviderId,targetSubject,targetShineId,
      occurredAt
    }={}){
      const rows=await sql`
        select outcome,reason_code
        from foundation.complete_identity_claim_v1(
          ${claimId}::uuid,
          ${requestId}::uuid,
          ${appId},
          ${sourceProviderId},
          ${sourceSubject},
          ${targetProviderId},
          ${targetSubject},
          ${targetShineId}::uuid,
          ${occurredAt}::timestamptz
        )
      `;
      return first(rows)??null;
    },

    async issueAccessGrant({
      consentId,grantId,requestId,ownerShineId,appId,scope,purpose,
      resourceId,resourceCategory,occurredAt
    }={}){
      const rows=await sql`
        select outcome,reason_code,grant_id::text
        from foundation.issue_access_grant_v1(
          ${consentId}::uuid,
          ${grantId}::uuid,
          ${requestId}::uuid,
          ${ownerShineId}::uuid,
          ${appId},
          ${scope},
          ${purpose},
          ${resourceId??null}::uuid,
          ${resourceCategory},
          ${occurredAt}::timestamptz
        )
      `;
      return first(rows)??null;
    },

    async revokeAccessGrant({
      eventId,revocationId,requestId,grantId,ownerShineId,appId,occurredAt
    }={}){
      const rows=await sql`
        select outcome,reason_code,revocation_id::text
        from foundation.revoke_access_grant_v1(
          ${eventId}::uuid,
          ${revocationId}::uuid,
          ${requestId}::uuid,
          ${grantId}::uuid,
          ${ownerShineId}::uuid,
          ${appId},
          ${occurredAt}::timestamptz
        )
      `;
      return first(rows)??null;
    },

    async listAppRevocations({appId,afterSequence=0,limit=101}={}){
      const rows=await sql`
        select sequence_no,event_payload,created_at
        from foundation.list_app_revocations_v1(
          ${appId},
          ${afterSequence}::bigint,
          ${limit}::integer
        )
      `;
      return rows.map(row=>({
        sequenceNo:Number(row.sequence_no),
        event:row.event_payload,
        createdAt:toIso(row.created_at)
      }));
    },

    async recordAppRevocationDelivery({
      deliveryId,appId,afterSequence,sequenceNos,occurredAt
    }={}){
      const rows=await sql`
        select delivery_id::text,terminal_sequence,event_count
        from foundation.record_app_revocation_delivery_v1(
          ${deliveryId}::uuid,
          ${appId},
          ${afterSequence}::bigint,
          ${sequenceNos}::bigint[],
          ${occurredAt}::timestamptz
        )
      `;
      const row=first(rows);
      return row?{
        deliveryId:String(row.delivery_id),
        terminalSequence:Number(row.terminal_sequence),
        eventCount:Number(row.event_count)
      }:null;
    },

    async acknowledgeAppRevocations({
      ackId,requestId,deliveryId,appId,sequenceNo,occurredAt
    }={}){
      const rows=await sql`
        select outcome,reason_code,checkpoint_sequence
        from foundation.ack_app_revocations_v2(
          ${ackId}::uuid,
          ${requestId}::uuid,
          ${deliveryId}::uuid,
          ${appId},
          ${sequenceNo}::bigint,
          ${occurredAt}::timestamptz
        )
      `;
      const row=first(rows);
      return row?{
        outcome:String(row.outcome),
        reasonCode:String(row.reason_code),
        checkpointSequence:Number(row.checkpoint_sequence)
      }:null;
    },

    async getAppRevocationStatus({appId}={}){
      const rows=await sql`
        select checkpoint_sequence,last_ack_at,latest_sequence,pending_count,oldest_pending_at
        from foundation.get_app_revocation_status_v1(${appId})
      `;
      const row=first(rows);
      return row?{
        checkpointSequence:Number(row.checkpoint_sequence??0),
        lastAckAt:toIso(row.last_ack_at),
        latestSequence:Number(row.latest_sequence??0),
        pendingCount:Number(row.pending_count??0),
        oldestPendingAt:toIso(row.oldest_pending_at)
      }:null;
    },

    async getAppRevocationHealth({appId}={}){
      const rows=await sql`
        select app_id,checkpoint_sequence,latest_sequence,pending_count,
               oldest_pending_at,pending_age_seconds,max_pending_age_seconds,
               freshness_state,stale_action,recommended_action
        from foundation.get_app_revocation_health_v1(${appId})
      `;
      const row=first(rows);
      return row?{
        appId:String(row.app_id),
        checkpointSequence:Number(row.checkpoint_sequence??0),
        latestSequence:Number(row.latest_sequence??0),
        pendingCount:Number(row.pending_count??0),
        oldestPendingAt:toIso(row.oldest_pending_at),
        pendingAgeSeconds:Number(row.pending_age_seconds??0),
        maxPendingAgeSeconds:Number(row.max_pending_age_seconds??900),
        freshnessState:String(row.freshness_state),
        staleAction:String(row.stale_action),
        recommendedAction:String(row.recommended_action)
      }:null;
    },

    async listAppRevocations({appId,afterSequence=0,limit=101}={}){
      const rows=await sql`
        select sequence_no,event_payload,created_at
        from foundation.list_app_revocations_v1(
          ${appId},
          ${afterSequence}::bigint,
          ${limit}::integer
        )
      `;
      return rows.map(row=>({
        sequenceNo:Number(row.sequence_no),
        event:row.event_payload,
        createdAt:toIso(row.created_at)
      }));
    },

    async recordAppRevocationDelivery({
      deliveryId,appId,afterSequence,sequenceNos,occurredAt
    }={}){
      const rows=await sql`
        select delivery_id::text,terminal_sequence,event_count
        from foundation.record_app_revocation_delivery_v1(
          ${deliveryId}::uuid,
          ${appId},
          ${afterSequence}::bigint,
          ${sequenceNos}::bigint[],
          ${occurredAt}::timestamptz
        )
      `;
      const row=first(rows);
      return row?{
        deliveryId:String(row.delivery_id),
        terminalSequence:Number(row.terminal_sequence),
        eventCount:Number(row.event_count)
      }:null;
    },

    async acknowledgeAppRevocations({
      ackId,requestId,deliveryId,appId,sequenceNo,occurredAt
    }={}){
      const rows=await sql`
        select outcome,reason_code,checkpoint_sequence
        from foundation.ack_app_revocations_v2(
          ${ackId}::uuid,
          ${requestId}::uuid,
          ${deliveryId}::uuid,
          ${appId},
          ${sequenceNo}::bigint,
          ${occurredAt}::timestamptz
        )
      `;
      const row=first(rows);
      return row?{
        outcome:String(row.outcome),
        reasonCode:String(row.reason_code),
        checkpointSequence:Number(row.checkpoint_sequence)
      }:null;
    },

    async getAppRevocationStatus({appId}={}){
      const rows=await sql`
        select checkpoint_sequence,last_ack_at,latest_sequence,pending_count,oldest_pending_at
        from foundation.get_app_revocation_status_v1(${appId})
      `;
      const row=first(rows);
      return row?{
        checkpointSequence:Number(row.checkpoint_sequence??0),
        lastAckAt:toIso(row.last_ack_at),
        latestSequence:Number(row.latest_sequence??0),
        pendingCount:Number(row.pending_count??0),
        oldestPendingAt:toIso(row.oldest_pending_at)
      }:null;
    },

    async getAppRevocationHealth({appId}={}){
      const rows=await sql`
        select app_id,checkpoint_sequence,latest_sequence,pending_count,
               oldest_pending_at,pending_age_seconds,max_pending_age_seconds,
               freshness_state,stale_action,recommended_action
        from foundation.get_app_revocation_health_v1(${appId})
      `;
      const row=first(rows);
      return row?{
        appId:String(row.app_id),
        checkpointSequence:Number(row.checkpoint_sequence??0),
        latestSequence:Number(row.latest_sequence??0),
        pendingCount:Number(row.pending_count??0),
        oldestPendingAt:toIso(row.oldest_pending_at),
        pendingAgeSeconds:Number(row.pending_age_seconds??0),
        maxPendingAgeSeconds:Number(row.max_pending_age_seconds??900),
        freshnessState:String(row.freshness_state),
        staleAction:String(row.stale_action),
        recommendedAction:String(row.recommended_action)
      }:null;
    },

    async listDiscoverableCapabilities({appId=null}={}){
      const rows=await sql`
        select foundation.list_discoverable_capabilities_v1(${appId}) as capabilities
      `;
      return first(rows)?.capabilities??[];
    },

    async getAppOperationalStatus({appId}={}){
      const rows=await sql`
        select foundation.get_app_operational_status_v1(${appId}) as status
      `;
      return first(rows)?.status??null;
    },

    async evaluateDependencyAdmission({
      serviceId='foundation.gateway',
      environment='production',
      operation='access.evaluate',
      asOf=new Date().toISOString()
    }={}){
      if(serviceId!=='foundation.gateway') return null;
      const rows=await sql`
        select foundation.evaluate_gateway_operation_policy_v1(
          ${operation},
          ${environment},
          ${asOf}::timestamptz
        ) as policy
      `;
      const policy=first(rows)?.policy??null;
      if(!policy) return null;
      if(policy.admission&&typeof policy.admission==='object') return policy.admission;
      return {
        serviceId,
        environment,
        operation,
        impactScope:policy.impactScope??null,
        admissionState:policy.policyState??'unavailable',
        reasonCode:policy.reasonCode??'operation-policy-unavailable',
        policyEvidenceRef:policy.policyEvidenceRef??null
      };
    },

    async evaluateGatewayRoutePolicy({
      method='POST',
      path,
      environment='production',
      asOf=new Date().toISOString()
    }={}){
      if(typeof path!=='string'||!path) return null;
      const rows=await sql`
        select foundation.evaluate_gateway_route_policy_v1(
          ${method},
          ${path},
          ${environment},
          ${asOf}::timestamptz
        ) as policy
      `;
      return first(rows)?.policy??null;
    },


    async verifyIntegrationIdentity({authContext}={}){
      const jwt=authContext?.jwt;
      if(typeof jwt!=='string'||!jwt) return null;
      const untrusted=decodeJwtPayload(jwt);
      if(!untrusted?.iss) return null;

      const providers=await sql`
        select provider_id,kind,project_url,publishable_key
        from foundation.identity_providers
        where kind='supabase-auth'
          and issuer=${String(untrusted.iss)}
          and status='active'
        limit 2
      `;
      if(!Array.isArray(providers)||providers.length!==1) return null;
      const provider=providers[0];

      const verification=await fetchImpl(String(provider.project_url).replace(/\/$/,'')+'/auth/v1/user',{
        method:'GET',
        headers:{apikey:String(provider.publishable_key),Authorization:'Bearer '+jwt},
        signal:AbortSignal.timeout(10000)
      });
      if(!verification.ok) return null;

      let user;
      try{user=await verification.json()}catch{return null}
      if(!user?.id) return null;

      const rows=await sql`
        select b.shine_id::text as shine_id
        from foundation.identity_bindings b
        join foundation.shine_identities i on i.shine_id=b.shine_id
        where b.provider=${String(provider.provider_id)}
          and b.provider_subject=${String(user.id)}
          and b.verified_at is not null
          and i.account_state='active'
        limit 1
      `;
      const row=first(rows);
      return row?{
        shineId:String(row.shine_id),
        authSubject:String(user.id),
        providerId:String(provider.provider_id),
        ...(untrusted.session_id?{sessionId:String(untrusted.session_id)}:{})
      }:null;
    },

    async verifyIntegrationDelegation({authContext,claimedClientId}={}){
      const token=authContext?.delegationToken;
      if(typeof token!=='string'||!token||!claimedClientId) return null;
      const tokenHash=await sha256Hex(token);
      const rows=await sql`
        select session_id::text,link_id::text,owner_shine_id::text,client_id
        from foundation.effective_integration_delegation_sessions
        where token_hash=${tokenHash}
          and client_id=${claimedClientId}
          and effective_status='active'
        limit 1
      `;
      const row=first(rows);
      return row?{
        shineId:String(row.owner_shine_id),
        clientId:String(row.client_id),
        sessionId:String(row.session_id),
        linkId:String(row.link_id)
      }:null;
    },

    async linkIntegrationClient({eventId,linkId,requestId,ownerShineId,clientId,expiresAt,occurredAt}={}){
      const rows=await sql`
        select outcome,reason_code,link_id::text
        from foundation.link_integration_client_v1(
          ${eventId}::uuid,${linkId}::uuid,${requestId}::uuid,
          ${ownerShineId}::uuid,${clientId},${expiresAt??null}::timestamptz,${occurredAt}::timestamptz
        )
      `;
      const row=first(rows);
      return row?{outcome:String(row.outcome),reasonCode:String(row.reason_code),linkId:String(row.link_id)}:null;
    },

    async grantIntegrationClientCapability({eventId,grantId,requestId,ownerShineId,clientId,capabilityId,purpose,expiresAt,occurredAt}={}){
      const rows=await sql`
        select outcome,reason_code,grant_id::text
        from foundation.grant_integration_client_capability_v1(
          ${eventId}::uuid,${grantId}::uuid,${requestId}::uuid,
          ${ownerShineId}::uuid,${clientId},${capabilityId},${purpose},
          ${expiresAt??null}::timestamptz,${occurredAt}::timestamptz
        )
      `;
      const row=first(rows);
      return row?{outcome:String(row.outcome),reasonCode:String(row.reason_code),grantId:String(row.grant_id)}:null;
    },

    async revokeIntegrationClientGrant({eventId,revocationId,requestId,ownerShineId,clientId,grantId,occurredAt}={}){
      const rows=await sql`
        select outcome,reason_code,grant_id::text
        from foundation.revoke_integration_client_grant_v1(
          ${eventId}::uuid,${revocationId}::uuid,${requestId}::uuid,
          ${ownerShineId}::uuid,${clientId},${grantId}::uuid,${occurredAt}::timestamptz
        )
      `;
      const row=first(rows);
      return row?{outcome:String(row.outcome),reasonCode:String(row.reason_code),grantId:String(row.grant_id)}:null;
    },

    async revokeIntegrationClientLink({eventId,revocationId,requestId,ownerShineId,clientId,linkId,occurredAt}={}){
      const rows=await sql`
        select outcome,reason_code,link_id::text
        from foundation.revoke_integration_client_link_v1(
          ${eventId}::uuid,${revocationId}::uuid,${requestId}::uuid,
          ${ownerShineId}::uuid,${clientId},${linkId}::uuid,${occurredAt}::timestamptz
        )
      `;
      const row=first(rows);
      return row?{outcome:String(row.outcome),reasonCode:String(row.reason_code),linkId:String(row.link_id)}:null;
    },

    async listIntegrationClientGrants({ownerShineId,clientId}={}){
      const rows=await sql`
        select foundation.list_integration_client_grants_v1(
          ${ownerShineId}::uuid,${clientId}
        ) as grants
      `;
      return first(rows)?.grants??[];
    },

    async createIntegrationLinkRequest({requestId,clientId,purpose,requestedCapabilities,userCodeHash,exchangeSecretHash,requestedAt,expiresAt}={}){
      const rows=await sql`
        select foundation.create_integration_link_request_v1(
          ${requestId}::uuid,${clientId},${purpose},${requestedCapabilities}::text[],
          ${userCodeHash},${exchangeSecretHash},${requestedAt}::timestamptz,${expiresAt}::timestamptz
        ) as result
      `;
      return first(rows)?.result??null;
    },

    async resolveIntegrationLinkApproval({userCodeHash}={}){
      const rows=await sql`
        select foundation.resolve_integration_link_approval_v1(${userCodeHash}) as result
      `;
      return first(rows)?.result??null;
    },

    async approveIntegrationLinkRequest({eventId,linkId,requestId,ownerShineId,userCodeHash,approvedCapabilities,occurredAt}={}){
      const rows=await sql`
        select foundation.approve_integration_link_request_v1(
          ${eventId}::uuid,${linkId}::uuid,${requestId}::uuid,${ownerShineId}::uuid,
          ${userCodeHash},${approvedCapabilities}::text[],${occurredAt}::timestamptz
        ) as result
      `;
      return first(rows)?.result??null;
    },

    async getIntegrationLinkRequestStatus({requestId,clientId}={}){
      const rows=await sql`
        select foundation.get_integration_link_request_status_v1(
          ${requestId}::uuid,${clientId}
        ) as result
      `;
      return first(rows)?.result??null;
    },

    async exchangeIntegrationLinkRequest({eventId,sessionId,refreshId,requestId,clientId,exchangeSecretHash,delegationTokenHash,refreshTokenHash,sessionExpiresAt,refreshExpiresAt,occurredAt}={}){
      const rows=await sql`
        select foundation.exchange_integration_link_request_v2(
          ${eventId}::uuid,${sessionId}::uuid,${refreshId}::uuid,${requestId}::uuid,
          ${clientId},${exchangeSecretHash},${delegationTokenHash},${refreshTokenHash},
          ${sessionExpiresAt}::timestamptz,${refreshExpiresAt}::timestamptz,${occurredAt}::timestamptz
        ) as result
      `;
      return first(rows)?.result??null;
    },

    async rotateIntegrationDelegation({eventId,oldRefreshTokenHash,clientId,newRefreshId,newRefreshTokenHash,newSessionId,newDelegationHash,occurredAt,delegationExpiresAt,refreshExpiresAt}={}){
      const rows=await sql`
        select foundation.rotate_delegation_refresh_v1(
          ${eventId}::uuid,${oldRefreshTokenHash},${clientId},
          ${newRefreshId}::uuid,${newRefreshTokenHash},${newSessionId}::uuid,${newDelegationHash},
          ${occurredAt}::timestamptz,${delegationExpiresAt}::timestamptz,${refreshExpiresAt}::timestamptz
        ) as result
      `;
      return first(rows)?.result??null;
    },

    async rotateIntegrationDelegationV2({requestId,eventId,oldRefreshTokenHash,clientId,newRefreshId,newRefreshTokenHash,newSessionId,newDelegationHash,occurredAt,delegationExpiresAt,refreshExpiresAt}={}){
      const rows=await sql`
        select foundation.rotate_delegation_refresh_v2(
          ${requestId}::uuid,${eventId}::uuid,${oldRefreshTokenHash},${clientId},
          ${newRefreshId}::uuid,${newRefreshTokenHash},${newSessionId}::uuid,${newDelegationHash},
          ${occurredAt}::timestamptz,${delegationExpiresAt}::timestamptz,${refreshExpiresAt}::timestamptz
        ) as result
      `;
      return first(rows)?.result??null;
    },

    async planConciergeRequest({requestId,ownerShineId,clientId,purpose,capabilityIds,occurredAt}={}){
      const rows=await sql`
        select foundation.plan_concierge_request_v1(
          ${requestId}::uuid,${ownerShineId}::uuid,${clientId},${purpose},
          ${capabilityIds}::text[],${occurredAt}::timestamptz
        ) as plan
      `;
      return first(rows)?.plan??null;
    },

    async gateConciergeExecution({eventId,requestId,ownerShineId,clientId,occurredAt}={}){
      const rows=await sql`
        select foundation.gate_concierge_execution_v1(
          ${eventId}::uuid,${requestId}::uuid,${ownerShineId}::uuid,${clientId},${occurredAt}::timestamptz
        ) as gate
      `;
      return first(rows)?.gate??null;
    },

    async explainConciergeDenial({ownerShineId,requestId}={}){
      const rows=await sql`
        select foundation.explain_concierge_denial_v1(
          ${ownerShineId}::uuid,${requestId}::uuid
        ) as explanation
      `;
      return first(rows)?.explanation??null;
    },

    async recordConciergeExecutionEvent({eventId,requestId,ownerShineId,clientId,eventType,reasonCode,occurredAt}={}){
      await sql`
        select foundation.record_concierge_execution_event_v1(
          ${eventId}::uuid,${requestId}::uuid,${ownerShineId}::uuid,${clientId},
          ${eventType},${reasonCode},${occurredAt}::timestamptz
        )
      `;
      return {recorded:true};
    },

    async getConciergeResumeState({requestId,ownerShineId,clientId}={}){
      const rows=await sql`
        select foundation.get_concierge_resume_state_v1(
          ${requestId}::uuid,${ownerShineId}::uuid,${clientId}
        ) as state
      `;
      return first(rows)?.state??null;
    },

    async recordConciergeStepCheckpoint({checkpointId,requestId,stepId,capabilityId,result,completedAt}={}){
      const rows=await sql`
        select foundation.record_concierge_step_checkpoint_v1(
          ${checkpointId}::uuid,${requestId}::uuid,${stepId}::uuid,
          ${capabilityId},${JSON.stringify(result??{})}::jsonb,${completedAt}::timestamptz
        ) as result
      `;
      return first(rows)?.result??{recorded:true};
    },

    async queueConciergeRetry({retryJobId,eventId,requestId,ownerShineId,clientId,capabilityIds,notBefore,expiresAt,reasonCode,occurredAt}={}){
      const rows=await sql`
        select foundation.queue_concierge_retry_v1(
          ${retryJobId}::uuid,${eventId}::uuid,${requestId}::uuid,${ownerShineId}::uuid,
          ${clientId},${capabilityIds}::text[],${notBefore}::timestamptz,${expiresAt}::timestamptz,
          ${reasonCode},${occurredAt}::timestamptz
        ) as retry
      `;
      return first(rows)?.retry??null;
    },

    async claimDueConciergeRetry({eventId,claimToken,clientId,occurredAt}={}){
      const rows=await sql`
        select foundation.claim_due_concierge_retry_v1(
          ${eventId}::uuid,${claimToken}::uuid,${clientId},${occurredAt}::timestamptz
        ) as retry
      `;
      return first(rows)?.retry??null;
    },

    async finishConciergeRetry({eventId,retryJobId,claimToken,outcome,reasonCode,retryAfter,occurredAt}={}){
      const rows=await sql`
        select foundation.finish_concierge_retry_v1(
          ${eventId}::uuid,${retryJobId}::uuid,${claimToken}::uuid,
          ${outcome},${reasonCode},${retryAfter??null}::timestamptz,${occurredAt}::timestamptz
        ) as retry
      `;
      return first(rows)?.retry??null;
    },

    async getConciergeFleetStatus({ownerShineId,clientId,purpose}={}){
      const rows=await sql`
        select foundation.get_concierge_fleet_status_v1(
          ${ownerShineId}::uuid,${clientId},${purpose}
        ) as fleet
      `;
      return first(rows)?.fleet??null;
    },

    async listConnectedIntegrations({ownerShineId}={}){
      const rows=await sql`
        select foundation.list_connected_integrations_v1(${ownerShineId}::uuid) as integrations
      `;
      return first(rows)?.integrations??[];
    },

    async listUserAccessHistory({ownerShineId,limit=50,before=null}={}){
      const rows=await sql`
        select foundation.list_user_access_history_v1(
          ${ownerShineId}::uuid,${limit}::integer,${before??null}::timestamptz
        ) as history
      `;
      return first(rows)?.history??null;
    },

    async explainCapabilityAccess({ownerShineId,ticketId}={}){
      const rows=await sql`
        select foundation.explain_capability_access_v1(
          ${ownerShineId}::uuid,${ticketId}::uuid
        ) as explanation
      `;
      return first(rows)?.explanation??null;
    },

    async cancelConciergeRequest({eventId,requestId,ownerShineId,clientId,reasonCode,occurredAt}={}){
      const rows=await sql`
        select foundation.cancel_concierge_request_v1(
          ${eventId}::uuid,${requestId}::uuid,${ownerShineId}::uuid,${clientId},
          ${reasonCode},${occurredAt}::timestamptz
        ) as result
      `;
      return first(rows)?.result??null;
    },

    async listUserConciergeJobs({ownerShineId,limit=50,before=null}={}){
      const rows=await sql`
        select foundation.list_user_concierge_jobs_v3(
          ${ownerShineId}::uuid,${limit}::integer,${before??null}::timestamptz
        ) as jobs
      `;
      return first(rows)?.jobs??null;
    },

    async resolveIntegrationSubjectOwner({appId,subjectId}={}){
      const rows=await sql`
        select owner_shine_id::text
        from foundation.integration_subject_bindings
        where app_id=${appId}
          and subject_id=${subjectId}
          and status='active'
          and revoked_at is null
        order by bound_at desc
        limit 2
      `;
      if(!rows.length) return null;
      const owners=[...new Set(rows.map(r=>String(r.owner_shine_id)))];
      if(owners.length!==1) return {ambiguous:true};
      return {ownerShineId:owners[0],ambiguous:false};
    },

    async getIntegrationContextPublishEvent({requestId}={}){
      const rows=await sql`
        select snapshot_id::text,app_id,subject_id,context_kind,resource_id
        from foundation.integration_context_snapshot_events
        where request_id=${requestId}::uuid
        order by occurred_at desc
        limit 1
      `;
      const row=first(rows);
      return row?{
        snapshotId:String(row.snapshot_id),
        appId:String(row.app_id),
        subjectId:String(row.subject_id),
        contextKind:String(row.context_kind),
        resourceId:String(row.resource_id)
      }:null;
    },

    async publishIntegrationContextSnapshot({eventId,requestId,ownerShineId,appId,subjectId,contextKind,resourceId,sourceRevision,payload,sourceUpdatedAt,occurredAt}={}){
      const rows=await sql`
        select foundation.publish_integration_context_snapshot_v1(
          ${eventId}::uuid,${requestId}::uuid,${ownerShineId}::uuid,${appId},
          ${subjectId},${contextKind},${resourceId},${sourceRevision}::bigint,
          ${JSON.stringify(payload??{})}::jsonb,${sourceUpdatedAt??null}::timestamptz,${occurredAt}::timestamptz
        ) as result
      `;
      return first(rows)?.result??null;
    },

    async redeemCapabilityInvocationTicket({eventId,ticketId,stepId,capabilityId,occurredAt}={}){
      const rows=await sql`
        select foundation.consume_capability_invocation_ticket_v2(
          ${eventId}::uuid,${ticketId}::uuid,${stepId}::uuid,${capabilityId},${occurredAt}::timestamptz
        ) as result
      `;
      return first(rows)?.result??null;
    },

    async issueCapabilityInvocationTicket({conciergeRequestId,stepId,ownerShineId,clientId,occurredAt}={}){
      const ticketId=crypto.randomUUID();
      const expiresAt=new Date(Date.parse(occurredAt)+60*1000).toISOString();
      const rows=await sql`
        select foundation.issue_capability_invocation_ticket_v2(
          ${ticketId}::uuid,${conciergeRequestId}::uuid,${stepId}::uuid,
          ${ownerShineId}::uuid,${clientId},${expiresAt}::timestamptz,${occurredAt}::timestamptz
        ) as ticket
      `;
      return first(rows)?.ticket??null;
    },

    async getCapabilityAdapterHealth({capabilityId}={}){
      const rows=await sql`
        select capability_id,health_status,retry_after,last_outcome,failures_in_last_3
        from foundation.capability_adapter_health
        where capability_id=${capabilityId}
        limit 1
      `;
      return first(rows)??{
        capability_id:capabilityId,
        health_status:'available',
        retry_after:null,
        last_outcome:'unknown',
        failures_in_last_3:0
      };
    },

    async recordCapabilityAdapterHealth({eventId,capabilityId,outcome,reasonCode,latencyMs=null,occurredAt}={}){
      await sql`
        select foundation.record_capability_adapter_health_v1(
          ${eventId}::uuid,${capabilityId},${outcome},${reasonCode},
          ${latencyMs}::integer,${occurredAt}::timestamptz
        )
      `;
      return {recorded:true};
    },

    async invokeCapability({capabilityId,requestId,input,context}={}){
      const rows=await sql`
        select
          a.endpoint_url,a.adapter_protocol,a.auth_mode,a.timeout_ms,a.status,a.effective_status,
          c.invocation_state,c.capability_mode
        from foundation.effective_capability_invocation_adapters a
        join foundation.app_capabilities c on c.capability_id=a.capability_id
        where a.capability_id=${capabilityId}
        limit 1
      `;
      const adapter=first(rows);
      if(!adapter||adapter.status!=='active'||adapter.invocation_state!=='live'){
        return {status:'failed',reasonCode:'capability-adapter-not-live'};
      }
      if(adapter.effective_status!=='active'){
        return {status:'failed',reasonCode:'capability-adapter-attestation-mismatch',adapterStatus:adapter.effective_status};
      }
      const health=await this.getCapabilityAdapterHealth({capabilityId});
      if(health?.health_status==='quarantined'){
        return {status:'failed',reasonCode:'capability-adapter-quarantined',retryAfter:health.retry_after??null};
      }
      if(!['read','advisory'].includes(String(adapter.capability_mode))){
        return {status:'failed',reasonCode:'capability-mode-not-supported'};
      }
      if(adapter.adapter_protocol!=='shine-capability/v1'||adapter.auth_mode!=='one-time-foundation-ticket'){
        return {status:'failed',reasonCode:'capability-adapter-unsupported'};
      }

      const conciergeRequestId=String(context?.conciergeRequestId??'');
      const ownerShineId=String(context?.ownerShineId??'');
      const clientId=String(context?.clientId??'');
      if(!conciergeRequestId||!ownerShineId||!clientId){
        return {status:'failed',reasonCode:'capability-invocation-context-missing'};
      }

      let ticket;
      try{
        ticket=await this.issueCapabilityInvocationTicket({
          conciergeRequestId,stepId:requestId,ownerShineId,clientId,occurredAt:new Date().toISOString()
        });
      }catch{
        return {status:'failed',reasonCode:'capability-ticket-issue-failed'};
      }
      if(!ticket?.ticketId) return {status:'failed',reasonCode:'capability-ticket-issue-failed'};

      let response;
      const startedAt=Date.now();
      try{
        response=await fetchImpl(String(adapter.endpoint_url),{
          method:'POST',
          headers:{'content-type':'application/json'},
          body:JSON.stringify({
            protocol:'shine-capability/v1',schemaVersion:'1.0.0',requestId,capabilityId,
            input:input&&typeof input==='object'&&!Array.isArray(input)?input:{},
            context:{
              ticketId:String(ticket.ticketId),stepId:requestId,conciergeRequestId,
              purpose:String(context?.purpose??'')
            }
          }),
          signal:AbortSignal.timeout(Number(adapter.timeout_ms)||15000)
        });
      }catch{
        try{await this.recordCapabilityAdapterHealth({
          eventId:crypto.randomUUID(),capabilityId,outcome:'failure',
          reasonCode:'capability-endpoint-unavailable',
          latencyMs:Math.max(0,Date.now()-startedAt),occurredAt:new Date().toISOString()
        })}catch{}
        return {status:'failed',reasonCode:'capability-endpoint-unavailable'};
      }

      let payload;
      try{payload=await response.json()}catch{
        try{await this.recordCapabilityAdapterHealth({
          eventId:crypto.randomUUID(),capabilityId,outcome:'failure',
          reasonCode:'capability-response-invalid',
          latencyMs:Math.max(0,Date.now()-startedAt),occurredAt:new Date().toISOString()
        })}catch{}
        return {status:'failed',reasonCode:'capability-response-invalid'};
      }
      if(!response.ok){
        try{await this.recordCapabilityAdapterHealth({
          eventId:crypto.randomUUID(),capabilityId,outcome:'failure',
          reasonCode:'capability-endpoint-rejected',
          latencyMs:Math.max(0,Date.now()-startedAt),occurredAt:new Date().toISOString()
        })}catch{}
        return {status:'failed',reasonCode:'capability-endpoint-rejected',httpStatus:response.status,error:payload?.error??null};
      }
      if(payload?.protocol!=='shine-capability-result/v1'||payload?.schemaVersion!=='1.0.0'||
         payload?.requestId!==requestId||payload?.capabilityId!==capabilityId||
         payload?.status!=='completed'||!payload?.result||typeof payload.result!=='object'||Array.isArray(payload.result)){
        try{await this.recordCapabilityAdapterHealth({
          eventId:crypto.randomUUID(),capabilityId,outcome:'failure',
          reasonCode:'capability-response-invalid',
          latencyMs:Math.max(0,Date.now()-startedAt),occurredAt:new Date().toISOString()
        })}catch{}
        return {status:'failed',reasonCode:'capability-response-invalid'};
      }
      try{await this.recordCapabilityAdapterHealth({
        eventId:crypto.randomUUID(),capabilityId,outcome:'success',
        reasonCode:'capability-completed',
        latencyMs:Math.max(0,Date.now()-startedAt),occurredAt:new Date().toISOString()
      })}catch{}
      return {status:'completed',reasonCode:'capability-completed',result:payload.result};
    },

    async getAppManifest({appId}={}){
      const rows=await sql`
        select manifest from foundation.app_registry
        where app_id=${appId} and status='active' limit 1
      `;
      return first(rows)?.manifest??null;
    },

    async getVaultResource({resourceId,resourceCategory,ownerShineId}={}){
      const rows=resourceId
        ? await sql`
            select resource_id::text, owner_shine_id::text, category, sensitivity, content_type, storage_ref
            from foundation.vault_resources where resource_id=${resourceId}::uuid limit 1
          `
        : await sql`
            select resource_id::text, owner_shine_id::text, category, sensitivity, content_type, storage_ref
            from foundation.vault_resources
            where owner_shine_id=${ownerShineId}::uuid and category=${resourceCategory}
            order by created_at desc limit 1
          `;
      return mapResource(first(rows));
    },

    async getEffectiveGrants({shineId,appId,scope,purpose}={}){
      const rows=await sql`
        select grant_id::text, owner_shine_id::text, app_id, scope, purpose,
               resource_id::text, resource_category, effective_status,
               issued_at, not_before, expires_at, revoked_at
        from foundation.effective_access_grants
        where owner_shine_id=${shineId}::uuid
          and app_id=${appId} and scope=${scope} and purpose=${purpose}
        order by issued_at desc
      `;
      return rows.map(mapGrant);
    },

    async evaluateDefence(args){ return defenceGate(args); },

    async writeAuditEvent(event){
      const inserted=await sql`
        insert into foundation.access_audit_events(
          event_id, request_id, app_id, shine_id, scope, purpose,
          resource_id, resource_category, decision, reason_code,
          grant_id, occurred_at, defence_evidence_ref, request_context
        ) values (
          ${event.eventId}::uuid, ${event.requestId}::uuid, ${event.appId},
          ${event.shineId??null}::uuid, ${event.scope}, ${event.purpose},
          ${event.resourceId??null}::uuid, ${event.resourceCategory??null},
          ${event.decision}, ${event.reasonCode}, ${event.grantId??null}::uuid,
          ${event.occurredAt}::timestamptz, ${event.defenceEvidenceRef??null},
          ${JSON.stringify(event.requestContext??{})}::jsonb
        )
        on conflict (request_id) do nothing
        returning request_id::text
      `;
      if(inserted.length) return {inserted:true};

      const existing=await sql`
        select app_id, shine_id::text, scope, purpose, resource_id::text,
               resource_category, decision, reason_code, grant_id::text
        from foundation.access_audit_events
        where request_id=${event.requestId}::uuid limit 1
      `;
      const row=first(existing);
      if(!row||!sameAudit(row,event)) throw new Error('audit-replay-conflict');
      return {inserted:false,replayed:true};
    }
  };
}
