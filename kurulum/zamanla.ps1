# zamanla.ps1 - Motorun gece gorevlerini Windows Gorev Zamanlayici'ya kaydeder.
#
# NEDEN: motor yalniz bir oturum acilinca calisiyordu; derleme, gomme, yedek
# ve toplama hep "bir sonraki oturuma" kaliyordu. Artik her gece kosar.
# PC gece uyuyorsa (kullanici karari) gorev UYANDIRMAZ; kacirilan kosu
# makine acilinca ilk firsatta yapilir (StartWhenAvailable).
#
# Gorevler (\Beyin\):
#   derle          03:00 her gun     kavram notu derle (model gerekir)
#   gom            03:10 her gun     vektor gomme (Ollama varsa)
#   bagla          03:15 her gun     capraz baglanti bolumlerini tazele (gom'un ciktisini kullanir)
#   topla-uygula   03:20 her gun     3 gunluk yetim oturumlari isle (model gerekir)
#   yedek          03:40 Pazar       tam vault yedegi (brain-cli; brain-cli cozulmuyorsa KAYDEDILMEZ)
#   copcu          04:00 her gun     disk copcusu RAPORU (silmez; silme kullanici karari)
#   bahcivan       04:30 Pazar       kavram/skill/betik kullanim raporu
#   denetle        05:00 Pazar       kavram notu semantik denetimi (hizli yol; model cagirmaz)
#
# Hepsi: powershell -File ~\.beyin\beyin.ps1 zamanli <komut>  (zamanli-kos.ps1 sarar:
# [zamanlayici] logu, kimlik on kontrolu, makbuz src=zamanlayici).
#
# ONKOSUL: gorevler KURULU dagiticiyi cagirir (~\.beyin\beyin.ps1), depodaki
# kurulum\beyin.ps1'i degil. Depoya yeni bir komut eklendiyse once 'beyin kur'.
# Bu betik kayittan ONCE her rotanin kurulu dagiticida gercekten var oldugunu
# dogrular ve tanimayan komutun gorevini kaydetmez (sesli atlar).
#
# Idempotent: tekrar calistirmak gorevleri gunceller. -Kaldir hepsini siler.
# ~\.codex\hooks.json'a DOKUNMAZ.
#
# Kullanim:
#   powershell -NoProfile -ExecutionPolicy Bypass -File kurulum\zamanla.ps1
#   ... -KuruCalisma   ne yapacagini yazar
#   ... -Liste         kayitli gorevler + son kosu sonucu
#   ... -Kaldir        gorevleri siler

param(
    [string]$Vault = $(if ($env:BEYIN_VAULT) { $env:BEYIN_VAULT } else { Split-Path $PSScriptRoot -Parent }),
    [switch]$Kaldir,
    [switch]$KuruCalisma,
    [switch]$Liste,

    # Vault sahiplik kapisini as (vault tasima gibi bilincli durumlar icin).
    [switch]$Zorla
)

$ErrorActionPreference = 'Stop'
$YOL = '\Beyin\'
$dispatcher = Join-Path $env:USERPROFILE '.beyin\beyin.ps1'

