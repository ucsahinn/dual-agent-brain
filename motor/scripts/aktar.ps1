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
    [switch]$Hepsi
)

$ErrorActionPreference = 'SilentlyContinue'
if (-not $Vault) { $Vault = $(if ($env:BEYIN_VAULT) { $env:BEYIN_VAULT } else { Split-Path (Split-Path $PSScriptRoot -Parent) -Parent }) }
function Vault-Mi([string]$Y) {
    try { return [bool]($Y -and (Test-Path -LiteralPath $Y -PathType Container) -and (Test-Path -LiteralPath (Join-Path $Y 'motor\hooks\lib.ps1') -PathType Leaf)) } catch { return $false }
}
if (-not (Vault-Mi $Vault)) {
    Write-Output "HATA: vault degil (motor\hooks\lib.ps1 yok): '$Vault'"
    exit 2
}
. (Join-Path $Vault 'motor\hooks\lib.ps1')
$p = Get-BeyinPaths -Vault $Vault
$ajan = Get-BeyinAgent

# --- Kapat: -Tamam <id> ---
if ($Tamam) {
    $k = Get-BeyinHandoff -Paths $p -Id $Tamam
    if (-not $k) { Write-Output "HATA: aktarim bulunamadi: $Tamam  (liste: beyin aktar -Hepsi)"; exit 2 }
    if ($k.status -eq 'tamam') { Write-Output "Zaten kapali: $Tamam ($($k.doneBy), $($k.doneTs))"; exit 0 }
    $k.status = 'tamam'
    $k.doneBy = $ajan
    $k.doneTs = (Get-Date).ToString('o', [Globalization.CultureInfo]::InvariantCulture)
    $yaz = Set-BeyinHandoff -Paths $p -Kayit $k
    if (-not $yaz.Ok) {
        Write-BeyinLog -Vault $Vault -Message "aktar: KAPATILAMADI $Tamam ($($yaz.Hata))"
        Write-BeyinMakbuz -Paths $p -Script 'aktar' -Outcome 'AKTAR_YAZILAMADI' -Note $yaz.Hata
        Write-Host "HATA: aktarim kapatilamadi - $($yaz.Hata)" -ForegroundColor Red
        exit 3
    }
    Update-BeyinAktarimlarMd -Paths $p | Out-Null
    Write-BeyinLog -Vault $Vault -Message "aktar: kapatildi $Tamam (kapatan=$ajan)"
    Write-BeyinMakbuz -Paths $p -Script 'aktar' -Outcome 'AKTAR_TAMAM' -Agent $ajan -Note $Tamam
    "Aktarim kapatildi: $Tamam"
    exit 0
}

# --- Liste ---
if (-not $Metin) {
    # '$hepsi' adi KULLANILAMAZ: [switch]$Hepsi parametresiyle ayni degiskendir (PS adlari harf
    # duyarsiz); diziyi switch'e atama sessizce duser ve foreach $false uzerinde doner (olculdu:
    # liste bos alanlarla basildi).
    $kayitlar = @(Get-BeyinHandoffListe -Paths $p -Hepsi:$Hepsi)
    if ($kayitlar.Count -eq 0) {
        if ($Hepsi) { 'Hic aktarim yok.' } else { 'Acik aktarim yok.  Kaydetmek icin:  beyin aktar "soru" -Kime claude|codex' }
        exit 0
    }
    foreach ($h in $kayitlar) {
        $ts = ''
        try { $ts = ([datetime]::Parse([string]$h.ts, [Globalization.CultureInfo]::InvariantCulture)).ToString('yyyy-MM-dd HH:mm', [Globalization.CultureInfo]::InvariantCulture) } catch { }
        $durum = $(if ($h.status -eq 'tamam') { "TAMAM ($($h.doneBy))" } else { 'ACIK' })
        "$($h.id)  [$durum]  $($h.from.agent) -> $($h.to)  proje: $($h.from.project)  $ts"
        "  soru   : $($h.question)"
        if ($h.evidence) { "  kanit  : $($h.evidence)" }
        if ($h.scope)    { "  kapsam : $($h.scope)" }
        if ($h.risk)     { "  risk   : $($h.risk)" }
        if ($h.next)     { "  sonraki: $($h.next)" }
        if ($h.status -ne 'tamam') { "  kapat  : beyin aktar -Tamam $($h.id)" }
        ''
    }
    exit 0
}

