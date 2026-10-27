$repo=Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
. (Join-Path $repo 'motor/hooks/lib.ps1');. (Join-Path $PSScriptRoot 'core.ps1')
Describe 'Exec recovery after a failed setup turn' {
 It 'resumes the owned thread after three setup failures without replaying a valid live response' {
  Mock Get-KanalCapacity { @{onerilen=8} };Mock Get-KanalTeamCount {0};Mock Start-Sleep {}
  Mock Get-KanalDelivery { @{Status='yutuldu'} }
  $fixture=Join-Path $TestDrive 'recovery.js';$counter=(Join-Path $TestDrive 'counter').Replace('\','/')
  $source=@'
const fs=require('fs'),args=process.argv.slice(2),sid='11111111-1111-4111-8111-111111111111';
if(args.includes('--version')){console.log('codex-cli 0.162.1');process.exit(0);}
const input=fs.readFileSync(0,'utf8'),file='COUNTER',n=fs.existsSync(file)?Number(fs.readFileSync(file,'utf8')):0;fs.writeFileSync(file,String(n+1));
console.log(JSON.stringify({type:'thread.started',thread_id:sid}));
if(n<3){console.log(JSON.stringify({type:'item.completed',item:{type:'command_execution',exit_code:-1,aggregated_output:'setup refresh had errors'}}));process.exit(1);}
if(!args.includes('resume')||!args.includes(sid)||!input.includes('second'))process.exit(39);
console.log(JSON.stringify({type:'item.completed',item:{type:'agent_message',text:'Outcome: recovered\nEvidence: owned resume\nChanged scope: none\nRisks: none\nOpen questions: none\nNext verification: none'}}));console.log(JSON.stringify({type:'turn.completed'}));
'@
  [IO.File]::WriteAllText($fixture,$source.Replace('COUNTER',$counter),(New-Object Text.UTF8Encoding $false))
  $shim=Join-Path $TestDrive 'codex.cmd';[IO.File]::WriteAllText($shim,"@echo off`r`nnode.exe `"%~dp0recovery.js`" %*`r`n")
  $ctx=New-KanalContext $repo;$ctx.Codex=$shim;$ctx.VersionTimeoutMs=15000;$ctx.State=Join-Path $TestDrive 'state';$ctx.ConfigPath=Join-Path $TestDrive 'config.toml';'[mcp_servers.node_repl]'|Set-Content $ctx.ConfigPath
  $first=Submit-KanalTurn $ctx -Proje $TestDrive -Metin 'first';$first.Status|Should Be 'failed';$first.Attempts|Should Be 3
  $second=Submit-KanalTurn $ctx -Id $first.Id -Metin 'second';$second.Status|Should Be 'completed';$second.Attempts|Should Be 1;$second.SessionId|Should Be $first.SessionId
  $second.Delivery.Source|Should Be 'validated-live-turn';$second.Delivery.RolloutStatus|Should Be 'yutuldu';$second.Error|Should Not Match 'setup refresh'
  $second.SetupLock.ReleaseReason|Should Be 'first-command-or-agent';$second.SetupLock.ReleasedAt|Should Not BeNullOrEmpty
  @($second.RetryEvents|Where-Object {$_.Turn -eq 2}).Count|Should Be 0
 }
}
