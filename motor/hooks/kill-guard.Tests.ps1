# kill-guard.Tests.ps1 - BB5 (2026-10-06): pre-tool-use.ps1 surec oldurme korumasi.
$here = $PSScriptRoot
$vault = Split-Path (Split-Path $here -Parent) -Parent
. (Join-Path $here 'lib.ps1')
$p = Get-BeyinPaths -Vault $vault
# Guard'in makbuzlari GERCEK vault'a dusmesin (doktor 'kill guard' satiri onlari sayar):
# guard, BEYIN_VAULT ile lib'i kopyalanmis gecici bir vault'a yonlendirilir.
$kgVault = Join-Path $env:TEMP ('beyin-kg-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path (Join-Path $kgVault 'motor\hooks'), (Join-Path $kgVault 'motor\scripts\.state\sessions') | Out-Null
Copy-Item (Join-Path $here 'lib.ps1') (Join-Path $kgVault 'motor\hooks\lib.ps1')
Copy-Item (Join-Path $here 'pre-tool-use.ps1') (Join-Path $kgVault 'motor\hooks\pre-tool-use.ps1')
Set-Content -Path (Join-Path $kgVault '.beyin-version') -Value '1.0.0'

function Invoke-Guard($Komut, [hashtable]$Env = @{}) {
    $in  = Join-Path $env:TEMP ("kg-in-" + [guid]::NewGuid().ToString('N') + '.json')
    $err = Join-Path $env:TEMP ("kg-err-" + [guid]::NewGuid().ToString('N') + '.txt')
    $payload = @{ session_id = 'kg-test'; hook_event_name = 'PreToolUse'; tool_name = 'Bash'; tool_input = @{ command = $Komut }; cwd = $vault }
    [IO.File]::WriteAllText($in, ($payload | ConvertTo-Json -Compress -Depth 4), (New-Object Text.UTF8Encoding $false))
    $eski = @{}
    if (-not $Env.ContainsKey('BEYIN_VAULT')) { $Env['BEYIN_VAULT'] = $kgVault }
    foreach ($k in $Env.Keys) { $eski[$k] = [Environment]::GetEnvironmentVariable($k); [Environment]::SetEnvironmentVariable($k, $Env[$k]) }
    try {
        cmd /c "powershell -NoProfile -ExecutionPolicy Bypass -File `"$(Join-Path $here 'pre-tool-use.ps1')`" < `"$in`" 2> `"$err`"" | Out-Null
        $kod = $LASTEXITCODE
        return @{ Kod = $kod; Err = $(if (Test-Path $err) { [IO.File]::ReadAllText($err) } else { '' }) }
    } finally {
        foreach ($k in $Env.Keys) { [Environment]::SetEnvironmentVariable($k, $eski[$k]) }
        Remove-Item -LiteralPath $in, $err -Force -ErrorAction SilentlyContinue
    }
}

Describe 'kill guard (BB5)' {
    It 'ajanlari AD ile toptan olduren komutlar reddedilir (exit 2, gerekce stderr)' {
        foreach ($k in @('taskkill /IM node.exe /F', 'taskkill /F /IM "claude.exe"', 'Stop-Process -Name codex -Force', 'Get-Process node | Stop-Process', 'pkill -9 node', 'wmic process where name="node.exe" delete')) {
            $r = Invoke-Guard $k
            $r.Kod | Should Be 2
            $r.Err | Should Match 'kill guard'
        }
    }
    It 'Codex dizi bicimli komut da yakalanir' {
        $r = Invoke-Guard @('powershell', '-Command', 'Stop-Process -Name node')
        $r.Kod | Should Be 2
    }
    It 'korunan PID (testi calistiran surec = guard''in atasi) reddedilir, var olmayan PID gecer' {
        (Invoke-Guard "taskkill /PID $PID /F").Kod | Should Be 2
        (Invoke-Guard "Stop-Process -Id $PID").Kod | Should Be 2
        (Invoke-Guard 'taskkill /PID 999991 /F').Kod | Should Be 0
    }
    It 'insan onayi kayitlarina dokunan komut reddedilir' {
        (Invoke-Guard 'Remove-Item motor\scripts\.state\approvals\TASK-1.json').Kod | Should Be 2
        (Invoke-Guard 'echo {} > motor/scripts/.state/korunan-pid.json').Kod | Should Be 2
    }
    It 'zararsiz komutlar, PID okuyan ama oldurmeyen komutlar ve kapali ayar gecer' {
        (Invoke-Guard 'git status').Kod | Should Be 0
        (Invoke-Guard "Get-Process -Id $PID | Format-List").Kod | Should Be 0
        (Invoke-Guard 'taskkill /IM node.exe /F' @{ BEYIN_KILL_GUARD = 'kapali' }).Kod | Should Be 0
        (Invoke-Guard 'taskkill /IM node.exe /F' @{ BEYIN_CHILD = '1' }).Kod | Should Be 0
    }
    It 'node on filtresi: zararsiz komut PowerShell acmadan gecer, oldurme komutu launcher uzerinden exit 2' {
        $launcher = Join-Path $env:USERPROFILE '.beyin\beyin-launcher.ps1'
        if (-not (Test-Path -LiteralPath $launcher) -or -not (Get-Command node -ErrorAction SilentlyContinue)) { Set-TestInconclusive 'launcher ya da node yok'; return }
        $mjs = Join-Path $here 'kill-guard-on.mjs'
        $sonuc = @{}
        foreach ($k in @('git status', 'taskkill /IM node.exe /F', 'kill-guard-on.mjs dosyasina bak')) {
            $in = Join-Path $env:TEMP ("kgon-" + [guid]::NewGuid().ToString('N') + '.json')
            [IO.File]::WriteAllText($in, (@{ tool_name = 'Bash'; tool_input = @{ command = $k } } | ConvertTo-Json -Compress), (New-Object Text.UTF8Encoding $false))
            $eskiV = $env:BEYIN_VAULT; $env:BEYIN_VAULT = $kgVault
            try { cmd /c "node `"$mjs`" < `"$in`" 2>nul" | Out-Null; $sonuc[$k] = $LASTEXITCODE }
            finally { $env:BEYIN_VAULT = $eskiV; Remove-Item -LiteralPath $in -Force -ErrorAction SilentlyContinue }
        }
        $sonuc['git status'] | Should Be 0
        $sonuc['taskkill /IM node.exe /F'] | Should Be 2
        $sonuc['kill-guard-on.mjs dosyasina bak'] | Should Be 0
    }
    It 'anlik aktarim: calisan ajana PreToolUse additionalContext ile bir kez teslim, projeye sinirli olan baska projede gelmez' {
        if (-not (Get-Command node -ErrorAction SilentlyContinue)) { Set-TestInconclusive 'node yok'; return }
        $hd = Join-Path $kgVault 'motor\scripts\.state\handoff'
        New-Item -ItemType Directory -Force -Path $hd | Out-Null
        $ts = (Get-Date).ToString('o')
        @(
            @{ v = 2; id = '20991231T000001-aaaa'; ts = $ts; from = @{ agent = 'claude'; project = 'Beyin' }; to = 'codex'; toProject = ''; kind = 'soru'; question = 'ANLIK-HER-YERE'; status = 'acik' },
            @{ v = 2; id = '20991231T000002-bbbb'; ts = $ts; from = @{ agent = 'claude'; project = 'Beyin' }; to = 'codex'; toProject = 'baska-proje'; kind = 'soru'; question = 'ANLIK-SINIRLI'; status = 'acik' },
            @{ v = 2; id = '20991231T000003-cccc'; ts = $ts; from = @{ agent = 'codex'; project = 'codex-chef' }; to = 'codex'; toProject = ''; kind = 'devir'; question = 'ANLIK-DEVIR'; status = 'acik' }
        ) | ForEach-Object { [IO.File]::WriteAllText((Join-Path $hd "$($_.id).json"), ($_ | ConvertTo-Json -Compress -Depth 4)) }
        $in = Join-Path $env:TEMP ("anlik-" + [guid]::NewGuid().ToString('N') + '.json')
        [IO.File]::WriteAllText($in, (@{ session_id = 'anlik-test-1'; tool_name = 'Bash'; tool_input = @{ command = 'git status' }; cwd = 'D:\proje\codex-chef' } | ConvertTo-Json -Compress), (New-Object Text.UTF8Encoding $false))
        $mjs = Join-Path $here 'kill-guard-on.mjs'
        $eskiV = $env:BEYIN_VAULT; $env:BEYIN_VAULT = $kgVault
        try {
            $o1 = [string](cmd /c "node `"$mjs`" --codex < `"$in`"")
            $o2 = [string](cmd /c "node `"$mjs`" --codex < `"$in`"")
        } finally { $env:BEYIN_VAULT = $eskiV; Remove-Item -LiteralPath $in -Force -ErrorAction SilentlyContinue }
        $o1 | Should Match 'additionalContext'
        $o1 | Should Match 'ANLIK-HER-YERE'
        $o1 | Should Not Match 'ANLIK-SINIRLI'
        $o1 | Should Not Match 'ANLIK-DEVIR'
        [string]::IsNullOrWhiteSpace($o2) | Should Be $true
    }
    It 'teslim hakki: atomik, ikinci talep reddedilir; PowerShell yolunun aldigini node vermez; alt ajan cagrisi atlanir' {
        if (-not (Get-Command node -ErrorAction SilentlyContinue)) { Set-TestInconclusive 'node yok'; return }
        $kp = Get-BeyinPaths -Vault $kgVault
        $hd = Join-Path $kgVault 'motor\scripts\.state\handoff'
        New-Item -ItemType Directory -Force -Path $hd | Out-Null
        $ts = (Get-Date).ToString('o')
        @{ v = 2; id = '20991231T000010-dddd'; ts = $ts; from = @{ agent = 'claude'; project = 'Beyin' }; to = 'codex'; toProject = ''; kind = 'soru'; question = 'HAK-PS-ALDI'; status = 'acik' },
        @{ v = 2; id = '20991231T000011-eeee'; ts = $ts; from = @{ agent = 'claude'; project = 'Beyin' }; to = 'codex'; toProject = ''; kind = 'soru'; question = 'HAK-SERBEST'; status = 'acik' } |
            ForEach-Object { [IO.File]::WriteAllText((Join-Path $hd "$($_.id).json"), ($_ | ConvertTo-Json -Compress -Depth 4)) }
        $ilk = Request-BeyinTeslimHakki -Paths $kp -SessionKey 'hak-test' -Id '20991231T000010-dddd'
        $ikinci = Request-BeyinTeslimHakki -Paths $kp -SessionKey 'hak-test' -Id '20991231T000010-dddd'
        $mjs = Join-Path $here 'kill-guard-on.mjs'
        $in = Join-Path $env:TEMP ("hak-" + [guid]::NewGuid().ToString('N') + '.json')
        $inAlt = Join-Path $env:TEMP ("hak-alt-" + [guid]::NewGuid().ToString('N') + '.json')
        [IO.File]::WriteAllText($in, (@{ session_id = 'hak-test'; tool_name = 'Bash'; tool_input = @{ command = 'git status' }; cwd = 'D:\proje\codex-chef' } | ConvertTo-Json -Compress), (New-Object Text.UTF8Encoding $false))
        [IO.File]::WriteAllText($inAlt, (@{ session_id = 'hak-alt'; agent_id = 'sub-1'; tool_name = 'Bash'; tool_input = @{ command = 'git status' }; cwd = 'D:\proje\codex-chef' } | ConvertTo-Json -Compress), (New-Object Text.UTF8Encoding $false))
        $eskiV = $env:BEYIN_VAULT; $env:BEYIN_VAULT = $kgVault
        try {
            $o = [string](cmd /c "node `"$mjs`" --codex < `"$in`"")
            $oAlt = [string](cmd /c "node `"$mjs`" --codex < `"$inAlt`"")
        } finally { $env:BEYIN_VAULT = $eskiV; Remove-Item -LiteralPath $in, $inAlt -Force -ErrorAction SilentlyContinue }
        $ilk | Should Be $true
        $ikinci | Should Be $false
        $o | Should Match 'HAK-SERBEST'
        $o | Should Not Match 'HAK-PS-ALDI'
        [string]::IsNullOrWhiteSpace($oAlt) | Should Be $true
        (Get-BeyinTeslimEdilen -Paths $kp -SessionKey 'hak-test') -contains '20991231T000011-eeee' | Should Be $true
    }
    It 'paralel arac cagrilari: ayni oturumda 6 es zamanli kanca, mesaj TAM BIR KEZ verilir' {
        if (-not (Get-Command node -ErrorAction SilentlyContinue)) { Set-TestInconclusive 'node yok'; return }
        $hd = Join-Path $kgVault 'motor\scripts\.state\handoff'
        New-Item -ItemType Directory -Force -Path $hd | Out-Null
        $kayit = @{ v = 2; id = '20991231T000020-ffff'; ts = (Get-Date).ToString('o'); from = @{ agent = 'claude'; project = 'Beyin' }; to = 'codex'; toProject = ''; kind = 'soru'; question = 'PARALEL-TEK'; status = 'acik' }
        [IO.File]::WriteAllText((Join-Path $hd "$($kayit.id).json"), ($kayit | ConvertTo-Json -Compress -Depth 4))
        $in = Join-Path $env:TEMP ("par-" + [guid]::NewGuid().ToString('N') + '.json')
        [IO.File]::WriteAllText($in, (@{ session_id = 'paralel-test'; tool_name = 'Bash'; tool_input = @{ command = 'git status' }; cwd = 'D:\proje\codex-chef' } | ConvertTo-Json -Compress), (New-Object Text.UTF8Encoding $false))
        $mjs = Join-Path $here 'kill-guard-on.mjs'
        $surecler = @()
        try {
            foreach ($i in 1..6) {
                $psi = New-Object System.Diagnostics.ProcessStartInfo
                $psi.FileName = 'cmd.exe'; $psi.Arguments = "/d /c node `"$mjs`" --codex < `"$in`""
                $psi.UseShellExecute = $false; $psi.RedirectStandardOutput = $true; $psi.CreateNoWindow = $true
                $psi.EnvironmentVariables['BEYIN_VAULT'] = $kgVault
                $surecler += [System.Diagnostics.Process]::Start($psi)
            }
            $ciktilar = @($surecler | ForEach-Object { $o = $_.StandardOutput.ReadToEnd(); $_.WaitForExit(); $o })
        } finally { Remove-Item -LiteralPath $in -Force -ErrorAction SilentlyContinue }
        @($ciktilar | Where-Object { $_ -match 'PARALEL-TEK' }).Count | Should Be 1
    }
    It 'makbuzlar gecici vault''a yazilir (gercek vault kirlenmez)' {
        $null = Invoke-Guard 'taskkill /IM node.exe /F'
        $gun = (Get-Date).ToString('yyyy-MM-dd')
        $mk = Join-Path $kgVault "motor\scripts\.state\makbuz\$gun.jsonl"
        (Test-Path -LiteralPath $mk) | Should Be $true
        ([IO.File]::ReadAllText($mk)) | Should Match '"script":"kill-guard"'
    }
    It 'Get-BeyinKorunanPid ata zincirini icerir; Get-BeyinAtaZinciri kendini ilk sirada verir' {
        $z = @(Get-BeyinAtaZinciri -ProcessId $PID)
        [int]$z[0].Pid | Should Be $PID
        $k = Get-BeyinKorunanPid -Paths $p
        if ($z.Count -gt 1) { $k.ContainsKey([int]$z[1].Pid) | Should Be $true }
    }
}
Remove-Item -LiteralPath $kgVault -Recurse -Force -ErrorAction SilentlyContinue
