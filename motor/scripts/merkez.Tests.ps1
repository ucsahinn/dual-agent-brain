# merkez.Tests.ps1 - Beyin merkez veri katmani (durum kurali + anlik goruntu) ve ekran duman testi.
Describe 'merkez durum kurali (2026-10-15): kanittan tek durum, kaynak ve bayat bayragi' {
    BeforeAll { . (Join-Path $PSScriptRoot 'merkez-veri.ps1') }
    It 'lider: olmus surec kapali; taze nabiz calisiyor; kart claim; canli surec bosta; kanit yoksa kapali' {
        (Get-MerkezDurum @{ Tur = 'lider'; SurecCanli = $false; NabizSn = 5 }).Durum | Should Be 'kapali'
        $d = Get-MerkezDurum @{ Tur = 'lider'; SurecCanli = $true; NabizSn = 30 }; $d.Durum | Should Be 'calisiyor'; $d.Kaynak | Should Be 'nabiz'
        $d = Get-MerkezDurum @{ Tur = 'lider'; SurecCanli = $true; NabizSn = 900; KartDurum = 'in_progress' }; $d.Durum | Should Be 'calisiyor'; $d.Kaynak | Should Be 'kart'; $d.Bayat | Should Be $true
        (Get-MerkezDurum @{ Tur = 'lider'; SurecCanli = $true; NabizSn = 900; KartDurum = 'review' }).Durum | Should Be 'inceleme'
        (Get-MerkezDurum @{ Tur = 'lider'; SurecCanli = $true; NabizSn = 900; KartDurum = 'blocked' }).Durum | Should Be 'engelli'
        (Get-MerkezDurum @{ Tur = 'lider'; SurecCanli = $true; NabizSn = 900 }).Durum | Should Be 'bosta'
        (Get-MerkezDurum @{ Tur = 'lider'; SurecCanli = $null; NabizSn = 900 }).Durum | Should Be 'bosta'
        (Get-MerkezDurum @{ Tur = 'lider'; SurecCanli = $null; NabizSn = 99999 }).Durum | Should Be 'kapali'
    }
    It 'isci: kosu durumu, gozetmen, kota, karar ve sessizlik' {
        (Get-MerkezDurum @{ Tur = 'isci'; IsciDurum = 'running'; NabizSn = 10 }).Durum | Should Be 'calisiyor'
        (Get-MerkezDurum @{ Tur = 'isci'; IsciDurum = 'running'; NabizSn = 900 }).Bayat | Should Be $true
        $d = Get-MerkezDurum @{ Tur = 'isci'; IsciDurum = 'running'; NabizSn = 10; GozetmenDurdu = $true }; $d.Durum | Should Be 'engelli'; $d.Kaynak | Should Be 'gozetmen'
        (Get-MerkezDurum @{ Tur = 'isci'; IsciDurum = 'running'; NabizSn = 10; SurecCanli = $false }).Durum | Should Be 'engelli'
        (Get-MerkezDurum @{ Tur = 'isci'; IsciDurum = 'paused_limit' }).Durum | Should Be 'duraklatildi'
        (Get-MerkezDurum @{ Tur = 'isci'; IsciDurum = 'planned' }).Durum | Should Be 'bekliyor'
        (Get-MerkezDurum @{ Tur = 'isci'; IsciDurum = 'finished'; Verdict = 'pass' }).Durum | Should Be 'bitti'
        (Get-MerkezDurum @{ Tur = 'isci'; IsciDurum = 'collected'; Verdict = 'partial' }).Durum | Should Be 'inceleme'
        (Get-MerkezDurum @{ Tur = 'isci'; IsciDurum = 'integrated'; Verdict = 'fail' }).Durum | Should Be 'engelli'
        (Get-MerkezDurum @{ Tur = 'isci'; IsciDurum = 'timed_out' }).Durum | Should Be 'engelli'
        (Get-MerkezDurum @{ Tur = 'isci'; IsciDurum = 'aborted' }).Durum | Should Be 'kapali'
    }
    It 'metin koruma: sir maskeleme, tek satir, uzunluk' {
        Protect-MerkezSatir (('tok' + 'en=') + ('a' * 10)) | Should Be 'token=***'
        Protect-MerkezSatir ('x ' + ('Z9' * 20)) | Should Be 'x ***'
        (Protect-MerkezSatir ("a`nb")) | Should Be 'a b'
        (Protect-MerkezSatir ('ab ' * 40) 64).Length | Should Be 64
        $e = [char]27
        (Protect-MerkezSatir "a${e}[31mKIRMIZI${e}[0m b${e}]0;BASLIK$([char]7)c") | Should Be 'aKIRMIZI bc'
        Protect-MerkezSatir ('Author' + 'ization: Bea' + 'rer abc123') | Should Not Match 'abc123'
        Protect-MerkezSatir ('git clone https://kisi' + ':gizli' + '@host/x') | Should Be 'git clone https://***@host/x'
    }
    It 'lider: tur bitti -> bosta; uzun arac cagrisi 15 dk boyunca calisiyor' {
        (Get-MerkezDurum @{ Tur = 'lider'; SurecCanli = $true; NabizSn = 10; Etkinlik = 'bekliyor' }).Durum | Should Be 'bosta'
        $d = Get-MerkezDurum @{ Tur = 'lider'; SurecCanli = $true; NabizSn = 400; Etkinlik = 'arac' }; $d.Durum | Should Be 'calisiyor'; $d.Kaynak | Should Be 'uzun-arac'
        (Get-MerkezDurum @{ Tur = 'lider'; SurecCanli = $true; NabizSn = 1200; Etkinlik = 'arac' }).Durum | Should Be 'bosta'
    }
}

