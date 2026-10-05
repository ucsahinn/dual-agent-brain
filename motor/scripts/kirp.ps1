# kirp.ps1 - 80-memory dosyalarini KAYIPSIZ arsivleyerek kisa tutar.
#
# NEDEN (2026-10-05): Claude Code kanca baglamini 10.000 karakterde kesiyor;
# current-context.md 43 KB, active-threads.md 24 KB olmustu ve acilista
# modele yalniz ilk 2 KB ulasiyordu. Avenoxbeyin ayni sorunu "Last-Session 94K
# karaktere cikti" diye yasamis; cozumu olculebilir sinir + kayipsiz arsiv.
#
# NE YAPAR: current-context.md'deki '## YYYY-MM-DD ...' tarihli bolumlerden
# -Gun'den (varsayilan 30) eski olanlari 80-memory/arsiv/current-context-arsiv.md
# dosyasina (basa, tarih damgali) tasir; active-threads.md tablosunda en yeni
# tarihi -Gun'den eski olan satirlari 80-memory/arsiv/active-threads-arsiv.md
# dosyasina tasir. Tarihsiz bolum/satirlara DOKUNMAZ ('## Odak', 'Acik sinirlar').
#
# KURATORLU BOLGE: 80-memory onizleme-gerektirir. Bu betik VARSAYILAN OLARAK
# KURU calisir ve tam plani basar - onizleme budur. Yazmak icin -Uygula; o
# karari ajan degil kullanici verir.
#
# Kullanim:
#   beyin kirp                 plan (hicbir sey yazmaz)
#   beyin kirp -Gun 45         45 gunden eski bolumler
#   beyin kirp -Uygula         plani uygular (once git durumu temiz olsun)

param(
    [string]$Vault = $(if ($env:BEYIN_VAULT) { $env:BEYIN_VAULT } else { Split-Path (Split-Path $PSScriptRoot -Parent) -Parent }),
    [int]$Gun = 30,
    [switch]$Uygula,
    [switch]$Json
)

$ErrorActionPreference = 'SilentlyContinue'
$vaultOk = $false
try { $vaultOk = [bool]($Vault -and (Test-Path -LiteralPath $Vault -PathType Container) -and (Test-Path -LiteralPath (Join-Path $Vault 'motor\hooks\lib.ps1'))) } catch { }
if (-not $vaultOk) { Write-Output "HATA: vault degil (motor\hooks\lib.ps1 yok): '$Vault'"; exit 2 }
. (Join-Path $Vault 'motor\hooks\lib.ps1')
$p  = Get-BeyinPaths -Vault $Vault
$sw = [Diagnostics.Stopwatch]::StartNew()
if ($Gun -lt 7) { $Gun = 7 }
$sinir = (Get-Date).Date.AddDays(-$Gun)
$arsivDir = Join-Path $p.Memory 'arsiv'
$damga = (Get-Date).ToString('yyyy-MM-dd')
$inv = [cultureinfo]::InvariantCulture

function Read-Raw([string]$Yol) {
    $t = [System.IO.File]::ReadAllText($Yol, [System.Text.Encoding]::UTF8)
    return ($t -replace ('^' + [char]0xFEFF), '')
}
function Son-Tarih([string]$Metin) {
    $en = $null
    foreach ($m in [regex]::Matches($Metin, '\b(20\d{2})-(\d{2})-(\d{2})\b')) {
        try { $d = [datetime]::ParseExact($m.Value, 'yyyy-MM-dd', $inv); if (-not $en -or $d -gt $en) { $en = $d } } catch { }
    }
    return $en
}
function Arsive-Ekle([string]$Yol, [string]$Baslik, [string[]]$Parcalar) {
    # Arsiv dosyasinin BASINA eklenir (en yeni ustte); dosya yoksa baslikla acilir.
    $eski = ''
    if (Test-Path -LiteralPath $Yol) { $eski = Read-Raw $Yol }
    $yeni = "## [arsiv $damga] $Baslik`n`n" + (($Parcalar -join "`n`n").Trim()) + "`n`n"
    if (-not $eski) { $eski = "# $Baslik arsivi`n`nBu dosya 'beyin kirp' tarafindan kayipsiz arsivlemeyle dolar; en yeni blok ustte.`n`n" }
    $m = [regex]::Match($eski, '(?m)^## \[arsiv ')
    $out = if ($m.Success) { $eski.Substring(0, $m.Index) + $yeni + $eski.Substring($m.Index) } else { $eski.TrimEnd() + "`n`n" + $yeni }
    Write-BeyinText -Path $Yol -Text $out
}

