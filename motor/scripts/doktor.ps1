# doktor.ps1 - Beynin saglik kontrolu. Salt-okunur tani; hicbir sey duzeltmez.
#
#   -Derin : canli 'claude -p' duman testi + brain-cli sema/denetim kontrolu
#
# Bu betik bir denetimde "her sey OK derken motor veri kaybediyor" diye
# elestirildi. Eklenen kontroller tam olarak o kor noktalari kapatiyor:
# butunluk (yazildi denen blok gercekten dosyada mi), encoding tuzaklari,
# derleme basarisizligi, kuyruk derinligi, sema uyumu.

param(
    # TASINABILIRLIK (2026-09-10): vault yolu artik GOMULU DEGIL.
    # Oncelik: -Vault parametresi > BEYIN_VAULT ortam degiskeni > betigin kendi
    # konumundan turetme (<vault>\motor\scripts\<bu betik>.ps1 oldugu icin
    # iki seviye yukarisi vault'tur). Boylece motor baska bir makinede, baska
    # bir kullanici adiyla ve baska bir vault konumunda TEK SATIR DEGISMEDEN
    # calisir. Gomulu yol ayni zamanda depoya kisisel veri sizdiriyordu.
    [string]$Vault = $(if ($env:BEYIN_VAULT) { $env:BEYIN_VAULT } else { Split-Path (Split-Path $PSScriptRoot -Parent) -Parent }),
    [switch]$Derin,
    # -Ozet: "beynim ne durumda?" sorusunun tek komutluk cevabi. Ayni
    # kontrollerin hepsi kosar (maliyet ayni, model cagrisi yok) ama cikti
    # 51 satirlik tablo yerine 8-10 satirlik durum olur: tani, butce, kuyruk,
    # kuratorlu gecikme, son derleme ve proje basina devam noktalari.
    [switch]$Ozet
)

$ErrorActionPreference = 'SilentlyContinue'

