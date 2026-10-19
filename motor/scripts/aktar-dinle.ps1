# beyin aktar dinle -Kime claude|codex [-Proje <ad>] [-Sure <sn>]
# CANLI UYANDIRMA (2026-10-19): yeni aktarim kaydi (.state\handoff\<id>.json) dustugu anda TEK SATIR basar.
# Claude Code'un Monitor araci bu betigi arka planda calistirir; her satir oturuma olay olarak duser ve
# bosta duran oturumu uyandirir. Yoklama yok (FileSystemWatcher); bosta jeton maliyeti 0.
# GUVENLIK: satir yalniz kimlik + gonderen + temizlenmis tek satirlik onizleme tasir; tam metin ASLA
# basilmaz (guvenilmez veri) - okumak icin: beyin aktar. Yalniz hedef ajana (ve -Proje verildiyse o projeye
# ya da projesiz kayda) adresli ACIK kayitlar. Hicbir sey yazmaz, hicbir sureci kapatmaz.
param([string]$Vault = '', [string]$Kime = 'claude', [string]$Proje = '', [int]$Sure = 0)
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch { }   # Monitor ciktiyi yonlendirilmis okur: OEM kod sayfasi Turkce/isaretleri bozuyordu
if ($Kime -notin @('claude', 'codex')) { [Console]::Out.WriteLine('beyin aktar dinle: -Kime claude ya da codex olmali'); exit 2 }
if (-not $Vault) { $Vault = $(if ($env:BEYIN_VAULT) { $env:BEYIN_VAULT } else { Split-Path (Split-Path $PSScriptRoot -Parent) -Parent }) }
. (Join-Path $Vault 'motor\hooks\lib.ps1')
$p = Get-BeyinPaths -Vault $Vault
$dizin = Join-Path $p.ScrState 'handoff'
if (-not (Test-Path -LiteralPath $dizin)) { New-Item -ItemType Directory -Force -Path $dizin | Out-Null }
function Yaz([string]$s) { [Console]::Out.WriteLine($s); [Console]::Out.Flush() }
function Temiz([string]$s, [int]$n) {
    # kontrol, C1, yon ve kacis karakterleri gider; tek satir; kisaltilir
    $t = ([string]$s) -replace '[\x00-\x1f\x7f-\x9f\u200b-\u200f\u202a-\u202e\u2066-\u2069\ufeff]', ' ' -replace '\s+', ' '
    $t = $t.Trim(); if ($t.Length -gt $n) { $t = $t.Substring(0, $n - 3) + '...' }
    return $t
}
$gor = New-Object 'System.Collections.Generic.HashSet[string]'
foreach ($f in [IO.Directory]::EnumerateFiles($dizin, '*.json')) { [void]$gor.Add([IO.Path]::GetFileNameWithoutExtension($f)) }   # yalniz BASLADIKTAN SONRA gelenler
$w = New-Object IO.FileSystemWatcher $dizin, '*'
$w.IncludeSubdirectories = $false
$w.NotifyFilter = [IO.NotifyFilters]'FileName, LastWrite'
Yaz ("beyin aktar dinle: {0}{1} icin dinleniyor | yeni aktarim gelince tek satir | tam metin: beyin aktar" -f $Kime, $(if ($Proje) { " / $Proje" } else { '' }))
$bitis = $(if ($Sure -gt 0) { (Get-Date).AddSeconds($Sure) } else { [datetime]::MaxValue })
while ((Get-Date) -lt $bitis) {
    $kalan = [int][Math]::Min(30000, [Math]::Max(100, ($bitis - (Get-Date)).TotalMilliseconds))
    $r = $w.WaitForChanged([IO.WatcherChangeTypes]'Created, Changed, Renamed', $kalan)
    if ($r.TimedOut -or -not $r.Name -or $r.Name -notlike '*.json') { continue }   # atomik yazimin .tmp- dosyasi da atlanir
    $id = [IO.Path]::GetFileNameWithoutExtension($r.Name)
    if ($gor.Contains($id)) { continue }
    $o = $null
    for ($i = 0; $i -lt 10 -and -not $o; $i++) {
        try { $o = [IO.File]::ReadAllText((Join-Path $dizin $r.Name)) | ConvertFrom-Json } catch { Start-Sleep -Milliseconds 100 }
    }
    if (-not $o) { continue }
    if ([string]$o.to -ne $Kime -or [string]$o.status -ne 'acik') { continue }
    if ($Proje -and [string]$o.toProject -and [string]$o.toProject -ne $Proje) { continue }
    [void]$gor.Add($id)
    $kimden = Temiz ([string]$(if ($o.from -and $o.from.agent) { $o.from.agent } else { $o.from })) 20
    $kp = Temiz ([string]$(if ($o.from -and $o.from.project) { $o.from.project } else { '' })) 30
    Yaz ("AKTAR {0} | {1}{2} -> {3}{4} | [{5}] {6} | oku: beyin aktar" -f (Temiz $id 40), $kimden, $(if ($kp) { "/$kp" } else { '' }), $Kime,
         $(if ($o.toProject) { '/' + (Temiz ([string]$o.toProject) 30) } else { '' }), (Temiz ([string]$o.kind) 10), (Temiz ([string]$o.question) 140))
}
$w.Dispose()
