import {readFile,mkdir,writeFile,stat} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {resolve,dirname,relative,sep} from 'node:path';
import {fileURLToPath} from 'node:url';

const here=dirname(fileURLToPath(import.meta.url));
const digest=(algorithm,data)=>createHash(algorithm).update(data).digest('hex');
const gitBlob=data=>digest('sha1',Buffer.concat([Buffer.from('blob '+data.length+'\0'),data]));
const inside=(root,path)=>{const rel=relative(root,path);return rel!==''&&!rel.startsWith('..'+sep)&&rel!=='..';};
export async function buildPackage({sourceRoot=resolve(here,'../../..'),outputDirectory,lockPath=resolve(here,'source-lock-v1.json')}={}){
  if(typeof outputDirectory!=='string'||!outputDirectory)throw new Error('explicit output directory required');
  const root=resolve(sourceRoot),out=resolve(outputDirectory);
  if(out===root||inside(root,out))throw new Error('output must be outside source tree');
  const lock=JSON.parse(await readFile(lockPath,'utf8'));
  if(lock.contract!=='shine-foundation/vc-server-package-source-lock-v1'||lock.schemaVersion!=='1.0.0'||!/^[0-9a-f]{40}$/.test(lock.sourceCommit)||!Array.isArray(lock.files)||!lock.files.length)throw new Error('invalid source lock');
  const files=new Map();
  for(const item of lock.files){
    if(!/^foundation\/(onboarding|runtime)\/[a-z0-9-]+\.mjs$/.test(item.path)||files.has(item.path))throw new Error('invalid or duplicate package path');
    const data=await readFile(resolve(root,item.path));
    if(digest('sha256',data)!==item.sha256||gitBlob(data)!==item.gitBlobSha)throw new Error('source integrity mismatch: '+item.path);
    files.set(item.path,data);
  }
  const entry='foundation/onboarding/veteran-care-server-read-v1.mjs';
  if(!files.has(entry))throw new Error('missing entry point');
  const visited=new Set(),queue=[entry];
  while(queue.length){
    const p=queue.pop();if(visited.has(p))continue;visited.add(p);
    const source=files.get(p)?.toString('utf8');if(!source)throw new Error('missing module: '+p);
    if(/\bimport\s*\(/.test(source))throw new Error('dynamic imports require explicit review');
    for(const match of source.matchAll(/(?:from\s*|import\s*)['"]([^'"]+)['"]/g)){
      const spec=match[1];if(spec.startsWith('node:'))continue;
      if(!spec.startsWith('.'))throw new Error('external dependency requires explicit review');
      const dep=relative(root,resolve(root,dirname(p),spec)).split(sep).join('/');
      if(!files.has(dep))throw new Error('missing dependency: '+dep);queue.push(dep);
    }
  }
  if(visited.size!==files.size)throw new Error('unreachable file in package');
  try{await stat(out);throw new Error('output already exists');}catch(error){if(error.code!=='ENOENT')throw error;}
  await mkdir(out,{recursive:true});
  for(const [p,data] of files){const dest=resolve(out,p);await mkdir(dirname(dest),{recursive:true});await writeFile(dest,data,{flag:'wx'});}
  const manifest={name:'@shine-foundation/veteran-care-server-read',version:'1.0.0',private:true,type:'module',engines:{node:'>=22'},exports:{'.':'./'+entry},files:['foundation/','source-lock-v1.json','README.md'],scripts:{},shineFoundation:{sourceCommit:lock.sourceCommit,liveIntegrationVerified:false,serverOnly:true}};
  await writeFile(resolve(out,'package.json'),JSON.stringify(manifest,null,2)+'\n',{flag:'wx'});
  await writeFile(resolve(out,'source-lock-v1.json'),JSON.stringify(lock,null,2)+'\n',{flag:'wx'});
  await writeFile(resolve(out,'README.md'),await readFile(resolve(here,'README.md')),{flag:'wx'});
  return Object.freeze({outputDirectory:out,moduleCount:files.size,sourceCommit:lock.sourceCommit,liveIntegrationVerified:false});
}
if(process.argv[1]&&resolve(process.argv[1])===fileURLToPath(import.meta.url)){
  if(process.argv.length!==3)throw new Error('usage: node build-v1.mjs /absolute/output/outside/source');
  console.log(JSON.stringify(await buildPackage({outputDirectory:process.argv[2]})));
}

