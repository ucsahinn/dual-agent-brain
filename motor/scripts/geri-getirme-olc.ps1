# geri-getirme-olc.ps1 - Geri getirme (retrieval) icin DONDURULMUS holdout kapisi.
#
# NEDEN (2026-10-05): Laya'yi gercek vault verisinde %22,8 ile eleyen olcum tek
# seferlik bir Python betigiydi. Avenoxbeyin ayni isi SHA-256 ile dondurulmus
# bir fixture + CI kapisi olarak tutuyor; motorun geri getirme kurallari
# (kademeli kosinus esigi, ek soyucu, durdurma kelimeleri) degistikce
# regresyon GORUNUR olsun.
#
# Vaka = bir kavram notu: sorgu notun ilk paragrafindan turetilir (baslik
# haric), dogru cevap o notun kendisi. Vektor yolu (bge-m3) ve kelime yolu ayri
# olculur: rank-1 isabet, ilk-2 isabet, bos donus (abstain), gecikme p50.
#
# Kullanim:
#   beyin geri-getirme-olc              fixture varsa onu, yoksa deterministik ornegi kosar
#   beyin geri-getirme-olc -Dondur      fixture'i yeniden uretir (sha256 ile) - bilerek yapilir
#   beyin geri-getirme-olc -Vaka 40     ornek buyuklugu (fixture yokken)
#   beyin geri-getirme-olc -Esik 0.8    vektor rank-1 bu oranin altindaysa cikis 5
#   beyin geri-getirme-olc -Json

param(
    [string]$Vault = $(if ($env:BEYIN_VAULT) { $env:BEYIN_VAULT } else { Split-Path (Split-Path $PSScriptRoot -Parent) -Parent }),
    [int]$Vaka = 40,
    [double]$Esik = 0.8,
    [switch]$Dondur,
    [switch]$Json
)

$ErrorActionPreference = 'SilentlyContinue'
$vaultOk = $false
try { $vaultOk = [bool]($Vault -and (Test-Path -LiteralPath $Vault -PathType Container) -and (Test-Path -LiteralPath (Join-Path $Vault 'motor\hooks\lib.ps1'))) } catch { }
if (-not $vaultOk) { Write-Output "HATA: vault degil (motor\hooks\lib.ps1 yok): '$Vault'"; exit 2 }
. (Join-Path $Vault 'motor\hooks\lib.ps1')
$p  = Get-BeyinPaths -Vault $Vault
$sw = [Diagnostics.Stopwatch]::StartNew()
$fixtureDir = Join-Path $PSScriptRoot 'fixtures'
$fixture    = Join-Path $fixtureDir 'geri-getirme-holdout.json'
$conceptDir = Join-Path $p.Compiled 'concepts'

function Get-Sorgu([string]$Yol) {
    # Frontmatter ve '# Baslik' atilir; ilk dolu paragraf (en fazla 400 karakter) sorgu olur.
    try {
        $ham = [System.IO.File]::ReadAllText($Yol)
        $ham = $ham -replace ('^' + [char]0xFEFF), ''
        $m = [regex]::Match($ham, '(?s)\A---\r?\n.*?\r?\n---\r?\n?')
        $govde = if ($m.Success) { $ham.Substring($m.Length) } else { $ham }
        # MAKINE BOLUMU DISARIDA (olculdu 2026-10-05): '## Ilgili notlar' altindaki
        # 'Bu bolum MAKINE BAKIMLIDIR...' cumlesi sorgu olunca 11/40 vaka ayni
        # 'makine' notuna gidiyordu - motor degil, uretec hataliydi.
        $mi = [regex]::Match($govde, '(?m)^##[ \t]*[Iiİı]lgili notlar')
        if ($mi.Success) { $govde = $govde.Substring(0, $mi.Index) }
        foreach ($para in ($govde -split "(\r?\n){2,}")) {
            $t = $para.Trim()
            if (-not $t -or $t.StartsWith('#') -or $t.StartsWith('---') -or $t.StartsWith('|') -or $t.StartsWith('>') -or $t.StartsWith('- [[')) { continue }
            if ($t -match 'MAKINE BAKIMLIDIR|yakinlik 0\.\d') { continue }
            $t = ($t -replace '\s+', ' ')
            if ($t.Length -lt 40) { continue }
            if ($t.Length -gt 400) { $t = $t.Substring(0, 400) }
            return $t
        }
    } catch { }
    return ''
}
function Sha256([string]$S) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($S))) -replace '-', '').ToLowerInvariant() } finally { $sha.Dispose() }
}

