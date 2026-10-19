param(
    [string]$Vault = '',
    [switch]$Tek,          # bir kare ciz ve cik (test / ekran goruntusu icin)
    [int]$Genislik = 0,    # pencere genisligini ez (test: 90 / 120 / 170 / 210)
    [int]$Yukseklik = 0,
    [switch]$Aktifler,     # -Tek ile: Genel sekmesinde canli ekrandaki varsayilan gorunum (yalniz aktif kanatlar)
    [ValidateSet('Genel', 'Ajanlar', 'Kosular', 'Olaylar', 'Hepsi')][string]$Sekme = 'Genel',   # Hepsi: -Tek ile dort sekme ard arda
    [switch]$Ayrinti,      # -Tek ile: ilk secilebilir ajanin ayrintisi acik cizilir
    [ValidateSet('', 'osc', 'boya', 'kapali')][string]$Zemin = '',
    [switch]$Yardim,      # -Tek ile: ? yardim katmani acik cizilir
    [int]$Olcum = 0        # N kare cizip ortalama / p95 suresini yazar (cizimi ekrana basmaz)
)
# ---------- baslatici ----------
# Yeniden yukleme eskiden yeni powershell'i ICERIDEN baslatip bekliyordu: her yayin bir sureci (135-205 MB) bellekte birakiyordu
# (11 saatlik panelde dort surec zinciri). Simdi kucuk bir baslatici dongusu calisir; panel yeniden yuklenmek isteyince 75 koduyla
# cikar, baslatici onu acik sekmesiyle yeniden baslatir. Bellekte en cok baslatici + bir panel kalir.
if (-not $Tek -and $Olcum -le 0 -and -not $env:BEYIN_MERKEZ_IC) {
    $env:BEYIN_MERKEZ_IC = '1'; $sk = $(if ($Sekme -eq 'Hepsi') { 'Genel' } else { $Sekme })
    $env:BEYIN_MERKEZ_SEKME_DOSYA = Join-Path ([IO.Path]::GetTempPath()) "beyin-merkez-$([guid]::NewGuid().ToString('N')).sekme"
    do {
        $arg = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath, '-Sekme', $sk)
        if ($Vault) { $arg += @('-Vault', $Vault) }; if ($Zemin) { $arg += @('-Zemin', $Zemin) }; if ($Genislik) { $arg += @('-Genislik', $Genislik) }; if ($Yukseklik) { $arg += @('-Yukseklik', $Yukseklik) }
        & powershell.exe @arg; $kod = $LASTEXITCODE
        try { if (Test-Path -LiteralPath $env:BEYIN_MERKEZ_SEKME_DOSYA) { $sk = ([IO.File]::ReadAllText($env:BEYIN_MERKEZ_SEKME_DOSYA)).Trim(); Remove-Item -LiteralPath $env:BEYIN_MERKEZ_SEKME_DOSYA -ErrorAction SilentlyContinue } } catch { }
        if ($sk -notin @('Genel', 'Ajanlar', 'Kosular', 'Olaylar')) { $sk = 'Genel' }
    } while ($kod -eq 75)
    exit $kod
}
$script:sekmeDosya = $env:BEYIN_MERKEZ_SEKME_DOSYA
Remove-Item Env:\BEYIN_MERKEZ_IC, Env:\BEYIN_MERKEZ_SEKME_DOSYA -ErrorAction SilentlyContinue   # panelin actigi wt sekmelerine sizmasin
# merkez.ps1 - Beyin MERKEZ: tum sistemin tek izleme ekrani (Windows Terminal).
# Liderler (Claude/Codex oturumlari), takim kosulari ve iscileri, onaylar, pano, aktarimlar, kaynak, maliyet ve bugun.
# KULLANICI VERISI YAZMAZ (yalniz kendi onbellek/durum dosyalari); yalniz okur. Enter ayrinti/panel acar, c secili satirin guvenli komutunu PANOYA kopyalar (calistirmaz).
# Veri: merkez-veri.ps1 (durum kurali tek yerde). Balon/ayrinti: merkez-balon.ps1. Cizim katmani + palet: beyin-ciz.ps1.
# Sekmeler: 1 Genel · 2 Ajanlar · 3 Kosular · 4 Olaylar (Tab / Shift+Tab). Tuslar: ↑↓ j k sec, Enter ayrinti, Esc kapat,
# c kopyala, p kosu panosu, a bostakiler, PgUp/PgDn olay kaydir, r tazele, q cik.
# Gorsel dil (1.5.0): Aurora paleti (anlam rolleri beyin-ciz'de), tek dis cerceve, ├─ BOLUM ─┤ ayraclari, rozetler, kartlar.
# Emoji YALNIZ bolum/kart basliginda; satir ici durum tek hucreli renkli simge. Hareket yalniz anlam tasidiginda: calisan
# ajan doner/tarar, hata nabiz atar, cubuk yeni degere yumusakca dolar, yeni olay 2.5 sn parlar; bostaki hicbir sey kipirdamaz.
if (-not $Vault) { $Vault = $(if ($env:BEYIN_VAULT) { $env:BEYIN_VAULT } else { Split-Path (Split-Path $PSScriptRoot -Parent) -Parent }) }
. (Join-Path $Vault 'motor\hooks\lib.ps1')
$cizYol = Join-Path $PSScriptRoot 'beyin-ciz.ps1'
if (-not (Test-Path -LiteralPath $cizYol)) { Write-Host 'beyin merkez: beyin-ciz.ps1 bulunamadi (motor eksik kurulmus) · beyin guncelle'; exit 2 }
. $cizYol
$CizGerekli = 3
if ($BeyinCizSurum -lt $CizGerekli) { Write-Host 'beyin merkez: beyin-ciz.ps1 eski; yayin yarim kalmis olabilir · birkac saniye sonra yeniden ac'; exit 2 }
. (Join-Path $PSScriptRoot 'merkez-veri.ps1')
$balonYol = Join-Path $PSScriptRoot 'merkez-balon.ps1'; if (Test-Path -LiteralPath $balonYol) { . $balonYol }
$p = Get-BeyinPaths -Vault $Vault
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }
if (-not $Tek -and $Olcum -le 0) { try { [Console]::CursorVisible = $false } catch { } }

# ---------- zemin ----------
$zKip = $Zemin
if (-not $zKip) { $zKip = $(if ($Tek -or $Olcum -gt 0) { 'kapali' } else { try { [string](Get-BeyinAyar 'BEYIN_MERKEZ_ZEMIN' 'osc') } catch { 'osc' } }) }
if ($zKip -eq 'osc' -and ($Tek -or -not $env:WT_SESSION)) { $zKip = $(if ($Tek) { 'kapali' } else { 'boya' }) }   # OSC 11 yalniz Windows Terminal'de; -Tek ciktisina kacis dizisi girmez
Set-CizZemin $(if ($zKip -eq 'boya') { 'boya' } else { 'kapali' })

# ---------- anlam tablolari ----------
# DURUM rolu: dort nokta (calisiyor, insan/karar bekliyor, engelli, bosta); digerleri sozcukle
$durumRenk = @{ calisiyor = $cOk; inceleme = $cWarn; engelli = $cErr; duraklatildi = $cMauve; bosta = $cFaint; bitti = $cFaint; bekliyor = $cInfo; kapali = $cFrame2 }
$durumAd = @{ calisiyor = 'çalışıyor'; inceleme = 'incelemede'; engelli = 'engelli'; duraklatildi = 'kota'; bosta = 'boşta'; bitti = 'bitti'; bekliyor = 'sırada'; kapali = 'kapandı' }
$durumSira = @{ engelli = 0; inceleme = 1; calisiyor = 2; duraklatildi = 3; bekliyor = 4; bitti = 5; bosta = 6; kapali = 7 }
$kimlikRenk = @{ claude = $cPeach; codex = $cTeal }
$panoAd = @{ todo = 'bekliyor'; in_progress = 'sürüyor'; review = 'incelemede'; blocked = 'engelli' }
$sekmeler = @('Genel', 'Ajanlar', 'Kosular', 'Olaylar')
$sekmeAd = @{ Genel = 'Genel'; Ajanlar = 'Ajanlar'; Kosular = 'Koşular'; Olaylar = 'Olaylar' }
function Fmt([double]$n) { if ($n -ge 1e9) { return ('{0:0.0} milyar' -f ($n / 1e9)) }; if ($n -ge 1e6) { return ('{0:0.0}M' -f ($n / 1e6)) }; if ($n -ge 1e3) { return ('{0:0.0}K' -f ($n / 1e3)) }; return "$([int64]$n)" }
function EsikBar([double]$oran, [int]$gen) { $r = $(if ($oran -ge 0.9) { $cErr } elseif ($oran -ge 0.7) { $cWarn } else { $cOk }); return (Bar $oran $gen $r) }
function Usd([double]$v) { if ($v -ge 100) { return ('${0:0}' -f $v) }; return ('${0:0.00}' -f $v) }

# ---------- durum ----------
$script:onb = @{}; $script:anlik = $null; $script:sonHizli = [datetime]::MinValue; $script:sonTam = [datetime]::MinValue
$script:sekmeAktif = $(if ($Sekme -eq 'Hepsi') { 'Genel' } else { $Sekme })
$script:secAnahtar = @{}; $script:sec = -1; $script:secilebilir = New-Object System.Collections.Generic.List[object]
$script:hepsi = @{ Genel = $false; Ajanlar = $true; Kosular = $false; Olaylar = $false }
$script:acik = ''; $script:acikAktarim = ''; $script:olayKaydir = 0; $script:yeniOlay = 0
$script:mesaj = ''; $script:mesajRenk = $cWarn; $script:mesajZaman = [datetime]::MinValue
$script:lastFrame = ''; $script:cizimHata = 0; $script:cizimMesaj = ''; $script:sonCizim = Get-Date
$script:olayGoruldu = $null; $script:flas = @{}; $script:tween = @{}; $script:tohumlandi = $false
$script:sesKip = $(try { [string](Get-BeyinAyar 'BEYIN_MERKEZ_SES' 'kapali') } catch { 'kapali' })
$script:sessizSaat = $(try { [string](Get-BeyinAyar 'BEYIN_MERKEZ_SESSIZ' 'yok') } catch { 'yok' })
$script:bildirimAcik = $(try { [string](Get-BeyinAyar 'BEYIN_BILDIRIM' (Get-BeyinAyarVars 'BEYIN_BILDIRIM')) -ne 'kapali' } catch { $true })
$script:gecmis = @{ Cal = New-Object System.Collections.Generic.List[double]; Commit = New-Object System.Collections.Generic.List[double] }
$script:etkinlik = @{}; $script:hataBas = $null; $script:onayBas = $null; $script:veriSurum = 0; $script:bolumOnb = @{}; $script:CizCanli = $false

