import {readFile} from 'node:fs/promises';
import {validateAppendageConnectionSpec} from './connection-spec-v1.mjs';

for(const name of ['travel-v1.json','dive-v1.json']){
  const spec=JSON.parse(await readFile(new URL('./examples/'+name,import.meta.url),'utf8'));
  validateAppendageConnectionSpec(spec);
  console.log('PASS '+name);
}
