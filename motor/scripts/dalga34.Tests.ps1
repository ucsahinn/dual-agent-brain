. (Join-Path (Split-Path $PSScriptRoot -Parent) 'hooks/lib.ps1')
. (Join-Path $PSScriptRoot 'merkez-veri.ps1')

Describe 'Y9: channel workers in the same read-only monitor model' {
    It 'uses the same effective-token formula for team and channel workers' {
        (Get-MerkezEffectiveTokens ([pscustomobject]@{input_tokens=1000;cached_input_tokens=800;output_tokens=100})) | Should Be 380
        (Get-MerkezEffectiveTokens ([pscustomobject]@{input_tokens=100;cached_input_tokens=1000;output_tokens=10})) | Should Be 20
    }
    It 'reads both engines, approvals, queue, effective budget and last event without mutating records' {
        $tv = Join-Path $TestDrive 'channels'
        $paths = Get-BeyinPaths -Vault $tv
        $dir = Join-Path $paths.ScrState 'codex-kanal'
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        $file = Join-Path $dir 'CK-fixture.json'
        $record = @{ Id='CK-fixture'; Engine='claude'; Backend='claude-stream'; Role='qa_lead'; Project='C:\demo'; Status='limit-waiting'; Started=(Get-Date).AddMinutes(-4).ToString('o'); LastEvent='2026-10-28T10:00:00Z'; Budget=@{effectiveTokens=123}; PendingApprovals=@(@{id='approval-1';method='command'}); LimitQueue=@{status='planned';dueAt=999999} }
        $record | ConvertTo-Json -Depth 6 | Set-Content -Encoding UTF8 -LiteralPath $file
        $before = [IO.File]::ReadAllText($file)
        $workers = @(Get-MerkezKanalIsciler -Paths $paths)
        $workers.Count | Should Be 1
        $workers[0].Ajan | Should Be claude
        $workers[0].Jeton | Should Be 123
        $workers[0].Onay | Should Be 1
        $workers[0].Kuyruk | Should Be planned
        $workers[0].Rol | Should Be qa_lead
        [IO.File]::ReadAllText($file) | Should Be $before
    }
}

Describe 'R13: hints must agree with dispatcher and installed team CLI' {
    It 'rejects an unknown command and an unsupported PowerShell flag' {
        . (Join-Path $PSScriptRoot 'ipucu-denetle.ps1')
        $root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
        $r = Test-BeyinHintConsistency -Vault $root -Texts @('beyin merkez -Olmayan', 'beyin ghost')
        $r.Ok | Should Be $false
        $r.Errors.Count | Should Be 2
    }
}

