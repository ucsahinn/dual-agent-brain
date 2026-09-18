# kaldir.ps1 - Beyin kancalarini bu makineden kaldirir.
#
# NE SILER: yalnizca KURULUM izlerini - kanca girdileri, launcher, dagitici,
# vault kaydi ve ~\.beyin klasoru (yalniz bizim dosyalarimizi tasiyorsa),
# skill baglantilari, \Beyin\ zamanlanmis gorevleri.
# -Yedekleri ile ayrica kur.ps1'in biraktigi *.yedek-* kopyalari da silinir.
#
# NE SILMEZ: VAULT'UN KENDISI. Notlarin, gunluk loglarin, kavram notlarin ve
# git gecmisin oldugu gibi kalir. Beyin susar, hafiza durur.
# Vault'u da silmek istiyorsan klasoru elle sil - bu betik bunu ASLA yapmaz.
# -IzinleriSikilastir ile degistirilen vault ACL'i de GERI ALINMAZ; sonuc
# bolumunde soylenir (geri almak icin: icacls "<vault>" /reset).
#
# Kullanim:
#   powershell -NoProfile -ExecutionPolicy Bypass -File kaldir.ps1 -KuruCalisma
#   powershell -NoProfile -ExecutionPolicy Bypass -File kaldir.ps1
#   powershell -NoProfile -ExecutionPolicy Bypass -File kaldir.ps1 -Yedekleri

param(
    [switch]$KuruCalisma,

    # kur.ps1'in her yazimda biraktigi *.yedek-<tarih> kopyalarini da sil
    # (~\.beyin, ~\.claude\hooks, settings.json ve hooks.json yaninda).
    # NEDEN opt-in (2026-09-16): yedekler eski ayar dosyalarini tasir, kullanici
    # geri donmek isteyebilir. Varsayilan: birakilir, SAYISI raporlanir - eski
    # surum hic soylemiyordu ve kullanici 'temiz kaldirildi' saniyordu (olculdu:
    # ~\.beyin'de 5, ~\.claude\hooks'ta 4 yedek kalmisti).
    [switch]$Yedekleri
)

$ErrorActionPreference = 'Continue'
$yapilan = New-Object System.Collections.Generic.List[string]
# KALDIRMA BASARISIZLIKLARI: eskiden hicbir yerde toplanmiyordu ve betik her
# durumda 0 ile cikiyordu - dusen bir kaldirma da 'KALDIRILDI' diyordu.
$basarisizlik = New-Object System.Collections.Generic.List[string]
$notlar  = New-Object System.Collections.Generic.List[string]
$birakilanYedek = 0

function Bildir([string]$M, [string]$Renk = 'Gray') { Write-Host "  $M" -ForegroundColor $Renk }

# Yedek deseni: kur.ps1 Yedekle() -> "<dosya>.yedek-yyyyMMdd-HHmmss"; elle alinmis
# ".yedek-faz0" gibi ekler de ayni onekle. Yalniz BIZIM dosyalarimizin yaninda,
# yalniz o dosyanin adiyla baslayan yedekler aranir.
function Yedekleri-Isle([string]$Dizin, [string]$Desen) {
    if (-not (Test-Path -LiteralPath $Dizin)) { return }
    foreach ($y in @(Get-ChildItem -LiteralPath $Dizin -File -Filter $Desen -Force -ErrorAction SilentlyContinue)) {
        if (-not $Yedekleri) { $script:birakilanYedek++; continue }
        if ($KuruCalisma) { Bildir "silinecek: $($y.FullName)" 'Yellow'; continue }
        Remove-Item -LiteralPath $y.FullName -Force -ErrorAction SilentlyContinue
        Bildir "silindi: $($y.Name)" 'Green'
        $yapilan.Add("yedek $($y.Name)")
    }
}

Write-Host ''
Write-Host 'Beyin kaldirma' -ForegroundColor Cyan
Write-Host ("  Mod : " + $(if ($KuruCalisma) { 'KURU CALISMA (hicbir sey silinmez)' } else { 'KALDIR' }))
Write-Host ("  Yedekler : " + $(if ($Yedekleri) { 'SILINECEK (-Yedekleri)' } else { 'birakilir (-Yedekleri ile silinir)' }))
Write-Host ''

