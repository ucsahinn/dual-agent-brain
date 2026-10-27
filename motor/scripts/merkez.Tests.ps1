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

Describe 'merkez kosu ozeti ve siradaki adim' {
    BeforeAll { . (Join-Path $PSScriptRoot 'merkez-veri.ps1') }
    It 'kosu ozeti fixture turlerinde adimlari, rozetleri, sayaclari ve tokenlari toplar' {
        $cases = @(
            @{ Run = @{ status='planned'; workers=@() }; Current=1; Badge='onay' },   # plan tamam, sirada baslat (koşu panosu kurali)
            @{ Run = @{ status='running'; workers=@(@{status='running'; changedPaths=@('a'); usage=@{input_tokens=11;output_tokens=2;cached_input_tokens=1}}) }; Current=2; Badge='calisiyor' },   # basladi: sirada topla
            @{ Run = @{ status='running'; workers=@(@{status='paused_limit'; changedPaths=@(); usage=@{input_tokens=3;output_tokens=4;cached_input_tokens=2}}) }; Current=2; Badge='sef' },   # kota rozeti yalniz 'paused' kosuda (koşu panosu)
            @{ Run = @{ status='paused'; workers=@(@{status='paused_limit'}) }; Current=2; Badge='kota' },
            @{ Run = @{ status='integrated'; integration=@{ ok=$false; checks=@(@{command='a';status=0},@{command='b';status=1}) }; workers=@(@{status='integrated';verdict='fail'}) }; Current=3; Badge='kontrol' },   # gercek sema: ok + status (0 = gecti)
            @{ Run = @{ status='verified'; workers=@(@{status='integrated';verdict='pass'}) }; Current=5; Badge='dogrulandi' },
            @{ Run = @{ status='merged'; workers=@(@{status='integrated';verdict='pass'}) }; Current=6; Badge='anadalda' },
            @{ Run = @{ status='aborted'; workers=@(@{status='aborted'}) }; Current=1; Badge='iptal' }
        )
        foreach ($c in $cases) {
            $o = Get-MerkezKosuOzet $c.Run
            $o.Adimlar.Count | Should Be 6
            $o.Guncel | Should Be $c.Current
            $o.Rozet | Should Be $c.Badge
            $o.Kirik | Should Be ($c.Badge -in @('kontrol','iptal'))
            ($o.JetonGiris -ge 0) | Should Be $true
            ($o.JetonCikis -ge 0) | Should Be $true
            ($o.JetonOnbellek -ge 0) | Should Be $true
            $o.Kontrol.ContainsKey('Gecen') | Should Be $true
            $o.Kontrol.ContainsKey('Toplam') | Should Be $true
        }
        $tok = Get-MerkezKosuOzet @{ status='running'; workers=@(@{status='running';usage=@{input_tokens=11;output_tokens=2;cached_input_tokens=1}},@{status='finished';usage=@{input_tokens=7;output_tokens=5;cached_input_tokens=3}}) }
        $tok.JetonGiris | Should Be 18
        $tok.JetonCikis | Should Be 7
        $tok.JetonOnbellek | Should Be 4
    }
    It 'sirada onay satiri hata teshisini ve bitmemis kosuyu gecer' {
        (Get-MerkezSirada @{ Onaylar=@(@{Satir='onayla TASK-1'}); Teshis=@(@{Seviye='err';Metin='hata'}); Kosular=@(@{Guncel=1}) }).Neden | Should Match 'onay'
        (Get-MerkezSirada @{ Onaylar=@(); Teshis=@(@{Seviye='err';Metin='hata'}); Kosular=@(@{Guncel=1}) }).Renk | Should Be 'err'
        (Get-MerkezSirada @{ Onaylar=@(); Teshis=@(); Kosular=@(@{Guncel=2}) }).Renk | Should Be 'warn'
        (Get-MerkezSirada @{ Onaylar=@(); Teshis=@(); Kosular=@() }).Renk | Should Be 'ok'
    }
}

Describe 'merkez tek kare boyut ve enjeksiyon regresyonu' {
    It '90, 120 ve 170 sutunda temiz gecici vault ile cizer' {
        $root = Join-Path ([IO.Path]::GetTempPath()) ('merkez-render-' + [guid]::NewGuid().ToString('N'))
        $motor = Join-Path $root 'motor'; $scripts = Join-Path $motor 'scripts'; $hooks = Join-Path $motor 'hooks'
        New-Item -ItemType Directory -Force -Path $scripts,$hooks | Out-Null
        try {
            Copy-Item (Join-Path $PSScriptRoot 'merkez*.ps1') $scripts; Copy-Item (Join-Path $PSScriptRoot 'beyin-ciz.ps1') $scripts
            Copy-Item (Join-Path $PSScriptRoot 'takim-uyum.ps1') $scripts
            Copy-Item (Join-Path (Split-Path $PSScriptRoot -Parent) 'hooks\lib.ps1') $hooks
            foreach ($width in @(90,120,170)) {
                # Alt surec UTF-8 yazar; ust surec de UTF-8 okumali, yoksa her cerceve karakteri birkac karaktere bolunur.
                $eskiKod = [Console]::OutputEncoding; [Console]::OutputEncoding = [Text.Encoding]::UTF8
                try { $out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scripts 'merkez.ps1') -Vault $root -Tek -Genislik $width -Yukseklik 50 2>&1 | Out-String } finally { [Console]::OutputEncoding = $eskiKod }
                $LASTEXITCODE | Should Be 0
                $esc = [string][char]27; $bel = [string][char]7; $plain = [regex]::Replace([regex]::Replace($out, ($esc + '\[[0-9;?]*[A-Za-z]'), ''), ($esc + '\][^' + $bel + ']*' + $bel + '?'), '')   # PS 5.1: `e kacisi yok
                foreach ($line in ($plain -split "`r?`n")) { $line.Length | Should BeLessThan ($width + 1) }
                foreach ($label in @('SIRADA','KANATLAR','KO','PANO','TE')) { $plain | Should Match $label }
            }
        } finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
    }
    It 'handoff ve kart basligindaki kontrol karakterleri satir veya OSC baslik enjeksiyonu yapmaz' {
        $safe = Protect-MerkezSatir ("soru`n`e]0;INJECT`a devam")
        $safe | Should Not Match ([string][char]27 + '\]')
        $safe | Should Not Match "`n"
    }
}

Describe 'merkez ekran metni temizligi (2026-10-15 guvenlik denetimi TASK-075)' {
    It 'rol, isci adi, kosu kimligi ve siradaki adim metni cizimde kontrol dizisi tasimaz' {
        $kaynak = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'merkez.ps1') -Raw -Encoding UTF8
        $kaynak | Should Match 'Protect-MerkezSatir \(\[string\]\$ag\.Rol\)'
        $kaynak | Should Match 'Protect-MerkezSatir \(\[string\]\$ag\.Ad\) 16'
        $kaynak | Should Match 'Protect-MerkezSatir \(\[string\]\$k\.RunId\)'
        $kaynak | Should Match 'Protect-MerkezSatir \(\[string\]\$k\.Sonraki\.Metin\)'
        . (Join-Path $PSScriptRoot 'merkez-veri.ps1')
        $e = [string][char]27
        (Protect-MerkezSatir ("R-1" + $e + "]0;SAHTE" + [char]7 + "x`nY") 30) | Should Be 'R-1x Y'
    }
}

Describe 'merkez kod incelemesi regresyonlari (2026-10-15)' {
    BeforeAll { . (Join-Path $PSScriptRoot 'merkez-veri.ps1') }
    It 'raporlarini teslim etmis salt okunur inceleme kosusu iptal degil, raporlar rozeti alir' {
        $o = Get-MerkezKosuOzet @{ status='aborted'; workers=@(@{status='collected'},@{status='collected'}) }
        $o.Rozet | Should Be 'raporlar'; $o.Kirik | Should Be $false
        (Get-MerkezKosuOzet @{ status='aborted'; workers=@(@{status='aborted'}) }).Rozet | Should Be 'iptal'
    }
    It 'kontrol sayimi gercek semayi okur; suren kosunun suresi simdiye kadar akar, biten kosu son olayda durur' {
        $o = Get-MerkezKosuOzet @{ status='integrated'; integration=@{ ok=$false; checks=@(@{command='a';status=0},@{command='b';status=1}) }; workers=@() }
        $o.Kontrol.Gecen | Should Be 1; $o.Kontrol.Toplam | Should Be 2
        $bas = (Get-Date).ToUniversalTime().AddMinutes(-30).ToString('o'); $eski = (Get-Date).ToUniversalTime().AddMinutes(-27).ToString('o')
        (Get-MerkezKosuOzet @{ status='running'; startedAt=$bas; history=@(@{at=$eski;event='started'}); workers=@() }).Sure -ge 1700 | Should Be $true
        (Get-MerkezKosuOzet @{ status='merged'; startedAt=$bas; history=@(@{at=$eski;event='merged'}); workers=@() }).Sure -lt 400 | Should Be $true
    }
    It 'kanat: vault ile ayni onekli kardes klasor (Beyin-motor) vault kanadina dusmez' {
        $v = Join-Path ([IO.Path]::GetTempPath()) 'OrnekVault'
        $p = @{ Vault = $v }
        Get-MerkezProje (Join-Path $v 'motor\scripts') $p | Should Be 'OrnekVault'
        Get-MerkezProje ($v + '-motor') $p | Should Not Be 'OrnekVault'
    }
    It 'JSON onbellegi: degismeyen dosya ayni nesne, degisen dosya yeni deger, okunamayan dosya onceki deger' {
        $f = Join-Path ([IO.Path]::GetTempPath()) ("merkez-json-" + [guid]::NewGuid().ToString('N') + '.json'); $onb = @{}
        try {
            Set-Content -LiteralPath $f -Value '{"a":1}' -Encoding UTF8
            (Read-MerkezJsonOnb $f $onb).a | Should Be 1
            Start-Sleep -Milliseconds 20; Set-Content -LiteralPath $f -Value '{"a":22}' -Encoding UTF8
            (Read-MerkezJsonOnb $f $onb).a | Should Be 22
            Remove-Item -LiteralPath $f -Force
            (Read-MerkezJsonOnb $f $onb).a | Should Be 22
        } finally { Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue }
    }
}

