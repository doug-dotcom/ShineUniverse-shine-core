import postgres from 'npm:postgres@3.4.9';

const CONTRACT='shine-defence/external-dispatcher-readiness-trigger-v1';
const API_VERSION='2026-03-10';
const MAX_BODY_BYTES=16*1024;
const UUID=/^[a-f0-9]{8}-[a-f0-9]{4}-[1-5][a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/i;
const TOKEN=/^[a-f0-9]{64}$/;
const NUMERIC_ID=/^[0-9]{1,20}$/;

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

const jsonResponse=(status:number,body:unknown)=>new Response(JSON.stringify(body),{
  status,
  headers:{'content-type':'application/json','cache-control':'no-store'}
});

const base64url=(bytes:Uint8Array)=>{
  let binary='';
  for(const byte of bytes) binary+=String.fromCharCode(byte);
  return btoa(binary).replace(/=/g,'').replace(/\+/g,'-').replace(/\//g,'_');
};

const base64urlText=(value:string)=>base64url(new TextEncoder().encode(value));

const pemPkcs8Bytes=(pem:string)=>{
  const normalized=pem.replace(/\\n/g,'\n').trim();
  const match=normalized.match(
    /^-----BEGIN PRIVATE KEY-----\s*([A-Za-z0-9+/=\s]+)\s*-----END PRIVATE KEY-----$/
  );
  if(!match) throw new Error('github-app-private-key-must-be-pkcs8');
  const binary=atob(match[1].replace(/\s+/g,''));
  return Uint8Array.from(binary,c=>c.charCodeAt(0));
};

async function createGithubAppJwt(appId:string,privateKeyPkcs8:string){
  if(!NUMERIC_ID.test(appId)) throw new Error('github-app-id-invalid');
  const now=Math.floor(Date.now()/1000);
  const header=base64urlText(JSON.stringify({alg:'RS256',typ:'JWT'}));
  const payload=base64urlText(JSON.stringify({
    iat:now-60,
    exp:now+540,
    iss:appId
  }));
  const unsigned=header+'.'+payload;
  const key=await crypto.subtle.importKey(
    'pkcs8',
    pemPkcs8Bytes(privateKeyPkcs8),
    {name:'RSASSA-PKCS1-v1_5',hash:'SHA-256'},
    false,
    ['sign']
  );
  const signature=await crypto.subtle.sign(
    {name:'RSASSA-PKCS1-v1_5'},
    key,
    new TextEncoder().encode(unsigned)
  );
  return unsigned+'.'+base64url(new Uint8Array(signature));
}

type RequiredRepo={
  targetId:string;
  repository:string;
  repositoryId:string;
};

async function githubJson(url:string,token:string){
  const response=await fetch(url,{
    redirect:'error',
    headers:{
      'Accept':'application/vnd.github+json',
      'Authorization':'Bearer '+token,
      'X-GitHub-Api-Version':API_VERSION,
      'User-Agent':'Shine-Defence-Dispatcher-Readiness/1.0'
    }
  });
  const text=await response.text();
  let body:any=null;
  try{body=text?JSON.parse(text):null}catch{}
  return {response,body};
}

async function claimLease(leaseId:string,leaseToken:string,executionId:string){
  const rows=await sql`
    select foundation.claim_defence_external_dispatcher_readiness_lease_v1(
      ${leaseId}::uuid,
      ${leaseToken},
      ${executionId},
      now()
    ) as claim
  `;
  return rows[0]?.claim??null;
}

async function requiredRepositories():Promise<RequiredRepo[]>{
  const rows=await sql`
    select foundation.get_defence_external_dispatcher_required_repositories_v1()
      as required
  `;
  const required=rows[0]?.required;
  if(
    !required||
    required.contract!=='shine-defence/external-dispatcher-required-repositories-v1'||
    !Array.isArray(required.repositories)||
    required.repositories.length<1||
    required.repositories.length>100
  ){
    throw new Error('dispatcher-required-repositories-invalid');
  }
  const repos=required.repositories.map((x:any)=>({
    targetId:String(x.targetId||''),
    repository:String(x.repository||''),
    repositoryId:String(x.repositoryId||'')
  }));
  if(repos.some((x:RequiredRepo)=>
    !NUMERIC_ID.test(x.repositoryId)||
    !/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(x.repository)
  )){
    throw new Error('dispatcher-required-repository-entry-invalid');
  }
  return repos;
}

async function recordReadiness(args:{
  executionId:string;
  appId:string|null;
  installationId:string|null;
  credentialsPresent:boolean;
  appIdentityVerified:boolean;
  installationTokenIssued:boolean;
  actionsWriteConfirmed:boolean;
  repositoryCoverageComplete:boolean;
  requiredCount:number;
  coveredCount:number;
  missingRepositoryIds:string[];
  outcome:string;
  tokenExpiresAt:string|null;
  metadata:any;
}){
  const validUntil=new Date(Date.now()+60*60*1000).toISOString();
  const rows=await sql`
    select foundation.record_defence_external_dispatcher_readiness_v1(
      gen_random_uuid(),
      ${args.appId},
      ${args.installationId},
      ${args.credentialsPresent},
      ${args.appIdentityVerified},
      ${args.installationTokenIssued},
      ${args.actionsWriteConfirmed},
      ${args.repositoryCoverageComplete},
      ${args.requiredCount},
      ${args.coveredCount},
      ${sql.json(args.missingRepositoryIds)},
      ${args.outcome},
      ${args.tokenExpiresAt}::timestamptz,
      now(),
      ${validUntil}::timestamptz,
      ${'external-dispatcher-readiness:'+args.executionId},
      ${sql.json(args.metadata)}
    ) as result
  `;
  return rows[0]?.result??null;
}

async function revokeInstallationToken(token:string){
  const response=await fetch('https://api.github.com/installation/token',{
    method:'DELETE',
    redirect:'error',
    headers:{
      'Accept':'application/vnd.github+json',
      'Authorization':'Bearer '+token,
      'X-GitHub-Api-Version':API_VERSION,
      'User-Agent':'Shine-Defence-Dispatcher-Readiness/1.0'
    }
  });
  return response.status===204;
}

Deno.serve(async(req:Request)=>{
  const executionId=Deno.env.get('SB_EXECUTION_ID')||crypto.randomUUID();
  let leaseAccepted=false;
  let installationToken:string|null=null;

  try{
    if(req.method!=='POST') return jsonResponse(405,{error:'method-not-allowed'});
    const contentLength=Number(req.headers.get('content-length')||0);
    if(contentLength>MAX_BODY_BYTES) return jsonResponse(413,{error:'body-too-large'});

    const raw=await req.text();
    if(raw.length>MAX_BODY_BYTES) return jsonResponse(413,{error:'body-too-large'});
    const body=JSON.parse(raw||'{}');

    if(
      body?.contract!==CONTRACT||
      body?.schemaVersion!=='1.0.0'||
      !UUID.test(String(body?.leaseId??''))||
      !TOKEN.test(String(body?.leaseToken??''))
    ){
      return jsonResponse(400,{error:'invalid-dispatcher-readiness-trigger'});
    }

    const claim=await claimLease(
      String(body.leaseId),
      String(body.leaseToken),
      executionId
    );
    if(claim?.status!=='accepted'){
      return jsonResponse(401,{error:'dispatcher-readiness-lease-rejected'});
    }
    leaseAccepted=true;

    const required=await requiredRepositories();
    const requiredIds=new Set(required.map(x=>x.repositoryId));

    const appId=Deno.env.get('SHINE_DEFENCE_GITHUB_APP_ID')||'';
    const installationId=
      Deno.env.get('SHINE_DEFENCE_GITHUB_APP_INSTALLATION_ID')||'';
    const privateKey=
      Deno.env.get('SHINE_DEFENCE_GITHUB_APP_PRIVATE_KEY_PKCS8')||'';

    const credentialsPresent=
      NUMERIC_ID.test(appId)&&
      NUMERIC_ID.test(installationId)&&
      privateKey.includes('BEGIN PRIVATE KEY');

    const baseMetadata={
      collector:'shine-defence/external-dispatcher-activation-readiness-v1',
      credentialValueExposed:false,
      appJwtStored:false,
      installationTokenStored:false,
      readinessCheckDispatchesWorkflow:false,
      workflowOidcRemainsAuthoritative:true,
      requiredRepositoryCount:required.length
    };

    if(!credentialsPresent){
      const result=await recordReadiness({
        executionId,
        appId:NUMERIC_ID.test(appId)?appId:null,
        installationId:NUMERIC_ID.test(installationId)?installationId:null,
        credentialsPresent:false,
        appIdentityVerified:false,
        installationTokenIssued:false,
        actionsWriteConfirmed:false,
        repositoryCoverageComplete:false,
        requiredCount:required.length,
        coveredCount:0,
        missingRepositoryIds:[...requiredIds],
        outcome:'missing_credentials',
        tokenExpiresAt:null,
        metadata:{
          ...baseMetadata,
          githubAppIdPresent:Boolean(appId),
          githubInstallationIdPresent:Boolean(installationId),
          githubPrivateKeyPresent:Boolean(privateKey),
          workflowAccessComplete:false
        }
      });
      return jsonResponse(200,{
        status:'not_configured',
        contract:'shine-defence/external-dispatcher-activation-readiness-v1',
        requiredRepositoryCount:required.length,
        result
      });
    }

    let appJwt:string;
    try{
      appJwt=await createGithubAppJwt(appId,privateKey);
    }catch(error){
      const result=await recordReadiness({
        executionId,
        appId,
        installationId,
        credentialsPresent:true,
        appIdentityVerified:false,
        installationTokenIssued:false,
        actionsWriteConfirmed:false,
        repositoryCoverageComplete:false,
        requiredCount:required.length,
        coveredCount:0,
        missingRepositoryIds:[...requiredIds],
        outcome:'invalid_app_identity',
        tokenExpiresAt:null,
        metadata:{
          ...baseMetadata,
          reasonCode:error instanceof Error?error.message:'app-jwt-sign-failed',
          workflowAccessComplete:false
        }
      });
      return jsonResponse(200,{status:'blocked',reasonCode:'invalid_app_identity',result});
    }

    const appCheck=await githubJson('https://api.github.com/app',appJwt);
    const appIdentityVerified=
      appCheck.response.ok&&
      String(appCheck.body?.id??'')===appId;

    if(!appIdentityVerified){
      const result=await recordReadiness({
        executionId,
        appId,
        installationId,
        credentialsPresent:true,
        appIdentityVerified:false,
        installationTokenIssued:false,
        actionsWriteConfirmed:false,
        repositoryCoverageComplete:false,
        requiredCount:required.length,
        coveredCount:0,
        missingRepositoryIds:[...requiredIds],
        outcome:'invalid_app_identity',
        tokenExpiresAt:null,
        metadata:{
          ...baseMetadata,
          appHttpStatus:appCheck.response.status,
          observedAppId:appCheck.body?.id?String(appCheck.body.id):null,
          workflowAccessComplete:false
        }
      });
      return jsonResponse(200,{status:'blocked',reasonCode:'invalid_app_identity',result});
    }

    const tokenResponse=await fetch(
      'https://api.github.com/app/installations/'+installationId+'/access_tokens',
      {
        method:'POST',
        redirect:'error',
        headers:{
          'Accept':'application/vnd.github+json',
          'Authorization':'Bearer '+appJwt,
          'X-GitHub-Api-Version':API_VERSION,
          'Content-Type':'application/json',
          'User-Agent':'Shine-Defence-Dispatcher-Readiness/1.0'
        },
        body:JSON.stringify({permissions:{actions:'write'}})
      }
    );
    const tokenText=await tokenResponse.text();
    let tokenBody:any=null;
    try{tokenBody=tokenText?JSON.parse(tokenText):null}catch{}

    if(!tokenResponse.ok||!tokenBody?.token){
      const result=await recordReadiness({
        executionId,
        appId,
        installationId,
        credentialsPresent:true,
        appIdentityVerified:true,
        installationTokenIssued:false,
        actionsWriteConfirmed:false,
        repositoryCoverageComplete:false,
        requiredCount:required.length,
        coveredCount:0,
        missingRepositoryIds:[...requiredIds],
        outcome:'installation_token_failed',
        tokenExpiresAt:null,
        metadata:{
          ...baseMetadata,
          tokenHttpStatus:tokenResponse.status,
          workflowAccessComplete:false
        }
      });
      return jsonResponse(200,{status:'blocked',reasonCode:'installation_token_failed',result});
    }

    installationToken=String(tokenBody.token);
    const tokenExpiresAt=
      typeof tokenBody.expires_at==='string'?tokenBody.expires_at:null;
    const actionsWriteConfirmed=
      String(tokenBody.permissions?.actions??'')==='write';

    const reposCheck=await githubJson(
      'https://api.github.com/installation/repositories?per_page=100',
      installationToken
    );
    const accessibleRepos=Array.isArray(reposCheck.body?.repositories)
      ?reposCheck.body.repositories
      :[];
    const accessibleIds=new Set(
      accessibleRepos.map((x:any)=>String(x?.id??'')).filter((x:string)=>NUMERIC_ID.test(x))
    );
    const missingRepositoryIds=[
      ...requiredIds
    ].filter(id=>!accessibleIds.has(id));
    const coveredCount=required.length-missingRepositoryIds.length;
    const repositoryCoverageComplete=
      reposCheck.response.ok&&missingRepositoryIds.length===0;

    const workflowChecks=await Promise.all(required.map(async item=>{
      const [owner,name]=item.repository.split('/');
      const workflow=
        item.targetId==='core'
          ?'shine-defence-authority-state.yml'
          :'shine-defence-release-head.yml';
      const check=await githubJson(
        'https://api.github.com/repos/'+encodeURIComponent(owner)+'/'+
        encodeURIComponent(name)+'/actions/workflows/'+encodeURIComponent(workflow),
        installationToken!
      );
      return {
        targetId:item.targetId,
        repository:item.repository,
        workflow,
        accessible:check.response.ok,
        httpStatus:check.response.status
      };
    }));
    const workflowAccessComplete=workflowChecks.every(x=>x.accessible);
    const inaccessibleWorkflows=workflowChecks.filter(x=>!x.accessible);

    let outcome='ready';
    if(!actionsWriteConfirmed) outcome='permission_gap';
    else if(!repositoryCoverageComplete||!workflowAccessComplete) outcome='repository_gap';

    const revoked=await revokeInstallationToken(installationToken);
    installationToken=null;

    const result=await recordReadiness({
      executionId,
      appId,
      installationId,
      credentialsPresent:true,
      appIdentityVerified:true,
      installationTokenIssued:true,
      actionsWriteConfirmed,
      repositoryCoverageComplete,
      requiredCount:required.length,
      coveredCount,
      missingRepositoryIds,
      outcome,
      tokenExpiresAt,
      metadata:{
        ...baseMetadata,
        tokenHttpStatus:tokenResponse.status,
        repositoriesHttpStatus:reposCheck.response.status,
        workflowAccessComplete,
        inaccessibleWorkflows,
        installationTokenRevoked:revoked,
        installationTokenStored:false,
        appJwtStored:false
      }
    });

    return jsonResponse(200,{
      status:outcome==='ready'?'ready':'blocked',
      contract:'shine-defence/external-dispatcher-activation-readiness-v1',
      outcome,
      requiredRepositoryCount:required.length,
      coveredRepositoryCount:coveredCount,
      actionsWriteConfirmed,
      repositoryCoverageComplete,
      workflowAccessComplete,
      missingRepositoryIds,
      inaccessibleWorkflows,
      installationTokenRevoked:revoked,
      result
    });
  }catch(error){
    if(installationToken){
      try{await revokeInstallationToken(installationToken)}catch{}
    }
    const message=error instanceof Error?error.message:'dispatcher-readiness-error';
    console.error(
      'defence-external-dispatcher-activation-readiness',
      message,
      {leaseAccepted}
    );
    return jsonResponse(500,{
      error:'dispatcher-activation-readiness-failed'
    });
  }
});
