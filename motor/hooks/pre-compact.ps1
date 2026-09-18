# PreCompact: context dolup sikistirma yapilmadan ONCE konusmayi gunluk loga
# bosaltir; boylece uzun oturumlarin ortasindaki bilgi kaybolmaz.
#
# Watermark sayesinde bu, SessionEnd'in ayni icerigi ikinci kez ozetlemesine
# yol acmaz: flush yalniz watermark'tan sonraki satirlari isler.

$ErrorActionPreference = 'SilentlyContinue'
. (Join-Path $PSScriptRoot 'lib.ps1')
$ErrorActionPreference = 'SilentlyContinue'

if (Test-BeyinChild) { exit 0 }

$vault = Get-BeyinVault -ScriptPath $PSCommandPath
$p     = Get-BeyinPaths -Vault $vault
New-Item -ItemType Directory -Force -Path $p.State, $p.Sessions, $p.ScrState, $p.Queue | Out-Null

$hook = Read-BeyinHookPayload
$st   = Get-BeyinSessionState -Paths $p -SessionId $hook.session_id
$cwd  = if ($hook.cwd) { $hook.cwd } else { $st.cwd }
$cwdLeaf = if ($cwd) { Get-BeyinProjectLeaf -Path $cwd -Paths $p } else { '-' }

# --- 1) sikistirma oncesi flush ---
# ESIK ve TEKRAR PENCERESI (2026-09-10). Onceki surum kosulsuzdu: her
# sikistirmada bir surec doguyordu. Olcum: 'pre-compact: flush baslatildi' 444
# kez, 'session-end: flush baslatildi' 32 kez (14:1) - gunluk butceyi pratikte
# pre-compact yakiyordu ve ayni dev rollout ayni pencereyi ust uste okuyordu.
$pcAtla = $false
if ($hook.transcript_path -and -not (Test-Path -LiteralPath $hook.transcript_path)) {
    Write-BeyinLog -Vault $vault -Message "pre-compact: transkript diskte yok, atlandi (proje=$cwdLeaf)"
    $pcAtla = $true
}
if (-not $pcAtla -and $st.prompts -lt 2) {
    # session-end ile ayni esik: iki mesajdan kisa konusma ozetlenmiyor.
    Write-BeyinLog -Vault $vault -Message "pre-compact: $($st.prompts) prompt, flush atlandi (proje=$cwdLeaf)"
    $pcAtla = $true
}
if (-not $pcAtla -and $hook.transcript_path -and (Test-BeyinClaimBusy -Paths $p -TranscriptPath $hook.transcript_path)) {
    # Bu transkript su an baska bir flush tarafindan isleniyor; ikinci surec
    # yalnizca claim'e carpip kuyruga yaziyor. Ucuz on kontrol.
    Add-BeyinQueue -Paths $p -TranscriptPath $hook.transcript_path -Cwd $cwd -Reason 'pre-compact' -Agent (Get-BeyinAgent)
    Write-BeyinLog -Vault $vault -Message "pre-compact: transkript zaten isleniyor, is kuyruga alindi (proje=$cwdLeaf)"
    $pcAtla = $true
}
# OTURUM PAYI (2026-09-17, makbuzla olculdu).
# Gunluk butce oturum KAPATMAKTAN degil, uzun oturumlarin otomatik
# SIKISTIRMASINDAN doluyordu: bes oturum 27/14/14/7/1 kez sikismis, 63 cagri
# harcamis, tavan gun ortasinda dolmus ve sonraki oturumlarin kapanis ozeti
# ertesi gune kalmisti. Is mesru (63'un 57'si gunluk loga gercekten yazdi),
# bu yuzden DUSURULMUYOR - payi asan KUYRUGA aliniyor. Kuyrugu gece gorevi
# (topla-uygula) isliyor, yani hicbir konusma kaybolmuyor; yalnizca bes farkli
# oturumun ILK ozeti, tek bir oturumun 27. sikismasindan ONCE geciyor.
if (-not $pcAtla -and $hook.transcript_path) {
    $pcBugun = (Get-Date).ToString('yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)
    $pcSayac = 0
    if ([string]$st.pcGun -eq $pcBugun) { $pcSayac = [int]$st.pcSayi }
    $pcPay = Get-BeyinOturumPayi
    if ($pcSayac -ge $pcPay) {
        Add-BeyinQueue -Paths $p -TranscriptPath $hook.transcript_path -Cwd $cwd -Reason 'pre-compact' -Agent (Get-BeyinAgent)
        Write-BeyinLog -Vault $vault -Message "pre-compact: oturum gunluk payini doldurdu ($pcSayac/$pcPay), is kuyruga alindi (proje=$cwdLeaf)"
        $pcAtla = $true
    } else {
        # Sayaci SIMDI artir: flush ayri bir surecte basliyor, sonucu
        # beklenmiyor. Fazla saymak (flush duserse) payi biraz erken
        # doldurur; eksik saymak payi tamamen etkisiz kilardi.
        $st.pcSayi = $pcSayac + 1
        $st.pcGun  = $pcBugun
        Set-BeyinSessionState -Paths $p -State $st
    }
}

if ($hook.transcript_path -and -not $pcAtla) {
    $ok = Start-BeyinScript -ScriptPath (Join-Path $p.Scripts 'flush.ps1') -Vault $vault -Params @{
        TranscriptPath = $hook.transcript_path
        Vault          = $vault
        Reason         = 'pre-compact'
        Agent          = (Get-BeyinAgent)
        ProjectPath    = $cwd
    }
    if ($ok) {
        Write-BeyinLog -Vault $vault -Message "pre-compact: flush baslatildi (trigger=$($hook.trigger), proje=$cwdLeaf, ajan=$(Get-BeyinAgent))"
    } else {
        Add-BeyinQueue -Paths $p -TranscriptPath $hook.transcript_path -Cwd $cwd -Reason 'pre-compact' -Agent (Get-BeyinAgent)
        Write-BeyinLog -Vault $vault -Message "pre-compact: flush baslatilamadi, is kuyruga alindi"
    }
}

# --- 2) 18:00 sonrasi derleyici denemesi (SessionEnd ile ayni 30 dk penceresi) ---
try {
    if ((Get-Date).Hour -ge 18) {
        $pending = @(Get-BeyinPendingDaylogs -Paths $p)
        if ($pending.Count -gt 0) {
            $attempt = Join-Path $p.ScrState 'last_compile_attempt'
            # KILITLI DAMGA (2026-09-16): session-start.ps1 / session-end.ps1 ile
            # AYNI kilit (counter.lock) ve AYNI sira. NEDEN: uc kanca ayni dosyayi
            # yaziyordu, yalniz session-start kilitliydi (engine.log 2026-09-04
            # 13:26:49 'last_compile_attempt ... being used by another process').
            # 30 dk kontrolu kilit ICINDE: es zamanli iki sikistirma iki derleyici
            # baslatmasin. Kilit 2 sn'de alinamazsa tetik atlanir; damga
            # yazilmadigi icin sonraki kanca yeniden dener. Codex'te bu kanca
            # 15 sn taniyor, 2 sn bekleme tavanin cok altinda.
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
                    Write-BeyinLog -Vault $vault -Message 'pre-compact: derleyici baslatildi'
                }
            }
        }
    }
} catch { }

exit 0
