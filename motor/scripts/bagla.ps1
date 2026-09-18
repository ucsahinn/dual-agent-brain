# bagla.ps1 - Kavram notlarini birbirine baglar: her nota, anlamca en yakin
# kardeslerini gosteren MAKINE BAKIMLI bir "## Ilgili notlar" bolumu dokur.
#
# OLCUM (2026-09-17): 86-compiled\concepts altinda 132 makine-uretimi kavram
# notu var ve 91'i 86-compiled\index.md DISINDA hicbir yerden gelen baglanti
# almiyor. Obsidian graf gorunumunde bu notlar bir ag degil, dagilmis
# noktalardir. Motorda iki ilgili notu birbirine baglayan HICBIR sey yoktu:
# "capraz referanslar zaten orada" iddiasi bu vault'ta dogru degildi.
#
# NEDEN MODEL CAGIRMAZ: gom.ps1 her kavram notunu bge-m3 ile zaten gomuyor
# (motor\scripts\.state\kavram-vektor.bin + .dat; vektorler BIRIM uzunlukta).
# En yakin komsu = iki birim vektorun ic carpimi. Yani baglanti dokumek icin
# ne model cagrisi ne ag gerekir, yalniz diskteki vektorler yeter.
#
# SURE: tarama not sayisinda KARESELDIR (132 not = 8646 cift x 1024 boyut).
# Olculdu: derlenmis ic dongu (Add-Type) ~1 sn, saf PowerShell dongusu ~33 sn -
# ikisi de birebir ayni ciftleri buluyor. Add-Type kurulamazsa saf yol kosar ve
# hangisinin kostugu rapora yazilir (bkz. Initialize-BaglaHizliYol).
#
# IDEMPOTENT: bolum her kosuda YENIDEN uretilir ve eskisinin YERINE konur.
# Onceki kosudan beri hicbir sey degismediyse not HIC YAZILMAZ - aksi halde
# her gece 132 notun 'updated' damgasi tazelenir ve 90-archive altina 132
# gereksiz kopya duserdi. Esigin ustunde komsusu kalmayan nottan bolum
# KALDIRILIR: bayat bir "ilgili notlar" listesi birakilmaz.
#
# SINIR: yalniz 86-compiled\concepts altindaki notlarin GOVDESINE dokunur ve
# yalniz "## Ilgili notlar" basligi ile bir SONRAKI baslik arasindaki araligi
# yonetir. Notun geri kalani (elle ya da derleyici tarafindan yazilmis bolumler
# dahil) aynen korunur.
#
# O ARALIGA ELLE YAZILMISSA NOT ATLANIR (2026-09-17 denetimi): onceki surum
# araligi kosulsuz kendi blogyla degistiriyordu, yani basligin altina yazilan
# bir insan cumlesi SESSIZCE ve GERI DONUSSUZ siliniyordu. Artik aralik once
# taranir; icinde bize ait olmayan (beyan cumlesi ya da "- [[slug|baslik]] -
# yakinlik 0.NN" maddesi olmayan) tek bir satir varsa not YAZILMAZ, engine.log'a
# dusulur ve raporda 'elle' olarak gorunur.
#
# Frontmatter motorundur: id/created korunur, updated tazelenir ve eski surum
# HER yazimda 90-archive'a kopyalanir (Write-BeyinKavramNotu -Guncelle;
# ARSIVLEME ACIK). Ayni denetim -Arsivleme:$false'u da kaldirdi: kosu zaten
# idempotent oldugu icin degismeyen not hic yazilmaz, arsiv kopyasi yalniz
# gercek bir degisiklikte olusur - yani paylasilan geri donus agini bu betik
# icin delmenin bir kazanci yoktu, bedeli kurtarilamayan bir kayipti.
#
# Cikis kodlari (stdout son satir | process cikis kodu):
#   BAGLA_KURU        kuru calisma raporu (VARSAYILAN - yazilmadi)          | 0
#   BAGLA_OK          -Uygula ile yazildi                                   | 0
#   BAGLA_VEKTOR_YOK  indeks yok/okunamadi/baska model -> once: beyin gom   | 0
#   BAGLA_HATA_SLOT   derleyici slotu alinamadi, HICBIR not yazilmadi       | 4
#   BAGLA_HATA_ICSEL  beklenmedik hata (yarim not yok)                      | 5
# NEDEN SIFIR-DISI (2026-09-17): zamanli-kos.ps1 cocugun kodunu AYNEN dondurur.
# exit 0 demek Gorev Zamanlayici'da 0x0, makbuzda ZAMANLI_OK ve doktor'un
# 'zamanlanmis gorevler' satirinda YESIL demektir - hic yazamadan donen bir gece
# kosusu boylece scheduler duzeyinde GORUNMEZ olurdu. (Ayni ders zamanli-kos.ps1
# icinde KIMLIK_YOK=3 ile bir kez odendi; BAGLA_KURU/OK/VEKTOR_YOK gercekten
# beklenen durumlar oldugu icin 0 kalir.)
#
# Kullanim:
#   beyin bagla                   kuru calisma: ne degisirdi
#   beyin bagla-uygula            gercekten yaz
#   beyin bagla -MinCos 0.60      daha dar yakinlik esigi
#   beyin bagla -EnFazla 6        not basina daha cok komsu
#   beyin bagla -Json             makine okunur (otomasyon/doktor icin)

param(
    # TASINABILIRLIK: vault yolu GOMULU DEGIL. Oncelik: -Vault > BEYIN_VAULT >
    # betigin konumu (<vault>\motor\scripts\<betik>.ps1 -> iki seviye yukarisi).
    [string]$Vault = $(if ($env:BEYIN_VAULT) { $env:BEYIN_VAULT } else { Split-Path (Split-Path $PSScriptRoot -Parent) -Parent }),
    # 1.0 BILEREK disarida: notun kendisiyle esitligi aranmaz. Alt sinir da var:
    # cok dusuk bir esikte HER not HER notun "komsusu" olur ve bolum anlamini
    # kaybeder (bge-m3'te olculen anlamli aralik 0.50-0.70).
    [ValidateRange(0.10, 0.999)][double]$MinCos = 0.55,
    [ValidateRange(1, 25)][int]$EnFazla = 4,
    [switch]$Uygula,
    [switch]$Json
)

$ErrorActionPreference = 'SilentlyContinue'
# NEDEN: $Vault ilk KONUMSAL parametre; fazladan bir konumsal arguman Vault'a baglanir,
# lib.ps1 sessizce yuklenemez ve betik bos/yanlis sonucla exit 0 verir (ayni desen
# makbuz.ps1, bahcivan.ps1 ve denetle.ps1'de olculdu). SESLI dus.
if (-not $Vault) { $Vault = $(if ($env:BEYIN_VAULT) { $env:BEYIN_VAULT } else { Split-Path (Split-Path $PSScriptRoot -Parent) -Parent }) }
$vaultOk = $false
try { $vaultOk = [bool]($Vault -and (Test-Path -LiteralPath $Vault -PathType Container) -and (Test-Path -LiteralPath (Join-Path $Vault 'motor\hooks\lib.ps1') -PathType Leaf)) } catch { }
if (-not $vaultOk) { Write-Output "HATA: vault degil (motor\hooks\lib.ps1 yok): '$Vault'  - konumsal arguman -Vault'a baglanir; esik icin -MinCos <0.10-0.999>, komsu tavani icin -EnFazla <n> kullan"; exit 2 }
. (Join-Path $Vault 'motor\hooks\lib.ps1')
$p = Get-BeyinPaths -Vault $Vault
$inv = [Globalization.CultureInfo]::InvariantCulture
$simdi = Get-Date
$sw = [Diagnostics.Stopwatch]::StartNew()

