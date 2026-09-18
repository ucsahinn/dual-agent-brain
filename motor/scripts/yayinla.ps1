# yayinla.ps1 - Motoru + kurulumu uzak depoya gonderir. NOTLARI GONDERMEZ.
#
# NEDEN AYRI BIR DEPO: vault'un kendi git gecmisi kisisel notlari, musteri
# adlarini, oturum ozetlerini ve (uc commit'te) mutlak kullanici yollarini
# tasiyor. O gecmisi paylasilabilir hale getirmek icin yeniden yazmak
# gerekirdi. Bunun yerine YAYIN DEPOSU AYRI ve TEMIZ BIR GECMISLE kurulur:
# icine yalnizca kod, kurulum ve bos iskelet girer.
#
# GUVENLIK MODELI - IZIN VERILENLER LISTESI (allowlist):
# Ne gonderilecegi tek tek sayilir. "Sunlari haric tut" yaklasimi kullanilmaz;
# o yaklasimda yeni eklenen bir klasor SESSIZCE disari sizar. Burada yeni bir
# sey eklemek icin bu listeye elle yazmak gerekir.
#
# Gonderilmeden once her dosya taranir: sir deseni, mutlak kullanici yolu,
# e-posta, yerel proje/musteri adi. Bulunursa yayin DURUR.
#
# Tarama FAIL-CLOSED'dur: taranamayan (cok buyuk, acilamayan) dosya ve
# yapilamayan kontrol "temiz" sayilmaz, bulgu olarak raporlanir ve yayini
# durdurur. Bir guvenlik kapisinin en kotu davranisi sessizce no-op olmaktir.
#
# Kullanim:
#   beyin yayinla                 -> kuru calisma: ne gidecegini goster
#   beyin yayinla -Uygula         -> yerel yayin klasorunu hazirla + commit
#   beyin yayinla -Uygula -Gonder -> ayrica uzak depoya push et

param(
    [string]$Vault = $(if ($env:BEYIN_VAULT) { $env:BEYIN_VAULT } else { Split-Path (Split-Path $PSScriptRoot -Parent) -Parent }),

    # Yayin kopyasinin hazirlanacagi yer. Vault'un DISINDA olmali.
    [string]$Hedef = '',

    # Uzak depo adresi (ilk kurulumda). Verilmezse mevcut 'origin' kullanilir.
    [string]$Uzak = '',

    [switch]$Uygula,
    [switch]$Gonder
)

$ErrorActionPreference = 'Stop'
# VAULT KAPISI (2026-09-17 bagimsiz denetimi - A5). $Vault bu betikte ILK
# bildirilen parametredir: 'beyin yayinla ZZZ' o degeri oraya bagliyor ve
# asagidaki dot-source ham bir PowerShell hatasiyla patliyordu
# ("The module 'ZZZ' could not be loaded.", exit 1) - kullaniciya ne oldugunu
# soylemeyen bir yigin izi. Diger 14 komuttaki kapinin AYNISI.
$vaultOk = $false
try { $vaultOk = [bool]($Vault -and (Test-Path -LiteralPath $Vault -PathType Container) -and (Test-Path -LiteralPath (Join-Path $Vault 'motor\hooks\lib.ps1') -PathType Leaf)) } catch { }
if (-not $vaultOk) { Write-Output "HATA: vault degil (motor\hooks\lib.ps1 yok): '$Vault'  - konumsal arguman -Vault'a baglanir; yayin klasoru icin -Hedef <yol> kullan"; exit 2 }
. (Join-Path $Vault 'motor\hooks\lib.ps1')
$p = Get-BeyinPaths -Vault $Vault

if (-not $Hedef) { $Hedef = Join-Path (Split-Path $Vault -Parent) ((Split-Path -Leaf $Vault) + '-motor') }   # <yaprak>-motor (doktor da boyle arar)

# ===========================================================================
# IZIN VERILEN ICERIK
# ===========================================================================
# Tam dosyalar
$IZIN_DOSYA = @(
    'AGENTS.md',
    'CLAUDE.md',
    'brain.config.json',
    '.beyin-version',
    '.gitattributes',
    # RELEASE GEREGI (2026-09-17): lisanssiz bir depo yasal olarak "tum haklar
    # sakli"dir - kimse kuramaz, kullanamaz, degistiremez. Depoda licenseInfo
    # null idi; "baskasi da kurup kendi kullanabilsin" hedefinin onundeki en
    # somut engel buydu. CHANGELOG da release'in parcasi: kullanici neyin
    # degistigini gormeden guncellemeye guvenemez.
    'LICENSE',
    'CHANGELOG.md'
)
# Tamami kopyalanacak klasorler
$IZIN_KLASOR = @(
    'motor\hooks',
    'motor\scripts',
    'motor\skills',
    'kurulum',
    'templates'
)
# Bos olarak olusturulacak klasorler (iskelet; icerik GITMEZ)
$ISKELET = @(
    '00-inbox', '10-command-center', '20-goals', '30-projects', '40-knowledge',
    '50-research', '60-decisions', '70-personal', '80-memory', '85-daylogs',
    '86-compiled', '90-archive'
)
# Izinli klasorlerin icinde bile ASLA gitmeyecekler
$ASLA = @('.state', 'node_modules', '.git', '.brain')

# ===========================================================================
# TARAMA: sizinti olan hicbir sey gitmesin
# ===========================================================================
$rxYol   = [regex]::new('(?:[A-Za-z]:[\\/]Users[\\/][^\\/\s"''<]+|/(?:home|Users)/[^/\s"''<]+)', 'IgnoreCase, CultureInvariant')
$rxMail  = [regex]::new('[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}', 'IgnoreCase, CultureInvariant')
# Kullanici adi: vault yolundan turetilir, boylece betik her makinede calisir
$kadi = ''
if ($Vault -match '[\\/]Users[\\/]([^\\/]+)') { $kadi = $Matches[1] }

