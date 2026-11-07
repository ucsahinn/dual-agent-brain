# merkez-gelen.ps1 - Beyin MERKEZ: "5 İşler" gelen kutusu, eylem tuslari, onay penceresi, is kuyrugu, oto-duzeltme (2026-10-31).
# merkez.ps1 dot-source eder (cizim yardimcilari, SecKayit, Vurgu, Mesaj, Bildir orada). Eylem modeli: merkez-eylem.ps1.
#
# Akis: satir sec (↑↓) ya da isaretle (Bosluk; * gorunen ayni turdekilerin hepsi, u temizle) -> eylem tusu (o n x d t O) ->
#   insan onayi ya da tehlikeli adim varsa ONAY PENCERESI (hedefler listelenir; Y ya da ekrandaki kod) -> onaylar bu surecte
#   yazilir, komutlar SIRAYLA kuyrukta kosar (gizli ya da yeni sekmede) -> sonuc SON İŞLEMLER satirinda ve mesaj seridinde.
# Oto-duzeltme (z): yalniz Oto isaretli teshis/kosu adimlari (maliyet taramasi, topla), anahtar basina 30 dk'da bir.
# Onay ve tehlikeli adim ASLA oto calismaz.

$script:isaret = [ordered]@{}      # Anahtar -> oge (coklu secim)
$script:modal = $null              # @{ Eylem; Hedef; Kod; Giris; Insan }
$script:kuyruk = New-Object System.Collections.Generic.List[object]   # @{ Argv; Gorunur; Oto }
$script:aktifIs = $null            # @{ Id; Argv; Basladi; Gorunur }
$script:izlenenIs = @{}            # Id -> bildirildi mi
$script:sonIsler = @()
$script:sonIsOku = [datetime]::MinValue
$script:otoAcik = $(try { [string](Get-BeyinAyar 'BEYIN_MERKEZ_OTO' 'kapali') -eq 'acik' } catch { $false })
$script:otoSon = @{}
$script:otoDurum = @{}             # argv -> @{ Hata; Sonraki; Vazgecti } (geri cekilme 1-2-4..30 dk, 3 hatada vazgec)
$script:sessizBitis = $null        # sessiz mod: ses ve bildirim susar; liste ve onay sayaci ASLA gizlenmez
$script:sessizKip = 'kapali'
$script:ModalSure = 60             # onay penceresi 60 sn icinde onaylanmazsa ret sayilir
$script:acikKart = ''
$script:onayBicim = Get-MerkezOnayBicimi
$script:etkilesimli = $(try { -not [Console]::IsInputRedirected } catch { $false })

function OgeEylemleri($oge) { if (-not $oge) { return @() }; return @(Get-MerkezEylemler $oge $script:anlik) }
function EylemIpucu($oge, [int]$maks = 3) {
    # satir sonundaki tus ipuclari: "o onayla ve kapat · x durdur"
    $e = @(OgeEylemleri $oge | Select-Object -First $maks)
    if (-not $e.Count) { return '' }
    return (@($e | ForEach-Object { "$cAccent$BOLD$($_.Tus)$RS $cFaint$(Protect-MerkezSatir ([string]$_.Ad) 28)$RS" }) -join "$cFrame · $RS")
}
function IsaretKutusu([string]$an) { if ($script:isaret.Contains($an)) { return "$cAccent$BOLD■$RS" }; return "$cFrame□$RS" }

