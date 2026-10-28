import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
const script=fileURLToPath(new URL('./channel-evidence.ps1',import.meta.url));
export function persistChannelEvidence({vault,engine,id}) {
 if(!vault||!['codex','claude'].includes(engine)||!/^CK-[a-f0-9]{32}$/.test(id))throw new Error('Invalid channel evidence identity');
 const result=spawnSync('powershell.exe',['-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',script,'-Vault',vault,'-Engine',engine,'-Id',id],
  {encoding:'utf8',timeout:15000,maxBuffer:65536,windowsHide:true,shell:false,env:{...process.env,BEYIN_CHILD:'1'}});
 if(result.status!==0)throw new Error('Channel evidence persistence failed');
}
