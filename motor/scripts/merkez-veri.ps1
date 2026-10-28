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
        # Kart son durumdaysa o kazanir (2026-10-19): salt-okunur kosu 'collected' kalir (integrate/merge adimi yok);
        # sahip karti done/cancelled yapsa da isci sonsuza dek "incelemede" gorunuyordu.
        switch ([string]$K.KartDurum) {
            'done'      { return @{ Durum = 'bitti'; Kaynak = 'kart'; Bayat = $false } }
            'cancelled' { return @{ Durum = 'kapali'; Kaynak = 'kart'; Bayat = $false } }
            'blocked'   { if ($d -notin @('queued', 'spawning', 'running')) { return @{ Durum = 'engelli'; Kaynak = 'kart'; Bayat = $false } } }
        }
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

function Read-MerkezJsonOnb([string]$Yol, [hashtable]$Onbellek, [IO.FileInfo]$Fi = $null) {
    # Dosya boyu ve zamani degismediyse onceki ayristirma doner (1,5 sn'lik hizli turda oturum/koşu JSON'lari
    # her seferinde yeniden ayristiriliyordu). Okuma hatasinda onceki deger korunur.
    $k = "json:$Yol"
    try {
        $fi = $(if ($Fi) { $Fi } else { Get-Item -LiteralPath $Yol -ErrorAction Stop })   # numaralandirmadan gelen bilgi: ikinci stat yok
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

$script:MerkezProtOnb = @{}
function Protect-MerkezSatir([string]$Metin, [int]$Uzunluk = 64) {
    # Ekrana giden HER ajan metni buradan gecer: tek satir, kontrol/ANSI/OSC dizileri silinir (sahte cerceve ya da
    # pencere basligi cizilemez), sirlar maskelenir, uzunluk kesilir. Balon modulu yukluyse onun daha genis maske
    # kurallari da uygulanir (ad cakismasi olmasin diye bu islev ayri adlidir).
    if (-not $Metin) { return '' }
    # Saf islev: ayni (metin, uzunluk) icin sonuc onbellekten (kare basina onlarca cagri, her biri ~1 ms regex).
    $ok = "$Uzunluk|$Metin"; if ($script:MerkezProtOnb.ContainsKey($ok)) { return $script:MerkezProtOnb[$ok] }
    if ($script:MerkezProtOnb.Count -gt 4000) { $script:MerkezProtOnb.Clear() }
    $m = [string]$Metin
    $m = $m -replace '\x1b\][^\x07\x1b]*(\x07|\x1b\\)?', '' -replace '\x1b\[[0-9;?]*[A-Za-z]', '' -replace '\x1b.', ''
    $m = ($m -replace '[\r\n\t]+', ' ' -replace '[\x00-\x1f\x7f]', '' -replace '[\u200B-\u200F\u2060-\u2064\uFEFF\u202A-\u202E\u2066-\u2069\u0080-\u009F]', '').Trim()
    $m = $m -replace '(?i)\b(bearer|basic)\s+\S+', '$1 ***'
    $m = $m -replace '(?i)((?:token|key|secret|password|passwd|pwd|parola|authorization|credential)s?\s*[=:]\s*)\S+', '$1***'
    $m = $m -replace '(?i)(\w+://)[^/\s:@]+:[^/\s@]+@', '$1***@'
    $m = $m -replace '(?i)("(?:[\w-]*(?:token|key|secret|passw(?:or)?d|pwd|parola|auth|credential|cookie)s?)"\s*:\s*)"[^"]*"', '$1"***"'
    $m = $m -replace '(?i)\b((?:set-)?cookie\s*:\s*)\S+', '$1***' -replace '(?i)\b((?:session_?id|sid|sig|signature|access_token)=)[^&\s]+', '$1***'
    $m = $m -replace '(?i)(\s-(?:u|p|-password|-token)\s+)\S+', '$1***'
    $m = $m -replace '\b(sk-|ghp_|github_pat_|xox[abpr]-|AKIA|AIza)[A-Za-z0-9_-]{8,}', '***'
    $m = [regex]::Replace($m, '[A-Za-z0-9+_=-]{32,}', { param($x) $sir = $false; foreach ($pc in ($x.Value -split '[-_/+=]')) { if ($pc.Length -ge 20 -and $pc -match '\d' -and $pc -match '[A-Za-z]') { $sir = $true; break } }; if ($sir) { '***' } else { $x.Value } })   # proje/klasor adlari maskelenmez
    # ev dizini ~ : tek, cift (JSON kacisli) ters bolu ve /c/Users bicimleri; kullanici adi ekrana cikmasin
    $m = $m -replace '(?i)([A-Z]:(\\{1,2}|/)Users(\\{1,2}|/)|/c/Users/)[^\\/\s"'']+', '~'
    # Get-Command her cagrida milisaniyeler suruyordu (kare basina yuzlerce cagri): bulununca onbellekte kalir
    if (-not $script:MerkezProtVar) { $script:MerkezProtVar = [bool](Get-Command Protect-MerkezMetin -ErrorAction SilentlyContinue) }
    if ($script:MerkezProtVar) { try { $m = [string](Protect-MerkezMetin $m) } catch { } }
    # BMP emoji (✅ ❌ ⚠ ⭐ ⚡ ✨...) Windows Terminal'de 2 hucre cizilir ama genislik olcusu 1 sayar: guvenli simgeye cevrilir
    if (Get-Command Get-CizGuvenliMetin -ErrorAction SilentlyContinue) { $m = Get-CizGuvenliMetin $m }
    else { $m = $m -replace '[\u2705\u2714]', '✓' -replace '[\u274C\u274E\u2716]', '✕' -replace '\u26A0', '▲' -replace '\u25B6', '▸' -replace '[\u200B-\u200F\uFE0E\uFE0F]', '' -replace '[\u231A\u231B\u23E9-\u23FA\u2600-\u270D\u270F-\u2712\u2717-\u27BF\u2B00-\u2BFF]', '•' }
    if ($m.Length -gt $Uzunluk) { $kes = [Math]::Max(1, $Uzunluk - 1); if ([char]::IsHighSurrogate($m[$kes - 1])) { $kes-- }; $m = $m.Substring(0, [Math]::Max(0, $kes)) + '…' }   # vekil cift ortadan bolunmez
    if ($script:MerkezProtVar) { $script:MerkezProtOnb[$ok] = $m }   # balon modulu yuklenmeden onbelleklenmez (maske kurallari eksik kalmasin)
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

# SALT OKUNUR KOSU BITISI (2026-10-19): okuma/inceleme kosusunda integrate/merge adimi yoktur; kosu 'collected'
# kalir ve merkez onu sonsuza dek "ŞEF SIRASI · bütünleştir" diye gosteriyordu (suresi de buyuyordu). Kosu bitmis
# sayilir: motorun salt okunur bitis durumu (MerkezSaltOkunurSon) ya da 'collected' + butun isciler 'collected' ve
# (butun yazma kapsamlari bos YA DA butun kartlar done/cancelled). Gorunum mevcut "raporlar teslim alındı · salt
# okunur koşu kapatıldı" yolundan gelir (etkin durum 'aborted' + hepsi collected). Kayit degismez: kopyasi doner.
$script:MerkezSaltOkunurSon = @('completed')   # AgentChef: run.status 'completed' + run.completion {at, reason, partial}
function Get-MerkezKosuEtkin($Kosu, $KartHarita) {
    if (-not $Kosu) { return $Kosu }
    $st = [string]$Kosu.status
    $ws = @($Kosu.workers | Where-Object { $null -ne $_ })
    $bitti = $false
    if ($st -in $script:MerkezSaltOkunurSon) { $bitti = $true }
    elseif ($st -eq 'collected' -and $ws.Count -and -not @($ws | Where-Object { [string]$_.status -ne 'collected' }).Count) {
        $yazmasiz = -not @($ws | Where-Object { -not $_.PSObject.Properties['writeScope'] -or @($_.writeScope | Where-Object { $_ }).Count }).Count   # alan VAR ve bos olmali; alan yoksa kanit yok
        $kartKapali = [bool]($KartHarita -and -not @($ws | Where-Object { [string]$KartHarita[[string]$_.taskId] -notin @('done', 'cancelled') }).Count)
        $bitti = ($yazmasiz -or $kartKapali)
    }
    if (-not $bitti) { return $Kosu }
    $c = $Kosu.PSObject.Copy(); $c.status = 'aborted'
    $c | Add-Member -NotePropertyName merkezSaltOkunur -NotePropertyValue $true -Force
    $c | Add-Member -NotePropertyName merkezKismi -NotePropertyValue ([bool]($Kosu.completion -and $Kosu.completion.partial)) -Force
    return $c
}
. (Join-Path $PSScriptRoot 'takim-uyum.ps1')
function Get-MerkezKosuSonraki($Kosu, [bool]$Sahipsiz, [string]$MotorSurum = '') {
    # @{ Metin; Onay (kullanicidan satir bekliyor mu); Renk = ok|warn|err|muted }
    $id = [string]$Kosu.runId; $st = [string]$Kosu.status
    if ($Sahipsiz) { return @{ Metin = "gözetmen durdu → beyin takim resume --run $id"; Onay = $false; Renk = 'err' } }
    if(-not $MotorSurum){$MotorSurum=Get-TakimUyumSurum}
    $lead=Get-TakimLeadReviewAdim $Kosu $MotorSurum
    if($lead){return @{Metin="şef incelemesi → $lead";Onay=$false;Renk='warn'}}
    switch ($st) {
        'planned'  { return @{ Metin = "onay bekliyor → baslat $id"; Onay = $true; Renk = 'warn' } }
        'verified' { return @{ Metin = "onay bekliyor → birlestir $id"; Onay = $true; Renk = 'warn' } }
        'merged'   { return @{ Metin = 'ana dalda'; Onay = $false; Renk = 'ok' } }
        'aborted'  {
            if ($Kosu.merkezSaltOkunur) { return @{ Metin = $(if ($Kosu.merkezKismi) { 'yarım kaldı · bir işçi toplanmadı ya da kararı kısmi/başarısız · salt okunur koşu kapatıldı' } else { 'raporlar teslim alındı · salt okunur koşu kapatıldı' }); Onay = $false; Renk = $(if ($Kosu.merkezKismi) { 'warn' } else { 'ok' }) } }
            $wsA = @($Kosu.workers | Where-Object { $null -ne $_ })
            if ($wsA.Count -and -not @($wsA | Where-Object { $_.status -ne 'collected' }).Count) { return @{ Metin = 'raporlar teslim alındı · salt okunur koşu kapatıldı'; Onay = $false; Renk = 'ok' } }
            return @{ Metin = 'iptal edildi'; Onay = $false; Renk = 'muted' }
        }
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
    $sorunKod = @('failed','timed_out','scope_violation','rejected_content','conflict')   # aborted: durduruldu, sorun degil (durum kurali 'kapali')
    # karar fail/blocked olan isci de sorunludur (kirmizi); kismen yalniz partial/warn (sari)
    $sorunlu = @($ws | Where-Object { $_.status -in $sorunKod -or [string]$_.verdict -in @('fail', 'blocked') }).Count
    $kismen = @($ws | Where-Object { $_.status -notin $sorunKod -and $_.verdict -and [string]$_.verdict -notin @('pass', 'fail', 'blocked') }).Count
    $bitmis = $ws.Count - $calisan - $bekleyen
    $temiz = [Math]::Max(0, $bitmis - $sorunlu - $kismen)
    $conflicts = @(); if ($ig) { $conflicts = @($ig.conflicts | Where-Object { $null -ne $_ }) }
    $cakisma = $conflicts.Count -gt 0
    $kontrolDustu = [bool]($ig -and -not $ig.ok -and -not $cakisma)
    $dogrulamaDustu = [bool]($v -and $v.verdict -and $v.verdict -notin @('pass','warn'))
    $kirik = [bool]($cakisma -or $kontrolDustu -or $dogrulamaDustu -or $st -eq 'failed' -or ($st -eq 'aborted' -and -not ($ws.Count -gt 0 -and @($ws | Where-Object { $_.status -ne 'collected' }).Count -eq 0)))
    # Salt okunur inceleme kosusu: isciler raporlarini teslim etti (collected) ve kosu kapatildi -> iptal degil.
    $raporlu = [bool]($Kosu.merkezSaltOkunur -or ($st -eq 'aborted' -and $ws.Count -gt 0 -and @($ws | Where-Object { $_.status -ne 'collected' }).Count -eq 0))
    if ($raporlu) { $asamalar[2] = $true; $guncel = 3 }   # topla tamam; sonraki adimlar bu kosu turunde yok (Atlanan)
    $kapsanan = 0; if ($ig -and $ig.coveredByConductor) { $kapsanan = @($ig.coveredByConductor | Where-Object { $_ }).Count }
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
    if ($raporlu) {
        # salt okunur kosu: sure SON ISCININ bitisine kadar. Yeniden toplama (collect) gecmise yeni olay yazar ve completion.at'i
        # de o ana tasir; sure 12 saate sisiyordu (olculdu: 3 dk'lik kosu "12 sa 14 dk").
        $isciSon = $null; foreach ($w in $ws) { if ($w.finishedAt) { try { $t = [datetime]$w.finishedAt; if (-not $isciSon -or $t -gt $isciSon) { $isciSon = $t } } catch { } } }
        if ($isciSon) { $sonAt = $isciSon } elseif ($Kosu.completion -and $Kosu.completion.at) { try { $sonAt = [datetime]$Kosu.completion.at } catch { } }
    }
    $bitti = $st -in @('merged', 'aborted', 'failed', 'verified')
    if (-not ($bitti -and $sonAt)) { $sonAt = $Simdi }
    $sure = 0.0; if ($baslangic) { $sure = [Math]::Max(0, ($sonAt - $baslangic).TotalSeconds) }
    return @{ Adimlar = [bool[]]$asamalar; Guncel = $guncel; Kirik = $kirik; Rozet = $rozet; Atlanan = $raporlu; Kapsanan = $kapsanan; Temiz = $temiz; Kismen = $kismen; Sorunlu = $sorunlu; Calisan = $calisan; Bekleyen = $bekleyen; Dosya = $dosya; JetonGiris = $inTok; JetonCikis = $outTok; JetonOnbellek = $cacheTok; Kontrol = @{ Gecen = $gecen; Toplam = $toplam }; Sure = $sure; Baslangic = $baslangic }
}

function Get-MerkezSirada($a) {
    if ($a.Onaylar.Count -gt 0) { $x = $a.Onaylar[0]; return @{ Metin = Protect-MerkezSatir ([string]$x.Satir); Neden = Protect-MerkezSatir (('onay bekliyor · ' + [string]$x.Neden).TrimEnd(' ', '·')); Renk = 'warn' } }
    $err = @($a.Teshis | Where-Object { $_.Seviye -eq 'err' })
    if ($err.Count) {
        # hata: aciklama baslikta, komutu "ilk adim" olarak (SIRADA onu kopyalanabilir mavi satir cizer); komutsuz hatada beyin doktor
        $hm = Protect-MerkezSatir ([string]$err[0].Metin) 300; $hk = 'beyin doktor'
        if ($hm -match '^(.*?)\s*·\s*(beyin [^·]+)$') { $hm = $Matches[1]; $hk = $Matches[2].Trim() }
        return @{ Metin = $hm; Neden = "ilk adım: $hk$(if ($err.Count -gt 1) { " · $($err.Count) hata" })"; Renk = 'err' }
    }
    foreach ($k in $a.Kosular) { if ($k.Guncel -lt 6 -and $k.Durum -notin @('merged','aborted','failed')) { return @{ Metin = Protect-MerkezSatir ([string]$k.Sonraki.Metin); Neden = Protect-MerkezSatir ([string]$k.RunId); Renk = $(if ($k.Sonraki -and $k.Sonraki.Renk) { [string]$k.Sonraki.Renk } else { 'warn' }) } } }
    # Yolunda: yine de bir bakista durum (kac ajan calisiyor, uyari var mi) - bos satir bilgi tasimiyordu
    # 'info' teshisi (bakilacak yer, sorun degil) uyari sayilmaz ve ilk adim olmaz
    $cal = @($a.Ajanlar | Where-Object { $_.Durum -eq 'calisiyor' }).Count; $uyL = @($a.Teshis | Where-Object { $_.Seviye -eq 'warn' }); $uy = $uyL.Count
    $calS = $(if ($cal) { "$cal ajan çalışıyor" } else { 'çalışan ajan yok' })
    if ($uy) {
        # Uyari varken "her şey yolunda" baslik rozetiyle celisiyordu: sorun yok ama uyari var; ilk adim ilk teshisin komutu.
        $komut = ''; foreach ($t in $uyL) { if ([string]$t.Metin -match '·\s*(beyin [^·]+)$') { $komut = $Matches[1].Trim(); break } }
        return @{ Metin = "hata yok · $uy uyarı bekliyor"; Neden = (@($(if ($komut) { "ilk adım: $komut" }), $calS) | Where-Object { $_ }) -join ' · '; Renk = 'warn' }
    }
    return @{ Metin = 'her şey yolunda'; Neden = "$calS · bekleyen onay yok"; Renk = 'ok' }
}

function Get-MerkezBellekDokum([hashtable]$Onbellek, [datetime]$Simdi) {
    # bellek alarmi icin: surec adina gore toplam ayrilmis bellek, en buyuk uc ("codex 2,2 GB, ChatGPT 2,1 GB, brave 2,0 GB"). 20 sn onbellek; salt okunur.
    if ($Onbellek.ContainsKey('bellekDokum') -and ($Simdi - $Onbellek.bellekDokum.Zaman).TotalSeconds -lt 20) { return $Onbellek.bellekDokum.Metin }
    $m = ''
    try {
        $top = @{}; foreach ($pr in @(Get-Process -ErrorAction SilentlyContinue)) { $ad = [string]$pr.ProcessName; $top[$ad] = [int64]$top[$ad] + [int64]$pr.PagedMemorySize64 }
        $m = (@($top.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 3 | ForEach-Object { '{0} {1:0.0} GB' -f (Protect-MerkezSatir ([string]$_.Key) 24), ($_.Value / 1GB) })) -join ', '
    } catch { }
    $Onbellek.bellekDokum = @{ Zaman = $Simdi; Metin = $m }; return $m
}
function Get-MerkezEskiAktarim($Aktarimlar, [datetime]$Simdi = (Get-Date)) {
    # 3 gunden eski acik aktarimlar: TEK teshis, sayi + EN ESKISI (eskiden siralamada ilk rastlanan yaziliyordu).
    $eski = @(); foreach ($h in @($Aktarimlar)) { try { $t = [datetime]::Parse([string]$h.ts); if (($Simdi - $t).TotalDays -gt 3) { $eski += @{ H = $h; T = $t } } } catch { } }
    if (-not $eski.Count) { return $null }
    $eh = @($eski | Sort-Object -Property @{ Expression = { $_.T } })[0].H
    $bas = $(if ($eski.Count -gt 1) { "$($eski.Count) aktarım 3 günden eski · en eskisi " } else { 'aktarım 3 günden eski · ' })
    return @{ Seviye = 'warn'; Metin = "$bas$($eh.id)$(if ($eh.toProject) { " ($($eh.toProject))" }) · oku: beyin aktar · c kapatma komutunu kopyalar · beyin aktar -Tamam $($eh.id)" }
}

function ConvertTo-MerkezOlay($Kayit) {
    # Makbuz satiri -> ekran olayi @{ Zaman; Ajan; Ikon; Renk; Metin; Anahtar } ya da $null (gurultu).
    # Gurultu: her arac cagrisinda yazilan 'gecti', esik alti/atlandi geri getirme, bos flush, gosterim makbuzlari.
    $sc = [string]$Kayit.script; $oc = [string]$Kayit.outcome
    if ($oc -in @('GECTI', 'ESIK_ALTI', 'ATLANDI', 'FLUSH_BOS', 'GOSTERILDI', 'KAPI_KAPALI', 'OLCULEMEDI', 'KIRP_PLAN', 'KULLANIM_OK', 'FLUSH_KUYRUKTA', 'LAYA_GOLGE_ATLANDI', 'LAYA_GOLGE_ABSTAIN')) { return $null }
    if ("$sc/$oc" -eq 'session-start/ENJEKSIYON') { return $null }   # acilislar KANATLAR'da gorunur; akista tekrar gurultusu
    $not = Protect-MerkezSatir ([string]$Kayit.note) 80
    # -Wildcard: COMPILE_HATA_<neden> / FLUSH_HATA_<neden> gibi ekli adlar tek kalipla eslenir (makbuzdaki gercek adlar)
    $o = switch -Wildcard ("$sc/$oc") {
        'flush/FLUSH_OK'                 { @('✎', 'muted', 'oturum özeti günlüğe yazıldı') }
        'session-start/ENJEKSIYON'       { @('○', 'muted', $(if ([string]$Kayit.reason -eq 'hafif') { 'oturum açıldı · vault dışı' } else { 'oturum açıldı · tam hafıza' })) }
        'session-end/SESSIONEND_OK'      { @('●', 'muted', 'oturum kapandı') }
        'session-end/KUYRUK'             { @('●', 'muted', 'oturum kapandı · özet kuyrukta') }
        'session-end/TAKIM_ISCI_BITTI'   { @('●', 'teal', 'takım işçisi bitirdi') }
        'retrieval/ENJEKSIYON'           { $kv = @($Kayit.concepts | Where-Object { $_ }); @('◆', 'accent', "$($kv.Count) not bağlama eklendi$(if ($kv.Count) { ': ' + (Protect-MerkezSatir (([string]$kv[0]) -replace '\.md$', '' -replace '-', ' ') 60) })") }
        'aktar/DEVIR_KAYDEDILDI'         { @('⇄', 'muted', 'aktarım gönderildi') }
        'aktar/AKTAR_KAYDEDILDI'         { @('⇄', 'accent', 'aktarım gönderildi') }
        'aktar/BRIFING_KAYDEDILDI'       { @('⇄', 'accent', 'işçi brifingi kaydedildi') }
        'aktar/AKTAR_TAMAM'              { @('✓', 'ok', "aktarım kapatıldı$(if ($not) { ' · ' + $not })") }
        'aktar/AKTAR_YANITLANDI'         { @('⇄', 'ok', 'aktarım yanıtlandı') }
        'pano/ONAY_KAYDEDILDI'           { @('◐', 'warn', "onay satırı kaydedildi$(if ($not) { ' · ' + $not })") }
        'pano/ONAY_KULLANILDI'           { @('✓', 'ok', "onay kullanıldı$(if ($not) { ' · ' + $not })") }
        'pano/PANO_HATA'                 { @('✕', 'err', "pano komutu reddedildi$(if ($not) { ' · ' + $not })") }
        'pano/PANO_OK'                   { @('▤', 'muted', "pano$(if ($not) { ' · ' + $not })") }
        'takim/TAKIM_OK'                 { @('▤', 'accent', "takım$(if ($not) { ' · ' + $not })") }
        'takim/TAKIM_HATA'               { @('✕', 'err', "takım komutu düştü$(if ($not) { ' · ' + $not })") }
        'takim/ONAY_ATLANDI'             { @('⊘', 'warn', "onay satırı işlenmedi$(if ($not) { ' · ' + $not })") }
        'takim/ONAY_KAYDEDILDI'          { @('◐', 'warn', "takım onayı kaydedildi$(if ($not) { ' · ' + $not })") }
        'yayinla/YAYIN_OK'               { @('↑', 'ok', 'motor yayınlandı') }
        'kill-guard/RED'                 { @('⊘', 'warn', "kill guard engelledi$(if ($not) { ' · ' + $not })") }   # engel: koruma calisti, hata degil
        'compile/COMPILE_OK'             { @('◆', 'ok', 'derleme: yeni kavram notları') }
        'gom/GOM_OK'                     { @('◆', 'muted', 'vektör gömme tazelendi') }
        'compile/COMPILE_BOS'            { @('◆', 'muted', 'derleme: yeni kavram yok') }
        'bagla/BAGLA_OK'                 { @('◆', 'muted', 'ilgili not bağlantıları tazelendi') }
        'zamanli/ZAMANLI_OK'             { @('◷', 'muted', "zamanlı görev$(if ($not -match '^(\S+(?: \S+)?) kod=') { ': ' + $Matches[1] }) tamam") }
        'copcu/COPCU_RAPOR'              { @('▤', 'muted', 'disk raporu hazır') }
        'bekci/BEKCI_RAPOR'              { @('▤', 'muted', 'kaynak bekçisi raporu') }
        'maliyet/MALIYET_KISMI'          { @('▤', 'muted', 'maliyet taraması (kısmi)') }
        'maliyet/MALIYET_OK'             { @('▤', 'muted', 'maliyet taraması') }
        'gecmis-toparla/TOPLA_OK'        { @('✎', 'muted', 'eski oturumlar toplandı') }
        'gom/GOM_OLLAMA_YOK'             { @('◆', 'warn', 'vektör gömme atlandı · Ollama kapalı') }
        'compile/COMPILE_HATA*'          { @('✕', 'err', "derleme düştü$(if ($oc -match '^COMPILE_HATA_(.+)$') { ' · ' + (Protect-MerkezSatir ($Matches[1].ToLowerInvariant() -replace '[_-]', ' ') 30) })") }
        'flush/FLUSH_HATA*'              { @('✕', 'err', "oturum özeti yazılamadı$(if ($oc -match '^FLUSH_HATA_(.+)$') { ' · ' + (Protect-MerkezSatir ($Matches[1].ToLowerInvariant() -replace '[_-]', ' ') 30) })") }
        'flush/FLUSH_MESGUL'             { @('◷', 'muted', 'oturum özeti ertelendi · motor meşgul') }
        'flush/FLUSH_ERTELENDI'          { @('◷', 'muted', 'oturum özeti ertelendi') }
        'ayar/AYAR_YAZILDI'              { @('▸', 'accent', "ayar değişti$(if ($not) { ' · ' + $not })") }
        'ayar/AYAR_SILINDI'              { @('▸', 'muted', "ayar varsayılana döndü$(if ($not) { ' · ' + $not })") }
        'ayar/AYAR_GECERSIZ'             { @('⊘', 'warn', "geçersiz ayar değeri reddedildi$(if ($not) { ' · ' + $not })") }
        'ayar/AYAR_YAZILAMADI'           { @('✕', 'err', "ayar yazılamadı$(if ($not) { ' · ' + $not })") }
        'denetle/DENETIM_OK'             { @('◆', 'muted', 'not denetimi tamam') }
        'bahcivan/BAHCIVAN_*'            { @('▤', 'muted', 'bahçıvan raporu') }
        'niyet/NIYET_YAZILDI'            { @('✎', 'accent', 'niyet kaydedildi') }
        'guncelle/GUNCELLE_*'            { @('↑', 'muted', "motor güncelleme denetimi$(if ($oc -eq 'GUNCELLE_AG_YOK') { ' · ağ yok' })") }
        'takim/ONAY_YOK'                 { @('⊘', 'warn', "onay satırı bulunamadı$(if ($not) { ' · ' + $not })") }
        default {
            $sev = $(if ($oc -match 'HATA|DUSTU|BOZUK') { 'err' } elseif ($oc -match 'RED') { 'warn' } elseif ($oc -match '_OK$') { 'muted' } else { 'muted' })
            $ocT = ($oc -replace '_', ' ').ToLowerInvariant(); if ($ocT.StartsWith("$sc ")) { $ocT = $ocT.Substring($sc.Length + 1) }   # "zamanli · zamanli ok" tekrari
            $scAd = @{ gom = 'vektör gömme'; compile = 'derleme'; flush = 'oturum özeti'; aktar = 'aktarım'; pano = 'pano'; takim = 'takım'; zamanli = 'zamanlı görev'; maliyet = 'maliyet'; copcu = 'disk raporu'; bekci = 'bekçi'; bagla = 'ilgili notlar'; ayar = 'ayar'; denetle = 'denetim'; bahcivan = 'bahçıvan'; guncelle = 'güncelleme'; niyet = 'niyet'; 'laya-shadow' = 'Laya gölge'; 'geri-getirme-olc' = 'geri getirme ölçümü'; 'skill-aday' = 'skill adayı'; 'yol-temizle' = 'yol temizliği'; 'gecmis-toparla' = 'eski oturum toplama'; retrieval = 'hatırlama'; yayinla = 'yayın'; kirp = 'kırpma'; kullanim = 'kullanım'; 'session-start' = 'oturum açılışı'; 'session-end' = 'oturum kapanışı' }[$sc]
            @('·', $sev, "$(if ($scAd) { $scAd } else { Protect-MerkezSatir $sc 30 }) · $(Protect-MerkezSatir $ocT 60)")   # ham betik adi yerine Turkce ad; ham degerler temizlenir
        }
    }
    $z = $null; try { $z = [datetime]$Kayit.ts } catch { return $null }
    $ajan = $(if ($sc -in @('zamanli', 'gom', 'compile', 'bagla', 'copcu', 'maliyet', 'bekci', 'gecmis-toparla', 'kirp', 'kullanim', 'denetle', 'bahcivan', 'skill-aday', 'geri-getirme-olc')) { 'motor' } else { [string]$Kayit.agent })   # zamanli gorevler oturum degil
    return @{ Zaman = $z; Ajan = $ajan; Ikon = $o[0]; Renk = $o[1]; Metin = $o[2]; Anahtar = [string]$Kayit.key; Tur = "$sc/$oc"; Adet = 1 }
}

function Get-MerkezOlaylar([string]$MakbuzDizin, [int]$Adet = 14, [datetime]$Simdi = (Get-Date)) {
    # Bugunun (azsa dunun de) makbuz kuyrugundan son anlamli olaylar, yeniden eskiye. Ayni oturumdan ard arda
    # gelen ayni tur olay tek satirda birlesir (Adet). Dosya yoksa bos liste; asla firlatmaz.
    $sonuc = New-Object System.Collections.Generic.List[object]
    try {
        foreach ($gun in @($Simdi, $Simdi.AddDays(-1))) {
            $f = Join-Path $MakbuzDizin ($gun.ToString('yyyy-MM-dd') + '.jsonl')
            if (-not (Test-Path -LiteralPath $f)) { continue }
            $sat = @(Read-MerkezSonSatirlar -Yol $f -Bayt 98304)
            for ($i = $sat.Count - 1; $i -ge 0 -and $sonuc.Count -lt $Adet; $i--) {
                $t = $sat[$i].Trim(); if (-not $t.StartsWith('{')) { continue }
                $k = $null; try { $k = $t | ConvertFrom-Json } catch { continue }
                $o = ConvertTo-MerkezOlay $k; if (-not $o) { continue }
                if ($sonuc.Count) { $son = $sonuc[$sonuc.Count - 1]; if ($son.Tur -eq $o.Tur -and $son.Ajan -eq $o.Ajan -and [Math]::Abs(($son.Zaman - $o.Zaman).TotalMinutes) -lt 30) { $son.Adet++; continue } }   # ayni ajanin 30 dk icindeki ayni olaylari tek satir
                $sonuc.Add($o)
            }
            if ($sonuc.Count -ge $Adet) { break }
        }
    } catch { }
    return ,$sonuc
}

function Get-MerkezEtkinlikHisto([string]$MakbuzDizin, [int]$Kova = 12, [int]$KovaDk = 10, [datetime]$Simdi = (Get-Date)) {
    # Sistem etkinligi: son Kova*KovaDk dakikadaki makbuz sayisi, kova basina (eskiden yeniye). ConvertFrom-Json yerine
    # yalniz "ts" alani regex ile okunur (hizli). Gece yarisini asan pencerede dunun dosyasi da okunur. Asla firlatmaz.
    $h = New-Object int[] $Kova
    try {
        $bas = $Simdi.AddMinutes(-$Kova * $KovaDk); $rx = [regex]'"ts":"([^"]+)"'
        foreach ($gun in @($Simdi, $Simdi.AddDays(-1))) {
            if ($gun.Date -lt $bas.Date) { continue }
            $f = Join-Path $MakbuzDizin ($gun.ToString('yyyy-MM-dd') + '.jsonl')
            if (-not (Test-Path -LiteralPath $f)) { continue }
            foreach ($sat in @(Read-MerkezSonSatirlar -Yol $f -Bayt 262144)) {
                $m = $rx.Match($sat); if (-not $m.Success) { continue }
                $t = [datetime]::MinValue; if (-not [datetime]::TryParse($m.Groups[1].Value, [ref]$t)) { continue }
                if ($t -lt $bas -or $t -gt $Simdi) { continue }
                $i = [int][Math]::Floor(($t - $bas).TotalMinutes / $KovaDk); if ($i -ge $Kova) { $i = $Kova - 1 }; if ($i -ge 0) { $h[$i]++ }
            }
        }
    } catch { }
    return ,$h
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

# ---------------------------------------------------------------------------------------------------------
# CLAUDE ISCILERI (2026-10-19): Claude Code Workflow kosulari ve Agent araciyla acilan alt ajanlar. Bunlar
# takim kosusu kaydi (team-runs) birakmaz; kendi dosyalarini ~/.claude/projects/<proje>/<oturum>/subagents
# altina yazar. Salt okunur: yalniz dosya adi/zamani, journal.jsonl olay satirlari ve meta.json okunur;
# transkript icerigi okunmaz. Durum: journal'da started - (result + failed) > 0 ve son yazim CanliSn icinde.
# ---------------------------------------------------------------------------------------------------------
$script:MerkezJournalOnb = @{}
$script:MerkezRxJTur = [regex]'"type"\s*:\s*"(\w+)"'
$script:MerkezRxJEtiket = [regex]'"label"\s*:\s*"((?:[^"\\]|\\.)*)"'
$script:MerkezRxJFaz = [regex]'"phase"\s*:\s*"((?:[^"\\]|\\.)*)"'
function Get-MerkezProjeAd([string]$Klasor) {
    # "C--Users-ali-Desktop-ornek-proje" -> "ornek-proje"; "C--" -> "kök"
    if ($Klasor -match '^[A-Za-z]--Users-[^-]+$') { return 'ev' }
    $n = $Klasor -replace '^[A-Za-z]--Users-[^-]+-', '' -replace '^(Desktop|Documents|OneDrive|Masaustu|Belgeler)-', '' -replace '^[A-Za-z]--$', ''
    if (-not $n) { $n = 'kök' }
    return $n
}
function Read-MerkezJournal([IO.FileInfo]$Dosya) {
    $k = "$($Dosya.Length)|$($Dosya.LastWriteTimeUtc.Ticks)"
    if ($script:MerkezJournalOnb.ContainsKey($Dosya.FullName) -and $script:MerkezJournalOnb[$Dosya.FullName].K -eq $k) { return $script:MerkezJournalOnb[$Dosya.FullName].O }
    $o = @{ Basladi = 0; Bitti = 0; Hata = 0; Ad = ''; Faz = '' }; $adlar = New-Object System.Collections.Generic.List[string]
    try {
        foreach ($sat in [IO.File]::ReadLines($Dosya.FullName)) {
            $m = $script:MerkezRxJTur.Match($sat); if (-not $m.Success) { continue }
            switch ($m.Groups[1].Value) {
                'started' {
                    $o.Basladi++
                    $e = $script:MerkezRxJEtiket.Match($sat); if ($e.Success) { $on = ($e.Groups[1].Value -split '[:/ ]')[0]; if ($on -and -not $adlar.Contains($on)) { $adlar.Add($on) } }
                    $f = $script:MerkezRxJFaz.Match($sat); if ($f.Success) { $o.Faz = $f.Groups[1].Value }
                }
                'result' { $o.Bitti++ }
                'failed' { $o.Hata++ }
            }
        }
    } catch { }
    $o.Ad = (@($adlar | Select-Object -First 4) -join ', ')
    if ($script:MerkezJournalOnb.Count -gt 200) { $script:MerkezJournalOnb.Clear() }
    $script:MerkezJournalOnb[$Dosya.FullName] = @{ K = $k; O = $o }
    return $o
}
function Read-MerkezAjanMeta([string]$JsonlYol) {
    $m = $JsonlYol -replace '\.jsonl$', '.meta.json'
    try { if ([IO.File]::Exists($m)) { $j = [IO.File]::ReadAllText($m) | ConvertFrom-Json; $d = [string]$j.description; if (-not $d) { $d = [string]$j.agentType }; return $d } } catch { }
    return ''
}
function Get-MerkezClaudeIsler {
    param([string]$Kok = (Join-Path $env:USERPROFILE '.claude\projects'), [datetime]$Simdi = (Get-Date), [int]$PencereDk = 120, [int]$CanliSn = 180)
    $L = New-Object System.Collections.Generic.List[object]
    if (-not $Kok -or -not [IO.Directory]::Exists($Kok)) { return ,$L }
    $sinir = $Simdi.ToUniversalTime().AddMinutes(-$PencereDk); $canliSinir = $Simdi.ToUniversalTime().AddSeconds(-$CanliSn)
    foreach ($pd in [IO.Directory]::EnumerateDirectories($Kok)) {
        $proje = Get-MerkezProjeAd ([IO.Path]::GetFileName($pd))
        foreach ($sd in [IO.Directory]::EnumerateDirectories($pd)) {
            $sub = [IO.Path]::Combine($sd, 'subagents'); if (-not [IO.Directory]::Exists($sub)) { continue }
            $oturum = [IO.Path]::GetFileName($sd)
            $wfk = [IO.Path]::Combine($sub, 'workflows')
            if ([IO.Directory]::Exists($wfk)) {
                foreach ($wd in [IO.Directory]::EnumerateDirectories($wfk)) {
                    $j = New-Object IO.FileInfo ([IO.Path]::Combine($wd, 'journal.jsonl'))
                    if (-not $j.Exists) { continue }
                    $son = $j.LastWriteTimeUtc
                    foreach ($f in (New-Object IO.DirectoryInfo $wd).EnumerateFiles('agent-*.jsonl')) { if ($f.LastWriteTimeUtc -gt $son) { $son = $f.LastWriteTimeUtc } }
                    if ($son -lt $sinir) { continue }
                    $o = Read-MerkezJournal $j
                    $acik = [Math]::Max(0, $o.Basladi - $o.Bitti - $o.Hata); $canli = ($acik -gt 0 -and $son -gt $canliSinir)
                    $durum = $(if ($canli) { 'calisiyor' } elseif ($acik -gt 0) { 'sessiz' } elseif ($o.Hata) { 'hatali' } else { 'bitti' })
                    $L.Add(@{ Tur = 'workflow'; Kimlik = [IO.Path]::GetFileName($wd); Proje = $proje; Oturum = $oturum; Ad = $o.Ad; Faz = $o.Faz; Toplam = $o.Basladi; Biten = $o.Bitti; Hata = $o.Hata
                              Calisan = $(if ($canli) { $acik } else { 0 }); Durum = $durum; Son = $son.ToLocalTime() })
                }
            }
            # workflow disi: Agent araciyla acilan alt ajanlar, oturum basina tek satir
            $top = 0; $can = 0; $sonA = [datetime]::MinValue; $adlar = New-Object System.Collections.Generic.List[string]
            foreach ($f in (New-Object IO.DirectoryInfo $sub).EnumerateFiles('agent-*.jsonl')) {
                if ($f.LastWriteTimeUtc -lt $sinir) { continue }
                $top++; if ($f.LastWriteTimeUtc -gt $sonA) { $sonA = $f.LastWriteTimeUtc }
                if ($f.LastWriteTimeUtc -gt $canliSinir) { $can++; if ($adlar.Count -lt 3) { $d = Read-MerkezAjanMeta $f.FullName; if ($d) { $adlar.Add($d) } } }
            }
            if ($top) {
                $L.Add(@{ Tur = 'ajan'; Kimlik = "ajan:$oturum"; Proje = $proje; Oturum = $oturum; Ad = (@($adlar) -join ', '); Faz = ''; Toplam = $top; Biten = $top - $can; Hata = 0
                          Calisan = $can; Durum = $(if ($can) { 'calisiyor' } else { 'bitti' }); Son = $sonA.ToLocalTime() })
            }
        }
    }
    return ,$L
}
function Get-MerkezKosuKapasite($Kosu) {
    # AgentChef 1.8.2+ kosu kaydi (2026-10-19): capacity {recommended, requested, ownerOverride, reason, atStart} ve
    # gecmiste capacity_lowered {from, to, reason}. Ekran icin tek satir: "önerilen 0 · sahip onayı 1 · başlangıçta 2→1 (neden)".
    # Alan yoksa (eski kayit) bos doner; deger guvenilmez veridir, temizlenip kisaltilir.
    $c = $Kosu.capacity; if (-not $c) { return @{ Metin = ''; Uyari = $false } }
    $p = @(); $uyari = $false
    if ($null -ne $c.recommended) { $p += "önerilen $([int]$c.recommended)" }
    if ($c.ownerOverride) { $uyari = $true; $p += "sahip onayı $(if ($null -ne $c.requested) { [int]$c.requested } else { [int]$Kosu.maxWorkers })" }
    $dus = @(@($Kosu.history) | Where-Object { $_ -and [string]$_.event -eq 'capacity_lowered' } | Select-Object -Last 1)
    if ($dus.Count) {
        $uyari = $true
        $p += "başlangıçta $([int]$dus[0].from)→$([int]$dus[0].to)$(if ($dus[0].reason) { ' (' + (Protect-MerkezSatir ([string]$dus[0].reason) 60) + ')' })"
    } elseif ($c.atStart -and $null -ne $c.atStart.recommended -and $null -ne $c.recommended -and [int]$c.atStart.recommended -ne [int]$c.recommended) {
        $p += "başlangıçta önerilen $([int]$c.atStart.recommended)"
    }
    return @{ Metin = ($p -join ' · '); Uyari = $uyari }
}
function Get-MerkezEffectiveTokens {
    param($Usage)
    if (-not $Usage) { return 0.0 }
    $inCount = [math]::Max(0, [double]$Usage.input_tokens)
    $outCount = [math]::Max(0, [double]$Usage.output_tokens)
    $cachedCount = [math]::Min($inCount, [math]::Max(0, [double]$Usage.cached_input_tokens))
    return ($inCount - $cachedCount + $outCount + $cachedCount * 0.1)
}

function Get-MerkezKanalIsciler {
    param([hashtable]$Paths)
    foreach ($engine in @('codex','claude')) {
        $root = Join-Path $Paths.ScrState ($engine + '-kanal')
        if (-not (Test-Path -LiteralPath $root)) { continue }
        foreach ($file in @(Get-ChildItem -LiteralPath $root -Filter '*.json' -File -ErrorAction SilentlyContinue)) {
            try {
                $r = (Read-MerkezPaylasimli $file.FullName) | ConvertFrom-Json
                if (-not $r.Id -or -not $r.Project -or -not $r.Status) { continue }
                $agent = $engine; if ($r.Engine) { $agent = [string]$r.Engine } elseif ($r.Backend -eq 'claude-stream') { $agent = 'claude' }
                $status = switch ([string]$r.Status) {
                    running { 'calisiyor' }; queued { 'bekliyor' }; ready { 'bosta' }
                    completed { 'bitti' }; closed { 'kapali' }; 'limit-waiting' { 'duraklatildi' }
                    default { 'engelli' }
                }
                $start = $null; $end = $null
                if ($r.Started) { $start = [datetime]$r.Started }
                if ($r.Finished) { $end = [datetime]$r.Finished }
                $event = [string]$r.LastEvent
                $evPath = Join-Path (Join-Path $root $file.BaseName) 'events.jsonl'
                if (Test-Path -LiteralPath $evPath) {
                    $last = @(Read-MerkezSonSatirlar $evPath 8192 | Where-Object { $_.Trim() } | Select-Object -Last 1)
                    if ($last.Count) { try { $ev = $last[0] | ConvertFrom-Json; $event = "$($ev.at) $($ev.type)" } catch { } }
                }
                $approvals = @($r.PendingApprovals | Where-Object { $_ }).Count
                if ($approvals) { $status = 'bekliyor' }
                $effectiveUsage = 0.0; if ($r.Budget) { $effectiveUsage = [double]$r.Budget.effectiveTokens }
                $queue = ''; if ($r.LimitQueue) { $queue = [string]$r.LimitQueue.status }
                @{ Tur='isci'; Kanal=$engine; Ajan=$agent; Ad=[string]$r.Id; Rol=[string]$r.Role; Kanat=(Get-MerkezProjeAd ([string]$r.Project)); Cwd=[string]$r.Project; Kosu=''
                   Durum=$status; Kaynak='kanal'; Bayat=$false; NabizSn=[math]::Max(0, ((Get-Date) - $file.LastWriteTime).TotalSeconds)
                   Balon=(Protect-MerkezSatir "$event$(if ($approvals) { " | onay $approvals" })$(if ($queue) { " | kuyruk $queue" })" 150)
                   SonOlay=$event; Onay=$approvals; Kuyruk=$queue; Basladi=$start; Bitti=$end; Jeton=$effectiveUsage; Pid=$r.Pid; Dosya=0; Commit=$false }
            } catch { }
        }
    }
}

function Get-MerkezAnlik {
    param([hashtable]$Paths, [int]$SonKosuSaat = 6, [switch]$Hizli, [hashtable]$Onbellek, [string]$AyrintiAnahtar = '', [string]$ClaudeKok = '')
    # -AyrintiAnahtar 'Tur:Kosu:Ad': yalniz o ajanin ayrintisi (son adimlar, jeton, bekleme) hesaplanir; hizli turda da (onbellekli).
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
            $harita = @{}
            if (Test-Path -LiteralPath $Paths.Board) { $st = (Read-MerkezPaylasimli $Paths.Board) | ConvertFrom-Json; $kartlar = @($st.tasks | Where-Object { $_ -and $_.status -in @('todo', 'in_progress', 'review', 'blocked') })
                foreach ($t in @($st.tasks)) { if ($t -and $t.id) { $harita[[string]$t.id] = [string]$t.status } } }
            $Onbellek.Kartlar = $kartlar; $Onbellek.KartDurumHarita = $harita
        } catch { if ($Onbellek.ContainsKey('Kartlar')) { $kartlar = $Onbellek.Kartlar } }   # yazilirken okunduysa onceki gorunum kalir
    }

    # --- takim kosulari + isciler (hizli) ---
    $isciOturum = @{}
    foreach ($f in @($(if ($Paths.TeamRuns -and (Test-Path -LiteralPath $Paths.TeamRuns)) { Get-ChildItem -LiteralPath $Paths.TeamRuns -Filter '*.json' -File -ErrorAction SilentlyContinue }))) {   # klasor yoksa her tazelemede $Error'a kayit dusmesin
        $k = $null
        if ($f.LastWriteTime -lt $simdi.AddDays(-7)) { continue }   # 7 gunden eski kosu (acik da olsa bayat): okunmaz, liste buyudukce maliyet artmaz
        try { $k = Read-MerkezJsonOnb $f.FullName $Onbellek $f } catch { $k = $null }
        if (-not $k) { continue }
        if (-not $k -or -not $k.runId) { continue }
        $kartHarita = $(if ($Onbellek.KartDurumHarita) { $Onbellek.KartDurumHarita } else { @{} })
        $k = Get-MerkezKosuEtkin $k $kartHarita   # salt okunur kosu bitti -> raporlar teslim alindi (etkin durum)
        $bitmis = [string]$k.status -in @('merged', 'aborted', 'failed')
        $kwsl = @($k.workers | Where-Object { $null -ne $_ })
        if (-not $bitmis -and $kwsl.Count -and -not @($kwsl | Where-Object { [string]$_.status -in @('queued', 'spawning', 'running', 'planned', 'paused_limit') }).Count -and
            -not @($kwsl | Where-Object { [string]$kartHarita[[string]$_.taskId] -notin @('done', 'cancelled') }).Count) { $bitmis = $true }   # salt-okunur kosu: kartlar kapandi
        if ($bitmis -and $f.LastWriteTime -lt $simdi.AddHours(-$SonKosuSaat)) { continue }
        if (-not $bitmis -and $f.LastWriteTime -lt $simdi.AddDays(-7)) { continue }   # insan onayi 7 gun gecerli; daha eski koşu bayattir
        $sahipsiz = [bool](([string]$k.status -eq 'running') -and @($k.workers | Where-Object { $_.status -in @('queued', 'spawning', 'running') }).Count -and (Test-MerkezGozetmenDurdu $k $Onbellek $simdi))
        $sonraki = Get-MerkezKosuSonraki $k $sahipsiz
        $ws = @($k.workers | Where-Object { $null -ne $_ })
        $jeton = 0.0; foreach ($w in $ws) { if ($w.usage) { try { $jeton += Get-MerkezEffectiveTokens $w.usage } catch { } } }
        $ozet = Get-MerkezKosuOzet $k $sahipsiz $simdi
        $kosuOge = @{ Kapasite = (Get-MerkezKosuKapasite $k); RunId = [string]$k.runId; Repo = [string]$k.repoName; Durum = [string]$k.status; Asama = (Get-MerkezKosuAsama $k); Sonraki = $sonraki; Ozet = $ozet
            Isci = $ws.Count; Biten = @($ws | Where-Object { $_.status -in @('finished', 'collected', 'integrated') }).Count
            Sorunlu = @($ws | Where-Object { $_.status -in @('failed', 'timed_out', 'scope_violation', 'rejected_content', 'conflict') }).Count
            Jeton = $jeton; Sahipsiz = $sahipsiz; KayitGuncel = $f.LastWriteTime; Bitmis = $bitmis
            Dogrulama = $(if ($k.verification) { [string]$k.verification.verdict } else { '' }) }
        foreach ($ok in $ozet.Keys) { if (-not $kosuOge.ContainsKey($ok) -or $ok -eq 'Sorunlu') { $kosuOge[$ok] = $ozet[$ok] } }   # sozlesme: ozet alanlari koşu ogesinde
        $a.Kosular.Add($kosuOge)
        if ($sonraki.Onay) { $a.Onaylar.Add(@{ Satir = ($sonraki.Metin -replace '^onay bekliyor → ', ''); Neden = "koşu $($k.runId) · $($k.repoName)" }) }
        if ($bitmis) { continue }
        foreach ($w in $ws) {
            $ev = $null; if ([string]$w.taskId -cmatch '\A[A-Za-z0-9][A-Za-z0-9._-]{0,63}\z' -and [string]$k.runId -cmatch '\A[A-Za-z0-9][A-Za-z0-9._-]{0,63}\z') { try { $ev = Join-Path (Join-Path (Join-Path $Paths.TeamRuns $k.runId) $w.taskId) 'events.jsonl' } catch { $ev = $null } }
            $nabiz = -1; if ($ev -and (Test-Path -LiteralPath $ev)) { $nabiz = ($simdi - (Get-Item -LiteralPath $ev).LastWriteTime).TotalSeconds }
            $surec = $null; if ($w.pid) { $surec = Test-MerkezPidCanli ([int]$w.pid) $Onbellek $simdi }
            $d = Get-MerkezDurum @{ Tur = 'isci'; IsciDurum = [string]$w.status; Verdict = [string]$w.verdict; NabizSn = $nabiz; SurecCanli = $surec; GozetmenDurdu = $sahipsiz; KartDurum = $kartHarita[[string]$w.taskId] }
            $balon = ''; if ($d.Durum -in @('calisiyor', 'engelli')) { $balon = Get-MerkezIsciEtkinlik $ev }
            elseif ($d.Durum -eq 'duraklatildi') { $balon = '‖ kota doldu' } elseif ($d.Durum -eq 'bitti') { $balon = '✓ teslim etti' }
            $basla = $null; if ($w.startedAt) { try { $basla = [datetime]$w.startedAt } catch { } }
            $son = $null; if ($w.finishedAt) { try { $son = [datetime]$w.finishedAt } catch { } }
            $a.Ajanlar.Add(@{ Tur = 'isci'; Ajan = 'codex'; Ad = [string]$w.taskId; Rol = [string]$w.role; Kanat = [string]$k.repoName; Kosu = [string]$k.runId
                Durum = $d.Durum; Kaynak = $d.Kaynak; Bayat = $d.Bayat; NabizSn = $nabiz; Balon = $balon; Basladi = $basla; Bitti = $son
                Jeton = (Get-MerkezEffectiveTokens $w.usage); Verdict = [string]$w.verdict; Pid = $w.pid
                Dosya = @($w.changedPaths | Where-Object { $_ }).Count; Commit = [bool]$w.commit })
            if ($d.Durum -eq 'duraklatildi') { $a.Teshis.Add(@{ Seviye = 'warn'; Metin = "$($w.taskId) kota sınırında · beyin takim resume --run $($k.runId) --wait" }) }
            elseif ($d.Bayat -and $d.Kaynak -eq 'surec') { $a.Teshis.Add(@{ Seviye = 'err'; Anahtar = "surec:$($w.taskId)"; Metin = "$($w.taskId) işçi süreci yok (koşu hâlâ çalışıyor görünüyor) · beyin takim resume --run $($k.runId)" }) }
            elseif ($d.Bayat -and $d.Kaynak -ne 'gozetmen' -and $nabiz -ge 0) { $a.Teshis.Add(@{ Seviye = 'warn'; Metin = "$($w.taskId) $([int]($nabiz / 60)) dk'dır olay üretmiyor" }) }
            elseif ($d.Durum -eq 'engelli') { $a.Teshis.Add(@{ Seviye = 'warn'; Anahtar = "engelli:$($k.runId):$($w.taskId)"; Metin = "$($w.taskId) işçisi engelli ($(@([string]$w.status, [string]$w.verdict | Where-Object { $_ }) -join ' / ')) · beyin takim izle $($k.runId) $($w.taskId)" }) }
            elseif ($d.Durum -eq 'engelli') { $a.Teshis.Add(@{ Seviye = 'warn'; Anahtar = "engelli:$($k.runId):$($w.taskId)"; Metin = "$($w.taskId) işçisi engelli ($(@([string]$w.status, [string]$w.verdict | Where-Object { $_ }) -join ' / ')) · beyin takim izle $($k.runId) $($w.taskId)" }) }
        }
        if ($sahipsiz) { $a.Teshis.Add(@{ Seviye = 'err'; Anahtar = "sahipsiz:$($k.runId)"; Metin = "koşu $($k.runId) sahipsiz (gözetmen durdu) · beyin takim resume --run $($k.runId)" }) }
        if ($k.integration -and -not $k.integration.ok -and [string]$k.status -eq 'integrated') { $a.Teshis.Add(@{ Seviye = 'err'; Anahtar = "kontrol:$($k.runId)"; Metin = "koşu $($k.runId) bütünleştirme kontrolü düştü" }) }
    }

    if (-not $Hizli -or -not $Onbellek.ContainsKey('SonKosu')) {
        $Onbellek.SonKosu = $null
        try {
            $sf = @($(if ($Paths.TeamRuns -and (Test-Path -LiteralPath $Paths.TeamRuns)) { Get-ChildItem -LiteralPath $Paths.TeamRuns -Filter '*.json' -File -ErrorAction SilentlyContinue }) | Sort-Object LastWriteTime -Descending | Select-Object -First 1)
            if ($sf.Count) { $sk = Read-MerkezJsonOnb $sf[0].FullName $Onbellek $sf[0]; if ($sk -and $sk.runId) { $Onbellek.SonKosu = @{ RunId = [string]$sk.runId; Durum = [string]$sk.status; Repo = [string]$sk.repoName; Zaman = $sf[0].LastWriteTime } } }
        } catch { }
    }
    $a.SonKosu = $Onbellek.SonKosu
    # Claude Code Workflow / Agent iscileri: tam turda taranir (~0,1 sn), hizli turda onbellekten
    if (-not $Hizli -or -not $Onbellek.ContainsKey('ClaudeIsler')) {
        $kok = $(if ($ClaudeKok) { $ClaudeKok } elseif ($env:BEYIN_CLAUDE_PROJE_KOK) { $env:BEYIN_CLAUDE_PROJE_KOK } else { Join-Path $env:USERPROFILE '.claude\projects' })
        try { $Onbellek.ClaudeIsler = Get-MerkezClaudeIsler -Kok $kok -Simdi $simdi } catch { $Onbellek.ClaudeIsler = (New-Object System.Collections.Generic.List[object]) }
    }
    $a.ClaudeIsler = $Onbellek.ClaudeIsler

    # --- liderler: oturum dosyalari (hizli) ---
    foreach ($f in @($(if ($Paths.Sessions -and (Test-Path -LiteralPath $Paths.Sessions)) { Get-ChildItem -LiteralPath $Paths.Sessions -Filter '*.json' -File -ErrorAction SilentlyContinue }) | Where-Object { $_.LastWriteTime -ge $simdi.AddHours(-24) })) {
        $o = $null
        try { $o = Read-MerkezJsonOnb $f.FullName $Onbellek $f } catch { $o = $null }
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
                if ($e) { $Onbellek["tx:$($ag.Ad)"] = [bool]$e.Ok }   # transkript bulundu mu (bos yeni oturum ile hic olmayan ayrilir)
                if ($e -and $e.Ok) { $Onbellek.Balon[$ag.Ad] = [string]$e.Metin; $Onbellek["tur:$($ag.Ad)"] = [string]$e.Tur; if ($e.Zaman) { $Onbellek.Nabiz[$ag.Ad] = [datetime]$e.Zaman } }
            } catch { }
        }
        if ($Onbellek.Balon.ContainsKey($ag.Ad)) { $ag.Balon = $Onbellek.Balon[$ag.Ad] }
        if ($Onbellek.ContainsKey("tx:$($ag.Ad)")) { $ag.Transkript = [bool]$Onbellek["tx:$($ag.Ad)"] }
        # NABIZ: oturum dosyasi yalniz kullanici mesajinda yazilir; calisan oturumun gercek nabzi transkriptin son kaydidir.
        if ($Onbellek.Nabiz.ContainsKey($ag.Ad)) {
            $tn = ($simdi - $Onbellek.Nabiz[$ag.Ad]).TotalSeconds
            if ($tn -ge 0 -and $tn -lt $ag.NabizSn) { $ag.NabizSn = $tn }
            $surec = $null; if ($ag.Pid) { $surec = Test-MerkezPidCanli ([int]$ag.Pid) $Onbellek $simdi }
            $d = Get-MerkezDurum @{ Tur = 'lider'; SurecCanli = $surec; NabizSn = $ag.NabizSn; Etkinlik = [string]$Onbellek["tur:$($ag.Ad)"] }
            $ag.Durum = $d.Durum; $ag.Kaynak = $(if ($d.Kaynak -eq 'nabiz') { 'transkript' } else { $d.Kaynak }); $ag.Bayat = $d.Bayat
        }
    }

    # Uzun sessizlik: lider 5+ dk ayni arac/dusunce kaydinda. Claude Code izin istemini transkripte yazmaz; uzun komut ile
    # "pencerede onay bekleyen komut" disaridan ayirt edilemez. Durum degismez (calisiyor), yalniz bakilacak yer soylenir.
    $uzun = @($a.Ajanlar | Where-Object { $_.Tur -eq 'lider' -and $_.Kaynak -eq 'uzun-arac' -and [double]$_.NabizSn -ge 300 })
    if ($uzun.Count) {
        $pr = @($uzun | ForEach-Object { Get-MerkezProje ([string]$_.Cwd) $Paths } | Where-Object { $_ } | Select-Object -Unique)
        $a.Teshis.Add(@{ Seviye = 'info'; Anahtar = 'uzun'; Metin = "$($uzun.Count) oturum 5+ dk tek araçta$(if ($pr.Count) { ' (' + (($pr | Select-Object -First 3) -join ', ') + ')' }) · izin onayı bekliyor olabilir, pencereye bak" })
    }

    # --- kartlar + onaylar ---
    # Yetim kart: sahibi "team-<runId>" olan acik kart, ama o kosu kapanmis (iptal/basarisiz/ana dalda). Kart kendiliginden
    # kapanmaz; panoda "bekliyor" gorunup sonsuza dek acik kalir. Teshis, kapatma komutunu verir (merkez yazmaz).
    $a.Yetim = @{}
    foreach ($k in $kartlar) {
        if ([string]$k.status -eq 'review') { continue }   # incelemedeki kart 'onayla' bekler (birlesen kosuda normal akis), yetim degil
        $ses = $(if ($k.owner) { [string]$k.owner.session } else { '' })
        if ($ses -notmatch '^team-(R[\w-]+)$') { continue }
        $rid = $Matches[1]; $rf = Join-Path $Paths.TeamRuns "$rid.json"
        $rk = $null; try { if (Test-Path -LiteralPath $rf) { $rk = Read-MerkezJsonOnb $rf $Onbellek } } catch { }
        if (-not $rk -and (Test-Path -LiteralPath $Paths.TeamRuns) -and -not (Test-Path -LiteralPath $rf)) { $a.Yetim[[string]$k.id] = @{ Run = $rid; Durum = 'kayip' }; continue }   # kosu kaydi yok (temizlenmis)
        if (-not $rk -and (Test-Path -LiteralPath $Paths.TeamRuns) -and -not (Test-Path -LiteralPath $rf)) { $a.Yetim[[string]$k.id] = @{ Run = $rid; Durum = 'kayip' }; continue }   # kosu kaydi yok (temizlenmis)
        if ($rk -and [string]$rk.status -in @('aborted', 'failed', 'merged')) { $a.Yetim[[string]$k.id] = @{ Run = $rid; Durum = [string]$rk.status } }
    }
    if ($a.Yetim.Count) {
        $ids = @($a.Yetim.Keys | Sort-Object); $ilk = $a.Yetim[$ids[0]]
        $dAd = @{ aborted = 'iptal'; failed = 'başarısız'; merged = 'ana dalda'; kayip = 'kaydı yok' }[$ilk.Durum]
        $a.Teshis.Add(@{ Seviye = 'warn'; Anahtar = 'yetim'; Metin = "$($ids.Count) kart kapanmış koşuya bağlı ($($ilk.Run) · $dAd) · beyin pano transition --task $($ids[0]) --status cancelled --reason 'koşu kapandı'" })
    }
    $a.Kartlar = @($kartlar | Sort-Object -Property @{ Expression = { switch ([string]$_.status) { 'blocked' { 0 } 'review' { 1 } 'in_progress' { 2 } default { 3 } } } }, @{ Expression = { [string]$_.id } })
    foreach ($k in $kartlar) { if ([string]$k.status -eq 'review') { $a.Onaylar.Add(@{ Satir = "onayla $($k.id)"; Neden = "kart incelemede$(if ([string]$k.title) { ' · ' + (Protect-MerkezSatir ([string]$k.title) 60) })" }) } }

    # --- aktarimlar (yavas) ---
    # Kademeli: aktarim listesi (~450 ms) tam tazelemede de en cok 20 sn'de bir okunur; animasyon donmasin
    $tazeAkt = $Onbellek.ContainsKey('ts:Aktarimlar') -and ($simdi - $Onbellek['ts:Aktarimlar']).TotalSeconds -lt 20
    if ($Onbellek.ContainsKey('Aktarimlar') -and ($Hizli -or $tazeAkt)) { $a.Aktarimlar = $Onbellek.Aktarimlar } else {
        $Onbellek['ts:Aktarimlar'] = $simdi
        try {
            $hdImza = ''; try { $di = New-Object IO.DirectoryInfo($Paths.Handoff); if ($di.Exists) { $hdImza = "$($di.LastWriteTimeUtc.Ticks)|$(@($di.GetFiles('*.json')).Count)" } } catch { }
            if ($hdImza -and $Onbellek['imza:AktarimDir'] -eq $hdImza -and $Onbellek.ContainsKey('AktarimHam')) { $ak = $Onbellek.AktarimHam }
            else { $ak = @(Get-BeyinHandoffListe -Paths $Paths | Where-Object { $_ -and [string]$_.status -ne 'tamam' -and [string]$_.kind -ne 'devir' }); $Onbellek.AktarimHam = $ak; $Onbellek['imza:AktarimDir'] = $hdImza }
            $a.Aktarimlar = @($ak | Sort-Object -Property @{ Expression = { [string]$_.ts } } -Descending)
            $Onbellek.Aktarimlar = $a.Aktarimlar
        } catch { if ($Onbellek.ContainsKey('Aktarimlar')) { $a.Aktarimlar = $Onbellek.Aktarimlar } }
    }
    $et = Get-MerkezEskiAktarim $a.Aktarimlar $simdi; if ($et) { $a.Teshis.Add($et) }

    # --- kaynak + maliyet (yavas) ---
    $tazeKay = $Onbellek.ContainsKey('ts:Kaynak') -and ($simdi - $Onbellek['ts:Kaynak']).TotalSeconds -lt 20
    if ($Onbellek.ContainsKey('Kaynak') -and ($Hizli -or $tazeKay)) { $a.Kaynak = $Onbellek.Kaynak } else {
        $Onbellek['ts:Kaynak'] = $simdi
        $taze = [bool]$Onbellek.KaynakTaze; $Onbellek.KaynakTaze = $false
        $yeniK = $null; try { $yeniK = Get-BeyinKaynakOzeti -Paths $Paths -SaltOkunur -OnbellekDk $(if ($taze) { 0 } else { 1 }) } catch { $yeniK = $null }   # read-only monitor never refreshes disk caches
        # yuk altinda olcum ara sira bos doner (CIM zaman asimi): 10 dk'ya kadar son iyi olcum kalir, yoksa bellek alarmi
        # bir kaybolup bir gelir ve her geliste yeniden bildirim/nabiz tetiklenirdi
        if ((-not $yeniK -or -not $yeniK.Ok) -and $Onbellek.Kaynak -and $Onbellek.Kaynak.Ok -and $Onbellek.ContainsKey('ts:KaynakIyi') -and ($simdi - $Onbellek['ts:KaynakIyi']).TotalMinutes -lt 10) { $yeniK = $Onbellek.Kaynak }
        elseif ($yeniK -and $yeniK.Ok) { $Onbellek['ts:KaynakIyi'] = $simdi }
        $a.Kaynak = $yeniK; $Onbellek.Kaynak = $a.Kaynak
    }
    if ($Hizli -and $Onbellek.ContainsKey('Maliyet')) { $a.Maliyet = $Onbellek.Maliyet } else {
        $m = $null; $mf = Join-Path $Paths.ScrState 'maliyet\son.json'
        try { if (Test-Path -LiteralPath $mf) { $m = (Read-MerkezPaylasimli $mf) | ConvertFrom-Json } } catch { }
        $a.Maliyet = $m; $Onbellek.Maliyet = $m
    }
    if ($a.Kaynak -and $a.Kaynak.Ok) {
        if ($a.Kaynak.CommitYuzde -ge 85) {
            $enCok = Get-MerkezBellekDokum $Onbellek $simdi
            $a.Teshis.Add(@{ Seviye = 'err'; Anahtar = 'commit'; Metin = "bellek (commit) %$($a.Kaynak.CommitYuzde)$(if ($enCok) { ' · en çok: ' + $enCok }) · bekçi listeler, kapatma kararı senin · beyin bekci" })
        }
        if ($a.Kaynak.BostaOturum -ge 5) { $a.Teshis.Add(@{ Seviye = 'warn'; Metin = "son 24 saatte açılmış $($a.Kaynak.BostaOturum) oturum 2+ saattir sessiz (kapanmış olabilir) · beyin bekci" }) }
    }

    # --- son olaylar (yavas; makbuz kuyrugu) + oturum -> kanat eslemesi ---
    # olay akisi yalniz bugunun makbuz dosyasi buyudugunde yeniden okunur (imza: boy + gun)
    $mkF = $(if ($Paths.Makbuz) { Join-Path $Paths.Makbuz ($simdi.ToString('yyyy-MM-dd') + '.jsonl') } else { '' }); $mkImza = ''
    try { if ($mkF -and (Test-Path -LiteralPath $mkF)) { $mkImza = "$((Get-Item -LiteralPath $mkF).Length)|$($simdi.ToString('yyyyMMdd'))" } } catch { }
    if ($Onbellek.ContainsKey('Olaylar') -and ($Hizli -or $Onbellek['imza:Olaylar'] -eq $mkImza)) { $a.Olaylar = $Onbellek.Olaylar } else {
        $a.Olaylar = $(if ($Paths.Makbuz) { Get-MerkezOlaylar $Paths.Makbuz 60 $simdi } else { New-Object System.Collections.Generic.List[object] }); $Onbellek.Olaylar = $a.Olaylar; $Onbellek['imza:Olaylar'] = $mkImza
        $Onbellek.Etkinlik = $(if ($Paths.Makbuz) { Get-MerkezEtkinlikHisto $Paths.Makbuz 12 10 $simdi } else { New-Object int[] 12 })
    }
    $a.Etkinlik = $(if ($Onbellek.ContainsKey('Etkinlik')) { $Onbellek.Etkinlik } else { New-Object int[] 12 })
    $kanatOf = @{}; foreach ($ag in $a.Ajanlar) { if ($ag.Tur -eq 'lider' -and $ag.Ad) { $kanatOf[[string]$ag.Ad] = [string]$ag.Kanat } }
    foreach ($ol in $a.Olaylar) { $ol.Kanat = $(if ($ol.Anahtar -and $kanatOf.ContainsKey($ol.Anahtar)) { $kanatOf[$ol.Anahtar] } else { '' }) }

    # Channel state is read directly: calling its CLI here could refresh/write state.
    $channelSeen = @{}
    foreach ($ag in @(Get-MerkezKanalIsciler -Paths $Paths)) {
        if ($channelSeen.ContainsKey($ag.Ad)) { continue }; $channelSeen[$ag.Ad] = $true
        $a.Ajanlar.Add($ag)
        if ($ag.Onay) { $a.Onaylar.Add(@{ Satir="beyin $($ag.Ajan) durum $($ag.Ad)"; Neden="$($ag.Ad): $($ag.Onay) kanal onayi bekliyor" }) }
    }
    $a.Kuyruk = @($a.Ajanlar | Where-Object { $_.Durum -eq 'bekliyor' -or $_.Kuyruk } | ForEach-Object { @{ Ad=$_.Ad; Proje=$_.Kanat; Durum=$_.Durum; Kuyruk=$_.Kuyruk } })
    $a.Sprint = @($kartlar | Group-Object -Property { if ($_.sprint) { [string]$_.sprint } else { 'sprint yok' } } | ForEach-Object { @{ Ad=$_.Name; Acik=$_.Count } })
    # --- sayaclar ---
    foreach ($ag in $a.Ajanlar) { $s = [string]$ag.Durum; if ($a.Sayac.ContainsKey($s)) { $a.Sayac[$s]++ } else { $a.Sayac[$s] = 1 } }
    # --- Bugun seridi (yavas kaynaklar; yalniz tam turda, onbellekli) ---
    if ($Hizli -and $Onbellek.ContainsKey('Bugun')) { $a.Bugun = $Onbellek.Bugun } else {
        try { $a.Bugun = Get-MerkezBugun $Paths $Onbellek $a.Ajanlar $simdi } catch { $a.Bugun = $null }
        $Onbellek.Bugun = $a.Bugun
    }

    # eski maliyet taramasi: bugun rakami sabahtan kalmissa bilgi (panel taramayi kendisi baslatmaz, ~18 sn surer)
    if ($a.Bugun -and $a.Bugun.UsdZaman -and ($simdi - [datetime]$a.Bugun.UsdZaman).TotalHours -gt 6) {
        $a.Teshis.Add(@{ Seviye = 'info'; Anahtar = 'maliyet-eski'; Metin = "bugünkü maliyet $([int]($simdi - [datetime]$a.Bugun.UsdZaman).TotalHours) saat önce tarandı · beyin maliyet" })
    }

    # --- acik ajanin ayrintisi ---
    $a.Ayrinti = $null
    if ($AyrintiAnahtar) {
        foreach ($ag in $a.Ajanlar) {
            if ("$($ag.Tur):$($ag.Kosu):$($ag.Ad)" -ne $AyrintiAnahtar) { continue }
            try {
                if ($ag.Tur -eq 'isci') {
                    if ([string]$ag.Kosu -cnotmatch '\A[A-Za-z0-9][A-Za-z0-9._-]{0,63}\z' -or [string]$ag.Ad -cnotmatch '\A[A-Za-z0-9][A-Za-z0-9._-]{0,63}\z') { throw 'gecersiz kimlik' }   # yol gezinme yok
                    $ev = Join-Path (Join-Path (Join-Path $Paths.TeamRuns $ag.Kosu) $ag.Ad) 'events.jsonl'
                    $a.Ayrinti = @{ Ok = $true; Adimlar = @(Get-MerkezIsciAdimlar $ev 5); Baglam = $null; Toplam = $(if ($ag.Jeton) { [int64]$ag.Jeton } else { $null }); Model = ''; SonIstem = $null; SonBitis = $ag.Bitti }
                } elseif (Get-Command Get-MerkezAyrinti -ErrorAction SilentlyContinue) {
                    $ak = "ayrinti:$AyrintiAnahtar"
                    if ($Onbellek.ContainsKey($ak) -and ($simdi - $Onbellek[$ak].Zaman).TotalSeconds -lt 4) { $a.Ayrinti = $Onbellek[$ak].Sonuc }
                    else { $a.Ayrinti = Get-MerkezAyrinti -Ajan $ag.Ajan -OturumId $ag.Ad -Cwd $ag.Cwd -Adim 5; $Onbellek[$ak] = @{ Zaman = $simdi; Sonuc = $a.Ayrinti } }
                }
                if ($a.Ayrinti -and $a.Bugun -and $a.Bugun.MalOturum -and $a.Bugun.MalOturum.ContainsKey([string]$ag.Ad)) { $a.Ayrinti.MaliyetUsd = $a.Bugun.MalOturum[[string]$ag.Ad].Usd; $a.Ayrinti.MaliyetZaman = $a.Bugun.UsdZaman }
            } catch { $a.Ayrinti = $null }
            break
        }
    }
    $a.Sirada = Get-MerkezSirada $a
    return $a
}

# =====================================================================================================================
# 1.5.0: Bugun seridi, ajan ayrintisi, satir komutu. Hepsi SALT OKUNUR, asla firlatmaz; her kaynak boyut+zaman ya da
# kalinan bayt konumuyla onbellekli (kare basina dosya taramasi yok).
# =====================================================================================================================

function Read-MerkezEkSatirlar([string]$Yol, [long]$Ofset) {
    # Dosyanin $Ofset'ten sonraki TAM satirlari (son yarim satir bir sonraki okumaya kalir). @{ Satirlar; Ofset }
    $fs = [System.IO.File]::Open($Yol, 'Open', 'Read', ([System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete))
    try {
        if ($Ofset -gt $fs.Length) { $Ofset = 0 }   # dosya kuculdu/yenilendi: bastan
        $n = [int][Math]::Min(8MB, $fs.Length - $Ofset); if ($n -le 0) { return @{ Satirlar = @(); Ofset = $Ofset } }
        [void]$fs.Seek($Ofset, 'Begin'); $buf = New-Object byte[] $n; $okunan = 0
        while ($okunan -lt $n) { $r = $fs.Read($buf, $okunan, $n - $okunan); if ($r -le 0) { break }; $okunan += $r }
        $son = [Array]::LastIndexOf($buf, [byte]10, $okunan - 1); if ($son -lt 0) { return @{ Satirlar = @(); Ofset = $Ofset } }
        $metin = [Text.Encoding]::UTF8.GetString($buf, 0, $son + 1)
        return @{ Satirlar = @($metin -split "`n"); Ofset = $Ofset + $son + 1 }
    } finally { $fs.Dispose() }
}

$script:MerkezRxTs = [regex]'"ts":"([^"]+)"'; $script:MerkezRxSc = [regex]'"script":"([^"]+)"'
$script:MerkezRxOc = [regex]'"outcome":"([^"]+)"'; $script:MerkezRxKey = [regex]'"key":"([^"]*)"'
function Get-MerkezGunSayac([string]$MakbuzDizin, [datetime]$Gun, [hashtable]$Onbellek) {
    # Bir gunun makbuz sayaclari, DAKIKA cozunurlugunde (dun "bu saate kadar" karsilastirmasi icin). Bugunun dosyasi
    # artimli okunur (kalinan bayt), gecmis gun dosyasi bir kez. Donus: Oturum/Ozet/Yayin/Derleme/Hata her biri int[1440].
    $ad = $Gun.ToString('yyyy-MM-dd'); $k = "gun:$ad"
    if (-not $Onbellek.ContainsKey($k)) {
        $Onbellek[$k] = @{ Ofset = [long]0; Oturum = (New-Object int[] 1440); Ozet = (New-Object int[] 1440); Yayin = (New-Object int[] 1440)
                           Derleme = (New-Object int[] 1440); Hata = (New-Object int[] 1440); Engel = (New-Object int[] 1440); Anahtar = (New-Object 'System.Collections.Generic.HashSet[string]'); Son = @{} }
    }
    $d = $Onbellek[$k]
    try {
        $f = Join-Path $MakbuzDizin "$ad.jsonl"
        if (Test-Path -LiteralPath $f) {
            if ((Get-Item -LiteralPath $f).Length -lt $d.Ofset) { foreach ($alan in @('Oturum', 'Ozet', 'Yayin', 'Derleme', 'Hata', 'Engel')) { [Array]::Clear($d[$alan], 0, 1440) }; $d.Anahtar.Clear(); $d.Ofset = 0 }
            $r = Read-MerkezEkSatirlar $f $d.Ofset
            foreach ($sat in $r.Satirlar) {
                $mt = $script:MerkezRxTs.Match($sat); if (-not $mt.Success) { continue }
                $t = [datetime]::MinValue; if (-not [datetime]::TryParse($mt.Groups[1].Value, [ref]$t)) { continue }
                if ($t.Date -ne $Gun.Date) { continue }
                $dk = $t.Hour * 60 + $t.Minute
                $sc = $script:MerkezRxSc.Match($sat).Groups[1].Value; $oc = $script:MerkezRxOc.Match($sat).Groups[1].Value
                switch ("$sc/$oc") {
                    'session-start/ENJEKSIYON' { $ky = $script:MerkezRxKey.Match($sat).Groups[1].Value; if ($ky -and $d.Anahtar.Add($ky)) { $d.Oturum[$dk]++ } }
                    'flush/FLUSH_OK' { $d.Ozet[$dk]++ }
                    'yayinla/YAYIN_OK' { $d.Yayin[$dk]++ }
                    'compile/COMPILE_OK' { $d.Derleme[$dk]++ }
                }
                # onerilen komutun son calismasi: aktar yalniz kapatinca sayilir (listeleme/gosterim her turda yazilir, kanit degildir)
                $sonAd = $(if ($sc -eq 'aktar') { $(if ($oc -eq 'AKTAR_TAMAM') { 'aktar' } else { '' }) } else { $sc })
                if ($sonAd -and (-not $d.Son.ContainsKey($sonAd) -or $t -gt $d.Son[$sonAd])) { $d.Son[$sonAd] = $t }
                if ($oc -match 'HATA|DUSTU|BOZUK') { $d.Hata[$dk]++ } elseif ($oc -eq 'RED') { $d.Engel[$dk]++ }   # kill guard engeli hata degil
            }
            $d.Ofset = $r.Ofset
        }
    } catch { }
    return $d
}
function Get-MerkezDakikaToplam([int[]]$Dizi, [int]$Dakika = 1439) { $s = 0; for ($i = 0; $i -le [Math]::Min(1439, $Dakika); $i++) { $s += $Dizi[$i] }; return $s }

function Get-MerkezMaliyetGun([string]$Dizin, [datetime]$Gun, [hashtable]$Onbellek) {
    # maliyet\gun\<gun>.json (beyin maliyet / gece maliyet-tara yazar): Claude USD + Codex jeton + dosya zamani + oturum
    # basina USD/jeton (ayrinti paneli). Dosya yoksa $null. Panel taramayi KENDISI baslatmaz (~18 sn surer).
    $f = Join-Path $Dizin ($Gun.ToString('yyyy-MM-dd') + '.json')
    try {
        if (-not (Test-Path -LiteralPath $f)) { return $null }
        $o = Read-MerkezJsonOnb $f $Onbellek; if (-not $o -or -not $o.k) { return $null }
        $ck = "malgun:$f"; $imza = [string]$Onbellek["json:$f"].Imza
        if ($Onbellek.ContainsKey($ck) -and $Onbellek[$ck].Imza -eq $imza) { return $Onbellek[$ck].Sonuc }
        $usd = 0.0; $cj = [int64]0; $ot = @{}
        foreach ($p in $o.k.PSObject.Properties) {
            $par = $p.Name -split '\|'; $v = $p.Value
            if ($par[0] -eq 'claude') { $usd += [double]$v.usd } elseif ($par[0] -eq 'codex') { $cj += [int64]$v.in + [int64]$v.out }
            if ($par.Count -ge 3) { $s = $par[2]; if (-not $ot.ContainsKey($s)) { $ot[$s] = @{ Usd = 0.0; Jeton = [int64]0 } }; $ot[$s].Usd += [double]$v.usd; $ot[$s].Jeton += [int64]$v.in + [int64]$v.out + [int64]$v.cr }
        }
        $sonuc = @{ ClaudeUsd = $usd; CodexJeton = $cj; Zaman = (Get-Item -LiteralPath $f).LastWriteTime; Oturum = $ot }
        $Onbellek[$ck] = @{ Imza = $imza; Sonuc = $sonuc }
        return $sonuc
    } catch { return $null }
}

$script:MerkezGitKokOnb = @{}
function Get-MerkezGitDizin([string]$Cwd) {
    # Calisma klasorunden yukari .git'i bulur; .git DOSYA ise (worktree) gitdir: izlenir. Sonuc klasor basina onbellekte.
    if (-not $Cwd) { return $null }
    if ($script:MerkezGitKokOnb.ContainsKey($Cwd)) { return $script:MerkezGitKokOnb[$Cwd] }
    $sonuc = $null
    try {
        $d = $Cwd
        for ($i = 0; $i -lt 12 -and $d; $i++) {
            $g = Join-Path $d '.git'
            if (Test-Path -LiteralPath $g -PathType Container) { $sonuc = $g; break }
            if (Test-Path -LiteralPath $g -PathType Leaf) {
                $ic = [IO.File]::ReadAllText($g); if ($ic -match 'gitdir:\s*(.+)') { $gd = $Matches[1].Trim(); if (-not [IO.Path]::IsPathRooted($gd)) { $gd = Join-Path $d $gd }; $sonuc = $gd }
                break
            }
            $d = Split-Path -Parent $d
        }
    } catch { }
    if ($sonuc) { $script:MerkezGitKokOnb[$Cwd] = $sonuc }; return $sonuc
}
$script:MerkezRxReflog = [regex]'^[0-9a-f]{40} [0-9a-f]{40} [^\t]*? (\d{9,11}) [+-]\d{4}\t(commit(?: \((?:amend|merge|initial)\))?):'
function Get-MerkezGitBugun([string[]]$GitDizinler, [datetime]$Simdi, [hashtable]$Onbellek) {
    # git CALISTIRMADAN: her deponun logs\HEAD kuyrugu (64 KB) okunur; bugunun ve dunun commit'leri.
    # Bu makinede yapilan commit'leri sayar (cekme/yeniden temelleme sayilmaz). @{ Bugun; Dun; DunSimdiye; Depo }
    $bugun = 0; $dun = 0; $dunSimdi = 0; $depo = @{}; $dk = $Simdi.Hour * 60 + $Simdi.Minute
    $tek = @{}; foreach ($x in @($GitDizinler | Where-Object { $_ })) { try { $n0 = [IO.Path]::GetFullPath([string]$x).TrimEnd('\', '/').ToLowerInvariant() } catch { $n0 = ([string]$x).ToLowerInvariant() }; if (-not $tek.ContainsKey($n0)) { $tek[$n0] = [string]$x } }
    foreach ($gd in @($tek.Values | Select-Object -First 12)) {
        try {
            $lf = Join-Path $gd 'logs\HEAD'; if (-not (Test-Path -LiteralPath $lf)) { continue }
            $fi = Get-Item -LiteralPath $lf; $imza = "$($fi.Length)|$($fi.LastWriteTimeUtc.Ticks)|$($Simdi.ToString('yyyyMMdd'))"; $ck = "reflog:$lf"
            if (-not ($Onbellek.ContainsKey($ck) -and $Onbellek[$ck].Imza -eq $imza)) {
                $zl = New-Object System.Collections.Generic.List[datetime]
                foreach ($s in @(Read-MerkezSonSatirlar -Yol $lf -Bayt 65536)) {
                    $m = $script:MerkezRxReflog.Match($s); if (-not $m.Success) { continue }
                    $t = [DateTimeOffset]::FromUnixTimeSeconds([int64]$m.Groups[1].Value).LocalDateTime
                    if ($t.Date -ge $Simdi.Date.AddDays(-1)) { $zl.Add($t) }
                }
                $Onbellek[$ck] = @{ Imza = $imza; Zaman = $zl }
            }
            $n = 0
            foreach ($t in $Onbellek[$ck].Zaman) {
                if ($t.Date -eq $Simdi.Date) { $bugun++; $n++ } elseif ($t.Date -eq $Simdi.Date.AddDays(-1)) { $dun++; if (($t.Hour * 60 + $t.Minute) -le $dk) { $dunSimdi++ } }
            }
            if ($n) { $depoAd = Split-Path -Leaf ($gd -replace '[\\/]\.git([\\/].*)?$', ''); $depo[$depoAd] = [int]$depo[$depoAd] + $n }   # worktree: ...\.git\worktrees\x -> depo adi
        } catch { }
    }
    return @{ Bugun = $bugun; Dun = $dun; DunSimdiye = $dunSimdi; Depo = $depo }
}

function Get-MerkezBugun([hashtable]$Paths, [hashtable]$Onbellek, $Ajanlar, [datetime]$Simdi) {
    # Bugun seridi: bugun ve dun (AYNI SAATE KADAR) oturum, ozet, yayin, commit; maliyet gunluk dosyadan; 24 saatlik dagilim.
    $b = @{ Ok = $true; Saatlik = (New-Object int[] 24) }
    $dk = $Simdi.Hour * 60 + $Simdi.Minute
    if ($Paths.Makbuz) {
        $g = Get-MerkezGunSayac $Paths.Makbuz $Simdi.Date $Onbellek; $y = Get-MerkezGunSayac $Paths.Makbuz $Simdi.Date.AddDays(-1) $Onbellek
        $b.SonCalisma = $g.Son
        $tk = "bugun-top:$($g.Ofset)|$($y.Ofset)|$dk|$($Simdi.ToString('yyyyMMdd'))"
        if ($Onbellek.ContainsKey($tk)) { foreach ($e in $Onbellek[$tk].GetEnumerator()) { $b[$e.Key] = $e.Value } }
        else {
        foreach ($ad in @('Oturum', 'Ozet', 'Yayin', 'Derleme', 'Hata', 'Engel')) { $b[$ad] = (Get-MerkezDakikaToplam $g[$ad]); $b["${ad}Dun"] = (Get-MerkezDakikaToplam $y[$ad] $dk) }
        for ($i = 0; $i -lt 1440; $i++) { $b.Saatlik[[int][Math]::Floor($i / 60)] += $g.Oturum[$i] + $g.Ozet[$i] + $g.Yayin[$i] + $g.Derleme[$i] }
            foreach ($eski in @($Onbellek.Keys | Where-Object { $_ -like 'bugun-top:*' })) { $Onbellek.Remove($eski) }
            $yS = New-Object int[] 24; for ($i = 0; $i -lt 1440; $i++) { $yS[[int][Math]::Floor($i / 60)] += $y.Oturum[$i] + $y.Ozet[$i] + $y.Yayin[$i] + $y.Derleme[$i] }
            $sa = $Simdi.Hour; $b.Son24 = @(for ($j = $sa + 1; $j -le 23; $j++) { $yS[$j] }) + @(for ($j = 0; $j -le $sa; $j++) { $b.Saatlik[$j] })   # dunun kalan saatleri + bugun: her zaman 24 saat
            $kayit = @{}; foreach ($ad in @('Oturum', 'Ozet', 'Yayin', 'Derleme', 'Hata', 'Engel')) { $kayit[$ad] = $b[$ad]; $kayit["${ad}Dun"] = $b["${ad}Dun"] }; $kayit.Saatlik = $b.Saatlik; $kayit.Son24 = $b.Son24
            $Onbellek[$tk] = $kayit
        }
    }
    $mDir = Join-Path $Paths.ScrState 'maliyet\gun'
    $mb = Get-MerkezMaliyetGun $mDir $Simdi.Date $Onbellek; $my = Get-MerkezMaliyetGun $mDir $Simdi.Date.AddDays(-1) $Onbellek
    $b.Usd = $(if ($mb) { $mb.ClaudeUsd } else { $null }); $b.UsdZaman = $(if ($mb) { $mb.Zaman } else { $null }); $b.UsdDun = $(if ($my) { $my.ClaudeUsd } else { $null })
    $b.CodexJeton = $(if ($mb) { $mb.CodexJeton } else { $null }); $b.MalOturum = $(if ($mb) { $mb.Oturum } else { @{} })
    $b.Gunluk = @(for ($i = 6; $i -ge 0; $i--) { $g = Get-MerkezMaliyetGun $mDir $Simdi.Date.AddDays(-$i) $Onbellek; $(if ($g) { [double]$g.ClaudeUsd } else { 0.0 }) })   # 7 gun, eskiden yeniye
    # git kokleri: vault + liderlerin calisma klasorleri; en cok 12
    $gd = @((Get-MerkezGitDizin $Paths.Vault)); foreach ($ag in $Ajanlar) { if ($ag.Tur -eq 'lider' -and $ag.Cwd) { $gd += (Get-MerkezGitDizin ([string]$ag.Cwd)) } }
    $gt = Get-MerkezGitBugun $gd $Simdi $Onbellek
    $b.Commit = $gt.Bugun; $b.CommitDun = $gt.DunSimdiye; $b.CommitDepo = $gt.Depo
    return $b
}

$script:MerkezIsciAdimOnb = @{}
function Get-MerkezIsciAdimlar([string]$EventsYol, [int]$Adet = 5) {
    # Isci events.jsonl kuyrugundan son $Adet adim (yeniden eskiye) @{ Zaman; Metin }; boyut+zaman onbellegi.
    if (-not $EventsYol -or -not (Test-Path -LiteralPath $EventsYol)) { return @() }
    try {
        $fi = Get-Item -LiteralPath $EventsYol; $imza = "$($fi.Length)|$($fi.LastWriteTimeUtc.Ticks)|$Adet"
        if ($script:MerkezIsciAdimOnb.ContainsKey($EventsYol) -and $script:MerkezIsciAdimOnb[$EventsYol].Imza -eq $imza) { return $script:MerkezIsciAdimOnb[$EventsYol].Adim }
        $sonuc = New-Object System.Collections.Generic.List[object]
        $satirlar = @(Read-MerkezSonSatirlar -Yol $EventsYol -Bayt 131072)
        for ($i = $satirlar.Count - 1; $i -ge 0 -and $sonuc.Count -lt $Adet; $i--) {
            $s = $satirlar[$i].Trim(); if (-not $s.StartsWith('{')) { continue }
            $o = $null; try { $o = $s | ConvertFrom-Json } catch { continue }
            $it = $o.item; if (-not $it -or [string]$it.type -notin @('command_execution', 'file_change', 'mcp_tool_call', 'web_search')) { continue }
            $m = switch ([string]$it.type) {
                'command_execution' { "▸ Shell: $(([string]$it.command) -replace '^"?[^"]*powershell(\.exe)?"?\s+(-\w+\s+)*', '' -replace '^-Command\s+', '')" }
                'file_change' { $ch = @($it.changes | Where-Object { $_ }); "▸ Edit: $(if ($ch.Count) { Split-Path -Leaf ([string]$ch[0].path) })$(if ($ch.Count -gt 1) { " +$($ch.Count - 1)" })" }
                'mcp_tool_call' { "▸ mcp: $($it.server).$($it.tool)" }
                default { "▸ Web: $($it.query)" }
            }
            $m = Protect-MerkezSatir $m 160
            if ($sonuc.Count -and $sonuc[$sonuc.Count - 1].Metin -eq $m) { continue }   # started + completed cifti tek adim
            $z = $null; try { if ($o.timestamp) { $z = [datetime]$o.timestamp } } catch { }
            $sonuc.Add(@{ Zaman = $z; Metin = $m })
        }
        $arr = [object[]]$sonuc.ToArray(); $script:MerkezIsciAdimOnb[$EventsYol] = @{ Imza = $imza; Adim = $arr }; return $arr
    } catch { return @() }
}

# --- satir komutu (c: panoya kopyala) ---
# Yalniz BEYAZ LISTEDEKI bicimler kopyalanir; ajan metninden turetilen parca kontrol dizisi ya da kabuk isleci (; | & $ ` < > ( ) { })
# iceriyorsa reddedilir. Sonda satir sonu YOK: yapistirinca kendiliginden calismaz. Onay satirlari (onayla/baslat/birlestir)
# SOHBETE yapistirilir, terminale degil.
$script:MerkezKomutRxEski = [regex]"^(beyin [a-z][\w-]*|onayla TASK-[\w-]+|baslat R[\w-]+|birlestir R[\w-]+|claude --resume [\w-]+|codex resume [\w-]+)( [\w\-\.:/\\'=~ ışğüöçİŞĞÜÖÇ]*)?$"
$script:MerkezKomutBicim = @(
    '^beyin aktar -Tamam [A-Za-z0-9][A-Za-z0-9._-]{0,63}$'
    "^beyin pano transition --task TASK-[0-9]{1,6} --status cancelled --reason 'koşu kapandı'$"
    '^beyin pano show --task TASK-[0-9]{1,6}$'
    '^onayla TASK-[A-Z0-9](?:[A-Z0-9-]{0,46}[A-Z0-9])?$', '^baslat R[0-9A-Za-z-]{1,40}$', '^birlestir R[0-9A-Za-z-]{1,40}$'
    '^claude --resume [0-9A-Fa-f-]{8,64}$', '^codex resume [0-9A-Fa-f-]{8,64}$'
    '^beyin takim (izle|durum|status|collect|integrate|lead-review|verify|resume|cleanup) (--run )?R[0-9A-Za-z-]{1,40}( TASK-[0-9]{1,6}| --wait| --recheck| --approved)?$'
    '^beyin (bekci|maliyet|doktor|aktar)$'
)
function Test-MerkezGuvenliKomut([string]$Komut) {
    # Beyaz liste TUR BASINA tam eslesme: kimlikler yalniz ASCII, serbest ek yok, alt komut sabit (ajan metninden '· beyin guncelle
    # -Uygula' gibi bir kuyruk kopyalanamaz). -cmatch: buyuk/kucuk harf ve Unicode rakam hilesi yok.
    if (-not $Komut -or $Komut.Length -gt 200) { return $false }
    if ($Komut -match '[\x00-\x1f\x7f-\x9f;|&`$<>(){}"]') { return $false }
    foreach ($b in $script:MerkezKomutBicim) { if ($Komut -cmatch $b) { return $true } }
    return $false
}
function Get-MerkezSatirKomut($Oge) {
    # $Oge: @{ Tur = onay|aktarim|kart|kosu|teshis|lider|isci|bugun; Nesne; Yetim(bool) }. Donus: @{ Komut; Ipucu } ya da $null
    if (-not $Oge) { return $null }
    $n = $Oge.Nesne; $k = ''; $ip = 'terminale yapıştır'
    switch ([string]$Oge.Tur) {
        'onay'    { $k = [string]$n.Satir; $ip = 'sohbete tek başına yapıştır' }
        'aktarim' { $k = "beyin aktar -Tamam $([string]$n.id)" }
        'kart'    { if ($Oge.Yetim) { $k = "beyin pano transition --task $([string]$n.id) --status cancelled --reason 'koşu kapandı'" } elseif ([string]$n.status -eq 'review') { $k = "onayla $([string]$n.id)"; $ip = 'sohbete tek başına yapıştır (önce bağımsız doğrulama)' } else { $k = "beyin pano show --task $([string]$n.id)" } }
        'kosu'    { $sm = [string]$n.Sonraki.Metin; if ($sm -match '^onay bekliyor → (.+)$') { $k = $Matches[1].Trim(); $ip = 'sohbete tek başına yapıştır' } elseif ($sm -match '(beyin [^·→]+?)\s*$') { $k = $Matches[1].Trim() } else { $k = "beyin takim durum $([string]$n.RunId)" } }
        'teshis'  { if ([string]$n.Metin -match '·\s*(beyin [^·]+)$') { $k = $Matches[1].Trim() } }
        'lider'   { $k = $(if ($n.Ajan -eq 'codex') { "codex resume $([string]$n.Ad)" } else { "claude --resume $([string]$n.Ad)" }); $ip = 'yeni terminalde oturumu sürdürür' }
        'isci'    { $k = "beyin takim izle $([string]$n.Kosu) $([string]$n.Ad)" }
        'bugun'   { $k = 'beyin maliyet' }
    }
    if (-not $k -or -not (Test-MerkezGuvenliKomut $k)) { return $null }
    return @{ Komut = $k; Ipucu = $ip }
}
