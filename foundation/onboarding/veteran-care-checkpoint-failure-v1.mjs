import {createVeteranCareResumeRecheckGate} from './veteran-care-resume-recheck-v1.mjs';
const fields=['checkpointId','foundationAppId','ownerShineId','operationId','taskId','memoryId','memoryVersion','preparationId','stage','status','revision','validUntil'];
function capture(v){
  if(!v||Object.getPrototypeOf(v)!==Object.prototype)throw new TypeError();
  const d=Object.getOwnPropertyDescriptors(v);
  if(Reflect.ownKeys(d).length!==fields.length||fields.some(k=>!Object.hasOwn(d,k)||!Object.hasOwn(d[k],'value')))throw new TypeError();
  return Object.freeze(Object.fromEntries(fields.map(k=>[k,d[k].value])));
}
const same=(a,b)=>fields.every(k=>a[k]===b[k]);
const fail=(status,read=false,attempted=false)=>({status,reasonCode:'vc-checkpoint-not-confirmed',retrievalPerformed:read,checkpointWriteAttempted:attempted,durableProgressConfirmed:false,writeOutcome:attempted?'unconfirmed':'not-attempted',resultReturned:false,resumePermitted:false,modelDisclosurePermitted:false});
// A commit acknowledgement is not permission. Even a confirmed checkpoint must
// enter the fresh layer-32 resume gate. Ambiguous writes are never auto-retried.
export function createVeteranCareCheckpointFailureGate({commitResumeCheckpoint,getCurrentResumeCheckpoint,checkpointClock=()=>Date.now(),readSelectedMemory,...options}={}){
  if([commitResumeCheckpoint,getCurrentResumeCheckpoint,checkpointClock,readSelectedMemory].some(f=>typeof f!=='function'))throw new TypeError('atomic checkpoint commit and authoritative readback required');
  createVeteranCareResumeRecheckGate({...options,getCurrentResumeCheckpoint,readSelectedMemory});
  return async function checkpoint(input){
    let first,query,performed=false,attempted=false;
    try{
      let last=checkpointClock();if(!Number.isSafeInteger(last)||last<0)throw new TypeError();
      const now=()=>{const t=checkpointClock();if(!Number.isSafeInteger(t)||t<last)throw new TypeError();last=t;return t;};
      const resume=createVeteranCareResumeRecheckGate({...options,getCurrentResumeCheckpoint:async q=>{
        const row=capture(await getCurrentResumeCheckpoint(q));if(!first){first=row;query=q;}return row;
      },readSelectedMemory:async q=>{performed=true;return readSelectedMemory(q);}});
      const result=await resume(input);
      if(result.status!=='resume-rechecked-result')return fail(result.status,performed);
      if(first.revision>=Number.MAX_SAFE_INTEGER)return fail('denied',performed);
      const candidate=Object.freeze({...first,revision:first.revision+1,validUntil:result.checkpoint.validUntil});
      if(now()>=Date.parse(candidate.validUntil))return fail('denied',performed);
      attempted=true;
      const ack=await commitResumeCheckpoint(Object.freeze({expectedRevision:first.revision,checkpoint:candidate}));
      if(!ack||Object.getPrototypeOf(ack)!==Object.prototype)throw new TypeError();
      const d=Object.getOwnPropertyDescriptors(ack);
      if(Reflect.ownKeys(d).length!==2||!Object.hasOwn(d.status??{},'value')||!Object.hasOwn(d.checkpoint??{},'value')||d.status.value!=='committed'||!same(candidate,capture(d.checkpoint.value)))return fail('unavailable',performed,attempted);
      const stored=capture(await getCurrentResumeCheckpoint(query));
      if(!same(candidate,stored)||now()>=Date.parse(candidate.validUntil))return fail('unavailable',performed,attempted);
      return {contract:'shine-foundation/veteran-care-checkpoint-save-result-v1',status:'checkpoint-confirmed',retrievalPerformed:performed,checkpointWriteAttempted:true,
        durableProgressConfirmed:true,writeOutcome:'confirmed',checkpoint:Object.freeze({checkpointId:candidate.checkpointId,revision:candidate.revision,stage:candidate.stage,validUntil:candidate.validUntil}),
        resultReturned:false,resumePermitted:false,modelDisclosurePermitted:false,requiresFreshResumeCheck:true};
    }catch{return fail('unavailable',performed,attempted);}
  };
}
