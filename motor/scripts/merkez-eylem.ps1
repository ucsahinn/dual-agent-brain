# merkez-eylem.ps1 - Beyin MERKEZ eylem katmani (2026-10-31, motor 1.9.0).
#
# NEDEN: merkez 1.8'e kadar salt okunurdu; kullanici her kart icin sohbete 'onayla TASK-x' yaziyor, terminalde kod giriyor,
# kosu adimlarini (collect, integrate, verify, merge) elle kopyalayip calistiriyordu. Bu katman secili satir(lar) icin
# EYLEM listesi uretir (tus, ad, adimlar) ve adimlari calistirir:
#   - insan onayi: merkez surecinin KENDISINDE, gercek tus basisiyla (Console.ReadKey) yazilir; kanal 'merkez', ajan 'insan'.
#     Ajan kabugu etkilesimsizdir (stdin yonlendirilmis) ve merkez penceresine tus basamaz; -Tek/-Olcum ciktisinda eylem yok.
#     Bicim BEYIN_MERKEZ_ONAY ile: 'tus' (onay penceresinde Y), 'kod' (ekrandaki 4 haneli kod). Ayrinti: 60-decisions/ADR-014.
#   - komut: `beyin <argv>` merkez-is.ps1 kosucusuyla calisir (uzun takim adimlari gorunur WT sekmesinde, kisalar gizli);
#     sonuc .state\merkez-isler\<id>.json'a yazilir, merkez okur. Argv BEYAZ LISTEDEN gecer (Test-MerkezEylemArgv) - ajan
#     metninden turetilen serbest metin calistirilmaz.
# Bu dosya merkez.ps1 ve merkez-is.ps1 tarafindan dot-source edilir; lib.ps1 (Add-BeyinOnay, Get-BeyinAyar) yuklu olmalidir.

$script:MerkezEylemKartRx = 'TASK-[A-Za-z0-9](?:[A-Za-z0-9-]{0,46}[A-Za-z0-9])?'
$script:MerkezEylemKosuRx = 'R[0-9A-Za-z](?:[0-9A-Za-z-]{0,40}[0-9A-Za-z])?'
$script:MerkezEylemAktRx = '[A-Za-z0-9][A-Za-z0-9._-]{0,63}'

function Get-MerkezIsDizin([hashtable]$Paths) {
    $d = Join-Path $Paths.ScrState 'merkez-isler'
    if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Force -Path $d | Out-Null }
    return $d
}
function Get-MerkezBeyinCli {
    $y = Join-Path $env:USERPROFILE '.beyin\beyin.ps1'
    return $y
}
function Protect-MerkezEylemMetin([string]$Metin, [int]$Uzunluk = 200) {
    # Ekrana basilacak cikti satiri: kontrol dizileri (ESC, OSC, C1) ve sekmeler temizlenir, uzunluk sinirlanir.
    $s = ([string]$Metin) -replace '\x1b\[[0-9;?]*[ -/]*[@-~]', '' -replace '\x1b\][^\x07\x1b]*(\x07|\x1b\\)?', '' -replace '[\x00-\x08\x0b-\x1f\x7f-\x9f]', '' -replace '\t', ' '
    $s = $s.Trim()
    if ($s.Length -gt $Uzunluk) { $s = $s.Substring(0, [Math]::Max(1, $Uzunluk - 1)) + '…' }
    return $s
}

