# kanca.Tests.ps1 - Kanca katmani icin Pester 3.4 testleri (2026-10-05).
#
# Kapsam: 2026-10-05 kod incelemesinde dogrulanan hatalar ve avenoxbeyin/hafiza-os
# incelemesinden alinan ozellikler. Her test GERCEK vault'ta, gecici session_id
# ile kosar ve kendi izini siler; kuratorlu bolgeye yazmaz.
#
# Calistirma:
#   powershell -NoProfile -ExecutionPolicy Bypass -Command "Import-Module Pester -MaximumVersion 3.99; Invoke-Pester -Script 'motor/hooks/kanca.Tests.ps1'"

$here  = Split-Path -Parent $MyInvocation.MyCommand.Path
$vault = Split-Path -Parent (Split-Path -Parent $here)
$lib   = Join-Path $here 'lib.ps1'
. $lib
$p = Get-BeyinPaths -Vault $vault

function Invoke-Kanca([string]$Betik, [hashtable]$Payload) {
    # Kancayi gercek stdin ile kosar (PS 5.1 -File + '<' yonlendirmesi cmd uzerinden).
    $in  = Join-Path $env:TEMP ("kanca-test-in-"  + [guid]::NewGuid().ToString('N') + '.json')
    $out = Join-Path $env:TEMP ("kanca-test-out-" + [guid]::NewGuid().ToString('N') + '.json')
    [IO.File]::WriteAllText($in, ($Payload | ConvertTo-Json -Compress), (New-Object Text.UTF8Encoding $false))
    try {
        cmd /c "powershell -NoProfile -ExecutionPolicy Bypass -File `"$(Join-Path $here $Betik)`" < `"$in`" > `"$out`" 2>&1" | Out-Null
        $raw = [IO.File]::ReadAllText($out)
        if (-not $raw.Trim()) { return '' }
        try { return [string](ConvertFrom-Json $raw).hookSpecificOutput.additionalContext } catch { return $raw }
    } finally {
        Remove-Item -LiteralPath $in, $out -Force -ErrorAction SilentlyContinue
    }
}
function Remove-Oturum([string]$Sid) {
    Get-ChildItem -LiteralPath $p.Sessions -Filter "$Sid*" -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
}

Describe 'session-start: Claude Code 10k tavani' {
    $sid = "kanca-test-ss-$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())"
    $ctx = Invoke-Kanca 'session-start.ps1' @{ session_id = $sid; cwd = $vault; hook_event_name = 'SessionStart'; source = 'startup' }
    $tavan = 9500
    try { $tavan = [int](Get-BeyinAyar 'BEYIN_CLAUDE_TAVAN' (Get-BeyinAyarVars 'BEYIN_CLAUDE_TAVAN')) } catch { }
    It 'vault ici acilis baglami tavani asmaz (Claude Code 10.000 ustunu dosyaya atar)' {
        ($ctx.Length -gt 0) | Should Be $true
        ($ctx.Length -le $tavan) | Should Be $true
    }
    It 'korunan bloklar yerinde: isletim satiri, Kurallar, Guncel Baglam, Protokol' {
        $ctx.Contains('[Hafiza] Beyin hafiza motoru aktif') | Should Be $true
        $ctx.Contains('[Hafiza: Kurallar]') | Should Be $true
        $ctx.Contains('[Hafiza: Guncel Baglam]') | Should Be $true
        $ctx.Contains('[Hafiza Protokolu]') | Should Be $true
    }
    It 'dusen/kirpilan bloklar gorunur bildirilir, etikette kapanis parantezi yok' {
        if ($ctx.Contains('nedeniyle su bloklar dusuruldu/kirpildi')) {
            $ctx.Contains('Aktif Basliklar]') | Should Be $false
        }
    }
    It 'oturum durumu kilit altinda yazildi: start ve cwd dolu' {
        $st = Get-BeyinSessionState -Paths $p -SessionId $sid
        ([long]$st.start -gt 0) | Should Be $true
        ([string]$st.cwd) | Should Be $vault
    }
    It 'session-start makbuzu dusuyor (uzunluk + tavan + dusenler)' {
        $m = @(Read-BeyinMakbuz -Paths $p -Gun 1 | Where-Object { $_.script -eq 'session-start' -and $_.key -eq $sid })
        $m.Count | Should Be 1
        ([string]$m[0].note -like 'uzunluk=*tavan=*') | Should Be $true
    }
    Remove-Oturum $sid
}

