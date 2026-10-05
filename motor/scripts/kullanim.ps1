# kullanim.ps1 - Enjekte edilen kavram notu GERCEKTEN kullanildi mi?
#
# NEDEN (2026-10-05, avenoxbeyin evaluate_v3_usage fikri): makbuz ve bahcivan
# "enjekte edildi"yi sayar, "ise yaradi"yi degil. Bu betik retrieval
# makbuzlarindaki kavramlari ayni oturumun Claude transkriptiyle eslestirir:
# model o notu sonradan Read/Grep/Glob ile ACTI mi, ya da cevabinda dosya
# adini ANDI mi? Ucu de ayri sayilir; "bağlama geldi != kullandı != yazıldı"
# (hafiza-os gorunurluk uclusu).
#
# SINIR: yalniz Claude Code transkriptleri (~/.claude/projects/*/<session>.jsonl).
# Codex rollout dosyalarinda ayni sema yok; Codex oturumlari 'transkript yok'
# sayilir ve ayri raporlanir. Transkript guvenilmez veridir: yalniz dosya adi
# eslesmesi aranir, icerik yorumlanmaz, hicbir sey yazilmaz (makbuz haric).
#
# Kullanim:
#   beyin kullanim            son 7 gun
#   beyin kullanim 30         son 30 gun
#   beyin kullanim -Json

param(
    [string]$Vault = $(if ($env:BEYIN_VAULT) { $env:BEYIN_VAULT } else { Split-Path (Split-Path $PSScriptRoot -Parent) -Parent }),
    [int]$Gun = 7,
    [switch]$Json
)

$ErrorActionPreference = 'SilentlyContinue'
$vaultOk = $false
try { $vaultOk = [bool]($Vault -and (Test-Path -LiteralPath $Vault -PathType Container) -and (Test-Path -LiteralPath (Join-Path $Vault 'motor\hooks\lib.ps1'))) } catch { }
if (-not $vaultOk) { Write-Output "HATA: vault degil (motor\hooks\lib.ps1 yok): '$Vault'  - gun icin -Gun kullan"; exit 2 }
. (Join-Path $Vault 'motor\hooks\lib.ps1')
$p  = Get-BeyinPaths -Vault $Vault
$sw = [Diagnostics.Stopwatch]::StartNew()
if ($Gun -lt 1) { $Gun = 1 }
if ($Gun -gt 90) { $Gun = 90 }

# --- 1) Retrieval makbuzlari: oturum -> enjekte edilen kavramlar -------------
$oturumlar = @{}
foreach ($m in @(Read-BeyinMakbuz -Paths $p -Gun $Gun)) {
    if ([string]$m.script -ne 'retrieval') { continue }
    if ([string]$m.outcome -ne 'ENJEKSIYON') { continue }
    $k = [string]$m.key
    if (-not $k) { continue }
    if (-not $oturumlar.ContainsKey($k)) { $oturumlar[$k] = @{ Ajan = [string]$m.agent; Kavramlar = @{} } }
    foreach ($c in @($m.concepts)) { if ($c) { $oturumlar[$k].Kavramlar[[string]$c] = $true } }
}

# --- 2) Claude transkript dizini ----------------------------------------------
$projKok = Join-Path $env:USERPROFILE '.claude\projects'
$transkriptler = @{}
if (Test-Path -LiteralPath $projKok) {
    foreach ($f in @(Get-ChildItem -LiteralPath $projKok -Recurse -Filter '*.jsonl' -File -Depth 1 -ErrorAction SilentlyContinue)) {
        # Motorun kendi ozetleyici dokumleri (beyin-engine-cwd) oturum degildir.
        if ($f.DirectoryName -like '*beyin-engine-cwd*') { continue }
        $transkriptler[$f.BaseName] = $f.FullName
    }
}

