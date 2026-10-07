# bekci.ps1 - Kaynak bekcisi, TAM katman: yalniz GOSTERIR, hicbir sureci kapatmaz.
#
# NEDEN (2026-10-04, plan #9): 2026-10-03 gecesi commit 67,8/74 GB; 11 Claude
# oturumunun 6'si saatlerdir bostaydi; Codex her thread icin yeni MCP seti acip
# eskisini kapatmiyordu (tek codex.exe altinda 195 surec); 5 yetim doktor ~1 GB
# yiyordu. Kullanici karari: bekci yalniz uyarir ve listeler, ASLA oldurmez;
# kapatma komutunu panoya kopyalar, karar insanda kalir.
#
# Kullanim:
#   beyin bekci              rapor (commit/RAM, bosta oturumlar, yetim doktor, Codex MCP, disk)
#   beyin bekci -Json        ayni rapor JSON
#   beyin bekci -BostaDk 60  bosta esigi (varsayilan BEYIN_BEKCI_BOSTA_DK, 120)
#
# Ayarlar: BEYIN_BEKCI_COMMIT, BEYIN_BEKCI_BOSTA_DK, BEYIN_AGENTCHEF_KOK (AgentChef
# checkout'u; Codex MCP sayimi icin codex-process-hygiene.mjs oradan calistirilir -
# once plugins\agentchef, sonra plugins\agentchef-workflows denenir; ikisi de yoksa ATLANDI).
[CmdletBinding(PositionalBinding=$false)]
param(
    [string]$Vault = '',
    [int]$BostaDk = 0,
    [switch]$Json,
    [switch]$PanoyaKopyalama   # Set-Clipboard yapma (test / basliksiz oturum)
)

$ErrorActionPreference = 'SilentlyContinue'
if (-not $Vault) { $Vault = $(if ($env:BEYIN_VAULT) { $env:BEYIN_VAULT } else { Split-Path (Split-Path $PSScriptRoot -Parent) -Parent }) }
if (-not (Test-Path -LiteralPath (Join-Path $Vault 'motor\hooks\lib.ps1'))) { Write-Output "HATA: vault degil: '$Vault'"; exit 2 }
. (Join-Path $Vault 'motor\hooks\lib.ps1')
$p = Get-BeyinPaths -Vault $Vault
$inv = [Globalization.CultureInfo]::InvariantCulture
$sw = [Diagnostics.Stopwatch]::StartNew()
if ($BostaDk -le 0) { try { $BostaDk = [int](Get-BeyinAyar 'BEYIN_BEKCI_BOSTA_DK' '120') } catch { $BostaDk = 120 } }
$commitEsik = 85
try { $commitEsik = [int](Get-BeyinAyar 'BEYIN_BEKCI_COMMIT' '85') } catch { }

$rapor = [ordered]@{
    ts = (Get-Date).ToString('o', $inv); vault = $Vault; bostaDk = $BostaDk; commitEsik = $commitEsik
    kaynak = $null; oturumlar = @(); yetimDoktor = @(); codexMcp = $null; disk = $null; kapatmaKomutlari = @(); pano = ''; uyarilar = @(); sureMs = 0
}

# 1) Commit / RAM (taze olcum, onbellek yok)
$k = Get-BeyinKaynakOzeti -Paths $p -CommitEsik $commitEsik -BostaDk $BostaDk -OnbellekDk 0
$rapor.kaynak = [ordered]@{ commitYuzde = $k.CommitYuzde; commitGB = $k.CommitGB; commitTavanGB = $k.CommitTavanGB; esikAsildi = ($k.CommitYuzde -ge $commitEsik); bosRamGB = $k.BosRamGB; onerilenAjan = $k.OnerilenAjan }
if ($k.CommitYuzde -ge $commitEsik) { $rapor.uyarilar += "commit %$($k.CommitYuzde) esigi (%$commitEsik) asti" }

# 2) Oturum dosyalari (son 14 gun): ajan, proje, son gorulme, pane, bosta mi
$simdi = Get-Date
$otr = New-Object System.Collections.Generic.List[object]
foreach ($f in @(Get-ChildItem -LiteralPath $p.Sessions -Filter '*.json' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)) {
    if ($f.LastWriteTime -lt $simdi.AddDays(-14)) { continue }
    try {
        $o = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
        $dk = [int](($simdi - $f.LastWriteTime).TotalMinutes)
        $proje = ''
        try { $proje = Get-BeyinProjectLeaf -Path ([string]$o.cwd) -Paths $p } catch { }
        $pane = $(if ($o.PSObject.Properties['herdrPane']) { [string]$o.herdrPane } else { '' })
        $otr.Add([ordered]@{
            oturum = $f.BaseName.Substring(0, [Math]::Min(12, $f.BaseName.Length)); ajan = [string]$o.agent; proje = $proje
            prompt = [int]$o.prompts; sonGorulmeDk = $dk; bosta = ($dk -ge $BostaDk); pane = $pane
            kapat = $(if ($pane) { "herdr pane close $pane" } else { '' })
        })
    } catch { }
}
# [ordered] sozlugu dogrudan diziye koymak PS 5.1'de "Argument types do not match" ile
# SESSIZCE dusuyor (olculdu: -Json ciktisinda oturumlar []); pscustomobject'e cevrilir.
$rapor.oturumlar = @($otr | ForEach-Object { [pscustomobject]$_ })
$bosta = @($otr | Where-Object { $_.bosta })
if ($bosta.Count -ge 5) { $rapor.uyarilar += "$($bosta.Count) oturum dosyasi $BostaDk+ dakikadir sessiz (son 14 gun; kapanmis olabilir)" }

