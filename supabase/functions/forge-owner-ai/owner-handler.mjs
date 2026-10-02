export function createHandler({createClient,env,fetcher=fetch}) {
 const origins=['https://app.forgehub.dev','https://scope.forgehub.dev'];
 return async req=>{
  const origin=req.headers.get('origin')||'';
  const headers={'Content-Type':'application/json','Cache-Control':'no-store','Vary':'Origin',
   'Access-Control-Allow-Origin':origins.includes(origin)?origin:origins[0],
   'Access-Control-Allow-Headers':'authorization, apikey, content-type, x-client-info',
   'Access-Control-Allow-Methods':'POST, OPTIONS'};
  const reply=(body,status=200)=>new Response(JSON.stringify(body),{status,headers});
  if(origin&&!origins.includes(origin))return reply({error:'Origin not permitted.'},403);
  if(req.method==='OPTIONS')return new Response(null,{status:204,headers});
  if(req.method!=='POST')return reply({error:'POST required.'},405);
  try {
   const auth=req.headers.get('Authorization')||'';
   if(!/^Bearer \S+$/i.test(auth))return reply({error:'Sign in to Forge first.'},401);
   const client=createClient(env('SUPABASE_URL'),env('SUPABASE_ANON_KEY'),{global:{headers:{Authorization:auth}},auth:{persistSession:false}});
   const {data,error}=await client.auth.getUser(auth.slice(7));
   if(error||!data?.user)return reply({error:'Sign in to Forge first.'},401);
   const {data:context,error:contextError}=await client.rpc('forge_account_context');
   if(contextError||!context?.is_owner)return reply({error:'This AI connection is reserved for the Forge owner.'},403);
   const reader=req.body?.getReader();if(!reader)return reply({error:'Request required.'},400);
   let size=0;const chunks=[];
   for(;;){const {done,value}=await reader.read();if(done)break;size+=value.length;if(size>20*1024*1024){await reader.cancel();return reply({error:'Keep the AI upload below 20 MB including encoding.'},413);}chunks.push(value);}
   const bytes=new Uint8Array(size);let offset=0;for(const chunk of chunks){bytes.set(chunk,offset);offset+=chunk.length;}
   let body;try{body=JSON.parse(new TextDecoder().decode(bytes));}catch{return reply({error:'Invalid request.'},400);}
   if(!body||!['status','save','generate'].includes(body.action))return reply({error:'Unknown action.'},400);
   if(body.action==='save'&&!context.admin_unlocked)return reply({error:'Unlock the owner console with your authenticator before saving your key.'},403);
   const admin=createClient(env('SUPABASE_URL'),env('SUPABASE_SERVICE_ROLE_KEY'),{auth:{persistSession:false}});
   if(body.action==='save'){
    if(typeof body.key!=='string'||!/^[A-Za-z0-9_-]{20,256}$/.test(body.key.trim()))return reply({error:'Enter a valid Gemini API key.'},400);
    const {error:saveError}=await admin.rpc('forge_owner_ai_secret',{p_user:data.user.id,p_key:body.key.trim()});
    if(saveError)return reply({error:'Your key could not be saved. Please try again.'},503);
    return reply({configured:true});
   }
   const {data:key,error:keyError}=await admin.rpc('forge_owner_ai_secret',{p_user:data.user.id});
   if(keyError)return reply({error:'Your AI connection could not be loaded.'},503);
   if(body.action==='status')return reply({configured:Boolean(key)});
   if(!key)return reply({error:'Connect your personal Gemini key once in Account & admin → My AI connection. Your owner access is already recognized.'},409);
   if(!Array.isArray(body.parts)||!body.parts.length||body.parts.length>80)return reply({error:'Invalid document parts.'},400);
   const allowed=['application/pdf','image/png','image/jpeg','image/webp'];
   const parts=[];
   for(const p of body.parts){
    if(p&&typeof p.text==='string')parts.push({text:p.text});
    else if(p?.inlineData&&allowed.includes(p.inlineData.mimeType)&&typeof p.inlineData.data==='string')parts.push({inlineData:{mimeType:p.inlineData.mimeType,data:p.inlineData.data}});
    else return reply({error:'Invalid document format.'},400);
   }
   const upstream=await fetcher('https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-pro:generateContent',{
    method:'POST',headers:{'Content-Type':'application/json','x-goog-api-key':key},signal:AbortSignal.timeout(110000),
    body:JSON.stringify({contents:[{role:'user',parts}],generationConfig:{temperature:0.1,responseMimeType:'application/json'}})
   });
   if(!upstream.ok)return reply({error:upstream.status===429?'Your Gemini account has reached a provider limit. Try again later.':`Your Gemini request failed (${upstream.status}). Check the key and API access in your Google account.`},upstream.status===429?429:502);
   return reply(await upstream.json());
  }catch{return reply({error:'Your AI request could not complete. Please try again.'},502);}
 };
}

