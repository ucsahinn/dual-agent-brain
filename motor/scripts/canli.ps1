# canli.ps1 - Su an ne oluyor? Tek ekran: aktif oturumlar, kuyruk, calisan
# isler, butce, niyet, son makbuzlar. HICBIR SEY YAZMAZ.
#
# NEDEN: 15 es zamanli oturum, iki ajan, arka planda flush/derleyici - ve
# "su an ne calisiyor" sorusunun tek bir cevabi yoktu. Doktor saglik soyler,
# bu betik anlik durumu soyler.
#
# Kullanim:
#   beyin canli              son 30 dakikada dokunulan oturumlar
#   beyin canli 120          son 2 saat
#   beyin canli -Json

param(
    [string]$Vault = $(if ($env:BEYIN_VAULT) { $env:BEYIN_VAULT } else { Split-Path (Split-Path $PSScriptRoot -Parent) -Parent }),
    [int]$Dakika = 30,
    [switch]$Json
)

$ErrorActionPreference = 'SilentlyContinue'
# NEDEN: $Vault ilk KONUMSAL parametre; fazladan bir konumsal arguman Vault'a baglanir, lib.ps1 sessizce
# yuklenemez ve betik bos/yanlis sonucla exit 0 verir (ayni desen makbuz.ps1'de olculdu). SESLI dus.
$vaultOk = $false
try { $vaultOk = [bool]($Vault -and (Test-Path -LiteralPath $Vault -PathType Container) -and (Test-Path -LiteralPath (Join-Path $Vault 'motor\hooks\lib.ps1') -PathType Leaf)) } catch { }
if (-not $vaultOk) { Write-Output "HATA: vault degil (motor\hooks\lib.ps1 yok): '$Vault'  - konumsal arguman -Vault'a baglanir; dakika icin -Dakika <n> kullan"; exit 2 }
. (Join-Path $Vault 'motor\hooks\lib.ps1')
$p = Get-BeyinPaths -Vault $Vault
$simdi = Get-Date
$inv = [Globalization.CultureInfo]::InvariantCulture

function Yas([datetime]$T) {
    $d = $simdi - $T
    if ($d.TotalMinutes -lt 1) { return 'simdi' }
    if ($d.TotalMinutes -lt 60) { return "$([int]$d.TotalMinutes) dk" }
    if ($d.TotalHours -lt 48) { return "$([int]$d.TotalHours) sa" }
    return "$([int]$d.TotalDays) gun"
}

# --- 1) OTURUMLAR ---------------------------------------------------------
$oturumlar = New-Object System.Collections.Generic.List[object]
foreach ($f in @(Get-ChildItem -LiteralPath $p.Sessions -Filter '*.json' -File -ErrorAction SilentlyContinue |
                 Where-Object { $_.LastWriteTime -ge $simdi.AddMinutes(-$Dakika) } |
                 Sort-Object LastWriteTime -Descending)) {
    try {
        $o = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
        $ajan = if ($o.PSObject.Properties['agent'] -and $o.agent) { [string]$o.agent } else { '?' }
        $proje = if ($o.cwd) { Get-BeyinProjectLeaf -Path ([string]$o.cwd) -Paths $p } else { '-' }
        $basla = if ($o.start) { [DateTimeOffset]::FromUnixTimeSeconds([int64]$o.start).LocalDateTime } else { $f.CreationTime }
        $oturumlar.Add([pscustomobject]@{
            oturum  = $(if ($f.BaseName.Length -gt 12) { $f.BaseName.Substring(0, 12) } else { $f.BaseName })
            ajan    = $ajan
            proje   = $proje
            prompt  = [int]$o.prompts
            basladi = $basla.ToString('HH:mm', $inv)
            son     = (Yas $f.LastWriteTime)
            # @($null).Count 1'DIR (bos degil). Alani hic olmayan eski
            # oturum dosyalari bu yuzden '1 kavram' gosteriyordu.
            kavram  = $(if ($o.PSObject.Properties['kavram'] -and $o.kavram) { @($o.kavram).Count } else { 0 })
        })
    } catch { }
}

# --- 2) KUYRUK ------------------------------------------------------------
$kuyruk = New-Object System.Collections.Generic.List[object]
foreach ($f in @(Get-ChildItem -LiteralPath $p.Queue -Filter '*.json' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime)) {
    try {
        $o = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
        $kuyruk.Add([pscustomobject]@{
            ajan   = $(if ($o.agent) { [string]$o.agent } else { '?' })
            neden  = [string]$o.reason
            proje  = $(if ($o.cwd) { Get-BeyinProjectLeaf -Path ([string]$o.cwd) -Paths $p } else { '-' })
            bekliyor = (Yas $f.LastWriteTime)
            transkript = (Split-Path -Leaf ([string]$o.transcript))
        })
    } catch { }
}

