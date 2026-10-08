import {createVeteranCareAIDecisionBuilder} from './veteran-care-ai-decision-v1.mjs';
const UUID=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
const toolId='veteran-care.selected_record_read';
function capture(v,keys){
  if(!v||Object.getPrototypeOf(v)!==Object.prototype)throw new TypeError();
  const d=Object.getOwnPropertyDescriptors(v);
  if(Reflect.ownKeys(d).length!==keys.length||keys.some(k=>!Object.hasOwn(d,k)||!Object.hasOwn(d[k],'value')))throw new TypeError();
  return Object.freeze(Object.fromEntries(keys.map(k=>[k,d[k].value])));
}
const refuse=(status='denied')=>({status,reasonCode:'vc-ai-tool-authority-unverified',executionPermitted:false,toolInvoked:false});
// Foundation validates proposed tool scope. AI owns independently authenticated
// proposal correlation and its current tool policy. No model text is authority.
export function createVeteranCareAIToolAuthorityEvaluator({getCurrentAIToolPolicy,resolveVerifiedAIToolProposal,toolClock=()=>Date.now(),...options}={}){
  if([getCurrentAIToolPolicy,resolveVerifiedAIToolProposal,toolClock].some(f=>typeof f!=='function'))throw new TypeError('current AI policy and verified proposal authority required');
  const build=createVeteranCareAIDecisionBuilder(options);
  return async function evaluate(input){
    let authContext,aiCallerProof,purposeContext,toolCall;
    try{
      const q=capture(input,['authContext','aiCallerProof','purposeContext','toolCall']);
      authContext=capture(q.authContext,['appToken','jwt']);aiCallerProof=capture(q.aiCallerProof,['proofRef']);purposeContext=capture(q.purposeContext,['preparationId']);
      const t=capture(q.toolCall,['toolCallId','toolId','arguments']),args=capture(t.arguments,['recordId','recordVersion']);
      if(typeof t.toolCallId!=='string'||!UUID.test(t.toolCallId)||t.toolId!==toolId||typeof args.recordId!=='string'||!UUID.test(args.recordId)||!Number.isSafeInteger(args.recordVersion)||args.recordVersion<1)throw new TypeError();
      toolCall=Object.freeze({...t,arguments:args});
      if([...Object.values(authContext),aiCallerProof.proofRef,purposeContext.preparationId].some(v=>typeof v!=='string'))throw new TypeError();
    }catch{return refuse();}
    try{
      const started=toolClock();if(!Number.isSafeInteger(started)||started<0)throw new TypeError();
      const decisionInput=Object.freeze({authContext,aiCallerProof,purposeContext,request:Object.freeze({capabilityId:toolId,input:toolCall.arguments})});
      const first=await build(decisionInput);if(first.status!=='decision-ready')return refuse(first.status);
      const e=first.envelope,query=Object.freeze({foundationAppId:e.foundationAppId,aiCallerId:e.aiCallerId,actorShineId:e.actorShineId,toolId});
      const p=capture(await getCurrentAIToolPolicy(query),['status','foundationAppId','aiCallerId','targetServiceAppId','toolId','capabilityId','scope','operation','purpose','policyRevision','validUntil']);
      if(p.status!=='active'||p.foundationAppId!==e.foundationAppId||p.aiCallerId!==e.aiCallerId||p.targetServiceAppId!==e.audience||p.toolId!==toolId||p.capabilityId!==e.capabilityId||p.scope!==e.scope||p.operation!==e.operation||p.purpose!==e.purpose||!Number.isSafeInteger(p.policyRevision)||p.policyRevision<1||typeof p.validUntil!=='string'||!Number.isSafeInteger(Date.parse(p.validUntil)))return refuse();
      const proofQuery=Object.freeze({...query,callerProofRef:e.callerProofRef,keyId:e.keyId,toolCallId:toolCall.toolCallId,recordId:e.resourceId,recordVersion:e.resourceVersion,preparationId:e.preparationId});
      const proof=capture(await resolveVerifiedAIToolProposal(proofQuery),['verified',...Object.keys(proofQuery)]);
      if(proof.verified!==true||Object.keys(proofQuery).some(k=>proof[k]!==proofQuery[k]))return refuse();
      const final=await build(decisionInput);if(final.status!=='decision-ready')return refuse(final.status);
      if(Object.keys(e).filter(k=>k!=='requestId').some(k=>e[k]!==final.envelope[k]))return refuse();
      const finalPolicy=capture(await getCurrentAIToolPolicy(query),Object.keys(p));
      if(Object.keys(p).some(k=>p[k]!==finalPolicy[k]))return refuse();
      const now=toolClock(),deadline=Math.min(Date.parse(e.validUntil),Date.parse(p.validUntil));
      if(!Number.isSafeInteger(now)||now<started||now>=deadline)return refuse();
      return {status:'tool-scope-approved',executionPermitted:false,toolInvoked:false,modelDisclosurePermitted:false,
        envelope:Object.freeze({...final.envelope,contract:'shine-foundation/veteran-care-ai-tool-authority-v1',schemaVersion:'1.0.0',
          contractDecision:final.envelope.contract,toolCallId:toolCall.toolCallId,toolId,toolPolicyRevision:p.policyRevision,validUntil:new Date(deadline).toISOString(),executionPermitted:false,toolInvoked:false,modelDisclosurePermitted:false,requiresFreshExecutionCheck:true})};
    }catch{return refuse('unavailable');}
  };
}
