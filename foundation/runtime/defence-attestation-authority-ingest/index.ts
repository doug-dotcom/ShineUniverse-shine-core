import postgres from 'npm:postgres@3.4.9';
import {verifyGithubActionsOidc} from '../_shared/github-actions-oidc-v1.mjs';
import {bindGithubOidcOperation,oidcReplayConflict} from '../_shared/github-oidc-operation-v1.mjs';

const AUDIENCE='shine-defence-authority-state';
const OIDC_POLICY={
  audience:AUDIENCE,
  expectedRepository:'doug-dotcom/ShineUniverse-shine-core',
  expectedRepositoryId:'1072897952',
  expectedRepositoryOwner:'doug-dotcom',
  expectedRepositoryOwnerId:'225530237',
  expectedRef:'refs/heads/main',
  expectedRefType:'branch',
  expectedRunnerEnvironment:'github-hosted',
  subjectMode:'repository-ref',
  expectedWorkflow:{path:'.github/workflows/shine-defence-authority-state.yml',branch:'main'},
  allowedEvents:['push','workflow_dispatch','schedule']
};
const MAX_BODY_BYTES=48*1024;

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

const sha40=(value:unknown)=>typeof value==='string'&&/^[a-f0-9]{40}$/i.test(value);
const clean=(value:unknown,max=1024)=>typeof value==='string'&&value.length>0&&value.length<=max&&!/[\u0000-\u001f\u007f]/.test(value);
const authorityRef=(sha:string)=>
  'doug-dotcom/ShineUniverse-shine-core/.github/workflows/shine-defence-release-attestation-v1.yml@'+sha.toLowerCase();

const jsonResponse=(status:number,body:unknown)=>new Response(JSON.stringify(body),{
  status,
  headers:{'content-type':'application/json','cache-control':'no-store'}
});

type Activation={
  lineageSequence:number;
  activationKind:'bootstrap'|'promotion'|'rollback';
  authoritySha:string;
  authorityRef:string;
  workflowBlobSha:string;
  activatedAt:string;
  predecessorAuthoritySha:string|null;
  restoreFromSequence:number|null;
  promotionReceipt:Record<string,unknown>|null;
  rollbackReceipt:Record<string,unknown>|null;
};

function validateActivation(value:any):Activation{
  if(!value||typeof value!=='object'||Array.isArray(value)) throw new Error('activation object required');
  if(!Number.isInteger(value.lineageSequence)||value.lineageSequence<1||value.lineageSequence>1_000_000) throw new Error('invalid lineage sequence');
  if(!['bootstrap','promotion','rollback'].includes(value.activationKind)) throw new Error('invalid activation kind');
  if(!sha40(value.authoritySha)||!sha40(value.workflowBlobSha)) throw new Error('invalid authority SHA');
  if(value.authorityRef!==authorityRef(String(value.authoritySha))) throw new Error('authority ref mismatch');
  if(!clean(value.activatedAt,64)||Number.isNaN(Date.parse(value.activatedAt))) throw new Error('invalid activatedAt');

  if(value.activationKind==='bootstrap'){
    if(value.lineageSequence!==1||value.predecessorAuthoritySha!==null||value.restoreFromSequence!==null) throw new Error('invalid bootstrap activation');
  }else{
    if(!sha40(value.predecessorAuthoritySha)) throw new Error('invalid predecessor authority SHA');
    if(value.activationKind==='promotion'&&value.restoreFromSequence!==null) throw new Error('promotion restore sequence forbidden');
    if(value.activationKind==='rollback'&&(!Number.isInteger(value.restoreFromSequence)||value.restoreFromSequence<1||value.restoreFromSequence>=value.lineageSequence)){
      throw new Error('invalid rollback source sequence');
    }
  }

  for(const key of ['promotionReceipt','rollbackReceipt']){
    const child=value[key];
    if(child!==null&&(!child||typeof child!=='object'||Array.isArray(child)||JSON.stringify(child).length>8192)) throw new Error('invalid '+key);
  }
  if(value.activationKind==='promotion'&&value.rollbackReceipt!==null) throw new Error('promotion rollback receipt forbidden');
  if(value.activationKind==='rollback'&&value.promotionReceipt!==null) throw new Error('rollback promotion receipt forbidden');

  return value as Activation;
}


