import test from 'node:test';import assert from 'node:assert/strict';import fs from 'node:fs';import os from 'node:os';import path from 'node:path';
import {approvalPolicy,briefWriteScopes,fanout,budgetState,compileBrief,handoffSchema,toHandoff,detectLimit,LimitQueue} from './policy.mjs';
test('only explicit brief paths grant file scopes and sensitive or linked paths stay manual',()=>{
 assert.deepEqual(briefWriteScopes('Write scope:\n- `src/`\n- `test/a.js`\nBoundaries:\nno publish'),['src/','test/a.js']);
 assert.deepEqual(briefWriteScopes('Write scope:\nOnly requested changes, read-only.\nBoundaries:\nnone'),[]);
 const root=fs.mkdtempSync(path.join(os.tmpdir(),'beyin-safe-path-'));fs.mkdirSync(path.join(root,'real'));fs.symlinkSync(path.join(root,'real'),path.join(root,'linked'),'junction');
 try{for(const file of ['.env','.git/config','linked/test.js']){assert.equal(approvalPolicy({method:'item/fileChange/requestApproval',params:{fileChanges:[{path:file,kind:'update'}]}},['./'],root).decision,'pending');}}finally{fs.rmSync(root,{recursive:true,force:true});}
});
test('only scoped reversible file writes auto-approve; shell and deletion wait',()=>{
 const root=fs.mkdtempSync(path.join(os.tmpdir(),'beyin-policy-'));fs.mkdirSync(path.join(root,'src'));
 try{const request={method:'item/fileChange/requestApproval',params:{fileChanges:[{path:path.join(root,'src','file.js'),kind:'update'}]}};
  assert.equal(approvalPolicy(request,['src/'],root).decision,'accept');request.params.fileChanges[0].path=path.join(root,'outside.js');assert.equal(approvalPolicy(request,['src/'],root).decision,'pending');
  request.params.fileChanges[0]={path:path.join(root,'src','file.js'),kind:'delete'};assert.equal(approvalPolicy(request,['src/'],root).decision,'pending');assert.equal(approvalPolicy({method:'item/commandExecution/requestApproval',params:{command:'anything'}},['src/'],root).decision,'pending');
 }finally{fs.rmSync(root,{recursive:true,force:true});}
});
test('fanout honors overlap dependencies live capacity and the hard cap',()=>{
 assert.equal(fanout([['src/'],['src/a.js']],8).workers,1);assert.equal(fanout([['a'],['b'],['c']],2).workers,2);assert.equal(fanout([['a'],['b']],0).workers,0);assert.equal(fanout([['a'],['b']],8,true).workers,1);
});
test('budget brake handles token limit unknown prices and cache accounting',()=>{
 const chief=budgetState({inputTokens:199310,cachedInputTokens:153216,outputTokens:827});
 assert.equal(chief.effectiveTokens,62242.6);assert.equal(chief.blocked,false);assert.equal(chief.limit,2000000);
 assert.match(chief.formula,/cached\*0\.1/);
 assert.equal(budgetState({inputTokens:100,cachedInputTokens:999,outputTokens:10},19).blocked,true);
 assert.equal(budgetState({inputTokens:80,outputTokens:30},100,'unknown',{}).blocked,true);
 assert.equal(budgetState({inputTokens:10,outputTokens:2},100,'unknown',{}).cost,null);
});
test('brief compiler preserves seven fields, exact user words, and rejects overflow',()=>{
 const fields={Goal:'do task',Evidence:'fixture', 'Write scope':'src/',Boundaries:'no publish','Done when':'test','Return format':'six fields',"User's words":'exact words'};
 const brief=compileBrief(fields);assert.ok(brief.text.includes("User's words:\nexact words"));assert.throws(()=>compileBrief({...fields,Evidence:'x'.repeat(30000)},100));
});
test('schema handoff is strict and converts to the six field checker format',()=>{
 assert.equal(handoffSchema.required.length,6);const object={outcome:'ok',evidence:'proof',changed_scope:'none',risks:'none',open_questions:'none',next_verification:'none'};assert.ok(toHandoff(object).startsWith('Outcome: ok'));assert.throws(()=>toHandoff({...object,risks:''}));
});
test('limit queue triggers by fake clock, backs off and skips manual continuation',()=>{
 const now=1000000;assert.equal(detectLimit({code:'rate_limit_exceeded',resetsAt:2000},now).dueAt,2000000);
 const q=new LimitQueue();q.plan('thread',2,now);assert.equal(q.due(now-1,2),'wait');assert.equal(q.due(now,3),'superseded');q.plan('thread',3,now);assert.equal(q.due(now,3),'resume');q.failed(now);assert.equal(q.value.dueAt,now+15*60000);q.failed(now);assert.equal(q.value.dueAt,now+60*60000);q.failed(now);assert.equal(q.value.dueAt,now+180*60000);q.failed(now);assert.equal(q.value.status,'abandoned');
});