$plan = [ordered]@{ v = 1; ts = (Get-Date).ToString('o'); gun = $Gun; uygula = [bool]$Uygula; currentContext = @(); activeThreads = @(); kazanc = 0 }

# --- 1) current-context.md: tarihli '## ' bolumleri ------------------------------
$ccYol = Join-Path $p.Memory 'current-context.md'
$ccTasinan = New-Object System.Collections.Generic.List[string]
$ccKalanMetin = ''
if (Test-Path -LiteralPath $ccYol) {
    $ham = Read-Raw $ccYol
    $nl = if ($ham.Contains("`r`n")) { "`r`n" } else { "`n" }
    $ms = @([regex]::Matches($ham, '(?m)^## .*$'))
    $bolumler = New-Object System.Collections.Generic.List[object]
    for ($i = 0; $i -lt $ms.Count; $i++) {
        $bas = $ms[$i].Index
        $son = if ($i + 1 -lt $ms.Count) { $ms[$i + 1].Index } else { $ham.Length }
        $baslik = $ms[$i].Value.Trim()
        $md = [regex]::Match($baslik, '^## (20\d{2}-\d{2}-\d{2})')
        $tarih = $null
        if ($md.Success) { try { $tarih = [datetime]::ParseExact($md.Groups[1].Value, 'yyyy-MM-dd', $inv) } catch { } }
        $bolumler.Add([pscustomobject]@{ Baslik = $baslik; Tarih = $tarih; Metin = $ham.Substring($bas, $son - $bas); Bas = $bas; Son = $son })
    }
    $sb = New-Object System.Text.StringBuilder
    $onceki = 0
    foreach ($b in $bolumler) {
        [void]$sb.Append($ham.Substring($onceki, $b.Bas - $onceki))
        if ($b.Tarih -and $b.Tarih -lt $sinir) {
            $ccTasinan.Add($b.Metin.TrimEnd())
            $plan.currentContext += [ordered]@{ baslik = $b.Baslik; tarih = $b.Tarih.ToString('yyyy-MM-dd'); karakter = $b.Metin.Length }
            $plan.kazanc += $b.Metin.Length
        } else { [void]$sb.Append($b.Metin) }
        $onceki = $b.Son
    }
    [void]$sb.Append($ham.Substring($onceki))
    $ccKalanMetin = $sb.ToString()
    if ($ccTasinan.Count -gt 0) {
        # Kalan dosyada arsive isaret: model gerekirse acsin.
        $isaret = "$nl> Eski tarihli bolumler 80-memory/arsiv/current-context-arsiv.md icinde (beyin kirp, $damga).$nl"
        if ($ccKalanMetin -notmatch 'current-context-arsiv\.md') {
            $mo = [regex]::Match($ccKalanMetin, '(?m)^## Odak.*$')
            if ($mo.Success) { $ccKalanMetin = $ccKalanMetin.Insert($mo.Index + $mo.Length, $isaret) } else { $ccKalanMetin = $ccKalanMetin.TrimEnd() + $nl + $isaret }
        }
    }
}

