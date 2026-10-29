$repo=Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
. (Join-Path $repo 'motor/hooks/lib.ps1');. (Join-Path $PSScriptRoot 'core.ps1');. (Join-Path $PSScriptRoot 'kopru.ps1')
function New-FakeCodexInstall([string]$Root,[string]$Version){
 $directory=Join-Path $Root 'node_modules/@openai/codex/bin';New-Item -ItemType Directory -Force $directory|Out-Null
 $app=(Join-Path $PSScriptRoot 'fixtures/app-server.mjs').Replace('\','/')
 $source=@'
const fs=require('fs'),args=process.argv.slice(2);
if(args.includes('--version')){console.log('codex-cli VERSION');process.exit(0);}
if('VERSION'==='0.147.0'){console.error('model_not_found; setup refresh had errors');process.exit(71);}
if(args.includes('generate-json-schema')){fs.writeFileSync(require('path').join(args[args.indexOf('--out')+1],'fixture.json'),'{}');}
else if(args.includes('app-server')){import('file:///APPFIXTURE');}
else{fs.readFileSync(0,'utf8');console.log(JSON.stringify({type:'thread.started',thread_id:'11111111-1111-4111-8111-111111111111'}));console.log(JSON.stringify({type:'item.completed',item:{type:'agent_message',text:'Outcome: OK\nEvidence: selected current fixture\nChanged scope: none\nRisks: none\nOpen questions: none\nNext verification: none'}}));console.log(JSON.stringify({type:'turn.completed'}));}
'@
 [IO.File]::WriteAllText((Join-Path $directory 'codex.js'),$source.Replace('VERSION',$Version).Replace('APPFIXTURE',$app),(New-Object Text.UTF8Encoding $false))
 $shim=Join-Path $Root 'codex.cmd';[IO.File]::WriteAllText($shim,"@echo off`r`nnode.exe `"%~dp0node_modules\@openai\codex\bin\codex.js`" %*`r`n")
 return $shim
}
Describe 'One deterministic Codex resolver' {
 BeforeEach {
  $old=New-FakeCodexInstall (Join-Path $TestDrive 'old') '0.147.0';$new=New-FakeCodexInstall (Join-Path $TestDrive 'new') '0.162.1'
  $ctx=New-KanalContext $repo;$ctx.State=Join-Path $TestDrive 'state';$ctx.CodexCandidates=@($old,$new);$ctx.CodexSetting='';$ctx.ConfigPath=Join-Path $TestDrive 'config.toml';'[mcp_servers.node_repl]'|Set-Content $ctx.ConfigPath
  Mock Get-KanalCapacity { @{onerilen=8} };Mock Get-KanalTeamCount {0}
 }
 It 'selects newest version despite candidate order and caches that exact launch' {
  $a=Resolve-KanalCodex $ctx;$a.Path|Should Be $new;$a.Version|Should Be '0.162.1';$a.Conflict|Should Be $true;$a.Candidates.Count|Should Be 2
  (Resolve-KanalLaunch $ctx).Path|Should Be $new
 }
 It 'selects a slow current launcher whose version probe exceeds five seconds' {
  $cli=Join-Path (Split-Path $new -Parent) 'node_modules/@openai/codex/bin/codex.js'
  $source=[IO.File]::ReadAllText($cli).Replace("console.log('codex-cli 0.162.1');", "Atomics.wait(new Int32Array(new SharedArrayBuffer(4)),0,0,5500);console.log('codex-cli 0.162.1');")
  [IO.File]::WriteAllText($cli,$source)
  $a=Resolve-KanalCodex $ctx
  $a.Version|Should Be '0.162.1'
  $a.Path|Should Be $new
 }
 It 'refuses an automatic downgrade when another candidate cannot be version validated' {
  $ctx.FailVersionProbe=$new
  Mock Get-KanalCodexVersion {throw 'probe timed out'} -ParameterFilter {$Context.ContainsKey('FailVersionProbe') -and $Launch.Path -eq $Context.FailVersionProbe}
  {Resolve-KanalCodex $ctx}|Should Throw 'could not be version-validated'
  $ctx.ResolvedCodex|Should BeNullOrEmpty
 }
 It 'retries a timed out version probe once using a fresh owned process' {
  $cli=Join-Path (Split-Path $new -Parent) 'node_modules/@openai/codex/bin/codex.js'
  $delay="if(!fs.existsSync(__filename+'.attempt')){fs.writeFileSync(__filename+'.attempt','1');Atomics.wait(new Int32Array(new SharedArrayBuffer(4)),0,0,3500);}"
  [IO.File]::WriteAllText($cli,[IO.File]::ReadAllText($cli).Replace("console.log('codex-cli 0.162.1');",$delay+"console.log('codex-cli 0.162.1');"))
  $ctx.VersionTimeoutMs=3000
  (Resolve-KanalCodex $ctx).Version|Should Be '0.162.1'
 }
 It 'honors the explicit Beyin setting even when it pins the older installation' {
  $ctx.Remove('CodexSetting');$script:explicitOld=$old
  Mock Get-BeyinAyar {param($Ad,$Varsayilan) if($Ad -eq 'BEYIN_CODEX_YOLU'){return $script:explicitOld};return $Varsayilan}
  $a=Resolve-KanalCodex $ctx;$a.Path|Should Be $old
  (Get-KanalSchemaStatus $ctx).Current|Should Be '0.147.0';(Get-KanalSchemaStatus $ctx).Changed|Should Be $true
  Assert-MockCalled Get-BeyinAyar -Times 1 -Exactly -Scope It -ParameterFilter {$Ad -eq 'BEYIN_CODEX_YOLU'}
 }
 It 'discovers both PATH entries without invoking any discovered executable' {
  $saved=$env:PATH
  try{$env:PATH=(Split-Path $old -Parent)+';'+(Split-Path $new -Parent)+';'+$saved;$ctx.Remove('CodexCandidates');$paths=@(Get-KanalCodexCandidates $ctx);($paths -contains $old)|Should Be $true;($paths -contains $new)|Should Be $true}finally{$env:PATH=$saved}
 }
 It 'uses the same selected current executable for exec, schema generation, app-server and TUI launch base' {
  $schema=Export-KanalSchema $ctx;$schema.Current|Should Be '0.162.1';$schema.Generated|Should Be $true
  $exec=Submit-KanalTurn $ctx -Proje $TestDrive -Metin 'first';$exec.Status|Should Be 'completed';$exec.CodexPath|Should Be $new;$exec.Attempts|Should Be 1;$exec.SandboxFallback|Should BeNullOrEmpty
  $bridge=Open-KanalBridge $ctx $TestDrive
  try{$result=Send-KanalBridge $ctx $bridge.Id 'sor' 'first';$result.Status|Should Be 'completed';$result.Attempts|Should Be 1;$result.ModelFallback|Should BeNullOrEmpty;$result.SandboxFallback|Should BeNullOrEmpty;$result.CodexVersion|Should Be '0.162.1'
   $launch=Get-Content -Raw (Join-Path (Join-Path $ctx.State $bridge.Id) 'launch.json')|ConvertFrom-Json
   $launch.command|Should Be (Resolve-KanalCodex $ctx).command;$launch.args[0]|Should Be (Resolve-KanalCodex $ctx).args[0]
   (Get-Content -Raw (Join-Path (Join-Path $ctx.State $bridge.Id) 'events.jsonl'))|Should Match 'Multiple Codex versions'
  }finally{try{Close-KanalWorker $ctx $bridge.Id|Out-Null}catch{}}
 }
}
