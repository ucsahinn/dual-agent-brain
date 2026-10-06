# maliyet.Tests.ps1 - beyin maliyet (BB1, 2026-10-06): tekillestirme, artimli
# ofset, Codex kumulatif fark, taninmayan bicim ve dolar hesabi. Gercek
# transkriptlere DOKUNMAZ: CLAUDE_CONFIG_DIR / CODEX_HOME gecici klasore cevrilir.

$vault = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$powershell = Join-Path $PSHOME 'powershell.exe'
. (Join-Path $vault 'motor\hooks\lib.ps1')

function New-MaliyetOrtami {
    $kok = Join-Path $env:TEMP ('beyin-mal-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    $tv = Join-Path $kok 'vault'
    New-Item -ItemType Directory -Force -Path (Join-Path $tv 'motor\hooks'), (Join-Path $tv 'motor\scripts\.state'), (Join-Path $kok 'claude\projects\C--proje'), (Join-Path $kok 'codex\sessions\2026\10\06') | Out-Null
    Copy-Item (Join-Path $vault 'motor\hooks\lib.ps1') (Join-Path $tv 'motor\hooks\lib.ps1')
    Copy-Item (Join-Path $vault 'motor\scripts\maliyet.ps1') (Join-Path $tv 'motor\scripts\maliyet.ps1')
    Copy-Item (Join-Path $vault 'motor\scripts\fiyat.json') (Join-Path $tv 'motor\scripts\fiyat.json')
    Set-Content -Path (Join-Path $tv '.beyin-version') -Value '1.0.0'
    return @{ Kok = $kok; Vault = $tv; Claude = (Join-Path $kok 'claude\projects\C--proje\oturum-1.jsonl'); Codex = (Join-Path $kok 'codex\sessions\2026\10\06\rollout-2026-10-06T01-00-00-test.jsonl') }
}
function Satir-Claude([string]$Id, [int]$In, [int]$Out, [int]$Cw1h, [int]$Cr) {
    $ts = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
    '{"parentUuid":"x","cwd":"C:\\Users\\t\\proje","sessionId":"oturum-1","message":{"model":"claude-opus-5-5","id":"' + $Id + '","type":"message","role":"assistant","content":[{"type":"text","text":"tamam"}],"usage":{"input_tokens":' + $In + ',"cache_creation_input_tokens":' + $Cw1h + ',"cache_read_input_tokens":' + $Cr + ',"output_tokens":' + $Out + ',"cache_creation":{"ephemeral_1h_input_tokens":' + $Cw1h + ',"ephemeral_5m_input_tokens":0},"speed":"standard"}},"type":"assistant","uuid":"u","timestamp":"' + $ts + '"}'
}
function Satir-Codex([int]$In, [int]$Cached, [int]$Out) {
    $ts = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
    '{"timestamp":"' + $ts + '","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":' + $In + ',"cached_input_tokens":' + $Cached + ',"output_tokens":' + $Out + ',"total_tokens":0}}}}'
}
function Kos([hashtable]$O) {
    $env:CLAUDE_CONFIG_DIR = Join-Path $O.Kok 'claude'; $env:CODEX_HOME = Join-Path $O.Kok 'codex'
    try { $j = & $powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $O.Vault 'motor\scripts\maliyet.ps1') -Vault $O.Vault -Gun 2 -Json 2>&1 | Out-String }
    finally { $env:CLAUDE_CONFIG_DIR = $null; $env:CODEX_HOME = $null }
    return ($j.Trim() -split "`n" | Select-Object -Last 1 | ConvertFrom-Json)
}
function Yaz([string]$Yol, [string[]]$Satirlar) { [IO.File]::AppendAllText($Yol, (($Satirlar -join "`n") + "`n"), (New-Object System.Text.UTF8Encoding($false))) }

Describe 'beyin maliyet (BB1)' {
    It 'Claude: ayni message.id tek sayilir, dolar dogru, ikinci kosu yalniz yeni satiri sayar' {
        $o = New-MaliyetOrtami
        try {
            $baslik = '{"type":"session_meta","cwd":"C:\\Users\\t\\proje","session_id":"cx-1"}'
            Yaz $o.Codex @($baslik, (Satir-Codex 1000 400 50))
            # ayni yanitin iki parcasi + ikinci yanit
            Yaz $o.Claude @((Satir-Claude 'msg_A' 1000 1000 10000 100000), (Satir-Claude 'msg_A' 1000 1000 10000 100000), (Satir-Claude 'msg_B' 0 0 0 0))
            $r1 = Kos $o
            Yaz $o.Claude @((Satir-Claude 'msg_C' 1000 0 0 0))
            Yaz $o.Codex @((Satir-Codex 3000 1400 150))
            $r2 = Kos $o
        } finally { Remove-Item -LiteralPath $o.Kok -Recurse -Force -ErrorAction SilentlyContinue }
        # opus-5-5: 1000*4 + 1000*20 + 10000*4*2 + 100000*0.2 = 124000 / 1e6 = 0.124
        [double]$r1.claudeUsd | Should Be 0.12
        [int]$r1.yeniKayit | Should Be 3          # msg_A + msg_B + codex
        [int]$r1.taninmayan | Should Be 0
        [int64]$r1.codexJeton | Should Be 1050    # (1000-400) + 400 + 50
        [int]$r2.yeniKayit | Should Be 2          # yalniz msg_C + codex farki
        [double]$r2.claudeUsd | Should Be 0.13    # +1000*4/1e6
        [int64]$r2.codexJeton | Should Be 3150    # ilk 1050 + fark 2100
    }
    It 'taninmayan bicim sayilir, tahmin uretilmez' {
        $o = New-MaliyetOrtami
        try {
            Yaz $o.Claude @('{"cwd":"C:\\x","sessionId":"s","message":{"model":"claude-opus-5-5","id":"msg_Z","usage":{"tokens_in":5}},"type":"assistant","timestamp":"2026-10-06T00:00:00Z"}')
            $r = Kos $o
        } finally { Remove-Item -LiteralPath $o.Kok -Recurse -Force -ErrorAction SilentlyContinue }
        [int]$r.taninmayan | Should Be 1
        [double]$r.claudeUsd | Should Be 0
    }
    It 'Get-BeyinUsdTahmini: bilinmeyen model $null, hizli mod x2, uzun onek once' {
        $p = Get-BeyinPaths -Vault $vault
        $t = Get-BeyinFiyatTablosu -Paths $p
        (Get-BeyinUsdTahmini -Tablo $t -Model 'gpt-5-codex' -In 1e6 -Out 0 -Cw5 0 -Cw1h 0 -Cr 0) | Should Be $null
        (Get-BeyinUsdTahmini -Tablo $t -Model 'claude-opus-5-5' -In 1e6 -Out 0 -Cw5 0 -Cw1h 0 -Cr 0 -Fast $true) | Should Be 8
        (Get-BeyinUsdTahmini -Tablo $t -Model 'claude-opus-5' -In 1e6 -Out 0 -Cw5 0 -Cw1h 0 -Cr 0) | Should Be 5
        (Get-BeyinUsdTahmini -Tablo $t -Model 'claude-haiku-4-5' -In 0 -Out 0 -Cw5 1e6 -Cw1h 0 -Cr 0) | Should Be 1.25
    }
}
