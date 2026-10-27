import {spawn} from 'node:child_process';import {EventEmitter} from 'node:events';import readline from 'node:readline';import {randomUUID} from 'node:crypto';
import {handoffSchema} from '../codex-kanal/policy.mjs';
export class ClaudeRpc extends EventEmitter {
 constructor(config){super();this.cfg=config;this.sessionId=config.sessionId||randomUUID();this.resume=Boolean(config.sessionId);this.turn=0;this.active=null;this.approvals=new Map();this.controls=new Map();this.usage={inputTokens:0,outputTokens:0,cachedInputTokens:0};this.closing=false;this.threadStarted=false;}
 spawn(){
  const args=[...this.cfg.args,'-p','--input-format','stream-json','--output-format','stream-json','--verbose','--permission-mode','default','--permission-prompt-tool','stdio','--strict-mcp-config','--mcp-config',JSON.stringify({mcpServers:{}}),'--json-schema',JSON.stringify(handoffSchema),this.resume?'--resume':'--session-id',this.sessionId];
  if(this.cfg.readOnly)args.push('--tools','Read,Glob,Grep');
  // Match the official SDK child environment; do not change the parent or any
  // persisted configuration. CLAUDECODE is the CLI's nested interactive marker.
  const childEnv={...process.env};delete childEnv.CLAUDECODE;
  const child=spawn(this.cfg.command,args,{cwd:this.cfg.cwd,env:childEnv,windowsHide:true,shell:false,stdio:['pipe','pipe','pipe']});this.process=child;
  child.stderr.on('data',()=>{});child.stdin.on('error',()=>{});
  child.on('error',()=>{if(this.process===child){this.active=null;this.approvals.clear();this.rejectControls();this.emit('closed');}});
  child.on('exit',()=>{if(this.process===child&&!this.closing){this.resume=true;this.process=null;this.active=null;this.approvals.clear();this.rejectControls();this.emit('closed');}});
  readline.createInterface({input:child.stdout}).on('line',line=>{if(this.process!==child||line.length>1048576)return;let m;try{m=JSON.parse(line);}catch{this.emit('protocolWarning','invalid-json');return;}this.receive(m);});
 }
 rejectControls(){for(const control of this.controls.values()){clearTimeout(control.timer);control.reject(new Error('Claude control connection closed'));}this.controls.clear();}
 handshake(){return new Promise((resolve,reject)=>{
  const id=randomUUID();const timer=setTimeout(()=>{this.controls.delete(id);reject(new Error('Claude initialize timeout'));},this.cfg.timeout||15000);
  this.controls.set(id,{resolve,reject,timer});this.process.stdin.write(JSON.stringify({type:'control_request',request_id:id,request:{subtype:'initialize',hooks:null}})+'\n');
 });}
 async initialize(){this.spawn();return this.handshake();}
 receive(m){
  if(m.type==='control_response'){const control=this.controls.get(m.response?.request_id);if(control){clearTimeout(control.timer);this.controls.delete(m.response.request_id);m.response.subtype==='success'?control.resolve(m.response.response||{}):control.reject(new Error('Claude control request rejected'));}return;}
  if(m.type==='system'&&m.subtype==='init'&&m.session_id!==this.sessionId){this.emit('protocolWarning','session-mismatch');return;}
  if(m.type==='system'&&m.subtype==='init'&&typeof m.model==='string'&&/^[A-Za-z0-9._:-]+$/.test(m.model)){this.model=m.model;this.emit('notification',{method:'thread/modelUpdated',params:{threadId:this.sessionId,model:m.model}});}
  if(m.type==='control_request'){
   if(m.request?.subtype!=='can_use_tool'){this.process.stdin.write(JSON.stringify({type:'control_response',response:{subtype:'error',request_id:m.request_id,error:'Unsupported control request'}})+'\n');return;}
   this.approvals.set(m.request_id,m.request);this.emit('request',{id:m.request_id,method:'claude/toolApproval',params:{toolName:m.request.tool_name,input:m.request.input,command:m.request.input?.command||'',cwd:this.cfg.cwd}});return;
  }
  if(m.type==='assistant'&&this.active){for(const part of m.message?.content||[])if(part.type==='text')this.active.answer=part.text;}
  if(m.type==='result'&&this.active){
   const active=this.active;this.active=null;
   const text=m.structured_output?JSON.stringify(m.structured_output):(m.result||active.answer||'');
   this.emit('notification',{method:'item/completed',params:{threadId:this.sessionId,turnId:active.id,item:{type:'agentMessage',text}}});
   this.usage.inputTokens+=Number(m.usage?.input_tokens||0)+Number(m.usage?.cache_read_input_tokens||0)+Number(m.usage?.cache_creation_input_tokens||0);this.usage.outputTokens+=Number(m.usage?.output_tokens||0);this.usage.cachedInputTokens+=Number(m.usage?.cache_read_input_tokens||0);
   this.emit('notification',{method:'thread/tokenUsage/updated',params:{threadId:this.sessionId,tokenUsage: { total: { ...this.usage } }}});
   this.emit('notification',{method:'turn/completed',params:{threadId:this.sessionId,turn:{id:active.id,status:m.is_error?'failed':'completed',error:m.is_error?{code:m.subtype}:null}}});
  }
 }
 async call(method,params={}){
  if(method==='thread/start'||method==='thread/resume'){
   if(method==='thread/start'&&this.threadStarted){await this.stopProcess();this.closing=false;this.sessionId=randomUUID();this.resume=false;this.spawn();await this.handshake();}
   if(method==='thread/resume'&&params.threadId!==this.sessionId)throw new Error('Claude thread is not owned');this.threadStarted=true;return {thread:{id:this.sessionId}};
  }
  if(method==='turn/start'){
   if(this.active)throw new Error('Claude turn already active');if(!this.process){this.closing=false;this.resume=true;this.spawn();await this.handshake();}
   const id='claude-turn-'+(++this.turn);this.active={id,answer:''};
   this.emit('notification',{method:'turn/started',params:{threadId:this.sessionId,turn:{id}}});
   this.process.stdin.write(JSON.stringify({type:'user',session_id:this.sessionId,parent_tool_use_id:null,message:{role:'user',content:params.input.map(p=>p.text||'').join('\n')}})+'\n');return {turn:{id,status:'inProgress'}};
  }
  if(method==='turn/interrupt'){
   if(this.active){const id=this.active.id;this.active=null;await this.stopProcess();this.closing=false;this.resume=true;this.emit('notification',{method:'turn/completed',params:{threadId:this.sessionId,turn:{id,status:'interrupted'}}});}return {};
  }
  throw new Error('Claude stream operation unsupported');
 }
 respond(id,result){
  const request=this.approvals.get(id);if(!request)throw new Error('Unknown Claude approval');this.approvals.delete(id);
  const response=result.decision==='accept'?{behavior:'allow',updatedInput:request.input}:{behavior:'deny',message:'Owner declined this request'};
  this.process.stdin.write(JSON.stringify({type:'control_response',response:{subtype:'success',request_id:id,response}})+'\n');
 }
 async stopProcess(){const child=this.process;this.process=null;this.rejectControls();if(!child)return;this.closing=true;child.stdin.end();await new Promise(resolve=>{if(child.exitCode!==null)return resolve();const timer=setTimeout(()=>{child.kill();resolve();},1000);child.once('exit',()=>{clearTimeout(timer);resolve();});});}
 async close(){await this.stopProcess();this.emit('closed');}
}