Describe 'merkez premium gorunum (2026-10-15)' {
    BeforeAll { . (Join-Path $PSScriptRoot 'merkez-veri.ps1') }
    It 'inceleme kosusu topla adiminda biter, sonraki adimlar atlanir; siradaki satir raporlari soyler' {
        $run = @{ status='aborted'; runId='R-X'; workers=@(@{status='collected'},@{status='collected'}) }
        $o = Get-MerkezKosuOzet $run
        $o.Atlanan | Should Be $true; $o.Guncel | Should Be 3; $o.Adimlar[2] | Should Be $true
        (Get-MerkezKosuSonraki $run $false).Metin | Should Match 'raporlar teslim'
        (Get-MerkezKosuSonraki @{ status='aborted'; runId='R-Y'; workers=@(@{status='aborted'}) } $false).Metin | Should Be 'iptal edildi'
        (Get-MerkezKosuOzet @{ status='aborted'; workers=@(@{status='aborted'}) }).Atlanan | Should Be $false
    }
    It 'karar fail olan isci sorunlu (kirmizi), partial/warn kismen (sari) sayilir' {
        $o = Get-MerkezKosuOzet @{ status='integrated'; workers=@(@{status='integrated';verdict='fail'},@{status='integrated';verdict='warn'},@{status='integrated';verdict='pass'}) }
        $o.Sorunlu | Should Be 1; $o.Kismen | Should Be 1; $o.Temiz | Should Be 1
    }
    It 'sefin kapsadigi isci sayilir (integrate --covers)' {
        (Get-MerkezKosuOzet @{ status='merged'; integration=@{ ok=$true; coveredByConductor=@('TASK-1') }; workers=@(@{status='failed'},@{status='integrated';verdict='pass'}) }).Kapsanan | Should Be 1
        (Get-MerkezKosuOzet @{ status='merged'; integration=@{ ok=$true }; workers=@() }).Kapsanan | Should Be 0
    }
    It 'yolunda gorunumu bos degil: calisan ajan ve uyari sayisi soylenir' {
        $s = Get-MerkezSirada @{ Onaylar=@(); Teshis=@(@{Seviye='warn';Metin='x'}); Kosular=@(); Ajanlar=@(@{Durum='calisiyor'},@{Durum='bosta'}) }
        $s.Metin | Should Be 'hata yok · 1 uyarı bekliyor'; $s.Renk | Should Be 'warn'; $s.Neden | Should Match '1 ajan çalışıyor'
        $s2 = Get-MerkezSirada @{ Onaylar=@(); Teshis=@(@{Seviye='warn';Metin='20 oturum sessiz · beyin bekci'}); Kosular=@(); Ajanlar=@() }
        $s2.Neden | Should Match '^ilk adım: beyin bekci'
        (Get-MerkezSirada @{ Onaylar=@(); Teshis=@(); Kosular=@(); Ajanlar=@(@{Durum='calisiyor'}) }).Metin | Should Be 'her şey yolunda'
    }
    It 'eski aktarim teshisi en eskisini ve sayiyi yazar' {
        $simdi = Get-Date
        $ak = @(@{ id='YENI'; ts=$simdi.AddDays(-4).ToString('o'); toProject='p1' }, @{ id='ESKI'; ts=$simdi.AddDays(-9).ToString('o'); toProject='p2' }, @{ id='TAZE'; ts=$simdi.AddHours(-2).ToString('o') })
        $t = Get-MerkezEskiAktarim $ak $simdi
        $t.Metin | Should Match '^2 aktarım'; $t.Metin | Should Match 'ESKI \(p2\)'
        Get-MerkezEskiAktarim @($ak[2]) $simdi | Should Be $null
    }
    It 'gercek vault cizimi her genislikte ve iki gorunumde satiri tam pencere genisliginde kapatir' {
        $vault = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
        $esc = [string][char]27
        foreach ($g in @(@{ W = 90; A = $false }, @{ W = 120; A = $true }, @{ W = 170; A = $true }, @{ W = 210; A = $false })) {
            $eskiKod = [Console]::OutputEncoding; [Console]::OutputEncoding = [Text.Encoding]::UTF8
            try {
                $arg = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $PSScriptRoot 'merkez.ps1'), '-Vault', $vault, '-Tek', '-Genislik', $g.W); if ($g.A) { $arg += '-Aktifler' }
                $out = & powershell.exe @arg 2>&1 | Out-String
            } finally { [Console]::OutputEncoding = $eskiKod }
            $LASTEXITCODE | Should Be 0
            $plain = [regex]::Replace($out, ($esc + '\[[0-9;?]*[A-Za-z]'), '')
            $satirlar = @($plain -split "`r?`n" | Where-Object { $_.Trim() })
            $satirlar.Count | Should BeGreaterThan 10
            foreach ($l in $satirlar) { "$($g.W):$($l.Length)" | Should Be "$($g.W):$($g.W)" }   # cerceve sag kenari her satirda ayni sutunda
            $satirlar[0] | Should Match '^╭'; $satirlar[$satirlar.Count - 1] | Should Match '╯$'
        }
    }
}

Describe 'merkez sabit veriyle kenar durumlari (onay, hatali kosu, engelli kart)' {
    It 'onay bekleyen ve kontrolu dusmus kosu her genislikte tam cerceveyle cizilir' {
        $root = Join-Path ([IO.Path]::GetTempPath()) ('merkez-fx-' + [guid]::NewGuid().ToString('N'))
        $scripts = Join-Path $root 'motor\scripts'; $hooks = Join-Path $root 'motor\hooks'; $runs = Join-Path $scripts '.state\team-runs'
        New-Item -ItemType Directory -Force -Path $scripts, $hooks, $runs | Out-Null
        try {
            Copy-Item (Join-Path $PSScriptRoot 'merkez*.ps1') $scripts; Copy-Item (Join-Path $PSScriptRoot 'beyin-ciz.ps1') $scripts
            Copy-Item (Join-Path $PSScriptRoot 'takim-uyum.ps1') $scripts
            Copy-Item (Join-Path (Split-Path $PSScriptRoot -Parent) 'hooks\lib.ps1') $hooks
            Copy-Item (Join-Path $PSScriptRoot 'takim-uyum.ps1') $scripts
            $simdi = (Get-Date).ToUniversalTime()
            @{ runId = 'R-ONAY'; repoName = 'demo'; status = 'planned'; workers = @(@{ taskId = 'TASK-1'; status = 'planned'; role = 'docs_author' }) } | ConvertTo-Json -Depth 6 | Set-Content -Encoding UTF8 (Join-Path $runs 'R-ONAY.json')
            @{ runId = 'R-HATA'; repoName = 'demo'; status = 'integrated'; startedAt = $simdi.AddMinutes(-20).ToString('o'); integration = @{ ok = $false; checks = @(@{ command = 'test'; status = 1 }) }
               workers = @(@{ taskId = 'TASK-2'; status = 'integrated'; verdict = 'fail'; role = 'qa_lead' }, @{ taskId = 'TASK-3'; status = 'integrated'; verdict = 'pass'; role = 'docs_author' }) } | ConvertTo-Json -Depth 6 | Set-Content -Encoding UTF8 (Join-Path $runs 'R-HATA.json')
            @{ tasks = @(@{ id = 'TASK-9'; status = 'review'; title = 'Belgeleri guncelle'; owner = @{ agent = 'codex' } }, @{ id = 'TASK-8'; status = 'blocked'; title = 'Engelli is'; owner = @{ agent = 'claude' } }) } | ConvertTo-Json -Depth 6 | Set-Content -Encoding UTF8 (Join-Path $scripts '.state\board.json')
            $esc = [string][char]27
            foreach ($w in @(90, 120, 210)) {
                $eskiKod = [Console]::OutputEncoding; [Console]::OutputEncoding = [Text.Encoding]::UTF8
                try { $out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scripts 'merkez.ps1') -Vault $root -Tek -Genislik $w 2>&1 | Out-String } finally { [Console]::OutputEncoding = $eskiKod }
                $LASTEXITCODE | Should Be 0
                $plain = [regex]::Replace($out, ($esc + '\[[0-9;?]*[A-Za-z]'), '')
                $satirlar = @($plain -split "`r?`n" | Where-Object { $_.Trim() })
                foreach ($l in $satirlar) { "$($w):$($l.Length)" | Should Be "$($w):$($w)" }
                $plain | Should Match 'baslat R-ONAY'
                $plain | Should Match 'onayla TASK-9'
                $plain | Should Match 'KONTROL DÜŞTÜ'
                $plain | Should Match '\d HATA'   # makinenin bellek durumu ikinci bir hata ekleyebilir
                @($satirlar | Where-Object { $_ -match '▣ demo' })[0].Split([char]0x2502).Count | Should Be 3   # tek kanat: ortada sutun ayraci yok
            }
        } finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

Describe 'merkez canli panel (1.4.5): olay akisi ve guvenli simgeler' {
    BeforeAll { . (Join-Path $PSScriptRoot 'merkez-veri.ps1') }
    It 'ev dizini her yol biciminde ~ olur (kullanici adi ekrana cikmaz)' {
        $u = 'ornek' + 'kisi'
        (Protect-MerkezSatir ('cd C:\Users\' + $u + '\Desktop') 80) | Should Be 'cd ~\Desktop'
        (Protect-MerkezSatir ('"C:\\Users\\' + $u + '\\Desktop\\x"') 80) | Should Be '"~\\Desktop\\x"'
        (Protect-MerkezSatir ('cd /c/Users/' + $u + '/Desktop') 80) | Should Be 'cd ~/Desktop'
        (Protect-MerkezSatir ('C:/Users/' + $u + '/a') 80) | Should Be '~/a'
    }
    It 'makbuz gurultusu atilir, anlamli olay Turkce metne cevrilir' {
        ConvertTo-MerkezOlay @{ ts = (Get-Date).ToString('o'); script = 'kill-guard'; outcome = 'GECTI' } | Should Be $null
        ConvertTo-MerkezOlay @{ ts = (Get-Date).ToString('o'); script = 'retrieval'; outcome = 'ESIK_ALTI' } | Should Be $null
        $o = ConvertTo-MerkezOlay @{ ts = (Get-Date).ToString('o'); script = 'kill-guard'; outcome = 'RED'; agent = 'codex'; note = 'Stop-Process -Name x' }
        $o.Renk | Should Be 'warn'; $o.Metin | Should Match 'kill guard engelledi'   # engel: koruma calisti, hata degil
        (ConvertTo-MerkezOlay @{ ts = (Get-Date).ToString('o'); script = 'retrieval'; outcome = 'ENJEKSIYON'; concepts = @('ornek-kavram.md') }).Metin | Should Match '1 not bağlama eklendi: ornek kavram'
    }
    It 'ayni oturumun ardisik ayni olaylari tek satirda birlesir; makbuz yoksa bos liste' {
        $d = Join-Path ([IO.Path]::GetTempPath()) ('merkez-mk-' + [guid]::NewGuid().ToString('N')); New-Item -ItemType Directory -Path $d | Out-Null
        try {
            $simdi = Get-Date; $f = Join-Path $d ($simdi.ToString('yyyy-MM-dd') + '.jsonl')
            $sat = @(
                (@{ ts = $simdi.AddMinutes(-3).ToString('o'); script = 'flush'; outcome = 'FLUSH_OK'; agent = 'claude'; key = 'K1' } | ConvertTo-Json -Compress),
                (@{ ts = $simdi.AddMinutes(-2).ToString('o'); script = 'flush'; outcome = 'FLUSH_OK'; agent = 'claude'; key = 'K1' } | ConvertTo-Json -Compress),
                (@{ ts = $simdi.AddMinutes(-1).ToString('o'); script = 'kill-guard'; outcome = 'GECTI'; agent = 'codex' } | ConvertTo-Json -Compress),
                (@{ ts = $simdi.ToString('o'); script = 'yayinla'; outcome = 'YAYIN_OK'; agent = 'claude' } | ConvertTo-Json -Compress))
            [IO.File]::WriteAllLines($f, [string[]]$sat)
            $ol = Get-MerkezOlaylar $d 10 $simdi
            $ol.Count | Should Be 2
            $ol[0].Metin | Should Be 'motor yayınlandı'
            $ol[1].Adet | Should Be 2
            (Get-MerkezOlaylar (Join-Path $d 'yok') 10 $simdi).Count | Should Be 0
        } finally { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue }
    }
    It 'cizimde Windows Terminalde emoji genisliginde cizilen belirsiz simge (⚠ ✔ ✖ ▶ ⏸) yok' {
        $vault = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
        $eskiKod = [Console]::OutputEncoding; [Console]::OutputEncoding = [Text.Encoding]::UTF8
        try { $out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'merkez.ps1') -Vault $vault -Tek -Genislik 170 2>&1 | Out-String } finally { [Console]::OutputEncoding = $eskiKod }
        $LASTEXITCODE | Should Be 0
        $out | Should Not Match '[\u26A0\u2714\u2716\u25B6\u23F8\uFE0F]'
        $kaynak = (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'merkez.ps1') -Raw -Encoding UTF8) + (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'merkez-veri.ps1') -Raw -Encoding UTF8)
        ($kaynak -replace '#[^\r\n]*', '') | Should Not Match '[\u26A0\u2714\u2716\u25B6\u23F8]'
    }
}

