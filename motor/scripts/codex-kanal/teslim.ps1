function Get-KanalHash([string]$Text){
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text.Replace("`r`n","`n").TrimEnd())))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
}
function Open-KanalClaim($Context,[string]$Key){return Open-KanalLock (Join-Path $Context.State ('claim-'+(Get-KanalHash $Key)+'.lock'))}
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