# ---------------------------------------------------------------------------
# YEREL AD TARAMASI - proje / musteri adlari
# ---------------------------------------------------------------------------
# NEDEN (2026-09-17, olculdu): tarayici yol, kullanici adi, e-posta ve sir
# desenine bakiyordu. GERCEK PROJE ADI bunlarin hicbirine uymuyor. Depoyu
# public'e cevirmeden once yapilan taramada HEAD'de dort gercek proje adi
# yedi kod yorumunda duruyordu ve bu dogrulama 19 commit boyunca hepsini
# "temiz" diye gecirmisti.
#
# AD LISTESI BU DOSYAYA YAZILAMAZ: yayinla.ps1'in kendisi yayinlanan
# dosyalardan biridir; listeyi buraya gomek, tam olarak gizlenmek istenen
# adlari yayinlamak olurdu. Bu yuzden iki YEREL kaynak kullanilir:
#   1) ASIL kaynak - ~\.beyin\yayin-yasak.txt (satir basi bir terim, '#' yorum).
#   2) Destekleyici - kullanicinin calisma koklerindeki KLASOR ADLARI
#      (Desktop, Documents, source\repos + OneDrive yonlendirmeleri).
# Yanlis pozitif icin kacis: ~\.beyin\yayin-izin.txt (ayni bicim).
#
# NEDEN 1 ASIL, 2 DESTEKLEYICI (2026-09-17, olculdu): klasor turetimi MAKINE
# DURUMUNA baglidir. Ayni dosya kumesi iki kosuda: gercek USERPROFILE ile 64
# terim -> '4 dosyada SIZINTI VAR' (dogru); bos USERPROFILE ile 0 terim ->
# 'temiz - 75 dosyada sizinti bulunamadi' (YANLIS NEGATIF). Yeni bir makine,
# yeni profil, CI ya da proje klasorlerinin arsivlenmesi kapiyi sessizce
# no-op yapiyordu. Ayrica elle notrlestirilmis bes addan biri, klasoru artik
# diskte olmadigi icin 64 terimlik turetilmis listede DE yoktu - yasak
# dosyasinin var olma sebebi tam olarak budur.
#
# FAIL-CLOSED: birlesik liste bos cikarsa yayin DURUR (asagida). Kapinin
# calismamasi, kapinin 'temiz' demesiyle ayni sey degildir.
$JENERIK = @(
    'beyin', 'motor', 'kurulum', 'templates', 'iskelet', 'skills', 'scripts',
    'hooks', 'desktop', 'documents', 'downloads', 'music', 'pictures', 'videos',
    'temp', 'tmp', 'cache', 'test', 'tests', 'docs', 'doc', 'data', 'bin',
    'lib', 'dist', 'build', 'public', 'assets', 'tools', 'src', 'source',
    'repos', 'projects', 'proje', 'work', 'new', 'old', 'yeni', 'eski',
    'backup', 'backups', 'yedek', 'arsiv', 'archive', 'node_modules',
    'obsidian', 'claude', 'codex', 'anthropic', 'openai', 'ollama', 'github',
    'git', 'powershell', 'windows', 'program files', 'onedrive', 'dropbox',
    'zoom', 'office', 'visual studio', 'vscode', 'python', 'node', 'java',
    # 2026-09-17, olculdu: esik 3'e inince + OneDrive kokleri eklenince
    # 'Dash' adli bir klasor listeye girdi ve doktor.ps1'deki '$dash' /
    # 'dashboard.md' satirlarini SIZINTI saydi. Ikisi de motorun kendi
    # sozlugu; jenerige alinmasi tasinabilir cozum (yerel izin dosyasi bir
    # sonraki makinede ayni yanlis pozitifi yine uretirdi).
    'dash', 'dashboard', 'panel', 'index', 'notes', 'notlar'
)

$YASAK_DOSYA = Join-Path $env:USERPROFILE '.beyin\yayin-yasak.txt'
$IZIN_DOSYA_AD = Join-Path $env:USERPROFILE '.beyin\yayin-izin.txt'