Describe 'merkez 1.4.8: yetim kart, bilgi teshisi, onay atlandi olayi' {
    BeforeAll {
        . (Join-Path (Split-Path $PSScriptRoot -Parent) 'hooks\lib.ps1')
        . (Join-Path $PSScriptRoot 'merkez-veri.ps1')
        $script:yv = Join-Path ([IO.Path]::GetTempPath()) ("merkez-yetim-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
        $script:yp = @{ Vault = $script:yv; Sessions = (Join-Path $script:yv 'sessions'); TeamRuns = (Join-Path $script:yv 'team-runs'); Board = (Join-Path $script:yv 'board.json'); ScrState = (Join-Path $script:yv 'scr'); Handoff = (Join-Path $script:yv 'handoff') }
        foreach ($d in @($script:yp.Sessions, $script:yp.TeamRuns, $script:yp.ScrState, $script:yp.Handoff)) { New-Item -ItemType Directory -Force -Path $d | Out-Null }
        Set-Content -LiteralPath (Join-Path $script:yp.TeamRuns 'R-IPTAL.json') -Value (@{ runId = 'R-IPTAL'; repoName = 'demo'; status = 'aborted'; workers = @() } | ConvertTo-Json -Depth 6) -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $script:yp.TeamRuns 'R-BIRLESTI.json') -Value (@{ runId = 'R-BIRLESTI'; repoName = 'demo'; status = 'merged'; workers = @() } | ConvertTo-Json -Depth 6) -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $script:yp.TeamRuns 'R-CANLI.json') -Value (@{ runId = 'R-CANLI'; repoName = 'demo'; status = 'planned'; workers = @() } | ConvertTo-Json -Depth 6) -Encoding UTF8
        $board = @{ schemaVersion = 4; tasks = @(
            @{ id = 'TASK-1'; title = 'Team run R-IPTAL: qa_lead'; status = 'todo'; owner = @{ agent = 'codex'; session = 'team-R-IPTAL' } },
            @{ id = 'TASK-2'; title = 'Team run R-CANLI: qa_lead'; status = 'todo'; owner = @{ agent = 'codex'; session = 'team-R-CANLI' } },
            @{ id = 'TASK-4'; title = 'Team run R-BIRLESTI: qa_lead'; status = 'review'; owner = @{ agent = 'codex'; session = 'team-R-BIRLESTI' } },
            @{ id = 'TASK-3'; title = 'el ile kart'; status = 'todo'; owner = @{ agent = 'claude'; session = 'oturum-x' } }) }
        Set-Content -LiteralPath $script:yp.Board -Value ($board | ConvertTo-Json -Depth 6) -Encoding UTF8
        $script:ya = Get-MerkezAnlik -Paths $script:yp
    }
    AfterAll { Remove-Item -LiteralPath $script:yv -Recurse -Force -ErrorAction SilentlyContinue }
    It 'kapanmis kosuya bagli acik kart yetim; canli kosunun, el ile acilmis ve onay bekleyen (review) kart degil; teshis iptal komutu verir' {
        @($script:ya.Yetim.Keys) -join ',' | Should Be 'TASK-1'
        $t = @($script:ya.Teshis | Where-Object { $_.Anahtar -eq 'yetim' })
        $t.Count | Should Be 1
        $t[0].Metin | Should Match 'R-IPTAL · iptal'
        $t[0].Metin | Should Match 'beyin pano transition --task TASK-1 --status cancelled --reason'
    }
    It 'info teshisi uyari sayilmaz ve ilk adim olmaz' {
        $s = Get-MerkezSirada @{ Onaylar=@(); Teshis=@(@{Seviye='info';Metin='bak · beyin x'}); Kosular=@(); Ajanlar=@() }
        $s.Metin | Should Be 'her şey yolunda'
        $s2 = Get-MerkezSirada @{ Onaylar=@(); Teshis=@(@{Seviye='info';Metin='bak'}, @{Seviye='warn';Metin='eski · beyin aktar -Tamam 1'}); Kosular=@(); Ajanlar=@() }
        $s2.Metin | Should Be 'hata yok · 1 uyarı bekliyor'
        $s2.Neden | Should Match 'ilk adım: beyin aktar -Tamam 1'
    }
    It 'gecersiz kosu icin baslat satiri olay akisinda Turkce gorunur' {
        $o = ConvertTo-MerkezOlay @{ ts = (Get-Date).ToString('o'); script = 'takim'; outcome = 'ONAY_ATLANDI'; agent = 'claude'; note = 'baslat R-1 durum aborted' }
        $o.Renk | Should Be 'warn'; $o.Metin | Should Match '^onay satırı işlenmedi · baslat R-1'
    }
}

