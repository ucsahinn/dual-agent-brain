param(
    [string]$Vault = '',
    [switch]$Tek   # bir kare ciz ve cik (test / ekran goruntusu icin)
)
# merkez.ps1 - Beyin MERKEZ: tum sistemin tek izleme ekrani (Windows Terminal).
# Liderler (Claude/Codex oturumlari), takim kosulari ve iscileri, onaylar, pano, aktarimlar,
# kaynak ve maliyet tek ekranda. HICBIR SEY YAZMAZ; yalniz okur ve Enter ile panel acar.
# Veri: merkez-veri.ps1 (durum kurali tek yerde). Balon: merkez-balon.ps1 (varsa).
# Tuslar: yukari/asagi (ya da j) sec, Enter odak (isci paneli / lider ayrintisi), p kosu panosu, a hepsi, r tazele, q cik.
# Gorsel dil (2026-10-15 tasarim incelemesi): kutu yalniz onay bandinda; bolumler acik baslik;
# renk rolleri ayri: DURUM (yesil/sari/kirmizi/sonuk), KIMLIK (Claude seftali, Codex turkuaz), VURGU (mavi: secim ve guncel asama).
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
$bgSel = BG 49 50 68; $bgGate = BG 58 50 36
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
    if ($n -lt 0x1100) { if (($n -ge 0x231A -and $n -le 0x231B) -or ($n -ge 0x23E9 -and $n -le 0x23FA)) { return 2 }; return 1 }
    if (($n -ge 0x1100 -and $n -le 0x115F) -or ($n -ge 0x2E80 -and $n -le 0xA4CF) -or ($n -ge 0xAC00 -and $n -le 0xD7A3) -or ($n -ge 0xF900 -and $n -le 0xFAFF) -or ($n -ge 0xFE30 -and $n -le 0xFE4F) -or ($n -ge 0xFF00 -and $n -le 0xFF60) -or ($n -ge 0xFFE0 -and $n -le 0xFFE6)) { return 2 }
    return 1
}
function VisLen([string]$s) { $t = Strip $s; $n = 0; for ($i = 0; $i -lt $t.Length; $i++) { if ([char]::IsHighSurrogate($t[$i])) { $n += 2; $i++ } else { $n += CellW $t[$i] } }; return $n }
function Cut([string]$s, [int]$w) {
    if ($w -le 0) { return '' }
    if ((VisLen $s) -le $w) { return $s }
    $out = New-Object Text.StringBuilder; $vis = 0; $i = 0
    while ($i -lt $s.Length) {
        if ($s[$i] -eq $ESC) { $m = $rxAnsi.Match($s, $i); if ($m.Success -and $m.Index -eq $i) { [void]$out.Append($m.Value); $i += $m.Length; continue } }
        $cw = $(if ([char]::IsHighSurrogate($s[$i])) { 2 } else { CellW $s[$i] })
        if ($vis + $cw -gt $w - 1) { break }
        if ([char]::IsHighSurrogate($s[$i]) -and $i + 1 -lt $s.Length) { [void]$out.Append($s.Substring($i, 2)); $i += 2 } else { [void]$out.Append($s[$i]); $i++ }
        $vis += $cw
    }
    return $out.ToString() + "…$RS"
}
function Pad([string]$s, [int]$w) { $s = Cut $s $w; return $s + (' ' * [Math]::Max(0, $w - (VisLen $s))) }
function PadL([string]$s, [int]$w) { $s = Cut $s $w; return (' ' * [Math]::Max(0, $w - (VisLen $s))) + $s }
function Kisa([double]$sn) {
    if ($sn -lt 0) { return '—' }; if ($sn -lt 60) { return "$([int]$sn) sn" }; if ($sn -lt 3600) { return "$([int][Math]::Floor($sn / 60)) dk" }
    if ($sn -lt 86400) { return "$([int][Math]::Floor($sn / 3600)) sa $([int][Math]::Floor(($sn % 3600) / 60)) dk" }; return "$([int][Math]::Floor($sn / 86400)) gün"
}
function Fmt([double]$n) { if ($n -ge 1e9) { return ('{0:0.0}B' -f ($n / 1e9)) }; if ($n -ge 1e6) { return ('{0:0.0}M' -f ($n / 1e6)) }; if ($n -ge 1e3) { return ('{0:0.0}K' -f ($n / 1e3)) }; return "$([int64]$n)" }
function Bar([double]$oran, [int]$gen, [string]$renk) {
    $oran = [Math]::Max([double]0, [Math]::Min([double]1, $oran)); $dolu = [int][Math]::Round($oran * $gen)
    return "$renk" + ('█' * $dolu) + "$cFrame" + ('░' * ($gen - $dolu)) + $RS
}
function RolTr([string]$r) { switch ($r) { 'root_cause_debugger' { 'hata ayıklayıcı' } 'docs_author' { 'belge yazarı' } 'qa_lead' { 'QA lideri' } 'spec_author' { 'spek yazarı' } 'test_verifier' { 'doğrulayıcı' } 'code_mapper' { 'kod haritacısı' } 'code_reviewer' { 'kod incelemeci' } 'security_auditor' { 'güvenlik denetçisi' } 'frontend_verifier' { 'arayüz doğrulayıcı' } '' { '' } default { $r -replace '_', ' ' } } }