function Get-YasakAdlar {
    # Iki kumeyi AYRI tutar: hangi terimin nereden geldigi raporlanabilsin.
    $turetilen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $dosyadan  = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $set       = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $okunamayan = New-Object System.Collections.Generic.List[string]
    $bakilanKok = New-Object System.Collections.Generic.List[string]

    # Kendi adlarimiz jenerige eklenir: vault yapragi ve yayin hedefi yapragi.
    # NEDEN '<vaultyapragi>-motor' HER ZAMAN (2026-09-17, olculdu): varsayilan
    # disinda bir -Hedef verildiginde gercek yayin klasoru adi izin listesine
    # girmiyor, o ad vault'un kendi dosyalarinda gectigi icin yayin YANLIS
    # POZITIF ile duruyordu.
    $kendi = @(
        (Split-Path -Leaf $Vault),
        (Split-Path -Leaf $Hedef),
        ((Split-Path -Leaf $Vault) + '-motor')
    )
    $izinli = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($g in $JENERIK) { [void]$izinli.Add($g) }
    foreach ($g in $kendi)   { if ($g) { [void]$izinli.Add($g) } }
    if (Test-Path -LiteralPath $IZIN_DOSYA_AD) {
        foreach ($ln in @(Get-Content -LiteralPath $IZIN_DOSYA_AD -Encoding UTF8 -ErrorAction SilentlyContinue)) {
            $t = "$ln".Trim()
            if ($t -and -not $t.StartsWith('#')) { [void]$izinli.Add($t) }
        }
    }

    # 1) ASIL KAYNAK - elle bakimli yasak listesi. Diskte artik klasoru
    #    olmayan (arsivlenmis, teslim edilmis) proje adlari YALNIZ burada
    #    yasar; turetim onlari goremez.
    if (Test-Path -LiteralPath $YASAK_DOSYA) {
        foreach ($ln in @(Get-Content -LiteralPath $YASAK_DOSYA -Encoding UTF8 -ErrorAction SilentlyContinue)) {
            $t = "$ln".Trim()
            if ($t -and -not $t.StartsWith('#') -and -not $izinli.Contains($t)) { [void]$dosyadan.Add($t) }
        }
    }

    # 2) DESTEKLEYICI - calisma koklerindeki klasor adlari.
    #    OneDrive yonlendirmesi (2026-09-17): Desktop/Documents yonlendirilmis
    #    olabilir; o durumda $env:USERPROFILE\Desktop YA YOKTUR ya da bostur ve
    #    turetim sessizce hicbir sey bulmaz. GetFolderPath yonlendirilmis
    #    GERCEK yolu verir; $env:OneDrive altindaki ikisi de ayrica denenir.
    $adaylar = New-Object System.Collections.Generic.List[string]
    if ($env:USERPROFILE) {
        $adaylar.Add((Join-Path $env:USERPROFILE 'Desktop'))
        $adaylar.Add((Join-Path $env:USERPROFILE 'Documents'))
        $adaylar.Add((Join-Path $env:USERPROFILE 'source\repos'))
    }
    foreach ($ozel in @('Desktop', 'MyDocuments')) {
        $y = ''
        try { $y = [Environment]::GetFolderPath($ozel) } catch { $y = '' }
        if ($y) { $adaylar.Add($y) }
    }
    if ($env:OneDrive) {
        $adaylar.Add((Join-Path $env:OneDrive 'Desktop'))
        $adaylar.Add((Join-Path $env:OneDrive 'Documents'))
    }
    foreach ($ham in $adaylar) {
        if (-not $ham) { continue }
        $kok = $ham.TrimEnd('\', '/')
        if (-not $kok) { continue }
        if ($bakilanKok -contains $kok) { continue }   # -contains: harf duyarsiz
        $bakilanKok.Add($kok)
        if (-not (Test-Path -LiteralPath $kok)) { continue }
        # KOR NOKTA (2026-09-17): -ErrorAction SilentlyContinue okunamayan bir
        # kokte BOS liste donuyordu; kapi hicbir sey demeden koru kaliyordu.
        # Simdi hata yakalanip raporlanir.
        $kokHata = $null
        $altlar = @(Get-ChildItem -LiteralPath $kok -Directory -Force -ErrorAction SilentlyContinue -ErrorVariable kokHata)
        if ($kokHata -and $kokHata.Count -gt 0) {
            $okunamayan.Add("$kok  ->  $($kokHata[0].Exception.Message)")
        }
        foreach ($d in $altlar) {
            $ad = $d.Name
            # Cok kisa adlar ve sayi/tarih klasorleri kelime sinirinda yanlis
            # pozitif uretir. ESIK 4 -> 3 (2026-09-17): 4 sinir bu makinede dort
            # klasoru listeden dusuruyordu; uc harfli proje/musteri kisaltmalari
            # gercek ve yakalanmasi gereken sizintidir.
            if ($ad.Length -lt 3) { continue }
            if ($ad.StartsWith('.') -or $ad.StartsWith('$')) { continue }
            if ($ad -match '^[\d\W_]+$') { continue }
            if ($izinli.Contains($ad)) { continue }
            [void]$turetilen.Add($ad)
        }
    }

    foreach ($t in $turetilen) { [void]$set.Add($t) }
    foreach ($t in $dosyadan)  { [void]$set.Add($t) }
    return [pscustomobject]@{
        Adlar       = @($set)
        Turetilen   = $turetilen.Count
        Dosyadan    = $dosyadan.Count
        # Kaynak AYRIMI korunur: elle yazilan adlarda sinir kurali gevsek
        # olacak (bkz. asagidaki rxYasak dongusu).
        DosyadanAdlar = @($dosyadan)
        Kokler      = @($bakilanKok)
        Okunamayan  = @($okunamayan)
    }
}

$yasakBilgi  = Get-YasakAdlar
$YASAK_ADLAR = @($yasakBilgi.Adlar)
$rxYasak = @()
$dosyadanSet = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
foreach ($d in @($yasakBilgi.DosyadanAdlar)) { [void]$dosyadanSet.Add($d) }

foreach ($ad in $YASAK_ADLAR) {
    # SINIR KURALI ADIN KAYNAGINA GORE DEGISIR (2026-09-18, olculdu).
    #
    # TURETILEN adlar (calisma koklerindeki klasor adlari) rastgele Turkce
    # kelimeler olabilir; orada 'kisa' adinin 'kisaltma' icinde eslesmemesi
    # gerekir, yoksa kapi gurultuye bogulur ve kimse bakmaz.
    #
    # DOSYADAN gelen adlar (yayin-yasak.txt) ise kullanicinin BILEREK yazdigi,
    # ayirt edici adlardir. Orada ayni gevsetme GERCEK sizinti kacirdi
    # (olculdu 2026-09-18): yasakli bir marka adi, kucuk harfle devam eden bir
    # sonekle birlesince ('<ad>beyin', '<ad>ai') yayinda kaldi. Ayirt edici bir
    # ad icin dogru varsayim ONEK eslesmesidir - arkasina bir harf daha gelmesi
    # o adi masum yapmaz.
    # KELIME SINIRI. Amac: 'kisa' adi 'kisaltma' icinde eslesmesin, ama
    # '<ad>3', '<ad>Panel', '<ad>-panel', '<ad>_v2' EslesSIN.
    #
    # NEDEN ESKI SINIR YETMIYORDU (2026-09-17, olculdu): sondaki
    # '(?![A-Za-z0-9])' rakamla biten proje adlarini ('<ad>3') ve bitisik
    # sonekleri ('<ad>Panel') KACIRIYORDU - ikisi de gercek sizinti bicimi.
    #
    # NEDEN '(?![A-Za-z])' DE YETMEZ: '<ad>Panel'de sonraki karakter 'P', bir
    # harf; look-ahead basarisiz olur ve eslesme yine kacar. (Olculdu.)
    #
    # COZUM: sinir 'sonrasinda KUCUK harf YOK'. Rakam, buyuk harf, tire, alt
    # cizgi, noktalama ve dosya sonu sinir sayilir; yalniz kucuk harfle devam
    # eden kelime ('kisaltma') elenir.
    #
    # (?-i: ...) ZORUNLU: regex IgnoreCase ile derleniyor ve IgnoreCase altinda
    # \p{Ll} / [a-z] BUYUK harfleri de eslerdi - o zaman '<ad>Panel' yine
    # kacardi. Inline '-i' yalniz bu look-ahead icin kucuk/buyuk ayrimini geri
    # acar. \p{Ll} ([a-z] degil): 'etiket' kadar 'etiği' de elensin.
    $sonEk = if ($dosyadanSet.Contains($ad)) { '' } else { '(?!(?-i:\p{Ll}))' }
    $rxYasak += [pscustomobject]@{
        Ad  = $ad
        Rx  = [regex]::new('(?<![A-Za-z0-9])' + [regex]::Escape($ad) + $sonEk, 'IgnoreCase, CultureInvariant')
        Sik = [bool]$dosyadanSet.Contains($ad)
    }
}

# UZANTI POLITIKASI - KARA LISTE, beyaz liste DEGIL.
#
# NEDEN TERS CEVRILDI (2026-09-17): eskiden yalniz
# '\.(ps1|md|json|txt|css|base|canvas|ya?ml)$' taraniyordu. Bugun yayinlanan
# dosyalarin hepsi kapsamdaydi, ama motor/ ya da kurulum/ altina yarin eklenen
# bir .cmd, .mjs, .py, .html, .bat ya da .gitignore TARANMADAN yayinlanirdi -
# ve kimse bunu fark etmezdi. Beyaz liste, unutuldugu anda sessizce sizdirir.
# Simdi kural tersi: bilinen IKILI uzantilar ve ilk 8 KB'inda NUL bayti olan
# dosyalar disinda HER SEY taranir; yeni bir metin uzantisi kendiliginden
# kapsama girer.
$IKILI_UZANTI = @(
    'png', 'jpg', 'jpeg', 'gif', 'ico', 'svgz', 'webp', 'bmp', 'tif', 'tiff',
    'zip', 'gz', '7z', 'rar', 'tar', 'xz',
    'exe', 'dll', 'pdb', 'msi', 'bin', 'dat', 'pdf',
    'woff', 'woff2', 'ttf', 'otf', 'eot',
    'mp4', 'mp3', 'wav', 'ogg', 'webm', 'avi', 'mov'
)
# Cok buyuk dosya icin tavan. TAVANI ASAN ATLANMAZ, BULGU OLARAK RAPORLANIR:
# 'taranamadi' ile 'temiz' ayni sey degil - sessiz atlama yine yanlis negatif
# olurdu. Yayin durur, kullanici o dosyayi elle dogrular.
$MAX_TARAMA_BAYT = 8MB

function Test-Sizinti([string]$Yol, [string]$Rel) {
    $bulgu = New-Object System.Collections.Generic.List[string]

    $uz = ''
    try { $uz = [IO.Path]::GetExtension($Yol) } catch { $uz = '' }
    if ($uz) { $uz = $uz.TrimStart('.') }
    if ($uz -and ($IKILI_UZANTI -contains $uz)) { return $bulgu }   # -contains: harf duyarsiz

    $bilgi = $null
    try { $bilgi = Get-Item -LiteralPath $Yol -Force -ErrorAction Stop }
    catch { $bulgu.Add("TARANAMADI (dosya bilgisi okunamadi): $($_.Exception.Message)"); return $bulgu }
    if ($bilgi.Length -gt $MAX_TARAMA_BAYT) {
        $bulgu.Add("TARANMADI - dosya tavani asiyor ($([math]::Round($bilgi.Length / 1MB, 1)) MB > $($MAX_TARAMA_BAYT / 1MB) MB). Elle dogrula ya da yayindan cikar.")
        return $bulgu
    }

    # IKILI SEZGISI: ilk 8 KB'de NUL bayti. UTF-16 BOM'u olan dosya metindir,
    # NUL'lari kodlamadandir - onu ikili sayip atlamak yanlis negatif olurdu.
    $bas = $null
    try {
        $fs = [IO.File]::OpenRead($Yol)
        try {
            $n = [int][Math]::Min([int64]8192, $fs.Length)
            $bas = New-Object 'byte[]' $n
            if ($n -gt 0) { [void]$fs.Read($bas, 0, $n) }
        } finally { $fs.Dispose() }
    } catch { $bulgu.Add("TARANAMADI (dosya acilamadi): $($_.Exception.Message)"); return $bulgu }

    $kodlama = 'UTF8'
    if ($bas.Length -ge 2) {
        if     ($bas[0] -eq 0xFF -and $bas[1] -eq 0xFE) { $kodlama = 'Unicode' }
        elseif ($bas[0] -eq 0xFE -and $bas[1] -eq 0xFF) { $kodlama = 'BigEndianUnicode' }
    }
    if ($kodlama -eq 'UTF8' -and $bas.Length -gt 0 -and [Array]::IndexOf($bas, [byte]0) -ge 0) {
        return $bulgu   # gercekten ikili
    }

    $icerik = ''
    try { $icerik = Get-Content -LiteralPath $Yol -Raw -Encoding $kodlama }
    catch { $bulgu.Add("TARANAMADI (icerik okunamadi): $($_.Exception.Message)"); return $bulgu }
    if (-not $icerik) { return $bulgu }

    foreach ($m in $rxYol.Matches($icerik)) {
        # YANLIS POZITIF ELEMESI. Motorun kendisi yol ARAYAN regex'ler
        # iceriyor ('/home/[^\\/\s]+/', 'C:/Users/...' gibi). Bunlar birer
        # DESEN KAYNAGIDIR, gercek yol degil. Ilk surumde tarayici bunlari
        # sizinti sayip yayini gereksiz yere durdurdu.
        #
        # Ayirt etme: gercek bir kullanici yolunda regex meta karakteri olmaz.
        if ($m.Value -match '[\[\]\^\$\*\+\?\(\)\|]') { continue }
        # '<ad>' gibi yer tutucular ve '...' ile biten ornekler sorun degil
        if ($m.Value -match '<[^>]*>?$' -or $m.Value -match '\.\.\.$') { continue }
        $bulgu.Add("mutlak yol: $($m.Value)")
    }
    if ($kadi) {
        $rxKadi = [regex]::new('(?<![A-Za-z0-9])' + [regex]::Escape($kadi) + '(?![A-Za-z0-9])', 'IgnoreCase, CultureInvariant')
        if ($rxKadi.IsMatch($icerik)) { $bulgu.Add('kullanici adi geciyor') }
    }
    foreach ($m in $rxMail.Matches($icerik)) { $bulgu.Add("e-posta: $($m.Value)") }

    # Proje / musteri adi. Kaynak: yerel klasor adlari + yayin-yasak.txt.
    foreach ($y in $rxYasak) {
        if ($y.Rx.IsMatch($icerik)) { $bulgu.Add("yerel ad geciyor: $($y.Ad)") }
    }

    # Sir taramasi: motorun kendi maskeleyicisini kullan.
    #
    # DIKKAT 1: Protect-BeyinSecrets bir HASHTABLE doner (Text/Redactions/
    # Failed/FailedPatterns). $r.Count anahtar sayisini (4) verir, eslesme
    # sayisini DEGIL - o kontrol HER dosyayi sizintili gosterirdi.
    # Dogru alan Redactions.
    #
    # DIKKAT 2: lib.ps1 sir DESENLERININ TANIMLANDIGI dosyadir ('sk-ant-...',
    # 'AKIA...' gibi). Kendi desenlerini kacinilmaz olarak esler; taransa
    # yayin her seferinde durur. Bu yuzden yalniz o dosyanin SIR taramasi
    # atlanir - yol, kullanici adi ve e-posta taramasi yine yapilir.
    if ($Rel -notmatch '(?:^|[\\/])lib\.ps1$') {
        try {
            $r = Protect-BeyinSecrets -Text $icerik -Vault $Vault
            if ($r -and $r.Redactions -gt 0) { $bulgu.Add("sir deseni: $($r.Redactions) eslesme") }
            if ($r -and $r.Failed -gt 0) { $bulgu.Add("sir taramasi EKSIK yapildi: $($r.FailedPatterns)") }
        } catch { }
    }

    return ($bulgu | Select-Object -Unique)
}

# ===========================================================================
# TOPLA
# ===========================================================================
$gidecek = New-Object System.Collections.Generic.List[object]

foreach ($f in $IZIN_DOSYA) {
    $y = Join-Path $Vault $f
    if (Test-Path -LiteralPath $y) { $gidecek.Add([pscustomobject]@{ Rel = $f; Tam = $y }) }
}
foreach ($k in $IZIN_KLASOR) {
    $kk = Join-Path $Vault $k
    if (-not (Test-Path -LiteralPath $kk)) { continue }
    foreach ($f in @(Get-ChildItem -LiteralPath $kk -Recurse -File -ErrorAction SilentlyContinue)) {
        $rel = $f.FullName.Substring($Vault.Length).TrimStart('\', '/')
        $parcalar = $rel -split '[\\/]'
        if (@($parcalar | Where-Object { $ASLA -contains $_ }).Count -gt 0) { continue }
        if ($f.Name -like '*.tmp-*' -or $f.Name -like '*.yedek-*') { continue }
        $gidecek.Add([pscustomobject]@{ Rel = $rel; Tam = $f.FullName })
    }
}

"YAYIN HAZIRLIGI"
"  Kaynak vault : $Vault"
"  Hedef klasor : $Hedef"
"  Mod          : $(if ($Uygula) { if ($Gonder) { 'UYGULA + GONDER' } else { 'UYGULA (yerel)' } } else { 'KURU CALISMA' })"
''
"  Gidecek dosya: $($gidecek.Count)"
"  Bos iskelet  : $($ISKELET.Count) klasor"
''

# ===========================================================================
# GUVENLIK TARAMASI
# ===========================================================================
'GUVENLIK TARAMASI'
"  yerel ad listesi: $($YASAK_ADLAR.Count) terim"
"    klasor adlarindan turetilen : $($yasakBilgi.Turetilen)   ($($yasakBilgi.Kokler.Count) kok bakildi)"
"    yayin-yasak.txt             : $($yasakBilgi.Dosyadan)   ($YASAK_DOSYA)  [onek eslesmesi]"
foreach ($ok in $yasakBilgi.Okunamayan) {
    # Kor nokta gorunur olsun: okunamayan bir kok, sessizce bos donen bir kok
    # demektir - o koke ait hicbir proje adi listede yoktur.
    "    UYARI - kok OKUNAMADI (turetim eksik): $ok"
}

# FAIL-CLOSED. NEDEN (2026-09-17, olculdu): liste bos oldugunda tarayici ad
# kontrolunu hic yapmadan 'temiz - N dosyada sizinti bulunamadi' basiyordu.
# Ayni dosya kumesi gercek USERPROFILE ile 4 sizinti buluyor, bos USERPROFILE
# ile 0 buluyordu. 'Kapi calismadi' ile 'kapi temiz dedi' ayni sey degildir;
# yanlis negatif burada gercek zarardir. Liste bossa yayin DURUR.
if ($YASAK_ADLAR.Count -eq 0) {
    ''
    '  DURDURULDU: yasak ad listesi bos - ad taramasi YAPILMADI.'
    '  Yol, kullanici adi, e-posta ve sir taramasi calisabilir; ama PROJE /'
    '  MUSTERI ADI taramasi bu kosuda hic yapilmadi. Bu bir "temiz" sonucu'
    '  degildir.'
    ''
    '  Nasil doldurulur (ikisinden biri yeter):'
    "    1) Elle liste (ONERILEN, tasinabilir): $YASAK_DOSYA"
    '       Satir basi bir terim yaz, "#" ile baslayan satirlar yorumdur.'
    '       Ornek:'
    '         # yayinlanmamasi gereken proje / musteri adlari'
    '         ornek-musteri'
    '         ornek-proje'
    '    2) Turetim: USERPROFILE dogru ayarli olsun ve calisma koklerinden en az'
    '       biri okunabilsin (Desktop / Documents / source\repos, OneDrive'
    '       yonlendirmeleri dahil). Bakilan kokler:'
    foreach ($k in $yasakBilgi.Kokler) { "         $k" }
    ''
    "  Yanlis pozitif cikarsa kacis listesi: $IZIN_DOSYA_AD"
    exit 1
}
$sorunlu = New-Object System.Collections.Generic.List[object]
foreach ($g in $gidecek) {
    $b = Test-Sizinti $g.Tam $g.Rel
    if ($b.Count -gt 0) { $sorunlu.Add([pscustomobject]@{ Rel = $g.Rel; Bulgu = $b }) }
}

if ($sorunlu.Count -eq 0) {
    "  temiz - $($gidecek.Count) dosyada sizinti bulunamadi"
} else {
    "  $($sorunlu.Count) dosyada SIZINTI VAR - yayin durduruldu:"
    foreach ($s in $sorunlu) {
        "    $($s.Rel)"
        foreach ($b in $s.Bulgu) { "        $b" }
    }
    ''
    'Bunlari duzeltmeden yayin yapilmaz. Mutlak yollari degiskene cevir,'
    'kullanici adini <ad> gibi bir yer tutucuyla degistir.'
    'Bulgu "yerel ad geciyor" ise: ad gercekten kisisel mi? Oyleyse kodda'
    'notrlestir (ornek: gercek proje adi yerine ornek-proje). Degilse'
    ('adi ~\.beyin\yayin-izin.txt dosyasina ekle.')
    exit 1
}
''

if (-not $Uygula) {
    'Gidecek dosyalarin ilk 25 tanesi:'
    foreach ($g in ($gidecek | Select-Object -First 25)) { "  $($g.Rel)" }
    if ($gidecek.Count -gt 25) { "  ... ve $($gidecek.Count - 25) dosya daha" }
    ''
    'KURU CALISMA bitti. Uygulamak icin: -Uygula   (uzaga gondermek icin ayrica -Gonder)'
    exit 0
}

# ===========================================================================
# UYGULA
# ===========================================================================
# Hedef vault'un ICINDE olamaz: yayin klasoru temizlenirken vault silinir.
# DIKKAT: bu kontrol YOL SINIRINA bakmali. Duz onek karsilastirmasi
# ('Beyin-motor' -like 'Beyin*') KARDES klasoru de icerde
# sanar; ilk surumde tam olarak bu oldu ve gecerli bir hedef reddedildi.
$vNorm = $Vault.TrimEnd('\', '/')
$hNorm = $Hedef.TrimEnd('\', '/')
if ($hNorm -eq $vNorm -or $hNorm.StartsWith($vNorm + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Hedef vault'un ICINDE (ya da vault'un kendisi) olamaz: $Hedef"
}

# HEDEF ISARETI (2026-09-16). NEDEN: asagidaki temizlik hedefteki HER SEYI
# (.git haric) geri donusum kutusuz, kalici siler; tek koruma 'vault icinde
# olamaz' idi. Yanlis ya da eksik -Hedef ('D:\repos\beyin-motor' yerine
# 'D:\repos', yanlis cwd'den '.', 'Documents') o klasorun tamamini silerdi ve
# -Uygula kuru calisma yapilmadan dogrudan verilebiliyor. Simdi temizlik yalniz
# su hedeflerde yapilir:
#   1. yayinla'nin daha once biraktigi .beyin-yayin isareti varsa
#   2. hedef bossa (ya da yalniz .git varsa)
#   3. -Uzak verildiyse ve hedefin .git origin'i ona esitse
#   4. eski yayin parmak izi: .git + .beyin-version + kurulum\kur.ps1 + motor\hooks
#      (isaret dosyasindan onceki surumlerin urettigi klasorler / klonlar icin)
#      VE vault kopyasi degil: kurulum\DEPO-README.md YOK (yayinla onu hedeften
#      siler; her vault'ta vardir) ve 85-daylogs altinda .md yok. NEDEN
#      (2026-09-16): o dort dosya vault'un tam kopyasinda / yedeginde
#      (ornek D:\Yedek\Beyin-kopya) ve junction/subst ile ulasilan canli
#      vault'ta da vardir; yukaridaki dize tabanli 'vault icinde olamaz'
#      kontrolu takma ad yolunu yakalayamaz. Ayirt edici olmadan yanlis -Hedef
#      yine tum notlari silerdi - korumanin amaci tam olarak buydu.
# Aksi halde yayin DURUR, hicbir sey silinmez. Isaret her yayin sonunda yazilir
# ve .gitignore'dadir: yerel, yayincinin yazdigi bir kanit; depoya girmez.
$ISARET = '.beyin-yayin'
function Test-YayinHedefi([string]$Yol) {
    if (-not (Test-Path -LiteralPath $Yol)) { return 'yeni klasor' }
    if (Test-Path -LiteralPath (Join-Path $Yol $ISARET)) { return "$ISARET isareti var" }
    $icerik = @(Get-ChildItem -LiteralPath $Yol -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne '.git' })
    if ($icerik.Count -eq 0) { return 'bos klasor' }
    $gitVar = Test-Path -LiteralPath (Join-Path $Yol '.git')
    if ($gitVar -and $Uzak -and (Get-Command git -ErrorAction SilentlyContinue)) {
        $origin = ''
        try { $origin = [string](& git -C $Yol remote get-url origin 2>$null) } catch { }
        if ($origin -and ($origin.Trim().TrimEnd('/') -eq $Uzak.Trim().TrimEnd('/'))) { return 'origin = -Uzak' }
    }
    # Ayirt edici (bkz. madde 4): vault kopyasinda DEPO-README.md ve gunluk log
    # vardir, yayin klasorunde ikisi de yoktur. 85-daylogs hedefte hic yoksa
    # sayim 0'dir (eski yayinlar iskeleti tasimayabilir).
    if ($gitVar -and (Test-Path -LiteralPath (Join-Path $Yol '.beyin-version')) -and
        (Test-Path -LiteralPath (Join-Path $Yol 'kurulum\kur.ps1')) -and
        (Test-Path -LiteralPath (Join-Path $Yol 'motor\hooks')) -and
        -not (Test-Path -LiteralPath (Join-Path $Yol 'kurulum\DEPO-README.md')) -and
        @(Get-ChildItem -LiteralPath (Join-Path $Yol '85-daylogs') -Filter '*.md' -File -ErrorAction SilentlyContinue).Count -eq 0) {
        return 'eski yayin parmak izi (.git + .beyin-version + kurulum + motor; DEPO-README.md ve gunluk log yok = vault kopyasi degil)'
    }
    return ''
}
$hedefKaniti = Test-YayinHedefi $Hedef
if (-not $hedefKaniti) {
    throw "Hedef bir beyin yayin klasoru gibi gorunmuyor, TEMIZLENMEDI: $Hedef  (bos degil; icinde $ISARET isareti yok ve .git+.beyin-version+kurulum\kur.ps1 parmak izi ya yok ya da bir VAULT KOPYASINA ait: kurulum\DEPO-README.md ya da 85-daylogs\*.md var). Dogru -Hedef ver ya da bos bir klasor kullan."
}

'YAYIN KLASORU HAZIRLANIYOR'
"  hedef kaniti : $hedefKaniti"
if (-not (Test-Path -LiteralPath $Hedef)) { New-Item -ItemType Directory -Force -Path $Hedef | Out-Null }

# Eski icerigi temizle (.git HARIC - gecmis korunur)
foreach ($it in @(Get-ChildItem -LiteralPath $Hedef -Force -ErrorAction SilentlyContinue)) {
    if ($it.Name -eq '.git') { continue }
    Remove-Item -LiteralPath $it.FullName -Recurse -Force -ErrorAction SilentlyContinue
}

foreach ($g in $gidecek) {
    $h = Join-Path $Hedef $g.Rel
    $hd = Split-Path $h -Parent
    if (-not (Test-Path -LiteralPath $hd)) { New-Item -ItemType Directory -Force -Path $hd | Out-Null }
    Copy-Item -LiteralPath $g.Tam -Destination $h -Force
}
"  $($gidecek.Count) dosya kopyalandi"

# Bos iskelet + .gitkeep
foreach ($k in $ISKELET) {
    $kk = Join-Path $Hedef $k
    if (-not (Test-Path -LiteralPath $kk)) { New-Item -ItemType Directory -Force -Path $kk | Out-Null }
    Write-BeyinText -Path (Join-Path $kk '.gitkeep') -Text ''
}
"  $($ISKELET.Count) bos iskelet klasoru"

# .gitignore: yanlislikla not commit edilmesin
$gitignore = @'
# Beyin motor deposu - BURAYA NOT GIRMEZ.
#
# Bu depo yalnizca motoru, kurulumu ve BOS vault iskeletini tasir. Kisisel
# notlar, gunluk loglar ve derlenmis kavramlar bilerek DISARIDA birakilmistir:
# beynin icerigi kullanicinin makinesinde kalir.
#
# Asagidaki desenler, bu depo bir vault olarak kullanilirsa (klonla + kur.ps1)
# uretilen icerigin yanlislikla geri commit edilmesini engeller.

# Makine bolgeleri - motor uretir
85-daylogs/*
!85-daylogs/.gitkeep
86-compiled/*
!86-compiled/.gitkeep
90-archive/*
!90-archive/.gitkeep

# Kuratorlu bolgeler - kullanicinin kendi icerigi
00-inbox/*
!00-inbox/.gitkeep
20-goals/*
!20-goals/.gitkeep
30-projects/*
!30-projects/.gitkeep
40-knowledge/*
!40-knowledge/.gitkeep
50-research/*
!50-research/.gitkeep
60-decisions/*
!60-decisions/.gitkeep
70-personal/*
!70-personal/.gitkeep
80-memory/*
!80-memory/.gitkeep
10-command-center/*
!10-command-center/.gitkeep

# Motor durumu, yedekler, gecici dosyalar
motor/scripts/.state/
motor/hooks/.state/
.brain/
.obsidian/workspace*.json
.obsidian/cache/
*.tmp-*
*.yedek-*
.beyin-yayin
'@
Write-BeyinText -Path (Join-Path $Hedef '.gitignore') -Text ($gitignore + "`r`n")
'  .gitignore yazildi'

# Yayin isareti (bkz. Test-YayinHedefi): bu klasor yayinla.ps1 tarafindan
# yonetilir, bir sonraki yayin icerigi (.git haric) silip yeniden yazar.
$isaretSurum = if (Test-Path -LiteralPath (Join-Path $Vault '.beyin-version')) {
    (Get-Content -LiteralPath (Join-Path $Vault '.beyin-version') -Raw).Trim()
} else { 'bilinmiyor' }
$isaretMetin = "beyin yayin klasoru - yayinla.ps1 her yayinda bu klasorun icerigini (.git haric) silip yeniden yazar. Elle dosya koyma.`n" +
               "surum: $isaretSurum`n" +
               "son yayin: $((Get-Date).ToString('yyyy-MM-ddTHH:mm:ssK', [Globalization.CultureInfo]::InvariantCulture))`n"
Write-BeyinText -Path (Join-Path $Hedef $ISARET) -Text $isaretMetin
"  $ISARET isareti yazildi"

# Depo README'si: kurulum\DEPO-README.md -> depo kokunde README.md.
# Vault'un kendi README.md'si KISISELDIR ve bilerek gonderilmez.
$depoReadme = Join-Path $Vault 'kurulum\DEPO-README.md'
if (Test-Path -LiteralPath $depoReadme) {
    Copy-Item -LiteralPath $depoReadme -Destination (Join-Path $Hedef 'README.md') -Force
    Remove-Item -LiteralPath (Join-Path $Hedef 'kurulum\DEPO-README.md') -Force -ErrorAction SilentlyContinue
    '  README.md yazildi (kurulum\DEPO-README.md kaynagindan)'
} else {
    '  UYARI: kurulum\DEPO-README.md yok - depo README''siz gidiyor'
}

# ===========================================================================
# GIT
# ===========================================================================
''
'GIT'
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { '  git bulunamadi - commit atlandi'; exit 0 }

if (-not (Test-Path -LiteralPath (Join-Path $Hedef '.git'))) {
    & git -C $Hedef init -q
    & git -C $Hedef symbolic-ref HEAD refs/heads/main
    '  yeni depo baslatildi (dal: main, TEMIZ gecmis)'
}
if ($Uzak) {
    # NEDEN (2026-09-16): eskiden 'remote remove origin 2>$null' + 'remote add'
    # idi. $ErrorActionPreference='Stop' altinda yerli komutun stderr'i
    # ('error: No such remote: origin') 2>$null'a RAGMEN NativeCommandError
    # olarak betigi durduruyor (bu makinede olculdu). Bos/yeni hedefe -Uzak ile
    # ilk yayin 'remote add', 'add -A' ve commit'e hic gelmiyordu. Simdi once
    # bakilir: origin varsa adresi guncellenir, yoksa eklenir; stderr'e yazan
    # komut kalmaz. ('git remote' uzak yokken bos doner, hata yazmaz.)
    $uzakAdlar = @(& git -C $Hedef remote)
    if ($uzakAdlar -contains 'origin') {
        & git -C $Hedef remote set-url origin $Uzak
    } else {
        & git -C $Hedef remote add origin $Uzak
    }
    "  uzak ayarlandi: $Uzak"
}

& git -C $Hedef add -A
$degisiklik = @(& git -C $Hedef status --porcelain)
if ($degisiklik.Count -eq 0) {
    '  degisiklik yok - commit atlandi'
} else {
    $surum = if (Test-Path -LiteralPath (Join-Path $Vault '.beyin-version')) {
        (Get-Content -LiteralPath (Join-Path $Vault '.beyin-version') -Raw).Trim()
    } else { 'bilinmiyor' }
    $mesaj = "motor $surum - $($gidecek.Count) dosya`n`nBeyin motoru + kurulum katmani. Notlar bilerek yok."
    & git -C $Hedef -c user.name='beyin' -c user.email='beyin@localhost' commit -q -m $mesaj
    "  commit: $($degisiklik.Count) degisiklik"
}

if ($Gonder) {
    $uzaklar = @(& git -C $Hedef remote)
    if ($uzaklar.Count -eq 0) {
        '  UZAK DEPO YOK - push atlandi. -Uzak "https://github.com/<kullanici>/<depo>.git" ile ayarla.'
    } else {
        & git -C $Hedef push -u origin main
        if ($LASTEXITCODE -eq 0) { '  push TAMAM' } else { '  push BASARISIZ (yukaridaki hataya bak)' }
    }
}

''
"YAYIN HAZIR: $Hedef"
Write-BeyinLog -Vault $Vault -Message "yayinla: $($gidecek.Count) dosya -> $Hedef$(if ($Gonder) { ' (push)' } else { '' })"
Write-BeyinMakbuz -Paths $p -Script 'yayinla' -Outcome 'YAYIN_OK' -Note "$($gidecek.Count) dosya$(if ($Gonder) { ', push' } else { '' })"
