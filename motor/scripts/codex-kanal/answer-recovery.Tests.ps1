$repo=Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
. (Join-Path $repo 'motor/hooks/lib.ps1');. (Join-Path $PSScriptRoot 'core.ps1')
Describe 'Read-only status answer recovery' {
 BeforeEach {
  $ctx=New-KanalContext $TestDrive;$ctx.State=Join-Path $TestDrive 'records';$ctx.RolloutRoot=Join-Path $TestDrive 'rollouts'
  New-Item -ItemType Directory -Force $ctx.State,$ctx.RolloutRoot|Out-Null
  $sid='11111111-1111-4111-8111-111111111111';$tid='22222222-2222-4222-8222-222222222222'
  $record=[pscustomobject]@{Id=('CK-'+'7'*32);Owner='beyin-codex-kanal-v1';OwnerSession='previous-session';SessionId=$sid;Project=[string]$TestDrive;Engine='codex';Backend='app-server';Status='closed';Turn=1;ActiveTurn=$tid;Answer='';Error='App-server exited';PromptHash=(Get-KanalHash 'brief')}
  $recordPath=Join-Path $ctx.State ($record.Id+'.json')
  $recordJson=$record|ConvertTo-Json -Depth 8
  Set-Content -Encoding UTF8 -LiteralPath $recordPath -Value $recordJson
  $file=Join-Path $ctx.RolloutRoot ('rollout-'+$sid+'.jsonl')
  $answer="Outcome: recovered`nEvidence: fixture`nChanged scope: none`nRisks: none`nOpen questions: none`nNext verification: none"
  @(
   @{type='session_meta';payload=@{id=$sid;cwd=[string]$TestDrive}}
   @{type='turn_context';payload=@{turn_id=$tid;cwd=[string]$TestDrive}}
   @{type='event_msg';payload=@{type='user_message';message='brief'}}
   @{type='event_msg';timestamp='2026-10-28T22:36:59Z';payload=@{type='task_complete';turn_id=$tid;last_agent_message=$answer}}
  )|ForEach-Object {$_|ConvertTo-Json -Depth 8 -Compress}|Set-Content -Encoding UTF8 $file
 }
 It 'shows the lost same-turn answer without mutating the old record or sending notices' {
  $before=[IO.File]::ReadAllText($recordPath)
  $r=@(Get-KanalRecords $ctx -Hepsi)[0]
  $r.Status|Should Be 'completed';$r.Answer|Should Be $answer;$r.ActiveTurn|Should Be ''
  $r.Recovery.Source|Should Be 'owned-rollout';$r.Recovery.OriginalStatus|Should Be 'closed'
  $r.Recovery.Path|Should Be $file;$r.Error|Should Be ''
  [IO.File]::ReadAllText($recordPath)|Should Be $before
  Test-Path (Join-Path $TestDrive 'motor/scripts/.state/handoff')|Should Be $false
 }
 It 'does not steal a later turn answer even when a prior brief hash matches' {
  @{type='turn_context';payload=@{turn_id='33333333-3333-4333-8333-333333333333';cwd=[string]$TestDrive}}|ConvertTo-Json -Compress|Add-Content -Encoding UTF8 $file
  @{type='event_msg';payload=@{type='task_complete';turn_id='33333333-3333-4333-8333-333333333333';last_agent_message='foreign answer'}}|ConvertTo-Json -Compress|Add-Content -Encoding UTF8 $file
  $r=@(Get-KanalRecords $ctx -Hepsi)[0];$r.Answer|Should Be $answer
 }
 It 'shows a recovery route when metadata belongs to another project' {
  $text=[IO.File]::ReadAllText($file).Replace(([string]$TestDrive).Replace('\','\\'),'foreign-project')
  [IO.File]::WriteAllText($file,$text)
  $r=@(Get-KanalRecords $ctx -Hepsi)[0];$r.Answer|Should Be ''; $r.Recovery.Status|Should Be 'unavailable'
  $r.Recovery.Hint|Should Match 'rollout';$r.ActiveTurn|Should Be ''
 }
 It 'preserves malformed structured answers as invalid rather than losing the worker text' {
  $text=[IO.File]::ReadAllText($file).Replace(($answer|ConvertTo-Json -Compress),('{'|ConvertTo-Json -Compress));[IO.File]::WriteAllText($file,$text)
  $r=@(Get-KanalRecords $ctx -Hepsi)[0];$r.Answer|Should Be '{';$r.Status|Should Be 'invalid-handoff'
 }
 It 'does not recover a previous identical prompt when the failed attempt has no turn identity' {
  $record.ActiveTurn='';$record|ConvertTo-Json -Depth 8|Set-Content -Encoding UTF8 $recordPath
  @{type='event_msg';payload=@{type='user_message';message='brief'}}|ConvertTo-Json -Compress|Add-Content -Encoding UTF8 $file
  $r=@(Get-KanalRecords $ctx -Hepsi)[0];$r.Answer|Should Be '';$r.Status|Should Be 'closed';$r.Recovery.Status|Should Be 'unavailable'
 }
}
