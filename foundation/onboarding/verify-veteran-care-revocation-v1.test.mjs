import test from 'node:test';
import assert from 'node:assert/strict';
import {runVeteranCareRevocationProof} from './verify-veteran-care-revocation-v1.mjs';
test('joined producer feed acknowledgement and two consumers prove revocation without live claims',async()=>{
 const r=await runVeteranCareRevocationProof();assert.equal(r.passed,15);assert.equal(r.evidence,'offline-synthetic');assert.equal(r.hostedAuthenticationVerified,false);assert.equal(r.durableDatabaseVerified,false);assert.equal(r.productionDisclosureVerified,false);
 assert.equal(r.results.find(x=>x.scenario==='consumer A initially allowed').outcome,'allow');assert.equal(r.results.find(x=>x.scenario==='consumer A remains blocked after acknowledgement').outcome,'deny');assert.equal(r.results.find(x=>x.scenario==='consumer B remains blocked after acknowledgement').outcome,'deny');
});
test('independent concurrent proof runs cannot inherit withdrawn authority or another delivery',async()=>{
 const results=await Promise.all([runVeteranCareRevocationProof(),runVeteranCareRevocationProof()]);assert.deepEqual(results[0],results[1]);
});
