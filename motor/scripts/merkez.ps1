param(
    [string]$Vault = '',
    [switch]$Tek,          # bir kare ciz ve cik (test / ekran goruntusu icin)
    [int]$Genislik = 0,    # pencere genisligini ez (test: 90 / 120 / 170 / 210)
    [int]$Yukseklik = 0,
    [switch]$Aktifler,     # -Tek ile: Genel sekmesinde canli ekrandaki varsayilan gorunum (yalniz aktif kanatlar)
    [ValidateSet('Genel', 'Ajanlar', 'Kosular', 'Olaylar', 'Hepsi')][string]$Sekme = 'Genel',   # Hepsi: -Tek ile dort sekme ard arda
    [switch]$Ayrinti,      # -Tek ile: ilk secilebilir ajanin ayrintisi acik cizilir
    [ValidateSet('', 'osc', 'boya', 'kapali')][string]$Zemin = '',
    [int]$Olcum = 0        # N kare cizip ortalama / p95 suresini yazar (cizimi ekrana basmaz)
)
# merkez.ps1 - Beyin MERKEZ: tum sistemin tek izleme ekrani (Windows Terminal).
# Liderler (Claude/Codex oturumlari), takim kosulari ve iscileri, onaylar, pano, aktarimlar, kaynak, maliyet ve bugun.
# HICBIR SEY YAZMAZ; yalniz okur. Enter ayrinti/panel acar, c secili satirin guvenli komutunu PANOYA kopyalar (calistirmaz).
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
$CizGerekli = 1
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
$script:bildirimAcik = $(try { [string](Get-BeyinAyar 'BEYIN_BILDIRIM' (Get-BeyinAyarVars 'BEYIN_BILDIRIM')) -ne 'kapali' } catch { $true })
$script:gecmis = @{ Cal = New-Object System.Collections.Generic.List[double]; Commit = New-Object System.Collections.Generic.List[double] }