# --- beyaz liste: calistirilabilecek argv bicimleri (tam eslesme, buyuk/kucuk harf duyarli) ---
function Get-MerkezEylemSiniflari {
    # TEK TABLO (AgentSpace incelemesi 2026-10-31): her calistirilabilir kalip TEK sinifa baglidir; sinif eyleme sonradan verilmez.
    #   serbest : okur ya da geri alinabilir kucuk yazim; oto-duzeltmeye girebilir (Oto bayragiyla)
    #   adim    : kosuyu ilerleten sef adimi (kaynak harcar); teyitsiz calisir ama ASLA oto degil
    #   onay    : insan onayi dosyasi gerektirir (done, start, merge); onay penceresi zorunlu
    #   tehlike : geri donussuz (abort, iptal); onay penceresi + her zaman kod
    $T = $script:MerkezEylemKartRx; $R = $script:MerkezEylemKosuRx; $A = $script:MerkezEylemAktRx
    return @(
        @{ Rx = "^takim (status|collect) --run $R$"; Sinif = 'serbest' }
        @{ Rx = "^takim izle $R( $T)?$"; Sinif = 'serbest' }
        @{ Rx = "^aktar -Tamam $A$"; Sinif = 'serbest' }
        @{ Rx = '^aktar -Topla -Uygula$'; Sinif = 'serbest' }
        # komut paleti (? ekrani): argumansiz cagrida YALNIZ GOSTEREN komutlar; yeni sekmede kosar
        @{ Rx = '^(durum|canli|kapasite|copcu|ayar|gecmis|makbuz)$'; Sinif = 'serbest' }
        @{ Rx = '^aktar( -Topla)?$'; Sinif = 'serbest' }
        @{ Rx = '^(maliyet|bekci|doktor)$'; Sinif = 'serbest' }
        @{ Rx = '^derle-zorla$'; Sinif = 'serbest' }
        @{ Rx = "^takim (integrate|verify|lead-review) --run $R$"; Sinif = 'adim' }
        @{ Rx = "^takim integrate --run $R --recheck$"; Sinif = 'adim' }
        @{ Rx = "^takim resume --run $R( --wait)?$"; Sinif = 'adim' }
        @{ Rx = "^takim (start|merge) --run $R$"; Sinif = 'onay' }
        @{ Rx = "^pano transition --task $T --status done --verified-by user$"; Sinif = 'onay' }
        @{ Rx = "^takim durdur $R$"; Sinif = 'tehlike' }
        @{ Rx = "^pano transition --task $T --status cancelled --reason kosu-kapandi$"; Sinif = 'tehlike' }
    )
}
function Get-MerkezEylemBicimleri { return @(Get-MerkezEylemSiniflari | ForEach-Object { $_.Rx }) }
function Get-MerkezEylemSinif([string[]]$Argv) {
    # Argv'nin sinifi; beyaz liste disi ise ''.
    if (-not (Test-MerkezEylemArgv $Argv)) { return '' }
    $s = @($Argv) -join ' '
    foreach ($b in (Get-MerkezEylemSiniflari)) { if ($s -cmatch $b.Rx) { return [string]$b.Sinif } }
    return ''
}
function Write-MerkezRed([hashtable]$Paths, [string]$Kod, [string]$Not) {
    # Fail-closed red: her ret makbuza kodla duser (beyaz-liste-disi, insan-teyidi-yok, onay-yazilamadi, durum-degisti, iptal-edildi, zaman-asimi)
    try { Write-BeyinMakbuz -Paths $Paths -Script 'merkez' -Outcome 'EYLEM_RED' -Agent 'merkez' -Reason $Kod -Note (Protect-MerkezEylemMetin $Not 160) } catch { }
}
function Test-MerkezEylemArgv([string[]]$Argv) {
    $Argv = @($Argv | Where-Object { $null -ne $_ })
    if (-not $Argv.Count -or $Argv.Count -gt 10) { return $false }
    foreach ($x in $Argv) { if (-not $x -or $x.Length -gt 80 -or $x -match '[\s\x00-\x1f\x7f-\x9f;|&`$<>(){}"''%!^,]') { return $false } }
    $s = $Argv -join ' '
    foreach ($b in (Get-MerkezEylemBicimleri)) { if ($s -cmatch $b) { return $true } }
    return $false
}
function ConvertTo-MerkezEylemArgv([string]$Komut) {
    # 'beyin takim verify --run R1' -> @('takim','verify','--run','R1'); beyaz listede degilse $null.
    $k = ([string]$Komut).Trim()
    if ($k -notmatch '^beyin\s+(.+)$') { return $null }
    $parca = @($Matches[1] -split '\s+' | Where-Object { $_ })
    if (Test-MerkezEylemArgv $parca) { return ,$parca }
    return $null
}

