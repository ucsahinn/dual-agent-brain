param(
    [string]$Vault = '',
    [switch]$Tek,          # bir kare ciz ve cik (test / ekran goruntusu icin)
    [int]$Genislik = 0,    # pencere genisligini ez (test: 90 / 120 / 170)
    [int]$Yukseklik = 0,
    [switch]$Aktifler      # -Tek ile: canli ekrandaki varsayilan gorunum (yalniz aktif kanatlar)
)
# merkez.ps1 - Beyin MERKEZ: tum sistemin tek izleme ekrani (Windows Terminal).
# Liderler (Claude/Codex oturumlari), takim kosulari ve iscileri, onaylar, pano, aktarimlar,
# kaynak ve maliyet tek ekranda. HICBIR SEY YAZMAZ; yalniz okur ve Enter ile panel acar.
# Veri: merkez-veri.ps1 (durum kurali tek yerde). Balon: merkez-balon.ps1 (varsa).
# Tuslar: yukari/asagi (ya da j) sec, Enter odak (isci paneli / lider ayrintisi), p kosu panosu, a hepsi, r tazele, q cik.
# Gorsel dil (1.4.1): koşu panosu (takim-izle.ps1) ile ayni - tek dis cerceve, ├─ BOLUM ─┤ ayraclari, rozetler,
# stat kartlari, adim cizgisi, SIRADA seridi. Renk rolleri: DURUM (yesil/sari/kirmizi/sonuk), KIMLIK (Claude seftali,
# Codex turkuaz), VURGU (mavi: secim, guncel adim, SIRADA).
if (-not $Vault) { $Vault = $(if ($env:BEYIN_VAULT) { $env:BEYIN_VAULT } else { Split-Path (Split-Path $PSScriptRoot -Parent) -Parent }) }
. (Join-Path $Vault 'motor\hooks\lib.ps1')
. (Join-Path $PSScriptRoot 'merkez-veri.ps1')
$balonYol = Join-Path $PSScriptRoot 'merkez-balon.ps1'; if (Test-Path -LiteralPath $balonYol) { . $balonYol }
$p = Get-BeyinPaths -Vault $Vault
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }
try { [Console]::CursorVisible = $false } catch { }
$ESC = [char]27

# ---------- palet (takim-izle ile ayni: Catppuccin Mocha) ----------
function FG([int]$r, [int]$g, [int]$b) { return "$ESC[38;2;$r;$g;${b}m" }
function BG([int]$r, [int]$g, [int]$b) { return "$ESC[48;2;$r;$g;${b}m" }
$RS = "$ESC[0m"; $BOLD = "$ESC[1m"
$cText = FG 205 214 244; $cMuted = FG 166 173 200; $cFaint = FG 127 132 156; $cFrame = FG 69 71 90; $cFrame2 = FG 88 91 112
$cTitle = FG 180 190 254; $cAccent = FG 137 180 250; $cOk = FG 166 227 161; $cWarn = FG 249 226 175; $cErr = FG 243 139 168
$cPeach = FG 250 179 135; $cTeal = FG 148 226 213; $cMauve = FG 203 166 247; $cSky = FG 137 220 235
$bgSel = BG 49 50 68; $bgGate = BG 58 50 36; $cBarOff = FG 88 91 112; $cIz = FG 54 56 76   # cubuk izi: dolu koyu blok (░ taramasi koyu zeminde gorunmuyordu)
$bgRun = BG 64 96 62; $bgIdle = BG 110 90 40; $bgDone = BG 49 66 110; $bgBad = BG 120 50 70; $bgWait = BG 49 50 68; $bgPart = BG 110 90 40
$spin = @('⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏'); $script:tik = 0
# DURUM rolu: dort nokta (calisiyor, insan/karar bekliyor, engelli, bosta); digerleri sozcukle
$durumRenk = @{ calisiyor = $cOk; inceleme = $cWarn; engelli = $cErr; duraklatildi = $cMauve; bosta = $cFaint; bitti = $cFaint; bekliyor = $cSky; kapali = $cFrame2 }
$durumAd = @{ calisiyor = 'çalışıyor'; inceleme = 'incelemede'; engelli = 'engelli'; duraklatildi = 'kota'; bosta = 'boşta'; bitti = 'bitti'; bekliyor = 'sırada'; kapali = 'kapandı' }
$durumSira = @{ engelli = 0; inceleme = 1; calisiyor = 2; duraklatildi = 3; bekliyor = 4; bitti = 5; bosta = 6; kapali = 7 }
$kimlikRenk = @{ claude = $cPeach; codex = $cTeal }
$panoAd = @{ todo = 'bekliyor'; in_progress = 'sürüyor'; review = 'incelemede'; blocked = 'engelli' }
$asamaAd = @('plan', 'başladı', 'işçiler bitti', 'toplandı', 'birleşti', 'doğrulandı', 'ana dalda')

# ---------- metin olcusu (genis karakter + ANSI guvenli) ----------
$rxAnsi = [regex]"$ESC\[[0-9;]*[A-Za-z]"
function Strip([string]$s) { return $rxAnsi.Replace($s, '') }
function CellW([char]$c) {
    $n = [int]$c
    if ($n -lt 0x1100) { if ($n -ge 0x231A -and $n -le 0x231B) { return 2 }; return 1 }
    if (($n -ge 0x1100 -and $n -le 0x115F) -or ($n -ge 0x2E80 -and $n -le 0xA4CF) -or ($n -ge 0xAC00 -and $n -le 0xD7A3) -or ($n -ge 0xF900 -and $n -le 0xFAFF) -or ($n -ge 0xFE30 -and $n -le 0xFE4F) -or ($n -ge 0xFF00 -and $n -le 0xFF60) -or ($n -ge 0xFFE0 -and $n -le 0xFFE6)) { return 2 }
    return 1
}
# HIZ (1.4.5): eskiden VisLen/Cut her karakter icin CellW islevini cagiriyordu; bir kare ~1,1 sn suruyordu ve 120 ms'lik
# animasyon saniyede bir kareye dusuyordu. Simdi: genislik = uzunluk + genis karakter sayisi (vekil cift zaten 2 birim
# uzunluktur = 2 hucre); Cut ANSI disi parcalari toptan keser, yalniz genis karakter iceren parcada tek tek yurur.
$rxGenis = [regex]'[\u1100-\u115F\u231A\u231B\u2E80-\uA4CF\uAC00-\uD7A3\uF900-\uFAFF\uFE30-\uFE4F\uFF00-\uFF60\uFFE0-\uFFE6]'
$rxGenisVeyaVekil = [regex]'[\u1100-\u115F\u231A\u231B\u2E80-\uA4CF\uAC00-\uD7A3\uF900-\uFAFF\uFE30-\uFE4F\uFF00-\uFF60\uFFE0-\uFFE6\uD800-\uDFFF]'
function VisLen([string]$s) { $t = $rxAnsi.Replace($s, ''); return $t.Length + $rxGenis.Matches($t).Count }
function Cut([string]$s, [int]$w) {
    if ($w -le 0) { return '' }
    if ((VisLen $s) -le $w) { return $s }
    $out = New-Object Text.StringBuilder; $vis = 0; $pos = 0; $hedef = $w - 1; $bitti = $false
    $parcalar = @($rxAnsi.Matches($s)) + @($null)
    foreach ($m in $parcalar) {
        $son = $(if ($m) { $m.Index } else { $s.Length })
        if ($son -gt $pos -and -not $bitti) {
            $seg = $s.Substring($pos, $son - $pos)
            if (-not $rxGenisVeyaVekil.IsMatch($seg)) {
                $n = [Math]::Min($seg.Length, $hedef - $vis); if ($n -gt 0) { [void]$out.Append($seg.Substring(0, $n)); $vis += $n }
                if ($n -lt $seg.Length) { $bitti = $true }
            } else {
                $i = 0
                while ($i -lt $seg.Length) {
                    $vek = [char]::IsHighSurrogate($seg[$i]) -and $i + 1 -lt $seg.Length
                    $cw = $(if ($vek) { 2 } elseif ($rxGenis.IsMatch([string]$seg[$i])) { 2 } else { 1 })
                    if ($vis + $cw -gt $hedef) { $bitti = $true; break }
                    if ($vek) { [void]$out.Append($seg.Substring($i, 2)); $i += 2 } else { [void]$out.Append($seg[$i]); $i++ }
                    $vis += $cw
                }
            }
        }
        if ($m) { [void]$out.Append($m.Value); $pos = $m.Index + $m.Length }
    }
    return $out.ToString() + "…$RS"
}
function Pad([string]$s, [int]$w) { $v = VisLen $s; if ($v -le $w) { return $s + (' ' * ($w - $v)) }; $s = Cut $s $w; return $s + (' ' * [Math]::Max(0, $w - (VisLen $s))) }   # tek olcum (sigan metinde Cut yok)
function PadL([string]$s, [int]$w) { $s = Cut $s $w; return (' ' * [Math]::Max(0, $w - (VisLen $s))) + $s }
function Kisa([double]$sn) {
    if ($sn -lt 0) { return '—' }; if ($sn -lt 60) { return "$([int]$sn) sn" }; if ($sn -lt 3600) { return "$([int][Math]::Floor($sn / 60)) dk" }
    if ($sn -lt 86400) { return "$([int][Math]::Floor($sn / 3600)) sa $([int][Math]::Floor(($sn % 3600) / 60)) dk" }; return "$([int][Math]::Floor($sn / 86400)) gün"
}
function KisaYas([double]$sn) {
    # Liste sutunu icin tek birimli yas (sabit genislikte kesilmesin): 45 sn, 12 dk, 13 sa, 3 gün
    if ($sn -lt 0) { return '—' }; if ($sn -lt 60) { return "$([int]$sn) sn" }; if ($sn -lt 3600) { return "$([int][Math]::Floor($sn / 60)) dk" }
    if ($sn -lt 86400) { return "$([int][Math]::Floor($sn / 3600)) sa" }; return "$([int][Math]::Floor($sn / 86400)) gün"
}
function Fmt([double]$n) { if ($n -ge 1e9) { return ('{0:0.0}Mr' -f ($n / 1e9)) }; if ($n -ge 1e6) { return ('{0:0.0}M' -f ($n / 1e6)) }; if ($n -ge 1e3) { return ('{0:0.0}K' -f ($n / 1e3)) }; return "$([int64]$n)" }
function Bar([double]$oran, [int]$gen, [string]$renk) {
    $oran = [Math]::Max([double]0, [Math]::Min([double]1, $oran)); $dolu = [int][Math]::Round($oran * $gen)
    return "$renk" + ('█' * $dolu) + "$cIz" + ('█' * ($gen - $dolu)) + $RS
}
function RolTr([string]$r) { switch ($r) { 'root_cause_debugger' { 'hata ayıklayıcı' } 'docs_author' { 'belge yazarı' } 'qa_lead' { 'QA lideri' } 'spec_author' { 'spek yazarı' } 'test_verifier' { 'doğrulayıcı' } 'code_mapper' { 'kod haritacısı' } 'code_reviewer' { 'kod incelemeci' } 'security_auditor' { 'güvenlik denetçisi' } 'frontend_verifier' { 'arayüz doğrulayıcı' } 'design_reviewer' { 'tasarım incelemeci' } 'performance_auditor' { 'performans denetçisi' } 'docs_researcher' { 'belge araştırmacısı' } 'engineering_planner' { 'mühendislik planlayıcı' } '' { '' } default { $r -replace '_', ' ' } } }

