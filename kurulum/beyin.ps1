# beyin.ps1 - Beyin TEK GIRIS NOKTASI (dagitici).
#
# NEDEN VAR: skill dosyalari ve belgeler her komutu TAM VAULT YOLUYLA yaziyordu
# (powershell ... -File "C:\Users\<ad>\Documents\Beyin\motor\scripts\
# doktor.ps1"). Bu uc sorun uretiyordu:
#   1. Baska bir makinede/kullanici adiyla hicbir komut calismiyordu.
#   2. Kisisel mutlak yol depoya ve model baglamina sizyordu.
#   3. Vault tasininca 15+ yerde elle duzeltme gerekiyordu.
#
# Artik tek portatif yol var ve her makinede aynidir:
#   powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.beyin\beyin.ps1" durum
#
# BU DOSYANIN KAYNAGI: <vault>\kurulum\beyin.ps1
# Buraya (~\.beyin\) kur.ps1 tarafindan KOPYALANIR. Elle duzenleme.
#
# ===========================================================================
# ARGUMAN SOZLESMESI (2026-09-17 bagimsiz denetimi; hepsi KOSARAK olculdu)
# ===========================================================================
# param() BLOGU YOK - BILEREK. Denetimde olculdu:
#   beyin niyet -- metin  -> dagitici PARAMETRE BAGLAYICISINDA patliyordu
#                            ("parameter name '' is ambiguous", exit 1): '--'
#                            PowerShell icin BOS ADLI bir anahtardir ve betigin
#                            kendi kodu HIC calismiyordu.
#   beyin -Yokboyle       -> hicbir parametreye baglanmiyor, $Komut varsayilani
#                            'yardim' devreye giriyor: bilinmeyen bayrak SESSIZCE
#                            yardim acip exit 0 veriyordu.
# $args ile parcalar HAM gelir; baglayici hic devreye girmez (olculdu: paramsiz
# bir betik 'niyet', '--', 'metin' parcalarini oldugu gibi alir).
#
# UC KURAL, her komut dalinda ayni:
#   1. Tire ile baslayan parca ancak O DALIN BILINEN anahtar kumesindeyse
#      anahtardir. Kume hedef betigin kendi param() blogundan okunmustur
#      (asagidaki her dalin -Deger/-Bayrak listesi).
#   2. Tire ile baslayan ama PowerShell parametre adi BICIMINDE OLMAYAN parca
#      (bosluk, nokta, egik cizgi ... icerir) DEGERDIR:  beyin niyet "-bir metin",
#      beyin al "-rapor.md".  Parametre adi biciminde ama BILINMEYEN bir parca
#      SESSIZCE YUTULMAZ: sesli hata + exit 2.
#   3. '--' ayiricidan SONRAKI her parca degerdir:  beyin niyet -- -Temizle
#      ('-Temizle' anahtar degil, metin olarak kaydedilir).
#
# KONUMSAL DEGER: her dal yalniz KENDI kabul ettigi kadar konumsal deger alir,
# gerisi reddedilir. NEDEN: hedef betiklerin cogunda $Vault ILK bildirilen
# parametredir; ciplak birakilan bir konumsal deger oraya baglanir ve komut
# YANLIS VAULT ile calisip 'basarili' cikar. Olculdu (duzeltme oncesi):
#   beyin derle 3 / derle ZZZ -> exit 0, COMPILE_BOS (yanlis vault, sessiz)
#   beyin arsivle 30          -> exit 0, "90 gun" (hem yanlis vault hem 30 yok sayildi)
#   beyin topla ZZZ           -> exit 0, "Vault : ZZZ"
#   beyin zamanla ZZZ         -> exit 0, gorev listesi (ZZZ yutuldu)
# Ikinci savunma hatti hedef betiklerin kendi vault kapisidir (compile.ps1,
# arsivle.ps1, sema-goc.ps1, gecmis-toparla.ps1, yol-temizle.ps1, isaret-goc.ps1,
# yayinla.ps1 - hepsine ayni kosuda eklendi); dagiticiyi atlayip betigi dogrudan
# calistiran da ayni korumayi alsin.

$ErrorActionPreference = 'Continue'

# Ham parcalar. [string] zorlamasi: $null hicbir yerde .StartsWith'e girmesin.
$Ham = @()
foreach ($a in $args) { $Ham += ,([string]$a) }

# ---------------------------------------------------------------------------
# Kultur-bagimsiz kucultme
# ---------------------------------------------------------------------------
function Kucult([string]$S) {
    # NEDEN GEREKLI: makine kulturu tr-TR. ToLowerInvariant NOKTALI I'yi (U+0130)
    # 'i' + birlesik noktaya (U+0307) katlar; sonuc 'i' ile ESLESMEZ. Olculdu:
    # 'beyin DURUM' calisiyordu ('I' harfi yok) ama 'beyin NIYET'in noktali-I'li
    # yazimi "Bilinmeyen komut" aliyordu. Noktasiz i (U+0131) de 'i'ye katlanir:
    # TR klavyede yazilan komut da calissin.
    if ($null -eq $S) { return '' }
    return (($S -replace '\u0130', 'i') -replace '\u0131', 'i').ToLowerInvariant()
}

# ---------------------------------------------------------------------------
# Vault cozumu - launcher ile AYNI sira (tek davranis, iki giris noktasi)
# ---------------------------------------------------------------------------
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

$vault = Get-BeyinVaultYolu
$scripts = Join-Path $vault 'motor\scripts'

