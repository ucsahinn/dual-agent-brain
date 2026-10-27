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
    if (-not (M $ham '(?i)taskkill|tskill|pkill|killall|stop-process|spps|wmic|\bkill(?=\s)|approvals|korunan-pid|ayar\.json|agentchef-kok|kill-guard|vault\.txt|beyin-launcher|BEYIN_KILL_GUARD|start-process[^;|&]*claude|\bclaude(?:\.exe|\.cmd)?(?:\\?[''"])?\s+(?:-p\b|--print\b)|\bcodex(?:\.exe|\.cmd)?(?:\\?[''"])?\s+(?:exec|e)\b')) { exit 0 }

    $cmd = ''; $dosya = ''
    try {
        $o = $ham | ConvertFrom-Json
        $ti = $o.tool_input
        if ($ti) {
            $c = $ti.command
            if ($c -is [array]) { $cmd = ($c | ForEach-Object { [string]$_ }) -join ' ' } elseif ($c) { $cmd = [string]$c }
            # 2026-10-14 guvenlik denetimi: Write/Edit/MultiEdit/NotebookEdit kill guard'in DISINDAYDI; onay kaydi bu
            # araclarla dogrudan yazilabiliyordu. Dosya araclarinda yalniz HEDEF YOL denetlenir (icerik degil).
            foreach ($alan in @('file_path', 'notebook_path', 'path')) { if (-not $dosya -and $ti.$alan) { $dosya = [string]$ti.$alan } }
        }
    } catch { }
    if ($dosya -and -not $cmd) {
        if ((M $dosya '(?i)[\\/]\.state[\\/]+approvals([\\/]|$)|korunan-pid\.json|[\\/]\.beyin[\\/]+(?:ayar\.json|agentchef-kok\.txt|vault\.txt|kill-guard-on\.mjs|beyin-launcher\.ps1)$')) {
            [Console]::Error.WriteLine('[Beyin kill guard] ENGELLENDI: insan onayi kayitlari, korunan PID listesi ve Beyin ayar/kesif dosyalari ajan araciyla yazilamaz. Ayar degisikligi kullanicinin isidir (beyin ayar ...).')
            exit 2
        }
        exit 0
    }
    if (-not $cmd) { $cmd = $ham }

    $ad = '(?:node|claude|codex|powershell|pwsh|cmd|conhost|windowsterminal|wt|bash|code)(?:\.exe)?'
    $red = ''
    # Cagri konumu: satir basi, ; | & && || sonrasi, cmd /c, start, Start-Process, -Command. Metin icinde gecmesi engellenmez.
    $cagri = '(?im)(?:^|[;|&]\s*|&&\s*|\|\|\s*|\bcmd(?:\.exe)?\s+/[ck]\s+[''"]?|\bstart\s+(?:/\w+\s+)*|\bstart-process\s+(?:-filepath\s+)?|-command\s+[''"]?)(?:&\s*)?(?:\\?[''"])?(?:[\w:.\\/-]*[\\/])?'
    # claude print: her zaman (Claude onay taklidi). codex exec: yalniz onay sozcugu tasiyorsa (Codex'e devir akislari calisir; 2026-10-14 peer incelemesi).
    $altAjan = $cagri + '(?:claude(?:\.exe|\.cmd)?(?:\\?[''"])?\s+(?:-p\b|--print\b)|codex(?:\.exe|\.cmd)?(?:\\?[''"])?\s+(?:exec|e)\b(?=[\s\S]*\b(?:baslat|birlestir|onayla)\b))'
    # Start-Process <claude> -ArgumentList '-p',... bicimi (2026-10-14: bilinen sinir kapandi)
    $altAjan = '(?:' + $altAjan + ')|(?i)\bstart-process\b[^;|&\r\n]*\bclaude(?:\.exe|\.cmd)?\b[^;|&\r\n]*-argumentlist\b[^;|&\r\n]*[''"](?:-p|--print)[''"]'
    if ((M $cmd $altAjan)) {
        # 2026-10-14 guvenlik denetimi: ajanin actigi alt ajan oturumu (claude -p / codex exec) Beyin kancalarini
        # tetikler ve kendi "kullanici" satiriyla onay (baslat/birlestir/onayla) uretebilirdi. Takim iscileri motorun
        # kendisiyle acilir (beyin takim start), ajanin kabugundan degil.
        $red = 'ajan kabugundan alt ajan oturumu (claude -p / codex exec) acilamaz: bu yol insan onayini taklit edebilir. Takim isi icin beyin takim kullan; elle gerekiyorsa kullanici kendisi calistirsin.'
    } elseif ((M $cmd '(?i)BEYIN_KILL_GUARD|[\\/]\.beyin[\\/]+(?:ayar\.json|agentchef-kok\.txt|kill-guard-on\.mjs)')) {
        $red = 'kill guard ve Beyin kesif/ayar dosyalari ajan komutuyla degistirilemez. Kapatmak ya da ayar degistirmek kullanicinin kararidir (kendi terminalinde: beyin ayar ...).'
    } elseif ((M $cmd '(?i)\.state[\\/]+approvals|korunan-pid\.json')) {
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
                # A registered worker is stopped only through its owner-checked job command.
                # Raw PID kills remain denied, including when the worker is not an ancestor.
                $kanalState = Join-Path $vault 'motor/scripts/.state/codex-kanal'
                if (Test-Path -LiteralPath $kanalState) {
                    foreach ($kf in Get-ChildItem -LiteralPath $kanalState -Filter 'CK-*.json' -File) {
                        try {
                            $kr = [IO.File]::ReadAllText($kf.FullName) | ConvertFrom-Json
                            if ($kr.Owner -ne 'beyin-codex-kanal-v1' -or $kr.Id -cnotmatch '^CK-[a-f0-9]{32}$') { continue }
                            $kp = Get-Process -Id $h -ErrorAction SilentlyContinue
                            if ($kp -and $kr.RootPid -eq $h -and $kr.RootStart -and [math]::Abs(($kp.StartTime.ToUniversalTime()-[datetime]::Parse($kr.RootStart).ToUniversalTime()).TotalSeconds) -lt 1) {
                                $red = "kayitli isci PID $h korunuyor; yalniz sahip oturum beyin codex kapat $($kr.Id) kullanabilir."
                                break
                            }
                        } catch { }
                    }
                }
                if ($red) { break }
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
