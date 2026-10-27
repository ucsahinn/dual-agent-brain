# Pester 3.4+; no live model calls. The process fixture checks arguments and stdin.
$root = $PSScriptRoot
. (Join-Path (Split-Path $root -Parent) 'hooks/lib.ps1')
. (Join-Path $root 'codex-kanal/core.ps1')
$originalFilter = ${function:Protect-BeyinSecrets}
$originalTeamCount = ${function:Get-KanalTeamCount}
$originalInvoke = ${function:Invoke-KanalProcess}
$originalSleep = Get-Command Start-Sleep -CommandType Cmdlet
Describe 'Codex live channel' {
    BeforeEach {
        Mock Invoke-KanalProcess { param($Context,$Record) & $originalInvoke $Context $Record }
        Mock Start-Sleep { param($Seconds,$Milliseconds) if ($Milliseconds) { & $originalSleep -Milliseconds $Milliseconds } else { & $originalSleep -Seconds $Seconds } }
        Mock Protect-BeyinSecrets { param($Text, $Vault) & $originalFilter -Text $Text -Vault $Vault }
        $ctx = New-KanalContext (Split-Path (Split-Path $root -Parent) -Parent)
        $ctx.State = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $ctx.ConfigPath=Join-Path $TestDrive 'fixture-config.toml'
        "[mcp_servers.node_repl]`ncommand='fixture'`n[mcp_servers.serena]`ncommand='fixture'`n[mcp_servers.serena.tools.find_symbol]`nenabled=true"|Set-Content -LiteralPath $ctx.ConfigPath -Encoding UTF8
        New-Item -ItemType Directory -Path $ctx.State -Force | Out-Null
        Mock Get-KanalCapacity { @{ onerilen = 2; neden = 'fixture: 8 GB free'; commitYuzde = 40; bosRamGB = 8 } }
        Mock Get-KanalTeamCount { 0 }
        $fixture = Join-Path $TestDrive 'fake codex.js'
        @'
const args = process.argv.slice(2), p = require('fs').readFileSync(0, 'utf8');
if (!args.includes('--json') || !args.includes('-')) process.exit(11);
for (const label of ['Goal:', 'Evidence:', 'Write scope:', 'Boundaries:', 'Done when:', 'Return format:', "User's words:"]) if (!p.includes(label)) process.exit(17);
if (!args.join(' ').includes('sandbox_mode=workspace-write') && !args.join(' ').includes('sandbox_mode=read-only')) process.exit(12);
if (args.includes('gpt-6-luna') && !p.includes('Explore broadly but summarize tightly')) process.exit(16);
if (args.includes('resume')) {
  if (!args.includes('11111111-1111-4111-8111-111111111111')) process.exit(13);
  if (!p.includes('second')) process.exit(14);
} else if (!p.includes('first')) process.exit(15);
console.log('{"type":"thread.started","thread_id":"11111111-1111-4111-8111-111111111111"}');
console.log('{"type":"item.completed","item":{"type":"agent_message","text":"Outcome: OK\\nEvidence: counted\\nChanged scope: none\\nRisks: none\\nOpen questions: none\\nNext verification: none"}}');
console.log('{"type":"turn.completed","usage":{"input_tokens":1,"output_tokens":1}}');
'@ | Set-Content -LiteralPath $fixture -Encoding UTF8
        $shim = Join-Path $TestDrive 'codex.cmd'
        "@echo off`r`nif `"%~1`"==`"--version`" (`r`necho codex-cli 0.162.1`r`nexit /b 0`r`n)`r`nnode.exe `"%~dp0fake codex.js`" %*`r`n" | Set-Content -LiteralPath $shim -Encoding ASCII
        $ctx.Codex = $shim
    }
    # Removing admission control would admit a worker under measured memory pressure.
    It 'rejects zero capacity without creating a worker' {
        Mock Get-KanalCapacity { @{ onerilen = 0; neden = 'commit %98'; commitYuzde = 98; bosRamGB = 2.2 } }
        { Submit-KanalTurn $ctx -Proje $TestDrive -Metin 'first' } | Should Throw 'commit %98'
        @(Get-ChildItem $ctx.State -Filter '*.json').Count | Should Be 0
    }
    It 'disables configured node_repl without overriding plugin transports' {
        $source = [IO.File]::ReadAllText($fixture)
        $guard = "if (!args.includes('mcp_servers.node_repl.enabled=false') || args.some(a => a.includes('cua_repl'))) process.exit(29);"
        [IO.File]::WriteAllText($fixture, $source.Replace("if (!args.includes('--json')", "$guard`nif (!args.includes('--json')"))
        (Submit-KanalTurn $ctx -Proje $TestDrive -Metin 'first').Status | Should Be 'completed'
    }
    It 'retries a transient setup error in the same sandbox with bounded jitter' {
        $script:retryCalls = 0
        Mock Start-Sleep {}
        Mock Invoke-KanalProcess {
            $script:retryCalls++
            if ($script:retryCalls -eq 1) { throw (New-KanalSetupFailure) }
            return @{SessionId='11111111-1111-4111-8111-111111111111'; Answer="Outcome: OK`nEvidence: counted`nChanged scope: none`nRisks: none`nOpen questions: none`nNext verification: none"}
        }
        $a = Submit-KanalTurn $ctx -Proje $TestDrive -Metin 'first'
        $a.Status | Should Be 'completed'
        $script:retryCalls | Should Be 2
        $a.RetryCount | Should Be 1
        $a.Attempts | Should Be 2
        @($a.RetryEvents).Count | Should Be 1
        $a.WindowsSandbox | Should Be 'elevated'
        $a.SandboxFallback | Should BeNullOrEmpty
        Assert-MockCalled Start-Sleep -Times 1 -Exactly -Scope It -ParameterFilter { $Seconds -ge 10 -and $Seconds -le 40 }
    }
    It 'stops after three setup attempts with fallback only on the last attempt' {
        $script:retryCalls = 0
        Mock Start-Sleep {}
        Mock Invoke-KanalProcess { $script:retryCalls++; throw (New-KanalSetupFailure) }
        $a = Submit-KanalTurn $ctx -Proje $TestDrive -Metin 'first'
        $a.Status | Should Be 'failed'
        $script:retryCalls | Should Be 3
        $a.RetryCount | Should Be 2
        $a.SandboxFallback.Attempt | Should Be 3
    }
    It 'does not retry an unrelated failure' {
        $script:retryCalls = 0
        Mock Start-Sleep {}
        Mock Invoke-KanalProcess { $script:retryCalls++; throw 'transport failed' }
        $a = Submit-KanalTurn $ctx -Proje $TestDrive -Metin 'first'
        $a.Status | Should Be 'failed'
        $script:retryCalls | Should Be 1
        Assert-MockCalled Start-Sleep -Times 0 -Exactly -Scope It
    }
    It 'preserves UTF8 input without a BOM and trusts a valid live turn despite stale rollout evidence' {
        $source=[IO.File]::ReadAllText($fixture)
        $check="if(p.charCodeAt(0)!==71 || !p.includes('Türkçe ıİ şğ'))process.exit(37);`n"
        [IO.File]::WriteAllText($fixture,$source.Replace("if (!args.includes('--json')",$check+"if (!args.includes('--json')"),(New-Object Text.UTF8Encoding $false))
        Mock Get-KanalDelivery { @{Status='yutuldu'} }
        $previousInput=[Console]::InputEncoding
        try{[Console]::InputEncoding=[Text.Encoding]::UTF8;$a=Submit-KanalTurn $ctx -Proje $TestDrive -Metin 'first Türkçe ıİ şğ'}finally{[Console]::InputEncoding=$previousInput}
        $a.Status|Should Be 'completed';$a.Attempts|Should Be 1;$a.Delivery.Source|Should Be 'validated-live-turn';$a.Delivery.RolloutStatus|Should Be 'yutuldu'
    }
    It 'prioritizes a failed command setup signature over a valid handoff and delivery retry' {
        $source = [IO.File]::ReadAllText($fixture)
        [IO.File]::WriteAllText($fixture, $source.Replace("console.log('{", "console.log(JSON.stringify({type:'item.completed',item:{type:'command_execution',status:'failed',exit_code:1,aggregated_output:'setup refresh had errors'}}));`nconsole.log('{"))
        Mock Start-Sleep {}
        $a = Submit-KanalTurn $ctx -Proje $TestDrive -Metin 'first second'
        $a.Status | Should Be 'failed'
        $a.Attempts | Should Be 3
        $a.RetryCount | Should Be 2
        $a.WindowsSandbox | Should Be 'unelevated'
        $a.SandboxFallback.To | Should Be 'unelevated'
        $a.RetryEvents[0].Reason | Should Be 'sandbox-setup-refresh'
    }
    It 'retries an exit minus one command setup failure directly as unelevated without stderr' {
        $source=[IO.File]::ReadAllText($fixture)
        $inject="if(!process.argv.some(a=>a.includes('unelevated'))){console.log(JSON.stringify({type:'item.completed',item:{type:'command_execution',status:'failed',exit_code:-1,aggregated_output:'Failed to create unified exec process: helper_unknown_error: setup refresh had errors'}}));}`n"
        [IO.File]::WriteAllText($fixture,$inject+$source);Mock Start-Sleep {}
        $a=Submit-KanalTurn $ctx -Proje $TestDrive -Metin 'first second'
        $a.Status|Should Be 'completed';$a.Attempts|Should Be 3;$a.SandboxFallback.To|Should Be 'unelevated'
        @($a.RetryEvents).Count|Should Be 2;$a.RetryEvents[0].Reason|Should Be 'sandbox-setup-refresh'
    }
    It 'falls back once from elevated to unelevated on failed stderr setup refresh' {
        $source=[IO.File]::ReadAllText($fixture)
        $guard="const u=process.argv.some(a=>a.includes('windows.sandbox=unelevated')||a.includes('windows.sandbox=\`"unelevated\`"')); if(!u){process.stderr.write('setup refresh had errors sk-'+ 'Q'.repeat(32));process.exit(9);}`n"
        [IO.File]::WriteAllText($fixture,$guard+$source);Mock Start-Sleep {}
        $a=Submit-KanalTurn $ctx -Proje $TestDrive -Metin 'first second'
        $a.Status|Should Be 'completed';$a.Attempts|Should Be 3;$a.SandboxFallback.To|Should Be 'unelevated';$a.Sandbox|Should Be 'workspace-write'
        $a.SandboxFallback.StderrTail|Should Match 'setup refresh';$a.SandboxFallback.StderrTail|Should Not Match ('sk-'+('Q'*32))
    }
    It 'keeps a valid completed exec turn successful despite stderr setup refresh warning' {
        [IO.File]::WriteAllText($fixture,"process.stderr.write('setup refresh had errors');`n"+[IO.File]::ReadAllText($fixture))
        $a=Submit-KanalTurn $ctx -Proje $TestDrive -Metin 'first'
        $a.Status|Should Be 'completed';$a.Attempts|Should Be 1;$a.RetryCount|Should Be 0
    }
    It 'uses an explicit unelevated worker profile without trying elevated first' {
        $ctx.WindowsSandbox='unelevated';$source=[IO.File]::ReadAllText($fixture)
        $guard="if(!process.argv.some(a=>a.includes('windows.sandbox=unelevated')||a.includes('windows.sandbox=\`"unelevated\`"')))process.exit(31);`n"
        [IO.File]::WriteAllText($fixture,$guard+$source)
        $a=Submit-KanalTurn $ctx -Proje $TestDrive -Metin 'first'
        $a.Status|Should Be 'completed';$a.Attempts|Should Be 1;$a.WindowsSandbox|Should Be 'unelevated'
    }
    It 'retains failed stderr after the single fallback also fails' {
        [IO.File]::WriteAllText($fixture,"process.stderr.write('setup refresh had errors sk-'+ 'Q'.repeat(32));process.exit(9);")
        Mock Start-Sleep {}
        $a=Submit-KanalTurn $ctx -Proje $TestDrive -Metin 'first'
        $a.Status|Should Be 'failed';$a.Attempts|Should Be 3;$a.Error|Should Match 'setup refresh';$a.StderrTail|Should Not Match ('sk-'+('Q'*32))
    }
    It 'records redacted error events and failed stderr without retrying unrelated errors' {
        [IO.File]::WriteAllText($fixture,"console.log(JSON.stringify({type:'error',message:'unrelated error sk-'+ 'Q'.repeat(32)}));process.stderr.write('unrelated stderr sk-'+ 'Q'.repeat(32));process.exit(7);")
        $a=Submit-KanalTurn $ctx -Proje $TestDrive -Metin 'first'
        $a.Status|Should Be 'failed';$a.Attempts|Should Be 1;$a.Error|Should Match 'unrelated error';$a.StderrTail|Should Match 'unrelated stderr'
        ([IO.File]::ReadAllText((Join-Path (Join-Path $ctx.State $a.Id) 'events.jsonl')))|Should Not Match ('sk-'+('Q'*32))
    }
    It 'does not retry ordinary final-answer text containing the setup error phrase' {
        $source = [IO.File]::ReadAllText($fixture).Replace('Outcome: OK', 'Outcome: setup refresh had errors')
        [IO.File]::WriteAllText($fixture, $source)
        Mock Start-Sleep {}
        $a = Submit-KanalTurn $ctx -Proje $TestDrive -Metin 'first second'
        $a.Status | Should Be 'completed'
        $a.SessionId | Should Be '11111111-1111-4111-8111-111111111111'
        $a.RetryCount | Should Be 0
        $a.Attempts | Should Be 1
    }
    It 'counts other team workers against capacity' {
        Mock Get-KanalTeamCount { 2 }
        { Submit-KanalTurn $ctx -Proje $TestDrive -Metin 'first' } | Should Throw 'capacity'
    }
    It 'counts the engines queued and spawning team states' {
        $ctx.Vault = Join-Path $TestDrive 'team-vault'
        $paths = Get-BeyinPaths -Vault $ctx.Vault
        New-Item -ItemType Directory -Force -Path $paths.TeamRuns | Out-Null
        '{"workers":[{"status":"queued"},{"status":"spawning"},{"status":"completed"}]}' | Set-Content (Join-Path $paths.TeamRuns 'fixture.json')
        (& $originalTeamCount $ctx) | Should Be 2
    }
    It 'refuses unknown roles and path traversal' {
        { Resolve-KanalRole $ctx 'agentchef:../../missing' } | Should Throw
        { Resolve-KanalRole $ctx 'not-a-real-role' } | Should Throw
    }
    It 'loads installed AgentChef role instructions' {
        $r = Resolve-KanalRole $ctx 'agentchef:code-mapper'
        $r.Text.Length | Should BeGreaterThan 100
        $r.Name | Should Be 'code-mapper'
    }
    It 'uses the installed Codex role model and narrower sandbox' {
        $a = Submit-KanalTurn $ctx -Proje $TestDrive -Rol 'agentchef:code-mapper' -Metin 'first'
        $a.Status | Should Be 'completed'
        $a.RoleModel | Should Be 'gpt-6-luna'
        $a.Sandbox | Should Be 'read-only'
    }
    It 'rejects blank or reordered handoff fields' {
        Test-KanalHandoff "Outcome: OK`nEvidence: count`nChanged scope: none`nRisks:`nOpen questions: none`nNext verification: none" | Should Be $false
        Test-KanalHandoff "Evidence: count`nOutcome: OK`nChanged scope: none`nRisks: none`nOpen questions: none`nNext verification: none" | Should Be $false
    }
    It 'preserves complete briefs and rejects empty or missing brief fields' {
        Test-KanalBrief "Goal:`nEvidence:`nWrite scope:`nBoundaries:`nDone when:`nReturn format:`nUser's words:" | Should Be $false
        Test-KanalBrief 'Goal: first' | Should Be $false
        $brief = New-KanalBrief 'first' 'C:/example'
        Test-KanalBrief $brief | Should Be $true
        New-KanalBrief $brief 'C:/other' | Should Be $brief
    }
    It 'terminates its own timed out fixture and records failure' {
        'setInterval(() => {}, 1000);' | Set-Content -LiteralPath $fixture -Encoding UTF8
        $ctx.Timeout = 1
        $a = Submit-KanalTurn $ctx -Proje $TestDrive -Metin 'first'
        $a.Status | Should Be 'failed'
        $a.Error | Should Match 'timed out'
        $a.Prompt | Should Be ''
    }
    It 'never resumes an unowned TUI session' {
        { Submit-KanalTurn $ctx -Id '11111111-1111-4111-8111-111111111111' -Metin 'second' } | Should Throw 'owned'
    }
    # A fake executable tests the real stdin transport, JSONL parser, state and resume path.
    It 'sends and resumes the same owned session end to end' {
        $a = Submit-KanalTurn $ctx -Proje $TestDrive -Metin "first `"quoted`" & literal"
        if ($a.Status -eq 'failed') { throw $a.Error }
        if ($a.Status -eq 'invalid-handoff') { throw ($a.HandoffCheck + ': ' + $a.Answer) }
        $a.Status | Should Be 'completed'
        $a.SessionId | Should Be '11111111-1111-4111-8111-111111111111'
        $a.Answer | Should Match 'Outcome: OK'
        $b = Submit-KanalTurn $ctx -Id $a.Id -Metin 'second'
        $b.Status | Should Be 'completed'
        $b.Turn | Should Be 2
        $b.SessionId | Should Be $a.SessionId
        (Read-KanalRecord $ctx $a.Id).Answer | Should Match 'Evidence: counted'
    }
    It 'persists only redacted input and output' {
        $value = 'sk-' + ('A' * 32)
        $a = Submit-KanalTurn $ctx -Proje $TestDrive -Metin "first api_key=$value"
        (Get-Content -Raw (Join-Path $ctx.State ($a.Id + '.json'))) | Should Not Match $value
    }
    It 'refuses a concurrent turn on the same worker' {
        $a = Submit-KanalTurn $ctx -Proje $TestDrive -Metin 'first'
        $l = [IO.File]::Open((Join-Path $ctx.State ($a.Id + '.lock')), 'OpenOrCreate', 'ReadWrite', 'None')
        try { { Submit-KanalTurn $ctx -Id $a.Id -Metin 'second' } | Should Throw } finally { $l.Dispose() }
    }
    It 'counts already reserved channel workers' {
        $a = Submit-KanalTurn $ctx -Proje $TestDrive -Metin 'first'
        $a.Status = 'queued'; $a.Pid = $PID; $a.ProcessStart = (Get-Process -Id $PID).StartTime.ToUniversalTime().ToString('o')
        Save-KanalRecord $ctx $a
        Mock Get-KanalCapacity { @{ onerilen = 1; neden = 'one slot'; commitYuzde = 40; bosRamGB = 8 } }
        { Submit-KanalTurn $ctx -Proje $TestDrive -Metin 'first' } | Should Throw 'active=1'
    }
    It 'marks dead owners interrupted without retrying their turn' {
        $a = Submit-KanalTurn $ctx -Proje $TestDrive -Metin 'first'
        $a.Status = 'running'; $a.Pid = 2147483646
        Save-KanalRecord $ctx $a
        @(Get-KanalRecords $ctx)[0].Status | Should Be 'interrupted'
        (Read-KanalRecord $ctx $a.Id).Turn | Should Be 1
    }
    It 'rejects incomplete handoffs' {
        "'{}'" | Set-Content -LiteralPath $fixture -Encoding UTF8
        $a = Submit-KanalTurn $ctx -Proje $TestDrive -Metin 'first'
        $a.Status | Should Be 'failed'
        $a.SessionId | Should Be ''
    }
    It 'redacts secrets from model output before persisting' {
        $secret = 'sk-' + ('B' * 32)
        $text = [IO.File]::ReadAllText($fixture).Replace('Outcome: OK', "Outcome: $secret")
        [IO.File]::WriteAllText($fixture, $text)
        $a = Submit-KanalTurn $ctx -Proje $TestDrive -Metin 'first'
        $a.Status | Should Be 'completed'
        $a.Answer | Should Not Match $secret
        (Get-Content -Raw (Join-Path $ctx.State ($a.Id + '.json'))) | Should Not Match $secret
    }
    It 'fails closed when the secret filter fails' {
        Mock Protect-BeyinSecrets { @{ Text = ''; Failed = 1 } }
        { Submit-KanalTurn $ctx -Proje $TestDrive -Metin 'first' } | Should Throw 'Secret filter failed'
        @(Get-ChildItem $ctx.State -Filter '*.json').Count | Should Be 0
    }
    It 'finishes a detached worker and emits exactly one handoff in the isolated vault' {
        $isolated = Join-Path $TestDrive 'vault'
        New-Item -ItemType Directory -Force -Path (Join-Path $isolated 'motor/hooks') | Out-Null
        Copy-Item -LiteralPath (Join-Path $ctx.Vault 'motor/hooks/lib.ps1') -Destination (Join-Path $isolated 'motor/hooks/lib.ps1')
        $ctx.Vault = $isolated
        $oldPath = $env:PATH
        $listener = $null
        try {
            $env:PATH = [string]$TestDrive + ';' + $oldPath
            $listenCode = '& ' + (Quote-KanalLiteral (Join-Path $root 'aktar-dinle.ps1')) +
                ' -Vault ' + (Quote-KanalLiteral $isolated) + ' -Kime claude -Sure 30'
            $listener = Start-KanalPowerShell $listenCode $isolated
            $listener.StandardInput.Close()
            $listener.StandardOutput.ReadLine() | Should Match 'dinleniyor'
            $listenLine = $listener.StandardOutput.ReadLineAsync()
            $listenErrors = $listener.StandardError.ReadToEndAsync()
            $a = Submit-KanalTurn $ctx -Proje $TestDrive -Metin 'first' -Arkaplan
            $a.Status | Should Be 'queued'
            $deadline = [datetime]::UtcNow.AddSeconds(25)
            do { Start-Sleep -Milliseconds 200; $b = Read-KanalRecord $ctx $a.Id } while (-not $b.Notification -and [datetime]::UtcNow -lt $deadline)
            $b.Status | Should Be 'completed'
            $b.Notification | Should Not Be 'failed'
            $b.Notification | Should Not Be ''
            $paths = Get-BeyinPaths -Vault $isolated
            @(Get-ChildItem -LiteralPath $paths.Handoff -Filter '*.json').Count | Should Be 1
            Test-Path (Join-Path $isolated '10-command-center/aktarimlar.md') | Should Be $false
            $listenLine.Wait(12000) | Should Be $true
            $listenLine.Result | Should Match '^AKTAR '
            $listenLine.Result | Should Match $a.Id
            $duplicate = $listener.StandardOutput.ReadLineAsync()
            $duplicate.Wait(500) | Should Be $false
        } finally {
            $env:PATH = $oldPath
            if ($listener) { if (-not $listener.HasExited) { $listener.Kill() }; $listener.Dispose() }
        }
    }
}
