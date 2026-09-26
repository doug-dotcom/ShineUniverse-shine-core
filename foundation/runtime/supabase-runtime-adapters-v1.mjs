const first=rows=>Array.isArray(rows)&&rows.length?rows[0]:null;

export async function sha256Hex(value){
  if(typeof value!=='string'||!value) return null;
  const digest=await crypto.subtle.digest('SHA-256',new TextEncoder().encode(value));
  return [...new Uint8Array(digest)].map(b=>b.toString(16).padStart(2,'0')).join('');
}

const decodeIssuer=jwt=>{
  try{
    const part=jwt.split('.')[1];
    if(!part) return null;
    const normalized=part.replace(/-/g,'+').replace(/_/g,'/');
    const padded=normalized+'='.repeat((4-normalized.length%4)%4);
    return JSON.parse(atob(padded))?.iss??null;
  }catch{return null}
};

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

export function createSupabaseRuntimeAdapters({
  sql,
  authClient,
  defenceGate,
  localAuthUrl,
  fetchFn=fetch
}={}){
  if(typeof sql!=='function') throw new TypeError('sql must be a Postgres.js-compatible tag');
  if(typeof authClient?.auth?.getClaims!=='function') throw new TypeError('authClient.auth.getClaims is required');
  if(typeof defenceGate!=='function') throw new TypeError('defenceGate is required');
  if(typeof fetchFn!=='function') throw new TypeError('fetchFn is required');

  return {
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

    async verifyIdentity({authContext}={}){
      const jwt=authContext?.jwt;
      if(!jwt) return null;

      const tokenIssuer=decodeIssuer(jwt);
      const localIssuer=localAuthUrl?localAuthUrl.replace(/\/$/,'')+'/auth/v1':null;

      let provider='supabase-auth';
      let subject=null;
      let sessionId;

      if(!tokenIssuer||!localIssuer||tokenIssuer===localIssuer){
        const {data,error}=await authClient.auth.getClaims(jwt);
        const claims=data?.claims;
        if(error||!claims?.sub) return null;
        subject=String(claims.sub);
        if(claims.session_id) sessionId=String(claims.session_id);
      }else{
        const issuers=await sql`
          select issuer_id, issuer_url, api_url, publishable_key
          from foundation.trusted_auth_issuers
          where issuer_url=${tokenIssuer}
            and status='active'
          limit 1
        `;
        const issuer=first(issuers);
        if(!issuer) return null;

        const response=await fetchFn(String(issuer.api_url).replace(/\/$/,'')+'/auth/v1/user',{
          headers:{
            apikey:String(issuer.publishable_key),
            Authorization:'Bearer '+jwt
          },
          signal:AbortSignal.timeout(15000)
        });
        if(!response.ok) return null;

        const user=await response.json();
        if(!user?.id) return null;
        provider=String(issuer.issuer_id);
        subject=String(user.id);
      }

      const rows=await sql`
        select b.shine_id::text as shine_id
        from foundation.identity_bindings b
        join foundation.shine_identities i on i.shine_id=b.shine_id
        where b.provider=${provider}
          and b.provider_subject=${subject}
          and b.verified_at is not null
          and i.account_state='active'
        limit 1
      `;
      const row=first(rows);
      return row?{
        shineId:String(row.shine_id),
        authSubject:subject,
        authProvider:provider,
        ...(sessionId?{sessionId}:{})
      }:null;
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
          ${event.shineId}::uuid, ${event.scope}, ${event.purpose},
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