# ---------- cerceve (koşu panosu ile ayni) ----------
function MiniBar([double]$oran, [int]$gen, [string]$renk) {
    $oran = [Math]::Max([double]0, [Math]::Min([double]1, $oran)); $on = [int][Math]::Round($oran * $gen)
    return "$renk$('█' * $on)$cIz$('█' * ($gen - $on))$RS"
}
# ---------- canli cizim (1.4.5): renk gecisli cubuklar, tarama, nabiz ----------
# Emoji kurali: yalniz Emoji_Presentation=Yes ve U+1F000 ustu (vekil cift) emoji kullanilir; bunlar her terminalde 2 hucre
# cizilir ve VisLen onlari 2 sayar. Genisligi belirsiz BMP simgeleri (⚠ ✔ ✖ ▶ ⏸) Windows Terminal'de 2 hucre cizilip
# yanindaki harfin ustune biniyordu (1.4.4 ekran goruntusu) - onlarin yerine metin simgeleri (▲ ✓ ✕ ▸ ‖).
$rgbOk = @(166, 227, 161); $rgbWarn = @(249, 226, 175); $rgbErr = @(243, 139, 168); $rgbTeal = @(148, 226, 213); $rgbAcc = @(137, 180, 250); $rgbIz = @(54, 56, 76); $rgbAk = @(245, 245, 255)
function Karis([int[]]$x, [int[]]$y, [double]$t) {
    $t = [Math]::Max([double]0, [Math]::Min([double]1, $t))
    return (FG ([int]($x[0] + ($y[0] - $x[0]) * $t)) ([int]($x[1] + ($y[1] - $x[1]) * $t)) ([int]($x[2] + ($y[2] - $x[2]) * $t)))
}
function GradBar([double]$oran, [int]$gen, [int[]]$c1, [int[]]$c2) {
    # dolu hucreler c1 -> c2 renk gecisli, bos kisim koyu iz
    $oran = [Math]::Max([double]0, [Math]::Min([double]1, $oran)); $on = [int][Math]::Round($oran * $gen); $sb = ''
    for ($i = 0; $i -lt $on; $i++) { $sb += (Karis $c1 $c2 ($(if ($gen -gt 1) { $i / [double]($gen - 1) } else { 0 }))) + '█' }
    return $sb + "$cIz$('█' * ($gen - $on))$RS"
}
function IsiBar([double]$oran, [int]$gen) {
    # kullanim cubugu: her hucre konumuna gore yesil -> sari -> kirmizi (doluluk arttikca isinir)
    $oran = [Math]::Max([double]0, [Math]::Min([double]1, $oran)); $on = [int][Math]::Round($oran * $gen); $sb = ''
    for ($i = 0; $i -lt $on; $i++) { $t = $(if ($gen -gt 1) { $i / [double]($gen - 1) } else { 0 }); $sb += $(if ($t -lt 0.6) { Karis $rgbOk $rgbWarn ($t / 0.6) } else { Karis $rgbWarn $rgbErr (($t - 0.6) / 0.4) }) + '█' }
    return $sb + "$cIz$('█' * ($gen - $on))$RS"
}
function Tarama([int]$gen, [int]$faz, [int[]]$c) {
    # gidip gelen parlak bas + sonen kuyruk: "canli calisiyor" gostergesi (her ajan kendi fazinda)
    $yol = [Math]::Max(1, 2 * ($gen - 1)); $k = $faz % $yol; $pos = $(if ($k -lt $gen) { $k } else { $yol - $k }); $sb = ''
    for ($i = 0; $i -lt $gen; $i++) {
        $uz = [Math]::Abs($i - $pos)
        $sb += $(switch ($uz) { 0 { Karis $c $rgbAk 0.45 } 1 { FG $c[0] $c[1] $c[2] } 2 { Karis $c $rgbIz 0.55 } default { $cIz } }) + '━'
    }
    return "$sb$RS"
}
function Spark([double[]]$v, [int]$gen, [int[]]$c1, [int[]]$c2, [double]$maks = -1) {
    # Mini grafik: son $gen deger, ▁..█ yukseklik; renk yukseklige gore c1 -> c2. Sifir/eksik deger koyu taban cizgisi.
    $bl = @('▁', '▂', '▃', '▄', '▅', '▆', '▇', '█'); if ($v.Count -gt $gen) { $v = $v[($v.Count - $gen)..($v.Count - 1)] }
    $m = $maks; if ($m -le 0) { $m = 0.0; foreach ($x in $v) { if ($x -gt $m) { $m = $x } } }; $sb = "$cIz$('▁' * [Math]::Max(0, $gen - $v.Count))"   # pipeline yok
    foreach ($x in $v) {
        if ($m -le 0 -or $x -le 0) { $sb += "$cIz▁"; continue }
        $t = [Math]::Min(1.0, $x / $m); $k = [int][Math]::Round($t * 7)
        $sb += (Karis $c1 $c2 $t) + $bl[$k]
    }
    return "$sb$RS"
}
function BgKaris([int[]]$x, [int[]]$y, [double]$t) {
    $t = [Math]::Max([double]0, [Math]::Min([double]1, $t))
    return (BG ([int]($x[0] + ($y[0] - $x[0]) * $t)) ([int]($x[1] + ($y[1] - $x[1]) * $t)) ([int]($x[2] + ($y[2] - $x[2]) * $t)))
}
function Nabiz([int[]]$c, [double]$hiz = 0.55) { return (Karis $rgbIz $c (0.35 + 0.65 * (([Math]::Sin($script:tik * $hiz) + 1) / 2))) }

