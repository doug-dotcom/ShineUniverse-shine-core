import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

export function loadVerifiedRuntimeBundle({repoRoot,artifactSha256,sourceCommit,mappings}){
  const registry=mappings??JSON.parse(readFileSync(fileURLToPath(new URL('../../../foundation/deployments/verified-runtime-bundles-v1.json',import.meta.url)),'utf8'));
  const binding=registry[artifactSha256.toLowerCase()];
  if(!binding)return null;
  if(binding.sourceCommit!==sourceCommit.toLowerCase())throw new Error('runtime-bundle-source-mismatch');
  const root=resolve(repoRoot);
  const path=resolve(root,binding.path);
  if(!path.startsWith(root+'/'))throw new Error('runtime-bundle-path-invalid');
  const bundle=JSON.parse(readFileSync(path,'utf8'));
  if(!Array.isArray(bundle.files)||bundle.files.length!==binding.fileCount)throw new Error('runtime-bundle-file-count-mismatch');
  const names=new Set();
  for(const file of bundle.files){
    if(typeof file.name!=='string'||typeof file.content!=='string'||file.name.startsWith('/')||file.name.includes(String.fromCharCode(92))||file.name.split('/').some(p=>!p||p==='.'||p==='..')||names.has(file.name))throw new Error('runtime-bundle-file-invalid');
    names.add(file.name);
  }
  const canonical=JSON.stringify(bundle.files.map(f=>[f.name,f.content]).sort((a,b)=>a[0].localeCompare(b[0])));
  if(createHash('sha256').update(canonical).digest('hex')!==binding.filesSha256)throw new Error('runtime-bundle-digest-mismatch');
  return bundle.files;
}