Describe 'merkez 1.5.0: sekmeler, ayrinti, bugun verisi, satir komutu' {
    BeforeAll {
        . (Join-Path (Split-Path $PSScriptRoot -Parent) 'hooks\lib.ps1')
        . (Join-Path $PSScriptRoot 'merkez-veri.ps1')
        $script:esc = [string][char]27
        function Duz([string]$s) { return [regex]::Replace([regex]::Replace($s, ($script:esc + '\[[0-9;?]*[A-Za-z]'), ''), ($script:esc + '\][^' + [char]7 + ']*' + [char]7 + '?'), '') }
    }
    It 'gercek vault: dort sekme, ayrinti acik ve kapali, 90/120/170/210 sutunda her satir tam genislikte' {
        $vault = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
        foreach ($g in @(@{ W = 90; A = $false }, @{ W = 120; A = $true }, @{ W = 170; A = $false }, @{ W = 210; A = $true })) {
            $eskiKod = [Console]::OutputEncoding; [Console]::OutputEncoding = [Text.Encoding]::UTF8
            try {
                $arg = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $PSScriptRoot 'merkez.ps1'), '-Vault', $vault, '-Tek', '-Sekme', 'Hepsi', '-Genislik', $g.W, '-Yukseklik', 50); if ($g.A) { $arg += '-Ayrinti' }
                $out = & powershell.exe @arg 2>&1 | Out-String
            } finally { [Console]::OutputEncoding = $eskiKod }
            $LASTEXITCODE | Should Be 0
            $parcalar = @((Duz $out) -split '=== SEKME \w+ ===\r?\n' | Where-Object { $_.Trim() })
            $parcalar.Count | Should Be 4
            $i = 0
            foreach ($p in $parcalar) {
                $satirlar = @($p -split "`r?`n" | Where-Object { $_ })
                $satirlar[0] | Should Match '^╭'; $satirlar[$satirlar.Count - 1] | Should Match '╯$'
                foreach ($l in $satirlar) { "$($g.W)/$i`:$($l.Length)" | Should Be "$($g.W)/$i`:$($g.W)" }
                $i++
            }
            $parcalar[0] | Should Match 'SIRADA'; $parcalar[1] | Should Match 'KANATLAR'; $parcalar[2] | Should Match 'KOŞULAR'; $parcalar[3] | Should Match 'OLAYLAR'
            $out | Should Not Match '[\u26A0\u2714\u2716\u25B6\u23F8\u2699]'
        }
    }
    It 'emoji yalniz baslikta: kaynakta her emoji bir BUYUK harfli bolum/kart adindan once gelir' {
        $tok = $null; $err = $null; [void][System.Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'merkez.ps1'), [ref]$tok, [ref]$err)
        $kod = (@($tok | Where-Object { $_.Kind -ne 'Comment' } | ForEach-Object { $_.Text }) -join "`n")
        $kotu = @([regex]::Matches($kod, '[\uD800-\uDBFF][\uDC00-\uDFFF](?! [A-ZÇĞİÖŞÜ]{3,})') | ForEach-Object { $kod.Substring([Math]::Max(0, $_.Index - 20), 40) })
        "$($kotu.Count): $($kotu -join ' | ')" | Should Be '0: '
    }
    It 'gun sayaci: oturum benzersiz anahtarla, ozet/yayin sayilir; ek satirlar artimli okunur; dun ayni saate kadar' {
        $d = Join-Path ([IO.Path]::GetTempPath()) ('merkez-gun-' + [guid]::NewGuid().ToString('N')); New-Item -ItemType Directory -Path $d | Out-Null
        try {
            $simdi = Get-Date; $f = Join-Path $d ($simdi.ToString('yyyy-MM-dd') + '.jsonl'); $o = @{}
            $sat = { param($t, $sc, $oc, $k) (@{ ts = $t.ToString('o'); script = $sc; agent = 'claude'; key = $k; outcome = $oc } | ConvertTo-Json -Compress) }
            [IO.File]::WriteAllLines($f, [string[]]@((& $sat $simdi 'session-start' 'ENJEKSIYON' 'K1'), (& $sat $simdi 'session-start' 'ENJEKSIYON' 'K1'), (& $sat $simdi 'session-start' 'ENJEKSIYON' 'K2'), (& $sat $simdi 'flush' 'FLUSH_OK' 'K1'), (& $sat $simdi 'yayinla' 'YAYIN_OK' '')))
            $g = Get-MerkezGunSayac $d $simdi.Date $o
            (Get-MerkezDakikaToplam $g.Oturum) | Should Be 2
            (Get-MerkezDakikaToplam $g.Ozet) | Should Be 1
            (Get-MerkezDakikaToplam $g.Yayin) | Should Be 1
            [IO.File]::AppendAllText($f, (& $sat $simdi 'flush' 'FLUSH_OK' 'K2') + "`n")
            $g = Get-MerkezGunSayac $d $simdi.Date $o
            (Get-MerkezDakikaToplam $g.Ozet) | Should Be 2
            (Get-MerkezDakikaToplam $g.Oturum) | Should Be 2
            $dun = $simdi.AddDays(-1); $fd = Join-Path $d ($dun.ToString('yyyy-MM-dd') + '.jsonl')
            $sonra = $dun.AddMinutes(30); if ($sonra.Date -ne $dun.Date) { $sonra = $dun }
            [IO.File]::WriteAllLines($fd, [string[]]@((& $sat $dun.AddMinutes(-1) 'flush' 'FLUSH_OK' 'A'), (& $sat $sonra 'flush' 'FLUSH_OK' 'B')))
            $y = Get-MerkezGunSayac $d $dun.Date $o
            $dk = $simdi.Hour * 60 + $simdi.Minute
            (Get-MerkezDakikaToplam $y.Ozet $dk) -ge 1 | Should Be $true
            (Get-MerkezDakikaToplam $y.Ozet) | Should Be 2
        } finally { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue }
    }
    It 'maliyet gun dosyasi: Claude USD, Codex jeton, oturum basina USD' {
        $d = Join-Path ([IO.Path]::GetTempPath()) ('merkez-mal-' + [guid]::NewGuid().ToString('N')); New-Item -ItemType Directory -Path $d | Out-Null
        try {
            $gun = (Get-Date).Date; $f = Join-Path $d ($gun.ToString('yyyy-MM-dd') + '.json')
            Set-Content -LiteralPath $f -Encoding UTF8 -Value '{"v":1,"k":{"claude|P|S1|m":{"usd":1.5,"in":10,"out":5,"cr":0},"claude|P|S1|n":{"usd":0.5,"in":1,"out":1,"cr":0},"codex|P|S2|m":{"usd":0,"in":100,"out":50,"cr":0}}}'
            $m = Get-MerkezMaliyetGun $d $gun @{}
            $m.ClaudeUsd | Should Be 2
            $m.CodexJeton | Should Be 150
            $m.Oturum['S1'].Usd | Should Be 2
            (Get-MerkezMaliyetGun $d $gun.AddDays(-5) @{}) | Should Be $null
        } finally { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue }
    }
    It 'git kaydi: bugunun ve dunun commitleri, worktree gitdir dosyasi izlenir (git calistirilmaz)' {
        $d = Join-Path ([IO.Path]::GetTempPath()) ('merkez-git-' + [guid]::NewGuid().ToString('N'))
        $gd = Join-Path $d 'repo\.git'; New-Item -ItemType Directory -Force -Path (Join-Path $gd 'logs') | Out-Null
        try {
            $simdi = Get-Date; $ep = { param($t) [DateTimeOffset]::new($t).ToUnixTimeSeconds() }
            $z = '0' * 40; $h = 'a' * 40
            $s1 = "$z $h Ad <a@b> $(& $ep $simdi.AddMinutes(-1)) +0300`tcommit: bugun"
            $s2 = "$h $h Ad <a@b> $(& $ep $simdi.AddMinutes(-1)) +0300`tcheckout: moving"
            $s3 = "$h $h Ad <a@b> $(& $ep $simdi.AddDays(-1).AddMinutes(-2)) +0300`tcommit (amend): dun"
            [IO.File]::WriteAllLines((Join-Path $gd 'logs\HEAD'), [string[]]@($s3, $s1, $s2))
            $wt = Join-Path $d 'wt'; New-Item -ItemType Directory -Force -Path $wt | Out-Null
            Set-Content -LiteralPath (Join-Path $wt '.git') -Value "gitdir: $gd" -Encoding ASCII
            (Get-MerkezGitDizin $wt) | Should Be $gd
            $r = Get-MerkezGitBugun @($gd) $simdi @{}
            $r.Bugun | Should Be 1; $r.Dun | Should Be 1; $r.DunSimdiye | Should Be 1
        } finally { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue }
    }
    It 'isci adimlari: son 5 adim yeniden eskiye, started+completed cifti tek adim' {
        $d = Join-Path ([IO.Path]::GetTempPath()) ('merkez-isci-' + [guid]::NewGuid().ToString('N')); New-Item -ItemType Directory -Path $d | Out-Null
        try {
            $f = Join-Path $d 'events.jsonl'
            $sat = @(1..7 | ForEach-Object { (@{ type = 'item.completed'; item = @{ type = 'command_execution'; command = "komut-$_" } } | ConvertTo-Json -Compress -Depth 4) })
            $sat += (@{ type = 'item.started'; item = @{ type = 'command_execution'; command = 'komut-7' } } | ConvertTo-Json -Compress -Depth 4)
            [IO.File]::WriteAllLines($f, [string[]]$sat)
            $a = @(Get-MerkezIsciAdimlar $f 5)
            $a.Count | Should Be 5
            $a[0].Metin | Should Match 'komut-7'
            $a[4].Metin | Should Match 'komut-3'
        } finally { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue }
    }
    It 'satir komutu: beyaz liste; ajan metninden kabuk islecli komut reddedilir; sonda satir sonu yok' {
        (Get-MerkezSatirKomut @{ Tur = 'aktarim'; Nesne = @{ id = '20261011T125258-13ee' } }).Komut | Should Be 'beyin aktar -Tamam 20261011T125258-13ee'
        (Get-MerkezSatirKomut @{ Tur = 'kart'; Yetim = $true; Nesne = @{ id = 'TASK-1' } }).Komut | Should Match "^beyin pano transition --task TASK-1 --status cancelled --reason 'koşu kapandı'$"
        (Get-MerkezSatirKomut @{ Tur = 'kart'; Nesne = @{ id = 'TASK-2'; status = 'review' } }).Komut | Should Be 'onayla TASK-2'
        (Get-MerkezSatirKomut @{ Tur = 'onay'; Nesne = @{ Satir = 'birlestir R20261015-4368' } }).Ipucu | Should Match 'sohbete'
        (Get-MerkezSatirKomut @{ Tur = 'lider'; Nesne = @{ Ajan = 'codex'; Ad = '01a146bc-161e-7182' } }).Komut | Should Be 'codex resume 01a146bc-161e-7182'
        Get-MerkezSatirKomut @{ Tur = 'teshis'; Nesne = @{ Metin = 'x · beyin aktar -Tamam 1; Remove-Item C:\' } } | Should Be $null
        Get-MerkezSatirKomut @{ Tur = 'teshis'; Nesne = @{ Metin = ('x · beyin bekci' + [char]27 + '[2J') } } | Should Be $null
        Get-MerkezSatirKomut @{ Tur = 'teshis'; Nesne = @{ Metin = 'yalniz bilgi' } } | Should Be $null
        Test-MerkezGuvenliKomut "beyin bekci`n" | Should Be $false
        Test-MerkezGuvenliKomut 'beyin bekci | iex' | Should Be $false
        Test-MerkezGuvenliKomut 'beyin bekci' | Should Be $true
    }
    It 'Protect-MerkezSatir: BMP emoji guvenli simgeye cevrilir, vekil cift kesimde bolunmez' {
        (Protect-MerkezSatir ('tamam ' + [char]0x2705 + ' dikkat ' + [char]0x26A0 + [char]0xFE0F) 80) | Should Be 'tamam ✓ dikkat ▲'
        $e = [char]::ConvertFromUtf32(0x1F680)
        $k = Protect-MerkezSatir ('abc' + $e + $e + $e) 5
        ($k -match '[\uD800-\uDBFF](?![\uDC00-\uDFFF])') | Should Be $false
    }
}

Describe 'takim-izle 1.5.0: tek kare, ortak katman, simge' {
    It 'kosu panosu ve isci paneli -Tek ile 90/120/170 sutunda tam genislikte cizilir, yasak simge yok' {
        $root = Join-Path ([IO.Path]::GetTempPath()) ('takim-izle-' + [guid]::NewGuid().ToString('N'))
        $hooks = Join-Path $root 'motor\hooks'; New-Item -ItemType Directory -Force -Path $hooks | Out-Null
        try {
            Copy-Item (Join-Path (Split-Path $PSScriptRoot -Parent) 'hooks\lib.ps1') $hooks
            . (Join-Path $hooks 'lib.ps1'); $pp = Get-BeyinPaths -Vault $root
            $tr = $pp.TeamRuns; New-Item -ItemType Directory -Force -Path (Join-Path $tr 'R-T\TASK-1') | Out-Null
            $bas = (Get-Date).ToUniversalTime().AddMinutes(-3).ToString('o')
            $kos = @{ runId = 'R-T'; repoName = 'cok-uzun-bir-depo-adi-ornek-proje-2026-xyz'; status = 'running'; baseBranch = 'feature/uzun-dal-adi-ornek'; startedAt = $bas; approvals = @{ start = @{ at = $bas } }
                      supervisor = @{ pid = $PID; heartbeatAt = (Get-Date).ToUniversalTime().ToString('o') }
                      workers = @(@{ taskId = 'TASK-1'; role = 'qa_lead'; status = 'running'; startedAt = $bas; pid = $PID }, @{ taskId = 'TASK-2'; role = 'docs_author'; status = 'finished'; startedAt = $bas; finishedAt = $bas; verdict = 'pass' }) }
            Set-Content -LiteralPath (Join-Path $tr 'R-T.json') -Value ($kos | ConvertTo-Json -Depth 6) -Encoding UTF8
            $ev = @((@{ type = 'thread.started'; thread_id = 'th-1' } | ConvertTo-Json -Compress), (@{ type = 'item.completed'; item = @{ type = 'command_execution'; command = 'npm test'; exit_code = 0; aggregated_output = 'ok' } } | ConvertTo-Json -Compress -Depth 4), (@{ type = 'item.completed'; item = @{ type = 'agent_message'; text = 'Testleri calistirdim, hepsi gecti.' } } | ConvertTo-Json -Compress -Depth 4))
            [IO.File]::WriteAllLines((Join-Path $tr 'R-T\TASK-1\events.jsonl'), [string[]]$ev)
            foreach ($w in @(90, 120, 170)) {
                foreach ($kart in @('', 'TASK-1')) {
                    $eskiKod = [Console]::OutputEncoding; [Console]::OutputEncoding = [Text.Encoding]::UTF8
                    try {
                        $arg = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $PSScriptRoot 'takim-izle.ps1'), '-Vault', $root, '-Run', 'R-T', '-Tek', '-Genislik', $w, '-Yukseklik', 45); if ($kart) { $arg += @('-Kart', $kart) }
                        $out = & powershell.exe @arg 2>&1 | Out-String
                    } finally { [Console]::OutputEncoding = $eskiKod }
                    $LASTEXITCODE | Should Be 0
                    $esc = [string][char]27; $plain = [regex]::Replace($out, ($esc + '\[[0-9;?]*[A-Za-z]'), '')
                    $satirlar = @($plain -split "`r?`n" | Where-Object { $_ })
                    $satirlar.Count | Should BeGreaterThan 8
                    $satirlar[0] | Should Match '^╭'; $satirlar[$satirlar.Count - 1] | Should Match '╯$'
                    foreach ($l in $satirlar) { "$w/$kart`:$($l.Length)" | Should Be "$w/$kart`:$w" }
                    $out | Should Not Match '[\u26A0\u2714\u2716\u25B6\u23F8\u2699\u2139\u27E1]'
                }
            }
        } finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

Describe 'merkez-balon 1.5.0: ajan ayrintisi' {
    BeforeAll { . (Join-Path $PSScriptRoot 'merkez-balon.ps1') }
    It 'Claude transkripti: son 5 arac adimi, model, baglam (onbellek dahil), tur bitisi; onbellek ikinci cagrida ayristirmaz' {
        $kok = Join-Path ([IO.Path]::GetTempPath()) ('merkez-ay-' + [guid]::NewGuid().ToString('N')); $env:CLAUDE_CONFIG_DIR = $kok
        $proj = Join-Path $kok 'projects\x'; New-Item -ItemType Directory -Force -Path $proj | Out-Null
        try {
            Clear-MerkezOnbellek
            $id = 'aaaa1111-2222-3333-4444-555566667777'; $f = Join-Path $proj "$id.jsonl"
            $t = (Get-Date).ToUniversalTime()
            $sat = @((@{ type = 'user'; timestamp = $t.AddMinutes(-9).ToString('o'); message = @{ role = 'user'; content = 'gorev' } } | ConvertTo-Json -Compress -Depth 6))
            foreach ($i in 1..7) { $sat += (@{ type = 'assistant'; timestamp = $t.AddMinutes(-8 + $i).ToString('o'); message = @{ model = 'claude-opus-5-5'; usage = @{ input_tokens = 10; cache_read_input_tokens = 1000; cache_creation_input_tokens = 5 }; content = @(@{ type = 'tool_use'; name = 'Read'; input = @{ file_path = "C:\x\dosya$i.ps1" } }) } } | ConvertTo-Json -Compress -Depth 8) }
            $sat += (@{ type = 'assistant'; timestamp = $t.ToString('o'); message = @{ model = 'claude-opus-5-5'; stop_reason = 'end_turn'; usage = @{ input_tokens = 20; cache_read_input_tokens = 2000; cache_creation_input_tokens = 0 }; content = @(@{ type = 'text'; text = 'bitti' }) } } | ConvertTo-Json -Compress -Depth 8)
            [IO.File]::WriteAllLines($f, [string[]]$sat)
            $r = Get-MerkezAyrinti -Ajan claude -OturumId $id -Adim 5
            $r.Ok | Should Be $true
            @($r.Adimlar).Count | Should Be 5
            $r.Adimlar[0].Metin | Should Match 'dosya7'
            $r.Model | Should Be 'claude-opus-5-5'
            $r.Baglam | Should Be 2020
            ($null -ne $r.SonBitis) | Should Be $true
            ($null -ne $r.SonIstem) | Should Be $true
            $n = Get-MerkezAyristirmaSayisi; [void](Get-MerkezAyrinti -Ajan claude -OturumId $id -Adim 5); (Get-MerkezAyristirmaSayisi) | Should Be $n
        } finally { Remove-Item Env:\CLAUDE_CONFIG_DIR -ErrorAction SilentlyContinue; Remove-Item -LiteralPath $kok -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

Describe 'merkez 1.5.1: QA kenar durumlari' {
    BeforeAll {
        . (Join-Path (Split-Path $PSScriptRoot -Parent) 'hooks\lib.ps1')
        . (Join-Path $PSScriptRoot 'merkez-veri.ps1')
        function YeniVault {
            $root = Join-Path ([IO.Path]::GetTempPath()) ('merkez-qa-' + [guid]::NewGuid().ToString('N'))
            $scripts = Join-Path $root 'motor\scripts'; $hooks = Join-Path $root 'motor\hooks'
            New-Item -ItemType Directory -Force -Path $scripts, $hooks, (Join-Path $scripts '.state\team-runs'), (Join-Path $scripts '.state\makbuz') | Out-Null
            Copy-Item (Join-Path $PSScriptRoot 'merkez*.ps1') $scripts; Copy-Item (Join-Path $PSScriptRoot 'beyin-ciz.ps1') $scripts
            Copy-Item (Join-Path $PSScriptRoot 'takim-uyum.ps1') $scripts
            Copy-Item (Join-Path (Split-Path $PSScriptRoot -Parent) 'hooks\lib.ps1') $hooks
            return $root
        }
        function Ciz([string]$root, [string[]]$ek) {
            $eskiKod = [Console]::OutputEncoding; [Console]::OutputEncoding = [Text.Encoding]::UTF8
            try { $out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'motor\scripts\merkez.ps1') -Vault $root -Tek @ek 2>&1 | Out-String } finally { [Console]::OutputEncoding = $eskiKod }
            return [regex]::Replace($out, ([string][char]27 + '\[[0-9;?]*[A-Za-z]'), '')
        }
    }
    It 'uzun kebab/klasor adi sir sayilip *** olmaz; gercek sir yine maskelenir' {
        Protect-MerkezSatir 'my-very-long-project-folder-name-2026-q4' 80 | Should Be 'my-very-long-project-folder-name-2026-q4'
        Protect-MerkezSatir ('tok ' + 'a1B2c3D4e5F6g7H8i9J0k1L2m3N4o5P6q7') 80 | Should Match '\*\*\*'
    }
    It 'engelli isci teshis alir; kaydi silinmis kosunun karti yetim sayilir' {
        $root = YeniVault
        try {
            $p = Get-BeyinPaths -Vault $root
            @{ runId = 'R-ENG'; repoName = 'demo'; status = 'running'; workers = @(@{ taskId = 'TASK-1'; status = 'failed'; role = 'qa_lead' }, @{ taskId = 'TASK-2'; status = 'running'; role = 'docs_author'; pid = $PID }) } | ConvertTo-Json -Depth 6 | Set-Content -Encoding UTF8 (Join-Path $p.TeamRuns 'R-ENG.json')
            @{ tasks = @(@{ id = 'TASK-7'; status = 'todo'; title = 'Team run R-YOK: qa_lead'; owner = @{ agent = 'codex'; session = 'team-R-YOK' } }) } | ConvertTo-Json -Depth 6 | Set-Content -Encoding UTF8 $p.Board
            $a = Get-MerkezAnlik -Paths $p
            (@($a.Teshis | ForEach-Object { $_.Metin }) -join '|') | Should Match 'TASK-1 işçisi engelli \(failed\)'
            $a.Yetim['TASK-7'].Durum | Should Be 'kayip'
        } finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
    }
    It 'tek olayli gun: Olaylar basligi (1) der (tek oge hashtable olarak acilmaz)' {
        $root = YeniVault
        try {
            $f = Join-Path $root ('motor\scripts\.state\makbuz\' + (Get-Date).ToString('yyyy-MM-dd') + '.jsonl')
            [IO.File]::WriteAllText($f, ((@{ ts = (Get-Date).ToString('o'); script = 'yayinla'; outcome = 'YAYIN_OK'; agent = 'claude'; key = 'K' } | ConvertTo-Json -Compress) + "`n"))
            $o = Ciz $root @('-Sekme', 'Olaylar', '-Genislik', '120', '-Yukseklik', '30')
            $o | Should Match 'OLAYLAR \(1\)'
        } finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
    }
    It 'bozuk maliyet dosyasi kareyi dusurmez, yalniz kart "okunamadi" der' {
        $root = YeniVault
        try {
            $d = Join-Path $root 'motor\scripts\.state\maliyet'; New-Item -ItemType Directory -Force -Path $d | Out-Null
            Set-Content -LiteralPath (Join-Path $d 'son.json') -Encoding UTF8 -Value '{"v":1,"gun":7,"claudeUsd":"abc","codexJeton":1,"buyukBaglamUsd":0}'
            $o = Ciz $root @('-Genislik', '170', '-Yukseklik', '50')
            $o | Should Match 'maliyet dosyası okunamadı'
            $o | Should Match 'SIRADA'
        } finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

Describe 'merkez 1.6.0: ses, sessiz saat, yardim, filtre, 24 saat, olay adlari' {
    BeforeAll {
        . (Join-Path (Split-Path $PSScriptRoot -Parent) 'hooks\lib.ps1')
        . (Join-Path $PSScriptRoot 'beyin-ciz.ps1')
        . (Join-Path $PSScriptRoot 'merkez-veri.ps1')
        # merkez.ps1'deki saf islevler AST ile cikarilir (betik calistirilmaz, ses calinmaz)
        $tok = $null; $err = $null; $ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'merkez.ps1'), [ref]$tok, [ref]$err)
        foreach ($ad in @('SessizMi', 'KosuSonucTon', 'OlayTonu', 'OlaylariBildir', 'KosuRozetMetin', 'TeshisAnahtar')) { $f = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $ad }, $true); . ([scriptblock]::Create($f.Extent.Text)) }
    }
    It 'ayar dogrulayici: ses kipleri ve sessiz saat bicimi' {
        (Test-BeyinAyarDeger -Ad 'BEYIN_MERKEZ_SES' -Deger 'ton').Ok | Should Be $true
        (Test-BeyinAyarDeger -Ad 'BEYIN_MERKEZ_SES' -Deger 'yuksek').Ok | Should Be $false
        (Test-BeyinAyarDeger -Ad 'BEYIN_MERKEZ_SESSIZ' -Deger '23-8').Deger | Should Be '23-08'
        (Test-BeyinAyarDeger -Ad 'BEYIN_MERKEZ_SESSIZ' -Deger 'yok').Ok | Should Be $true
        (Test-BeyinAyarDeger -Ad 'BEYIN_MERKEZ_SESSIZ' -Deger '25-08').Ok | Should Be $false
        (Test-BeyinAyarDeger -Ad 'BEYIN_MERKEZ_SESSIZ' -Deger '08-08').Ok | Should Be $false; (Test-BeyinAyarDeger -Ad 'BEYIN_MERKEZ_SESSIZ' -Deger '8-08').Ok | Should Be $false; (Test-BeyinAyarDeger -Ad 'BEYIN_MERKEZ_SESSIZ' -Deger '08-8').Ok | Should Be $false
    }
    It 'sessiz saat: gece yarisini asan ve gun ici araliklar' {
        $script:sessizSaat = '23-08'
        SessizMi (Get-Date '2026-10-17 23:30') | Should Be $true
        SessizMi (Get-Date '2026-10-17 03:00') | Should Be $true
        SessizMi (Get-Date '2026-10-17 08:00') | Should Be $false
        SessizMi (Get-Date '2026-10-17 14:00') | Should Be $false
        $script:sessizSaat = '09-17'
        SessizMi (Get-Date '2026-10-17 09:00') | Should Be $true
        SessizMi (Get-Date '2026-10-17 17:00') | Should Be $false
        $script:sessizSaat = 'yok'
        SessizMi (Get-Date '2026-10-17 03:00') | Should Be $false
    }
    It 'olaylar makbuzdaki GERCEK adlarla eslenir (gom/GOM_OLLAMA_YOK, COMPILE_HATA_<neden>, FLUSH_HATA_<neden>)' {
        $ol = { param($sc, $oc) ConvertTo-MerkezOlay @{ ts = (Get-Date).ToString('o'); script = $sc; outcome = $oc; agent = 'codex' } }
        $g = & $ol 'gom' 'GOM_OLLAMA_YOK'; $g.Metin | Should Be 'vektör gömme atlandı · Ollama kapalı'; $g.Renk | Should Be 'warn'; $g.Ajan | Should Be 'motor'
        $c = & $ol 'compile' 'COMPILE_HATA_cikis-kodu'; $c.Metin | Should Be 'derleme düştü · cikis kodu'; $c.Renk | Should Be 'err'
        (& $ol 'compile' 'COMPILE_HATA_REDAKSIYON').Metin | Should Be 'derleme düştü · redaksiyon'
        $f = & $ol 'flush' 'FLUSH_HATA_cikis-kodu'; $f.Metin | Should Be 'oturum özeti yazılamadı · cikis kodu'; $f.Renk | Should Be 'err'
        (& $ol 'flush' 'FLUSH_OK').Metin | Should Be 'oturum özeti günlüğe yazıldı'
        (& $ol 'flush' 'FLUSH_MESGUL').Renk | Should Be 'muted'
        (& $ol 'ayar' 'AYAR_GECERSIZ').Renk | Should Be 'warn'
        & $ol 'laya-shadow' 'LAYA_GOLGE_ATLANDI' | Should Be $null
        (& $ol 'compile' 'KUYRUK_BOS').Metin | Should Be 'derleme · kuyruk bos'
        (& $ol 'skill-aday' 'SKILL_ADAY_OK').Metin | Should Match '^skill adayı · '
    }
    It 'sessiz saat elle girilmis bicimleri kabul eder, gecersizi yok sayar' {
        Test-CizSessizSaat '8-17' (Get-Date '2026-10-17 09:00') | Should Be $true
        Test-CizSessizSaat ' 23 - 8 ' (Get-Date '2026-10-17 02:00') | Should Be $true
        Test-CizSessizSaat '08-08' (Get-Date '2026-10-17 08:00') | Should Be $false
        Test-CizSessizSaat '25-08' (Get-Date '2026-10-17 03:00') | Should Be $false
        Test-CizSessizGecerli '25-08' | Should Be $false
        Test-CizSessizGecerli 'yok' | Should Be $true
        Test-CizSessizGecerli '9-17' | Should Be $true
    }
    It 'esikte gidip gelen bellek alarmi 30 dk icinde bir kez calar; iptal edilen kosu ses vermez' {
        $script:calan = New-Object System.Collections.Generic.List[string]
        function SesCal([string]$tur) { $script:calan.Add($tur) }
        function Bildir([string]$b, [string]$m, [string]$t = '') { }
        $script:olayGoruldu = $null; $script:olaySon = @{}
        $hata = @{ Onaylar = @(); Kosular = @(); Teshis = @(@{ Seviye = 'err'; Anahtar = 'commit'; Metin = 'bellek %85' }) }
        $sakin = @{ Onaylar = @(); Kosular = @(); Teshis = @() }
        OlaylariBildir $sakin                       # ilk okuma tohumlar
        OlaylariBildir $hata; OlaylariBildir $sakin; OlaylariBildir $hata; OlaylariBildir $sakin; OlaylariBildir $hata
        @($script:calan) -join ',' | Should Be 'hata'
        OlaylariBildir @{ Onaylar = @(); Teshis = @(); Kosular = @(@{ Bitmis = $true; RunId = 'R9'; Rozet = 'iptal' }) }
        @($script:calan) -join ',' | Should Be 'hata'
        OlaylariBildir @{ Onaylar = @(); Teshis = @(); Kosular = @(@{ Bitmis = $true; RunId = 'R8'; Rozet = 'basarisiz' }) }
        @($script:calan) -join ',' | Should Be 'hata,hata'
    }
    It 'kosu sonucu tonu: basarisiz hata, uyariyla yumusak, iptal sessiz, hata her seyi bastirir' {
        KosuSonucTon 'basarisiz' | Should Be 'hata'
        KosuSonucTon 'dogrulandi' | Should Be 'kosu'
        KosuSonucTon 'uyarili' | Should Be 'uyari'
        KosuSonucTon 'iptal' | Should Be ''
        OlayTonu @('kosu:R1') @{ 'kosu:R1' = '' } | Should Be ''
        OlayTonu @('kosu:R1') @{ 'kosu:R1' = 'hata' } | Should Be 'hata'
        OlayTonu @('kosu:R1', 'onay:baslat R2') @{ 'kosu:R1' = 'kosu' } | Should Be 'onay'
        OlayTonu @('hata:commit', 'onay:x') @{} | Should Be 'hata'
    }
    It 'tek kare: yardim katmani ve 24 saatlik serit her genislikte tam cerceve' {
        $vault = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
        foreach ($w in @(90, 170)) {
            $eskiKod = [Console]::OutputEncoding; [Console]::OutputEncoding = [Text.Encoding]::UTF8
            try { $out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'merkez.ps1') -Vault $vault -Tek -Yardim -Genislik $w -Yukseklik 40 2>&1 | Out-String } finally { [Console]::OutputEncoding = $eskiKod }
            $plain = [regex]::Replace($out, ([string][char]27 + '\[[0-9;?]*[A-Za-z]'), '')
            $plain | Should Match 'YARDIM'
            $plain | Should Match 'ilk soruna atla'
            foreach ($l in @($plain -split "`r?`n" | Where-Object { $_ })) { "$w`:$($l.Length)" | Should Be "$w`:$w" }
        }
        $b = Get-MerkezBugun (Get-BeyinPaths -Vault $vault) @{} @() (Get-Date)
        @($b.Son24).Count | Should Be 24
    }
}

Describe 'merkez 1.6.0: guvenlik (son hat koruyucu, beyaz liste, maskeleme, panel kimligi)' {
    BeforeAll {
        . (Join-Path (Split-Path $PSScriptRoot -Parent) 'hooks\lib.ps1')
        . (Join-Path $PSScriptRoot 'beyin-ciz.ps1')
        . (Join-Path $PSScriptRoot 'merkez-veri.ps1')
        $script:E = [string][char]27; $script:B = [string][char]7
    }
    It 'son hat koruyucu yalniz SGR renk kodunu gecirir; OSC, imlec, ekran silme, C1 ve yon kontrol silinir' {
        $g = Get-CizGuvenliSatir ("a$($E)[31mX$($E)]0;PWN$($B)Y$($E)[2JZ$($E)]52;c;QUJD$($E)\W" + [char]0x9B + 'K' + [char]0x202E + 'Q')
        $g | Should Be "a$($E)[31mXYZWKQ"
    }
    It 'beyaz liste: tur basina tam eslesme; saldirgan kuyrugu ve Unicode rakam reddedilir' {
        Test-MerkezGuvenliKomut 'beyin aktar -Tamam 20261011T125258-13ee' | Should Be $true
        Test-MerkezGuvenliKomut 'beyin takim resume --run R20261015-4368 --wait' | Should Be $true
        Test-MerkezGuvenliKomut 'beyin guncelle -Uygula' | Should Be $false
        Test-MerkezGuvenliKomut 'beyin kirp -Uygula' | Should Be $false
        Test-MerkezGuvenliKomut ('onayla TASK-' + [char]0xFF10 + '46') | Should Be $false
        Test-MerkezGuvenliKomut 'onayla TASK-46 ve baska bir sey' | Should Be $false
        Get-MerkezSatirKomut @{ Tur = 'teshis'; Nesne = @{ Metin = 'eski aktarim x · beyin guncelle -Uygula' } } | Should Be $null
        (Get-MerkezSatirKomut @{ Tur = 'teshis'; Nesne = @{ Metin = 'eski · oku, sonra satirda c ile kapat · beyin aktar' } }).Komut | Should Be 'beyin aktar'
    }
    It 'son hat koruyucu izin listesi: ozel/ara bayt CSI de silinir, yalniz SGR kalir' {
        foreach ($d in @("$($E)[>0c", "$($E)[=c", "$($E)[!p", "$($E)[ q", "$($E)[>4;2m", "$($E)[?1`$p", "$($E)[5``", "$($E)7", "$($E)")) {
            (Get-CizGuvenliSatir ("a" + $d + "b")).IndexOf([char]27) | Should Be -1
        }
        Get-CizGuvenliSatir "$($E)[1mok$($E)[38;2;1;2;3m!$($E)[0m" | Should Be "$($E)[1mok$($E)[38;2;1;2;3m!$($E)[0m"
    }
    It 'kimlik: sondaki satir sonu ve yol gezinme reddedilir; maskeyi sifir genislik atlatamaz' {
        Test-BeyinTakimKimlik "R1`n" | Should Be $false
        Test-BeyinTakimKimlik '..' | Should Be $false
        Test-BeyinTakimKimlik 'R20261015-4368' | Should Be $true
        Protect-MerkezSatir ('anahtar sk-' + [char]0x200B + 'abcdefghijklmnopqrstuv') 120 | Should Not Match 'abcdefghijkl'
    }
    It 'maskeleme: JSON tirnakli parola, cerez ve oturum parametresi' {
        Protect-MerkezSatir 'curl -d {"password":"hunter2"} x' 120 | Should Not Match 'hunter2'
        Protect-MerkezSatir 'Cookie: sid=abc123def' 120 | Should Not Match 'abc123def'
        Protect-MerkezSatir 'https://x/y?sig=SECRETSIG&a=1' 120 | Should Not Match 'SECRETSIG'
    }
    It 'panel argumani: tirnak/; iceren gorev ya da kosu kimligiyle wt argumani uretilmez' {
        $p = @{ Scripts = 'C:\x'; Vault = 'C:\v' }
        Get-BeyinTakimPanelArgv -Paths $p -RunId 'R20261015-4368' -TaskId 'x" ; new-tab calc "' | Should Be $null
        Get-BeyinTakimPanelArgv -Paths $p -RunId 'R1;calc' -TaskId 'TASK-1' | Should Be $null
        @(Get-BeyinTakimPanelArgv -Paths $p -RunId 'R20261015-4368' -TaskId 'TASK-069').Count | Should BeGreaterThan 5
    }
}

Describe 'merkez 1.6.1: Claude Code Workflow/Agent iscileri gorunur (B1, 2026-10-19)' {
    BeforeAll {
        . (Join-Path (Split-Path $PSScriptRoot -Parent) 'hooks\lib.ps1')
        . (Join-Path $PSScriptRoot 'beyin-ciz.ps1')
        . (Join-Path $PSScriptRoot 'merkez-veri.ps1')
        $script:kok = Join-Path ([IO.Path]::GetTempPath()) ('claude-kok-' + [guid]::NewGuid().ToString('N'))
        $ses = Join-Path $script:kok 'C--Users-ali-Desktop-ornek-proje\s-111\subagents'
        $wfA = Join-Path $ses 'workflows\wf_canli-01'; $wfB = Join-Path $ses 'workflows\wf_eski-02'
        New-Item -ItemType Directory -Force -Path $wfA, $wfB | Out-Null
        $j = @('{"type":"launched"}',
               '{"type":"started","key":"k1","agentId":"a1","label":"verify:ui","phase":"Verify"}',
               '{"type":"started","key":"k2","agentId":"a2","label":"verify:turkish","phase":"Verify"}',
               '{"type":"started","key":"k3","agentId":"a3","label":"review:code","phase":"Review"}',
               '{"type":"result","key":"k1","agentId":"a1","result":{"summary":"ok"}}',
               '{"type":"failed","key":"k2","agentId":"a2"}')
        [IO.File]::WriteAllLines((Join-Path $wfA 'journal.jsonl'), [string[]]$j)
        [IO.File]::WriteAllLines((Join-Path $wfB 'journal.jsonl'), [string[]]@('{"type":"started","key":"x","label":"eski:is","phase":"P"}'))
        (Get-Item (Join-Path $wfB 'journal.jsonl')).LastWriteTime = (Get-Date).AddHours(-5)
        [IO.File]::WriteAllText((Join-Path $ses 'agent-b1.jsonl'), '{}')
        [IO.File]::WriteAllText((Join-Path $ses 'agent-b1.meta.json'), '{"agentType":"agentchef:qa-lead","description":"kenar durum testi"}')
        [IO.File]::WriteAllText((Join-Path $ses 'agent-b2.jsonl'), '{}')
        (Get-Item (Join-Path $ses 'agent-b2.jsonl')).LastWriteTime = (Get-Date).AddMinutes(-30)
    }
    AfterAll { Remove-Item -LiteralPath $script:kok -Recurse -Force -ErrorAction SilentlyContinue }
    It 'Workflow journal sayilir: 3 basladi, 1 bitti, 1 hata -> 1 acik, calisiyor; 2 sa disindaki workflow listelenmez' {
        $ci = (Get-MerkezClaudeIsler -Kok $script:kok).ToArray()
        $wf = @($ci | Where-Object { $_.Tur -eq 'workflow' })
        $wf.Count | Should Be 1
        $wf[0].Kimlik | Should Be 'wf_canli-01'
        $wf[0].Proje | Should Be 'ornek-proje'
        $wf[0].Toplam | Should Be 3; $wf[0].Biten | Should Be 1; $wf[0].Hata | Should Be 1; $wf[0].Calisan | Should Be 1
        $wf[0].Durum | Should Be 'calisiyor'
        $wf[0].Faz | Should Be 'Review'
        $wf[0].Ad | Should Be 'verify, review'
    }
    It 'Agent araciyla acilan alt ajanlar oturum basina tek satir: 2 ajan, 1 acik, meta aciklamasi' {
        $ag = @((Get-MerkezClaudeIsler -Kok $script:kok).ToArray() | Where-Object { $_.Tur -eq 'ajan' })
        $ag.Count | Should Be 1
        $ag[0].Toplam | Should Be 2; $ag[0].Calisan | Should Be 1; $ag[0].Durum | Should Be 'calisiyor'
        $ag[0].Ad | Should Be 'kenar durum testi'
    }
    It 'canli pencere disinda kalan acik workflow "sessiz" olur, calisiyor sayilmaz' {
        $wf = @((Get-MerkezClaudeIsler -Kok $script:kok -Simdi (Get-Date).AddMinutes(10)).ToArray() | Where-Object { $_.Tur -eq 'workflow' })
        $wf[0].Durum | Should Be 'sessiz'; $wf[0].Calisan | Should Be 0
    }
    It 'proje adi cozumu ve olmayan kok' {
        Get-MerkezProjeAd 'C--Users-ali-Documents-Beyin' | Should Be 'Beyin'
        Get-MerkezProjeAd 'C--Users-ali' | Should Be 'ev'
        Get-MerkezProjeAd 'C--' | Should Be 'kök'
        (Get-MerkezClaudeIsler -Kok (Join-Path $script:kok 'yok')).Count | Should Be 0
    }
    It 'Get-MerkezAnlik ClaudeIsler alanini doldurur (tam turda)' {
        $vault = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
        $a = Get-MerkezAnlik -Paths (Get-BeyinPaths -Vault $vault) -Onbellek @{} -ClaudeKok $script:kok
        @($a.ClaudeIsler | Where-Object { $_.Durum -eq 'calisiyor' }).Count | Should Be 2
    }
    It 'tek kare: 3. sekmede CLAUDE ISCILERI bolumu; Genel kartinda "Claude isi calisiyor"; her genislikte tam cerceve' {
        $vault = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
        $eskiKok = $env:BEYIN_CLAUDE_PROJE_KOK; $env:BEYIN_CLAUDE_PROJE_KOK = $script:kok
        try {
            foreach ($w in @(90, 170)) {
                foreach ($sek in @('Kosular', 'Genel')) {
                    $eskiKod = [Console]::OutputEncoding; [Console]::OutputEncoding = [Text.Encoding]::UTF8
                    try { $out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'merkez.ps1') -Vault $vault -Tek -Sekme $sek -Genislik $w -Yukseklik $(if ($sek -eq 'Genel') { 120 } else { 50 }) 2>&1 | Out-String } finally { [Console]::OutputEncoding = $eskiKod }   # Genel: canli vault uzunlugundan bagimsiz olsun diye yuksek pencere
                    $plain = [regex]::Replace($out, ([string][char]27 + '\[[0-9;?]*[A-Za-z]'), '')
                    if ($sek -eq 'Kosular') { $plain | Should Match 'CLAUDE İŞÇİLERİ \(2 çalışıyor'; $plain | Should Match 'ornek-proje' }
                    else { $plain | Should Match 'CLAUDE İŞÇİLERİ \(2 çalışıyor' }
                    if ($sek -eq 'Genel' -and $w -ge 120) { $plain | Should Match 'Claude işi çalışıyor' }
                    if ($sek -eq 'Genel') { $plain | Should Not Match 'çalışan koşu yok' }
                    foreach ($l in @($plain -split "`r?`n" | Where-Object { $_ })) { "$sek/$w`:$($l.Length)" | Should Be "$sek/$w`:$w" }
                }
            }
        } finally { $env:BEYIN_CLAUDE_PROJE_KOK = $eskiKok }
    }
}

