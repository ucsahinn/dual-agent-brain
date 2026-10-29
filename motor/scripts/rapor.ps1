param([string]$Vault = '', [string]$Proje = '', [string]$Komut = 'liste', [string]$Is = '', [string]$Kaynak = '', [switch]$Json)
$ErrorActionPreference = 'Stop'
if (-not $Vault) { $Vault = $(if ($env:BEYIN_VAULT) { $env:BEYIN_VAULT } else { Split-Path (Split-Path $PSScriptRoot -Parent) -Parent }) }
. (Join-Path $Vault 'motor/hooks/lib.ps1')
if (-not $Proje) { $Proje = (Get-Location).Path }
if ($Komut -eq 'kaydet') {
    $source = Resolve-BeyinContainedFile -Root $Proje -Path $Kaynak
    Write-BeyinProjectReport -Project $Proje -Task $Is -Text ([IO.File]::ReadAllText($source))
} elseif ($Komut -eq 'liste') {
    $rows = @(Get-BeyinProjectReports -Project $Proje)
    if ($Json) { ConvertTo-Json -InputObject $rows -Depth 4 } else { $rows | Format-Table Name,Outcome,Path -AutoSize | Out-String -Width 220 }
} else { throw 'rapor liste|kaydet' }