function HLine([int]$w, [string]$label, [string]$left, [string]$right) {
    $lab = $(if ($label) { " $label$cFrame " } else { '' })
    $fill = $w - 2 - (VisLen $lab) - $(if ($right) { 1 } else { 0 }); if ($fill -lt 0) { $fill = 0 }
    return "$cFrame$left─$lab$('─' * $fill)$right$RS"
}
function Row([string]$c, [int]$w) { return "$cFrame│$RS " + (Pad $c ($w - 4)) + " $cFrame│$RS" }
function Blank([int]$w) { return (Row '' $w) }
function Cols([string]$a, [string]$b, [int]$w, [int]$solW) { return (Pad $a ($solW - 1)) + " $cFrame│ $RS" + (Cut $b ($w - 4 - $solW - 2)) }
function Sec([string]$ad, [string]$renk = $cAccent) { return "$renk$BOLD$ad$RS" }
function Cards([object[]]$cards, [int]$inner) {
    # stat kartlari (koşu panosu ile ayni): genis ekranda yan yana, darda 3'lu / 2'li satirlara boler
    $out = New-Object System.Collections.Generic.List[string]
    $n = $cards.Count; if ($n -eq 0) { return $out }
    $perRow = 1; foreach ($cand in @($n, [int][Math]::Ceiling($n / 2.0), [int][Math]::Ceiling($n / 3.0), 2, 1)) { if ($cand -lt 1 -or $cand -gt $n) { continue }; if ([int][Math]::Floor(($inner - ($cand - 1)) / $cand) -ge 36) { $perRow = $cand; break } }
    for ($s0 = 0; $s0 -lt $n; $s0 += $perRow) {
        $grp = @($cards[$s0..([Math]::Min($n, $s0 + $perRow) - 1)])
        $cw0 = [int][Math]::Floor(($inner - ($grp.Count - 1)) / $grp.Count); $artik = $inner - ($grp.Count - 1) - $cw0 * $grp.Count
        $hh = 0; foreach ($c in $grp) { if (@($c.l).Count -gt $hh) { $hh = @($c.l).Count } }
        $top = ''; $bot = ''; $mid = @(); for ($k = 0; $k -lt $hh; $k++) { $mid += '' }
        $ci = 0
        foreach ($c in $grp) {
            $cw = $cw0 + $(if ($ci -lt $artik) { 1 } else { 0 }); $ci++   # artik hucreler ilk kartlara: satir tam dolar, sag kenarda bosluk kalmaz
            # kenar rengi durumu tasir (c.r: uyari/hata); sakin kart cerceve renginde kalir
            $kr = $(if ($c.r) { $c.r } else { $cFrame }); $tr = $(if ($c.r) { $c.r } elseif ($c.tr) { $c.tr } else { $cAccent })
            $lab = " $tr$BOLD$($c.t)$RS$kr "
            $fill = $cw - 2 - (VisLen $lab); if ($fill -lt 0) { $fill = 0 }
            $top += "$kr┌$lab$('─' * $fill)┐$RS "
            $bot += "$kr└$('─' * ($cw - 2))┘$RS "
            for ($k = 0; $k -lt $hh; $k++) { $txt = $(if ($k -lt @($c.l).Count) { [string]@($c.l)[$k] } else { '' }); $mid[$k] += "$kr│$RS " + (Pad $txt ($cw - 4)) + " $kr│$RS " }
        }
        $out.Add($top.TrimEnd()); foreach ($m in $mid) { $out.Add($m.TrimEnd()) }; $out.Add($bot.TrimEnd())
    }
    return $out
}

# ---------- durum ----------
$script:onb = @{}; $script:anlik = $null; $script:sonHizli = [datetime]::MinValue; $script:sonTam = [datetime]::MinValue
$script:secAnahtar = ''; $script:sec = 0; $script:hepsi = $false; $script:acik = ''; $script:mesaj = ''; $script:mesajZaman = [datetime]::MinValue
$script:lastFrame = ''; $script:cizimHata = 0; $script:cizimMesaj = ''; $script:sonCizim = Get-Date; $script:secilebilir = @()
$script:olayGoruldu = $null
$script:bildirimAcik = $(try { [string](Get-BeyinAyar 'BEYIN_BILDIRIM' (Get-BeyinAyarVars 'BEYIN_BILDIRIM')) -ne 'kapali' } catch { $true })

function Bildir([string]$baslik, [string]$metin) {
    if (-not $script:bildirimAcik) { return }
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
    foreach ($t in $a.Teshis) { if ($t.Seviye -eq 'err') { $o["hata:$(if ($t.Anahtar) { $t.Anahtar } else { $t.Metin -replace '\d', '#' })"] = [string]$t.Metin } }
    if ($null -eq $script:olayGoruldu) { $script:olayGoruldu = @{}; foreach ($k in $o.Keys) { $script:olayGoruldu[$k] = $true }; return }
    foreach ($k in @($script:olayGoruldu.Keys)) { if (-not $o.Contains($k)) { $script:olayGoruldu.Remove($k) } }
    $yeni = @($o.Keys | Where-Object { -not $script:olayGoruldu.ContainsKey($_) })
    if (-not $yeni.Count) { return }
    foreach ($k in $yeni) { $script:olayGoruldu[$k] = $true }
    Bildir 'Beyin merkez' (@($yeni | ForEach-Object { $o[$_] }) -join ' · ')
}

$script:gecmis = @{ Cal = New-Object System.Collections.Generic.List[double]; Commit = New-Object System.Collections.Generic.List[double] }
function Tazele([bool]$tam) {
    $script:anlik = Get-MerkezAnlik -Paths $p -Onbellek $script:onb -Hizli:(-not $tam)
    $script:sonHizli = Get-Date; if ($tam) { $script:sonTam = Get-Date }
    if ($tam) {
        # panel acik kaldikca biriken egilim (6 sn'de bir nokta, en cok 60 = 6 dk)
        try {
            $script:gecmis.Cal.Add([double]@($script:anlik.Ajanlar | Where-Object { $_.Durum -eq 'calisiyor' }).Count)
            if ($script:anlik.Kaynak -and $script:anlik.Kaynak.Ok) { $script:gecmis.Commit.Add([double]$script:anlik.Kaynak.CommitYuzde) }
            foreach ($k in @('Cal', 'Commit')) { while ($script:gecmis[$k].Count -gt 60) { $script:gecmis[$k].RemoveAt(0) } }
        } catch { }
    }
    try { OlaylariBildir $script:anlik } catch { }
}
function KisaId($ag) {
    # Codex oturum kimligi UUIDv7: ilk haneler zaman damgasi, ayni saatte acilan oturumlarda cakisir -> son 4 hane.
    $id = [string]$ag.Ad; if (-not $id) { return '' }
    $id = $(if ($ag.Ajan -eq 'codex') { $id.Substring([Math]::Max(0, $id.Length - 4)) } else { $id.Substring(0, [Math]::Min(4, $id.Length)) })
    return (Protect-MerkezSatir $id 4)
}
function Sar([string]$metin, [int]$gen, [int]$maks = 2) {
    # Duz metni sozcuk sinirindan $gen genisliginde en cok $maks satira boler; sigmayan son satir kesilir.
    $sat = New-Object System.Collections.Generic.List[string]; $cur = ''
    foreach ($s in ($metin -split ' ')) {
        if (-not $cur) { $cur = $s; continue }
        if ((VisLen "$cur $s") -le $gen) { $cur = "$cur $s" } else { $sat.Add($cur); $cur = $s }
    }
    if ($cur) { $sat.Add($cur) }
    if ($sat.Count -gt $maks) { $son = ($sat.GetRange($maks - 1, $sat.Count - $maks + 1) -join ' '); $sat = $sat.GetRange(0, $maks - 1); $sat.Add((Cut $son $gen)) }
    return ,$sat
}
function AjanAnahtar($ag) { return "$($ag.Tur):$($ag.Kosu):$($ag.Ad)" }

# ---------- cizim ----------
function AjanSatir($ag, [int]$gen, [bool]$secili, [bool]$idGoster, [int]$ekGen = 19) {
    $d = [string]$ag.Durum; $renk = $durumRenk[$d]; if (-not $renk) { $renk = $cFaint }
    $kr = $kimlikRenk[[string]$ag.Ajan]; if (-not $kr) { $kr = $cMuted }
    $isaret = $(if ($secili) { "$cAccent$BOLD▸$RS" } else { ' ' })
    $nokta = $(switch ($d) { 'calisiyor' { "$renk$($spin[$script:tik % $spin.Count])$RS" } 'inceleme' { "$renk◐$RS" } 'engelli' { "$renk✕$RS" } 'duraklatildi' { "$renk◐$RS" } 'bitti' { "$renk✓$RS" } 'bekliyor' { "$renk◌$RS" } default { "$renk○$RS" } })
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
    $tarS = $(if ($ns -ge 0 -and $ns -le 3) { Tarama 6 (2 * $script:tik + $tFaz) $rgbOk } elseif ($ns -le 60) { Tarama 6 ([int][Math]::Floor($script:tik / 2) + $tFaz) $rgbOk } else { Tarama 6 $tFaz $rgbIz })   # 60 sn+ sessiz: donuk
    $durumYazi = $(if ($d -eq 'calisiyor') { "$renk$($durumAd[$d])$RS $tarS" } else { "$renk$($durumAd[$d])$RS" })
    $yasRenk = $(if ($ag.Bayat) { $cWarn } else { $cMuted })
    if (-not $ag.Bayat -and $d -eq 'calisiyor') { $yasRenk = $(if ($yasSn -ge 0 -and $yasSn -le 10) { $cOk } elseif ($yasSn -le 60) { $cText } else { $cMuted }) }   # taze nabiz yesil
    $yas = "$yasRenk$(Kisa $yasSn)$(if ($ag.Bayat) { ' !' })$RS"
    $ek = @(); if ($ag.Jeton) { $ek += "$(Fmt $ag.Jeton) jt" }; if ($ag.Dosya) { $ek += "$($ag.Dosya) dosya" }
    $ekS = $(if ($ek.Count) { "$cFaint$($ek -join ' · ')$RS" } else { '' })
    $sol = "$isaret $nokta $(Pad $ad 18) $(Pad $rol 15) $(Pad $durumYazi 16) "
    $sag = " $(PadL $yas 11)$(if ($ekGen -gt 0) { ' ' + (PadL $ekS $ekGen) }) "
    $balonGen = $gen - (VisLen $sol) - (VisLen $sag)
    # Balon: calisan ajanda canli (soluk degil), digerlerinde "son yaptigi" olarak soluk; bostaki ajanin yarim kalmis
    # "düşünüyor" kaydi su an dusunuyormus gibi okunuyordu, gosterilmez.
    $bm = [string]$ag.Balon; if ($d -ne 'calisiyor' -and $bm -match '^… düşünüyor') { $bm = '' }
    $bm = $bm -replace '(?i)(/c/Users/|[A-Z]:[\\/]Users[\\/])[^/\\\s]+', '~'   # ev dizini ~: yol on eki dar balonu yemesin, kullanici adi ekrana cikmasin
    $balon = $(if ($bm -and $balonGen -gt 6) { "$(if ($d -eq 'calisiyor') { $cText } else { $cFaint })$(Cut $bm $balonGen)$RS" } else { '' })
    $satir = $sol + (Pad $balon ([Math]::Max(0, $balonGen))) + $sag
    if ($secili) { $satir = "$bgSel" + ((Pad $satir $gen) -replace [regex]::Escape($RS), "$RS$bgSel") + $RS }
    return $satir
}

