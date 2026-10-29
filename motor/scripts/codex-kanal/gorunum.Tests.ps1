. (Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'hooks/lib.ps1')
. (Join-Path $PSScriptRoot 'core.ps1')
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'merkez-veri.ps1')
Describe 'Channel history visibility' {
    BeforeEach {
        $ctx=New-KanalContext (Join-Path $TestDrive ([guid]::NewGuid().ToString('N')))
        New-Item -ItemType Directory -Force $ctx.State | Out-Null
        $old=[pscustomobject]@{Owner='beyin-codex-kanal-v1';Id=('CK-'+[guid]::NewGuid().ToString('N'));Project=[string]$TestDrive;Status='closed';Created=[datetime]::UtcNow.AddDays(-4).ToString('o');Finished=[datetime]::UtcNow.AddDays(-3).ToString('o');Pid=0;ProcessStart=''}
        Save-KanalRecord $ctx $old
    }
    It 'hides old terminal records without losing direct or all-history access' {
        @(Get-KanalRecords $ctx -RecentHours 24).Count | Should Be 0
        @(Get-KanalRecords $ctx -Hepsi).Count | Should Be 1
        (Read-KanalRecord $ctx $old.Id).Id | Should Be $old.Id
    }
    It 'archives by metadata only and keeps archived records readable' {
        @(Archive-KanalRecords $ctx).Count | Should Be 1
        (Read-KanalRecord $ctx $old.Id).ArchivedAt | Should BeNullOrEmpty
        $null=Archive-KanalRecords $ctx -Apply
        (Read-KanalRecord $ctx $old.Id).ArchivedAt | Should Not BeNullOrEmpty
        @(Get-KanalRecords $ctx -Hepsi).Count | Should Be 1
    }
    It 'never archives an identity-verified living owner even if terminal and old' {
        $old.Pid=$PID;$old.ProcessStart=(Get-Process -Id $PID).StartTime.ToUniversalTime().ToString('o')
        Save-KanalRecord $ctx $old
        @(Archive-KanalRecords $ctx -Apply).Count | Should Be 0
        @(Get-KanalRecords $ctx -RecentHours 24).Count | Should Be 1
    }
    It 'retains open records and recent closed records but hides archived ones in merkez' {
        $old.Status='ready';Save-KanalRecord $ctx $old
        @(Get-KanalRecords $ctx -RecentHours 24).Count | Should Be 1
        $old.Status='closed';$old.Finished=[datetime]::UtcNow.ToString('o');Save-KanalRecord $ctx $old
        @(Get-KanalRecords $ctx -RecentHours 24).Count | Should Be 1
        $old | Add-Member ArchivedAt ([datetime]::UtcNow.ToString('o'));Save-KanalRecord $ctx $old
        @(Get-MerkezKanalIsciler @{ScrState=(Split-Path $ctx.State -Parent)}).Count | Should Be 0
    }
    It 'preserves a living encoded parent session even after the worker ended' {
        $old | Add-Member OwnerSession ('agent:{0}:{1}' -f $PID,(Get-Process -Id $PID).StartTime.ToUniversalTime().Ticks)
        Save-KanalRecord $ctx $old
        @(Archive-KanalRecords $ctx -Apply).Count | Should Be 0
    }
    It 'shows one merkez row when the same record appears in both engine roots' {
        $old.Status='ready';Save-KanalRecord $ctx $old
        $other=Join-Path (Split-Path $ctx.State -Parent) 'claude-kanal'
        New-Item -ItemType Directory -Force $other | Out-Null
        Copy-Item (Get-KanalRecordPath $ctx $old.Id) $other
        @(Get-MerkezKanalIsciler @{ScrState=(Split-Path $ctx.State -Parent)}).Count | Should Be 1
    }
}

Describe 'Claim keys use actual task intent' {
    BeforeAll { . (Join-Path $PSScriptRoot 'kopru.ps1') }
    It 'gives different keys to different plain messages compiled with the generic brief' {
        $r=[pscustomobject]@{Project=[string]$TestDrive;TaskKey='old-empty';ExplicitWriteScopes=$false}
        $a=Get-KanalClaimKey $r (New-KanalBrief 'first task' ([string]$TestDrive))
        $b=Get-KanalClaimKey $r (New-KanalBrief 'second task' ([string]$TestDrive))
        $a | Should Not Be $b
    }
    It 'keeps explicit Windows scope equivalence across different task messages' {
        $r=[pscustomobject]@{Project=[string]$TestDrive;ExplicitWriteScopes=$true;WriteScopes=@('SRC\A')}
        $a=Get-KanalClaimKey $r 'first'
        $r.WriteScopes=@('src/a')
        (Get-KanalClaimKey $r 'second') | Should Be $a
    }
}
