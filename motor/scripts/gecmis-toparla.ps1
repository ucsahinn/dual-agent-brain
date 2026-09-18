# gecmis-toparla.ps1 - Birikmis YEREL transkript yiginini gunluk loglara isler.
#
# Farki: gecmis-import.ps1 DIS export'lari (ChatGPT/Claude/Gemini takeout)
# alir. Bu betik makinedeki kendi oturum transkriptlerini toparlar - yetim
# tarayicinin 72 saatlik penceresine hic girmemis eski oturumlari.
#
# Neden ayri bir betik: yetim tarayici oturum basina en fazla 3 is baslatir.
# Birikmis yigin bu hizla drenaj olmaz; tek seferlik ve KONTROLLU bir gecis
# gerekiyor.
#
# Varsayilan KURU CALISMA - hicbir sey yazilmaz, yalniz liste basilir.
# Gercekten islemek icin -Uygula ver.
#
# Butce: her dosya bir 'claude -p' cagrisi harcar. Gunluk tavan flush.ps1
# icinde uygulanir; tavan dolunca bu betik durur (kalan isler kuyruga alinir).

# -Gun varsayilani 3: kullanici "gecmis oturumlar: bugunden itibaren" dedi.
# Havuz olculdu - 30 gunde 2.875 dosya / 13,5 GB. Derin gecmis bilincli olarak
# ISTENMIYOR; bu betik yalniz penceredeen dusmus yakin yigini toplar.
param(
    # TASINABILIRLIK (2026-09-10): vault yolu artik GOMULU DEGIL.
    # Oncelik: -Vault parametresi > BEYIN_VAULT ortam degiskeni > betigin kendi
    # konumundan turetme (<vault>\motor\scripts\<bu betik>.ps1 oldugu icin
    # iki seviye yukarisi vault'tur). Boylece motor baska bir makinede, baska
    # bir kullanici adiyla ve baska bir vault konumunda TEK SATIR DEGISMEDEN
    # calisir. Gomulu yol ayni zamanda depoya kisisel veri sizdiriyordu.
    [string]$Vault = $(if ($env:BEYIN_VAULT) { $env:BEYIN_VAULT } else { Split-Path (Split-Path $PSScriptRoot -Parent) -Parent }),
    [int]$Gun = 3,
    [int]$EnFazla = 25,
    [switch]$Uygula
)

$ErrorActionPreference = 'SilentlyContinue'
# VAULT KAPISI (2026-09-17 bagimsiz denetimi - A1). $Vault bu betikte ILK
# bildirilen parametredir, yani 0. KONUM ona aittir: 'beyin <komut> ZZZ' gibi
# ciplak birakilan bir konumsal deger buraya baglaniyordu. lib.ps1 o yoldan
# yuklenemiyor, $ErrorActionPreference = 'SilentlyContinue' hatayi yutuyor ve
# betik HICBIR SEY YAPMADAN 'basariyla' cikiyordu (olculdu). Ayni kapi
# niyet/al/ayar/guncelle dahil 14 komutta zaten vardi; burada eksikti.
$vaultOk = $false
try { $vaultOk = [bool]($Vault -and (Test-Path -LiteralPath $Vault -PathType Container) -and (Test-Path -LiteralPath (Join-Path $Vault 'motor\hooks\lib.ps1') -PathType Leaf)) } catch { }
if (-not $vaultOk) { Write-Output "HATA: vault degil (motor\hooks\lib.ps1 yok): '$Vault'  - konumsal arguman -Vault'a baglanir; gun penceresi icin -Gun <n> kullan"; exit 2 }
. (Join-Path $Vault 'motor\hooks\lib.ps1')
$p = Get-BeyinPaths -Vault $Vault

$cut    = (Get-Date).AddDays(-$Gun)
$aktifS = (Get-Date).AddMinutes(-5)

# TEK KAYNAK + ORTAM DEGISKENI DESTEGI: bkz. lib.ps1 Get-BeyinTranscriptRoots
# (CLAUDE_CONFIG_DIR / CODEX_HOME). Bu liste eskiden burada ve
# session-start.ps1'de AYRI AYRI yaziliydi; birindeki duzeltme digerine
# gecmiyordu.
$roots = @(Get-BeyinTranscriptRoots)

"Vault     : $Vault"
"Pencere   : son $Gun gun"
"Mod       : $(if ($Uygula) { 'UYGULA (yazacak)' } else { 'kuru calisma (yazmaz)' })"
''

$adaylar = New-Object System.Collections.Generic.List[object]
$atlandi = @{}
function Say([string]$k) { if (-not $atlandi.ContainsKey($k)) { $atlandi[$k] = 0 }; $atlandi[$k]++ }

