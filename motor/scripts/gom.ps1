# gom.ps1 - Kavram notlarini vektore gomer (Ollama bge-m3). Vektor geri
# getirmenin (Find-BeyinRelevantConceptsVec) veri kaynagi.
#
# NEDEN: anahtar kelime geri getirme yalniz ayni kelimeyi yakalar. "npm
# windows'ta patliyor" ile "spawnsync einval" arasindaki anlam koprusunu
# kelime kurmaz, vektor kurar.
#
# Artimli: hash = SHA1(model + metin). Ayni hash -> eski vektor korunur,
# yalniz yeni/degisen notlar gomulur (16'lik partiler), silinen not budanir.
# Vektorler BIRIM uzunluga getirilip float32 olarak kavram-vektor.bin'e,
# meta (model, dim, slug+hash listesi) kavram-vektor.dat'a yazilir.
#
# Cikis kodlari (stdout tek satir):
#   GOM_OK yeni=N ayni=M silinen=K dim=D
#   GOM_OLLAMA_YOK      Ollama cevap vermiyor (kelime yolu calismaya devam eder)
#   GOM_MODEL_YOK       model yuklu degil -> ollama pull bge-m3
#   GOM_BOS             gomulecek kavram yok
#   GOM_HATA_*          gomme basarisiz (eski indeks korunur)
#
# Kullanim:  beyin gom  |  beyin gom -Zorla  (hepsini yeniden gom)

param(
    [string]$Vault = $(if ($env:BEYIN_VAULT) { $env:BEYIN_VAULT } else { Split-Path (Split-Path $PSScriptRoot -Parent) -Parent }),
    [switch]$Zorla,
    [int]$Parti = 16,
    [int]$MetinTavan = 2000
)

$ErrorActionPreference = 'SilentlyContinue'
# NEDEN: $Vault ilk KONUMSAL parametre; fazladan bir konumsal arguman Vault'a baglanir, lib.ps1 sessizce
# yuklenemez ve betik bos/yanlis sonucla exit 0 verir (ayni desen makbuz.ps1'de olculdu). SESLI dus.
$vaultOk = $false
try { $vaultOk = [bool]($Vault -and (Test-Path -LiteralPath $Vault -PathType Container) -and (Test-Path -LiteralPath (Join-Path $Vault 'motor\hooks\lib.ps1') -PathType Leaf)) } catch { }
if (-not $vaultOk) { Write-Output "GOM_HATA_VAULT vault degil (motor\hooks\lib.ps1 yok): '$Vault'"; exit 2 }
. (Join-Path $Vault 'motor\hooks\lib.ps1')
$p = Get-BeyinPaths -Vault $Vault
$inv = [Globalization.CultureInfo]::InvariantCulture
$sw = [Diagnostics.Stopwatch]::StartNew()
$model = $script:BeyinEmbedModel
$dat = Join-Path $p.ScrState 'kavram-vektor.dat'
$bin = Join-Path $p.ScrState 'kavram-vektor.bin'
$datOnce = Measure-BeyinDosya -Path $dat
$binOnce = Measure-BeyinDosya -Path $bin

function Bitir([string]$Kod, [string]$Log, [object[]]$Files = @()) {
    if ($Log) { Write-BeyinLog -Vault $Vault -Message "gom: $Log" }
    Write-BeyinMakbuz -Paths $p -Script 'gom' -Outcome ($Kod -split ' ')[0] -Model $model -Files $Files -DurationMs $sw.ElapsedMilliseconds -Note $Log
    Write-Output $Kod
    exit 0
}

# --- 1) Ollama + model ------------------------------------------------------------
$tags = Invoke-BeyinOllamaJson -Yol '/api/tags' -TimeoutMs 3000
if (-not $tags) { Bitir 'GOM_OLLAMA_YOK' "Ollama cevap vermiyor ($($script:BeyinOllamaUrl)); kelime yolu gecerli" }
$modelVar = [bool](@($tags.models | Where-Object { ([string]$_.name) -like ($model + '*') }).Count)
if (-not $modelVar) { Bitir 'GOM_MODEL_YOK' "model '$model' Ollama'da yok -> ollama pull $model" }

# --- 2) Kavram metinleri + hash ---------------------------------------------------
$conceptDir = Join-Path $p.Compiled 'concepts'
$dosyalar = @(Get-ChildItem -LiteralPath $conceptDir -Filter '*.md' -File -ErrorAction SilentlyContinue | Sort-Object Name)
if ($dosyalar.Count -eq 0) { Bitir 'GOM_BOS' 'gomulecek kavram notu yok' }

