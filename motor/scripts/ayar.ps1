# ayar.ps1 - Motor ayarlarinin TEK MERKEZI: goster, yaz, sil.
#
# NEDEN: her ayar ayri bir ortam degiskeniydi. Kullanici bunlari elle 'setx' ile
# kurmak zorundaydi, degisiklik yeni bir konsol acmadan gorunmuyordu ve hangi
# ayarlarin VAR OLDUGUNU gosteren tek bir yer yoktu (envanter kaynak kodun
# icinde dagiliyordu). Artik tek dosya: ~\.beyin\ayar.json.
#
# Oncelik (lib.ps1 -> Get-BeyinAyar): ortam degiskeni > ayar dosyasi > varsayilan.
# Ortam degiskeni USTTE kalir ki tek seferlik override mumkun olsun
# (ornek: doktor -Derin iki ozetleyici arka ucunu ayri ayri sinar).
#
# Kullanim:
#   beyin ayar                        tum ayarlar: etkin deger + kaynak
#   beyin ayar -Liste                 ayni
#   beyin ayar -Json                  tamami makine okunur JSON
#   beyin ayar BEYIN_OZETLEYICI       yalniz o ayarin detayi
#   beyin ayar ozetleyici codex       yaz (BEYIN_ oneki ve buyuk/kucuk harf serbest)
#   beyin ayar ozetleyici -Sil        ayar dosyasindan kaldir (varsayilana doner)
#   beyin ayar BEYIN_VAULT <yol> -Zorla   motor imzasi tasimayan klasoru bilerek vault yap
#
# BEYIN_VAULT OZELDIR: ayar.json'a YAZILMAZ. Vault yolunun tek kaydi
# ~\.beyin\vault.txt'tir (kurulum onu yazar, launcher onu okur); burada yalniz
# GOSTERILIR, degistirilirse vault.txt guncellenir.
#
# YAZIM ASLA VARSAYILMAZ (2026-09-17). Bu betik $ErrorActionPreference =
# 'SilentlyContinue' altinda calisiyor ve basari mesaji + makbuz KOSULSUZ
# basiliyordu. Olculdu: ayar.json baska bir surecte FileShare.None ile acikken
# 'beyin ayar ozetleyici codex' ekrana "BEYIN_OZETLEYICI = codex" yazip exit 0
# verdi, dosyanin icerigi degismemisti. Artik her yazimdan sonra dosya GERI
# OKUNUR ve beklenenle karsilastirilir; uymuyorsa HATA + sifir-disi cikis +
# AYAR_YAZILAMADI makbuzu.

# NEDEN [CmdletBinding(PositionalBinding=$false)]: $Vault ilk bildirilen parametre
# oldugu icin ortu bindirme altinda 0. konumu kapar ve `ayar ozetleyici codex`
# cagrisinda 'ozetleyici' sessizce Vault'a baglanirdi (ayni tuzak niyet.ps1'de
# olculdu). Konumsal baglama kapatilir: yalniz Position=0/1 tasiyan $Ad ve
# $Deger konumsaldir, $Vault adli kalir.
[CmdletBinding(PositionalBinding=$false)]
param(
    [string]$Vault = '',
    [Parameter(Position=0)][string]$Ad = '',
    [Parameter(Position=1)][string]$Deger = '',
    # A4 (2026-09-17 bagimsiz denetimi): 'deger VERILMEDI' ile 'deger BOS
    # VERILDI' ayrimi. Bos dizge bir native cagride (`& powershell -File ...`)
    # SESSIZCE DUSER, yani dagitici -Deger "" gecirse bile buraya hicbir sey
    # varmaz ve betik 'deger yok' dalina girer. Olculdu: `beyin ayar codex_model ""`
    # exit 0 verip ayari YAZMAK YERINE GOSTERIYORDU - oysa o ayarin kendi
    # aciklamasi "bos = codex varsayilani" diyor, yani bos MESRU bir deger.
    # Bu yuzden niyet ayri bir ANAHTARLA tasinir; anahtar duser gibi bir sey yok.
    [switch]$BosDeger,
    [switch]$Sil,
    [switch]$Json,
    [switch]$Liste,
    [switch]$Zorla
)