function KanatSatirlari([string]$kanat, $ajanlar, [int]$ic) {
    # Bir kanat: alt baslik + ajan satirlari (+ acik ayrinti) + toplanmis sakinler. Satir icerigi $ic genisliginde.
    $L = New-Object System.Collections.Generic.List[string]
    $aktif = @($ajanlar | Where-Object { $_.Durum -notin @('bosta', 'kapali', 'bitti') })
    $sakin = @($ajanlar | Where-Object { $_.Durum -in @('bosta', 'kapali', 'bitti') })
    $ozet = @(); if ($aktif.Count) { $ozet += "$cOk$($aktif.Count) aktif$RS" }; if ($sakin.Count) { $ozet += "$cFaint$($sakin.Count) boşta$RS" }
    $lid = @($ajanlar | Where-Object { $_.Tur -eq 'lider' }).Count; $isc = @($ajanlar | Where-Object { $_.Tur -eq 'isci' }).Count
    $L.Add("$cTitle$BOLD▣ $(Protect-MerkezSatir $kanat 40)$RS$cFaint  ·  $RS$($ozet -join "$cFaint · $RS")$(if ($isc) { "$cFaint  ·  $RS$cTeal$isc işçi$RS" })")
    $gosterilen = $(if ($script:hepsi -or -not $aktif.Count) { @($aktif) + @($sakin) } else { $aktif })
    $rolSay = @{}; foreach ($ag in $ajanlar) { if ($ag.Tur -eq 'lider') { $rolSay[$ag.Rol] = 1 + [int]$rolSay[$ag.Rol] } }
    # jeton/dosya sutunu yalniz o kanatta degeri olan bir ajan varsa yer kaplar; yoksa genislik balona kalir
    $ekGen = $(if (@($gosterilen | Where-Object { $_.Jeton -or $_.Dosya }).Count) { 19 } else { 0 })
    foreach ($ag in $gosterilen) {
        $anahtar = AjanAnahtar $ag
        $script:secilebilir += , $ag
        $L.Add((AjanSatir $ag $ic ($anahtar -eq $script:secAnahtar) ([int]$rolSay[$ag.Rol] -gt 1) $ekGen))
        if ($script:acik -and $script:acik -eq $anahtar) {
            if ($ag.Tur -eq 'lider') {
                $L.Add("      $cFaint oturum $(Protect-MerkezSatir (([string]$ag.Ad) -replace '-', ' ') 60) · pid $(if ($ag.Pid) { $ag.Pid } else { '—' }) · durum kaynağı $($ag.Kaynak) · başladı $(if ($ag.Basladi) { $ag.Basladi.ToString('HH:mm') } else { '—' })$RS")
                $L.Add("      $cFaint$(Protect-MerkezSatir ([string]$ag.Cwd) ($ic - 8))$RS")
            } else {
                $L.Add("      $cFaint koşu $(Protect-MerkezSatir ([string]$ag.Kosu) 30) · durum kaynağı $($ag.Kaynak) · karar $(if ($ag.Verdict) { $ag.Verdict } else { '—' }) · ⏎ işçi paneli · p koşu panosu$RS")
            }
        }
    }
    if (-not $script:hepsi -and $aktif.Count -and $sakin.Count) {
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
        'kota'          { return "$bgIdle$BOLD ◐ KOTA SINIRI $RS" }
        default         { return "$bgDone$BOLD ▸ ŞEF SIRASI $RS" }
    }
}

function KonuAyrinti([string]$m, [string]$renk) {
    # ilk ':' / '(' / '. ' oncesi konu (parlak), sonrasi ayrinti (soluk): goz yalniz konuyu okur
    $i = $m.IndexOfAny([char[]]@(':', '(')); $j = $m.IndexOf('. '); if ($j -gt 0 -and ($i -lt 0 -or $j -lt $i)) { $i = $j + 1 }
    if ($i -le 0 -or $i -ge $m.Length - 1) { return "$renk$m$RS" }
    return "$renk$($m.Substring(0, $i + 1))$RS$cFaint$($m.Substring($i + 1))$RS"
}
function KosuRozetMetin([string]$r) {
    switch ($r) {
        'raporlar' { 'raporlar alındı' } 'iptal' { 'iptal' } 'basarisiz' { 'başarısız' } 'anadalda' { 'ana dalda' } 'sahipsiz' { 'gözetmen durdu' }
        'calisiyor' { 'çalışıyor' } 'cakisma' { 'çakışma' } 'kontrol' { 'kontrol düştü' } 'dogrulanamadi' { 'doğrulanamadı' }
        'uyarili' { 'uyarıyla doğrulandı' } 'dogrulandi' { 'doğrulandı' } 'onay' { 'onay bekliyor' } 'kota' { 'kota sınırı' } default { 'şef sırası' }
    }
}

