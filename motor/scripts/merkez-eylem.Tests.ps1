# merkez-eylem.Tests.ps1 - merkez eylem katmani (2026-10-31): beyaz liste, eylem turetme, insan onayi kapisi, is kosucusu.
Describe 'merkez eylem: beyaz liste' {
    BeforeAll { . (Join-Path (Split-Path $PSScriptRoot -Parent) 'hooks\lib.ps1'); . (Join-Path $PSScriptRoot 'merkez-veri.ps1'); . (Join-Path $PSScriptRoot 'merkez-eylem.ps1') }
    It 'gecerli takim, pano, aktar ve rapor bicimleri' {
        Test-MerkezEylemArgv @('takim', 'verify', '--run', 'R20261031-a71d') | Should Be $true
        Test-MerkezEylemArgv @('takim', 'resume', '--run', 'R1', '--wait') | Should Be $true
        Test-MerkezEylemArgv @('takim', 'durdur', 'R20261031-a71d') | Should Be $true
        Test-MerkezEylemArgv @('pano', 'transition', '--task', 'TASK-DOC2-ZIMMET', '--status', 'done', '--verified-by', 'user') | Should Be $true
        Test-MerkezEylemArgv @('pano', 'transition', '--task', 'TASK-12', '--status', 'cancelled', '--reason', 'kosu-kapandi') | Should Be $true
        Test-MerkezEylemArgv @('aktar', '-Tamam', '20261031T170222-3bf5') | Should Be $true
        Test-MerkezEylemArgv @('maliyet') | Should Be $true
    }
    It 'serbest metin, kabuk islecleri, bilinmeyen alt komut ve baska dogrulayici reddedilir' {
        Test-MerkezEylemArgv @('takim', 'verify', '--run', 'R1;calc') | Should Be $false
        Test-MerkezEylemArgv @('takim', 'verify', '--run', 'R1', '&&', 'calc') | Should Be $false
        Test-MerkezEylemArgv @('guncelle', '-Uygula') | Should Be $false
        Test-MerkezEylemArgv @('pano', 'transition', '--task', 'TASK-1', '--status', 'done', '--verified-by', 'codex') | Should Be $false
        Test-MerkezEylemArgv @('pano', 'transition', '--task', 'task-1', '--status', 'done', '--verified-by', 'user') | Should Be $false
        Test-MerkezEylemArgv @('takim', 'verify', '--run', 'R 1') | Should Be $false
        Test-MerkezEylemArgv @('takim', 'verify', '--run', 'R1$(calc)') | Should Be $false
        Test-MerkezEylemArgv @() | Should Be $false
        ConvertTo-MerkezEylemArgv 'beyin takim verify --run R1 · beyin guncelle -Uygula' | Should Be $null
        (ConvertTo-MerkezEylemArgv 'beyin takim collect --run R1') -join ' ' | Should Be 'takim collect --run R1'
    }
}

