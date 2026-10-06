# doktor.Tests.ps1 - doktor.ps1'in yetim/sure/tek-kopya kapilari (2026-10-03).
#
# Olculen sorun: bes ebeveynsiz 'doktor -Ozet' ayni anda, her biri ~200 MB ve
# altinda 972 ayri 'git show' cocugu. Bu testler uc kapiyi ve git grep
# tekillestirmesini kilitler. Gercek vault'a karsi SALT-OKUNUR kosarlar
# (doktor hicbir sey yazmaz); her -Ozet kosusu ~30 sn surer.

$doktor = Join-Path $PSScriptRoot 'doktor.ps1'
$vault = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$powershell = (Get-Command powershell.exe -ErrorAction Stop).Source

function Invoke-Doktor {
    # '$Args' adi KULLANILAMAZ: PowerShell'in otomatik degiskeniyle cakisir ve
    # splat bos gider (ilk surumde -Ozet hic gecmedi, test tam tabloyu okudu).
    param([string[]]$Argumanlar)
    $out = & $powershell -NoProfile -ExecutionPolicy Bypass -File $doktor -Vault $vault @Argumanlar 2>&1 | Out-String
    return @{ Exit = $LASTEXITCODE; Out = $out }
}

# Baska bir doktor zaten calisiyorsa (orkestrator olcumu, zamanlayici, kullanici) mutex
# dogru calisarak bu testlerin kendi kopyalarini 3 ile dusurur ve testler YANLIS kirmizi
# olur (olculdu: 2/4). Bu durumda sure/mutex/ebeveyn testleri atlanir, sebebi yazilir.
$baskaDoktor = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -like '*doktor.ps1*' -and $_.ProcessId -ne $PID }).Count -gt 0
if ($baskaDoktor) { Write-Host "doktor.Tests: baska bir doktor sureci calisiyor; mutex/sure/ebeveyn testleri ATLANDI (tekrar: beklet ve yeniden kos)" -ForegroundColor Yellow }

