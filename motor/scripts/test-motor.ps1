# Local verification only. Does not install, publish, or change user settings.
[CmdletBinding()]
param(
    [ValidateSet('Pester','Node','All')][string]$Suite = 'All',
    [ValidateSet('Combined','PerFile')][string]$PesterMode = 'Combined',
    [string[]]$PesterPath = @(),
    [string]$ResultsDirectory = ''
)
$ErrorActionPreference = 'Stop'
$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$results = $(if ($ResultsDirectory) { [IO.Path]::GetFullPath($ResultsDirectory) } else { Join-Path $PSScriptRoot '.state/dalga34-tests' })
New-Item -ItemType Directory -Force -Path $results | Out-Null
$failed = 0
if ($Suite -in @('All','Pester')) {
    $motorHostContext=@{explicitAgent=$(if ($env:BEYIN_AGENT -in @('claude','codex')) { $env:BEYIN_AGENT } else { '' }); claudeContext=($env:CLAUDECODE -eq '1'); codexContext=[bool]($env:CODEX_THREAD_ID -or $env:CODEX_SESSION_ID -or $env:CODEX_SANDBOX)}
    Import-Module Pester -MaximumVersion 3.99 -ErrorAction Stop
    $sourceTests = @()
    $motorBatches = New-Object System.Collections.Generic.List[object]
    $motorRunnerErrors = New-Object System.Collections.Generic.List[string]
    Write-Output "Pester $((Get-Module Pester).Version), PowerShell $($PSVersionTable.PSVersion): $PesterMode run started"
    $motorPreviousPreference = $ErrorActionPreference
    try {
        if ($PesterPath.Count) { $sourceTests = @($PesterPath | ForEach-Object { (Get-Item -LiteralPath $_ -ErrorAction Stop).FullName }) }
        else {
            $sourceTests = @(Get-ChildItem -LiteralPath @((Join-Path $root 'motor/hooks'), (Join-Path $root 'motor/scripts')) -Filter '*.Tests.ps1' -File -Recurse |
                Where-Object { $_.FullName -notmatch '[\\/]\.state[\\/]' } | ForEach-Object { $_.FullName })
        }
        if (-not $sourceTests.Count) { throw 'No source tests discovered' }
        foreach ($motorFile in $sourceTests) {
            $motorTokens=$null;$motorParseErrors=$null
            $motorAst=[Management.Automation.Language.Parser]::ParseFile($motorFile,[ref]$motorTokens,[ref]$motorParseErrors)
            if ($motorParseErrors.Count) { throw "Test source has parse errors: $motorFile" }
            $motorCases=@($motorAst.FindAll({param($node) $node -is [Management.Automation.Language.CommandAst] -and $node.GetCommandName() -eq 'It'},$true))
            if (-not $motorCases.Count) { throw "Test source contains no It cases: $motorFile" }
        }
        Write-Output "Pester: $($sourceTests.Count) source test files (runtime .state excluded), mode=$PesterMode"
        # Combined invokes Pester once; PerFile deliberately repeats Invoke-Pester
        # inside THIS PowerShell process, matching the chief's sequence check.
        $motorGroups=@()
        if ($PesterMode -eq 'Combined') { $motorGroups=@(@{paths=$sourceTests}) }
        else { $motorGroups=@(foreach ($motorFile in $sourceTests) { @{paths=@($motorFile)} }) }
        $ErrorActionPreference = 'Continue'
        foreach ($motorGroup in $motorGroups) {
            if ($PesterMode -eq 'PerFile') { Write-Output ("Pester file: " + $motorGroup.paths[0]) }
            $motorOutput=@(Invoke-Pester -Script $motorGroup.paths -PassThru -Quiet -Strict)
            $motorResult=@($motorOutput | Where-Object { $_ -and $_.PSObject.Properties['TestResult'] -and $_.PSObject.Properties['TotalCount'] })
            if ($motorResult.Count -ne 1) { throw 'Pester did not return exactly one result object' }
            $motorResult=$motorResult[0]
            $motorRecords=@($motorResult.TestResult)
            if ($motorResult.TotalCount -le 0 -or $motorRecords.Count -ne $motorResult.TotalCount) { throw 'Pester returned incomplete or empty test coverage' }
            if (@($motorRecords | Where-Object { $_.Result -eq 'Failed' }).Count -ne $motorResult.FailedCount) { throw 'Pester failure count disagrees with individual test results' }
            $motorBatches.Add($motorResult)
        }
    } catch { $motorRunnerErrors.Add([string]$_.Exception.Message) }
    finally { $ErrorActionPreference = $motorPreviousPreference }
    $summary = [ordered]@{
        ts=(Get-Date).ToString('o'); mode=$PesterMode; powershell=[string]$PSVersionTable.PSVersion; pester=[string](Get-Module Pester).Version
        host=$motorHostContext
        sourceFiles=@($sourceTests); completedBatches=$motorBatches.Count; runnerErrors=@($motorRunnerErrors.ToArray())
        total=0;passed=0;failed=$motorRunnerErrors.Count;skipped=0;pending=0;seconds=0.0;failures=@()
    }
    foreach ($motorBatch in $motorBatches) {
        $summary.total+=$motorBatch.TotalCount;$summary.passed+=$motorBatch.PassedCount;$summary.failed+=$motorBatch.FailedCount
        $summary.skipped+=$motorBatch.SkippedCount;$summary.pending+=$motorBatch.PendingCount;$summary.seconds+=$motorBatch.Time.TotalSeconds
        $summary.failures+=@($motorBatch.TestResult | Where-Object { $_.Result -ne 'Passed' -and $_.Result -ne 'Skipped' } | Select-Object Describe,Name,Result,FailureMessage,StackTrace)
    }
    $json = $summary | ConvertTo-Json -Depth 6
    [IO.File]::WriteAllText((Join-Path $results 'pester.json'), $json)
    [IO.File]::WriteAllText((Join-Path $results ('pester-'+$PesterMode.ToLowerInvariant()+'.json')), $json)
    Write-Output $json
    $failed += $summary.failed
    if ($summary.pending -gt 0 -or $summary.skipped -gt 0) { $failed++ }
}
if ($Suite -in @('All','Node')) {
    $files = @(Get-ChildItem -LiteralPath (Join-Path $root 'motor') -Filter '*.test.mjs' -File -Recurse | Where-Object { $_.FullName -notmatch '[\\/]\.state[\\/]' } | Sort-Object FullName | ForEach-Object { $_.FullName })
    $node = (Get-Command node.exe -ErrorAction Stop).Source
    Write-Output "Node: $($files.Count) test files, concurrency 1"
    & $node --test --test-concurrency=1 @files 2>&1 | Tee-Object -FilePath (Join-Path $results 'node.tap')
    if ($LASTEXITCODE -ne 0) { $failed++ }
}
if ($failed) { exit 1 }
exit 0
