# merkez-veri.ps1 - Beyin merkez ekraninin veri katmani. HICBIR SEY YAZMAZ.
#
# NEDEN: koşu panosu tek koşuyu gosteriyordu; "su an kim ne yapiyor" sorusu icin canli,
# bekci, pano, aktar, takim durum ve maliyet ayri ayri calistiriliyordu. Bu dosya hepsini
# TEK anlik goruntude toplar; merkez.ps1 yalniz cizer.
#
# DURUM KURALI (AgentSpace ofis spec'indeki oncelik zincirinden kavram, kod degil):
# her ajanin durumu kanita gore TEK yerde turetilir ve yanina KAYNAGI ile BAYAT bayragi
# yazilir. Boylece "calisiyor gorunen ama olmus" ajan ekranda gizlenmez.
#   lider: surec olmus -> kapali | son kayit 'tur bitti' -> bosta | nabiz < 120 sn (arac/dusunce suruyorsa
#          15 dk) -> calisiyor | kart in_progress/review/blocked -> calisiyor/inceleme/engelli (kart verilirse)
#          surec canli -> bosta | nabiz < kapanma esigi -> bosta | kanit yok -> kapali
#   isci : kosu kaydindaki isci durumu + gozetmen nabzi + son olay zamani
#
# Kullanim (dot-source):  . merkez-veri.ps1 ; $a = Get-MerkezAnlik -Paths $p

$script:MerkezCalismaSn = 120      # bu kadar saniye icinde nabiz -> calisiyor
$script:MerkezKapanmaSn = 7200     # bu kadar saniyedir sessiz lider kapali sayilir (pid yoksa)
$script:MerkezGosterKapaliSn = 1800 # kapanan lider bu kadar sure sonuk satirla gorunur
$script:MerkezIsciSessizSn = 600   # calisan isciden 10 dk olay gelmediyse bayat
$script:MerkezAracSn = 900         # son kayit arac/dusunce ve surec canliysa 15 dk boyunca calisiyor (uzun test/derleme)

function Get-MerkezDurum {
    # Saf islev (test edilir). Girdi: @{ Tur='lider'|'isci'; SurecCanli=$true|$false|$null; NabizSn=<double, -1 bilinmiyor>;
    # KartDurum; IsciDurum; Verdict; GozetmenDurdu }. Cikti: @{ Durum; Kaynak; Bayat }.
    param([hashtable]$K)
    $nabiz = $(if ($null -ne $K.NabizSn) { [double]$K.NabizSn } else { -1 })
    if ($K.Tur -eq 'isci') {
        $d = [string]$K.IsciDurum; $v = [string]$K.Verdict
        if ($d -in @('queued', 'spawning', 'running')) {
            if ($K.GozetmenDurdu) { return @{ Durum = 'engelli'; Kaynak = 'gozetmen'; Bayat = $true } }
            if ($K.SurecCanli -eq $false -and $d -eq 'running') { return @{ Durum = 'engelli'; Kaynak = 'surec'; Bayat = $true } }
            return @{ Durum = 'calisiyor'; Kaynak = 'kosu'; Bayat = [bool]($nabiz -ge $script:MerkezIsciSessizSn) }
        }
        switch ($d) {
            'planned'      { return @{ Durum = 'bekliyor'; Kaynak = 'kosu'; Bayat = $false } }
            'paused_limit' { return @{ Durum = 'duraklatildi'; Kaynak = 'kota'; Bayat = $false } }
            'aborted'      { return @{ Durum = 'kapali'; Kaynak = 'kosu'; Bayat = $false } }
        }
        if ($d -in @('failed', 'timed_out', 'scope_violation', 'rejected_content', 'conflict')) { return @{ Durum = 'engelli'; Kaynak = 'kosu'; Bayat = $false } }
        if ($d -in @('finished', 'collected', 'integrated')) {
            if ($v -in @('fail', 'blocked')) { return @{ Durum = 'engelli'; Kaynak = 'karar'; Bayat = $false } }
            if ($v -in @('partial', 'warn')) { return @{ Durum = 'inceleme'; Kaynak = 'karar'; Bayat = $false } }
            return @{ Durum = 'bitti'; Kaynak = 'kosu'; Bayat = $false }
        }
        return @{ Durum = 'bosta'; Kaynak = 'kanit-yok'; Bayat = $false }
    }
    # lider
    if ($K.SurecCanli -eq $false) { return @{ Durum = 'kapali'; Kaynak = 'surec'; Bayat = $false } }
    $et = [string]$K.Etkinlik
    if ($et -eq 'bekliyor' -and $K.SurecCanli -ne $false) { return @{ Durum = 'bosta'; Kaynak = 'tur-bitti'; Bayat = $false } }
    $pencere = $(if ($et -in @('arac', 'dusunce') -and $K.SurecCanli -eq $true) { $script:MerkezAracSn } else { $script:MerkezCalismaSn })
    if ($nabiz -ge 0 -and $nabiz -lt $pencere) { return @{ Durum = 'calisiyor'; Kaynak = $(if ($pencere -gt $script:MerkezCalismaSn -and $nabiz -ge $script:MerkezCalismaSn) { 'uzun-arac' } else { 'nabiz' }); Bayat = $false } }
    switch ([string]$K.KartDurum) {
        'in_progress' { return @{ Durum = 'calisiyor'; Kaynak = 'kart'; Bayat = $true } }
        'review'      { return @{ Durum = 'inceleme'; Kaynak = 'kart'; Bayat = $false } }
        'blocked'     { return @{ Durum = 'engelli'; Kaynak = 'kart'; Bayat = $false } }
    }
    if ($K.SurecCanli -eq $true) { return @{ Durum = 'bosta'; Kaynak = 'surec'; Bayat = $false } }
    if ($nabiz -ge 0 -and $nabiz -lt $script:MerkezKapanmaSn) { return @{ Durum = 'bosta'; Kaynak = 'nabiz'; Bayat = $false } }
    return @{ Durum = 'kapali'; Kaynak = 'kanit-yok'; Bayat = $false }
}