# --- Sabitler -----------------------------------------------------------------
# Baslik TAM olarak budur: bolum bununla YAZILIR. BULUNURKEN lib.ps1'in paylasilan
# deseni kullanilir ($script:BeyinIlgiliBaslikRx) - o desen tr-TR'de dogal olarak
# yazilacak NOKTALI BUYUK I varyantini da kabul eder; ASCII-only bir desen o
# basligi goremez ve betik her kosuda IKINCI bir bolum eklerdi.
$BOLUM_BASLIK = '## Ilgili notlar'
# Bir satirlik kaynak beyani: okuyan kisi bu listeyi insan yargisi sanmasin.
$BOLUM_NOT = 'Bu bolum MAKINE BAKIMLIDIR: baglantilar notlarin gomme (bge-m3) benzerliginden turetilir, insan yargisi degildir; `beyin bagla` her kosuda yeniden uretir.'
# Beyan cumlesinin SURUMDEN BAGIMSIZ izi: cumle ileride degisirse eski surumu
# tasiyan notlar "elle yazilmis" sanilip sonsuza dek atlanmasin.
$BOLUM_NOT_IZ = 'Bu bolum MAKINE BAKIMLIDIR'
# Bizim urettigimiz madde: "- [[slug|Baslik]] - yakinlik 0.71". Aralikta bundan
# ve beyan cumlesinden baska bir sey varsa o aralik artik yalniz bizim degildir.
$RX_MADDE = '^\s*-\s*\[\[[^\]\r\n]+\]\]\s*-\s*yakinlik\s+[0-9]+[.,][0-9]+\s*$'
$MakbuzSlugTavan  = 60   # makbuz satiri sismesin; tam liste -Json ciktisinda zaten var
$MakbuzDosyaTavan = 60   # ayni tavan files[] icin: 132 girdilik tek satir 15 KB idi
$ListeTavan       = 40   # konsol raporunda satir satir gosterilen degisiklik tavani
# DERLEYICI MUTEKSI BEKLEME SURESI. 60 sn yapisal olarak yetersizdi: compile.ps1'in
# kendi ExecutionTimeLimit'i 3 SAAT ve gece gorevi 03:00'ta basliyor, bagla 03:15'te
# geliyor - 60 sn'lik bir bekleme o yarisi garantili kaybeder. 5 dakika, elle kosan
# kullaniciyi kilitlemeden gecenin normal derleme kuyrugunu bekler; suresi dolarsa
# HICBIR not yazilmaz, kod 4 ile cikilir ve gece gorevi kirmiziya duser.
$SlotBekleme      = 300

