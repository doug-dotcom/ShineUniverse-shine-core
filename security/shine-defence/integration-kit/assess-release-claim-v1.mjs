#!/usr/bin/env node
import {readFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';

export function assessReleaseClaim({ledger,appId,releaseCommitSha,profileBlobSha}){
  const app=ledger?.apps?.find(entry=>entry.id===appId);
  if(!app)return {state:'uncertified',badgeCurrent:false,appId,reviewedCommitSha:null,reviewedProfileBlobSha:null};
  if(releaseCommitSha!==app.reviewCommitSha){
    return {state:'unreviewed_revision',badgeCurrent:false,appId,reviewedCommitSha:app.reviewCommitSha,reviewedProfileBlobSha:app.profileBlobSha};
  }
  if(profileBlobSha!==app.profileBlobSha){
    return {state:'profile_drift',badgeCurrent:false,appId,reviewedCommitSha:app.reviewCommitSha,reviewedProfileBlobSha:app.profileBlobSha};
  }
  return {state:'reviewed_release',badgeCurrent:true,appId,reviewedCommitSha:app.reviewCommitSha,reviewedProfileBlobSha:app.profileBlobSha};
}

function selfTest(){
  const ledger={apps:[{id:'demo',reviewCommitSha:'a'.repeat(40),profileBlobSha:'b'.repeat(40)}]};
  const cases=[
    ['reviewed_release',assessReleaseClaim({ledger,appId:'demo',releaseCommitSha:'a'.repeat(40),profileBlobSha:'b'.repeat(40)})],
    ['profile_drift',assessReleaseClaim({ledger,appId:'demo',releaseCommitSha:'a'.repeat(40),profileBlobSha:'c'.repeat(40)})],
    ['unreviewed_revision',assessReleaseClaim({ledger,appId:'demo',releaseCommitSha:'d'.repeat(40),profileBlobSha:'b'.repeat(40)})],
    ['uncertified',assessReleaseClaim({ledger,appId:'missing',releaseCommitSha:'d'.repeat(40),profileBlobSha:'b'.repeat(40)})]
  ];
  for(const [expected,result] of cases)if(result.state!==expected)throw new Error('expected '+expected+', got '+result.state);
  if(!cases[0][1].badgeCurrent||cases.slice(1).some(([,result])=>result.badgeCurrent))throw new Error('badgeCurrent state error');
  console.log('SHINE DEFENCE RELEASE CLAIM: PASS '+cases.length+' states');
}

function main(){
  const args=process.argv.slice(2);
  if(args.includes('--self-test'))return selfTest();
  const value=name=>{const i=args.indexOf(name);return i>=0?args[i+1]:undefined};
  const ledgerPath=value('--ledger')||'security/shine-defence/ecosystem-profile-ledger-v1.json';
  const appId=value('--app');
  const releaseCommitSha=value('--release-sha');
  const profileBlobSha=value('--profile-blob-sha');
  if(!appId||!/^[a-f0-9]{40}$/.test(releaseCommitSha||'')||!/^[a-f0-9]{40}$/.test(profileBlobSha||'')){
    console.error('usage: assess-release-claim-v1.mjs --app <id> --release-sha <40hex> --profile-blob-sha <40hex> [--ledger <path>]');
    process.exit(64);
  }
  const ledger=JSON.parse(readFileSync(ledgerPath,'utf8'));
  const result=assessReleaseClaim({ledger,appId,releaseCommitSha,profileBlobSha});
  console.log(JSON.stringify(result));
  process.exitCode=result.badgeCurrent?0:2;
}

if(import.meta.url===pathToFileURL(process.argv[1]).href)main();
