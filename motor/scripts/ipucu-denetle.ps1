# Static, read-only command contract check; never execute a hint or the external CLI.
param([string]$Vault = '', [string]$AgentChef = '', [switch]$Json)

function Test-BeyinHintConsistency {
    param([string]$Vault, [string[]]$Texts, [string]$AgentChef = '')
    $errors = New-Object System.Collections.Generic.List[string]
    $warnings = New-Object System.Collections.Generic.List[string]
    $dispatcher = Join-Path $Vault 'kurulum/beyin.ps1'
    $ast = [Management.Automation.Language.Parser]::ParseFile($dispatcher, [ref]$null, [ref]$null)
    $switch = $ast.FindAll({param($n) $n -is [Management.Automation.Language.SwitchStatementAst] -and $n.Condition.Extent.Text -eq '$KomutN'}, $true) | Select-Object -First 1
    $commands = @{}
    foreach ($clause in $switch.Clauses) {
        $labels = @($clause.Item1.FindAll({param($n) $n -is [Management.Automation.Language.StringConstantExpressionAst]}, $true) | ForEach-Object { $_.Value })
        if ($clause.Item1 -is [Management.Automation.Language.StringConstantExpressionAst]) { $labels += $clause.Item1.Value }
        $flags = @([regex]::Matches($clause.Item2.Extent.Text, "'(-[a-z][a-z0-9-]*)'") | ForEach-Object { $_.Groups[1].Value })
        foreach ($label in $labels) { if ($label -cmatch '^[a-z][a-z0-9-]*$') { $commands[$label] = $flags } }
    }
    $sources = New-Object System.Collections.Generic.List[object]
    if ($PSBoundParameters.ContainsKey('Texts')) {
        foreach ($text in $Texts) { $sources.Add(@{Source='fixture';Text=$text}) }
    } else {
        foreach ($relative in @('CLAUDE.md','AGENTS.md','kurulum/KILAVUZ.md')) {
            $file = Join-Path $Vault $relative
            if (-not (Test-Path -LiteralPath $file)) { $errors.Add("missing source: $relative"); continue }
            $body = [IO.File]::ReadAllText($file)
            # Inline code and command lines inside fenced examples; prose is not a command.
            foreach ($m in [regex]::Matches($body, '(?m)`(beyin\s+[^`\r\n]+)`|^\s*(beyin\s+[^\r\n]+)')) {
                $text = $m.Groups[1].Value; if (-not $text) { $text = $m.Groups[2].Value }
                $sources.Add(@{Source=$relative;Text=$text})
            }
        }
        foreach ($folder in @('motor/hooks','motor/scripts')) {
            foreach ($file in @(Get-ChildItem -LiteralPath (Join-Path $Vault $folder) -Filter '*.ps1' -File | Where-Object { $_.Name -notlike '*.Tests.ps1' -and $_.Name -notlike '*kanal*' -and $_.Name -ne 'ipucu-denetle.ps1' })) {
                $tree = [Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$null, [ref]$null)
                foreach ($literal in @($tree.FindAll({param($n) $n -is [Management.Automation.Language.StringConstantExpressionAst] -or $n -is [Management.Automation.Language.ExpandableStringExpressionAst]}, $true))) {
                    foreach ($m in [regex]::Matches($literal.Value, '\bbeyin\s+[a-z][a-z0-9-]*(?:(?!\bbeyin\b)[^\r\n])*')) {
                        # UI prose beginning with 'beyin motoru' is not executable code.
                        if ($m.Value -match '^beyin\s+(motoru|motorunun|motorun|hafiza|icin|ile|girdileri|girdilerini|kancalarini|kurulmadan|yayin)\b') { continue }
                        $sources.Add(@{Source=$file.Name;Text=$m.Value})
                    }
                }
            }
        }
    }
    $teamCommands = @{}
    if ($AgentChef) {
        $teamFile = Join-Path $AgentChef 'scripts/team-run.mjs'
        if (Test-Path -LiteralPath $teamFile) {
            $code = [IO.File]::ReadAllText($teamFile)
            $contract = [regex]::Match($code, '(?s)const COMMANDS\s*=\s*\{(.*?)\n\};').Groups[1].Value
            foreach ($m in [regex]::Matches($contract, '(?:"([a-z-]+)"|\b([a-z-]+))\s*:\s*\[([^\]]*)\]')) {
                $name = $m.Groups[1].Value; if (-not $name) { $name = $m.Groups[2].Value }
                $teamCommands[$name] = @([regex]::Matches($m.Groups[3].Value, '"([a-z-]+)"') | ForEach-Object { '--' + $_.Groups[1].Value }) + @('--json')
            }
            if (-not $teamCommands.Count) { $errors.Add('team-run COMMANDS contract could not be parsed') }
        } else { $errors.Add('team-run.mjs missing') }
    } else { $warnings.Add('AgentChef root not selected; team CLI flags unverified (-AgentChef <root>)') }
    foreach ($hint in $sources) {
        $m = [regex]::Match($hint.Text, '^beyin\s+([a-z][a-z0-9-]*)(.*)$')
        if (-not $m.Success) { continue }
        $command = $m.Groups[1].Value; $tail = ($m.Groups[2].Value -split '[;`)]' | Select-Object -First 1)
        if (-not $commands.ContainsKey($command)) { $errors.Add("$($hint.Source): unknown command $command"); continue }
        # Only actual syntax tokens outside quoted example text are flags.
        $tail = $tail -replace '"[^"\r\n]*"', '' -replace "'[^'\r\n]*'", ''
        if ($command -in @('pano','takim','codex','claude')) {
            if ($command -eq 'takim' -and $teamCommands.Count) {
                $sub = [regex]::Match($tail.Trim(), '^([a-z-]+)').Value
                if ($sub -eq 'kullan') { $sub = '' } # grammatical suffix after the command name
                $local = @('durum','baslat','birlestir','durdur','maliyet','izle')
                if ($sub -and $sub -notin $local -and -not $teamCommands.ContainsKey($sub)) { $errors.Add("$($hint.Source): unknown team command $sub") }
                if ($teamCommands.ContainsKey($sub)) {
                    foreach ($f in [regex]::Matches($tail, '(?<![\w-])--[a-z][a-z-]*')) {
                        if ($f.Value -notin $teamCommands[$sub]) { $errors.Add("$($hint.Source): takim $sub rejects $($f.Value)") }
                    }
                }
            }
            continue
        }
        foreach ($flag in [regex]::Matches($tail, '(?<![\w-])-[A-Za-z][A-Za-z0-9]*')) {
            if ($flag.Value.ToLowerInvariant() -notin $commands[$command]) { $errors.Add("$($hint.Source): $command rejects $($flag.Value)") }
        }
    }
    return @{Ok=($errors.Count -eq 0); Checked=$sources.Count; Errors=@($errors.ToArray() | Sort-Object -Unique); Warnings=$warnings.ToArray()}
}

if ($MyInvocation.InvocationName -eq '.') { return }
if (-not $Vault) { $Vault = $(if ($env:BEYIN_VAULT) { $env:BEYIN_VAULT } else { Split-Path (Split-Path $PSScriptRoot -Parent) -Parent }) }
if (-not $AgentChef) { $AgentChef = $env:BEYIN_AGENTCHEF_KOK }
$result = Test-BeyinHintConsistency -Vault $Vault -AgentChef $AgentChef
if ($Json) { $result | ConvertTo-Json -Depth 5 } else { "IPUCU: $($result.Checked) kontrol, $($result.Errors.Count) hata"; $result.Errors; $result.Warnings }
if (-not $result.Ok) { exit 1 }
