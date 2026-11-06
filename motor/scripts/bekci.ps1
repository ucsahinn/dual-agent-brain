# bekci.ps1 - Kaynak bekcisi, TAM katman: yalniz GOSTERIR, hicbir sureci kapatmaz.
#
# NEDEN (2026-10-04, plan #9): 2026-10-03 gecesi commit 67,8/74 GB; 11 Claude
# oturumunun 6'si saatlerdir bostaydi; Codex her thread icin yeni MCP seti acip
# eskisini kapatmiyordu (tek codex.exe altinda 195 surec); 5 yetim doktor ~1 GB
# yiyordu. Kullanici karari: bekci yalniz uyarir ve listeler, ASLA oldurmez;
# kapatma komutunu panoya kopyalar, karar insanda kalir.
#
# 2.0 (2026-10-31): KARAR LISTESI. Oturum dosyalari degil CANLI surecler listelenir; her biri icin bellek (surec agaci
# commit toplami), son is (transkript), sessizlik ve GEREKCELI karar: GUVENLE KAPAT / BAK / DOKUNMA. Panoya YALNIZ
# 'guvenle kapat' grubunun komutu gider. Bellegi kimin tuttugu (ajan agaclari, sahipsiz node, diger uygulamalar) ayri
# gosterilir. Kapanmis oturum kayitlari ve bitmis kosularin olu iscileri artik satir satir listelenmez (tek sayi).
#
# Kullanim:
#   beyin bekci              rapor
#   beyin bekci -Json        ayni rapor JSON
#   beyin bekci -BostaDk 60  'guvenle kapat' icin sessizlik esigi (varsayilan BEYIN_BEKCI_BOSTA_DK, 120)
#   beyin bekci -Hepsi       DOKUNMA grubunu da satir satir goster
#
# Ayarlar: BEYIN_BEKCI_COMMIT, BEYIN_BEKCI_BOSTA_DK, BEYIN_AGENTCHEF_KOK (Codex MCP sayimi icin codex-process-hygiene.mjs).
[CmdletBinding(PositionalBinding=$false)]
param(
    [string]$Vault = '',
    [int]$BostaDk = 0,
    [switch]$Json,
    [switch]$Hepsi,
    [switch]$PanoyaKopyalama   # Set-Clipboard yapma (test / basliksiz oturum)
)

$ErrorActionPreference = 'SilentlyContinue'
if (-not $Vault) { $Vault = $(if ($env:BEYIN_VAULT) { $env:BEYIN_VAULT } else { Split-Path (Split-Path $PSScriptRoot -Parent) -Parent }) }
if (-not (Test-Path -LiteralPath (Join-Path $Vault 'motor\hooks\lib.ps1'))) { Write-Output "HATA: vault degil: '$Vault'"; exit 2 }
. (Join-Path $Vault 'motor\hooks\lib.ps1')
foreach ($m in @('merkez-veri.ps1', 'merkez-balon.ps1', 'bekci-karar.ps1')) { $y = Join-Path $PSScriptRoot $m; if (Test-Path -LiteralPath $y) { . $y } }
if (-not $Json) { try { if (-not [Console]::IsOutputRedirected) { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } } catch { } }
$p = Get-BeyinPaths -Vault $Vault
$inv = [Globalization.CultureInfo]::InvariantCulture
$sw = [Diagnostics.Stopwatch]::StartNew()
if ($BostaDk -le 0) { try { $BostaDk = [int](Get-BeyinAyar 'BEYIN_BEKCI_BOSTA_DK' '120') } catch { $BostaDk = 120 } }
$commitEsik = 85
try { $commitEsik = [int](Get-BeyinAyar 'BEYIN_BEKCI_COMMIT' '85') } catch { }