# ---------- gelen kutusu sekmesi ----------
function GelenSayisi($a) {
    if (-not $a) { return 0 }
    $n = $a.Onaylar.Count
    $n += @($a.Teshis | Where-Object { $_.Seviye -in @('err', 'warn') -and (Get-MerkezTeshisEylem $_) }).Count
    return $n
}
function KartAyrinti($kt, [int]$gen) {
    # incelemedeki kartin kaniti: onaydan once ne teslim edildigini gormek icin (yazma kapsami, son kanitlar, rapor)
    $L = New-Object System.Collections.Generic.List[string]
    $ws = $(if ($kt.writeScope) { "$(Protect-MerkezSatir ([string]$kt.writeScope.repo) 24) · $(Protect-MerkezSatir ((@($kt.writeScope.paths) | Select-Object -First 3) -join ', ') 120)" } else { '—' })
    $L.Add("    $cAccent│$RS ${cFaint}yazma kapsamı$RS $cText$ws$RS")
    if ($kt.reports) { $L.Add("    $cAccent│$RS ${cFaint}rapor$RS $cText$(Protect-MerkezSatir ((@($kt.reports) | Select-Object -First 3) -join ', ') 120)$RS") }
    foreach ($ev in @($kt.evidence | Select-Object -Last 2)) {
        $t = Protect-MerkezSatir ([string]$ev.text) 700
        $ilk = $true
        foreach ($s in (Sar $t ($gen - 8) 4)) { $L.Add("    $cAccent│$RS $(if ($ilk) { "${cFaint}kanıt$RS " } else { '      ' })$cMuted$s$RS"); $ilk = $false }
    }
    if (-not @($kt.evidence).Count) { $L.Add("    $cAccent│$RS ${cWarn}kanıt kaydı yok · onaylamadan önce bak: beyin pano show --task $(Protect-MerkezSatir ([string]$kt.id) 40)$RS") }
    $L.Add("    $cAccent│$RS ${cFaint}o: onay yazılır ve kart kapanır · doğrulayan olarak sen kaydedilirsin (--verified-by user)$RS")
    return ,$L
}
function GelenSatir($L, [string]$tur, [string]$an, $nesne, [string]$govde, [bool]$yetim = $false) {
    $w = $script:w; $ic = $w - 4
    $oge = @{ Tur = $tur; Anahtar = $an; Nesne = $nesne; Yetim = $yetim }
    $sc = SecKayit $tur $an $nesne $yetim
    $ip = EylemIpucu $oge
    $sol = "$(IsaretKutusu $an) $govde"
    $ipG = VisLen $ip
    $satir = $(if ($ip -and (VisLen $sol) + $ipG + 4 -le $ic) { (Pad $sol ($ic - $ipG - 1)) + ' ' + $ip } else { $sol })
    $L.Add((Row (Vurgu $satir $ic $sc $an) $w))
    return $sc
}
function BolumGelen($L, $bolumBas, $a) {
    $w = $script:w; $ic = $w - 4
    # ust serit: ne kadar is bekliyor, oto durumu, onay bicimi
    $onayS = switch ($script:onayBicim) { 'kod' { 'onay: ekrandaki kod' } 'kapali' { 'onay: merkezden kapalı' } default { 'onay: Y tuşu' } }
    $otoS = $(if ($script:otoAcik) { "$cOk${BOLD}oto-düzelt açık$RS" } else { "${cFaint}oto-düzelt kapalı$RS" })
    $isS = $(if ($script:aktifIs) { "$cInfo⠿ çalışıyor: beyin $(Protect-MerkezSatir (@($script:aktifIs.Argv) -join ' ') 50)$RS" } elseif ($script:kuyruk.Count) { "$cInfo$($script:kuyruk.Count) iş sırada$RS" } else { "${cFaint}kuyruk boş$RS" })
    $sesS = $(if (SessizAktif) { "$cMauve${BOLD}sessiz$(if ($script:sessizKip -eq '30dk') { ' ' + [int]($script:sessizBitis - (Get-Date)).TotalMinutes + ' dk' })$RS" } else { '' })
    $L.Add((Row "$otoS$cFrame  ·  $RS$cFaint$onayS$RS$cFrame  ·  $RS$isS$(if ($sesS) { "$cFrame  ·  $RS$sesS" })$(if ($script:isaret.Count) { "$cFrame  ·  $RS$cAccent$BOLD$($script:isaret.Count) işaretli$RS" })" $w))
    foreach ($vz in @($script:otoDurum.Keys | Where-Object { $script:otoDurum[$_].Vazgecti })) { $L.Add((Row "$cErr✕$RS ${cText}oto-düzelt vazgeçti (3 hata): beyin $(Protect-MerkezSatir ($vz -replace '^argv:', '') 60)$RS ${cFaint}· elle bak · z kapat-aç sıfırlar$RS" $w)) }
    if (-not $script:etkilesimli) { $L.Add((Row "${cWarn}bu pencere etkileşimsiz: eylemler kapalı (yalnız izleme)$RS" $w)) }
    $L.Add((Blank $w))

    # 1) ONAY BEKLEYENLER: kosu kapilari + incelemedeki kartlar
    $kapilar = @($a.Onaylar | Where-Object { [string]$_.Satir -match '^(baslat|birlestir) ' })
    $inc = @($a.Kartlar | Where-Object { [string]$_.status -eq 'review' })
    Bolum $L $bolumBas 'ONAY BEKLİYOR' "🔔 ONAY BEKLİYOR ($($kapilar.Count + $inc.Count))" $(if ($kapilar.Count + $inc.Count) { $cWarn } else { $cFaint })
    foreach ($g in $kapilar) { [void](GelenSatir $L 'onay' "onay:$($g.Satir)" $g "$cWarn$BOLD◐ $(Protect-MerkezSatir $g.Satir 40)$RS  $cMuted$(Protect-MerkezSatir $g.Neden 60)$RS") }
    foreach ($kt in $inc) {
        $bas = Protect-MerkezSatir ([string]$kt.title) 70; $yol = $(if ($kt.writeScope -and @($kt.writeScope.paths).Count) { ([string]@($kt.writeScope.paths)[0]) -replace '^.*[\\/]', '' } else { '' })
        if ($bas -match '^Team run (R[\w-]+): (.+)$') { $bas = "…$($Matches[1].Substring([Math]::Max(0, $Matches[1].Length - 4))) · $(RolTr $Matches[2])" }
        $kanit = @($kt.evidence).Count
        $an = "kart:$($kt.id)"
        $sc = GelenSatir $L 'kart' $an $kt "$cWarn●$RS $cText$(Pad (Protect-MerkezSatir ([string]$kt.id) 24) 24)$RS $cMuted$bas$(if ($yol) { " · $(Protect-MerkezSatir $yol 36)" })$RS $(if ($kanit) { "$cOk$kanit kanıt$RS" } else { "${cWarn}kanıt yok$RS" })"
        if ($script:acikKart -eq [string]$kt.id) { foreach ($s in (KartAyrinti $kt $ic)) { $L.Add((Row $s $w)) } }
    }
    if (-not ($kapilar.Count + $inc.Count)) { $L.Add((Row "$cOk✓$RS ${cFaint}onay bekleyen yok$RS" $w)) }
    elseif ($inc.Count -gt 1) { $L.Add((Row "${cFaint}  Bosluk işaretle · * hepsini işaretle · o hepsini tek pencerede onayla · Enter kanıtı göster$RS" $w)) }
    $L.Add((Blank $w))

    # 1b) TAKILI: hata seviyesindeki teshisler (is akisini durduran) onaylarin hemen altinda
    $takili = @($a.Teshis | Where-Object { $_.Seviye -eq 'err' })
    if ($takili.Count) {
        Bolum $L $bolumBas 'TAKILI' "⛔ TAKILI ($($takili.Count))" $cErr
        foreach ($t in $takili) { TeshisSatiri $L $t }
        $L.Add((Blank $w))
    }

    # 2) SEF SIRASI: kosularin calistirilabilir sonraki adimi
    $kos = @($a.Kosular | Where-Object { -not $_.Bitmis -and [string]$_.Durum -notin @('merged', 'aborted', 'failed') })
    Bolum $L $bolumBas 'KOŞULAR' "🏃 KOŞULAR · SIRADAKİ ADIM ($($kos.Count))" $cAccent
    foreach ($k in $kos) {
        $snr = switch ([string]$k.Sonraki.Renk) { 'ok' { $cOk } 'warn' { $cWarn } 'err' { $cErr } default { $cMuted } }
        [void](GelenSatir $L 'kosu' "kosu:$($k.RunId)" $k "$cText$(Pad (Protect-MerkezSatir ([string]$k.RunId) 16) 16)$RS $cFaint$(Pad (Protect-MerkezSatir ([string]$k.Repo) 14) 14)$RS $cFaint$($k.Biten)/$($k.Isci)$RS  $snr$(Protect-MerkezSatir ([string]$k.Sonraki.Metin) 70)$RS")
    }
    if (-not $kos.Count) { $L.Add((Row "$cOk✓$RS ${cFaint}açık koşu yok$RS" $w)) }
    $L.Add((Blank $w))

    # 3) TESHIS: neden -> etki -> duzeltme
    $tes = @(@($a.Teshis | Where-Object { $_.Seviye -eq 'warn' }) + @($a.Teshis | Where-Object { $_.Seviye -notin @('err', 'warn') }))
    Bolum $L $bolumBas 'TEŞHİS' "🩺 TEŞHİS · DÜZELT ($($tes.Count))" $(if ($tes.Count) { $cWarn } else { $cFaint })
    foreach ($t in $tes) { TeshisSatiri $L $t }
    if (-not $tes.Count) { $L.Add((Row "$cOk✓$RS ${cFaint}$(if ($takili.Count) { 'uyarı yok (hatalar yukarıda, TAKILI)' } else { 'teşhis temiz' })$RS" $w)) }
    $L.Add((Blank $w))

    # 4) AKTARIMLAR
    $akt = @($a.Aktarimlar | Sort-Object -Property @{ Expression = { [string]$_.ts } } | Select-Object -First 12)
    Bolum $L $bolumBas 'AKTARIMLAR' "📨 AKTARIMLAR ($(@($a.Aktarimlar).Count) açık)" $cAccent
    foreach ($hd in $akt) {
        $yasSn = -1; try { $yasSn = ((Get-Date) - [datetime]::Parse([string]$hd.ts)).TotalSeconds } catch { }
        $kimden = Protect-MerkezSatir $(if ($hd.from -is [string]) { [string]$hd.from } else { [string]$hd.from.agent }) 8
        [void](GelenSatir $L 'aktarim' "aktarim:$($hd.id)" $hd "$($kimlikRenk[$kimden])$(Pad $kimden 7)$RS $cFaint$(PadL (KisaYas $yasSn) 6)$RS  $(KonuAyrinti (Protect-MerkezSatir ([string]$hd.question) 140) $cText)")
    }
    if (-not $akt.Count) { $L.Add((Row "$cOk✓$RS ${cFaint}bekleyen aktarım yok$RS" $w)) }
    $L.Add((Blank $w))

    # 5) SON ISLEMLER
    Bolum $L $bolumBas 'SON İŞLEMLER' "🧾 SON İŞLEMLER" $cAccent
    $isl = @($script:sonIsler | Select-Object -First 6)
    foreach ($j in $isl) {
        $d = [string]$j.durum; $canli = ($d -eq 'calisiyor' -and (Test-MerkezIsCanli $j))
        $icn = $(if ($d -eq 'tamam') { "$cOk✓$RS" } elseif ($canli) { $script:CizCanli = $true; "$cInfo$(@('⠋','⠙','⠹','⠸','⠼','⠴','⠦','⠧','⠇','⠏')[$script:tik % 10])$RS" } elseif ($d -eq 'calisiyor') { "$cWarn?$RS" } else { "$cErr✕$RS" })
        $son = $(if (@($j.son).Count) { Protect-MerkezSatir ([string]@($j.son)[-1]) 90 } else { '' })
        $zaman = ''; try { $zaman = ([datetime]::Parse([string]$j.basladi)).ToString('HH:mm') } catch { }
        $L.Add((Row "$icn $cFaint$zaman$RS $cText$(Protect-MerkezSatir ("beyin " + (@($j.argv) -join ' ')) 70)$RS$(if ($d -eq 'calisiyor' -and -not $canli) { " ${cWarn}penceresi kapandı$RS" } elseif ($son) { "  $cFaint$son$RS" })" $w))
    }
    if (-not $isl.Count) { $L.Add((Row "${cFaint}bu oturumda merkezden çalıştırılan iş yok$RS" $w)) }
}