function Mesaj([string]$m, [string]$renk = $cWarn) { $script:mesaj = $m; $script:mesajRenk = $renk; $script:mesajZaman = Get-Date }
function Bildir([string]$baslik, [string]$metin) {
    if (-not $script:bildirimAcik -or $Tek -or $Olcum -gt 0) { return }
    try {
        [void][Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
        [void][Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime]
        $x = New-Object Windows.Data.Xml.Dom.XmlDocument
        $x.LoadXml("<toast><visual><binding template='ToastGeneric'><text>$([Security.SecurityElement]::Escape($baslik))</text><text>$([Security.SecurityElement]::Escape($metin))</text></binding></visual></toast>")
        $app = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'
        [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($app).Show([Windows.UI.Notifications.ToastNotification]::new($x))
    } catch { }
}
function OlaylariBildir($a) {
    # Yalniz SONRADAN olusan onay ve hata olaylari; kalkan olay yeniden kurulur. Isci bitti bildirimini koşu panosu verir.
    $o = [ordered]@{}
    foreach ($g in $a.Onaylar) { $o["onay:$($g.Satir)"] = "onay bekliyor: $($g.Satir)" }
    foreach ($t in $a.Teshis) { if ($t.Seviye -eq 'err') { $o["hata:$(TeshisAnahtar $t)"] = [string]$t.Metin } }
    if ($null -eq $script:olayGoruldu) { $script:olayGoruldu = @{}; foreach ($k in $o.Keys) { $script:olayGoruldu[$k] = $true }; return }
    foreach ($k in @($script:olayGoruldu.Keys)) { if (-not $o.Contains($k)) { $script:olayGoruldu.Remove($k) } }
    $yeni = @($o.Keys | Where-Object { -not $script:olayGoruldu.ContainsKey($_) })
    if (-not $yeni.Count) { return }
    foreach ($k in $yeni) { $script:olayGoruldu[$k] = $true }
    Bildir 'Beyin merkez' (@($yeni | ForEach-Object { $o[$_] }) -join ' · ')
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
    $olaylar = $(if ($a.Olaylar) { [object[]]$a.Olaylar.ToArray() } else { @() })
    if (-not $script:ilkYukleme) { $script:ilkYukleme = $s }
    foreach ($ol in $olaylar) { if (Set-CizFlas $script:flas (OlayAnahtar $ol) "$($ol.Adet)" $s ($y -and $ol.Zaman -ge $script:ilkYukleme.AddMinutes(-1))) { if ($script:sekmeAktif -ne 'Olaylar') { $script:yeniOlay++ } } }
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
    $script:sonHizli = Get-Date; if ($tam) { $script:sonTam = Get-Date }
    if ($tam) {
        # panel acik kaldikca biriken egilim (6 sn'de bir nokta, en cok 60 = 6 dk)
        try {
            $script:gecmis.Cal.Add([double]@($script:anlik.Ajanlar | Where-Object { $_.Durum -eq 'calisiyor' }).Count)
            if ($script:anlik.Kaynak -and $script:anlik.Kaynak.Ok) { $script:gecmis.Commit.Add([double]$script:anlik.Kaynak.CommitYuzde) }
            foreach ($k in @('Cal', 'Commit')) { while ($script:gecmis[$k].Count -gt 60) { $script:gecmis[$k].RemoveAt(0) } }
        } catch { }
    }
    try { FlasGuncelle $script:anlik } catch { }
    try { OlaylariBildir $script:anlik } catch { }
}

# ---------- secim ve vurgu ----------
function SecKayit([string]$Tur, [string]$Anahtar, $Nesne, [bool]$Yetim = $false) {
    # Cizim sirasinda secilebilir satiri kaydeder; secili ise $true doner (satir vurgulu cizilir).
    $n = [int]$script:secSayac[$Anahtar]; $script:secSayac[$Anahtar] = $n + 1; if ($n) { $Anahtar = "$Anahtar#$n" }
    $script:secilebilir.Add(@{ Tur = $Tur; Anahtar = $Anahtar; Nesne = $Nesne; Yetim = $Yetim })
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
function AjanSatir($ag, [int]$gen, [bool]$secili, [bool]$idGoster, [int]$ekGen = 19) {
    $d = [string]$ag.Durum; $renk = $durumRenk[$d]; if (-not $renk) { $renk = $cFaint }
    $kr = $kimlikRenk[[string]$ag.Ajan]; if (-not $kr) { $kr = $cMuted }
    $isaret = $(if ($secili) { "$cAccent$BOLD▸$RS" } else { ' ' })
    $uzun = ($d -eq 'calisiyor' -and $ag.Kaynak -eq 'uzun-arac')
    $nokta = $(switch ($d) {
            'calisiyor' { $(if ($uzun) { "$cWarn$($spin[[int][Math]::Floor($script:tik / 4) % $spin.Count])$RS" } else { "$renk$($spin[$script:tik % $spin.Count])$RS" }) }
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
    $tFaz = [Math]::Abs(([string]$ag.Ad).GetHashCode()) % 9; $ns = [double]$ag.NabizSn
    $tarS = $(if ($ns -ge 0 -and $ns -le 3) { Tarama 6 (2 * $script:tik + $tFaz) $rgbOk } elseif ($ns -ge 0 -and $ns -le 60) { Tarama 6 ([int][Math]::Floor($script:tik / 2) + $tFaz) $rgbOk } else { Tarama 6 $tFaz $rgbIz })   # 60 sn+ sessiz: donuk
    $durumYazi = $(if ($uzun) { "$cWarn◷ uzun işlem$RS" }   # 2+ dk tek arac: uzun komut ya da izin istemi
        elseif ($d -eq 'calisiyor') { "$renk$($durumAd[$d])$RS $tarS" } else { "$renk$($durumAd[$d])$RS" })
    $yasRenk = $(if ($ag.Bayat -or $uzun) { $cWarn } else { $cMuted })
    if (-not $ag.Bayat -and -not $uzun -and $d -eq 'calisiyor') { $yasRenk = $(if ($yasSn -ge 0 -and $yasSn -le 10) { $cOk } elseif ($yasSn -le 60) { $cText } else { $cMuted }) }   # taze nabiz yesil
    $yas = "$yasRenk$(Kisa $yasSn)$(if ($ag.Bayat) { ' !' })$RS"
    $ek = @(); if ($ag.Jeton) { $ek += "$(Fmt $ag.Jeton) jt" }; if ($ag.Dosya) { $ek += "$($ag.Dosya) dosya" }
    $ekS = $(if ($ek.Count) { "$cFaint$($ek -join ' · ')$RS" } else { '' })
    # dar satirda "N mesaj" sutunu gizlenir: yer en bilgilendirici kisma, balona kalir
    $sol = "$isaret $nokta $(Pad $ad 18) $(if ($gen -ge 110) { (Pad $rol 15) + ' ' })$(Pad $durumYazi 16) "
    $sag = " $(PadL $yas 11)$(if ($ekGen -gt 0) { ' ' + (PadL $ekS $ekGen) }) "
    $balonGen = $gen - (VisLen $sol) - (VisLen $sag)
    # Balon: calisan ajanda canli (soluk degil), digerlerinde "son yaptigi" olarak soluk; bostaki ajanin yarim kalmis
    # "düşünüyor" kaydi su an dusunuyormus gibi okunuyordu, gosterilmez.
    $bm = Get-CizGuvenliMetin ([string]$ag.Balon); if ($d -ne 'calisiyor' -and $bm -match '^… düşünüyor') { $bm = '' }
    $bm = $bm -replace '(?i)(/c/Users/|[A-Z]:[\\/]Users[\\/])[^/\\\s]+', '~'   # ev dizini ~
    $balon = $(if ($bm -and $balonGen -gt 6) { "$(if ($d -eq 'calisiyor') { $cText } else { $cFaint })$(Cut $bm $balonGen)$RS" } else { '' })
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
    $ozet = @(); if ($aktif.Count) { $ozet += "$cOk$($aktif.Count) aktif$RS" }; if ($sakin.Count) { $ozet += "$cFaint$($sakin.Count) boşta$RS" }
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
        $sayi = switch ($s) { 'Ajanlar' { [int]$a.Sayac['calisiyor'] } 'Kosular' { @($a.Kosular | Where-Object { -not $_.Bitmis }).Count } 'Olaylar' { $script:yeniOlay } default { 0 } }
        $sayiS = $(if ($sayi -gt 0) { " $(if ($s -eq 'Olaylar') { $cInfo } else { $cFaint })$sayi$RS" } else { '' })
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
    # canli noktasi: veri tazeyse SABIT yesil; bayatsa nabiz (alarm) - bostaki ekran kipirdamaz
    $nokta = $(if ($bayatVeri) { Nabiz $rgbWarn 0.3 } else { $cOk })
    $saat = "$cFrame─ $RS$nokta●$RS ${cFaint}canlı $cMuted$((Get-Date).ToString('HH:mm:ss'))$RS$sonOlS$cFrame ─╮$RS"
    $ad = "$cTitle$BOLD◆ Beyin merkez$RS"
    $cip = SekmeCipleri $a
    if ($w -ge 120 -and ((VisLen $ad) + (VisLen $cip) + (VisLen $saat) + 10) -le $w) {
        $L.Add((HLine ($w - (VisLen $saat)) "$ad$cFrame ─ $RS$cip" '╭' '') + $saat)
    } else {
        $L.Add((HLine ($w - (VisLen $saat)) "$ad$cFrame · $RS${cMuted}tüm sistem$RS" '╭' '') + $saat)
        $L.Add((Row $cip $w))
    }
}
function BolumRozet($L, $a) {
    $w = $script:w; $n = { param($k) $(if ($a.Sayac.ContainsKey($k)) { [int]$a.Sayac[$k] } else { 0 }) }
    $hata = @($a.Teshis | Where-Object { $_.Seviye -eq 'err' }).Count; $uyari = @($a.Teshis | Where-Object { $_.Seviye -eq 'warn' }).Count
    # yalniz HATA nabiz atar; uyari ve onay sabit (bekleyen is alarm degil)
    $rozet = $(if ($hata) { "$(BgKaris (CizKarisRgb $rgbErr $rgbZemin 0.70) (CizKarisRgb $rgbErr $rgbZemin 0.40) ((([Math]::Sin($script:tik * 0.7) + 1) / 2)))$cText$BOLD ✕ $hata HATA $RS" }
        elseif ($a.Onaylar.Count) { "$bgWait$BOLD ◐ $($a.Onaylar.Count) ONAY BEKLİYOR $RS" } elseif ($uyari) { "$bgIdle$BOLD ▲ $uyari UYARI $RS" } else { "$bgRun$BOLD ● SAĞLIKLI $RS" })
    $sayac = @()
    foreach ($d in @('calisiyor', 'inceleme', 'engelli', 'duraklatildi', 'bekliyor', 'bosta')) { $v = & $n $d; if ($v -gt 0) { $sayac += "$($durumRenk[$d])$BOLD$v$RS $cMuted$($durumAd[$d])$RS" } }
    if (-not $sayac.Count) { $sayac += "$cFaint etkin ajan yok$RS" }
    $etk = [double[]]@($a.Etkinlik); $etkN = [int]($etk | Measure-Object -Sum).Sum   # motor makbuzlari (kanca/komut), ajan mesaji degil
    $etkS = $(if ($etkN) { "${cFaint}motor son 2 sa$RS $(Spark $etk 12 $rgbAcc $rgbTeal) ${cFaint}$etkN olay$RS" } else { "${cFaint}motor son 2 sa sessiz$RS" })
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
        $bayat = $b.UsdZaman -and ((Get-Date) - [datetime]$b.UsdZaman).TotalHours -gt 2
        $par += "$cPeach$BOLD$(Usd ([double]$b.Usd))$RS$(if ($bayat) { "$cFaint $(([datetime]$b.UsdZaman).ToString('HH:mm')) itibarıyla$RS" })$(DunS $b.UsdDun 'usd')"
    }
    $par += "$cText$BOLD$([int]$b.Oturum)$RS ${cMuted}oturum$RS$(DunS $b.OturumDun)"
    $par += "$cText$BOLD$([int]$b.Ozet)$RS ${cMuted}özet$RS$(DunS $b.OzetDun)"
    $par += "$cText$BOLD$([int]$b.Commit)$RS ${cMuted}commit$RS$(DunS $b.CommitDun)"
    if ([int]$b.Yayin -or [int]$b.YayinDun) { $par += "$cText$BOLD$([int]$b.Yayin)$RS ${cMuted}yayın$RS" }
    if ([int]$b.Hata) { $par += "$cErr$BOLD$([int]$b.Hata)$RS ${cErr}hata$RS" }
    if ([int]$b.Engel) { $par += "$cWarn$BOLD$([int]$b.Engel)$RS ${cWarn}engel$RS" }
    $saatN = (Get-Date).Hour; $sl = [double[]]@($b.Saatlik[0..$saatN])
    $sagS = "${cFaint}dün: aynı saate kadar · saatlik$RS $(Spark $sl ([Math]::Min(24, $sl.Count)) $rgbAcc $rgbTeal)"
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
function BolumKartlar($L, $a) {
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
            "$(if ($script:gecmis.Cal.Count -ge 3) { Spark ([double[]]$script:gecmis.Cal.ToArray()) 12 $rgbTeal $rgbOk } else { "${cFaint}············$RS" }) ${cFaint}eğilim$RS$cMuted · $lid oturum$RS$(if ($isc) { "$cMuted · $RS$cTeal$isc işçi$RS" })") }
        @{ t = '🏃 KOŞULAR'; l = @("$cText$BOLD$($acikKosu.Count)$RS$cMuted açık$RS$(if ($a.Kosular.Count - $acikKosu.Count) { "$cFaint · $($a.Kosular.Count - $acikKosu.Count) biten$RS" })",
            $(if ($kIsci) { "$cOk$kIsci işçi çalışıyor$RS" } else { "${cFaint}çalışan işçi yok$RS" }),
            $(if ($sonBiten.Count) { "$cMuted$(Protect-MerkezSatir ([string]$sonBiten[0].RunId) 16)$RS $cFaint· $(KosuRozetMetin ([string]$sonBiten[0].Rozet))$RS" } else { "${cFaint}son 6 saatte biten yok$RS" })) }
        @{ t = $(if ($a.Onaylar.Count) { '🔔 ONAYLAR' } else { '🔔 ONAYLAR ✓' }); r = $(if ($a.Onaylar.Count) { $cWarn } else { '' }); l = @($(if ($a.Onaylar.Count) { "$cWarn$BOLD$($a.Onaylar.Count)$RS$cWarn senden bekleniyor$RS" } else { "$cOk✓ bekleyen yok$RS" }),
            $(if ($a.Onaylar.Count) { "$cText$BOLD$(Protect-MerkezSatir ([string]$a.Onaylar[0].Satir) 30)$RS" } else { "${cFaint}onay gelince burada çıkar$RS" }),
            $(if ($a.Onaylar.Count) { "${cFaint}sohbete tek başına bu satırı yaz$RS" } else { '' })) }
    )
    if ($a.Kaynak -and $a.Kaynak.Ok) {
        $cy = [int]$a.Kaynak.CommitYuzde; $cr = $(if ($cy -ge 85) { $cErr } elseif ($cy -ge 70) { $cWarn } else { $cOk })
        $oranC = Get-CizTween $script:tween 'commit' ($cy / 100.0)
        $kartlar += @{ t = "💾 KAYNAK$(if ($cy -ge 70 -and $cy -lt 85) { ' ▲' })"; r = $(if ($cy -ge 85) { $cErr } else { '' }); tr = $(if ($cy -ge 70) { $cWarn } else { '' }); l = @("${cMuted}bellek$RS $(EsikBar $oranC 10) $cr$BOLD%$cy$RS$(if ($a.Kaynak.CommitTavanGB) { "$cFaint · $([Math]::Round([double]$a.Kaynak.CommitGB))/$([Math]::Round([double]$a.Kaynak.CommitTavanGB)) GB$RS" })",
            "${cMuted}boş RAM$RS $cText$('{0:0.0}' -f [double]$a.Kaynak.BosRamGB) GB$RS$(if ($a.Kaynak.OnerilenAjan) { "$cFaint · $($a.Kaynak.OnerilenAjan) ajana yer var$RS" })",
            "${cMuted}eğilim$RS $(if ($script:gecmis.Commit.Count -ge 3) { Spark ([double[]]$script:gecmis.Commit.ToArray()) 10 $rgbOk $rgbErr 100 } else { "${cFaint}··········$RS" })$cFaint · $(if ([int]$a.Kaynak.BostaOturum) { $(if ($w -ge 170) { "$($a.Kaynak.BostaOturum) sessiz oturum" } else { "$($a.Kaynak.BostaOturum) sessiz" }) } else { 'sessiz oturum yok' })$RS") }
    }
    if ($a.Maliyet) {
        $mUsd = [double]$a.Maliyet.claudeUsd; $bUsd = [double]$a.Maliyet.buyukBaglamUsd
        $kartlar += @{ t = "💰 MALİYET · $([int]$a.Maliyet.gun) GÜN"; l = @("$cPeach${BOLD}Claude$RS $cText$BOLD$(Usd $mUsd)$RS$cFaint · API eşdeğeri$RS",
            "$cTeal${BOLD}Codex$RS $cText$(Fmt ([double]$a.Maliyet.codexJeton))$RS$cMuted jeton$RS",
            $(if ($bUsd -gt 0 -and $mUsd -gt 0) { "${cMuted}200K üstü oturum$RS $cWarn$(Usd $bUsd)$RS$cFaint · %$([int][Math]::Round(100 * $bUsd / $mUsd))$RS" } else { "${cFaint}beyin maliyet$RS" })) }
    }
    $enEski = ''; foreach ($hd in $a.Aktarimlar) { try { $t = [datetime]::Parse([string]$hd.ts); if (-not $enEski -or $t -lt $enEski.T) { $enEski = @{ T = $t; P = [string]$hd.toProject } } } catch { } }
    $kartlar += @{ t = '📋 PANO · AKTARIM'; l = @("$cText$BOLD$($a.Kartlar.Count)$RS$cMuted açık kart$RS$(if (@($a.Kartlar | Where-Object { $_.status -eq 'review' }).Count) { "$cWarn · $(@($a.Kartlar | Where-Object { $_.status -eq 'review' }).Count) incelemede$RS" })",
        "$cText$BOLD$($a.Aktarimlar.Count)$RS$cMuted açık aktarım$RS",
        $(if ($enEski) { "${cFaint}en eski $(KisaYas ((Get-Date) - $enEski.T).TotalSeconds)$(if ($enEski.P) { " · $(Protect-MerkezSatir $enEski.P 16)" })$RS" } else { "${cFaint}bekleyen aktarım yok$RS" })) }
    if ($w -ge 120) { foreach ($ln in (Cards $kartlar $ic 36)) { $L.Add((Row $ln $w)) } }   # 36: alti kart tek sirada metni kesiyordu
    else {
        # dar ekran: kart ozeti iki satir; deger durum rengiyle (onay sari, sifir yesil)
        $oz1 = @("${cMuted}onay$RS $(if ($a.Onaylar.Count) { "$cWarn$BOLD$($a.Onaylar.Count)$RS" } else { "$cOk" + '0' + "$RS" })")
        if ($a.Kaynak -and $a.Kaynak.Ok) { $cy = [int]$a.Kaynak.CommitYuzde; $oz1 += "${cMuted}bellek$RS $(if ($cy -ge 85) { $cErr } elseif ($cy -ge 70) { $cWarn } else { $cText })%$cy$RS" }
        if ($a.Maliyet) { $oz1 += "${cMuted}maliyet $([int]$a.Maliyet.gun) gün$RS $cText$(Usd ([double]$a.Maliyet.claudeUsd))$RS" }
        $oz2 = @("${cMuted}ajan$RS $cText$calisan/$toplam$RS", "${cMuted}koşu$RS $cText$($acikKosu.Count)$RS", "${cMuted}pano$RS $cText$($a.Kartlar.Count)$RS", "${cMuted}aktarım$RS $cText$($a.Aktarimlar.Count)$RS")
        $L.Add((Row ($oz1 -join "$cFrame  ·  $RS") $w)); $L.Add((Row ($oz2 -join "$cFrame  ·  $RS") $w))
    }
}
function BolumSirada($L, $bolumBas, $a) {
    $w = $script:w; $ic = $w - 4; $sr = $a.Sirada; if (-not $sr) { return }
    $srr = switch ([string]$sr.Renk) { 'ok' { $cOk } 'warn' { $cWarn } 'err' { $cErr } default { $cText } }
    # yalniz HATA serit nabiz atar; uyari sabit sari, yolunda sabit mavi
    $vur = $(if ([string]$sr.Renk -eq 'err') { Nabiz $rgbErr 0.8 } elseif ([string]$sr.Renk -eq 'warn') { $cWarn } else { $cAccent })
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
function KanatGruplari($a) {
    # Sira SABIT: once dikkat isteyen (engelli/inceleme), sonra uzun islem, sonra calisan, sonra ad.
    $kanatSira = { param($g) $ds = @($g.Group | ForEach-Object { [string]$_.Durum })
        if ($ds -contains 'engelli' -or $ds -contains 'inceleme') { 0 } elseif (@($g.Group | Where-Object { $_.Kaynak -eq 'uzun-arac' -and $_.Durum -eq 'calisiyor' }).Count) { 1 } elseif (@($ds | Where-Object { $_ -notin @('bosta', 'kapali', 'bitti') }).Count) { 2 } else { 3 } }
    return @($a.Ajanlar | Group-Object -Property { $_.Kanat } | Sort-Object -Property @{ Expression = { & $kanatSira $_ } }, @{ Expression = { ([string]$_.Name).ToLowerInvariant() } })
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
    Bolum $L $bolumBas 'KANATLAR' "🏢 KANATLAR ($($gruplar.Count))"
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
        $solW = $(if ($iki) { [int][Math]::Floor(($ic - 2) / 2) } else { $ic })
        $bloklar = KanatBloklari $gosterGrup $(if ($iki) { $solW - 1 } else { $solW }) $hepsi $true
        if ($iki) {
            $sol = New-Object System.Collections.Generic.List[string]; $sag = New-Object System.Collections.Generic.List[string]; $hs = 0; $hd = 0
            foreach ($b in $bloklar) { if ($hs -le $hd) { $sol.AddRange([string[]]$b); $hs += $b.Count } else { $sag.AddRange([string[]]$b); $hd += $b.Count } }
            for ($i = 0; $i -lt [Math]::Max($sol.Count, $sag.Count); $i++) { $L.Add((Row (Cols $(if ($i -lt $sol.Count) { $sol[$i] } else { '' }) $(if ($i -lt $sag.Count) { $sag[$i] } else { '' }) $w $solW) $w)) }
        } else { foreach ($b in $bloklar) { foreach ($s in $b) { $L.Add((Row $s $w)) } } }
    }
    if (-not $gruplar.Count) { $L.Add((Row "${cFaint}son 24 saatte etkin ajan yok$RS" $w)) }
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
    # adim cizgisi: tamam ✓ ━, kirik ✕, guncel ▸, bekleyen ○ ╌
    $ok = @($k.Adimlar); $cur = $(if ($null -ne $k.Guncel) { [int]$k.Guncel } else { -1 })
    if ($ok.Count -eq 6) {
        $seg = ''
        for ($i = 0; $i -lt 6; $i++) {
            $s = $(if ($ok[$i]) { "$cOk✓$RS $cMuted$($adlar[$i])$RS" } elseif ($k.Atlanan) { "$cFrame2– $($adlar[$i])$RS" } elseif ($i -eq $cur -and $k.Kirik) { "$cErr$BOLD✕ $($adlar[$i])$RS" } elseif ($i -eq $cur) { "$cAccent$BOLD▸ $($adlar[$i])$RS" } else { "$cFaint○ $($adlar[$i])$RS" })
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
function BolumKosular($L, $bolumBas, $a, [bool]$hepsi, [bool]$isciler) {
    $w = $script:w; if (-not $a.Kosular.Count) { if ($isciler) { Bolum $L $bolumBas 'KOŞULAR' '🏃 KOŞULAR (0)'; $L.Add((Row "${cFaint}son 6 saatte takım koşusu yok · beyin takim plan$RS" $w)); $L.Add((Blank $w)) }; return }
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
        $hp = Protect-MerkezSatir ([string]$hd.toProject) 30; $hpS = $(if ($hp) { "$(if ($yasSn -gt 3 * 86400) { $cWarn } else { $cMuted })$hp$RS" } else { "${cFrame2}her yer$RS" })
        $eskiMi = $yasSn -gt 3 * 86400; $yasR = $(if ($eskiMi) { "$cWarn$BOLD" } elseif ($yasSn -ge 86400) { $cText } else { $cMuted })
        $hid = [string]$hd.id; $kid = Protect-MerkezSatir $hid.Substring([Math]::Max(0, $hid.Length - 4)) 4
        $an = "aktarim:$hid"; $sc = SecKayit 'aktarim' $an $hd
        $aL.Add((Vurgu "$(Pad $yon 14) $cFaint$kid$RS $(Pad $hpS 13) $(PadL "$yasR$(KisaYas $yasSn)$RS" 7)  $(KonuAyrinti (Protect-MerkezSatir ([string]$hd.question) 160) $(if ($eskiMi) { $cWarn } else { $cText }))" $sagGen $sc))
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
function OlayListesi($olaylar, [int]$gen, [int]$adet) {
    # olay satirlari; ardisik iki olay arasinda 1 saatten uzun bosluk ya da gun degisimi soluk ayiracla
    $R = New-Object System.Collections.Generic.List[string]; $onceki = $null
    foreach ($ol in $olaylar) {
        if ($R.Count -ge $adet) { break }
        if ($onceki -and (($onceki.Zaman - $ol.Zaman).TotalMinutes -gt 60 -or $onceki.Zaman.Date -ne $ol.Zaman.Date) -and $R.Count -lt $adet - 1) {
            $R.Add("$cFrame2┄┄ $(if ($onceki.Zaman.Date -ne $ol.Zaman.Date) { $ol.Zaman.ToString('d MMM', [Globalization.CultureInfo]::GetCultureInfo('tr-TR')) } else { "$(Kisa ($onceki.Zaman - $ol.Zaman).TotalSeconds) sessiz" }) ┄┄$RS")
        }
        $R.Add((OlaySatiri $ol $gen)); $onceki = $ol
    }
    return ,$R
}
function BolumOlaylar($L, $bolumBas, $a, [int]$adet) {
    $w = $script:w; $ic = $w - 4
    $olaylar = $(if ($a.Olaylar) { [object[]]$a.Olaylar.ToArray() } else { @() })   # @() generic List uzerinde PS 5.1de firlatir
    if (-not $olaylar.Count -or $adet -lt 3) { return }
    $bolumBas.Add(@{ Ad = 'SON OLAYLAR'; I = $L.Count })
    $L.Add((HLine $w ("$(Sec '📜 SON OLAYLAR')$cFaint  motor makbuzları · 4 Olaylar$RS") '├' '┤'))
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
    $saatN = (Get-Date).Hour
    $T.Add("${cFaint}saatlik etkinlik (00 → $('{0:00}' -f $saatN))$RS")
    $T.Add((Spark ([double[]]@($b.Saatlik[0..$saatN])) ([Math]::Min($gen - 2, $saatN + 1)) $rgbAcc $rgbTeal))
    if ($b.UsdZaman) { $T.Add("${cFaint}maliyet $(([datetime]$b.UsdZaman).ToString('HH:mm')) itibarıyla (tam gün dünle)$RS"); $T.Add("${cFaint}tazelemek: $RS$cAccent${BOLD}beyin maliyet$RS") }
    if ($b.CommitDepo -and $b.CommitDepo.Count) { $T.Add(''); $T.Add("${cFaint}commit · depo$RS"); foreach ($k in @($b.CommitDepo.Keys | Sort-Object { -$b.CommitDepo[$_] } | Select-Object -First 5)) { $T.Add("  $cText$(Pad (Protect-MerkezSatir $k 24) 26)$RS$cMuted$($b.CommitDepo[$k])$RS") } }
    return $T
}

function SekmeIcerik($L, $bolumBas, $a, [int]$h) {
    $w = $script:w; $ic = $w - 4
    switch ($script:sekmeAktif) {
        'Genel' {
            BolumRozet $L $a; BolumBugun $L $a; $L.Add((Blank $w))
            BolumKartlar $L $a; $L.Add((Blank $w))
            BolumSirada $L $bolumBas $a; BolumOnay $L $bolumBas $a
            BolumTeshis $L $bolumBas $a $(if ($w -ge 170) { 5 } else { 3 })
            BolumKanatlar $L $bolumBas $a $script:hepsi.Genel $false
            BolumKosular $L $bolumBas $a $false $false
            BolumPanoAktarim $L $bolumBas $a $(if ($w -ge 170) { 6 } else { 4 })
            # SON OLAYLAR ekranda kalan bos yuksekligi doldurur; hicbir bolumu disari itmez
            $bos = $(if ($Tek -and $Yukseklik -le 0) { 10 } else { ($h - 1) - $L.Count - 1 - 1 })
            BolumOlaylar $L $bolumBas $a ([Math]::Min(14, $bos))
        }
        'Ajanlar' {
            BolumRozet $L $a; $L.Add((Blank $w))
            BolumKanatlar $L $bolumBas $a $script:hepsi.Ajanlar ($w -ge 170)
            BolumTeshis $L $bolumBas $a 5
        }
        'Kosular' {
            BolumRozet $L $a; $L.Add((Blank $w))
            BolumOnay $L $bolumBas $a
            BolumKosular $L $bolumBas $a $script:hepsi.Kosular $true
        }
        'Olaylar' {
            BolumRozet $L $a; BolumBugun $L $a; $L.Add((Blank $w))
            $olaylar = $(if ($a.Olaylar) { [object[]]$a.Olaylar.ToArray() } else { @() })
            $bos = $(if ($Tek -and $Yukseklik -le 0) { 24 } else { [Math]::Max(3, ($h - 1) - $L.Count - 1 - 1) })
            $script:olayKaydir = [Math]::Max(0, [Math]::Min($script:olayKaydir, [Math]::Max(0, $olaylar.Count - $bos)))
            $gor = @($olaylar | Select-Object -Skip $script:olayKaydir -First $bos)
            $bolumBas.Add(@{ Ad = 'SON OLAYLAR'; I = $L.Count })
            $L.Add((HLine $w ("$(Sec "📜 OLAYLAR ($($olaylar.Count))")$cFaint  motor makbuzları$(if ($olaylar.Count -gt $bos) { " · $($script:olayKaydir + 1)-$($script:olayKaydir + $gor.Count) · PgUp/PgDn" })$RS") '├' '┤'))
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
    $durumS = $(if ($script:cizimHata) { "$cFrame  ─  $RS$cErr✕ çizim hatası $($script:cizimHata)$RS" } elseif ($veriYas -gt 5 -and -not $Tek) { "$cFrame  ─  $RS$cWarn veri $([int]$veriYas) sn önce$RS" } else { '' })
    $tk = { param($k, $e) "$cAccent$BOLD$k$RS $cFaint$e$RS" }; $ay = "$cFrame  ·  $RS"
    $sec = $(if ($script:sec -ge 0 -and $script:sec -lt $script:secilebilir.Count) { $script:secilebilir[$script:sec] } else { $null })
    $par = @((& $tk 'Tab' 'sekme'))
    if ($script:sekmeAktif -eq 'Olaylar') { $par += (& $tk '↑↓' 'kaydır') } else { $par += (& $tk '↑↓' 'seç') }
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
    $par += (& $tk 'r' 'tazele'); $par += (& $tk 'q' 'çık')
    $tus = "$msj$($par -join $ay)$durumS"
    if ((VisLen $tus) -gt $w - 6) { $tus = "$msj$((@($par | Select-Object -First 3) + @(& $tk 'q' 'çık')) -join $ay)$durumS" }
    if ((VisLen $tus) -gt $w - 6) { $tus = Cut $tus ($w - 6) }
    return (HLine $w $tus '╰' '╯')
}

function CizSatirlar([int]$w, [int]$h) {
    # Bir karenin satirlari (yazmadan). Secilebilirler cizim sirasinda kaydedilir; secim anahtari korunur.
    $script:w = $w
    $a = $script:anlik; $L = New-Object System.Collections.Generic.List[string]
    $script:secilebilir = New-Object System.Collections.Generic.List[object]; $bolumBas = New-Object System.Collections.Generic.List[object]; $script:secSayac = @{}
    BolumBaslik $L $a
    SekmeIcerik $L $bolumBas $a $h
    $script:sec = -1; $sa = [string]$script:secAnahtar[$script:sekmeAktif]
    for ($i = 0; $i -lt $script:secilebilir.Count; $i++) { if ($script:secilebilir[$i].Anahtar -eq $sa) { $script:sec = $i; break } }
    $alt = BolumAlt $L $a $h
    $maks = $(if ($Tek -and $Yukseklik -le 0) { 100000 } else { [Math]::Max(5, $h - 1) })
    if ($L.Count -gt $maks - 1) {
        $kes = $maks - 2; $gizli = $L.Count - $kes
        $gizliBolum = @($bolumBas | Where-Object { $_.I -ge $kes } | ForEach-Object { $_.Ad })
        $L = [System.Collections.Generic.List[string]]@($L | Select-Object -First $kes)
        $L.Add((Row "$cWarn▼ $gizli satır sığmadı$RS$(if ($gizliBolum.Count) { "$cMuted · gizlenen: $($gizliBolum -join ', ')$RS" })$cFaint · sekmelerde tam liste (2 Ajanlar · 3 Koşular · 4 Olaylar)$RS" $w))
    }
    if (-not ($Tek -and $Yukseklik -le 0)) { while ($L.Count -lt $maks - 1) { $L.Add((Blank $w)) } }
    $L.Add($alt)
    return ,$L
}
function PencereBoyu { $w = 160; $h = 50; try { $w = $Host.UI.RawUI.WindowSize.Width; $h = $Host.UI.RawUI.WindowSize.Height } catch { }; if ($Genislik -gt 0) { $w = $Genislik }; if ($Yukseklik -gt 0) { $h = $Yukseklik }; if ($w -lt 90) { $w = 90 }; return @($w, $h) }
function Ciz {
    $b = PencereBoyu; $L = CizSatirlar $b[0] $b[1]
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
    if ($ok) { Mesaj "✓ panoya kopyalandı: $(Cut $k.Komut 48) · $($k.Ipucu)" $cOk; $script:flas["kopya:$($oge.Anahtar)"] = @{ Imza = 'k'; Zaman = Get-Date } } else { Mesaj 'panoya yazılamadı' $cErr }
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
function TusIsle($kk) {
    # tus -> eylem; donus $true: cik
    switch ($kk.Key) {
        'UpArrow' { SecimKaydir -1; return $false } 'DownArrow' { SecimKaydir 1; return $false }
        'PageUp' { if ($script:sekmeAktif -eq 'Olaylar') { SecimKaydir -10 } else { SecimKaydir -10 }; return $false }
        'PageDown' { SecimKaydir 10; return $false }
        'Enter' { Odak; return $false }
        'Escape' { $script:acik = ''; $script:acikAktarim = ''; return $false }
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
        'r' { [void]$script:onb.Remove('ts:Aktarimlar'); [void]$script:onb.Remove('ts:Kaynak'); Tazele $true; Mesaj 'tazelendi' $cOk }
        'c' { $o = Secili; if ($o) { Kopyala $o } else { Mesaj 'önce ↑↓ ile bir satır seç' } }
        'p' { KosuPanosu (Secili) }
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
        foreach ($s in $sekmeler) { $script:sekmeAktif = $s; for ($i = 0; $i -lt $Olcum; $i++) { $script:tik++; $sw.Restart(); [void](CizSatirlar $(if ($Genislik) { $Genislik } else { 170 }) $(if ($Yukseklik) { $Yukseklik } else { 50 })); $ms.Add($sw.Elapsed.TotalMilliseconds) } }
        $sir = @($ms | Sort-Object); "merkez çizim · $($ms.Count) kare · ortalama $([Math]::Round(($ms | Measure-Object -Average).Average, 1)) ms · p95 $([Math]::Round($sir[[int][Math]::Floor($sir.Count * 0.95)], 1)) ms · en çok $([Math]::Round($sir[$sir.Count - 1], 1)) ms"
        exit 0
    }
    if ($Tek) {
        $script:hepsi.Genel = -not $Aktifler
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
            foreach ($ln in $L) { [Console]::Write("$ln$RS`n") }
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
        if (($simdi - $script:sonTam).TotalSeconds -ge 6) { try { Tazele $true } catch { } }
        elseif (($simdi - $script:sonHizli).TotalSeconds -ge 1.5) { try { Tazele $false } catch { } }
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
        Start-Sleep -Milliseconds 120   # tarama/spinner akici; kare degismediyse yazilmaz
    }
} finally {
    try { [Console]::CursorVisible = $true } catch { }
    if ($oscAcik -and -not $yenidenYukle) { [Console]::Write((Get-CizOscKapat)) }   # yeniden yuklemede zemin yanip sonmesin
    if (-not $Tek -and $Olcum -le 0) { [Console]::Write("$ESC[0m$ESC[2J$ESC[H") } else { [Console]::Write("$ESC[0m") }
}
if ($yenidenYukle) { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath -Vault $Vault -Sekme $script:sekmeAktif; exit $LASTEXITCODE }