# --- 1) Vakalar: fixture ya da deterministik ornek ------------------------------
$vakalar = New-Object System.Collections.Generic.List[object]
$kaynak = ''
if ((Test-Path -LiteralPath $fixture) -and -not $Dondur) {
    try {
        $fx = Get-Content -LiteralPath $fixture -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($v in @($fx.vakalar)) { $vakalar.Add([pscustomobject]@{ dosya = [string]$v.dosya; sorgu = [string]$v.sorgu; sha = [string]$v.sha }) }
        $kaynak = "fixture ($($fx.dondurma), $($vakalar.Count) vaka)"
    } catch { $vakalar.Clear() }
}
if ($vakalar.Count -eq 0) {
    $notlar = @(Get-ChildItem -LiteralPath $conceptDir -Filter '*.md' -File -ErrorAction SilentlyContinue | Sort-Object Name)
    if ($notlar.Count -eq 0) { Write-Output 'OLC_HATA_NOT kavram notu yok'; exit 2 }
    if ($Vaka -lt 5) { $Vaka = 5 }
    $adim = [math]::Max(1, [math]::Floor($notlar.Count / $Vaka))
    for ($i = 0; $i -lt $notlar.Count -and $vakalar.Count -lt $Vaka; $i += $adim) {
        $q = Get-Sorgu $notlar[$i].FullName
        if (-not $q) { continue }
        $vakalar.Add([pscustomobject]@{ dosya = $notlar[$i].Name; sorgu = $q; sha = (Sha256 $q) })
    }
    $kaynak = "deterministik ornek (her $adim. not, $($vakalar.Count) vaka)"
    if ($Dondur) {
        New-Item -ItemType Directory -Force -Path $fixtureDir | Out-Null
        $fxObj = [ordered]@{ v = 1; dondurma = (Get-Date).ToString('yyyy-MM-dd'); not = $notlar.Count; vakalar = @($vakalar | ForEach-Object { [ordered]@{ dosya = $_.dosya; sorgu = $_.sorgu; sha = $_.sha } }) }
        Write-BeyinText -Path $fixture -Text ($fxObj | ConvertTo-Json -Depth 5)
        $kaynak += ' -> DONDURULDU: ' + $fixture
    }
}
if ($vakalar.Count -eq 0) { Write-Output 'OLC_HATA_VAKA sorgu uretilebilen not yok'; exit 2 }

# Fixture butunlugu: sorgu metni sha ile dogrulanir (elle oynanmis fixture sahte yesil vermesin).
$bozuk = 0
foreach ($v in $vakalar) { if ((Sha256 $v.sorgu) -ne $v.sha) { $bozuk++ } }

