# Each host owns a KILL_ON_JOB_CLOSE job. No name-based process termination.
function Initialize-KanalJob {
    if ('BeyinChannelJob' -as [type]) { return }
    Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Threading;
public sealed class BeyinChannelJob : IDisposable {
    [StructLayout(LayoutKind.Sequential)] struct Basic { public long a,b; public uint flags; public UIntPtr min,max; public uint count; public UIntPtr affinity; public uint priority,scheduling; }
    [StructLayout(LayoutKind.Sequential)] struct Io { public ulong a,b,c,d,e,f; }
    [StructLayout(LayoutKind.Sequential)] struct Extended { public Basic basic; public Io io; public UIntPtr process,job,peakProcess,peakJob; }
    [StructLayout(LayoutKind.Sequential)] struct Accounting { public long a,b,c,d; public uint faults,total,active,terminated; }
    [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern IntPtr CreateJobObject(IntPtr attributes,string name);
    [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern IntPtr OpenJobObject(uint access,bool inherit,string name);
    [DllImport("kernel32.dll",SetLastError=true)] static extern bool SetInformationJobObject(IntPtr job,int info,ref Extended value,uint length);
    [DllImport("kernel32.dll",SetLastError=true)] static extern bool QueryInformationJobObject(IntPtr job,int info,out Accounting value,uint length,IntPtr returned);
    [DllImport("kernel32.dll",SetLastError=true)] static extern bool AssignProcessToJobObject(IntPtr job,IntPtr process);
    [DllImport("kernel32.dll",SetLastError=true)] static extern bool TerminateJobObject(IntPtr job,uint code);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr value);
    IntPtr handle;
    public string Name { get; private set; }
    public BeyinChannelJob(string name) {
        Name=name; handle=CreateJobObject(IntPtr.Zero,name);
        int error=Marshal.GetLastWin32Error();
        if(handle==IntPtr.Zero) throw new Win32Exception(error);
        if(error==183) { Dispose(); throw new InvalidOperationException("Channel job already exists"); }
        var limits=new Extended(); limits.basic.flags=0x2000;
        if(!SetInformationJobObject(handle,9,ref limits,(uint)Marshal.SizeOf(limits))) { error=Marshal.GetLastWin32Error(); Dispose(); throw new Win32Exception(error); }
    }
    public void Assign(System.Diagnostics.Process process) { if(!AssignProcessToJobObject(handle,process.Handle)) throw new Win32Exception(Marshal.GetLastWin32Error()); }
    public static bool Stop(string name) {
        var h=OpenJobObject(0xC,false,name); if(h==IntPtr.Zero) return false;
        try {
            if(!TerminateJobObject(h,125)) throw new Win32Exception(Marshal.GetLastWin32Error());
            for(int i=0;i<100;i++) { Accounting value; if(!QueryInformationJobObject(h,1,out value,(uint)Marshal.SizeOf(typeof(Accounting)),IntPtr.Zero)) throw new Win32Exception(Marshal.GetLastWin32Error()); if(value.active==0) return true; Thread.Sleep(100); }
            return false;
        } finally { CloseHandle(h); }
    }
    public void Dispose() { if(handle!=IntPtr.Zero) { CloseHandle(handle); handle=IntPtr.Zero; } GC.SuppressFinalize(this); }
    ~BeyinChannelJob() { Dispose(); }
}
'@
}
function Get-KanalOwnerSession {
    foreach ($key in @('BEYIN_KANAL_OWNER','CODEX_SESSION_ID','CODEX_THREAD_ID','CLAUDE_SESSION_ID')) {
        $value=[Environment]::GetEnvironmentVariable($key)
        if ($value) { return $value }
    }
    # When a shell did not export its session ID, bind to the nearest agent ancestor.
    $current=$PID
    for($i=0;$i -lt 16 -and $current;$i++) {
        $process=Get-CimInstance Win32_Process -Filter "ProcessId=$current" -ErrorAction SilentlyContinue
        if(-not $process){break}
        if($process.Name -match '^(codex|claude)(\.exe)?$') { return ('agent:{0}:{1}' -f $current,([datetime]$process.CreationDate).ToUniversalTime().Ticks) }
        $current=[int]$process.ParentProcessId
    }
    return ('process:{0}:{1}' -f $PID,(Get-Process -Id $PID).StartTime.ToUniversalTime().Ticks)
}
function Test-KanalProcessIdentity([int]$ProcessId,[string]$Started) {
    if(-not $ProcessId -or -not $Started){return $false}
    $p=Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
    return [bool]($p -and [math]::Abs(($p.StartTime.ToUniversalTime()-[datetime]::Parse($Started).ToUniversalTime()).TotalSeconds) -lt 1)
}
function Register-KanalProcess($Context,$Record,$Process) {
    $values=@{OwnerSession=(Get-KanalOwnerSession);HostPid=$PID;HostStart=(Get-Process -Id $PID).StartTime.ToUniversalTime().ToString('o');RootPid=$Process.Id;RootStart=$Process.StartTime.ToUniversalTime().ToString('o');JobName=$Process.ChannelJob.Name}
    foreach($key in $values.Keys){$Record | Add-Member -NotePropertyName $key -NotePropertyValue $values[$key] -Force}
    Save-KanalRecord $Context $Record
}
function Close-KanalPowerShell($Process) {
    if(-not $Process){return}
    if($Process.PSObject.Properties['ChannelJob']){$Process.ChannelJob.Dispose()}
    $Process.Dispose()
}
function Close-KanalWorker($Context,[string]$Id) {
    $r=Read-KanalRecord $Context $Id
    if(-not $r.OwnerSession -or $r.OwnerSession -cne (Get-KanalOwnerSession)){throw 'Channel owner session mismatch'}
    if($r.Status -eq 'closed'){return $r}
    if($r.RootPid -and (Get-Process -Id $r.RootPid -ErrorAction SilentlyContinue) -and -not (Test-KanalProcessIdentity $r.RootPid $r.RootStart)){throw 'Worker PID identity changed'}
    if($r.JobName -cne ('Local\Beyin-'+$Id)){throw 'Invalid worker job ownership'}
    Initialize-KanalJob
    $clean=[BeyinChannelJob]::Stop($r.JobName)
    if(-not $clean -and (Test-KanalProcessIdentity $r.RootPid $r.RootStart)){throw 'Worker job unavailable; no PID fallback is permitted'}
    $r.Status=$(if($clean -or -not (Test-KanalProcessIdentity $r.RootPid $r.RootStart)){'closed'}else{'not-clean'})
    $r|Add-Member -NotePropertyName CloseReason -NotePropertyValue 'owner' -Force
    $r | Add-Member -NotePropertyName Finished -NotePropertyValue ([datetime]::UtcNow.ToString('o')) -Force
    Save-KanalRecord $Context $r
    return $r
}
function Get-KanalOrphans($Context) {
    if(-not (Test-Path -LiteralPath $Context.State)){return}
    foreach($file in Get-ChildItem -LiteralPath $Context.State -Filter 'CK-*.json' -File){
        $r=Read-KanalRecord $Context $file.BaseName
        if($r.HostPid -and -not (Test-KanalProcessIdentity $r.HostPid $r.HostStart) -and (Test-KanalProcessIdentity $r.RootPid $r.RootStart)){
            [pscustomobject]@{Id=$r.Id;Status='orphan';RootPid=$r.RootPid;OwnerSession=$r.OwnerSession}
        }
    }
}
