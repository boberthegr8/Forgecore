import {test} from 'node:test';
import assert from 'node:assert/strict';
import {createHandler} from './owner-handler.mjs';
function fixture({owner=true,mfa=true,signedIn=true,key='owner-private-test-key'}={}){
 const calls=[];const client={auth:{getUser:async()=>({data:{user:signedIn?{id:'verified-owner'}:null}})},rpc:async(name,args)=>{calls.push({name,args});return name==='forge_account_context'?{data:{is_owner:owner,admin_unlocked:mfa}}:{data:key};}};
 const handler=createHandler({createClient:()=>client,env:()=>'',fetcher:async(url,options)=>{calls.push({url,options});return new Response(JSON.stringify({candidates:[]}));}});
 const invoke=(body,origin='https://scope.forgehub.dev')=>handler(new Request('https://test.local',{method:'POST',headers:{origin,Authorization:'Bearer test'},body:JSON.stringify(body)}));
 return {calls,invoke};
}
test('non-owner cannot inspect, save, or use owner key',async()=>{for(const action of ['status','save','generate']){const f=fixture({owner:false});assert.equal((await f.invoke({action,key:'x'.repeat(30),parts:[{text:'test'}]})).status,403);assert.deepEqual(f.calls.map(c=>c.name),['forge_account_context']);}});
test('signed-out cannot reach owner registry or provider',async()=>{const f=fixture({signedIn:false});assert.equal((await f.invoke({action:'generate'})).status,401);assert.equal(f.calls.length,0);});
test('status returns only configured flag',async()=>{const f=fixture();assert.deepEqual(await (await f.invoke({action:'status'})).json(),{configured:true});});
test('saving requires MFA and ignores user-supplied identity',async()=>{const f=fixture({mfa:false});assert.equal((await f.invoke({action:'save',key:'x'.repeat(30)})).status,403);assert.equal(f.calls.length,1);const g=fixture();assert.equal((await g.invoke({action:'save',key:'x'.repeat(30),userId:'intruder'})).status,200);assert.equal(g.calls[1].args.p_user,'verified-owner');});
test('missing owner key never falls back to shared AI',async()=>{const f=fixture({key:null});assert.equal((await f.invoke({action:'generate',parts:[{text:'test'}]})).status,409);assert.equal(f.calls.some(c=>c.url),false);});
test('owner generation uses saved key only on server',async()=>{const f=fixture();const r=await f.invoke({action:'generate',parts:[{text:'test'}],key:'untrusted-override'});assert.deepEqual(await r.json(),{candidates:[]});assert.equal(f.calls.at(-1).options.headers['x-goog-api-key'],'owner-private-test-key');});
test('untrusted origins and malformed parts cannot reach provider',async()=>{const f=fixture();assert.equal((await f.invoke({action:'generate'},'https://evil.example')).status,403);assert.equal(f.calls.length,0);assert.equal((await f.invoke({action:'generate',parts:[null]})).status,400);assert.equal(f.calls.some(c=>c.url),false);});

