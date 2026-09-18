# SessionEnd: transkripti arka planda gunluk loga bosaltir (flush), gerekirse
# derleyiciyi tetikler ve hafiza guncellenmeden bitmisse yansima isareti birakir.
# Hizli doner: agir isler ayri surecte calisir.

$ErrorActionPreference = 'SilentlyContinue'
# SURE OLCUMU EN BASTA (2026-09-16). NEDEN: makbuzdaki 8 session-end satirinin
# hepsi ms=0 idi; Codex'in 3 sn tavanina yaklasma ne makbuzdan ne doktordan
# gorulebiliyordu (ilk belirti kancanin sessizce olmesi olurdu). Kronometre
# lib.ps1 YUKLENMEDEN once baslar; Get-SeMs ise surec baslangicindan sayar
# (powershell acilisi + 190 KB lib ayristirma - asil maliyet orasi; launcher
# kancayi ayni surecte calistirir: '& $target'). Kronometre yalniz yedek.
$seSw = [System.Diagnostics.Stopwatch]::StartNew()
. (Join-Path $PSScriptRoot 'lib.ps1')
$ErrorActionPreference = 'SilentlyContinue'

if (Test-BeyinChild) { exit 0 }

function Get-SeMs {
    # Codex'in saydigi sure: kanca SURECININ baslangicindan itibaren gecen ms.
    try { return [long]((Get-Date) - [System.Diagnostics.Process]::GetCurrentProcess().StartTime).TotalMilliseconds }
    catch { return [long]$seSw.ElapsedMilliseconds }
}

$vault = Get-BeyinVault -ScriptPath $PSCommandPath
$p     = Get-BeyinPaths -Vault $vault
New-Item -ItemType Directory -Force -Path $p.State, $p.Sessions, $p.Reflect, $p.ScrState, $p.Queue | Out-Null

$hook = Read-BeyinHookPayload
$st   = Get-BeyinSessionState -Paths $p -SessionId $hook.session_id

$prompts    = $st.prompts
$transcript = $hook.transcript_path
$cwd        = if ($hook.cwd) { $hook.cwd } else { $st.cwd }
# Get-BeyinProjectLeaf: surucu kokunde ('C:\') ham Split-Path etiketi bozuyor
# ve o etiket .state\reflect notuna, oradan da bir sonraki oturumun baglamina
# giriyordu. TEK KAYNAK lib.ps1'deki fonksiyon.
$cwdLeaf    = if ($cwd) { Get-BeyinProjectLeaf -Path $cwd -Paths $p } else { '-' }