$ErrorActionPreference = 'SilentlyContinue'
# NEDEN burada: [CmdletBinding] altinda `powershell -File` param varsayilanlarini
# degerlendirirken $PSScriptRoot BOS gelir (niyet.ps1'de olculdu), govdede dolu.
if (-not $Vault) { $Vault = $(if ($env:BEYIN_VAULT) { $env:BEYIN_VAULT } else { Split-Path (Split-Path $PSScriptRoot -Parent) -Parent }) }
$vaultOk = $false
try { $vaultOk = [bool]($Vault -and (Test-Path -LiteralPath $Vault -PathType Container) -and (Test-Path -LiteralPath (Join-Path $Vault 'motor\hooks\lib.ps1') -PathType Leaf)) } catch { }
if (-not $vaultOk) {
    Write-Output "HATA: vault degil (motor\hooks\lib.ps1 yok): '$Vault'  - ayar adi konumsaldir, vault icin -Vault kullan"
    exit 2
}
. (Join-Path $Vault 'motor\hooks\lib.ps1')
$p = Get-BeyinPaths -Vault $Vault

$ayarDosyasi = Join-Path $env:USERPROFILE '.beyin\ayar.json'
$vaultKayit  = Join-Path $env:USERPROFILE '.beyin\vault.txt'

# ---------------------------------------------------------------------------
# ENVANTER - ARTIK BURADA DEGIL.
# Liste ve deger kurallari lib.ps1'de (Get-BeyinAyarKayitlari /
# Test-BeyinAyarDeger). Buradaki kopya, motorun gercekte uyguladigi kurallardan
# ayrisabiliyordu; doktor'unki ucuncu bir kopyaydi. Yeni ayar eklerken TEK yer:
# lib.ps1 -> Get-BeyinAyarKayitlari.
# ---------------------------------------------------------------------------
$kayitlar = @(Get-BeyinAyarKayitlari)

# Motorun kendi kullandigi, kullaniciya ayar olarak SUNULMAYAN degiskenler.
$motorIci = @(
    @{ Ad = 'BEYIN_AGENT';  Aciklama = 'kancayi calistiran ajan (launcher ayarlar)' },
    @{ Ad = 'BEYIN_CHILD';  Aciklama = 'alt surec bayragi: kanca ozyinelemesini keser' },
    @{ Ad = 'BEYIN_KAYNAK'; Aciklama = 'makbuz kaynak etiketi (hook/cli/zamanli)' }
)

function Kayit([string]$N) {
    foreach ($k in $kayitlar) { if ($k.Ad -eq $N) { return $k } }
    return $null
}

function Coz-Ad([string]$Girdi) {
    # Buyuk/kucuk harf duyarsiz; 'ozetleyici' gibi oneksiz kisa ad da kabul.
    # ToUpperInvariant SART: tr-TR kulturunde 'i'.ToUpper() noktali I uretir ve
    # ad eslesmesi sessizce basarisiz olur.
    $n = ([string]$Girdi).Trim()
    if (-not $n) { return '' }
    $n = $n.Replace('-', '_').ToUpperInvariant()
    if (-not $n.StartsWith('BEYIN_')) { $n = 'BEYIN_' + $n }
    return $n
}

function Oku-Ayar {
    # Ucuncu bir ayristirici kopyasi BURADA DURUYORDU. Artik motorun kendi
    # fonksiyonu cagriliyor: ayar.ps1'in gordugu ile kancalarin gordugu
    # dosyanin AYNI olmasinin tek garantisi budur.
    # Onbellek UYARISI: Get-BeyinAyarTablo surec basina bir kez okur, o yuzden
    # her yazimdan sonra Clear-BeyinAyarCache cagrilir (bkz. Yaz-Ayar).
    # KOPYA doner: donen sozluk onbellegin TA KENDISI; cagiran onu degistirip
    # (Remove/ekleme) yaziyor, onbellegi yerinde bozmasin.
    $t = @{}
    foreach ($k in @((Get-BeyinAyarTablo).Keys)) { $t[[string]$k] = [string](Get-BeyinAyarTablo)[$k] }
    return $t
}