function TeshisSatiri($L, $t) {
    # olgu (+ oto rozeti) · secilince neden / etki / duzelt ayrintisi
    $w = $script:w; $ic = $w - 4
    $icn = $(if ($t.Seviye -eq 'err') { "$cErr$BOLD✕$RS" } elseif ($t.Seviye -eq 'warn') { "$cWarn$BOLD▲$RS" } else { "$cInfo●$RS" })
    $mt = Protect-MerkezSatir ([string]$t.Metin) 300; if ($mt -match '^(.*?)\s*·\s*(beyin [^·]+)$') { $mt = $Matches[1] }
    $e = Get-MerkezTeshisEylem $t
    $an = "teshis:$(TeshisAnahtar $t)"
    $sc = GelenSatir $L 'teshis' $an $t "$icn $cText$(Protect-MerkezSatir $mt ($ic - 40))$RS$(if ($e -and $e.Oto) { " $cOk${BOLD}oto$RS" })"
    if ($sc -and ($t.Neden -or $t.Etki -or $e)) {
        if ($t.Neden) { $L.Add((Row "    $cAccent│$RS ${cFaint}neden $RS $cMuted$(Protect-MerkezSatir ([string]$t.Neden) ($ic - 14))$RS" $w)) }
        if ($t.Etki) { $L.Add((Row "    $cAccent│$RS ${cFaint}etki  $RS $cMuted$(Protect-MerkezSatir ([string]$t.Etki) ($ic - 14))$RS" $w)) }
        if ($e) { $L.Add((Row "    $cAccent│$RS ${cFaint}düzelt$RS $cAccent$(Protect-MerkezSatir ((Get-MerkezEylemHedefleri $e) -join ' ; ') ($ic - 14))$RS" $w)) }
        elseif (-not $e) { $L.Add((Row "    $cAccent│$RS ${cFaint}tek tuşluk düzeltmesi yok · bakılacak yer metinde$RS" $w)) }
    }
}

