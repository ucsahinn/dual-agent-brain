# Same Windows-session mutex for exec and app-server, independent of vault/state.
param([switch]$Serve,[string]$Name='Local\Beyin-codex-setup',[int]$WaitMs=60000,[int]$HoldMs=60000)
function Open-KanalSetupLock([string]$Name='Local\Beyin-codex-setup',[int]$WaitMs=60000){
    $mutex=New-Object Threading.Mutex($false,$Name)
    try{
        try{$acquired=$mutex.WaitOne($WaitMs)}catch [Threading.AbandonedMutexException]{$acquired=$true}
        if(-not $acquired){throw 'Codex setup admission lock timed out'}
        return $mutex
    }catch{$mutex.Dispose();throw}
}
function Close-KanalSetupLock($Mutex,$Record=$null,[string]$Reason=''){
    if($Mutex){try{$Mutex.ReleaseMutex()}finally{$Mutex.Dispose()}
        if($Record -and $Record.SetupLock){$Record.SetupLock.ReleasedAt=[datetime]::UtcNow.ToString('o');$Record.SetupLock.ReleaseReason=$Reason}
    }
}
if($Serve){
    Add-Type -TypeDefinition 'public static class BeyinSetupInput { public static bool Wait(int milliseconds) { return System.Threading.Tasks.Task.Run(() => System.Console.In.ReadLine()).Wait(milliseconds); } }'
    $lease=Open-KanalSetupLock $Name $WaitMs
    try{[Console]::Out.WriteLine('ready');[Console]::Out.Flush();[void][BeyinSetupInput]::Wait($HoldMs)}
    finally{Close-KanalSetupLock $lease}
}