# --- eylem modeli ---
# @{ Kod; Tus; Ad; Insan (bool: insan onayi yazar); Tehlike (bool: Y ile teyit); Toplu (bool: isaretli coklu secimde calisir)
#    Adimlar = @( @{ Tur = 'onay'; Id; OnayTur } | @{ Tur = 'komut'; Argv; Gorunur } ); Oto (bool: oto-duzeltmede kendiliginden) ; Aciklama }
function New-MerkezEylem([string]$Kod, [string]$Tus, [string]$Ad, [object[]]$Adimlar, [switch]$Insan, [switch]$Tehlike, [switch]$Toplu, [switch]$Oto, [string]$Aciklama = '') {
    # Sinif tablosu kazanir: komut adimlarindan biri 'tehlike' ise Tehlike, biri 'onay' ise Insan; Oto yalniz BUTUN adimlar 'serbest' ise.
    $siniflar = @($Adimlar | Where-Object { $_ -and $_.Tur -eq 'komut' } | ForEach-Object { Get-MerkezEylemSinif @($_.Argv) })
    $tehlikeT = [bool]$Tehlike -or ($siniflar -contains 'tehlike')
    $insanT = [bool]$Insan -or [bool](@($Adimlar | Where-Object { $_ -and $_.Tur -eq 'onay' }).Count)
    $otoT = [bool]$Oto -and -not $insanT -and -not $tehlikeT -and $siniflar.Count -gt 0 -and -not @($siniflar | Where-Object { $_ -ne 'serbest' }).Count
    return @{ Kod = $Kod; Tus = $Tus; Ad = $Ad; Adimlar = @($Adimlar); Insan = $insanT; Tehlike = $tehlikeT; Toplu = [bool]$Toplu; Oto = $otoT; Aciklama = $Aciklama; Siniflar = $siniflar }
}
function New-MerkezKomutAdim([string[]]$Argv, [switch]$Gorunur) { return @{ Tur = 'komut'; Argv = @($Argv); Gorunur = [bool]$Gorunur } }
function New-MerkezOnayAdim([string]$Id, [string]$OnayTur = '') { return @{ Tur = 'onay'; Id = $Id; OnayTur = $OnayTur } }

