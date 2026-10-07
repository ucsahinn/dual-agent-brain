# aktar.ps1 - Ajanlar arasi AKTARIM (handoff) kanali: Codex -> Claude ve Claude -> Codex.
#
# NEDEN (2026-10-04, plan #11): kurallar "Codex sorusunu beyne yazar, sonraki Claude
# oturumu tasir" diyordu ama kodda karsiligi yoktu; soru gunluk logun icinde
# kayboluyordu. Bu betik soruyu/handoff'u KUCUK, YAPILI bir kayit olarak motor
# durumuna yazar; session-start hedef ajanin HER yeni oturumunda `[Hafiza: Aktarim]`
# blogu olarak enjekte eder (ayni oturumda ikinci acilis tekrar gostermez), alan
# ajan `-Tamam <id>` ile kapatir. Turetilmis gorunum: 10-command-center\aktarimlar.md.
#
# Kullanim:
#   beyin aktar                                      acik aktarimlari listele (-Hepsi: kapananlar da)
#   beyin aktar "soru/handoff" -Kime claude          kaydet (Kanit/Kapsam/Risk/Sonraki istege bagli)
#   beyin aktar "..." -Kime codex -Proje x -Kanit "..." -Kapsam "..." -Risk "..." -Sonraki "..."
#   beyin aktar -Tamam <id>                          kapat (kapatan ajan ve zaman yazilir)
#   beyin aktar "yanit" -Yanit <id>                  soruya yanit: soran ajana geri yazilir, soru kapanir
#   beyin aktar -Bekle <id> [-Sure 100]              yanit gelene kadar bekle (ayni tur icinde soru-cevap)
#   beyin aktar "soru" -Kime claude -VeBekle         gonder ve yanitini bekle
#
# TESLIM (2026-10-07): hedef ajan aktarimi AYNI OTURUMDA bir sonraki kullanici mesajinda
# (UserPromptSubmit) ya da yeni oturum acilisinda gorur. Bos bekleyen bir ajani uyandiran
# bir kanal YOKTUR; -Bekle yalniz karsi ajan o sirada calisiyorsa ise yarar.
#
# Dosya: motor\scripts\.state\handoff\<id>.json
#   {v,id,ts,from{agent,session,project},to,question,evidence,scope,risk,next,status,doneBy,doneTs}
# Kuratorlu alana YAZMAZ. Metinler Protect-BeyinSecrets'ten gecer (fail-closed: desen
# duserse YAZMAZ). Codex session-end kancasi bunu CAGIRMAZ (3 sn tavani); kanal acik komuttur.
[CmdletBinding(PositionalBinding=$false)]
param(
    [string]$Vault = '',
    [Parameter(Position=0)][string]$Metin = '',
    [string]$Kanit = '',
    [string]$Kapsam = '',
    [string]$Risk = '',
    [string]$Sonraki = '',
    [string]$Kime = '',
    [string]$Proje = '',
    # Tur (2026-10-06): soru (varsayilan) ya da devir (nerede kaldim / siradaki adim). brifing yalniz pano uretir.
    [string]$Tur = 'soru',
    [string]$Tamam = '',
    [switch]$Hepsi,
    # SORU-CEVAP (2026-10-07): -Yanit <id> yanit yazar; -Bekle <id> yanit bekler; -VeBekle gonder+bekle.
    [string]$Yanit = '',
    [string]$Bekle = '',
    [switch]$VeBekle,
    [int]$Sure = 100,
    # TESLIM YERI (2026-10-07): bos = hedef ajanin HER acilisinda/mesajinda; '<proje>' = yalniz o projede.
    [string]$Hedef = ''
)