$rapor = [ordered]@{
    ts = (Get-Date).ToString('o', $inv); vault = $Vault; bostaDk = $BostaDk; commitEsik = $commitEsik
    kaynak = $null; karar = $null; bellek = @(); oturumlar = @(); yetimDoktor = @(); codexMcp = $null; disk = $null; kapatmaKomutlari = @(); pano = ''; uyarilar = @(); sureMs = 0
}

# 1) Commit / RAM (taze olcum, onbellek yok)
$k = Get-BeyinKaynakOzeti -Paths $p -CommitEsik $commitEsik -BostaDk $BostaDk -OnbellekDk 0
$rapor.kaynak = [ordered]@{ commitYuzde = $k.CommitYuzde; commitGB = $k.CommitGB; commitTavanGB = $k.CommitTavanGB; esikAsildi = ($k.CommitYuzde -ge $commitEsik); bosRamGB = $k.BosRamGB; onerilenAjan = $k.OnerilenAjan }
if ($k.CommitYuzde -ge $commitEsik) { $rapor.uyarilar += "commit %$($k.CommitYuzde) esigi (%$commitEsik) asti" }

# 2) Canli ajan surecleri + karar
$ad = Get-BekciAdaylar -Paths $p -EsikDk $BostaDk
if ($ad.Hata) { $rapor.uyarilar += $ad.Hata }
$kapat = @($ad.Adaylar | Where-Object { $_.Karar -eq 'kapat' })
$bak = @($ad.Adaylar | Where-Object { $_.Karar -eq 'bak' })
$dokunma = @($ad.Adaylar | Where-Object { $_.Karar -eq 'dokunma' })
$kazancMB = [double](($kapat | Measure-Object -Property BellekMB -Sum).Sum)
$rapor.karar = [ordered]@{ kapat = $kapat; bak = $bak; dokunma = $dokunma; kapanmisKayit = $ad.Kapanmis; kazancMB = [math]::Round($kazancMB) }
$rapor.oturumlar = @($ad.Adaylar)   # geriye uyum: canli oturumlar
if ($ad.Agac) {
    $ajanPid = @{}; foreach ($x in $ad.Adaylar) { $ajanPid[[int]$x.Pid] = "$($x.Ajan)" }
    $rapor.bellek = @(Get-BekciBellekGruplari $ad.Agac $ajanPid | Select-Object -First 10 | ForEach-Object { [pscustomobject]@{ grup = $_.Ad; mb = [math]::Round($_.MB); surec = $_.Surec } })
}

# 2b) Takim: yalniz CANLI isci ve sef bekleyen kosu (olu isciler tek sayi)
$takimD = $null
try { $takimD = Get-BeyinTakimDurum -Paths $p } catch { }
$takimCanli = New-Object System.Collections.Generic.List[string]; $takimOlu = 0
if ($takimD) {
    foreach ($kr in @($takimD.Acik)) { foreach ($w in @($kr.workers)) { if (-not $w) { continue }
        $c = [bool]($w.pid -and (Get-Process -Id ([int]$w.pid) -ErrorAction SilentlyContinue))
        if ($c) { $takimCanli.Add("$($kr.runId) $($w.taskId) [$($w.status)] pid $($w.pid)") } else { $takimOlu++ } } }
}
$rapor.takim = $(if ($takimD) { [ordered]@{ acikKosu = @($takimD.Acik).Count; calisanIsci = [int]$takimD.Isci; canliIsci = @($takimCanli); oluIsci = $takimOlu; onayBekleyen = @($takimD.OnayBekleyen | ForEach-Object { "$($_.Tur) $($_.RunId)" }); satir = [string]$takimD.Satir } } else { $null })