# ---------- onay penceresi ----------
function ModalAc($eylem) {
    if (-not $script:etkilesimli) { Mesaj 'etkileşimsiz pencere: eylem yok' $cErr; return }
    if ($eylem.Insan -and $script:onayBicim -eq 'kapali') { Mesaj 'merkezden onay kapalı (beyin ayar BEYIN_MERKEZ_ONAY tus)' $cErr; return }
    # 3'ten fazla insan onayi tek pencerede: Y yerine ekrandaki kod (yanlislikla toplu onay olmasin; AgentSpace incelemesi 2026-10-31)
    $onaySay = @($eylem.Adimlar | Where-Object { $_.Tur -eq 'onay' }).Count
    # toplu onay (birden fazla) her zaman kod ister; tek onay BEYIN_MERKEZ_ONAY'a gore Y ya da kod
    $kod = $(if ($eylem.Tehlike -or ($eylem.Insan -and ($script:onayBicim -eq 'kod' -or $onaySay -gt 1))) { '{0:D4}' -f (Get-Random -Minimum 0 -Maximum 10000) } else { '' })
    # tampondaki tuslar (yazarken onde giden, yapistirma) onayi gecmesin: pencere acilirken temizlenir, 400 ms tus kabul edilmez
    try { while ([Console]::KeyAvailable) { [void][Console]::ReadKey($true) } } catch { }
    $script:modal = @{ Eylem = $eylem; Hedef = @(Get-MerkezEylemHedefleri $eylem); Kod = $kod; Giris = ''; Acildi = Get-Date
        OnayIdler = @($eylem.Adimlar | Where-Object { $_.Tur -eq 'onay' } | ForEach-Object { $(if ($_.OnayTur) { "$($_.OnayTur) $($_.Id)" } else { [string]$_.Id }) }) }
}
function ModalCiz($L) {
    $m = $script:modal; $w = $script:w; $ic = $w - 4; $e = $m.Eylem
    $renk = $(if ($e.Tehlike) { $cErr } elseif ($e.Insan) { $cWarn } else { $cAccent })
    $L.Add((HLine $w (Sec $(if ($e.Insan) { '🔐 İNSAN ONAYI' } elseif ($e.Tehlike) { '🛑 TEYİT' } else { '🚀 ÇALIŞTIR' }) $renk) '├' '┤'))
    $L.Add((Row "$renk$BOLD$(Protect-MerkezSatir ([string]$e.Ad) ($ic - 2))$RS" $w))
    if ($e.Aciklama) { foreach ($s in (Sar (Protect-MerkezSatir ([string]$e.Aciklama) 400) ($ic - 2) 3)) { $L.Add((Row "$cMuted$s$RS" $w)) } }
    $L.Add((Blank $w))
    if ($m.OnayIdler.Count) {
        # BUTUN onay kimlikleri her zaman gorunur (adim listesi kesilse bile): gormedigin karti onaylamazsin
        $L.Add((Row "$cWarn${BOLD}Onaylanacak ($($m.OnayIdler.Count)):$RS" $w))
        foreach ($s in (Sar ($m.OnayIdler -join ', ') ($ic - 4) 40)) { $L.Add((Row "  $cText$s$RS" $w)) }
        $L.Add((Blank $w))
    }
    $gos = [Math]::Max(4, [Math]::Min(18, $script:h - 18 - [Math]::Ceiling(($m.OnayIdler -join ', ').Length / [Math]::Max(20, $ic - 4))))
    foreach ($s in @($m.Hedef | Select-Object -First $gos)) { $L.Add((Row "  $cFrame•$RS $cText$(Protect-MerkezSatir $s ($ic - 6))$RS" $w)) }
    if ($m.Hedef.Count -gt $gos) { $L.Add((Row "  $cFaint… +$($m.Hedef.Count - $gos) adım daha$RS" $w)) }
    $L.Add((Blank $w))
    if ($e.Insan) { $L.Add((Row "${cFaint}Bu onay senin adına yazılır (kanal: merkez). Ajanlar bu pencereye tuş basamaz; onayı yalnız sen verirsin.$RS" $w)) }
    $kalan = [Math]::Max(0, $script:ModalSure - [int]((Get-Date) - $m.Acildi).TotalSeconds); $script:CizCanli = $true
    $L.Add((Row "${cFaint}$kalan sn içinde onaylanmazsa reddedilmiş sayılır$RS" $w))
    if ($m.Kod) { $L.Add((Row "$cWarn${BOLD}$(if (@($m.Eylem.Adimlar | Where-Object { $_.Tur -eq 'onay' }).Count -gt 3) { 'Toplu onay: ' })Onaylamak için kodu yaz: $($m.Kod)$RS   $cText> $($m.Giris)$cAccent▏$RS   ${cFaint}Esc vazgeç$RS" $w)) }
    else { $L.Add((Row "$renk${BOLD}Y$RS $cText$(if ($e.Insan) { 'onayla ve çalıştır' } else { 'çalıştır' })$RS$cFrame   ·   $RS$cAccent${BOLD}Esc$RS ${cText}vazgeç$RS" $w)) }
    $L.Add((Blank $w))
}
function ModalTus($kk) {
    $m = $script:modal
    if ($kk.Key -eq 'Escape') { $script:modal = $null; Mesaj 'vazgeçildi' $cMuted; Write-MerkezRed $p 'iptal-edildi' ([string]$m.Eylem.Ad); return }
    if (((Get-Date) - $m.Acildi).TotalMilliseconds -lt 400) { return }   # pencere acilir acilmaz gelen tus sayilmaz
    if ($m.Kod) {
        if ($kk.Key -eq 'Backspace') { if ($m.Giris.Length) { $m.Giris = $m.Giris.Substring(0, $m.Giris.Length - 1) }; return }
        $ch = [string]$kk.KeyChar
        if ($ch -match '^[0-9]$' -and $m.Giris.Length -lt 4) { $m.Giris += $ch }
        if ($m.Giris.Length -eq 4) {
            if ($m.Giris -eq $m.Kod) { ModalUygula } else { $script:modal = $null; Mesaj 'kod eşleşmedi · onay verilmedi' $cErr; try { Write-BeyinMakbuz -Paths $p -Script 'merkez' -Outcome 'ONAY_REDDEDILDI' -Agent 'insan' -Reason 'merkez' -Note 'kod eslesmedi' } catch { } }
        }
        return
    }
    if ([string]$kk.KeyChar -in @('y', 'Y')) { ModalUygula }
}
function ModalUygula {
    $m = $script:modal; $script:modal = $null
    $r = Invoke-MerkezEylemAdimlari -Paths $p -Eylem $m.Eylem -InsanTeyit:([bool]$m.Eylem.Insan)
    foreach ($k in $r.Kuyruk) { $script:kuyruk.Add(@{ Argv = $k.Argv; Gorunur = $k.Gorunur; Oto = $false; OnayId = [string]$k.OnayId }) }
    $script:isaret.Clear()
    $parca = @()
    if ($r.Onay.Count) { $parca += "✓ onay: $(($r.Onay | Select-Object -First 4) -join ', ')$(if ($r.Onay.Count -gt 4) { " +$($r.Onay.Count - 4)" })" }
    if ($r.OnayHata.Count) { $parca += "✕ $($r.OnayHata.Count) onay yazılamadı: $(@($r.OnayHata)[0])" }
    if ($r.Atlanan.Count) { $parca += "$($r.Atlanan.Count) atlandı (durum değişti): $(@($r.Atlanan)[0])" }
    if ($r.Kuyruk.Count) { $parca += "$($r.Kuyruk.Count) komut sırada" }
    Mesaj $(if ($parca.Count) { $parca -join ' · ' } else { 'yapılacak adım kalmadı' }) $(if ($r.OnayHata.Count) { $cErr } elseif ($r.Atlanan.Count) { $cWarn } else { $cOk })
    KuyrukIlerlet
}

