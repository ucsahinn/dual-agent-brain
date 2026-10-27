. (Join-Path $PSScriptRoot 'sema.ps1')
function Get-KanalActiveCount($Context){
    $count=Get-KanalTeamCount $Context
    $states=@($Context.State,(Join-Path $Context.Vault 'motor/scripts/.state/codex-kanal'),(Join-Path $Context.Vault 'motor/scripts/.state/claude-kanal'))|Select-Object -Unique
    foreach($state in $states){$other=$Context.Clone();$other.State=$state;foreach($r in Get-KanalRecords $other){if(($r.Status -in @('queued','running') -or ($r.Backend -in @('app-server','claude-stream') -and $r.Status -in @('ready','completed','invalid-handoff','limit-waiting'))) -and (Test-KanalProcessIdentity $r.Pid $r.ProcessStart)){$count++}}}
    return $count
}
function Resolve-KanalLaunch($Context,[string]$Engine='codex') {
    if($Engine -eq 'codex'){return Resolve-KanalCodex $Context}
    $node=Get-Command node.exe -CommandType Application -ErrorAction Stop | Select-Object -First 1
    $native=Get-Command ($Engine+'.exe') -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if($native){return @{command=$native.Source;args=@()}}
    $shim=Get-Command ($Engine+'.cmd') -CommandType Application -ErrorAction Stop | Select-Object -First 1
    $relative=$(if($Engine -eq 'codex'){'node_modules/@openai/codex/bin/codex.js'}else{'node_modules/@anthropic-ai/claude-code/cli.js'})
    $cli=Join-Path (Split-Path $shim.Source -Parent) $relative
    if(-not (Test-Path -LiteralPath $cli -PathType Leaf)){throw 'Unsupported CLI shim layout; install/repair is an operator action'}
    return @{command=$node.Source;args=@($cli)}
}
function Open-KanalBridge($Context,[string]$Project,[string]$Role='', [switch]$Share) {
    if(-not (Test-Path -LiteralPath $Project -PathType Container)){throw 'Project directory does not exist'}
    New-Item -ItemType Directory -Force $Context.State | Out-Null
    $gate=Open-KanalLock (Join-Path $Context.State 'admission.lock')
    try{
        $cap=Get-KanalCapacity $Context
        $count=Get-KanalActiveCount $Context
        if($cap.onerilen -le $count){throw "capacity rejected: active=$count recommended=$($cap.onerilen)"}
        $roleInfo=Resolve-KanalRole $Context $Role
        $engine=$(if($Context.Engine){$Context.Engine}else{'codex'})
        $id='CK-'+[guid]::NewGuid().ToString('N');$directory=Join-Path $Context.State $id
        New-Item -ItemType Directory -Force $directory | Out-Null
        $record=[pscustomobject]@{Owner='beyin-codex-kanal-v1';Id=$id;OwnerSession=(Get-KanalOwnerSession);Backend='app-server';Project=(Resolve-Path -LiteralPath $Project).ProviderPath;Role=$roleInfo.Name;RoleModel=$roleInfo.Model;Sandbox=$roleInfo.Sandbox;RoleText=(Protect-KanalText $Context $roleInfo.Text);Status='queued';SessionId='';Turn=0;Created=[datetime]::UtcNow.ToString('o');Started='';Finished='';Pid=0;ProcessStart='';Prompt='';Answer='';Summary='';Error='';DurationSeconds=0;Background=$true;HandoffValid=$false;HandoffCheck='';Notification=''}
        Save-KanalRecord $Context $record
        $record|Add-Member -NotePropertyName WindowsSandbox -NotePropertyValue $(if($Context.WindowsSandbox){$Context.WindowsSandbox}else{'elevated'}) -Force
        if($engine -eq 'codex'){
            $models=Get-KanalModelProfile $Context
            $record|Add-Member -NotePropertyName CatalogModel -NotePropertyValue $roleInfo.Model -Force
            $record|Add-Member -NotePropertyName ReviewModel -NotePropertyValue $models.ReviewModel -Force
            if(-not $record.RoleModel){$record.RoleModel=$models.Model}
        }
        if($engine -eq 'claude'){$record.Backend='claude-stream';$record.RoleModel='';$record|Add-Member -NotePropertyName McpDiet -NotePropertyValue @{Enabled=@();Policy='strict-empty-config'} -Force}
        $record|Add-Member -NotePropertyName WriteScopes -NotePropertyValue @($Context.WriteScopes) -Force
        $record|Add-Member -NotePropertyName ExplicitWriteScopes -NotePropertyValue ([bool]@($Context.WriteScopes|Where-Object {$_}).Count) -Force
        Save-KanalRecord $Context $record
        $launch=$(if($Context.BridgeLaunch){$Context.BridgeLaunch}else{Resolve-KanalLaunch $Context $engine})
        if(-not $Context.BridgeLaunch -and $engine -eq 'codex'){Set-KanalCodexRecord $Context $record $launch;Save-KanalRecord $Context $record}
        if(-not $Context.BridgeLaunch -and $engine -eq 'codex'){$record|Add-Member -NotePropertyName Schema -NotePropertyValue (Get-KanalSchemaStatus $Context) -Force;if($record.Schema.Changed -or -not $record.Schema.Generated){Write-Warning $record.Schema.Notice};Save-KanalRecord $Context $record}
        $arguments=@($launch.args)
        $dietFile=''
        if(-not $Context.BridgeLaunch -and $engine -eq 'codex'){$profile=New-KanalMcpProfile $Context $record.Role $directory;$dietFile=$profile.Path;$record|Add-Member -NotePropertyName McpDiet -NotePropertyValue @{Enabled=$profile.Enabled;Disabled=$profile.Disabled} -Force;$arguments+=@('-c','approval_policy="on-request"','-c','approvals_reviewer="auto_review"');$arguments+=@($profile.Arguments);$arguments+=@('app-server','--listen','stdio://');Save-KanalRecord $Context $record}
        $paths=Get-BeyinPaths -Vault $Context.Vault
        $handoffDirectory=$(if($Context.BridgeLaunch){Join-Path $Context.State 'fixture-notifications'}else{$paths.Handoff})
        $checker='';$chef=Get-KanalChefRoot;if($chef -and (Test-Path (Join-Path $chef 'scripts/coordination-board.mjs'))){$checker=Join-Path $chef 'scripts/coordination-board.mjs'}
        $config=@{state=$Context.State;id=$id;owner=$record.OwnerSession;command=$launch.command;args=$arguments;timeout=15000;share=[bool]$Share;handoffDirectory=$handoffDirectory;engine=$engine;readOnly=($record.Sandbox -eq 'read-only');tokenBudget=
            $(if($Context.TokenBudget){$Context.TokenBudget}else{[long](Get-BeyinAyar 'BEYIN_CODEX_JETON_BUTCE' '2000000')});pricesFile=(Join-Path $Context.Vault 'motor/scripts/fiyat.json');checker=$checker;dietFile=$dietFile}
        if($Context.SetupLockOptions){$config.setupLockOptions=$Context.SetupLockOptions}
        [IO.File]::WriteAllText((Join-Path $directory 'launch.json'),($config|ConvertTo-Json -Depth 12),(New-Object Text.UTF8Encoding $false))
        $code='& '+(Quote-KanalLiteral $Context.Entry)+' -Komut sunucu -Id '+(Quote-KanalLiteral $id)+' -Vault '+(Quote-KanalLiteral $Context.Vault)+' -EtatRacine '+(Quote-KanalLiteral $Context.State)
        $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($code))
        $child=Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -WindowStyle Hidden -WorkingDirectory $Context.Vault -ArgumentList @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-EncodedCommand',$encoded) -PassThru
        $record.Pid=$child.Id;$record.ProcessStart=$child.StartTime.ToUniversalTime().ToString('o');Save-KanalRecord $Context $record;$child.Dispose()
    }finally{$gate.Dispose()}
    $until=[datetime]::UtcNow.AddSeconds(95) # setup admission (60s) + RPC initialization
    do{[Threading.Thread]::Sleep(50);$record=Read-KanalRecord $Context $id;if($record.Status -in @('failed','closed')){throw ('Channel host failed during startup: '+$record.Error)}}while($record.Status -eq 'queued' -and [datetime]::UtcNow -lt $until)
    if($record.Status -eq 'queued'){try{Close-KanalWorker $Context $id|Out-Null}catch{};throw "Channel startup timeout; inspect owned worker $id"}
    return $record
}
function Run-KanalBridgeHost($Context,[string]$Id) {
    $until=[datetime]::UtcNow.AddSeconds(15);$gate=$null
    while(-not $gate){try{$gate=Open-KanalLock (Join-Path $Context.State 'admission.lock')}catch{if([datetime]::UtcNow -gt $until){throw};[Threading.Thread]::Sleep(50)}}
    try{$r=Read-KanalRecord $Context $Id;if($r.Pid -ne $PID){throw 'Host PID mismatch'}}finally{$gate.Dispose()}
    $node=(Get-Command node.exe -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
    $launch=Join-Path (Join-Path $Context.State $Id) 'launch.json'
    $code='$null=[Console]::In.ReadLine(); & '+(Quote-KanalLiteral $node)+' '+(Quote-KanalLiteral (Join-Path $PSScriptRoot 'host-service.mjs'))+' '+(Quote-KanalLiteral $launch)+'; exit $LASTEXITCODE'
    $process=Start-KanalPowerShell $code $r.Project -JobName ('Local\Beyin-'+$Id)
    try{
        Register-KanalProcess $Context $r $process
        $output=$process.StandardOutput.ReadToEndAsync();$errors=$process.StandardError.ReadToEndAsync();$process.StandardInput.Close()
        $process.WaitForExit() # This is the persistent host; each client probe has its own deadline.
    }finally{Close-KanalPowerShell $process}
}
function Send-KanalBridge($Context,[string]$Id,[string]$Method,[string]$Text='', [string]$RequestId='',[string]$Decision='', [switch]$Background) {
    $r=Read-KanalRecord $Context $Id
    if($r.OwnerSession -cne (Get-KanalOwnerSession)){throw 'Channel owner session mismatch'}
    if($r.Backend -notin @('app-server','claude-stream')){throw 'Worker does not use a persistent backend'}
    if(-not (Test-KanalProcessIdentity $r.Pid $r.ProcessStart)){throw 'Channel host disconnected'}
    $request=[guid]::NewGuid().ToString();$directory=Join-Path $Context.State $Id
    $file=Join-Path (Join-Path $directory 'commands') ($request+'.json')
    $message=@{owner=$r.OwnerSession;method=$Method;text=(Protect-KanalText $Context $Text);requestId=$RequestId;decision=$Decision}
    if($Method -eq 'sor'){
        $gate=Open-KanalLock (Join-Path $Context.State 'admission.lock')
        try{
            $scope=[regex]::Match($Text,'(?ms)^Write scope:\s*(.*?)^Boundaries:').Groups[1].Value
            $key=$(if($scope){Get-KanalHash ($r.Project+'|'+$scope)}elseif($r.TaskKey){$r.TaskKey}else{Get-KanalHash ($r.Project+'|'+$Text)})
            if(@(Get-KanalRecords $Context|Where-Object {$_.Id -ne $Id -and $_.TaskKey -eq $key -and $_.Status -in @('queued','running')}).Count){throw 'Task already claimed by another worker'}
            $claims=Join-Path $Context.State 'task-claims';New-Item -ItemType Directory -Force $claims|Out-Null
            $claimPath=Join-Path $claims ($key+'.json')
            if(Test-Path -LiteralPath $claimPath){$previous=[IO.File]::ReadAllText($claimPath)|ConvertFrom-Json;if($previous.Id -ne $Id){$claimOwner=Read-KanalRecord $Context $previous.Id;$done=Join-Path (Join-Path $Context.State $previous.Id) ('claim-done-'+$previous.Request);if(-not (Test-Path -LiteralPath $done) -and $claimOwner.Status -notin @('closed','failed','stalled','disconnected') -and (Test-KanalProcessIdentity $claimOwner.Pid $claimOwner.ProcessStart)){throw 'Task already claimed by another worker'}}}
            [IO.File]::WriteAllText($claimPath,(@{Id=$Id;Request=$request}|ConvertTo-Json -Compress),(New-Object Text.UTF8Encoding $false))
            $message.taskKey=$key
            $message.claimRequest=$request
        }finally{$gate.Dispose()}
    }
    $temp=$file+'.tmp';[IO.File]::WriteAllText($temp,($message|ConvertTo-Json -Depth 8),(New-Object Text.UTF8Encoding $false));[IO.File]::Move($temp,$file)
    if($Background){return Read-KanalRecord $Context $Id}
    $response=Join-Path (Join-Path $directory 'responses') ($request+'.json');$until=[datetime]::UtcNow.AddSeconds($Context.Timeout)
    while(-not (Test-Path -LiteralPath $response)){
        if([datetime]::UtcNow -gt $until){throw 'Channel response timeout; worker may still be running'}
        [Threading.Thread]::Sleep(50)
    }
    $result=[IO.File]::ReadAllText($response)|ConvertFrom-Json
    [IO.File]::Delete($response)
    if(-not $result.ok){throw $result.error}
    return $result.result
}
