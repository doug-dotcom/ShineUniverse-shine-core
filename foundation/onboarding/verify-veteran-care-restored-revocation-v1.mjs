import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {pathToFileURL} from 'node:url';
import {runVeteranCareIsolatedRestore} from './verify-veteran-care-isolated-restore-v1.mjs';
const owner='11111111-1111-4111-8111-111111111111',controlOwner='22222222-2222-4222-8222-222222222222';
const epoch='33333333-3333-4333-8333-333333333333',oldEpoch='44444444-4444-4444-8444-444444444444';
const grant='cccccccc-cccc-4ccc-8ccc-cccccccccccc';
const digestQuery="select coalesce(jsonb_agg(to_jsonb(r) order by grant_id),'[]'::jsonb)::text from vc_restore.revocations r";
export async function runVeteranCareRestoredRevocationProof(){
  return runVeteranCareIsolatedRestore({verifyRestoredDatabase:async({source,target,readerRole,sql})=>{
    if(!/^vc_restore_reader_[0-9a-f]{24}$/.test(readerRole))throw Error();
    const checks=[];
    const check=async(label,actor,expected)=>{
      const r=await sql(target,`set role ${readerRole};set vc_restore.shine_id='${actor}';select count(*) from vc_restore.records;`);
      if(r.split('\n').at(-1)!==String(expected))throw Error();checks.push(label);
    };
    // The source is the independently current synthetic authority. This update
    // occurs AFTER the archive was taken and restored, never in the backup.
    await sql(source,`update vc_restore.revocations set revision=3 where grant_id='${grant}';`);
    const canonical=await sql(source,digestQuery),requiredDigest=createHash('sha256').update(canonical).digest('hex');
    const oldDigest=createHash('sha256').update(await sql(target,digestQuery)).digest('hex');
    if(requiredDigest===oldDigest)throw Error();
    const contract=await readFile(new URL('../recovery/veteran-care-restored-revocation-continuity-v1.sql',import.meta.url),'utf8');
    await sql(target,contract.replaceAll('__READER_ROLE__',readerRole));
    // An unrevoked second owner's grant is the positive control: denial cannot
    // be explained merely by the withdrawn first owner's permission.
    await sql(target,`insert into vc_restore.permissions values ('99999999-9999-4999-8999-999999999999','bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','${controlOwner}','active',1);
      insert into vc_restore.recovery_watermark values(true,'${epoch}','${epoch}',3,2,'${requiredDigest}','${oldDigest}');`);
    await check('lagging-watermark-blocks-positive-control',controlOwner,0);
    await check('restored-old-grant-blocked',owner,0);
    await sql(target,`update vc_restore.revocations set revision=3 where grant_id='${grant}';update vc_restore.recovery_watermark set applied_revision=3,applied_digest='${requiredDigest}';`);
    await check('reconciled-unrevoked-positive-control-reads',controlOwner,1);
    await check('later-revocation-overrides-old-active-grant',owner,0);
    await sql(target,`update vc_restore.permissions set status='active',revision=1 where grant_id='${grant}';`);
    await check('replayed-active-grant-cannot-resurrect-authority',owner,0);
    await sql(target,`update vc_restore.recovery_watermark set applied_epoch='${oldEpoch}';`);
    await check('wrong-authority-epoch-blocks',controlOwner,0);
    await sql(target,`update vc_restore.recovery_watermark set applied_epoch='${epoch}',applied_revision=4;`);
    await check('unexpected-ahead-revision-blocks',controlOwner,0);
    await sql(target,`update vc_restore.recovery_watermark set applied_revision=3;delete from vc_restore.revocations where grant_id='${grant}';`);
    await check('missing-ledger-entry-blocks-digest-parity',controlOwner,0);
    await check('deleted-tombstone-does-not-revive-old-grant',owner,0);
    await sql(target,`insert into vc_restore.revocations values('${grant}',3);`);
    await check('reconciliation-restores-positive-control',controlOwner,1);
    await sql(target,'delete from vc_restore.recovery_watermark;');
    await check('missing-current-watermark-fails-closed',controlOwner,0);
    if(await sql(target,`select has_table_privilege('${readerRole}','vc_restore.revocations','DELETE') or has_table_privilege('${readerRole}','vc_restore.recovery_watermark','UPDATE')`)!=='f')throw Error();
    checks.push('reader-cannot-edit-recovery-authority');
    if(await sql(target,"select count(*) from vc_restore.tasks where status='paused'")!=='1')throw Error();
    checks.push('restored-task-remains-paused');
    return Object.freeze({revocationContinuityVerified:true,evidenceMode:'synthetic-postgres-ci',postBackupRevision:3,restoredRevision:2,
      requiredLedgerSha256:requiredDigest,backupLedgerSha256:oldDigest,contractSha256:createHash('sha256').update(contract).digest('hex'),
      checks:Object.freeze(checks),productionRevocationVerified:false,freshRuntimeAuthorityStillRequired:true});
  }});
}
if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href){
  try{process.stdout.write(JSON.stringify(await runVeteranCareRestoredRevocationProof(),null,2)+'\n');}
  catch{process.stderr.write('VC restored revocation proof failed; no production continuity claimed.\n');process.exitCode=1;}
}
