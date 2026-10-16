# beyin-ciz.ps1 - Beyin terminal panellerinin ORTAK cizim katmani (merkez.ps1 ve takim-izle.ps1 nokta-kaynak eder).
# Yalniz islev ve degisken tanimlar; G/C yapmaz. Palet ANLAM ROLLERI olarak tek yerde (Aurora); eski degisken adlari
# ($cText, $cOk, $bgSel...) bu rollerin takma adidir. Genislik olcusu, kesme, cerceve, kartlar, cubuklar, animasyon,
# parlama/yumusak gecis ve simge politikasi buradadir; panel dosyalari yalniz kendi bolumlerini cizer.
# Surum el sikismasi: arayan $BeyinCizSurum'u kendi bekledigiyle karsilastirir (yayin dosyalari sirayla yazar).
$BeyinCizSurum = 1
$ESC = [char]27

# ---------- palet: Aurora (anlam rolleri) ----------
# Zemin ustunde olculmus kontrast (WCAG): Metin 15.4, Soluk 6.1, Sonuk 4.3, Vurgu 9.8, Ok 12.1, Uyari 11.0, Hata 6.8, Bilgi 7.2.
# Cerceve ~2.4:1: ince ama secilir (52,63,88 ~1.7:1 ile dikey cizgi gercek Windows Terminal ekraninda kayboluyordu).
$CizRgb = @{
    Zemin = @(15, 20, 32); Cerceve = @(70, 84, 115); Metin = @(230, 235, 245); Soluk = @(138, 149, 171)
    Vurgu = @(124, 196, 255); Baslik = @(169, 184, 255); Ok = @(110, 231, 183); Uyari = @(251, 191, 36)
    Hata = @(251, 113, 133); Bilgi = @(96, 165, 250); Claude = @(255, 179, 138); Codex = @(94, 234, 212); Kota = @(196, 167, 255)
}
function CizKarisRgb([int[]]$x, [int[]]$y, [double]$t) {
    $t = [Math]::Max([double]0, [Math]::Min([double]1, $t))
    return @([int]($x[0] + ($y[0] - $x[0]) * $t), [int]($x[1] + ($y[1] - $x[1]) * $t), [int]($x[2] + ($y[2] - $x[2]) * $t))
}
$CizRgb.Sonuk = CizKarisRgb $CizRgb.Soluk $CizRgb.Zemin 0.20
$CizRgb.Cerceve2 = CizKarisRgb $CizRgb.Cerceve $CizRgb.Soluk 0.30
$CizRgb.Iz = CizKarisRgb $CizRgb.Cerceve $CizRgb.Zemin 0.45      # bos cubuk hucresi: zeminde secilir, dolu kisimla karismaz
$CizRgb.Ak = @(245, 248, 255)                                       # tarama basinin parlakligi

function FG([int]$r, [int]$g, [int]$b) { return "$ESC[38;2;$r;$g;${b}m" }
function BG([int]$r, [int]$g, [int]$b) { return "$ESC[48;2;$r;$g;${b}m" }
function CizFG([int[]]$c) { return (FG $c[0] $c[1] $c[2]) }
function CizBG([int[]]$c) { return (BG $c[0] $c[1] $c[2]) }
function CizRozetBG([int[]]$c, [double]$t = 0.68) { return (CizBG (CizKarisRgb $c $CizRgb.Zemin $t)) }

