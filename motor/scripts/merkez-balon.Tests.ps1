# Pester 3.4: Invoke-Pester -Script .\merkez-balon.Tests.ps1
# Butun fikstur dosyalari testin olusturdugu gecici klasorde; gercek transkriptlere dokunulmaz.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here 'merkez-balon.ps1')

$script:tmp = Join-Path ([IO.Path]::GetTempPath()) ('merkez-balon-test-' + [guid]::NewGuid().ToString('N'))
$script:eskiClaude = $env:CLAUDE_CONFIG_DIR
$script:eskiCodex = $env:CODEX_HOME
$env:CLAUDE_CONFIG_DIR = Join-Path $script:tmp 'claude'
$env:CODEX_HOME = Join-Path $script:tmp 'codex'
$script:claudeProje = Join-Path $env:CLAUDE_CONFIG_DIR 'projects\C--fikstur-proje'
$script:codexGun = Join-Path $env:CODEX_HOME ('sessions\{0:yyyy}\{0:MM}\{0:dd}' -f (Get-Date))
New-Item -ItemType Directory -Force -Path $script:claudeProje, $script:codexGun | Out-Null

$utf8 = New-Object Text.UTF8Encoding($false)
function Add-Satir([string]$Yol, [string[]]$Satirlar) {
    [IO.File]::AppendAllText($Yol, (($Satirlar -join "`n") + "`n"), $utf8)
    # mtime cozunurlugu: ayni boyda yazimlar icin bile degisiklik gorulsun
    (Get-Item -LiteralPath $Yol).LastWriteTimeUtc = (Get-Date).ToUniversalTime().AddSeconds((Get-Random -Minimum 1 -Maximum 100000))
}
function J($o) { return ($o | ConvertTo-Json -Compress -Depth 10) }
$ts = '2026-10-15T04:43:19.422Z'

function C-Arac([string]$Ad, $Girdi) { J @{ type = 'assistant'; isSidechain = $false; timestamp = $ts; message = @{ role = 'assistant'; stop_reason = 'tool_use'; content = @(@{ type = 'tool_use'; id = 'x'; name = $Ad; input = $Girdi }) } } }
function C-Yazi([string]$T, [string]$Stop = $null) { J @{ type = 'assistant'; isSidechain = $false; timestamp = $ts; message = @{ role = 'assistant'; stop_reason = $Stop; content = @(@{ type = 'text'; text = $T }) } } }
function C-Dusun { J @{ type = 'assistant'; isSidechain = $false; timestamp = $ts; message = @{ role = 'assistant'; content = @(@{ type = 'thinking'; thinking = 'gizli' }) } } }
function C-Sonuc { J @{ type = 'user'; isSidechain = $false; timestamp = $ts; message = @{ role = 'user'; content = @(@{ type = 'tool_result'; tool_use_id = 'x'; content = 'cikti' }) } } }
function C-Istem([string]$T) { J @{ type = 'user'; isSidechain = $false; timestamp = $ts; message = @{ role = 'user'; content = $T } } }

function X-Rec([string]$Tip, $Payload) { J @{ timestamp = $ts; type = $Tip; payload = $Payload } }

