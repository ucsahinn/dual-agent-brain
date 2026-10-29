function Get-KanalHash([string]$Text){
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text.Replace("`r`n","`n").TrimEnd())))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
}
function Open-KanalClaim($Context,[string]$Key){return Open-KanalLock (Join-Path $Context.State ('claim-'+(Get-KanalHash $Key)+'.lock'))}
function Get-KanalRecoveredRecord($Context,$Record){
    # Status is a read-only projection: never rewrite a live host's record or
    # send a notification just because an operator inspected an old worker.
    if($Record.Answer -or $Record.Status -notin @('failed','closed','disconnected','interrupted','invalid-handoff')){return $Record}
    if($Record.Engine -and $Record.Engine -ne 'codex'){return $Record}
    if($Record.SessionId -cnotmatch '^[a-f0-9-]{36}$'){return $Record}
    $target=[string]$Record.ActiveTurn
    if(-not $target -and $Record.PendingTurn){$target=[string]$Record.PendingTurn.Id}
    $root=$(if($Context.RolloutRoot){$Context.RolloutRoot}else{Join-Path $env:USERPROFILE '.codex/sessions'})
    if(-not $Context.RolloutRoot){
        $launch=Join-Path (Join-Path $Context.State $Record.Id) 'launch.json'
        if(Test-Path -LiteralPath $launch -PathType Leaf){
            try{$cfg=[IO.File]::ReadAllText($launch)|ConvertFrom-Json
                if($cfg.id -ceq $Record.Id -and $cfg.owner -ceq $Record.OwnerSession){
                    $index=0;if($Record.ProfileIndex){$index=[int]$Record.ProfileIndex}
                    $profile=@($cfg.profiles)[$index]
                    if($profile.home){$root=Join-Path $profile.home 'sessions'}
                }
            }catch{}
        }
    }
    $recovery=@{Status='unavailable';Source='owned-rollout';OriginalStatus=$Record.Status;Hint=('Inspect rollout *'+$Record.SessionId+'*.jsonl under '+$root+' for the matching turn task_complete.last_agent_message; no automatic replay.')}
    $Record|Add-Member -NotePropertyName Recovery -NotePropertyValue $recovery -Force
    if($Record.ActiveTurn){$Record|Add-Member -NotePropertyName PendingTurn -NotePropertyValue @{Id=$target;Turn=$Record.Turn} -Force;$Record.ActiveTurn=''}
    # Repeated identical prompts are not unique turn evidence. Without the
    # persisted turn identity, show the route instead of claiming old work anew.
    if(-not $target){return $Record}
    $reader=$null
    try{
        $files=@(Get-ChildItem -LiteralPath $root -Recurse -File -Filter ('*'+$Record.SessionId+'*.jsonl') -ErrorAction Stop)
        if($files.Count -ne 1 -or $files[0].Length -gt 134217728){return $Record}
        $stream=[IO.File]::Open($files[0].FullName,'Open','Read',([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
        $reader=New-Object IO.StreamReader $stream
        $sessionOk=$false;$turn='';$answer='';$finished=''
        $watch=[Diagnostics.Stopwatch]::StartNew()
        while($null -ne ($line=$reader.ReadLine())){
            if($watch.Elapsed.TotalSeconds -gt 5){return $Record}
            # An incomplete trailing append is safe to ignore; never infer success.
            try{$e=$line|ConvertFrom-Json -ErrorAction Stop}catch{continue}
            if($e.type -eq 'session_meta'){$sessionOk=($e.payload.id -ceq $Record.SessionId -and $e.payload.cwd -eq $Record.Project)}
            if($e.type -eq 'turn_context'){$turn=[string]$e.payload.turn_id}
            if($e.type -eq 'event_msg' -and $e.payload.type -eq 'task_complete'){
                $eventTurn=[string]$e.payload.turn_id;if(-not $eventTurn){$eventTurn=$turn}
                $belongs=($target -ceq $eventTurn)
                if($sessionOk -and $belongs -and $e.payload.last_agent_message){$answer=[string]$e.payload.last_agent_message;$finished=[string]$e.timestamp}
            }
        }
        if(-not $answer -or -not $sessionOk){return $Record}
        $answer=Protect-KanalText $Context $answer
        try{$answer=ConvertFrom-KanalHandoffJson $answer}catch{}
        $valid=Test-KanalHandoff $answer
        $Record.Answer=$answer;$Record.Status=$(if($valid){'completed'}else{'invalid-handoff'})
        $Record|Add-Member -NotePropertyName ActiveTurn -NotePropertyValue '' -Force
        $Record.PSObject.Properties.Remove('PendingTurn')
        $Record|Add-Member -NotePropertyName HandoffValid -NotePropertyValue $valid -Force
        $Record|Add-Member -NotePropertyName HandoffCheck -NotePropertyValue 'rollout-local-six-fields' -Force
        $Record|Add-Member -NotePropertyName Summary -NotePropertyValue (($answer -replace '\s+',' ').Substring(0,[math]::Min(240,($answer -replace '\s+',' ').Length))) -Force
        $Record|Add-Member -NotePropertyName Finished -NotePropertyValue $finished -Force
        $recovery.Status='recovered';$recovery.Path=$files[0].FullName;$recovery.TurnId=$target;$recovery.OriginalError=$Record.Error
        $Record.Error=''
    }catch{$recovery.Status='unavailable'}finally{if($reader){$reader.Dispose()}}
    return $Record
}
function Get-KanalContinuation([datetime]$LastTurn,[string]$TaskKey,[string]$PreviousKey,[long]$ContextTokens,[int]$Requests){
    $reason=$(if($TaskKey -cne $PreviousKey){'task-changed'}elseif(([datetime]::UtcNow-$LastTurn.ToUniversalTime()).TotalMinutes -ge 60){'age'}elseif($ContextTokens -gt 200000){'context'}elseif($Requests -gt 300){'requests'}else{'same-task-recent'})
    return @{Decision=$(if($reason -eq 'same-task-recent'){'resume'}else{'fresh'});Reason=$reason}
}
function Get-KanalDelivery($Context,$Record){
    # Verify channel ownership before looking up a rollout; never inspect foreign TUI logs.
    $owned=Read-KanalRecord $Context $Record.Id
    if($owned.OwnerSession -cne (Get-KanalOwnerSession) -or $owned.SessionId -cne $Record.SessionId -or $Record.SessionId -cnotmatch '^[a-f0-9-]{36}$'){return @{Status='belirsiz'}}
    $root=$(if($Context.RolloutRoot){$Context.RolloutRoot}else{Join-Path $env:USERPROFILE '.codex/sessions'})
    if(-not (Test-Path -LiteralPath $root)){return @{Status='belirsiz'}}
    $files=@(Get-ChildItem -LiteralPath $root -Recurse -File -Filter ('*'+$Record.SessionId+'*.jsonl'))
    if($files.Count -ne 1 -or $files[0].Length -gt 16777216){return @{Status='belirsiz'}}
    $seen=$false;$sessionOk=$false;$processed=$false
    try{
        foreach($line in [IO.File]::ReadAllLines($files[0].FullName)){
            $e=$line|ConvertFrom-Json
            if($e.type -eq 'session_meta'){$sessionOk=($e.payload.id -ceq $Record.SessionId)}
            if($e.type -eq 'event_msg' -and $e.payload.type -eq 'user_message' -and (Get-KanalHash ([string]$e.payload.message)) -eq $Record.PromptHash){$seen=$true;$processed=$false}
            if($seen -and $e.type -eq 'event_msg' -and $e.payload.type -eq 'task_complete'){$processed=$true}
            if($e.type -eq 'response_item' -and $e.payload.role -eq 'user'){
                $text=(@($e.payload.content|Where-Object {$_.type -in @('input_text','text')}|ForEach-Object {$_.text}) -join "`n")
                if((Get-KanalHash $text) -eq $Record.PromptHash){$seen=$true;$processed=$false}
            }
            if($seen -and $e.type -eq 'response_item' -and $e.payload.role -eq 'assistant' -and $e.payload.phase -eq 'final_answer'){$processed=$true}
        }
    }catch{return @{Status='belirsiz'}}
    return @{Status=$(if(-not $sessionOk){'belirsiz'}elseif($processed){'islendi'}elseif($seen){'alindi-cevapsiz'}else{'yutuldu'});PromptHash=$Record.PromptHash}
}
function New-KanalSetupFailure {
    $error=New-Object InvalidOperationException 'Sandbox setup refresh had errors'
    $error.Data['KanalSetupFailure']=$true
    return $error
}
function Test-KanalToolSetupFailure($Event){
    if($Event.type -ne 'item.completed'){return $false}
    $item=$Event.item
    if($item.type -eq 'command_execution' -and ($item.status -eq 'failed' -or ($null -ne $item.exit_code -and $item.exit_code -ne 0))){return ([string]$item.aggregated_output -match 'setup refresh had errors')}
    if($item.type -eq 'mcp_tool_call' -and $item.status -eq 'failed' -and $item.error){return (($item.error|ConvertTo-Json -Depth 8) -match 'setup refresh had errors')}
    return $false
}