# Zemin kipi: 'kapali' (terminal zemini), 'boya' (her sifirlama Aurora zeminini yeniden basar), 'osc' (Windows Terminal
# sekme zeminini OSC 11 ile bir kez boyar; cikista OSC 111 geri alir). Arayan Set-CizZemin ile secer.
$script:CizZemin = 'kapali'
$BOLD = "$ESC[1m"
$RS = "$ESC[0m"
function Set-CizZemin([string]$Kip) {
    $script:CizZemin = $Kip
    $script:RS = $(if ($Kip -eq 'boya') { "$ESC[0m$(CizBG $CizRgb.Zemin)" } else { "$ESC[0m" })
    Set-Variable -Name RS -Value $script:RS -Scope Script
}
function Get-CizOscAc { return "$ESC]11;#{0:x2}{1:x2}{2:x2}$ESC\" -f $CizRgb.Zemin[0], $CizRgb.Zemin[1], $CizRgb.Zemin[2] }
function Get-CizOscKapat { return "$ESC]111$ESC\" }

$cText = CizFG $CizRgb.Metin; $cMuted = CizFG $CizRgb.Soluk; $cFaint = CizFG $CizRgb.Sonuk
$cFrame = CizFG $CizRgb.Cerceve; $cFrame2 = CizFG $CizRgb.Cerceve2; $cTitle = CizFG $CizRgb.Baslik; $cAccent = CizFG $CizRgb.Vurgu
$cOk = CizFG $CizRgb.Ok; $cWarn = CizFG $CizRgb.Uyari; $cErr = CizFG $CizRgb.Hata; $cSky = CizFG $CizRgb.Bilgi; $cInfo = $cSky
$cPeach = CizFG $CizRgb.Claude; $cTeal = CizFG $CizRgb.Codex; $cMauve = CizFG $CizRgb.Kota
$cIz = CizFG $CizRgb.Iz; $cBarOff = $cFrame2
# Rozet zeminleri: durum renginin zemine karistirilmis koyu tonu + parlak metin (terminal varsayilan rengine kalmaz)
$bgRun = (CizRozetBG $CizRgb.Ok) + $cText; $bgIdle = (CizRozetBG $CizRgb.Uyari) + $cText; $bgPart = $bgIdle
$bgDone = (CizRozetBG $CizRgb.Vurgu) + $cText; $bgBad = (CizRozetBG $CizRgb.Hata) + $cText; $bgWait = (CizRozetBG $CizRgb.Baslik 0.78) + $cText
$bgInfo = (CizRozetBG $CizRgb.Bilgi) + $cText
$bgSel = CizBG (CizKarisRgb $CizRgb.Vurgu $CizRgb.Zemin 0.84)
$rgbOk = $CizRgb.Ok; $rgbWarn = $CizRgb.Uyari; $rgbErr = $CizRgb.Hata; $rgbTeal = $CizRgb.Codex; $rgbAcc = $CizRgb.Vurgu
$rgbIz = $CizRgb.Iz; $rgbAk = $CizRgb.Ak; $rgbInfo = $CizRgb.Bilgi; $rgbZemin = $CizRgb.Zemin
$CizSpin = @('⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏'); $spin = $CizSpin

# ---------- simge politikasi ----------
# Windows Terminal'de genisligi belirsiz BMP simgeleri (U+26A0 U+2714 U+2716 U+25B6 U+23F8 U+2699 U+231A U+231B U+25C0 ve U+FE0F secicisi) 2 hucre cizilip yanindaki harfe
# biniyordu; YASAK. Renkli emoji (U+1F000 ustu, vekil cift = 2 hucre, VisLen 2 sayar) yalniz BOLUM/KART BASLIGINDA.
# Satir ici durum her yerde tek hucreli renkli simge: CizGlif.
$CizGlif = @{ ok = '✓'; hata = '✕'; uyari = '▲'; bilgi = '●'; oynat = '▸'; duraklat = '‖'; yarim = '◐'; bekle = '◌'; bos = '○'
              nokta = '●'; saat = '◷'; aktar = '⇄'; yasak = '⊘'; liste = '▤'; elmas = '◆'; kalem = '✎'; kanat = '▣'; sakin = '▢' }
$CizYasakRx = [regex]'[\u26A0\u2714\u2716\u25B6\u25C0\u23F8\u2699\u231A\u231B\uFE0F]'
# izinli: ASCII + Latin (Turkce), genel noktalama, oklar, matematik, teknik (⏎), kutu, blok, geometrik, ✓ ✕ ✎, Braille, vekil cift
$CizIzinliRx = [regex]'^[\u0000-\u024F\u2000-\u206F\u2190-\u21FF\u2200-\u22FF\u2300-\u23CF\u2500-\u25FF\u2713\u2715\u270E\u2800-\u28FF\uD800-\uDFFF]*$'

# ---------- metin olcusu (genis karakter + ANSI guvenli) ----------
# Genislik = uzunluk + genis karakter sayisi (vekil cift zaten 2 birim = 2 hucre). Cut ANSI disi parcalari toptan keser,
# yalniz genis karakter ya da vekil cift iceren parcada tek tek yurur; vekil cifti asla ortadan bolmez.
$rxAnsi = [regex]"$ESC\[[0-9;?]*[A-Za-z]|$ESC\][^$ESC\a]*(?:$ESC\\|\a)"
$rxGenis = [regex]'[\u1100-\u115F\u2E80-\uA4CF\uAC00-\uD7A3\uF900-\uFAFF\uFE30-\uFE4F\uFF00-\uFF60\uFFE0-\uFFE6]'
$rxGenisVeyaVekil = [regex]'[\u1100-\u115F\u2E80-\uA4CF\uAC00-\uD7A3\uF900-\uFAFF\uFE30-\uFE4F\uFF00-\uFF60\uFFE0-\uFFE6\uD800-\uDFFF]'
# Ajan/veri metni icin: BMP emoji (Windows Terminal 2 hucre cizer, olcu 1 sayar) guvenli simgeye, sifir genislikli
# karakterler (\uFE0F secici, ZWJ, ZW bosluklar, birlesik isaretler) silinir; boylece balon ve adim satirlari tasmaz.
$rxCizEmojiBmp = [regex]'[\u231A\u231B\u23E9-\u23FA\u2600-\u270D\u270F-\u2712\u2717-\u27BF\u2B00-\u2BFF]'
$rxCizSifir = [regex]'[\u200B-\u200F\uFE0E\uFE0F\u0300-\u036F\u20D0-\u20FF]'
function Get-CizGuvenliMetin([string]$s) {
    if (-not $s) { return $s }
    $s = $rxCizSifir.Replace($s, '')
    $s = $s -replace '[\u2705\u2714]', '✓' -replace '[\u274C\u274E\u2716]', '✕' -replace '\u26A0', '▲' -replace '\u25B6', '▸'
    return $rxCizEmojiBmp.Replace($s, '•')
}
function Strip([string]$s) { return $rxAnsi.Replace($s, '') }
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
                    $cw = $(if ($vek) { 2 } elseif ([char]::IsSurrogate($seg[$i])) { 1 } elseif ($rxGenis.IsMatch([string]$seg[$i])) { 2 } else { 1 })
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
function Pad([string]$s, [int]$w) { $v = VisLen $s; if ($v -le $w) { return $s + (' ' * ($w - $v)) }; $s = Cut $s $w; return $s + (' ' * [Math]::Max(0, $w - (VisLen $s))) }
function PadL([string]$s, [int]$w) { $s = Cut $s $w; return (' ' * [Math]::Max(0, $w - (VisLen $s))) + $s }
function CutLeft([string]$s, [int]$w) {
    # duz metni SOLDAN keser (yol gibi: sonu onemli). Genislige duyarli.
    if ($w -le 0) { return '' }; if ((VisLen $s) -le $w) { return $s }
    $t = Strip $s; $i = $t.Length; $vis = 1
    while ($i -gt 0) { $c = $t[$i - 1]; $cw = $(if ([char]::IsLowSurrogate($c) -and $i -ge 2) { 2 } elseif ($rxGenis.IsMatch([string]$c)) { 2 } else { 1 }); if ($vis + $cw -gt $w) { break }; $vis += $cw; $i -= $(if ($cw -eq 2 -and [char]::IsLowSurrogate($c)) { 2 } else { 1 }) }
    return '…' + $t.Substring($i)
}
function CutWord([string]$s, [int]$w) {
    # sozcuk sinirinda keser (sigmazsa duz keser); genislige duyarli
    if ((VisLen $s) -le $w) { return $s }
    $k = Cut $s $w; $d = Strip $k; $d = $d.Substring(0, [Math]::Max(0, $d.Length - 1)); $sp = $d.LastIndexOf(' ')
    if ($sp -gt [int]($w * 0.6)) { return $d.Substring(0, $sp).TrimEnd() + '…' }
    return $k
}
function Sar([string]$metin, [int]$gen, [int]$maks = 2) {
    # Duz metni sozcuk sinirindan $gen genisliginde en cok $maks satira boler; sigmayan son satir kesilir.
    $sat = New-Object System.Collections.Generic.List[string]; $cur = ''
    foreach ($s in ($metin -split ' ')) {
        if (-not $cur) { $cur = $s; continue }
        if ((VisLen "$cur $s") -le $gen) { $cur = "$cur $s" } else { $sat.Add($cur); $cur = $s }
    }
    if ($cur) { $sat.Add($cur) }
    for ($i = 0; $i -lt $sat.Count; $i++) { if ((VisLen $sat[$i]) -gt $gen) { $sat[$i] = Cut $sat[$i] $gen } }   # tek sozcuk satirdan uzunsa
    if ($sat.Count -gt $maks) { $son = ($sat.GetRange($maks - 1, $sat.Count - $maks + 1) -join ' '); $sat = $sat.GetRange(0, $maks - 1); $sat.Add((Cut $son $gen)) }
    return ,$sat
}
function Kisa([double]$sn) {
    if ($sn -lt 0) { return '—' }; if ($sn -lt 60) { return "$([int]$sn) sn" }; if ($sn -lt 3600) { return "$([int][Math]::Floor($sn / 60)) dk" }
    if ($sn -lt 86400) { return "$([int][Math]::Floor($sn / 3600)) sa $([int][Math]::Floor(($sn % 3600) / 60)) dk" }; return "$([int][Math]::Floor($sn / 86400)) gün"
}
function KisaYas([double]$sn) {
    # liste sutunu icin tek birimli yas (sabit genislikte kesilmesin): 45 sn, 12 dk, 13 sa, 3 gün
    if ($sn -lt 0) { return '—' }; if ($sn -lt 60) { return "$([int]$sn) sn" }; if ($sn -lt 3600) { return "$([int][Math]::Floor($sn / 60)) dk" }
    if ($sn -lt 86400) { return "$([int][Math]::Floor($sn / 3600)) sa" }; return "$([int][Math]::Floor($sn / 86400)) gün"
}
function RolTr([string]$r) {
    switch ($r) {
        'root_cause_debugger' { 'hata ayıklayıcı' } 'docs_author' { 'belge yazarı' } 'qa_lead' { 'QA lideri' } 'spec_author' { 'spek yazarı' }
        'test_verifier' { 'doğrulayıcı' } 'code_mapper' { 'kod haritacısı' } 'code_reviewer' { 'kod incelemeci' } 'security_auditor' { 'güvenlik denetçisi' }
        'frontend_verifier' { 'arayüz doğrulayıcı' } 'design_reviewer' { 'tasarım incelemeci' } 'performance_auditor' { 'performans denetçisi' }
        'docs_researcher' { 'belge araştırmacısı' } 'engineering_planner' { 'mühendislik planlayıcı' } 'release_verifier' { 'sürüm doğrulayıcı' }
        'mcp_integrator' { 'MCP bütünleştirici' } 'devex_auditor' { 'geliştirici deneyimi' } 'codex_doctor' { 'Codex doktoru' }
        'context_architect' { 'bağlam mimarı' } 'product_strategist' { 'ürün stratejisti' } 'prompt_architect' { 'istem mimarı' }
        'google_seo_auditor' { 'SEO denetçisi' } '' { '' } default { $r -replace '_', ' ' }
    }
}

# ---------- renk karisimi (onbellekli: kare basina yuzlerce FG cagrisi yerine sozluk) ----------
$script:CizKarisOnb = @{}
function Karis([int[]]$x, [int[]]$y, [double]$t) {
    $q = [int][Math]::Round([Math]::Max([double]0, [Math]::Min([double]1, $t)) * 48)
    $k = "f$($x[0]),$($x[1]),$($x[2])|$($y[0]),$($y[1]),$($y[2])|$q"
    $v = $script:CizKarisOnb[$k]; if ($v) { return $v }
    $v = CizFG (CizKarisRgb $x $y ($q / 48.0)); $script:CizKarisOnb[$k] = $v; return $v
}
function BgKaris([int[]]$x, [int[]]$y, [double]$t) {
    $q = [int][Math]::Round([Math]::Max([double]0, [Math]::Min([double]1, $t)) * 48)
    $k = "b$($x[0]),$($x[1]),$($x[2])|$($y[0]),$($y[1]),$($y[2])|$q"
    $v = $script:CizKarisOnb[$k]; if ($v) { return $v }
    $v = CizBG (CizKarisRgb $x $y ($q / 48.0)); $script:CizKarisOnb[$k] = $v; return $v
}

# ---------- cubuklar ve canli cizim ----------
function Bar([double]$oran, [int]$gen, [string]$renk) {
    $oran = [Math]::Max([double]0, [Math]::Min([double]1, $oran)); $dolu = [int][Math]::Round($oran * $gen)
    return "$renk" + ('█' * $dolu) + "$cIz" + ('█' * ($gen - $dolu)) + $RS
}
function MiniBar([double]$oran, [int]$gen, [string]$renk) { return (Bar $oran $gen $renk) }   # bos kisim koyu iz (░ koyu zeminde gorunmuyordu)
function GradBar([double]$oran, [int]$gen, [int[]]$c1, [int[]]$c2) {
    # dolu hucreler c1 -> c2 renk gecisli, bos kisim koyu iz
    $oran = [Math]::Max([double]0, [Math]::Min([double]1, $oran)); $on = [int][Math]::Round($oran * $gen); $sb = ''
    for ($i = 0; $i -lt $on; $i++) { $sb += (Karis $c1 $c2 ($(if ($gen -gt 1) { $i / [double]($gen - 1) } else { 0 }))) + '█' }
    return $sb + "$cIz$('█' * ($gen - $on))$RS"
}
function IsiBar([double]$oran, [int]$gen) {
    # kullanim cubugu: hucre konumuna gore yesil -> sari -> kirmizi (doluluk arttikca isinir)
    $oran = [Math]::Max([double]0, [Math]::Min([double]1, $oran)); $on = [int][Math]::Round($oran * $gen); $sb = ''
    for ($i = 0; $i -lt $on; $i++) { $t = $(if ($gen -gt 1) { $i / [double]($gen - 1) } else { 0 }); $sb += $(if ($t -lt 0.6) { Karis $rgbOk $rgbWarn ($t / 0.6) } else { Karis $rgbWarn $rgbErr (($t - 0.6) / 0.4) }) + '█' }
    return $sb + "$cIz$('█' * ($gen - $on))$RS"
}
function Tarama([int]$gen, [int]$faz, [int[]]$c) {
    # gidip gelen parlak bas + sonen kuyruk: "canli calisiyor" gostergesi (her ajan kendi fazinda)
    $yol = [Math]::Max(1, 2 * ($gen - 1)); $k = $faz % $yol; $pos = $(if ($k -lt $gen) { $k } else { $yol - $k }); $sb = ''
    for ($i = 0; $i -lt $gen; $i++) {
        $uz = [Math]::Abs($i - $pos)
        $sb += $(switch ($uz) { 0 { Karis $c $rgbAk 0.45 } 1 { Karis $c $c 0 } 2 { Karis $c $rgbIz 0.55 } default { $cIz } }) + '━'
    }
    return "$sb$RS"
}
function Spark([double[]]$v, [int]$gen, [int[]]$c1, [int[]]$c2, [double]$maks = -1) {
    # mini grafik: son $gen deger, ▁..█ yukseklik; renk yukseklige gore c1 -> c2. Sifir/eksik deger koyu taban cizgisi.
    $bl = @('▁', '▂', '▃', '▄', '▅', '▆', '▇', '█'); if ($v.Count -gt $gen) { $v = $v[($v.Count - $gen)..($v.Count - 1)] }
    $m = $maks; if ($m -le 0) { $m = 0.0; foreach ($x in $v) { if ($x -gt $m) { $m = $x } } }; $sb = "$cIz$('▁' * [Math]::Max(0, $gen - $v.Count))"
    foreach ($x in $v) {
        if ($m -le 0 -or $x -le 0) { $sb += "$cIz▁"; continue }
        $t = [Math]::Min(1.0, $x / $m); $k = [int][Math]::Round($t * 7)
        $sb += (Karis $c1 $c2 $t) + $bl[$k]
    }
    return "$sb$RS"
}
function Nabiz([int[]]$c, [double]$hiz = 0.55) { return (Karis $rgbIz $c (0.35 + 0.65 * (([Math]::Sin($script:tik * $hiz) + 1) / 2))) }

# ---------- hareket durumu: parlama ve yumusak gecis ----------
# Parlama: bir anahtarin imzasi ILK goruldukten SONRA degisirse 2.5 sn sonen vurgu (ilk okumada hicbir sey parlamaz).
function Set-CizFlas([hashtable]$Durum, [string]$Anahtar, [string]$Imza, [datetime]$Simdi, [bool]$YeniParlar = $false) {
    # $YeniParlar: tohumlama (ilk okuma) bittikten sonra HIC gorulmemis anahtar da parlar (yeni olay, yeni onay)
    $e = $Durum[$Anahtar]
    if ($null -eq $e) { $Durum[$Anahtar] = @{ Imza = $Imza; Zaman = $(if ($YeniParlar) { $Simdi } else { [datetime]::MinValue }) }; return $YeniParlar }
    if ($e.Imza -ne $Imza) { $e.Imza = $Imza; $e.Zaman = $Simdi; return $true }
    return $false
}
function Get-CizFlasOran([hashtable]$Durum, [string]$Anahtar, [datetime]$Simdi, [int]$Ms = 2500) {
    $e = $Durum[$Anahtar]; if ($null -eq $e -or $e.Zaman -eq [datetime]::MinValue) { return 0.0 }
    $g = ($Simdi - $e.Zaman).TotalMilliseconds; if ($g -lt 0 -or $g -ge $Ms) { return 0.0 }
    $x = 1.0 - $g / $Ms; return $x * $x   # sonerken yavaslar
}
# Yumusak gecis: gosterilen deger hedefe her karede kalan farkin $Adim kadarini yaklasir (cubuk ziplamaz, dolar).
function Get-CizTween([hashtable]$Durum, [string]$Anahtar, [double]$Hedef, [double]$Adim = 0.35) {
    if (-not $Durum.ContainsKey($Anahtar)) { $Durum[$Anahtar] = $Hedef; return $Hedef }
    $v = [double]$Durum[$Anahtar]; $d = $Hedef - $v
    if ([Math]::Abs($d) -lt 0.004) { $Durum[$Anahtar] = $Hedef; return $Hedef }
    $v += $d * $Adim; $Durum[$Anahtar] = $v; return $v
}

# ---------- cerceve ----------
function HLine([int]$w, [string]$label, [string]$left, [string]$right) {
    $lab = $(if ($label) { " $label$cFrame " } else { '' })
    $fill = $w - 2 - (VisLen $lab) - $(if ($right) { 1 } else { 0 }); if ($fill -lt 0) { $fill = 0 }
    return "$cFrame$left─$lab$('─' * $fill)$right$RS"
}
function Row([string]$c, [int]$w) { return "$cFrame│$RS " + (Pad $c ($w - 4)) + " $cFrame│$RS" }
function Blank([int]$w) { return (Row '' $w) }
function Cols([string]$a, [string]$b, [int]$w, [int]$solW) { return (Pad $a ($solW - 1)) + " $cFrame│ $RS" + (Pad $b ($w - 4 - $solW - 2)) }
function Sec([string]$ad, [string]$renk = $cAccent) { return "$renk$BOLD$ad$RS" }
function Cards([object[]]$cards, [int]$inner, [int]$minGen = 36) {
    # stat kartlari: genis ekranda yan yana, darda 3'lu / 2'li satirlara boler; artik hucreler ilk kartlara (sag kenar dolar)
    $out = New-Object System.Collections.Generic.List[string]
    $n = $cards.Count; if ($n -eq 0) { return $out }
    $perRow = 1; foreach ($cand in @($n, [int][Math]::Ceiling($n / 2.0), [int][Math]::Ceiling($n / 3.0), 2, 1)) { if ($cand -lt 1 -or $cand -gt $n) { continue }; if ([int][Math]::Floor(($inner - ($cand - 1)) / $cand) -ge $minGen) { $perRow = $cand; break } }
    for ($s0 = 0; $s0 -lt $n; $s0 += $perRow) {
        $grp = @($cards[$s0..([Math]::Min($n, $s0 + $perRow) - 1)])
        $cw0 = [int][Math]::Floor(($inner - ($grp.Count - 1)) / $grp.Count); $artik = $inner - ($grp.Count - 1) - $cw0 * $grp.Count
        $hh = 0; foreach ($c in $grp) { if (@($c.l).Count -gt $hh) { $hh = @($c.l).Count } }
        $top = ''; $bot = ''; $mid = @(); for ($k = 0; $k -lt $hh; $k++) { $mid += '' }
        $ci = 0
        foreach ($c in $grp) {
            $cw = $cw0 + $(if ($ci -lt $artik) { 1 } else { 0 }); $ci++
            # kenar rengi durumu tasir (c.r: uyari/hata); sakin kart cerceve renginde kalir
            $kr = $(if ($c.r) { $c.r } else { $cFrame }); $tr = $(if ($c.r) { $c.r } elseif ($c.tr) { $c.tr } else { $cAccent })
            $lab = " $tr$BOLD$($c.t)$RS$kr "
            $fill = $cw - 2 - (VisLen $lab); if ($fill -lt 0) { $fill = 0 }
            $top += "$kr╭$lab$('─' * $fill)╮$RS "
            $bot += "$kr╰$('─' * ($cw - 2))╯$RS "
            for ($k = 0; $k -lt $hh; $k++) { $txt = $(if ($k -lt @($c.l).Count) { [string]@($c.l)[$k] } else { '' }); $mid[$k] += "$kr│$RS " + (Pad $txt ($cw - 4)) + " $kr│$RS " }
        }
        $out.Add($top.Substring(0, $top.Length - 1)); foreach ($m in $mid) { $out.Add($m.Substring(0, $m.Length - 1)) }; $out.Add($bot.Substring(0, $bot.Length - 1))
    }
    return $out
}
function Write-CizKare([System.Collections.Generic.List[string]]$L, [int]$w, [string]$Onceki) {
    # Tek kare yazici: imleci basa al, satirlari yaz; ESC[K YALNIZ satir pencereden kisaysa (tam genislikte imlec "kaydirma
    # bekliyor" durumundadir, ESC[K son sutunu = sag kenari siler); ESC[J kalan ekrani temizler. Degismediyse yazmaz.
    $sb = New-Object Text.StringBuilder; [void]$sb.Append("$ESC[H")
    foreach ($ln in $L) { [void]$sb.Append($ln).Append($RS); if ((VisLen $ln) -lt $w) { [void]$sb.Append("$ESC[K") }; [void]$sb.Append("`n") }
    [void]$sb.Append("$ESC[J")
    $kare = $sb.ToString(); if ($kare -ne $Onceki) { [Console]::Write($kare) }
    return $kare
}
