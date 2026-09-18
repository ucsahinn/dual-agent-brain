# makbuz.ps1 - Motor koşularının makbuzlarını listeler.
#
# NEDEN: motor her koşuda ne yazdığını, kaç bayt önce/sonra, kaç bütçe yaktığını,
# hangi kavramları enjekte ettiğini kaydeder (Write-BeyinMakbuz). Bu betik o
# kaydı okunur bir tabloya çevirir. Bahçıvan, canlı görünüm ve doktor da aynı
# okuyucuyu (Read-BeyinMakbuz) kullanır; burada yalnız sunum var.
#
# Kullanım:
#   beyin makbuz            son 1 gün
#   beyin makbuz 7          son 7 gün
#   beyin makbuz 7 -Betik flush
#   beyin makbuz 7 -Json

param(
    [string]$Vault = $(if ($env:BEYIN_VAULT) { $env:BEYIN_VAULT } else { Split-Path (Split-Path $PSScriptRoot -Parent) -Parent }),
    [int]$Gun = 1,
    [string]$Betik = '',
    # SATIR TAVANI (2026-09-17): "beyin makbuz 2" 824 satir basiyordu (2 gunde 378
    # kosu) - terminalde okunamaz. Tablo yalniz en yeni $EnFazla kosuyu gosterir;
    # BETIK BAZINDA ozeti ve sifir-bayt uyarisi HER ZAMAN tam kumeden hesaplanir.
    # 0 = sinirsiz.
    [int]$EnFazla = 40,
    [switch]$Json
)

$ErrorActionPreference = 'SilentlyContinue'
# NEDEN: $Vault ilk KONUMSAL parametre; `makbuz.ps1 -Gun 2 flush` 'flush'u Vault'a bagliyor, lib.ps1
# sessizce yuklenemiyor ve 'Son 2 gunde makbuz yok' diye YANLIS rapor cikiyordu (olculdu: 282 makbuz
# varken, exit 0). Vault gercek vault degilse (motor\hooks\lib.ps1 yok) SESLI dus.
$vaultOk = $false
try { $vaultOk = [bool]($Vault -and (Test-Path -LiteralPath $Vault -PathType Container) -and (Test-Path -LiteralPath (Join-Path $Vault 'motor\hooks\lib.ps1') -PathType Leaf)) } catch { }
if (-not $vaultOk) { Write-Output "HATA: vault degil (motor\hooks\lib.ps1 yok): '$Vault'  - konumsal arguman -Vault'a baglanir; betik suzmek icin -Betik <ad> kullan"; exit 2 }
. (Join-Path $Vault 'motor\hooks\lib.ps1')
$p = Get-BeyinPaths -Vault $Vault
$inv = [Globalization.CultureInfo]::InvariantCulture

$satirlar = @(Read-BeyinMakbuz -Paths $p -Gun $Gun)
if ($Betik) { $satirlar = @($satirlar | Where-Object { $_.script -eq $Betik }) }

if ($Json) { $satirlar | ConvertTo-Json -Depth 6; exit 0 }

if ($satirlar.Count -eq 0) {
    "Son $Gun gunde makbuz yok$(if ($Betik) { " (betik: $Betik)" })."
    "Makbuz dizini: $($p.Makbuz)"
    exit 0
}

