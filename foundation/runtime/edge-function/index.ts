import postgres from 'npm:postgres@3.4.9';
import {createFoundationGateway} from '../../gateway/gateway-core-v1.mjs';
import {createFoundationHttpHandler} from '../../gateway/http-handler-v1.mjs';
import {createPublicDefenceStatusService} from '../../gateway/defence-status-v1.mjs';
import {createSupabaseRuntimeAdapters} from '../supabase-runtime-adapters-v1.mjs';
import {createFoundationRuntimeDefenceGateV1} from '../runtime-defence-gate-v1.mjs';
import defenceLedger from '../../../security/shine-defence/ecosystem-profile-ledger-v1.json' with {type:'json'};
import defenceRevocations from '../../../security/shine-defence/revocations-v1.json' with {type:'json'};

const requireEnv=(name:string)=>{
  const value=Deno.env.get(name);
  if(!value) throw new Error('Missing required environment variable: '+name);
  return value;
};

const rawSql=postgres(requireEnv('SUPABASE_DB_URL'),{
  max:1,
  prepare:false,
  idle_timeout:20,
  connect_timeout:10
});

const sql:any=(strings:any,...values:any[])=>rawSql.begin(async(tx:any)=>{
  await tx.unsafe('set local role foundation_gateway');
  return tx(strings,...values);
});

const adapters=createSupabaseRuntimeAdapters({
  sql,
  fetchImpl:fetch,
  defenceGate:createFoundationRuntimeDefenceGateV1()
});

const gateway=createFoundationGateway({adapters});
const defenceStatus=createPublicDefenceStatusService({
  ledger:defenceLedger,
  revocations:defenceRevocations
});

const handler=createFoundationHttpHandler({
  gateway,
  defenceStatus,
  maxBodyBytes:16*1024,
  authenticate:async(request:Request)=>{
    const authorization=request.headers.get('authorization')??'';
    const appToken=request.headers.get('x-shine-app-token')??'';
    const userToken=request.headers.get('x-shine-user-token')??'';
    const jwt=authorization.startsWith('Bearer ')?authorization.slice('Bearer '.length):'';
    if(!appToken||(!jwt&&!userToken)){
      throw new Error('missing runtime credentials');
    }
    return {appToken,...(jwt?{jwt}:{}),...(userToken?{userToken}:{})};
  }
});

Deno.serve((request:Request)=>handler(request));
