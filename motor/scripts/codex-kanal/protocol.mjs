import {spawn} from 'node:child_process';
import readline from 'node:readline';
import {EventEmitter} from 'node:events';

// JSON-RPC without the jsonrpc header, as specified by Codex app-server.
// Never attach raw stderr or server error strings to durable client errors.
export class AppServerRpc extends EventEmitter {
  constructor({command,args=[],cwd,env=process.env,timeout=15000,transport}){
    super();this.sequence=0;this.pending=new Map();this.timeout=timeout;this.closed=false;this.stderrTail='';
    if(transport){this.transport=transport;transport.on('message',line=>this.receive(line));transport.on('close',()=>this.ended({source:'transport-close'}));transport.on('error',()=>this.ended({source:'transport-error'}));return;}
    this.process=spawn(command,args,{cwd,env,windowsHide:true,shell:false,stdio:['pipe','pipe','pipe']});
    this.process.stderr.on('data',chunk=>{this.stderrTail=(this.stderrTail+chunk.toString('utf8')).slice(-16384);});
    // close follows stdout drain; exit may precede the final successful tool item.
    this.process.on('error',()=>this.ended({source:'process-error'}));this.process.on('close',(code,signal)=>this.ended({source:'process-close',code,signal}));
    this.process.stdin.on('error',()=>this.ended({source:'stdin-error'}));
    const rl=readline.createInterface({input:this.process.stdout});
    rl.on('line',line=>this.receive(line));
  }
  receive(line){
    // A large tool result is not a process exit. Keep draining the live stream
    // so the authoritative turn completion can still reach its caller.
    if(Buffer.byteLength(line)>16777216){this.emit('protocolWarning','oversized-message-skipped');return;}
    let m;try{m=JSON.parse(line);}catch{this.emit('protocolWarning','invalid-json');return;}
    if(m.method){this.emit(m.id===undefined?'notification':'request',m);return;}
    const waiter=this.pending.get(m.id);if(!waiter)return;
    this.pending.delete(m.id);clearTimeout(waiter.timer);
    if(m.error){this.emit('notification',{method:'error',params:{error:m.error}});waiter.reject(new Error(`RPC ${Number(m.error.code)||0}`));}else waiter.resolve(m.result);
  }
  write(message){
    if(this.closed)throw new Error('App-server connection closed');
    const line=JSON.stringify(message);
    if(this.transport)this.transport.send(line);else this.process.stdin.write(line+'\n');
  }
  call(method,params={}){
    if(this.pending.size>=128)return Promise.reject(new Error('Too many pending RPC requests'));
    const id=++this.sequence;
    return new Promise((resolve,reject)=>{
      const timer=setTimeout(()=>{this.pending.delete(id);reject(new Error(`RPC timeout: ${method}`));},this.timeout);
      this.pending.set(id,{resolve,reject,timer});
      try{this.write({id,method,params});}catch(e){clearTimeout(timer);this.pending.delete(id);reject(e);}
    });
  }
  respond(id,result){this.write({id,result});}
  async initialize(){
    const result=await this.call('initialize',{clientInfo:{name:'beyin_kanal',version:'2.0.0'},capabilities:{experimentalApi:true}});
    this.write({method:'initialized',params:{}});return result;
  }
  ended(detail){if(this.closed)return;this.closed=true;for(const w of this.pending.values()){clearTimeout(w.timer);w.reject(new Error('App-server exited'));}this.pending.clear();this.emit('closed',detail);}
  async close(){
    if(this.transport){this.transport.close();this.ended();return;}
    if(!this.process)return;
    this.process.stdin.end();
    if(this.process.exitCode===null){await new Promise(resolve=>{const timer=setTimeout(()=>{this.process.kill();resolve();},1000);this.process.once('exit',()=>{clearTimeout(timer);resolve();});});}
    this.ended();
  }
}
