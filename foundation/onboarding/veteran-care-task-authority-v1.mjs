import {createVeteranCareSessionIdentityVerifier} from './veteran-care-session-v1.mjs';
import {createVeteranCareResultAudienceGate} from './veteran-care-result-audience-v1.mjs';
const UUID=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
const fields=['taskId','foundationAppId','ownerShineId','memoryId','memoryVersion','preparationId','purpose','operation','status','revision','validUntil'];
function capture(v,keys){
  if(!v||Object.getPrototypeOf(v)!==Object.prototype)throw new TypeError();
  const d=Object.getOwnPropertyDescriptors(v);
  if(Reflect.ownKeys(d).length!==keys.length||keys.some(k=>!Object.hasOwn(d,k)||!Object.hasOwn(d[k],'value')))throw new TypeError();
  return Object.freeze(Object.fromEntries(keys.map(k=>[k,d[k].value])));
}
const deny=(status='denied',retrievalPerformed=false)=>({status,reasonCode:'vc-task-authority-unverified',retrievalPerformed,resultReturned:false,modelDisclosurePermitted:false});
// Consumers supply current durable task authority. Never reuse a queued task
// snapshot as authority for a new read, retry, resume or disclosure.
export function createVeteranCareTaskAuthorityGate({getCurrentVCTask,readSelectedMemory,taskClock=()=>Date.now(),...options}={}){
  if(options.appId!=='shine.veteran-care'||[getCurrentVCTask,readSelectedMemory,taskClock].some(f=>typeof f!=='function'))throw new TypeError('current VC task authority and private read required');
  const verify=createVeteranCareSessionIdentityVerifier(options);
  // Validate the entire recipient/retrieval dependency contract at construction.
  createVeteranCareResultAudienceGate({...options,readSelectedMemory});
  return async function release(input){
    let taskId,selected;
    try{
      const i=capture(input,['taskId','authContext','companionAuthContext','request','recipientAuthContext']);taskId=i.taskId;
      selected=Object.freeze({authContext:capture(i.authContext,['appToken','jwt']),companionAuthContext:capture(i.companionAuthContext,['clientToken','userToken']),request:capture(i.request,['operation','memoryId','memoryVersion','preparationId']),recipientAuthContext:capture(i.recipientAuthContext,['serviceToken'])});
      const r=selected.request;
      if(typeof taskId!=='string'||!UUID.test(taskId)||r.operation!=='read'||typeof r.memoryId!=='string'||!UUID.test(r.memoryId)||!Number.isSafeInteger(r.memoryVersion)||r.memoryVersion<1||typeof r.preparationId!=='string'||!UUID.test(r.preparationId)||[...Object.values(selected.authContext),...Object.values(selected.companionAuthContext),selected.recipientAuthContext.serviceToken].some(v=>typeof v!=='string'||!v.length))throw new TypeError();
    }catch{return deny();}
    let performed=false,taskRefused=false;
    try{
      const started=taskClock();if(!Number.isSafeInteger(started)||started<0)throw new TypeError();
      let last=started;
      const actor=await verify({authContext:selected.authContext});if(actor.status!=='verified')return deny(actor.status);
      const r=selected.request,query=Object.freeze({taskId,foundationAppId:options.appId,ownerShineId:actor.identity.shineId.toLowerCase(),memoryId:r.memoryId,memoryVersion:r.memoryVersion,preparationId:r.preparationId,purpose:'veteran-care.appointment-preparation',operation:'read'});
      async function current(){
        const task=capture(await getCurrentVCTask(query),fields),now=taskClock();
        if(!Number.isSafeInteger(now)||now<last)throw new TypeError();last=now;
        if(Object.keys(query).some(k=>task[k]!==query[k])||task.status!=='running'||!Number.isSafeInteger(task.revision)||task.revision<1||typeof task.validUntil!=='string'||!Number.isSafeInteger(Date.parse(task.validUntil))||now>=Date.parse(task.validUntil))return null;
        return task;
      }
      const first=await current();if(!first)return deny();
      const same=t=>t&&fields.every(k=>t[k]===first[k]);
      const gate=createVeteranCareResultAudienceGate({...options,readSelectedMemory:async q=>{
        if(!same(await current())||q.ownerShineId!==query.ownerShineId){taskRefused=true;throw new Error('task gate refused');}
        performed=true;return readSelectedMemory(q);
      }});
      const prepared=await gate(selected);
      if(taskRefused)return deny('denied',performed);
      if(prepared.status!=='audience-bound-result')return deny(prepared.status,performed);
      if(prepared.recipient.actorShineId!==query.ownerShineId||!same(await current()))return deny('denied',performed);
      const deadline=Math.min(Date.parse(first.validUntil),Date.parse(prepared.recipient.validUntil)),now=taskClock();
      if(!Number.isSafeInteger(now)||now<last||now>=deadline)return deny('denied',performed);
      return {...prepared,contract:'shine-foundation/veteran-care-task-authority-result-v1',status:'task-bound-result',
        task:Object.freeze({taskId,revision:first.revision,validUntil:new Date(deadline).toISOString()}),
        recipient:Object.freeze({...prepared.recipient,validUntil:new Date(deadline).toISOString()}),requiresFreshTaskCheck:true};
    }catch{return deny('unavailable',performed);}
  };
}