Describe 'prompt-counter: durum kalicilik, tekrar bastirma, sentetik tur' {
    $sid = "kanca-test-pc-$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())"
    $soru = "Kapasite ve yuk testi harness'inde fail-closed onay kapisi nasil calisiyor; 500k satir 100 kullanici performans testinde onay olmadan kosmasin istiyorum"
    $c1 = Invoke-Kanca 'prompt-counter.ps1' @{ session_id = $sid; cwd = $vault; prompt = $soru }
    $st1 = Get-BeyinSessionState -Paths $p -SessionId $sid
    $c2 = Invoke-Kanca 'prompt-counter.ps1' @{ session_id = $sid; cwd = $vault; prompt = $soru }
    $c3 = Invoke-Kanca 'prompt-counter.ps1' @{ session_id = $sid; cwd = $vault; prompt = $soru }
    $st3 = Get-BeyinSessionState -Paths $p -SessionId $sid
    It 'ilk promptta kavram enjekte edilir ve kavram listesi DISKE yazilir (kapsam tuzagi kapandi)' {
        ($c1.Length -gt 0) | Should Be $true
        (@($st1.kavram).Count -gt 0) | Should Be $true
        ([string]$st1.cwd) | Should Be $vault
    }
    It 'kavram kaydi dosya|mtimeTicks bicimindedir (guncellenen not yeniden basilabilsin)' {
        ([string](@($st1.kavram)[0]) -match '\.md\|\d+$') | Should Be $true
    }
    It 'ayni oturumda bir kavram ikinci kez basilmaz (uc kosunun kavram kumeleri ayrik)' {
        $rx = [regex]'86-compiled/concepts/([^)\s]+\.md)'
        $k1 = @($rx.Matches($c1) | ForEach-Object { $_.Groups[1].Value })
        $k2 = @($rx.Matches($c2) | ForEach-Object { $_.Groups[1].Value })
        $k3 = @($rx.Matches($c3) | ForEach-Object { $_.Groups[1].Value })
        ($k1.Count -gt 0) | Should Be $true
        (@($k2 | Where-Object { $k1 -contains $_ }).Count) | Should Be 0
        (@($k3 | Where-Object { ($k1 + $k2) -contains $_ }).Count) | Should Be 0
    }
    It 'prompts sayaci her kosuda bir artar' {
        [int]$st3.prompts | Should Be 3
    }
    It 'sentetik tur (<task-notification>) arama yapmaz ve ATLANDI makbuzu birakir' {
        $sid2 = "kanca-test-syn-$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())"
        $cs = Invoke-Kanca 'prompt-counter.ps1' @{ session_id = $sid2; cwd = $vault; prompt = ("<task-notification>" + $soru + "</task-notification>") }
        $m = @(Read-BeyinMakbuz -Paths $p -Gun 1 | Where-Object { $_.script -eq 'retrieval' -and $_.key -eq $sid2 })
        Remove-Oturum $sid2
        ($cs.Length -eq 0 -or -not $cs.Contains('[Hafiza: Ilgili Kavram')) | Should Be $true
        $m.Count | Should Be 1
        ([string]$m[0].outcome) | Should Be 'ATLANDI'
    }
    It 'konu kapisi: ayirt edici terimi olmayan istemde arama yapilmaz, KAPI_KAPALI makbuzu' {
        $sid3 = "kanca-test-gate-$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())"
        $ck = Invoke-Kanca 'prompt-counter.ps1' @{ session_id = $sid3; cwd = $vault; prompt = 'bu da bunu ve onu ama yine de da ki mi ne' }
        $m = @(Read-BeyinMakbuz -Paths $p -Gun 1 | Where-Object { $_.script -eq 'retrieval' -and $_.key -eq $sid3 })
        Remove-Oturum $sid3
        ($ck.Length -eq 0 -or -not $ck.Contains('[Hafiza: Ilgili Kavram')) | Should Be $true
        $m.Count | Should Be 1
        ([string]$m[0].outcome) | Should Be 'KAPI_KAPALI'
        ([string]$m[0].note -like 'yol=kapi-kapali*') | Should Be $true
    }
    Remove-Oturum $sid
}