function Get-MerkezKartKapatEylem([string]$TaskId) {
    if ($TaskId -cnotmatch "^$($script:MerkezEylemKartRx)$") { return $null }
    return (New-MerkezEylem 'kart-onayla' 'o' 'onayla ve kapat' @((New-MerkezOnayAdim $TaskId), (New-MerkezKomutAdim @('pano', 'transition', '--task', $TaskId, '--status', 'done', '--verified-by', 'user'))) -Insan -Toplu `
        -Aciklama "insan onayı yazılır, kart 'done' olur (doğrulayan: sen · --verified-by user)")
}
function Get-MerkezKosuKapiEylem([string]$Tur, [string]$RunId) {
    if ($RunId -cnotmatch "^$($script:MerkezEylemKosuRx)$") { return $null }
    if ($Tur -eq 'baslat') { return (New-MerkezEylem 'kosu-baslat' 'o' 'başlat (onay + start)' @((New-MerkezOnayAdim $RunId 'baslat'), (New-MerkezKomutAdim @('takim', 'start', '--run', $RunId) -Gorunur)) -Insan -Aciklama 'işçiler başlar; çıktı yeni sekmede') }
    if ($Tur -eq 'birlestir') { return (New-MerkezEylem 'kosu-birlestir' 'o' 'birleştir (onay + merge)' @((New-MerkezOnayAdim $RunId 'birlestir'), (New-MerkezKomutAdim @('takim', 'merge', '--run', $RunId) -Gorunur)) -Insan -Aciklama 'ara dal senin dalına girer; çıktı yeni sekmede') }
    return $null
}
function Get-MerkezSonrakiEylem($Kosu) {
    # Kosunun "sonraki adim" metninden calistirilabilir eylem: collect/integrate/verify/resume/lead-review.
    $m = [string]$Kosu.Sonraki.Metin
    if ($m -notmatch '(beyin takim [^·→]+?)\s*$') { return $null }
    $argv = ConvertTo-MerkezEylemArgv $Matches[1]
    if (-not $argv) { return $null }
    $alt = [string]$argv[1]
    $ad = switch ($alt) { 'collect' { 'topla' } 'integrate' { 'bütünleştir' } 'verify' { 'doğrula' } 'resume' { 'sürdür' } 'lead-review' { 'şef incelemesi' } default { $alt } }
    $oto = ($alt -eq 'collect')   # isciler bitti, topla: motorun kendi defter isi, guvenli
    return (New-MerkezEylem "kosu-$alt" 'n' "sıradaki adım: $ad" @((New-MerkezKomutAdim $argv -Gorunur:($alt -ne 'collect'))) -Oto:$oto -Aciklama "beyin $($argv -join ' ')")
}
function Get-MerkezTeshisEylem($Teshis) {
    # Teshisin duzeltmesi: yapisal 'Duzelt' alani (Argv, Oto) ya da metnin sonundaki '· beyin ...' komutu.
    if (-not $Teshis) { return $null }
    if ($Teshis.Duzelt -and $Teshis.Duzelt.Coklu) {
        # coklu duzeltme (or. yetim kartlarin hepsini iptal): her argv ayri adim, hepsi beyaz listeden
        $ad = @(); foreach ($c in @($Teshis.Duzelt.Coklu)) { if (Test-MerkezEylemArgv @($c)) { $ad += (New-MerkezKomutAdim @($c)) } }
        if (-not $ad.Count) { return $null }
        $iptal = [bool](@($Teshis.Duzelt.Coklu | Where-Object { @($_) -contains 'cancelled' }).Count)
        return (New-MerkezEylem 'teshis-duzelt' 'd' ([string]$Teshis.Duzelt.Ad) $ad -Tehlike:$iptal -Aciklama "$($ad.Count) komut")
    }
    $argv = $null; $oto = $false
    # Komut YALNIZ yapisal Duzelt alanindan: Metin ajan metni (aktarim kimligi, proje adi) tasir; sonundaki '· beyin ...'
    # parcasi calistirilmaz (inceleme 2026-10-31: 'x · beyin takim durdur R1' kimlikli aktarim d tusuyla abort tetikliyordu).
    if ($Teshis.Duzelt -and $Teshis.Duzelt.Argv) { if (Test-MerkezEylemArgv @($Teshis.Duzelt.Argv)) { $argv = @($Teshis.Duzelt.Argv); $oto = [bool]$Teshis.Duzelt.Oto } }
    if (-not $argv) { return $null }
    $alt = [string]$argv[0]
    # gorunur: uzun takim adimlari ve ciktisi okunacak raporlar (bekci, doktor); gizli: kisa yazma adimlari
    $uzun = (($alt -eq 'takim' -and [string]$argv[1] -in @('resume', 'integrate', 'verify', 'lead-review')) -or $alt -in @('bekci', 'doktor'))
    $tehlike = (($alt -eq 'pano' -and $argv -contains 'cancelled') -or ($alt -eq 'takim' -and [string]$argv[1] -in @('durdur', 'start', 'merge')))
    if ($tehlike) { $oto = $false }
    $ad = $(if ($Teshis.Duzelt -and $Teshis.Duzelt.Ad) { [string]$Teshis.Duzelt.Ad } elseif ($alt -eq 'bekci') { 'bekçi raporunu aç' } elseif ($alt -eq 'aktar') { 'en eski aktarımı kapat (okundu)' } else { "düzelt: beyin $($argv -join ' ')" })
    return (New-MerkezEylem 'teshis-duzelt' 'd' $ad @((New-MerkezKomutAdim $argv -Gorunur:$uzun)) -Tehlike:$tehlike -Oto:$oto -Aciklama "beyin $($argv -join ' ')")
}

function Get-MerkezEylemler($Oge, $Anlik = $null) {
    # Secili ogenin eylemleri (ilk eleman varsayilan). Bilinmeyen tur: bos liste.
    $L = New-Object System.Collections.Generic.List[object]
    if (-not $Oge) { return @() }
    $n = $Oge.Nesne
    switch ([string]$Oge.Tur) {
        'kart' {
            $id = [string]$n.id
            if ([string]$n.status -eq 'review') { $e = Get-MerkezKartKapatEylem $id; if ($e) { $L.Add($e) } }
            if ($Oge.Yetim -and $id -cmatch "^$($script:MerkezEylemKartRx)$") { $L.Add((New-MerkezEylem 'kart-iptal' 'x' 'iptal et (koşu kapandı)' @((New-MerkezKomutAdim @('pano', 'transition', '--task', $id, '--status', 'cancelled', '--reason', 'kosu-kapandi'))) -Tehlike -Toplu -Aciklama 'kart cancelled olur')) }
        }
        'onay' {
            $s = [string]$n.Satir
            if ($s -cmatch "^onayla ($($script:MerkezEylemKartRx))$") { $e = Get-MerkezKartKapatEylem $Matches[1]; if ($e) { $L.Add($e) } }
            elseif ($s -cmatch "^(baslat|birlestir) ($($script:MerkezEylemKosuRx))$") { $e = Get-MerkezKosuKapiEylem $Matches[1] $Matches[2]; if ($e) { $L.Add($e) } }
        }
        'kosu' {
            $rid = [string]$n.RunId
            if ([string]$n.Sonraki.Metin -match '^onay bekliyor → (baslat|birlestir) ') { $e = Get-MerkezKosuKapiEylem $Matches[1] $rid; if ($e) { $L.Add($e) } }
            $e = Get-MerkezSonrakiEylem $n; if ($e) { $L.Add($e) }
            if ($Anlik -and $Anlik.Kartlar) {
                $inc = @($Anlik.Kartlar | Where-Object { [string]$_.status -eq 'review' -and $_.owner -and [string]$_.owner.session -eq "team-$rid" } | ForEach-Object { [string]$_.id })
                if ($inc.Count) {
                    $ad = @(); foreach ($t in $inc) { $k = Get-MerkezKartKapatEylem $t; if ($k) { $ad += $k.Adimlar } }
                    if ($ad.Count) { $L.Add((New-MerkezEylem 'kosu-kartlar' 'O' "$($inc.Count) kartı onayla ve kapat" $ad -Insan -Aciklama "incelemedeki kartlar: $(($inc | Select-Object -First 6) -join ', ')$(if ($inc.Count -gt 6) { ' …' })")) }
                }
            }
            if ([string]$n.Durum -in @('planned', 'running', 'paused', 'collected', 'integrated', 'verified') -and $rid -cmatch "^$($script:MerkezEylemKosuRx)$") {
                $L.Add((New-MerkezEylem 'kosu-durdur' 'x' 'koşuyu durdur (abort)' @((New-MerkezKomutAdim @('takim', 'durdur', $rid) -Gorunur)) -Tehlike -Aciklama 'motor yalnız kendi işçilerini durdurur'))
            }
        }
        'teshis' { $e = Get-MerkezTeshisEylem $n; if ($e) { $L.Add($e) } }
        'aktarim' {
            $id = [string]$n.id
            if ($id -cmatch "^$($script:MerkezEylemAktRx)$") { $L.Add((New-MerkezEylem 'aktarim-kapat' 't' 'aktarımı kapat (okundu)' @((New-MerkezKomutAdim @('aktar', '-Tamam', $id))) -Toplu -Aciklama "beyin aktar -Tamam $id")) }
            # T: hepsini kurala gore topla (teslim edilmis / yetim devir / bayat); taze ve gorulmemis mesaj KALIR
            $L.Add((New-MerkezEylem 'aktarim-topla' 'T' 'hepsini topla (teslim edilmiş/yetim/bayat)' @((New-MerkezKomutAdim @('aktar', '-Topla', '-Uygula'))) -Oto -Aciklama 'beyin aktar -Topla -Uygula · önizleme: beyin aktar -Topla'))
        }
        'isci' {
            $rid = [string]$n.Kosu; $tid = [string]$n.Ad
            if ($rid -cmatch "^$($script:MerkezEylemKosuRx)$" -and [string]$n.Durum -eq 'duraklatildi') { $L.Add((New-MerkezEylem 'isci-surdur' 'n' 'kotadan sürdür' @((New-MerkezKomutAdim @('takim', 'resume', '--run', $rid, '--wait') -Gorunur)) -Aciklama "beyin takim resume --run $rid --wait")) }
        }
    }
    return $L.ToArray()
}

# --- toplu eylem birlestirme: isaretli ogelerde ayni Kod'lu eylemlerin adimlari tek pencerede ---
function Get-MerkezBakimEylemi($Anlik) {
    # BAKIM TURU (2026-11-07, tus B): bekleyen guvenli bakim islerini tek onayla sirayla kosar.
    # Yalniz beyaz listede 'serbest' komutlar; neyin gerektigi anlik teshisten okunur:
    #   aktar -Topla -Uygula : acik aktarim varsa (kurallar yeni/gorulmemisi zaten birakir)
    #   derle-zorla          : deneme tavanina carpmis gun varsa
    #   maliyet              : bugunku maliyet 6+ saat eskiyse
    $tes = @(); if ($Anlik -and $Anlik.Teshis) { $tes = @($Anlik.Teshis) }
    $anahtar = @{}; foreach ($t in $tes) { if ($t.Anahtar) { $anahtar[[string]$t.Anahtar] = $true } }
    $ad = @()
    if ($Anlik -and @($Anlik.Aktarimlar | Where-Object { $_ }).Count) { $ad += , (New-MerkezKomutAdim @('aktar', '-Topla', '-Uygula')) }
    if ($anahtar.ContainsKey('derleme-tavan')) { $ad += , (New-MerkezKomutAdim @('derle-zorla')) }
    if ($anahtar.ContainsKey('maliyet-eski')) { $ad += , (New-MerkezKomutAdim @('maliyet')) }
    if (-not $ad.Count) { return $null }
    $ozet = @($ad | ForEach-Object { 'beyin ' + (@($_.Argv) -join ' ') }) -join ' → '
    return (New-MerkezEylem 'bakim' 'B' "bakım turu ($($ad.Count) iş)" $ad -Oto -Aciklama $ozet)
}
function Join-MerkezEylemler([object[]]$Eylemler) {
    $E = @($Eylemler | Where-Object { $_ })
    if (-not $E.Count) { return $null }
    if ($E.Count -eq 1) { return $E[0] }
    $ilk = $E[0]; $ad = New-Object System.Collections.Generic.List[object]
    foreach ($e in $E) { foreach ($s in $e.Adimlar) { $ad.Add($s) } }
    $ozet = "$($E.Count) öğe · $($ilk.Ad)"
    return (New-MerkezEylem $ilk.Kod $ilk.Tus $ozet $ad.ToArray() -Insan:([bool]($E | Where-Object { $_.Insan })) -Tehlike:([bool]($E | Where-Object { $_.Tehlike })) -Toplu -Aciklama $ilk.Aciklama)
}
function Get-MerkezEylemHedefleri($Eylem) {
    # Onay penceresinde gosterilecek satirlar: her adim icin okunur ozet.
    $s = New-Object System.Collections.Generic.List[string]
    foreach ($a in $Eylem.Adimlar) {
        if ($a.Tur -eq 'onay') { $s.Add($(if ($a.OnayTur) { "insan onayı · $($a.OnayTur) $($a.Id)" } else { "insan onayı · $($a.Id)" })) }
        else {
            $sn = Get-MerkezEylemSinif @($a.Argv)
            $etki = switch ($sn) { 'tehlike' { '   [geri alınamaz]' } 'onay' { '   [kalıcı]' } 'adim' { '   [koşu ilerler]' } default { '' } }
            $s.Add("beyin $(@($a.Argv) -join ' ')$etki$(if ($a.Gorunur) { '   (yeni sekmede)' })")
        }
    }
    return $s.ToArray()
}

# --- calistirma ---
function New-MerkezIsId { return ('{0}-{1}' -f (Get-Date).ToString('yyyyMMddHHmmss'), [guid]::NewGuid().ToString('N').Substring(0, 6)) }
function Start-MerkezKomut {
    # Kosucuyu baslatir; donus @{ Ok; Id; Neden }. Gorunur: Windows Terminal yeni sekme (yoksa ayri pencere); degilse gizli.
    param([hashtable]$Paths, [string[]]$Argv, [switch]$Gorunur, [string]$Zincir = '')
    if (-not (Test-MerkezEylemArgv $Argv)) { Write-MerkezRed $Paths 'beyaz-liste-disi' (@($Argv) -join ' '); return @{ Ok = $false; Id = ''; Neden = 'komut beyaz listede değil' } }
    $cli = Get-MerkezBeyinCli
    if (-not (Test-Path -LiteralPath $cli)) { return @{ Ok = $false; Id = ''; Neden = "beyin CLI yok: $cli" } }
    $id = New-MerkezIsId
    [void](Get-MerkezIsDizin -Paths $Paths)
    $kosucu = Join-Path $Paths.Scripts 'merkez-is.ps1'
    $ps = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $kosucu, '-Vault', [string]$Paths.Vault, '-IsId', $id)
    if ($Gorunur) { $ps += '-Gorunur' }
    $ps += $Argv
    $q = { param($x) if ($x -match '[\s"]') { '"' + ($x -replace '"', '') + '"' } else { $x } }
    try {
        $wt = $(if ($Gorunur) { (Get-Command wt.exe -ErrorAction SilentlyContinue).Source } else { $null })
        if ($wt) {
            $baslik = ("beyin $($Argv -join ' ')" -replace '[;"]', ' ')
            $wa = @('-w', '0', 'new-tab', '--title', $baslik, 'powershell.exe') + $ps
            Start-Process -FilePath $wt -ArgumentList (@($wa | ForEach-Object { & $q $_ }) -join ' ') | Out-Null
        } elseif ($Gorunur) {
            Start-Process -FilePath 'powershell.exe' -ArgumentList (@($ps | ForEach-Object { & $q $_ }) -join ' ') | Out-Null
        } else {
            Start-Process -FilePath 'powershell.exe' -ArgumentList (@($ps | ForEach-Object { & $q $_ }) -join ' ') -WindowStyle Hidden | Out-Null
        }
    } catch { return @{ Ok = $false; Id = $id; Neden = $_.Exception.Message } }
    return @{ Ok = $true; Id = $id; Neden = '' }
}
function Read-MerkezIs([hashtable]$Paths, [string]$Id) {
    if ($Id -notmatch '^[A-Za-z0-9-]{6,64}$') { return $null }
    $f = Join-Path (Get-MerkezIsDizin -Paths $Paths) "$Id.json"
    if (-not (Test-Path -LiteralPath $f)) { return $null }
    try { return ((Get-Content -LiteralPath $f -Raw -Encoding UTF8) | ConvertFrom-Json) } catch { return $null }
}
function Get-MerkezSonIsler([hashtable]$Paths, [int]$Saat = 12, [int]$Adet = 20) {
    # Son isler (yeniden eskiye). Eski kayitlar (7 gun) silinir: klasor buyumez.
    $L = New-Object System.Collections.Generic.List[object]
    try {
        $d = Get-MerkezIsDizin -Paths $Paths; $sinir = (Get-Date).AddHours(-$Saat); $sil = (Get-Date).AddDays(-7)
        foreach ($f in @(Get-ChildItem -LiteralPath $d -Filter '*.json' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)) {
            if ($f.LastWriteTime -lt $sil) { Remove-Item -LiteralPath $f.FullName -ErrorAction SilentlyContinue; continue }
            if ($f.LastWriteTime -lt $sinir -or $L.Count -ge $Adet) { continue }
            try { $o = (Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8) | ConvertFrom-Json; if ($o -and $o.id) { $L.Add($o) } } catch { }
        }
    } catch { }
    return $L.ToArray()
}
function Test-MerkezIsCanli($Is) {
    # 'calisiyor' yazan ama sureci olmeyen is (pencere kapatildi): yetim sayilir.
    if (-not $Is -or [string]$Is.durum -ne 'calisiyor') { return $false }
    try { $pr = Get-Process -Id ([int]$Is.pid) -ErrorAction Stop; return [bool]$pr } catch { return $false }
}

function Revoke-MerkezOnay {
    # Kuyruk dustu / panel kapandi: bu partide yazilip KULLANILMAMIS kart onayi gecersizlenir (7 gun acik kalmasin).
    param([hashtable]$Paths, [string[]]$Idler, [string]$Neden = 'merkez-iptal')
    $n = 0
    foreach ($id in @($Idler | Where-Object { $_ } | Select-Object -Unique)) {
        if (Use-BeyinOnay -Paths $Paths -TaskId $id -Kullanan $Neden) { $n++; try { Write-BeyinMakbuz -Paths $Paths -Script 'pano' -Outcome 'ONAY_IPTAL' -Agent 'merkez' -Reason 'merkez' -Note "$id $Neden" } catch { } }
    }
    return $n
}
function Test-MerkezHedefGuncel {
    # YURUTME ANINDA YENIDEN DENETIM: kart hala 'review' mi, kosu hala ayni kapida mi? Taze okuma (onbellek yok).
    # Donus: '' (guncel) ya da neden metni. Okunamazsa fail-closed: 'okunamadi'.
    param([hashtable]$Paths, $Adim, [hashtable]$Pano = $null)
    try {
        if ($Adim.OnayTur) {
            $f = Join-Path $Paths.TeamRuns "$($Adim.Id).json"
            if (-not (Test-Path -LiteralPath $f)) { return 'koşu kaydı yok' }
            $k = (Get-Content -LiteralPath $f -Raw -Encoding UTF8) | ConvertFrom-Json
            $bek = $(if ($Adim.OnayTur -eq 'baslat') { 'planned' } else { 'verified' })
            if ([string]$k.status -ne $bek) { return "koşu artık '$($k.status)'" }
            return ''
        }
        if (-not $Pano) { return 'pano okunamadı' }
        if (-not $Pano.ContainsKey([string]$Adim.Id)) { return 'kart yok' }
        $st = [string]$Pano[[string]$Adim.Id]
        if ($st -ne 'review') { return "kart artık '$st'" }
        return ''
    } catch { return 'okunamadı' }
}
function Read-MerkezPanoDurum([hashtable]$Paths) {
    try {
        if (-not $Paths.Board -or -not (Test-Path -LiteralPath $Paths.Board)) { return $null }
        $fs = New-Object IO.FileStream($Paths.Board, [IO.FileMode]::Open, [IO.FileAccess]::Read, ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
        try { $st = (New-Object IO.StreamReader($fs, [Text.Encoding]::UTF8, $true)).ReadToEnd() | ConvertFrom-Json } finally { $fs.Dispose() }
        $h = @{}; foreach ($t in @($st.tasks)) { if ($t -and $t.id) { $h[[string]$t.id] = [string]$t.status } }
        return $h
    } catch { return $null }
}
function Get-MerkezOnayBicimi {
    $v = 'tus'; try { $v = [string](Get-BeyinAyar 'BEYIN_MERKEZ_ONAY' 'tus') } catch { $v = 'kod' }
    if ($v -notin @('tus', 'kod', 'kapali')) { $v = 'kod' }   # bozuk/gecersiz ayar: guclu kapi (fail-closed)
    return $v
}
function Invoke-MerkezEylemAdimlari {
    # Insan teyidi ALINDIKTAN SONRA cagrilir (merkez.ps1 onay penceresi). Onay adimlari bu surecte yazilir; komut adimlari
    # sirayla kuyruga girer: ayni karta ait 'onay' adimi basarisizsa o kartin komutu calistirilmaz.
    # Donus: @{ Onay = [string[]]; OnayHata = [string[]]; Isler = [object[]] (@{Id;Argv;Gorunur;Ok;Neden}); Kuyruk = [object[]] }
    param([hashtable]$Paths, $Eylem, [switch]$InsanTeyit)
    $r = @{ Onay = New-Object System.Collections.Generic.List[string]; OnayHata = New-Object System.Collections.Generic.List[string]; Atlanan = New-Object System.Collections.Generic.List[string]; Isler = New-Object System.Collections.Generic.List[object]; Kuyruk = New-Object System.Collections.Generic.List[object] }
    $dusen = @{}
    $pano = $null; if (@($Eylem.Adimlar | Where-Object { $_.Tur -eq 'onay' -and -not $_.OnayTur }).Count) { $pano = Read-MerkezPanoDurum -Paths $Paths }
    foreach ($a in $Eylem.Adimlar) {
        if ($a.Tur -eq 'onay') {
            if (-not $InsanTeyit) { $r.OnayHata.Add("$($a.Id): insan teyidi yok"); $dusen[[string]$a.Id] = $true; Write-MerkezRed $Paths 'insan-teyidi-yok' ([string]$a.Id); continue }
            $guncel = Test-MerkezHedefGuncel -Paths $Paths -Adim $a -Pano $pano
            if ($guncel) { $r.Atlanan.Add("$($a.Id): $guncel"); $dusen[[string]$a.Id] = $true; Write-MerkezRed $Paths 'durum-degisti' "$($a.Id) $guncel"; continue }
            $k = Add-BeyinOnay -Paths $Paths -TaskId ([string]$a.Id) -Kanal 'merkez' -Ajan 'insan' -Tur ([string]$a.OnayTur)
            if ($k.Ok) {
                $r.Onay.Add($(if ($a.OnayTur) { "$($a.OnayTur) $($a.Id)" } else { [string]$a.Id }))
                try { Write-BeyinMakbuz -Paths $Paths -Script $(if ($a.OnayTur) { 'takim' } else { 'pano' }) -Outcome 'ONAY_KAYDEDILDI' -Agent 'insan' -Reason 'merkez' -Note $(if ($a.OnayTur) { "$($a.OnayTur) $($a.Id)" } else { [string]$a.Id }) } catch { }
            } else { $r.OnayHata.Add("$($a.Id): $($k.Hata)"); $dusen[[string]$a.Id] = $true; Write-MerkezRed $Paths 'onay-yazilamadi' "$($a.Id) $($k.Hata)" }
            continue
        }
        $hedef = ''; for ($i = 0; $i -lt @($a.Argv).Count; $i++) { if ([string]$a.Argv[$i] -in @('--task', '--run') -and $i + 1 -lt @($a.Argv).Count) { $hedef = [string]$a.Argv[$i + 1] } }
        if ($hedef -and $dusen.ContainsKey($hedef)) { continue }
        $r.Kuyruk.Add(@{ Argv = @($a.Argv); Gorunur = [bool]$a.Gorunur; OnayId = $(if ($hedef -and $r.Onay -contains $hedef) { $hedef } else { '' }) })
    }
    return $r
}
