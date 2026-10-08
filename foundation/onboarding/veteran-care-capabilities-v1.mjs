// Producer-side declaration only. VC Integrations owns registration and live adapters.
const APP=/^shine\.[a-z0-9][a-z0-9-]*$/;
const UUID=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
function exactInput(input,keys){
  if(!input||typeof input!=='object'||Array.isArray(input)||Object.getPrototypeOf(input)!==Object.prototype)
    throw new TypeError('plain capability input is required');
  const descriptors=Object.getOwnPropertyDescriptors(input);
  if(Reflect.ownKeys(input).length!==keys.length||keys.some(k=>!Object.hasOwn(descriptors,k))||
    Object.values(descriptors).some(d=>!Object.hasOwn(d,'value')||!d.enumerable))
    throw new TypeError('capability input fields do not match');
}
function validApp(appId){
  if(typeof appId!=='string'||!APP.test(appId)) throw new TypeError('registered VC appId is required');
  return appId.slice('shine.'.length);
}
export function validateVeteranCareCapabilityInput({appId,capabilityId,input}={}){
  const slug=validApp(appId);
  if(capabilityId===slug+'.adj_guidance'){
    exactInput(input,['question']);
    if(typeof input.question!=='string'||!input.question.trim()||input.question.length>2000)
      throw new TypeError('bounded question is required');
  }else if(capabilityId===slug+'.selected_record_read'){
    exactInput(input,['recordId','recordVersion']);
    if(typeof input.recordId!=='string'||!UUID.test(input.recordId)||
      !Number.isSafeInteger(input.recordVersion)||input.recordVersion<1)
      throw new TypeError('exact record and version are required');
  }else throw new TypeError('unsupported VC capability');
  return structuredClone(input);
}
export function createVeteranCareCapabilityDeclaration({appId,getAppManifest}={}){
  const slug=validApp(appId);
  if(typeof getAppManifest!=='function')throw new TypeError('Foundation registry adapter is required');
  return async function declare(){
    let manifest;
    try{manifest=await getAppManifest({appId});}
    catch{return {status:'unavailable',reasonCode:'vc-registry-unavailable'};}
    if(!manifest||manifest.appId!==appId)
      return {status:'blocked',reasonCode:'vc-app-unregistered'};
    const base={appId,capabilityVersion:'1.0.0',invocationState:'declared',invocable:false};
    return {
      contract:'shine-foundation/veteran-care-capability-declaration-v1',
      schemaVersion:'1.0.0',status:'declaration-ready',
      registrationApplied:false,executionRequiresAuthorization:true,
      capabilities:[
        {...base,capabilityId:slug+'.adj_guidance',displayName:'Ask Adj for general guidance',
          description:'Declared general DVA guidance; no private passport retrieval or automatic submission.',
          mode:'advisory',requiredPermissions:[],
          inputSchema:{type:'object',additionalProperties:false,required:['question'],properties:{question:{type:'string',minLength:1,maxLength:2000,pattern:'\\S'}}},
          outputSchema:{type:'object',additionalProperties:false,required:['summary','sources'],properties:{summary:{type:'string',maxLength:12000},sources:{type:'array',maxItems:20,items:{type:'object',additionalProperties:false,required:['url','reviewedAt'],properties:{url:{type:'string',format:'uri',maxLength:2048},reviewedAt:{type:'string',format:'date-time'}}}}}}
        },
        {...base,capabilityId:slug+'.selected_record_read',displayName:'Read one selected record',
          description:'Declared exact-version record read; ownership and current explicit permission must be enforced by the VC consumer.',
          mode:'read',requiredPermissions:[{scope:slug+'.record.read',purpose:slug+'.appointment-preparation',resourceCategory:slug+'.record'}],
          inputSchema:{type:'object',additionalProperties:false,required:['recordId','recordVersion'],properties:{recordId:{type:'string',pattern:UUID.source.replaceAll('a-f','a-fA-F').replace('[89ab]','[89abAB]')},recordVersion:{type:'integer',minimum:1,maximum:Number.MAX_SAFE_INTEGER}}},
          outputSchema:{type:'object',additionalProperties:false,required:['recordId','recordVersion','contentRef'],properties:{recordId:{type:'string',pattern:UUID.source.replaceAll('a-f','a-fA-F').replace('[89ab]','[89abAB]')},recordVersion:{type:'integer',minimum:1,maximum:Number.MAX_SAFE_INTEGER},contentRef:{type:'string',minLength:1,maxLength:500}}}
        }
      ]
    };
  };
}