Describe 'Wave 3/4 CLI smoke through the real dispatcher' {
    It 'lists history, saves and indexes a report, deduplicates and acknowledges a handoff' {
        $root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
        $tv = Join-Path $TestDrive 'cli-vault'
        foreach ($folder in @('motor/hooks','motor/scripts','kurulum')) { New-Item -ItemType Directory -Force -Path (Join-Path $tv $folder) | Out-Null }
        Copy-Item (Join-Path $root 'motor/hooks/lib.ps1') (Join-Path $tv 'motor/hooks/lib.ps1')
        foreach ($file in @('gecmis.ps1','rapor.ps1','aktar.ps1')) { Copy-Item (Join-Path $PSScriptRoot $file) (Join-Path $tv ('motor/scripts/' + $file)) }
        $cli = Join-Path $tv 'kurulum/beyin.ps1'
        Copy-Item (Join-Path $root 'kurulum/beyin.ps1') $cli
        $project = Join-Path $TestDrive 'cli-project'
        New-Item -ItemType Directory -Force -Path $project | Out-Null
        $source = Join-Path $project 'source.md'
        Set-Content -Encoding UTF8 -LiteralPath $source -Value "Outcome: fixture ready`nEvidence: synthetic"
        $exe = (Get-Command powershell.exe).Source
        $savedVault = $env:BEYIN_VAULT; $savedAgent = $env:BEYIN_AGENT
        try {
            $env:BEYIN_VAULT = $tv; $env:BEYIN_AGENT = 'claude'
            $paths = Get-BeyinPaths -Vault $tv
            Add-BeyinSessionHistory -Paths $paths -Session fixture -Project $project -Task TASK-1 -Event open -Agent claude
            $history = & $exe -NoProfile -ExecutionPolicy Bypass -File $cli gecmis -Proje $project -Is TASK-1 -Json | Out-String
            $LASTEXITCODE | Should Be 0
            @($history | ConvertFrom-Json)[0].olay | Should Be open
            $null = & $exe -NoProfile -ExecutionPolicy Bypass -File $cli rapor kaydet -Proje $project -Is TASK-1 -Kaynak $source
            $LASTEXITCODE | Should Be 0
            $reports = & $exe -NoProfile -ExecutionPolicy Bypass -File $cli rapor liste -Proje $project -Json | Out-String
            $LASTEXITCODE | Should Be 0
            @($reports | ConvertFrom-Json)[0].Outcome | Should Be 'fixture ready'
            for ($i=0; $i -lt 3; $i++) { $null = & $exe -NoProfile -ExecutionPolicy Bypass -File $cli aktar 'same event' -Kime claude -Olay fixture-event }
            $h = @(Get-BeyinHandoffListe -Paths $paths)
            $h.Count | Should Be 1
            $h[0].occurrences | Should Be 3
            $null = & $exe -NoProfile -ExecutionPolicy Bypass -File $cli aktar -Gor $h[0].id
            $LASTEXITCODE | Should Be 0
            @(Read-BeyinMakbuz -Paths $paths -Gun 1 | Where-Object { $_.outcome -eq 'OKUNDU' }).Count | Should Be 1
            $null = & $exe -NoProfile -ExecutionPolicy Bypass -File $cli aktar -Kayit $h[0].id -Durum completed
            $LASTEXITCODE | Should Be 0
            (Get-BeyinHandoff -Paths $paths -Id $h[0].id).a2aStatus | Should Be completed
            # Fake channel only in the temporary vault: prove the dispatcher's post-call seam.
            $stub = @'
param([string]$Komut,[string]$Id='', [string]$Proje='')
$dir=Join-Path $env:BEYIN_VAULT 'motor/scripts/.state/codex-kanal'
New-Item -ItemType Directory -Force -Path $dir | Out-Null
$idValue='CK-'+('b'*32);$file=Join-Path $dir ($idValue+'.json')
if($Komut -eq 'ac'){$r=[pscustomobject]@{Owner='beyin-codex-kanal-v1';Id=$idValue;Engine='codex';Project=$Proje;SessionId='dispatcher-thread';TaskKey='dispatcher-task';Status='ready';Turn=0;HandoffValid=$false;Answer=''}}else{$r=Get-Content -LiteralPath $file -Raw|ConvertFrom-Json}
if($Komut -eq 'sor'){$r.Turn=1;$r.Status='completed';$r.HandoffValid=$true;$r.Answer="Outcome: dispatcher channel ready`nEvidence: synthetic"}
if($Komut -eq 'kapat'){$r.Status='closed'}
$r|ConvertTo-Json|Set-Content -Encoding UTF8 -LiteralPath $file
Write-Output 'fixture-channel-ok'
'@
            Set-Content -Encoding UTF8 -LiteralPath (Join-Path $tv 'motor/scripts/codex-kanal.ps1') -Value $stub
            $ck = 'CK-' + ('b' * 32)
            $null = & $exe -NoProfile -ExecutionPolicy Bypass -File $cli codex ac -Proje $project
            $LASTEXITCODE | Should Be 0
            $null = & $exe -NoProfile -ExecutionPolicy Bypass -File $cli codex sor $ck
            $LASTEXITCODE | Should Be 0
            $null = & $exe -NoProfile -ExecutionPolicy Bypass -File $cli codex kapat $ck
            $LASTEXITCODE | Should Be 0
            $chain = @(Get-BeyinSessionHistory -Paths $paths -Task dispatcher-task)
            ($chain.olay -join ',') | Should Be 'open,resume,complete,close'
            @(Get-BeyinProjectReports -Project $project).Count | Should Be 2
        } finally { $env:BEYIN_VAULT=$savedVault; $env:BEYIN_AGENT=$savedAgent }
    }
}
