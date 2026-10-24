import assert from 'node:assert/strict';
import {test} from 'node:test';
import {readFileSync} from 'node:fs';
import {recoverAuthorityHeartbeat} from './authority-heartbeat-recovery-v1.mjs';

const now=Date.parse('2026-10-24T12:40:00Z');
const iso=age=>new Date(now-age*60000).toISOString();
const repository={full_name:'doug-dotcom/ShineUniverse-shine-core',id:1072897952};
const sha='9a70cdcb9169f22c18c0afeb44e209ae2c2c33bc';
const run={id:100,repository,head_repository:repository,head_branch:'main',head_sha:sha,
  event:'schedule',path:'.github/workflows/shine-defence-on-demand-executor-readiness.yml',
  status:'completed',conclusion:'failure',run_attempt:1,updated_at:iso(1)};
const publisher=(overrides={})=>({...run,id:200,
  path:'.github/workflows/shine-defence-authority-state.yml',
  conclusion:'success',run_started_at:iso(60),created_at:iso(60),...overrides});

function fixture({source={},verified={},runs=[],mainSha=sha,responses={}}={}){
  const calls=[];
  const event={repository,workflow_run:{...structuredClone(run),...source}};
  const fetchImpl=async(url,options)=>{
    calls.push({url,options});
    const path=url.replace('https://api.github.com/repos/'+repository.full_name,'');
    if(responses[path]) return responses[path];
    let data;
    if(path==='/actions/runs/100') data={...event.workflow_run,...verified};
    else if(path==='/branches/main') data={commit:{sha:mainSha}};
    else if(path.includes('/runs?')) data={workflow_runs:runs};
    else if(path.endsWith('/dispatches')) return {status:204};
    else throw new Error('unexpected request');
    return {status:200,json:async()=>data};
  };
  const execute=(extra={})=>recoverAuthorityHeartbeat({eventName:'workflow_run',event,
    token:'synthetic-test-token',fetchImpl,now,...extra});
  return {execute,calls,event};
}

test('ageing publisher requests only canonical main publisher',async()=>{
  const f=fixture({runs:[publisher()]});
  assert.equal((await f.execute()).result,'refresh-requested');
  const post=f.calls.filter(x=>x.options.method==='POST');
  assert.equal(post.length,1);
  assert.equal(post[0].url,'https://api.github.com/repos/'+repository.full_name+
    '/actions/workflows/shine-defence-authority-state.yml/dispatches');
  assert.deepEqual(JSON.parse(post[0].options.body),{ref:'main'});
  assert.ok(f.calls.every(x=>x.options.redirect==='error'&&x.options.signal));
});
test('recent success suppresses refresh regardless of listing order',async()=>{
  const f=fixture({runs:[publisher(),publisher({id:201,run_started_at:iso(29)})]});
  assert.equal((await f.execute()).result,'publisher-recent');
  assert.equal(f.calls.length,3);
});
test('fresh queued publisher suppresses duplicate dispatch',async()=>{
  const f=fixture({runs:[publisher({status:'queued',created_at:iso(2)})]});
  assert.equal((await f.execute()).result,'publisher-in-flight');
  assert.equal(f.calls.length,3);
});
test('stuck publisher does not suppress recovery',async()=>{
  const f=fixture({runs:[publisher({status:'in_progress',created_at:iso(11)})]});
  assert.equal((await f.execute()).result,'refresh-requested');
});
for(const [label,source] of Object.entries({
  fork:{head_repository:{...repository,id:999}},
  branch:{head_branch:'feature'},
  pullRequest:{event:'pull_request'},
  recursion:{path:'.github/workflows/shine-defence-authority-state.yml'},
  unknownWorkflow:{path:'.github/workflows/arbitrary.yml'},
  incomplete:{status:'in_progress'},
  stale:{updated_at:iso(11)},
  future:{updated_at:iso(-1)},
  invalidTime:{updated_at:'invalid'},
  malformedId:{id:'100/../../branches/main'}
})){
  test('refuses '+label+' without network',async()=>{
    const f=fixture({source});
    await assert.rejects(f.execute());
    assert.equal(f.calls.length,0);
  });
}
test('API metadata mismatch cannot dispatch',async()=>{
  const f=fixture({verified:{run_attempt:2}});
  await assert.rejects(f.execute(),/recovery-run-mismatch/);
  assert.equal(f.calls.length,1);
});
test('changed main cannot dispatch',async()=>{
  const f=fixture({mainSha:'a'.repeat(40)});
  await assert.rejects(f.execute(),/recovery-main-changed/);
  assert.equal(f.calls.length,2);
});
test('untrusted or future publisher metadata is not a freshness proof',async()=>{
  const f=fixture({runs:[publisher({run_started_at:iso(-1)}),
    publisher({head_sha:'b'.repeat(40),run_started_at:iso(1)})]});
  assert.equal((await f.execute()).result,'refresh-requested');
});
test('API denial stops recovery without leaking response body',async()=>{
  const f=fixture({responses:{'/actions/runs/100':{status:403,
    json:()=>{throw new Error('must not read sensitive response');}}}});
  await assert.rejects(f.execute(),/^Error: recovery-api-rejected$/);
  assert.equal(f.calls.length,1);
});
test('missing token stops before network',async()=>{
  const f=fixture();
  await assert.rejects(f.execute({token:''}),/recovery-token-unavailable/);
  assert.equal(f.calls.length,0);
});
test('privileged watcher excludes PR code, artifacts, OIDC and recursive triggers',()=>{
  const workflow=readFileSync(new URL('../../../.github/workflows/shine-defence-heartbeat-recovery.yml',import.meta.url),'utf8');
  assert.match(workflow,/permissions: \{\}/);
  assert.match(workflow,/actions: write/);
  assert.match(workflow,/ref: \$\{\{ github\.sha \}\}/);
  assert.match(workflow,/persist-credentials: false/);
  assert.match(workflow,/cancel-in-progress: false/);
  assert.match(workflow,/timeout-minutes: 2/);
  assert.doesNotMatch(workflow,/id-token:|secrets\.|download-artifact|head_sha \}\}/);
  const triggers=workflow.split('\non:\n')[1].split('permissions:')[0];
  assert.doesNotMatch(triggers,/workflow_dispatch:|schedule:|pull_request|Authority State|Heartbeat Recovery\n/);
});
