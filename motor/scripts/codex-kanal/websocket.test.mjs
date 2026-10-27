import test from 'node:test';import assert from 'node:assert/strict';import http from 'node:http';import {createHash} from 'node:crypto';
import {WebSocketTransport,tuiPlan} from './websocket.mjs';
test('loopback websocket authenticates without an Origin and rejects a wrong token',async()=>{
 const token=['fixture','W'.repeat(32)].join('-'), sockets=new Set();
 const server=http.createServer();server.on('upgrade',(req,socket)=>{
  sockets.add(socket);socket.on('close',()=>sockets.delete(socket));
  if(req.headers.origin||req.headers.authorization!=='Bearer '+token){socket.end('HTTP/1.1 403 Forbidden\r\nContent-Length: 0\r\n\r\n');return;}
  const accept=createHash('sha1').update(req.headers['sec-websocket-key']+'258EAFA5-E914-47DA-95CA-C5AB0DC85B11').digest('base64');
  socket.write('HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: '+accept+'\r\n\r\n');
  socket.on('data',chunk=>{if((chunk[0]&15)===8){socket.end();return;}const body=Buffer.from('{"fixture":true}');socket.write(Buffer.concat([Buffer.from([0x81,body.length]),body]));});
 });
 await new Promise(r=>server.listen(0,'127.0.0.1',r));const url='ws://127.0.0.1:'+server.address().port;
 try{
  await assert.rejects(WebSocketTransport.connect(url,'wrong'),/handshake/);
  const status=await new Promise((resolve,reject)=>{const req=http.get({hostname:'127.0.0.1',port:server.address().port,headers:{Origin:'https://fixture.invalid',Authorization:'Bearer '+token,Connection:'Upgrade',Upgrade:'websocket','Sec-WebSocket-Version':'13','Sec-WebSocket-Key':'fixture'}},res=>{res.resume();resolve(res.statusCode);});req.on('error',reject);req.setTimeout(2000,()=>req.destroy(new Error('Origin rejection timeout')));});assert.equal(status,403);
  const transport=await WebSocketTransport.connect(url,token);
  const response=new Promise(r=>transport.once('message',r));transport.send('{"test":true}');assert.deepEqual(JSON.parse(await response),{fixture:true});transport.close();
  const plan=tuiPlan({threadId:'owned-thread',url,token,command:'node',args:['codex.js']});
  assert.ok(!JSON.stringify(plan.args).includes(token));assert.equal(plan.env.BEYIN_REMOTE_TOKEN,token);assert.ok(plan.args.includes('owned-thread'));
 }finally{for(const s of sockets)s.destroy();await new Promise(r=>server.close(r));}
});
