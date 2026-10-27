# takim-kanca.Tests.ps1 - Takim modu (2026-10-12) kanca sozlesmesi: onay fiilleri, isci modu,
# adresli aktarim (sema v3), isci session-end brifingi, anlik teslim suzgeci.
#
# Her test GECICI vault'ta kosar (gercek vault'a aktarim/onay yazilmaz; canli oturumlara
# test mesaji dusmez). Kancalar vault'u kendi konumundan turettigi icin lib + kanca
# kopyalari gecici vault'tan calistirilir (kanca.Tests.ps1 New-KancaVault deseni).

$here  = Split-Path -Parent $MyInvocation.MyCommand.Path
$vault = Split-Path -Parent (Split-Path -Parent $here)
. (Join-Path $here 'lib.ps1')

function New-TakimVault {
    $tv = Join-Path $env:TEMP ('beyin-takim-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Force -Path (Join-Path $tv 'motor\hooks'), (Join-Path $tv 'motor\scripts\.state\sessions'), (Join-Path $tv 'motor\scripts\.state\team-runs'), (Join-Path $tv '80-memory'), (Join-Path $tv '10-command-center') | Out-Null
    foreach ($f in @('lib.ps1', 'session-start.ps1', 'prompt-counter.ps1', 'session-end.ps1', 'kill-guard-on.mjs')) { Copy-Item (Join-Path $here $f) (Join-Path $tv "motor\hooks\$f") }
    Set-Content -Path (Join-Path $tv '.beyin-version') -Value '1.0.0'
    Set-Content -Path (Join-Path $tv '80-memory\rules.md') -Value "# Kurallar`n`n- **kural:** test kurali."
    return $tv
}
function Invoke-TakimKanca([string]$Tv, [string]$Betik, [hashtable]$Payload, [hashtable]$Env = @{}) {
    $in  = Join-Path $env:TEMP ("takim-in-"  + [guid]::NewGuid().ToString('N') + '.json')
    $out = Join-Path $env:TEMP ("takim-out-" + [guid]::NewGuid().ToString('N') + '.json')
    [IO.File]::WriteAllText($in, ($Payload | ConvertTo-Json -Compress), (New-Object Text.UTF8Encoding $false))
    $eski = @{}
    foreach ($k in $Env.Keys) { $eski[$k] = [Environment]::GetEnvironmentVariable($k); [Environment]::SetEnvironmentVariable($k, $Env[$k]) }
    try {
        cmd /c "powershell -NoProfile -ExecutionPolicy Bypass -File `"$(Join-Path $Tv "motor\hooks\$Betik")`" < `"$in`" > `"$out`" 2>&1" | Out-Null
        $raw = [IO.File]::ReadAllText($out)
        if (-not $raw.Trim()) { return '' }
        try { return [string](ConvertFrom-Json $raw).hookSpecificOutput.additionalContext } catch { return $raw }
    } finally {
        foreach ($k in $Env.Keys) { [Environment]::SetEnvironmentVariable($k, $eski[$k]) }
        Remove-Item -LiteralPath $in, $out -Force -ErrorAction SilentlyContinue
    }
}
function Write-KosuFixture([hashtable]$Tp, [string]$RunId, [string]$Durum = 'planned') {
    $run = @{ schemaVersion = 1; runId = $RunId; status = $Durum; repoName = 'proj'; integrationBranch = "takim/$RunId"; updatedAt = (Get-Date).ToString('o')
              workers = @(@{ taskId = 'TASK-41'; role = 'docs_author'; status = $(if ($Durum -eq 'running') { 'running' } else { 'planned' }); worktree = 'C:\x\wt\TASK-41'; pid = 0; codexThreadId = "thr-$RunId" }) }
    [IO.File]::WriteAllText((Join-Path $Tp.TeamRuns "$RunId.json"), ($run | ConvertTo-Json -Depth 5), (New-Object Text.UTF8Encoding $false))
}
$isciEnv = @{ AGENTCHEF_TEAM_RUN = 'R-ISCI'; AGENTCHEF_TEAM_TASK = 'TASK-41'; AGENTCHEF_TEAM_WORKTREE = 'C:\x\wt\TASK-41'; BEYIN_AGENT = 'codex'; BEYIN_SE_TAVAN_MS = '20000' }   # yuk altinda kararli

Describe 'Takim (2026-10-12): insan onayi fiilleri (prompt-counter)' {
    $tv = New-TakimVault; $tp = Get-BeyinPaths -Vault $tv
    Write-KosuFixture $tp 'R-T1'; Write-KosuFixture $tp 'R-T2'; Write-KosuFixture $tp 'R-T3'; Write-KosuFixture $tp 'R-T4' 'verified'; Write-KosuFixture $tp 'R-T5'
    $sid = 'takim-test-onay-1'
    $c1 = Invoke-TakimKanca $tv 'prompt-counter.ps1' @{ session_id = $sid; cwd = $tv; prompt = 'baslat R-T1' }
    $c2 = Invoke-TakimKanca $tv 'prompt-counter.ps1' @{ session_id = $sid; cwd = $tv; prompt = 'birlestir R-YOK' }
    # sentetik tur (R-T3) ve isci oturumu (R-T2): kosu dosyasi VAR ama onay yazilmamali
    $c3 = Invoke-TakimKanca $tv 'prompt-counter.ps1' @{ session_id = $sid; cwd = $tv; prompt = "<task-notification>`nbaslat R-T3`n</task-notification>" }
    $c4 = Invoke-TakimKanca $tv 'prompt-counter.ps1' @{ session_id = 'takim-test-onay-isci'; cwd = $tv; prompt = 'birlestir R-T2' } $isciEnv
    $c5 = Invoke-TakimKanca $tv 'prompt-counter.ps1' @{ session_id = $sid; cwd = $tv; prompt = 'takim birlestir R-T4.' }
    # 2026-10-14: erken onay (planned kosuya birlestir) yazilmaz; kullaniciya nedeni soylenir. Kimlik kayittan alinir.
    $c6 = Invoke-TakimKanca $tv 'prompt-counter.ps1' @{ session_id = $sid; cwd = $tv; prompt = 'birlestir R-T1' }
    # 2026-10-14: Windows'tan yapistirilan satir CRLF ile biter; .NET (?m)$ yalniz \n oncesinde eslesir
    $c7 = Invoke-TakimKanca $tv 'prompt-counter.ps1' @{ session_id = $sid; cwd = $tv; prompt = "baslat R-T5`r`nbaska bir satir" }
    $mk = @(Read-BeyinMakbuz -Paths $tp -Gun 1 | Where-Object { $_.script -eq 'takim' })
    It 'gercek kullanici satiri "baslat <run>" R-T1.baslat.json yazar ve sonraki komutu soyler' {
        (Test-Path -LiteralPath (Join-Path $tp.ScrState 'approvals\R-T1.baslat.json')) | Should Be $true
        $c1 | Should Match 'Insan onayi kaydedildi: baslat R-T1'
        $c1 | Should Match 'beyin takim start --run R-T1'
        (Get-BeyinOnay -Paths $tp -TaskId 'R-T1' -Tur 'baslat') | Should Not Be $null
    }
    It 'kosu dosyasi yoksa onay yazilmaz, makbuz ONAY_ATLANDI' {
        (Test-Path -LiteralPath (Join-Path $tp.ScrState 'approvals\R-YOK.birlestir.json')) | Should Be $false
        @($mk | Where-Object { $_.outcome -eq 'ONAY_ATLANDI' -and [string]$_.note -like '*R-YOK*' }).Count | Should Be 1
    }
    It 'sentetik tur ve isci oturumu (AGENTCHEF_TEAM_TASK) onay SAYMAZ' {
        (Test-Path -LiteralPath (Join-Path $tp.ScrState 'approvals\R-T3.baslat.json')) | Should Be $false
        (Test-Path -LiteralPath (Join-Path $tp.ScrState 'approvals\R-T2.birlestir.json')) | Should Be $false
        ($c3 -notmatch 'Insan onayi kaydedildi') | Should Be $true
        ($c4 -notmatch 'Insan onayi kaydedildi') | Should Be $true
    }
    It '"takim birlestir <run>." bicimi de gecer; TASK onayi (onayla) bayt-bayt eski bicimde kalir' {
        (Test-Path -LiteralPath (Join-Path $tp.ScrState 'approvals\R-T4.birlestir.json')) | Should Be $true
        $c5 | Should Match 'beyin takim merge --run R-T4'
        $t = Add-BeyinOnay -Paths $tp -TaskId 'TASK-9' -Kanal 'sohbet'
        $ham = Get-Content -LiteralPath $t.Yol -Raw
        $ham | Should Match '^\{"v":1,"taskId":"TASK-9","nonce":"[0-9a-f]{12}","approvedAt":"[^"]+","kanal":"sohbet","ajan":"","session":"","kullanildi":"","kullanan":""\}\s*$'
        (Get-BeyinOnay -Paths $tp -TaskId 'TASK-9' -Tur 'baslat') | Should Be $null
    }
    It 'CRLF ile biten onay satiri da kaydedilir' {
        (Test-Path -LiteralPath (Join-Path $tp.ScrState 'approvals\R-T5.baslat.json')) | Should Be $true
        $c7 | Should Match 'Insan onayi kaydedildi: baslat R-T5'
    }
    It 'birlestir yalniz dogrulanmis (verified) kosu icin yazilir; erken satir reddedilir ve nedeni soylenir' {
        (Test-Path -LiteralPath (Join-Path $tp.ScrState 'approvals\R-T1.birlestir.json')) | Should Be $false
        $c6 | Should Match "kaydedilmedi: kosu su an 'planned'"
        @($mk | Where-Object { $_.outcome -eq 'ONAY_ATLANDI' -and [string]$_.note -like '*R-T1*beklenen verified*' }).Count | Should Be 1
    }
    Remove-Item -Recurse -Force $tv -ErrorAction SilentlyContinue
}

Describe 'Takim (2026-10-12): isci modu session-start, sef isletim satiri' {
    $tv = New-TakimVault; $tp = Get-BeyinPaths -Vault $tv
    $proje = Join-Path $tv 'wt-proje'; New-Item -ItemType Directory -Force -Path $proje | Out-Null
    $sid = 'takim-test-ss-isci'
    $ctx = Invoke-TakimKanca $tv 'session-start.ps1' @{ session_id = $sid; cwd = $proje; hook_event_name = 'SessionStart'; source = 'startup' } $isciEnv
    $st = Get-BeyinSessionState -Paths $tp -SessionId $sid
    $mk = @(Read-BeyinMakbuz -Paths $tp -Gun 1 | Where-Object { $_.script -eq 'session-start' -and $_.key -eq $sid })
    It 'isci: [Hafiza: Takim] blogu var; vault baglami ve "Vault DISINDA" satiri YOK; Kurallar var' {
        $ctx | Should Match '\[Hafiza: Takim \| kosu R-ISCI \| kart TASK-41 \| isci\]'
        $ctx | Should Match 'git commit/push/checkout/worktree/branch YAPMA'
        $ctx | Should Match 'C:\\x\\wt\\TASK-41'
        ($ctx -notmatch 'Vault DISINDA') | Should Be $true
        ($ctx -notmatch '\[Hafiza: Guncel Baglam\]') | Should Be $true
        $ctx | Should Match '\[Hafiza: Kurallar\]'
    }
    It 'isci: oturum durumunda takimRun/takimKart; takim-oturum jsonl yazildi; makbuz reason isci; toparlama atlandi' {
        [string]$st.takimKart | Should Be 'TASK-41'
        [string]$st.takimRun | Should Be 'R-ISCI'
        $jl = Join-Path $tp.TakimOturum 'R-ISCI.jsonl'
        (Test-Path -LiteralPath $jl) | Should Be $true
        (Get-Content -LiteralPath $jl -Raw) | Should Match '"kart":"TASK-41"'
        (Get-Content -LiteralPath $jl -Raw) | Should Match "`"sessionId`":`"$sid`""
        $mk.Count | Should Be 1
        [string]$mk[0].reason | Should Be 'isci'
        (Get-Content -LiteralPath (Join-Path $tp.ScrState 'engine.log') -Raw) | Should Match 'takim iscisi \(R-ISCI/TASK-41\), toparlama atlandi'
        ((Get-BeyinTakimIsciler -Paths $tp)[$sid]).Kart | Should Be 'TASK-41'
    }
    It 'sef (isci degil): isletim satirinda "Takim:" ozeti ve bekleyen onay (<=200 karakter)' {
        Write-KosuFixture $tp 'R-SEF' 'planned'
        $ctx2 = Invoke-TakimKanca $tv 'session-start.ps1' @{ session_id = 'takim-test-ss-sef'; cwd = $tv; hook_event_name = 'SessionStart'; source = 'startup' }
        $ctx2 | Should Match 'Takim: 1 kosu acik \(R-SEF planned 0/1 isci\); onay bekliyor: baslat R-SEF\.'
        $ctx2 | Should Match '\[Hafiza: Guncel Baglam\]|\[Hafiza Protokolu\]|Vault DISINDA|\[Hafiza: Kurallar\]'
        ($ctx2 -notmatch '\[Hafiza: Takim \|') | Should Be $true
        $d = Get-BeyinTakimDurum -Paths $tp
        ($d.Satir.Length -le 200) | Should Be $true
    }
    Remove-Item -Recurse -Force $tv -ErrorAction SilentlyContinue
}

Describe 'Takim (2026-10-12): adresli aktarim (sema v3)' {
    $tv = New-TakimVault; $tp = Get-BeyinPaths -Vault $tv
    $hGenel = Add-BeyinHandoff -Paths $tp -Metin 'GENEL-CODEX' -Kime codex -FromAgent claude -GorunumYok
    $hIsci  = Add-BeyinHandoff -Paths $tp -Metin 'ISCIYE-OZEL' -Kime codex -FromAgent claude -ToWorker 'task-41' -GorunumYok
    $hBaska = Add-BeyinHandoff -Paths $tp -Metin 'BASKA-ISCI' -Kime codex -FromAgent claude -ToWorker 'TASK-42' -GorunumYok
    $hSef   = Add-BeyinHandoff -Paths $tp -Metin 'ISCIDEN-SEFE' -Kime claude -FromAgent codex -FromWorker 'TASK-41' -GorunumYok
    $hRet   = Add-BeyinHandoff -Paths $tp -Metin 'yanlis' -Kime claude -FromAgent claude -ToWorker 'TASK-41' -GorunumYok
    It 'Add-BeyinHandoff: -ToWorker v3 kayit (buyuk harf), claude hedefine isci adresi reddedilir, v2 kayit degismez' {
        $hIsci.Kod | Should Be 'KAYDEDILDI'
        $k = Get-BeyinHandoff -Paths $tp -Id $hIsci.Id
        [int]$k.v | Should Be 3
        [string]$k.toWorker | Should Be 'TASK-41'
        [int](Get-BeyinHandoff -Paths $tp -Id $hGenel.Id).v | Should Be 2
        $hRet.Kod | Should Be 'HEDEF_GECERSIZ'
        [string](Get-BeyinHandoff -Paths $tp -Id $hSef.Id).from.worker | Should Be 'TASK-41'
    }
    It 'Get-BeyinHandoffAcik -Isci: isci yalniz kendi kartini alir; sef toWorker''li mesaji almaz' {
        $isci = @(Get-BeyinHandoffAcik -Paths $tp -Kime codex -Isci 'TASK-41' | ForEach-Object { $_.question })
        $sef  = @(Get-BeyinHandoffAcik -Paths $tp -Kime codex | ForEach-Object { $_.question })
        ($isci -join ',') | Should Be 'ISCIYE-OZEL'
        ($sef -join ',') | Should Be 'GENEL-CODEX'
    }
    It 'prompt-counter isci: adresli mesaj bir kez gosterilir, genel mesaj gelmez; sefe isciden gelen "codex/TASK-41" etiketli' {
        $c1 = Invoke-TakimKanca $tv 'prompt-counter.ps1' @{ session_id = 'takim-test-pc-isci'; cwd = $tv; prompt = 'isci devam ediyor, bu bir brief satiri' } $isciEnv
        $c2 = Invoke-TakimKanca $tv 'prompt-counter.ps1' @{ session_id = 'takim-test-pc-isci'; cwd = $tv; prompt = 'isci devam ediyor, ikinci tur' } $isciEnv
        $c1 | Should Match 'ISCIYE-OZEL'
        ($c1 -notmatch 'GENEL-CODEX') | Should Be $true
        ($c1 -notmatch 'BASKA-ISCI') | Should Be $true
        ($c2 -notmatch 'ISCIYE-OZEL') | Should Be $true
        $c3 = Invoke-TakimKanca $tv 'prompt-counter.ps1' @{ session_id = 'takim-test-pc-sef'; cwd = $tv; prompt = 'sef okuyor, uzun bir kullanici mesaji' } @{ BEYIN_AGENT = 'claude' }
        $c3 | Should Match '\(codex/TASK-41\): ISCIDEN-SEFE'
    }
    It 'aktarimlar.md gorunumunde codex/TASK-41 -> claude ve claude -> codex@TASK-41' {
        $md = Update-BeyinAktarimlarMd -Paths $tp
        $icerik = Get-Content -LiteralPath $md.Yol -Raw -Encoding UTF8
        $icerik | Should Match 'codex/TASK-41 -> claude'
        $icerik | Should Match 'claude -> codex@TASK-41'
    }
    It 'Close-BeyinHandoff: tek atimlik devir kapandiginda turetilmis acik aktarim gorunumu yenilenir' {
        $h = Add-BeyinHandoff -Paths $tp -Metin 'tek-atimlik devir' -Kime codex -Kind 'devir' -FromAgent codex -Proje 'proj' -GorunumYok
        $null = Update-BeyinAktarimlarMd -Paths $tp
        $once = Get-Content -LiteralPath (Join-Path $tv '10-command-center\aktarimlar.md') -Raw -Encoding UTF8
        ($once -match [regex]::Escape($h.Id)) | Should Be $true
        $kapatildi = Close-BeyinHandoff -Paths $tp -Id $h.Id -DoneBy 'gosterildi (tek atimlik devir)'
        $sonra = Get-Content -LiteralPath (Join-Path $tv '10-command-center\aktarimlar.md') -Raw -Encoding UTF8
        $acikBolum = [regex]::Match($sonra, '(?ms)^## Acik \(\d+\)(.*?)(?=^## Kapali)').Groups[1].Value
        $kapatildi | Should Be $true
        ($acikBolum -match [regex]::Escape($h.Id)) | Should Be $false
        $sonra | Should Match ([regex]::Escape($h.Id))
        $sonra | Should Match '## Acik \(4\)'
        $sonra | Should Match '## Kapali \(son 1\)'
    }
    It 'kill-guard-on.mjs anlik teslim: isci yalniz toWorker mesajini alir, sef toWorker mesajini almaz' {
        if (-not (Get-Command node -ErrorAction SilentlyContinue)) { Set-TestInconclusive 'node yok'; return }
        $mjs = Join-Path $tv 'motor\hooks\kill-guard-on.mjs'
        $in = Join-Path $env:TEMP ("takim-anlik-" + [guid]::NewGuid().ToString('N') + '.json')
        [IO.File]::WriteAllText($in, (@{ session_id = 'anlik-isci'; tool_name = 'Bash'; tool_input = @{ command = 'git status' }; cwd = 'D:\proje\x' } | ConvertTo-Json -Compress), (New-Object Text.UTF8Encoding $false))
        $inSef = Join-Path $env:TEMP ("takim-anlik-sef-" + [guid]::NewGuid().ToString('N') + '.json')
        [IO.File]::WriteAllText($inSef, (@{ session_id = 'anlik-sef'; tool_name = 'Bash'; tool_input = @{ command = 'git status' }; cwd = 'D:\proje\x' } | ConvertTo-Json -Compress), (New-Object Text.UTF8Encoding $false))
        $eskiV = $env:BEYIN_VAULT; $eskiT = $env:AGENTCHEF_TEAM_TASK; $env:BEYIN_VAULT = $tv
        try {
            $env:AGENTCHEF_TEAM_TASK = 'TASK-41'
            $oIsci = [string](cmd /c "node `"$mjs`" --codex < `"$in`"")
            $env:AGENTCHEF_TEAM_TASK = $null
            $oSef = [string](cmd /c "node `"$mjs`" --codex < `"$inSef`"")
        } finally { $env:BEYIN_VAULT = $eskiV; $env:AGENTCHEF_TEAM_TASK = $eskiT; Remove-Item -LiteralPath $in, $inSef -Force -ErrorAction SilentlyContinue }
        $oIsci | Should Match 'ISCIYE-OZEL'
        ($oIsci -notmatch 'GENEL-CODEX') | Should Be $true
        ($oIsci -notmatch 'BASKA-ISCI') | Should Be $true
        $oSef | Should Match 'GENEL-CODEX'
        ($oSef -notmatch 'ISCIYE-OZEL') | Should Be $true
    }
    Remove-Item -Recurse -Force $tv -ErrorAction SilentlyContinue
}

Describe 'Takim (2026-10-12): isci session-end' {
    $tv = New-TakimVault; $tp = Get-BeyinPaths -Vault $tv
    $sid = 'takim-test-se-isci'
    $tr = Join-Path $tv 'sahte-transkript.jsonl'; Set-Content -Path $tr -Value '{"type":"user"}'
    Set-BeyinSessionState -Paths $tp -State @{ start = 1; prompts = 3; cwd = $tv; agent = 'codex'; takimRun = 'R-ISCI'; takimKart = 'TASK-41'; key = (Get-BeyinSessionKey -SessionId $sid) }
    $null = Invoke-TakimKanca $tv 'session-end.ps1' @{ session_id = $sid; cwd = $tv; transcript_path = $tr; hook_event_name = 'SessionEnd' } $isciEnv
    $kuyruk = @(Get-ChildItem -LiteralPath $tp.Queue -Filter '*.json' -File | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json })
    $acik1 = @(Get-BeyinHandoffListe -Paths $tp)
    # ikinci kapanis (resume sonrasi): ayni ref ile ikinci brifing YAZILMAZ
    Set-BeyinSessionState -Paths $tp -State @{ start = 1; prompts = 3; cwd = $tv; agent = 'codex'; takimRun = 'R-ISCI'; takimKart = 'TASK-41'; key = (Get-BeyinSessionKey -SessionId $sid) }
    $null = Invoke-TakimKanca $tv 'session-end.ps1' @{ session_id = $sid; cwd = $tv; transcript_path = $tr; hook_event_name = 'SessionEnd' } $isciEnv
    $acik2 = @(Get-BeyinHandoffListe -Paths $tp)
    $mk = @(Read-BeyinMakbuz -Paths $tp -Gun 1 | Where-Object { $_.script -eq 'session-end' -and $_.key -eq (Get-BeyinSessionKey -SessionId $sid) })
    It 'kuyruk ogesi reason takim-TASK-41, ajan codex' {
        $kuyruk.Count | Should Be 1
        [string]$kuyruk[0].reason | Should Be 'takim-TASK-41'
        [string]$kuyruk[0].agent | Should Be 'codex'
    }
    It 'sefe tek brifing: ref takim:R-ISCI:TASK-41, from.worker TASK-41, ikinci kapanista tekrar yok' {
        $acik1.Count | Should Be 1
        [string]$acik1[0].ref | Should Be 'takim:R-ISCI:TASK-41'
        [string]$acik1[0].to | Should Be 'claude'
        [string]$acik1[0].kind | Should Be 'brifing'
        [string]$acik1[0].from.worker | Should Be 'TASK-41'
        $acik1[0].question | Should Match 'beyin takim collect --run R-ISCI'
        $acik2.Count | Should Be 1
    }
    It 'makbuz TAKIM_ISCI_BITTI dusuyor, yansima isareti birakilmiyor' {
        @($mk | Where-Object { $_.outcome -eq 'TAKIM_ISCI_BITTI' }).Count | Should Be 2
        @(Get-ChildItem -LiteralPath $tp.Reflect -Filter '*.txt' -File -ErrorAction SilentlyContinue).Count | Should Be 0
    }
    Remove-Item -Recurse -Force $tv -ErrorAction SilentlyContinue
}
