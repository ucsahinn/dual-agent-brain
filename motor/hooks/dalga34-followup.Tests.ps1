. (Join-Path $PSScriptRoot 'lib.ps1')
Describe 'Followup: opt-in RRF and producer-owned history' {
    It 'defaults to hybrid and enables RRF only through the registered setting' {
        $old=$env:BEYIN_GETIRME_RRF
        try {
            $env:BEYIN_GETIRME_RRF='0'
            (Get-BeyinRetrievalFusion) | Should Be hibrit
            $env:BEYIN_GETIRME_RRF='1'
            (Get-BeyinRetrievalFusion) | Should Be rrf60
            @((Get-BeyinAyarKayitlari) | Where-Object { $_.Ad -eq 'BEYIN_GETIRME_RRF' }).Count | Should Be 1
        } finally { $env:BEYIN_GETIRME_RRF=$old }
    }
    It 'deduplicates producer and dispatcher events and reports across asynchronous turns' {
        $p=Get-BeyinPaths -Vault (Join-Path $TestDrive 'vault')
        $project=Join-Path $TestDrive 'project';New-Item -ItemType Directory -Force $project | Out-Null
        $r=[pscustomobject]@{Owner='beyin-codex-kanal-v1';Id=('CK-'+('a'*32));Engine='codex';Project=$project;SessionId='thread-1';TaskKey='task';Status='ready';Turn=0;HandoffValid=$false;Answer=''}
        Sync-BeyinChannelRecordEvidence -Paths $p -Record $r
        $r.Turn=1;$r.Status='running';Sync-BeyinChannelRecordEvidence -Paths $p -Record $r
        $r.Status='completed';$r.HandoffValid=$true;$r.Answer="Outcome: ready`nEvidence: fixture"
        Sync-BeyinChannelRecordEvidence -Paths $p -Record $r
        Sync-BeyinChannelRecordEvidence -Paths $p -Record $r
        $r.Status='closed';Sync-BeyinChannelRecordEvidence -Paths $p -Record $r
        $events=@(Get-BeyinSessionHistory -Paths $p -Task task)
        ($events.olay -join ',') | Should Be 'open,resume,complete,close'
        @(Get-BeyinProjectReports -Project $project).Count | Should Be 1
    }
    It 'persists the RRF option through ayar in an isolated profile and honors environment precedence' {
        $profileBefore=$env:USERPROFILE;$flagBefore=$env:BEYIN_GETIRME_RRF
        try {
            $env:USERPROFILE=Join-Path $TestDrive 'profile'
            $env:BEYIN_GETIRME_RRF=$null
            $vault=Join-Path $TestDrive 'settings-vault'
            New-Item -ItemType Directory -Force (Join-Path $vault 'motor/hooks') | Out-Null
            Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'lib.ps1') -Destination (Join-Path $vault 'motor/hooks/lib.ps1')
            $command=Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts/ayar.ps1'
            $null=& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $command -Vault $vault -Ad BEYIN_GETIRME_RRF -Deger 1
            $LASTEXITCODE | Should Be 0
            Clear-BeyinAyarCache
            (Get-BeyinRetrievalFusion) | Should Be rrf60
            $env:BEYIN_GETIRME_RRF='0'
            (Get-BeyinRetrievalFusion) | Should Be hibrit
        } finally { $env:USERPROFILE=$profileBefore;$env:BEYIN_GETIRME_RRF=$flagBefore;Clear-BeyinAyarCache }
    }
}
