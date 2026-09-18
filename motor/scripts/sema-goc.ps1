# sema-goc.ps1 - Motorun yazdigi/kurdugu notlarin frontmatter'ini vault semasina
# (codex-chef.brain-note.v1) tasir. BIR KERELIK gectir; yeni yazmalar zaten
# dogru sema ile uretiliyor.
#
# Neden gerekli: motorun ilk surumu id / updated / source_refs alanlarini
# yazmiyor, `type: "daylog"` ve `confidence: "machine-generated"` gibi semada
# OLMAYAN enum degerleri kullaniyordu. brain-cli status 45 hata veriyordu ve
# hepsi motor dosyalarindandi -- kullanicinin gercek tani kapisi kirmizi kaliyordu.
#
# FRONTMATTER SIFIRDAN KURULMAZ (2026-09-17, bagimsiz denetim - F3).
# Onceki surum frontmatter'i bilinen 13 alandan yeniden insa ediyordu. Olculdu:
#   - `kaynak_oturum` + `elle_eklenen` alanli bir not 615 -> 556 bayt: iki alan
#     da SESSIZCE SILINDI, kuru kosu raporu hangi alanlarin yok olacagini
#     soylemiyordu.
#   - Blok bicimli `source_refs:` (ardindan '  - "..."' satirlari) + `aliases` +
#     `cssclasses` tasiyan bir not 536 -> 443 bayt: source_refs UYDURMA bir
#     degerle (`["engine:beyin"]`) DEGISTIRILDI, kalan iki alan silindi.
# Ikisi de geri donussuzdu. Bu surum:
#   (a) frontmatter'i SIRALI GIRDILERE ayirir; tanimadigi alani OLDUGU GIBI korur,
#   (b) cok satirli YAML listesini gecerli frontmatter sayar ve ASLA uydurma
#       degerle degistirmez; source_refs VARSA hic dokunulmaz,
#   (c) degisecek/eklenecek alanlari kuru kosu raporunda ADIYLA yazar,
#   (d) guvenle ayristiramadigi notu ATLAR ve SEBEBINI SOYLER (sessiz yeniden
#       yazmaktansa dokunmamak).
# Gecerli bir degeri olan alan HIC ELLENMEZ (tirnak bicimi bile degismez):
# boylece dosya baytlari gereksiz yere oynamaz.
#
# Korunanlar: mevcut id ve created degerleri (varsa) DEGISTIRILMEZ; yalnizca
# eksikler tamamlanir ve gecersiz enum degerleri gecerli karsiligiyla degistirilir.
# Govde (frontmatter sonrasi) HIC dokunulmaz.
#
# MAKBUZ (2026-09-17, denetim - F5): bu betik NOT ICERIGINI degistiriyor; artik
# diger yazicilarla ayni sozlesmeyle makbuz birakir (kuru kosuda da, ayri outcome).
#
# Varsayilan KURU CALISMA. Uygulamak icin -Uygula.

