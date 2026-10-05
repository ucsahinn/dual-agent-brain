# pano.ps1 - Ortak gorev panosu sarmalayicisi: AgentChef coordination-board.mjs + Beyin durumu.
#
# NEDEN (2026-10-04, plan #13): AgentChef'in panosu vardi (coordination-board.mjs) ama
# ortak konum, sahip, yazma kapsami ve kira yoktu; her ajan kendi state'ine bakiyordu.
# Bu sarmalayici TEK ortak state'i (<vault>\motor\scripts\.state\board.json) kullanir,
# komutu AgentChef'in kendi CLI'sina aynen gecirir (yeniden yazmaz), her degisiklikten
# sonra 10-command-center\pano.md turetilmis gorunumunu yeniler. session-start isletim
# satirina "Pano: N acik, M bu projede" bilgisini ve acik kartlarin yazma kapsamlarini
# (sahiplik uyarisi, plan #14) lib.ps1 Get-BeyinPanoDurum uretir - orada node BASLATILMAZ.
#
# Kullanim (komut ve bayraklar AgentChef'inkiyle BIREBIR; --state ve --json otomatik eklenir):
#   beyin pano                                       yardim + ozet
#   beyin pano init
#   beyin pano create --id TASK-012 --title "..." --owner-coordinator backend_coordinator
#        [--owner-agent codex --owner-session <ad>] [--write-repo Beyin --write-paths motor/x.ps1,kurulum/y.ps1]
#   beyin pano brief --task TASK-012 --brief-file brief.md     (7 alan zorunlu; brief-check ile onceden dene)
#   beyin pano brief-check --brief-file brief.md               (pano gerekmez)
#   beyin pano renew-lease --task TASK-012 --minutes 90        (yazma kapsami olan kart icin kira)
#   beyin pano transition --task TASK-012 --status in_progress (brief + canli kira yoksa reddedilir)
#   beyin pano add-evidence --task TASK-012 --evidence "..."   |  handoff  |  attach-report  |  show [--task id]
#
# Ayar: BEYIN_AGENTCHEF_KOK (AgentChef checkout; coordination-board.mjs oradan calisir).
# Hata: node CLI stderr'e {"ok":false,"error":"..."} yazar ve exit 1 verir; aynen gecirilir.
[CmdletBinding(PositionalBinding=$false)]
param(
    [string]$Vault = '',
    # create icin --owner-coordinator (katalogda ZORUNLU). Verilmezse ayar BEYIN_PANO_KOORDINATOR
    # (vars. leadership_coordinator). Gecerli: backend|devops|leadership|product|qa|ui|marketing + _coordinator.
    [string]$Koordinator = '',
    [Parameter(ValueFromRemainingArguments=$true)][string[]]$Arg = @()
)

$ErrorActionPreference = 'SilentlyContinue'
if (-not $Vault) { $Vault = $(if ($env:BEYIN_VAULT) { $env:BEYIN_VAULT } else { Split-Path (Split-Path $PSScriptRoot -Parent) -Parent }) }
if (-not (Test-Path -LiteralPath (Join-Path $Vault 'motor\hooks\lib.ps1'))) { Write-Output "HATA: vault degil: '$Vault'"; exit 2 }
. (Join-Path $Vault 'motor\hooks\lib.ps1')
$p = Get-BeyinPaths -Vault $Vault

$kok = ''
try { $kok = [string](Get-BeyinAyar 'BEYIN_AGENTCHEF_KOK' (Join-Path $env:USERPROFILE 'Desktop\codex-chef')) } catch { $kok = Join-Path $env:USERPROFILE 'Desktop\codex-chef' }
$board = Join-Path $kok 'scripts\coordination-board.mjs'
$nodeExe = (Get-Command node -ErrorAction SilentlyContinue).Source
$args2 = @($Arg | Where-Object { $null -ne $_ })

if ($args2.Count -eq 0) {
    $d = Get-BeyinPanoDurum -Paths $p
    "PANO  state: $($p.Board)  |  AgentChef: $board $(if (Test-Path -LiteralPath $board) { '' } else { '(YOK - BEYIN_AGENTCHEF_KOK ayarini kontrol et)' })"
    "  acik kart: $($d.Acik) (todo $($d.Todo), in_progress $($d.Surecte), review $($d.Inceleme)) · toplam $($d.Toplam)"
    foreach ($k in $d.Kartlar) { "  - $($k.id) [$($k.status)] $($k.title)$(if ($k.owner) { " · $($k.owner.agent)" })$(if ($k.writeScope) { " · yazar: $($k.writeScope.repo): $(@($k.writeScope.paths) -join ', ')" })$(if ($k.leaseUntil) { " · kira $($k.leaseUntil)" })" }
    ''
    'Komutlar AgentChef coordination-board ile birebir: init | create | brief | brief-check | assign | renew-lease | transition | add-evidence | handoff | resolve-handoff | handoff-check | attach-report | show'
    '  1.3.3+: in_progress icin sahip (assign) gerekir; review icin kanit; done icin --verified-by (sahip/oturum/koordinator DISINDA biri);'
    '  geri hareketler (review->in_progress, ->blocked, ->cancelled) --reason ister; show: --status open, --owner, leaseState/stale alanlari.'
    '  beyin pano create --id TASK-012 --title "..." --owner-coordinator backend_coordinator --owner-agent codex --write-repo Beyin --write-paths motor/x.ps1'
    '  beyin pano brief-check --brief-file brief.md   ·   beyin pano brief --task TASK-012 --brief-file brief.md'
    '  beyin pano renew-lease --task TASK-012 --minutes 90   ·   beyin pano transition --task TASK-012 --status in_progress'
    '  beyin pano attach-report --task TASK-012 --report-id TASK-012-sonuc.md   (review -> done icin rapor zorunlu; kimlik "<TASK>-*.md" biciminde)'
    "Turetilmis gorunum: $(Join-Path (Join-Path $Vault '10-command-center') 'pano.md')"
    exit 0
}
if (-not $nodeExe) { Write-Output 'HATA: node bulunamadi (PATH). Pano AgentChef coordination-board.mjs ile calisir.'; exit 2 }
if (-not (Test-Path -LiteralPath $board -PathType Leaf)) { Write-Output "HATA: coordination-board.mjs yok: $board  (ayar: beyin ayar BEYIN_AGENTCHEF_KOK <checkout>)"; exit 2 }

