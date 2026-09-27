import { createClient } from 'npm:@supabase/supabase-js@2.112.4';
const origins = ['https://scope.forgehub.dev','https://app.forgehub.dev'];
Deno.serve(async req => {
 const origin=req.headers.get('origin')||'';
 const headers={'Content-Type':'application/json','Access-Control-Allow-Origin':origins.includes(origin)?origin:origins[0],'Access-Control-Allow-Headers':'authorization, apikey, content-type, x-client-info','Access-Control-Allow-Methods':'POST, OPTIONS','Vary':'Origin'};
 const reply=(data:unknown,status=200)=>new Response(JSON.stringify(data),{status,headers});
 if(origin&&!origins.includes(origin))return reply({error:'Origin not permitted.'},403);
 if(req.method==='OPTIONS')return new Response(null,{status:204,headers});
 if(req.method!=='POST')return reply({error:'POST required.'},405);
 try {
  const url=Deno.env.get('SUPABASE_URL')!;
  const auth=req.headers.get('Authorization')||'';
  const userClient=createClient(url,Deno.env.get('SUPABASE_ANON_KEY')!,{global:{headers:{Authorization:auth}},auth:{persistSession:false}});
  const {data:{user},error:authError}=await userClient.auth.getUser(auth.replace(/^Bearer /i,''));
  if(authError||!user)return reply({error:'Sign in required.'},401);
  const {data:policy,error:policyError}=await userClient.rpc('forge_ai_settings');
  if(policyError||!policy)return reply({error:'AI settings unavailable.'},503);
  if(policy.mode==='disabled')return reply({error:'Shared AI is disabled by the owner.'},403);
  // Deliberately no generic GEMINI_API_KEY or personal-key fallback.
  const free=policy.mode==='free';
  const key=Deno.env.get(free?'FORGE_FREE_GEMINI_KEY':'FORGE_BUSINESS_GEMINI_KEY');
  const confirmed=Deno.env.get(free?'FORGE_FREE_BILLING_DISABLED':'FORGE_BUSINESS_ENABLED')==='true';
  if(!key||!confirmed)return reply({error:free?'Free AI is awaiting a separate no-billing provider account. Your personal key will not be used.':'Business AI is not configured. No personal key will be used.'},503);
  const reader=req.body?.getReader();if(!reader)return reply({error:'Request required.'},400);
  let size=0;const chunks:Uint8Array[]=[];
  for(;;){const {done,value}=await reader.read();if(done)break;size+=value.length;if(size>20*1024*1024){await reader.cancel();return reply({error:'Keep the AI upload below 20 MB including encoding.'},413);}chunks.push(value);}
  const bytes=new Uint8Array(size);let offset=0;for(const chunk of chunks){bytes.set(chunk,offset);offset+=chunk.length;}
  let body;try{body=JSON.parse(new TextDecoder().decode(bytes));}catch{return reply({error:'Invalid request.'},400);}
  if(!Array.isArray(body.parts)||body.parts.length<1||body.parts.length>80)return reply({error:'Invalid document parts.'},400);
  const allowed=['application/pdf','image/png','image/jpeg','image/webp'];
  const parts=body.parts.map((p:any)=>{
   if(typeof p.text==='string')return {text:p.text};
   if(p.inlineData&&allowed.includes(p.inlineData.mimeType)&&typeof p.inlineData.data==='string')return {inlineData:{mimeType:p.inlineData.mimeType,data:p.inlineData.data}};
   throw new Error('Invalid document format.');
  });
  const admin=createClient(url,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,{auth:{persistSession:false}});
  const {error:limitError}=await admin.rpc('forge_ai_reserve',{p_user:user.id,p_mode:policy.mode});
  if(limitError)return reply({error:limitError.message},429);
  const upstream=await fetch('https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent',{
   method:'POST',headers:{'Content-Type':'application/json','x-goog-api-key':key},signal:AbortSignal.timeout(110000),
   body:JSON.stringify({contents:[{role:'user',parts}],generationConfig:{temperature:0.1,responseMimeType:'application/json',maxOutputTokens:8192}})
  });
  if(!upstream.ok)return reply({error:upstream.status===429?'Provider allowance reached. Please try later; no paid fallback was used.':'AI provider could not complete this request. No fallback was used.'},upstream.status===429?429:502);
  return reply(await upstream.json());
 }catch{return reply({error:'AI request could not complete. No paid fallback was used.'},502);}
});

