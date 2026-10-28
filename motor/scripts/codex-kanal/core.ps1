# Channel-owned exec sessions only. JSONL stays in memory; durable data is redacted.
. (Join-Path $PSScriptRoot 'surec.ps1')
. (Join-Path $PSScriptRoot 'teslim.ps1')
. (Join-Path $PSScriptRoot 'profil.ps1')
. (Join-Path $PSScriptRoot 'ikili.ps1')
. (Join-Path $PSScriptRoot 'setup-lock.ps1')
function New-KanalContext([string]$Vault) {
    return @{ Vault = $Vault; State = (Join-Path $Vault 'motor/scripts/.state/codex-kanal');
        Codex = ''; Entry = (Join-Path $Vault 'motor/scripts/codex-kanal.ps1'); Timeout = 900 }
}
function Resolve-KanalEngine([string]$Value,[string]$Planned='') {
    if(-not $Value){$Value=$Planned}
    if($Value -cin @('codex','claude')){return $Value};return $null
}
function Resolve-KanalBackend([string]$Value) {
    if($Value -cin @('exec','app-server','claude-stream')){return $Value};return $null
}
function Get-KanalWorkerExit([int]$Code,[string]$Engine) {
    $signal=$(if($Code -gt 128 -and $Code -le 192){$Code-128}else{$null})
    return @{Kind=$(if($signal){'signal'}elseif($Code -eq 0){'normal'}else{'fault'});Signal=$signal;Fault=($Code -ne 0 -and -not $signal);Engine=(Resolve-KanalEngine $Engine)}
}
function Get-KanalProfiles($Context) {
    $profiles=@($Context.CodexProfiles)
    if($Context.CodexProfileFile){
        if((Get-Item -LiteralPath $Context.CodexProfileFile).Length -gt 65536){throw 'Channel profile file exceeds 64 KiB'}
        $profiles=@([IO.File]::ReadAllText($Context.CodexProfileFile)|ConvertFrom-Json)
    }
    if(-not @($profiles|Where-Object {$_}).Count -and ($Context.CodexHome -or $Context.CodexProfile)){$profiles=@(@{name='selected';home=$Context.CodexHome;profile=$Context.CodexProfile})}
    if($profiles.Count -gt 8){throw 'At most eight preconfigured channel profiles'}
    $names=@()
    foreach($p in $profiles){
        if(-not $p){continue}
        if($p.name -cnotmatch '^[A-Za-z0-9_-]{1,64}$' -or $p.name -in $names){throw 'Unique literal channel profile name required'}
        $names+=$p.name
        if($p.profile -and $p.profile -cnotmatch '^[A-Za-z0-9_-]{1,64}$'){throw 'Invalid Codex profile name'}
        $homePath=''
        if($p.home){if(-not (Test-Path -LiteralPath $p.home -PathType Container)){throw 'CODEX_HOME must already exist; account setup is an operator action'};$homePath=(Resolve-Path -LiteralPath $p.home).ProviderPath}
        @{name=[string]$p.name;home=$homePath;profile=[string]$p.profile}
    }
}
function Protect-KanalText($Context, [string]$Text) {
    $r = Protect-BeyinSecrets -Text $Text
    if ($r.Failed) { throw 'Secret filter failed; data was not persisted' }
    return [string]$r.Text
}
function Test-KanalBrief([string]$Text) {
    return Test-KanalFields $Text @('Goal','Evidence','Write scope','Boundaries','Done when','Return format',"User's words")
}
function New-KanalBrief([string]$Text, [string]$Project) {
    if (Test-KanalBrief $Text) { return $Text }
    return @"
Goal:
$Text

Evidence:
Project directory: $Project. Inspect current files before making claims.

Write scope:
Only changes explicitly requested in the user's words within the project. If no file changes are requested, read-only.

Boundaries:
You are not alone in the codebase. Preserve others' work. Never spawn agents. No commits, pushes, installs, credentials, account/database writes, publish or deploy without explicit approval. Never print secrets or inspect auth files. Follow the project's instructions and the user's narrower scope.

Done when:
The requested result is supported by bounded local evidence, or the exact blocker and remaining check are reported. Never claim an unperformed check passed.

Return format:
Exactly six labeled fields in order: Outcome, Evidence, Changed scope, Risks, Open questions, Next verification. Use none for an empty field.

User's words:
$Text
"@
}
function Get-KanalChefRoot {
    # Resolve existing installation pointers read-only; never refresh ~/.beyin caches.
    $candidates = @([string](Get-BeyinAyar 'BEYIN_AGENTCHEF_KOK' ''), [string]$env:AGENTCHEF_ROOT)
    $cache = Join-Path $env:USERPROFILE '.beyin/agentchef-kok.txt'
    if (Test-Path -LiteralPath $cache -PathType Leaf) { $candidates += [IO.File]::ReadAllText($cache).Trim() }
    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath (Join-Path $candidate 'plugins/agentchef/agents') -PathType Container)) { return $candidate }
    }
    return ''
}
function Resolve-KanalRole($Context, [string]$Role) {
    if (-not $Role) { return @{ Name = ''; Text = ''; Model = ''; Sandbox = 'workspace-write' } }
    $name = ($Role -replace '^agentchef:', '') -replace '_', '-'
    if ($name -cnotmatch '^[a-z][a-z0-9-]*$') { throw 'Invalid AgentChef role' }
    $chef = Get-KanalChefRoot
    if (-not $chef) { throw 'Installed AgentChef catalog not found' }
    $codexName = $name.Replace('-', '_')
    $path = Join-Path $chef "templates/codex/agents/$codexName.toml"
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "AgentChef role not found: $name" }
    $text = [IO.File]::ReadAllText($path)
    $instructions = [regex]::Match($text, '(?ms)^developer_instructions[ \t]*=[ \t]*"""\r?\n(.*?)^"""')
    $model = [regex]::Match($text, '(?m)^model[ \t]*=[ \t]*"([a-zA-Z0-9._-]+)"').Groups[1].Value
    $sandbox = [regex]::Match($text, '(?m)^sandbox_mode[ \t]*=[ \t]*"(read-only|workspace-write)"').Groups[1].Value
    if (-not $instructions.Success -or -not $model) { throw "Unsupported or incomplete Codex role definition: $name" }
    if (-not $sandbox) { $sandbox = 'workspace-write' }
    return @{ Name = $name; Text = $instructions.Groups[1].Value; Model = $model; Sandbox = $sandbox }
}
function Get-KanalCapacity($Context) {
    $k = Get-BeyinKaynakOzeti -Paths (Get-BeyinPaths -Vault $Context.Vault) -OnbellekDk 0
    if (-not $k.Ok) { throw 'Live capacity could not be measured' }
    return Get-BeyinKapasiteKayit $k
}
function Get-KanalTeamCount($Context) {
    $p = Get-BeyinPaths -Vault $Context.Vault
    $count = 0
    if (Test-Path -LiteralPath $p.TeamRuns) {
        foreach ($f in Get-ChildItem -LiteralPath $p.TeamRuns -Filter '*.json' -File) {
            $run = [IO.File]::ReadAllText($f.FullName) | ConvertFrom-Json
            $count += @($run.workers | Where-Object { $_.status -in @('queued','spawning','running') }).Count
        }
    }
    return $count
}
function Get-KanalRecordPath($Context, [string]$Id) {
    if ($Id -cnotmatch '^CK-[a-f0-9]{32}$') { throw 'Session is not channel-owned; use aktar for TUI sessions' }
    return Join-Path $Context.State ($Id + '.json')
}
function Read-KanalRecord($Context, [string]$Id) {
    $path = Get-KanalRecordPath $Context $Id
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw 'Session is not channel-owned' }
    # Atomic replacement must remain possible while a status reader holds the old inode.
    for ($attempt = 0; ; $attempt++) {
        try {
            $stream = [IO.File]::Open($path, 'Open', 'Read', ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
            $reader = New-Object IO.StreamReader $stream
            try { $r = $reader.ReadToEnd() | ConvertFrom-Json } finally { $reader.Dispose() }
            break
        } catch [IO.IOException] {
            if ($attempt -ge 19) { throw }
            # Windows Replace may briefly expose a sharing/delete-pending window.
            [Threading.Thread]::Sleep(25)
        }
    }
    if ($r.Owner -ne 'beyin-codex-kanal-v1' -or $r.Id -ne $Id) { throw 'Invalid channel ownership' }
    return $r
}
function Save-KanalRecord($Context, $Record) {
    if($Record.PSObject.Properties['Engine'] -and $Record.Engine -and -not (Resolve-KanalEngine $Record.Engine)){$Record.Engine=$null;$Record|Add-Member -NotePropertyName EngineStatus -NotePropertyValue 'unknown' -Force}
    if($Record.PSObject.Properties['Backend'] -and $Record.Backend -and -not (Resolve-KanalBackend $Record.Backend)){$Record.Backend=$null;$Record|Add-Member -NotePropertyName BackendStatus -NotePropertyValue 'unknown' -Force}
    $path = Get-KanalRecordPath $Context $Record.Id
    $text = Protect-KanalText $Context ($Record | ConvertTo-Json -Depth 12)
    $tmp = $path + '.tmp-' + [guid]::NewGuid().ToString('N')
    [IO.File]::WriteAllText($tmp, $text, (New-Object Text.UTF8Encoding $false))
    if (Test-Path -LiteralPath $path) {
        $backup = $tmp + '.bak'
        [IO.File]::Replace($tmp, $path, $backup)
        [IO.File]::Delete($backup)
    }
    else { [IO.File]::Move($tmp, $path) }
    Sync-BeyinChannelRecordEvidence -Paths (Get-BeyinPaths -Vault $Context.Vault) -Record $Record
}
function Get-KanalRecords($Context) {
    if (-not (Test-Path -LiteralPath $Context.State)) { return }
    foreach ($file in Get-ChildItem -LiteralPath $Context.State -Filter 'CK-*.json' -File) {
        $r = Read-KanalRecord $Context $file.BaseName
        if ($r.Status -in @('queued','running')) {
            $alive = Get-Process -Id $r.Pid -ErrorAction SilentlyContinue
            if (-not $alive -or [math]::Abs(($alive.StartTime.ToUniversalTime() - [datetime]::Parse($r.ProcessStart).ToUniversalTime()).TotalSeconds) -gt 1) {
                $r.Status = 'interrupted'; $r.Error = 'Owner process ended; outcome unknown. No automatic retry.'
            } else {
                $r.DurationSeconds = $(if($r.Started){[math]::Round(([datetime]::UtcNow - [datetime]::Parse($r.Started).ToUniversalTime()).TotalSeconds,2)}else{0})
            }
        }
        $r
    }
}
function Open-KanalLock([string]$Path) {
    try { return [IO.File]::Open($Path, 'OpenOrCreate', 'ReadWrite', 'None') }
    catch { throw 'Channel busy: concurrent admission or turn; retry after the current call' }
}
function Quote-KanalLiteral([string]$Value) { return "'" + $Value.Replace("'", "''") + "'" }
function Start-KanalPowerShell([string]$Code, [string]$Directory, [string]$JobName = '') {
    Initialize-KanalJob
    if(-not $JobName){$JobName='Local\Beyin-helper-'+[guid]::NewGuid().ToString('N')}
    $job=New-Object BeyinChannelJob $JobName
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = Join-Path $PSHOME 'powershell.exe'
    # The child cannot start descendants before the host assigns its job.
    $Code = '[Console]::InputEncoding = New-Object Text.UTF8Encoding $false; $null = [Console]::In.Peek(); ' + $Code
    $info.Arguments = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand ' + [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($Code))
    $info.WorkingDirectory = $Directory
    $info.UseShellExecute = $false; $info.CreateNoWindow = $true
    $info.RedirectStandardInput = $true; $info.RedirectStandardOutput = $true; $info.RedirectStandardError = $true
    $info.StandardOutputEncoding = New-Object Text.UTF8Encoding $false
    $info.StandardErrorEncoding = New-Object Text.UTF8Encoding $false
    $proc = New-Object Diagnostics.Process
    $proc.StartInfo = $info
    # .NET Framework constructs StandardInput with Console.InputEncoding during
    # Start and AutoFlush can emit its BOM before BaseStream.Write is reached.
    $previousInput=[Console]::InputEncoding
    try {
        try{[Console]::InputEncoding=New-Object Text.UTF8Encoding $false;[void]$proc.Start()}finally{[Console]::InputEncoding=$previousInput}
        $job.Assign($proc)
    } catch { $job.Dispose(); if($proc.Id -and -not $proc.HasExited){$proc.Kill()}; $proc.Dispose(); throw }
    $proc | Add-Member -NotePropertyName ChannelJob -NotePropertyValue $job
    return $proc
}
function Invoke-KanalProcess($Context, $Record) {
    if($Record.CodexLaunch){$launch=$Record.CodexLaunch}else{$launch=Resolve-KanalCodex $Context;Set-KanalCodexRecord $Context $Record $launch;Save-KanalRecord $Context $Record}
    $exe=$launch.command
    $argv = @($launch.args)+@('exec','--output-schema',(Join-Path $PSScriptRoot 'handoff.schema.json'),'-c',('sandbox_mode="' + $Record.Sandbox + '"'),'-c','approval_policy="on-request"',
        '-c','approvals_reviewer="auto_review"','-c','mcp_servers.node_repl.enabled=false')
    $windows=$(if($Record.WindowsSandbox){$Record.WindowsSandbox}else{'elevated'})
    if($windows -notin @('elevated','unelevated')){throw 'Invalid Windows sandbox profile'}
    $argv+=@('-c',('windows.sandbox="'+$windows+'"'))
    $profile=New-KanalMcpProfile $Context $Record.Role (Join-Path $Context.State $Record.Id)
    $argv+=@($profile.Arguments)
    if ($Record.RoleModel) { $argv += @('-m', $Record.RoleModel) }
    if ($Record.SessionId) { $argv += @('resume', $Record.SessionId) }
    else { $argv += @('-C', $Record.Project, '-s', $Record.Sandbox) }
    $argv += @('--skip-git-repo-check','--json','-')
    $quoted = @($argv | ForEach-Object { Quote-KanalLiteral $_ }) -join ','
    $code = '[Console]::OutputEncoding = New-Object Text.UTF8Encoding $false; $OutputEncoding = [Console]::OutputEncoding; ' +
        '$p = [Console]::In.ReadToEnd(); $a = @(' + $quoted + '); $p | & ' + (Quote-KanalLiteral $exe) + ' @a; exit $LASTEXITCODE'
    $setupLock=Open-KanalSetupLock
    $Record|Add-Member -NotePropertyName SetupLock -NotePropertyValue @{Name='Local\Beyin-codex-setup';AcquiredAt=[datetime]::UtcNow.ToString('o');MaxHoldSeconds=60} -Force
    $setupWatch=[Diagnostics.Stopwatch]::StartNew()
    try{$proc = Start-KanalPowerShell $code $Record.Project -JobName ('Local\Beyin-'+$Record.Id)}catch{Close-KanalSetupLock $setupLock $Record 'launch-failed';throw}
    try{Register-KanalProcess $Context $Record $proc}catch{Close-KanalSetupLock $setupLock $Record 'registration-failed';Close-KanalPowerShell $proc;throw}
    $stderrTask = $proc.StandardError.ReadToEndAsync() # only a redacted tail is persisted on failure
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $session = [string]$Record.SessionId; $answer = ''; $complete = $false; $failed = $false; $setupFailed = $false; $setupToolFailed=$false; $successfulItems=0
    try {
        # Windows PowerShell's .NET Framework writer emits a UTF-8 BOM.
        # Write bytes directly so the exact hashed prompt reaches the CLI.
        $bytes=(New-Object Text.UTF8Encoding $false).GetBytes($Record.Prompt)
        $proc.StandardInput.BaseStream.Write($bytes,0,$bytes.Length);$proc.StandardInput.BaseStream.Close()
        $pending = $proc.StandardOutput.ReadLineAsync()
        while ($true) {
            if($setupLock -and $setupWatch.Elapsed.TotalSeconds -ge 60){Close-KanalSetupLock $setupLock $Record 'deadline';$setupLock=$null}
            if ($watch.Elapsed.TotalSeconds -gt $Context.Timeout) { throw 'Codex turn timed out' }
            if (-not $pending.Wait(200)) { continue }
            $line = $pending.Result
            if ($null -eq $line) { break }
            try { $event = $line | ConvertFrom-Json -ErrorAction Stop } catch { throw 'Invalid Codex JSONL event' }
            if($setupLock -and $event.type -in @('item.started','item.completed') -and $event.item.type -in @('command_execution','agent_message')){Close-KanalSetupLock $setupLock $Record 'first-command-or-agent';$setupLock=$null}
            if(Test-KanalToolSetupFailure $event){$setupFailed=$true;$setupToolFailed=$true}
            if($event.type -eq 'item.completed' -and (($event.item.type -eq 'command_execution' -and $null -ne $event.item.exit_code -and $event.item.exit_code -eq 0) -or $event.item.type -eq 'file_change')){$successfulItems++}
            if ($event.type -eq 'thread.started') {
                if ([string]$event.thread_id -notmatch '^[a-f0-9-]{36}$') { throw 'Invalid Codex session id' }
                if ($session -and $session -ne [string]$event.thread_id) { throw 'Resume returned a different session' }
                $session = [string]$event.thread_id
                $Record.SessionId = $session; Save-KanalRecord $Context $Record
            }
            if ($event.type -eq 'item.completed' -and $event.item.type -eq 'agent_message') { $answer = [string]$event.item.text }
            if ($event.type -eq 'turn.completed') { $complete = $true }
            if ($event.type -match 'error|warn' -or $event.type -eq 'turn.failed' -or ($event.type -eq 'item.completed' -and ($event.item.status -eq 'failed' -or ($null -ne $event.item.exit_code -and $event.item.exit_code -ne 0)))) {
                $message=Protect-KanalText $Context ($event|ConvertTo-Json -Compress -Depth 15)
                if($message.Length -gt 8192){$message=$message.Substring($message.Length-8192)}
                $Record.Error=($Record.Error+"`n"+$message).Trim();if($Record.Error.Length -gt 16384){$Record.Error=$Record.Error.Substring($Record.Error.Length-16384)}
                $entry=@{type=$event.type;message=$message;at=[datetime]::UtcNow.ToString('o')}|ConvertTo-Json -Compress
                [IO.File]::AppendAllText((Join-Path (Join-Path $Context.State $Record.Id) 'events.jsonl'),($entry+"`n"),(New-Object Text.UTF8Encoding $false))
                if($message -match 'setup refresh had errors'){$setupFailed=$true}
            }
            $pending = $proc.StandardOutput.ReadLineAsync()
        }
        $remaining = [int][math]::Max(1, ($Context.Timeout - $watch.Elapsed.TotalSeconds) * 1000)
        if (-not $proc.WaitForExit($remaining)) { throw 'Codex turn timed out' }
        $valid=$complete -and $session -and $answer -and (Test-KanalHandoff (ConvertFrom-KanalHandoffJson $answer))
        $Record|Add-Member -NotePropertyName WorkerExit -NotePropertyValue (Get-KanalWorkerExit $proc.ExitCode (Resolve-KanalEngine $Record.Engine 'codex')) -Force
        if($Record.WorkerExit.Kind -eq 'signal'){$failure=New-Object Exception 'Worker interrupted by signal';$failure.Data['KanalSignal']=$true;throw $failure}
        if (-not $valid) {
            [void]$stderrTask.Wait(1000)
            $tail=$(if($stderrTask.IsCompleted){Protect-KanalText $Context $stderrTask.Result}else{''})
            if($tail.Length -gt 8192){$tail=$tail.Substring($tail.Length-8192)}
            $Record|Add-Member -NotePropertyName StderrTail -NotePropertyValue $tail -Force
            $Record.Error=($Record.Error+"`n"+$tail).Trim()
            if($setupFailed -or $tail -match 'setup refresh had errors'){$failure=New-KanalSetupFailure;if($successfulItems){$failure.Data['UnsafeRetry']=$true};throw $failure}
            throw "Codex failed or returned an incomplete turn (exit $($proc.ExitCode)); raw diagnostics withheld"
        }
        [void]$stderrTask.Wait(1000)
        $warningTail=$(if($stderrTask.IsCompleted){Protect-KanalText $Context $stderrTask.Result}else{''})
        if($warningTail.Length -gt 8192){$warningTail=$warningTail.Substring($warningTail.Length-8192)}
        if($Record.Error -or $warningTail){$Record|Add-Member -NotePropertyName Warnings -NotePropertyValue (@($Record.Warnings)+@(($Record.Error+"`n"+$warningTail).Trim())) -Force;$Record.Error=''}
        return @{ SessionId = $session; Answer = (Protect-KanalText $Context (ConvertFrom-KanalHandoffJson $answer)) }
    } catch {
        $original=$_.Exception
        # Finish this owned tree before draining failure diagnostics (also timeout
        # or invalid JSON). Never wait on a still-live stderr pipe indefinitely.
        $proc.ChannelJob.Dispose();[void]$stderrTask.Wait(1000)
        if($stderrTask.Status -eq 'RanToCompletion'){
            $tail=Protect-KanalText $Context $stderrTask.Result;if($tail.Length -gt 8192){$tail=$tail.Substring($tail.Length-8192)};$Record|Add-Member -NotePropertyName StderrTail -NotePropertyValue $tail -Force
            if($tail -match 'setup refresh had errors' -and -not $original.Data['KanalSetupFailure']){$failure=New-KanalSetupFailure;if($successfulItems){$failure.Data['UnsafeRetry']=$true};$Record.Error=($Record.Error+"`n"+$original.Message).Trim();throw $failure}
        }
        throw
    } finally {
        Close-KanalSetupLock $setupLock $Record 'attempt-ended'
        Close-KanalPowerShell $proc
        if(Test-Path -LiteralPath $profile.Path){[IO.File]::Delete($profile.Path)}
    }
}
function Test-KanalHandoff([string]$Text) {
    return Test-KanalFields $Text @('Outcome','Evidence','Changed scope','Risks','Open questions','Next verification')
}
function Test-KanalFields([string]$Text, [string[]]$Labels) {
    $alternatives = @($Labels | ForEach-Object { [regex]::Escape($_) }) -join '|'
    $headers = [regex]::Matches($Text, ('(?im)^[ \t]*(?:#{1,6}[ \t]+)?(?:\*\*)?(' + $alternatives + ')(?:\*\*)?(?:[ \t]*:[ \t]*(?:\*\*)?[ \t]*(.*)|[ \t]*)\r?$'))
    if ($headers.Count -ne $Labels.Count) { return $false }
    for ($i = 0; $i -lt $Labels.Count; $i++) {
        $m = $headers[$i]
        if ($m.Groups[1].Value -ne $labels[$i]) { return $false }
        $end = $(if ($i -lt $Labels.Count - 1) { $headers[$i+1].Index } else { $Text.Length })
        $body = $m.Groups[2].Value + $Text.Substring($m.Index + $m.Length, $end - $m.Index - $m.Length)
        if (-not $body.Trim()) { return $false }
    }
    return $true
}
function Test-KanalCatalogHandoff($Context, $Record) {
    if (-not (Test-KanalHandoff $Record.Answer)) { return $false }
    $chef = Get-KanalChefRoot
    $node = Get-Command node.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $chef -or -not $node) { $Record.HandoffCheck = 'local-six-fields'; return $true }
    $checker = Join-Path $chef 'scripts/coordination-board.mjs'
    if (-not (Test-Path -LiteralPath $checker -PathType Leaf)) { $Record.HandoffCheck = 'local-six-fields'; return $true }
    $file = Join-Path $Context.State ($Record.Id + '.handoff.md')
    [IO.File]::WriteAllText($file, (Protect-KanalText $Context $Record.Answer), (New-Object Text.UTF8Encoding $false))
    $code = '& ' + (Quote-KanalLiteral $node.Source) + ' ' + (Quote-KanalLiteral $checker) +
        ' handoff-check --handoff-file ' + (Quote-KanalLiteral $file) + ' --json; exit $LASTEXITCODE'
    $p = Start-KanalPowerShell $code $Context.Vault
    try {
        $p.StandardInput.Close(); $output = $p.StandardOutput.ReadToEndAsync(); $errors = $p.StandardError.ReadToEndAsync()
        if (-not $p.WaitForExit(15000)) { $p.Kill(); $Record.HandoffCheck = 'checker-timeout'; return $false }
        $check = $output.Result | ConvertFrom-Json
        $Record.HandoffCheck = "AgentChef handoff-check (exit $($p.ExitCode); missing $(@($check.missing) -join ', '))"
        return ($p.ExitCode -eq 0 -and $check.ok)
    } finally { Close-KanalPowerShell $p }
}
function Complete-KanalTurn($Context, $Record) {
    $watch = [Diagnostics.Stopwatch]::StartNew()
    # Add fields also when resuming a record produced by an older channel version.
    $Record | Add-Member -NotePropertyName Attempts -NotePropertyValue 0 -Force
    $Record | Add-Member -NotePropertyName RetryCount -NotePropertyValue 0 -Force
    if (-not $Record.PSObject.Properties['RetryEvents']) { $Record | Add-Member -NotePropertyName RetryEvents -NotePropertyValue @() }
    $Record | Add-Member -NotePropertyName PromptHash -NotePropertyValue (Get-KanalHash $Record.Prompt) -Force
    $claim=$null
    $setupRetries=0
    $Record.Status = 'running'; Save-KanalRecord $Context $Record
    try {
        $key=$(if($Record.TaskKey){$Record.TaskKey}else{$Record.Project+'|'+$Record.PromptHash})
        $claim=Open-KanalClaim $Context $key
        while ($true) {
            $Record.Attempts++;$Record.Error='';$Record|Add-Member -NotePropertyName StderrTail -NotePropertyValue '' -Force; Save-KanalRecord $Context $Record
            try {
                $result = Invoke-KanalProcess $Context $Record
                # A validated live turn is authoritative; rollout files can lag or
                # contain historical BOM-corrupted prompts. Never replay this turn.
                $rollout=Get-KanalDelivery $Context $Record
                $Record | Add-Member -NotePropertyName Delivery -NotePropertyValue @{Status='islendi';Source='validated-live-turn';RolloutStatus=$rollout.Status;PromptHash=$Record.PromptHash} -Force
                break
            }
            catch {
                $setup=[bool]$_.Exception.Data['KanalSetupFailure']
                if (-not $setup -or $_.Exception.Data['UnsafeRetry'] -or $setupRetries -ge 2) { throw }
                $setupRetries++
                if($setupRetries -eq 2 -and $Record.WindowsSandbox -ne 'unelevated'){$Record|Add-Member -NotePropertyName SandboxFallback -NotePropertyValue @{From='elevated';To='unelevated';Attempt=($Record.Attempts+1);Reason='failed-setup-refresh';Turn=$Record.Turn;At=[datetime]::UtcNow.ToString('o');Error=$Record.Error;StderrTail=$Record.StderrTail} -Force;$Record|Add-Member -NotePropertyName WindowsSandbox -NotePropertyValue 'unelevated' -Force}
                $Record.RetryCount++
                $delay=Get-Random -Minimum 10 -Maximum 41;$reason='sandbox-setup-refresh'
                $Record.RetryEvents = @($Record.RetryEvents) + @([pscustomobject]@{
                    Turn = $Record.Turn; At = [datetime]::UtcNow.ToString('o');
                    Reason = $reason; DelaySeconds = $delay; Attempt = $Record.Attempts + 1
                })
                # Store only a fixed reason, never raw events, environment or stderr.
                Save-KanalRecord $Context $Record
                if($delay){Start-Sleep -Seconds $delay}
            }
        }
        $Record.SessionId = $result.SessionId; $Record.Answer = $result.Answer
        $Record.HandoffValid = Test-KanalCatalogHandoff $Context $Record
        $Record.Status = $(if ($Record.HandoffValid) { 'completed' } else { 'invalid-handoff' })
        $Record.Summary = ($Record.Answer -replace '\s+', ' ').Trim()
        if ($Record.Summary.Length -gt 240) { $Record.Summary = $Record.Summary.Substring(0,240) }
    } catch { $Record.Status = $(if($_.Exception.Data['KanalSignal']){'interrupted'}else{'failed'}); $Record.Error = Protect-KanalText $Context ($Record.Error+"`n"+$_.Exception.Message+"`n"+$Record.StderrTail).Trim();if($Record.Error.Length -gt 16384){$Record.Error=$Record.Error.Substring($Record.Error.Length-16384)} }
    finally {
        if($claim){$claim.Dispose()}
        $checkpointDir=Join-Path $Context.State $Record.Id
        New-Item -ItemType Directory -Force $checkpointDir|Out-Null
        [IO.File]::WriteAllText((Join-Path $checkpointDir 'notes.md'),(Protect-KanalText $Context $Record.Answer),(New-Object Text.UTF8Encoding $false))
        $Record.Prompt = ''; $Record.DurationSeconds = [math]::Round($watch.Elapsed.TotalSeconds,2)
        $Record.Finished = [datetime]::UtcNow.ToString('o'); Save-KanalRecord $Context $Record
    }
    if ($Record.Background) {
        # One fixed, non-secret completion line. No derived Markdown or curated notes are written.
        $p = Get-BeyinPaths -Vault $Context.Vault
        try {
            # The existing listener uses WaitForChanged, which can miss the final rename
            # while discarding the temporary-file event. Stage OUTSIDE its watched folder.
            $staging = $p.Clone()
            $staging.Handoff = Join-Path $Context.State 'notifications-staging'
            $n = Add-BeyinHandoff -Paths $staging -Metin "Codex kanal $($Record.Id) $($Record.Status); oku: beyin codex durum $($Record.Id)" `
                -Kime claude -FromAgent codex -Proje ([IO.Path]::GetFileName($Record.Project)) -GorunumYok
            if ($n.Ok) {
                New-Item -ItemType Directory -Force -Path $p.Handoff | Out-Null
                [IO.File]::Move((Join-Path $staging.Handoff ($n.Id + '.json')), (Join-Path $p.Handoff ($n.Id + '.json')))
                $Record.Notification = [string]$n.Id
            } else { $Record.Notification = 'failed' }
        } catch { $Record.Notification = 'failed' }
        Save-KanalRecord $Context $Record
    }
    return $Record
}
function Submit-KanalTurn {
    param($Context, [string]$Proje = '', [string]$Rol = '', [string]$Metin = '', [string]$Id = '', [switch]$Arkaplan)
    if (-not $Metin.Trim()) { throw 'Prompt is empty' }
    $clean = Protect-KanalText $Context $Metin
    New-Item -ItemType Directory -Path $Context.State -Force | Out-Null
    $admission = Open-KanalLock (Join-Path $Context.State 'admission.lock')
    $turnLock = $null; $record = $null; $carry=''
    try {
        if ($Id) {
            $null = Read-KanalRecord $Context $Id
            $record = @(Get-KanalRecords $Context | Where-Object { $_.Id -eq $Id })[0]
            if($record.EngineStatus -eq 'unknown' -or $record.BackendStatus -eq 'unknown' -or ($record.Engine -and -not (Resolve-KanalEngine $record.Engine)) -or ($record.Backend -and -not (Resolve-KanalBackend $record.Backend))){throw 'Unknown engine/backend; resume refused'}
            if($record.OwnerSession -and $record.OwnerSession -cne (Get-KanalOwnerSession)){throw 'Channel owner session mismatch'}
            if ($record.Status -in @('queued','running')) { throw 'Worker already has an active turn' }
            if (-not $record.SessionId) { throw 'Worker has no resumable session' }
            $decision=Get-KanalContinuation ([datetime]::Parse($record.Finished)) ([string]$record.TaskKey) ([string]$record.TaskKey) ([long]$record.ContextTokens) $record.Turn
            $record | Add-Member -NotePropertyName Continuation -NotePropertyValue $decision -Force
            if($decision.Decision -eq 'fresh'){$carry="### Previous owned session handoff`n"+$record.Answer+"`n`n";$record.SessionId=''}
            $turnLock = Open-KanalLock (Join-Path $Context.State ($Id + '.lock'))
        } else {
            if (-not (Test-Path -LiteralPath $Proje -PathType Container)) { throw 'Project directory does not exist' }
            $projectPath = (Resolve-Path -LiteralPath $Proje).ProviderPath
            $roleInfo = Resolve-KanalRole $Context $Rol
            $Id = 'CK-' + [guid]::NewGuid().ToString('N')
            $turnLock = Open-KanalLock (Join-Path $Context.State ($Id + '.lock'))
            $record = [pscustomobject]@{ Owner = 'beyin-codex-kanal-v1'; Engine='codex';Backend='exec'; Id = $Id; Project = $projectPath; Role = $roleInfo.Name;
                RoleModel = $roleInfo.Model; Sandbox = $roleInfo.Sandbox;
                WindowsSandbox = $(if($Context.WindowsSandbox){$Context.WindowsSandbox}else{'elevated'});
                RoleText = (Protect-KanalText $Context $roleInfo.Text); Created = [datetime]::UtcNow.ToString('o');
                SessionId = ''; Status = ''; Turn = 0; Prompt = ''; Answer = ''; Summary = ''; Error = '';
                Pid = 0; ProcessStart = ''; Started = ''; Finished = ''; DurationSeconds = 0;
                Background = $false; HandoffValid = $false; HandoffCheck = ''; Notification = '' }
        }
        $cap = Get-KanalCapacity $Context
        $active = @(Get-KanalRecords $Context | Where-Object { $_.Status -in @('queued','running') }).Count + (Get-KanalTeamCount $Context)
        if ($cap.onerilen -le $active) { throw "capacity rejected: active=$active recommended=$($cap.onerilen); $($cap.neden); commit %$($cap.commitYuzde), free RAM $($cap.bosRamGB) GB" }
        $record.Turn++; $record.Status = 'queued'; $record.Background = [bool]$Arkaplan
        $record.Pid = $PID; $record.ProcessStart = (Get-Process -Id $PID).StartTime.ToUniversalTime().ToString('o')
        $record.Started = [datetime]::UtcNow.ToString('o'); $record.Finished = ''; $record.Error = ''; $record.Answer = ''; $record.Summary = ''
        $compiled=New-KanalCompiledPrompt $Context $record.RoleText (New-KanalBrief $clean $record.Project)
        $record.Prompt=$compiled.Text
        $record|Add-Member -NotePropertyName BriefStats -NotePropertyValue @{Characters=$compiled.Characters;EstimatedTokens=
            $compiled.EstimatedTokens;Injected=$compiled.Injected} -Force
        $record.Prompt=$carry+$record.Prompt
        $checkpointDir=Join-Path $Context.State $record.Id;New-Item -ItemType Directory -Force $checkpointDir|Out-Null
        [IO.File]::WriteAllText((Join-Path $checkpointDir 'plan.md'),(Protect-KanalText $Context $record.Prompt),(New-Object Text.UTF8Encoding $false))
        $scope=[regex]::Match($record.Prompt,'(?ms)^Write scope:\s*(.*?)^Boundaries:').Groups[1].Value
        if(-not $record.PSObject.Properties['TaskKey']){$record | Add-Member -NotePropertyName TaskKey -NotePropertyValue (Get-KanalHash ($record.Project+'|'+$scope+'|'+$clean))}
        if(@(Get-KanalRecords $Context | Where-Object {$_.Id -ne $record.Id -and $_.TaskKey -eq $record.TaskKey -and $_.Status -in @('queued','running')}).Count){throw 'Task already claimed by an active worker'}
        if(-not $record.CodexLaunch){Set-KanalCodexRecord $Context $record (Resolve-KanalCodex $Context)}
        Save-KanalRecord $Context $record
        if ($Arkaplan) {
            # Encoded command contains only paths and channel id, never the brief.
            $code = '& ' + (Quote-KanalLiteral $Context.Entry) + ' -Komut isci -Id ' + (Quote-KanalLiteral $Id) +
                ' -Vault ' + (Quote-KanalLiteral $Context.Vault) + ' -EtatRacine ' + (Quote-KanalLiteral $Context.State)
            $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($code))
            $child = Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -WindowStyle Hidden -WorkingDirectory $Context.Vault `
                -ArgumentList @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-EncodedCommand',$encoded) -PassThru
            $record.Pid = $child.Id; $record.ProcessStart = $child.StartTime.ToUniversalTime().ToString('o')
            Save-KanalRecord $Context $record
            $child.Dispose()
        }
    } catch {
        if ($turnLock) { $turnLock.Dispose(); $turnLock = $null }
        throw
    } finally { if ($Arkaplan -and $turnLock) { $turnLock.Dispose(); $turnLock = $null }; $admission.Dispose() }
    try {
        if ($Arkaplan) { return $record }
        return Complete-KanalTurn $Context $record
    } finally { if ($turnLock) { $turnLock.Dispose() } }
}
