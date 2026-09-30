import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';

const root=fileURLToPath(new URL('../../',import.meta.url));
const sql=readFileSync(root+'foundation/postgres/explicit-client-deny-policies-hosted-v1.sql','utf8');

const targets=[
  'foundation.project_l_policy_transition_authorization_events',
  'foundation.project_l_roster_head_witness_events',
  'foundation.project_l_roster_head_witness_state',
  'foundation.project_l_trace_witness_events',
  'foundation.project_l_trace_witness_state',
  'universe.app_registry',
  'universe.app_repo_links',
  'universe.daily_build_closes',
  'universe.data_dataset_aliases',
  'universe.data_dataset_relationships',
  'universe.data_datasets',
  'universe.data_sources',
  'universe.dataset_capability_map',
  'universe.foundation_app_links',
  'universe.layer_events',
  'universe.layer_ledger_anchors',
  'universe.readiness_events',
  'universe.readiness_releases',
  'universe.readiness_stage_definitions',
  'universe.repo_registry'
];

test('hosted deny policy hardening covers all intentional closed tables',()=>{
  for(const target of targets) assert.match(sql,new RegExp(target.replaceAll('.','\\.')));
  assert.equal(targets.length,20);
});

test('client deny policies are restrictive and false for both read and write',()=>{
  assert.match(sql,/as restrictive for all to anon, authenticated using \(false\) with check \(false\)/i);
  assert.match(sql,/p\.polpermissive=false/);
  assert.match(sql,/p\.polcmd='\*'/);
  assert.match(sql,/pg_get_expr\(p\.polqual,p\.polrelid\)='false'/);
  assert.match(sql,/pg_get_expr\(p\.polwithcheck,p\.polrelid\)='false'/);
});

test('hardening refuses privilege expansion or missing RLS targets',()=>{
  assert.match(sql,/explicit-client-deny-unexpected-client-grant/);
  assert.match(sql,/explicit-client-deny-rls-disabled/);
  assert.match(sql,/explicit-client-deny-target-missing/);
  assert.doesNotMatch(sql,/grant\s+(select|insert|update|delete).*\b(anon|authenticated)\b/i);
});