function Get-BaglaGuvenliMesaj([string]$M) {
    # Istisna mesaji MUTLAK YOL tasiyabilir. Makbuz ve engine.log git'e girebilir;
    # icinde kullanici adi BULUNMAMALI (denetle.ps1 ile ayni kural).
    $s = [string]$M
    if (-not $s) { return '' }
    try {
        $v = ([string]$p.Vault).TrimEnd('\')
        if ($v) { $s = [regex]::Replace($s, [regex]::Escape($v + '\'), '', $script:BeyinRxCI) }
        $h = ([string]$env:USERPROFILE).TrimEnd('\')
        if ($h) { $s = [regex]::Replace($s, [regex]::Escape($h), '~', $script:BeyinRxCI) }
    } catch { }
    return $s
}

function Get-BaglaMaskeliGovde {
    # KOD BLOKLARINI MASKELER. Bir kavram govdesindeki ``` / ~~~ cit'i icinde
    # satir basinda '## Ilgili notlar' GECEBILIR - bu ozelligi anlatan bir gunluk
    # logu derlendiginde tam olarak bu olur (compile.ps1 daylog'u kavram govdesine
    # cevirir; bugunun logu bu bolumu belgeliyor). Maskelenmezse o alinti bolum
    # BASLANGICI sayilir ve bir sonraki basliga kadar her sey silinir.
    #
    # Maske UZUNLUGU ve SATIR SAYISINI KORUR (her karakter 'x' olur): bu yuzden
    # maskeli metinde bulunan indeksler HAM govdede de birebir gecerlidir.
    param([string]$Body)
    $t = [string]$Body
    if (-not $t) { return '' }
    if (($t.IndexOf('```') -lt 0) -and ($t.IndexOf('~~~') -lt 0)) { return $t }
    $sb = New-Object System.Text.StringBuilder
    $cit = ''
    foreach ($par in [regex]::Split($t, '(?<=\n)')) {
        $ln = [string]$par
        if ($ln.Length -eq 0) { continue }
        $govdeSatir = $ln -replace '[\r\n]+$', ''
        $kuyruk = $ln.Substring($govdeSatir.Length)
        $bas = $govdeSatir.TrimStart()
        $isaret = ''
        if ($bas.StartsWith('```')) { $isaret = '```' } elseif ($bas.StartsWith('~~~')) { $isaret = '~~~' }
        if (-not $cit) {
            if ($isaret) { $cit = $isaret }
            [void]$sb.Append($ln)
        } elseif ($isaret -eq $cit) {
            $cit = ''
            [void]$sb.Append($ln)
        } else {
            [void]$sb.Append(('x' * $govdeSatir.Length) + $kuyruk)
        }
    }
    return $sb.ToString()
}

function Get-BaglaBolum {
    # Govdede "## Ilgili notlar" bolumunu bulur. Bolum BASLIKTA baslar ve BIR
    # SONRAKI BASLIKTA (herhangi bir seviye) ya da govdenin sonunda biter.
    # Donus: @{ Var; Bas; Son }  - Bas dahil, Son haric.
    #
    # Buyuk/kucuk harf duyarsizligi CultureInvariant'tir: bu makinenin kulturu
    # tr-TR ve 'Ilgili' bastaki noktali I ile yazilmistir; kultur-duyarli bir
    # eslesme bolumu SESSIZCE bulamaz, betik de her kosuda IKINCI bir bolum
    # eklerdi. (Ayni tuzak icin bkz. lib.ps1 Test-BeyinMatch.) Desen bes betigin
    # ORTAK sabitidir: $script:BeyinIlgiliBaslikRx - I, U+0130 ve U+0131'i kabul eder.
    param([string]$Body)
    $r = @{ Var = $false; Bas = -1; Son = -1 }
    $t = [string]$Body
    if (-not $t) { return $r }
    $maske = Get-BaglaMaskeliGovde -Body $t
    $m = [regex]::Match($maske, $script:BeyinIlgiliBaslikRx, $script:BeyinRxCIM)
    if (-not $m.Success) { return $r }
    $r.Var = $true
    $r.Bas = $m.Index
    $sonrasi = $m.Index + $m.Length
    $r.Son = $t.Length
    if ($sonrasi -lt $maske.Length) {
        $m2 = [regex]::Match($maske.Substring($sonrasi), '(?m)^#{1,6}[ \t]+\S')
        if ($m2.Success) { $r.Son = $sonrasi + $m2.Index }
    }
    return $r
}

function Get-BaglaElYazisi {
    # YONETILEN ARALIKTA BIZE AIT OLMAYAN ILK SATIR (yoksa bos dize).
    # Bize ait olan: baslik satiri, bos satir, beyan cumlesi ve
    # "- [[slug|Baslik]] - yakinlik 0.NN" maddeleri. Baska her sey INSAN (ya da
    # baska bir arac) yazisidir; uzerine yazilmaz, not atlanir.
    param([string]$Span)
    $s = [string]$Span
    if (-not $s) { return '' }
    $ilk = $true
    foreach ($ln in ($s -split "`r?`n")) {
        $t = ([string]$ln).Trim()
        if ($ilk) { $ilk = $false; continue }   # baslik satiri
        if (-not $t) { continue }
        if ($t.StartsWith($BOLUM_NOT_IZ)) { continue }
        if (Test-BeyinMatch -Text $t -Pattern $RX_MADDE) { continue }
        if ($t.Length -gt 120) { $t = $t.Substring(0, 120) + '...' }
        return $t
    }
    return ''
}

function New-BaglaGovde {
    # Bir GOVDEDEN, verilen madde listesiyle YENI govdeyi kurar. Saf fonksiyon:
    # ayni girdi -> ayni cikti. Iki yerden cagrilir - plan asamasinda (rapor icin)
    # ve KILIT ICINDE taze okunan govde uzerinde (gercek yazim icin). Ikisi ayni
    # kod olmazsa yazilan sey raporlanandan farkli olur.
    # Donus: @{ Ok; Govde; Durum; Oran; ElYazisi; BolumVar }
    param([string]$Govde, [string[]]$Maddeler)
    $r = @{ Ok = $true; Govde = ''; Durum = 'degismedi'; Oran = 0.6; ElYazisi = ''; BolumVar = $false }
    $t = [string]$Govde
    $md = @($Maddeler)
    $aralik = Get-BaglaBolum -Body $t
    $r.BolumVar = $aralik.Var
    if ($aralik.Var) {
        $el = Get-BaglaElYazisi -Span $t.Substring($aralik.Bas, $aralik.Son - $aralik.Bas)
        if ($el) { $r.Ok = $false; $r.ElYazisi = $el; $r.Govde = $t.Trim(); return $r }
    }
    $on  = if ($aralik.Var) { $t.Substring(0, $aralik.Bas).TrimEnd() } else { $t.TrimEnd() }
    $art = if ($aralik.Var) { ([string]$t.Substring($aralik.Son)).Trim() } else { '' }
    $artVar = -not [string]::IsNullOrWhiteSpace($art)

    if ($md.Count -eq 0) {
        # ESIGIN USTUNDE KOMSU YOK -> varsa bolumu KALDIR, yoksa dokunma.
        $yeni = if ($artVar) { $on + "`n`n" + $art } else { $on }
    } else {
        $sat = New-Object System.Collections.Generic.List[string]
        $sat.Add($BOLUM_BASLIK)
        $sat.Add('')
        $sat.Add($BOLUM_NOT)
        $sat.Add('')
        foreach ($m in $md) { $sat.Add([string]$m) }
        $blok = ($sat.ToArray() -join "`n")
        $yeni = if ($artVar) { $on + "`n`n" + $blok + "`n`n" + $art } else { $on + "`n`n" + $blok }
    }

    $eskiTrim = $t.Trim()
    $yeniTrim = $yeni.Trim()
    $durum = 'tazelendi'
    if ($eskiTrim -ceq $yeniTrim) { $durum = 'degismedi' }
    elseif (-not $aralik.Var) { $durum = 'eklendi' }
    elseif ($md.Count -eq 0) { $durum = 'kaldirildi' }

    # KISALMA KAPISININ ORANI (Write-BeyinKavramNotu -EnAzOran).
    #
    # Varsayilan %60 kapisi "model ozetleyip bilgi kaybetti" senaryosu icin var
    # ve EKLEME/TAZELEME'de yapisal olarak atesleyemez (govde yalniz buyur).
    # Ama KALDIRMA gercek bir kisalmadir: 412 karakterlik bir nottan ~450
    # karakterlik bolum cikarsa oran 0.41'e duser ve kapi kendi yazdigimiz
    # blogu geri almamizi ENGELLER - bolum sonsuza dek bayat kalirdi
    # (diskteki 132 notun 24'u bu boyutta; olculdu).
    #
    # Bu yuzden kapi ancak SU KANIT varken gevsetilir: kisalma miktari, TAM
    # OLARAK bu betigin yonettigi eski blogun boyunu asmiyor. Yani govdenin
    # bizim bolumumuz disinda tek karakteri bile kaybolmuyor. O zaman bile
    # taban 0.30'dur: govde ucte birin altina duserse yazim yine REDDEDILIR.
    # OLCUM TABANI ONEMLI: bu hesap $t'nin KENDISINDEN yapilir - yani cagiran
    # taze govdeyi verdiginde gevseme de taze govdeye gore hesaplanir. (Onceki
    # surum plan asamasindaki BAYAT govdeye gore hesapliyordu ve artik gecerli
    # olmayan bir govde icin 0.30'u verebiliyordu.)
    $eskiBlokUz = if ($aralik.Var) { $aralik.Son - $aralik.Bas } else { 0 }
    $oran = 0.6
    $kayip = $eskiTrim.Length - $yeniTrim.Length
    if ($kayip -gt 0 -and $kayip -le ($eskiBlokUz + 8) -and $yeniTrim.Length -lt [int]($eskiTrim.Length * 0.6)) { $oran = 0.30 }

    $r.Govde = $yeniTrim
    $r.Durum = $durum
    $r.Oran  = $oran
    return $r
}

$script:BaglaHizliYol = $false
function Initialize-BaglaHizliYol {
    # KOSINUS TARAMASI ICIN DERLENMIS IC DONGU.
    #
    # OLCUM (bu makine, 132 not x 1024 boyut = 8,85 milyon carpma-toplama):
    #   saf PowerShell ic dongu : 39,8 sn
    #   Add-Type (C#) ayni is   :  0,9 sn derleme + 0,025 sn tarama
    # Ikisi de AYNI cifti buldu (2677 cift, birebir). Tarama not sayisinda
    # KARESELDIR: 132 notta 33 sn katlanilabilir, 264 notta 2,5 dakika olur -
    # yani saf PowerShell yolu vault buyudukce gece gorevini yer.
    #
    # Add-Type .NET Framework'un csc.exe'sini cagirir; kilitli bir makinede,
    # yazilamayan bir TEMP'te ya da bir guvenlik urunu araya girdiginde
    # BASARISIZ OLABILIR (bir guvenlik urununun localhost trafigini engelledigi
    # olculdu - bkz. lib.ps1 Start-BeyinEmbedWarmup). Bu yuzden hizli yol bir
    # OPTIMIZASYONDUR, bagimlilik degil: derlenemezse saf PowerShell dongusu
    # kosar, sonuc aynidir, yalniz yavastir. Hangi yolun kostugu rapora yazilir.
    if ($script:BaglaHizliYol) { return $true }
    try {
        Add-Type -TypeDefinition @'
public static class BeyinBaglaCos {
    // Birim vektorlerde kosinus = ic carpim. gi[] = indeks icindeki GECERLI
    // (diskte karsiligi olan) kayitlarin sira numaralari.
    public static void Pairs(float[] a, int d, double min, int[] gi,
                             System.Collections.Generic.List<int> oi,
                             System.Collections.Generic.List<int> oj,
                             System.Collections.Generic.List<double> oc) {
        int n = gi.Length;
        for (int x = 0; x < n - 1; x++) {
            int bi = gi[x] * d;
            for (int y = x + 1; y < n; y++) {
                int bj = gi[y] * d;
                double s = 0;
                for (int k = 0; k < d; k++) { s += (double)a[bi + k] * (double)a[bj + k]; }
                if (s >= min) { oi.Add(gi[x]); oj.Add(gi[y]); oc.Add(s); }
            }
        }
    }
}
'@ -ErrorAction Stop | Out-Null
        $script:BaglaHizliYol = $true
    } catch {
        $script:BaglaHizliYol = $false
    }
    return $script:BaglaHizliYol
}

$script:mkYazildi = $false
function Stop-Bagla {
    # TEK CIKIS: makbuz + log + cikti + exit. Makbuz bir kez yazilir.
    #
    # CIKIS KODU BIR TANI SINYALIDIR, sus payi degil: zamanli-kos.ps1 cocugun
    # kodunu aynen dondurur, Gorev Zamanlayici onu LastTaskResult'a yazar ve
    # doktor'un 'zamanlanmis gorevler' satiri oradan bakar. Beklenen durumlar
    # (kuru kosu, basarili yazim, indeks yoklugu) 0; GERCEKTEN yapilamayan is
    # (slot alinamadi, ic hata) sifir-disi. Bkz. dosya basindaki 'Cikis kodlari'.
    param(
        [string]$Kod,
        [string]$Log,
        [object[]]$Files = @(),
        [string[]]$Concepts = @(),
        [hashtable]$Sonuc = $null,
        [string[]]$Metin = @(),
        [int]$CikisKodu = 0
    )
    if (-not $script:mkYazildi) {
        $script:mkYazildi = $true
        if ($Log) { Write-BeyinLog -Vault $Vault -Message "bagla: $Log" }
        Write-BeyinMakbuz -Paths $p -Script 'bagla' -Outcome $Kod -Files $Files -Concepts $Concepts `
            -DurationMs $sw.ElapsedMilliseconds -Note $Log
    }
    if ($Json) {
        if ($null -eq $Sonuc) { $Sonuc = @{ ok = $false; outcome = $Kod; note = $Log } }
        ConvertTo-Json -InputObject $Sonuc -Depth 6
    } else {
        foreach ($m in @($Metin)) { $m }
    }
    exit $CikisKodu
}

# =============================================================================
# 1) VEKTOR INDEKSI SART
# -----------------------------------------------------------------------------
# Indeks yoksa TAHMINE DUSULMEZ. Baslik kelimelerinden "ilgili not" uydurmak,
# okuyanin makine-uretimi bir listeyi anlamsal saniyor olmasi demektir; yanlis
# baglanti, baglanti olmamasindan kotudur. Sessizce ve kod 0 ile cikilir, ne
# yapilmasi gerektigi yazilir.
# =============================================================================
if (-not (Test-BeyinVectorReady -Paths $p)) {
    $datYol = Join-Path $p.ScrState 'kavram-vektor.dat'
    $binYol = Join-Path $p.ScrState 'kavram-vektor.bin'
    $vi0 = Get-BeyinVectorIndex -Paths $p
    $neden = 'indeks bos'
    if (-not (Test-Path -LiteralPath $datYol) -or -not (Test-Path -LiteralPath $binYol)) { $neden = 'indeks dosyasi yok' }
    elseif (-not $vi0) { $neden = 'indeks okunamadi (.bin boyu .dat ile uyusmuyor ya da bozuk)' }
    elseif ([string]$vi0.Meta.model -ne $script:BeyinEmbedModel) { $neden = "indeks baska modelle uretilmis ($($vi0.Meta.model) != $($script:BeyinEmbedModel))" }
    $json0 = @{
        ok = $false; outcome = 'BAGLA_VEKTOR_YOK'; ts = $simdi.ToString('o', $inv)
        neden = $neden; komut = 'beyin gom'; sureMs = $sw.ElapsedMilliseconds
    }
    Stop-Bagla -Kod 'BAGLA_VEKTOR_YOK' -Log "vektor indeksi kullanilamaz ($neden); once: beyin gom" -Sonuc $json0 -Metin @(
        "BAGLA_VEKTOR_YOK  $neden",
        '',
        'Capraz baglanti kavram notlarinin gomme vektorlerinden turetilir; indeks olmadan',
        'baglanti TAHMIN EDILMEZ (yanlis baglanti, baglanti olmamasindan kotudur).',
        '',
        '  Once :  beyin gom                (Ollama + bge-m3 gerekir)',
        "  Model yoksa:  ollama pull $($script:BeyinEmbedModel)",
        '  Sonra:  beyin bagla              (kuru)  /  beyin bagla-uygula'
    )
}

# =============================================================================
# 2) HESAPLA  (tek try: cikis her yolda asagidaki Stop-Bagla'dan gecer)
# =============================================================================
$cikis = $null
try {
    $vi = Get-BeyinVectorIndex -Paths $p
    $all = $vi.All
    $dim = $vi.Dim
    $nAll = $vi.N

    $conceptDir = Join-Path $p.Compiled 'concepts'
    $diskDosya = @{}
    foreach ($f in @(Get-ChildItem -LiteralPath $conceptDir -Filter '*.md' -File -ErrorAction SilentlyContinue)) {
        $diskDosya[([IO.Path]::GetFileNameWithoutExtension($f.Name)).ToLowerInvariant()] = $f
    }

    # INDEKS BAYATLIGI IKI YONLUDUR ve ikisi de sessizce yanlis sonuc uretir:
    #   - indekste olup diskte olmayan kayit -> silinmis nota baglanti (kirik link)
    #   - diskte olup indekste olmayan not   -> o not hic baglanti almaz/vermez
    # Ikisi de burada SAYILIR ve rapora yazilir; karar kullanicinin (beyin gom).
    $gecerli = New-Object System.Collections.Generic.List[int]
    $slugOf = New-Object string[] $nAll
    $indekstekiDisk = @{}
    for ($i = 0; $i -lt $nAll; $i++) {
        $s = [string]$vi.Meta.items[$i].slug
        $slugOf[$i] = $s
        $k = $s.ToLowerInvariant()
        if ($diskDosya.ContainsKey($k)) {
            $gecerli.Add($i)
            $indekstekiDisk[$k] = $true
        }
    }
    $g = @($gecerli.ToArray())
    $ng = $g.Count
    $diskteOlmayan = $nAll - $ng
    $indekssiz = New-Object System.Collections.Generic.List[string]
    foreach ($k in @($diskDosya.Keys)) { if (-not $indekstekiDisk.ContainsKey($k)) { $indekssiz.Add([string]$k) } }

    # INDEKS YASI AYRI BIR SEYDIR ve BASLI BASINA DURDURUCU DEGILDIR.
    # Test-BeyinVectorReady yalniz "indeks okunuyor mu, bos mu, dogru model mi"
    # diye bakar - BAYATLIK onun kapisi degil. Aylar once uretilmis bir indeks o
    # kapidan gecer ve baglantilar eski anlamlardan dokunur. Bu yuzden yas BURADA
    # olculur ve UYARI olarak raporlanir; kosu durmaz (bayat indeks yanlis degil,
    # yalniz eski; durdurmak gece gorevini hicbir sey yapamaz hale getirirdi).
    # OLCU: notun mtime'i indeksten 1 GUNDEN fazla yeniyse o not indekse
    # girmemis sayilir. 1 gun pay, bagla'nin KENDI yaziminin yanlis alarm
    # uretmemesi icindir (gom 03:10, bagla 03:15 - notlar indeksten birkac
    # dakika yeni olur).
    $datYolu = Join-Path $p.ScrState 'kavram-vektor.dat'
    $indeksZaman = $null
    $indeksYasGun = -1
    $bayatNot = 0
    try {
        $indeksZaman = (Get-Item -LiteralPath $datYolu -ErrorAction Stop).LastWriteTimeUtc
        $indeksYasGun = [math]::Round(((Get-Date).ToUniversalTime() - $indeksZaman).TotalDays, 1)
        $esik = $indeksZaman.AddDays(1)
        foreach ($f in @($diskDosya.Values)) { if ($f.LastWriteTimeUtc -gt $esik) { $bayatNot++ } }
    } catch { }

    # --- Notlari BIR KEZ ayristir (baslik + govde). Komsunun BASLIGI da lazim,
    #     bu yuzden hepsi bolum uretiminden ONCE okunur.
    $idxItems = @(Get-BeyinConceptIndex -Paths $p)
    $baslikMap = @{}
    foreach ($it in $idxItems) {
        $baslikMap[([IO.Path]::GetFileNameWithoutExtension([string]$it.dosya)).ToLowerInvariant()] = [string]$it.baslik
    }

    $notlar = @{}
    $okunamayan = New-Object System.Collections.Generic.List[string]
    foreach ($i in $g) {
        $slug = $slugOf[$i]
        $dosya = $diskDosya[$slug.ToLowerInvariant()]
        $nt = Split-BeyinNote -Path $dosya.FullName
        if (-not $nt.Ok) { $okunamayan.Add($slug); continue }
        $bas = [string]$baslikMap[$slug.ToLowerInvariant()]
        if (-not $bas) { $bas = [string]$nt.Fields['title'] }
        if (-not $bas) {
            $mh = [regex]::Match([string]$nt.Body, '(?m)^#\s+(.+)$')
            if ($mh.Success) { $bas = $mh.Groups[1].Value.Trim() }
        }
        if (-not $bas) { $bas = $slug }
        # Wikilink govdesini bozacak karakterler temizlenir ('|' ve koseli parantez).
        $gorunen = [regex]::Replace(($bas -replace '[\[\]\|]', ' '), '\s{2,}', ' ').Trim()
        if (-not $gorunen) { $gorunen = $slug }
        $notlar[$i] = @{
            Slug     = $slug
            Path     = $dosya.FullName
            Body     = [string]$nt.Body
            FmBaslik = [string]$nt.Fields['title']
            Gorunen  = $gorunen
        }
    }

    # =========================================================================
    # 3) KOSINUS TARAMASI  (model cagrisi YOK, ag YOK)
    # -------------------------------------------------------------------------
    # Vektorler BIRIM uzunlukta (gom.ps1 ConvertTo-BeyinUnitVector uygular), bu
    # yuzden kosinus = ic carpim. Tarama not sayisinda KARESELDIR; her cift bir
    # kez hesaplanir ve IKI YONE birden yazilir (isi yariya indirir). Sure ve
    # HANGI YOLUN kostugu her kosuda basilir - sessiz yavaslamayi kullanici gorur.
    # =========================================================================
    $swTara = [Diagnostics.Stopwatch]::StartNew()
    $komsu = @{}
    foreach ($i in $g) { $komsu[$i] = New-Object System.Collections.Generic.List[object] }
    $hizli = Initialize-BaglaHizliYol
    if ($hizli) {
        try {
            $gInt = [int[]]$gecerli.ToArray()
            $oi = New-Object 'System.Collections.Generic.List[int]'
            $oj = New-Object 'System.Collections.Generic.List[int]'
            $oc = New-Object 'System.Collections.Generic.List[double]'
            [BeyinBaglaCos]::Pairs($all, $dim, $MinCos, $gInt, $oi, $oj, $oc)
            for ($t = 0; $t -lt $oc.Count; $t++) {
                $komsu[$oi[$t]].Add([pscustomobject]@{ Idx = $oj[$t]; Cos = [double]$oc[$t] })
                $komsu[$oj[$t]].Add([pscustomobject]@{ Idx = $oi[$t]; Cos = [double]$oc[$t] })
            }
        } catch {
            # Derlendi ama cagri patladi: yavas yola don, sonuc yine dogru olsun.
            $hizli = $false
            foreach ($i in $g) { $komsu[$i] = New-Object System.Collections.Generic.List[object] }
        }
    }
    if (-not $hizli) {
        $vecI = New-Object float[] $dim
        for ($a = 0; $a -lt $ng - 1; $a++) {
            $i = $g[$a]
            [Array]::Copy($all, $i * $dim, $vecI, 0, $dim)
            for ($b = $a + 1; $b -lt $ng; $b++) {
                $j = $g[$b]
                $bj = $j * $dim
                $acc = 0.0
                for ($k = 0; $k -lt $dim; $k++) { $acc += $vecI[$k] * $all[$bj + $k] }
                if ($acc -ge $MinCos) {
                    $komsu[$i].Add([pscustomobject]@{ Idx = $j; Cos = [double]$acc })
                    $komsu[$j].Add([pscustomobject]@{ Idx = $i; Cos = [double]$acc })
                }
            }
        }
    }
    $swTara.Stop()
    $taraYol = if ($hizli) { 'derlenmis' } else { 'saf PowerShell' }

    # =========================================================================
    # 4) KOMSU SECIMI + KARSILIKLILIK
    # -------------------------------------------------------------------------
    # Kosinus SIMETRIKTIR ama "en yakin 4" DEGILDIR: A'nin ilk dordunde B olabilir,
    # B'nin ilk dordunde A olmayabilir. -EnFazla kirpmasi bu yuzden yonlu bir graf
    # uretir ve bazi notlar hicbir listeye giremez.
    #
    # OLCUM (canli vault, MinCos 0.55 / EnFazla 4): 510 kenar, 0 cozulmeyen link,
    # gelen derece en az 0 en cok 22 - ve 132 notun 13'u kimsenin ilk dordunde
    # DEGIL. Yani "91 not gelen baglanti almiyor" problemi 13'e iniyordu, 0'a
    # degil; artigi rapor etmemek olcumu yarim birakmak olurdu.
    #
    # KARSILIKLILIK PASI bunu kapatir: gelen derecesi 0 kalan her not, KENDI en
    # yakin komsusunun listesine eklenir (karsilikli kenar). Bu, o listeyi
    # -EnFazla'nin bir ustune cikarabilir - bilincli: tavan "kalabaligi onlemek"
    # icindir, "bir notu graftan dislamak" icin degil. Kac kenar boyle eklendigi
    # raporda AYRICA yazilir, kirpma sayisiyla birlikte.
    # =========================================================================
    $secim = @{}        # i -> secilmis komsu kayitlari (cos'a gore azalan)
    $hamSay = @{}       # i -> esigin ustundeki TOPLAM (kirpilmamis) komsu sayisi
    $kirpilanNot = 0
    $komsusuz = 0
    $sirasi = New-Object System.Collections.Generic.List[int]
    foreach ($i in $g) {
        if (-not $notlar.ContainsKey($i)) { continue }
        $sirasi.Add([int]$i)
        # PS 5.1 TUZAGI (bu betikte olculdu): @($list) bir
        # System.Collections.Generic.List[object] uzerinde 'Argument types do not
        # match' FIRLATIR (List[string] ve List[int] firlatmaz - yalniz [object]).
        # Motorun her yerinde .ToArray() gecilmesinin sebebi bu; burada da oyle.
        $sirali = @($komsu[$i].ToArray() | Sort-Object Cos -Descending)
        # AYRISTIRILAMAYAN KOMSU ONCE ELENIR, kirpmadan da sayimdan da once.
        # Eskiden eleme madde yazilirken yapiliyordu ve su BOS BLOK uretilebiliyordu:
        # esigin ustundeki komsularin hepsi Split-BeyinNote'tan gecememisse
        # $secilen.Count > 0 oldugu icin "kaldir" dali secilmiyor, ama tek bir madde
        # de yazilamiyordu - nota BASLIK + beyan cumlesi, SIFIR madde dusuyordu.
        $sirali = @($sirali | Where-Object { $notlar.ContainsKey([int]$_.Idx) })
        $hamSay[$i] = $sirali.Count
        if ($sirali.Count -gt $EnFazla) { $kirpilanNot++ }
        $secim[$i] = @($sirali | Select-Object -First $EnFazla)
        if (@($secim[$i]).Count -eq 0) { $komsusuz++ }
    }

    $gelenSay = @{}
    foreach ($i in @($sirasi.ToArray())) { $gelenSay[[int]$i] = 0 }
    foreach ($i in @($sirasi.ToArray())) {
        foreach ($x in @($secim[[int]$i])) { $gelenSay[[int]$x.Idx] = [int]$gelenSay[[int]$x.Idx] + 1 }
    }
    $karsilikKenar = 0
    foreach ($i in @($sirasi.ToArray())) {
        $ii = [int]$i
        if ([int]$gelenSay[$ii] -ne 0) { continue }
        $benim = @($secim[$ii])
        # Esigin ustunde hic komsusu olmayan not KARSILIKLILIKLA DA kurtarilamaz:
        # baglanacagi bir sey yok. Cozumu esik, bu pas degil (-MinCos).
        if ($benim.Count -eq 0) { continue }
        $j = [int]$benim[0].Idx
        if (-not $secim.ContainsKey($j)) { continue }
        $zaten = $false
        foreach ($y in @($secim[$j])) { if ([int]$y.Idx -eq $ii) { $zaten = $true; break } }
        if ($zaten) { continue }
        $ek = [pscustomobject]@{ Idx = $ii; Cos = [double]$benim[0].Cos; Karsilik = $true }
        $secim[$j] = @((@($secim[$j]) + @($ek)) | Sort-Object Cos -Descending)
        $gelenSay[$ii] = 1
        $karsilikKenar++
    }
    $gelenSifir = @(@($sirasi.ToArray()) | Where-Object { [int]$gelenSay[[int]$_] -eq 0 }).Count

    # =========================================================================
    # 4b) BOLUMU URET / TAZELE / KALDIR  (yazmadan once KARSILASTIR)
    # =========================================================================
    $planlar = New-Object System.Collections.Generic.List[object]
    foreach ($i in @($sirasi.ToArray())) {
        $ii = [int]$i
        $n = $notlar[$ii]
        $secilen = @($secim[$ii])
        $maddeler = New-Object System.Collections.Generic.List[string]
        $komsuListe = New-Object System.Collections.Generic.List[object]
        foreach ($x in $secilen) {
            $kn = $notlar[[int]$x.Idx]
            # LINK BICIMI (2026-09-17, olculdu): baglantiyi YAZAN not zaten
            # 86-compiled/concepts altinda; '[[concepts/<slug>]]' oradan
            # 'concepts/concepts/<slug>' demek olur ve COZULMEZ (brain-cli 510
            # kirik link saydi). index.md 86-compiled kokunde durdugu icin
            # 'concepts/<slug>' onun icin dogru; kardes notlar icin CIPLAK slug
            # dogru bicimdir - mevcut el yazimi 'Iliskili: [[<slug>]]' baglantilari
            # da boyle ve coquluyorlar.
            $maddeler.Add('- [[' + $kn.Slug + '|' + $kn.Gorunen + ']] - yakinlik ' + ([double]$x.Cos).ToString('0.00', $inv))
            $komsuListe.Add([pscustomobject]@{ slug = $kn.Slug; cos = [math]::Round([double]$x.Cos, 3); karsilik = [bool]$x.Karsilik })
        }
        $md = @($maddeler.ToArray())
        $y = New-BaglaGovde -Govde ([string]$n.Body) -Maddeler $md

        $baslikYaz = [string]$n.FmBaslik
        if (-not $baslikYaz) { $baslikYaz = [string]$n.Gorunen }
        $durum = [string]$y.Durum
        $neden = ''
        if (-not $y.Ok) {
            # ELLE YAZILMIS ARALIK: uzerine YAZILMAZ. Bir insan basligin altina bir
            # cumle yazdiysa onu sessizce silmek, kurtarilamayan bir kayiptir.
            $durum = 'elle'
            $neden = 'bolumde bize ait olmayan satir: ' + [string]$y.ElYazisi
        }
        $planlar.Add([pscustomobject]@{
            Slug     = $n.Slug
            Path     = [string]$n.Path
            Baslik   = $baslikYaz
            Durum    = $durum
            Govde    = [string]$y.Govde
            HamGovde = [string]$n.Body
            Maddeler = $md
            Oran     = [double]$y.Oran
            Komsu    = @($komsuListe.ToArray())
            Kirpildi = ([int]$hamSay[$ii] -gt $EnFazla)
            HamKomsu = [int]$hamSay[$ii]
            Gelen    = [int]$gelenSay[$ii]
            Once     = [long](-1)
            Sonra    = [long](-1)
            Neden    = $neden
        })
    }

    $degisecek = @($planlar | Where-Object { $_.Durum -ne 'degismedi' -and $_.Durum -ne 'elle' })

    # =========================================================================
    # 5) YAZ (yalniz -Uygula)
    # -------------------------------------------------------------------------
    # DERLEYICI MUTEKSI: kavram notu yazimi OKU-DEGISTIR-YAZ'dir ve compiled.lock
    # onu KORUMAZ (al.ps1 Enter-AlSlot aciklamasi). compile.ps1 ve al.ps1 kendini
    # 'compile-slot' havuzuyla seri hale getiriyor; bagla da ayni havuzu alir.
    #
    # AMA KILIT TEK BASINA YETMEZ - VE ONCEKI SURUM TAM BURADA YANILIYORDU:
    # govdeler kilitten ONCE okunuyor, kilit yalniz YAZMA icin aliniyordu. Yani
    # korunmasi gereken OKU-DEGISTIR-YAZ'in 'oku' ucu kilidin disindaydi.
    # Somut kayip senaryosu: derle 03:00'ta basliyor (ExecutionTimeLimit 3 saat),
    # bagla 03:15'te X notunu okuyor; compile/al X'e '## Guncelleme <gun>' blogu
    # ekleyip slotu birakiyor; bagla slotu aliyor ve ELINDEKI ESKI govdeyi
    # yaziyor - eklenen blok yok oluyor. %60 kapisi bunu yakalamaz (tipik ek
    # govdenin ~%20'sidir). Ayni pencere 'beyin al' ile 'beyin bagla-uygula'
    # ayni anda kosunca da acilir.
    #
    # COZUM: kilidin icinde her not TAZE okunur ve bolum O govde uzerinden
    # yeniden kurulur (New-BaglaGovde ayni saf fonksiyondur). Plan asamasi artik
    # yalniz RAPOR ve hangi notlarin ise gerek duydugudur; diske giden govde her
    # zaman kilit icinde okunmus govdedir. Bu, kilidi kosinus taramasi boyunca
    # tutmaktan da iyidir: derleyici 30+ saniye bosuna beklemez.
    # =========================================================================
    $yazilan = New-Object System.Collections.Generic.List[object]
    $mkFiles = New-Object System.Collections.Generic.List[object]
    $reddedilen = 0
    $hatali = 0
    $tazeFark = 0    # plan okumasindan sonra diskte DEGISMIS not (kilit ici taze okuma yakaladi)
    $tazeNoop = 0    # taze govdeye gore yapacak is kalmamis not
    $slotYok = $false
    if ($Uygula -and $degisecek.Count -gt 0) {
        $slot = Enter-BeyinSlot -Paths $p -MaxSlots 1 -Prefix 'compile-slot'
        if (-not $slot) {
            if (-not $Json) { "Derleyici slotu dolu (derle/al kosuyor); en fazla $SlotBekleme sn bekleniyor..." }
            $swSlot = [Diagnostics.Stopwatch]::StartNew()
            while ($true) {
                $slot = Enter-BeyinSlot -Paths $p -MaxSlots 1 -Prefix 'compile-slot'
                if ($slot) { break }
                if ($swSlot.Elapsed.TotalSeconds -ge $SlotBekleme) { break }
                Start-Sleep -Milliseconds 500
            }
        }
        if (-not $slot) {
            $slotYok = $true
        } else {
            try {
                foreach ($pl in $degisecek) {
                    # TAZE OKUMA - KILIDIN ICINDE. Bkz. yukaridaki mutex notu.
                    $taze = Split-BeyinNote -Path ([string]$pl.Path)
                    if (-not $taze.Ok) {
                        $hatali++
                        $pl.Durum = 'hata'
                        $pl.Neden = 'not taze okunamadi'
                        Write-BeyinLog -Vault $Vault -Message "bagla: '$($pl.Slug)' ATLANDI - kilit icinde taze okunamadi"
                        continue
                    }
                    $tazeGovde = [string]$taze.Body
                    if (($tazeGovde.Trim()) -cne (([string]$pl.HamGovde).Trim())) {
                        $tazeFark++
                        Write-BeyinLog -Vault $Vault -Message "bagla: '$($pl.Slug)' plan okumasindan sonra diskte degismis; bolum TAZE govde uzerinden kuruldu (kayip yok)"
                    }
                    $y2 = New-BaglaGovde -Govde $tazeGovde -Maddeler @($pl.Maddeler)
                    if (-not $y2.Ok) {
                        $pl.Durum = 'elle'
                        $pl.Neden = 'bolumde bize ait olmayan satir: ' + [string]$y2.ElYazisi
                        Write-BeyinLog -Vault $Vault -Message "bagla: '$($pl.Slug)' ATLANDI - $($pl.Neden)"
                        continue
                    }
                    if ([string]$y2.Durum -eq 'degismedi') {
                        # Plan asamasindan beri baskasi ayni sonucu yazmis ya da not
                        # degismis: YAZMA. Gereksiz 'updated' damgasi ve arsiv kopyasi yok.
                        $pl.Durum = 'degismedi'
                        $tazeNoop++
                        continue
                    }
                    $pl.Durum = [string]$y2.Durum
                    $pl.Govde = [string]$y2.Govde
                    $pl.Oran = [double]$y2.Oran
                    $w = Write-BeyinKavramNotu -Paths $p -Name ($pl.Slug + '.md') -Title $pl.Baslik `
                        -Body $pl.Govde -SourceRefs @('engine:bagla.ps1') -Guncelle -EnAzOran ([double]$pl.Oran)
                    $pl.Once = [long]$w.Before
                    $pl.Sonra = [long]$w.After
                    if ($w.Ok) {
                        $yazilan.Add($pl)
                        $mkFiles.Add(@{ p = (ConvertTo-BeyinMakbuzYol -Paths $p -Path $w.Path); b = [long]$w.Before; a = [long]$w.After })
                    } else {
                        $pl.Neden = [string]$w.Reason
                        # KISALMA KAPISI burada ASLA atesmemeli: bolum yalniz eklenir ya da
                        # ayni yere geri konur. Atesliyorsa varsayim bozulmustur - not
                        # ATLANIR ve iz birakilir (sessiz kayip yok).
                        if (Test-BeyinMatch -Text $pl.Neden -Pattern 'REDDEDILDI') {
                            $reddedilen++
                            $pl.Durum = 'reddedildi'
                            Write-BeyinLog -Vault $Vault -Message "bagla: '$($pl.Slug)' ATLANDI - kisalma kapisi atesledi: $($pl.Neden)"
                        } else {
                            $hatali++
                            $pl.Durum = 'hata'
                            Write-BeyinLog -Vault $Vault -Message "bagla: '$($pl.Slug)' yazilamadi: $(Get-BaglaGuvenliMesaj $pl.Neden)"
                        }
                    }
                }
            } finally { Exit-BeyinSlot -Handle $slot }
        }
    }

    # =========================================================================
    # 6) SONUC
    # =========================================================================
    # SAYIMLAR PLAN NESNELERINDEN OKUNUR ve yazma asamasi bu nesnelerin Durum'unu
    # gunceller (taze okuma 'degismedi'ye cevirebilir, 'elle'ye dusurebilir).
    # Bu yuzden sayim yazmadan SONRA yapilir: rapor niyeti degil, OLANI anlatir.
    $sayEklendi    = @($planlar | Where-Object { $_.Durum -eq 'eklendi' }).Count
    $sayTazelendi  = @($planlar | Where-Object { $_.Durum -eq 'tazelendi' }).Count
    $sayKaldirildi = @($planlar | Where-Object { $_.Durum -eq 'kaldirildi' }).Count
    $sayDegismedi  = @($planlar | Where-Object { $_.Durum -eq 'degismedi' }).Count
    $sayElle       = @($planlar | Where-Object { $_.Durum -eq 'elle' }).Count
    $bolumluNot    = @($planlar | Where-Object { @($_.Komsu).Count -gt 0 }).Count

    $notJson = New-Object System.Collections.Generic.List[object]
    foreach ($pl in $planlar) {
        $notJson.Add([pscustomobject]@{
            slug     = $pl.Slug
            durum    = $pl.Durum
            komsu    = @($pl.Komsu)
            hamKomsu = $pl.HamKomsu
            kirpildi = $pl.Kirpildi
            gelen    = $pl.Gelen
            once     = $pl.Once
            sonra    = $pl.Sonra
            neden    = $pl.Neden
        })
    }

    $kod = if ($slotYok) { 'BAGLA_HATA_SLOT' } elseif ($Uygula) { 'BAGLA_OK' } else { 'BAGLA_KURU' }
    $indeksOzet = @{ vektor = $nAll; gecerli = $ng; diskKavram = $diskDosya.Count; indekssizNot = $indekssiz.Count
                     diskteOlmayanKayit = $diskteOlmayan; okunamayan = $okunamayan.Count
                     yasGun = $indeksYasGun; indekstenYeniNot = $bayatNot }
    $sayimOzet  = @{ eklendi = $sayEklendi; tazelendi = $sayTazelendi; kaldirildi = $sayKaldirildi
                     degismedi = $sayDegismedi; elle = $sayElle; reddedilen = $reddedilen; hata = $hatali
                     yazilan = $yazilan.Count; tazeFark = $tazeFark; tazeNoop = $tazeNoop }
    $kapsamOzet = @{ bolumluNot = $bolumluNot; komsusuzNot = $komsusuz; kirpilanNot = $kirpilanNot
                     karsilikKenar = $karsilikKenar; gelenSifirNot = $gelenSifir }
    $sonuc = @{
        ok       = (-not $slotYok)
        outcome  = $kod
        ts       = $simdi.ToString('o', $inv)
        uygula   = [bool]$Uygula
        minCos   = $MinCos
        enFazla  = $EnFazla
        indeks   = $indeksOzet
        sayim    = $sayimOzet
        kapsam   = $kapsamOzet
        taramaMs = $swTara.ElapsedMilliseconds
        taramaYol = $taraYol
        sureMs   = $sw.ElapsedMilliseconds
        notlar   = @($notJson.ToArray())
    }

    # --- Makbuz alanlari ---
    # HER IKI LISTE DE TAVANLIDIR. files[] eskiden TAVANSIZDI: 132 notluk bir
    # kosu tek satirda 15 KB JSONL uretti ve doktor ile makbuz.ps1 her saglik
    # kontrolunde 90 gunluk bu satirlari okuyor. Kirpilan kisim yerine TOPLAM
    # bayt farki yazilir - sayi kaybolmaz, satir sismez. Tam liste -Json'da.
    $touched = New-Object System.Collections.Generic.List[string]
    foreach ($x in @($(if ($Uygula) { @($yazilan.ToArray()) } else { $degisecek }))) { $touched.Add([string]$x.Slug) }
    $mkConcepts = @(@($touched.ToArray()) | Select-Object -First $MakbuzSlugTavan)
    $mkKirpma = ''
    if ($touched.Count -gt $MakbuzSlugTavan) { $mkKirpma = " (+$($touched.Count - $MakbuzSlugTavan) slug makbuzda kirpildi; tam liste: -Json)" }
    $mkHepsi = @($mkFiles.ToArray())
    $mkFilesKirpik = @($mkHepsi | Select-Object -First $MakbuzDosyaTavan)
    $toplamOnce = 0; $toplamSonra = 0
    foreach ($fx in $mkHepsi) { $toplamOnce += [long]$fx.b; $toplamSonra += [long]$fx.a }
    $mkDosyaKirpma = ''
    if ($mkHepsi.Count -gt $MakbuzDosyaTavan) {
        $mkDosyaKirpma = " (+$($mkHepsi.Count - $MakbuzDosyaTavan) dosya makbuzda kirpildi; toplam $toplamOnce -> $toplamSonra bayt)"
    }

    $note = "KURU: degisecek=$($degisecek.Count)"
    if ($Uygula) { $note = "yazildi=$($yazilan.Count)" }
    $note += " (eklendi=$sayEklendi tazelendi=$sayTazelendi kaldirildi=$sayKaldirildi) degismedi=$sayDegismedi"
    if ($sayElle -gt 0) { $note += " elle=$sayElle" }
    if ($Uygula) { $note += " reddedilen=$reddedilen hata=$hatali" }
    if ($tazeFark -gt 0) { $note += " tazeFark=$tazeFark" }
    if ($karsilikKenar -gt 0) { $note += " karsilik=$karsilikKenar" }
    $note += " · $ng/$($diskDosya.Count) kavram indekste · MinCos=$($MinCos.ToString('0.000', $inv)) EnFazla=$EnFazla$mkKirpma$mkDosyaKirpma"
    if ($slotYok) { $note = "derleyici slotu ${SlotBekleme} sn'de alinamadi; $($degisecek.Count) not YAZILMADI (veri kaybi yok, tekrar calistir)" }

    # --- Konsol raporu ---
    $metin = New-Object System.Collections.Generic.List[string]
    $metin.Add("BAGLA  $($simdi.ToString('yyyy-MM-dd HH:mm', $inv))  |  esik $($MinCos.ToString('0.000', $inv))  |  not basina en fazla $EnFazla komsu$(if (-not $Uygula) { '  [KURU CALISMA]' })")
    $metin.Add("Indeks : $nAll vektor, $ng tanesi diskte var$(if ($diskteOlmayan) { " ($diskteOlmayan kayit artik diskte yok, atlandi)" })$(if ($indeksYasGun -ge 0) { " · $($indeksYasGun.ToString('0.0', $inv)) gunluk" })")
    $metin.Add("Diskte : $($diskDosya.Count) kavram notu$(if ($indekssiz.Count) { " · $($indekssiz.Count) tanesi indekste YOK (baglanti alamaz/veremez) -> beyin gom" })$(if ($okunamayan.Count) { " · $($okunamayan.Count) not ayristirilamadi" })")
    if ($bayatNot -gt 0) {
        # Test-BeyinVectorReady BAYATLIGA BAKMAZ (yalniz okunabilirlik + model adi):
        # eski bir indeks o kapidan gecer ve baglantilar eski anlamlardan dokunur.
        $metin.Add("         INDEKS BAYAT: $bayatNot not indeksten en az 1 gun daha yeni - o notlarin baglantilari ESKI metinden turetiliyor -> beyin gom")
    }
    $metin.Add("Komsu  : $bolumluNot not baglanti aldi, $komsusuz not esigin ustunde komsu bulamadi")
    if ($kirpilanNot -gt 0) {
        $metin.Add("         KIRPILDI: $kirpilanNot notta esigin ustunde $EnFazla'ten fazla komsu vardi, liste -EnFazla ile kesildi")
    }
    # KARSILIKLILIK DURUSTLUGU: kirpma yonlu bir graf uretir; kac notun gelen
    # baglantisi kirpma yuzunden sifir kaldigi ve kacinin bu pasla kurtarildigi
    # ACIKCA yazilir - "91 not baglantisiz" olcumunun artigi gorunmez kalmasin.
    $metin.Add("         Karsiliklilik: $karsilikKenar kenar eklendi (kirpma yuzunden gelen baglantisi kalmayan notlar icin)")
    if ($gelenSifir -gt 0) {
        $metin.Add("         HALA GELEN BAGLANTISI YOK: $gelenSifir not - hepsinin esigin ustunde hic komsusu yok (-MinCos dusur)")
    }
    if ($komsusuz -gt 0) {
        $metin.Add("         Esik $($MinCos.ToString('0.000', $inv)) bu $komsusuz not icin cok dar olabilir (-MinCos ile dusur)")
    }
    $metin.Add('')
    $metin.Add("DEGISIKLIK  eklendi $sayEklendi  |  tazelendi $sayTazelendi  |  kaldirildi $sayKaldirildi  |  degismedi $sayDegismedi$(if ($sayElle) { "  |  elle $sayElle" })$(if ($Uygula) { "  |  reddedilen $reddedilen  |  hata $hatali" })")
    if ($degisecek.Count -gt 0) {
        $gosterilen = @($degisecek | Select-Object -First $ListeTavan)
        foreach ($x in $gosterilen) {
            $ek = ''
            if ($Uygula -and $x.Once -ge 0 -and $x.Sonra -ge 0) { $ek = "  ($($x.Once) -> $($x.Sonra) bayt)" }
            elseif ($x.Neden) { $ek = "  ($(Get-BaglaGuvenliMesaj $x.Neden))" }
            $metin.Add(("  {0,-11} {1}  [{2} komsu]{3}" -f $x.Durum, $x.Slug, @($x.Komsu).Count, $ek))
        }
        if ($degisecek.Count -gt $gosterilen.Count) {
            $metin.Add("  ... ve $($degisecek.Count - $gosterilen.Count) not daha (tam liste: -Json)")
        }
    } else {
        $metin.Add('  (degisiklik yok - bolumler guncel)')
    }
    if ($sayElle -gt 0) {
        $metin.Add('')
        $metin.Add("ELLE YAZILMIS: $sayElle notun '## Ilgili notlar' bolumunde bize ait olmayan satir var; o notlar ATLANDI (icerik silinmedi).")
        foreach ($x in @(@($planlar | Where-Object { $_.Durum -eq 'elle' }) | Select-Object -First 10)) {
            $metin.Add("  atlandi     $($x.Slug)  ($(Get-BaglaGuvenliMesaj $x.Neden))")
        }
        $metin.Add('  Cozum: o satirlari basliktan CIKAR (baska bir baslik altina tasi) - bolumu motor yonetir.')
    }
    $metin.Add('')
    if ($slotYok) {
        $metin.Add("Derleyici slotu ${SlotBekleme} sn'de alinamadi (baska bir derleme/alim kosuyor).")
        $metin.Add('Hicbir not yazilmadi; birkac dakika sonra tekrar dene.')
    } elseif (-not $Uygula) {
        $metin.Add('KURU CALISMA - hicbir not yazilmadi. Gercekten yazmak icin: beyin bagla-uygula')
    } else {
        if ($yazilan.Count -gt 0) {
            $metin.Add("$($yazilan.Count) not yazildi; onceki surumler 90-archive'a kopyalanir (alinamayan kopya engine.log'a dusulur).")
        } else {
            $metin.Add('Hicbir not yazilmadi: bolumler zaten guncel (idempotent kosu - arsiv kopyasi da olusmadi).')
        }
        if ($tazeFark -gt 0) { $metin.Add("$tazeFark not plan okumasindan sonra diskte degismisti: bolum TAZE govde uzerinden kuruldu (kayip yok).") }
        if ($tazeNoop -gt 0) { $metin.Add("$tazeNoop notta yapacak is kalmamisti (baska bir kosu ayni sonucu yazmis) - yazilmadi.") }
        if ($reddedilen -gt 0) { $metin.Add("$reddedilen not ATLANDI: kisalma kapisi atesledi - ayrinti engine.log'da.") }
        if ($hatali -gt 0) { $metin.Add("$hatali not yazilamadi - ayrinti engine.log'da.") }
    }
    $metin.Add("($([math]::Round($sw.ElapsedMilliseconds / 1000.0, 1)) sn; kosinus taramasi $([math]::Round($swTara.ElapsedMilliseconds / 1000.0, 1)) sn, $taraYol yol$(if (-not $hizli) { ' - derlenmis ic dongu kurulamadi, bu yol karesel ve yavastir' }))")
    $metin.Add($kod)

    $cikis = @{ Kod = $kod; Log = $note; Files = $mkFilesKirpik; Concepts = $mkConcepts; Sonuc = $sonuc; Metin = @($metin.ToArray()) }
} catch {
    $mesaj = Get-BaglaGuvenliMesaj $_.Exception.Message
    $cikis = @{ Kod = 'BAGLA_HATA_ICSEL'; Log = "beklenmedik hata: $mesaj"; Files = @(); Concepts = @(); Sonuc = $null; Metin = @("BAGLA_HATA_ICSEL  $mesaj") }
}

if ($null -eq $cikis) {
    $cikis = @{ Kod = 'BAGLA_HATA_ICSEL'; Log = 'sonuc uretilemedi'; Files = @(); Concepts = @(); Sonuc = $null; Metin = @('BAGLA_HATA_ICSEL  sonuc uretilemedi') }
}
# CIKIS KODU: beklenen durumlar 0, YAPILAMAYAN IS sifir-disi. Bkz. dosya basi.
$cikisKodu = 0
if ([string]$cikis.Kod -eq 'BAGLA_HATA_SLOT') { $cikisKodu = 4 }
elseif ([string]$cikis.Kod -eq 'BAGLA_HATA_ICSEL') { $cikisKodu = 5 }
Stop-Bagla -Kod ([string]$cikis.Kod) -Log ([string]$cikis.Log) -Files @($cikis.Files) -Concepts @($cikis.Concepts) `
    -Sonuc $cikis.Sonuc -Metin @($cikis.Metin) -CikisKodu $cikisKodu
