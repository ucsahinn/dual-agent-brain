# One source of truth for launch AND version. No package.json version guesses.
function Get-KanalCodexCandidates($Context){
    if($Context.ContainsKey('CodexCandidates')){return @($Context.CodexCandidates)}
    $paths=@()
    foreach($name in @('codex.cmd','codex.exe')){$paths+=@(Get-Command $name -All -CommandType Application -ErrorAction SilentlyContinue|ForEach-Object Source)}
    foreach($directory in ($env:PATH -split ';')){if($directory){foreach($name in @('codex.cmd','codex.exe')){$path=Join-Path $directory.Trim('"') $name;if(Test-Path -LiteralPath $path -PathType Leaf){$paths+=$path}}}}
    $paths+=@((Join-Path $env:APPDATA 'npm/codex.cmd'),(Join-Path $env:USERPROFILE '.local/bin/codex.exe'),(Join-Path $env:USERPROFILE '.local/bin/codex.cmd'))
    return @($paths|Where-Object {Test-Path -LiteralPath $_ -PathType Leaf}|ForEach-Object {[IO.Path]::GetFullPath($_)}|Sort-Object -Unique)
}
function ConvertTo-KanalCodexLaunch([string]$Path){
    $full=(Resolve-Path -LiteralPath $Path -ErrorAction Stop).ProviderPath
    if([IO.Path]::GetExtension($full) -ieq '.cmd'){
        $cli=Join-Path (Split-Path $full -Parent) 'node_modules/@openai/codex/bin/codex.js'
        if((Test-Path -LiteralPath $cli -PathType Leaf) -and (Get-Item -LiteralPath $full).Length -lt 65536 -and [IO.File]::ReadAllText($full) -match 'node_modules[\\/]@openai[\\/]codex[\\/]bin[\\/]codex\.js'){
            return @{command=(Get-Command node.exe -CommandType Application -ErrorAction Stop|Select-Object -First 1).Source;args=@($cli);Path=$full}
        }
        return @{command=(Get-Command node.exe -CommandType Application -ErrorAction Stop|Select-Object -First 1).Source;args=@((Join-Path $PSScriptRoot 'cmd-entry.mjs'),$full);Path=$full}
    }
    if([IO.Path]::GetExtension($full) -ine '.exe'){throw 'Codex path must be an exe or cmd launcher'}
    return @{command=$full;args=@();Path=$full}
}
function Get-KanalCodexVersion($Context,$Launch){
    $arguments=@($Launch.args)+@('--version');$quoted=@($arguments|ForEach-Object {Quote-KanalLiteral $_}) -join ','
    $code='& '+(Quote-KanalLiteral $Launch.command)+' @('+ $quoted +'); exit $LASTEXITCODE'
    $p=Start-KanalPowerShell $code $Context.Vault
    try{
        $out=$p.StandardOutput.ReadToEndAsync();$err=$p.StandardError.ReadToEndAsync();$p.StandardInput.Close()
        $timeout=$(if($Context.VersionTimeoutMs){[int]$Context.VersionTimeoutMs}else{5000})
        if(-not $p.WaitForExit($timeout) -or $p.ExitCode -ne 0){throw 'Codex version probe failed or timed out'}
        $m=[regex]::Match($out.Result.Trim(),'(?m)^codex(?:-cli)?\s+(\d+\.\d+\.\d+(?:-[A-Za-z0-9.-]+)?)(?:\+[A-Za-z0-9.-]+)?\s*$')
        if(-not $m.Success){throw 'Codex version response was not recognized'}
        return $m.Groups[1].Value
    }finally{Close-KanalPowerShell $p}
}
function Compare-KanalCodexVersion([string]$Left,[string]$Right){
    $l=$Left -split '-',2;$r=$Right -split '-',2;$base=([version]$l[0]).CompareTo([version]$r[0]);if($base){return $base}
    if($l.Count -eq 1 -and $r.Count -eq 1){return 0};if($l.Count -eq 1){return 1};if($r.Count -eq 1){return -1}
    $lp=$l[1].Split('.');$rp=$r[1].Split('.')
    for($i=0;$i -lt [math]::Min($lp.Count,$rp.Count);$i++){
        if($lp[$i] -ceq $rp[$i]){continue};$ln=$lp[$i] -match '^\d+$';$rn=$rp[$i] -match '^\d+$'
        if($ln -and $rn){return ([decimal]$lp[$i]).CompareTo([decimal]$rp[$i])};if($ln){return -1};if($rn){return 1};return [string]::CompareOrdinal($lp[$i],$rp[$i])
    };return $lp.Count.CompareTo($rp.Count)
}
function Resolve-KanalCodex($Context){
    if($Context.ResolvedCodex){return $Context.ResolvedCodex}
    # Context.Codex is the existing explicit fixture injection, never a CLI switch.
    $override=$(if($Context.Codex){$Context.Codex}elseif($Context.ContainsKey('CodexSetting')){$Context.CodexSetting}else{Get-BeyinAyar 'BEYIN_CODEX_YOLU' ''})
    $paths=$(if($Context.Codex){@($Context.Codex)}else{@(Get-KanalCodexCandidates $Context)+@($override)|Where-Object {$_}|Sort-Object -Unique})
    if($paths.Count -gt 16){throw 'Too many Codex candidates (maximum 16); choose BEYIN_CODEX_YOLU'}
    $candidates=@();$best=$null;$chosen=$null
    foreach($path in $paths){
        try{$launch=ConvertTo-KanalCodexLaunch $path;$version=Get-KanalCodexVersion $Context $launch;$item=@{Path=$launch.Path;Version=$version;Probe='ok'};$launch.Version=$version
            if($override -and $launch.Path -ieq [IO.Path]::GetFullPath($override)){$chosen=$launch}
            if(-not $best -or (Compare-KanalCodexVersion $version $best.Version) -gt 0 -or ((Compare-KanalCodexVersion $version $best.Version) -eq 0 -and [string]::Compare($launch.Path,$best.Path,[StringComparison]::OrdinalIgnoreCase) -lt 0)){$best=$launch}
        }catch{$item=@{Path=[string]$path;Version='';Probe='unavailable'};if($override -and [IO.Path]::GetFullPath($path) -ieq [IO.Path]::GetFullPath($override)){throw 'Explicit BEYIN_CODEX_YOLU could not be version-validated'}}
        $candidates+=$item
    }
    if($override){if(-not $chosen){throw 'Explicit BEYIN_CODEX_YOLU was not found'};$best=$chosen}
    if(-not $best){throw 'No version-validated Codex installation found'}
    $versions=@($candidates|Where-Object {$_.Probe -eq 'ok'}|ForEach-Object Version|Sort-Object -Unique)
    $best.Candidates=$candidates;$best.Conflict=($versions.Count -gt 1);$best.Selection=$(if($override){'BEYIN_CODEX_YOLU'}else{'newest-version'})
    $Context.ResolvedCodex=$best;return $best
}
function Set-KanalCodexRecord($Context,$Record,$Launch){
    foreach($key in @('Path','Version','Candidates')){$Record|Add-Member -NotePropertyName ('Codex'+$key) -NotePropertyValue $Launch[$key] -Force}
    $Record|Add-Member -NotePropertyName CodexLaunch -NotePropertyValue @{command=$Launch.command;args=@($Launch.args);Path=$Launch.Path;Version=$Launch.Version} -Force
    if($Launch.Conflict){
        $directory=Join-Path $Context.State $Record.Id;New-Item -ItemType Directory -Force $directory|Out-Null
        $message='Multiple Codex versions found; selected '+$Launch.Version+' via '+$Launch.Selection
        $entry=@{type='warning';message=$message;CodexCandidates=$Launch.Candidates}|ConvertTo-Json -Depth 8 -Compress
        [IO.File]::AppendAllText((Join-Path $directory 'events.jsonl'),($entry+"`n"),(New-Object Text.UTF8Encoding $false))
        $Record|Add-Member -NotePropertyName CodexWarning -NotePropertyValue $message -Force
    }
}
