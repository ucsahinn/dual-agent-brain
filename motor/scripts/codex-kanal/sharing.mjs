import net from 'node:net';import {spawn} from 'node:child_process';import {randomBytes,createHash} from 'node:crypto';
import {AppServerRpc} from './protocol.mjs';import {WebSocketTransport,tuiPlan} from './websocket.mjs';
const pause=ms=>new Promise(r=>setTimeout(r,ms));
async function freePort(){const probe=net.createServer();await new Promise((resolve,reject)=>{probe.once('error',reject);probe.listen(0,'127.0.0.1',resolve);});const port=probe.address().port;await new Promise(r=>probe.close(r));return port;}
export async function verifyWindowsPeer(port,clientPort,rootPid){
 if(process.platform!=='win32'||![port,clientPort,rootPid].every(n=>Number.isInteger(n)&&n>0))return false;
 const script=`$ErrorActionPreference='Stop'; $rows=@(Get-NetTCPConnection -State Established -LocalAddress 127.0.0.1 -LocalPort ${port} -RemotePort ${clientPort}); $ok=$false; foreach($row in $rows){$current=[int]$row.OwningProcess; for($i=0;$i -lt 32 -and $current -gt 0;$i++){if($current -eq ${rootPid}){$ok=$true;break}; $p=Get-CimInstance Win32_Process -Filter ('ProcessId='+$current); if(-not $p){break};$current=[int]$p.ParentProcessId}}; if($ok){'owned'}else{'foreign'}`;
 return new Promise(resolve=>{
  const probe=spawn('powershell.exe',['-NoProfile','-NonInteractive','-EncodedCommand',Buffer.from(script,'utf16le').toString('base64')],{windowsHide:true,shell:false,stdio:['ignore','pipe','ignore']});let output='',done=false;
  const finish=value=>{if(done)return;done=true;clearTimeout(timer);resolve(value);};const timer=setTimeout(()=>{probe.kill();finish(false);},5000);
  probe.stdout.on('data',b=>{if(output.length<100)output+=b.toString();});probe.on('error',()=>finish(false));probe.on('exit',code=>finish(code===0&&output.trim()==='owned'));
 });
}
export async function startShared(config){
 const url='ws://127.0.0.1:'+await freePort(),token=
  randomBytes(32).toString('base64url'),hash=createHash('sha256').update(token).digest('hex');
 const args=[...config.args];const index=args.indexOf('--listen');if(index>=0)args.splice(index,2);
 args.push('--listen',url,'--ws-auth','capability-token','--ws-token-sha256',hash);
 const server=spawn(config.command,args,{cwd:config.cwd,env:process.env,windowsHide:true,shell:false,stdio:['ignore','ignore','pipe']});let stderrTail='';server.stderr.on('data',chunk=>{stderrTail=(stderrTail+chunk.toString('utf8')).slice(-16384);});
 let spawnFailed=false;server.on('error',()=>{spawnFailed=true;});let transport;
 try{
  const deadline=Date.now()+(config.startupMs||15000);
  while(Date.now()<deadline){
   if(spawnFailed||server.exitCode!==null)throw new Error('Shared app-server exited during startup');
   try{transport=await WebSocketTransport.connect(url,token,clientPort=>{
    if(server.exitCode!==null||!server.pid)return false;
    return config.verifyPeer?config.verifyPeer(clientPort):verifyWindowsPeer(Number(new URL(url).port),clientPort,server.pid);
   });break;}catch{await pause(50);}
  }
  if(!transport)throw new Error('Shared app-server startup timeout');
  const rpc=new AppServerRpc({transport,timeout:config.timeout||15000});Object.defineProperty(rpc,'stderrTail',{get:()=>stderrTail,set:value=>{stderrTail=value;}});
  return {url,token,args,rpc,server,async close(){await rpc.close();if(server.exitCode===null)server.kill();await new Promise(r=>{if(server.exitCode!==null)return r();const timer=setTimeout(r,1000);server.once('exit',()=>{clearTimeout(timer);r();});});}};
 }catch(e){server.kill();throw e;}
}
const literal=text=>"'"+String(text).replaceAll("'","''")+"'";
export async function launchTui(config,backend,threadId){
 if(process.platform!=='win32')throw new Error('Visible TUI launcher currently requires Windows');
 const base=config.args.slice(0,config.args.indexOf('app-server'));
 const plan=tuiPlan({threadId,url:backend.url,token:
  backend.token,command:config.command,args:base});
 const client='& '+[plan.command,...plan.args].map(literal).join(' ')+'; exit $LASTEXITCODE';
 const encoded=Buffer.from(client,'utf16le').toString('base64');
 const launcher="Start-Process -FilePath powershell.exe -WindowStyle Normal -ArgumentList @('-NoProfile','-EncodedCommand',"+literal(encoded)+')';
 const child=spawn('powershell.exe',['-NoProfile','-NonInteractive','-EncodedCommand',Buffer.from(launcher,'utf16le').toString('base64')],{env:{...process.env,...plan.env},windowsHide:true,shell:false,stdio:'ignore'});
 await new Promise((resolve,reject)=>{const timer=setTimeout(()=>{child.kill();reject(new Error('TUI launcher timeout'));},10000);child.once('error',()=>{clearTimeout(timer);reject(new Error('TUI launcher failed'));});child.once('exit',code=>{clearTimeout(timer);code===0?resolve():reject(new Error('TUI launcher rejected'));});});
 return {opened:true,threadId};
}
