# beyin-launcher.ps1 (SIM) - ~\.claude\hooks\ altinda durur.
#
# NEDEN VAR: Codex'in ~\.codex\hooks.json dosyasi bu yola isaret ediyor ve o dosya
# her kanca tanimini SHA-256 ile hash'ler; degisen tanim /hooks ile yeniden
# onaylanana kadar SESSIZCE atlanir. Bu yuzden yol DEGISTIRILMEZ.
#
# Gercek launcher artik ajan-tarafsiz konumda: ~\.beyin\beyin-launcher.ps1.
# Bu dosya yalnizca oraya yonlendirir. Claude Code dogrudan gercek launcher'i
# cagirir; Codex bu sim uzerinden gelir. Ikisi de AYNI motoru calistirir.
#
# BU DOSYANIN KAYNAGI: <vault>\kurulum\beyin-launcher-sim.ps1 (kur.ps1 kopyalar).
param(
    [Parameter(Mandatory = $true)][string]$Hook,
    [string]$Agent = 'codex'
)
$gercek = Join-Path $env:USERPROFILE '.beyin\beyin-launcher.ps1'
if (-not (Test-Path -LiteralPath $gercek)) { exit 0 }   # kurulum yok: sessiz cik
& $gercek -Hook $Hook -Agent $Agent
exit $LASTEXITCODE