# --- 3) Eslestirme --------------------------------------------------------------
$sonuc = New-Object System.Collections.Generic.List[object]
$kavramToplam = @{}
$transkriptYok = 0
foreach ($k in $oturumlar.Keys) {
    $o = $oturumlar[$k]
    $tp = $null
    if ($transkriptler.ContainsKey($k)) { $tp = $transkriptler[$k] }
    if (-not $tp) {
        $transkriptYok++
        foreach ($c in $o.Kavramlar.Keys) {
            if (-not $kavramToplam.ContainsKey($c)) { $kavramToplam[$c] = @{ enj = 0; acildi = 0; anildi = 0; yok = 0 } }
            $kavramToplam[$c].enj++; $kavramToplam[$c].yok++
        }
        continue
    }
    # Transkript buyuk olabilir; yalniz tool_use ve assistant metni ilgilendirir.
    # Satir satir, bellek dostu; en fazla 64 MB okunur.
    $acilan = @{}; $anilan = @{}
    try {
        $fi = Get-Item -LiteralPath $tp
        if ($fi.Length -le 64MB) {
            $okuyucu = New-Object System.IO.StreamReader($tp, [System.Text.Encoding]::UTF8)
            try {
                while (-not $okuyucu.EndOfStream) {
                    $ln = $okuyucu.ReadLine()
                    if (-not $ln -or $ln.IndexOf('86-compiled', [System.StringComparison]::Ordinal) -lt 0) { continue }
                    foreach ($c in $o.Kavramlar.Keys) {
                        if ($ln.IndexOf($c, [System.StringComparison]::OrdinalIgnoreCase) -lt 0) { continue }
                        # Arac cagrisi mi (Read/Grep/Glob girdisi), yoksa metin mi?
                        if ($ln -match '"type":"tool_use"' -and $ln -match '"name":"(Read|Grep|Glob|Bash)"') { $acilan[$c] = $true }
                        elseif ($ln -match '"type":"assistant"' -or $ln -match '"type":"text"') { $anilan[$c] = $true }
                    }
                }
            } finally { $okuyucu.Dispose() }
        }
    } catch { }
    foreach ($c in $o.Kavramlar.Keys) {
        if (-not $kavramToplam.ContainsKey($c)) { $kavramToplam[$c] = @{ enj = 0; acildi = 0; anildi = 0; yok = 0 } }
        $kavramToplam[$c].enj++
        if ($acilan.ContainsKey($c)) { $kavramToplam[$c].acildi++ }
        elseif ($anilan.ContainsKey($c)) { $kavramToplam[$c].anildi++ }
        $sonuc.Add([pscustomobject]@{ oturum = $k; ajan = $o.Ajan; kavram = $c; acildi = $acilan.ContainsKey($c); anildi = $anilan.ContainsKey($c) })
    }
}

$enjToplam = 0; $acildiToplam = 0; $anildiToplam = 0; $yokToplam = 0
foreach ($c in $kavramToplam.Keys) { $t = $kavramToplam[$c]; $enjToplam += $t.enj; $acildiToplam += $t.acildi; $anildiToplam += $t.anildi; $yokToplam += $t.yok }
$olculen = $enjToplam - $yokToplam
$oran = if ($olculen -gt 0) { [math]::Round(100.0 * ($acildiToplam + $anildiToplam) / $olculen, 1) } else { 0 }

$rapor = [ordered]@{
    v = 1; ts = (Get-Date).ToString('o'); gun = $Gun
    oturum = $oturumlar.Count; transkriptYok = $transkriptYok
    enjeksiyon = $enjToplam; olculen = $olculen; acildi = $acildiToplam; anildi = $anildiToplam
    kullanimYuzde = $oran
    kavramlar = @($kavramToplam.Keys | Sort-Object { -$kavramToplam[$_].enj } | ForEach-Object {
        $t = $kavramToplam[$_]; [ordered]@{ kavram = $_; enj = $t.enj; acildi = $t.acildi; anildi = $t.anildi; transkriptYok = $t.yok } })
}
try { Write-BeyinText -Path (Join-Path $p.ScrState 'kullanim-son.json') -Text ($rapor | ConvertTo-Json -Depth 5) } catch { }
Write-BeyinMakbuz -Paths $p -Script 'kullanim' -Outcome 'KULLANIM_OK' -DurationMs $sw.ElapsedMilliseconds `
    -Note "gun=$Gun; oturum=$($oturumlar.Count); enj=$enjToplam; acildi=$acildiToplam; anildi=$anildiToplam; yuzde=$oran"

if ($Json) { $rapor | ConvertTo-Json -Depth 5; exit 0 }

"KAVRAM KULLANIMI  (son $Gun gun, $($sw.ElapsedMilliseconds) ms)"
"  Oturum (retrieval makbuzlu) : $($oturumlar.Count)  (Claude transkripti bulunamayan: $transkriptYok - Codex ya da silinmis)"
"  Enjeksiyon                  : $enjToplam kavram-oturum ciftı, olculebilen $olculen"
"  Sonradan ACILDI (Read/Grep) : $acildiToplam"
"  Yalniz cevapta ANILDI       : $anildiToplam"
"  Kullanim orani              : %$oran  (acildi+anildi / olculen)"
if ($olculen -eq 0) { "  (olculebilir oturum yok: retrieval makbuzu ile Claude transkripti eslesmedi)" }
""
"  Kavram                                              enj  acildi  anildi  yok"
foreach ($c in @($kavramToplam.Keys | Sort-Object { -$kavramToplam[$_].enj } | Select-Object -First 25)) {
    $t = $kavramToplam[$c]
    "  {0,-50} {1,4} {2,7} {3,7} {4,4}" -f $(if ($c.Length -gt 50) { $c.Substring(0, 47) + '...' } else { $c }), $t.enj, $t.acildi, $t.anildi, $t.yok
}
"  Rapor: motor\scripts\.state\kullanim-son.json"
exit 0