# --- 2) Olcum ------------------------------------------------------------------
$vekHazir = Test-BeyinVectorReady -Paths $p
$vekR1 = 0; $vekR2 = 0; $vekBos = 0; $vekMs = New-Object System.Collections.Generic.List[long]
$kelR1 = 0; $kelR2 = 0; $kelBos = 0
$eksik = 0
$hatalar = New-Object System.Collections.Generic.List[string]
foreach ($v in $vakalar) {
    if (-not (Test-Path -LiteralPath (Join-Path $conceptDir $v.dosya))) { $eksik++; continue }
    if ($vekHazir) {
        $t0 = $sw.ElapsedMilliseconds
        $vr = Find-BeyinRelevantConceptsVec -Paths $p -Query $v.sorgu -EnFazla 5 -TimeoutMs 3000
        $vekMs.Add($sw.ElapsedMilliseconds - $t0)
        $liste = @()
        if ($vr.Ok) { $liste = @($vr.Sonuc | ForEach-Object { [string]$_.Item.dosya }) }
        if ($liste.Count -eq 0) { $vekBos++ }
        elseif ($liste[0] -eq $v.dosya) { $vekR1++; $vekR2++ }
        elseif ($liste.Count -gt 1 -and $liste[1] -eq $v.dosya) { $vekR2++ }
        else { if ($hatalar.Count -lt 10) { $hatalar.Add("vektor: $($v.dosya) -> $($liste[0])") } }
    }
    $kl = @(Find-BeyinRelevantConcepts -Paths $p -Query $v.sorgu -EnFazla 5 | ForEach-Object { [string]$_.Item.dosya })
    if ($kl.Count -eq 0) { $kelBos++ }
    elseif ($kl[0] -eq $v.dosya) { $kelR1++; $kelR2++ }
    elseif ($kl.Count -gt 1 -and $kl[1] -eq $v.dosya) { $kelR2++ }
}
$n = $vakalar.Count - $eksik
function Oran($a) { if ($n -gt 0) { return [math]::Round($a / $n, 3) } else { return 0 } }
$p50 = 0
if ($vekMs.Count -gt 0) { $sirali = @($vekMs | Sort-Object); $p50 = $sirali[[math]::Floor($sirali.Count / 2)] }

$vekOk = (-not $vekHazir) -or ((Oran $vekR1) -ge $Esik)
$rapor = [ordered]@{
    v = 1; ts = (Get-Date).ToString('o'); kaynak = $kaynak; vaka = $vakalar.Count; eksik = $eksik; bozukSha = $bozuk
    vektorHazir = $vekHazir
    vektor = [ordered]@{ rank1 = (Oran $vekR1); rank2 = (Oran $vekR2); bos = (Oran $vekBos); p50ms = $p50 }
    kelime = [ordered]@{ rank1 = (Oran $kelR1); rank2 = (Oran $kelR2); bos = (Oran $kelBos) }
    esik = $Esik; gecti = ($vekOk -and $bozuk -eq 0)
    ornekHata = @($hatalar)
    sureMs = $sw.ElapsedMilliseconds
}
try { Write-BeyinText -Path (Join-Path $p.ScrState 'geri-getirme-olc.json') -Text ($rapor | ConvertTo-Json -Depth 5) } catch { }
$kod = if ($rapor.gecti) { 'OLC_OK' } else { 'OLC_DUSTU' }
Write-BeyinMakbuz -Paths $p -Script 'geri-getirme-olc' -Outcome $kod -DurationMs $sw.ElapsedMilliseconds `
    -Note "vaka=$n; vektor r1=$(Oran $vekR1) r2=$(Oran $vekR2) bos=$(Oran $vekBos); kelime r1=$(Oran $kelR1); esik=$Esik; bozukSha=$bozuk"

if ($Json) { $rapor | ConvertTo-Json -Depth 5 } else {
    "GERI GETIRME OLCUMU  ($kaynak; $n vaka, $($sw.ElapsedMilliseconds) ms)"
    if ($vekHazir) { "  Vektor (bge-m3): rank-1 $(Oran $vekR1)  ilk-2 $(Oran $vekR2)  bos $(Oran $vekBos)  p50 $p50 ms" } else { '  Vektor: indeks hazir degil (beyin gom) - yalniz kelime olculdu' }
    "  Kelime         : rank-1 $(Oran $kelR1)  ilk-2 $(Oran $kelR2)  bos $(Oran $kelBos)"
    "  Esik (vektor rank-1 >= $Esik): $(if ($rapor.gecti) { 'GECTI' } else { 'DUSTU' })$(if ($bozuk) { "  - fixture sha uyusmazligi: $bozuk" })$(if ($eksik) { "  - silinmis not: $eksik" })"
    foreach ($h in $hatalar) { "    ornek hata: $h" }
    "  Rapor: motor\scripts\.state\geri-getirme-olc.json"
}
if ($rapor.gecti) { exit 0 } else { exit 5 }