# ============================================================================
# 1) flush'i arka planda baslat
# ----------------------------------------------------------------------------
# Transkript yok ama oturumda is yapildiysa isi KUYRUGA at: bir sonraki
# oturum acilisinda toparlanir (temiz kapanmayan oturumlar kaybolmasin).
# ============================================================================
$isCodex = ((Get-BeyinAgent) -eq 'codex')
# Transkript diskte yoksa surec dogurma: bos bir flush claims\ altina olu bir
# kilit dosyasi birakip cikiyordu (session-start kuyruk dongusu bu kontrolu
# zaten yapiyor, iki kanca yapmiyordu).
if ($transcript -and -not (Test-Path -LiteralPath $transcript)) {
    Write-BeyinLog -Vault $vault -Message "session-end: transkript diskte yok, atlandi (proje=$cwdLeaf, ajan=$(Get-BeyinAgent))"
    $transcript = ''
}
if ($transcript -and $prompts -ge 2 -and $isCodex) {
    # CODEX HIZLI YOL (2026-09-10). Codex, SessionEnd kancasina belgelenmis
    # olarak en fazla 3 sn tanir (varsayilan 1 sn; learn.chatgpt.com/docs/hooks)
    # ve sure dolunca TUM SUREC AGACINI oldurur (Windows: JobObject /
    # taskkill /T /F; codex-rs hooks/engine/command_runner.rs). Start-Process
    # ile baslatilan flush ayni agacta oldugu icin onunla birlikte olurdu.
    # Olculdu: 15 gunde 0 codex session-end blogu, 8 temizlenmemis Codex
    # oturum durumu. Claude Code'da ayni zincire 15 sn taninir, orada calisir.
    #
    # Bu yuzden Codex'te YALNIZ KUYRUGA yazilir (~1 sn): isi bir sonraki
    # SessionStart (hangi ajan olursa olsun) drenaj eder. Derleyici tetigi de
    # atlanir (o da alt surec). hooks.json'daki timeout DEGISTIRILMEZ: Codex
    # guven hash'i timeout alanini da kapsar, degisen kanca /hooks ile yeniden
    # onaylanana kadar sessizce atlanir.
    Add-BeyinQueue -Paths $p -TranscriptPath $transcript -Cwd $cwd -Reason 'session-end' -Agent 'codex'
    # Kanit damgasi: doktor 'Codex SessionEnd' satiri engine.log yerine bunu okur
    # (log 500 KB'de son 200 satira kirpiliyor; 7 gunluk sayim orada guvenilmez).
    Write-BeyinText -Path (Join-Path $p.ScrState 'last-codex-session-end.txt') -Text (Get-Date -Format 'o')
    # -DurationMs (2026-09-16): doktor/makbuz 3 sn tavanina yaklasmayi gorsun.
    Write-BeyinMakbuz -Paths $p -Script 'session-end' -Outcome 'KUYRUK' -Agent 'codex' -Key (Get-BeyinSessionKey -SessionId $hook.session_id) `
        -Reason 'session-end' -DurationMs (Get-SeMs) -Note "$prompts prompt, proje=$cwdLeaf (3 sn tavani: flush kuyrukta)"
    Write-BeyinLog -Vault $vault -Message "session-end: is kuyruga alindi - Codex 3 sn tavani ($prompts prompt, proje=$cwdLeaf, ajan=codex)"
} elseif ($transcript -and $prompts -ge 2) {
    $ok = Start-BeyinScript -ScriptPath (Join-Path $p.Scripts 'flush.ps1') -Vault $vault -Params @{
        TranscriptPath = $transcript
        Vault          = $vault
        Reason         = 'session-end'
        Agent          = (Get-BeyinAgent)
        ProjectPath    = $cwd
    }
    # MAKBUZ CLAUDE DALINDA DA (2026-09-16). NEDEN: 2 gunluk makbuzda session-end
    # satirlarinin hepsi agent=codex idi; Claude kapanislari makbuzda hic yoktu,
    # 'flush baslatildi mi, kuyruga mi dustu' yalniz engine.log'dan okunuyordu
    # (500 KB'de kirpilan log 7 gunluk sayim icin guvenilmez).
    # Sonuc adi '_OK' ile bitmeli: makbuz.ps1 basari desenini '(_OK$|^OK$|^ENJEKSIYON$)'
    # ile arar; 'FLUSH_BASLATILDI' ne basari ne erteleme sayiliyordu (2026-09-17).
    if ($ok) {
        # Log'a yalniz YAPRAK ad: engine.log her projenin tam yolunu tutan bir
        # envantere donusmesin.
        Write-BeyinLog -Vault $vault -Message "session-end: flush baslatildi ($prompts prompt, proje=$cwdLeaf, ajan=$(Get-BeyinAgent))"
        Write-BeyinMakbuz -Paths $p -Script 'session-end' -Outcome 'SESSIONEND_OK' -Agent (Get-BeyinAgent) -Key (Get-BeyinSessionKey -SessionId $hook.session_id) `
            -Reason 'session-end' -DurationMs (Get-SeMs) -Note "$prompts prompt, proje=$cwdLeaf"
    } else {
        Add-BeyinQueue -Paths $p -TranscriptPath $transcript -Cwd $cwd -Reason 'session-end' -Agent (Get-BeyinAgent)
        Write-BeyinLog -Vault $vault -Message "session-end: flush baslatilamadi, is kuyruga alindi (proje=$cwdLeaf)"
        Write-BeyinMakbuz -Paths $p -Script 'session-end' -Outcome 'KUYRUK' -Agent (Get-BeyinAgent) -Key (Get-BeyinSessionKey -SessionId $hook.session_id) `
            -Reason 'session-end' -DurationMs (Get-SeMs) -Note "$prompts prompt, proje=$cwdLeaf (flush baslatilamadi)"
    }
} elseif ($transcript) {
    # prompts 0 veya 1: eskiden 0'da HICBIR dal calismiyordu - ne flush, ne
    # kuyruk, ne log. Oturum durumu su hallerde yok olur: durum dosyasi
    # temizlenmis, SessionStart hic ateslenmemis, session_id degismis, JSON
    # bozulmus. Sonuc tam sessiz dusustu. Artik en azindan iz kaliyor ve is
    # kuyruga giriyor (flush 'cok kisa konusma' kararini kendisi verir).
    Add-BeyinQueue -Paths $p -TranscriptPath $transcript -Cwd $cwd -Reason 'session-end' -Agent (Get-BeyinAgent)
    Write-BeyinLog -Vault $vault -Message "session-end: $prompts prompt, is kuyruga alindi (proje=$cwdLeaf, ajan=$(Get-BeyinAgent))"
    Write-BeyinMakbuz -Paths $p -Script 'session-end' -Outcome 'KUYRUK' -Agent (Get-BeyinAgent) -Key (Get-BeyinSessionKey -SessionId $hook.session_id) `
        -Reason 'session-end' -DurationMs (Get-SeMs) -Note "$prompts prompt, proje=$cwdLeaf (kisa oturum: flush karar verir)"
}

