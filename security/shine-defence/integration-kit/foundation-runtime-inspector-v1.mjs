#!/usr/bin/env node
import {readFileSync,readdirSync,statSync} from 'node:fs';
import {join,relative} from 'node:path';
import {fileURLToPath} from 'node:url';

export const SHINE_DEFENCE_FOUNDATION_RUNTIME_INSPECTOR_VERSION='1.0.0';

const root=fileURLToPath(new URL('../../../',import.meta.url));

function walk(dir){
  const out=[];
  for(const name of readdirSync(dir)){
    const path=join(dir,name);
    const st=statSync(path);
    if(st.isDirectory())out.push(...walk(path));
    else out.push(path);
  }
  return out;
}

function read(path){return readFileSync(join(root,path),'utf8');}

function imports(text){
  const out=[];
  const re=/(?:from\s*|import\s*)['"]([^'"]+)['"]/g;
  let m;
  while((m=re.exec(text)))out.push(m[1]);
  return out;
}

function pinnedNpm(spec){
  return /^npm:(?:@[^/]+\/[^@]+|[^@]+)@\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?$/.test(spec);
}

export function inspectFoundationRuntime({repoRoot=root}={}){
  const runtimeDir=join(repoRoot,'foundation/runtime');
  const runtimeFiles=walk(runtimeDir).filter(path=>/\.(?:ts|mjs|js)$/.test(path));
  const findings=[];
  const allImports=[];

  for(const path of runtimeFiles){
    const text=readFileSync(path,'utf8');
    for(const spec of imports(text)){
      allImports.push({file:relative(repoRoot,path).replaceAll('\\','/'),spec});
      if(spec.startsWith('npm:')&&!pinnedNpm(spec)){
        findings.push({control:'dependencies',state:'fail',file:relative(repoRoot,path),reason:'unpinned-npm-import',spec});
      }
      if(spec.startsWith('jsr:')||spec.startsWith('http://')||spec.startsWith('https://')){
        findings.push({control:'dependencies',state:'fail',file:relative(repoRoot,path),reason:'unbounded-runtime-import',spec});
      }
    }
  }

  const gateway=readFileSync(join(repoRoot,'foundation/runtime/edge-function/index.ts'),'utf8');
  const navigator=readFileSync(join(repoRoot,'foundation/runtime/data-navigator/index.ts'),'utf8');
  const posture=readFileSync(join(repoRoot,'foundation/postgres/defence-operational-posture-v1.sql'),'utf8');

  const required=[
    ['auth',gateway.includes("set local role foundation_gateway"),'gateway-must-assume-foundation-gateway-role'],
    ['auth',gateway.includes('createFoundationRuntimeDefenceGateV1'),'gateway-must-compose-runtime-defence-gate'],
    ['auth',navigator.includes('effective_app_credentials')&&navigator.includes('sha256Hex'),'data-navigator-must-verify-hashed-app-credentials'],
    ['rls',posture.includes('integration_delegation_refresh_requests enable row level security'),'delegation-refresh-request-store-must-enable-rls'],
    ['service_to_service',posture.includes('shine_defence_runtime nologin nosuperuser nocreatedb nocreaterole nobypassrls'),'defence-runtime-role-must-be-least-privilege'],
    ['secrets',posture.includes('invalidCredentialHashes'),'posture-must-test-credential-hash-shape'],
    ['data_exposure',posture.includes('publicSchemaUsageGrants')&&posture.includes('publicTableGrants'),'posture-must-test-public-database-exposure'],
    ['deployment_integrity',posture.includes('get_service_deployment_truth_v1'),'posture-must-consume-foundation-deployment-truth']
  ];

  for(const [control,ok,reason] of required){
    if(!ok)findings.push({control,state:'fail',reason});
  }

  const npmImports=allImports.filter(x=>x.spec.startsWith('npm:'));
  const unpinnedNpmImports=npmImports.filter(x=>!pinnedNpm(x.spec));
  const remoteRuntimeImports=allImports.filter(x=>x.spec.startsWith('jsr:')||x.spec.startsWith('http://')||x.spec.startsWith('https://'));

  return {
    report:'shine-defence/foundation-runtime-inspection-v1',
    version:SHINE_DEFENCE_FOUNDATION_RUNTIME_INSPECTOR_VERSION,
    state:findings.some(x=>x.state==='fail')?'fail':'pass',
    controls:{
      auth:findings.filter(x=>x.control==='auth'),
      rls:findings.filter(x=>x.control==='rls'),
      serviceToService:findings.filter(x=>x.control==='service_to_service'),
      secrets:findings.filter(x=>x.control==='secrets'),
      dependencies:{
        state:unpinnedNpmImports.length||remoteRuntimeImports.length?'fail':'pass',
        npmImports,
        unpinnedNpmImports,
        remoteRuntimeImports
      },
      dataExposure:findings.filter(x=>x.control==='data_exposure'),
      deploymentIntegrity:findings.filter(x=>x.control==='deployment_integrity')
    },
    findings
  };
}

function main(){
  const report=inspectFoundationRuntime();
  if(process.argv.includes('--json'))process.stdout.write(JSON.stringify(report,null,2)+'\n');
  else console.log(`SHINE DEFENCE FOUNDATION RUNTIME INSPECTION: ${report.state.toUpperCase()} (${report.findings.length} findings)`);
  if(report.state!=='pass')process.exitCode=1;
}

if(process.argv[1]&&fileURLToPath(import.meta.url)===fileURLToPath(new URL('file://'+process.argv[1]))){
  main();
}
