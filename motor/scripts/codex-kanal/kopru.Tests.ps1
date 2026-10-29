$repo=Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
. (Join-Path $repo 'motor/hooks/lib.ps1')
. (Join-Path $PSScriptRoot 'core.ps1')
. (Join-Path $PSScriptRoot 'kopru.ps1')
function New-KopruFixtureContext([string]$Name,[string]$Engine='codex') {
    # State overrides alone do not isolate admission: it also scans Vault's
    # codex/claude roots. Give every fixture its own complete runtime namespace.
    $fixture=Join-Path $TestDrive $Name
    New-Item -ItemType Directory -Force (Join-Path $fixture 'motor/hooks') | Out-Null
    Copy-Item -LiteralPath (Join-Path $repo 'motor/hooks/lib.ps1') -Destination (Join-Path $fixture 'motor/hooks/lib.ps1')
    $context=New-KanalContext $fixture
    $context.Engine=$Engine
    $context.State=Join-Path $fixture ('motor/scripts/.state/'+$Engine+'-kanal')
    $context.Entry=Join-Path $repo ('motor/scripts/'+$Engine+'-kanal.ps1')
    $context.Timeout=20
    $context.SetupLockOptions=@{holdMs=100;waitMs=3000;name=('Local\Beyin-fixture-'+[guid]::NewGuid().ToString('N'))}
    return $context
}
Describe 'Persistent channel with a fake app-server process' {
    BeforeEach {
        # Any read of the user's runtime state is a test isolation failure.
        Mock Get-KanalRecords { throw 'Unrelated real-vault state was scanned' } -ParameterFilter { $Context.Vault -eq $repo }
    }
    It 'keeps schema notices inside JSON rather than the warning stream' {
        Mock Get-KanalCapacity { @{onerilen=8} };Mock Get-KanalTeamCount { 0 }
        $ctx=New-KopruFixtureContext 'schema-json'
        $script:SchemaFixture=Join-Path $PSScriptRoot 'fixtures/app-server.mjs'
        Mock Resolve-KanalLaunch { @{command=(Get-Command node.exe).Source;args=@($script:SchemaFixture)} }
        Mock Set-KanalCodexRecord {}
        Mock Get-KanalSchemaStatus { @{Changed=$true;Generated=$false;Notice='Schema checks the exact selected executable fixture'} }
        Mock New-KanalMcpProfile { @{Path='';Enabled=@();Disabled=@();Arguments=@()} }
        Mock Get-KanalProfiles { @() }
        $r=$null
        try {
            $output=@(Open-KanalBridge $ctx $TestDrive 3>&1)
            $output.Count | Should Be 1
            $r=$output[0]
            $json=$output | ConvertTo-Json -Depth 12
            $decoded=$json | ConvertFrom-Json
            $decoded.Warnings[0] | Should Match 'Schema checks'
        } finally {if($r -and $r.Id){try{Close-KanalWorker $ctx $r.Id|Out-Null}catch{}}}
    }
    It 'admits a fixture worker without reading unrelated real-vault channel states' {
        Mock Get-KanalCapacity { @{onerilen=8} };Mock Get-KanalTeamCount { 0 }
        $ctx=New-KopruFixtureContext 'isolated-admission'
        $ctx.BridgeLaunch=@{command=(Get-Command node.exe).Source;args=@((Join-Path $PSScriptRoot 'fixtures/app-server.mjs'))}
        $r=$null
        try { $r=Open-KanalBridge $ctx $TestDrive; $r.Status | Should Be ready }
        finally { if($r){$null=Close-KanalWorker $ctx $r.Id} }
    }
    It 'rejects the same active task on another ready worker before delivery' {
        Mock Get-KanalCapacity { @{onerilen=8} };Mock Get-KanalTeamCount { 0 }
        $ctx=New-KopruFixtureContext 'claims-bridge'
        $ctx.BridgeLaunch=@{command=(Get-Command node.exe).Source;args=@((Join-Path $PSScriptRoot 'fixtures/app-server.mjs'))}
        $ctx.SetupLockOptions=@{holdMs=100;waitMs=3000;name=('Local\Beyin-fixture-'+[guid]::NewGuid().ToString('N'))}
        $a=$null;$b=$null
        try{$a=Open-KanalBridge $ctx $TestDrive;$b=Open-KanalBridge $ctx $TestDrive
            $null=Send-KanalBridge $ctx $a.Id 'sor' 'wait' -Background
            {Send-KanalBridge $ctx $b.Id 'sor' 'wait' -Background}|Should Throw 'Task already claimed'
        }finally{foreach($r in @($a,$b)){try{Close-KanalWorker $ctx $r.Id|Out-Null}catch{}}}
    }
    It 'derives each plain-text claim from its message despite an old shared TaskKey' {
        Mock Get-KanalCapacity { @{onerilen=8} };Mock Get-KanalTeamCount { 0 }
        $ctx=New-KopruFixtureContext 'distinct-claims'
        $ctx.BridgeLaunch=@{command=(Get-Command node.exe).Source;args=@((Join-Path $PSScriptRoot 'fixtures/app-server.mjs'))}
        $a=$null;$b=$null
        try {
            $a=Open-KanalBridge $ctx $TestDrive;$b=Open-KanalBridge $ctx $TestDrive
            foreach($r in @($a,$b)){$r|Add-Member TaskKey (Get-KanalHash 'old empty prompt');Save-KanalRecord $ctx $r}
            $null=Send-KanalBridge $ctx $a.Id 'sor' 'wait' -Background
            (Send-KanalBridge $ctx $b.Id 'sor' 'different task').Status | Should Be completed
        } finally {foreach($r in @($a,$b)){if($r){try{Close-KanalWorker $ctx $r.Id|Out-Null}catch{}}}}
    }
    It 'blocks different messages that request the same write scope' {
        Mock Get-KanalCapacity { @{onerilen=8} };Mock Get-KanalTeamCount { 0 }
        $ctx=New-KopruFixtureContext 'scope-claims'
        $ctx.BridgeLaunch=@{command=(Get-Command node.exe).Source;args=@((Join-Path $PSScriptRoot 'fixtures/app-server.mjs'))}
        $a=$null;$b=$null
        try {
            $a=Open-KanalBridge $ctx $TestDrive;$b=Open-KanalBridge $ctx $TestDrive
            $null=Send-KanalBridge $ctx $a.Id 'sor' "Goal: hold-claim`nWrite scope: src/a`nBoundaries: local" -Background
            {Send-KanalBridge $ctx $b.Id 'sor' "Goal: other`nWrite scope: SRC\A`nBoundaries: local" -Background}|Should Throw 'Task already claimed'
        } finally {foreach($r in @($a,$b)){if($r){try{Close-KanalWorker $ctx $r.Id|Out-Null}catch{}}}}
    }
    It 'routes the Claude wrapper through one owned persistent stream process' {
        Mock Get-KanalCapacity { @{onerilen=8} };Mock Get-KanalTeamCount { 0 }
        $ctx=New-KopruFixtureContext 'claude-bridge' 'claude'
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
        $ctx=New-KopruFixtureContext 'bridge'
        $ctx.BridgeLaunch=@{command=(Get-Command node.exe).Source;args=@((Join-Path $PSScriptRoot 'fixtures/app-server.mjs'))}
        $r=Open-KanalBridge $ctx $TestDrive
        try{
            $r.Status | Should Be 'ready'
            $a=Send-KanalBridge $ctx $r.Id 'sor' 'first'
            (Read-KanalRecord $ctx $r.Id).ClaimKey | Should BeNullOrEmpty
            $b=Send-KanalBridge $ctx $r.Id 'sor' 'second'
            $a.Status | Should Be 'completed';$b.Turn | Should Be 2
            $b.SessionId | Should Be $a.SessionId
            (Close-KanalWorker $ctx $r.Id).Status | Should Be 'closed'
        }finally{try{Close-KanalWorker $ctx $r.Id|Out-Null}catch{}}
    }
}