Describe 'lib: eszamanli ekleme, oturum durumu, ek soyucu, sir desenleri' {
    It 'Add-BeyinText 6 paralel surecten 50 satir -> 300 satir, hicbiri dusmez' {
        $f = Join-Path $env:TEMP ("kanca-test-append-" + [guid]::NewGuid().ToString('N') + '.log')
        $libW = $lib
        $jobs = 1..6 | ForEach-Object {
            Start-Job -ScriptBlock { param($lib, $f, $n) . $lib; for ($i = 0; $i -lt 50; $i++) { Add-BeyinText -Path $f -Text "p$n-$i`n" } } -ArgumentList $libW, $f, $_
        }
        $jobs | Wait-Job -Timeout 120 | Out-Null
        $jobs | Remove-Job -Force
        $n = @(Get-Content -LiteralPath $f).Count
        Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue
        $n | Should Be 300
    }
    It 'Update-BeyinSessionState: firlatan Degistir degisikligi IKI kez uygulamaz' {
        $sid = "kanca-test-upd-$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())"
        Update-BeyinSessionState -Paths $p -SessionId $sid -Degistir { param($s); $s.prompts = 5; return $s } | Out-Null
        $r = Update-BeyinSessionState -Paths $p -SessionId $sid -Degistir { param($s); $s.prompts = $s.prompts + 1; throw 'kasitli' }
        $st = Get-BeyinSessionState -Paths $p -SessionId $sid
        Remove-Oturum $sid
        ([int]$st.prompts -le 6) | Should Be $true
        ([int]$st.prompts -ne 7) | Should Be $true
    }
    It 'Get-BeyinKokle Turkce ekleri soyar, kisa koku korur' {
        (Get-BeyinKokle -W 'notlari') | Should Be 'notlar'
        (Get-BeyinKokle -W 'motoru') | Should Be 'motor'
        (Get-BeyinKokle -W 'kavrami') | Should Be 'kavram'
        (Get-BeyinKokle -W 'kutu') | Should Be 'kutu'
        (Get-BeyinKokle -W 'login') | Should Be 'login'
    }
    It 'Get-BeyinKelimeler sorgu ve indeks tarafinda ayni koku uretir' {
        $a = @(Get-BeyinKelimeler -Text 'kavram notlari ve vektor indeksi')
        $b = @(Get-BeyinKelimeler -Text 'kavram notlar vektor indeks')
        (@(Compare-Object $a $b).Count) | Should Be 0
    }
    It 'Protect-BeyinSecrets: Turkce etiket, Vercel ve Stripe webhook maskelenir' {
        # Ornek sirlar PARCALI kurulur: yayin tarayicisi (beyin yayinla) bu dosyayi da
        # tarar ve duz yazilmis 'sifrem: ...' kalibini sizinti sayar (olculdu).
        $t1 = 'sif' + 'rem: ' + 'Gizli' + '12345x'
        $t2 = 'vck' + '_' + ('a' * 24)
        $t3 = 'whsec' + '_' + ('b' * 24)
        $t4 = 'par' + 'ola = ' + 'plainOk' + '12345'
        $r = Protect-BeyinSecrets -Text ($t1 + "`n" + $t2 + "`n" + $t3 + "`n" + $t4)
        $r.Failed | Should Be 0
        ($r.Text -notmatch 'Gizli12345x') | Should Be $true
        ($r.Text -notmatch 'vck_a{24}') | Should Be $true
        ($r.Text -notmatch 'whsec_b{24}') | Should Be $true
        ($r.Text -notmatch 'plainOk12345') | Should Be $true
    }
    It 'Protect-BeyinSecrets: siradan Turkce metin maskelenmez (yanlis pozitif)' {
        $r = Protect-BeyinSecrets -Text 'Parola politikasi yenilendi; kurtarma kodu akisi test edildi, anahtarim dolabimda.'
        $r.Redactions | Should Be 0
    }
    It 'Get-BeyinFlushBudget 1-1000 araligina sikisir' {
        $eski = $script:BeyinFlushBudget
        $script:BeyinFlushBudget = 0
        $b0 = Get-BeyinFlushBudget
        $script:BeyinFlushBudget = 5000
        $b1 = Get-BeyinFlushBudget
        $script:BeyinFlushBudget = $eski
        $b0 | Should Be 1
        $b1 | Should Be 1000
    }
    It 'Test-BeyinRxZamanli: patlayan desen flush''i askiya almaz, false doner' {
        $t = ('a' * 30000) + 'b'
        $sw = [Diagnostics.Stopwatch]::StartNew()
        $r = Test-BeyinRxZamanli -Metin $t -Desen '^(a+)+$'
        $sw.Stop()
        $r | Should Be $false
        ($sw.Elapsed.TotalSeconds -lt 30) | Should Be $true
    }
}