Describe 'merkez eylem: satir eylemleri' {
    BeforeAll { . (Join-Path (Split-Path $PSScriptRoot -Parent) 'hooks\lib.ps1'); . (Join-Path $PSScriptRoot 'merkez-veri.ps1'); . (Join-Path $PSScriptRoot 'merkez-eylem.ps1') }
    It 'incelemedeki kart: o = insan onayi + done (dogrulayan user), toplu' {
        $e = @(Get-MerkezEylemler @{ Tur = 'kart'; Nesne = [pscustomobject]@{ id = 'TASK-DOC2-ZIMMET'; status = 'review' } })
        $e.Count | Should Be 1
        $e[0].Tus | Should BeExactly 'o'; $e[0].Insan | Should Be $true; $e[0].Toplu | Should Be $true
        $e[0].Adimlar[0].Tur | Should Be 'onay'; $e[0].Adimlar[0].Id | Should Be 'TASK-DOC2-ZIMMET'
        ($e[0].Adimlar[1].Argv -join ' ') | Should Be 'pano transition --task TASK-DOC2-ZIMMET --status done --verified-by user'
    }
    It 'surmekte olan kartin eylemi yok; yetim kart iptal tehlikeli' {
        @(Get-MerkezEylemler @{ Tur = 'kart'; Nesne = [pscustomobject]@{ id = 'TASK-1'; status = 'in_progress' } }).Count | Should Be 0
        $y = @(Get-MerkezEylemler @{ Tur = 'kart'; Nesne = [pscustomobject]@{ id = 'TASK-1'; status = 'todo' }; Yetim = $true })
        $y[0].Tus | Should BeExactly 'x'; $y[0].Tehlike | Should Be $true
    }
    It 'kosu: onay kapisi, siradaki adim, kartlari toplu onay ve durdur' {
        $k = @{ RunId = 'R20261031-a71d'; Durum = 'integrated'; Sonraki = @{ Metin = 'doğrula → beyin takim verify --run R20261031-a71d'; Onay = $false } }
        $anlik = @{ Kartlar = @([pscustomobject]@{ id = 'TASK-A'; status = 'review'; owner = [pscustomobject]@{ session = 'team-R20261031-a71d' } }, [pscustomobject]@{ id = 'TASK-B'; status = 'review'; owner = [pscustomobject]@{ session = 'team-Rbaska' } }) }
        $e = @(Get-MerkezEylemler @{ Tur = 'kosu'; Nesne = $k } $anlik)
        ($e | ForEach-Object { $_.Tus }) -join '' | Should BeExactly 'nOx'
        ($e[0].Adimlar[0].Argv -join ' ') | Should Be 'takim verify --run R20261031-a71d'; $e[0].Adimlar[0].Gorunur | Should Be $true
        @($e[1].Adimlar | Where-Object { $_.Tur -eq 'onay' }).Count | Should Be 1
        $e[2].Tehlike | Should Be $true
        $p = @(Get-MerkezEylemler @{ Tur = 'kosu'; Nesne = @{ RunId = 'R9'; Durum = 'planned'; Sonraki = @{ Metin = 'onay bekliyor → baslat R9'; Onay = $true } } })
        $p[0].Insan | Should Be $true; $p[0].Adimlar[0].OnayTur | Should Be 'baslat'; ($p[0].Adimlar[1].Argv -join ' ') | Should Be 'takim start --run R9'
    }
    It 'teshis: yapisal duzeltme, oto bayragi, coklu iptal tehlikeli, komutsuz teshis eylemsiz' {
        $t = @{ Seviye = 'info'; Metin = 'x · beyin maliyet'; Duzelt = @{ Ad = 'tara'; Argv = @('maliyet'); Oto = $true } }
        $e = Get-MerkezTeshisEylem $t; $e.Oto | Should Be $true; $e.Tus | Should BeExactly 'd'
        $c = Get-MerkezTeshisEylem @{ Seviye = 'warn'; Metin = 'yetim'; Duzelt = @{ Ad = 'iptal'; Coklu = @(, @('pano', 'transition', '--task', 'TASK-1', '--status', 'cancelled', '--reason', 'kosu-kapandi')) } }
        $c.Tehlike | Should Be $true; @($c.Adimlar).Count | Should Be 1
        Get-MerkezTeshisEylem @{ Seviye = 'warn'; Metin = 'sessiz isci' } | Should Be $null
        Get-MerkezTeshisEylem @{ Seviye = 'warn'; Metin = 'x'; Duzelt = @{ Argv = @('guncelle', '-Uygula'); Oto = $true } } | Should Be $null
    }
    It 'toplu birlestirme adimlari toplar, onay ozeti okunur' {
        $a = Get-MerkezKartKapatEylem 'TASK-1'; $b = Get-MerkezKartKapatEylem 'TASK-2'
        $j = Join-MerkezEylemler @($a, $b)
        @($j.Adimlar).Count | Should Be 4; $j.Insan | Should Be $true
        (Get-MerkezEylemHedefleri $j)[0] | Should Be 'insan onayı · TASK-1'
    }
}