function Ciz {
    $w = 160; $h = 50; try { $w = $Host.UI.RawUI.WindowSize.Width; $h = $Host.UI.RawUI.WindowSize.Height } catch { }
    if ($Genislik -gt 0) { $w = $Genislik }; if ($Yukseklik -gt 0) { $h = $Yukseklik }
    if ($w -lt 90) { $w = 90 }
    $ic = $w - 4
    $a = $script:anlik; $L = New-Object System.Collections.Generic.List[string]
    $script:secilebilir = @(); $bolumBas = New-Object System.Collections.Generic.List[object]
    $hata = @($a.Teshis | Where-Object { $_.Seviye -eq 'err' }).Count; $uyari = $a.Teshis.Count - $hata
    $say = $a.Sayac; $n = { param($k) $(if ($say.ContainsKey($k)) { [int]$say[$k] } else { 0 }) }

    # ---- baslik (kosu panosu ile ayni cerceve) ----
    $sonOl = [double](@($a.Ajanlar | Where-Object { $_.NabizSn -ge 0 } | ForEach-Object { [double]$_.NabizSn }) | Measure-Object -Minimum).Minimum
    $bayatVeri = (-not $a.Ajanlar.Count) -or $sonOl -gt 120
    $sonOlS = $(if ($a.Ajanlar.Count) { " $cFrame·$RS ${cFaint}son olay$RS $(if ($bayatVeri) { $cWarn } else { $cMuted })$(KisaYas $sonOl)$RS" } else { '' })
    $saat = "$cFrame─ $RS$(if ($bayatVeri) { Nabiz $rgbWarn 0.3 } else { Nabiz $rgbOk })●$RS ${cFaint}canlı $cMuted$((Get-Date).ToString('HH:mm:ss'))$RS$sonOlS$cFrame ─╮$RS"
    $L.Add((HLine ($w - (VisLen $saat)) "$cTitle$BOLD◆ Beyin merkez$RS$cFrame · $RS${cMuted}tüm sistem$RS$cFrame · $RS${cMuted}bu makine$RS" '╭' '') + $saat)
    $rozet = $(if ($hata) { "$(BgKaris @(120, 50, 70) @(170, 60, 90) ((([Math]::Sin($script:tik * 0.7) + 1) / 2)))$BOLD 🔴 $hata HATA $RS" } elseif ($a.Onaylar.Count) { "$bgWait$BOLD 🔔 $($a.Onaylar.Count) ONAY BEKLİYOR $RS" } elseif ($uyari) { "$(BgKaris @(95, 78, 38) @(130, 106, 46) ((([Math]::Sin($script:tik * 0.45) + 1) / 2)))$BOLD 🟡 $uyari UYARI $RS" } else { "$bgRun$BOLD 🟢 SAĞLIKLI $RS" })
    $sayac = @()
    foreach ($d in @('calisiyor', 'inceleme', 'engelli', 'duraklatildi', 'bekliyor', 'bosta')) { $v = & $n $d; if ($v -gt 0) { $sayac += "$($durumRenk[$d])$BOLD$v$RS $cMuted$($durumAd[$d])$RS" } }
    if (-not $sayac.Count) { $sayac += "$cFaint etkin ajan yok$RS" }
    $etk = [double[]]@($a.Etkinlik); $etkS = "${cFaint}etkinlik$RS $(Spark $etk 12 $rgbAcc $rgbTeal) ${cFaint}2 sa · $([int]($etk | Measure-Object -Sum).Sum) kayıt$RS"
    $solBas = "$rozet   $($sayac -join "$cFrame · $RS")"; $bosluk = ($w - 4) - (VisLen $solBas) - (VisLen $etkS)
    $L.Add((Row $(if ($bosluk -ge 3) { $solBas + (' ' * $bosluk) + $etkS } else { $solBas }) $w))
    $L.Add((Blank $w))

    # ---- stat kartlari ----
    $calisan = & $n 'calisiyor'; $toplam = $a.Ajanlar.Count
    $lid = @($a.Ajanlar | Where-Object { $_.Tur -eq 'lider' -and $_.Durum -ne 'kapali' }).Count; $isc = @($a.Ajanlar | Where-Object { $_.Tur -eq 'isci' }).Count
    $acikKosu = @($a.Kosular | Where-Object { -not $_.Bitmis }); $kIsci = 0; foreach ($k in $acikKosu) { $kIsci += [int]$(if ($null -ne $k.Calisan) { $k.Calisan } else { 0 }) }
    $etkin = @($a.Ajanlar | Where-Object { $_.Durum -ne 'kapali' })
    $nClaude = @($etkin | Where-Object { $_.Ajan -eq 'claude' }).Count; $nCodex = @($etkin | Where-Object { $_.Ajan -eq 'codex' }).Count
    $sonBiten = @($a.Kosular | Where-Object { $_.Bitmis } | Sort-Object -Property @{ Expression = { $_.KayitGuncel }; Descending = $true } | Select-Object -First 1)
    $kartlar = @(
        @{ t = '🤖 AJANLAR'; l = @("$(GradBar ($(if ($toplam) { $calisan / [double]$toplam } else { 0 })) 12 $rgbTeal $rgbOk)  $cText$BOLD$calisan$RS$cMuted/$toplam çalışıyor$RS",
            "$cPeach${BOLD}Claude$RS $cText$nClaude$RS$cFrame  ·  $RS$cTeal${BOLD}Codex$RS $cText$nCodex$RS",
            "$(Spark ([double[]]$script:gecmis.Cal.ToArray()) 12 $rgbTeal $rgbOk) ${cFaint}eğilim$RS$cMuted · $lid lider$RS$(if ($isc) { "$cMuted · $RS$cTeal$isc işçi$RS" })") }
        @{ t = '🏃 KOŞULAR'; l = @("$cText$BOLD$($acikKosu.Count)$RS$cMuted açık$RS$(if ($a.Kosular.Count - $acikKosu.Count) { "$cFaint · $($a.Kosular.Count - $acikKosu.Count) biten$RS" })",
            $(if ($kIsci) { "$cOk$kIsci işçi çalışıyor$RS" } else { "${cFaint}çalışan işçi yok$RS" }),
            $(if ($sonBiten.Count) { "$cMuted$(Protect-MerkezSatir ([string]$sonBiten[0].RunId) 16)$RS $cFaint· $(KosuRozetMetin ([string]$sonBiten[0].Rozet))$RS" } else { "${cFaint}son 6 saatte biten yok$RS" })) }
        @{ t = $(if ($a.Onaylar.Count) { '🔔 ONAYLAR' } else { '🔔 ONAYLAR ✓' }); r = $(if ($a.Onaylar.Count) { $cWarn } else { '' }); l = @($(if ($a.Onaylar.Count) { "$cWarn$BOLD$($a.Onaylar.Count)$RS$cWarn senden bekleniyor$RS" } else { "$cOk✓ bekleyen yok$RS" }),
            $(if ($a.Onaylar.Count) { "$cText$BOLD$(Protect-MerkezSatir ([string]$a.Onaylar[0].Satir) 30)$RS" } else { "${cFaint}onay gelince burada çıkar$RS" }),
            $(if ($a.Onaylar.Count) { "${cFaint}sohbete tek başına bu satırı yaz$RS" } else { '' })) }
    )
    if ($a.Kaynak -and $a.Kaynak.Ok) {
        $cy = [int]$a.Kaynak.CommitYuzde; $cr = $(if ($cy -ge 85) { $cErr } elseif ($cy -ge 70) { $cWarn } else { $cOk })
        $kartlar += @{ t = "💾 KAYNAK$(if ($cy -ge 70 -and $cy -lt 85) { ' ▲' })"; r = $(if ($cy -ge 85) { $cErr } else { '' }); tr = $(if ($cy -ge 70) { $cWarn } else { '' }); l = @("${cMuted}commit$RS $(IsiBar ($cy / 100.0) 10) $cr$BOLD%$cy$RS$(if ($a.Kaynak.CommitTavanGB) { "$cFaint · $([Math]::Round([double]$a.Kaynak.CommitGB))/$([Math]::Round([double]$a.Kaynak.CommitTavanGB)) GB$RS" })",
            "${cMuted}boş RAM$RS $cText$('{0:0.0}' -f [double]$a.Kaynak.BosRamGB) GB$RS$(if ($a.Kaynak.OnerilenAjan) { "$cFaint · öneri $($a.Kaynak.OnerilenAjan) ajan$RS" })",
            "${cMuted}eğilim$RS $(Spark ([double[]]$script:gecmis.Commit.ToArray()) 10 $rgbOk $rgbErr 100)$cFaint · $(if ([int]$a.Kaynak.BostaOturum) { "$($a.Kaynak.BostaOturum) sessiz oturum" } else { 'sessiz oturum yok' })$RS") }
    }
    if ($a.Maliyet) {
        $mUsd = [double]$a.Maliyet.claudeUsd; $bUsd = [double]$a.Maliyet.buyukBaglamUsd
        $kartlar += @{ t = "💰 MALİYET · $([int]$a.Maliyet.gun) GÜN"; l = @("$cPeach${BOLD}Claude$RS $cText$BOLD`$$([int]$mUsd)$RS$cFaint · API eşdeğeri$RS",
            "$cTeal${BOLD}Codex$RS $cText$(Fmt ([double]$a.Maliyet.codexJeton))$RS$cMuted jeton$RS",
            $(if ($bUsd -gt 0 -and $mUsd -gt 0) { "${cMuted}200K+ bağlam$RS $cWarn`$$([int]$bUsd)$RS$cFaint · %$([int][Math]::Round(100 * $bUsd / $mUsd))$RS" } else { "${cFaint}beyin maliyet$RS" })) }
    }
    $enEski = ''; foreach ($hd in $a.Aktarimlar) { try { $t = [datetime]::Parse([string]$hd.ts); if (-not $enEski -or $t -lt $enEski.T) { $enEski = @{ T = $t; P = [string]$hd.toProject } } } catch { } }
    $kartlar += @{ t = '📋 PANO · AKTARIM'; l = @("$cText$BOLD$($a.Kartlar.Count)$RS$cMuted açık kart$RS$(if (@($a.Kartlar | Where-Object { $_.status -eq 'review' }).Count) { "$cWarn · $(@($a.Kartlar | Where-Object { $_.status -eq 'review' }).Count) incelemede$RS" })",
        "$cText$BOLD$($a.Aktarimlar.Count)$RS$cMuted açık aktarım$RS",
        $(if ($enEski) { "${cFaint}en eski $(KisaYas ((Get-Date) - $enEski.T).TotalSeconds)$(if ($enEski.P) { " · $(Protect-MerkezSatir $enEski.P 16)" })$RS" } else { "${cFaint}bekleyen aktarım yok$RS" })) }
    if ($w -ge 120) { foreach ($ln in (Cards $kartlar $ic)) { $L.Add((Row $ln $w)) } }
    else {
        # dar ekran: alti kartin ozeti tek satir (dikey alan canli bolumlere kalsin)
        # dar ekran: kart ozeti iki satir; deger durum rengiyle (onay sari, sifir yesil)
        $oz1 = @("${cMuted}onay$RS $(if ($a.Onaylar.Count) { "$cWarn$BOLD$($a.Onaylar.Count)$RS" } else { "$cOk" + '0' + "$RS" })")
        if ($a.Kaynak -and $a.Kaynak.Ok) { $cy = [int]$a.Kaynak.CommitYuzde; $oz1 += "${cMuted}commit$RS $(if ($cy -ge 85) { $cErr } elseif ($cy -ge 70) { $cWarn } else { $cText })%$cy$RS" }
        if ($a.Maliyet) { $oz1 += "${cMuted}maliyet $([int]$a.Maliyet.gun) gün$RS $cText`$$([int][double]$a.Maliyet.claudeUsd)$RS" }
        $oz2 = @("${cMuted}ajan$RS $cText$calisan/$toplam$RS", "${cMuted}koşu$RS $cText$($acikKosu.Count)$RS", "${cMuted}pano$RS $cText$($a.Kartlar.Count)$RS", "${cMuted}aktarım$RS $cText$($a.Aktarimlar.Count)$RS")
        $L.Add((Row ($oz1 -join "$cFrame  ·  $RS") $w)); $L.Add((Row ($oz2 -join "$cFrame  ·  $RS") $w))
    }
    $L.Add((Blank $w))

    # ---- SIRADA ----
    $sr = $a.Sirada
    if ($sr) {
        $srr = switch ([string]$sr.Renk) { 'ok' { $cOk } 'warn' { $cWarn } 'err' { $cErr } default { $cText } }
        $bolumBas.Add(@{ Ad = 'SIRADA'; I = $L.Count })
        # uyari/hata/onay: serit nabiz gibi atar (tek hareketli vurgu, dikkat cekmesi gereken yer)
        $vur = $(if ([string]$sr.Renk -eq 'err') { Nabiz $rgbErr 0.8 } elseif ([string]$sr.Renk -eq 'warn') { Nabiz $rgbWarn 0.45 } else { $cAccent })   # onay/hata/uyari: serit ve baslik durum renginde
        $L.Add((HLine $w (Sec '🧭 SIRADA' $vur) '├' '┤'))
        $L.Add((Row "$vur$BOLD▌$RS $srr$BOLD$(Protect-MerkezSatir ([string]$sr.Metin) ($ic - 4))$RS" $w))
        if ($sr.Neden) {
            $nd = Protect-MerkezSatir ([string]$sr.Neden) ($ic - 4)
            # kopyalanacak komut satirin en parlak ogesi
            if ($nd -match '^ilk adım: (beyin [^·]+?)( · (.*))?$') { $ndS = "${cFaint}ilk adım$RS  $cAccent$BOLD$($Matches[1])$RS$(if ($Matches[3]) { "$cFaint  ·  $($Matches[3])$RS" })" } else { $ndS = "$cMuted$nd$RS" }
            $L.Add((Row "$vur▌$RS $ndS" $w))
        }
        $L.Add((Blank $w))
    }

    # ---- ONAY BEKLIYOR ----
    if ($a.Onaylar.Count) {
        $bolumBas.Add(@{ Ad = 'ONAY BEKLİYOR'; I = $L.Count })
        $L.Add((HLine $w (Sec '🔔 ONAY BEKLİYOR' $cWarn) '├' '┤'))
        foreach ($g in $a.Onaylar) { $L.Add((Row "$cWarn$BOLD◐ $(Protect-MerkezSatir $g.Satir 40)$RS   $cMuted$(Protect-MerkezSatir $g.Neden ($ic - 50))$RS" $w)) }
        $L.Add((Row "$cFaint  sohbete yalnız bu satırı yaz (baslat · birlestir · onayla) · onayla için önce bağımsız doğrulama (--verified-by)$RS" $w))
        $L.Add((Blank $w))
    }

    # ---- TESHIS ----
    if ($a.Teshis.Count) {
        $bolumBas.Add(@{ Ad = 'TEŞHİS'; I = $L.Count })
        $L.Add((HLine $w (Sec "🩺 TEŞHİS ($($a.Teshis.Count))" $(if ($hata) { $cErr } else { $cWarn })) '├' '┤'))
        foreach ($t in @(@($a.Teshis | Where-Object { $_.Seviye -eq 'err' }) + @($a.Teshis | Where-Object { $_.Seviye -ne 'err' }) | Select-Object -First 5)) {
            $icn = $(if ($t.Seviye -eq 'err') { '🔴' } else { '🟡' }); $ilk = $true
            foreach ($parcaS in (Sar (Protect-MerkezSatir ([string]$t.Metin) 400) ($ic - 3) 2)) { $L.Add((Row $(if ($ilk) { "$icn $RS$cText$parcaS$RS" } else { "   $cText$parcaS$RS" }) $w)); $ilk = $false }
        }
        if ($a.Teshis.Count -gt 5) { $L.Add((Row "$cFaint +$($a.Teshis.Count - 5) uyarı daha · beyin doktor$RS" $w)) }
        $L.Add((Blank $w))
    }

    # ---- KANATLAR ----
    $aktifMi = { param($g) @($g.Group | Where-Object { $_.Durum -notin @('bosta', 'kapali', 'bitti') }).Count -gt 0 }
    $gruplar = @($a.Ajanlar | Group-Object -Property { $_.Kanat } | Sort-Object -Property @{ Expression = { @($_.Group | Where-Object { $_.Durum -notin @('bosta', 'kapali', 'bitti') }).Count }; Descending = $true }, @{ Expression = { ($_.Group | ForEach-Object { $_.NabizSn } | Measure-Object -Minimum).Minimum } })
    $aktifGrup = @($gruplar | Where-Object { & $aktifMi $_ }); $sakinGrup = @($gruplar | Where-Object { -not (& $aktifMi $_) })
    # @(): tek kanatta $(...) diziyi tek GroupInfo'ya acar ve .Count kanattaki AJAN sayisini verir (iki sutun yanlis acilirdi)
    $gosterGrup = @($(if ($script:hepsi) { $gruplar } else { $aktifGrup }))
    $bolumBas.Add(@{ Ad = 'KANATLAR'; I = $L.Count })
    $L.Add((HLine $w (Sec "🏢 KANATLAR ($($gruplar.Count))") '├' '┤'))
    $iki = ($w -ge 200 -and $gosterGrup.Count -ge 2)   # 170-199 sutunda iki sutun islem balonunu kesiyordu
    $solW = $(if ($iki) { [int][Math]::Floor(($ic - 2) / 2) } else { $ic })
    $bloklar = New-Object System.Collections.Generic.List[object]
    foreach ($g in $gosterGrup) {
        $sirali = @($g.Group | Sort-Object -Property @{ Expression = { $durumSira[[string]$_.Durum] } }, @{ Expression = { $_.Tur -ne 'lider' } }, @{ Expression = { $_.NabizSn } })
        $bloklar.Add(@(@(KanatSatirlari ([string]$g.Name) $sirali $(if ($iki) { $solW - 1 } else { $solW })) + @('')))
    }
    if ($iki) {
        $sol = New-Object System.Collections.Generic.List[string]; $sag = New-Object System.Collections.Generic.List[string]; $hs = 0; $hd = 0
        foreach ($b in $bloklar) { if ($hs -le $hd) { $sol.AddRange([string[]]$b); $hs += $b.Count } else { $sag.AddRange([string[]]$b); $hd += $b.Count } }
        for ($i = 0; $i -lt [Math]::Max($sol.Count, $sag.Count); $i++) {
            $s1 = $(if ($i -lt $sol.Count) { $sol[$i] } else { '' }); $s2 = $(if ($i -lt $sag.Count) { $sag[$i] } else { '' })
            $L.Add((Row (Cols $s1 $s2 $w $solW) $w))
        }
    } else { foreach ($b in $bloklar) { foreach ($s in $b) { $L.Add((Row $s $w)) } } }
    if (-not $gruplar.Count) { $L.Add((Row "${cFaint}son 24 saatte etkin ajan yok$RS" $w)) }
    elseif (-not $gosterGrup.Count) { $L.Add((Row "${cFaint}şu an çalışan ajan yok$RS" $w)) }
    if (-not $script:hepsi -and $sakinGrup.Count) {
        # sigan kadar kanat adi, kalani +N (satir sonunda kesik ad kalmasin)
        $bas = "▢ boşta kanatlar: "; $par = @(); $kalan = $sakinGrup.Count
        foreach ($sg in $sakinGrup) {
            $ad = "$(Protect-MerkezSatir ([string]$sg.Name) 30) $($sg.Count)"; $deneme = @($par) + @($ad)
            $ek = $(if ($kalan -gt 1) { "  ·  +$($kalan - 1)" } else { '' }); if ((VisLen ($bas + ($deneme -join '  ·  ') + $ek)) -gt ($ic - 1)) { break }
            $par = $deneme; $kalan--
        }
        $L.Add((Row "$cFaint▢ boşta kanatlar: $($par -join '  ·  ')$(if ($kalan) { "  ·  +$kalan" })$RS" $w))
    }
    # her kanat blogu bos satirla biter; son blogun bosu bolum araligi olur (iki bos satir ust uste gelmesin)
    if ((Strip $L[$L.Count - 1]) -notmatch '^│[\s│]*│$') { $L.Add((Blank $w)) }
    $script:sec = -1
    for ($i = 0; $i -lt $script:secilebilir.Count; $i++) { if ((AjanAnahtar $script:secilebilir[$i]) -eq $script:secAnahtar) { $script:sec = $i; break } }

    # ---- KOSULAR ----
    if ($a.Kosular.Count) {
        $bolumBas.Add(@{ Ad = 'KOŞULAR'; I = $L.Count })
        $L.Add((HLine $w (Sec "🏃 KOŞULAR ($($a.Kosular.Count))") '├' '┤'))
        $adlar = @('plan', 'başlat', 'topla', 'bütünleştir', 'doğrula', 'ana dala al')
        $kosuSirali = @($a.Kosular | Sort-Object -Property @{ Expression = { $_.Bitmis } }, @{ Expression = { $(if ($_.KayitGuncel) { $_.KayitGuncel } else { $_.Guncel }) }; Descending = $true })
        $acikK = @($kosuSirali | Where-Object { -not $_.Bitmis }); $bitenK = @($kosuSirali | Where-Object { $_.Bitmis })
        $gosterK = @($acikK) + @($bitenK | Select-Object -First $(if ($script:hepsi) { $bitenK.Count } else { 1 }))
        foreach ($k in $gosterK) {
            $rz = $(if ($k.Rozet) { KosuRozet ([string]$k.Rozet) } elseif ($k.Sahipsiz) { KosuRozet 'sahipsiz' } else { KosuRozet '' })
            $sureS = $(if ($k.Sure) { "$cMuted süre$RS $cText$(Kisa ([double]$k.Sure))$RS" } else { '' }) + $(if ($k.Baslangic) { "$cMuted   başladı$RS $cText$(([datetime]$k.Baslangic).ToLocalTime().ToString('HH:mm'))$RS" } else { '' })
            $L.Add((Row "$rz  $cText$BOLD$(Protect-MerkezSatir ([string]$k.RunId) 30)$RS$cFrame · $RS$cMuted$(Protect-MerkezSatir $k.Repo 30)$RS   $sureS" $w))
            # adim cizgisi (kosu panosu ile ayni): tamam ✓ ━, kirik ✕, guncel ▸, bekleyen ○ ╌
            $ok = @($k.Adimlar); $cur = $(if ($null -ne $k.Guncel) { [int]$k.Guncel } else { -1 })
            if ($ok.Count -eq 6) {
                $seg = ''
                for ($i = 0; $i -lt 6; $i++) {
                    # Atlanan: salt okunur inceleme kosusu topla'da biter; sonraki adimlar "beklemiyor", atlandi (–)
                    $s = $(if ($ok[$i]) { "$cOk✓$RS $cMuted$($adlar[$i])$RS" } elseif ($k.Atlanan) { "$cFrame2– $($adlar[$i])$RS" } elseif ($i -eq $cur -and $k.Kirik) { "$cErr$BOLD✕ $($adlar[$i])$RS" } elseif ($i -eq $cur) { "$cAccent$BOLD▸ $($adlar[$i])$RS" } else { "$cFaint○ $($adlar[$i])$RS" })
                    $seg += $s; if ($i -lt 5) { $seg += $(if ($ok[$i]) { " $cOk━$RS " } else { " $cBarOff╌$RS " }) }
                }
                if ($k.Atlanan) { $seg = "$cOk✓$RS $cMuted$($adlar[0])$RS $cOk━$RS $cOk✓$RS $cMuted$($adlar[1])$RS $cOk━$RS $cOk✓$RS $cMuted$($adlar[2])$RS   ${cFaint}salt okunur koşu · bütünleştirme ve birleştirme yok$RS" }
                $L.Add((Row "  $seg" $w))
            }
            # isci cubugu: yesil temiz, sari kismen, kirmizi sorunlu, soluk kalan
            $nW = [Math]::Max(1, [int]$k.Isci); $bw = 14
            # sef kapsadi (integrate --covers): sorunlu sayilmaz, mavi hucre
            $kp = [int]$k.Kapsanan; $tz = [int]$(if ($null -ne $k.Temiz) { $k.Temiz } else { $k.Biten }); $ks = [int]$k.Kismen; $so = [Math]::Max(0, [int]$k.Sorunlu - $kp)
            # en buyuk kalan yontemi: hucre toplami tam $bw olur (Round ile 15/14 tasmasi ve renk kaymasi yok)
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
            $L.Add((Blank $w))
        }
        if ($gosterK.Count -lt $kosuSirali.Count) { $L[$L.Count - 1] = (Row "$cFaint  +$($kosuSirali.Count - $gosterK.Count) biten koşu daha · [a] hepsi$RS" $w); $L.Add((Blank $w)) }
    }

    # ---- PANO | AKTARIMLAR ----
    # Yan yana: pano tarafi %42 (kart satiri kisa, aktarim metni uzun), en az 52 hucre
    # biri bossa yan yana koyma: bos taraf uzun listenin yaninda bos sutun birakir
    $yan = ($w -ge 140 -and $a.Kartlar.Count -gt 0 -and $a.Aktarimlar.Count -gt 0); $kw = $(if ($yan) { [Math]::Max(52, [int][Math]::Floor(($ic - 2) * 0.42)) } else { $ic })
    $pL = New-Object System.Collections.Generic.List[string]; $aL = New-Object System.Collections.Generic.List[string]
    foreach ($kt in @($a.Kartlar | Select-Object -First 6)) {
        $st = [string]$kt.status; $r = switch ($st) { 'blocked' { $cErr } 'review' { $cWarn } 'in_progress' { $cOk } default { $cFaint } }
        $sahip = $(if ($kt.owner -and $kt.owner.agent) { Protect-MerkezSatir ([string]$kt.owner.agent) 10 } else { '' })
        $pL.Add("$r● $(Pad $panoAd[$st] 10)$RS $cText$(Pad (Protect-MerkezSatir ([string]$kt.id) 12) 9)$RS $(if ($sahip) { "$($kimlikRenk[$sahip])$(Pad $sahip 6)$RS " })$cMuted$(Protect-MerkezSatir ([string]$kt.title) 90)$RS")
    }
    if (-not $a.Kartlar.Count) { $pL.Add("$cOk✓$RS$cFaint açık kart yok$RS") } elseif ($a.Kartlar.Count -gt 6) { $pL.Add("$cFaint +$($a.Kartlar.Count - 6) kart · beyin pano list$RS") }
    foreach ($hd in @($a.Aktarimlar | Sort-Object -Property @{ Expression = { [string]$_.ts } } | Select-Object -First 6)) {   # en eski ustte: kapatilacak olan
        $yasSn = -1; try { $yasSn = ((Get-Date) - [datetime]::Parse([string]$hd.ts)).TotalSeconds } catch { }
        $kimden = Protect-MerkezSatir $(if ($hd.from -is [string]) { [string]$hd.from } else { [string]$hd.from.agent }) 8; $kime = Protect-MerkezSatir $(if ($hd.to -is [string]) { [string]$hd.to } else { [string]$hd.to.agent }) 8
        $yon = "$($kimlikRenk[$kimden])$kimden$RS$cFaint→$RS$($kimlikRenk[$kime])$kime$RS"
        $hp = Protect-MerkezSatir ([string]$hd.toProject) 30; $hpS = $(if ($hp) { "$(if ($yasSn -gt 3 * 86400) { $cWarn } else { $cMuted })$hp$RS" } else { "${cFrame2}her yer$RS" })   # -Hedef verilmemis: her projede gorunur
        $eskiMi = $yasSn -gt 3 * 86400; $yasR = $(if ($eskiMi) { "$cWarn$BOLD" } elseif ($yasSn -ge 86400) { $cText } else { $cMuted })
        $hid = [string]$hd.id; $kid = Protect-MerkezSatir $hid.Substring([Math]::Max(0, $hid.Length - 4)) 4   # beyin aktar -Tamam <id> icin ayirt edici kuyruk
        $aL.Add("$(Pad $yon 14) $cFaint$kid$RS $(Pad $hpS 13) $(PadL "$yasR$(KisaYas $yasSn)$RS" 7)  $(KonuAyrinti (Protect-MerkezSatir ([string]$hd.question) 120) $(if ($eskiMi) { $cWarn } else { $cText }))")
    }
    if (-not $a.Aktarimlar.Count) { $aL.Add("$cOk✓$RS$cFaint bekleyen aktarım yok$RS") } elseif ($a.Aktarimlar.Count -gt 6) { $aL.Add("$cFaint +$($a.Aktarimlar.Count - 6) daha · beyin aktar$RS") }
    $bolumBas.Add(@{ Ad = 'PANO · AKTARIMLAR'; I = $L.Count })
    if ($yan) {
        $solEt = Sec "📋 PANO ($($a.Kartlar.Count) açık)"
        $L.Add((HLine $w ($solEt + "$cFrame " + ('─' * [Math]::Max(1, $kw - (VisLen $solEt) - 2)) + "┬─ $RS" + (Sec "📨 AKTARIMLAR ($($a.Aktarimlar.Count) açık)")) '├' '┤'))
        for ($i = 0; $i -lt [Math]::Max($pL.Count, $aL.Count); $i++) {
            $s1 = $(if ($i -lt $pL.Count) { $pL[$i] } else { '' }); $s2 = $(if ($i -lt $aL.Count) { $aL[$i] } else { '' })
            $L.Add((Row (Cols $s1 $s2 $w $kw) $w))
        }
    } else {
        $L.Add((HLine $w (Sec "📋 PANO ($($a.Kartlar.Count) açık)") '├' '┤')); foreach ($s in $pL) { $L.Add((Row $s $w)) }
        $L.Add((HLine $w (Sec "📨 AKTARIMLAR ($($a.Aktarimlar.Count) açık)") '├' '┤')); foreach ($s in $aL) { $L.Add((Row $s $w)) }
    }

    # ---- SON OLAYLAR: ekranda kalan bos yuksekligi doldurur; hicbir bolumu disari itmez ----
    $olaylar = $(if ($a.Olaylar) { [object[]]$a.Olaylar.ToArray() } else { @() })   # @() generic List uzerinde PS 5.1de firlatir
    if ($olaylar.Count) {
        $bosSatir = $(if ($Tek -and $Yukseklik -le 0) { 10 } else { ($h - 1) - $L.Count - 1 - 2 })   # -1 alt cerceve, -2 baslik + bosluk
        $nOl = [Math]::Min($olaylar.Count, [Math]::Min(14, $bosSatir))
        if ($nOl -ge 3) {
            $bolumBas.Add(@{ Ad = 'SON OLAYLAR'; I = $L.Count })
            $L.Add((HLine $w ("$(Sec '📜 SON OLAYLAR')$cFaint  motor makbuzları · beyin makbuz$RS") '├' '┤'))
            $olRenk = @{ ok = $cOk; warn = $cWarn; err = $cErr; accent = $cAccent; teal = $cTeal; muted = $cMuted }
            foreach ($ol in @($olaylar | Select-Object -First $nOl)) {
                $r = $olRenk[[string]$ol.Renk]; if (-not $r) { $r = $cMuted }
                $yasS = KisaYas ((Get-Date) - $ol.Zaman).TotalSeconds
                $ajR = $kimlikRenk[[string]$ol.Ajan]; if (-not $ajR) { $ajR = $cMuted }
                $sag = $(if ($ol.Kanat) { "$cFaint · $(Protect-MerkezSatir ([string]$ol.Kanat) 24)$RS" } else { '' })
                $adetS = $(if ($ol.Adet -gt 1) { "$cFaint ×$($ol.Adet)$RS" } else { '' })
                $L.Add((Row "$cFaint$($ol.Zaman.ToString('HH:mm'))$RS $cFrame2$(PadL $yasS 6)$RS  $ajR$(Pad (Protect-MerkezSatir ([string]$ol.Ajan) 8) 7)$RS $r$($ol.Ikon) $(Protect-MerkezSatir ([string]$ol.Metin) 140)$RS$adetS$sag" $w))
            }
        }
    }

    # ---- alt cerceve: tuslar ----
    $veriYas = ((Get-Date) - $script:sonHizli).TotalSeconds
    $msj = $(if ($script:mesaj -and ((Get-Date) - $script:mesajZaman).TotalSeconds -lt 6) { "$cWarn$($script:mesaj)$RS$cFrame  ─  $RS" } else { '' })
    $durumS = $(if ($script:cizimHata) { "$cFrame  ─  $RS$cErr✕ çizim hatası $($script:cizimHata)$RS" } elseif ($veriYas -gt 5) { "$cFrame  ─  $RS$cWarn veri $([int]$veriYas) sn önce$RS" } else { '' })
    $gizliAjan = @($a.Ajanlar | Where-Object { $_.Durum -in @('bosta', 'kapali', 'bitti') }).Count
    $aEtiket = $(if ($script:hepsi) { 'aktifler' } elseif ($gizliAjan) { "hepsi (+$gizliAjan boşta)" } else { 'hepsi' })
    $tk = { param($k, $e) "$cAccent$BOLD$k$RS $cFaint$e$RS" }; $ay = "$cFrame  ·  $RS"
    $tus = "$msj$(& $tk 'a' $aEtiket)$ay$(& $tk '↑↓' 'seç')$ay$(& $tk '⏎' 'odak')$ay$(& $tk 'p' 'koşu panosu')$ay$(& $tk 'r' 'tazele')$ay$(& $tk 'q' 'çık')$durumS"
    $alt = (HLine $w $tus '╰' '╯')
    $maks = $(if ($Tek -and $Yukseklik -le 0) { 100000 } else { [Math]::Max(5, $h - 1) })
    if ($L.Count -gt $maks - 1) {
        $kes = $maks - 2; $gizli = $L.Count - $kes
        $gizliBolum = @($bolumBas | Where-Object { $_.I -ge $kes } | ForEach-Object { $_.Ad })
        $L = [System.Collections.Generic.List[string]]@($L | Select-Object -First $kes)
        $L.Add((Row "$cWarn▼ $gizli satır ekrana sığmadı$RS$(if ($gizliBolum.Count) { "$cMuted · gizlenen: $($gizliBolum -join ', ')$RS" })$cFaint · pencereyi büyüt ya da [a] ile yalnız aktifler$RS" $w))
    }
    $L.Add($alt)
    $sb = New-Object Text.StringBuilder; [void]$sb.Append("$ESC[H")
    foreach ($ln in $L) { [void]$sb.Append($ln).Append($RS); if ((VisLen $ln) -lt $w) { [void]$sb.Append("$ESC[K") }; [void]$sb.Append("`n") }   # tam genislikte ESC[K sag kenari siler
    [void]$sb.Append("$ESC[J")
    $kare = $sb.ToString(); if ($kare -ne $script:lastFrame) { $script:lastFrame = $kare; [Console]::Write($kare) }
}

