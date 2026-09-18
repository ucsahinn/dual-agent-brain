# guncelle.ps1 - Motoru uzak depodan tazeler. KULLANICI NOTLARINA DOKUNMAZ.
#
# NEDEN: motor yayinla.ps1 ile GitHub'a cikiyordu ama karsi yon yoktu. Baska bir
# makineye kurmus kullanici yeni surumu elle indirip kopyalamak zorundaydi; elle
# kopyalama ya eksik kaliyor (kaldirilan betikler makinede kaliyor) ya da not
# klasorlerine tasiyor. Bu betik tek komutla motoru tazeler ve YALNIZ motor
# yuzeyine dokunur:
#   klasorler : motor\hooks, motor\scripts, motor\skills, kurulum, templates
#   kok dosya : AGENTS.md, CLAUDE.md, brain.config.json, .beyin-version,
#               LICENSE, CHANGELOG.md
# Bunlarin DISINDA kalan her sey (not klasorleri, .obsidian, .brain, .git ve
# her duzeydeki .state) hedef kumenin disindadir: okunmaz, yedeklenmez,
# yazilmaz, silinmez.
#
# NEDEN templates de hedef kumede: yayinla.ps1 $IZIN_KLASOR templates'i PAKETE
# koyuyor ama burada hedef kumede degildi. Sonuc: surumle gelen sablon
# duzeltmeleri kurulu bir vault'a HIC ulasmiyordu (tek yonlu olu yuzey).
#
# YEREL DUZENLEMEYE ACIK YUZEY: AGENTS.md, CLAUDE.md, brain.config.json ve
# templates\ altindaki her sey kullanicinin kendi makinesine gore duzenledigi
# dosyalardir (brain.config.json ayrica vault anayasasinin parcasi:
# preview-required). Bunlar yerel olarak DEGISTIRILMISSE guncelleme onlari
# ATLAR ve adiyla raporlar; uzerine yazmak icin -Zorla gerekir. Pakette yeni
# gelen ya da yerelde hic degismemis olan sessizce yazilir. .beyin-version bu
# korumanin DISINDADIR: o dosya motorun kendi surum damgasi, kullanici icerigi
# degil - korunursa surum karsilastirmasi kalici olarak yalan soyler.
#
# KAYNAK VAULT KORUMASI: bu vault yayinin KAYNAGI ise guncelleme ters yonde
# calisir ve gelistirmeyi ezer. Ayirt edici kesindir: yayinla.ps1 depo README'sini
# kurulum\DEPO-README.md kaynagindan alip depo KOKUNE README.md olarak yazar ve
# kurulum\DEPO-README.md'yi hedeften siler. Yani o dosya yalniz gelistirme
# vault'unda bulunur.
#
# Kullanim:
#   beyin guncelle                 guncelle (surum ayniysa hicbir sey yapmaz)
#   beyin guncelle -KuruCalisma    ne degisecegini goster, HICBIR SEY YAZMA
#   beyin guncelle -Zorla          surum ayni olsa da yap; kaynak vault korumasini as
#   beyin guncelle -GeriAl         en son GECERLI yedegi geri yukle, kur.ps1 kos
#   beyin guncelle -Json           makine okunur cikti
#
# Yedek: motor\scripts\.state\guncelleme-yedek\<yyyyMMdd-HHmmss>\ (en yeni 3 tutulur)
# Her yedek klasoru, yedekleme dongusu TAMAMEN bittikten sonra yazilan bir
# TAMAM.txt tamamlanma isareti tasir (dosya sayisi + tam goreli yol listesi).
# Isareti olmayan ya da listesi diskle uyusmayan klasor GECERLI YEDEK SAYILMAZ
# ve -GeriAl tarafindan kullanilmaz. Bkz. Test-YedekGecerli.

param(
    [string]$Vault = '',
    # Bos birakilirsa BEYIN_DEPO ayarindan cozulur (lib.ps1 yuklendikten
    # SONRA; param varsayilaninda cagrilamaz, lib o an henuz yok).
    [string]$Depo  = '',
    [string]$Dal   = 'main',
    [switch]$KuruCalisma,
    [switch]$Zorla,
    [switch]$Json,
    [switch]$GeriAl
)

# NEDEN 'Stop': bu betik YAZAR. Sessizce yutulan bir kopyalama hatasi yarim
# kurulum birakir; yarim kurulum motorun tumunu bozar. Riskli bolge try/catch
# ile sarili ve hata halinde yedek geri yuklenir.
$ErrorActionPreference = 'Stop'

# --- Vault cozumu (kurulum\beyin.ps1 icindeki Get-BeyinVaultYolu ile ayni) ---
function Get-BeyinVaultYolu {
    if ($env:BEYIN_VAULT) { return $env:BEYIN_VAULT }
    $kayit = Join-Path $env:USERPROFILE '.beyin\vault.txt'
    if (Test-Path -LiteralPath $kayit) {
        try {
            $y = (Get-Content -LiteralPath $kayit -Raw -Encoding UTF8).Trim()
            if ($y) { return $y }
        } catch { }
    }
    return (Join-Path $env:USERPROFILE 'Documents\Beyin')
}
if (-not $Vault) { $Vault = Get-BeyinVaultYolu }

