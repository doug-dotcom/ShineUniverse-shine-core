import fs from 'node:fs';

const handler=fs.readFileSync('foundation/gateway/http-handler-v1.mjs','utf8');
const runtime=fs.readFileSync('foundation/runtime/supabase-runtime-adapters-v1.mjs','utf8');
const index=fs.readFileSync('foundation/runtime/edge-function/index.ts','utf8');
const registry=JSON.parse(fs.readFileSync('foundation/contracts/gateway-operation-registry-v1.json','utf8'));

const fail=message=>{throw new Error(message)};

if(!handler.includes("operationPolicyRequired")){
  fail('HTTP handler does not expose required operation policy mode');
}
if(!handler.includes("evaluateOperationPolicy({")){
  fail('HTTP handler does not evaluate operation policy for POST routes');
}
if(!handler.includes("policyState==='deny'")){
  fail('HTTP handler does not fail denied operation policy closed');
}
if(!handler.includes("policyState==='unavailable'")){
  fail('HTTP handler does not fail unavailable operation policy closed');
}

if(!runtime.includes('async evaluateGatewayRoutePolicy(')){
  fail('runtime adapter does not expose evaluateGatewayRoutePolicy');
}
if(!runtime.includes('foundation.evaluate_gateway_route_policy_v1(')){
  fail('runtime adapter is not backed by the hosted route policy broker');
}

if(!index.includes('evaluateOperationPolicy:adapters.evaluateGatewayRoutePolicy')){
  fail('Edge composition does not wire the route policy broker');
}
if(!index.includes('operationPolicyRequired:true')){
  fail('Edge composition does not require route policy enforcement');
}

const privileged=registry.routes.filter(route=>route.effectClass!=='read');
if(privileged.length!==23){
  fail('unexpected privileged route count: '+privileged.length);
}
const workerOnly=privileged.filter(route=>route.controlMode==='internal-worker');
if(workerOnly.length!==2){
  fail('unexpected worker-only route count: '+workerOnly.length);
}

process.stdout.write(JSON.stringify({
  verifier:'shine-foundation/gateway-policy-wiring-v1',
  privilegedRoutes:privileged.length,
  workerOnlyRoutes:workerOnly.length,
  frontDoorPolicyRequired:true
},null,2)+'\n');
