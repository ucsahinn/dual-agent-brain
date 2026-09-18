# yol-temizle.ps1 - Makine bolgesindeki MUTLAK KULLANICI YOLLARINI kisaltir.
#
# NEDEN (2026-09-10 denetimi): motorun cikti temizleyicisi yalniz
# 'C:\Users\<ad>\' bicimini kisaltiyordu. Ajanlar Git Bash / Node / WSL / uzak
# sunucu baglaminda yollari ileri egik cizgiyle ve POSIX bicimiyle yaziyor:
#   C:/Users/<ad>/...      -> gunluk logda commit edilmis halde bulundu
#   /home/<ad>/...         -> uzak Linux oturumlarindan; olculdu: 7 satirda
# Vault sozlesmesi (AGENTS.md, Privacy And Secrets) ozel mutlak yollari
# yasakliyor; doktor'un 'mutlak yol' satiri artik bunlari da goruyor.
#
# Motor ILERIYE DONUK duzeltildi (flush.ps1 uc bicimi de kisaltiyor). Bu betik
# GECMISTEKI dosyalari temizler. Makine bolgesi (85-daylogs, 86-compiled) motor
# tarafindan sona eklenerek yazilir; bu degisiklik satir icinde kalir ve blok
# yapisini bozmaz.
#
# Varsayilan KURU CALISMA. Uygulamak icin -Uygula.
# Dosyalar git ile izleniyor: -Uygula sonrasi 'git diff' ile gozden gecir.
#
# MAKBUZ (2026-09-17, bagimsiz denetim - F5): bu betik NOT ICERIGINI degistiriyor
# ama hic makbuz yazmiyordu. Olculdu: -Uygula 4 gunluk logda 33 mutlak yolu
# kisalttiktan sonra makbuz dizini BOS kaldi - 'notumu ne degistirdi' sorusu
# makbuzdan cevaplanamiyordu. Artik diger yazicilarla ayni sozlesme kullanilir
# (-Script/-Outcome/-Files @(@{p;b;a})/-Note); kuru kosuda da makbuz yazilir,
# outcome ayridir (YOL_KURU).

param(
    # TASINABILIRLIK (2026-09-10): vault yolu artik GOMULU DEGIL.
    # Oncelik: -Vault parametresi > BEYIN_VAULT ortam degiskeni > betigin kendi
    # konumundan turetme (<vault>\motor\scripts\<bu betik>.ps1 oldugu icin
    # iki seviye yukarisi vault'tur). Boylece motor baska bir makinede, baska
    # bir kullanici adiyla ve baska bir vault konumunda TEK SATIR DEGISMEDEN
    # calisir. Gomulu yol ayni zamanda depoya kisisel veri sizdiriyordu.
    [string]$Vault = $(if ($env:BEYIN_VAULT) { $env:BEYIN_VAULT } else { Split-Path (Split-Path $PSScriptRoot -Parent) -Parent }),
    [switch]$Uygula
)

$ErrorActionPreference = 'SilentlyContinue'
# VAULT KAPISI (2026-09-17 bagimsiz denetimi - A1). $Vault bu betikte ILK
# bildirilen parametredir, yani 0. KONUM ona aittir: 'beyin <komut> ZZZ' gibi
# ciplak birakilan bir konumsal deger buraya baglaniyordu. lib.ps1 o yoldan
# yuklenemiyor, $ErrorActionPreference = 'SilentlyContinue' hatayi yutuyor ve
# betik HICBIR SEY YAPMADAN 'basariyla' cikiyordu (olculdu). Ayni kapi
# niyet/al/ayar/guncelle dahil 14 komutta zaten vardi; burada eksikti.
$vaultOk = $false
try { $vaultOk = [bool]($Vault -and (Test-Path -LiteralPath $Vault -PathType Container) -and (Test-Path -LiteralPath (Join-Path $Vault 'motor\hooks\lib.ps1') -PathType Leaf)) } catch { }
if (-not $vaultOk) { Write-Output "HATA: vault degil (motor\hooks\lib.ps1 yok): '$Vault'  - konumsal arguman -Vault'a baglanir; uygulamak icin -Uygula kullan"; exit 2 }
. (Join-Path $Vault 'motor\hooks\lib.ps1')
$p = Get-BeyinPaths -Vault $Vault
$sw = [Diagnostics.Stopwatch]::StartNew()

