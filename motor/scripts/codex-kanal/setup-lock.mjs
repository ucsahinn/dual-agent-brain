import {spawn} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import path from 'node:path';
export async function acquireSetupLock({name='Local\\Beyin-codex-setup',waitMs=60000,holdMs=60000}={}){
 const ps=path.join(process.env.SystemRoot||'C:\\Windows','System32/WindowsPowerShell/v1.0/powershell.exe');
 const child=spawn(ps,['-NoProfile','-NonInteractive','-File',fileURLToPath(new URL('./setup-lock.ps1',import.meta.url)),'-Serve','-Name',name,'-WaitMs',String(waitMs),'-HoldMs',String(holdMs)],{stdio:['pipe','pipe','ignore'],windowsHide:true});
 let released=false;
 const release=()=>{if(released)return;released=true;child.stdin.end('\n');};
 child.stdin.on('error',()=>{});
 await new Promise((resolve,reject)=>{
  let output='';const timer=setTimeout(()=>{release();reject(new Error('Codex setup admission lock timed out'));},waitMs+5000);
  const fail=()=>{clearTimeout(timer);reject(new Error('Codex setup admission lock unavailable'));};
  child.once('error',fail);child.once('exit',fail);
  child.stdout.on('data',chunk=>{output+=chunk.toString();if(output.includes('ready')){clearTimeout(timer);resolve();}});
 });
 return {release};
}