# ============================================================================
# TARAMA - ucuzdan pahaliya siralanmis.
#
# Transkripti TAM OKUMUYORUZ. Ilk surumde her aday icin Read-BeyinTranscript
# cagriliyordu; 30 gunluk havuz 13,5 GB oldugu icin tarama bitmedi. Zaten
# gereksizdi: flush.ps1 "cok kisa" ve "bicim taninmadi" durumlarini kendisi,
# MODEL CAGIRMADAN once eliyor - bosa butce harcanmiyor.
#
# Sira: dosya adi -> watermark -> karantina -> cwd (ilk 40 satir) -> zaman
# damgasi (son 300 satir). Her adim bir sonrakinin girdisini kucultuyor.
# ============================================================================
$onAday = New-Object System.Collections.Generic.List[object]
foreach ($root in $roots) {
    if (-not (Test-Path -LiteralPath $root.Path)) { continue }
    foreach ($f in @(Get-ChildItem -LiteralPath $root.Path -Recurse -Filter $root.Filter -File -ErrorAction SilentlyContinue |
                     Where-Object { $_.LastWriteTime -gt $cut -and $_.Length -gt 8192 })) {

        if ($f.LastWriteTime -gt $aktifS) { Say 'hala-aktif'; continue }
        if ($f.Name -like 'agent-*')      { Say 'alt-ajan'; continue }
        # 'Isaret var mi' KAPISI KALDIRILDI (2026-09-10, bagimsiz denetim).
        #
        # Burada 'Get-BeyinWatermark > 0 ise islenmis' yaziyordu ve bu, KURTARMA
        # ARACININ KURTARMASI GEREKEN TAM DURUMU disliyordu:
        #
        #   PreCompact bir kez ozetler (lines = 120), konusma devam eder, oturum
        #   duzgun kapanmaz -> 120. satirdan sonrasi hic islenmemistir.
        #   Bu kapi "isaret var" deyip dosyayi atliyordu. Yani motorun kayip
        #   kapilarina karsi yazilmis kurtarma yolu, kayiplarin en yaygin
        #   turune KAPALIYDI.
        #
        # Karar zaten bir satir asagida, Test-BeyinShouldRetry'de dogru
        # veriliyor: lines>0 olsa bile dosya isaretten sonra BUYUDUYSE
        # Retry=$true doner, buyumediyse 'islenmis' der ve sayac yine artar.
        # Iki kapi ayni soruyu soruyordu; yanlis cevap vereni kaldirildi.
        # Kuyrukta bekleyen is (Codex session-end artik yalniz kuyruga yazar): bir
        # sonraki SessionStart drenaj eder; burada aday sayilmasi yanlis alarm olur.
        if (Test-Path -LiteralPath (Join-Path $p.Queue ((Get-BeyinKey -Text $f.FullName) + '.json'))) { Say 'kuyrukta'; continue }

        $rt = Test-BeyinShouldRetry -Paths $p -TranscriptPath $f.FullName -CurrentSize $f.Length
        if (-not $rt.Retry) { Say $rt.Reason; continue }

        # MAKINE THREAD ELEMESI KESMEDEN ONCE (2026-09-16).
        # NEDEN: eleme (ilk 40 satirlik okuma, dosya basina ~ms) asagidaki
        # EnFazla*3 kesmesinden SONRA yapiliyordu. Olculdu (son 3 gun, 8 KB
        # ustu 80 Codex rollout'u): 72'si makine thread'i (subagent 37,
        # guardian_review 34, onboarding 1); isaret tasimadiklari icin
        # Test-BeyinShouldRetry onlari elemez ve 75'lik kesmeyi bunlar
        # dolduruyordu - gercek oturumlar kesmenin disinda kaliyor, 'Toplam
        # aday' / 'Pencere disi' (doktor bunlara bakar) eksik cikiyordu. Eleme
        # artik burada; kesme yalniz gercek adaylara uygulanir. Sonuc ikinci
        # donguye tasinir, dosya ikinci kez okunmaz.
        $info = Get-BeyinProjectFromTranscript -Path $f.FullName -Vault $Vault
        if ($info.Excluded) { Say $info.ExcludeReason; continue }

        $onAday.Add([pscustomobject]@{ F = $f; Agent = $root.Agent; Info = $info })
    }
}

