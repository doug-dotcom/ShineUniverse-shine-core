const APP=/^shine\.[a-z0-9][a-z0-9-]*$/;
const ID=/^[a-z0-9][a-z0-9._:-]*$/;
const ENV=/^[A-Z][A-Z0-9_]*$/;
const REPO=/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/;
const URL=/^https:\/\/[a-z0-9.-]+$/;
const ISSUER=/^https:\/\/[a-z0-9.-]+\/auth\/v1$/;
const DBNAME=/^[a-z][a-z0-9_]{0,62}$/;
const HEADER=/^x-[a-z0-9-]{1,62}$/;
const PRIVATE_KEYS=new Set([
  'shineId','providerSubject','credentialId','resourceId',
  'appToken','userToken','password','secret','serviceRoleKey','apiKey'
]);

const plain=value=>value&&typeof value==='object'&&!Array.isArray(value);

const rejectPrivateState=(value,path='spec')=>{
  if(Array.isArray(value)){
    value.forEach((item,index)=>rejectPrivateState(item,path+'['+index+']'));
    return;
  }
  if(!plain(value)) return;
  for(const [key,item] of Object.entries(value)){
    if(PRIVATE_KEYS.has(key)) throw new TypeError(path+'.'+key+' is private/live state and cannot appear in an onboarding spec');
    rejectPrivateState(item,path+'.'+key);
  }
};

const exactKeys=(obj,required,optional=[],name='object')=>{
  if(!plain(obj)) throw new TypeError(name+' must be an object');
  for(const key of required) if(!(key in obj)) throw new TypeError(name+'.'+key+' is required');
  const allowed=new Set([...required,...optional]);
  for(const key of Object.keys(obj)) if(!allowed.has(key)) throw new TypeError(name+'.'+key+' is not allowed');
};

export function validateAppendageConnectionSpec(spec){
  exactKeys(spec,['spec','schemaVersion','app','source','identity','runtime','pilot','safety'],[],'spec');
  if(spec.spec!=='shine-foundation/appendage-connection-spec-v1') throw new TypeError('unsupported spec');
  if(spec.schemaVersion!=='1.0.0') throw new TypeError('unsupported schemaVersion');
  rejectPrivateState(spec);

  exactKeys(spec.app,['appId','name','primaryPurpose'],[],'app');
  if(!APP.test(spec.app.appId)) throw new TypeError('invalid app.appId');
  if(typeof spec.app.name!=='string'||!spec.app.name.trim()) throw new TypeError('invalid app.name');
  if(typeof spec.app.primaryPurpose!=='string'||!spec.app.primaryPurpose.trim()) throw new TypeError('invalid app.primaryPurpose');

  exactKeys(spec.source,['repository','branch','backendEntrypoint'],[],'source');
  if(!REPO.test(spec.source.repository)) throw new TypeError('invalid source.repository');
  if(typeof spec.source.branch!=='string'||!spec.source.branch.trim()) throw new TypeError('invalid source.branch');
  if(typeof spec.source.backendEntrypoint!=='string'||!spec.source.backendEntrypoint.trim()) throw new TypeError('invalid source.backendEntrypoint');

  if(!plain(spec.identity)) throw new TypeError('identity must be an object');
  if(spec.identity.kind==='supabase-auth'){
    exactKeys(spec.identity,['kind','providerId','projectUrl','issuer'],[],'identity');
    if(!ID.test(spec.identity.providerId)||!URL.test(spec.identity.projectUrl)||!ISSUER.test(spec.identity.issuer)) throw new TypeError('invalid supabase-auth identity');
  }else if(spec.identity.kind==='supabase-opaque-vault'){
    exactKeys(spec.identity,['kind','providerId','projectUrl','verificationResource','subjectField','tokenHeader'],[],'identity');
    if(!ID.test(spec.identity.providerId)||!URL.test(spec.identity.projectUrl)||!DBNAME.test(spec.identity.verificationResource)||!DBNAME.test(spec.identity.subjectField)||!HEADER.test(spec.identity.tokenHeader)) throw new TypeError('invalid supabase-opaque-vault identity');
  }else{
    throw new TypeError('unsupported identity.kind');
  }

  exactKeys(spec.runtime,['platform','foundationBaseUrlEnv','appTokenEnv','userCredentialMode'],[],'runtime');
  if(!['railway','supabase-edge','other-server'].includes(spec.runtime.platform)) throw new TypeError('invalid runtime.platform');
  if(!ENV.test(spec.runtime.foundationBaseUrlEnv)||!ENV.test(spec.runtime.appTokenEnv)) throw new TypeError('invalid runtime env name');
  const expectedMode=spec.identity.kind==='supabase-auth'?'bearer-jwt':'opaque-header';
  if(spec.runtime.userCredentialMode!==expectedMode) throw new TypeError('runtime.userCredentialMode does not match identity.kind');

  exactKeys(spec.pilot,['scope','purpose','resourceCategory'],[],'pilot');
  if(!ID.test(spec.pilot.scope)||!ID.test(spec.pilot.purpose)||!/^[a-z0-9][a-z0-9._-]*$/.test(spec.pilot.resourceCategory)) throw new TypeError('invalid pilot');
  const appSlug=spec.app.appId.slice('shine.'.length);
  if(!spec.pilot.purpose.startsWith(appSlug+'.')) throw new TypeError('pilot.purpose must be namespaced to the app');

  exactKeys(spec.safety,['standaloneFallback','secretsInSpec','personalIdsInSpec'],[],'safety');
  if(spec.safety.standaloneFallback!==true||spec.safety.secretsInSpec!==false||spec.safety.personalIdsInSpec!==false) throw new TypeError('invalid safety declaration');

  return structuredClone(spec);
}

