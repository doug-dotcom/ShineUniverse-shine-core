const UUID=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const CLIENT=/^[a-z0-9][a-z0-9._:-]*$/;
const TOKEN=/^[a-z0-9][a-z0-9._:-]*$/;

const response=(kind,envelope,status,reasonCode,extra={})=>({
  conciergeResponse:kind,
  schemaVersion:'1.0.0',
  requestId:envelope?.requestId??null,
  status,
  reasonCode,
  ...extra
});

const fresh=(requestedAt,clock)=>{
  const t=Date.parse(requestedAt??'');
  const now=Date.parse(clock());
  return Number.isFinite(t)&&Number.isFinite(now)&&t>=now-10*60*1000&&t<=now+5*60*1000;
};

const requireAdapter=(adapters,name)=>{
  if(typeof adapters?.[name]!=='function') throw new TypeError('missing concierge adapter: '+name);
};

async function verifyPair(adapters,authContext,clientId){
  const client=await adapters.verifyIntegrationClient({authContext,claimedClientId:clientId});
  if(!client?.clientId) return {error:'integration-client-unverified'};
  if(client.clientId!==clientId) return {error:'integration-client-mismatch'};

  if(authContext?.delegationToken){
    const delegated=await adapters.verifyIntegrationDelegation({authContext,claimedClientId:clientId});
    if(!delegated?.shineId) return {error:'delegation-unverified'};
    if(delegated.clientId!==clientId) return {error:'delegation-client-mismatch'};
    return {
      client,
      identity:{
        shineId:delegated.shineId,
        providerId:'foundation-delegation',
        sessionId:delegated.sessionId
      }
    };
  }

  const identity=await adapters.verifyIntegrationIdentity({authContext});
  if(!identity?.shineId) return {error:'identity-unverified'};
  return {client,identity};
}

export function createConciergePlanService({adapters,clock=()=>new Date().toISOString()}={}){
  for(const n of ['verifyIntegrationClient','verifyIntegrationIdentity','verifyIntegrationDelegation','planConciergeRequest']) requireAdapter(adapters,n);

  return async function handle({envelope,authContext}={}){
    const kind='shine-concierge/plan-response-v1';
    const capabilities=envelope?.capabilityIds;
    if(!envelope||envelope.conciergePlan!=='shine-concierge/plan-v1'||
       envelope.schemaVersion!=='1.0.0'||!UUID.test(envelope.requestId??'')||
       !CLIENT.test(envelope.clientId??'')||!TOKEN.test(envelope.purpose??'')||
       !Array.isArray(capabilities)||capabilities.length<1||capabilities.length>20||
       capabilities.some(c=>!TOKEN.test(c??''))||
       new Set(capabilities).size!==capabilities.length||
       !fresh(envelope.requestedAt,clock)){
      return response(kind,envelope,'invalid','invalid-concierge-plan-request');
    }

    let verified;
    try{verified=await verifyPair(adapters,authContext,envelope.clientId)}
    catch{return response(kind,envelope,'unavailable','foundation-dependency-unavailable')}
    if(verified.error) return response(kind,envelope,'denied',verified.error);

    try{
      const plan=await adapters.planConciergeRequest({
        requestId:envelope.requestId,
        ownerShineId:verified.identity.shineId,
        clientId:envelope.clientId,
        purpose:envelope.purpose,
        capabilityIds:capabilities,
        occurredAt:clock()
      });
      if(!plan) return response(kind,envelope,'unavailable','concierge-plan-write-failed');
      return response(kind,envelope,'planned','concierge-plan-created',{plan});
    }catch(error){
      const message=String(error?.message??'');
      if(message.includes('integration-client-not-linked')){
        return response(kind,envelope,'denied','integration-client-not-linked');
      }
      if(message.includes('replay-conflict')){
        return response(kind,envelope,'invalid','concierge-plan-replay-conflict');
      }
      return response(kind,envelope,'unavailable','concierge-plan-write-failed');
    }
  };
}

