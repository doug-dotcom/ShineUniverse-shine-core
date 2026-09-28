#!/usr/bin/env node
import {createHash} from 'node:crypto';
import {readFileSync,writeFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {inspectFoundationRuntime,SHINE_DEFENCE_FOUNDATION_RUNTIME_INSPECTOR_VERSION} from './foundation-runtime-inspector-v1.mjs';

const arg=(name)=>{
  const i=process.argv.indexOf(name);
  return i>=0?process.argv[i+1]:null;
};
const required=(name)=>{
  const value=arg(name);
  if(!value)throw new Error(name+' is required');
  return value;
};
const sha40=/^[a-f0-9]{40}$/i;
const sha64=/^[a-f0-9]{64}$/i;
const service=/^[a-z0-9][a-z0-9._:-]*$/;
const env=/^[a-z0-9][a-z0-9._-]*$/;

const repoRoot=resolve(required('--repo-root'));
const output=required('--output');
const serviceId=required('--service');
const environment=required('--environment');
const artifactSha256=required('--artifact');
const sourceCommit=required('--source-commit');
const policyCommit=required('--policy-commit');

if(!service.test(serviceId))throw new Error('invalid service id');
if(!env.test(environment))throw new Error('invalid environment');
if(!sha64.test(artifactSha256))throw new Error('invalid artefact sha256');
if(!sha40.test(sourceCommit)||!sha40.test(policyCommit))throw new Error('invalid commit sha');

const report=inspectFoundationRuntime({repoRoot});
const reportBytes=JSON.stringify(report,null,2)+'\n';
const reportSha256=createHash('sha256').update(reportBytes).digest('hex');
const authStatus=Array.isArray(report.controls?.auth)&&report.controls.auth.length===0?'pass':'fail';
const dependenciesStatus=report.controls?.dependencies?.state==='pass'?'pass':'fail';

const summary={
  contract:'shine-defence/reattestation-submission-v1',
  schemaVersion:'1.0.0',
  serviceId,
  environment,
  artifactSha256:artifactSha256.toLowerCase(),
  sourceCommit:sourceCommit.toLowerCase(),
  policyCommit:policyCommit.toLowerCase(),
  inspectorVersion:SHINE_DEFENCE_FOUNDATION_RUNTIME_INSPECTOR_VERSION,
  reportState:report.state,
  reportSha256,
  authStatus,
  dependenciesStatus,
  summary:{
    findingCount:Array.isArray(report.findings)?report.findings.length:0,
    npmImportCount:Array.isArray(report.controls?.dependencies?.npmImports)?report.controls.dependencies.npmImports.length:0,
    unpinnedNpmImportCount:Array.isArray(report.controls?.dependencies?.unpinnedNpmImports)?report.controls.dependencies.unpinnedNpmImports.length:0,
    remoteRuntimeImportCount:Array.isArray(report.controls?.dependencies?.remoteRuntimeImports)?report.controls.dependencies.remoteRuntimeImports.length:0
  }
};

writeFileSync(output,JSON.stringify(summary,null,2)+'\n');
const reportOutput=arg('--report-output');
if(reportOutput)writeFileSync(reportOutput,reportBytes);

console.log('SHINE DEFENCE REATTESTATION INSPECTION:',JSON.stringify({
  serviceId,
  environment,
  artifactSha256:summary.artifactSha256,
  sourceCommit:summary.sourceCommit,
  policyCommit:summary.policyCommit,
  reportState:summary.reportState,
  authStatus,
  dependenciesStatus,
  reportSha256
}));

if(authStatus!=='pass'||dependenciesStatus!=='pass'||report.state!=='pass')process.exitCode=1;