Describe 'merkez 1.6.1: canli korelasyon - onerilen komut, yenile, taze kaynak (2026-10-19)' {
    BeforeAll {
        . (Join-Path (Split-Path $PSScriptRoot -Parent) 'hooks\lib.ps1')
        . (Join-Path $PSScriptRoot 'beyin-ciz.ps1')
        . (Join-Path $PSScriptRoot 'merkez-veri.ps1')
    }
    It 'makbuz sayaci onerilen komutun son calismasini tutar; aktar yalniz kapatinca (listeleme kanit degil)' {
        $d = Join-Path ([IO.Path]::GetTempPath()) ('mkb-' + [guid]::NewGuid().ToString('N')); New-Item -ItemType Directory -Force -Path $d | Out-Null
        try {
            $g = Get-Date '2026-10-19 12:00'
            $sat = @('{"ts":"2026-10-19T12:15:00+03:00","script":"bekci","outcome":"BEKCI_RAPOR","agent":"cli"}',
                     '{"ts":"2026-10-19T12:16:00+03:00","script":"aktar","outcome":"GOSTERILDI","agent":"cli"}',
                     '{"ts":"2026-10-19T12:20:00+03:00","script":"maliyet","outcome":"MALIYET_OK","agent":"cli"}',
                     '{"ts":"2026-10-19T12:10:00+03:00","script":"aktar","outcome":"AKTAR_TAMAM","agent":"cli"}')
            [IO.File]::WriteAllLines((Join-Path $d '2026-10-19.jsonl'), [string[]]$sat)
            $s = Get-MerkezGunSayac $d $g @{}
            ([datetime]$s.Son['bekci']).ToString('HH:mm') | Should Be (([datetime]'2026-10-19T12:15:00+03:00').ToString('HH:mm'))
            ([datetime]$s.Son['maliyet']).ToString('HH:mm') | Should Be (([datetime]'2026-10-19T12:20:00+03:00').ToString('HH:mm'))
            ([datetime]$s.Son['aktar']).ToString('HH:mm') | Should Be (([datetime]'2026-10-19T12:10:00+03:00').ToString('HH:mm'))
        } finally { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue }
    }
    It 'eski aktarim teshisi: c dogrudan beyaz listeli kapatma komutunu kopyalar (eskiden yalniz listeleme komutu)' {
        $t = Get-MerkezEskiAktarim @(@{ id = '20261011T125258-13ee'; ts = (Get-Date).AddDays(-8).ToString('o'); toProject = 'ornek.proje' }) (Get-Date)
        $t.Metin | Should Match 'beyin aktar -Tamam 20261011T125258-13ee$'
        (Get-MerkezSatirKomut @{ Tur = 'teshis'; Nesne = $t }).Komut | Should Be 'beyin aktar -Tamam 20261011T125258-13ee'
    }
    It 'panel kaynagi en cok 1 dk eski olcumle ister; r (KaynakTaze) yeniden olcturur' {
        $script:istenenDk = 'yok'
        function Get-BeyinKaynakOzeti { param($Paths, [int]$CommitEsik = 85, [int]$BostaDk = 120, [string]$SessionKey = '', $OnbellekDk = 'verilmedi') $script:istenenDk = $OnbellekDk; return @{ Ok = $true; CommitYuzde = 50; BosRamGB = 10.0; BostaOturum = 0; OnerilenAjan = 5 } }
        $vault = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent; $pp = Get-BeyinPaths -Vault $vault
        [void](Get-MerkezAnlik -Paths $pp -Onbellek @{} -ClaudeKok 'C:\yok-klasor')
        $script:istenenDk | Should Be 1
        $o = @{ KaynakTaze = $true }
        [void](Get-MerkezAnlik -Paths $pp -Onbellek $o -ClaudeKok 'C:\yok-klasor')
        $script:istenenDk | Should Be 0
        $o.KaynakTaze | Should Be $false
    }
    It 'alt cubukta r yenile her zaman gorunur ve yardim r tusunu anlatir' {
        $vault = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
        $eskiKod = [Console]::OutputEncoding; [Console]::OutputEncoding = [Text.Encoding]::UTF8
        try {
            $out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'merkez.ps1') -Vault $vault -Tek -Sekme Kosular -Genislik 170 -Yukseklik 40 2>&1 | Out-String
            $yar = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'merkez.ps1') -Vault $vault -Tek -Yardim -Genislik 170 -Yukseklik 60 2>&1 | Out-String
        } finally { [Console]::OutputEncoding = $eskiKod }
        $plain = [regex]::Replace($out, ([string][char]27 + '\[[0-9;?]*[A-Za-z]'), '')
        @($plain -split "`r?`n" | Where-Object { $_ -match '^╰' })[0] | Should Match 'r yenile'
        [regex]::Replace($yar, ([string][char]27 + '\[[0-9;?]*[A-Za-z]'), '') | Should Match 'kaynağı yeniden ölçer'
    }
}

