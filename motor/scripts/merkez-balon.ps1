# merkez-balon.ps1 - canli bir Claude Code / Codex oturumunun SON etkinligini tek satirlik
# kisa bir "balon" metnine cevirir (Beyin merkez izleme paneli icin).
#
# Kullanim (dot-source):
#   . "$PSScriptRoot\merkez-balon.ps1"
#   $b = Get-MerkezEtkinlik -Ajan claude -OturumId <id> [-Cwd <yol>]
#   $b.Ok / $b.Metin (<=64 karakter, tek satir, maskeli) / $b.Zaman / $b.Tur
#   Tur: arac | yazi | dusunce | bekliyor | yok
#
# UCUZLUK SOZLESMESI (panel ~5 sn'de bir, ~20 oturum icin cagirir):
#   - Transkriptin yalniz KUYRUGU okunur (64 KB; anlamli kayit yoksa 256 KB, sonra 1 MB).
#     Codex rollout dosyalari onlarca GB olabilir: tamamini okumak yasak.
#   - Cozumlenen transkript yolu oturum kimligi basina script-scope tabloda tutulur;
#     bulunamayan kimlik 30 sn boyunca yeniden aranmaz.
#   - Dosya boyu + mtime degismediyse yeniden ayristirilmaz, onceki sonuc doner.
#   - Kayitlar kuyruktan geriye taranir, ilk anlamli kayitta durulur.
# OKUMA KURALI: dosyalar ReadWrite+Delete paylasimiyla acilir (takim-izle.ps1 Read-Shared ile ayni):
#   yazan ajani ya da motorun atomik yeniden adlandirmasini asla engellemez. Salt okunur.
# GIZLILIK: transkript icerigi hicbir yere yazilmaz; donen metin maskelenir ve 64 karakterle kesilir.
# Ortam degiskenleri lib.ps1 ile ayni: CLAUDE_CONFIG_DIR, CODEX_HOME.

$script:MerkezYol = @{}      # "ajan|id" -> transkript yolu
$script:MerkezYok = @{}      # "ajan|id" -> son basarisiz arama zamani
$script:MerkezSonuc = @{}    # "ajan|id" -> @{ Len; Mtime; Sonuc }
$script:MerkezAyristirma = 0 # test/teshis: gercek ayristirma sayaci
$script:MerkezMaxMetin = 160   # ekran Cut ile kendi genisligine keser; kaynakta 64 genis ekranda balonu bosuna kisaltiyordu

function Clear-MerkezOnbellek {
    $script:MerkezYol = @{}; $script:MerkezYok = @{}; $script:MerkezSonuc = @{}; $script:MerkezAyristirma = 0
}

function Get-MerkezAyristirmaSayisi { return $script:MerkezAyristirma }

function Get-MerkezClaudeKok { if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $env:USERPROFILE '.claude' } }
function Get-MerkezCodexKok { if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE '.codex' } }

