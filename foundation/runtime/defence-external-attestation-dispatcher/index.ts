import postgres from 'npm:postgres@3.4.9';

const CONTRACT='shine-defence/external-attestation-dispatch-trigger-v1';
const MAX_BODY_BYTES=16*1024;
const API_VERSION='2026-03-10';
const SHA_ID=/^[0-9]{1,20}$/;
const UUID=/^[a-f0-9]{8}-[a-f0-9]{4}-[1-5][a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/i;
const TOKEN=/^[a-f0-9]{64}$/;

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
  const b64=match[1].replace(/\s+/g,'');
  const binary=atob(b64);
  return Uint8Array.from(binary,c=>c.charCodeAt(0));
};

async function createGithubAppJwt(appId:string,privateKeyPkcs8:string){
  if(!SHA_ID.test(appId)) throw new Error('github-app-id-invalid');
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

type DispatchItem={
  dispatchKind:'authority_refresh'|'rollback_refresh';
  targetId:string|null;
  repository:string;
  repositoryId:string;
  workflowPath:string;
  ref:string;
  reasonCode:string;
};

const validItem=(item:any):item is DispatchItem=>
  item&&
  (item.dispatchKind==='authority_refresh'||item.dispatchKind==='rollback_refresh')&&
  (item.targetId===null||/^railway:[a-z0-9][a-z0-9-]*$/.test(String(item.targetId)))&&
  /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(String(item.repository||''))&&
  SHA_ID.test(String(item.repositoryId||''))&&
  /^\.github\/workflows\/[A-Za-z0-9_.-]+\.ya?ml$/.test(String(item.workflowPath||''))&&
  /^[A-Za-z0-9._/-]{1,128}$/.test(String(item.ref||''))&&
  /^[a-z0-9][a-z0-9-]{1,127}$/.test(String(item.reasonCode||''));

async function createInstallationToken(
  appId:string,
  installationId:string,
  privateKeyPkcs8:string,
  repositoryIds:string[]
){
  if(!SHA_ID.test(installationId)) throw new Error('github-installation-id-invalid');
  const appJwt=await createGithubAppJwt(appId,privateKeyPkcs8);
  const response=await fetch(
    'https://api.github.com/app/installations/'+installationId+'/access_tokens',
    {
      method:'POST',
      redirect:'error',
      headers:{
        'Accept':'application/vnd.github+json',
        'Authorization':'Bearer '+appJwt,
        'X-GitHub-Api-Version':API_VERSION,
        'Content-Type':'application/json',
        'User-Agent':'Shine-Defence-External-Dispatcher/1.0'
      },
      body:JSON.stringify({
        repository_ids:repositoryIds.map(Number),
        permissions:{actions:'write'}
      })
    }
  );
  const text=await response.text();
  let body:any=null;
  try{body=text?JSON.parse(text):null}catch{}
  if(!response.ok||!body?.token){
    throw new Error('github-installation-token-failed:'+response.status);
  }
  return String(body.token);
}

async function dispatchWorkflow(token:string,item:DispatchItem){
  const [owner,repo]=item.repository.split('/');
  const workflowId=item.workflowPath.split('/').at(-1)!;
  const url=
    'https://api.github.com/repos/'+encodeURIComponent(owner)+'/'+
    encodeURIComponent(repo)+'/actions/workflows/'+
    encodeURIComponent(workflowId)+'/dispatches';
  const response=await fetch(url,{
    method:'POST',
    redirect:'error',
    headers:{
      'Accept':'application/vnd.github+json',
      'Authorization':'Bearer '+token,
      'X-GitHub-Api-Version':API_VERSION,
      'Content-Type':'application/json',
      'User-Agent':'Shine-Defence-External-Dispatcher/1.0'
    },
    body:JSON.stringify({ref:item.ref})
  });
  const text=await response.text();
  let body:any=null;
  try{body=text?JSON.parse(text):null}catch{}
  const accepted=response.status===200||response.status===204;
  return {
    accepted,
    httpStatus:response.status,
    githubRunId:accepted&&body?.workflow_run_id
      ?String(body.workflow_run_id)
      :null
  };
}

async function claimLease(leaseId:string,leaseToken:string,executionId:string){
  const rows=await sql`
    select foundation.claim_defence_external_dispatch_lease_v1(
      ${leaseId}::uuid,
      ${leaseToken},
      ${executionId},
      now()
    ) as claim
  `;
  return rows[0]?.claim??null;
}

async function dispatchPlan(){
  const rows=await sql`
    select foundation.get_defence_external_dispatch_plan_v1(
      now(),3600,900
    ) as plan
  `;
  return rows[0]?.plan??null;
}

async function recordHeartbeat(
  executionId:string,
  credentialsReady:boolean,
  outcome:string,
  metadata:any
){
  const rows=await sql`
    select foundation.record_defence_external_dispatcher_heartbeat_v1(
      gen_random_uuid(),
      ${credentialsReady},
      ${outcome},
      now(),
      ${'external-dispatcher:'+executionId+':heartbeat'},
      ${sql.json(metadata)}
    ) as result
  `;
  return rows[0]?.result??null;
}

async function recordDispatch(
  executionId:string,
  item:DispatchItem,
  outcome:'dispatched'|'disabled'|'failed'|'skipped',
  githubRunId:string|null,
  httpStatus:number|null,
  metadata:any
){
  const eventId=crypto.randomUUID();
  const rows=await sql`
    select foundation.record_defence_external_dispatch_event_v1(
      ${eventId}::uuid,
      ${item.dispatchKind},
      ${item.targetId},
      ${item.repository},
      ${item.workflowPath},
      ${item.ref},
      ${item.reasonCode},
      ${outcome},
      ${githubRunId},
      ${httpStatus},
      now(),
      ${'external-dispatcher:'+executionId+':'+eventId},
      ${sql.json(metadata)}
    ) as result
  `;
  return rows[0]?.result??null;
}

Deno.serve(async(req:Request)=>{
  const executionId=
    Deno.env.get('SB_EXECUTION_ID')||crypto.randomUUID();
  let leaseAccepted=false;

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
      return jsonResponse(400,{error:'invalid-external-dispatch-trigger'});
    }

    const claim=await claimLease(
      String(body.leaseId),
      String(body.leaseToken),
      executionId
    );
    if(claim?.status!=='accepted'){
      return jsonResponse(401,{error:'external-dispatch-lease-rejected'});
    }
    leaseAccepted=true;

    const plan=await dispatchPlan();
    if(
      !plan||
      plan.contract!=='shine-defence/external-dispatch-plan-v1'||
      !Array.isArray(plan.items)||
      plan.items.some((item:any)=>!validItem(item))||
      plan.items.length>50
    ){
      throw new Error('external-dispatch-plan-invalid');
    }

    const appId=Deno.env.get('SHINE_DEFENCE_GITHUB_APP_ID')||'';
    const installationId=
      Deno.env.get('SHINE_DEFENCE_GITHUB_APP_INSTALLATION_ID')||'';
    const privateKey=
      Deno.env.get('SHINE_DEFENCE_GITHUB_APP_PRIVATE_KEY_PKCS8')||'';

    const credentialsReady=
      SHA_ID.test(appId)&&
      SHA_ID.test(installationId)&&
      privateKey.includes('BEGIN PRIVATE KEY');

    const credentialMetadata={
      collector:'shine-defence/external-attestation-dispatcher-v1',
      githubAppIdPresent:Boolean(appId),
      githubInstallationIdPresent:Boolean(installationId),
      githubPrivateKeyPresent:Boolean(privateKey),
      credentialValueExposed:false,
      triggerIsEvidence:false,
      workflowOidcRemainsAuthoritative:true,
      planPhase:plan.phase,
      plannedItemCount:plan.items.length
    };

    if(!credentialsReady){
      for(const item of plan.items){
        await recordDispatch(
          executionId,item,'disabled',null,null,
          {...credentialMetadata,reasonCode:'github-app-credentials-missing'}
        );
      }
      const heartbeat=await recordHeartbeat(
        executionId,
        false,
        'disabled_missing_credentials',
        credentialMetadata
      );
      return jsonResponse(200,{
        status:'disabled',
        contract:'shine-defence/external-attestation-dispatcher-v1',
        reasonCode:'github-app-credentials-missing',
        planPhase:plan.phase,
        itemCount:plan.items.length,
        heartbeat
      });
    }

    if(plan.items.length===0){
      const heartbeat=await recordHeartbeat(
        executionId,true,'ready_idle',credentialMetadata
      );
      return jsonResponse(200,{
        status:'idle',
        contract:'shine-defence/external-attestation-dispatcher-v1',
        planPhase:plan.phase,
        itemCount:0,
        heartbeat
      });
    }

    const repositoryIds:string[]=[
      ...new Set(
        (plan.items as DispatchItem[]).map(item=>String(item.repositoryId))
      )
    ];
    const installationToken=await createInstallationToken(
      appId,installationId,privateKey,repositoryIds
    );

    let dispatched=0;
    let failed=0;
    const results:any[]=[];

    for(const item of plan.items as DispatchItem[]){
      try{
        const result=await dispatchWorkflow(installationToken,item);
        const outcome=result.accepted?'dispatched':'failed';
        if(result.accepted) dispatched+=1;
        else failed+=1;

        await recordDispatch(
          executionId,
          item,
          outcome,
          result.githubRunId,
          result.httpStatus,
          {
            ...credentialMetadata,
            githubApiVersion:API_VERSION,
            installationTokenStored:false,
            appJwtStored:false
          }
        );

        results.push({
          targetId:item.targetId,
          repository:item.repository,
          outcome,
          httpStatus:result.httpStatus,
          githubRunId:result.githubRunId
        });
      }catch(error){
        failed+=1;
        const reason=error instanceof Error?error.message:'dispatch-failed';
        await recordDispatch(
          executionId,item,'failed',null,null,
          {
            ...credentialMetadata,
            reasonCode:reason.slice(0,256),
            installationTokenStored:false,
            appJwtStored:false
          }
        );
        results.push({
          targetId:item.targetId,
          repository:item.repository,
          outcome:'failed',
          error:reason.slice(0,256)
        });
      }
    }

    const heartbeat=await recordHeartbeat(
      executionId,
      true,
      failed>0?'ready_partial_failure':'ready_dispatched',
      {
        ...credentialMetadata,
        dispatchedCount:dispatched,
        failedCount:failed,
        installationTokenStored:false,
        appJwtStored:false
      }
    );

    return jsonResponse(200,{
      status:failed>0?'partial_failure':'dispatched',
      contract:'shine-defence/external-attestation-dispatcher-v1',
      planPhase:plan.phase,
      itemCount:plan.items.length,
      dispatchedCount:dispatched,
      failedCount:failed,
      results,
      heartbeat
    });
  }catch(error){
    const message=error instanceof Error?error.message:'external-dispatcher-error';
    console.error(
      'defence-external-attestation-dispatcher',
      message,
      {leaseAccepted}
    );
    if(leaseAccepted){
      try{
        await recordHeartbeat(
          executionId,
          false,
          'failed',
          {
            collector:'shine-defence/external-attestation-dispatcher-v1',
            reasonCode:message.slice(0,256),
            credentialValueExposed:false,
            triggerIsEvidence:false
          }
        );
      }catch{}
    }
    return jsonResponse(500,{
      error:'external-attestation-dispatcher-failed'
    });
  }
});