$ErrorActionPreference = 'SilentlyContinue'
# EKRAN CIKTISI (2026-10-07): etkilesimli terminalde onemli satirlar renkli - Cyan: yanit ve
# kimlik vurgusu, Green: basari, Yellow: uyari/zaman asimi, Red: hata. Cikti yonlendirilmisse
# (ajan kabugu, boru, dosya) DUZ metin: ajanlar ayristirabilsin ve hicbir satir kaybolmasin
# (Write-Host yonlendirmede yakalanmaz). Konsol UTF-8: Turkce karakterler bozulmasin
# (olculdu: IBM437 konsolda Git Bash'e 'ğ'->'g', 'ü'->0x81 gidiyordu).
$script:Renkli = $false
try { $script:Renkli = -not [Console]::IsOutputRedirected } catch { }
# Yonlendirilmis ciktida baytlar dogrudan UTF-8 yazilir. Konsol kod sayfasi DEGISTIRILMEZ:
# ust surecin (ajanin/kullanicinin) terminalini kalici etkilerdi. Etkilesimli konsol zaten
# Unicode yazar.
$script:CiktiAkisi = $null
if (-not $script:Renkli) { try { $script:CiktiAkisi = [Console]::OpenStandardOutput() } catch { } }
function Yaz([string]$Metin, [string]$Renk = '') {
    if ($script:Renkli -and $Renk) { Write-Host $Metin -ForegroundColor $Renk; return }
    if ($script:CiktiAkisi) {
        try { $b = [Text.Encoding]::UTF8.GetBytes($Metin + "`n"); $script:CiktiAkisi.Write($b, 0, $b.Length); $script:CiktiAkisi.Flush(); return } catch { }
    }
    Write-Output $Metin
}
function Hata([string]$Metin, [int]$Kod = 2) { Yaz "HATA: $Metin" 'Red'; exit $Kod }

if (-not $Vault) { $Vault = $(if ($env:BEYIN_VAULT) { $env:BEYIN_VAULT } else { Split-Path (Split-Path $PSScriptRoot -Parent) -Parent }) }
function Vault-Mi([string]$Y) {
    try { return [bool]($Y -and (Test-Path -LiteralPath $Y -PathType Container) -and (Test-Path -LiteralPath (Join-Path $Y 'motor\hooks\lib.ps1') -PathType Leaf)) } catch { return $false }
}
if (-not (Vault-Mi $Vault)) { Hata "vault degil (motor\hooks\lib.ps1 yok): '$Vault'" }
. (Join-Path $Vault 'motor\hooks\lib.ps1')
$p = Get-BeyinPaths -Vault $Vault
$ajan = Get-BeyinAgent

# Celisen bayraklar acikca reddedilir (eskiden biri sessizce yok sayiliyordu).
if ($Bekle -and $Yanit) { Hata '-Bekle ve -Yanit birlikte verilemez (once yanitla, bekleme soranin isidir).' }
if ($Bekle -and $Tamam) { Hata '-Bekle ve -Tamam birlikte verilemez.' }
if ($VeBekle -and ([string]$Tur).Trim().ToLowerInvariant() -eq 'devir') { Hata '-VeBekle devir ile kullanilmaz (devre yanit gelmez).' }

function Bekle-Yanit([string]$SoruId, [int]$Saniye) {
    # Yanit = to bu ajan, kind yanit, ref soru kimligi. KAPALI olsa da bulunur (biri once
    # -Tamam ile kapatmis olabilir); aciksa gosterilip kapatilir (okundu).
    $Saniye = [math]::Max(10, [math]::Min(3600, $Saniye))
    $bitis = (Get-Date).AddSeconds($Saniye)
    Yaz "Yanit bekleniyor: $SoruId (en fazla $Saniye sn). Karsi ajan calisiyorsa bir sonraki komutunda, degilse bir sonraki mesajinda gorur." 'Yellow'
    while ((Get-Date) -lt $bitis) {
        $y = @(Get-BeyinHandoffListe -Paths $p -Hepsi | Where-Object { [string]$_.ref -eq $SoruId -and [string]$_.kind -eq 'yanit' -and [string]$_.to -eq $ajan })
        if ($y.Count -gt 0) {
            $h = $y[0]
            Yaz "YANIT ($($h.from.agent), $($h.id)): $($h.question)" 'Cyan'
            if ($h.evidence) { Yaz "  kanit  : $($h.evidence)" }
            if ($h.next)     { Yaz "  sonraki: $($h.next)" }
            if ([string]$h.status -eq 'acik') { $null = Close-BeyinHandoff -Paths $p -Id ([string]$h.id) -DoneBy "$ajan (yanit okundu)" }
            Write-BeyinMakbuz -Paths $p -Script 'aktar' -Outcome 'AKTAR_YANIT_ALINDI' -Agent $ajan -Note "$SoruId <- $($h.id)"
            $script:BekleKod = 0; return
        }
        $s = Get-BeyinHandoff -Paths $p -Id $SoruId
        if ($s -and [string]$s.status -eq 'tamam' -and [string]$s.doneBy -notlike '*yanitladi*') { Yaz "Soru yanitsiz kapatildi ($($s.doneBy))." 'Yellow'; $script:BekleKod = 4; return }
        Start-Sleep -Seconds 3
    }
    Yaz "ZAMAN ASIMI: $Saniye sn icinde yanit gelmedi. Yanit sonra gelirse bir sonraki mesajda/acilista gorunur; yeniden beklemek icin: beyin aktar -Bekle $SoruId" 'Yellow'
    $script:BekleKod = 3
}
# NOT: Bekle-Yanit cikis kodunu $script:BekleKod'a yazar. 'exit (Bekle-Yanit ...)' KULLANMA:
# fonksiyonun yazdigi satirlar o zaman cikis degerine karisir ve ekrana hic basilmaz (olculdu).
$script:BekleKod = 0

