# Fixed producer entry point. Reads only a channel-owned record below this vault.
param([Parameter(Mandatory=$true)][string]$Vault,
      [Parameter(Mandatory=$true)][ValidateSet('codex','claude')][string]$Engine,
      [Parameter(Mandatory=$true)][ValidatePattern('\ACK-[a-f0-9]{32}\z')][string]$Id)
$ErrorActionPreference='Stop'
try {
    . (Join-Path (Split-Path $PSScriptRoot -Parent) 'hooks/lib.ps1')
    $p=Get-BeyinPaths -Vault $Vault
    $root=Join-Path $p.ScrState ($Engine+'-kanal')
    $file=Resolve-BeyinContainedFile -Root $root -Path (Join-Path $root ($Id+'.json'))
    $r=[IO.File]::ReadAllText($file) | ConvertFrom-Json
    if ($r.Id -cne $Id -or $r.Engine -cne $Engine -or $r.Owner -ne 'beyin-codex-kanal-v1') { throw 'Evidence owner mismatch' }
    Sync-BeyinChannelRecordEvidence -Paths $p -Record $r
} catch { Write-Error 'Channel evidence could not be persisted; inspect the local record'; exit 1 }
