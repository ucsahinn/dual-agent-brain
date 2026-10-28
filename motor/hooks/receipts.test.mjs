import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';import os from 'node:os';import path from 'node:path';
import {spawnSync} from 'node:child_process';import {fileURLToPath} from 'node:url';
const hook=fileURLToPath(new URL('./kill-guard-on.mjs',import.meta.url));
const lib=fileURLToPath(new URL('./lib.ps1',import.meta.url));
for(const failFirst of [false,true])test('JS PreToolUse shares saved displayed read receipts, once; receipt lock failure first='+failFirst,()=>{
 const root=fs.mkdtempSync(path.join(os.tmpdir(),'beyin-receipts-'));
 const ps=path.join(root,'fixture.ps1');
 const run=action=>{fs.writeFileSync(ps,`. '${lib.replaceAll("'","''")}'\n$p=Get-BeyinPaths -Vault '${root.replaceAll("'","''")}'\n${action}`);const r=spawnSync('powershell.exe',['-NoProfile','-File',ps],{encoding:'utf8',windowsHide:true});assert.equal(r.status,0,r.stderr);return r.stdout.trim();};
 try{
  const id=run("(Add-BeyinHandoff -Paths $p -Metin 'receipt fixture' -Kime claude -GorunumYok).Id");
  const invoke=()=>spawnSync(process.execPath,[hook],{input:JSON.stringify({session_id:'receipt-session',cwd:root,tool_input:{command:'pwd'}}),env:{...process.env,BEYIN_VAULT:root,BEYIN_CHILD:'0',BEYIN_KILL_GUARD:'kapali',BEYIN_AKTAR_ANLIK:'acik'},encoding:'utf8',windowsHide:true});
  if(failFirst){
   const lock=path.join(root,'motor/scripts/.state/makbuz/makbuz.node.lock');fs.writeFileSync(lock,'fixture lock');
   const failed=invoke();assert.equal(failed.status,0);assert.equal(failed.stdout,'');
   assert.equal(fs.existsSync(path.join(root,'motor/scripts/.state/handoff-teslim/receipt-session',id)),false);
   assert.equal(fs.existsSync(path.join(root,'motor/scripts/.state/handoff-teslim/receipt-session.damga')),false);
   fs.unlinkSync(lock);
  }
  const first=invoke();assert.equal(first.status,0);assert.match(first.stdout,/receipt fixture/);assert.equal(invoke().stdout,'');
  run(`$null=Read-BeyinHandoff -Paths $p -Id '${id}' -Agent claude`);
  const records=fs.readdirSync(path.join(root,'motor/scripts/.state/makbuz')).filter(n=>n.endsWith('.jsonl')).flatMap(n=>fs.readFileSync(path.join(root,'motor/scripts/.state/makbuz',n),'utf8').trim().split('\n').map(JSON.parse)).filter(r=>r.note.includes(id));
  assert.deepEqual(records.map(r=>r.outcome),['KAYDEDILDI','GOSTERILDI','OKUNDU']);
  for(const r of records){assert.equal(r.v,1);assert.equal(r.script,'aktar');assert.ok(r.ts);assert.equal(typeof r.note,'string');}
 }finally{fs.rmSync(root,{recursive:true,force:true});}
});