# --- Bekle: -Bekle <id> ---
if ($Bekle) {
    if (-not (Get-BeyinHandoff -Paths $p -Id $Bekle)) { Hata "aktarim bulunamadi: $Bekle" }
    Bekle-Yanit $Bekle $Sure
    exit $script:BekleKod
}

# --- Yanit: "metin" -Yanit <id> ---
if ($Yanit) {
    $soru = Get-BeyinHandoff -Paths $p -Id $Yanit
    if (-not $soru) { Hata "aktarim bulunamadi: $Yanit  (liste: beyin aktar)" }
    if (-not $Metin) { Hata "yanit metni yok. Kullanim: beyin aktar `"yanit metni`" -Yanit $Yanit" }
    if ([string]$soru.status -ne 'acik') { Hata "soru zaten kapali ($($soru.doneBy)); yeni bir soru icin: beyin aktar `"...`" -Kime $($soru.from.agent)" }
    if ([string]$soru.to -ne $ajan) { Hata "bu soru '$($soru.to)' ajanina yazilmis; yanitini o ajan verir (sen: $ajan)." }
    # $hedef ADI KULLANILAMAZ: -Hedef parametresiyle ayni degisken (PS harf duyarsiz); onu
    # ezip yaniti 'codex' adli bir projeye sinirliyordu (olculdu 2026-10-07).
    $yanitKime = [string]$soru.from.agent
    if ($yanitKime -ne 'claude' -and $yanitKime -ne 'codex') { $yanitKime = $(if ($ajan -eq 'codex') { 'claude' } else { 'codex' }) }
    $yr = Add-BeyinHandoff -Paths $p -Metin $Metin -Kime $yanitKime -Kanit $Kanit -Kapsam $Kapsam -Risk $Risk -Sonraki $Sonraki `
        -Proje ([string]$soru.from.project) -Kind 'yanit' -Ref $Yanit -FromAgent $ajan -FromSession ([string]$env:HERDR_PANE_ID) -HedefProje $Hedef
    if (-not $yr.Ok) { Hata "yanit yazilamadi ($($yr.Kod): $($yr.Hata))" 3 }
    $kapandi = Close-BeyinHandoff -Paths $p -Id $Yanit -DoneBy "$ajan (yanitladi: $($yr.Id))"
    Write-BeyinMakbuz -Paths $p -Script 'aktar' -Outcome 'AKTAR_YANITLANDI' -Agent $ajan -Note "$Yanit -> $($yr.Id)"
    Yaz "Yanit kaydedildi: $($yr.Id)  ($ajan -> $yanitKime)$(if ($kapandi) { ". Soru $Yanit kapatildi." } else { '.' })" 'Green'
    if (-not $kapandi) { Yaz "UYARI: soru $Yanit kapatilamadi (baskasi kapatmis olabilir)." 'Yellow' }
    exit 0
}

# --- Kapat: -Tamam <id> ---
if ($Tamam) {
    $k = Get-BeyinHandoff -Paths $p -Id $Tamam
    if (-not $k) { Hata "aktarim bulunamadi: $Tamam  (liste: beyin aktar -Hepsi)" }
    if ($k.status -eq 'tamam') { Yaz "Zaten kapali: $Tamam ($($k.doneBy), $($k.doneTs))" 'Yellow'; exit 0 }
    $k.status = 'tamam'
    $k.doneBy = $ajan
    $k.doneTs = (Get-Date).ToString('o', [Globalization.CultureInfo]::InvariantCulture)
    $yaz = Set-BeyinHandoff -Paths $p -Kayit $k
    if (-not $yaz.Ok) {
        Write-BeyinLog -Vault $Vault -Message "aktar: KAPATILAMADI $Tamam ($($yaz.Hata))"
        Write-BeyinMakbuz -Paths $p -Script 'aktar' -Outcome 'AKTAR_YAZILAMADI' -Note $yaz.Hata
        Hata "aktarim kapatilamadi - $($yaz.Hata)" 3
    }
    Update-BeyinAktarimlarMd -Paths $p | Out-Null
    Write-BeyinLog -Vault $Vault -Message "aktar: kapatildi $Tamam (kapatan=$ajan)"
    Write-BeyinMakbuz -Paths $p -Script 'aktar' -Outcome 'AKTAR_TAMAM' -Agent $ajan -Note $Tamam
    Yaz "Aktarim kapatildi: $Tamam" 'Green'
    exit 0
}

# --- Liste ---
if (-not $Metin) {
    # Gonderim bayragi verilip metin bos kaldiysa SESSIZCE liste basma: cagiranin metin
    # degiskeni bos kalmis olabilir, basarili gorunur ama hicbir sey gitmez (denetim 2026-10-07).
    $gonderimBayragi = @('Kime', 'Kanit', 'Kapsam', 'Risk', 'Sonraki', 'Proje', 'Hedef', 'Tur', 'VeBekle') | Where-Object { $PSBoundParameters.ContainsKey($_) }
    if (@($gonderimBayragi).Count -gt 0) { Hata "gonderilecek metin bos (verilen: -$((@($gonderimBayragi)) -join ', -')). Kullanim: beyin aktar `"soru`" -Kime claude|codex" }
    # '$hepsi' adi KULLANILAMAZ: [switch]$Hepsi parametresiyle ayni degiskendir (PS adlari harf
    # duyarsiz); diziyi switch'e atama sessizce duser ve foreach $false uzerinde doner (olculdu:
    # liste bos alanlarla basildi).
    $kayitlar = @(Get-BeyinHandoffListe -Paths $p -Hepsi:$Hepsi)
    if ($kayitlar.Count -eq 0) {
        if ($Hepsi) { Yaz 'Hic aktarim yok.' } else { Yaz 'Acik aktarim yok.  Kaydetmek icin:  beyin aktar "soru" -Kime claude|codex' }
        exit 0
    }
    foreach ($h in $kayitlar) {
        $ts = ''
        try { $ts = ([datetime]::Parse([string]$h.ts, [Globalization.CultureInfo]::InvariantCulture)).ToString('yyyy-MM-dd HH:mm', [Globalization.CultureInfo]::InvariantCulture) } catch { }
        $acik = ($h.status -ne 'tamam')
        $durum = $(if ($acik) { 'ACIK' } else { "TAMAM ($($h.doneBy))" })
        $tur = $(if ($h.PSObject.Properties['kind'] -and $h.kind) { [string]$h.kind } else { 'soru' })
        $hedefP = $(if ($h.PSObject.Properties['toProject'] -and $h.toProject) { "  hedef: $($h.toProject)" } else { '' })
        Yaz "$($h.id)  [$durum]  [$tur]  $($h.from.agent) -> $($h.to)  proje: $($h.from.project)$hedefP  $ts" $(if ($acik) { 'Cyan' } else { 'DarkGray' })
        Yaz "  soru   : $($h.question)"
        if ($h.ref)      { Yaz "  yanitladigi: $($h.ref)" }
        if ($h.evidence) { Yaz "  kanit  : $($h.evidence)" }
        if ($h.scope)    { Yaz "  kapsam : $($h.scope)" }
        if ($h.risk)     { Yaz "  risk   : $($h.risk)" }
        if ($h.next)     { Yaz "  sonraki: $($h.next)" }
        if ($acik) { Yaz "  yanit  : beyin aktar `"...`" -Yanit $($h.id)   |   kapat: beyin aktar -Tamam $($h.id)" 'DarkGray' }
        Yaz ''
    }
    exit 0
}

# --- Kaydet ---
$kime = ([string]$Kime).Trim().ToLowerInvariant()
if (-not $kime) { $kime = $(if ($ajan -eq 'codex') { 'claude' } else { 'codex' }) }
if ($kime -ne 'claude' -and $kime -ne 'codex') { Hata "-Kime claude ya da codex olmali (verilen: '$Kime')" }

# KAYIT TEK YOLDAN (2026-10-06): lib Add-BeyinHandoff (pano brifingi de ayni fonksiyonu
# kullanir). Sozlesme ayni: alanlar fail-closed maskelenir, yazim geri okunur.
$proje = ([string]$Proje).Trim()
if (-not $proje) { try { $proje = Get-BeyinProjectLeaf -Path (Get-Location).Path -Paths $p } catch { $proje = '' } }
$tur = ([string]$Tur).Trim().ToLowerInvariant()
if (-not $tur) { $tur = 'soru' }
if ($tur -ne 'soru' -and $tur -ne 'devir') { Hata "-Tur soru ya da devir olmali (verilen: '$Tur')" }
# DEVIR AYNI AJANA (2026-10-06): devir yalniz ayni ajanin AYNI projedeki acilisinda
# gosterilir ve gosterilince kapanir. Baska ajana yazilan devir sessizce gorunmez
# kalirdi (olculdu: Codex'e giden kart bildirimi bu yuzden dustu). Acikca reddet.
if ($tur -eq 'devir' -and $kime -ne $ajan) {
    Hata "-Tur devir yalniz ayni ajana yazilir (gonderen: $ajan, hedef: $kime). Baska ajana bildirim icin -Tur'u verme (soru/handoff)."
}
$sonuc = Add-BeyinHandoff -Paths $p -Metin $Metin -Kime $kime -Kanit $Kanit -Kapsam $Kapsam -Risk $Risk -Sonraki $Sonraki `
    -Proje $proje -Kind $tur -FromAgent $ajan -FromSession ([string]$env:HERDR_PANE_ID) -HedefProje $Hedef
if ($sonuc.Kod -eq 'BOS') { Hata 'bos soru/handoff metni' }
if ($sonuc.Kod -eq 'REDAKSIYON_DUSTU') {
    Write-BeyinMakbuz -Paths $p -Script 'aktar' -Outcome 'AKTAR_REDAKSIYON_DUSTU' -Note $sonuc.Hata
    Hata "sir redaksiyonu uygulanamadi ($($sonuc.Hata)). Aktarim YAZILMADI." 3
}
if (-not $sonuc.Ok) {
    Write-BeyinLog -Vault $Vault -Message "aktar: YAZILAMADI ($($sonuc.Hata))"
    Write-BeyinMakbuz -Paths $p -Script 'aktar' -Outcome 'AKTAR_YAZILAMADI' -Note $sonuc.Hata
    Hata "aktarim kaydedilemedi - $($sonuc.Hata)" 3
}
if ($sonuc.Maske -gt 0) { Yaz "UYARI: $($sonuc.Maske) sir benzeri deger maskelendi." 'Yellow' }
$kesilen = @()
if (([string]$Metin).Trim().Length -gt 600) { $kesilen += 'metin 600' }
foreach ($alan in @(@{ A = 'kanit'; D = $Kanit }, @{ A = 'kapsam'; D = $Kapsam }, @{ A = 'risk'; D = $Risk }, @{ A = 'sonraki'; D = $Sonraki })) { if (([string]$alan.D).Trim().Length -gt 300) { $kesilen += "$($alan.A) 300" } }
if ($kesilen.Count -gt 0) { Yaz "UYARI: kisaltildi ($($kesilen -join ', ') karakter). Uzun icerik icin dosya yolunu -Kanit'e yaz." 'Yellow' }
$id = $sonuc.Id
Write-BeyinLog -Vault $Vault -Message "aktar: kaydedildi $id ($ajan -> $kime, tur=$tur, proje=$proje, hedef=$Hedef)"
Write-BeyinMakbuz -Paths $p -Script 'aktar' -Outcome 'AKTAR_KAYDEDILDI' -Agent $ajan -Note "$id -> $kime ($tur)"
Yaz "Aktarim kaydedildi: $id  ($ajan -> $kime, proje: $(if ($proje) { $proje } else { '-' }), teslim: $(if ($Hedef) { "yalniz '$Hedef' projesinde" } else { 'her proje klasorunde' }))" 'Green'
Yaz "  Hedef ajan calisiyorsa bir sonraki komutunda, degilse bir sonraki mesajinda ya da acilista [Hafiza: Aktarim] blogu olarak gorur."
Yaz "  Yanit: beyin aktar `"...`" -Yanit $id   |   bekle: beyin aktar -Bekle $id   |   kapat: beyin aktar -Tamam $id" 'Cyan'
Yaz "  Turetilmis gorunum: $(Join-Path (Join-Path $Vault '10-command-center') 'aktarimlar.md')" 'DarkGray'
if ($VeBekle) { Bekle-Yanit $id $Sure; exit $script:BekleKod }
exit 0