function Ayar-Okunabilir {
    # $true = ayar.json ya YOK ya da GERCEKTEN okunabiliyor.
    #
    # Get-BeyinAyarTablo bilerek FAIL-OPEN'dir: kilitli ya da bozuk dosyada BOS
    # sozluk doner (kancalar bir ayar dosyasi yuzunden cokmemeli). Ama 'beyin
    # ayar' icin o bosluk YANILTICIDIR - "ayar yok" gibi gorunur:
    #   - yazarken: dosyadaki DIGER ayarlari sessizce silerdik,
    #   - -Sil'de : "Ayar dosyasinda zaten yok" diye YALAN soylerdik (olculdu:
    #               dosya FileShare.None ile acikken tam olarak bu cikti, exit 0).
    # Bu yuzden bosluk gorulen her yerde once dosyanin okunabildigi kanitlanir.
    if (-not [System.IO.File]::Exists($ayarDosyasi)) { return $true }
    try {
        [void][System.IO.File]::ReadAllText($ayarDosyasi, [System.Text.Encoding]::UTF8)
        return $true
    } catch { }
    return $false
}

function Yaz-Ayar([hashtable]$Tablo) {
    # $true  = dosyanin DISKTEKI GERCEK icerigi $Tablo ile birebir ayni
    # $false = yazim olmadi / eksik oldu -> cagiran HATA basmali, basari DEGIL
    #
    # ConvertTo-Json KULLANMAZ: dosyanin bicimi Get-BeyinAyarTablo'nun satir
    # regex'iyle sozlesmelidir (her satir tek anahtar). Sozluk bosalirsa dosya
    # silinir; o durumda dogrulama "dosya gercekten gitti mi" olur.
    #
    # Geri okuma NEDEN sart: Write-BeyinText hedef kilitliyken sessizce
    # basarisiz olabiliyor ve bu betik SilentlyContinue altinda. Salt-okunur
    # ATTRIBUTE sorun degil (Replace yolu onu asar) - sorun PAYLASIM KILIDI:
    # OneDrive/Dropbox senkronu, antivirus, acik editor, es zamanli ikinci
    # 'beyin ayar'.
    $adlar = @(@($Tablo.Keys) | Sort-Object)
    if ($adlar.Count -eq 0) {
        try {
            if (Test-Path -LiteralPath $ayarDosyasi) { Remove-Item -LiteralPath $ayarDosyasi -Force -ErrorAction Stop }
        } catch { }
        Clear-BeyinAyarCache
        return (-not [System.IO.File]::Exists($ayarDosyasi))
    }
    $sat = New-Object System.Collections.Generic.List[string]
    $sat.Add('{')
    for ($i = 0; $i -lt $adlar.Count; $i++) {
        $k = [string]$adlar[$i]
        $v = ([string]$Tablo[$k]).Replace('\', '\\').Replace('"', '\"')
        $vir = ''
        if ($i -lt ($adlar.Count - 1)) { $vir = ',' }
        $sat.Add(('  "{0}": "{1}"{2}' -f $k, $v, $vir))
    }
    $sat.Add('}')
    try {
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $ayarDosyasi) | Out-Null
        # UTF-8 BOM'suz (JSON standardi BOM istemez) + CRLF; Write-BeyinText atomiktir.
        Write-BeyinText -Path $ayarDosyasi -Text (($sat -join "`r`n") + "`r`n")
    } catch { }

    # GERI OKUMA - motorun gercekte kullanacagi ayristiriciyla, taze.
    Clear-BeyinAyarCache
    $gercek = Get-BeyinAyarTablo
    Clear-BeyinAyarCache
    if ($null -eq $gercek) { return $false }
    if ($gercek.Count -ne $adlar.Count) { return $false }
    foreach ($k2 in $adlar) {
        if (-not $gercek.ContainsKey($k2)) { return $false }
        if (([string]$gercek[$k2]) -ne ([string]$Tablo[$k2])) { return $false }
    }
    return $true
}

