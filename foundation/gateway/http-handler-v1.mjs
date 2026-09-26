const JSON_HEADERS={
  'content-type':'application/json; charset=utf-8',
  'cache-control':'no-store'
};

const json=(status,body)=>new Response(JSON.stringify(body),{
  status,
  headers:JSON_HEADERS
});

export function createFoundationHttpHandler({gateway,authenticate}={}){
  if(typeof gateway!=='function') throw new TypeError('gateway must be a function');
  if(typeof authenticate!=='function') throw new TypeError('authenticate must be a function');

  return async function handle(request){
    const url=new URL(request.url);

    if(request.method==='GET' && url.pathname==='/health'){
      return json(200,{
        service:'shine-foundation-gateway',
        status:'ok',
        schemaVersion:'1.0.0'
      });
    }

    if(url.pathname!=='/v1/access/evaluate') return json(404,{error:'not-found'});
    if(request.method!=='POST') return json(405,{error:'method-not-allowed'});

    const contentType=request.headers.get('content-type') ?? '';
    if(!contentType.toLowerCase().startsWith('application/json')){
      return json(415,{error:'unsupported-media-type'});
    }

    let envelope;
    try{
      envelope=await request.json();
    }catch{
      return json(400,{error:'invalid-json'});
    }

    let authContext;
    try{
      authContext=await authenticate(request);
    }catch{
      return json(401,{error:'unauthenticated'});
    }

    const result=await gateway({envelope,authContext});

    const status={
      allowed:200,
      denied:403,
      invalid:400,
      unavailable:503
    }[result.status] ?? 500;

    return json(status,result);
  };
}