$sha = [System.Security.Cryptography.SHA1]::Create()
$rxFm = [regex]'(?s)\A---\r?\n.*?\r?\n---\r?\n'
$rxBaslik = [regex]'(?m)^#\s+(.+)$'
# MAKINE BAKIMLI BOLUM GOMULMEZ (2.3, bagla.ps1). bagla her kavram notuna
# "## Ilgili notlar" bolumu yazar ve o bolumu BU indeksten turetir. Bolum
# gomulen metne girerse iki sey bozulur:
#   1) GERI BESLEME: komsu listesi vektoru etkiler, vektor komsu listesini
#      etkiler. Ustelik bolumun aciklama cumlesi 132 notta AYNIDIR - paylasilan
#      sabit bir metin parcasi TUM ciftlerin kosinusunu yukari iter ve ayirt
#      etme gucunu dusurur.
#   2) BOS IS + SALINIM: bagla bir baglantiyi degistirince notun hash'i degisir,
#      gom notu yeniden gomer, vektor kayar, bagla baglantiyi yine degistirir.
#      Iki gece gorevi (03:10 gom, 03:15 bagla) birbirini kovalar.
# Bolum turetilmis veridir, notun bilgisi degil: gomulen metnin disinda kalir.
# Desen TEK KAYNAKTAN gelir (lib.ps1 $script:BeyinIlgiliBolumRx): bes betik ayni
# basligi tanimak zorunda ve elle kopyalanan surum noktali buyuk I'yi kaciriyordu.
$rxIlgili = [regex]::new($script:BeyinIlgiliBolumRx, $script:BeyinRxCIMS)
$kayitlar = New-Object System.Collections.Generic.List[object]
foreach ($f in $dosyalar) {
    try {
        $raw = [IO.File]::ReadAllText($f.FullName)
        $govde = $rxFm.Replace($raw, '', 1)
        $govde = $rxIlgili.Replace($govde, '')   # bkz. $rxIlgili: turetilmis bolum gomulmez
        $mB = $rxBaslik.Match($govde)
        $baslik = if ($mB.Success) { $mB.Groups[1].Value.Trim() } else { [IO.Path]::GetFileNameWithoutExtension($f.Name) }
        $metin = ($baslik + "`n" + ($govde -replace '\s+', ' ')).Trim()
        if ($metin.Length -gt $MetinTavan) { $metin = $metin.Substring(0, $MetinTavan) }
        $hash = ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($model + "`n" + $metin))) -replace '-', '').Substring(0, 16).ToLowerInvariant()
        $kayitlar.Add(@{ slug = [IO.Path]::GetFileNameWithoutExtension($f.Name); metin = $metin; hash = $hash })
    } catch { }
}

# --- 3) Eski indeks: ayni hash -> vektor korunur ----------------------------------
$eski = @{}
$dim = 0
if (-not $Zorla) {
    $vi = Get-BeyinVectorIndex -Paths $p
    if ($vi -and ([string]$vi.Meta.model -eq $model)) {
        $dim = $vi.Dim
        for ($i = 0; $i -lt $vi.N; $i++) {
            $it = $vi.Meta.items[$i]
            $v = New-Object float[] $dim
            [Array]::Copy($vi.All, $i * $dim, $v, 0, $dim)
            $eski[[string]$it.slug] = @{ hash = [string]$it.hash; vec = $v }
        }
    }
}

$yeni = New-Object System.Collections.Generic.List[object]
$ayni = 0
foreach ($k in $kayitlar) {
    if ($eski.ContainsKey($k.slug) -and $eski[$k.slug].hash -eq $k.hash) { $k.vec = $eski[$k.slug].vec; $ayni++ }
    else { $yeni.Add($k) }
}
$silinen = @($eski.Keys | Where-Object { $sl = $_; -not ($kayitlar | Where-Object { $_.slug -eq $sl }) }).Count

# --- 4) Yeni/degisenleri partiler halinde gom -------------------------------------
$gomulen = 0
for ($i = 0; $i -lt $yeni.Count; $i += $Parti) {
    $parca = @($yeni | Select-Object -Skip $i -First $Parti)
    $emb = Invoke-BeyinOllamaEmbed -Texts @($parca | ForEach-Object { $_.metin }) -TimeoutMs 180000
    if (-not $emb.Ok) { Bitir "GOM_HATA_EMBED" "parti $([int]($i / $Parti) + 1) gomulemedi ($($parca.Count) not); eski indeks korundu" }
    for ($j = 0; $j -lt $parca.Count; $j++) {
        $u = ConvertTo-BeyinUnitVector ([float[]]$emb.Vectors[$j])
        if ($dim -eq 0) { $dim = $u.Length }
        if ($u.Length -ne $dim) { Bitir 'GOM_HATA_BOYUT' "boyut uyusmazligi ($($u.Length) != $dim); -Zorla ile yeniden gom" }
        $parca[$j].vec = $u; $gomulen++
    }
}
if ($dim -eq 0) { Bitir 'GOM_BOS' 'hicbir vektor uretilmedi' }

# --- 5) Yaz: .bin (float32) + .dat (meta) ----------------------------------------
$n = $kayitlar.Count
$all = New-Object float[] ($n * $dim)
$items = New-Object System.Collections.Generic.List[object]
for ($i = 0; $i -lt $n; $i++) {
    $k = $kayitlar[$i]
    if (-not $k.vec) { Bitir 'GOM_HATA_EKSIK' "'$($k.slug)' icin vektor yok; eski indeks korundu" }
    [Array]::Copy([float[]]$k.vec, 0, $all, $i * $dim, $dim)
    $items.Add(@{ slug = $k.slug; hash = $k.hash })
}
$bytes = New-Object byte[] ($n * $dim * 4)
[System.Buffer]::BlockCopy($all, 0, $bytes, 0, $bytes.Length)
Write-BeyinBytes -Path $bin -Bytes $bytes
Write-BeyinText -Path $dat -Text (ConvertTo-Json -InputObject @{ v = 1; model = $model; dim = $dim; ts = (Get-Date).ToString('o', $inv); items = $items.ToArray() } -Compress -Depth 4)

$files = @(
    @{ p = 'motor/scripts/.state/kavram-vektor.bin'; b = $binOnce; a = (Measure-BeyinDosya -Path $bin) },
    @{ p = 'motor/scripts/.state/kavram-vektor.dat'; b = $datOnce; a = (Measure-BeyinDosya -Path $dat) }
)
Bitir "GOM_OK yeni=$gomulen ayni=$ayni silinen=$silinen dim=$dim" "yeni=$gomulen ayni=$ayni silinen=$silinen dim=$dim ($n kavram, $([math]::Round($sw.ElapsedMilliseconds / 1000.0, 1)) sn)" $files