function Yazilamadi([string]$Anahtar, [string]$Neden) {
    # Yazimin GERCEKLESMEDIGI tek cikis noktasi. Basari mesaji burada ASLA
    # basilmaz ve makbuz AYAR_YAZILAMADI olur.
    Write-Output "HATA: $Anahtar yazilamadi - $Neden"
    Write-Output "  hedef: $ayarDosyasi"
    Write-Output '  Dosya baska bir surecte kilitli olabilir: OneDrive/Dropbox senkronu, antivirus,'
    Write-Output '  acik bir editor ya da es zamanli ikinci bir "beyin ayar". Kapatip tekrar dene.'
    Write-BeyinLog -Vault $Vault -Message "ayar: $Anahtar YAZILAMADI ($Neden)"
    Write-BeyinMakbuz -Paths $p -Script 'ayar' -Outcome 'AYAR_YAZILAMADI' -Key $Anahtar -Reason $Neden
}

function Etkin([string]$N) {
    # @{ Deger; Kaynak } - oncelik zinciri, lib.ps1 ile ayni sira.
    $ov = [Environment]::GetEnvironmentVariable($N, 'Process')
    if ($ov) { return @{ Deger = [string]$ov; Kaynak = 'ortam degiskeni' } }
    if ($N -eq 'BEYIN_VAULT') {
        try {
            if (Test-Path -LiteralPath $vaultKayit) {
                $y = (Get-Content -LiteralPath $vaultKayit -Raw -Encoding UTF8).Trim()
                if ($y) { return @{ Deger = $y; Kaynak = 'vault.txt' } }
            }
        } catch { }
    } else {
        $t = Oku-Ayar
        if ($t.ContainsKey($N)) {
            $d = [string]$t[$N]
            if ($d) { return @{ Deger = $d; Kaynak = 'ayar dosyasi' } }
        }
    }
    $k = Kayit $N
    $vr = ''
    if ($k) { $vr = [string]$k.Varsayilan }
    return @{ Deger = $vr; Kaynak = 'varsayilan' }
}

function Dogrula([string]$N, [string]$D, [switch]$ZorlaGec) {
    # @{ Ok; Deger; Hata; Uyari } - YAZMADAN once calisir. Gecersiz = yazma yok.
    #
    # KURALLARIN GOVDESI BURADA DEGIL. lib.ps1 -> Test-BeyinAyarDeger tek
    # kaynaktir; Get-BeyinAyarDenetim (ve onun uzerinden doktor) diskteki
    # dosyayi AYNI kurallarla olcer. Kurali burada tekrar yazma - iki kopya,
    # daha once tam olarak boyle ayrisip doktor'u yanlis yesil gostermisti.
    #
    # DIKKAT: anahtarin adi '$ZorlaGec'; '$Zorla' YAZILAMAZ - PS 5.1'de degisken
    # adlari harf duyarsizdir ve '$Zorla' betigin kendi [switch]$Zorla
    # parametresiyle AYNI addir.
    return (Test-BeyinAyarDeger -Ad $N -Deger $D -Zorla:$ZorlaGec)
}

function Kirp([string]$S, [int]$N) {
    $x = [string]$S
    if ($x.Length -le $N) { return $x }
    return ($x.Substring(0, $N - 1) + '~')
}

function Goster([string]$D) {
    if ($D) { return $D }
    return '(bos)'
}

$surum = Get-BeyinVersion -Vault $Vault
if (-not $surum) { $surum = '?' }
$dosyaVar = 'yok'
if (Test-Path -LiteralPath $ayarDosyasi) { $dosyaVar = 'var' }

