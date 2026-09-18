# kur.ps1 - Beyin ikinci beyni bu makineye kurar.
#
# NE YAPAR (hepsi FIKIRLIDIR: ayni sonucu vermek icin tekrar tekrar
# calistirilabilir, var olan bir kurulumu bozmaz):
#   1. Vault'u dogrular; eksik klasor/sozlesme dosyalarini tamamlar
#   2. ~\.beyin\vault.txt yazar        (vault yolunun TEK kaydi)
#   3. ~\.beyin\beyin.ps1 kurar        (tasinabilir tek giris noktasi)
#   3b. ~\.beyin\beyin.cmd kurar + ~\.beyin'i kullanici PATH'ine ekler
#       (boylece her yerden sadece: beyin durum). -PathAtla ile kapatilir.
#   4. ~\.claude\hooks\beyin-launcher.ps1 kurar (Codex icin sim; gercek launcher ~\.beyin\)
#   5. ~\.claude\settings.json icine kanca girdilerini BIRLESTIRIR
#   6. ~\.codex\hooks.json icin ayni seyi yapar - ama DIKKATLE (asagiya bak)
#   7. Skill'leri iki ajanin da tarayacagi dizinlere baglar (junction)
#   8. Kurulumu DOGRULAR ve rapor verir
#
# CODEX UYARISI: Codex her kanca tanimini SHA-256 ile hash'ler ve degismis bir
# kancayi /hooks ile yeniden onaylanana kadar SESSIZCE atlar. Bu yuzden
# hooks.json'a yalnizca GEREKTIGINDE dokunuruz:
#   - beyin girdisi yoksa  -> ekleriz ve "/hooks ile onayla" deriz
#   - ayni girdi varsa     -> HIC DOKUNMAYIZ (hash bozulmasin)
#   - farkli girdi varsa   -> DOKUNMAYIZ, farki gosteririz, karar kullanicinin
#   - -CodexZorla verildiyse -> beyin girdilerini beklenen komut+timeout ile
#     YERINDE YENILERIZ. hooks.json'u degistirmenin TEK onayli yolu budur;
#     hash bilerek bozulur, ardindan Codex TUI'de /hooks ile yeniden onay SARTTIR.
#
# Kullanim:
#   powershell -NoProfile -ExecutionPolicy Bypass -File kur.ps1
#   powershell -NoProfile -ExecutionPolicy Bypass -File kur.ps1 -Vault "D:\Beyin" -KuruCalisma

param(
    # Vault konumu. Verilmezse: bu betik <vault>\kurulum\ altinda oldugu icin
    # bir seviye yukarisi vault'tur.
    [string]$Vault = (Split-Path $PSScriptRoot -Parent),

    # Yazmadan once ne yapilacagini goster.
    [switch]$KuruCalisma,

    # Gece gorevlerini de kaydet (kurulum\zamanla.ps1). Opt-in: zamanlayici
    # kullanicinin makinesine gorev yazar, varsayilan olarak yapilmaz.
    [switch]$Zamanla,

    # Codex kanca ayarini ZORLA yenile: beyin girdileri farkli komut/timeout ile
    # kayitliysa beklenen bicime yeniden yazilir, eksikler eklenir. Sonrasinda
    # Codex TUI'de /hooks ile yeniden onay gerekir. Varsayilan: yalnizca eksikse
    # yazar, farkli girdiye dokunmaz.
    # NEDEN (2026-09-16): eski surumde bu bayrak farkli girdiyi ASLA yenilemiyordu
    # ('atlandi farkli girdiler var, dokunulmadi') - kurulumun onerdigi care bostu.
    [switch]$CodexZorla,

    # YALNIZ VAULT: klasor yapisi + baslangic dosyalari + surum damgasi kurulur;
    # ev dizinine (launcher, dagitici, kanca ayarlari, skill baglantilari)
    # HIC DOKUNULMAZ.
    #
    # Ne ise yarar:
    #   - Ikinci bir vault hazirlamak (deneme/arsiv) - makine ayarini bozmadan
    #   - Bir vault'un eksiklerini tamamlamak
    #   - Kurulumu bir kopyada dogrulamak (yeni makine simulasyonu). Bu mod
    #     olmadan test ya eksik kalir ya da calisan kurulumu bozar.
    [switch]$YalnizVault,

    # PATH adimini ATLA. 'beyin' komutunu PATH'e eklemek VARSAYILANDIR:
    # o adim olmadan belgelerdeki her ornek ("beyin durum") yabanci bir
    # kullanicida "komut bulunamadi" ile duser.
    #
    # NEDEN [switch] (sifir makine testi 2026-09-17, olculdu): once
    # `[bool]$PathEkle = $true` idi ve `-PathEkle:$false` DENENINCE kurulum
    # hic calismiyordu - "Cannot convert value System.String to type
    # System.Boolean", cikis 1, tek dosya bile yazilmadan. Sebep: `-File` ile
    # her arguman METIN gecer, `[bool]` metin kabul etmez. `-File` ise bu
    # motorun belgelenen tek cagri bicimi. Switch metinle gelmez, bayragin
    # varligina bakar; -KuruCalisma / -YalnizVault / -Zamanla hep boyle.
    [switch]$PathAtla,

    # DOSYA IZINLERINI SIKILASTIR (opt-in, bilerek varsayilan DEGIL).
    #
    # Vault kisisel notlar, musteri adlari ve proje detaylari tasir. Kanonik
    # erisim politikasi: miras KIRIK, tam yetki yalniz sahibi + SYSTEM +
    # Administrators. brain-cli bu politikayi denetliyor.
    #
    # Neden varsayilan degil: ACL degistirmek geri alinmasi zahmetli, sisteme
    # dokunan bir islemdir ve yanlis bir yolda calistirilirsa (ornek: yanlis
    # -Vault) zarar verir. Kullanici ISTEYEREK acmali.
    [switch]$IzinleriSikilastir
)

$ErrorActionPreference = 'Stop'

