#!/usr/bin/env node
import {readFileSync,writeFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {join} from 'node:path';

export const SHINE_DEFENCE_ESTATE_PROVIDER_COLLECTOR_VERSION='1.0.0';
const root=fileURLToPath(new URL('../../../',import.meta.url));
const registryPath=join(root,'security/shine-defence/estate-provider-sources-v1.json');
const TARGET=/^(?:supabase|railway):[a-z0-9][a-z0-9-]*$/;
const UUID=/^[a-f0-9]{8}-[a-f0-9]{4}-[1-5][a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/i;
const SHA=/^[a-f0-9]{40}$/i;
const secretLike=/(?:bearer\s+[a-z0-9._-]{12,}|sbp_[a-z0-9_-]{12,}|(?:token|secret|password|credential|authorization|cookie|api[_-]?key)\s*[=:]\s*[^\s]{8,})/i;
const fail=m=>{throw new Error(m)};

export function validateSources(registry){
  const failures=[];
  if(registry?.contract!=='shine-defence/estate-provider-sources-v1'||registry.version!=='1.0.0'||!Array.isArray(registry.sources)) return ['unsupported provider source registry'];
  const ids=new Set(),scopes=new Set();
  for(const [i,s] of registry.sources.entries()){
    const p='source '+i;
    if(!TARGET.test(s.targetId||''))failures.push(p+': invalid targetId');
    else if(ids.has(s.targetId))failures.push(p+': duplicate targetId');
    else ids.add(s.targetId);
    if(s.provider==='supabase'){
      if(!/^[a-z]{20}$/.test(s.projectRef||''))failures.push(p+': invalid Supabase project ref');
      const scope='supabase:'+s.projectRef;
      if(scopes.has(scope))failures.push(p+': duplicate provider scope'); else scopes.add(scope);
    }else if(s.provider==='railway'){
      if(!UUID.test(s.projectId||'')||!UUID.test(s.environmentId||'')||!UUID.test(s.serviceId||''))failures.push(p+': invalid Railway scope');
      const scope=['railway',s.projectId,s.environmentId,s.serviceId].join(':');
      if(scopes.has(scope))failures.push(p+': duplicate provider scope'); else scopes.add(scope);
    }else failures.push(p+': unsupported provider');
  }
  if(ids.size!==20)failures.push('expected exactly 20 estate provider targets');
  return failures;
}

const cleanString=(value,max=256)=>typeof value==='string'&&value.length>0&&value.length<=max&&!secretLike.test(value);
const iso=()=>new Date().toISOString();

function classifyRailway(deployments,{sleepAllowed=false}={}){
  const sorted=[...deployments].sort((a,b)=>String(b.createdAt).localeCompare(String(a.createdAt)));
  const latest=sorted[0]??null;
  const serving=sorted.find(d=>d.status==='SUCCESS'||d.status==='SLEEPING')??null;
  if(!latest) return {runtimeState:'unknown',current:null,latest:null};

  if(latest.status==='SLEEPING'){
    return {runtimeState:sleepAllowed?'sleeping':'inactive',current:latest,latest};
  }
  if(['BUILDING','DEPLOYING','QUEUED','WAITING','NEEDS_APPROVAL','INITIALIZING'].includes(latest.status)){
    return {runtimeState:serving?'transitioning':'unknown',current:serving,latest};
  }
  if(latest.status==='SUCCESS'){
    return {runtimeState:'active',current:latest,latest};
  }
  if(['FAILED','CRASHED'].includes(latest.status)){
    return {runtimeState:serving?'active':'failed',current:serving??latest,latest};
  }
  if(['REMOVED','REMOVING','SKIPPED'].includes(latest.status)){
    return {runtimeState:serving?'active':'inactive',current:serving,latest};
  }
  return {runtimeState:'unknown',current:serving,latest};
}

export function railwayObservation(source,deployments){
  const {runtimeState,current,latest}=classifyRailway(deployments,source);
  const artifact=current?.meta?.commitHash;
  const branch=current?.meta?.branch;
  return {
    targetId:source.targetId,
    provider:'railway',
    runtimeState,
    healthState:'unknown',
    deploymentRef:current?.id??latest?.id??null,
    versionRef:cleanString(branch,128)?branch:null,
    artifactRef:SHA.test(artifact||'')?artifact:null,
    sourceRef:'railway:deployment:'+(current?.id??latest?.id??'unknown'),
    metadata:{
      latestAttemptStatus:latest?.status??'UNKNOWN',
      currentDeploymentStatus:current?.status??'UNKNOWN',
      projectId:source.projectId,
      environmentId:source.environmentId,
      serviceId:source.serviceId
    }
  };
}

export function supabaseObservation(source,project){
  const status=String(project?.status??'UNKNOWN').toUpperCase();
  let runtimeState='unknown',healthState='unknown';
  if(status==='ACTIVE_HEALTHY'){runtimeState='active';healthState='healthy'}
  else if(status.includes('UNHEALTHY')){runtimeState='active';healthState='unhealthy'}
  else if(['PAUSED','INACTIVE','REMOVED'].includes(status)){runtimeState='inactive'}
  else if(/COMING|RESTOR|UPDAT|RESTART|GOING/.test(status)){runtimeState='transitioning'}
  const version=project?.database?.version;
  return {
    targetId:source.targetId,
    provider:'supabase',
    runtimeState,
    healthState,
    deploymentRef:source.projectRef,
    versionRef:cleanString(version,128)?version:null,
    artifactRef:null,
    sourceRef:'supabase:project:'+source.projectRef+':'+status.toLowerCase(),
    metadata:{
      projectStatus:status,
      projectRef:source.projectRef,
      region:cleanString(project?.region,128)?project.region:null,
      postgresEngine:cleanString(project?.database?.postgres_engine,32)?project.database.postgres_engine:null
    }
  };
}

async function railwayDeployments(source,token){
  const query=`query deployments($input: DeploymentListInput!, $first: Int) {
    deployments(input: $input, first: $first) {
      edges { node { id status createdAt url meta } }
    }
  }`;
  const response=await fetch('https://backboard.railway.com/graphql/v2',{
    method:'POST',
    headers:{'Authorization':'Bearer '+token,'Content-Type':'application/json'},
    body:JSON.stringify({query,variables:{input:{projectId:source.projectId,serviceId:source.serviceId,environmentId:source.environmentId},first:10}})
  });
  if(!response.ok)fail('Railway HTTP '+response.status+' for '+source.targetId);
  const body=await response.json();
  if(Array.isArray(body.errors)&&body.errors.length)fail('Railway GraphQL error for '+source.targetId+': '+body.errors.map(e=>e.message).join('; '));
  const edges=body?.data?.deployments?.edges;
  if(!Array.isArray(edges))fail('Railway deployments missing for '+source.targetId);
  return edges.map(e=>e.node).filter(Boolean);
}

async function supabaseProject(source,token){
  const response=await fetch('https://api.supabase.com/v1/projects/'+encodeURIComponent(source.projectRef),{
    headers:{'Authorization':'Bearer '+token,'Accept':'application/json'}
  });
  if(!response.ok)fail('Supabase HTTP '+response.status+' for '+source.targetId);
  return response.json();
}

export async function collect({registry,railwayToken,supabaseToken,fetchProviders=true}){
  const failures=validateSources(registry);if(failures.length)fail(failures.join('; '));
  const observations=[];
  const providerStatus={
    railway:railwayToken?'configured':'credential_missing',
    supabase:supabaseToken?'configured':'credential_missing'
  };
  if(!fetchProviders)return {providerStatus,observations};

  for(const source of registry.sources){
    if(source.provider==='railway'){
      if(!railwayToken)continue;
      observations.push(railwayObservation(source,await railwayDeployments(source,railwayToken)));
    }else if(source.provider==='supabase'){
      if(!supabaseToken)continue;
      observations.push(supabaseObservation(source,await supabaseProject(source,supabaseToken)));
    }
  }

  for(const o of observations){
    if(!TARGET.test(o.targetId)||!['railway','supabase'].includes(o.provider))fail('invalid generated provider observation');
    if(!['active','sleeping','transitioning','inactive','failed','unknown'].includes(o.runtimeState))fail('invalid generated runtime state');
    if(!['healthy','degraded','unhealthy','unknown'].includes(o.healthState))fail('invalid generated health state');
    if(!cleanString(o.sourceRef,512))fail('invalid generated sourceRef');
    if(secretLike.test(JSON.stringify(o.metadata)))fail('secret-like generated metadata');
  }

  return {providerStatus,observations};
}

function selfTest(){
  const registry={contract:'shine-defence/estate-provider-sources-v1',version:'1.0.0',sources:[
    {targetId:'railway:test',provider:'railway',projectId:'11111111-1111-4111-8111-111111111111',environmentId:'22222222-2222-4222-8222-222222222222',serviceId:'33333333-3333-4333-8333-333333333333'},
    ...Array.from({length:19},(_,i)=>({targetId:'supabase:'+(String.fromCharCode(97+i%20)).repeat(20),provider:'supabase',projectRef:(String.fromCharCode(97+i%20)).repeat(20)}))
  ]};
  // The synthetic source set deliberately collides after 20 alphabet letters only if validation is wrong.
  const failures=validateSources(registry);
  if(failures.length)fail('source validation fixture failed: '+failures.join('; '));

  const source=registry.sources[0];
  const ok={id:'d1',status:'SUCCESS',createdAt:'2026-09-28T00:00:00.000Z',meta:{commitHash:'a'.repeat(40),branch:'main'}};
  const building={id:'d2',status:'BUILDING',createdAt:'2026-09-28T01:00:00.000Z',meta:{commitHash:'b'.repeat(40),branch:'main'}};
  const r=railwayObservation(source,[building,ok]);
  if(r.runtimeState!=='transitioning'||r.deploymentRef!=='d1'||r.artifactRef!=='a'.repeat(40))fail('Railway transition classification failed');

  const failed={id:'d3',status:'FAILED',createdAt:'2026-09-28T02:00:00.000Z',meta:{commitHash:'c'.repeat(40),branch:'main'}};
  const r2=railwayObservation(source,[failed,ok]);
  if(r2.runtimeState!=='active'||r2.deploymentRef!=='d1')fail('failed candidate must not erase serving Railway release');

  const s=supabaseObservation({targetId:'supabase:'+('z'.repeat(20)),projectRef:'z'.repeat(20)},{status:'ACTIVE_HEALTHY',region:'ap-southeast-2',database:{version:'17.6.1.166',postgres_engine:'17'}});
  if(s.runtimeState!=='active'||s.healthState!=='healthy')fail('Supabase healthy classification failed');

  console.log('SHINE DEFENCE ESTATE PROVIDER COLLECTOR SELF-TEST: PASS transition + failed-candidate fallback + Supabase health');
}

async function main(){
  const args=process.argv.slice(2);
  if(args.includes('--self-test'))return selfTest();
  const registry=JSON.parse(readFileSync(registryPath,'utf8'));
  const failures=validateSources(registry);
  if(failures.length)fail(failures.join('; '));
  if(args.includes('--validate-only')){
    console.log('SHINE DEFENCE ESTATE PROVIDER SOURCES: PASS '+registry.sources.length+' targets');
    return;
  }

  const outputArg=args.indexOf('--output');
  const outputPath=outputArg>=0?args[outputArg+1]:null;
  if(outputArg>=0&&!outputPath)fail('--output requires a path');

  const result=await collect({
    registry,
    railwayToken:process.env.SHINE_DEFENCE_RAILWAY_WORKSPACE_TOKEN||'',
    supabaseToken:process.env.SHINE_DEFENCE_SUPABASE_READ_TOKEN||''
  });

  const snapshot={
    contract:'shine-defence/provider-snapshot-v1',
    schemaVersion:'1.0.0',
    collectedAt:iso(),
    providerStatus:result.providerStatus,
    observations:result.observations
  };
  const bytes=JSON.stringify(snapshot,null,2)+'\n';
  if(outputPath)writeFileSync(outputPath,bytes);
  else process.stdout.write(bytes);
}

if(process.argv[1]&&import.meta.url===new URL('file://'+process.argv[1]).href){
  main().catch(error=>{console.error(String(error?.stack||error));process.exit(1)});
}