# --- 2) active-threads.md: tablo satirlari ----------------------------------------
$atYol = Join-Path $p.Memory 'active-threads.md'
$atTasinan = New-Object System.Collections.Generic.List[string]
$atKalanMetin = ''
if (Test-Path -LiteralPath $atYol) {
    $ham = Read-Raw $atYol
    $nl = if ($ham.Contains("`r`n")) { "`r`n" } else { "`n" }
    $satirlar = @($ham -split "\r?\n")
    $kalan = New-Object System.Collections.Generic.List[string]
    $tabloSatir = 0
    foreach ($ln in $satirlar) {
        if (-not $ln.StartsWith('|')) { $kalan.Add($ln); continue }
        $tabloSatir++
        if ($tabloSatir -le 2) { $kalan.Add($ln); continue }
        $t = Son-Tarih $ln
        if ($t -and $t -lt $sinir) {
            $atTasinan.Add($ln)
            $ad = ([regex]::Match($ln, '^\|\s*([^|]+?)\s*\|')).Groups[1].Value
            $plan.activeThreads += [ordered]@{ baslik = $ad; tarih = $t.ToString('yyyy-MM-dd'); karakter = $ln.Length }
            $plan.kazanc += $ln.Length
        } else { $kalan.Add($ln) }
    }
    $atKalanMetin = ($kalan -join $nl)
}

# --- 3) Uygula ya da plan ----------------------------------------------------------
$yazildi = $false
if ($Uygula -and ($ccTasinan.Count -gt 0 -or $atTasinan.Count -gt 0)) {
    New-Item -ItemType Directory -Force -Path $arsivDir | Out-Null
    if ($ccTasinan.Count -gt 0) {
        Arsive-Ekle -Yol (Join-Path $arsivDir 'current-context-arsiv.md') -Baslik 'current-context' -Parcalar $ccTasinan.ToArray()
        Write-BeyinText -Path $ccYol -Text $ccKalanMetin
    }
    if ($atTasinan.Count -gt 0) {
        $tabloBas = @()
        try { $tabloBas = @((Read-Raw $atYol) -split "\r?\n" | Where-Object { $_.StartsWith('|') } | Select-Object -First 2) } catch { }
        Arsive-Ekle -Yol (Join-Path $arsivDir 'active-threads-arsiv.md') -Baslik 'active-threads' -Parcalar @(((@($tabloBas) + @($atTasinan)) -join "`n"))
        Write-BeyinText -Path $atYol -Text $atKalanMetin
    }
    $yazildi = $true
    Write-BeyinLog -Vault $Vault -Message "kirp: current-context $($ccTasinan.Count) bolum, active-threads $($atTasinan.Count) satir arsivlendi ($($plan.kazanc) karakter)"
}
Write-BeyinMakbuz -Paths $p -Script 'kirp' -Outcome $(if ($yazildi) { 'KIRP_UYGULANDI' } elseif ($Uygula) { 'KIRP_BOS' } else { 'KIRP_PLAN' }) `
    -DurationMs $sw.ElapsedMilliseconds -Note "gun=$Gun; cc=$($ccTasinan.Count); at=$($atTasinan.Count); kazanc=$($plan.kazanc)"

if ($Json) { $plan | ConvertTo-Json -Depth 5; exit 0 }
"KIRP $(if ($yazildi) { '- UYGULANDI' } else { '- PLAN (hicbir sey yazilmadi)' })  (esik: $Gun gunden eski, $($sinir.ToString('yyyy-MM-dd')) oncesi)"
"  current-context.md : $($ccTasinan.Count) tarihli bolum -> 80-memory/arsiv/current-context-arsiv.md"
foreach ($b in $plan.currentContext) { "    - $($b.baslik.Substring(0, [math]::Min(80, $b.baslik.Length)))  ($($b.karakter) kr)" }
"  active-threads.md  : $($atTasinan.Count) satir -> 80-memory/arsiv/active-threads-arsiv.md"
foreach ($b in $plan.activeThreads) { "    - $($b.baslik) (son tarih $($b.tarih), $($b.karakter) kr)" }
"  Toplam kazanc      : $($plan.kazanc) karakter"
if (-not $Uygula) { "  Uygulamak icin: beyin kirp -Uygula   (kuratorlu bolge: once bu plani oku, karar senin)" }
exit 0