# ---------- acik baslik (kutu yok) ----------
function Baslik([int]$w, [string]$label, [string]$sag = '') {
    $lab = "$cFrame──$RS $label$RS "; $sg = $(if ($sag) { " $sag$RS $cFrame──$RS" } else { '' })
    $fill = [Math]::Max(1, $w - (VisLen $lab) - (VisLen $sg))
    return $lab + "$cFrame" + ('─' * $fill) + $RS + $sg
}
function Satir([string]$c, [int]$w) { return '  ' + (Pad $c ($w - 2)) }

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

function Tazele([bool]$tam) {
    $script:anlik = Get-MerkezAnlik -Paths $p -Onbellek $script:onb -Hizli:(-not $tam)
    $script:sonHizli = Get-Date; if ($tam) { $script:sonTam = Get-Date }
    try { OlaylariBildir $script:anlik } catch { }
}
function AjanAnahtar($ag) { return "$($ag.Tur):$($ag.Kosu):$($ag.Ad)" }

# ---------- cizim ----------
function AjanSatir($ag, [int]$gen, [bool]$secili, [bool]$idGoster) {
    $d = [string]$ag.Durum; $renk = $durumRenk[$d]; if (-not $renk) { $renk = $cFaint }
    $serit = "$renk▌$RS"
    $kr = $kimlikRenk[[string]$ag.Ajan]; if (-not $kr) { $kr = $cMuted }
    if ($ag.Tur -eq 'lider') {
        $ad = "$kr$BOLD$($ag.Rol)$RS" + $(if ($idGoster) { " $cFaint$(([string]$ag.Ad).Substring(0, [Math]::Min(4, ([string]$ag.Ad).Length)))$RS" } else { '' })
        $rol = $(if ($ag.Prompt) { "$cFaint$($ag.Prompt) mesaj$RS" } else { '' })
        $yasSn = $ag.NabizSn
    } else {
        $ad = "$cFaint↳$RS $cText$BOLD$($ag.Ad)$RS"
        $rol = "$cMuted$(Protect-MerkezSatir (RolTr $ag.Rol) 24)$RS"
        $yasSn = $(if ($ag.Basladi) { $bitis = $(if ($ag.Bitti) { $ag.Bitti } else { Get-Date }); ($bitis - $ag.Basladi).TotalSeconds } else { -1 })
    }
    $durumYazi = $(if ($d -ne 'calisiyor') { "$renk$($durumAd[$d])$RS" } else { '' })
    $yasRenk = $(if ($ag.Bayat) { $cWarn } else { $cMuted })
    $yas = "$yasRenk$(Kisa $yasSn)$(if ($ag.Bayat) { ' !' })$RS"
    $jeton = $(if ($ag.Jeton) { "$cFaint$(Fmt $ag.Jeton)$RS" } else { '' })
    $basAd = $(if ($secili) { $ad -replace [regex]::Escape($BOLD), "$BOLD" } else { $ad })
    $sol = "$serit $(Pad $basAd 18) $(Pad $rol 16) $(Pad $durumYazi 10) "
    $sag = " $(PadL $yas 10) $(PadL $jeton 7)"
    $balonGen = $gen - (VisLen $sol) - (VisLen $sag)
    $balon = $(if ($ag.Balon -and $balonGen -gt 6) { "$cMuted$(Cut ([string]$ag.Balon) $balonGen)$RS" } else { '' })
    $satir = $sol + (Pad $balon ([Math]::Max(0, $balonGen))) + $sag
    if ($secili) { $satir = "$bgSel" + ((Pad $satir $gen) -replace [regex]::Escape($RS), "$RS$bgSel") + $RS }
    return $satir
}