Describe 'Get-MerkezEtkinlik - Claude' {
    $id = 'aaaaaaaa-1111-2222-3333-444444444444'
    $yol = Join-Path $script:claudeProje "$id.jsonl"
    Clear-MerkezOnbellek

    It 'transkript yoksa Ok=false, Tur=yok' {
        $r = Get-MerkezEtkinlik -Ajan claude -OturumId 'bbbbbbbb-0000-0000-0000-000000000000'
        $r.Ok | Should Be $false
        $r.Tur | Should Be 'yok'
        $r.Zaman | Should Be $null
    }
    It 'yol karakteri iceren kimligi reddeder' {
        (Get-MerkezEtkinlik -Ajan claude -OturumId '..\..\x').Ok | Should Be $false
    }
    It 'Bash araci: komut ilk satiri' {
        Add-Satir $yol @('{"type":"summary"}', '{bozuk json', (C-Istem 'test calistir'), (C-Arac 'Bash' @{ command = "npm test`nsecond line" }), (C-Sonuc), '{"type":"attachment"}')
        $r = Get-MerkezEtkinlik -Ajan claude -OturumId $id -Cwd 'C:\fikstur\proje'
        $r.Ok | Should Be $true
        $r.Metin | Should Be '▸ Bash: npm test'
        $r.Tur | Should Be 'arac'
        $r.Zaman | Should Not BeNullOrEmpty
        ($r.Zaman -is [DateTime]) | Should Be $true
    }
    It 'Cwd verilmeden de proje klasorunu tarayip bulur' {
        Clear-MerkezOnbellek
        (Get-MerkezEtkinlik -Ajan claude -OturumId $id).Metin | Should Be '▸ Bash: npm test'
    }
    It 'onbellek: degismeyen dosya yeniden ayristirilmaz' {
        $once = Get-MerkezAyristirmaSayisi
        $r = Get-MerkezEtkinlik -Ajan claude -OturumId $id
        $r.Metin | Should Be '▸ Bash: npm test'
        (Get-MerkezAyristirmaSayisi) | Should Be $once
        Add-Satir $yol @((C-Arac 'Edit' @{ file_path = 'C:\x\motor\team-run.mjs'; old_string = 'a'; new_string = 'b' }))
        (Get-MerkezEtkinlik -Ajan claude -OturumId $id).Metin | Should Be '▸ Edit: team-run.mjs'
        (Get-MerkezAyristirmaSayisi) | Should Be ($once + 1)
    }
    It 'Read araci dosya adini gosterir' {
        Add-Satir $yol @((C-Arac 'Read' @{ file_path = ('X:/ornek/' + 'Beyin/motor/hooks/lib.ps1') }), (C-Sonuc))
        (Get-MerkezEtkinlik -Ajan claude -OturumId $id).Metin | Should Be '▸ Read: lib.ps1'
    }
    It 'dusunce bloku' {
        Add-Satir $yol @((C-Dusun))
        $r = Get-MerkezEtkinlik -Ajan claude -OturumId $id
        $r.Metin | Should Be '… düşünüyor'
        $r.Tur | Should Be 'dusunce'
    }
    It 'asistan metni: tek satir, 400 karakter kesimi' {
        Add-Satir $yol @((C-Yazi ("Ilk satir burada`nikinci satir " + ('uzun kelime ' * 50))))
        $r = Get-MerkezEtkinlik -Ajan claude -OturumId $id
        $r.Tur | Should Be 'yazi'
        $r.Metin | Should Match '^✎ Ilk satir burada ikinci satir'
        $r.Metin.Length | Should Be 400
        $r.Metin | Should Match '…$'
        $r.Metin | Should Not Match "[`r`n]"
    }
    It 'end_turn metni Tur=bekliyor' {
        Add-Satir $yol @((C-Yazi 'Bitti.' 'end_turn'))
        $r = Get-MerkezEtkinlik -Ajan claude -OturumId $id
        $r.Metin | Should Be '✎ Bitti.'
        $r.Tur | Should Be 'bekliyor'
    }
    It 'yeni kullanici istemi -> dusunce' {
        Add-Satir $yol @((C-Istem 'devam et'))
        (Get-MerkezEtkinlik -Ajan claude -OturumId $id).Tur | Should Be 'dusunce'
    }
    It 'sir maskeleme: token=, Bearer, uzun hex, password' {
        $sahteBaslik = ('Author' + 'ization: ' + 'Bea' + 'rer ' + 'Zx9abcdefghijk123')   # parcali: sir tarayicisi sahte degeri gercek sanmasin
        Add-Satir $yol @((C-Arac 'Bash' @{ command = ('curl -H "' + $sahteBaslik + '" "https://h/?' + 'tok' + 'en=S3CRETVALUE"') }))
        $r = Get-MerkezEtkinlik -Ajan claude -OturumId $id
        $r.Metin | Should Not Match 'Zx9abcdefghijk123'
        $r.Metin | Should Not Match 'S3CRETVALUE'
        $r.Metin | Should Match '\*\*\*'
        Add-Satir $yol @((C-Yazi 'hash 0123456789abcdef0123456789abcdef01234567 ok'))
        (Get-MerkezEtkinlik -Ajan claude -OturumId $id).Metin | Should Be '✎ hash *** ok'
        Add-Satir $yol @((C-Yazi ('set pass' + 'word hunter2 and ke' + 'y=abc123')))
        $m = (Get-MerkezEtkinlik -Ajan claude -OturumId $id).Metin
        $m | Should Not Match 'hunter2'
        $m | Should Not Match 'abc123'
        Add-Satir $yol @((C-Yazi 'blob QWxhZGRpbjpvcGVuIHNlc2FtZTEyMzQ1Njc4OTAxMjM0NTY= end'))
        (Get-MerkezEtkinlik -Ajan claude -OturumId $id).Metin | Should Be '✎ blob *** end'
    }
    It 'maskeleme yollari ve kebab adlari bozmaz' {
        (Format-MerkezMetin 'motor/scripts/merkez-balon-test-fixture-2026.ps1') | Should Be 'motor/scripts/merkez-balon-test-fixture-2026.ps1'
    }
    It 'yan zincir (sidechain) kayitlari yok sayilir' {
        $side = (C-Arac 'Bash' @{ command = 'gizli yan' }) -replace '"isSidechain":false', '"isSidechain":true'
        Add-Satir $yol @((C-Arac 'Grep' @{ pattern = 'Get-Beyin' }), $side)
        (Get-MerkezEtkinlik -Ajan claude -OturumId $id).Metin | Should Be '▸ Grep: Get-Beyin'
    }
    It '64 KB kuyrukta anlamli kayit yoksa daha genis kuyruga bakar' {
        Add-Satir $yol @((C-Arac 'Glob' @{ pattern = '**/*.ps1' }), (J @{ type = 'attachment'; pad = ('x' * 90000) }))
        (Get-MerkezEtkinlik -Ajan claude -OturumId $id).Metin | Should Be '▸ Glob: **/*.ps1'
    }
}

