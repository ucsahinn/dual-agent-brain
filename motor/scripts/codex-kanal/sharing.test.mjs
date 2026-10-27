import test from 'node:test';import assert from 'node:assert/strict';import {fileURLToPath} from 'node:url';import {startShared} from './sharing.mjs';import {AppServerRpc} from './protocol.mjs';import {WebSocketTransport} from './websocket.mjs';
test('two authenticated clients share one fake server thread',async()=>{
 const backend=await startShared({command:process.execPath,args:[fileURLToPath(new URL('./fixtures/ws-app-server.mjs',import.meta.url)),'app-server','--listen','stdio://'],cwd:process.cwd()});
 let second;try{
  await backend.rpc.initialize();const a=await backend.rpc.call('thread/start',{});
  second=new AppServerRpc({transport:await WebSocketTransport.connect(backend.url,backend.token)});await second.initialize();
  const b=await second.call('thread/read',{threadId:a.thread.id});assert.equal(b.thread.id,a.thread.id);
  assert.ok(!backend.args.includes(backend.token));
 }finally{await second?.close();await backend.close();}
});
test('a squatted port receives no bearer token before peer ownership verification',async()=>{
 let checked=0,unexpected;
 try{await assert.rejects((async()=>{unexpected=await startShared({command:process.execPath,args:[fileURLToPath(new URL('./fixtures/ws-app-server.mjs',import.meta.url)),'app-server','--listen','stdio://'],cwd:process.cwd(),startupMs:1000,verifyPeer:async()=>{checked++;return false;}});return unexpected;})(),/startup|ownership/);}finally{await unexpected?.close();}
 assert.ok(checked>0);
});
