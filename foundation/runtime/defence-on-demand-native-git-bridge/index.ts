import postgres from 'npm:postgres@3.4.9';
import {verifyGithubActionsOidc} from '../_shared/github-actions-oidc-v1.mjs';
import {bindGithubOidcOperation,oidcReplayConflict} from '../_shared/github-oidc-operation-v1.mjs';

const AUDIENCE='shine-defence-on-demand-native-git';
const OIDC_POLICY={
  audience:AUDIENCE,
  expectedRepositoryOwner:'doug-dotcom',
  expectedRepositoryOwnerId:'225530237',
  expectedRef:'refs/heads/main',
  expectedRefType:'branch',
  expectedRunnerEnvironment:'github-hosted',
  subjectMode:'repository-ref',
  allowedEvents:['push']
};
const MAX_BODY_BYTES=32*1024;
const UUID=/^[a-f0-9]{8}-[a-f0-9]{4}-[1-5][a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/i;
const SHA=/^[a-f0-9]{40}$/i;
const SHA256=/^[a-f0-9]{64}$/i;

const requireEnv=(name:string)=>{
  const value=Deno.env.get(name);
  if(!value) throw new Error('Missing required environment variable: '+name);
  return value;
};

const sql=postgres(requireEnv('SUPABASE_DB_URL'),{
  max:1,prepare:false,idle_timeout:20,connect_timeout:10
});

const jsonResponse=(status:number,body:unknown)=>new Response(JSON.stringify(body),{
  status,
  headers:{'content-type':'application/json','cache-control':'no-store'}
});

const clean=(v:unknown,max=1024)=>typeof v==='string'&&v.length>0&&v.length<=max&&!/[\u0000-\u001f\u007f]/.test(v);

async function currentProfile(targetId:string){
  const rows=await sql`
    select *
    from foundation.defence_on_demand_executor_profiles
    where target_id=${targetId}
      and effective_at<=now()
    order by effective_at desc,profile_sequence desc
    limit 1
  `;
  const profile=rows[0];
  if(!profile||!profile.native_git_enabled) throw new Error('native-git-executor-profile-missing');
  return profile;
}

function assertWorkflowIdentity(identity:any,profile:any,kind:'candidate'|'execution'){
  const metadata=profile.metadata??{};
  const wrapperPath=kind==='candidate'
    ?metadata.nativeGitCandidateWorkflowPath
    :metadata.nativeGitExecutionWorkflowPath;
  const reusableRef=metadata.nativeGitReusableWorkflowRef;
  const reusableSha=metadata.nativeGitReusableWorkflowSha;

  if(identity.repository!==profile.native_git_repository) throw new Error('native-git-caller-repository-mismatch');
  if(!clean(wrapperPath,512)||!clean(reusableRef,1024)||!SHA.test(String(reusableSha??''))){
    throw new Error('native-git-workflow-profile-incomplete');
  }
  const expectedCallerRef=identity.repository+'/'+wrapperPath+'@refs/heads/main';
  if(identity.workflowRef!==expectedCallerRef) throw new Error('native-git-caller-workflow-mismatch');
  if(identity.jobWorkflowRef!==reusableRef) throw new Error('native-git-reusable-workflow-ref-mismatch');
  if(String(identity.jobWorkflowSha||'').toLowerCase()!==String(reusableSha).toLowerCase()){
    throw new Error('native-git-reusable-workflow-sha-mismatch');
  }
}

async function requestContextFromApproval(approvalId:string){
  const rows=await sql`
    select
      a.approval_id,a.request_id,a.approved_at,a.expires_at as approval_expires_at,
      a.approval,a.approval_sha256,
      r.target_id,r.expires_at as request_expires_at,r.evidence_fingerprint
    from foundation.defence_on_demand_revalidation_approvals a
    join foundation.defence_on_demand_revalidation_requests r
      on r.request_id=a.request_id
    where a.approval_id=${approvalId}::uuid
  `;
  const row=rows[0];
  if(!row) throw new Error('native-git-approval-missing');
  if(new Date(row.approval_expires_at).getTime()<=Date.now()||
     new Date(row.request_expires_at).getTime()<=Date.now()){
    throw new Error('native-git-approval-expired');
  }
  if(row.approval?.executorSelection?.selectedMode!=='native_git'){
    throw new Error('native-git-not-approved-executor');
  }
  return row;
}

async function liveScope(targetId:string){
  const rows=await sql`
    select
      foundation.get_defence_on_demand_revalidation_snapshot_v1(
        ${targetId},now()
      ) as snapshot,
      foundation.get_defence_on_demand_executor_selection_v1(
        ${targetId},now()
      ) as selection
  `;
  const snapshot=rows[0]?.snapshot;
  const selection=rows[0]?.selection;
  if(!snapshot||snapshot.eligible!==true||snapshot.postureState!=='revalidation_required'){
    throw new Error('native-git-live-scope-not-revalidation-required');
  }
  if(!selection||selection.state!=='ready'||selection.selectedMode!=='native_git'){
    throw new Error('native-git-live-executor-not-ready');
  }
  return {snapshot,selection};
}

async function prepareClaim(approvalId:string,identity:any){
  const ctx=await requestContextFromApproval(approvalId);
  const profile=await currentProfile(ctx.target_id);
  assertWorkflowIdentity(identity,profile,'candidate');
  const {snapshot,selection}=await liveScope(ctx.target_id);

  const fpRows=await sql`
    select foundation.get_defence_on_demand_revalidation_fingerprint_v1(
      ${sql.json(snapshot)}
    ) as fingerprint
  `;
  if(fpRows[0]?.fingerprint!==ctx.evidence_fingerprint){
    throw new Error('native-git-live-fingerprint-drift');
  }

  const existing=await sql`
    select candidate_id,candidate_commit_sha
    from foundation.defence_on_demand_native_git_candidates
    where approval_id=${approvalId}::uuid
  `;
  if(existing.length) throw new Error('native-git-candidate-already-prepared');

  return {
    approvalId,
    requestId:String(ctx.request_id),
    targetId:ctx.target_id,
    repository:selection.nativeGit.repository,
    branch:selection.nativeGit.branch,
    baseHeadSha:String(snapshot.source.headSha).toLowerCase(),
    triggerPathPrefix:selection.nativeGit.triggerPathPrefix,
    approvalExpiresAt:new Date(ctx.approval_expires_at).toISOString()
  };
}

async function recordCandidate(body:any,identity:any){
  const ctx=await requestContextFromApproval(String(body.approvalId));
  const profile=await currentProfile(ctx.target_id);
  assertWorkflowIdentity(identity,profile,'candidate');

  const existing=await sql`
    select candidate_id,candidate_commit_sha,trigger_path,marker_sha256,metadata
    from foundation.defence_on_demand_native_git_candidates
    where approval_id=${String(body.approvalId)}::uuid
  `;
  if(existing.length){
    const x=existing[0];
    if(String(x.candidate_commit_sha).toLowerCase()===String(body.candidateCommitSha).toLowerCase()&&
       x.trigger_path===body.triggerPath&&
       String(x.marker_sha256).toLowerCase()===String(body.markerSha256).toLowerCase()){
      return {status:'already-recorded',candidateId:x.candidate_id,candidateCommitSha:x.candidate_commit_sha};
    }
    throw new Error('native-git-candidate-conflict');
  }

  const expires=new Date(Math.min(
    new Date(ctx.approval_expires_at).getTime(),
    Date.now()+10*60*1000
  )).toISOString();

  return sql.begin(async tx=>{
    await tx`set local role shine_defence_on_demand_executor`;
    const rows=await tx`
      select foundation.record_defence_on_demand_native_git_candidate_v1(
        gen_random_uuid(),
        ${String(body.approvalId)}::uuid,
        ${profile.native_git_repository},
        ${profile.native_git_branch},
        ${String(body.baseHeadSha).toLowerCase()},
        ${String(body.candidateCommitSha).toLowerCase()},
        ${String(body.triggerPath)},
        ${String(body.markerSha256).toLowerCase()},
        ${'github:'+String(identity.actor||'actions')},
        now(),
        ${expires}::timestamptz,
        ${[
          'github-oidc','native-git-candidate',
          identity.runId,identity.runAttempt,String(body.candidateCommitSha).toLowerCase()
        ].join(':')},
        ${tx.json({
          candidateBranch:String(body.candidateBranch),
          githubRunId:identity.runId,
          githubRunAttempt:identity.runAttempt,
          githubActor:identity.actor,
          callerWorkflowRef:identity.workflowRef,
          reusableJobWorkflowRef:identity.jobWorkflowRef,
          reusableJobWorkflowSha:identity.jobWorkflowSha,
          runtimeCodeChanged:false
        })}
      ) as result
    `;
    return rows[0]?.result??null;
  });
}

async function executionContext(executionId:string,identity:any){
  const rows=await sql`
    select
      a.execution_id,a.request_id,a.approval_id,a.expires_at,
      a.execution_envelope,a.envelope_sha256,
      encode(
        extensions.digest(
          convert_to(a.execution_envelope::text,'UTF8'),'sha256'
        ),
        'hex'
      ) as computed_envelope_sha256,
      c.candidate_id,c.repository,c.branch,c.base_head_sha,
      c.candidate_commit_sha,c.trigger_path,c.metadata as candidate_metadata,
      foundation.get_defence_on_demand_revalidation_status_v1(
        a.execution_envelope->>'targetId',now()
      ) as control_status
    from foundation.defence_on_demand_revalidation_admissions a
    join foundation.defence_on_demand_native_git_candidates c
      on c.approval_id=a.approval_id
     and c.request_id=a.request_id
    where a.execution_id=${executionId}::uuid
  `;
  const row=rows[0];
  if(!row) throw new Error('native-git-execution-missing');
  if(new Date(row.expires_at).getTime()<=Date.now()) throw new Error('native-git-execution-expired');
  if(row.envelope_sha256!==row.computed_envelope_sha256) throw new Error('native-git-execution-integrity-failed');
  if(row.execution_envelope?.constraints?.executorMode!=='native_git') throw new Error('native-git-execution-mode-invalid');
  if(row.control_status?.state!=='admitted'&&row.control_status?.state!=='in_progress'){
    throw new Error('native-git-execution-not-active');
  }
  const profile=await currentProfile(String(row.execution_envelope.targetId));
  assertWorkflowIdentity(identity,profile,'execution');
  if(profile.native_git_repository!==row.repository||profile.native_git_branch!==row.branch){
    throw new Error('native-git-execution-profile-drift');
  }
  return {row,profile};
}

async function recordFastForwardStart(body:any,identity:any){
  const {row}=await executionContext(String(body.executionId),identity);
  const existing=await sql`
    select event_id,evidence
    from foundation.defence_on_demand_revalidation_events
    where execution_id=${String(body.executionId)}::uuid
      and step_type='redeploy_started'
  `;
  if(existing.length){
    const e=existing[0].evidence;
    if(String(e?.observedBranchHeadSha||'').toLowerCase()===String(body.observedBranchHeadSha).toLowerCase()&&
       String(e?.candidateCommitSha||'').toLowerCase()===String(body.candidateCommitSha).toLowerCase()){
      return {status:'already-recorded',eventId:existing[0].event_id};
    }
    throw new Error('native-git-fast-forward-start-conflict');
  }

  const env=row.execution_envelope;
  return sql.begin(async tx=>{
    await tx`set local role shine_defence_on_demand_executor`;
    const rows=await tx`
      select foundation.record_defence_on_demand_revalidation_step_v1(
        gen_random_uuid(),
        ${String(body.executionId)}::uuid,
        'redeploy_started',
        ${tx.json({
          projectId:env.railway.projectId,
          environmentId:env.railway.environmentId,
          serviceId:env.railway.serviceId,
          expectedSourceHeadSha:env.constraints.expectedSourceHeadSha,
          executorMode:'native_git',
          repository:row.repository,
          branch:row.branch,
          observedBranchHeadSha:String(body.observedBranchHeadSha).toLowerCase(),
          candidateCommitSha:String(body.candidateCommitSha).toLowerCase(),
          githubRunId:identity.runId,
          githubRunAttempt:identity.runAttempt,
          githubActor:identity.actor,
          callerWorkflowRef:identity.workflowRef,
          reusableJobWorkflowRef:identity.jobWorkflowRef,
          reusableJobWorkflowSha:identity.jobWorkflowSha,
          externalMutationPerformed:false
        })},
        now()
      ) as result
    `;
    return rows[0]?.result??null;
  });
}

async function recordFastForwardResult(body:any,identity:any){
  const {row}=await executionContext(String(body.executionId),identity);
  const existing=await sql`
    select receipt_id,previous_head_sha,new_head_sha,observed_after_sha
    from foundation.defence_on_demand_native_git_fast_forward_receipts
    where execution_id=${String(body.executionId)}::uuid
  `;
  if(existing.length){
    const x=existing[0];
    if(String(x.previous_head_sha).toLowerCase()===String(body.previousHeadSha).toLowerCase()&&
       String(x.new_head_sha).toLowerCase()===String(body.newHeadSha).toLowerCase()&&
       String(x.observed_after_sha).toLowerCase()===String(body.observedAfterSha).toLowerCase()){
      return {status:'already-recorded',receiptId:x.receipt_id};
    }
    throw new Error('native-git-fast-forward-receipt-conflict');
  }

  return sql.begin(async tx=>{
    await tx`set local role shine_defence_on_demand_executor`;
    const rows=await tx`
      select foundation.record_defence_on_demand_native_git_fast_forward_v1(
        gen_random_uuid(),
        ${String(body.executionId)}::uuid,
        ${String(body.previousHeadSha).toLowerCase()},
        ${String(body.newHeadSha).toLowerCase()},
        ${String(body.observedAfterSha).toLowerCase()},
        now(),
        ${[
          'github-oidc','native-git-fast-forward',
          identity.runId,identity.runAttempt,String(body.newHeadSha).toLowerCase()
        ].join(':')},
        ${tx.json({
          candidateBranch:String(row.candidate_metadata?.candidateBranch??''),
          githubRunId:identity.runId,
          githubRunAttempt:identity.runAttempt,
          githubActor:identity.actor,
          callerWorkflowRef:identity.workflowRef,
          reusableJobWorkflowRef:identity.jobWorkflowRef,
          reusableJobWorkflowSha:identity.jobWorkflowSha
        })}
      ) as result
    `;
    return rows[0]?.result??null;
  });
}

async function recordFailure(body:any,identity:any){
  const {row}=await executionContext(String(body.executionId),identity);
  const terminal=await sql`
    select event_id,step_type
    from foundation.defence_on_demand_revalidation_events
    where execution_id=${String(body.executionId)}::uuid
      and step_type in ('completed','failed')
    order by event_sequence desc limit 1
  `;
  if(terminal.length) return {status:'already-terminal',stepType:terminal[0].step_type};

  return sql.begin(async tx=>{
    await tx`set local role shine_defence_on_demand_executor`;
    const rows=await tx`
      select foundation.record_defence_on_demand_revalidation_step_v1(
        gen_random_uuid(),
        ${String(body.executionId)}::uuid,
        'failed',
        ${tx.json({
          phase:clean(body.phase,128)?String(body.phase):'native_git_fast_forward',
          reasonCode:clean(body.reasonCode,256)?String(body.reasonCode):'native-git-workflow-failed',
          externalMutationPerformed:Boolean(body.externalMutationPerformed),
          expectedSourceHeadSha:row.execution_envelope?.constraints?.expectedSourceHeadSha??null,
          requiredBranchBaseSha:row.execution_envelope?.constraints?.requiredBranchBaseSha??null,
          githubRunId:identity.runId,
          githubRunAttempt:identity.runAttempt
        })},
        now()
      ) as result
    `;
    return rows[0]?.result??null;
  });
}

Deno.serve(async(req:Request)=>{
  try{
    if(req.method!=='POST') return jsonResponse(405,{error:'method-not-allowed'});
    const length=Number(req.headers.get('content-length')||0);
    if(length>MAX_BODY_BYTES) return jsonResponse(413,{error:'body-too-large'});

    const auth=req.headers.get('authorization')??'';
    if(!auth.startsWith('Bearer ')) return jsonResponse(401,{error:'missing-oidc-token'});
    const identity=await verifyGithubActionsOidc(auth.slice(7),OIDC_POLICY);

    const raw=await req.text();
    if(raw.length>MAX_BODY_BYTES) return jsonResponse(413,{error:'body-too-large'});
    const body=JSON.parse(raw||'{}');
    if(body?.contract!=='shine-defence/on-demand-native-git-bridge-v1'||
       body?.schemaVersion!=='1.0.0'){
      return jsonResponse(400,{error:'invalid-native-git-bridge-request'});
    }

    const action=String(body.action||'');
    const allowed=new Set([
      'prepare-claim','record-candidate','execution-claim',
      'record-fast-forward-start','record-fast-forward-result','record-failure'
    ]);
    if(!allowed.has(action)) return jsonResponse(400,{error:'unsupported-native-git-bridge-action'});

    if((action==='prepare-claim'||action==='record-candidate')&&!UUID.test(String(body.approvalId??''))){
      return jsonResponse(400,{error:'invalid-native-git-approval-id'});
    }
    if(action!=='prepare-claim'&&action!=='record-candidate'&&!UUID.test(String(body.executionId??''))){
      return jsonResponse(400,{error:'invalid-native-git-execution-id'});
    }
    if(action==='record-candidate'&&(
      !SHA.test(String(body.baseHeadSha??''))||
      !SHA.test(String(body.candidateCommitSha??''))||
      !SHA256.test(String(body.markerSha256??''))||
      !clean(body.triggerPath,512)||
      !clean(body.candidateBranch,256)
    )){
      return jsonResponse(400,{error:'invalid-native-git-candidate-evidence'});
    }
    if((action==='record-fast-forward-start'||action==='record-fast-forward-result')&&(
      !SHA.test(String(
        action==='record-fast-forward-start'?body.observedBranchHeadSha:body.previousHeadSha
      )??'')||
      !SHA.test(String(
        action==='record-fast-forward-start'?body.candidateCommitSha:body.newHeadSha
      )??'')
    )){
      return jsonResponse(400,{error:'invalid-native-git-fast-forward-evidence'});
    }
    if(action==='record-fast-forward-result'&&!SHA.test(String(body.observedAfterSha??''))){
      return jsonResponse(400,{error:'invalid-native-git-observed-after-sha'});
    }

    const operation='native-git-'+action;
    const controlId=action==='prepare-claim'||action==='record-candidate'
      ?String(body.approvalId)
      :String(body.executionId);
    const binding=await bindGithubOidcOperation({
      sql,
      identity,
      audience:AUDIENCE,
      operation,
      targetKey:controlId+':'+action,
      request:body
    });
    if(oidcReplayConflict(binding)){
      return jsonResponse(409,{error:'oidc-replay-conflict',binding});
    }

    let result:any;
    if(action==='prepare-claim') result=await prepareClaim(String(body.approvalId),identity);
    else if(action==='record-candidate') result=await recordCandidate(body,identity);
    else if(action==='execution-claim'){
      const {row}=await executionContext(String(body.executionId),identity);
      result={
        executionId:String(row.execution_id),
        requestId:String(row.request_id),
        approvalId:String(row.approval_id),
        targetId:String(row.execution_envelope.targetId),
        repository:row.repository,
        branch:row.branch,
        baseHeadSha:String(row.base_head_sha).toLowerCase(),
        candidateCommitSha:String(row.candidate_commit_sha).toLowerCase(),
        triggerPath:row.trigger_path,
        candidateBranch:String(row.candidate_metadata?.candidateBranch??''),
        projectId:String(row.execution_envelope.railway.projectId),
        environmentId:String(row.execution_envelope.railway.environmentId),
        serviceId:String(row.execution_envelope.railway.serviceId),
        expiresAt:new Date(row.expires_at).toISOString()
      };
    } else if(action==='record-fast-forward-start') result=await recordFastForwardStart(body,identity);
    else if(action==='record-fast-forward-result') result=await recordFastForwardResult(body,identity);
    else result=await recordFailure(body,identity);

    return jsonResponse(200,{
      status:'accepted',
      contract:'shine-defence/on-demand-native-git-bridge-v1',
      action,
      result
    });
  }catch(error){
    const message=error instanceof Error?error.message:'native-git-bridge-error';
    const authFailure=/OIDC|oidc|caller-repository|caller-workflow|reusable-workflow|subject mismatch|ref mismatch|repository owner/.test(message);
    console.error('defence-on-demand-native-git-bridge',message);
    return jsonResponse(authFailure?401:409,{
      error:authFailure?'unauthorized-native-git-bridge':'native-git-bridge-rejected',
      reasonCode:message
    });
  }
});
