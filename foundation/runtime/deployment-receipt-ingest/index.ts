import postgres from 'npm:postgres@3.4.9';

const AUDIENCE='shine-foundation-deployment-receipt';
const EXPECTED_ISSUER='https://token.actions.githubusercontent.com';
const EXPECTED_REPOSITORY='doug-dotcom/ShineUniverse-shine-core';
const EXPECTED_REF='refs/heads/main';
const EXPECTED_WORKFLOW_REF='doug-dotcom/ShineUniverse-shine-core/.github/workflows/publish-foundation-deployment-receipt.yml@refs/heads/main';
const MAX_BODY_BYTES=32*1024;
const encoder=new TextEncoder();
const decoder=new TextDecoder();

const requireEnv=(name:string)=>{
  const value=Deno.env.get(name);
  if(!value) throw new Error('Missing required environment variable: '+name);
  return value;
};

const sql=postgres(requireEnv('SUPABASE_DB_URL'),{
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
const clean=(value:unknown,max=1024)=>typeof value==='string'&&value.length>0&&value.length<=max&&!/[\u0000-\u001f\u007f]/.test(value);
const sha40=(value:unknown)=>typeof value==='string'&&/^[a-f0-9]{40}$/i.test(value);
const sha64=(value:unknown)=>typeof value==='string'&&/^[a-f0-9]{64}$/i.test(value);

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
    'jwk',jwk,{name:'RSASSA-PKCS1-v1_5',hash:'SHA-256'},false,['verify']
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
  if(String(payload.repository)!==EXPECTED_REPOSITORY) throw new Error('OIDC repository mismatch');
  if(String(payload.ref)!==EXPECTED_REF) throw new Error('OIDC ref mismatch');
  if(String(payload.workflow_ref)!==EXPECTED_WORKFLOW_REF) throw new Error('OIDC workflow mismatch');
  if(!['push','workflow_dispatch'].includes(String(payload.event_name))) throw new Error('OIDC event not allowed');

  return {
    runId:String(payload.run_id??''),
    runAttempt:String(payload.run_attempt??''),
    eventName:String(payload.event_name),
    actor:String(payload.actor??''),
    repository:String(payload.repository),
    ref:String(payload.ref),
    workflowRef:String(payload.workflow_ref),
    workflowSha:String(payload.sha??'')
  };
}

const jsonResponse=(status:number,body:unknown)=>new Response(JSON.stringify(body),{
  status,
  headers:{'content-type':'application/json','cache-control':'no-store'}
});

Deno.serve(async(req:Request)=>{
  try{
    if(req.method!=='POST') return jsonResponse(405,{error:'method-not-allowed'});

    const declaredLength=Number(req.headers.get('content-length')||0);
    if(declaredLength>MAX_BODY_BYTES) return jsonResponse(413,{error:'body-too-large'});

    const auth=req.headers.get('authorization')??'';
    if(!auth.startsWith('Bearer ')) return jsonResponse(401,{error:'missing-oidc-token'});
    const identity=await verifyGithubOidc(auth.slice(7));

    const raw=await req.text();
    if(raw.length>MAX_BODY_BYTES) return jsonResponse(413,{error:'body-too-large'});
    const body=JSON.parse(raw||'{}');

    if(body?.contract!=='shine-foundation/deployment-receipt-publish-v1'||body?.schemaVersion!=='1.0.0'){
      return jsonResponse(400,{error:'unsupported-deployment-receipt'});
    }

    const receipt=body?.receipt;
    if(
      !receipt||
      !clean(receipt.runtimeVersion,128)||
      !/^\d+$/.test(receipt.runtimeVersion)||
      !sha64(receipt.artifactSha256)||
      !['active','inactive','failed'].includes(receipt.runtimeState)||
      !sha40(receipt.sourceCommit)||
      !clean(receipt.providerEvidenceRef,1000)||
      !clean(receipt.providerObservedAt,64)||
      Number.isNaN(Date.parse(receipt.providerObservedAt))||
      typeof receipt.rollback!=='boolean'
    ){
      return jsonResponse(400,{error:'invalid-deployment-receipt'});
    }

    const rows=await sql\`
      select foundation.submit_service_deployment_receipt_v1(
        'foundation.gateway',
        'production',
        'supabase-edge',
        'supabase://sjpxqeyewahraxvidvcc/functions/foundation-gateway',
        \${receipt.runtimeVersion},
        \${String(receipt.artifactSha256).toLowerCase()},
        \${receipt.runtimeState},
        \${'github://doug-dotcom/ShineUniverse-shine-core/commit/'+String(receipt.sourceCommit).toLowerCase()},
        \${receipt.providerEvidenceRef},
        \${new Date(receipt.providerObservedAt).toISOString()}::timestamptz,
        'github-actions-oidc',
        \${sql.json({
          transport:'github-oidc',
          githubRunId:identity.runId,
          githubRunAttempt:identity.runAttempt,
          githubEvent:identity.eventName,
          githubActor:identity.actor,
          githubRepository:identity.repository,
          githubRef:identity.ref,
          githubWorkflowRef:identity.workflowRef,
          githubWorkflowSha:identity.workflowSha,
          rollback:receipt.rollback
        })}
      ) as result
    \`;

    const result=rows[0]?.result??null;
    if(!result) return jsonResponse(500,{error:'deployment-receipt-result-missing'});

    const statusRows=await sql\`
      select foundation.get_deployment_reconciliation_status_v1(
        'foundation.gateway','production'
      ) as status
    \`;

    return jsonResponse(200,{
      status:'accepted',
      contract:'shine-foundation/deployment-receipt-ingest-v1',
      receipt:result,
      reconciliation:statusRows[0]?.status??null
    });
  }catch(error){
    const message=error instanceof Error?error.message:'deployment-receipt-ingest-error';
    const authFailure=/OIDC|oidc|repository mismatch|ref mismatch|workflow mismatch|event not allowed|missing-oidc/.test(message);
    console.error('foundation-deployment-receipt-ingest',message);
    return jsonResponse(authFailure?401:400,{
      error:authFailure?'unauthorized-deployment-receipt':'deployment-receipt-rejected'
    });
  }
});