Describe 'merkez eylem: insan onayi kapisi' {
    BeforeAll {
        . (Join-Path (Split-Path $PSScriptRoot -Parent) 'hooks\lib.ps1'); . (Join-Path $PSScriptRoot 'merkez-eylem.ps1')

        function Yaz-TestKasa($kok, [hashtable]$Kartlar, [hashtable]$Kosular) {
            $st = Join-Path $kok 'state'; New-Item -ItemType Directory -Force -Path $st, (Join-Path $st 'team-runs') | Out-Null
            $tasks = @($Kartlar.Keys | ForEach-Object { @{ id = $_; status = $Kartlar[$_] } })
            Set-Content -LiteralPath (Join-Path $st 'board.json') -Value (ConvertTo-Json @{ tasks = $tasks } -Depth 4) -Encoding UTF8
            foreach ($r in $Kosular.Keys) { Set-Content -LiteralPath (Join-Path $st "team-runs\$r.json") -Value (ConvertTo-Json @{ runId = $r; status = $Kosular[$r] }) -Encoding UTF8 }
            return @{ ScrState = $st; Scripts = $PSScriptRoot; Vault = $kok; Board = (Join-Path $st 'board.json'); TeamRuns = (Join-Path $st 'team-runs') }
        }
        $script:tp = Yaz-TestKasa (Join-Path $TestDrive 'k1') @{ 'TASK-77' = 'review'; 'TASK-78' = 'review'; 'TASK-79' = 'done' } @{ 'R20261031-test' = 'planned'; 'R20261031-eski' = 'running' }
    }
    It 'teyitsiz cagri onay YAZMAZ ve o kartin komutunu kuyruga almaz' {
        $r = Invoke-MerkezEylemAdimlari -Paths $script:tp -Eylem (Get-MerkezKartKapatEylem 'TASK-77')
        $r.Onay.Count | Should Be 0; $r.OnayHata.Count | Should Be 1; $r.Kuyruk.Count | Should Be 0
        Test-Path (Join-Path $script:tp.ScrState 'approvals\TASK-77.json') | Should Be $false
    }
    It 'teyitli cagri merkez kanaliyla insan onayi yazar ve done komutunu kuyruga alir' {
        $r = Invoke-MerkezEylemAdimlari -Paths $script:tp -Eylem (Get-MerkezKartKapatEylem 'TASK-78') -InsanTeyit
        $r.Onay -join ',' | Should Be 'TASK-78'; $r.Kuyruk.Count | Should Be 1
        $o = Get-BeyinOnay -Paths $script:tp -TaskId 'TASK-78'
        $o.kanal | Should Be 'merkez'; $o.ajan | Should Be 'insan'
        $k = Invoke-MerkezEylemAdimlari -Paths $script:tp -Eylem (Get-MerkezKosuKapiEylem 'baslat' 'R20261031-test') -InsanTeyit
        (Get-BeyinOnay -Paths $script:tp -TaskId 'R20261031-test' -Tur 'baslat').tur | Should Be 'baslat'
        ($k.Kuyruk[0].Argv -join ' ') | Should Be 'takim start --run R20261031-test'
    }
    It 'beyaz liste disi argv kosucu tarafindan baslatilmaz' {
        (Start-MerkezKomut -Paths $script:tp -Argv @('guncelle', '-Uygula')).Ok | Should Be $false
    }
}