# ---------- eylem tusu ----------
function EylemTus([string]$tus) {
    if (-not $script:etkilesimli) { Mesaj 'etkileşimsiz pencere: eylem yok' $cErr; return }
    $hedefler = @()
    if ($script:isaret.Count) {
        # isaretler ekrandaki GUNCEL satira cozulur; artik gorunmeyen (kapanmis, baska sekmede) isaret dusurulur
        $guncel = @{}; foreach ($x in $script:secilebilir) { $guncel[[string]$x.Anahtar] = $x }
        foreach ($an in @($script:isaret.Keys)) { if ($guncel.ContainsKey($an)) { $script:isaret[$an] = $guncel[$an] } else { $script:isaret.Remove($an) } }
        $hedefler = @($script:isaret.Values)
        if (-not $hedefler.Count) { Mesaj 'işaretli satırlar artık görünmüyor; işaretler temizlendi'; return }
    } else { $o = Secili; if ($o) { $hedefler = @($o) } }
    if (-not $hedefler.Count) { Mesaj 'önce ↑↓ ile bir satır seç (ya da Boşluk ile işaretle)'; return }
    $bulunan = @()
    foreach ($o in $hedefler) { $e = @(OgeEylemleri $o | Where-Object { $_.Tus -ceq $tus }) | Select-Object -First 1; if ($e) { $bulunan += $e } }
    if (-not $bulunan.Count) {
        $tum = @(OgeEylemleri $hedefler[0]); Mesaj $(if ($tum.Count) { "bu satırda '$tus' yok · var olanlar: $(@($tum | ForEach-Object { "$($_.Tus) $($_.Ad)" }) -join ' · ')" } else { 'bu satır için eylem yok' }); return
    }
    if ($bulunan.Count -gt 1 -and -not $bulunan[0].Toplu) { Mesaj "'$($bulunan[0].Ad)' toplu çalışmaz · tek satır seç"; return }
    if ($hedefler.Count -gt $bulunan.Count) { Mesaj "$($hedefler.Count - $bulunan.Count) işaretli satırda '$tus' yok; yalnız $($bulunan.Count) tanesine uygulanacak" $cWarn }
    $eylem = Join-MerkezEylemler $bulunan
    if ($eylem.Insan -or $eylem.Tehlike -or @($eylem.Adimlar).Count -gt 1) { ModalAc $eylem; return }
    foreach ($s in $eylem.Adimlar) { if ($s.Tur -eq 'komut') { $script:kuyruk.Add(@{ Argv = $s.Argv; Gorunur = $s.Gorunur; Oto = $false }) } }
    Mesaj "→ beyin $(@($eylem.Adimlar[0].Argv) -join ' ')$(if ($eylem.Adimlar[0].Gorunur) { ' · yeni sekmede' })" $cAccent
    KuyrukIlerlet
}
function BakimTuru {
    # B: secili satirdan bagimsiz; birden cok adim varsa ModalAc listeyi gosterip Y ister.
    if (-not $script:etkilesimli -or -not $script:EylemVar) { Mesaj 'etkileşimsiz pencere: bakım turu yok' $cErr; return }
    $e = Get-MerkezBakimEylemi $script:anlik
    if (-not $e) { Mesaj '✓ bakım gerekmiyor: açık aktarım, takılı derleme ya da eski maliyet yok' $cOk; return }
    if (@($e.Adimlar).Count -gt 1) { ModalAc $e; return }
    foreach ($s in $e.Adimlar) { $script:kuyruk.Add(@{ Argv = $s.Argv; Gorunur = $false; Oto = $false }) }
    Mesaj "→ $($e.Aciklama)" $cAccent
    KuyrukIlerlet
}
function EylemMenusu {
    $o = Secili; if (-not $o) { Mesaj 'önce bir satır seç'; return }
    $e = @(OgeEylemleri $o)
    Mesaj $(if ($e.Count) { "eylemler: $(@($e | ForEach-Object { "$($_.Tus) $($_.Ad)" }) -join '  ·  ')" } else { 'bu satır için eylem yok' }) $cAccent
}
function IsaretDegistir {
    $o = Secili; if (-not $o) { return }
    if (-not @(OgeEylemleri $o | Where-Object { $_.Toplu }).Count) { Mesaj 'bu satır toplu işleme girmez (tek tek çalıştır)'; return }
    if ($script:isaret.Contains($o.Anahtar)) { $script:isaret.Remove($o.Anahtar) } else { $script:isaret[$o.Anahtar] = $o }
    SecimKaydir 1
}
function HepsiniIsaretle {
    $o = Secili; if (-not $o) { Mesaj 'önce bir satır seç'; return }
    $n = 0
    foreach ($x in $script:secilebilir) { if ($x.Tur -eq $o.Tur -and @(OgeEylemleri $x | Where-Object { $_.Toplu }).Count) { $script:isaret[$x.Anahtar] = $x; $n++ } }
    Mesaj "$n satır işaretlendi · eylem tuşu hepsine uygular · u temizler" $cAccent
}

