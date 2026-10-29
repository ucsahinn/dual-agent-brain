# Isolated regression fixtures for the wave 3/4 motor contract (PS 5.1/Pester 3).
. (Join-Path $PSScriptRoot 'lib.ps1')

Describe 'R9: transcript memory accepts only conversational plain text' {
    It 'drops tool names, inputs, results, reasoning and system messages' {
        $lines = @(
            '{"type":"user","message":{"role":"user","content":[{"type":"text","text":"QUESTION"},{"type":"tool_result","content":"SECRET_RESULT"}]}}',
            '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"ANSWER"},{"type":"tool_use","name":"SECRET_TOOL","input":{"data":"SECRET_INPUT"}},{"type":"thinking","thinking":"SECRET_REASON"}]}}',
            '{"type":"system","message":{"role":"system","content":"SECRET_SYSTEM"}}'
        )
        $r = Convert-BeyinLinesToTurns -Lines $lines -Format claude
        ($r.Turns -join '|') | Should Be "USER: QUESTION|ASSISTANT: ANSWER"
    }
    It 'filters Codex system envelopes and tools through both full and tail readers' {
        $lines = @(
            '{"type":"response_item","payload":{"type":"message","role":"developer","content":[{"type":"input_text","text":"SECRET_SYSTEM"}]}}',
            '{"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"QUESTION"}]}}',
            '{"type":"response_item","payload":{"type":"function_call_output","output":"SECRET_TOOL_RESULT"}}',
            '{"type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"ANSWER"},{"type":"function_call","name":"SECRET_TOOL"}]}}'
        )
        $file = Join-Path $TestDrive 'codex-conversation.jsonl'
        [IO.File]::WriteAllText($file, (($lines -join "`n") + "`n"))
        $full = Read-BeyinTranscript -Path $file
        $tail = Read-BeyinTranscriptTail -Path $file
        ($full.Turns -join '|') | Should Be 'USER: QUESTION|ASSISTANT: ANSWER'
        ($tail.Turns -join '|') | Should Be 'USER: QUESTION|ASSISTANT: ANSWER'
    }
}

Describe 'B2/Y13: durable event deduplication and truthful receipts' {
    BeforeEach {
        $script:waveVault = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $script:wavePaths = Get-BeyinPaths -Vault $script:waveVault
    }
    It 'coalesces three retries of the same source/worker/state event' {
        $a = Add-BeyinHandoff -Paths $wavePaths -Metin 'worker finished' -Kime claude -FromAgent codex -FromWorker TASK-1 -Ref event-1 -GorunumYok
        $b = Add-BeyinHandoff -Paths $wavePaths -Metin 'worker finished' -Kime claude -FromAgent codex -FromWorker TASK-1 -Ref event-1 -GorunumYok
        $c = Add-BeyinHandoff -Paths $wavePaths -Metin 'worker finished' -Kime claude -FromAgent codex -FromWorker TASK-1 -Ref event-1 -GorunumYok
        $b.Id | Should Be $a.Id
        $c.Id | Should Be $a.Id
        (Get-BeyinHandoff -Paths $wavePaths -Id $a.Id).occurrences | Should Be 3
        @(Get-BeyinHandoffListe -Paths $wavePaths).Count | Should Be 1
    }
    It 'reads old records and persists all six A2A states without confusing display with read' {
        $a = Add-BeyinHandoff -Paths $wavePaths -Metin 'question' -Kime claude -GorunumYok
        (Get-BeyinHandoffState (Get-BeyinHandoff -Paths $wavePaths -Id $a.Id)) | Should Be submitted
        foreach ($state in @('working','input-required','completed','failed','canceled')) {
            $event = Add-BeyinHandoff -Paths $wavePaths -Metin 'state fixture' -Kime claude -GorunumYok
            (Set-BeyinHandoffState -Paths $wavePaths -Id $event.Id -State $state -Agent claude) | Should Be $true
            (Get-BeyinHandoffState (Get-BeyinHandoff -Paths $wavePaths -Id $event.Id)) | Should Be $state
        }
        $legacy = [pscustomobject]@{ status = 'tamam' }
        (Get-BeyinHandoffState $legacy) | Should Be completed
        $null = Read-BeyinHandoff -Paths $wavePaths -Id $a.Id -Agent claude
        $null = Read-BeyinHandoff -Paths $wavePaths -Id $a.Id -Agent claude
        @(Read-BeyinMakbuz -Paths $wavePaths -Gun 1 | Where-Object { $_.outcome -eq 'OKUNDU' }).Count | Should Be 1
    }
    It 'rejects non-recipient state changes and late updates after completion' {
        $a = Add-BeyinHandoff -Paths $wavePaths -Metin 'protected state' -Kime claude -GorunumYok
        (Set-BeyinHandoffState -Paths $wavePaths -Id $a.Id -State completed -Agent codex) | Should Be $false
        (Set-BeyinHandoffState -Paths $wavePaths -Id $a.Id -State completed -Agent claude) | Should Be $true
        (Set-BeyinHandoffState -Paths $wavePaths -Id $a.Id -State working -Agent claude) | Should Be $false
        (Get-BeyinHandoffState (Get-BeyinHandoff -Paths $wavePaths -Id $a.Id)) | Should Be completed
    }
}