# ============================================================================
# 2) Derleyici tetigi
# ----------------------------------------------------------------------------
# Tamamlanmis bir gunun derlenmemis logu varsa (saat sartsiz) veya saat 18'i
# gectiyse bugunun logu icin. 30 dakikalik pencere ust uste baslatmayi onler.
# ============================================================================
try {
    $today   = Get-BeyinToday
    $pending = @(Get-BeyinPendingDaylogs -Paths $p)

    $shouldCompile = $false
    foreach ($f in $pending) { if ($f.BaseName -lt $today) { $shouldCompile = $true; break } }
    if (-not $shouldCompile -and (Get-Date).Hour -ge 18 -and $pending.Count -gt 0) { $shouldCompile = $true }

    if ($shouldCompile -and -not $isCodex) {   # Codex: alt surec tavani asar (bkz. yukarisi)
        $attempt = Join-Path $p.ScrState 'last_compile_attempt'
        # KILITLI DAMGA (2026-09-16): session-start.ps1 ile AYNI kilit
        # (counter.lock) ve AYNI sira. NEDEN: uc kanca ayni dosyayi yaziyordu,
        # yalniz session-start kilitliydi; engine.log 2026-09-04 13:26:49
        # 'derleyici tetigi hatasi ... last_compile_attempt ... being used by
        # another process'. Atomik yazim pencereyi daraltti ama File.Replace
        # de hedef acikken firlatir; catch yalniz loglar, derleyici o kapanista
        # baslamaz. 30 dk kontrolu KILIT ICINDE: iki kapanis ayni saniyede
        # (16:33:34/35 ornegi) 'taze degil' gorup iki derleyici baslatmasin.
        # Kilit 2 sn'de alinamazsa tetik bu kapanista atlanir; damga
        # yazilmadigi icin bir sonraki kanca yeniden dener (gecikme, kayip degil).
        $script:derleTetik = $false
        Invoke-BeyinWithLock -LockPath (Join-Path $p.ScrState 'counter.lock') -TimeoutSeconds 2 -Action {
            $recent = $false
            if (Test-Path -LiteralPath $attempt) {
                if (((Get-Date) - (Get-Item -LiteralPath $attempt).LastWriteTime).TotalMinutes -lt 30) { $recent = $true }
            }
            if (-not $recent) {
                Write-BeyinText -Path $attempt -Text (Get-Date -Format 'o')
                $script:derleTetik = $true
            }
        } | Out-Null
        if ($script:derleTetik) {
            if (Start-BeyinScript -ScriptPath (Join-Path $p.Scripts 'compile.ps1') -Vault $vault -Params @{ Vault = $vault }) {
                Write-BeyinLog -Vault $vault -Message "session-end: derleyici baslatildi ($($pending.Count) bekleyen log)"
            }
        }
    }
} catch {
    Write-BeyinLog -Vault $vault -Message "session-end: derleyici tetigi hatasi: $($_.Exception.Message)"
}

# ============================================================================
# 3) Hafiza guncellenmeden bittiyse yansima isareti
# ============================================================================
$modified = $false
foreach ($n in @('current-context.md','active-threads.md','rules.md')) {
    $f = Join-Path $p.Memory $n
    if (Test-Path -LiteralPath $f) {
        # PS 5.1: [DateTimeOffset]$dt cast'i ToUnixTimeSeconds vermez, ::new() gerekir
        $mt = [DateTimeOffset]::new((Get-Item -LiteralPath $f).LastWriteTimeUtc, [TimeSpan]::Zero).ToUnixTimeSeconds()
        if ($mt -gt $st.start) { $modified = $true; break }
    }
}

if ($prompts -ge 5 -and -not $modified) {
    $key = Get-BeyinSessionKey -SessionId $hook.session_id
    $txt = "$((Get-Date).ToString('yyyy-MM-dd HH:mm', [Globalization.CultureInfo]::InvariantCulture)) - $prompts mesaj"
    if ($cwdLeaf -ne '-') { $txt += " - proje: $cwdLeaf" }
    Write-BeyinText -Path (Join-Path $p.Reflect "$key.txt") -Text $txt

    $all = @(Get-ChildItem -LiteralPath $p.Reflect -Filter '*.txt' -File -ErrorAction SilentlyContinue |
             Sort-Object LastWriteTime -Descending)
    if ($all.Count -gt 10) {
        foreach ($old in $all[10..($all.Count - 1)]) {
            Remove-Item -LiteralPath $old.FullName -Force -ErrorAction SilentlyContinue
        }
    }
}

Remove-BeyinSessionState -Paths $p -SessionId $hook.session_id
exit 0