Describe 'merkez eylem: inceleme regresyonlari (2026-10-31)' {
    BeforeAll {
        . (Join-Path (Split-Path $PSScriptRoot -Parent) 'hooks\lib.ps1'); . (Join-Path $PSScriptRoot 'merkez-veri.ps1'); . (Join-Path $PSScriptRoot 'merkez-eylem.ps1')

        function Yaz-TestKasa($kok, [hashtable]$Kartlar, [hashtable]$Kosular) {
            $st = Join-Path $kok 'state'; New-Item -ItemType Directory -Force -Path $st, (Join-Path $st 'team-runs') | Out-Null
            $tasks = @($Kartlar.Keys | ForEach-Object { @{ id = $_; status = $Kartlar[$_] } })
            Set-Content -LiteralPath (Join-Path $st 'board.json') -Value (ConvertTo-Json @{ tasks = $tasks } -Depth 4) -Encoding UTF8
            foreach ($r in $Kosular.Keys) { Set-Content -LiteralPath (Join-Path $st "team-runs\$r.json") -Value (ConvertTo-Json @{ runId = $r; status = $Kosular[$r] }) -Encoding UTF8 }
            return @{ ScrState = $st; Scripts = $PSScriptRoot; Vault = $kok; Board = (Join-Path $st 'board.json'); TeamRuns = (Join-Path $st 'team-runs') }
        }
        $script:tp2 = Yaz-TestKasa (Join-Path $TestDrive 'k2') @{ 'TASK-90' = 'review' } @{}
    }
    It 'teshis metnindeki ajan metni komut olmaz: aktarim kimligine gomulu durdur calistirilmaz' {
        $kotu = @{ id = 'x · beyin takim durdur R1'; ts = (Get-Date).AddDays(-5).ToString('o'); toProject = 'p' }
        # 2026-11-06: duzeltme kimlikten BAGIMSIZ sabit argv (aktar -Topla -Uygula); kimlikteki metin komuta hic girmez
        $t = Get-MerkezEskiAktarim @($kotu) (Get-Date)
        $e = Get-MerkezTeshisEylem $t
        ($e.Adimlar[0].Argv -join ' ') | Should Be 'aktar -Topla -Uygula'
        (@($e.Adimlar | ForEach-Object { $_.Argv }) -join ' ') | Should Not Match 'durdur'
        $e.Tehlike | Should Be $false; $e.Oto | Should Be $true
        Get-MerkezTeshisEylem @{ Seviye = 'warn'; Metin = 'herhangi · beyin takim durdur R1' } | Should Be $null
        $iyi = Get-MerkezEskiAktarim @(@{ id = '20261026T193246-a67b'; ts = (Get-Date).AddDays(-5).ToString('o') }) (Get-Date)
        ((Get-MerkezTeshisEylem $iyi).Adimlar[0].Argv -join ' ') | Should Be 'aktar -Topla -Uygula'
    }
    It 'durdur her yolda tehlikeli ve asla oto degil' {
        $e = Get-MerkezTeshisEylem @{ Seviye = 'err'; Metin = 'x'; Duzelt = @{ Argv = @('takim', 'durdur', 'R1'); Oto = $true } }
        $e.Tehlike | Should Be $true; $e.Oto | Should Be $false
    }
    It 'kuyruk dusunce bu partide yazilan kart onayi geri alinir' {
        $r = Invoke-MerkezEylemAdimlari -Paths $script:tp2 -Eylem (Get-MerkezKartKapatEylem 'TASK-90') -InsanTeyit
        $r.Kuyruk[0].OnayId | Should Be 'TASK-90'
        (Get-BeyinOnay -Paths $script:tp2 -TaskId 'TASK-90') | Should Not Be $null
        Revoke-MerkezOnay -Paths $script:tp2 -Idler @('TASK-90') | Should Be 1
        Get-BeyinOnay -Paths $script:tp2 -TaskId 'TASK-90' | Should Be $null
    }
}