function CizimSonuc {
    try { Ciz; if ($script:cizimHata) { $script:cizimHata = 0; $script:lastFrame = '' }; $script:sonCizim = Get-Date }
    catch {
        $script:cizimHata++; $script:cizimMesaj = (Protect-MerkezSatir ([string]$_.Exception.Message) 120)
        try { $hh = $Host.UI.RawUI.WindowSize.Height; [Console]::Write("$ESC[$hh;1H$cErr▲ merkez $(if ($script:cizimHata -ge 5) { 'BOZUK' } else { 'SORUNLU' }) · $($script:cizimHata) kez çizilemedi · son başarılı $(Kisa ((Get-Date) - $script:sonCizim).TotalSeconds) önce · $($script:cizimMesaj)$RS$ESC[K") } catch { }
    }
}

function SeciliAjan { if ($script:sec -ge 0 -and $script:sec -lt $script:secilebilir.Count) { return $script:secilebilir[$script:sec] }; return $null }
function SecimKaydir([int]$adim) {
    $n = $script:secilebilir.Count; if (-not $n) { return }
    $i = $(if ($script:sec -lt 0) { 0 } else { [Math]::Max(0, [Math]::Min($n - 1, $script:sec + $adim)) })
    $script:sec = $i; $script:secAnahtar = AjanAnahtar $script:secilebilir[$i]
}
function Odak {
    $ag = SeciliAjan; if (-not $ag) { return }
    $anahtar = AjanAnahtar $ag
    if ($ag.Tur -eq 'isci' -and $script:acik -ne $anahtar) {
        $sn = Open-BeyinTakimPanel -Paths $p -RunId $ag.Kosu -TaskIds @([string]$ag.Ad)
        $script:mesaj = $(if ($sn.Ok) { "$($ag.Ad) paneli açıldı" } else { "panel açılamadı: $($sn.Neden)" }); $script:mesajZaman = Get-Date
    }
    $script:acik = $(if ($script:acik -eq $anahtar) { '' } else { $anahtar })
}

