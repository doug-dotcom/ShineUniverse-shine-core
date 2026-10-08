import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,readFile,writeFile,rm,cp,stat} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {resolve,dirname} from 'node:path';
import {pathToFileURL,fileURLToPath} from 'node:url';
import {execFileSync} from 'node:child_process';
import {buildPackage} from './build-v1.mjs';
const here=dirname(fileURLToPath(import.meta.url)),root=resolve(here,'../../..');
async function temporary(fn){const dir=await mkdtemp(resolve(tmpdir(),'vc-package-test-'));try{await fn(dir);}finally{await rm(dir,{recursive:true,force:true});}}
test('packed tarball imports through root export and refuses unconfigured reads',async()=>temporary(async dir=>{
 const out=resolve(dir,'package'),report=await buildPackage({outputDirectory:out});
 assert.equal(report.moduleCount,15);assert.equal(report.liveIntegrationVerified,false);
 const manifest=JSON.parse(await readFile(resolve(out,'package.json'),'utf8'));
 assert.equal(manifest.private,true);assert.deepEqual(manifest.scripts,{});assert.equal(manifest.dependencies,undefined);
 const packed=JSON.parse(execFileSync('npm',['pack','--ignore-scripts','--json','--pack-destination',dir],{cwd:out,encoding:'utf8'}))[0];
 assert.equal(packed.files.filter(f=>f.path.endsWith('.mjs')).length,15);
 assert.ok(packed.files.every(f=>!(/test|fixture|credential\.json|\.sql$/.test(f.path))));
 const extracted=resolve(dir,'consumer');await import('node:fs/promises').then(fs=>fs.mkdir(extracted));
 execFileSync('tar',['-xzf',resolve(dir,packed.filename),'-C',extracted]);
 await cp(resolve(extracted,'package'),resolve(extracted,'node_modules/@shine-foundation/veteran-care-server-read'),{recursive:true});
 const entry=resolve(extracted,'smoke.mjs');
 await writeFile(entry,"export {createVeteranCareServerReadEntryPoint,VETERAN_CARE_SERVER_READ_ADAPTERS} from '@shine-foundation/veteran-care-server-read';\n");
 const {createVeteranCareServerReadEntryPoint,VETERAN_CARE_SERVER_READ_ADAPTERS}=await import(pathToFileURL(entry));
 assert.equal(VETERAN_CARE_SERVER_READ_ADAPTERS.length,19);
 const gate=createVeteranCareServerReadEntryPoint();assert.equal(gate.configurationStatus,'blocked');
 const result=await gate.readSelectedMemory({});
 assert.equal(result.resultReturned,false);assert.equal(result.retrievalPerformed,false);
 assert.equal(result.modelDisclosurePermitted,false);assert.equal(result.memoryWritePermitted,false);
 assert.equal(result.transportPerformed,false);
 await assert.rejects(buildPackage({outputDirectory:out}),/output already exists/);
}));
test('producer drift fails before writing output',async()=>temporary(async dir=>{
 const source=resolve(dir,'source');await cp(resolve(root,'foundation'),resolve(source,'foundation'),{recursive:true});
 await writeFile(resolve(source,'foundation/onboarding/veteran-care-server-read-v1.mjs'),'// drift');
 const out=resolve(dir,'result');await assert.rejects(buildPackage({sourceRoot:source,outputDirectory:out}),/integrity mismatch/);
 await assert.rejects(stat(out),{code:'ENOENT'});
}));
test('missing closure module fails before writing output',async()=>temporary(async dir=>{
 const lock=JSON.parse(await readFile(resolve(here,'source-lock-v1.json'),'utf8'));
 lock.files=lock.files.filter(f=>!f.path.endsWith('veteran-care-capability-health-v1.mjs'));
 const lockPath=resolve(dir,'lock.json');await writeFile(lockPath,JSON.stringify(lock));
 const out=resolve(dir,'result');await assert.rejects(buildPackage({lockPath,outputDirectory:out}),/missing dependency/);
 await assert.rejects(stat(out),{code:'ENOENT'});
}));
test('source tree cannot be overwritten by a package build',async()=>{
 await assert.rejects(buildPackage({outputDirectory:resolve(root,'generated-package')}),/outside source tree/);
});
