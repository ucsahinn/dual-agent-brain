import test from 'node:test';import assert from 'node:assert/strict';import fs from 'node:fs';import os from 'node:os';import path from 'node:path';import {fileURLToPath} from 'node:url';
import {ChannelHost} from './host-service.mjs';
const fixture=fileURLToPath(new URL('./fixtures/app-server.mjs',import.meta.url));
test('chief cached usage permits a second turn with the recorded effective-token formula',async()=>{
 const root=fs.mkdtempSync(path.join(os.tmpdir(),'beyin-cached-')),id='CK-'+'f'.repeat(32);
 fs.writeFileSync(path.join(root,id+'.json'),JSON.stringify({Owner:'beyin-codex-kanal-v1',Id:id,OwnerSession:'owner',Project:root,Turn:1,BudgetBlocked:true,Usage:{inputTokens:199310,cachedInputTokens:153216,outputTokens:827}}));
 const host=new ChannelHost({state:root,id,owner:'owner',command:process.execPath,args:[fixture]});
 try{await host.start();const result=await host.dispatch({owner:'owner',method:'sor',text:'second'});assert.equal(result.Status,'completed');assert.equal(result.Turn,2);assert.equal(result.Budget.blocked,false);assert.equal(result.Budget.limit,2000000);assert.match(result.Budget.formula,/cached\*0\.1/);assert.ok(result.Budget.effectiveTokens<63000);assert.equal(result.SetupLock.ReleaseReason,'first-command-or-agent');}finally{await host.close();fs.rmSync(root,{recursive:true,force:true});}
});
test('mailbox runs two turns on one process and exposes pending approvals',async()=>{
 const root=fs.mkdtempSync(path.join(os.tmpdir(),'beyin-host-')),id='CK-'+'a'.repeat(32);
 fs.writeFileSync(path.join(root,id+'.json'),JSON.stringify({Owner:'beyin-codex-kanal-v1',Id:id,OwnerSession:'owner',Project:root,Turn:0,SessionId:'',Status:'queued'}));
 const host=new ChannelHost({state:root,id,command:process.execPath,args:[fixture],owner:'owner',timeout:2000});
 try{
  await host.start();
  const first=await host.dispatch({owner:'owner',method:'sor',text:'first'});assert.equal(first.Status,'completed');assert.equal(first.Turn,1);
  const session=first.SessionId;
  const second=await host.dispatch({owner:'owner',method:'sor',text:'second'});assert.equal(second.Turn,2);assert.equal(second.SessionId,session);
  await assert.rejects(host.dispatch({owner:'stranger',method:'sor',text:'no'}),/owner/);
  const turn=host.dispatch({owner:'owner',method:'sor',text:'approval'});
  for(let i=0;i<100&&!host.approvals.size;i++)await new Promise(r=>setTimeout(r,10));
  assert.equal(host.approvals.size,1);
  await host.dispatch({owner:'owner',method:'onay',requestId:'9001',decision:'decline'});await turn;
  host.cfg.sleep=async ms=>assert.ok(ms>=10000&&ms<=40000);
  const failed=await host.dispatch({owner:'owner',method:'sor',text:'tool-error'});
  assert.equal(failed.Status,'failed');assert.equal(failed.Attempts,3);assert.equal(failed.RetryCount,2);
  const ordinary=await host.dispatch({owner:'owner',method:'sor',text:'answer-error-text'});assert.equal(ordinary.Attempts,1);
  const effects=await host.dispatch({owner:'owner',method:'sor',text:'tool-error-with-success'});assert.equal(effects.Attempts,1);
 }finally{await host.close();fs.rmSync(root,{recursive:true,force:true});}
});
test('known limits preserve undelivered briefs and resume from persisted queue without a scheduler',async()=>{
 const root=fs.mkdtempSync(path.join(os.tmpdir(),'beyin-limit-host-')),id='CK-'+'f'.repeat(32),cfg={state:root,id,owner:'owner',command:process.execPath,args:[fixture,'--limit']};
 fs.writeFileSync(path.join(root,id+'.json'),JSON.stringify({Owner:'beyin-codex-kanal-v1',Id:id,OwnerSession:'owner',Project:root,Turn:0,Status:'queued'}));let host=new ChannelHost(cfg);
 try{await host.start();const limit=await host.dispatch({owner:'owner',method:'sor',text:'undelivered task'});assert.equal(limit.Status,'limit-waiting');assert.equal(limit.Turn,0);assert.equal(host.limitQueue.value.pendingPrompt,'undelivered task');await host.close();host=new ChannelHost({...cfg,args:[fixture]});await host.start();host.limitQueue.value.dueAt=Date.now()-1;await host.dispatch({owner:'owner',method:'tetikle'});assert.equal(host.record.Status,'completed');assert.equal(host.record.Turn,1);assert.equal(host.limitQueue.value.status,'verified');assert.equal(host.limitQueue.value.pendingPrompt,undefined);}finally{await host.close();fs.rmSync(root,{recursive:true,force:true});}
});
test('Claude host reconnects its crashed fake child with the same owned session',async()=>{
 const root=fs.mkdtempSync(path.join(os.tmpdir(),'beyin-claude-host-')),id='CK-'+'e'.repeat(32);
 fs.writeFileSync(path.join(root,id+'.json'),JSON.stringify({Owner:'beyin-codex-kanal-v1',Id:id,OwnerSession:'owner',Project:root,Turn:0,Status:'queued'}));
 const host=new ChannelHost({state:root,id,owner:'owner',engine:'claude',command:process.execPath,args:[fileURLToPath(new URL('../claude-kanal/fixtures/claude.mjs',import.meta.url)),'--fixture-state',path.join(root,'context')],turnTimeout:3000});
 try{await host.start();const first=await host.dispatch({owner:'owner',method:'sor',text:'remember'});assert.equal(first.Status,'completed');await assert.rejects(host.dispatch({owner:'owner',method:'sor',text:'crash'}),/exited/);assert.equal(host.record.Status,'disconnected');const recall=await host.dispatch({owner:'owner',method:'sor',text:'recall'});assert.equal(recall.SessionId,first.SessionId);assert.match(recall.Answer,/synthetic-memory/);assert.equal(recall.Status,'completed');
  assert.equal(host.record.RoleModel,'claude-sonnet-fixture');const permission=host.dispatch({owner:'owner',method:'sor',text:'approval'});for(let i=0;i<100&&!host.approvals.size;i++)await new Promise(r=>setTimeout(r,10));assert.equal(host.record.PendingApprovals[0].command,'fixture never executed');await host.dispatch({owner:'owner',method:'onay',requestId:'fixture-permission',decision:'decline'});assert.match((await permission).Answer,/permission deny/);
 }finally{await host.close();fs.rmSync(root,{recursive:true,force:true});}
});
test('silence nudge, stalled termination and pending-limit idle exemption run through the host',async()=>{
 const root=fs.mkdtempSync(path.join(os.tmpdir(),'beyin-supervised-')),id='CK-'+'d'.repeat(32);
 fs.writeFileSync(path.join(root,id+'.json'),JSON.stringify({Owner:'beyin-codex-kanal-v1',Id:id,OwnerSession:'owner',Project:root,Turn:0,Status:'queued'}));
 const host=new ChannelHost({state:root,id,owner:'owner',command:process.execPath,args:[fixture],supervisor:{nudgeMs:100,stallMs:200},idleMs:100});
 try{await host.start();host.limitQueue.plan(host.record.SessionId,0,Date.now()+3600000);await host.supervise(host.idleSince+101);assert.equal(host.stopping,false);host.limitQueue.value=null;
  const pending=host.dispatch({owner:'owner',method:'sor',text:'wait'});for(let i=0;i<100&&!host.active?.id;i++)await new Promise(r=>setTimeout(r,10));assert.ok(host.active?.id);
  const last=host.lastEvent;await host.supervise(last+101);assert.equal(host.ledger.events.filter(e=>e.state==='nudged').length,1);await host.supervise(last+102);assert.equal(host.ledger.events.filter(e=>e.state==='nudged').length,1);await host.supervise(last+201);assert.equal((await pending).Status,'stalled');assert.equal(host.record.Status,'stalled');
 }finally{await host.close();fs.rmSync(root,{recursive:true,force:true});}
});
test('host enforces scoped automatic approvals and the token budget brake',async()=>{
 const root=fs.mkdtempSync(path.join(os.tmpdir(),'beyin-budget-')),id='CK-'+'c'.repeat(32);fs.mkdirSync(path.join(root,'src'));
 fs.writeFileSync(path.join(root,id+'.json'),JSON.stringify({Owner:'beyin-codex-kanal-v1',Id:id,OwnerSession:'owner',Project:root,Turn:0,Status:'queued',WriteScopes:['src/'],ExplicitWriteScopes:true}));
 const host=new ChannelHost({state:root,id,owner:'owner',command:process.execPath,args:[fixture],tokenBudget:12});
 try{await host.start();let timer;try{await Promise.race([host.dispatch({owner:'owner',method:'sor',text:'file-approval'}),new Promise((_,reject)=>{timer=setTimeout(()=>reject(new Error('Scoped approval was not automatic')),3000);})]);}finally{clearTimeout(timer);}assert.equal(host.approvals.size,0);assert.equal(host.record.ApprovalDecisions[0].decision,'accept');await host.dispatch({owner:'owner',method:'sor',text:'count'});await assert.rejects(host.dispatch({owner:'owner',method:'sor',text:'over-budget'}),/budget/);}finally{await host.close();fs.rmSync(root,{recursive:true,force:true});}
});