Describe 'merkez anlik goruntu (2026-10-15): kosular, isciler, liderler, onaylar, teshis' {
    BeforeAll {
        . (Join-Path (Split-Path $PSScriptRoot -Parent) 'hooks\lib.ps1')
        . (Join-Path $PSScriptRoot 'merkez-veri.ps1')
        $script:tv = Join-Path ([IO.Path]::GetTempPath()) ("merkez-test-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
        $script:tp = @{ Vault = $script:tv; Sessions = (Join-Path $script:tv 'sessions'); TeamRuns = (Join-Path $script:tv 'team-runs'); Board = (Join-Path $script:tv 'board.json'); ScrState = (Join-Path $script:tv 'scr'); Handoff = (Join-Path $script:tv 'handoff') }
        foreach ($d in @($script:tp.Sessions, $script:tp.TeamRuns, $script:tp.ScrState, $script:tp.Handoff)) { New-Item -ItemType Directory -Force -Path $d | Out-Null }
        $eski = (Get-Date).ToUniversalTime().AddMinutes(-10).ToString('o')
        $kosu = @{ runId = 'R-SAHIPSIZ'; repoName = 'demo'; status = 'running'; supervisor = @{ pid = 999999; heartbeatAt = $eski }
                   workers = @(@{ taskId = 'TASK-1'; role = 'docs_author'; status = 'running'; pid = $null; startedAt = $eski }, @{ taskId = 'TASK-2'; role = 'qa_lead'; status = 'paused_limit' }) }
        Set-Content -LiteralPath (Join-Path $script:tp.TeamRuns 'R-SAHIPSIZ.json') -Value ($kosu | ConvertTo-Json -Depth 6) -Encoding UTF8
        $onay = @{ runId = 'R-ONAY'; repoName = 'demo'; status = 'verified'; workers = @(@{ taskId = 'TASK-3'; role = 'qa_lead'; status = 'integrated'; verdict = 'pass' }) }
        Set-Content -LiteralPath (Join-Path $script:tp.TeamRuns 'R-ONAY.json') -Value ($onay | ConvertTo-Json -Depth 6) -Encoding UTF8
        $board = @{ schemaVersion = 4; tasks = @(@{ id = 'TASK-9'; title = 'inceleme bekleyen kart'; status = 'review' }, @{ id = 'TASK-8'; title = 'bitmis'; status = 'done' }) }
        Set-Content -LiteralPath $script:tp.Board -Value ($board | ConvertTo-Json -Depth 6) -Encoding UTF8
        $ses = @{ agent = 'claude'; pid = $PID; cwd = $script:tv; prompts = 3; start = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() }
        Set-Content -LiteralPath (Join-Path $script:tp.Sessions 'oturum-canli.json') -Value ($ses | ConvertTo-Json) -Encoding UTF8
        $isciSes = @{ agent = 'codex'; pid = $PID; cwd = $script:tv; takimRun = 'R-SAHIPSIZ'; takimKart = 'TASK-1' }
        Set-Content -LiteralPath (Join-Path $script:tp.Sessions 'oturum-isci.json') -Value ($isciSes | ConvertTo-Json) -Encoding UTF8
        $script:an = Get-MerkezAnlik -Paths $script:tp
    }
    AfterAll { Remove-Item -LiteralPath $script:tv -Recurse -Force -ErrorAction SilentlyContinue }
    It 'sahipsiz kosunun calisan iscisi engelli/gozetmen; kota iscisi duraklatildi; teshiste resume onerisi' {
        $t1 = @($script:an.Ajanlar | Where-Object { $_.Ad -eq 'TASK-1' })[0]
        $t1.Durum | Should Be 'engelli'; $t1.Kaynak | Should Be 'gozetmen'
        @($script:an.Ajanlar | Where-Object { $_.Ad -eq 'TASK-2' })[0].Durum | Should Be 'duraklatildi'
        (@($script:an.Teshis | ForEach-Object { $_.Metin }) -join '|') | Should Match 'R-SAHIPSIZ sahipsiz'
        @($script:an.Kosular | Where-Object { $_.RunId -eq 'R-SAHIPSIZ' })[0].Sahipsiz | Should Be $true
    }
    It 'onay bekleyenler: dogrulanmis kosu birlestir, review kart onayla' {
        $satirlar = @($script:an.Onaylar | ForEach-Object { $_.Satir })
        $satirlar -contains 'birlestir R-ONAY' | Should Be $true
        $satirlar -contains 'onayla TASK-9' | Should Be $true
        @($script:an.Kartlar).Count | Should Be 1
    }
    It 'lider canli surecle gorunur; isci oturumu lider olarak tekrar sayilmaz' {
        $l = @($script:an.Ajanlar | Where-Object { $_.Tur -eq 'lider' })
        $l.Count | Should Be 1
        $l[0].Ad | Should Be 'oturum-canli'
        $l[0].Durum | Should Be 'calisiyor'
    }
}

Describe 'merkez veri + balon birlikte (2026-10-15): ad cakismasi yok' {
    It 'iki modul ayni oturumda yuklenince isci balonu ve satir temizligi calisir' {
        . (Join-Path $PSScriptRoot 'merkez-veri.ps1'); . (Join-Path $PSScriptRoot 'merkez-balon.ps1')
        $d = Join-Path ([IO.Path]::GetTempPath()) ("merkez-ev-" + [guid]::NewGuid().ToString('N').Substring(0, 8)); New-Item -ItemType Directory -Force -Path $d | Out-Null
        try {
            $ev = Join-Path $d 'events.jsonl'
            Set-Content -LiteralPath $ev -Encoding UTF8 -Value @('{"type":"item.completed","item":{"type":"reasoning","text":"x"}}', '{"type":"item.completed","item":{"type":"command_execution","command":"npm test"}}')
            Get-MerkezIsciEtkinlik $ev | Should Be '▸ npm test'
            (Protect-MerkezSatir ("satir1`nsatir2") 64) | Should Be 'satir1 satir2'
        } finally { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

Describe 'merkez ekrani (2026-10-15): tek kare duman testi' {
    It 'merkez.ps1 -Tek hatasiz bir kare cizer ve baslik/bolumleri icerir' {
        $vault = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
        $cikti = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'merkez.ps1') -Vault $vault -Tek 2>&1 | Out-String
        $LASTEXITCODE | Should Be 0
        $cikti | Should Match 'merkez'
        $cikti | Should Match 'Pano'
        $cikti | Should Match 'Aktar'
        $cikti | Should Not Match 'Exception'
    }
}