Describe 'merkez eylem: sinif tablosu ve yurutme aninda denetim (2026-10-31 tur 2)' {
    BeforeAll {
        . (Join-Path (Split-Path $PSScriptRoot -Parent) 'hooks\lib.ps1'); . (Join-Path $PSScriptRoot 'merkez-veri.ps1'); . (Join-Path $PSScriptRoot 'merkez-eylem.ps1')
        function Yaz-TestKasa($kok, [hashtable]$Kartlar, [hashtable]$Kosular) {
            $st = Join-Path $kok 'state'; New-Item -ItemType Directory -Force -Path $st, (Join-Path $st 'team-runs') | Out-Null
            $tasks = @($Kartlar.Keys | ForEach-Object { @{ id = $_; status = $Kartlar[$_] } })
            Set-Content -LiteralPath (Join-Path $st 'board.json') -Value (ConvertTo-Json @{ tasks = $tasks } -Depth 4) -Encoding UTF8
            foreach ($r in $Kosular.Keys) { Set-Content -LiteralPath (Join-Path $st "team-runs\$r.json") -Value (ConvertTo-Json @{ runId = $r; status = $Kosular[$r] }) -Encoding UTF8 }
            return @{ ScrState = $st; Scripts = $PSScriptRoot; Vault = $kok; Board = (Join-Path $st 'board.json'); TeamRuns = (Join-Path $st 'team-runs') }
        }
        $script:tp3 = Yaz-TestKasa (Join-Path $TestDrive 'k3') @{ 'TASK-A1' = 'review'; 'TASK-A2' = 'done' } @{ 'R20261031-k' = 'running' }
    }
    It 'her kalip tek sinifa bagli; sinif eylemin Insan/Tehlike/Oto bayragini belirler' {
        Get-MerkezEylemSinif @('maliyet') | Should Be 'serbest'
        Get-MerkezEylemSinif @('takim', 'verify', '--run', 'R1') | Should Be 'adim'
        Get-MerkezEylemSinif @('takim', 'merge', '--run', 'R1') | Should Be 'onay'
        Get-MerkezEylemSinif @('takim', 'durdur', 'R1') | Should Be 'tehlike'
        Get-MerkezEylemSinif @('guncelle') | Should Be ''
        @(Get-MerkezEylemSiniflari | Where-Object { $_.Sinif -notin @('serbest', 'adim', 'onay', 'tehlike') }).Count | Should Be 0
        # Oto bayragi adim/onay/tehlike sinifinda kendiliginden duser
        (New-MerkezEylem 'x' 'n' 'x' @((New-MerkezKomutAdim @('takim', 'verify', '--run', 'R1'))) -Oto).Oto | Should Be $false
        (New-MerkezEylem 'x' 'n' 'x' @((New-MerkezKomutAdim @('takim', 'collect', '--run', 'R1'))) -Oto).Oto | Should Be $true
        (New-MerkezEylem 'x' 'x' 'x' @((New-MerkezKomutAdim @('takim', 'durdur', 'R1')))).Tehlike | Should Be $true
    }
    It 'surumdeki her eylemin komutu bir sinifa bagli (drift kapisi)' {
        $k = @{ RunId = 'R20261031-k'; Durum = 'integrated'; Sonraki = @{ Metin = 'doğrula → beyin takim verify --run R20261031-k' } }
        $hepsi = @(Get-MerkezEylemler @{ Tur = 'kosu'; Nesne = $k }) + @(Get-MerkezEylemler @{ Tur = 'kart'; Nesne = [pscustomobject]@{ id = 'TASK-1'; status = 'review' } }) + @(Get-MerkezEylemler @{ Tur = 'aktarim'; Nesne = [pscustomobject]@{ id = 'abc-1' } })
        foreach ($e in $hepsi) { foreach ($a in @($e.Adimlar | Where-Object { $_.Tur -eq 'komut' })) { "$($e.Kod): $(Get-MerkezEylemSinif @($a.Argv))" | Should Not Match ': $' } }
    }
    It 'onay penceresi ile yurutme arasinda kart kapandiysa onay yazilmaz, komut atlanir' {
        $e = Join-MerkezEylemler @((Get-MerkezKartKapatEylem 'TASK-A1'), (Get-MerkezKartKapatEylem 'TASK-A2'))
        $r = Invoke-MerkezEylemAdimlari -Paths $script:tp3 -Eylem $e -InsanTeyit
        $r.Onay -join ',' | Should Be 'TASK-A1'
        $r.Atlanan.Count | Should Be 1; $r.Atlanan[0] | Should Match 'TASK-A2'
        $r.Kuyruk.Count | Should Be 1; ($r.Kuyruk[0].Argv -join ' ') | Should Match 'TASK-A1'
        Get-BeyinOnay -Paths $script:tp3 -TaskId 'TASK-A2' | Should Be $null
    }
    It 'kosu artik planlanmis degilse baslat onayi yazilmaz' {
        $r = Invoke-MerkezEylemAdimlari -Paths $script:tp3 -Eylem (Get-MerkezKosuKapiEylem 'baslat' 'R20261031-k') -InsanTeyit
        $r.Onay.Count | Should Be 0; $r.Atlanan.Count | Should Be 1; $r.Kuyruk.Count | Should Be 0
    }
    It 'pano okunamazsa fail-closed: onay yazilmaz' {
        $bos = @{ ScrState = (Join-Path $TestDrive 'bos'); Board = (Join-Path $TestDrive 'bos\yok.json'); TeamRuns = (Join-Path $TestDrive 'bos') }
        New-Item -ItemType Directory -Force -Path $bos.ScrState | Out-Null
        $r = Invoke-MerkezEylemAdimlari -Paths $bos -Eylem (Get-MerkezKartKapatEylem 'TASK-A1') -InsanTeyit
        $r.Onay.Count | Should Be 0; $r.Atlanan.Count | Should Be 1
    }
}

