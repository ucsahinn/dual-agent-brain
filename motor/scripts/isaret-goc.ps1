# isaret-goc.ps1 - v1 satir isaretlerini v2'ye (lastSize'li) tasir. BIR KERELIK.
#
# NEDEN (2026-09-10 denetimi, KRITIK bulgu):
# Eski Set-BeyinWatermark yalniz 'lines' yaziyordu ve Test-BeyinShouldRetry
# "Lines>0 ise islenmis" diyordu. Sonuc: bir oturum PreCompact ile bir kez
# ozetlendikten sonra devam edip DUZGUN KAPANMAZSA (pane oldurme, Ctrl+C,
# Codex penceresini kapatma - ucunde de SessionEnd atesmez) isaretin
# OTESINDEKI her satir sonsuza dek atlaniyordu. Ne yetim tarayici ne
# gecmis-toparla dokunuyordu, cunku ikisi de ayni fonksiyonu cagiriyor.
#
# Motor artik lastSize yaziyor ve dosya buyuduyse geri geliyor. Ama ESKI
# isaretlerde lastSize yok; bu betik onlari tamamlar:
#   lastSize <- isaretteki satirin GERCEK bayt karsiligi
#               (Get-BeyinByteOffsetOfLine, dosyayi akitarak sayar)
# Boylece o satirdan sonra yazilmis her bayt "islenmemis" olarak gorunur.
#
# Varsayilan KURU CALISMA. Uygulamak icin -Uygula.
# Not: isaret dosyalari .state altinda ve .gitignore'da; geri alinabilirlik
# icin -Uygula once .state\watermarks-yedek-<damga> kopyasi alir.
#
# YEDEK YALNIZ IS VARKEN (2026-09-17, bagimsiz denetim - F4).
# Onceki surum -Uygula'da KOSULSUZ tam kopya aliyordu. Olculdu: iki ardisik
# -Uygula kosusunda ikincisi 0 isaret gocurdugu halde yine tum dizini kopyaladi.
# Gercek vault'ta yuzlerce isaret var; her bos kosu hepsini bir kez daha yaziyor
# ve bu kopyalari temizleyen HICBIR yol yok (copcu'nun '*.yedek-*' kurali DOSYA
# adina bakar, bu DIZIN adlari eslesmez). Artik: is yoksa yedek alinmaz, alinan
# yedeklerin yalniz en yeni $script:IsaretYedekTut tanesi tutulur, eskiler budanir.
# Ayrica .state\watermarks hic yoksa gocurulecek is de yoktur: 'yedek alinamadi'
# deyip exit 1 vermek yerine TEMIZ cikilir.
#
# MAKBUZ (2026-09-17, denetim - F5): bu betik MOTOR DURUMUNU degistiriyor; artik
# diger yazicilarla ayni sozlesmeyle makbuz birakir (kuru kosuda da, ayri outcome).

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
$IsaretYedekTut = 5   # en yeni kac yedek dizini tutulur

"Vault : $Vault"
"Mod   : $(if ($Uygula) { 'UYGULA (yazacak)' } else { 'kuru calisma (yazmaz)' })"
''

