# beyin codex gonder -Proje <dir> [-Rol agentchef:code-mapper] [-BrifDosya <file> | -Metin <text>] [-Arkaplan]
# beyin codex devam <CK-id> -Metin <text>; liste; durum <CK-id>. Only owned exec sessions.
[CmdletBinding(PositionalBinding=$false)]
param(
    [Parameter(Position=0)][ValidateSet('gonder','devam','liste','durum','isci','kapat','yetim','ac','sor','steer','interrupt','onay','sunucu','sema','tui','tetikle','limitler','temizle')][string]$Komut = 'liste',
    [Parameter(Position=1)][string]$Id = '', [string]$Proje = '', [string]$Rol = '',
    [string]$BrifDosya = '', [string]$Metin = '', [switch]$Arkaplan,
    [string]$Vault = '', [string]$EtatRacine = '', [ValidateSet('exec','app-server')][string]$Motor='app-server',
    [string]$Istek='',[ValidateSet('accept','decline','cancel')][string]$Karar='decline',[switch]$Uret,
    [ValidateSet('codex','claude')][string]$Engine='codex',[string[]]$YazmaKapsami=@(),[long]$JetonButce=2000000,
    [ValidateSet('elevated','unelevated')][string]$WindowsSandbox='elevated',
    [string]$CodexHome='', [string]$CodexProfil='', [string]$ProfilDosya='', [switch]$LimitteProfilDegistir,
    [switch]$Hepsi, [ValidateRange(1,87600)][int]$SonSaat=24, [switch]$Uygula
)
$ErrorActionPreference = 'Stop'
try {
    [Console]::OutputEncoding = New-Object Text.UTF8Encoding $false
    if (-not $Vault) { $Vault = $(if ($env:BEYIN_VAULT) { $env:BEYIN_VAULT } else { Split-Path (Split-Path $PSScriptRoot -Parent) -Parent }) }
    . (Join-Path $Vault 'motor/hooks/lib.ps1')
    if(-not $PSBoundParameters.ContainsKey('JetonButce')){$JetonButce=[long](Get-BeyinAyar 'BEYIN_CODEX_JETON_BUTCE' '2000000')}
    if($JetonButce -le 0){throw 'Worker effective token budget must be positive'}
    . (Join-Path $PSScriptRoot 'codex-kanal/core.ps1')
    . (Join-Path $PSScriptRoot 'codex-kanal/kopru.ps1')
    $ctx = New-KanalContext $Vault
    $ctx.Engine=$Engine;$ctx.WriteScopes=$YazmaKapsami;$ctx.TokenBudget=$JetonButce
    $ctx.WindowsSandbox=$WindowsSandbox
    $ctx.CodexHome=$CodexHome;$ctx.CodexProfile=$CodexProfil;$ctx.CodexProfileFile=$ProfilDosya;$ctx.AutoProfileSwitch=[bool]$LimitteProfilDegistir
    if($Engine -ne 'codex' -and ($CodexHome -or $CodexProfil -or $ProfilDosya -or $LimitteProfilDegistir)){throw 'Codex profiles require the codex engine'}
    if($Motor -eq 'exec' -and ($CodexHome -or $CodexProfil -or $ProfilDosya -or $LimitteProfilDegistir)){throw 'Codex profile selection requires app-server'}
    if($Engine -eq 'claude'){$ctx.State=Join-Path $Vault 'motor/scripts/.state/claude-kanal';$ctx.Entry=Join-Path $PSScriptRoot 'claude-kanal.ps1'}
    if ($EtatRacine) {
        if ($Komut -notin @('isci','sunucu')) { throw 'EtatRacine is internal to detached workers' }
        $ctx.State = $EtatRacine
    }
    if ($BrifDosya -and $Metin) { throw 'Choose BrifDosya or Metin, not both' }
    if ($BrifDosya) {
        $Metin = [IO.File]::ReadAllText((Resolve-Path -LiteralPath $BrifDosya).ProviderPath)
        if (-not (Test-KanalBrief $Metin)) { throw 'BrifDosya requires seven labeled Agent Brief fields' }
    }
    switch ($Komut) {
        'tui' {
            if($Id -match '^CK-'){$r=Read-KanalRecord $ctx $Id}else{$target=$(if($Proje){$Proje}else{$Id});$r=Open-KanalBridge $ctx $target $Rol -Share}
            $opened=Send-KanalBridge $ctx $r.Id 'tui'
            @{Id=$r.Id;ThreadId=$r.SessionId;Tui=$opened}|ConvertTo-Json -Depth 10
        }
        'sema' { if($Uret){Export-KanalSchema $ctx|ConvertTo-Json -Depth 10}else{Get-KanalSchemaStatus $ctx|ConvertTo-Json -Depth 10} }
        'sunucu' { Run-KanalBridgeHost $ctx $Id }
        'ac' { Open-KanalBridge $ctx $Proje $Rol | ConvertTo-Json -Depth 12 }
        {$_ -in @('sor','steer','interrupt','onay','tetikle','limitler')} {
            if($Komut -eq 'sor'){$owned=Read-KanalRecord $ctx $Id;$Metin=(New-KanalCompiledPrompt $ctx $owned.RoleText (New-KanalBrief $Metin $owned.Project)).Text}
            Send-KanalBridge $ctx $Id $Komut $Metin $Istek $Karar -Background:$Arkaplan | ConvertTo-Json -Depth 12
        }
        'kapat' { Close-KanalWorker $ctx $Id | ConvertTo-Json -Depth 10 }
        'yetim' { ConvertTo-Json -InputObject @(Get-KanalOrphans $ctx) -Depth 10 }
        'temizle' { if(Test-Path -LiteralPath $ctx.State){ConvertTo-Json -InputObject @(Archive-KanalRecords $ctx -RecentHours $SonSaat -Apply:$Uygula) -Depth 10}else{'[]'} }
        'liste' { ConvertTo-Json -InputObject @(Get-KanalRecords $ctx -Hepsi:$Hepsi -RecentHours $SonSaat | Select-Object Id,SessionId,Project,Role,Created,Started,Finished,Status,ArchivedAt,Summary,DurationSeconds,Turn,Error,Notification) -Depth 10 }
        'durum' {
            $r = @(Get-KanalRecords $ctx -Hepsi | Where-Object { $_.Id -eq $Id })
            if (-not $r.Count) { $null = Read-KanalRecord $ctx $Id }
            $r | Select-Object * -ExcludeProperty Prompt,RoleText | ConvertTo-Json -Depth 10
        }
        'gonder' {
            if ($Id) { throw 'gonder does not accept an existing id' }
            if($Motor -eq 'app-server'){
                $r=Open-KanalBridge $ctx $Proje $Rol
                $r=Send-KanalBridge $ctx $r.Id 'sor' (New-KanalCompiledPrompt $ctx $r.RoleText (New-KanalBrief $Metin $r.Project)).Text -Background:$Arkaplan
            }else{$r = Submit-KanalTurn $ctx -Proje $Proje -Rol $Rol -Metin $Metin -Arkaplan:$Arkaplan}
            $r | ConvertTo-Json -Depth 10
            if ($r.Status -in @('failed','invalid-handoff')) { exit 3 }
        }
        'devam' {
            if (-not $Id -or $Rol -or $Proje) { throw 'devam requires owned id; project and role are fixed' }
            $owned=Read-KanalRecord $ctx $Id
            if($owned.BackendStatus -eq 'unknown' -or (-not (Resolve-KanalBackend $owned.Backend) -and $owned.Backend)){throw 'Unknown backend; resume refused'}
            if($owned.EngineStatus -eq 'unknown' -or ($owned.Engine -and -not (Resolve-KanalEngine $owned.Engine))){throw 'Unknown engine; resume refused'}
            if($owned.Backend -in @('app-server','claude-stream')){
                if(-not (Test-KanalProcessIdentity $owned.Pid $owned.ProcessStart)){$owned=Resume-KanalBridge $ctx $Id}
                $r=Send-KanalBridge $ctx $Id 'sor' (New-KanalCompiledPrompt $ctx $owned.RoleText (New-KanalBrief $Metin $owned.Project)).Text -Background:$Arkaplan
            }else{$r = Submit-KanalTurn $ctx -Id $Id -Metin $Metin -Arkaplan:$Arkaplan}
            $r | ConvertTo-Json -Depth 10
            if ($r.Status -in @('failed','invalid-handoff')) { exit 3 }
        }
        'isci' {
            # Parent holds these only during admission. Wait boundedly before taking ownership.
            $deadline = [datetime]::UtcNow.AddSeconds(15); $gate = $null
            while (-not $gate) {
                try { $gate = Open-KanalLock (Join-Path $ctx.State 'admission.lock') }
                catch { if ([datetime]::UtcNow -gt $deadline) { throw }; Start-Sleep -Milliseconds 100 }
            }
            try {
                $r = Read-KanalRecord $ctx $Id
                if ($r.Pid -ne $PID -or $r.Status -ne 'queued') { throw 'Detached worker ownership mismatch' }
                $lock = Open-KanalLock (Join-Path $ctx.State ($Id + '.lock'))
            } finally { $gate.Dispose() }
            try { $null = Complete-KanalTurn $ctx $r } finally { $lock.Dispose() }
        }
    }
} catch { Write-Output ('HATA: ' + $_.Exception.Message); exit 2 }