# ---------------------------------------------------------------------------
# VAULT SAHIPLIK KAPISI
# ---------------------------------------------------------------------------
# Zamanlanmis gorevler MAKINE GENELINDE '\Beyin\' altinda duruyor ve bu betik
# hangi vault'tan kosulursa kosulsun ONLARI degistiriyor. Olculdu (2026-09-17):
# kum havuzu testleri sirasinda sahte bir ev dizininden kosan bir zamanla.ps1
# brain-cli'yi bulamadi ve GERCEK makinenin 'beyin-yedek' gorevini KALDIRDI.
# Iki kez yasandi; kullanici bunu ancak doktorun 'zamanlanmis gorevler'
# satirindan fark edebilir.
#
# Neden yanlis: kaydedilen gorevlerin eylemi '~\.beyin\beyin.ps1' dagiticisi,
# o da vault'u vault.txt'ten cozer. Yani gorevler HER ZAMAN vault.txt'teki
# vault icin calisir; baska bir vault icin gorev kaydetmek anlamsiz, mevcut
# gorevleri bozmak ise gercek zarar.
$kayitliVault = ''
try {
    $vtxt = Join-Path $env:USERPROFILE '.beyin\vault.txt'
    if (Test-Path -LiteralPath $vtxt -PathType Leaf) {
        $kayitliVault = (Get-Content -LiteralPath $vtxt -Raw -Encoding UTF8).Trim()
    }
} catch { }
if ($kayitliVault -and -not $Zorla) {
    $a = $Vault.TrimEnd('\', '/')
    $b = $kayitliVault.TrimEnd('\', '/')
    if (-not [string]::Equals($a, $b, [StringComparison]::OrdinalIgnoreCase)) {
        Write-Host ''
        Write-Host 'ZAMANLAYICI: DURDU - bu vault makinenin kayitli vault''u DEGIL.' -ForegroundColor Red
        Write-Host ''
        Write-Host "  istenen vault : $Vault"
        Write-Host "  kayitli vault : $kayitliVault   (~\.beyin\vault.txt)"
        Write-Host ''
        Write-Host '  Gece gorevleri makine genelinde \Beyin\ altinda tutulur ve eylemleri'
        Write-Host '  ~\.beyin\beyin.ps1 dagiticisidir; o da vault''u vault.txt''ten cozer.'
        Write-Host '  Yani gorevler HER ZAMAN kayitli vault icin calisir. Baska bir vault'
        Write-Host '  icin kaydetmek anlamsiz olurdu, mevcut gorevleri bozmak ise gercek'
        Write-Host '  zarardir - bu yuzden duruldu, hicbir gorev degistirilmedi.'
        Write-Host ''
        Write-Host '  Vault''u tasidiysan once kurulumu yenile:  beyin kur'
        Write-Host '  Yine de devam etmek icin:                 zamanla.ps1 -Vault "..." -Zorla'
        exit 2
    }
}

$GOREVLER = @(
    @{ Ad = 'derle';        Saat = '03:00'; Gun = '';       Aciklama = 'Gunluk loglardan kavram notu derle (model gerekir)' },
    @{ Ad = 'gom';          Saat = '03:10'; Gun = '';       Aciklama = 'Kavram notlarini bge-m3 ile gom (Ollama varsa)' },
    # NEDEN 03:15 VE NEDEN HER GUN: bagla, gom'un o gece yazdigi vektor indeksini
    # okur - bu yuzden gom'dan (03:10) SONRA, topla'dan (03:20) ONCE. Gorev adi
    # 'beyin-bagla' ama KOMUT 'bagla-uygula': kuru kosu gece hicbir ise yaramaz,
    # bolumleri gercekten tazeleyen yol budur. Yazma tarafi idempotenttir - hicbir
    # sey degismediyse tek bir not bile yazilmaz, 'updated' damgalari tazelenmez.
    # SIRALAMA GARANTISI YOKTUR (bkz. denetle notu): gom o gece kosmadiysa bagla
    # dunku indeksle calisir; bu bilincli ve zararsizdir - eksik not yalniz o gece
    # baglanti almaz, ertesi gece alir.
    @{ Ad = 'bagla';        Saat = '03:15'; Gun = '';       Aciklama = 'Kavram notlarindaki "## Ilgili notlar" capraz baglantilarini tazele'; Komut = 'bagla-uygula' },
    @{ Ad = 'topla-uygula'; Saat = '03:20'; Gun = '';       Aciklama = 'Son 3 gunun yetim oturumlarini isle (model gerekir)'; Arg = '3' },
    @{ Ad = 'yedek';        Saat = '03:40'; Gun = 'Sunday'; Aciklama = 'Tam vault yedegi' },
    @{ Ad = 'copcu';        Saat = '04:00'; Gun = '';       Aciklama = 'Disk copcusu raporu (silmez)' },
    @{ Ad = 'bahcivan';     Saat = '04:30'; Gun = 'Sunday'; Aciklama = 'Kavram/skill/betik kullanim raporu' },
    # NEDEN HAFTALIK (2.3): gorev -Derin VERMEZ, yani denetle'nin hizli yolu kosar;
    # o yol model cagirmaz (diskteki bge-m3 vektorleri uzerinde calisir) ve gece
    # butcesinden hic harcamaz. Ama tum kavram ciftlerini gezer ve notlar gun icinde
    # yalniz birkac tane artar; gunluk kosmasi bos is olurdu. Saat bahcivandan
    # (04:30) SONRA secildi ki iki RAPOR yan yana okunsun: bahcivan hangi kavram
    # olu aday der, denetle hangileri yakin-ikiz/celiskili der.
    # DIKKAT - SIRALAMA GARANTISI YOKTUR: kayitli bahcivan gorevi Arg TASIMAZ,
    # yani 'beyin zamanli bahcivan' yani KURU rapor yolu kosar; hicbir sey
    # arsivlenmez ve hicbir aday isaretlenmez. Olu adaylari gercekten tasiyan
    # 'bahcivan-uygula' ZAMANLANMIS BIR GOREV DEGILDIR, elle kosulur.
    # (Hakemlik isteyen kullanici elle kosar: beyin denetle -Derin, 1 butce.)
    @{ Ad = 'denetle';      Saat = '05:00'; Gun = 'Sunday'; Aciklama = 'Kavram notlari semantik denetimi (yakin-ikiz / celiski)' }
)

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

function Gorev-Adi([string]$Ad) { return "beyin-$Ad" }
$inv = [Globalization.CultureInfo]::InvariantCulture

# ============================================================================
# DAGITICI SENKRONU  (2026-09-17 denetimi)
# ----------------------------------------------------------------------------
# Bu betik gorevleri ~\.beyin\beyin.ps1'e - kur.ps1'in kurdugu KOPYAYA - kaydeder,
# depodaki kurulum\beyin.ps1'e degil. Depoya yeni bir komut eklenip 'beyin kur'
# kosulmadigi surece kopyada O ROTA YOKTUR ve kaydedilen gorev her gece var
# olmayan bir komutu cagirir. OLCULDU: 'bagla' rotasi depoya girdi, kurulu
# kopyada yoktu; beyin-bagla 03:15'te her gece bos donerdi ve bunu soyleyen tek
# bir kontrol bile yoktu. Onkosul bir devir notunda yazmak yetmez, CALISTIRILABILIR
# olmali - bu yuzden kayittan once rota gercekten dogrulanir.
# Dagitici okunamazsa KARAR VERILMEZ (engelleme yok): bu bir senkron kontrolu,
# ikinci bir izin kapisi degil.
# ============================================================================
$dagiticiMetin = ''
try { $dagiticiMetin = [IO.File]::ReadAllText($dispatcher) } catch { }
function Test-DagiticiRota([string]$Komut) {
    if (-not $dagiticiMetin) { return $true }
    # Dagitici switch'i komutlari TEK TIRNAKLI degismez olarak yazar:
    #   'bagla-uygula'   ya da   { $_ -in @('bagla', 'link') }
    # Kultur-bagimsiz eslesme: tr-TR'de ASCII olmayan bir katlama olmasin.
    $rx = "'" + [regex]::Escape($Komut) + "'"
    return [bool][regex]::IsMatch($dagiticiMetin, $rx, [System.Text.RegularExpressions.RegexOptions]'IgnoreCase,CultureInvariant')
}

if ($Liste) {
    $var = @(Get-ScheduledTask -TaskPath $YOL -ErrorAction SilentlyContinue)
    if ($var.Count -eq 0) { "Kayitli beyin gorevi yok ($YOL). Kurmak icin: kurulum\zamanla.ps1"; exit 0 }
    "ZAMANLANMIS GOREVLER ($YOL)"
    foreach ($t in $var) {
        # NEDEN: LastTaskResult UInt32'dir; 0x800710E0 / 0xC000013A gibi HATA kodlari [int]'e sigmaz ve
        # $ErrorActionPreference=Stop ile -Liste tam bir gorev basarisizken ilk satirda cokuyordu (olculdu:
        # 'Value was either too large or too small for an Int32'). Devre disi gorevde NextRunTime $null ->
        # .ToString() ayni sekilde. Her gorev kendi try'inda: biri bozuksa digerleri yine listelenir.
        try {
            $i = Get-ScheduledTaskInfo -TaskName $t.TaskName -TaskPath $YOL -ErrorAction SilentlyContinue
            $sonuc = if ($null -ne $i) { '0x{0:X}' -f [uint32]$i.LastTaskResult } else { '?' }
            $sonKosu = if ($i -and $i.LastRunTime -gt [datetime]'2000-01-01') { $i.LastRunTime.ToString('yyyy-MM-dd HH:mm', $inv) } else { '-' }
            $sonraki = if ($i -and $i.NextRunTime -and $i.NextRunTime -gt [datetime]'2000-01-01') { $i.NextRunTime.ToString('yyyy-MM-dd HH:mm', $inv) } else { '-' }
            "  {0,-22} {1,-9} son: {2,-19} sonuc: {3,-10} sonraki: {4}" -f $t.TaskName, $t.State, $sonKosu, $sonuc, $sonraki
        } catch { "  {0,-22} {1,-9} (bilgi alinamadi: {2})" -f $t.TaskName, $t.State, $_.Exception.Message }
    }
    '  (0x0 = basarili, 0x41303 = henuz kosmadi, 0x41301 = su an kosuyor; 0x1..0xFF = betik hatasi, 0x3 = kimlik yok'
    '   -> engine.log [zamanlayici] satirlari; 0x800710E0 = oturum acik degildi, 0xC000013A = 3 saatlik sinirda olduruldu)'
    exit 0
}

if ($Kaldir) {
    # YALNIZ BU KURULUMUN GOREVLERI (2026-09-18): \Beyin\ makine genelindedir.
    $hepsiG = @(Get-ScheduledTask -TaskPath $YOL -ErrorAction SilentlyContinue)
    $var    = @($hepsiG | Where-Object { Test-GorevBizim -Gorev $_ -Dagitici $dispatcher })
    $yabanciG = @($hepsiG).Count - @($var).Count
    if ($yabanciG -gt 0) { "  ($yabanciG gorev baska bir beyin kurulumuna ait - DOKUNULMADI)" }
    foreach ($t in $var) {
        if ($KuruCalisma) { "  kaldirilacak: $($t.TaskName)"; continue }
        Unregister-ScheduledTask -TaskName $t.TaskName -TaskPath $YOL -Confirm:$false
        "  kaldirildi: $($t.TaskName)"
    }
    "$($var.Count) gorev$(if ($KuruCalisma) { ' kaldirilacakti (kuru)' } else { ' kaldirildi' })."
    exit 0
}

if (-not (Test-Path -LiteralPath $dispatcher)) {
    "HATA: dagitici yok: $dispatcher  -> once kurulum\kur.ps1 calistir."
    exit 1
}
if (-not (Test-DagiticiRota 'zamanli')) {
    # 'zamanli' sarmalayicisi yoksa TEK BIR gorev bile kosamaz: hepsi onun uzerinden gider.
    "HATA: kurulu dagitici 'zamanli' rotasini tanimiyor: $dispatcher"
    "      Kurulu kopya depodaki kurulum\beyin.ps1'in gerisinde. Once: beyin kur  (ya da kurulum\kur.ps1)"
    exit 1
}

"ZAMANLAYICI  ($YOL, kullanici: $env:USERNAME, dagitici: $dispatcher)$(if ($KuruCalisma) { '  [KURU CALISMA]' })"
$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited
$ayar = New-ScheduledTaskSettingsSet -StartWhenAvailable -MultipleInstances IgnoreNew `
        -ExecutionTimeLimit (New-TimeSpan -Hours 3) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
        -RunOnlyIfIdle:$false -Hidden:$false
$n = 0
$eksikRota = 0
$basarisiz = New-Object System.Collections.Generic.List[string]
foreach ($g in $GOREVLER) {
    $ad = Gorev-Adi $g.Ad
    # 'yedek' ARTIK HER ZAMAN KAYDEDILIR (2026-09-18).
    # Eskiden brain-cli cozulemezse bu gorev atlanir, hatta devre disi
    # birakilirdi - cunku 'beyin yedek' o araca bagliydi ve arac bu depoda
    # gelmiyordu. Motorun kendi yerli yedegi (motor\scripts\yedek.ps1) oldugu
    # icin o kosul kalkti: brain-cli varsa dagitici onu tercih eder, yoksa
    # yerli yedek kosar. Iki durumda da gorev anlamlidir.
    # GOREV ADI ile DAGITICI KOMUTU ayri olabilir: 'beyin-bagla' gorevi
    # 'bagla-uygula' komutunu kosar (kuru kosu gece bir ise yaramaz). Komut
    # verilmemisse eski davranis aynen gecerli: komut = gorev adi.
    $rota = $(if ($g.Komut) { [string]$g.Komut } else { [string]$g.Ad })
    if (-not (Test-DagiticiRota $rota)) {
        # Kurulu dagitici bu komutu tanimiyor (bkz. DAGITICI SENKRONU). Gorevi
        # kaydetmek onu her gece bos kosturmak olurdu; 'yedek' ile AYNI desen:
        # sesli atla ve onceki kurulumdan kalan calisamaz gorevi kaldir.
        "  {0,-22} ATLANDI: kurulu dagitici '{1}' komutunu tanimiyor -> once: beyin kur" -f $ad, $rota
        $eksikRota++
        if (-not $KuruCalisma) {
            try {
                if (Get-ScheduledTask -TaskName $ad -TaskPath $YOL -ErrorAction SilentlyContinue) {
                    Unregister-ScheduledTask -TaskName $ad -TaskPath $YOL -Confirm:$false
                    "      (onceki $ad gorevi kaldirildi: dagitici komutu tanimiyor, her gece bos koserdi)"
                }
            } catch { }
        }
        continue
    }
    $komut = $rota + $(if ($g.Arg) { ' ' + $g.Arg } else { '' })
    $arg = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$dispatcher`" zamanli $komut"
    $saat = [datetime]::ParseExact($g.Saat, 'HH:mm', [Globalization.CultureInfo]::InvariantCulture)
    $tetik = if ($g.Gun) { New-ScheduledTaskTrigger -Weekly -DaysOfWeek $g.Gun -At $saat } else { New-ScheduledTaskTrigger -Daily -At $saat }
    $eylem = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $arg
    "  {0,-22} {1} {2,-7} {3}" -f $ad, $g.Saat, $(if ($g.Gun) { $g.Gun } else { 'her gun' }), $g.Aciklama
    if ($KuruCalisma) { "      powershell.exe $arg"; $n++; continue }
    # KAYIT DOGRULANIR (olculdu 2026-09-17): eskiden sonuc hic kontrol
    # edilmiyor, `$n++` kosulsuz calisiyordu. Bir kayit basarisiz olsa bile
    # (hemen once Unregister edilmis bir gorevle yaris, yetki, ad cakismasi)
    # betik "8 gorev kaydedildi" diyordu; gercekte 7 kaydedilmisti ve eksik
    # gece gorevi hic kosmuyordu - kullaniciya hicbir sey soylenmeden.
    try {
        Register-ScheduledTask -TaskName $ad -TaskPath $YOL -Action $eylem -Trigger $tetik -Principal $principal -Settings $ayar `
            -Description "Ikinci beyin: $($g.Aciklama). Kaynak: $Vault" -Force -ErrorAction Stop | Out-Null
        if (Get-ScheduledTask -TaskName $ad -TaskPath $YOL -ErrorAction SilentlyContinue) {
            $n++
        } else {
            $basarisiz.Add("$ad (kayit sonrasi bulunamadi)")
        }
    } catch {
        $basarisiz.Add("$ad ($($_.Exception.Message))")
    }
}
''
if ($eksikRota -gt 0) {
    "$eksikRota gorev ATLANDI: kurulu dagitici ($dispatcher) o komutlari tanimiyor."
    "Kurulu kopya depodaki kurulum\beyin.ps1'in gerisinde. Cozum:  beyin kur  (ya da kurulum\kur.ps1), sonra bu betigi tekrar calistir."
    ''
}
"$n gorev $(if ($KuruCalisma) { 'kaydedilecekti (kuru calisma)' } else { 'kaydedildi/guncellendi' }). Durum: kurulum\zamanla.ps1 -Liste  |  beyin doktor -> 'zamanlanmis gorevler'"
'PC gece uyuyorsa gorevler uyandirmaz; makine acilinca ilk firsatta kosar (StartWhenAvailable).'
if ($basarisiz.Count -gt 0) {
    ''
    "$($basarisiz.Count) GOREV KAYDEDILEMEDI:"
    foreach ($b in $basarisiz) { "  $b" }
    'Bu gorevler HIC KOSMAYACAK. Tekrar dene; surerse Gorev Zamanlayici''yi (taskschd.msc) ac ve \Beyin\ altina bak.'
    exit 1
}
exit 0
