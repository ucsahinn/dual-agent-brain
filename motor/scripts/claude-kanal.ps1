[CmdletBinding(PositionalBinding=$false)]
param(
 [Parameter(Position=0)][string]$Komut='liste',[Parameter(Position=1)][string]$Id='',
 [string]$Proje='',[string]$Rol='',[string]$BrifDosya='',[string]$Metin='',
 [switch]$Arkaplan,[string]$Vault='',[string]$EtatRacine='',
 [string]$Istek='',[ValidateSet('accept','decline','cancel')][string]$Karar='decline',
 [string[]]$YazmaKapsami=@(),[long]$JetonButce=2000000
)
& (Join-Path $PSScriptRoot 'codex-kanal.ps1') @PSBoundParameters -Engine claude
exit $LASTEXITCODE
