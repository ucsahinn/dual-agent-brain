# niyet.ps1 - Ileriye donuk hedefi (niyeti) kaydeder, gosterir, temizler.
#
# NEDEN: motor ne YAPILDIGINI kaydediyordu, ne YAPILMAK ISTENDIGINI degil.
# Tek satirlik niyet: oturum acilisinda iki ajana da enjekte edilir (7 gun),
# ozetleyici oturum sonunda "niyete ulasildi mi" diye tek satir yazar.
#
# Kullanim:
#   beyin niyet                      kayitli niyeti goster
#   beyin niyet "bu hafta X'i bitir" kaydet (500 karakter, sir maskelenir)
#   beyin niyet "..." -Proje x       proje etiketiyle kaydet
#   beyin niyet -Temizle             sil
#
# Dosya: motor\scripts\.state\niyet.json  {v,text,project,ts,agent}
# Kuratorlu alana YAZMAZ; yalniz motor durumu.

# NEDEN: eskiden $Vault ilk KONUMSAL parametreydi; `niyet.ps1 -Proje x "bu hafta bitir"` metni Vault'a
# bagliyor, lib.ps1 sessizce yuklenemiyor (EAP SilentlyContinue), 'Kayitli niyet yok' basip exit 0 ile
# cikiyordu: niyet KAYDEDILMIYORDU (olculdu). Ara cozum olan "vault degilse metin say" sezgisi de yanlisti:
# acikca verilmis ama var olmayan bir -Vault degeri METIN diye kaydediliyor ve sonraki acilista iki ajana
# enjekte ediliyordu (olculdu: exit 0, niyet.json text = dizin yolu). Betik adli/konumsal ayrimini yapamaz;
# bu yuzden metin DOGRUDAN tek konumsal parametredir (Position=0), $Vault yalniz adli kalir
# (PositionalBinding=$false: ikinci bir konumsal deger sessizce hicbir yere baglanmaz, hata verir).
[CmdletBinding(PositionalBinding=$false)]
param(
    [string]$Vault = '',
    [Parameter(Position=0)][string]$Metin = '',
    [string]$Proje = '',
    [switch]$Temizle
)

