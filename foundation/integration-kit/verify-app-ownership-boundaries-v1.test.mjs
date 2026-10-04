import {test} from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {verifyAppOwnershipBoundaries as verify} from "./verify-app-ownership-boundaries-v1.mjs";
const contract=JSON.parse(readFileSync(new URL("../contracts/app-ownership-boundaries-v1.json",import.meta.url)));
const rows=contract.apps.map(({app_key,canonical_repo,category})=>({app_key,canonical_repo,category}));
test("all catalogue apps have boundaries; shared repositories grant no access",()=>{
 const result=verify(contract,rows);
 assert.equal(result.appCount,21); assert.equal(result.grantsAccess,false);
 assert.equal(result.runtimeEnforced,false);
});
test("missing new app and wrong repository fail closed",()=>{
 assert.throws(()=>verify(contract,[...rows,{app_key:"new",canonical_repo:"a/b",category:"product"}]),/coverage-gap/);
 assert.throws(()=>verify(contract,rows.map((r,i)=>i? r:{...r,canonical_repo:"a/b"})),/registry-drift/);
});
test("duplicate gateway identity and implicit grants are rejected",()=>{
 const c=structuredClone(contract);c.apps[0].gatewayAppId="shine.daash";
 assert.throws(()=>verify(c,rows),/gateway-duplicate/);
 const d=structuredClone(contract);d.policy.sharedRepositoryGrantsAccess=true;
 assert.throws(()=>verify(d,rows),/implicit-access/);
});