async function recordSyncReceipt(client:any,{
  activation,body,identity,binding,outcome,observedAt
}:{
  activation:Activation;
  body:any;
  identity:any;
  binding:any;
  outcome:'asserted-current'|'recorded'|'replayed';
  observedAt:Date;
}){
  const evidenceRef=[
    'github-oidc','authority-sync-receipt',
    identity.runId,identity.runAttempt,
    String(activation.lineageSequence),
    activation.authoritySha.toLowerCase()
  ].join(':');

  const rows=await client`
    select foundation.record_defence_attestation_authority_sync_receipt_v1(
      ${activation.lineageSequence},
      ${activation.authoritySha.toLowerCase()},
      ${activation.authorityRef},
      ${activation.workflowBlobSha.toLowerCase()},
      ${String(body.publisherCommitSha).toLowerCase()},
      ${String(body.lineageBlobSha).toLowerCase()},
      ${String(body.authorityContractBlobSha).toLowerCase()},
      ${outcome},
      ${identity.runId},
      ${identity.runAttempt},
      ${identity.eventName},
      ${observedAt.toISOString()}::timestamptz,
      ${evidenceRef},
      ${client.json({
        oidcBindingId:binding.bindingId,
        githubActor:identity.actor,
        githubWorkflowRef:identity.workflowRef,
        githubWorkflowSha:identity.workflowSha
      })}
    ) as result
  `;
  const receipt=rows[0]?.result??null;
  if(!receipt) throw new Error('authority-sync-receipt-result-missing');
  if(receipt.status==='rejected'){
    throw new Error('authority-sync-receipt-rejected:'+String(receipt.reasonCode||'unknown'));
  }
  return receipt;
}

