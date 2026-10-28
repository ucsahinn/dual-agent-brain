import test from 'node:test';import assert from 'node:assert/strict';import fs from 'node:fs';import os from 'node:os';import path from 'node:path';import {fileURLToPath} from 'node:url';import {ChannelHost} from './host-service.mjs';
for(const mode of ['fallback','rpc-error','stderr-only','warning','always','unrelated','profile','effect-crash','tool-handoff','tool-handoff-snake','transient'])test('sandbox diagnostics and outcome: '+mode,async()=>{
 const root=fs.mkdtempSync(path.join(os.tmpdir(),'beyin-fallback-')),id='CK-'+'b'.repeat(32),secret='sk-'+'Q'.repeat(32);
 fs.writeFileSync(path.join(root,id+'.json'),JSON.stringify({Owner:'beyin-codex-kanal-v1',Id:id,OwnerSession:'owner',Project:root,Turn:0,Sandbox:'workspace-write'}));
 const host=new ChannelHost({state:root,id,owner:'owner',command:process.execPath,args:[fileURLToPath(new URL('./fixtures/fallback-server.mjs',import.meta.url)),mode],windowsSandbox:mode==='profile'?'unelevated':'elevated',timeout:1000,sleep:async()=>{}});
 try{await host.start();const result=await host.dispatch({owner:'owner',method:'sor',text:'task'});
  if(['fallback','rpc-error','stderr-only'].includes(mode)){assert.equal(result.Status,'completed');assert.equal(result.Attempts,3);assert.equal(result.SandboxFallback.To,'unelevated');assert.equal(result.Sandbox,'workspace-write');}
  if(['tool-handoff','tool-handoff-snake'].includes(mode)){assert.equal(result.Status,'completed');assert.equal(result.Attempts,1);assert.equal(result.Error,'');assert.match(result.Warnings.join('\n'),/setup refresh/);assert.ok(!result.SandboxFallback);}
  if(mode==='transient'){assert.equal(result.Status,'completed');assert.equal(result.Attempts,2);assert.equal(result.WindowsSandbox,'elevated');assert.ok(!result.SandboxFallback);}
  if(mode==='warning'){assert.equal(result.Status,'completed');assert.equal(result.Attempts,1);assert.ok(!result.SandboxFallback);assert.equal(result.Error,'');assert.match(result.Warnings.join('\n'),/setup refresh/);}
  if(mode==='profile'){assert.equal(result.Status,'completed');assert.equal(result.Attempts,1);assert.equal(result.WindowsSandbox,'unelevated');assert.ok(!result.SandboxFallback);}
  if(mode==='effect-crash'){assert.equal(result.Status,'failed');assert.equal(result.Attempts,1);assert.ok(!result.SandboxFallback);}
  if(mode==='always'){assert.equal(result.Status,'failed');assert.equal(result.Attempts,3);assert.match(result.Error,/setup refresh/);assert.match(result.StderrTail,/setup refresh/);}
  if(mode==='unrelated'){assert.equal(result.Status,'failed');assert.equal(result.Attempts,1);assert.match(result.Error,/unrelated failure/);}
  for(const retry of result.RetryEvents||[])if(retry.Reason==='sandbox-tool-failure')assert.ok(retry.DelaySeconds>=10&&retry.DelaySeconds<=40);
  const event=fs.readFileSync(path.join(root,id,'events.jsonl'),'utf8');if(mode!=='profile')assert.match(event,/message|StderrTail/);assert.ok(!event.includes(secret));assert.ok(!fs.readFileSync(path.join(root,id+'.json'),'utf8').includes(secret));
 }finally{await host.close();fs.rmSync(root,{recursive:true,force:true});}
});
