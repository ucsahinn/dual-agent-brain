# yedek.ps1 - Tam vault yedegi. Bagimliligi YOK.
#
# NEDEN VAR (2026-09-18 denetimi): 'beyin yedek' brain-cli.mjs'e bagliydi ve o
# arac bu depoda GELMIYOR. Yani komut yardimda tanitiliyor, Pazar gece gorevi
# olarak kaydediliyor ve doktorun 'yedek tazeligi' satiri onu oneriyordu - ama
# motoru yeni kuran biri icin hicbiri CALISMIYORDU. Motorun kendi notlarini
# koruma vaadi, depoda olmayan bir araca dayanamaz.
#
# brain-cli varsa dagitici ONU tercih eder (mevcut davranis korunur); bu betik
# onsuz calisan yoldur.
#
# YEDEK SOZLESMESI (guncelle.ps1'in ayni kalibi - YARIM YEDEK FELAKETI):
# guncelle.ps1 -GeriAl bir zamanlar yarim bir yedekle motoru 69 dosyadan 1'e
# dusurup cikis kodu 0 ile "BASARILI" demisti. Dersi: bir yedek, TAMAMLANMA
# ISARETI tasimadan yedek sayilmaz. Burada da ayni: kopyalama bittikten SONRA
# TAMAM.txt yazilir (dosya sayisi + bayt). Isaretsiz bir klasor yarim kalmis
# demektir ve 'yedek tazeligi' onu saymaz.

param(
    # TASINABILIRLIK: vault yolu gomulu DEGIL. Oncelik: -Vault > BEYIN_VAULT >
    # betigin konumundan turetme (<vault>\motor\scripts\<bu betik>.ps1).
    [string]$Vault = $(if ($env:BEYIN_VAULT) { $env:BEYIN_VAULT } else { Split-Path (Split-Path $PSScriptRoot -Parent) -Parent }),
    # Kac yedek tutulur. 0 = budama yok.
    [int]$Tut = 5,
    [switch]$KuruCalisma,
    [switch]$Json
)

$ErrorActionPreference = 'SilentlyContinue'
# VAULT KAPISI: konumsal bir arguman sessizce -Vault'a baglanip betigi YANLIS
# klasorde "basariyla" calistirabiliyordu (2026-09-17 denetimi).
$vaultOk = $false
try { $vaultOk = [bool]($Vault -and (Test-Path -LiteralPath $Vault -PathType Container) -and (Test-Path -LiteralPath (Join-Path $Vault 'motor\hooks\lib.ps1') -PathType Leaf)) } catch { }
if (-not $vaultOk) { Write-Output "HATA: vault degil (motor\hooks\lib.ps1 yok): '$Vault'"; exit 2 }
. (Join-Path $Vault 'motor\hooks\lib.ps1')
$p = Get-BeyinPaths -Vault $Vault
$sw = [Diagnostics.Stopwatch]::StartNew()
$inv = [Globalization.CultureInfo]::InvariantCulture

$YEDEK_KOK   = Join-Path $Vault '.brain\backups'
$ISARET      = 'TAMAM.txt'

# HARIC TUTULANLAR - her biri bir SEBEPLE:
#   .git        surum gecmisi; yedegin icinde ikinci bir depo olmasin
#   .obsidian   arayuz durumu; not degil, her makinede farkli
#   .brain      YEDEKLERIN KENDISI - ozyineleme (yedek icinde yedek)
#   .state      motor calisma durumu; yeniden uretilir, kopyalanirsa
#               geri yuklemede BAYAT kuyruk/sayac dirilir
$HARIC_KOK = @('.git', '.obsidian', '.brain')
$HARIC_AD  = @('.state')

function Test-Haric([string]$Rel) {
    $parcalar = $Rel -split '[\\/]'
    if ($parcalar.Count -gt 0 -and ($HARIC_KOK -contains $parcalar[0])) { return $true }
    foreach ($x in $parcalar) { if ($HARIC_AD -contains $x) { return $true } }
    return $false
}

