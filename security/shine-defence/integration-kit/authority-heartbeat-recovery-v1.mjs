import {readFile} from 'node:fs/promises';
import {pathToFileURL} from 'node:url';

const REPOSITORY='doug-dotcom/ShineUniverse-shine-core';
const REPOSITORY_ID=1072897952;
const PUBLISHER='.github/workflows/shine-defence-authority-state.yml';
const API='https://api.github.com/repos/'+REPOSITORY;
const CONTROL_PATHS=new Set([
  '.github/workflows/shine-defence-core.yml',
  '.github/workflows/shine-defence-on-demand-executor-readiness.yml',
  '.github/workflows/shine-defence-reattest.yml',
  '.github/workflows/shine-defence-provider-collector.yml',
  '.github/workflows/shine-defence-release-head.yml'
]);
const EVENTS=new Set(['schedule','workflow_dispatch','push']);
const REFRESH_AFTER_MS=30*60*1000;
const IN_FLIGHT_MS=10*60*1000;
const MAX_EVENT_AGE_MS=10*60*1000;
const sha=value=>typeof value==='string'&&/^[a-f0-9]{40}$/.test(value);
const timestamp=value=>typeof value==='string'?Date.parse(value):NaN;

function trustedRun(run){
  return run?.repository?.full_name===REPOSITORY&&
    run.repository.id===REPOSITORY_ID&&
    run.head_repository?.full_name===REPOSITORY&&
    run.head_repository.id===REPOSITORY_ID&&
    run.head_branch==='main'&&EVENTS.has(run.event)&&sha(run.head_sha);
}

export async function recoverAuthorityHeartbeat({
  eventName,event,token,fetchImpl=globalThis.fetch,now=Date.now()
}={}){
  const source=event?.workflow_run;
  if(eventName!=='workflow_run'||event?.repository?.full_name!==REPOSITORY||
      event.repository.id!==REPOSITORY_ID||!trustedRun(source)||
      !CONTROL_PATHS.has(source.path)||source.status!=='completed'||
      !Number.isSafeInteger(source.id)||source.id<=0||!Number.isFinite(now)){
    throw new Error('untrusted-recovery-event');
  }
  const eventAge=now-timestamp(source.updated_at);
  if(!Number.isFinite(eventAge)||eventAge<0||eventAge>MAX_EVENT_AGE_MS){
    throw new Error('stale-recovery-event');
  }
  if(typeof token!=='string'||!token) throw new Error('recovery-token-unavailable');

  async function request(path,{method='GET',body}={}){
    const response=await fetchImpl(API+path,{
      method,redirect:'error',signal:AbortSignal.timeout(10000),
      headers:{Accept:'application/vnd.github+json',Authorization:'Bearer '+token,
        'X-GitHub-Api-Version':'2022-11-28','Content-Type':'application/json'},
      ...(body===undefined?{}:{body:JSON.stringify(body)})
    });
    if(response.status!==(method==='POST'?204:200)){
      throw new Error('recovery-api-rejected');
    }
    return method==='POST'?null:response.json();
  }

  // Re-fetch trusted metadata; do not consume artifacts, logs or caller-supplied URLs.
  const verified=await request('/actions/runs/'+source.id);
  if(!trustedRun(verified)||verified.id!==source.id||verified.path!==source.path||
      verified.status!=='completed'||verified.head_sha!==source.head_sha||
      verified.run_attempt!==source.run_attempt||verified.event!==source.event||
      verified.updated_at!==source.updated_at){
    throw new Error('recovery-run-mismatch');
  }
  const main=await request('/branches/main');
  if(!sha(main?.commit?.sha)||main.commit.sha!==verified.head_sha){
    throw new Error('recovery-main-changed');
  }
  const listing=await request('/actions/workflows/shine-defence-authority-state.yml/runs?branch=main&per_page=30');
  if(!Array.isArray(listing?.workflow_runs)) throw new Error('invalid-publisher-runs');
  const runs=listing.workflow_runs.filter(run=>trustedRun(run)&&run.path===PUBLISHER&&
    run.head_sha===main.commit.sha);
  for(const run of runs){
    // Future/invalid dates are not evidence that a publisher is current.
    if(['queued','in_progress','waiting','pending','requested'].includes(run.status)){
      const age=now-timestamp(run.created_at);
      if(Number.isFinite(age)&&age>=0&&age<IN_FLIGHT_MS){
        return {result:'publisher-in-flight',runId:run.id};
      }
    }
    if(run.status==='completed'&&run.conclusion==='success'){
      const age=now-timestamp(run.run_started_at);
      if(Number.isFinite(age)&&age>=0&&age<REFRESH_AFTER_MS){
        return {result:'publisher-recent',runId:run.id};
      }
    }
  }
  await request('/actions/workflows/shine-defence-authority-state.yml/dispatches',{
    method:'POST',body:{ref:'main'}
  });
  return {result:'refresh-requested',sourceRunId:source.id};
}

if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href){
  try{
    const result=await recoverAuthorityHeartbeat({
      eventName:process.env.GITHUB_EVENT_NAME,
      event:JSON.parse(await readFile(process.env.GITHUB_EVENT_PATH,'utf8')),
      token:process.env.GITHUB_TOKEN
    });
    console.log(JSON.stringify(result));
  }catch{
    // No API response bodies, event payloads or credentials in diagnostics.
    console.error('AUTHORITY_HEARTBEAT_RECOVERY_FAILED');
    process.exitCode=1;
  }
}
