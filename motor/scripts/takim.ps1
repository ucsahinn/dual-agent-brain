# takim.ps1 - Takim kosusu sarmalayicisi: AgentChef team-run.mjs + Beyin insan onayi kapisi + turetilmis gorunum.
#
# NEDEN (2026-10-12, takim modu plani): sef = kullanicinin konustugu Claude oturumu; isciler =
# 1-4 Codex (`codex exec`, abonelik), her isci bir pano karti ve kendi git worktree'si. Motor
# (scripts/team-run.mjs) AgentChef'tedir; bu sarmalayici pano.ps1 ile AYNI deseni izler: TEK
# state (board.json'un klasoru; team-runs/ ve onay dosyalari onun altinda), --state/--json
# otomatik, komut ve bayraklar aynen gecer, her mutasyondan sonra 10-command-center\takim.md
# (ve pano.md) yeniden turetilir. IKI INSAN ONAYI yalniz burada (etkilesimli terminal) ve
# prompt-counter'da (kullanicinin GERCEK mesajinda tek satir) uretilir; motor ASLA uretmez:
#   start  <- 'baslat <runId>'     isciler baslasin
#   merge  <- 'birlestir <runId>'  ara dal takim/<runId> kullanicinin daline girsin
# Onay yoksa node HIC cagrilmaz (exit 5); basarili gecisten sonra onay 'kullanildi' damgalanir
# (tek kullanimlik, 7 gun). Kart 'done' onayi ('onayla TASK-x') pano.ps1'de kalir.
#
# Kullanim:
#   beyin takim                          ozet + komutlar
#   beyin takim durum [runId]            kosular, isciler, bekleyen onaylar (dosyadan; runId verilirse motor status)
#   beyin takim plan --repo <yol> --plan-file <json> [--run <id>]
#   beyin takim baslat <runId>           TERMINAL onayi (sohbetten: tek satir 'baslat <runId>')
#   beyin takim start --run <runId>      onay kapisi -> motor iscileri acar
#   beyin takim status|collect|integrate|verify --run <runId>
#   beyin takim birlestir <runId>        TERMINAL onayi (sohbetten: 'birlestir <runId>')
#   beyin takim merge --run <runId>      onay kapisi -> motor ara dali kullanicinin daline alir
#   beyin takim durdur <runId>           motor abort: yalniz kendi cocuklarini durdurur (taskkill YOK)
#   beyin takim maliyet <runId>          kart basina jeton (maliyet.ps1 -Run)
#   beyin takim izle <runId> [TASK ...|pano]  kosu panosu + isci panellerini wt sekmelerinde (yeniden) acar (pano: yalniz kosu panosu)
#   beyin takim pause|resume|abort|cleanup|doctor|watch ...   aynen gecer
# Isci paneli (2026-10-13): start basarili olunca her isci icin premium panel sekmesi acilir; motorun ham
# `watch` sekmesi kapatilir (AGENTCHEF_TEAM_PANE=off). Ayar BEYIN_TAKIM_PANEL: on (varsayilan) | motor | off.
# Komutlarda runId '--run <id>', '--run=<id>' ya da ikinci konumsal arguman olarak verilebilir.
#
# Ayar: BEYIN_AGENTCHEF_KOK (AgentChef checkout). Hata: node CLI stderr'e {"ok":false,"error":"..."}
# yazar; aynen gecirilir. Cikis kodlari motorun: 0 ok, 1 ret, 2 kullanim, 3 onay yok, 4 kismi.
[CmdletBinding(PositionalBinding=$false)]
param(
    [string]$Vault = '',
    [Parameter(ValueFromRemainingArguments=$true)][string[]]$Arg = @()
)

$ErrorActionPreference = 'SilentlyContinue'
if (-not $Vault) { $Vault = $(if ($env:BEYIN_VAULT) { $env:BEYIN_VAULT } else { Split-Path (Split-Path $PSScriptRoot -Parent) -Parent }) }
if (-not (Test-Path -LiteralPath (Join-Path $Vault 'motor\hooks\lib.ps1'))) { Write-Output "HATA: vault degil: '$Vault'"; exit 2 }
. (Join-Path $Vault 'motor\hooks\lib.ps1')
$p = Get-BeyinPaths -Vault $Vault

$acKok = Get-BeyinAgentChefKok
$kok = [string]$acKok.Yol
$engine = Join-Path $kok 'scripts\team-run.mjs'
$nodeExe = (Get-Command node -ErrorAction SilentlyContinue).Source
$args2 = @($Arg | Where-Object { $null -ne $_ })
$engineVar = [bool](Test-Path -LiteralPath $engine -PathType Leaf)

