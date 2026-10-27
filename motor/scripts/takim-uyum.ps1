# Read-only UI compatibility. The AgentChef engine remains the approval authority.
function Get-TakimUyumSurum {
    $roots=@($env:BEYIN_AGENTCHEF_KOK,$env:AGENTCHEF_ROOT)
    if(Get-Command Get-BeyinAyar -ErrorAction SilentlyContinue){$roots=@((Get-BeyinAyar 'BEYIN_AGENTCHEF_KOK' ''))+$roots}
    $cache=Join-Path $env:USERPROFILE '.beyin/agentchef-kok.txt'
    if(Test-Path -LiteralPath $cache){$roots+=([IO.File]::ReadAllText($cache).Trim())}
    foreach($root in $roots){if($root){try{return [string]((Get-Content -LiteralPath (Join-Path $root 'package.json') -Raw -Encoding UTF8 -ErrorAction Stop|ConvertFrom-Json).version)}catch{}}}
    return ''
}
function Test-Takim190([string]$Surum){
    try{return ($Surum -notmatch '-' -and [version](($Surum -split '\+')[0]) -ge [version]'1.9.0')}catch{return $false}
}
function Get-TakimCleanupKomut([string]$Id,[string]$Surum){
    return "beyin takim cleanup $Id"+$(if(Test-Takim190 $Surum){' --approved'}else{''})
}
function Get-TakimLeadReviewAdim($Kosu,[string]$Surum){
    if(-not (Test-Takim190 $Surum) -or $Kosu.status -notin @('integrated','verified') -or -not $Kosu.integration.ok){return ''}
    if(-not @($Kosu.workers|Where-Object {$_.sandbox -ne 'read-only'}).Count){return ''}
    $r=$Kosu.leadReview
    $valid=$r -and $r.engine -eq 'claude' -and $r.reviewer -and $r.verdict -eq 'pass' -and $Kosu.integration.commit -and $r.integrationCommit -ceq $Kosu.integration.commit -and @($r.evidence).Count -gt 0 -and -not @($r.evidence|Where-Object {$_ -isnot [string] -or -not $_.Trim()}).Count
    if($valid){return ''}
    return "beyin takim lead-review --run $($Kosu.runId)"
}
