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
            Copy-Item (Join-Path $PSScriptRoot 'merkez*.ps1') $scripts
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
        $s.Metin | Should Be 'sorun yok · 1 uyarı'; $s.Renk | Should Be 'warn'; $s.Neden | Should Match '1 ajan çalışıyor'
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
            Copy-Item (Join-Path $PSScriptRoot 'merkez*.ps1') $scripts
            Copy-Item (Join-Path (Split-Path $PSScriptRoot -Parent) 'hooks\lib.ps1') $hooks
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
                $plain | Should Match '1 HATA'
                @($satirlar | Where-Object { $_ -match '▣ demo' })[0].Split([char]0x2502).Count | Should Be 3   # tek kanat: ortada sutun ayraci yok
            }
        } finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

Describe 'merkez canli panel (1.4.5): olay akisi ve guvenli simgeler' {
    BeforeAll { . (Join-Path $PSScriptRoot 'merkez-veri.ps1') }
    It 'makbuz gurultusu atilir, anlamli olay Turkce metne cevrilir' {
        ConvertTo-MerkezOlay @{ ts = (Get-Date).ToString('o'); script = 'kill-guard'; outcome = 'GECTI' } | Should Be $null
        ConvertTo-MerkezOlay @{ ts = (Get-Date).ToString('o'); script = 'retrieval'; outcome = 'ESIK_ALTI' } | Should Be $null
        $o = ConvertTo-MerkezOlay @{ ts = (Get-Date).ToString('o'); script = 'kill-guard'; outcome = 'RED'; agent = 'codex'; note = 'Stop-Process -Name x' }
        $o.Renk | Should Be 'err'; $o.Metin | Should Match 'kill guard engelledi'
        (ConvertTo-MerkezOlay @{ ts = (Get-Date).ToString('o'); script = 'retrieval'; outcome = 'ENJEKSIYON'; concepts = @('ornek-kavram.md') }).Metin | Should Match '1 kavram hatırlandı: ornek kavram'
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