# 3) Yetim doktor PowerShell'leri (ebeveyni olu)
$yd = New-Object System.Collections.Generic.List[object]
if ($ad.Agac) {
    foreach ($pr in $ad.Agac.Surec.Values) {
        if ($pr.Ad -notin @('powershell.exe', 'pwsh.exe') -or $pr.Komut -notlike '*doktor.ps1*' -or $pr.Komut -like '*Pester*' -or $pr.Pid -eq $PID) { continue }
        $ebeveynYasiyor = $ad.Agac.Surec.ContainsKey($pr.Ebeveyn)
        $yd.Add([ordered]@{ pid = $pr.Pid; ebeveyn = $pr.Ebeveyn; ebeveynYasiyor = $ebeveynYasiyor; wsMB = [math]::Round($pr.WsMB)
                            baslangic = $(try { $pr.Olusma.ToString('yyyy-MM-dd HH:mm', $inv) } catch { '' }); yetim = (-not $ebeveynYasiyor) })
    }
}
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
$rapor.codexMcp = $(if ($hyg) { $hyg } else { [ordered]@{ durum = 'ATLANDI'; neden = $(if (-not $nodeExe) { 'node yok' } elseif (-not $kok) { 'AgentChef bulunamadi (kur ya da: beyin ayar BEYIN_AGENTCHEF_KOK <klasor>)' } elseif (-not $hygYol) { "codex-process-hygiene.mjs bulunamadi ($kok\plugins\{agentchef,agentchef-workflows}\scripts)" } else { 'cikti okunamadi' }) } })
$rapor.nodeRepl = $null
try {
    $rapor.nodeRepl = Get-BeyinNodeReplReport
    if ($rapor.nodeRepl.OrphanCount) { $rapor.uyarilar += "node_repl.exe: $($rapor.nodeRepl.OrphanCount) yetim aday (ebeveyn yok veya PID yeniden kullanilmis); yalniz rapor" }
    if ($rapor.nodeRepl.Excess) { $rapor.uyarilar += "node_repl.exe: $($rapor.nodeRepl.Count) surec, esik $($rapor.nodeRepl.Limit); yalniz rapor" }
} catch { $rapor.uyarilar += 'node_repl.exe sayimi alinamadi' }

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

# 6) Pano: YALNIZ 'guvenle kapat' grubu + yetim doktor (kopyalanir, CALISTIRILMAZ)
$kapatPid = @($kapat | Where-Object { $_.Kapat -like 'taskkill*' } | ForEach-Object { $_.Pid })
if ($kapatPid.Count) { $rapor.kapatmaKomutlari = @(('taskkill ' + (($kapatPid | ForEach-Object { "/PID $_" }) -join ' ') + ' /T /F')) + @($rapor.kapatmaKomutlari) }
foreach ($x in @($kapat | Where-Object { $_.Kapat -notlike 'taskkill*' })) { $rapor.kapatmaKomutlari += $x.Kapat }
$panoMetin = @($rapor.kapatmaKomutlari) -join "`r`n"
if ($panoMetin -and -not $PanoyaKopyalama -and -not $Json) {
    try { Set-Clipboard -Value $panoMetin; $rapor.pano = 'kopyalandi' } catch { $rapor.pano = "kopyalanamadi: $($_.Exception.Message)" }
} elseif ($panoMetin) { $rapor.pano = 'kopyalanmadi' } else { $rapor.pano = 'kopyalanacak komut yok' }
$rapor.sureMs = [int]$sw.ElapsedMilliseconds
Write-BeyinMakbuz -Paths $p -Script 'bekci' -Outcome 'BEKCI_RAPOR' -DurationMs $rapor.sureMs -Note "commit=%$($k.CommitYuzde) kapat=$($kapat.Count) bak=$($bak.Count) dokunma=$($dokunma.Count) kazanc=$([math]::Round($kazancMB))MB yetimDoktor=$($yetimler.Count)"

# son karar ozeti: merkez bellek teshisinde "N oturum guvenle kapatilabilir" der (30 dk tazelikte)
try { Write-BeyinText -Path (Join-Path $p.ScrState 'bekci-son.json') -Text (ConvertTo-Json -Compress -InputObject ([ordered]@{ ts = (Get-Date).ToString('o', $inv); kapat = $kapat.Count; bak = $bak.Count; dokunma = $dokunma.Count; kazancMB = [math]::Round($kazancMB) })) } catch { }
if ($Json) { $rapor | ConvertTo-Json -Depth 6; exit 0 }