Describe 'merkez 1.6.2: takim kosusu kapasitesi gorunur (AgentChef 1.8.2 capacity alanlari, 2026-10-19)' {
    BeforeAll {
        . (Join-Path (Split-Path $PSScriptRoot -Parent) 'hooks\lib.ps1')
        . (Join-Path $PSScriptRoot 'beyin-ciz.ps1')
        . (Join-Path $PSScriptRoot 'merkez-veri.ps1')
    }
    It 'sahip asimi: onerilen 0 · sahip onayi 1 (uyari renginde)' {
        $k = Get-MerkezKosuKapasite ([pscustomobject]@{ maxWorkers = 1; capacity = [pscustomobject]@{ recommended = 0; requested = 1; ownerOverride = $true; reason = 'commit %88 >= 85' }; history = @() })
        $k.Metin | Should Be 'önerilen 0 · sahip onayı 1'
        $k.Uyari | Should Be $true
    }
    It 'baslangicta dusurme: capacity_lowered olayi "başlangıçta 2→1 (neden)" olarak' {
        $k = Get-MerkezKosuKapasite ([pscustomobject]@{ maxWorkers = 1; capacity = [pscustomobject]@{ recommended = 2; ownerOverride = $false; atStart = [pscustomobject]@{ recommended = 1 } }
                                     history = @([pscustomobject]@{ event = 'planned' }, [pscustomobject]@{ event = 'capacity_lowered'; from = 2; to = 1; reason = 'commit %86 >= 85 (bellek dolu)' }) })
        $k.Metin | Should Be 'önerilen 2 · başlangıçta 2→1 (commit %86 >= 85 (bellek dolu))'
        $k.Uyari | Should Be $true
    }
    It 'baslangicta olcum degistiyse ama dusurme yoksa bilgi; kapasite alani olmayan eski kayitta bos' {
        (Get-MerkezKosuKapasite ([pscustomobject]@{ capacity = [pscustomobject]@{ recommended = 1; atStart = [pscustomobject]@{ recommended = 3 } }; history = @() })).Metin | Should Be 'önerilen 1 · başlangıçta önerilen 3'
        (Get-MerkezKosuKapasite ([pscustomobject]@{ runId = 'R1'; history = @() })).Metin | Should Be ''
    }
    It 'tek kare: 3. sekmede kosu satirinin altinda kapasite satiri' {
        $fx = Join-Path ([IO.Path]::GetTempPath()) ('kap-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path (Join-Path $fx 'motor\hooks') | Out-Null
        try {
            Copy-Item (Join-Path (Split-Path $PSScriptRoot -Parent) 'hooks\lib.ps1') (Join-Path $fx 'motor\hooks')
            . (Join-Path $fx 'motor\hooks\lib.ps1'); $pp = Get-BeyinPaths -Vault $fx
            New-Item -ItemType Directory -Force -Path $pp.TeamRuns | Out-Null
            $bas = (Get-Date).ToUniversalTime().AddMinutes(-2).ToString('o')
            $kos = @{ runId = 'R20261019-kap1'; repoName = 'demo'; status = 'running'; baseBranch = 'main'; startedAt = $bas; maxWorkers = 1
                      capacity = @{ recommended = 0; requested = 1; ownerOverride = $true; reason = 'commit %88 >= 85' }
                      supervisor = @{ pid = $PID; heartbeatAt = (Get-Date).ToUniversalTime().ToString('o') }
                      workers = @(@{ taskId = 'TASK-1'; role = 'qa_lead'; status = 'running'; startedAt = $bas; pid = $PID }); history = @(@{ at = $bas; event = 'started' }) }
            Set-Content -LiteralPath (Join-Path $pp.TeamRuns 'R20261019-kap1.json') -Value ($kos | ConvertTo-Json -Depth 6) -Encoding UTF8
            $eskiKod = [Console]::OutputEncoding; [Console]::OutputEncoding = [Text.Encoding]::UTF8
            try { $out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'merkez.ps1') -Vault $fx -Tek -Sekme Kosular -Genislik 150 -Yukseklik 40 2>&1 | Out-String } finally { [Console]::OutputEncoding = $eskiKod }
            $plain = [regex]::Replace($out, ([string][char]27 + '\[[0-9;?]*[A-Za-z]'), '')
            $plain | Should Match 'kapasite önerilen 0 · sahip onayı 1'
            foreach ($l in @($plain -split "`r?`n" | Where-Object { $_ })) { "150:$($l.Length)" | Should Be '150:150' }
        } finally { Remove-Item -LiteralPath $fx -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

Describe 'merkez 1.6.4: kart son durumu isci durumunu belirler (salt-okunur kosu, 2026-10-19)' {
    BeforeAll {
        . (Join-Path (Split-Path $PSScriptRoot -Parent) 'hooks\lib.ps1')
        . (Join-Path $PSScriptRoot 'beyin-ciz.ps1')
        . (Join-Path $PSScriptRoot 'merkez-veri.ps1')
    }
    It 'collected + verdict warn: kart done -> bitti, cancelled -> kapali, blocked -> engelli; kart acikken eski davranis (inceleme)' {
        (Get-MerkezDurum @{ Tur = 'isci'; IsciDurum = 'collected'; Verdict = 'warn'; KartDurum = 'done' }).Durum | Should Be 'bitti'
        (Get-MerkezDurum @{ Tur = 'isci'; IsciDurum = 'collected'; Verdict = 'partial'; KartDurum = 'cancelled' }).Durum | Should Be 'kapali'
        (Get-MerkezDurum @{ Tur = 'isci'; IsciDurum = 'collected'; Verdict = 'warn'; KartDurum = 'blocked' }).Durum | Should Be 'engelli'
        (Get-MerkezDurum @{ Tur = 'isci'; IsciDurum = 'collected'; Verdict = 'warn'; KartDurum = 'review' }).Durum | Should Be 'inceleme'
        (Get-MerkezDurum @{ Tur = 'isci'; IsciDurum = 'running'; Verdict = ''; KartDurum = 'blocked'; NabizSn = 5 }).Durum | Should Be 'calisiyor'
    }
    It 'butun kartlari kapanmis salt-okunur kosu aktif sayilmaz; kanatta isci kalmaz, acik kartli kosu kalir' {
        $fx = Join-Path ([IO.Path]::GetTempPath()) ('kart-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path (Join-Path $fx 'motor\hooks') | Out-Null
        try {
            Copy-Item (Join-Path (Split-Path $PSScriptRoot -Parent) 'hooks\lib.ps1') (Join-Path $fx 'motor\hooks')
            $pp = Get-BeyinPaths -Vault $fx; New-Item -ItemType Directory -Force -Path $pp.TeamRuns, (Split-Path $pp.Board -Parent) | Out-Null
            $bas = (Get-Date).ToUniversalTime().AddMinutes(-30).ToString('o')
            $yaz = { param($id, $tasks) Set-Content -LiteralPath (Join-Path $pp.TeamRuns "$id.json") -Encoding UTF8 -Value (@{ runId = $id; repoName = 'demo'; status = 'collected'; baseBranch = 'main'; startedAt = $bas
                       workers = @($tasks | ForEach-Object { @{ taskId = $_; role = 'code_reviewer'; status = 'collected'; verdict = 'warn'; startedAt = $bas; finishedAt = $bas } }); history = @() } | ConvertTo-Json -Depth 6) }
            & $yaz 'R20261019-kapali' @('TASK-VP-K1', 'TASK-VP-K2')
            & $yaz 'R20261019-acik' @('TASK-VP-A1')
            Set-Content -LiteralPath $pp.Board -Encoding UTF8 -Value (@{ schemaVersion = 4; tasks = @(@{ id = 'TASK-VP-K1'; status = 'done'; title = 'k1' }, @{ id = 'TASK-VP-K2'; status = 'cancelled'; title = 'k2' }, @{ id = 'TASK-VP-A1'; status = 'review'; title = 'a1' }) } | ConvertTo-Json -Depth 6)
            $a = Get-MerkezAnlik -Paths $pp -Onbellek @{} -ClaudeKok 'C:\yok-klasor'
            $kapali = @($a.Kosular | Where-Object { $_.RunId -eq 'R20261019-kapali' })
            $kapali.Count | Should Be 1; $kapali[0].Bitmis | Should Be $true
            @($a.Ajanlar | Where-Object { $_.Tur -eq 'isci' -and $_.Ad -in @('TASK-VP-K1', 'TASK-VP-K2') }).Count | Should Be 0
            $acik = @($a.Ajanlar | Where-Object { $_.Tur -eq 'isci' -and $_.Ad -eq 'TASK-VP-A1' })
            $acik.Count | Should Be 1; $acik[0].Durum | Should Be 'inceleme'
        } finally { Remove-Item -LiteralPath $fx -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

Describe 'merkez 1.6.4: salt okunur kosu bitisi (collected / completed, 2026-10-19)' {
    BeforeAll {
        . (Join-Path (Split-Path $PSScriptRoot -Parent) 'hooks\lib.ps1')
        . (Join-Path $PSScriptRoot 'beyin-ciz.ps1')
        . (Join-Path $PSScriptRoot 'merkez-veri.ps1')
        $script:isci = { param($id, $yaz) [pscustomobject]@{ taskId = $id; status = 'collected'; verdict = 'pass'; writeScope = @($yaz | Where-Object { $_ }) } }
    }
    It 'collected + butun isciler collected + yazma kapsami bos: raporlar, bitmis, butunlestir onerisi yok' {
        $k = [pscustomobject]@{ runId = 'R1'; status = 'collected'; workers = @((& $isci 'TASK-A' $null), (& $isci 'TASK-B' $null)); history = @() }
        $e = Get-MerkezKosuEtkin $k @{}
        $e.status | Should Be 'aborted'; $k.status | Should Be 'collected'   # kayit degismez, kopya doner
        (Get-MerkezKosuSonraki $e $false).Metin | Should Be 'raporlar teslim alındı · salt okunur koşu kapatıldı'
        (Get-MerkezKosuOzet $e).Rozet | Should Be 'raporlar'
    }
    It 'yazma kapsamli ama kartlari kapali kosu da biter; kartlari acik yazan kosu bütünleştir der' {
        $k = [pscustomobject]@{ runId = 'R2'; status = 'collected'; workers = @((& $isci 'TASK-C' 'src/a.ts')); history = @() }
        (Get-MerkezKosuSonraki (Get-MerkezKosuEtkin $k @{ 'TASK-C' = 'done' }) $false).Metin | Should Match 'raporlar teslim alındı'
        (Get-MerkezKosuSonraki (Get-MerkezKosuEtkin $k @{ 'TASK-C' = 'review' }) $false).Metin | Should Match 'bütünleştir'
    }
    It 'motorun completed durumu: tam ve kismi' {
        $k = [pscustomobject]@{ runId = 'R3'; status = 'completed'; completion = [pscustomobject]@{ partial = $false }; workers = @((& $isci 'TASK-D' $null)); history = @() }
        (Get-MerkezKosuSonraki (Get-MerkezKosuEtkin $k @{}) $false).Metin | Should Be 'raporlar teslim alındı · salt okunur koşu kapatıldı'
        $kp = [pscustomobject]@{ runId = 'R4'; status = 'completed'; completion = [pscustomobject]@{ partial = $true }; workers = @([pscustomobject]@{ taskId = 'TASK-E'; status = 'failed' }); history = @() }
        $s = Get-MerkezKosuSonraki (Get-MerkezKosuEtkin $kp @{}) $false
        $s.Metin | Should Be 'yarım kaldı · bir işçi toplanmadı ya da kararı kısmi/başarısız · salt okunur koşu kapatıldı'; $s.Renk | Should Be 'warn'
    }
    It 'anlik goruntude: salt okunur collected kosu Bitmis, sonraki adim raporlar' {
        $fx = Join-Path ([IO.Path]::GetTempPath()) ('so-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path (Join-Path $fx 'motor\hooks') | Out-Null
        try {
            Copy-Item (Join-Path (Split-Path $PSScriptRoot -Parent) 'hooks\lib.ps1') (Join-Path $fx 'motor\hooks')
            $pp = Get-BeyinPaths -Vault $fx; New-Item -ItemType Directory -Force -Path $pp.TeamRuns | Out-Null
            $bas = (Get-Date).ToUniversalTime().AddMinutes(-50).ToString('o')
            Set-Content -LiteralPath (Join-Path $pp.TeamRuns 'R20261019-so1.json') -Encoding UTF8 -Value (@{ runId = 'R20261019-so1'; repoName = 'demo'; status = 'collected'; startedAt = $bas
                workers = @(@{ taskId = 'TASK-S1'; status = 'collected'; verdict = 'pass'; writeScope = @() }); history = @(@{ at = $bas; event = 'collected' }) } | ConvertTo-Json -Depth 6)
            $a = Get-MerkezAnlik -Paths $pp -Onbellek @{} -ClaudeKok 'C:\yok-klasor'
            $r = @($a.Kosular | Where-Object { $_.RunId -eq 'R20261019-so1' })[0]
            $r.Bitmis | Should Be $true
            $r.Sonraki.Metin | Should Match 'raporlar teslim alındı'
        } finally { Remove-Item -LiteralPath $fx -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

Describe 'merkez 1.6.4: salt okunur kosu suresi son isci bitisinde durur (2026-10-20)' {
    BeforeAll {
        . (Join-Path (Split-Path $PSScriptRoot -Parent) 'hooks\lib.ps1')
        . (Join-Path $PSScriptRoot 'beyin-ciz.ps1')
        . (Join-Path $PSScriptRoot 'merkez-veri.ps1')
    }
    It 'completed kosu: yeniden toplama 12 saat sonra olsa da sure = baslangic -> son isci finishedAt (3 dk)' {
        $bas = [datetime]'2026-10-19T22:18:00Z'; $isci = $bas.AddMinutes(3); $yeniden = $bas.AddHours(12)
        $k = [pscustomobject]@{ runId = 'R1'; status = 'completed'; startedAt = $bas.ToString('o'); completion = [pscustomobject]@{ at = $yeniden.ToString('o'); partial = $false }
            workers = @([pscustomobject]@{ taskId = 'TASK-A'; status = 'collected'; finishedAt = $bas.AddMinutes(2).ToString('o') }, [pscustomobject]@{ taskId = 'TASK-B'; status = 'collected'; finishedAt = $isci.ToString('o') })
            history = @([pscustomobject]@{ at = $bas.ToString('o'); event = 'started' }, [pscustomobject]@{ at = $yeniden.ToString('o'); event = 'completed_read_only' }) }
        $o = Get-MerkezKosuOzet (Get-MerkezKosuEtkin $k @{}) $false ($yeniden.AddHours(1))
        [int]$o.Sure | Should Be 180
    }
    It 'isci finishedAt yoksa completion.at kullanilir' {
        $bas = [datetime]'2026-10-19T22:18:00Z'
        $k = [pscustomobject]@{ runId = 'R2'; status = 'completed'; startedAt = $bas.ToString('o'); completion = [pscustomobject]@{ at = $bas.AddMinutes(10).ToString('o'); partial = $false }
            workers = @([pscustomobject]@{ taskId = 'TASK-A'; status = 'collected' }); history = @([pscustomobject]@{ at = $bas.AddHours(5).ToString('o'); event = 'x' }) }
        [int](Get-MerkezKosuOzet (Get-MerkezKosuEtkin $k @{}) $false ($bas.AddHours(6))).Sure | Should Be 600
    }
}
