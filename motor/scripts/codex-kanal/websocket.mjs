import http from 'node:http';import net from 'node:net';import {randomBytes,createHash} from 'node:crypto';import {EventEmitter} from 'node:events';
import {loopbackEndpoint} from './spike.mjs';

// Small RFC6455 client for the local app-server. No listener or Origin header.
export class WebSocketTransport extends EventEmitter {
 static async connect(endpoint,token,verifyPeer){
  const url=new URL(loopbackEndpoint(endpoint));if(!token)return Promise.reject(new Error('WebSocket token required'));
  let agent=false,verifiedSocket;
  if(verifyPeer){
   verifiedSocket=net.connect({host:url.hostname,port:Number(url.port)});
   try{
    await new Promise((resolve,reject)=>{const timer=setTimeout(()=>{verifiedSocket.destroy();reject(new Error('Peer connection timeout'));},3000);verifiedSocket.once('connect',()=>{clearTimeout(timer);resolve();});verifiedSocket.once('error',e=>{clearTimeout(timer);reject(e);});});
    // No HTTP bytes or bearer token are sent until the peer of this very socket
    // is verified. Reusing it avoids a check/reconnect port ownership race.
    if(!await verifyPeer(verifiedSocket.localPort))throw new Error('WebSocket peer ownership rejected');
    agent=new http.Agent({keepAlive:false});agent.createConnection=()=>verifiedSocket;
   }catch(e){verifiedSocket.destroy();throw e;}
  }
  return new Promise((resolve,reject)=>{
   const key=randomBytes(16).toString('base64');
   const request=http.request({hostname:url.hostname,port:url.port,path:'/',method:'GET',agent,headers:{Connection:'Upgrade',Upgrade:'websocket','Sec-WebSocket-Version':'13','Sec-WebSocket-Key':key,Authorization:'Bearer '+token}});
   const timer=setTimeout(()=>{request.destroy();reject(new Error('WebSocket handshake timeout'));},5000);
   request.on('upgrade',(response,socket,head)=>{
    clearTimeout(timer);const expected=createHash('sha1').update(key+'258EAFA5-E914-47DA-95CA-C5AB0DC85B11').digest('base64');
    if(response.headers['sec-websocket-accept']!==expected){socket.destroy();reject(new Error('Invalid WebSocket handshake'));return;}
    const transport=new WebSocketTransport(socket);if(head.length)queueMicrotask(()=>transport.consume(head));resolve(transport);
   });
   request.on('response',response=>{clearTimeout(timer);response.resume();reject(new Error('WebSocket handshake rejected'));});
   request.on('error',e=>{clearTimeout(timer);reject(new Error('WebSocket handshake failed: '+(e.code||'transport')));});request.end();
  });
 }
 constructor(socket){
  super();this.socket=socket;this.buffer=Buffer.alloc(0);this.fragments=[];this.fragmentBytes=0;
  socket.on('data',chunk=>this.consume(chunk));socket.on('close',()=>this.emit('close'));socket.on('error',()=>socket.destroy());
 }
 frame(opcode,body){
  if(body.length>1048576)throw new Error('WebSocket message too large');
  const mask=randomBytes(4);let header;
  if(body.length<126)header=Buffer.from([0x80|opcode,0x80|body.length]);
  else if(body.length<65536){header=Buffer.alloc(4);header[0]=0x80|opcode;header[1]=0xFE;header.writeUInt16BE(body.length,2);}
  else{header=Buffer.alloc(10);header[0]=0x80|opcode;header[1]=0xFF;header.writeBigUInt64BE(BigInt(body.length),2);}
  const payload=Buffer.from(body);for(let i=0;i<payload.length;i++)payload[i]^=mask[i%4];
  this.socket.write(Buffer.concat([header,mask,payload]));
 }
 send(text){this.frame(1,Buffer.from(text,'utf8'));}
 consume(chunk){
  this.buffer=Buffer.concat([this.buffer,chunk]);
  if(this.buffer.length>2097152){this.socket.destroy();return;}
  while(this.buffer.length>=2){
   const first=this.buffer[0],opcode=first&15,masked=this.buffer[1]&128;let length=this.buffer[1]&127,offset=2;
   if(masked){this.socket.destroy();return;}
   if(length===126){if(this.buffer.length<4)return;length=this.buffer.readUInt16BE(2);offset=4;}
   if(length===127){if(this.buffer.length<10)return;const n=this.buffer.readBigUInt64BE(2);if(n>1048576n){this.socket.destroy();return;}length=Number(n);offset=10;}
   if(length>1048576){this.socket.destroy();return;}if(this.buffer.length<offset+length)return;
   const payload=this.buffer.subarray(offset,offset+length);this.buffer=this.buffer.subarray(offset+length);
   if(opcode===8){this.socket.end();return;}if(opcode===9){this.frame(10,payload);continue;}if(opcode===10)continue;
   if(![0,1].includes(opcode)||(opcode===0&&!this.fragments.length)||(opcode===1&&this.fragments.length)){this.socket.destroy();return;}
   this.fragments.push(payload);this.fragmentBytes+=payload.length;if(this.fragmentBytes>1048576){this.socket.destroy();return;}
   if(first&128){const message=Buffer.concat(this.fragments).toString('utf8');this.fragments=[];this.fragmentBytes=0;this.emit('message',message);}
  }
 }
 close(){if(!this.socket.destroyed){this.frame(8,Buffer.alloc(0));this.socket.end();}}
}
export function tuiPlan({threadId,url,token,command,args=[]}){
 if(!threadId||!token)throw new Error('Owned thread and token required');loopbackEndpoint(url);
 return {command,args:[...args,'resume',threadId,'--remote',url,'--remote-auth-token-env','BEYIN_REMOTE_TOKEN'],env:{BEYIN_REMOTE_TOKEN:token}};
}