$vaultOk = $false
try { $vaultOk = [bool]($Vault -and (Test-Path -LiteralPath $Vault -PathType Container) -and (Test-Path -LiteralPath (Join-Path $Vault 'motor\hooks\lib.ps1') -PathType Leaf)) } catch { }
if (-not $vaultOk) { Write-Output "HATA: vault degil (motor\hooks\lib.ps1 yok): '$Vault'  - dogru yol icin -Vault <yol>"; exit 2 }
. (Join-Path $Vault 'motor\hooks\lib.ps1')
$p = Get-BeyinPaths -Vault $Vault
$inv = [Globalization.CultureInfo]::InvariantCulture
$Vault = [IO.Path]::GetFullPath($Vault).TrimEnd('\')

# ===========================================================================
# HEDEF KUME - izin verilenler listesi (yayinla.ps1 ile ayni yuzey)
# ===========================================================================
# Depo adresi: parametre > BEYIN_DEPO ayari > varsayilan. Motoru fork eden
# biri kendi deposunu gosterebilmeli; sabit gomulu adres onu bizim depomuza
# mahkum ediyordu (inceleme 2026-09-17).
if (-not $Depo) {
    # Varsayilan TEK yerde (lib.ps1 ayar envanteri). Eskiden burada, doktorda
    # ve envanterde olmak uzere UC kopyaydi - BEYIN_FLUSH_BUTCE ayni sekilde
    # kacmis ve 'beyin ayar' 80 derken motor 200 kullanmisti.
    $Depo = Get-BeyinAyar 'BEYIN_DEPO' (Get-BeyinAyarVars 'BEYIN_DEPO')
}
$Depo = ([string]$Depo).TrimEnd('/')
if ($Depo.EndsWith('.git', [StringComparison]::OrdinalIgnoreCase)) { $Depo = $Depo.Substring(0, $Depo.Length - 4) }

$HEDEF_DOSYA  = @('AGENTS.md', 'CLAUDE.md', 'brain.config.json', '.beyin-version',
                  # RELEASE (2026-09-17): kullanici `beyin guncelle` kostugunda
                  # degisiklik gunlugunu HIC gormuyordu - oysa guncellemeye
                  # guvenmesini saglayan sey tam olarak odur. LICENSE da surumle
                  # degisebilir ve kurulu kopyada eski kalmamali. Ikisi de
                  # $KORUMALI_DOSYA DEGIL: kullanici icerigi degil, upstream'in
                  # dosyalari - .beyin-version gibi kosulsuz yazilirlar.
                  'LICENSE', 'CHANGELOG.md')
$HEDEF_KLASOR = @('motor\hooks', 'motor\scripts', 'motor\skills', 'kurulum', 'templates')
# Izinli klasorlerin icinde bile ASLA dokunulmayacak yol parcalari
$ASLA = @('.state', '.git', '.brain', 'node_modules')

# Yerel duzenlemeye acik yuzey: yerelde DEGISMISSE uzerine yazilmaz (-Zorla ile
# yazilir) ve hicbir kosulda SILINMEZ. .beyin-version bilerek disarida.
$KORUMALI_DOSYA  = @('AGENTS.md', 'CLAUDE.md', 'brain.config.json')
$KORUMALI_KLASOR = @('templates')
# Kurtarma araclari: silinirlerse kullanicinin geri donus yolu kalmaz.
$KURTARMA_ARAC   = @('guncelle.ps1', 'kur.ps1', 'doktor.ps1')
# Yedek tamamlanma isareti (yedek klasorunun KOKUNDE; hedef kumede degil,
# bu yuzden Get-GoreliDosyalar onu gormez ve geri yuklemeye karismaz).
$YEDEK_ISARET    = 'TAMAM.txt'
$YEDEK_ISARET_V  = 'beyin-yedek/1'

$script:yerelSurum = 'bilinmiyor'
$script:uzakSurum  = ''
$script:gecici     = ''
$script:yedekKok   = ''
$script:makbuzYazildi = $false

# Kendi adi: uzak pakette guncelle.ps1 baska adla dururken kendini silmemek
# icin. Fonksiyonlardan once cozulur ki Test-Silinebilir her cagrida gorsun.
$script:kendiAd = ''
try { if ($PSCommandPath) { $script:kendiAd = (Split-Path -Leaf $PSCommandPath) } } catch { }

function Yaz { param([string]$S) if (-not $Json) { Write-Output $S } }

# Yerel surum HER cikista raporlanabilsin diye daha kaynak vault korumasindan
# once okunur (JSON tuketicisi hangi dalda durursa dursun surumu gorsun).
try {
    $sv0 = Join-Path $Vault '.beyin-version'
    if (Test-Path -LiteralPath $sv0 -PathType Leaf) {
        $t0 = (Get-Content -LiteralPath $sv0 -Raw -Encoding UTF8).Trim()
        if ($t0) { $script:yerelSurum = $t0 }
    }
} catch { }

function Test-VaultAlti {
    param([string]$Yol)
    try {
        $tam = [IO.Path]::GetFullPath($Yol)
        $kok = $Vault
        if (-not $kok.EndsWith('\')) { $kok = $kok + '\' }
        return $tam.StartsWith($kok, [StringComparison]::OrdinalIgnoreCase)
    } catch { return $false }
}

# NEDEN: Test-VaultAlti TAMAMEN METINSELDIR - yol dizesine bakar, diski
# cozmez. Hedef klasorlerden biri (ya da onun vault altindaki bir ust
# parcasi, ornegin motor) KENDISI bir junction/symlink ise numaralama
# vault DISINDAKI dosyalari dondurur, Test-VaultAlti yine True der ve o
# yabanci dosyalar yedeklenir, uzerine yazilir, pakette yoksa silinir.
# (Klasorun ICINE konan junction'a PS 5.1 Get-ChildItem -Recurse inmez;
# tehlikeli olan yon klasorun KENDISININ baglanti olmasi.) Cozmek yerine
# REDDEDIYORUZ: burada dogru davranisi tahmin etmek mumkun degil.
function Get-HedefBaglantilari {
    $bulunan = New-Object System.Collections.Generic.List[string]
    foreach ($k in $HEDEF_KLASOR) {
        $birikim = ''
        foreach ($par in @($k -split '[\\/]')) {
            if (-not $par) { continue }
            if ($birikim) { $birikim = $birikim + '\' + $par } else { $birikim = $par }
            $tam = Join-Path $Vault $birikim
            if (-not (Test-Path -LiteralPath $tam)) { break }
            try {
                $oge = Get-Item -LiteralPath $tam -Force -ErrorAction Stop
                if ($oge.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                    if (-not $bulunan.Contains($birikim)) { $bulunan.Add($birikim) }
                }
            } catch { }
        }
    }
    return ,$bulunan
}

function Remove-Gecici {
    if ($script:gecici -and (Test-Path -LiteralPath $script:gecici)) {
        try { Remove-Item -LiteralPath $script:gecici -Recurse -Force -ErrorAction SilentlyContinue } catch { }
    }
}

function Bitir {
    param(
        [string]$Outcome,
        [int]$Kod = 0,
        [string]$Not = '',
        [string[]]$Satir = @(),
        $Ek = $null
    )
    Remove-Gecici
    Write-BeyinMakbuz -Paths $p -Script 'guncelle' -Outcome $Outcome -Note $Not
    $script:makbuzYazildi = $true
    if ($Json) {
        $o = [ordered]@{
            sonuc      = $Outcome
            kod        = $Kod
            not        = $Not
            vault      = $Vault
            depo       = $Depo
            dal        = $Dal
            yerelSurum = $script:yerelSurum
            uzakSurum  = $script:uzakSurum
            zaman      = (Get-Date).ToString('o', $inv)
        }
        if ($Ek) { foreach ($k in @($Ek.Keys)) { $o[[string]$k] = $Ek[$k] } }
        ([pscustomobject]$o | ConvertTo-Json -Depth 6)
    } else {
        foreach ($s in $Satir) { Write-Output $s }
    }
    exit $Kod
}

# NEDEN trap: her cikis yolu Bitir'den gecmeli - Bitir gecici klasoru siler ve
# makbuzu yazar. Yakalanmamis bir terminating hata (ErrorActionPreference
# 'Stop' ile her hata terminating'dir) eskiden betigi oldugu yerde olduruyordu:
# gecici klasor diskte, makbuz hic yazilmamis, cagirana da yalniz ham hata
# metni. Bu son savunma; normal hatalar hala kendi try/catch'lerinde ele
# aliniyor ve trap'a hic ulasmiyor.
# DIKKAT: PowerShell trap'i KAPSAMA GIRISTE kaydeder, bu satira gelindiginde
# degil. Yani betigin ILK satirlarindaki bir hatada da atesler - o an Bitir
# henuz TANIMLI DEGILDIR (olculdu: kilitli lib.ps1 -> nokta-kaynak hatasi ->
# "The term 'Bitir' is not recognized"). Once varligini dogruluyoruz.
trap {
    if ($script:makbuzYazildi) { continue }
    $m = ''
    try { $m = [string]$_.Exception.Message } catch { $m = 'bilinmeyen hata' }
    $bitirVar = $false
    try { $bitirVar = [bool](Get-Command 'Bitir' -CommandType Function -ErrorAction SilentlyContinue) } catch { }
    if (-not $bitirVar) {
        if ($Json) {
            ([pscustomobject][ordered]@{
                sonuc = 'GUNCELLE_COKTU'; kod = 1; not = $m; vault = $Vault
            } | ConvertTo-Json -Depth 3)
        } else {
            Write-Output "GUNCELLE: BEKLENMEYEN HATA (hazirlik asamasi) - $m"
        }
        exit 1
    }
    Bitir -Outcome 'GUNCELLE_COKTU' -Kod 1 -Not $m -Satir @(
        'GUNCELLE: BEKLENMEYEN HATA - islem yarida kesildi.',
        "  $m",
        '  Motor yarim kalmis olabilir: beyin guncelle -GeriAl'
    )
}

# --- Hedef kumedeki goreli dosya yollari -----------------------------------
function Test-Yasak {
    param([string]$Rel)
    foreach ($par in ($Rel -split '[\\/]')) {
        foreach ($y in $ASLA) {
            if ([string]::Equals($par, $y, [StringComparison]::OrdinalIgnoreCase)) { return $true }
        }
    }
    return $false
}

# Yerel duzenlemeye acik mi? (ustteki YEREL DUZENLEMEYE ACIK YUZEY notu)
function Test-Korumali {
    param([string]$Rel)
    foreach ($d in $KORUMALI_DOSYA) {
        if ([string]::Equals($Rel, $d, [StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    $ilk = @($Rel -split '[\\/]')[0]
    foreach ($k in $KORUMALI_KLASOR) {
        if ([string]::Equals($ilk, $k, [StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return $false
}

# NEDEN tek fonksiyon: silme kurali iki yerde isliyor - guncelleme yolundaki
# $silinen listesi ve Restore-Yedek'in "yedekte olmayani sil" adimi. Ikisi ayri
# yazilmisti ve Restore-Yedek'inki uzanti ayrimi da kurtarma araci korumasi da
# tanimiyordu: yarim bir yedekle -GeriAl, guncelle.ps1/kur.ps1/doktor.ps1 dahil
# hedef kumenin tamamini siliyordu. Kural artik tek yerde.
function Test-Silinebilir {
    param([string]$Rel)
    if (-not $Rel.EndsWith('.ps1', [StringComparison]::OrdinalIgnoreCase)) { return $false }
    if (Test-Korumali $Rel) { return $false }
    $ad = Split-Path -Leaf $Rel
    foreach ($k in $KURTARMA_ARAC) {
        if ([string]::Equals($ad, $k, [StringComparison]::OrdinalIgnoreCase)) { return $false }
    }
    if ($script:kendiAd -and [string]::Equals($ad, $script:kendiAd, [StringComparison]::OrdinalIgnoreCase)) { return $false }
    return $true
}

function Get-GoreliDosyalar {
    param([string]$Kok)
    $liste = New-Object System.Collections.Generic.List[string]
    $kokTam = ''
    try { $kokTam = [IO.Path]::GetFullPath($Kok).TrimEnd('\') } catch { return ,$liste }
    foreach ($d in $HEDEF_DOSYA) {
        if (Test-Path -LiteralPath (Join-Path $kokTam $d) -PathType Leaf) { $liste.Add($d) }
    }
    foreach ($k in $HEDEF_KLASOR) {
        $tam = Join-Path $kokTam $k
        if (-not (Test-Path -LiteralPath $tam -PathType Container)) { continue }
        foreach ($f in @(Get-ChildItem -LiteralPath $tam -Recurse -File -Force -ErrorAction SilentlyContinue)) {
            $rel = $f.FullName.Substring($kokTam.Length).TrimStart('\')
            if (Test-Yasak $rel) { continue }
            $liste.Add($rel)
        }
    }
    return ,$liste
}

function Get-DosyaHash {
    param([string]$Yol)
    try { return (Get-FileHash -LiteralPath $Yol -Algorithm SHA256).Hash } catch { return '' }
}

function New-Set {
    param([string[]]$Ogeler)
    $s = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($o in @($Ogeler)) { [void]$s.Add($o) }
    return ,$s
}

function Copy-Dosya {
    param([string]$Kaynak, [string]$Hedef)
    $dizin = Split-Path -Parent $Hedef
    if ($dizin -and -not (Test-Path -LiteralPath $dizin -PathType Container)) {
        New-Item -ItemType Directory -Force -Path $dizin | Out-Null
    }
    Copy-Item -LiteralPath $Kaynak -Destination $Hedef -Force
}

# --- Ag: once curl.exe, sonra Invoke-WebRequest (TLS 1.2 elle) -------------
# NEDEN WebClient YOK: `New-Object System.Net.WebClient` + gizli pencere
# kombinasyonunu bazi guvenlik urunleri kotucul bir kalip sayip engelliyor
# (olculdu: surec hic baslamadi). curl.exe Windows 10+ ile geliyor.
function Get-Uzak {
    param([string]$Url, [string]$Hedef)
    $curl = $null
    try { $curl = Get-Command 'curl.exe' -ErrorAction SilentlyContinue } catch { }
    if ($curl) {
        try {
            & $curl.Source '-fsSL' '-o' $Hedef $Url
            if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $Hedef -PathType Leaf)) { return $true }
        } catch { }
    }
    try {
        # PS 5.1 varsayilani TLS 1.0; GitHub reddeder.
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $Url -OutFile $Hedef -UseBasicParsing -ErrorAction Stop | Out-Null
        if (Test-Path -LiteralPath $Hedef -PathType Leaf) { return $true }
    } catch { }
    return $false
}

# --- Yedek tamamlanma isareti ----------------------------------------------
# NEDEN: yedek klasoru zaman damgasiyla olusturulup dosyalar TEK TEK
# kopyalaniyor. Kopyalama ortasinda surec olurse (Ctrl+C, disk dolmasi, AV
# kilidi, uyku) diskte YARIM ama en yeni tarihli bir klasor kalir. -GeriAl
# eskiden "en yeni klasor" diye dogrudan onu aliyor ve hedef kumeyi o yarim
# kopyaya esitliyordu; kotu niyet gerekmiyordu. Isaret dosyasi dongu TAMAMEN
# bittikten SONRA yaziliyor, yani varligi butunlugun kanitidir. Ctrl+C catch'e
# dusmedigi icin "hata halinde temizle" tek basina yetmez - isaret sarttir.
function Write-YedekIsaret {
    param([string]$YedekKok, $Dosyalar)
    $satir = New-Object System.Collections.Generic.List[string]
    $satir.Add($YEDEK_ISARET_V)
    $satir.Add('zaman=' + (Get-Date).ToString('o', $inv))
    $satir.Add('dosya=' + (@($Dosyalar).Count))
    foreach ($rel in @($Dosyalar)) { $satir.Add($rel) }
    Write-BeyinText -Path (Join-Path $YedekKok $YEDEK_ISARET) -Text (($satir -join "`r`n") + "`r`n")
}

# @{ ok = bool; not = 'neden gecersiz'; dosya = n }
function Test-YedekGecerli {
    param([string]$YedekKok)
    $isaret = Join-Path $YedekKok $YEDEK_ISARET
    if (-not (Test-Path -LiteralPath $isaret -PathType Leaf)) {
        return @{ ok = $false; not = "tamamlanma isareti yok ($YEDEK_ISARET)"; dosya = 0 }
    }
    $ham = ''
    try { $ham = (Get-Content -LiteralPath $isaret -Raw -Encoding UTF8) } catch {
        return @{ ok = $false; not = "isaret okunamadi: $($_.Exception.Message)"; dosya = 0 }
    }
    $satirlar = @(($ham -split "`r?`n") | Where-Object { $_ -ne '' })
    if ($satirlar.Count -lt 3) { return @{ ok = $false; not = 'isaret eksik'; dosya = 0 } }
    if (-not [string]::Equals($satirlar[0].Trim(), $YEDEK_ISARET_V, [StringComparison]::OrdinalIgnoreCase)) {
        return @{ ok = $false; not = "isaret bicimi taninmadi: $($satirlar[0].Trim())"; dosya = 0 }
    }
    $beklenen = -1
    foreach ($s in $satirlar[1..2]) {
        if ($s.StartsWith('dosya=', [StringComparison]::OrdinalIgnoreCase)) {
            $n = 0
            if ([int]::TryParse($s.Substring(6).Trim(), [ref]$n)) { $beklenen = $n }
        }
    }
    if ($beklenen -lt 0) { return @{ ok = $false; not = 'isarette dosya sayisi yok'; dosya = 0 } }
    $listelenen = @($satirlar | Select-Object -Skip 3)
    if ($listelenen.Count -ne $beklenen) {
        return @{ ok = $false; not = "isaret kendiyle tutarsiz (dosya=$beklenen, listede $($listelenen.Count))"; dosya = 0 }
    }
    # Listedeki ile diskteki GERCEKTEN ayni mi: isaret yazildiktan sonra elle
    # dosya silinmis/eklenmis olabilir.
    # DIKKAT: Get-GoreliDosyalar ',$liste' dondurur; dogrudan @(...) icine
    # alinirsa liste NESNESI tek oge olarak sarilir. Once degiskene al.
    $diskteHam = Get-GoreliDosyalar -Kok $YedekKok
    $diskte = @($diskteHam)
    $listeSet = New-Set -Ogeler $listelenen
    $diskSet  = New-Set -Ogeler $diskte
    $eksikOl = @($listelenen | Where-Object { -not $diskSet.Contains($_) })
    $fazlaOl = @($diskte | Where-Object { -not $listeSet.Contains($_) })
    if ($eksikOl.Count -gt 0 -or $fazlaOl.Count -gt 0) {
        $n = "isaret diskle uyusmuyor (eksik $($eksikOl.Count), fazla $($fazlaOl.Count))"
        if ($eksikOl.Count -gt 0) { $n = $n + "; ilk eksik: $($eksikOl[0])" }
        elseif ($fazlaOl.Count -gt 0) { $n = $n + "; ilk fazla: $($fazlaOl[0])" }
        return @{ ok = $false; not = $n; dosya = 0 }
    }
    return @{ ok = $true; not = ''; dosya = $beklenen }
}

# --- Yedek geri yukleme: hedef kumeyi yedegin TAM kopyasi yapar ------------
# Silme adimi Test-Silinebilir'e uyar: yalniz .ps1, templates disi, kurtarma
# araclari (guncelle/kur/doktor.ps1) haric. Guncelleme yolundaki $silinen ile
# AYNI kural; eskiden burada hicbir ayrim yoktu.
function Restore-Yedek {
    param([string]$YedekKok)
    $yedektekiler = Get-GoreliDosyalar -Kok $YedekKok
    $set = New-Set -Ogeler @($yedektekiler)
    $geri = 0
    $basarisiz = New-Object System.Collections.Generic.List[string]
    foreach ($rel in $yedektekiler) {
        try {
            Copy-Dosya -Kaynak (Join-Path $YedekKok $rel) -Hedef (Join-Path $Vault $rel)
            $geri++
        } catch {
            $basarisiz.Add("yaz: $rel  ($($_.Exception.Message))")
        }
    }
    $sil = 0
    foreach ($rel in (Get-GoreliDosyalar -Kok $Vault)) {
        if ($set.Contains($rel)) { continue }
        if (-not (Test-Silinebilir $rel)) { continue }
        $yol = Join-Path $Vault $rel
        if (-not (Test-VaultAlti $yol)) { continue }
        try {
            Remove-Item -LiteralPath $yol -Force -ErrorAction SilentlyContinue
            $sil++
        } catch {
            $basarisiz.Add("sil: $rel  ($($_.Exception.Message))")
        }
    }
    return @{ geri = $geri; sil = $sil; basarisiz = @($basarisiz) }
}

# NEDEN sarmalayici: geri yukleme cagrilari (yazim hatasi ve kur.ps1 basarisiz
# dallari) try/catch DISINDAYDI, $ErrorActionPreference ise 'Stop'. Geri
# yukleme orijinal hatayi doguran AYNI disk-dolu/kilit kosulunda kosuyor;
# firlarsa betik orada olur, motor yarim kalir ve Bitir'e hic varilmadigi icin
# makbuz da yazilmazdi. Bu fonksiyon asla firlatmaz.
function Invoke-GeriYukle {
    param([string]$YedekKok)
    try { return (Restore-Yedek -YedekKok $YedekKok) }
    catch { return @{ geri = 0; sil = 0; basarisiz = @("geri yukleme coktu: $($_.Exception.Message)") } }
}

function Get-BasarisizSatirlari {
    param($R)
    $c = New-Object System.Collections.Generic.List[string]
    $b = @($R.basarisiz)
    if ($b.Count -eq 0) { return ,$c }
    $c.Add("  GERI YUKLENEMEYEN ($($b.Count)):")
    $i = 0
    foreach ($x in $b) {
        if ($i -ge 20) { $c.Add("    ... +$($b.Count - 20)"); break }
        $c.Add("    $x")
        $i++
    }
    return ,$c
}

# Tum yedek klasorleri (gecersizler dahil): budama bunlari da temizlesin.
function Get-YedekKlasorleri {
    $kok = Join-Path $p.ScrState 'guncelleme-yedek'
    if (-not (Test-Path -LiteralPath $kok -PathType Container)) { return ,@() }
    return ,@(Get-ChildItem -LiteralPath $kok -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending)
}

# ===========================================================================
# 0) HEDEF KLASOR BAGLANTI KONTROLU (junction/symlink)
# ===========================================================================
$baglantilar = Get-HedefBaglantilari
if (@($baglantilar).Count -gt 0) {
    $bn = (@($baglantilar) -join ', ')
    Bitir -Outcome 'GUNCELLE_PAKET_BOZUK' -Kod 2 -Not "hedef klasor baglanti (junction/symlink): $bn" -Satir @(
        'GUNCELLE: DURDU - hedef klasor bir BAGLANTI (junction/symlink).',
        '',
        "  Baglanti: $bn",
        '',
        '  Bu klasorlerin icerigi fiziksel olarak vault DISINDA duruyor olabilir.',
        '  Guncelleme oradaki dosyalari yedekler, uzerine yazar ve pakette yoksa',
        '  silerdi; vault siniri kontrolu yol dizesine bakar, baglantiyi cozmez.',
        '  Dogru davranisi tahmin etmek yerine hicbir sey yapmadan duruyoruz.',
        '',
        '  Cozum: baglantiyi kaldirip gercek klasoru vault icine tasi.'
    ) -Ek @{ baglanti = @($baglantilar) }
}

# ===========================================================================
# 1) KAYNAK VAULT KORUMASI
# ===========================================================================
$kaynakVault = Test-Path -LiteralPath (Join-Path $Vault 'kurulum\DEPO-README.md') -PathType Leaf
if ($kaynakVault -and -not $Zorla -and $GeriAl) {
    # NEDEN ayri dal: -GeriAl de bu korumanin ARKASINDA kaliyor, ama eski
    # mesaj yalniz "uzerine yazmak" dilinde yazilmisti ve cikis 0'di. Geri
    # alma istenip hicbir sey yapilmamasi BASARI degildir: cagiran (kabuk,
    # kanca, panik anindaki kullanici) 0 gorunce geri alindi saniyordu.
    Bitir -Outcome 'GUNCELLE_KAYNAK_VAULT' -Kod 1 -Not 'geri alma yapilmadi: bu vault yayinin kaynagi' -Satir @(
        'GUNCELLE: GERI ALMA YAPILMADI - bu vault yayinin KAYNAGI.',
        '',
        "  Isaret: kurulum\DEPO-README.md var. O dosya yalniz gelistirme vault'unda",
        '  bulunur. Buradaki motor gelistirmenin kendisi; bir guncelleme yedegine',
        '  geri donmek kendi calismani eski bir kopyayla ezerdi.',
        '',
        '  Gercekten geri almak icin  :  beyin guncelle -GeriAl -Zorla',
        '  Motoru buradan yayinlamak  :  beyin yayinla -Uygula -Gonder'
    )
}
if ($kaynakVault -and -not $Zorla) {
    Bitir -Outcome 'GUNCELLE_KAYNAK_VAULT' -Kod 0 -Not 'kurulum\DEPO-README.md var: yayinin kaynagi' -Satir @(
        'GUNCELLE: DURDU - bu vault yayinin KAYNAGI.',
        '',
        "  Isaret: kurulum\DEPO-README.md var. O dosya yalniz gelistirme vault'unda bulunur;",
        '  yayinla.ps1 onu depo kokune README.md olarak tasir. Yani buraya uzaktan yazmak',
        '  kendi gelistirmeni eski bir paketle ezmek olurdu.',
        '',
        '  Motoru buradan YAYINLAMAK icin:  beyin yayinla -Uygula -Gonder',
        '  Gercekten uzerine yazmak icin :  beyin guncelle -Zorla'
    )
}

# ===========================================================================
# 10) -GeriAl: en son yedegi geri yukle
# ===========================================================================
if ($GeriAl) {
    $yedekler = Get-YedekKlasorleri
    if (-not $yedekler -or $yedekler.Count -eq 0) {
        Bitir -Outcome 'GUNCELLE_PAKET_BOZUK' -Kod 1 -Not 'geri alinacak yedek yok' -Satir @(
            'GUNCELLE: geri alinacak yedek yok.',
            "  Beklenen yer: $(Join-Path $p.ScrState 'guncelleme-yedek')"
        )
    }
    # En yeni GECERLI yedegi bul. "En yeni" tek basina yetmez: yarim kalmis bir
    # klasor de en yeni tarihli olabilir (bkz. Write-YedekIsaret NEDEN notu).
    $secilen = $null
    $redSatir = New-Object System.Collections.Generic.List[string]
    $redEk = New-Object System.Collections.Generic.List[string]
    foreach ($y in $yedekler) {
        $t = Test-YedekGecerli -YedekKok $y.FullName
        if ($t.ok) { $secilen = $y; break }
        $redSatir.Add("    $($y.Name): $($t.not)")
        $redEk.Add("$($y.Name): $($t.not)")
    }
    if (-not $secilen) {
        $satirlar = New-Object System.Collections.Generic.List[string]
        $satirlar.Add('GUNCELLE: GECERLI YEDEK YOK - HICBIR SEY DEGISTIRILMEDI.')
        $satirlar.Add('')
        $satirlar.Add("  Yedek klasoru bulundu ama hicbiri butun degil ($($yedekler.Count) aday):")
        foreach ($s in $redSatir) { $satirlar.Add($s) }
        $satirlar.Add('')
        $satirlar.Add('  Yarim bir yedekle geri almak, hedef kumeyi o yarim kopyaya esitlemek')
        $satirlar.Add('  demektir. Bilerek reddediyoruz.')
        $satirlar.Add("  Yer: $(Join-Path $p.ScrState 'guncelleme-yedek')")
        Bitir -Outcome 'GUNCELLE_YEDEK_GECERSIZ' -Kod 1 -Not "gecerli yedek yok ($($yedekler.Count) aday reddedildi)" -Satir @($satirlar) -Ek @{
            adaylar = $yedekler.Count; red = @($redEk)
        }
    }
    if ($redEk.Count -gt 0) {
        Yaz "GUNCELLE: $($redEk.Count) yedek gecersiz sayildi, atlandi:"
        foreach ($s in $redSatir) { Yaz $s }
    }
    $sonYedek = $secilen.FullName
    Yaz "GUNCELLE: geri aliniyor -> $($secilen.Name)"
    $r = Invoke-GeriYukle -YedekKok $sonYedek
    Write-BeyinLog -Vault $Vault -Message "guncelle: geri alindi ($($secilen.Name); $($r.geri) dosya yazildi, $($r.sil) silindi, $(@($r.basarisiz).Count) basarisiz)"
    # NEDEN kur.ps1 yoksa HATA: eskiden Test-Path false ise $kurKod baslangic
    # 0'inda kaliyor ve cikti "kur.ps1: cikis 0" diyordu - kurulum hic
    # kosmamisken BASARI raporu. Kurtarma yolunda en aldatici satir buydu.
    $kur = Join-Path $Vault 'kurulum\kur.ps1'
    $kurKod = 0
    $kurVar = Test-Path -LiteralPath $kur -PathType Leaf
    if ($kurVar) {
        $kurCikti = @(& powershell -NoProfile -ExecutionPolicy Bypass -File $kur -Vault $Vault)
        $kurKod = $LASTEXITCODE
        if (-not $Json) { foreach ($s in $kurCikti) { Write-Output ('  ' + [string]$s) } }
    }
    $script:yerelSurum = 'bilinmiyor'
    try { $script:yerelSurum = (Get-Content -LiteralPath (Join-Path $Vault '.beyin-version') -Raw -Encoding UTF8).Trim() } catch { }

    $basarisizSayi = @($r.basarisiz).Count
    if (-not $kurVar) {
        $satirlar = New-Object System.Collections.Generic.List[string]
        $satirlar.Add('')
        $satirlar.Add("GUNCELLE: GERI YUKLENDI AMA KURULUM YOK  ($($secilen.Name))")
        $satirlar.Add("  geri yuklenen: $($r.geri) dosya")
        $satirlar.Add("  silinen      : $($r.sil) dosya (yedekte olmayan .ps1)")
        foreach ($s in (Get-BasarisizSatirlari $r)) { $satirlar.Add($s) }
        $satirlar.Add('  kur.ps1      : BULUNAMADI - kurulum kosmadi, motor bagli DEGIL.')
        $satirlar.Add("                 Beklenen: $kur")
        $satirlar.Add("  surum        : $($script:yerelSurum)")
        Bitir -Outcome 'GUNCELLE_KUR_BASARISIZ' -Kod 1 -Not "geri alindi ama kur.ps1 bulunamadi: $kur" -Satir @($satirlar) -Ek @{
            yedek = $secilen.Name; geriYuklenen = $r.geri; silinen = $r.sil
            kurKod = $null; kurVar = $false; basarisiz = @($r.basarisiz)
        }
    }
    $kod = 0
    if ($kurKod -ne 0 -or $basarisizSayi -gt 0) { $kod = 1 }
    $baslik = if ($kod -eq 0) { 'GERI ALINDI' } else { 'GERI ALINDI (SORUNLU)' }
    $satirlar = New-Object System.Collections.Generic.List[string]
    $satirlar.Add('')
    $satirlar.Add("GUNCELLE: $baslik  ($($secilen.Name))")
    $satirlar.Add("  geri yuklenen: $($r.geri) dosya")
    $satirlar.Add("  silinen      : $($r.sil) dosya (yedekte olmayan .ps1)")
    foreach ($s in (Get-BasarisizSatirlari $r)) { $satirlar.Add($s) }
    $satirlar.Add("  kur.ps1      : cikis $kurKod")
    $satirlar.Add("  surum        : $($script:yerelSurum)")
    Bitir -Outcome 'GUNCELLE_GERI_ALINDI' -Kod $kod -Not "$($secilen.Name); $($r.geri) yazildi, $($r.sil) silindi, $basarisizSayi basarisiz, kur=$kurKod" -Satir @($satirlar) -Ek @{
        yedek = $secilen.Name; geriYuklenen = $r.geri; silinen = $r.sil
        kurKod = $kurKod; kurVar = $true; basarisiz = @($r.basarisiz)
    }
}

# ===========================================================================
# 2) SURUM KARSILASTIRMASI  (yerel surum yukarida okundu)
# ===========================================================================
$rxDepo = [regex]::new('github\.com[/:]([^/]+)/([^/]+?)(?:\.git)?/*$', 'IgnoreCase, CultureInvariant')
$m = $rxDepo.Match($Depo)
if (-not $m.Success) {
    Bitir -Outcome 'GUNCELLE_AG_YOK' -Kod 1 -Not "depo adresi cozulemedi: $Depo" -Satir @(
        "GUNCELLE: depo adresi cozulemedi: $Depo",
        '  Beklenen bicim: https://github.com/<sahip>/<depo>'
    )
}
$sahip = $m.Groups[1].Value
$depoAd = $m.Groups[2].Value

$script:gecici = Join-Path $env:TEMP ('beyin-guncelle-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $script:gecici | Out-Null

$surumUrl = "https://raw.githubusercontent.com/$sahip/$depoAd/$Dal/.beyin-version"
$surumDosya = Join-Path $script:gecici 'uzak-surum.txt'
if (-not (Get-Uzak -Url $surumUrl -Hedef $surumDosya)) {
    Bitir -Outcome 'GUNCELLE_AG_YOK' -Kod 1 -Not "uzak surum okunamadi: $surumUrl" -Satir @(
        'GUNCELLE: AG YOK - uzak surum okunamadi, hicbir sey yazilmadi.',
        "  Adres: $surumUrl",
        '  Ag baglantisini, vekil sunucuyu ya da depo/dal adini kontrol et.'
    )
}
try { $script:uzakSurum = (Get-Content -LiteralPath $surumDosya -Raw -Encoding UTF8).Trim() } catch { $script:uzakSurum = '' }
if (-not $script:uzakSurum) {
    Bitir -Outcome 'GUNCELLE_AG_YOK' -Kod 1 -Not 'uzak .beyin-version bos' -Satir @(
        'GUNCELLE: AG YOK - uzak .beyin-version bos geldi, hicbir sey yazilmadi.',
        "  Adres: $surumUrl"
    )
}

Yaz "GUNCELLE  yerel: $($script:yerelSurum)   uzak: $($script:uzakSurum) ($sahip/$depoAd@$Dal)"

if ([string]::Equals($script:yerelSurum, $script:uzakSurum, [StringComparison]::Ordinal) -and -not $Zorla) {
    Bitir -Outcome 'GUNCELLE_GUNCEL' -Kod 0 -Not "surum $($script:yerelSurum)" -Satir @(
        '',
        "GUNCELLE: GUNCEL - surum $($script:yerelSurum), yapilacak bir sey yok.",
        '  Ayni surumu yine de indirmek icin: beyin guncelle -Zorla'
    )
}

# ===========================================================================
# 3) INDIRME
# ===========================================================================
$zipUrl = "https://codeload.github.com/$sahip/$depoAd/zip/refs/heads/$Dal"
$zip = Join-Path $script:gecici 'paket.zip'
Yaz "  indiriliyor: $zipUrl"
if (-not (Get-Uzak -Url $zipUrl -Hedef $zip)) {
    Bitir -Outcome 'GUNCELLE_AG_YOK' -Kod 1 -Not "paket indirilemedi: $zipUrl" -Satir @(
        'GUNCELLE: AG YOK - paket indirilemedi, hicbir sey yazilmadi.',
        "  Adres: $zipUrl"
    )
}
$acik = Join-Path $script:gecici 'acik'
try {
    New-Item -ItemType Directory -Force -Path $acik | Out-Null
    Expand-Archive -LiteralPath $zip -DestinationPath $acik -Force -ErrorAction Stop
} catch {
    Bitir -Outcome 'GUNCELLE_PAKET_BOZUK' -Kod 1 -Not "zip acilamadi: $($_.Exception.Message)" -Satir @(
        'GUNCELLE: PAKET BOZUK - zip acilamadi, hicbir sey yazilmadi.',
        "  $($_.Exception.Message)"
    )
}
# Zip icinde tek ust klasor olur: <depo>-<dal>
$paket = $acik
$ustler = @(Get-ChildItem -LiteralPath $acik -Directory -ErrorAction SilentlyContinue)
if ($ustler.Count -eq 1) { $paket = $ustler[0].FullName }

# ===========================================================================
# 4) DOGRULAMA
# ===========================================================================
$zorunlu = @('motor\hooks\lib.ps1', 'motor\scripts\doktor.ps1', 'kurulum\kur.ps1')
$eksik = @()
foreach ($z in $zorunlu) {
    if (-not (Test-Path -LiteralPath (Join-Path $paket $z) -PathType Leaf)) { $eksik += $z }
}
$uzakDosyalar = Get-GoreliDosyalar -Kok $paket
$yerelDosyalar = Get-GoreliDosyalar -Kok $Vault
$uzakPs1 = @($uzakDosyalar | Where-Object { $_.EndsWith('.ps1', [StringComparison]::OrdinalIgnoreCase) }).Count
$yerelPs1 = @($yerelDosyalar | Where-Object { $_.EndsWith('.ps1', [StringComparison]::OrdinalIgnoreCase) }).Count
$esik = [int][math]::Floor($yerelPs1 / 2)
if ($eksik.Count -gt 0 -or $uzakPs1 -lt $esik) {
    $not = "eksik=[$($eksik -join ', ')] uzakPs1=$uzakPs1 yerelPs1=$yerelPs1 esik=$esik"
    Bitir -Outcome 'GUNCELLE_PAKET_BOZUK' -Kod 1 -Not $not -Satir @(
        'GUNCELLE: PAKET BOZUK - hicbir sey yazilmadi.',
        "  eksik zorunlu dosya: $(if ($eksik.Count) { $eksik -join ', ' } else { '(yok)' })",
        "  paketteki .ps1     : $uzakPs1   (yerel: $yerelPs1, gereken en az: $esik)"
    ) -Ek @{ eksik = @($eksik); uzakPs1 = $uzakPs1; yerelPs1 = $yerelPs1 }
}

# --- Fark hesabi -----------------------------------------------------------
$yerelSet = New-Set -Ogeler @($yerelDosyalar)
$uzakSet  = New-Set -Ogeler @($uzakDosyalar)

$eklenen = New-Object System.Collections.Generic.List[string]
$degisen = New-Object System.Collections.Generic.List[string]
# Yerel olarak degistirilmis korumali dosyalar: yazilmaz, adiyla raporlanir.
$atlanan = New-Object System.Collections.Generic.List[string]
foreach ($rel in $uzakDosyalar) {
    if (-not $yerelSet.Contains($rel)) { $eklenen.Add($rel); continue }
    $h1 = Get-DosyaHash (Join-Path $paket $rel)
    $h2 = Get-DosyaHash (Join-Path $Vault $rel)
    if ([string]::Equals($h1, $h2, [StringComparison]::OrdinalIgnoreCase)) { continue }
    # NEDEN: AGENTS.md / CLAUDE.md kullanicinin kendi makinesine gore
    # ozellestirdigi dosyalar, brain.config.json ise vault anayasasinin
    # preview-required parcasi, templates\ ise duzenlenebilir sablonlar.
    # Eskiden tek bir 'beyin guncelle' ucunu de sorulmadan uzak paketle
    # degistiriyordu. Fark varsa varsayilan ATLAMAK; -Zorla acikca ister.
    if ((Test-Korumali $rel) -and -not $Zorla) { $atlanan.Add($rel); continue }
    $degisen.Add($rel)
}
$atlananSet = New-Set -Ogeler @($atlanan)
# Silinen: uzak pakette OLMAYAN yerel .ps1 dosyalari. Kural Test-Silinebilir'de
# (Restore-Yedek ile PAYLASILAN tek tanim): yalniz .ps1 - kaldirilan betikler
# makinede kalirsa dagitici hala onlari cagirabilir; diger uzantilarda silme
# YAPILMAZ. templates\ altindaki kullanici sablonlari ve kurtarma araclari
# (guncelle.ps1, kur.ps1, doktor.ps1 ve betigin kendi dosya adi) disaridadir:
# uzak pakette yoklarsa bile silmek kullanicinin geri donus yolunu kaldirir.
$silinen = New-Object System.Collections.Generic.List[string]
foreach ($rel in $yerelDosyalar) {
    if ($uzakSet.Contains($rel)) { continue }
    if (-not (Test-Silinebilir $rel)) { continue }
    $silinen.Add($rel)
}

function Ozet-Satirlari {
    param([string]$Baslik, $Liste)
    $c = New-Object System.Collections.Generic.List[string]
    $c.Add("$Baslik ($(@($Liste).Count))")
    $i = 0
    foreach ($x in @($Liste)) {
        if ($i -ge 20) { $c.Add("  ... +$((@($Liste).Count) - 20)"); break }
        $c.Add("  $x")
        $i++
    }
    if (@($Liste).Count -eq 0) { $c.Add('  (yok)') }
    return ,$c
}

# ===========================================================================
# 11) -KuruCalisma: ne degisecegini bas, HICBIR SEY YAZMA
# ===========================================================================
if ($KuruCalisma) {
    $satirlar = New-Object System.Collections.Generic.List[string]
    $satirlar.Add('')
    $satirlar.Add("GUNCELLE (KURU CALISMA - hicbir sey yazilmadi)  $($script:yerelSurum) -> $($script:uzakSurum)")
    $satirlar.Add('')
    foreach ($s in (Ozet-Satirlari -Baslik 'EKLENECEK' -Liste $eklenen)) { $satirlar.Add($s) }
    $satirlar.Add('')
    foreach ($s in (Ozet-Satirlari -Baslik 'DEGISECEK' -Liste $degisen)) { $satirlar.Add($s) }
    $satirlar.Add('')
    foreach ($s in (Ozet-Satirlari -Baslik 'SILINECEK (.ps1)' -Liste $silinen)) { $satirlar.Add($s) }
    $satirlar.Add('')
    foreach ($s in (Ozet-Satirlari -Baslik 'ATLANACAK (yerel olarak degistirilmis)' -Liste $atlanan)) { $satirlar.Add($s) }
    if ($atlanan.Count -gt 0) {
        $satirlar.Add('  Bu dosyalar yerelde degistirilmis; uzerine yazmak icin: beyin guncelle -Zorla')
    }
    $satirlar.Add('')
    $satirlar.Add('  Uygulamak icin: beyin guncelle')
    Bitir -Outcome 'GUNCELLE_KURU' -Kod 0 -Not "ekle=$($eklenen.Count) degis=$($degisen.Count) sil=$($silinen.Count) atla=$($atlanan.Count)" -Satir @($satirlar) -Ek @{
        eklenen = @($eklenen); degisen = @($degisen); silinen = @($silinen); atlanan = @($atlanan)
    }
}

# ===========================================================================
# 5) YEDEK
# ===========================================================================
$yedekAna = Join-Path $p.ScrState 'guncelleme-yedek'
New-Item -ItemType Directory -Force -Path $yedekAna | Out-Null
$script:yedekKok = Join-Path $yedekAna ((Get-Date).ToString('yyyyMMdd-HHmmss', $inv))
New-Item -ItemType Directory -Force -Path $script:yedekKok | Out-Null
$yedeklenen = 0
# NEDEN try/catch: bu dongu eskiden korumasizdi ve $ErrorActionPreference
# 'Stop'. Yarim kalan klasor diskte kaliyor, zaman damgasi yuzunden EN YENI
# yedek oluyordu. Hata halinde artik cop birakmadan siliniyor; isaret dosyasi
# ise yakalanamayan durumlara (Ctrl+C) karsi ikinci savunma.
try {
    foreach ($rel in $yerelDosyalar) {
        Copy-Dosya -Kaynak (Join-Path $Vault $rel) -Hedef (Join-Path $script:yedekKok $rel)
        $yedeklenen++
    }
    Write-YedekIsaret -YedekKok $script:yedekKok -Dosyalar $yerelDosyalar
} catch {
    $hy = $_.Exception.Message
    $yarim = $script:yedekKok
    try { Remove-Item -LiteralPath $yarim -Recurse -Force -ErrorAction SilentlyContinue } catch { }
    $script:yedekKok = ''
    Bitir -Outcome 'GUNCELLE_YEDEK_GECERSIZ' -Kod 1 -Not "yedek alinamadi: $hy" -Satir @(
        'GUNCELLE: YEDEK ALINAMADI - hicbir sey yazilmadi.',
        "  $hy",
        "  $yedeklenen / $(@($yerelDosyalar).Count) dosya kopyalanmisti; yarim klasor silindi.",
        '  Yedeksiz guncelleme yapilmaz: geri donus yolu olmadan yazmak daha kotudur.'
    ) -Ek @{ yedeklenen = $yedeklenen; beklenen = @($yerelDosyalar).Count }
}
Yaz "  yedek: $($script:yedekKok)  ($yedeklenen dosya; .state kopyalanmadi)"

# En yeni 3 yedek tutulur.
#
# DIKKAT (2026-09-18, PS 5.1'de olculdu): Get-YedekKlasorleri `,@(...)` ile
# donuyor, yani boru hattina TEK OGE (dizinin kendisi) veriyor.
# `Get-YedekKlasorleri | Select-Object -Skip 3` o tek ogeyi atlar ve HICBIR SEY
# uretmez - dongu govdesi hic kosmazdi ve yedekler sonsuza dek birikiyordu.
# Once DEGISKENE al, sonra boru hattina ver.
$tumYedekler = Get-YedekKlasorleri
foreach ($eski in @($tumYedekler | Select-Object -Skip 3)) {
    if (-not (Test-VaultAlti $eski.FullName)) { continue }
    Remove-Item -LiteralPath $eski.FullName -Recurse -Force -ErrorAction SilentlyContinue
}

# ===========================================================================
# 6) YAZIM
# ===========================================================================
$yazildi = 0
$silindi = 0
try {
    if ($atlanan.Count -gt 0) {
        Yaz "  ATLANDI - yerel olarak degistirilmis ($($atlanan.Count)):"
        foreach ($rel in $atlanan) { Yaz "    $rel" }
        Yaz '    (uzerine yazmak icin: beyin guncelle -Zorla)'
    }
    foreach ($rel in $uzakDosyalar) {
        if ($atlananSet.Contains($rel)) { continue }
        Copy-Dosya -Kaynak (Join-Path $paket $rel) -Hedef (Join-Path $Vault $rel)
        $yazildi++
    }
    if ($silinen.Count -gt 0) {
        Yaz "  silinen .ps1 ($($silinen.Count)) - hepsi yedekte:"
        foreach ($rel in $silinen) {
            $yol = Join-Path $Vault $rel
            if (-not (Test-VaultAlti $yol)) { continue }
            if (-not (Test-Path -LiteralPath (Join-Path $script:yedekKok $rel) -PathType Leaf)) {
                Yaz "    ATLANDI (yedekte yok): $rel"
                continue
            }
            Yaz "    $rel"
            Remove-Item -LiteralPath $yol -Force
            $silindi++
        }
    }
} catch {
    $hata = $_.Exception.Message
    $r = Invoke-GeriYukle -YedekKok $script:yedekKok
    Write-BeyinLog -Vault $Vault -Message "guncelle: yazim hatasi, geri alindi ($hata; $(@($r.basarisiz).Count) basarisiz)"
    $satirlar = New-Object System.Collections.Generic.List[string]
    $satirlar.Add('GUNCELLE: YAZIM HATASI - yedek geri yuklendi.')
    $satirlar.Add("  $hata")
    $satirlar.Add("  geri yuklenen: $($r.geri) dosya")
    foreach ($s in (Get-BasarisizSatirlari $r)) { $satirlar.Add($s) }
    if (@($r.basarisiz).Count -gt 0) {
        $satirlar.Add("  Yedek DURUYOR: $($script:yedekKok)")
        $satirlar.Add('  Elle geri almak icin: beyin guncelle -GeriAl')
    }
    Bitir -Outcome 'GUNCELLE_KUR_BASARISIZ' -Kod 1 -Not "yazim hatasi, geri alindi: $hata ($(@($r.basarisiz).Count) basarisiz)" -Satir @($satirlar) -Ek @{
        basarisiz = @($r.basarisiz); yedek = $script:yedekKok
    }
}

# ===========================================================================
# 7) KURULUM
# ===========================================================================
$kur = Join-Path $Vault 'kurulum\kur.ps1'
$kurCikti = @()
$kurKod = 0
try {
    $kurCikti = @(& powershell -NoProfile -ExecutionPolicy Bypass -File $kur -Vault $Vault)
    $kurKod = $LASTEXITCODE
} catch {
    $kurKod = 1
    $kurCikti = @("kur.ps1 calistirilamadi: $($_.Exception.Message)")
}
if (-not $Json) {
    Yaz ''
    Yaz "KUR.PS1 (cikis $kurKod)"
    foreach ($s in $kurCikti) { Yaz ('  ' + [string]$s) }
}
if ($kurKod -ne 0) {
    $r = Invoke-GeriYukle -YedekKok $script:yedekKok
    Write-BeyinLog -Vault $Vault -Message "guncelle: kur.ps1 basarisiz (cikis $kurKod), geri alindi ($(@($r.basarisiz).Count) basarisiz)"
    $satirlar = New-Object System.Collections.Generic.List[string]
    $satirlar.Add('')
    $satirlar.Add("GUNCELLE: KUR BASARISIZ (kur.ps1 cikis $kurKod) - yedek geri yuklendi, motor eski haline dondu.")
    $satirlar.Add("  yedek        : $($script:yedekKok)")
    $satirlar.Add("  geri yuklenen: $($r.geri) dosya")
    foreach ($s in (Get-BasarisizSatirlari $r)) { $satirlar.Add($s) }
    if (@($r.basarisiz).Count -gt 0) {
        $satirlar.Add('  Motor TAM ESKI HALINDE DEGIL. Elle: beyin guncelle -GeriAl')
    }
    Bitir -Outcome 'GUNCELLE_KUR_BASARISIZ' -Kod 1 -Not "kur.ps1 cikis $kurKod, geri alindi ($(@($r.basarisiz).Count) basarisiz)" -Satir @($satirlar) -Ek @{
        kurKod = $kurKod; kurCikti = @($kurCikti | ForEach-Object { [string]$_ })
        basarisiz = @($r.basarisiz); yedek = $script:yedekKok
    }
}

# ===========================================================================
# 8) DOGRULAMA: doktor -Ozet
# ===========================================================================
$doktor = Join-Path $Vault 'motor\scripts\doktor.ps1'
$dokCikti = @()
$dokKod = 0
try {
    $dokCikti = @(& powershell -NoProfile -ExecutionPolicy Bypass -File $doktor -Vault $Vault -Ozet)
    $dokKod = $LASTEXITCODE
} catch {
    $dokKod = 1
    $dokCikti = @("doktor.ps1 calistirilamadi: $($_.Exception.Message)")
}
if (-not $Json) {
    Yaz ''
    Yaz "DOKTOR -Ozet (cikis $dokKod)"
    foreach ($s in $dokCikti) { Yaz ('  ' + [string]$s) }
    if ($dokKod -ne 0) {
        Yaz ''
        Yaz "  NOT: doktor cikis $dokKod verdi. Guncelleme GERI ALINMADI - doktor uyarisi"
        Yaz '  guncellemeyi bozuk yapmaz. Yukaridaki tabloya bak; gerekirse: beyin guncelle -GeriAl'
    }
}

# ===========================================================================
# 9) DEGISIKLIK OZETI
# ===========================================================================
try { $script:yerelSurum = (Get-Content -LiteralPath (Join-Path $Vault '.beyin-version') -Raw -Encoding UTF8).Trim() } catch { }
Write-BeyinLog -Vault $Vault -Message "guncelle: $($script:uzakSurum) yazildi (ekle=$($eklenen.Count) degis=$($degisen.Count) sil=$silindi atla=$($atlanan.Count), doktor=$dokKod)"

$son = New-Object System.Collections.Generic.List[string]
$son.Add('')
$son.Add("GUNCELLE: TAMAM   $($script:uzakSurum)  ($sahip/$depoAd@$Dal)")
$son.Add("  eklenen: $($eklenen.Count)   degisen: $($degisen.Count)   silinen: $silindi   atlanan: $($atlanan.Count)   yazilan dosya: $yazildi")
$son.Add("  yedek  : $($script:yedekKok)   (geri almak icin: beyin guncelle -GeriAl)")
$son.Add("  doktor : cikis $dokKod$(if ($dokKod -ne 0) { '  << uyari var, guncelleme geri ALINMADI' })")
$son.Add('')
foreach ($s in (Ozet-Satirlari -Baslik 'EKLENEN' -Liste $eklenen)) { $son.Add($s) }
$son.Add('')
foreach ($s in (Ozet-Satirlari -Baslik 'DEGISEN' -Liste $degisen)) { $son.Add($s) }
$son.Add('')
foreach ($s in (Ozet-Satirlari -Baslik 'SILINEN (.ps1)' -Liste $silinen)) { $son.Add($s) }
$son.Add('')
foreach ($s in (Ozet-Satirlari -Baslik 'ATLANAN (yerel olarak degistirilmis)' -Liste $atlanan)) { $son.Add($s) }
if ($atlanan.Count -gt 0) {
    $son.Add('  Bu dosyalar korundu; uzerine yazmak icin: beyin guncelle -Zorla')
}

Bitir -Outcome 'GUNCELLE_OK' -Kod 0 -Not "$($script:uzakSurum): ekle=$($eklenen.Count) degis=$($degisen.Count) sil=$silindi atla=$($atlanan.Count) doktor=$dokKod" -Satir @($son) -Ek @{
    eklenen  = @($eklenen)
    degisen  = @($degisen)
    silinen  = @($silinen)
    atlanan  = @($atlanan)
    yazilan  = $yazildi
    yedek    = $script:yedekKok
    kurKod   = $kurKod
    doktorKod = $dokKod
}