# ---------------------------------------------------------------------------
# -Json: tamami makine okunur (salt okunur yol)
# ---------------------------------------------------------------------------
if ($Json) {
    # DIKKAT: bu degiskene '$liste' ADI VERILEMEZ - PS 5.1'de degisken adlari harf
    # duyarsizdir ve '$liste' betik kapsaminda '-Liste' anahtarinin TA KENDISIDIR.
    # Olculdu: liste atamasi [switch]'e donusuyor, JSON 'ayarlar' alani
    # [{"IsPresent":false}] cikiyordu.
    $cikti = New-Object System.Collections.Generic.List[object]
    foreach ($k in $kayitlar) {
        $e = Etkin $k.Ad
        $cikti.Add([ordered]@{
            ad         = [string]$k.Ad
            deger      = [string]$e.Deger
            kaynak     = [string]$e.Kaynak
            varsayilan = [string]$k.Varsayilan
            secenekler = @($k.Secenekler)
            aciklama   = [string]$k.Aciklama
            # Kural ENVANTERDEN gelir (lib.ps1 'Dosyaya' alani), burada elle degil.
            duzenlenir = [bool](Test-BeyinAyarDosyaya -Ad $k.Ad)
        })
    }
    [ordered]@{
        v          = 1
        motor      = [string]$surum
        vault      = [string]$Vault
        dosya      = [string]$ayarDosyasi
        dosyaVar   = [bool](Test-Path -LiteralPath $ayarDosyasi)
        vaultKayit = [string]$vaultKayit
        # DIKKAT: '@($cikti)' YAZILAMAZ. PS 5.1'de bir List[object]'i @(...) ile sarip
        # sozluk LITERALI icine koymak 'Argument types do not match' firlatir ve
        # $ErrorActionPreference='SilentlyContinue' altinda betik SESSIZCE hicbir sey
        # basmadan exit 0 verir (olculdu: -Json bos cikti). .ToArray() calisiyor.
        ayarlar    = $cikti.ToArray()
    } | ConvertTo-Json -Depth 6
    exit 0
}

# ---------------------------------------------------------------------------
# Liste (argumansiz ya da -Liste)
# ---------------------------------------------------------------------------
if ($Liste -or (-not $Ad)) {
    if ($Sil -or $Deger -or $BosDeger) {
        Write-Output 'HATA: ayar adi verilmedi. Kullanim: beyin ayar <ad> <deger>  |  beyin ayar <ad> -Sil'
        exit 1
    }
    "BEYIN AYARLARI   (motor $surum)"
    "  ayar dosyasi : $ayarDosyasi   [$dosyaVar]"
    "  vault kaydi  : $vaultKayit"
    ''
    '{0,-18} {1,-32} {2,-15} {3}' -f 'AD', 'ETKIN DEGER', 'KAYNAK', 'ACIKLAMA'
    foreach ($k in $kayitlar) {
        $e = Etkin $k.Ad
        '{0,-18} {1,-32} {2,-15} {3}' -f $k.Ad, (Kirp (Goster $e.Deger) 32), $e.Kaynak, $k.Aciklama
        if (@($k.Secenekler).Count -gt 0) {
            '{0,-18} {1}' -f '', ('secenekler: ' + (@($k.Secenekler) -join ' | '))
        }
    }
    ''
    'MOTOR ICI (salt okunur, ayar degil)'
    foreach ($m in $motorIci) {
        $mv = [Environment]::GetEnvironmentVariable($m.Ad, 'Process')
        if (-not $mv) { $mv = '(ayarlanmamis)' }
        '  {0,-16} {1,-14} {2}' -f $m.Ad, $mv, $m.Aciklama
    }
    ''
    'Oncelik: ortam degiskeni > ayar dosyasi > varsayilan  (ortam degiskeni tek seferlik override icin ustte)'
    'Yaz: beyin ayar <ad> <deger>    Sil: beyin ayar <ad> -Sil    Detay: beyin ayar <ad>    JSON: beyin ayar -Json'
    'Degisiklik BIR SONRAKI OTURUMDAN itibaren gecerli: kancalar ayari kendi surecinde, acilista okur.'
    exit 0
}

# ---------------------------------------------------------------------------
# Tek ayar: ad cozumu
# ---------------------------------------------------------------------------
$hedef = Coz-Ad $Ad
$kyt = Kayit $hedef
if (-not $kyt) {
    Write-Output "HATA: bilinmeyen ayar: '$Ad'"
    Write-Output 'Gecerli adlar:'
    foreach ($k in $kayitlar) { Write-Output ('  {0,-18} {1}' -f $k.Ad, $k.Aciklama) }
    Write-Output "('BEYIN_' oneki ve buyuk/kucuk harf serbest: beyin ayar ozetleyici codex)"
    Write-BeyinLog -Vault $Vault -Message "ayar: bilinmeyen ad '$Ad'"
    Write-BeyinMakbuz -Paths $p -Script 'ayar' -Outcome 'AYAR_GECERSIZ' -Key ([string]$Ad) -Reason 'bilinmeyen ad'
    exit 1
}

