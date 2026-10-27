. (Join-Path $PSScriptRoot 'takim-uyum.ps1')
. (Join-Path $PSScriptRoot 'merkez-veri.ps1')
Describe 'AgentChef 1.9 compatibility hints' {
 It 'recognizes lead-review commands in the worker panel command label' {
  $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'takim-izle.ps1'),[ref]$null,[ref]$null)
  $fn=$ast.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'CheckKey'},$true)|Select-Object -First 1
  . ([scriptblock]::Create($fn.Extent.Text));(CheckKey 'node scripts/team-run.mjs lead-review --run R-1')|Should Be 'team-run lead-review'
 }
 It 'keeps old cleanup hints but requires explicit approved cleanup on 1.9' {
  (Get-TakimCleanupKomut 'R-1' '1.8.6')|Should Be 'beyin takim cleanup R-1'
  (Get-TakimCleanupKomut 'R-1' '1.9.0')|Should Be 'beyin takim cleanup R-1 --approved'
 }
 It 'requires lead review only on the new motor and writable runs' {
  $run=@{runId='R-1';status='integrated';integration=@{ok=$true;commit='abc'};workers=@(@{sandbox='workspace-write'})}
  (Get-MerkezKosuSonraki $run $false '1.8.6').Metin|Should Match 'verify'
  (Get-MerkezKosuSonraki $run $false '1.9.0').Metin|Should Match 'lead-review'
  $run.workers=@(@{sandbox='read-only'});(Get-MerkezKosuSonraki $run $false '1.9.0').Metin|Should Match 'verify'
 }
 It 'accepts only a passing Claude review pinned to the integration commit with evidence' {
  $run=@{runId='R-1';status='integrated';integration=@{ok=$true;commit='abc'};workers=@(@{sandbox='workspace-write'});leadReview=@{engine='claude';reviewer='chief';verdict='pass';integrationCommit='abc';evidence=@('proof')}}
  (Get-MerkezKosuSonraki $run $false '1.9.0').Metin|Should Match 'verify'
  $run.leadReview.integrationCommit='old';(Get-MerkezKosuSonraki $run $false '1.9.0').Metin|Should Match 'lead-review'
  $run.status='verified';(Get-MerkezKosuSonraki $run $false '1.9.0').Metin|Should Match 'lead-review'
  $run.leadReview.integrationCommit='abc';$run.leadReview.evidence=@();(Get-MerkezKosuSonraki $run $false '1.9.0').Metin|Should Match 'lead-review'
 }
 It 'reads a selected AgentChef package version without executing it or writing a cache' {
  $saved=$env:BEYIN_AGENTCHEF_KOK
  try{$env:BEYIN_AGENTCHEF_KOK=$TestDrive;' {"version":"1.9.0"}'|Set-Content (Join-Path $TestDrive 'package.json');(Get-TakimUyumSurum)|Should Be '1.9.0'}finally{$env:BEYIN_AGENTCHEF_KOK=$saved}
 }
 It 'renders the new lead-review and approved cleanup hints while keeping the 1.8 panel hint' {
  $root=Join-Path $TestDrive 'panel';$hooks=Join-Path $root 'motor/hooks';$runs=Join-Path $root 'motor/scripts/.state/team-runs';$chef=Join-Path $root 'chef'
  New-Item -ItemType Directory -Force $hooks,$runs,$chef|Out-Null
  Copy-Item (Join-Path (Split-Path $PSScriptRoot -Parent) 'hooks/lib.ps1') $hooks
  $saved=$env:BEYIN_AGENTCHEF_KOK
  try{
   $env:BEYIN_AGENTCHEF_KOK=$chef;'{"version":"1.9.0"}'|Set-Content (Join-Path $chef 'package.json')
   $run=@{runId='R-UI';repoName='fixture';status='integrated';integration=@{ok=$true;commit='abc'};workers=@(@{taskId='TASK-UI';role='docs_author';status='integrated';sandbox='workspace-write';verdict='pass'})}
   $file=Join-Path $runs 'R-UI.json';$run|ConvertTo-Json -Depth 6|Set-Content -Encoding UTF8 $file
   $args=@('-NoProfile','-File',(Join-Path $PSScriptRoot 'takim-izle.ps1'),'-Vault',$root,'-Run','R-UI','-Tek','-Genislik',210,'-Yukseklik',70)
   $screen=& powershell.exe @args 2>&1|Out-String;$LASTEXITCODE|Should Be 0;$screen|Should Match 'lead-review'
   $run.status='aborted';$run|ConvertTo-Json -Depth 6|Set-Content -Encoding UTF8 $file
   $screen=& powershell.exe @args 2>&1|Out-String;$LASTEXITCODE|Should Be 0;$screen|Should Match 'cleanup R-UI --approved'
   '{"version":"1.8.6"}'|Set-Content (Join-Path $chef 'package.json')
   $screen=& powershell.exe @args 2>&1|Out-String;$LASTEXITCODE|Should Be 0;$screen|Should Match 'cleanup R-UI';$screen|Should Not Match '--approved'
  }finally{$env:BEYIN_AGENTCHEF_KOK=$saved}
 }
}
