$repo = Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
. (Join-Path $repo 'motor/hooks/lib.ps1')
. (Join-Path $PSScriptRoot 'core.ps1')
Describe 'Channel process ownership' {
    It 'closes only the registered job and its descendants' {
        $ctx=New-KanalContext $repo; $ctx.State=Join-Path $TestDrive 'owned'
        New-Item -ItemType Directory -Force $ctx.State | Out-Null
        $r=[pscustomobject]@{Owner='beyin-codex-kanal-v1';Id=('CK-'+[guid]::NewGuid().ToString('N'));OwnerSession=(Get-KanalOwnerSession);Status='running';Prompt='';Error='';Finished=''}
        $p=Start-KanalPowerShell '$child=Start-Process powershell.exe -WindowStyle Hidden -ArgumentList @("-NoProfile","-Command","Start-Sleep -Seconds 60") -PassThru; Write-Output $child.Id; Start-Sleep -Seconds 60' $TestDrive -JobName ('Local\Beyin-'+$r.Id)
        try {
            Register-KanalProcess $ctx $r $p
            $p.StandardInput.Close()
            $line=$p.StandardOutput.ReadLineAsync(); $line.Wait(10000) | Should Be $true
            $childId=[int]$line.Result
            (Close-KanalWorker $ctx $r.Id).Status | Should Be 'closed'
            $p.WaitForExit(10000) | Should Be $true
            Start-Sleep -Milliseconds 100
            @(Get-Process -Id $childId -ErrorAction SilentlyContinue).Count | Should Be 0
        } finally { Close-KanalPowerShell $p }
    }
    It 'denies a different owner before touching a process' {
        $ctx=New-KanalContext $repo; $ctx.State=Join-Path $TestDrive 'foreign'
        New-Item -ItemType Directory -Force $ctx.State | Out-Null
        $r=[pscustomobject]@{Owner='beyin-codex-kanal-v1';Id=('CK-'+[guid]::NewGuid().ToString('N'));OwnerSession='some-other-session';Status='running'}
        Save-KanalRecord $ctx $r
        { Close-KanalWorker $ctx $r.Id } | Should Throw 'owner'
    }
    It 'reports dead hosts without stopping any unrelated process' {
        $ctx=New-KanalContext $repo; $ctx.State=Join-Path $TestDrive 'orphans'
        New-Item -ItemType Directory -Force $ctx.State | Out-Null
        $r=[pscustomobject]@{Owner='beyin-codex-kanal-v1';Id=('CK-'+[guid]::NewGuid().ToString('N'));OwnerSession=(Get-KanalOwnerSession);HostPid=2147483646;HostStart='2000-01-01T00:00:00Z';RootPid=$PID;RootStart=(Get-Process -Id $PID).StartTime.ToUniversalTime().ToString('o');Status='running'}
        Save-KanalRecord $ctx $r
        @(Get-KanalOrphans $ctx)[0].Status | Should Be 'orphan'
        (Get-Process -Id $PID).Id | Should Be $PID
    }
    It 'rejects reused process identities' {
        Test-KanalProcessIdentity $PID '2000-01-01T00:00:00Z' | Should Be $false
    }
}