function KanatBlogu([string]$kanat, $ajanlar, [int]$w) {
    $L = New-Object System.Collections.Generic.List[string]
    $aktif = @($ajanlar | Where-Object { $_.Durum -notin @('bosta', 'kapali', 'bitti') })
    $sakin = @($ajanlar | Where-Object { $_.Durum -in @('bosta', 'kapali', 'bitti') })
    $ozet = @(); if ($aktif.Count) { $ozet += "$cOk$($aktif.Count) aktif$RS" }; if ($sakin.Count) { $ozet += "$cFaint$($sakin.Count) sakin$RS" }
    $L.Add((Baslik $w "$cText$BOLD$(Protect-MerkezSatir $kanat 40)$RS" ($ozet -join "$cFaint · $RS")))
    $gosterilen = $(if ($script:hepsi -or -not $aktif.Count) { @($aktif) + @($sakin) } else { $aktif })
    $rolSay = @{}; foreach ($ag in $ajanlar) { if ($ag.Tur -eq 'lider') { $rolSay[$ag.Rol] = 1 + [int]$rolSay[$ag.Rol] } }
    foreach ($ag in $gosterilen) {
        $anahtar = AjanAnahtar $ag
        $script:secilebilir += , $ag
        $secili = ($anahtar -eq $script:secAnahtar)
        $L.Add('  ' + (AjanSatir $ag ($w - 2) $secili ([int]$rolSay[$ag.Rol] -gt 1)))
        if ($script:acik -and $script:acik -eq $anahtar) {
            if ($ag.Tur -eq 'lider') {
                $L.Add((Satir "    $cFaint oturum $($ag.Ad) · pid $(if ($ag.Pid) { $ag.Pid } else { '—' }) · durum kaynağı $($ag.Kaynak) · başladı $(if ($ag.Basladi) { $ag.Basladi.ToString('HH:mm') } else { '—' })$RS" $w))
                $L.Add((Satir "    $cFaint$(Protect-MerkezSatir ([string]$ag.Cwd) ($w - 10))$RS" $w))
            } else {
                $L.Add((Satir "    $cFaint koşu $($ag.Kosu) · durum kaynağı $($ag.Kaynak) · karar $(if ($ag.Verdict) { $ag.Verdict } else { '—' }) · ⏎ işçi paneli · p koşu panosu$RS" $w))
            }
        }
    }
    if (-not $script:hepsi -and $aktif.Count -and $sakin.Count) {
        $adlar = @($sakin | Select-Object -First 4 | ForEach-Object { if ($_.Tur -eq 'lider') { $_.Rol } else { $_.Ad } })
        $L.Add((Satir "$cFaint ○ $($sakin.Count) sakin: $($adlar -join ', ')$(if ($sakin.Count -gt 4) { " +$($sakin.Count - 4)" })$RS" $w))
    }
    return $L
}