function Yaz-Ozet {
    $d = Get-BeyinTakimDurum -Paths $p
    "TAKIM  state: $($p.TeamRuns)  |  motor: $engine $(if ($engineVar) { "(AgentChef $($acKok.Surum), kaynak: $($acKok.Kaynak))" } else { '(YOK - AgentChef 1.5.0+ gerekir; ayar BEYIN_AGENTCHEF_KOK)' })"
    if ($d.Acik.Count -eq 0) { "  acik kosu yok (toplam kayit $($d.Kosular.Count))" }
    else {
        "  $($d.Satir)"
        foreach ($k in $d.Acik) {
            $calisan = @($k.workers | Where-Object { $script:BeyinTakimCalisan -contains [string]$_.status }).Count
            "  - $($k.runId) [$($k.status)] $(if ($k.PSObject.Properties['repoName']) { $k.repoName } else { '' }) $($k.integrationBranch) - isci $calisan/$(@($k.workers).Count)"
            foreach ($w in @($k.workers)) { if ($w) { "      $($w.taskId) $($w.role) [$($w.status)]$(if ($w.pid) { " pid $($w.pid)" })" } }
        }
    }
    foreach ($b in $d.OnayBekleyen) { "  ONAY BEKLIYOR: sohbete tek satir yaz ->  $($b.Tur) $($b.RunId)" }
}

if ($args2.Count -eq 0) {
    Yaz-Ozet
    ''
    'Komutlar (motor: plan | start | status | collect | integrate | verify | merge | pause | resume | abort | cleanup | doctor | watch):'
    '  beyin takim plan --repo <yol> --plan-file <plan.json>      kartlari acar, kosu kaydi "planned"'
    '  beyin takim start --run <id>     (insan onayi: sohbete "baslat <id>")   isciler kendi worktree ve terminal sekmesinde'
    '  beyin takim collect|integrate|verify --run <id>             topla -> ara dala birlestir -> test_verifier dogrular'
    '  beyin takim merge --run <id>     (insan onayi: sohbete "birlestir <id>")  ara dal senin daline girer; push/PR ayri'
    'Beyin fiilleri: durum [id] | baslat <id> | birlestir <id> (terminal onayi) | durdur <id> (abort) | maliyet <id> | izle <id> [TASK] (isci panelleri)'
    "Turetilmis gorunum: $(Join-Path (Join-Path $Vault '10-command-center') 'takim.md')"
    exit 0
}

$komut = ([string]$args2[0]).ToLowerInvariant()

# runId cozumleme: --run <id> | --run=<id> | ikinci konumsal. Donus @{ Id; Gecen } (gecen: --run bicimine normalize)
function Coz-RunId([string[]]$A) {
    $id = ''; $out = New-Object System.Collections.Generic.List[string]
    $out.Add([string]$A[0])
    for ($i = 1; $i -lt $A.Count; $i++) {
        $x = [string]$A[$i]
        if ($x -eq '--run' -and $i + 1 -lt $A.Count) { $id = [string]$A[$i + 1]; $out.Add('--run'); $out.Add($id); $i++ }
        elseif ($x -like '--run=*') { $id = $x.Substring(6); $out.Add('--run'); $out.Add($id) }
        elseif ($i -eq 1 -and -not $id -and -not $x.StartsWith('-')) { $id = $x; $out.Add('--run'); $out.Add($id) }
        else { $out.Add($x) }
    }
    return @{ Id = $id; Gecen = $out.ToArray() }
}

# ---------------- Beyin fiilleri (motora gitmez) ----------------
if ($komut -eq 'durum' -and ($args2.Count -eq 1 -or -not $engineVar -or -not $nodeExe)) {
    Yaz-Ozet
    $verilmis = @(Get-BeyinOnayBekleyen -Paths $p | Where-Object { $_.Tur })
    foreach ($v in $verilmis) { "  verilmis, kullanilmamis onay: $($v.Tur) $($v.Id) ($($v.Kanal))" }
    $null = Update-BeyinTakimMd -Paths $p
    exit 0
}

