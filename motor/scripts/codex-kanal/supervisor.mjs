import fs from 'node:fs';import {randomUUID} from 'node:crypto';
export class Supervisor {
 constructor({nudgeMs=20*60000,stallMs=40*60000}={}){if(nudgeMs<=0||stallMs<=nudgeMs)throw new Error('Invalid silence thresholds');this.nudgeMs=nudgeMs;this.stallMs=stallMs;this.nudged=false;this.stalled=false;}
 reset(){this.nudged=false;this.stalled=false;}
 tick(lastEvent,now,active,budgetBlocked){
  if(!active||this.stalled)return 'none';const silent=now-lastEvent;
  if(silent>=this.stallMs){this.stalled=true;return 'stall';}
  if(!budgetBlocked&&!this.nudged&&silent>=this.nudgeMs){this.nudged=true;return 'nudge';}return 'none';
 }
}
export class Ledger {
 constructor(file){this.file=file;this.events=[];this.recovered=false;for(const candidate of [file,file+'.bak']){try{const value=JSON.parse(fs.readFileSync(candidate,'utf8'));if(!Array.isArray(value.events))continue;this.events=value.events;this.recovered=candidate!==file;break;}catch{if(candidate===file&&fs.existsSync(file))this.recovered=true;}}this.keys=new Set(this.events.map(e=>e.key));}
 add(key,state,turn=0){
  if(!/^[a-zA-Z0-9_./:-]{1,160}$/.test(key)||!['queued','ready','running','nudged','stalled','completed','failed','invalid-handoff','interrupted','closed','disconnected','limit-waiting'].includes(state))throw new Error('Invalid ledger event');
  if(this.keys.has(key))return false;
  this.events.push({key,state,turn,at:new Date().toISOString()});this.keys.add(key);
  if(this.events.length>2000){this.events=this.events.slice(-2000);this.keys=new Set(this.events.map(e=>e.key));}
  const tmp=this.file+'.'+randomUUID()+'.tmp';fs.writeFileSync(tmp,JSON.stringify({events:this.events}),{mode:0o600});
  if(fs.existsSync(this.file)){try{JSON.parse(fs.readFileSync(this.file,'utf8'));fs.copyFileSync(this.file,this.file+'.bak');}catch{}}
  fs.renameSync(tmp,this.file);return true;
 }
}
