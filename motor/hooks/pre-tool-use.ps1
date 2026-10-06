# pre-tool-use.ps1 - Surec oldurme korumasi (kill guard), Claude Code + Codex PreToolUse (BB5, 2026-10-06).
#
# NEDEN (AgentSpace kill guard dersi): paralel calisan ajanlardan biri "takilan
# node'u kapatayim" diye 'taskkill /IM node.exe /F' kostugunda diger ajanlarin
# hepsini (ve kendini) oldurur. Kural (onay istemi) tek basina yetmez: onay
# yorgunlugunda gecer. Bu kanca, ajanlari ad ile toptan olduren komutlari ve
# KORUNAN bir PID'i hedefleyen komutlari mekanik olarak reddeder; ayrica insan
# onayi kayitlarina (.state\approvals) ve korunan PID listesine dokunan komutlari.
#
# KORUNAN PID: bu kancanin ata zinciri (onu cagiran ajan + terminali), canli
# oturum durumlarindaki ajan PID'leri (session-start yazar) ve
# .state\korunan-pid.json ({"pids":[...]}) - kullanicinin elle ekledikleri.
#
# CIKTI: engelde gerekce STDERR'e, cikis kodu 2 (Claude Code ve Codex ikisi de
# PreToolUse'ta exit 2'yi "engelle, gerekceyi modele goster" diye yorumlar).
# FAIL-OPEN: herhangi bir hata -> exit 0 (koruma, ajanin calismasini durdurmamali).
# Hizli yol: desen yoksa lib YUKLENMEZ, ConvertFrom-Json yok (~ms).
# Kapatmak: ayar BEYIN_KILL_GUARD kapali (ya da ortam degiskeni).