function Read-MerkezPaylasimli([string]$Yol) {
    # Yazani asla engellemez (ReadWrite+Delete paylasimi; takim-izle.ps1 ile ayni kural).
    $fs = [System.IO.File]::Open($Yol, 'Open', 'Read', ([System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete))
    try { $sr = New-Object System.IO.StreamReader($fs, [Text.Encoding]::UTF8, $true); return $sr.ReadToEnd() } finally { $fs.Dispose() }
}

function Read-MerkezJsonOnb([string]$Yol, [hashtable]$Onbellek) {
    # Dosya boyu ve zamani degismediyse onceki ayristirma doner (1,5 sn'lik hizli turda oturum/koşu JSON'lari
    # her seferinde yeniden ayristiriliyordu). Okuma hatasinda onceki deger korunur.
    $k = "json:$Yol"
    try {
        $fi = Get-Item -LiteralPath $Yol -ErrorAction Stop
        $imza = "$($fi.Length)|$($fi.LastWriteTimeUtc.Ticks)"
        if ($Onbellek.ContainsKey($k) -and $Onbellek[$k].Imza -eq $imza) { return $Onbellek[$k].Nesne }
        $o = (Read-MerkezPaylasimli $Yol) | ConvertFrom-Json; $Onbellek[$k] = @{ Imza = $imza; Nesne = $o }; return $o
    } catch { if ($Onbellek.ContainsKey($k)) { return $Onbellek[$k].Nesne }; return $null }
}

function Read-MerkezSonSatirlar([string]$Yol, [int]$Bayt = 32768) {
    # Dosyanin son $Bayt baytini satir listesi olarak dondurur (ilk yarim satir atilir).
    $fs = [System.IO.File]::Open($Yol, 'Open', 'Read', ([System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete))
    try {
        $bas = [Math]::Max(0, $fs.Length - $Bayt); [void]$fs.Seek($bas, 'Begin')
        $buf = New-Object byte[] ([int]($fs.Length - $bas)); [void]$fs.Read($buf, 0, $buf.Length)
        $metin = [Text.Encoding]::UTF8.GetString($buf)
        $satirlar = @($metin -split "`n")
        if ($bas -gt 0 -and $satirlar.Count -gt 1) { $satirlar = $satirlar[1..($satirlar.Count - 1)] }
        return $satirlar
    } finally { $fs.Dispose() }
}

function Protect-MerkezSatir([string]$Metin, [int]$Uzunluk = 64) {
    # Ekrana giden HER ajan metni buradan gecer: tek satir, kontrol/ANSI/OSC dizileri silinir (sahte cerceve ya da
    # pencere basligi cizilemez), sirlar maskelenir, uzunluk kesilir. Balon modulu yukluyse onun daha genis maske
    # kurallari da uygulanir (ad cakismasi olmasin diye bu islev ayri adlidir).
    if (-not $Metin) { return '' }
    $m = [string]$Metin
    $m = $m -replace '\x1b\][^\x07\x1b]*(\x07|\x1b\\)?', '' -replace '\x1b\[[0-9;?]*[A-Za-z]', '' -replace '\x1b.', ''
    $m = ($m -replace '[\r\n\t]+', ' ' -replace '[\x00-\x1f\x7f]', '').Trim()
    $m = $m -replace '(?i)\b(bearer|basic)\s+\S+', '$1 ***'
    $m = $m -replace '(?i)((?:token|key|secret|password|passwd|pwd|parola|authorization|credential)s?\s*[=:]\s*)\S+', '$1***'
    $m = $m -replace '(?i)(\w+://)[^/\s:@]+:[^/\s@]+@', '$1***@'
    $m = $m -replace '(?i)(\s-(?:u|p|-password|-token)\s+)\S+', '$1***'
    $m = $m -replace '\b(sk-|ghp_|github_pat_|xox[abpr]-|AKIA|AIza)[A-Za-z0-9_-]{8,}', '***'
    $m = $m -replace '[A-Za-z0-9+_=-]{32,}', '***'
    if (Get-Command Protect-MerkezMetin -ErrorAction SilentlyContinue) { try { $m = [string](Protect-MerkezMetin $m) } catch { } }
    if ($m.Length -gt $Uzunluk) { $m = $m.Substring(0, [Math]::Max(1, $Uzunluk - 1)) + '…' }
    return $m
}

$script:MerkezIsciBalon = @{}
function Get-MerkezIsciEtkinlik([string]$EventsYol) {
    # Isci events.jsonl kuyrugundan son anlamli olay -> kisa balon metni. Dosya boyu+zamani degismediyse onbellekten.
    if (-not $EventsYol -or -not (Test-Path -LiteralPath $EventsYol)) { return '' }
    $fi = Get-Item -LiteralPath $EventsYol; $imza = "$($fi.Length)|$($fi.LastWriteTimeUtc.Ticks)"
    if ($script:MerkezIsciBalon.ContainsKey($EventsYol) -and $script:MerkezIsciBalon[$EventsYol].Imza -eq $imza) { return $script:MerkezIsciBalon[$EventsYol].Metin }
    $sonuc = Get-MerkezIsciEtkinlikOku $EventsYol
    $script:MerkezIsciBalon[$EventsYol] = @{ Imza = $imza; Metin = $sonuc }
    return $sonuc
}
function Get-MerkezIsciEtkinlikOku([string]$EventsYol) {
    try {
        $satirlar = @(Read-MerkezSonSatirlar -Yol $EventsYol -Bayt 24576)
        for ($i = $satirlar.Count - 1; $i -ge 0; $i--) {
            $s = $satirlar[$i].Trim(); if (-not $s.StartsWith('{')) { continue }
            $o = $null; try { $o = $s | ConvertFrom-Json } catch { continue }
            $it = $o.item; if (-not $it) { continue }
            switch ([string]$it.type) {
                'command_execution' { $c = [string]$it.command; $c = $c -replace '^"?[^"]*powershell(\.exe)?"?\s+(-\w+\s+)*', '' -replace '^-Command\s+', ''; return (Protect-MerkezSatir ("▸ " + $c)) }
                'file_change'       { $ch = @($it.changes | Where-Object { $_ }); $yol = $(if ($ch.Count) { Split-Path -Leaf ([string]$ch[0].path) } else { '' }); return (Protect-MerkezSatir ("▸ Edit: $yol" + $(if ($ch.Count -gt 1) { " +$($ch.Count - 1)" }))) }
                'agent_message'     {
                    # Isci son mesaji teslim JSON'u olabilir: ham JSON yerine 'outcome' alani gosterilir.
                    $tx = [string]$it.text
                    if ($tx.TrimStart().StartsWith('{')) { try { $j = $tx | ConvertFrom-Json; if ($j.outcome) { $tx = [string]$j.outcome } } catch { } }
                    return (Protect-MerkezSatir ("✎ " + $tx))
                }
                'reasoning'         { return '… düşünüyor' }
                'mcp_tool_call'     { return (Protect-MerkezSatir ("▸ $($it.server).$($it.tool)")) }
            }
        }
    } catch { }
    return ''
}

$script:MerkezProjeOnb = @{}
function Get-MerkezProje([string]$Cwd, [hashtable]$Paths) {
    # Kanat = proje: once git deposunun koku (alt klasorde calisan oturum ayni kanatta kalsin), yoksa motorun proje adi.
    if ($script:MerkezProjeOnb.ContainsKey($Cwd)) { return $script:MerkezProjeOnb[$Cwd] }
    $ad = ''
    try {
        # Vault icindeki her alt klasor 'Beyin' kanadidir; baska yerde motorun proje adi (git koku aramasi ust klasore
        # tirmanip Desktop gibi ortak bir kok buluyordu).
        $v = [string]$Paths.Vault
        if ($v) {
            $c = $Cwd.Replace('/', '\').TrimEnd('\'); $vv = $v.Replace('/', '\').TrimEnd('\')
            if ($c -ieq $vv -or $c.StartsWith($vv + '\', [StringComparison]::OrdinalIgnoreCase)) { $ad = Split-Path -Leaf $vv }
        }
    } catch { }
    if (-not $ad) { try { $ad = Get-BeyinProjectLeaf -Path $Cwd -Paths $Paths } catch { $ad = Split-Path -Leaf $Cwd } }
    $script:MerkezProjeOnb[$Cwd] = $ad; return $ad
}

function Test-MerkezGozetmenDurdu($Kosu, [hashtable]$Onbellek, [datetime]$Simdi = (Get-Date)) {
    $sv = $Kosu.supervisor; if (-not $sv) { return $false }
    $yas = [double]::PositiveInfinity
    if ($sv.heartbeatAt) { try { $yas = ((Get-Date).ToUniversalTime() - ([datetime]::Parse([string]$sv.heartbeatAt)).ToUniversalTime()).TotalSeconds } catch { } }
    if ($yas -lt 60) { return $false }
    $canli = $false; if ($sv.pid) { $canli = Test-MerkezPidCanli ([int]$sv.pid) $Onbellek $Simdi }
    return -not $canli
}

function Get-MerkezKosuAsama($Kosu) {
    # 0..6: plan, basladi, isciler bitti, toplandi, birlesti, dogrulandi, ana dalda
    switch ([string]$Kosu.status) {
        'planned' { return 0 } 'running' { if (@($Kosu.workers | Where-Object { $_.status -in @('queued', 'spawning', 'running', 'planned') }).Count) { return 1 } return 2 }
        'paused' { return 1 } 'collected' { return 3 } 'integrated' { return 4 } 'verified' { return 5 } 'merged' { return 6 }
    }
    return 0
}

function Get-MerkezKosuSonraki($Kosu, [bool]$Sahipsiz) {
    # @{ Metin; Onay (kullanicidan satir bekliyor mu); Renk = ok|warn|err|muted }
    $id = [string]$Kosu.runId; $st = [string]$Kosu.status
    if ($Sahipsiz) { return @{ Metin = "gözetmen durdu → beyin takim resume --run $id"; Onay = $false; Renk = 'err' } }
    switch ($st) {
        'planned'  { return @{ Metin = "onay bekliyor → baslat $id"; Onay = $true; Renk = 'warn' } }
        'verified' { return @{ Metin = "onay bekliyor → birlestir $id"; Onay = $true; Renk = 'warn' } }
        'merged'   { return @{ Metin = 'ana dalda'; Onay = $false; Renk = 'ok' } }
        'aborted'  { return @{ Metin = 'iptal edildi'; Onay = $false; Renk = 'muted' } }
        'failed'   { return @{ Metin = 'başarısız · işçi raporlarına bak'; Onay = $false; Renk = 'err' } }
        'collected' { return @{ Metin = "bütünleştir → beyin takim integrate --run $id"; Onay = $false; Renk = 'muted' } }
    }
    if ($st -eq 'paused') { return @{ Metin = "kota → beyin takim resume --run $id --wait"; Onay = $false; Renk = 'warn' } }
    if ($st -eq 'integrated') {
        if ($Kosu.integration -and -not $Kosu.integration.ok) { return @{ Metin = 'kontrol düştü → onar, integrate --recheck'; Onay = $false; Renk = 'err' } }
        return @{ Metin = "doğrula → beyin takim verify --run $id"; Onay = $false; Renk = 'muted' }
    }
    $calisan = @($Kosu.workers | Where-Object { $_.status -in @('queued', 'spawning', 'running') }).Count
    if ($calisan) { return @{ Metin = "$calisan işçi çalışıyor"; Onay = $false; Renk = 'ok' } }
    return @{ Metin = "topla → beyin takim collect --run $id"; Onay = $false; Renk = 'muted' }
}

function Get-MerkezKosuOzet($Kosu, [bool]$Sahipsiz = $false, [datetime]$Simdi = (Get-Date)) {
    # Saf ozet: kosu JSON'u + gozetmen durumu; RenderRun/KosuAsamalar kurallariyla uyumlu.
    $ws = @($Kosu.workers | Where-Object { $null -ne $_ })
    $st = [string]$Kosu.status; $ig = $Kosu.integration; $v = $Kosu.verification
    $asamalar = @($true, [bool](($Kosu.approvals -and $Kosu.approvals.start) -or $Kosu.startedAt -or $st -in @('running','paused','collected','integrated','verified','merged')), [bool]($st -in @('collected','integrated','verified','merged')),
        [bool](($ig -and $ig.ok) -or $st -in @('verified','merged')), [bool](($v -and $v.verdict -in @('pass','warn')) -or $st -in @('verified','merged')), [bool](($Kosu.approvals -and $Kosu.approvals.merge) -or $st -eq 'merged'))
    $guncel = 6; for ($i = 0; $i -lt 6; $i++) { if (-not $asamalar[$i]) { $guncel = $i; break } }
    $calisan = @($ws | Where-Object { $_.status -in @('queued','spawning','running') }).Count
    $bekleyen = @($ws | Where-Object { $_.status -in @('planned','paused_limit') }).Count
    $sorunKod = @('failed','timed_out','scope_violation','rejected_content','conflict','aborted')
    $sorunlu = @($ws | Where-Object { $_.status -in $sorunKod }).Count
    $kismen = @($ws | Where-Object { $_.status -notin $sorunKod -and $_.verdict -and $_.verdict -ne 'pass' }).Count
    $bitmis = $ws.Count - $calisan - $bekleyen
    $temiz = [Math]::Max(0, $bitmis - $sorunlu - $kismen)
    $conflicts = @(); if ($ig) { $conflicts = @($ig.conflicts | Where-Object { $null -ne $_ }) }
    $cakisma = $conflicts.Count -gt 0
    $kontrolDustu = [bool]($ig -and -not $ig.ok -and -not $cakisma)
    $dogrulamaDustu = [bool]($v -and $v.verdict -and $v.verdict -notin @('pass','warn'))
    $kirik = [bool]($cakisma -or $kontrolDustu -or $dogrulamaDustu -or $st -eq 'failed' -or ($st -eq 'aborted' -and -not ($ws.Count -gt 0 -and @($ws | Where-Object { $_.status -ne 'collected' }).Count -eq 0)))
    # Salt okunur inceleme kosusu: isciler raporlarini teslim etti (collected) ve kosu kapatildi -> iptal degil.
    $raporlu = [bool]($st -eq 'aborted' -and $ws.Count -gt 0 -and @($ws | Where-Object { $_.status -ne 'collected' }).Count -eq 0)
    $rozet = if ($raporlu) { 'raporlar' } elseif ($st -eq 'aborted') { 'iptal' } elseif ($st -eq 'failed') { 'basarisiz' } elseif ($st -eq 'merged') { 'anadalda' }
        elseif ($Sahipsiz) { 'sahipsiz' } elseif ($calisan -gt 0) { 'calisiyor' } elseif ($cakisma) { 'cakisma' }
        elseif ($kontrolDustu) { 'kontrol' } elseif ($dogrulamaDustu) { 'dogrulanamadi' }
        elseif ($st -eq 'verified' -and $v.verdict -eq 'warn') { 'uyarili' } elseif ($st -eq 'verified') { 'dogrulandi' }
        elseif ($st -eq 'planned') { 'onay' } elseif ($st -eq 'paused') { 'kota' } else { 'sef' }
    $inTok = 0L; $outTok = 0L; $cacheTok = 0L; $dosya = 0
    foreach ($w in $ws) {
        $dosya += @($w.changedPaths | Where-Object { $_ }).Count
        if ($w.usage) { try { $inTok += [int64]$w.usage.input_tokens; $outTok += [int64]$w.usage.output_tokens; $cacheTok += [int64]$w.usage.cached_input_tokens } catch { } }
    }
    $gecen = 0; $toplam = 0
    if ($st -in @('integrated','verified','merged') -and $ig -and $ig.checks) {
        $kontroller = @(); if ($ig.checks -is [System.Collections.IDictionary]) { $kontroller = @($ig.checks.Values) }
        elseif ($ig.checks -is [System.Array]) { $kontroller = @($ig.checks) }
        else { $kontroller = @($ig.checks.PSObject.Properties | ForEach-Object { $_.Value }) }
        foreach ($c in $kontroller) { $toplam++; if ($c.ok -eq $true -or [string]$c.status -eq '0' -or [string]$c.status -in @('passed','pass','ok','success')) { $gecen++ } }
    }
    $baslangic = $null; if ($Kosu.startedAt) { try { $baslangic = [datetime]$Kosu.startedAt } catch { } }
    $sonAt = $null; foreach ($e in @($Kosu.history)) { if ($e.at) { try { $t = [datetime]$e.at; if (-not $sonAt -or $t -gt $sonAt) { $sonAt = $t } } catch { } } }
    $bitti = $st -in @('merged', 'aborted', 'failed', 'verified')
    if (-not ($bitti -and $sonAt)) { $sonAt = $Simdi }
    $sure = 0.0; if ($baslangic) { $sure = [Math]::Max(0, ($sonAt - $baslangic).TotalSeconds) }
    return @{ Adimlar = [bool[]]$asamalar; Guncel = $guncel; Kirik = $kirik; Rozet = $rozet; Temiz = $temiz; Kismen = $kismen; Sorunlu = $sorunlu; Calisan = $calisan; Bekleyen = $bekleyen; Dosya = $dosya; JetonGiris = $inTok; JetonCikis = $outTok; JetonOnbellek = $cacheTok; Kontrol = @{ Gecen = $gecen; Toplam = $toplam }; Sure = $sure; Baslangic = $baslangic }
}

function Get-MerkezSirada($a) {
    if ($a.Onaylar.Count -gt 0) { $x = $a.Onaylar[0]; return @{ Metin = Protect-MerkezSatir ([string]$x.Satir); Neden = Protect-MerkezSatir (('onay bekliyor · ' + [string]$x.Neden).TrimEnd(' ', '·')); Renk = 'warn' } }
    $err = @($a.Teshis | Where-Object { $_.Seviye -eq 'err' })
    if ($err.Count) { return @{ Metin = Protect-MerkezSatir ([string]$err[0].Metin); Neden = 'tanı gerektiriyor'; Renk = 'err' } }
    foreach ($k in $a.Kosular) { if ($k.Guncel -lt 6 -and $k.Durum -notin @('merged','aborted','failed')) { return @{ Metin = Protect-MerkezSatir ([string]$k.Sonraki.Metin); Neden = Protect-MerkezSatir ([string]$k.RunId); Renk = $(if ($k.Sonraki -and $k.Sonraki.Renk) { [string]$k.Sonraki.Renk } else { 'warn' }) } } }
    return @{ Metin = 'her şey yolunda'; Neden = ''; Renk = 'ok' }
}

function Test-MerkezPidCanli([int]$ProcessId, [hashtable]$Onbellek, [datetime]$Simdi) {
    if ($ProcessId -le 0) { return $false }
    if (-not $Onbellek) { $Onbellek = @{} }
    if (-not $Onbellek.ContainsKey('PidZamani') -or (($Simdi - $Onbellek.PidZamani).TotalSeconds -ge 3)) {
        $pids = @{}; try { foreach ($pr in @(Get-Process -ErrorAction SilentlyContinue)) { $pids[[int]$pr.Id] = $true } } catch { }
        $Onbellek.Pidler = $pids; $Onbellek.PidZamani = $Simdi
    }
    return [bool]$Onbellek.Pidler[[int]$ProcessId]
}

function Get-MerkezAnlik {
    param([hashtable]$Paths, [int]$SonKosuSaat = 6, [switch]$Hizli, [hashtable]$Onbellek)
    # $Onbellek: yavas veriler (pano, aktarim, kaynak, maliyet, balon) icin cagiran tarafin tuttugu sozluk.
    # -Hizli: yavas verileri onbellekten al, yalniz koşu + oturum + surec canliligini tazele.
    if (-not $Onbellek) { $Onbellek = @{} }
    $simdi = Get-Date; $simdiUtc = $simdi.ToUniversalTime()
    $a = @{ Ts = $simdi; Ajanlar = New-Object System.Collections.Generic.List[object]; Kosular = New-Object System.Collections.Generic.List[object]
            Kartlar = @(); Aktarimlar = @(); Onaylar = New-Object System.Collections.Generic.List[object]; Teshis = New-Object System.Collections.Generic.List[object]
            Kaynak = $null; Maliyet = $null; Sayac = @{} }
    # Surec listesi 3 sn saklanir: 1.5 sn arayla gelen hizli cizimlerde tekrar tarama yok.

    # --- pano (yavas) ---
    $kartlar = $null
    if ($Hizli -and $Onbellek.ContainsKey('Kartlar')) { $kartlar = $Onbellek.Kartlar } else {
        $kartlar = @()
        try {
            if (Test-Path -LiteralPath $Paths.Board) { $st = (Read-MerkezPaylasimli $Paths.Board) | ConvertFrom-Json; $kartlar = @($st.tasks | Where-Object { $_ -and $_.status -in @('todo', 'in_progress', 'review', 'blocked') }) }
            $Onbellek.Kartlar = $kartlar
        } catch { if ($Onbellek.ContainsKey('Kartlar')) { $kartlar = $Onbellek.Kartlar } }   # yazilirken okunduysa onceki gorunum kalir
    }

    # --- takim kosulari + isciler (hizli) ---
    $isciOturum = @{}
    foreach ($f in @(Get-ChildItem -LiteralPath $Paths.TeamRuns -Filter '*.json' -File -ErrorAction SilentlyContinue)) {
        $k = $null
        try { $k = Read-MerkezJsonOnb $f.FullName $Onbellek } catch { $k = $null }
        if (-not $k) { continue }
        if (-not $k -or -not $k.runId) { continue }
        $bitmis = [string]$k.status -in @('merged', 'aborted', 'failed')
        if ($bitmis -and $f.LastWriteTime -lt $simdi.AddHours(-$SonKosuSaat)) { continue }
        if (-not $bitmis -and $f.LastWriteTime -lt $simdi.AddDays(-7)) { continue }   # insan onayi 7 gun gecerli; daha eski koşu bayattir
        $sahipsiz = [bool](([string]$k.status -eq 'running') -and @($k.workers | Where-Object { $_.status -in @('queued', 'spawning', 'running') }).Count -and (Test-MerkezGozetmenDurdu $k $Onbellek $simdi))
        $sonraki = Get-MerkezKosuSonraki $k $sahipsiz
        $ws = @($k.workers | Where-Object { $null -ne $_ })
        $jeton = 0L; foreach ($w in $ws) { if ($w.usage) { try { $jeton += [int64]$w.usage.input_tokens + [int64]$w.usage.output_tokens } catch { } } }
        $ozet = Get-MerkezKosuOzet $k $sahipsiz $simdi
        $kosuOge = @{ RunId = [string]$k.runId; Repo = [string]$k.repoName; Durum = [string]$k.status; Asama = (Get-MerkezKosuAsama $k); Sonraki = $sonraki; Ozet = $ozet
            Isci = $ws.Count; Biten = @($ws | Where-Object { $_.status -in @('finished', 'collected', 'integrated') }).Count
            Sorunlu = @($ws | Where-Object { $_.status -in @('failed', 'timed_out', 'scope_violation', 'rejected_content', 'conflict') }).Count
            Jeton = $jeton; Sahipsiz = $sahipsiz; KayitGuncel = $f.LastWriteTime; Bitmis = $bitmis
            Dogrulama = $(if ($k.verification) { [string]$k.verification.verdict } else { '' }) }
        foreach ($ok in $ozet.Keys) { if (-not $kosuOge.ContainsKey($ok) -or $ok -eq 'Sorunlu') { $kosuOge[$ok] = $ozet[$ok] } }   # sozlesme: ozet alanlari koşu ogesinde
        $a.Kosular.Add($kosuOge)
        if ($sonraki.Onay) { $a.Onaylar.Add(@{ Satir = ($sonraki.Metin -replace '^onay bekliyor → ', ''); Neden = "koşu $($k.runId) · $($k.repoName)" }) }
        if ($bitmis) { continue }
        foreach ($w in $ws) {
            $ev = Join-Path (Join-Path (Join-Path $Paths.TeamRuns $k.runId) $w.taskId) 'events.jsonl'
            $nabiz = -1; if (Test-Path -LiteralPath $ev) { $nabiz = ($simdi - (Get-Item -LiteralPath $ev).LastWriteTime).TotalSeconds }
            $surec = $null; if ($w.pid) { $surec = Test-MerkezPidCanli ([int]$w.pid) $Onbellek $simdi }
            $d = Get-MerkezDurum @{ Tur = 'isci'; IsciDurum = [string]$w.status; Verdict = [string]$w.verdict; NabizSn = $nabiz; SurecCanli = $surec; GozetmenDurdu = $sahipsiz }
            $balon = ''; if ($d.Durum -in @('calisiyor', 'engelli')) { $balon = Get-MerkezIsciEtkinlik $ev }
            elseif ($d.Durum -eq 'duraklatildi') { $balon = '⏸ kota doldu' } elseif ($d.Durum -eq 'bitti') { $balon = '✔ teslim etti' }
            $basla = $null; if ($w.startedAt) { try { $basla = [datetime]$w.startedAt } catch { } }
            $son = $null; if ($w.finishedAt) { try { $son = [datetime]$w.finishedAt } catch { } }
            $a.Ajanlar.Add(@{ Tur = 'isci'; Ajan = 'codex'; Ad = [string]$w.taskId; Rol = [string]$w.role; Kanat = [string]$k.repoName; Kosu = [string]$k.runId
                Durum = $d.Durum; Kaynak = $d.Kaynak; Bayat = $d.Bayat; NabizSn = $nabiz; Balon = $balon; Basladi = $basla; Bitti = $son
                Jeton = $(if ($w.usage) { try { [int64]$w.usage.input_tokens + [int64]$w.usage.output_tokens } catch { 0 } } else { 0 }); Verdict = [string]$w.verdict; Pid = $w.pid
                Dosya = @($w.changedPaths | Where-Object { $_ }).Count; Commit = [bool]$w.commit })
            if ($d.Durum -eq 'duraklatildi') { $a.Teshis.Add(@{ Seviye = 'warn'; Metin = "$($w.taskId) kota sınırında · beyin takim resume --run $($k.runId) --wait" }) }
            elseif ($d.Bayat -and $d.Kaynak -eq 'surec') { $a.Teshis.Add(@{ Seviye = 'err'; Anahtar = "surec:$($w.taskId)"; Metin = "$($w.taskId) işçi süreci yok (koşu hâlâ çalışıyor görünüyor) · beyin takim resume --run $($k.runId)" }) }
            elseif ($d.Bayat -and $d.Kaynak -ne 'gozetmen' -and $nabiz -ge 0) { $a.Teshis.Add(@{ Seviye = 'warn'; Metin = "$($w.taskId) $([int]($nabiz / 60)) dk'dır olay üretmiyor" }) }
        }
        if ($sahipsiz) { $a.Teshis.Add(@{ Seviye = 'err'; Anahtar = "sahipsiz:$($k.runId)"; Metin = "koşu $($k.runId) sahipsiz (gözetmen durdu) · beyin takim resume --run $($k.runId)" }) }
        if ($k.integration -and -not $k.integration.ok -and [string]$k.status -eq 'integrated') { $a.Teshis.Add(@{ Seviye = 'err'; Anahtar = "kontrol:$($k.runId)"; Metin = "koşu $($k.runId) bütünleştirme kontrolü düştü" }) }
    }

    # --- liderler: oturum dosyalari (hizli) ---
    foreach ($f in @(Get-ChildItem -LiteralPath $Paths.Sessions -Filter '*.json' -File -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -ge $simdi.AddHours(-24) })) {
        $o = $null
        try { $o = Read-MerkezJsonOnb $f.FullName $Onbellek } catch { $o = $null }
        if (-not $o) { continue }
        if ($o.PSObject.Properties['takimRun'] -and $o.takimRun) { continue }   # isci oturumu: koşu altinda gorunur
        $ajan = $(if ($o.agent) { [string]$o.agent } else { '?' })
        $surec = $null; if ($o.PSObject.Properties['pid'] -and $o.pid) { $surec = Test-MerkezPidCanli ([int]$o.pid) $Onbellek $simdi }
        $nabiz = ($simdi - $f.LastWriteTime).TotalSeconds
        $d = Get-MerkezDurum @{ Tur = 'lider'; SurecCanli = $surec; NabizSn = $nabiz }
        if ($d.Durum -eq 'kapali' -and $nabiz -gt $script:MerkezGosterKapaliSn) { continue }
        $proje = $(if ($o.cwd) { Get-MerkezProje ([string]$o.cwd) $Paths } else { '-' })
        $basla = $null; if ($o.start) { try { $basla = [DateTimeOffset]::FromUnixTimeSeconds([int64]$o.start).LocalDateTime } catch { } }
        $a.Ajanlar.Add(@{ Tur = 'lider'; Ajan = $ajan; Ad = $f.BaseName; Rol = $(if ($ajan -eq 'codex') { 'Codex' } else { 'Claude' }); Kanat = $proje; Kosu = ''
            Durum = $d.Durum; Kaynak = $d.Kaynak; Bayat = $d.Bayat; NabizSn = $nabiz; Balon = ''; Basladi = $basla; Bitti = $null; Prompt = [int]$o.prompts
            Cwd = [string]$o.cwd; Pid = $o.pid; Jeton = 0 })
    }

    # --- liderlerin balonu (yavas; balon modulu yuklu ise) ---
    if (-not $Onbellek.ContainsKey('Balon')) { $Onbellek.Balon = @{} }
    if (-not $Onbellek.ContainsKey('Nabiz')) { $Onbellek.Nabiz = @{} }
    $balonVar = [bool](Get-Command Get-MerkezEtkinlik -ErrorAction SilentlyContinue)
    foreach ($ag in $a.Ajanlar) {
        if ($ag.Tur -ne 'lider') { continue }
        if ($ag.Durum -eq 'kapali') { $ag.Balon = ''; continue }
        if (-not $Hizli -and $balonVar) {
            try {
                $e = Get-MerkezEtkinlik -Ajan $ag.Ajan -OturumId $ag.Ad -Cwd $ag.Cwd
                if ($e -and $e.Ok) { $Onbellek.Balon[$ag.Ad] = [string]$e.Metin; $Onbellek["tur:$($ag.Ad)"] = [string]$e.Tur; if ($e.Zaman) { $Onbellek.Nabiz[$ag.Ad] = [datetime]$e.Zaman } }
            } catch { }
        }
        if ($Onbellek.Balon.ContainsKey($ag.Ad)) { $ag.Balon = $Onbellek.Balon[$ag.Ad] }
        # NABIZ: oturum dosyasi yalniz kullanici mesajinda yazilir; calisan oturumun gercek nabzi transkriptin son kaydidir.
        if ($Onbellek.Nabiz.ContainsKey($ag.Ad)) {
            $tn = ($simdi - $Onbellek.Nabiz[$ag.Ad]).TotalSeconds
            if ($tn -ge 0 -and $tn -lt $ag.NabizSn) { $ag.NabizSn = $tn }
            $surec = $null; if ($ag.Pid) { $surec = Test-MerkezPidCanli ([int]$ag.Pid) $Onbellek $simdi }
            $d = Get-MerkezDurum @{ Tur = 'lider'; SurecCanli = $surec; NabizSn = $ag.NabizSn; Etkinlik = [string]$Onbellek["tur:$($ag.Ad)"] }
            $ag.Durum = $d.Durum; $ag.Kaynak = $(if ($d.Kaynak -eq 'nabiz') { 'transkript' } else { $d.Kaynak }); $ag.Bayat = $d.Bayat
        }
    }

    # --- kartlar + onaylar ---
    $a.Kartlar = @($kartlar | Sort-Object -Property @{ Expression = { switch ([string]$_.status) { 'blocked' { 0 } 'review' { 1 } 'in_progress' { 2 } default { 3 } } } }, @{ Expression = { [string]$_.id } })
    foreach ($k in $kartlar) { if ([string]$k.status -eq 'review') { $a.Onaylar.Add(@{ Satir = "onayla $($k.id)"; Neden = "kart incelemede · $(Protect-MerkezSatir ([string]$k.title) 60)" }) } }

    # --- aktarimlar (yavas) ---
    if ($Hizli -and $Onbellek.ContainsKey('Aktarimlar')) { $a.Aktarimlar = $Onbellek.Aktarimlar } else {
        try {
            $ak = @(Get-BeyinHandoffListe -Paths $Paths | Where-Object { $_ -and [string]$_.status -ne 'tamam' -and [string]$_.kind -ne 'devir' })
            $a.Aktarimlar = @($ak | Sort-Object -Property @{ Expression = { [string]$_.ts } } -Descending)
            $Onbellek.Aktarimlar = $a.Aktarimlar
        } catch { if ($Onbellek.ContainsKey('Aktarimlar')) { $a.Aktarimlar = $Onbellek.Aktarimlar } }
    }
    foreach ($h in $a.Aktarimlar) {
        try { $t = [datetime]::Parse([string]$h.ts); if (($simdi - $t).TotalDays -gt 3) { $a.Teshis.Add(@{ Seviye = 'warn'; Metin = "aktarım $($h.id) 3 günden eski ($($h.toProject)) · beyin aktar -Tamam $($h.id)" }); break } } catch { }
    }

    # --- kaynak + maliyet (yavas) ---
    if ($Hizli -and $Onbellek.ContainsKey('Kaynak')) { $a.Kaynak = $Onbellek.Kaynak } else {
        try { $a.Kaynak = Get-BeyinKaynakOzeti -Paths $Paths } catch { $a.Kaynak = $null }
        $Onbellek.Kaynak = $a.Kaynak
    }
    if ($Hizli -and $Onbellek.ContainsKey('Maliyet')) { $a.Maliyet = $Onbellek.Maliyet } else {
        $m = $null; $mf = Join-Path $Paths.ScrState 'maliyet\son.json'
        try { if (Test-Path -LiteralPath $mf) { $m = (Read-MerkezPaylasimli $mf) | ConvertFrom-Json } } catch { }
        $a.Maliyet = $m; $Onbellek.Maliyet = $m
    }
    if ($a.Kaynak -and $a.Kaynak.Ok) {
        if ($a.Kaynak.CommitYuzde -ge 85) { $a.Teshis.Add(@{ Seviye = 'err'; Anahtar = 'commit'; Metin = "commit %$($a.Kaynak.CommitYuzde) · beyin bekci" }) }
        if ($a.Kaynak.BostaOturum -ge 5) { $a.Teshis.Add(@{ Seviye = 'warn'; Metin = "$($a.Kaynak.BostaOturum) oturum 2+ saattir sessiz · beyin bekci" }) }
    }

    # --- sayaclar ---
    foreach ($ag in $a.Ajanlar) { $s = [string]$ag.Durum; if ($a.Sayac.ContainsKey($s)) { $a.Sayac[$s]++ } else { $a.Sayac[$s] = 1 } }
    $a.Sirada = Get-MerkezSirada $a
    return $a
}