Describe 'D2/J2/I7: persistent session chain and project report root' {
    BeforeEach {
        $script:historyPaths = Get-BeyinPaths -Vault (Join-Path $TestDrive ('history-' + [guid]::NewGuid().ToString('N')))
        $script:projectRoot = Join-Path $TestDrive ('project-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path $projectRoot | Out-Null
    }
    It 'retains open resume and close events in order' {
        foreach ($event in @('open','resume','close')) {
            Add-BeyinSessionHistory -Paths $historyPaths -Session 'session-1' -Project $projectRoot -Task 'TASK-1' -Event $event -Agent codex
        }
        $chain = @(Get-BeyinSessionHistory -Paths $historyPaths -Task 'TASK-1')
        ($chain.olay -join ',') | Should Be 'open,resume,close'
        @(Get-BeyinSessionHistory -Paths $historyPaths -Task 'TASK-OTHER').Count | Should Be 0
    }
    It 'journals channel lifecycle and imports its validated report without writing channel files' {
        $dir = Join-Path $historyPaths.ScrState 'codex-kanal'
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        $id = 'CK-' + ('a' * 32)
        $file = Join-Path $dir ($id + '.json')
        $record = @{Owner='beyin-codex-kanal-v1';Id=$id;Engine='codex';Project=$projectRoot;SessionId='thread-1';TaskKey='work-1';Status='ready';Turn=0;HandoffValid=$false;Answer=''}
        $before = @{}
        foreach ($step in @('ready','completed','closed')) {
            $record.Status = $step
            if ($step -eq 'completed') { $record.Turn=1; $record.HandoffValid=$true; $record.Answer="Outcome: channel ready`nEvidence: synthetic" }
            $record | ConvertTo-Json | Set-Content -Encoding UTF8 -LiteralPath $file
            $text = [IO.File]::ReadAllText($file)
            Sync-BeyinChannelHistory -Paths $historyPaths -Before $before -Engine codex -Action $(if ($step -eq 'ready') { 'ac' } elseif ($step -eq 'closed') { 'kapat' } else { 'sor' })
            [IO.File]::ReadAllText($file) | Should Be $text
            $before = Get-BeyinChannelSnapshot -Paths $historyPaths
        }
        $events = @(Get-BeyinSessionHistory -Paths $historyPaths -Task work-1)
        ($events.olay -join ',') | Should Be 'open,resume,complete,close'
        @(Get-BeyinProjectReports -Project $projectRoot).Count | Should Be 1
    }
    It 'stores reports under one root, indexes them, rejects traversal and keeps plan text out of context' {
        $r = Write-BeyinProjectReport -Project $projectRoot -Task 'TASK-1' -Text "Outcome: ready`nEvidence: fixture"
        $r | Should Match '[\\/]\.beyin[\\/]raporlar[\\/]'
        @(Get-BeyinProjectReports -Project $projectRoot).Count | Should Be 1
        { Write-BeyinProjectReport -Project $projectRoot -Task '../escape' -Text 'x' } | Should Throw
        $pointer = Get-BeyinRunPointer -Paths $historyPaths -Run 'R-test' -Task 'TASK-1'
        $pointer | Should Match 'plan.md'
        $pointer | Should Not Match 'SECRET_PLAN_BODY'
    }
    It 'materializes a run plan and notes, preserving notes on continuation' {
        $run = [pscustomobject]@{runId='R-fixture'; workers=@([pscustomobject]@{taskId='TASK-1'; role='qa_lead'}); planFile='' }
        Initialize-BeyinRunNotes -Paths $historyPaths -Run $run
        $notes = Join-Path $historyPaths.TeamRuns 'R-fixture/TASK-1/notes.md'
        Test-Path -LiteralPath $notes | Should Be $true
        Set-Content -LiteralPath $notes -Value 'existing notes'
        Initialize-BeyinRunNotes -Paths $historyPaths -Run $run
        (Get-Content -LiteralPath $notes -Raw).Trim() | Should Be 'existing notes'
    }
    It 'indexes Outcome headings from actual team-run Markdown reports' {
        $null = Write-BeyinProjectReport -Project $projectRoot -Task TASK-2 -Text "## Outcome`nteam result`n`n## Evidence`nfixture"
        @(Get-BeyinProjectReports -Project $projectRoot)[0].Outcome | Should Be 'team result'
    }
    It 'rejects a report source routed through a directory junction' {
        $valid = Join-Path $projectRoot 'valid.md'; Set-Content -LiteralPath $valid -Value 'fixture'
        (Resolve-BeyinContainedFile -Root $projectRoot -Path $valid) | Should Be $valid
        $outside = Join-Path $TestDrive 'outside-project'
        New-Item -ItemType Directory -Force -Path $outside | Out-Null
        $file = Join-Path $outside 'evidence.md'; Set-Content -LiteralPath $file -Value 'fixture'
        $link = Join-Path $projectRoot 'linked'
        New-Item -ItemType Junction -Path $link -Target $outside | Out-Null
        { Resolve-BeyinContainedFile -Root $projectRoot -Path (Join-Path $link 'evidence.md') } | Should Throw
        { Resolve-BeyinContainedFile -Root $projectRoot -Path $file } | Should Throw
    }
}

Describe 'Bekci: read-only node_repl process ownership accounting' {
    It 'counts excess instances and detects missing or reused parents without kill commands' {
        $now = Get-Date
        $rows = @(
            [pscustomobject]@{Name='codex.exe';ProcessId=10;ParentProcessId=1;CreationDate=$now},
            [pscustomobject]@{Name='node_repl.exe';ProcessId=11;ParentProcessId=10;CreationDate=$now.AddMinutes(-1)},
            [pscustomobject]@{Name='node_repl.exe';ProcessId=12;ParentProcessId=999;CreationDate=$now},
            [pscustomobject]@{Name='node_repl.exe';ProcessId=13;ParentProcessId=10;CreationDate=$now.AddMinutes(1)}
        )
        $r = Get-BeyinNodeReplReport -Processes $rows -Limit 2
        $r.Count | Should Be 3
        $r.OrphanCount | Should Be 2
        $r.Excess | Should Be $true
        ($r | ConvertTo-Json -Depth 5) | Should Not Match 'taskkill|Stop-Process'
    }
}

Describe 'Merkez read-only resource probes' {
    Mock Get-CimInstance { [pscustomobject]@{TotalVirtualMemorySize=64000000;FreeVirtualMemory=32000000;FreePhysicalMemory=8000000} }
    It 'does not write resource or capacity caches in monitor mode' {
        $p = Get-BeyinPaths -Vault (Join-Path $TestDrive 'readonly')
        New-Item -ItemType Directory -Force -Path $p.ScrState | Out-Null
        $null = Get-BeyinKaynakOzeti -Paths $p -SaltOkunur
        @(Get-ChildItem -LiteralPath $p.ScrState -File).Count | Should Be 0
    }
}

Describe 'F2: reciprocal rank fusion and heading bounded chunks' {
    It 'fuses the union of vector and keyword rankings, counting each document once per list' {
        $a = [pscustomobject]@{Item=[pscustomobject]@{dosya='a.md'};Skor=9;Tutan=@()}
        $b = [pscustomobject]@{Item=[pscustomobject]@{dosya='b.md'};Skor=8;Tutan=@()}
        $c = [pscustomobject]@{Item=[pscustomobject]@{dosya='c.md'};Skor=7;Tutan=@()}
        $r = @(Merge-BeyinRanks -Vector @($a,$b,$b) -Keyword @($b,$c) -K 60)
        $r.Count | Should Be 3
        $r[0].Item.dosya | Should Be 'b.md'
    }
    It 'never combines separate headings or drops the tail of a long section' {
        $chunks = @(Split-BeyinHeadingChunks -Text ("# A`nalpha`n## B`n" + ('beta ' * 30)) -MaxChars 48)
        $chunks.Count | Should BeGreaterThan 2
        @($chunks | Where-Object { $_ -match 'alpha' -and $_ -match 'beta' }).Count | Should Be 0
        ($chunks -join "`n") | Should Match 'beta'
        @($chunks | Where-Object { $_.Length -gt 48 }).Count | Should Be 0
    }
    It 'retrieves text below later headings through the keyword index' {
        $p = Get-BeyinPaths -Vault (Join-Path $TestDrive 'chunks')
        $dir = Join-Path $p.Compiled 'concepts'
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        Set-Content -Encoding UTF8 -LiteralPath (Join-Path $dir 'late.md') -Value ("# Start`nintro text`n" + ("filler`n" * 50) + "## Later`nquasar nebula")
        $r = @(Find-BeyinRelevantConcepts -Paths $p -Query 'quasar nebula')
        $r.Count | Should Be 1
        $r[0].Item.dosya | Should Be 'late.md'
    }
}
