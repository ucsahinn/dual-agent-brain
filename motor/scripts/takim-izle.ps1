param(
    [string]$Vault = '',
    [Parameter(Mandatory = $true)][string]$Run,
    [string]$Kart = '',
    [string]$Model = ''
)
# takim-izle.ps1 v13 - Takim kosusu isci paneli + kosu panosu (Beyin). v13: stat kartlari (widget), asama ilerleme cubugu, Turkce rol/pano adlari, jeton ozeti, dar ekranda kartlar alt alta. v12: Catppuccin Mocha paleti, cerceveye gomulu bolum basliklari, durum = glif + sozcuk, titreme onleme. v9: genislik-duyarli (CJK), Turkce is adlari, yabanci dildeki isci notlari gizli. Motorun (AgentChef team-run.mjs) kosu kaydini ve iscinin
# events.jsonl'ini YALNIZ OKUR; isciye dokunmaz, dosya yaratmaz. Sekmeyi kapatmak isciyi durdurmaz; 'q' cikar.
# Kaynak: <state>\team-runs\<runId>.json (kosu kaydi), <state>\team-runs\<runId>\<TASK>\events.jsonl, stderr.log,
# <state>\team-runs\<runId>\reports\<TASK>-<rol>.md (handoff). Acilis: beyin takim start (otomatik) ya da beyin takim izle <runId> [TASK].
if (-not $Vault) { $Vault = $(if ($env:BEYIN_VAULT) { $env:BEYIN_VAULT } else { Split-Path (Split-Path $PSScriptRoot -Parent) -Parent }) }
. (Join-Path $Vault 'motor\hooks\lib.ps1')
$p = Get-BeyinPaths -Vault $Vault
$Board = $p.Board
$runRec = Join-Path $p.TeamRuns "$Run.json"
$Worktree = ''
try { $rr0 = Get-Content -LiteralPath $runRec -Raw -Encoding UTF8 | ConvertFrom-Json; $wk0 = @($rr0.workers | Where-Object { [string]$_.taskId -eq $Kart })[0]; if ($wk0 -and $wk0.worktree) { $Worktree = [string]$wk0.worktree }; if (-not $Model -and $rr0.model) { $Model = [string]$rr0.model } } catch { }

try { chcp 65001 | Out-Null } catch { }
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$OutputEncoding = [Text.Encoding]::UTF8
$env:GIT_OPTIONAL_LOCKS = '0'
try { [Console]::CursorVisible = $false } catch { }

# ---------- palet ----------
$ESC = [char]27
function FG([int]$r, [int]$g, [int]$b) { return "$ESC[38;2;$r;$g;${b}m" }
function BG([int]$r, [int]$g, [int]$b) { return "$ESC[48;2;$r;$g;${b}m" }
$RS = "$ESC[0m"; $BOLD = "$ESC[1m"; $ITAL = "$ESC[3m"
# Palet: Catppuccin Mocha (koyu zemin icin kanitli notr palet); tek vurgu (mavi) + uc durum rengi (yesil/sari/kirmizi)
$cText   = FG 205 214 244   # text #cdd6f4
$cMuted  = FG 166 173 200   # subtext #a6adc8
$cFaint  = FG 127 132 156   # overlay #7f849c
$cFrame  = FG 69 71 90      # surface1 #45475a
$cTitle  = FG 180 190 254   # lavender #b4befe
$cAccent = FG 137 180 250   # blue #89b4fa
$cOk     = FG 166 227 161   # green #a6e3a1
$cWarn   = FG 249 226 175   # yellow #f9e2af
$cErr    = FG 243 139 168   # red #f38ba8
$cCmd    = FG 205 214 244
$cMsg    = FG 205 214 244
$cFile   = FG 205 214 244
$cThink  = FG 127 132 156
$cBarOff = FG 69 71 90
$cGutCmd = FG 88 91 112
$pOku = FG 137 180 250; $pDuz = FG 203 166 247; $pTest = FG 249 226 175; $pGit = FG 166 227 161; $pTakim = FG 250 179 135
$bgPanel = ''              # v13: panel zemini terminalin kendi zemini; yamali arka plan kutulari kalkti
$bgBody  = BG 30 30 46
$bgFail  = BG 49 50 68
$bgRun = BG 64 96 62; $bgIdle = BG 110 90 40; $bgDone = BG 49 66 110; $bgBad = BG 120 50 70; $bgWait = BG 49 50 68; $bgPart = BG 110 90 40

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
        $rr = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
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
$rxAnsi = [regex]::new("$ESC\[[0-9;]*m")
$rxCtl1 = [regex]::new("$ESC\[[0-9;?]*[ -/]*[@-~]")
$rxCtl2 = [regex]::new("$ESC\][^$([char]7)]*$([char]7)|[\x00-\x08\x0B-\x1F\x7F]")