# ---------------------------------------------------------------------------
# -Sil
# ---------------------------------------------------------------------------
if ($Sil) {
    if (-not (Test-BeyinAyarDosyaya -Ad $hedef)) {
        Write-Output 'HATA: BEYIN_VAULT silinemez - vault yolunun tek kaydi vault.txt ve motor onsuz calismaz.'
        Write-Output 'Baska bir vault icin deger vererek yaz: beyin ayar BEYIN_VAULT <klasor yolu>'
        Write-BeyinMakbuz -Paths $p -Script 'ayar' -Outcome 'AYAR_GECERSIZ' -Key $hedef -Reason 'vault silinemez'
        exit 1
    }
    $t = Oku-Ayar
    if (-not (Ayar-Okunabilir)) {
        Yazilamadi $hedef 'ayar dosyasi OKUNAMADI (kilitli); silinip silinmedigi bilinemez'
        exit 3
    }
    if (-not $t.ContainsKey($hedef)) {
        $e0 = Etkin $hedef
        "Ayar dosyasinda zaten yok: $hedef   (etkin deger: $(Goster $e0.Deger), kaynak: $($e0.Kaynak))"
        exit 0
    }
    $eski = [string]$t[$hedef]
    $t.Remove($hedef)
    # SILME DE DOGRULANIR: anahtar gercekten gitti mi; sozluk bosaldiysa dosya
    # gercekten silindi mi. Aksi halde "kaldirildi" diyip hicbir sey yapmamis
    # olurduk (ayni sessiz yol yazimda olculdu).
    if (-not (Yaz-Ayar $t)) {
        Yazilamadi $hedef 'silme sonrasi geri okuma uyusmadi (anahtar hala dosyada)'
        exit 3
    }
    Write-BeyinLog -Vault $Vault -Message "ayar: $hedef silindi (eski deger: $eski)"
    Write-BeyinMakbuz -Paths $p -Script 'ayar' -Outcome 'AYAR_SILINDI' -Key $hedef -Note "$eski -> varsayilan ($($kyt.Varsayilan))"
    $e = Etkin $hedef
    "$hedef ayar dosyasindan kaldirildi."
    "  etkin deger: $(Goster $e.Deger)   (kaynak: $($e.Kaynak))"
    if ($e.Kaynak -eq 'ortam degiskeni') { '  DIKKAT: ayni adli bir ortam degiskeni hala ayari eziyor; o oncelikli.' }
    'Bir sonraki oturumdan itibaren gecerli (kancalar ayari kendi surecinde okur).'
    exit 0
}