Deno.serve(async(req:Request)=>{
  try{
    if(req.method!=='POST') return jsonResponse(405,{error:'method-not-allowed'});
    const contentLength=Number(req.headers.get('content-length')||0);
    if(contentLength>MAX_BODY_BYTES) return jsonResponse(413,{error:'body-too-large'});

    const auth=req.headers.get('authorization')||'';
    if(!auth.startsWith('Bearer ')) return jsonResponse(401,{error:'missing-oidc-token'});
    const identity=await verifyGithubActionsOidc(auth.slice(7),OIDC_POLICY);

    const raw=await req.text();
    if(raw.length>MAX_BODY_BYTES) return jsonResponse(413,{error:'body-too-large'});
    const body=JSON.parse(raw||'{}');

    if(body?.contract!=='shine-defence/attestation-authority-activation-v1'||body?.schemaVersion!=='1.0.0'){
      return jsonResponse(400,{error:'unsupported-authority-activation'});
    }
    if(!sha40(body?.publisherCommitSha)||String(body.publisherCommitSha).toLowerCase()!==String(identity.sha).toLowerCase()){
      return jsonResponse(401,{error:'authority-publisher-commit-mismatch'});
    }
    if(!sha40(body?.lineageBlobSha)||!sha40(body?.authorityContractBlobSha)){
      return jsonResponse(400,{error:'invalid-authority-contract-fingerprint'});
    }

    const activation=validateActivation(body.activation);
    const binding=await bindGithubOidcOperation({
      sql,
      identity,
      audience:AUDIENCE,
      operation:'attestation-authority-sync',
      targetKey:'authority:'+activation.lineageSequence+':'+activation.authoritySha.toLowerCase(),
      request:body
    });
    if(oidcReplayConflict(binding)){
      return jsonResponse(409,{error:'oidc-replay-conflict',binding});
    }

    if(activation.activationKind==='bootstrap'){
      const rows=await sql`
        select
          activation_sequence,
          lower(authority_sha) as authority_sha,
          authority_ref,
          lower(workflow_blob_sha) as workflow_blob_sha,
          activation_kind,
          activated_at
        from foundation.current_defence_attestation_authority
      `;
      const current=rows[0];
      if(
        !current||
        Number(current.activation_sequence)!==1||
        current.authority_sha!==activation.authoritySha.toLowerCase()||
        current.authority_ref!==activation.authorityRef||
        current.workflow_blob_sha!==activation.workflowBlobSha.toLowerCase()||
        current.activation_kind!=='bootstrap'||
        new Date(current.activated_at).toISOString()!==new Date(activation.activatedAt).toISOString()
      ){
        return jsonResponse(409,{error:'bootstrap-authority-state-mismatch'});
      }

      const observedAt=new Date();
      const syncReceipt=await recordSyncReceipt(sql,{
        activation,body,identity,binding,outcome:'asserted-current',observedAt
      });
      const summaryRows=await sql`
        select foundation.get_defence_attestation_authority_sync_summary_v1() as summary
      `;

      return jsonResponse(200,{
        status:'asserted-current',
        contract:'shine-defence/attestation-authority-sync-response-v1',
        activationSequence:1,
        authoritySha:current.authority_sha,
        syncReceipt,
        syncSummary:summaryRows[0]?.summary??null,
        oidcBinding:{status:binding.status,bindingId:binding.bindingId}
      });
    }

    const evidenceRef=[
      'shine-defence','authority-sync',
      String(activation.lineageSequence),
      activation.authoritySha.toLowerCase()
    ].join(':');

    const activationMetadata:any={
      lineageSequence:activation.lineageSequence,
      publisherCommitSha:String(body.publisherCommitSha).toLowerCase(),
      lineageBlobSha:String(body.lineageBlobSha).toLowerCase(),
      authorityContractBlobSha:String(body.authorityContractBlobSha).toLowerCase(),
      promotionReceipt:activation.promotionReceipt,
      rollbackReceipt:activation.rollbackReceipt,
      githubRunId:identity.runId,
      githubRunAttempt:identity.runAttempt,
      githubActor:identity.actor,
      githubWorkflowRef:identity.workflowRef,
      githubWorkflowSha:identity.workflowSha
    };

    let result:any=null;
    let syncReceipt:any=null;
    const observedAt=new Date();

    await sql.begin(async(tx:any)=>{
      const rows=await tx`
        select foundation.record_defence_attestation_authority_activation_v1(
          ${activation.authoritySha.toLowerCase()},
          ${activation.authorityRef},
          ${activation.workflowBlobSha.toLowerCase()},
          ${activation.activationKind},
          ${new Date(activation.activatedAt).toISOString()}::timestamptz,
          ${String(activation.predecessorAuthoritySha).toLowerCase()},
          ${activation.restoreFromSequence},
          ${evidenceRef},
          ${tx.json(activationMetadata)}
        ) as result
      `;

      result=rows[0]?.result??null;
      if(!result) throw new Error('authority-sync-result-missing');
      if(result.status==='rejected') return;

      const receiptOutcome=result.status==='recorded'?'recorded':'replayed';
      syncReceipt=await recordSyncReceipt(tx,{
        activation,body,identity,binding,outcome:receiptOutcome,observedAt
      });
    });

    if(result?.status==='rejected'){
      return jsonResponse(409,{error:'authority-sync-state-conflict',result});
    }

    const [parityRows,summaryRows]=await Promise.all([
      sql`select foundation.get_defence_release_authority_parity_summary_v1() as parity`,
      sql`select foundation.get_defence_attestation_authority_sync_summary_v1() as summary`
    ]);

    return jsonResponse(200,{
      status:'accepted',
      contract:'shine-defence/attestation-authority-sync-response-v1',
      result,
      syncReceipt,
      syncSummary:summaryRows[0]?.summary??null,
      parity:parityRows[0]?.parity??null,
      oidcBinding:{status:binding.status,bindingId:binding.bindingId}
    });
  }catch(error){
    const message=error instanceof Error?error.message:'authority-sync-error';
    const authFailure=/OIDC|oidc|repository mismatch|ref mismatch|workflow mismatch|event not allowed|publisher-commit-mismatch|missing-oidc/.test(message);
    console.error('defence-attestation-authority-ingest',message);
    return jsonResponse(authFailure?401:400,{
      error:authFailure?'unauthorized-authority-sync':'authority-sync-rejected'
    });
  }
});
