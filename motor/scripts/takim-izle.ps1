param(
    [string]$Vault = '',
    [Parameter(Mandatory = $true)][string]$Run,
    [string]$Kart = '',
    [string]$Model = '',
    [switch]$Tek,          # bir kare ciz ve cik (test / ekran goruntusu); bildirim, zil, pencere basligi yok
    [int]$Genislik = 0,
    [int]$Yukseklik = 0
)
# takim-izle.ps1 v15 - Takim kosusu isci paneli + kosu panosu (Beyin). v13: stat kartlari (widget), asama ilerleme cubugu, Turkce rol/pano adlari, jeton ozeti, dar ekranda kartlar alt alta. v12: Catppuccin Mocha paleti, cerceveye gomulu bolum basliklari, durum = glif + sozcuk, titreme onleme. v9: genislik-duyarli (CJK), Turkce is adlari, yabanci dildeki isci notlari gizli. Motorun (AgentChef team-run.mjs) kosu kaydini ve iscinin
# events.jsonl'ini YALNIZ OKUR; isciye dokunmaz, dosya yaratmaz. Sekmeyi kapatmak isciyi durdurmaz; 'q' cikar.
# Kaynak: <state>\team-runs\<runId>.json (kosu kaydi), <state>\team-runs\<runId>\<TASK>\events.jsonl, stderr.log,
# <state>\team-runs\<runId>\reports\<TASK>-<rol>.md (handoff). Acilis: beyin takim start (otomatik) ya da beyin takim izle <runId> [TASK].
if (-not $Vault) { $Vault = $(if ($env:BEYIN_VAULT) { $env:BEYIN_VAULT } else { Split-Path (Split-Path $PSScriptRoot -Parent) -Parent }) }
. (Join-Path $Vault 'motor\hooks\lib.ps1')
$p = Get-BeyinPaths -Vault $Vault
$Board = $p.Board
$runRec = Join-Path $p.TeamRuns "$Run.json"
$Worktree = ''
# PAYLASIMLI OKUMA (2026-10-14): Get-Content/ReadAllText dosyayi FILE_SHARE_DELETE olmadan acar; motor o an kosu kaydini
# atomik yeniden adlandirirsa Windows EPERM verir ve gozetmen tick'i duser (R20261014-753a'da uc isciyi 'failed' yapti).
# Panel butun dosyalari ReadWrite+Delete paylasimiyla okur: motorun yazmasini asla engellemez.
function Read-Shared([string]$Path) {
    $fs = $null
    try {
        $fs = New-Object IO.FileStream($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
        $sr = New-Object IO.StreamReader($fs, [Text.Encoding]::UTF8, $true)
        return $sr.ReadToEnd()
    } finally { if ($fs) { $fs.Dispose() } }
}
try { $rr0 = Read-Shared $runRec | ConvertFrom-Json; $wk0 = @($rr0.workers | Where-Object { [string]$_.taskId -eq $Kart })[0]; if ($wk0 -and $wk0.worktree) { $Worktree = [string]$wk0.worktree }; if (-not $Model -and $rr0.model) { $Model = [string]$rr0.model } } catch { }

try { chcp 65001 | Out-Null } catch { }
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$OutputEncoding = [Text.Encoding]::UTF8
$env:GIT_OPTIONAL_LOCKS = '0'
try { [Console]::CursorVisible = $false } catch { }

# ---------- palet: ortak cizim katmani (beyin-ciz.ps1; Aurora rolleri, genislik olcusu, kartlar, kare yazici) ----------
$cizYol = Join-Path $PSScriptRoot 'beyin-ciz.ps1'
if (-not (Test-Path -LiteralPath $cizYol)) { Write-Host 'takim-izle: beyin-ciz.ps1 bulunamadi (motor eksik kurulmus) · beyin guncelle'; exit 2 }
. $cizYol
$ITAL = "$ESC[3m"
$cCmd = $cText; $cMsg = $cText; $cFile = $cText; $cThink = $cFaint; $cGutCmd = $cFrame2
$pOku = $cAccent; $pDuz = $cMauve; $pTest = $cWarn; $pGit = $cOk; $pTakim = $cPeach
$bgPanel = ''; $bgBody = CizBG $CizRgb.Zemin; $bgFail = $bgWait

# ---------- dosyalar ----------
$dir = Join-Path (Join-Path $p.TeamRuns $Run) $Kart
$events = Join-Path $dir 'events.jsonl'
$errLog = Join-Path $dir 'stderr.log'
$finalMd = ''   # rapor yolu kosu kaydindan (reportId) cozulur

# onceki kosularin bitmis iscileri (referans sure)
$refMins = $null
try {
    $durs = @()
    foreach ($f in (Get-ChildItem -LiteralPath $p.TeamRuns -Filter '*.json' -File -ErrorAction SilentlyContinue)) {
        if ($f.BaseName -eq $Run) { continue }
        $rr = Read-Shared $f.FullName | ConvertFrom-Json
        foreach ($w in @($rr.workers)) { if ($w.startedAt -and $w.finishedAt) { $durs += ([DateTime]$w.finishedAt - [DateTime]$w.startedAt).TotalMinutes } }
    }
    if ($durs.Count) { $refMins = [int](($durs | Measure-Object -Average).Average) }
} catch { }

# ---------- durum ----------
function NewState {
    return @{
        title = ''; lease = $null; leaseFrom = $null; thread = ''; turns = 0; turnDone = $false
        cmdOk = 0; cmdFail = 0; msgs = 0; files = 0; reasoning = 0; errors = 0
        inTok = 0L; cachedTok = 0L; outTok = 0L
        phase = @{ oku = 0; duzenle = 0; test = 0; git = 0; takim = 0 }
        phaseMin = @{}
        checks = [ordered]@{}; checkSeq = 0
        slow = $null
        current = $null; currentStart = $null; started = @{}
        lastTest = ''; lastFail = $null; lastFiles = New-Object System.Collections.Generic.List[string]
        start = $null; finish = $null; rc = $null; rcLost = $false; lastEvent = $null; lastErrLine = ''
        commit = ''; commitFresh = $false; verdict = ''; outcome = ''; workerStatus = ''; runStatus = ''; role = ''; failureTxt = ''; recPid = 0; activity = @{}; lastErrAt = $null
        proc = $null; procChecked = $false; freeMb = 0; boardStatus = ''
        sideAt = (Get-Date).AddMinutes(-1); boardAt = (Get-Date).AddMinutes(-1); errPos = 0L; prevBadge = ''
    }
}
$script:hideThink = $true; $script:onlyImportant = $true; $script:freezeAt = -1; $script:showTok = $false   # klavye: t / e / boşluk
$st = NewState
$rows = New-Object System.Collections.Generic.List[object]   # ham kayitlar; render aninda bicimlenir
$pos = 0L; $carry = New-Object byte[] 0; $replay = $true; $replayDividerAdded = $false
$spin = @('⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏')
$spark = @('▁', '▂', '▃', '▄', '▅', '▆', '▇', '█')
$rxCtl1 = [regex]::new("$ESC\[[0-9;?]*[ -/]*[@-~]")
$rxCtl2 = [regex]::new("$ESC\][^$([char]7)]*$([char]7)|[\x00-\x08\x0B-\x1F\x7F]")

# ---------- yardimcilar ----------
function Clean([string]$s) { if ($null -eq $s) { return '' }; $s = $rxCtl1.Replace($s, ''); $s = $rxCtl2.Replace($s, ''); return (Get-CizGuvenliMetin $s.Replace("`t", '  ')) }   # BMP emoji satiri tasirmasin
function Fmt([long]$n) { if ($n -ge 1000000) { return ('{0:N1}M' -f ($n / 1000000.0)) }; if ($n -ge 1000) { return ('{0:N1}K' -f ($n / 1000.0)) }; return "$n" }
function Ago($t) { if (-not $t) { return '—' }; $s = [int]((Get-Date) - $t).TotalSeconds; if ($s -lt 0) { $s = 0 }; if ($s -lt 60) { return "$s sn" }; if ($s -lt 3600) { return "$([int][Math]::Floor($s/60)) dk $($s%60) sn" }; return "$([int][Math]::Floor($s/3600)) sa $([int][Math]::Floor(($s%3600)/60)) dk" }
function Span($a, $b) { if (-not $a) { return '—' }; if (-not $b) { $b = Get-Date }; $d = $b - $a; if ($d.TotalDays -ge 1) { return ('{0}g {1:hh\:mm\:ss}' -f [int]$d.TotalDays, $d) }; return ('{0:hh\:mm\:ss}' -f $d) }
function DurS([double]$sec) { if ($sec -lt 59.95) { return ('{0:0.0} sn' -f $sec) }; $t = [int][Math]::Round($sec); if ($t -lt 3600) { return "$([int][Math]::Floor($t/60)) dk $($t%60) sn" }; return "$([int][Math]::Floor($t/3600)) sa $([int][Math]::Floor(($t%3600)/60)) dk" }
function Wrap([string]$s, [int]$w) {
    # genislige duyarli sarma (eskiden .Length: CJK/emoji iceren satir cerceveden tasiyordu); sozcuk sinirindan, uzun sozcuk bolunur
    if ($w -lt 8) { $w = 8 }
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($para in (($s -replace "`r", '') -split "`n")) {
        $p = $para.Trim(); if (-not $p) { continue }
        $cur = ''
        foreach ($soz in ($p -split ' ')) {
            if (-not $soz) { continue }
            while ((VisLen $soz) -gt $w) { if ($cur) { $out.Add($cur); $cur = '' }; $par = Cut $soz ($w + 1); $par = $par.Substring(0, $par.Length - "…$RS".Length); if (-not $par) { break }; $out.Add($par); $soz = $soz.Substring($par.Length) }
            if (-not $cur) { $cur = $soz } elseif ((VisLen "$cur $soz") -le $w) { $cur = "$cur $soz" } else { $out.Add($cur); $cur = $soz }
        }
        if ($cur) { $out.Add($cur) }
    }
    return $out
}
function CleanCmd([string]$c) {
    $c = $c -replace '^"?[A-Za-z]:\\\\?WINDOWS\\\\?System32\\\\?WindowsPowerShell\\\\?v1\.0\\\\?powershell\.exe"?\s+-Command\s+', ''
    $c = $c -replace '^"?[A-Za-z]:\\WINDOWS\\System32\\WindowsPowerShell\\v1\.0\\powershell\.exe"?\s+-Command\s+', ''
    $c = $c -replace '\\\\', '\' -replace '\\"', '"'
    $c = $c -replace '''"''', '''' -replace '^[''"]', '' -replace '[''"]$', ''
    return ($c -replace '\s+', ' ').Trim()
}
function Rel([string]$p) { $wt = [string]$script:Worktree; if ($p -and $wt -and $p.Replace('/', '\').StartsWith($wt.Replace('/', '\'), 'OrdinalIgnoreCase')) { return $p.Replace('/', '\').Substring($wt.Length).TrimStart('\').Replace('\', '/') } return $p }
function Phase([string]$c) {
    if ($c -match '(^|[;&|]\s*)(node (\S+[\\/])?team-run\.mjs|codex(\.cmd)? exec|beyin(\.ps1)? takim|powershell[^;|&]*takim\.ps1)') { return 'takim' }
    if ($c -match '(^|[;&|]\s*)(node --test|npm(\.cmd)? run|npm(\.cmd)? test|node scripts/validate|gitleaks)') { return 'test' }
    if ($c -match '(^|[;&|]\s*)git (add|commit|checkout|switch|worktree|merge|stash|restore)') { return 'git' }
    if ($c -match '(^|[;&|]\s*)(Set-Content|Out-File|Add-Content|New-Item|Copy-Item|Remove-Item|Move-Item|apply_patch)') { return 'duzenle' }
    return 'oku'
}
function CheckKey([string]$c) {
    # dogrulama/kontrol komutlarina kisa, kararli bir anahtar; kontrol degilse ''
    if ($c -match 'node --test ((?:\S+\s*)+)') {
        $names = @(); foreach ($f in ($Matches[1] -split '\s+')) { if ($f -match '([^\\/]+?)\.test\.mjs') { $names += $Matches[1] } }
        if ($names.Count) { return 'test ' + (($names | Select-Object -First 3) -join ',') + $(if ($names.Count -gt 3) { "+$($names.Count-3)" } else { '' }) }
        return 'test'
    }
    if ($c -match 'node scripts[\\/](validate-[\w-]+)\.mjs') { return $Matches[1] }
    if ($c -match 'npm(?:\.cmd)? run ([\w:-]+)') { return "npm run $($Matches[1])" }
    if ($c -match 'npm(?:\.cmd)? test') { return 'npm test' }
    if ($c -match 'gitleaks') { return 'gitleaks' }
    if ($c -match '(^|[;&|]\s*)git commit') { return 'git commit' }
    if ($c -match '(?:^|[;&|]\s*)(?:&\s*)?node\s+[''"]?\S*?team-run\.mjs[''"]?\s+(plan|start|status|supervise|watch|abort|collect|integrate|verify|merge|pause|resume|cleanup|doctor)\b') { return "team-run $($Matches[1])" }
    if ($c -match 'render-target-artifacts') { return 'render:targets' }
    return ''
}
function Bump([datetime]$t, [string]$ph) {
    $key = $t.ToString('HHmm')
    if ($st.activity.ContainsKey($key)) { $st.activity[$key]++ } else { $st.activity[$key] = 1 }
    if ($ph) {
        if (-not $st.phaseMin.ContainsKey($key)) { $st.phaseMin[$key] = @{ oku = 0; duzenle = 0; test = 0; git = 0; takim = 0 } }
        $st.phaseMin[$key][$ph]++
    }
}
function AddRow([string]$kind, [hashtable]$h) { $h.kind = $kind; $h.ts = $(if ($script:replay) { '' } else { (Get-Date).ToString('HH:mm:ss') }); $rows.Add($h) }

function Handle([string]$line) {
    try { $ev = $line | ConvertFrom-Json } catch { return }
    if (-not $ev -or -not $ev.type) { return }
    $now = Get-Date; $st.lastEvent = $now
    if (-not $script:replay) { Bump $now '' }
    switch ($ev.type) {
        'thread.started' { $st.thread = [string]$ev.thread_id; AddRow 'info' @{ text = "◆ oturum $($st.thread)" } }
        'turn.started' { $st.turns++ }
        'turn.completed' {
            $u = $ev.usage
            if ($u) { $st.inTok += [long]$u.input_tokens; $st.cachedTok += [long]$u.cached_input_tokens; $st.outTok += [long]$u.output_tokens }
            $st.turnDone = $true
            AddRow 'ok' @{ text = "✓ tur tamamlandı   giriş $(Fmt $st.inTok) · önbellek $(Fmt $st.cachedTok) · çıkış $(Fmt $st.outTok)" }
        }
        'turn.failed' { $st.errors++; AddRow 'err' @{ text = "✕ tur başarısız: " + (Clean (($ev | ConvertTo-Json -Compress -Depth 4))) } }
        'error' { $st.errors++; AddRow 'err' @{ text = "✕ hata: " + (Clean ([string]$ev.message)) } }
        'item.started' {
            $it = $ev.item
            if ($it -and $it.type -eq 'command_execution') { $st.current = Clean (CleanCmd ([string]$it.command)); $st.currentStart = $now; $st.started[[string]$it.id] = $now }
        }
        'item.completed' {
            $it = $ev.item
            if (-not $it) { return }
            switch ($it.type) {
                'command_execution' {
                    $code = $it.exit_code
                    $ok = ($null -eq $code -or $code -eq 0)
                    if ($ok) { $st.cmdOk++ } else { $st.cmdFail++ }
                    $c = Clean (CleanCmd ([string]$it.command))
                    $ph = Phase $c; $st.phase[$ph]++
                    if (-not $script:replay) { Bump $now $ph }
                    $dur = ''; $durSec = -1.0; $id = [string]$it.id
                    if ($st.started.ContainsKey($id)) { if (-not $script:replay) { $durSec = ($now - $st.started[$id]).TotalSeconds; $dur = $(if ($durSec -ge 1) { DurS $durSec } else { '' }) }; $st.started.Remove($id) }
                    if ($durSec -ge 0 -and (-not $st.slow -or $durSec -gt $st.slow.sec)) { $st.slow = @{ cmd = $c; sec = $durSec } }
                    if ($st.current -eq $c) { $st.current = $null }
                    $o = Clean ([string]$it.aggregated_output)
                    $detail = ''
                    if ($o -match '\u2139 pass (\d+)[\s\S]*?\u2139 fail (\d+)') { $st.lastTest = "$($Matches[1]) pass / $($Matches[2]) fail"; $detail = "$($Matches[1])/$([int]$Matches[1]+[int]$Matches[2])"; if ($Matches[2] -eq '0') { $st.lastFail = $null } }
                    elseif ($o -match '(\d+) passed, (\d+) failed') { $st.lastTest = "$($Matches[1]) pass / $($Matches[2]) fail"; $detail = "$($Matches[1])/$([int]$Matches[1]+[int]$Matches[2])"; if ($Matches[2] -eq '0') { $st.lastFail = $null } }
                    elseif ($o -match 'no leaks found') { $detail = 'temiz' }
                    elseif ($o -match 'leaks found: (\d+)') { $detail = "$($Matches[1]) sızıntı" }
                    $sandbox = (-not $ok -and $o -match 'spawn EPERM')   # Codex Windows sandbox alt sureci engelledi: kodun hatasi degil
                    $ck = CheckKey $c
                    if ($ck) {
                        $st.checkSeq++
                        if ($st.checks.Contains($ck)) { $st.checks[$ck].n++ } else { $st.checks[$ck] = @{ n = 1 } }
                        $st.checks[$ck].ok = $ok; $st.checks[$ck].dur = $dur; $st.checks[$ck].detail = $detail; $st.checks[$ck].seq = $st.checkSeq; $st.checks[$ck].sandbox = $sandbox
                    }
                    if (-not $ok -and -not $sandbox -and ($ck -or $ph -ne 'oku')) { $st.lastFail = @{ cmd = $c; code = $code; at = $now.ToString('HH:mm:ss'); n = $st.cmdFail; key = $ck }; if (-not $script:replay) { try { [Console]::Write([char]7) } catch { } } }   # kesif komutlarinin (okuma) hatasi sabitlenmez
                    elseif ($st.lastFail -and (($st.lastFail.cmd -eq $c) -or ($ck -and $st.lastFail.key -eq $ck))) { $st.lastFail = $null }   # ayni komut/kontrol sonra gecti: cozuldu
                    AddRow 'cmd' @{ ok = $ok; code = $code; dur = $dur; cmd = $c; ph = $ph; ck = $ck; detail = $detail; sandbox = $sandbox; out = $(if ($ok) { '' } else { $o.Substring(0, [Math]::Min(500, $o.Length)) }) }
                }
                'agent_message' { $st.msgs++; AddRow 'msg' @{ text = Clean ([string]$it.text) } }
                'reasoning' {
                    $st.reasoning++
                    $raw = [string]$it.text
                    if ($raw -match '^\s*\*\*(.+?)\*\*') { $t = $Matches[1] } else { $t = $raw }
                    $t = (Clean ($t -replace '\*\*', '') -replace '\s+', ' ').Trim()
                    if ($t) { AddRow 'think' @{ text = $t } }
                }
                'file_change' {
                    foreach ($ch in @($it.changes | Where-Object { $_ })) {
                        $st.files++; $st.phase.duzenle++
                        if (-not $script:replay) { Bump $now 'duzenle' }
                        $p = Clean (Rel ([string]$ch.path)); $k = [string]$ch.kind
                        AddRow 'file' @{ path = $p; fkind = $k }
                        if ($st.lastFiles -contains $p) { [void]$st.lastFiles.Remove($p) }
                        $st.lastFiles.Add($p)
                    }
                }
                'mcp_tool_call' { AddRow 'info' @{ text = "▸ mcp $(Clean ([string]$it.server))/$(Clean ([string]$it.tool))" } }
                'web_search' { AddRow 'info' @{ text = "⌕ web: $(Clean ([string]$it.query))" } }
                default { }
            }
        }
        default { }
    }
}

function ResetAll { $script:st = NewState; $rows.Clear(); $script:pos = 0L; $script:carry = New-Object byte[] 0; $script:replay = $true; $script:replayDividerAdded = $false }

function ReadNew {
    if (-not (Test-Path -LiteralPath $events)) { return }
    try {
        $fs = [IO.File]::Open($events, 'Open', 'Read', 'ReadWrite, Delete')
        try {
            if ($fs.Length -lt $pos) { ResetAll }
            $fs.Seek($pos, 'Begin') | Out-Null
            $n = [Math]::Min($fs.Length - $pos, 1048576)
            if ($n -le 0) { if ($script:replay) { $script:replay = $false }; return }
            $bytes = New-Object byte[] $n
            $read = $fs.Read($bytes, 0, $n)
            $script:pos += $read
        } finally { $fs.Close() }
        if ($read -lt $n) { $bytes = $bytes[0..($read - 1)] }
        $all = New-Object byte[] ($carry.Length + $bytes.Length)
        [Array]::Copy($carry, 0, $all, 0, $carry.Length); [Array]::Copy($bytes, 0, $all, $carry.Length, $bytes.Length)
        $lastNl = [Array]::LastIndexOf($all, [byte]10)
        if ($lastNl -lt 0) { $script:carry = $all; return }
        $script:carry = if ($lastNl + 1 -lt $all.Length) { $all[($lastNl + 1)..($all.Length - 1)] } else { New-Object byte[] 0 }
        $txt = [Text.Encoding]::UTF8.GetString($all, 0, $lastNl + 1)
        $budget = [Diagnostics.Stopwatch]::StartNew()
        foreach ($raw in ($txt -split "`n")) { $l = $raw.Trim(); if ($l) { Handle $l }; if ($budget.ElapsedMilliseconds -gt 400 -and -not $script:replay) { break } }
        if ($script:replay -and $pos -ge $fs.Length) { $script:replay = $false }
    } catch { }
}

function RefreshSide {
    if (((Get-Date) - $st.sideAt).TotalSeconds -lt 3) { return }
    $st.sideAt = Get-Date
    # kosu kaydi: isci alanlari (startedAt/finishedAt/exitCode/status/verdict/pid/worktree/reportId)
    try {
        $rr = Read-Shared $runRec | ConvertFrom-Json
        $wk = @($rr.workers | Where-Object { [string]$_.taskId -eq $Kart })[0]
        if ($wk) {
            if (-not $Model -and $rr.model) { $script:Model = [string]$rr.model }
            if ($wk.worktree) { $script:Worktree = [string]$wk.worktree }
            $newStart = $(if ($wk.startedAt) { ([DateTime]$wk.startedAt).ToLocalTime() } else { $null })
            if ($newStart -and $st.start -and $newStart -gt $st.start) { ResetAll }
            $st.start = $newStart
            $st.finish = $(if ($wk.finishedAt) { ([DateTime]$wk.finishedAt).ToLocalTime() } else { $null })
            $st.rc = $(if ($null -ne $wk.exitCode) { [int]$wk.exitCode } else { $null })
            $st.workerStatus = [string]$wk.status; $st.runStatus = [string]$rr.status; $st.role = [string]$wk.role
            if ($wk.verdict) { $st.verdict = [string]$wk.verdict }
            if ($wk.failure -and -not $st.failureTxt) { $st.failureTxt = Clean ([string]$wk.failure) }
            if ($wk.pid -and -not $st.proc) { $st.recPid = [int]$wk.pid }
            if ($wk.reportId) { $script:finalMd = Join-Path (Join-Path (Join-Path $p.TeamRuns $Run) 'reports') ([string]$wk.reportId) }
        }
    } catch { }
    if (Test-Path -LiteralPath $errLog) {
        try {
            $fs = [IO.File]::Open($errLog, 'Open', 'Read', 'ReadWrite, Delete')
            try {
                if ($fs.Length -lt $st.errPos) { $st.errPos = 0L; $st.errors = 0 }
                if ($fs.Length -gt $st.errPos) {
                    $fs.Seek($st.errPos, 'Begin') | Out-Null; $b = New-Object byte[] ($fs.Length - $st.errPos); $r = $fs.Read($b, 0, $b.Length); $st.errPos += $r
                    $t = [Text.Encoding]::UTF8.GetString($b, 0, $r)
                    $errLines = @(($t -split "`n") | Where-Object { $_ -cmatch 'ERROR' -and $_ -notmatch 'memories_write' })
                    $st.errors += $errLines.Count
                    if ($errLines.Count) { $st.lastErrAt = Get-Date; $st.lastErrLine = Clean (($errLines[-1] -replace '^\S+Z\s+ERROR\s+\S+:\s*', '') -replace '\s+', ' ') }
                }
            } finally { $fs.Close() }
        } catch { }
    }
    if (-not $st.outcome -and $finalMd -and (Test-Path -LiteralPath $finalMd)) {
        try { $f = Read-Shared $finalMd; if ($f -match '(?s)##\s*Outcome\s*\r?\n(.*?)(?:\r?\n##\s|\z)') { $st.outcome = ((Clean $Matches[1]) -replace '\*\*', '' -replace '\s+', ' ').Trim() } } catch { }
    }
    if (-not $st.outcome -and $st.rc -ne $null -and $st.failureTxt) { $st.outcome = $st.failureTxt }
    if (((Get-Date) - $st.boardAt).TotalSeconds -gt 20) {
        $st.boardAt = Get-Date
        try {
            $raw = $(if ($Worktree -and (Test-Path -LiteralPath $Worktree)) { (& git -C $Worktree log -1 --format='%ct|%h %s' 2>$null | Out-String).Trim() } else { '' })
            if ($raw -match '^(\d+)\|(.+)$') { $st.commit = $Matches[2]; $ct = [DateTimeOffset]::FromUnixTimeSeconds([long]$Matches[1]).LocalDateTime; $st.commitFresh = ($st.start -and $ct -gt $st.start -and (-not $st.finish -or $ct -lt $st.finish.AddMinutes(3))) }
        } catch { }
        try {
            $b = Read-Shared $Board | ConvertFrom-Json
            $t = @($b.tasks | Where-Object { $_.id -eq $Kart })[0]
            if (-not $t) { $st.title = 'pano dışı koşu'; $st.boardStatus = '' }
            if ($t) {
                $st.title = Clean ([string]$t.title); $st.boardStatus = [string]$t.status
                if ($t.leaseUntil) {
                    $nl = ([DateTime]$t.leaseUntil).ToLocalTime()
                    if (-not $st.lease -or $nl -ne $st.lease) { $st.leaseFrom = Get-Date }
                    $st.lease = $nl
                } else { $st.lease = $null }
            }
        } catch { }
        # isci sureci canli mi (yalniz okur): bu worktree'yi -C ile alan codex.exe; sarmalayici olse de surec yasar
        try {
            $pick = $null
            if ($st.recPid) { $pick = Get-CimInstance Win32_Process -Filter "ProcessId=$($st.recPid)" -ErrorAction SilentlyContinue }
            $st.proc = if ($pick) { @{ pid = $pick.ProcessId; mb = [int]($pick.WorkingSetSize / 1MB); since = $pick.CreationDate } } else { $null }
            $st.procChecked = $true
        } catch { }
        try { $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue; if ($os) { $st.freeMb = [int]($os.FreePhysicalMemory / 1024) } } catch { }
    }
}



# ======================= v8 GORUNUM =======================
# Tasarim incelemesi (design_reviewer, 2026-10-13) sonrasi: akis tek satir ve soluk, bant uc sayi, gercek "su an",
# yalniz cozulmemis hata, tek vurgu rengi (camgobegi), yesil yalniz ✓/rozet, sari yalniz uyari, kirmizi yalniz cozulmemis hata.
# Sutunlar: bolum etiketi x=2, icerik x=4, ŞU AN/son soz degeri x=12.

function ShortCmd([string]$c, [int]$w) {
    $s = $c -replace 'npm\.cmd', 'npm' -replace 'npx\.cmd', 'npx'
    if ($s -match '^(.*?node --test)\s+((?:\S+\.mjs\s*)+)(.*)$') { $n = @($Matches[2] -split '\s+' | Where-Object { $_ }).Count; $s = "$($Matches[1]) ($n test dosyası)$($Matches[3])" }
    $parts = @($s -split '\s*(?:&&|;|\|\|)\s*' | Where-Object { $_ })
    if ($parts.Count -gt 1) { $s = $parts[0] }
    return (Cut $s $w)
}
function Num([double]$v, [int]$dec) { return $v.ToString("N$dec", [Globalization.CultureInfo]::GetCultureInfo('tr-TR')) }
function Sure($a, $b) {
    if (-not $a) { return '—' }; if (-not $b) { $b = Get-Date }
    $s = [int]($b - $a).TotalSeconds; if ($s -lt 0) { $s = 0 }
    if ($s -lt 60) { return "$s sn" }; if ($s -lt 3600) { return "$([int][Math]::Floor($s/60)) dk $($s%60) sn" }
    return "$([int][Math]::Floor($s/3600)) sa $([int][Math]::Floor(($s%3600)/60)) dk"
}
function Sec([string]$name) { return "$cAccent$BOLD$name$RS" }
function Yabanci([string]$t) {
    # Latin disi harf cogunluktaysa (Kiril, CJK, Arapca...) isci notu baska dildedir
    if (-not $t) { return $false }
    $lat = 0; $oth = 0
    foreach ($ch in $t.ToCharArray()) { if ([char]::IsLetter($ch)) { if ([int]$ch -lt 0x0250 -or ([int]$ch -ge 0x1E00 -and [int]$ch -le 0x1EFF)) { $lat++ } else { $oth++ } } }
    return ($oth -ge 4)   # 4+ Latin disi harf: Kiril/CJK karisik metin de yabancidir
}
function IsAdi([string]$c, [string]$ph, [string]$ck, [string]$detail) {
    # ham komutu operatorun anlayacagi Turkce is adina cevirir
    if ($ck -like 'test *') { return "Test: $($ck.Substring(5).Replace(',', ', '))" + $(if ($detail) { "  $detail" } else { '' }) }
    if ($ck -eq 'test') { return 'Testler koştu' + $(if ($detail) { "  $detail" } else { '' }) }
    if ($ck -like 'npm run *') { $n = $ck.Substring(8); if ($n -eq 'check') { return 'Tam kontrol (npm run check)' }; return "npm run $n" }
    if ($ck -eq 'npm test') { return 'Testler koştu (npm test)' }
    if ($ck -like 'validate-*') { return "Denetim: $ck" + $(if ($detail) { "  $detail" } else { '' }) }
    if ($ck -eq 'gitleaks') { return 'Sır taraması' + $(if ($detail) { "  $detail" } else { '' }) }
    if ($ck -eq 'git commit') { return 'Commit' }
    if ($ck -like 'team-run *') { return "Takım motoru: $($ck.Substring(9))" }
    if ($ck -eq 'render:targets') { return 'Üretilen dosyalar güncel' }
    $hedef = ''; if ($c -match '([\w./\\-]+\.(mjs|cjs|json|ts|js|md|ps1|toml|yaml|yml|txt))\b') { $hedef = ($Matches[1] -replace '\\', '/') }
    if ($c -match '^\s*\$\w+\s*=' -or $c -match '^(rg|grep|Select-String|Get-Content|cat|type|ls|dir|Get-ChildItem|find|sed|head|tail)\b') { return 'Okuma' + $(if ($hedef) { ": $(CutLeft $hedef 40)" } else { '' }) }
    if ($ph -eq 'duzenle' -and ($c -match '(Set-Content|Out-File|Add-Content|New-Item|Copy-Item|Move-Item|Remove-Item|apply_patch|\[IO\.File\]::Write)')) { return 'Düzenleme' + $(if ($hedef) { ": $(CutLeft $hedef 40)" } else { '' }) }
    if ($ph -eq 'git') { if ($c -match '(^|[;&|]\s*)git (\w+)') { return "git $($Matches[2])" }; return 'git' }
    if ($c -match '^(rg|grep|Select-String|Get-Content|cat|type|ls|dir|Get-ChildItem|find|sed|head|tail)\b') { return 'Okuma' }
    if ($c -match '^node (\S+\.mjs)') { return "node $($Matches[1])" }
    return 'Komut'
}
function HLine([int]$w, [string]$label, [string]$left, [string]$right) {
    $lab = if ($label) { " $label$cFrame " } else { '' }
    $fill = $w - 2 - (VisLen $lab) - 1; if ($fill -lt 0) { $fill = 0 }
    return "$cFrame$left─$lab$('─' * $fill)$right$RS"
}
function Row([string]$content, [int]$w) { return "$cFrame│$RS$bgPanel " + (Pad $content ($w - 4)) + " $RS$cFrame│$RS" }
function Blank([int]$w) { return (Row '' $w) }
function Cols([string]$a, [string]$b, [int]$w, [int]$leftW) { return (Pad $a $leftW) + "$cFrame│ $RS" + (Cut $b ($w - 4 - $leftW - 2)) }

function RolTr([string]$r) { switch ($r) { 'root_cause_debugger' { 'hata ayıklayıcı' } 'docs_author' { 'belge yazarı' } 'qa_lead' { 'QA lideri' } 'spec_author' { 'spek yazarı' } 'test_verifier' { 'doğrulayıcı' } 'code_mapper' { 'kod haritacısı' } 'docs_researcher' { 'belge araştırmacısı' } 'context_architect' { 'bağlam mimarı' } 'prompt_architect' { 'prompt mimarı' } 'mcp_integrator' { 'MCP entegratörü' } 'product_strategist' { 'ürün stratejisti' } 'engineering_planner' { 'mühendislik planlayıcı' } 'design_reviewer' { 'tasarım incelemeci' } 'devex_auditor' { 'DevEx denetçisi' } 'performance_auditor' { 'performans denetçisi' } 'security_auditor' { 'güvenlik denetçisi' } 'code_reviewer' { 'kod incelemeci' } 'release_verifier' { 'sürüm doğrulayıcı' } 'google_seo_auditor' { 'SEO denetçisi' } 'frontend_verifier' { 'arayüz doğrulayıcı' } 'codex_doctor' { 'Codex doktoru' } '' { '' } default { $r -replace '_', ' ' } } }
function PanoTr([string]$d) { switch ($d) { 'todo' { 'bekliyor' } 'in_progress' { 'sürüyor' } 'review' { 'incelemede' } 'blocked' { 'engelli' } 'done' { 'bitti' } 'cancelled' { 'iptal' } 'backlog' { 'birikim' } default { $d } } }
function SureK($a, $b) {
    # kompakt sure: 47 sn / 3 dk 26 sn / 1 sa 12 dk  ("3d 26s" gun gibi okunuyordu, v13e)
    if (-not $a) { return '—' }; if (-not $b) { $b = Get-Date }
    $sec = [int]($b - $a).TotalSeconds; if ($sec -lt 0) { $sec = 0 }
    if ($sec -lt 60) { return "$sec sn" }; if ($sec -lt 3600) { return "$([int][Math]::Floor($sec/60)) dk $($sec%60) sn" }
    return "$([int][Math]::Floor($sec/3600)) sa $([int][Math]::Floor(($sec%3600)/60)) dk"
}
function Yuzde([double]$pay, [double]$payda) { if ($payda -le 0) { return '—' }; return ('%{0}' -f [int][Math]::Round(100.0 * $pay / $payda)) }
function KareYaz($L, [int]$w) {
    if ($Tek) { foreach ($ln in $L) { [Console]::Write("$ln$RS`n") }; return }
    $script:lastFrame = Write-CizKare ([System.Collections.Generic.List[string]]$L) $w $script:lastFrame
}
function PencereBoyu { $w = 160; $h = 50; try { $w = $Host.UI.RawUI.WindowSize.Width; $h = $Host.UI.RawUI.WindowSize.Height } catch { }; if ($Genislik -gt 0) { $w = $Genislik }; if ($Yukseklik -gt 0) { $h = $Yukseklik }; return @($w, $h) }
function LastMsg { for ($i = $rows.Count - 1; $i -ge 0; $i--) { if ($rows[$i].kind -eq 'msg') { return $rows[$i] } }; return $null }
function OkSinceFail {
    # son basarisiz komuttan sonra basarili bir komut geldi mi (cozulmus sayilir)
    for ($i = $rows.Count - 1; $i -ge 0; $i--) { $r = $rows[$i]; if ($r.kind -ne 'cmd') { continue }; return [bool]$r.ok }
    return $true
}

function FeedLine($r, [int]$w, [string]$tsShow, $lastMsgRef) {
    # her olay tek satir; mesajlar ilk cumle, soluk; zaman yalniz dakika degisince
    $ts = if ($tsShow) { "$cFaint$($tsShow.PadRight(6))$RS" } else { ' ' * 6 }
    $body = $w - 10
    switch ($r.kind) {
        'cmd' {
            if ($r.ok) { $mark = "$cFaint✓$RS"; $col = $cText } elseif ($r.sandbox) { $mark = "$cWarn◐$RS"; $col = $cText } else { $mark = "$cErr✕$RS"; $col = $cText }
            $dur = if ($r.dur) { "  $cFaint$($r.dur)$RS" } else { '' }
            $code = if ($r.ok) { '' } elseif ($r.sandbox) { "  $cWarn sandbox engeli$RS$cFaint (spawn EPERM; host'ta koşar)$RS" } else { "  $cErr başarısız · rc $($r.code)$RS" }
            $ad = IsAdi $r.cmd $r.ph $r.ck $r.detail
            $kalan = $body - 6 - (VisLen $code) - (VisLen $dur) - (VisLen $ad) - 4
            $kisa = if ($kalan -ge 24 -and $ad -notmatch '^(Test|Tam kontrol|Denetim|Sır|Commit|Takım|Üretilen)') { "  $cFaint$(ShortCmd $r.cmd ([Math]::Min(60, $kalan)))$RS" } else { '' }
            $tekrS = if ($r.tekrar) { "  $cFaint×$($r.tekrar)$RS" } else { '' }
            return "$ts $mark $col$ad$RS$kisa$code$dur$tekrS"
        }
        'msg' {
            if ($lastMsgRef -and [object]::ReferenceEquals($r, $lastMsgRef)) { return $null }   # son soz zaten ustte
            $t = ($r.text -replace '[*`#]', '' -replace '\s+', ' ').Trim()
            if ($t -match '^\s*\{\s*"\s*outcome') { return $null }   # JSON handoff: SONUC bolumu gosterir
            if (Yabanci $t) { return $null }   # isci notu baska dilde: akisa alma (son soz bolumu uyarir)
            if ($t -match '^(.{20,}?[.!?])\s') { $t = $Matches[1] }
            return "$ts $cFaint»$RS $cMuted$(CutWord $t ([Math]::Min(100, $body - 4)))$RS"
        }
        'think' { return "$ts $cThink∙ $ITAL$(CutWord $r.text ([Math]::Min(100, $body - 4)))$RS" }
        'file' { return $null }   # DOSYALAR bolumu gosteriyor
        'ok' { return "$ts $cOk✓$RS $cText$(Cut ($r.text -replace '^✓\s*', '') ($body - 4))$RS" }
        'err' { return "$ts $cErr✕$RS $cText$(CutWord (($r.text -replace '^✕\s*', '') -replace '\s+', ' ') ([Math]::Min(100, $body - 4)))$RS" }
        'divider' { return $null }
        default { return "$ts $cFaint$(Cut $r.text ($body - 2))$RS" }
    }
}

function CheckRows([int]$w, [int]$max) {
    $lines = New-Object System.Collections.Generic.List[string]
    if ($st.checks.Count -eq 0) { $lines.Add("$cFaint henüz doğrulama koşmadı$RS"); return $lines }
    $items = @($st.checks.GetEnumerator() | Sort-Object { $_.Value.seq } -Descending | Select-Object -First $max)
    $nameW = [Math]::Max(16, [Math]::Min(30, $w - 24))
    foreach ($kv in $items) {
        $v = $kv.Value
        $mark = if ($v.ok) { "$cOk✓$RS" } elseif ($v.sandbox) { "$cWarn◐$RS" } else { "$cErr✕$RS" }
        $det = if ($v.sandbox -and -not $v.ok) { 'sandbox' } elseif ($v.detail) { $v.detail } elseif ($v.ok) { 'geçti' } else { 'başarısız' }
        $detCol = if ($v.ok) { $cMuted } elseif ($v.sandbox) { $cWarn } else { $cErr }
        $dur = if ($v.dur) { "$cFaint$($v.dur)$RS" } else { '' }
        $lines.Add("$mark $cText$(Pad $kv.Key $nameW)$RS $detCol$(Pad $det 12)$RS $dur")
    }
    return $lines
}
function FileRows([int]$w, [int]$max) {
    $lines = New-Object System.Collections.Generic.List[string]
    $all = @($st.lastFiles); $files = @($all | Select-Object -Last $max)
    if (-not $all.Count) { $lines.Add("$cFaint dosya değişmedi (yalnız inceleme)$RS"); return $lines }
    for ($i = $files.Count - 1; $i -ge 0; $i--) { $lines.Add("$cFaint✎$RS $cText$(CutLeft $files[$i] ($w - 3))$RS") }
    if ($all.Count -gt $files.Count) { $lines.Add("$cFaint  +$($all.Count - $files.Count) daha$RS") }
    return $lines
}

function Render([int]$tick) {
    $pb = PencereBoyu; $w = $pb[0]; $h = $pb[1]
    if ($w -lt 60) { $w = 60 }
    $inner = $w - 4
    $twoCol = $w -ge 110
    $done = ($st.rc -ne $null -or $st.turnDone)
    $evAge = if ($st.lastEvent) { ((Get-Date) - $st.lastEvent).TotalSeconds } else { -1 }
    $silent = (-not $done -and $evAge -gt 180)
    $okEnd = ($st.rc -eq 0 -or ($null -eq $st.rc -and $st.turnDone))
    $glyph = if ($done) { if ($okEnd) { '✓' } else { '✕' } } elseif ($silent) { '◐' } elseif ($st.start) { $spin[$tick % $spin.Count] } else { '…' }
    $badge = if ($st.rc -ne $null -and $st.rc -ne 0) { "$bgBad$BOLD ✕ HATA rc=$($st.rc) $RS" }
             elseif ($done) { switch ($st.verdict) { 'pass' { "$bgRun$BOLD ✓ BİTTİ $RS" } 'partial' { "$bgPart$BOLD ◐ KISMEN $RS" } 'warn' { "$bgPart$BOLD ◐ UYARI $RS" } '' { "$bgDone$BOLD ✓ BİTTİ $RS" } default { "$bgBad$BOLD ✕ $($st.verdict.ToUpper([cultureinfo]'tr-TR')) $RS" } } }
             elseif (-not $st.start) { "$bgWait$BOLD BEKLİYOR $RS" }
             elseif ($silent) { "$bgIdle$BOLD ◐ SESSİZ $(Sure $st.lastEvent) $RS" }
             else { "$bgPart$BOLD $glyph ÇALIŞIYOR $RS" }
    $badgeKey = (Strip $badge) -replace '[⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏]', ''
    if (-not $Tek -and $st.prevBadge -and $badgeKey -ne $st.prevBadge -and $done) { try { [Console]::Write([char]7) } catch { } }
    $st.prevBadge = $badgeKey
    $endAt = if ($st.finish) { $st.finish } elseif ($done -and $st.lastEvent) { $st.lastEvent } else { Get-Date }
    $mins = if ($st.start) { [int](($endAt - $st.start).TotalMinutes) } else { 0 }
    $phaseName = if ($done) { 'bitti' } elseif ($st.current) { 'komut' } else { 'bekliyor' }
    if (-not $Tek) { try { $Host.UI.RawUI.WindowTitle = "$glyph $Kart $phaseName $mins dk" } catch { } }
    $unresolved = ($st.lastFail -and -not $done -and -not (OkSinceFail))

    if ($h -lt 12) {
        $line = "$badge $cTitle$Kart$RS $cCmd$(ShortCmd $(if ($st.current) { $st.current } else { '—' }) 40)$RS $cFaint$(Sure $st.currentStart)$RS · $($st.cmdOk) komut $(if ($unresolved) { "$cErr$($st.cmdFail) başarısız$RS" } else { "$($st.cmdFail) başarısız" })"
        [Console]::Write("$ESC[H" + (Pad $line $w) + "$ESC[J"); return
    }

    $L = New-Object System.Collections.Generic.List[string]
    # ---- baslik ----
    $bs = if ($st.boardStatus) { $bsc = switch ($st.boardStatus) { 'in_progress' { $cOk } 'blocked' { $cErr } default { $cMuted } }; "$cFrame─ $cMuted pano$RS $bsc$(PanoTr $st.boardStatus)$RS " } else { '' }
    $clockLab = "$cFrame─ $cFaint$((Get-Date).ToString('HH:mm'))$RS$cFrame ─╮$RS"
    $rightW = 10 + (VisLen $bs)
    $titleLab = "$cTitle$BOLD$Kart$RS" + $(if ($st.role) { "$cFrame · $cAccent$(RolTr $st.role)$RS" } else { '' }) + "$cFrame · $cMuted$Run$RS" + $(if ($st.title -and $st.title -ne 'pano dışı koşu' -and $st.title -notlike 'Team run *') { "$cFrame  $cMuted$(CutWord $st.title ($inner - $rightW - 34))$RS" } else { '' })
    $L.Add((HLine ($w - $rightW + 1) $titleLab '╭' '') + $bs + $clockLab)

    # ---- durum bandi (2 satir) ----
    $refTxt = if ($refMins -and -not $done) { $rc2 = if ($mins -gt ($refMins * 2)) { $cWarn } else { $cFaint }; $oran = if ($refMins -gt 0) { $mins / [double]$refMins } else { 0 }; " $(MiniBar $oran 6 $(if ($mins -gt ($refMins * 2)) { $cWarn } else { $cAccent })) $rc2/ ~$refMins dk$RS" } else { '' }
    $leaseTxt = if ($done) { '' } elseif ($st.lease) {
        $rem = $st.lease - (Get-Date)
        if ($rem.TotalSeconds -le 0) { "   $cMuted kira$RS $cWarn doldu$RS" }
        else { $total = if ($st.leaseFrom) { ($st.lease - $st.leaseFrom).TotalSeconds } else { 0 }; $ratio = if ($total -gt 0) { $rem.TotalSeconds / $total } else { 1 }; $lc = if ($rem.TotalMinutes -lt 10) { $cWarn } else { $cAccent }; "   $cMuted kira$RS $(MiniBar $ratio 6 $lc) $cText$([int]$rem.TotalMinutes) dk$RS" }
    } else { '' }
    $commitTxt = if ($done -and $st.commitFresh -and $st.commit -match '^(\S+)') { "   $cMuted commit$RS $cText$($Matches[1])$RS" } else { '' }
    $chkOk = @($st.checks.GetEnumerator() | Where-Object { $_.Value.ok }).Count
    $oranTxt = if ($done -and $st.checks.Count) { "   $(if ($chkOk -eq $st.checks.Count) { $cOk } elseif ($chkOk -eq 0) { $cErr } else { $cWarn })$chkOk/$($st.checks.Count) doğrulama geçti$RS" } else { '' }
    $s1 = "$badge$oranTxt$leaseTxt$commitTxt   $cMuted model$RS $cFaint$Model$RS" + $(if ($st.turns -gt 1) { "   $cMuted tur$RS $cText$($st.turns)$RS" } else { '' }) + $(if ($st.thread) { "   $cMuted oturum$RS $cFaint$($st.thread.Substring(0, [Math]::Min(8, $st.thread.Length)))$RS" } else { '' })
    $L.Add((Row $s1 $w))
    $dogF = 0; $kesF = 0; foreach ($rw in $rows) { if ($rw.kind -eq 'cmd' -and -not $rw.ok) { if ($rw.ck -or $rw.ph -eq 'test' -or $rw.ph -eq 'takim') { $dogF++ } else { $kesF++ } } }
    $failTxt = "$(if ($unresolved) { $cErr } elseif ($dogF) { $cWarn } else { $cFaint })doğrulama ✕ $dogF$RS   $cFaint keşif ✕ $kesF$RS"
    $warns = @()
    if (-not $done -and $evAge -gt 60) { $warns += "$cWarn son olay $(Sure $st.lastEvent) önce$RS" }
    if (-not $done -and $st.procChecked -and $st.start -and -not $st.proc -and $evAge -gt 60) { $warns += "$cErr süreç bulunamadı$RS" }
    if ($st.freeMb -and $st.freeMb -lt 4096) { $warns += "$(if ($st.freeMb -lt 2048) { $cErr } else { $cWarn }) RAM $(Num ($st.freeMb/1024.0) 1) GB$RS" }
    if ($st.rcLost) { $warns += "$cWarn sarmalayıcı koptu, süreç izleniyor$RS" }
    if ($warns.Count) { $L.Add((Row "  $($warns -join '   ')" $w)) }
    # stat kartlari (v13): tek bakista sure / jeton / komut / dosya / test / son olay
    $tokIn = $st.inTok; $tokOut = $st.outTok; $tokC = $st.cachedTok
    $testTxt = if ($st.lastTest -match '^(\d+) pass / (\d+) fail$') { $pf = [int]$Matches[2]; "$cOk$($Matches[1]) geçti$RS · $(if ($pf) { $cErr } else { $cFaint })$pf başarısız$RS" } else { "$cFaint test koşmadı$RS" }
    $testAlt = $(if ($st.checks.Count) { "$(@($st.checks.GetEnumerator() | Where-Object { $_.Value.ok }).Count)/$($st.checks.Count) doğrulama" } else { 'doğrulama yok' })
    $sonTxt = if ($done) { "$cMuted iş bitti$RS" } elseif ($st.lastEvent) { $ea = ((Get-Date) - $st.lastEvent).TotalSeconds; "$(if ($ea -gt 180) { $cErr } elseif ($ea -gt 60) { $cWarn } else { $cText })$(SureK $st.lastEvent) önce$RS" } else { "$cFaint henüz yok$RS" }
    $sonAlt = if ($st.proc) { "Codex süreci $($st.proc.pid) · $($st.proc.mb) MB" } elseif ($st.procChecked -and $st.start -and -not $done) { 'Codex süreci bulunamadı' } elseif ($done) { "$($st.msgs) mesaj · $($st.reasoning) düşünce" } else { "tur $($st.turns)" }
    $sonDosya = if (@($st.lastFiles).Count) { "son: $(CutLeft ([string]$st.lastFiles[$st.lastFiles.Count - 1]) 26)" } else { 'değişiklik yok (yalnız inceleme)' }
    $cards = @(
        @{ t = 'SÜRE'; l = @(("$cText$(Sure $st.start $endAt)$RS" + $(if ($refMins -and -not $done) { "  $(MiniBar $(if ($refMins -gt 0) { $mins / [double]$refMins } else { 0 }) 8 $(if ($mins -gt ($refMins * 2)) { $cWarn } else { $cAccent }))" } else { '' })), $(if ($refMins) { "önceki işçiler ort. ~$refMins dk" } else { 'karşılaştırma yok (ilk koşu)' })) },
        @{ t = 'JETON'; l = @("giriş $cText$(Fmt $tokIn)$RS · çıkış $cText$(Fmt $tokOut)$RS", "önbellek payı $(Yuzde $tokC $tokIn)") },
        @{ t = 'KOMUT'; l = @("$cText$($st.cmdOk)$RS başarılı · $(if ($unresolved) { $cErr } elseif ($dogF) { $cWarn } else { $cFaint })$($st.cmdFail) başarısız$RS", $(if ($dogF -gt 0) { "doğrulama komutu $dogF başarısız" } elseif ($kesF -gt 0) { "${cFaint}keşif komutu $kesF başarısız (önemsiz)$RS" } else { "${cFaint}hata yok$RS" })) },
        @{ t = 'DOSYA'; l = @("$cText$(@($st.lastFiles).Count)$RS dosya · $cText$($st.files)$RS değişiklik", $sonDosya) },
        @{ t = 'TEST'; l = @($testTxt, $testAlt) },
        @{ t = 'SON OLAY'; l = @($sonTxt, $sonAlt) }
    )
    foreach ($cl in @(Cards $cards $inner 32)) { $L.Add((Row $cl $w)) }

    # ---- su an / sonuc ----
    $lastMsg = LastMsg
    if ($done) {
        $L.Add((HLine $w (Sec 'SONUÇ') '├' '┤'))
        $ol = @(); if ($st.outcome) { $ol = @(Wrap $st.outcome ([Math]::Min(100, $inner - 12))) | Select-Object -First 3 }
        $temiz = ($st.outcome -replace '[`*]', '' -replace '\s+', ' ').Trim()
        $ol = @(); if ($temiz) { $ol = @(Wrap $temiz ([Math]::Min(100, $inner - 12))) | Select-Object -First 3 }
        $olAll = @(); if ($temiz) { $olAll = @(Wrap $temiz ([Math]::Min(100, $inner - 12))) }
        if ($st.outcome -and (Yabanci $st.outcome)) { $ol = @("rapor Türkçe değil; özet gizlendi. Raporu aç: $(if ($finalMd) { Split-Path $finalMd -Leaf } else { '—' })"); $olAll = $ol }
        $neden = @(); $nedenSb = 0; foreach ($kv in $st.checks.GetEnumerator()) { if (-not $kv.Value.ok) { $neden += (IsAdi '' 'test' $kv.Key ''); if ($kv.Value.sandbox) { $nedenSb++ } } }; $neden = @($neden | Select-Object -Unique)
        if ($ol.Count) { for ($i = 0; $i -lt $ol.Count; $i++) { $txt = if ($i -eq $ol.Count - 1 -and $olAll.Count -gt $ol.Count) { "$($ol[$i]) $cFaint…$RS" } else { $ol[$i] }; $L.Add((Row "          $cMuted$txt$RS" $w)) } } else { $L.Add((Row "          $cFaint rapor bekleniyor (işçi bitti, motor topluyor)$RS" $w)) }
        if ($st.verdict -and $st.verdict -ne 'pass' -and $neden.Count) { $L.Add((Row "$cWarn$BOLD neden$RS     $cText$(CutWord ("$(if ($st.verdict -eq 'warn') { 'uyarı' } else { 'kısmen' }): $($neden.Count) doğrulama geçmedi$(if ($nedenSb -eq $neden.Count) { ', hepsi sandbox engeli (host''ta ayrıca koşar)' } elseif ($nedenSb) { ", $nedenSb tanesi sandbox engeli" }) ($($neden -join ', '))") ([Math]::Min(100, $inner - 12)))$RS" $w)) }
    } else {
        $cur = if ($st.current) { $age = ((Get-Date) - $st.currentStart).TotalSeconds; $ac = if ($age -gt 600) { $cErr } elseif ($age -gt 60) { $cWarn } else { $cFaint }; "$cText$(ShortCmd $st.current ([Math]::Min(60, $inner - 30)))$RS   $ac· $(Sure $st.currentStart)$RS" }
               else { $lastCmdAt = $null; for ($i = $rows.Count - 1; $i -ge 0; $i--) { if ($rows[$i].kind -eq 'cmd' -and $rows[$i].ts) { $lastCmdAt = $rows[$i].ts; break } }; "$cMuted bekliyor$RS" + $(if ($st.lastEvent) { "   $cFaint· son olaydan $(Sure $st.lastEvent)$RS" } else { '' }) }
        $evre = 'kesif'; for ($i = $rows.Count - 1; $i -ge 0; $i--) { $rr2 = $rows[$i]; if ($rr2.kind -ne 'cmd') { continue }; if ($rr2.ck -eq 'git commit') { $evre = 'teslim' } elseif ($rr2.ck -or $rr2.ph -eq 'test') { $evre = 'dogrulama' } elseif ($rr2.ph -eq 'duzenle') { $evre = 'yazma' } else { $evre = 'kesif' }; break }
        $evreler = @(@('kesif', 'keşif'), @('yazma', 'yazma'), @('dogrulama', 'doğrulama'), @('teslim', 'teslim')); $ei = [Array]::IndexOf(@($evreler | ForEach-Object { $_[0] }), $evre)
        $es = @(); for ($i = 0; $i -lt 4; $i++) { if ($i -lt $ei) { $es += "$cFaint✓ $($evreler[$i][1])$RS" } elseif ($i -eq $ei) { $es += "$cAccent● $($evreler[$i][1])$RS" } else { $es += "$cBarOff○ $($evreler[$i][1])$RS" } }
        if (-not $st.start) { $cur = "$cFaint henüz başlamadı · sohbete ""baslat $Run"" yazılınca işçi açılır$RS" }
        $L.Add((HLine $w (Sec 'ŞU AN') '├' '┤'))
        $L.Add((Row "          $cur" $w))
        $L.Add((Row "          $($es -join "$cFrame ─ $RS")" $w))
        if ($lastMsg -and (Yabanci $lastMsg.text)) { $L.Add((Row "$cMuted son söz$RS   $cFaint not Türkçe değil; gizlendi$RS" $w)) }
        elseif ($lastMsg) {
            $ml = @(Wrap (($lastMsg.text -replace '[*`#]', '') -replace '\s+', ' ') ([Math]::Min(100, $inner - 12))); $show = [Math]::Min($ml.Count, 2)
            for ($i = 0; $i -lt $show; $i++) { $pre = if ($i -eq 0) { "$cMuted son söz$RS   " } else { '          ' }; $txt = if ($i -eq $show - 1 -and $ml.Count -gt $show) { "$($ml[$i]) $cFaint…$RS" } else { $ml[$i] }; $L.Add((Row "$pre$cMsg$txt$RS" $w)) }
        }
    }
    $L.Add((Blank $w))

    # ---- dogrulamalar | dosyalar ----
    $tableRows = if ($h -ge 34) { 6 } else { 3 }
    $leftW = if ($twoCol) { 62 } else { $inner }
    $cr = @(CheckRows ($leftW - 4) $tableRows)   # tek elemanli List string'e acilir; @() ile dizi
    $fr = @(FileRows $(if ($twoCol) { $inner - $leftW - 4 } else { $inner - 4 }) $tableRows)
    if ($twoCol) {
        $L.Add((HLine $w '' '├' '┤'))
        $L.Add((Row (Cols "$(Sec 'DOĞRULAMALAR')  $cFaint$(@($st.checks.GetEnumerator() | Where-Object { $_.Value.ok }).Count)/$($st.checks.Count) geçti$RS" "$(Sec 'DOSYALAR')  $cFaint$(@($st.lastFiles).Count) dosya$RS" $w $leftW) $w))
        $n = [Math]::Max($cr.Count, $fr.Count)
        for ($i = 0; $i -lt $n; $i++) { $a = if ($i -lt $cr.Count) { "  $($cr[$i])" } else { '' }; $b = if ($i -lt $fr.Count) { $fr[$i] } else { '' }; $L.Add((Row (Cols $a $b $w $leftW) $w)) }
    } else {
        $L.Add((Row (Sec 'DOĞRULAMALAR') $w)); foreach ($ln in $cr) { $L.Add((Row "  $ln" $w)) }
        $L.Add((Blank $w))
        $L.Add((Row "$(Sec 'DOSYALAR')  $cFaint$(@($st.lastFiles).Count) dosya$RS" $w)); foreach ($ln in $fr) { $L.Add((Row "  $ln" $w)) }
    }
    $L.Add((Blank $w))

    # ---- son hata (yalniz cozulmemisse) ----
    if ($unresolved) {
        $L.Add((Row "$cErr▌ ✕$RS $cText$(ShortCmd $st.lastFail.cmd ([Math]::Min(60, $inner - 24)))$RS  $cFaint· rc $($st.lastFail.code) · $($st.lastFail.at.Substring(0,5))$RS" $w))
        $failRow = $null; for ($i = $rows.Count - 1; $i -ge 0; $i--) { if ($rows[$i].kind -eq 'cmd' -and -not $rows[$i].ok) { $failRow = $rows[$i]; break } }
        if ($failRow -and $failRow.out) { $ol = @(Wrap $failRow.out ([Math]::Min(100, $inner - 6)) | Where-Object { $_ -notmatch '^[\s~+]+$' }); if ($ol.Count) { $L.Add((Row "$cErr▌$RS   $cMuted$($ol[-1])$RS" $w)) } }
        $L.Add((Blank $w))
    } elseif (-not $done -and $st.lastErrLine -and $st.lastErrAt -and ((Get-Date) - $st.lastErrAt).TotalMinutes -lt 15) {
        $L.Add((Row "$cErr▌ ✕$RS $cMuted stderr$RS  $cText$(CutWord $st.lastErrLine ([Math]::Min(100, $inner - 14)))$RS" $w)); $L.Add((Blank $w))
    }

    # ---- akis ----
    $L.Add((HLine $w (Sec 'AKIŞ') '├' '┤'))
    $avail = $h - $L.Count - $(if ($done) { 4 } else { 2 }); if ($avail -lt 3) { $avail = 3 }
    $lastIdx = if ($script:freezeAt -ge 0) { [Math]::Min($script:freezeAt, $rows.Count) - 1 } else { $rows.Count - 1 }
    $vis = New-Object System.Collections.Generic.List[int]
    for ($i = $lastIdx; $i -ge 0 -and $vis.Count -lt $avail; $i--) {
        $r = $rows[$i]; $rk = $r.kind
        if ($rk -eq 'file' -or $rk -eq 'divider' -or $rk -eq 'ok') { continue }   # dosyalar DOSYALAR'da, jeton [m] ile
        if ($rk -eq 'cmd' -and -not $r.ok -and $r.ck -and $vis.Count -gt 0) { $prev = $rows[$vis[$vis.Count - 1]]; if ($prev.kind -eq 'cmd' -and -not $prev.ok -and $prev.ck -eq $r.ck) { if (-not $prev.tekrar) { $prev.tekrar = 1 }; $prev.tekrar++; continue } }
        if ($rk -eq 'think' -and $script:hideThink) { continue }
        if ($script:onlyImportant -and ($rk -eq 'info' -or ($rk -eq 'cmd' -and ($r.ph -eq 'oku' -or ((IsAdi $r.cmd $r.ph $r.ck $r.detail) -like 'Okuma*'))))) { continue }   # okuma/kesif komutlari (basarisiz olanlar dahil) gurultudur
        if ($rk -eq 'msg' -and $lastMsg -and [object]::ReferenceEquals($r, $lastMsg) -and -not $done) { continue }
        $vis.Add($i)
    }
    $lastMin = ''
    $lines = New-Object System.Collections.Generic.List[string]
    for ($k2 = $vis.Count - 1; $k2 -ge 0; $k2--) {
        $r = $rows[$vis[$k2]]
        $m = if ($r.ts) { $r.ts.Substring(0, 5) } else { '' }
        $tsShow = if ($m -and $m -ne $lastMin) { $lastMin = $m; $m } else { '' }
        $fl = FeedLine $r $inner $tsShow $(if ($done) { $null } else { $lastMsg })
        if ($fl) { $lines.Add([string]$fl) }
    }
    $take = [Math]::Min($avail, $lines.Count)
    if ($lines.Count -eq 0) { $L.Add((Row "  $cFaint$(if ($st.start) { 'işçinin ilk komutu bekleniyor' } else { 'koşu başlayınca olaylar burada' })$RS" $w)); $take = 1 }
    for ($i = $lines.Count - $take; $i -lt $lines.Count; $i++) { $L.Add((Row "  $($lines[$i])" $w)) }
    $sirada = if ($done) { if (-not $finalMd) { "işçi bitti, motor henüz toplamadı: beyin takim collect $Run" } elseif ($st.verdict -eq 'pass') { "hazır: işçi tamam · koşu panosundan devam et (beyin takim izle $Run)" } else { "raporu oku: $(Split-Path $finalMd -Leaf) · sonra koşu panosu: beyin takim izle $Run" } } else { '' }
    $hedefYuk = if ($done) { [Math]::Max(22, $L.Count + $(if ($sirada) { 2 } else { 0 }) + 1) } else { $h }
    $bosla = $hedefYuk - $L.Count - $(if ($sirada) { 2 } else { 0 }) - 1
    for ($i = 0; $i -lt $bosla; $i++) { $L.Add((Blank $w)) }
    if ($sirada) {
        $L.Add((Blank $w))
        $sp2 = @($sirada -split ' · ', 2)
        if ((VisLen $sirada) -gt ($inner - 14) -and $sp2.Count -eq 2) { $L.Add((Row "$cAccent$BOLD▌ SIRADA$RS   $cText$($sp2[0])$RS" $w)); $L.Add((Row "$cAccent▌$RS          $cMuted$($sp2[1])$RS" $w)) }
        else { $L.Add((Row "$cAccent$BOLD▌ SIRADA$RS   $cText$sirada$RS" $w)) }
    }

    # ---- alt cizgi ----
    $kT = if ($script:hideThink) { "$cFaint[t]$RS$cMuted düşünmeyi aç$RS" } else { "$cAccent[t]$RS$cText düşünmeyi gizle$RS" }
    $kE = if ($script:onlyImportant) { "$cFaint[e]$RS$cMuted akış: hepsi$RS" } else { "$cAccent[e]$RS$cText akış: önemli$RS" }
    $kP = if ($script:freezeAt -ge 0) { "$cWarn[boşluk] çöz$RS" } else { "$cFaint[boşluk]$RS$cMuted dondur$RS" }
    $kM = if ($script:showTok) { "$cAccent[m]$RS$cText maliyet: $(Fmt $st.inTok) giriş · $(Fmt $st.outTok) çıkış$RS" } else { "$cFaint[m]$RS$cMuted maliyet$RS" }
    $extra = "  $kM" + $(if ($st.start -and ((Get-Date) - $st.start).TotalSeconds -lt 60 -and $w -ge 120) { "$cFrame  ─  $RS$cFaint yalnız izler; sekmeyi kapatmak işçiyi durdurmaz$RS" } else { '' })
    $L.Add((HLine $w "$kT  $kE  $kP  $cFaint[q]$RS$cMuted çık$RS$extra" '╰' '╯'))
    KareYaz $L $w
}


# ======================= KOSU PANOSU (-Kart verilmezse) =======================
# Tek ekranda butun kosu (design_reviewer spesifikasyonu 2026-10-13): rozet, asama hatti, isci tablosu,
# BUTUNLESTIRME | DOGRULAMA, SIRADA (ne yapmali + neden). Yalniz okur; yukseklik icerige gore.
function IsciDurumTr([string]$d) { switch ($d) { 'planned' { 'bekliyor' } 'queued' { 'sırada' } 'spawning' { 'açılıyor' } 'running' { 'çalışıyor' } 'finished' { 'bitti' } 'collected' { 'toplandı' } 'integrated' { 'birleşti' } 'failed' { 'başarısız' } 'timed_out' { 'zaman aşımı' } 'scope_violation' { 'kapsam ihlali' } 'rejected_content' { 'içerik reddi' } 'conflict' { 'çakışma' } 'aborted' { 'iptal' } 'paused_limit' { 'limit' } default { $d } } }
function VerdictTr([string]$v) { switch ($v) { 'pass' { "$cOk✓ geçti$RS" } 'warn' { "$cWarn◐ uyarı$RS" } 'partial' { "$cWarn◐ kısmen$RS" } 'blocked' { "$cErr✕ engellendi$RS" } 'fail' { "$cErr✕ başarısız$RS" } '' { "$cFaint—$RS" } default { "$cErr✕ $v$RS" } } }
function KosuAsamalar($rr) {
    # 1 plan (kayit var) 2 baslat (onay tuketildi) 3 topla (tum isciler terminal) 4 butunlestir (integration.ok) 5 dogrula (verdict) 6 ana dal (merge onayi tuketildi)
    $ws = @($rr.workers); $term = @('finished', 'failed', 'timed_out', 'scope_violation', 'aborted', 'collected', 'integrated', 'conflict', 'paused_limit')
    $ok = @(
        $true,
        [bool]($rr.approvals -and $rr.approvals.start),
        ([string]$rr.status -in @('collected', 'integrated', 'verified', 'merged')),
        [bool]($rr.integration -and $rr.integration.ok),
        [bool]($rr.verification -and $rr.verification.verdict -in @('pass', 'warn')),
        [bool]($rr.approvals -and $rr.approvals.merge)
    )
    $cur = 6; for ($i = 0; $i -lt 6; $i++) { if (-not $ok[$i]) { $cur = $i; break } }
    return @{ Ok = $ok; Cur = $cur }
}
$script:jetonCache = @{}
function IsciJeton([string]$taskId) {
    # motor isci kaydina usage yazamadiysa (gozetmen hatasi, el ile onarim) turn.completed olaylarindan topla; dosya degismedikce onbellek
    $f = Join-Path (Join-Path (Join-Path $p.TeamRuns $Run) $taskId) 'events.jsonl'
    if (-not (Test-Path -LiteralPath $f)) { return $null }
    $t = (Get-Item -LiteralPath $f).LastWriteTimeUtc
    if ($script:jetonCache.ContainsKey($f) -and $script:jetonCache[$f].t -eq $t) { return $script:jetonCache[$f].u }
    $i = 0L; $o = 0L; $c = 0L; $var = $false
    foreach ($ln in ((Read-Shared $f) -split "`n")) {
        if ($ln -notmatch '"turn\.completed"') { continue }
        try { $e = $ln | ConvertFrom-Json; if ($e.usage) { $var = $true; $i += [long]$e.usage.input_tokens; $o += [long]$e.usage.output_tokens; $c += [long]$e.usage.cached_input_tokens } } catch { }
    }
    $u = if ($var) { [pscustomobject]@{ input_tokens = $i; output_tokens = $o; cached_input_tokens = $c } } else { $null }
    $script:jetonCache[$f] = @{ t = $t; u = $u }; return $u
}
$olayAd = @{ planned = 'planlandı'; planning_failed = 'plan hatası'; started = 'başladı'; start_rolled_back = 'başlatma geri alındı'; supervisor_tick_failed = 'gözetmen hatası'
    conductor_repair = 'şef onarımı'; usage_limit = 'kota sınırı'; paused = 'duraklatıldı'; supervisor_complete = 'işçiler bitti'; worker_content_rejected = 'içerik reddi'
    scope_violation = 'kapsam ihlali'; worker_collected_read_only = 'rapor alındı'; collection_complete = 'toplandı'; integration_complete = 'bütünleştirildi'
    verification_complete = 'doğrulandı'; merged = 'ana dala alındı'; aborted = 'iptal'
    worker_finished = 'bitti'; worker_failed = 'başarısız'; worker_rejected_content = 'içerik reddi'; worker_collected = 'toplandı'; worker_collected_existing_commit = 'toplandı' }
$script:detay = $false   # kosu panosu: [d] butunlestirme kontrollerinin tamami
function MotorHataTr([string]$m) {
    $m = ((Clean $m) -replace '\s+', ' ').Trim()
    if ($m -match 'Team content in (\S+) contains a ([\w-]+) and was rejected') { return "içerik reddi: $($Matches[1]) sır benzeri satır içeriyor" }
    if ($m -match 'actual worktree changes exceed the declared write scope') { return 'yazma kapsamının dışına çıktı' }
    if ($m -match 'worker produced no Git changes') { return 'Git değişikliği üretmedi' }
    if ($m -match 'final handoff file is missing') { return 'handoff dosyası yok' }
    if ($m -match '^invalid final handoff: (.*)$') { return "handoff geçersiz: $($Matches[1])" }
    if ($m -match 'idle_timeout') { return 'boşta kaldı, zaman aşımı' }
    if ($m -match 'abort_requested') { return 'iptal istendi' }
    if ($m -match 'EPERM: operation not permitted, rename') { return 'kayıt dosyası kilitliydi (Windows EPERM); gözetmen tick''i düştü' }
    return $m
}
$script:ozetCache = @{}
function IsciOzet([string]$taskId) {
    # isci events.jsonl'inden tek geciste: jeton (turn.completed) + dogrulama kontrolleri (son durumlari) ; dosya degismedikce onbellek
    $f = Join-Path (Join-Path (Join-Path $p.TeamRuns $Run) $taskId) 'events.jsonl'
    if (-not (Test-Path -LiteralPath $f)) { return $null }
    $t = (Get-Item -LiteralPath $f).LastWriteTimeUtc
    if ($script:ozetCache.ContainsKey($f) -and $script:ozetCache[$f].t -eq $t) { return $script:ozetCache[$f].o }
    $i = 0L; $o = 0L; $c = 0L; $var = $false; $kont = [ordered]@{}
    foreach ($ln in ((Read-Shared $f) -split "`n")) {
        if ($ln -match '"turn\.completed"') {
            try { $e = $ln | ConvertFrom-Json; if ($e.usage) { $var = $true; $i += [long]$e.usage.input_tokens; $o += [long]$e.usage.output_tokens; $c += [long]$e.usage.cached_input_tokens } } catch { }
        } elseif ($ln -match '"item\.completed"' -and $ln -match '"command_execution"') {
            try {
                $e = $ln | ConvertFrom-Json; $it = $e.item
                $ck = CheckKey (Clean (CleanCmd ([string]$it.command)))
                if ($ck -and $ck -ne 'git commit' -and $ck -notlike 'team-run *') { $kont[$ck] = ($null -eq $it.exit_code -or $it.exit_code -eq 0) }
            } catch { }
        }
    }
    $gec = @($kont.Values | Where-Object { $_ }).Count
    $oz = [pscustomobject]@{ usage = $(if ($var) { [pscustomobject]@{ input_tokens = $i; output_tokens = $o; cached_input_tokens = $c } } else { $null }); gecen = $gec; toplam = $kont.Count }
    $script:ozetCache[$f] = @{ t = $t; o = $oz }; return $oz
}
function KisaSure([double]$sec) { if ($sec -lt 0) { $sec = 0 }; if ($sec -lt 60) { return "$([int]$sec) sn" }; if ($sec -lt 3600) { return "$([int][Math]::Round($sec / 60)) dk" }; return "$([int][Math]::Floor($sec / 3600)) sa $([int][Math]::Floor(($sec % 3600) / 60)) dk" }
function OlayZaman($rr, [string]$ev, [switch]$Ilk) {
    $hit = @($rr.history | Where-Object { $_.event -eq $ev -and $_.at })
    if (-not $hit.Count) { return $null }
    $x = if ($Ilk) { $hit[0] } else { $hit[-1] }
    return ([DateTime]$x.at).ToLocalTime()
}
function Paketle([string[]]$parcalar, [int]$gen, [int]$maxSatir) {
    # parcalari " · " ile, satir genisligini asmadan en fazla $maxSatir satira yerlestirir
    $sat = New-Object System.Collections.Generic.List[string]; $cur = ''
    foreach ($pc in $parcalar) {
        if (-not $pc) { continue }
        $aday = if ($cur) { "$cur · $pc" } else { $pc }
        if ((VisLen $aday) -le $gen -or -not $cur) { $cur = $aday } else { $sat.Add($cur); $cur = $pc; if ($sat.Count -ge $maxSatir) { break } }
    }
    if ($cur -and $sat.Count -lt $maxSatir) { $sat.Add($cur) }
    return @($sat)
}
# Windows bildirimi: kosu kullanicidan bir sey bekledigi ya da bir sorun ciktigi anda tek bildirim.
# Ilk cizimde var olan durumlar bildirilmez (yalniz SONRADAN olusan olaylar). BEYIN_BILDIRIM=kapali susturur.
$script:bildirimAcik = $(try { [string](Get-BeyinAyar 'BEYIN_BILDIRIM' (Get-BeyinAyarVars 'BEYIN_BILDIRIM')) -ne 'kapali' } catch { $true })
$script:olayGoruldu = $null; $script:sonBildirim = [datetime]::MinValue
function Bildir([string]$baslik, [string]$metin) {
    if (-not $script:bildirimAcik) { return }
    try {
        [void][Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
        [void][Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime]
        $x = New-Object Windows.Data.Xml.Dom.XmlDocument
        $x.LoadXml("<toast><visual><binding template='ToastGeneric'><text>$([Security.SecurityElement]::Escape($baslik))</text><text>$([Security.SecurityElement]::Escape($metin))</text></binding></visual></toast>")
        $app = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'
        [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($app).Show([Windows.UI.Notifications.ToastNotification]::new($x))
    } catch { }
}
# Kosu kaydindan olay kumesi: anahtar -> okunur metin. Saf islev (test edilir).
function KosuOlaylari($rr, [bool]$sahipsiz) {
    $o = [ordered]@{}; $id = [string]$rr.runId; $st = [string]$rr.status
    switch ($st) {
        'planned'  { $o['durum:planned'] = "onay bekliyor: sohbete yaz  baslat $id" }
        'verified' { $o['durum:verified'] = "doğrulandı, birleştirme onayı bekliyor: birlestir $id" }
        'merged'   { $o['durum:merged'] = 'ana dala alındı' }
        'failed'   { $o['durum:failed'] = 'koşu başarısız' }
        'aborted'  { $o['durum:aborted'] = 'koşu iptal edildi' }
    }
    foreach ($wk in @($rr.workers | Where-Object { $null -ne $_ })) {
        $t = [string]$wk.taskId; $d = [string]$wk.status
        if ($d -eq 'paused_limit') { $o["kota:$t"] = "$t kota sınırına takıldı" }
        elseif ($d -in @('failed', 'timed_out', 'scope_violation', 'rejected_content', 'conflict')) { $o["sorun:$t"] = "$t sorunlu bitti ($d)" }
        elseif ($d -in @('finished', 'collected', 'integrated')) { $o["bitti:$t"] = "$t bitti" }
    }
    $ig = $rr.integration
    if ($ig -and -not $ig.ok) { $o['sorun:butunlestirme'] = 'bütünleştirme kontrolü düştü ya da çakışma var' }
    $v = $rr.verification
    if ($v -and $v.verdict -and [string]$v.verdict -notin @('pass', 'warn')) { $o['sorun:dogrulama'] = "doğrulama geçmedi ($($v.verdict))" }
    if ($sahipsiz) { $o['sahipsiz'] = "gözetmen durdu: beyin takim resume --run $id" }
    return $o
}
function OlaylariBildir($rr, [bool]$sahipsiz) {
    $o = KosuOlaylari $rr $sahipsiz
    if ($null -eq $script:olayGoruldu) { $script:olayGoruldu = @{}; foreach ($k in $o.Keys) { $script:olayGoruldu[$k] = $true }; return }
    # Kalkan durum yeniden kurulur: ayni isci ikinci kez kotaya takilirsa ya da gozetmen yine durursa yine bildirilir.
    foreach ($k in @($script:olayGoruldu.Keys)) { if (-not $o.Contains($k)) { $script:olayGoruldu.Remove($k) } }
    $yeni = @($o.Keys | Where-Object { -not $script:olayGoruldu.ContainsKey($_) })
    if (-not $yeni.Count) { return }
    foreach ($k in $yeni) { $script:olayGoruldu[$k] = $true }
    Bildir "Beyin takım · $([string]$rr.runId)" (@($yeni | ForEach-Object { $o[$_] }) -join ' · ')
}
# Gozetmen nabzi: kayitli pid yasamiyor ve son nabiz 60 sn'den eski ise kosu sahipsiz kalmistir (uyku, cokme, yeniden baslatma).
function GozetmenDurmus($rr) {
    $sv = $rr.supervisor; if (-not $sv) { return $false }
    $yas = [double]::PositiveInfinity
    if ($sv.heartbeatAt) { try { $yas = ((Get-Date).ToUniversalTime() - ([datetime]::Parse([string]$sv.heartbeatAt)).ToUniversalTime()).TotalSeconds } catch { } }
    if ($yas -lt 60) { return $false }
    $canli = $false; if ($sv.pid) { $canli = [bool](Get-Process -Id ([int]$sv.pid) -ErrorAction SilentlyContinue) }
    return -not $canli
}
function RenderRun([int]$tick) {
    $pb = PencereBoyu; $w = $pb[0]; $h = $pb[1]
    if ($w -lt 80) { $w = 80 }
    $inner = $w - 4
    $kompakt = $w -lt 110
    $rr = $null; try { $rr = Read-Shared $runRec | ConvertFrom-Json } catch { }
    $L = New-Object System.Collections.Generic.List[string]
    if (-not $rr) { $L.Add((HLine $w "$cTitle$BOLD$Run$RS" '╭' '╮')); $L.Add((Row "$cFaint koşu kaydı okunamadı$RS" $w)); $L.Add((HLine $w '' '╰' '╯')); KareYaz $L $w; return }
    $ws = @($rr.workers | Where-Object { $null -ne $_ }); $st2 = [string]$rr.status
    $sorunluD = @('failed', 'timed_out', 'scope_violation', 'rejected_content', 'conflict', 'aborted')
    $calisan = @($ws | Where-Object { $_.status -in @('queued', 'spawning', 'running') }).Count
    $bekleyen = @($ws | Where-Object { $_.status -in @('planned', 'paused_limit') }).Count
    $bitenS = $ws.Count - $calisan - $bekleyen
    $sorunlu = @($ws | Where-Object { $_.status -in $sorunluD }).Count
    $kismen = @($ws | Where-Object { $_.status -notin $sorunluD -and $_.verdict -and $_.verdict -ne 'pass' }).Count
    $temiz = [Math]::Max(0, $bitenS - $sorunlu - $kismen)
    $as = KosuAsamalar $rr
    $ig = $rr.integration; $v = $rr.verification
    $cakisma = @($(if ($ig) { $ig.conflicts } else { @() }) | Where-Object { $null -ne $_ }).Count -gt 0   # @($null).Count = 1 (PS 5.1)
    $kontrolDustu = [bool]($ig -and -not $ig.ok -and -not $cakisma)
    $dogrulamaDustu = [bool]($v -and $v.verdict -and $v.verdict -notin @('pass', 'warn'))
    $uyari = [bool]($v -and $v.verdict -eq 'warn')
    $id = [string]$rr.runId
    $sahipsiz = [bool]($st2 -eq 'running' -and $calisan -gt 0 -and (GozetmenDurmus $rr))
    try { OlaylariBildir $rr $sahipsiz } catch { }

    # ---- rozet ----
    if ($st2 -eq 'aborted') { $badge = "$bgBad$BOLD ✕ İPTAL $RS"; $glyph = '✕' }
    elseif ($st2 -eq 'failed') { $badge = "$bgBad$BOLD ✕ BAŞARISIZ $RS"; $glyph = '✕' }
    elseif ($st2 -eq 'merged') { $badge = "$bgRun$BOLD ✓ ANA DALDA $RS"; $glyph = '✓' }
    elseif ($sahipsiz) { $badge = "$bgBad$BOLD ▲ GÖZETMEN DURDU $RS"; $glyph = '▲' }
    elseif ($calisan -gt 0) { $glyph = $spin[$tick % $spin.Count]; $badge = "$bgPart$BOLD $glyph ÇALIŞIYOR $RS" }
    elseif ($cakisma) { $badge = "$bgBad$BOLD ✕ ÇAKIŞMA $RS"; $glyph = '✕' }
    elseif ($kontrolDustu) { $badge = "$bgBad$BOLD ✕ KONTROL DÜŞTÜ $RS"; $glyph = '✕' }
    elseif ($dogrulamaDustu) { $badge = "$bgBad$BOLD ✕ DOĞRULANAMADI $RS"; $glyph = '✕' }
    elseif ($st2 -eq 'verified' -and $uyari) { $badge = "$bgPart$BOLD ◐ UYARIYLA DOĞRULANDI $RS"; $glyph = '◐' }
    elseif ($st2 -eq 'verified') { $badge = "$bgRun$BOLD ✓ DOĞRULANDI $RS"; $glyph = '✓' }
    elseif ($st2 -eq 'planned') { $badge = "$bgWait$BOLD ◐ ONAY BEKLİYOR $RS"; $glyph = '◐' }
    elseif ($st2 -eq 'paused') { $badge = "$bgIdle$BOLD ◐ KOTA SINIRI $RS"; $glyph = '◐' }
    else { $badge = "$bgDone$BOLD ▸ ŞEF SIRASI $RS"; $glyph = '▸' }
    if (-not $Tek) { try { $Host.UI.RawUI.WindowTitle = "$glyph koşu $Run" } catch { } }

    # ---- baslik: taban dal saat'i ezmesin diye gerekirse kirpilir ----
    $clockLab = "$cFrame─ $cFaint$((Get-Date).ToString('HH:mm'))$RS$cFrame ─╮$RS"
    $sabit = "$cTitle$BOLD$Run$RS$cFrame · $cMuted koşu panosu$RS$cFrame · $cMuted taban dal $RS" + $(if ($rr.repoName) { "$cFrame · $cMuted repo $cText$(Cut (Clean ([string]$rr.repoName)) 30)$RS" } else { '' })
    $tabanGen = [Math]::Max(8, ($w - 9 - 6) - (VisLen $sabit))
    $titleLab = "$cTitle$BOLD$Run$RS$cFrame · $cMuted koşu panosu$RS$cFrame · $cMuted taban dal $cText$(Cut (Clean ([string]$rr.baseBranch)) $tabanGen)$RS" + $(if ($rr.repoName) { "$cFrame · $cMuted repo $cText$(Cut (Clean ([string]$rr.repoName)) 30)$RS" } else { '' })
    $L.Add((HLine ($w - 9) $titleLab '╭' '') + $clockLab)

    # ---- zamanlar ----
    $onayS = if ($rr.approvals -and $rr.approvals.start -and $rr.approvals.start.consumedAt) { ([DateTime]$rr.approvals.start.consumedAt).ToLocalTime() } else { $null }
    $onayM = if ($rr.approvals -and $rr.approvals.merge -and $rr.approvals.merge.consumedAt) { ([DateTime]$rr.approvals.merge.consumedAt).ToLocalTime() } else { $null }
    $t0 = $(if ($rr.startedAt) { ([DateTime]$rr.startedAt).ToLocalTime() } elseif ($onayS) { $onayS } else { $null })
    $tSon = $null; foreach ($hh in @($rr.history)) { if ($hh.at) { $tSon = ([DateTime]$hh.at).ToLocalTime() } }
    $bittiMi = ($st2 -in @('merged', 'aborted', 'failed', 'verified'))
    $sure = if ($t0) { SureK $t0 $(if ($bittiMi) { $tSon } else { $null }) } else { '—' }

    # ---- isci ozetleri (motor kaydi + events.jsonl yedegi) ----
    $oz = @{}; $dosya = 0; $commits = 0; $tokIn = 0L; $tokOut = 0L; $tokC = 0L; $durs = @(); $maxDur = 0.0
    foreach ($wk in $ws) {
        $o1 = IsciOzet ([string]$wk.taskId); $oz[[string]$wk.taskId] = $o1
        $dosya += @($wk.changedPaths | Where-Object { $null -ne $_ }).Count; if ($wk.commit) { $commits++ }
        $use = if ($wk.usage -and $wk.usage.input_tokens) { $wk.usage } elseif ($o1) { $o1.usage } else { $null }
        if ($use) { $tokIn += [long]$use.input_tokens; $tokOut += [long]$use.output_tokens; $tokC += [long]$use.cached_input_tokens }
        if ($wk.startedAt) { $bitis = $(if ($wk.finishedAt) { [DateTime]$wk.finishedAt } else { Get-Date }); $dsec = ($bitis - [DateTime]$wk.startedAt).TotalSeconds; if ($wk.finishedAt) { $durs += $dsec }; if ($dsec -gt $maxDur) { $maxDur = $dsec } }
    }
    $ortIsci = if ($durs.Count) { KisaSure (($durs | Measure-Object -Average).Average) } else { '' }

    # ---- durum satiri ----
    $s1 = "$badge   $cMuted süre$RS $cText$sure$RS" + $(if ($onayS) { "   $cMuted başlatma$RS $cText$($onayS.ToString('HH:mm'))$RS" } else { '' }) + $(if ($onayM) { "   $cMuted ana dala alma$RS $cText$($onayM.ToString('HH:mm'))$RS" } else { '' }) + "   $cMuted model$RS $cFaint$($rr.model)$RS"
    $L.Add((Row $s1 $w))
    if ($st2 -eq 'failed' -and $rr.failure) { $L.Add((Row "  $cErr↳ $(CutWord (MotorHataTr ([string]$rr.failure)) ($inner - 6))$RS" $w)) }
    $L.Add((Blank $w))

    # ---- AŞAMA: cubuk + adimlar + onaylar + olaylar ----
    $L.Add((HLine $w (Sec 'AŞAMA') '├' '┤'))
    $adlar = @('plan', 'başlat', 'topla', 'bütünleştir', 'doğrula', 'ana dala al')
    $tamam = 0; foreach ($o2 in $as.Ok) { if ($o2) { $tamam++ } }
    $kirikVar = ($cakisma -or $kontrolDustu -or $dogrulamaDustu -or $st2 -in @('aborted', 'failed'))
    $barCol = if ($kirikVar) { $cErr } elseif ($tamam -eq 6) { $cOk } elseif ($uyari) { $cWarn } else { $cAccent }
    $durumTxt = if ($tamam -eq 6) { "$cOk tamam$RS" } elseif ($kirikVar -and $as.Cur -lt 6) { "$cErr takıldı: $($adlar[$as.Cur])$RS" } elseif ($as.Cur -lt 6) { "$cMuted sıradaki:$RS $cText$($adlar[$as.Cur])$RS" } else { '' }
    $barW = [Math]::Min(48, $inner - 40)
    $L.Add((Row "  $(MiniBar ($tamam / 6.0) $barW $barCol)  $cText$BOLD$tamam/6$RS $cMuted adım ·$RS$durumTxt" $w))
    $segs = @()
    for ($i = 0; $i -lt 6; $i++) {
        $kirik = ($i -eq $as.Cur -and $kirikVar)
        if ($as.Ok[$i]) { $segs += "$cOk✓$RS $cMuted$($adlar[$i])$RS" }
        elseif ($kirik) { $segs += "$cErr$BOLD✕ $($adlar[$i])$RS" }
        elseif ($i -eq $as.Cur) { $segs += "$cAccent$BOLD▸ $($adlar[$i])$RS" }
        else { $segs += "$cFaint○ $($adlar[$i])$RS" }
    }
    $bag = if ($kompakt) { 1 } else { 3 }
    $line = ''
    for ($i = 0; $i -lt 6; $i++) { $line += $segs[$i]; if ($i -lt 5) { $line += $(if ($as.Ok[$i]) { " $cOk$('━' * $bag)$RS " } else { " $cBarOff$('╌' * $bag)$RS " }) } }
    $L.Add((Row ("  " + $line) $w))
    # onaylar: kosu bu iki insan onayina takilir
    $onB = if ($onayS) { "$cOk✓ başlat$RS $cFaint$($onayS.ToString('HH:mm'))$RS" } elseif ($st2 -eq 'planned') { "$cWarn◐ başlat bekliyor$RS" } else { "$cFaint○ başlat$RS" }
    $onM = if ($onayM) { "$cOk✓ ana dala al$RS $cFaint$($onayM.ToString('HH:mm'))$RS" } elseif ($st2 -eq 'verified') { "$cWarn◐ ana dala al bekliyor$RS" } else { "$cFaint○ ana dala al$RS" }
    $L.Add((Row "  $cAccent onay$RS     $onB $cFrame·$RS $onM" $w))
    $olaylar = @($rr.history | Where-Object { $_.event -and $_.event -notin @('worker_collected') } | Select-Object -Last 8)
    if ($olaylar.Count) {
        $parca = @()
        foreach ($ol in $olaylar) {
            $ad = if ($olayAd.ContainsKey([string]$ol.event)) { $olayAd[[string]$ol.event] } else { ([string]$ol.event) -replace '_', ' ' }
            if ($ol.taskId) { $ad += " $(([string]$ol.taskId) -replace '^TASK-', '#')" }
            $saat = try { ([DateTime]$ol.at).ToLocalTime().ToString('HH:mm') } catch { '' }
            $renk = if ($ol.event -in @('supervisor_tick_failed', 'planning_failed', 'worker_content_rejected', 'worker_rejected_content', 'worker_failed', 'scope_violation', 'aborted', 'start_rolled_back')) { $cErr } elseif ($ol.event -in @('conductor_repair', 'usage_limit', 'paused')) { $cWarn } else { $cMuted }
            $parca += "$cFaint$saat$RS $renk$ad$RS"
        }
        # en yeniler kalir: sigmayan eski olaylar bastan duser ("…")
        $sep = " $cFrame·$RS "; $sigan = @(); $alan = $inner - 14
        for ($k = $parca.Count - 1; $k -ge 0; $k--) { $aday = @($parca[$k]) + $sigan; if ((VisLen ($aday -join $sep)) -gt $alan) { break }; $sigan = $aday }
        $on = if ($sigan.Count -lt $parca.Count) { "$cFaint…$RS " } else { '' }
        $L.Add((Row "  $cAccent olaylar$RS  $on$($sigan -join $sep)" $w))
    }
    $L.Add((Blank $w))

    # ---- kartlar (karar degerine gore: DOGRULAMA, KONTROL, ISCILER, JETON, SURE, DOSYA) ----
    $ckOk = 0; $ckN = 0; $nTest = 0; $nDen = 0; $nDiger = 0
    $ckList = if ($ig) { @($ig.checks | ForEach-Object { [string]$_.command }) } else { @($rr.checks | ForEach-Object { [string]$_ }) }
    foreach ($cmd in $ckList) { $k0 = CheckKey $cmd; if ($k0 -like 'test*') { $nTest++ } elseif ($k0 -like 'validate-*') { $nDen++ } else { $nDiger++ } }
    if ($ig) { foreach ($ck in @($ig.checks)) { $ckN++; if ($ck.status -eq 0) { $ckOk++ } } }
    $turler = (@($(if ($nTest) { "$nTest test" }), $(if ($nDen) { "$nDen denetim" }), $(if ($nDiger) { "$nDiger diğer" })) | Where-Object { $_ }) -join ' · '
    $vAt = if ($v -and $v.at) { ([DateTime]$v.at).ToLocalTime() } else { $null }
    $vYas = if ($vAt) { "$(KisaSure ((Get-Date) - $vAt).TotalSeconds) önce" } else { '' }
    $dogL = if ($v -and $v.verdict) { @((VerdictTr ([string]$v.verdict)), "$cMuted doğrulayıcı$(if ($vAt) { ' · ' + $vAt.ToString('HH:mm') + ' · ' + $vYas })$RS") + $(if ($v.failure) { @("$cErr$(CutWord ((Clean ([string]$v.failure)) -replace '\s+', ' ') 32)$RS") } else { @() }) }
            elseif ($ig -and $ig.ok) { @("$cAccent▸ sırada$RS", "$cMuted bağımsız test_verifier$RS") } elseif ($ig) { @("$cFaint○ koşmadı$RS", "$cMuted önce bütünleştirme düzelmeli$RS") } else { @("$cFaint○ bekliyor$RS", "$cMuted bütünleştirmeden sonra$RS") }
    $konL = if ($ig) { @($(if ($ig.ok) { "$cOk✓ $ckOk/$ckN geçti$RS" } else { "$cErr✕ $ckOk/$ckN geçti$RS" }), $(if ($cakisma) { "$cErr$(@($ig.conflicts).Count) çakışan dosya$RS" } else { "$cMuted$turler$RS" })) } else { @("$cFaint○ $(@($ckList).Count) kontrol planlı$RS", "$cMuted$turler$RS") }
    # bolunmus isci cubugu: yesil temiz, sari kismen, kirmizi sorunlu, soluk bitmemis
    $bw = 12; $nW = [Math]::Max(1, $ws.Count)
    $g1 = [int][Math]::Round($bw * $temiz / $nW); $y1 = [int][Math]::Round($bw * $kismen / $nW); $r1 = [int][Math]::Round($bw * $sorunlu / $nW); if ($g1 + $y1 + $r1 -gt $bw) { $g1 = $bw - $y1 - $r1 }
    $iBar = "$cOk$('█' * $g1)$cWarn$('█' * $y1)$cErr$('█' * $r1)$cBarOff$('░' * [Math]::Max(0, $bw - $g1 - $y1 - $r1))$RS"
    $isciDetay = (@($(if ($temiz) { "$cOk$temiz temiz$RS" }), $(if ($kismen) { "$cWarn$kismen kısmen$RS" }), $(if ($sorunlu) { "$cErr$sorunlu sorunlu$RS" }), $(if ($calisan) { "$cWarn$calisan çalışıyor$RS" }), $(if ($bekleyen) { "$cFaint$bekleyen bekliyor$RS" })) | Where-Object { $_ }) -join ' · '
    $isL = @("$cText$bitenS/$($ws.Count)$RS bitti  $iBar", $isciDetay)
    $jeL = @("giriş $cText$(Fmt $tokIn)$RS · çıkış $cText$(Fmt $tokOut)$RS", "önbellek payı $(Yuzde $tokC $tokIn)")
    # sure karti: zamanin nereye gittigi (asama sureleri)
    $tBas = OlayZaman $rr 'started' -Ilk; $tTop = OlayZaman $rr 'collection_complete'; $tBut = OlayZaman $rr 'integration_complete'; $tDog = OlayZaman $rr 'verification_complete'; $tAna = OlayZaman $rr 'merged'
    $asamaP = @()
    $sonlu = ($st2 -in @('aborted', 'failed'))
    if ($tBas) { $asamaP += $(if ($tTop) { "iş $(KisaSure ($tTop - $tBas).TotalSeconds)" } elseif (-not $sonlu) { "iş $(KisaSure ((Get-Date) - $tBas).TotalSeconds) $cWarn(sürüyor)$RS" } else { '' }) }
    if ($tTop) { $asamaP += $(if ($tBut) { "bütünleştirme $(KisaSure ($tBut - $tTop).TotalSeconds)" } elseif ($st2 -eq 'collected') { "$cWarn bütünleştirme bekliyor $(KisaSure ((Get-Date) - $tTop).TotalSeconds)$RS" } else { '' }) }
    if ($tBut) { $asamaP += $(if ($tDog) { "doğrulama $(KisaSure ($tDog - $tBut).TotalSeconds)" } elseif ($st2 -eq 'integrated' -and -not $kontrolDustu) { "$cWarn doğrulama bekliyor $(KisaSure ((Get-Date) - $tBut).TotalSeconds)$RS" } else { '' }) }
    $asamaP = @($asamaP | Where-Object { $_ })
    if ($tDog -and $tAna) { $asamaP += "ana dala $(KisaSure ($tAna - $tDog).TotalSeconds)" }
    if ($ortIsci) { $asamaP += "işçi ort. $ortIsci" }
    if (-not $asamaP.Count) { $asamaP = @("$cFaint henüz başlamadı$RS") }
    $kartGen = if ($kompakt) { [int][Math]::Floor(($inner - 4) / 3) - 10 } else { [int][Math]::Floor(($inner - 2) / 3) - 4 }
    $suL = @(Paketle $asamaP $kartGen 2)
    $doL = @("$cText$dosya$RS dosya değişti", "$commits teslim commit'i")
    $kartlar = @(
        @{ t = 'DOĞRULAMA'; l = $dogL; k = "$($dogL[0])$(if ($vYas) { " $cFaint$vYas$RS" })" },
        @{ t = 'KONTROL'; l = $konL; k = "$($konL[0])" },
        @{ t = 'İŞÇİLER'; l = $isL; k = "$cText$bitenS/$($ws.Count)$RS $iBar" },
        @{ t = 'JETON'; l = $jeL; k = "$cText$(Fmt $tokIn)$RS/$cText$(Fmt $tokOut)$RS $cFaint$(Yuzde $tokC $tokIn)$RS" },
        @{ t = 'SÜRE'; l = $suL; k = "$(@(Paketle $asamaP ([int][Math]::Floor(($inner - 4) / 3) - 6) 1)[0])" },
        @{ t = 'DOSYA'; l = $doL; k = "$cText$dosya$RS dosya · $commits commit" }
    )
    if ($kompakt) {
        # dar ekran: kenarliksiz, 3 sutun "ETIKET deger" (isci tablosu ekranin ustunde kalsin)
        $sw = [int][Math]::Floor(($inner - 4) / 3)
        for ($s0 = 0; $s0 -lt $kartlar.Count; $s0 += 3) {
            $hucre = @(); foreach ($kc in @($kartlar[$s0..([Math]::Min($kartlar.Count, $s0 + 3) - 1)])) { $hucre += (Pad "$cAccent$BOLD$($kc.t)$RS $($kc.k)" $sw) }
            $L.Add((Row ("  " + ($hucre -join ' ')) $w))
        }
    } else { foreach ($cl in @(Cards $kartlar $inner 32)) { $L.Add((Row $cl $w)) } }
    $L.Add((Blank $w))

    # ---- isci tablosu ----
    $L.Add((HLine $w (Sec 'İŞÇİLER') '├' '┤'))
    $dar = $inner -lt 104
    $rolW = if ($dar) { 15 } else { 16 }
    $barG = if ($dar) { 0 } else { 6 }
    $hdr = "  $cAccent$(Pad 'TASK' 9) $(Pad 'ROL' $rolW) $(Pad 'DURUM' 14) $(Pad 'SÜRE' (11 + $(if ($barG) { $barG + 1 } else { 0 }))) $(Pad 'JETON' 11) $(Pad 'DOSYA' 13) $(Pad 'SONUÇ' 14)" + $(if (-not $dar) { 'SON OLAY' } else { '' }) + $RS
    $L.Add((Row $hdr $w))
    foreach ($wk in $ws) {
        $d = [string]$wk.status; $o1 = $oz[[string]$wk.taskId]
        $dc = switch ($d) { 'running' { $cWarn } 'spawning' { $cWarn } 'queued' { $cFaint } 'failed' { $cErr } 'timed_out' { $cErr } 'scope_violation' { $cErr } 'conflict' { $cErr } 'rejected_content' { $cErr } 'aborted' { $cMuted } 'planned' { $cFaint } default { $cOk } }
        $dm = switch ($d) { 'running' { "$($spin[$tick % $spin.Count]) " } 'spawning' { '▸ ' } 'finished' { '✓ ' } 'collected' { '✓ ' } 'integrated' { '✓ ' } 'failed' { '✕ ' } 'timed_out' { '✕ ' } 'scope_violation' { '✕ ' } 'rejected_content' { '✕ ' } 'conflict' { '✕ ' } 'aborted' { '✕ ' } default { '○ ' } }
        $ws0 = $(if ($wk.startedAt) { ([DateTime]$wk.startedAt).ToLocalTime() } else { $null })
        $wf = $(if ($wk.finishedAt) { ([DateTime]$wk.finishedAt).ToLocalTime() } else { $null })
        $wsure = if ($ws0) { SureK $ws0 $wf } else { '—' }
        $sureHucre = if ($barG -and $ws0) { $dsec = if ($ws0) { (($(if ($wf) { $wf } else { Get-Date })) - $ws0).TotalSeconds } else { 0 }; "$(MiniBar $(if ($maxDur -gt 0) { $dsec / $maxDur } else { 0 }) $barG $(if ($d -eq 'running') { $cWarn } else { $cAccent })) $cText$wsure$RS" } else { "$cText$wsure$RS" }
        $sonT = if ($wk.lastEventAt) { ([DateTime]$wk.lastEventAt).ToLocalTime() } else { $null }
        $son = if ($sonT) { if ($wf) { $sonT.ToString('HH:mm') } else { "$(KisaSure ((Get-Date) - $sonT).TotalSeconds) önce" } } else { '—' }
        $sonCol = if (-not $wf -and $sonT -and ((Get-Date) - $sonT).TotalSeconds -gt 120 -and $d -eq 'running') { $cWarn } else { $cFaint }
        $use = if ($wk.usage -and $wk.usage.input_tokens) { $wk.usage } elseif ($o1) { $o1.usage } else { $null }
        $jeton = if ($use -and $use.input_tokens) { "$(Fmt ([long]$use.input_tokens))/$(Fmt ([long]$use.output_tokens))" } else { '—' }
        $sha = if ($wk.commit) { " $cFaint$(([string]$wk.commit).Substring(0, [Math]::Min(7, ([string]$wk.commit).Length)))$RS" } else { '' }
        $dosyaH = "$cText$(@($wk.changedPaths | Where-Object { $null -ne $_ }).Count)$RS$sha"
        $sonuc = if (-not $wk.verdict -and $wk.note) { "$cWarn◐ şef$RS" } else { (VerdictTr ([string]$wk.verdict)) + $(if ($o1 -and $o1.toplam -gt 0 -and $wk.verdict -and $o1.gecen -lt $o1.toplam) { " $cFaint$($o1.gecen)/$($o1.toplam)$RS" } else { '' }) }
        $L.Add((Row ("  $cText$(Pad (Clean ([string]$wk.taskId)) 9)$RS $cMuted$(Pad (RolTr (Clean ([string]$wk.role))) $rolW)$RS $dc$(Pad ($dm + (IsciDurumTr $d)) 14)$RS $(Pad $sureHucre (11 + $(if ($barG) { $barG + 1 } else { 0 }))) $cMuted$(Pad $jeton 11)$RS $(Pad $dosyaH 13) $(Pad $sonuc 14)" + $(if (-not $dar) { "$sonCol$son$RS" } else { '' })) $w))
        if ($wk.failure) { $L.Add((Row "            $cErr↳ $(CutWord (MotorHataTr ([string]$wk.failure)) ($inner - 16))$RS" $w)) }
        if ($wk.note) {
            $nl2 = @(Wrap ((Clean ([string]$wk.note)) -replace '\s+', ' ') ($inner - 34))
            for ($j = 0; $j -lt [Math]::Min(2, $nl2.Count); $j++) { $pre = if ($j -eq 0) { "$cWarn$BOLD↳ şef müdahalesi:$RS " } else { '                  ' }; $son2 = if ($j -eq 1 -and $nl2.Count -gt 2) { " $cFaint…$RS" } else { '' }; $L.Add((Row "            $pre$cMuted$($nl2[$j])$RS$son2" $w)) }
        }
    }
    if ($kismen -gt 0) { $L.Add((Row "  $cFaint◐ kısmen: işçinin kendi doğrulamalarından bazıları geçmedi (x/y = geçen/toplam)$RS" $w)) }
    $L.Add((Blank $w))

    # ---- butunlestirme (tek satir ozet; ayrinti [d]) ----
    $L.Add((HLine $w (Sec 'BÜTÜNLEŞTİRME') '├' '┤'))
    if ($ig) {
        $L.Add((Row "  $(if ($ig.ok) { "$cOk✓ temiz$RS" } else { "$cErr✕ sorunlu$RS" }) $cFrame·$RS $cText$(@($ig.merged | Where-Object { $null -ne $_ }).Count)$RS $cMuted işçi dalı$RS $cFaint$($rr.integrationBranch)$RS $cFrame·$RS $(if ($cakisma) { "$cErr çakışma: $(@($ig.conflicts) -join ', ')$RS" } else { "$cMuted çakışma yok$RS" })" $w))
        $dusen = @($ig.checks | Where-Object { $_.status -ne 0 })
        if (-not $dusen.Count -and -not $script:detay) { $L.Add((Row "  $cOk✓$RS $cText$ckOk/$ckN kontrol geçti$RS $cMuted· $turler$RS   $cFaint[d] ayrıntı$RS" $w)) }
        else {
            foreach ($ck in @($ig.checks)) {
                if ($ck.status -eq 0 -and -not $script:detay) { continue }
                $m = if ($ck.status -eq 0) { "$cOk✓$RS" } else { "$cErr✕$RS" }; $ad = IsAdi ([string]$ck.command) 'test' (CheckKey ([string]$ck.command)) ''
                $L.Add((Row "    $m $(if ($ck.status -eq 0) { $cText } else { $cErr })$(Cut $ad ($inner - 16))$RS$(if ($ck.status -ne 0) { "  $cErr rc $($ck.status)$RS" } else { '' })" $w))
            }
            if ($dusen.Count -and -not $script:detay) { $L.Add((Row "    $cFaint$($ckOk) geçen kontrol gizli · [d] ayrıntı$RS" $w)) }
        }
    } else {
        $L.Add((Row "  $cFaint○ henüz bütünleştirilmedi · $(@($ckList).Count) kontrol planlı ($turler)$RS" $w))
        if ($script:detay) { foreach ($cmd in $ckList) { $L.Add((Row "    $cFaint○ $(Cut (IsAdi $cmd 'test' (CheckKey $cmd) '') ($inner - 10))$RS" $w)) } }
    }
    $L.Add((Blank $w))

    # ---- SIRADA ----
    $neden = ''; $nedenCol = $cMuted
    if ($st2 -eq 'aborted') { $adim = "koşu iptal edildi · temizlik: beyin takim cleanup $id" }
    elseif ($st2 -eq 'failed') { $adim = "koşu başarısız · işçi panellerine bak · temizlik: beyin takim cleanup $id" }
    elseif ($st2 -eq 'merged') { $adim = 'bitti: ek adım yok'; $neden = 'kartlar için sohbete onayla <TASK>; push/PR ayrı karar' }
    elseif ($st2 -eq 'planned') { $adim = "başlat: sohbete yaz  baslat $id"; $neden = 'işçiler ancak senin onayınla açılır' }
    elseif ($sahipsiz) { $adim = "gözetmen durmuş (uyku/çökme?): beyin takim resume --run $id"; $neden = 'işçiler kayıtlı Codex oturumlarından devam eder; canlı işçi varsa önce o biter'; $nedenCol = $cWarn }
    elseif ($calisan -gt 0) { $nCal = @($ws | Where-Object { $_.status -in @('spawning', 'running') }).Count; $nSir = $calisan - $nCal; $adim = "bekle: $nCal işçi çalışıyor" + $(if ($nSir) { ", $nSir sırada" } else { '' }); $neden = 'bitince toplanır; işçi panelleri ayrı sekmede' }
    elseif ($st2 -eq 'paused' -and @($ws | Where-Object { $_.status -eq 'paused_limit' }).Count) { $adim = "kota sıfırlanınca kendiliğinden devam: beyin takim resume --run $id --wait"; $neden = 'işçi kaldığı Codex oturumundan sürer; vazgeçersen: beyin takim collect' }
    elseif ($st2 -in @('running', 'paused')) { $adim = "topla: beyin takim collect $id"; $neden = 'işçiler bitti, çıktılar toplanmadı' }
    elseif ($cakisma) { $adim = "çakışmayı çöz: $(@($ig.conflicts) -join ', ')"; $neden = 'düzeltip beyin takim integrate'; $nedenCol = $cErr }
    elseif ($kontrolDustu) { $dus = @($ig.checks | Where-Object { $_.status -ne 0 } | ForEach-Object { IsAdi ([string]$_.command) 'test' (CheckKey ([string]$_.command)) '' } | Select-Object -Unique); $adim = "kontrol başarısız: $($dus -join ', ')"; $neden = 'raporları oku; düzeltip beyin takim integrate'; $nedenCol = $cErr }
    elseif ($st2 -eq 'collected') { $adim = "bütünleştir: beyin takim integrate $id" }
    elseif ($st2 -eq 'integrated') { $adim = "doğrula: beyin takim verify $id" }
    elseif ($dogrulamaDustu) { $adim = "doğrulama geçmedi · raporu oku · beyin takim verify $id"; $nedenCol = $cErr; $neden = $(if ($v.reportId) { "rapor: $($v.reportId)" } else { '' }) }
    elseif ($st2 -eq 'verified') { $adim = "ana dala al: sohbete yaz  birlestir $id"; if ($uyari) { $neden = "uyarıyla doğrulandı: önce rapora bak$(if ($v.reportId) { " ($($v.reportId))" })"; $nedenCol = $cWarn } else { $neden = 'doğrulandı; ana dala alma senin onayınla' } }
    else { $adim = "beyin takim status $id" }
    if (-not $neden -and $kismen -gt 0) { $neden = "$kismen işçi kısmen bitti; işçi raporlarına bak"; $nedenCol = $cWarn }
    $L.Add((HLine $w '' '├' '┤'))
    $L.Add((Row "$cAccent$BOLD▌ SIRADA$RS   $cText$BOLD$adim$RS" $w))
    if ($neden) { $L.Add((Row "$cAccent▌$RS          $nedenCol$neden$RS" $w)) }
    $kD = if ($script:detay) { "$cAccent[d]$RS$cText ayrıntıyı gizle$RS" } else { "$cFaint[d]$RS$cMuted ayrıntı$RS" }
    $L.Add((HLine $w "$cFaint[q]$RS$cMuted çık$RS  $kD$cFrame  ─  $RS$cFaint[1-$([Math]::Min(4, [Math]::Max(1, $ws.Count)))]$RS$cMuted işçi paneli aç$RS$cFrame  ─  $RS$cFaint tüm sistem: beyin merkez$RS$(if ($script:panelMesaj) { "$cFrame  ─  $RS$cWarn$($script:panelMesaj)$RS" })" '╰' '╯'))
    KareYaz $L $w
}

# kendini yenileme: bu dosya degisirse (ve cozumlenebiliyorsa) ayni konsolda yeni surumu baslat, kendini kapat
$selfPath = $PSCommandPath
function SonDamga { $d = $null; foreach ($f in @($selfPath, $cizYol)) { try { $t = (Get-Item -LiteralPath $f).LastWriteTimeUtc; if (-not $d -or $t -gt $d) { $d = $t } } catch { } }; return $d }
$selfStamp = SonDamga
$selfAt = Get-Date
function SelfReloadIfChanged {
    if (-not $selfPath -or -not $selfStamp) { return $false }
    if (((Get-Date) - $script:selfAt).TotalSeconds -lt 5) { return $false }
    $script:selfAt = Get-Date
    try {
        $cur = SonDamga
        if ($cur -le $selfStamp) { return $false }
        if (((Get-Date).ToUniversalTime() - $cur).TotalSeconds -lt 3) { return $false }   # yazim (yayin) bitmemis olabilir
        foreach ($f in @($selfPath, $cizYol)) {
            $tok = $null; $errs = $null
            [void][System.Management.Automation.Language.Parser]::ParseFile($f, [ref]$tok, [ref]$errs)
            if ($errs -and $errs.Count) { $script:selfStamp = $cur; return $false }
        }
        return $true
    } catch { return $false }
}

# Cizim bekcisi: cizim hatasi sessizce yutulursa donmus panel canli gorunur. Hata sayilir ve son satira rozet basilir.
$script:cizimHata = 0; $script:cizimMesaj = ''; $script:sonCizim = Get-Date; $script:panelMesaj = ''
function CizimSonuc([scriptblock]$ciz) {
    try { & $ciz; if ($script:cizimHata) { $script:cizimHata = 0; $script:lastFrame = '' }; $script:sonCizim = Get-Date }
    catch {
        $script:cizimHata++; $script:cizimMesaj = (Clean ([string]$_.Exception.Message)) -replace '\s+', ' '
        try {
            $hh = $Host.UI.RawUI.WindowSize.Height; $ww = [Math]::Max(40, $Host.UI.RawUI.WindowSize.Width)
            $etiket = if ($script:cizimHata -ge 5) { 'BOZUK' } else { 'SORUNLU' }
            $msg = "▲ panel $etiket · $($script:cizimHata) kez çizilemedi · son başarılı çizim $(Ago $script:sonCizim) önce · $($script:cizimMesaj)"
            [Console]::Write("$ESC[$hh;1H$cErr$(Cut $msg ($ww - 1))$RS$ESC[K")
        } catch { }
    }
}

if ($Tek) {
    if (-not $Kart) { RenderRun 0 }
    else { for ($i = 0; $i -lt 200 -and $script:replay; $i++) { ReadNew }; RefreshSide; Render 0 }
    exit 0
}
Clear-Host
$tick = 0; $quit = $false
while ($true) {
    if (SelfReloadIfChanged) {
        try { [Console]::CursorVisible = $true } catch { }
        [Console]::Write("$ESC[H$ESC[J$cMuted izleyici yenileniyor (yeni sürüm)…$RS`n")
        $yArg = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $selfPath, '-Vault', $Vault, '-Run', $Run); if ($Kart) { $yArg += @('-Kart', $Kart) }; if ($Model) { $yArg += @('-Model', $Model) }   # PS 5.1 bos argumani dusurur
        & powershell.exe @yArg
        exit $LASTEXITCODE
    }
    if (-not $Kart) { CizimSonuc { RenderRun $tick } }
    else {
    ReadNew
    if (-not $replay -and -not $replayDividerAdded) { $replayDividerAdded = $true; if ($rows.Count -gt 0) { $rows.Add(@{ kind = 'divider'; ts = '' }) } }
    RefreshSide
    if ($rows.Count -gt 3000) { $rows.RemoveRange(0, $rows.Count - 2000) }
    CizimSonuc { Render $tick }
    }
    $tick++
    try {
        while ([Console]::KeyAvailable) {
            $kk = [Console]::ReadKey($true)
            switch ($kk.KeyChar) {
                'q' { $quit = $true }
                't' { $script:hideThink = -not $script:hideThink }
                'e' { $script:onlyImportant = -not $script:onlyImportant }
                ' ' { $script:freezeAt = $(if ($script:freezeAt -ge 0) { -1 } else { $rows.Count }) }
                'm' { $script:showTok = -not $script:showTok }
                'd' { $script:detay = -not $script:detay; $script:lastFrame = '' }
                { -not $Kart -and $_ -in @('1', '2', '3', '4') } {
                    $script:panelMesaj = ''
                    try {
                        $rrK = Read-Shared $runRec | ConvertFrom-Json
                        $wsK = @($rrK.workers | Where-Object { $null -ne $_ })
                        $ix = [int][string]$_ - 1
                        if ($ix -lt $wsK.Count) {
                            $tid = [string]$wsK[$ix].taskId
                            $sn = Open-BeyinTakimPanel -Paths $p -RunId $Run -TaskIds @($tid)
                            $script:panelMesaj = $(if ($sn.Ok) { "$tid paneli açıldı" } else { "$tid paneli açılamadı: $($sn.Neden)" })
                        } else { $script:panelMesaj = "işçi $($ix + 1) yok" }
                    } catch { $script:panelMesaj = 'panel açılamadı' }
                    $script:lastFrame = ''
                }
                default { }
            }
        }
    } catch { }
    if ($quit) { break }
    Start-Sleep -Milliseconds 500
}
try { [Console]::CursorVisible = $true } catch { }
Write-Host "$RS"