$ErrorActionPreference = 'Stop'
# tr-TR TUZAGI: -match + (?i) bu kulturde 'I'/'i' eslestirmez ('/IM', '/PID' kaciyordu, testle
# olculdu). Butun eslesmeler IgnoreCase + CultureInvariant ile.
$KgSecenek = [Text.RegularExpressions.RegexOptions]'IgnoreCase, CultureInvariant'
function M([string]$Metin, [string]$Desen) { return [regex]::IsMatch($Metin, $Desen, $KgSecenek) }
try {
    if ($env:BEYIN_CHILD -eq '1') { exit 0 }
    if ($env:BEYIN_KILL_GUARD -eq 'kapali') { exit 0 }
    $ham = [Console]::In.ReadToEnd()
    if (-not $ham) { exit 0 }
    # --- hizli on filtre ---
    if (-not (M $ham '(?i)taskkill|tskill|pkill|killall|stop-process|spps|wmic|\bkill(?=\s)|approvals|korunan-pid')) { exit 0 }

    # --- yavas yol: komutu cikar ---
    $cmd = ''
    try {
        $o = $ham | ConvertFrom-Json
        $ti = $o.tool_input
        if ($ti) {
            $c = $ti.command
            if ($c -is [array]) { $cmd = ($c | ForEach-Object { [string]$_ }) -join ' ' } elseif ($c) { $cmd = [string]$c }
        }
    } catch { }
    if (-not $cmd) { $cmd = $ham }

    $ad = '(?:node|claude|codex|powershell|pwsh|cmd|conhost|windowsterminal|wt|bash|code)(?:\.exe)?'
    $red = ''
    if ((M $cmd '(?i)\.state[\\/]+approvals|korunan-pid\.json')) {
        $red = 'insan onayi kayitlari (.state\approvals) ve korunan PID listesi ajan komutuyla okunamaz/degistirilemez. Onay yalniz kullanicinin kendi mesajindan (onayla TASK-x) gelir.'
    } elseif ((M $cmd "(?i)\btaskkill(?:\.exe)?\b[^|;&]*?/im\s+[`"']?$ad(?=[`"'\s]|$)") -or
              (M $cmd "(?i)\b(?:stop-process|spps|kill)\b[^|;&]*?-(?:name|processname)\s+[`"']?$ad(?=[`"'\s,]|$)") -or
              (M $cmd "(?i)\b(?:pkill|killall|tskill)\b(?:\s+-\S+)*\s+[`"']?$ad(?=[`"'\s]|$)") -or
              (M $cmd "(?i)\b(?:get-process|gps|ps)\s+(?:-name\s+)?[`"']?$ad\b[^;&]*\|\s*(?:stop-process|spps|kill)\b") -or
              (M $cmd "(?i)\bwmic\b[^|;&]*\bprocess\b[^|;&]*name\s*=\s*[`"'\\]*$ad[^|;&]*\bdelete\b")) {
        $red = 'ajan surecleri (node/claude/codex/powershell/terminal) AD ile toptan olduruluyor: bu komut paralel calisan diger ajanlari ve bu oturumu da oldurur. Belirli bir PID hedefle (once Get-Process ile hangi surec oldugunu dogrula).'
    }

    $vault = $(if ($env:BEYIN_VAULT) { $env:BEYIN_VAULT } else { Split-Path (Split-Path $PSScriptRoot -Parent) -Parent })
    . (Join-Path $vault 'motor\hooks\lib.ps1')
    $p = Get-BeyinPaths -Vault $vault
    try { if ([string](Get-BeyinAyar 'BEYIN_KILL_GUARD' (Get-BeyinAyarVars 'BEYIN_KILL_GUARD')) -eq 'kapali') { exit 0 } } catch { }

    $hedef = @()
    $oldurFiili = ((M $cmd '(?i)\btaskkill\b|\btskill\b|\bstop-process\b|\bspps\b|\bkill(?=\s)|\bwmic\b[^|;&]*\bdelete\b'))
    if (-not $red -and $oldurFiili) {
        foreach ($rx in @('(?i)/pid\s+(\d+)', '(?i)-id\s+(\d+(?:\s*,\s*\d+)*)', '(?i)\bkill\s+(?:-\S+\s+)*(\d+)', '(?i)processid\s*=\s*(\d+)', '(?i)\btskill\s+(\d+)', '(?i)stop-process\s+(\d+)')) {
            foreach ($m in [regex]::Matches($cmd, $rx, $KgSecenek)) { foreach ($n in ($m.Groups[1].Value -split '\s*,\s*')) { if ((M $n '^\d+$')) { $hedef += [int]$n } } }
        }
        $hedef = @($hedef | Sort-Object -Unique)
        if ($hedef.Count -gt 0) {
            $korunan = Get-BeyinKorunanPid -Paths $p
            foreach ($h in $hedef) {
                if ($korunan.ContainsKey($h)) { $red = "korunan surec PID $h ($($korunan[$h])) hedefleniyor: bu bir ajan oturumu ya da onun ata surecidir. Oldurmek gerekiyorsa kullanici kendisi yapmali."; break }
            }
        }
    }

    $not = $cmd; if ($not.Length -gt 160) { $not = $not.Substring(0, 160) }
    try { $pr = Protect-BeyinSecrets -Text $not -Vault $vault; $not = $(if ([int]$pr.Failed -gt 0) { '(maske uygulanamadi)' } else { [string]$pr.Text }) } catch { $not = '(maske hatasi)' }
    if ($red) {
        Write-BeyinMakbuz -Paths $p -Script 'kill-guard' -Outcome 'RED' -Agent (Get-BeyinAgent) -Note $not
        [Console]::Error.WriteLine("[Beyin kill guard] ENGELLENDI: $red")
        exit 2
    }
    if ($oldurFiili -or (M $cmd '(?i)\bpkill\b|\bkillall\b')) {
        Write-BeyinMakbuz -Paths $p -Script 'kill-guard' -Outcome 'GECTI' -Agent (Get-BeyinAgent) -Note $not
    }
    exit 0
} catch {
    # Tani: BEYIN_KG_HATA=1 iken fail-open nedeni stderr'e yazilir (normalde sessiz).
    if ($env:BEYIN_KG_HATA -eq '1') { [Console]::Error.WriteLine("[kill guard] fail-open: " + $_.Exception.Message + " @ " + $_.InvocationInfo.ScriptLineNumber) }
    exit 0
}
