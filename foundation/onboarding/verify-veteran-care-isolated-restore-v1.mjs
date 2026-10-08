import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {randomBytes,createHash} from 'node:crypto';
import {mkdtemp,readFile,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';
const exec=promisify(execFile),hash=v=>createHash('sha256').update(v).digest('hex');
export function assertVeteranCareRestoreCIEnvironment(env){
  if(env.CI!=='true'||env.GITHUB_ACTIONS!=='true'||env.FOUNDATION_VC_SYNTHETIC_RESTORE!=='1'||! /^[0-9a-f]{64}$/.test(env.FOUNDATION_VC_POSTGRES_CONTAINER??'')||!['localhost','127.0.0.1'].includes(env.PGHOST)||String(env.PGPORT)!=='5432'||env.PGUSER!=='postgres'||env.PGDATABASE!=='postgres'||env.PGPASSWORD!=='postgres')throw new Error('isolated synthetic CI environment required');
}
export function assertVeteranCareRestoreDatabaseName(name){
  if(typeof name!=='string'||!/^vc_restore_(source|target)_[0-9a-f]{24}$/.test(name))throw new Error('generated scratch database name required');
  return name;
}
const tables=['checkpoints','permissions','records','retry_bindings','revocations','tasks'];
export async function runVeteranCareIsolatedRestore({verifyRestoredDatabase}={}){
  if(verifyRestoredDatabase!==undefined&&typeof verifyRestoredDatabase!=='function')throw new TypeError('trusted isolated proof callback required');
  assertVeteranCareRestoreCIEnvironment(process.env);
  const suffix=randomBytes(12).toString('hex'),source=assertVeteranCareRestoreDatabaseName('vc_restore_source_'+suffix),target=assertVeteranCareRestoreDatabaseName('vc_restore_target_'+suffix),role='vc_restore_reader_'+suffix;
  const childEnv={PATH:process.env.PATH,PGHOST:'127.0.0.1',PGPORT:'5432',PGUSER:'postgres',PGPASSWORD:'postgres',PGDATABASE:'postgres',LC_ALL:'C'};
  const call=async(tool,args)=>(await exec(tool,args,{env:childEnv,timeout:60000,maxBuffer:4*1024*1024})).stdout.trim();
  const sql=(db,text)=>call('psql',['-X','-A','-t','-v','ON_ERROR_STOP=1','-h','127.0.0.1','-p','5432','-U','postgres','-d',db,'-c',text]);
  const container=process.env.FOUNDATION_VC_POSTGRES_CONTAINER,containerArchive='/tmp/vc_synthetic_restore_'+suffix+'.dump';
  const pgTool=(tool,args)=>call('docker',['exec','-e','PGPASSWORD=postgres',container,tool,...args]);
  let dir,sourceCreated=false,targetCreated=false,roleCreated=false,archiveAttempted=false,report,error;
  try{
    dir=await mkdtemp(join(tmpdir(),'vc-synthetic-restore-'));
    await sql('postgres',`create role ${role} nologin nosuperuser nobypassrls;`);roleCreated=true;
    await sql('postgres',`create database ${source};`);sourceCreated=true;
    await sql('postgres',`create database ${target};`);targetCreated=true;
    const fixture=await readFile(new URL('../recovery/veteran-care-isolated-restore-fixture-v1.sql',import.meta.url),'utf8');
    await sql(source,fixture.replaceAll('__READER_ROLE__',role));
    if(await sql(target,"select count(*) from information_schema.tables where table_schema='vc_restore'")!=='0')throw Error();
    const archive=join(dir,'synthetic.dump');
    archiveAttempted=true;
    await pgTool('pg_dump',['-h','127.0.0.1','-p','5432','-U','postgres','-d',source,'--format=custom','--file',containerArchive]);
    await call('docker',['cp',container+':'+containerArchive,archive]);
    const archiveHash=hash(await readFile(archive));
    await pgTool('pg_restore',['-h','127.0.0.1','-p','5432','-U','postgres','-d',target,'--exit-on-error','--no-owner',containerArchive]);
    const tableDigests={};
    for(const table of tables){
      const query=`select coalesce(jsonb_agg(to_jsonb(t) order by to_jsonb(t)::text),'[]'::jsonb)::text from vc_restore.${table} t`;
      const a=hash(await sql(source,query)),b=hash(await sql(target,query));if(a!==b)throw Error();tableDigests[table]=b;
    }
    const schemaQuery="select coalesce(jsonb_agg(to_jsonb(t) order by t.table_name,t.ordinal_position),'[]'::jsonb)::text from (select table_name,column_name,data_type,is_nullable,column_default,ordinal_position from information_schema.columns where table_schema='vc_restore') t";
    const schemaHash=hash(await sql(source,schemaQuery));if(hash(await sql(target,schemaQuery))!==schemaHash)throw Error();
    const constraintsQuery="select coalesce(jsonb_agg(to_jsonb(t) order by t.table_name,t.name),'[]'::jsonb)::text from (select c.relname table_name,k.conname name,pg_get_constraintdef(k.oid) definition from pg_constraint k join pg_class c on c.oid=k.conrelid join pg_namespace n on n.oid=c.relnamespace where n.nspname='vc_restore') t";
    const constraintsHash=hash(await sql(source,constraintsQuery));if(hash(await sql(target,constraintsQuery))!==constraintsHash)throw Error();
    const policyQuery="select coalesce(jsonb_agg(to_jsonb(t) order by t.tablename,t.policyname),'[]'::jsonb)::text from (select tablename,policyname,permissive,roles,cmd,qual,with_check from pg_policies where schemaname='vc_restore') t";
    const policyHash=hash(await sql(source,policyQuery));if(hash(await sql(target,policyQuery))!==policyHash)throw Error();
    if(await sql(target,"select relrowsecurity and relforcerowsecurity from pg_class where oid='vc_restore.records'::regclass")!=='t')throw Error();
    if(await sql(target,`select ${['INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER'].map(p=>`has_table_privilege('${role}','vc_restore.records','${p}')`).join(' or ')} or has_table_privilege('${role}','vc_restore.permissions','SELECT')`) !=='f')throw Error();
    for(const [actor,expected] of [['11111111-1111-4111-8111-111111111111',1],['22222222-2222-4222-8222-222222222222',1],['33333333-3333-4333-8333-333333333333',0]]){
      const result=await sql(target,`set role ${role};set vc_restore.shine_id='${actor}';select count(*)::text||':'||coalesce(bool_and(owner_id::text='${actor}'),true)::text from vc_restore.records;`);
      if(result.split('\n').at(-1)!==String(expected)+':true')throw Error();
    }
    if(await sql(target,"select count(*) from vc_restore.tasks where status='paused'")!=='1')throw Error();
    const continuity=verifyRestoredDatabase?await verifyRestoredDatabase(Object.freeze({source,target,readerRole:role,sql})):null;
    if(verifyRestoredDatabase&&continuity?.revocationContinuityVerified!==true)throw Error();
    report={contract:'shine-foundation/veteran-care-isolated-restore-proof-v1',status:'passed',evidenceMode:'synthetic-postgres-ci',databaseRestoreExecuted:true,
      fixtureSha256:hash(fixture),archiveSha256:archiveHash,schemaSha256:schemaHash,constraintsSha256:constraintsHash,tableDigests,
      schemaAndDataMatched:true,constraintsMatched:true,rowLevelSecurityVerified:true,leastPrivilegeVerified:true,crossOwnerReadBlocked:true,pausedTaskPreserved:true,
      productionBackupVerified:false,productionRestorePerformed:false,revocationContinuityVerified:continuity!==null,restoreAuthorityProvided:false,
      ...(continuity?{revocationContinuity:continuity}:{})};
  }catch{error=new Error('isolated synthetic restore drill failed');}
  // Only databases created by this invocation may be removed. Never accept a
  // caller database name, remote connection string or backup archive.
  for(const [created,db] of [[targetCreated,target],[sourceCreated,source]])if(created)try{await sql('postgres',`drop database ${assertVeteranCareRestoreDatabaseName(db)} with (force);`);}catch{error=new Error('isolated restore cleanup failed');}
  if(roleCreated)try{await sql('postgres',`drop role ${role};`);}catch{error=new Error('isolated restore cleanup failed');}
  if(archiveAttempted)try{await call('docker',['exec',container,'rm','-f',containerArchive]);}catch{error=new Error('isolated restore cleanup failed');}
  if(dir)try{await rm(dir,{recursive:true,force:true});}catch{error=new Error('isolated restore cleanup failed');}
  if(error)throw error;
  return {...report,cleanupVerified:true};
}
if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href){
  try{process.stdout.write(JSON.stringify(await runVeteranCareIsolatedRestore(),null,2)+'\n');}
  catch{process.stderr.write('VC isolated synthetic restore proof failed; no production restore claimed.\n');process.exitCode=1;}
}
