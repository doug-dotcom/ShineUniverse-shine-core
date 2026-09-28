import fs from 'node:fs';
import process from 'node:process';

const registryPath='foundation/contracts/gateway-operation-registry-v1.json';
const handlerPath='foundation/gateway/http-handler-v1.mjs';

const registry=JSON.parse(fs.readFileSync(registryPath,'utf8'));
const handler=fs.readFileSync(handlerPath,'utf8');
const fail=message=>{ throw new Error(message); };

if(registry?.gatewayOperationRegistry!=='shine-foundation/gateway-operation-registry-v1'){
  fail('invalid Gateway operation registry contract');
}
if(registry?.schemaVersion!=='1.0.0') fail('unsupported Gateway operation registry schema');
if(!Array.isArray(registry.routes)||registry.routes.length<1) fail('Gateway operation registry has no routes');

const declared=[];
for(const match of handler.matchAll(/^const\s+([A-Za-z0-9_]+(?:Path|Match))=([^\n]+)$/gm)){
  declared.push({symbol:match[1],expr:match[2]});
}

const declaredSymbols=[...new Set(declared.map(x=>x.symbol))].sort();
const registrySymbols=registry.routes.map(x=>x.routeSymbol).sort();
if(JSON.stringify(declaredSymbols)!==JSON.stringify(registrySymbols)){
  const declaredSet=new Set(declaredSymbols);
  const registrySet=new Set(registrySymbols);
  const missing=declaredSymbols.filter(x=>!registrySet.has(x));
  const stale=registrySymbols.filter(x=>!declaredSet.has(x));
  fail('Gateway route registry drift: unregistered='+JSON.stringify(missing)+' stale='+JSON.stringify(stale));
}

const simplePathBySymbol=new Map();
for(const {symbol,expr} of declared){
  const m=expr.match(/p=>p==='([^']+)'\|\|p\.endsWith\('[^']+'\);?$/);
  if(m) simplePathBySymbol.set(symbol,m[1]);
}

const inferredMethod=new Map();
for(const match of handler.matchAll(/if\(request\.method==='(GET|POST)'&&([A-Za-z0-9_]+(?:Path|Match))\(url\.pathname\)\)/g)){
  inferredMethod.set(match[2],match[1]);
}
for(const line of handler.split('\n')){
  if(!line.includes('const is')) continue;
  for(const m of line.matchAll(/([A-Za-z0-9_]+Path)\(url\.pathname\)/g)){
    inferredMethod.set(m[1],'POST');
  }
}
if(handler.includes('const defenceMatch=defenceStatusMatch(url.pathname);')){
  inferredMethod.set('defenceStatusMatch','GET');
}

const seenSymbol=new Set();
const seenMethodPath=new Set();
for(const route of registry.routes){
  for(const field of ['routeSymbol','method','path','operationKey','riskClass','effectClass','authClass','controlMode']){
    if(typeof route[field]!=='string'||!route[field]) fail('route missing '+field+': '+JSON.stringify(route));
  }
  if(seenSymbol.has(route.routeSymbol)) fail('duplicate route symbol: '+route.routeSymbol);
  seenSymbol.add(route.routeSymbol);

  const key=route.method+' '+route.path;
  if(seenMethodPath.has(key)) fail('duplicate method/path: '+key);
  seenMethodPath.add(key);

  if(!['GET','POST'].includes(route.method)) fail('unsupported HTTP method: '+key);
  const inferred=inferredMethod.get(route.routeSymbol);
  if(!inferred) fail('cannot infer HTTP method for '+route.routeSymbol);
  if(inferred!==route.method) fail('HTTP method drift for '+route.routeSymbol+': handler='+inferred+' registry='+route.method);

  const simple=simplePathBySymbol.get(route.routeSymbol);
  if(simple&&simple!==route.path) fail('path drift for '+route.routeSymbol+': handler='+simple+' registry='+route.path);

  if(route.controlMode==='public-exempt'){
    if(route.effectClass!=='read'||route.authClass!=='public') fail('public exemption must be public read-only: '+key);
    if(!route.exemptionReason) fail('public exemption requires reason: '+key);
  }

  if(route.controlMode==='auth-only'&&route.effectClass!=='read'){
    fail('auth-only route cannot mutate: '+key);
  }

  if(route.effectClass!=='read'&&!route.controlRef){
    fail('mutating/executing route requires named control: '+key);
  }

  if(route.riskClass==='protected-execution'&&route.authClass==='public'){
    fail('protected execution cannot be public: '+key);
  }

  if(!['public-exempt','auth-only','service-guard','internal-worker','dependency-admission'].includes(route.controlMode)){
    fail('unknown control mode: '+route.controlMode+' for '+key);
  }
}

const summary={
  registry:registry.gatewayOperationRegistry,
  routeCount:registry.routes.length,
  publicExempt:registry.routes.filter(x=>x.controlMode==='public-exempt').length,
  authenticatedRead:registry.routes.filter(x=>x.controlMode==='auth-only').length,
  serviceGuard:registry.routes.filter(x=>x.controlMode==='service-guard').length,
  internalWorker:registry.routes.filter(x=>x.controlMode==='internal-worker').length,
  dependencyAdmission:registry.routes.filter(x=>x.controlMode==='dependency-admission').length
};

process.stdout.write(JSON.stringify(summary,null,2)+'\n');