# KENAR DURUM (F4): isaret dizini hic yoksa gocurulecek is de yoktur.
# Eski kod buraya kadar gelip Copy-Item'da patliyor, 'UYARI: yedek alinamadi ...
# duruldu' yazip exit 1 veriyordu - hicbir sey yapilmayacak bir kosu icin HATA.
if (-not (Test-Path -LiteralPath $p.Marks -PathType Container)) {
    'Isaret dizini yok (.state\watermarks) - gocurulecek is yok.'
    Write-BeyinMakbuz -Paths $p -Script 'isaret-goc' -Outcome 'ISARET_ISYOK' `
        -DurationMs $sw.ElapsedMilliseconds -Note 'isaret dizini yok'
    exit 0
}

$isaretler = @(Get-ChildItem -LiteralPath $p.Marks -Filter '*.json' -File -ErrorAction SilentlyContinue)
"Toplam isaret : $($isaretler.Count)"

$aday = New-Object System.Collections.Generic.List[object]
$atla = @{}
function Say([string]$k) { if (-not $atla.ContainsKey($k)) { $atla[$k] = 0 }; $atla[$k]++ }

foreach ($mf in $isaretler) {
    $mo = $null
    try { $mo = Get-Content -LiteralPath $mf.FullName -Raw -Encoding UTF8 | ConvertFrom-Json } catch { Say 'bozuk-isaret'; continue }
    if (-not $mo) { Say 'bozuk-isaret'; continue }

    $lines = if ($mo.PSObject.Properties['lines'])    { [int]$mo.lines }     else { 0 }
    $ls    = if ($mo.PSObject.Properties['lastSize']) { [int64]$mo.lastSize } else { 0 }
    $tp    = if ($mo.PSObject.Properties['path'])     { [string]$mo.path }   else { '' }

    if ($lines -le 0)  { Say 'satir-isareti-degil'; continue }   # bayt isareti / karantina
    if ($ls -gt 0)     { Say 'zaten-v2'; continue }
    if (-not $tp)      { Say 'yol-yok'; continue }
    if (-not (Test-Path -LiteralPath $tp)) { Say 'transkript-silinmis'; continue }

    $boyut = (Get-Item -LiteralPath $tp).Length
    # Tavan ustu dosyalar bayt yolundan gidiyor; onlarin kurali zaten ayri.
    if ($boyut -gt ($script:BeyinMaxTranscriptMB * 1MB)) { Say 'tavan-ustu'; continue }

    $ofs = [int64](Get-BeyinByteOffsetOfLine -Path $tp -Lines $lines)
    if ($ofs -le 0) { Say 'offset-hesaplanamadi'; continue }

    $aday.Add([pscustomobject]@{
        Isaret = $mf.FullName
        Yol    = $tp
        Ad     = (Split-Path -Leaf $tp)
        Satir  = $lines
        Offset = $ofs
        Boyut  = $boyut
        Kalan  = ($boyut - $ofs)
    })
}

$adayArr = @($aday.ToArray() | Sort-Object Kalan -Descending)
$kalanli = @($adayArr | Where-Object { $_.Kalan -gt 0 })

"Gocurulecek   : $($adayArr.Count)  (v1 satir isareti, transkripti diskte)"
"Bunlardan icerigi kalmis : $($kalanli.Count) dosya, $([math]::Round((($kalanli | Measure-Object -Property Kalan -Sum).Sum) / 1MB, 1)) MB islenmemis"
if ($atla.Count -gt 0) {
    "Atlananlar    : " + (($atla.GetEnumerator() | Sort-Object Name | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ', ')
}
''

if ($kalanli.Count -gt 0) {
    'En cok icerik kalan 15 dosya:'
    $kalanli | Select-Object -First 15 |
        Format-Table -AutoSize @{N='Dosya';E={ $_.Ad.Substring(0, [Math]::Min(34, $_.Ad.Length)) }},
                               @{N='Satir';E={ $_.Satir }},
                               @{N='IslenenBayt';E={ $_.Offset }},
                               @{N='Boyut';E={ $_.Boyut }},
                               @{N='KalanKB';E={ [math]::Round($_.Kalan / 1KB) }} | Out-String -Width 200
}

$mkNot = "$($isaretler.Count) isaret, $($adayArr.Count) gocurulecek, $($kalanli.Count) dosyada icerik kalmis"

if (-not $Uygula) {
    ''
    'KURU CALISMA. Uygulamak icin:  -Uygula'
    'Uygulandiktan sonra bu dosyalar yetim tarayici ve gecmis-toparla icin yeniden gorunur olur.'
    '(Yetim tarayici yalniz son 72 saate bakar; daha eskisi icin: gecmis-toparla.ps1 -Gun <N> -Uygula)'
    Write-BeyinMakbuz -Paths $p -Script 'isaret-goc' -Outcome 'ISARET_KURU' `
        -DurationMs $sw.ElapsedMilliseconds -Note "KURU: $mkNot"
    exit 0
}