function Yaz-Yardim {
    @"
beyin - Beyin ikinci beyin yoneticisi

  Vault: $vault$(if (-not (Test-Path -LiteralPath $vault)) { '   << BULUNAMADI' })

TANI
  durum            Kisa saglik ozeti (8-12 satir, model cagirmaz)   << en sik kullanilan
  doktor           Tam kontrol tablosu (sayi surumle degisir; TANI satiri gercek sayiyi basar)
  derin            Tam kontrol + canli 'claude -p' duman testi (gunluk butceden 1 harcar)
  makbuz [gun] [betik]  Motor kosu makbuzlari: ne yazildi, kac bayt, kac butce (varsayilan 1 gun)
  canli [dk]       Su an ne oluyor: aktif oturumlar, kuyruk, calisan is, butce, niyet (yazmaz)

BAKIM
  niyet [metin]    Ileriye donuk hedefi kaydet/goster (iki ajana enjekte edilir); -Proje x; -Temizle siler
  topla [gun]      Pencereden dusmus oturumlari topla (varsayilan kuru calisma, 3 gun)
  topla-uygula     Ayni, ama gercekten isle
  derle            Gunluk loglardan kavram notu uret
  derle-zorla      Bekleyen gunleri zorla derle
  al <yol>         Dis kaynagi (makale/rapor/dokuman) oku, kavram notuna cevir; -Proje x, -KuruCalisma, -Json, -MaxKavram 3
  denetle          Kavram notlari arasinda yakin-ikiz/celiski taramasi (semantik lint); -MinCos, -EnFazla, -Json; -Derin 1 butce harcar
  arsivle [gun]    Eski gunluk loglari 90-archive'a tasi (varsayilan 90 gun)
  bahcivan [gun]   Kavram/skill/betik kullanim raporu: canli, uyuyor, olu-aday (kuru)
  bahcivan-uygula  Olu aday kavramlari 90-archive'a tasi (makbuz kapsami dolmadan tasimaz)
  copcu            Disk copcusu: repolardaki yok sayilan cikti klasorlerini olc (kuru); -Kok, -MinMB
  copcu-uygula     Kapilardan gecenleri KALICI sil (-CopKutusu: geri donusum kutusu)
  gom              Kavram notlarini bge-m3 ile gom (vektor geri getirme; Ollama gerekir; -Zorla)
  bagla            Her kavram notuna en yakin kardeslerini gosteren "## Ilgili notlar" bolumu dokur (kuru; once gom)
  bagla-uygula     Ayni, ama bolumleri gercekten yazar; -MinCos, -EnFazla, -Json
  zamanla          Gece gorevlerini Gorev Zamanlayici'ya kaydet (-Liste, -Kaldir, -KuruCalisma, -Zorla)
  zamanli <komut>  Zamanlayici sarmalayicisi: kimlik on kontrolu + [zamanlayici] logu + makbuz
  yedek            Tam vault yedegi al - GERCEKTEN yazar (-KuruCalisma yalniz plani gosterir, -Tut <n>)

AYARLAR
  ayar             Tum ayarlari tek yerden gor/degistir (ad, etkin deger, kaynak)
  ayar <ad> <deger>  Ayari kalici yaz   |   ayar <ad> -Sil  varsayilana dondur
                     (-Sil varsayilana dondurur; varsayilani bos olan ayarda etkin deger de bos olur)

TASIMA / KURULUM
  guncelle         Motoru GitHub deposundan guncelle (NOTLARA DOKUNMAZ)
  kur              Kurulumu yeniden calistir (guncelleme sonrasi)
  kaldir           Motoru kaldir - VAULT'A DOKUNMAZ (-KuruCalisma, -Yedekleri)
  yayinla          Motoru + kurulumu GitHub deposuna gonder
  nerede           Cozulen vault yolunu ve kurulum durumunu goster

DUZELTME
  yol-temizle      Makine bolgesindeki mutlak kullanici yollarini kisalt
  isaret-goc       Isaret (watermark) semasini v2'ye gocur
  sema-goc         Durum dosyasi semasini gocur
  ice-aktar        Disaridan oturum gecmisi ice aktar

ORNEK
  beyin durum
  beyin ayar
  beyin topla 7
  beyin doktor

ARGUMAN NOTU
  Tire ile BASLAYAN bir DEGER vermek icin ya adli parametreyi kullan
  (beyin niyet -Metin "-once sunu bitir") ya da '--' ayiricisini koy
  (beyin niyet -- "-once sunu bitir"). '--' sonrasindaki her sey degerdir.
  Bilinmeyen bir anahtar SESSIZCE yutulmaz: sesli hata + exit 2.

Not: bu dagitici vault'un kendi betiklerine yonlendirir. Betikler
<vault>\motor\scripts altindadir ve dogrudan da calistirilabilir.
"@
}

function Cagir([string]$Betik, $Args2) {
    $yol = Join-Path $scripts $Betik
    if (-not (Test-Path -LiteralPath $yol)) {
        Write-Host "HATA: betik yok -> $yol" -ForegroundColor Red
        Write-Host "Vault yolu yanlis olabilir. Kontrol: beyin nerede" -ForegroundColor Yellow
        exit 2
    }
    # -File ile cagir: parametreler oldugu gibi gecer, tirnak sorunu olmaz.
    # DIKKAT: BOS DIZGE argumani native cagride SESSIZCE DUSER. Bu yuzden hicbir
    # dal bos deger GECIRMEZ; bos deger niyeti ayri bir ANAHTARLA tasinir
    # (ayar dalinda -BosDeger). Bkz. A4 duzeltmesi.
    $psArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $yol)
    foreach ($a in @($Args2)) { if ($null -ne $a) { $psArgs += [string]$a } }
    & powershell @psArgs
    exit $LASTEXITCODE
}

# ---------------------------------------------------------------------------
# ARGUMAN AYRISTIRICI - tek govde, her dal ayni kurallari alir
# ---------------------------------------------------------------------------
# Her dal kendi BILINEN anahtar kumesini verir. Kumeler hedef betigin param()
# blogundan tek tek okunmustur (2026-09-17); uydurma kume yok.
$ORTAK_BAYRAK = @('-verbose', '-debug')

function Coz-Anahtar([string]$K, [string[]]$Deger, [string[]]$Bayrak) {
    # @{ Tur; Ad } - Tur: deger | bayrak | yok | belirsiz
    # Kisaltma DESTEKLENIR (PowerShell sozlesmesi): '-Kuru' -> '-KuruCalisma',
    # ama yalniz TEK adaya uyuyorsa. Iki adaya uyuyorsa sessizce birini secmek
    # yerine BELIRSIZ denir.
    $adlar = @()
    $turler = @()
    foreach ($d in $Deger)  { $adlar += $d; $turler += 'deger' }
    foreach ($b in $Bayrak) { $adlar += $b; $turler += 'bayrak' }
    for ($j = 0; $j -lt $adlar.Count; $j++) {
        if ($adlar[$j] -eq $K) { return @{ Tur = $turler[$j]; Ad = $adlar[$j] } }
    }
    $bulunan = @()
    for ($j = 0; $j -lt $adlar.Count; $j++) {
        if (([string]$adlar[$j]).StartsWith($K, [System.StringComparison]::Ordinal)) { $bulunan += $j }
    }
    if ($bulunan.Count -eq 1) { return @{ Tur = $turler[$bulunan[0]]; Ad = $adlar[$bulunan[0]] } }
    if ($bulunan.Count -gt 1) {
        $liste = @()
        foreach ($j in $bulunan) { $liste += $adlar[$j] }
        return @{ Tur = 'belirsiz'; Ad = ($liste -join ', ') }
    }
    return @{ Tur = 'yok'; Ad = '' }
}

function Anahtar-Ozeti([string[]]$Deger, [string[]]$Bayrak) {
    $t = @()
    foreach ($d in $Deger)  { $t += ($d + ' <deger>') }
    foreach ($b in $Bayrak) { $t += $b }
    if ($t.Count -eq 0) { return '(bu komut anahtar almaz)' }
    return ($t -join '  ')
}