function Mesaj([string]$m, [string]$renk = $cWarn) { $script:mesaj = $m; $script:mesajRenk = $renk; $script:mesajZaman = Get-Date }
function SessizMi([datetime]$t) {
    # SS-SS (gece yarisini asabilir: 23-08) araliginda ses yok; kural ortak katmanda (kosu panosu da kullanir)
    return (Test-CizSessizSaat $script:sessizSaat $t)
}
function SesCal([string]$tur) {
    # Istege bagli ses (BEYIN_MERKEZ_SES): uc ayri kisa ton - hata inen, onay cikan, kosu bitti uclu arpej. toast kipinde Windows
    # bildirim sesi (Bildir). Sessiz saatte ve -Tek/-Olcum'da hic ses yok.
    if ($script:sesKip -ne 'ton' -or $Tek -or $Olcum -gt 0 -or (SessizMi (Get-Date))) { return }
    # uyari: tek yumusak nota (uyariyla biten kosu); bos tur (iptal edilen kosu) ses vermez
    if (-not $tur) { return }
    $notalar = switch ($tur) { 'hata' { @(@(880, 140), @(587, 220)) } 'onay' { @(@(659, 110), @(988, 160)) } 'uyari' { @(, @(587, 160)) } default { @(@(523, 90), @(659, 90), @(784, 140)) } }
    try { foreach ($n in $notalar) { [Console]::Beep($n[0], $n[1]) } } catch { }
}
function Bildir([string]$baslik, [string]$metin, [string]$tur = '') {
    if (-not $script:bildirimAcik -or $Tek -or $Olcum -gt 0) { return }
    try {
        [void][Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
        [void][Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime]
        $x = New-Object Windows.Data.Xml.Dom.XmlDocument
        # ses yalniz toast kipinde ve sessiz saat disinda (Windows'un varsayilan bildirim sesi eskiden her bildirimde caliyordu)
        $sesli = ($script:sesKip -eq 'toast' -and -not (SessizMi (Get-Date)))
        $ses = $(if (-not $sesli -or -not $tur) { "<audio silent='true'/>" } else { "<audio src='ms-winsoundevent:Notification.$(switch ($tur) { 'hata' { 'Reminder' } 'onay' { 'IM' } 'uyari' { 'Default' } default { 'Mail' } })'/>" })
        $x.LoadXml("<toast><visual><binding template='ToastGeneric'><text>$([Security.SecurityElement]::Escape($baslik))</text><text>$([Security.SecurityElement]::Escape($metin))</text></binding></visual>$ses</toast>")
        $app = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'
        [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($app).Show([Windows.UI.Notifications.ToastNotification]::new($x))
    } catch { }
}
function OlaylariBildir($a) {
    # Yalniz SONRADAN olusan onay ve hata olaylari; kalkan olay yeniden kurulur. Isci bitti bildirimini koşu panosu verir.
    $o = [ordered]@{}
    foreach ($g in $a.Onaylar) { $o["onay:$($g.Satir)"] = "onay bekliyor: $($g.Satir)" }
    foreach ($t in $a.Teshis) { if ($t.Seviye -eq 'err') { $o["hata:$(TeshisAnahtar $t)"] = [string]$t.Metin } }
    $kosuTon = @{}
    foreach ($k in $a.Kosular) { if ($k.Bitmis) { $o["kosu:$($k.RunId)"] = "koşu bitti: $($k.RunId) · $(KosuRozetMetin ([string]$k.Rozet))"; $kosuTon["kosu:$($k.RunId)"] = KosuSonucTon ([string]$k.Rozet) } }
    $simdi = Get-Date
    if ($null -eq $script:olayGoruldu) { $script:olayGoruldu = @{}; foreach ($k in $o.Keys) { $script:olayGoruldu[$k] = $true; $script:olaySon[$k] = $simdi }; return }
    foreach ($k in @($script:olayGoruldu.Keys)) { if (-not $o.Contains($k)) { $script:olayGoruldu.Remove($k) } }
    $yeni = @($o.Keys | Where-Object { -not $script:olayGoruldu.ContainsKey($_) })
    if (-not $yeni.Count) { return }
    foreach ($k in $yeni) { $script:olayGoruldu[$k] = $true }
    # Soguma: esikte gidip gelen alarm (bellek %84/%85, kaynak olcumu bir gelip bir gitmesi) 30 dk icinde yeniden calmaz
    $yeni = @($yeni | Where-Object { -not $script:olaySon.ContainsKey($_) -or ($simdi - $script:olaySon[$_]).TotalMinutes -ge 30 })
    foreach ($k in $yeni) { $script:olaySon[$k] = $simdi }
    if ($script:olaySon.Count -gt 500) { foreach ($k in @($script:olaySon.Keys)) { if (($simdi - $script:olaySon[$k]).TotalHours -ge 2) { $script:olaySon.Remove($k) } } }
    if (-not $yeni.Count) { return }
    $tur = OlayTonu $yeni $kosuTon
    if ($tur) { SesCal $tur }
    Bildir 'Beyin merkez' (Protect-MerkezSatir ((@($yeni | ForEach-Object { $o[$_] }) -join ' · ')) 220) $tur
}
$script:olaySon = @{}; $script:oncekiCanli = $true; $script:flasOlayRef = $null; $script:sonGc = [datetime]::Now
function KosuSonucTon([string]$rozet) {
    # biten kosunun sonucu tonu belirler: basarisiz -> hata, uyariyla -> yumusak uyari, iptal/sahipsiz -> sessiz, basarili -> kosu bitti
    if ($rozet -in @('basarisiz', 'kontrol', 'cakisma', 'dogrulanamadi')) { return 'hata' }
    if ($rozet -in @('uyarili', 'kota')) { return 'uyari' }
    if ($rozet -in @('iptal', 'sahipsiz')) { return '' }
    return 'kosu'
}
function OlayTonu([object[]]$yeni, $kosuTon) {
    # en agir yeni olayin tonu bir kez: hata > onay > uyari > kosu bitti; yalniz sessiz olaylar -> ''
    $kt = @($yeni | Where-Object { $_ -like 'kosu:*' } | ForEach-Object { [string]$kosuTon[$_] })
    if (@($yeni | Where-Object { $_ -like 'hata:*' }).Count -or $kt -contains 'hata') { return 'hata' }
    if (@($yeni | Where-Object { $_ -like 'onay:*' }).Count) { return 'onay' }
    if ($kt -contains 'uyari') { return 'uyari' }
    if ($kt -contains 'kosu') { return 'kosu' }
    return ''
}
function TeshisAnahtar($t) { return $(if ($t.Anahtar) { [string]$t.Anahtar } else { ([string]$t.Metin) -replace '\d', '#' }) }
function AjanAnahtar($ag) { return "$($ag.Tur):$($ag.Kosu):$($ag.Ad)" }
function OlayAnahtar($ol) { return "olay:$($ol.Zaman.Ticks)|$($ol.Tur)|$($ol.Anahtar)" }
function KisaId($ag) {
    # Codex oturum kimligi UUIDv7: ilk haneler zaman damgasi, ayni saatte acilan oturumlarda cakisir -> son 4 hane.
    $id = [string]$ag.Ad; if (-not $id) { return '' }
    $id = $(if ($ag.Ajan -eq 'codex') { $id.Substring([Math]::Max(0, $id.Length - 4)) } else { $id.Substring(0, [Math]::Min(4, $id.Length)) })
    return (Protect-MerkezSatir $id 4)
}

function FlasGuncelle($a) {
    # Parlama imzalari: ilk okuma TOHUMLAR (hicbir sey parlamaz); sonra degisen ya da yeni gorunen satir 2.5 sn parlar.
    $s = Get-Date; $y = $script:tohumlandi
    [object[]]$olaylar = @(); if ($a.Olaylar) { $olaylar = $a.Olaylar.ToArray() }   # $(...) tek ogeyi acip hashtable yapiyordu
    if (-not $script:ilkYukleme) { $script:ilkYukleme = $s }
    $olayAyni = ($a.Olaylar -and [object]::ReferenceEquals($a.Olaylar, $script:flasOlayRef)); $script:flasOlayRef = $a.Olaylar   # liste degismediyse yeni olay yok
    if (-not $olayAyni) { foreach ($ol in $olaylar) { if (Set-CizFlas $script:flas (OlayAnahtar $ol) "$($ol.Adet)" $s ($y -and $ol.Zaman -ge $script:ilkYukleme.AddMinutes(-1))) { if ($script:sekmeAktif -ne 'Olaylar' -and [string]$ol.Renk -ne 'muted') { $script:yeniOlay++ } } } }   # rutin olay (ozet yazildi, gomme) sayaca girmez
    foreach ($ag in $a.Ajanlar) { [void](Set-CizFlas $script:flas "ajan:$(AjanAnahtar $ag)" ([string]$ag.Durum) $s $y) }
    foreach ($g in $a.Onaylar) { [void](Set-CizFlas $script:flas "onay:$($g.Satir)" '1' $s $y) }
    foreach ($t in $a.Teshis) { [void](Set-CizFlas $script:flas "teshis:$(TeshisAnahtar $t)" ([string]$t.Seviye) $s $y) }
    foreach ($k in $a.Kosular) { [void](Set-CizFlas $script:flas "kosu:$($k.RunId)" "$($k.Guncel)|$($k.Rozet)" $s $y) }
    $script:tohumlandi = $true
    if ($script:flas.Count -gt 3000) { foreach ($k in @($script:flas.Keys)) { if ($script:flas[$k].Zaman -lt $s.AddHours(-2)) { $script:flas.Remove($k) } } }
}

function Tazele([bool]$tam) {
    $ay = $(if ($script:acik -match '^(lider|isci):') { $script:acik } else { '' })
    $script:anlik = Get-MerkezAnlik -Paths $p -Onbellek $script:onb -Hizli:(-not $tam) -AyrintiAnahtar $ay
    $script:sonHizli = Get-Date; if ($tam) { $script:sonTam = Get-Date }; $script:veriSurum++
    if ($tam) {
        # panel acik kaldikca biriken egilim (6 sn'de bir nokta, en cok 60 = 6 dk)
        try {
            $script:gecmis.Cal.Add([double]@($script:anlik.Ajanlar | Where-Object { $_.Durum -eq 'calisiyor' }).Count)
            if ($script:anlik.Kaynak -and $script:anlik.Kaynak.Ok) { $script:gecmis.Commit.Add([double]$script:anlik.Kaynak.CommitYuzde) }
            foreach ($k in @('Cal', 'Commit')) { while ($script:gecmis[$k].Count -gt 60) { $script:gecmis[$k].RemoveAt(0) } }
        } catch { }
    }
    try { EtkinlikGuncelle $script:anlik } catch { }
    try { FlasGuncelle $script:anlik } catch { }
    try { OlaylariBildir $script:anlik } catch { }
}
function EtkinlikGuncelle($a) {
    # Ajanin son olay zamani (simdi - nabiz) bir oncekinden ilerlediyse o an bir etkinlik sayilir. 3 dk'dan eskisi atilir.
    $s = Get-Date; $gor = @{}
    foreach ($ag in $a.Ajanlar) {
        $k = AjanAnahtar $ag; $gor[$k] = $true; $ns = [double]$ag.NabizSn; if ($ns -lt 0) { continue }
        $olay = $s.AddSeconds(-$ns); $h = $script:etkinlik[$k]
        if (-not $h) { $script:etkinlik[$k] = @{ Son = $olay; Liste = (New-Object System.Collections.Generic.List[datetime]) }; continue }
        if (($olay - $h.Son).TotalSeconds -gt 1) { $h.Liste.Add($olay); $h.Son = $olay }
        while ($h.Liste.Count -and ($s - $h.Liste[0]).TotalSeconds -gt 180) { $h.Liste.RemoveAt(0) }
    }
    foreach ($k in @($script:etkinlik.Keys)) { if (-not $gor.ContainsKey($k)) { $script:etkinlik.Remove($k) } }
}
function EtkinlikSerit($ag, [int]$n = 6, [int]$kovaSn = 20) {
    # son n*kovaSn saniyenin etkinligi: kova basina olay sayisi, kimlik renginden yesile; en yeni hucre taze olayda nabiz atar
    $h = $script:etkinlik[(AjanAnahtar $ag)]; $s = Get-Date; $say = New-Object double[] $n
    if ($h) { foreach ($t in $h.Liste) { $i = $n - 1 - [int][Math]::Floor(($s - $t).TotalSeconds / $kovaSn); if ($i -ge 0 -and $i -lt $n) { $say[$i]++ } } }
    $kim = $(if ($ag.Ajan -eq 'codex') { $rgbTeal } else { $CizRgb.Claude })
    $ns = [double]$ag.NabizSn
    if ($ns -lt 0 -or $ns -gt 60) { return "$cIz$('·' * $n)$RS" }   # sessiz: donuk taban
    $sp = (Spark $say $n $kim $rgbOk 3).Replace('▁', '·')   # bos kova nokta
    if ($ns -le 3) { $sp = (Spark ($say[0..($n - 2)]) ($n - 1) $kim $rgbOk 3).Replace('▁', '·') + "$ESC[77m$BOLD▆$RS" }   # yeni olay: son hucre atar (SGR 77 yer tutucu: her karede nabiz rengi)
    return $sp
}

# ---------- secim ve vurgu ----------
function SecKayit([string]$Tur, [string]$Anahtar, $Nesne, [bool]$Yetim = $false) {
    # Cizim sirasinda secilebilir satiri kaydeder; secili ise $true doner (satir vurgulu cizilir).
    $ham = $Anahtar; $n = [int]$script:secSayac[$Anahtar]; $script:secSayac[$Anahtar] = $n + 1; if ($n) { $Anahtar = "$Anahtar#$n" }
    $script:secilebilir.Add(@{ Tur = $Tur; Anahtar = $Anahtar; Ham = $ham; Nesne = $Nesne; Yetim = $Yetim })
    return ($Anahtar -eq [string]$script:secAnahtar[$script:sekmeAktif])
}
function Zeminle([string]$icerik, [int]$gen, [string]$bg) { return "$bg" + ((Pad $icerik $gen) -replace [regex]::Escape($RS), "$RS$bg") + $RS }
function Vurgu([string]$icerik, [int]$gen, [bool]$secili, [string]$flasAnahtar = '') {
    # secim (kalici zemin) once; secili degilse parlama (sonen zemin)
    if ($secili) { return (Zeminle $icerik $gen $bgSel) }
    if ($flasAnahtar) { $o = Get-CizFlasOran $script:flas $flasAnahtar (Get-Date); if ($o -gt 0) { return (Zeminle $icerik $gen (BgKaris $rgbZemin $rgbInfo (0.34 * $o))) } }
    return $icerik
}

# ---------- satir cizerleri ----------
$script:ajanSatirOnb = @{}
function AjanSatir($ag, [int]$gen, [bool]$secili, [bool]$idGoster, [int]$ekGen = 19) {
    # Satir saniyede bir (ya da ajan durumu/secim degisince) kurulur; her karede yalniz doner simge ve nabiz rengi yerlestirilir.
    # Parlama suruyorsa onbellek atlanir (zemin her karede soner).
    $an = AjanAnahtar $ag; $et = $script:etkinlik[$an]
    $k = "$an|$gen|$secili|$idGoster|$ekGen|$($ag.Durum)|$($ag.Kaynak)|$($ag.Bayat)|$([int]$ag.NabizSn)|$($ag.Prompt)|$($ag.Balon)|$($ag.Jeton)|$($ag.Dosya)|$(if ($et) { "$($et.Liste.Count)|$($et.Son.Ticks)" })|$([int64][Math]::Floor((Get-Date).Ticks / 10000000))"
    $flasVar = (Get-CizFlasOran $script:flas "ajan:$an" (Get-Date)) -gt 0
    $e = $script:ajanSatirOnb[$an]
    if ($flasVar -or -not $e -or $e.K -ne $k) { $v = AjanSatirHam $ag $gen $secili $idGoster $ekGen; if (-not $flasVar) { $script:ajanSatirOnb[$an] = @{ K = $k; V = $v } } } else { $v = $e.V }
    if ($script:ajanSatirOnb.Count -gt 400) { $script:ajanSatirOnb.Clear() }
    if ($v.IndexOf([char]0xE000) -ge 0 -or $v.IndexOf([char]0xE001) -ge 0) { $script:CizCanli = $true; $v = $v.Replace([string][char]0xE000, $spin[$script:tik % $spin.Count]).Replace([string][char]0xE001, $spin[[int][Math]::Floor($script:tik / 4) % $spin.Count]) }
    if ($v.IndexOf("$ESC[77m") -ge 0) { $v = $v.Replace("$ESC[77m", (Nabiz $rgbOk 0.9)) }
    return $v
}
function AjanSatirHam($ag, [int]$gen, [bool]$secili, [bool]$idGoster, [int]$ekGen = 19) {
    $d = [string]$ag.Durum; $renk = $durumRenk[$d]; if (-not $renk) { $renk = $cFaint }
    $kr = $kimlikRenk[[string]$ag.Ajan]; if (-not $kr) { $kr = $cMuted }
    $isaret = $(if ($secili) { "$cAccent$BOLD▸$RS" } else { ' ' })
    $uzun = ($d -eq 'calisiyor' -and $ag.Kaynak -eq 'uzun-arac')
    $nokta = $(switch ($d) {
            'calisiyor' { $script:CizCanli = $true; $(if ($uzun) { "$cWarn$([char]0xE001)$RS" } else { "$renk$([char]0xE000)$RS" }) }   # yer tutucu: AjanSatir her karede doner simgeyle degistirir
            'inceleme' { "$renk◐$RS" } 'engelli' { "$renk✕$RS" } 'duraklatildi' { "$renk‖$RS" } 'bitti' { "$renk✓$RS" } 'bekliyor' { "$renk◌$RS" } default { "$renk○$RS" } })
    if ($ag.Tur -eq 'lider') {
        $ad = "$kr$BOLD$(Protect-MerkezSatir ([string]$ag.Rol) 12)$RS" + $(if ($idGoster) { " $cFaint$(KisaId $ag)$RS" } else { '' })
        $rol = $(if ($ag.Prompt) { "$cFaint$($ag.Prompt) mesaj$RS" } else { "${cFaint}yeni oturum$RS" })
        $yasSn = $ag.NabizSn
    } else {
        $ad = "$cFaint↳$RS $cText$BOLD$(Protect-MerkezSatir ([string]$ag.Ad) 16)$RS"
        $rol = "$cMuted$(Protect-MerkezSatir (RolTr $ag.Rol) 24)$RS"
        $yasSn = $(if ($ag.Basladi) { $bitis = $(if ($ag.Bitti) { $ag.Bitti } else { Get-Date }); ($bitis - $ag.Basladi).TotalSeconds } else { -1 })
    }
    $tarS = EtkinlikSerit $ag 6 20   # son 2 dk: kim gercekten is yapiyor (ozdes tarama cubugu yerine)
    $durumYazi = $(if ($uzun) { "$cWarn◷ uzun işlem$RS" }   # 2+ dk tek arac: uzun komut ya da izin istemi
        elseif ($d -eq 'calisiyor') { "$renk$($durumAd[$d])$RS $tarS" } else { "$renk$($durumAd[$d])$RS" })
    $yasRenk = $(if ($ag.Bayat -or $uzun) { $cWarn } else { $cMuted })
    if (-not $ag.Bayat -and -not $uzun -and $d -eq 'calisiyor') { $yasRenk = $(if ($yasSn -ge 0 -and $yasSn -le 10) { $cOk } elseif ($yasSn -le 60) { $cText } else { $cMuted }) }   # taze nabiz yesil
    $yas = "$yasRenk$(if ($yasSn -ge 3600) { KisaYas $yasSn } else { Kisa $yasSn })$(if ($ag.Bayat) { ' !' })$RS"
    $ek = @(); if ($ag.Jeton) { $ek += "$(Fmt $ag.Jeton) jt" }; if ($ag.Dosya) { $ek += "$($ag.Dosya) dosya" }
    $ekS = $(if ($ek.Count) { "$cFaint$($ek -join ' · ')$RS" } else { '' })
    # dar satirda "N mesaj" sutunu gizlenir: yer en bilgilendirici kisma, balona kalir
    $sol = "$isaret $nokta $(Pad $ad 18) $(if ($gen -ge 110) { (Pad $rol 15) + ' ' })$(Pad $durumYazi 16) "
    $sag = "  $(PadL $yas 9)$(if ($ekGen -gt 0) { ' ' + (PadL $ekS $ekGen) }) "
    $balonGen = $gen - (VisLen $sol) - (VisLen $sag)
    # Balon: calisan ajanda canli (soluk degil), digerlerinde "son yaptigi" olarak soluk; bostaki ajanin yarim kalmis
    # "düşünüyor" kaydi su an dusunuyormus gibi okunuyordu, gosterilmez.
    $bm = (Get-CizGuvenliMetin ([string]$ag.Balon)) -replace '\*\*|__', '' -replace '\s*\|\s*', ' · ' -replace '\s{2,}', ' '; if ($d -ne 'calisiyor' -and $bm -match '^… düşünüyor') { $bm = '' }
    $bm = $bm -replace '(?i)(/c/Users/|[A-Z]:[\\/]Users[\\/])[^/\\\s]+', '~'   # ev dizini ~
    if (-not $bm -and $ag.Tur -eq 'lider' -and $d -eq 'calisiyor') { $bm = $(if ($ag.Transkript) { '◌ henüz araç adımı yok · ilk yanıt bekleniyor' } elseif ($ag.Transkript -eq $false) { '◌ etkinlik kaydı okunamıyor (transkript bu makinede yok)' } else { '◌ etkinlik okunuyor…' }) }
    $balon = $(if ($bm -and $balonGen -gt 6) { "$(if ($d -eq 'calisiyor') { $cText } else { $cFaint })$(if ($bm.StartsWith('▸')) { CutMid $bm $balonGen } else { Cut $bm $balonGen })$RS" } else { '' })
    $satir = $sol + (Pad $balon ([Math]::Max(0, $balonGen))) + $sag
    return (Vurgu $satir $gen $secili "ajan:$(AjanAnahtar $ag)")
}

function AyrintiSatirlari($ag, [int]$gen) {
    # Acik ajanin ayrintisi: durum/kaynak, oturum suresi ve bekleme, model + baglam cubugu, maliyet, son 5 adim, komut.
    $L = New-Object System.Collections.Generic.List[string]
    $ay = $script:anlik.Ayrinti; $simdi = Get-Date
    $kr = $kimlikRenk[[string]$ag.Ajan]; if (-not $kr) { $kr = $cMuted }
    $d = [string]$ag.Durum
    $L.Add("$kr$BOLD$(Protect-MerkezSatir ([string]$ag.Rol) 12)$RS $cFaint$(KisaId $ag)$RS$cFrame · $RS$cTitle$(Protect-MerkezSatir ([string]$ag.Kanat) 30)$RS$cFrame · $RS$($durumRenk[$d])$($durumAd[$d])$RS$cFaint · kaynak $($ag.Kaynak)$RS")
    $oturum = @()
    if ($ag.Basladi) { $oturum += "${cMuted}başladı$RS $cText$(Kisa ($simdi - $ag.Basladi).TotalSeconds) önce$RS$cFaint ($(if ($ag.Basladi.Date -eq $simdi.Date) { $ag.Basladi.ToString('HH:mm') } else { $ag.Basladi.ToString('d MMM HH:mm', [Globalization.CultureInfo]::GetCultureInfo('tr-TR')) }))$RS" }
    if ($ay -and $ay.SonIstem) { $oturum += "${cMuted}son istem$RS $cText$(([datetime]$ay.SonIstem).ToString('HH:mm'))$RS" }
    if ($ag.Tur -eq 'lider' -and $ay -and $ay.SonBitis -and ($d -in @('bosta', 'bitti')) -and (-not $ay.SonIstem -or [datetime]$ay.SonBitis -ge [datetime]$ay.SonIstem)) { $oturum += "${cWarn}sıranı bekliyor$RS $cText$(Kisa ($simdi - [datetime]$ay.SonBitis).TotalSeconds)$RS" }
    elseif ($ag.Kaynak -eq 'uzun-arac') { $oturum += "${cWarn}tek araçta$RS $cText$(Kisa ([double]$ag.NabizSn))$RS$cFaint · izin istemi olabilir$RS" }
    if ($oturum.Count) { $L.Add($oturum -join "$cFrame  ·  $RS") }
    if ($ay -and ($ay.Model -or $ay.Baglam)) {
        $bg = [double]$ay.Baglam; $tavan = $(if ($bg -gt 200000) { 1000000 } else { 200000 })
        $L.Add("$(if ($ay.Model) { "${cMuted}model$RS $cText$(Protect-MerkezSatir ([string]$ay.Model) 28)$RS   " })$(if ($bg -gt 0) { "${cMuted}bağlam$RS $(EsikBar ($bg / $tavan) 10) $cText$(Fmt $bg)$RS$cFaint / $(Fmt $tavan)$RS" })$(if ($ay.Toplam) { "$cFaint   toplam $(Fmt ([double]$ay.Toplam)) jeton$RS" })")
    }
    if ($ay -and $null -ne $ay.MaliyetUsd) { $L.Add("${cMuted}bugün$RS $cPeach$BOLD$(Usd ([double]$ay.MaliyetUsd))$RS$cFaint API eşdeğeri$(if ($ay.MaliyetZaman) { ' · ' + ([datetime]$ay.MaliyetZaman).ToString('HH:mm') + ' itibarıyla' })$RS") }
    $adim = $(if ($ay) { @($ay.Adimlar) } else { @() })
    if ($adim.Count) {
        $L.Add("${cFaint}son adımlar$RS")
        foreach ($s in $adim) {
            $z = $(if ($s.Zaman) { ([datetime]$s.Zaman).ToString('HH:mm:ss') } else { '        ' })
            $m = (Get-CizGuvenliMetin ([string]$s.Metin)) -replace '(?i)(/c/Users/|[A-Z]:[\\/]Users[\\/])[^/\\\s]+', '~'
            $L.Add("  $cFaint$z$RS  $cText$(Cut $m ($gen - 14))$RS")
        }
    } elseif (-not $ay) { $L.Add("${cFaint}ayrıntı okunuyor…$RS") }
    $L.Add("${cMuted}dizin$RS $cFaint$(CutLeft (Protect-MerkezSatir ([string]$ag.Cwd) 200) ($gen - 8))$RS")
    $k = Get-MerkezSatirKomut @{ Tur = [string]$ag.Tur; Nesne = $ag }
    if ($k) { $L.Add("$cAccent${BOLD}c$RS ${cFaint}kopyala$RS  $cAccent$(Cut $k.Komut ($gen - 14))$RS") }
    return $L
}

function KanatSatirlari([string]$kanat, $ajanlar, [int]$ic, [bool]$hepsi, [bool]$satirIci) {
    # Bir kanat: alt baslik + ajan satirlari (+ satir ici ayrinti) + toplanmis sakinler. Satir icerigi $ic genisliginde.
    $L = New-Object System.Collections.Generic.List[string]
    $aktif = @($ajanlar | Where-Object { $_.Durum -notin @('bosta', 'kapali', 'bitti') })
    $sakin = @($ajanlar | Where-Object { $_.Durum -in @('bosta', 'kapali', 'bitti') })
    $nEng = @($aktif | Where-Object { $_.Durum -eq 'engelli' }).Count
    $ozet = @(); if ($aktif.Count - $nEng) { $ozet += "$cOk$($aktif.Count - $nEng) aktif$RS" }; if ($nEng) { $ozet += "$cErr$nEng engelli$RS" }; if ($sakin.Count) { $ozet += "$cFaint$($sakin.Count) boşta$RS" }
    $isc = @($ajanlar | Where-Object { $_.Tur -eq 'isci' }).Count
    $gosterilen = @($(if ($hepsi -or -not $aktif.Count) { @($aktif) + @($sakin) } else { $aktif }))
    $acikBurada = ($satirIci -and $script:acik -and @($gosterilen | Where-Object { (AjanAnahtar $_) -eq $script:acik }).Count)
    $tekSatir = ($gosterilen.Count -eq 1 -and -not $isc -and -not $acikBurada -and -not (-not $hepsi -and $aktif.Count -and $sakin.Count))
    if ($tekSatir) {
        $kw = [Math]::Min(18, [Math]::Max(15, [int][Math]::Floor($ic / 7)))
        $ag = $gosterilen[0]; $sc = SecKayit ([string]$ag.Tur) (AjanAnahtar $ag) $ag
        $bas = "$cTitle$BOLD▣ $(Pad (Protect-MerkezSatir $kanat 40) ($kw - 2))$RS"
        $L.Add($bas + (AjanSatir $ag ($ic - $kw) $sc $false $(if ($ag.Jeton -or $ag.Dosya) { 19 } else { 0 })))
        $L.Add('__TEK__'); return $L   # isaret: bu blogun ardina bos satir eklenmez
    }
    $L.Add("$cTitle$BOLD▣ $(Protect-MerkezSatir $kanat 40)$RS$cFaint  ·  $RS$($ozet -join "$cFaint · $RS")$(if ($isc) { "$cFaint  ·  $RS$cTeal$isc işçi$RS" })")
    $rolSay = @{}; foreach ($ag in $ajanlar) { if ($ag.Tur -eq 'lider') { $rolSay[$ag.Rol] = 1 + [int]$rolSay[$ag.Rol] } }
    $ekGen = $(if (@($gosterilen | Where-Object { $_.Jeton -or $_.Dosya }).Count) { 19 } else { 0 })
    foreach ($ag in $gosterilen) {
        $anahtar = AjanAnahtar $ag
        $sc = SecKayit ([string]$ag.Tur) $anahtar $ag
        $L.Add((AjanSatir $ag $ic $sc ([int]$rolSay[$ag.Rol] -gt 1) $ekGen))
        if ($satirIci -and $script:acik -eq $anahtar) { foreach ($s in (AyrintiSatirlari $ag ($ic - 6))) { $L.Add("    $cAccent│$RS $s") } }
    }
    if (-not $hepsi -and $aktif.Count -and $sakin.Count) {
        $adlar = @($sakin | Select-Object -First 4 | ForEach-Object { $(if ($_.Tur -eq 'lider') { "$(Protect-MerkezSatir ([string]$_.Rol) 12) $(KisaId $_)" } else { Protect-MerkezSatir ([string]$_.Ad) 16 }) })
        $L.Add("  $cFaint○ $($sakin.Count) boşta: $($adlar -join ', ')$(if ($sakin.Count -gt 4) { " +$($sakin.Count - 4)" })$RS")
    }
    return $L
}

function KosuRozet([string]$r) {
    switch ($r) {
        'raporlar'      { return "$bgDone$BOLD ✓ RAPORLAR ALINDI $RS" }
        'iptal'         { return "$bgBad$BOLD ✕ İPTAL $RS" }
        'basarisiz'     { return "$bgBad$BOLD ✕ BAŞARISIZ $RS" }
        'anadalda'      { return "$bgRun$BOLD ✓ ANA DALDA $RS" }
        'sahipsiz'      { return "$bgBad$BOLD ▲ GÖZETMEN DURDU $RS" }
        'calisiyor'     { return "$bgPart$BOLD $($spin[$script:tik % $spin.Count]) ÇALIŞIYOR $RS" }
        'cakisma'       { return "$bgBad$BOLD ✕ ÇAKIŞMA $RS" }
        'kontrol'       { return "$bgBad$BOLD ✕ KONTROL DÜŞTÜ $RS" }
        'dogrulanamadi' { return "$bgBad$BOLD ✕ DOĞRULANAMADI $RS" }
        'uyarili'       { return "$bgPart$BOLD ◐ UYARIYLA DOĞRULANDI $RS" }
        'dogrulandi'    { return "$bgRun$BOLD ✓ DOĞRULANDI $RS" }
        'onay'          { return "$bgWait$BOLD ◐ ONAY BEKLİYOR $RS" }
        'kota'          { return "$bgIdle$BOLD ‖ KOTA SINIRI $RS" }
        default         { return "$bgDone$BOLD ▸ ŞEF SIRASI $RS" }
    }
}
function KosuRozetMetin([string]$r) {
    switch ($r) {
        'raporlar' { 'raporlar alındı' } 'iptal' { 'iptal' } 'basarisiz' { 'başarısız' } 'anadalda' { 'ana dalda' } 'sahipsiz' { 'gözetmen durdu' }
        'calisiyor' { 'çalışıyor' } 'cakisma' { 'çakışma' } 'kontrol' { 'kontrol düştü' } 'dogrulanamadi' { 'doğrulanamadı' }
        'uyarili' { 'uyarıyla doğrulandı' } 'dogrulandi' { 'doğrulandı' } 'onay' { 'onay bekliyor' } 'kota' { 'kota sınırı' } default { 'şef sırası' }
    }
}
function KonuAyrinti([string]$m, [string]$renk) {
    # ilk ':' / '(' / '. ' oncesi konu (parlak), sonrasi ayrinti (soluk): goz yalniz konuyu okur
    $i = $m.IndexOfAny([char[]]@(':', '(')); $j = $m.IndexOf('. '); if ($j -gt 0 -and ($i -lt 0 -or $j -lt $i)) { $i = $j + 1 }
    if ($i -le 0 -or $i -ge $m.Length - 1) { return "$renk$m$RS" }
    return "$renk$($m.Substring(0, $i + 1))$RS$cFaint$($m.Substring($i + 1))$RS"
}

# ---------- bolumler (her biri cerceveli satirlari $L'ye ekler) ----------
function Bolum([System.Collections.Generic.List[string]]$L, $bolumBas, [string]$ad, [string]$etiket, [string]$renk = $cAccent) {
    $bolumBas.Add(@{ Ad = $ad; I = $L.Count }); $L.Add((HLine $script:w (Sec $etiket $renk) '├' '┤'))
}
function SekmeCipleri($a) {
    $parca = @()
    for ($i = 0; $i -lt $sekmeler.Count; $i++) {
        $s = $sekmeler[$i]
        $sayi = switch ($s) { 'Ajanlar' { [int]$a.Sayac['calisiyor'] } 'Kosular' { @($a.Kosular | Where-Object { -not $_.Bitmis }).Count + @($a.ClaudeIsler | Where-Object { $_ -and $_.Durum -eq 'calisiyor' }).Count } 'Olaylar' { [Math]::Min(99, $script:yeniOlay) } default { 0 } }
        $sayiS = $(if ($sayi -gt 0) { "$(if ($s -eq 'Olaylar') { $cInfo } else { $cFaint }) $sayi$RS" } else { '' })   # "Ajanlar 4": sayi soluk, tus numarasi parlak oldugu icin karismaz
        $parca += $(if ($s -eq $script:sekmeAktif) { "$bgSel$cAccent$BOLD $($i + 1) $($sekmeAd[$s])$RS$bgSel$sayiS$bgSel $RS" } else { "$cFaint$($i + 1)$RS $cMuted$($sekmeAd[$s])$RS$sayiS" })
    }
    return ($parca -join '  ')
}

function BolumBaslik($L, $a) {
    $w = $script:w
    $nbz = @($a.Ajanlar | Where-Object { $_.NabizSn -ge 0 } | ForEach-Object { [double]$_.NabizSn })
    $sonOl = $(if ($nbz.Count) { [double]($nbz | Measure-Object -Minimum).Minimum } else { 1e9 })
    $bayatVeri = (-not $a.Ajanlar.Count) -or $sonOl -gt 120
    $sonOlS = $(if ($nbz.Count) { " $cFrame·$RS ${cFaint}son olay$RS $(if ($bayatVeri) { $cWarn } else { $cMuted })$(KisaYas $sonOl)$RS" } else { '' })
    # canli noktasi SABIT: veri tazeyse yesil, bayatsa sari. Eskiden bayatta nabiz atiyordu; bayat = sakin ekran, nabiz onu
    # surekli 120 ms'lik kareye kilitliyordu (bos panel ~%15 cekirdek, performans denetimi 2026-10-17)
    $nokta = $(if ($bayatVeri) { $cWarn } else { $cOk })
    $hataV = @($a.Teshis | Where-Object { $_.Seviye -eq 'err' }).Count; $uyV = @($a.Teshis | Where-Object { $_.Seviye -eq 'warn' }).Count
    $kose = $(if ($hataV) { $cErr } elseif ($a.Onaylar.Count -or $uyV) { $cWarn } else { $cFrame })
    $saat = "$cFrame─ $RS$nokta●$RS ${cFaint}canlı $cMuted$((Get-Date).ToString($(if ($script:oncekiCanli) { 'HH:mm:ss' } else { 'HH:mm' })))$RS$sonOlS$cFrame ─$kose╮$RS"
    $ad = "$cTitle$BOLD◆ Beyin merkez$RS"
    $cip = SekmeCipleri $a
    if ($w -ge 120 -and ((VisLen $ad) + (VisLen $cip) + (VisLen $saat) + 10) -le $w) {
        $L.Add(((HLine ($w - (VisLen $saat)) "$ad$cFrame ─ $RS$cip" '╭' '') -replace "^$([regex]::Escape($cFrame))╭", "$kose╭$cFrame") + $saat)
    } else {
        $L.Add(((HLine ($w - (VisLen $saat)) "$ad$cFrame · $RS${cMuted}tüm sistem$RS" '╭' '') -replace "^$([regex]::Escape($cFrame))╭", "$kose╭$cFrame") + $saat)
        $L.Add((Row $cip $w))
    }
}
function BolumRozet($L, $a) {
    $w = $script:w; $n = { param($k) $(if ($a.Sayac.ContainsKey($k)) { [int]$a.Sayac[$k] } else { 0 }) }
    $hata = @($a.Teshis | Where-Object { $_.Seviye -eq 'err' }).Count; $uyari = @($a.Teshis | Where-Object { $_.Seviye -eq 'warn' }).Count
    # yalniz HATA nabiz atar; uyari ve onay sabit (bekleyen is alarm degil)
    $sm = Get-Date
    # histerezis: hata 2 dk boyunca hic gorulmezse sifirlanir; kisa kesintiden sonra nabiz bastan baslamaz
    if ($hata) { $script:hataSon = $sm; if (-not $script:hataBas) { $script:hataBas = $sm } } elseif (-not $script:hataSon -or ($sm - $script:hataSon).TotalSeconds -ge 120) { $script:hataBas = $null }
    if ($a.Onaylar.Count) { if (-not $script:onayBas) { $script:onayBas = $sm } } else { $script:onayBas = $null }
    $hataAt = $hata -and ($sm - $script:hataBas).TotalSeconds -lt 60; $onayAt = $a.Onaylar.Count -and ($sm - $script:onayBas).TotalSeconds -lt 30
    $rozet = $(if ($hata) { "$(if ($hataAt) { BgKaris (CizKarisRgb $rgbErr $rgbZemin 0.70) (CizKarisRgb $rgbErr $rgbZemin 0.40) ((([Math]::Sin($script:tik * 0.7) + 1) / 2)) } else { CizBG (CizKarisRgb $rgbErr $rgbZemin 0.45) })$cText$BOLD ✕ $hata HATA $RS" }
        elseif ($a.Onaylar.Count) { "$(if ($onayAt) { BgKaris (CizKarisRgb $CizRgb.Baslik $rgbZemin 0.78) (CizKarisRgb $rgbWarn $rgbZemin 0.55) ((([Math]::Sin($script:tik * 0.3) + 1) / 2)) } else { $bgWait })$cText$BOLD ◐ $($a.Onaylar.Count) ONAY BEKLİYOR $RS" } elseif ($uyari) { "$bgIdle$BOLD ▲ $uyari UYARI $RS" } else { "$bgRun$BOLD ● SAĞLIKLI $RS" })
    $sayac = @()
    foreach ($d in @('calisiyor', 'inceleme', 'engelli', 'duraklatildi', 'bekliyor', 'bosta')) { $v = & $n $d; if ($v -gt 0) { $sayac += "$($durumRenk[$d])$BOLD$v$RS $cMuted$($durumAd[$d])$RS" } }
    if (-not $sayac.Count) { $sayac += "$cFaint etkin ajan yok$RS" }
    $etk = [double[]]@($a.Etkinlik); $etkN = [int]($etk | Measure-Object -Sum).Sum   # motor makbuzlari (kanca/komut), ajan mesaji degil
    $etkS = $(if ($etkN) { "${cFaint}motor son 2 sa$RS $(Spark $etk 12 $rgbInfo $rgbAcc) ${cFaint}$etkN olay$RS" } else { "${cFaint}motor son 2 sa sessiz$RS" })
    $solBas = "$rozet   $($sayac -join "$cFrame · $RS")"; $bosluk = ($w - 4) - (VisLen $solBas) - (VisLen $etkS)
    $L.Add((Row $(if ($bosluk -ge 3) { $solBas + (' ' * $bosluk) + $etkS } else { $solBas }) $w))
}
function DunS($dun, [string]$bicim = '') {
    # "dun N": dunun AYNI SAATINE kadarki deger (maliyette tam gun); yoksa bos
    if ($null -eq $dun) { return '' }
    return " ${cFaint}dün $(if ($bicim -eq 'usd') { Usd ([double]$dun) } else { [int]$dun })$RS"
}
function Fark([double]$bugun, $dun, [bool]$azIyi = $false) {
    # dunun AYNI SAATINE gore fark: ↑ / ↓ ve sayi; renk anlam tasir (maliyette azalma iyi)
    if ($null -eq $dun) { return '' }
    $d = [double]$dun; if ($bugun -eq $d) { return "$cFaint =$RS" }
    $yukari = $bugun -gt $d
    $renk = $(if (-not $azIyi) { $cFaint } elseif ($yukari) { $cWarn } else { $cOk })   # etkinlikte yon deger yargisi degil: notr
    return " $renk$(if ($yukari) { '↑' } else { '↓' })$RS"
}
function BolumBugun($L, $a) {
    # Bugun seridi: tek satir; dun ayni saate kadar karsilastirma, maliyet "itibariyla" etiketiyle, saatlik dagilim grafigi
    $w = $script:w; $b = $a.Bugun; if (-not $b) { return }
    $par = @()
    if ($null -ne $b.Usd) {
        $yasSa = $(if ($b.UsdZaman) { ((Get-Date) - [datetime]$b.UsdZaman).TotalHours } else { 0 })
        $bayatS = $(if ($yasSa -gt 6) { "$cWarn $([int]$yasSa) sa önceki tarama$RS" } elseif ($yasSa -gt 2) { "$cFaint $(([datetime]$b.UsdZaman).ToString('HH:mm')) itibarıyla$RS" } else { '' })
        $par += "$cPeach$BOLD$(Usd ([double]$b.Usd))$RS$bayatS$(if ($yasSa -le 2) { DunS $b.UsdDun 'usd' })"   # sabahki kismi rakam dunun tam gunuyle kiyaslanmaz
    }
    $yu = { param($ad, $v) [int][Math]::Round((Get-CizTween $script:tween "bugun:$ad" ([double]$v) 0.3)) }   # sayi degisince yeni degere yuvarlanir
    if ($null -eq $b.Usd) { $par += "${cFaint}$(if ($w -ge 120) { 'bugünkü maliyet henüz hesaplanmadı' } else { 'maliyet bekliyor' })$(if ($null -ne $b.UsdDun) { ' · dün ' + (Usd ([double]$b.UsdDun)) })$RS" }   # yeni gun: tarama sabah/elle (beyin maliyet)
    $par += "$cText$BOLD$(& $yu 'oturum' $b.Oturum)$RS ${cMuted}oturum$RS$(DunS $b.OturumDun)"
    $par += "$cText$BOLD$(& $yu 'ozet' $b.Ozet)$RS ${cMuted}özet$RS$(DunS $b.OzetDun)"
    $par += "$cText$BOLD$(& $yu 'commit' $b.Commit)$RS ${cMuted}commit$RS$(DunS $b.CommitDun)"
    if ([int]$b.Yayin -or [int]$b.YayinDun) { $par += "$cText$BOLD$([int]$b.Yayin)$RS ${cMuted}yayın$RS" }
    if ([int]$b.Hata) { $par += "$cErr$BOLD$([int]$b.Hata)$RS ${cErr}hata$RS" }
    if ([int]$b.Engel) { $par += "$cWarn$BOLD$([int]$b.Engel)$RS ${cWarn}engel$RS" }
    $sl = [double[]]@($(if ($b.Son24) { $b.Son24 } else { $b.Saatlik }))
    $hucre = $(if ($w -ge 170) { 24 } else { 12 }); if ($sl.Count -gt $hucre) { $sl = [double[]]@($sl | Select-Object -Last $hucre) }
    $sagS = "${cFaint}dün: aynı saate kadar · son $hucre sa$RS $(Spark $sl $hucre $rgbInfo $rgbAcc)"
    $sc = SecKayit 'bugun' 'bugun' $b
    $ay = "$cFrame  ·  $RS"; $sol = "$cAccent${BOLD}BUGÜN$RS  $($par -join $ay)"
    $bosluk = ($w - 4) - (VisLen $sol) - (VisLen $sagS)
    if ($bosluk -ge 3) { $L.Add((Row (Vurgu ($sol + (' ' * $bosluk) + $sagS) ($w - 4) $sc) $w)); return }
    if ((VisLen $sol) -le ($w - 4)) { $L.Add((Row (Vurgu $sol ($w - 4) $sc) $w)); return }
    # dar ekran: iki satira bol (kesik "dün…" okunmuyordu)
    $yarim = [int][Math]::Ceiling($par.Count / 2.0)
    $L.Add((Row (Vurgu "$cAccent${BOLD}BUGÜN$RS  $(@($par | Select-Object -First $yarim) -join $ay)" ($w - 4) $sc) $w))
    $L.Add((Row (Vurgu "       $(@($par | Select-Object -Skip $yarim) -join $ay)" ($w - 4) $sc) $w))
}
function EgilimSerit([double[]]$v, [int]$gen) {
    # degisim gostergesi: 3 ornekten azsa toplaniyor; sabitse "sabit N"; degilse en dusuk-en yuksek araligina olcekli
    if ($v.Count -lt 3) { return "${cFaint}$('·' * $gen)$RS" }
    $son = @($v | Select-Object -Last $gen); $mn = ($son | Measure-Object -Minimum).Minimum; $mx = ($son | Measure-Object -Maximum).Maximum
    if ($mn -eq $mx) { return "$cFaint$(Pad "━ sabit $([int]$mx) ━" $gen)$RS" }
    return (Spark ([double[]]@($son | ForEach-Object { $_ - $mn + 1 })) $gen $rgbAcc $rgbOk ($mx - $mn + 1))
}
function BolumKartlar($L, $a) {
    $claudeCalisan = @($a.ClaudeIsler | Where-Object { $_ -and $_.Durum -eq 'calisiyor' }).Count
    $w = $script:w; $ic = $w - 4; $n = { param($k) $(if ($a.Sayac.ContainsKey($k)) { [int]$a.Sayac[$k] } else { 0 }) }
    $calisan = & $n 'calisiyor'; $toplam = $a.Ajanlar.Count
    $lid = @($a.Ajanlar | Where-Object { $_.Tur -eq 'lider' -and $_.Durum -ne 'kapali' }).Count; $isc = @($a.Ajanlar | Where-Object { $_.Tur -eq 'isci' }).Count
    $acikKosu = @($a.Kosular | Where-Object { -not $_.Bitmis }); $kIsci = 0; foreach ($k in $acikKosu) { $kIsci += [int]$(if ($null -ne $k.Calisan) { $k.Calisan } else { 0 }) }
    $etkin = @($a.Ajanlar | Where-Object { $_.Durum -ne 'kapali' })
    $nClaude = @($etkin | Where-Object { $_.Ajan -eq 'claude' }).Count; $nCodex = @($etkin | Where-Object { $_.Ajan -eq 'codex' }).Count
    $sonBiten = @($a.Kosular | Where-Object { $_.Bitmis } | Sort-Object -Property @{ Expression = { $_.KayitGuncel }; Descending = $true } | Select-Object -First 1)
    $oranAjan = Get-CizTween $script:tween 'ajan' $(if ($toplam) { $calisan / [double]$toplam } else { 0 })
    $kartlar = @(
        @{ t = '🤖 AJANLAR'; l = @("$(Bar $oranAjan 12 $cAccent)  $cText$BOLD$calisan$RS$cMuted/$toplam çalışıyor$RS",
            "$cPeach${BOLD}Claude$RS $cText$nClaude$RS$cFrame  ·  $RS$cTeal${BOLD}Codex$RS $cText$nCodex$RS",
            "$(EgilimSerit ([double[]]$script:gecmis.Cal.ToArray()) 12) ${cFaint}son 6 dk$RS$cMuted · $lid oturum$RS$(if ($isc) { "$cMuted · $RS$cTeal$isc işçi$RS" })") }
        @{ t = '🏃 KOŞULAR'; l = @("$cText$BOLD$($acikKosu.Count)$RS$cMuted açık$RS$(if ($a.Kosular.Count - $acikKosu.Count) { "$cFaint · $($a.Kosular.Count - $acikKosu.Count) biten$RS" })",
            $(if ($kIsci -or $claudeCalisan) { "$cOk$(@($(if ($kIsci) { "$kIsci takım işçisi" }), $(if ($claudeCalisan) { "$claudeCalisan Claude işi" }) | Where-Object { $_ }) -join ' · ') çalışıyor$RS" } else { "${cFaint}çalışan işçi yok$RS" }),
            $(if ($sonBiten.Count) { "$cMuted$(Protect-MerkezSatir ([string]$sonBiten[0].RunId) 16)$RS $cFaint· $(KosuRozetMetin ([string]$sonBiten[0].Rozet))$RS" } else { "${cFaint}son 6 saatte biten yok$RS" })) }
        @{ t = $(if ($a.Onaylar.Count) { '🔔 ONAYLAR' } else { '🔔 ONAYLAR ✓' }); r = $(if ($a.Onaylar.Count) { $cWarn } else { '' }); l = @($(if ($a.Onaylar.Count) { "$cWarn$BOLD$($a.Onaylar.Count)$RS$cWarn senden bekleniyor$RS" } else { "$cOk✓ bekleyen yok$RS" }),
            $(if ($a.Onaylar.Count) { "$cText$BOLD$(Protect-MerkezSatir ([string]$a.Onaylar[0].Satir) 30)$RS" } else { "${cFaint}onay gelince burada çıkar$RS" }),
            $(if ($a.Onaylar.Count) { "${cFaint}sohbete tek başına bu satırı yaz$RS" } else { '' })) }
    )
    if ($a.Kaynak -and $a.Kaynak.Ok) {
        $cy = [int]$a.Kaynak.CommitYuzde; $cr = $(if ($cy -ge 85) { $cErr } elseif ($cy -ge 70) { $cWarn } else { $cOk })
        $oranC = Get-CizTween $script:tween 'commit' ($cy / 100.0)
        $kartlar += @{ t = "💾 KAYNAK$(if ($cy -ge 85) { ' ✕' } elseif ($cy -ge 70) { ' ▲' })"; r = $(if ($cy -ge 85) { $cErr } else { '' }); tr = $(if ($cy -ge 70) { $cWarn } else { '' }); l = @("${cMuted}bellek$RS $(EsikBar $oranC 10) $cr$BOLD%$cy$RS$(if ($a.Kaynak.CommitTavanGB) { "$cFaint · $([Math]::Round([double]$a.Kaynak.CommitGB))/$([Math]::Round([double]$a.Kaynak.CommitTavanGB)) GB$RS" })",
            "${cMuted}boş RAM$RS $cText$('{0:0.0}' -f [double]$a.Kaynak.BosRamGB) GB$RS$(if ($a.Kaynak.OnerilenAjan) { "$cFaint · $($a.Kaynak.OnerilenAjan) ajana yer var$RS" })",
            "${cFaint}son 6 dk$RS $(if ($script:gecmis.Commit.Count -ge 3) { Spark ([double[]]$script:gecmis.Commit.ToArray()) 10 $rgbOk $rgbErr 100 } else { "${cFaint}··········$RS" })$cFaint · $(if ([int]$a.Kaynak.BostaOturum) { $(if ($w -ge 170) { "$($a.Kaynak.BostaOturum) sessiz oturum" } else { "$($a.Kaynak.BostaOturum) sessiz" }) } else { 'sessiz oturum yok' })$RS") }
    }
    if ($a.Maliyet) { try {
        $mUsd = [double]$a.Maliyet.claudeUsd; $bUsd = [double]$a.Maliyet.buyukBaglamUsd; [void](Fmt ([double]$a.Maliyet.codexJeton)); [void][int]$a.Maliyet.gun
        if ([double]::IsInfinity($mUsd) -or [double]::IsInfinity($bUsd) -or $mUsd -gt 1e9) { throw 'maliyet degeri gecersiz' }
        $kartlar += @{ t = "💰 MALİYET · $([int]$a.Maliyet.gun) GÜN"; l = @("$cPeach${BOLD}Claude$RS $cText$BOLD$(Usd $mUsd)$RS$cFaint · API eşdeğeri$RS",
            "$cTeal${BOLD}Codex$RS $cText$(Fmt ([double]$a.Maliyet.codexJeton))$RS$cMuted jeton$RS",
            "$(if ($a.Bugun -and @($a.Bugun.Gunluk).Count -eq 7) { (Spark ([double[]]$a.Bugun.Gunluk) 7 $rgbAcc $CizRgb.Claude) + " ${cFaint}7 gün$RS" })$(if ($bUsd -gt 0 -and $mUsd -gt 0) { "$cFaint · $RS$cWarn%$([int][Math]::Round(100 * $bUsd / $mUsd))$RS$cFaint'si 200K+ bağlamda$RS" })") }
    } catch { $kartlar += @{ t = '💰 MALİYET'; tr = $cWarn; l = @("${cWarn}maliyet dosyası okunamadı$RS", "${cFaint}yeniden taramak: beyin maliyet$RS", '') } } }
    $enEski = ''; foreach ($hd in $a.Aktarimlar) { try { $t = [datetime]::Parse([string]$hd.ts); if (-not $enEski -or $t -lt $enEski.T) { $enEski = @{ T = $t; P = [string]$hd.toProject } } } catch { } }
    $eskiAkt = ($enEski -and ((Get-Date) - $enEski.T).TotalDays -gt 3)
    $kartlar += @{ t = "📋 PANO · AKTARIM$(if ($eskiAkt) { ' ▲' })"; tr = $(if ($eskiAkt) { $cWarn } else { '' }); l = @("$cText$BOLD$($a.Kartlar.Count)$RS$cMuted açık kart$RS$(if (@($a.Kartlar | Where-Object { $_.status -eq 'review' }).Count) { "$cWarn · $(@($a.Kartlar | Where-Object { $_.status -eq 'review' }).Count) incelemede$RS" })",
        "$cText$BOLD$($a.Aktarimlar.Count)$RS$cMuted açık aktarım$RS",
        $(if ($enEski) { "${cFaint}en eskisi $(KisaYas ((Get-Date) - $enEski.T).TotalSeconds) önce$(if ($enEski.P) { " · $(Protect-MerkezSatir $enEski.P 16)" })$RS" } else { "${cFaint}bekleyen aktarım yok$RS" })) }
    $sessiz = (-not $a.Kosular.Count -and -not $a.Onaylar.Count -and -not $claudeCalisan)   # Claude Workflow/Agent iscisi calisirken 'koşu yok' denmez
    if ($sessiz) { $kartlar = @($kartlar | Where-Object { $_.t -notmatch 'KOŞULAR|ONAYLAR' }) }
    if ($w -ge 120) {
        foreach ($ln in (Cards $kartlar $ic 36)) { $L.Add((Row $ln $w)) }   # 36: alti kart tek sirada metni kesiyordu
        if ($sessiz) { $L.Add((Row "  $cOk✓$RS ${cFaint}çalışan koşu yok · onay bekleyen yok$RS" $w)) }
    }
    else {
        # dar ekran: kart ozeti iki satir; deger durum rengiyle (onay sari, sifir yesil)
        $oz1 = @("${cMuted}onay$RS $(if ($a.Onaylar.Count) { "$cWarn$BOLD$($a.Onaylar.Count)$RS" } else { "$cOk" + '0' + "$RS" })")
        if ($a.Kaynak -and $a.Kaynak.Ok) { $cy = [int]$a.Kaynak.CommitYuzde; $oz1 += "${cMuted}bellek$RS $(if ($cy -ge 85) { $cErr } elseif ($cy -ge 70) { $cWarn } else { $cText })%$cy$RS" }
        if ($a.Maliyet) { try { $oz1 += "${cMuted}maliyet $([int]$a.Maliyet.gun) gün$RS $cText$(Usd ([double]$a.Maliyet.claudeUsd))$RS" } catch { $oz1 += "${cWarn}maliyet okunamadı$RS" } }
        $oz2 = @("${cMuted}ajan$RS $cText$calisan/$toplam$RS", "${cMuted}koşu$RS $cText$($acikKosu.Count)$RS", "${cMuted}pano$RS $cText$($a.Kartlar.Count)$RS", "${cMuted}aktarım$RS $cText$($a.Aktarimlar.Count)$RS")
        $L.Add((Row ($oz1 -join "$cFrame  ·  $RS") $w)); $L.Add((Row ($oz2 -join "$cFrame  ·  $RS") $w))
    }
}
function BolumSirada($L, $bolumBas, $a) {
    $w = $script:w; $ic = $w - 4; $sr = $a.Sirada; if (-not $sr) { return }
    $srr = switch ([string]$sr.Renk) { 'ok' { $cOk } 'warn' { $cWarn } 'err' { $cErr } default { $cText } }
    # yalniz HATA serit nabiz atar; uyari sabit sari, yolunda sabit mavi
    $vur = $(if ([string]$sr.Renk -eq 'err' -and $script:hataBas -and ((Get-Date) - $script:hataBas).TotalSeconds -lt 60) { Nabiz $rgbErr 0.8 } elseif ([string]$sr.Renk -eq 'err') { $cErr } elseif ([string]$sr.Renk -eq 'warn') { $cWarn } else { $cAccent })
    Bolum $L $bolumBas 'SIRADA' '🧭 SIRADA' $vur
    $L.Add((Row "$vur$BOLD▌$RS $srr$BOLD$(Protect-MerkezSatir ([string]$sr.Metin) ($ic - 4))$RS" $w))
    if ($sr.Neden) {
        $nd = Protect-MerkezSatir ([string]$sr.Neden) 400
        # kopyalanacak komut satirin en parlak ogesi; KESILMEZ, sigmazsa sarilir (kesik komut kopyalanamaz)
        if ($nd -match '^ilk adım: (beyin [^·]+?)( · (.*))?$') {
            $kmt = $Matches[1].Trim(); $kalan = [string]$Matches[3]
            $on = "${cFaint}ilk adım$RS  "; $sar = Sar $kmt ($ic - 4 - (VisLen $on)) 4
            for ($j = 0; $j -lt $sar.Count; $j++) { $L.Add((Row "$vur▌$RS $(if ($j -eq 0) { $on } else { ' ' * (VisLen $on) })$cAccent$BOLD$($sar[$j])$RS$(if ($j -eq $sar.Count - 1 -and $kalan -and (VisLen "$($sar[$j])  ·  $kalan") -le ($ic - 4 - (VisLen $on))) { "$cFaint  ·  $kalan$RS"; $kalan = '' })" $w)) }
            if ($kalan) { $L.Add((Row "$vur▌$RS $cMuted$(Protect-MerkezSatir $kalan ($ic - 4))$RS" $w)) }
        } else { $L.Add((Row "$vur▌$RS $cMuted$(Protect-MerkezSatir $nd ($ic - 4))$RS" $w)) }
    }
    $L.Add((Blank $w))
}
function BolumOnay($L, $bolumBas, $a) {
    $w = $script:w; $ic = $w - 4; if (-not $a.Onaylar.Count) { return }
    Bolum $L $bolumBas 'ONAY BEKLİYOR' '🔔 ONAY BEKLİYOR' $cWarn
    foreach ($g in $a.Onaylar) {
        $an = "onay:$($g.Satir)"; $sc = SecKayit 'onay' $an $g
        $L.Add((Row (Vurgu "$cWarn$BOLD◐ $(Protect-MerkezSatir $g.Satir 40)$RS   $cMuted$(Protect-MerkezSatir $g.Neden ($ic - 50))$RS" $ic $sc $an) $w))
    }
    $L.Add((Row "$cFaint  sohbete yalnız bu satırı yaz (baslat · birlestir · onayla) · onayla için önce bağımsız doğrulama (--verified-by) · c kopyalar$RS" $w))
    $L.Add((Blank $w))
}
function BolumTeshis($L, $bolumBas, $a, [int]$maks) {
    $w = $script:w; $ic = $w - 4; if (-not $a.Teshis.Count) { return }
    $hata = @($a.Teshis | Where-Object { $_.Seviye -eq 'err' }).Count; $uyari = @($a.Teshis | Where-Object { $_.Seviye -eq 'warn' }).Count
    Bolum $L $bolumBas 'TEŞHİS' "🩺 TEŞHİS ($($a.Teshis.Count))" $(if ($hata) { $cErr } elseif ($uyari) { $cWarn } else { $cAccent })
    foreach ($t in @(@($a.Teshis | Where-Object { $_.Seviye -eq 'err' }) + @($a.Teshis | Where-Object { $_.Seviye -eq 'warn' }) + @($a.Teshis | Where-Object { $_.Seviye -notin @('err', 'warn') }) | Select-Object -First $maks)) {
        # satir ici durum tek hucreli renkli simge (emoji yalniz bolum basliginda)
        $icn = $(if ($t.Seviye -eq 'err') { "$cErr$BOLD✕$RS" } elseif ($t.Seviye -eq 'warn') { "$cWarn$BOLD▲$RS" } else { "$cInfo●$RS" })
        $an = "teshis:$(TeshisAnahtar $t)"; $sc = SecKayit 'teshis' $an $t; $ilk = $true
        $mt = Protect-MerkezSatir ([string]$t.Metin) 400; $kmt = ''
        if ($mt -match '^(.*?)\s*·\s*(beyin [^·]+)$') { $mt = $Matches[1]; $kmt = $Matches[2].Trim() }
        if ($kmt -match '^beyin (\S+)' -and $a.Bugun -and $a.Bugun.SonCalisma -and $a.Bugun.SonCalisma.ContainsKey($Matches[1])) {
            $mt += " · son çalıştırma $(KisaYas ((Get-Date) - [datetime]$a.Bugun.SonCalisma[$Matches[1]]).TotalSeconds) önce"   # komut calisti mi: makbuzdan, canli
        }
        $tek = $(if ($kmt) { "$mt$cFrame  →  $RS$cAccent$BOLD$kmt" } else { $mt })
        if ($kmt -and (VisLen "$mt  →  $kmt") -le ($ic - 2)) { $L.Add((Row (Vurgu "$icn $cText$tek$RS" $ic $sc $an) $w)) }
        else {
            foreach ($parcaS in (Sar $mt ($ic - 2) 2)) { $L.Add((Row (Vurgu $(if ($ilk) { "$icn $cText$parcaS$RS" } else { "  $cText$parcaS$RS" }) $ic $sc $an) $w)); $ilk = $false }
            if ($kmt) { foreach ($ks in (Sar $kmt ($ic - 6) 2)) { $L.Add((Row (Vurgu "  $cFrame→$RS $cAccent$BOLD$ks$RS" $ic $sc $an) $w)) } }
        }
    }
    if ($a.Teshis.Count -gt $maks) { $L.Add((Row "$cFaint +$($a.Teshis.Count - $maks) teşhis daha · beyin doktor$RS" $w)) }
    $L.Add((Blank $w))
}
$script:filtre = 'hepsi'
$filtreAd = @{ hepsi = 'hepsi'; sorun = 'yalnız sorunlu'; claude = 'yalnız Claude'; codex = 'yalnız Codex' }
function FiltreUyar($ag) {
    switch ($script:filtre) {
        'sorun' { return ($ag.Durum -in @('engelli', 'inceleme', 'duraklatildi') -or $ag.Bayat -or $ag.Kaynak -eq 'uzun-arac') }
        'claude' { return ($ag.Ajan -eq 'claude') } 'codex' { return ($ag.Ajan -eq 'codex') } default { return $true }
    }
}
function KanatGruplari($a) {
    # Sira SABIT: once dikkat isteyen (engelli/inceleme), sonra uzun islem, sonra calisan, sonra ad.
    $kanatSira = { param($g) $ds = @($g.Group | ForEach-Object { [string]$_.Durum })
        if ($ds -contains 'engelli' -or $ds -contains 'inceleme') { 0 } elseif (@($g.Group | Where-Object { $_.Kaynak -eq 'uzun-arac' -and $_.Durum -eq 'calisiyor' }).Count) { 1 } elseif (@($ds | Where-Object { $_ -notin @('bosta', 'kapali', 'bitti') }).Count) { 2 } else { 3 } }
    $ajanlar = @($a.Ajanlar | Where-Object { FiltreUyar $_ })   # f filtresi (hepsi / sorunlu / claude / codex)
    return @($ajanlar | Group-Object -Property { $_.Kanat } | Sort-Object -Property @{ Expression = { & $kanatSira $_ } }, @{ Expression = { ([string]$_.Name).ToLowerInvariant() } })
}
function KanatBloklari($gosterGrup, [int]$solW, [bool]$hepsi, [bool]$satirIci) {
    $bloklar = New-Object System.Collections.Generic.List[object]
    foreach ($g in $gosterGrup) {
        $sirali = @($g.Group | Sort-Object -Property @{ Expression = { $durumSira[[string]$_.Durum] } }, @{ Expression = { $_.Tur -ne 'lider' } }, @{ Expression = { $_.NabizSn } })
        $ks = @(KanatSatirlari ([string]$g.Name) $sirali $solW $hepsi $satirIci)
        if ($ks.Count -and $ks[$ks.Count - 1] -eq '__TEK__') { $bloklar.Add(@($ks | Select-Object -First ($ks.Count - 1))) } else { $bloklar.Add(@($ks + @(''))) }
    }
    # tek satirlik kanatlar ardisik durur; cok satirli bir kanattan once ayirici bos satir
    $bl2 = New-Object System.Collections.Generic.List[object]
    for ($i = 0; $i -lt $bloklar.Count; $i++) { $b = @($bloklar[$i]); if ($i -gt 0 -and $b.Count -gt 1 -and @($bloklar[$i - 1]).Count -eq 1) { $b = @('') + $b }; $bl2.Add($b) }
    if ($bl2.Count -and @($bl2[$bl2.Count - 1]).Count -eq 1) { $bl2[$bl2.Count - 1] = @(@($bl2[$bl2.Count - 1]) + @('')) }
    return $bl2
}
function BolumKanatlar($L, $bolumBas, $a, [bool]$hepsi, [bool]$yanPanel) {
    $w = $script:w; $ic = $w - 4
    $aktifMi = { param($g) @($g.Group | Where-Object { $_.Durum -notin @('bosta', 'kapali', 'bitti') }).Count -gt 0 }
    $gruplar = KanatGruplari $a
    $aktifGrup = @($gruplar | Where-Object { & $aktifMi $_ }); $sakinGrup = @($gruplar | Where-Object { -not (& $aktifMi $_) })
    $gosterGrup = @($(if ($hepsi) { $gruplar } else { $aktifGrup }))
    Bolum $L $bolumBas 'KANATLAR' "🏢 KANATLAR ($($gruplar.Count))$(if ($script:filtre -ne 'hepsi') { " · filtre: $($filtreAd[$script:filtre])" })"
    $acikAg = $null; if ($yanPanel -and $script:acik) { $acikAg = @($a.Ajanlar | Where-Object { (AjanAnahtar $_) -eq $script:acik })[0] }
    if ($acikAg) {
        # genis ekran + ayrinti: solda kanatlar, sagda 🔎 AYRINTI paneli
        $solW = [int][Math]::Floor(($ic - 2) * 0.56); $sagW = $ic - $solW - 3
        $sol = New-Object System.Collections.Generic.List[string]; foreach ($b in (KanatBloklari $gosterGrup ($solW - 1) $hepsi $false)) { foreach ($s in $b) { $sol.Add($s) } }
        $sag = New-Object System.Collections.Generic.List[string]
        $sag.Add("$cAccent$BOLD🔎 AYRINTI$RS$cFaint  ·  Esc kapat$RS"); foreach ($s in (AyrintiSatirlari $acikAg ($sagW - 1))) { $sag.Add($s) }
        for ($i = 0; $i -lt [Math]::Max($sol.Count, $sag.Count); $i++) { $L.Add((Row (Cols $(if ($i -lt $sol.Count) { $sol[$i] } else { '' }) $(if ($i -lt $sag.Count) { $sag[$i] } else { '' }) $w $solW) $w)) }
    } else {
        $iki = ($w -ge 200 -and $gosterGrup.Count -ge 2 -and -not $script:acik)   # 170-199 sutunda iki sutun islem balonunu kesiyordu
        if ($iki) { $iki = (@(KanatBloklari $gosterGrup ([int][Math]::Floor(($ic - 2) / 2) - 1) $hepsi $true | Where-Object { @($_).Count -ge 3 }).Count -ge 2) }   # tek satirlik kanatlar tek sutunda daha okunur
        $solW = $(if ($iki) { [int][Math]::Floor(($ic - 2) / 2) } else { $ic })
        $bloklar = KanatBloklari $gosterGrup $(if ($iki) { $solW - 1 } else { $solW }) $hepsi $true
        if ($iki) {
            $sol = New-Object System.Collections.Generic.List[string]; $sag = New-Object System.Collections.Generic.List[string]; $hs = 0; $hd = 0
            foreach ($b in $bloklar) { if ($hs -le $hd) { $sol.AddRange([string[]]$b); $hs += $b.Count } else { $sag.AddRange([string[]]$b); $hd += $b.Count } }
            for ($i = 0; $i -lt [Math]::Max($sol.Count, $sag.Count); $i++) { $L.Add((Row (Cols $(if ($i -lt $sol.Count) { $sol[$i] } else { '' }) $(if ($i -lt $sag.Count) { $sag[$i] } else { '' }) $w $solW) $w)) }
        } else { foreach ($b in $bloklar) { foreach ($s in $b) { $L.Add((Row $s $w)) } } }
    }
    if (-not $gruplar.Count -and $script:filtre -ne 'hepsi') { $L.Add((Row "${cFaint}bu filtreye uyan ajan yok · f ile değiştir$RS" $w)) }
    elseif (-not $gruplar.Count) { $L.Add((Row "${cFaint}son 24 saatte etkin ajan yok$RS" $w)) }
    elseif (-not $gosterGrup.Count) { $L.Add((Row "${cFaint}şu an çalışan ajan yok$RS" $w)) }
    if (-not $hepsi -and $sakinGrup.Count) {
        # sigan kadar kanat adi, kalani +N (satir sonunda kesik ad kalmasin)
        $bas = "▢ boşta kanatlar: "; $par = @(); $kalan = $sakinGrup.Count
        foreach ($sg in $sakinGrup) {
            $ad = "$(Protect-MerkezSatir ([string]$sg.Name) 30) $($sg.Count)"; $deneme = @($par) + @($ad)
            $ek = $(if ($kalan -gt 1) { "  ·  +$($kalan - 1)" } else { '' }); if ((VisLen ($bas + ($deneme -join '  ·  ') + $ek)) -gt ($ic - 1)) { break }
            $par = $deneme; $kalan--
        }
        $L.Add((Row "$cFaint▢ boşta kanatlar: $($par -join '  ·  ')$(if ($kalan) { "  ·  +$kalan" })$RS" $w))
    }
    if ((Strip $L[$L.Count - 1]) -notmatch '^│[\s│]*│$') { $L.Add((Blank $w)) }
}
function KosuSatirlari($L, $k, [bool]$isciler, $a) {
    $w = $script:w; $ic = $w - 4
    $adlar = @('plan', 'başlat', 'topla', 'bütünleştir', 'doğrula', 'ana dala al')
    $rz = $(if ($k.Rozet) { KosuRozet ([string]$k.Rozet) } elseif ($k.Sahipsiz) { KosuRozet 'sahipsiz' } else { KosuRozet '' })
    $sureS = $(if ($k.Sure) { "$cMuted süre$RS $cText$(Kisa ([double]$k.Sure))$RS" } else { '' }) + $(if ($k.Baslangic) { "$cMuted   başladı$RS $cText$(([datetime]$k.Baslangic).ToLocalTime().ToString('HH:mm'))$RS" } else { '' })
    $an = "kosu:$($k.RunId)"; $sc = SecKayit 'kosu' $an $k
    $L.Add((Row (Vurgu "$rz  $cText$BOLD$(Protect-MerkezSatir ([string]$k.RunId) 30)$RS$cFrame · $RS$cMuted$(Protect-MerkezSatir $k.Repo 30)$RS   $sureS" $ic $sc $an) $w))
    if ($k.Kapasite -and $k.Kapasite.Metin) { $L.Add((Row (Vurgu "  ${cMuted}kapasite$RS $(if ($k.Kapasite.Uyari) { $cWarn } else { $cText })$($k.Kapasite.Metin)$RS" $ic $sc $an) $w)) }   # AgentChef 1.8.2+: sahip asimi / baslangicta dusurme gorunur
    # adim cizgisi: tamam ✓ ━, kirik ✕, guncel ▸, bekleyen ○ ╌
    $ok = @($k.Adimlar); $cur = $(if ($null -ne $k.Guncel) { [int]$k.Guncel } else { -1 })
    if ($ok.Count -eq 6) {
        $seg = ''
        for ($i = 0; $i -lt 6; $i++) {
            $s = $(if ($ok[$i]) { "$cOk✓$RS $cMuted$($adlar[$i])$RS" } elseif ($k.Atlanan) { "$cFrame2– $($adlar[$i])$RS" } elseif ($i -eq $cur -and $k.Kirik) { "$cErr$BOLD✕ $($adlar[$i])$RS" } elseif ($i -eq $cur) { "$(if ($k.Durum -eq 'running') { Nabiz $rgbAcc 0.5 } else { $cAccent })$BOLD▸ $($adlar[$i])$RS" } else { "$cFaint○ $($adlar[$i])$RS" })
            $seg += $s; if ($i -lt 5) { $seg += $(if ($ok[$i]) { " $cOk━$RS " } else { " $cBarOff╌$RS " }) }
        }
        if ($k.Atlanan) { $seg = "$cOk✓$RS $cMuted$($adlar[0])$RS $cOk━$RS $cOk✓$RS $cMuted$($adlar[1])$RS $cOk━$RS $cOk✓$RS $cMuted$($adlar[2])$RS   ${cFaint}salt okunur koşu · bütünleştirme ve birleştirme yok$RS" }
        $L.Add((Row "  $seg" $w))
    }
    # isci cubugu: yesil temiz, mavi sef kapsadi, sari kismen, kirmizi sorunlu, koyu iz kalan (en buyuk kalan yontemi)
    $nW = [Math]::Max(1, [int]$k.Isci); $bw = 14
    $kp = [int]$k.Kapsanan; $tz = [int]$(if ($null -ne $k.Temiz) { $k.Temiz } else { $k.Biten }); $ks = [int]$k.Kismen; $so = [Math]::Max(0, [int]$k.Sorunlu - $kp)
    $pay = @($tz, $kp, $ks, $so); $hucre = @(0, 0, 0, 0); $kalan = @(0.0, 0.0, 0.0, 0.0)
    for ($j = 0; $j -lt 4; $j++) { $x = $bw * $pay[$j] / [double]$nW; $hucre[$j] = [int][Math]::Floor($x); $kalan[$j] = $x - $hucre[$j] }
    $hedef = [int][Math]::Round($bw * [Math]::Min($nW, ($tz + $kp + $ks + $so)) / [double]$nW)
    while (($hucre | Measure-Object -Sum).Sum -lt $hedef) { $mx = 0; for ($j = 1; $j -lt 4; $j++) { if ($kalan[$j] -gt $kalan[$mx]) { $mx = $j } }; $hucre[$mx]++; $kalan[$mx] = -1 }
    $iBar = "$cOk$('█' * $hucre[0])$cAccent$('█' * $hucre[1])$cWarn$('█' * $hucre[2])$cErr$('█' * $hucre[3])$cIz$('█' * [Math]::Max(0, $bw - ($hucre | Measure-Object -Sum).Sum))$RS"
    $parca = @("$iBar $cText$($k.Biten)/$($k.Isci)$RS$cMuted işçi$RS$(if ($kp) { "$cAccent · $kp şef kapsadı$RS" })")
    if ($k.Kontrol -and $k.Kontrol.Toplam) { $parca += $(if ($k.Kontrol.Gecen -eq $k.Kontrol.Toplam) { "$cOk✓ $($k.Kontrol.Gecen)/$($k.Kontrol.Toplam) kontrol$RS" } else { "$cErr✕ $($k.Kontrol.Gecen)/$($k.Kontrol.Toplam) kontrol$RS" }) }
    if ($k.JetonGiris -or $k.JetonCikis) { $parca += "${cMuted}jeton$RS $cText$(Fmt ([double]$k.JetonGiris))$RS$cFaint↓ $RS$cText$(Fmt ([double]$k.JetonCikis))$RS$cFaint↑$RS$(if ($k.JetonOnbellek -and $k.JetonGiris) { "$cMuted · önbellek %$([int][Math]::Round(100.0 * $k.JetonOnbellek / $k.JetonGiris))$RS" })" } elseif ($k.Jeton) { $parca += "$cMuted$(Fmt $k.Jeton) jeton$RS" }
    if ($k.Dosya) { $parca += "$cMuted$($k.Dosya) dosya$RS" }
    $L.Add((Row "  $($parca -join "$cFrame   ·   $RS")" $w))
    $snr = switch ($k.Sonraki.Renk) { 'ok' { $cOk } 'warn' { $cWarn } 'err' { $cErr } default { $cMuted } }
    if (-not $k.Atlanan) { $L.Add((Row "  $cAccent▌$RS $snr$(Protect-MerkezSatir ([string]$k.Sonraki.Metin) ($ic - 6))$RS" $w)) }
    if ($isciler) {
        foreach ($ag in @($a.Ajanlar | Where-Object { $_.Tur -eq 'isci' -and $_.Kosu -eq $k.RunId } | Sort-Object -Property @{ Expression = { $durumSira[[string]$_.Durum] } }, @{ Expression = { [string]$_.Ad } })) {
            $sc2 = SecKayit 'isci' (AjanAnahtar $ag) $ag
            $L.Add((Row "  $(AjanSatir $ag ($ic - 2) $sc2 $false 19)" $w))
            if ($script:acik -eq (AjanAnahtar $ag)) { foreach ($s in (AyrintiSatirlari $ag ($ic - 8))) { $L.Add((Row "      $cAccent│$RS $s" $w)) } }
        }
        foreach ($kt in @($a.Kartlar | Where-Object { $_.owner -and [string]$_.owner.session -eq "team-$($k.RunId)" })) { $L.Add((Row "  $cFaint▤ pano$RS $cText$(Protect-MerkezSatir ([string]$kt.id) 12)$RS $cMuted$($panoAd[[string]$kt.status])$RS$(if ($a.Yetim -and $a.Yetim.ContainsKey([string]$kt.id)) { "$cWarn · yetim$RS" })" $w)) }
    }
    $L.Add((Blank $w))
}
function BolumClaudeIsler($L, $bolumBas, $a, [bool]$yalnizCalisan) {
    # Claude Code Workflow kosulari ve Agent alt ajanlari (takim kosusu disindaki isciler). Genel'de yalniz calisanlar.
    $w = $script:w; $ci = @($a.ClaudeIsler | Where-Object { $_ }); if (-not $ci.Count) { return }
    $calisan = @($ci | Where-Object { $_.Durum -eq 'calisiyor' })
    if ($yalnizCalisan -and -not $calisan.Count) { return }
    $digeri = @($ci | Where-Object { $_.Durum -ne 'calisiyor' } | Sort-Object -Property @{ Expression = { $_.Son }; Descending = $true })
    $goster = @($calisan) + @($(if ($yalnizCalisan) { @() } else { $digeri | Select-Object -First $(if ($script:hepsi.Kosular) { 40 } else { 4 }) }))
    Bolum $L $bolumBas 'CLAUDE' "🤖 CLAUDE İŞÇİLERİ ($($calisan.Count) çalışıyor · son 2 sa $($ci.Count))"
    $don = '⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    foreach ($c in $goster) {
        $ikon = switch ([string]$c.Durum) { 'calisiyor' { $script:CizCanli = $true; "$cOk$($don[[int]($script:tik % 10)])$RS" } 'hatali' { "$cErr✕$RS" } 'sessiz' { "$cWarn◷$RS" } default { "$cFaint✓$RS" } }
        $durS = switch ([string]$c.Durum) { 'calisiyor' { "${cOk}çalışıyor$RS" } 'hatali' { "${cErr}hatayla bitti$RS" } 'sessiz' { "${cWarn}sessiz$RS" } default { "${cFaint}bitti$RS" } }
        $sayi = $(if ($c.Tur -eq 'workflow') { "$($c.Biten)/$($c.Toplam) bitti$(if ($c.Hata) { " · $($c.Hata) hata" })$(if ($c.Calisan) { " · $($c.Calisan) açık" })" } else { "$($c.Toplam) ajan$(if ($c.Calisan) { " · $($c.Calisan) açık" })" })
        $ek = @(); if ($c.Ad) { $ek += (Protect-MerkezSatir ([string]$c.Ad) 60) }; if ($c.Faz) { $ek += "faz $(Protect-MerkezSatir ([string]$c.Faz) 20)" }
        $ek += "$(KisaYas ((Get-Date) - [datetime]$c.Son).TotalSeconds) önce"
        $L.Add((Row "  $ikon $cPeach$BOLD$(Pad (Protect-MerkezSatir ([string]$c.Proje) 18) 18)$RS $cMuted$(Pad $(if ($c.Tur -eq 'workflow') { 'workflow' } else { 'ajan' }) 8)$RS $(Pad $durS 13) $cText$(Pad $sayi 26)$RS $cFaint$($ek -join ' · ')$RS" $w))
    }
    if (-not $yalnizCalisan -and $goster.Count -lt $ci.Count) { $L.Add((Row "$cFaint  +$($ci.Count - $goster.Count) biten daha · a hepsi$RS" $w)) }
    $L.Add((Blank $w))
}
function BolumKosular($L, $bolumBas, $a, [bool]$hepsi, [bool]$isciler) {
    $w = $script:w
    BolumClaudeIsler $L $bolumBas $a (-not $isciler)   # Claude Code Workflow/Agent iscileri: takim kosulariyla ayni yerde
    if (-not $a.Kosular.Count) {
        if ($isciler) {
            Bolum $L $bolumBas 'KOŞULAR' '🏃 KOŞULAR (0)'
            $L.Add((Row "${cText}Çalışan takım koşusu yok.$RS ${cFaint}Son 6 saatte biten koşu da yok.$RS" $w)); $L.Add((Blank $w))
            $L.Add((Row "  ${cMuted}koşu planlamak:$RS     $cAccent${BOLD}beyin takim plan$RS" $w))
            $L.Add((Row "  ${cMuted}koşuların durumu:$RS   $cAccent${BOLD}beyin takim durum$RS" $w))
            if ($a.SonKosu) { $L.Add((Blank $w)); $L.Add((Row "  ${cFaint}son koşu:$RS $cText$(Protect-MerkezSatir $a.SonKosu.RunId 30)$RS$cFaint · $(Protect-MerkezSatir $a.SonKosu.Repo 30) · $(Protect-MerkezSatir $(switch ([string]$a.SonKosu.Durum) { 'aborted' { 'iptal edildi' } 'failed' { 'başarısız' } 'merged' { 'ana dala alındı' } 'verified' { 'doğrulandı' } default { [string]$a.SonKosu.Durum } }) 20) · $(KisaYas ((Get-Date) - $a.SonKosu.Zaman).TotalSeconds) önce$RS" $w)) }
            $L.Add((Blank $w))
        }
        return
    }
    Bolum $L $bolumBas 'KOŞULAR' "🏃 KOŞULAR ($($a.Kosular.Count))"
    $kosuSirali = @($a.Kosular | Sort-Object -Property @{ Expression = { $_.Bitmis } }, @{ Expression = { $(if ($_.KayitGuncel) { $_.KayitGuncel } else { $_.Guncel }) }; Descending = $true })
    $acikK = @($kosuSirali | Where-Object { -not $_.Bitmis }); $bitenK = @($kosuSirali | Where-Object { $_.Bitmis })
    $gosterK = @($acikK) + @($bitenK | Select-Object -First $(if ($hepsi) { $bitenK.Count } else { 1 }))
    foreach ($k in $gosterK) { KosuSatirlari $L $k $isciler $a }
    if ($gosterK.Count -lt $kosuSirali.Count) { $L[$L.Count - 1] = (Row "$cFaint  +$($kosuSirali.Count - $gosterK.Count) biten koşu daha · a hepsi$RS" $w); $L.Add((Blank $w)) }
}
function BolumPanoAktarim($L, $bolumBas, $a, [int]$maks) {
    $w = $script:w; $ic = $w - 4
    # Yan yana: pano tarafi %42 (kart satiri kisa, aktarim metni uzun), en az 52 hucre; biri bossa yan yana koyma
    $yan = ($w -ge 140 -and $a.Kartlar.Count -gt 0 -and $a.Aktarimlar.Count -gt 0); $kw = $(if ($yan) { [Math]::Max(52, [int][Math]::Floor(($ic - 2) * 0.42)) } else { $ic })
    $sagGen = $(if ($yan) { $w - 4 - $kw - 2 } else { $ic })
    $pL = New-Object System.Collections.Generic.List[string]; $aL = New-Object System.Collections.Generic.List[string]
    foreach ($kt in @($a.Kartlar | Select-Object -First $maks)) {
        $st = [string]$kt.status; $r = switch ($st) { 'blocked' { $cErr } 'review' { $cWarn } 'in_progress' { $cOk } default { $cFaint } }
        $sahip = $(if ($kt.owner -and $kt.owner.agent) { Protect-MerkezSatir ([string]$kt.owner.agent) 10 } else { '' })
        $bas = Protect-MerkezSatir ([string]$kt.title) 90
        if ($bas -match '^Team run (R[\w-]+): (.+)$') {   # takim karti: basliklar ozdes, ayirt eden repo + kosu + rol + ilk yazma yolu
            $rid = $Matches[1]; $rol = $Matches[2]; $yol = $(if ($kt.writeScope -and @($kt.writeScope.paths).Count) { ([string]@($kt.writeScope.paths)[0]).TrimEnd('/', '\') -replace '^.*[\\/]', '' } else { '' })
            $bas = "$(if ($kt.writeScope -and $kt.writeScope.repo) { "$cText$(Protect-MerkezSatir ([string]$kt.writeScope.repo) 20)$RS$cFaint · " })$cFaint…$(if ($rid.Length -gt 4) { $rid.Substring($rid.Length - 4) } else { $rid }) · $RS$cMuted$(RolTr $rol)$(if ($yol) { "$cFaint · $(Protect-MerkezSatir $yol 40)" })"
        }
        $yetim = [bool]($a.Yetim -and $a.Yetim.ContainsKey([string]$kt.id))
        $stAd = $panoAd[$st]; if ($yetim) { $r = $cWarn; $stAd = 'yetim' }
        $an = "kart:$($kt.id)"; $sc = SecKayit 'kart' $an $kt $yetim
        $pL.Add((Vurgu "$r● $(Pad $stAd 10)$RS $cText$(Pad (Protect-MerkezSatir ([string]$kt.id) 12) 9)$RS $(if ($sahip) { "$($kimlikRenk[$sahip])$(Pad $sahip 6)$RS " })$cMuted$bas$RS" ($kw - 1) $sc))
    }
    if (-not $a.Kartlar.Count) { $pL.Add("$cOk✓$RS$cFaint açık kart yok$RS") } elseif ($a.Kartlar.Count -gt $maks) { $pL.Add("$cFaint +$($a.Kartlar.Count - $maks) kart · beyin pano list$RS") }
    foreach ($hd in @($a.Aktarimlar | Sort-Object -Property @{ Expression = { [string]$_.ts } } | Select-Object -First $maks)) {   # en eski ustte: kapatilacak olan
        $yasSn = -1; try { $yasSn = ((Get-Date) - [datetime]::Parse([string]$hd.ts)).TotalSeconds } catch { }
        $kimden = Protect-MerkezSatir $(if ($hd.from -is [string]) { [string]$hd.from } else { [string]$hd.from.agent }) 8; $kime = Protect-MerkezSatir $(if ($hd.to -is [string]) { [string]$hd.to } else { [string]$hd.to.agent }) 8
        $yon = "$($kimlikRenk[$kimden])$kimden$RS$cFaint→$RS$($kimlikRenk[$kime])$kime$RS"
        $hp = Protect-MerkezSatir ([string]$hd.toProject) 30; $hpS = $(if ($hp) { "$(if ($yasSn -gt 3 * 86400) { $cWarn } else { $cMuted })$hp$RS" } else { "${cFaint}tüm projeler$RS" })
        $eskiMi = $yasSn -gt 3 * 86400; $yasR = $(if ($eskiMi) { "$cWarn$BOLD" } elseif ($yasSn -ge 86400) { $cText } else { $cMuted })
        $hid = [string]$hd.id; $kid = Protect-MerkezSatir $hid.Substring([Math]::Max(0, $hid.Length - 4)) 4
        $an = "aktarim:$hid"; $sc = SecKayit 'aktarim' $an $hd
        $aL.Add((Vurgu "$(Pad $yon 14) $cFaint$kid$RS $(Pad $hpS 13) $(PadL "$yasR$(KisaYas $yasSn)$RS" 7)  $(KonuAyrinti (Protect-MerkezSatir ([string]$hd.question) 160) $cText)" $sagGen $sc))
        if ($script:acikAktarim -eq $hid) { foreach ($s in (Sar (Protect-MerkezSatir ([string]$hd.question) 600) ($sagGen - 4) 4)) { $aL.Add("    $cAccent│$RS $cMuted$s$RS") }; $aL.Add("    $cAccent│$RS ${cFaint}c kopyala: beyin aktar -Tamam $(Protect-MerkezSatir $hid 40)$RS") }
    }
    if (-not $a.Aktarimlar.Count) { $aL.Add("$cOk✓$RS$cFaint bekleyen aktarım yok$RS") } elseif ($a.Aktarimlar.Count -gt $maks) { $aL.Add("$cFaint +$($a.Aktarimlar.Count - $maks) daha · beyin aktar$RS") }
    $bolumBas.Add(@{ Ad = 'PANO · AKTARIMLAR'; I = $L.Count })
    if ($yan) {
        $solEt = Sec "📋 PANO ($($a.Kartlar.Count) açık)"
        $L.Add((HLine $w ($solEt + "$cFrame " + ('─' * [Math]::Max(1, $kw - (VisLen $solEt) - 2)) + "┬─ $RS" + (Sec "📨 AKTARIMLAR ($($a.Aktarimlar.Count) açık)")) '├' '┤'))
        for ($i = 0; $i -lt [Math]::Max($pL.Count, $aL.Count); $i++) { $L.Add((Row (Cols $(if ($i -lt $pL.Count) { $pL[$i] } else { '' }) $(if ($i -lt $aL.Count) { $aL[$i] } else { '' }) $w $kw) $w)) }
    } else {
        if ($a.Kartlar.Count -or -not $a.Aktarimlar.Count) { $L.Add((HLine $w (Sec "📋 PANO ($($a.Kartlar.Count) açık)") '├' '┤')); foreach ($s in $pL) { $L.Add((Row $s $w)) } }
        $L.Add((HLine $w (Sec "📨 AKTARIMLAR ($($a.Aktarimlar.Count) açık)") '├' '┤')); foreach ($s in $aL) { $L.Add((Row $s $w)) }
    }
}
function OlaySatiri($ol, [int]$gen) {
    $olRenk = @{ ok = $cOk; warn = $cWarn; err = $cErr; accent = $cAccent; teal = $cTeal; muted = $cMuted }
    $r = $olRenk[[string]$ol.Renk]; if (-not $r) { $r = $cMuted }
    $yasS = KisaYas ((Get-Date) - $ol.Zaman).TotalSeconds
    $ajR = $kimlikRenk[[string]$ol.Ajan]; if (-not $ajR) { $ajR = $cMuted }
    $sag = $(if ($ol.Kanat) { "$cFaint · $(Protect-MerkezSatir ([string]$ol.Kanat) 24)$RS" } else { '' })
    $adetS = $(if ($ol.Adet -gt 1) { "$cFaint ×$($ol.Adet)$RS" } else { '' })
    return (Vurgu "$cFaint$($ol.Zaman.ToString('HH:mm'))$RS $cFrame2$(PadL $yasS 6)$RS  $ajR$(Pad (Protect-MerkezSatir ([string]$ol.Ajan) 8) 7)$RS $r$($ol.Ikon) $(Protect-MerkezSatir ([string]$ol.Metin) 140)$RS$adetS$sag" $gen $false (OlayAnahtar $ol))
}
function RutinAd($ol) { switch ([string]$ol.Tur) { 'flush/FLUSH_OK' { '✎ özet' } 'aktar/DEVIR_KAYDEDILDI' { '⇄ aktarım' } 'gom/GOM_OK' { '◆ gömme' } 'zamanli/ZAMANLI_OK' { '◷ zamanlı görev' } default { "$($ol.Ikon) $(Protect-MerkezSatir ((([string]$ol.Metin) -split ' ')[0]) 24)" } } }   # ham betik adi temizlenir
function RutinSatiri($g, [int]$gen) {
    # ayni ajanin ardisik rutin olaylari: "22:00–22:21  codex  ✎ özet ×11 · ⇄ aktarım ×4" (anlamli olaylar ayri satirda parlak kalir)
    $ajR = $kimlikRenk[[string]$g.Ajan]; if (-not $ajR) { $ajR = $cMuted }
    $yasS = KisaYas ((Get-Date) - $g.Zaman).TotalSeconds
    $ic = @($g.Say.Keys | ForEach-Object { "$_$(if ($g.Say[$_] -gt 1) { " ×$($g.Say[$_])" })" }) -join "$cFrame · $RS$cFaint"
    return "$cFaint$($g.Zaman.ToString('HH:mm'))$RS $cFrame2$(PadL $yasS 6)$RS  $ajR$(Pad (Protect-MerkezSatir ([string]$g.Ajan) 8) 7)$RS $cFaint$ic$RS$(if ($g.Ilk.ToString('HH:mm') -ne $g.Zaman.ToString('HH:mm')) { "$cFrame2  $($g.Ilk.ToString('HH:mm'))–$($g.Zaman.ToString('HH:mm'))$RS" })"
}
function OlayListesi($olaylar, [int]$gen, [int]$adet) {
    # olay satirlari; ardisik iki olay arasinda 1 saatten uzun bosluk ya da gun degisimi soluk ayiracla
    $R = New-Object System.Collections.Generic.List[string]; $onceki = $null
    $gruplu = New-Object System.Collections.Generic.List[object]
    foreach ($ol in $olaylar) {
        $son = $(if ($gruplu.Count) { $gruplu[$gruplu.Count - 1] } else { $null })
        if ($son -and [string]$ol.Renk -eq 'muted' -and $son.Rutin -and $son.Ajan -eq $ol.Ajan -and ($son.Ilk - $ol.Zaman).TotalMinutes -lt 60) {
            $son.Ilk = $ol.Zaman; $son.Say[(RutinAd $ol)] = [int]$son.Say[(RutinAd $ol)] + [int][Math]::Max(1, $ol.Adet); $son.N++; continue
        }
        if ([string]$ol.Renk -eq 'muted') { $gruplu.Add(@{ Rutin = $true; Ajan = $ol.Ajan; Zaman = $ol.Zaman; Ilk = $ol.Zaman; Ol = $ol; N = 1; Say = [ordered]@{ (RutinAd $ol) = [int][Math]::Max(1, $ol.Adet) } }) }
        else { $gruplu.Add(@{ Rutin = $false; Ajan = $ol.Ajan; Zaman = $ol.Zaman; Ilk = $ol.Zaman; Ol = $ol }) }
    }
    foreach ($g in $gruplu) {
        $ol = $g.Ol
        if ($R.Count -ge $adet) { break }
        if ($onceki -and (($onceki.Zaman - $ol.Zaman).TotalMinutes -gt 60 -or $onceki.Zaman.Date -ne $ol.Zaman.Date) -and $R.Count -lt $adet - 1) {
            $R.Add("$cFrame2┄┄ $(if ($onceki.Zaman.Date -ne $ol.Zaman.Date) { $ol.Zaman.ToString('d MMM', [Globalization.CultureInfo]::GetCultureInfo('tr-TR')) } else { "$(Kisa ($onceki.Zaman - $ol.Zaman).TotalSeconds) sessiz" }) ┄┄$RS")
        }
        if ($g.Rutin -and $g.N -gt 1) { $R.Add((RutinSatiri $g $gen)) } else { $R.Add((OlaySatiri $ol $gen)) }
        $onceki = @{ Zaman = $g.Ilk }
    }
    return ,$R
}
function BolumOlaylar($L, $bolumBas, $a, [int]$adet) {
    $w = $script:w; $ic = $w - 4
    [object[]]$olaylar = @(); if ($a.Olaylar) { $olaylar = $a.Olaylar.ToArray() }   # @() generic List uzerinde PS 5.1de firlatir; $(...) tek ogeyi acar
    if (-not $olaylar.Count -or $adet -lt 3) { return }
    $bolumBas.Add(@{ Ad = 'SON OLAYLAR'; I = $L.Count })
    $L.Add((HLine $w ("$(Sec '📜 SON OLAYLAR')$cFaint  motor makbuzları · tümü: 4$RS") '├' '┤'))
    foreach ($s in (OlayListesi $olaylar $ic $adet)) { $L.Add((Row $s $w)) }
}
function BugunTablosu($a, [int]$gen) {
    # Olaylar sekmesi sag sutun: bugun / dun (ayni saate kadar) tablosu + 24 saatlik dagilim + depo bazli commit
    $b = $a.Bugun; $T = New-Object System.Collections.Generic.List[string]
    $T.Add("$cAccent$BOLD📅 BUGÜN$RS$cFaint  dün = aynı saate kadar$RS")
    if (-not $b) { $T.Add("${cFaint}veri yok$RS"); return $T }
    $sat = { param($ad, $bv, $dv, $az) "$(Pad "$cMuted$ad$RS" 12)$(PadL "$cText$BOLD$bv$RS" 9)$(PadL "$cFaint$dv$RS" 10)$(Fark ([double]$(if ($bv -match '^[\d.,]+$') { $bv -replace ',', '.' } else { 0 })) $(if ($dv -match '^[\d.,]+$') { [double]($dv -replace ',', '.') } else { $null }) $az)" }
    $T.Add("$(Pad '' 12)$(PadL "${cFaint}bugün$RS" 9)$(PadL "${cFaint}dün$RS" 10)")
    if ($null -ne $b.Usd) { $T.Add("$(Pad "${cMuted}Claude `$$RS" 12)$(PadL "$cPeach$BOLD$('{0:0.00}' -f [double]$b.Usd)$RS" 9)$(PadL "$cFaint$(if ($null -ne $b.UsdDun) { '{0:0.00}' -f [double]$b.UsdDun } else { '—' })$RS" 10)$(Fark ([double]$b.Usd) $b.UsdDun $true)") }
    $T.Add((& $sat 'oturum' "$([int]$b.Oturum)" "$([int]$b.OturumDun)" $false))
    $T.Add((& $sat 'özet' "$([int]$b.Ozet)" "$([int]$b.OzetDun)" $false))
    $T.Add((& $sat 'commit' "$([int]$b.Commit)" "$([int]$b.CommitDun)" $false))
    $T.Add((& $sat 'yayın' "$([int]$b.Yayin)" "$([int]$b.YayinDun)" $false))
    $T.Add((& $sat 'derleme' "$([int]$b.Derleme)" "$([int]$b.DerlemeDun)" $false))
    $T.Add((& $sat 'hata' "$([int]$b.Hata)" "$([int]$b.HataDun)" $true))
    $T.Add((& $sat 'engel' "$([int]$b.Engel)" "$([int]$b.EngelDun)" $false))
    $T.Add('')
    $T.Add("${cFaint}son 24 saat etkinlik (saat başına)$RS")
    $T.Add((Spark ([double[]]@($(if ($b.Son24) { $b.Son24 } else { $b.Saatlik }))) ([Math]::Min($gen - 2, 24)) $rgbInfo $rgbAcc))
    if ($b.UsdZaman) { $T.Add("${cFaint}maliyet $(([datetime]$b.UsdZaman).ToString('HH:mm')) itibarıyla (tam gün dünle)$RS"); $T.Add("${cFaint}tazelemek: $RS$cAccent${BOLD}beyin maliyet$RS") }
    if ($b.CommitDepo -and $b.CommitDepo.Count) { $T.Add(''); $T.Add("${cFaint}commit · depo$RS"); foreach ($k in @($b.CommitDepo.Keys | Sort-Object { -$b.CommitDepo[$_] } | Select-Object -First 5)) { $T.Add("  $cText$(Pad (Protect-MerkezSatir $k 24) 26)$RS$cMuted$($b.CommitDepo[$k])$RS") } }
    return $T
}

function OnbBolum($L, $bolumBas, [string]$ad, [scriptblock]$kur) {
    # Anahtar: veri surumu, boyut, sekme, secim, acik ayrinti/aktarim, hepsi, kaydirma ve 30 sn'lik yas penceresi. Bolum kurulurken bir
    # sey canlandiysa (parlama, yumusak gecis, nabiz) onbellege alinmaz. Isabette satirlar, secilebilirler ve bolum baslari geri yuklenir.
    $k = "$ad|$($script:veriSurum)|$($script:w)|$($script:h)|$($script:sekmeAktif)|$($script:secAnahtar[$script:sekmeAktif])|$($script:acik)|$($script:acikAktarim)|$($script:hepsi[$script:sekmeAktif])|$($script:olayKaydir)|$($script:filtre)|$([int64][Math]::Floor((Get-Date).Ticks / 300000000))"
    $e = $script:bolumOnb[$ad]
    if ($e -and $e.K -eq $k) {
        $i0 = $L.Count; foreach ($s in $e.L) { $L.Add($s) }
        foreach ($b in $e.B) { $bolumBas.Add(@{ Ad = $b.Ad; I = $i0 + $b.I }) }
        foreach ($s in $e.S) { [void](SecKayit $s.Tur $s.Ham $s.Nesne $s.Yetim) }
        $script:onbIsabet++; return
    }
    $i0 = $L.Count; $s0 = $script:secilebilir.Count; $b0 = $bolumBas.Count; $onceCanli = $script:CizCanli; $script:CizCanli = $false
    & $kur
    $canli = $script:CizCanli; $script:CizCanli = $onceCanli -or $canli
    if ($canli) { $script:bolumOnb.Remove($ad); return }
    $kL = @(); for ($i = $i0; $i -lt $L.Count; $i++) { $kL += $L[$i] }
    $kS = @(); for ($i = $s0; $i -lt $script:secilebilir.Count; $i++) { $kS += $script:secilebilir[$i] }
    $kB = @(); for ($i = $b0; $i -lt $bolumBas.Count; $i++) { $kB += @{ Ad = $bolumBas[$i].Ad; I = $bolumBas[$i].I - $i0 } }
    $script:bolumOnb[$ad] = @{ K = $k; L = $kL; S = $kS; B = $kB }
}
$script:yardimAcik = $false
function YardimIcerik($L) {
    # ? ile acilan rehber: tuslar, renkler, simgeler, ses. Hicbir sey yazmaz.
    $w = $script:w
    $sat = { param($k, $e) "  $cAccent$BOLD$(Pad $k 14)$RS $cText$e$RS" }
    $L.Add((HLine $w (Sec '📖 YARDIM · ? kapatır') '├' '┤'))
    $L.Add((Row "${cMuted}Tuşlar$RS" $w))
    foreach ($t in @(@('Tab · 1-4', 'sekme: Genel, Ajanlar, Koşular, Olaylar'), @('↑ ↓ · j k', 'satır seç (Olaylar sekmesinde kaydır)'), @('Enter', 'ayrıntı · işçi paneli · koşu panosu · aktarımın tam metni'),
            @('Esc', 'ayrıntıyı kapat'), @('c', 'seçili satırın güvenli komutunu panoya kopyala (çalıştırmaz)'), @('g', 'ilk soruna atla'), @('f', 'kanat filtresi: hepsi → sorunlu → Claude → Codex'),
            @('p', 'koşu panosu'), @('a', 'boştakileri / biten koşuları göster-gizle'), @('PgUp PgDn', 'olay listesini kaydır'), @('r', 'yenile: kaynağı yeniden ölçer, tüm verileri yeniden okur'), @('q', 'çık'))) { $L.Add((Row (& $sat $t[0] $t[1]) $w)) }
    $L.Add((Blank $w))
    $L.Add((Row "${cMuted}Renkler ve simgeler$RS" $w))
    # parcalar satira sigdigi kadar yan yana; sigmayan alt satira (dar pencerede metin kesilmez)
    $paket = { param([string[]]$pr, [string]$ay = '   ') $cur = ''; foreach ($x in $pr) { if (-not $cur) { $cur = "  $x" } elseif ((VisLen "$cur$ay$x") -le ($w - 4)) { $cur = "$cur$ay$x" } else { $L.Add((Row $cur $w)); $cur = "  $x" } }; if ($cur) { $L.Add((Row $cur $w)) } }
    & $paket @("$cOk⠋ çalışıyor$RS", "$cWarn◷ uzun işlem$RS", "$cWarn▲ uyarı$RS", "$cErr✕ hata / engelli$RS", "$cInfo● bilgi$RS", "$cMauve‖ kota$RS", "$cFaint○ boşta$RS", "$cPeach${BOLD}Claude$RS", "$cTeal${BOLD}Codex$RS")
    & $paket @("$(Spark ([double[]]@(1, 2, 3, 2, 1, 3)) 6 $rgbTeal $rgbOk 3) ${cText}etkinlik şeridi: son 2 dakika,$RS", "${cText}20 sn'lik kovalar; yeni olayda son hücre atar$RS") ' '
    & $paket @("${cText}parlayan satır yeni olaydır (2,5 sn);$RS", "${cText}hata rozeti 60 sn, onay rozeti 30 sn atar, sonra sabit kalır$RS") ' '
    $L.Add((Blank $w))
    $L.Add((Row "${cMuted}Ses (isteğe bağlı)$RS" $w))
    & $paket @("${cText}şu an: $RS$cAccent$(@{ kapali = "kapalı"; ton = "ton"; toast = "Windows bildirim sesi" }[$script:sesKip])$RS", "${cFaint}sessiz saat: $RS$(if (Test-CizSessizGecerli $script:sessizSaat) { "$cFaint$(Protect-MerkezSatir $script:sessizSaat 12)$RS" } else { "$cWarn$(Protect-MerkezSatir $script:sessizSaat 12) (geçersiz, yok sayılıyor)$RS" })") " $cFaint·$RS "
    & $paket @("${cFaint}aç: $RS${cAccent}beyin ayar BEYIN_MERKEZ_SES ton$RS${cFaint} (ya da toast)$RS", "${cFaint}sessiz saat: $RS${cAccent}beyin ayar BEYIN_MERKEZ_SESSIZ 23-08$RS") " $cFaint·$RS "
    & $paket @("${cFaint}tonlar: hata (inen), onay bekliyor (çıkan), koşu bitti (üçlü),$RS", "${cFaint}uyarıyla biten koşu (tek nota); iptal sessiz$RS") ' '
    & $paket @("${cFaint}aynı olay bir kez çalar; eşikte gidip gelen alarm 30 dk susar.$RS", "${cFaint}Ayar değişince paneli yeniden aç (q, sonra beyin merkez).$RS") ' '
    $L.Add((Blank $w))
    & $paket @("${cMuted}Panel salt okunurdur.$RS", "${cFaint}onayla / baslat / birlestir satırlarını sohbete sen yazarsın; panel onay vermez.$RS") ' '
}
function SekmeIcerik($L, $bolumBas, $a, [int]$h) {
    $w = $script:w; $ic = $w - 4
    switch ($script:sekmeAktif) {
        'Genel' {
            BolumRozet $L $a; OnbBolum $L $bolumBas 'bugun' { BolumBugun $L $a }; $L.Add((Blank $w))
            OnbBolum $L $bolumBas 'kartlar' { BolumKartlar $L $a }; $L.Add((Blank $w))
            OnbBolum $L $bolumBas 'sirada' { BolumSirada $L $bolumBas $a; BolumOnay $L $bolumBas $a; BolumTeshis $L $bolumBas $a $(if ($w -ge 170) { 5 } else { 3 }) }
            OnbBolum $L $bolumBas 'kanatlar' { BolumKanatlar $L $bolumBas $a $script:hepsi.Genel $false }
            BolumKosular $L $bolumBas $a $false $false
            OnbBolum $L $bolumBas 'pano' { BolumPanoAktarim $L $bolumBas $a $(if ($w -ge 170) { 6 } else { 4 }) }
            # SON OLAYLAR ekranda kalan bos yuksekligi doldurur; hicbir bolumu disari itmez
            $bos = $(if ($Tek -and $Yukseklik -le 0) { 10 } else { ($h - 1) - $L.Count - 1 - 1 })
            OnbBolum $L $bolumBas "olaylar$bos" { BolumOlaylar $L $bolumBas $a ([Math]::Min(14, $bos)) }
        }
        'Ajanlar' {
            BolumRozet $L $a; $L.Add((Blank $w))
            OnbBolum $L $bolumBas 'kanatlarA' { BolumKanatlar $L $bolumBas $a $script:hepsi.Ajanlar ($w -ge 170) }
            BolumTeshis $L $bolumBas $a 5
        }
        'Kosular' {
            BolumRozet $L $a; $L.Add((Blank $w))
            BolumOnay $L $bolumBas $a
            BolumKosular $L $bolumBas $a $script:hepsi.Kosular $true
        }
        'Olaylar' {
            BolumRozet $L $a; if ($w -lt 120) { BolumBugun $L $a }; $L.Add((Blank $w))   # >=120: sagdaki BUGUN tablosu ayni bilgiyi tasir
            [object[]]$olaylar = @(); if ($a.Olaylar) { $olaylar = $a.Olaylar.ToArray() }
            $bos = $(if ($Tek -and $Yukseklik -le 0) { 24 } else { [Math]::Max(3, ($h - 1) - $L.Count - 1 - 1) })
            $script:olayKaydir = [Math]::Max(0, [Math]::Min($script:olayKaydir, [Math]::Max(0, $olaylar.Count - $bos)))
            $gor = @($olaylar | Select-Object -Skip $script:olayKaydir)   # gruplu satirlar ekrani doldurur (sayfa satirla sinirli)
            $bolumBas.Add(@{ Ad = 'SON OLAYLAR'; I = $L.Count })
            $L.Add((HLine $w ("$(Sec "📜 OLAYLAR ($($olaylar.Count))")$cFaint  motor makbuzları$(if ($script:olayKaydir -gt 0) { " · $($script:olayKaydir) olay yukarıda" }) · PgUp/PgDn kaydırır$RS") '├' '┤'))
            if ($w -ge 120) {
                $sagW = 44; $solW = $ic - $sagW - 2
                $sagT = BugunTablosu $a ($sagW - 1)
                $gorS = OlayListesi $gor ($solW - 1) $bos
                for ($i = 0; $i -lt [Math]::Max($gorS.Count, $sagT.Count); $i++) { $L.Add((Row (Cols $(if ($i -lt $gorS.Count) { $gorS[$i] } else { '' }) $(if ($i -lt $sagT.Count) { $sagT[$i] } else { '' }) $w $solW) $w)) }
            } else {
                foreach ($s in (OlayListesi $gor $ic $bos)) { $L.Add((Row $s $w)) }
                if (-not $gor.Count) { $L.Add((Row "${cFaint}bugün motor olayı yok$RS" $w)) }
            }
            $script:yeniOlay = 0
        }
    }
}

function BolumAlt($L, $a, [int]$h) {
    $w = $script:w
    $veriYas = ((Get-Date) - $script:sonHizli).TotalSeconds
    $msj = $(if ($script:mesaj -and ((Get-Date) - $script:mesajZaman).TotalSeconds -lt 5) { "$($script:mesajRenk)$(Cut (Protect-MerkezSatir $script:mesaj 200) ([Math]::Max(20, $w - 40)))$RS$cFrame  ─  $RS" } else { '' })
    $durumS = $(if ($script:cizimHata) { "$cFrame  ─  $RS$cErr✕ çizim hatası $($script:cizimHata)$RS" } elseif ($veriYas -gt $(if ($script:oncekiCanli) { 5 } else { 8 }) -and -not $Tek) { "$cFrame  ─  $RS$cWarn veri $([int]$veriYas) sn önce$RS" } else { '' })
    $tk = { param($k, $e) "$cAccent$BOLD$k$RS $cFaint$e$RS" }; $ay = "$cFrame  ·  $RS"
    $sec = $(if ($script:sec -ge 0 -and $script:sec -lt $script:secilebilir.Count) { $script:secilebilir[$script:sec] } else { $null })
    $par = @((& $tk 'Tab' 'sekme'))
    if ($script:sekmeAktif -eq 'Olaylar') { $par += (& $tk '↑↓' 'kaydır') } elseif ($script:secilebilir.Count) { $par += (& $tk '↑↓' 'seç') }
    if ($a.Teshis.Count -and $script:sekmeAktif -in @('Genel', 'Ajanlar')) { $par += (& $tk 'g' 'soruna git') }
    if ($script:sekmeAktif -in @('Genel', 'Ajanlar')) { $par += (& $tk 'f' $(if ($script:filtre -eq 'hepsi') { 'filtre' } else { "filtre: $($filtreAd[$script:filtre])" })) }
    if ($sec) {
        if ($sec.Tur -in @('lider', 'isci')) { $par += (& $tk '⏎' $(if ($script:acik -eq $sec.Anahtar) { 'kapat' } elseif ($sec.Tur -eq 'isci') { 'işçi paneli' } else { 'ayrıntı' })) }
        elseif ($sec.Tur -eq 'kosu') { $par += (& $tk '⏎' 'koşu panosu') } elseif ($sec.Tur -eq 'aktarim') { $par += (& $tk '⏎' 'tam metin') }
        if (Get-MerkezSatirKomut $sec) { $par += (& $tk 'c' 'kopyala') }
        if ($sec.Nesne -and $sec.Nesne.Kosu -or $sec.Tur -eq 'kosu') { $par += (& $tk 'p' 'koşu panosu') }
    }
    if ($script:sekmeAktif -in @('Genel', 'Ajanlar', 'Kosular')) {
        $gizli = @($a.Ajanlar | Where-Object { $_.Durum -in @('bosta', 'kapali', 'bitti') }).Count
        $par += (& $tk 'a' $(if ($script:sekmeAktif -eq 'Kosular') { $(if ($script:hepsi.Kosular) { 'biten koşuları gizle' } else { 'biten koşuları göster' }) } elseif ($script:hepsi[$script:sekmeAktif]) { 'boştakileri gizle' } else { "boştakileri göster (+$gizli)" }))
    }
    $par += (& $tk 'r' 'yenile'); $par += (& $tk '?' 'yardım'); $par += (& $tk 'q' 'çık')
    $tus = "$msj$($par -join $ay)$durumS"
    if ((VisLen $tus) -gt $w - 6) { $tus = "$msj$((@($par | Select-Object -First 3) + @((& $tk '?' 'yardım'), (& $tk 'q' 'çık'))) -join $ay)$durumS" }
    if ((VisLen $tus) -gt $w - 6) { $tus = Cut $tus ($w - 6) }
    return (HLine $w $tus '╰' '╯')
}

function CizSatirlar([int]$w, [int]$h) {
    # Bir karenin satirlari (yazmadan). Secilebilirler cizim sirasinda kaydedilir; secim anahtari korunur.
    $script:w = $w; $script:h = $h; $script:CizCanli = $false
    $a = $script:anlik; $L = New-Object System.Collections.Generic.List[string]
    $script:secilebilir = New-Object System.Collections.Generic.List[object]; $bolumBas = New-Object System.Collections.Generic.List[object]; $script:secSayac = @{}
    BolumBaslik $L $a
    if ($script:yardimAcik) { YardimIcerik $L } else { SekmeIcerik $L $bolumBas $a $h }
    if (-not $Tek -and -not $script:secAnahtar.ContainsKey($script:sekmeAktif) -and $script:secilebilir.Count) {
        $ilk = @($script:secilebilir | Where-Object { $_.Tur -eq 'teshis' -or ($_.Tur -in @('lider', 'isci') -and $_.Nesne.Durum -in @('engelli', 'inceleme')) } | Select-Object -First 1)
        if (-not $ilk.Count) { $ilk = @($script:secilebilir | Where-Object { $_.Tur -in @('lider', 'isci') -and $_.Nesne.Durum -eq 'calisiyor' } | Select-Object -First 1) }
        if ($ilk.Count) { $script:secAnahtar[$script:sekmeAktif] = [string]$ilk[0].Anahtar }
    }
    if ($script:soruBekle) { $script:soruBekle = $false; IlkSoruBul }
    $script:sec = -1; $sa = [string]$script:secAnahtar[$script:sekmeAktif]
    for ($i = 0; $i -lt $script:secilebilir.Count; $i++) { if ($script:secilebilir[$i].Anahtar -eq $sa) { $script:sec = $i; break } }
    $alt = BolumAlt $L $a $h
    $maks = $(if ($Tek -and $Yukseklik -le 0) { 100000 } else { [Math]::Max(5, $h - 1) })
    if ($L.Count -gt $maks - 1) {
        $kes = $maks - 2
        $selIdx = -1; for ($i = 1; $i -lt $L.Count; $i++) { if ($L[$i].Contains($bgSel)) { $selIdx = $i; break } }
        if ($selIdx -ge $kes - 1) {
            # secili satir gorunur kalacak kadar kaydir: baslik + "yukarida" satiri sabit, secimin altinda 2 satir pay
            $ust = [Math]::Min($L.Count - $kes + 1, $selIdx - $kes + 4)
            $yeni = New-Object System.Collections.Generic.List[string]; $yeni.Add($L[0]); $yeni.Add((Row "$cFaint▲ $ust satır yukarıda · ↑ ile dön$RS" $w))
            for ($i = 1 + $ust + 1; $i -lt $L.Count; $i++) { $yeni.Add($L[$i]) }
            $bb = New-Object System.Collections.Generic.List[object]; foreach ($b in $bolumBas) { if ($b.I -gt $ust + 1) { $bb.Add(@{ Ad = $b.Ad; I = $b.I - $ust }) } }
            $L = $yeni; $bolumBas = $bb
        }
        $gizli = $L.Count - $kes
        $gizliBolum = @(); for ($i = 0; $i -lt $bolumBas.Count; $i++) { $son = $(if ($i + 1 -lt $bolumBas.Count) { $bolumBas[$i + 1].I } else { $L.Count }); if ($son -gt $kes) { $gizliBolum += $(if ($bolumBas[$i].I -ge $kes) { $bolumBas[$i].Ad } else { "$($bolumBas[$i].Ad) (kısmen)" }) } }
        $L = [System.Collections.Generic.List[string]]@($L | Select-Object -First $kes)
        $L.Add((Row "$cWarn▼ $gizli satır sığmadı$RS$(if ($gizliBolum.Count) { "$cMuted · gizlenen: $($gizliBolum -join ', ')$RS" })$cFaint · sekmelerde tam liste (2 Ajanlar · 3 Koşular · 4 Olaylar)$RS" $w))
    }
    if (-not ($Tek -and $Yukseklik -le 0)) { while ($L.Count -lt $maks - 1) { $L.Add((Blank $w)) } }
    $L.Add($alt)
    return ,$L
}
function PencereBoyu { $w = 160; $h = 50; try { $w = $Host.UI.RawUI.WindowSize.Width; $h = $Host.UI.RawUI.WindowSize.Height } catch { }; if ($Genislik -gt 0) { $w = $Genislik }; if ($Yukseklik -gt 0) { $h = $Yukseklik }; $ham = $w; if ($w -lt 90) { $w = 90 }; return @($w, $h, $ham) }
function Ciz {
    $b = PencereBoyu
    if ($b[2] -lt 90 -and $b[2] -ge 10) {
        # dar pencere: cerceve kaymasin diye panel cizilmez; yalniz ne yapilacagi yazar
        $L = New-Object System.Collections.Generic.List[string]
        $L.Add((Cut "$cTitle$BOLD◆ Beyin merkez$RS" ($b[2] - 1))); $L.Add((Cut "${cWarn}pencere $($b[2]) sütun · en az 90 gerekli$RS" ($b[2] - 1))); $L.Add((Cut "${cFaint}pencereyi genişlet ya da yazıyı küçült (Ctrl -) · q çık$RS" ($b[2] - 1)))
        $script:lastFrame = Write-CizKare $L $b[2] $script:lastFrame; return
    }
    $L = CizSatirlar $b[0] $b[1]
    $script:lastFrame = Write-CizKare $L $b[0] $script:lastFrame
}
function CizimSonuc {
    try { Ciz; if ($script:cizimHata) { $script:cizimHata = 0; $script:lastFrame = '' }; $script:sonCizim = Get-Date }
    catch {
        $script:cizimHata++; $script:cizimMesaj = (Protect-MerkezSatir ([string]$_.Exception.Message) 120)
        try { $hh = $Host.UI.RawUI.WindowSize.Height; [Console]::Write("$ESC[$hh;1H$cErr▲ merkez $(if ($script:cizimHata -ge 5) { 'BOZUK' } else { 'SORUNLU' }) · $($script:cizimHata) kez çizilemedi · son başarılı $(Kisa ((Get-Date) - $script:sonCizim).TotalSeconds) önce · $($script:cizimMesaj)$RS$ESC[K") } catch { }
    }
}

# ---------- eylemler ----------
function Secili { if ($script:sec -ge 0 -and $script:sec -lt $script:secilebilir.Count) { return $script:secilebilir[$script:sec] }; return $null }
function SecimKaydir([int]$adim) {
    if ($script:sekmeAktif -eq 'Olaylar') { $script:olayKaydir = [Math]::Max(0, $script:olayKaydir + $adim); return }
    $n = $script:secilebilir.Count; if (-not $n) { return }
    $i = $(if ($script:sec -lt 0) { $(if ($adim -lt 0) { $n - 1 } else { 0 }) } else { [Math]::Max(0, [Math]::Min($n - 1, $script:sec + $adim)) })
    $script:sec = $i; $script:secAnahtar[$script:sekmeAktif] = [string]$script:secilebilir[$i].Anahtar
}
function SekmeGec([string]$s) { if ($s -and $s -ne $script:sekmeAktif) { $script:sekmeAktif = $s; if ($s -eq 'Olaylar') { $script:yeniOlay = 0 } } }
function KosuPanosu($oge) {
    $run = $(if ($oge -and $oge.Tur -eq 'kosu') { [string]$oge.Nesne.RunId } elseif ($oge -and $oge.Nesne.Kosu) { [string]$oge.Nesne.Kosu } else { '' })
    if (-not $run) { Mesaj 'seçili satır bir koşuya ait değil'; return }
    $sn = Open-BeyinTakimPanel -Paths $p -RunId $run -TaskIds @('pano')
    if ($sn.Ok) { Mesaj "koşu panosu açıldı ($run)" $cOk } else { Mesaj "açılamadı: $($sn.Neden)" $cErr }
}
function Kopyala($oge) {
    # Secili satirin GUVENLI komutu panoya; calistirilmaz, satir sonu eklenmez (yapistirinca kendiliginden calismaz).
    $k = Get-MerkezSatirKomut $oge
    if (-not $k) { Mesaj 'bu satırın güvenli komutu yok'; return }
    $ok = $false
    try { Set-Clipboard -Value $k.Komut -ErrorAction Stop; $ok = $true } catch { try { Add-Type -AssemblyName System.Windows.Forms; [Windows.Forms.Clipboard]::SetText($k.Komut); $ok = $true } catch { } }
    if ($ok) { Mesaj "✓ panoya kopyalandı: $($k.Komut) · $($k.Ipucu)" $cOk; $script:flas["kopya:$($oge.Anahtar)"] = @{ Imza = 'k'; Zaman = Get-Date } } else { Mesaj 'panoya yazılamadı' $cErr }
}
function Odak {
    $oge = Secili; if (-not $oge) { return }
    switch ($oge.Tur) {
        'isci' {
            if ($script:acik -ne $oge.Anahtar) {
                $sn = Open-BeyinTakimPanel -Paths $p -RunId $oge.Nesne.Kosu -TaskIds @([string]$oge.Nesne.Ad)
                if ($sn.Ok) { Mesaj "$($oge.Nesne.Ad) paneli açıldı" $cOk } else { Mesaj "panel açılamadı: $($sn.Neden)" $cErr }
            }
            $script:acik = $(if ($script:acik -eq $oge.Anahtar) { '' } else { $oge.Anahtar }); Tazele $false
        }
        'lider' { $script:acik = $(if ($script:acik -eq $oge.Anahtar) { '' } else { $oge.Anahtar }); Tazele $false }
        'kosu' { KosuPanosu $oge }
        'aktarim' { $id = [string]$oge.Nesne.id; $script:acikAktarim = $(if ($script:acikAktarim -eq $id) { '' } else { $id }) }
        default { Kopyala $oge }
    }
}
$script:soruBekle = $false
function IlkSoruna {
    # ilk teshis satirina ya da engelli/incelemedeki ajana atla. Baska sekmede/yardimdaysa once Genel'e gecer; arama
    # bir sonraki karede yapilir (eldeki secilebilir listesi onceki sekmenindir, "sorun yok" yaniltirdi).
    if ($script:sekmeAktif -notin @('Genel', 'Ajanlar') -or $script:yardimAcik) {
        if ($script:sekmeAktif -notin @('Genel', 'Ajanlar')) { SekmeGec 'Genel' }
        $script:yardimAcik = $false; $script:soruBekle = $true; return
    }
    IlkSoruBul
}
function IlkSoruBul {
    $h = @($script:secilebilir | Where-Object { $_.Tur -eq 'teshis' -or ($_.Tur -in @('lider', 'isci') -and $_.Nesne.Durum -in @('engelli', 'inceleme')) } | Select-Object -First 1)
    if ($h.Count) { $script:secAnahtar[$script:sekmeAktif] = [string]$h[0].Anahtar; Mesaj 'ilk soruna atlandı · c komutu kopyalar' $cAccent } else { Mesaj 'sorun yok' $cOk }
}
function TusIsle($kk) {
    # tus -> eylem; donus $true: cik
    switch ($kk.Key) {
        'UpArrow' { SecimKaydir -1; return $false } 'DownArrow' { SecimKaydir 1; return $false }
        'PageUp' { if ($script:sekmeAktif -eq 'Olaylar') { SecimKaydir -10 } else { SecimKaydir -10 }; return $false }
        'PageDown' { SecimKaydir 10; return $false }
        'Enter' { Odak; return $false }
        'Escape' { $script:acik = ''; $script:acikAktarim = ''; $script:yardimAcik = $false; return $false }
        'Tab' {
            $i = [Array]::IndexOf($sekmeler, $script:sekmeAktif); $yon = $(if ($kk.Modifiers -band [ConsoleModifiers]::Shift) { -1 } else { 1 })
            SekmeGec $sekmeler[($i + $yon + $sekmeler.Count) % $sekmeler.Count]; return $false
        }
    }
    switch -CaseSensitive ([string]$kk.KeyChar) {
        'q' { return $true }
        '1' { SekmeGec 'Genel' } '2' { SekmeGec 'Ajanlar' } '3' { SekmeGec 'Kosular' } '4' { SekmeGec 'Olaylar' }
        'j' { SecimKaydir 1 } 'k' { SecimKaydir -1 }
        'a' { $script:hepsi[$script:sekmeAktif] = -not $script:hepsi[$script:sekmeAktif] }
        'r' { foreach ($k in @('ts:Aktarimlar', 'ts:Kaynak', 'Maliyet', 'Bugun', 'ClaudeIsler', 'SonKosu')) { [void]$script:onb.Remove($k) }; $script:onb.KaynakTaze = $true; $script:bolumOnb = @{}; $script:lastFrame = ''; Tazele $true; Mesaj "yenilendi · $((Get-Date).ToString('HH:mm:ss')) · kaynak yeniden ölçüldü" $cOk }
        'c' { $o = Secili; if ($o) { Kopyala $o } else { Mesaj 'önce ↑↓ ile bir satır seç' } }
        'p' { KosuPanosu (Secili) }
        '?' { $script:yardimAcik = -not $script:yardimAcik }
        'f' { $sira = @('hepsi', 'sorun', 'claude', 'codex'); $script:filtre = $sira[([Array]::IndexOf($sira, $script:filtre) + 1) % 4]; Mesaj "filtre: $($filtreAd[$script:filtre])" $cAccent }
        'g' { IlkSoruna }
    }
    return $false
}

# ---------- kendini yenileme ----------
# Dosya basina damga. Yayin dosyalari SIRAYLA yazar: yeni bir beyin-ciz eski merkez ile karismasin diye yeniden yukleme
# yalniz izlenen dosyalarin HEPSI en az 3 sn'dir degismemisken ve degisen dosya ayristirilabiliyorsa yapilir. Yeni surec
# acik sekmeyi tasir (-Sekme).
$izlenen = @($PSCommandPath, $cizYol, (Join-Path $PSScriptRoot 'merkez-veri.ps1'), $balonYol, (Join-Path $Vault 'motor\hooks\lib.ps1'))
$damga = @{}; foreach ($f in $izlenen) { try { if (Test-Path -LiteralPath $f) { $damga[$f] = (Get-Item -LiteralPath $f).LastWriteTimeUtc } } catch { } }
$selfAt = Get-Date
function YeniSurumVar {
    if (((Get-Date) - $script:selfAt).TotalSeconds -lt 5) { return $false }
    $script:selfAt = Get-Date; $simdiU = (Get-Date).ToUniversalTime(); $degisen = $false
    foreach ($f in $izlenen) {
        try {
            if (-not (Test-Path -LiteralPath $f) -or -not $damga.ContainsKey($f)) { continue }
            $t = (Get-Item -LiteralPath $f).LastWriteTimeUtc
            if (($simdiU - $t).TotalSeconds -lt 3) { return $false }   # yayin suruyor: hepsi otursun
            if ($t -le $damga[$f]) { continue }
            $e = $null; [void][System.Management.Automation.Language.Parser]::ParseFile($f, [ref]$null, [ref]$e)
            if ($e -and $e.Count) { $damga[$f] = $t; continue }
            $degisen = $true
        } catch { }
    }
    return $degisen
}

# ---------- ana dongu ----------
$yenidenYukle = $false; $oscAcik = $false
try {
    Tazele $true
    if ($Olcum -gt 0) {
        $sw = New-Object Diagnostics.Stopwatch; $ms = New-Object System.Collections.Generic.List[double]
        $sekMs = [ordered]@{}
        foreach ($s in $sekmeler) { $script:sekmeAktif = $s; $t0 = $ms.Count; for ($i = 0; $i -lt $Olcum; $i++) { $script:tik++; $sw.Restart(); [void](CizSatirlar $(if ($Genislik) { $Genislik } else { 170 }) $(if ($Yukseklik) { $Yukseklik } else { 50 })); $ms.Add($sw.Elapsed.TotalMilliseconds) }; $sekMs[$s] = [Math]::Round((@($ms.GetRange($t0, $ms.Count - $t0) | Sort-Object))[[int][Math]::Floor($Olcum / 2)], 1) }
        "sekme medyanı (ms): $(@($sekMs.Keys | ForEach-Object { "$_ $($sekMs[$_])" }) -join ' · ')"
        $sir = @($ms | Sort-Object); "merkez çizim · $($ms.Count) kare · ortalama $([Math]::Round(($ms | Measure-Object -Average).Average, 1)) ms · p95 $([Math]::Round($sir[[int][Math]::Floor($sir.Count * 0.95)], 1)) ms · en çok $([Math]::Round($sir[$sir.Count - 1], 1)) ms · bölüm önbelleği $([int]$script:onbIsabet) isabet"
        exit 0
    }
    if ($Tek) {
        $script:hepsi.Genel = -not $Aktifler; $script:yardimAcik = [bool]$Yardim
        $liste = $(if ($Sekme -eq 'Hepsi') { $sekmeler } else { @($script:sekmeAktif) })
        foreach ($s in $liste) {
            $script:sekmeAktif = $s
            if ($Ayrinti) {
                [void](CizSatirlar 170 50)
                $ilk = @($script:secilebilir | Where-Object { $_.Tur -in @('lider', 'isci') })[0]
                if ($ilk) { $script:acik = $ilk.Anahtar; $script:secAnahtar[$s] = $ilk.Anahtar; Tazele $false }
            }
            $b = PencereBoyu; $L = CizSatirlar $b[0] $b[1]
            if ($Sekme -eq 'Hepsi') { [Console]::Write("=== SEKME $s ===`n") }
            foreach ($ln in $L) { [Console]::Write("$(Get-CizGuvenliSatir $ln)$RS`n") }
        }
        exit 0
    }
    if ($zKip -eq 'osc') { [Console]::Write((Get-CizOscAc)); $oscAcik = $true }
    Clear-Host
    $quit = $false
    while (-not $quit) {
        if (YeniSurumVar) {
            [Console]::Write("$ESC[H$ESC[J$cMuted merkez yenileniyor…$RS`n")
            $yenidenYukle = $true; $quit = $true; break
        }
        $simdi = Get-Date
        $sakin = -not $script:oncekiCanli
        if (($simdi - $script:sonTam).TotalSeconds -ge $(if ($sakin) { 15 } else { 6 })) { try { Tazele $true } catch { } }
        elseif (($simdi - $script:sonHizli).TotalSeconds -ge $(if ($sakin) { 5 } else { 1.5 })) { try { Tazele $false } catch { } }
        $script:tik++
        CizimSonuc
        try {
            while ([Console]::KeyAvailable) {
                $once = $script:sekmeAktif
                if (TusIsle ([Console]::ReadKey($true))) { $quit = $true }
                $script:lastFrame = ''
                if ($script:sekmeAktif -ne $once) { break }   # yeni sekme cizilmeden kalan tus eski secim listesine uygulanmasin
            }
        } catch { }
        # Hareket (calisan ajan, parlama, yumusak gecis, nabiz) varsa 120 ms; yoksa saat saniyede bir degistigi icin 1 sn. Bekleme
        # dilimlenir: tus gelince hemen cizilir (bostaki panel cekirdegin ~%35'ini yiyordu, performans denetimi 2026-10-16).
        $script:oncekiCanli = $script:CizCanli
        # uzun omurlu bosta panel: CLR 2. kusak ve buyuk nesne yigini kendiliginden geri verilmiyordu (canli izde ~5,5 MB/sa
        # dogrusal buyume; sanal saatli 3 saatlik testte panelin kendi durumu sinirli). Hareket yokken 10 dk'da bir tam toplama.
        if (-not $script:CizCanli -and ((Get-Date) - $script:sonGc).TotalMinutes -ge 10) {
            $script:sonGc = Get-Date
            try { [System.Runtime.GCSettings]::LargeObjectHeapCompactionMode = 'CompactOnce'; [GC]::Collect(); [GC]::WaitForPendingFinalizers(); [GC]::Collect() } catch { }
        }
        $hedefMs = $(if ($script:CizCanli) { 120 } else { 1000 }); $bekle = [Diagnostics.Stopwatch]::StartNew()
        while ($bekle.ElapsedMilliseconds -lt $hedefMs) { if ([Console]::KeyAvailable) { break }; Start-Sleep -Milliseconds 40 }
    }
} finally {
    try { [Console]::CursorVisible = $true } catch { }
    if ($oscAcik -and -not $yenidenYukle) { [Console]::Write((Get-CizOscKapat)) }   # yeniden yuklemede zemin yanip sonmesin
    if (-not $Tek -and $Olcum -le 0) { [Console]::Write("$ESC[0m$ESC[2J$ESC[H") } else { [Console]::Write("$ESC[0m") }
}
if ($yenidenYukle) {
    # baslatici altindaysa: sekmeyi birak, 75 ile cik (baslatici yeniden baslatir); baslaticisiz (eski cagri) ise eski yol
    if ($script:sekmeDosya) { try { [IO.File]::WriteAllText($script:sekmeDosya, $script:sekmeAktif) } catch { }; exit 75 }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath -Vault $Vault -Sekme $script:sekmeAktif; exit $LASTEXITCODE
}