# IS YOKSA YEDEK DE YOK (F4). Yedek bir GERI ALMA araci; hicbir sey
# yazilmayacaksa geri alinacak bir sey de yoktur.
if ($adayArr.Count -eq 0) {
    ''
    'Gocurulecek isaret yok - yedek ALINMADI, hicbir sey yazilmadi.'
    Write-BeyinMakbuz -Paths $p -Script 'isaret-goc' -Outcome 'ISARET_ISYOK' `
        -DurationMs $sw.ElapsedMilliseconds -Note $mkNot
    exit 0
}

# Yedek: isaret dizininin tamami (kucuk, JSON). Ayni saniyede iki kosu olursa
# Copy-Item var olan dizinin ICINE kopyalar (ic ice yedek); damga cakisirsa
# sayac eklenir.
$yedekTaban = Join-Path $p.ScrState ("watermarks-yedek-" + ((Get-Date).ToString('yyyyMMdd-HHmmss', [Globalization.CultureInfo]::InvariantCulture)))
$yedek = $yedekTaban
$sayac = 1
while (Test-Path -LiteralPath $yedek) { $yedek = "$yedekTaban-$sayac"; $sayac++ }
try {
    Copy-Item -LiteralPath $p.Marks -Destination $yedek -Recurse -Force -ErrorAction Stop
    "Yedek alindi : $yedek"
} catch {
    "UYARI: yedek alinamadi ($($_.Exception.Message)) - yine de devam ediliyor mu? HAYIR, duruldu."
    Write-BeyinMakbuz -Paths $p -Script 'isaret-goc' -Outcome 'ISARET_HATA_YEDEK' `
        -DurationMs $sw.ElapsedMilliseconds -Note "yedek alinamadi: $($_.Exception.Message)"
    exit 1
}

# ESKI YEDEKLERI BUDA: en yeni $IsaretYedekTut tanesi kalir. Bunlari baska
# hicbir yol temizlemiyor (copcu'nun '*.yedek-*' kurali DOSYA adina bakar).
$budanan = 0
try {
    $tumYedek = @(Get-ChildItem -LiteralPath $p.ScrState -Directory -Filter 'watermarks-yedek-*' -ErrorAction SilentlyContinue |
                  Sort-Object Name -Descending)
    if ($tumYedek.Count -gt $IsaretYedekTut) {
        foreach ($y in @($tumYedek | Select-Object -Skip $IsaretYedekTut)) {
            try { Remove-Item -LiteralPath $y.FullName -Recurse -Force -ErrorAction Stop; $budanan++ } catch { }
        }
    }
} catch { }
if ($budanan -gt 0) { "Eski yedek budandi : $budanan dizin (en yeni $IsaretYedekTut tutuldu)" }

$yazildi = 0; $hata = 0
$mkIsaret = New-Object System.Collections.Generic.List[object]
foreach ($a in $adayArr) {
    $mkOnce = Measure-BeyinDosya -Path $a.Isaret
    try {
        $mo = Get-Content -LiteralPath $a.Isaret -Raw -Encoding UTF8 | ConvertFrom-Json
        $json = @{
            v = 2; lines = [int]$mo.lines; path = $a.Yol; lastSize = $a.Offset
            byteOffset = $(if ($mo.PSObject.Properties['byteOffset']) { [int64]$mo.byteOffset } else { [int64]0 })
            ts = $(if ($mo.PSObject.Properties['ts']) { [string]$mo.ts } else { (Get-Date -Format 'o') })
            gocuruldu = (Get-Date -Format 'o')
        } | ConvertTo-Json -Compress
        Write-BeyinText -Path $a.Isaret -Text $json
        $yazildi++
        $mkIsaret.Add(@{ p = (ConvertTo-BeyinMakbuzYol -Paths $p -Path $a.Isaret); b = $mkOnce; a = (Measure-BeyinDosya -Path $a.Isaret) })
    } catch { $hata++ }
}

''
"Sonuc: $yazildi isaret v2'ye gocuruldu, $hata hata"
Write-BeyinLog -Vault $Vault -Message "isaret-goc: $yazildi isaret v2'ye gocuruldu ($($kalanli.Count) dosyada islenmemis icerik var), $hata hata"
Write-BeyinMakbuz -Paths $p -Script 'isaret-goc' `
    -Outcome $(if ($hata -gt 0) { 'ISARET_KISMI' } elseif ($yazildi -gt 0) { 'ISARET_OK' } else { 'ISARET_ISYOK' }) `
    -Files @($mkIsaret.ToArray()) -DurationMs $sw.ElapsedMilliseconds `
    -Note "$yazildi gocuruldu, $hata hata, $budanan eski yedek budandi ($mkNot)"
"Kontrol: motor\scripts\gecmis-toparla.ps1 -Gun 30   (kuru calisma; kac oturum geri geldi)"