"MAKBUZ  son $Gun gun  |  $($satirlar.Count) kosu$(if ($Betik) { "  |  betik: $Betik" })"
''
# NEDEN: Format-Table sutunlari HOST genisligine (120) gore sigdirir, Out-String -Width'e gore degil; 'not'
# sutunu (FLUSH_HATA/KIMLIK/ISTISNA ayrintisinin TEK yeri) sessizce dusuyordu (olculdu: baslikta 'not' yok,
# -Json'da 59 not). Satirlar sabit genislikte elle basilir (104 sutun, 120'ye sigar); not, satirin ALTINDA
# kendi girintili satirinda ve kirpilmadan (makbuz zaten 300 karakterde keser).
function Kes([string]$S, [int]$N) { if (-not $S) { return '' }; if ($S.Length -gt $N) { return $S.Substring(0, $N - 1) + '~' }; return $S }
$FMT = '{0,-11} {1,-16} {2,-7} {3,-11} {4,-20} {5,6} {6,5} {7,5} {8,9} {9,6}'
$FMT -f 'zaman', 'betik', 'ajan', 'kaynak', 'sonuc', 'sn', 'butce', 'dosya', 'bayt+/-', 'kavram'
$FMT -f ('-' * 11), ('-' * 16), ('-' * 7), ('-' * 11), ('-' * 20), ('-' * 6), ('-' * 5), ('-' * 5), ('-' * 9), ('-' * 6)
$gosterilen = @($satirlar | Sort-Object ts -Descending)
$kirpilan = 0
if ($EnFazla -gt 0 -and $gosterilen.Count -gt $EnFazla) {
    $kirpilan = $gosterilen.Count - $EnFazla
    $gosterilen = @($gosterilen | Select-Object -First $EnFazla)
}
foreach ($m in $gosterilen) {
    $dosya = @($m.files).Count
    $degisim = 0
    foreach ($f in @($m.files)) { if ($f.b -ge 0 -and $f.a -ge 0) { $degisim += ($f.a - $f.b) } }
    $zaman = try { ([datetime]::Parse([string]$m.ts, $inv)).ToString('MM-dd HH:mm', $inv) } catch { [string]$m.ts }
    $sn = if ($m.ms) { [string]::Format($inv, '{0:0.0}', $m.ms / 1000.0) } else { '' }
    $FMT -f $zaman, (Kes ([string]$m.script) 16), (Kes ([string]$m.agent) 7), (Kes ([string]$m.src) 11), (Kes ([string]$m.outcome) 20), $sn, $m.budget, $dosya, $(if ($dosya) { $degisim } else { '' }), @($m.concepts).Count
    if ($m.note) { "            not: $([string]$m.note)" }
}
if ($kirpilan -gt 0) {
    ''
    "  ... ve $kirpilan kosu daha gosterilmedi (tavan $EnFazla). Hepsi icin: -EnFazla 0 ya da -Json."
    '  (Asagidaki BETIK BAZINDA ozeti ve uyarilar TUM kosulari sayar.)'
}
''

# Ozet
$grup = $satirlar | Group-Object script | Sort-Object Count -Descending
'BETIK BAZINDA'
foreach ($g in $grup) {
    $basari = @($g.Group | Where-Object { $_.outcome -match '(_OK$|^OK$|^ENJEKSIYON$)' }).Count
    $erteli = @($g.Group | Where-Object { $_.outcome -match 'KUYRUK|BUTCE|SLOT|MESGUL' }).Count
    $hata   = @($g.Group | Where-Object { $_.outcome -match 'HATA|ISTISNA|KIMLIK' }).Count
    "  {0,-16} {1,4} kosu  {2,4} basarili  {3,4} ertelendi  {4,4} hata  butce={5}" -f $g.Name, $g.Count, $basari, $erteli, $hata, (($g.Group | Measure-Object -Property budget -Sum).Sum)
}
$sifir = @($satirlar | Where-Object { @($_.files | Where-Object { $_.b -gt 0 -and $_.a -eq 0 }).Count -gt 0 })
if ($sifir.Count) {
    ''
    "DIKKAT: $($sifir.Count) kosuda bir dosya SIFIR BAYTA dustu:"
    foreach ($m in $sifir) { foreach ($f in @($m.files | Where-Object { $_.b -gt 0 -and $_.a -eq 0 })) { "  $($m.ts)  $($m.script)  $($f.p)  ($($f.b) -> 0)" } }
    '  Geri alma: git -C "<vault>" checkout -- <dosya>'
}