# Pahali adim (zaman damgasi: son 300 satir) yalniz en yeni EnFazla*3 dosya
# icin. Daha eskisi zaten bu kosuda islenmeyecek; onlar icin zaman cozmek bos is.
#
# AMA SAYIM KIRPMADAN ONCE YAPILIR (2026-09-17, bagimsiz denetim - F8).
# Onceki surum 'Toplam aday' ve 'Pencere disi' satirlarini KIRPILMIS listeden
# hesapliyordu. Olculdu (ayni havuz): -EnFazla 25 -> 'Toplam aday 8 / Pencere
# disi 4', -EnFazla 1 -> 'Toplam aday 3 / Pencere disi 0'. Doktor 'Pencere disi'
# satirina bakar; havuz EnFazla*3'u astiginda birikmis yigin EKSIK raporlaniyor,
# hatta 0 gorunuyordu. Kirpma artik YALNIZ islenecek listeye uygulanir ve
# kirpildigi raporda acikca yazilir.
$onAdayTum      = @($onAday | Sort-Object { $_.F.LastWriteTime } -Descending)
$toplamAdaySay  = $onAdayTum.Count
$pencereSinir   = (Get-Date).AddHours(-72)
$pencereDisiSay = @($onAdayTum | Where-Object { $_.F.LastWriteTime -lt $pencereSinir }).Count
$kirpmaTavan    = $EnFazla * 3
$onAday = @($onAdayTum | Select-Object -First $kirpmaTavan)
$kirpildi = ($toplamAdaySay -gt $onAday.Count)

foreach ($a in $onAday) {
    $f = $a.F
    $info = $a.Info   # eleme + proje turetme ilk dongude yapildi

    $zaman = Get-BeyinTranscriptTime -Path $f.FullName
    $adaylar.Add([pscustomobject]@{
        Tarih = $zaman.Date
        Saat  = $zaman.Stamp
        Ajan  = $a.Agent
        Proje = $(if ($info.ProjectLeaf) { $info.ProjectLeaf } else { '-' })
        KB    = [math]::Round($f.Length / 1KB)
        Yol   = $f.FullName
        Cwd   = $info.Cwd
        Mtime = $f.LastWriteTime
    })
}

# En eskiden yeniye: kronolojik sira gunluk logda dogru okunsun.
$sirali = @($adaylar | Sort-Object Tarih, Saat)
$secili = @($sirali | Select-Object -First $EnFazla)