if ($komut -eq 'baslat' -or $komut -eq 'birlestir') {
    # INSAN ONAYI - TERMINAL KANALI (pano.ps1 'onayla' ile ayni kural): yalniz etkilesimli
    # terminal, ekrandaki kod yazilir. Ajan kabugu etkilesimsizdir -> exit 5.
    $runId = $(if ($args2.Count -ge 2) { [string]$args2[1] } else { '' })
    if (-not (Test-BeyinOnayKimligi -Id $runId -Tur $komut)) { Write-Output "Kullanim: beyin takim $komut <runId>   (sohbetten: tek satir `"$komut <runId>`")"; exit 2 }
    if (-not (Test-Path -LiteralPath (Join-Path $p.TeamRuns "$runId.json"))) { Write-Output "HATA: kosu yok: $runId (once: beyin takim plan ...)"; exit 2 }
    if ([Console]::IsInputRedirected) {
        Write-Output "HATA: onay yalniz etkilesimli terminalde verilir (bu kabuk etkilesimsiz). Sohbete tek satir yaz: $komut $runId"
        Write-BeyinMakbuz -Paths $p -Script 'takim' -Outcome 'ONAY_REDDEDILDI' -Note "$komut $runId etkilesimsiz stdin"
        exit 5
    }
    $onayKodu = '{0:D4}' -f (Get-Random -Minimum 0 -Maximum 10000)
    Write-Host "$komut $runId icin insan onayi. Onaylamak icin su kodu yaz: $onayKodu" -ForegroundColor Yellow
    $onayGiris = Read-Host 'Kod'
    if ([string]$onayGiris -ne $onayKodu) {
        Write-Output 'Kod eslesmedi, onay verilmedi.'
        Write-BeyinMakbuz -Paths $p -Script 'takim' -Outcome 'ONAY_REDDEDILDI' -Note "$komut $runId kod eslesmedi"
        exit 5
    }
    $onayKayit = Add-BeyinOnay -Paths $p -TaskId $runId -Kanal 'terminal' -Ajan 'insan' -Tur $komut
    if (-not $onayKayit.Ok) { Write-Output "HATA: onay yazilamadi - $($onayKayit.Hata)"; exit 3 }
    Write-BeyinMakbuz -Paths $p -Script 'takim' -Outcome 'ONAY_KAYDEDILDI' -Agent 'insan' -Reason 'terminal' -Note "$komut $runId"
    "Onay kaydedildi: $komut $runId (7 gun gecerli, tek kullanimlik). Simdi: beyin takim $(if ($komut -eq 'baslat') { 'start' } else { 'merge' }) --run $runId"
    $null = Update-BeyinTakimMd -Paths $p
    exit 0
}

if ($komut -eq 'izle') {
    $runId = $(if ($args2.Count -ge 2) { [string]$args2[1] } else { '' })
    if (-not $runId) { Write-Output 'Kullanim: beyin takim izle <runId> [TASK ...]'; exit 2 }
    if (-not (Test-Path -LiteralPath (Join-Path $p.TeamRuns "$runId.json"))) { Write-Output "HATA: kosu yok: $runId"; exit 2 }
    $sonuc = Open-BeyinTakimPanel -Paths $p -RunId $runId -TaskIds @($args2 | Select-Object -Skip 2)
    if ($sonuc.Ok) { "Panel acildi: $($sonuc.Acilan) sekme ($runId)$(if ($sonuc.Neden) { " - $($sonuc.Neden)" })" } else { Write-Output "HATA: panel acilamadi - $($sonuc.Neden)"; exit 1 }
    exit 0
}

if ($komut -eq 'maliyet') {
    $runId = $(if ($args2.Count -ge 2) { [string]$args2[1] } else { '' })
    if (-not $runId) { Write-Output 'Kullanim: beyin takim maliyet <runId>'; exit 2 }
    $mYol = Join-Path $p.Scripts 'maliyet.ps1'
    & powershell -NoProfile -ExecutionPolicy Bypass -File $mYol -Vault $Vault -Run $runId @($args2 | Select-Object -Skip 2)
    exit $LASTEXITCODE
}

if (-not $nodeExe) { Write-Output 'HATA: node bulunamadi (PATH). Takim kosusu AgentChef team-run.mjs ile calisir.'; exit 2 }
if (-not $engineVar) { Write-Output "HATA: team-run.mjs yok: $engine  (AgentChef 1.5.0+; ayar: beyin ayar BEYIN_AGENTCHEF_KOK <checkout>)"; exit 2 }

# 'durdur <id>' -> abort; 'durum <id>' -> status
if ($komut -eq 'durdur') { $args2[0] = 'abort'; $komut = 'abort' }
if ($komut -eq 'durum')  { $args2[0] = 'status'; $komut = 'status' }

$coz = Coz-RunId $args2
$runId = [string]$coz.Id
$gecilen = @($coz.Gecen)
$stateVar = $false; $jsonVar = $false
foreach ($a in $gecilen) { if ($a -eq '--state') { $stateVar = $true }; if ($a -eq '--json') { $jsonVar = $true } }
if (-not $stateVar) {
    New-Item -ItemType Directory -Force -Path $p.ScrState, $p.TeamRuns | Out-Null
    $gecilen += @('--state', $p.Board)
}
if (-not $jsonVar) { $gecilen += '--json' }

# INSAN ONAYI KAPISI: start <- baslat, merge <- birlestir. Onay yoksa node HIC cagrilmaz.
$onayTur = ''
if ($komut -eq 'start') { $onayTur = 'baslat' } elseif ($komut -eq 'merge') { $onayTur = 'birlestir' }
if ($onayTur) {
    if (-not $runId) { Write-Output "HATA: $komut icin --run <runId> gerekir"; exit 2 }
    if (-not (Get-BeyinOnay -Paths $p -TaskId $runId -Tur $onayTur)) {
        Write-Output "HATA: insan onayi yok: '$komut' yapilamaz ($runId). Kullanici sohbete tek satir '$onayTur $runId' yazmali (ya da terminalde: beyin takim $onayTur $runId)."
        Write-BeyinMakbuz -Paths $p -Script 'takim' -Outcome 'ONAY_YOK' -Note "$komut $runId reddedildi"
        exit 5
    }
}

# Isci paneli: premium panel (takim-izle.ps1) acilacaksa motorun ham izleyici sekmesi kapatilir.
$panelMod = [string]$(if ($env:BEYIN_TAKIM_PANEL) { $env:BEYIN_TAKIM_PANEL } else { 'on' })
if ($komut -eq 'start' -and $panelMod -ne 'motor' -and -not $env:AGENTCHEF_TEAM_PANE) { $env:AGENTCHEF_TEAM_PANE = 'off' }

$sw = [Diagnostics.Stopwatch]::StartNew()
$eapEski = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
# Deneysel opt-in (2026-10-13): motor `AGENTCHEF_TEAM_MODE=experimental` yoksa start'i "team-mode-disabled" ile
# reddeder ve doctor "opt-in" FAIL verir. Kullanici karari (2026-10-12) "once bize": sarmalayici bu bayragi
# kendi surecinde verir; disaridan baska bir deger gelmisse (ornek: kapatmak icin 'off') ona dokunmaz.
# AgentChef 1.6.0+ (2026-10-14): takim modu herkese acik, bayrak gereksiz; satir 1.5.x uyumu icin durur.
$motorSurum = ''; try { $motorSurum = [string]((Get-Content -LiteralPath (Join-Path $kok 'package.json') -Raw -Encoding UTF8 | ConvertFrom-Json).version) } catch { }
$eskiMotor = $true; try { if ($motorSurum -and ([version](($motorSurum -split '[-+]')[0]) -ge [version]'1.6.0')) { $eskiMotor = $false } } catch { }
if ($eskiMotor -and -not $env:AGENTCHEF_TEAM_MODE) { $env:AGENTCHEF_TEAM_MODE = 'experimental' }   # 1.6.0+ motorda bayrak gereksiz: ortam oldugu gibi gecer
$cikti = & $nodeExe $engine @gecilen 2>&1
$kod = $LASTEXITCODE
$ErrorActionPreference = $eapEski
$sw.Stop()
$metin = ($cikti | ForEach-Object { "$_" }) -join "`n"
if ($metin) { Write-Output $metin }
if ($kod -eq 0 -and $onayTur) {
    if (Use-BeyinOnay -Paths $p -TaskId $runId -Tur $onayTur -Kullanan 'takim') {
        Write-BeyinMakbuz -Paths $p -Script 'takim' -Outcome 'ONAY_KULLANILDI' -Note "$onayTur $runId -> $komut"
    }
}
$panelNot = ''
if ($kod -eq 0 -and $komut -eq 'start' -and $panelMod -eq 'on') {
    try { $ps = Open-BeyinTakimPanel -Paths $p -RunId $runId; $panelNot = $(if ($ps.Ok) { "panel $($ps.Acilan) sekme" } else { "panel acilamadi ($($ps.Neden))" }) } catch { $panelNot = 'panel acilamadi' }
    Write-Host "[takim] $panelNot" -ForegroundColor DarkGray
}

$mutasyon = @('plan', 'start', 'collect', 'integrate', 'verify', 'merge', 'pause', 'resume', 'abort', 'cleanup')
$mdNot = ''
if ($mutasyon -contains $komut -and -not $stateVar) {
    $md = Update-BeyinTakimMd -Paths $p
    if ($md.Ok) { $mdNot = "takim.md yenilendi ($($md.Acik) acik)" } else { $mdNot = 'takim.md YENILENEMEDI' }
    $null = Update-BeyinPanoMd -Paths $p
    Write-Host "[takim] $mdNot" -ForegroundColor DarkGray
    try {
        $bs = Sync-BeyinPanoBrifing -Paths $p -Tetik 'takim'
        if ($bs.Yeni -gt 0) { $mdNot += "; brifing $($bs.Yeni)" }
    } catch { }
}
Write-BeyinMakbuz -Paths $p -Script 'takim' -Outcome $(if ($kod -eq 0) { 'TAKIM_OK' } else { 'TAKIM_HATA' }) -DurationMs $sw.ElapsedMilliseconds -Note "$komut $runId exit=$kod $mdNot"
exit $kod
