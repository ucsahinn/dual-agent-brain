import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {ChannelHost} from './host-service.mjs';

const fixture=fileURLToPath(new URL('./fixtures/app-server.mjs',import.meta.url));
for(const scenario of ['oversized-event','late-rpc-error','late-rpc-error-fast','late-disconnect','complete-then-exit'])test(`${scenario}: the same turn retains its final answer and corrects notification`,async()=>{
 const root=fs.mkdtempSync(path.join(os.tmpdir(),'beyin-late-')),id='CK-'+'9'.repeat(32);
 const notices=path.join(root,'notices');
 fs.writeFileSync(path.join(root,id+'.json'),JSON.stringify({Owner:'beyin-codex-kanal-v1',Id:id,OwnerSession:'fixture',Project:root,Turn:0,Status:'queued'}));
 const host=new ChannelHost({state:root,id,owner:'fixture',command:process.execPath,args:[fixture],handoffDirectory:notices,timeout:2000,turnTimeout:3000,acquireSetup:async()=>({release(){}})});
 try{
  await host.start();
  const pending=host.dispatch({owner:'fixture',method:'sor',text:scenario});
  if(scenario==='late-disconnect'){
   for(let i=0;i<100&&!host.active?.id;i++)await new Promise(r=>setTimeout(r,1));
   assert.ok(host.active?.id);host.rpc.ended({source:'fixture-connection-fault'});
  }
  const result=await pending;
  const failedFirst=['late-rpc-error','late-disconnect'].includes(scenario);
  if(failedFirst)assert.equal(result.Status,'failed');
  if(scenario==='complete-then-exit')await new Promise(resolve=>host.rpc.process.once('close',()=>setTimeout(resolve,10)));
  for(let i=0;i<100&&host.record.Status!=='completed';i++)await new Promise(r=>setTimeout(r,10));
  assert.equal(host.record.Status,'completed');assert.match(host.record.Answer,/Outcome: OK/);
  assert.equal(host.record.ActiveTurn,'');assert.equal(host.record.PendingTurn,undefined);
  assert.equal(host.record.Error,'');assert.equal(host.record.Attempts,1);
  const stored=JSON.parse(fs.readFileSync(path.join(root,id+'.json'),'utf8'));
  assert.equal(stored.Status,'completed');assert.equal(stored.Answer,host.record.Answer);assert.equal(stored.ActiveTurn,'');
  const messages=fs.readdirSync(notices).map(n=>JSON.parse(fs.readFileSync(path.join(notices,n),'utf8')).question);
  assert.equal(messages.filter(m=>m.includes(' completed;')).length,1);
  assert.equal(messages.filter(m=>m.includes(' failed;')).length,failedFirst?1:0);
  host.notification({method:'turn/completed',params:{threadId:host.record.SessionId,turn:{id:'foreign-turn',status:'completed'}}});
  assert.equal(host.record.Answer,stored.Answer);assert.equal(fs.readdirSync(notices).length,messages.length);
  await host.close();assert.equal(host.record.ActiveTurn,'');assert.match(host.record.Answer,/Outcome: OK/);
 }finally{await host.close();fs.rmSync(root,{recursive:true,force:true});}
});

test('closing an active turn clears its active identity and settles the waiting caller',async()=>{
 const root=fs.mkdtempSync(path.join(os.tmpdir(),'beyin-close-')),id='CK-'+'8'.repeat(32);
 fs.writeFileSync(path.join(root,id+'.json'),JSON.stringify({Owner:'beyin-codex-kanal-v1',Id:id,OwnerSession:'fixture',Project:root,Turn:0}));
 const host=new ChannelHost({state:root,id,owner:'fixture',command:process.execPath,args:[fixture],turnTimeout:3000,acquireSetup:async()=>({release(){}})});
 try{await host.start();const pending=host.runTurn('wait');
  for(let i=0;i<100&&!host.active?.id;i++)await new Promise(r=>setTimeout(r,10));
  assert.ok(host.active?.id);await host.close();await pending.catch(()=>{});
  assert.equal(host.record.ActiveTurn,'');assert.equal(host.record.Status,'closed');
 }finally{await host.close();fs.rmSync(root,{recursive:true,force:true});}
});

