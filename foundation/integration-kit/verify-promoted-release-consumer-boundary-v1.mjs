#!/usr/bin/env node
import {readdirSync,readFileSync,statSync} from 'node:fs';
import {join,relative,sep} from 'node:path';
import {fileURLToPath} from 'node:url';

const root=fileURLToPath(new URL('../../',import.meta.url));
const rawBindingToken='current_foundation_release_identity';
const extensions=new Set(['.sql','.mjs','.js','.ts']);

const allowlist=new Set([
  'foundation/postgres/foundation-release-identity-binding-v1.sql',
  'foundation/postgres/foundation-release-identity-reattestation-continuity-v1.sql',
  'foundation/postgres/foundation-readiness-drift-v1.sql',
  'foundation/postgres/foundation-scoped-remediation-executor-v1.sql',
  'foundation/postgres/foundation-release-projection-reconciliation-v1.sql'
]);

function extension(path){
  const i=path.lastIndexOf('.');
  return i<0?'':path.slice(i);
}

function walk(dir,out=[]){
  for(const name of readdirSync(dir)){
    if(name==='.git'||name==='node_modules') continue;
    const full=join(dir,name);
    const stat=statSync(full);
    if(stat.isDirectory()) walk(full,out);
    else out.push(full);
  }
  return out;
}

const violations=[];
for(const full of walk(root)){
  const rel=relative(root,full).split(sep).join('/');
  if(!extensions.has(extension(rel))) continue;
  if(rel.includes('.test.')) continue;
  if(rel.endsWith('/verify-promoted-release-consumer-boundary-v1.mjs')) continue;

  const source=readFileSync(full,'utf8');
  if(!source.includes(rawBindingToken)) continue;
  if(allowlist.has(rel)) continue;
  violations.push(rel);
}

if(violations.length){
  console.error(
    'Raw Foundation release binding consumed outside the control-plane allowlist:\n'
    +violations.map(path=>' - '+path).join('\n')
    +'\nDownstream production consumers must use '
    +'foundation.get_foundation_promoted_release_v1 / '
    +'foundation.assert_foundation_promoted_release_v1.'
  );
  process.exit(1);
}

console.log(
  'Foundation promoted-release consumer boundary verified: '
  +allowlist.size+' raw-binding control-plane files allowlisted; '
  +'no unapproved production consumers.'
);