# ---------- ekran ----------
$e = [char]27; $renkli = -not [Console]::IsOutputRedirected
function Renk([string]$kod, [string]$m) { if ($renkli) { return "$e[${kod}m$m$e[0m" }; return $m }
function Kirmizi($m) { Renk '91' $m }; function Sari($m) { Renk '93' $m }; function Yesil($m) { Renk '92' $m }; function Soluk($m) { Renk '90' $m }; function Kalin($m) { Renk '1' $m }
function Kes([string]$m, [int]$n) { if ($m.Length -le $n) { return $m }; return $m.Substring(0, [Math]::Max(1, $n - 1)) + '…' }
function AdayYaz($x, [bool]$ayrinti) {
    $basl = "{0,-6} {1,-18} {2,9}  {3,7} sessiz" -f $x.Ajan, (Kes ([string]$x.Proje) 18), (Format-BekciMB $x.BellekMB), (Format-BekciSure $x.SessizDk)
    "  $basl  $(Soluk "pid $($x.Pid) · $($x.Oturum.Substring(0, [Math]::Min(8, $x.Oturum.Length)))$(if ($x.AltSurec -gt 0) { " · +$($x.AltSurec) alt süreç" })")"
    "      $(Soluk 'neden:') $($x.Neden)"
    if ($ayrinti -and $x.Son) { "      $(Soluk 'son:') $(Kes ([string]$x.Son) 100)" }
    if ($ayrinti -and @($x.Kartlar).Count) { "      $(Soluk 'kart:') $(@($x.Kartlar) -join ', ')" }
    if ($ayrinti -and $x.Takim) { "      $(Soluk 'takım:') $($x.Takim)" }
    if ($ayrinti) { "      $(Soluk 'kapat:') $(if ($x.Nazik) { "$($x.Nazik)  ya da  " })$($x.Kapat)" }
}

