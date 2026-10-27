import test from 'node:test';import assert from 'node:assert/strict';import fs from 'node:fs';import path from 'node:path';import os from 'node:os';import {fileURLToPath} from 'node:url';
import {ClaudeRpc} from './stream.mjs';
test('Claude control handshake completes before any user turn',async()=>{
 const rpc=new ClaudeRpc({command:process.execPath,args:[fileURLToPath(new URL('./fixtures/claude.mjs',import.meta.url))],cwd:process.cwd(),timeout:1000});
 try{const result=await rpc.initialize();assert.equal(result.capabilities?.toolApproval,true);}finally{await rpc.close();}
});
test('fake Claude keeps context across two turns and a resumed process',async()=>{
 const dir=fs.mkdtempSync(path.join(os.tmpdir(),'beyin-claude-')),state=path.join(dir,'fake-context');
 const config={command:process.execPath,args:[fileURLToPath(new URL('./fixtures/claude.mjs',import.meta.url)),'--fixture-state',state],cwd:dir};
 let rpc=new ClaudeRpc(config);const run=async text=>{const completed=new Promise(resolve=>{const fn=m=>{if(m.method==='turn/completed'){rpc.off('notification',fn);resolve(m);}};rpc.on('notification',fn);});let answer='';const capture=m=>{if(m.method==='item/completed')answer=m.params.item.text;};rpc.on('notification',capture);await rpc.call('turn/start',{input:[{type:'text',text}]});await completed;rpc.off('notification',capture);return answer;};
 try{await rpc.initialize();const sid=(await rpc.call('thread/start',{})).thread.id;await run('remember');assert.match(await run('recall'),/synthetic-memory/);await rpc.close();rpc=new ClaudeRpc({...config,sessionId:sid});await rpc.initialize();assert.equal((await rpc.call('thread/resume',{threadId:sid})).thread.id,sid);assert.match(await run('recall'),/synthetic-memory/);}finally{await rpc.close();fs.rmSync(dir,{recursive:true,force:true});}
});
