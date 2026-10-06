# skill-aday.Tests.ps1 - BB4 (2026-10-06): aday olcutu sentetik makbuz + kavram notuyla.
$vault = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$powershell = Join-Path $PSHOME 'powershell.exe'

Describe 'beyin skill-aday (BB4)' {
    It '3 oturum + 2 gun + liste -> aday; Ilgili notlar sayilmaz; tek gunluk tekrar aday degil' {
        $tv = Join-Path $env:TEMP ('beyin-skill-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        $mk = Join-Path $tv 'motor\scripts\.state\makbuz'
        $cd = Join-Path $tv '86-compiled\concepts'
        New-Item -ItemType Directory -Force -Path (Join-Path $tv 'motor\hooks'), $mk, $cd | Out-Null
        Copy-Item (Join-Path $vault 'motor\hooks\lib.ps1') (Join-Path $tv 'motor\hooks\lib.ps1')
        Copy-Item (Join-Path $vault 'motor\scripts\skill-aday.ps1') (Join-Path $tv 'motor\scripts\skill-aday.ps1')
        Set-Content -Path (Join-Path $tv '.beyin-version') -Value '1.0.0'
        $utf8 = New-Object System.Text.UTF8Encoding($false)
        [IO.File]::WriteAllText((Join-Path $cd 'yordam-notu.md'), "---`ntitle: `"Yordam Notu`"`n---`n# Yordam`n1. bir`n2. iki`n3. uc`n", $utf8)
        [IO.File]::WriteAllText((Join-Path $cd 'duz-not.md'), "---`ntitle: `"Duz`"`n---`nDuz yazi.`n## Ilgili notlar`n- [[a]]`n- [[b]]`n- [[c]]`n- [[d]]`n", $utf8)
        [IO.File]::WriteAllText((Join-Path $cd 'tek-gun.md'), "---`ntitle: `"Tek`"`n---`n1. a`n2. b`n3. c`n", $utf8)
        $bugun = Get-Date; $dun = $bugun.AddDays(-1)
        function Satir($T, $K, $C) { '{"v":1,"ts":"' + $T.ToString('o') + '","script":"retrieval","outcome":"ENJEKSIYON","key":"' + $K + '","concepts":[' + (($C | ForEach-Object { '"' + $_ + '"' }) -join ',') + ']}' }
        [IO.File]::WriteAllText((Join-Path $mk ($dun.ToString('yyyy-MM-dd') + '.jsonl')), ((Satir $dun 'k1' @('yordam-notu.md', 'duz-not.md')) + "`n"), $utf8)
        [IO.File]::WriteAllText((Join-Path $mk ($bugun.ToString('yyyy-MM-dd') + '.jsonl')), (@(
            (Satir $bugun 'k2' @('yordam-notu.md', 'duz-not.md', 'tek-gun.md')),
            (Satir $bugun 'k3' @('yordam-notu.md', 'duz-not.md', 'tek-gun.md')),
            (Satir $bugun 'k4' @('tek-gun.md'))) -join "`n") + "`n", $utf8)
        try { $j = & $powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $tv 'motor\scripts\skill-aday.ps1') -Vault $tv -Json 2>&1 | Out-String | ConvertFrom-Json
              $md = Test-Path -LiteralPath (Join-Path $tv '86-compiled\skill-adaylari.md') }
        finally { Remove-Item -LiteralPath $tv -Recurse -Force -ErrorAction SilentlyContinue }
        [int]$j.aday | Should Be 1
        [string]$j.adaylar[0].dosya | Should Be 'yordam-notu.md'
        [int]$j.adaylar[0].oturum | Should Be 3
        $md | Should Be $true
    }
}