"$(Kalin 'BEKÇİ')  $((Get-Date).ToString('yyyy-MM-dd HH:mm', $inv))  $(Soluk '· yalnız gösterir, hiçbir süreci kapatmaz')"
''
$cm = "commit %$($k.CommitYuzde) ($($k.CommitGB)/$($k.CommitTavanGB) GB)"
"$(Kalin 'BELLEK')   $(if ($k.CommitYuzde -ge $commitEsik) { Kirmizi "$cm ▲ eşik %$commitEsik aşıldı" } else { Yesil $cm })  $(Soluk "· boş RAM $($k.BosRamGB) GB · $($k.OnerilenAjan) ajana yer")"
if ($rapor.bellek.Count) {
    $grAd = @{ 'sahipsiz-node' = 'sahipsiz node (ebeveyni ölü)' }
    $parca = @($rapor.bellek | Select-Object -First 6 | ForEach-Object { "$(if ($_.grup -like 'ajan:*') { ($_.grup -replace '^ajan:', '') + ' oturumları' } elseif ($grAd.ContainsKey($_.grup)) { $grAd[$_.grup] } else { $_.grup }) $(Format-BekciMB $_.mb)" })
    "         $(Soluk 'en çok tutan:') $($parca -join ' · ')"
}
''
"$(Kalin 'KARAR')    $(Yesil "$($kapat.Count) güvenle kapatılabilir") · $(Sari "$($bak.Count) bakman gerek") · $(Soluk "$($dokunma.Count) dokunma")$(if ($kazancMB -gt 0) { " · kapatırsan ~$(Format-BekciMB $kazancMB) boşalır" })"
"         $(Soluk "eşik: turu bitmiş + $BostaDk dk sessiz + açık kartı yok · ayar: beyin bekci -BostaDk <dk>")"
''
if ($kapat.Count) {
    (Yesil "✓ GÜVENLE KAPATILABİLİR ($($kapat.Count) · ~$(Format-BekciMB $kazancMB))")
    foreach ($x in $kapat) { AdayYaz $x $true }
    ''
}
if ($bak.Count) {
    (Sari "? BAK, SONRA KARAR VER ($($bak.Count))")
    foreach ($x in $bak) { AdayYaz $x $true }
    ''
}
if ($dokunma.Count) {
    (Soluk "✕ DOKUNMA ($($dokunma.Count)) · çalışıyor ya da yakın zamanda etkin")
    if ($Hepsi) { foreach ($x in $dokunma) { AdayYaz $x $false } }
    else { "  $(Soluk ((@($dokunma | ForEach-Object { "$($_.Ajan)/$($_.Proje) $(Format-BekciMB $_.BellekMB)" }) -join ' · ') + ' · ayrıntı: beyin bekci -Hepsi'))" }
    ''
}
if (-not $ad.Adaylar.Count) { "  $(Soluk '(canlı ajan süreci bulunamadı)')"; '' }
"$(Soluk "kapanmış oturum kaydı: $($ad.Kapanmis) (süreci yok, işlem gerekmez)")"
if ($takimD -and @($takimD.Acik).Count) {
    "$(Soluk "takım: $(@($takimD.Acik).Count) açık koşu · canlı işçi $($takimCanli.Count) · kapanmış işçi $takimOlu (normal)")"
    foreach ($t in $takimCanli) { "  $t" }
}
''
if ($yd.Count) { "$(Kalin 'YETİM DOKTOR') ($($yetimler.Count))"; $yd | ForEach-Object { [pscustomobject]$_ } | Format-Table pid, ebeveyn, ebeveynYasiyor, wsMB, baslangic -AutoSize | Out-String -Width 160 }
if ($hyg) {
    "$(Kalin 'MCP')      codex $($hyg.codexSurec) · claude $($hyg.claudeSurec) süreç · MCP örnek $($hyg.mcpOrnek)$(if ($hyg.mcpYetimAday) { ' · ' + (Sari "yetim aday $($hyg.mcpYetimAday)") }) · yardımcı süreç $($hyg.mcpYardimciSurec) · $(Format-BekciMB $hyg.mcpRamMB)"
    "         $(Soluk ((@($hyg.sunucular | Sort-Object { -[int]$_.ramMB } | Select-Object -First 5 | ForEach-Object { "$($_.sunucu) $($_.ornek)× $(Format-BekciMB $_.ramMB)" })) -join ' · '))"
} else { "$(Kalin 'MCP')      $(Soluk "atlandı: $($rapor.codexMcp.neden)")" }
if ($rapor.nodeRepl) { "         $(Soluk "node_repl $($rapor.nodeRepl.Count) süreç · yetim aday $($rapor.nodeRepl.OrphanCount)")" }
"$(Kalin 'DİSK')     $(Soluk "Claude transkript $($rapor.disk.claudeTranskriptGB) GB · Codex oturum $($rapor.disk.codexOturumGB) GB · Codex sqlite $($rapor.disk.codexSqliteGB) GB (yalnız rapor)")"
''
if ($rapor.uyarilar.Count) { (Sari 'UYARILAR'); $rapor.uyarilar | ForEach-Object { "  - $_" }; '' }
"$(Kalin 'PANODA')   $(if ($panoMetin) { "$($rapor.pano): yalnız güvenle kapatılabilirler$(if ($yetimler.Count) { ' + yetim doktor' }) · çalıştırmak senin kararın" } else { 'kopyalanacak komut yok' })"
if ($panoMetin) { $panoMetin -split "`r`n" | ForEach-Object { "  $_" } }
"$(Soluk "kapatmadan önce: oturumu pencerede /exit ile kapatmak en temizidir (özet kaydı yazılır); taskkill son çare. ($($rapor.sureMs) ms)")"
exit 0