param(
    # TASINABILIRLIK (2026-09-10): vault yolu artik GOMULU DEGIL.
    # Oncelik: -Vault parametresi > BEYIN_VAULT ortam degiskeni > betigin kendi
    # konumundan turetme (<vault>\motor\scripts\<bu betik>.ps1 oldugu icin
    # iki seviye yukarisi vault'tur). Boylece motor baska bir makinede, baska
    # bir kullanici adiyla ve baska bir vault konumunda TEK SATIR DEGISMEDEN
    # calisir. Gomulu yol ayni zamanda depoya kisisel veri sizdiriyordu.
    [string]$Vault = $(if ($env:BEYIN_VAULT) { $env:BEYIN_VAULT } else { Split-Path (Split-Path $PSScriptRoot -Parent) -Parent }),
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
if (-not $vaultOk) { Write-Output "HATA: vault degil (motor\hooks\lib.ps1 yok): '$Vault'  - konumsal arguman -Vault'a baglanir; uygulamak icin -Uygula kullan"; exit 2 }
. (Join-Path $Vault 'motor\hooks\lib.ps1')
$p = Get-BeyinPaths -Vault $Vault
$sw = [Diagnostics.Stopwatch]::StartNew()

# Semada gecerli degerler (brain-foundation.mjs'ten)
$validType = @('capture','project','goal','decision','knowledge','research','profile','preference','active-thread','session-summary')
$validConf = @('confirmed','observed','inferred','unverified')

# Hedef dosyalar: motorun yazdigi/kurdugu her sey
$targets = New-Object System.Collections.Generic.List[string]
foreach ($f in @(Get-ChildItem -LiteralPath $p.Daylogs -Filter '*.md' -File -ErrorAction SilentlyContinue)) { $targets.Add($f.FullName) }
foreach ($f in @(Get-ChildItem -LiteralPath $p.Compiled -Recurse -Filter '*.md' -File -ErrorAction SilentlyContinue)) { $targets.Add($f.FullName) }
$extra = Join-Path $Vault '10-command-center\BASLA-BURADAN.md'
if (Test-Path -LiteralPath $extra) { $targets.Add($extra) }

if ($targets.Count -eq 0) {
    'Tasinacak dosya yok.'
    Write-BeyinMakbuz -Paths $p -Script 'sema-goc' -Outcome 'SEMA_HEDEF_YOK' -DurationMs $sw.ElapsedMilliseconds -Note 'hedef dosya yok'
    exit 0
}

# =============================================================================
# Frontmatter ayristirici
# =============================================================================
function Split-SemaFmGirdi {
    # Frontmatter metnini SIRALI girdilere ayirir.
    # Bir girdi = kok seviyedeki 'anahtar:' satiri + onu izleyen GIRINTILI/BOS/
    # yorum satirlari (cok satirli YAML listesi ya da blok skaler bu sekilde
    # tek parca halinde korunur).
    # Donus: @{ Ok; Sira=List[string]; Map=hashtable; Sebep }
    param([string]$Fm)
    $sira = New-Object System.Collections.Generic.List[string]
    $map  = @{}
    $suan = $null
    $kokRx = [regex]'^([A-Za-z_][A-Za-z0-9_.\-]*):(\s.*)?$'
    foreach ($ln in @($Fm -split "`r?`n")) {
        $m = $kokRx.Match($ln)
        if ($m.Success) {
            $anahtar = $m.Groups[1].Value
            if ($map.ContainsKey($anahtar)) {
                return @{ Ok = $false; Sebep = "ayni anahtar iki kez: $anahtar" }
            }
            $girdi = @{ Anahtar = $anahtar; Satirlar = (New-Object System.Collections.Generic.List[string]) }
            $girdi.Satirlar.Add([string]$ln)
            $map[$anahtar] = $girdi
            $sira.Add($anahtar)
            $suan = $girdi
            continue
        }
        # Girintili / bos / yorum satiri: icinde bulundugumuz girdiye aittir.
        if ($ln -match '^[ \t]' -or [string]::IsNullOrWhiteSpace($ln) -or $ln.TrimStart().StartsWith('#')) {
            if ($null -eq $suan) {
                if ([string]::IsNullOrWhiteSpace($ln)) { continue }
                return @{ Ok = $false; Sebep = "anahtarsiz satir: $($ln.Trim())" }
            }
            $suan.Satirlar.Add([string]$ln)
            continue
        }
        # Kok seviyede anahtar OLMAYAN bir satir: guvenle ayristiramayiz.
        return @{ Ok = $false; Sebep = "cozulemeyen satir: $($ln.Trim())" }
    }
    return @{ Ok = $true; Sira = $sira; Map = $map; Sebep = '' }
}

function Test-SemaTekSatir {
    # Girdi tek satirlik bir 'anahtar: deger' mi? (Sondaki bos satirlar sayilmaz.)
    param($Girdi)
    for ($i = 1; $i -lt $Girdi.Satirlar.Count; $i++) {
        if (-not [string]::IsNullOrWhiteSpace($Girdi.Satirlar[$i])) { return $false }
    }
    return $true
}

function Get-SemaDeger {
    # Tek satirlik girdinin degeri (tirnaklar soyulmus). Cok satirliysa $null.
    param($Girdi)
    if ($null -eq $Girdi) { return $null }
    if (-not (Test-SemaTekSatir -Girdi $Girdi)) { return $null }
    $m = [regex]::Match([string]$Girdi.Satirlar[0], '^[^:]+:\s*(.*)$')
    if (-not $m.Success) { return $null }
    return $m.Groups[1].Value.Trim().Trim('"')
}

$isoNow = Get-BeyinIsoNow
$changed = 0
$atlandi = 0
$report = New-Object System.Collections.Generic.List[string]
$mkFiles = New-Object System.Collections.Generic.List[object]

foreach ($path in $targets) {
    # OKUMA KENDI BASINA BIR HATA YOLU (2026-09-18, kosarak olculdu).
    # Eskiden bu satir try/catch DISINDAYDI ve $ErrorActionPreference
    # 'SilentlyContinue' altinda okuma duserse ATAMA HIC YAPILMIYORDU: $raw
    # BIR ONCEKI DONGU TURUNDAN KALAN icerigi tutuyordu. Sonuc: okunamayan
    # dosya, komsusunun govdesi ve komsusunun 'id' degeriyle YENIDEN
    # YAZILIYORDU (satir ~269 Write-BeyinText -Path $path). Geri donusu yok,
    # ustelik cift 'id' semayi da bozuyordu.
    #
    # Ayrica ilk hedefte duserse $raw tanimsiz kalip "frontmatter yok"
    # deniyordu - YANLIS SEBEP - ve $atlandi artmadigi icin rapor "Atlanan: 0"
    # basip sonucu SEMA_OK yaziyordu.
    $raw = $null
    try {
        $raw = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
    } catch {
        $report.Add("ATLANDI (okunamadi - $($_.Exception.Message)): $(Split-Path -Leaf $path)")
        $atlandi++
        continue
    }
    if ($null -eq $raw) {
        $report.Add("ATLANDI (okunamadi): $(Split-Path -Leaf $path)")
        $atlandi++
        continue
    }
    $raw = $raw -replace ('^' + [char]0xFEFF), ''

    $m = [regex]::Match($raw, '(?s)^---\r?\n(.*?)\r?\n---\r?\n(.*)$')
    if (-not $m.Success) {
        $report.Add("ATLANDI (frontmatter yok): $(Split-Path -Leaf $path)")
        $atlandi++
        continue
    }
    $fm   = $m.Groups[1].Value
    $body = $m.Groups[2].Value
    $rel  = $path.Replace($Vault + '\', '').Replace('\', '/')

    $ay = Split-SemaFmGirdi -Fm $fm
    if (-not $ay.Ok) {
        # SESSIZ YENIDEN YAZMAKTANSA DOKUNMAMAK: ne oldugu soylenir.
        $report.Add("ATLANDI (frontmatter ayristirilamadi - $($ay.Sebep)): $rel")
        $atlandi++
        continue
    }
    $sira = $ay.Sira
    $map  = $ay.Map

    # --- hedef degerler: yalniz EKSIK ya da GECERSIZ olan alanlar hesaplanir ---
    $istek = New-Object System.Collections.Generic.List[object]   # @{ Anahtar; Deger; Sebep }

    $v = Get-SemaDeger -Girdi $map['brain_schema']
    if ($v -ne 'codex-chef.brain-note.v1') { $istek.Add(@{ Anahtar = 'brain_schema'; Deger = 'codex-chef.brain-note.v1'; Sebep = 'sema etiketi' }) }

    $v = Get-SemaDeger -Girdi $map['id']
    if (-not $v -or $v -notmatch '^brn_[0-9a-fA-F-]{36}$') { $istek.Add(@{ Anahtar = 'id'; Deger = (New-BeyinNoteId); Sebep = 'gecersiz/eksik id' }) }

    $v = Get-SemaDeger -Girdi $map['type']
    if ($validType -notcontains $v) {
        # daylog -> session-summary (anlami birebir uyuyor), digerleri -> knowledge
        $yeniType = if ($v -eq 'daylog') { 'session-summary' } else { 'knowledge' }
        $istek.Add(@{ Anahtar = 'type'; Deger = $yeniType; Sebep = "type: '$v' -> '$yeniType'" })
    }

    $v = Get-SemaDeger -Girdi $map['confidence']
    if ($validConf -notcontains $v) {
        # machine-generated semada yok; makine uretimi = dogrulanmamis
        $yeniConf = if ($rel -like '10-command-center/*') { 'confirmed' } else { 'unverified' }
        $istek.Add(@{ Anahtar = 'confidence'; Deger = $yeniConf; Sebep = "confidence: '$v' -> '$yeniConf'" })
    }

    $v = Get-SemaDeger -Girdi $map['title']
    if (-not $v) { $istek.Add(@{ Anahtar = 'title'; Deger = ([IO.Path]::GetFileNameWithoutExtension($path) -replace '"',''); Sebep = 'baslik eksik' }) }

    $v = Get-SemaDeger -Girdi $map['status'];     if (-not $v) { $istek.Add(@{ Anahtar = 'status';     Deger = 'active'; Sebep = 'eksik' }) }
    $v = Get-SemaDeger -Girdi $map['privacy'];    if (-not $v) { $istek.Add(@{ Anahtar = 'privacy';    Deger = 'local';  Sebep = 'eksik' }) }
    $v = Get-SemaDeger -Girdi $map['project_id']; if (-not $v) { $istek.Add(@{ Anahtar = 'project_id'; Deger = 'brain';  Sebep = 'eksik' }) }

    $v = Get-SemaDeger -Girdi $map['retention']
    if (-not $v) {
        $yeniRet = if ($rel -like '10-command-center/*') { 'permanent' } else { 'review-90d' }
        $istek.Add(@{ Anahtar = 'retention'; Deger = $yeniRet; Sebep = 'eksik' })
    }

    $v = Get-SemaDeger -Girdi $map['created']
    if (-not $v -or $v -notmatch '^\d{4}-\d{2}-\d{2}T') {
        $yeniCreated = if ($v -match '^(\d{4}-\d{2}-\d{2})$') { $Matches[1] + 'T00:00:00.000Z' } else { $isoNow }
        $istek.Add(@{ Anahtar = 'created'; Deger = $yeniCreated; Sebep = 'gecersiz/eksik tarih' })
    }

    $v = Get-SemaDeger -Girdi $map['updated']
    if (-not $v -or $v -notmatch '^\d{4}-\d{2}-\d{2}T') { $istek.Add(@{ Anahtar = 'updated'; Deger = $isoNow; Sebep = 'gecersiz/eksik tarih' }) }

    # source_refs: VARSA (tek satir ya da blok liste) HIC DOKUNULMAZ.
    # Koken bilgisi UYDURULMAZ; yalnizca hic yoksa notr bir deger eklenir.
    if (-not $map.ContainsKey('source_refs')) {
        $istek.Add(@{ Anahtar = 'source_refs'; Deger = '["engine:beyin"]'; Sebep = 'eksik'; Ham = $true })
    }

    if ($istek.Count -eq 0) { continue }

    # --- cok satirli bir alani DEGISTIRMEK gerekiyorsa: notu ATLA ve SOYLE ---
    $engel = ''
    foreach ($it in $istek) {
        if ($map.ContainsKey($it.Anahtar) -and -not (Test-SemaTekSatir -Girdi $map[$it.Anahtar])) { $engel = $it.Anahtar; break }
    }
    if ($engel) {
        $report.Add("ATLANDI (cok satirli alan guvenle degistirilemez: $engel): $rel")
        $atlandi++
        continue
    }

    # --- uygula: var olan girdinin SATIRINI degistir, yoksa SONA ekle ---
    $eklenen = New-Object System.Collections.Generic.List[string]
    $degisti = New-Object System.Collections.Generic.List[string]
    foreach ($it in $istek) {
        $satir = if ($it.Ham) { "$($it.Anahtar): $($it.Deger)" } else { "$($it.Anahtar): `"$($it.Deger)`"" }
        if ($map.ContainsKey($it.Anahtar)) {
            $map[$it.Anahtar].Satirlar[0] = $satir
            $degisti.Add("$($it.Anahtar) [$($it.Sebep)]")
        } else {
            $yeni = @{ Anahtar = $it.Anahtar; Satirlar = (New-Object System.Collections.Generic.List[string]) }
            $yeni.Satirlar.Add($satir)
            $map[$it.Anahtar] = $yeni
            $sira.Add($it.Anahtar)
            $eklenen.Add("$($it.Anahtar) [$($it.Sebep)]")
        }
    }

    # TANIMADIGIMIZ HER ALAN, SIRASI VE SATIRLARIYLA, OLDUGU GIBI GECER.
    $fmSatir = New-Object System.Collections.Generic.List[string]
    foreach ($a in $sira) { foreach ($l in $map[$a].Satirlar) { $fmSatir.Add([string]$l) } }
    $new = "---`n" + ($fmSatir -join "`n") + "`n---`n" + $body

    # Karsilastirma satir sonundan bagimsiz olmali: dosyalar LF, bazi
    # duzenleyiciler CRLF birakabiliyor. Sirf CRLF yuzunden yeniden yazma yok.
    $normYeni = ($new -replace "`r`n", "`n")
    $normEski = ($raw -replace "`r`n", "`n")
    if ($normYeni -eq $normEski) { continue }

    $changed++
    $detay = ''
    if ($eklenen.Count) { $detay += "  eklenen: $($eklenen -join ', ')" }
    if ($degisti.Count) { $detay += "  degisen: $($degisti -join ', ')" }
    $report.Add("GUNCELLENECEK: $rel$detay")
    $mkOnce = Measure-BeyinDosya -Path $path
    if ($Uygula) {
        Write-BeyinText -Path $path -Text $new
        $mkFiles.Add(@{ p = (ConvertTo-BeyinMakbuzYol -Paths $p -Path $path); b = $mkOnce; a = (Measure-BeyinDosya -Path $path) })
    } else {
        $mkFiles.Add(@{ p = (ConvertTo-BeyinMakbuzYol -Paths $p -Path $path); b = $mkOnce; a = $mkOnce })
    }
}

"Hedef dosya : $($targets.Count)"
"Degisecek   : $changed"
"Atlanan     : $atlandi (guvenle ayristirilamayan / cok satirli alan degisimi gereken not)"
''
$report | ForEach-Object { "  $_" }
''
$mkNot = "$($targets.Count) hedef, $changed degisecek, $atlandi atlandi"
if ($Uygula) {
    Write-BeyinLog -Vault $Vault -Message "sema-goc: $changed dosya vault semasina tasindi, $atlandi atlandi"
    Write-BeyinMakbuz -Paths $p -Script 'sema-goc' `
        -Outcome $(if ($atlandi -gt 0) { 'SEMA_KISMI' } elseif ($changed -gt 0) { 'SEMA_OK' } else { 'SEMA_ISYOK' }) `
        -Files @($mkFiles.ToArray()) -DurationMs $sw.ElapsedMilliseconds -Note $mkNot
    "$changed dosya guncellendi."
} else {
    Write-BeyinMakbuz -Paths $p -Script 'sema-goc' -Outcome 'SEMA_KURU' `
        -Files @($mkFiles.ToArray()) -DurationMs $sw.ElapsedMilliseconds -Note "KURU: $mkNot"
    'KURU CALISMA - hicbir dosya degismedi. Uygulamak icin -Uygula ekle.'
}