$komut = [string]$args2[0]
$gecilen = @($args2)
$stateVar = $false; $jsonVar = $false
foreach ($a in $gecilen) { if ($a -eq '--state') { $stateVar = $true }; if ($a -eq '--json') { $jsonVar = $true } }
if (-not $stateVar -and $komut -ne 'brief-check') {
    New-Item -ItemType Directory -Force -Path $p.ScrState | Out-Null
    $gecilen += @('--state', $p.Board)
    # board.json yoksa create/transition/... ENOENT veriyordu (prova bulgusu #19a):
    # init'i otomatik kos; yalniz 'show' icin dokunma (bos pano = bos liste).
    if ($komut -ne 'init' -and $komut -ne 'show' -and -not (Test-Path -LiteralPath $p.Board)) {
        $initCik = & $nodeExe $board init --state $p.Board --json 2>&1
        if ($LASTEXITCODE -ne 0) { Write-Output "HATA: pano baslatilamadi (init): $(($initCik | ForEach-Object { "$_" }) -join ' ')"; exit 1 }
        Write-Host "[pano] board.json yoktu, olusturuldu: $($p.Board)" -ForegroundColor DarkGray
    }
}
if (-not $jsonVar) { $gecilen += '--json' }
# create: koordinator katalogda ZORUNLU (AgentChef karari 2026-10-04). Oncelik: --owner-coordinator
# (aynen gecer) > -Koordinator > ayar BEYIN_PANO_KOORDINATOR (vars. leadership_coordinator).
$gecerliKoord = @('backend_coordinator', 'devops_coordinator', 'leadership_coordinator', 'product_coordinator', 'qa_coordinator', 'ui_coordinator', 'marketing_coordinator')
if ($komut -eq 'create' -and -not ($gecilen -contains '--owner-coordinator')) {
    $koord = [string]$Koordinator
    if (-not $koord) { try { $koord = [string](Get-BeyinAyar 'BEYIN_PANO_KOORDINATOR' 'leadership_coordinator') } catch { $koord = 'leadership_coordinator' } }
    if ($koord -and $koord -notlike '*_coordinator') { $koord = "${koord}_coordinator" }
    if ($gecerliKoord -notcontains $koord) { Write-Output "HATA: gecersiz koordinator '$koord' (gecerli: $($gecerliKoord -join ', '))"; exit 2 }
    $gecilen += @('--owner-coordinator', $koord)
}

$sw = [Diagnostics.Stopwatch]::StartNew()
# stderr'deki {"ok":false,"error":...} satiri KULLANICIYA ulasmali: SilentlyContinue altinda
# 2>&1 ile gelen hata kayitlari yutuluyordu (olculdu: hata ciktisi bos). Cagri suresince 'Continue'.
$eapEski = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$cikti = & $nodeExe $board @gecilen 2>&1
$kod = $LASTEXITCODE
$ErrorActionPreference = $eapEski
$sw.Stop()
$metin = ($cikti | ForEach-Object { "$_" }) -join "`n"
if ($metin) { Write-Output $metin }

$mutasyon = @('init', 'create', 'transition', 'handoff', 'attach-report', 'brief', 'renew-lease', 'add-evidence')
$mdNot = ''
if ($kod -eq 0 -and $mutasyon -contains $komut -and -not $stateVar) {
    $md = Update-BeyinPanoMd -Paths $p
    if ($md.Ok) { $mdNot = "pano.md yenilendi ($($md.Acik) acik)" } else { $mdNot = 'pano.md YENILENEMEDI' }
    Write-Host "[pano] $mdNot" -ForegroundColor DarkGray
}
Write-BeyinMakbuz -Paths $p -Script 'pano' -Outcome $(if ($kod -eq 0) { 'PANO_OK' } else { 'PANO_HATA' }) -DurationMs $sw.ElapsedMilliseconds -Note "$komut exit=$kod $mdNot"
exit $kod
