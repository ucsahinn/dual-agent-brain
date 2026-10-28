$runner=Join-Path $PSScriptRoot 'test-motor.ps1'
Describe 'Motor test harness: coverage, invocation mode and honest exit status' {
    It 'records a passing fixture and mode in both combined and per-file runs' {
        $file=Join-Path $TestDrive 'pass.Tests.ps1'
        Set-Content -LiteralPath $file -Value "Describe 'fixture' { It 'passes' { 1 | Should Be 1 } }"
        foreach ($mode in @('Combined','PerFile')) {
            $out=Join-Path $TestDrive $mode
            $null=& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runner -Suite Pester -PesterMode $mode -PesterPath $file -ResultsDirectory $out
            $LASTEXITCODE | Should Be 0
            $r=Get-Content -LiteralPath (Join-Path $out 'pester.json') -Raw | ConvertFrom-Json
            $r.mode | Should Be $mode
            $r.total | Should Be 1
            $r.passed | Should Be 1
            @($r.sourceFiles).Count | Should Be 1
        }
    }
    It 'keeps failed assertions red and returns a nonzero process exit code' {
        $file=Join-Path $TestDrive 'fail.Tests.ps1';$out=Join-Path $TestDrive 'failed-result'
        Set-Content -LiteralPath $file -Value "Describe 'fixture' { It 'fails' { 1 | Should Be 2 } }"
        $null=& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runner -Suite Pester -PesterPath $file -ResultsDirectory $out
        $LASTEXITCODE | Should Be 1
        $r=Get-Content -LiteralPath (Join-Path $out 'pester.json') -Raw | ConvertFrom-Json
        $r.failed | Should Be 1
        @($r.failures).Count | Should Be 1
    }
    It 'rejects empty test files rather than counting no executed tests as success' {
        $file=Join-Path $TestDrive 'empty.Tests.ps1';$out=Join-Path $TestDrive 'empty-result'
        Set-Content -LiteralPath $file -Value '# no test definitions'
        $null=& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runner -Suite Pester -PesterPath $file -ResultsDirectory $out 2>&1
        $LASTEXITCODE | Should Be 1
    }
    It 'includes a test-script load error in the failed result and exit code' {
        $file=Join-Path $TestDrive 'load-error.Tests.ps1';$out=Join-Path $TestDrive 'load-error-result'
        Set-Content -LiteralPath $file -Value "Describe 'fixture' { It 'passes' { 1 | Should Be 1 } }; throw 'fixture load failure'"
        $null=& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runner -Suite Pester -PesterPath $file -ResultsDirectory $out
        $LASTEXITCODE | Should Be 1
        $r=Get-Content -LiteralPath (Join-Path $out 'pester.json') -Raw | ConvertFrom-Json
        $r.passed | Should Be 1
        $r.failed | Should Be 1
        $r.failures[0].FailureMessage | Should Match 'fixture load failure'
    }
    It 'rejects an unknown switch before discovering or executing source tests' {
        $out=Join-Path $TestDrive 'unknown-result'
        $null=& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runner -Suite Pester -UnknownMotorSwitch -ResultsDirectory $out 2>&1
        $LASTEXITCODE | Should Be 1
        (Test-Path -LiteralPath (Join-Path $out 'pester.json')) | Should Be $false
    }
}