Describe 'merkez: derleme tavani teshisi (2026-11-07)' {
    BeforeAll { . (Join-Path (Split-Path $PSScriptRoot -Parent) 'hooks\lib.ps1'); . (Join-Path $PSScriptRoot 'merkez-veri.ps1'); . (Join-Path $PSScriptRoot 'merkez-eylem.ps1') }
    It 'final olmayan ve tavana carpan gunu bulur, final olani ve tavan altini atlar' {
        $f = Join-Path $env:TEMP ("tavan-" + [guid]::NewGuid().ToString('N') + '.txt')
        try {
            [IO.File]::WriteAllText($f, "2026-11-01.md|partial|3`n2026-11-02.md|partial|3`n2026-11-02.md|final|3|100`n2026-11-03.md|partial|2`n2026-11-04.md|partial|1`n2026-11-04.md|partial|4`n")
            $g = @(Get-MerkezDerlemeTavani $f)
            ($g -join ',') | Should Be '2026-11-01,2026-11-04'
        } finally { Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue }
        @(Get-MerkezDerlemeTavani (Join-Path $env:TEMP 'olmayan-dosya.txt')).Count | Should Be 0
    }
    It 'teshis tek tusla derle-zorla eylemi uretir (serbest, oto) ve kopyalanabilir' {
        Get-MerkezTavanTeshis @() | Should Be $null
        $t = Get-MerkezTavanTeshis @('2026-11-06')
        $t.Metin | Should Match 'beyin derle-zorla$'
        Test-MerkezEylemArgv @('derle-zorla') | Should Be $true
        Get-MerkezEylemSinif @('derle-zorla') | Should Be 'serbest'
        $e = Get-MerkezTeshisEylem $t
        @($e.Adimlar)[0].Argv -join ' ' | Should Be 'derle-zorla'
        $e.Oto | Should Be $true
        Test-MerkezGuvenliKomut 'beyin derle-zorla' | Should Be $true
    }
}

Describe 'merkez: bakim turu B (2026-11-07)' {
    BeforeAll { . (Join-Path (Split-Path $PSScriptRoot -Parent) 'hooks\lib.ps1'); . (Join-Path $PSScriptRoot 'merkez-veri.ps1'); . (Join-Path $PSScriptRoot 'merkez-eylem.ps1') }
    It 'bakim gerekmiyorsa eylem yok' {
        Get-MerkezBakimEylemi @{ Teshis = @(); Aktarimlar = @() } | Should Be $null
        Get-MerkezBakimEylemi $null | Should Be $null
    }
    It 'gerekenleri sirayla toplar; hepsi serbest, oto ve beyaz listede' {
        $an = @{ Aktarimlar = @(@{ id = 'x1' }); Teshis = @(@{ Anahtar = 'derleme-tavan' }, @{ Anahtar = 'maliyet-eski' }, @{ Anahtar = 'commit' }) }
        $e = Get-MerkezBakimEylemi $an
        (@($e.Adimlar | ForEach-Object { @($_.Argv) -join ' ' }) -join '|') | Should Be 'aktar -Topla -Uygula|derle-zorla|maliyet'
        $e.Tus | Should Be 'B'
        $e.Oto | Should Be $true
        $e.Insan | Should Be $false
        $e.Tehlike | Should Be $false
        foreach ($s in $e.Adimlar) { Test-MerkezEylemArgv @($s.Argv) | Should Be $true }
    }
    It 'yalniz tavan varsa tek adim' {
        $e = Get-MerkezBakimEylemi @{ Aktarimlar = @(); Teshis = @(@{ Anahtar = 'derleme-tavan' }) }
        @($e.Adimlar).Count | Should Be 1
        $e.Aciklama | Should Be 'beyin derle-zorla'
    }
}