export function createConciergeExecuteService({adapters,clock=()=>new Date().toISOString(),idFactory=()=>crypto.randomUUID()}={}){
  for(const n of [
    'verifyIntegrationClient','verifyIntegrationIdentity','verifyIntegrationDelegation',
    'gateConciergeExecution','invokeCapability','recordConciergeExecutionEvent',
    'getConciergeResumeState','recordConciergeStepCheckpoint','queueConciergeRetry'
  ]) requireAdapter(adapters,n);

  return async function handle({envelope,authContext}={}){
    const kind='shine-concierge/execute-response-v1';
    const inputs=envelope?.inputs;
    if(!envelope||envelope.conciergeExecute!=='shine-concierge/execute-v1'||
       envelope.schemaVersion!=='1.0.0'||!UUID.test(envelope.requestId??'')||
       !CLIENT.test(envelope.clientId??'')||
       (inputs!==undefined&&(!inputs||typeof inputs!=='object'||Array.isArray(inputs)))||
       !fresh(envelope.requestedAt,clock)){
      return response(kind,envelope,'invalid','invalid-concierge-execute-request');
    }

    let verified;
    try{verified=await verifyPair(adapters,authContext,envelope.clientId)}
    catch{return response(kind,envelope,'unavailable','foundation-dependency-unavailable')}
    if(verified.error) return response(kind,envelope,'denied',verified.error);

    let gate;
    try{
      gate=await adapters.gateConciergeExecution({
        eventId:idFactory(),
        requestId:envelope.requestId,
        ownerShineId:verified.identity.shineId,
        clientId:envelope.clientId,
        occurredAt:clock()
      });
    }catch(error){
      const message=String(error?.message??'');
      if(message.includes('not-found')) return response(kind,envelope,'invalid','concierge-request-not-found');
      if(message.includes('owner-mismatch')) return response(kind,envelope,'denied','concierge-request-owner-mismatch');
      if(message.includes('client-mismatch')) return response(kind,envelope,'denied','concierge-request-client-mismatch');
      return response(kind,envelope,'unavailable','concierge-execution-gate-failed');
    }

    if(!gate) return response(kind,envelope,'unavailable','concierge-execution-gate-failed');
    if(gate.status==='blocked'){
      let explanation=null;
      try{
        if(typeof adapters.explainConciergeDenial==='function'){
          explanation=await adapters.explainConciergeDenial({
            ownerShineId:verified.identity.shineId,
            requestId:envelope.requestId
          });
        }
      }catch{}
      return response(kind,envelope,'blocked',gate.reasonCode,{
        gate,
        ...(explanation?{explanation}:{})
      });
    }

    try{
      await adapters.recordConciergeExecutionEvent({
        eventId:idFactory(),
        requestId:envelope.requestId,
        ownerShineId:verified.identity.shineId,
        clientId:envelope.clientId,
        eventType:'execution-started',
        reasonCode:'concierge-execution-started',
        occurredAt:clock()
      });
    }catch{
      return response(kind,envelope,'unavailable','concierge-execution-audit-failed');
    }

    const steps=Array.isArray(gate?.plan?.steps)?gate.plan.steps:[];
    let resumeState=null;
    try{
      resumeState=await adapters.getConciergeResumeState({
        requestId:envelope.requestId,
        ownerShineId:verified.identity.shineId,
        clientId:envelope.clientId
      });
    }catch{}
    const checkpointByStep=new Map(
      (Array.isArray(resumeState?.steps)?resumeState.steps:[])
        .filter(s=>s?.completed===true&&s?.stepId)
        .map(s=>[String(s.stepId),s])
    );
    const results=[];
    for(const step of steps){
      const capabilityId=String(step?.capabilityId??'');
      const stepId=String(step?.stepId??'');
      const input=inputs?.[capabilityId]??{};
      const checkpoint=checkpointByStep.get(stepId);
      if(checkpoint){
        results.push({
          capabilityId,
          appId:step?.appId??null,
          status:'completed',
          reasonCode:'concierge-step-reused',
          result:checkpoint.result??{},
          reused:true
        });
        continue;
      }
      let outcome;
      try{
        outcome=await adapters.invokeCapability({
          capabilityId,
          requestId:stepId,
          input,
          context:{
            clientId:envelope.clientId,
            ownerShineId:verified.identity.shineId,
            purpose:String(gate?.plan?.purpose??''),
            conciergeRequestId:envelope.requestId
          },
          authContext
        });
      }catch{
        outcome={status:'failed',reasonCode:'capability-invocation-failed'};
      }

      results.push({
        capabilityId,
        appId:step?.appId??null,
        status:outcome?.status??'failed',
        reasonCode:outcome?.reasonCode??'capability-invocation-failed',
        ...(outcome?.result?{result:outcome.result}:{})
      });

      if(outcome?.status==='completed'){
        try{
          await adapters.recordConciergeStepCheckpoint({
            checkpointId:idFactory(),
            requestId:envelope.requestId,
            stepId,
            capabilityId,
            result:outcome?.result??{},
            completedAt:clock()
          });
        }catch{
          return response(kind,envelope,'unavailable','concierge-checkpoint-write-failed',{results});
        }
      }

      if(outcome?.status!=='completed'){
        const reason=outcome?.reasonCode??'capability-invocation-failed';
        const transientReasons=new Set([
          'capability-adapter-quarantined',
          'capability-endpoint-unavailable',
          'capability-endpoint-rejected',
          'capability-response-invalid',
          'capability-invocation-failed'
        ]);
        if(transientReasons.has(reason)){
          results[results.length-1]={
            ...results[results.length-1],
            transient:true,
            retryAfter:outcome?.retryAfter??null
          };
          continue;
        }

        try{
          await adapters.recordConciergeExecutionEvent({
            eventId:idFactory(),
            requestId:envelope.requestId,
            ownerShineId:verified.identity.shineId,
            clientId:envelope.clientId,
            eventType:'execution-failed',
            reasonCode:reason,
            occurredAt:clock()
          });
        }catch{}
        return response(kind,envelope,'failed',reason,{results});
      }
    }

    const completed=results.filter(r=>r.status==='completed');
    const transientFailures=results.filter(r=>r.status!=='completed'&&r.transient===true);

    if(transientFailures.length>0&&completed.length>0){
      try{
        await adapters.recordConciergeExecutionEvent({
          eventId:idFactory(),
          requestId:envelope.requestId,
          ownerShineId:verified.identity.shineId,
          clientId:envelope.clientId,
          eventType:'execution-completed',
          reasonCode:'concierge-execution-partial',
          occurredAt:clock()
        });
      }catch{
        return response(kind,envelope,'unavailable','concierge-execution-audit-failed',{results});
      }
      const retryTimes=transientFailures
        .map(r=>r.retryAfter)
        .filter(v=>typeof v==='string'&&Number.isFinite(Date.parse(v)))
        .map(v=>Date.parse(v));
      const nowMs=Date.parse(clock());
      const notBefore=new Date(
        retryTimes.length?Math.max(nowMs+30000,Math.min(...retryTimes)):nowMs+30000
      ).toISOString();
      let retry=null;
      try{
        retry=await adapters.queueConciergeRetry({
          retryJobId:idFactory(),eventId:idFactory(),requestId:envelope.requestId,
          ownerShineId:verified.identity.shineId,clientId:envelope.clientId,
          capabilityIds:transientFailures.map(r=>r.capabilityId),
          notBefore,
          expiresAt:new Date(nowMs+24*60*60*1000).toISOString(),
          reasonCode:'concierge-execution-partial',occurredAt:new Date(nowMs).toISOString()
        });
      }catch{}
      return response(kind,envelope,'partial','concierge-execution-partial',{
        results,
        completedCapabilities:completed.map(r=>r.capabilityId),
        unavailableCapabilities:transientFailures.map(r=>({
          capabilityId:r.capabilityId,
          reasonCode:r.reasonCode,
          retryAfter:r.retryAfter??null
        })),
        retry,
        synthesisReady:true,
        synthesisMustDisclosePartial:true
      });
    }

    if(transientFailures.length>0&&completed.length===0){
      try{
        await adapters.recordConciergeExecutionEvent({
          eventId:idFactory(),
          requestId:envelope.requestId,
          ownerShineId:verified.identity.shineId,
          clientId:envelope.clientId,
          eventType:'execution-failed',
          reasonCode:'concierge-specialists-temporarily-unavailable',
          occurredAt:clock()
        });
      }catch{}
      const retryTimes=transientFailures
        .map(r=>r.retryAfter)
        .filter(v=>typeof v==='string'&&Number.isFinite(Date.parse(v)))
        .map(v=>Date.parse(v));
      const nowMs=Date.parse(clock());
      const notBefore=new Date(
        retryTimes.length?Math.max(nowMs+30000,Math.min(...retryTimes)):nowMs+30000
      ).toISOString();
      let retry=null;
      try{
        retry=await adapters.queueConciergeRetry({
          retryJobId:idFactory(),eventId:idFactory(),requestId:envelope.requestId,
          ownerShineId:verified.identity.shineId,clientId:envelope.clientId,
          capabilityIds:transientFailures.map(r=>r.capabilityId),
          notBefore,
          expiresAt:new Date(nowMs+24*60*60*1000).toISOString(),
          reasonCode:'concierge-specialists-temporarily-unavailable',
          occurredAt:new Date(nowMs).toISOString()
        });
      }catch{}
      return response(kind,envelope,'unavailable','concierge-specialists-temporarily-unavailable',{
        results,
        unavailableCapabilities:transientFailures.map(r=>({
          capabilityId:r.capabilityId,
          reasonCode:r.reasonCode,
          retryAfter:r.retryAfter??null
        })),
        retry,
        synthesisReady:false,
        synthesisMustDisclosePartial:false
      });
    }

    try{
      await adapters.recordConciergeExecutionEvent({
        eventId:idFactory(),
        requestId:envelope.requestId,
        ownerShineId:verified.identity.shineId,
        clientId:envelope.clientId,
        eventType:'execution-completed',
        reasonCode:'concierge-execution-completed',
        occurredAt:clock()
      });
    }catch{
      return response(kind,envelope,'unavailable','concierge-execution-audit-failed',{results});
    }

    return response(kind,envelope,'completed','concierge-execution-completed',{
      results,
      synthesisReady:true,
      synthesisMustDisclosePartial:false
    });
  };
}