# ---------- yardimcilar ----------
function Clean([string]$s) { if ($null -eq $s) { return '' }; $s = $rxCtl1.Replace($s, ''); $s = $rxCtl2.Replace($s, ''); return $s.Replace("`t", '  ') }
function Strip([string]$s) { return $rxAnsi.Replace($s, '') }
function CellW([char]$c) {
    $u = [int]$c
    if ($u -lt 0x1100) { return 1 }
    if (($u -ge 0x1100 -and $u -le 0x115F) -or ($u -ge 0x2E80 -and $u -le 0xA4CF) -or ($u -ge 0xAC00 -and $u -le 0xD7A3) -or ($u -ge 0xF900 -and $u -le 0xFAFF) -or ($u -ge 0xFE30 -and $u -le 0xFE4F) -or ($u -ge 0xFF00 -and $u -le 0xFF60) -or ($u -ge 0xFFE0 -and $u -le 0xFFE6)) { return 2 }
    return 1
}
function VisLen([string]$s) { $t = Strip $s; $n = 0; for ($i = 0; $i -lt $t.Length; $i++) { if ([char]::IsHighSurrogate($t[$i])) { $n += 2; $i++ } else { $n += CellW $t[$i] } }; return $n }
function Cut([string]$s, [int]$w) {
    if ($w -lt 2) { return '' }
    if ((VisLen $s) -le $w) { return $s }
    $out = New-Object Text.StringBuilder; $vis = 0; $i = 0
    while ($i -lt $s.Length -and $vis -lt ($w - 1)) {
        if ($s[$i] -eq $ESC) { $j = $s.IndexOf('m', $i); if ($j -lt 0) { break }; [void]$out.Append($s.Substring($i, $j - $i + 1)); $i = $j + 1; continue }
        if ([char]::IsHighSurrogate($s[$i]) -and ($i + 1) -lt $s.Length) { if ($vis + 2 -gt ($w - 1)) { break }; [void]$out.Append($s.Substring($i, 2)); $i += 2; $vis += 2; continue }
        $cw = CellW $s[$i]; if ($vis + $cw -gt ($w - 1)) { break }
        [void]$out.Append($s[$i]); $vis += $cw; $i++
    }
    return "$($out.ToString())$cMuted…"
}
function Pad([string]$s, [int]$w) { $s = Cut $s $w; return $s + (' ' * [Math]::Max(0, $w - (VisLen $s))) }
function Fmt([long]$n) { if ($n -ge 1000000) { return ('{0:N1}M' -f ($n / 1000000.0)) }; if ($n -ge 1000) { return ('{0:N1}K' -f ($n / 1000.0)) }; return "$n" }
function Ago($t) { if (-not $t) { return '—' }; $s = [int]((Get-Date) - $t).TotalSeconds; if ($s -lt 0) { $s = 0 }; if ($s -lt 60) { return "$s sn" }; if ($s -lt 3600) { return "$([int][Math]::Floor($s/60)) dk $($s%60) sn" }; return "$([int][Math]::Floor($s/3600)) sa $([int][Math]::Floor(($s%3600)/60)) dk" }
function Span($a, $b) { if (-not $a) { return '—' }; if (-not $b) { $b = Get-Date }; $d = $b - $a; if ($d.TotalDays -ge 1) { return ('{0}g {1:hh\:mm\:ss}' -f [int]$d.TotalDays, $d) }; return ('{0:hh\:mm\:ss}' -f $d) }
function DurS([double]$sec) { if ($sec -lt 60) { return ('{0:0.0} sn' -f $sec) }; if ($sec -lt 3600) { return "$([int][Math]::Floor($sec/60)) dk $([int]($sec%60)) sn" }; return "$([int][Math]::Floor($sec/3600)) sa $([int][Math]::Floor(($sec%3600)/60)) dk" }
function Wrap([string]$s, [int]$w) {
    if ($w -lt 8) { $w = 8 }
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($para in (($s -replace "`r", '') -split "`n")) {
        $p = $para.Trim(); if (-not $p) { continue }
        while ($p.Length -gt $w) {
            $cut = $p.LastIndexOf(' ', [Math]::Min($w, $p.Length - 1)); if ($cut -lt ($w / 2)) { $cut = $w }
            if ([char]::IsHighSurrogate($p[$cut - 1])) { $cut-- }
            $out.Add($p.Substring(0, $cut).TrimEnd()); $p = $p.Substring($cut).TrimStart()
        }
        $out.Add($p)
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
        'thread.started' { $st.thread = [string]$ev.thread_id; AddRow 'info' @{ text = "⟡ oturum $($st.thread)" } }
        'turn.started' { $st.turns++ }
        'turn.completed' {
            $u = $ev.usage
            if ($u) { $st.inTok += [long]$u.input_tokens; $st.cachedTok += [long]$u.cached_input_tokens; $st.outTok += [long]$u.output_tokens }
            $st.turnDone = $true
            AddRow 'ok' @{ text = "✔ tur tamamlandı   giriş $(Fmt $st.inTok) · önbellek $(Fmt $st.cachedTok) · çıkış $(Fmt $st.outTok)" }
        }
        'turn.failed' { $st.errors++; AddRow 'err' @{ text = "✖ tur başarısız: " + (Clean (($ev | ConvertTo-Json -Compress -Depth 4))) } }
        'error' { $st.errors++; AddRow 'err' @{ text = "✖ hata: " + (Clean ([string]$ev.message)) } }
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
                    if ($o -match 'ℹ pass (\d+)[\s\S]*?ℹ fail (\d+)') { $st.lastTest = "$($Matches[1]) pass / $($Matches[2]) fail"; $detail = "$($Matches[1])/$([int]$Matches[1]+[int]$Matches[2])"; if ($Matches[2] -eq '0') { $st.lastFail = $null } }
                    elseif ($o -match '(\d+) passed, (\d+) failed') { $st.lastTest = "$($Matches[1]) pass / $($Matches[2]) fail"; $detail = "$($Matches[1])/$([int]$Matches[1]+[int]$Matches[2])"; if ($Matches[2] -eq '0') { $st.lastFail = $null } }
                    elseif ($o -match 'no leaks found') { $detail = 'temiz' }
                    elseif ($o -match 'leaks found: (\d+)') { $detail = "$($Matches[1]) sızıntı" }
                    $ck = CheckKey $c
                    if ($ck) {
                        $st.checkSeq++
                        if ($st.checks.Contains($ck)) { $st.checks[$ck].n++ } else { $st.checks[$ck] = @{ n = 1 } }
                        $st.checks[$ck].ok = $ok; $st.checks[$ck].dur = $dur; $st.checks[$ck].detail = $detail; $st.checks[$ck].seq = $st.checkSeq
                    }
                    if (-not $ok -and ($ck -or $ph -ne 'oku')) { $st.lastFail = @{ cmd = $c; code = $code; at = $now.ToString('HH:mm:ss'); n = $st.cmdFail; key = $ck }; if (-not $script:replay) { try { [Console]::Write([char]7) } catch { } } }   # kesif komutlarinin (okuma) hatasi sabitlenmez
                    elseif ($st.lastFail -and (($st.lastFail.cmd -eq $c) -or ($ck -and $st.lastFail.key -eq $ck))) { $st.lastFail = $null }   # ayni komut/kontrol sonra gecti: cozuldu
                    AddRow 'cmd' @{ ok = $ok; code = $code; dur = $dur; cmd = $c; ph = $ph; ck = $ck; detail = $detail; out = $(if ($ok) { '' } else { $o.Substring(0, [Math]::Min(500, $o.Length)) }) }
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
                'mcp_tool_call' { AddRow 'info' @{ text = "⚙ mcp $(Clean ([string]$it.server))/$(Clean ([string]$it.tool))" } }
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
        $fs = [IO.File]::Open($events, 'Open', 'Read', 'ReadWrite')
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
        $rr = Get-Content -LiteralPath $runRec -Raw -Encoding UTF8 | ConvertFrom-Json
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
            $fs = [IO.File]::Open($errLog, 'Open', 'Read', 'ReadWrite')
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
        try { $f = Get-Content -LiteralPath $finalMd -Raw -Encoding UTF8; if ($f -match '(?s)##\s*Outcome\s*\r?\n(.*?)(?:\r?\n##\s|\z)') { $st.outcome = ((Clean $Matches[1]) -replace '\*\*', '' -replace '\s+', ' ').Trim() } } catch { }
    }
    if (-not $st.outcome -and $st.rc -ne $null -and $st.failureTxt) { $st.outcome = $st.failureTxt }
    if (((Get-Date) - $st.boardAt).TotalSeconds -gt 20) {
        $st.boardAt = Get-Date
        try {
            $raw = $(if ($Worktree -and (Test-Path -LiteralPath $Worktree)) { (& git -C $Worktree log -1 --format='%ct|%h %s' 2>$null | Out-String).Trim() } else { '' })
            if ($raw -match '^(\d+)\|(.+)$') { $st.commit = $Matches[2]; $ct = [DateTimeOffset]::FromUnixTimeSeconds([long]$Matches[1]).LocalDateTime; $st.commitFresh = ($st.start -and $ct -gt $st.start -and (-not $st.finish -or $ct -lt $st.finish.AddMinutes(3))) }
        } catch { }
        try {
            $b = Get-Content -LiteralPath $Board -Raw -Encoding UTF8 | ConvertFrom-Json
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
# yalniz cozulmemis hata, tek vurgu rengi (camgobegi), yesil yalniz ✔/rozet, sari yalniz uyari, kirmizi yalniz cozulmemis hata.
# Sutunlar: bolum etiketi x=2, icerik x=4, ŞU AN/son soz degeri x=12.

function ShortCmd([string]$c, [int]$w) {
    $s = $c -replace 'npm\.cmd', 'npm' -replace 'npx\.cmd', 'npx'
    if ($s -match '^(.*?node --test)\s+((?:\S+\.mjs\s*)+)(.*)$') { $n = @($Matches[2] -split '\s+' | Where-Object { $_ }).Count; $s = "$($Matches[1]) ($n test dosyası)$($Matches[3])" }
    $parts = @($s -split '\s*(?:&&|;|\|\|)\s*' | Where-Object { $_ })
    if ($parts.Count -gt 1) { $s = $parts[0] }
    return (Cut $s $w)
}
function CutLeft([string]$p, [int]$w) { if ($p.Length -le $w) { return $p }; return "$cFaint…$RS" + $p.Substring($p.Length - ($w - 1)) }
function CutWord([string]$s, [int]$w) {
    if ($s.Length -le $w) { return $s }
    $k = $s.LastIndexOf(' ', [Math]::Min($w - 1, $s.Length - 1)); if ($k -lt [int]($w / 2)) { $k = $w - 1 }
    return $s.Substring(0, $k).TrimEnd() + "$cFaint…$RS"
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
    if ($ck -like 'test *' -or $ck -eq 'test') { return 'Testler koştu' + $(if ($detail) { "  $detail" } else { '' }) }
    if ($ck -like 'npm run *') { $n = $ck.Substring(8); if ($n -eq 'check') { return 'Tam kontrol (npm run check)' }; return "npm run $n" }
    if ($ck -eq 'npm test') { return 'Testler koştu (npm test)' }
    if ($ck -like 'validate-*') { return "Doğrulama: $ck" + $(if ($detail) { "  $detail" } else { '' }) }
    if ($ck -eq 'gitleaks') { return 'Sır taraması' + $(if ($detail) { "  $detail" } else { '' }) }
    if ($ck -eq 'git commit') { return 'Commit' }
    if ($ck -like 'team-run *') { return "Takım motoru: $($ck.Substring(9))" }
    if ($ck -eq 'render:targets') { return 'Üretilmiş dosyalar yenilendi' }
    $hedef = ''; if ($c -match '([\w./\\-]+\.(mjs|cjs|json|ts|js|md|ps1|toml|yaml|yml|txt))\b') { $hedef = ($Matches[1] -replace '\\', '/') }
    if ($c -match '^\s*\$\w+\s*=' -or $c -match '^(rg|grep|Select-String|Get-Content|cat|type|ls|dir|Get-ChildItem|find|sed|head|tail)\b') { return 'Okuma' + $(if ($hedef) { ": $(CutLeft $hedef 40)" } else { '' }) }
    if ($ph -eq 'duzenle' -and ($c -match '(Set-Content|Out-File|Add-Content|New-Item|Copy-Item|Move-Item|Remove-Item|apply_patch|\[IO\.File\]::Write)')) { return 'Düzenleme' + $(if ($hedef) { ": $(CutLeft $hedef 40)" } else { '' }) }
    if ($ph -eq 'git') { if ($c -match '(^|[;&|]\s*)git (\w+)') { return "git $($Matches[2])" }; return 'git' }
    if ($c -match '^(rg|grep|Select-String|Get-Content|cat|type|ls|dir|Get-ChildItem|find|sed|head|tail)\b') { return 'Okuma' }
    if ($c -match '^node (\S+\.mjs)') { return "node $($Matches[1])" }
    return 'Komut'
}
function MiniBar([double]$ratio, [int]$w, [string]$col) {
    if ($ratio -lt 0) { $ratio = 0 }; if ($ratio -gt 1) { $ratio = 1 }
    $on = [int][Math]::Round($ratio * $w)
    return "$col$('█' * $on)$cBarOff$('░' * ($w - $on))$RS"
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
function Cards([object[]]$cards, [int]$inner) {
    # stat kartlari (widget): her kart @{ t = 'BAŞLIK'; l = @('satır', ...) }; genis ekranda yan yana, darda 3'lu / 2'li satirlara boler
    $out = New-Object System.Collections.Generic.List[string]
    $n = $cards.Count; if ($n -eq 0) { return $out }
    $perRow = 1; foreach ($cand in @($n, [int][Math]::Ceiling($n / 2.0), [int][Math]::Ceiling($n / 3.0), 2, 1)) { if ($cand -lt 1 -or $cand -gt $n) { continue }; if ([int][Math]::Floor(($inner - ($cand - 1)) / $cand) -ge 32) { $perRow = $cand; break } }
    for ($s0 = 0; $s0 -lt $n; $s0 += $perRow) {
        $grp = @($cards[$s0..([Math]::Min($n, $s0 + $perRow) - 1)])
        $cw = [int][Math]::Floor(($inner - ($grp.Count - 1)) / $grp.Count)
        $hh = 0; foreach ($c in $grp) { if (@($c.l).Count -gt $hh) { $hh = @($c.l).Count } }
        $top = ''; $bot = ''; $mid = @(); for ($k = 0; $k -lt $hh; $k++) { $mid += '' }
        foreach ($c in $grp) {
            $lab = " $cAccent$BOLD$($c.t)$RS$cFrame "
            $fill = $cw - 2 - (VisLen $lab); if ($fill -lt 0) { $fill = 0 }
            $top += "$cFrame┌$lab$('─' * $fill)┐$RS "
            $bot += "$cFrame└$('─' * ($cw - 2))┘$RS "
            for ($k = 0; $k -lt $hh; $k++) { $txt = if ($k -lt @($c.l).Count) { [string]@($c.l)[$k] } else { '' }; $mid[$k] += "$cFrame│$RS " + (Pad $txt ($cw - 4)) + " $cFrame│$RS " }
        }
        $out.Add($top.TrimEnd()); foreach ($m in $mid) { $out.Add($m.TrimEnd()) }; $out.Add($bot.TrimEnd())
    }
    return $out
}
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
            if ($r.ok) { $mark = "$cFaint✔$RS"; $col = $cText } else { $mark = "$cErr✖$RS"; $col = $cText }
            $dur = if ($r.dur) { "  $cFaint$($r.dur)$RS" } else { '' }
            $code = if ($r.ok) { '' } else { "  $cErr başarısız · rc $($r.code)$RS" }
            $ad = IsAdi $r.cmd $r.ph $r.ck $r.detail
            $kalan = $body - 6 - (VisLen $code) - (VisLen $dur) - (VisLen $ad) - 4
            $kisa = if ($kalan -ge 24 -and $ad -notmatch '^(Testler|Tam kontrol|Doğrulama|Sır|Commit|Takım|Üretilmiş)') { "  $cFaint$(ShortCmd $r.cmd ([Math]::Min(60, $kalan)))$RS" } else { '' }
            $tek = if ($r.tekrar) { "  $cFaint×$($r.tekrar)$RS" } else { '' }
            return "$ts $mark $col$ad$RS$kisa$code$dur$tek"
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
        'ok' { return "$ts $cOk✔$RS $cText$(Cut ($r.text -replace '^✔\s*', '') ($body - 4))$RS" }
        'err' { return "$ts $cErr✖$RS $cText$(CutWord (($r.text -replace '^✖\s*', '') -replace '\s+', ' ') ([Math]::Min(100, $body - 4)))$RS" }
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
        $mark = if ($v.ok) { "$cOk✔$RS" } else { "$cErr✖$RS" }
        $det = if ($v.detail) { $v.detail } elseif ($v.ok) { 'geçti' } else { 'başarısız' }
        $detCol = if ($v.ok) { $cMuted } else { $cErr }
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
    $w = $Host.UI.RawUI.WindowSize.Width; $h = $Host.UI.RawUI.WindowSize.Height
    if ($w -lt 60) { $w = 60 }
    $inner = $w - 4
    $twoCol = $w -ge 110
    $done = ($st.rc -ne $null -or $st.turnDone)
    $evAge = if ($st.lastEvent) { ((Get-Date) - $st.lastEvent).TotalSeconds } else { -1 }
    $silent = (-not $done -and $evAge -gt 180)
    $okEnd = ($st.rc -eq 0 -or ($null -eq $st.rc -and $st.turnDone))
    $glyph = if ($done) { if ($okEnd) { '✔' } else { '✖' } } elseif ($silent) { '◐' } elseif ($st.start) { $spin[$tick % $spin.Count] } else { '…' }
    $badge = if ($st.rc -ne $null -and $st.rc -ne 0) { "$bgBad$BOLD ✖ HATA rc=$($st.rc) $RS" }
             elseif ($done) { switch ($st.verdict) { 'pass' { "$bgRun$BOLD ✔ BİTTİ $RS" } 'partial' { "$bgPart$BOLD ◐ KISMEN $RS" } 'warn' { "$bgPart$BOLD ◐ UYARI $RS" } '' { "$bgDone$BOLD ✔ BİTTİ $RS" } default { "$bgBad$BOLD ✖ $($st.verdict.ToUpper([cultureinfo]'tr-TR')) $RS" } } }
             elseif (-not $st.start) { "$bgWait$BOLD BEKLİYOR $RS" }
             elseif ($silent) { "$bgIdle$BOLD ◐ SESSİZ $(Sure $st.lastEvent) $RS" }
             else { "$bgPart$BOLD $glyph ÇALIŞIYOR $RS" }
    $badgeKey = (Strip $badge) -replace '[⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏]', ''
    if ($st.prevBadge -and $badgeKey -ne $st.prevBadge -and $done) { try { [Console]::Write([char]7) } catch { } }
    $st.prevBadge = $badgeKey
    $endAt = if ($st.finish) { $st.finish } elseif ($done -and $st.lastEvent) { $st.lastEvent } else { Get-Date }
    $mins = if ($st.start) { [int](($endAt - $st.start).TotalMinutes) } else { 0 }
    $phaseName = if ($done) { 'bitti' } elseif ($st.current) { 'komut' } else { 'bekliyor' }
    try { $Host.UI.RawUI.WindowTitle = "$glyph $Kart $phaseName $mins dk" } catch { }
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
    $s1 = "$badge$leaseTxt$commitTxt   $cMuted model$RS $cFaint$Model$RS" + $(if ($st.turns -gt 1) { "   $cMuted tur$RS $cText$($st.turns)$RS" } else { '' }) + $(if ($st.thread) { "   $cMuted oturum$RS $cFaint$($st.thread.Substring(0, [Math]::Min(8, $st.thread.Length)))$RS" } else { '' })
    $L.Add((Row $s1 $w))
    $dogF = 0; $kesF = 0; foreach ($rw in $rows) { if ($rw.kind -eq 'cmd' -and -not $rw.ok) { if ($rw.ck -or $rw.ph -eq 'test' -or $rw.ph -eq 'takim') { $dogF++ } else { $kesF++ } } }
    $failTxt = "$(if ($unresolved) { $cErr } elseif ($dogF) { $cWarn } else { $cFaint })doğrulama ✖ $dogF$RS   $cFaint keşif ✖ $kesF$RS"
    $warns = @()
    if (-not $done -and $evAge -gt 60) { $warns += "$cWarn son olay $(Sure $st.lastEvent) önce$RS" }
    if (-not $done -and $st.procChecked -and $st.start -and -not $st.proc -and $evAge -gt 60) { $warns += "$cErr süreç bulunamadı$RS" }
    if ($st.freeMb -and $st.freeMb -lt 4096) { $warns += "$(if ($st.freeMb -lt 2048) { $cErr } else { $cWarn }) RAM $(Num ($st.freeMb/1024.0) 1) GB$RS" }
    if ($st.rcLost) { $warns += "$cWarn sarmalayıcı koptu, süreç izleniyor$RS" }
    if ($warns.Count) { $L.Add((Row "  $($warns -join '   ')" $w)) }
    # stat kartlari (v13): tek bakista sure / jeton / komut / dosya / test / son olay
    $tokIn = $st.inTok; $tokOut = $st.outTok; $tokC = $st.cachedTok
    $testTxt = if ($st.lastTest -match '^(\d+) pass / (\d+) fail$') { $pf = [int]$Matches[2]; "$cOk$($Matches[1]) geçti$RS · $(if ($pf) { $cErr } else { $cFaint })$pf kaldı$RS" } else { "$cFaint test koşmadı$RS" }
    $testAlt = $(if ($st.checks.Count) { "$(@($st.checks.GetEnumerator() | Where-Object { $_.Value.ok }).Count)/$($st.checks.Count) doğrulama" } else { 'doğrulama yok' })
    $sonTxt = if ($done) { "$cMuted bitti$RS" } elseif ($st.lastEvent) { $ea = ((Get-Date) - $st.lastEvent).TotalSeconds; "$(if ($ea -gt 180) { $cErr } elseif ($ea -gt 60) { $cWarn } else { $cText })$(SureK $st.lastEvent) önce$RS" } else { "$cFaint henüz yok$RS" }
    $sonAlt = if ($st.proc) { "Codex süreci $($st.proc.pid) · $($st.proc.mb) MB" } elseif ($st.procChecked -and $st.start -and -not $done) { 'Codex süreci bulunamadı' } elseif ($done) { "$($st.msgs) mesaj · $($st.reasoning) düşünce" } else { "tur $($st.turns)" }
    $sonDosya = if (@($st.lastFiles).Count) { "son: $(CutLeft ([string]$st.lastFiles[$st.lastFiles.Count - 1]) 26)" } else { 'değişiklik yok (yalnız inceleme)' }
    $cards = @(
        @{ t = 'SÜRE'; l = @(("$cText$(Sure $st.start $endAt)$RS" + $(if ($refMins -and -not $done) { "  $(MiniBar $(if ($refMins -gt 0) { $mins / [double]$refMins } else { 0 }) 8 $(if ($mins -gt ($refMins * 2)) { $cWarn } else { $cAccent }))" } else { '' })), $(if ($refMins) { "önceki işçiler ort. ~$refMins dk" } else { 'karşılaştırma yok (ilk koşu)' })) },
        @{ t = 'JETON'; l = @("giriş $cText$(Fmt $tokIn)$RS · çıkış $cText$(Fmt $tokOut)$RS", "önbellek payı $(Yuzde $tokC $tokIn)") },
        @{ t = 'KOMUT'; l = @("$cText$($st.cmdOk)$RS başarılı · $(if ($unresolved) { $cErr } elseif ($dogF) { $cWarn } else { $cFaint })$($st.cmdFail) başarısız$RS", $(if (($dogF + $kesF) -gt 0) { "doğrulama ✖ $dogF · keşif ✖ $kesF" } else { "${cFaint}hata yok$RS" })) },
        @{ t = 'DOSYA'; l = @("$cText$(@($st.lastFiles).Count)$RS dosya · $cText$($st.files)$RS değişiklik", $sonDosya) },
        @{ t = 'TEST'; l = @($testTxt, $testAlt) },
        @{ t = 'SON OLAY'; l = @($sonTxt, $sonAlt) }
    )
    foreach ($cl in @(Cards $cards $inner)) { $L.Add((Row $cl $w)) }

    # ---- su an / sonuc ----
    $lastMsg = LastMsg
    if ($done) {
        $L.Add((HLine $w (Sec 'SONUÇ') '├' '┤'))
        $ol = @(); if ($st.outcome) { $ol = @(Wrap $st.outcome ([Math]::Min(100, $inner - 12))) | Select-Object -First 3 }
        $temiz = ($st.outcome -replace '[`*]', '' -replace '\s+', ' ').Trim()
        $ol = @(); if ($temiz) { $ol = @(Wrap $temiz ([Math]::Min(100, $inner - 12))) | Select-Object -First 3 }
        $olAll = @(); if ($temiz) { $olAll = @(Wrap $temiz ([Math]::Min(100, $inner - 12))) }
        if ($st.outcome -and (Yabanci $st.outcome)) { $ol = @("rapor Türkçe değil; özet gizlendi. Raporu aç: $(if ($finalMd) { Split-Path $finalMd -Leaf } else { '—' })"); $olAll = $ol }
        $neden = @(); foreach ($kv in $st.checks.GetEnumerator()) { if (-not $kv.Value.ok) { $neden += (IsAdi '' 'test' $kv.Key '') } }
        if ($ol.Count) { for ($i = 0; $i -lt $ol.Count; $i++) { $txt = if ($i -eq $ol.Count - 1 -and $olAll.Count -gt $ol.Count) { "$($ol[$i]) $cFaint…$RS" } else { $ol[$i] }; $L.Add((Row "          $cMsg$txt$RS" $w)) } } else { $L.Add((Row "          $cFaint rapor bekleniyor (işçi bitti, motor topluyor)$RS" $w)) }
        if ($st.verdict -and $st.verdict -ne 'pass' -and $neden.Count) { $L.Add((Row "$cMuted neden$RS     $cMuted$(CutWord ("$(if ($st.verdict -eq 'warn') { 'uyarı' } else { 'kısmen' }): $($neden.Count) doğrulama geçmedi ($($neden -join ', '))") ([Math]::Min(100, $inner - 12)))$RS" $w)) }
    } else {
        $cur = if ($st.current) { $age = ((Get-Date) - $st.currentStart).TotalSeconds; $ac = if ($age -gt 600) { $cErr } elseif ($age -gt 60) { $cWarn } else { $cFaint }; "$cText$(ShortCmd $st.current ([Math]::Min(60, $inner - 30)))$RS   $ac· $(Sure $st.currentStart)$RS" }
               else { $lastCmdAt = $null; for ($i = $rows.Count - 1; $i -ge 0; $i--) { if ($rows[$i].kind -eq 'cmd' -and $rows[$i].ts) { $lastCmdAt = $rows[$i].ts; break } }; "$cMuted bekliyor$RS" + $(if ($st.lastEvent) { "   $cFaint· son olaydan $(Sure $st.lastEvent)$RS" } else { '' }) }
        $evre = 'kesif'; for ($i = $rows.Count - 1; $i -ge 0; $i--) { $rr2 = $rows[$i]; if ($rr2.kind -ne 'cmd') { continue }; if ($rr2.ck -eq 'git commit') { $evre = 'teslim' } elseif ($rr2.ck -or $rr2.ph -eq 'test') { $evre = 'dogrulama' } elseif ($rr2.ph -eq 'duzenle') { $evre = 'yazma' } else { $evre = 'kesif' }; break }
        $evreler = @(@('kesif', 'keşif'), @('yazma', 'yazma'), @('dogrulama', 'doğrulama'), @('teslim', 'teslim')); $ei = [Array]::IndexOf(@($evreler | ForEach-Object { $_[0] }), $evre)
        $es = @(); for ($i = 0; $i -lt 4; $i++) { if ($i -lt $ei) { $es += "$cFaint✔ $($evreler[$i][1])$RS" } elseif ($i -eq $ei) { $es += "$cAccent● $($evreler[$i][1])$RS" } else { $es += "$cBarOff○ $($evreler[$i][1])$RS" } }
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
        $L.Add((Row "$cErr▌ ✖$RS $cText$(ShortCmd $st.lastFail.cmd ([Math]::Min(60, $inner - 24)))$RS  $cFaint· rc $($st.lastFail.code) · $($st.lastFail.at.Substring(0,5))$RS" $w))
        $failRow = $null; for ($i = $rows.Count - 1; $i -ge 0; $i--) { if ($rows[$i].kind -eq 'cmd' -and -not $rows[$i].ok) { $failRow = $rows[$i]; break } }
        if ($failRow -and $failRow.out) { $ol = @(Wrap $failRow.out ([Math]::Min(100, $inner - 6)) | Where-Object { $_ -notmatch '^[\s~+]+$' }); if ($ol.Count) { $L.Add((Row "$cErr▌$RS   $cMuted$($ol[-1])$RS" $w)) } }
        $L.Add((Blank $w))
    } elseif (-not $done -and $st.lastErrLine -and $st.lastErrAt -and ((Get-Date) - $st.lastErrAt).TotalMinutes -lt 15) {
        $L.Add((Row "$cErr▌ ✖$RS $cMuted stderr$RS  $cText$(CutWord $st.lastErrLine ([Math]::Min(100, $inner - 14)))$RS" $w)); $L.Add((Blank $w))
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
    $sirada = if ($done) { if (-not $finalMd) { "işçi bitti, motor henüz toplamadı: beyin takim collect $Run" } elseif ($st.verdict -eq 'pass') { "hazır: işçi tamam · koşu panosundan devam et (beyin takim izle $Run)" } else { "raporu oku: $(Split-Path $finalMd -Leaf) · sonra koşu panosu (beyin takim izle $Run)" } } else { '' }
    $hedefYuk = if ($done) { [Math]::Max(22, $L.Count + $(if ($sirada) { 2 } else { 0 }) + 1) } else { $h }
    $bosla = $hedefYuk - $L.Count - $(if ($sirada) { 2 } else { 0 }) - 1
    for ($i = 0; $i -lt $bosla; $i++) { $L.Add((Blank $w)) }
    if ($sirada) { $L.Add((Blank $w)); $L.Add((Row "$cAccent$BOLD▌ SIRADA$RS   $cText$sirada$RS" $w)) }

    # ---- alt cizgi ----
    $kT = if ($script:hideThink) { "$cFaint[t]$RS$cMuted düşünmeyi aç$RS" } else { "$cAccent[t]$RS$cText düşünmeyi gizle$RS" }
    $kE = if ($script:onlyImportant) { "$cFaint[e]$RS$cMuted akış: hepsi$RS" } else { "$cAccent[e]$RS$cText akış: önemli$RS" }
    $kP = if ($script:freezeAt -ge 0) { "$cWarn[boşluk] çöz$RS" } else { "$cFaint[boşluk]$RS$cMuted dondur$RS" }
    $kM = if ($script:showTok) { "$cAccent[m]$RS$cText maliyet: $(Fmt $st.inTok) giriş · $(Fmt $st.outTok) çıkış$RS" } else { "$cFaint[m]$RS$cMuted maliyet$RS" }
    $extra = "  $kM" + $(if ($st.start -and ((Get-Date) - $st.start).TotalSeconds -lt 60 -and $w -ge 120) { "$cFrame  ─  $RS$cFaint yalnız izler; sekmeyi kapatmak işçiyi durdurmaz$RS" } else { '' })
    $L.Add((HLine $w "$kT  $kE  $kP  $cFaint[q]$RS$cMuted çık$RS$extra" '╰' '╯'))
    $sb = New-Object Text.StringBuilder
    [void]$sb.Append("$ESC[H")
    foreach ($ln in $L) { [void]$sb.Append($ln).Append("$RS$ESC[K`n") }
    [void]$sb.Append("$ESC[J")
    $kare = $sb.ToString(); if ($kare -ne $script:lastFrame) { $script:lastFrame = $kare; [Console]::Write($kare) }
}


# ======================= KOSU PANOSU (-Kart verilmezse) =======================
# Tek ekranda butun kosu (design_reviewer spesifikasyonu 2026-10-13): rozet, asama hatti, isci tablosu,
# BUTUNLESTIRME | DOGRULAMA, SIRADA (ne yapmali + neden). Yalniz okur; yukseklik icerige gore.
function IsciDurumTr([string]$d) { switch ($d) { 'planned' { 'bekliyor' } 'queued' { 'sırada' } 'spawning' { 'açılıyor' } 'running' { 'çalışıyor' } 'finished' { 'bitti' } 'collected' { 'toplandı' } 'integrated' { 'birleşti' } 'failed' { 'başarısız' } 'timed_out' { 'zaman aşımı' } 'scope_violation' { 'kapsam ihlali' } 'rejected_content' { 'içerik reddi' } 'conflict' { 'çakışma' } 'aborted' { 'iptal' } 'paused_limit' { 'limit' } default { $d } } }
function VerdictTr([string]$v) { switch ($v) { 'pass' { "$cOk✔ geçti$RS" } 'warn' { "$cWarn◐ uyarı$RS" } 'partial' { "$cWarn◐ kısmen$RS" } 'blocked' { "$cErr✖ engellendi$RS" } 'fail' { "$cErr✖ başarısız$RS" } '' { "$cFaint—$RS" } default { "$cErr✖ $v$RS" } } }
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
function RenderRun([int]$tick) {
    $w = $Host.UI.RawUI.WindowSize.Width; $h = $Host.UI.RawUI.WindowSize.Height
    if ($w -lt 80) { $w = 80 }
    $inner = $w - 4
    $rr = $null; try { $rr = Get-Content -LiteralPath $runRec -Raw -Encoding UTF8 | ConvertFrom-Json } catch { }
    $L = New-Object System.Collections.Generic.List[string]
    if (-not $rr) { $L.Add((HLine $w "$cTitle$BOLD$Run$RS" '╭' '╮')); $L.Add((Row "$cFaint koşu kaydı okunamadı$RS" $w)); $L.Add((HLine $w '' '╰' '╯')); [Console]::Write("$ESC[H" + ($L -join "$RS$ESC[K`n") + "$RS$ESC[K`n$ESC[J"); return }
    $ws = @($rr.workers); $st2 = [string]$rr.status
    $calisan = @($ws | Where-Object { $_.status -in @('queued', 'spawning', 'running') }).Count
    $bekleyen = @($ws | Where-Object { $_.status -in @('planned', 'paused_limit') }).Count
    $bitenS = $ws.Count - $calisan - $bekleyen
    $sorunlu = @($ws | Where-Object { $_.status -in @('failed', 'timed_out', 'scope_violation', 'rejected_content', 'conflict', 'aborted') }).Count
    $as = KosuAsamalar $rr
    $ig = $rr.integration; $v = $rr.verification
    $cakisma = @($(if ($ig) { $ig.conflicts } else { @() })).Count -gt 0
    $kontrolDustu = [bool]($ig -and -not $ig.ok -and -not $cakisma)
    $dogrulamaDustu = [bool]($v -and $v.verdict -and $v.verdict -notin @('pass', 'warn'))
    # rozet: calisan varsa CALISIYOR; cakisma; kontrol; dogrulama; onay bekliyor; bitti
    if ($st2 -eq 'aborted') { $badge = "$bgBad$BOLD ✖ İPTAL $RS"; $glyph = '✖' }
    elseif ($st2 -eq 'failed') { $badge = "$bgBad$BOLD ✖ BAŞARISIZ $RS"; $glyph = '✖' }
    elseif ($st2 -eq 'merged') { $badge = "$bgRun$BOLD ✔ ANA DALDA $RS"; $glyph = '✔' }
    elseif ($calisan -gt 0) { $glyph = $spin[$tick % $spin.Count]; $badge = "$bgPart$BOLD $glyph ÇALIŞIYOR $RS" }
    elseif ($cakisma) { $badge = "$bgBad$BOLD ✖ ÇAKIŞMA $RS"; $glyph = '✖' }
    elseif ($kontrolDustu) { $badge = "$bgBad$BOLD ✖ KONTROL DÜŞTÜ $RS"; $glyph = '✖' }
    elseif ($dogrulamaDustu) { $badge = "$bgBad$BOLD ✖ DOĞRULAMA $RS"; $glyph = '✖' }
    elseif ($st2 -eq 'verified') { $badge = "$bgRun$BOLD ✔ DOĞRULANDI $RS"; $glyph = '✔' }
    elseif ($st2 -eq 'planned') { $badge = "$bgWait$BOLD ◐ ONAY BEKLİYOR $RS"; $glyph = '◐' }
    elseif ($st2 -eq 'paused') { $badge = "$bgIdle$BOLD ◐ DURAKLADI $RS"; $glyph = '◐' }
    else { $badge = "$bgDone$BOLD ▶ ŞEF SIRASI $RS"; $glyph = '▶' }
    try { $Host.UI.RawUI.WindowTitle = "$glyph koşu $Run" } catch { }
    $clockLab = "$cFrame─ $cFaint$((Get-Date).ToString('HH:mm'))$RS$cFrame ─╮$RS"
    $titleLab = "$cTitle$BOLD$Run$RS$cFrame · $cMuted koşu panosu$RS$cFrame · $cMuted taban $($rr.baseBranch)$RS" + $(if ($rr.repoName) { "$cFrame · $cMuted$($rr.repoName)$RS" } else { '' })
    $L.Add((HLine ($w - 9) $titleLab '╭' '') + $clockLab)
    $onayS = if ($rr.approvals -and $rr.approvals.start) { ([DateTime]$rr.approvals.start.consumedAt).ToLocalTime().ToString('HH:mm') } else { '—' }
    $onayM = if ($rr.approvals -and $rr.approvals.merge) { ([DateTime]$rr.approvals.merge.consumedAt).ToLocalTime().ToString('HH:mm') } else { '—' }
    $t0 = $(if ($rr.startedAt) { ([DateTime]$rr.startedAt).ToLocalTime() } elseif ($rr.approvals -and $rr.approvals.start) { ([DateTime]$rr.approvals.start.consumedAt).ToLocalTime() } else { $null })
    $tSon = $null; foreach ($hh in @($rr.history)) { if ($hh.at) { $tSon = ([DateTime]$hh.at).ToLocalTime() } }
    $bittiMi = ($st2 -in @('merged', 'aborted', 'failed', 'verified'))
    $sure = if ($t0) { SureK $t0 $(if ($bittiMi) { $tSon } else { $null }) } else { '—' }
    $dosya = 0; $commits = 0; $tokIn = 0L; $tokOut = 0L; $tokC = 0L; $durs = @()
    foreach ($wk in $ws) {
        $dosya += @($wk.changedPaths).Count; if ($wk.commit) { $commits++ }
        if ($wk.usage) { $tokIn += [long]$wk.usage.input_tokens; $tokOut += [long]$wk.usage.output_tokens; $tokC += [long]$wk.usage.cached_input_tokens }
        if ($wk.startedAt -and $wk.finishedAt) { $durs += ([DateTime]$wk.finishedAt - [DateTime]$wk.startedAt).TotalSeconds }
    }
    $ortIsci = if ($durs.Count) { $o = ($durs | Measure-Object -Average).Average; DurS $o } else { '—' }
    $L.Add((Row "$badge   $cMuted süre$RS $cText$sure$RS   $cMuted başlatma$RS $cText$onayS$RS   $cMuted birleştirme$RS $cText$onayM$RS   $cMuted model$RS $cFaint$($rr.model)$RS" $w))
    $L.Add((Blank $w))
    # asama: ilerleme cubugu + hat
    $L.Add((HLine $w (Sec 'AŞAMA') '├' '┤'))
    $tamam = 0; foreach ($o2 in $as.Ok) { if ($o2) { $tamam++ } }
    $kirikVar = ($cakisma -or $kontrolDustu -or $dogrulamaDustu -or $st2 -in @('aborted', 'failed'))
    $barCol = if ($kirikVar) { $cErr } elseif ($tamam -eq 6) { $cOk } else { $cAccent }
    $barW = [Math]::Min(60, $inner - 22)
    $L.Add((Row "  $(MiniBar ($tamam / 6.0) $barW $barCol)  $cText$BOLD$tamam/6$RS $cMuted· $(Yuzde $tamam 6)$RS" $w))
    $adlar = @('plan', 'başlat', 'topla', 'bütünleştir', 'doğrula', 'ana dala')
    $segs = @()
    for ($i = 0; $i -lt 6; $i++) {
        $kirik = ($i -eq $as.Cur -and $kirikVar)
        if ($as.Ok[$i]) { $segs += "$cOk✔$RS $cMuted$($adlar[$i])$RS" }
        elseif ($kirik) { $segs += "$cErr$BOLD✖ $($adlar[$i])$RS" }
        elseif ($i -eq $as.Cur) { $segs += "$cAccent$BOLD▶ $($adlar[$i])$RS" }
        else { $segs += "$cFaint○ $($adlar[$i])$RS" }
    }
    $line = ''
    for ($i = 0; $i -lt 6; $i++) { $line += $segs[$i]; if ($i -lt 5) { $line += $(if ($as.Ok[$i]) { " $cOk━━━$RS " } else { " $cBarOff╌╌╌$RS " }) } }
    $L.Add((Row ("  " + $line) $w))
    $L.Add((Blank $w))
    # ozet kartlari (widget)
    $ckOk = 0; $ckN = 0; if ($ig) { foreach ($ck in @($ig.checks)) { $ckN++; if ($ck.status -eq 0) { $ckOk++ } } }
    $isciBar = MiniBar $(if ($ws.Count) { $bitenS / [double]$ws.Count } else { 0 }) 10 $(if ($sorunlu) { $cErr } elseif ($bitenS -eq $ws.Count) { $cOk } else { $cWarn })
    $kontrolL = if ($ig) { @("$(if ($ig.ok) { "$cOk$ckOk/$ckN geçti$RS" } else { "$cErr$ckOk/$ckN geçti$RS" })", $(if ($cakisma) { "$cErr$(@($ig.conflicts).Count) çakışan dosya$RS" } else { 'çakışma yok' })) } else { @("$cFaint bütünleştirme bekliyor$RS", "$(@($rr.checks).Count) kontrol planlı") }
    $dogrulaL = if ($v -and $v.verdict) { @((VerdictTr ([string]$v.verdict)), "test_verifier · $(if ($v.at) { ([DateTime]$v.at).ToLocalTime().ToString('HH:mm') } else { '' })") } else { @("$cFaint bekliyor$RS", 'bağımsız test_verifier') }
    $cards = @(
        @{ t = 'İŞÇİLER'; l = @(("$cText$bitenS/$($ws.Count)$RS bitti" + $(if ($calisan) { " · $cWarn$calisan$RS çalışıyor" } else { '' }) + $(if ($sorunlu) { " · $cErr$sorunlu$RS sorunlu" } else { '' })), ($isciBar + "  $cFaint$(Yuzde $bitenS $ws.Count)$RS")) },
        @{ t = 'JETON'; l = @("giriş $cText$(Fmt $tokIn)$RS · çıkış $cText$(Fmt $tokOut)$RS", "önbellek payı $(Yuzde $tokC $tokIn)") },
        @{ t = 'SÜRE'; l = @("koşu $cText$sure$RS", "işçi başına ort. $ortIsci") },
        @{ t = 'KONTROL'; l = $kontrolL },
        @{ t = 'DOĞRULAMA'; l = $dogrulaL },
        @{ t = 'DOSYA'; l = @("$cText$dosya$RS dosya değişti", "$commits teslim commit'i") }
    )
    foreach ($cl in @(Cards $cards $inner)) { $L.Add((Row $cl $w)) }
    $L.Add((Blank $w))
    # isci tablosu
    $L.Add((HLine $w (Sec 'İŞÇİLER') '├' '┤'))
    $dar = $inner -lt 104
    $rolW = if ($dar) { 16 } else { 22 }
    $hdr = "  $cAccent$(Pad 'TASK' 10) $(Pad 'ROL' $rolW) $(Pad 'DURUM' 14) $(Pad 'SÜRE' 12) $(Pad 'JETON' 11) $(Pad 'DOSYA' 6) $(Pad 'VERDICT' 11)" + $(if (-not $dar) { 'SON OLAY' } else { '' }) + $RS
    $L.Add((Row $hdr $w))
    foreach ($wk in $ws) {
        $d = [string]$wk.status
        $dc = switch ($d) { 'running' { $cWarn } 'spawning' { $cWarn } 'queued' { $cFaint } 'failed' { $cErr } 'timed_out' { $cErr } 'scope_violation' { $cErr } 'conflict' { $cErr } 'rejected_content' { $cErr } 'aborted' { $cMuted } 'planned' { $cFaint } default { $cOk } }
        $dm = switch ($d) { 'running' { "$($spin[$tick % $spin.Count]) " } 'spawning' { '▶ ' } 'finished' { '✔ ' } 'collected' { '✔ ' } 'integrated' { '✔ ' } 'failed' { '✖ ' } 'timed_out' { '✖ ' } 'scope_violation' { '✖ ' } 'rejected_content' { '✖ ' } 'conflict' { '✖ ' } 'aborted' { '✖ ' } default { '○ ' } }
        $ws0 = $(if ($wk.startedAt) { ([DateTime]$wk.startedAt).ToLocalTime() } else { $null })
        $wf = $(if ($wk.finishedAt) { ([DateTime]$wk.finishedAt).ToLocalTime() } else { $null })
        $wsure = if ($ws0) { SureK $ws0 $wf } else { '—' }
        $sonT = if ($wk.lastEventAt) { ([DateTime]$wk.lastEventAt).ToLocalTime() } else { $null }
        $son = if ($sonT) { if ($wf) { $sonT.ToString('HH:mm') } else { "$(SureK $sonT) önce" } } else { '—' }
        $sonCol = if (-not $wf -and $sonT -and ((Get-Date) - $sonT).TotalSeconds -gt 120 -and $d -eq 'running') { $cWarn } else { $cFaint }
        $jeton = if ($wk.usage -and $wk.usage.input_tokens) { "$(Fmt ([long]$wk.usage.input_tokens))/$(Fmt ([long]$wk.usage.output_tokens))" } else { '—' }
        $L.Add((Row ("  $cText$(Pad ([string]$wk.taskId) 10)$RS $cMuted$(Pad (RolTr ([string]$wk.role)) $rolW)$RS $dc$(Pad ($dm + (IsciDurumTr $d)) 14)$RS $cText$(Pad $wsure 12)$RS $cMuted$(Pad $jeton 11)$RS $cText$(Pad ([string]@($wk.changedPaths).Count) 6)$RS $(Pad (VerdictTr ([string]$wk.verdict)) 11)" + $(if (-not $dar) { "$sonCol$son$RS" } else { '' })) $w))
        if ($wk.failure) { $L.Add((Row "             $cErr↳ $(CutWord ((Clean ([string]$wk.failure)) -replace '\s+', ' ') ($inner - 16))$RS" $w)) }
    }
    $L.Add((Blank $w))
    # butunlestirme | dogrulama (iki sutun; darda alt alta)
    $leftW = if ($dar) { $inner } else { [int]($inner * 0.6) }
    $A = New-Object System.Collections.Generic.List[string]; $Bc = New-Object System.Collections.Generic.List[string]
    $A.Add((Sec 'BÜTÜNLEŞTİRME') + $(if ($rr.integrationBranch) { "  $cFaint$($rr.integrationBranch)$RS" } else { '' }))
    if ($ig) {
        $A.Add("  $(if ($ig.ok) { "$cOk✔ temiz$RS" } else { "$cErr✖ sorunlu$RS" })   $cMuted birleşen$RS $cText$(@($ig.merged).Count)$RS   $cMuted çakışma$RS $(if ($cakisma) { "$cErr$(@($ig.conflicts) -join ', ')$RS" } else { "$cFaint yok$RS" })")
        foreach ($ck in @($ig.checks)) { $m = if ($ck.status -eq 0) { "$cOk✔$RS" } else { "$cErr✖$RS" }; $ad = IsAdi ([string]$ck.command) 'test' (CheckKey ([string]$ck.command)) ''; $A.Add("    $m $cText$(Cut $ad ($leftW - 16))$RS$(if ($ck.status -ne 0) { "  $cErr rc $($ck.status)$RS" } else { '' })") }
    } else { $A.Add("  $cFaint henüz bütünleştirilmedi$RS"); foreach ($ck in @($rr.checks)) { $A.Add("    $cFaint○ $(Cut (IsAdi ([string]$ck) 'test' (CheckKey ([string]$ck)) '') ($leftW - 10))$RS") } }
    $Bc.Add((Sec 'DOĞRULAMA') + "  $cFaint bağımsız test_verifier$RS")
    if ($v -and $v.verdict) { $Bc.Add("  $(VerdictTr ([string]$v.verdict))   $cFaint$(if ($v.at) { ([DateTime]$v.at).ToLocalTime().ToString('HH:mm') } else { '' })$RS"); if ($v.reportId) { $Bc.Add("  $cFaint rapor: $($v.reportId)$RS") }; if ($v.failure) { $Bc.Add("  $cErr$(CutWord ((Clean ([string]$v.failure)) -replace '\s+', ' ') ($inner - $leftW - 8))$RS") } }
    else { $Bc.Add("  $cFaint henüz doğrulanmadı$RS"); $Bc.Add("  $cFaint bütünleştirmeden sonra koşar$RS") }
    $L.Add((HLine $w '' '├' '┤'))
    if ($dar) { foreach ($x in $A) { $L.Add((Row $x $w)) }; $L.Add((Blank $w)); foreach ($x in $Bc) { $L.Add((Row $x $w)) } }
    else { $n = [Math]::Max($A.Count, $Bc.Count); for ($i = 0; $i -lt $n; $i++) { $aa = if ($i -lt $A.Count) { $A[$i] } else { '' }; $bb = if ($i -lt $Bc.Count) { $Bc[$i] } else { '' }; $L.Add((Row (Cols $aa $bb $w $leftW) $w)) } }
    $L.Add((Blank $w))
    # SIRADA
    $id = [string]$rr.runId; $neden = ''
    $kismi = @($ws | Where-Object { $_.verdict -and $_.verdict -ne 'pass' }).Count
    if ($st2 -eq 'aborted') { $adim = "koşu iptal edildi · temizlik: beyin takim cleanup $id" }
    elseif ($st2 -eq 'failed') { $adim = "koşu başarısız · işçi panellerine bak · temizlik: beyin takim cleanup $id" }
    elseif ($st2 -eq 'merged') { $adim = 'bitti: ek adım yok'; $neden = 'ara dal senin dalında; kartlar için sohbete onayla <TASK>; push/PR ayrı karar' }
    elseif ($st2 -eq 'planned') { $adim = "sohbete yaz: baslat $id" }
    elseif ($calisan -gt 0) { $adim = "bekle: $calisan işçi çalışıyor"; $neden = 'bitince toplanır; işçi panelleri ayrı sekmede' }
    elseif ($st2 -in @('running', 'paused')) { $adim = "beyin takim collect $id"; $neden = 'işçiler bitti, çıktılar toplanmadı' }
    elseif ($cakisma) { $adim = "çakışmayı çöz: $(@($ig.conflicts) -join ', ')"; $neden = 'bütünleştirme çakıştı; düzeltip beyin takim integrate' }
    elseif ($kontrolDustu) { $dus = @($ig.checks | Where-Object { $_.status -ne 0 } | ForEach-Object { IsAdi ([string]$_.command) 'test' (CheckKey ([string]$_.command)) '' }); $adim = "kontrol başarısız: $($dus -join ', ')"; $neden = 'raporları oku; düzeltme koşusundan sonra beyin takim integrate' }
    elseif ($st2 -eq 'collected') { $adim = "beyin takim integrate $id" }
    elseif ($st2 -eq 'integrated') { $adim = "beyin takim verify $id" }
    elseif ($dogrulamaDustu) { $adim = "doğrulama geçmedi · raporu oku · beyin takim verify $id (yeniden)" }
    elseif ($st2 -eq 'verified') { $adim = "sohbete yaz: birlestir $id"; $neden = $(if ($v.verdict -eq 'warn') { 'uyarıyla doğrulandı; merge için --accept-warn' } else { 'doğrulandı; ana dala alma onayı' }) }
    else { $adim = "beyin takim status $id" }
    if ($kismi -gt 0 -and -not $neden) { $neden = "$kismi işçi kısmen bitti; önce raporları oku" }
    $L.Add((HLine $w '' '├' '┤'))
    $L.Add((Row "$cAccent$BOLD▌ SIRADA$RS   $cText$BOLD$adim$RS" $w))
    if ($neden) { $L.Add((Row "$cAccent▌$RS          $cMuted$neden$RS" $w)) }
    $L.Add((HLine $w "$cFaint[q]$RS$cMuted çık$RS$cFrame  ─  $RS$cFaint işçi paneli: beyin takim izle $Run <TASK>$RS" '╰' '╯'))
    $sb = New-Object Text.StringBuilder
    [void]$sb.Append("$ESC[H")
    foreach ($ln in $L) { [void]$sb.Append($ln).Append("$RS$ESC[K`n") }
    [void]$sb.Append("$ESC[J")
    $kare = $sb.ToString(); if ($kare -ne $script:lastFrame) { $script:lastFrame = $kare; [Console]::Write($kare) }
}

# kendini yenileme: bu dosya degisirse (ve cozumlenebiliyorsa) ayni konsolda yeni surumu baslat, kendini kapat
$selfPath = $PSCommandPath
$selfStamp = $(try { (Get-Item -LiteralPath $selfPath).LastWriteTimeUtc } catch { $null })
$selfAt = Get-Date
function SelfReloadIfChanged {
    if (-not $selfPath -or -not $selfStamp) { return $false }
    if (((Get-Date) - $script:selfAt).TotalSeconds -lt 5) { return $false }
    $script:selfAt = Get-Date
    try {
        $cur = (Get-Item -LiteralPath $selfPath).LastWriteTimeUtc
        if ($cur -le $selfStamp) { return $false }
        if (((Get-Date).ToUniversalTime() - $cur).TotalSeconds -lt 2) { return $false }   # yazim bitmemis olabilir
        $tok = $null; $errs = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($selfPath, [ref]$tok, [ref]$errs)
        if ($errs -and $errs.Count) { $script:selfStamp = $cur; return $false }
        return $true
    } catch { return $false }
}

Clear-Host
$tick = 0; $quit = $false
while ($true) {
    if (SelfReloadIfChanged) {
        try { [Console]::CursorVisible = $true } catch { }
        [Console]::Write("$ESC[H$ESC[J$cMuted izleyici yenileniyor (yeni sürüm)…$RS`n")
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $selfPath -Vault $Vault -Run $Run -Kart $Kart -Model $Model
        exit $LASTEXITCODE
    }
    if (-not $Kart) { try { RenderRun $tick } catch { } }
    else {
    ReadNew
    if (-not $replay -and -not $replayDividerAdded) { $replayDividerAdded = $true; if ($rows.Count -gt 0) { $rows.Add(@{ kind = 'divider'; ts = '' }) } }
    RefreshSide
    if ($rows.Count -gt 3000) { $rows.RemoveRange(0, $rows.Count - 2000) }
    try { Render $tick } catch { }
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
                default { }
            }
        }
    } catch { }
    if ($quit) { break }
    Start-Sleep -Milliseconds 500
}
try { [Console]::CursorVisible = $true } catch { }
Write-Host "$RS"