# ----------------------------------------------------------------------------
# VAULT DOGRULAMASI - HER SEYDEN ONCE (2026-09-10, bagimsiz denetim)
#
# Asagidaki dot-source $ErrorActionPreference = 'SilentlyContinue' altinda
# calisiyor. Vault yolu yanlissa lib.ps1 yuklenmez, hicbir yardimci fonksiyon
# tanimli olmaz ve betik CALISMAYA DEVAM EDER: her Test-Path $false doner,
# her sayim 0 cikar ve doktor UYDURMA AMA INANDIRICI bir saglik raporu basar.
#
# Bu, hatanin en kotu turudur: sessiz degil, YANLIS GUVEN veren. Kullanici
# "beynim iyi" der, oysa doktor bos bir klasore bakmaktadir. Tasinabilirlik
# calismasi vault'u tasinabilir yaptigi icin yanlis yol ihtimali de artti.
#
# Bu yuzden burada SERT DURULUR.
# ----------------------------------------------------------------------------
# Join-Path DEGIL: var olmayan bir surucude (X:\...) Join-Path
# SilentlyContinue altinda BOS dizge dondurur ve hata mesaji "Motor var mi: ()"
# gibi anlamsiz cikar. Dizge birlestirme her zaman calisir.
$libYol = ($Vault.TrimEnd('\', '/')) + '\motor\hooks\lib.ps1'
if (-not (Test-Path -LiteralPath $Vault) -or -not (Test-Path -LiteralPath $libYol)) {
    Write-Host ''
    Write-Host 'DOKTOR CALISTIRILAMADI: vault bulunamadi.' -ForegroundColor Red
    Write-Host ''
    Write-Host "  Denenen yol : $Vault"
    Write-Host "  Vault var mi: $(Test-Path -LiteralPath $Vault)"
    Write-Host "  Motor var mi: $(Test-Path -LiteralPath $libYol)   ($libYol)"
    Write-Host ''
    Write-Host '  Yol su sirayla cozulur:' -ForegroundColor Yellow
    Write-Host "    1. -Vault parametresi"
    Write-Host "    2. BEYIN_VAULT ortam degiskeni   -> $(if ($env:BEYIN_VAULT) { $env:BEYIN_VAULT } else { '(ayarli degil)' })"
    Write-Host "    3. betigin konumu (<vault>\motor\scripts)"
    Write-Host ''
    Write-Host '  Kurulum tanisi icin:' -ForegroundColor Yellow
    Write-Host "    powershell -NoProfile -ExecutionPolicy Bypass -File `"$(Join-Path $env:USERPROFILE '.beyin\beyin.ps1')`" nerede"
    Write-Host ''
    exit 2
}
. $libYol
if (-not (Get-Command Get-BeyinPaths -ErrorAction SilentlyContinue)) {
    Write-Host ''
    Write-Host 'DOKTOR CALISTIRILAMADI: motor kutuphanesi yuklenemedi.' -ForegroundColor Red
    Write-Host "  $libYol var ama Get-BeyinPaths tanimlanmadi - dosya bozuk olabilir."
    Write-Host '  Kontrol: powershell -NoProfile -Command "& { . ''' + $libYol + '''; }"'
    Write-Host ''
    exit 2
}
$p = Get-BeyinPaths -Vault $Vault

$rows = New-Object System.Collections.Generic.List[object]
function Add-Row {
    param([string]$Kontrol, [bool]$Ok, [string]$Detay, [string]$Duzeltme = '')
    $rows.Add([pscustomobject]@{
        Kontrol  = $Kontrol
        Durum    = $(if ($Ok) { 'OK' } else { 'SORUN' })
        Detay    = $Detay
        Duzeltme = $Duzeltme
    })
}

# ============================================================================
# ONKOSULLAR
# ============================================================================
$claude = Get-BeyinClaudeExe
$claudeTip = ''
if ($claude) {
    $gc = Get-Command claude -ErrorAction SilentlyContinue
    if ($gc) { $claudeTip = " ($($gc.CommandType))" }
}
# OZETLEYICI TEK AJANA BAGLI (2026-09-10, bagimsiz denetim).
# Motor iki ajanin da oturumunu okur ama OZETLEMEYI yalnizca 'claude -p' yapar.
# Yalniz Codex kurulu bir makinede kancalar ateslenir, transkriptler bulunur,
# isler kuyruga girer - ve kuyruk SONSUZA KADAR buyur. Hicbir gunluk log
# yazilmaz. Eski satir bunu 'kurulumu kontrol et' diye geciyordu; sonucu
# soylemiyordu. Sonuc soylenmezse kullanici kuyrugun neden buyudugunu
# anlamaz.
$kuyrukSay = @(Get-ChildItem -LiteralPath $p.Queue -Filter '*.json' -File -ErrorAction SilentlyContinue).Count
$codexExe = Get-BeyinCodexExe
$arkaUc = Get-BeyinModelBackend
Add-Row 'ozetleyici (claude/codex)' ([bool]$arkaUc) `
    $(if ($arkaUc) { "aktif: $arkaUc" + $(if ($claude -and $codexExe) { ' (yedek: ' + $(if ($arkaUc -eq 'claude') { 'codex' } else { 'claude' }) + ')' } else { ' (YEDEK YOK)' }) + " · claude=$(if ($claude) { 'var' } else { 'yok' }) codex=$(if ($codexExe) { 'var' } else { 'yok' })" }
      else { "HICBIRI YOK - hicbir ozet uretilemez; su an $kuyrukSay is kuyrukta bekliyor" }) `
    'Motor iki ajanin oturumunu okur ve claude -p YA DA codex exec ile ozetler. Ikisi de yoksa kancalar calisir, kuyruk buyur, gunluk log YAZILMAZ. Cozum: Claude Code CLI ya da Codex CLI kur.'

Add-Row 'PowerShell' $true "surum $($PSVersionTable.PSVersion)"

# ============================================================================
# ENCODING TUZAKLARI  (bu makinede sessiz veri bozulmasi kaynagi)
# ============================================================================
# 1) tr-TR kultur tuzagi
$naive = ('API_KEY' -match 'api_key')
$safe  = (Test-BeyinMatch -Text 'API_KEY' -Pattern 'api_key')
Add-Row 'kultur-bagimsiz regex' $safe `
    "kultur=$([System.Globalization.CultureInfo]::CurrentCulture.Name), naif=-match:$naive, motor=$safe" `
    'lib.ps1 icindeki BeyinRxCI tanimini kontrol et; bozuksa sir taramasi yanlis negatif verir'

# 2) $OutputEncoding: temiz bir alt surecte olcuyoruz (kancalarin calistigi bicim)
$encOk = $false; $encDetay = 'olculemedi'
try {
    $tmp = Join-Path $env:TEMP ("beyin-enc-{0}.ps1" -f ([guid]::NewGuid().ToString('N')))
    $probe = '. "' + (Join-Path $Vault 'motor\hooks\lib.ps1') + '"' + [Environment]::NewLine + '$OutputEncoding.WebName'
    [System.IO.File]::WriteAllText($tmp, $probe, (New-Object System.Text.UTF8Encoding($true)))
    $w = (& powershell -NoProfile -ExecutionPolicy Bypass -File $tmp 2>$null | Out-String).Trim()
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    $encOk = ($w -eq 'utf-8')
    $encDetay = "alt surecte OutputEncoding=$w (utf-8 olmali)"
} catch { $encDetay = "hata: $($_.Exception.Message)" }
Add-Row 'pipe encoding' $encOk $encDetay `
    'lib.ps1 basindaki $OutputEncoding atamasi eksik; Turkce karakterler claude -p''ye ? olarak gider'

# 3) .ps1 dosyalari BOM'lu mu (PS 5.1 BOM'suz dosyayi ANSI okur)
$noBom = New-Object System.Collections.Generic.List[string]
# KAPSAM (2026-09-10): kurulum\ da dahil. O klasordeki betikler de Turkce metin
# tasiyor ve BOM'suz yazildiklarinda ayni sessiz bozulmayi yasiyorlar - ilk
# yazildiklarinda tam olarak bu oldu ve bu satir onlari GORMEDIGI icin doktor
# yesil kaldi. Kurulum betikleri motorun parcasidir, denetim disinda kalamaz.
$scriptFiles = @(Get-ChildItem -LiteralPath (Join-Path $Vault 'motor\hooks'),
                                            (Join-Path $Vault 'motor\scripts'),
                                            (Join-Path $Vault 'kurulum') `
                 -Filter '*.ps1' -File -ErrorAction SilentlyContinue)
# SATIR SONU DA DENETLENIR (2026-09-17, olculdu). Projenin degismezi
# "tum .ps1 UTF-8 BOM + CRLF" ve .gitattributes 'eol=crlf' diyor, ama bu
# satir yalnizca BOM'a bakiyordu. Iki dosya (arsivle.ps1, beyin-launcher.ps1)
# BOM'lu ama LF satir sonluydu ve hicbir kontrol bunu gormedi: kural vardi,
# uygulanmiyordu. Sebep, calisma agaci kopyalarinin o kural konmadan once
# cikarilmasi; git mevcut dosyalari kendiliginden yenilemiyor
# (care: git rm --cached + checkout ya da git add --renormalize).
$lfBetik = New-Object System.Collections.Generic.List[string]
foreach ($f in $scriptFiles) {
    try {
        $fs = [System.IO.File]::OpenRead($f.FullName)
        $buf = New-Object byte[] 3
        [void]$fs.Read($buf, 0, 3); $fs.Close()
        if (-not ($buf[0] -eq 0xEF -and $buf[1] -eq 0xBB -and $buf[2] -eq 0xBF)) { $noBom.Add($f.Name) }
    } catch { }
    try {
        # Bayt duzeyinde say: CR sayisi LF sayisina esit degilse dosya ya
        # tamamen LF ya da KARISIK satir sonu tasiyor. Ikisi de sozlesme disi.
        $ham = [System.IO.File]::ReadAllBytes($f.FullName)
        $cr = 0; $lf = 0
        foreach ($b in $ham) { if ($b -eq 13) { $cr++ } elseif ($b -eq 10) { $lf++ } }
        if ($lf -gt 0 -and $cr -ne $lf) { $lfBetik.Add("$($f.Name) (CR=$cr LF=$lf)") }
    } catch { }
}
$kodSorun = New-Object System.Collections.Generic.List[string]
if ($noBom.Count)   { $kodSorun.Add("$($noBom.Count) betikte BOM yok: $($noBom -join ', ')") }
if ($lfBetik.Count) { $kodSorun.Add("$($lfBetik.Count) betikte satir sonu CRLF degil: $($lfBetik -join ', ')") }
Add-Row 'betik kodlamasi' ($kodSorun.Count -eq 0) `
    $(if ($kodSorun.Count) { $kodSorun -join ' · ' } else { "$($scriptFiles.Count) betik, hepsi UTF-8 BOM + CRLF" }) `
    'PS 5.1 BOM''suz .ps1 dosyasini ANSI okur (ASCII-disi karakter parse hatasi verir); satir sonu sozlesmesi .gitattributes''ta eol=crlf. Duzeltme: git rm --cached <dosya>; git checkout -- <dosya>'

# ============================================================================
# BETIKLER  (hepsi - onceki surum yalniz ucunu denetliyordu)
# ============================================================================
foreach ($f in ($scriptFiles | Sort-Object Name)) {
    $err = $null
    [System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$null, [ref]$err) | Out-Null
    $n = @($err).Count
    $grp = if ($f.DirectoryName -like '*hooks*') { 'hook' } else { 'script' }
    Add-Row "$grp/$($f.Name)" ($n -eq 0) `
        $(if ($n) { "sozdizimi hatasi: $n (ilk: satir $($err[0].Extent.StartLineNumber))" } else { 'sozdizimi temiz' }) `
        'dosyayi yeniden yaz'
}

# ============================================================================
# KANCA YAPILANDIRMASI
# ============================================================================
$sj = Join-Path $env:USERPROFILE '.claude\settings.json'
$sjOk = $false; $sjDetay = 'global settings.json yok'; $hookPathsOk = $true; $missing = @()
if (Test-Path -LiteralPath $sj) {
    try {
        $cfg = Get-Content -LiteralPath $sj -Raw -Encoding UTF8 | ConvertFrom-Json
        $wired = New-Object System.Collections.Generic.List[string]
        foreach ($evt in @('SessionStart','UserPromptSubmit','SessionEnd','PreCompact')) {
            foreach ($e in @($cfg.hooks.$evt)) {
                foreach ($h in @($e.hooks)) {
                    if ($h.command -and (Test-BeyinMatch -Text $h.command -Pattern 'beyin-launcher')) {
                        if ($wired -notcontains $evt) { $wired.Add($evt) }
                        # kanca yolunun gercekten var oldugunu dogrula
                        $mm = [regex]::Match($h.command, '-File\s+"([^"]+)"')
                        if ($mm.Success -and -not (Test-Path -LiteralPath $mm.Groups[1].Value)) {
                            $hookPathsOk = $false; $missing += (Split-Path -Leaf $mm.Groups[1].Value)
                        }
                    }
                }
            }
        }
        $sjOk = ($wired -contains 'SessionStart') -and ($wired -contains 'SessionEnd')
        $sjDetay = "bagli olay: $(if ($wired.Count) { $wired -join ', ' } else { 'hicbiri' })"
    } catch { $sjDetay = 'JSON bozuk' }
}
Add-Row 'global kanca ayari' $sjOk $sjDetay 'global settings.json icine beyin kancalarini ekle'
Add-Row 'kanca yollari' $hookPathsOk `
    $(if ($hookPathsOk) { 'ayardaki tum kanca dosyalari mevcut' } else { "eksik: $($missing -join ', ')" }) `
    'vault tasindiysa global settings.json icindeki yollari guncelle'

# LAUNCHER IZI - kancanin vault'a HIC ULASAMADIGI durumlar.
# Launcher, kayitli vault yolu erisilemezse ya da kanca betigi yoksa
# ~\.beyin\launcher-hata.log dosyasina tek satir dusuyor (vault'a yazamaz,
# cunku sorun tam olarak vault'a ulasamamasi). O dosyayi OKUYAN bir goz
# olmazsa iz birakmak hicbir sey degistirmez - bu satir o goz.
#
# Kill switch (BEYIN_VAULT var olmayan bir yola ayarli) iz BIRAKMAZ, yani
# motoru bilerek susturan kullanici burada kirmizi gormez.
$lncLog = Join-Path $env:USERPROFILE '.beyin\launcher-hata.log'
$lncSatir = @()
$lncSon = ''
if (Test-Path -LiteralPath $lncLog) {
    try {
        $lncHam = @(Get-Content -LiteralPath $lncLog -Encoding UTF8 -ErrorAction Stop | Where-Object { $_.Trim() })
        # Yalniz son 7 gun: eski bir ariza cozulduyse kalici kirmizi olmasin.
        $lncEsik = (Get-Date).AddDays(-7)
        foreach ($ln in $lncHam) {
            $m = [regex]::Match([string]$ln, '^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})')
            if (-not $m.Success) { continue }
            $t = [datetime]::MinValue
            if ([datetime]::TryParseExact($m.Groups[1].Value, 'yyyy-MM-dd HH:mm:ss',
                    [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$t)) {
                if ($t -ge $lncEsik) { $lncSatir += $ln }
            }
        }
        if ($lncSatir.Count) { $lncSon = [string]$lncSatir[-1] }
    } catch {
        # Dosya okunamadi: "temiz" demek YANLIS olur, bunu soyle.
        $lncSon = "log okunamadi: $($_.Exception.Message)"
        $lncSatir = @($lncSon)
    }
}
Add-Row 'launcher izi' ($lncSatir.Count -eq 0) `
    $(if ($lncSatir.Count) { "$($lncSatir.Count) kayit (7 gun) · son: $lncSon" } else { 'kayit yok (kancalar vault''a ulasiyor)' }) `
    'Launcher kancayi calistiramadi: kayitli vault yolu erisilemiyor (harici/ag disk bagli degil, klasor tasindi) ya da kanca betigi eksik. O oturumlar HAFIZASIZ acildi. Yolu dogrula: beyin nerede  ·  vault tasindiysa: beyin kur  ·  duzelince dosyayi sil: %USERPROFILE%\.beyin\launcher-hata.log'

$vsj = Join-Path $Vault '.claude\settings.json'
Add-Row 'cift tetiklenme' (-not (Test-Path -LiteralPath $vsj)) `
    $(if (Test-Path -LiteralPath $vsj) { 'vault settings.json VAR: kancalar 2 kez calisir' } else { 'vault settings.json yok (dogru)' }) `
    'vault .claude/settings.json dosyasini sil'

# ============================================================================
# KURATORLU HAFIZA
# ============================================================================
foreach ($m in @('current-context.md','active-threads.md','rules.md','profile.md','decisions.md','session-index.md')) {
    $f = Join-Path $p.Memory $m
    $ok = Test-Path -LiteralPath $f
    $detay = 'yok'
    if ($ok) {
        $d = (Get-Item -LiteralPath $f).LastWriteTime
        $detay = "$($d.ToString('yyyy-MM-dd')) ($([int]((Get-Date) - $d).TotalDays) gun once)"
    }
    Add-Row "80-memory/$m" $ok $detay 'eksikse ONIZLEME ile olustur'
}

# ============================================================================
# MAKINE BOLGELERI
# ============================================================================
$dayFiles = @(Get-ChildItem -LiteralPath $p.Daylogs -Filter '*.md' -File -ErrorAction SilentlyContinue |
              Where-Object { $_.Name -cmatch '^\d{4}-\d{2}-\d{2}\.md$' })
# Kavram SAYISI yalniz concepts altindan; TARAMA kapsami tum 86-compiled.
# index.md / log.md / son-durum.md model uretimi metin tasiyor ve son-durum
# gunluk log bloklarinin TAM GOVDESINI kopyaliyor - sir/mutlak yol taramasinin
# disinda kalmalari kor nokta idi.
$conFiles = @(Get-ChildItem -LiteralPath (Join-Path $p.Compiled 'concepts') -Filter '*.md' -File -ErrorAction SilentlyContinue)
$scanFiles = @(Get-ChildItem -LiteralPath $p.Compiled -Recurse -Filter '*.md' -File -ErrorAction SilentlyContinue) +
             @(Get-ChildItem -LiteralPath $p.Memory -Filter '*.md' -File -ErrorAction SilentlyContinue) +
             @(Get-ChildItem -LiteralPath (Join-Path $Vault '90-archive') -Recurse -Filter '*.md' -File -ErrorAction SilentlyContinue)
Add-Row '85-daylogs' $true "$($dayFiles.Count) gunluk log"
Add-Row '86-compiled' $true "$($conFiles.Count) kavram notu"

# En eski gunluk log yasi -> arsivleme onerisi
if ($dayFiles.Count -gt 0) {
    $oldest = ($dayFiles | Sort-Object Name | Select-Object -First 1)
    $age = 0
    try { $age = [int]((Get-Date) - [datetime]::ParseExact($oldest.BaseName, 'yyyy-MM-dd', $null)).TotalDays } catch { }
    $eskiler = @($dayFiles | Where-Object {
        try { ((Get-Date) - [datetime]::ParseExact($_.BaseName, 'yyyy-MM-dd', $null)).TotalDays -gt 90 } catch { $false }
    })
    Add-Row 'daylog yasi' ($eskiler.Count -eq 0) `
        "en eski: $($oldest.BaseName) ($age gun), 90 gunu gecen: $($eskiler.Count)" `
        $(if ($eskiler.Count) { 'arsivle.ps1 (kuru calisma) ile gozden gecir' } else { '' })
}

$pending = @(Get-BeyinPendingDaylogs -Paths $p)
Add-Row 'derleme kuyrugu' ($pending.Count -le 7) `
    "$($pending.Count) bekleyen log$(if ($pending.Count) { ': ' + (($pending | Select-Object -ExpandProperty BaseName) -join ', ') })" `
    $(if ($pending.Count -gt 7) { 'compile.ps1 -Force ile elle derle' } else { '' })

# DENEME TAVANI - tavana carpip 'final' sayilan gunler SESSIZ kalmamali:
# o gunun icerigi bir daha derlemeye girmeyecek, kullanici bilmeli.
$sd = Get-BeyinSeenDetail -Paths $p
$tavanaCarpan = @($sd.GetEnumerator() | Where-Object { $_.Value.State -ne 'final' -and $_.Value.Attempts -ge $script:BeyinMaxCompileAttempts } |
                  ForEach-Object { "$($_.Key) ($($_.Value.Attempts)x)" })
Add-Row 'derleme deneme tavani' ($tavanaCarpan.Count -eq 0) `
    "$($tavanaCarpan.Count) gun tavana carpti$(if ($tavanaCarpan.Count) { ': ' + ($tavanaCarpan -join ', ') })" `
    $(if ($tavanaCarpan.Count) { 'bu gunler artik derlenmeyecek; compile.ps1 -Force ile elle dene' } else { '' })

# ============================================================================
# BUTUNLUK  ("yazildi" denen blok gercekten dosyada mi)
# ----------------------------------------------------------------------------
# Bu kontrol denetimde bulunan kor noktayi kapatir: engine.log 8 kez
# "flush: yazildi" derken dosyada 0 blok vardi ve doktor "saglikli" diyordu.
# ============================================================================
$today = Get-BeyinToday
$todayLog = Join-Path $p.Daylogs "$today.md"
$blockFile = Join-Path $p.ScrState "blocks-$today.txt"
$expected = 0
if (Test-Path -LiteralPath $blockFile) {
    $raw = (Get-Content -LiteralPath $blockFile -Raw); if ($raw) { [int]::TryParse($raw.Trim(), [ref]$expected) | Out-Null }
}
$actual = 0
if (Test-Path -LiteralPath $todayLog) {
    $actual = ([regex]::Matches((Get-Content -LiteralPath $todayLog -Raw -Encoding UTF8), '(?m)^### Oturum')).Count
}
Add-Row 'gunluk log butunlugu' ($actual -ge $expected) `
    "bugun yazildi denen: $expected, dosyada bulunan: $actual" `
    $(if ($actual -lt $expected) { 'blok kaybi var: dosya elle silinmis olabilir veya yazma basarisiz' } else { '' })

# Ayni butunluk kontrolu GECMIS gunler icin.
#
# NEDEN ("zamanlanmis is calisiyor ama bos donuyor" sinifindan bir ders):
#   Yukaridaki kontrol yalnizca BUGUNE bakiyordu. Blok kaybi dun olduysa bugun
#   expected=actual oldugu icin doktor "saglikli" diyordu ve kayip kalici olarak
#   fark edilmeden kaliyordu. Kaybin fark edilme suresi, kaybin oldugu gunun
#   bitmesiyle sonsuza gidiyordu.
#
# Bu kontrol yeni bir alarm SINIFI getirmez, mevcut degismezi geriye tasir:
# motor o gun hic calismadiysa iddia da bulunan da 0'dir ve satir yesil kalir.
# Yani vault'a birkac gun girilmemesi gurultu uretmez.
$gecmisKayip = @()
foreach ($bf in @(Get-ChildItem -LiteralPath $p.ScrState -Filter 'blocks-*.txt' -File -ErrorAction SilentlyContinue)) {
    $gun = $bf.BaseName -replace '^blocks-', ''
    if ($gun -eq $today) { continue }                      # bugun yukarida olculdu
    if ($gun -cnotmatch '^\d{4}-\d{2}-\d{2}$') { continue }

    $bek = 0
    try {
        $raw = (Get-Content -LiteralPath $bf.FullName -Raw)
        if ($raw) { [int]::TryParse($raw.Trim(), [ref]$bek) | Out-Null }
    } catch { }
    if ($bek -le 0) { continue }

    $gLog = Join-Path $p.Daylogs "$gun.md"
    if (-not (Test-Path -LiteralPath $gLog)) {
        # Arsivlenmis olabilir; yoklugu tek basina kayip sayilmaz.
        continue
    }
    $bul = 0
    try { $bul = ([regex]::Matches((Get-Content -LiteralPath $gLog -Raw -Encoding UTF8), '(?m)^### Oturum')).Count } catch { }
    if ($bul -lt $bek) { $gecmisKayip += "$gun ($bul/$bek)" }
}
Add-Row 'gunluk log butunlugu (gecmis)' ($gecmisKayip.Count -eq 0) `
    "$($gecmisKayip.Count) gunde blok kaybi$(if ($gecmisKayip.Count) { ': ' + ($gecmisKayip -join ', ') })" `
    $(if ($gecmisKayip.Count) { 'o gunun logu elle duzenlenmis/silinmis olabilir; gecmis-toparla.ps1 ile gozden gecir' } else { '' })

# ============================================================================
# IS KUYRUGU ve WATERMARK
# ============================================================================
$q = @(Get-ChildItem -LiteralPath $p.Queue -Filter '*.json' -File -ErrorAction SilentlyContinue)
Add-Row 'is kuyrugu' ($q.Count -le 5) "$($q.Count) bekleyen flush isi" `
    $(if ($q.Count -gt 5) { 'butce/slot tavani surekli doluyor olabilir; engine.log''a bak' } else { '' })

$w = @(Get-ChildItem -LiteralPath $p.Marks -Filter '*.json' -File -ErrorAction SilentlyContinue)
$islenmis = 0; $buyukParcaMark = 0; $karantina = @{}; $takili = New-Object System.Collections.Generic.List[string]
foreach ($mf in $w) {
    try { $mo = Get-Content -LiteralPath $mf.FullName -Raw -Encoding UTF8 | ConvertFrom-Json } catch { continue }
    $ln = if ($mo.PSObject.Properties['lines']) { [int]$mo.lines } else { 0 }
    if ($ln -gt 0) { $islenmis++; continue }
    $rn = if ($mo.PSObject.Properties['reason']) { [string]$mo.reason } else { 'bilinmiyor' }
    # Tavan ustu dosyanin BAYT isareti: 'lines' 0 ama islenmis. Ayri kova.
    if ($rn -eq 'buyuk-parca') { $buyukParcaMark++; continue }
    $sk = if ($mo.PSObject.Properties['skips']) { [int]$mo.skips } else { 0 }
    if ($sk -le 0) { continue }
    if (-not $karantina.ContainsKey($rn)) { $karantina[$rn] = 0 }
    $karantina[$rn]++
    # 5+ kez denenmis ve hala ozetlenememis: dosya buyuyor ama ozetlenemiyor.
    # Bu bir hata isaretidir, karantinanin normal isleyisi degil.
    #
    # ISTISNA: 'cok-kisa' bir ARIZA DEGIL, tasarlanmis sonuctur.
    #   flush.ps1 4 turdan kisa konusmayi ozetlemez ve Test-BeyinShouldRetry
    #   dosya BUYUMEDIKCE tekrar denemez. Kullanici bir oturumda uc kez kisa
    #   sey yazip biraktiysa dosya birkac kez buyur, her seferinde hala kisadir
    #   ve sayac artar. Bunu 'cikis-kodu'/'bos-yanit' gibi gercek motor
    #   arizalariyla ayni kefeye koymak doktoru kalici kirmiziya cakiyor -
    #   ve surekli kirmizi bir gosterge, okunmayan bir gostergedir.
    #
    # AMA korlemesine muaf tutmak gercek bir bugu gizlerdi: transkript
    # ayristiricisi bozulup buyuk bir dosyaya "0 tur" derse o da 'cok-kisa'
    # olarak kaydedilir. Ayirt edici olcut BOYUT DEGIL, HAM SATIR SAYISIDIR.
    #   olculdu 2026-08-30: 134,7 KB'lik bir dosya yalnizca 14 ham satir ve
    #   3 tur icieriyordu (birkac dev mesaj) -> 'cok-kisa' DOGRU siniflandirma.
    #   Ayni gun 1,8 MB / 724 satirlik dosyadan ayristirici 141 tur cikardi.
    # Yani cok satirli bir dosya hala "cok kisa" gorunuyorsa ayristirma
    # suphelidir ve BILDIRILIR. Karantinadaki 8 dosyanin en yuksegi 29 satir.
    if ($sk -ge 5) {
        $bildir = $true
        if ($rn -like 'buyuk-*') { $bildir = $false }   # tavan ustu: 'yeni bayt yok' ariza degil
        # Codex makine thread'leri (subagent, onboarding_checklist, guardian...) TASARIM GEREGI
        # ozetlenmez; her SessionEnd tetiginde tekrar denenip sayac artar. Takili degil, filtre.
        if ($rn -like 'codex-makine-thread-*') { $bildir = $false }
        if ($rn -eq 'cok-kisa') {
            $bildir = $false
            $tp = [string]$mo.path
            # TAVAN USTU dosyada satir sayma YOK: Get-Content 1 GB'lik rollout'u
            # dakikalarca kilitler (olculdu). Buyuk dosya bayt penceresiyle
            # okunur; 'cok-kisa' orada 'pencerede tur yok' demektir, ayristirma
            # suphesi degil.
            if ($tp -and (Test-Path -LiteralPath $tp) -and
                ((Get-Item -LiteralPath $tp).Length -le ((Get-BeyinMaxTranscriptMB) * 1MB))) {
                try {
                    $hamSatir = (Get-Content -LiteralPath $tp -ErrorAction Stop | Measure-Object -Line).Lines
                    if ($hamSatir -ge 40) {
                        $bildir = $true
                        $rn = "cok-kisa/AYRISTIRMA-SUPHELI-$hamSatir-satir"
                    }
                } catch { }
            }
        }
        if ($bildir) { $takili.Add("$(Split-Path -Leaf ([string]$mo.path)) (${sk}x $rn)") }
    }
}
Add-Row 'watermark' $true "$islenmis transkript ozetlenmis (tekrar ozetleme korumasi)$(if ($buyukParcaMark) { ", $buyukParcaMark tavan ustu bayt isaretli" })"

# KARANTINA - sessiz filtre sessiz kayiptir: sebebiyle birlikte gorunur olmali.
$kSay = ($karantina.Values | Measure-Object -Sum).Sum
if (-not $kSay) { $kSay = 0 }
Add-Row 'karantina' ($takili.Count -eq 0) `
    "$kSay transkript karantinada$(if ($karantina.Count) { ' -> ' + (($karantina.GetEnumerator() | Sort-Object Name | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ', ') })" `
    $(if ($takili.Count) { "5+ kez denenip hala ozetlenemeyen: $($takili -join '; ') - engine.log'a bak" } else { '' })

$sv = Test-BeyinStateCompatible -Paths $p
$claimSay = @(Get-ChildItem -LiteralPath $p.Claims -Filter '*.lock' -File -ErrorAction SilentlyContinue).Count
Add-Row 'durum surumu' $sv.Ok `
    "motor v$(Get-BeyinVersion -Vault $Vault), $($sv.Checked) durum dosyasi + $claimSay claim kilidi kontrol edildi$(if ($sv.Mismatched.Count) { ", uyumsuz: $($sv.Mismatched -join ', ')" })" `
    $(if (-not $sv.Ok) { 'daha yeni bir motor surumu bu durumu yazmis olabilir; .state icerigini gozden gecir' } else { '' })

# Makine bolgesindeki degisiklikler commit edilmemis mi (geri alinabilirlik)
try {
    Push-Location $Vault
    $dirty = @(& git status --porcelain -- '85-daylogs' '86-compiled' 2>$null)
    Pop-Location
    Add-Row 'makine bolgesi git' ($dirty.Count -le 20) `
        "$($dirty.Count) commit edilmemis makine dosyasi" `
        $(if ($dirty.Count -gt 20) { 'motor yazmalari tek kopya; commit atmayi dusun (git ile geri alinabilir olur)' } else { '' })
} catch { }

$budgetFile = Join-Path $p.ScrState ("budget-$today.txt")
$used = 0
if (Test-Path -LiteralPath $budgetFile) {
    $raw = (Get-Content -LiteralPath $budgetFile -Raw); if ($raw) { [int]::TryParse($raw.Trim(), [ref]$used) | Out-Null }
}
# TAVAN: flush 50 gorur, compile 60. Satir 60'i esik aliyordu ama sayac
# 50'de DONUYOR (Test-BeyinBudget tavanda artirmadan doner), yani satir
# YAPISAL OLARAK asla kirmizi olamiyordu - flush tamamen kilitliyken bile
# 'OK 50/60' yaziyordu. Belirleyici esik flush tavani.
$fb = Get-BeyinFlushBudget; $cb = Get-BeyinCompileBudget

# KIM YEDI (2026-09-17): kullanici "o kadar oturum kapatmadim, kotam niye
# doldu" diye sordugunda cevabi bulmak icin makbuzlari elle cozumlemek
# gerekti. Cevap satirin KENDISINDE olmali. Bugunun makbuzlarindan butce
# harcayan cagrilar sebebe gore gruplanir; ilk uc kalem basilir.
$butceKim = ''
try {
    $bkSebep = @{}
    foreach ($m in @(Read-BeyinMakbuz -Paths $p -Gun 1)) {
        $bb = 0
        try { $bb = [int]$m.budget } catch { }
        if ($bb -le 0) { continue }
        $r = [string]$m.reason
        if (-not $r) { $r = [string]$m.script }
        if (-not $r) { $r = '?' }
        if (-not $bkSebep.ContainsKey($r)) { $bkSebep[$r] = 0 }
        $bkSebep[$r] = [int]$bkSebep[$r] + $bb
    }
    $bkSira = @($bkSebep.GetEnumerator() | Sort-Object -Property Value -Descending | Select-Object -First 3)
    if ($bkSira.Count -gt 0) {
        $butceKim = ' - en cok: ' + (($bkSira | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ', ')
    }
} catch { }

Add-Row 'gunluk butce' ($used -lt $fb) "$used / $fb flush tavani (derleyici rezervi $cb)$butceKim" `
    $(if ($used -ge $fb) { "flush tavani DOLU: yeni oturum ozeti uretilmiyor, isler KUYRUGA aliniyor (kayip yok). Gece yarisi sifirlanir. 'pre-compact' kalemi buyukse sebep uzun oturumlarin otomatik sikismasidir - oturum basina pay zaten sinirli; tavani yukseltmek icin: beyin ayar BEYIN_FLUSH_BUTCE <sayi>" } else { '' })

# ============================================================================
# ES ZAMANLILIK
# ============================================================================
$sessFiles = @(Get-ChildItem -LiteralPath $p.Sessions -Filter '*.json' -File -ErrorAction SilentlyContinue)

# ESIK MOTORDAN GENIS OLMALI.
#
# Motor (Clear-BeyinStaleSessions) 3 gunden eski dosyalari SessionStart'ta
# siler. Doktor da 3 gun kullaninca, son oturumdan sonra bayatlamis dosyalari
# "SORUN" diye bildiriyordu - oysa bir sonraki oturum onlari zaten silecekti.
#
# Olculdu 2026-08-30: 12 dosya "bayat" isaretlendi; hepsi motorun esigini yeni
# gecmisti ve silme mekanizmasi calisiyordu (elle dogrulandi).
#
# Bir izleyici NORMAL GECIKMEYE degil, BASARISIZLIGA alarm vermeli. 4 gun,
# motorun en az bir temizlik firsatini kacirdigini gosterir - asil bildirmek
# istedigimiz sey bu.
$engineDays = Get-BeyinSessionStaleDays   # motorla AYNI kaynak (14); doktor 3 sanip 25 dosyayi yanlis bildiriyordu
$stale = @($sessFiles | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-($engineDays + 1)) })
$bekleyen = @($sessFiles | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-$engineDays) }).Count - $stale.Count
$detay = "$($sessFiles.Count) acik/yarim oturum, $($stale.Count) bayat"
if ($bekleyen -gt 0) { $detay += " ($bekleyen tanesi sonraki oturumda silinecek)" }
Add-Row 'oturum durumu' ($stale.Count -eq 0) $detay `
    'Bayat oturum durumu, motorun en az bir temizlik firsatini kacirdigini gosterir (esik: Get-BeyinSessionStaleDays + 1 gun). Kancalar calisiyor mu: beyin doktor -> ''ajan esligi''. Temizlik bir sonraki oturum acilisinda kendiliginden kosar; surerse dosyalari elle sil: <vault>\motor\hooks\.state\sessions'

$reflects = @(Get-ChildItem -LiteralPath $p.Reflect -Filter '*.txt' -File -ErrorAction SilentlyContinue)
Add-Row 'yansima kuyrugu' ($reflects.Count -le 10) "$($reflects.Count) bekleyen yansima isareti" `
    'Yansima isaretleri birikiyor: oturum sonunda hafiza guncellemesi onerildi ama hic yazilmadi. Kuratorlu bolge senin sorumlulugunda - 80-memory/current-context.md ve active-threads.md guncelle, sonra <vault>\motor\scripts\.state\reflect altindaki isaretleri sil.'

# ============================================================================
# GUVENLIK
# ============================================================================
$leakFiles = New-Object System.Collections.Generic.List[string]
$desenDusen = 0
$sirHedef = @($dayFiles + $scanFiles) | Where-Object { $_ }
foreach ($f in $sirHedef) {
    $c = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8
    if (-not $c) { continue }
    # -Vault GECILIYOR: desen dusmesi engine.log'a yazilsin (lib.ps1 bunu
    # acikca istiyor). $r.Failed de okunuyor: bir desen dusmusse tarama
    # EKSIK yapilmistir, 'temiz' demek FAIL-OPEN olurdu.
    $r = Protect-BeyinSecrets -Text $c -Vault $Vault
    $desenDusen += [int]$r.Failed
    $already = ([regex]::Matches($c, '\[REDAKTE:[a-z\-]+\]', $script:BeyinRxCI)).Count
    if ($r.Redactions -gt $already) { $leakFiles.Add($f.Name) }
}
Add-Row 'sir taramasi' (($leakFiles.Count -eq 0) -and ($desenDusen -eq 0)) `
    $(if ($leakFiles.Count) { "$($leakFiles.Count) dosyada maskelenmemis sir: $($leakFiles -join ', ')" }
      elseif ($desenDusen -gt 0) { "$($sirHedef.Count) dosya tarandi AMA $desenDusen desen uygulanamadi - tarama EKSIK" }
      else { "$($sirHedef.Count) dosya tarandi (gunluk log + 86-compiled + 80-memory + 90-archive), temiz" }) `
    'sizan degeri ROTASYONA al; dosyayi temizlemek yetmez, git gecmisine girmis olabilir'

# Mutlak yol sizintisi
$pathLeak = @()
# Desen ILERI egik cizgiyi de kapsar: ajanlar Git Bash / Node baglaminda
# 'C:/Users/...' yaziyor ve eski desen bunu goremiyordu (85-daylogs'ta
# commit edilmis gercek ornek bulundu). /home/<kullanici>/ da eklendi.
$yolRx = '(?:[A-Za-z]:[\\/]Users[\\/][^\\/\s]+[\\/]|/(?:home|Users)/[^/\s]+/)'
foreach ($f in @($dayFiles + $scanFiles) | Where-Object { $_ }) {
    $c = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8
    if ($c -and [regex]::IsMatch($c, $yolRx)) { $pathLeak += $f.BaseName }
}
$pathLeak = @($pathLeak | Sort-Object -Unique)
Add-Row 'mutlak yol' ($pathLeak.Count -eq 0) `
    $(if ($pathLeak.Count) { "$($pathLeak.Count) dosyada tam kullanici yolu var: $(($pathLeak | Select-Object -First 6) -join ', ')" } else { 'makine bolgesi ve 80-memory temiz' }) `
    'motor artik yalniz yaprak ad yaziyor; eski kayitlar elle temizlenebilir'

$injFiles = @()
foreach ($f in $dayFiles) {
    $c = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8
    if ($c -and (Test-BeyinMatch -Text $c -Pattern 'UYARI - supheli talimat metni')) { $injFiles += $f.BaseName }
}
Add-Row 'injection uyarisi' ($injFiles.Count -eq 0) `
    $(if ($injFiles.Count) { "$($injFiles.Count) gunde uyari: $($injFiles -join ', ')" } else { 'uyari yok' }) `
    'o gunlerin loglarini gozden gecir'

# ============================================================================
# MOTOR LOGU  (basarisizlik gorunur olsun)
# ============================================================================
$eng = Join-Path $p.ScrState 'engine.log'
# NEDEN (2026-09-16 denetim): engine.log burada BIR KEZ ve TAMAMEN yuklenir
# (dondurulmus engine.1.log ile birlikte); hem 'motor logu' satiri hem asagidaki
# kayip kapilari sayimlari ayni diziyi kullanir. Eskiden yukleme kayip kapilari
# bolumundeydi ve bu satir yalniz -Tail 60'a bakabiliyordu: motor dakikada 5-6
# satir yazdigi icin 60 satir ~10 dakikaydi (olculdu: 21:50 -> 22:00); 21:40'taki
# bir basarisizlik 21:55'te coktan pencere disindaydi.
# DONEN LOG: Write-BeyinLog 1 MB'de engine.log -> engine.1.log'a donduruyor.
# 7 gunluk sayimlar iki dosyayi birlikte okumali, yoksa dondurmenin hemen
# ardindaki ilk kosuda her sayim sifir gorunup YESIL raporlanir.
# BAYT TAVANI (2026-09-17, kosarak olculdu). Eskiden iki log dosyasi da
# TAMAMEN yukleniyordu, boyut kapisi yoktu. Olculen sureler (taban 10 sn):
#   1 MB NUL dolu   -> 116 sn
#   10 MB NUL dolu  -> 300 sn ustu (oldurulmus)
#   100 MB NUL dolu -> 421 sn ustu (oldurulmus)
#   50 MB normal satir -> 200 sn ustu (oldurulmus)
# Bekleme boyunca TEK SATIR cikti yoktu: kullanici donmus bir terminal
# goruyor, iptalden baska sinyali yok. 'beyin durum' en sik kullanilan komut;
# asilmasi motorun tanisini tamamen erisilemez kiliyor.
#
# Tum analizler 'son 24 saat' / 'son 7 gun' penceresinde calisiyor, yani eski
# satirlar hicbir hesaba girmiyor: son N bayti okumak yeterli. Kirpma
# OLDUGUNDA soylenir - sessiz kirpma, sessiz asilmadan daha az kotu degil.
#
# Write-BeyinLog 1 MB'de donduruyor ama (a) ancak BIR SONRAKI yazimda,
# (b) dosya kilitliyse kirpmaya dusuyor; cokmeyle NUL dolu kalmis bir log tam
# da en yavas haldir. Bu yuzden tavan burada, OKUMA tarafinda.
$LOG_TAVAN_BAYT = 4MB
$engKirpma = New-Object System.Collections.Generic.List[string]

function Read-DoktorLogKuyruk {
    # Dosyanin SON $LOG_TAVAN_BAYT baytini satir dizisi olarak dondurur.
    # Tavanin altindaysa tamami okunur (eski davranis aynen korunur).
    param([string]$Yol, [string]$Ad)
    if (-not (Test-Path -LiteralPath $Yol -PathType Leaf)) { return @() }
    try {
        $bilgi = Get-Item -LiteralPath $Yol -ErrorAction Stop
        if ($bilgi.Length -le $LOG_TAVAN_BAYT) {
            return @(Get-Content -LiteralPath $Yol -Encoding UTF8 -ErrorAction SilentlyContinue)
        }
        $atlanan = $bilgi.Length - $LOG_TAVAN_BAYT
        $script:engKirpma.Add("$Ad $([math]::Round($bilgi.Length / 1MB, 1)) MB (son $([math]::Round($LOG_TAVAN_BAYT / 1MB, 0)) MB okundu)")
        $metin = ''
        $fs = [System.IO.File]::Open($Yol, 'Open', 'Read', 'ReadWrite')
        try {
            [void]$fs.Seek($atlanan, [System.IO.SeekOrigin]::Begin)
            $buf = New-Object byte[] $LOG_TAVAN_BAYT
            $okunan = $fs.Read($buf, 0, $buf.Length)
            $metin = [System.Text.Encoding]::UTF8.GetString($buf, 0, $okunan)
        } finally { $fs.Close(); $fs.Dispose() }
        # Ilk satir yarim olabilir (bayt ortasindan basladik) - at.
        $satirlar = @($metin -split "`r?`n")
        if ($satirlar.Count -gt 1) { $satirlar = @($satirlar | Select-Object -Skip 1) }

        # SATIR UZUNLUGU TAVANI (2026-09-17, izole olcumle bulundu).
        # Bayt tavani TEK BASINA YETMEDI. Olculen:
        #   bu fonksiyonun kendisi      : 108 ms okuma + 275 ms split (hizli)
        #   doktor, log dosyasi YOK     : 6 sn
        #   doktor, 20 MB NUL log VAR   : 553 sn
        # Sebep: NUL dolu bir dosyada satir ayirici HIC yok; son 4 MB tek bir
        # 4.194.304 karakterlik "satir" olarak donuyor ve bu dev dizge $engAll
        # uzerinde calisan 11 ayri yerde tekrar tekrar regex'ten geciyor.
        # Gercek bir motor log satiri 200-400 karakter; bu tavani asan sey log
        # satiri DEGILDIR.
        $SATIR_TAVAN = 2000
        if (@($satirlar).Count -le 1 -and $metin.Length -gt $SATIR_TAVAN) {
            # Pencerede hic satir ayirici yok -> dosya bozuk (cokmeyle NUL
            # dolmus olabilir). Taramak anlamsiz; SOYLE ve bos don.
            $script:engKirpma.Add("$Ad satir ayirici icermiyor ($([math]::Round($metin.Length / 1MB, 1)) MB tek blok) - bozuk log, taranmadi")
            return @()
        }
        $uzunSay = 0
        $kirpik = New-Object System.Collections.Generic.List[string]
        foreach ($sl in $satirlar) {
            if ($null -eq $sl) { continue }
            if ($sl.Length -gt $SATIR_TAVAN) { $uzunSay++; $kirpik.Add($sl.Substring(0, $SATIR_TAVAN)) }
            else { $kirpik.Add($sl) }
        }
        if ($uzunSay -gt 0) { $script:engKirpma.Add("$Ad $uzunSay satir $SATIR_TAVAN karakterde kirpildi") }
        return @($kirpik.ToArray())
    } catch {
        $script:engKirpma.Add("$Ad okunamadi: $($_.Exception.Message)")
        return @()
    }
}

$engAll = @()
$engEski = Join-Path $p.ScrState 'engine.1.log'
$engAll += @(Read-DoktorLogKuyruk -Yol $engEski -Ad 'engine.1.log')
$engAll += @(Read-DoktorLogKuyruk -Yol $eng -Ad 'engine.log')

# LOG BOYUTU AYRI SATIR: kirpma olduysa kullanici BILMELI. Buyuyen bir log hem
# taniyi yavaslatir hem de dondurme mekanizmasinin calismadigini gosterir.
if ($engKirpma.Count -gt 0) {
    Add-Row 'motor log boyutu' $false ($engKirpma -join ' - ') `
        'Log tavani asti; doktor yalniz son bolumu okudu. Write-BeyinLog 1 MB''de dondurur; dondurme calismiyorsa dosya baska bir surec tarafindan tutuluyor olabilir. Kucultmek icin motoru bosta birak, .state icindeki engine.log dosyasini arsivle ya da sil (motor yeniden olusturur).'
}
function Get-DoktorLogSince {
    # engine.log satirlarini tarih damgasina gore suzer (satir basi 'yyyy-MM-dd HH:mm:ss').
    param([string[]]$Lines, [datetime]$Since, [string]$Pattern)
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($l in @($Lines)) {
        if (-not $l -or $l.Length -lt 19) { continue }
        $ts = $null
        try { $ts = [datetime]::ParseExact($l.Substring(0, 19), 'yyyy-MM-dd HH:mm:ss', [cultureinfo]::InvariantCulture) } catch { continue }
        if ($ts -lt $Since) { continue }
        if (Test-BeyinMatch -Text $l -Pattern $Pattern) { $out.Add($l) }
    }
    return $out.ToArray()
}
if (Test-Path -LiteralPath $eng) {
    # ASIL YAVASLIK BURADAYDI (2026-09-17, izole olcumle bulundu).
    # `Get-Content -Tail 60` satir sonu ARAYARAK geriye dogru okur. NUL ile
    # dolmus (cokme sonrasi) bir logda hic satir sonu yoktur, bu yuzden
    # dosyanin TAMAMINI geriye dogru tarar. Olculdu: doktor logsuz 6-7 sn,
    # 20 MB NUL logla 553 sn. Yukaridaki bayt tavani burayi KAPSAMIYORDU -
    # burasi BAGIMSIZ ikinci bir okumaydi ve tavan tek basina ise yaramadi.
    # $engAll zaten tavanli okundu; son 60 satiri oradan almak ayni sonucu
    # verir, ikinci bir tam dosya taramasi yapmaz.
    $tail = @($engAll | Select-Object -Last 60)
    # BUTCE/SLOT DOLMASI BASARISIZLIK DEGIL - tasarlanmis davranistir: is
    # dusurulmuyor, kuyruga aliniyor. Bunlari 'basarisizlik' saymak alarm
    # yorgunlugu yaratir ve kullaniciyi gercek hatalari gormemeye alistirir
    # (bu oturumda ayni desen uc kez cikti). Ayri sayilir, ayri raporlanir.
    # Desen, motorun 'sessiz olamaz' diye ozellikle ekledigi uyarilari da
    # kapsamali: eski uc kelime bunlarin HICBIRINI yakalamiyordu
    # (gunluk log sifir bayta inme nobetcisi, maskeleme dusmesi, isaret
    # yazilamamasi, bozuk isaret dosyasi).
    # NEDEN (2026-09-16 denetim): desen motorun KENDI hata satirlarini yakalamiyordu:
    # session-start/session-end 'toparlama hatasi:' / 'derleyici tetigi hatasi:',
    # flush 'updated tazelemesi hatasi:', zamanli-kos '[zamanlayici] HATA:',
    # '... ATLANDI: kimlik yok', 'bitti: X (kod=N'. engine.log'da 4 gercek
    # 'hatasi:' satiri ve bir 'derle ATLANDI: kimlik yok' satiri vardi; hicbiri
    # bu satiri kirmiziya cevirmemisti. Pencere: son 24 saat (gunde 350-420
    # satir) VE son 60 satir (motor iki gundur susmussa son hata yine gorunsun).
    # Butce/slot satirlari yine basarisizlik degildir (eski 'toparlama hatasi:
    # butce-dolu-atlandi' dahil) - ayri sayilir.
    # NEDEN (2026-09-16 inceleme): '(kod=' alt deseni '-?' ile negatif cocuk kodlarini da
    # yakalar: zamanlayici 3 saat sinirinda oldurdugunde ya da betik cokunce
    # zamanli-kos 'bitti: X (kod=-1073741510' (0xC000013A) yazar; '[1-9]' tek basina
    # eksi isaretinde takilip bu satiri yesil birakiyordu (kod=0 yine haric).
    $failDesen = 'BASARISIZ|bulunamadi|istisna|UYGULANAMADI|YAZILAMADI|MASKELENMEDI|BOZUK|UYARI -|hatasi:|\] HATA:|ATLANDI: kimlik|\(kod=-?[1-9]'
    $fails24   = @(Get-DoktorLogSince -Lines $engAll -Since (Get-Date).AddHours(-24) -Pattern $failDesen)
    $failsSon  = @($tail | Where-Object { Test-BeyinMatch -Text $_ -Pattern $failDesen })
    # NEDEN (2026-09-16 inceleme): gecmis-import her kosuda 'N yazildi, N atlandi, 0 basarisiz, ...'
    # ozet satiri yazar; 'BASARISIZ' buyuk/kucuk harf duyarsiz eslesince sifir hatali bir
    # takeout aktarimi 24 saat pencerede bu satiri bir gun kirmizi tutuyordu (eski 60
    # satirlik kuyrukta ~10 dakikada kayboluyordu). '0 basarisiz' haric tutulur; N>0
    # olan ozet yine sayilir.
    # KOTA/LIMIT ve KIMLIK de haric (2026-09-17): saglayici tavani ya da kapali
    # oturum motor arizasi DEGIL - cagri hizmet almadi, butce iade edildi, is
    # kuyrukta. 'butce doldu' zaten haricti; ayni sinif. Olculdu: gece oturum
    # limiti 8 satir yazdi ve 'motor logu' satirini kirmiziya cevirdi.
    # session-start saglik uyarisi ayni istisnayi kullanir (tek kural, iki yer).
    $fails     = @(@($fails24 + $failsSon) | Where-Object { -not (Test-BeyinMatch -Text $_ -Pattern 'butce-dolu|butce doldu|slot yok|\b0 basarisiz\b|KOTA/LIMIT|\[KIMLIK\]|session limit|usage limit') } | Select-Object -Unique)
    $tavan  = @($tail | Where-Object { Test-BeyinMatch -Text $_ -Pattern 'butce doldu|slot yok' })
    $lastFlush = @($tail | Where-Object { Test-BeyinMatch -Text $_ -Pattern 'flush: yazildi' } | Select-Object -Last 1)
    $detay = $(if ($lastFlush.Count) { "son flush: $(($lastFlush[0] -split '  ')[0])" } else { 'son 60 satirda basarili flush yok' })
    if ($tavan.Count) { $detay += " · $($tavan.Count) kez tavan doldu (kuyruga alindi)" }
    $detay += " · log: $eng"
    Add-Row 'motor logu' ($fails.Count -eq 0) $detay `
        $(if ($fails.Count) { "son 24 saatte / son 60 satirda $($fails.Count) basarisizlik: $((($fails | Select-Object -Last 1) -replace '\s+',' '))" } else { '' })
} else {
    Add-Row 'motor logu' $true 'henuz kayit yok (motor hic calismadi)' 'vault icinde bir oturum ac/kapa'
}

# ============================================================================
# KAYIP KAPILARI (2026-09-10) - "doktor yesil" ile "hicbir sey kaybolmuyor"
# ayni sey degil. Dort kor nokta olculdu; her biri ayri satir oldu:
#   1. tavan ustu transkriptin atlanmasi   (305 kez sessizce atlanmisti)
#   2. yetim penceresinden dusen oturumlar  (15 oturum hic ozetlenmemisti)
#   3. Codex SessionEnd'in hic ateslenmemesi (15 gunde 0 blok)
#   4. kuratorlu katmanin makine katmaninin gerisinde kalmasi (10 gun)
# ============================================================================
$sonYedi = (Get-Date).AddDays(-7)
# $engAll (engine.log + dondurulmus engine.1.log) ve Get-DoktorLogSince artik
# yukarida, MOTOR LOGU bolumunde yuklenir/tanimlanir (2026-09-16): 'motor logu'
# satiri da ayni diziyi kullaniyor, log iki kez okunmasin.
# Pencere gercekten 7 gunu kapsiyor mu?
$logIlkTarih = $null
foreach ($l in $engAll) {
    if ($l -and $l.Length -ge 19) {
        try { $logIlkTarih = [datetime]::ParseExact($l.Substring(0,19), 'yyyy-MM-dd HH:mm:ss', [cultureinfo]::InvariantCulture); break } catch { }
    }
}
$pencereEksik = ($logIlkTarih -eq $null) -or ($logIlkTarih -gt (Get-Date).AddDays(-7))
$pencereNot = if ($pencereEksik) { ' [pencere eksik: log dondurulmus]' } else { '' }

# 1) Tavan ustu transkript: atlanan var mi (eski davranis), pencere ozeti kac kez (yeni davranis)
# Pencere: son 24 saat AMA motor (lib.ps1) son degistirildikten sonrasi; duzeltme oncesi
# satirlar bir gun boyunca kirmizi gostermesin (olculdu: yamadan sonra 31 eski satir).
$motorMt = (Get-Item -LiteralPath (Join-Path $Vault 'motor\hooks\lib.ps1')).LastWriteTime
$buyukSince = (Get-Date).AddHours(-24)
if ($motorMt -gt $buyukSince) { $buyukSince = $motorMt }
$buyukAtlanan = @(Get-DoktorLogSince -Lines $engAll -Since $buyukSince -Pattern 'transkript cok buyuk .* atlandi')
$buyukParca   = @(Get-DoktorLogSince -Lines $engAll -Since $sonYedi -Pattern 'flush: buyuk transkript')
Add-Row 'buyuk transkript' ($buyukAtlanan.Count -eq 0) `
    $(if ($buyukAtlanan.Count) { "motor son degistiginden beri $($buyukAtlanan.Count) kez tavan ustu transkript ATLANDI (icerik beyne girmedi)" }
      else { "atlanan yok; bayt-penceresi ozeti: $($buyukParca.Count) kez (7 gun)$pencereNot" }) `
    'flush.ps1 tavan ustu dosyayi Read-BeyinTranscriptTail ile okumali (motor 2.1); eski surum atliyordu'

# 2) Yetim penceresinden dusen, hic ozetlenmemis oturumlar (gecmis-toparla kuru calisma)
$topla = Join-Path $Vault 'motor\scripts\gecmis-toparla.ps1'
$adaySay = -1; $adayDetay = ''
if (Test-Path -LiteralPath $topla) {
    try {
        # NEDEN (2026-09-16 denetim): -EnFazla 10 ile gecmis-toparla on adaylari
        # EnFazla*3 = 30 EN YENI dosyaya kirpiyor ve 'Pencere disi' sayimi bu
        # kirpmadan SONRA yapiliyor; 72 saat disina dusenler tanim geregi en
        # eskiler oldugu icin ilk onlar atiliyordu. Olculdu: -EnFazla 10 ->
        # 'Toplam aday 8 / Pencere disi 0', -EnFazla 1000 -> '37 / 23'; satir
        # 23 oturum kaybolmusken YESIL basiyordu. Bu satir yalniz SAYAR (kuru
        # calisma, -Uygula yok), o yuzden tavan fiilen kaldirildi (+1.3 sn olculdu).
        $tOut = @(& $topla -Vault $Vault -Gun 7 -EnFazla 1000 2>$null | Out-String -Stream)
        $toplamAday = -1
        foreach ($l in $tOut) {
            if ($l -match '^Toplam aday\s*:\s*(\d+)') { $toplamAday = [int]$Matches[1] }
            if ($l -match '^Pencere disi\s*:\s*(\d+)') { $adaySay = [int]$Matches[1] }
            if ($l -match '^Atlananlar\s*:\s*(.+)$') { $adayDetay = $Matches[1].Trim() }
        }
        # Yalniz 72 saatlik yetim penceresinin DISINA dusenler kayiptir; icindekileri
        # tarayici zaten toplar (kod incelemesi 2026-09-10, bulgu 4).
        if ($adaySay -lt 0 -and $toplamAday -ge 0) { $adaySay = 0 }
        if ($toplamAday -ge 0) { $adayDetay = "7 gunde toplam aday $toplamAday" + $(if ($adayDetay) { "; elenen: $adayDetay" } else { '' }) }
    } catch { }
}
# TAZE KURULUM ISTISNASI (2026-09-17, olculdu): bu kontrol MAKINEDEKI ajan
# transkriptlerini tarar, vault'un icini degil. Yayin kumesinden yeni kurulmus
# temiz bir vault'ta, kullanicinin aylardir suregelen Claude/Codex oturumlari
# aniden "37 oturum kayboldu" diye kirmizi basiyordu. O oturumlar beyin
# KURULMADAN onceye ait; hicbir zaman ozetlenmeyeceklerdi, yani kayip degil
# ON TARIH. Gunluk log yoksa beyin henuz tek bir sey kaydetmemis demektir.
# Kapi: gunluk log YOK **ve** kurulum yeni. Yalniz "log yok"a bakmak
# yetmiyordu - loglarini arsivlemis eski bir vault'ta gercek kayip
# maskelenebiliyordu (inceleme 2026-09-17, kosarak dogrulandi). Kurulum yasi
# icin .beyin-version'in olusturulma zamani kullanilir; klonlanmis ya da
# kopyalanmis bir vault'ta bu, vault'un BU MAKINEDE var oldugu andir - tam da
# aranan sey. Okunamazsa en eski makbuza bakilir; o da yoksa vault gercekten
# yenidir.
$kurulumGun = 0
try {
    $svDosya = Get-Item -LiteralPath (Join-Path $Vault '.beyin-version') -ErrorAction Stop
    $kurulumGun = [int]((Get-Date) - $svDosya.CreationTime).TotalDays
} catch {
    try {
        $mkEnEski = @(Get-ChildItem -LiteralPath $p.Makbuz -Filter '*.jsonl' -File -ErrorAction SilentlyContinue |
                      Sort-Object Name | Select-Object -First 1)
        if ($mkEnEski.Count -gt 0 -and $mkEnEski[0].BaseName -match '^(\d{4}-\d{2}-\d{2})$') {
            $kurulumGun = [int]((Get-Date) - [datetime]::ParseExact($Matches[1], 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)).TotalDays
        }
    } catch { }
}
$tazeVault = (($dayFiles.Count -eq 0) -and ($kurulumGun -le 7))
Add-Row 'yetim adaylari (7 gun)' (($adaySay -le 0) -or $tazeVault) `
    $(if ($tazeVault -and $adaySay -gt 0) { "taze kurulum ($kurulumGun gun): gunluk log yok, makinedeki $adaySay eski oturum beyin kurulmadan onceye ait (on tarih, kayip degil)" }
      elseif ($adaySay -lt 0) { 'kontrol edilemedi (gecmis-toparla calismadi) - sorun degil' }
      elseif ($adaySay -eq 0) { "72 saatlik pencereden dusup ozetlenmemis oturum yok$(if ($adayDetay) { " ($adayDetay)" })" }
      else { "$adaySay oturum 72 saatlik yetim penceresinden dustu, hic ozetlenmedi ($adayDetay)" }) `
    $(if ($tazeVault) { 'Eski oturumlari yine de almak istersen: beyin ice-aktar (dis gecmis) ya da beyin topla-uygula 7' }
      else { 'motor\scripts\gecmis-toparla.ps1 -Gun 7 -Uygula' })

# 3) Codex SessionEnd: codex bloklari var ama session-end tetigi hic yoksa kanca olu demektir
$codexSe = @(Get-DoktorLogSince -Lines $engAll -Since $sonYedi -Pattern 'session-end: .*ajan=codex')
$codexBlok = 0
foreach ($f in @(Get-ChildItem -LiteralPath $p.Daylogs -Filter '*.md' -File -ErrorAction SilentlyContinue |
                 Where-Object { $_.Name -cmatch '^\d{4}-\d{2}-\d{2}\.md$' -and $_.LastWriteTime -gt $sonYedi })) {
    try { $codexBlok += ([regex]::Matches((Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8), '\[codex/')).Count } catch { }
}
# engine.log 500 KB'de son 200 satira kirpilir; 7 gunluk sayim orada guvenilmez.
# Asil kanit session-end.ps1'in yazdigi damga dosyasidir (kod incelemesi, bulgu 5).
$seDamga = Join-Path $p.ScrState 'last-codex-session-end.txt'
$seDamgaOk = $false; $seDamgaNe = 'yok'
if (Test-Path -LiteralPath $seDamga) {
    $seDamgaZaman = (Get-Item -LiteralPath $seDamga).LastWriteTime
    $seDamgaNe = $seDamgaZaman.ToString('yyyy-MM-dd HH:mm')
    if ($seDamgaZaman -gt $sonYedi) { $seDamgaOk = $true }
}
# BEDAVA GECIS KAPATILDI (2026-09-10, bagimsiz denetim).
#
# Kosul eskiden '($codexBlok -eq 0) -or ...' ile basliyordu: yani 7 gunde HIC
# codex blogu yoksa satir OK veriyordu. Ama sifir blok, tam olarak KANCANIN
# OLU OLDUGUNUN belirtisidir. "Codex hic kullanilmiyor" ile "Codex kancasi
# calismiyor" ayni sey sayiliyordu ve ikincisi yesil raporlaniyordu.
#
# Bu ozellikle YENI MAKINEDE onemli: orada Codex'in guven hash'i yoktur, kanca
# /hooks ile onaylanana kadar sessizce atlanir, hicbir codex blogu yazilmaz -
# ve doktor "OK" derdi. Kurulum sonrasi prosedurun tamami uygulansa bile
# hicbir yerde kirmizi cikmazdi.
#
# Dogru ayrim DISKTEKI KANITA bakmak: Codex'in son 7 gunde gercek oturumu var
# mi? Varsa ve hicbiri hafizaya girmemisse SORUN. Hic oturum yoksa bu makinede
# Codex kullanilmiyor demektir - o zaman kontrol GECERSIZ, ve bunu acikca
# soyluyoruz ("kullanilmiyor"), sessizce yesil vermiyoruz.
$codexKok = @(Get-BeyinTranscriptRoots | Where-Object { $_.Agent -eq 'codex' })
$codexOturum = 0
if ($codexKok.Count -and (Test-Path -LiteralPath $codexKok[0].Path)) {
    $codexOturum = @(Get-ChildItem -LiteralPath $codexKok[0].Path -Recurse -Filter 'rollout-*.jsonl' -File -ErrorAction SilentlyContinue |
                     Where-Object { $_.LastWriteTime -gt $sonYedi -and $_.Length -gt 8192 }).Count
}
$codexKullaniliyor = ($codexOturum -gt 0)
# TAZE VAULT ISTISNASI: vault'ta hic gunluk log yoksa beyin daha yeni
# kurulmustur. Codex'in DISKTE oturumu olmasi normaldir (o makinede Codex
# kullaniliyor) ama bu yeni vault'un onlari kacirdigi anlamina GELMEZ -
# henuz hicbir sey kacirmadi. Karsilastirma ancak vault yasadikca anlamli.
$vaultBos = (@(Get-ChildItem -LiteralPath $p.Daylogs -Filter '*.md' -File -ErrorAction SilentlyContinue).Count -eq 0)
$codexOk = if (-not $codexKullaniliyor -or $vaultBos) { $true }
           else { ($codexBlok -gt 0) -or ($codexSe.Count -gt 0) -or $seDamgaOk }

Add-Row 'Codex SessionEnd' $codexOk `
    $(if ($vaultBos) { 'vault yeni (henuz gunluk log yok) - kontrol GECERSIZ' }
      elseif (-not $codexKullaniliyor) { 'bu makinede Codex kullanilmiyor (7 gunde diskte gercek rollout yok) - kontrol GECERSIZ' }
      else { "7 gunde diskte $codexOturum codex oturumu, hafizada $codexBlok codex blogu, session-end tetigi: $($codexSe.Count), son kanit damgasi: $seDamgaNe" }) `
    'Codex oturumlari diskte var ama hicbiri hafizaya girmemis. Sirayla: (1) Codex TUI''de /hooks ac, beyin girdileri Trusted mi bak - Modified/Untrusted ise kanca SESSIZCE atlanir; (2) oturumlari /exit ile kapat, pencere kapatinca SessionEnd atesmez; (3) yine de olmazsa yetim tarayici 72 saat icinde toplar, daha eskisi icin: beyin topla-uygula 7'

# 4) Kuratorlu katman gecikmesi: current-context guncellemesinden beri kac oturum blogu yazildi
$ctxFile = Join-Path $p.Memory 'current-context.md'
$geride = 0
if (Test-Path -LiteralPath $ctxFile) {
    $ctxMt = (Get-Item -LiteralPath $ctxFile).LastWriteTime
    # BLOK zamani sayilir (dosya adi tarihi + blok saati), dosya mtime degil: dosya
    # mtime'i bir blok eklenince tum gunu "sonra" gosteriyordu (olculdu: 65 vs 4).
    foreach ($f in @(Get-ChildItem -LiteralPath $p.Daylogs -Filter '*.md' -File -ErrorAction SilentlyContinue |
                     Where-Object { $_.Name -cmatch '^\d{4}-\d{2}-\d{2}\.md$' -and $_.LastWriteTime -gt $ctxMt })) {
        try {
            foreach ($b in @(Split-BeyinDaylogBlocks -Path $f.FullName)) {
                $bt = $null
                try { $bt = [datetime]::ParseExact(($f.BaseName + ' ' + $b.Saat), 'yyyy-MM-dd H:mm', [cultureinfo]::InvariantCulture) } catch { }
                if ($bt -and $bt -gt $ctxMt) { $geride++ }
            }
        } catch { }
    }
}
Add-Row 'kuratorlu katman' ($geride -le 40) `
    "current-context.md guncellemesinden beri $geride oturum blogu yazildi" `
    '80-memory/current-context.md ve active-threads.md icin ONIZLEME hazirla; 86-compiled kavramlarindan kalici olanlari 40-knowledge altina tasi'

# Kuratorlu metindeki motor surumu ile gercek surum ayni mi? current-context
# her oturumda enjekte edildigi icin bayat surum modele guvenle yanlis cevap
# verdiriyordu.
try {
    $ctxF = Join-Path $p.Memory 'current-context.md'
    if (Test-Path -LiteralPath $ctxF) {
        $ctxC = Get-Content -LiteralPath $ctxF -Raw -Encoding UTF8
        $mv = Get-BeyinVersion -Vault $Vault
        $mm = [regex]::Match($ctxC, '(?i)motoru?\s*\*{0,2}v(\d+\.\d+\.\d+)')
        if ($mm.Success -and $mv) {
            Add-Row 'surum tutarliligi' ($mm.Groups[1].Value -eq $mv) `
                "current-context: v$($mm.Groups[1].Value) · .beyin-version: $mv" `
                'current-context.md icindeki surumu ONIZLEME ile guncelle'
        }
    }
} catch { }

# GIT GECMISI (2026-09-10): calisma agacini temizlemek yetmiyor. yol-temizle
# calistiktan sonra uc gunluk logda 8 mutlak yol HEAD'de duruyordu ve hicbir
# kontrol commit'lere bakmiyordu. Depo su an yerel (uzak yok), yani acil bir
# sizinti degil; ama paylasim/uzak ekleme kararindan ONCE bilinmeli.
try {
    if (Get-Command git -ErrorAction SilentlyContinue) {
        $gecmisYol = @()
        foreach ($f in @($dayFiles + $scanFiles) | Where-Object { $_ }) {
            $rel = $f.FullName.Substring($Vault.Length).TrimStart('\', '/') -replace '\\', '/'
            $head = (& git -C $Vault show ("HEAD:" + $rel) 2>$null | Out-String)
            if ($head -and [regex]::IsMatch($head, $yolRx)) { $gecmisYol += $f.BaseName }
        }
        $gecmisYol = @($gecmisYol | Sort-Object -Unique)
        Add-Row 'git gecmisi (mutlak yol)' ($gecmisYol.Count -eq 0) `
            $(if ($gecmisYol.Count) { "$($gecmisYol.Count) dosyada HEAD icinde tam kullanici yolu var: $(($gecmisYol | Select-Object -First 6) -join ', ')" } else { 'HEAD temiz' }) `
            'depo YEREL kaldigi surece kabul edilebilir; uzak depo/paylasim dusunuluyorsa once git-filter-repo ile gecmisi temizle veya bu kabulu ADR olarak yaz'
    }
} catch { }

# ============================================================================
# VAULT DOSYA IZINLERI (ACL)  -  2026-09-11
# ----------------------------------------------------------------------------
# Bu kontrol brain-cli'de vardi ama bu makinede 'Windows ACL inspection failed'
# donuyordu. O basarisizlik "denetim GECMEDI" demekti, "guvenli" demek degil -
# ama pratikte kimse ayrimi yapmiyordu. Yerelde Get-Acl sorunsuz calisiyor,
# yani sorun vault'ta degil aractaki cagirmada.
#
# Bir guvenlik kontrolunun dis bir araca bagli olup o arac bozuldugunda
# SESSIZCE kaybolmasi kabul edilemez. Doktor kendi bakar.
try {
    $acl = Get-Acl -LiteralPath $Vault -ErrorAction Stop
    $genisGruplar = @('Everyone', 'Authenticated Users', 'BUILTIN\Users', 'INTERACTIVE', 'Herkes')
    $mirasVar = @($acl.Access | Where-Object { $_.IsInherited }).Count -gt 0
    $riskli = New-Object System.Collections.Generic.List[string]
    $okuyan = New-Object System.Collections.Generic.List[string]

    foreach ($r in $acl.Access) {
        if ($r.AccessControlType -ne 'Allow') { continue }
        $kim = [string]$r.IdentityReference
        $genis = $false
        foreach ($g in $genisGruplar) { if ($kim -like "*$g*") { $genis = $true; break } }
        if (-not $genis) { continue }
        # Yazma iceren herhangi bir hak
        if ([string]$r.FileSystemRights -match 'Write|Modify|FullControl|Delete|ChangePermissions|TakeOwnership') {
            $riskli.Add("$kim ($($r.FileSystemRights))")
        } else {
            $okuyan.Add($kim)
        }
    }

    # MIRAS: kirilmamissa profil izinleri buraya akar. Kirilmis olmasi IYIDIR.
    $detay = "sahip: $($acl.Owner) · $($acl.Access.Count) kural · miras $(if ($mirasVar) { 'ACIK' } else { 'kirilmis (iyi)' })"
    if ($riskli.Count) { $detay += " · GENIS GRUBA YAZMA: $($riskli -join ', ')" }
    elseif ($okuyan.Count) { $detay += " · genis gruba salt-okuma: $(($okuyan | Sort-Object -Unique) -join ', ')" }

    Add-Row 'vault dosya izinleri' ($riskli.Count -eq 0) $detay `
        'Genis bir gruba (Everyone / Authenticated Users / Users) YAZMA hakki verilmis. Vault kisisel notlar, musteri adlari ve proje detaylari tasiyor. Bu genelde vault SURUCU KOKU altindayken (D:\Beyin gibi) mirasla gelir; kullanici profili altinda olmaz. Motorun desteklenen yolu: beyin kur -IzinleriSikilastir  ·  elle: icacls "<vault>" /inheritance:r /grant:r "%USERNAME%:(OI)(CI)F" "SYSTEM:(OI)(CI)F" "Administrators:(OI)(CI)F"'
} catch {
    Add-Row 'vault dosya izinleri' $false "ACL okunamadi: $($_.Exception.Message)" `
        'Get-Acl basarisiz. Yol erisilebilir mi, surucu NTFS mi kontrol et.'
}

# ============================================================================
# AJAN ESLIGI  (2026-09-15, Faz 0)
# ----------------------------------------------------------------------------
# Beyin iki ajanin ortak mali. Bu satir "tek tarafli bir sey kaldi mi" sorusunu
# her kosuda sorar: sozlesme dosyalari ayristi mi, kanca ayarlari ayni motoru
# mu bagliyor, ozetleyicinin yedegi var mi.
try {
    $eslikSorun = New-Object System.Collections.Generic.List[string]
    $eslikDetay = New-Object System.Collections.Generic.List[string]

    # (a) CLAUDE.md ile AGENTS.md ayni isletim protokolunu mu tasiyor
    #     AGENTS.md Ingilizce, CLAUDE.md Turkce -> metin hash'i degil, ORTAK
    #     KURAL BASLIKLARI karsilastirilir: her ikisinde de gecmesi gereken
    #     anahtar kavramlar.
    # 2.4 KOMUTLARI EKLENDI (2026-09-17, olculdu): liste yalniz yedi kavram
    # tasiyordu ve AGENTS.md'de 'ayar' ile 'guncelle' HIC gecmedigi halde satir
    # "sozlesme: esit" diyordu. Yani bir surumle eklenen her yeni komut tek
    # sozlesmeye yazilip digerine yazilmadiginda sessizce ayrisabiliyordu -
    # Codex tarafindaki kullanici o komuttan hic haberdar olmuyordu.
    # ELLE BAKIMLI LISTE YINE BAYATLADI (2026-09-18 denetimi): yukaridaki
    # "ADI BURAYA DA yazilmali" kurali yazilmasina ragmen dokuz komut kacmisti
    # (yedek, canli, makbuz, copcu, gom, zamanla, bahcivan, niyet, ice-aktar).
    # Yani denetleyicinin kendisi, denetledigi surukLenmenin aynisina ugramisti.
    #
    # COZUM: komut adlari DAGITICIDAN turetilir. Bakim yuku tersine doner -
    # yeni komut eklendiginde ya iki sozlesmeye de yazarsin ya MUAF sayarsin;
    # sessizce kacamaz.
    $sabitKavram = @('preview', '85-daylogs', '86-compiled', '80-memory', 'BEYIN_VAULT', '/exit', 'beyin.ps1', 'KILAVUZ.md')

    # MUAF: sozlesme dosyalarinda gecmesi GEREKMEYEN komutlar. Ya kullaniciya
    # degil motora ait (zamanli, kur, kaldir), ya tek seferlik gocler
    # (isaret-goc, sema-goc, yol-temizle), ya da tani/yardim (nerede, yardim).
    $sozlesmeMuaf = @('yardim', 'nerede', 'kur', 'kaldir', 'zamanli', 'isaret-goc', 'sema-goc',
                      'yol-temizle', 'durum', 'doktor', 'derin', 'derle', 'topla', 'arsivle', 'yayinla')

    $komutKavram = New-Object System.Collections.Generic.List[string]
    try {
        # Dagiticinin KURULU kopyasi esastir (gorevleri de o calistirir); yoksa
        # depodaki. Rota bicimleri: "{ $_ -in @('a', 'b') } {" ve "'ad' {".
        $dspY = Join-Path $env:USERPROFILE '.beyin\beyin.ps1'
        if (-not (Test-Path -LiteralPath $dspY)) { $dspY = Join-Path $Vault 'kurulum\beyin.ps1' }
        if (Test-Path -LiteralPath $dspY) {
            $dspHam = Get-Content -LiteralPath $dspY -Raw -Encoding UTF8
            $adlar = New-Object System.Collections.Generic.List[string]
            # YALNIZ KANONIK AD: cogul rotada ilk ad esastir. Takma adlar
            # ('status', 'backup', 'archive') sozlesmeye yazilmak zorunda degil;
            # hepsini aramak satiri gurultuye bogar ve kimse bakmaz.
            foreach ($m in [regex]::Matches($dspHam, '(?m)^\s*\{\s*\$_\s+-in\s+@\(([^)]*)\)\s*\}\s*\{')) {
                $ilk = [regex]::Match($m.Groups[1].Value, "'([^']+)'")
                if ($ilk.Success) { $adlar.Add($ilk.Groups[1].Value) }
            }
            foreach ($m in [regex]::Matches($dspHam, '(?m)^\s*''([a-z][a-z0-9-]*)''\s*\{')) { $adlar.Add($m.Groups[1].Value) }
            foreach ($a in (@($adlar) | Sort-Object -Unique)) {
                if ($sozlesmeMuaf -contains $a) { continue }
                # '-uygula' / '-zorla' varyantlari: temel komut zaten arandigi
                # icin ayrica yazilmalari gerekmez.
                if ($a -like '*-uygula' -or $a -like '*-zorla') { continue }
                $komutKavram.Add("beyin $a")
            }
        }
    } catch { }
    # Turetim hicbir sey vermediyse (dagitici okunamadi) ESKI listeye duseriz:
    # kontrolun kendisi sessizce bosalmasin.
    if ($komutKavram.Count -eq 0) {
        foreach ($a in @('ayar', 'guncelle', 'al', 'denetle', 'bagla')) { $komutKavram.Add("beyin $a") }
    }
    $ortakKavram = @($sabitKavram) + @($komutKavram.ToArray())
    $cl = if (Test-Path -LiteralPath (Join-Path $Vault 'CLAUDE.md')) { Get-Content -LiteralPath (Join-Path $Vault 'CLAUDE.md') -Raw -Encoding UTF8 } else { '' }
    $ag = if (Test-Path -LiteralPath (Join-Path $Vault 'AGENTS.md')) { Get-Content -LiteralPath (Join-Path $Vault 'AGENTS.md') -Raw -Encoding UTF8 } else { '' }
    # BELGELEME BICIMI SERBEST (2026-09-18, olculdu): sozlesmeler komutlari
    # cogunlukla backtick ile yaziyor (`canli`, `makbuz`) - 'beyin canli' tam
    # dizgesini aramak ALTI komutta yanlis pozitif uretti. Onemli olan komutun
    # BELGELENMIS olmasi, hangi bicimde yazildigi degil.
    function Test-KavramGecer([string]$Metin, [string]$Kavram) {
        if ($Metin -match [regex]::Escape($Kavram)) { return $true }
        if ($Kavram -like 'beyin *') {
            $ad = $Kavram.Substring(6)
            # Backtick'li ya da kod blogunda gecen ciplak komut adi da sayilir.
            if ($Metin -match ('`' + [regex]::Escape($ad) + '[` ]')) { return $true }
        }
        return $false
    }
    $eksikCl = @($ortakKavram | Where-Object { -not (Test-KavramGecer $cl $_) })
    $eksikAg = @($ortakKavram | Where-Object { -not (Test-KavramGecer $ag $_) })
    if ($eksikCl.Count) { $eslikSorun.Add("CLAUDE.md eksik: $($eksikCl -join ',')") }
    if ($eksikAg.Count) { $eslikSorun.Add("AGENTS.md eksik: $($eksikAg -join ',')") }
    $eslikDetay.Add("sozlesme: $(if ($eksikCl.Count + $eksikAg.Count -eq 0) { 'esit' } else { 'AYRISTI' }) ($(@($ortakKavram).Count) kavram, $($komutKavram.Count) komut turetildi)")

    # (b) kanca ayarlari: iki ajan da 4 olayi bagliyor mu, dogru launcher'a mi
    $gercekL = Join-Path $env:USERPROFILE '.beyin\beyin-launcher.ps1'
    $simL    = Join-Path $env:USERPROFILE '.claude\hooks\beyin-launcher.ps1'
    function Say-Kanca([string]$Yol) {
        $n = 0; $hedef = ''
        try {
            $d = Get-Content -LiteralPath $Yol -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($ev in @('SessionStart','UserPromptSubmit','SessionEnd','PreCompact')) {
                if (-not $d.hooks.PSObject.Properties[$ev]) { continue }
                foreach ($g in @($d.hooks.$ev)) { foreach ($h in @($g.hooks)) {
                    if ($h.command -like '*beyin-launcher*') { $n++; if (-not $hedef) { $hedef = $h.command } } } }
            }
        } catch { }
        return @{ N = $n; Hedef = $hedef }
    }
    $clK = Say-Kanca (Join-Path $env:USERPROFILE '.claude\settings.json')
    $cxK = Say-Kanca (Join-Path $env:USERPROFILE '.codex\hooks.json')
    # KURULU OLMAYAN AJAN ICIN KANCA BEKLENMEZ (2026-09-18).
    # Eskiden yalniz-Claude bir makinede 'Codex 0/4 kanca' KALICI kirmizi
    # veriyordu. 'Codex SessionEnd' satirinda bu muafiyet zaten vardi
    # ('bu makinede Codex kullanilmiyor -> kontrol GECERSIZ'), 'ajan esligi'de
    # yoktu. 1-3 arasi YINE kirmizi: o gercek bir YARIM kurulumdur.
    $clVarE = [bool](Get-BeyinClaudeExe)
    $cxVarE = [bool](Get-Command codex -ErrorAction SilentlyContinue)
    if ($clK.N -ne 4 -and -not ($clK.N -eq 0 -and -not $clVarE)) { $eslikSorun.Add("Claude $($clK.N)/4 kanca") }
    if ($cxK.N -ne 4 -and -not ($cxK.N -eq 0 -and -not $cxVarE)) { $eslikSorun.Add("Codex $($cxK.N)/4 kanca") }
    $clYol = if ($clK.Hedef -like "*$([IO.Path]::GetFileName((Split-Path $gercekL -Parent)))\beyin-launcher*") { 'gercek' } elseif ($clK.Hedef) { 'sim' } else { '-' }
    $cxYol = if ($cxK.Hedef -like '*.claude\hooks\beyin-launcher*') { 'sim' } elseif ($cxK.Hedef) { 'gercek' } else { '-' }
    $eslikDetay.Add("claude: $($clK.N) kanca ($clYol) · codex: $($cxK.N) kanca ($cxYol, hash korunuyor)")
    if (-not (Test-Path -LiteralPath $gercekL)) { $eslikSorun.Add('gercek launcher yok (~\.beyin)') }
    if (-not (Test-Path -LiteralPath $simL))    { $eslikSorun.Add('Codex simi yok (~\.claude\hooks)') }

    # (c) ozetleyici: hangi arka uc, yedegi var mi
    $claudeVar = [bool](Get-BeyinClaudeExe)
    $codexVar  = [bool](Get-Command codex -ErrorAction SilentlyContinue)
    # NOT: '$ozet' KULLANILAMAZ - betigin [switch]$Ozet parametresiyle cakisir.
    $ozetDurum = if ($claudeVar -and $codexVar) { 'claude (yedek: codex)' } elseif ($claudeVar) { 'claude (YEDEK YOK)' } elseif ($codexVar) { 'codex (YEDEK YOK)' } else { 'HICBIRI' }
    if (-not $claudeVar -and -not $codexVar) { $eslikSorun.Add('ozetleyici yok') }
    $eslikDetay.Add("ozetleyici: $ozetDurum")

    Add-Row 'ajan esligi' ($eslikSorun.Count -eq 0) `
        (($eslikDetay -join ' · ') + $(if ($eslikSorun.Count) { " · SORUN: $($eslikSorun -join '; ')" } else { '' })) `
        'Iki ajan ayni motoru esit kullanmali. Sozlesme ayristiysa CLAUDE.md ve AGENTS.md isletim protokolunu esitle; kanca eksikse kur.ps1; launcher/sim yoksa kur.ps1.'
} catch { }

# ============================================================================
# CODEX KILL-SWITCH  (2026-09-10, bagimsiz denetim)
# ----------------------------------------------------------------------------
# Codex'in kanca motoru ~/.codex/config.toml icinde [features] altindaki
# 'hooks' bayragiyla acilip kapaniyor. Bu bayrak bu deponun KENDI belgelerinde
# kill-switch olarak geciyor (AGENTS.md, beyin-doktor skill'i).
#
# Varsayilani TRUE - olculdu: bos bir CODEX_HOME ile 'codex features list'
# ciktisinda hooks 'stable/true'. Yani kurulumun bu dosyaya YAZMASI gerekmez
# ve yazmamali: config.toml 26 KB'lik, beyinle ilgisiz onlarca blok iceren bir
# kullanici dosyasi; ona dokunmak gereksiz risk.
#
# Ama bayrak ACIKCA false yapilmissa Codex kancalari hic calismaz ve bunu
# hicbir kontrol gormuyordu. Kullanicinin kendi kapattigi bir anahtar,
# unutuldugunda sessiz bir arizaya donusur. Bu satirin isi YAZMAK degil,
# GORMEK.
try {
    $codexCfg = Join-Path $env:USERPROFILE '.codex\config.toml'
    if ($env:CODEX_HOME) { $codexCfg = Join-Path $env:CODEX_HOME 'config.toml' }
    if (Test-Path -LiteralPath $codexCfg) {
        $cfg = Get-Content -LiteralPath $codexCfg -Raw -Encoding UTF8
        # [features] blogunu ayikla (bir sonraki [baslik] veya dosya sonuna dek)
        $fm = [regex]::Match($cfg, '(?ms)^\[features\][^\S\r\n]*\r?\n(.*?)(?=^\[|\Z)')
        $hooksAcik = $true          # varsayilan
        $hooksYazili = $false
        $memAcik = $false
        if ($fm.Success) {
            $hm = [regex]::Match($fm.Groups[1].Value, '(?m)^\s*hooks\s*=\s*(true|false)')
            if ($hm.Success) { $hooksYazili = $true; $hooksAcik = ($hm.Groups[1].Value -eq 'true') }
            $mm = [regex]::Match($fm.Groups[1].Value, '(?m)^\s*memories\s*=\s*(true|false)')
            if ($mm.Success) { $memAcik = ($mm.Groups[1].Value -eq 'true') }
        }
        Add-Row 'Codex kanca anahtari' $hooksAcik `
            "[features] hooks = $(if ($hooksYazili) { $(if ($hooksAcik) { 'true' } else { 'FALSE' }) } else { '(yazili degil - varsayilan true)' })$(if ($memAcik) { ' · DIKKAT: memories = true, Codex kendi hafizasini da tutuyor' })" `
            'Codex kanca motoru KAPALI: ~/.codex/config.toml icinde [features] altina hooks = true yaz, sonra Codex TUI''de /hooks ile beyin girdilerini onayla. Bu dosyaya kurulum betigi DOKUNMAZ - senin yapilandirmandir.'
    }
} catch { }

# ============================================================================
# GERI GETIRME (okuma yolu)  -  2026-09-10, bagimsiz denetim
# ----------------------------------------------------------------------------
# Doktor bugune kadar YALNIZ YAZMA YOLUNU olcuyordu: kac oturum ozetlendi, kac
# kavram uretildi, kuyruk ne durumda. Ama bir hafiza sisteminin asil iddiasi
# okuma yolundadir - dogru sey, dogru anda geri geliyor mu?
#
# Bu olculmedigi surece sessiz bir bicimde bozulabilir: indeks bayatlar, esik
# yanlis ayarlanir, kavramlar ikizlenir. Hicbiri hata vermez; sadece hafiza
# ise yaramaz hale gelir.
# ============================================================================
try {
    $conceptDir = Join-Path $p.Compiled 'concepts'
    $kavramlar = @(Get-ChildItem -LiteralPath $conceptDir -Filter '*.md' -File -ErrorAction SilentlyContinue)

    # 1) Indeks tazeligi ve kurulabilirligi
    $idx = @(Get-BeyinConceptIndex -Paths $p)
    # NEDEN (2026-09-16 denetim): onbellek dosyasi lib.ps1 Get-BeyinConceptIndex'te
    # 'kavram-indeks.dat' (uzanti .json DEGIL); eski metin var olmayan bir .json'a
    # yonlendiriyordu, kullanici bayat .dat dururken 'onbellek zaten yok' sanirdi.
    Add-Row 'geri getirme indeksi' ($kavramlar.Count -eq 0 -or $idx.Count -eq $kavramlar.Count) `
        "$($idx.Count) kavram indekslendi / diskte $($kavramlar.Count)" `
        'Indeks eksik: 86-compiled/concepts altinda okunamayan not olabilir. Onbellek: motor\scripts\.state\kavram-indeks.dat (silinirse yeniden kurulur).'

    # 2) IKIZ KAVRAM. Ayni ders iki dosyada durursa geri getirme ikisini birden
    #    basar; baglam iki katina cikar, bilgi artmaz. Es zamanli derleyici
    #    hatasi 2026-09-10'da tam olarak bunu uretmisti (tek slot ile kapatildi).
    $slugGrup = @{}
    foreach ($f in $kavramlar) {
        $n = ([IO.Path]::GetFileNameWithoutExtension($f.Name)).ToLowerInvariant() -replace '[^a-z0-9]', ''
        if (-not $slugGrup.ContainsKey($n)) { $slugGrup[$n] = New-Object System.Collections.Generic.List[string] }
        $slugGrup[$n].Add($f.Name)
    }
    $ikiz = @($slugGrup.Keys | Where-Object { $slugGrup[$_].Count -gt 1 })
    Add-Row 'ikiz kavram' ($ikiz.Count -eq 0) `
        $(if ($ikiz.Count) { "$($ikiz.Count) grup: $((($ikiz | Select-Object -First 3) | ForEach-Object { $slugGrup[$_] -join ' ~ ' }) -join ' | ')" } else { "$($kavramlar.Count) kavram, tipografik ikiz yok" }) `
        'Ayni dersin iki kopyasi: icerigi zengin olani birak, digerini sil ve 86-compiled/index.md satirini da kaldir. Yeni ikizleri compile.ps1 slug tekillestirmesi engelliyor.'

    # 3) OLU BILGI: hicbir yerden baglanti almayan ve indekste olmayan kavram.
    #    Boyle bir not ne gezinerek ne aramayla bulunur - uretilmis ama
    #    erisilemez bilgidir.
    $idxDosya = Join-Path $p.Compiled 'index.md'
    $idxMetin = ''
    if (Test-Path -LiteralPath $idxDosya) { $idxMetin = Get-Content -LiteralPath $idxDosya -Raw -Encoding UTF8 }
    $olu = @()
    foreach ($f in $kavramlar) {
        $slug = [IO.Path]::GetFileNameWithoutExtension($f.Name)
        if ($idxMetin -and $idxMetin.Contains($slug)) { continue }
        $olu += $f.Name
    }
    Add-Row 'indekste olmayan kavram' ($olu.Count -eq 0) `
        $(if ($olu.Count) { "$($olu.Count) not index.md'de yok: $(($olu | Select-Object -First 4) -join ', ')" } else { 'tum kavramlar indekste' }) `
        'index.md kavram katalogudur; orada olmayan not oturum acilisinda da gorunmez. Cozum: beyin derle (index.md oku-birlestir-yaz ile guncellenir).'
} catch { }

# ============================================================================
# CAPRAZ BAGLANTI  (2.3, 2026-09-17; dedektor ayni gun denetimde DEGISTIRILDI)
# ----------------------------------------------------------------------------
# OLCUM: 132 kavram notunun 91'i 86-compiled/index.md DISINDA hicbir yerden
# gelen baglanti almiyordu. Bir wiki'nin degeri notlarin sayisinda degil
# aralarindaki kenarlarda; kenarsiz notlar Obsidian grafinde dagilmis
# noktalardir ve gezinerek hicbiri bulunmaz. bagla.ps1 her nota gomme
# benzerligiyle secilmis "## Ilgili notlar" bolumu dokuyor.
#
# ILK DEDEKTOR YANLISTI ve iki yonden birden yanlisti:
#   - KIRMIZI OLAMIYORDU: "kapsam ucte birin altinda" olarak olcuyordu, ama
#     bagla bir bolumu yalniz komsu esigin altina duserse kaldirir. Gorevin
#     durmasi (03:15 hic kosmamasi) diskteki 132 bolumu OLDUGU GIBI birakir -
#     kapsam %100, satir sonsuza dek YESIL. Tam kacirmasi gereken sey buydu.
#   - BOSUNA KIRMIZI OLABILIYORDU: tek bir 'beyin bagla-uygula -MinCos 0.9'
#     kosusu bolumlerin cogunu MESRU sekilde kaldirir (olculdu: 132 not yazildi,
#     0 bolum kaldi) ve satiri gece varsayilan kosu geri getirene kadar kirmizi
#     tutardi.
# ARTIK TAZELIK OLCULUR, VARLIK DEGIL: en yeni basarili bagla makbuzu
# (BAGLA_OK) ile bagla'nin PESINDEN kosmasi gereken en yeni olay - kavram
# notlarinin ve vektor indeksinin en yeni yazma zamani - karsilastirilir.
# bagla o olaydan 2 GUNDEN fazla geride kaldiysa SORUN. Kapsam yuzdesi ayrinti
# metninde durur (tani icin degerli), tek basina karar vermez.
# Vektor indeksi yoksa ozellik zaten calisamaz -> YESIL (yoklugu hata degil).
# ============================================================================
try {
    $cbDir = Join-Path $p.Compiled 'concepts'
    $cbDosya = @(Get-ChildItem -LiteralPath $cbDir -Filter '*.md' -File -ErrorAction SilentlyContinue)
    if ($cbDosya.Count -eq 0) {
        Add-Row 'capraz baglanti' $true 'kavram notu yok' 'Once kavram uret: beyin derle'
    } else {
        $cbVar = 0
        $cbRef = $null
        foreach ($f in $cbDosya) {
            if ($null -eq $cbRef -or $f.LastWriteTime -gt $cbRef) { $cbRef = $f.LastWriteTime }
            $cbTxt = ''
            try { $cbTxt = [IO.File]::ReadAllText($f.FullName) } catch { continue }
            # Kultur-bagimsiz ve bes betikte ORTAK desen (lib.ps1): baslik bastaki
            # NOKTALI I ile yazilabilir, kultur-duyarli/ASCII-only bir eslesme onu
            # sessizce kacirir (bkz. Test-BeyinMatch).
            if (Test-BeyinMatch -Text $cbTxt -Pattern $script:BeyinIlgiliBaslikRx -Multiline) { $cbVar++ }
        }
        $cbYok = $cbDosya.Count - $cbVar
        $cbOran = $cbVar / [double]$cbDosya.Count
        $cbYuzde = [int][math]::Round($cbOran * 100)
        $cbVektor = Test-BeyinVectorReady -Paths $p
        # gom'un indeksi de referanstir: gece gom kosup bagla kosmuyorsa satir
        # notlar hic degismese bile bunu gorur.
        try {
            $cbDat = (Get-Item -LiteralPath (Join-Path $p.ScrState 'kavram-vektor.dat') -ErrorAction Stop).LastWriteTime
            if ($null -eq $cbRef -or $cbDat -gt $cbRef) { $cbRef = $cbDat }
        } catch { }
        $cbSon = $null
        foreach ($mk in @(Read-BeyinMakbuz -Paths $p -Gun 90 | Where-Object { $_.script -eq 'bagla' -and $_.outcome -eq 'BAGLA_OK' })) {
            try {
                $mkT = [datetime]::Parse([string]$mk.ts, [Globalization.CultureInfo]::InvariantCulture)
                if ($null -eq $cbSon -or $mkT -gt $cbSon) { $cbSon = $mkT }
            } catch { }
        }
        $cbKostu = ($null -ne $cbSon)
        # Makbuz penceresi 90 gun. Bolumler diskte ama pencerede TEK BIR basarili
        # kosu yoksa "en iyi ihtimalle 90 gun once kostu" kabul edilir - boylece
        # pencereden dusen bir olum satiri sessizce yesile cevirmez.
        $cbOlcum = $cbSon
        if (-not $cbKostu -and $cbVar -gt 0) { $cbOlcum = (Get-Date).AddDays(-90) }
        $cbGecikme = $null
        if ($cbOlcum -and $cbRef) { $cbGecikme = [math]::Round(($cbRef - $cbOlcum).TotalDays, 1) }
        $cbOk = $true
        if ($cbVektor -and $null -ne $cbGecikme -and $cbGecikme -gt 2.0) { $cbOk = $false }
        $cbDetay = "$cbVar/$($cbDosya.Count) not '## Ilgili notlar' tasiyor (%$cbYuzde)"
        if ($cbYok -gt 0) { $cbDetay += " · $cbYok not baglantisiz" }
        if (-not $cbVektor) { $cbDetay += ' · vektor indeksi yok, ozellik beklemede (beyin gom)' }
        elseif (-not $cbKostu -and $cbVar -eq 0) { $cbDetay += ' · bagla henuz hic yazmadi (yalniz kuru kosu)' }
        elseif (-not $cbKostu) { $cbDetay += ' · 90 gunluk makbuzda TEK bir basarili bagla kosusu yok' }
        else {
            $cbYas = [math]::Round(((Get-Date) - $cbSon).TotalDays, 1)
            $cbDetay += " · son yazim $cbYas gun once"
            if ($null -ne $cbGecikme -and $cbGecikme -gt 2.0) { $cbDetay += ", notlar/indeks ondan $cbGecikme gun daha YENI (gece gorevi kosmuyor)" }
        }
        Add-Row 'capraz baglanti' $cbOk $cbDetay `
            'bagla, kavram notlarinin gerisinde kaldi: elle bir kez kosturup (beyin bagla-uygula) gece gorevini kontrol et (kurulum\zamanla.ps1 -Liste; beyin-bagla 03:15). Gorev kirmizi donuyorsa engine.log [zamanlayici] satirlarina bak; vektor indeksi eskiyse once beyin gom. Kapsam dusukse esik dar olabilir: beyin bagla -MinCos 0.50'
    }
} catch { }

# ============================================================================
# NOT GUNCELLIGI  (2.3, 2026-09-17; dedektor ayni gun denetimde DEGISTIRILDI)
# ----------------------------------------------------------------------------
# OLCUM: 2.3'ten once yazilmis 128 kavram notunun HICBIRI olusturulduktan sonra
# guncellenmemisti. compile.ps1 var olan bir kavram hakkinda YENI bilgi gorunce
# onu "kopya kavram atlandi" deyip atiyordu; beyin ilk gun ne ogrendiyse orada
# kaliyordu ve bunu hicbir kontrol soylemiyordu.
#
# 2.3 guncelleme yolunu ekledi: model <<<GUNCELLE: slug.md>>> blogu verir, motor
# bunu mevcut govdeye tarihli "## Guncelleme <gun>" bolumu olarak EKLER (eski
# govde yeniden yazilmaz; kisalma kapisi ayrica korur).
#
# BU SATIRIN ILK SURUMU OLU BIR DEDEKTORDU (denetim 2026-09-17). Kanit olarak
# frontmatter'daki "created != updated" farkini sayiyordu. O fark 2.3 kaniti
# DEGIL, bir SEMA GOCU izidir: sema-goc.ps1 gecerli 'updated' alani olmayan nota
# o anin damgasini basar ve 2026-08-27'de tam 3 nota basmisti
# (beyin-motoru-bolge-ayrimi, comfyui-portable-kurulum,
# minimax-music-3-caption-tarifi). Sonuc: sayac her zaman 3, satir KALICI YESIL -
# hic guncelleme uretmeyen yuz derleme bile onu kirmiziya cevirmezdi, yani tam da
# yakalamak icin yazildigi arizaya kordu. Ustelik o uc not compile.ps1'in yapisal
# kapisinin (sablon disi 'generated_by' alani) REDDETTIGI notlar; sayi hicbir
# zaman dusemezdi de. Detay metni daha da kotuydu: okuyan "3 guncellenmis" gorup
# yolun calistigini saniyordu, oysa diskte 0 '## Guncelleme' bolumu vardi.
#
# ARTIK OLCULEN SEY DOGRUDAN SINYALDIR - compile.ps1'in uygulama katmaninin
# engine.log'a yazdigi satirlar:
#   uygulandi  : 'compile: kavram notu guncellendi:'          -> guncelleme INDI
#   reddedildi : hedef yok / gecersiz ad / cok kisa / tavan /
#                'guncelleme uygulanmadi, mevcut not korundu' -> kapida dondu
#   atlandi    : 'guncelleme atlandi, mevcut not korundu:'    -> IDEMPOTENT,
#                SAGLIKLI sonuc (malzeme zaten notta), ret SAYILMAZ
# SORUN yalnizca iki durumda cikar:
#   (a) DOGRUDAN: blok uretildi, en az biri REDDEDILDI ve hicbiri inmedi.
#   (b) SEZGISEL: 2.3'ten beri 10 modelli derleme kostu ve model bir tek blok
#       bile uretmedi (prompt tarafi olmus olabilir). Esik bilerek YUKSEK: ardi
#       ardina birkac gecenin yalnizca YENI kavram uretmesi mesru bir sonuctur,
#       bozuk bir yol degil. Bu kapi ACIKCA SEZGISELDIR, Duzeltme metninde yazar.
# "Kalici kirmizi olmaz": diskteki tek bir '## Guncelleme' bolumu ya da tek bir
# basarili 'kavram notu guncellendi' satiri satiri kalici yesile dondurur.
#
# 2.3 NE ZAMAN INDI: motor\scripts\.state\surum-inis.json (makine-sahipli, BIR
# KEZ yazilir). .beyin-version'un mtime'i bu is icin YANLISTI: kur.ps1 her yeni
# surumde, 'beyin yayinla', git checkout/stash ve duz klasor kopyasi hepsi o
# damgayi tazeliyor ve sayaci sifirliyordu. State dosyasi yoksa ve yazilamazsa
# mtime'a duser - yanlis alarm vermektense susar.
# ============================================================================
try {
    $ngInv = [Globalization.CultureInfo]::InvariantCulture

    # ---- Surum kapisi --------------------------------------------------------
    $ngSurum = [string](Get-BeyinVersion -Vault $Vault)
    $ngSurumOk = $false
    $ngSm = [regex]::Match($ngSurum, '^(\d+)\.(\d+)')
    if ($ngSm.Success) { $ngSurumOk = ((([int]$ngSm.Groups[1].Value) * 100) + ([int]$ngSm.Groups[2].Value)) -ge 203 }

    # ---- INIS ANI: makine-sahipli damga, TEK yazim ---------------------------
    $ngInis = $null
    $ngInisKaynak = ''
    $ngInisDosya = Join-Path $p.ScrState 'surum-inis.json'
    try {
        if (Test-Path -LiteralPath $ngInisDosya) {
            $ngJs = ConvertFrom-Json (Get-Content -LiteralPath $ngInisDosya -Raw -Encoding UTF8)
            if ($ngJs -and $ngJs.ts) { $ngInis = [datetime]::Parse([string]$ngJs.ts, $ngInv); $ngInisKaynak = 'damga' }
        }
    } catch { $ngInis = $null }
    if ($ngSurumOk -and -not $ngInis) {
        # 2.3'u goren ILK doktor kosusu ani BIR KEZ yazar. Doktorun tek yazma
        # islemi budur ve makine bolgesindedir (motor\scripts\.state); kuratorlu
        # alana dokunmaz, var olan damgayi da hicbir zaman ezmez.
        try {
            New-Item -ItemType Directory -Force -Path $p.ScrState -ErrorAction SilentlyContinue | Out-Null
            $ngIso = Get-BeyinIsoNow
            Write-BeyinText -Path $ngInisDosya -Text ('{"surum":"' + $ngSurum + '","ts":"' + $ngIso + '"}')
            $ngInis = [datetime]::Parse($ngIso, $ngInv); $ngInisKaynak = 'damga-yeni'
        } catch { }
        if (-not $ngInis) {
            try {
                $ngSurumDosya = Join-Path $Vault '.beyin-version'
                if (Test-Path -LiteralPath $ngSurumDosya) {
                    $ngInis = (Get-Item -LiteralPath $ngSurumDosya -ErrorAction SilentlyContinue).LastWriteTime
                    $ngInisKaynak = 'mtime'
                }
            } catch { }
        }
    }

    # ---- DISKTEKI KANIT: '## Guncelleme' bolumleri ---------------------------
    $ngNotlar = @(Get-ChildItem -LiteralPath (Join-Path $p.Compiled 'concepts') -Filter '*.md' -File -ErrorAction SilentlyContinue)
    $ngBolum     = 0   # toplam "## Guncelleme" bolumu - 2.3'e OZGU tek disk kaniti
    $ngEskiDamga = 0   # created != updated ama INIS'ten ONCE: sema gocu izi
    $ngYeniDamga = 0   # created != updated ve INIS'ten SONRA: gercek 2.3 guncellemesi
    foreach ($ngF in $ngNotlar) {
        $ngNot = Split-BeyinNote -Path $ngF.FullName
        if (-not $ngNot.Ok) { continue }
        $ngCreated = [string]$ngNot.Fields['created']
        $ngUpdated = ''
        $ngM = [regex]::Match([string]$ngNot.Fm, '(?m)^updated:\s*"?([^"\r\n]*)"?\s*$')
        if ($ngM.Success) { $ngUpdated = $ngM.Groups[1].Value.Trim() }
        if ($ngCreated -and $ngUpdated -and $ngUpdated -ne $ngCreated) {
            # Tarih ayristirmasi InvariantCulture: makine kulturu tr-TR.
            # INIS'ten ONCEKI damga sema gocudur; 2.3 kaniti SAYILMAZ.
            try {
                $ngTc = [datetime]::Parse($ngCreated, $ngInv)
                $ngTu = [datetime]::Parse($ngUpdated, $ngInv)
                if (($ngTu - $ngTc).TotalSeconds -gt 1) {
                    if ((-not $ngInis) -or ($ngTu -lt $ngInis)) { $ngEskiDamga++ } else { $ngYeniDamga++ }
                }
            } catch { $ngEskiDamga++ }
        }
        # Baslik sayimi BILEREK buyuk/kucuk harf DUYARLI: motor bolumu her zaman
        # "## Guncelleme <gun>" yazar ve duyarsiz eslesme tr-TR'de ayri bir tuzaktir
        # (bkz. 'kultur-bagimsiz regex' satiri).
        $ngBolum += @([regex]::Matches([string]$ngNot.Body, '(?m)^##[ \t]+Guncelleme\b')).Count
    }

    # ---- DOGRUDAN SINYAL: engine.log uygulama katmani ------------------------
    # $engAll yukarida BIR KEZ yuklendi (engine.log + dondurulmus engine.1.log),
    # yani pencere log donmesi kadardir; detay metni sayilari "2.3'ten beri" diye
    # verir, "her zaman" demez.
    # Desenler compile.ps1'in yazdigi satirlarin birebir basidir ve HARF DUYARLI
    # eslesir: tr-TR'de duyarsiz eslesme 'I' harfinde sessizce bozulur.
    # 'guncelleme malzemesi tavanda kirpildi' BASARILI bir guncellemenin satiridir
    # ve ret desenine GIRMEZ ('guncelleme tavani (' ondan farklidir).
    $ngUygulandi = 0
    $ngRet       = 0
    $ngAtlandi   = 0
    $ngUygRx = [regex]::new('compile: kavram notu guncellendi:')
    $ngRetRx = [regex]::new('compile: (?:GUNCELLE hedefi yok|gecersiz GUNCELLE adi|GUNCELLE blogu cok kisa|guncelleme tavani \(|guncelleme uygulanmadi, mevcut not korundu)')
    $ngAtlRx = [regex]::new('compile: guncelleme atlandi, mevcut not korundu:')
    if ($ngSurumOk -and $ngInis) {
        foreach ($ngL in @($engAll)) {
            if (-not $ngL -or $ngL.Length -lt 19) { continue }
            $ngTs = $null
            try { $ngTs = [datetime]::ParseExact($ngL.Substring(0, 19), 'yyyy-MM-dd HH:mm:ss', $ngInv) } catch { continue }
            if ($ngTs -lt $ngInis) { continue }
            if ($ngUygRx.IsMatch($ngL)) { $ngUygulandi++; continue }
            if ($ngRetRx.IsMatch($ngL)) { $ngRet++; continue }
            if ($ngAtlRx.IsMatch($ngL)) { $ngAtlandi++ }
        }
    }
    $ngUretilen = $ngUygulandi + $ngRet + $ngAtlandi

    # FIRSAT SAYIMI: yalniz MODELE GIDEN derleme (budget > 0) firsat sayilir.
    # COMPILE_BOS / COMPILE_BUTCE / COMPILE_SLOT_YOK kosulari modele hic sormadi,
    # dolayisiyla guncelleme blogu uretme sansi da hic olmadi.
    $ngDerleme = 0
    if ($ngSurumOk -and $ngInis) {
        foreach ($ngMk in @(Read-BeyinMakbuz -Paths $p -Gun 45)) {
            if ([string]$ngMk.script -ne 'compile') { continue }
            if ([int]$ngMk.budget -le 0) { continue }
            try { if ([datetime]::Parse([string]$ngMk.ts, $ngInv) -lt $ngInis) { continue } } catch { continue }
            $ngDerleme++
        }
    }

    # ---- KARAR ---------------------------------------------------------------
    $ngCalisiyor = ($ngBolum -gt 0) -or ($ngUygulandi -gt 0) -or ($ngYeniDamga -gt 0)
    $ngSezgiselEsik = 10
    $ngOlu    = ($ngRet -gt 0) -and (-not $ngCalisiyor)
    $ngSessiz = ($ngDerleme -ge $ngSezgiselEsik) -and ($ngUretilen -eq 0) -and (-not $ngCalisiyor)
    $ngOk = (-not $ngSurumOk) -or (-not ($ngOlu -or $ngSessiz))

    $ngDetay = "$($ngNotlar.Count) not · $ngBolum '## Guncelleme' bolumu · 2.3'ten beri $ngUygulandi guncelleme indi / $ngRet blok reddedildi / $ngAtlandi idempotent atlandi · $ngDerleme modelli derleme"
    if ($ngEskiDamga -gt 0) { $ngDetay += " · $ngEskiDamga eski sema damgasi (2.3 kaniti DEGIL)" }
    if ($ngInis) { $ngDetay += " · inis $($ngInis.ToString('yyyy-MM-dd', $ngInv))$(if ($ngInisKaynak -eq 'mtime') { ' (mtime)' })" }
    if (-not $ngSurumOk) { $ngDetay += " (surum $(if ($ngSurum) { $ngSurum } else { '?' }) - guncelleme yolu bu surumde yok)" }
    elseif ($ngOlu) { $ngDetay += ' (uretilen bloklarin hicbiri inmedi)' }
    elseif ($ngSessiz) { $ngDetay += " (SEZGISEL: $ngSezgiselEsik modelli derlemede model hic GUNCELLE blogu uretmedi)" }
    elseif (-not $ngCalisiyor) { $ngDetay += ' (henuz guncelleme uretilmedi - ariza degil)' }

    Add-Row 'not guncelligi' $ngOk $ngDetay `
        'Iki ayri durum var. (a) "N blok reddedildi / 0 indi": model GUNCELLE blogu URETIYOR ama hepsi kapida donuyor - sebep engine.log satirinda YAZILI (hedef yok / gecersiz ad / cok kisa / tavan / sablon disi frontmatter alani). Once o sebebi oku, sonra compile.ps1 Update-CompileKavramNotu kapilarina bak. (b) SEZGISEL uyari (esik 10 modelli derleme): model hic blok uretmiyor - prompt tarafina bak, compile.ps1 <<<GUNCELLE: slug.md>>> sozlesmesini modele anlatiyor mu, Write-BeyinKavramNotu -Guncelle ile mi cagriliyor. Kanit: motor\scripts\.state\engine.log ve beyin makbuz 7. DIKKAT: frontmatter "created != updated" farki 2.3 kaniti DEGILDIR - sema gocu de o damgayi basar, bu yuzden ayri sayilir.'
} catch { }

# ============================================================================
# KAYNAK ALIMI  (2.3, 2026-09-17)
# ----------------------------------------------------------------------------
# 2.3'e kadar beyin YALNIZ kendi ajan transkriptlerini yiyebiliyordu: elindeki
# bir makaleyi ya da raporu icine almanin yolu yoktu. 'beyin al <yol>' bunu acti;
# kaynak sayfasi 86-compiled\sources altina duser, ciktisi normal kavram notudur.
#
# Bu BILGI satiridir. Ozellik ISTEGE BAGLI oldugu icin klasor yoksa da, klasor
# bos da olsa YESIL - "kaynak alinmamis" bir ariza degildir. Kirmizi olabilecegi
# tek durum kontrolun KENDISININ patlamasidir (asagidaki catch).
# ============================================================================
try {
    $ksInv = [Globalization.CultureInfo]::InvariantCulture
    $ksDir = Join-Path $p.Compiled 'sources'
    if (-not (Test-Path -LiteralPath $ksDir)) {
        Add-Row 'kaynak alimi' $true 'klasor yok - hic dis kaynak alinmamis (ozellik istege bagli)' `
            'Elindeki makale/rapor/dokumani beyne vermek icin: beyin al <yol>  (-KuruCalisma yazmadan gosterir). Desteklenen: .md .markdown .txt .log .html .htm .json .csv'
    } else {
        $ksDosya = @(Get-ChildItem -LiteralPath $ksDir -Filter '*.md' -File -ErrorAction SilentlyContinue)
        $ksSon = 'henuz yok'
        if ($ksDosya.Count -gt 0) {
            $ksEn = @($ksDosya | Sort-Object LastWriteTime -Descending)[0]
            $ksYas = [int]((Get-Date) - $ksEn.LastWriteTime).TotalDays
            $ksSon = "$($ksEn.LastWriteTime.ToString('yyyy-MM-dd HH:mm', $ksInv)) ($ksYas gun once, $($ksEn.Name))"
        }
        Add-Row 'kaynak alimi' $true "$($ksDosya.Count) kaynak sayfasi · son: $ksSon" `
            'Yeni kaynak: beyin al <yol>. Kaynak sayfalari 86-compiled\sources altindadir; uretilen kavramlar normal kavram notudur ve var olan bir notu GUNCELLEYEBILIR.'
    }
} catch {
    # Klasorun YOK olmasi sorun degildir; OKUNAMAMASI sorundur - bu catch o yuzden
    # sessiz degil.
    if (-not @($rows | Where-Object { $_.Kontrol -eq 'kaynak alimi' }).Count) {
        Add-Row 'kaynak alimi' $false "kontrol hatasi: $($_.Exception.Message)" '86-compiled\sources okunamadi (izin ya da yol sorunu). Ozellik istege bagli oldugu icin klasorun hic OLMAMASI gecerlidir; okunamamasi degil.'
    }
}

# ============================================================================
# MAKBUZ  (Faz 1A, 2026-09-15)
# ----------------------------------------------------------------------------
# Motorun her kosusu bir makbuz birakiyor mu; bir dosya sifir bayta dustu mu;
# engine.log basari sayiyor ama makbuz yok mu (makbuzsuz kosu = yazici
# fonksiyon bir yerde atlanmis demek).
# ============================================================================
try {
    $mk24 = @(Read-BeyinMakbuz -Paths $p -Gun 1)
    $mk7  = @(Read-BeyinMakbuz -Paths $p -Gun 7)
    $mkDizinVar = [bool]($p.Makbuz -and (Test-Path -LiteralPath $p.Makbuz))
    # engine.log'daki gercek basarilar (son 24 saat): makbuz da olmali
    $engSatir = @()
    try {
        foreach ($lf in @((Join-Path $p.ScrState 'engine.log'), (Join-Path $p.ScrState 'engine.1.log'))) {
            if (Test-Path -LiteralPath $lf) { $engSatir += @(Get-Content -LiteralPath $lf -Encoding UTF8 -ErrorAction SilentlyContinue) }
        }
    } catch { }
    function MkBasariSay([datetime]$Baslangic) {
        $n = 0
        foreach ($ln in $engSatir) {
            if ($ln -notmatch '^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\s+(flush: yazildi ->|compile: \d+ kavram notu yazildi)') { continue }
            try {
                $t = [datetime]::ParseExact($Matches[1], 'yyyy-MM-dd HH:mm:ss', [Globalization.CultureInfo]::InvariantCulture)
                if ($t -ge $Baslangic) { $n++ }
            } catch { }
        }
        return $n
    }
    $engOk24 = MkBasariSay ((Get-Date).AddDays(-1))
    if ($mk24.Count -eq 0) {
        $mkOk = ($engOk24 -eq 0)
        $mkDet = if (-not $mkDizinVar) { 'henuz kayit yok (dizin olusmadi)' }
                 elseif ($engOk24 -gt 0) { "24 saatte 0 makbuz ama engine.log $engOk24 basarili flush/compile sayiyor" }
                 else { 'henuz kayit yok (24 saatte motor kosusu olmadi)' }
        Add-Row 'makbuz (24 saat)' $mkOk $mkDet 'Motor kosuyor ama makbuz yazmiyor: Write-BeyinMakbuz cagrisi flush/compile icinde atlanmis. lib.ps1 Write-BeyinMakbuz ve flush.ps1 Stop-Flush kontrol et.'
    } else {
        $mkGrup = @($mk24 | Group-Object script | Sort-Object Count -Descending | ForEach-Object { "$($_.Name)=$($_.Count)" })
        $mkButce = ($mk24 | Measure-Object -Property budget -Sum).Sum
        Add-Row 'makbuz (24 saat)' $true "$($mk24.Count) kosu: $($mkGrup -join ' ') · butce=$mkButce" 'Ayrinti: beyin makbuz 1'
    }

    # sifir bayt: b>0 -> a=0 (dosya vardi, kosudan sonra bos). 7 gun.
    $mkSifir = New-Object System.Collections.Generic.List[string]
    foreach ($m in $mk7) {
        foreach ($f in @($m.files)) {
            if ($null -eq $f) { continue }
            if ([long]$f.b -gt 0 -and [long]$f.a -eq 0) { $mkSifir.Add("$($f.p) ($($m.script), $($f.b)->0)") }
        }
    }
    Add-Row 'sifir bayt yazimi' ($mkSifir.Count -eq 0) `
        $(if ($mkSifir.Count) { "$($mkSifir.Count) dosya SIFIR BAYTA dustu: $(($mkSifir | Select-Object -First 3) -join '; ')" } else { "7 gunde sifir bayt yazimi yok ($($mk7.Count) makbuz)" }) `
        'Dosya kosudan once doluydu, sonra bos: geri al -> git -C "<vault>" checkout -- <dosya>; sonra ilgili betigin yazma yolunu (Write-BeyinText) incele.'

    # makbuzsuz kosu: makbuz kaydinin basladigi andan itibaren engine.log basari > makbuz basari
    $mkIlk = $null
    foreach ($m in $mk7) { try { $t = [datetime]::Parse($m.ts, [Globalization.CultureInfo]::InvariantCulture); if ($null -eq $mkIlk -or $t -lt $mkIlk) { $mkIlk = $t } } catch { } }
    if ($null -eq $mkIlk) {
        Add-Row 'makbuzsuz kosu' $true 'henuz kayit yok' 'Makbuz kaydi basladiginda engine.log basarilariyla karsilastirilir.'
    } else {
        $engOkMk = MkBasariSay $mkIlk
        $mkOkSay = @($mk7 | Where-Object { $_.outcome -in @('FLUSH_OK', 'COMPILE_OK') }).Count
        $mkFark = $engOkMk - $mkOkSay
        Add-Row 'makbuzsuz kosu' ($mkFark -le 0) `
            $(if ($mkFark -gt 0) { "engine.log $engOkMk basari, makbuz $mkOkSay (fark $mkFark)" } else { "engine.log $engOkMk basari = makbuz $mkOkSay" }) `
            'Bir betik basari logluyor ama makbuz yazmiyor. flush.ps1 / compile.ps1 sonundaki Write-FlushMakbuz / Write-CompileMakbuz cagrisini kontrol et.'
    }
} catch { }

# ============================================================================
# NIYET  (Faz 1B, 2026-09-15)
# ============================================================================
try {
    $nyF = Join-Path $p.ScrState 'niyet.json'
    if (-not (Test-Path -LiteralPath $nyF)) {
        Add-Row 'niyet' $true 'kayitli niyet yok' 'Ileriye donuk hedef kaydetmek icin: beyin niyet "..."  (oturum acilisinda iki ajana da enjekte edilir).'
    } else {
        $nyHepsi = Get-BeyinNiyet -Paths $p -MaxGun 36500
        if (-not $nyHepsi) {
            Add-Row 'niyet' $false 'niyet.json okunamadi/bos' 'beyin niyet -Temizle ile sil, sonra yeniden yaz.'
        } else {
            $nyKisa = [string]$nyHepsi.Text
            if ($nyKisa.Length -gt 50) { $nyKisa = $nyKisa.Substring(0, 47) + '...' }
            $nyGun = [int][math]::Floor($nyHepsi.AgeDays)
            Add-Row 'niyet' ($nyHepsi.AgeDays -le 7) `
                "$nyGun gun$(if ($nyHepsi.Project) { ", proje: $($nyHepsi.Project)" }): $nyKisa$(if ($nyHepsi.AgeDays -gt 7) { ' (BAYAT - enjekte edilmiyor)' })" `
                'Niyet 7 gunden eski: ya yenile (beyin niyet "...") ya temizle (beyin niyet -Temizle). Bayat hedef enjekte edilmez.'
        }
    }
} catch { }

# ============================================================================
# OLU KAVRAM  (Faz 2C, 2026-09-15)  -  bahcivan.ps1'in kavram bolumu
# ============================================================================
try {
    $bhOut = & (Join-Path $p.Scripts 'bahcivan.ps1') -Vault $Vault -Bolum kavram -Json 2>$null
    $bh = ($bhOut -join "`n") | ConvertFrom-Json
    if (-not $bh -or -not $bh.kavram) {
        Add-Row 'olu kavram' $true 'bahcivan calismadi (makbuz yok ya da kavram klasoru bos)' 'beyin bahcivan'
    } else {
        $bhAday = @($bh.kavram.oluAday).Count
        if (-not $bh.kapsamYeterli) {
            Add-Row 'olu kavram' $true "kapsam $($bh.kapsamGun)/$($bh.gun) gun - olu karari verilemez (canli $($bh.kavram.canli), uyuyor $($bh.kavram.uyuyor), toplam $($bh.kavram.toplam))" 'Makbuz penceresi dolunca (90 gun) bahcivan olu adaylari secebilir. Simdilik yalniz rapor: beyin bahcivan'
        } else {
            Add-Row 'olu kavram' ($bhAday -lt 10) "canli $($bh.kavram.canli), uyuyor $($bh.kavram.uyuyor), olu-aday $bhAday / $($bh.kavram.toplam)" 'Olu aday >=10: beyin bahcivan (liste) sonra beyin bahcivan-uygula (90-archive/86-compiled/concepts/ altina tasir).'
        }
    }
} catch { }

# ============================================================================
# DISK  (Faz 3E, 2026-09-15)  -  bos alan + copcu'nun son olcumu
# ============================================================================
try {
    $dsk = Get-PSDrive -Name ($env:SystemDrive.TrimEnd(':')) -ErrorAction Stop
    $bosGB = [math]::Round($dsk.Free / 1GB, 1)
    $topGB = [math]::Round(($dsk.Free + $dsk.Used) / 1GB, 0)
    $cpNot = ''
    $cpF = Join-Path $p.ScrState 'copcu-son.json'
    if (Test-Path -LiteralPath $cpF) {
        try {
            $cp = Get-Content -LiteralPath $cpF -Raw -Encoding UTF8 | ConvertFrom-Json
            $cpGun = [int]((Get-Date) - [datetime]::Parse([string]$cp.ts, [Globalization.CultureInfo]::InvariantCulture)).TotalDays
            $cpNot = " · geri kazanilabilir $([math]::Round([double]$cp.silinebilirMB / 1024, 1)) GB (copcu $cpGun gun once, $($cp.aday) aday)"
        } catch { }
    } else { $cpNot = ' · copcu henuz calismadi' }
    # KULLANICININ YAPABILECEGI BIR SEY YOKSA SATIR KIRMIZI OLMAMALI
    # (2026-09-18). Sabit 20 GB esigi kucuk diskli bir makinede KALICI kirmizi
    # uretiyordu ve onerilen care (beyin copcu) cogu zaman silinecek bir sey
    # bulmuyordu. Doktorun kendi felsefesi ('surekli kirmizi bir satir tum
    # sinyali korlestirir', bkz. 'yedek tazeligi') bu satira uygulanmamisti.
    #
    # Yeni yuklem: 5 GB altinda HER ZAMAN kirmizi (yazmalarin gercekten
    # dustugu taban). 5-20 GB arasi YALNIZCA copcu 2 GB'tan fazla geri
    # kazanilabilir diyorsa - yani gercekten YAPILACAK bir sey varsa.
    $cpGeriMB = -1
    if (Test-Path -LiteralPath $cpF) {
        try { $cpGeriMB = [double](Get-Content -LiteralPath $cpF -Raw -Encoding UTF8 | ConvertFrom-Json).silinebilirMB } catch { $cpGeriMB = -1 }
    }
    $diskOk = $true
    if ($bosGB -lt 5) { $diskOk = $false }
    elseif ($bosGB -lt 20 -and $cpGeriMB -gt 2048) { $diskOk = $false }
    Add-Row 'disk' $diskOk "$bosGB / $topGB GB bos$cpNot" `
        $(if (-not $diskOk) { 'beyin copcu (rapor) sonra beyin copcu-uygula (kalici) - yalniz git''in yok saydigi cikti klasorleri silinir. Copcunun bulacagi bir sey yoksa yer acmak motor disi bir istir.' } else { '' })
} catch { }

# ============================================================================
# EMBEDDING  (Faz 4F, 2026-09-15)  -  vektor geri getirme sagligi
# ============================================================================
try {
    $emDat = Join-Path $p.ScrState 'kavram-vektor.dat'
    $emTags = Invoke-BeyinOllamaJson -Yol '/api/tags' -TimeoutMs 1500
    if (-not $emTags) {
        Add-Row 'embedding' $true "Ollama yok/kapali: anahtar kelime yolu$(if (Test-Path -LiteralPath $emDat) { ' (vektor indeksi duruyor, Ollama acilinca kullanilir)' })" 'Istege bagli: Ollama kur + ollama pull bge-m3 + beyin gom. Kelime yolu her zaman calisir.'
    } else {
        $emModelVar = [bool](@($emTags.models | Where-Object { ([string]$_.name) -like ($script:BeyinEmbedModel + '*') }).Count)
        if (-not (Test-Path -LiteralPath $emDat)) {
            Add-Row 'embedding' $true "vektor indeksi yok (Ollama var$(if ($emModelVar) { ", $($script:BeyinEmbedModel) yuklu" } else { ", model yok" }))" "beyin gom  (model yoksa once: ollama pull $($script:BeyinEmbedModel))"
        } elseif (-not $emModelVar) {
            Add-Row 'embedding' $false "vektor indeksi var ama '$($script:BeyinEmbedModel)' Ollama'da yok - sorgu gomulemez, kelime yoluna dusuluyor" "ollama pull $($script:BeyinEmbedModel)"
        } else {
            $emMeta = Get-Content -LiteralPath $emDat -Raw -Encoding UTF8 | ConvertFrom-Json
            $emN = @($emMeta.items).Count
            $emDisk = @(Get-ChildItem -LiteralPath (Join-Path $p.Compiled 'concepts') -Filter '*.md' -File -ErrorAction SilentlyContinue).Count
            $emEksik = [math]::Max(0, $emDisk - $emN)
            $emYas = try { [int]((Get-Date) - [datetime]::Parse([string]$emMeta.ts, [Globalization.CultureInfo]::InvariantCulture)).TotalDays } catch { 999 }
            $emBayat = ($emDisk -gt 0 -and ($emEksik / [double]$emDisk) -gt 0.10 -and $emYas -gt 2)
            Add-Row 'embedding' (-not $emBayat) "$emN vektor / diskte $emDisk kavram ($($emMeta.model), $($emMeta.dim)-d, $emYas gun once)$(if ($emEksik) { " · $emEksik eksik" })" 'Eksik %10 ustu ve 2 gunden eski: beyin gom (zamanlayici gece 03:10 kosar).'
        }
    }
} catch { }

# ============================================================================
# ZAMANLANMIS GOREVLER  (Faz 5D, 2026-09-15)
# ============================================================================
try {
    $zg = @(Get-ScheduledTask -TaskPath '\Beyin\' -ErrorAction SilentlyContinue)
    if ($zg.Count -eq 0) {
        Add-Row 'zamanlanmis gorevler' $true 'kurulmamis (motor yalniz oturumlarda calisir)' 'Gece gorevleri icin: beyin zamanla  (derle 03:00, gom 03:10, bagla 03:15, topla 03:20, yedek Paz 03:40, copcu 04:00, bahcivan Paz 04:30, denetle Paz 05:00)'
    } else {
        $zgSorun = New-Object System.Collections.Generic.List[string]
        $zgSon = [datetime]::MinValue
        foreach ($t in $zg) {
            $i = Get-ScheduledTaskInfo -TaskName $t.TaskName -TaskPath '\Beyin\' -ErrorAction SilentlyContinue
            if (-not $i) { continue }
            # NEDEN (2026-09-16 denetim): LastTaskResult UInt32'dir ve zamanlayicinin
            # TUM hata kodlari 0x80000000 ustundedir (0x80070005 erisim yok, 0x8007052E
            # parola, 0x800710E0 operator reddetti, 0x8004131F zaten kosuyor). [int]
            # donusumu tam bu degerlerde firlatiyordu, bos catch yutuyordu ve satir
            # TAMAMEN KAYBOLUYORDU (-Ozet: 'Zamanlayici : -', TANI bir kontrol eksik).
            # Satirin var olma sebebi olan hata sinifi satiri siliyordu.
            $kod = [uint32]$i.LastTaskResult
            if ($kod -notin @(0, 267011, 267009)) { $zgSorun.Add("$($t.TaskName)=$('0x{0:X}' -f $kod)") }
            if ($i.LastRunTime -gt $zgSon) { $zgSon = $i.LastRunTime }
            if ($t.State -eq 'Disabled') { $zgSorun.Add("$($t.TaskName) devre disi") }
        }
        # NEDEN (2026-09-16 denetim): sarmalayici (zamanli-kos.ps1) ESKIDEN her durumda
        # exit 0 veriyordu (2026-09-16 itibariyle KIMLIK_YOK=3, cocuk kodu aynen doner);
        # makbuz yine de ikinci ve aciklayici kaynak: sonuc kodu yalniz sayidir, makbuz
        # notu nedeni tasir. Canli ornek: 2026-09-15 16:25 'derle KIMLIK_YOK (oturum yok,
        # loggedIn=false)' - o gun gorev sonucu 0, satir yesil, gece derleme gunlerce
        # sessizce atlanabilirdi. Ayni gece hem 'beyin-derle=0x3' hem 'derle son kosu
        # KIMLIK_YOK (...)' gorunebilir; bu bilincli: biri zamanlayicinin, digeri motorun
        # tanigi. Son 3 gunde her komutun SON makbuzu okunur; sonuncusu basarisizsa satir
        # kirmizi (toparlaninca kendiliginden yesile doner, eski bir basarisizlik
        # 3 gun kirmizi tutmaz - zamanlayicinin kendi 'son sonuc' anlamiyla ayni).
        # BEKLENEN KUME KARSILASTIRMASI (2026-09-17, olculdu)
        #
        # Bu satir eskiden yalniz KAYITLI gorevlere bakiyordu. Olculen sonuc:
        # zamanla.ps1 sekiz gorev tanimlarken makinede altisi kayitliydi
        # ('bagla' ve 'denetle' 2.3'te eklenmis, 'beyin zamanla' bir daha
        # kosulmamisti) ve satir "6 gorev - son kosu 0 gun once" deyip YESIL
        # basiyordu. Yani surumle gelen her yeni gece gorevi sessizce hic
        # kosmuyordu ve hicbir kontrol bunu soylemiyordu.
        #
        # Beklenen adlar zamanla.ps1'in KENDISINDEN okunur - tek dogruluk
        # kaynagi orasi. Betik CALISTIRILMAZ (yan etkisi var: gorev kaydeder);
        # $GOREVLER blogu metin olarak ayristirilir.
        $zgBeklenen = @()
        try {
            $zgYol = Join-Path $Vault 'kurulum\zamanla.ps1'
            if (Test-Path -LiteralPath $zgYol -PathType Leaf) {
                $zgHam = Get-Content -LiteralPath $zgYol -Raw -Encoding UTF8
                $zgBlok = [regex]::Match($zgHam, '(?s)\$GOREVLER\s*=\s*@\((.*?)\n\)')
                if ($zgBlok.Success) {
                    foreach ($mm in [regex]::Matches($zgBlok.Groups[1].Value, "@\{\s*Ad\s*=\s*'([^']+)'")) {
                        $zgBeklenen += ('beyin-' + $mm.Groups[1].Value)
                    }
                }
            }
        } catch { }
        if ($zgBeklenen.Count -gt 0) {
            $zgKayitli = @($zg | ForEach-Object { [string]$_.TaskName })
            $zgEksik = @($zgBeklenen | Where-Object { $zgKayitli -notcontains $_ })
            if ($zgEksik.Count -gt 0) {
                # 'beyin-yedek' brain-cli bulunamazsa BILEREK kaydedilmez;
                # onu eksik saymak kalici yanlis kirmizi uretirdi.
                #
                # DIKKAT (olculdu 2026-09-17): burada `$cli` OKUNAMAZ - o
                # degisken betigin brain-cli bolumunde, bu satirdan COK SONRA
                # tanimlaniyor. Ilk surum onu okudugu icin kosul HER ZAMAN
                # "mazur" cikiyordu ve gercekten eksik olan yedek gorevi hic
                # raporlanmiyordu; yani kontrolun yakalamasi gereken tek
                # ozel durum tam da gozden kaciyordu. Arama burada, yerinde
                # yapilir.
                $zgCli = $null
                # TEK KAYNAK (2026-09-18): arama lib.ps1'de, burada kopyasi yok.
                $zgCli = (Get-BeyinBrainCli -Vault $Vault).Yol
                $zgYedekMazur = ($zgEksik -contains 'beyin-yedek') -and (-not $zgCli)
                $zgGercekEksik = @($zgEksik | Where-Object { -not ($_ -eq 'beyin-yedek' -and $zgYedekMazur) })
                if ($zgGercekEksik.Count -gt 0) {
                    $zgSorun.Add("$($zgGercekEksik.Count) gorev EKSIK: $($zgGercekEksik -join ', ')")
                }
            }
        }

        $zgSonMk = @{}
        foreach ($m in @(Read-BeyinMakbuz -Paths $p -Gun 3)) {
            if ($m.script -ne 'zamanli' -or -not $m.reason) { continue }
            $zgSonMk[[string]$m.reason] = $m   # dosya+satir sirasi kronolojik: sonuncu kalir
        }
        foreach ($zgAd in @($zgSonMk.Keys | Sort-Object)) {
            $m = $zgSonMk[$zgAd]
            if ($m.outcome -eq 'KIMLIK_YOK' -or $m.outcome -eq 'ZAMANLI_HATA') {
                $zgNot = [string]$m.note
                if ($zgNot.Length -gt 80) { $zgNot = $zgNot.Substring(0, 80) + '...' }
                $zgSorun.Add("$zgAd son kosu $($m.outcome)$(if ($zgNot) { " ($zgNot)" })")
            }
        }
        $zgYas = if ($zgSon -gt [datetime]'2000-01-01') { [int]((Get-Date) - $zgSon).TotalDays } else { -1 }
        # 3 gunden uzun hic kosmadi (ve en az bir gorev bir kez kosmus ya da kurulum 3 gunden eski)
        if ($zgYas -gt 3) { $zgSorun.Add("son kosu $zgYas gun once") }
        Add-Row 'zamanlanmis gorevler' ($zgSorun.Count -eq 0) `
            "$($zg.Count)$(if ($zgBeklenen.Count) { "/$($zgBeklenen.Count)" }) gorev · son kosu: $(if ($zgYas -ge 0) { "$zgYas gun once" } else { 'henuz yok' })$(if ($zgSorun.Count) { ' · SORUN: ' + ($zgSorun -join '; ') })" `
            'Gorev EKSIK ise: beyin zamanla  (fikirli, var olanlari bozmaz - surumle gelen yeni gece gorevleri ancak boyle kurulur). Basarisiz sonuc kodu, makbuzda KIMLIK_YOK/ZAMANLI_HATA ya da 3 gundur kosmayan gorev: beyin zamanla -Liste ile bak; beyin makbuz -Gun 3 (nota bak); engine.log [zamanlayici] satirlari; KIMLIK_YOK ise ajanda yeniden oturum ac (claude auth status / codex login status); PC uyuyorsa acilinca kosar (StartWhenAvailable).'
    }
} catch {
    # NEDEN (2026-09-16 denetim): kontrolun kendisi patlarsa satir yok olmasin;
    # '-' yerine kirmizi bir satirla hatanin kendisi gorunsun (eski bos catch
    # tam olarak bu yuzden sessiz kaliyordu).
    if (-not @($rows | Where-Object { $_.Kontrol -eq 'zamanlanmis gorevler' }).Count) {
        Add-Row 'zamanlanmis gorevler' $false "kontrol hatasi: $($_.Exception.Message)" 'Get-ScheduledTask / Get-ScheduledTaskInfo / Read-BeyinMakbuz basarisiz; beyin zamanla -Liste ile elle bak'
    }
}

# ============================================================================
# KURTARMA (2026-09-10)
# ============================================================================
# NEDEN: doktor 48 seyi denetliyordu ama beynin KENDI KURTARMA YOLUNU hic
# denetlemiyordu. Bu turda somut olarak yasandi: bir betik hatasi kalici bir
# kavram notunu SIFIR BAYTA dusurdu ve dosya yalnizca commit'ten geri alinabildi.
# Yani kurtarma yolu teorik degil, KULLANILAN bir yol - ama saglikli olup
# olmadigini kimse olcmuyordu.
#
# Ayrica bu turda 'yedek alindi' sanilan bir komut aslinda yalniz ONIZLEME
# plani uretmisti (brain-cli backup, --apply olmadan hicbir sey yazmaz).
# Onizlemeyi yedek sanmak, olmayan bir agin ustunde yurumektir.
try {
    $yedekKok = Join-Path $Vault '.brain\backups'
    $yedekler = @(Get-ChildItem -LiteralPath $yedekKok -Directory -Filter 'backup-*' -ErrorAction SilentlyContinue |
                  Sort-Object LastWriteTime -Descending)
    if ($yedekler.Count -eq 0) {
        # TAZE KURULUM ISTISNASI (2026-09-17, olculdu): yeni kurulmus bir
        # vault'ta henuz tek bir gunluk log ya da kavram notu yokken "yedek
        # yok" KAYIP degil - kaybedilecek bir sey yok. Ilk icerik dustugu anda
        # satir normal davranisina doner.
        # Ayni kapi: icerik yoksa VE kurulum yeniyse kayip yok. Eski bir
        # vault icerigini arsivlemis olabilir - orada yedeksizlik gercek.
        $korunacakVar = (($dayFiles.Count -gt 0) -or ($conFiles.Count -gt 0) -or ($kurulumGun -gt 7))
        Add-Row 'yedek tazeligi' (-not $korunacakVar) `
            $(if ($korunacakVar -and (($dayFiles.Count -gt 0) -or ($conFiles.Count -gt 0))) { "hic yedek yok ($($dayFiles.Count) gunluk log + $($conFiles.Count) kavram notu korumasiz)" }
              elseif ($korunacakVar) { "hic yedek yok (kurulum $kurulumGun gun once; icerik arsivlenmis ya da tasinmis olabilir)" }
              else { "taze kurulum ($kurulumGun gun): henuz yedeklenecek icerik yok (0 gunluk log, 0 kavram notu)" }) `
            'yedek al: brain-cli backup --target "<vault>" --apply  (--apply YOKSA yalniz onizleme uretir, hicbir sey yazilmaz)'
    } else {
        $sonY  = $yedekler[0]
        $yas   = [int]((Get-Date) - $sonY.LastWriteTime).TotalDays
        $boyut = 0
        try { $boyut = [math]::Round((Get-ChildItem -LiteralPath $yedekKok -Recurse -File -ErrorAction SilentlyContinue |
                                      Measure-Object -Property Length -Sum).Sum / 1MB) } catch { }
        Add-Row 'yedek tazeligi' ($yas -le 7) `
            "$($yedekler.Count) yedek · en yenisi $yas gun once ($($sonY.Name)) · toplam $boyut MB" `
            'yedek al: brain-cli backup --target "<vault>" --apply'
    }

    # Tek nokta arizasi: yedekler vault'un ICINDE. Vault dizini giderse yedekler
    # de gider. Bunu kirmizi bir satir yapmiyoruz - duzeltmesi kullanicinin
    # karari (uzak depo / harici disk) ve surekli kirmizi bir satir, doktorun
    # tum sinyalini kortelestirir. Ama HER kosuda gorunur kalir.
    $uzak = @(& git -C $Vault remote 2>$null | Where-Object { $_ })
    $disYedek = $yedekKok -notlike ($Vault + '*')

    # YAYIN DEPOSU (2026-09-10): motor + kurulum ayri bir depoya gonderiliyor
    # ('beyin yayinla'). Bu depo NOT TASIMAZ - onun amaci "bu makineye bir sey
    # olursa ayni kurulumu geri kur" olmaktir, not yedegi degil.
    #
    # Bunu ayirt etmek onemli: yayin deposu varken satirin "uzak depo YOK"
    # demesi yaniltici olurdu (motor aslinda yedekli), "uzak depo var" demesi
    # de yaniltici olurdu (notlar yedekli DEGIL). Ikisi ayri ayri raporlanir.
    $yayinKok = Join-Path (Split-Path $Vault -Parent) ((Split-Path $Vault -Leaf) + '-motor')
    $yayinDurum = 'yok'
    $yayinYas = -1
    if (Test-Path -LiteralPath (Join-Path $yayinKok '.git')) {
        $yUzak = @(& git -C $yayinKok remote 2>$null | Where-Object { $_ })
        if ($yUzak.Count) {
            $yayinDurum = 'uzakta'
            try {
                $sonC = (& git -C $yayinKok log -1 --format=%cI 2>$null | Out-String).Trim()
                if ($sonC) { $yayinYas = [int]((Get-Date) - [datetime]::Parse($sonC)).TotalDays }
            } catch { }
        } else { $yayinDurum = 'yerel (uzak ayarlanmamis)' }
    }

    $yayinMetin = switch ($yayinDurum) {
        'yok'     { 'motor yayini YOK' }
        'uzakta'  { "motor yayini uzakta$(if ($yayinYas -ge 0) { " ($yayinYas gun once)" })" }
        default   { "motor yayini $yayinDurum" }
    }

    Add-Row 'kurtarma yedekliligi' $true `
        "$yayinMetin · vault uzak deposu: $(if ($uzak.Count) { ($uzak -join ', ') } else { 'YOK (notlar yalniz burada)' }) · yedekler $(if ($disYedek) { 'vault DISINDA' } else { 'vault ICINDE (.brain\backups)' })" `
        $(if ($yayinDurum -eq 'yok') {
              'Motor ve kurulum hicbir yere gonderilmemis: bu makineye bir sey olursa kurulumu sifirdan yazmak gerekir. Cozum: beyin yayinla -Uygula -Gonder'
          } elseif ($yayinYas -gt 30) {
              "Motor yayini $yayinYas gundur guncellenmemis; diskteki motor ile yayindaki farkli olabilir. Cozum: beyin yayinla -Uygula -Gonder"
          } elseif (-not $uzak.Count -and -not $disYedek) {
              'BILGI: motor yedekli ama NOTLAR degil - notlarin tek kopyasi bu makinede. Bu bilincli bir tercihti (notlar disari cikmiyor). Ek guvence istersen .brain\backups klasorunu periyodik olarak baska bir diske kopyala.'
          } else { '' })

    # Calisan kod ile commit edilmis kod ayni mi. Bu turda motor 2.1.2 bir sure
    # tamamen commit edilmemis halde calisti; o pencerede bir dosya bozulsaydi
    # geri alinacak bir surum YOKTU.
    # NEDEN (2026-09-16 denetim): yalniz motor/ bakiliyordu; kurulum/ (kur.ps1, her
    # zamanli gorevin gectigi beyin.ps1 dagiticisi, zamanla.ps1, iskelet) de motor
    # kodudur (BOM/parse taramasi ve yayinla.ps1 oyle sayar) ama kapsam disiydi.
    # Olculdu: kurulum altinda degismis dosya varken satir 'calisan kod = commit
    # edilmis kod' diyordu; dagitici bozuk kalsa geri alinacak surum olmazdi.
    $kirli = @(& git -C $Vault status --porcelain -- 'motor' 'kurulum' 2>$null | Where-Object { $_ })
    Add-Row 'motor kodu commit edildi mi' ($kirli.Count -eq 0) `
        $(if ($kirli.Count) { "$($kirli.Count) motor/kurulum dosyasi commit edilmemis: $((($kirli | Select-Object -First 4) | ForEach-Object { ($_ -split '\s+', 3)[-1] }) -join ', ')" } else { 'calisan kod = commit edilmis kod (motor + kurulum)' }) `
        'commit et: git -C "<vault>" add motor kurulum; git -C "<vault>" commit -m "..."  (commit edilmemis motor/kurulum kodu bozulursa geri alinacak surum yoktur)'
} catch { }

# ============================================================================
# OBSIDIAN YUZEYI
# ============================================================================
$bases = @(Get-ChildItem -LiteralPath (Join-Path $Vault '10-command-center') -Filter '*.base' -File -ErrorAction SilentlyContinue)
# DAVRANISSAL KONTROL (2026-09-10): satir yalnizca DOSYA SAYIYORDU ve iki olu
# base'i haftalarca 'OK' diye rapor etti (gunluk-loglar 0 satir gosteriyordu,
# kavramlar 79 nottan 3'unu). Artik her base'in filtresi klasordeki notlarin
# frontmatter'ina karsi sinaniyor.
$baseSorun = New-Object System.Collections.Generic.List[string]
foreach ($b in $bases) {
    try {
        $bc = Get-Content -LiteralPath $b.FullName -Raw -Encoding UTF8
        $mk = [regex]::Match($bc, 'file\.inFolder\("([^"]+)"\)')
        if (-not $mk.Success) { continue }
        $klasor = Join-Path $Vault ($mk.Groups[1].Value -replace '/', '\')
        if (-not (Test-Path -LiteralPath $klasor)) {
            # TAZE VAULT ISTISNASI: hicbir gunluk log yoksa beyin daha yeni
            # kurulmus demektir; motorun henuz uretmedigi bir klasorun yoklugu
            # ARIZA DEGILDIR. Ilk kurulumda bu satir kirmizi yaniyordu ve yeni
            # kullaniciya "bir sey bozuk" izlenimi veriyordu.
            $hicLogVar = @(Get-ChildItem -LiteralPath $p.Daylogs -Filter '*.md' -File -ErrorAction SilentlyContinue).Count
            if ($hicLogVar -eq 0) { continue }
            $baseSorun.Add("$($b.Name): klasor yok"); continue
        }
        $notlar = @(Get-ChildItem -LiteralPath $klasor -Recurse -Filter '*.md' -File -ErrorAction SilentlyContinue)
        if ($notlar.Count -eq 0) { continue }
        foreach ($fm in [regex]::Matches($bc, '''\s*([A-Za-z_][A-Za-z0-9_.]*)\s*==\s*"([^"]+)"\s*''')) {
            $alan = $fm.Groups[1].Value; $deger = $fm.Groups[2].Value
            $es = 0
            foreach ($n in $notlar) {
                $nc = Get-Content -LiteralPath $n.FullName -TotalCount 25 -Encoding UTF8 -ErrorAction SilentlyContinue
                if ($nc -and ($nc -join "`n") -match ("(?m)^" + [regex]::Escape($alan) + ':\s*"?' + [regex]::Escape($deger) + '"?\s*$')) { $es++ }
            }
            if ($es -eq 0) { $baseSorun.Add("$($b.Name): '$alan == $deger' hicbir notla eslesmiyor ($($notlar.Count) not)") }
            elseif ($es -lt [math]::Ceiling($notlar.Count * 0.1)) { $baseSorun.Add("$($b.Name): '$alan == $deger' yalniz $es/$($notlar.Count) not") }
        }
    } catch { }
}
# ============================================================================
# MOTOR GUNCELLIGI  (2026-09-17)  -  yayinlanan surumle arasindaki fark
# ============================================================================
# NEDEN: 'surum tutarliligi' yalniz vault ICINDEKI iki damgayi karsilastirir
# (current-context ile .beyin-version). Baska bir makineye kurulmus bir motorun
# GERIDE kaldigini hicbir kontrol soylemiyordu; kullanici ancak bir hatayla
# karsilasinca fark ediyordu.
#
# ASLA KALICI KIRMIZI DEGIL: ag yoksa, depo erisilemezse ya da bu vault yayinin
# KAYNAGI ise yesil doner ve sebebini yazar.
#
# AG MALIYETI: tam doktorda gunde EN FAZLA bir kez, 2500 ms tavanla. '-Ozet'
# (yani 'beyin durum') hicbir zaman aga cikmaz, yalniz onbellegi okur - durum
# komutu en sik kullanilan komut ve gecikmemeli.
try {
    $guKaynak = Test-Path -LiteralPath (Join-Path $Vault 'kurulum\DEPO-README.md')
    $guYerel  = 'bilinmiyor'
    $guSv = Join-Path $Vault '.beyin-version'
    if (Test-Path -LiteralPath $guSv -PathType Leaf) {
        try { $guYerel = (Get-Content -LiteralPath $guSv -Raw -Encoding UTF8).Trim() } catch { }
    }

    if ($guKaynak) {
        Add-Row 'motor guncelligi' $true "bu vault yayinin KAYNAGI (surum $guYerel) - guncelleme ters yonde calisir" `
            'Kaynak vault guncellenmez, yayinlanir: beyin yayinla -Uygula -Gonder'
    } else {
        $guCache = Join-Path $p.ScrState 'uzak-surum.txt'
        $guUzak = ''; $guYas = 9999
        $guCurlKod = 0      # 0 = hic denenmedi
        $Dal = 'main'
        # Depo adresi AYARDAN gelir: motoru fork eden biri kendi deposunu
        # gosterebilmeli, yoksa hem 'beyin guncelle' hem bu satir sonsuza dek
        # bizim depomuza bakar (inceleme 2026-09-17).
        $guDepo = Get-BeyinAyar 'BEYIN_DEPO' (Get-BeyinAyarVars 'BEYIN_DEPO')
        $guDepo = ([string]$guDepo).TrimEnd('/')
        if ($guDepo.EndsWith('.git', [StringComparison]::OrdinalIgnoreCase)) { $guDepo = $guDepo.Substring(0, $guDepo.Length - 4) }
        if (Test-Path -LiteralPath $guCache -PathType Leaf) {
            try {
                $parca = ((Get-Content -LiteralPath $guCache -Raw -Encoding UTF8).Trim() -split "`t")
                if ($parca.Count -ge 2) {
                    $guYas = [int]((Get-Date) - [datetime]::Parse($parca[0], [Globalization.CultureInfo]::InvariantCulture)).TotalHours
                    $guUzak = $parca[1]
                }
            } catch { }
        }
        # Tazeleme yalnizca TAM doktorda ve onbellek 24 saatten eskiyse.
        if ((-not $Ozet) -and $guYas -ge 24) {
            try {
                # github.com/<kullanici>/<depo> -> raw.githubusercontent.com/<kullanici>/<depo>/<dal>
                $guUrl = ($guDepo -replace '^https?://github\.com/', 'https://raw.githubusercontent.com/') + "/$Dal/.beyin-version"
                $guTmp = Join-Path $env:TEMP ('beyin-uzak-surum-' + [guid]::NewGuid().ToString('N') + '.txt')
                # curl.exe: Windows 10+ ile gelir. Inline PowerShell + WebClient
                # KULLANILMAZ - o kombinasyonu bazi guvenlik urunleri
                # kotucul bir kalip sayip engelliyor (olculdu).
                & curl.exe -fsSL --max-time 3 -o $guTmp $guUrl 2>$null | Out-Null
                $guCurlKod = $LASTEXITCODE
                if ($guCurlKod -eq 0 -and (Test-Path -LiteralPath $guTmp)) {
                    $t = (Get-Content -LiteralPath $guTmp -Raw -Encoding UTF8).Trim()
                    if ($t -match '^\d+\.\d+') {
                        $guUzak = $t; $guYas = 0
                        Write-BeyinText -Path $guCache -Text ("{0}`t{1}" -f (Get-Date).ToString('yyyy-MM-ddTHH:mm:ssK', [Globalization.CultureInfo]::InvariantCulture), $t)
                    } else {
                        $guCurlKod = -1   # indi ama surum gibi durmuyor
                    }
                }
                Remove-Item -LiteralPath $guTmp -Force -ErrorAction SilentlyContinue
            } catch { }
        }

        if ($guDepo -notmatch '^https?://github\.com/') {
            # raw.githubusercontent donusumu yalniz GitHub icin gecerli.
            Add-Row 'motor guncelligi' $true "yerel surum $guYerel - depo GitHub disi ($guDepo), surum karsilastirmasi yapilamadi" `
                'GitHub disi bir depoda guncelligi elle kontrol et; beyin guncelle yine de calisir.'
        } elseif (-not $guUzak) {
            # curl cikis kodu ayirimi: 22 = sunucu CEVAP VERDI ama HTTP 4xx/5xx
            # (depo yok, ozel ya da dal adi yanlis) -> bu bir SORUN, 'ag yok'
            # degil. 6/7/28/35 = DNS/baglanti/zaman asimi/TLS -> gercekten ag
            # yok, yesil. 0 = hic denenmedi (-Ozet ya da onbellek taze).
            $guHttp = ($guCurlKod -eq 22)
            Add-Row 'motor guncelligi' (-not $guHttp) `
                $(if ($guHttp) { "yerel surum $guYerel - UZAK DEPO OKUNAMIYOR (HTTP hatasi): depo yok, ozel ya da '$Dal' dali yanlis. 'beyin guncelle' bu haliyle calismaz." }
                  elseif ($guCurlKod -eq -1) { "yerel surum $guYerel - uzak dosya indi ama surum gibi durmuyor" }
                  else { "yerel surum $guYerel - uzak surum bilinmiyor (ag yok ya da kontrol edilmedi)" }) `
                $(if ($guHttp) { 'Depo adresini kontrol et; ozel depoda guncelleme calismaz (curl kimlik dogrulamiyor). Yerel yayin: beyin yayinla -Uygula -Gonder' }
                  else { 'Istege bagli: beyin guncelle -KuruCalisma  (ne degisecegini yazmadan gosterir)' })
        } elseif ($guUzak -eq $guYerel) {
            Add-Row 'motor guncelligi' $true "guncel: $guYerel (uzak kontrol $guYas saat once)" ''
        } else {
            Add-Row 'motor guncelligi' $false "yerel $guYerel - yayinda $guUzak (uzak kontrol $guYas saat once)" `
                'beyin guncelle   (once: beyin guncelle -KuruCalisma; notlara dokunmaz, yalniz motor/kurulum yazilir)'
        }
    }
} catch { }