Describe 'doktor.ps1 yetim ve sure kapilari' {
    It 'sozdizimi temiz ve git gecmisi tek git grep cagrisi kullaniyor (dosya basina git show yok)' {
        $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($doktor, [ref]$null, [ref]$errors)
        @($errors).Count | Should Be 0
        $src = Get-Content -LiteralPath $doktor -Raw -Encoding UTF8
        $src | Should Match 'git -C \$Vault grep -I -l -P'
        $src | Should Not Match 'git -C \$Vault show \("HEAD:"'
    }

    It '-SureSiniri 1 ile agir kontroller ATLANDI olarak raporlanir ve kosu yine 0 ile biter' -Skip:$baskaDoktor {
        $sw = [Diagnostics.Stopwatch]::StartNew()
        $r = Invoke-Doktor @('-Ozet', '-SureSiniri', '1')
        $sw.Stop()
        $r.Exit | Should Be 0
        $r.Out | Should Match 'ATLANDI'
        $r.Out | Should Match 'yetim adaylari \(7 gun\)'
        $sw.Elapsed.TotalSeconds | Should BeLessThan 90
    }

    It 'ayni vault icin ikinci doktor beklemeden 3 ile cikar (named mutex)' -Skip:$baskaDoktor {
        $ilk = Start-Process $powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$doktor`" -Vault `"$vault`" -Ozet -SureSiniri 0" -PassThru -WindowStyle Hidden
        try {
            Start-Sleep -Seconds 4
            $sw = [Diagnostics.Stopwatch]::StartNew()
            $r = Invoke-Doktor @('-Ozet')
            $sw.Stop()
            $r.Exit | Should Be 3
            $r.Out | Should Match 'ZATEN CALISIYOR'
            $sw.Elapsed.TotalSeconds | Should BeLessThan 10
        } finally {
            $ilk | Wait-Process -Timeout 180 -ErrorAction SilentlyContinue
            if (-not $ilk.HasExited) { Stop-Process -Id $ilk.Id -Force -ErrorAction SilentlyContinue }
        }
    }

    It 'ebeveyn surec olunce doktor kendini kapatir (cikis 4) ve engine.log''a yazar' -Skip:$baskaDoktor {
        $outer = Start-Process $powershell -ArgumentList "-NoProfile -Command `"& '$powershell' -NoProfile -ExecutionPolicy Bypass -File '$doktor' -Vault '$vault' -Ozet -SureSiniri 0 | Out-Null`"" -PassThru -WindowStyle Hidden
        # Yuk altinda ic surec 4 sn'de dogmayabiliyor (olculdu); 20 sn'ye kadar yokla.
        $inner = @(); $bekle = 0
        while ($inner.Count -eq 0 -and $bekle -lt 20) {
            Start-Sleep -Seconds 1; $bekle++
            $inner = @(Get-CimInstance Win32_Process -Filter "ParentProcessId = $($outer.Id)" | Where-Object { $_.CommandLine -like '*doktor.ps1*' })
        }
        if ($inner.Count -ne 1) { Stop-Process -Id $outer.Id -Force -ErrorAction SilentlyContinue }
        $inner.Count | Should Be 1
        Stop-Process -Id $outer.Id -Force
        $t = 0
        while ((Get-Process -Id $inner[0].ProcessId -ErrorAction SilentlyContinue) -and $t -lt 30) { Start-Sleep -Seconds 1; $t++ }
        [bool](Get-Process -Id $inner[0].ProcessId -ErrorAction SilentlyContinue) | Should Be $false
        $log = Get-Content -LiteralPath (Join-Path $vault 'motor\scripts\.state\engine.log') -Tail 20 -Encoding UTF8
        @($log | Where-Object { $_ -match 'doktor: ebeveyn surec \(' + $outer.Id + '\) oldu' }).Count | Should BeGreaterThan 0
    }
}

Describe 'doktor.ps1 ucuncu durum (OLCULEMEDI) ve yeni problar' {
    It 'olculemeyen kontrol SORUN sayilmaz, ozette OLCULEMEDI sayimi ve ? on ekiyle gorunur, cikis 0' -Skip:$baskaDoktor {
        # auto-memory kokunu bir DOSYAYA yonlendir: prob olcum yapamaz -> OLCULEMEDI.
        $sahte = Join-Path $env:TEMP ("beyin-am-" + [guid]::NewGuid().ToString('N') + '.txt')
        [IO.File]::WriteAllText($sahte, 'klasor degil')
        $eski = $env:BEYIN_CLAUDE_PROJECTS
        $env:BEYIN_CLAUDE_PROJECTS = $sahte
        try { $r = Invoke-Doktor @('-Ozet', '-SureSiniri', '1') }
        finally { $env:BEYIN_CLAUDE_PROJECTS = $eski; Remove-Item -LiteralPath $sahte -Force -ErrorAction SilentlyContinue }
        $r.Exit | Should Be 0
        $r.Out | Should Match 'OLCULEMEDI \d+: [^\r\n]*auto-memory'
        $r.Out | Should Not Match '- auto-memory:'
    }

    It 'auto-memory: MEMORY.md''de listelenmeyen not SORUN olarak raporlanir' -Skip:$baskaDoktor {
        $kok = Join-Path $env:TEMP ("beyin-amk-" + [guid]::NewGuid().ToString('N'))
        $md = Join-Path $kok 'C--ornek-proje\memory'
        New-Item -ItemType Directory -Force -Path $md | Out-Null
        [IO.File]::WriteAllText((Join-Path $md 'MEMORY.md'), "- [Bir](bir.md) - listeli`n")
        [IO.File]::WriteAllText((Join-Path $md 'bir.md'), 'not')
        [IO.File]::WriteAllText((Join-Path $md 'iki.md'), 'listelenmemis not')
        $eski = $env:BEYIN_CLAUDE_PROJECTS
        $env:BEYIN_CLAUDE_PROJECTS = $kok
        try { $r = Invoke-Doktor @('-Ozet', '-SureSiniri', '1') }
        finally { $env:BEYIN_CLAUDE_PROJECTS = $eski; Remove-Item -LiteralPath $kok -Recurse -Force -ErrorAction SilentlyContinue }
        $r.Exit | Should Be 0
        $r.Out | Should Match '- auto-memory: [^\r\n]*1 listelenmemis \(iki\.md\)'
    }
}