# --- 0) Vault kaydi - SILINMEDEN ONCE oku ---
# NEDEN (2026-09-16): skill baglantilari <vault>\motor\skills\<ad> hedefine
# kuruludur; hangi junction'in bizim oldugunu vault yolundan anliyoruz. Eski
# surum vault.txt'yi 2. bolumde siliyor, 3. bolum sabit bir ad listesine
# bakiyordu - motor\skills'e eklenen ucuncu bir skill olu junction olarak kaliyordu.
function Test-GorevBizim {
    # Bir zamanlanmis gorev BU kurulumun mu?
    #
    # NEDEN (2026-09-18, kum havuzu testinde CANLI olarak gerceklesti):
    # \Beyin\ gorev yolu MAKINE GENELINDEDIR. $env:USERPROFILE'i sahte bir
    # eve cevirip izole bir kopyayi kaldirmak, GERCEK makinedeki 8 gece
    # gorevinin hepsini sildi. vault.txt'e bakan kapi bunu goremez, cunku o
    # dosya da sahte evin icindeydi.
    #
    # Gorevin EYLEMI ise sahte olamaz: icinde cagrilacak dagiticinin GERCEK
    # yolu yazar. Kaldirmanin dogru olcutu budur.
    param([object]$Gorev, [string]$Dagitici)
    if (-not $Dagitici) { return $false }
    try {
        foreach ($e in @($Gorev.Actions)) {
            $metin = "$($e.Execute) $($e.Arguments)"
            if ($metin.IndexOf($Dagitici, [StringComparison]::OrdinalIgnoreCase) -ge 0) { return $true }
        }
    } catch { }
    return $false
}