# ============================================================================
# AYAR DOSYASI  (2026-09-17)  -  ~\.beyin\ayar.json saglikli mi
# ============================================================================
# NEDEN: ayar dosyasi FAIL-OPEN okunur (bozuksa motor durmaz, varsayilana
# duser). Bu dogru davranis, ama sessiz: kullanici bir ayar yazdigini sanip
# varsayilanla calisabilir. Bu satir o sessizligi bozar.
#
# NEDEN KENDI AYRISTIRICISI YOK (inceleme 2026-09-17, kosarak dogrulandi):
# bu satirin ilk surumu ayar dosyasini KENDI regex'iyle okuyordu ve o regex
# IgnoreCase idi; lib.ps1'inki degil. Olculen sonuc: {"beyin_ozetleyici":"codex"}
# yazildiginda doktor "1 ayar yazili - OK" derken motor o satiri YOK SAYIP
# 'auto' yukluyordu. Yani satir, kirmak icin eklendigi sessiz uyusmazligin
# tam ustune "gecerli" damgasi basiyordu. Ikinci ayrisma: doktor butceye
# yalniz `^\d+$` bakiyordu, 0 geciyordu - butce 0 her model cagrisini
# reddeder ve TUM ozetleme sessizce durur, doktor tamamen yesil kalirdi.
# Artik tek ayristirici ve tek kural kumesi lib.ps1'de; doktor onu CAGIRIR.
try {
    $ayD = Get-BeyinAyarDenetim
    if (-not $ayD.Var) {
        Add-Row 'ayar dosyasi' $true 'yok - tum ayarlar varsayilan (normal)' `
            'Ayarlari gormek/degistirmek icin: beyin ayar'
    } else {
        # Ortam degiskeni ayar dosyasini EZER: sessiz sasirtma kaynagi, soylenir.
        $ayEzen = New-Object System.Collections.Generic.List[string]
        foreach ($k in @($ayD.Tablo.Keys)) {
            $ev = [Environment]::GetEnvironmentVariable([string]$k)
            if ($ev -and $ev -ne [string]$ayD.Tablo[$k]) { $ayEzen.Add([string]$k) }
        }
        $aySorun = @($ayD.Sorunlar)
        $ayNot = "$($ayD.Sayi) ayar yazili"
        if ($ayEzen.Count -gt 0) { $ayNot += " · ortam degiskeni EZIYOR: $($ayEzen -join ', ')" }
        Add-Row 'ayar dosyasi' ($aySorun.Count -eq 0) "$ayNot$(if ($aySorun.Count) { ' · ' + ($aySorun -join ' · ') })" `
            'beyin ayar   (gecersiz degeri duzelt ya da: beyin ayar <ad> -Sil)'
    }
} catch {
    # Denetim fonksiyonu yoksa/patlarsa satir KIRMIZI olmaz: ayar dosyasi
    # zorunlu degil ve motor onsuz tam calisir.
    Add-Row 'ayar dosyasi' $true "kontrol edilemedi: $($_.Exception.Message)" 'beyin ayar'
}

