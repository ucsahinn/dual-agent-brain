# beyin kapasite [-Json] - canli es zamanli ajan onerisi (kaynak bekcisiyle ayni olcum, tek formul).
# Yalniz OLCER ve gosterir; .state\kapasite.json dosyasini tazeler (AgentChef takim kosusu onu okur).
param([string]$Vault, [switch]$Json)
$ErrorActionPreference = 'Stop'
if (-not $Vault) { $Vault = $(if ($env:BEYIN_VAULT) { $env:BEYIN_VAULT } else { Split-Path (Split-Path $PSScriptRoot -Parent) -Parent }) }
. (Join-Path $Vault 'motor\hooks\lib.ps1')
$p = Get-BeyinPaths -Vault $Vault
$k = Get-BeyinKaynakOzeti -Paths $p
if (-not $k.Ok) { if ($Json) { Write-Output (@{ v = 1; hata = 'kaynak olculemedi' } | ConvertTo-Json -Compress) } else { Write-Output 'beyin kapasite: kaynak olculemedi' }; exit 3 }
$o = Get-BeyinKapasiteKayit $k
if ($Json) { Write-Output ($o | ConvertTo-Json -Compress); exit 0 }
Write-Output ("es zamanli ajan onerisi: {0} (tavan {1})" -f $o.onerilen, $o.tavan)
Write-Output ("neden: {0}" -f $o.neden)
Write-Output ("olcum: commit %{0} · bos RAM {1} GB · {2}" -f $o.commitYuzde, $o.bosRamGB, $o.ts)
Write-Output ("dosya: {0}" -f (Join-Path $p.ScrState 'kapasite.json'))