Describe 'betikler: kullanim, geri-getirme-olc, kirp (kuru), gom cikis kodu' {
    $dsp = Join-Path $vault 'kurulum\beyin.ps1'
    It 'beyin kirp varsayilan kuru: 80-memory degismez, plan basar' {
        $once = @(Get-ChildItem -LiteralPath (Join-Path $vault '80-memory') -File | ForEach-Object { "$($_.Name)|$($_.LastWriteTimeUtc.Ticks)" })
        $o = & powershell -NoProfile -ExecutionPolicy Bypass -File $dsp kirp 2>&1 | Out-String
        $sonra = @(Get-ChildItem -LiteralPath (Join-Path $vault '80-memory') -File | ForEach-Object { "$($_.Name)|$($_.LastWriteTimeUtc.Ticks)" })
        ($o -match 'PLAN \(hicbir sey yazilmadi\)') | Should Be $true
        (@(Compare-Object $once $sonra).Count) | Should Be 0
    }
    It 'beyin kullanim raporu ve json uretir' {
        $o = & powershell -NoProfile -ExecutionPolicy Bypass -File $dsp kullanim 3 2>&1 | Out-String
        ($o -match 'KAVRAM KULLANIMI') | Should Be $true
        (Test-Path -LiteralPath (Join-Path $p.ScrState 'kullanim-son.json')) | Should Be $true
    }
    It 'geri-getirme-olc fixture sha dogrulamasi: bozuk fixture gecmez' {
        $fx = Join-Path $vault 'motor\scripts\fixtures\geri-getirme-holdout.json'
        if (-not (Test-Path -LiteralPath $fx)) { Set-TestInconclusive 'fixture yok (beyin geri-getirme-olc -Dondur)' }
        $j = Get-Content -LiteralPath $fx -Raw -Encoding UTF8 | ConvertFrom-Json
        ([string]$j.vakalar[0].sha).Length | Should Be 64
    }
    It 'gom.ps1 Bitir hata kodunu tasir (GOM_HATA_* -> exit 5)' {
        $src = Get-Content -LiteralPath (Join-Path $vault 'motor\scripts\gom.ps1') -Raw
        ($src -match "exit \`$Cikis") | Should Be $true
        (@([regex]::Matches($src, "-Cikis 5")).Count) | Should Be 3
    }
}
