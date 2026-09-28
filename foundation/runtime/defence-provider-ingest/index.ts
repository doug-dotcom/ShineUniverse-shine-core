import postgres from 'npm:postgres@3.4.9';

const AUDIENCE='shine-defence-provider-ingest';
const EXPECTED_ISSUER='https://token.actions.githubusercontent.com';
const EXPECTED_REPOSITORY='doug-dotcom/ShineUniverse-shine-core';
const EXPECTED_REF='refs/heads/main';
const EXPECTED_WORKFLOW_REF='doug-dotcom/ShineUniverse-shine-core/.github/workflows/shine-defence-provider-collector.yml@refs/heads/main';
const MAX_BODY_BYTES=96*1024;
const MAX_OBSERVATIONS=50;
const encoder=new TextEncoder();
const decoder=new TextDecoder();

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

const base64urlBytes=(value:string)=>{
  const padded=value.replace(/-/g,'+').replace(/_/g,'/')+'='.repeat((4-value.length%4)%4);
  const binary=atob(padded);
  return Uint8Array.from(binary,c=>c.charCodeAt(0));
};
const parsePart=(value:string)=>JSON.parse(decoder.decode(base64urlBytes(value)));
const clean=(value:unknown,max=512)=>typeof value==='string'&&value.length>0&&value.length<=max;
const secretKey=/^(?:secret|token|password|credential|authorization|cookie|api[_-]?key|apikey)$/i;
const hasSensitiveKey=(value:unknown):boolean=>{
  if(Array.isArray(value)) return value.some(hasSensitiveKey);
  if(value&&typeof value==='object'){
    for(const [key,child] of Object.entries(value as Record<string,unknown>)){
      if(secretKey.test(key)||hasSensitiveKey(child)) return true;
    }
  }
  return false;
};

let oidcMetadataPromise:Promise<{jwks_uri:string}>|null=null;
let jwksPromise:Promise<{keys:JsonWebKey[]}>|null=null;
const getOidcMetadata=()=>oidcMetadataPromise??=(async()=>{
  const response=await fetch(EXPECTED_ISSUER+'/.well-known/openid-configuration');
  if(!response.ok) throw new Error('GitHub OIDC metadata unavailable');
  const body=await response.json();
  if(!clean(body?.jwks_uri,1024)) throw new Error('GitHub OIDC jwks_uri missing');
  return {jwks_uri:body.jwks_uri};
})();
const getJwks=()=>jwksPromise??=(async()=>{
  const metadata=await getOidcMetadata();
  const response=await fetch(metadata.jwks_uri);
  if(!response.ok) throw new Error('GitHub OIDC JWKS unavailable');
  const body=await response.json();
  if(!Array.isArray(body?.keys)) throw new Error('GitHub OIDC JWKS invalid');
  return {keys:body.keys};
})();

async function verifyGithubOidc(token:string){
  const parts=token.split('.');
  if(parts.length!==3) throw new Error('invalid OIDC token format');
  const header=parsePart(parts[0]);
  const payload=parsePart(parts[1]);
  if(header?.alg!=='RS256'||!clean(header?.kid,256)) throw new Error('unsupported OIDC signing header');

  const jwks=await getJwks();
  const jwk=jwks.keys.find((key:any)=>key.kid===header.kid);
  if(!jwk) throw new Error('OIDC signing key not found');

  const key=await crypto.subtle.importKey(
    'jwk',
    jwk,
    {name:'RSASSA-PKCS1-v1_5',hash:'SHA-256'},
    false,
    ['verify']
  );
  const ok=await crypto.subtle.verify(
    {name:'RSASSA-PKCS1-v1_5'},
    key,
    base64urlBytes(parts[2]),
    encoder.encode(parts[0]+'.'+parts[1])
  );
  if(!ok) throw new Error('OIDC signature verification failed');

  const now=Math.floor(Date.now()/1000);
  const aud=Array.isArray(payload.aud)?payload.aud:[payload.aud];
  if(payload.iss!==EXPECTED_ISSUER) throw new Error('OIDC issuer mismatch');
  if(!aud.includes(AUDIENCE)) throw new Error('OIDC audience mismatch');
  if(typeof payload.exp!=='number'||payload.exp<now-30) throw new Error('OIDC token expired');
  if(typeof payload.nbf==='number'&&payload.nbf>now+30) throw new Error('OIDC token not active');
  if(payload.repository!==EXPECTED_REPOSITORY) throw new Error('OIDC repository mismatch');
  if(payload.ref!==EXPECTED_REF) throw new Error('OIDC ref mismatch');
  if(payload.workflow_ref!==EXPECTED_WORKFLOW_REF) throw new Error('OIDC workflow mismatch');
  if(!['schedule','workflow_dispatch'].includes(String(payload.event_name))) throw new Error('OIDC event not allowed');

  return {
    repository:String(payload.repository),
    runId:String(payload.run_id??''),
    runAttempt:String(payload.run_attempt??''),
    actor:String(payload.actor??''),
    eventName:String(payload.event_name)
  };
}