# ---------- is kuyrugu ----------
function KuyrukIlerlet {
    # Sirali: bir is bitmeden digeri baslamaz (ayni panoya paralel yazim olmasin). Gorunur is sekmede kosar; o da bitene kadar beklenir.
    if ($script:aktifIs) {
        $j = Read-MerkezIs -Paths $p -Id $script:aktifIs.Id
        $bitti = $j -and [string]$j.durum -ne 'calisiyor'
        $yetim = (-not $bitti) -and ((Get-Date) - $script:aktifIs.Basladi).TotalSeconds -gt 20 -and -not ($j -and (Test-MerkezIsCanli $j))
        if (-not $bitti -and -not $yetim) { return }
        IsSonucu $script:aktifIs $j $yetim
        if ($yetim -or ($j -and [string]$j.durum -ne 'tamam')) { KuyrukIptal 'önceki adım bitmedi' }
        $script:aktifIs = $null
    }
    if (-not $script:kuyruk.Count) { return }
    $k = $script:kuyruk[0]; $script:kuyruk.RemoveAt(0)
    $r = Start-MerkezKomut -Paths $p -Argv $k.Argv -Gorunur:([bool]$k.Gorunur)
    if ($r.Ok) { $script:aktifIs = @{ Id = $r.Id; Argv = $k.Argv; Basladi = Get-Date; Gorunur = $k.Gorunur; Oto = $k.Oto }; $script:sonIsOku = [datetime]::MinValue }
    else { Mesaj "başlatılamadı: $($r.Neden)" $cErr }
}
function KuyrukIptal([string]$neden) {
    # Kalan isler atilir; onlara ait (henuz kullanilmamis) kart onaylari gecersizlenir.
    if (-not $script:kuyruk.Count) { return }
    $idler = @($script:kuyruk | ForEach-Object { [string]$_.OnayId } | Where-Object { $_ })
    $n = $script:kuyruk.Count; $script:kuyruk.Clear()
    $iptal = $(if ($idler.Count) { Revoke-MerkezOnay -Paths $p -Idler $idler } else { 0 })
    Mesaj "sıradaki $n iş durduruldu ($neden)$(if ($iptal) { " · $iptal onay geri alındı" })" $cErr
}
function IsSonucu($is, $j, [bool]$yetim) {
    $kmt = "beyin $(@($is.Argv) -join ' ')"
    if ($yetim) { Mesaj "? $kmt · pencere kapandı, sonuç bilinmiyor" $cWarn; return }
    $son = $(if ($j -and @($j.son).Count) { Protect-MerkezSatir ([string]@($j.son)[-1]) 120 } else { '' })
    if ($is.Oto) {
        $ok = "argv:$(@($is.Argv) -join ' ')"; $od = $script:otoDurum[$ok]; if (-not $od) { $od = @{ Hata = 0; Sonraki = [datetime]::MinValue; Vazgecti = $false }; $script:otoDurum[$ok] = $od }
        if ([string]$j.durum -eq 'tamam') { $od.Hata = 0; $od.Sonraki = [datetime]::MinValue }
        else {
            $od.Hata++; $od.Sonraki = (Get-Date).AddMinutes([Math]::Min(30, [Math]::Pow(2, $od.Hata - 1)))
            if ($od.Hata -ge 3) { $od.Vazgecti = $true; try { Write-BeyinMakbuz -Paths $p -Script 'merkez' -Outcome 'OTO_VAZGECTI' -Agent 'merkez' -Reason 'oto' -Note $kmt } catch { } }
        }
    }
    if ([string]$j.durum -eq 'tamam') { Mesaj "✓ $kmt$(if ($son) { " · $son" })" $cOk }
    else {
        Mesaj "✕ $kmt (kod $($j.kod))$(if ($son) { " · $son" })" $cErr
        Bildir 'Beyin merkez' "iş başarısız: $kmt" 'hata'
        if ($script:kuyruk.Count) { Mesaj "✕ $kmt (kod $($j.kod)) · sıradaki $($script:kuyruk.Count) iş durduruldu" $cErr }
    }
    $script:onb.Remove('ts:Aktarimlar'); $script:onb.Remove('Kartlar'); $script:sonTam = [datetime]::MinValue   # sonuc hemen gorunsun
}
function IslerTazele {
    if ($script:modal -and ((Get-Date) - $script:modal.Acildi).TotalSeconds -ge $script:ModalSure) {
        Write-MerkezRed $p 'zaman-asimi' ([string]$script:modal.Eylem.Ad); $script:modal = $null; Mesaj 'onay penceresinin süresi doldu · reddedildi' $cWarn
    }
    try { KuyrukIlerlet } catch { }
    if (((Get-Date) - $script:sonIsOku).TotalSeconds -ge 2) { $script:sonIsOku = Get-Date; try { $script:sonIsler = @(Get-MerkezSonIsler -Paths $p -Saat 12 -Adet 8) } catch { } }
}
function OtoDuzelt($a) {
    # Yalniz Oto isaretli eylemler; insan onayi ya da tehlikeli adim iceren hicbir sey. Anahtar basina 30 dk soguma.
    if (-not $script:otoAcik -or -not $a -or -not $script:etkilesimli) { return }
    $simdi = Get-Date
    $adaylar = @()
    foreach ($t in $a.Teshis) { $e = Get-MerkezTeshisEylem $t; if ($e -and $e.Oto -and -not $e.Insan -and -not $e.Tehlike) { $adaylar += @{ Anahtar = "teshis:$(TeshisAnahtar $t)"; Eylem = $e } } }
    foreach ($k in $a.Kosular) { if ($k.Bitmis) { continue }; $e = Get-MerkezSonrakiEylem $k; if ($e -and $e.Oto) { $adaylar += @{ Anahtar = "kosu:$($k.RunId):$($e.Kod)"; Eylem = $e } } }
    foreach ($ad in $adaylar) {
        $argv = @($ad.Eylem.Adimlar[0].Argv); $ayni = $false
        $soguma = "argv:$($argv -join ' ')"   # ayni komut teshis ve kosu adayindan iki kez gelmesin
        if ($script:otoSon.ContainsKey($soguma) -and ($simdi - $script:otoSon[$soguma]).TotalMinutes -lt 30) { continue }
        $od = $script:otoDurum[$soguma]; if ($od -and ($od.Vazgecti -or $simdi -lt $od.Sonraki)) { continue }   # 3 hatada vazgecer; arada geri cekilir
        if (@($script:kuyruk | Where-Object { $_.Oto }).Count -or ($script:aktifIs -and $script:aktifIs.Oto)) { continue }   # ayni anda tek oto isi
        foreach ($q in $script:kuyruk) { if ((@($q.Argv) -join ' ') -eq ($argv -join ' ')) { $ayni = $true } }
        if ($script:aktifIs -and (@($script:aktifIs.Argv) -join ' ') -eq ($argv -join ' ')) { $ayni = $true }
        if ($ayni) { continue }
        $script:otoSon[$soguma] = $simdi
        $script:kuyruk.Add(@{ Argv = $argv; Gorunur = $false; Oto = $true })
        try { Write-BeyinMakbuz -Paths $p -Script 'merkez' -Outcome 'OTO_DUZELT' -Agent 'merkez' -Reason 'oto' -Note ($argv -join ' ') } catch { }
        Mesaj "oto-düzelt: beyin $($argv -join ' ')" $cInfo
    }
}
function SessizAktif { return [bool]($script:sessizKip -eq 'oturum' -or ($script:sessizKip -eq '30dk' -and $script:sessizBitis -and (Get-Date) -lt $script:sessizBitis)) }
function SessizDegistir {
    # kapali -> 30 dk -> oturum -> kapali. Yalniz ses ve Windows bildirimi susar; liste, onay sayaci ve rozet ASLA gizlenmez.
    $script:sessizKip = switch ($script:sessizKip) { 'kapali' { '30dk' } '30dk' { 'oturum' } default { 'kapali' } }
    $script:sessizBitis = $(if ($script:sessizKip -eq '30dk') { (Get-Date).AddMinutes(30) } else { $null })
    Mesaj $(switch ($script:sessizKip) { '30dk' { 'sessiz: 30 dk (ses ve bildirim yok; onaylar görünür kalır)' } 'oturum' { 'sessiz: bu oturum boyunca' } default { 'sessiz mod kapalı' } }) $cMauve
}
function OtoDegistir {
    $script:otoAcik = -not $script:otoAcik
    if ($script:otoAcik) { $script:otoDurum = @{} }   # yeniden acmak vazgecmeleri sifirlar
    Mesaj $(if ($script:otoAcik) { 'oto-düzelt AÇIK · yalnız güvenli adımlar (maliyet taraması, işçi sonuçlarını toplama); onay ve durdurma asla oto değil' } else { 'oto-düzelt kapalı' }) $(if ($script:otoAcik) { $cOk } else { $cMuted })
}