$beyinKok   = Join-Path $env:USERPROFILE '.beyin'
$vaultKayit = Join-Path $beyinKok 'vault.txt'
$vaultYolu  = ''
try {
    if (Test-Path -LiteralPath $vaultKayit) { $vaultYolu = (Get-Content -LiteralPath $vaultKayit -Raw -Encoding UTF8).Trim() }
} catch { }
if (-not $vaultYolu -and $env:BEYIN_VAULT) { $vaultYolu = $env:BEYIN_VAULT }
$vaultYolu = $vaultYolu.TrimEnd('\', '/')

# --- 1) Kanca girdileri ---
Write-Host '1) Kanca girdileri' -ForegroundColor Cyan
foreach ($a in @(@{ Ad = 'Claude'; Yol = (Join-Path $env:USERPROFILE '.claude\settings.json') },
                 @{ Ad = 'Codex';  Yol = (Join-Path $env:USERPROFILE '.codex\hooks.json') })) {
    # Ayar dosyasinin yanindaki kur.ps1 yedekleri (dosya olsun olmasin)
    Yedekleri-Isle (Split-Path $a.Yol -Parent) ((Split-Path $a.Yol -Leaf) + '.yedek-*')

    if (-not (Test-Path -LiteralPath $a.Yol)) { Bildir "$($a.Ad): ayar dosyasi yok"; continue }
    try {
        $veri = Get-Content -LiteralPath $a.Yol -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch { Bildir "$($a.Ad): JSON okunamadi - DOKUNULMADI" 'Red'; continue }
    if (-not $veri.PSObject.Properties['hooks']) { Bildir "$($a.Ad): kanca yok"; continue }

    $silinen = 0
    # PS 5.1 TUZAGI (olculdu 2026-09-17): ozelligi olmayan bir PSCustomObject
    # icin `.PSObject.Properties.Name` $null doner ve `@($null)` BOS DEGIL,
    # TEK ELEMANLI bir dizidir (Count = 1). Yani ilk kaldirmadan sonra
    # 'hooks' bos bir nesneye donusunce ikinci kosu $null bir olay adiyla
    # donguye giriyordu: "Cannot index into a null array", ardindan
    # "The property 'hooks' cannot be found on this object" ve
    # "value of argument name is not valid". Cikis kodu 0 kaliyordu, yani
    # kullanici bir yigin kirmizi hata gorup kaldirmanin basarili olup
    # olmadigini anlayamiyordu. Ayni durum motorun hic kurulmadigi bir
    # makinede kaldir.ps1 kosulunca da olusur.
    foreach ($olay in @($veri.hooks.PSObject.Properties.Name | Where-Object { $_ })) {
        $gruplar = @($veri.hooks.$olay | Where-Object { $null -ne $_ })
        foreach ($g in $gruplar) {
            if ($null -eq $g -or -not $g.PSObject.Properties['hooks']) { continue }
            $once = @($g.hooks).Count
            $g.hooks = @(@($g.hooks) | Where-Object { -not ($_.command -like '*beyin-launcher*') })
            $silinen += $once - @($g.hooks).Count
        }
        # Bosalan gruplari at, olay tamamen bosaldiysa olayi at
        $gruplar = @($gruplar | Where-Object { $null -ne $_ -and @($_.hooks).Count -gt 0 })
        if ($gruplar.Count -eq 0 -and $olay) { $veri.hooks.PSObject.Properties.Remove($olay) }
        else { $veri.hooks.$olay = $gruplar }
    }

    if ($silinen -eq 0) { Bildir "$($a.Ad): beyin girdisi yok"; continue }
    if ($KuruCalisma) { Bildir "$($a.Ad): $silinen girdi silinecek" 'Yellow'; continue }

    # YAZIM DOGRULANMADAN "SILINDI" DENMEZ (2026-09-18 denetimi).
    # $ErrorActionPreference 'Continue' altinda Copy/Write/Move sessizce
    # dusebilir (Controlled Folder Access, ACL, hedefte deny-write) ve eski
    # surum yine de KOSULSUZ yesil "girdi silindi" basip cikis 0 veriyordu:
    # kullanici motorun kaldirildigini sanirken kancalar calismaya devam
    # ediyordu. Artik yazimdan sonra dosya YENIDEN OKUNUP dogrulanir.
    $yazimOk = $false
    $yazimHata = ''
    try {
        Copy-Item -LiteralPath $a.Yol -Destination "$($a.Yol).yedek-$((Get-Date).ToString('yyyyMMdd-HHmmss', [Globalization.CultureInfo]::InvariantCulture))" -Force -ErrorAction Stop
        $tmp = $a.Yol + '.tmp'
        [System.IO.File]::WriteAllText($tmp, (($veri | ConvertTo-Json -Depth 12) + "`n"), (New-Object System.Text.UTF8Encoding $false))
        Move-Item -LiteralPath $tmp -Destination $a.Yol -Force -ErrorAction Stop
        $kontrol = Get-Content -LiteralPath $a.Yol -Raw -Encoding UTF8 -ErrorAction Stop
        $yazimOk = -not ($kontrol -like '*beyin-launcher*')
        if (-not $yazimOk) { $yazimHata = 'dosyada beyin-launcher girdisi HALA duruyor' }
    } catch {
        $yazimHata = $_.Exception.Message
    }
    if (-not $yazimOk) {
        Bildir "$($a.Ad): girdiler SILINEMEDI - $yazimHata" 'Red'
        $basarisizlik.Add("$($a.Ad) kanca girdileri silinemedi: $yazimHata")
        continue
    }
    Bildir "$($a.Ad): $silinen girdi silindi (yedek alindi)" 'Green'
    $yapilan.Add("$($a.Ad) kanca girdileri")
    if ($a.Ad -eq 'Codex') {
        Bildir "  NOT: Codex TUI'de /hooks ile degisikligi onaylaman gerekebilir." 'Yellow'
    }
}

# --- 2) Dosyalar ---
Write-Host ''
Write-Host '2) Kurulum dosyalari' -ForegroundColor Cyan
$simYol = Join-Path $env:USERPROFILE '.claude\hooks\beyin-launcher.ps1'
foreach ($f in @($simYol,
                 (Join-Path $beyinKok 'beyin-launcher.ps1'),
                 (Join-Path $beyinKok 'beyin.ps1'),
                 (Join-Path $beyinKok 'beyin.cmd'),
                 (Join-Path $beyinKok 'ayar.json'),
                 $vaultKayit)) {
    if (-not (Test-Path -LiteralPath $f)) { Bildir "yok    : $(Split-Path $f -Leaf)"; continue }
    if ($KuruCalisma) { Bildir "silinecek: $f" 'Yellow'; continue }
    Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue
    Bildir "silindi: $(Split-Path $f -Leaf)" 'Green'
    $yapilan.Add((Split-Path $f -Leaf))
}
# Yedekler: sim'in yaninda (~\.claude\hooks) ve ~\.beyin icinde
Yedekleri-Isle (Split-Path $simYol -Parent) 'beyin-launcher.ps1.yedek-*'
Yedekleri-Isle $beyinKok '*.yedek-*'

# --- Ortam degisikligini isletim sistemine duyur ---------------------------
#
# NEDEN VAR: PATH'i REG_EXPAND_SZ turunu koruyarak yazmak icin kayit defterine
# DOGRUDAN yaziyoruz. Bunun bedeli, [Environment]::SetEnvironmentVariable'in
# kendiliginden yaptigi WM_SETTINGCHANGE yayinini kaybetmek. Yayin olmadan
# Explorer ortam blogunu tazelemez ve Explorer'dan acilan HER yeni terminal
# eski PATH'i miras alir - yani "yeni bir terminal ac" tarifi calismaz
# (inceleme 2026-09-17). Yayin basarisiz olursa kurulum BOZULMAZ: en kotu
# ihtimalle kullanici oturumu kapatip acar, ya da tam yolu kullanir.
#
# MALIYET: bu makinede 2.4 sn olculdu (SMTO_ABORTIFHUNG + 1000 ms,
# ust seviye pencere basina). Kurulum/kaldirma tek seferlik oldugu icin
# kabul edildi; kanca yolunda ASLA cagrilmaz.
#
# NOT: ayni blok kaldir.ps1'de de var. lib.ps1'e tasinmadi cunku bu iki betik
# vault'tan BAGIMSIZ calisabilmeli (kur.ps1 vault olusmadan once de kosar).
function Duyur-OrtamDegisikligi {
    try {
        if (-not ('BeyinOrtamYayin' -as [type])) {
            Add-Type -Namespace Beyin -Name OrtamYayin -MemberDefinition @'
[DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
public static extern System.IntPtr SendMessageTimeout(
    System.IntPtr hWnd, uint Msg, System.IntPtr wParam, string lParam,
    uint fuFlags, uint uTimeout, out System.UIntPtr lpdwResult);
'@ -ErrorAction Stop
        }
        $sonuc = [System.UIntPtr]::Zero
        # HWND_BROADCAST = 0xffff, WM_SETTINGCHANGE = 0x1A, SMTO_ABORTIFHUNG = 0x2
        [void][Beyin.OrtamYayin]::SendMessageTimeout(
            [System.IntPtr]0xffff, 0x1A, [System.IntPtr]::Zero, 'Environment',
            0x2, 1000, [ref]$sonuc)
        return $true
    } catch { return $false }
}

# --- Kullanici PATH'inden '~\.beyin' girdisini cikar ---
#
# kur.ps1 bu girdiyi '%USERPROFILE%\.beyin' bicimiyle ekler, ama baska bir
# surum ya da kullanici tam yolu yazmis olabilir: karsilastirma GENISLETILMIS
# yol uzerinden yapilir. Deger turu (REG_EXPAND_SZ) korunur - REG_SZ'ye
# cevirmek kullanicinin '%JAVA_HOME%\bin' gibi diger girdilerini dondururdu.
try {
    $reg = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', $true)
    if ($reg) {
        try {
            $tur = try { $reg.GetValueKind('Path') } catch { [Microsoft.Win32.RegistryValueKind]::ExpandString }
            $ham = [string]$reg.GetValue('Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
            $parcalar = @($ham -split ';' | Where-Object { $_ -ne '' })
            $hedef = $beyinKok.TrimEnd('\')
            $kalanlar = @($parcalar | Where-Object {
                -not [string]::Equals([Environment]::ExpandEnvironmentVariables($_).TrimEnd('\'), $hedef, [StringComparison]::OrdinalIgnoreCase)
            })
            if ($kalanlar.Count -eq $parcalar.Count) {
                Bildir "PATH: girdi yok, dokunulmadi" 'DarkGray'
            } else {
                Bildir "PATH'ten cikarilacak: $hedef" 'Yellow'
                if (-not $KuruCalisma) {
                    $reg.SetValue('Path', ($kalanlar -join ';'), $tur)
                    $duyuruldu = Duyur-OrtamDegisikligi
                    Bildir $(if ($duyuruldu) { 'PATH guncellendi (YENI terminalde gecerli)' } else { 'PATH guncellendi - duyuru basarisiz, oturumu kapatip acmak gerekebilir' }) 'Green'
                    $yapilan.Add('kullanici PATH girdisi')
                }
            }
        } finally { $reg.Close() }
    }
} catch {
    Bildir "PATH okunamadi/yazilamadi: $($_.Exception.Message)" 'Yellow'
}

# ~\.beyin klasorunun kendisi: YALNIZ bizim dosyalarimizi tasiyorsa silinir.
# NEDEN: klasor kur.ps1'e aittir ama icine baska bir sey konmus olabilir;
# yabanci dosya varsa klasor birakilir ve adlari soylenir.
if (Test-Path -LiteralPath $beyinKok) {
    $kalan = @(Get-ChildItem -LiteralPath $beyinKok -Force -ErrorAction SilentlyContinue)
    $bizim = @('beyin-launcher.ps1', 'beyin.ps1', 'beyin.cmd', 'vault.txt', 'ayar.json',
               'yayin-yasak.txt', 'yayin-izin.txt')
    $yabanci = @($kalan | Where-Object {
        -not ($bizim -contains $_.Name) -and $_.Name -notlike '*.yedek-*' -and $_.Name -notlike '*.tmp-*'
    })
    $yedekKalan = @($kalan | Where-Object { $_.Name -like '*.yedek-*' -or $_.Name -like '*.tmp-*' }).Count
    if ($yabanci.Count -gt 0) {
        Bildir "birakildi: $beyinKok  (yabanci dosya var: $(($yabanci | ForEach-Object { $_.Name }) -join ', '))" 'Yellow'
    } elseif ($KuruCalisma) {
        # Kuru calismada gercek kosunun sonucunu soyle: yedekler -Yedekleri olmadan kalir, klasor de kalir.
        if ($yedekKalan -gt 0 -and -not $Yedekleri) { Bildir "birakilacak: $beyinKok  ($yedekKalan yedek dosya - -Yedekleri ile klasorle birlikte silinir)" 'Yellow' }
        else { Bildir "silinecek: $beyinKok  ($($kalan.Count) dosya, hepsi bizim)" 'Yellow' }
    } else {
        $kalan = @(Get-ChildItem -LiteralPath $beyinKok -Force -ErrorAction SilentlyContinue)
        if ($kalan.Count -eq 0) {
            Remove-Item -LiteralPath $beyinKok -Force -ErrorAction SilentlyContinue
            Bildir "silindi: $beyinKok" 'Green'
            $yapilan.Add('~\.beyin klasoru')
        } else {
            Bildir "birakildi: $beyinKok  ($($kalan.Count) yedek dosya - -Yedekleri ile silinir)" 'Yellow'
        }
    }
}

# --- 3) Skill baglantilari ---
Write-Host ''
Write-Host '3) Skill baglantilari' -ForegroundColor Cyan
# LISTE DINAMIK (2026-09-16): kur.ps1 motor\skills altindaki HER klasoru uc koke
# baglar; burada da ad listesi degil, junction HEDEFI belirleyici: hedef
# <vault>\motor\skills\ altindaysa bizimdir. vault.txt yoksa/eskiyse geri donus:
# bilinen adlar + '\motor\skills\' iceren hedef. Junction silinir, icerik DEGIL.
$bilinen = @('beyin-doktor', 'gecmis-import')
$skillOnek = if ($vaultYolu) { (Join-Path $vaultYolu 'motor\skills') + '\' } else { '' }
foreach ($kok in @((Join-Path $env:USERPROFILE '.claude\skills'),
                   (Join-Path $env:USERPROFILE '.codex\skills'),
                   (Join-Path $env:USERPROFILE '.agents\skills'))) {
    if (-not (Test-Path -LiteralPath $kok)) { continue }
    foreach ($it in @(Get-ChildItem -LiteralPath $kok -Directory -Force -ErrorAction SilentlyContinue)) {
        $bagli = ($it.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0
        if (-not $bagli) {
            if ($bilinen -contains $it.Name) { Bildir "atlandi: $($it.FullName)  (baglanti degil, GERCEK klasor - dokunulmadi)" 'Yellow' }
            continue
        }
        $hedefYol = ''
        try { $hedefYol = [string](@($it.Target) | Select-Object -First 1) } catch { }
        $bizimSkill = $false
        if ($skillOnek -and $hedefYol -and $hedefYol.StartsWith($skillOnek, [StringComparison]::OrdinalIgnoreCase)) { $bizimSkill = $true }
        elseif ($hedefYol -like '*\motor\skills\*' -and (-not $skillOnek -or ($bilinen -contains $it.Name))) { $bizimSkill = $true }
        if (-not $bizimSkill) { continue }
        if ($KuruCalisma) { Bildir "silinecek: $($it.FullName)  -> $hedefYol" 'Yellow'; continue }
        # Junction'i sil: icerigi DEGIL, yalnizca baglantiyi.
        [System.IO.Directory]::Delete($it.FullName, $false)
        Bildir "silindi: $($it.FullName)" 'Green'
        $yapilan.Add("skill baglantisi $($it.Name)")
    }
}

# --- 4) Zamanlanmis gorevler (Faz 5D) ---
Write-Host ''
Write-Host '4) Zamanlanmis gorevler' -ForegroundColor Cyan
try {
    $dagitici = Join-Path $beyinKok 'beyin.ps1'
    $hepsi = @(Get-ScheduledTask -TaskPath '\Beyin\' -ErrorAction SilentlyContinue)
    $zg    = @($hepsi | Where-Object { Test-GorevBizim -Gorev $_ -Dagitici $dagitici })
    $yabanci = @($hepsi).Count - @($zg).Count
    if ($yabanci -gt 0) {
        $notlar.Add("$yabanci zamanlanmis gorev BASKA bir beyin kurulumuna ait (eylemleri $dagitici yolunu cagirmiyor) - DOKUNULMADI.")
    }
    if ($zg.Count -eq 0) { Bildir "yok    : \Beyin\ altinda bu kuruluma ait gorev yok$(if ($yabanci) { " ($yabanci yabanci gorev korundu)" })" }
    elseif ($KuruCalisma) { Bildir "kaldirilacak: $($zg.Count) zamanlanmis gorev (\Beyin\)$(if ($yabanci) { ", $yabanci yabanci gorev korunacak" })" 'Yellow' }
    else {
        foreach ($t in $zg) { Unregister-ScheduledTask -TaskName $t.TaskName -TaskPath '\Beyin\' -Confirm:$false -ErrorAction SilentlyContinue }
        Bildir "kaldirildi: $($zg.Count) zamanlanmis gorev$(if ($yabanci) { " ($yabanci yabanci gorev korundu)" })" 'Green'
        $yapilan.Add("$($zg.Count) zamanlanmis gorev")
    }
} catch { Bildir "zamanlanmis gorevler okunamadi: $($_.Exception.Message)" 'Yellow' }

# --- Notlar: ne BIRAKILDI ---
if ($birakilanYedek -gt 0) { $notlar.Add("$birakilanYedek adet *.yedek-* dosyasi birakildi (silmek icin: kaldir.ps1 -Yedekleri).") }
if ($vaultYolu -and (Test-Path -LiteralPath $vaultYolu)) {
    try {
        $acl = Get-Acl -LiteralPath $vaultYolu -ErrorAction Stop
        if (@($acl.Access | Where-Object { $_.IsInherited }).Count -eq 0) {
            $notlar.Add("Vault izinleri sikilastirilmis (miras kirik) ve GERI ALINMADI. Geri almak icin: icacls `"$vaultYolu`" /reset")
        }
    } catch { }
}

# --- Sonuc ---
Write-Host ''
if ($KuruCalisma) {
    Write-Host 'KURU CALISMA bitti - hicbir sey silinmedi.' -ForegroundColor Yellow
    Write-Host 'Gercekten kaldirmak icin -KuruCalisma olmadan calistir.' -ForegroundColor Yellow
} else {
    if ($basarisizlik.Count -gt 0) {
        Write-Host "KISMEN KALDIRILDI - $($yapilan.Count) oge silindi, $($basarisizlik.Count) ISLEM DUSTU." -ForegroundColor Red
        foreach ($b in $basarisizlik) { Write-Host "  - $b" -ForegroundColor Red }
    } else {
        Write-Host "KALDIRILDI - $($yapilan.Count) oge." -ForegroundColor Green
    }
}
if ($notlar.Count -gt 0) {
    Write-Host ''
    Write-Host 'BIRAKILANLAR:' -ForegroundColor Yellow
    foreach ($n in $notlar) { Write-Host "  - $n" -ForegroundColor Yellow }
}
Write-Host ''
Write-Host 'VAULT DOKUNULMADI. Notlarin, gunluk loglarin ve git gecmisin yerinde.' -ForegroundColor Cyan
Write-Host 'Yeniden kurmak icin: kurulum\kur.ps1' -ForegroundColor Cyan
Write-Host ''

# Sessiz basarisizlik olmasin: dusen islem varsa cikis kodu da soylesin.
exit $(if ($basarisizlik.Count -gt 0) { 1 } else { 0 })
