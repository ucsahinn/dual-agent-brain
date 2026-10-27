function Get-KanalModelProfile($Context){
    $path=$(if($Context.ConfigPath){$Context.ConfigPath}else{Join-Path $env:USERPROFILE '.codex/config.toml'})
    $values=@{Model='';ReviewModel=''}
    if(Test-Path -LiteralPath $path){
        if((Get-Item -LiteralPath $path).Length -gt 1048576){throw 'Model config exceeds bounded parser size'}
        foreach($line in [IO.File]::ReadAllLines($path)){
            if($line -match '^\s*\['){break}
            $m=[regex]::Match($line,'^\s*(model|review_model)\s*=\s*["'']([A-Za-z0-9._:-]+)["'']\s*(?:#.*)?$')
            if($m.Success){$key=$(if($m.Groups[1].Value -eq 'model'){'Model'}else{'ReviewModel'});$values[$key]=$m.Groups[2].Value}
        }
    }
    return $values
}
function New-KanalMcpProfile($Context,[string]$Role,[string]$Directory){
    New-Item -ItemType Directory -Force $Directory|Out-Null
    $config=$(if($Context.ConfigPath){$Context.ConfigPath}else{Join-Path $env:USERPROFILE '.codex/config.toml'})
    $names=@();if(Test-Path -LiteralPath $config){if((Get-Item -LiteralPath $config).Length -gt 1048576){throw 'MCP config exceeds bounded parser size'};foreach($line in [IO.File]::ReadAllLines($config)){
        $m=[regex]::Match($line,'^\s*\[mcp_servers\.(?:"([A-Za-z0-9_-]+)"|([A-Za-z0-9_-]+))(?:\.(?:env|http_headers|tools(?:\.[A-Za-z0-9_-]+)?))?\]\s*(?:#.*)?$')
        if($m.Success){$name=$m.Groups[1].Value+$m.Groups[2].Value;if($name -ne 'cua_repl'){$names+=$name}}
        elseif($line -match '^\s*\[\[?\s*mcp_servers(?:\.|\s*\])'){throw 'Unrecognized MCP table; diet cannot safely override this configuration'}
    }}
    $names=@($names|Select-Object -Unique);if($names.Count -gt 32){throw 'MCP diet exceeds the bounded 32-server override budget'}
    $allow=switch($Role){
        {$_ -in @('code-mapper','root-cause-debugger','code-reviewer')} {@('serena','serena_bridge','context7')}
        {$_ -in @('frontend-verifier','design-reviewer')} {@('playwright','chrome-devtools','context7')}
        'docs-researcher' {@('openaiDeveloperDocs','context7')}
        'mcp-integrator' {@('context7','openaiDeveloperDocs')}
        default {@()}
    }
    $enabled=@();$disabled=@();$lines=@();$arguments=@()
    foreach($name in $names){$on=($name -in $allow -and $name -ne 'node_repl');if($on){$enabled+=$name}else{$disabled+=$name};$value=$on.ToString().ToLowerInvariant();$lines+="[mcp_servers.$name]`nenabled = $value`n";$arguments+=@('-c',"mcp_servers.$name.enabled=$value")}
    $file=Join-Path $Directory 'mcp-profile.toml';[IO.File]::WriteAllText($file,($lines -join "`n"),(New-Object Text.UTF8Encoding $false))
    return @{Path=$file;Enabled=$enabled;Disabled=$disabled;Arguments=$arguments;Role=$Role}
}
function New-KanalCompiledPrompt($Context,[string]$RoleText,[string]$Brief){
    if(-not (Test-KanalBrief $Brief)){throw 'Seven nonempty brief fields required'}
    $parts=$RoleText -split '<!-- optional -->';$required=$parts[0]
    # Catalog governance is mandatory, separately accounted overhead. The 12K
    # default bounds the task and optional references; it never truncates policy.
    $max=$(if($Context.BriefBudget){[int]$Context.BriefBudget}else{12000+$required.Length+$(if($required){2}else{0})})
    $text=$required+$(if($required){"`n`n"}else{''})+$Brief
    if($text.Length -gt $max){throw 'Mandatory role and brief exceed the character budget'}
    for($i=1;$i -lt $parts.Count;$i++){if($text.Length+$parts[$i].Length+2 -le $max){$text+="`n`n"+$parts[$i]}}
    $injected=@();$candidates=@($Context.MemoryCandidates|Where-Object {$_ -and $_.score -ge 0.5}|Sort-Object @{Expression={if($_.misses -ge 3){$_.score*0.5}else{$_.score}};Descending=$true}|Select-Object -First 5)
    foreach($memory in $candidates){$block="`n`n### Approved reference: $($memory.path)`n$($memory.text)";if($text.Length+$block.Length -le $max){$text+=$block;$injected+=$memory.path}}
    return @{Text=(Protect-KanalText $Context $text);Characters=$text.Length;MandatoryRoleCharacters=$required.Length;CharacterBudget=$max;EstimatedTokens=
        [int][math]::Ceiling($text.Length/4);Injected=$injected}
}
function ConvertFrom-KanalHandoffJson([string]$Text){
    if(-not $Text.TrimStart().StartsWith('{')){return $Text}
    try{$data=$Text|ConvertFrom-Json}catch{throw 'Invalid structured handoff JSON'}
    $names=@('outcome','evidence','changed_scope','risks','open_questions','next_verification');$labels=@('Outcome','Evidence','Changed scope','Risks','Open questions','Next verification')
    if(@($data.PSObject.Properties).Count -ne 6){throw 'Invalid structured handoff fields'}
    $lines=@();for($i=0;$i -lt 6;$i++){$v=$data.($names[$i]);if($v -isnot [string] -or -not $v.Trim()){throw 'Invalid structured handoff field'};$lines+=$labels[$i]+': '+$v};return $lines -join "`n"
}