# --- Kaydet ---
$kime = ([string]$Kime).Trim().ToLowerInvariant()
if (-not $kime) { $kime = $(if ($ajan -eq 'codex') { 'claude' } else { 'codex' }) }
if ($kime -ne 'claude' -and $kime -ne 'codex') { Write-Output "HATA: -Kime claude ya da codex olmali (verilen: '$Kime')"; exit 2 }

# KAYIT TEK YOLDAN (2026-10-06): lib Add-BeyinHandoff (pano brifingi de ayni fonksiyonu
# kullanir). Sozlesme ayni: alanlar fail-closed maskelenir, yazim geri okunur.
$proje = ([string]$Proje).Trim()
if (-not $proje) { try { $proje = Get-BeyinProjectLeaf -Path (Get-Location).Path -Paths $p } catch { $proje = '' } }
$tur = ([string]$Tur).Trim().ToLowerInvariant()
if (-not $tur) { $tur = 'soru' }
if ($tur -ne 'soru' -and $tur -ne 'devir') { Write-Output "HATA: -Tur soru ya da devir olmali (verilen: '$Tur')"; exit 2 }
# DEVIR AYNI AJANA (2026-10-06): devir yalniz ayni ajanin AYNI projedeki acilisinda
# gosterilir ve gosterilince kapanir. Baska ajana yazilan devir sessizce gorunmez
# kalirdi (olculdu: Codex'e giden kart bildirimi bu yuzden dustu). Acikca reddet.
if ($tur -eq 'devir' -and $kime -ne $ajan) {
    Write-Output "HATA: -Tur devir yalniz ayni ajana yazilir (gonderen: $ajan, hedef: $kime). Baska ajana bildirim icin -Tur'u verme (soru/handoff)."
    exit 2
}
$sonuc = Add-BeyinHandoff -Paths $p -Metin $Metin -Kime $kime -Kanit $Kanit -Kapsam $Kapsam -Risk $Risk -Sonraki $Sonraki `
    -Proje $proje -Kind $tur -FromAgent $ajan -FromSession ([string]$env:HERDR_PANE_ID)
if ($sonuc.Kod -eq 'BOS') { Write-Output 'HATA: bos soru/handoff metni'; exit 2 }
if ($sonuc.Kod -eq 'REDAKSIYON_DUSTU') {
    Write-Output "HATA: sir redaksiyonu uygulanamadi ($($sonuc.Hata)). Aktarim YAZILMADI."
    Write-BeyinMakbuz -Paths $p -Script 'aktar' -Outcome 'AKTAR_REDAKSIYON_DUSTU' -Note $sonuc.Hata
    exit 3
}
if (-not $sonuc.Ok) {
    Write-BeyinLog -Vault $Vault -Message "aktar: YAZILAMADI ($($sonuc.Hata))"
    Write-BeyinMakbuz -Paths $p -Script 'aktar' -Outcome 'AKTAR_YAZILAMADI' -Note $sonuc.Hata
    Write-Host "HATA: aktarim kaydedilemedi - $($sonuc.Hata)" -ForegroundColor Red
    exit 3
}
if ($sonuc.Maske -gt 0) { "UYARI: $($sonuc.Maske) sir benzeri deger maskelendi." }
$id = $sonuc.Id
$md = @{ Yol = (Join-Path (Join-Path $Vault '10-command-center') 'aktarimlar.md') }
Write-BeyinLog -Vault $Vault -Message "aktar: kaydedildi $id ($ajan -> $kime, tur=$tur, proje=$proje)"
Write-BeyinMakbuz -Paths $p -Script 'aktar' -Outcome 'AKTAR_KAYDEDILDI' -Agent $ajan -Note "$id -> $kime ($tur)"
"Aktarim kaydedildi: $id  ($ajan -> $kime, proje: $(if ($proje) { $proje } else { '-' }))"
"  Hedef ajanin bir sonraki oturum acilisinda [Hafiza: Aktarim] blogu olarak gorunur; kapatmak icin: beyin aktar -Tamam $id"
if ($md -and $md.Yol) { "  Turetilmis gorunum: $($md.Yol)" }
exit 0