export function createConciergeSupersedeService({adapters,clock=()=>new Date().toISOString(),idFactory=()=>crypto.randomUUID()}={}){
  for(const n of [
    'verifyIntegrationClient','verifyIntegrationIdentity','verifyIntegrationDelegation',
    'cancelConciergeRequest'
  ]) requireAdapter(adapters,n);

  return async function handle({envelope,authContext}={}){
    const kind='shine-concierge/supersede-response-v1';
    if(!envelope||envelope.conciergeSupersede!=='shine-concierge/supersede-v1'||
       envelope.schemaVersion!=='1.0.0'||!UUID.test(envelope.requestId??'')||
       !UUID.test(envelope.supersededByRequestId??'')||
       envelope.requestId===envelope.supersededByRequestId||
       !CLIENT.test(envelope.clientId??'')||
       !fresh(envelope.requestedAt,clock)){
      return response(kind,envelope,'invalid','invalid-concierge-supersede-request');
    }

    let verified;
    try{verified=await verifyPair(adapters,authContext,envelope.clientId)}
    catch{return response(kind,envelope,'unavailable','foundation-dependency-unavailable')}
    if(verified.error) return response(kind,envelope,'denied',verified.error);

    try{
      const result=await adapters.cancelConciergeRequest({
        eventId:idFactory(),
        requestId:envelope.requestId,
        ownerShineId:verified.identity.shineId,
        clientId:envelope.clientId,
        reasonCode:'superseded-by-newer-request',
        occurredAt:clock()
      });
      if(!result?.status) return response(kind,envelope,'unavailable','concierge-supersede-write-failed');
      const status=result.status==='cancelled'?'superseded':
        result.status==='already-cancelled'?'already-superseded':
        result.status;
      return response(kind,envelope,status,result.reasonCode??'superseded-by-newer-request',{
        supersededRequestId:envelope.requestId,
        supersededByRequestId:envelope.supersededByRequestId,
        cancelledAt:result.cancelledAt??null
      });
    }catch(error){
      const message=String(error?.message??'');
      if(message.includes('not-found')) return response(kind,envelope,'invalid','concierge-request-not-found');
      if(message.includes('owner-mismatch')) return response(kind,envelope,'denied','concierge-request-owner-mismatch');
      if(message.includes('client-mismatch')) return response(kind,envelope,'denied','concierge-request-client-mismatch');
      return response(kind,envelope,'unavailable','concierge-supersede-write-failed');
    }
  };
}
