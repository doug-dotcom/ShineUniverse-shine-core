import {createClient} from 'npm:@supabase/supabase-js@2.117.1';
import postgres from 'npm:postgres@3.4.9';
import {createFoundationGateway} from '../../gateway/gateway-core-v1.mjs';
import {createFoundationHttpHandler} from '../../gateway/http-handler-v1.mjs';
import {createSupabaseRuntimeAdapters} from '../supabase-runtime-adapters-v1.mjs';
import {createFoundationRuntimeDefenceGateV1} from '../runtime-defence-gate-v1.mjs';

const requireEnv=(name:string)=>{
  const value=Deno.env.get(name);
  if(!value) throw new Error('Missing required environment variable: '+name);
  return value;
};

const supabaseUrl=requireEnv('SUPABASE_URL');

const publishableKeys=Deno.env.get('SUPABASE_PUBLISHABLE_KEYS');
const supabaseKey=publishableKeys
  ? JSON.parse(publishableKeys)['default']
  : requireEnv('SUPABASE_ANON_KEY');

const rawSql=postgres(requireEnv('SUPABASE_DB_URL'),{
  max:1,
  prepare:false,
  idle_timeout:20,
  connect_timeout:10
});

// Every database operation runs inside a transaction scoped to the
// NOLOGIN foundation_gateway role. The built-in Supabase DB connection
// is never passed to the Foundation adapters directly.
const sql:any=(strings:any,...values:any[])=>rawSql.begin(async(tx:any)=>{
  await tx.unsafe('set local role foundation_gateway');
  return tx(strings,...values);
});

const authClient=createClient(supabaseUrl,supabaseKey,{
  auth:{persistSession:false,autoRefreshToken:false,detectSessionInUrl:false}
});

const adapters=createSupabaseRuntimeAdapters({
  sql,
  authClient,
  defenceGate:createFoundationRuntimeDefenceGateV1()
});

const gateway=createFoundationGateway({adapters});

const handler=createFoundationHttpHandler({
  gateway,
  maxBodyBytes:16*1024,
  authenticate:async(request:Request)=>{
    const authorization=request.headers.get('authorization')??'';
    const appToken=request.headers.get('x-shine-app-token')??'';

    if(!authorization.startsWith('Bearer ')||!appToken){
      throw new Error('missing runtime credentials');
    }

    return {
      jwt:authorization.slice('Bearer '.length),
      appToken
    };
  }
});

Deno.serve((request:Request)=>handler(request));