# ---------- kendini yenileme (takim-izle ile ayni) ----------
# Dosya basina damga (eskiden yalniz merkez.ps1'in damgasi vardi; veri/balon ondan yeniyse her acilista yeniden
# yukleniyor ve ic ice surec birikiyordu). Yeniden yukleme ayni konsolda yeni sureci baslatir; bu surec onu bekler
# ve o cikinca cikar (bir yeniden yukleme = bir bekleyen ebeveyn; damga yalniz gercek degisiklikte tetikler).
$izlenen = @($PSCommandPath, (Join-Path $PSScriptRoot 'merkez-veri.ps1'), $balonYol, (Join-Path $Vault 'motor\hooks\lib.ps1'))
$damga = @{}; foreach ($f in $izlenen) { try { if (Test-Path -LiteralPath $f) { $damga[$f] = (Get-Item -LiteralPath $f).LastWriteTimeUtc } } catch { } }
$selfAt = Get-Date
function YeniSurumVar {
    if (((Get-Date) - $script:selfAt).TotalSeconds -lt 5) { return $false }
    $script:selfAt = Get-Date
    foreach ($f in $izlenen) {
        try {
            if (-not (Test-Path -LiteralPath $f) -or -not $damga.ContainsKey($f)) { continue }
            $t = (Get-Item -LiteralPath $f).LastWriteTimeUtc
            if ($t -le $damga[$f] -or ((Get-Date).ToUniversalTime() - $t).TotalSeconds -lt 2) { continue }
            $e = $null; [void][System.Management.Automation.Language.Parser]::ParseFile($f, [ref]$null, [ref]$e)
            if ($e -and $e.Count) { $damga[$f] = $t; continue }
            return $true
        } catch { }
    }
    return $false
}