type ProviderObservation={
  targetId:string;
  provider:'railway'|'supabase';
  runtimeState:'active'|'sleeping'|'transitioning'|'inactive'|'failed'|'unknown';
  healthState:'healthy'|'degraded'|'unhealthy'|'unknown';
  deploymentRef:string|null;
  versionRef:string|null;
  artifactRef:string|null;
  sourceRef:string;
  metadata:Record<string,unknown>;
};

function validateObservation(value:any):ProviderObservation{
  if(!value||typeof value!=='object') throw new Error('provider observation must be an object');
  if(!/^(?:railway|supabase):[a-z0-9][a-z0-9-]*$/.test(value.targetId||'')) throw new Error('invalid provider targetId');
  if(!['railway','supabase'].includes(value.provider)) throw new Error('invalid provider');
  if(!['active','sleeping','transitioning','inactive','failed','unknown'].includes(value.runtimeState)) throw new Error('invalid runtimeState');
  if(!['healthy','degraded','unhealthy','unknown'].includes(value.healthState)) throw new Error('invalid healthState');
  for(const key of ['deploymentRef','versionRef','artifactRef']){
    if(value[key]!==null&&value[key]!==undefined&&!clean(value[key],512)) throw new Error('invalid '+key);
  }
  if(!clean(value.sourceRef,512)) throw new Error('invalid sourceRef');
  if(!value.metadata||typeof value.metadata!=='object'||Array.isArray(value.metadata)) throw new Error('invalid metadata');
  if(JSON.stringify(value.metadata).length>8192) throw new Error('provider metadata too large');
  if(hasSensitiveKey(value.metadata)) throw new Error('sensitive provider metadata key rejected');
  return value as ProviderObservation;
}

const jsonResponse=(status:number,body:unknown)=>new Response(JSON.stringify(body),{
  status,
  headers:{'content-type':'application/json','cache-control':'no-store'}
});

Deno.serve(async(req:Request)=>{
  try{
    if(req.method!=='POST') return jsonResponse(405,{error:'method-not-allowed'});
    const length=Number(req.headers.get('content-length')||0);
    if(length>MAX_BODY_BYTES) return jsonResponse(413,{error:'body-too-large'});

    const auth=req.headers.get('authorization')||'';
    if(!auth.startsWith('Bearer ')) return jsonResponse(401,{error:'missing-oidc-token'});
    const identity=await verifyGithubOidc(auth.slice(7));

    const raw=await req.text();
    if(raw.length>MAX_BODY_BYTES) return jsonResponse(413,{error:'body-too-large'});
    const body=JSON.parse(raw);
    if(body?.contract!=='shine-defence/provider-snapshot-v1'||body?.schemaVersion!=='1.0.0') return jsonResponse(400,{error:'unsupported-provider-snapshot'});
    if(!Array.isArray(body.observations)||body.observations.length>MAX_OBSERVATIONS) return jsonResponse(400,{error:'invalid-observation-count'});
    const observations=body.observations.map(validateObservation);

    const now=new Date();
    const observedAt=now.toISOString();
    const validUntil=new Date(now.getTime()+2*60*60*1000).toISOString();
    let accepted=0;

    await rawSql.begin(async(tx:any)=>{
      await tx.unsafe('set local role shine_defence_runtime');

      for(const observation of observations){
        const targetRows=await tx`
          select provider
          from foundation.defence_estate_targets
          where target_id=${observation.targetId}
            and lifecycle='active'
        `;
        const target=targetRows[0];
        if(!target) throw new Error('unknown provider target: '+observation.targetId);
        if(target.provider!==observation.provider) throw new Error('provider mismatch for '+observation.targetId);

        const evidenceKind=observation.provider==='railway'?'railway-api':'supabase-management-api';
        await tx`
          select foundation.record_defence_estate_observation_v1(
            ${observation.targetId},
            ${observation.runtimeState},
            ${observation.healthState},
            ${observation.deploymentRef},
            ${observation.versionRef},
            ${observation.artifactRef},
            ${observedAt}::timestamptz,
            ${validUntil}::timestamptz,
            ${evidenceKind},
            ${'github-oidc:'+observation.sourceRef+':'+identity.runId+':'+identity.runAttempt},
            ${tx.json({
              ...observation.metadata,
              collector:'shine-defence/estate-provider-collector-v1',
              githubRunId:identity.runId,
              githubRunAttempt:identity.runAttempt,
              githubEvent:identity.eventName
            })}
          )
        `;
        accepted++;
      }
    });

    return jsonResponse(200,{
      status:'accepted',
      contract:'shine-defence/provider-ingest-v1',
      accepted,
      observedAt,
      validUntil
    });
  }catch(error){
    const message=error instanceof Error?error.message:'provider-ingest-error';
    const authFailure=/OIDC|oidc|repository mismatch|ref mismatch|workflow mismatch|event not allowed|missing-oidc/.test(message);
    console.error('defence-provider-ingest',message);
    return jsonResponse(authFailure?401:400,{error:authFailure?'unauthorized-provider-ingest':'provider-ingest-rejected'});
  }
});
