$repo=Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
. (Join-Path $repo 'motor/hooks/lib.ps1')
. (Join-Path $PSScriptRoot 'core.ps1')
. (Join-Path $PSScriptRoot 'kopru.ps1')
Describe 'Dalga 4 channel contracts without live agents' {
 It 'records unknown values instead of mapping them to a different engine' {
  (Resolve-KanalEngine 'typo')|Should BeNullOrEmpty
  (Resolve-KanalEngine '' 'claude')|Should Be 'claude'
  (Resolve-KanalBackend 'typo')|Should BeNullOrEmpty
 }
 It 'classifies signal exits separately from faults' {
  $r=Get-KanalWorkerExit 143 'codex';$r.Kind|Should Be 'signal';$r.Signal|Should Be 15;$r.Fault|Should Be $false
 }
 It 'persists unknown engine and backend as null with an explicit unknown marker' {
  $ctx=New-KanalContext $repo;$ctx.State=Join-Path $TestDrive 'unknown';New-Item -ItemType Directory $ctx.State|Out-Null
  $r=[pscustomobject]@{Owner='beyin-codex-kanal-v1';Id=('CK-'+('e'*32));Engine='typo';Backend='typo'}
  Save-KanalRecord $ctx $r;$saved=Read-KanalRecord $ctx $r.Id
  $saved.Engine|Should BeNullOrEmpty;$saved.Backend|Should BeNullOrEmpty;$saved.EngineStatus|Should Be 'unknown';$saved.BackendStatus|Should Be 'unknown'
 }
 It 'validates explicit existing homes without creating accounts or modifying settings' {
  $homePath=Join-Path $TestDrive 'home';New-Item -ItemType Directory $homePath|Out-Null
  $ctx=New-KanalContext $repo;$ctx.CodexProfiles=@(@{name='one';home=$homePath;profile='worker'})
  $p=@(Get-KanalProfiles $ctx);$p.Count|Should Be 1;$p[0].home|Should Be $homePath
  $ctx.CodexProfiles=@(@{name='two';home=(Join-Path $TestDrive 'absent')})
  {Get-KanalProfiles $ctx}|Should Throw
 }
 It 'restarts a dead fake host from launch.json with the same owned thread' {
  Mock Get-KanalCapacity { @{onerilen=8} };Mock Get-KanalActiveCount {0}
  $ctx=New-KanalContext $repo;$ctx.State=Join-Path $TestDrive 'state';$ctx.Timeout=10
  $id='CK-'+('d'*32);$dir=Join-Path $ctx.State $id;New-Item -ItemType Directory $dir -Force|Out-Null
  $r=[pscustomobject]@{Owner='beyin-codex-kanal-v1';Id=$id;OwnerSession=(Get-KanalOwnerSession);Backend='app-server';Engine='codex';Project=[string]$TestDrive;SessionId='33333333-3333-4333-8333-333333333333';Status='running';Pid=0;ProcessStart='';Turn=0;Error=''}
  Save-KanalRecord $ctx $r
  $cfg=@{state=$ctx.State;id=$id;owner=$r.OwnerSession;command=(Get-Command node.exe).Source;args=@((Join-Path $PSScriptRoot 'fixtures/dalga4-server.mjs'),'subscription');engine='codex';setupLockOptions=@{name=('Local\Beyin-test-'+[guid]::NewGuid().ToString('N'))}}
  [IO.File]::WriteAllText((Join-Path $dir 'launch.json'),($cfg|ConvertTo-Json -Depth 8))
  try{
   $res=Resume-KanalBridge $ctx $id;$res.SessionId|Should Be $r.SessionId;$res.Status|Should Be 'ready'
   $done=Send-KanalBridge $ctx $id 'sor' 'recover';$done.Status|Should Be 'completed';$done.Error|Should BeNullOrEmpty
   Test-Path (Join-Path $dir 'plan.md')|Should Be $true
   Test-Path (Join-Path $dir 'notes.md')|Should Be $true
  }finally{try{Close-KanalWorker $ctx $id|Out-Null}catch{}}
 }
}