# Sira onemli: once Windows ters egik, sonra Windows ileri egik, sonra POSIX.
$kurallar = @(
    @{ Ad = 'win-ters';  P = '[A-Za-z]:\\Users\\[^\\/\s"'']+\\'; R = '~\' }
    @{ Ad = 'win-ileri'; P = '[A-Za-z]:/Users/[^\\/\s"'']+/';     R = '~/' }
    @{ Ad = 'posix';     P = '/home/[^\\/\s"'']+/';               R = '~/' }
)

$hedefler = @()
$hedefler += @(Get-ChildItem -LiteralPath $p.Daylogs -Filter '*.md' -File -ErrorAction SilentlyContinue)
$hedefler += @(Get-ChildItem -LiteralPath $p.Compiled -Recurse -Filter '*.md' -File -ErrorAction SilentlyContinue)
$arsiv = Join-Path $Vault '90-archive'
if (Test-Path -LiteralPath $arsiv) {
    $hedefler += @(Get-ChildItem -LiteralPath $arsiv -Recurse -Filter '*.md' -File -ErrorAction SilentlyContinue)
}

"Vault  : $Vault"
"Mod    : $(if ($Uygula) { 'UYGULA (yazacak)' } else { 'kuru calisma (yazmaz)' })"
"Hedef  : $($hedefler.Count) makine-bolgesi dosyasi (85-daylogs + 86-compiled + 90-archive)"
''

# "TARANMADI" ILE "TEMIZ" AYNI CEVAP DEGILDIR (2026-09-18 denetimi).
# Eskiden okunamayan dosya sessizce atlaniyordu ve kalanlar temizse rapor
# "Mutlak yol bulunamadi - temiz." diyip makbuza YOL_ISYOK yaziyordu -
# okunmamis dosyalari taranmis sayarak. Kisisel mutlak yollar git'e izlenen
# notlarda kalirken hem insana hem makbuza "temiz" deniyordu.
$okunamayan = New-Object System.Collections.Generic.List[string]
$bulunan = New-Object System.Collections.Generic.List[object]
foreach ($f in $hedefler) {
    $c = $null
    try { $c = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8 -ErrorAction Stop } catch { $c = $null }
    if ($null -eq $c) { $okunamayan.Add($f.Name); continue }
    if ($c.Length -eq 0) { continue }
    $toplam = 0
    foreach ($k in $kurallar) {
        $toplam += ([regex]::Matches($c, $k.P, $script:BeyinRxCI)).Count
    }
    if ($toplam -gt 0) {
        $bulunan.Add([pscustomobject]@{ Dosya = $f.Name; Yol = $f.FullName; Sayi = $toplam })
    }
}

if ($okunamayan.Count -gt 0) {
    "UYARI: $($okunamayan.Count) dosya OKUNAMADI, taranamadi: $(($okunamayan | Select-Object -First 5) -join ', ')$(if ($okunamayan.Count -gt 5) { ' ...' })"
}

if ($bulunan.Count -eq 0) {
    if ($okunamayan.Count -gt 0) {
        "Okunabilen dosyalarda mutlak yol yok - ama $($okunamayan.Count) dosya taranamadi, sonuc EKSIK."
        Write-BeyinLog -Vault $Vault -Message "yol-temizle: $($okunamayan.Count) dosya okunamadi - tarama eksik"
        Write-BeyinMakbuz -Paths $p -Script 'yol-temizle' -Outcome 'YOL_KISMI' `
            -DurationMs $sw.ElapsedMilliseconds -Note "$($hedefler.Count) hedeften $($okunamayan.Count) tanesi okunamadi; okunanlarda mutlak yol yok"
        exit 0
    }
    'Mutlak yol bulunamadi - temiz.'
    Write-BeyinMakbuz -Paths $p -Script 'yol-temizle' -Outcome 'YOL_ISYOK' `
        -DurationMs $sw.ElapsedMilliseconds -Note "$($hedefler.Count) hedef tarandi, mutlak yol yok"
    exit 0
}

$bulunan.ToArray() | Sort-Object Sayi -Descending |
    Format-Table -AutoSize Dosya, @{ N = 'Eslesme'; E = { $_.Sayi } } | Out-String -Width 120

if (-not $Uygula) {
    'KURU CALISMA. Uygulamak icin:  -Uygula'
    $kuruEslesme = (($bulunan.ToArray() | Measure-Object -Property Sayi -Sum).Sum)
    "Toplam $kuruEslesme eslesme, $($bulunan.Count) dosya."
    # Kuru kosuda da makbuz: a = b (hicbir bayt degismedi), outcome ayri.
    $kuruFiles = New-Object System.Collections.Generic.List[object]
    foreach ($b in $bulunan.ToArray()) {
        $bb = Measure-BeyinDosya -Path $b.Yol
        $kuruFiles.Add(@{ p = (ConvertTo-BeyinMakbuzYol -Paths $p -Path $b.Yol); b = $bb; a = $bb })
    }
    Write-BeyinMakbuz -Paths $p -Script 'yol-temizle' -Outcome 'YOL_KURU' `
        -Files @($kuruFiles.ToArray()) -DurationMs $sw.ElapsedMilliseconds `
        -Note "KURU: $($bulunan.Count) dosyada $kuruEslesme mutlak yol (yazilmadi)"
    exit 0
}

$degisen = 0; $eslesme = 0; $atlanan = 0
$mkFiles = New-Object System.Collections.Generic.List[object]
foreach ($b in $bulunan.ToArray()) {
    $c = $null
    try { $c = Get-Content -LiteralPath $b.Yol -Raw -Encoding UTF8 -ErrorAction Stop } catch { $c = $null }
    if ($null -eq $c) {
        "ATLANDI (okunamadi): $($b.Dosya)"
        $atlanan++
        continue
    }
    $yeni = $c
    foreach ($k in $kurallar) {
        $yeni = [regex]::Replace($yeni, $k.P, $k.R, $script:BeyinRxCI)
    }
    if ($yeni -ne $c) {
        # Guvenlik: icerik kisalmasi beklenen mertebede mi (yalniz yol kisaltma)
        if ($yeni.Length -lt ($c.Length - ($b.Sayi * 200))) {
            "ATLANDI (supheli kisalma): $($b.Dosya)"
            $atlanan++
            continue
        }
        $mkOnce = Measure-BeyinDosya -Path $b.Yol
        Write-BeyinText -Path $b.Yol -Text $yeni
        $degisen++; $eslesme += $b.Sayi
        $mkFiles.Add(@{ p = (ConvertTo-BeyinMakbuzYol -Paths $p -Path $b.Yol); b = $mkOnce; a = (Measure-BeyinDosya -Path $b.Yol) })
    }
}
''
"Sonuc: $degisen dosyada $eslesme mutlak yol kisaltildi.$(if ($atlanan) { " $atlanan dosya supheli kisalma yuzunden ATLANDI." })"
Write-BeyinLog -Vault $Vault -Message "yol-temizle: $degisen dosyada $eslesme mutlak yol kisaltildi, $atlanan atlandi"
Write-BeyinMakbuz -Paths $p -Script 'yol-temizle' `
    -Outcome $(if ($atlanan -gt 0 -or $okunamayan.Count -gt 0) { 'YOL_KISMI' } elseif ($degisen -gt 0) { 'YOL_OK' } else { 'YOL_ISYOK' }) `
    -Files @($mkFiles.ToArray()) -DurationMs $sw.ElapsedMilliseconds `
    -Note "$degisen dosyada $eslesme mutlak yol kisaltildi, $atlanan atlandi"
"Kontrol: git -C `"$Vault`" diff --stat -- 85-daylogs 86-compiled 90-archive"
