import {createVeteranCareFreshPermissionEvaluator} from './veteran-care-permission-freshness-v1.mjs';
const UUID=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const unavailable=()=>({status:'unavailable',decision:'deny',reasonCode:'vc-audit-not-confirmed',executionPerformed:false,auditRecorded:false});

// Server-only permission-observation audit, not a record of data delivery.
// writeAuditEvent must acknowledge durable recording of this exact event ID.
// Consumer must recheck authority at execution after this asynchronous write.
export function createVeteranCareAuditedPermissionEvaluator({writeAuditEvent,auditIdFactory=()=>crypto.randomUUID(),auditClock=()=>Date.now(),...options}={}){
  if(typeof writeAuditEvent!=='function'||typeof auditIdFactory!=='function'||typeof auditClock!=='function')throw new TypeError('audit sink, server ID and clock required');
  const evaluate=createVeteranCareFreshPermissionEvaluator(options);
  const appId=options.appId;
  return async function auditedEvaluate(input){
    let eventId;
    try{eventId=auditIdFactory();if(typeof eventId!=='string'||!UUID.test(eventId))return unavailable();eventId=eventId.toLowerCase();}catch{return unavailable();}
    const result=await evaluate(input);
    try{
      const now=auditClock();
      if(!Number.isSafeInteger(now)||now<0)return unavailable();
      // Explicit projection: never spread input, result, request, context or errors.
      const observedOutcome=result.decision==='allow'?'permission-allowed':result.status==='unavailable'?'authority-unavailable':'permission-denied';
      const event=Object.freeze({event:'shine-foundation/veteran-care-permission-audit-v1',schemaVersion:'1.0.0',
        eventId,appId,occurredAt:new Date(now).toISOString(),stage:'permission-evaluation',observedOutcome,
        executionPerformed:false,disclosureVerified:false});
      const ack=await writeAuditEvent(event);
      if(!ack||Object.getPrototypeOf(ack)!==Object.prototype)return unavailable();
      const d=Object.getOwnPropertyDescriptors(ack);
      if(!Object.hasOwn(d,'status')||!Object.hasOwn(d.status,'value')||d.status.value!=='recorded'||
        !Object.hasOwn(d,'eventId')||!Object.hasOwn(d.eventId,'value')||d.eventId.value!==eventId)return unavailable();
      return {...result,auditRecorded:true,auditEventId:eventId};
    }catch{return unavailable();}
  };
}