function Ciz {
    $w = 160; $h = 50; try { $w = $Host.UI.RawUI.WindowSize.Width; $h = $Host.UI.RawUI.WindowSize.Height } catch { }
    if ($w -lt 90) { $w = 90 }
    $a = $script:anlik; $L = New-Object System.Collections.Generic.List[string]
    $script:secilebilir = @()

    # ---- baslik ----
    $hata = @($a.Teshis | Where-Object { $_.Seviye -eq 'err' }).Count; $uyari = $a.Teshis.Count - $hata
    $saglik = $(if ($hata) { "$cErr✖ $hata hata$RS" } elseif ($uyari) { "$cWarn⚠ $uyari uyarı$RS" } else { "$cOk✔ sağlıklı$RS" })
    $sagUst = "$saglik   $cMuted$((Get-Date).ToString('HH:mm'))$RS"
    $ust = "$cTitle$BOLD◆ Beyin merkez$RS"
    $L.Add($ust + (' ' * [Math]::Max(1, $w - (VisLen $ust) - (VisLen $sagUst))) + $sagUst)
    $say = $a.Sayac; $chips = @()
    foreach ($d in @('calisiyor', 'inceleme', 'engelli', 'duraklatildi', 'bekliyor', 'bosta')) {
        $n = $(if ($say.ContainsKey($d)) { $say[$d] } else { 0 }); if ($n -le 0) { continue }
        $nk = $(if ($d -in @('calisiyor', 'inceleme', 'engelli')) { '●' } elseif ($d -eq 'bosta') { '○' } else { '' })
        $chips += "$($durumRenk[$d])$nk$(if ($nk) { ' ' })$BOLD$n$RS $($durumRenk[$d])$($durumAd[$d])$RS"
    }
    if (-not $chips.Count) { $chips += "$cFaint etkin ajan yok$RS" }
    $met = @()
    if ($a.Kaynak -and $a.Kaynak.Ok) {
        $cy = [int]$a.Kaynak.CommitYuzde; $cr = $(if ($cy -ge 85) { $cErr } elseif ($cy -ge 70) { $cWarn } else { $cOk })
        $met += "$cFaint commit$RS $(Bar ($cy / 100.0) 10 $cr) $cText$BOLD%$cy$RS"
        if ($a.Kaynak.BosRamGB -ge 0) { $met += "$cFaint RAM$RS $cText$BOLD$($a.Kaynak.BosRamGB) GB$RS$cFaint boş$RS" }
    }
    if ($a.Maliyet) {
        $met += "$cFaint maliyet $([int]$a.Maliyet.gun) gün$RS $cText$BOLD`$$([int][double]$a.Maliyet.claudeUsd)$RS"
        $met += "$cFaint Codex$RS $cText$BOLD$(Fmt ([double]$a.Maliyet.codexJeton))$RS$cFaint jeton$RS"
    }
    $L.Add('  ' + ($chips -join '    '))
    if ($met.Count) { $L.Add('  ' + ($met -join '    ')) }
    $L.Add('')

    # ---- onay bandi (tek yuksek ses) ----
    if ($a.Onaylar.Count) {
        $L.Add("$bgGate" + ((Pad "$cWarn$BOLD▌ Onay bekliyor  $($a.Onaylar.Count)$RS$bgGate   $cMuted sohbete yalnız bu satırı yaz$RS$bgGate" $w) -replace [regex]::Escape($RS), "$RS$bgGate") + $RS)
        foreach ($g in $a.Onaylar) { $L.Add("$bgGate" + ((Pad "$cWarn▌$RS$bgGate   $cWarn$BOLD$(Protect-MerkezSatir $g.Satir 40)$RS$bgGate   $cMuted$(Protect-MerkezSatir $g.Neden 120)$RS$bgGate" $w) -replace [regex]::Escape($RS), "$RS$bgGate") + $RS) }
        $L.Add('')
    }

    # ---- kanatlar ----
    $aktifMi = { param($g) @($g.Group | Where-Object { $_.Durum -notin @('bosta', 'kapali', 'bitti') }).Count -gt 0 }
    $gruplar = @($a.Ajanlar | Group-Object -Property { $_.Kanat } | Sort-Object -Property @{ Expression = { @($_.Group | Where-Object { $_.Durum -notin @('bosta', 'kapali', 'bitti') }).Count }; Descending = $true }, @{ Expression = { ($_.Group | ForEach-Object { $_.NabizSn } | Measure-Object -Minimum).Minimum } })
    $aktifGrup = @($gruplar | Where-Object { & $aktifMi $_ }); $sakinGrup = @($gruplar | Where-Object { -not (& $aktifMi $_) })
    $gosterGrup = $(if ($script:hepsi) { $gruplar } else { $aktifGrup })
    $iki = ($w -ge 170 -and $gosterGrup.Count -ge 2)
    $kolW = $(if ($iki) { [int][Math]::Floor(($w - 3) / 2) } else { $w })
    $bloklar = New-Object System.Collections.Generic.List[object]
    foreach ($g in $gosterGrup) {
        $sirali = @($g.Group | Sort-Object -Property @{ Expression = { $durumSira[[string]$_.Durum] } }, @{ Expression = { $_.Tur -ne 'lider' } }, @{ Expression = { $_.NabizSn } })
        $blok = @(KanatBlogu ([string]$g.Name) $sirali $kolW) + @(''); $bloklar.Add($blok)
    }
    if ($iki) {
        $sol = New-Object System.Collections.Generic.List[string]; $sag = New-Object System.Collections.Generic.List[string]; $hs = 0; $hd = 0
        foreach ($b in $bloklar) { if ($hs -le $hd) { $sol.AddRange([string[]]$b); $hs += $b.Count } else { $sag.AddRange([string[]]$b); $hd += $b.Count } }
        for ($i = 0; $i -lt [Math]::Max($sol.Count, $sag.Count); $i++) {
            $s1 = $(if ($i -lt $sol.Count) { $sol[$i] } else { '' }); $s2 = $(if ($i -lt $sag.Count) { $sag[$i] } else { '' })
            $L.Add((Pad $s1 $kolW) + " $cFrame▏$RS " + $s2)
        }
    } else { foreach ($b in $bloklar) { $L.AddRange([string[]]$b) } }
    if (-not $gruplar.Count) { $L.Add("  $cFaint son 24 saatte etkin ajan yok$RS"); $L.Add('') }
    if (-not $script:hepsi -and $sakinGrup.Count) {
        $L.Add("  $cFaint sakin: $(@($sakinGrup | ForEach-Object { "$($_.Name) ($($_.Count))" }) -join '  ·  ')$RS"); $L.Add('')
    }
    # secim ajana bagli: sira degisse de imlec ayni ajanda kalir
    $script:sec = -1
    for ($i = 0; $i -lt $script:secilebilir.Count; $i++) { if ((AjanAnahtar $script:secilebilir[$i]) -eq $script:secAnahtar) { $script:sec = $i; break } }

    # ---- kosular ----
    if ($a.Kosular.Count) {
        $L.Add((Baslik $w "$cText${BOLD}Koşular$RS" "$cFaint$($a.Kosular.Count)$RS"))
        foreach ($k in @($a.Kosular | Sort-Object -Property @{ Expression = { $_.Bitmis } }, @{ Expression = { $_.Guncel }; Descending = $true })) {
            $iz = ''
            for ($i = 0; $i -le 6; $i++) {
                $nokta = $(if ($i -lt $k.Asama -or ($k.Bitmis -and $i -le $k.Asama)) { "$cOk●$RS" } elseif ($i -eq $k.Asama) { "$cAccent◉$RS" } else { "$cFrame○$RS" })
                $cizgi = $(if ($i -lt 6) { $(if ($i -lt $k.Asama) { "$cOk━$RS" } else { "$cFrame┄$RS" }) } else { '' })
                $iz += $nokta + $cizgi
            }
            $sr = switch ($k.Sonraki.Renk) { 'ok' { $cOk } 'warn' { $cWarn } 'err' { $cErr } default { $cMuted } }
            $isc = "$cText$($k.Biten)/$($k.Isci)$RS$cFaint işçi$RS$(if ($k.Sorunlu) { "  $cErr$($k.Sorunlu) sorunlu$RS" })"
            $L.Add((Satir "$cText$BOLD$($k.RunId)$RS  $cFaint$(Pad (Protect-MerkezSatir $k.Repo 30) 18)$RS $iz  $cAccent$(Pad $asamaAd[[int]$k.Asama] 13)$RS $(Pad $isc 20) $cFaint$(if ($k.Jeton) { "$(Fmt $k.Jeton) jeton" })$RS   $sr$($k.Sonraki.Metin)$RS" $w))
        }
        $L.Add('')
    }

    # ---- pano | aktarimlar (dar ekranda alt alta) ----
    $yan = ($w -ge 140); $kw = $(if ($yan) { [int][Math]::Floor(($w - 3) / 2) } else { $w })
    $pL = New-Object System.Collections.Generic.List[string]; $aL = New-Object System.Collections.Generic.List[string]
    $pL.Add((Baslik $kw "$cText${BOLD}Pano$RS" "$cFaint$($a.Kartlar.Count) açık$RS"))
    foreach ($kt in @($a.Kartlar | Select-Object -First 6)) {
        $st = [string]$kt.status; $r = switch ($st) { 'blocked' { $cErr } 'review' { $cWarn } 'in_progress' { $cOk } default { $cFaint } }
        $sahip = $(if ($kt.owner -and $kt.owner.agent) { Protect-MerkezSatir ([string]$kt.owner.agent) 10 } else { '' })
        $sahipS = $(if ($kw -ge 110 -and $sahip) { "$($kimlikRenk[$sahip])$(Pad $sahip 7)$RS " } else { '' })
        $pL.Add((Satir "$r$(Pad $panoAd[$st] 11)$RS $cText$(Pad (Protect-MerkezSatir ([string]$kt.id) 12) 9)$RS $sahipS$cMuted$(Protect-MerkezSatir ([string]$kt.title) 90)$RS" $kw))
    }
    if (-not $a.Kartlar.Count) { $pL.Add((Satir "$cFaint açık kart yok$RS" $kw)) } elseif ($a.Kartlar.Count -gt 6) { $pL.Add((Satir "$cFaint +$($a.Kartlar.Count - 6) kart · beyin pano list$RS" $kw)) }
    $aL.Add((Baslik $kw "$cText${BOLD}Aktarımlar$RS" "$cFaint$($a.Aktarimlar.Count) açık$RS"))
    foreach ($hd in @($a.Aktarimlar | Select-Object -First 6)) {
        $yas = ''; try { $yas = Kisa ((Get-Date) - [datetime]::Parse([string]$hd.ts)).TotalSeconds } catch { }
        $kimden = Protect-MerkezSatir $(if ($hd.from -is [string]) { [string]$hd.from } else { [string]$hd.from.agent }) 8; $kime = Protect-MerkezSatir $(if ($hd.to -is [string]) { [string]$hd.to } else { [string]$hd.to.agent }) 8
        $yon = "$($kimlikRenk[$kimden])$kimden$RS$cFaint→$RS$($kimlikRenk[$kime])$kime$RS"
        $aL.Add((Satir "$(Pad $yon 14) $cFaint$(Pad (Protect-MerkezSatir ([string]$hd.toProject) 30) 12)$RS $cText$(Protect-MerkezSatir ([string]$hd.question) 90)" ($kw - 12)) + "$cMuted$(PadL $yas 12)$RS")
    }
    if (-not $a.Aktarimlar.Count) { $aL.Add((Satir "$cFaint bekleyen aktarım yok$RS" $kw)) } elseif ($a.Aktarimlar.Count -gt 6) { $aL.Add((Satir "$cFaint +$($a.Aktarimlar.Count - 6) · beyin aktar$RS" $kw)) }
    if ($yan) {
        for ($i = 0; $i -lt [Math]::Max($pL.Count, $aL.Count); $i++) {
            $s1 = $(if ($i -lt $pL.Count) { $pL[$i] } else { '' }); $s2 = $(if ($i -lt $aL.Count) { $aL[$i] } else { '' })
            $L.Add((Pad $s1 $kw) + "   " + $s2)
        }
    } else { $L.AddRange([string[]]$pL); $L.Add(''); $L.AddRange([string[]]$aL) }
    $L.Add('')

    # ---- teshis ----
    if ($a.Teshis.Count) {
        $L.Add((Baslik $w "$cText${BOLD}Teşhis$RS" "$cFaint$($a.Teshis.Count)$RS"))
        foreach ($t in @($a.Teshis | Sort-Object -Property @{ Expression = { $_.Seviye -ne 'err' } } | Select-Object -First 5)) {
            $ic = $(if ($t.Seviye -eq 'err') { "$cErr✖" } else { "$cWarn⚠" }); $L.Add("  $ic $RS$cText$(Protect-MerkezSatir ([string]$t.Metin) ([Math]::Min(110, $w - 6)))$RS")
        }
        if ($a.Teshis.Count -gt 5) { $L.Add("  $cFaint +$($a.Teshis.Count - 5) uyarı daha · beyin doktor$RS") }
    }

    # ---- alt satir ----
    $veriYas = ((Get-Date) - $script:sonHizli).TotalSeconds
    $msj = $(if ($script:mesaj -and ((Get-Date) - $script:mesajZaman).TotalSeconds -lt 6) { "$cWarn$($script:mesaj)$RS    " } else { '' })
    $tus = "$cText↑↓$RS$cFaint seç$RS   $cText⏎$RS$cFaint odak$RS   $cText p$RS$cFaint koşu panosu$RS   $cText a$RS$cFaint $(if ($script:hepsi) { 'yalnız aktifler' } else { 'hepsi' })$RS   $cText r$RS$cFaint tazele$RS   $cText q$RS$cFaint çık$RS"
    $durum = $(if ($script:cizimHata) { "   $cErr✖ çizim hatası $($script:cizimHata)$RS" } elseif ($veriYas -gt 5) { "   $cWarn veri $([int]$veriYas) sn önce$RS" } else { '' })
    $alt = "$msj$tus$durum"
    $maks = $(if ($Tek) { 100000 } else { [Math]::Max(5, $h - 2) })
    if ($L.Count -gt $maks) { $L = [System.Collections.Generic.List[string]]@($L | Select-Object -First ($maks - 1)); $L.Add("  $cFaint… ekran dar · pencereyi büyüt ya da a ile yalnız aktifleri göster$RS") }
    $sb = New-Object Text.StringBuilder; [void]$sb.Append("$ESC[H")
    foreach ($ln in $L) { [void]$sb.Append($ln).Append("$RS$ESC[K`n") }
    [void]$sb.Append("$ESC[J"); if ($Tek) { [void]$sb.Append($alt).Append($RS) } else { [void]$sb.Append("$ESC[$h;1H").Append($alt).Append("$RS$ESC[K") }
    $kare = $sb.ToString(); if ($kare -ne $script:lastFrame) { $script:lastFrame = $kare; [Console]::Write($kare) }
}