# Dosyanin son $Bayt baytini paylasimli okur. Ilk (muhtemelen yarim) satir atilir; dosya basindan
# okunduysa atilmaz.
function Read-MerkezKuyruk([string]$Path, [long]$Bayt) {
    $fs = $null
    try {
        $fs = New-Object IO.FileStream($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
        $len = $fs.Length
        $bas = [long]0
        if ($len -gt $Bayt) { $bas = $len - $Bayt }
        [void]$fs.Seek($bas, [IO.SeekOrigin]::Begin)
        $buf = New-Object byte[] ([int]($len - $bas))
        $okunan = 0
        while ($okunan -lt $buf.Length) {
            $n = $fs.Read($buf, $okunan, $buf.Length - $okunan)
            if ($n -le 0) { break }
            $okunan += $n
        }
        $metin = [Text.Encoding]::UTF8.GetString($buf, 0, $okunan)
        $satirlar = $metin -split "`n"
        if ($bas -gt 0 -and $satirlar.Count -gt 0) { $satirlar = @($satirlar | Select-Object -Skip 1) }
        return [pscustomobject]@{ Satirlar = $satirlar; Tam = ($bas -eq 0) }
    } finally { if ($fs) { $fs.Dispose() } }
}

# Sir benzeri parcalari maskeler. Kesmeden ONCE cagrilir.
function Protect-MerkezMetin([string]$Metin) {
    if (-not $Metin) { return $Metin }
    $m = $Metin
    # Authorization: Bearer xxx
    $m = [regex]::Replace($m, '(?i)\b(bearer|basic)\s+[A-Za-z0-9._~+/=\-]{8,}', '$1 ***')
    # anahtar=deger / anahtar: deger (token=, api_key=, client_secret:, password= ...)
    $m = [regex]::Replace($m, '(?i)\b([\w\-]*(?:token|key|secret|passw(?:or)?d|pwd|parola|sifre|şifre|auth|credential)s?)(\s*[=:]\s*)("[^"]*"|''[^'']*''|[^\s&;,]+)', '$1$2***')
    # komut satiri bayraklari: --password xxx, -p:xxx yok; --token xxx
    $m = [regex]::Replace($m, '(?i)(--?(?:token|api-?key|secret|passw(?:or)?d|pwd|parola))(\s+)("[^"]*"|''[^'']*''|\S+)', '$1$2***')
    # "password hunter2" bicimi (ayirici olmadan)
    $m = [regex]::Replace($m, '(?i)\b(password|passwd|parola|şifre|sifre)\b(\s+)(?!\*\*\*)(\S+)', '$1$2***')
    # bilinen onekli anahtarlar
    $m = [regex]::Replace($m, '\b(?:sk|pk|rk)-[A-Za-z0-9_\-]{12,}|\bgh[pousr]_[A-Za-z0-9]{12,}|\bgithub_pat_[A-Za-z0-9_]{12,}|\bxox[abprs]-[A-Za-z0-9\-]{8,}|\bAKIA[0-9A-Z]{12,}|\bAIza[0-9A-Za-z_\-]{20,}|\beyJ[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-\.]+', '***')
    # uzun hex
    $m = [regex]::Replace($m, '\b[0-9a-fA-F]{24,}\b', { param($x) if ($x.Value -match '\d') { '***' } else { $x.Value } })
    # uzun base64 / base64url: en az bir rakam ve bir harf iceren 32+ karakterlik kosu
    $m = [regex]::Replace($m, '[A-Za-z0-9+/_\-]{32,}={0,2}', {
            param($x)
            $v = $x.Value
            # Yol ve kebab-case adlar (a/b-c_d) maskelenmez: ayiricilar arasindaki en uzun parca
            # 20+ karakter olup hem rakam hem harf iceriyorsa sir sayilir.
            $sir = $false
            foreach ($parca in ($v -split '[-_/+]')) { if ($parca.Length -ge 20 -and $parca -match '\d' -and $parca -match '[A-Za-z]') { $sir = $true; break } }
            if ($sir) { '***' } else { $v }
        })
    return $m
}

# Tek satir + maske + MerkezMaxMetin (160) karakter kesimi.
function Format-MerkezMetin([string]$Metin) {
    if ($null -eq $Metin) { return '' }
    $t = [regex]::Replace($Metin, '[\x00-\x1F\x7F  ]+', ' ')
    $t = [regex]::Replace($t, '\s{2,}', ' ').Trim()
    if ($t.Length -gt 600) { $t = $t.Substring(0, 600) }
    $t = Protect-MerkezMetin $t
    $max = $script:MerkezMaxMetin
    if ($t.Length -gt $max) {
        $kes = $max - 1
        if ([char]::IsHighSurrogate($t[$kes - 1])) { $kes-- }
        $t = $t.Substring(0, $kes).TrimEnd() + '…'
    }
    return $t
}

# Asistan metnindeki markdown suslerini atar (balonda ** ve ` gurultudur).
function Get-MerkezDuzMetin([string]$Metin) { return ([string]$Metin -replace '\*\*|__|`', '' -replace '(?m)^\s*#{1,6}\s+', '') }

function Get-MerkezYaprak([string]$Yol) {
    if (-not $Yol) { return '' }
    $y = $Yol.Trim().Trim('"', "'").TrimEnd('/', '\')
    $i = $y.LastIndexOfAny([char[]]@('/', '\'))
    if ($i -ge 0) { return $y.Substring($i + 1) }
    return $y
}

function Get-MerkezIlkSatir([string]$Metin) {
    if (-not $Metin) { return '' }
    foreach ($s in ($Metin -split "`r?`n")) { if ($s.Trim()) { return $s.Trim() } }
    return ''
}

function Get-MerkezPatchDosya([string]$Patch) {
    if ($Patch -match '\*\*\* (?:Update|Add|Delete) File:\s*([^\r\n]+)') { return (Get-MerkezYaprak $Matches[1]) }
    return ''
}

function Get-MerkezAlan($Nesne, [string[]]$Adlar) {
    if ($null -eq $Nesne) { return $null }
    foreach ($a in $Adlar) {
        $p = $Nesne.PSObject.Properties[$a]
        if ($p -and $null -ne $p.Value -and [string]$p.Value -ne '') { return $p.Value }
    }
    return $null
}

# Claude tool_use blogu -> "▸ Ad: ozet"
function Format-MerkezClaudeArac([string]$Ad, $Girdi) {
    $ozet = ''
    switch -Regex ($Ad) {
        '^(Bash|PowerShell)$' { $ozet = Get-MerkezIlkSatir ([string](Get-MerkezAlan $Girdi @('command'))); break }
        '^(Read|Edit|Write|MultiEdit|NotebookEdit)$' { $ozet = Get-MerkezYaprak ([string](Get-MerkezAlan $Girdi @('file_path', 'notebook_path', 'path'))); break }
        '^(Grep|Glob)$' { $ozet = [string](Get-MerkezAlan $Girdi @('pattern')); break }
        '^WebFetch$' { $u = [string](Get-MerkezAlan $Girdi @('url')); if ($u -match '^\w+://([^/]+)') { $ozet = $Matches[1] } else { $ozet = $u }; break }
        '^WebSearch$' { $ozet = [string](Get-MerkezAlan $Girdi @('query')); break }
        '^(Agent|Task)$' { $ozet = [string](Get-MerkezAlan $Girdi @('description', 'subagent_type')); break }
        '^Skill$' { $ozet = [string](Get-MerkezAlan $Girdi @('skill')); break }
        '^mcp__' { $parca = $Ad -split '__'; $Ad = 'mcp'; $ozet = ($parca | Select-Object -Skip 1) -join '.'; break }
        default { $ozet = '' }
    }
    if ($ozet) { return "▸ ${Ad}: $ozet" }
    return "▸ $Ad"
}

# Codex arac adi + ham girdi -> "▸ Ad: ozet"
function Format-MerkezCodexArac([string]$Ad, [string]$Girdi) {
    $Ad = [string]$Ad
    if ($Ad -eq 'apply_patch') { $d = Get-MerkezPatchDosya $Girdi; if ($d) { return "▸ Edit: $d" }; return '▸ Edit' }
    if ($Ad -eq 'exec') {
        # Kod modu: girdi JS; ilk tools.X({ anahtar: "deger" ... }) cagrisi okunur.
        $rx = 'tools\.([\w]+)\(\s*\{\s*(\w+)\s*:\s*(\[?\s*\{?\s*(?:\w+\s*:\s*)?)("(?:[^"\\]|\\.)*"|''(?:[^''\\]|\\.)*''|`(?:[^`\\]|\\.)*`)'
        $m = [regex]::Match($Girdi, $rx)
        if (-not $m.Success) {
            $m2 = [regex]::Match($Girdi, 'tools\.([\w]+)\(')
            if ($m2.Success) { if ($m2.Groups[1].Value -eq 'write_stdin') { return '▸ Shell: stdin' }; return (Format-MerkezCodexArac $m2.Groups[1].Value '') }
            return '▸ Shell'
        }
        $arac = $m.Groups[1].Value
        $lit = $m.Groups[4].Value
        $deger = $lit.Substring(1, $lit.Length - 2)
        if ($lit[0] -eq '"') { try { $deger = ConvertFrom-Json ('"' + $deger + '"') } catch { } }
        else { $deger = $deger -replace '\\n', "`n" -replace '\\(.)', '$1' }
        switch -Regex ($arac) {
            '^(exec_command|shell|shell_command|local_shell)$' { return "▸ Shell: $(Get-MerkezIlkSatir $deger)" }
            '^apply_patch$' { $d = Get-MerkezPatchDosya $deger; if ($d) { return "▸ Edit: $d" }; return '▸ Edit' }
            '^web' { if ($m.Groups[2].Value -in @('query', 'q', 'search_query')) { return "▸ Web: $(Get-MerkezIlkSatir $deger)" }; return '▸ Web' }
            default { return "▸ ${arac}: $(Get-MerkezIlkSatir $deger)" }
        }
    }
    if ($Ad -match '^(shell|exec_command|shell_command|container\.exec|local_shell)$') {
        $cmd = ''
        try {
            $a = $Girdi | ConvertFrom-Json
            $c = Get-MerkezAlan $a @('cmd', 'command')
            if ($c -is [array]) {
                $arr = @($c | ForEach-Object { [string]$_ })
                # ["powershell","-Command","..."] / ["bash","-lc","..."] -> son eleman asil komut
                if ($arr.Count -ge 3 -and $arr[$arr.Count - 2] -match '^-(c|lc|Command|NoProfile)$') { $cmd = $arr[$arr.Count - 1] } else { $cmd = $arr -join ' ' }
            } else { $cmd = [string]$c }
        } catch { $cmd = '' }
        if ($cmd) { return "▸ Shell: $(Get-MerkezIlkSatir $cmd)" }
        return '▸ Shell'
    }
    if ($Ad -eq 'update_plan') { return '▸ Plan' }
    if ($Ad -match '^web') { try { $a = $Girdi | ConvertFrom-Json; $q = Get-MerkezAlan $a @('query', 'q'); if ($q) { return "▸ Web: $q" } } catch { }; return '▸ Web' }
    if ($Ad) { return "▸ $Ad" }
    return '▸ araç'
}

function ConvertTo-MerkezZaman($Ham) {
    if (-not $Ham) { return $null }
    if ($Ham -is [DateTime]) { return $Ham.ToLocalTime() }
    try { return ([DateTimeOffset]::Parse([string]$Ham, [Globalization.CultureInfo]::InvariantCulture)).LocalDateTime } catch { return $null }
}

function New-MerkezSonuc([bool]$Ok, [string]$Metin, $Zaman, [string]$Tur) {
    return @{ Ok = $Ok; Metin = $Metin; Zaman = $Zaman; Tur = $Tur }
}

# Claude kaydi -> sonuc ya da $null (anlamsiz kayit, geriye taramaya devam)
function Convert-MerkezClaudeKayit($o) {
    $tip = [string]$o.type
    if ($tip -ne 'assistant' -and $tip -ne 'user') { return $null }
    if ($o.PSObject.Properties['isSidechain'] -and $o.isSidechain -eq $true) { return $null }
    $msg = $o.message
    if ($null -eq $msg) { return $null }
    $zaman = ConvertTo-MerkezZaman $o.timestamp
    $icerik = $msg.content
    if ($tip -eq 'user') {
        if ($o.PSObject.Properties['isMeta'] -and $o.isMeta -eq $true) { return $null }
        if ($icerik -is [string]) { if ($icerik.Trim()) { return (New-MerkezSonuc $true '… düşünüyor' $zaman 'dusunce') }; return $null }
        $bloklar = @($icerik)
        if (@($bloklar | Where-Object { $_.type -eq 'tool_result' }).Count) { return $null }   # arac sonucu: onceki araci goster
        if (@($bloklar | Where-Object { $_.type -eq 'text' -and $_.text }).Count) { return (New-MerkezSonuc $true '… düşünüyor' $zaman 'dusunce') }
        return $null
    }
    $bloklar = @($icerik)
    for ($i = $bloklar.Count - 1; $i -ge 0; $i--) {
        $b = $bloklar[$i]
        if ($null -eq $b) { continue }
        switch ([string]$b.type) {
            'tool_use' { return (New-MerkezSonuc $true (Format-MerkezMetin (Format-MerkezClaudeArac ([string]$b.name) $b.input)) $zaman 'arac') }
            'text' {
                if (-not ([string]$b.text).Trim()) { continue }
                $tur = 'yazi'; if ([string]$msg.stop_reason -eq 'end_turn') { $tur = 'bekliyor' }
                return (New-MerkezSonuc $true (Format-MerkezMetin ('✎ ' + (Get-MerkezDuzMetin $b.text))) $zaman $tur)
            }
            { $_ -eq 'thinking' -or $_ -eq 'redacted_thinking' } { return (New-MerkezSonuc $true '… düşünüyor' $zaman 'dusunce') }
        }
    }
    return $null
}

# Codex rollout kaydi -> sonuc ya da $null
function Convert-MerkezCodexKayit($o) {
    $tip = [string]$o.type
    $p = $o.payload
    if ($null -eq $p) { return $null }
    $zaman = ConvertTo-MerkezZaman $o.timestamp
    $pt = [string]$p.type
    if ($tip -eq 'event_msg') {
        if ($pt -eq 'task_complete') {
            $son = [string](Get-MerkezAlan $p @('last_agent_message'))
            if ($son.Trim()) { return (New-MerkezSonuc $true (Format-MerkezMetin ('✎ ' + (Get-MerkezDuzMetin $son))) $zaman 'bekliyor') }
            return (New-MerkezSonuc $true '‖ bekliyor' $zaman 'bekliyor')
        }
        if ($pt -eq 'turn_aborted') { return (New-MerkezSonuc $true '‖ durduruldu' $zaman 'bekliyor') }
        return $null
    }
    if ($tip -ne 'response_item') { return $null }
    switch ($pt) {
        'reasoning' { return (New-MerkezSonuc $true '… düşünüyor' $zaman 'dusunce') }
        'message' {
            $rol = [string]$p.role
            $metin = (@($p.content) | Where-Object { $_ -and $_.PSObject.Properties['text'] } | ForEach-Object { [string]$_.text }) -join ' '
            if ($rol -eq 'assistant') { if ($metin.Trim()) { return (New-MerkezSonuc $true (Format-MerkezMetin ('✎ ' + (Get-MerkezDuzMetin $metin))) $zaman 'yazi') }; return $null }
            if ($rol -eq 'user') {
                # Ortam/talimat enjeksiyonlari (<environment_context> vb.) kullanici istemi sayilmaz.
                if ($metin.TrimStart().StartsWith('<')) { return $null }
                if ($metin.Trim()) { return (New-MerkezSonuc $true '… düşünüyor' $zaman 'dusunce') }
            }
            return $null
        }
        'custom_tool_call' { return (New-MerkezSonuc $true (Format-MerkezMetin (Format-MerkezCodexArac ([string]$p.name) ([string]$p.input))) $zaman 'arac') }
        'function_call' { return (New-MerkezSonuc $true (Format-MerkezMetin (Format-MerkezCodexArac ([string]$p.name) ([string]$p.arguments))) $zaman 'arac') }
        'local_shell_call' {
            $c = $null; if ($p.action) { $c = Get-MerkezAlan $p.action @('command') }
            $s = (@($c) | ForEach-Object { [string]$_ }) -join ' '
            if ($s) { return (New-MerkezSonuc $true (Format-MerkezMetin "▸ Shell: $s") $zaman 'arac') }
            return (New-MerkezSonuc $true '▸ Shell' $zaman 'arac')
        }
        'web_search_call' {
            $q = $null; if ($p.action) { $q = Get-MerkezAlan $p.action @('query') }
            if ($q) { return (New-MerkezSonuc $true (Format-MerkezMetin "▸ Web: $q") $zaman 'arac') }
            return (New-MerkezSonuc $true '▸ Web' $zaman 'arac')
        }
    }
    return $null
}

function Resolve-MerkezTranskript([string]$Ajan, [string]$OturumId, [string]$Cwd) {
    $anahtar = "$Ajan|$OturumId"
    if ($script:MerkezYol.ContainsKey($anahtar)) {
        $y = $script:MerkezYol[$anahtar]
        if (Test-Path -LiteralPath $y -PathType Leaf) { return $y }
        $script:MerkezYol.Remove($anahtar)
    }
    if ($script:MerkezYok.ContainsKey($anahtar) -and ((Get-Date) - $script:MerkezYok[$anahtar]).TotalSeconds -lt 30) { return $null }
    $bulunan = $null
    if ($Ajan -eq 'claude') {
        $kok = Join-Path (Get-MerkezClaudeKok) 'projects'
        $ad = "$OturumId.jsonl"
        if ($Cwd) {
            $kod = [regex]::Replace($Cwd.TrimEnd('\', '/'), '[^A-Za-z0-9]', '-')
            $aday = Join-Path (Join-Path $kok $kod) $ad
            if (Test-Path -LiteralPath $aday -PathType Leaf) { $bulunan = $aday }
        }
        if (-not $bulunan -and (Test-Path -LiteralPath $kok)) {
            foreach ($d in [IO.Directory]::EnumerateDirectories($kok)) {
                $aday = Join-Path $d $ad
                if ([IO.File]::Exists($aday)) { $bulunan = $aday; break }
            }
        }
    } else {
        $kok = Join-Path (Get-MerkezCodexKok) 'sessions'
        if (Test-Path -LiteralPath $kok) {
            $desen = "rollout-*$OturumId.jsonl"
            # Once son 3 gunun klasorleri (ucuz), sonra butun agac.
            for ($g = 0; $g -lt 3 -and -not $bulunan; $g++) {
                $gun = (Get-Date).AddDays(-$g)
                $kl = Join-Path $kok ('{0:yyyy}\{0:MM}\{0:dd}' -f $gun)
                if (Test-Path -LiteralPath $kl) { $bulunan = @([IO.Directory]::EnumerateFiles($kl, $desen))[0] }
            }
            if (-not $bulunan) {
                try { $bulunan = @([IO.Directory]::EnumerateFiles($kok, $desen, [IO.SearchOption]::AllDirectories))[0] } catch { $bulunan = $null }
            }
        }
    }
    if ($bulunan) { $script:MerkezYol[$anahtar] = $bulunan; $script:MerkezYok.Remove($anahtar); return $bulunan }
    $script:MerkezYok[$anahtar] = Get-Date
    return $null
}

function Get-MerkezEtkinlik {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][ValidateSet('claude', 'codex')][string]$Ajan,
        [Parameter(Mandatory = $true)][string]$OturumId,
        [string]$Cwd
    )
    $yok = New-MerkezSonuc $false '' $null 'yok'
    try {
        if ($OturumId -notmatch '^[A-Za-z0-9\-_]+$') { return $yok }   # yol enjeksiyonuna kapali
        $yol = Resolve-MerkezTranskript $Ajan $OturumId $Cwd
        if (-not $yol) { return $yok }
        $fi = New-Object IO.FileInfo($yol)
        $fi.Refresh()
        if (-not $fi.Exists) { return $yok }
        $anahtar = "$Ajan|$OturumId"
        $onceki = $script:MerkezSonuc[$anahtar]
        if ($onceki -and $onceki.Len -eq $fi.Length -and $onceki.Mtime -eq $fi.LastWriteTimeUtc.Ticks) { return $onceki.Sonuc.Clone() }

        $script:MerkezAyristirma++
        $sonuc = $null
        foreach ($bayt in @(65536, 262144, 1048576)) {
            $k = Read-MerkezKuyruk $yol $bayt
            $s = $k.Satirlar
            for ($i = $s.Count - 1; $i -ge 0; $i--) {
                $ln = $s[$i].Trim()
                if (-not $ln -or $ln[0] -ne '{') { continue }
                # Ucuz on suzgec: ilgisiz kayitlari JSON'a cevirme.
                if ($Ajan -eq 'claude') { if ($ln -notmatch '"type"\s*:\s*"(assistant|user)"') { continue } }
                else { if ($ln -notmatch '"type"\s*:\s*"(response_item|event_msg)"') { continue }; if ($ln -match '^\{[^{]*"type"\s*:\s*"event_msg"' -and $ln -notmatch '"(task_complete|turn_aborted)"') { continue } }
                $o = $null
                try { $o = $ln | ConvertFrom-Json } catch { continue }
                if ($null -eq $o) { continue }
                $r = $null
                try { if ($Ajan -eq 'claude') { $r = Convert-MerkezClaudeKayit $o } else { $r = Convert-MerkezCodexKayit $o } } catch { $r = $null }
                if ($r) { $sonuc = $r; break }
            }
            if ($sonuc -or $k.Tam) { break }
        }
        if (-not $sonuc) { $sonuc = New-MerkezSonuc $true '' $null 'yok' }
        $script:MerkezSonuc[$anahtar] = @{ Len = $fi.Length; Mtime = $fi.LastWriteTimeUtc.Ticks; Sonuc = $sonuc }
        return $sonuc.Clone()
    } catch {
        return $yok
    }
}
