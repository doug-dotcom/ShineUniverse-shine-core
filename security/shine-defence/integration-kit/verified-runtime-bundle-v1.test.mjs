import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,readFileSync,writeFileSync,mkdirSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {loadVerifiedRuntimeBundle} from './verified-runtime-bundle-v1.mjs';
import {inspectFoundationRuntime} from './foundation-runtime-inspector-v1.mjs';
const artifact='9ad0189be337a91ca90b3c278d0a274a445cdbacd976f9935753d4b151e3e565';
const source='b135f80d07bc1bafd8266c1bd1e510fa84a4b22d';
const registry=JSON.parse(readFileSync('foundation/deployments/verified-runtime-bundles-v1.json','utf8'));
const load=(extra={})=>loadVerifiedRuntimeBundle({repoRoot:process.cwd(),artifactSha256:artifact,sourceCommit:source,...extra});
test('verified archive resolves all 31 deployed files',()=>assert.equal(load().length,31));
test('source mismatch refuses artifact reuse',()=>assert.throws(()=>load({sourceCommit:'a'.repeat(40)}),/source-mismatch/));
test('unknown artifacts preserve legacy inspection',()=>assert.equal(load({artifactSha256:'b'.repeat(64)}),null));
test('altered expected digest refuses archive',()=>{const mappings=structuredClone(registry);mappings[artifact].filesSha256='0'.repeat(64);assert.throws(()=>load({mappings}),/digest-mismatch/)});
test('archive path traversal is refused',()=>{const mappings=structuredClone(registry);mappings[artifact].path='../outside.json';assert.throws(()=>load({mappings}),/path-invalid/)});
test('backslashes in bundle filenames are refused',()=>{
 const root=mkdtempSync(join(tmpdir(),'foundation-bundle-'));
 try{mkdirSync(join(root,'foundation/releases'),{recursive:true});const bundle=JSON.parse(readFileSync(registry[artifact].path,'utf8'));bundle.files[1].name='bad'+String.fromCharCode(92)+'path.mjs';writeFileSync(join(root,registry[artifact].path),JSON.stringify(bundle));assert.throws(()=>load({repoRoot:root}),/file-invalid/)}finally{rmSync(root,{recursive:true,force:true})}
});
test('archive duplicates and changed file counts are refused',()=>{
 const root=mkdtempSync(join(tmpdir(),'foundation-bundle-'));
 try{mkdirSync(join(root,'foundation/releases'),{recursive:true});const bundle=JSON.parse(readFileSync(registry[artifact].path,'utf8'));
 const path=join(root,registry[artifact].path);
 bundle.files[1].name=bundle.files[0].name;writeFileSync(path,JSON.stringify(bundle));
 assert.throws(()=>load({repoRoot:root}),/file-invalid/);
 bundle.files.pop();writeFileSync(path,JSON.stringify(bundle));assert.throws(()=>load({repoRoot:root}),/file-count-mismatch/);
 }finally{rmSync(root,{recursive:true,force:true})}
});
test('inspector checks dependency imports inside deployed gateway modules',()=>{
 const deployedFiles=load();deployedFiles.find(f=>f.name==='foundation/gateway/gateway-core-v1.mjs').content+="\nimport x from 'npm:unsafe@latest';";
 const report=inspectFoundationRuntime({repoRoot:process.cwd(),deployedFiles});
 assert.equal(report.state,'fail');assert.equal(report.controls.dependencies.unpinnedNpmImports.length,1);
});
test('missing deployed entrypoint cannot fall back to repository source',()=>assert.throws(()=>inspectFoundationRuntime({repoRoot:process.cwd(),deployedFiles:load().filter(f=>!f.name.endsWith('edge-function/index.ts'))}),/entrypoint-missing/));