# ---------------------------------------------------------------------------
# BOS DEGER - MESRU MU? (A4, 2026-09-17)
# ---------------------------------------------------------------------------
# OLCULDU (duzeltme oncesi): `beyin ayar codex_model ""` exit 0 veriyor ve ayari
# YAZMAK YERINE GOSTERIYORDU - yani bos bir degerle gelen kullanici hicbir sey
# olmadigini anlamiyordu. Artik bos deger ACIKCA ele aliniyor.
#
# YAZILAMIYOR, VE BU BILINCLI: bos degerin saklanmasini engelleyen kural bu
# betikte degil, motorun TEK dogrulama noktasindadir (lib.ps1 ->
# Test-BeyinAyarDeger: "bos deger yazilamaz; varsayilana dondurmek icin -Sil").
# Okuma yolu da ayni sekilde davranir (Get-BeyinAyar dosyadaki bos degeri yok
# sayip varsayilana duser). Kurali burada TEKRAR YAZMAK iki kopya demek olurdu -
# bu dosyanin kendi notu bunu yasakliyor ve doktor'un denetimi (Get-BeyinAyarDenetim)
# diskteki degeri AYNI kuralla olctugu icin yazilan bos deger orada 'gecersiz'
# gorunurdu. Bu yuzden kapi burada: sesli hata + dogru komut.
if ($BosDeger -and -not $Deger) {
    if ([string]$kyt.Varsayilan) {
        Write-Output "HATA: '$hedef' icin BOS deger saklanamaz - motor dosyadaki bos degeri yok sayar,"
        Write-Output "      varsayilan devreye girer: '$($kyt.Varsayilan)'  (lib.ps1 -> Get-BeyinAyar)"
        Write-Output "  Varsayilana donmek icin:  beyin ayar $hedef -Sil"
    } else {
        Write-Output "HATA: '$hedef' icin bos deger DOSYAYA yazilamaz (lib.ps1 -> Test-BeyinAyarDeger)."
        Write-Output "      Ama istedigin sonuc zaten mumkun: bu ayarin varsayilani da bos"
        Write-Output "      ($($kyt.Aciklama)), yani ayari kaldirmak bos degerin TA KENDISIDIR."
        Write-Output "  Sunu calistir:  beyin ayar $hedef -Sil     -> etkin deger: (bos)"
    }
    Write-BeyinLog -Vault $Vault -Message "ayar: $hedef bos deger reddedildi"
    Write-BeyinMakbuz -Paths $p -Script 'ayar' -Outcome 'AYAR_GECERSIZ' -Key $hedef -Reason 'bos deger'
    exit 1
}

# ---------------------------------------------------------------------------
# Deger yok: tek ayarin detayi
# ---------------------------------------------------------------------------
if (-not $Deger -and -not $BosDeger) {
    $e = Etkin $hedef
    "$hedef"
    "  aciklama      : $($kyt.Aciklama)"
    "  etkin deger   : $(Goster $e.Deger)"
    "  kaynak        : $($e.Kaynak)"
    "  varsayilan    : $(Goster $kyt.Varsayilan)"
    if (@($kyt.Secenekler).Count -gt 0) { "  secenekler    : $(@($kyt.Secenekler) -join ' | ')" }
    if ($hedef -eq 'BEYIN_VAULT') {
        "  saklandigi yer: $vaultKayit   (ayar.json'a yazilmaz)"
    } else {
        $t = Oku-Ayar
        $df = '(bu ayar dosyada yok)'
        if ($t.ContainsKey($hedef)) { $df = [string]$t[$hedef] }
        "  ayar dosyasi  : $ayarDosyasi -> $df"
    }
    $ov = [Environment]::GetEnvironmentVariable($hedef, 'Process')
    if ($ov) { "  ortam degiskeni: $ov   (ONCELIKLI - ayar dosyasini eziyor)" }
    ''
    "Yaz: beyin ayar $hedef <deger>    Sil: beyin ayar $hedef -Sil"
    exit 0
}

# ---------------------------------------------------------------------------
# Yaz
# ---------------------------------------------------------------------------
$sonuc = Dogrula -N $hedef -D $Deger -ZorlaGec:$Zorla
if (-not $sonuc.Ok) {
    Write-Output "HATA: $hedef icin gecersiz deger - $($sonuc.Hata)"
    Write-Output 'Hicbir sey yazilmadi.'
    Write-BeyinLog -Vault $Vault -Message "ayar: $hedef gecersiz deger reddedildi ($($sonuc.Hata))"
    Write-BeyinMakbuz -Paths $p -Script 'ayar' -Outcome 'AYAR_GECERSIZ' -Key $hedef -Reason ([string]$sonuc.Hata)
    exit 1
}
$yeni = [string]$sonuc.Deger
if ($sonuc.Uyari) { [string]$sonuc.Uyari }

