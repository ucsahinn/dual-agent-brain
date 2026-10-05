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

function Temizle([string]$T, [int]$Max) {
    $t = ([string]$T -replace '\s+', ' ').Trim()
    if ($t.Length -gt $Max) { $t = $t.Substring(0, $Max - 3) + '...' }
    return $t
}
$alanlar = [ordered]@{ question = (Temizle $Metin 600); evidence = (Temizle $Kanit 300); scope = (Temizle $Kapsam 300); risk = (Temizle $Risk 300); next = (Temizle $Sonraki 300) }
if (-not $alanlar.question) { Write-Output 'HATA: bos soru/handoff metni'; exit 2 }
$maskeToplam = 0
foreach ($ad in @($alanlar.Keys)) {
    if (-not $alanlar[$ad]) { continue }
    $prot = Protect-BeyinSecrets -Text $alanlar[$ad] -Vault $Vault
    # FAIL-CLOSED: redaksiyon duserse YAZMA (niyet.ps1 ile ayni sozlesme).
    if ($prot.Failed -gt 0) {
        Write-Output "HATA: sir redaksiyonu uygulanamadi ($($prot.Failed) desen). Aktarim YAZILMADI."
        Write-BeyinMakbuz -Paths $p -Script 'aktar' -Outcome 'AKTAR_REDAKSIYON_DUSTU' -Note "$($prot.Failed) desen uygulanamadi"
        exit 3
    }
    $alanlar[$ad] = $prot.Text
    $maskeToplam += [int]$prot.Redactions
}
if ($maskeToplam -gt 0) { "UYARI: $maskeToplam sir benzeri deger maskelendi." }

$proje = ([string]$Proje).Trim()
if (-not $proje) { try { $proje = Get-BeyinProjectLeaf -Path (Get-Location).Path -Paths $p } catch { $proje = '' } }
$id = (Get-Date).ToString('yyyyMMddTHHmmss', [Globalization.CultureInfo]::InvariantCulture) + '-' + ([guid]::NewGuid().ToString('N').Substring(0, 4))
$kayit = [ordered]@{
    v        = 1
    id       = $id
    ts       = (Get-Date).ToString('o', [Globalization.CultureInfo]::InvariantCulture)
    from     = [ordered]@{ agent = $ajan; session = [string]$env:HERDR_PANE_ID; project = $proje }
    to       = $kime
    question = $alanlar.question
    evidence = $alanlar.evidence
    scope    = $alanlar.scope
    risk     = $alanlar.risk
    next     = $alanlar.next
    status   = 'acik'
    doneBy   = ''
    doneTs   = ''
}
$yaz = Set-BeyinHandoff -Paths $p -Kayit $kayit
if (-not $yaz.Ok) {
    Write-BeyinLog -Vault $Vault -Message "aktar: YAZILAMADI ($($yaz.Hata))"
    Write-BeyinMakbuz -Paths $p -Script 'aktar' -Outcome 'AKTAR_YAZILAMADI' -Note $yaz.Hata
    Write-Host "HATA: aktarim kaydedilemedi - $($yaz.Hata)" -ForegroundColor Red
    exit 3
}
# GERI OKUMA: motorun session-start'ta kullanacagi yoldan (niyet.ps1 sozlesmesi).
$geri = Get-BeyinHandoff -Paths $p -Id $id
if (-not $geri -or [string]$geri.question -ne [string]$alanlar.question) {
    Write-BeyinLog -Vault $Vault -Message "aktar: YAZILAMADI (geri okuma farkli ya da yok: $id)"
    Write-BeyinMakbuz -Paths $p -Script 'aktar' -Outcome 'AKTAR_YAZILAMADI' -Note 'geri okuma farkli'
    Write-Host 'HATA: aktarim yazildi sanildi ama geri okunamadi' -ForegroundColor Red
    exit 3
}
$md = Update-BeyinAktarimlarMd -Paths $p
Write-BeyinLog -Vault $Vault -Message "aktar: kaydedildi $id ($ajan -> $kime, proje=$proje, $($alanlar.question.Length) kr)"
Write-BeyinMakbuz -Paths $p -Script 'aktar' -Outcome 'AKTAR_KAYDEDILDI' -Agent $ajan -Note "$id -> $kime"
"Aktarim kaydedildi: $id  ($ajan -> $kime, proje: $(if ($proje) { $proje } else { '-' }))"
"  Hedef ajanin bir sonraki oturum acilisinda [Hafiza: Aktarim] blogu olarak gorunur; kapatmak icin: beyin aktar -Tamam $id"
if ($md -and $md.Yol) { "  Turetilmis gorunum: $($md.Yol)" }
exit 0