Add-Row 'Obsidian Bases' (($bases.Count -ge 1) -and ($baseSorun.Count -eq 0)) `
    $(if ($baseSorun.Count) { $baseSorun -join ' | ' } elseif ($bases.Count) { "$($bases.Count) base, filtreler notlarla eslesiyor" } else { 'base gorunumu yok' }) `
    'base filtresini notlarin gercek frontmatter alanina cevir (or. type == "session-summary", tags.contains("derlenmis"))'

$dash = Join-Path $Vault '10-command-center\dashboard.md'
$dashOk = $false
if (Test-Path -LiteralPath $dash) {
    $dc = Get-Content -LiteralPath $dash -Raw -Encoding UTF8
    $dashOk = (Test-BeyinMatch -Text $dc -Pattern '85-daylogs') -and (Test-BeyinMatch -Text $dc -Pattern '86-compiled')
}
Add-Row 'dashboard baglantilari' $dashOk `
    $(if ($dashOk) { 'makine bolgeleri dashboard''da gorunuyor' } else { 'dashboard makine bolgelerini gostermiyor' }) `
    'dashboard.md icine makine bolgesi bolumu ekle'

# ============================================================================
# DERIN: canli testler
# ============================================================================
if ($Derin) {
    # ============================================================================
    # UPSTREAM TAKIBI
    # ----------------------------------------------------------------------------
    # Bu motoru bir yukari akis deposundan turettiysen, oradaki duzeltmeleri
    # FARK ETME mekanizmasi olmadan "takip edecegim" bir dilekten ibarettir.
    # Olculdu: takip edilmeyen bir yukari akista dort commit gozden kacti ve
    # biri yerel motorda gercek bir kusuru ortaya cikardi.
    #
    # ISTEGE BAGLIDIR: yalniz .state\upstream-takip.json dosyasini kendin
    # olusturursan calisir - {"repo":"<sahip>/<depo>","reviewedSha":"<sha>"}.
    # Dosya yoksa kontrol sessizce atlanir; varsayilan durum budur.
    #
    # AG CAGRISI OLDUGU ICIN yalnizca -Derin altinda. Cevrimdisi olmak ya da gh
    # bulunmamak SORUN degildir: "kontrol edilemedi" der, gecer. Bir tani aracinin
    # ag yok diye kirmizi yanmasi, kendisi gurultu olur.
    # ============================================================================
    $takipDosya = Join-Path $p.ScrState 'upstream-takip.json'
    if (Test-Path -LiteralPath $takipDosya) {
        $takip = $null
        try { $takip = Get-Content -LiteralPath $takipDosya -Raw -Encoding UTF8 | ConvertFrom-Json } catch { }
        if ($takip -and $takip.repo -and $takip.reviewedSha) {
            if (Get-Command gh -ErrorAction SilentlyContinue) {
                # SADE --jq KULLANILIYOR ve bu bir olcum karari.
                # Ilk surum tek cagrida hem sha hem baslik cekiyordu:
                #     --jq '.[] | "\(.sha[0:7]) \(.commit.message | split("\n")[0])"'
                # Olculdu: bu ifade PowerShell'in argüman aktarimindan sag
                # cikmiyor, gh exit 1 veriyor ve kontrol "kontrol edilemedi"
                # diye SESSIZCE devre disi kaliyordu - yani faydali gorunup is
                # yapmayan bir kontrol. Ayni cagri '.[].sha' ile exit 0 veriyor.
                # Basliklar gerekiyorsa ayri, basit cagrilarla aliniyor.
                $shalar = $null
                $prevEap = $ErrorActionPreference
                try {
                    $ErrorActionPreference = 'Continue'
                    $shalar = & gh api ("repos/{0}/commits?per_page=20" -f $takip.repo) --jq '.[].sha' 2>$null
                } finally { $ErrorActionPreference = $prevEap }

                if ($LASTEXITCODE -eq 0 -and $shalar) {
                    $liste = @($shalar | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ })
                    $idx = -1
                    for ($i = 0; $i -lt $liste.Count; $i++) {
                        if ($liste[$i].StartsWith($takip.reviewedSha)) { $idx = $i; break }
                    }
                    if ($idx -lt 0) {
                        Add-Row 'upstream takibi' $true `
                            "incelenen $($takip.reviewedSha) son $($liste.Count) commit icinde yok (cok geride olabilir)" `
                            'upstream-takip.json icindeki reviewedSha guncel mi kontrol et'
                    } elseif ($idx -eq 0) {
                        Add-Row 'upstream takibi' $true "guncel ($($takip.repo) @ $($takip.reviewedSha))"
                    } else {
                        # Yalniz ilk uc yeni commit'in basligini cek - her biri ayri, sade cagri.
                        $basliklar = New-Object System.Collections.Generic.List[string]
                        foreach ($sha in $liste[0..([Math]::Min(2, $idx - 1))]) {
                            $msg = $null
                            try {
                                $ErrorActionPreference = 'Continue'
                                $msg = & gh api ("repos/{0}/commits/{1}" -f $takip.repo, $sha) --jq '.commit.message' 2>$null
                            } catch { } finally { $ErrorActionPreference = $prevEap }
                            $ilkSatir = if ($msg) { (@($msg)[0]) } else { '(baslik alinamadi)' }
                            $basliklar.Add(('{0} {1}' -f $sha.Substring(0, 7), $ilkSatir))
                        }
                        Add-Row 'upstream takibi' $false `
                            "$idx yeni commit: $($basliklar -join ' | ')" `
                            'her birini yerel motora karsi SINA, sonra upstream-takip.json icindeki reviewedSha degerini guncelle'
                    }
                } else {
                    Add-Row 'upstream takibi' $true 'kontrol edilemedi (ag yok veya gh yetkisiz) - sorun degil'
                }
            } else {
                Add-Row 'upstream takibi' $true 'gh CLI yok, kontrol atlandi'
            }
        }
    }

    # ARKA UC BAGIMSIZ (2026-09-18 denetimi). Eskiden kapi 'if ($claude)' idi:
    # yalniz-Codex bir makinede duman testi HIC kosmuyor, satir tabloya HIC
    # eklenmiyor ve butceden hicbir sey harcanmiyordu. Oysa Invoke-BeyinModel
    # zaten codex'e dusuyor (lib.ps1 Get-BeyinModelBackend) - yani AGENTS.md ve
    # SKILL.md'nin "claude yoksa codex exec" vaadi DOGRUYDU, kodu tek satirlik
    # bu kapi yalanliyordu. Belgeye degil KODA dokunuldu.
    $arkaUc = ''
    try { $arkaUc = [string](Get-BeyinModelBackend) } catch { $arkaUc = '' }
    if ($arkaUc) {
        $r = Invoke-BeyinModel -Prompt 'Yalniz su kelimeyi yaz: PONG' -Paths $p -Model 'haiku' -TimeoutSeconds 120
        $rUc = if ($r.PSObject.Properties['Backend'] -and $r.Backend) { [string]$r.Backend } else { $arkaUc }
        Add-Row "model duman testi ($rUc)" ($r.Ok -and (Test-BeyinMatch -Text $r.Out -Pattern 'PONG')) `
            $(if ($r.Ok) { "yanit alindi: $(($r.Out -replace '\s+',' ').Trim())" } else { "basarisiz: $($r.Reason) (exit=$($r.ExitCode))" }) `
            'oturum limiti veya kimlik dogrulama sorunu olabilir'
    } else {
        # Arka uc YOKLUGU hata degil: motor ozetleme disinda tam calisir.
        Add-Row 'model duman testi' $true 'ne claude ne codex CLI var - duman testi atlandi (butce harcanmadi)' ''
    }

    # brain-cli sema + denetim
    #
    # TASINABILIRLIK (2026-09-10): eskiden IKI mutlak yol gomuluydu
    # (kullanicinin masaustundeki bir arac klasoru). Baska bir makinede ya da
    # codex-chef baska bir yere klonlandiginda bu satir sessizce dusuyor ve
    # 'vault sema' kontrolu hicbir sey denetlemeden gecmis gorunuyordu.
    #
    # brain-cli ZORUNLU DEGILDIR: motor onsuz tam calisir, bu yalnizca ek bir
    # dogrulama katmanidir. Bulunamazsa satir bunu ACIKCA soyler - sessizce
    # yesil gostermez.
    #
    # Kesif sirasi: BEYIN_BRAIN_CLI ortam degiskeni > vault yani sira >
    # bilinen depo duzenleri (kullanici profiline gore) > PATH uzerinde komut.
    # TEK KAYNAK (2026-09-18): arama lib.ps1 Get-BeyinBrainCli'de. Eskiden bu
    # blok dortuncu kopyaydi ve BEYIN_BRAIN_CLI AYARINI hic okumuyordu.
    $bc = Get-BeyinBrainCli -Vault $Vault
    $cli = $bc.Yol
    if (-not $cli) {
        $g = Get-Command 'brain-cli' -ErrorAction SilentlyContinue
        if ($g) { $cli = $g.Source }
    }
    if (-not $cli) {
        Add-Row 'vault sema (brain-cli)' $true "brain-cli bulunamadi - bu kontrol ATLANDI (motor onsuz tam calisir)$(if ($bc.Belirsiz) { ' · ' + $bc.Belirsiz })" `
            'brain-cli bu depoda gelmez; elinde varsa: beyin ayar BEYIN_BRAIN_CLI <brain-cli.mjs yolu>'
    }
    if ($cli -and (Get-Command node -ErrorAction SilentlyContinue)) {
        try {
            $t = $Vault.Replace('\', '/')
            $out = (& node $cli status --target $t --json 2>&1 | Out-String)
            $j = $out | ConvertFrom-Json
            Add-Row 'vault sema (brain-cli)' ([bool]$j.ok) "hata: $(@($j.errors).Count)" `
                $(if (-not $j.ok) { 'sema-goc.ps1 ile frontmatter''i tasi' } else { '' })

            $out2 = (& node $cli audit --target $t --json 2>&1 | Out-String)
            $j2 = $out2 | ConvertFrom-Json
            $bl = @($j2.relationships.brokenLinks).Count
            Add-Row 'kirik link (brain-cli)' ($bl -eq 0) "kirik link: $bl, orphan: $(@($j2.relationships.orphanNotes).Count)" `
                $(if ($bl) { 'motor kaynakli linkleri duzelt' } else { '' })
        } catch {
            # TANI ARACININ KENDI KOR NOKTASI (2026-09-18 denetimi):
            # eskiden burada $true basiliyordu - yani brain-cli PATLADIGINDA
            # satir YESIL ve Duzeltme metni BOS oluyordu. Ustelik ayni catch
            # 'kirik link' satirini da yutuyordu: o satir tabloya HIC
            # eklenmiyordu ve kimse yoklugunu fark etmiyordu.
            $bcHata = [string]$_.Exception.Message
            Add-Row 'vault sema (brain-cli)' $false "calistirilamadi: $bcHata" `
                "brain-cli cagrisi dustu. Elle dene: node --version  ·  node ""$cli"" status --target ""$($Vault.Replace('\','/'))"" --json   Surekli duserse: beyin ayar BEYIN_BRAIN_CLI -Sil (kontrol atlanir, motor onsuz tam calisir)"
            Add-Row 'kirik link (brain-cli)' $false "calistirilamadi: $bcHata" `
                'Ayni brain-cli cagrisina bagli; ustteki satirin caresi bunu da cozer.'
        }
    }
}

# ============================================================================
# RAPOR
# ============================================================================
if ($Ozet) {
    # "Beynim ne durumda?" - tek komut, 8-12 satir, model cagrisi yok.
    $bad = @($rows | Where-Object { $_.Durum -eq 'SORUN' })
    function Detay([string]$ad) { $x = @($rows | Where-Object { $_.Kontrol -eq $ad }); if ($x.Count) { return $x[0].Detay } return '-' }
    "BEYIN DURUMU  ($((Get-Date).ToString('yyyy-MM-dd HH:mm', [Globalization.CultureInfo]::InvariantCulture)))  ·  motor v$(Get-BeyinVersion -Vault $Vault)"
    if ($bad.Count -eq 0) { "  Saglik      : temiz ($($rows.Count) kontrol)" }
    else { "  Saglik      : $($bad.Count) sorun / $($rows.Count) kontrol -> " + (($bad | ForEach-Object { $_.Kontrol }) -join ', ') }
    "  Butce       : $(Detay 'gunluk butce')"
    "  Is kuyrugu  : $(Detay 'is kuyrugu') · derleme: $(Detay 'derleme kuyrugu')"
    "  Makine      : $(Detay '85-daylogs') · $(Detay '86-compiled')"
    "  Kuratorlu   : $(Detay 'kuratorlu katman')"
    "  Kayip kapisi: $(Detay 'buyuk transkript') · $(Detay 'yetim adaylari (7 gun)')"
    "  Kurtarma    : $(Detay 'yedek tazeligi') · $(Detay 'kurtarma yedekliligi')"
    "  Ajan esligi : $(Detay 'ajan esligi')"
    "  Makbuz      : $(Detay 'makbuz (24 saat)') · $(Detay 'sifir bayt yazimi')"
    "  Niyet       : $(Detay 'niyet')"
    "  Bahcivan    : $(Detay 'olu kavram')"
    "  Disk        : $(Detay 'disk')"
    "  Zamanlayici : $(Detay 'zamanlanmis gorevler')"
    "  Geri getirme: $(Detay 'geri getirme indeksi') · $(Detay 'ikiz kavram')"
    "  Capraz bag  : $(Detay 'capraz baglanti')"
    "  Not guncel  : $(Detay 'not guncelligi')"
    "  Kaynak alimi: $(Detay 'kaynak alimi')"
    "  Embedding   : $(Detay 'embedding')"
    "  Motor surumu: $(Detay 'motor guncelligi')"
    "  Ayarlar     : $(Detay 'ayar dosyasi')"
    ''
    'DEVAM NOKTALARI (86-compiled/son-durum.md, turetilmis)'
    try {
        $sdF = Join-Path $p.Compiled 'son-durum.md'
        if (Test-Path -LiteralPath $sdF) {
            $sdRaw = Get-Content -LiteralPath $sdF -Raw -Encoding UTF8
            $mSd = [regex]::Match($sdRaw, '(?ms)^## Devam noktalari\r?\n(.*?)(?=\r?\n## )')
            if ($mSd.Success) {
                foreach ($ln in @(($mSd.Groups[1].Value -split "`n") | Where-Object { $_.Trim() })) {
                    if ($ln -match '^\|\s*---') { continue }
                    "  $($ln.Trim())"
                }
            } else { '  (son-durum.md eski bicimde - bir sonraki oturum acilisinda yenilenir)' }
        } else { '  (son-durum.md yok)' }
    } catch { '  (son-durum.md okunamadi)' }
    if ($bad.Count -gt 0) {
        ''
        'SORUNLAR'
        foreach ($b in $bad) { "  - $($b.Kontrol): $($b.Detay)$(if ($b.Duzeltme) { "  ->  $($b.Duzeltme)" })" }
    }
    ''
    'Tam tablo icin: -Ozet olmadan calistir.'
    exit 0
}

$rows | Format-Table -AutoSize -Wrap
''
$bad = @($rows | Where-Object { $_.Durum -eq 'SORUN' })
if ($bad.Count -eq 0) {
    "TANI: saglikli ($($rows.Count) kontrol)"
} else {
    "TANI: $($bad.Count) sorun / $($rows.Count) kontrol"
    ''
    'Sorunlu kontroller:'
    foreach ($b in $bad) { "  - $($b.Kontrol): $($b.Detay)$(if ($b.Duzeltme) { "  ->  $($b.Duzeltme)" })" }
}