if ($hedef -eq 'BEYIN_VAULT') {
    # GERI DONUS YOLU (2026-09-17). BEYIN_VAULT -Sil acikca reddediliyor, yani
    # yanlis yazilmis bir vault yolunun geri alma komutu YOK. Eski yol
    # yazmadan once yanina birakilir ve tam komut ekrana basilir.
    $eskiVault = ''
    try {
        if (Test-Path -LiteralPath $vaultKayit) {
            $eskiVault = ([string](Get-Content -LiteralPath $vaultKayit -Raw -Encoding UTF8)).Trim()
        }
    } catch { }
    $vaultYedek = $vaultKayit + '.onceki'
    $yedekOk = $false
    if ($eskiVault) {
        try { Copy-Item -LiteralPath $vaultKayit -Destination $vaultYedek -Force -ErrorAction Stop; $yedekOk = $true } catch { }
    }

    try {
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $vaultKayit) | Out-Null
        Write-BeyinText -Path $vaultKayit -Text ($yeni + "`r`n")
    } catch { }

    # GERI OKUMA: vault.txt de ayar.json ile ayni kilit riskini tasiyor.
    $vDisk = ''
    try { $vDisk = ([string](Get-Content -LiteralPath $vaultKayit -Raw -Encoding UTF8)).Trim() } catch { }
    if ($vDisk -ne $yeni) {
        Write-Output "HATA: BEYIN_VAULT yazilamadi - geri okuma uyusmadi."
        Write-Output "  hedef    : $vaultKayit"
        Write-Output "  beklenen : $yeni"
        Write-Output "  diskteki : $(Goster $vDisk)"
        Write-Output '  Dosya baska bir surecte kilitli olabilir (OneDrive/Dropbox, antivirus, editor, es zamanli beyin ayar).'
        Write-BeyinLog -Vault $Vault -Message "ayar: BEYIN_VAULT YAZILAMADI (disk: '$vDisk', beklenen: '$yeni')"
        Write-BeyinMakbuz -Paths $p -Script 'ayar' -Outcome 'AYAR_YAZILAMADI' -Key $hedef -Reason 'vault.txt geri okuma uyusmadi'
        exit 3
    }

    Write-BeyinLog -Vault $Vault -Message "ayar: BEYIN_VAULT -> $yeni (vault.txt, onceki: $(Goster $eskiVault))"
    Write-BeyinMakbuz -Paths $p -Script 'ayar' -Outcome 'AYAR_YAZILDI' -Key $hedef -Note "$(Goster $eskiVault) -> $yeni"
    "BEYIN_VAULT = $yeni"
    "  kayit: $vaultKayit   (ayar.json'a yazilmaz)"
    if ($yedekOk) {
        "  GERI DONUS: beyin ayar BEYIN_VAULT ""$eskiVault""   (eski yolun yedegi: $vaultYedek)"
    } elseif ($eskiVault) {
        "  GERI DONUS: beyin ayar BEYIN_VAULT ""$eskiVault""   (yedek alinamadi, yolu not al)"
    }
} else {
    $t = Oku-Ayar
    if (-not (Ayar-Okunabilir)) {
        Yazilamadi $hedef 'ayar dosyasi OKUNAMADI (kilitli); diger ayarlari silmemek icin yazim iptal'
        exit 3
    }
    $onceki = ''
    if ($t.ContainsKey($hedef)) { $onceki = [string]$t[$hedef] }
    $t[$hedef] = $yeni
    # BASARI MESAJI ANCAK DOGRULAMA GECTIKTEN SONRA.
    if (-not (Yaz-Ayar $t)) {
        Yazilamadi $hedef 'yazim sonrasi geri okuma uyusmadi'
        exit 3
    }
    $not = $yeni
    if ($onceki) { $not = "$onceki -> $yeni" }
    Write-BeyinLog -Vault $Vault -Message "ayar: $hedef -> $yeni"
    Write-BeyinMakbuz -Paths $p -Script 'ayar' -Outcome 'AYAR_YAZILDI' -Key $hedef -Note $not
    "$hedef = $yeni"
    "  kayit: $ayarDosyasi"
}
$e2 = Etkin $hedef
if ($e2.Kaynak -eq 'ortam degiskeni' -and $e2.Deger -ne $yeni) {
    "  DIKKAT: ayni adli ortam degiskeni ('$($e2.Deger)') ONCELIKLI; bu surecte yazdigin deger etkili olmaz."
}
'Bir sonraki oturumdan itibaren gecerli (kancalar ayari kendi surecinde, acilista okur).'