test('a real fake-child exit records its code and clears active identity',async()=>{
 const root=fs.mkdtempSync(path.join(os.tmpdir(),'beyin-exit-')),id='CK-'+'6'.repeat(32);
 fs.writeFileSync(path.join(root,id+'.json'),JSON.stringify({Owner:'beyin-codex-kanal-v1',Id:id,OwnerSession:'fixture',Project:root,Turn:0}));
 const host=new ChannelHost({state:root,id,owner:'fixture',command:process.execPath,args:[fixture],acquireSetup:async()=>({release(){}})});
 try{await host.start();const r=await host.runTurn('crash');assert.equal(r.Status,'failed');assert.equal(r.ActiveTurn,'');
  assert.equal(r.ConnectionClosure.Source,'process-close');assert.equal(r.ConnectionClosure.Code,7);assert.equal(r.Attempts,1);
 }finally{await host.close();fs.rmSync(root,{recursive:true,force:true});}
});

test('a timed out turn keeps its identity for later read-only rollout recovery',async()=>{
 const root=fs.mkdtempSync(path.join(os.tmpdir(),'beyin-timeout-')),id='CK-'+'5'.repeat(32);
 fs.writeFileSync(path.join(root,id+'.json'),JSON.stringify({Owner:'beyin-codex-kanal-v1',Id:id,OwnerSession:'fixture',Project:root,Turn:0}));
 const host=new ChannelHost({state:root,id,owner:'fixture',command:process.execPath,args:[fixture],turnTimeout:100,acquireSetup:async()=>({release(){}})});
 try{await host.start();const r=await host.runTurn('wait');assert.equal(r.Status,'failed');assert.equal(r.ActiveTurn,'');assert.equal(r.PendingTurn?.Id,'turn-1');}
 finally{await host.close();fs.rmSync(root,{recursive:true,force:true});}
});

for(const reason of ['timeout','stall','owner'])test(`completion during ${reason} shutdown stays completed on disk`,async()=>{
 const root=fs.mkdtempSync(path.join(os.tmpdir(),'beyin-drain-')),id='CK-'+'4'.repeat(32);
 fs.writeFileSync(path.join(root,id+'.json'),JSON.stringify({Owner:'beyin-codex-kanal-v1',Id:id,OwnerSession:'fixture',Project:root,Turn:0}));
 const host=new ChannelHost({state:root,id,owner:'fixture',command:process.execPath,args:[fixture],turnTimeout:reason==='timeout'?30:3000,supervisor:{nudgeMs:10,stallMs:20},acquireSetup:async()=>({release(){}})});
 try{await host.start();const pending=host.runTurn('late-disconnect');
  for(let i=0;i<100&&!host.active?.id;i++)await new Promise(r=>setTimeout(r,1));
  assert.ok(host.active?.id);
  if(reason==='stall')await host.supervise(host.lastEvent+21);
  if(reason==='owner')await host.close();
  await pending;
  for(let i=0;i<100&&host.rpc.process.exitCode===null;i++)await new Promise(r=>setTimeout(r,10));
  await new Promise(r=>setTimeout(r,20));
  const r=JSON.parse(fs.readFileSync(path.join(root,id+'.json'),'utf8'));
  assert.equal(r.Status,'completed');assert.match(r.Answer,/Outcome: OK/);assert.equal(r.ActiveTurn,'');assert.equal(r.PendingTurn,undefined);
 }finally{await host.close();fs.rmSync(root,{recursive:true,force:true});}
});

test('terminal writes normalize legacy active identity without discarding recovery evidence',()=>{
 const root=fs.mkdtempSync(path.join(os.tmpdir(),'beyin-invariant-')),id='CK-'+'3'.repeat(32);
 fs.writeFileSync(path.join(root,id+'.json'),JSON.stringify({Owner:'beyin-codex-kanal-v1',Id:id,OwnerSession:'fixture',Project:root,Turn:1,Attempts:1,Status:'failed',ActiveTurn:'turn-1'}));
 try{const host=new ChannelHost({state:root,id,owner:'fixture'});host.save();
  const r=JSON.parse(fs.readFileSync(path.join(root,id+'.json'),'utf8'));
  assert.equal(r.ActiveTurn,'');assert.equal(r.PendingTurn.Id,'turn-1');assert.equal(r.PendingTurn.Turn,1);
 }finally{fs.rmSync(root,{recursive:true,force:true});}
});
