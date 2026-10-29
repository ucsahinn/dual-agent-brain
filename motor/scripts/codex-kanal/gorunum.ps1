# Read-only history policy shared by channel CLI and merkez. No model calls.
function Test-KanalHistoryOwner($Record,[string]$Vault='') {
    foreach ($pair in @(@('Pid','ProcessStart'),@('HostPid','HostStart'),@('RootPid','RootStart'))) {
        $number=$Record.($pair[0]);$stamp=$Record.($pair[1])
        if (-not $number) { continue }
        try {
            $process=Get-Process -Id ([int]$number) -ErrorAction SilentlyContinue
            # A live PID without a usable stamp is uncertain: preserve the record.
            if ($process -and (-not $stamp -or [math]::Abs(($process.StartTime.ToUniversalTime()-[datetime]::Parse($stamp).ToUniversalTime()).TotalSeconds) -lt 1)) { return $true }
        } catch { return $true }
    }
    if ($Record.OwnerSession -match '^(?:agent|process):(\d+):(\d+)$') {
        try {
            $process=Get-Process -Id ([int]$Matches[1]) -ErrorAction SilentlyContinue
            if ($process -and $process.StartTime.ToUniversalTime().Ticks -eq [long]$Matches[2]) { return $true }
        } catch { return $true }
    } elseif ($Vault -and $Record.OwnerSession -and (Get-Command Get-BeyinSessionState -ErrorAction SilentlyContinue)) {
        try {
            $session=Get-BeyinSessionState -Paths (Get-BeyinPaths -Vault $Vault) -SessionId ([string]$Record.OwnerSession)
            if ($session.pid -and $session.start) {
                $process=Get-Process -Id ([int]$session.pid) -ErrorAction SilentlyContinue
                $began=[datetimeoffset]::FromUnixTimeSeconds([long]$session.start).UtcDateTime
                if ($process -and $process.StartTime.ToUniversalTime() -le $began.AddSeconds(5)) { return $true }
            }
        } catch { return $true }
    }
    return $false
}
function Test-KanalHistoryTerminal($Record) {
    return $Record.Status -in @('closed','completed','failed','invalid-handoff','interrupted','stalled','disconnected','canceled','cancelled')
}
function Test-KanalHistoryVisible($Record,[int]$RecentHours=24,[datetime]$Now=[datetime]::UtcNow,[string]$Vault='') {
    if ($Record.ArchivedAt) { return $false }
    if (-not (Test-KanalHistoryTerminal $Record) -or (Test-KanalHistoryOwner $Record $Vault)) { return $true }
    foreach ($name in @('Finished','Started','Created')) {
        if (-not $Record.$name) { continue }
        try { return [datetime]::Parse($Record.$name).ToUniversalTime() -ge $Now.ToUniversalTime().AddHours(-$RecentHours) } catch { return $true }
    }
    return $true # No trustworthy date: never silently archive.
}
function Archive-KanalRecords($Context,[int]$RecentHours=24,[switch]$Apply) {
    $gate=Open-KanalLock (Join-Path $Context.State 'admission.lock')
    try {
        foreach ($record in @(Get-KanalRecords $Context -Hepsi)) {
            if ($record.ArchivedAt -or -not (Test-KanalHistoryTerminal $record) -or (Test-KanalHistoryOwner $record $Context.Vault) -or (Test-KanalHistoryVisible $record $RecentHours)) { continue }
            # Share the worker's exclusive lock; never race an active exec writer.
            $workerLock=$null
            try {
                $workerLock=Open-KanalLock (Join-Path $Context.State ($record.Id+'.lock'))
                $fresh=Read-KanalRecord $Context $record.Id
                if (-not (Test-KanalHistoryTerminal $fresh) -or (Test-KanalHistoryOwner $fresh $Context.Vault)) { continue }
                if ($Apply) {
                    $fresh | Add-Member -NotePropertyName ArchivedAt -NotePropertyValue ([datetime]::UtcNow.ToString('o')) -Force
                    Save-KanalRecord $Context $fresh
                }
                [pscustomobject]@{Id=$record.Id;Status=$record.Status;Reason="closed more than $RecentHours hours ago";Applied=[bool]$Apply}
            } catch { if ($workerLock) { throw } } finally { if ($workerLock) { $workerLock.Dispose() } }
        }
    } finally { $gate.Dispose() }
}