# BU IKI SAYI KIRPMADAN ONCEKI GERCEK SAYILARDIR (F8). Doktor bunlari okur
# (^Toplam aday : N / ^Pencere disi : N); satir bicimi bilerek degismedi.
"Toplam aday : $toplamAdaySay"
# Yetim tarayicinin penceresi 72 saat: ondan ESKI adaylar gercekten kacmis olanlardir.
# Daha yeni olanlari tarayici zaten toplar; doktor yalniz bu sayiya bakar.
"Pencere disi : $pencereDisiSay (72 saatten eski; yetim tarayici artik gormez)"
if ($kirpildi) { "  (kirpildi: $toplamAdaySay adayin en yeni $($onAday.Count) tanesi degerlendirildi)" }
"Bu kosuda   : $($secili.Count) (EnFazla=$EnFazla)"
if ($atlandi.Count -gt 0) {
    "Atlananlar  : " + (($atlandi.GetEnumerator() | Sort-Object Name | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ', ')
}
''

if ($secili.Count -eq 0) { 'Islenecek dosya yok.'; exit 0 }

$secili | Format-Table -AutoSize Tarih, Saat, Ajan, Proje, KB, @{ N = 'Dosya'; E = { (Split-Path -Leaf $_.Yol).Substring(0, [Math]::Min(12, (Split-Path -Leaf $_.Yol).Length)) } } | Out-String -Width 200

if (-not $Uygula) {
    ''
    'KURU CALISMA. Gercekten islemek icin:  -Uygula'
    "Tahmini butce: $($secili.Count) 'claude -p' cagrisi."
    exit 0
}

''
'=== ISLENIYOR (sirali - es zamanli degil) ==='
# KUYRUK DURUMU CIKTIDAN DEGIL DISKTEN OKUNUR (2026-09-17, denetim - F7).
# flush FLUSH_HATA_* dondugunde de isi KUYRUGA ALIYOR (flush.ps1: Add-BeyinQueue
# + 'is kuyruga alindi, watermark ilerletilmedi'). Eski ozet blogu bunu hic
# hesaba katmiyordu. Olculdu: flush FLUSH_HATA_istisna dondu, .state/queue'da
# is dosyasi olustu, engine.log 'is kuyruga alindi' yazdi - gecmis-toparla ise
# '0 kuyruga dustu, 0 islenmedi, 1 hata' dedi. Artik her dosya icin kuyruk
# dosyasinin varligi olculur ve ozete AYRI bir sayi olarak yazilir.
$ok = 0; $bos = 0; $hata = 0; $kuyruk = 0; $mesgul = 0
$kuyruktaSay = 0
foreach ($a in $secili) {
    $sonuc = & (Join-Path $p.Scripts 'flush.ps1') `
        -TranscriptPath $a.Yol -Vault $Vault -Reason 'gecmis-toparla' `
        -Agent $a.Ajan -ProjectPath $a.Cwd
    $kod = ([string]($sonuc | Select-Object -First 1)).Trim()
    $kuyruktaMi = $false
    try { $kuyruktaMi = [bool](Test-Path -LiteralPath (Join-Path $p.Queue ((Get-BeyinKey -Text $a.Yol) + '.json'))) } catch { }
    if ($kuyruktaMi) { $kuyruktaSay++ }
    "  {0} {1,-14} {2} -> {3}{4}" -f $a.Tarih, $a.Proje, (Split-Path -Leaf $a.Yol).Substring(0, 8), $kod, $(if ($kuyruktaMi) { '  [kuyrukta]' } else { '' })
    # DURMA KOSULU GERCEK KODLARLA (2026-09-16).
    # NEDEN: eski kosul '*MESGUL*' veya '*BUTCE*' idi. flush.ps1 butce/slot
    # dolunca FLUSH_KUYRUKTA doner ('BUTCE' hicbir Stop-Flush kodunda gecmez)
    # -> dongu durmuyor, kalan her dosya icin claim + on kontrol + kuyruk
    # yazimi yapilip 'hata' sayiliyor ve makbuz sahte TOPLA_HATA yaziyordu.
    # FLUSH_MESGUL ise yalniz O transkriptin baska surecte oldugunu soyler
    # (ornek: canli bir PreCompact) - tum kosuyu kesmek yanlis; atla, devam et.
    # Kodlar: FLUSH_OK, FLUSH_BOS, FLUSH_KUYRUKTA (butce on kontrol / slot yok /
    # butce doldu), FLUSH_MESGUL, FLUSH_HATA_<sebep>.
    if     ($kod -like 'FLUSH_OK*')       { $ok++ }
    elseif ($kod -like 'FLUSH_BOS*')      { $bos++ }
    elseif ($kod -like 'FLUSH_KUYRUKTA*') {
        $kuyruk++
        # Yalniz BU transkript kuyruga girdi (flush kendi kendini kuyruga atar);
        # kalan dosyalar bu kosuda islenMEDI, sonraki kosu ya da yetim tarayici
        # toplar. Eski metin hepsinin kuyruga girdigini soyluyordu (2026-09-17).
        $kalanIslenmeyen = $secili.Count - $ok - $bos - $mesgul - $kuyruk - $hata
        "  -> durduruldu: butce/slot dolu ($kod); bu is kuyrukta, kalan $kalanIslenmeyen dosya bu kosuda islenmedi (sonraki kosu ya da yetim tarayici toplar)"
        break
    }
    elseif ($kod -like 'FLUSH_MESGUL*')   { $mesgul++ }
    else                                  { $hata++ }
}
# Makbuz notu GERCEK sonuc ozeti: yazilan/bos/mesgul/kuyruk/islenmeyen/hata.
# TOPLA_HATA yalniz gercek hata icin; butce/slot dolusu TOPLA_KUYRUK (makbuz
# okuyucusu 'KUYRUK' desenini erteleme sayar, hata degil).
# 'kuyrukta bekleyen' AYRI bir olcudur (F7): flush hem FLUSH_KUYRUKTA hem
# FLUSH_MESGUL hem FLUSH_HATA_* yollarinda isi kuyruga atabilir; bu sayi
# .state/queue'dan OKUNUR, cikis kodundan cikarilmaz.
$kalan = $secili.Count - ($ok + $bos + $hata + $kuyruk + $mesgul)
$ozet = "$ok yazildi, $bos bos, $mesgul mesgul-atlandi, $kuyruk butce/slot-kuyrugu, $kalan islenmedi, $hata hata; kuyrukta bekleyen $kuyruktaSay is (aday $toplamAdaySay)"
''
"Sonuc: $ozet"
Write-BeyinLog -Vault $Vault -Message "gecmis-toparla: $ozet"
Write-BeyinMakbuz -Paths $p -Script 'gecmis-toparla' `
    -Outcome $(if ($hata -gt 0) { 'TOPLA_HATA' } elseif ($kuyruk -gt 0) { 'TOPLA_KUYRUK' } else { 'TOPLA_OK' }) `
    -Note $ozet
"Kontrol:  git -C `"$Vault`" diff --numstat -- 85-daylogs"