Describe 'Get-MerkezEtkinlik - Codex' {
    $id = '01a00000-1c77-75a1-aaa5-47a8849e2664'
    $yol = Join-Path $script:codexGun "rollout-2026-10-15T07-00-00-$id.jsonl"
    Clear-MerkezOnbellek

    It 'transkript yoksa Ok=false' {
        $r = Get-MerkezEtkinlik -Ajan codex -OturumId '01a00000-0000-0000-0000-000000000000'
        $r.Ok | Should Be $false
        $r.Tur | Should Be 'yok'
    }
    It 'kod modu exec: exec_command komutu' {
        Add-Satir $yol @(
            (X-Rec 'session_meta' @{ id = $id }),
            (X-Rec 'response_item' @{ type = 'message'; role = 'user'; content = @(@{ type = 'input_text'; text = '<environment_context>x</environment_context>' }) }),
            (X-Rec 'response_item' @{ type = 'message'; role = 'user'; content = @(@{ type = 'input_text'; text = 'testleri kos' }) }),
            (X-Rec 'response_item' @{ type = 'reasoning'; summary = @(); encrypted_content = 'zzz' }),
            (X-Rec 'response_item' @{ type = 'custom_tool_call'; name = 'exec'; call_id = 'c1'; input = 'const r = await tools.exec_command({cmd:"npm test --silent", workdir:"C:/x"}); text(r)' }),
            (X-Rec 'response_item' @{ type = 'custom_tool_call_output'; call_id = 'c1'; output = 'ok' }),
            '{bozuk',
            '{"type":"bilinmeyen","payload":{"type":"x"}}',
            (X-Rec 'token_usage_record' @{ a = 1 }),
            (X-Rec 'event_msg' @{ type = 'token_count' })
        )
        $r = Get-MerkezEtkinlik -Ajan codex -OturumId $id
        $r.Ok | Should Be $true
        $r.Metin | Should Be '▸ Shell: npm test --silent'
        $r.Tur | Should Be 'arac'
        ($r.Zaman -is [DateTime]) | Should Be $true
    }
    It 'onbellek isabeti' {
        $once = Get-MerkezAyristirmaSayisi
        (Get-MerkezEtkinlik -Ajan codex -OturumId $id).Metin | Should Be '▸ Shell: npm test --silent'
        (Get-MerkezAyristirmaSayisi) | Should Be $once
    }
    It 'apply_patch (dogrudan ve kod modu)' {
        Add-Satir $yol @((X-Rec 'response_item' @{ type = 'custom_tool_call'; name = 'apply_patch'; input = "*** Begin Patch`n*** Update File: motor/scripts/team-run.mjs`n@@`n-a`n+b`n*** End Patch" }))
        (Get-MerkezEtkinlik -Ajan codex -OturumId $id).Metin | Should Be '▸ Edit: team-run.mjs'
        Add-Satir $yol @((X-Rec 'response_item' @{ type = 'custom_tool_call'; name = 'exec'; input = 'await tools.apply_patch({patch:"*** Begin Patch\n*** Add File: C:/x/lib.ps1\n+x\n*** End Patch"})' }))
        (Get-MerkezEtkinlik -Ajan codex -OturumId $id).Metin | Should Be '▸ Edit: lib.ps1'
    }
    It 'eski function_call shell (komut dizisi)' {
        Add-Satir $yol @((X-Rec 'response_item' @{ type = 'function_call'; name = 'shell'; arguments = (J @{ command = @('powershell', '-Command', 'Get-ChildItem motor') }) }))
        (Get-MerkezEtkinlik -Ajan codex -OturumId $id).Metin | Should Be '▸ Shell: Get-ChildItem motor'
    }
    It 'reasoning -> dusunce' {
        Add-Satir $yol @((X-Rec 'response_item' @{ type = 'reasoning'; summary = @(@{ type = 'summary_text'; text = 'plan' }) }))
        $r = Get-MerkezEtkinlik -Ajan codex -OturumId $id
        $r.Metin | Should Be '… düşünüyor'
        $r.Tur | Should Be 'dusunce'
    }
    It 'asistan mesaji -> yazi, kesim ve tek satir' {
        Add-Satir $yol @((X-Rec 'response_item' @{ type = 'message'; role = 'assistant'; phase = 'commentary'; content = @(@{ type = 'output_text'; text = ("Kontrol ediyorum`n" + ('a' * 500)) }) }))
        $r = Get-MerkezEtkinlik -Ajan codex -OturumId $id
        $r.Tur | Should Be 'yazi'
        $r.Metin | Should Match '^✎ Kontrol ediyorum a+…$'
        $r.Metin.Length | Should Be 400
    }
    It 'task_complete -> bekliyor, maskeli son mesaj' {
        Add-Satir $yol @((X-Rec 'event_msg' @{ type = 'task_complete'; last_agent_message = ('Tamam api_' + 'key=s' + 'k-abcdefghijklmnopqrstu yazildi') }))
        $r = Get-MerkezEtkinlik -Ajan codex -OturumId $id
        $r.Tur | Should Be 'bekliyor'
        $r.Metin | Should Match '^✎ Tamam'
        $r.Metin | Should Not Match 'abcdefghijklmnop'
    }
    It 'eski gun klasorundeki oturumu agac taramasiyla bulur' {
        $eskiId = '01a99999-1c77-75a1-aaa5-47a8849e2664'
        $eskiKl = Join-Path $env:CODEX_HOME 'sessions\2020\01\02'
        New-Item -ItemType Directory -Force -Path $eskiKl | Out-Null
        $ey = Join-Path $eskiKl "rollout-2020-01-02T00-00-00-$eskiId.jsonl"
        Add-Satir $ey @((X-Rec 'response_item' @{ type = 'web_search_call'; action = @{ type = 'search'; query = 'pester 3.4' } }))
        (Get-MerkezEtkinlik -Ajan codex -OturumId $eskiId).Metin | Should Be '▸ Web: pester 3.4'
    }
    It 'temizlik' {
        $env:CLAUDE_CONFIG_DIR = $script:eskiClaude
        $env:CODEX_HOME = $script:eskiCodex
        Clear-MerkezOnbellek
        Remove-Item -LiteralPath $script:tmp -Recurse -Force
        (Test-Path -LiteralPath $script:tmp) | Should Be $false
    }
}
