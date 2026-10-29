param([string]$Vault = '', [string]$Proje = '', [string]$Is = '', [switch]$Json)
$ErrorActionPreference = 'Stop'
if (-not $Vault) { $Vault = $(if ($env:BEYIN_VAULT) { $env:BEYIN_VAULT } else { Split-Path (Split-Path $PSScriptRoot -Parent) -Parent }) }
. (Join-Path $Vault 'motor/hooks/lib.ps1')
$rows = @(Get-BeyinSessionHistory -Paths (Get-BeyinPaths -Vault $Vault) -Project $Proje -Task $Is)
if ($Json) { ConvertTo-Json -InputObject $rows -Depth 6 } else { $rows | Format-Table zaman,motor,isciId,oturumId,proje,isAnahtari,olay -AutoSize | Out-String -Width 220 }