$ErrorActionPreference = 'SilentlyContinue'
# NEDEN: [CmdletBinding]/[Parameter] altinda `powershell -File` (dagiticinin cagirma yolu) param
# varsayilanlarini degerlendirirken $PSScriptRoot BOS geliyor (olculdu: 'Split-Path ... empty string',
# exit 1); govdede dolu. Vault varsayilani bu yuzden param() icinde degil burada cozulur.
if (-not $Vault) { $Vault = $(if ($env:BEYIN_VAULT) { $env:BEYIN_VAULT } else { Split-Path (Split-Path $PSScriptRoot -Parent) -Parent }) }
function Vault-Mi([string]$Y) {
    try { return [bool]($Y -and (Test-Path -LiteralPath $Y -PathType Container) -and (Test-Path -LiteralPath (Join-Path $Y 'motor\hooks\lib.ps1') -PathType Leaf)) } catch { return $false }
}
if (-not (Vault-Mi $Vault)) {
    # Gecersiz -Vault asla metin sayilmaz: SESLI hata, hicbir sey yazilmaz.
    Write-Output "HATA: vault degil (motor\hooks\lib.ps1 yok): '$Vault'  - niyet metni konumsal ya da -Metin `"...`" ile verilir"
    exit 2
}
. (Join-Path $Vault 'motor\hooks\lib.ps1')
$p = Get-BeyinPaths -Vault $Vault
$dosya = Join-Path $p.ScrState 'niyet.json'

if ($Temizle) {
    if (Test-Path -LiteralPath $dosya) {
        Remove-Item -LiteralPath $dosya -Force
        Write-BeyinLog -Vault $Vault -Message 'niyet: temizlendi'
        Write-BeyinMakbuz -Paths $p -Script 'niyet' -Outcome 'NIYET_TEMIZLENDI'
        'Niyet temizlendi.'
    } else { 'Kayitli niyet zaten yok.' }
    exit 0
}

if (-not $Metin) {
    $ny = Get-BeyinNiyet -Paths $p -MaxGun 36500
    if (-not $ny) { 'Kayitli niyet yok.  Kaydetmek icin:  beyin niyet "hedef cumlesi"'; exit 0 }
    $gun = [int][math]::Floor($ny.AgeDays)
    "NIYET  ($gun gun once, $($ny.Ts.ToString('yyyy-MM-dd HH:mm', [Globalization.CultureInfo]::InvariantCulture)), ajan: $($ny.Agent)$(if ($ny.Project) { ", proje: $($ny.Project)" }))"
    "  $($ny.Text)"
    if ($ny.AgeDays -gt 7) { ''; 'BAYAT: 7 gunden eski, oturum acilisinda ENJEKTE EDILMIYOR. Yenile ya da -Temizle.' }
    exit 0
}

# --- Kaydet ---
$metin = [string]$Metin
$metin = ($metin -replace '\s+', ' ').Trim()
if ($metin.Length -gt 500) { $metin = $metin.Substring(0, 500) }
$prot = Protect-BeyinSecrets -Text $metin -Vault $Vault
# FAIL-CLOSED, SOZLESME TUTARLILIGI (2026-09-18): niyet metni iki ajana da
# 7 gun boyunca enjekte ediliyor ve diske yaziliyor. Girdi 500 karakterle
# sinirli oldugu icin bugun zaman asimi uretilemiyor, ama kural desene
# baglanamaz: redaksiyon duserse YAZMA. Diger yedi cagri noktasi boyle.
if ($prot.Failed -gt 0) {
    Write-Output "HATA: sir redaksiyonu uygulanamadi ($($prot.Failed) desen). Niyet YAZILMADI."
    Write-BeyinMakbuz -Paths $p -Script 'niyet' -Outcome 'NIYET_REDAKSIYON_DUSTU' -Note "$($prot.Failed) desen uygulanamadi"
    exit 3
}
$metin = $prot.Text
if ($prot.Redactions -gt 0) { "UYARI: $($prot.Redactions) sir benzeri deger maskelendi." }

$kayit = [ordered]@{
    v       = 1
    text    = $metin
    project = [string]$Proje
    ts      = (Get-Date).ToString('o', [Globalization.CultureInfo]::InvariantCulture)
    agent   = (Get-BeyinAgent)
}
# YAZIM ASLA VARSAYILMAZ (2026-09-17, kosarak olculdu).
# Bu betik $ErrorActionPreference = 'SilentlyContinue' altinda calisiyor ve
# basari mesaji + makbuz KOSULSUZ basiliyordu. Iki vaka olculdu:
#   .state klasoru yerine ayni adda DOSYA  -> "Niyet kaydedildi (16 karakter)",
#       exit 0, niyet.json YOK, geri okuma "Kayitli niyet yok."
#   niyet.json baskasinda FileShare.None ile ACIK -> "Niyet kaydedildi",
#       exit 0, dosya DEGISMEDI.
# Kullanici niyetini yazdigini sanip devam ediyor; o niyet hicbir oturuma
# enjekte edilmiyor ve kimse bunu soylemiyor. ayar.ps1 ayni hatayi bugun
# kapatti; ayni kalip buraya da uygulanir: YAZ, GERI OKU, KARSILASTIR.
$mkBasarisiz = $null
try {
    New-Item -ItemType Directory -Force -Path $p.ScrState -ErrorAction Stop | Out-Null
} catch {
    $mkBasarisiz = "durum klasoru olusturulamadi: $($_.Exception.Message)"
}
if (-not $mkBasarisiz) {
    try {
        Write-BeyinText -Path $dosya -Text (ConvertTo-Json -InputObject $kayit -Compress) -ErrorAction Stop
    } catch {
        $mkBasarisiz = "yazilamadi: $($_.Exception.Message)"
    }
}
if (-not $mkBasarisiz) {
    # GERI OKUMA - motorun gercekte kullanacagi yoldan, taze.
    $geri = $null
    try { $geri = Get-BeyinNiyet -Paths $p -MaxGun 3650 } catch { }
    if ($null -eq $geri) {
        $mkBasarisiz = 'yazimdan sonra geri okunamadi (dosya olusmamis ya da bozuk)'
    } elseif ([string]$geri.Text -ne [string]$metin) {
        $mkBasarisiz = 'yazimdan sonra geri okunan metin farkli (dosya baska bir surec tarafindan tutuluyor olabilir)'
    }
}

if ($mkBasarisiz) {
    Write-BeyinLog -Vault $Vault -Message "niyet: YAZILAMADI ($mkBasarisiz)"
    Write-BeyinMakbuz -Paths $p -Script 'niyet' -Outcome 'NIYET_YAZILAMADI' -Note $mkBasarisiz
    Write-Host "HATA: niyet kaydedilemedi - $mkBasarisiz" -ForegroundColor Red
    "  hedef: $dosya"
    '  Niyet YAZILMADI; hicbir oturuma enjekte edilmeyecek. Dosyayi tutan bir surec'
    '  (editor, yedekleme, antivirus) varsa kapat ve tekrar dene.'
    exit 3
}

Write-BeyinLog -Vault $Vault -Message "niyet: kaydedildi ($($metin.Length) karakter$(if ($Proje) { ", proje=$Proje" }))"
Write-BeyinMakbuz -Paths $p -Script 'niyet' -Outcome 'NIYET_YAZILDI' -Note "$($metin.Length) karakter$(if ($Proje) { ", proje=$Proje" })"
"Niyet kaydedildi ($($metin.Length) karakter). Sonraki oturum acilisinda iki ajana da enjekte edilir; 7 gun sonra bayatlar."
"  $metin"