$yenidenYukle = $false
try {
Tazele $true
if ($Tek) { $script:hepsi = -not $Aktifler; Ciz; [Console]::Write("$RS`n"); exit 0 }
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
            $kk = [Console]::ReadKey($true)
            switch ($kk.Key) {
                'UpArrow'   { SecimKaydir -1 }
                'DownArrow' { SecimKaydir 1 }
                'Enter'     { Odak }
                default {
                    switch ([string]$kk.KeyChar) {
                        'q' { $quit = $true } 'a' { $script:hepsi = -not $script:hepsi } 'r' { [void]$script:onb.Remove('ts:Aktarimlar'); [void]$script:onb.Remove('ts:Kaynak'); Tazele $true }   # r: kademeli kaynaklar da hemen
                        'j' { SecimKaydir 1 } 'k' { SecimKaydir -1 }
                        'p' {
                            $ag = SeciliAjan
                            if ($ag -and $ag.Kosu) { $sn = Open-BeyinTakimPanel -Paths $p -RunId $ag.Kosu -TaskIds @('pano'); $script:mesaj = $(if ($sn.Ok) { "koşu panosu açıldı ($($ag.Kosu))" } else { "açılamadı: $($sn.Neden)" }) }
                            else { $script:mesaj = 'seçili ajan bir koşuya ait değil' }
                            $script:mesajZaman = Get-Date
                        }
                    }
                }
            }
            $script:lastFrame = ''
        }
    } catch { }
    Start-Sleep -Milliseconds 120   # tarama/nabiz/spinner akici; kare degismediyse yazilmaz
}
} finally {
    try { [Console]::CursorVisible = $true } catch { }
    if (-not $Tek) { [Console]::Write("$RS$ESC[2J$ESC[H") } else { [Console]::Write($RS) }
}
if ($yenidenYukle) { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath -Vault $Vault; exit $LASTEXITCODE }
