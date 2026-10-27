import test from 'node:test';import assert from 'node:assert/strict';import {fileURLToPath} from 'node:url';
import {AppServerRpc} from './protocol.mjs';
const fixture=fileURLToPath(new URL('./fixtures/app-server.mjs',import.meta.url));
test('persistent stdio thread, steer, interrupt, events and approvals',async()=>{
  const rpc=new AppServerRpc({command:process.execPath,args:[fixture],cwd:process.cwd(),timeout:2000});
  try{
    await rpc.initialize();const {thread}=await rpc.call('thread/start',{cwd:process.cwd(),sandbox:'workspace-write',approvalPolicy:'on-request'});
    assert.equal(thread.id,'11111111-1111-4111-8111-111111111111');
    const events=[];rpc.on('notification',m=>events.push(m));
    const request=new Promise(resolve=>rpc.once('request',resolve));
    await rpc.call('turn/start',{threadId:thread.id,input:[{type:'text',text:'wait'}]});
    assert.equal((await rpc.call('turn/steer',{threadId:thread.id,expectedTurnId:'turn-1',input:[{type:'text',text:'extra'}]})).turnId,'turn-1');
    await rpc.call('turn/interrupt',{threadId:thread.id,turnId:'turn-1'});
    await rpc.call('turn/start',{threadId:thread.id,input:[{type:'text',text:'approval'}]});
    const approval=await request;assert.equal(approval.id,9001);rpc.respond(approval.id,{decision:'decline'});
    const secondClient=await rpc.call('thread/read',{threadId:thread.id});assert.equal(secondClient.thread.turns,2);
    assert.ok(events.some(m=>m.method==='turn/completed'));
    assert.equal((await rpc.call('thread/resume',{threadId:thread.id})).thread.id,thread.id);
  }finally{await rpc.close();}
});
test('unknown methods reject without leaking raw diagnostics',async()=>{
  const rpc=new AppServerRpc({command:process.execPath,args:[fixture],cwd:process.cwd(),timeout:1000});
  try{await rpc.initialize();await assert.rejects(rpc.call('bad',{}),/RPC -32601/);}finally{await rpc.close();}
});
