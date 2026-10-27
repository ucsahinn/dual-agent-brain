function Get-KanalSchemaStatus($Context,[string]$Version=''){
    $pin=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'schema-lock.json'))|ConvertFrom-Json
    $launch=$null;if(-not $Version){$launch=Resolve-KanalCodex $Context;$Version=$launch.Version}
    $manifest=Join-Path $Context.State ('schemas/'+$Version+'/version.json')
    $generated=$false
    if(Test-Path -LiteralPath $manifest){try{
        $data=[IO.File]::ReadAllText($manifest)|ConvertFrom-Json;$root=[IO.Path]::GetFullPath((Split-Path $manifest -Parent))+[IO.Path]::DirectorySeparatorChar
        $generated=($data.version -eq $Version -and @($data.files).Count -gt 0)
        foreach($file in @($data.files)){$full=[IO.Path]::GetFullPath($file.path);if(-not $full.StartsWith($root,[StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $full -PathType Leaf) -or (Get-Item -LiteralPath $full).Attributes -band [IO.FileAttributes]::ReparsePoint -or (Get-FileHash -LiteralPath $full).Hash -ne $file.sha256){$generated=$false;break}}
    }catch{$generated=$false}}
    return @{Expected=$pin.version;Current=$Version;CodexPath=$(if($launch){$launch.Path}else{''});CodexCandidates=$(if($launch){$launch.Candidates}else{@()});CandidateConflict=$(if($launch){$launch.Conflict}else{$false});Changed=($Version -ne $pin.version);Generated=$generated;Notice='Schema checks the exact selected executable; generation is an operator gate outside the sandbox'}
}
function Export-KanalSchema($Context){
    $status=Get-KanalSchemaStatus $Context
    if($status.Changed){throw 'Codex version changed; review schema pin before generation'}
    $output=Join-Path $Context.State ('schemas/'+$status.Current)
    New-Item -ItemType Directory -Force $output|Out-Null
    $launch=Resolve-KanalCodex $Context
    & $launch.command @($launch.args) app-server generate-json-schema --out $output
    if($LASTEXITCODE -ne 0){throw 'Schema generation failed'}
    $files=@(Get-ChildItem -LiteralPath $output -Recurse -File -Filter '*.json'|Where-Object {$_.Name -ne 'version.json'})
    if(-not $files.Count){throw 'Schema generation produced no JSON files'}
    @{version=$status.Current;files=@($files|ForEach-Object {@{path=$_.FullName;sha256=(Get-FileHash -LiteralPath $_.FullName).Hash}})}|ConvertTo-Json -Depth 8|Set-Content -Encoding UTF8 (Join-Path $output 'version.json')
    return Get-KanalSchemaStatus $Context
}
