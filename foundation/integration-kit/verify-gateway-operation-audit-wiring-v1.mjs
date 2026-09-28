import fs from 'node:fs';

const handler=fs.readFileSync('foundation/gateway/http-handler-v1.mjs','utf8');
const runtime=fs.readFileSync('foundation/runtime/supabase-runtime-adapters-v1.mjs','utf8');
const edge=fs.readFileSync('foundation/runtime/edge-function/index.ts','utf8');

const need=(condition,message)=>{
  if(!condition) throw new Error(message);
};

need(runtime.includes('async recordGatewayOperationAuditEvent'),
  'runtime adapter missing recordGatewayOperationAuditEvent');
need(runtime.includes('foundation.record_gateway_operation_audit_event_v1'),
  'runtime adapter is not wired to hosted audit recorder');

need(handler.includes('recordOperationAudit'),
  'HTTP handler missing operation audit callback');
need(handler.includes('operationAuditRequired=false'),
  'HTTP handler missing operation audit required flag');
need(handler.includes("phase:'policy'"),
  'HTTP handler missing pre-execution policy audit');
need(handler.includes("phase:'outcome'"),
  'HTTP handler missing outcome audit');
need(handler.includes("error:'operation-audit-unavailable'"),
  'HTTP handler does not fail closed when pre-execution audit is unavailable');

const policyAudit=handler.indexOf("phase:'policy'");
const policyDeny=handler.indexOf("if(policyState==='deny')");
need(policyAudit>=0&&policyDeny>=0&&policyAudit<policyDeny,
  'policy audit must occur before policy denial/route execution');

const outcomeAudit=handler.indexOf("phase:'outcome'");
const responseJson=handler.indexOf('return json(status,body);');
need(outcomeAudit>=0&&responseJson>=0&&outcomeAudit<responseJson,
  'outcome audit must be attempted before the HTTP response is returned');

need(edge.includes('recordOperationAudit:adapters.recordGatewayOperationAuditEvent'),
  'production Edge does not wire operation audit recorder');
need(edge.includes('operationAuditRequired:true'),
  'production Edge does not require operation audit');

process.stdout.write(JSON.stringify({
  verifier:'shine-foundation/gateway-operation-audit-wiring-v1',
  schemaVersion:'1.0.0',
  runtimeAdapter:true,
  policyBeforeExecution:true,
  outcomeAppend:true,
  productionRequired:true
},null,2)+'\n');