# --- 3) CALISAN (slot kilitleri: ozel acilamiyorsa mesgul) ----------------
$calisan = New-Object System.Collections.Generic.List[object]
foreach ($f in @(Get-ChildItem -LiteralPath $p.Slots -Filter '*.lock' -File -ErrorAction SilentlyContinue)) {
    $mesgul = $false
    try { $h = [System.IO.File]::Open($f.FullName, 'Open', 'ReadWrite', 'None'); $h.Close(); $h.Dispose() } catch { $mesgul = $true }
    if ($mesgul) {
        $tur = if ($f.BaseName -like 'compile*') { 'derleyici' } else { 'flush' }
        $calisan.Add([pscustomobject]@{ slot = $f.BaseName; is = $tur; basladi = (Yas $f.LastWriteTime) })
    }
}

# --- 4) BUTCE -------------------------------------------------------------
$kullanilan = Get-BeyinBudgetUsed -Paths $p
$butce = [pscustomobject]@{ kullanilan = $kullanilan; flushTavan = (Get-BeyinFlushBudget); derleyiciRezerv = (Get-BeyinCompileBudget) }

# --- 5) NIYET -------------------------------------------------------------
$niyet = Get-BeyinNiyet -Paths $p -MaxGun 36500

# --- 6) SON MAKBUZLAR -----------------------------------------------------
$makbuz = @(Read-BeyinMakbuz -Paths $p -Gun 2 | Sort-Object ts -Descending | Select-Object -First 8 | ForEach-Object {
    $t = try { [datetime]::Parse($_.ts, $inv) } catch { $simdi }
    [pscustomobject]@{
        ne_zaman = (Yas $t)
        betik    = $_.script
        ajan     = $_.agent
        sonuc    = $_.outcome
        sn       = $(if ($_.ms) { [string]::Format($inv, '{0:0.0}', $_.ms / 1000.0) } else { '' })
        not      = $(if ($_.note) { $n = [string]$_.note; if ($n.Length -gt 50) { $n.Substring(0, 47) + '...' } else { $n } } else { '' })
    }
})

if ($Json) {
    [pscustomobject]@{ zaman = $simdi.ToString('o', $inv); oturumlar = @($oturumlar); kuyruk = @($kuyruk); calisan = @($calisan); butce = $butce; niyet = $niyet; makbuz = $makbuz } |
        ConvertTo-Json -Depth 6
    exit 0
}

"CANLI  $($simdi.ToString('yyyy-MM-dd HH:mm', $inv))  |  vault: $(Split-Path -Leaf $Vault)"
''
"OTURUMLAR (son $Dakika dk dokunulan: $($oturumlar.Count))"
if ($oturumlar.Count) { ($oturumlar | Format-Table -AutoSize | Out-String -Width 200).TrimEnd() } else { '  (yok)' }
''
"KUYRUK ($($kuyruk.Count) is bekliyor)"
if ($kuyruk.Count) { ($kuyruk | Select-Object -First 8 | Format-Table -AutoSize | Out-String -Width 200).TrimEnd(); if ($kuyruk.Count -gt 8) { "  ... +$($kuyruk.Count - 8)" } } else { '  (bos)' }
''
"CALISAN ($($calisan.Count))"
if ($calisan.Count) { ($calisan | Format-Table -AutoSize | Out-String -Width 200).TrimEnd() } else { '  (su an arka planda is yok)' }
''
"BUTCE   $($butce.kullanilan) / $($butce.flushTavan) flush (derleyici rezervi $($butce.derleyiciRezerv))$(if ($butce.kullanilan -ge $butce.flushTavan) { '   << DOLU: yeni ozetler kuyruga gider' })"
''
if ($niyet) {
    $g = [int][math]::Floor($niyet.AgeDays)
    "NIYET   ($g gun$(if ($niyet.Project) { ", proje: $($niyet.Project)" })$(if ($niyet.AgeDays -gt 7) { ', BAYAT' })): $($niyet.Text)"
} else { 'NIYET   (yok)  ->  beyin niyet "..."' }
''
"SON MAKBUZLAR ($($makbuz.Count))"
if ($makbuz.Count) { ($makbuz | Format-Table -AutoSize | Out-String -Width 200).TrimEnd() } else { '  (yok)' }