function Konum-Reddet([string]$KomutAdi, $Fazla, [string]$Ipucu) {
    $F = @(@($Fazla) | Where-Object { $null -ne $_ })
    if ($F.Count -eq 0) { return }
    $gosterim = @()
    foreach ($f in $F) { $gosterim += ("'" + [string]$f + "'") }
    Write-Host ("HATA: '$KomutAdi' bu konumsal degeri beklemiyor: " + ($gosterim -join ', ')) -ForegroundColor Red
    if ($Ipucu) { Write-Host "  $Ipucu" -ForegroundColor Yellow }
    Write-Host '  NEDEN HATA: konumsal deger hedef betikte sessizce -Vault parametresine baglaniyordu;' -ForegroundColor DarkGray
    Write-Host '  komut YANLIS VAULT ile calisip "basarili" cikiyordu (2026-09-17 denetimi, olculdu).' -ForegroundColor DarkGray
    exit 2
}

function Ayristir {
    param(
        [string]$KomutAdi,
        [object[]]$Parcalar = @(),
        [string[]]$Deger = @(),
        [string[]]$Bayrak = @(),
        [int]$Slot = 0,
        # Bu KONUMSAL SLOT INDISI tire ile baslayan bir degeri de kabul eder.
        # NEDEN VAR: 'beyin ayar codex_model -mini' olcumle DOGRU calisiyordu ve
        # bozulmamali - model adlari tire ile baslayabilir. Ama yalniz DEGER
        # slotunda: 'beyin ayar -Yokboyle' (ad slotu bos) hata almali.
        [int]$SerbestSlot = -1,
        [switch]$SinirsizSlot,
        # ROTANIN KENDI EKLEDIGI BAYRAKLAR ('durum' -> doktor.ps1 -Ozet gibi).
        # Kullanici ayni bayragi zaten yazdiysa IKINCI KEZ eklenmez.
        [string[]]$Ekle = @()
    )
    $bay = @($Bayrak) + $ORTAK_BAYRAK
    $konum = New-Object System.Collections.Generic.List[string]
    $gecen = New-Object System.Collections.Generic.List[string]
    $bayrakGecen = New-Object System.Collections.Generic.List[string]
    $i = 0
    $P = @($Parcalar)
    while ($i -lt $P.Count) {
        $x = [string]$P[$i].T
        if ($P[$i].Z -or -not $x.StartsWith('-')) {
            # '--' ile ACIKCA deger yapilmis bir parca da PARAMETRE ADI
            # biciminde olabilir ('beyin niyet -- "-Temizle"'). O durumda
            # 'powershell -File' onu yine ad sayar ve hedef betik
            # "Missing an argument" ile duser - adli deger yolundaki tuzagin
            # konumsal ikizi. Sessiz karisik hata yerine ne oldugunu soyle.
            if ($P[$i].Z -and $x -match '^-[A-Za-z_][A-Za-z0-9_]*$') {
                Write-Host "HATA: '$KomutAdi' icin verilen '$x' degeri bir PARAMETRE ADI biciminde." -ForegroundColor Red
                Write-Host '  powershell -File onu deger degil anahtar sayar; hedef betik "Missing an argument" ile duser.' -ForegroundColor Yellow
                Write-Host '  Cozum: degeri dogrudan betige ver (ornek: niyet icin)' -ForegroundColor Yellow
                Write-Host ("    powershell -NoProfile -ExecutionPolicy Bypass -File ""<vault>\motor\scripts
iyet.ps1"" -Metin '$x'") -ForegroundColor DarkGray
                exit 2
            }
            $konum.Add($x); $i++; continue
        }
        $k = Kucult $x
        $c = Coz-Anahtar $k $Deger $bay
        if ($c.Tur -eq 'deger') {
            if (($i + 1) -ge $P.Count) {
                Write-Host "HATA: '$KomutAdi $x' - bu anahtar bir DEGER bekliyor ama deger verilmemis." -ForegroundColor Red
                Write-Host ("  gecerli anahtarlar: " + (Anahtar-Ozeti $Deger $bay)) -ForegroundColor Yellow
                exit 2
            }
            $dgr = [string]$P[$i + 1].T
            # TIRE-ONLU DEGER TUZAGI (2026-09-18, izole olculdu).
            # 'powershell -File' bir argumani PARAMETRE ADI bicimindeyse ad
            # sayar, onceki anahtarin DEGERI saymaz. Olculdu:
            #   -Metin '-once sunu bitir'  -> CALISIR (bosluk var, ad bicimi degil)
            #   -Metin '-Temizle'          -> "Missing an argument for parameter 'Metin'"
            # Bu, Cagir'daki "bos dizge sessizce duser" notunun ayni ailesi.
            # -File ile ifade edilemiyor; en azindan SESSIZ ve karisik bir
            # PowerShell hatasi yerine ne oldugunu soyluyoruz.
            if ($dgr -match '^-[A-Za-z_][A-Za-z0-9_]*$') {
                Write-Host "HATA: '$KomutAdi $x' degeri '$dgr' - bu deger bir PARAMETRE ADI biciminde." -ForegroundColor Red
                Write-Host '  powershell -File onu deger degil anahtar sayar; hedef betik "Missing an argument" ile duser.' -ForegroundColor Yellow
                Write-Host '  Cozum: degeri dogrudan betige ver ->' -ForegroundColor Yellow
                Write-Host ("    powershell -NoProfile -ExecutionPolicy Bypass -File ""<vault>\motor\scripts\<betik>.ps1"" $x '$dgr'") -ForegroundColor DarkGray
                exit 2
            }
            $gecen.Add($c.Ad); $gecen.Add($dgr); $i += 2; continue
        }
        if ($c.Tur -eq 'bayrak') { $gecen.Add($c.Ad); $bayrakGecen.Add($c.Ad); $i++; continue }
        if ($c.Tur -eq 'belirsiz') {
            Write-Host "HATA: '$KomutAdi $x' - anahtar kisaltmasi BELIRSIZ; su anahtarlarin hepsine uyuyor: $($c.Ad)" -ForegroundColor Red
            Write-Host '  Tam adi yaz.' -ForegroundColor Yellow
            exit 2
        }
        # Tire ile basliyor ama bilinen bir anahtar degil.
        # (a) PowerShell parametre adi BICIMINDE degilse DEGERDIR.
        #     'beyin niyet "-bir metin"' ve 'beyin al "-rapor.md"' bu daldan gecer:
        #     ikisi de duzeltme oncesi anahtar sanilip komutu patlatiyordu (olculdu).
        if ($x -notmatch '^-[A-Za-z_][A-Za-z0-9_]*$') { $konum.Add($x); $i++; continue }
        # (b) Serbest deger slotu HALA BOSSA degerdir (bkz. -SerbestSlot).
        if ($SerbestSlot -ge 0 -and $konum.Count -eq $SerbestSlot) { $konum.Add($x); $i++; continue }
        # (c) Aksi halde BILINMEYEN ANAHTAR. Sessiz yutma yok.
        Write-Host "HATA: '$KomutAdi' bu anahtari tanimiyor: '$x'" -ForegroundColor Red
        Write-Host ("  gecerli anahtarlar: " + (Anahtar-Ozeti $Deger $bay)) -ForegroundColor Yellow
        Write-Host "  Bunu bir DEGER olarak vermek istiyorsan:  beyin $KomutAdi -- ""$x""" -ForegroundColor Yellow
        Write-Host '  NEDEN HATA: bilinmeyen bayrak eskiden SESSIZCE yutuluyordu; komut yazim hatasiyla' -ForegroundColor DarkGray
        Write-Host '  bambaska bir sey yapip exit 0 veriyordu (2026-09-17 denetimi, olculdu).' -ForegroundColor DarkGray
        exit 2
    }
    if (-not $SinirsizSlot -and $konum.Count -gt $Slot) {
        Konum-Reddet $KomutAdi (@($konum.ToArray() | Select-Object -Skip $Slot)) ''
    }

    # ROTA BAYRAGI ENJEKSIYONU (2026-09-18, kosarak olculdu).
    # Yedi rota hedef betige kendi bayragini ekliyordu ('durum' -> -Ozet,
    # 'topla-uygula' -> -Uygula ...). Kullanici AYNI bayragi da yazarsa hedef
    # betik "Cannot bind parameter ... specified more than once" ile duserdi:
    # 'beyin durum -Ozet' ve 'beyin derin -Derin' ikisi de exit 1 veriyordu.
    #
    # Ayni hata sinifi sayisal parametrelerde zaten yasanmis ve cozumu
    # Sayi-Konum'da AYRISTIRICIYA kurulmustu ("VARSAYILAN ENJEKTE ETMEZ",
    # asagida). Bayrak tarafi o dersin uygulanmamis yarisiydi. Cozum cagri
    # noktasinda degil BURADA: sekizinci rota eklendiginde hata geri gelmesin.
    #
    # NEDEN $bayrakGecen, $gecen DEGIL: $gecen anahtar adlarinin YANINDA
    # degerleri de tasiyor. 'beyin bahcivan-uygula -Bolum -uygula' cagrisinda
    # '-uygula' bir DEGER olarak $gecen'e girer; orada aramak onu bayrak sanip
    # enjeksiyonu yanlislikla atlardi.
    foreach ($e in @($Ekle)) {
        $eK = Kucult $e
        # OZ DENETIM: rota kendi KABUL ETMEDIGI bir bayragi enjekte ediyorsa bu
        # bir MOTOR kusurudur, kullanici hatasi degil - sessiz kalmasin.
        if (-not (@($bay) -contains $eK)) {
            Write-Host "HATA (motor kusuru): '$KomutAdi' rotasi '$e' bayragini enjekte ediyor ama kendi anahtar kumesinde yok." -ForegroundColor Red
            exit 2
        }
        if (-not (@($bayrakGecen.ToArray()) -contains $eK)) { $gecen.Add($eK) }
    }

    return @{ Konum = $konum.ToArray(); Gecen = $gecen.ToArray() }
}

function Sayi-Konum([string]$Ad, $Konum) {
    # @{ Gecen; Konum } - ilk konumsal parca TAM SAYI ise adli parametreye cevrilir,
    # degilse dokunulmaz (cagiran onu Konum-Reddet ile karsilar).
    # VARSAYILAN ENJEKTE ETMEZ: rotalar -Gun/-Dakika varsayilanini HER ZAMAN
    # ekliyordu ve 'beyin makbuz -Gun 7' -> 'parameter Gun is specified more than
    # once' veriyordu (olculdu). Varsayilan hedef betigin kendisindedir.
    $K = @(@($Konum) | Where-Object { $null -ne $_ })
    if ($K.Count -gt 0 -and "$($K[0])" -match '^\d+$') {
        return @{ Gecen = @($Ad, "$($K[0])"); Konum = @($K | Select-Object -Skip 1) }
    }
    return @{ Gecen = @(); Konum = $K }
}

function Bul-BrainCli {
    # TEK KAYNAK: arama sozlesmesi lib.ps1'deki Get-BeyinBrainCli'dedir.
    # Bu dosya lib.ps1'i normalde dot-source ETMEZ (dagitici/zamanlayici soguk
    # yolda hizli acilmali), o yuzden lib yalniz BURADA ve yalniz gerektiginde
    # yuklenir - 'beyin yedek' ve 'beyin zamanla' soguk yollardir, kanca degil.
    #
    # Yuklenemezse (vault bozuk/tasinmis) eski ORTAM DEGISKENI yoluna duseriz:
    # bozuk bir kurulumda bile komutun bir cevap vermesi TANI geregidir.
    $lib = Join-Path $vault 'motor\hooks\lib.ps1'
    if (Test-Path -LiteralPath $lib) {
        try {
            . $lib
            return (Get-BeyinBrainCli -Vault $vault).Yol
        } catch { }
    }
    if ($env:BEYIN_BRAIN_CLI -and (Test-Path -LiteralPath $env:BEYIN_BRAIN_CLI)) { return $env:BEYIN_BRAIN_CLI }
    return $null
}

# ---------------------------------------------------------------------------
# Komut + parcalar
# ---------------------------------------------------------------------------
$YARDIM_BAYRAK = @('-h', '-?', '-help', '--help', '--h', '/?')

# Bastaki tek basina '--': komut ondan SONRA gelir (beyin -- durum).
if ($Ham.Count -gt 0 -and $Ham[0] -ceq '--') { $Ham = @($Ham | Select-Object -Skip 1) }

$Komut = 'yardim'
$KalanHam = @()
if ($Ham.Count -gt 0) {
    $Komut = [string]$Ham[0]
    $KalanHam = @($Ham | Select-Object -Skip 1)
}
$KomutN = Kucult $Komut

# Bilinmeyen bir BAYRAK komut yerine gecemez. Eskiden sessizce yardim acip
# exit 0 veriyordu (olculdu: 'beyin -Yokboyle').
if ($Komut.StartsWith('-') -and ($KomutN -notin $YARDIM_BAYRAK)) {
    Write-Host "HATA: burada bir KOMUT bekleniyor, bayrak degil: '$Komut'" -ForegroundColor Red
    Write-Host '  Komut listesi:  beyin yardim' -ForegroundColor Yellow
    exit 2
}

# '--' AYIRICI: sonrasindaki her parca DEGERDIR (Z = zorunlu konumsal).
$Parca = New-Object System.Collections.Generic.List[object]
$zorlaKonum = $false
foreach ($x in $KalanHam) {
    if ((-not $zorlaKonum) -and ([string]$x) -ceq '--') { $zorlaKonum = $true; continue }
    $Parca.Add([pscustomobject]@{ T = [string]$x; Z = $zorlaKonum })
}
$PA = @($Parca.ToArray())

# ---------------------------------------------------------------------------
# Dagitim
# ---------------------------------------------------------------------------
switch ($KomutN) {

    { $_ -in @('durum', 'ozet', 'status') } {
        $a = Ayristir -KomutAdi $Komut -Parcalar $PA -Deger @('-vault') -Bayrak @('-derin', '-ozet') -Slot 0 -Ekle @('-ozet')
        Cagir 'doktor.ps1' @($a.Gecen)
    }
    { $_ -in @('doktor', 'doctor', 'tam') } {
        $a = Ayristir -KomutAdi $Komut -Parcalar $PA -Deger @('-vault') -Bayrak @('-derin', '-ozet') -Slot 0
        Cagir 'doktor.ps1' @($a.Gecen)
    }
    { $_ -in @('derin', 'deep') } {
        $a = Ayristir -KomutAdi $Komut -Parcalar $PA -Deger @('-vault') -Bayrak @('-derin', '-ozet') -Slot 0 -Ekle @('-derin')
        Cagir 'doktor.ps1' @($a.Gecen)
    }
    { $_ -in @('canli', 'live') } {
        $a = Ayristir -KomutAdi $Komut -Parcalar $PA -Deger @('-vault', '-dakika') -Bayrak @('-json') -Slot 1
        $s = Sayi-Konum '-Dakika' $a.Konum
        Konum-Reddet $Komut $s.Konum 'Dakika sayisi bekleniyordu:  beyin canli 30   (ya da -Dakika 30)'
        Cagir 'canli.ps1' (@($s.Gecen) + @($a.Gecen))
    }
    { $_ -in @('bahcivan', 'gardener') } {
        $a = Ayristir -KomutAdi $Komut -Parcalar $PA -Deger @('-vault', '-gun', '-bolum') -Bayrak @('-uygula', '-json') -Slot 1
        $s = Sayi-Konum '-Gun' $a.Konum
        Konum-Reddet $Komut $s.Konum 'Gun sayisi bekleniyordu:  beyin bahcivan 30   (bolum icin -Bolum <ad>)'
        Cagir 'bahcivan.ps1' (@($s.Gecen) + @($a.Gecen))
    }
    'bahcivan-uygula' {
        $a = Ayristir -KomutAdi $Komut -Parcalar $PA -Deger @('-vault', '-gun', '-bolum') -Bayrak @('-uygula', '-json') -Slot 1 -Ekle @('-uygula')
        $s = Sayi-Konum '-Gun' $a.Konum
        Konum-Reddet $Komut $s.Konum 'Gun sayisi bekleniyordu:  beyin bahcivan-uygula 30'
        Cagir 'bahcivan.ps1' (@($s.Gecen) + @($a.Gecen))
    }
    { $_ -in @('copcu', 'janitor') } {
        # -Kok: copcu.ps1'in gercek parametresi (copcu.ps1 param blogu), ama
        # dagitici bilmedigi icin 'beyin copcu -Kok D:\isler' exit 2 veriyordu -
        # oysa KILAVUZ onu belgeliyordu.
        $a = Ayristir -KomutAdi $Komut -Parcalar $PA -Deger @('-vault', '-minmb', '-kok') -Bayrak @('-uygula', '-copkutusu', '-json') -Slot 0
        Cagir 'copcu.ps1' @($a.Gecen)
    }
    'copcu-uygula' {
        $a = Ayristir -KomutAdi $Komut -Parcalar $PA -Deger @('-vault', '-minmb', '-kok') -Bayrak @('-uygula', '-copkutusu', '-json') -Slot 0 -Ekle @('-uygula')
        Cagir 'copcu.ps1' @($a.Gecen)
    }
    { $_ -in @('gom', 'embed') } {
        $a = Ayristir -KomutAdi $Komut -Parcalar $PA -Deger @('-vault', '-parti', '-metintavan') -Bayrak @('-zorla') -Slot 0
        Cagir 'gom.ps1' @($a.Gecen)
    }
    { $_ -in @('bagla', 'link') } {
        $a = Ayristir -KomutAdi $Komut -Parcalar $PA -Deger @('-vault', '-mincos', '-enfazla') -Bayrak @('-uygula', '-json') -Slot 0
        Cagir 'bagla.ps1' @($a.Gecen)
    }
    'bagla-uygula' {
        $a = Ayristir -KomutAdi $Komut -Parcalar $PA -Deger @('-vault', '-mincos', '-enfazla') -Bayrak @('-uygula', '-json') -Slot 0 -Ekle @('-uygula')
        Cagir 'bagla.ps1' @($a.Gecen)
    }
    { $_ -in @('zamanla', 'schedule') } {
        $a = Ayristir -KomutAdi $Komut -Parcalar $PA -Deger @('-vault') -Bayrak @('-kaldir', '-kurucalisma', '-liste', '-zorla') -Slot 0
        $zy = Join-Path $vault 'kurulum\zamanla.ps1'
        if (-not (Test-Path -LiteralPath $zy)) { Write-Host "HATA: betik yok -> $zy" -ForegroundColor Red; exit 1 }
        # -File: -Liste/-Kaldir/-KuruCalisma anahtarlari cocuk surecte dogru ayristirilir
        $zArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $zy, '-Vault', $vault)
        foreach ($g in @($a.Gecen)) { if ($null -ne $g) { $zArgs += [string]$g } }
        & powershell.exe @zArgs
        exit $LASTEXITCODE
    }
    { $_ -in @('zamanli', 'scheduled') } {
        # HAM GECIS: ic komut yine BU dagiticidan gecer (zamanli-kos.ps1 ->
        # beyin.ps1 <komut> <arg>) ve dogrulamayi orada alir. Burada ikinci kez
        # dogrulamak, gecerli bir ic anahtari yanlislikla reddetme riski yaratir.
        if ($PA.Count -eq 0) { Write-Host 'Kullanim: beyin zamanli <komut> [arg]' -ForegroundColor Yellow; exit 1 }
        $zk = [string]$PA[0].T
        $za = @()
        for ($i = 1; $i -lt $PA.Count; $i++) { $za += [string]$PA[$i].T }
        $zArg = @()
        if ($za.Count) { $zArg = @('-Arg') + $za }
        Cagir 'zamanli-kos.ps1' (@('-Komut', $zk) + $zArg)
    }
    { $_ -in @('makbuz', 'receipt') } {
        # beyin makbuz [gun] [betik]: ondeki sayi -Gun, ardindan gelen parca -Betik.
        # NEDEN: `beyin makbuz 7 flush` 'flush'u konumsal birakiyor, makbuz.ps1'de
        # $Vault'a baglaniyordu (olculdu).
        $a = Ayristir -KomutAdi $Komut -Parcalar $PA -Deger @('-vault', '-gun', '-betik', '-enfazla') -Bayrak @('-json') -Slot 2
        $s = Sayi-Konum '-Gun' $a.Konum
        $mk = @($s.Gecen)
        $kalanK = @($s.Konum)
        if ($kalanK.Count -gt 0) { $mk += @('-Betik', [string]$kalanK[0]) }
        Konum-Reddet $Komut (@($kalanK | Select-Object -Skip 1)) 'Kullanim: beyin makbuz [gun] [betik]'
        Cagir 'makbuz.ps1' ($mk + @($a.Gecen))
    }

    { $_ -in @('topla', 'toparla') } {
        $a = Ayristir -KomutAdi $Komut -Parcalar $PA -Deger @('-vault', '-gun', '-enfazla') -Bayrak @('-uygula') -Slot 1
        $s = Sayi-Konum '-Gun' $a.Konum
        Konum-Reddet $Komut $s.Konum 'Gun sayisi bekleniyordu:  beyin topla 7   (vault icin -Vault <yol>)'
        Cagir 'gecmis-toparla.ps1' (@($s.Gecen) + @($a.Gecen))
    }
    'topla-uygula' {
        $a = Ayristir -KomutAdi $Komut -Parcalar $PA -Deger @('-vault', '-gun', '-enfazla') -Bayrak @('-uygula') -Slot 1 -Ekle @('-uygula')
        $s = Sayi-Konum '-Gun' $a.Konum
        Konum-Reddet $Komut $s.Konum 'Gun sayisi bekleniyordu:  beyin topla-uygula 7'
        Cagir 'gecmis-toparla.ps1' (@($s.Gecen) + @($a.Gecen))
    }

    { $_ -in @('niyet', 'intent') } {
        # beyin niyet "metin" [-Proje x]  |  beyin niyet -Proje x "metin"  |  beyin niyet -Temizle  |  beyin niyet
        # NEDEN: yalniz ONDEKI tire'siz parcalar metin sayiliyordu; `-Proje x "bu hafta ..."` sirasinda
        # metin konumsal kalip niyet.ps1'de $Vault'a baglaniyor, niyet SESSIZCE kaydedilmiyordu (olculdu).
        # Adli parametrelerin degeri disindaki TUM konumsal parcalar metindir.
        $a = Ayristir -KomutAdi $Komut -Parcalar $PA -Deger @('-vault', '-metin', '-proje') -Bayrak @('-temizle') -SinirsizSlot
        $nArgs = @($a.Gecen)
        $metin = ((@($a.Konum)) -join ' ').Trim()
        $metinVar = $false
        foreach ($g in $nArgs) { if ((Kucult ([string]$g)) -eq '-metin') { $metinVar = $true } }
        # BOS metin -Metin ile GECIRILMEZ: bos dizge native cagride duser ve
        # niyet.ps1 '-Metin' anahtarini degersiz gorup baglama hatasi verirdi.
        if ($metin -and -not $metinVar) { $nArgs = @('-Metin', $metin) + $nArgs }
        Cagir 'niyet.ps1' $nArgs
    }
    { $_ -in @('derle', 'compile') } {
        $a = Ayristir -KomutAdi $Komut -Parcalar $PA -Deger @('-vault', '-maxdays', '-maxnewconcepts', '-maxupdates') -Bayrak @('-force') -Slot 0
        Cagir 'compile.ps1' @($a.Gecen)
    }
    'derle-zorla' {
        $a = Ayristir -KomutAdi $Komut -Parcalar $PA -Deger @('-vault', '-maxdays', '-maxnewconcepts', '-maxupdates') -Bayrak @('-force') -Slot 0 -Ekle @('-force')
        Cagir 'compile.ps1' @($a.Gecen)
    }

    { $_ -in @('al', 'kaynak', 'ingest') } {
        # beyin al <yol> [-Proje x] [-KuruCalisma] [-Json] [-MaxKavram 3]
        # NEDEN 'niyet' ile AYNI ayristirma: al.ps1'in ILK konumsal parametresi $Vault'tur.
        # Ciplak birakilan bir yol oraya baglanir, betik var olmayan bir vault'a bakar ve
        # kaynak SESSIZCE alinmaz - niyet'te tam olarak bu olculdu. Bu yuzden konumsal
        # deger burada adli -Kaynak'a cevrilir.
        $a = Ayristir -KomutAdi $Komut -Parcalar $PA -Deger @('-vault', '-kaynak', '-proje', '-maxkavram') -Bayrak @('-kurucalisma', '-json') -SinirsizSlot
        $alArgs = @($a.Gecen)
        $kaynakVar = $false
        foreach ($g in $alArgs) { if ((Kucult ([string]$g)) -eq '-kaynak') { $kaynakVar = $true } }
        if (-not $kaynakVar) {
            $kp = @(@($a.Konum) | Where-Object { "$_" -ne '' })
            if ($kp.Count -eq 0) {
                Write-Host 'Kullanim: beyin al <yol> [-Proje x] [-KuruCalisma] [-Json] [-MaxKavram 3]' -ForegroundColor Yellow
                Write-Host '  Ornek  : beyin al "D:\indirilenler\rapor.md" -Proje beyin -KuruCalisma' -ForegroundColor Yellow
                Write-Host '  Desteklenen: .md .markdown .txt .log .html .htm .json .csv' -ForegroundColor Yellow
                exit 1
            }
            if ($kp.Count -gt 1) {
                # Kalani sessizce gecirmek konumsal tuzagi geri getirirdi; sessizce atmak da
                # kullaniciyi yanlis yola sokar. Bu yuzden SOYLENIR.
                Write-Host 'UYARI: birden fazla konumsal deger verildi; yalniz ilki kaynak sayildi.' -ForegroundColor Yellow
                Write-Host ('  yok sayilan: ' + ((@($kp) | Select-Object -Skip 1) -join ' ') + '   (bosluklu yolu tirnak icine al)') -ForegroundColor Yellow
            }
            # SONDAKI AYIRICI KIRPILIR (denetim 2026-09-17, olculdu). Cagir
            # `& powershell -File` ile calisir; native cagri argumani yeniden
            # tirnaklarken SONU TERS TIRNAKLA BITEN bir deger kapanis tirnagini
            # kacirir: 'D:\rapor ve notlar\' karsi tarafa 'D:\rapor ve notlar"'
            # olarak varir ve al.ps1 'kaynak bulunamadi' der. Bosluksuz yolda
            # gorunmez (olculdu: 'D:\indirilenler\raporlar\' saglam gecti), ama
            # al.ps1 DIZIN kabul eder ve PowerShell sekme tamamlama dizin adinin
            # sonuna ters tirnak ekler - yani kullanicinin NORMAL yazimi budur.
            # SURUCU KOKU korunur: 'D:\' kirpilirsa 'D:' surucunun O ANKI
            # calisma dizinine isaret eder, baska bir yer olur.
            $kAl = ([string]$kp[0])
            if ($kAl -notmatch '^[A-Za-z]:[\\/]$') { $kAl = $kAl.TrimEnd('\', '/') }
            $alArgs = @('-Kaynak', $kAl) + $alArgs
        }
        Cagir 'al.ps1' $alArgs
    }
    { $_ -in @('denetle', 'lint') } {
        $a = Ayristir -KomutAdi $Komut -Parcalar $PA -Deger @('-vault', '-mincos', '-enfazla') -Bayrak @('-derin', '-json') -Slot 0
        Cagir 'denetle.ps1' @($a.Gecen)
    }
    { $_ -in @('arsivle', 'archive') } {
        # beyin arsivle [gun]: ondeki sayi -GunSayisi'na baglanir (arsivle.ps1'in
        # kendi param adi; 2026-09-17'de dogrulandi). Eskiden sayi konumsal kalip
        # $Vault'a baglaniyordu: hem yanlis vault hem kullanicinin gun sayisi yok
        # sayiliyordu - 'beyin arsivle 30' ekrana "90 gun" yaziyordu (olculdu).
        $a = Ayristir -KomutAdi $Komut -Parcalar $PA -Deger @('-vault', '-gunsayisi') -Bayrak @('-uygula') -Slot 1
        $s = Sayi-Konum '-GunSayisi' $a.Konum
        Konum-Reddet $Komut $s.Konum 'Gun sayisi bekleniyordu:  beyin arsivle 30   (vault icin -Vault <yol>)'
        Cagir 'arsivle.ps1' (@($s.Gecen) + @($a.Gecen))
    }
    { $_ -in @('yol-temizle', 'yol') } {
        $a = Ayristir -KomutAdi $Komut -Parcalar $PA -Deger @('-vault') -Bayrak @('-uygula') -Slot 0
        Cagir 'yol-temizle.ps1' @($a.Gecen)
    }
    'isaret-goc' {
        $a = Ayristir -KomutAdi $Komut -Parcalar $PA -Deger @('-vault') -Bayrak @('-uygula') -Slot 0
        Cagir 'isaret-goc.ps1' @($a.Gecen)
    }
    'sema-goc' {
        $a = Ayristir -KomutAdi $Komut -Parcalar $PA -Deger @('-vault') -Bayrak @('-uygula') -Slot 0
        Cagir 'sema-goc.ps1' @($a.Gecen)
    }
    { $_ -in @('ice-aktar', 'import') } {
        $a = Ayristir -KomutAdi $Komut -Parcalar $PA -Deger @('-vault', '-dosya', '-enfazla', '-kaynak') -Bayrak @('-uygula') -Slot 1
        $iArgs = @($a.Gecen)
        $dosyaVerildi = $false
        foreach ($g in $iArgs) { if ((Kucult ([string]$g)) -eq '-dosya') { $dosyaVerildi = $true } }
        $kp = @(@($a.Konum) | Where-Object { "$_" -ne '' })
        if (-not $dosyaVerildi -and $kp.Count -gt 0) {
            $iArgs = @('-Dosya', [string]$kp[0]) + $iArgs
        } elseif ($kp.Count -gt 0) {
            Konum-Reddet $Komut $kp 'Dosya zaten -Dosya <yol> ile verildi.'
        }
        Cagir 'gecmis-import.ps1' $iArgs
    }
    { $_ -in @('yayinla', 'publish') } {
        $a = Ayristir -KomutAdi $Komut -Parcalar $PA -Deger @('-vault', '-hedef', '-uzak') -Bayrak @('-uygula', '-gonder') -Slot 0
        Cagir 'yayinla.ps1' @($a.Gecen)
    }

    { $_ -in @('yedek', 'backup') } {
        # YERLI YEDEK (2026-09-18): bu komut brain-cli.mjs'e bagliydi ve o arac
        # BU DEPODA GELMIYOR - yani motoru yeni kuran biri icin yardimda
        # tanitilan, gece gorevi olarak kaydedilen ve doktorun onerdigi komut
        # HIC CALISMIYORDU. Artik motorun kendi yedegi var (yedek.ps1,
        # bagimliligi yok); brain-cli varsa yine O tercih edilir - zengin
        # manifest/dogrulama uretiyor ve mevcut davranis bozulmasin.
        $a = Ayristir -KomutAdi $Komut -Parcalar $PA -Deger @('-vault', '-tut') -Bayrak @('-kurucalisma', '-json') -Slot 0
        $cli = Bul-BrainCli
        $nodeVar = [bool](Get-Command node -ErrorAction SilentlyContinue)
        if (-not $cli -or -not $nodeVar) {
            Cagir 'yedek.ps1' @($a.Gecen)
        }
        if (@($a.Gecen) -contains '-kurucalisma') {
            # brain-cli'nin kuru yolu --apply'siz cagridir; ayni sozlesmeyi
            # yerli yedekle tutarli tutmak icin oraya yonlendiriyoruz.
            Cagir 'yedek.ps1' @($a.Gecen)
        }
        # --apply SART: --apply olmadan brain-cli yalniz ONIZLEME plani uretir
        # ve hicbir sey yazmaz. Onizlemeyi yedek sanmak gercek bir tuzaktir.
        & node $cli backup --target $vault --apply
        exit $LASTEXITCODE
    }

    { $_ -in @('guncelle', 'update') } {
        # NEDEN AYRI ELE ALINIYOR: guncelle.ps1 calisirken motor\scripts
        # icerigini uzerine yazar - yani KENDI dosyasini da. 'Cagir' zaten
        # ayri bir powershell surecinde `-File` ile baslatir; PowerShell
        # betigi bastan sonuna okuyup dosyayi kapatir, dolayisiyla kopyalama
        # kilitlenmez (kurulumdan sonra dogrulandi).
        $a = Ayristir -KomutAdi $Komut -Parcalar $PA -Deger @('-vault', '-depo', '-dal') -Bayrak @('-kurucalisma', '-zorla', '-json', '-gerial') -Slot 0
        Cagir 'guncelle.ps1' @($a.Gecen)
    }

    { $_ -in @('ayar', 'ayarlar', 'config', 'settings') } {
        # beyin ayar                     -> hepsini listele
        # beyin ayar BEYIN_OZETLEYICI    -> yalniz onu goster
        # beyin ayar ozetleyici codex    -> yaz (BEYIN_ oneki sart degil)
        # beyin ayar ozetleyici -Sil     -> varsayilana dondur
        # beyin ayar codex_model ""      -> BOS degeri ACIKCA yaz (A4)
        #
        # Konumsal degerler ADLI parametreye cevrilir. NEDEN: ayar.ps1'in
        # param blogunda $Vault da vardir; ciplak birakilan ilk konumsal
        # deger niyet/al komutlarinda tam olarak oraya baglanmisti ve komut
        # SESSIZCE yanlis calismisti (olculdu).
        #
        # -SerbestSlot 1: DEGER slotu tire ile baslayan bir degeri kabul eder
        # (model adlari boyle olabiliyor; 'beyin ayar codex_model -mini' olcumle
        # dogruydu ve korunuyor). AD slotu kabul etmez: 'beyin ayar -Yokboyle'
        # artik sesli hata verir.
        $a = Ayristir -KomutAdi $Komut -Parcalar $PA -Deger @('-vault', '-ad', '-deger') -Bayrak @('-sil', '-json', '-liste', '-zorla') -SinirsizSlot -SerbestSlot 1
        $konum = @($a.Konum)
        $gecenAy = @($a.Gecen)
        $adVerildi = $false
        $degerVerildi = $false
        foreach ($g in $gecenAy) {
            $gk = Kucult ([string]$g)
            if ($gk -eq '-ad') { $adVerildi = $true }
            if ($gk -eq '-deger') { $degerVerildi = $true }
        }
        $ayArgs = @()
        if ($konum.Count -ge 1 -and -not $adVerildi) { $ayArgs += @('-Ad', [string]$konum[0]) }
        if ($konum.Count -ge 2 -and -not $degerVerildi) {
            # Bosluklu deger tirnaksiz yazilmis olabilir: kalani birlestir.
            $deg = ((@($konum | Select-Object -Skip 1)) -join ' ')
            if ($deg -eq '') {
                # A4: BOS DEGER. Bos dizge native cagride SESSIZCE DUSER; 'deger
                # verilmedi' ile 'deger BOS verildi' ayrimi bu yuzden ayri bir
                # ANAHTARLA tasinir. Olculdu (duzeltme oncesi): beyin ayar
                # codex_model "" -> exit 0, ayari YAZMAK YERINE GOSTERIYORDU,
                # oysa o ayarin kendi aciklamasi "bos = codex varsayilani" diyor.
                $ayArgs += @('-BosDeger')
            } else {
                $ayArgs += @('-Deger', $deg)
            }
        }
        Cagir 'ayar.ps1' ($ayArgs + $gecenAy)
    }

    { $_ -in @('kur', 'install') } {
        $a = Ayristir -KomutAdi $Komut -Parcalar $PA -Deger @('-vault') -Bayrak @('-kurucalisma', '-zamanla', '-codexzorla', '-yalnizvault', '-pathatla', '-izinlerisikilastir') -Slot 0
        $kur = Join-Path $vault 'kurulum\kur.ps1'
        if (-not (Test-Path -LiteralPath $kur)) { Write-Host "HATA: $kur yok" -ForegroundColor Red; exit 2 }
        $kArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $kur, '-Vault', $vault)
        foreach ($g in @($a.Gecen)) { if ($null -ne $g) { $kArgs += [string]$g } }
        & powershell @kArgs
        exit $LASTEXITCODE
    }

    { $_ -in @('kaldir', 'uninstall') } {
        # NEDEN VAR (2026-09-18 denetimi): 'kur' rotasi vardi, 'kaldir' YOKTU.
        # Bu dosyanin basindaki "motorun TEK portatif giris noktasi" iddiasi
        # ancak bununla dogru olur. kaldir.ps1 ~\.beyin'e kopyalanmiyor, o
        # yuzden Cagir degil 'kur'/'zamanla' kalibi kullaniliyor.
        $a = Ayristir -KomutAdi $Komut -Parcalar $PA -Deger @('-vault') -Bayrak @('-kurucalisma', '-yedekleri') -Slot 0
        $kld = Join-Path $vault 'kurulum\kaldir.ps1'
        if (-not (Test-Path -LiteralPath $kld)) { Write-Host "HATA: $kld yok" -ForegroundColor Red; exit 2 }
        $klArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $kld)
        foreach ($g in @($a.Gecen)) { if ($null -ne $g) { $klArgs += [string]$g } }
        & powershell @klArgs
        exit $LASTEXITCODE
    }

    { $_ -in @('nerede', 'where', 'bilgi') } {
        [void](Ayristir -KomutAdi $Komut -Parcalar $PA -Deger @() -Bayrak @() -Slot 0)
        "Vault           : $vault"
        "  var mi        : $(Test-Path -LiteralPath $vault)"
        "Cozum kaynagi   : $(if ($env:BEYIN_VAULT) { 'BEYIN_VAULT ortam degiskeni' }
                             elseif (Test-Path -LiteralPath (Join-Path $env:USERPROFILE '.beyin\vault.txt')) { '~\.beyin\vault.txt' }
                             else { 'varsayilan (~\Documents\Beyin)' })"
        "Motor betikleri : $scripts  ($(if (Test-Path -LiteralPath $scripts) { @(Get-ChildItem $scripts -Filter *.ps1 -File).Count } else { 0 }) betik)"
        "Launcher        : $(Join-Path $env:USERPROFILE '.beyin\beyin-launcher.ps1')  var=$(Test-Path -LiteralPath (Join-Path $env:USERPROFILE '.beyin\beyin-launcher.ps1'))"
        "Codex simi      : $(Join-Path $env:USERPROFILE '.claude\hooks\beyin-launcher.ps1')  var=$(Test-Path -LiteralPath (Join-Path $env:USERPROFILE '.claude\hooks\beyin-launcher.ps1'))"
        "Claude ayari    : $(Join-Path $env:USERPROFILE '.claude\settings.json')  var=$(Test-Path -LiteralPath (Join-Path $env:USERPROFILE '.claude\settings.json'))"
        "Codex ayari     : $(Join-Path $env:USERPROFILE '.codex\hooks.json')  var=$(Test-Path -LiteralPath (Join-Path $env:USERPROFILE '.codex\hooks.json'))"
        "brain-cli       : $(if (Bul-BrainCli) { Bul-BrainCli } else { 'bulunamadi (istege bagli)' })"
        "Motor surumu    : $(if (Test-Path -LiteralPath (Join-Path $vault '.beyin-version')) { (Get-Content (Join-Path $vault '.beyin-version') -Raw).Trim() } else { 'bilinmiyor' })"
        exit 0
    }

    { $_ -in @('yardim', 'help', '-h', '--help', '-?', '-help', '--h', '/?') } { Yaz-Yardim; exit 0 }

    default {
        Write-Host "Bilinmeyen komut: $Komut" -ForegroundColor Red
        ''
        Yaz-Yardim
        exit 2
    }
}