# VAULT YOLUNU MUTLAKLASTIR (2026-09-16).
# NEDEN: '-Vault .' ya da '..\Beyin' gibi goreli bir deger vault.txt'ye OLDUGU
# GIBI yaziliyordu (olculdu: 'kur.ps1 -KuruCalisma -Vault .' -> 'vault.txt ... -> .').
# Launcher '.'yi her kancanin KENDI cwd'sine gore cozer: kurulum vault icinde
# kostugu icin canli deneme gecer ve 'KURULUM TAMAM' basilir, ama baska bir
# proje klasorunde acilan hicbir oturum hafizaya girmez - sessiz, tam kayip.
# Resolve-Path KULLANILMAZ: vault henuz olmayabilir. Sondaki ters egik de
# atilir; 'D:\Beyin\' her kosuda vault.txt'yi yeniden yaziyordu.
if ([string]::IsNullOrWhiteSpace($Vault)) { throw '-Vault bos olamaz.' }
$cwdFs = (Get-Location -PSProvider FileSystem).ProviderPath
$Vault = [IO.Path]::GetFullPath([IO.Path]::Combine($cwdFs, $Vault)).TrimEnd('\', '/')
if ($Vault -match '^[A-Za-z]:$') { $Vault += '\' }   # surucu koku: 'C:' tek basina cwd'ye gore cozulur
$ilerleme = New-Object System.Collections.Generic.List[object]
$uyarilar = New-Object System.Collections.Generic.List[string]

function Adim([string]$Ad, [string]$Sonuc, [string]$Detay = '') {
    $ilerleme.Add([pscustomobject]@{ Adim = $Ad; Sonuc = $Sonuc; Detay = $Detay })
    $renk = switch ($Sonuc) { 'kuruldu' { 'Green' } 'zaten' { 'DarkGray' } 'atlandi' { 'Yellow' } 'HATA' { 'Red' } default { 'Gray' } }
    Write-Host ("  {0,-9} {1}{2}" -f $Sonuc, $Ad, $(if ($Detay) { "  -  $Detay" } else { '' })) -ForegroundColor $renk
}
function Uyar([string]$M) { $uyarilar.Add($M) }

function Test-KancaAyariGecerli {
    # Dosya VAR + JSON olarak AYRISTIRILABILIR + beyin kancasi iceriyor.
    # Ucu birden saglanmadan "OK" denmez: ajan bu dosyayi ConvertFrom-Json ile
    # okur, alt dizgi aramasiyla degil.
    param([string]$Yol)
    if (-not (Test-Path -LiteralPath $Yol)) { return $false }
    $ham = $null
    try { $ham = Get-Content -LiteralPath $Yol -Raw -Encoding UTF8 -ErrorAction Stop } catch { return $false }
    if (-not $ham) { return $false }
    try { $null = $ham | ConvertFrom-Json } catch { return $false }
    return ($ham -like '*beyin-launcher*')
}

function Yaz-Dosya([string]$Yol, [string]$Icerik) {
    # ATOMIK: gecici dosyaya yaz, sonra yerine koy. Dogrudan yazim dosyayi
    # ACILIS aninda truncate eder; surec o pencerede olurse hedef 0 bayt kalir.
    if ($KuruCalisma) { return }
    $dizin = Split-Path $Yol -Parent
    if ($dizin -and -not (Test-Path -LiteralPath $dizin)) { New-Item -ItemType Directory -Force -Path $dizin | Out-Null }
    $tmp = $Yol + '.tmp-' + [guid]::NewGuid().ToString('N').Substring(0, 8)
    try {
        [System.IO.File]::WriteAllText($tmp, $Icerik, (New-Object System.Text.UTF8Encoding $false))
        if (Test-Path -LiteralPath $Yol) {
            try { [System.IO.File]::Replace($tmp, $Yol, $null) }
            catch { Move-Item -LiteralPath $tmp -Destination $Yol -Force }
        } else {
            Move-Item -LiteralPath $tmp -Destination $Yol -Force
        }
    } finally {
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
    }
}

function Yaz-Bayt([string]$Yol, [byte[]]$Bayt) {
    # ATOMIK BAYT YAZIMI (2026-09-16) - Yaz-Dosya'nin ikili esi.
    # NEDEN: launcher/dagitici/sim ve ayri vault'ta motor dosyalari duz
    # 'Copy-Item -Force' ile uzerine yaziliyordu; Copy-Item hedefi ACILISTA
    # truncate eder. Kurulum o pencerede kesilirse (acik bir ajan oturumunda
    # 'beyin kur' + Ctrl+C) ~\.beyin\beyin-launcher.ps1 0 bayt kalir ve iki
    # ajanin dort kancasi da parse hatasiyla duser; ayri vault'ta lib.ps1 yarim
    # kalirsa motor tumden durur. Proje kurali 'tum yazimlar atomik' - kendi
    # Yaz-Dosya'miz bunu zaten soyluyordu, kopyalar uymuyordu.
    if ($KuruCalisma) { return }
    $dizin = Split-Path $Yol -Parent
    if ($dizin -and -not (Test-Path -LiteralPath $dizin)) { New-Item -ItemType Directory -Force -Path $dizin | Out-Null }
    $tmp = $Yol + '.tmp-' + [guid]::NewGuid().ToString('N').Substring(0, 8)
    try {
        [System.IO.File]::WriteAllBytes($tmp, $Bayt)
        if (Test-Path -LiteralPath $Yol) {
            try { [System.IO.File]::Replace($tmp, $Yol, $null) }
            catch { Move-Item -LiteralPath $tmp -Destination $Yol -Force }
        } else {
            Move-Item -LiteralPath $tmp -Destination $Yol -Force
        }
    } finally {
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
    }
}

function Kopyala-Atomik([string]$Kaynak, [string]$Hedef) {
    # 'Copy-Item -Force' yerine: kaynagi oku, hedefe ATOMIK yaz (bkz. Yaz-Bayt).
    Yaz-Bayt $Hedef ([System.IO.File]::ReadAllBytes($Kaynak))
}

function Icacls-Kos([string[]]$Argumanlar) {
    # icacls'i CIKIS KODU + TUM CIKTI ile calistirir.
    # NEDEN (2026-09-16): bu betik $ErrorActionPreference='Stop' ile kosar ve PS 5.1'de
    # '2>&1' yerel komutun her stderr satirini NativeCommandError'a cevirir; Stop
    # altinda bu TERMINATING olur. Yani icacls bir hata basinca (ad cozulemedi,
    # yol yok) kod cikis kodunu hic okuyamadan try/catch'e ucuyor ve 'ACL
    # okunamadi' diye yanlis bir satir basiliyordu (harness'ta olculdu). Burada
    # tercih gecici olarak Continue'ya alinir; hata satirlari da metne katilir.
    $eski = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $satirlar = @(& icacls @Argumanlar 2>&1 | ForEach-Object {
            if ($_ -is [System.Management.Automation.ErrorRecord]) { $_.Exception.Message } else { [string]$_ }
        })
        return @{ Kod = $LASTEXITCODE; Cikti = ($satirlar -join "`n") }
    } finally { $ErrorActionPreference = $eski }
}

function Yedekle([string]$Yol) {
    if ($KuruCalisma -or -not (Test-Path -LiteralPath $Yol)) { return $null }
    $y = "$Yol.yedek-$((Get-Date).ToString('yyyyMMdd-HHmmss', [Globalization.CultureInfo]::InvariantCulture))"
    Copy-Item -LiteralPath $Yol -Destination $y -Force
    return $y
}

Write-Host ''
Write-Host 'Beyin kurulumu' -ForegroundColor Cyan
Write-Host ("  Vault : $Vault")
Write-Host ("  Mod   : " + $(if ($KuruCalisma) { 'KURU CALISMA (hicbir sey yazilmaz)' } else { 'kurulum' }))
Write-Host ''

# ===========================================================================
# 1) VAULT ISKELETI
# ===========================================================================
Write-Host '1) Vault iskeleti' -ForegroundColor Cyan

if (-not (Test-Path -LiteralPath $Vault)) {
    if ($KuruCalisma) { Adim 'vault dizini' 'atlandi' 'kuru calisma' }
    else { New-Item -ItemType Directory -Force -Path $Vault | Out-Null; Adim 'vault dizini' 'kuruldu' $Vault }
} else {
    Adim 'vault dizini' 'zaten' $Vault
}

$klasorler = @('00-inbox', '10-command-center', '20-goals', '30-projects', '40-knowledge',
               '50-research', '60-decisions', '70-personal', '80-memory', '85-daylogs',
               '86-compiled', '86-compiled\concepts', '86-compiled\sources', '90-archive', 'templates',
               'motor\hooks', 'motor\scripts', 'motor\skills',
               'motor\scripts\.state', 'motor\scripts\.state\queue',
               'motor\scripts\.state\watermarks', 'motor\scripts\.state\sessions',
               'motor\scripts\.state\claims', 'motor\scripts\.state\makbuz')
$eksik = 0
foreach ($k in $klasorler) {
    $y = Join-Path $Vault $k
    if (-not (Test-Path -LiteralPath $y)) {
        $eksik++
        if (-not $KuruCalisma) { New-Item -ItemType Directory -Force -Path $y | Out-Null }
    }
}
Adim 'klasor yapisi' $(if ($eksik) { 'kuruldu' } else { 'zaten' }) "$($klasorler.Count) klasor, $eksik tanesi eksikti"

# Motor dosyalari yerinde mi (bu betik depodan calistiriliyorsa motor bos olabilir)
$motorKaynak = Join-Path $PSScriptRoot '..\motor'
$motorHedef  = Join-Path $Vault 'motor'
if ((Resolve-Path -LiteralPath $motorKaynak -ErrorAction SilentlyContinue).Path -ne
    (Resolve-Path -LiteralPath $motorHedef  -ErrorAction SilentlyContinue).Path) {
    if (Test-Path -LiteralPath $motorKaynak) {
        $kopyalanan = 0
        if (-not $KuruCalisma) {
            # DIKKAT: duz 'Copy-Item -Recurse' KULLANILMAZ. scripts\ altinda
            # .state var: isaretler (watermark), is kuyrugu, oturum durumlari,
            # butce sayaclari ve motor logu. Bunlar KAYNAK VAULT'A AITTIR.
            # Yeni bir vault'a kopyalanirsa motor "bu transkript zaten
            # islenmis" sanar ve gercek oturumlari SESSIZCE atlar - yani yeni
            # beyin dogar dogmaz hafiza kaybina ugrar. Ilk surumde tam olarak
            # bu oluyordu (test vault'unda 1457 dosya; 1400'u baska bir
            # vault'un durumuydu).
            foreach ($alt in @('hooks', 'scripts', 'skills')) {
                $k = Join-Path $motorKaynak $alt
                if (-not (Test-Path -LiteralPath $k)) { continue }
                # Kaynak yolu COZULMELI: $motorKaynak icinde '..' var
                # (<kurulum>\..\motor). Cozulmemis yol, Get-ChildItem'in
                # dondurdugu MUTLAK FullName'den daha uzun oluyor ve Substring
                # "startIndex cannot be larger than length" ile patliyor.
                $k = (Get-Item -LiteralPath $k).FullName
                foreach ($f in @(Get-ChildItem -LiteralPath $k -Recurse -File -ErrorAction SilentlyContinue)) {
                    $rel = $f.FullName.Substring($k.Length).TrimStart('\', '/')
                    if (($rel -split '[\\/]') -contains '.state') { continue }
                    if ($f.Name -like '*.tmp-*' -or $f.Name -like '*.yedek-*') { continue }
                    $h = Join-Path (Join-Path $motorHedef $alt) $rel
                    $hd = Split-Path $h -Parent
                    if (-not (Test-Path -LiteralPath $hd)) { New-Item -ItemType Directory -Force -Path $hd | Out-Null }
                    Kopyala-Atomik $f.FullName $h   # atomik: canli motor dosyasi (bkz. Yaz-Bayt)
                    $kopyalanan++
                }
            }
        }
        # KOK SOZLESME DOSYALARI + SABLONLAR.
        #
        # brain-cli semasi bunlari ZORUNLU sayiyor. Depo klonu vault'un kendisi
        # oldugunda zaten yerindeler; ama 'kur.ps1 -Vault <bos dizin>' ile
        # ikinci bir vault kurulurken eksik kaliyorlardi ve yeni beyin
        # sema-gecersiz doguyordu (temiz kurulum testinde 5 eksik dosya).
        $kokKaynak = (Get-Item -LiteralPath (Join-Path $PSScriptRoot '..')).FullName
        foreach ($kd in @('AGENTS.md', 'CLAUDE.md', 'brain.config.json', '.codex-chef-brain.json', '.gitignore')) {
            $kk = Join-Path $kokKaynak $kd
            $kh = Join-Path $Vault $kd
            if ((Test-Path -LiteralPath $kk) -and -not (Test-Path -LiteralPath $kh)) {
                if (-not $KuruCalisma) { Copy-Item -LiteralPath $kk -Destination $kh -Force }
                $kopyalanan++
            }
        }
        # README.md: depo kokunde DEPO tanitimi olabilir; vault'a giden
        # surumu kurulum\DEPO-README.md'den degil, varsa kok README'den alinir.
        $rk = Join-Path $kokKaynak 'README.md'
        $rh = Join-Path $Vault 'README.md'
        if ((Test-Path -LiteralPath $rk) -and -not (Test-Path -LiteralPath $rh)) {
            if (-not $KuruCalisma) { Copy-Item -LiteralPath $rk -Destination $rh -Force }
            $kopyalanan++
        }
        # templates/: not sablonlari
        $tk = Join-Path $kokKaynak 'templates'
        if (Test-Path -LiteralPath $tk) {
            foreach ($tf in @(Get-ChildItem -LiteralPath $tk -File -ErrorAction SilentlyContinue)) {
                $th = Join-Path (Join-Path $Vault 'templates') $tf.Name
                if (Test-Path -LiteralPath $th) { continue }
                if (-not $KuruCalisma) {
                    $thd = Split-Path $th -Parent
                    if (-not (Test-Path -LiteralPath $thd)) { New-Item -ItemType Directory -Force -Path $thd | Out-Null }
                    Copy-Item -LiteralPath $tf.FullName -Destination $th -Force
                }
                $kopyalanan++
            }
        }
        Adim 'motor dosyalari' 'kuruldu' "$kopyalanan dosya kopyalandi (.state HARIC - o kaynak vault'a ait)"
    }
} else {
    $hookSay = @(Get-ChildItem (Join-Path $Vault 'motor\hooks') -Filter '*.ps1' -File -ErrorAction SilentlyContinue).Count
    $scrSay  = @(Get-ChildItem (Join-Path $Vault 'motor\scripts') -Filter '*.ps1' -File -ErrorAction SilentlyContinue).Count
    Adim 'motor dosyalari' 'zaten' "$hookSay kanca + $scrSay betik yerinde"
}

# --- Baslangic dosyalari (iskelet) ---
#
# NEDEN: motor 80-memory dosyalarini OKUR ama URETMEZ - orasi kuratorlu bolge
# ve motorun oraya yazmasi vault sozlesmesine aykiri. Sonuc: temiz bir kurulumda
# o dosyalar hic olusmuyordu ve doktor 6 ayri satirda "yok" diyordu; yeni makine
# simulasyonunda tam olarak bu goruldu. Iskelet bosluğu doldurur: dosyalar VAR
# ama BOS - yapisi dogru, icerigi kullanicinin.
#
# ASLA UZERINE YAZMAZ. Yalnizca hedef YOKSA kopyalar. Boylece kur.ps1 var olan
# bir beyinde tekrar tekrar calistirilabilir ve kullanicinin yazdigi hicbir sey
# kaybolmaz.
$iskelet = Join-Path $PSScriptRoot 'iskelet'
if (Test-Path -LiteralPath $iskelet) {
    $yeni = 0; $duran = 0
    foreach ($f in @(Get-ChildItem -LiteralPath $iskelet -Recurse -File -Force -ErrorAction SilentlyContinue)) {
        $rel = $f.FullName.Substring($iskelet.Length).TrimStart('\', '/')
        $hedef = Join-Path $Vault $rel
        if (Test-Path -LiteralPath $hedef) { $duran++; continue }
        $yeni++
        if ($KuruCalisma) { continue }
        $hd = Split-Path $hedef -Parent
        if (-not (Test-Path -LiteralPath $hd)) { New-Item -ItemType Directory -Force -Path $hd | Out-Null }
        Copy-Item -LiteralPath $f.FullName -Destination $hedef -Force

        # TAZE KIMLIK + TAZE TARIH (2026-09-11).
        #
        # Sablon dosyalari kendi Brain not kimliklerini (brn_...) tasiyor.
        # Duz kopyalama, AYNI KIMLIGI vault'ta iki yere koyuyordu: bir kez
        # kurulum/iskelet altinda, bir kez gercek yerinde. brain-cli bunu
        # dogru sekilde hata sayiyor ("duplicates Brain note id") - temiz
        # kurulum testinde nokta atisi 9 cakisma cikti.
        #
        # Bir sablon icerigini verir, KIMLIGINI vermez. Kopyaya yeni bir
        # kimlik ve gercek bir tarih yaziliyor; boylece kurulan not kendi
        # yasam dongusune sahip oluyor.
        if ($hedef -like '*.md') {
            try {
                $ham = [System.IO.File]::ReadAllText($hedef)
                $yeniId = 'brn_' + [guid]::NewGuid().ToString()
                $simdi = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ', [Globalization.CultureInfo]::InvariantCulture)
                $ham = [regex]::Replace($ham, '(?m)^id:\s*"brn_[^"]*"', "id: `"$yeniId`"")
                $ham = [regex]::Replace($ham, '(?m)^created:\s*"[^"]*"', "created: `"$simdi`"")
                $ham = [regex]::Replace($ham, '(?m)^updated:\s*"[^"]*"', "updated: `"$simdi`"")
                # Atomik (2026-09-16): yarim yazim iskeletle AYNI brn_ kimligi birakirdi
                # (brain-cli 'duplicates Brain note id'). Kodlama ayni: UTF-8, BOM'suz.
                Yaz-Dosya $hedef $ham
            } catch { }
        }
    }
    Adim 'baslangic dosyalari' $(if ($yeni) { 'kuruldu' } else { 'zaten' }) `
        "$yeni yeni, $duran zaten vardi (var olan dosyalara DOKUNULMAZ)"
} else {
    Adim 'baslangic dosyalari' 'atlandi' 'kurulum\iskelet yok'
}

# Surum damgasi
$surumDosya = Join-Path $Vault '.beyin-version'
# Surum YALNIZ KAYNAK vault'un .beyin-version dosyasindan okunur (kurulum\ bir alt
# klasor). GOMULU SABIT ARTIK YOK (denetim 2026-09-17). NEDEN: burada bir yedek
# sabit duruyordu ve HER surum yukseltmesinde bayatladi - once 2.1.2 yazip 2.1.3
# kurdu (olculdu), sonra 2.3'te yine 2.2.0 kaldi. Bayat sabit SESSIZCE yanlis
# damga basar: 'beyin nerede' eski surumu soyler, doktor 'surum tutarliligi'
# yanlis alarm verir, 'beyin yayinla' commit mesaji eski kalir ve surume bagli
# kontroller (doktor 'not guncelligi') kendilerini sessizce kapatir.
# Artik TAHMIN EDILMEZ: kaynak okunamazsa damgaya DOKUNULMAZ ve adim HATA olarak
# yuksek sesle raporlanir. Boylece surum yukseltme kontrol listesinde bu dosya
# yoktur - guncellenecek bir sabit kalmadi.
$kaynakSurum = ''; $kaynakSurumOkundu = $false
try { $ks = (Get-Content -LiteralPath (Join-Path (Split-Path $PSScriptRoot -Parent) '.beyin-version') -Raw -ErrorAction Stop).Trim(); if ($ks -match '^\d+\.\d+\.\d+$') { $kaynakSurum = $ks; $kaynakSurumOkundu = $true } } catch { }
if (-not $kaynakSurumOkundu) {
    $mevcutSurum = ''
    try { $mevcutSurum = (Get-Content -LiteralPath $surumDosya -Raw -ErrorAction Stop).Trim() } catch { }
    Adim 'surum damgasi' 'HATA' "kaynak .beyin-version okunamadi - damgaya DOKUNULMADI (mevcut: $(if ($mevcutSurum) { $mevcutSurum } else { 'yok' }))"
    Uyar 'Kaynak .beyin-version okunamadi: motor surumu damgalanamadi. Depo eksik ya da bozuk olabilir. Duzeltilene kadar "beyin nerede", doktor "surum tutarliligi" ve surume bagli kontroller yaniltir.'
} elseif (-not (Test-Path -LiteralPath $surumDosya)) {
    Yaz-Dosya $surumDosya "$kaynakSurum`n"
    Adim 'surum damgasi' 'kuruldu' $kaynakSurum
} else {
    # DAMGA MOTOR-SAHIPLIDIR (2026-09-16). NEDEN: ayri vault'a yeniden kurulumda
    # motor dosyalari her kosuda uzerine yaziliyor ama damga ilk surumde
    # kaliyordu (2.2.0 klonuyla kurulan vault 2.3.0 klonuyla yenilenince: motor
    # yeni, damga 'zaten 2.2.0'; 'beyin nerede' eski surumu soyler, doktor
    # 'surum tutarliligi' yanlis alarm verir, yayinla commit mesaji eski kalir).
    # Kaynak surum DAHA YENIYSE damga guncellenir. Buraya yalniz kaynak surum
    # GERCEKTEN OKUNDUYSA gelinir (yukaridaki HATA dali okunamayan durumu alir),
    # yani karsilastirma hicbir zaman bir tahminle yapilmaz.
    $mevcutSurum = ''
    try { $mevcutSurum = (Get-Content -LiteralPath $surumDosya -Raw -ErrorAction Stop).Trim() } catch { }
    $yeniMi = $false
    if ($mevcutSurum -ne $kaynakSurum) {
        try { $yeniMi = ([version]$kaynakSurum) -gt ([version]$mevcutSurum) }
        catch { $yeniMi = $true }   # mevcut deger bozuk/bos: kaynakla duzelt
    }
    if ($yeniMi) {
        Yaz-Dosya $surumDosya "$kaynakSurum`n"
        Adim 'surum damgasi' 'kuruldu' "$mevcutSurum -> $kaynakSurum"
    } elseif ($mevcutSurum -eq $kaynakSurum) {
        Adim 'surum damgasi' 'zaten' $mevcutSurum
    } else {
        Adim 'surum damgasi' 'zaten' "$mevcutSurum (kaynak $kaynakSurum daha yeni degil - dokunulmadi)"
    }
}

# ===========================================================================
# 2) ~\.beyin  -  vault kaydi + dagitici
# ===========================================================================
# --- Ev dizini yollari (dogrulama bolumu bunlara bakar) ---
$beyinKok    = Join-Path $env:USERPROFILE '.beyin'
$vaultKayit  = Join-Path $beyinKok 'vault.txt'
$launcherYol = Join-Path $env:USERPROFILE '.beyin\beyin-launcher.ps1'          # gercek (ajan-tarafsiz)
$simYol      = Join-Path $env:USERPROFILE '.claude\hooks\beyin-launcher.ps1'  # Codex simi (hooks.json buraya bakar)
$claudeAyar  = Join-Path $env:USERPROFILE '.claude\settings.json'
$codexAyar   = Join-Path $env:USERPROFILE '.codex\hooks.json'

if ($YalnizVault) {
    Write-Host ''
    Write-Host 'YALNIZ VAULT modu: ev dizinine dokunulmuyor.' -ForegroundColor Yellow
    Write-Host '  atlandi   tasinabilir giris noktasi (~\.beyin)' -ForegroundColor DarkGray
    Write-Host '  atlandi   kanca ayarlari (Claude + Codex)' -ForegroundColor DarkGray
    Write-Host '  atlandi   skill aynalari' -ForegroundColor DarkGray
}
else {
Write-Host ''
Write-Host '2) Tasinabilir giris noktasi' -ForegroundColor Cyan

$beyinKok = Join-Path $env:USERPROFILE '.beyin'
if (-not (Test-Path -LiteralPath $beyinKok) -and -not $KuruCalisma) {
    New-Item -ItemType Directory -Force -Path $beyinKok | Out-Null
}

$vaultKayit = Join-Path $beyinKok 'vault.txt'
$mevcutKayit = if (Test-Path -LiteralPath $vaultKayit) { (Get-Content -LiteralPath $vaultKayit -Raw -Encoding UTF8).Trim() } else { '' }
if ($mevcutKayit -eq $Vault) {
    Adim 'vault.txt' 'zaten' $Vault
} else {
    Yaz-Dosya $vaultKayit "$Vault`n"
    Adim 'vault.txt' 'kuruldu' $(if ($mevcutKayit) { "$mevcutKayit -> $Vault" } else { $Vault })
}

foreach ($d in @(@{ K = 'beyin.ps1'; H = (Join-Path $beyinKok 'beyin.ps1') },
                 @{ K = 'beyin-launcher.ps1';     H = (Join-Path $beyinKok 'beyin-launcher.ps1') },
                 @{ K = 'beyin-launcher-sim.ps1'; H = (Join-Path $env:USERPROFILE '.claude\hooks\beyin-launcher.ps1') })) {
    $kaynak = Join-Path $PSScriptRoot $d.K
    if (-not (Test-Path -LiteralPath $kaynak)) { Adim $d.K 'HATA' "kaynak yok: $kaynak"; continue }
    $ayni = $false
    if (Test-Path -LiteralPath $d.H) {
        $ayni = (Get-FileHash -LiteralPath $kaynak).Hash -eq (Get-FileHash -LiteralPath $d.H).Hash
    }
    if ($ayni) { Adim $d.K 'zaten' 'icerik ayni' }
    else {
        $y = Yedekle $d.H
        if (-not $KuruCalisma) {
            $hd = Split-Path $d.H -Parent
            if (-not (Test-Path -LiteralPath $hd)) { New-Item -ItemType Directory -Force -Path $hd | Out-Null }
            Kopyala-Atomik $kaynak $d.H   # atomik: iki ajanin her kancasinin calistirdigi canli dosya (bkz. Yaz-Bayt)
        }
        Adim $d.K 'kuruldu' $(if ($y) { 'eski surum yedeklendi' } else { 'yeni' })
    }
}

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

function Test-BeyinPathGirdisi {
    # Kullanici PATH'inde bu kok GERCEKTEN duruyor mu? Karsilastirma
    # GENISLETILMIS yol uzerinden: girdi '%USERPROFILE%\.beyin' bicimiyle
    # yazilir, duz metin karsilastirmasi onu kacirirdi.
    param([string]$Kok)
    try {
        $r = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment')
        if (-not $r) { return $false }
        try {
            $h = [string]$r.GetValue('Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
            foreach ($x in @($h -split ';' | Where-Object { $_ -ne '' })) {
                if ([string]::Equals([Environment]::ExpandEnvironmentVariables($x).TrimEnd('\'), $Kok.TrimEnd('\'), [StringComparison]::OrdinalIgnoreCase)) { return $true }
            }
        } finally { $r.Close() }
    } catch { }
    return $false
}

# --- 'beyin' komutu: .cmd sarmalayici + kullanici PATH'i ---
#
# NEDEN: motorun tek giris noktasi bir .ps1 dosyasi. Onu her seferinde
#   powershell -NoProfile -ExecutionPolicy Bypass -File "%USERPROFILE%\.beyin\beyin.ps1" durum
# diye yazmak hem uzun hem de belgelerdeki kisa ornekle ('beyin durum')
# uyusmuyordu. .cmd sarmalayici hem cmd hem PowerShell hem de Git Bash
# icinden calisir; PATH girdisi de onu her yerden gorunur yapar.
#
# PATH REG_EXPAND_SZ TUZAGI: [Environment]::SetEnvironmentVariable(...,'User')
# degeri REG_SZ olarak yeniden yazar. Kullanicinin PATH'inde '%JAVA_HOME%\bin'
# gibi bir girdi varsa o girdi genisletilmis haliyle DONAR ve degisken sonradan
# degisince bozulur. Bu yuzden kayit defterine dogrudan, DEGER TURU KORUNARAK
# yazilir.
$cmdYol = Join-Path $beyinKok 'beyin.cmd'
$cmdIcerik = @'
@echo off
REM beyin - ikinci beyin dagiticisi. Kaynak: <vault>\kurulum\beyin.ps1
REM Bu sarmalayici kur.ps1 tarafindan uretilir; elle duzenleme.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0beyin.ps1" %*
'@
$cmdVar = (Test-Path -LiteralPath $cmdYol) -and `
          (((Get-Content -LiteralPath $cmdYol -Raw -ErrorAction SilentlyContinue) -replace "`r`n", "`n").Trim() -eq ($cmdIcerik -replace "`r`n", "`n").Trim())
if ($cmdVar) {
    Adim 'beyin.cmd' 'zaten' 'icerik ayni'
} else {
    if (-not $KuruCalisma) { Yaz-Dosya $cmdYol ($cmdIcerik + "`n") }
    Adim 'beyin.cmd' 'kuruldu' 'komut sarmalayicisi'
}

if ($PathAtla) {
    Adim 'PATH' 'atlandi' '-PathAtla verildi'
} else {
    try {
        $reg = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', $true)
        if (-not $reg) { throw 'HKCU\Environment acilamadi' }
        try {
            $tur = try { $reg.GetValueKind('Path') } catch { [Microsoft.Win32.RegistryValueKind]::ExpandString }
            $ham = [string]$reg.GetValue('Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
            # Karsilastirma GENISLETILMIS yol uzerinden yapilir: girdi zaten
            # '%USERPROFILE%\.beyin' olarak duruyorsa ikinci kez eklenmemeli.
            $parcalar = @($ham -split ';' | Where-Object { $_ -ne '' })
            $zaten = $false
            foreach ($x in $parcalar) {
                $g = [Environment]::ExpandEnvironmentVariables($x).TrimEnd('\')
                if ([string]::Equals($g, $beyinKok.TrimEnd('\'), [StringComparison]::OrdinalIgnoreCase)) { $zaten = $true; break }
            }
            if ($zaten) {
                Adim 'PATH' 'zaten' 'kullanici PATH''inde'
            } else {
                # '%USERPROFILE%' bicimi yazilir: profil yolu degisirse (ya da
                # ayni yapilandirma baska bir kullaniciya tasinirsa) girdi
                # kendiliginden dogru yeri gosterir.
                $yeniGirdi = '%USERPROFILE%\.beyin'
                $yeniPath = (@($parcalar) + @($yeniGirdi)) -join ';'
                $duyuruldu = $false
                if (-not $KuruCalisma) {
                    $reg.SetValue('Path', $yeniPath, $tur)
                    # Ayni surecte de hemen calissin (yeni pencere beklemeden):
                    $env:Path = $env:Path + ';' + $beyinKok
                    $duyuruldu = Duyur-OrtamDegisikligi
                }
                $pathNot = ''
                if (-not $KuruCalisma) {
                    if ($duyuruldu) {
                        $pathNot = ' (YENI terminalde gecerli)'
                    } else {
                        # Duyuru basarisizsa "yeni terminal ac" tarifi calismaz:
                        # Explorer'dan acilan her surec onbellekli eski ortami
                        # miras alir. Kullaniciya kesin cozumu soyle.
                        $pathNot = ' - ortam duyurusu basarisiz; acik pencereler eski PATH ile kalabilir, oturumu kapatip acmak kesin cozum'
                    }
                }
                Adim 'PATH' 'kuruldu' ($yeniGirdi + ' eklendi' + $pathNot)
            }
        } finally { $reg.Close() }
    } catch {
        # PATH yazilamamasi kurulumu bozmaz: tam yolla her sey calisir.
        Adim 'PATH' 'atlandi' "yazilamadi: $($_.Exception.Message)  (tam yolla calismaya devam eder)"
    }
}

# ===========================================================================
# 3) KANCA AYARLARI
# ===========================================================================
Write-Host ''
Write-Host '3) Kanca ayarlari' -ForegroundColor Cyan

$launcherYol = Join-Path $env:USERPROFILE '.beyin\beyin-launcher.ps1'          # gercek (ajan-tarafsiz)
$simYol      = Join-Path $env:USERPROFILE '.claude\hooks\beyin-launcher.ps1'  # Codex simi (hooks.json buraya bakar)
# CodexTimeout (2026-09-16): Codex, SessionEnd kancasina belgelenmis olarak en
# fazla 3 sn tanir (varsayilan 1; motor/hooks/session-end.ps1 ve SKILL.md ayni
# tavani soyler). Eski kurulum 15 yaziyordu: belge disi deger, ve dosya hash-donuk
# oldugu icin sonradan duzeltmek yeniden onay istiyordu. Yalniz YENI yazilan
# girdileri ve -CodexZorla ile yenilenenleri etkiler; var olan dosyaya dokunulmaz.
$KANCALAR = @(
    @{ Olay = 'SessionStart';     Hook = 'session-start';   Timeout = 15 },
    @{ Olay = 'UserPromptSubmit'; Hook = 'prompt-counter';  Timeout = 5  },
    @{ Olay = 'SessionEnd';       Hook = 'session-end';     Timeout = 15; CodexTimeout = 3 },
    @{ Olay = 'PreCompact';       Hook = 'pre-compact';     Timeout = 15 }
)
$CODEX_SESSIONEND_TAVAN = 3

function Kanca-Timeout($K, [string]$Ajan) {
    if ($Ajan -eq 'codex' -and $K.ContainsKey('CodexTimeout')) { return [int]$K.CodexTimeout }
    return [int]$K.Timeout
}

function Komut-Metni([string]$Hook, [string]$Ajan) {
    # Codex: SIM yolu (hooks.json hash'i bozulmasin). Claude: gercek launcher.
    $yol = if ($Ajan -eq 'codex') { $simYol } else { $launcherYol }
    $c = "powershell -NoProfile -ExecutionPolicy Bypass -File `"$yol`" -Hook $Hook"
    if ($Ajan -eq 'codex') { $c += ' -Agent codex' }
    return $c
}

function Birlestir-Kanca([string]$AyarYol, [string]$Ajan, [bool]$Yaz, [bool]$Yenile = $false) {
    # Var olan JSON'u KORUYARAK beyin girdilerini ekler. Baska kancalar
    # (ornek: herdr-agent-state) oldugu gibi kalir.
    #
    # $Yenile (yalniz -CodexZorla ile gelir): farkli komut/timeout ile kayitli
    # beyin girdilerini YERINDE beklenen bicime ceker. NEDEN (2026-09-16): eski
    # surum farkli girdiyi kosulsuz atliyordu ($farkli += ...; continue), $eklendi
    # 0 kaliyor ve dosya hic yazilmiyordu - '-CodexZorla' vaadi bostu (olculdu:
    # 'atlandi farkli girdiler var, dokunulmadi').
    $veri = $null
    if (Test-Path -LiteralPath $AyarYol) {
        try { $veri = Get-Content -LiteralPath $AyarYol -Raw -Encoding UTF8 | ConvertFrom-Json }
        catch { Adim "$Ajan ayari" 'HATA' 'JSON okunamadi - elle bak, DOKUNULMADI'; return @{ Degisti = $false; Yeni = 0; Yenilenen = 0; Farkli = 0; Hata = $true } }
    }
    if (-not $veri) { $veri = [pscustomobject]@{} }
    if (-not $veri.PSObject.Properties['hooks']) {
        $veri | Add-Member -NotePropertyName 'hooks' -NotePropertyValue ([pscustomobject]@{}) -Force
    }

    $eklendi = 0; $yenilenen = 0; $farkli = @()
    foreach ($k in $KANCALAR) {
        $beklenen = Komut-Metni $k.Hook $Ajan
        $zamanAsimi = Kanca-Timeout $k $Ajan
        $olay = $k.Olay

        $mevcutGiris = @()
        if ($veri.hooks.PSObject.Properties[$olay]) {
            foreach ($grup in @($veri.hooks.$olay)) {
                foreach ($h in @($grup.hooks)) {
                    if ($h.command -and $h.command -like '*beyin-launcher*') { $mevcutGiris += $h }
                }
            }
        }

        if ($mevcutGiris.Count -gt 0) {
            $eslesen = @($mevcutGiris | Where-Object { $_.command -eq $beklenen })
            if (-not $Yenile) {
                if ($eslesen.Count -gt 0) { continue }              # tipatip ayni: dokunma
                $farkli += "$olay (mevcut: $($mevcutGiris[0].command))"
                continue                                             # farkli: DOKUNMA
            }
            # -Yenile: komut ve timeout'u yerinde beklenene cek. Codex'te hash
            # bilerek bozulur; cagiran /hooks onayini soyler.
            foreach ($h in $mevcutGiris) {
                $degisti = $false
                if ($h.command -ne $beklenen) { $h.command = $beklenen; $degisti = $true }
                $mevcutTo = if ($h.PSObject.Properties['timeout']) { [string]$h.timeout } else { '' }
                if ($mevcutTo -ne [string]$zamanAsimi) {
                    if ($h.PSObject.Properties['timeout']) { $h.timeout = $zamanAsimi }
                    else { $h | Add-Member -NotePropertyName 'timeout' -NotePropertyValue $zamanAsimi -Force }
                    $degisti = $true
                }
                if ($degisti) { $yenilenen++ }
            }
            continue
        }

        # Yok: ekle
        $yeniHook = [pscustomobject]@{ type = 'command'; command = $beklenen; timeout = $zamanAsimi }
        if (-not $veri.hooks.PSObject.Properties[$olay]) {
            $veri.hooks | Add-Member -NotePropertyName $olay -NotePropertyValue @() -Force
        }
        $gruplar = @($veri.hooks.$olay)
        # GRUP SECIMI (2026-09-16). NEDEN: girdi korlemesine ILK gruba ekleniyordu;
        # o grubun matcher'i daraltilmissa (Claude Code SessionStart 'startup',
        # PreCompact 'manual' gibi) beyin kancasi resume/clear/compact'ta HIC
        # tetiklenmiyor, kur 'kuruldu' diyor, doktor girdiyi sayiyordu. Yalniz
        # matcher'i olmayan / bos / '*' olan gruba eklenir; yoksa kendi '*'
        # grubu acilir. Codex gruplarinda matcher yok -> davranis degismez.
        $genisGrup = $null
        foreach ($g in $gruplar) {
            if (-not $g.PSObject.Properties['hooks']) { continue }
            $m = if ($g.PSObject.Properties['matcher']) { [string]$g.matcher } else { '' }
            if ($m -eq '' -or $m -eq '*') { $genisGrup = $g; break }
        }
        if ($genisGrup) {
            $genisGrup.hooks = @($genisGrup.hooks) + $yeniHook
        } else {
            $gruplar = @($gruplar) + [pscustomobject]@{ matcher = '*'; hooks = @($yeniHook) }
        }
        $veri.hooks.$olay = $gruplar
        $eklendi++
    }

    if ($farkli.Count -gt 0) {
        Uyar "$Ajan : $($farkli.Count) kanca FARKLI bir komutla kayitli, DOKUNULMADI -> $($farkli -join '; ')"
    }

    if (($eklendi -gt 0 -or $yenilenen -gt 0) -and $Yaz -and -not $KuruCalisma) {
        Yedekle $AyarYol | Out-Null
        Yaz-Dosya $AyarYol (($veri | ConvertTo-Json -Depth 12) + "`n")
    }
    return @{ Degisti = ($eklendi -gt 0 -or $yenilenen -gt 0); Yeni = $eklendi; Yenilenen = $yenilenen; Farkli = $farkli.Count }
}

# --- Claude Code: guvenli, hash yok ---
$claudeAyar = Join-Path $env:USERPROFILE '.claude\settings.json'
# TEK SEFERLIK GOC (Faz 0.2): eski kurulumlar Claude'u da ~\.claude\hooks simine
# bagliyordu. Claude'un dosyasinda hash yok; girdileri gercek launcher'a cevir.
# CODEX ICIN ASLA YAPILMAZ.
try {
    if (Test-Path -LiteralPath $claudeAyar) {
        $ham = Get-Content -LiteralPath $claudeAyar -Raw -Encoding UTF8
        # .Replace (dize metodu, literal): JSON icinde her ters egik cizgi ikiye katlanir.
        # -replace kullanilamaz: .NET yer degistirme dizesi kacislari farkli yorumlar.
        $eskiSim = $simYol.Replace('\', '\\')
        $yeniGer = $launcherYol.Replace('\', '\\')
        if ($ham.Contains($eskiSim)) {
            if (-not $KuruCalisma) { Yedekle $claudeAyar | Out-Null; Yaz-Dosya $claudeAyar $ham.Replace($eskiSim, $yeniGer) }
            Adim 'Claude launcher yolu' 'kuruldu' 'sim -> gercek launcher (~\.beyin)'
        }
    }
} catch { Adim 'Claude launcher yolu' 'HATA' $_.Exception.Message }
$r = Birlestir-Kanca $claudeAyar 'claude' $true
# "AYRISTIRILAMADI" ILE "ZATEN YERINDE" AYNI CEVAP DEGILDIR (2026-09-18).
# Eskiden bozuk JSON'da Birlestir-Kanca sifirli bir sonuc donuyordu ve bu
# else dali "zaten - 4 girdi yerinde" basiyordu: SIFIR girdi birlestirilmisken.
if ($r.Hata) { Adim 'Claude kancalari' 'HATA' 'ayar dosyasi ayristirilamadi - kanca durumu BILINMIYOR' }
elseif ($r.Yeni -gt 0) { Adim 'Claude kancalari' 'kuruldu' "$($r.Yeni) girdi eklendi (var olanlar korundu)" }
elseif ($r.Farkli -gt 0) { Adim 'Claude kancalari' 'atlandi' "$($r.Farkli) girdi farkli - elle bak" }
else { Adim 'Claude kancalari' 'zaten' '4 girdi yerinde' }

# --- Codex: HASH GUVENI VAR, dikkatli ---
$codexAyar = Join-Path $env:USERPROFILE '.codex\hooks.json'
$codexVar = Test-Path -LiteralPath $codexAyar
$codexBeyinVar = $false
if ($codexVar) {
    try { $codexBeyinVar = (Get-Content -LiteralPath $codexAyar -Raw -Encoding UTF8) -like '*beyin-launcher*' } catch { }
}

if ($codexBeyinVar -and -not $CodexZorla) {
    # Zaten kurulu: HASH'I BOZMA. Yalnizca tipatip esleseler mi diye bak.
    $r2 = Birlestir-Kanca $codexAyar 'codex' $false
    if ($r2.Farkli -gt 0) {
        Adim 'Codex kancalari' 'atlandi' "girdiler farkli komutla kayitli - DOKUNULMADI (guven hash'i)"
        Uyar 'Codex kanca komutlari beklenen bicimden farkli. Isliyorsa dokunma. Yenilemenin TEK onayli yolu: kur.ps1 -CodexZorla (beyin girdilerini beklenen komut+timeout ile yeniden yazar), SONRASINDA Codex TUI''de /hooks ile YENIDEN onayla.'
    } elseif ($r2.Hata) {
        Adim 'Codex kancalari' 'HATA' 'hooks.json ayristirilamadi - kanca durumu BILINMIYOR (dosyaya dokunulmadi)'
    } else {
        Adim 'Codex kancalari' 'zaten' '4 girdi yerinde, hash''e dokunulmadi'
    }
} else {
    # -CodexZorla: hooks.json'u degistirmenin TEK onayli yolu. Farkli girdiler
    # yerinde yenilenir, eksikler eklenir; hash bilerek bozulur -> /hooks sart.
    $r2 = Birlestir-Kanca $codexAyar 'codex' $true $CodexZorla
    if ($r2.Yeni -gt 0 -or $r2.Yenilenen -gt 0) {
        # NEDEN (2026-09-16): Birlestir-Kanca kuru calismada da SAYAR ama yazmaz
        # (yazim kosulu '-not $KuruCalisma'). Eski metin '-KuruCalisma -CodexZorla'
        # ile 'yenilendi / guven hash'i bozuldu' diyordu: dosyaya dokunulmamis,
        # hash saglamken yanlis alarm. Kuru calismada gelecek zaman + 'yazilmadi'.
        if ($KuruCalisma) {
            Adim 'Codex kancalari' 'atlandi' "kuru calisma: $($r2.Yeni) girdi eklenecek, $($r2.Yenilenen) girdi yenilenecek - yazilmadi"
            if ($r2.Yenilenen -gt 0) { Uyar "kuru calisma: -CodexZorla $($r2.Yenilenen) Codex girdisini YENILEYECEK (guven hash'i bozulacak, /hooks ile yeniden onay gerekecek) - hicbir sey yazilmadi." }
        } else {
            Adim 'Codex kancalari' 'kuruldu' "$($r2.Yeni) girdi eklendi, $($r2.Yenilenen) girdi yenilendi"
            Uyar 'CODEX TUI''DE /hooks CALISTIR ve girdileri onayla. Onaylanmayan kanca SESSIZCE atlanir - hicbir hata vermez, sadece calismaz.'
            if ($r2.Yenilenen -gt 0) { Uyar "-CodexZorla ile $($r2.Yenilenen) Codex girdisi YENIDEN YAZILDI: guven hash'i bilerek bozuldu; /hooks ile yeniden onaylanana kadar o kancalar CALISMAZ." }
        }
    } elseif ($r2.Farkli -gt 0) {
        Adim 'Codex kancalari' 'atlandi' 'farkli girdiler var, dokunulmadi'
    } else {
        Adim 'Codex kancalari' 'zaten' "4 girdi yerinde$(if ($CodexZorla) { ' (-CodexZorla: yenilenecek fark yok, hash''e dokunulmadi)' })"
    }
}

# ===========================================================================
# 4) SKILL AYNALARI
# ===========================================================================
Write-Host ''
Write-Host '4) Skill aynalari' -ForegroundColor Cyan

# Claude proje skill'lerini yalnizca cwd'nin motor/skills'inden yukler; Codex
# motor/skills'i HIC taramaz. Tek kaynak vault'ta kalir, uc yere baglanir.
$skillKaynak = Join-Path $Vault 'motor\skills'
$skillHedefler = @(
    @{ Ad = 'Claude (kullanici)'; Yol = (Join-Path $env:USERPROFILE '.claude\skills') },
    @{ Ad = 'Codex (kullanici)';  Yol = (Join-Path $env:USERPROFILE '.codex\skills') },
    @{ Ad = 'Ortak (.agents)';    Yol = (Join-Path $env:USERPROFILE '.agents\skills') }
)
$skiller = @(Get-ChildItem -LiteralPath $skillKaynak -Directory -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
if ($skiller.Count -eq 0) { Adim 'skill kaynagi' 'atlandi' "$skillKaynak bos" }

foreach ($hk in $skillHedefler) {
    if (-not (Test-Path -LiteralPath $hk.Yol)) {
        if ($KuruCalisma) { continue }
        New-Item -ItemType Directory -Force -Path $hk.Yol | Out-Null
    }
    foreach ($s in $skiller) {
        $kaynak = Join-Path $skillKaynak $s
        $hedef  = Join-Path $hk.Yol $s
        if (Test-Path -LiteralPath $hedef) {
            $it = Get-Item -LiteralPath $hedef -Force
            $bagli = ($it.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0
            # HEDEF FARKLIYSA YENILE (2026-09-15): vault tasininca/yeniden adlandirilinca eski
            # junction'lar olu kaliyordu ve kur.ps1 'zaten baglanti' deyip geciyordu (olculdu).
            $eskiHedef = ''
            try { $eskiHedef = [string](@($it.Target) | Select-Object -First 1) } catch { }
            $ayni = $bagli -and $eskiHedef -and ($eskiHedef.TrimEnd('') -eq $kaynak.TrimEnd(''))
            if (-not $bagli -or $ayni -or $KuruCalisma) {
                Adim "$($hk.Ad)\$s" 'zaten' $(if (-not $bagli) { 'gercek klasor - dokunulmadi' } elseif ($ayni) { 'baglanti' } else { "baglanti ESKI hedefe bakiyor ($eskiHedef) - kuru calisma" })
                continue
            }
            # Junction'i kaldir (icerik degil, yalniz baglanti): cmd rmdir reparse point'i guvenle siler
            try { & cmd.exe /d /s /c "rmdir `"$hedef`"" | Out-Null } catch { }
            if (Test-Path -LiteralPath $hedef) { Adim "$($hk.Ad)\$s" 'HATA' "eski baglanti kaldirilamadi ($eskiHedef)"; continue }
            Adim "$($hk.Ad)\$s" 'yenilendi' "eski hedef: $eskiHedef"
        }
        if ($KuruCalisma) { Adim "$($hk.Ad)\$s" 'atlandi' 'kuru calisma'; continue }
        $tur = ''
        try { New-Item -ItemType Junction -Path $hedef -Target $kaynak -ErrorAction Stop | Out-Null; $tur = 'junction' }
        catch {
            try { New-Item -ItemType SymbolicLink -Path $hedef -Target $kaynak -ErrorAction Stop | Out-Null; $tur = 'symlink' }
            catch {
                try { Copy-Item -LiteralPath $kaynak -Destination $hedef -Recurse -Force -ErrorAction Stop; $tur = 'KOPYA'
                      Uyar "$($hk.Ad)\$s baglanti yerine KOPYA olarak kuruldu - motor guncellenince elle yenile." }
                catch { Adim "$($hk.Ad)\$s" 'HATA' $_.Exception.Message; continue }
            }
        }
        Adim "$($hk.Ad)\$s" 'kuruldu' $tur
    }
}


}

# ===========================================================================
# 4b) DOSYA IZINLERI  (yalniz -IzinleriSikilastir ile)
# ===========================================================================
Write-Host ''
Write-Host '4b) Dosya izinleri' -ForegroundColor Cyan
try {
    $acl = Get-Acl -LiteralPath $Vault -ErrorAction Stop
    $mirasVar = @($acl.Access | Where-Object { $_.IsInherited }).Count -gt 0
    $genis = @($acl.Access | Where-Object {
        $_.AccessControlType -eq 'Allow' -and
        ([string]$_.IdentityReference -match 'Everyone|Authenticated Users|BUILTIN\\Users|INTERACTIVE|Herkes') -and
        ([string]$_.FileSystemRights -match 'Write|Modify|FullControl|Delete')
    })

    if (-not $IzinleriSikilastir) {
        $durum = "miras $(if ($mirasVar) { 'ACIK' } else { 'kirilmis' }), $($acl.Access.Count) kural"
        if ($mirasVar -or $genis.Count) {
            Adim 'dosya izinleri' 'atlandi' "$durum - SIKILASTIRILMADI"
            Uyar "Vault izinleri gevsek ($durum). Vault kisisel notlar tasiyor. Sikilastirmak icin: kur.ps1 -IzinleriSikilastir"
        } else {
            Adim 'dosya izinleri' 'zaten' "$durum (iyi)"
        }
    } else {
        # Kanonik politika: miras kir, tam yetki yalniz sahibi + SYSTEM +
        # Administrators. Diger her sey kaldirilir.
        #
        # icacls KULLANILIYOR, Set-Acl DEGIL: icacls miras kirmayi ve toplu
        # yeniden uygulamayi tek adimda, guvenilir sekilde yapar.
        $sahip = $acl.Owner
        # SID'LER, UI ADLARI DEGIL (2026-09-16). 'Administrators'/'SYSTEM' Ingilizce
        # UI adlaridir; yerellestirilmis Windows'ta (de: Administratoren, fr:
        # Administrateurs) icacls adi cozemez, 1332 'No mapping between account
        # names and security IDs' verir ve TUM grant komutu 0 dosya isler. Iyi
        # bilinen SID'ler her dilde aynidir: S-1-5-32-544 Administrators,
        # S-1-5-18 SYSTEM. Sahip de SID olarak verilir (ad cozumune bagimlilik yok).
        $sahipSid = ''
        try { $sahipSid = $acl.GetOwner([System.Security.Principal.SecurityIdentifier]).Value } catch { }
        if ($KuruCalisma) {
            Adim 'dosya izinleri' 'atlandi' "kuru calisma (sikilastirilacakti: sahip=$sahip)"
        } elseif (-not $sahipSid) {
            Adim 'dosya izinleri' 'HATA' "sahip SID'i cozulemedi ($sahip) - HICBIR SEY DEGISTIRILMEDI"
        } else {
            # SIRA ONEMLI: ONCE GRANT, SONRA MIRAS KIR. Eski sira (once
            # /inheritance:r, sonra grant) grant basarisiz olunca DACL'i BOS
            # birakiyordu: sahip dahil kimse okuyamiyor, iki ajanin kancalari
            # sessizce (exit 0) duruyor, Obsidian vault'u acamiyordu - gecici
            # dizinde olculdu (exit 1332, 'processed 0 files', ACE sayisi 0 ve
            # eski $ok kontrolu bos DACL'i 'kuruldu' sayiyordu). Grant tutmazsa
            # mirasa dokunulmaz ve HATA verilir.
            $g = Icacls-Kos @($Vault, '/grant:r', "*${sahipSid}:(OI)(CI)F", '*S-1-5-18:(OI)(CI)F', '*S-1-5-32-544:(OI)(CI)F')
            $r2 = $g.Cikti
            if ($g.Kod -ne 0) {
                Adim 'dosya izinleri' 'HATA' "grant basarisiz (icacls cikis $($g.Kod)) - miras KIRILMADI, hicbir sey degismedi"
                Uyar "Izin sikilastirma uygulanmadi. icacls ciktisi: $($r2.Trim())"
            } else {
            # /inheritance:r  mirasi kirar ve devralinan kurallari KOPYALAMAZ.
            # Yukaridaki acik ACE'ler yerinde kalir.
            $m1 = Icacls-Kos @($Vault, '/inheritance:r')
            $r1 = $m1.Cikti
            $mirasKirildi = ($m1.Kod -eq 0)

            # CODEX SANDBOX GRUBU: SALT-OKUMA.
            #
            # Kanonik politikanin parcasi ve ORTAK BEYIN TASARIMININ GEREGI:
            # Codex sandbox'i vault'u okuyabilmeli, yoksa Codex tarafinda
            # hafiza calismaz. Ama YAZAMAMALI - yazma yolu yalniz motorun
            # kendisinden gecer.
            #
            # Grup yoksa (Codex sandbox kurulu degil) sessizce atlanir; o
            # makinede zaten okuyacak kimse yok.
            $sandboxGrubu = $null
            foreach ($aday in @("$env:COMPUTERNAME\CodexSandboxUsers", 'CodexSandboxUsers')) {
                $c = Icacls-Kos @($Vault, '/grant:r', "${aday}:(OI)(CI)(RX)")
                if ($c.Kod -eq 0) { $sandboxGrubu = $aday; break }
            }
            $r3 = if ($sandboxGrubu) { "sandbox salt-okuma: $sandboxGrubu" } else { 'sandbox grubu yok (atlandi)' }
            $sonAcl = Get-Acl -LiteralPath $Vault
            $kalanGenis = @($sonAcl.Access | Where-Object {
                [string]$_.IdentityReference -match 'Everyone|Authenticated Users|BUILTIN\\Users|INTERACTIVE'
            }).Count
            # BOS DACL 'kuruldu' SAYILMASIN: sahibin acik FullControl ACE'si sart.
            $tamYetki = [int][System.Security.AccessControl.FileSystemRights]::FullControl
            $sahipAce = @($sonAcl.Access | Where-Object {
                $sid = ''
                try { $sid = $_.IdentityReference.Translate([System.Security.Principal.SecurityIdentifier]).Value } catch { }
                (-not $_.IsInherited) -and ($_.AccessControlType -eq 'Allow') -and ($sid -eq $sahipSid) -and
                    (([int]$_.FileSystemRights -band $tamYetki) -eq $tamYetki)
            }).Count
            $ok = $mirasKirildi -and (@($sonAcl.Access | Where-Object { $_.IsInherited }).Count -eq 0) -and ($kalanGenis -eq 0) -and ($sahipAce -gt 0)
            Adim 'dosya izinleri' $(if ($ok) { 'kuruldu' } else { 'HATA' }) `
                "miras kirildi, tam yetki: $sahip + SYSTEM + Administrators (SID ile) · $r3 ($($sonAcl.Access.Count) kural)"
            if (-not $ok) { Uyar "Izin sikilastirma tam uygulanamadi (sahip ACE: $sahipAce, miras kirildi: $mirasKirildi). Cikti: $($r1.Trim()) $($r2.Trim())  Geri almak icin: icacls `"$Vault`" /reset" }
            }
        }
    }
} catch {
    Adim 'dosya izinleri' 'atlandi' "ACL okunamadi: $($_.Exception.Message)"
}

# ===========================================================================
# 5) DOGRULAMA
# ===========================================================================
Write-Host ''
Write-Host '5) Dogrulama' -ForegroundColor Cyan

$kontroller = @(
    @{ Ad = 'vault';            Ok = (Test-Path -LiteralPath $Vault) },
    @{ Ad = 'vault.txt';        Ok = (Test-Path -LiteralPath $vaultKayit) },
    @{ Ad = 'beyin.ps1';        Ok = (Test-Path -LiteralPath (Join-Path $beyinKok 'beyin.ps1')) },
    # NEDEN GERI OKUMA (inceleme 2026-09-17): eski hali 'beyin.cmd var mi'
    # diye soruyordu. O dosya PATH yazimi FIRLATSA BILE yaziliyor, yani
    # kurulumun oz-denetimi kendi hata modunu goremiyordu. Artik kaynak
    # kayit defteri: girdi gercekten orada mi?
    @{ Ad = 'beyin komutu';     Ok = ($PathAtla -or $KuruCalisma -or (Test-BeyinPathGirdisi -Kok $beyinKok)) },
    @{ Ad = 'launcher';         Ok = (Test-Path -LiteralPath $launcherYol) },
    @{ Ad = 'Codex simi';       Ok = (Test-Path -LiteralPath $simYol) },
    @{ Ad = 'kanca betikleri';  Ok = (@(Get-ChildItem (Join-Path $Vault 'motor\hooks') -Filter '*.ps1' -File -ErrorAction SilentlyContinue).Count -ge 5) },
    @{ Ad = 'motor betikleri';  Ok = (@(Get-ChildItem (Join-Path $Vault 'motor\scripts') -Filter '*.ps1' -File -ErrorAction SilentlyContinue).Count -ge 5) },
    # AYRISTIRILABILIR OLMALI, sadece metin icermesi YETMEZ (2026-09-18):
    # sondaki virgullu bozuk bir JSON da '*beyin-launcher*' alt dizgisini
    # tasir - ajan o dosyayi okuyamazken kurulum "OK" basiyordu.
    @{ Ad = 'Claude ayari';     Ok = (Test-KancaAyariGecerli -Yol $claudeAyar) },
    @{ Ad = 'Codex ayari';      Ok = (Test-KancaAyariGecerli -Yol $codexAyar) }
)
# YalnizVault: ev dizini kurulmadi, o satirlari denetleme - yoksa mod her
# zaman "eksik" raporlar ve dogru calistiginda bile basarisiz gorunur.
if ($YalnizVault) {
    $kontroller = @($kontroller | Where-Object { $_.Ad -notin @('vault.txt', 'beyin.ps1', 'beyin komutu', 'launcher', 'Claude ayari', 'Codex ayari') })
}
$kotu = 0
# HATA ADIMLARI SONUCA GIRER (2026-09-18): eskiden `Adim ... 'HATA'` yalniz
# $ilerleme listesine yaziliyordu ve $kotu'yu hic beslemiyordu - yani surum
# damgasi yazilamamis, kaynak dosya eksik ya da ayar dosyasi ayristirilamamis
# bir kurulum yine 'KURULUM TAMAM' + exit 0 veriyordu.
$hataAdimlari = @($ilerleme | Where-Object { $_.Sonuc -eq 'HATA' })
if ($hataAdimlari.Count -gt 0) { $kotu += $hataAdimlari.Count }
foreach ($k in $kontroller) {
    if (-not $k.Ok) { $kotu++ }
    Write-Host ("  {0,-6} {1}" -f $(if ($k.Ok) { 'OK' } else { 'EKSIK' }), $k.Ad) -ForegroundColor $(if ($k.Ok) { 'Green' } else { 'Red' })
}

# Codex SessionEnd timeout raporu - SALT RAPOR, dosyaya dokunulmaz (hash).
# NEDEN (2026-09-16): eski kurulum 15 yaziyordu, Codex tavani 3. Asan deger
# belgelenmemis davranistir; en kotu durumda kanca 1 sn'de olur ve Codex
# oturumlari yalniz 72 saatlik yetim tarayiciyla hafizaya girer. Kirmizi
# sayilmaz (calisan kurulumu bozmasin), ama caresiyle birlikte gosterilir.
if (-not $YalnizVault -and (Test-Path -LiteralPath $codexAyar)) {
    try {
        $cj = Get-Content -LiteralPath $codexAyar -Raw -Encoding UTF8 | ConvertFrom-Json
        $seTo = @()
        if ($cj -and $cj.PSObject.Properties['hooks'] -and $cj.hooks.PSObject.Properties['SessionEnd']) {
            foreach ($grup in @($cj.hooks.SessionEnd)) {
                foreach ($h in @($grup.hooks)) {
                    if ($h.command -like '*beyin-launcher*' -and $h.PSObject.Properties['timeout']) { $seTo += [int]$h.timeout }
                }
            }
        }
        $asan = @($seTo | Where-Object { $_ -gt $CODEX_SESSIONEND_TAVAN })
        if ($asan.Count -gt 0) {
            Write-Host ("  {0,-6} Codex SessionEnd timeout {1} > {2} (tavan)" -f 'UYARI', ($asan -join ','), $CODEX_SESSIONEND_TAVAN) -ForegroundColor Yellow
            Uyar "Codex SessionEnd timeout $($asan -join ',') sn; belgelenmis tavan $CODEX_SESSIONEND_TAVAN. Dosyaya dokunulmadi (hash). Duzeltmek icin: kur.ps1 -CodexZorla, sonra Codex TUI'de /hooks ile yeniden onayla."
        } elseif ($seTo.Count -gt 0) {
            Write-Host ("  {0,-6} Codex SessionEnd timeout {1} <= {2}" -f 'OK', ($seTo -join ','), $CODEX_SESSIONEND_TAVAN) -ForegroundColor Green
        }
    } catch { }
}

# Canli kanca denemesi (yalniz gercek kurulumda)
if (-not $KuruCalisma -and -not $YalnizVault -and (Test-Path -LiteralPath $launcherYol)) {
    try {
        $payload = '{"hook_event_name":"SessionStart","session_id":"kurulum-testi","cwd":"' +
                   ($Vault -replace '\\', '\\\\') + '","source":"startup","transcript_path":""}'
        $cikti = $payload | & powershell -NoProfile -ExecutionPolicy Bypass -File $launcherYol -Hook session-start 2>&1 | Out-String
        $ok = $cikti -like '*additionalContext*'
        Write-Host ("  {0,-6} canli kanca denemesi  ({1} karakter baglam)" -f $(if ($ok) { 'OK' } else { 'EKSIK' }), $cikti.Length) `
            -ForegroundColor $(if ($ok) { 'Green' } else { 'Red' })
        if (-not $ok) { $kotu++ }
    } catch { Write-Host "  EKSIK  canli kanca denemesi - $($_.Exception.Message)" -ForegroundColor Red; $kotu++ }
}

# ===========================================================================
# SONUC
# ===========================================================================
Write-Host ''
if ($KuruCalisma) {
    Write-Host 'KURU CALISMA bitti - hicbir sey yazilmadi.' -ForegroundColor Yellow
    Write-Host 'Gercekten kurmak icin -KuruCalisma olmadan calistir.' -ForegroundColor Yellow
} elseif ($kotu -eq 0) {
    Write-Host 'KURULUM TAMAM.' -ForegroundColor Green
} else {
    Write-Host "KURULUM BITTI - $kotu eksik var (yukariya bak)." -ForegroundColor Yellow
}

if ($uyarilar.Count -gt 0) {
    Write-Host ''
    Write-Host 'DIKKAT:' -ForegroundColor Yellow
    foreach ($u in $uyarilar) { Write-Host "  - $u" -ForegroundColor Yellow }
}

Write-Host ''
if ($YalnizVault) {
    Write-Host 'Bu vault hazir ama BU MAKINEYE BAGLANMADI.' -ForegroundColor Yellow
    Write-Host 'Baglamak icin -YalnizVault olmadan calistir.' -ForegroundColor Yellow
    Write-Host ''
    exit 0
}
if ($Zamanla) {
    Write-Host 'ZAMANLAYICI' -ForegroundColor Cyan
    try {
        $zy = Join-Path $PSScriptRoot 'zamanla.ps1'
        if ($KuruCalisma) { & $zy -Vault $Vault -KuruCalisma } else { & $zy -Vault $Vault }
    } catch { Write-Host "  zamanlayici HATA: $($_.Exception.Message)" -ForegroundColor Red }
    Write-Host ''
}
Write-Host 'SONRAKI ADIMLAR' -ForegroundColor Cyan
Write-Host '  1. Codex TUI''de  /hooks  calistir ve beyin girdilerini onayla (Trusted olmali).'
Write-Host '  2. Codex oturumlarini  /exit  ile kapat (pencere kapatinca SessionEnd atesmez).'
Write-Host '  3. YENI bir terminal ac (PATH girdisi ancak yeni pencerede gecerli olur).'
Write-Host '  4. Durum kontrolu:'
Write-Host '     beyin durum' -ForegroundColor White
Write-Host '     (komut bulunamazsa tam yolla:)' -ForegroundColor DarkGray
Write-Host "     powershell -NoProfile -ExecutionPolicy Bypass -File `"$(Join-Path $beyinKok 'beyin.ps1')`" durum" -ForegroundColor DarkGray
Write-Host '  5. Kullanim kilavuzu: <vault>\kurulum\KILAVUZ.md' -ForegroundColor White
Write-Host ''

exit $(if ($KuruCalisma -or $kotu -eq 0) { 0 } else { 1 })