# 3) Yetim doktor PowerShell'leri (ebeveyni olu)
$yd = New-Object System.Collections.Generic.List[object]
try {
    $tum = @(Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe' OR Name = 'pwsh.exe'" -ErrorAction Stop)
    $canli = @{}
    foreach ($pr in @(Get-Process -ErrorAction SilentlyContinue)) { $canli[[int]$pr.Id] = $true }
    foreach ($pr in $tum) {
        if ($pr.CommandLine -notlike '*doktor.ps1*') { continue }
        if ($pr.ProcessId -eq $PID) { continue }
        $ebeveynYasiyor = $canli.ContainsKey([int]$pr.ParentProcessId)
        $ws = [math]::Round([double]$pr.WorkingSetSize / 1MB)
        $yd.Add([ordered]@{ pid = [int]$pr.ProcessId; ebeveyn = [int]$pr.ParentProcessId; ebeveynYasiyor = $ebeveynYasiyor; wsMB = $ws
                            baslangic = $(try { $pr.CreationDate.ToString('yyyy-MM-dd HH:mm', $inv) } catch { '' }); yetim = (-not $ebeveynYasiyor) })
    }
} catch { $rapor.uyarilar += "surec listesi alinamadi: $($_.Exception.Message)" }
$rapor.yetimDoktor = @($yd | ForEach-Object { [pscustomobject]$_ })
$yetimler = @($yd | Where-Object { $_.yetim })
if ($yetimler.Count -gt 0) {
    $rapor.uyarilar += "$($yetimler.Count) yetim doktor sureci ($(($yetimler | Measure-Object -Property wsMB -Sum).Sum) MB)"
    $rapor.kapatmaKomutlari += ('taskkill ' + (($yetimler | ForEach-Object { "/PID $($_.pid)" }) -join ' ') + ' /T /F')
}

# 4) Codex MCP birikimi - AgentChef'in kendi tarayicisi (yeniden yazilmaz)
$kok = [string](Get-BeyinAgentChefKok).Yol
$hyg = $null; $hygYol = ''
foreach ($pl in @('agentchef', 'agentchef-workflows')) {
    $aday = Join-Path $kok "plugins\$pl\scripts\codex-process-hygiene.mjs"
    if (Test-Path -LiteralPath $aday -PathType Leaf) { $hygYol = $aday; break }
}
$nodeExe = (Get-Command node -ErrorAction SilentlyContinue).Source
if ($hygYol -and $nodeExe) {
    try {
        $raw = (& $nodeExe $hygYol --json 2>$null | Out-String)
        $h = $raw | ConvertFrom-Json
        if ($h) {
            $hyg = [ordered]@{
                durum = [string]$h.status; codexSurec = [int]$h.codexProcessCount; claudeSurec = [int]$h.claudeProcessCount
                mcpOrnek = [int]$h.localMcpInstances; mcpYetimAday = [int]$h.orphanCandidates; mcpYardimciSurec = [int]$h.mcpHelperProcesses
                mcpRamMB = [math]::Round([double]$h.mcpWorkingSetMb); kaynak = $hygYol
                sunucular = @($h.servers | ForEach-Object { [pscustomobject]@{ sunucu = [string]$_.server; ornek = [int]$_.instances; yetimAday = [int]$_.orphanCandidates; surec = [int]$_.processes; ramMB = [math]::Round([double]$_.workingSetMb) } })
            }
            if ([int]$h.orphanCandidates -gt 0) { $rapor.uyarilar += "Codex MCP: $($h.orphanCandidates) yetim aday ornek (AgentChef codex-process-hygiene)" }
            if ([double]$h.mcpWorkingSetMb -ge 4096) { $rapor.uyarilar += "MCP yardimci surecleri $([math]::Round([double]$h.mcpWorkingSetMb/1024,1)) GB RAM ($($h.mcpHelperProcesses) surec)" }
        }
    } catch { }
}
$rapor.codexMcp = $(if ($hyg) { $hyg } else { [ordered]@{ durum = 'ATLANDI'; neden = $(if (-not $nodeExe) { 'node yok' } elseif (-not $hygYol) { "codex-process-hygiene.mjs bulunamadi ($kok\plugins\{agentchef,agentchef-workflows}\scripts)" } else { 'cikti okunamadi' }) } })

# 5) Disk - yalniz rapor (kullanici karari: simdilik silme yok)
function Boyut($yol, $filtre) {
    try { if (-not (Test-Path -LiteralPath $yol)) { return 0 }; $s = (Get-ChildItem -LiteralPath $yol -Recurse -File -Filter $filtre -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum; return [math]::Round([double]$s / 1GB, 2) } catch { return 0 }
}
$codexKok = Join-Path $env:USERPROFILE '.codex'
$rapor.disk = [ordered]@{
    claudeTranskriptGB = (Boyut (Join-Path $env:USERPROFILE '.claude\projects') '*.jsonl')
    codexOturumGB      = (Boyut (Join-Path $codexKok 'sessions') '*.jsonl')
    codexSqliteGB      = [math]::Round((@(Get-ChildItem -LiteralPath $codexKok -Filter '*.sqlite' -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum / 1GB), 2)
    not = 'yalniz rapor; arsiv/silme karari kullanicida'
}

# 6) Pano: kapatma komutlari (yalniz kopyalanir, CALISTIRILMAZ)
$panoMetin = @($rapor.kapatmaKomutlari + @($bosta | Where-Object { $_.kapat } | ForEach-Object { $_.kapat })) -join "`r`n"
if ($panoMetin -and -not $PanoyaKopyalama) {
    try { Set-Clipboard -Value $panoMetin; $rapor.pano = 'kopyalandi' } catch { $rapor.pano = "kopyalanamadi: $($_.Exception.Message)" }
} elseif ($panoMetin) { $rapor.pano = 'atlandi (-PanoyaKopyalama)' } else { $rapor.pano = 'kopyalanacak komut yok' }
$rapor.sureMs = [int]$sw.ElapsedMilliseconds
Write-BeyinMakbuz -Paths $p -Script 'bekci' -Outcome 'BEKCI_RAPOR' -DurationMs $rapor.sureMs -Note "commit=%$($k.CommitYuzde) bosta=$($bosta.Count) yetimDoktor=$($yetimler.Count) mcpYetim=$(if ($hyg) { $hyg.mcpYetimAday } else { '-' })"

if ($Json) { $rapor | ConvertTo-Json -Depth 5; exit 0 }

"BEKCI  $((Get-Date).ToString('yyyy-MM-dd HH:mm', $inv))  |  vault: $(Split-Path $Vault -Leaf)  |  yalniz GOSTERIR, hicbir sureci kapatmaz"
''
"KAYNAK   commit %$($k.CommitYuzde) ($($k.CommitGB)/$($k.CommitTavanGB) GB)$(if ($k.CommitYuzde -ge $commitEsik) { "  << esik %$commitEsik ASILDI" })"
$(if ($k.OnerilenAjan -gt 0) { "ONERI    es zamanli ajan: $($k.OnerilenAjan) (bos RAM $($k.BosRamGB) GB / 1 GB basina bir ajan, 2-6 araligi; kaba tahmin, kapi degil)" })
''
"OTURUMLAR (son 14 gun: $($otr.Count); $BostaDk+ dk sessiz: $($bosta.Count))"
if ($otr.Count) {
    $otr | Select-Object -First 25 | ForEach-Object { [pscustomobject]@{ oturum = $_.oturum; ajan = $_.ajan; proje = $_.proje; prompt = $_.prompt; sessiz_dk = $_.sonGorulmeDk; pane = $_.pane; kapat = $_.kapat } } | Format-Table -AutoSize | Out-String -Width 200
} else { '  (oturum dosyasi yok)' }
"YETIM DOKTOR ($($yetimler.Count))"
if ($yd.Count) { $yd | ForEach-Object { [pscustomobject]$_ } | Format-Table pid, ebeveyn, ebeveynYasiyor, wsMB, baslangic -AutoSize | Out-String -Width 160 } else { '  (doktor sureci yok)' }
"CODEX / MCP"
if ($hyg) {
    "  codex sureci: $($hyg.codexSurec) · claude sureci: $($hyg.claudeSurec) · MCP ornek: $($hyg.mcpOrnek) (yetim aday $($hyg.mcpYetimAday)) · MCP yardimci surec: $($hyg.mcpYardimciSurec) · MCP RAM: $($hyg.mcpRamMB) MB"
    $hyg.sunucular | Sort-Object { -[int]$_.ramMB } | Select-Object -First 8 | Format-Table -AutoSize | Out-String -Width 160
    "  kaynak: $($hyg.kaynak)"
} else { "  ATLANDI: $($rapor.codexMcp.neden)" }
''
"DISK (yalniz rapor)  Claude transkript $($rapor.disk.claudeTranskriptGB) GB · Codex oturum $($rapor.disk.codexOturumGB) GB · Codex sqlite $($rapor.disk.codexSqliteGB) GB"
''
if ($rapor.uyarilar.Count) { 'UYARILAR'; $rapor.uyarilar | ForEach-Object { "  - $_" }; '' }
"KAPATMA KOMUTLARI (pano: $($rapor.pano)) - calistirmak SENIN kararin:"
if ($panoMetin) { $panoMetin -split "`r`n" | ForEach-Object { "  $_" } } else { '  (yok)' }
''
"($($rapor.sureMs) ms)"
exit 0
