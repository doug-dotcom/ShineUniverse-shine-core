const UUID=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const REF=/^[a-z0-9][a-z0-9._:-]{0,127}$/i;
const EMAIL=/^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const ACTIONS=new Set([
  'appointment-book',
  'appointment-reschedule',
  'appointment-cancel',
  'referral-follow-up',
  'provider-contact',
  'document-request',
  'reminder'
]);
const TARGET_KINDS=new Set(['practitioner','provider','service','support-person']);
const CHANNELS=new Set(['phone','email','web','in-person','unspecified']);
const WINDOWS=new Set(['morning','afternoon','evening','any']);

const object=value=>Boolean(value)&&typeof value==='object'&&!Array.isArray(value);
const keysExact=(value,allowed,required=[])=>{
  if(!object(value)) return false;
  const keys=Object.keys(value);
  return keys.every(key=>allowed.has(key))&&required.every(key=>keys.includes(key));
};
const text=(value,max=180)=>typeof value==='string'&&value.trim().length>0&&value.trim().length<=max&&!/[\u0000-\u001f\u007f]/.test(value);
const iso=value=>typeof value==='string'&&Number.isFinite(Date.parse(value));
const ref=value=>typeof value==='string'&&REF.test(value);
const url=value=>{
  if(typeof value!=='string'||value.length>500) return false;
  try{
    const parsed=new URL(value);
    return parsed.protocol==='https:'||parsed.protocol==='http:';
  }catch{return false}
};

function projectContact(value){
  if(value===undefined) return undefined;
  if(!keysExact(value,new Set(['phone','email','url']))) return null;
  if(value.phone!==undefined&&!text(value.phone,40)) return null;
  if(value.email!==undefined&&(typeof value.email!=='string'||value.email.length>254||!EMAIL.test(value.email))) return null;
  if(value.url!==undefined&&!url(value.url)) return null;
  if(value.phone===undefined&&value.email===undefined&&value.url===undefined) return null;
  return {
    ...(value.phone!==undefined?{phone:value.phone.trim()}:{}),
    ...(value.email!==undefined?{email:value.email.trim()}:{}),
    ...(value.url!==undefined?{url:value.url.trim()}:{}),
  };
}

function projectTarget(value){
  if(!keysExact(value,new Set(['kind','displayName','contact']),['kind','displayName'])) return null;
  if(!TARGET_KINDS.has(value.kind)||!text(value.displayName,160)) return null;
  const contact=projectContact(value.contact);
  if(value.contact!==undefined&&contact===null) return null;
  return {
    kind:value.kind,
    displayName:value.displayName.trim(),
    ...(contact?{contact}:{}),
  };
}

function projectTiming(value){
  if(value===undefined) return undefined;
  if(!keysExact(value,new Set(['requestedAt','dueAt','window','timezone']))) return null;
  if(value.requestedAt!==undefined&&!iso(value.requestedAt)) return null;
  if(value.dueAt!==undefined&&!iso(value.dueAt)) return null;
  if(value.window!==undefined&&!WINDOWS.has(value.window)) return null;
  if(value.timezone!==undefined&&!text(value.timezone,80)) return null;
  if(Object.keys(value).length===0) return null;
  return {
    ...(value.requestedAt!==undefined?{requestedAt:new Date(value.requestedAt).toISOString()}:{}),
    ...(value.dueAt!==undefined?{dueAt:new Date(value.dueAt).toISOString()}:{}),
    ...(value.window!==undefined?{window:value.window}:{}),
    ...(value.timezone!==undefined?{timezone:value.timezone.trim()}:{}),
  };
}

function projectLocation(value){
  if(value===undefined) return undefined;
  if(!keysExact(value,new Set(['displayName','address']))) return null;
  if(value.displayName!==undefined&&!text(value.displayName,180)) return null;
  if(value.address!==undefined&&!text(value.address,300)) return null;
  if(value.displayName===undefined&&value.address===undefined) return null;
  return {
    ...(value.displayName!==undefined?{displayName:value.displayName.trim()}:{}),
    ...(value.address!==undefined?{address:value.address.trim()}:{}),
  };
}

export function projectWellnessHealthMinimalHandoff(value){
  const allowed=new Set([
    'healthMinimalHandoff','schemaVersion','handoffId','canonicalRecordId',
    'permissionDecisionId','actionCode','target','timing','location','channel',
    'sourceRecordIds'
  ]);
  const required=[
    'healthMinimalHandoff','schemaVersion','handoffId','canonicalRecordId',
    'permissionDecisionId','actionCode','target','sourceRecordIds'
  ];
  if(!keysExact(value,allowed,required)) return null;
  if(value.healthMinimalHandoff!=='shine-wellness/concierge-health-minimal-v1'||value.schemaVersion!=='1.0.0') return null;
  if(!UUID.test(value.handoffId)||!ref(value.canonicalRecordId)||!ref(value.permissionDecisionId)) return null;
  if(!ACTIONS.has(value.actionCode)) return null;

  const target=projectTarget(value.target);
  if(!target) return null;
  const timing=projectTiming(value.timing);
  if(value.timing!==undefined&&timing===null) return null;
  const location=projectLocation(value.location);
  if(value.location!==undefined&&location===null) return null;
  if(value.channel!==undefined&&!CHANNELS.has(value.channel)) return null;

  if(!Array.isArray(value.sourceRecordIds)||value.sourceRecordIds.length<1||value.sourceRecordIds.length>8) return null;
  if(value.sourceRecordIds.some(item=>!ref(item))||new Set(value.sourceRecordIds).size!==value.sourceRecordIds.length) return null;
  if(!value.sourceRecordIds.includes(value.canonicalRecordId)) return null;

  return {
    healthMinimalHandoff:'shine-wellness/concierge-health-minimal-v1',
    schemaVersion:'1.0.0',
    handoffId:value.handoffId,
    canonicalRecordId:value.canonicalRecordId,
    permissionDecisionId:value.permissionDecisionId,
    actionCode:value.actionCode,
    target,
    ...(timing?{timing}:{}),
    ...(location?{location}:{}),
    ...(value.channel!==undefined?{channel:value.channel}:{}),
    sourceRecordIds:[...value.sourceRecordIds],
  };
}

export function isWellnessHealthMinimalHandoff(value){
  return projectWellnessHealthMinimalHandoff(value)!==null;
}

export const WELLNESS_CONCIERGE_PURPOSE='wellness-care-logistics';