function CizimSonuc {
    try { Ciz; if ($script:cizimHata) { $script:cizimHata = 0; $script:lastFrame = '' }; $script:sonCizim = Get-Date }
    catch {
        $script:cizimHata++; $script:cizimMesaj = (Protect-MerkezSatir ([string]$_.Exception.Message) 120)
        try { $hh = $Host.UI.RawUI.WindowSize.Height; [Console]::Write("$ESC[$hh;1H$cErr⚠ merkez $(if ($script:cizimHata -ge 5) { 'BOZUK' } else { 'SORUNLU' }) · $($script:cizimHata) kez çizilemedi · son başarılı $(Kisa ((Get-Date) - $script:sonCizim).TotalSeconds) önce · $($script:cizimMesaj)$RS$ESC[K") } catch { }
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
# yukleniyor ve ic ice surec birikiyordu). Yeniden yukleme ayni konsolda yeni sureci baslatir ve bu surec CIKAR.
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
if ($Tek) { $script:hepsi = $true; Ciz; [Console]::Write("$RS`n"); exit 0 }
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
                        'q' { $quit = $true } 'a' { $script:hepsi = -not $script:hepsi } 'r' { Tazele $true }
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
    Start-Sleep -Milliseconds 250
}
} finally {
    try { [Console]::CursorVisible = $true } catch { }
    if (-not $Tek) { [Console]::Write("$RS$ESC[2J$ESC[H") } else { [Console]::Write($RS) }
}
if ($yenidenYukle) { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath -Vault $Vault; exit $LASTEXITCODE }
