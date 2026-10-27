$repo=Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
. (Join-Path $repo 'motor/hooks/lib.ps1')
. (Join-Path $PSScriptRoot 'core.ps1')
. (Join-Path $PSScriptRoot 'kopru.ps1')
Describe 'Persistent channel with a fake app-server process' {
    It 'rejects the same active task on another ready worker before delivery' {
        Mock Get-KanalCapacity { @{onerilen=8} };Mock Get-KanalTeamCount { 0 }
        $ctx=New-KanalContext $repo;$ctx.State=Join-Path $TestDrive 'claims-bridge';$ctx.Timeout=20
        $ctx.BridgeLaunch=@{command=(Get-Command node.exe).Source;args=@((Join-Path $PSScriptRoot 'fixtures/app-server.mjs'))}
        $ctx.SetupLockOptions=@{holdMs=100;waitMs=3000;name=('Local\Beyin-fixture-'+[guid]::NewGuid().ToString('N'))}
        $a=$null;$b=$null
        try{$a=Open-KanalBridge $ctx $TestDrive;$b=Open-KanalBridge $ctx $TestDrive
            $null=Send-KanalBridge $ctx $a.Id 'sor' 'wait' -Background
            {Send-KanalBridge $ctx $b.Id 'sor' 'wait' -Background}|Should Throw 'Task already claimed'
        }finally{foreach($r in @($a,$b)){try{Close-KanalWorker $ctx $r.Id|Out-Null}catch{}}}
    }
    It 'routes the Claude wrapper through one owned persistent stream process' {
        Mock Get-KanalCapacity { @{onerilen=8} };Mock Get-KanalTeamCount { 0 }
        $ctx=New-KanalContext $repo;$ctx.State=Join-Path $TestDrive 'claude-bridge';$ctx.Timeout=20;$ctx.Engine='claude';$ctx.Entry=Join-Path $repo 'motor/scripts/claude-kanal.ps1'
        $ctx.BridgeLaunch=@{command=(Get-Command node.exe).Source;args=@((Join-Path $repo 'motor/scripts/claude-kanal/fixtures/claude.mjs'),'--fixture-state',(Join-Path $TestDrive 'claude-context'))}
        $r=Open-KanalBridge $ctx $TestDrive
        try{
            $a=Send-KanalBridge $ctx $r.Id 'sor' 'remember';$b=Send-KanalBridge $ctx $r.Id 'sor' 'recall'
            $b.Backend|Should Be 'claude-stream';$b.SessionId|Should Be $a.SessionId;$b.Answer|Should Match 'synthetic-memory';$b.Turn|Should Be 2
            $null=Send-KanalBridge $ctx $r.Id 'sor' 'approval' -Background
            $until=[datetime]::UtcNow.AddSeconds(10)
            do{[Threading.Thread]::Sleep(50);$pending=Read-KanalRecord $ctx $r.Id}while(-not $pending.PendingApprovals.Count -and [datetime]::UtcNow -lt $until)
            $pending.PendingApprovals[0].id|Should Be 'fixture-permission'
            $answer=Send-KanalBridge $ctx $r.Id 'onay' -RequestId 'fixture-permission' -Decision 'decline';$answer.decided|Should Be $true
            do{[Threading.Thread]::Sleep(50);$done=Read-KanalRecord $ctx $r.Id}while($done.Status -eq 'running' -and [datetime]::UtcNow -lt $until)
            $done.Answer|Should Match 'permission deny'
            (Close-KanalWorker $ctx $r.Id).Status|Should Be 'closed'
        }finally{try{Close-KanalWorker $ctx $r.Id|Out-Null}catch{}}
    }
    It 'opens, sends two turns and closes the exact owned job' {
        Mock Get-KanalCapacity { @{onerilen=8} }
        Mock Get-KanalTeamCount { 0 }
        $ctx=New-KanalContext $repo;$ctx.State=Join-Path $TestDrive 'bridge';$ctx.Timeout=20
        $ctx.BridgeLaunch=@{command=(Get-Command node.exe).Source;args=@((Join-Path $PSScriptRoot 'fixtures/app-server.mjs'))}
        $r=Open-KanalBridge $ctx $TestDrive
        try{
            $r.Status | Should Be 'ready'
            $a=Send-KanalBridge $ctx $r.Id 'sor' 'first'
            $b=Send-KanalBridge $ctx $r.Id 'sor' 'second'
            $a.Status | Should Be 'completed';$b.Turn | Should Be 2
            $b.SessionId | Should Be $a.SessionId
            (Close-KanalWorker $ctx $r.Id).Status | Should Be 'closed'
        }finally{try{Close-KanalWorker $ctx $r.Id|Out-Null}catch{}}
    }
}