# --- Kaynak dosyalari topla -------------------------------------------------
$kaynak = New-Object System.Collections.Generic.List[object]
$okunamayan = New-Object System.Collections.Generic.List[string]
$toplamBayt = [long]0
foreach ($f in @(Get-ChildItem -LiteralPath $Vault -File -Recurse -Force -ErrorAction SilentlyContinue)) {
    $rel = $f.FullName.Substring($Vault.Length).TrimStart('\', '/')
    if (Test-Haric $rel) { continue }
    $kaynak.Add([pscustomobject]@{ Tam = $f.FullName; Rel = $rel; Bayt = [long]$f.Length })
    $toplamBayt += [long]$f.Length
}

if ($kaynak.Count -eq 0) {
    Write-Output 'HATA: yedeklenecek dosya bulunamadi - vault bos gorunuyor, hicbir sey yazilmadi.'
    Write-BeyinMakbuz -Paths $p -Script 'yedek' -Outcome 'YEDEK_KAYNAK_YOK' -DurationMs $sw.ElapsedMilliseconds
    exit 3
}

$damga = (Get-Date).ToString('yyyy-MM-ddTHH-mm-ss', $inv)
$hedef = Join-Path $YEDEK_KOK ("beyin-" + $damga)
$mb = [math]::Round($toplamBayt / 1MB, 1)

Write-Output ("YEDEK  {0}  |  {1} dosya  |  {2} MB{3}" -f (Get-Date).ToString('yyyy-MM-dd HH:mm', $inv), $kaynak.Count, $mb, $(if ($KuruCalisma) { '  |  KURU CALISMA' }))
Write-Output "  kaynak : $Vault"
Write-Output "  hedef  : $hedef"
Write-Output "  haric  : $($HARIC_KOK -join ', '), */$($HARIC_AD -join ', */')"

if ($KuruCalisma) {
    Write-Output ''
    Write-Output 'KURU CALISMA bitti - hicbir sey yazilmadi. Gercekten almak icin -KuruCalisma olmadan calistir.'
    Write-BeyinMakbuz -Paths $p -Script 'yedek' -Outcome 'YEDEK_KURU' -DurationMs $sw.ElapsedMilliseconds `
        -Note "$($kaynak.Count) dosya, $mb MB"
    exit 0
}

# --- DISK YERI KONTROLU: yarim yedek yerine HIC yedek ------------------------
# Yer yetmezse kopyalama ortasinda duser ve geride TAMAM.txt'siz bir enkaz
# kalir. Once bak, sonra basla.
try {
    $kok = [IO.Path]::GetPathRoot($Vault)
    $dsk = Get-PSDrive -Name ($kok.TrimEnd('\', ':')) -ErrorAction Stop
    if ($null -ne $dsk.Free -and $dsk.Free -lt ($toplamBayt * 1.1)) {
        Write-Output ("HATA: disk yeri yetersiz - gereken ~{0} MB, bos {1} MB. Hicbir sey yazilmadi." -f [math]::Round($toplamBayt * 1.1 / 1MB, 0), [math]::Round($dsk.Free / 1MB, 0))
        Write-BeyinMakbuz -Paths $p -Script 'yedek' -Outcome 'YEDEK_DISK_YETERSIZ' -DurationMs $sw.ElapsedMilliseconds
        exit 3
    }
} catch { }

New-Item -ItemType Directory -Force -Path $hedef | Out-Null

$yazilan = 0
$yazilanBayt = [long]0
foreach ($k in $kaynak) {
    $hf = Join-Path $hedef $k.Rel
    $hd = Split-Path $hf -Parent
    try {
        if ($hd -and -not (Test-Path -LiteralPath $hd)) { New-Item -ItemType Directory -Force -Path $hd | Out-Null }
        Copy-Item -LiteralPath $k.Tam -Destination $hf -Force -ErrorAction Stop
        $yazilan++
        $yazilanBayt += $k.Bayt
    } catch {
        $okunamayan.Add("$($k.Rel) - $($_.Exception.Message)")
    }
}

# --- TAMAMLANMA ISARETI ------------------------------------------------------
# EKSIK DOSYA VARSA ISARET YAZILMAZ. Isaretsiz klasor 'yarim' demektir;
# doktor onu yedek saymaz ve bir sonraki kosu ustune yazmaz, yaninda yenisini
# acar. Yarim bir yedegi TAM sanmak, yedegin hic olmamasindan kotudur.
$tam = ($okunamayan.Count -eq 0)
if ($tam) {
    $satirlar = New-Object System.Collections.Generic.List[string]
    $satirlar.Add("beyin-yedek")
    $satirlar.Add("ts=$((Get-Date).ToString('o', $inv))")
    $satirlar.Add("vault=$Vault")
    $satirlar.Add("surum=$(Get-BeyinVersion -Vault $Vault)")
    $satirlar.Add("dosya=$yazilan")
    $satirlar.Add("bayt=$yazilanBayt")
    Write-BeyinText -Path (Join-Path $hedef $ISARET) -Text (($satirlar -join "`r`n") + "`r`n")
} else {
    Write-Output ''
    Write-Output "UYARI: $($okunamayan.Count) dosya kopyalanamadi - yedek YARIM."
    foreach ($x in @($okunamayan | Select-Object -First 5)) { Write-Output "    $x" }
    if ($okunamayan.Count -gt 5) { Write-Output "    ... ve $($okunamayan.Count - 5) dosya daha" }
    Write-Output "  TAMAM.txt YAZILMADI: bu klasor yedek sayilmaz, elle bak: $hedef"
}

# --- BUDAMA: en yeni $Tut TAM yedek tutulur ----------------------------------
# DIKKAT (guncelle.ps1'de olculdu): bir fonksiyon `,@(...)` ile donerse boru
# hattina TEK oge verir ve 'Select-Object -Skip N' hicbir sey uretmez - orada
# "en yeni 3 yedek tutulur" vaadi bu yuzden OLU KODDU. Once DEGISKENE al.
$budanan = 0
if ($Tut -gt 0 -and $tam) {
    $hepsi = @(Get-ChildItem -LiteralPath $YEDEK_KOK -Directory -ErrorAction SilentlyContinue |
               Where-Object { $_.Name -like 'beyin-*' -and (Test-Path -LiteralPath (Join-Path $_.FullName $ISARET)) } |
               Sort-Object Name -Descending)
    foreach ($eski in @($hepsi | Select-Object -Skip $Tut)) {
        # Yalniz KENDI urettiklerimiz ve yalniz yedek kokunun ALTINDA.
        if ($eski.FullName -notlike (Join-Path $YEDEK_KOK '*')) { continue }
        Remove-Item -LiteralPath $eski.FullName -Recurse -Force -ErrorAction SilentlyContinue
        if (-not (Test-Path -LiteralPath $eski.FullName)) { $budanan++ }
    }
}

$sure = [math]::Round($sw.Elapsed.TotalSeconds, 1)
Write-Output ''
Write-Output ("Sonuc: {0} dosya, {1} MB, {2} sn{3}{4}" -f $yazilan, [math]::Round($yazilanBayt / 1MB, 1), $sure,
    $(if ($budanan) { ", $budanan eski yedek budandi" }), $(if (-not $tam) { '  << YARIM' }))
if ($tam) { Write-Output "  isaret : $(Join-Path $hedef $ISARET)" }

Write-BeyinLog -Vault $Vault -Message "yedek: $yazilan dosya, $([math]::Round($yazilanBayt / 1MB, 1)) MB -> $hedef$(if (-not $tam) { ' (YARIM)' })"
Write-BeyinMakbuz -Paths $p -Script 'yedek' `
    -Outcome $(if ($tam) { 'YEDEK_OK' } else { 'YEDEK_YARIM' }) `
    -DurationMs $sw.ElapsedMilliseconds `
    -Note "$yazilan dosya, $([math]::Round($yazilanBayt / 1MB, 1)) MB, $budanan budandi$(if (-not $tam) { ", $($okunamayan.Count) kopyalanamadi" })"

if ($Json) {
    [ordered]@{
        ts = (Get-Date).ToString('o', $inv); hedef = $hedef; dosya = $yazilan
        bayt = $yazilanBayt; tam = $tam; budanan = $budanan
        okunamayan = @($okunamayan.ToArray())
    } | ConvertTo-Json -Depth 4
}

exit $(if ($tam) { 0 } else { 3 })
