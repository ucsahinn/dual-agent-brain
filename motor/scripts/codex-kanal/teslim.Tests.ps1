$repo=Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
. (Join-Path $repo 'motor/hooks/lib.ps1');. (Join-Path $PSScriptRoot 'core.ps1')
Describe 'Delivery, claim and continuation decisions' {
 It 'distinguishes unknown swallowed pending and processed owned rollout evidence' {
  $r=[pscustomobject]@{Id=('CK-'+[guid]::NewGuid().ToString('N'));Owner='beyin-codex-kanal-v1';OwnerSession=(Get-KanalOwnerSession);SessionId='11111111-1111-4111-8111-111111111111';PromptHash=(Get-KanalHash 'message')}
  $ctx=New-KanalContext $repo;$ctx.RolloutRoot=Join-Path $TestDrive 'rollouts';$ctx.State=Join-Path $TestDrive 'state';New-Item -ItemType Directory -Force $ctx.State,$ctx.RolloutRoot | Out-Null;Save-KanalRecord $ctx $r
  (Get-KanalDelivery $ctx $r).Status | Should Be 'belirsiz'
  $file=Join-Path $ctx.RolloutRoot ('rollout-'+$r.SessionId+'.jsonl')
  $meta=@{type='session_meta';payload=@{id=$r.SessionId}}|ConvertTo-Json -Compress
  Set-Content -Encoding UTF8 $file $meta
  (Get-KanalDelivery $ctx $r).Status | Should Be 'yutuldu'
  @{type='event_msg';payload=@{type='user_message';message='message'}}|ConvertTo-Json -Compress|Add-Content -Encoding UTF8 $file
  (Get-KanalDelivery $ctx $r).Status | Should Be 'alindi-cevapsiz'
  @{type='event_msg';payload=@{type='task_complete';last_agent_message='done'}}|ConvertTo-Json -Compress|Add-Content -Encoding UTF8 $file
  (Get-KanalDelivery $ctx $r).Status | Should Be 'islendi'
  $r.OwnerSession='other-owner';Save-KanalRecord $ctx $r
  (Get-KanalDelivery $ctx $r).Status | Should Be 'belirsiz'
 }
 It 'selects fresh for age context request count or changed task and resumes otherwise' {
  (Get-KanalContinuation ([datetime]::UtcNow.AddMinutes(-1)) 'a' 'a' 10 1).Decision | Should Be 'resume'
  (Get-KanalContinuation ([datetime]::UtcNow.AddMinutes(-61)) 'a' 'a' 10 1).Decision | Should Be 'fresh'
  (Get-KanalContinuation ([datetime]::UtcNow) 'a' 'a' 200001 1).Decision | Should Be 'fresh'
  (Get-KanalContinuation ([datetime]::UtcNow) 'a' 'a' 10 301).Decision | Should Be 'fresh'
  (Get-KanalContinuation ([datetime]::UtcNow) 'a' 'b' 10 1).Decision | Should Be 'fresh'
 }
 It 'binds a task claim to one active worker' {
  $ctx=New-KanalContext $repo;$ctx.State=Join-Path $TestDrive 'claims';New-Item -ItemType Directory -Force $ctx.State|Out-Null
  $a=Open-KanalClaim $ctx 'same-key'
  try{{Open-KanalClaim $ctx 'same-key'}|Should Throw; $b=Open-KanalClaim $ctx 'different-scope';$b.Dispose()}finally{$a.Dispose()}
 }
}
