#!/usr/bin/env node
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';

const registry=JSON.parse(readFileSync(new URL('../object-registry-v1.json',import.meta.url),'utf8'));
const root=new URL('../../',import.meta.url);
const gitBlobSha=bytes=>createHash('sha1').update(Buffer.from('blob '+bytes.length+'\0')).update(bytes).digest('hex');
const declaredVersion=value=>{
  if(typeof value.version==='string') return value.version;
  if(typeof value.schemaVersion==='string') return value.schemaVersion;
  if(typeof value?.properties?.schemaVersion?.const==='string') return value.properties.schemaVersion.const;
  return undefined;
};
const failures=[];
const ids=new Set();
const paths=new Set();

for(const entry of registry.entries){
  if(ids.has(entry.id)||paths.has(entry.path)){
    failures.push(entry.id+': duplicate registry identity');
    continue;
  }
  ids.add(entry.id);
  paths.add(entry.path);

  let bytes;
  try{
    bytes=readFileSync(new URL(entry.path,root));
  }catch{
    failures.push(entry.id+': missing '+entry.path);
    continue;
  }

  const sha=gitBlobSha(bytes);
  if(sha!==entry.blobSha){
    failures.push(entry.id+': blob drift '+sha+' != '+entry.blobSha);
  }

  if(entry.path.endsWith('.json')){
    try{
      const value=JSON.parse(bytes.toString('utf8'));
      const version=declaredVersion(value);
      if(version!==entry.version){
        failures.push(entry.id+': version drift '+version+' != '+entry.version);
      }
    }catch{
      failures.push(entry.id+': invalid JSON');
    }
  }
}

if(failures.length){
  for(const failure of failures) console.error('FAIL '+failure);
  process.exit(1);
}

console.log('SHINE FOUNDATION OBJECT REGISTRY: PASS '+registry.entries.length+' canonical schemas');
