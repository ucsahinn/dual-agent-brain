# lib.ps1 - Ikinci beyin motoru: ortak yardimcilar.
#
# TEK MOTOR, IKI AJAN. Claude Code ve Codex ayni kancalari, ayni betikleri
# ve ayni vault'u kullanir; aralarindaki tek fark gunluk log blogunun
# basligina yazilan -Agent etiketidir. Hicbiri birincil degildir.
#
# Onemli: bu vault'un anayasasi (AGENTS.md + brain.config.json) "preview-required"
# ve "overwritePolicy: never" der. Bu yuzden motor SADECE makine-sahipli
# bolgelere yazar: 85-daylogs/ ve 86-compiled/.
# Kuratorlu notlar (80-memory, 40-knowledge, 60-decisions ...) motor icin
# SALT-OKUNURDUR; onlari yalnizca model, kullaniciya onizleme gostererek gunceller.

# DIKKAT: Bu dosya dot-source edilir (. lib.ps1), yani burada yapilan
# Set-StrictMode / $ErrorActionPreference degisiklikleri CAGIRANIN kapsamina
# sizar. Onceki surum burada 'Stop' ayarliyordu ve kancalarin kendi
# 'SilentlyContinue' ayarini eziyordu; eksik bir hafiza dosyasi kancayi
# cokertebiliyordu. Bir kutuphane cagiranin hata politikasini degistirmemeli:
# her giris betigi kendi politikasini kendisi belirler.
#
# Kancalar ASLA cokmemeli (cokme oturum baslangicini bozabilir) -> onlar
# SilentlyContinue kullanir ve her seyi acikca kontrol eder.
# Betikler (flush/compile/doktor) kendi try/catch'lerini yonetir.

# ============================================================================
# ENCODING  (bu makine icin ZORUNLU - sessiz veri bozulmasi kaynagi)
# ----------------------------------------------------------------------------
# UC AYRI encoding tuzagi var, ucu de PS 5.1'e ozgu ve ucu de SESSIZ bozuyor:
#
# 1) $OutputEncoding varsayilani PS 5.1'de us-ascii (PS7'de UTF-8). Native bir
#    exe'ye PIPE ile yazilan her sey bununla kodlanir. Yani 'claude -p'ye
#    gonderilen Turkce yonerge ve transkriptin tamami '?' oluyordu:
#      'TEST-cgiso' -> 84,69,83,84,45,63,63,63,63,63   (bes harf de 0x3F)
#    Olculdu. Duzeltmesi bu satir. ($false ONEMLI: PS 5.1 pipe'a zaten kendi
#    BOM'unu ekliyor; UTF8Encoding($true) BOM'u IKI KEZ yazar.)
#
# 2) [Console]::Out.Write ciktiyi [Console]::OutputEncoding ile kodlar. Konsol
#    mirasi olmayan bir spawn'da (Claude Code kancalari boyle calisir) bu deger
#    IBM437 oluyor; kanca JSON'u gecersiz UTF-8 olarak cikiyor. Cozum: ham
#    bayt yazmak -> Write-BeyinHookContext icinde.
#
# 3) [Console]::In.ReadToEnd() girdiyi [Console]::InputEncoding ile cozer; ayni
#    spawn'da IBM437 oluyor ve UTF-8 payload bozuluyor (JSON yapisi ASCII
#    oldugu icin ConvertFrom-Json BASARILI olur, yalniz degerler bozulur -
#    tam sessiz hata). Cozum: ham bayt okumak -> Read-BeyinHookPayload icinde.
#
# Bu dosya dot-source edildigi icin asagidaki atama cagiranin kapsamina siziyor;
# burada sizinti ISTENEN davranistir (flush/compile/doktor hepsi pipe kullanir).
# ============================================================================

$OutputEncoding = New-Object System.Text.UTF8Encoding($false)

# ============================================================================
# Yol ve ortam
# ============================================================================

function Get-BeyinVault {
    # hooks/ veya scripts/ altindan cagrildiginda vault kokunu bulur
    param([string]$ScriptPath)
    $dir = Split-Path -Parent $ScriptPath          # .../motor/hooks
    $motor = Split-Path -Parent $dir               # .../motor
    return (Split-Path -Parent $motor)             # vault koku
}

function Get-BeyinAgent {
    # Hangi ajan bu kancayi calistirdi. Launcher BEYIN_AGENT'i ayarlar.
    # Vault TEK BEYIN: Claude Code ve Codex ayni motoru cagiriyor, gunluk log
    # blogu hangisinin urettigini gosteriyor.
    if ($env:BEYIN_AGENT -eq 'codex') { return 'codex' }
    return 'claude'
}

function Test-BeyinChild {
    # 'claude -p' ile spawn edilen alt surecte hook'lar TEKRAR calismasin.
    # Bu koruma olmadan flush -> claude -p -> SessionEnd -> flush ... sonsuz dongu olur.
    return ($env:BEYIN_CHILD -eq '1')
}

# ============================================================================
# AYARLAR  (~\.beyin\ayar.json)
# ----------------------------------------------------------------------------
# ONCELIK: ortam degiskeni > ayar dosyasi > varsayilan.
# Ortam degiskeni USTTE kalir ki tek seferlik override mumkun olsun (doktor
# -Derin iki ozetleyici arka ucunu boyle sinar). Kalici ayar dosyaya yazilir:
# tek merkez 'beyin ayar' (motor\scripts\ayar.ps1); burasi yalnizca OKUR.
#
# NEDEN ConvertFrom-Json YOK: bu fonksiyon Codex'in 3 saniyelik SessionEnd
# yolunda calisiyor ve ConvertFrom-Json'un ILK yuklenmesi bu makinede ~150 ms
# (olculdu) - kanca butcesinin yirmide biri, tek bir ayar okumak icin. Dosya
# duz satir regex'iyle ayristirilir; ayar.ps1 dosyayi tam bu bicimde yazar:
#   {
#     "BEYIN_OZETLEYICI": "codex"
#   }
#
# FAIL-OPEN: dosya yoksa, okunamiyorsa ya da bozuksa BOS sozluk doner ve her
# ayar varsayilanina duser. Bozuk bir ayar dosyasi motoru DURDURMAZ.
# ============================================================================

$script:BeyinAyarCache = $null

function Get-BeyinAyarDosyasi {
    return (Join-Path $env:USERPROFILE '.beyin\ayar.json')
}

function Get-BeyinAyarTablo {
    # Dosya surec basina BIR KEZ okunur; sonrasi onbellekten.
    if ($null -ne $script:BeyinAyarCache) { return $script:BeyinAyarCache }
    $t = @{}
    try {
        $f = Get-BeyinAyarDosyasi
        if ([System.IO.File]::Exists($f)) {
            $ham = [System.IO.File]::ReadAllText($f, [System.Text.Encoding]::UTF8)
            if ($ham) {
                foreach ($m in [regex]::Matches($ham, '"(?<k>BEYIN_[A-Z_]+)"\s*:\s*"(?<v>[^"]*)"')) {
                    $dv = $m.Groups['v'].Value
                    # JSON kacislari: yollardaki '\\' -> '\', '\"' -> '"'.
                    if ($dv.IndexOf('\') -ge 0) { $dv = $dv -replace '\\(.)', '$1' }
                    $t[$m.Groups['k'].Value] = $dv
                }
            }
        }
    } catch { $t = @{} }
    $script:BeyinAyarCache = $t
    return $t
}

# YONLENDIRILMIS CIKTI UTF-8 (2026-10-07): dispatcher (beyin.ps1 Cagir) cikti bir ajana
# yonlendirildiginde betigi kendi gizli konsoluyla BEYIN_STDOUT_UTF8=1 ile baslatir; burada
# stdout UTF-8'e alinir. Gizli konsol paylasilmadigi icin baska hicbir terminal etkilenmez.
# Kancalar bu degiskeni almaz: davranislari degismez.
if ($env:BEYIN_STDOUT_UTF8 -eq '1') {
    try { if ([Console]::IsOutputRedirected) { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } } catch { }
}

function Get-BeyinAyar([string]$Ad, [string]$Varsayilan) {
    try {
        $o = [Environment]::GetEnvironmentVariable($Ad, 'Process')
        if ($o) { return [string]$o }
        $t = Get-BeyinAyarTablo
        if ($t -and $t.ContainsKey($Ad)) {
            $d = [string]$t[$Ad]
            if ($d) { return $d }
        }
    } catch { }
    return [string]$Varsayilan
}

function Clear-BeyinAyarCache {
    # Ayni surecte ayar.json degistiginde onbellegi gecersiz kilar.
    # Bunu YALNIZ 'beyin ayar' cagirir (yazimdan hemen sonra); aksi halde ayni
    # surecte eski deger okunurdu. SICAK YOLDA CAGRILMAZ.
    $script:BeyinAyarCache = $null
}

# ============================================================================
# AYAR ENVANTERI + DEGER KURALLARI - TEK DOGRULUK KAYNAGI   (SOGUK YOL)
# ----------------------------------------------------------------------------
# Bu bilgi UC yerde kopyaliydi: ayar.ps1'in $kayitlar listesi, ayar.ps1'in
# Dogrula'si ve doktor.ps1'in kendi ayristiricisi. Uc kopya = uc ayri dilbilgisi.
# Olculdu (2026-09-17): ayar.json'a kucuk harfle yazilmis bir anahtar icin
# doktor "1 ayar yazili" diyordu, motor ise ayni satiri YOK SAYIYORDU; ve
# {"BEYIN_FLUSH_BUTCE":"0"} doktor'un '^\d+$' testini geciyordu - butce 0 her
# model cagrisini reddeder, yani TUM ozetleme sessizce durur, doktor yesil.
#
# Artik envanter ve deger kurallari BURADA duruyor; 'beyin ayar' bunlari
# cagirir. Asagidaki fonksiyonlarin HICBIRI kanca yolunda calismaz: liste
# tembel kurulur, yani lib.ps1 yuklemesine maliyeti yoktur.
#
# Get-BeyinAyarTablo'nun SICAK YOL davranisi bu blokla DEGISMEZ: ayni regex,
# ayni "yalniz BUYUK HARF anahtar gecerlidir" sozlesmesi, ayni fail-open, ayni
# onbellek. Degisen tek sey, Get-BeyinAyarDenetim'in bunu artik GORUP SOYLEMESI.
# ============================================================================

$script:BeyinAyarKayitlari = $null

function Get-BeyinAyarKayitlari {
    # @( @{ Ad; Varsayilan; Secenekler; Aciklama } ) - kullanici ayarlanabilir
    # ayarlarin TEK listesi. Yeni ayar eklerken: buraya bir satir + ilgili
    # yerde Get-BeyinAyar cagrisi. Kopyasini baska bir betige YAZMA.
    if ($null -ne $script:BeyinAyarKayitlari) { return $script:BeyinAyarKayitlari }
    $script:BeyinAyarKayitlari = @(
        @{ Ad = 'BEYIN_OZETLEYICI';  Varsayilan = 'auto';                   Secenekler = @('auto', 'claude', 'codex'); Aciklama = 'Ozetleyici arka uc' },
        @{ Ad = 'BEYIN_CODEX_MODEL'; Varsayilan = '';                       Secenekler = @();                          Aciklama = 'Codex arka ucu model adi (bos = codex varsayilani)' },
        @{ Ad = 'BEYIN_EMBED_MODEL'; Varsayilan = 'bge-m3';                 Secenekler = @();                          Aciklama = 'Ollama gomme modeli' },
        @{ Ad = 'BEYIN_OLLAMA_URL';  Varsayilan = 'http://127.0.0.1:11434'; Secenekler = @();                          Aciklama = 'Ollama adresi (localhost yazma: +2 sn IPv6 denemesi)' },
        @{ Ad = 'BEYIN_FLUSH_BUTCE'; Varsayilan = '200';                    Secenekler = @();                          Aciklama = 'Gunluk model cagrisi tavani (1-1000)' },
        @{ Ad = 'BEYIN_BEKCI_COMMIT';   Varsayilan = '85';                   Secenekler = @();                          Aciklama = 'Kaynak bekcisi: commit yuzdesi esigi (50-99); asilinca oturum acilisinda tek uyari satiri' },
        @{ Ad = 'BEYIN_BEKCI_BOSTA_DK'; Varsayilan = '120';                  Secenekler = @();                          Aciklama = 'Kaynak bekcisi: bosta oturum esigi, dakika (10-1440)' },
        @{ Ad = 'BEYIN_CLAUDE_TAVAN';   Varsayilan = '9500';                 Secenekler = @();                          Aciklama = 'Claude Code acilis baglami toplam tavani, karakter (4000-9800). Claude Code 10.000 karakteri asan kanca ciktisini dosyaya atip modele ~2 KB onizleme verir (2026-10-05 transkriptten olculdu)' },
        @{ Ad = 'BEYIN_BRIFING_KIME';   Varsayilan = 'claude';               Secenekler = @('claude', 'codex');         Aciklama = 'Sahipsiz pano kartinin brifingi kime gider (koordinator ajan). Sahipli kartta karsi ajan secilir.' },
        @{ Ad = 'BEYIN_PANO_ONAY';      Varsayilan = 'zorunlu';              Secenekler = @('zorunlu', 'kapali');        Aciklama = 'Pano karti done icin insan onayi (sohbete onayla TASK-x ya da beyin pano onayla). kapali = eski davranis.' },
        @{ Ad = 'BEYIN_KILL_GUARD';     Varsayilan = 'acik';                 Secenekler = @('acik', 'kapali');           Aciklama = 'Surec oldurme korumasi (PreToolUse kancasi, kayitliysa): ajanlari ad ile toptan olduren ve korunan PID hedefleyen komutlari reddeder. Kayit: kur.ps1 -KillGuard' },
        @{ Ad = 'BEYIN_SONME';          Varsayilan = 'acik';                 Secenekler = @('acik', 'kapali');           Aciklama = 'Kullanim sonmesi: 14 gunde 5+ olculebilir enjeksiyonda hic acilmayan/anilmayan kavram notunun geri getirme skoru x0.6 (beyin kullanim 14 hesaplar; 14 gunden taze not muaf)' },
        @{ Ad = 'BEYIN_AGENTCHEF_KOK';  Varsayilan = (Join-Path $env:USERPROFILE 'Desktop\codex-chef'); Secenekler = @(); Aciklama = 'AgentChef checkout yolu (bekci: codex-process-hygiene.mjs; pano: coordination-board.mjs)' },
        @{ Ad = 'BEYIN_PANO_KOORDINATOR'; Varsayilan = 'leadership_coordinator'; Secenekler = @('backend_coordinator', 'devops_coordinator', 'leadership_coordinator', 'product_coordinator', 'qa_coordinator', 'ui_coordinator', 'marketing_coordinator'); Aciklama = 'beyin pano create icin varsayilan --owner-coordinator (AgentChef katalog koordinatoru); -Koordinator ile ezilir' },
        @{ Ad = 'BEYIN_BRAIN_CLI';   Varsayilan = '';                       Secenekler = @();                          Aciklama = 'brain-cli.mjs yolu (istege bagli, beyin yedek)' },
        @{ Ad = 'BEYIN_DEPO';        Varsayilan = 'https://github.com/ucsahinn/dual-agent-brain'; Secenekler = @();    Aciklama = 'Motor guncelleme deposu (fork ettiysen kendi adresini yaz)' },
        # Dosyaya = $false: 'beyin ayar' listesinde GORUNUR (etkin vault ve kaynagi
        # oradan okunuyor) ama ~\.beyin\ayar.json'a YAZILAMAZ - kaydi vault.txt.
        # Eskiden bu kural uc yerde ayri ayri elle kodluydu (ayar.ps1'de iki, burada bir).
        @{ Ad = 'BEYIN_VAULT';       Varsayilan = (Join-Path $env:USERPROFILE 'Documents\Beyin'); Secenekler = @();     Aciklama = 'Vault yolu (kaydi ~\.beyin\vault.txt)'; Dosyaya = $false }
    )
    return $script:BeyinAyarKayitlari
}

function Get-BeyinAyarVars {
    # Bir ayarin ENVANTERDEKI varsayilani. Calisma zamani varsayilanlari da
    # buradan gelir, boylece kopya kalmaz.
    #
    # NEDEN (2026-09-18 denetiminde olculdu): varsayilan iki yerde durunca
    # kacinilmaz olan oldu ve kactilar. Envanter BEYIN_FLUSH_BUTCE icin '80'
    # diyordu, calisma zamani '200' kullaniyordu. Hicbir ayar yazilmamis bir
    # makinede 'beyin ayar BEYIN_FLUSH_BUTCE' "etkin deger: 80" basarken
    # 'beyin durum' ayni anda "33 / 200 flush tavani" basiyordu: ikisi de
    # kendi kopyasina gore dogruydu, biri kullaniciya yalan soyluyordu.
    param([string]$Ad)
    $kyt = Get-BeyinAyarKayit -Ad $Ad
    if ($null -eq $kyt) { return '' }
    return [string]$kyt.Varsayilan
}

function Get-BeyinAyarKayit {
    # Tek bir envanter satiri, yoksa $null.
    param([string]$Ad)
    foreach ($kyt in (Get-BeyinAyarKayitlari)) { if ($kyt.Ad -eq $Ad) { return $kyt } }
    return $null
}

function Test-BeyinAyarDosyaya {
    # Bu ayar ~\.beyin\ayar.json'a YAZILABILIR mi? Envanterdeki 'Dosyaya'
    # alani belirler; alan yoksa varsayilan EVET.
    param([string]$Ad)
    $kyt = Get-BeyinAyarKayit -Ad $Ad
    if ($null -eq $kyt) { return $true }
    if (-not $kyt.ContainsKey('Dosyaya')) { return $true }
    return [bool]$kyt.Dosyaya
}

function Get-BeyinBrainCli {
    # @{ Yol; Belirsiz } - brain-cli.mjs arama SOZLESMESI, TEK yerde.
    #
    # NEDEN (2026-09-18 denetimi): bu arama DORT ayri kopya halindeydi
    # (beyin.ps1, doktor.ps1 x2, zamanla.ps1). Dorduncusu de yalniz
    # $env:BEYIN_BRAIN_CLI'ye bakiyordu, yani envanterde duran ve
    # dogrulamasi olan BEYIN_BRAIN_CLI ayarini HICBIRI okumuyordu:
    # kullanici 'beyin ayar BEYIN_BRAIN_CLI <yol>' yazar, hicbir sey degisir,
    # hata da almazdi. Ayrica zamanla.ps1'deki "yol cozulemiyorsa gorevi SILME"
    # inceligi diger uc kopyada yoktu.
    #
    # BELIRSIZ ucuncu durumu: kullanici ACIKCA bir yol verdi ama o yol su an
    # cozulemiyor (harici/ag disk bagli degil). Bu "arac yok" KESINLIGI
    # degildir; cagiran taraf buna gore davranmali (gorev silmemeli).
    param([string]$Vault)

    $acik = ''
    try { $acik = [string](Get-BeyinAyar 'BEYIN_BRAIN_CLI' '') } catch { $acik = '' }
    if (-not $acik) { $acik = [string]$env:BEYIN_BRAIN_CLI }
    if ($acik) {
        if (Test-Path -LiteralPath $acik) { return @{ Yol = $acik; Belirsiz = '' } }
        return @{ Yol = $null; Belirsiz = "BEYIN_BRAIN_CLI ayarli ama yol su an cozulemiyor: $acik" }
    }

    $kokler = New-Object System.Collections.Generic.List[string]
    if ($Vault) { $kokler.Add((Split-Path $Vault -Parent)) }
    if ($env:USERPROFILE) {
        $kokler.Add($env:USERPROFILE)
        $kokler.Add((Join-Path $env:USERPROFILE 'Desktop'))
        $kokler.Add((Join-Path $env:USERPROFILE 'Documents'))
        $kokler.Add((Join-Path $env:USERPROFILE 'source\repos'))
    }
    $alt = 'codex-chef\scripts\brain-cli.mjs'
    foreach ($kok in $kokler) {
        if (-not $kok) { continue }
        $c = Join-Path $kok $alt
        if (Test-Path -LiteralPath $c) { return @{ Yol = $c; Belirsiz = '' } }
        # TEK SEVIYE JOKER: bu araclar cogu makinede bir ust 'suite' klasoru
        # icinde durur. O klasorun ADI kisiye ozeldir ve koda yazilamaz
        # (yayin tarayicisi hakli olarak sizinti sayar). Derinlik BIR seviye:
        # daha derini her cagride diski tarardi.
        foreach ($x in @(Get-ChildItem -LiteralPath $kok -Directory -Force -ErrorAction SilentlyContinue)) {
            $c2 = Join-Path $x.FullName $alt
            if (Test-Path -LiteralPath $c2) { return @{ Yol = $c2; Belirsiz = '' } }
        }
    }
    return @{ Yol = $null; Belirsiz = '' }
}

function Test-BeyinAyarDeger {
    # @{ Ok; Deger; Hata; Uyari } - bir ayar degerinin TEK dogrulama noktasi.
    # 'beyin ayar' yazmadan once bunu cagirir, Get-BeyinAyarDenetim diskteki
    # dosyayi denetlerken AYNI kurallari kullanir. Iki yerde iki kural kalmasin.
    #
    # -Zorla yalniz BEYIN_VAULT icin anlamli: motor imzasi (motor\hooks\lib.ps1)
    # tasimayan bir klasoru bilerek vault yapmak icin (ornek: taze kurulum
    # oncesi). Imzasiz bir vault yolu, kancalari gercek vault'tan SESSIZCE
    # koparir - hicbir yerde hata cikmaz.
    param([string]$Ad, [string]$Deger, [switch]$Zorla)

    $s = @{ Ok = $true; Deger = ([string]$Deger).Trim(); Hata = ''; Uyari = '' }
    $v = [string]$s.Deger

    if ($Ad -eq 'BEYIN_OZETLEYICI') {
        $dl = $v.ToLowerInvariant()
        if ($dl -ne 'auto' -and $dl -ne 'claude' -and $dl -ne 'codex') {
            $s.Ok = $false
            $s.Hata = "gecerli degerler: auto | claude | codex  (verilen: '$v')"
        } else { $s.Deger = $dl }
    } elseif ($Ad -eq 'BEYIN_FLUSH_BUTCE') {
        if ($v -notmatch '^\d{1,4}$') {
            $s.Ok = $false
            $s.Hata = "pozitif tam sayi olmali, 1-1000  (verilen: '$v')"
        } else {
            # DIKKAT: burada '$ad' ADI KULLANILAMAZ - PS 5.1'de degisken adlari
            # harf duyarsizdir, '$ad' ile parametre '$Ad' AYNI degiskendir.
            # (Ayni sinif hata bu kod yolunda daha once '$n' ile olculdu:
            # [string] kisitli parametre sayiyi eziyor ve '120' -gt '1000'
            # METIN olarak karsilastiriliyordu.)
            $sayi = [int]$v
            if ($sayi -lt 1 -or $sayi -gt 1000) {
                $s.Ok = $false
                $s.Hata = "1-1000 araliginda olmali (verilen: $sayi)"
            } else { $s.Deger = [string]$sayi }
        }
    } elseif ($Ad -eq 'BEYIN_PANO_KOORDINATOR') {
        $k = $v.Trim().ToLowerInvariant()
        if ($k -and $k -notlike '*_coordinator') { $k = "${k}_coordinator" }
        $secenek = @((Get-BeyinAyarKayit -Ad $Ad).Secenekler)
        if ($secenek -notcontains $k) {
            $s.Ok = $false
            $s.Hata = "gecerli degerler: $($secenek -join ' | ')  (verilen: '$v')"
        } else { $s.Deger = $k }
    } elseif ($Ad -eq 'BEYIN_BRIFING_KIME' -or $Ad -eq 'BEYIN_PANO_ONAY' -or $Ad -eq 'BEYIN_SONME' -or $Ad -eq 'BEYIN_KILL_GUARD') {
        $k = $v.Trim().ToLowerInvariant()
        $secenek = @((Get-BeyinAyarKayit -Ad $Ad).Secenekler)
        if ($secenek -notcontains $k) {
            $s.Ok = $false
            $s.Hata = "gecerli degerler: $($secenek -join ' | ')  (verilen: '$v')"
        } else { $s.Deger = $k }
    } elseif ($Ad -eq 'BEYIN_CLAUDE_TAVAN') {
        if ($v -notmatch '^\d{4}$' -or [int]$v -lt 4000 -or [int]$v -gt 9800) {
            $s.Ok = $false
            $s.Hata = "4000-9800 araliginda tam sayi olmali (verilen: '$v'); 10.000 ustu Claude Code tarafindan dosyaya atilir"
        } else { $s.Deger = [string]([int]$v) }
    } elseif ($Ad -eq 'BEYIN_BEKCI_COMMIT' -or $Ad -eq 'BEYIN_BEKCI_BOSTA_DK') {
        $alt = $(if ($Ad -eq 'BEYIN_BEKCI_COMMIT') { 50 } else { 10 })
        $ust = $(if ($Ad -eq 'BEYIN_BEKCI_COMMIT') { 99 } else { 1440 })
        if ($v -notmatch '^\d{1,4}$' -or [int]$v -lt $alt -or [int]$v -gt $ust) {
            $s.Ok = $false
            $s.Hata = "$alt-$ust araliginda tam sayi olmali (verilen: '$v')"
        } else { $s.Deger = [string]([int]$v) }
    } elseif ($Ad -eq 'BEYIN_OLLAMA_URL') {
        $httpMu  = $v.StartsWith('http://', [System.StringComparison]::OrdinalIgnoreCase)
        $httpsMu = $v.StartsWith('https://', [System.StringComparison]::OrdinalIgnoreCase)
        if (-not ($httpMu -or $httpsMu)) {
            $s.Ok = $false
            $s.Hata = "http:// ya da https:// ile baslamali (verilen: '$v')"
        } else {
            if ($v.IndexOf('localhost', [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
                # Olculdu: .NET once ::1'i dener, Ollama yalniz IPv4 dinler; her yeni
                # surecte ilk istek ~2.2 sn gecikiyor (localhost 2241 ms / 127.0.0.1 354 ms).
                $s.Uyari = "UYARI: 'localhost' her surecte ~2 sn IPv6 gecikmesi ekliyor (olculdu). Onerilen: " + ($v -replace 'localhost', '127.0.0.1')
            }
            $s.Deger = $v.TrimEnd('/')
        }
    } elseif ($Ad -eq 'BEYIN_BRAIN_CLI') {
        $varMi = $false
        try { $varMi = [bool](Test-Path -LiteralPath $v -PathType Leaf) } catch { }
        if (-not $varMi) { $s.Uyari = 'UYARI: bu yolda dosya yok. Yine de kaydedildi; dosya olusunca calisir.' }
    } elseif ($Ad -eq 'BEYIN_DEPO') {
        # NORMALIZE: sondaki '/' ve '.git' kirpilir, saklanan deger tek bicimde
        # olsun - tuketici (guncelle, doktor) adresi raw URL'e cevirirken
        # '.../dual-agent-brain.git/main/...' gibi bozuk yollar uretmesin.
        $u = $v.TrimEnd('/')
        if ($u.EndsWith('.git', [System.StringComparison]::OrdinalIgnoreCase)) {
            $u = $u.Substring(0, $u.Length - 4).TrimEnd('/')
        }
        $s.Deger = $u
        # UYARIR AMA KABUL EDER: GitHub disi bir git barindiricisi (GitLab,
        # Gitea, kendi sunucusu) da gecerli bir hedeftir; burada reddetmek
        # fork'layani kilitlerdi. Yalniz "beklenen bicim bu degil" denir.
        if (-not [regex]::IsMatch($u, '^https://github\.com/[^/]+/[^/]+$', $script:BeyinRxCI)) {
            $s.Uyari = "UYARI: beklenen bicim https://github.com/<kullanici>/<depo> degil (verilen: '$u'). Kabul edildi - GitHub disi bir barindirici olabilir."
        }
    } elseif ($Ad -eq 'BEYIN_VAULT') {
        $klasorMu = $false
        try { $klasorMu = [bool](Test-Path -LiteralPath $v -PathType Container) } catch { }
        if (-not $klasorMu) {
            $s.Ok = $false
            $s.Hata = "klasor yok: '$v'  - vault yolu var olan bir klasor olmali"
        } else {
            # KLASOR OLMASI YETMEZ. Her tuketici (kancalar, launcher, guncelle,
            # ayar'in kendisi) '<yol>\motor\hooks\lib.ps1' arar. Tek bir yazim
            # hatasi ('...\Documents' vs '...\Documents\Beyin') hafizayi
            # koparirdi ve BEYIN_VAULT -Sil ile geri alinamaz.
            $imza = Join-Path $v 'motor\hooks\lib.ps1'
            $motorMu = $false
            try { $motorMu = [bool](Test-Path -LiteralPath $imza -PathType Leaf) } catch { }
            if (-not $motorMu) {
                if ($Zorla) {
                    $s.Uyari = "UYARI: bu klasor vault DEGIL (aranan: $imza). -Zorla verildi. Motor oraya kurulana kadar TUM kancalar sessizce devre disi kalir."
                } else {
                    $s.Ok = $false
                    $s.Hata = "vault degil - aranan dosya yok: '$imza'. Bos bir klasoru bilerek vault yapiyorsan: -Zorla"
                }
            }
        }
    }

    if ($s.Ok -and -not $s.Deger) {
        $s.Ok = $false
        $s.Hata = 'bos deger yazilamaz; varsayilana dondurmek icin -Sil kullan'
    }
    return $s
}

function Get-BeyinAyarDenetim {
    # @{ Tablo = <hashtable>; Sorunlar = <string[]>; Sayi = <int>; Dosya = <yol>; Var = <bool> }
    #
    # SOGUK YOL - kanca yolunda CAGRILMAZ, onbellek kullanmaz, dosyayi her
    # seferinde taze okur.
    #
    # Get-BeyinAyarTablo'nun sicak yol regex'i bilerek DAR: yalniz
    # "BEYIN_<BUYUK_HARF>" anahtarlarini gorur, baska her satiri sessizce atlar.
    # Sozlesme bu ve degismiyor. Sorun SESSIZLIGINDEYDI: kucuk harfle yazilmis
    # bir anahtar dosyada DURUYOR ama motora HIC ULASMIYORDU.
    # Bu fonksiyon ayni dosyayi GENIS bir regex'le ikinci kez okur ve farki
    # soyler; deger kurallari icin Test-BeyinAyarDeger'i cagirir (tek kaynak).
    $dosya = Get-BeyinAyarDosyasi
    $sonuc = @{ Tablo = @{}; Sorunlar = @(); Sayi = 0; Dosya = [string]$dosya; Var = $false }
    $sorun = New-Object System.Collections.Generic.List[string]
    $tablo = @{}

    try {
        if (-not [System.IO.File]::Exists($dosya)) { return $sonuc }
        $sonuc.Var = $true
        $ham = ''
        try { $ham = [System.IO.File]::ReadAllText($dosya, [System.Text.Encoding]::UTF8) } catch {
            $sorun.Add('ayar dosyasi okunamadi (baska bir surecte acik olabilir)')
            $sonuc.Sorunlar = $sorun.ToArray()
            return $sonuc
        }

        # GENIS ayristirici: buyuk/kucuk harf farketmeksizin her "anahtar": "deger".
        $ciftler = New-Object System.Collections.Generic.List[object]
        foreach ($m in [regex]::Matches([string]$ham, '"(?<k>[A-Za-z_][A-Za-z0-9_]*)"\s*:\s*"(?<v>[^"]*)"')) {
            $hv = [string]$m.Groups['v'].Value
            if ($hv.IndexOf('\') -ge 0) { $hv = $hv -replace '\\(.)', '$1' }
            $ciftler.Add(@{ K = [string]$m.Groups['k'].Value; V = $hv })
        }
        if ($ciftler.Count -eq 0) {
            $sorun.Add('dosya var ama hicbir anahtar ayristirilamadi (bozuk JSON?)')
            $sonuc.Sorunlar = $sorun.ToArray()
            return $sonuc
        }

        $bilinen = @{}
        foreach ($kyt in (Get-BeyinAyarKayitlari)) { $bilinen[[string]$kyt.Ad] = $true }

        # Sayac ORDINAL olmali: PS'in kendi hashtable'i harf duyarsizdir ve
        # 'beyin_ozetleyici' ile 'BEYIN_OZETLEYICI' ayni kova olurdu - tam da
        # ayirt etmeye calistigimiz sey.
        $sayac = New-Object 'System.Collections.Generic.Dictionary[string,int]' ([System.StringComparer]::Ordinal)

        foreach ($c in $ciftler) {
            $hk = [string]$c.K
            # Motorun GERCEKTE gordugu bicim: sicak yol regex'inin kabul ettigi.
            if (-not [regex]::IsMatch($hk, '^BEYIN_[A-Z_]+$')) {
                $buyuk = $hk.ToUpperInvariant()
                if ($bilinen.ContainsKey($buyuk)) {
                    $sorun.Add("anahtar buyuk harf degil: $hk (motor bu satiri YOK SAYAR)")
                } else {
                    $sorun.Add("bilinmeyen anahtar: $hk")
                }
                continue
            }
            if ($sayac.ContainsKey($hk)) { $sayac[$hk] = $sayac[$hk] + 1 } else { $sayac[$hk] = 1 }
            $tablo[$hk] = [string]$c.V     # motor gibi: SONUNCU kazanir
        }

        foreach ($ad in @($sayac.Keys)) {
            if ($sayac[$ad] -gt 1) { $sorun.Add("yinelenen anahtar: $ad (motor sonuncuyu alir)") }
        }

        foreach ($ad in @($tablo.Keys | Sort-Object)) {
            if (-not $bilinen.ContainsKey($ad)) { $sorun.Add("bilinmeyen anahtar: $ad"); continue }
            $dv = [string]$tablo[$ad]
            if (-not $dv) { $sorun.Add("$ad bos deger (motor varsayilana duser)"); continue }
            # BEYIN_VAULT'un kaydi vault.txt'tir; ayar.json'daki bir kopya
            # motor icin yalnizca gurultu, yol dogrulamasi burada anlamsiz.
            if ($ad -eq 'BEYIN_VAULT') { $sorun.Add('BEYIN_VAULT ayar dosyasina yazilmaz (kaydi vault.txt)'); continue }
            $d = Test-BeyinAyarDeger -Ad $ad -Deger $dv
            if (-not $d.Ok) {
                if ($ad -eq 'BEYIN_OZETLEYICI')      { $sorun.Add("BEYIN_OZETLEYICI gecersiz: $dv (auto|claude|codex)") }
                elseif ($ad -eq 'BEYIN_FLUSH_BUTCE') { $sorun.Add("BEYIN_FLUSH_BUTCE araliginda degil: $dv (1-1000)") }
                elseif ($ad -eq 'BEYIN_OLLAMA_URL')  { $sorun.Add("BEYIN_OLLAMA_URL protokolsuz: $dv") }
                else { $sorun.Add("$ad gecersiz: $dv") }
            } elseif ($d.Uyari) {
                if ($ad -eq 'BEYIN_DEPO')           { $sorun.Add("BEYIN_DEPO bicimi beklenmedik: $dv") }
                elseif ($ad -eq 'BEYIN_BRAIN_CLI')  { $sorun.Add("BEYIN_BRAIN_CLI yol yok: $dv") }
                elseif ($ad -eq 'BEYIN_OLLAMA_URL') { $sorun.Add("BEYIN_OLLAMA_URL localhost: $dv (her surecte ~2 sn IPv6 gecikmesi)") }
                else { $sorun.Add("$ad -> $($d.Uyari)") }
            }
        }
    } catch {
        $sorun.Add('ayar denetimi tamamlanamadi')
    }

    $sonuc.Tablo = $tablo
    $sonuc.Sayi  = [int]$tablo.Count
    $sonuc.Sorunlar = $sorun.ToArray()
    return $sonuc
}

function Get-BeyinPaths {
    param([string]$Vault)
    return @{
        Vault    = $Vault
        Memory   = Join-Path $Vault '80-memory'      # kuratorlu, motor icin salt-okunur
        Daylogs  = Join-Path $Vault '85-daylogs'     # makine yazar
        Compiled = Join-Path $Vault '86-compiled'    # makine yazar
        State    = Join-Path $Vault 'motor\hooks\.state'
        Sessions = Join-Path $Vault 'motor\hooks\.state\sessions'
        Reflect  = Join-Path $Vault 'motor\hooks\.state\reflect'
        ScrState = Join-Path $Vault 'motor\scripts\.state'
        Scripts  = Join-Path $Vault 'motor\scripts'
        Marks    = Join-Path $Vault 'motor\scripts\.state\watermarks'
        Queue    = Join-Path $Vault 'motor\scripts\.state\queue'
        Slots    = Join-Path $Vault 'motor\scripts\.state\slots'
        Claims   = Join-Path $Vault 'motor\scripts\.state\claims'
        Makbuz   = Join-Path $Vault 'motor\scripts\.state\makbuz'   # kosu makbuzlari (JSONL)
        Handoff  = Join-Path $Vault 'motor\scripts\.state\handoff'  # ajanlar arasi aktarimlar (beyin aktar)
        Board    = Join-Path $Vault 'motor\scripts\.state\board.json' # ortak gorev panosu (beyin pano / AgentChef coordination-board)
        Archive  = Join-Path $Vault '90-archive'
    }
}

# ============================================================================
# BOM'SUZ UTF-8 yazma
# ----------------------------------------------------------------------------
# PowerShell 5.1'de `Set-Content -Encoding UTF8` dosya basina BOM (EF BB BF)
# koyar. Vault'un kuratorlu notlarinda BOM YOK; motorun BOM'lu dosya uretmesi
# tutarsizlik yaratir, bazi YAML/frontmatter ayristiricilarini bozar ve git
# diff'lerini kirletir. Bu yuzden her yazma bu iki fonksiyondan gecer.
# ============================================================================

$script:BeyinUtf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Write-BeyinText {
    # ATOMIK YAZIM (2026-09-10). Onceki surum dogrudan
    # [IO.File]::WriteAllText cagiriyordu; o cagri dosyayi ACILIS aninda
    # TRUNCATE eder, yani icerik yazilmadan once hedef 0 BAYT olur.
    #
    # Bu pencerede surec olurse (Codex 3 sn kanca tavani TUM SUREC AGACINI
    # oldurur; kullanici pane oldurme / Ctrl+C kullaniyor) dosya SIFIR BAYT
    # kalir. flush.ps1 gunluk log icin buna karsi ozel bir koruma yazmisti
    # ("Kayip GERI ALINAMAZ" yorumu), ama ayni risk 86-compiled/index.md
    # (79 kavramin katalogu) ve son-durum.md icin acikta duruyordu.
    #
    # Cozum: gecici dosyaya yaz, sonra YERINE KOY. Yer degistirme isletim
    # sistemi duzeyinde tek adimdir: ya eski dosya ya yeni dosya gorunur,
    # arada bos dosya olmaz.
    param([string]$Path, [string]$Text)
    $tmp = $Path + '.tmp-' + [guid]::NewGuid().ToString('N').Substring(0, 8)
    try {
        [System.IO.File]::WriteAllText($tmp, $Text, $script:BeyinUtf8NoBom)
        if (Test-Path -LiteralPath $Path) {
            try {
                # Replace: hedefin ozniteliklerini korur, tek adimdir.
                [System.IO.File]::Replace($tmp, $Path, $null)
            } catch {
                # Ayni birimde degilse / hedef kilitliyse: Move -Force.
                Move-Item -LiteralPath $tmp -Destination $Path -Force -ErrorAction Stop
            }
        } else {
            Move-Item -LiteralPath $tmp -Destination $Path -Force -ErrorAction Stop
        }
    } catch {
        # Son care: dogrudan yaz (eski davranis). Atomik degil ama hic
        # yazmamaktan iyidir; iz birakiyoruz.
        try { [System.IO.File]::WriteAllText($Path, $Text, $script:BeyinUtf8NoBom) } catch { throw }
    } finally {
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
    }
}

function Add-BeyinText {
    param([string]$Path, [string]$Text)
    # ESZAMANLI EKLEME (2026-10-05, kod incelemesi): AppendAllText dosyayi
    # FileShare.Read ile acar; ayni saniyede 6-8 SessionStart engine.log'a
    # yazarken ikincisi IOException aliyor ve Write-BeyinLog'un catch'i
    # yutuyordu - tani satirlari tam yogun anda kayboluyordu. Paylasimli
    # (ReadWrite) acilis + 4 deneme; yine olmazsa hata cagirana cikar.
    $bytes = $script:BeyinUtf8NoBom.GetBytes($Text)
    $sonHata = $null
    for ($d = 0; $d -lt 4; $d++) {
        try {
            $fs = New-Object System.IO.FileStream($Path, [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write, [System.IO.FileShare]::ReadWrite)
            try { $fs.Write($bytes, 0, $bytes.Length) } finally { $fs.Dispose() }
            return
        } catch { $sonHata = $_; Start-Sleep -Milliseconds (40 * ($d + 1)) }
    }
    throw $sonHata
}

# ============================================================================
# Dosya kilidi
# ----------------------------------------------------------------------------
# Kullanici ayni anda birden fazla claude oturumu calistiriyor. Iki oturum ayni
# saniyede kapanirsa iki flush ayni gunluk log dosyasina yazar: blok araya
# girebilir veya dosya basligi iki kez olusabilir. Yazma bu kilitle serilestirilir.
# ============================================================================

function Invoke-BeyinWithLock {
    param(
        [string]$LockPath,
        [scriptblock]$Action,
        [int]$TimeoutSeconds = 30
    )
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $fs = $null
    while ($null -eq $fs) {
        try {
            $fs = [System.IO.File]::Open($LockPath, 'OpenOrCreate', 'ReadWrite', 'None')
        } catch {
            if ((Get-Date) -ge $deadline) { throw "kilit alinamadi: $LockPath" }
            Start-Sleep -Milliseconds 200
        }
    }
    try { & $Action } finally { $fs.Close(); $fs.Dispose() }
}

# ============================================================================
# Oturum bazli durum
# ----------------------------------------------------------------------------
# Eskiden prompt_count / session_start_time TEK dosyaydi. Es zamanli iki oturum
# birbirinin sayacini eziyordu: A oturumu 20 mesajdan sonra kapanirken B'nin
# sifirlanmis sayacini gorup "hafiza guncellenmedi" isareti birakabiliyordu.
# Artik her oturum kendi session_id dosyasini tutuyor.
# ============================================================================

function Get-BeyinSessionKey {
    param([string]$SessionId)
    if ([string]::IsNullOrWhiteSpace($SessionId)) { return 'default' }
    # dosya adi guvenligi: yalniz alfanumerik, tire, alt tire
    $k = ($SessionId -replace '[^A-Za-z0-9_-]', '')
    if ([string]::IsNullOrWhiteSpace($k)) { return 'default' }
    if ($k.Length -gt 64) { $k = $k.Substring(0, 64) }
    return $k
}

function Get-BeyinSessionState {
    param([hashtable]$Paths, [string]$SessionId)
    $key = Get-BeyinSessionKey -SessionId $SessionId
    $f = Join-Path $Paths.Sessions "$key.json"
    if (Test-Path -LiteralPath $f) {
        try {
            $o = Get-Content -LiteralPath $f -Raw -Encoding UTF8 | ConvertFrom-Json
            # 'kavram': bu oturumda ZATEN hatirlatilmis kavram notlarinin
            # dosya adlari. Icerik-tabanli geri getirme ayni notu tekrar
            # basmasin diye tutulur - her mesajda tekrarlanan ayni blok kisa
            # surede gorulmez hale gelir ve baglam butcesini bosa harcar.
            # (Eski durum dosyalarinda bu alan yok; bos dizi ile aciliyor.)
            $kavram = @()
            if ($o.PSObject.Properties['kavram'] -and $o.kavram) { $kavram = @($o.kavram) }
            # 'agent' (Faz 2G): oturumu hangi ajan acti - canli gorunum bunu okur.
            $agent = ''
            if ($o.PSObject.Properties['agent'] -and $o.agent) { $agent = [string]$o.agent }
            # 'pcSayi' / 'pcGun' (2026-09-17): bu oturumun BUGUN pre-compact
            # yoluyla harcadigi model cagrisi sayisi. Gunluk butceyi tek bir
            # uzun oturumun yiyip digerlerini ac birakmasini onleyen pay
            # sayaci. Tarih degisince sifirlanir.
            $pcSayi = 0
            if ($o.PSObject.Properties['pcSayi']) { $pcSayi = [int]$o.pcSayi }
            $pcGun = ''
            if ($o.PSObject.Properties['pcGun'] -and $o.pcGun) { $pcGun = [string]$o.pcGun }
            # 'herdrPane' (2026-10-04, plan #8): oturumu acan Herdr pane kimligi
            # (HERDR_PANE_ID). Kaynak bekcisi bosta oturumu 'herdr pane close'
            # satiriyla gosterebilsin diye. Herdr yoksa bos.
            $herdrPane = ''
            if ($o.PSObject.Properties['herdrPane'] -and $o.herdrPane) { $herdrPane = [string]$o.herdrPane }
            # 'seenHandoff' (plan #11): bu oturumda zaten gosterilmis aktarim
            # kimlikleri - ayni oturumda ikinci acilis (resume/compact) tekrar
            # basmasin.
            $seenHandoff = @()
            if ($o.PSObject.Properties['seenHandoff'] -and $o.seenHandoff) { $seenHandoff = @($o.seenHandoff) }
            # 'handoffDamga' (2026-10-06): prompt-counter aktarim klasoru damgasi (dosya
            # sayisi + en yeni yazim); degismediyse JSON okunmaz. 'pid': oturumun ajan
            # sureci (kill guard korunan PID kumesi). Set- tarafiyla BIRLIKTE eklendi.
            $handoffDamga = ''
            if ($o.PSObject.Properties['handoffDamga'] -and $o.handoffDamga) { $handoffDamga = [string]$o.handoffDamga }
            $oturumPid = 0
            if ($o.PSObject.Properties['pid'] -and $o.pid) { $oturumPid = [int]$o.pid }
            return @{
                start       = [int64]$o.start
                prompts     = [int]$o.prompts
                cwd         = [string]$o.cwd
                kavram      = $kavram
                agent       = $agent
                pcSayi      = $pcSayi
                pcGun       = $pcGun
                herdrPane   = $herdrPane
                seenHandoff = $seenHandoff
                handoffDamga = $handoffDamga
                pid         = $oturumPid
                key         = $key
            }
        } catch { }
    }
    return @{ start = 0; prompts = 0; cwd = ''; kavram = @(); agent = ''; pcSayi = 0; pcGun = ''; herdrPane = ''; seenHandoff = @(); handoffDamga = ''; pid = 0; key = $key }
}

function Set-BeyinSessionState {
    param([hashtable]$Paths, [hashtable]$State)
    New-Item -ItemType Directory -Force -Path $Paths.Sessions | Out-Null
    $f = Join-Path $Paths.Sessions "$($State.key).json"
    # 'kavram' ALANI DA YAZILIR. Eskiden bu fonksiyon yalniz uc sabit alani
    # serilestiriyordu; cagiran tarafin ekledigi her alan SESSIZCE dusuyordu.
    # Sonucu: geri getirme katmani "bu kavrami zaten gosterdim" bilgisini
    # kaydediyor saniyordu ama kayit hicbir zaman diske gitmiyordu ve ayni
    # not her mesajda tekrar basiliyordu.
    $kavram = @()
    if ($State.ContainsKey('kavram') -and $State['kavram']) { $kavram = @($State['kavram']) }
    $agent = ''
    if ($State.ContainsKey('agent') -and $State['agent']) { $agent = [string]$State['agent'] }
    $pcSayi = 0
    if ($State.ContainsKey('pcSayi')) { $pcSayi = [int]$State['pcSayi'] }
    $pcGun = ''
    if ($State.ContainsKey('pcGun') -and $State['pcGun']) { $pcGun = [string]$State['pcGun'] }
    # herdrPane + seenHandoff: Get- tarafiyla BIRLIKTE eklendi (bu fonksiyonun
    # tarihindeki "eklenen alan sessizce dusuyordu" tuzagi).
    $herdrPane = ''
    if ($State.ContainsKey('herdrPane') -and $State['herdrPane']) { $herdrPane = [string]$State['herdrPane'] }
    $seenHandoff = @()
    if ($State.ContainsKey('seenHandoff') -and $State['seenHandoff']) { $seenHandoff = @($State['seenHandoff']) }
    $handoffDamga = ''
    if ($State.ContainsKey('handoffDamga') -and $State['handoffDamga']) { $handoffDamga = [string]$State['handoffDamga'] }
    $oturumPid = 0
    if ($State.ContainsKey('pid') -and $State['pid']) { $oturumPid = [int]$State['pid'] }
    $json = @{ start = $State.start; prompts = $State.prompts; cwd = $State.cwd; kavram = $kavram; agent = $agent; pcSayi = $pcSayi; pcGun = $pcGun; herdrPane = $herdrPane; seenHandoff = $seenHandoff; handoffDamga = $handoffDamga; pid = $oturumPid } |
            ConvertTo-Json -Compress
    Write-BeyinText -Path $f -Text $json
}

function Update-BeyinSessionState {
    # OKU-DEGISTIR-YAZ, oturum basina KILIT ALTINDA.
    #
    # NEDEN (kanca denetimi 2026-09-17, kosarak olculdu): prompt sayaci
    # Get-BeyinSessionState + elle artis + Set-BeyinSessionState yapiyordu,
    # arada kilit YOKTU. Ayni session_id ile 5 paralel UserPromptSubmit
    # kosuldugunda sonuc prompts=1 cikti (beklenen 5). Durum dosyasi
    # bozulmuyor (Write-BeyinText atomik), yalniz artislar kayboluyor.
    # Etki: SessionEnd'in `prompts >= 2` kapisi - kaybeden bir oturum
    # "cok kisa" sayilip hic ozetlenmeyebilir. Ayni dosyadaki Test-BeyinBudget
    # ve Add-BeyinCounter zaten Invoke-BeyinWithLock kullaniyordu; oturum
    # durumu bu korumadan atlanmisti.
    #
    # Kilit oturum basina: iki farkli oturum birbirini beklemez.
    # Kilit alinamazsa (2 sn) SESSIZCE kilitsiz yola duser - kanca yolundayiz,
    # sayac kaybi bir oturumu ozetlenmemis birakabilir ama kanca tavanini
    # asmak TUM oturumu kaybettirir. Kotu olan iki seyden az kotusu.
    param(
        [hashtable]$Paths,
        [string]$SessionId,
        [scriptblock]$Degistir,
        [int]$TimeoutSeconds = 2
    )
    # ALT KAPSAM TUZAGI (2026-09-18, kosarak olculdu - ayni ders bu dosyada
    # Test-BeyinBudget'te zaten yaziliydi, burada atlanmisti):
    # `& $Action` scriptblock'u ALT KAPSAMDA calisir. Icerideki `$sonuc = $st`
    # atamasi disariya YANSIMAZ; fonksiyon $null donuyordu. Diske yazim
    # DOGRUYDU, kaybolan yalniz donus degeriydi - bu yuzden hicbir hata
    # gorunmedi ve hata 2026-09-17'den 2026-09-18'e kadar sessizce yasadi.
    #
    # OLCULEN ETKI (prompt-counter.ps1, $st = $null ile):
    #   - satir 56 `$st.ContainsKey('kavram')` null uzerinde method cagrisi
    #     firlatti; satir 44'teki try/catch onu yuttu -> ICERIK-TABANLI GERI
    #     GETIRMENIN TAMAMI hic calismadi. Makbuz kaniti: 'retrieval' satiri
    #     15 Eyl=24, 16 Eyl=19, 17 Eyl=23, 18 Eyl=0.
    #   - `$null % 15 -eq 0` HER ZAMAN dogru -> protokol hatirlatmasi 15
    #     mesajda bir degil HER mesajda enjekte edildi (sayi da bos basildi:
    #     "[Hafiza] . mesaj.").
    #   - `Set-BeyinSessionState -State $null` -> anahtarsiz '.json' adli cop
    #     dosya her promptta yeniden yazildi.
    #
    # COZUM: karar scriptblock'un DONUS DEGERI ile disari tasiniyor. Disaridan
    # OKUMA calisir, sorun yalniz ATAMADA.
    $key = Get-BeyinSessionKey -SessionId $SessionId
    New-Item -ItemType Directory -Force -Path $Paths.Sessions | Out-Null
    $kilit = Join-Path $Paths.Sessions "$key.lock"
    $sonuc = $null
    try {
        $sonuc = Invoke-BeyinWithLock -LockPath $kilit -TimeoutSeconds $TimeoutSeconds -Action {
            $st = Get-BeyinSessionState -Paths $Paths -SessionId $SessionId
            $st = & $Degistir $st
            if ($st) { Set-BeyinSessionState -Paths $Paths -State $st | Out-Null }
            $st
        }
    } catch {
        if ([string]$_.Exception.Message -like 'kilit alinamadi*') {
            # Kilit alinamadi: korumasiz yoldan devam et.
            $st = Get-BeyinSessionState -Paths $Paths -SessionId $SessionId
            $st = & $Degistir $st
            if ($st) { Set-BeyinSessionState -Paths $Paths -State $st | Out-Null }
            $sonuc = $st
        } else {
            # BASKA HATA (2026-10-05, kod incelemesi): yazim ya da $Degistir
            # firlattiysa degisikligi IKINCI kez uygulama - eskiden her istisna
            # 'kilit alinamadi' sayilip blok yeniden kosuyor, prompts +2 artiyordu.
            try { Write-BeyinLog -Vault $Paths.Vault -Message "session-state: $($_.Exception.Message)" } catch { }
            $sonuc = Get-BeyinSessionState -Paths $Paths -SessionId $SessionId
        }
    }
    # Scriptblock beklenmedik bir sey de yazdiysa son nesneyi al; hashtable
    # degilse sozlesmeyi bozmaktansa diskten TAZE oku. Bu fonksiyonun $null
    # donmesi cagiran tarafta sessiz ozellik olumu demek - bir daha olmasin.
    if ($sonuc -is [object[]]) { $sonuc = @($sonuc | Where-Object { $_ -is [hashtable] })[-1] }
    if ($sonuc -isnot [hashtable]) {
        $sonuc = Get-BeyinSessionState -Paths $Paths -SessionId $SessionId
    }
    return $sonuc
}

function Remove-BeyinSessionState {
    param([hashtable]$Paths, [string]$SessionId)
    $key = Get-BeyinSessionKey -SessionId $SessionId
    Remove-Item -LiteralPath (Join-Path $Paths.Sessions "$key.json") -Force -ErrorAction SilentlyContinue
}

function Clear-BeyinStaleSessions {
    # Cokerek kapanan oturumlarin durum dosyalari birikmesin.
    param([hashtable]$Paths, [int]$OlderThanDays = 0)
    if ($OlderThanDays -le 0) { $OlderThanDays = $script:BeyinSessionStaleDays }
    if (-not (Test-Path -LiteralPath $Paths.Sessions)) { return }
    $cut = (Get-Date).AddDays(-$OlderThanDays)
    foreach ($f in @(Get-ChildItem -LiteralPath $Paths.Sessions -Filter '*.json' -File -ErrorAction SilentlyContinue)) {
        if ($f.LastWriteTime -lt $cut) { Remove-Item -LiteralPath $f.FullName -Force -ErrorAction SilentlyContinue }
    }
}

# ============================================================================
# DERLEME KUYRUGU
# ----------------------------------------------------------------------------
# Bugunun gunluk logu gun icinde BUYUMEYE devam eder: her oturum kapanisi yeni
# blok ekler. Naif "derlendi" isareti bu yuzden hataliydi: log 18:00'de
# derlenip isaretlenince aksam eklenen bloklar bir daha HIC derlenmiyordu.
#
# Cozum: isaret iki durumlu.
#   name|partial -> derlendi ama gun henuz kapanmamisti
#   name|final   -> gun kapandiktan sonra derlendi, bir daha bakilmaz
#
# Boylece bugunun logu en fazla iki kez derlenir: gun icinde bir kez (partial),
# ertesi gun bir kez (final).
# ============================================================================

function Get-BeyinSeenMap {
    param([hashtable]$Paths)
    $map = @{}
    $f = Join-Path $Paths.ScrState 'compiled_daylogs.txt'
    if (-not (Test-Path -LiteralPath $f)) { return $map }
    foreach ($line in @(Get-Content -LiteralPath $f -Encoding UTF8 -ErrorAction SilentlyContinue)) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $parts = $line.Split('|')
        $name = $parts[0].Trim()
        $state = if ($parts.Count -gt 1) { $parts[1].Trim() } else { 'final' }  # eski format = final
        if (-not $name) { continue }
        # final her zaman kazanir
        if ($map.ContainsKey($name) -and $map[$name] -eq 'final') { continue }
        $map[$name] = $state
    }
    return $map
}

function Get-BeyinSeenDetail {
    # Get-BeyinSeenMap'in ayrintili hali: durum + DENEME SAYISI.
    # Bicim: name|state|attempts  (ucuncu alan yeni; eski 2 alanli satirlar
    # attempts=0 sayilir - Split('|') zaten geriye uyumlu).
    param([hashtable]$Paths)
    $map = @{}
    $f = Join-Path $Paths.ScrState 'compiled_daylogs.txt'
    if (-not (Test-Path -LiteralPath $f)) { return $map }
    foreach ($line in @(Get-Content -LiteralPath $f -Encoding UTF8 -ErrorAction SilentlyContinue)) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $parts = $line.Split('|')
        $name = $parts[0].Trim()
        if (-not $name) { continue }
        $state = if ($parts.Count -gt 1) { $parts[1].Trim() } else { 'final' }
        $att   = 0
        if ($parts.Count -gt 2) { [void][int]::TryParse($parts[2].Trim(), [ref]$att) }
        # 4. alan (2026-09-16): 'final' yazildigi andaki dosya boyutu. Gece sirasi
        # (derle 03:00 -> topla 03:20) dune final'den SONRA blok ekliyordu ve o
        # bloklar hic derlenmiyordu (olculdu: 2026-09-15.md final sonrasi +19 KB).
        $bayt  = [long]0
        if ($parts.Count -gt 3) { [void][long]::TryParse($parts[3].Trim(), [ref]$bayt) }
        if ($map.ContainsKey($name)) {
            # final -> partial gerilemesi yok; final -> final ise SONRAKI satir kazanir (yeni boyut)
            if ($map[$name].State -eq 'final' -and $state -ne 'final') { continue }
            if ($att -lt $map[$name].Attempts) { $att = $map[$name].Attempts }
        }
        $map[$name] = @{ State = $state; Attempts = $att; Bayt = $bayt }
    }
    return $map
}

function Get-BeyinPendingDaylogs {
    param([hashtable]$Paths)
    $today = ((Get-Date).ToString('yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture))
    $seen = Get-BeyinSeenDetail -Paths $Paths
    $all = @(Get-ChildItem -LiteralPath $Paths.Daylogs -Filter '*.md' -File -ErrorAction SilentlyContinue |
             Where-Object { $_.Name -cmatch '^\d{4}-\d{2}-\d{2}\.md$' } |
             Sort-Object Name)
    return @($all | Where-Object {
        if (-not $seen.ContainsKey($_.Name)) { return $true }    # hic derlenmemis
        $d = $seen[$_.Name]
        if ($d.State -eq 'final') {
            # FINAL AMA BUYUMUS (2026-09-16): final damgasindan sonra blok eklendiyse
            # (yetim toplama, kuyruk drenaji) gun yeniden derlenir. Boyut bilinmiyorsa
            # (eski 3 alanli kayit) eski davranis: bitti say.
            if ($d.Bayt -gt 0 -and $_.Length -gt $d.Bayt) { return $true }
            return $false
        }
        # DENEME TAVANI - '-First' (kronolojik) siralamanin zorunlu esi.
        # Tek basina -First, takilmis eski bir gunun korpus basini sonsuza
        # kadar isgal etmesine yol acardi: her gece ayni gun denenir, arkasi
        # hic sira almaz. Tavan dolunca gun 'final' sayilir ve loglanir.
        if ($d.Attempts -ge $script:BeyinMaxCompileAttempts) { return $false }
        return ($_.BaseName -lt $today)                          # partial + gun kapandi -> tekrar derle
    })
}

function Add-BeyinCompileAttempt {
    # DENEME kaydi - model cagrisindan ONCE, korpusa giren gunler icin.
    #
    # Neden basaridan ayri: takilma tam da BASARISIZLIKTA oluyor. Sayaci
    # yalnizca basarida artirmak, korunmasi gereken tek senaryoyu kacirir -
    # her gece ayni eski gun korpusa girer, model cagrisi patlar, hicbir sey
    # isaretlenmez, ertesi gece yine ayni gun basa gecer ve arkasindaki
    # gunler '-First' siralamasinda hic sira almaz.
    #
    # YALNIZ KAPALI gunler sayilir. Bugunun hala buyuyen logu gun icinde
    # birkac kez derlenebilir; bunlari saymak, gun kapanmadan tavana carpip
    # o gunun bir daha hic derlenmemesine yol acardi.
    param([hashtable]$Paths, [string[]]$Names)
    $today = ((Get-Date).ToString('yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture))
    $onceki = Get-BeyinSeenDetail -Paths $Paths
    $f = Join-Path $Paths.ScrState 'compiled_daylogs.txt'
    $txt = ''
    foreach ($n in @($Names)) {
        if (-not $n) { continue }
        $base = [IO.Path]::GetFileNameWithoutExtension($n)
        if ($base -ge $today) { continue }        # acik gun sayilmaz
        $durum = 'partial'
        $att = 1
        if ($onceki.ContainsKey($n)) {
            if ($onceki[$n].State -eq 'final') { continue }   # zaten kapanmis
            $durum = $onceki[$n].State
            $att = [int]$onceki[$n].Attempts + 1
        }
        $txt += "$n|$durum|$att`n"
    }
    if ($txt) { Add-BeyinText -Path $f -Text $txt }
}

function Add-BeyinSeenDaylogs {
    # BASARI kaydi. Bicim: name|state|attempts
    #
    # Yalniz KORPUSA GERCEKTEN GIREN gunler icin cagrilmali. Onceki surum
    # secilen tum gunleri isaretliyordu; korpus karakter tavaniyla kirpildigi
    # icin ICERIGI HIC OKUNMAMIS gunler 'derlendi' sayilip bir daha hic
    # islenmiyordu (sessiz bilgi kaybi).
    #
    # Deneme sayacini ARTIRMAZ - o Add-BeyinCompileAttempt'in isi. Burada
    # yalnizca mevcut sayac korunur.
    param([hashtable]$Paths, [string[]]$Names)
    $today = ((Get-Date).ToString('yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture))
    $onceki = Get-BeyinSeenDetail -Paths $Paths
    $f = Join-Path $Paths.ScrState 'compiled_daylogs.txt'
    $txt = ''
    foreach ($n in @($Names)) {
        if (-not $n) { continue }
        $base = [IO.Path]::GetFileNameWithoutExtension($n)
        $state = if ($base -lt $today) { 'final' } else { 'partial' }
        $att = 0
        if ($onceki.ContainsKey($n)) { $att = [int]$onceki[$n].Attempts }
        # final ise o anki boyutu da yaz: sonradan buyurse Get-BeyinPendingDaylogs yeniden secer
        $bayt = [long]0
        if ($state -eq 'final') { try { $bayt = [long](Get-Item -LiteralPath (Join-Path $Paths.Daylogs $n) -ErrorAction Stop).Length } catch { $bayt = 0 } }
        $txt += "$n|$state|$att|$bayt`n"
    }
    if ($txt) { Add-BeyinText -Path $f -Text $txt }
}

# ============================================================================
# Not okuma
# ============================================================================

function Read-BeyinFileHead {
    # Notun basindaki YAML frontmatter'i atar; baglama yalniz govde girer.
    # Frontmatter model icin gurultu, bosuna context harcar.
    param([string]$Path, [int]$Lines = 60)
    if (-not (Test-Path -LiteralPath $Path)) { return '' }
    try {
        $all = @(Get-Content -LiteralPath $Path -Encoding UTF8)
        if ($all.Count -eq 0) { return '' }
        # BOM varsa ilk satirin basindan temizle
        $all[0] = $all[0] -replace ("^" + [char]0xFEFF), ''
        if ($all[0].Trim() -eq '---') {
            $end = -1
            for ($i = 1; $i -lt $all.Count; $i++) {
                if ($all[$i].Trim() -eq '---') { $end = $i; break }
            }
            if ($end -ge 0) {
                if ($end + 1 -ge $all.Count) { return '' }
                $all = $all[($end + 1)..($all.Count - 1)]
            }
        }
        $s = 0
        while ($s -lt $all.Count -and [string]::IsNullOrWhiteSpace($all[$s])) { $s++ }
        if ($s -ge $all.Count) { return '' }
        $all = $all[$s..($all.Count - 1)]

        # KIRPMA ARTIK SESSIZ DEGIL.
        #
        # OLCULDU (2026-08-31). Olcumu iki kez yapmak gerekti: ilk sayim HAM satir
        # sayisini tavanla karsilastirmisti, oysa bu fonksiyon once frontmatter'i
        # atiyor. Dogru sayim, frontmatter sonrasi GOVDE uzerinden:
        #
        #     current-context.md   82 satir govde / tavan 45  -> 37 satir dusuyor
        #     rules.md             55 satir govde / tavan 50  ->  5 satir dusuyor
        #     active-threads.md    26 satir govde / tavan 35  ->  hic dusmuyor
        #
        # Asil kayip current-context'te: govdenin yarisindan fazlasi hicbir yerde
        # soylenmeden dusuyordu. rules.md'de dusen 5 satir "nasil eklenir"
        # boilerplate'iydi; kurallarin kendisi giriyordu. (Ilk yanlis sayima
        # dayanarak "kullanicinin uc kurali ulasmiyor" denmisti - dogru degildi.)
        #
        # Yine de kirpmanin sessiz olmasi basli basina kusur: dosya bir gun
        # tavani astiginda kimse haberdar olmuyor ve model eksik bir notu tam
        # sanip devam ediyor. Tavani kaldirmiyoruz (baglam butcesi gercek), ama
        # kirpma GORUNUR oluyor: model neyi gormedigini bilir ve gerekirse
        # dosyayi kendisi okur.
        if ($all.Count -gt $Lines) {
            $kalan = $all.Count - $Lines
            $all = $all[0..($Lines - 1)]
            $all += ''
            $all += "[... bu notun $kalan satiri daha var, baglam tavani nedeniyle kirpildi. Tamami gerekiyorsa dosyayi kendin oku: $Path]"
        }
        return ($all -join "`n").TrimEnd()
    } catch { return '' }
}

# ============================================================================
# Kanca sozlesmesi
# ============================================================================

function Write-BeyinHookContext {
    # Claude Code hook sozlesmesi: stdout'a tek satir JSON.
    #
    # HAM BAYT yaziyoruz: [Console]::Out.Write, [Console]::OutputEncoding'i
    # kullanir ve konsolsuz spawn'da o deger IBM437 oluyor -> Turkce hafiza
    # gecersiz UTF-8 olarak cikiyor. Ayrica PS 5.1'in ConvertTo-Json'i
    # non-ASCII'yi \uXXXX'e KACISLAMAZ, yani JSON'da ham Turkce karakter durur.
    # Ikisi birlesince kanca ciktisi bozulur. Bayt yolu encoding'i devre disi
    # birakir.
    param([string]$EventName, [string]$Context)
    if ([string]::IsNullOrWhiteSpace($Context)) { return }
    $payload = @{
        hookSpecificOutput = @{
            hookEventName     = $EventName
            additionalContext = $Context
        }
    }
    $json = $payload | ConvertTo-Json -Depth 5 -Compress
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
        $out = [Console]::OpenStandardOutput()
        $out.Write($bytes, 0, $bytes.Length)
        $out.Flush()
        $out.Close()
    } catch {
        [Console]::Out.Write($json)   # son care
    }
}

function Read-BeyinHookPayload {
    # Claude Code hook payload'ini stdin'den UTF-8 olarak okur.
    #
    # ENCODING SORUNU: [Console]::In.ReadToEnd() girdiyi [Console]::InputEncoding
    # ile cozer. Konsol mirasi olmayan bir spawn'da bu deger IBM437 olabiliyor ve
    # UTF-8 payload sessizce bozuluyor -- JSON yapisi ASCII oldugu icin
    # ConvertFrom-Json BASARILI olur, yalniz cwd/transcript_path gibi degerlerdeki
    # Turkce karakterler bozulur (vault algilanmaz, transkript bulunamaz).
    #
    # NEDEN OpenStandardInput DEGIL: PS 5.1'de -File ile calisan bir betikte
    # [Console]::OpenStandardInput() 0 BAYT dondurur (PowerShell handle'i kendisi
    # sarmalar). Olculdu. O yuzden [Console]::In kullanip encoding'i kurtariyoruz.
    #
    # KURTARMA: tek baytlik kod sayfalari (IBM437, 1254 ...) her bayti bir
    # karaktere birebir esler, yani mis-decode ROUND-TRIP edilebilir: yanlis
    # encoding ile bayta cevir, UTF-8 olarak yeniden coz.
    # 'source' (SessionStart: startup|resume|clear|compact) ve 'reason'
    # (SessionEnd) 2026-09-10'da eklendi: resume/compact yeniden atesledinde
    # prompt sayacinin sifirlanmasi uzun Codex thread'lerini dusuruyordu.
    $obj = @{ session_id = ''; transcript_path = ''; cwd = ''; hook_event_name = ''; trigger = ''; source = ''; reason = '' }

    # DIKKAT: [Console]::InputEncoding'e ATAMA YAPMA. Atama mevcut Console.In
    # TextReader'ini gecersiz kilip yeniden kuruyor; stdin bir PIPE oldugunda
    # tamponlanmis veri dusuyor ve payload BOS geliyor (olculdu). Encoding'i
    # degistirmek yerine okuduktan sonra round-trip ile kurtariyoruz.
    try {
        $raw = [Console]::In.ReadToEnd()
        if ([string]::IsNullOrWhiteSpace($raw)) { return $obj }

        $enc = $null
        try { $enc = [Console]::InputEncoding } catch { }
        # IsSingleByte (2026-10-05): round-trip kurtarma yalniz tek baytli kod sayfalarinda
        # kayipsizdir; UTF-16 (1200) ya da 932/949 gibi cok baytli girdide payload bozulurdu.
        if ($enc -and $enc.CodePage -ne 65001 -and $enc.IsSingleByte) {
            try {
                $bytes = $enc.GetBytes($raw)
                $raw = [System.Text.Encoding]::UTF8.GetString($bytes)
            } catch { }
        }

        $p = $raw | ConvertFrom-Json
        # 'source' ve 'reason' (2026-09-10, bagimsiz denetim): bu iki alan
        # LISTEDE YOKTU, yani hicbir zaman kopyalanmiyordu. Sonuc olu koddu:
        #
        #   session-start.ps1:34  $devam = ($hook.source -eq 'resume' -or ...)
        #
        # $hook.source her zaman bos oldugu icin $devam HER ZAMAN $false idi ve
        # prompt sayaci resume/compact sonrasinda da sifirlaniyordu. Sonucu:
        # devam eden bir oturum "2 prompt'tan kisa" gorunup ozetlenmeden
        # kapaniyordu. Koruma yazilmisti ama hic calismiyordu.
        #
        # 'reason' ayni sinif: SessionEnd'in neden atesledigini (exit / clear /
        # logout) tasir; tani icin gerekli.
        # 'prompt' / 'user_prompt': UserPromptSubmit'te kullanicinin yazdigi
        # metin. Icerik-tabanli geri getirme bunu SORGU olarak kullanir.
        # Bu alan yalniz bellekte skorlama icin okunur; hicbir yere YAZILMAZ
        # (gunluk log, motor logu ve isaret dosyalari dahil).
        foreach ($k in @('session_id','transcript_path','cwd','hook_event_name','trigger','source','reason','prompt','user_prompt')) {
            $v = $p.PSObject.Properties[$k]
            if ($v -and $null -ne $v.Value) { $obj[$k] = [string]$v.Value }
        }
        # VERBATIM ONEK (2026-09-16, denetim): Codex resume edilmis thread'lerde
        # transcript_path '\\?\C:\...' bicimiyle geliyor. Olculdu: 6 rollout icin biri
        # onekli biri duz iki ayri isaret/kuyruk kimligi olustu, ayni bayt araligi iki
        # kez ozetlendi. Onek burada soyulur; Get-BeyinKey de ayni normalizasyonu yapar.
        foreach ($k2 in @('transcript_path', 'cwd')) { $obj[$k2] = ConvertTo-BeyinDuzYol -Path ([string]$obj[$k2]) }
    } catch { }
    return $obj
}

# ============================================================================
# KULTUR-BAGIMSIZ REGEX  (bu makine icin ZORUNLU)
# ----------------------------------------------------------------------------
# Bu makinenin kulturu tr-TR. .NET'te Turkce kultur altinda 'I'.ToLower() = 'i'
# (U+0131, noktasiz i) olur. Sonuc: buyuk/kucuk harf duyarsiz eslesme buyuk 'I'
# iceren her sey icin SESSIZCE BOZULUR:
#
#   'API_KEY' -match 'api_key'   -> False
#   'ISTANBUL' -match 'istanbul' -> False
#   [regex]::IsMatch('I','^[A-Z]$', 'IgnoreCase') -> False
#
# PowerShell'in -match, -imatch, -replace operatorleri ve Select-String de
# etkilenir; hicbiri CultureInvariant kullanmaz. Tek dogru cozum asagidaki
# secenek kumesidir. Motorda buyuk/kucuk harf duyarsiz her eslesme bu
# yardimcilardan gecmek ZORUNDA - yoksa sir taramasi yanlis negatif verir.
# ============================================================================

$script:BeyinRxCI = [System.Text.RegularExpressions.RegexOptions]'IgnoreCase,CultureInvariant'
$script:BeyinRxCIM = [System.Text.RegularExpressions.RegexOptions]'IgnoreCase,CultureInvariant,Multiline'
$script:BeyinRxCIS = [System.Text.RegularExpressions.RegexOptions]'IgnoreCase,CultureInvariant,Singleline'
$script:BeyinRxCIMS = [System.Text.RegularExpressions.RegexOptions]'IgnoreCase,CultureInvariant,Multiline,Singleline'

# REGEX ZAMAN ASIMI - DERINLEMESINE SAVUNMA (denetim 2026-09-17).
# ----------------------------------------------------------------------------
# Yukaridaki dortlu SECENEK kumesidir; zaman asimi seceneklerle verilemez, ayri
# bir [TimeSpan] argumanidir ([regex]::Replace(metin, desen, yerine, secenek,
# ZAMAN) / IsMatch / Matches asiri yuklemeleri, .NET 4.5+).
#
# NEDEN: guvenilmez metinde katastrofik geri izleme ISTISNA DEGIL ASILMA uretir.
# Protect-BeyinSecrets'in fail-closed catch'i yalniz FIRLAYAN bir hatayi gorur;
# asilan bir Replace hicbir zaman catch'e ulasmaz, surec orada durur ve kimse
# "sir maskelenmedi" bilgisini alamaz. Zaman asimi asilmayi FIRLATMAYA cevirir,
# boylece mevcut fail-closed yol calisir.
#
# DEGER GEREKCESI: denetimde 60000 karakterlik korpus tavaninda olculen EN KOTU
# tam redaksiyon gecisi 1.19 sn idi (tum desenler birlikte). Buradaki tavan TEK
# desen icindir, yani tipik desen basina maliyetin (~60 ms) yaklasik 80 katidir.
# Somut bir somuru vakasi BULUNAMADI; bu kapatilmamis bir varsayimi kapatir,
# mesru bir girdiyi kesmez.
$script:BeyinRxZamanAsimi = [TimeSpan]::FromSeconds(5)

function Test-BeyinRxZamanli {
    # Zaman asimli, buyuk-kucuk harf duyarsiz IsMatch. Asim = eslesme yok
    # (gecerli metni engellemek yerine o deseni atlar) ama engine.log'a dusulur.
    param([string]$Metin, [string]$Desen, [string]$Vault = '')
    try { return [regex]::IsMatch($Metin, $Desen, $script:BeyinRxCI, $script:BeyinRxZamanAsimi) }
    catch [System.Text.RegularExpressions.RegexMatchTimeoutException] {
        if ($Vault) { try { Write-BeyinLog -Vault $Vault -Message "regex zaman asimi: $($Desen.Substring(0, [math]::Min(40, $Desen.Length)))" } catch { } }
        return $false
    }
}

# ============================================================================
# MAKINE BAKIMLI "## Ilgili notlar" BOLUMU - TEK KAYNAK
# ----------------------------------------------------------------------------
# bagla.ps1 bu bolumu YAZAR; gom.ps1 gomulen metinden CIKARIR (turetilmis metin
# vektoru kirletmesin), denetle.ps1 ve bahcivan.ps1 "kullanim kaniti" saymamak
# icin CIKARIR, doktor.ps1 SAYAR. Desen bes betikte elle kopyalanmisti ve besi
# de ayni korlugu tasiyordu: 'Ilgili' yalnizca ASCII 'I' ile eslesiyordu.
# IgnoreCase+CultureInvariant, tr-TR kullanicisinin dogal olarak yazacagi
# NOKTALI BUYUK I'yi (U+0130 'Ilgili') ASCII 'I'ye katlamaz - o baslik tum bu
# betiklere GORUNMEZ olurdu: bagla ikinci bir bolum ekler, gom link metnini
# gomer, bahcivan/denetle makine kenarlarini insan kullanimi sayardi. Karakter
# sinifi ucunu birden kabul eder (I, U+0130, U+0131).
# Degistirirsen BES betik birden degisir; kopyalama.
$script:BeyinIlgiliBaslikRx = '^##[ \t]*[Iiİı]lgili notlar[ \t\r]*$'
$script:BeyinIlgiliBolumRx  = $script:BeyinIlgiliBaslikRx + '.*?(?=^#{1,6}[ \t]+\S|\z)'

function Test-BeyinMatch {
    # Kultur-bagimsiz, buyuk/kucuk harf duyarsiz eslesme. -match yerine bunu kullan.
    param([string]$Text, [string]$Pattern, [switch]$Multiline, [switch]$Singleline)
    if ($null -eq $Text) { return $false }
    $opt = if ($Multiline) { $script:BeyinRxCIM } elseif ($Singleline) { $script:BeyinRxCIS } else { $script:BeyinRxCI }
    return [regex]::IsMatch($Text, $Pattern, $opt, $script:BeyinRxZamanAsimi)
}

function Invoke-BeyinReplace {
    # Kultur-bagimsiz, buyuk/kucuk harf duyarsiz degistirme.
    param([string]$Text, [string]$Pattern, [string]$Replacement, [switch]$Multiline, [switch]$Singleline)
    if ($null -eq $Text) { return '' }
    $opt = if ($Multiline) { $script:BeyinRxCIM } elseif ($Singleline) { $script:BeyinRxCIS } else { $script:BeyinRxCI }
    return [regex]::Replace($Text, $Pattern, $Replacement, $opt, $script:BeyinRxZamanAsimi)
}

# ============================================================================
# SIR REDAKSIYONU (savunma katmani)
# ----------------------------------------------------------------------------
# flush/compile prompt'lari modelden "sir yazma" diye RICA eder. Rica yeterli
# degildir: transkriptte prompt injection olabilir, model hata yapabilir, ya da
# sir bir arac ciktisinin icinde gelebilir. Bu yuzden diske yazilan HER metin
# once buradan gecer. Mekanik, modele guvenmeyen son savunma.
#
# Amac sifirlama degil, sizinti yuzeyini daraltmak: bilinen yuksek-riskli
# desenler maskelenir ve maskelenen sayisi cagirana bildirilir.
# ============================================================================

function Protect-BeyinSecrets {
    # -Vault istege bagli: verilirse maskeleme HATALARI engine.log'a yazilir.
    # Geriye uyumlu - eski cagirilar (yalniz -Text) calismaya devam eder, ama
    # o cagirilarda hata sessiz kalir, bu yuzden yeni cagirilar Vault gecmeli.
    param([string]$Text, [string]$Vault = '')

    if ([string]::IsNullOrEmpty($Text)) {
        return @{ Text = ''; Redactions = 0; Failed = 0; FailedPatterns = '' }
    }

    # TUM desenler kultur-bagimsiz calisir (tr-TR 'I' tuzagi icin bkz. yukarisi).
    # Sira onemli: dar/spesifik desenler once, genis atama desenleri sonra.
    $patterns = @(
        # --- saglayici anahtarlari (spesifik) ---
        @{ N = 'anthropic-key'; P = 'sk-ant-[A-Za-z0-9_\-]{8,}' }
        @{ N = 'openai-key';    P = '\bsk-(?!ant-)[A-Za-z0-9_\-]{16,}' }
        # stripe: live_/test_ sonrasi ALT CIZGI de olabilir -> [A-Za-z0-9_]
        @{ N = 'stripe-key';    P = '\b(?:sk|pk|rk)_(?:live|test)_[A-Za-z0-9_]{8,}' }
        @{ N = 'github-token';  P = '\b(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,})' }
        @{ N = 'gitlab-token';  P = '\bglpat-[A-Za-z0-9_\-]{16,}' }
        @{ N = 'hf-token';      P = '\bhf_[A-Za-z0-9]{20,}' }
        @{ N = 'npm-token';     P = '\bnpm_[A-Za-z0-9]{30,}' }
        @{ N = 'sendgrid-key';  P = '\bSG\.[A-Za-z0-9_\-]{16,}\.[A-Za-z0-9_\-]{16,}' }
        @{ N = 'pypi-token';    P = '\bpypi-AgEI[A-Za-z0-9_\-]{20,}' }
        @{ N = 'aws-secret';    P = '(?:aws_?secret[_a-z]*|secret_?access_?key)["'' \t]{0,6}[=:][ \t]*["'']?[A-Za-z0-9/+=]{40}' }
        @{ N = 'google-key';    P = '\bAIza[A-Za-z0-9_\-]{30,}' }
        @{ N = 'slack-token';   P = '\bxox[abeprs]-[A-Za-z0-9\-]{10,}' }
        @{ N = 'aws-key-id';    P = '\b(?:AKIA|ASIA)[0-9A-Z]{16}\b' }
        @{ N = 'jwt';           P = '\beyJ[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]{8,}' }
        @{ N = 'private-key';   P = '-----BEGIN[A-Z ]*PRIVATE KEY-----[\s\S]*?-----END[A-Z ]*PRIVATE KEY-----' }
        @{ N = 'bearer';        P = '\bbearer\s+[A-Za-z0-9._\-+/=]{20,}' }
        # 2026-09-16 (denetim, olculdu: 6 sinif maskelenmiyordu)
        @{ N = 'basic-auth';       P = '\bbasic\s+[A-Za-z0-9+/=]{16,}' }
        @{ N = 'azure-account-key'; P = 'AccountKey=[A-Za-z0-9+/=]{40,}' }
        @{ N = 'google-oauth';     P = '\bya29\.[A-Za-z0-9_\-]{20,}' }
        @{ N = 'slack-app-token';  P = '\bxapp-[A-Za-z0-9\-]{20,}' }
        # 2026-10-05 (avenoxbeyin/hafiza-os desen farki): Discord bot, Vercel, Stripe webhook.
        @{ N = 'discord-bot';   P = '\b[MN][A-Za-z0-9_\-]{23,}\.[A-Za-z0-9_\-]{6}\.[A-Za-z0-9_\-]{27,}' }
        @{ N = 'vercel-token';  P = '\bvck_[A-Za-z0-9]{20,}' }
        @{ N = 'stripe-webhook'; P = '\bwhsec_[A-Za-z0-9]{20,}' }
        # TURKCE ETIKET BAGLAMI (hafiza-os'tan alindi): "sifrem: ...", "parola = ...",
        # "kurtarma kodu: ..." - asagidaki Ingilizce isimli atama desenleri bunlari
        # gormuyordu. Deger en az 6 karakter ve en az bir harf/rakam icermeli.
        @{ N = 'tr-etiket';     P = '(?<![\p{L}\p{Nd}])(?:[sş]ifre(?:m|si|niz|n)?|parola(?:m|s[ıi]|n[ıi]z|n)?|kurtarma kod(?:u|lar[ıi])|gizli anahtar(?:[ıi]m)?|anahtar[ıi]m)["'']?[ \t]*[=:][ \t]*["'']?(?=[^\s"'',;]*[0-9A-Za-z])[^\s"'',;]{6,}' }
        # baglanti dizesindeki kimlik bilgisi: sema://kullanici:PAROLA@host
        # yalniz parolayi maskele, host'u birak (tani icin host degerli)
        @{ N = 'conn-cred';     P = '\b([A-Za-z][A-Za-z0-9+.\-]*://[^\s:/@]+):[^\s@]{3,}@'; R = '$1:[REDAKTE:conn-cred]@' }
        # --- hassas isimli atamalar (genis) ---
        # Buyuk/kucuk harf duyarsiz + kultur-bagimsiz oldugu icin API_KEY, api_key,
        # Api_Key hepsini yakalar. Onceki surum tr-TR yuzunden API_KEY'i KACIRIYORDU.
        # ANKRAJ KALDIRILDI (2026-09-10): '^[ \t]*' yuzunden 'export DB_PASSWORD=',
        # 'set API_KEY=', 'docker run -e POSTGRES_PASSWORD=', '$env:MY_API_KEY ='
        # bicimlerinin HEPSI maskelenmeden geciyordu (7/17 sentetik vaka kacti).
        # Artik isim oncesinde yalniz "kelime karakteri olmayan" bir sinir aranir.
        @{ N = 'env-assign';    P = '(?<![A-Za-z0-9])[A-Za-z0-9_]*(?:SECRET|PASSWORD|PASSWD|PASSPHRASE|(?<=_)PASS(?![A-Za-z])|(?<=_)PWD(?![A-Za-z])|TOKEN|API[_-]?KEY|APIKEY|PRIVATE[_-]?KEY|CREDENTIAL|ACCESS[_-]?KEY)[A-Za-z0-9_]*[ \t]*[=:][ \t]*["'']?(?=[^\s"'',;]*[0-9_\-./+=]|[^\s"'',;]{20,})[^\s"'',;]{8,}' }
        # \b yerine lookbehind: '_' bir kelime karakteri oldugu icin
        # DB_PASSWORD / MY_API_KEY icinde \b YOKTU. Tirnak [=:] ONCESINE de
        # izinli ki JSON bicimi ("password": "...") yakalansin.
        @{ N = 'inline-assign'; P = '(?<![A-Za-z0-9])(?:secret|password|passwd|api[_-]?key|apikey|access[_-]?token|auth[_-]?token|private[_-]?key)["'']?[ \t]*[=:][ \t]*["'']?(?=[^\s"'',;]*[0-9_\-./+=]|[^\s"'',;]{20,})[^\s"'',;]{8,}' }
        # --- kisisel yol (denetim 2026-09-17: MEKANIK SAVUNMA YOKTU) ---
        # Kaynak metninde 'C:\Users\<ad>\...' redaksiyondan AYNEN gecip
        # 86-compiled\sources\*.md icine yaziliyor ve commit ediliyordu. Tek
        # savunma istemdeki "mutlak dosya yolu yazma" satiriydi - yani MODELDEN
        # RICA; sirlar icin acikca reddedilen yaklasimin aynisi.
        #
        # YALNIZ KULLANICI ADI maskelenir, yolun geri kalani BIRAKILIR: tani
        # degeri (hangi klasor, hangi dosya) korunur, kimlik degeri gider.
        #
        # UCUZLUK SARTI (bu fonksiyon kanca yolunda da kosar): iki desen de
        # sabit bir on eke ('Users\' / '/home/' / '/Users/') ankrajlidir, geri
        # izleme yuzeyi yoktur, karakter sinifi tek gecislidir.
        #
        # YANLIS POZITIF SINIRI (OLCULDU): ad parcasi ALFANUMERIK BIR KARAKTERLE
        # BASLAMAK ZORUNDADIR ve yol ayiricilari / dosya adinda yasak
        # karakterleri disLAR. Boylece motorun KENDI yorumlarindaki yer
        # tutucular eslesmez:
        #   'C:\Users\<ad>\...'      -> '<' sinif disi
        #   'C:\Users\...\86-compiled\...' -> '.' ile basliyor (denetle.ps1:94;
        #                               ilk surum bunu SIZINTI sayip 'beyin
        #                               yayinla' kuru kosusunu DURDURDU)
        #   'C:\Users\$env:USERNAME\' -> '$' ile basliyor
        #   'C:\...'                 -> icinde 'Users' yok
        # yayinla.ps1 kendi yol tarayicisinda ayni elemeyi yapiyor; uslup ayni.
        @{ N = 'win-user-path'; P = '(?<![A-Za-z0-9])([A-Za-z]:\\Users\\)([A-Za-z0-9][^\\/:*?"<>|\r\n \t]{0,63})(?=\\)'; R = '$1[REDAKTE:kullanici]' }
        @{ N = 'posix-user-path'; P = '(?<![A-Za-z0-9])(/(?:home|Users)/)([A-Za-z0-9][A-Za-z0-9._\-]{0,63})(?=/)'; R = '$1[REDAKTE:kullanici]' }
    )

    $out = $Text
    $failed = New-Object System.Collections.Generic.List[string]

    foreach ($pat in $patterns) {
        $repl = if ($pat.ContainsKey('R')) { $pat.R } else { "[REDAKTE:$($pat.N)]" }
        $opt  = if ($pat.ContainsKey('M') -and $pat.M) { $script:BeyinRxCIM } else { $script:BeyinRxCI }
        try {
            # ZAMAN ASIMI: asilma -> RegexMatchTimeoutException -> asagidaki
            # fail-closed catch. Zaman asimi olmadan katastrofik geri izleme
            # bu satirda ASILIR ve catch hic atesLENMEZ (bkz. $script:BeyinRxZamanAsimi).
            $out = [regex]::Replace($out, $pat.P, $repl, $opt, $script:BeyinRxZamanAsimi)
        } catch {
            # BU, MOTORUN EN TEHLIKELI SESSIZ YOLUYDU.
            #
            # Eskiden bu catch bostu. Bir desen icin [regex]::Replace firlatirsa
            # (zaman asimi, geri izleme patlamasi, bicimsiz girdi) O SIR SINIFI
            # MASKELENMEDEN gecerdi - ve bu fonksiyonun ciktisi dogrudan
            # 85-daylogs'a yazilip git'e commit ediliyor.
            #
            # Yani tek bir sessiz regex hatasi, vault'un en sert kuralini
            # ("sir benzeri hicbir degeri hicbir nota yazma") sessizce
            # kaldiriyordu. Tek kanit, gunluk logda duran sirrin kendisi olurdu.
            #
            # Fonksiyon artik HANGI desenin dustugunu sayiyor ve donuyor;
            # cagiran fail-closed karar verebilir.
            $failed.Add([string]$pat.N)
            if ($Vault) {
                try {
                    $m = 'bilinmiyor'
                    if ($_ -and $_.Exception) { $m = $_.Exception.Message }
                    Write-BeyinLog -Vault $Vault -Message ("Protect-BeyinSecrets: '$($pat.N)' deseni UYGULANAMADI -> " +
                        "bu sir sinifi MASKELENMEDI | $m")
                } catch { }
            }
        }
    }

    $count = ([regex]::Matches($out, '\[REDAKTE:[a-z\-]+\]', $script:BeyinRxCI, $script:BeyinRxZamanAsimi)).Count
    return @{
        Text          = $out
        Redactions    = $count
        Failed        = $failed.Count
        FailedPatterns = ($failed -join ', ')
    }
}

function Test-BeyinInjection {
    # Transkriptin ozet ciktisini ele gecirmeye calisip calismadigini tespit eder.
    # Engellemez, PUANLAR.
    #
    # ONCEKI SURUMUN SORUNU (olculdu): tek sinyal yetiyordu ve desenler cok
    # genisti ('rol-degistirme' = 'act as', 'zorunlu-cikti' = 'output ... must').
    # Sonuc: prompt/guvenlik/ozetleme konusan HER NORMAL OTURUM 4 sinyal
    # atesliyordu ve gunluk logun basina korkutucu bir UYARI banner'i dusuyordu.
    # Bir sure sonra kullanici uyariyi okumayi birakir - guvenlik katmani kendi
    # kendini etkisiz kilar (alarm yorgunlugu).
    #
    # YENI DAVRANIS:
    #   - Motorun kendi sozlugu (prompt yonergeleri, <<<TRANSKRIPT>>> sinirlari,
    #     [REDAKTE:] isaretleri) taramadan ONCE cikarilir.
    #   - Her sinyal puanli; banner yalniz esik asilinca ve EN AZ 2 FARKLI
    #     sinyal varken dusuyor.
    #   - @{ Score; Signals; Banner } doner.
    # -Vault istege bagli: verilirse desen hatalari engine.log'a yazilir.
    param([string]$Text, [int]$Threshold = 3, [string]$Vault = '')

    # Bozuk alani ERKEN CIKISTA da olmali: iki donus yolunun sozlesmesi ayni.
    $empty = @{ Score = 0; Signals = @(); Banner = $false; Bozuk = 0 }
    if ([string]::IsNullOrEmpty($Text)) { return $empty }

    # 1) Motorun kendi vokabuleri: kendi kendini isaretlemesin
    $t = $Text
    foreach ($own in @(
        '<<<(?:TRANSKRIPT(?: SONU)?|LOGLAR(?: SONU)?|END|FILE:[^>\r\n]{0,80})>>>',
        '\[REDAKTE:[a-z\-]+\]',
        '\| GUVENILMEZ VERI(?:DIR)?:?[^\r\n]{0,80}',
        'UYARI - supheli talimat metni[^\r\n]*',
        'supheli talimat metni iceriyor'
    )) {
        try { $t = [regex]::Replace($t, $own, ' ', $script:BeyinRxCI) } catch { }
    }

    # 2) Puanli sinyaller. Agirlik = ne kadar spesifik.
    $signals = @(
        @{ N = 'yeni-sistem-talimati'; W = 3; P = '(?:yeni|new)\s+(?:sistem|system)\s+(?:talimat|instruction|prompt)' }
        @{ N = 'talimat-gecersiz';     W = 3; P = '(?:onceki|previous|prior|above)[\s\w]{0,24}(?:talimat|instruction|kural|rule)[a-z]*[\s\w]{0,12}(?:gecersiz|invalid|void|yoksay|ignore|disregard)' }
        @{ N = 'ignore-instructions';  W = 3; P = '(?:ignore|disregard|forget)\s+(?:all\s+)?(?:previous|prior|above|earlier)\s+(?:instruction|prompt|rule|direction)' }
        @{ N = 'sinir-taklidi';        W = 2; P = '-{3,}\s*(?:TRANSKRIPT|TRANSCRIPT|PROMPT|SYSTEM)\s+(?:SONU|END)' }
        @{ N = 'arac-cagirma-emri';    W = 2; P = '(?:Read|Write|Bash|Edit|WebFetch)\s+arac[a-z]{0,4}\s+kullan(?:arak)?' }
        @{ N = 'dosya-oku-emri';       W = 2; P = '(?:su|asagidaki|bu)\s+dosyayi\s+oku[a-z]*\s*(?:ve|,)?\s*(?:icerigini|tamamini)' }
        @{ N = 'sir-yazdirma';         W = 3; P = '(?:api[_\- ]?key|anahtar|token|parola)[\s\S]{0,40}(?:degerinin|tamamini|aynen)\s+(?:yaz|ekle|goster)' }
        @{ N = 'zorunlu-cikti';        W = 1; P = '(?:ciktiya|output)[\s\S]{0,50}(?:aynen|verbatim)[\s\S]{0,30}(?:ekle|yaz|include)' }
        # 2026-09-10 denetimi: iki klasik sinif hic aranmyordu.
        # Iki yonlu: TR'de fiil URL'den SONRA gelir ('... adresine gonder'),
        # EN'de once ('send ... to https://').
        @{ N = 'exfil';                W = 3; P = '(?:(?:gonder|ilet|yolla|send|post|upload|exfiltrat)[a-z]{0,8}[\s\S]{0,40}https?://|https?://[^\s]{0,80}[\s\S]{0,40}(?:gonder|ilet|yolla|upload|exfiltrat)[a-z]{0,8})' }
        @{ N = 'rol-degistirme';       W = 3; P = '(?:you are now|from now on you are|sen artik|bundan sonra sen)[\s\S]{0,30}(?:asistan|assistant|model|DAN|developer mode)' }
    )

    $hits = New-Object System.Collections.Generic.List[string]
    $bozuk = New-Object System.Collections.Generic.List[string]
    $score = 0
    foreach ($s in $signals) {
        try {
            # ZAMAN ASIMI (2026-10-05): 'exfil' deseni iki yonlu [\s\S]{0,40} tasiyor;
            # 90K guvenilmez metinde geri izleme patlarsa flush claim+slot tutarak
            # askida kaliyordu (model cagrisi oncesi, 240 sn tavani gecerli degil).
            if (Test-BeyinRxZamanli -Metin $t -Desen $s.P) {
                $hits.Add($s.N)
                $score += [int]$s.W
            }
        } catch {
            # Protect-BeyinSecrets ile ayni sinif, daha hafif sonuc.
            # Bir sinyal deseni dusEmezse o sinyal HIC aranmamis olur: puan
            # dusuk cikar, banner esigi asilmaz ve dedektor KISMEN KOR calisir
            # - ama kimse korlestigini bilmez. Dedektorun sessizce zayiflamasi,
            # hic dedektor olmamasindan daha yanilticidir.
            #
            # Burada FAIL CLOSED yapmiyoruz: bu bir uyari sistemi, engelleyici
            # degil. Tek bir desen hatasi yuzunden ozetlemeyi durdurmak
            # gurultuyu artirir ve zaten "banner'i okunmaz yapma" dersi bu
            # fonksiyonun kendi yorumunda kayitli. Sadece iz birakiyoruz.
            $bozuk.Add([string]$s.N)
        }
    }
    if ($bozuk.Count -gt 0 -and $Vault) {
        try {
            Write-BeyinLog -Vault $Vault -Message ("Test-BeyinInjection: $($bozuk.Count) sinyal deseni UYGULANAMADI " +
                "($($bozuk -join ', ')) -> dedektor bu kosuda kismen kor")
        } catch { }
    }

    # BANNER KURALI (2026-09-10'da duzeltildi).
    #
    # Onceki kural '($score -ge $Threshold) -and ($hits.Count -ge 2)' idi ve
    # ders kitabi enjeksiyonunu KACIRIYORDU: 'Ignore all previous instructions'
    # tek basina W=3 aliyor, esigi tutuyor ama tek sinyal oldugu icin banner
    # dusmuyordu. Alarm yorgunlugu endisesi hakli; cozum esigi degil sinyalin
    # SPESIFIKLIGINI kullanmak: W=3 sinyaller tek baslarina yeterince spesifik.
    $agirHit = $false
    foreach ($s in $signals) { if ($hits -contains $s.N -and [int]$s.W -ge 3) { $agirHit = $true; break } }
    $banner = ($score -ge $Threshold) -and (($hits.Count -ge 2) -or $agirHit)
    return @{ Score = $score; Signals = @($hits); Banner = $banner; Bozuk = $bozuk.Count }
}

# ============================================================================
# TRANSKRIPT OKUMA  (cok-ajanli)
# ----------------------------------------------------------------------------
# Vault TEK BEYIN: hem Claude Code hem Codex ayni 85-daylogs'a yaziyor. Iki
# ajanin transkript bicimi farkli, o yuzden okuma tek yerde toplandi ve bicim
# otomatik tespit ediliyor.
#
#   claude : ~/.claude/projects/**/<uuid>.jsonl
#            satir = { type, message: { role, content } }
#   codex  : ~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl
#            (bicim Read-BeyinTranscript icinde tespit edilir)
#
# Doner: @{ Turns; UserText; Format }
#   Turns    = "USER: ..." / "ASSISTANT: ..." satirlari
#   UserText = yalniz kullanici turlari (injection taramasi icin)
# ============================================================================

function Get-BeyinFormatFromLines {
    # Bicimi ZATEN OKUNMUS bir satir dizisinden tespit eder.
    #
    # ONCEKI HATA: tespit dosyanin ilk 8 SATIRINA bakiyordu. Guncel Claude Code
    # transkriptleri 8+ meta satirla basliyor:
    #   mode / permission-mode / system / system / file-history-snapshot / ...
    # ilk gercek mesaj 9. satirda veya daha sonra. Sonuc: transkript
    # "bilinmiyor" sayilip HIC ozetlenmiyordu (695 dosyanin %3,6'si; engine.log
    # 9 kez "bicim taninmadi", hep ayni dosyalar).
    #
    # Sabiti 8'den 40'a cikarmak cozum DEGIL - bicim yine degisir. Dogrusu:
    # ilk TANINABILIR kayda kadar tara, kesin bir ust sinirla dur.
    param([string[]]$Lines, [int]$MaxScan = 400)

    $n = [Math]::Min($MaxScan, @($Lines).Count)
    for ($i = 0; $i -lt $n; $i++) {
        $line = $Lines[$i]
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $o = $null
        try { $o = $line | ConvertFrom-Json } catch { continue }
        if (-not $o) { continue }

        # Codex rollout: ust seviyede 'payload' veya bilinen 'type' degerleri
        if ($o.PSObject.Properties['payload'] -or
            ($o.PSObject.Properties['type'] -and
             ([string]$o.type) -match '^(response_item|event_msg|session_meta|turn_context|compacted|world_state)$')) {
            return 'codex'
        }
        # Claude Code: 'message' nesnesi icinde role
        if ($o.PSObject.Properties['message'] -and $o.message -and
            $o.message.PSObject.Properties['role']) {
            return 'claude'
        }
    }
    return 'bilinmiyor'
}

function Get-BeyinTranscriptFormat {
    # Tek basina kullanim icin (dosyadan okur). Read-BeyinTranscript bunu
    # KULLANMAZ - o zaten tum dosyayi okuyor, ikinci disk okumasi gereksiz.
    param([string]$Path, [int]$MaxScan = 400)
    try {
        return Get-BeyinFormatFromLines -Lines @(Get-Content -LiteralPath $Path -TotalCount $MaxScan -Encoding UTF8 -ErrorAction SilentlyContinue) -MaxScan $MaxScan
    } catch { }
    return 'bilinmiyor'
}

function ConvertTo-BeyinTurnText {
    # Bir icerik alanini (string ya da blok dizisi) duz metne cevirir.
    # Arac GIRDILERI alinmaz - sir en cok orada olur; yalniz aracin adi kalir.
    param($Content)
    if ($null -eq $Content) { return '' }
    if ($Content -is [string]) { return $Content }
    $text = ''
    foreach ($blk in @($Content)) {
        if (-not $blk) { continue }
        if ($blk -is [string]) { $text += $blk + "`n"; continue }
        $bt = ''
        if ($blk.PSObject.Properties['type']) { $bt = [string]$blk.type }
        switch -Regex ($bt) {
            '^(text|input_text|output_text)$' {
                if ($blk.PSObject.Properties['text']) { $text += [string]$blk.text + "`n" }
            }
            '^(tool_use|function_call|local_shell_call|custom_tool_call)$' {
                $n = 'arac'
                foreach ($k in @('name','tool_name')) {
                    if ($blk.PSObject.Properties[$k] -and $blk.$k) { $n = [string]$blk.$k; break }
                }
                $text += "[arac: $n]`n"
            }
        }
    }
    return $text
}

function Convert-BeyinLinesToTurns {
    # Once BIRINCIL kaynak (Codex: response_item). Codex'te hic tur cikmazsa
    # YEDEK kaynak (event_msg/item_completed) denenir. Iki kaynak ASLA
    # birlestirilmez: ayni tur iki zarfta da bulunur, birlestirmek cift sayar.
    # Bilinen sinir: karar PENCERE basina verilir. Bir pencere yalniz
    # developer/arac response_item'lari + onceki pencerenin son turunun
    # item_completed kaydini iceriyorsa o tur iki kez ozetlenebilir. Yerel
    # rollout'larda (0.153.4) item_completed-only dosya yok; kabul edildi.
    param(
        [string[]]$Lines,
        [string]$Format,
        [int]$FromIndex = 0,
        [int]$MaxTurnChars = 1500,
        [int]$MaxChars = 0
    )
    $r = Convert-BeyinLinesToTurnsCore -Lines $Lines -Format $Format -FromIndex $FromIndex `
                                       -MaxTurnChars $MaxTurnChars -MaxChars $MaxChars -CodexSource 'response_item'
    if ($Format -eq 'codex' -and @($r.Turns).Count -eq 0) {
        $r2 = Convert-BeyinLinesToTurnsCore -Lines $Lines -Format $Format -FromIndex $FromIndex `
                                            -MaxTurnChars $MaxTurnChars -MaxChars $MaxChars -CodexSource 'item_completed'
        if (@($r2.Turns).Count -gt 0) { $r = $r2 }
    }
    return $r
}

function Convert-BeyinLinesToTurnsCore {
    # JSONL satir dizisini turlara cevirir. AYRISTIRMA KURALI TEK YERDE:
    # Read-BeyinTranscript (tam okuma, tavan alti) ve Read-BeyinTranscriptTail
    # (bayt penceresi, tavan ustu) ikisi de bunu cagirir. Kural iki yerde
    # kopyalansaydi biri sessizce eskirdi (Codex zarf bicimi degistiginde tek
    # yer duzeltilip digeri unutulurdu).
    #
    # Donus: @{ Turns; UserText; ConsumedIndex; Partial }
    #   ConsumedIndex = GERCEKTEN islenmis son satirin bir sonrasi (HARIC).
    #   Partial       = MaxChars doldu, dizide islenmemis satir kaldi.
    param(
        [string[]]$Lines,
        [string]$Format,
        [int]$FromIndex = 0,
        [int]$MaxTurnChars = 1500,
        [int]$MaxChars = 0,
        [string]$CodexSource = 'response_item'   # 'response_item' | 'item_completed'
    )
    $n = @($Lines).Count
    $consumed = $n
    $partial = $false

    $turns = New-Object System.Collections.Generic.List[string]
    $userSb = New-Object System.Text.StringBuilder
    $toplamKarakter = 0

    for ($idx = $FromIndex; $idx -lt $Lines.Count; $idx++) {
        $line = $Lines[$idx]
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $o = $null
        try { $o = $line | ConvertFrom-Json } catch { continue }
        if (-not $o) { continue }

        $role = ''
        $content = $null

        if ($Format -eq 'claude') {
            # isMeta=true: harness'in enjekte ettigi metin (Stop hook geri
            # bildirimi, goal check-in, sistem uyarilari). Codex dalindaki
            # role='developer' elemesiyle AYNI sinif: ozetlenecek veri degil.
            # Olcum (2026-09-10, 25 transkript): 1077 turun 11'i isMeta ama
            # 389.820 karakterin 19.421'i (%5).
            if ($o.PSObject.Properties['isMeta'] -and $o.isMeta) { continue }
            if (-not $o.PSObject.Properties['message'] -or -not $o.message) { continue }
            if ($o.message.PSObject.Properties['role']) { $role = [string]$o.message.role }
            if ($o.message.PSObject.Properties['content']) { $content = $o.message.content }
        }
        elseif ($Format -eq 'codex') {
            # Codex rollout'ta ayni tur UC KEZ gecebilir:
            #   response_item/message    -> modelin gercekten gordugu kayit  (BIRINCIL)
            #   event_msg/user_message   -> UI olayi, ayni metnin kopyasi     (ATLANIR)
            #   event_msg/item_completed -> ucuncu projeksiyon                (YEDEK)
            # Tek kaynak alinir, yoksa her tur cift sayilirdi. YEDEK yalniz
            # birincil HIC tur vermezse kullanilir (bkz. Convert-BeyinLinesToTurns).
            # Yukari akis bir motorda olculdu (2026-08-29): yeni Codex istemcileri
            # (paginated gecmis kipi) turlari YALNIZ item_completed zarfinda
            # yaziyor; o dosyalar burada 0 tur verip sessizce atlanirdi.
            # Yerel olcum (Codex 0.153.4, 400 rollout): 245 her ikisi, 154 yalniz
            # response_item, 0 yalniz item_completed - bugun degil, yarin icin.
            if (-not $o.PSObject.Properties['type']) { continue }
            if (-not $o.PSObject.Properties['payload'] -or -not $o.payload) { continue }
            $node = $o.payload
            if ($CodexSource -eq 'item_completed') {
                if (([string]$o.type) -ne 'event_msg') { continue }
                if (-not $node.PSObject.Properties['type'] -or ([string]$node.type) -ne 'item_completed') { continue }
                if (-not $node.PSObject.Properties['item'] -or -not $node.item) { continue }
                $it = $node.item
                $itType = ''
                if ($it.PSObject.Properties['type']) { $itType = [string]$it.type }
                # Reasoning / CommandExecution / FileChange bilerek atlanir.
                if ($itType -eq 'UserMessage') { $role = 'user' }
                elseif ($itType -eq 'AgentMessage') { $role = 'assistant' }
                else { continue }
                # Icerik blok tipi: UserMessage 'text', AgentMessage 'Text' (Codex
                # kaynaginda AgentMessageContent rename_all tasimiyor).
                # ConvertTo-BeyinTurnText'in switch -Regex'i harf duyarsiz.
                if ($it.PSObject.Properties['content']) { $content = $it.content }
            } else {
                if (([string]$o.type) -ne 'response_item') { continue }
                if (-not $node.PSObject.Properties['type'] -or ([string]$node.type) -ne 'message') { continue }
                if ($node.PSObject.Properties['role']) { $role = [string]$node.role }
                # role:"developer" = kancalarin enjekte ettigi baglam ve izin bloklari.
                # Alinirsa motor kendi enjeksiyonunu geri okuyup BESLEME DONGUSU yapar.
                if ($role -eq 'developer') { continue }
                if ($node.PSObject.Properties['content']) { $content = $node.content }
                # role='user' AMA SENTETIK: Codex, AGENTS.md talimat blogunu ve
                # birkac sistem blogunu KULLANICI turu olarak yaziyor. Olcum
                # (2026-09-10): bir Codex rollout'unda role=user iki mesajdi ve
                # ikisi de sentetikti (17.947 karakterlik AGENTS.md + 6.244
                # karakterlik codex_internal_context); UserText'in %100'u sahte.
                # Ozetleyici "ne konusuldu" diye calisma anlasmasini ozetliyordu.
                if ($role -eq 'user' -and $content) {
                    $bas = (ConvertTo-BeyinTurnText -Content $content)
                    if ($bas) {
                        $bas = $bas.TrimStart()
                        if ($bas.Length -gt 240) { $bas = $bas.Substring(0, 240) }
                        if (Test-BeyinMatch -Text $bas -Pattern '^(?:#\s*AGENTS\.md|<(?:INSTRUCTIONS|environment_context|codex_internal_context|recommended_plugins|in-app-browser-context|user_instructions|persistent_context)\b)') {
                            continue
                        }
                    }
                }
            }
        }
        else { continue }

        if ($role -ne 'user' -and $role -ne 'assistant') { continue }

        $text = (ConvertTo-BeyinTurnText -Content $content).Trim()
        if (-not $text) { continue }
        if ($text.Length -gt $MaxTurnChars) { $text = $text.Substring(0, $MaxTurnChars) + ' ...' }
        $satir = "{0}: {1}" -f $role.ToUpperInvariant(), $text

        # KARAKTER BUTCESI. En az bir tur her zaman alinir; aksi halde tek
        # basina butceyi asan bir tur sonsuz donguye sokardi (watermark
        # ilerlemez, is tekrar kuyruga girer, ayni yerde takilir).
        if ($MaxChars -gt 0 -and $turns.Count -gt 0 -and
            ($toplamKarakter + $satir.Length + 2) -gt $MaxChars) {
            $consumed = $idx                   # BU satir islenmedi
            $partial = $true
            break
        }

        if ($role -eq 'user') { [void]$userSb.AppendLine($text) }
        $turns.Add($satir)
        $toplamKarakter += $satir.Length + 2
    }

    return @{ Turns = @($turns); UserText = $userSb.ToString(); ConsumedIndex = $consumed; Partial = $partial }
}

function Read-BeyinTranscript {
    # PARCALAMA (Asama 6): kirpma yerine parca parca isleme.
    #
    # ESKI DAVRANIS - sessiz veri kaybi:
    #   flush tum turlari birlestirip son 90.000 karakteri aliyordu
    #   (Substring(Length - 90000)), yani KUYRUGU tutup BASI atiyordu; sonra
    #   watermark'i DOSYANIN TAMAMINA ilerletiyordu. Atilan bas kismi bir daha
    #   hicbir sey tarafindan islenmiyordu. Uzun oturumlarda ilk saatler
    #   kalici olarak kayboluyordu.
    #
    # YENI DAVRANIS:
    #   -MaxChars verilirse turlar BASTAN itibaren toplanir, sinir dolunca
    #   durulur ve ConsumedToLine dondurulur: GERCEKTEN islenmis son satirin
    #   bir sonrasi. flush watermark'i buraya ilerletir, kalan icin kendini
    #   kuyruga atar. Yon degisti: kuyruk yerine BASTAN - kronolojik sira
    #   korunuyor.
    #
    # ConsumedToLine ILERI kayarsa veri kaybi (onarilamaz), GERI kayarsa
    # tekrar ozetleme (yalniz israf). Bu yuzden durulan satirin indeksi
    # HARIC olarak yazilir: o satir bu turda islenmedi.
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [int]$FromLine = 0,
        [int]$MaxTurnChars = 1500,
        [int]$MaxChars = 0          # 0 = sinirsiz (eski davranis)
    )

    $result = @{ Turns = @(); UserText = ''; Format = 'bilinmiyor'
                 TotalLines = 0; ConsumedToLine = $FromLine; Partial = $false }
    if (-not (Test-Path -LiteralPath $Path)) { return $result }

    $all = @(Get-Content -LiteralPath $Path -Encoding UTF8 -ErrorAction SilentlyContinue)
    # YARIM SON SATIR (2026-09-16, denetim): PreCompact dosya yazilirken ateslenir;
    # '\n' ile bitmeyen son satir Get-Content'te bir satirdir ama JSON'u yarimdir.
    # Tuketilmis sayilirsa yazar tamamlayinca o tur (cogu zaman kapanis cevabi)
    # bir daha okunmaz. Son bayt 0x0A degilse o satir bu turda yok sayilir.
    try {
        $sonBayt = -1
        $fsSon = [System.IO.File]::Open($Path, 'Open', 'Read', 'ReadWrite')
        try { if ($fsSon.Length -gt 0) { [void]$fsSon.Seek(-1, 'End'); $sonBayt = $fsSon.ReadByte() } } finally { $fsSon.Dispose() }
        # TEK SATIR (2026-10-05): Count=1 iken 0..-1 = @(0,-1) ayni satiri IKI kez
        # veriyordu; yarim satir 'islenmis' damgalaniyordu.
        if ($sonBayt -ne 10 -and $all.Count -gt 0) { if ($all.Count -le 1) { $all = @() } else { $all = @($all[0..($all.Count - 2)]) } }
    } catch { }
    $result.TotalLines = $all.Count
    $result.ConsumedToLine = $all.Count
    if ($all.Count -le $FromLine) { $result.ConsumedToLine = $all.Count; return $result }

    # Bicimi ZATEN OKUNMUS diziden tespit et - ikinci disk okumasi gereksiz.
    # Tespit her zaman dosyanin BASINDAN yapilir ($FromLine'dan degil): meta
    # satirlari ve session_meta bastadir, watermark ilerledikce kaybolurlar.
    $fmt = Get-BeyinFormatFromLines -Lines $all
    $result.Format = $fmt

    $c = Convert-BeyinLinesToTurns -Lines $all -Format $fmt -FromIndex $FromLine -MaxTurnChars $MaxTurnChars -MaxChars $MaxChars
    $result.Turns = @($c.Turns)
    $result.UserText = $c.UserText
    $result.ConsumedToLine = [int]$c.ConsumedIndex
    $result.Partial = [bool]$c.Partial
    return $result
}

function Get-BeyinByteOffsetOfLine {
    # SATIR isaretini BAYT isaretine cevirir: N satir islenmisse N+1'inci
    # satirin basladigi bayt (yani N'inci '\n'in bir sonrasi). Dosya bastan
    # 1 MB'lik parcalarla AKARAK okunur, belege alinmaz; 100 MB'de ~1-2 sn.
    #
    # NEDEN (kod incelemesi 2026-09-10): satir yoluyla ozetlenmis bir dosya
    # 100 MB tavanini asinca bayt yolu isaret 0 goruyor, "son pencere" kipine
    # dusuyor ve (a) son 8 MB'in zaten ozetlenmis kismini IKINCI KEZ
    # ozetliyor, (b) satir isaretiyle son pencere arasini atlayip bunu
    # "onceki icerik atlandi" diye yanlis raporluyordu. Simdi gecis noktasi
    # hesaplanip oradan devam ediliyor.
    #
    # Get-Content ile tutarlilik: Get-Content '\n' ile boler (CRLF'yi de),
    # sondaki newline'siz son parca da bir satirdir. N '\n' bulunamazsa
    # dosya sonu doner (tum satirlar tuketilmis).
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][int]$Lines)
    if ($Lines -le 0) { return [long]0 }
    $len = [long](Get-Item -LiteralPath $Path).Length
    $buf = New-Object byte[] 1048576
    $sayac = 0
    $offset = [long]0
    try {
        $fs = [System.IO.File]::Open($Path, 'Open', 'Read', 'ReadWrite')
        try {
            while ($true) {
                $okunan = $fs.Read($buf, 0, $buf.Length)
                if ($okunan -le 0) { break }
                $pos = 0
                while ($pos -lt $okunan) {
                    $nl = [Array]::IndexOf($buf, [byte]10, $pos, $okunan - $pos)
                    if ($nl -lt 0) { break }
                    $sayac++
                    if ($sayac -ge $Lines) { return [long]($offset + $nl + 1) }
                    $pos = $nl + 1
                }
                $offset += $okunan
            }
        } finally { $fs.Close(); $fs.Dispose() }
    } catch {
        # HATA YOLU: -1 DONER, DOSYA SONU DEGIL (2026-09-10, bagimsiz denetim).
        #
        # Eskiden burasi $len (dosya sonu) donuyordu. Bir I/O istisnasi
        # (dosya kilitli, aginda kesinti, izin) gecici bir olaydir; ama
        # cagiran taraf donen degeri ISARET olarak yaziyordu. Yani tek bir
        # gecici hata, isareti dosyanin SONUNA atliyor ve aradaki tum
        # islenmemis icerigi KALICI olarak gomuyordu.
        #
        # -1 "bilmiyorum" demektir. Cagiranlar bunu gorunce isareti
        # ILERLETMEZ, onceki degeri korur. Kotu durumda ayni icerik bir kez
        # daha ozetlenir (yinelenen blok, geri alinabilir); iyi durumda hicbir
        # sey kaybolmaz. Fonksiyonun SONUNDAKI 'return $len' ise mesru:
        # orada dongu tukenmistir, yani dosyada $Lines kadar '\n' yoktur -
        # tum satirlar gercekten tuketilmistir.
        return [long](-1)
    }
    return $len
}

function Read-BeyinTranscriptTail {
    # TAVAN USTU (BUYUK) TRANSKRIPT OKUYUCU - bayt penceresi.
    #
    # NEDEN VAR: Read-BeyinTranscript dosyanin TAMAMINI Get-Content ile belege
    # alir; 100 MB tavani bu yuzden var. Ama tavani asan dosya "atlandi" deyip
    # bir daha HIC ozetlenmiyordu. Olculdu (2026-09-10): 20-21 Agustos'tan beri
    # acik iki Codex oturumu (1032 MB ve 1545 MB) engine.log'da 305 kez
    # "transkript cok buyuk, atlandi" ile gecti; o oturumlarin tek satiri bile
    # beyne girmedi. Doktor bu arada yesildi. Sessiz kayip.
    #
    # YONTEM - dosya BASTAN degil, ISARETTEN okunur:
    #   - byteOffset isareti varsa oradan EOF'a dogru en fazla MaxBytes okunur.
    #     Fazlasi Partial=$true ile bir sonraki parcaya kalir (flush kendini
    #     kuyruga atar). Read-BeyinTranscript'in satir parcalamasiyla ayni
    #     sozlesme, birimi bayt.
    #   - Isaret yoksa (dosya ilk kez goruluyor) ya da isaretten sonrasi
    #     MaxSkipBytes'i (64 MB) asiyorsa: dosyanin SON MaxBytes'i alinir, ara ATLANIR
    #     ve SkippedBytes ile bildirilir. 1 GB'lik gecmisi 8 MB'lik 128 parcada
    #     ozetlemek gunluk butceyi (50) iki gun kilitlerdi; yakin gecmis
    #     kazanilir, uzak gecmis bilincli ve GORUNUR bicimde feda edilir.
    #   - Pencerenin ilk satiri bayt ortasindan basliyorsa atilir; sonda '\n'
    #     ile bitmeyen (hala yazilan) satir atilir. ConsumedToByte her zaman
    #     tam bir satirin SONUNU gosterir; bir sonraki okuma oradan baslar.
    #   - Bolme BAYT duzeyinde '\n' (0x0A) ile yapilir: UTF-8'de 0x0A hicbir
    #     cok baytli karakterin icinde gecmez, guvenli.
    #
    # Donus: @{ Turns; UserText; Format; StartByte; ConsumedToByte; FileBytes;
    #           Partial; SkippedBytes; TailMode }
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [long]$FromByte = 0,
        [int]$MaxBytes = 8388608,          # 8 MB pencere
        [long]$MaxSkipBytes = 67108864,    # 64 MB'dan buyuk birikim -> sona atla (8 parca = 8 cagri; ~50 MB/gun buyuyen rollout bir gunu kacirmasin)
        [int]$MaxTurnChars = 1500,
        [int]$MaxChars = 0
    )
    $r = @{ Turns = @(); UserText = ''; Format = 'bilinmiyor'; StartByte = [long]$FromByte
            ConsumedToByte = [long]$FromByte; FileBytes = [long]0; Partial = $false
            SkippedBytes = [long]0; TailMode = $false }
    if (-not (Test-Path -LiteralPath $Path)) { return $r }

    $len = [long](Get-Item -LiteralPath $Path).Length
    $r.FileBytes = $len
    if ($FromByte -lt 0 -or $FromByte -gt $len) { $FromByte = 0 }

    $start = [long]$FromByte
    if ($FromByte -le 0 -or ($len - $FromByte) -gt $MaxSkipBytes) {
        $start = [Math]::Max([long]0, $len - [long]$MaxBytes)
        if ($start -gt $FromByte) { $r.SkippedBytes = $start - $FromByte; $r.TailMode = $true }
    }
    $r.StartByte = $start
    $r.ConsumedToByte = $start
    if ($start -ge $len) { return $r }

    # Pencerenin bir bayt oncesini de oku: 0x0A degilse ilk satir yarimdir.
    $lead = 0
    $seekAt = $start
    if ($start -gt 0) { $seekAt = $start - 1; $lead = 1 }
    $take = [int][Math]::Min([long]$MaxBytes + $lead, $len - $seekAt)
    $buf = New-Object byte[] $take
    $okunan = 0
    try {
        $fs = [System.IO.File]::Open($Path, 'Open', 'Read', 'ReadWrite')
        try {
            [void]$fs.Seek($seekAt, [System.IO.SeekOrigin]::Begin)
            $okunan = $fs.Read($buf, 0, $take)
        } finally { $fs.Close(); $fs.Dispose() }
    } catch { return $r }
    if ($okunan -le $lead) { return $r }

    # Bicim dosyanin BASINDAN tespit edilir (session_meta / meta satirlari
    # oradadir); yalnizca ilk 400 satir okunur, boyuttan bagimsiz ucuz.
    $r.Format = Get-BeyinTranscriptFormat -Path $Path

    $dropFirst = ($lead -eq 1 -and $buf[0] -ne 10)
    $lines = New-Object System.Collections.Generic.List[string]
    $ends  = New-Object System.Collections.Generic.List[long]
    $pos = $lead
    $ilk = $true
    while ($pos -lt $okunan) {
        $nl = [Array]::IndexOf($buf, [byte]10, $pos)
        if ($nl -lt 0 -or $nl -ge $okunan) { break }      # kalan: yarim satir
        $txt = [System.Text.Encoding]::UTF8.GetString($buf, $pos, $nl - $pos).TrimEnd([char]13)
        $pos = $nl + 1
        $satirSonu = [long]($seekAt + $pos)
        if ($ilk) {
            $ilk = $false
            if ($dropFirst) { $r.ConsumedToByte = $satirSonu; continue }
        }
        $lines.Add($txt)
        $ends.Add($satirSonu)
    }

    $pencereDolu = (($seekAt + $okunan) -lt $len)
    if ($lines.Count -eq 0) {
        # Pencerede TEK BIR tam satir bile yok (dev tek satir: base64 gomulu
        # icerik). Pencere doluysa isareti pencere sonuna ILERLET ve Partial
        # ver; aksi halde ayni pencere sonsuza dek yeniden okunur.
        if ($pencereDolu) { $r.ConsumedToByte = [long]($seekAt + $okunan); $r.Partial = $true }
        return $r
    }

    $c = Convert-BeyinLinesToTurns -Lines $lines.ToArray() -Format $r.Format -FromIndex 0 `
                                   -MaxTurnChars $MaxTurnChars -MaxChars $MaxChars
    $r.Turns = @($c.Turns)
    $r.UserText = $c.UserText
    $ci = [int]$c.ConsumedIndex
    if ($ci -ge $lines.Count)  { $r.ConsumedToByte = $ends[$lines.Count - 1] }
    elseif ($ci -le 0)         { $r.ConsumedToByte = $start }
    else                       { $r.ConsumedToByte = $ends[$ci - 1] }

    if ($c.Partial)          { $r.Partial = $true }
    elseif ($pencereDolu)    { $r.Partial = $true }   # pencere EOF'a ulasmadi: devami var
    return $r
}

# ============================================================================
# PROJE TURETICI + HARIC TUTMA  (tek yerde, dagitilmasin)
# ----------------------------------------------------------------------------
# Iki isi birden cozer:
#
# 1. PROJE ADI: yetim taramada blok "proje" etiketi tasimiyordu; gunluk logun
#    %42'si hangi projeye ait oldugunu bilmiyordu. Iki bicim de transkriptin
#    ICINDE cwd tasiyor:
#      claude : ilk ~30 satirda type=system kaydinda `cwd`
#      codex  : ilk satir session_meta -> payload.cwd
#    Klasor adindan cozmek (C--Users-<ad>-Desktop-codex-chef) BELIRSIZ:
#    tireli proje adlarinda yaprak ayirt edilemez. O yuzden yalnizca son care.
#
# 2. HARIC TUTMA: tarama havuzunun buyuk kismi ozetlenmemeli.
#      agent-*.jsonl      -> havuzun %49'u; alt-ajan, ana oturumun parcasi
#      beyin-engine-cwd   -> MOTORUN KENDI ozetleyici oturumlari.
#                            Ozetlenirse motor kendi ozetini ozetler: her ozet
#                            yeni transkript, o da yeni ozet. BESLEME DONGUSU.
#      Temp/scratchpad    -> test oturumlari, cop ozet uretir
#      vault klasoru      -> beyin uzerinde calisilan oturumlar (kullanici karari)
#
# Her haric tutma SEBEBIYLE loglanir: sessiz filtre, sessiz kayiptir.
# ============================================================================

# ============================================================================
# PROJE KIMLIGI  (2026-09-10, bagimsiz denetim)
# ----------------------------------------------------------------------------
# Proje etiketi klasor yapragindan turetiliyordu ve baska hicbir katman yoktu.
# Olculdu: 591 gunluk log blogunun 105'i (%18) anlamsiz etiketliydi -
# 'Desktop' 65 blok, 'kok-C' 33, ajanin urettigi uzun klasor adlari 7.
#
# Bu yalniz kozmetik degil: enjeksiyon "bu projedeki son oturumlar" derken
# etiketle esleme yapiyor. 'Desktop' diye bir proje olmadigi icin o 65 blok
# hicbir zaman dogru oturumda geri gelmiyordu.
# ============================================================================

# Proje OLMAYAN yapraklar. Bunlar bir calisma dizini olabilir ama bir proje
# kimligi degildir; 'genel' kovasina dusurulurler.
$script:BeyinJenerikYaprak = @(
    'desktop', 'documents', 'downloads', 'belgeler', 'masaustu',
    'src', 'source', 'sources', 'repo', 'repos', 'projects', 'proje', 'projeler',
    'work', 'workspace', 'tmp', 'temp', 'new', 'test', 'tests', 'bin', 'dist',
    'build', 'out', 'node_modules', 'home', 'users', 'user', 'appdata', 'local'
)

function Get-BeyinProjectAliases {
    # 80-memory/proje-adlari.md icindeki 'klasor = Kanonik Ad' haritasi.
    #
    # KURATORLU dosya: motor buraya YAZMAZ, yalniz okur. Kullanici bir klasorun
    # hangi projeye ait oldugunu biliyorsa burada soyler; motor tahmin etmez.
    # Dosya yoksa bos harita doner ve her sey eskisi gibi calisir.
    param([hashtable]$Paths)
    if ($null -ne $script:BeyinAliasCache) { return $script:BeyinAliasCache }
    $map = @{}
    try {
        $f = Join-Path $Paths.Memory 'proje-adlari.md'
        if (Test-Path -LiteralPath $f) {
            # KOD BLOKLARI ATLANIR. Dosya bir BELGEDIR ve icinde 'nasil yazilir'
            # ornekleri var. Ilk surumde ayristirici o ornekleri GERCEK
            # yapilandirma sandi: belgedeki 'ornek-source = ornek' satiri
            # canli bir takma ad haline geldi ve test bunu yakaladi.
            # Belgenin kendisi yapilandirmayi degistirememeli.
            $kodBloku = $false
            foreach ($ln in @(Get-Content -LiteralPath $f -Encoding UTF8 -ErrorAction SilentlyContinue)) {
                $t = $ln.Trim()
                if ($t.StartsWith('```')) { $kodBloku = -not $kodBloku; continue }
                if ($kodBloku) { continue }
                if (-not $t -or $t.StartsWith('#') -or $t.StartsWith('>') -or $t.StartsWith('|')) { continue }
                $m = [regex]::Match($t, '^\s*(?<k>[^=]+?)\s*=\s*(?<v>.+?)\s*$')
                if (-not $m.Success) { continue }
                $k = $m.Groups['k'].Value.Trim().ToLowerInvariant()
                $v = $m.Groups['v'].Value.Trim()
                if ($k -and $v) { $map[$k] = $v }
            }
        }
    } catch { }
    $script:BeyinAliasCache = $map
    return $map
}

function Resolve-BeyinProjectName {
    # Ham yapragi kanonik proje adina cevirir.
    # Sira: kullanici takma adi > jenerik elemesi > uzun ad kisaltma.
    param([string]$Leaf, [hashtable]$Paths)
    if ([string]::IsNullOrWhiteSpace($Leaf)) { return '' }
    $ad = $Leaf.Trim()

    # 1) Kullanici takma adi - her seyi gecer
    if ($Paths) {
        $map = Get-BeyinProjectAliases -Paths $Paths
        $k = $ad.ToLowerInvariant()
        if ($map.ContainsKey($k)) { return $map[$k] }
    }

    # 2) Jenerik yaprak / surucu koku -> proje degil
    if ($script:BeyinJenerikYaprak -contains $ad.ToLowerInvariant()) { return 'genel' }
    if ($ad -match '^kok-[A-Za-z]$') { return 'genel' }

    # 3) Ajanin urettigi uzun klasor adi bir proje adi degil, bir istegin
    #    ozetidir ('ornek-io-panelini-incele-ve-benim'). Ilk uc parcaya
    #    kisaltilir; boylece hem okunur kalir hem ayni istekten dogan
    #    klasorler ayni etikette toplanir.
    if ($ad.Length -gt 28) {
        $parca = @($ad -split '[-_ ]+' | Where-Object { $_ })
        if ($parca.Count -gt 3) {
            $ad = ($parca | Select-Object -First 3) -join '-'
        } elseif ($ad.Length -gt 32) {
            $ad = $ad.Substring(0, 32)
        }
    }
    return $ad
}

function Get-BeyinProjectLeaf {
    # Proje yolundan gunluk log basliginda kullanilacak kisa adi turetir.
    # TEK KAYNAK: hem tarayici (Get-BeyinProjectFromTranscript) hem flush.ps1
    # bunu cagirir; onceden flush ham Split-Path kullaniyordu.
    #
    # -Paths ISTEGE BAGLI: verilirse kullanici takma adlari (80-memory/
    # proje-adlari.md) uygulanir. Verilmezse yalniz jenerik elemesi ve uzun ad
    # kisaltmasi calisir - yani eski cagirilar bozulmadan calismaya devam eder.
    param([string]$Path, [hashtable]$Paths)
    if ([string]::IsNullOrWhiteSpace($Path)) { return '' }
    # SURUCU KOKU - Split-Path'e HIC verme.
    #   'C:\' -> Split-Path -Leaf onu oldugu gibi dondurur (baslikta cirkin)
    #   'C:'   -> Split-Path onu GECERLI DIZINE gore cozer ve alakasiz bir
    #            klasor adi dondurur (olculdu: '.claude'). Gunluk loga yanlis
    #            proje etiketi yazdiran sessiz hata budur.
    if ($Path -match '^[A-Za-z]:[\\/]?$') {
        # Surucu koku bir proje DEGILDIR. Eskiden 'kok-C' diye bir etiket
        # uretiliyordu ve son-durum tablosunda sahte bir proje satiri aciyordu
        # (olculdu: 33 blok). Artik 'genel' kovasina dusuyor.
        return 'genel'
    }
    # KULLANICI EV DIZINI de proje degildir (2026-09-16): aksi halde Windows hesap
    # adi proje etiketi olarak gunluk loga ve son-durum tablosuna yaziliyordu.
    try {
        $norm0 = ($Path -replace '/', '\').TrimEnd('\')
        foreach ($ev in @($env:USERPROFILE, $HOME)) {
            if ($ev -and [string]::Equals($norm0, (([string]$ev) -replace '/', '\').TrimEnd('\'), [StringComparison]::OrdinalIgnoreCase)) { return 'genel' }
        }
    } catch { }
    # WORKTREE NORMALIZASYONU (2026-09-10): Claude Code worktree oturumlarinda
    # cwd '<proje>\.claude\worktrees\<task-id>' oluyor ve yaprak 'task-MTN98...'
    # cikiyordu. Gunluk logda boyle bir proje etiketi yok; enjeksiyon o projenin
    # gecmisini bulamiyor, flush blogu sahte bir proje adiyla yaziyordu.
    # Yaprak, worktree kokunun UZERINDEKI gercek proje adina cozulur.
    $norm = $Path -replace '/', '\'
    $m = [regex]::Match($norm, '^(?<kok>.*?)\\\.claude[\\-]worktrees\\', $script:BeyinRxCI)
    if (-not $m.Success) { $m = [regex]::Match($norm, '^(?<kok>.*?)\\worktrees\\', $script:BeyinRxCI) }
    if ($m.Success -and $m.Groups['kok'].Value) {
        $kokLeaf = Split-Path -Leaf $m.Groups['kok'].Value
        if ($kokLeaf) { return (Resolve-BeyinProjectName -Leaf $kokLeaf -Paths $Paths) }
    }
    $leaf = Split-Path -Leaf $Path
    if (-not $leaf) { $leaf = ($Path -replace '[:\\/]', '') }
    # KIMLIK KATMANI: ham yaprak dogrudan etiket olmuyor.
    return (Resolve-BeyinProjectName -Leaf $leaf -Paths $Paths)
}

function Get-BeyinProjectFromTranscript {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [string]$Vault = '',
        [hashtable]$Paths = $null
    )
    # $Paths tanimsizdi (2026-09-16): takma adlar (80-memory/proje-adlari.md) bu
    # yoldan hic uygulanmiyordu. Verilmezse Vault'tan turetilir.
    if (-not $Paths -and $Vault) { try { $Paths = Get-BeyinPaths -Vault $Vault } catch { $Paths = $null } }
    $r = @{ Cwd = ''; ProjectLeaf = ''; Excluded = $false; ExcludeReason = '' }

    # --- 0) BOYUT TAVANI KALDIRILDI (2026-09-10) ---
    # Eskiden tavan ustu dosya burada "cok-buyuk" ile ELENIYORDU; sonuc: 1 GB'lik
    # iki Codex oturumu ne yetim taramasina ne gecmis-toparla'ya girdi, hicbir
    # zaman ozetlenmedi. Artik buyuk dosyayi flush.ps1 bayt penceresiyle okuyor
    # (Read-BeyinTranscriptTail); bu fonksiyon zaten yalnizca ilk 40 satiri
    # okudugu icin boyut burada bir maliyet degil.

    # --- 1) Ucuz yol/ad kontrolleri (dosyayi acmadan) ---
    $fileName = Split-Path -Leaf $Path
    $dirName  = Split-Path -Leaf (Split-Path -Parent $Path)

    if ($fileName -like 'agent-*') {
        $r.Excluded = $true; $r.ExcludeReason = 'alt-ajan'; return $r
    }
    # Workflow/alt-ajan altyapi dosyalari oturum transkripti DEGIL:
    # journal.jsonl bir workflow'un ajan sonuclarini tutuyor, ozetlenirse
    # anlamsiz blok uretir.
    if ($fileName -eq 'journal.jsonl' -or $Path -like '*\subagents\*') {
        $r.Excluded = $true; $r.ExcludeReason = 'workflow-altyapi'; return $r
    }
    if ($dirName -like '*beyin-engine-cwd*' -or $Path -like '*beyin-engine-cwd*') {
        $r.Excluded = $true; $r.ExcludeReason = 'motor-kendi-cwd'; return $r
    }
    # Claude proje dizini adi cwd'yi kodluyor: Temp altindaki oturumlar
    # "...-AppData-Local-Temp-..." seklinde gorunur.
    if ($dirName -like '*AppData-Local-Temp*' -or $Path -like '*\AppData\Local\Temp\*') {
        $r.Excluded = $true; $r.ExcludeReason = 'gecici-klasor'; return $r
    }

    # --- 2) cwd'yi transkriptin ICINDEN oku ---
    try {
        $i = 0
        foreach ($line in (Get-Content -LiteralPath $Path -TotalCount 40 -Encoding UTF8 -ErrorAction SilentlyContinue)) {
            $i++
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            $o = $null
            try { $o = $line | ConvertFrom-Json } catch { continue }
            if (-not $o) { continue }

            # codex: session_meta -> payload.cwd
            if ($o.PSObject.Properties['payload'] -and $o.payload -and
                $o.payload.PSObject.Properties['cwd'] -and $o.payload.cwd) {
                # MAKINE THREAD ELEMESI (2026-09-10 denetimi):
                # Codex 0.153.4 her alt ajan (thread_source=subagent), her
                # otomatik onay incelemesi (guardian_review) ve
                # onboarding_checklist icin AYRI bir rollout-*.jsonl yaziyor.
                # Bunlar Claude'un 'agent-*.jsonl' adlandirmasina uymadigi icin
                # hicbir elemeye takilmiyordu. Olcum: ozetlenmis 233 Codex
                # rollout'unun 216'si (%92,7) makine thread'iydi - yani gunluk
                # 'claude -p' butcesinin nerdeyse tamami cop ozete gidiyordu.
                if ($o.payload.PSObject.Properties['thread_source']) {
                    $ts = [string]$o.payload.thread_source
                    if ($ts -and $ts -ne 'user') {
                        $r.Excluded = $true
                        $r.ExcludeReason = "codex-makine-thread-$ts"
                        return $r
                    }
                }
                $r.Cwd = [string]$o.payload.cwd; break
            }
            # claude: ust seviyede cwd
            if ($o.PSObject.Properties['cwd'] -and $o.cwd) {
                $r.Cwd = [string]$o.cwd; break
            }
        }
    } catch { }

    # --- 3) Son care: klasor adindan kaba tahmin (belirsiz olabilir) ---
    if (-not $r.Cwd -and $dirName -match '^[A-Za-z]--') {
        $r.ProjectLeaf = ($dirName -split '-' | Where-Object { $_ } | Select-Object -Last 1)
    }

    if ($r.Cwd) {
        $leaf = Get-BeyinProjectLeaf -Path $r.Cwd -Paths $Paths
        if ($leaf) { $r.ProjectLeaf = $leaf }

        # --- 4) Vault klasoru kontrolu (cwd cozulduyse) ---
        if ($Vault -and (Test-BeyinInVault -Vault $Vault -Cwd $r.Cwd)) {
            $r.Excluded = $true; $r.ExcludeReason = 'vault-klasoru'; return $r
        }
    }

    return $r
}

# ============================================================================
# WATERMARK (su isareti)  -  ayni konusmayi tekrar tekrar ozetlemeyi onler
# ----------------------------------------------------------------------------
# Onceki surumde flush her seferinde transkriptin SON 120 turunu aliyordu ve
# nereye kadar ozetlendigini kimse tutmuyordu. PreCompact + SessionEnd ayni
# oturum icin ust uste atesledigi icin ayni icerik 2-4 kez ozetlenip gunluk loga
# 2-4 blok olarak yaziliyordu (engine.log'da olculdu). Sonuc: sisen log, tekrarla
# dolan derleme girdisi, bosa giden kota.
#
# Cozum: her transkript icin "kacinci satira kadar isledim" bilgisini tut.
# ============================================================================

function ConvertTo-BeyinDuzYol {
    # Windows 'verbatim' oneklerini soyar: '\\?\C:\x' -> 'C:\x', '\\?\UNC\srv\p' -> '\\srv\p'.
    # Ileri egik cizgiyi ters cevirir, sondaki ayraci atar. Ayni dosya = ayni anahtar.
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $Path }
    $t = $Path
    if ($t.StartsWith('\\?\UNC\', [StringComparison]::OrdinalIgnoreCase)) { $t = '\\' + $t.Substring(8) }
    elseif ($t.StartsWith('\\?\')) { $t = $t.Substring(4) }
    return ($t.Replace('/', '\').TrimEnd('\'))
}

function Get-BeyinKey {
    # Bir yolu dosya adi olarak kullanilabilir kisa bir anahtara cevirir.
    # NORMALIZE (2026-09-16): verbatim onek / egik cizgi farki ayni dosyaya iki
    # kimlik uretiyordu (isaret, talep, kuyruk). Duz yollar icin hash DEGISMEZ.
    param([string]$Text)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $b = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes((ConvertTo-BeyinDuzYol -Path $Text).ToLowerInvariant()))
        return -join ($b[0..11] | ForEach-Object { $_.ToString('x2') })
    } finally { $sha.Dispose() }
}

function Get-BeyinWatermark {
    param([hashtable]$Paths, [string]$TranscriptPath)
    $f = Join-Path $Paths.Marks ((Get-BeyinKey -Text $TranscriptPath) + '.json')
    if (Test-Path -LiteralPath $f) {
        try {
            $o = Get-Content -LiteralPath $f -Raw -Encoding UTF8 | ConvertFrom-Json
            return [int]$o.lines
        } catch {
            # BOZUK ISARET DOSYASI SESSIZ KALAMAZ.
            #
            # Dosya VAR ama ayristirilamiyorsa (yarim yazilmis, disk hatasi,
            # kodlama bozulmasi) burasi 0 doner ve transkript HIC ISLENMEMIS
            # gorunur. Sonuc: yeniden ozetlenir ve gunluk loga AYNI oturum
            # icin IKINCI bir blok yazilir. overwritePolicy=never oldugu icin
            # o yinelenen blok kolayca temizlenemez.
            #
            # Yani sessiz bir parse hatasi, makine bolgesinde kalici kirlilige
            # donusuyordu ve tek belirtisi "bir oturum iki kez yazilmis"
            # olurdu - kimsenin sebebini bulamayacagi bir belirti.
            #
            # Davranis DEGISMIYOR (yine 0 donuyor, icerik feda edilmiyor);
            # yalnizca iz birakiyor.
            try {
                Write-BeyinLog -Vault $Paths.Vault -Message ("Get-BeyinWatermark: isaret dosyasi BOZUK, 0 varsayildi -> " +
                    "bu transkript yeniden ozetlenebilir (yinelenen blok riski): $(Split-Path -Leaf $f)")
            } catch { }
        }
    }
    return 0
}

# ----------------------------------------------------------------------------
# DENEME KAYDI  -  toparlama acligini bitirir
#
# SORUN: "cok kisa konusma" ve "bicim taninmadi" durumlarinda watermark BILEREK
# ilerletilmiyordu (dogru karar: dosya buyurse ozetlenebilsin). Ama sonuc, ayni
# zehirli dosyalarin her SessionStart'ta 3 slotun tamamini isgal etmesiydi.
# Olculdu: 156 spawn'in 89'u (%57) hicbir is yapmadan ayni dosyalari deniyordu;
# eskiler hic siraya gelmiyordu.
#
# COZUM watermark'i ilerletmek DEGIL (o icerigi feda ederdi), ayri bir deneme
# kaydi tutmak:
#     { v:2, lines, lastSize, skips, reason, lastTry }
# Tarayici kurali: DOSYA SON DENEMEDEN BU YANA BUYUMEDIYSE ATLA.
# Tek kural hem acligi bitirir hem hicbir icerigi feda etmez - dosya gercekten
# buyudugunde otomatik yeniden denenir.
#
# 'lines' alani degismedi -> Get-BeyinWatermark geriye uyumlu.
# ----------------------------------------------------------------------------

function Get-BeyinMark {
    param([hashtable]$Paths, [string]$TranscriptPath)
    $r = @{ Lines = 0; LastSize = 0; Skips = 0; Reason = ''; ByteOffset = [long]0; AttemptSize = [long]0 }
    $f = Join-Path $Paths.Marks ((Get-BeyinKey -Text $TranscriptPath) + '.json')
    if (Test-Path -LiteralPath $f) {
        try {
            $o = Get-Content -LiteralPath $f -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($o.PSObject.Properties['lines'])    { $r.Lines    = [int]$o.lines }
            if ($o.PSObject.Properties['lastSize']) { $r.LastSize = [int64]$o.lastSize }
            if ($o.PSObject.Properties['skips'])    { $r.Skips    = [int]$o.skips }
            if ($o.PSObject.Properties['reason'])   { $r.Reason   = [string]$o.reason }
            # bayt isareti (tavan ustu dosyalar): Read-BeyinTranscriptTail buradan devam eder
            if ($o.PSObject.Properties['byteOffset']) { $r.ByteOffset = [long]$o.byteOffset }
            if ($o.PSObject.Properties['attemptSize']) { $r.AttemptSize = [long]$o.attemptSize }
        } catch {
            # Get-BeyinWatermark ile ayni sinif: dosya var ama okunamiyor.
            # Burada sonuc iki katli - hem Lines=0 (yeniden ozetleme, yinelenen
            # blok riski) hem LastSize=0, yani Test-BeyinShouldRetry aclik
            # korumasini da kaybediyor ve transkript her taramada yeniden
            # deneniyor.
            try {
                Write-BeyinLog -Vault $Paths.Vault -Message ("Get-BeyinMark: isaret dosyasi BOZUK, varsayilanlar kullanildi -> " +
                    "hem yeniden ozetleme hem aclik korumasi kaybi riski: $(Split-Path -Leaf $f)")
            } catch { }
        }
    }
    return $r
}

function Set-BeyinAttempt {
    # Basarisiz/atlanmis bir denemeyi kaydeder. Watermark'a (lines) DOKUNMAZ.
    param([hashtable]$Paths, [string]$TranscriptPath, [string]$Reason)
    try {
        New-Item -ItemType Directory -Force -Path $Paths.Marks | Out-Null
        $cur = Get-BeyinMark -Paths $Paths -TranscriptPath $TranscriptPath
        $size = 0
        if (Test-Path -LiteralPath $TranscriptPath) {
            # KALICI KAYIP DUZELTMESI (2026-09-10, bagimsiz denetim).
            #
            # Burasi eskiden KOSULSUZ dosya boyutunu yaziyordu. Set-BeyinWatermark
            # icin ayni hata bu turda zaten duzeltilmisti, ama deneme kaydinda
            # duruyordu ve sonucu aynidir:
            #
            #   1. PreCompact bir kez ozetler  -> lines = 120
            #   2. Konusma devam eder, dosya buyur
            #   3. Bir deneme ATLANIR (slot yok / butce dolu / kisa parca)
            #   4. Burasi lastSize = DOSYANIN TAMAMI yazar
            #   5. Test-BeyinShouldRetry: lines>0 ve CurrentSize <= LastSize
            #      -> 'islenmis' -> 120. satirdan sonraki her sey SONSUZA DEK
            #      atlanir. Dosya daha da buyumedikce kimse geri donmez.
            #
            # Dogru davranis ISARETIN DURUMUNA bagli:
            #   lines > 0  (kismen islenmis) -> lastSize, ISLENEN SATIRIN bayt
            #      karsiligi olmali. Boylece o noktadan sonraki icerik 'buyume'
            #      sayilir ve tarayici geri gelir.
            #   lines = 0  (hic islenmemis)  -> dosya boyutu DOGRU. Burada amac
            #      karantinadir: cok kisa / cok buyuk / bozuk bir dosya, BUYUYENE
            #      kadar tekrar tekrar denenmesin (aclik korumasi).
            if ($cur.Lines -gt 0) {
                try { $size = [int64](Get-BeyinByteOffsetOfLine -Path $TranscriptPath -Lines $cur.Lines) } catch { $size = 0 }
                # Bayt karsiligi hesaplanamadiysa ONCEKI degeri koru; dosya
                # boyutuna DUSME - o, tam olarak kacinmaya calistigimiz sey.
                if ($size -le 0) { $size = [int64]$cur.LastSize }
            } elseif ($cur.ByteOffset -gt 0) {
                # BAYT ISARETLI dosya: 'buyume' olcusu isaretin kendisi olmali, dosya
                # boyutu degil; aksi halde islenmemis kalan kuyruk dusunce kaybolur.
                $size = [int64]$cur.ByteOffset
            } else {
                $size = (Get-Item -LiteralPath $TranscriptPath).Length
            }
        }
        # DENEME BOYUTU (2026-09-16, denetim): lastSize islenen satirin bayt karsiligi
        # kaldigi icin, isaretten sonra yalniz meta/arac satiri alan dosya her
        # SessionStart'ta 'buyudu' sayilip yeniden deneniyordu (olculdu: 515 bos
        # deneme / 7 gun, ayni dosya 91 kez tam okundu). attemptSize denemenin
        # yapildigi andaki boyut: dosya BUNU asmadan yeniden denenmez. Basarili
        # ozetleme (Set-BeyinWatermark/ByteMark) alani yazmadigi icin sifirlanir.
        $attemptSize = [long]0
        try { if (Test-Path -LiteralPath $TranscriptPath) { $attemptSize = [long](Get-Item -LiteralPath $TranscriptPath).Length } } catch { }
        $f = Join-Path $Paths.Marks ((Get-BeyinKey -Text $TranscriptPath) + '.json')
        $json = @{
            v = 2; lines = $cur.Lines; path = $TranscriptPath
            lastSize = $size; skips = ($cur.Skips + 1); reason = $Reason
            byteOffset = $cur.ByteOffset   # bayt isareti deneme kaydinda KAYBOLMASIN
            attemptSize = $attemptSize
            lastTry = (Get-Date -Format 'o')
        } | ConvertTo-Json -Compress
        Write-BeyinText -Path $f -Text $json
    } catch {
        # SESSIZ OLAMAZ.
        #
        # Write-BeyinText -> [System.IO.File]::WriteAllText, yani firlatir
        # (disk dolu, izin, kilit). Eskiden bu catch bostu ve sonucu suydu:
        #   deneme kaydi yazilmaz
        #   -> Test-BeyinShouldRetry LastSize=0 gorur
        #   -> HER taramada Retry=$true doner
        #   -> ayni transkript sonsuza dek yeniden denenir, her seferinde bir
        #      spawn slotu (oturum basina 3) yakarak
        #
        # Bu tam olarak bu mekanizmanin ONLEMEK icin var oldugu aclik. Yazma
        # basarisizligi kaydi sessizce dusurulunce, aclik korumasinin kendisi
        # sessizce kapaniyordu ve hicbir yerde gorunmuyordu.
        #
        # FIRLATMIYORUZ: cagiran flush.ps1 zaten bir hata yolunda; burada
        # firlatmak oturumu bozar. Ama artik iz birakiyor.
        #
        # Istisna ONCE degiskene aliniyor: ic ice try icinde $_ guvenilir
        # degil ve olculdu - ilk surumde log satiri sebepsiz cikiyordu
        # ("... | " ve sonrasi bos), yani tanı degeri olmayan bir iz.
        $sebep = 'bilinmiyor'
        if ($_ -and $_.Exception) { $sebep = $_.Exception.Message }
        if ([string]::IsNullOrWhiteSpace($sebep)) { $sebep = "$_" }
        try {
            Write-BeyinLog -Vault $Paths.Vault -Message ("Set-BeyinAttempt: deneme kaydi YAZILAMADI ($Reason) -> " +
                "aclik korumasi bu transkript icin devre disi: $(Split-Path -Leaf $TranscriptPath) | $sebep")
        } catch { }
    }
}

function Test-BeyinShouldRetry {
    # Tarayici kurali: islenmisse atla; denenmis ve dosya BUYUMEMISSE atla.
    param([hashtable]$Paths, [string]$TranscriptPath, [long]$CurrentSize)
    $m = Get-BeyinMark -Paths $Paths -TranscriptPath $TranscriptPath
    # KUCULEN / YENIDEN YAZILAN DOSYA (2026-09-16): isaret dosya boyundan buyukse
    # dosya degistirilmis demektir (olculdu: 539 MB isaretli rollout 5 MB oldu ve
    # 'karantina-buyuk-parca' ile sonsuza dek atlaniyordu). Yeniden dene; flush
    # baslangicta isareti sifirlar (bastan okur).
    if (($m.ByteOffset -gt 0 -and $CurrentSize -lt $m.ByteOffset) -or
        ($m.Lines -gt 0 -and $m.LastSize -gt 0 -and $CurrentSize -lt $m.LastSize)) {
        return @{ Retry = $true; Reason = 'dosya-kuculdu' }
    }
    # DENEME BOYUTU: son denemeden beri dosya buyumediyse karantina (bkz. Set-BeyinAttempt)
    if ($m.AttemptSize -gt 0 -and $CurrentSize -le $m.AttemptSize) {
        return @{ Retry = $false; Reason = "karantina-$($m.Reason)" }
    }
    if ($m.Lines -gt 0) {
        # TAVAN USTU + SATIR ISARETI (guvenlik denetimi 2026-09-10, risk 2): dosya
        # satir yoluyla ozetlenmisken 100 MB'i asmis. 'islenmis' sayilirsa hicbir
        # tarayici bir daha dokunmaz; olculdu: uc dosya (227/263/305 MB) boyle
        # takiliydi. Buyudugu surece yeniden denenir; flush satir isaretini bayt
        # karsiligina cevirip devam eder (Get-BeyinByteOffsetOfLine), sonra
        # bayt isareti (lines=0, lastSize) normal kurala doner.
        if ($CurrentSize -gt ($script:BeyinMaxTranscriptMB * 1MB)) {
            if ($m.LastSize -le 0 -or $CurrentSize -gt $m.LastSize) { return @{ Retry = $true; Reason = '' } }
            return @{ Retry = $false; Reason = 'karantina-buyuk-buyumedi' }
        }
        # TAVAN ALTI + SATIR ISARETI: dosya isaretten sonra BUYUDUYSE kalan
        # icerik vardir; yeniden dene. Buyumediyse gercekten islenmis.
        # (lastSize yoksa - v1 isaret - eski davranis: islenmis say. Boyle
        # isaretler Set-BeyinWatermark ilk yazmada v2'ye yukselir.)
        if ($m.LastSize -gt 0 -and $CurrentSize -gt $m.LastSize) {
            return @{ Retry = $true; Reason = '' }
        }
        return @{ Retry = $false; Reason = 'islenmis' }
    }
    if ($m.LastSize -gt 0 -and $CurrentSize -le $m.LastSize) {
        return @{ Retry = $false; Reason = "karantina-$($m.Reason)" }
    }
    return @{ Retry = $true; Reason = '' }
}

function Set-BeyinWatermark {
    # v2 (2026-09-10): 'lastSize' EKLENDI.
    #
    # KRITIK KAYIP (denetimde olculdu): eski surum yalniz 'lines' yaziyordu ve
    # Test-BeyinShouldRetry "Lines>0 ise islenmis" diyordu. Sonuc: PreCompact
    # bir kez ozetledikten sonra oturum devam edip pane oldurulurse (Claude'da
    # Ctrl+C, Codex'te pencere kapatma - ikisinde de SessionEnd ATESLENMEZ)
    # isaretin OTESINDEKI her satir sonsuza dek atlanirdi; ne yetim tarayici ne
    # gecmis-toparla dokunurdu. Olcum (2026-09-10, 533 isaret): 104 dosya
    # isaretten sonra buyumustu, 95'i (29.001 satir) 12 saatten eskiydi.
    #
    # lastSize ile kural bayt yoluyla ayni: dosya buyuduyse yeniden dene,
    # buyumediyse atla (aclik korumasi bozulmaz).
    param([hashtable]$Paths, [string]$TranscriptPath, [int]$Lines)
    New-Item -ItemType Directory -Force -Path $Paths.Marks | Out-Null
    $f = Join-Path $Paths.Marks ((Get-BeyinKey -Text $TranscriptPath) + '.json')
    # lastSize = ISLENEN SATIRIN bayt karsiligi (dosyanin o anki boyutu DEGIL).
    # Fark onemli: PreCompact 2098. satiri ozetlerken dosya 2500. satirda
    # olabilir. Boyutu yazarsak 2099-2500 arasi "buyume yok" sayilip kalici
    # kaybolur. Satirin bayt karsiligini yazinca o araliktaki her bayt
    # "islenmemis" olarak gorunur ve tarayici geri gelir.
    $size = 0
    $oncekiMark = Get-BeyinMark -Paths $Paths -TranscriptPath $TranscriptPath
    try {
        if (Test-Path -LiteralPath $TranscriptPath) {
            if ($Lines -gt 0) { $size = [int64](Get-BeyinByteOffsetOfLine -Path $TranscriptPath -Lines $Lines) }
            # -1 = "bilmiyorum" (I/O hatasi). DOSYA BOYUTUNA DUSME: eskiden
            # buradaki geri donus (Get-Item).Length idi ve gecici bir okuma
            # hatasi, isareti dosyanin sonuna atlayip aradaki islenmemis her
            # seyi kalici olarak gomuyordu. Bilinmiyorsa onceki isaret korunur;
            # en kotu ihtimalle ayni araligi bir kez daha ozetleriz.
            if ($size -lt 0) { $size = [int64]$oncekiMark.LastSize }
            # 0 = $Lines gecerli degil / dosya bos. Burada dosya boyutu dogru
            # geri donustur: islenecek satir yoksa tamami islenmis sayilir.
            if ($size -eq 0) { $size = (Get-Item -LiteralPath $TranscriptPath).Length }
        }
    } catch { }
    # Bayt isareti varsa KORU: tavan ustu dosya satir yoluna dusup geri
    # donerse offset kaybolmasin.
    $cur = Get-BeyinMark -Paths $Paths -TranscriptPath $TranscriptPath
    $json = @{ v = 2; lines = $Lines; path = $TranscriptPath; lastSize = $size
               byteOffset = $cur.ByteOffset; ts = (Get-Date -Format 'o') } |
            ConvertTo-Json -Compress
    Write-BeyinText -Path $f -Text $json
}

function Set-BeyinByteMark {
    # TAVAN USTU dosya icin BAYT isareti. 'lines' bilerek 0 kalir: satir sayisi
    # bilinmiyor (dosya bastan okunmuyor). Tarayicilar bu dosyayi 'islenmis'
    # degil, 'lastSize' uzerinden degerlendirir: buyumediyse atlanir
    # (karantina-buyuk-parca), buyudugu an yeniden denenir - tam istenen.
    # -Size = ISLENEN son bayt (dosya boyutu DEGIL) verilmeli (2026-09-16):
    # parcali okumada kalan bayt kuyruga bagli kalmasin, tarayici da gorsun.
    param([hashtable]$Paths, [string]$TranscriptPath, [long]$Offset, [long]$Size)
    New-Item -ItemType Directory -Force -Path $Paths.Marks | Out-Null
    $f = Join-Path $Paths.Marks ((Get-BeyinKey -Text $TranscriptPath) + '.json')
    $json = @{ v = 2; lines = 0; path = $TranscriptPath; lastSize = $Size; byteOffset = $Offset
               skips = 0; reason = 'buyuk-parca'; ts = (Get-Date -Format 'o') } | ConvertTo-Json -Compress
    Write-BeyinText -Path $f -Text $json
}

function Clear-BeyinStaleClaims {
    # claims\*.lock dosyalari hicbir zaman silinmiyordu: Enter-BeyinClaim
    # yaratiyor, kilit surec olunce SERBEST kaliyor ama dosya diskte kaliyor.
    # Olcum (2026-09-10): 638 dosya, %100'u 1 saatten eski (yani olu).
    # Kilitli olan zaten silinemez (Remove-Item sessizce basarisiz olur),
    # silinebilen zaten olu - bu yuzden guvenli.
    # Ayni turda gunluk sayac dosyalari (budget-*/blocks-*) da suprulur.
    param([hashtable]$Paths, [int]$OlderThanDays = 7)
    $cut = (Get-Date).AddDays(-$OlderThanDays)
    try {
        if (Test-Path -LiteralPath $Paths.Claims) {
            foreach ($f in @(Get-ChildItem -LiteralPath $Paths.Claims -Filter '*.lock' -File -ErrorAction SilentlyContinue)) {
                if ($f.LastWriteTime -lt $cut) { Remove-Item -LiteralPath $f.FullName -Force -ErrorAction SilentlyContinue }
            }
        }
    } catch { }
    try {
        $cut2 = (Get-Date).AddDays(-60)
        foreach ($f in @(Get-ChildItem -LiteralPath $Paths.ScrState -File -ErrorAction SilentlyContinue |
                         Where-Object { $_.Name -match '^(?:budget|blocks)-\d{4}-\d{2}-\d{2}\.txt$' })) {
            if ($f.LastWriteTime -lt $cut2) { Remove-Item -LiteralPath $f.FullName -Force -ErrorAction SilentlyContinue }
        }
    } catch { }
}

function Clear-BeyinStaleMarks {
    param([hashtable]$Paths, [int]$OlderThanDays = 30)
    if (-not (Test-Path -LiteralPath $Paths.Marks)) { return }
    $cut = (Get-Date).AddDays(-$OlderThanDays)
    foreach ($f in @(Get-ChildItem -LiteralPath $Paths.Marks -Filter '*.json' -File -ErrorAction SilentlyContinue)) {
        # TRANSKRIPT HALA DISKTEYSE ISARETI SILME (2026-09-10): isaret silinince
        # Get-BeyinWatermark 0 doner ve uzun omurlu / resume edilen bir oturum
        # BASTAN ozetlenir -> makine bolgesinde yinelenen blok (overwritePolicy
        # never oldugu icin elle temizlenemez). Yalniz transkripti gitmis
        # isaretler cop.
        if ($f.LastWriteTime -lt $cut) {
            $hala = $false
            try {
                $mo = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
                if ($mo.PSObject.Properties['path'] -and $mo.path -and (Test-Path -LiteralPath ([string]$mo.path))) { $hala = $true }
            } catch { }
            if ($hala) { continue }
        }
        if ($f.LastWriteTime -lt $cut) { Remove-Item -LiteralPath $f.FullName -Force -ErrorAction SilentlyContinue }
    }
}

# ============================================================================
# ES ZAMANLILIK TAVANI ve GUNLUK BUTCE
# ----------------------------------------------------------------------------
# Kullanici ayni anda 10+ claude oturumu calistiriyor (.state/sessions'da
# olculdu). Her biri kapanista bir 'claude -p' baslatirsa motor kullanicinin
# kendi interaktif kotasini yer ve rate limit'i motorun kendisi tetikler.
# En fazla N es zamanli motor cocugu ve gunde en fazla M cagri.
# ============================================================================

# ============================================================================
# TRANSKRIPT TALEP KILIDI
# ----------------------------------------------------------------------------
# Watermark spawn aninda OKUNUYOR, 240 saniyelik model cagrisindan SONRA
# yaziliyor. Aradaki dort dakikada hicbir talep isareti yoktu: iki SessionStart
# (veya SessionEnd + PreCompact) ayni transkripti secip iki kez ozetleyebiliyordu
# -> mukerrer blok + iki kez tuketilen butce. engine.log'da ayni saniyede iki
# toparlama gozlendi.
#
# NEDEN DOSYA KILIDI, JSON "claimed" ISARETI DEGIL: isletim sistemi surec olunce
# handle'i serbest birakir. JSON isaret kullanilsaydi coken bir flush transkripti
# KALICI olarak kilitlerdi.
# ============================================================================

function Enter-BeyinClaim {
    param([hashtable]$Paths, [string]$TranscriptPath)
    if (-not $TranscriptPath) { return $null }
    try {
        New-Item -ItemType Directory -Force -Path $Paths.Claims | Out-Null
        $f = Join-Path $Paths.Claims ((Get-BeyinKey -Text $TranscriptPath) + '.lock')
        return [System.IO.File]::Open($f, 'OpenOrCreate', 'ReadWrite', 'None')
    } catch { return $null }
}

function Exit-BeyinClaim {
    param($Handle)
    if ($Handle) { try { $Handle.Close(); $Handle.Dispose() } catch { } }
}

function Test-BeyinClaimBusy {
    # Ucuz on kontrol (otorite DEGIL): kilidi acip hemen kapatir. Yalnizca
    # bosa surec acmayi azaltir; dogruluk garantisi flush.ps1'in kendi
    # talebinde.
    param([hashtable]$Paths, [string]$TranscriptPath)
    $h = Enter-BeyinClaim -Paths $Paths -TranscriptPath $TranscriptPath
    if ($h) { Exit-BeyinClaim -Handle $h; return $false }
    return $true
}

# ============================================================================
# ICERIK-TABANLI GERI GETIRME  (2026-09-10, bagimsiz denetim - kritik bulgu)
# ----------------------------------------------------------------------------
# Motor kavram notu URETIYOR ama modele yalnizca index.md'deki BASLIK LISTESI
# ulasiyordu. Olculdu: 84 notun govdesi hicbir enjeksiyonda yer almiyor.
# Yani beyin ogreniyor, hatirlamiyor - katalogu var, icerigi yok.
#
# Buradaki uc fonksiyon "dogru ani, dogru anda" katmanidir: kullanicinin
# yazdigi metne gercekten benzeyen kavramlarin OZETI enjekte edilir.
#
# TASARIM KURALI: gurultu sessizlikten kotudur. Esigi gecen yoksa HICBIR SEY
# enjekte edilmez. Alakasiz bir "hatirlatma" modeli yanlis yone iter ve
# zamanla tum hafiza enjeksiyonuna olan guveni bozar.
# ============================================================================

$script:BeyinDurdurmaKelimeleri = @(
    # Turkce
    'bir','bu','su','o','ve','veya','ile','icin','gibi','kadar','daha','cok','az',
    'ama','fakat','ancak','yani','eger','ise','de','da','ki','mi','mu','ne','nasil',
    'neden','niye','hangi','kim','nerede','ben','sen','biz','siz','onlar','var','yok',
    'olan','olarak','oldu','olur','yap','yapti','yapmak','et','etti','etmek','ol',
    'bunu','sunu','onu','beni','seni','bize','size','simdi','sonra','once','tum',
    'her','bazi','diger','ayni','baska','kendi','icinde','uzerinde','altinda',
    # ICERIK TASIMAYAN SIFAT/ZARFLAR (2026-09-18, olculdu): bunlar hem her
    # istemde hem cogu notta gecer ve asagidaki kademeli esikte HAKSIZ bir
    # indirim satin aliyorlardi. Olcum: 'eski relase silip' istemi
    # 'ajan-onbellek-dosya-commit-ezmesi' notunu YALNIZCA 'eski' kelimesi
    # yuzunden cos=0.52'de gecirdi.
    'eski','yeni','disi','disinda','icin','ici','uzere','dogru','yanlis',
    'buyuk','kucuk','ilk','son','iyi','kotu','tam','yarim','hepsi','hicbir',
    'sekilde','durum','durumda','konu','konusu','zaten','ayrica','yine',
    # BU KASANIN KENDI GURULTUSU: motorun adi her istemde ve cogu notta geciyor,
    # yani hicbir sey ayirt etmiyor. Olculdu: 'beyin yedek brain-cli' istemi
    # 'beyin-motoru-yetim-tarama-siniri' notunu YALNIZCA 'beyin' kelimesi
    # yuzunden cos=0.53'te gecirdi. Gercek beyin sorularinda 'motoru', 'kanca',
    # 'kavram' gibi ayirt edici terimler zaten var.
    'beyin','vault','kasa',
    # Ingilizce
    'the','a','an','and','or','but','if','then','else','for','with','from','to','of',
    'in','on','at','by','is','are','was','were','be','been','being','have','has','had',
    'do','does','did','can','could','will','would','should','this','that','these',
    'those','it','its','as','not','no','yes','you','your','we','our','they','their',
    # Kabuk/kod gurultusu
    'true','false','null','none','void','return','function','param','string','int',
    # Turkce edilgen/durum fiilleri (2026-09-17): her gunluk log blogunda gecerler
    # ('eklendi', 'edildi', 'mevcut'), konu tasimazlar. Olculdu: denetle'nin
    # 'bosluk' listesinde ilk ona giriyorlardi ve gercek konulari asagi itiyorlardi.
    # Geri getirmede de gurultu: iki not arasindaki ortak 'eklendi' alaka degildir.
    'eklendi','edildi','yapildi','olusturuldu','guncellendi','kaldirildi','duzeltildi',
    'calisti','gecti','verildi','alindi','yazildi','okundu','kullanildi','saglandi',
    'uygulandi','denendi','bulundu','mevcut','gerekiyor','gerekli','sonrasi','oncesi',
    'basarili','basarisiz','tamamlandi','baslatildi','degistirildi','silindi'
)

# HAFIF TURKCE EK SOYUCU (2026-10-05, avenoxbeyin'den uyarlandi). Sorgu ve
# indeks AYNI fonksiyondan gecer: dilbilimsel dogruluk degil, iki tarafta ayni
# davranis onemli. Yalniz yaygin cekim ekleri, en uzun once; kok 4 karakterin
# altina inmez, 6 karakterden kisa kelimeye dokunulmaz. ASCII katlanmis ('i')
# ve Turkce ('ı') bicimlerin ikisi de var. Olculdu: 'notlari' -> 'notlar',
# 'motoru' -> 'motor', 'hafizasi' -> 'hafiza', 'kavrami' -> 'kavram'.
$script:BeyinTurkceEkler = @(
    'lerinin','larinin','lerini','larini','lerine','larina','lerinde','larinda','lerden','lardan',
    'lerin','larin','ların','lerde','larda','lere','lara','leri','lari','ları','ler','lar',
    'sinin','sının','sunun','sünün','sini','sını','sunu','sünü','sine','sina','sına','suna','süne',
    'sinde','sinda','sında','sunda','sünde','inden','indan','ından','undan','ünden',
    'inin','ının','unun','ünün','ini','ını','unu','ünü','ine','ina','ına','una','üne','inde','inda','ında','unda','ünde',
    'iyle','ıyla','uyla','üyle','yle','yla','den','dan','ten','tan','nin','nın','nun','nün',
    'si','sı','su','sü','in','ın','un','ün','im','ım','um','üm','de','da','te','ta','ye','ya','yi','yı','yu','yü',
    'i','ı','u','ü'
) | Sort-Object { -$_.Length }

function Get-BeyinKokle {
    param([string]$W)
    if (-not $W -or $W.Length -lt 6) { return $W }
    foreach ($ek in $script:BeyinTurkceEkler) {
        if (-not $W.EndsWith($ek) -or ($W.Length - $ek.Length) -lt 4) { continue }
        # 'in/im' ailesi (2 harf) yalniz 7+ harfli kelimede: 'plugin', 'domain' gibi
        # Ingilizce terimler 'plug'/'doma' olmasin; 'motorun' (7) yine 'motor'.
        if ($ek.Length -eq 2 -and $ek -match '^[iıuü][nm]$' -and $W.Length -lt 7) { continue }
        # 's'/'y' ile baslayan ekler (si, su, yi, yla...) yalniz UNLUDEN sonra gelir:
        # 'indeksi' -> 'indeks' (i), 'arabasi' -> 'araba' (si). Olculdu: aksi halde
        # 'indeksi' -> 'indek' oluyor ve 'indeks' ile eslesmiyordu.
        $onceki = $W[$W.Length - $ek.Length - 1]
        if (($ek[0] -eq 's' -or $ek[0] -eq 'y') -and ('aeiouAEIOUıöü' -notcontains $onceki) -and ([string]'aeıioöuü').IndexOf($onceki) -lt 0) { continue }
        return $W.Substring(0, $W.Length - $ek.Length)
    }
    return $W
}

function Get-BeyinKelimeler {
    # Metni eslesmeye uygun terimlere ayirir.
    #
    # ToLowerInvariant KULLANILIR ve bu BILINCLI: tr-TR'de 'I'.ToLower() = 'ı'
    # olur; sorgu ile indeks AYNI donusumden gecmedikce eslesme sessizce
    # bozulur. Dilbilimsel dogruluk degil, IKI TARAFTA AYNI davranis onemli.
    param([string]$Text, [int]$MinUzunluk = 4)
    if ([string]::IsNullOrWhiteSpace($Text)) { return @() }
    $temiz = [regex]::Replace($Text.ToLowerInvariant(), '[^\p{L}\p{Nd}]+', ' ')
    $set = @{}
    foreach ($w in ($temiz -split '\s+')) {
        if ($w.Length -lt $MinUzunluk) { continue }
        if ($script:BeyinDurdurmaKelimeleri -contains $w) { continue }
        $w = Get-BeyinKokle -W $w
        if ($w.Length -lt $MinUzunluk) { continue }
        $set[$w] = $true
    }
    return @($set.Keys)
}

function Get-BeyinConceptIndex {
    # Kavram notlarinin hafif indeksi. ONBELLEKLI.
    #
    # NEDEN ONBELLEK: bu fonksiyon UserPromptSubmit'ten cagriliyor, yani HER
    # prompt'ta. 84 dosyayi her seferinde acmak 5 sn tavanini zorlar ve
    # kullanicinin her mesajina gecikme ekler. Parmak izi = not sayisi + en
    # yeni degisiklik zamani; degismediyse tek bir JSON okunur.
    param([hashtable]$Paths)
    $conceptDir = Join-Path $Paths.Compiled 'concepts'
    if (-not (Test-Path -LiteralPath $conceptDir)) { return @() }

    $dosyalar = @(Get-ChildItem -LiteralPath $conceptDir -Filter '*.md' -File -ErrorAction SilentlyContinue)
    if ($dosyalar.Count -eq 0) { return @() }

    $enYeni = ($dosyalar | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1).LastWriteTimeUtc.Ticks
    # 'v2-' (2026-10-05): terimler artik ek soyucudan geciyor ve 'guncel' alani
    # eklendi; eski onbellek ayni parmak iziyle bayat kalirdi.
    $parmak = "v2-$($dosyalar.Count)-$enYeni"
    # UZANTI '.dat', '.json' DEGIL (2026-09-11).
    #
    # brain-cli vault'taki .json dosyalarini sema denetiminden geciriyor ve
    # onbellekte tutulan kavram ozetlerinden biri GERCEK JSX kodu iceriyordu:
    # 'style={{...}}'. Yer tutucu dedektoru bunu cozulmemis bir sablon sandi
    # ve denetimi kirmiziya dusurdu - yanlis pozitif.
    #
    # Bu dosya MAKINE DURUMUDUR, denetlenecek bir not degil; icerigi de
    # tamamen turetilmis (silinirse kendini yeniden kurar). Taranmayan bir
    # uzantiya tasimak, tarayiciyi yaniltmadan onu kapsam disinda tutuyor.
    $onbellek = Join-Path $Paths.ScrState 'kavram-indeks.dat'

    if (Test-Path -LiteralPath $onbellek) {
        try {
            $o = Get-Content -LiteralPath $onbellek -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($o.parmak -eq $parmak -and $o.items) { return @($o.items) }
        } catch { }
    }

    $items = New-Object System.Collections.Generic.List[object]
    foreach ($f in $dosyalar) {
        try {
            # Yalniz BAS KISIM okunur: frontmatter + baslik + ilk paragraf.
            # Tam govde eslesme icin gerekli degil ve maliyeti buyutur.
            $ilk = @(Get-Content -LiteralPath $f.FullName -TotalCount 40 -Encoding UTF8 -ErrorAction SilentlyContinue)
            if (-not $ilk) { continue }
            $metin = $ilk -join "`n"

            $baslik = ''
            $m = [regex]::Match($metin, '(?m)^title:\s*"?([^"\r\n]+)"?\s*$')
            if ($m.Success) { $baslik = $m.Groups[1].Value.Trim() }
            if (-not $baslik) {
                $m2 = [regex]::Match($metin, '(?m)^#\s+(.+)$')
                if ($m2.Success) { $baslik = $m2.Groups[1].Value.Trim() }
            }
            if (-not $baslik) { $baslik = [IO.Path]::GetFileNameWithoutExtension($f.Name) }

            # Govde: frontmatter'dan ve '# Baslik' satirindan SONRAKI ilk paragraf
            $govde = ''
            $fmSon = $metin.IndexOf("`n---", 4)
            $kalan = if ($fmSon -gt 0) { $metin.Substring($fmSon + 4) } else { $metin }
            foreach ($ln in ($kalan -split "`n")) {
                $t = $ln.Trim()
                if (-not $t -or $t.StartsWith('#') -or $t.StartsWith('---')) { continue }
                $govde = $t
                break
            }

            # TAZELIK (2026-10-05, hafiza-os kaynak-bagi fikrinin ucuz hali): notun
            # 'updated' gunu enjeksiyon satirina yazilir; model eski bilgiyi
            # guncel karardan ayirabilsin.
            $guncel = ''
            $mu = [regex]::Match($metin, '(?m)^updated:\s*"?(\d{4}-\d{2}-\d{2})')
            if ($mu.Success) { $guncel = $mu.Groups[1].Value }
            $items.Add([pscustomobject]@{
                dosya   = $f.Name
                baslik  = $baslik
                guncel  = $guncel
                ozet    = $(if ($govde.Length -gt 240) { $govde.Substring(0, 240) } else { $govde })
                # Baslik terimleri AYRI tutulur: baslikta gecen bir terim,
                # govdede gecenden cok daha guclu bir alaka sinyalidir.
                bterim  = @(Get-BeyinKelimeler -Text ($baslik + ' ' + [IO.Path]::GetFileNameWithoutExtension($f.Name)))
                gterim  = @(Get-BeyinKelimeler -Text $govde)
            })
        } catch { }
    }

    try {
        Write-BeyinText -Path $onbellek -Text (@{ v = 1; parmak = $parmak; items = $items.ToArray() } | ConvertTo-Json -Depth 5 -Compress)
    } catch { }
    return @($items.ToArray())
}

# KULLANIM SONMESI (BB2, 2026-10-06; AgentSpace usage ledger + decay dersi).
# 'beyin kullanim 14' (Pazar gorevi) .state\kullanim-sonme.dat yazar: son 14 gunde
# 5+ OLCULEBILIR enjeksiyonda hic acilmayan/anilmayan kavram notu x0.6 (14 gunden
# taze not muaf). Kanca yolu yalniz bu dosyayi okur (ConvertFrom-Json yok, mtime
# onbellekli). Esigi GECMIS adayin SIRASINI degistirir; esigi kendisi degistirmez.
$script:BeyinSonmeOnbellek = $null; $script:BeyinSonmeDamga = 0
function Get-BeyinKullanimSonme {
    param([hashtable]$Paths)
    $bos = @{}
    try {
        $ayar = 'acik'
        try { $ayar = [string](Get-BeyinAyar 'BEYIN_SONME' (Get-BeyinAyarVars 'BEYIN_SONME')) } catch { }
        if ($ayar -eq 'kapali') { return $bos }
        $f = Join-Path $Paths.ScrState 'kullanim-sonme.dat'
        if (-not (Test-Path -LiteralPath $f)) { return $bos }
        $d = (Get-Item -LiteralPath $f).LastWriteTimeUtc.Ticks
        if ($script:BeyinSonmeOnbellek -and $script:BeyinSonmeDamga -eq $d) { return $script:BeyinSonmeOnbellek }
        $h = @{}
        foreach ($s in [IO.File]::ReadAllLines($f)) {
            $par = $s.Split([char]9)
            if ($par.Count -lt 2) { continue }
            $c = 0.0
            if ([double]::TryParse($par[1], [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$c) -and $c -gt 0 -and $c -lt 1) {
                $h[$par[0].Trim([char]0xFEFF).ToLowerInvariant()] = $c
            }
        }
        $script:BeyinSonmeOnbellek = $h; $script:BeyinSonmeDamga = $d
        return $h
    } catch { return $bos }
}

function Find-BeyinRelevantConcepts {
    # Sorgu metnine en yakin kavramlari doner. Eslesme yoksa BOS dizi.
    param(
        [hashtable]$Paths,
        [string]$Query,
        [int]$EnFazla = 2,
        [int]$Esik = 2,         # kac AYRI terim tutmali (baslik terimi 2 sayar)
        [switch]$SonmeYok
    )
    $qt = @(Get-BeyinKelimeler -Text $Query)
    if ($qt.Count -lt 2) { return @() }   # tek kelimelik prompt: sinyal yok

    $idx = @(Get-BeyinConceptIndex -Paths $Paths)
    if ($idx.Count -eq 0) { return @() }

    $skorlu = New-Object System.Collections.Generic.List[object]
    foreach ($it in $idx) {
        $skor = 0
        $tutan = New-Object System.Collections.Generic.List[string]
        foreach ($t in $qt) {
            if ($it.bterim -contains $t)      { $skor += 2; $tutan.Add($t) }
            elseif ($it.gterim -contains $t)  { $skor += 1; $tutan.Add($t) }
        }
        # IKI KOSUL BIRDEN: hem agirlikli skor esigi hem EN AZ IKI AYRI TERIM.
        #
        # Tek basina skor esigi yetmiyor, cunku baslikta gecen bir terim 2 puan
        # ediyor - yani TEK bir yaygin kelime esigi geciyordu. Olculdu: "bana
        # bir kek tarifi ver" sorgusu, sirf 'tarifi' kelimesi yuzunden
        # "MiniMax Music 3 Caption Tarifi" notunu getiriyordu.
        #
        # Iki ayri terim sarti bunu keser: gercek bir konu ortusmesinde birden
        # fazla terim tutar, rastlantisal kelime eslesmesinde tutmaz.
        if ($skor -ge $Esik -and $tutan.Count -ge 2) {
            $skorlu.Add([pscustomobject]@{ Item = $it; Skor = $skor; Tutan = @($tutan) })
        }
    }
    if ($skorlu.Count -eq 0) { return @() }
    if (-not $SonmeYok) {
        $sn = Get-BeyinKullanimSonme -Paths $Paths
        if ($sn.Count -gt 0) {
            foreach ($x in $skorlu) { $sk = ([string]$x.Item.dosya).ToLowerInvariant(); if ($sn.ContainsKey($sk)) { $x.Skor = [math]::Round($x.Skor * $sn[$sk], 2) } }
        }
    }
    return @($skorlu.ToArray() | Sort-Object Skor -Descending | Select-Object -First $EnFazla)
}

function Get-BeyinTranscriptRoots {
    # Iki ajanin transkript kokleri. TEK KAYNAK: bu liste eskiden hem
    # session-start.ps1'de hem gecmis-toparla.ps1'de ayri ayri yaziliydi;
    # birinde yapilan duzeltme digerine gecmiyordu.
    #
    # ORTAM DEGISKENLERI ONURLANDIRILIR (2026-09-10, bagimsiz denetim):
    #   CLAUDE_CONFIG_DIR - Claude Code'un yapilandirma koku
    #   CODEX_HOME        - Codex'in koku
    # Ikisi de resmi olarak desteklenen degiskenler. Sabit ~\.claude ve
    # ~\.codex varsayimi, bunlari kullanan bir makinede tarayiciyi BOS bir
    # klasore bakar hale getirir: hicbir oturum bulunmaz, hicbir hata da
    # verilmez. Yeni makineye tasinabilirlik icin bu varsayim kalkmali.
    $claudeKok = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $env:USERPROFILE '.claude' }
    $codexKok  = if ($env:CODEX_HOME)        { $env:CODEX_HOME }        else { Join-Path $env:USERPROFILE '.codex' }
    return @(
        @{ Path = (Join-Path $claudeKok 'projects'); Filter = '*.jsonl';         Agent = 'claude' }
        @{ Path = (Join-Path $codexKok  'sessions'); Filter = 'rollout-*.jsonl'; Agent = 'codex'  }
    )
}

function Enter-BeyinSlot {
    # Bos bir slot kilidi alir. Alamazsa $null doner (cagiran isi kuyruga atar).
    #
    # -Prefix AYRI HAVUZ ACAR (2026-09-10, bagimsiz denetim).
    #
    # Onceden tek bir isim alani vardi: flush 'slot1/slot2', derleyici de
    # -MaxSlots 1 ile YALNIZ 'slot1'. Sonuc: calisan bir flush slot1'i tutuyor
    # ve derleyici hicbir zaman slot bulamiyordu. Derleyici tam da yogun
    # zamanlarda (flush'larin kostugu zaman) susuyordu ve bunun tek izi
    # engine.log'daki 'baska bir derleyici calisiyor' satiriydi - ki YANLIS bir
    # aciklamaydi, calisan sey bir derleyici degil bir flush'ti.
    #
    # Butce zaten ayri (flush 50, derleyici 60): es zamanlilik siniri da ayri
    # olmali. Tek slot kurali derleyicinin KENDI havuzunda gecerli.
    param([hashtable]$Paths, [int]$MaxSlots = 2, [string]$Prefix = 'slot')
    New-Item -ItemType Directory -Force -Path $Paths.Slots | Out-Null
    for ($i = 1; $i -le $MaxSlots; $i++) {
        $f = Join-Path $Paths.Slots "$Prefix$i.lock"
        try {
            return [System.IO.File]::Open($f, 'OpenOrCreate', 'ReadWrite', 'None')
        } catch { continue }
    }
    return $null
}

function Exit-BeyinSlot {
    param($Handle)
    if ($Handle) { try { $Handle.Close(); $Handle.Dispose() } catch { } }
}

# Butce tavanlari TEK KAYNAK (2026-09-10): flush 50, compile 60 (10 birimlik
# fark derleyicinin ac kalmamasi icin ayrilmis rezerv). Onceden bu sayilar
# flush.ps1, compile.ps1 ve doktor.ps1'e ayri ayri gomuluydu; doktor 60'i tavan
# sanip 'gunluk butce OK 50/60' diyordu - oysa flush 50'de tamamen kilitliydi
# ve satir YAPISAL OLARAK asla kirmizi olamiyordu.
# 50 -> 80 (2026-09-15): 6 Eylul'den beri hemen her gun 49-51 harcandi ve gunde 38-102
# 'butce doldu' reddi dustu; kuyruk her gun tasiyordu. Ozetleyici haiku-sinifi ucuz bir
# cagri, tavan koruma icin var, dar bogaz olmak icin degil. BEYIN_FLUSH_BUTCE ile ayarlanir.
# VARSAYILAN 80 -> 200 (2026-09-17, olculdu). 80'lik tavan gercek bir gunu
# tasimiyordu: o gun 77 flush + 2 compile + 1 al ile tavan 14:00'te doldu ve
# dort oturumun kapanis ozeti ertesi gune kaldi. Tavanin amaci kullanicinin
# kotasini korumak, isi bogmak degil.
$script:BeyinFlushVars     = Get-BeyinAyarVars 'BEYIN_FLUSH_BUTCE'
$script:BeyinFlushBudget   = $(if ((Get-BeyinAyar 'BEYIN_FLUSH_BUTCE' $script:BeyinFlushVars) -match '^\d+$') { [int](Get-BeyinAyar 'BEYIN_FLUSH_BUTCE' $script:BeyinFlushVars) } else { [int]$script:BeyinFlushVars })
$script:BeyinCompileBudget = $script:BeyinFlushBudget + 10   # derleyici rezervi: flush tavaninin 10 ustu
# Oturum durumu bayatlik esigi TEK KAYNAK: session-start temizligi ve doktor ayni sayiyi
# kullanir. 14 gun: uzun Codex thread'leri haftalarca acik kalabiliyor (olculdu: 20
# Agustos'ta acilan rollout 15 Eylul'de hala aktif); durum silinirse prompt sayaci
# sifirlanir ve kapanis ozeti 'cok kisa' diye atlanir.
$script:BeyinSessionStaleDays = 14
function Get-BeyinSessionStaleDays { return $script:BeyinSessionStaleDays }

function Get-BeyinFlushBudget {
    # 1-1000 araligina sikistir (2026-10-05): BEYIN_FLUSH_BUTCE=0 (env ya da
    # elle yazilmis json) '^\d+$' kapisini geciyor ve butce 0 olunca TUM
    # ozetleme sessizce duruyordu; Test-BeyinAyarDeger yalniz 'beyin ayar' yolunda.
    $n = 0
    try { $n = [int]$script:BeyinFlushBudget } catch { $n = 0 }
    if ($n -lt 1) { $n = 1 }
    if ($n -gt 1000) { $n = 1000 }
    return $n
}

function Get-BeyinOturumPayi {
    # Bir oturumun pre-compact yoluyla gunde alabilecegi EN FAZLA model cagrisi.
    #
    # NEDEN (2026-09-17, makbuzla olculdu): gunluk butce oturum KAPATMAKTAN
    # degil, uzun oturumlarin otomatik SIKISTIRMASINDAN doluyordu. Bes oturum
    # 27/14/14/7/1 kez sikismis, 63 cagri harcamis ve tavan gun ortasinda
    # dolmustu; sonraki oturumlarin kapanis ozeti ac kaldi. Is mesru (63'un
    # 57'si gunluk loga gercekten yazdi), o yuzden DUSURULMUYOR - payi asan
    # kuyruga aliniyor ve sirasi gelince isleniyor.
    #
    # Pay gunluk butcenin %20'si, en az 10: bes farkli oturumun ilk ozetleri
    # bir oturumun 27. sikismasindan ONCE gecsin.
    param()
    $pay = [int][math]::Floor($script:BeyinFlushBudget * 0.20)
    if ($pay -lt 10) { $pay = 10 }
    return $pay
}
function Get-BeyinCompileBudget { return $script:BeyinCompileBudget }

function Get-BeyinBudgetUsed {
    # Gunun sayacini TUKETMEDEN okur. Kilit almaz: yalniz on kontrol icin.
    param([hashtable]$Paths)
    try {
        $f = Join-Path $Paths.ScrState ("budget-{0}.txt" -f ((Get-Date).ToString('yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)))
        if (-not (Test-Path -LiteralPath $f)) { return 0 }
        $raw = (Get-Content -LiteralPath $f -Raw -Encoding UTF8)
        if (-not $raw) { return 0 }
        $raw = $raw -replace ('^' + [char]0xFEFF), ''
        $n = 0
        if ([int]::TryParse($raw.Trim(), [ref]$n)) { return $n }
    } catch { }
    return 0
}

function Restore-BeyinBudget {
    # Kota/limit hatasinda sayaci GERI VER: o cagri hizmet almadi.
    # Onceden her kota hatasi gunluk tavandan bir birim yakiyordu; 7-8 Eylul'de
    # 36 kota hatasi bu sekilde bir gunluk butcenin %72'sini bosa harcadi.
    param([hashtable]$Paths)
    try {
        $f = Join-Path $Paths.ScrState ("budget-{0}.txt" -f ((Get-Date).ToString('yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)))
        $lock = Join-Path $Paths.ScrState 'budget.lock'
        Invoke-BeyinWithLock -LockPath $lock -TimeoutSeconds 5 -Action {
            $n = 0
            if (Test-Path -LiteralPath $f) {
                $raw = (Get-Content -LiteralPath $f -Raw -Encoding UTF8) -replace ('^' + [char]0xFEFF), ''
                [void][int]::TryParse($raw.Trim(), [ref]$n)
            }
            if ($n -gt 0) { Write-BeyinText -Path $f -Text ([string]($n - 1)) }
        } | Out-Null
    } catch { }
}

function Test-BeyinBudget {
    # Gunluk 'claude -p' cagri butcesi. Asilirsa $false doner.
    #
    # KILITLI: onceki surum kilitsiz oku-degistir-yaz yapiyordu. Iki es zamanli
    # flush ayni $n'i okuyup ikisi de $n+1 yazarsa sayac EKSIK sayar. Butce
    # kullanicinin kendi kotasini koruyan bir emniyet tavani; eksik sayan bir
    # tavan 60'i asan cagriya izin verir. Kullanici 10+ paralel oturum
    # calistirdigi icin bu teorik degil.
    #
    # REZERV: flush ve compile ayni sayaci paylasir ama FARKLI tavan gorur
    # (flush 50, compile 60). Boylece hacim arttiginda flush havuzu tuketip
    # derleyiciyi ac birakamaz - derleyici gunde bir calisan, kavram notu
    # ureten tek mekanizma ve aclik SESSIZ olurdu.
    param([hashtable]$Paths, [int]$MaxPerDay = 50)

    $f = Join-Path $Paths.ScrState ("budget-{0}.txt" -f ((Get-Date).ToString('yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)))
    $lock = Join-Path $Paths.ScrState 'budget.lock'
    try {
        # DIKKAT: `& $Action` scriptblock'u ALT KAPSAMDA calisir. Icerideki
        # `$sonuc = $true` atamasi disariya YANSIMAZ (olculdu: 10 istekten
        # 0'i izin aldi, oysa tavan 5'ti). Bu yuzden karar scriptblock'un
        # DONUS DEGERI ile disari tasiniyor. Disaridan OKUMA calisir, sorun
        # yalniz ATAMADA.
        $sonuc = Invoke-BeyinWithLock -LockPath $lock -TimeoutSeconds 5 -Action {
            $n = 0
            if (Test-Path -LiteralPath $f) {
                $raw = (Get-Content -LiteralPath $f -Raw -ErrorAction SilentlyContinue)
                if ($raw) {
                    # BOM ACIKCA SOYULUYOR - davranis tesadufe birakilmiyor.
                    #
                    # Olculdu 2026-08-31: blocks-2026-08-29.txt UTF-8 BOM ile
                    # basliyordu (PS 5.1'de Set-Content -Encoding UTF8 BOM ekler;
                    # bu dosyaya bir test sirasinda oyle yazilmisti). TryParse yine
                    # de dogru okuyordu ama SANS ESERI: .NET Trim() U+FEFF'i bosluk
                    # sayiyor. Saymasaydi sayac 0'a duserdi ve iki sayac icin de
                    # sonucu agir olurdu:
                    #   blok sayaci   -> beklenen dusuk kalir, gunluk log butunlugu
                    #                    kontrolu KORLESIR (bu oturumda kapatilan
                    #                    arizanin aynisi, arka kapidan)
                    #   butce sayaci  -> gunluk tavan sifirlanir, kota asilabilir
                    $raw = $raw -replace ("^" + [char]0xFEFF), ''
                    [int]::TryParse($raw.Trim(), [ref]$n) | Out-Null
                }
            }
            if ($n -ge $MaxPerDay) { return $false }
            Write-BeyinText -Path $f -Text ([string]($n + 1))
            return $true
        }
        return [bool]$sonuc
    } catch {
        # Kilit alinamadi: MUHAFAZAKAR davran. Butceyi tuketilmis say ve isi
        # kuyruga birak - yanlis tarafa dusmek, kotayi asmaktan iyidir.
        Write-BeyinLog -Vault $Paths.Vault -Message 'butce kilidi alinamadi, is ertelendi'
        return $false
    }
}

function Add-BeyinCounter {
    # Kilitli sayac artirma (blok sayaci gibi). Kilitsiz artis kaybolursa
    # doktor'un "gunluk log butunlugu" kontrolu ($actual -ge $expected) HER
    # ZAMAN OK verir ve motor kaynakli kaybi hic yakalamaz.
    param([hashtable]$Paths, [string]$Name)
    $f = Join-Path $Paths.ScrState "$Name.txt"
    $lock = Join-Path $Paths.ScrState 'counter.lock'
    try {
        Invoke-BeyinWithLock -LockPath $lock -TimeoutSeconds 5 -Action {
            $n = 0
            if (Test-Path -LiteralPath $f) {
                $raw = (Get-Content -LiteralPath $f -Raw -ErrorAction SilentlyContinue)
                if ($raw) {
                    # BOM ACIKCA SOYULUYOR - davranis tesadufe birakilmiyor.
                    #
                    # Olculdu 2026-08-31: blocks-2026-08-29.txt UTF-8 BOM ile
                    # basliyordu (PS 5.1'de Set-Content -Encoding UTF8 BOM ekler;
                    # bu dosyaya bir test sirasinda oyle yazilmisti). TryParse yine
                    # de dogru okuyordu ama SANS ESERI: .NET Trim() U+FEFF'i bosluk
                    # sayiyor. Saymasaydi sayac 0'a duserdi ve iki sayac icin de
                    # sonucu agir olurdu:
                    #   blok sayaci   -> beklenen dusuk kalir, gunluk log butunlugu
                    #                    kontrolu KORLESIR (bu oturumda kapatilan
                    #                    arizanin aynisi, arka kapidan)
                    #   butce sayaci  -> gunluk tavan sifirlanir, kota asilabilir
                    $raw = $raw -replace ("^" + [char]0xFEFF), ''
                    [int]::TryParse($raw.Trim(), [ref]$n) | Out-Null
                }
            }
            Write-BeyinText -Path $f -Text ([string]($n + 1))
        }
    } catch {
        # SESSIZ OLAMAZ - ustteki yorum sonucu zaten yaziyor:
        # sayac artisi kaybolursa "gunluk log butunlugu" kontrolu
        # ($actual -ge $expected) HER ZAMAN OK verir.
        #
        # Yani bu catch, kaybi yakalamak icin var olan kontrolu tam olarak
        # kaybin oldugu anda devre disi birakiyordu. Sayac dusukse beklenen de
        # dusuk olur, bulunan her zaman beklenene esit ya da fazla cikar ve
        # doktor "saglikli" der. Kontrol yalan soylemez, KOR olur - ki daha
        # kotusudur, cunku kimse aramaz.
        #
        # (Ayni kontrolu bu oturumda gecmis gunlere de genislettim; o genisletme
        # de bu sayaca dayaniyor. Sessiz kalan bir sayac ikisini birden korlestirir.)
        #
        # Firlatmiyoruz: sayac artisi bir yan etki, cagiran akis (blok yazma)
        # bu yuzden durmamali. Ama iz birakiyor.
        $sebep = 'bilinmiyor'
        if ($_ -and $_.Exception) { $sebep = $_.Exception.Message }
        if ([string]::IsNullOrWhiteSpace($sebep)) { $sebep = "$_" }
        try {
            Write-BeyinLog -Vault $Paths.Vault -Message ("Add-BeyinCounter: '$Name' sayaci ARTIRILAMADI -> " +
                "gunluk log butunlugu kontrolu bu gun icin kor kaliyor | $sebep")
        } catch { }
    }
}

# ============================================================================
# IS KUYRUGU  -  temiz kapanmayan oturumlar kaybolmasin
# ----------------------------------------------------------------------------
# flush'in tek tetigi SessionEnd/PreCompact. Kullanici pane'i olduruyor, Ctrl+C
# ile cikiyor veya makine yeniden basliyorsa SessionEnd HIC atesmiyor ve o oturum
# hafizaya girmiyor. Ayrica slot/butce dolu oldugunda isi dusurmek de kayip olur.
# Cozum: isi kuyruga yaz, SessionStart bir sonraki acilista kuyrugu bosalt.
# ============================================================================

function Add-BeyinQueue {
    # AJAN ALANI: onceki surumde kuyruk ajan tasimiyordu, bu yuzden kuyruktan
    # gelen her is gunluk loga 'claude' olarak yaziliyordu - bir Codex oturumu
    # slot/butce yuzunden kuyruga dustugunde yanlis etiketleniyordu.
    param([hashtable]$Paths, [string]$TranscriptPath, [string]$Cwd, [string]$Reason,
          [string]$Agent = '')
    if (-not $TranscriptPath) { return }
    New-Item -ItemType Directory -Force -Path $Paths.Queue | Out-Null
    $f = Join-Path $Paths.Queue ((Get-BeyinKey -Text $TranscriptPath) + '.json')
    $json = @{ v = 2; transcript = $TranscriptPath; cwd = $Cwd; reason = $Reason
               agent = $Agent; ts = (Get-Date -Format 'o') } | ConvertTo-Json -Compress
    Write-BeyinText -Path $f -Text $json
}

function Get-BeyinQueue {
    param([hashtable]$Paths, [int]$Max = 5)
    if (-not (Test-Path -LiteralPath $Paths.Queue)) { return @() }
    $items = New-Object System.Collections.Generic.List[object]
    foreach ($f in @(Get-ChildItem -LiteralPath $Paths.Queue -Filter '*.json' -File -ErrorAction SilentlyContinue |
                     Sort-Object LastWriteTime | Select-Object -First $Max)) {
        try {
            $o = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            # v1 kuyruk dosyalarinda 'agent' alani yok -> bos kalir, cagiran
            # biciminden turetir (geriye uyumlu).
            $ag = ''
            if ($o.PSObject.Properties['agent'] -and $o.agent) { $ag = [string]$o.agent }
            $items.Add([pscustomobject]@{
                File       = $f.FullName
                Transcript = [string]$o.transcript
                Cwd        = [string]$o.cwd
                Reason     = [string]$o.reason
                Agent      = $ag
            })
        } catch { Remove-Item -LiteralPath $f.FullName -Force -ErrorAction SilentlyContinue }
    }
    # DIKKAT: @($items) KULLANMA. Bu PowerShell 5.1 derlemesinde
    # List[object] uzerinde array-subexpression "Argument types do not match"
    # firlatiyor (List[string] ve List[psobject] sorunsuz, List[object] degil).
    # Olculdu: toparlama her SessionStart'ta bu yuzden sessizce dusuyordu.
    return $items.ToArray()
}

function Remove-BeyinQueueItem {
    param([string]$File)
    Remove-Item -LiteralPath $File -Force -ErrorAction SilentlyContinue
}

# ============================================================================
# ALT SUREC BASLATMA  (flush / compile)
# ----------------------------------------------------------------------------
# Iki hata burada tek yerde cozuluyor:
#
#   a) -WorkingDirectory VERILMEDIGINDE cocuk surec kancanin cwd'sini, yani
#      KULLANICININ O ANKI PROJE KLASORUNU miras aliyordu. flush icindeki
#      'claude -p' orada calisip o projenin CLAUDE.md/MCP/skill yapilandirmasini
#      yukluyordu -- transkript etrafina cizdigimiz veri sinirini tamamen
#      atlayan bir talimat kanali. (Invoke-BeyinClaude ayrica kendi notr
#      cwd'sini kuruyor; bu ikinci savunma.)
#
#   b) Elle quoting: CommandLineToArgvW kurallarinda kapanis alintisinin hemen
#      onundeki ters-slash o alintiyi KACISLAR. Deger ters-slash ile bitiyorsa
#      (surucu koku: 'D:\') arguman parcalaniyordu. Olculdu: -ProjectPath "C:\"
#      cocukta 'C:"' olarak geliyordu. TrimEnd ile normalize ediliyor.
# ============================================================================

function Start-BeyinScript {
    param(
        [Parameter(Mandatory = $true)][string]$ScriptPath,
        [Parameter(Mandatory = $true)][string]$Vault,
        [hashtable]$Params = @{}
    )
    if (-not (Test-Path -LiteralPath $ScriptPath)) { return $false }

    $argList = New-Object System.Collections.Generic.List[string]
    $argList.Add('-NoProfile'); $argList.Add('-ExecutionPolicy'); $argList.Add('Bypass')
    $argList.Add('-File'); $argList.Add('"' + $ScriptPath.TrimEnd('\') + '"')
    foreach ($k in $Params.Keys) {
        $v = [string]$Params[$k]
        $argList.Add('-' + $k)
        # Sondaki ters-slash kapanis alintisini kacislar -> normalize et
        $argList.Add('"' + ($v -replace '\\+$', '') + '"')
    }
    try {
        Start-Process -FilePath 'powershell.exe' -ArgumentList $argList.ToArray() `
            -WorkingDirectory $Vault -WindowStyle Hidden | Out-Null
        return $true
    } catch {
        Write-BeyinLog -Vault $Vault -Message "alt surec baslatilamadi ($(Split-Path -Leaf $ScriptPath)): $($_.Exception.Message)"
        return $false
    }
}

# ============================================================================
# MERKEZI 'claude -p' CAGRISI
# ----------------------------------------------------------------------------
# Onceki surumde 'Get-Content | & $claude -p' seklinde dogrudan pipe vardi. Uc
# ciddi sorunu vardi:
#
#   a) Cocuk surec KANCANIN cwd'sini miras aliyordu, yani KULLANICININ O ANKI
#      PROJE KLASORUNU. Ozetleyici o projenin CLAUDE.md'sini, MCP sunucularini
#      ve skill'lerini yukluyordu. Bu, transkript etrafina cizdigimiz
#      <<<TRANSKRIPT>>> veri sinirini TAMAMEN ATLAYAN bir talimat kanali; ayrica
#      her ozette o projenin MCP sunucularini ayaga kaldirmak demek.
#   b) Zaman asimi YOKTU. Rate limit'te takilan gizli surec sonsuza kadar yasiyordu.
#      Cikis kodu ve stderr de hic okunmuyordu, yani "model bos dedi" ile
#      "model cevap vermedi" ayirt edilemiyordu -> derleyici basarisizligi
#      basari sayip gunu kalici olarak 'derlendi' isaretliyordu.
#   c) Encoding: bkz. dosya basi. Turkce '?' oluyordu.
#
# Bu fonksiyon ucunu birden kapatir ve @{ Ok; Out; Err; ExitCode; Reason } doner.
# ============================================================================

# ============================================================================
# OZETLEYICI IKI AJANLI  (2026-09-15, Faz 0.4 / 0.5)
# ----------------------------------------------------------------------------
# Motor iki ajanin oturumunu okuyordu ama OZETLEMEYI yalnizca 'claude -p'
# yapiyordu: Codex-only bir makinede kancalar calisir, kuyruk buyur, hicbir
# gunluk log yazilmaz. Simetri icin ikinci arka uc: 'codex exec'.
#
# Secim: $script:BeyinOzetleyici = 'auto' | 'claude' | 'codex'
#   auto   -> claude varsa claude, yoksa codex
#   BEYIN_OZETLEYICI ortam degiskeni bu degeri ezer (doktor -Derin iki arka ucu
#   ayri ayri sinamak icin bunu kullanir).
# ============================================================================
$script:BeyinOzetleyici = (Get-BeyinAyar 'BEYIN_OZETLEYICI' (Get-BeyinAyarVars 'BEYIN_OZETLEYICI')).ToLowerInvariant()
$script:BeyinCodexModel = Get-BeyinAyar 'BEYIN_CODEX_MODEL' (Get-BeyinAyarVars 'BEYIN_CODEX_MODEL')   # bos = codex varsayilani

function Get-BeyinCodexExe {
    # codex npm ile gelir: 'codex.cmd' shim + posix 'codex'. CreateProcess bir
    # .cmd dosyasini dogrudan calistiramaz; cmd.exe uzerinden gidilir. Bu
    # fonksiyon shim'in TAM yolunu doner ($null = yok).
    foreach ($ad in @('codex.cmd', 'codex.exe', 'codex')) {
        $c = Get-Command $ad -ErrorAction SilentlyContinue
        if ($c -and $c.Source -and (Test-Path -LiteralPath $c.Source)) { return [string]$c.Source }
    }
    return $null
}

function Get-BeyinNotrCwd {
    # Vault DISINDA, bos, yazilabilir bir calisma dizini (Invoke-BeyinClaude ile
    # ayni gerekce: hicbir projenin AGENTS.md/CLAUDE.md/MCP'sini miras alma).
    param([hashtable]$Paths)
    $tamVault = $null
    try { $tamVault = [System.IO.Path]::GetFullPath($Paths.Vault).TrimEnd('\', '/') } catch { }
    foreach ($kok in @($env:LOCALAPPDATA, [System.IO.Path]::GetTempPath())) {
        if ([string]::IsNullOrWhiteSpace($kok)) { continue }
        try {
            $aday = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($kok, 'beyin-engine-cwd'))
            if ($tamVault -and ($aday.TrimEnd('\','/').Equals($tamVault, [StringComparison]::OrdinalIgnoreCase) -or
                                $aday.StartsWith($tamVault + [System.IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase))) { continue }
            New-Item -ItemType Directory -Force -Path $aday -ErrorAction Stop | Out-Null
            return $aday
        } catch { continue }
    }
    return $null
}

function Invoke-BeyinCodex {
    # Invoke-BeyinClaude'un birebir aynasi. Ayni donus sekli:
    #   @{ Ok; Out; Err; ExitCode; Reason }
    # Farklar: 'codex exec' (etkilesimsiz), sandbox read-only, git-disi klasor
    # izni, son mesaj DOSYAYA yazdirilir (-o) - stdout olay/toplam satirlariyla
    # kirli oldugu icin.
    param(
        [Parameter(Mandatory = $true)][string]$Prompt,
        [Parameter(Mandatory = $true)][hashtable]$Paths,
        [string]$Model = '',
        [int]$TimeoutSeconds = 240
    )
    $codex = Get-BeyinCodexExe
    if (-not $codex) { return @{ Ok = $false; Out = ''; Err = ''; ExitCode = -1; Reason = 'cli-yok' } }
    $cwd = Get-BeyinNotrCwd -Paths $Paths
    if (-not $cwd) { return @{ Ok = $false; Out = ''; Err = 'notr calisma dizini yok'; ExitCode = -3; Reason = 'cwd-yok' } }

    $sonMesaj = [System.IO.Path]::Combine($cwd, 'codex-son-' + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.txt')
    $arg = 'exec -s read-only --skip-git-repo-check --color never -o "' + $sonMesaj + '"'
    if ($Model) { $arg += ' -m ' + $Model }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    if ($codex.ToLowerInvariant().EndsWith('.exe')) {
        $psi.FileName = $codex; $psi.Arguments = $arg
    } else {
        # .cmd shim: cmd.exe /d /s /c "<shim> <args>"
        $psi.FileName = [System.IO.Path]::Combine($env:SystemRoot, 'System32', 'cmd.exe')
        $psi.Arguments = '/d /s /c ""' + $codex + '" ' + $arg + '"'
    }
    $psi.WorkingDirectory       = $cwd
    $psi.UseShellExecute        = $false
    $psi.CreateNoWindow         = $true
    $psi.RedirectStandardInput  = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.StandardOutputEncoding = New-Object System.Text.UTF8Encoding($false)
    $psi.StandardErrorEncoding  = New-Object System.Text.UTF8Encoding($false)
    $psi.EnvironmentVariables['BEYIN_CHILD'] = '1'   # beyin kancalari alt surecte calismasin (olculdu: 26k token yakiyordu)
    $psi.EnvironmentVariables['AGENTCHEF_ROUTING_HINT'] = 'off'   # AgentChef yonlendirme satiri motorun kendi model cagrilarinda gereksiz
    $proc = $null
    try {
        $proc = [System.Diagnostics.Process]::Start($psi)
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Prompt)
        $proc.StandardInput.BaseStream.Write($bytes, 0, $bytes.Length)
        $proc.StandardInput.BaseStream.Flush()
        $proc.StandardInput.Close()
        $tOut = $proc.StandardOutput.ReadToEndAsync()
        $tErr = $proc.StandardError.ReadToEndAsync()
        if (-not $proc.WaitForExit($TimeoutSeconds * 1000)) {
            # AGACI OLDUR (2026-09-16, denetim): .cmd simi cmd.exe ile basladigi icin
            # $proc.Kill() yalniz sarmalayiciyi olduruyor, codex/node torunu yasamaya
            # devam ediyordu (olculdu). taskkill /T tum agaci kapatir.
            Stop-BeyinProcessTree -ProcessId $proc.Id
            $kErr = ''; try { if ($tErr.Wait(1000)) { $kErr = $tErr.Result } } catch { }
            try { [void]$tOut.Wait(500) } catch { }
            Write-BeyinLog -Vault $Paths.Vault -Message "codex: zaman asimi (${TimeoutSeconds}sn), surec agaci olduruldu (pid=$($proc.Id))"
            return @{ Ok = $false; Out = ''; Err = $kErr; ExitCode = -2; Reason = "zaman-asimi ${TimeoutSeconds}sn" }
        }
        $proc.WaitForExit()
        $out = ''; $err = ''
        try { $out = $tOut.Result } catch { }
        try { $err = $tErr.Result } catch { }
        $code = $proc.ExitCode
        # Son mesaj dosyasi varsa o kazanir (temiz); yoksa stdout'a dus.
        $son = ''
        try { if (Test-Path -LiteralPath $sonMesaj) { $son = [System.IO.File]::ReadAllText($sonMesaj, (New-Object System.Text.UTF8Encoding($false))) } } catch { }
        if ($code -ne 0) { return @{ Ok = $false; Out = $out; Err = $err; ExitCode = $code; Reason = 'cikis-kodu' } }
        $metin = if (-not [string]::IsNullOrWhiteSpace($son)) { $son } else { $out }
        if ([string]::IsNullOrWhiteSpace($metin)) { return @{ Ok = $false; Out = ''; Err = $err; ExitCode = 0; Reason = 'bos-yanit' } }
        return @{ Ok = $true; Out = $metin.Trim(); Err = $err; ExitCode = 0; Reason = 'ok' }
    } catch {
        return @{ Ok = $false; Out = ''; Err = $_.Exception.Message; ExitCode = -3; Reason = 'istisna' }
    } finally {
        if ($proc) { try { $proc.Dispose() } catch { } }
        try { if (Test-Path -LiteralPath $sonMesaj) { Remove-Item -LiteralPath $sonMesaj -Force -ErrorAction SilentlyContinue } } catch { }
    }
}

function Stop-BeyinProcessTree {
    # Bir surec ve TUM torunlari (cmd.exe simi -> codex -> node). taskkill /T /F.
    param([int]$ProcessId)
    if ($ProcessId -le 0) { return }
    try { & (Join-Path $env:SystemRoot 'System32\taskkill.exe') /PID $ProcessId /T /F 2>$null | Out-Null } catch { }
    try { $pr = [System.Diagnostics.Process]::GetProcessById($ProcessId); if ($pr -and -not $pr.HasExited) { $pr.Kill() } } catch { }
}

function Get-BeyinModelBackend {
    # Hangi arka uc kullanilacak. 'claude' | 'codex' | '' (hicbiri).
    $sec = $script:BeyinOzetleyici
    $cl = [bool](Get-BeyinClaudeExe)
    $cx = [bool](Get-BeyinCodexExe)
    switch ($sec) {
        'claude' { if ($cl) { return 'claude' } else { return '' } }
        'codex'  { if ($cx) { return 'codex' }  else { return '' } }
        default  { if ($cl) { return 'claude' } elseif ($cx) { return 'codex' } else { return '' } }
    }
}

function Invoke-BeyinModel {
    # TEK GIRIS NOKTASI. Cagiranlar arka ucu bilmez; donen hashtable'da
    # Backend alani vardir (makbuz ve log icin).
    param(
        [Parameter(Mandatory = $true)][string]$Prompt,
        [Parameter(Mandatory = $true)][hashtable]$Paths,
        [string]$Model = 'haiku',
        [int]$TimeoutSeconds = 240
    )
    $b = Get-BeyinModelBackend
    if ($b -eq 'claude') {
        $r = Invoke-BeyinClaude -Prompt $Prompt -Paths $Paths -Model $Model -TimeoutSeconds $TimeoutSeconds
    } elseif ($b -eq 'codex') {
        $r = Invoke-BeyinCodex -Prompt $Prompt -Paths $Paths -Model $script:BeyinCodexModel -TimeoutSeconds $TimeoutSeconds
    } else {
        $r = @{ Ok = $false; Out = ''; Err = ''; ExitCode = -1; Reason = 'cli-yok' }
    }
    $r['Backend'] = $(if ($b) { $b } else { 'yok' })
    return $r
}

function Test-BeyinModelAuth {
    # Butce HARCAMADAN oturum kontrolu. Zamanlayici (Faz 5) bunu kullanir.
    #   claude auth status  -> JSON, loggedIn (dogrulandi)
    #   codex login status  -> "Logged in ..." (dogrulandi)
    # Donus: @{ Ok; Kesin; Backend; Detay }
    #
    # KESIN ALANI NEDEN VAR (2026-09-18, ilk gercek gece kosusunda olculdu):
    # eskiden zaman asimi da Ok=$false donuyordu ve cagiran taraf bunu
    # 'kimlik yok' diye raporluyordu. Gece gorevlerinden 'derle' (03:00) ve
    # 'topla-uygula' (03:20) tam olarak boyle dustu: oturum ACIKTI, kontrol
    # soguk baslangicta 20 sn tavanini asmisti. Kullaniciya 'yeniden oturum
    # ac' deniyordu ve gece derlemesi sessizce hic calismiyordu.
    #
    #   Ok=$true,  Kesin=$true   oturum acik
    #   Ok=$false, Kesin=$true   oturum GERCEKTEN yok (CLI yok / loggedIn=false)
    #   Ok=$false, Kesin=$false  KONTROL SONUCLANMADI (zaman asimi, hata,
    #                            ayristirilamayan cikti) - cagiran taraf buna
    #                            'kimlik yok' muamelesi YAPMAMALI.
    param([int]$TimeoutSeconds = 20)
    $b = Get-BeyinModelBackend
    if (-not $b) { return @{ Ok = $false; Kesin = $true; Backend = 'yok'; Detay = 'ne claude ne codex CLI var' } }
    try {
        if ($b -eq 'claude') {
            $exe = Get-BeyinClaudeExe
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = $exe; $psi.Arguments = 'auth status'
        } else {
            $exe = Get-BeyinCodexExe
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            if ($exe.ToLowerInvariant().EndsWith('.exe')) { $psi.FileName = $exe; $psi.Arguments = 'login status' }
            else { $psi.FileName = [System.IO.Path]::Combine($env:SystemRoot, 'System32', 'cmd.exe'); $psi.Arguments = '/d /s /c ""' + $exe + '" login status"' }
        }
        $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
        $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
        $psi.EnvironmentVariables['BEYIN_CHILD'] = '1'
        $psi.EnvironmentVariables['AGENTCHEF_ROUTING_HINT'] = 'off'   # AgentChef yonlendirme satiri motorun kendi model cagrilarinda gereksiz
        $proc = [System.Diagnostics.Process]::Start($psi)
        $tOut = $proc.StandardOutput.ReadToEndAsync(); $tErr = $proc.StandardError.ReadToEndAsync()
        if (-not $proc.WaitForExit($TimeoutSeconds * 1000)) { Stop-BeyinProcessTree -ProcessId $proc.Id; return @{ Ok = $false; Kesin = $false; Backend = $b; Detay = 'zaman asimi (kontrol sonuclanmadi)' } }
        $out = ''; try { $out = $tOut.Result } catch { }
        $err = ''; try { $err = $tErr.Result } catch { }
        $metin = $out + ' ' + $err
        if ($b -eq 'claude') {
            $ok = [regex]::IsMatch($metin, '"loggedIn"\s*:\s*true', $script:BeyinRxCI)
            # Ciktida loggedIn alani HIC yoksa karar verilemez: 'false' gormek
            # ile 'hic gormemek' ayni sey degil (CLI cikti bicimi degismis olabilir).
            $kesin = [regex]::IsMatch($metin, '"loggedIn"', $script:BeyinRxCI)
            return @{ Ok = $ok; Kesin = $kesin; Backend = 'claude'; Detay = $(if ($ok) { 'oturum acik' } else { 'oturum yok (claude auth status loggedIn=false)' }) }
        } else {
            $ok = [regex]::IsMatch($metin, 'logged in', $script:BeyinRxCI) -and -not [regex]::IsMatch($metin, 'not logged in', $script:BeyinRxCI)
            $kesin = [regex]::IsMatch($metin, 'logged in', $script:BeyinRxCI)
            return @{ Ok = $ok; Kesin = $kesin; Backend = 'codex'; Detay = $(if ($ok) { 'oturum acik' } else { 'oturum yok (codex login status)' }) }
        }
    } catch { return @{ Ok = $false; Kesin = $false; Backend = $b; Detay = "kontrol hatasi: $($_.Exception.Message)" } }
}

function Get-BeyinFailDetail {
    # Bir basarisiz Invoke-BeyinClaude sonucundan LOGA YAZILABILIR tek satirlik
    # sebep uretir.
    #
    # NEDEN VAR (olculdu 2026-08-30): engine.log dolusu
    #   "flush: BASARISIZ (cikis-kodu, exit=1) - is kuyruga alindi"
    # satiri vardi ve HICBIRI nedenini soylemiyordu. Cagiranlar yalnizca
    # $res.Err'i logluyordu; oysa 'claude -p' basarisiz oldugunda mesaji
    # cogu zaman STDOUT'a yaziyor ve stderr bos kaliyor. Yani teshis bilgisi
    # yakalaniyor, hashtable'da duruyor ve sonra ATILIYORDU.
    #
    # Sonuc: kuyruk 23 ogeye ciktigi halde kimse sebebini goremiyordu.
    # [KIMLIK] (2026-09-15, Faz 0.5): oturum yoksa cagri hizmet ALMADI - butce
    # geri verilir (Restore-BeyinBudget) ve zamanlayici "kimlik gecersiz" der.
    param([hashtable]$Result, [int]$MaxLen = 300)
    $__metin = (([string]$Result.Err) + ' ' + ([string]$Result.Out))
    if ([regex]::IsMatch($__metin, 'not logged in|please run /login|please log in|authentication|unauthori[sz]ed|invalid api key|login status', $script:BeyinRxCI)) {
        return ' [KIMLIK] oturum yok / kimlik gecersiz - yeniden denemekle gecmez, giris yap'
    }

    # IKI AKIS BIRLIKTE (2026-10-06): eskiden stdout'a yalniz stderr BOSKEN
    # bakiliyordu. CLI stderr'e bir UYARI bastiginda (taninmayan arac adi gibi) asil
    # mesaj stdout'ta kalip atiliyordu ve asagidaki KOTA etiketi yalniz gorunen
    # parcaya bakildigi icin eslesmiyordu (36 limit hatasi 'cikis-kodu' sayildi,
    # bkz. Get-BeyinClaudeArgs). Simdi siniflama BIRLESIK metinde; gosterimde iki
    # akis da var, sinyal tasiyan akis once gelir ki kesmede kaybolmasin.
    $errT = (([string]$Result.Err) -replace '\s+', ' ').Trim()
    $outT = (([string]$Result.Out) -replace '\s+', ' ').Trim()
    if (-not $errT -and -not $outT) { return ' | (cikti yok)' }

    # Kota/limit basarisizligini AYRI etiketle: bu, yeniden denemekle gecmez.
    # Motor duvara vurup vurmadigini boyle ayirt eder.
    # DESENLER RESMI HATA DIZELERINDEN TURETILDI (code.claude.com/docs/en/errors,
    # kontrol 2026-08-31). Onceki liste TAHMINE dayaniyordu ve olculdu ki alti
    # resmi dizeden BESINI kaciriyordu:
    #     "You've hit your session limit"   -> kaciriyordu
    #     "You've hit your weekly limit"    -> kaciriyordu
    #     "You've hit your Opus limit"      -> kaciriyordu
    #     "Credit balance is too low"       -> kaciriyordu
    #     "spend limit reached"             -> kaciriyordu
    #     "rate limit exceeded"             -> yakaliyordu
    #
    # Bu ayrimin onemi: motor "tekrar denemek ISE YARAMAZ" (kota) ile "yarayabilir"
    # (gecici hata) arasinda karar veriyor. Kota hatasi genel hata sanilirsa is
    # kuyrukta bosuna donup spawn slotu yakar.
    #
    # Resmi belge ayrica sunu soyluyor: cikis kodlari hata TURUNU ayirt ETMIYOR,
    # stderr ayiklamak gerekiyor. Yani buradaki yaklasim dogru, eksik olan
    # yalnizca dize listesiydi.
    # tr-TR: '(?i)' -match buyuk 'I' iceren mesajlari kacirir (RATE LIMIT). Test-BeyinMatch kultur-bagimsiz.
    $kotaRx = 'usage limit|rate limit|quota|too many requests|429|overloaded|hit your [a-z]* ?limit|credit balance is too low|spend limit'
    $kota = Test-BeyinMatch -Text $__metin -Pattern $kotaRx
    $parts = New-Object System.Collections.Generic.List[string]
    if ($errT) { $parts.Add('stderr: ' + $errT) }
    if ($outT) {
        if ($kota -and $errT -and -not (Test-BeyinMatch -Text $errT -Pattern $kotaRx)) { $parts.Insert(0, 'stdout: ' + $outT) }
        else { $parts.Add('stdout: ' + $outT) }
    }
    $onEk = $(if ($kota) { '[KOTA/LIMIT] ' } else { '' })
    if ($parts.Count -eq 2) {
        $yer = [math]::Max(2, $MaxLen - $onEk.Length - 3)
        $a = $parts[0]; $b = $parts[1]
        if ($a.Length + $b.Length -gt $yer) {
            $yari = [int][math]::Floor($yer / 2)
            if ($a.Length -le $yari) { $b = $b.Substring(0, [math]::Max(0, $yer - $a.Length)) }
            elseif ($b.Length -le $yari) { $a = $a.Substring(0, [math]::Max(0, $yer - $b.Length)) }
            else { $a = $a.Substring(0, $yari); $b = $b.Substring(0, $yer - $yari) }
        }
        $d = $a + ' ; ' + $b
    } else { $d = $parts[0] }
    $d = $onEk + $d
    if ($d.Length -gt $MaxLen) { $d = $d.Substring(0, $MaxLen) }
    return ' | ' + $d
}

# MODEL LIMITI ERTELEME (2026-10-06, AgentSpace limitDetect/resumeDaemon dersi).
# Limit mesajindan 'ne zaman tekrar denenir' cikarilir; o saate kadar ozetleyici
# denenmez (is kuyrukta bekler, butce yakilmaz). Ilk basarili flush/compile
# kaydi temizler. Bulunamazsa +60 dk; tavan +24 saat.
function Get-BeyinLimitReset {
    param([string]$Text, [datetime]$Simdi = (Get-Date))
    $r = @{ Ok = $false; Until = $Simdi.AddMinutes(60); Kaynak = 'varsayilan-60dk' }
    if ([string]::IsNullOrWhiteSpace($Text)) { return $r }
    $t = [string]$Text
    $inv = [Globalization.CultureInfo]::InvariantCulture
    try {
        # 1) Goreli: 'try again in 2 hours', 'resets in 45 minutes', 'retry after 120 seconds', 'Retry-After: 120'
        $m = [regex]::Match($t, '(?i)(?:try again|retry|resets?|available)\s+(?:in|after)\s+(\d+)\s*(hours?|hrs?|h|minutes?|mins?|m|seconds?|secs?|s)\b')
        if ($m.Success) {
            $n = [double]$m.Groups[1].Value; $birim = $m.Groups[2].Value.ToLowerInvariant()
            $dk = $(if ($birim.StartsWith('h')) { $n * 60 } elseif ($birim.StartsWith('m')) { $n } else { $n / 60.0 })
            $r.Until = $Simdi.AddMinutes([math]::Max(1, $dk)); $r.Ok = $true; $r.Kaynak = 'goreli'
        }
        if (-not $r.Ok) {
            $m = [regex]::Match($t, '(?i)retry-after\s*[:=]\s*(\d+)')
            if ($m.Success) { $r.Until = $Simdi.AddSeconds([math]::Max(60, [double]$m.Groups[1].Value)); $r.Ok = $true; $r.Kaynak = 'retry-after' }
        }
        # 2) Epoch: Codex rate_limits 'resets_at': 1791234567
        if (-not $r.Ok) {
            $m = [regex]::Match($t, '(?i)resets?_?at"?\s*[:=]\s*(\d{10})\b')
            if ($m.Success) { $r.Until = [DateTimeOffset]::FromUnixTimeSeconds([int64]$m.Groups[1].Value).LocalDateTime; $r.Ok = $true; $r.Kaynak = 'epoch' }
        }
        # 3) ISO-8601 zaman damgasi
        if (-not $r.Ok) {
            $m = [regex]::Match($t, '\b(20\d{2}-\d{2}-\d{2}T\d{2}:\d{2}(?::\d{2}(?:\.\d+)?)?(?:Z|[+-]\d{2}:?\d{2}))')
            if ($m.Success) { $r.Until = ([DateTimeOffset]::Parse($m.Groups[1].Value, $inv)).LocalDateTime; $r.Ok = $true; $r.Kaynak = 'iso' }
        }
        # 4a) Tarih + saat (2026-10-06): haftalik limit 'resets Sep 28, 4am' (yerel; gecmisse gelecek yil).
        # Eskiden saat dali 'resets Sep' gorup eslesmiyor, +60 dk varsayilana dusuyordu.
        if (-not $r.Ok) {
            $m = [regex]::Match($t, '(?i)\bresets?\s+(?:at\s+|on\s+)?(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\.?\s+(\d{1,2}),?\s+(?:at\s+)?(\d{1,2})(?::(\d{2}))?\s*(am|pm)\b')
            if ($m.Success) {
                $ay = [array]::IndexOf([string[]]@('jan','feb','mar','apr','may','jun','jul','aug','sep','oct','nov','dec'), $m.Groups[1].Value.ToLowerInvariant()) + 1
                $gun = [int]$m.Groups[2].Value; $sa = [int]$m.Groups[3].Value
                $dkk = $(if ($m.Groups[4].Value) { [int]$m.Groups[4].Value } else { 0 })
                $ap = $m.Groups[5].Value.ToLowerInvariant()
                if ($ap -eq 'pm' -and $sa -lt 12) { $sa += 12 } elseif ($ap -eq 'am' -and $sa -eq 12) { $sa = 0 }
                if ($ay -ge 1 -and $gun -ge 1 -and $gun -le [DateTime]::DaysInMonth($Simdi.Year, $ay) -and $sa -le 23 -and $dkk -le 59) {
                    $hedef = New-Object DateTime($Simdi.Year, $ay, $gun, $sa, $dkk, 0)
                    if ($hedef -le $Simdi) { $hedef = $hedef.AddYears(1) }
                    $r.Until = $hedef; $r.Ok = $true; $r.Kaynak = 'tarih'
                }
            }
        }
        # 4) Saat: 'resets at 3pm', 'resets 3:30 PM', 'reset at 15:00' (yerel saat; gecmisse yarin)
        if (-not $r.Ok) {
            $m = [regex]::Match($t, '(?i)\bresets?\s+(?:at\s+)?(\d{1,2})(?::(\d{2}))?\s*(am|pm)\b')
            if (-not $m.Success) { $m = [regex]::Match($t, '(?i)\bresets?\s+(?:at\s+)?(\d{1,2}):(\d{2})()\b') }
            if ($m.Success) {
                $sa = [int]$m.Groups[1].Value
                $dkk = $(if ($m.Groups[2].Value) { [int]$m.Groups[2].Value } else { 0 })
                $ap = $m.Groups[3].Value.ToLowerInvariant()
                if ($ap -eq 'pm' -and $sa -lt 12) { $sa += 12 } elseif ($ap -eq 'am' -and $sa -eq 12) { $sa = 0 }
                if ($sa -le 23 -and $dkk -le 59) {
                    $hedef = $Simdi.Date.AddHours($sa).AddMinutes($dkk)
                    if ($hedef -le $Simdi) { $hedef = $hedef.AddDays(1) }
                    $r.Until = $hedef; $r.Ok = $true; $r.Kaynak = 'saat'
                }
            }
        }
    } catch { }
    if ($r.Until -gt $Simdi.AddHours(24)) { $r.Until = $Simdi.AddHours(24) }
    if ($r.Until -lt $Simdi.AddMinutes(1)) { $r.Until = $Simdi.AddMinutes(1) }
    return $r
}

function Set-BeyinLimitErtele {
    param([hashtable]$Paths, [datetime]$Until, [string]$Kaynak = '', [string]$Backend = '', [string]$Ornek = '')
    try {
        $inv = [Globalization.CultureInfo]::InvariantCulture
        $ornekM = ''
        if ($Ornek) {
            $pr = Protect-BeyinSecrets -Text $Ornek -Vault $Paths.Vault
            if ([int]$pr.Failed -eq 0) { $ornekM = [string]$pr.Text; if ($ornekM.Length -gt 120) { $ornekM = $ornekM.Substring(0, 120) } }
        }
        $o = [ordered]@{ v = 1; until = $Until.ToString('o', $inv); kaynak = $Kaynak; backend = $Backend; ts = (Get-Date).ToString('o', $inv); ornek = $ornekM }
        Write-BeyinText -Path (Join-Path $Paths.ScrState 'limit-ertele.json') -Text (ConvertTo-Json -InputObject $o -Compress)
        return $true
    } catch { return $false }
}

function Test-BeyinLimitErtele {
    param([hashtable]$Paths)
    $r = @{ Aktif = $false; Until = $null; Kaynak = '' }
    try {
        $f = Join-Path $Paths.ScrState 'limit-ertele.json'
        if (-not (Test-Path -LiteralPath $f)) { return $r }
        $o = Get-Content -LiteralPath $f -Raw -Encoding UTF8 | ConvertFrom-Json
        $u = [datetime]::Parse([string]$o.until, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind)
        if ($u.Kind -eq [DateTimeKind]::Utc) { $u = $u.ToLocalTime() }
        if ($u -gt (Get-Date)) { $r.Aktif = $true; $r.Until = $u; $r.Kaynak = [string]$o.kaynak }
    } catch { }
    return $r
}

function Clear-BeyinLimitErtele {
    param([hashtable]$Paths)
    try { $f = Join-Path $Paths.ScrState 'limit-ertele.json'; if (Test-Path -LiteralPath $f) { [IO.File]::Delete($f) } } catch { }
}

# ============================================================================
# MALIYET OLCUMU (2026-10-06, AgentSpace token cost dersi; BB1)
# ----------------------------------------------------------------------------
# Kaynak: Claude Code transkriptindeki assistant satirlarinin message.usage alani
# (ayni yanit birden cok satira bolunur, message.id ile TEKILLESTIRILIR) ve Codex
# rollout'undaki token_count olayinin KUMULATIF total_token_usage alani (son deger
# eksi onceki olcum). Ikisi de RESMI OLMAYAN bicimlerdir: beklenen alan yoksa satir
# 'taninmayan' sayilir, tahmin uretilmez. Dolar degeri API ESDEGERIDIR (fiyat.json).
# ============================================================================
$script:BeyinFiyatOnbellek = $null

function Get-BeyinFiyatTablosu {
    param([hashtable]$Paths)
    if ($script:BeyinFiyatOnbellek) { return $script:BeyinFiyatOnbellek }
    $r = @{ Ok = $false; Tarih = ''; Modeller = @(); Hata = '' }
    try {
        $f = Join-Path $Paths.Vault 'motor\scripts\fiyat.json'
        $o = Get-Content -LiteralPath $f -Raw -Encoding UTF8 | ConvertFrom-Json
        $r.Tarih = [string]$o.tarih
        # Uzun onek once: 'claude-opus-5-5' 'claude-opus-5'ten once eslesmeli.
        $r.Modeller = @($o.modeller | Sort-Object { ([string]$_.onek).Length } -Descending)
        $r.Ok = ($r.Modeller.Count -gt 0)
    } catch { $r.Hata = $_.Exception.Message }
    $script:BeyinFiyatOnbellek = $r
    return $r
}

function Get-BeyinUsdTahmini {
    # $null = bu model icin fiyat yok (Codex/bilinmeyen). Jeton alanlari:
    # In (onbelleksiz girdi), Out, Cw5, Cw1h (onbellek yazma), Cr (onbellek okuma).
    param($Tablo, [string]$Model, [double]$In, [double]$Out, [double]$Cw5, [double]$Cw1h, [double]$Cr, [bool]$Fast = $false)
    if (-not $Tablo -or -not $Tablo.Ok -or -not $Model) { return $null }
    $m = $null
    foreach ($x in $Tablo.Modeller) { if ($Model.StartsWith([string]$x.onek, [StringComparison]::OrdinalIgnoreCase)) { $m = $x; break } }
    if (-not $m) { return $null }
    $g = [double]$m.girdi
    $usd = ($In * $g + $Out * [double]$m.cikti + $Cw5 * $g * 1.25 + $Cw1h * $g * 2.0 + $Cr * [double]$m.okuma) / 1000000.0
    if ($Fast -and $m.hizliCarpan) { $usd *= [double]$m.hizliCarpan }
    return $usd
}

function Measure-BeyinTranscriptUsage {
    # Bir transkriptin $Offset'ten sonrasini okur. Doner:
    #   Ok, Offset (son TAM satirin sonu), SonId, Kayitlar (claude), Taninmayan,
    #   CodexToplam @{In;Cr;Out} + CodexTs + Model (codex), Cwd, SessionId.
    # Claude: yalniz '"usage"' iceren assistant satirlari ayristirilir (ConvertFrom-Json
    # YOK; 2 GB'lik ilk tarama icin satir basina regex). Codex: kumulatif sayac
    # oldugu icin dosyanin yalniz SONU okunur (once 2 MB, bulunamazsa 8 MB).
    param([string]$Path, [string]$Agent, [long]$Offset = 0, [string]$SonId = '')
    $r = @{ Ok = $false; Offset = $Offset; SonId = $SonId; Kayitlar = (New-Object System.Collections.Generic.List[object])
            Taninmayan = 0; CodexToplam = $null; CodexTs = ''; Model = ''; Cwd = ''; SessionId = ''; Hata = '' }
    $fs = $null
    try {
        $fs = New-Object System.IO.FileStream($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
        $boy = $fs.Length
        if ($boy -lt $Offset) { $Offset = 0; $r.SonId = '' }   # dosya kisaldi/yeniden yazildi
        $utf8 = New-Object System.Text.UTF8Encoding($false)
        if ($Agent -eq 'codex') {
            if ($Offset -eq 0) {
                $bas = New-Object byte[] ([int][math]::Min(262144, $boy))
                $null = $fs.Read($bas, 0, $bas.Length)
                $t0 = $utf8.GetString($bas)
                $mc = [regex]::Match($t0, '"cwd":"((?:[^"\\]|\\.)*)"')
                if ($mc.Success) { $r.Cwd = ($mc.Groups[1].Value -replace '\\\\', '\') }
                $ms = [regex]::Match($t0, '"session_id":"([^"]+)"')
                if ($ms.Success) { $r.SessionId = $ms.Groups[1].Value }
                $mt0 = [regex]::Match($t0, '"type":"turn_context"[\s\S]{0,4000}?"model":"([^"]+)"')
                if ($mt0.Success) { $r.Model = $mt0.Groups[1].Value }
            }
            foreach ($kuyruk in @(2MB, 8MB)) {
                $bas = [long][math]::Max($Offset, $boy - $kuyruk)
                if ($bas -ge $boy) { break }
                $n = [int]($boy - $bas)
                $buf = New-Object byte[] $n
                $null = $fs.Seek($bas, [IO.SeekOrigin]::Begin)
                $okunan = 0; while ($okunan -lt $n) { $k = $fs.Read($buf, $okunan, $n - $okunan); if ($k -le 0) { break }; $okunan += $k }
                $t = $utf8.GetString($buf, 0, $okunan)
                $i = $t.LastIndexOf('"total_token_usage":{')
                if ($i -ge 0) {
                    $sat0 = $t.LastIndexOf("`n", $i) + 1
                    $sat = $t.Substring($sat0, [math]::Min(4000, $t.Length - $sat0))
                    $u = $t.Substring($i, [math]::Min(600, $t.Length - $i))
                    $mi = [regex]::Match($u, '"input_tokens":(\d+)'); $mk = [regex]::Match($u, '"cached_input_tokens":(\d+)'); $mo = [regex]::Match($u, '"output_tokens":(\d+)')
                    if ($mi.Success -and $mo.Success) {
                        $inT = [double]$mi.Groups[1].Value; $crT = $(if ($mk.Success) { [double]$mk.Groups[1].Value } else { 0 })
                        $r.CodexToplam = @{ In = [math]::Max(0, $inT - $crT); Cr = $crT; Out = [double]$mo.Groups[1].Value }
                        $mt = [regex]::Match($sat, '"timestamp":"([^"]+)"'); if ($mt.Success) { $r.CodexTs = $mt.Groups[1].Value }
                    } else { $r.Taninmayan++ }
                    $j = $t.LastIndexOf('"type":"turn_context"')
                    if ($j -ge 0) { $mm = [regex]::Match($t.Substring($j, [math]::Min(4000, $t.Length - $j)), '"model":"([^"]+)"'); if ($mm.Success) { $r.Model = $mm.Groups[1].Value } }
                    break
                }
            }
            $r.Offset = $boy; $r.Ok = $true
            return $r
        }

        # --- Claude: Offset'ten sona, parca parca, yalniz tam satirlar ---
        $null = $fs.Seek($Offset, [IO.SeekOrigin]::Begin)
        $buf = New-Object byte[] (8MB)
        $artik = New-Object System.IO.MemoryStream
        $sonId = $r.SonId
        while ($true) {
            $k = $fs.Read($buf, 0, $buf.Length)
            if ($k -le 0) { break }
            $son = [Array]::LastIndexOf($buf, [byte]10, $k - 1)
            if ($son -lt 0) { $artik.Write($buf, 0, $k); continue }
            $artik.Write($buf, 0, $son + 1)
            $parca = $utf8.GetString($artik.GetBuffer(), 0, [int]$artik.Length)
            $tamBayt = [long]$artik.Length
            $artik.SetLength(0)
            if ($son + 1 -lt $k) { $artik.Write($buf, $son + 1, $k - $son - 1) }
            foreach ($sat in $parca.Split("`n")) {
                if ($sat.IndexOf('"usage":{', [StringComparison]::Ordinal) -lt 0) { continue }
                if ($sat.IndexOf('"type":"assistant"', [StringComparison]::Ordinal) -lt 0) { continue }
                $im = $sat.IndexOf('"message":{', [StringComparison]::Ordinal)
                $iu = $sat.LastIndexOf('"usage":{', [StringComparison]::Ordinal)
                if ($im -lt 0 -or $iu -lt $im) { $r.Taninmayan++; continue }
                $msg = $sat.Substring($im, [math]::Min(400, $sat.Length - $im))
                $mId = [regex]::Match($msg, '"id":"(msg_[A-Za-z0-9_]+)"')
                $mMo = [regex]::Match($msg, '"model":"([^"]+)"')
                $model = $(if ($mMo.Success) { $mMo.Groups[1].Value } else { '' })
                if ($model.StartsWith('<')) { continue }   # <synthetic> API hata satiri
                $id = $(if ($mId.Success) { $mId.Groups[1].Value } else { '' })
                if ($id -and $id -eq $sonId) { continue }   # ayni yanitin devam satiri
                $u = $sat.Substring($iu, [math]::Min(1500, $sat.Length - $iu))
                $mi = [regex]::Match($u, '"input_tokens":(\d+)'); $mo = [regex]::Match($u, '"output_tokens":(\d+)')
                if (-not ($mi.Success -and $mo.Success)) { $r.Taninmayan++; continue }
                $mcw = [regex]::Match($u, '"cache_creation_input_tokens":(\d+)'); $mcr = [regex]::Match($u, '"cache_read_input_tokens":(\d+)')
                $m1h = [regex]::Match($u, '"ephemeral_1h_input_tokens":(\d+)')
                $mSp = [regex]::Match($u, '"speed":"(\w+)"')
                $cw = $(if ($mcw.Success) { [double]$mcw.Groups[1].Value } else { 0 })
                $cw1h = $(if ($m1h.Success) { [math]::Min($cw, [double]$m1h.Groups[1].Value) } else { 0 })
                $in = [double]$mi.Groups[1].Value; $cr = $(if ($mcr.Success) { [double]$mcr.Groups[1].Value } else { 0 })
                $its = $sat.LastIndexOf('"timestamp":"', [StringComparison]::Ordinal)
                $ts = $(if ($its -ge 0) { $e = $sat.IndexOf('"', $its + 13); $sat.Substring($its + 13, $e - $its - 13) } else { '' })
                if (-not $r.SessionId) { $mS = [regex]::Match($sat, '"sessionId":"([^"]+)"'); if ($mS.Success) { $r.SessionId = $mS.Groups[1].Value } }
                if (-not $r.Cwd) { $mC = [regex]::Match($sat, '"cwd":"((?:[^"\\]|\\.)*)"'); if ($mC.Success) { $r.Cwd = ($mC.Groups[1].Value -replace '\\\\', '\') } }
                $r.Kayitlar.Add(@{ Ts = $ts; Model = $model; In = $in; Out = [double]$mo.Groups[1].Value; Cw5 = $cw - $cw1h; Cw1h = $cw1h; Cr = $cr
                                   Fast = ($mSp.Success -and $mSp.Groups[1].Value -eq 'fast'); Ctx = ($in + $cw + $cr) })
                if ($id) { $sonId = $id }
            }
            $Offset += $tamBayt
        }
        $r.Offset = $Offset; $r.SonId = $sonId; $r.Ok = $true
    } catch { $r.Hata = $_.Exception.Message } finally { if ($fs) { $fs.Dispose() } }
    return $r
}

function Get-BeyinClaudeArgs {
    # Ozetleyici 'claude -p' arguman dizesi TEK YERDE (2026-10-06). Invoke-BeyinClaude
    # ve doktorun model cagirmayan 'ozetleyici bayraklari' sondasi ayni dizeyi kullanir.
    #
    # --tools "": yerlesik araclarin TAMAMI kapali (CLI yardimi: 'Use "" to disable
    # all tools'). Onceki --disallowed-tools ad listesi CLI surumuyle kayiyordu:
    # 2.1.268 ve 2.1.290 'MultiEdit' adini tanimiyor, her cagrida stderr'e
    # 'Permission deny rule "MultiEdit" matches no known tool' UYARISI basiyordu.
    # Uyari cagriyi durdurmuyordu ama stderr hic bos kalmadigi icin
    # Get-BeyinFailDetail stdout'taki asil mesaji atiyordu: 2026-10-06 00:31-03:49
    # arasi 36 flush 'You've hit your session limit - resets 3:50am' aldi, hepsi
    # 'cikis-kodu' sayildi, butce iade edilmedi, erteleme kurulmadi.
    # Bos arguman dusurulurse --tools degersiz kalir ve CLI ACIK hata verir (ardindan
    # gelen --no-session-persistence bir secenektir, deger olarak yutulmaz).
    # --no-session-persistence: ozetleyici transkriptleri ~/.claude/projects altina
    # yazilmasin (2006 beyin-engine-cwd dokumu olculmustu).
    param([string]$Model = 'haiku')
    return ('-p --model ' + $Model + ' --strict-mcp-config --tools "" --no-session-persistence')
}

function Invoke-BeyinClaude {
    param(
        [Parameter(Mandatory = $true)][string]$Prompt,
        [Parameter(Mandatory = $true)][hashtable]$Paths,
        [string]$Model = 'haiku',
        [int]$TimeoutSeconds = 240
    )

    $claude = Get-BeyinClaudeExe
    if (-not $claude) {
        return @{ Ok = $false; Out = ''; Err = ''; ExitCode = -1; Reason = 'cli-yok' }
    }

    # Notrsuz calisma dizini: hicbir projenin CLAUDE.md/MCP/skill yapilandirmasini
    # miras almamak icin vault'un DA disinda, bos bir klasor kullaniyoruz.
    #
    # ACIK KAPANIS (fail closed) - benzer bir motorda olculen ders:
    #
    #   Claude CLI, bir projenin .claude/ klasoru icindeki HER yolu "hassas"
    #   sayip otomatik koruyor ve --permission-mode acceptEdits altinda bile
    #   Write/Edit'i SESSIZCE reddediyor. Upstream'de bu, her gercek compile
    #   kosusunu "no-allowed-file-changes" ile dusurmustu.
    #
    # Buradaki eski fallback tam da o tuzaga dusuyordu:
    #     catch { $cwd = $Paths.ScrState }   # = <vault>\motor\scripts\.state
    # LOCALAPPDATA olusturulamadigi an motor sessizce .claude/ icinde calismaya
    # baslardi ve HER ozetleme sessizce basarisiz olurdu - log'da yalnizca
    # aciklamasiz bir exit kodu gorunurdu.
    #
    # Artik vault icine DUSMUYORUZ: sirasiyla LOCALAPPDATA, sistem TEMP; ikisi
    # de olmazsa acik hata donuyoruz. Sessiz yanlis calisma yerine gurultulu
    # basarisizlik.
    # Adaylari .NET ile birlestiriyoruz: Join-Path, var olmayan bir surucu adi
    # (bozuk LOCALAPPDATA/TEMP) gorunce KENDISI firlatir ve stderr'e gurultu
    # basar. [IO.Path]::Combine sadece dize birlestirir, dogrulama yapmaz.
    $adaylar = New-Object System.Collections.Generic.List[string]
    foreach ($kok in @($env:LOCALAPPDATA, [System.IO.Path]::GetTempPath())) {
        if ([string]::IsNullOrWhiteSpace($kok)) { continue }
        try { $adaylar.Add([System.IO.Path]::Combine($kok, 'beyin-engine-cwd')) } catch { }
    }

    # SIRA KRITIK: once KONTROL, sonra OLUSTUR.
    #
    # Onceki surum tersini yapiyordu: New-Item ile dizini olusturup SONRA
    # "vault icinde mi" diye bakiyordu. Yani engellemek icin var oldugu seyi
    # once yapiyordu - reddetse bile vault'a bir dizin birakiyordu.
    #
    # Olculdu 2026-08-31 (upstream'in test_compile_rejects_temp_stage_inside_vault
    # testinin yerel karsiligi kosuldu): LOCALAPPDATA ve TEMP vault icine
    # cozuldugunde fail-closed dogru calisiyordu (cwd-yok, exit -3, model
    # cagrilmadi) AMA guvensiz dizinde bir klasor olusuyordu. Upstream'in testi
    # tam bunu iddia ediyor: assertEqual(list(unsafe_temp.glob(...)), []).
    #
    # Daha kotusu: o klasor .claude/ altina duserse Claude CLI orayi sessizce
    # koruyor ve motor bir daha hicbir sey yazamiyor - bu fonksiyonun bastaki
    # yorumunda anlatilan tuzagin ta kendisi.
    #
    # GetFullPath dosya sistemine DOKUNMAZ, yalnizca yolu normallestirir; bu
    # yuzden kontrolu olusturmadan once yapabiliyoruz.
    $cwd = $null
    $tamVault = $null
    try { $tamVault = [System.IO.Path]::GetFullPath($Paths.Vault).TrimEnd('\', '/') } catch { }

    foreach ($aday in $adaylar) {
        if (-not $aday) { continue }
        try {
            $tamAday = [System.IO.Path]::GetFullPath($aday)

            # ONCE: vault icinde mi? Oyleyse DOKUNMA, olusturma bile.
            if ($tamVault) {
                $kok = $tamVault + [System.IO.Path]::DirectorySeparatorChar
                if ($tamAday.TrimEnd('\', '/').Equals($tamVault, [StringComparison]::OrdinalIgnoreCase) -or
                    $tamAday.StartsWith($kok, [StringComparison]::OrdinalIgnoreCase)) {
                    continue
                }
            }

            # SONRA: guvenli oldugu belli, simdi olustur.
            New-Item -ItemType Directory -Force -Path $tamAday -ErrorAction Stop | Out-Null
            $cwd = $tamAday
            break
        } catch { continue }
    }
    if (-not $cwd) {
        return @{ Ok = $false; Out = ''; Err = 'notr calisma dizini olusturulamadi (vault disinda yazilabilir yer yok)'
                  ExitCode = -3; Reason = 'cwd-yok' }
    }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName               = $claude
    # Arguman dizesi: hicbir deger bosluk icermiyor, duz birlestirme guvenli.
    # --strict-mcp-config + --mcp-config VERMEMEK = hic MCP sunucusu yuklenmez.
    # --tools "": ozetleyici arac cagirmaya ihtiyac duymuyor; prompt'ta rica etmek
    # yerine yerlesik araclarin TAMAMINI mekanik olarak kapatiyoruz (Get-BeyinClaudeArgs).
    #
    # --bare KULLANILMIYOR ve bu bilincli. Resmi belge onu "scripted/SDK
    # cagrilari icin onerilen mod" diye tanimliyor ve kancalari/LSP/plugin'i
    # atladigi icin buraya uygun GORUNUYOR. Olculdu (2026-08-31), uygun DEGIL:
    #     --strict-mcp-config          -> exit 0, 5,3 sn, 'PONG'
    #     --strict-mcp-config --bare   -> exit 1, 2,2 sn, 'Not logged in
    #                                     Please run /login'
    # --bare kimlik dogrulamayi da dusuruyor; eklenseydi HER ozetleme cokerdi.
    # Kendi kancalarimiza karsi korunma zaten BEYIN_CHILD ile saglaniyor
    # (Test-BeyinChild her kancanin ilk satirinda cikis yapiyor).
    $psi.Arguments = Get-BeyinClaudeArgs -Model $Model
    # 2026-10-05 (kod incelemesi): Agent (Task'in yeni adi), Skill, MultiEdit,
    # BashOutput/KillShell, ToolSearch listede yoktu - guvenilmez transkript
    # ozetleyiciye Skill/Agent cagrisi yaptirabilirdi. --no-session-persistence:
    # ozetleyici transkriptleri ~/.claude/projects altina yazilmasin (2006
    # beyin-engine-cwd dokumu olculmustu; yetim tarayici eliyor ama disk+tarama).
    $psi.WorkingDirectory       = $cwd
    $psi.UseShellExecute        = $false
    $psi.CreateNoWindow         = $true
    $psi.RedirectStandardInput  = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.StandardOutputEncoding = New-Object System.Text.UTF8Encoding($false)
    $psi.StandardErrorEncoding  = New-Object System.Text.UTF8Encoding($false)
    $psi.EnvironmentVariables['BEYIN_CHILD'] = '1'   # kancalar alt surecte calismasin
    $psi.EnvironmentVariables['AGENTCHEF_ROUTING_HINT'] = 'off'   # AgentChef yonlendirme satiri motorun kendi model cagrilarinda gereksiz

    $proc = $null
    try {
        $proc = [System.Diagnostics.Process]::Start($psi)

        # stdin'e HAM BAYT yaz: $OutputEncoding'e (us-ascii tuzagi) hic guvenmiyoruz.
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Prompt)
        $proc.StandardInput.BaseStream.Write($bytes, 0, $bytes.Length)
        $proc.StandardInput.BaseStream.Flush()
        $proc.StandardInput.Close()

        # Kilitlenmemek icin iki akisi es zamanli oku
        $tOut = $proc.StandardOutput.ReadToEndAsync()
        $tErr = $proc.StandardError.ReadToEndAsync()

        if (-not $proc.WaitForExit($TimeoutSeconds * 1000)) {
            # AGACI OLDUR (2026-10-05): Codex dali Stop-BeyinProcessTree kullaniyordu,
            # Claude dali yalniz ebeveyni; node torunu zaman asiminda yasiyordu.
            try { Stop-BeyinProcessTree -ProcessId $proc.Id } catch { try { $proc.Kill() } catch { } }

            # NEDEN OLCUYORUZ (bir yukari akis motorundan alinan ders)
            #   "Kontrolor beklemeyi birakti" ile "is basarisiz oldu" ayni cumle
            #   degildir. Vazgecmeden once uretilene BAK.
            #
            # Eskiden bu dal Out='' , Err='' donuyordu: es zamanli okuyucularin
            # o ana kadar topladigi her sey sessizce ATILIYORDU. Logda yalnizca
            # "zaman-asimi" kaliyordu ve iki cok farkli ariza ayirt edilemiyordu:
            #   (a) model hic konusmadi  -> baglanti/kimlik/kota tarafi
            #   (b) model 9 KB uretti, son saniyede kesildi -> tavan cok dusuk
            # Ikisinin cozumu farkli; ayni log satiri ikisini de gizliyordu.
            #
            # ICERIK KULLANILMAZ, yalnizca OLCU loglanir: yarim kalmis bir ozet
            # gunluk loga yazilirsa blok bozulur ve overwritePolicy=never
            # oldugu icin geri alinamaz. Sessiz veri kaybi yerine gurultulu olcu.
            #
            # OLCULDU (2026-08-30): 'claude -p' akis YAPMIYOR. 33,8 sn suren bir
            # cagride stdout'un tamami 29,4. saniyede TEK parcada geldi. Yani
            # zaman asimi pratikte her zaman TAM kayiptir; kurtarilacak kismi
            # metin yoktur ve bu dal normalde 0 raporlar. Sifirin kendisi bilgi:
            # "0 karakter" = beklenen timeout sekli, "N karakter" = cikti basildi
            # ama surec cikamadi (askida kalma), ki bu bambaska bir arizadir.
            $kismi = -1
            try {
                if ($tOut.Wait(2000)) {
                    $kOut = $tOut.Result
                    if ($null -ne $kOut) { $kismi = $kOut.Length }
                }
            } catch { }
            $kErr = ''
            try { if ($tErr.Wait(500)) { $kErr = $tErr.Result } } catch { }

            $olcu = if ($kismi -lt 0) { 'kismi cikti okunamadi' }
                    elseif ($kismi -eq 0) { 'model hic cikti uretmedi' }
                    else { "kismi cikti $kismi karakter (atildi)" }

            return @{
                Ok       = $false
                Out      = ''
                Err      = $kErr
                ExitCode = -2
                Reason   = "zaman-asimi ${TimeoutSeconds}sn, $olcu"
            }
        }
        $proc.WaitForExit()

        $out = ''; $err = ''
        try { $out = $tOut.Result } catch { }
        try { $err = $tErr.Result } catch { }
        $code = $proc.ExitCode

        if ($code -ne 0) {
            return @{ Ok = $false; Out = $out; Err = $err; ExitCode = $code; Reason = 'cikis-kodu' }
        }
        if ([string]::IsNullOrWhiteSpace($out)) {
            return @{ Ok = $false; Out = ''; Err = $err; ExitCode = 0; Reason = 'bos-yanit' }
        }
        return @{ Ok = $true; Out = $out.Trim(); Err = $err; ExitCode = 0; Reason = 'ok' }
    } catch {
        return @{ Ok = $false; Out = ''; Err = $_.Exception.Message; ExitCode = -3; Reason = 'istisna' }
    } finally {
        if ($proc) { try { $proc.Dispose() } catch { } }
    }
}

# ============================================================================
# Yardimcilar
# ============================================================================

function Get-BeyinToday { return ((Get-Date).ToString('yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)) }

# Read-BeyinTranscript dosyayi tamamen belege okudugu icin ust sinir sart.
# 100 MB comert: normal bir transkript 15 MB'in altinda kalir.
$script:BeyinMaxTranscriptMB = 100

# Tek bir flush parcasinin model'e gonderecegi en fazla karakter.
# Bu sinir artik KIRPMA degil PARCALAMA sinirdir: asan kisim kaybolmaz,
# bir sonraki parcada islenir (bkz. Read-BeyinTranscript -MaxChars).
$script:BeyinParcaKarakter = 90000

# Bir gunluk log en fazla kac kez derlemeye sokulur. Tavan dolunca 'final'
# sayilir: aksi halde takilmis bir gun kronolojik siranin basini sonsuza
# kadar isgal eder ve arkasindaki gunler hic derlenmez.
$script:BeyinMaxCompileAttempts = 3

function Get-BeyinMaxTranscriptMB { return $script:BeyinMaxTranscriptMB }

function Get-BeyinTailLines {
    # Dosyanin SONUNDAKI satirlari dondurur - dosyayi bastan okumadan.
    #
    # NEDEN: 'Get-Content -Tail' PS 5.1'de buyuk dosyalarda pratikte kilitleniyor.
    # Olculdu - 20 transkript uzerinde (en buyugu 728 MB) 10 dakikada bitmedi;
    # ayni is byte-seek ile saniyeler suruyor.
    #
    # Dosyanin sonundan geriye dogru pencere buyuterek okur. Pencerenin ilk
    # satiri byte ortasindan basladigi icin YARIM olabilir - her zaman atilir.
    param([string]$Path, [int]$MaxLines = 300, [int]$MaxBytes = 4194304)

    $pencere = 65536
    while ($true) {
        $txt = ''
        try {
            $fs = [System.IO.File]::Open($Path, 'Open', 'Read', 'ReadWrite')
            try {
                $len  = $fs.Length
                $take = [int][Math]::Min([long]$pencere, $len)
                [void]$fs.Seek($len - $take, [System.IO.SeekOrigin]::Begin)
                $buf  = New-Object byte[] $take
                $okunan = $fs.Read($buf, 0, $take)
                $txt = [System.Text.Encoding]::UTF8.GetString($buf, 0, $okunan)
            } finally { $fs.Close(); $fs.Dispose() }
        } catch { return @() }

        $lines = @($txt -split "`r?`n")
        # Tum dosyayi kapsamadiysak ilk satir yarimdir.
        if ($pencere -lt (Get-Item -LiteralPath $Path).Length -and $lines.Count -gt 1) {
            $lines = @($lines[1..($lines.Count - 1)])
        }
        $dolu = @($lines | Where-Object { $_ })

        # Tek satirlik dev kayitlar (base64 gomulu icerik) pencereye sigmayabilir.
        if ($dolu.Count -ge 1 -or $pencere -ge $MaxBytes -or $pencere -ge (Get-Item -LiteralPath $Path).Length) {
            if ($dolu.Count -gt $MaxLines) { $dolu = @($dolu[($dolu.Count - $MaxLines)..($dolu.Count - 1)]) }
            return $dolu
        }
        $pencere = $pencere * 8
    }
}

function Get-BeyinTranscriptTime {
    # Transkriptin GERCEK zamanini dondurur - flush'in calistigi ani degil.
    #
    # SORUN: flush her zaman Get-BeyinToday kullaniyordu. Yetim tarayici dunku
    # (ya da 3 gun onceki) bir oturumu topladiginda blok BUGUNUN loguna
    # dusuyordu. Gunluk log kronolojik kanit katmani olmaktan cikiyordu.
    #
    # Her iki bicimde de satirlarin ust seviyesinde ISO-8601 'timestamp' alani
    # var (Claude: mesaj satirlarinda, Codex: her satirda). Sondan tarayip en
    # yeni damgayi buluruz; bulunamazsa dosyanin LastWriteTime'ina duseriz.
    #
    # @{ Date = 'yyyy-MM-dd'; Stamp = 'HH:mm'; Iso; Source = 'icerik|dosya|bugun' }
    param([Parameter(Mandatory = $true)][string]$Path, [int]$MaxScan = 300)

    $sonuc = @{ Date = (Get-BeyinToday); Stamp = ((Get-Date).ToString('HH:mm', [Globalization.CultureInfo]::InvariantCulture))
                Iso = (Get-BeyinIsoNow); Source = 'bugun' }
    $dt = $null
    try {
        $tail = @(Get-BeyinTailLines -Path $Path -MaxLines $MaxScan)
        for ($i = $tail.Count - 1; $i -ge 0; $i--) {
            $line = $tail[$i]
            if (-not $line -or $line[0] -ne '{') { continue }
            try { $o = $line | ConvertFrom-Json -ErrorAction Stop } catch { continue }
            if (-not $o.PSObject.Properties['timestamp']) { continue }
            try { $dt = ([datetimeoffset]::Parse([string]$o.timestamp)).ToLocalTime(); break } catch { }
        }
        if ($dt) { $sonuc.Source = 'icerik' }
    } catch { }

    if (-not $dt) {
        try {
            $dt = [datetimeoffset](Get-Item -LiteralPath $Path -ErrorAction Stop).LastWriteTime
            $sonuc.Source = 'dosya'
        } catch { }
    }
    if (-not $dt) { return $sonuc }

    # SINIRLAR - bozuk/garip damga eski bir gunluk logu diriltmesin:
    #   gelecek tarih  -> saat bozuk, bugune al
    #   90 gunden eski -> arsivle.ps1 o tarihi tasimis olabilir, bugune al
    $simdi = [datetimeoffset]::Now
    if ($dt -gt $simdi.AddHours(1) -or $dt -lt $simdi.AddDays(-90)) {
        $sonuc.Source = 'bugun'
        return $sonuc
    }

    $sonuc.Date  = $dt.ToString('yyyy-MM-dd')
    $sonuc.Stamp = $dt.ToString('HH:mm')
    $sonuc.Iso   = $dt.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
    return $sonuc
}

function Get-BeyinIsoNow {
    # Vault semasi tam ISO-8601 + Z bekliyor: "2026-08-27T10:31:05.123Z"
    return (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
}

function New-BeyinNoteId {
    return 'brn_' + [guid]::NewGuid().ToString()
}

function Split-BeyinDaylogBlocks {
    # Bir gunluk logu '### Oturum' basliklarindan BLOKLARA ayirir.
    #
    # Neden gerekli: enjeksiyon "son 40 satir" aliyordu ve bu neredeyse her
    # zaman bir blogun ORTASINDAN basliyordu. Modele yarim bir ozetin kuyrugu
    # gidiyor, hangi projeye/oturuma ait oldugu bilinmiyordu.
    #
    # Donus: @( @{ Baslik; Proje; Ajan; Saat; Metin } )  - dosya sirasinda.
    param([string]$Path)
    $bos = @()
    if (-not (Test-Path -LiteralPath $Path)) { return $bos }
    $ham = ''
    try { $ham = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 } catch { return $bos }
    if (-not $ham) { return $bos }
    $ham = $ham -replace ('^' + [char]0xFEFF), ''
    # frontmatter'i at
    $fm = [regex]::Match($ham, '(?s)^---\r?\n.*?\r?\n---\r?\n')
    if ($fm.Success) { $ham = $ham.Substring($fm.Length) }

    $bloklar = New-Object System.Collections.Generic.List[object]
    # Blok basligi: "### Oturum 23:07 - ornek-proje [claude/yetim]"
    $rx = [regex]'(?m)^###\s+Oturum\s+(?<saat>\d{1,2}:\d{2})(?:\s*-\s*(?<proje>[^\[\r\n]+?))?\s*(?:\[(?<ajan>[^\]/]+)(?:/(?<sebep>[^\]]+))?\])?\s*$'
    $eslesme = @($rx.Matches($ham))
    for ($i = 0; $i -lt $eslesme.Count; $i++) {
        $bas = $eslesme[$i].Index
        $son = if ($i + 1 -lt $eslesme.Count) { $eslesme[$i + 1].Index } else { $ham.Length }
        # Eski blok basliklarinda sebep parantez icindeydi:
        #   "### Oturum 10:00 - ornek-proje (session-end)"
        # Temizlenmezse 'ornek-proje' ile 'ornek-proje (session-end)' AYRI proje
        # sayilir ve gruplama bolunur (olculdu: 20 + 4).
        $proje = $eslesme[$i].Groups['proje'].Value.Trim()
        $proje = ($proje -replace '\s*\([^)]*\)\s*$', '').Trim()
        $bloklar.Add([pscustomobject]@{
            Baslik = $eslesme[$i].Value.Trim()
            Saat   = $eslesme[$i].Groups['saat'].Value
            Proje  = $proje
            Ajan   = $eslesme[$i].Groups['ajan'].Value.Trim()
            Metin  = $ham.Substring($bas, $son - $bas).TrimEnd()
        })
    }
    # PS 5.1 TUZAGI: @(<List[object]>) "Argument types do not match" firlatir.
    # Bu bu oturumda ikinci kez isirdi (Get-BeyinQueue de ayni sekilde sessizce
    # patliyordu). Generic List her zaman .ToArray() ile donusturulur.
    return $bloklar.ToArray()
}

function Get-BeyinBlokAnahtar {
    # Gunluk log blogu icin KRONOLOJIK siralama anahtari: 'yyyy-MM-dd HH:mm'.
    # Blok basligindaki saat 'H:mm' olabiliyor (regex \d{1,2}); duz string
    # siralamasinda '9:49' > '10:00' cikardi. Sifir dolgusu bunu kapatir.
    param([string]$Gun, [string]$Saat)
    $sa = [string]$Saat
    if ($sa -match '^(\d{1,2}):(\d{2})$') { $sa = '{0:00}:{1}' -f [int]$Matches[1], $Matches[2] }
    else { $sa = '00:00' }
    return ('{0} {1}' -f $Gun, $sa)
}

function Read-BeyinDaylogForProject {
    # Enjeksiyon icin: MEVCUT PROJENIN son bloklarini dondurur.
    #
    # Eski davranis "son 40 satir"di: hangi projeye ait oldugu rastgeleydi ve
    # blok sinirini kesiyordu. Yeni davranis blok sinirinda kesiyor ve once
    # ayni projeyi ariyor; o projeye ait blok yoksa genel son bloklara duser
    # (baglamsiz kalmaktan iyidir, ve dustugu acikca isaretlenir).
    #
    # Donus: @{ Text; Kaynak = 'proje'|'genel'|''; Gun; BlokSayisi }
    param(
        [hashtable]$Paths,
        [string]$ProjectLeaf = '',
        [int]$Blok = 3,
        [int]$GunSayisi = 3,
        [int]$MaxKarakter = 4000
    )
    $r = @{ Text = ''; Kaynak = ''; Gun = ''; BlokSayisi = 0 }
    $gunler = @(Get-ChildItem -LiteralPath $Paths.Daylogs -Filter '*.md' -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -cmatch '^\d{4}-\d{2}-\d{2}\.md$' } |
                Sort-Object Name -Descending | Select-Object -First $GunSayisi)
    if (@($gunler).Count -eq 0) { return $r }

    # DIKKAT: $gunler AZALAN siradaydi (en yeni gun once). Bu listeye oyle
    # eklenip sonra '-Last N' alinirsa EN ESKI bloklar donerdi. Olculdu:
    # ornek-proje icin 2026-08-28 bloklari varken 2026-08-27 donuyordu.
    # Kronolojik gez, sondan al.
    $hepsi = New-Object System.Collections.Generic.List[object]
    foreach ($g in @($gunler | Sort-Object Name)) {
        foreach ($b in @(Split-BeyinDaylogBlocks -Path $g.FullName)) {
            $b | Add-Member -NotePropertyName Gun -NotePropertyValue $g.BaseName -Force
            $b | Add-Member -NotePropertyName Anahtar -NotePropertyValue (Get-BeyinBlokAnahtar -Gun $g.BaseName -Saat $b.Saat) -Force
            $hepsi.Add($b)
        }
    }
    if ($hepsi.Count -eq 0) { return $r }
    # KRONOLOJIK SIRA (2026-09-10): gunluk log saf append; yetim toparlama eski
    # oturumlari yenilerin ARKASINA ekliyor. Dosya sirasindan 'son N' almak
    # olculduğu kadariyla 15 gunun 45 slotunda 28 kez YANLIS blogu seciyordu
    # (or. 09-08'de 14:17/08:40/08:47 secildi, gunun gercek son ucu
    # 23:37/23:34/22:24). Saat 'H:mm' olabildigi icin anahtar sifir dolgulu.
    $hepsiArr = @($hepsi.ToArray() | Sort-Object Anahtar)

    $secili = @()
    if ($ProjectLeaf) {
        $secili = @($hepsiArr | Where-Object { $_.Proje -eq $ProjectLeaf })
        if ($secili.Count -gt 0) { $r.Kaynak = 'proje' }
    }
    if ($secili.Count -eq 0) { $secili = @($hepsiArr); $r.Kaynak = 'genel' }

    # TEKILLESTIRME: paralel panellerde (fan-out) ayni brifing 3-4 kez
    # ozetleniyor ve 'son N' bloklarin tamami ayni seyi anlatiyor. Ayni
    # (Gun+Saat+Proje+Ajan) dortlusunden yalniz EN UZUN blogu tut.
    $benzersiz = @{}
    foreach ($b in $secili) {
        $k = '{0}|{1}|{2}' -f $b.Anahtar, $b.Proje, $b.Ajan
        if (-not $benzersiz.ContainsKey($k) -or $benzersiz[$k].Metin.Length -lt $b.Metin.Length) {
            $benzersiz[$k] = $b
        }
    }
    $secili = @($benzersiz.Values | Sort-Object Anahtar)

    # En yeniler: liste kronolojik siralandi, sondan al.
    $secili = @($secili | Select-Object -Last $Blok)
    $metin = (@($secili | ForEach-Object { $_.Metin }) -join "`n`n").Trim()
    if ($metin.Length -gt $MaxKarakter) {
        # Blok sinirinda kesmeye devam: bastaki bloklari at, sondakileri tut.
        while ($secili.Count -gt 1 -and $metin.Length -gt $MaxKarakter) {
            $secili = @($secili | Select-Object -Skip 1)
            $metin = (@($secili | ForEach-Object { $_.Metin }) -join "`n`n").Trim()
        }
        if ($metin.Length -gt $MaxKarakter) { $metin = $metin.Substring(0, $MaxKarakter) + "`n_(kirpildi)_" }
    }
    $r.Text = $metin
    $r.Gun = @($secili | Select-Object -Last 1).Gun
    $r.BlokSayisi = $secili.Count
    return $r
}

function Update-BeyinSonDurum {
    # 86-compiled/son-durum.md - MAKINE SAHIPLI, TAMAMEN TURETILMIS.
    #
    # Kullanicinin istedigi gorunum: proje bazinda gruplanmis ozet.
    # Yazma tarafini degistirmiyoruz - gunluk log saf append kaliyor (Asama 1'de
    # kapatilan oku-degistir-yaz felaketini geri getirmemek icin). Gruplama
    # TURETILMIS bir dosyada yapiliyor: bozulsa/silinse bir sonraki calismada
    # yeniden insa edilir, veri kaybi yapisal olarak imkansiz.
    #
    # MODEL CAGRISI YOK - blok basliklarindan mekanik gruplama. Butceden
    # bagimsiz, her zaman guncel. Bu ayni zamanda 17 gundur bayat kalan
    # current-context.md sorununu da cozer: kuratorlu dosyaya dokunulmuyor.
    param([hashtable]$Paths, [int]$GunSayisi = 7, [int]$ProjeBasinaBlok = 3)

    $gunler = @(Get-ChildItem -LiteralPath $Paths.Daylogs -Filter '*.md' -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -cmatch '^\d{4}-\d{2}-\d{2}\.md$' } |
                Sort-Object Name -Descending | Select-Object -First $GunSayisi)
    if (@($gunler).Count -eq 0) { return $false }

    $gruplar = @{}
    $sira = New-Object System.Collections.Generic.List[string]
    $toplamBlok = 0
    foreach ($g in @($gunler | Sort-Object Name)) {
        foreach ($b in @(Split-BeyinDaylogBlocks -Path $g.FullName)) {
            $ad = if ($b.Proje) { $b.Proje } else { '(proje etiketsiz)' }
            if (-not $gruplar.ContainsKey($ad)) {
                $gruplar[$ad] = New-Object System.Collections.Generic.List[object]
                $sira.Add($ad)
            }
            $gruplar[$ad].Add([pscustomobject]@{ Gun = $g.BaseName; Saat = $b.Saat; Ajan = $b.Ajan; Metin = $b.Metin
                                                 Anahtar = (Get-BeyinBlokAnahtar -Gun $g.BaseName -Saat $b.Saat) })
            $toplamBlok++
        }
    }
    if ($toplamBlok -eq 0) { return $false }

    $iso = Get-BeyinIsoNow
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('---')
    [void]$sb.AppendLine('brain_schema: "codex-chef.brain-note.v1"')
    [void]$sb.AppendLine('id: "' + (New-BeyinNoteId) + '"')
    [void]$sb.AppendLine('type: "session-summary"')
    [void]$sb.AppendLine('title: "Son Durum - proje bazinda"')
    [void]$sb.AppendLine('project_id: "brain"')
    [void]$sb.AppendLine('status: "active"')
    [void]$sb.AppendLine('privacy: "local"')
    [void]$sb.AppendLine('confidence: "unverified"')
    [void]$sb.AppendLine('retention: "review-90d"')
    [void]$sb.AppendLine('created: "' + $iso + '"')
    [void]$sb.AppendLine('updated: "' + $iso + '"')
    [void]$sb.AppendLine('source_refs: ["engine:lib.ps1/Update-BeyinSonDurum", "vault:85-daylogs"]')
    [void]$sb.AppendLine('tags: ["son-durum", "makine-uretimi", "turetilmis"]')
    [void]$sb.AppendLine('---')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('# Son Durum')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('> **Bu dosya tamamen turetilmistir.** Kaynak: son ' + @($gunler).Count +
                         ' gunluk log. Elle duzenleme - her calismada yeniden uretilir.')
    [void]$sb.AppendLine('> Icerik makine ozetidir; kanonik bilgi degildir.')
    [void]$sb.AppendLine('')

    # KRONOLOJIK SIRALAMA + SON ETKINLIGE GORE PROJE SIRASI (2026-09-10).
    # Once: bloklar dosya sirasindaydi ('son:' saati yanlis, gosterilen bloklar
    # yanlis) ve projeler blok SAYISINA gore siralaniyordu - dun aksam
    # calisilan 2 bloklu proje 600. satirda kaliyordu.
    $siraliGruplar = @{}
    foreach ($ad in $sira) { $siraliGruplar[$ad] = @($gruplar[$ad].ToArray() | Sort-Object Anahtar) }
    $projeSirasi = @($sira | Sort-Object { $siraliGruplar[$_][-1].Anahtar } -Descending)

    # DEVAM NOKTALARI - sabah 30 saniyede okunacak tek tablo.
    # Kullanicinin sabah aradigi tek sey 'Yarim kalan' satiri; onceki surumde
    # 14 projenin 3'er tam blogu icine gomuluydu.
    [void]$sb.AppendLine('## Devam noktalari')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('| Proje | Son oturum | Yarim kalan |')
    [void]$sb.AppendLine('| --- | --- | --- |')
    foreach ($ad in $projeSirasi) {
        $son = $siraliGruplar[$ad][-1]
        $yk = ''
        $mm = [regex]::Match($son.Metin, '(?ms)^\*\*Yar[iı]m kalan:\*\*\s*(.+?)(?:\r?\n\r?\n|\r?\n\*\*|\z)')
        if ($mm.Success) {
            $yk = ($mm.Groups[1].Value -replace '\s+', ' ').Trim()
            $yk = ($yk -replace '^[-*\d.\s]+', '')
            if ($yk.Length -gt 150) { $yk = $yk.Substring(0, 150) + '...' }
        }
        if (-not $yk -or $yk -match '^(?i)yok\.?$') { $yk = '-' }
        # Tablo hucresinde boru isareti hucreyi boler
        $yk = $yk -replace '\|', '/'
        [void]$sb.AppendLine('| ' + $ad + ' | ' + $son.Anahtar + ' [' + $son.Ajan + '] | ' + $yk + ' |')
    }
    [void]$sb.AppendLine('')

    foreach ($ad in $projeSirasi) {
        $liste = $siraliGruplar[$ad]
        [void]$sb.AppendLine('## ' + $ad)
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine('_' + $liste.Count + ' oturum · son: ' + $liste[-1].Anahtar + '_')
        [void]$sb.AppendLine('')
        foreach ($b in @($liste | Select-Object -Last $ProjeBasinaBlok)) {
            # Gun basligi gunluk loga BAGLANIR: Obsidian graph'inda ve brain-cli
            # audit'inde gunluk loglar yetim gorunmesin (.base gorunumlerini
            # audit cozemiyor; Markdown wikilink ikisinde de calisir).
            [void]$sb.AppendLine('### [[../85-daylogs/' + $b.Gun + '|' + $b.Gun + ']] ' + $b.Saat + ' [' + $b.Ajan + ']')
            [void]$sb.AppendLine('')
            # Blok basligini at, govdeyi al
            $govde = ($b.Metin -replace '(?m)^###\s+Oturum[^\r\n]*\r?\n', '').Trim()
            [void]$sb.AppendLine($govde)
            [void]$sb.AppendLine('')
        }
    }

    # TUM gunluk loglar (yalniz son 7 degil): her log en az bir Markdown
    # baglantisiyla erisilebilir olsun. Ucuz: dizin listesi, icerik okunmaz.
    $tumGunler = @(Get-ChildItem -LiteralPath $Paths.Daylogs -Filter '*.md' -File -ErrorAction SilentlyContinue |
                   Where-Object { $_.Name -cmatch '^\d{4}-\d{2}-\d{2}\.md$' } |
                   Sort-Object Name -Descending)
    if (@($tumGunler).Count -gt 0) {
        [void]$sb.AppendLine('## Gunluk loglar (tumu)')
        [void]$sb.AppendLine('')
        foreach ($g in $tumGunler) {
            [void]$sb.AppendLine('- [[../85-daylogs/' + $g.BaseName + '|' + $g.BaseName + ']]')
        }
        [void]$sb.AppendLine('')
    }

    $hedef = Join-Path $Paths.Compiled 'son-durum.md'
    New-Item -ItemType Directory -Force -Path $Paths.Compiled | Out-Null
    Write-BeyinText -Path $hedef -Text $sb.ToString()
    return $true
}

function Read-BeyinFileTail {
    # Sona-eklenen (append-only) dosyalar icin: SON N satiri okur.
    #
    # Read-BeyinFileHead ILK N satiri okur; bu kuratorlu notlar icin dogru ama
    # 85-daylogs/*.md ve 86-compiled/index.md SONA eklenir. Bas-okuma o gunun EN
    # ESKI oturumunu ve en eski kavramlari enjekte ediyordu: 10 oturumluk bir
    # gunde en yeni 9'u hic gorunmuyordu ve 6 ay sonra enjeksiyon tamamen
    # alakasiz hale geliyordu. Bu bozulma sessizdi.
    param([string]$Path, [int]$Lines = 40)
    if (-not (Test-Path -LiteralPath $Path)) { return '' }
    try {
        $all = @(Get-Content -LiteralPath $Path -Encoding UTF8)
        if ($all.Count -eq 0) { return '' }
        $all[0] = $all[0] -replace ("^" + [char]0xFEFF), ''
        # frontmatter'i at
        if ($all[0].Trim() -eq '---') {
            $end = -1
            for ($i = 1; $i -lt $all.Count; $i++) { if ($all[$i].Trim() -eq '---') { $end = $i; break } }
            if ($end -ge 0 -and ($end + 1) -lt $all.Count) { $all = $all[($end + 1)..($all.Count - 1)] }
        }
        if ($all.Count -gt $Lines) { $all = $all[($all.Count - $Lines)..($all.Count - 1)] }
        return ($all -join "`n").Trim()
    } catch { return '' }
}

function Get-BeyinClaudeExe {
    # Yalniz GERCEK bir .exe kabul ediyoruz.
    #
    # Get-Command 'claude' bir Application dondurmek zorunda degil: function,
    # alias veya npm/winget kurulumundan gelen bir .cmd/.ps1 shim olabilir.
    # Shim'e stdin PIPE'i gercek surece ulasmayabilir; o zaman $summary bos doner,
    # flush sessizce FLUSH_BOS yazar ve doktor "claude CLI OK" diye rapor eder --
    # yani teshis kullaniciyi yanlis yone gonderir.
    $c = Get-Command claude -CommandType Application -ErrorAction SilentlyContinue
    if ($c) {
        $src = [string]$c.Source
        if ($src -and (Test-Path -LiteralPath $src) -and
            ([IO.Path]::GetExtension($src)).ToLowerInvariant() -eq '.exe') {
            return $src
        }
    }
    $fallback = Join-Path $env:USERPROFILE '.local\bin\claude.exe'
    if (Test-Path -LiteralPath $fallback) { return $fallback }
    return $null
}

# ============================================================================
# DURUM SURUMU
# ----------------------------------------------------------------------------
# .beyin-version dosyasi vardi ama hicbir kod onu OKUMUYORDU. Motorun durum
# dosyalari (sessions/*.json, watermarks/*.json, compiled_daylogs.txt) ileride
# bicim degistirirse eski dosyalar sessizce YANLIS okunur -- ornegin
# compiled_daylogs.txt'ye bir alan eklenirse Get-BeyinSeenMap $parts[1]'i yanlis
# yorumlar ve gunler hatali 'final' isaretlenir (kalici bilgi kaybi).
#
# Motorun yazdigi her JSON durum dosyasi 'v' alani tasiyor. Bu fonksiyon
# uyumsuzlugu gorunur kilar; doktor raporlar.
# ============================================================================

$script:BeyinStateVersion = 2

function Get-BeyinVersion {
    param([string]$Vault)
    $f = Join-Path $Vault '.beyin-version'
    if (Test-Path -LiteralPath $f) {
        try { return ((Get-Content -LiteralPath $f -Raw -Encoding UTF8).Trim()) } catch { }
    }
    return ''
}

function Test-BeyinStateCompatible {
    # Durum dosyalarinin 'v' alani beklenen surumle uyusuyor mu.
    # @{ Ok; Checked; Mismatched } doner.
    param([hashtable]$Paths)
    $checked = 0; $bad = New-Object System.Collections.Generic.List[string]
    foreach ($dir in @($Paths.Sessions, $Paths.Marks, $Paths.Queue)) {
        if (-not (Test-Path -LiteralPath $dir)) { continue }
        foreach ($f in @(Get-ChildItem -LiteralPath $dir -Filter '*.json' -File -ErrorAction SilentlyContinue)) {
            $checked++
            try {
                $o = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
                $v = if ($o.PSObject.Properties['v']) { [int]$o.v } else { 0 }
                # sessions/*.json 'v' tasimiyor (eski bicim) -> 0 kabul, uyumsuz degil
                if ($v -gt $script:BeyinStateVersion) { $bad.Add($f.Name) }
            } catch { $bad.Add($f.Name) }
        }
    }
    return @{ Ok = ($bad.Count -eq 0); Checked = $checked; Mismatched = @($bad) }
}

function Test-BeyinInVault {
    param([string]$Vault, [string]$Cwd)
    if ([string]::IsNullOrWhiteSpace($Cwd)) { return $false }
    try {
        $v = (Resolve-Path -LiteralPath $Vault -ErrorAction Stop).Path.TrimEnd('\')
        $c = (Resolve-Path -LiteralPath $Cwd -ErrorAction Stop).Path.TrimEnd('\')
        return ($c -eq $v) -or $c.StartsWith($v + '\', [StringComparison]::OrdinalIgnoreCase)
    } catch { return $false }
}

# ============================================================================
# MAKBUZ  (Faz 1A, 2026-09-15)
# ----------------------------------------------------------------------------
# NEDEN: makine yazimi makbuzsuzdu. Bir betik kalici bir kavram notunu SIFIR
# BAYTA dusurdu ve bu ancak brain-cli sayim farkiyla anlasildi. Artik her motor
# kosusu (flush, compile, retrieval, arsivle, ...) tek satirlik bir JSONL
# makbuz birakir: ne yazdi, kac bayt onceydi / sonra oldu, kac butce yakti,
# hangi kavramlari enjekte etti, ne kadar surdu. Doktor, bahcivan ve canli
# gorunum bu satirlari okur. Makbuz yazimi HICBIR ZAMAN kosuyu durdurmaz:
# tamami try/catch, kilit 2 sn ile sinirli.
#
# Satir: {"v":1,"ts":"...","script":"flush","src":"hook|cli|zamanlayici",
#         "agent":"codex","model":"claude","key":"05a435a7","reason":"session-end",
#         "outcome":"FLUSH_OK","ms":8123,"budget":1,
#         "files":[{"p":"85-daylogs/2026-09-14.md","b":4120,"a":5610}],
#         "concepts":[],"note":""}
# files[].a = -1 : dosya tasindi / silindi.  b = -1 : kosudan once yoktu.
# ============================================================================

function Measure-BeyinDosya {
    # Dosya boyutu (bayt). Yoksa -1. Makbuzun 'once/sonra' olcumu icin.
    param([string]$Path)
    try {
        if ($Path -and (Test-Path -LiteralPath $Path -PathType Leaf)) {
            return [long](Get-Item -LiteralPath $Path -ErrorAction Stop).Length
        }
    } catch { }
    return [long]-1
}

function ConvertTo-BeyinMakbuzYol {
    # Makbuza vault-goreli yol yazilir (tasinabilirlik + sizinti onlemi).
    # Vault disindaki bir yol icin kullanici profili '~' olur.
    param($Paths, [string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return '' }
    try {
        $v = ([string]$Paths.Vault).TrimEnd('\')
        if ($v -and $Path.StartsWith($v + '\', [StringComparison]::OrdinalIgnoreCase)) {
            return $Path.Substring($v.Length + 1).Replace('\', '/')
        }
        $h = ([string]$env:USERPROFILE).TrimEnd('\')
        if ($h -and $Path.StartsWith($h + '\', [StringComparison]::OrdinalIgnoreCase)) {
            return '~/' + $Path.Substring($h.Length + 1).Replace('\', '/')
        }
    } catch { }
    return (Split-Path -Leaf $Path)
}

function Write-BeyinMakbuz {
    # Tek satir makbuz. Asla firlatmaz. Dosya: makbuz\YYYY-MM-DD.jsonl (yerel gun).
    param(
        $Paths,
        [string]$Script,
        [string]$Outcome,
        [string]$Agent = '',
        [string]$Model = '',
        [string]$Key = '',
        [string]$Reason = '',
        [string]$Src = '',
        [object[]]$Files = @(),
        [int]$Budget = 0,
        [string[]]$Concepts = @(),
        [long]$DurationMs = 0,
        [string]$Note = ''
    )
    try {
        if (-not $Paths -or -not $Paths.Makbuz) { return }
        if (-not $Agent) { $Agent = Get-BeyinAgent }
        if (-not $Src) {
            $Src = if ($env:BEYIN_KAYNAK) { [string]$env:BEYIN_KAYNAK }
                   elseif ($env:BEYIN_AGENT) { 'hook' }
                   else { 'cli' }
        }
        $mkFiles = New-Object System.Collections.Generic.List[object]
        foreach ($f in @($Files)) {
            if ($null -eq $f) { continue }
            $mkFiles.Add([ordered]@{ p = [string]$f.p; b = [long]$f.b; a = [long]$f.a })
        }
        $mkNote = [string]$Note
        if ($mkNote.Length -gt 300) { $mkNote = $mkNote.Substring(0, 300) }
        $satir = [ordered]@{
            v        = 1
            ts       = (Get-Date).ToString('o', [Globalization.CultureInfo]::InvariantCulture)
            script   = [string]$Script
            src      = [string]$Src
            agent    = [string]$Agent
            model    = [string]$Model
            key      = [string]$Key
            reason   = [string]$Reason
            outcome  = [string]$Outcome
            ms       = [long]$DurationMs
            budget   = [int]$Budget
            files    = @($mkFiles.ToArray())
            concepts = @($Concepts | Where-Object { $_ } | ForEach-Object { [string]$_ })
            note     = $mkNote
        }
        $mkSatir = (ConvertTo-Json -InputObject $satir -Compress -Depth 5) -replace '\r?\n', ' '
        $mkDir = $Paths.Makbuz
        if (-not (Test-Path -LiteralPath $mkDir)) { New-Item -ItemType Directory -Force -Path $mkDir | Out-Null }
        $mkDosya = Join-Path $mkDir ((Get-Date).ToString('yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture) + '.jsonl')
        $mkEnc = New-Object System.Text.UTF8Encoding($false)
        Invoke-BeyinWithLock -LockPath (Join-Path $mkDir 'makbuz.lock') -TimeoutSeconds 2 -Action {
            [System.IO.File]::AppendAllText($mkDosya, $mkSatir + "`n", $mkEnc)
        }
    } catch { }
}

function Read-BeyinMakbuz {
    # Son N gunun makbuz satirlari (PSCustomObject). Bozuk satir atlanir.
    # TEK OKUYUCU: doktor, makbuz.ps1, bahcivan, canli hep bunu kullanir.
    param($Paths, [int]$Gun = 7)
    $sonuc = New-Object System.Collections.Generic.List[object]
    try {
        $dir = $Paths.Makbuz
        if (-not $dir -or -not (Test-Path -LiteralPath $dir)) { return @() }
        $sinir = (Get-Date).AddDays(-[math]::Max(1, $Gun))
        $sinirAd = $sinir.ToString('yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)
        $dosyalar = @(Get-ChildItem -LiteralPath $dir -Filter '*.jsonl' -File -ErrorAction SilentlyContinue |
                      Where-Object { $_.BaseName -cmatch '^\d{4}-\d{2}-\d{2}$' -and $_.BaseName -ge $sinirAd } |
                      Sort-Object Name)
        foreach ($d in $dosyalar) {
            $satirlar = @()
            try { $satirlar = [System.IO.File]::ReadAllLines($d.FullName) } catch { continue }
            foreach ($ln in $satirlar) {
                if ([string]::IsNullOrWhiteSpace($ln)) { continue }
                try {
                    $o = ConvertFrom-Json -InputObject $ln
                    if ($null -eq $o.ts) { continue }
                    try { if ([datetime]::Parse($o.ts, [Globalization.CultureInfo]::InvariantCulture) -lt $sinir) { continue } } catch { }
                    $sonuc.Add($o)
                } catch { }
            }
        }
    } catch { }
    return @($sonuc.ToArray())
}

function Compress-BeyinMakbuz {
    # 90 gunden eski gunluk makbuz dosyalarini makbuz\arsiv\YYYY-MM.jsonl'e katlar.
    # arsivle.ps1 -Uygula cagirir. Donus: katlanan dosya sayisi.
    param($Paths, [int]$OlderThanDays = 90)
    $n = 0
    try {
        $dir = $Paths.Makbuz
        if (-not $dir -or -not (Test-Path -LiteralPath $dir)) { return 0 }
        $sinirAd = (Get-Date).AddDays(-$OlderThanDays).ToString('yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)
        $arsiv = Join-Path $dir 'arsiv'
        $eski = @(Get-ChildItem -LiteralPath $dir -Filter '*.jsonl' -File -ErrorAction SilentlyContinue |
                  Where-Object { $_.BaseName -cmatch '^\d{4}-\d{2}-\d{2}$' -and $_.BaseName -lt $sinirAd } |
                  Sort-Object Name)
        if ($eski.Count -eq 0) { return 0 }
        New-Item -ItemType Directory -Force -Path $arsiv | Out-Null
        $enc = New-Object System.Text.UTF8Encoding($false)
        $sayac = [ref]0
        Invoke-BeyinWithLock -LockPath (Join-Path $dir 'makbuz.lock') -TimeoutSeconds 5 -Action {
            foreach ($d in $eski) {
                # SIRA: once TASI (acik dosyada burada duser, arsive hic yazilmaz),
                # sonra ekle, sonra geciciyi sil. Eski sira (ekle -> sil) silme
                # basarisiz olunca ayni gunu ikinci kez katliyordu (2026-09-16).
                $gecici = $d.FullName + '.katlaniyor'
                Move-Item -LiteralPath $d.FullName -Destination $gecici -ErrorAction Stop
                $hedef = Join-Path $arsiv ($d.BaseName.Substring(0, 7) + '.jsonl')
                $icerik = [System.IO.File]::ReadAllText($gecici)
                if ($icerik -and -not $icerik.EndsWith("`n")) { $icerik += "`n" }
                [System.IO.File]::AppendAllText($hedef, $icerik, $enc)
                Remove-Item -LiteralPath $gecici -Force -ErrorAction SilentlyContinue
                $sayac.Value = $sayac.Value + 1
            }
        }
        $n = [int]$sayac.Value
    } catch { }
    return $n
}

# ============================================================================
# NIYET  (Faz 1B, 2026-09-15)
# ----------------------------------------------------------------------------
# NEDEN: yon akisi geriye donuktu - motor ne yapildigini kaydediyor, ne
# yapilmak istendigini hicbir yerde tutmuyordu. current-context.md 10 gun
# bayat kalabiliyordu. Niyet tek satirlik, kullanicinin kendi yazdigi ileriye
# donuk hedef: oturum acilisinda iki ajana da enjekte edilir, ozetleyici
# oturum sonunda "niyete ulasildi mi" diye yazar. 7 gunden eski niyet
# enjekte EDILMEZ (bayat hedef yanlis yonlendirir); doktor uyarir.
# Dosya: motor\scripts\.state\niyet.json  {v,text,project,ts,agent}
# ============================================================================
function Get-BeyinNiyet {
    param([hashtable]$Paths, [int]$MaxGun = 7)
    try {
        $f = Join-Path $Paths.ScrState 'niyet.json'
        if (-not (Test-Path -LiteralPath $f)) { return $null }
        $o = Get-Content -LiteralPath $f -Raw -Encoding UTF8 | ConvertFrom-Json
        if (-not $o -or -not $o.text) { return $null }
        $ts = [datetime]::Parse([string]$o.ts, [Globalization.CultureInfo]::InvariantCulture)
        $yas = ((Get-Date) - $ts).TotalDays
        if ($yas -gt $MaxGun) { return $null }
        return @{
            Text    = [string]$o.text
            Project = [string]$o.project
            Ts      = $ts
            Agent   = [string]$o.agent
            AgeDays = [math]::Round($yas, 1)
        }
    } catch { return $null }
}

# ============================================================================
# AKTARIM (HANDOFF) KANALI  (2026-10-04, plan #11)  -  beyin aktar
# ----------------------------------------------------------------------------
# Codex -> Claude (ve tersi) icin yapili soru/handoff kaydi. Dosya basina bir
# JSON: .state\handoff\<id>.json. session-start hedef ajanin yeni oturumunda
# '[Hafiza: Aktarim]' blogu basar; -Tamam kapatir; 7 gunden eski kapali
# kayitlar handoff\arsiv altina tasinir. Turetilmis gorunum:
# 10-command-center\aktarimlar.md (her mutasyonda yeniden yazilir).
# ============================================================================
function Test-BeyinHandoffId {
    param([string]$Id)
    return [bool]($Id -and $Id -match '^\d{8}T\d{6}-[a-f0-9]{4}$')
}

function Get-BeyinHandoff {
    param([hashtable]$Paths, [string]$Id)
    if (-not (Test-BeyinHandoffId -Id $Id)) { return $null }
    foreach ($dir in @($Paths.Handoff, (Join-Path $Paths.Handoff 'arsiv'))) {
        $f = Join-Path $dir "$Id.json"
        if (Test-Path -LiteralPath $f) {
            try { return (Get-Content -LiteralPath $f -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { return $null }
        }
    }
    return $null
}

function Set-BeyinHandoff {
    # Yazar ve @{ Ok; Hata } doner. Asla firlatmaz.
    param([hashtable]$Paths, $Kayit)
    try {
        if (-not (Test-BeyinHandoffId -Id ([string]$Kayit.id))) { return @{ Ok = $false; Hata = "gecersiz kimlik: $($Kayit.id)" } }
        New-Item -ItemType Directory -Force -Path $Paths.Handoff -ErrorAction Stop | Out-Null
        $f = Join-Path $Paths.Handoff "$($Kayit.id).json"
        Write-BeyinText -Path $f -Text (ConvertTo-Json -InputObject $Kayit -Depth 4 -Compress)
        if (-not (Test-Path -LiteralPath $f)) { return @{ Ok = $false; Hata = 'dosya olusmadi' } }
        return @{ Ok = $true; Hata = '' }
    } catch { return @{ Ok = $false; Hata = $_.Exception.Message } }
}

function Get-BeyinHandoffListe {
    # Acik kayitlar (ts'ye gore eski->yeni); -Hepsi ile arsiv dahil kapalilar da.
    param([hashtable]$Paths, [switch]$Hepsi)
    $liste = New-Object System.Collections.Generic.List[object]
    $dirs = @($Paths.Handoff)
    if ($Hepsi) { $dirs += (Join-Path $Paths.Handoff 'arsiv') }
    foreach ($dir in $dirs) {
        if (-not (Test-Path -LiteralPath $dir)) { continue }
        foreach ($f in @(Get-ChildItem -LiteralPath $dir -Filter '*.json' -File -ErrorAction SilentlyContinue)) {
            try {
                $o = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
                if (-not $o -or -not $o.id -or -not $o.question) { continue }
                if (-not $Hepsi -and $o.status -eq 'tamam') { continue }
                $liste.Add($o)
            } catch { }
        }
    }
    return @($liste | Sort-Object -Property ts)
}

function Get-BeyinHandoffAcik {
    # Hedef ajana (ve istenirse projeye) gore acik aktarimlar.
    param([hashtable]$Paths, [string]$Kime = '', [string]$Proje = '')
    $acik = @(Get-BeyinHandoffListe -Paths $Paths)
    if ($Kime)  { $acik = @($acik | Where-Object { [string]$_.to -eq $Kime }) }
    # TESLIM SUZGECI (2026-10-07): eskiden vault disinda yalniz from.project == bu proje
    # gosteriliyordu; bir ajana ACIKCA yazilmis mesaj, gonderenin klasoru farkliysa HIC
    # ulasmiyordu (olculdu: Claude'un Beyin/agentchef etiketli iki aktarimini codex-chef
    # klasorundeki Codex hic gormedi). Simdi: devir yalniz kendi projesinde; diger turler
    # toProject verilmisse yalniz o projede, verilmemisse ('' ya da '*') her yerde.
    if ($Proje) {
        $acik = @($acik | Where-Object {
            $hp = $(if ($_.PSObject.Properties['toProject']) { [string]$_.toProject } else { '' })
            if ([string]$_.kind -eq 'devir') { [string]$_.from.project -eq $Proje }
            elseif ($hp -and $hp -ne '*') { $hp -eq $Proje }
            else { $true }
        })
    }
    return $acik
}

function Update-BeyinAktarimlarMd {
    # Turetilmis gorunum + arsivleme. Kuratorlu alana yazmaz (10-command-center turetilmis dosya).
    param([hashtable]$Paths)
    $r = @{ Ok = $false; Yol = ''; Acik = 0; Kapali = 0 }
    try {
        # 7 gunden eski kapali kayitlari arsive tasi
        $arsiv = Join-Path $Paths.Handoff 'arsiv'
        if (Test-Path -LiteralPath $Paths.Handoff) {
            foreach ($f in @(Get-ChildItem -LiteralPath $Paths.Handoff -Filter '*.json' -File -ErrorAction SilentlyContinue)) {
                try {
                    $o = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
                    if ($o.status -ne 'tamam' -or -not $o.doneTs) { continue }
                    $dts = [datetime]::Parse([string]$o.doneTs, [Globalization.CultureInfo]::InvariantCulture)
                    if (((Get-Date) - $dts).TotalDays -gt 7) {
                        New-Item -ItemType Directory -Force -Path $arsiv | Out-Null
                        Move-Item -LiteralPath $f.FullName -Destination (Join-Path $arsiv $f.Name) -Force
                    }
                } catch { }
            }
        }
        $hepsi = @(Get-BeyinHandoffListe -Paths $Paths -Hepsi)
        $acik = @($hepsi | Where-Object { $_.status -ne 'tamam' })
        $kapali = @($hepsi | Where-Object { $_.status -eq 'tamam' } | Sort-Object -Property doneTs -Descending | Select-Object -First 30)
        $r.Acik = $acik.Count; $r.Kapali = $kapali.Count
        $inv = [Globalization.CultureInfo]::InvariantCulture
        # Guvenilmez metin vault notuna yaziliyor: tablo ayiricisi, satir sonu, wikilink ve
        # HTML acilisi notrlestirilir (Obsidian'da baglanti/etiket uretmesin).
        function Kisa([string]$T, [int]$N) { $t = [string]$T; if ($t.Length -gt $N) { $t = $t.Substring(0, $N - 3) + '...' }; return ((($t -replace '\|', '/') -replace '\r?\n', ' ') -replace '\[\[', '[ [' -replace '\]\]', '] ]' -replace '<', '&lt;') }
        function Zaman([string]$T) { try { return ([datetime]::Parse($T, $inv)).ToString('yyyy-MM-dd HH:mm', $inv) } catch { return '' } }
        $sb = New-Object System.Text.StringBuilder
        [void]$sb.AppendLine('---')
        [void]$sb.AppendLine('type: "derived"')
        [void]$sb.AppendLine('title: "Ajanlar arasi aktarimlar"')
        [void]$sb.AppendLine("updated: `"$((Get-Date).ToString('o', $inv))`"")
        [void]$sb.AppendLine('---')
        [void]$sb.AppendLine('# Ajanlar arasi aktarimlar')
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine('> **Turetilmis dosya** - `beyin aktar` her kayit/kapatmada yeniden yazar; elle duzenleme. Kaynak: `motor/scripts/.state/handoff/`.')
        [void]$sb.AppendLine('> Kaydet: `beyin aktar "soru" -Kime claude|codex` - kapat: `beyin aktar -Tamam <id>`')
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine("## Acik ($($acik.Count))")
        [void]$sb.AppendLine('')
        if ($acik.Count -eq 0) { [void]$sb.AppendLine('(acik aktarim yok)') }
        else {
            [void]$sb.AppendLine('| Kimlik | Kimden -> Kime | Proje | Zaman | Soru / handoff | Kanit | Sonraki |')
            [void]$sb.AppendLine('| --- | --- | --- | --- | --- | --- | --- |')
            foreach ($h in $acik) { [void]$sb.AppendLine("| ``$($h.id)`` | $($h.from.agent) -> $($h.to) | $(Kisa $h.from.project 24) | $(Zaman $h.ts) | $(Kisa $h.question 220) | $(Kisa $h.evidence 120) | $(Kisa $h.next 120) |") }
        }
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine("## Kapali (son $($kapali.Count))")
        [void]$sb.AppendLine('')
        if ($kapali.Count -eq 0) { [void]$sb.AppendLine('(henuz kapanan yok)') }
        else {
            [void]$sb.AppendLine('| Kimlik | Kimden -> Kime | Proje | Kapatan | Kapanis | Soru / handoff |')
            [void]$sb.AppendLine('| --- | --- | --- | --- | --- | --- |')
            foreach ($h in $kapali) { [void]$sb.AppendLine("| ``$($h.id)`` | $($h.from.agent) -> $($h.to) | $(Kisa $h.from.project 24) | $($h.doneBy) | $(Zaman $h.doneTs) | $(Kisa $h.question 160) |") }
        }
        $yol = Join-Path (Join-Path $Paths.Vault '10-command-center') 'aktarimlar.md'
        Write-BeyinText -Path $yol -Text $sb.ToString()
        $r.Yol = $yol; $r.Ok = (Test-Path -LiteralPath $yol)
    } catch { }
    return $r
}

function Add-BeyinHandoff {
    # TEK KAYIT YOLU (2026-10-06): aktar.ps1 ve pano brifingi ayni fonksiyondan yazar.
    # Sema v2: kind (soru|brifing|devir), ref (tekillestirme anahtari), coordinator.
    # Alanlar Protect-BeyinSecrets'ten FAIL-CLOSED gecer; yazim geri okunur.
    # Donus: @{ Ok; Id; Hata; Kod; Maske }  Kod: KAYDEDILDI | BOS | REDAKSIYON_DUSTU | YAZILAMADI
    param([hashtable]$Paths, [string]$Metin, [string]$Kime, [string]$Kanit = '', [string]$Kapsam = '', [string]$Risk = '',
          [string]$Sonraki = '', [string]$Proje = '', [string]$Kind = 'soru', [string]$Ref = '', [string]$Coordinator = '',
          [string]$FromAgent = '', [string]$FromSession = '', [switch]$GorunumYok, [string]$HedefProje = '')
    $r = @{ Ok = $false; Id = ''; Hata = ''; Kod = ''; Maske = 0 }
    $kisalt = { param([string]$T, [int]$Max) $t = ([string]$T -replace '\s+', ' ').Trim(); if ($t.Length -gt $Max) { $t = $t.Substring(0, $Max - 3) + '...' }; $t }
    # HEDEF DOGRULAMASI (2026-10-07): claude|codex disinda bir hedefe yazilan aktarimi hic
    # kimse almazdi (ornek: BEYIN_BRIFING_KIME yazim hatasi).
    $Kime = ([string]$Kime).Trim().ToLowerInvariant()
    if ($Kime -ne 'claude' -and $Kime -ne 'codex') { $r.Kod = 'HEDEF_GECERSIZ'; $r.Hata = "hedef ajan claude ya da codex olmali: '$Kime'"; return $r }
    # Kisa alanlar: yalniz guvenli karakterler, sinirli uzunluk (gorunumde ve baglamda basilir).
    $temiz = { param([string]$T, [int]$Max) $t = ([string]$T -replace '[^\p{L}\p{Nd} ._@*:()-]', '').Trim(); if ($t.Length -gt $Max) { $t = $t.Substring(0, $Max) }; $t }
    $Proje = & $temiz $Proje 64; $HedefProje = & $temiz $HedefProje 64; $Ref = & $temiz $Ref 120
    $Coordinator = & $temiz $Coordinator 64; $FromAgent = & $temiz $FromAgent 16; $FromSession = & $temiz $FromSession 64
    # MASKE ONCE, KISALTMA SONRA (2026-10-07): eskiden once 600/300'e kesiliyordu; sinirda
    # kesilen bir anahtar desenin asgari uzunlugunun altina dusup kismen kaciyordu.
    $hamAlan = [ordered]@{ question = $Metin; evidence = $Kanit; scope = $Kapsam; risk = $Risk; next = $Sonraki }
    $sinir = @{ question = 600; evidence = 300; scope = 300; risk = 300; next = 300 }
    $alanlar = [ordered]@{}
    foreach ($ad in @($hamAlan.Keys)) {
        $deger = ([string]$hamAlan[$ad] -replace '\s+', ' ').Trim()
        if ($deger) {
            $prot = Protect-BeyinSecrets -Text $deger -Vault $Paths.Vault
            if ([int]$prot.Failed -gt 0) { $r.Kod = 'REDAKSIYON_DUSTU'; $r.Hata = "$($prot.Failed) desen uygulanamadi"; return $r }
            $deger = [string]$prot.Text
            $r.Maske += [int]$prot.Redactions
        }
        $alanlar[$ad] = (& $kisalt $deger $sinir[$ad])
    }
    if (-not $alanlar.question) { $r.Kod = 'BOS'; $r.Hata = 'bos soru/handoff metni'; return $r }
    $inv = [Globalization.CultureInfo]::InvariantCulture
    $id = (Get-Date).ToString('yyyyMMddTHHmmss', $inv) + '-' + ([guid]::NewGuid().ToString('N').Substring(0, 4))
    $kayit = [ordered]@{
        v = 2; id = $id; ts = (Get-Date).ToString('o', $inv)
        from = [ordered]@{ agent = $FromAgent; session = $FromSession; project = $Proje }
        to = $Kime; toProject = $HedefProje; kind = $(if ($Kind) { $Kind } else { 'soru' }); ref = $Ref; coordinator = $Coordinator
        question = $alanlar.question; evidence = $alanlar.evidence; scope = $alanlar.scope; risk = $alanlar.risk; next = $alanlar.next
        status = 'acik'; doneBy = ''; doneTs = ''
    }
    $yaz = Set-BeyinHandoff -Paths $Paths -Kayit $kayit
    if (-not $yaz.Ok) { $r.Kod = 'YAZILAMADI'; $r.Hata = $yaz.Hata; return $r }
    $geri = Get-BeyinHandoff -Paths $Paths -Id $id
    if (-not $geri -or [string]$geri.question -ne [string]$alanlar.question) { $r.Kod = 'YAZILAMADI'; $r.Hata = 'geri okuma farkli ya da yok'; return $r }
    if (-not $GorunumYok) { $null = Update-BeyinAktarimlarMd -Paths $Paths }
    $r.Ok = $true; $r.Id = $id; $r.Kod = 'KAYDEDILDI'
    return $r
}

# ============================================================================
# KORUNAN SURECLER (BB5, 2026-10-06): kill guard ve session-start kullanir.
# ============================================================================
function Get-BeyinAtaZinciri {
    # Verilen PID'den yukari ata zinciri: @(@{ Pid; Ad }) (kendisi dahil). CIM, seviye basina ~40 ms.
    param([int]$ProcessId = $PID, [int]$Derinlik = 8)
    $z = New-Object System.Collections.Generic.List[object]
    $cur = $ProcessId
    for ($i = 0; $i -lt $Derinlik -and $cur -gt 0; $i++) {
        try { $w = Get-CimInstance Win32_Process -Filter "ProcessId = $cur" -ErrorAction Stop } catch { break }
        if (-not $w) { break }
        $z.Add(@{ Pid = [int]$w.ProcessId; Ad = [string]$w.Name })
        $ust = [int]$w.ParentProcessId
        if ($ust -eq $cur -or $ust -le 4) { break }
        $cur = $ust
    }
    return $z
}

function Get-BeyinAjanPid {
    # Bu kancayi baslatan ajan sureci: ata zincirinde ilk claude/codex/node.
    param([int]$ProcessId = $PID)
    foreach ($a in @(Get-BeyinAtaZinciri -ProcessId $ProcessId)) {
        if ([string]$a.Ad -match '^(claude|codex|node)(\.exe)?$') { return [int]$a.Pid }
    }
    return 0
}

function Get-BeyinKorunanPid {
    # PID -> aciklama. Kaynaklar: bu surecin ata zinciri, son 24 saatte guncellenmis
    # oturum durumlarindaki canli ajan PID'leri, .state\korunan-pid.json {"pids":[..]}.
    param([hashtable]$Paths)
    $h = @{}
    foreach ($a in @(Get-BeyinAtaZinciri -ProcessId $PID)) { if ($a.Pid -ne $PID) { $h[[int]$a.Pid] = "ata surec: $($a.Ad)" } }
    try {
        $sinir = (Get-Date).AddHours(-24)
        foreach ($f in @(Get-ChildItem -LiteralPath $Paths.Sessions -Filter '*.json' -File -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -ge $sinir })) {
            $ham = [IO.File]::ReadAllText($f.FullName)
            $m = [regex]::Match($ham, '"pid"\s*:\s*(\d+)')
            if ($m.Success -and [int]$m.Groups[1].Value -gt 0) {
                $sp = [int]$m.Groups[1].Value
                if (Get-Process -Id $sp -ErrorAction SilentlyContinue) { if (-not $h.ContainsKey($sp)) { $h[$sp] = 'ajan oturumu' } }
            }
        }
    } catch { }
    try {
        $kf = Join-Path $Paths.ScrState 'korunan-pid.json'
        if (Test-Path -LiteralPath $kf) {
            foreach ($m in [regex]::Matches([IO.File]::ReadAllText($kf), '\d+')) { $n = [int]$m.Value; if ($n -gt 4 -and -not $h.ContainsKey($n)) { $h[$n] = 'korunan-pid.json' } }
        }
    } catch { }
    return $h
}

# ============================================================================
# TESLIM HAKKI (2026-10-07): ayni oturumda bir aktarim TEK KEZ gosterilir. Uc teslim yolu
# (session-start, prompt-counter, kill-guard-on.mjs) ayni depoyu kullanir:
# .state\handoff-teslim\<oturum>\<id> isaret dosyasi ATOMIK olusturulur (CreateNew /
# Node 'wx'); olusturabilen gosterir, digerleri atlar. Eskiden her yolun kendi "goruldu"
# listesi vardi: acilista gosterilen ilk arac cagrisinda tekrar geliyordu, paralel arac
# cagrilari ayni mesaji iki kez veriyordu (kod incelemesi, 2026-10-07).
# ============================================================================
function Get-BeyinTeslimDizini {
    param([hashtable]$Paths, [string]$SessionKey)
    return (Join-Path (Join-Path $Paths.ScrState 'handoff-teslim') $SessionKey)
}

function Get-BeyinTeslimEdilen {
    # Bu oturumda gosterilmis aktarim kimlikleri (isaret dosyalari).
    param([hashtable]$Paths, [string]$SessionKey)
    try {
        $d = Get-BeyinTeslimDizini -Paths $Paths -SessionKey $SessionKey
        if (-not (Test-Path -LiteralPath $d)) { return @() }
        return @(Get-ChildItem -LiteralPath $d -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -notlike '*.damga' } | ForEach-Object { $_.Name })
    } catch { return @() }
}

function Request-BeyinTeslimHakki {
    # $true: isaret bu cagriyla olusturuldu, goster. $false: baskasi zaten gosterdi ya da hata.
    param([hashtable]$Paths, [string]$SessionKey, [string]$Id)
    try {
        if (-not (Test-BeyinHandoffId -Id $Id) -or -not $SessionKey) { return $false }
        $d = Get-BeyinTeslimDizini -Paths $Paths -SessionKey $SessionKey
        New-Item -ItemType Directory -Force -Path $d -ErrorAction Stop | Out-Null
        $fs = [IO.File]::Open((Join-Path $d $Id), [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        $fs.Dispose()
        return $true
    } catch { return $false }
}

function Close-BeyinHandoff {
    # Acik aktarimi kapatir (status=tamam). Zaten kapaliysa $false.
    param([hashtable]$Paths, [string]$Id, [string]$DoneBy = '')
    try {
        $h = Get-BeyinHandoff -Paths $Paths -Id $Id
        if (-not $h -or [string]$h.status -ne 'acik') { return $false }
        $h.status = 'tamam'; $h.doneBy = $DoneBy; $h.doneTs = (Get-Date).ToString('o', [Globalization.CultureInfo]::InvariantCulture)
        return [bool](Set-BeyinHandoff -Paths $Paths -Kayit $h).Ok
    } catch { return $false }
}

function Get-BeyinDevirMetni {
    # Flush ozetindeki '**Devir:**' bolumu (sonraki '**Baslik:**' satirina ya da sona kadar).
    # 'yok' ya da 12 karakterden kisa ise bos dize.
    param([string]$Ozet)
    if (-not $Ozet) { return '' }
    $m = [regex]::Match($Ozet, '(?ms)^\*\*Devir:\*\*[ \t]*(.*?)(?=^\*\*[^*\r\n]+:\*\*|\z)')
    if (-not $m.Success) { return '' }
    $t = ($m.Groups[1].Value -replace '\s+', ' ').Trim()
    if ($t.Length -lt 12 -or $t -match '^(?i)\(?yok\)?\.?$') { return '' }
    return $t
}

function Add-BeyinDevir {
    # DEVIR (BB3, 2026-10-06; AgentSpace handoff dersi): oturum kapanirken ya da
    # sikistirilmadan once ozetleyicinin yazdigi "nerede kaldim / siradaki adim /
    # dokunulmayacak dosyalar" metni, AYNI AJANIN AYNI PROJEDEKI bir sonraki acilisina
    # TEK ATIMLIK aktarim olarak gider (gosterilince kapanir). Ayni oturumun onceki
    # acik devri kapatilir: gecerli olan son devirdir.
    param([hashtable]$Paths, [string]$Ozet, [string]$Agent, [string]$Proje, [string]$SessionKey)
    $r = @{ Ok = $false; Id = ''; Kod = 'YOK' }
    $metin = Get-BeyinDevirMetni -Ozet $Ozet
    if (-not $metin) { return $r }
    $ref = "devir@$SessionKey"
    foreach ($h in @(Get-BeyinHandoffListe -Paths $Paths)) {
        if ([string]$h.kind -eq 'devir' -and [string]$h.ref -eq $ref) { $null = Close-BeyinHandoff -Paths $Paths -Id ([string]$h.id) -DoneBy 'devir (yenisi yazildi)' }
    }
    $a = Add-BeyinHandoff -Paths $Paths -Metin $metin -Kime $Agent -Proje $Proje -Kind 'devir' -Ref $ref -FromAgent $Agent -FromSession $SessionKey
    $r.Ok = [bool]$a.Ok; $r.Id = [string]$a.Id; $r.Kod = [string]$a.Kod
    return $r
}

function Sync-BeyinPanoBrifing {
    # TUR BASI BRIFING (2026-10-06, AgentSpace briefingLedger dersi): pano karti review
    # ya da blocked durumuna gecince karsi ajana (koordinator tarafina) TEK brifing
    # aktarimi yazilir; ayni gecis (kart@durum@gecis-zamani) bir daha yazilmaz, kart
    # ilerleyince eski brifing kendiliginden kapanir. Node BASLATILMAZ; board.json
    # damgasi degismediyse dosya bile okunmaz (~1 ms).
    param([hashtable]$Paths, [string]$Tetik = '')
    $r = @{ Yeni = 0; Kapanan = 0; Ms = 0 }
    $sw = [Diagnostics.Stopwatch]::StartNew()
    try {
        if (-not $Paths.Board -or -not (Test-Path -LiteralPath $Paths.Board)) { return $r }
        $damgaF = Join-Path $Paths.ScrState 'pano-brifing-son.dat'
        $mt = [string](Get-Item -LiteralPath $Paths.Board).LastWriteTimeUtc.Ticks
        $eski = ''
        if (Test-Path -LiteralPath $damgaF) { try { $eski = ([IO.File]::ReadAllText($damgaF)).Trim() } catch { } }
        if ($eski -eq $mt) { $r.Ms = [int]$sw.ElapsedMilliseconds; return $r }
        $st = Get-Content -LiteralPath $Paths.Board -Raw -Encoding UTF8 | ConvertFrom-Json
        $inv = [Globalization.CultureInfo]::InvariantCulture
        $kartDurum = @{}
        foreach ($k in @($st.tasks)) { if ($k) { $kartDurum[[string]$k.id] = [string]$k.status } }
        $varRef = @{}
        foreach ($h in @(Get-BeyinHandoffListe -Paths $Paths -Hepsi)) {
            if (-not ($h.PSObject.Properties['ref'] -and $h.ref)) { continue }
            $varRef[[string]$h.ref] = $true
            if ($h.status -ne 'tamam' -and $h.PSObject.Properties['kind'] -and $h.kind -eq 'brifing') {
                $parca = ([string]$h.ref) -split '@'
                if ($parca.Count -ge 2 -and $kartDurum.ContainsKey($parca[0]) -and $kartDurum[$parca[0]] -ne $parca[1]) {
                    $h.status = 'tamam'; $h.doneBy = 'pano (kart ilerledi)'; $h.doneTs = (Get-Date).ToString('o', $inv)
                    if ((Set-BeyinHandoff -Paths $Paths -Kayit $h).Ok) { $r.Kapanan++ }
                }
            }
        }
        $varsayilanKime = 'claude'
        try { $varsayilanKime = ([string](Get-BeyinAyar 'BEYIN_BRIFING_KIME' (Get-BeyinAyarVars 'BEYIN_BRIFING_KIME'))).Trim().ToLowerInvariant() } catch { }
        if ($varsayilanKime -ne 'claude' -and $varsayilanKime -ne 'codex') { $varsayilanKime = 'claude' }   # yazim hatasi: brifing kaybolmasin
        foreach ($k in @($st.tasks)) {
            if (-not $k) { continue }
            $durum = [string]$k.status
            if ($durum -ne 'review' -and $durum -ne 'blocked') { continue }
            $an = ''
            foreach ($hx in @($k.history)) { if ($hx -and [string]$hx.to -eq $durum -and $hx.at) { $an = [string]$hx.at } }
            if (-not $an) { $an = [string]$k.updatedAt }
            $ref = "$($k.id)@$durum@$an"
            if ($varRef.ContainsKey($ref)) { continue }
            $sahip = $(if ($k.owner) { [string]$k.owner.agent } else { '' })
            $kime = $(if ($sahip -eq 'codex') { 'claude' } elseif ($sahip -eq 'claude') { 'codex' } else { $varsayilanKime })
            $rapor = @($k.reports) | Select-Object -Last 1
            $sonH = @($k.handoffs) | Select-Object -Last 1
            $ozet = ''
            if ($sonH) { foreach ($alan in @('outcome', 'summary', 'text', 'body')) { if ($sonH.PSObject.Properties[$alan] -and $sonH.$alan) { $ozet = [string]$sonH.$alan; break } } }
            $metin = $(if ($durum -eq 'review') { "$($k.id) incelemeye hazir: $($k.title)" } else { "$($k.id) TAKILDI (blocked): $($k.title)" })
            $kanit = "rapor: $(if ($rapor) { $rapor } else { 'YOK' }); kanit kaydi: $(@($k.evidence).Count)$(if ($ozet) { '; son devir: ' + $ozet })"
            $sonraki = $(if ($durum -eq 'review') { "dogrula: beyin pano show --task $($k.id); gecerse insan onayi (onayla $($k.id)) + transition done" } else { "karar ver: beyin pano show --task $($k.id)" })
            $proje = $(if ($k.writeScope) { [string]$k.writeScope.repo } else { '' })
            $a = Add-BeyinHandoff -Paths $Paths -Metin $metin -Kime $kime -Kanit $kanit -Sonraki $sonraki -Proje $proje -Kind 'brifing' -Ref $ref `
                -Coordinator ([string]$k.ownerCoordinator) -FromAgent 'pano' -GorunumYok
            if ($a.Ok) {
                $r.Yeni++; $varRef[$ref] = $true
                Write-BeyinMakbuz -Paths $Paths -Script 'aktar' -Outcome 'BRIFING_KAYDEDILDI' -Agent 'pano' -Reason $Tetik -Note "$($a.Id) ref=$ref -> $kime"
            }
        }
        if ($r.Yeni -gt 0 -or $r.Kapanan -gt 0) { $null = Update-BeyinAktarimlarMd -Paths $Paths }
        Write-BeyinText -Path $damgaF -Text $mt
    } catch { }
    $r.Ms = [int]$sw.ElapsedMilliseconds
    return $r
}

# INSAN ONAYI (2026-10-06, kullanici karari): pano karti 'done' icin insan onayi.
# Kayit .state\approvals\<TASK>.json (AgentChef K12 ayni yeri okur: board.json'un
# klasoru). Yazan yalniz iki insan kanali: kullanicinin GERCEK mesajinda tek satir
# 'onayla TASK-x' (prompt-counter) ve etkilesimli terminalde 'beyin pano onayla'.
# 7 gun gecerli, tek kullanimlik (done gecisinde 'kullanildi' damgalanir).
function Add-BeyinOnay {
    param([hashtable]$Paths, [string]$TaskId, [string]$Kanal = 'sohbet', [string]$Ajan = '', [string]$Session = '')
    $r = @{ Ok = $false; Hata = ''; Yol = '' }
    try {
        if ($TaskId -cnotmatch '^TASK-\d+$') { $r.Hata = "gecersiz kart kimligi: $TaskId"; return $r }
        $dir = Join-Path $Paths.ScrState 'approvals'
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        $inv = [Globalization.CultureInfo]::InvariantCulture
        $o = [ordered]@{ v = 1; taskId = $TaskId; nonce = [guid]::NewGuid().ToString('N').Substring(0, 12); approvedAt = (Get-Date).ToString('o', $inv)
                         kanal = $Kanal; ajan = $Ajan; session = $Session; kullanildi = ''; kullanan = '' }
        $f = Join-Path $dir "$TaskId.json"
        Write-BeyinText -Path $f -Text (ConvertTo-Json -InputObject $o -Compress)
        $r.Ok = [bool](Test-Path -LiteralPath $f); $r.Yol = $f
    } catch { $r.Hata = $_.Exception.Message }
    return $r
}

function Get-BeyinOnay {
    # Gecerli (Gun icinde, kullanilmamis) onay kaydi ya da $null.
    param([hashtable]$Paths, [string]$TaskId, [int]$Gun = 7)
    try {
        if ($TaskId -cnotmatch '^TASK-\d+$') { return $null }
        $f = Join-Path (Join-Path $Paths.ScrState 'approvals') "$TaskId.json"
        if (-not (Test-Path -LiteralPath $f)) { return $null }
        $o = Get-Content -LiteralPath $f -Raw -Encoding UTF8 | ConvertFrom-Json
        if ([string]$o.taskId -cne $TaskId -or [string]$o.kullanildi) { return $null }
        $ts = [datetime]::Parse([string]$o.approvedAt, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind)
        if ($ts.Kind -eq [DateTimeKind]::Utc) { $ts = $ts.ToLocalTime() }
        if (((Get-Date) - $ts).TotalDays -gt $Gun) { return $null }
        return $o
    } catch { return $null }
}

function Use-BeyinOnay {
    param([hashtable]$Paths, [string]$TaskId, [string]$Kullanan = '')
    try {
        $o = Get-BeyinOnay -Paths $Paths -TaskId $TaskId
        if (-not $o) { return $false }
        $o.kullanildi = (Get-Date).ToString('o', [Globalization.CultureInfo]::InvariantCulture)
        $o.kullanan = $Kullanan
        Write-BeyinText -Path (Join-Path (Join-Path $Paths.ScrState 'approvals') "$TaskId.json") -Text (ConvertTo-Json -InputObject $o -Compress)
        return $true
    } catch { return $false }
}

# ============================================================================
# ORTAK GOREV PANOSU - OKUMA KATMANI  (2026-10-04, plan #13/#14)  -  beyin pano
# ----------------------------------------------------------------------------
# board.json AgentChef coordination-board.mjs tarafindan yazilir (sema v3: owner,
# writeScope, leaseUntil, brief, evidence). Burasi yalniz OKUR: session-start
# isletim satiri ("Pano: N acik, M bu projede"), sahiplik uyarisi (acik kartin
# yazma kapsami bu repoya dusuyorsa) ve turetilmis pano.md. Node BASLATILMAZ.
# ============================================================================
function Get-BeyinAgentChefKok {
    # AGENTCHEF YOLU (2026-10-07): ayar (BEYIN_AGENTCHEF_KOK) gecerli bir checkout'u gosteriyorsa
    # o; degilse ~\agentchef* altinda coordination-board.mjs tasiyan kurulumlardan package.json
    # surumu en yuksek olan; o da yoksa Desktop\codex-chef. Eskiden yol tek bir surum klasorune
    # sabitti: AgentChef baska klasore kurulunca pano ve bekci SESSIZCE koparlardi (denetim).
    # Donus: @{ Yol; Kaynak (ayar|tarama|varsayilan|yok); Surum }
    $r = @{ Yol = ''; Kaynak = 'yok'; Surum = '' }
    $gecerli = { param([string]$K) $K -and (Test-Path -LiteralPath (Join-Path $K 'scripts\coordination-board.mjs') -PathType Leaf) }
    $surum = { param([string]$K) try { [string]((Get-Content -LiteralPath (Join-Path $K 'package.json') -Raw -Encoding UTF8 | ConvertFrom-Json).version) } catch { '' } }
    $ayar = ''
    try { $ayar = [string](Get-BeyinAyar 'BEYIN_AGENTCHEF_KOK' '') } catch { }
    if (& $gecerli $ayar) { $r.Yol = $ayar; $r.Kaynak = 'ayar'; $r.Surum = (& $surum $ayar); return $r }
    $adaylar = @(Get-ChildItem -LiteralPath $env:USERPROFILE -Directory -Filter 'agentchef*' -ErrorAction SilentlyContinue | Where-Object { & $gecerli $_.FullName })
    $enIyi = $null; $enIyiV = $null
    foreach ($a in $adaylar) {
        $s = & $surum $a.FullName
        $v = $null; try { $v = [version](($s -split '[-+]')[0]) } catch { }
        if (-not $enIyi -or ($v -and (-not $enIyiV -or $v -gt $enIyiV))) { $enIyi = $a.FullName; $enIyiV = $v; $r.Surum = $s }
    }
    if ($enIyi) { $r.Yol = $enIyi; $r.Kaynak = 'tarama'; return $r }
    $vars = Join-Path $env:USERPROFILE 'Desktop\codex-chef'
    if (& $gecerli $vars) { $r.Yol = $vars; $r.Kaynak = 'varsayilan'; $r.Surum = (& $surum $vars); return $r }
    $r.Yol = $(if ($ayar) { $ayar } else { $vars })
    return $r
}

function Get-BeyinPanoDurum {
    param([hashtable]$Paths, [string]$Proje = '')
    $r = @{ Var = $false; Toplam = 0; Acik = 0; Todo = 0; Surecte = 0; Inceleme = 0; Bekleyen = 0; BekleyenKartlar = @(); Kartlar = @(); BuProje = @(); Satir = '' }
    try {
        if (-not (Test-Path -LiteralPath $Paths.Board)) { return $r }
        $st = Get-Content -LiteralPath $Paths.Board -Raw -Encoding UTF8 | ConvertFrom-Json
        if (-not $st -or -not $st.tasks) { $r.Var = $true; return $r }
        $r.Var = $true
        # AgentChef 1.3.3 (sema v4): 'blocked' ACIK sayilir, 'cancelled' kapali. v3 panolarda bu durumlar yoktur; zararsiz.
        $acik = @($st.tasks | Where-Object { $_.status -in @('todo', 'in_progress', 'review', 'blocked') })
        $r.Toplam = @($st.tasks).Count
        $r.Acik = $acik.Count
        $r.Todo = @($acik | Where-Object { $_.status -eq 'todo' }).Count
        $r.Surecte = @($acik | Where-Object { $_.status -eq 'in_progress' }).Count
        $r.Inceleme = @($acik | Where-Object { $_.status -eq 'review' }).Count
        $r.Kartlar = $acik
        # BACKLOG (2026-10-06): AgentChef create kartlari 'backlog'da acar; acik
        # sayilmaz ama gorunmez de kalmamali (12 kart acildi, pano '0 acik' diyordu).
        $r.BekleyenKartlar = @($st.tasks | Where-Object { $_.status -eq 'backlog' })
        $r.Bekleyen = $r.BekleyenKartlar.Count
        if ($Proje) {
            $r.BuProje = @($acik | Where-Object { $_.writeScope -and ([string]$_.writeScope.repo).Equals($Proje, [System.StringComparison]::OrdinalIgnoreCase) })
        }
        if ($r.Acik -gt 0) {
            $ilk = $(if ($r.BuProje.Count) { $r.BuProje[0] } else { $acik[0] })
            $r.Satir = "Pano: $($r.Acik) acik" + $(if ($Proje) { ", $($r.BuProje.Count) bu projede" } else { '' }) +
                       $(if ($r.Bekleyen -gt 0) { ", $($r.Bekleyen) bekleyen" } else { '' }) +
                       " ($($ilk.id) $(if ($ilk.owner) { $ilk.owner.agent } else { '-' })/$($ilk.status))."
        } elseif ($r.Bekleyen -gt 0) {
            $r.Satir = "Pano: 0 acik, $($r.Bekleyen) bekleyen (backlog; ilk $($r.BekleyenKartlar[0].id))."
        }
    } catch { }
    return $r
}

function Get-BeyinPanoCakisma {
    # YOL CAKISMASI (2026-10-06, AgentSpace CONFLICT-NOTICE dersi): ayni repoya yazan
    # acik kartlarin yazma kapsamlari kesisiyor mu? Esitlik ya da dizin on eki
    # ('docs' ~ 'docs/a.md'); glob iceren yolda literal onek karsilastirilir (fazla
    # raporlar, asla eksik raporlamaz). Donus: @( @{ A; B; Yol; Izole } ).
    param([object[]]$Kartlar)
    $sonuc = New-Object System.Collections.Generic.List[object]
    # BLOCKED KILIT BIRAKIR (BB6, kullanici karari 2026-10-06; AgentChef K2 ayni anlam):
    # kilitli kartin yazma kapsami baskasini engellemez, cakisma sayilmaz.
    $liste = @($Kartlar | Where-Object { $_ -and [string]$_.status -ne 'blocked' -and $_.writeScope -and @($_.writeScope.paths).Count -gt 0 })
    for ($i = 0; $i -lt $liste.Count; $i++) {
        for ($j = $i + 1; $j -lt $liste.Count; $j++) {
            $a = $liste[$i]; $b = $liste[$j]
            if (-not ([string]$a.writeScope.repo).Equals([string]$b.writeScope.repo, [System.StringComparison]::OrdinalIgnoreCase)) { continue }
            $bulundu = $false
            foreach ($pa in @($a.writeScope.paths)) {
                foreach ($pb in @($b.writeScope.paths)) {
                    $x = (([string]$pa).Trim().Replace('\', '/').ToLowerInvariant() -split '[\*\?]')[0]
                    $y = (([string]$pb).Trim().Replace('\', '/').ToLowerInvariant() -split '[\*\?]')[0]
                    while ($x.StartsWith('./')) { $x = $x.Substring(2) }
                    while ($y.StartsWith('./')) { $y = $y.Substring(2) }
                    $x = $x.TrimEnd('/'); $y = $y.TrimEnd('/')
                    if (-not $x -or -not $y) { continue }
                    if ($x -eq $y -or $x.StartsWith($y + '/') -or $y.StartsWith($x + '/')) {
                        $sonuc.Add([pscustomobject]@{ A = [string]$a.id; B = [string]$b.id; Yol = $(if ($x.Length -le $y.Length) { $x } else { $y })
                            Izole = (([string]$a.isolation -eq 'worktree') -or ([string]$b.isolation -eq 'worktree')) })
                        $bulundu = $true; break
                    }
                }
                if ($bulundu) { break }
            }
        }
    }
    return $sonuc.ToArray()
}

function Update-BeyinPanoMd {
    # Turetilmis gorunum: 10-command-center\pano.md. Kuratorlu alana yazmaz.
    param([hashtable]$Paths)
    $r = @{ Ok = $false; Yol = ''; Acik = 0 }
    try {
        $d = Get-BeyinPanoDurum -Paths $Paths
        $inv = [Globalization.CultureInfo]::InvariantCulture
        $st = $null
        if (Test-Path -LiteralPath $Paths.Board) { $st = Get-Content -LiteralPath $Paths.Board -Raw -Encoding UTF8 | ConvertFrom-Json }
        $tum = @($(if ($st) { $st.tasks } else { @() }))
        function Kisa([string]$T, [int]$N) { $t = [string]$T; if ($t.Length -gt $N) { $t = $t.Substring(0, $N - 3) + '...' }; return ($t -replace '\|', '/') -replace '\r?\n', ' ' }
        function Zaman([string]$T) { if (-not $T) { return '-' }; try { return ([datetime]::Parse($T, $inv)).ToLocalTime().ToString('MM-dd HH:mm', $inv) } catch { return $T } }
        $sb = New-Object System.Text.StringBuilder
        [void]$sb.AppendLine('---')
        [void]$sb.AppendLine('type: "derived"')
        [void]$sb.AppendLine('title: "Ortak gorev panosu"')
        [void]$sb.AppendLine("updated: `"$((Get-Date).ToString('o', $inv))`"")
        [void]$sb.AppendLine('---')
        [void]$sb.AppendLine('# Ortak gorev panosu')
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine('> **Turetilmis dosya** - `beyin pano` her degisiklikte yeniden yazar; elle duzenleme. Kaynak: `motor/scripts/.state/board.json` (AgentChef coordination-board sema v3-v5; bilinmeyen alanlar yok sayilir).')
        [void]$sb.AppendLine('> Kural: yazma kapsami iceren her delegasyondan once kart acilir; `todo -> in_progress` icin brief (7 alan) ve yazma kapsami varsa canli kira gerekir.')
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine("## Acik ($($d.Acik))")
        [void]$sb.AppendLine('')
        if ($d.Acik -eq 0) { [void]$sb.AppendLine('(acik kart yok)') }
        else {
            [void]$sb.AppendLine('| Kart | Durum | Sahip | Yazma kapsami | Kira (yerel) | Brief | Kanit | Baslik |')
            [void]$sb.AppendLine('| --- | --- | --- | --- | --- | --- | --- | --- |')
            foreach ($k in $d.Kartlar) {
                $sahip = $(if ($k.owner) { "$($k.owner.agent)$(if ($k.owner.session) { '/' + $k.owner.session })" } else { '-' })
                $ws = $(if ($k.writeScope) { "$($k.writeScope.repo): $(Kisa (@($k.writeScope.paths) -join ', ') 90)" } else { '-' })
                # IZOLASYON / KILIT (BB6, ileriye uyumlu): AgentChef 1.3.5 'isolation' alani
                # varsa kapsam hucresine eklenir; blocked kart kilidini birakmistir.
                if ([string]$k.isolation -eq 'worktree') { $ws += ' [worktree]' }
                if ([string]$k.status -eq 'blocked' -and $k.writeScope) { $ws += ' (kilit birakildi)' }
                # KANIT YOK (2026-10-06): calisilan ya da incelemedeki kartta tek kanit yoksa
                # isaret; 'todo' isaretlenmez (henuz baslamadi).
                $kanitSay = @($k.evidence).Count
                $kanitHucre = $(if (($kanitSay -eq 0 -and $k.status -in @('in_progress', 'review')) -or $k.evidenceMissing -eq $true) { '**KANIT YOK**' } else { [string]$kanitSay })
                [void]$sb.AppendLine("| ``$($k.id)`` | $($k.status) | $sahip | $ws | $(Zaman $k.leaseUntil) | $(if ($k.brief) { 'var' } else { 'YOK' }) | $kanitHucre | $(Kisa $k.title 70) |")
            }
            $kanitsiz = @($d.Kartlar | Where-Object { @($_.evidence).Count -eq 0 -and $_.status -in @('in_progress', 'review') }).Count
            if ($kanitsiz -gt 0) { [void]$sb.AppendLine(''); [void]$sb.AppendLine("> **KANIT YOK:** $kanitsiz kart calisiliyor ya da incelemede ama tek kanit kaydi yok.") }
        }
        if ($d.Bekleyen -gt 0) {
            [void]$sb.AppendLine('')
            [void]$sb.AppendLine("## Bekleyen (backlog, $($d.Bekleyen))")
            [void]$sb.AppendLine('')
            [void]$sb.AppendLine('| Kart | Sahip | Yazma kapsami | Brief | Baslik |')
            [void]$sb.AppendLine('| --- | --- | --- | --- | --- |')
            foreach ($k in $d.BekleyenKartlar) {
                $ws = $(if ($k.writeScope) { "$($k.writeScope.repo): $(Kisa (@($k.writeScope.paths) -join ', ') 70)" } else { '-' })
                [void]$sb.AppendLine("| ``$($k.id)`` | $(if ($k.owner) { $k.owner.agent } else { '-' }) | $ws | $(if ($k.brief) { 'var' } else { 'YOK' }) | $(Kisa $k.title 70) |")
            }
        }
        # 1.3.3: 'cancelled' da kapali listesine girer (status sutununda ayirt edilir).
        $kapali = @($tum | Where-Object { $_.status -in @('done', 'cancelled') } | Select-Object -Last 20)
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine("## Bitti (son $($kapali.Count))")
        [void]$sb.AppendLine('')
        if ($kapali.Count -eq 0) { [void]$sb.AppendLine('(henuz biten kart yok)') }
        else {
            [void]$sb.AppendLine('| Kart | Durum | Sahip | Kanit | Baslik |')
            [void]$sb.AppendLine('| --- | --- | --- | --- | --- |')
            foreach ($k in $kapali) { [void]$sb.AppendLine("| ``$($k.id)`` | $($k.status) | $(if ($k.owner) { $k.owner.agent } else { '-' }) | $(@($k.evidence).Count) | $(Kisa $k.title 70) |") }
        }
        $yol = Join-Path (Join-Path $Paths.Vault '10-command-center') 'pano.md'
        Write-BeyinText -Path $yol -Text $sb.ToString()
        $r.Yol = $yol; $r.Acik = $d.Acik; $r.Ok = (Test-Path -LiteralPath $yol)
    } catch { }
    return $r
}

# ============================================================================
# KAYNAK BEKCISI - UCUZ KATMAN  (2026-10-04, plan #8)
# ----------------------------------------------------------------------------
# NEDEN: 2026-10-03 gecesi commit 67,8/74 GB'a cikti; 11 Claude oturumunun 6'si
# saatlerdir bostaydi, 5 yetim doktor ~1 GB yiyordu ve hicbir oturum bunu
# gormuyordu. Bu fonksiyon oturum acilisinda TEK ucuz olcum yapar (bir
# Win32_OperatingSystem cagrisi + oturum dosyalarinin LastWriteTime'i) ve
# yalniz esik asildiysa tek satir uretir. 1,5 sn sert tavan: tavan asilirsa
# elde ne varsa onunla doner, uyari uretmez (acilisi yavaslatmak kabul degil).
# Hicbir sureci listelemez/oldurmez; tam liste 'beyin bekci'de (bekci.ps1).
# ============================================================================
# OKUMA YOLU SIR MASKESI (2026-10-06, AgentSpace memorySecretMask): enjeksiyona giren
# metin (gunluk blogu, devam tablosu, aktarim, kavram ozeti) ikinci kez maskelenir.
# Yazim yolu fail-closed'dir; burada fail-DROP: desen uygulanamazsa blok HIC enjekte
# edilmez (maskesiz metin sizmaz) ve engine.log'a dusulur. Sayaclar makbuz notu icin.
$script:BeyinMaskeSayac = 0
$script:BeyinMaskeDusen = 0
function Protect-BeyinBlok {
    param([string]$Text, [string]$Vault = '', [string]$Ad = 'blok')
    if ([string]::IsNullOrEmpty($Text)) { return $Text }
    $pr = Protect-BeyinSecrets -Text $Text -Vault $Vault
    if ([int]$pr.Failed -gt 0) {
        $script:BeyinMaskeDusen++
        if ($Vault) { try { Write-BeyinLog -Vault $Vault -Message "maske: '$Ad' blogu dusuruldu (uygulanamayan desen: $($pr.FailedPatterns))" } catch { } }
        return $null
    }
    $script:BeyinMaskeSayac += [int]$pr.Redactions
    return [string]$pr.Text
}

function Get-BeyinKaynakOzeti {
    param([hashtable]$Paths, [int]$CommitEsik = 85, [int]$BostaDk = 120, [string]$SessionKey = '', [int]$OnbellekDk = 10)
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $r = @{ Ok = $false; CommitYuzde = -1; CommitGB = 0.0; CommitTavanGB = 0.0; BosRamGB = -1.0; OnerilenAjan = 0; OlcumYasiDk = 0; BostaOturum = 0; AktifOturum = 0; Esik = $false; Satir = ''; Ms = 0 }
    try {
        # OLCUM ONBELLEGI (olculdu, soguk surecte): Get-CimInstance ~600 ms,
        # PerformanceCounter ~2,5 sn - ikisi de kanca icin pahali (hedef <150 ms).
        # Commit yavas degisen bir buyukluk; 10 dakikalik onbellek yeter.
        # Onbellek varsa ve tazeyse CIM HIC cagrilmaz (~2 ms).
        $onb = $null
        $onbF = $(if ($Paths -and $Paths.ScrState) { Join-Path $Paths.ScrState 'kaynak-son.json' } else { '' })
        if ($onbF -and (Test-Path -LiteralPath $onbF)) {
            try {
                $o = Get-Content -LiteralPath $onbF -Raw -Encoding UTF8 | ConvertFrom-Json
                $ots = [datetime]::Parse([string]$o.ts, [Globalization.CultureInfo]::InvariantCulture)
                $yasDk = ((Get-Date) - $ots).TotalMinutes
                if ($yasDk -ge 0 -and $yasDk -lt $OnbellekDk) { $onb = $o; $r.OlcumYasiDk = [int]$yasDk }
            } catch { }
        }
        if ($onb) {
            $r.CommitYuzde = [int]$onb.commitYuzde; $r.CommitGB = [double]$onb.commitGB; $r.CommitTavanGB = [double]$onb.commitTavanGB; $r.Ok = $true
            if ($onb.PSObject.Properties['bosRamGB']) { $r.BosRamGB = [double]$onb.bosRamGB }
        } else {
            $os = Get-CimInstance -ClassName Win32_OperatingSystem -OperationTimeoutSec 1 -ErrorAction Stop
            # TotalVirtualMemorySize = commit LIMITI (KB), FreeVirtualMemory = bos commit (KB).
            $top = [double]$os.TotalVirtualMemorySize
            $bos = [double]$os.FreeVirtualMemory
            if ($top -gt 0) {
                $r.CommitYuzde   = [int][math]::Round(100.0 * ($top - $bos) / $top)
                $r.CommitGB      = [math]::Round(($top - $bos) / 1MB, 1)
                $r.CommitTavanGB = [math]::Round($top / 1MB, 1)
                # BOS FIZIKSEL RAM (2026-10-06, AgentSpace resourceGovernor fikri): sabit
                # '<=4 isci' yerine olcumden turetilen ONERI. Ayni CIM nesnesinden, ek maliyet yok.
                try { $r.BosRamGB = [math]::Round([double]$os.FreePhysicalMemory / 1MB, 1) } catch { }
                $r.Ok = $true
                if ($onbF) {
                    try {
                        Write-BeyinText -Path $onbF -Text (@{ ts = (Get-Date).ToString('o', [Globalization.CultureInfo]::InvariantCulture); commitYuzde = $r.CommitYuzde; commitGB = $r.CommitGB; commitTavanGB = $r.CommitTavanGB; bosRamGB = $r.BosRamGB; onerilenAjan = [int][math]::Min(6, [math]::Max(2, [math]::Floor([math]::Max(0, $r.BosRamGB)))) } | ConvertTo-Json -Compress)
                    } catch { }
                }
            }
        }
        # Bosta oturum: SON 24 SAATTE acilmis ama BostaDk'dan uzun suredir dokunulmamis
        # oturum DOSYALARI. Dosya kapanmis bir oturuma da ait olabilir (SessionEnd
        # her kapanista atesmez) - bu yuzden satir "kapanmis olabilir" der. Eski
        # surum 14 gunu tariyordu ve 43 sayiyordu; gercek kapanmamislar 9'du.
        if ($sw.ElapsedMilliseconds -lt 1500 -and $Paths -and (Test-Path -LiteralPath $Paths.Sessions)) {
            $simdi = Get-Date
            $pencere = $simdi.AddHours(-24)
            foreach ($f in @(Get-ChildItem -LiteralPath $Paths.Sessions -Filter '*.json' -File -ErrorAction SilentlyContinue)) {
                if ($sw.ElapsedMilliseconds -ge 1500) { break }
                if ($SessionKey -and $f.BaseName -eq $SessionKey) { continue }
                if ($f.LastWriteTime -lt $pencere) { continue }
                if ($f.LastWriteTime -lt $simdi.AddMinutes(-$BostaDk)) { $r.BostaOturum++ } else { $r.AktifOturum++ }
            }
        }
        # Kapi: commit esigi ASILDIYSA ya da 5+ oturum sessizse. Tek sessiz
        # oturum siradan; bes tanesi gercek bir sizinti sinyali.
        # ONERILEN ES ZAMANLI AJAN: bos RAM GB basina bir ajan, 2-6 araligi (kaba tahmin;
        # AgentChef routing'e bilgi, kapi degil). Olculemediyse 0.
        if ($r.BosRamGB -ge 0) { $r.OnerilenAjan = [int][math]::Min(6, [math]::Max(2, [math]::Floor($r.BosRamGB))) }
        $r.Esik = (($r.CommitYuzde -ge $CommitEsik) -or ($r.BostaOturum -ge 5))
        if ($r.Esik) {
            $saat = [math]::Round($BostaDk / 60.0, 1)
            $r.Satir = "[Hafiza] UYARI kaynak: commit %$($r.CommitYuzde) ($($r.CommitGB)/$($r.CommitTavanGB) GB$(if ($r.OlcumYasiDk -gt 0) { ", $($r.OlcumYasiDk) dk onceki olcum" }))" +
                       $(if ($r.BostaOturum -gt 0) { ", son 24 saatte acilmis $($r.BostaOturum) oturum ${saat}+ saattir sessiz (kapanmis olabilir)" } else { '' }) +
                       $(if ($r.OnerilenAjan -gt 0) { "; onerilen es zamanli ajan: $($r.OnerilenAjan) (bos RAM $($r.BosRamGB) GB)" } else { '' }) +
                       " - liste: beyin bekci (yalniz gosterir, hicbir sureci kapatmaz)."
        }
    } catch { }
    $r.Ms = [int]$sw.ElapsedMilliseconds
    return $r
}

# ============================================================================
# GOM / VEKTOR GERI GETIRME  (Faz 4F, 2026-09-15)
# ----------------------------------------------------------------------------
# NEDEN: geri getirme anahtar kelime tabanliydi; "npm windows'ta patlıyor"
# sorgusu "spawnsync einval" notunu bulmuyordu. Ollama'daki bge-m3 (1024-d,
# Turkce) ile her kavram notu bir vektore gomulur (gom.ps1), sorgu da ayni
# modelle gomulup kosinus benzerligiyle karsilastirilir. HIBRIT: vektor skoru
# anahtar kelime tutusuyla birlestirilir; hic kelime tutmayan VE benzerligi
# 0.75 altinda kalan aday duser (yalniz-vektor yanlis pozitiflerine karsi).
#
# Dosyalar (motor\scripts\.state):
#   kavram-vektor.bin  float32 little-endian, BIRIM vektorler (n x dim)
#   kavram-vektor.dat  {v,model,dim,ts,items:[{slug,hash}]}
# Kanca yolunda vektor kullanilamazsa (Ollama kapali, model yuklu degil,
# zaman asimi) SESSIZCE anahtar kelime yoluna dusulur; makbuz 'yol=' notu
# hangisinin kullanildigini soyler.
# ============================================================================
$script:BeyinEmbedModel = Get-BeyinAyar 'BEYIN_EMBED_MODEL' (Get-BeyinAyarVars 'BEYIN_EMBED_MODEL')
# 127.0.0.1, 'localhost' DEGIL: .NET once ::1'i dener, Ollama yalniz IPv4'te dinler; her yeni
# surecte ilk istek ~2.2 sn gecikiyordu (olculdu: localhost 2241 ms, 127.0.0.1 354 ms).
$script:BeyinOllamaUrl  = (Get-BeyinAyar 'BEYIN_OLLAMA_URL' (Get-BeyinAyarVars 'BEYIN_OLLAMA_URL')).TrimEnd('/')
$script:BeyinVecCache   = $null

function Write-BeyinBytes {
    # Write-BeyinText'in bayt esdegeri: gecici dosyaya yaz, yerine koy.
    param([string]$Path, [byte[]]$Bytes)
    $tmp = $Path + '.tmp-' + [guid]::NewGuid().ToString('N').Substring(0, 8)
    try {
        [System.IO.File]::WriteAllBytes($tmp, $Bytes)
        if (Test-Path -LiteralPath $Path) {
            try { [System.IO.File]::Replace($tmp, $Path, $null) }
            catch { Move-Item -LiteralPath $tmp -Destination $Path -Force -ErrorAction Stop }
        } else { Move-Item -LiteralPath $tmp -Destination $Path -ErrorAction Stop }
    } finally { if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue } }
}

function Invoke-BeyinOllamaJson {
    # Ollama HTTP: GET/POST, JSON doner; hata/zaman asiminda $null. Invoke-RestMethod
    # yerine HttpWebRequest: milisaniye zaman asimi kanca yolunda sart.
    param([string]$Yol, [string]$Method = 'GET', [string]$Body = '', [int]$TimeoutMs = 800)
    try {
        $req = [System.Net.HttpWebRequest]::Create($script:BeyinOllamaUrl + $Yol)
        $req.Method = $Method; $req.Timeout = $TimeoutMs; $req.ReadWriteTimeout = [math]::Max($TimeoutMs, 2000)
        $req.Proxy = $null
        if ($Method -eq 'POST') {
            $req.ContentType = 'application/json'
            $b = [System.Text.Encoding]::UTF8.GetBytes($Body)
            $req.ContentLength = $b.Length
            $rs = $req.GetRequestStream(); $rs.Write($b, 0, $b.Length); $rs.Close()
        }
        $resp = $req.GetResponse()
        $sr = New-Object System.IO.StreamReader($resp.GetResponseStream(), [System.Text.Encoding]::UTF8)
        $txt = $sr.ReadToEnd(); $sr.Close(); $resp.Close()
        return ($txt | ConvertFrom-Json)
    } catch { return $null }
}

function Invoke-BeyinOllamaEmbed {
    # Metinleri gomer. Donus: @{ Ok; Vectors = @(float[] ...) } - hata/zaman asiminda Ok=$false.
    param([string[]]$Texts, [int]$TimeoutMs = 800)
    $sonuc = @{ Ok = $false; Vectors = @() }
    try {
        $body = ConvertTo-Json -InputObject @{ model = $script:BeyinEmbedModel; input = @($Texts); keep_alive = '24h' } -Compress -Depth 3
        $o = Invoke-BeyinOllamaJson -Yol '/api/embed' -Method 'POST' -Body $body -TimeoutMs $TimeoutMs
        if (-not $o -or -not $o.embeddings) { return $sonuc }
        $vs = New-Object System.Collections.Generic.List[object]
        foreach ($e in $o.embeddings) { $vs.Add([float[]]$e) }
        if ($vs.Count -ne $Texts.Count) { return $sonuc }
        $sonuc.Ok = $true; $sonuc.Vectors = @($vs.ToArray())
    } catch { }
    return $sonuc
}

function ConvertTo-BeyinUnitVector {
    param([float[]]$V)
    $n = 0.0
    for ($i = 0; $i -lt $V.Length; $i++) { $n += [double]$V[$i] * [double]$V[$i] }
    $n = [math]::Sqrt($n)
    $u = New-Object float[] $V.Length
    if ($n -le 0) { return $u }
    for ($i = 0; $i -lt $V.Length; $i++) { $u[$i] = [float]($V[$i] / $n) }
    return $u
}

function Get-BeyinVectorIndex {
    # .dat + .bin -> @{ Meta; All=float[] (n*dim, birim); N; Dim }. Yoksa/bozuksa $null. Surec ici onbellek.
    param([hashtable]$Paths)
    if ($script:BeyinVecCache) { return $script:BeyinVecCache }
    try {
        $dat = Join-Path $Paths.ScrState 'kavram-vektor.dat'
        $bin = Join-Path $Paths.ScrState 'kavram-vektor.bin'
        if (-not (Test-Path -LiteralPath $dat) -or -not (Test-Path -LiteralPath $bin)) { return $null }
        $meta = Get-Content -LiteralPath $dat -Raw -Encoding UTF8 | ConvertFrom-Json
        $n = @($meta.items).Count; $dim = [int]$meta.dim
        if ($n -le 0 -or $dim -le 0) { return $null }
        $bytes = [System.IO.File]::ReadAllBytes($bin)
        if ($bytes.Length -ne ($n * $dim * 4)) { return $null }
        $all = New-Object float[] ($n * $dim)
        [System.Buffer]::BlockCopy($bytes, 0, $all, 0, $bytes.Length)
        $script:BeyinVecCache = @{ Meta = $meta; All = $all; N = $n; Dim = $dim }
        return $script:BeyinVecCache
    } catch { return $null }
}

function Test-BeyinVectorReady {
    param([hashtable]$Paths)
    $vi = Get-BeyinVectorIndex -Paths $Paths
    return [bool]($vi -and $vi.N -gt 0 -and ([string]$vi.Meta.model -eq $script:BeyinEmbedModel))
}

function Start-BeyinEmbedWarmup {
    # ISITMA (2026-09-15; DUZELTME 2026-09-16, denetim): Ollama modeli bosta kalinca
    # bellekten atiyor; ilk sorgu gomme 3-10 sn suruyor, kanca 800 ms'de kelime
    # yoluna dusuyor. Ilk surum BeginGetResponse + surec cikisi kullaniyordu:
    # baglanti kopunca Ollama istegi ATIYOR, model yuklenmiyordu (olculdu: 60
    # isitma, /api/ps hep bos, gun boyu 'yol=kelime(vektor-dusme)').
    # Simdi: govde dosyaya yazilir, cevabi BEKLEYEN ayri bir curl.exe sureci
    # baslatilir (kanca omrunden bagimsiz, ~200 ms). 120 sn damgasi firtinayi
    # onler. Vektor indeksi yoksa hic ugrasilmaz.
    param([hashtable]$Paths)
    try {
        if (-not (Test-BeyinVectorReady -Paths $Paths)) { return }
        $damga = Join-Path $Paths.ScrState 'embed-warm.txt'
        if ((Test-Path -LiteralPath $damga) -and ((Get-Item -LiteralPath $damga).LastWriteTime -gt (Get-Date).AddSeconds(-120))) { return }
        try { [System.IO.File]::WriteAllText($damga, (Get-Date).ToString('o')) } catch { }
        $govde = Join-Path $Paths.ScrState 'embed-warm.json'
        [System.IO.File]::WriteAllText($govde, (ConvertTo-Json -InputObject @{ model = $script:BeyinEmbedModel; input = @('isitma'); keep_alive = '24h' } -Compress -Depth 3), $script:BeyinUtf8NoBom)
        # OLCULDU (2026-09-16): 'powershell -WindowStyle Hidden -ExecutionPolicy
        # Bypass -Command "... New-Object System.Net.WebClient ... UploadString"'
        # birlesimini bazi guvenlik urunleri kotucul bir kalip sayip ENGELLIYOR
        # (hedef localhost olsa bile). Bu yuzden inline PowerShell YOK: yalniz
        # Windows'un kendi curl.exe'si. curl yoksa isitma yapilmaz (kelime yolu
        # zaten calisir).
        $curl = Join-Path $env:SystemRoot 'System32\curl.exe'
        if (-not (Test-Path -LiteralPath $curl)) { return }
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $curl
        $psi.Arguments = '-s -m 180 -o NUL -H "Content-Type: application/json" -d "@' + $govde + '" "' + $script:BeyinOllamaUrl + '/api/embed"'
        $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
        $psi.EnvironmentVariables['BEYIN_CHILD'] = '1'
        $psi.EnvironmentVariables['AGENTCHEF_ROUTING_HINT'] = 'off'   # AgentChef yonlendirme satiri motorun kendi model cagrilarinda gereksiz
        [void][System.Diagnostics.Process]::Start($psi)
    } catch { }
}

function Find-BeyinRelevantConceptsVec {
    # Vektor + anahtar kelime hibrit geri getirme. Donus: @{ Ok; Sonuc=@(...) }.
    # Ok=$false -> vektor yolu kullanilamadi, cagiran kelime yoluna duser.
    # Sonuc ogeleri Find-BeyinRelevantConcepts ile AYNI sekil: Item, Skor, Tutan (+ Cos).
    param(
        [hashtable]$Paths,
        [string]$Query,
        [int]$EnFazla = 2,
        [int]$TopK = 6,
        [double]$MinBenzerlik = 0.42,   # olculdu: dogru not 0.45-0.67, medyan 0.33-0.40 (bge-m3)
        [int]$TimeoutMs = 800,
        # FUSION DENEYI (BB2): 'hibrit' (varsayilan: cos*10 + baslik*2 + govde) ya da
        # 'rrfK' (K=5/60: esigi gecen adaylarda cos sirasi ile kelime sirasinin
        # karsilikli sira birlesimi). Varsayilan ancak holdout >= +0.02 olursa degisir.
        [string]$Fusion = 'hibrit',
        [switch]$SonmeYok
    )
    $r = @{ Ok = $false; Sonuc = @() }
    try {
        $vi = Get-BeyinVectorIndex -Paths $Paths
        if (-not $vi) { return $r }
        # Ham prompt HTTP'ye gider (BEYIN_OLLAMA_URL uzak olabilir): once sir maskele (2026-09-16).
        $q = [string]$Query
        if ($q.Length -gt 1000) { $q = $q.Substring(0, 1000) }
        # Redaksiyon duserse sorgu MASKELENMEMIS olur; bu metin kavram
        # eslestirmede kullanilip makbuz notuna dusebilir. Dusen desende
        # sorguyu kullanma - geri getirme bir kolayliktir, sir sizdirmaya
        # degmez. (2026-09-18 sozlesme tutarliligi turu.)
        try {
            $pr = Protect-BeyinSecrets -Text $q
            if ($pr.Failed -gt 0) { $q = '' } else { $q = $pr.Text }
        } catch { $q = '' }
        $emb = Invoke-BeyinOllamaEmbed -Texts @($q) -TimeoutMs $TimeoutMs
        if (-not $emb.Ok) { return $r }
        $qv = ConvertTo-BeyinUnitVector ([float[]]$emb.Vectors[0])
        if ($qv.Length -ne $vi.Dim) { return $r }
        $r.Ok = $true

        # Kosinus = birim vektorlerin ic carpimi (saf PowerShell; 114x1024 ~ 0.2 sn)
        $all = $vi.All; $dim = $vi.Dim; $n = $vi.N
        $skor = New-Object double[] $n
        for ($i = 0; $i -lt $n; $i++) {
            $acc = 0.0; $b = $i * $dim
            for ($j = 0; $j -lt $dim; $j++) { $acc += $all[$b + $j] * $qv[$j] }
            $skor[$i] = $acc
        }
        $sira = @(0..($n - 1) | Sort-Object { -$skor[$_] } | Select-Object -First $TopK)

        # Hibrit: kelime tutusu
        $qt = @(Get-BeyinKelimeler -Text $Query)
        $idx = @(Get-BeyinConceptIndex -Paths $Paths)
        $idxMap = @{}
        foreach ($it in $idx) { $idxMap[[IO.Path]::GetFileNameWithoutExtension($it.dosya).ToLowerInvariant()] = $it }
        $secilen = New-Object System.Collections.Generic.List[object]
        foreach ($i in $sira) {
            $cos = [double]$skor[$i]
            if ($cos -lt $MinBenzerlik) { continue }
            $slug = ([string]$vi.Meta.items[$i].slug).ToLowerInvariant()
            if (-not $idxMap.ContainsKey($slug)) { continue }   # not silinmis; gom yenilenince duser
            $it = $idxMap[$slug]
            $bt = 0; $gt = 0; $tutan = New-Object System.Collections.Generic.List[string]
            foreach ($t in $qt) {
                if ($it.bterim -contains $t) { $bt++; $tutan.Add($t) }
                elseif ($it.gterim -contains $t) { $gt++; $tutan.Add($t) }
            }
            # KADEMELI ESIK (2026-09-18, kosarak olculdu).
            # Eski kural: "hic kelime tutmuyorsa 0.60, tutuyorsa 0.42". Yani
            # TEK bir genel kelime (ornek: 'eski', 'test') 0.18'lik bir cos
            # indirimi satin aliyordu ve alakasiz notlar 0.52'de geciyordu.
            # Olculdu: uc gercek istemde gelen alti notun besi boyle gecmisti.
            #
            # Simdi indirim KANITIN GUCUYLE oransal:
            #   iki+ BASLIK terimi  -> 0.42  (baslik terimleri kuratorlu, guclu)
            #   bir  BASLIK terimi  -> 0.50
            #   iki+ GOVDE terimi   -> 0.55
            #   digeri (0 ya da 1)  -> 0.60  (yalniz yuksek benzerlik gecer)
            $esik = if ($bt -ge 2) { $MinBenzerlik }
                    elseif ($bt -eq 1) { [math]::Max($MinBenzerlik, 0.55) }
                    elseif ($gt -ge 2) { [math]::Max($MinBenzerlik, 0.55) }
                    else { 0.60 }
            if ($cos -lt $esik) { continue }
            $hibrit = [math]::Round($cos * 10 + $bt * 2 + $gt, 2)
            $secilen.Add([pscustomobject]@{ Item = $it; Skor = $hibrit; Tutan = @($tutan.ToArray()); Cos = [math]::Round($cos, 3); Kel = ($bt * 2 + $gt) })
        }
        $liste = @($secilen.ToArray())
        if ($Fusion -match '^rrf(\d+)$' -and $liste.Count -gt 1) {
            $rrfK = [double]$Matches[1]
            $rc = @{}; $rk = @{}; $sira = 1
            foreach ($x in @($liste | Sort-Object Cos -Descending)) { $rc[[string]$x.Item.dosya] = $sira; $sira++ }
            $sira = 1
            foreach ($x in @($liste | Sort-Object Kel -Descending)) { $rk[[string]$x.Item.dosya] = $sira; $sira++ }
            foreach ($x in $liste) { $x.Skor = [math]::Round(100.0 * (1.0 / ($rrfK + $rc[[string]$x.Item.dosya]) + 1.0 / ($rrfK + $rk[[string]$x.Item.dosya])), 3) }
        }
        if (-not $SonmeYok) {
            $sn = Get-BeyinKullanimSonme -Paths $Paths
            if ($sn.Count -gt 0) {
                foreach ($x in $liste) { $sk = ([string]$x.Item.dosya).ToLowerInvariant(); if ($sn.ContainsKey($sk)) { $x.Skor = [math]::Round($x.Skor * $sn[$sk], 3) } }
            }
        }
        $r.Sonuc = @($liste | Sort-Object Skor -Descending | Select-Object -First $EnFazla)
    } catch { }
    return $r
}

# ============================================================================
# KAVRAM NOTU YAZIMI / GUNCELLEME  (2.3, 2026-09-17)
# ----------------------------------------------------------------------------
# NEDEN: motor 128 kavram notu uretti ve HICBIRI olusturuldugu gunden sonra
# guncellenmedi (olculdu). Derleyici mevcut bir kavrama benzer yeni bilgi
# gorunce notu zenginlestirmek yerine 'kopya kavram atlandi' deyip atiyordu:
# uc hafta onceki bir not, sonradan gelen celiskiyi ya da ek kanidi hic
# ogrenmiyordu. Bilgi bir kez derlenip GUNCEL TUTULMALI.
#
# Sozlesme: frontmatter MOTORUN, govde MODELIN. id ve created ASLA degismez
# (Obsidian baglantilari ve brain-cli semasi buna bagli); updated ve
# source_refs birlestirilir. Guncellemeden ONCE eski surum
# 90-archive\86-compiled\concepts\<slug>.<damga>.md olarak saklanir: git
# commit'leri arasinda bile geri donus noktasi kalir.
# ============================================================================

function Split-BeyinNote {
    # Bir notu frontmatter + govde olarak ayirir. Donus: @{ Ok; Fm; Body; Fields }
    # Fields: id, created, title, sourceRefs (dizi), tags (ham dize)
    param([string]$Path)
    $r = @{ Ok = $false; Fm = ''; Body = ''; Fields = @{ id = ''; created = ''; title = ''; sourceRefs = @(); tags = '' } }
    try {
        if (-not (Test-Path -LiteralPath $Path)) { return $r }
        $ham = [System.IO.File]::ReadAllText($Path)
        $ham = $ham -replace ('^' + [char]0xFEFF), ''
        $m = [regex]::Match($ham, '(?s)\A---\r?\n(.*?)\r?\n---\r?\n?')
        if ($m.Success) {
            $r.Fm = $m.Groups[1].Value
            $r.Body = $ham.Substring($m.Length)
        } else {
            $r.Body = $ham
        }
        foreach ($alan in @('id', 'created', 'title')) {
            $mm = [regex]::Match($r.Fm, ('(?m)^' + $alan + ':\s*"?([^"\r\n]*)"?\s*$'))
            if ($mm.Success) { $r.Fields[$alan] = $mm.Groups[1].Value.Trim() }
        }
        $ms = [regex]::Match($r.Fm, '(?m)^source_refs:\s*\[(.*)\]\s*$')
        if ($ms.Success) {
            $liste = New-Object System.Collections.Generic.List[string]
            foreach ($t in [regex]::Matches($ms.Groups[1].Value, '"([^"]*)"')) { $liste.Add($t.Groups[1].Value) }
            $r.Fields['sourceRefs'] = @($liste.ToArray())
        }
        $mt = [regex]::Match($r.Fm, '(?m)^tags:\s*(.+)$')
        if ($mt.Success) { $r.Fields['tags'] = $mt.Groups[1].Value.Trim() }
        $r.Ok = $true
    } catch { }
    return $r
}

function Write-BeyinKavramNotu {
    # Kavram notu YAZAR ya da GUNCELLER. Donus:
    #   @{ Ok; Action='yeni'|'guncel'|'atlandi'; Path; Before; After; Reason }
    # -Body yalniz GOVDE (frontmatter'siz). Guncellemede eski govde arsive kopyalanir.
    param(
        [hashtable]$Paths,
        [string]$Name,                  # 'slug.md'
        [string]$Title,
        [string]$Body,
        [string[]]$SourceRefs = @(),
        [string]$Tags = '["derlenmis", "makine-uretimi"]',
        [switch]$Guncelle,              # verilmezse mevcut not EZILMEZ (eski davranis)
        [bool]$Arsivleme = $true,       # $false: 90-archive on-goruntusu ATLANIR. Bilerek KULLANILMIYOR:
                                        # geri donus agini delmenin bedeli kurtarilamayan kayiptir (bkz. asagisi).
        [double]$EnAzOran = 0.6         # guncellemede yeni govde eskinin en az %60'i olmali
    )
    $r = @{ Ok = $false; Action = 'atlandi'; Path = ''; Before = [long]-1; After = [long]-1; Reason = '' }
    try {
        $dir = Join-Path $Paths.Compiled 'concepts'
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        $hedef = Join-Path $dir $Name
        $r.Path = $hedef
        $govde = ([string]$Body).Trim()
        if (-not $govde) { $r.Reason = 'bos govde'; return $r }
        $iso = (Get-Date).ToString('o', [Globalization.CultureInfo]::InvariantCulture)
        $varMi = Test-Path -LiteralPath $hedef
        $r.Before = Measure-BeyinDosya -Path $hedef

        if ($varMi -and -not $Guncelle) { $r.Reason = 'mevcut not korundu (overwritePolicy: never)'; return $r }

        $id = ''; $created = ''; $mevcutRefs = @(); $mevcutTags = ''
        if ($varMi) {
            $eski = Split-BeyinNote -Path $hedef
            $id = [string]$eski.Fields['id']; $created = [string]$eski.Fields['created']
            $mevcutRefs = @($eski.Fields['sourceRefs']); $mevcutTags = [string]$eski.Fields['tags']
            $eskiGovde = ([string]$eski.Body).Trim()
            # KISALMA KAPISI: model ozetleyip kisaltirsa bilgi kaybolur. Eskinin
            # %60'inin altina inen bir 'guncelleme' kabul edilmez.
            if ($eskiGovde.Length -gt 0 -and $govde.Length -lt [int]($eskiGovde.Length * $EnAzOran)) {
                $r.Reason = "guncelleme REDDEDILDI: yeni govde $($govde.Length) < eski $($eskiGovde.Length) x $EnAzOran"
                return $r
            }
            # GERI DONUS NOKTASI: eski surumu arsive kopyala (git commit'leri arasinda da kurtarilabilir).
            # -Arsivleme:$false yalniz cagiranin geri donus noktasina GERCEKTEN ihtiyaci
            # olmadigi hallerdedir; varsayilan ACIKTIR ve oyle kalmalidir.
            #
            # NEDEN 'if' VE NEDEN LOGLU CATCH (2026-09-17 denetimi): bu blok once
            # `try { if (-not $Arsivleme) { throw ... } ... } catch { }` seklindeydi.
            # Iki ayri sey ayni GORUNMEZ sonuca dusuyordu: (1) bilincli atlama ve
            # (2) GERCEK arsiv hatasi - kilitli 90-archive, dolu disk, ACL reddi.
            # Ikisinde de $r.Ok yine $true doner ve hicbir cagiran, hicbir log
            # geri donus kopyasinin YAZILMADIGINI ogrenmezdi. Atlama artik akista
            # (istisna maliyeti yok), gercek hata ise log birakir.
            if ($Arsivleme) {
                try {
                    $arsiv = Join-Path $Paths.Archive '86-compiled\concepts'
                    New-Item -ItemType Directory -Force -Path $arsiv | Out-Null
                    $damga = (Get-Date).ToString('yyyyMMdd-HHmmss', [Globalization.CultureInfo]::InvariantCulture)
                    # KIMLIK CAKISMASI (2026-09-17): duz kopya canli notun id'sini tasiyordu ve
                    # brain-cli 'duplicates Brain note id' diye bildiriyordu. Arsiv kopyasi AYRI
                    # bir kayittir: yeni id, status 'superseded', ve hangi notun onceki surumu
                    # oldugu source_refs'e yazilir. Govde aynen korunur.
                    $onceki = [System.IO.File]::ReadAllText($hedef)
                    $onceki = $onceki -replace ('^' + [char]0xFEFF), ''
                    $yeniId = New-BeyinNoteId
                    $onceki = [regex]::Replace($onceki, '(?m)^id:\s*"[^"]*"\s*$', ('id: "' + $yeniId + '"'), 1)
                    $onceki = [regex]::Replace($onceki, '(?m)^status:\s*"[^"]*"\s*$', 'status: "superseded"', 1)
                    $onceki = [regex]::Replace($onceki, '(?m)^source_refs:\s*\[', ('source_refs: ["onceki-surum:' + $id + '", '), 1)
                    Write-BeyinText -Path (Join-Path $arsiv ([IO.Path]::GetFileNameWithoutExtension($Name) + '.' + $damga + '.md')) -Text $onceki
                } catch {
                    Write-BeyinLog -Vault $Paths.Vault -Message ("kavram arsivi alinamadi (" + $Name + "): " + $_.Exception.Message)
                }
            }
        }
        if (-not $id) { $id = New-BeyinNoteId }
        if (-not $created) { $created = $iso }
        if (-not $mevcutTags) { $mevcutTags = $Tags }

        # source_refs BIRLESTIR (tekrar yok, sira korunur)
        $refSet = New-Object System.Collections.Generic.List[string]
        foreach ($x in @($mevcutRefs) + @($SourceRefs)) {
            $t = [string]$x
            if ($t -and -not $refSet.Contains($t)) { $refSet.Add($t) }
        }
        if ($refSet.Count -eq 0) { $refSet.Add('engine:compile.ps1') }
        $refTxt = '[' + (($refSet.ToArray() | ForEach-Object { '"' + ($_ -replace '"', '') + '"' }) -join ', ') + ']'
        $baslik = ([string]$Title) -replace '"', ''
        if (-not $baslik) { $baslik = [IO.Path]::GetFileNameWithoutExtension($Name) }

        $fm = "---`n" +
              "brain_schema: `"codex-chef.brain-note.v1`"`n" +
              "id: `"$id`"`n" +
              "type: `"knowledge`"`n" +
              "title: `"$baslik`"`n" +
              "project_id: `"brain`"`n" +
              "status: `"active`"`n" +
              "privacy: `"local`"`n" +
              "confidence: `"unverified`"`n" +
              "retention: `"review-90d`"`n" +
              "created: `"$created`"`n" +
              "updated: `"$iso`"`n" +
              "source_refs: $refTxt`n" +
              "tags: $mevcutTags`n" +
              "---`n`n"
        Write-BeyinText -Path $hedef -Text ($fm + $govde + "`n")
        $r.After = Measure-BeyinDosya -Path $hedef
        $r.Ok = $true
        $r.Action = if ($varMi) { 'guncel' } else { 'yeni' }
    } catch { $r.Reason = $_.Exception.Message }
    return $r
}

function Get-BeyinVektorCiftleri {
    # Gomulmus kavramlar arasinda kosinus benzerligi yuksek CIFTLERI doner.
    # Yakin cift = ayni olgunun iki notu (birlestirilmeli) ya da celiski adayi.
    # Model cagrisi YOK: mevcut kavram-vektor.bin uzerinde saf PowerShell.
    # Donus: @( @{ A; B; Cos } ) - Cos'a gore azalan.
    param([hashtable]$Paths, [double]$MinCos = 0.80, [int]$EnFazla = 40)
    $sonuc = New-Object System.Collections.Generic.List[object]
    try {
        $vi = Get-BeyinVectorIndex -Paths $Paths
        if (-not $vi -or $vi.N -lt 2) { return @() }
        $all = $vi.All; $dim = $vi.Dim; $n = $vi.N
        for ($i = 0; $i -lt $n - 1; $i++) {
            $bi = $i * $dim
            for ($j = $i + 1; $j -lt $n; $j++) {
                $bj = $j * $dim
                $acc = 0.0
                for ($k = 0; $k -lt $dim; $k++) { $acc += $all[$bi + $k] * $all[$bj + $k] }
                if ($acc -ge $MinCos) {
                    $sonuc.Add([pscustomobject]@{ A = [string]$vi.Meta.items[$i].slug; B = [string]$vi.Meta.items[$j].slug; Cos = [math]::Round($acc, 3) })
                }
            }
        }
    } catch { }
    return @(@($sonuc.ToArray()) | Sort-Object Cos -Descending | Select-Object -First $EnFazla)
}

# BAYT TAVANI (denetim 2026-09-17 - B7).
# ----------------------------------------------------------------------------
# ConvertFrom-BeyinKaynak'in KARAKTER tavani vardi, BAYT tavani yoktu: 407 MB'lik
# bir .txt once TAMAMEN bellege alindi (~814 MB string, 5.2 sn), sonra 60000
# karaktere kirpildi. Yani tavan, maliyet ODENDIKTEN SONRA uygulaniyordu.
#
# DEGER GEREKCESI: korpus tavani 60000 KARAKTER; en savurgan kodlamada
# (UTF-16, karakter basina 2 bayt + coklu bayt UTF-8 dizileri) bu en fazla
# birkaç yuz KB'lik bir bas kisma denk gelir. 8 MB, mesru hicbir kaynagin bas
# kismini kesmeyecek kadar comert, en kotu durumda ayrilan bellegi ~16 MB'ta
# tutacak kadar dar. Tavani asan dosya REDDEDILMEZ - yalniz bas kismi okunur ve
# bu kullaniciya SOYLENIR (sessiz kirpma, kirpmanin kendisinden kotudur).
$script:BeyinKaynakBaytTavan = 8MB

function ConvertFrom-BeyinKaynak {
    # Dis kaynagi (makale, rapor, not) duz metne cevirir.
    # Desteklenen: .md .markdown .txt .log .html .htm .json .csv
    # Donus: @{ Ok; Text; Tur; Baslik; Reason; Uyari; Kodlama }
    param([string]$Path, [int]$MaxKarakter = 60000)
    $r = @{ Ok = $false; Text = ''; Tur = ''; Baslik = ''; Reason = ''; Uyari = ''; Kodlama = '' }
    $uyarilar = New-Object System.Collections.Generic.List[string]
    try {
        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { $r.Reason = 'dosya yok'; return $r }
        # .Trim(): yolun sonundaki bosluk uzantiya YAPISIR ('hedef.md ' -> '.md ')
        # ve gecerli bir dosya "desteklenmeyen tur" diye reddedilir (B9).
        # Yalniz UZANTI metni kirpilir; YOLUN kendisi (ve surucu koku) DOKUNULMAZ.
        $uzanti = ([IO.Path]::GetExtension($Path)).Trim().ToLowerInvariant()
        $r.Tur = $uzanti.TrimStart('.')
        $desteklenen = @('.md', '.markdown', '.txt', '.log', '.html', '.htm', '.json', '.csv')
        if ($desteklenen -notcontains $uzanti) {
            $r.Reason = "desteklenmeyen tur ($uzanti); desteklenen: " + ($desteklenen -join ' ')
            return $r
        }

        # --------------------------------------------------------------------
        # OKUMA: BAYT TAVANI + KODLAMA TESPITI  (denetim 2026-09-17 - B2/B7)
        # --------------------------------------------------------------------
        # Eskiden tek satirdi: [System.IO.File]::ReadAllText($Path) - kodlama
        # argumani YOK, dogrulama YOK, bayt tavani YOK. .NET o asiri yuklemede
        # BOM yoksa KOSULSUZ UTF-8 varsayar. OLCULDU:
        #   cp1254 (Windows ANSI, tr-TR)  -> 700 U+FFFD, tum Turkce harfler yok
        #   BOM'suz UTF-16 LE             -> 360 U+FFFD + 3056 gomulu NUL,
        #                                    uzunluk IKI KATI (korpus butcesinin
        #                                    iki katini yer)
        # ve bu metin sessizce 86-compiled\sources\*.md icine - NUL baytli
        # Markdown olarak - yaziliyordu. Ok=True, tek bir uyari yok.
        $fi = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
        $uzunlukBayt = [int64]$fi.Length
        $okunacak = $uzunlukBayt
        if ($uzunlukBayt -gt $script:BeyinKaynakBaytTavan) {
            $okunacak = [int64]$script:BeyinKaynakBaytTavan
            $uyarilar.Add("dosya $([math]::Round($uzunlukBayt/1MB,1)) MB; yalniz ilk $([int]($script:BeyinKaynakBaytTavan/1MB)) MB okundu")
        }
        $bayt = New-Object byte[] ([int]$okunacak)
        $fs = [System.IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
        try {
            $alindi = 0
            while ($alindi -lt $okunacak) {
                $n = $fs.Read($bayt, $alindi, [int]($okunacak - $alindi))
                if ($n -le 0) { break }
                $alindi += $n
            }
            if ($alindi -lt $bayt.Length) { $bayt = $bayt[0..([math]::Max(0,$alindi-1))] }
        } finally { $fs.Dispose() }

        # 1) BOM varsa ONA GORE oku - BOM'lu her sey (UTF-8, UTF-16 LE/BE,
        #    UTF-32) denetimde zaten dogru cozuluyordu, o yol korunuyor.
        $enc = $null
        $bomBoy = 0
        $b = $bayt
        if     ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF) { $enc = New-Object System.Text.UTF8Encoding($false); $bomBoy = 3; $r.Kodlama = 'utf-8 (BOM)' }
        elseif ($b.Length -ge 4 -and $b[0] -eq 0xFF -and $b[1] -eq 0xFE -and $b[2] -eq 0x00 -and $b[3] -eq 0x00) { $enc = New-Object System.Text.UTF32Encoding($false,$false); $bomBoy = 4; $r.Kodlama = 'utf-32le (BOM)' }
        elseif ($b.Length -ge 4 -and $b[0] -eq 0x00 -and $b[1] -eq 0x00 -and $b[2] -eq 0xFE -and $b[3] -eq 0xFF) { $enc = New-Object System.Text.UTF32Encoding($true,$false); $bomBoy = 4; $r.Kodlama = 'utf-32be (BOM)' }
        elseif ($b.Length -ge 2 -and $b[0] -eq 0xFF -and $b[1] -eq 0xFE) { $enc = New-Object System.Text.UnicodeEncoding($false,$false); $bomBoy = 2; $r.Kodlama = 'utf-16le (BOM)' }
        elseif ($b.Length -ge 2 -and $b[0] -eq 0xFE -and $b[1] -eq 0xFF) { $enc = New-Object System.Text.UnicodeEncoding($true,$false); $bomBoy = 2; $r.Kodlama = 'utf-16be (BOM)' }

        if ($enc) {
            $metin = $enc.GetString($bayt, $bomBoy, $bayt.Length - $bomBoy)
        } else {
            # 2) BOM YOK: once UTF-8'i KESIN cozumle. throwOnInvalidBytes=$true
            #    olan UTF8Encoding, gecersiz bir bayt dizisinde FIRLATIR - yani
            #    "sessizce U+FFFD uret" davranisi kapatilir ve ANSI bir dosyayi
            #    UTF-8 sanmak IMKANSIZ hale gelir.
            $metin = $null
            try {
                $kesin = New-Object System.Text.UTF8Encoding($false, $true)
                $metin = $kesin.GetString($bayt)
                $r.Kodlama = 'utf-8'
            } catch {
                $metin = $null
            }
            if ($null -eq $metin) {
                # 3) BOM'SUZ UTF-16 SEZGISI (ANSI'ye dusmeden ONCE).
                #    Denetimde olculen en kotu vaka buydu: BOM'suz UTF-16 LE,
                #    ANSI sanilip 3056 GOMULU NUL ve iki kati uzunlukla
                #    86-compiled\sources icine yaziliyordu. ANSI'ye dusmek bu
                #    dosyayi "uyarili mojibake"ye cevirir; oysa ayirt etmek
                #    UCUZDUR: ASCII agirlikli UTF-16 metninde baytlarin ~yarisi
                #    0x00'dir ve hepsi AYNI eslik konumundadir. Duz ANSI/UTF-8
                #    metinde 0x00 orani ~0'dir, yani yanlis pozitif yuzeyi yok.
                #    Yalniz bas 4096 bayta bakilir (sabit maliyet).
                $bak = [math]::Min(4096, $bayt.Length)
                $tek = 0; $cift = 0
                for ($i = 0; $i -lt $bak; $i++) {
                    if ($bayt[$i] -eq 0) { if (($i % 2) -eq 0) { $cift++ } else { $tek++ } }
                }
                $nulOran = ($tek + $cift) / [double][math]::Max(1, $bak)
                if ($nulOran -gt 0.25 -and $tek -gt ($cift * 4)) {
                    $metin = (New-Object System.Text.UnicodeEncoding($false, $false)).GetString($bayt)
                    $r.Kodlama = 'utf-16le (BOM yok, sezildi)'
                    $uyarilar.Add('dosyada BOM yok; bayt dagilimindan UTF-16 LE sezildi')
                } elseif ($nulOran -gt 0.25 -and $cift -gt ($tek * 4)) {
                    $metin = (New-Object System.Text.UnicodeEncoding($true, $false)).GetString($bayt)
                    $r.Kodlama = 'utf-16be (BOM yok, sezildi)'
                    $uyarilar.Add('dosyada BOM yok; bayt dagilimindan UTF-16 BE sezildi')
                }
            }
            if ($null -eq $metin) {
                # 4) UTF-8 de degil, UTF-16 de degil -> sistem ANSI kod sayfasina
                #    dus ve UYAR. Bu bir TAHMINDIR: kod sayfasi yanlissa metin
                #    bozuk gelir (ornek: cp1254 ile yazilmis bir dosya cp1252
                #    makinede Turkce harfleri kaybeder) ve kullanici BUNU BILMELI.
                # KULTURUN ANSI KOD SAYFASI, [Encoding]::Default DEGIL.
                # Olculdu (2026-09-17): bu makinede CurrentCulture = tr-TR,
                # TextInfo.ANSICodePage = 1254; ama [Encoding]::Default = 1252
                # cunku kurulu arayuz kulturu en-US. Turkce bir kullanicinin
                # "ANSI" kaydettigi dosya cp1254'tur; cp1252 ile cozulunce tum
                # Turkce harfler kaybolur. Kullanicinin kulturu dogru tahmindir.
                $ansi = $null
                try {
                    $kp = [Globalization.CultureInfo]::CurrentCulture.TextInfo.ANSICodePage
                    if ($kp -gt 0) { $ansi = [System.Text.Encoding]::GetEncoding($kp) }
                } catch { }
                if ($null -eq $ansi) { $ansi = [System.Text.Encoding]::Default }
                $metin = $ansi.GetString($bayt)
                $r.Kodlama = "ansi (cp$($ansi.CodePage))"
                $uyarilar.Add("dosyada BOM yok ve gecerli UTF-8 degil; sistem kod sayfasi cp$($ansi.CodePage) varsayildi - Turkce harfler yanlis cozulmus olabilir")
            }
        }
        $metin = $metin -replace ('^' + [char]0xFEFF), ''

        # --------------------------------------------------------------------
        # BOZULMA OLCUMU + NUL TEMIZLIGI
        # --------------------------------------------------------------------
        # GOMULU NUL: hicbir durumda ise yaramaz. Markdown'a yazildiginda dosyayi
        # bircok arac icin ikili (binary) yapar; git, editorler ve Obsidian farkli
        # davranir. KOSULSUZ temizlenir.
        # U+FFFD: cozucu bir baytı cozemedigini boyle soyler. Mesru bir metinde
        # nadiren tek tuk bulunur (kopyalanmis bozuk bir alinti).
        # ESIK GEREKCESI: toplam (FFFD + NUL) orani %0.5'i asiyor VE ham sayi
        # 3'ten cok ise bu artik "bir alintida bozuk karakter" degil, YANLIS
        # COZUMLENMIS BIR DOSYADIR - olculen vakalarda oran cp1254 icin ~%35,
        # BOM'suz UTF-16 icin ~%50 idi; mesru Turkce/Ingilizce metinde %0.
        # SAYIM YONTEMI: karakter dizisini boru hattindan gecirmek (ToCharArray |
        # Where-Object) 8 MB'lik bir metinde dakikalara mal olur. String.Replace
        # tek gecistir; uzunluk FARKI dogrudan sayiyi verir.
        $nulSayi = 0
        if ($metin.IndexOf([char]0) -ge 0) {
            $temizNul = $metin.Replace([string][char]0, '')
            $nulSayi = $metin.Length - $temizNul.Length
            $metin = $temizNul
        }
        $fffdSayi = 0
        if ($metin.IndexOf([char]0xFFFD) -ge 0) {
            $fffdSayi = $metin.Length - ($metin.Replace([string][char]0xFFFD, '')).Length
        }
        $bozukToplam = $nulSayi + $fffdSayi
        if ($bozukToplam -gt 3 -and $metin.Length -gt 0 -and (($bozukToplam / [double]($metin.Length + $nulSayi)) -gt 0.005)) {
            $uyarilar.Add("metin BOZUK gorunuyor: $fffdSayi cozulemeyen karakter, $nulSayi gomulu NUL (temizlendi) - kodlama: $($r.Kodlama)")
        } elseif ($nulSayi -gt 0) {
            $uyarilar.Add("$nulSayi gomulu NUL karakteri temizlendi")
        }
        if ($uzanti -eq '.html' -or $uzanti -eq '.htm') {
            # Kaba ama yeterli: script/style at, etiketleri soy, varliklari coz.
            $metin = [regex]::Replace($metin, '(?is)<(script|style)[^>]*>.*?</\1>', ' ')
            $mb = [regex]::Match($metin, '(?is)<title[^>]*>(.*?)</title>')
            if ($mb.Success) { $r.Baslik = ($mb.Groups[1].Value).Trim() }
            $metin = [regex]::Replace($metin, '(?is)<br\s*/?>|</p>|</div>|</li>|</h[1-6]>', "`n")
            $metin = [regex]::Replace($metin, '(?s)<[^>]+>', ' ')
            foreach ($e in @(@('&nbsp;', ' '), @('&amp;', '&'), @('&lt;', '<'), @('&gt;', '>'), @('&quot;', '"'), @('&#39;', "'"))) {
                $metin = $metin.Replace($e[0], $e[1])
            }
            $metin = [regex]::Replace($metin, '[ \t]{2,}', ' ')
            $metin = [regex]::Replace($metin, '(\r?\n){3,}', "`n`n")
        }
        # Baslik: frontmatter title > ilk '# ' basligi > dosya adi
        if (-not $r.Baslik) {
            $mfm = [regex]::Match($metin, '(?s)\A---\r?\n(.*?)\r?\n---')
            if ($mfm.Success) {
                $mt = [regex]::Match($mfm.Groups[1].Value, '(?m)^title:\s*"?([^"\r\n]+)"?\s*$')
                if ($mt.Success) { $r.Baslik = $mt.Groups[1].Value.Trim() }
            }
        }
        if (-not $r.Baslik) {
            $mh = [regex]::Match($metin, '(?m)^#\s+(.+)$')
            if ($mh.Success) { $r.Baslik = $mh.Groups[1].Value.Trim() }
        }
        if (-not $r.Baslik) { $r.Baslik = [IO.Path]::GetFileNameWithoutExtension($Path) }
        $metin = $metin.Trim()
        if (-not $metin) { $r.Reason = 'dosya bos'; return $r }
        if ($metin.Length -gt $MaxKarakter) {
            $metin = $metin.Substring(0, $MaxKarakter) + "`n`n[... kaynak $MaxKarakter karakterde kirpildi ...]"
            $uyarilar.Add("metin $MaxKarakter karakterde kirpildi")
        }
        $r.Text = $metin
        $r.Ok = $true
    } catch { $r.Reason = $_.Exception.Message }
    # UYARILAR SESSIZ KALMAZ: cagiran (al.ps1) bunlari hem kullaniciya basar hem
    # makbuza yazar. Kodlama tahmini ve kirpma, kullanicinin BILMESI gereken
    # seylerdir - sessiz gecen bir kodlama tahmini mojibake'yi kalici yapar.
    $r.Uyari = (@($uyarilar.ToArray()) -join '; ')
    return $r
}

function ConvertTo-BeyinSlug {
    # Baslikdan dosya adi uretir: kucuk harf, Turkce harfler sadelestirilir,
    # yalniz [a-z0-9-], en fazla 60 karakter. tr-TR'de ToLower() 'I'yi bozdugu
    # icin ToLowerInvariant kullanilir (motorun her yerinde ayni kural).
    param([string]$Text, [int]$MaxUzunluk = 60)
    $t = [string]$Text
    if (-not $t) { return 'kaynak' }
    foreach ($c in @(@('ç','c'), @('Ç','c'), @('ğ','g'), @('Ğ','g'), @('ı','i'), @('İ','i'),
                     @('ö','o'), @('Ö','o'), @('ş','s'), @('Ş','s'), @('ü','u'), @('Ü','u'))) {
        $t = $t.Replace($c[0], $c[1])
    }
    $t = $t.ToLowerInvariant()
    $t = [regex]::Replace($t, '[^a-z0-9]+', '-')
    $t = $t.Trim('-')
    if ($t.Length -gt $MaxUzunluk) {
        $t = $t.Substring(0, $MaxUzunluk)
        $son = $t.LastIndexOf('-')
        if ($son -gt 20) { $t = $t.Substring(0, $son) }
    }
    if (-not $t) { $t = 'kaynak' }

    # ------------------------------------------------------------------------
    # WINDOWS AYRILMIS AYGIT ADLARI (denetim 2026-09-17 - B3)
    # ------------------------------------------------------------------------
    # 'NUL' basligi 'nul' slug'ina, o da 'nul.md' dosya adina donuyordu. Windows
    # bu adi UZANTIDAN BAGIMSIZ olarak aygit sayar. OLCULDU:
    #   Write-BeyinText o yola YAZIYOR (dosya diskte, Get-ChildItem goruyor)
    #   ama Test-Path -LiteralPath  -> False
    #      Get-FileHash / Resolve-Path -> PathNotFound firlatiyor
    # Sonuc: al.ps1'deki "sayfa zaten var mi" kapisi HER ZAMAN False doner; ayni
    # kaynak ikinci kez alindiginda kod 'yeni sayfa' dalina duser ve BIRIKMIS
    # degerlendirmeyi sessizce yok eder - tam da o kapinin onlemek icin var
    # oldugu hata. Ayrica vault genelinde dosya gezen her arac (doktor, yayinla,
    # git) bu dosyalarda hata verir.
    # Cozum: govdeye bir ayirici eklenir; 'nul' -> 'nul-kaynak'. Ad ayrilmis
    # olmaktan cikar, okunurlugu ve izlenebilirligi korur.
    $ayrilmis = @('con','prn','aux','nul',
                  'com1','com2','com3','com4','com5','com6','com7','com8','com9',
                  'lpt1','lpt2','lpt3','lpt4','lpt5','lpt6','lpt7','lpt8','lpt9')
    # $t zaten ToLowerInvariant'tan gecti; ayrica uzantili yazim da denetlenir
    # ('nul.md' cagrisi slug'lamada 'nul-md' olur ama dogrudan cagiranlar icin
    # noktali govde de bakilir).
    $govde = $t
    $nokta = $govde.IndexOf('.')
    if ($nokta -gt 0) { $govde = $govde.Substring(0, $nokta) }
    if ($ayrilmis -contains $govde) { $t = $t + '-kaynak' }

    return $t
}

function Write-BeyinLog {
    # motorun kendi tanilama logu (kullanici notu degil)
    param([string]$Vault, [string]$Message)
    try {
        $dir = Join-Path $Vault 'motor\scripts\.state'
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        $p = Join-Path $dir 'engine.log'
        # LOG DONDURME (2026-09-10). Onceki surum 500 KB'de dosyayi SON 200
        # SATIRA indiriyordu; doktor'un 7 gunluk sayimlari (buyuk transkript,
        # Codex SessionEnd, injection uyarisi) o an sifirlanip YESIL raporluyordu
        # - yani kirpma, tani katmanini sessizce korlestiriyordu. Artik dosya
        # engine.1.log'a donuyor: tarihce bir tur daha yasiyor, doktor iki
        # dosyayi birlikte okuyabiliyor.
        if ((Test-Path -LiteralPath $p) -and ((Get-Item -LiteralPath $p).Length -gt 1MB)) {
            try {
                $eski = Join-Path $dir 'engine.1.log'
                Move-Item -LiteralPath $p -Destination $eski -Force -ErrorAction Stop
            } catch {
                # Dondurulemedi (dosya kilitli): son care olarak kirp.
                try {
                    $tail = @(Get-Content -LiteralPath $p -Tail 500 -Encoding UTF8)
                    Write-BeyinText -Path $p -Text (($tail -join "`n") + "`n")
                } catch { }
            }
        }
        Add-BeyinText -Path $p -Text ("{0}  {1}`n" -f ((Get-Date).ToString('yyyy-MM-dd HH:mm:ss', [Globalization.CultureInfo]::InvariantCulture)), $Message)
    } catch { }
}
