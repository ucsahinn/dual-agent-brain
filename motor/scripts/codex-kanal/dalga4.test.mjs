import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';import os from 'node:os';import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {ChannelHost} from './host-service.mjs';
import * as policy from './policy.mjs';

test('unknown engine/backend and signal exits remain honest',()=>{
 assert.equal(policy.channelEngine('typo'),null);
 assert.equal(policy.channelEngine(undefined,'claude'),'claude');
 assert.equal(policy.channelBackend('typo'),null);
 assert.deepEqual(policy.workerExit(143,null,'codex'),{kind:'signal',signal:15,fault:false,engine:'codex'});
 assert.equal(policy.workerExit(1,null,'claude').fault,true);
});
test('subscription budget uses both measured windows; unknown billing has no invented price',()=>{
 const limits={primary:{usedPercent:10},secondary:{usedPercent:100}};
 const r=policy.channelBudget({['input'+'Tokens']:9999999},1,'x',{},'subscription',limits);
 assert.equal(r.blocked,true);assert.equal(r.cost,null);assert.equal(r.apiEquivalent,false);
 assert.equal(policy.channelBudget({},1,'x',{},'unknown',null).reason,'billing-unknown');
 assert.equal(policy.channelBudget({inputTokens:2},1,'x',{},'api',null).blocked,true);
});
const fixture=fileURLToPath(new URL('./fixtures/dalga4-server.mjs',import.meta.url));
async function withHost(mode,fn,extra={}){
 const root=fs.mkdtempSync(path.join(os.tmpdir(),'beyin-d4-')),id='CK-'+'b'.repeat(32);
 fs.writeFileSync(path.join(root,id+'.json'),JSON.stringify({Owner:'beyin-codex-kanal-v1',Id:id,OwnerSession:'owner',Project:root,Turn:0,RoleModel:'missing-role',CatalogModel:'catalog-model',ReviewModel:'review-model'}));
 const host=new ChannelHost({state:root,id,owner:'owner',command:process.execPath,args:[fixture,mode],timeout:2000,acquireSetup:async()=>({release(){}}),handoffDirectory:path.join(root,'notices'),...extra});
 try{await host.start();await fn(host,root);}finally{await host.close();fs.rmSync(root,{recursive:true,force:true});}
}
test('recovered tool error yields one completed notification, warnings and checkpoint',()=>withHost('subscription',async(h,root)=>{
 const r=await h.dispatch({owner:'owner',method:'sor',text:'recover'});
 assert.equal(r.Status,'completed');assert.equal(r.Attempts,1);assert.equal(r.Error,'');assert.ok(r.Warnings.some(w=>w.includes('setup refresh')));
 const notices=fs.readdirSync(path.join(root,'notices')).map(n=>fs.readFileSync(path.join(root,'notices',n),'utf8'));
 assert.equal(notices.length,1);assert.match(notices[0],/completed/);assert.doesNotMatch(notices[0],/failed/);
 const notice=JSON.parse(notices[0]);
 assert.equal(notice.status,'acik');assert.equal(notice.a2aStatus,'submitted');
 assert.equal(notice.doneBy,'');assert.equal(notice.doneTs,'');
 assert.equal(r.RoleModel,'catalog-model');assert.equal(r.ModelList.length,2);assert.equal(r.BillingMode,'subscription');assert.equal(r.Budget.cost,null);
 assert.ok(fs.existsSync(path.join(h.directory,'plan.md')));assert.ok(fs.existsSync(path.join(h.directory,'notes.md')));
 assert.equal(JSON.parse(fs.readFileSync(path.join(h.directory,'checkpoint.json'))).threadId,r.SessionId);
}));
test('paginated model list selects supported role before catalog',()=>withHost('role',async h=>{
 assert.equal(h.record.RoleModel,'missing-role');assert.equal(h.record.ModelList.length,3);
}));
test('subscription with tiny token budget can run; secondary exhausted window waits',()=>withHost('subscription',async h=>{
 h.cfg.tokenBudget=1;h.record.Usage={['input'+'Tokens']:9999999};
 assert.equal((await h.dispatch({owner:'owner',method:'sor',text:'ok'})).Status,'completed');
 h.rpc.call=async method=>method==='account/rateLimits/read'?{rateLimits:{secondary:{usedPercent:100,resetsAt:1900000000}}}:{};
 assert.equal((await h.dispatch({owner:'owner',method:'sor',text:'wait'})).Status,'limit-waiting');
}));
test('profile rollover is opt in and preserves the owned thread',()=>withHost('subscription',async h=>{
 const sid=h.record.SessionId;h.cfg.profiles=[{name:'one',home:h.directory},{name:'two',home:h.directory}];h.record.ProfileIndex=0;
 assert.equal(await h.rotateProfile(),false);
 h.cfg.autoProfileSwitch=true;assert.equal(await h.rotateProfile(),true);
 assert.equal(h.record.ProfileIndex,1);assert.equal(h.record.SessionId,sid);
}));
test('signal exit is interrupted, never retried as a setup fault',()=>withHost('subscription',async h=>{
 const r=await h.dispatch({owner:'owner',method:'sor',text:'signal'});
 assert.equal(r.Status,'interrupted');assert.equal(r.WorkerExit.fault,false);assert.equal(r.WorkerExit.signal,15);assert.equal(r.Attempts,1);
 const sid=r.SessionId;assert.equal((await h.dispatch({owner:'owner',method:'sor',text:'ok'})).SessionId,sid);
 const failed=await h.dispatch({owner:'owner',method:'sor',text:'rpc-fault'});assert.equal(failed.Status,'failed');
}));
test('an old explicit crash checkpoint resumes instead of silently starting a new thread',()=>withHost('subscription',async h=>{
 h.record.Finished='2020-01-01T00:00:00.000Z';h.record.ResumeCheckpoint=true;
 const r=await h.dispatch({owner:'owner',method:'sor',text:'ok'});
 assert.equal(r.Continuation.Decision,'resume');assert.equal(r.Continuation.Reason,'checkpoint');
}));
test('failed retry attempts never send a terminal failed notification before success',()=>withHost('unused',async(h,root)=>{
 const r=await h.dispatch({owner:'owner',method:'sor',text:'task'});assert.equal(r.Status,'completed');assert.equal(r.Attempts,3);
 const notices=fs.readdirSync(path.join(root,'notices')).map(n=>fs.readFileSync(path.join(root,'notices',n),'utf8'));
 assert.equal(notices.length,1);assert.match(notices[0],/completed/);
},{args:[fileURLToPath(new URL('./fixtures/fallback-server.mjs',import.meta.url)),'fallback'],sleep:async()=>{}}));
test('rollover to a different home starts a new owned thread with checkpoint context',()=>withHost('cross-home',async(h,root)=>{
 h.cfg.profiles=[{name:'one',home:root},{name:'two',home:h.directory}];h.cfg.autoProfileSwitch=true;
 const old=h.record.SessionId;assert.equal(await h.rotateProfile(),true);
 assert.equal(h.record.ProfileSwitch.sessionPolicy,'fresh-home');assert.ok(h.record.PreviousSessions.includes(old));
 assert.equal((await h.dispatch({owner:'owner',method:'sor',text:'ok'})).Status,'completed');
}));
test('unknown persisted backend cannot turn into the default on the next launch',()=>withHost('subscription',async h=>{
 await h.close();fs.writeFileSync(h.file,JSON.stringify({...h.record,Backend:null,BackendStatus:'unknown'}));
 const next=new ChannelHost(h.cfg);try{await assert.rejects(next.start(),/Unknown engine\/backend/);}finally{await next.close();}
}));
test('measured preflight limit automatically rolls only when enabled',()=>withHost('subscription',async(h,root)=>{
 h.cfg.profiles=[{name:'one',home:root},{name:'two',home:root}];h.cfg.autoProfileSwitch=true;
 const original=h.rpc.call.bind(h.rpc);h.rpc.call=(method,params)=>method==='account/rateLimits/read'?Promise.resolve({rateLimits:{primary:{usedPercent:100,resetsAt:1900000000}}}):original(method,params);
 const r=await h.dispatch({owner:'owner',method:'sor',text:'ok'});
 assert.equal(r.Status,'completed');assert.equal(r.ProfileIndex,1);assert.equal(r.Turn,1);assert.equal(r.RateLimits.primary.usedPercent,20);
}));
