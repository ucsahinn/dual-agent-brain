import fs from 'node:fs';import path from 'node:path';
const fields=['Goal','Evidence','Write scope','Boundaries','Done when','Return format',"User's words"];
const names=['outcome','evidence','changed_scope','risks','open_questions','next_verification'];
const labels=['Outcome','Evidence','Changed scope','Risks','Open questions','Next verification'];
export const handoffSchema={type:'object',properties:Object.fromEntries(names.map(n=>[n,{type:'string',minLength:1}])),required:names,additionalProperties:false};
export function toHandoff(object){if(!object||typeof object!=='object'||Array.isArray(object)||Object.keys(object).length!==6||names.some(n=>typeof object[n]!=='string'||!object[n].trim()))throw new Error('Invalid six-field handoff JSON');return names.map((n,i)=>labels[i]+': '+object[n]).join('\n');}
export function compileBrief(input,maxChars=12000,role='',memories=[]){
 if(fields.some(f=>typeof input[f]!=='string'||!input[f].trim()))throw new Error('Seven nonempty brief fields required');
 const mandatory=fields.map(f=>f+':\n'+input[f]).join('\n\n');
 if(mandatory.length>maxChars)throw new Error('Mandatory brief exceeds character budget');
 const roleParts=role.split('<!-- optional -->'),requiredRole=roleParts.shift()||'';
 if(mandatory.length+requiredRole.length+2>maxChars)throw new Error('Mandatory role and brief exceed character budget');
 let text=requiredRole+(requiredRole?'\n\n':'')+mandatory;
 for(const optional of roleParts)if(text.length+optional.length+2<=maxChars)text+='\n\n'+optional;
 const injected=[];for(const memory of memories.slice(0,5)){const block='\n\n### Approved reference: '+memory.path+'\n'+memory.text;if(text.length+block.length>maxChars)continue;text+=block;injected.push(memory.path);}
 return {text,characters:text.length,estimatedTokens:
  Math.ceil(text.length/4),injected};
}
const inside=(file,scope)=>file===scope||file.startsWith(scope+path.sep);
export function briefWriteScopes(text){
 const matches=[...text.matchAll(/^Write scope:[ \t]*\r?\n([\s\S]*?)^Boundaries:/gm)];
 if(matches.length!==1)return [];
 return matches[0][1].split(/\r?\n/).map(s=>s.trim().replace(/^[-*]\s+/,'' )).filter(Boolean).flatMap(s=>{
  const value=s.startsWith('`')&&s.endsWith('`')?s.slice(1,-1):s;
  // Only literal paths, never prose, wildcards, parent traversal or switches.
  return /^(?:\.\/)?[A-Za-z0-9_./\\-]+$/.test(value)&&!value.startsWith('-')&&!value.split(/[\\/]/).includes('..')&&(value.includes('/')||value.includes('\\')||/\.[a-z0-9]+$/i.test(value))?[value]:[];
 });
}
function unsafePath(file,project){
 const relative=path.relative(project,path.resolve(project,file));
 if(relative.split(/[\\/]/).some(s=>/^(?:\.git|\.env(?:\..*)?|auth\.json|credentials?(?:\..*)?|id_rsa|id_ed25519)$/i.test(s)))return true;
 let current=path.resolve(project);for(const part of relative.split(path.sep)){current=path.join(current,part);if(fs.existsSync(current)&&fs.lstatSync(current).isSymbolicLink())return true;}return false;
}
function canonical(file){let current=path.resolve(file),suffix=[];while(!fs.existsSync(current)){const parent=path.dirname(current);if(parent===current)throw new Error('No existing ancestor');suffix.unshift(path.basename(current));current=parent;}return path.join(fs.realpathSync(current),...suffix);}
export function approvalPolicy(request,scopes=[],project){
 let changes=request.params?.fileChanges;
 if(request.method==='claude/toolApproval'&&['Write','Edit'].includes(request.params?.toolName))changes=[{path:request.params.input?.file_path,kind:'update'}];
 if((request.method!=='item/fileChange/requestApproval'&&request.method!=='claude/toolApproval')||!Array.isArray(changes)||!changes.length||request.params?.grantRoot)return {decision:'pending',reason:'owner-required'};
 try{
  const root=canonical(project),allowed=scopes.map(s=>({file:canonical(path.resolve(project,s)),directory:s.endsWith('/')||s.endsWith('\\')||(fs.existsSync(path.resolve(project,s))&&fs.statSync(path.resolve(project,s)).isDirectory())}));
  for(const change of changes){if(!['add','update','create','edit'].includes(change.kind)||typeof change.path!=='string')return {decision:'pending',reason:'irreversible-or-unknown'};if(unsafePath(change.path,project))return {decision:'pending',reason:'sensitive-or-linked-path'};const target=canonical(path.resolve(project,change.path));if(!inside(target,root)||!allowed.some(s=>s.directory?inside(target,s.file):target===s.file))return {decision:'pending',reason:'outside-scope'};}
  return {decision:'accept',reason:'scoped-file-change'};
 }catch{return {decision:'pending',reason:'path-unverified'};}
}
export function fanout(groups,capacity,dependent=false){
 const cap=Math.max(0,Math.min(8,Math.floor(Number(capacity)||0)));if(!cap)return {workers:0,route:'queue',reason:'capacity'};
 const normalize=s=>s.replaceAll('\\','/').replace(/\/$/,'').toLowerCase();
 let overlap=false;for(let a=0;a<groups.length;a++)for(let b=a+1;b<groups.length;b++)for(const x of groups[a])for(const y of groups[b]){const l=normalize(x),r=normalize(y);if(l===r||l.startsWith(r+'/')||r.startsWith(l+'/'))overlap=true;}
 const workers=dependent||overlap?1:Math.min(groups.length||1,cap);return {workers,route:workers===1?'single':workers>2?'team':'parallel',reason:dependent?'dependencies':overlap?'overlap':'independent-groups'};
}
export function budgetState(usage={},limit=2000000,model='',prices={}){
 const nonnegative=value=>Math.max(0,Number.isFinite(Number(value))?Number(value):0);
 const input=nonnegative(usage.inputTokens??usage.input_tokens),output=nonnegative(usage.outputTokens??usage.output_tokens),cache=Math.min(input,nonnegative(usage.cachedInputTokens??usage.cached_input_tokens??usage.cache_read_input_tokens));
 const price=(prices.modeller||[]).filter(p=>model.startsWith(p.onek)).sort((a,b)=>b.onek.length-a.onek.length)[0];
 const cost=price?(Math.max(0,input-cache)*price.girdi+cache*price.okuma+output*price.cikti)/1e6:null;
 const effectiveTokens=
  Math.round(((input-cache)+output+cache*0.1)*10)/10;
 return {tokens:
  input+output,effectiveTokens,limit,formula:'(input-cached)+output+cached*0.1',cacheWeight:0.1,cost,apiEquivalent:true,blocked:effectiveTokens>=limit,reason:effectiveTokens>=limit?'token-budget':'within-budget'};
}
export function detectLimit(error,now=Date.now()){
 if(!error||!['rate_limit_exceeded','usage_limit_reached'].includes(error.code))return null;
 const dueAt=Number.isFinite(Number(error.resetsAt))&&Number(error.resetsAt)>0?Number(error.resetsAt)*1000:now+5*3600000;
 return {dueAt:Math.max(now,dueAt)};
}
export class LimitQueue {
 constructor(value=null){this.value=value;}
 plan(sessionId,lastTurn,dueAt){this.value={sessionId,lastTurn,dueAt,attempts:0,status:'planned'};return this.value;}
 due(now,turn){if(!this.value||this.value.status!=='planned')return 'none';if(turn>this.value.lastTurn){this.value.status='superseded';return 'superseded';}return now>=this.value.dueAt?'resume':'wait';}
 failed(now){const delays=[15,60,180];this.value.attempts++;if(this.value.attempts>3)this.value.status='abandoned';else{this.value.status='planned';this.value.dueAt=now+delays[this.value.attempts-1]*60000;}return this.value;}
}
