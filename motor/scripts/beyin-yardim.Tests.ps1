$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$dispatcher = Join-Path $root 'kurulum\beyin.ps1'
$doctor = Join-Path $PSScriptRoot 'doktor.ps1'
$powershell = (Get-Command powershell.exe).Source

function Get-BeyinCanonicalCommands {
    $tokens = $null
    $errors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile($dispatcher, [ref]$tokens, [ref]$errors)
    $null = (@($errors).Count | Should Be 0)
    $switch = @($ast.FindAll({
        param($node)
        $node -is [Management.Automation.Language.SwitchStatementAst] -and
        $node.Condition.Extent.Text -eq '$KomutN'
    }, $true))
    $null = ($switch.Count | Should Be 1)

    $commands = foreach ($clause in $switch[0].Clauses) {
        $label = $clause.Item1
        if ($label -is [Management.Automation.Language.StringConstantExpressionAst]) {
            [string]$label.Value
            continue
        }
        $first = [regex]::Match($label.Extent.Text, "@\(\s*'([^']+)'")
        if ($first.Success) { [string]$first.Groups[1].Value }
    }
    return @($commands)
}

function Get-BeyinDoctorMutexName([string]$Vault) {
    $sha = [Security.Cryptography.SHA1]::Create()
    try {
        $hash = [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Vault.ToLowerInvariant()))) -replace '-', ''
    } finally { $sha.Dispose() }
    return 'Global\BeyinDoktor-' + $hash.Substring(0, 12)
}

function New-BeyinDoctorFixture {
    $vault = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path (Join-Path $vault 'motor\hooks'), (Join-Path $vault 'motor\scripts') | Out-Null
    Copy-Item -LiteralPath (Join-Path $root 'motor\hooks\lib.ps1') -Destination (Join-Path $vault 'motor\hooks\lib.ps1')
    return $vault
}

Describe 'Beyin dispatcher help parity' {
    It 'describes every canonical dispatcher command in the runtime help' {
        $savedVault = $env:BEYIN_VAULT
        try {
            $env:BEYIN_VAULT = $root
            $help = (& $powershell -NoProfile -ExecutionPolicy Bypass -File $dispatcher yardim | Out-String)
            $LASTEXITCODE | Should Be 0
            $missing = @(Get-BeyinCanonicalCommands | Where-Object {
                $help -notmatch ('(?m)^\s{2}' + [regex]::Escape($_) + '(?:\s|$)')
            })
            ($missing -join ', ') | Should Be ''
        } finally { $env:BEYIN_VAULT = $savedVault }
    }
}

Describe 'Beyin doctor mutex waiting' {
    It 'waits for the active doctor and continues after the mutex is released' {
        $vault = New-BeyinDoctorFixture
        $mutexName = Get-BeyinDoctorMutexName $vault
        $ready = Join-Path $TestDrive 'mutex-ready.txt'
        $holder = Join-Path $TestDrive 'hold-mutex.ps1'
        Set-Content -LiteralPath $holder -Encoding UTF8 -Value @'
param([string]$Name, [int]$HoldMs, [string]$Ready)
$mutex = New-Object Threading.Mutex($false, $Name)
$owned = $false
try {
    $owned = $mutex.WaitOne(5000)
    if (-not $owned) { exit 5 }
    [IO.File]::WriteAllText($Ready, 'ready')
    Start-Sleep -Milliseconds $HoldMs
} finally {
    if ($owned) { $mutex.ReleaseMutex() }
    $mutex.Dispose()
}
'@
        $process = Start-Process -FilePath $powershell -WindowStyle Hidden -PassThru -ArgumentList @(
            '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $holder,
            '-Name', $mutexName, '-HoldMs', '1200', '-Ready', $ready
        )
        try {
            $deadline = (Get-Date).AddSeconds(5)
            while (-not (Test-Path -LiteralPath $ready) -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 50 }
            (Test-Path -LiteralPath $ready) | Should Be $true
            $watch = [Diagnostics.Stopwatch]::StartNew()
            $output = (& $powershell -NoProfile -ExecutionPolicy Bypass -File $doctor -Vault $vault -Ozet -SureSiniri 1 -BeklemeSiniri 5 2>&1 | Out-String)
            $code = $LASTEXITCODE
            $watch.Stop()
            $code | Should Not Be 3
            $output | Should Not Match 'DOKTOR ZATEN CALISIYOR'
            $output | Should Match 'BEYIN DURUMU'
            ($watch.Elapsed.TotalMilliseconds -ge 800) | Should Be $true
        } finally {
            if (-not $process.HasExited) { $process.WaitForExit(5000) | Out-Null }
            if (-not $process.HasExited) { $process.Kill() }
            $process.Dispose()
        }
    }

    It 'returns code 3 when the mutex wait limit expires' {
        $vault = New-BeyinDoctorFixture
        $mutex = New-Object Threading.Mutex($false, (Get-BeyinDoctorMutexName $vault))
        $owned = $false
        try {
            $owned = $mutex.WaitOne(1000)
            $owned | Should Be $true
            $watch = [Diagnostics.Stopwatch]::StartNew()
            $output = (& $powershell -NoProfile -ExecutionPolicy Bypass -File $doctor -Vault $vault -Ozet -SureSiniri 1 -BeklemeSiniri 1 2>&1 | Out-String)
            $code = $LASTEXITCODE
            $watch.Stop()
            $code | Should Be 3
            $output | Should Match 'DOKTOR ZATEN CALISIYOR'
            ($watch.Elapsed.TotalMilliseconds -ge 800) | Should Be $true
            ($watch.Elapsed.TotalSeconds -lt 5) | Should Be $true
        } finally {
            if ($owned) { $mutex.ReleaseMutex() }
            $mutex.Dispose()
        }
    }
}