export function compileAppendageConnectionSpec(input){
  const spec=validateAppendageConnectionSpec(input);
  return {
    contract:'shine-foundation/appendage-onboarding-plan-v1',
    appManifest:{
      manifest:'shine-foundation/app-manifest-v1',
      schemaVersion:'1.0.0',
      appId:spec.app.appId,
      name:spec.app.name,
      version:'1.0.0',
      primaryPurpose:spec.app.primaryPurpose,
      supportedModes:['standalone','connected','universe-enhanced'],
      foundation:{
        contract:'shine-foundation/foundation-v1',
        standalonePrimaryPurposeAvailable:true,
        requestedScopes:[{
          scope:spec.pilot.scope,
          purpose:spec.pilot.purpose,
          resourceCategory:spec.pilot.resourceCategory,
          optional:true
        }],
        onFoundationUnavailable:'continue-standalone'
      }
    },
    identityProvider:{
      providerId:spec.identity.providerId,
      kind:spec.identity.kind,
      projectUrl:spec.identity.projectUrl,
      ...(spec.identity.kind==='supabase-auth'
        ? {issuer:spec.identity.issuer}
        : {
            verificationResource:spec.identity.verificationResource,
            subjectField:spec.identity.subjectField,
            tokenHeader:spec.identity.tokenHeader
          }),
      publishableKeyRequired:true
    },
    appIdentityProvider:{
      appId:spec.app.appId,
      providerId:spec.identity.providerId
    },
    runtime:{
      platform:spec.runtime.platform,
      repository:spec.source.repository,
      branch:spec.source.branch,
      backendEntrypoint:spec.source.backendEntrypoint,
      foundationBaseUrlEnv:spec.runtime.foundationBaseUrlEnv,
      appTokenEnv:spec.runtime.appTokenEnv,
      userCredentialMode:spec.runtime.userCredentialMode
    },
    pilot:{
      appId:spec.app.appId,
      scope:spec.pilot.scope,
      purpose:spec.pilot.purpose,
      resourceCategory:spec.pilot.resourceCategory
    },
    requiresLiveProvisioning:[
      'publishable-key',
      'app-credential-secret',
      'canonical-user-binding',
      'pilot-grant'
    ]
  };
}
