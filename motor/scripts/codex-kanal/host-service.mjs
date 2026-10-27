import fs from 'node:fs';import path from 'node:path';import {fileURLToPath} from 'node:url';import {randomUUID,createHash} from 'node:crypto';
import {AppServerRpc} from './protocol.mjs';
import {startShared,launchTui} from './sharing.mjs';
import {Supervisor,Ledger} from './supervisor.mjs';
import {ClaudeRpc} from '../claude-kanal/stream.mjs';
import {approvalPolicy,briefWriteScopes,budgetState,detectLimit,LimitQueue,handoffSchema,toHandoff} from './policy.mjs';
import {spawnSync} from 'node:child_process';
import {acquireSetupLock} from './setup-lock.mjs';

export function redact(value,secrets=[]){
 if(typeof value!=='string')return JSON.stringify(sanitize(value,secrets));
 let text=value;
 for(const secret of secrets)if(secret)text=text.split(secret).join('[REDACTED]');
 return text.replace(/sk-ant-[A-Za-z0-9_-]{16,}|sk-[A-Za-z0-9_-]{24,}|gh[pousr]_[A-Za-z0-9]{24,}|github_pat_[A-Za-z0-9_]{24,}|xox[baprs]-[A-Za-z0-9-]{10,}|eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+/g,'[REDACTED]')
 .replace(/-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z ]*PRIVATE KEY-----/g,'[REDACTED]')
 .replace(/((?:authorization|cookie)\s*:\s*)[^\r\n]+/gi,'$1[REDACTED]')
 .replace(/((?:password|passwd|secret|token|api[_-]?key)\s*[:=]\s*)(["'])(.*?)\2/gi,'$1$2[REDACTED]$2')
 .replace(/((?:password|passwd|secret|token|api[_-]?key|authorization|CLAUDE_CODE_MESSAGING_TOKEN)\s*["']?\s*[:=]\s*["']?)([^\s,"'{}]+)/gi,'$1[REDACTED]');
}
export function sanitize(value,secrets=[]){
 if(typeof value==='string')return redact(value,secrets);
 if(Array.isArray(value))return value.map(v=>sanitize(v,secrets));
 if(value&&typeof value==='object')return Object.fromEntries(Object.entries(value).map(([key,v])=>[key,/^(?:token|secret|password|passwd|authorization|cookie|api_key|apiKey|privateKey|connectionString|CLAUDE_CODE_MESSAGING_TOKEN)$/i.test(key)?'[REDACTED]':sanitize(v,secrets)]));
 return value;
}
export function atomicJson(file,value,secrets=[],io=fs){
 const tmp=file+'.'+randomUUID()+'.tmp';io.writeFileSync(tmp,JSON.stringify(sanitize(value,secrets)),{encoding:'utf8',mode:0o600});
 try{for(let attempt=0;;attempt++){
  try{io.renameSync(tmp,file);return;}catch(e){if(!['EPERM','EACCES','EBUSY'].includes(e.code)||attempt>=19)throw e;Atomics.wait(new Int32Array(new SharedArrayBuffer(4)),0,0,25);}
 }}catch(e){try{io.unlinkSync(tmp);}catch{}throw e;}
}
const labels=['Outcome','Evidence','Changed scope','Risks','Open questions','Next verification'];
const modelNotFound=value=>/model_not_found|modelnotfound|model is not supported when using Codex with a ChatGPT account/i.test(typeof value==='string'?value:JSON.stringify(value));
export function validHandoff(text){
 text=text.replace(/\r\n/g,'\n');
 const matches=[...text.matchAll(new RegExp('^[ \\t]*(?:#{1,6}[ \\t]+)?(?:\\*\\*)?('+labels.join('|')+')(?:\\*\\*)?[ \\t]*:[ \\t]*(?:\\*\\*)?(.*)$','gm'))];
 if(matches.length!==labels.length)return false;
 for(let i=0;i<labels.length;i++){if(matches[i][1]!==labels[i])return false;const end=i+1<labels.length?matches[i+1].index:text.length;const body=matches[i][2]+text.slice(matches[i].index+matches[i][0].length,end);if(!body.trim())return false;}
 return true;
}
export class ChannelHost {
 constructor(config){
  if(!/^CK-[a-f0-9]{32}$/.test(config.id))throw new Error('Invalid channel id');
  this.cfg=config;this.file=path.join(config.state,config.id+'.json');this.directory=path.join(config.state,config.id);
  this.record=JSON.parse(fs.readFileSync(this.file,'utf8').replace(/^\uFEFF/,''));
  if(this.record.Owner!=='beyin-codex-kanal-v1'||this.record.OwnerSession!==config.owner)throw new Error('Channel owner mismatch');
  fs.mkdirSync(path.join(this.directory,'commands'),{recursive:true});fs.mkdirSync(path.join(this.directory,'responses'),{recursive:true});
  this.approvals=new Map();this.active=null;this.stopping=false;this.lastEvent=Date.now();
  this.secretValues=[];
  this.supervisor=new Supervisor(config.supervisor);this.ledger=new Ledger(path.join(this.directory,'ledger.json'));this.idleSince=Date.now();
  this.limitQueue=new LimitQueue(this.record.LimitQueue);this.turnQueue=Promise.resolve();this.autoResuming=false;
  this.prices={};if(config.pricesFile){try{this.prices=JSON.parse(fs.readFileSync(config.pricesFile,'utf8').replace(/^\uFEFF/,''));}catch{}}
 }
 rememberSecret(value){if(value&&!this.secretValues.includes(value))this.secretValues.push(value);}
 async enterSetup(){
  if(this.cfg.engine==='claude')return;
  if(this.setupLease)return;
  this.setupLease=await (this.cfg.acquireSetup||acquireSetupLock)(this.cfg.setupLockOptions);
  this.record.SetupLock={Name:'Local\\Beyin-codex-setup',AcquiredAt:new Date().toISOString(),MaxHoldSeconds:60};this.save();
  this.setupTimer=setTimeout(()=>this.leaveSetup('deadline'),60000);this.setupTimer.unref();
 }
 leaveSetup(reason){
  if(!this.setupLease)return;this.setupLease.release();this.setupLease=null;clearTimeout(this.setupTimer);
  this.record.SetupLock.ReleasedAt=new Date().toISOString();this.record.SetupLock.ReleaseReason=reason;this.save();
 }
 save(){this.record.LastEvent=new Date(this.lastEvent).toISOString();atomicJson(this.file,this.record,this.secretValues);}
 event(type,detail={}){
  this.lastEvent=Date.now();fs.appendFileSync(path.join(this.directory,'events.jsonl'),redact({at:new Date().toISOString(),type,...detail},this.secretValues)+'\n',{mode:0o600});this.save();
 }
 async start(){
  await this.enterSetup();
  try{
  if(this.cfg.engine!=='claude'){
   this.record.WindowsSandbox??=this.cfg.windowsSandbox||'elevated';
   if(!['elevated','unelevated'].includes(this.record.WindowsSandbox))throw new Error('Invalid Windows sandbox profile');
   // Override is scoped to this owned backend; sandbox/approvals stay intact.
   const args=[...this.cfg.args];for(let i=args.length-2;i>=0;i--)if(args[i]==='-c'&&/^windows\.sandbox=/.test(args[i+1]))args.splice(i,2);
   const index=args.indexOf('app-server');args.splice(index<0?args.length:index,0,'-c','windows.sandbox="'+this.record.WindowsSandbox+'"');this.cfg.args=args;
  }
  if(this.cfg.share){this.shared=await startShared({...this.cfg,cwd:this.record.Project});this.rememberSecret(this.shared.token);this.rpc=this.shared.rpc;this.record.RemoteEndpoint=this.shared.url;}
  else if(this.cfg.engine==='claude')this.rpc=new ClaudeRpc({...this.cfg,cwd:this.record.Project,sessionId:this.record.SessionId});
  else this.rpc=new AppServerRpc({command:this.cfg.command,args:this.cfg.args,cwd:this.record.Project,timeout:this.cfg.timeout||15000});
  this.rpc.on('notification',m=>this.notification(m));
  this.rpc.on('request',m=>this.approval(m));
  this.rpc.on('closed',()=>{if(this.restarting)return;if(this.active){clearTimeout(this.active.timer);this.active.reject(new Error('App-server exited'));this.active=null;}if(!this.stopping){this.record.Status='disconnected';this.event('disconnected');}});
  await this.rpc.initialize();
  if(this.cfg.engine==='claude'&&this.rpc.model)this.record.RoleModel=this.rpc.model;
  const result=await this.rpc.call(this.record.SessionId?'thread/resume':'thread/start',{
   ...(this.record.SessionId?{threadId:this.record.SessionId}:{}),cwd:this.record.Project,sandbox:this.record.Sandbox||'workspace-write',approvalPolicy:'on-request',
   ...(this.record.RoleModel?{model:this.record.RoleModel}:{})
  });
  if(!result.thread?.id)throw new Error('App-server omitted thread id');
  this.record.SessionId=result.thread.id;this.record.Status='ready';this.ledger.add('ready','ready',this.record.Turn);this.event('ready');return this.record;
  }catch(error){this.leaveSetup('startup-failed');throw error;}
 }
 approval(message){
  const policy=this.record.Sandbox==='read-only'?{decision:'pending',reason:'read-only-role'}:approvalPolicy(message,this.record.WriteScopes||[],this.record.Project);
  if(policy.decision==='accept'){this.rpc.respond(message.id,{decision:'accept'});this.record.ApprovalDecisions=[...(this.record.ApprovalDecisions||[]),{id:message.id,decision:'accept',reason:policy.reason,at:new Date().toISOString()}].slice(-500);this.event('approval-decision',{requestId:message.id,decision:'accept',source:policy.reason});return;}
  this.approvals.set(message.id,message);this.record.PendingApprovals=[...this.approvals.values()].map(a=>({id:a.id,method:a.method,command:redact(a.params?.command||'',this.secretValues),cwd:a.params?.cwd||''}));this.event('approval-pending',{requestId:message.id,method:message.method});
 }
 notification(message){
  const p=message.params||{};
  if(p.threadId&&p.threadId!==this.record.SessionId)return;
  if(['item/started','item/completed','item.started','item.completed'].includes(message.method)&&['commandExecution','command_execution','agentMessage','agent_message'].includes(p.item?.type))this.leaveSetup('first-command-or-agent');
  const isItem=['item/completed','item.completed'].includes(message.method),exitCode=p.item?.exitCode??p.item?.exit_code;
  const toolFailed=isItem&&(p.item?.status==='failed'||(exitCode!=null&&exitCode!==0));
  const diagnostic=/error|warn/i.test(message.method)||toolFailed?redact(JSON.stringify(p),this.secretValues).slice(-8192):'';
  this.event(message.method,{turnId:p.turnId||p.turn?.id||'',...(diagnostic?{message:diagnostic}:{})});
  if(diagnostic){this.record.Error=(this.record.Error+'\n'+diagnostic).trim().slice(-16384);if(this.active&&/setup refresh had errors/i.test(diagnostic))this.active.setupFailure=true;this.save();}
  if(/error|warn/i.test(message.method)&&modelNotFound(p))this.attemptModelMissing=true;
  this.supervisor.reset();
  if(message.method==='thread/modelUpdated'&&typeof p.model==='string'){this.record.RoleModel=p.model;this.save();}
  if(message.method==='turn/started'&&this.active){this.active.id=p.turn.id;this.record.ActiveTurn=p.turn.id;this.save();}
  if(isItem&&['agentMessage','agent_message'].includes(p.item?.type)&&this.active)this.active.answer=p.item.text||'';
  if(isItem&&this.active){
   const item=p.item||{};
   if(['commandExecution','command_execution'].includes(item.type)&&toolFailed&&/setup refresh had errors/i.test(item.aggregatedOutput??item.aggregated_output??'')){this.active.setupFailure=true;this.active.setupToolFailure=true;}
   if(item.type==='mcpToolCall'&&item.status==='failed'&&/setup refresh had errors/.test(JSON.stringify(item.error||{})))this.active.setupFailure=true;
   if((['commandExecution','command_execution'].includes(item.type)&&exitCode===0)||['fileChange','file_change'].includes(item.type)){this.active.successfulItems++;this.attemptEffects=this.active.successfulItems;}
  }
  if(message.method==='thread/tokenUsage/updated'){
   const totals=p.tokenUsage?.total||{};this.record.UsageByThread??={};const previous=this.record.UsageByThread[this.record.SessionId]||{};this.record.Usage??={};
   for(const key of ['inputTokens','outputTokens','cachedInputTokens']){const value=Math.max(0,Number(totals[key])||0);this.record.Usage[key]=(this.record.Usage[key]||0)+Math.max(0,value-(previous[key]||0));}
   this.record.UsageByThread[this.record.SessionId]=totals;this.record.FixedLoad??=Number(totals.inputTokens||0);
   this.record.Budget=budgetState(this.record.Usage,this.cfg.tokenBudget||2000000,this.record.RoleModel||'',this.prices);this.record.BudgetBlocked=this.record.Budget.blocked;this.save();
  }
  if(message.method==='turn/completed'&&this.active){
   if(this.active.id&&p.turn.id!==this.active.id)return;
   clearTimeout(this.active.timer);
   const active=this.active;this.active=null;this.record.ActiveTurn='';this.record.Answer=redact(active.answer||'',this.secretValues);
   try{if(this.record.Answer.trim().startsWith('{'))this.record.Answer=toHandoff(JSON.parse(this.record.Answer));}catch{this.record.Answer='';}
   this.record.HandoffValid=validHandoff(this.record.Answer);this.record.HandoffCheck='local-six-fields';
   if(this.record.HandoffValid&&this.cfg.checker){
    const handoffFile=path.join(this.directory,'handoff.md');fs.writeFileSync(handoffFile,this.record.Answer,{mode:0o600});
    const check=spawnSync(process.execPath,[this.cfg.checker,'handoff-check','--handoff-file',handoffFile,'--json'],{encoding:'utf8',timeout:15000,maxBuffer:1048576,windowsHide:true,shell:false});
    let ok=false;try{ok=check.status===0&&JSON.parse(check.stdout).ok===true;}catch{}this.record.HandoffValid=ok;this.record.HandoffCheck=ok?'AgentChef handoff-check':'AgentChef handoff-check failed';
   }
   this.record.Status=p.turn.status==='completed'?(this.record.HandoffValid?'completed':'invalid-handoff'):p.turn.status;
   if(active.setupToolFailure)this.record.Status='failed';
   if(p.turn.error){if(modelNotFound(p.turn.error))this.attemptModelMissing=true;const message=redact(JSON.stringify(p.turn.error),this.secretValues).slice(-8192);this.record.Error=(this.record.Error+'\n'+message).trim().slice(-16384);if(/setup refresh had errors/i.test(message))active.setupFailure=true;this.event('turn-error',{message});}
   if(this.record.Status!=='completed'){
    const tail=redact(this.rpc.stderrTail||'',this.secretValues).slice(-8192);this.record.StderrTail=tail;
    if(/setup refresh had errors/i.test(tail))active.setupFailure=true;
    this.record.Error=(this.record.Error+'\n'+tail).trim().slice(-16384)||'Turn failed without an agent handoff';
   }
   const limit=detectLimit(p.turn.error);if(limit){this.limitQueue.plan(this.record.SessionId,this.record.Turn,limit.dueAt);this.record.LimitQueue=this.limitQueue.value;this.record.Status='limit-waiting';}
   this.record.Delivery={Status:active.answer?'islendi':'alindi-cevapsiz',PromptHash:this.record.PromptHash};
   this.record.Summary=this.record.Answer.replace(/\s+/g,' ').slice(0,240);this.record.Finished=new Date().toISOString();this.idleSince=Date.now();
   const eventKey='turn-'+this.record.Turn+'-attempt-'+this.record.Attempts+'-'+this.record.Status;
   if(this.ledger.add(eventKey,this.record.Status,this.record.Turn)&&!(active.setupFailure&&!active.successfulItems&&this.record.Attempts===1))this.notify(this.record.Status);
   this.save();active.resolve({...this.record,setupFailure:active.setupFailure,successfulItems:active.successfulItems});
  }
 }
 async runTurn(text,taskKey){if(this.turnBusy||this.stopping)throw new Error('Worker unavailable for another turn');this.turnBusy=true;try{return await this.performTurn(text,taskKey);}finally{this.leaveSetup('turn-ended');this.turnBusy=false;}}
 async performTurn(text,taskKey){
  if(this.active)throw new Error('Worker has an active turn');
  if(!text?.trim())throw new Error('Prompt is empty');
  if(!this.record.ExplicitWriteScopes)this.record.WriteScopes=briefWriteScopes(text);
  this.record.Budget=budgetState(this.record.Usage,this.cfg.tokenBudget||2000000,this.record.RoleModel||'',this.prices);
  this.record.BudgetBlocked=this.record.Budget.blocked;
  if(this.record.Budget.blocked){this.record.BudgetBlocked=true;this.record.Error='Worker token budget exhausted';this.save();this.notify('budget-blocked');throw new Error('Worker token budget exhausted');}
  if(this.cfg.engine!=='claude'){
   try{
    const limits=await this.rpc.call('account/rateLimits/read',{});const primary=limits.rateLimits?.primary;this.record.RateLimits=primary?{usedPercent:primary.usedPercent,resetsAt:primary.resetsAt}:null;
    if(primary?.usedPercent>=100){const due=detectLimit({code:'usage_limit_reached',resetsAt:primary.resetsAt}).dueAt;if(this.autoResuming&&this.limitQueue.value)this.limitQueue.failed(Date.now());else{this.limitQueue.plan(this.record.SessionId,this.record.Turn,due);this.limitQueue.value.pendingPrompt=redact(text,this.secretValues);this.limitQueue.value.taskKey=taskKey;}this.record.LimitQueue=this.limitQueue.value;this.record.Status='limit-waiting';this.save();this.notify('limit-waiting');return {...this.record};}
   }catch{this.record.RateLimits=null;this.record.RateLimitStatus='unavailable';}
  }
  const age=this.record.Finished?(Date.now()-Date.parse(this.record.Finished))/60000:0;
  const reason=taskKey&&this.record.TaskKey&&taskKey!==this.record.TaskKey?'task-changed':age>=60?'age':this.record.Usage?.inputTokens>200000?'context':this.record.Turn>300?'requests':'same-task-recent';
  this.record.Continuation={Decision:reason==='same-task-recent'?'resume':'fresh',Reason:reason};
  if(reason!=='same-task-recent'){
   text='### Previous owned session handoff\n'+(this.record.Summary||'none')+'\n\n'+text;
   const previous=this.record.SessionId;
   const response=await this.rpc.call('thread/start',{cwd:this.record.Project,sandbox:this.record.Sandbox||'workspace-write',approvalPolicy:'on-request',...(this.record.RoleModel?{model:this.record.RoleModel}:{})});
   this.record.SessionId=response.thread.id;this.record.PreviousSessions=[...(this.record.PreviousSessions||[]),previous];
  }
  if(taskKey)this.record.TaskKey=taskKey;
  this.record.Turn=(this.record.Turn||0)+1;this.record.RetryCount=0;this.record.Attempts=0;
  this.supervisor.reset();this.ledger.add('turn-'+this.record.Turn+'-start','running',this.record.Turn);
  this.record.PromptHash=createHash('sha256').update(text.replace(/\r\n/g,'\n').trimEnd()).digest('hex');
  let modelRetried=false,setupRetries=0;
  for(let attempt=0;attempt<4;attempt++){
   await this.enterSetup();
   this.record.Attempts++;this.attemptEffects=0;this.attemptModelMissing=false;this.record.Status='running';this.record.Answer='';this.record.Error='';this.record.StderrTail='';this.rpc.stderrTail='';this.record.Started=new Date().toISOString();this.record.Delivery={Status:'alindi-cevapsiz',PromptHash:this.record.PromptHash};this.save();
   const finished=new Promise((resolve,reject)=>{this.active={resolve,reject,answer:'',id:null,setupFailure:false,successfulItems:0};this.active.timer=setTimeout(()=>{const active=this.active;this.active=null;this.record.Error='Worker turn timeout';this.save();active?.reject(new Error('Worker turn timeout'));void this.close('failed');},this.cfg.turnTimeout||45*60000);});
   finished.catch(()=>{});
   try{await this.rpc.call('turn/start',{threadId:this.record.SessionId,input:[{type:'text',text}],outputSchema:handoffSchema,...(this.record.RoleModel?{model:this.record.RoleModel}:{})});}catch(e){const a=this.active;this.active=null;clearTimeout(a?.timer);a?.reject(e);}
   let result;try{result=await finished;}catch(e){
    if(this.cfg.engine==='claude')throw e;
    const tail=redact(this.rpc.stderrTail||'',this.secretValues).slice(-8192);this.record.Status='failed';this.record.StderrTail=tail;this.record.Error=(this.record.Error+'\n'+redact(e.message,this.secretValues)+'\n'+tail).trim().slice(-16384);this.save();
    result={...this.record,setupFailure:/setup refresh had errors/i.test(this.record.Error),successfulItems:this.attemptEffects||0};
   }
   this.leaveSetup('attempt-ended');
   if(result.Status!=='completed'){
    await new Promise(resolve=>setTimeout(resolve,20));
    const tail=redact(this.rpc.stderrTail||'',this.secretValues).slice(-8192);this.record.StderrTail=tail;
    if(tail){this.record.Error=(this.record.Error+'\n'+tail).trim().slice(-16384);result.Error=this.record.Error;result.StderrTail=tail;}
    if(/setup refresh had errors/i.test(tail))result.setupFailure=true;this.save();
   }
   // Only diagnostics from error/tool events enter Error, never agent prose.
   if(result.Status==='completed'||result.successfulItems||this.cfg.engine==='claude')return result;
   const modelMissing=this.attemptModelMissing;
   if(modelMissing&&!modelRetried){
    const from=this.record.RoleModel||'unknown';
    const to=[this.record.CatalogModel,this.record.ReviewModel].find(m=>typeof m==='string'&&/^[A-Za-z0-9._:-]+$/.test(m)&&m!==from);
    if(!to){this.record.Error+='\nmodel_not_found: no distinct catalog model or review_model is configured';this.save();return {...result,Error:this.record.Error};}
    modelRetried=true;this.record.ModelFallback={from,to,reason:'model_not_found'};this.record.RoleModel=to;
    this.record.RetryCount++;this.record.RetryEvents=[...(this.record.RetryEvents||[]),{Turn:this.record.Turn,Reason:'model_not_found',DelaySeconds:0}];this.event('model-fallback',this.record.ModelFallback);continue;
   }
   if(!result.setupFailure||setupRetries>=2)return result;
   setupRetries++;const delay=10+Math.floor((this.cfg.random||Math.random)()*31);
   this.record.RetryCount++;this.record.RetryEvents=[...(this.record.RetryEvents||[]),{Turn:this.record.Turn,At:new Date().toISOString(),Reason:'sandbox-tool-failure',DelaySeconds:delay,Sandbox:this.record.WindowsSandbox,Attempt:this.record.Attempts+1}];this.event('retry-scheduled');
   await (this.cfg.sleep|| (ms=>new Promise(r=>setTimeout(r,ms))))(delay*1000);
   if(setupRetries===2&&this.record.WindowsSandbox!=='unelevated'){
    this.record.SandboxFallback={From:this.record.WindowsSandbox,To:'unelevated',Attempt:this.record.Attempts+1,Reason:'failed-setup-refresh',Turn:this.record.Turn,At:new Date().toISOString(),Error:this.record.Error,StderrTail:this.record.StderrTail};
    this.record.WindowsSandbox='unelevated';this.event('sandbox-fallback',this.record.SandboxFallback);
   }
   this.restarting=true;try{if(this.shared){await this.shared.close();this.shared=null;}else await this.rpc.close();await this.start();}finally{this.restarting=false;}
  }
 }
 async dispatch(request){
  if(request.owner!==this.cfg.owner)throw new Error('Channel owner mismatch');
  switch(request.method){
   case 'durum':return {...this.record};
   case 'sor':{const result=this.turnQueue.then(()=>this.runTurn(request.text,request.taskKey));this.turnQueue=result.catch(()=>{});return result;}
   case 'steer':if(!this.active?.id)throw new Error('No active turn');return this.rpc.call('turn/steer',{threadId:this.record.SessionId,expectedTurnId:this.active.id,input:[{type:'text',text:request.text}]});
   case 'interrupt':if(!this.active?.id)throw new Error('No active turn');return this.rpc.call('turn/interrupt',{threadId:this.record.SessionId,turnId:this.active.id});
   case 'onay':{
    const approvalId=[...this.approvals.keys()].find(id=>String(id)===String(request.requestId));
    if(!['accept','decline','cancel'].includes(request.decision)||approvalId===undefined)throw new Error('Invalid approval decision');
    this.rpc.respond(approvalId,{decision:request.decision});this.approvals.delete(approvalId);this.record.PendingApprovals=this.record.PendingApprovals.filter(a=>a.id!==approvalId);
    this.record.ApprovalDecisions=[...(this.record.ApprovalDecisions||[]),{id:request.requestId,decision:request.decision,reason:'owner',at:new Date().toISOString()}].slice(-500);
    this.event('approval-decision',{requestId:request.requestId,decision:request.decision,source:'owner'});return {decided:true};
   }
   case 'limitler':return this.rpc.call('account/rateLimits/read',{});
   case 'tetikle':await this.resumeDue();return {...this.record};
   case 'tui':if(!this.shared)throw new Error('Open a shared channel first');return launchTui(this.cfg,this.shared,this.record.SessionId);
   case 'kapat':await this.close();return {closed:true};
   default:throw new Error('Unknown channel operation');
  }
 }
 async pump(){
  const directory=path.join(this.directory,'commands');
  for(const name of fs.readdirSync(directory).filter(n=>/^[a-f0-9-]{36}\.json$/.test(n))){
   const file=path.join(directory,name),working=file+'.working';try{fs.renameSync(file,working);}catch{continue;}
   let request;try{if(fs.statSync(working).size>1048576)throw new Error('Request too large');request=JSON.parse(fs.readFileSync(working,'utf8'));}catch{fs.unlinkSync(working);continue;}
   const response=path.join(this.directory,'responses',name);
   this.dispatch(request).then(result=>atomicJson(response,{ok:true,result},this.secretValues)).catch(()=>atomicJson(response,{ok:false,error:'Channel request failed; read worker status'},this.secretValues)).finally(()=>{
    // Unique completion marker avoids compare/unlink races with the next owner.
    if(/^[a-f0-9]{64}$/.test(request.taskKey||'')&&/^[a-f0-9-]{36}$/.test(request.claimRequest||'')){fs.writeFileSync(path.join(this.directory,'claim-done-'+request.claimRequest),'done',{mode:0o600});}
    try{fs.unlinkSync(working);}catch{}
   });
  }
 }
 notify(status){
  if(!this.cfg.handoffDirectory)return;
  // Same local handoff JSON format; never touch the curated/derived Markdown views.
  const key=this.record.Id+'-'+this.record.Turn+'-'+status,marker=path.join(this.directory,'notified-'+key);
  try{const fd=fs.openSync(marker,'wx');fs.closeSync(fd);}catch{return;}
  fs.mkdirSync(this.cfg.handoffDirectory,{recursive:true});const now=new Date();
  const id=now.toISOString().replace(/[-:]/g,'').slice(0,15)+'-'+randomUUID().replaceAll('-','').slice(0,4);
  atomicJson(path.join(this.cfg.handoffDirectory,id+'.json'),{v:2,id,ts:now.toISOString(),from:{agent:'codex',project:path.basename(this.record.Project)},to:'claude',kind:'bilgi',status:'acik',question:'Kanal '+this.record.Id+' '+status+'; beyin codex durum '+this.record.Id});
 }
 async supervise(now=Date.now()){
  const action=this.supervisor.tick(this.lastEvent,now,Boolean(this.active),Boolean(this.record.BudgetBlocked));
  if(action==='nudge'&&this.active?.id){this.ledger.add('turn-'+this.record.Turn+'-nudge','nudged',this.record.Turn);this.notify('nudged');await this.rpc.call('turn/steer',{threadId:this.record.SessionId,expectedTurnId:this.active.id,input:[{type:'text',text:'Report current progress or the exact blocker; preserve the original scope.'}]});}
  if(action==='stall'){
   this.ledger.add('turn-'+this.record.Turn+'-stalled','stalled',this.record.Turn);this.notify('stalled');
   const active=this.active;this.active=null;if(active){clearTimeout(active.timer);active.resolve({...this.record,Status:'stalled',setupFailure:false});}await this.close('stalled');
  }
  if(!this.active&&!this.turnBusy&&this.limitQueue.value?.status!=='planned'&&now-this.idleSince>=(this.cfg.idleMs||30*60000))await this.close('closed','idle');
 }
 async resumeDue(){
  if(this.autoResuming||this.active||this.turnBusy||this.record.BudgetBlocked)return;
  const action=this.limitQueue.due(Date.now(),this.record.Turn);if(action==='superseded'){this.record.LimitQueue=this.limitQueue.value;this.save();return;}if(action!=='resume')return;
  this.autoResuming=true;try{const r=await this.runTurn(this.limitQueue.value.pendingPrompt||'The usage limit reset. Continue the same task within its original scope and return the six-field handoff.',this.limitQueue.value.taskKey||this.record.TaskKey);if(r.Status==='completed'){this.limitQueue.value.status='verified';delete this.limitQueue.value.pendingPrompt;}else if(r.Status!=='limit-waiting')this.limitQueue.failed(Date.now());}catch{this.limitQueue.failed(Date.now());}finally{this.autoResuming=false;this.record.LimitQueue=this.limitQueue.value;this.save();}
 }
 async run(){await this.start();while(!this.stopping){await this.pump();await this.supervise();if(!this.stopping)await this.resumeDue();await new Promise(resolve=>setTimeout(resolve,50));}}
 async close(status='closed',reason='owner'){if(this.stopping)return;this.stopping=true;this.leaveSetup('closed');if(this.shared)await this.shared.close();else await this.rpc?.close();this.record.Status=status;this.record.CloseReason=reason;this.ledger.add('terminal-'+status,status,this.record.Turn);this.event(status);if(this.cfg.dietFile&&path.dirname(path.resolve(this.cfg.dietFile))===path.resolve(this.directory)){try{fs.unlinkSync(this.cfg.dietFile);}catch{}}}
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url)){
 const config=JSON.parse(fs.readFileSync(process.argv[2],'utf8').replace(/^\uFEFF/,''));
 const host=new ChannelHost(config);
 const shutdown=()=>host.close().finally(()=>process.exit(0));process.on('SIGTERM',shutdown);process.on('SIGINT',shutdown);
 host.run().catch(async error=>{host.record.Status='failed';host.record.StderrTail=redact(host.rpc?.stderrTail||'',host.secretValues).slice(-8192);host.record.Error=redact((host.record.Error||'')+'\n'+error.message+'\n'+host.record.StderrTail,host.secretValues).trim().slice(-16384);host.save();await host.close('failed');process.exitCode=1;});
}
