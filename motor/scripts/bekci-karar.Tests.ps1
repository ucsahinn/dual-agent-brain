# bekci-karar.Tests.ps1 - bekci 2.0 karar kurali (2026-10-31): guvenle kapat / bak / dokunma.
Describe 'bekci karar kurali' {
    BeforeAll { . (Join-Path $PSScriptRoot 'bekci-karar.ps1') }
    It 'turu bitmis, esik ustu sessiz, karti yok: guvenle kapat' {
        $k = Get-BekciKarar @{ SessizDk = 300; Tur = 'bekliyor'; KartlarAcik = 0; EsikDk = 120 }
        $k.Karar | Should Be 'kapat'; $k.Neden | Should Match 'turu bitmiş'
    }
    It 'son 10 dk etkin ya da is suruyor: dokunma' {
        (Get-BekciKarar @{ SessizDk = 3; Tur = 'bekliyor'; EsikDk = 120 }).Karar | Should Be 'dokunma'
        (Get-BekciKarar @{ SessizDk = 40; Tur = 'arac'; EsikDk = 120 }).Karar | Should Be 'dokunma'
        (Get-BekciKarar @{ SessizDk = 40; Tur = 'yazi'; EsikDk = 120 }).Karar | Should Be 'dokunma'
    }
    It 'acik kart sahibi, uzun suredir aracta ya da esik alti: bak (asla otomatik guvenli denmez)' {
        (Get-BekciKarar @{ SessizDk = 500; Tur = 'bekliyor'; KartlarAcik = 1; EsikDk = 120 }).Karar | Should Be 'bak'
        $u = Get-BekciKarar @{ SessizDk = 600; Tur = 'dusunce'; EsikDk = 120 }; $u.Karar | Should Be 'bak'; $u.Neden | Should Match 'izin onayı'
        (Get-BekciKarar @{ SessizDk = 60; Tur = 'bekliyor'; EsikDk = 120 }).Karar | Should Be 'bak'
    }
    It 'transkript okunamazsa kanit yok: guvenli denmez' {
        (Get-BekciKarar @{ SessizDk = 900; Tur = 'yok'; EsikDk = 120 }).Karar | Should Be 'bak'
        (Get-BekciKarar @{ SessizDk = 900; Tur = ''; EsikDk = 120 }).Karar | Should Be 'bak'
        (Get-BekciKarar @{ SessizDk = 30; Tur = ''; EsikDk = 120 }).Karar | Should Be 'dokunma'
    }
    It 'takim iscisi: kosu calisiyorsa dokunma, bittiyse bak (yetim)' {
        (Get-BekciKarar @{ SessizDk = 900; Tur = 'bekliyor'; Isci = $true; KosuCalisiyor = $true }).Karar | Should Be 'dokunma'
        (Get-BekciKarar @{ SessizDk = 900; Tur = 'bekliyor'; Isci = $true; KosuCalisiyor = $false }).Karar | Should Be 'bak'
    }
    It 'surec agaci toplami donguye girmez ve torunlari sayar' {
        $agac = @{ Surec = @{ 1 = @{ Pid = 1; CommitMB = 100 }; 2 = @{ Pid = 2; CommitMB = 50 }; 3 = @{ Pid = 3; CommitMB = 25 } }; Cocuk = @{ 1 = @(2); 2 = @(3, 1) } }
        $t = Get-BekciAgacToplam $agac 1
        $t.MB | Should Be 175; $t.Surec | Should Be 3
    }
    It 'sure bicimi' { Format-BekciSure 45 | Should Be '45 dk'; Format-BekciSure 90 | Should Match '^1[.,]5 sa$'; Format-BekciSure 2880 | Should Be '2 gün' }
}
