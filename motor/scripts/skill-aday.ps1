# skill-aday.ps1 - Tekrar eden YORDAMSAL kavram notlarindan skill adayi listesi (BB4, 2026-10-06).
#
# NEDEN (AgentSpace skill-from-usage dersi): ayni "nasil yapilir" bilgisi farkli
# oturumlarda tekrar tekrar baglama geliyorsa, her seferinde not olarak enjekte
# etmek yerine bir skill olmasi daha ucuz ve daha guvenilirdir.
#
# OLCUT (olculebilir olan): kavram notu son -Gun (30) gunde en az 3 FARKLI oturuma
# ve 2 FARKLI gune enjekte edilmis (retrieval makbuzu) VE notta en az 3 adimli bir
# liste var (numarali satirlar ya da '## Adim' basligi). Notun sonradan ACILIP
# ACILMADIGI (beyin kullanim) ayri sutundur: o olcum Codex'i goremedigi ve cogu
# oturumda sifir oldugu icin olcut degil, bilgi.
#
# CIKTI: 86-compiled/skill-adaylari.md (makine-sahipli, TURETILMIS; her kosuda
# yeniden yazilir). Skill'i KIMSE otomatik acmaz: insan ya da Claude listeden
# secer ve ai-skill-create ile taslagi acar. Mevcut skill adiyla ayni slug atlanir.
#
# Kullanim: beyin skill-aday [gun] [-Json] [-KuruCalisma]

param(
    [string]$Vault = $(if ($env:BEYIN_VAULT) { $env:BEYIN_VAULT } else { Split-Path (Split-Path $PSScriptRoot -Parent) -Parent }),
    [int]$Gun = 30,
    [switch]$Json,
    [switch]$KuruCalisma
)
$ErrorActionPreference = 'SilentlyContinue'
if (-not (Test-Path -LiteralPath (Join-Path $Vault 'motor\hooks\lib.ps1'))) { Write-Output "HATA: vault degil: '$Vault'"; exit 2 }
. (Join-Path $Vault 'motor\hooks\lib.ps1')
$p = Get-BeyinPaths -Vault $Vault
$sw = [Diagnostics.Stopwatch]::StartNew()
if ($Gun -lt 7) { $Gun = 7 }; if ($Gun -gt 90) { $Gun = 90 }
$inv = [Globalization.CultureInfo]::InvariantCulture

# 1) enjeksiyonlar: kavram -> oturumlar, gunler
$enj = @{}
foreach ($m in @(Read-BeyinMakbuz -Paths $p -Gun $Gun)) {
    if ([string]$m.script -ne 'retrieval' -or [string]$m.outcome -ne 'ENJEKSIYON') { continue }
    $gunAd = ''; try { $gunAd = ([datetimeoffset]::Parse([string]$m.ts, $inv)).ToLocalTime().ToString('yyyy-MM-dd') } catch { }
    foreach ($c in @($m.concepts)) {
        if (-not $c) { continue }
        $c = [string]$c
        if (-not $enj.ContainsKey($c)) { $enj[$c] = @{ Oturum = @{}; Gun = @{} } }
        if ($m.key) { $enj[$c].Oturum[[string]$m.key] = $true }
        if ($gunAd) { $enj[$c].Gun[$gunAd] = $true }
    }
}
# 2) kullanim (bilgi sutunu)
$kul = @{}
try {
    $ks = Get-Content -LiteralPath (Join-Path $p.ScrState 'kullanim-son.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($k in @($ks.kavramlar)) { $kul[[string]$k.kavram] = ([int]$k.acildi + [int]$k.anildi) }
} catch { }
# 3) mevcut skill adlari (ayni slug atlanir)
$skillAd = @{}
foreach ($d in @((Join-Path $env:USERPROFILE '.claude\skills'), (Join-Path $env:USERPROFILE '.agents\skills'), (Join-Path $env:USERPROFILE '.codex\skills'))) {
    if (Test-Path -LiteralPath $d) { foreach ($s in @(Get-ChildItem -LiteralPath $d -Directory)) { $skillAd[$s.Name.ToLowerInvariant()] = $true } }
}
# 4) aday secimi
$conceptDir = Join-Path $p.Compiled 'concepts'
$adaylar = New-Object System.Collections.Generic.List[object]
foreach ($c in $enj.Keys) {
    $e = $enj[$c]
    if ($e.Oturum.Count -lt 3 -or $e.Gun.Count -lt 2) { continue }
    $slug = [IO.Path]::GetFileNameWithoutExtension($c).ToLowerInvariant()
    if ($skillAd.ContainsKey($slug)) { continue }
    $f = Join-Path $conceptDir $c
    if (-not (Test-Path -LiteralPath $f)) { continue }
    $govde = [IO.File]::ReadAllText($f)
    # Makine bakimli '## Ilgili notlar' bolumu (wikilink maddeleri) sayilmaz.
    $govde = [regex]::Replace($govde, '(?ms)^## Ilgili notlar.*?(?=^## |\z)', '')
    $adim = ([regex]::Matches($govde, '(?m)^[ \t]*\d{1,2}[.)][ \t]+\S')).Count
    $madde = ([regex]::Matches($govde, '(?m)^[ \t]*[-*][ \t]+\S')).Count
    $baslik = [regex]::IsMatch($govde, '(?im)^#{2,4}[ \t]*(adim|adimlar|yordam|nasil|steps?|procedure)')
    if ($adim -lt 3 -and $madde -lt 4 -and -not $baslik) { continue }
    $tm = [regex]::Match($govde, '(?m)^title:\s*"?(.+?)"?\s*$')
    $adaylar.Add([pscustomobject]@{ Dosya = $c; Baslik = $(if ($tm.Success) { $tm.Groups[1].Value } else { $slug }); Oturum = $e.Oturum.Count; Gun = $e.Gun.Count
        Adim = $adim; Madde = $madde; Kullanim = $(if ($kul.ContainsKey($c)) { $kul[$c] } else { -1 }) })
}
$sirali = @($adaylar | Sort-Object @{ Expression = 'Oturum'; Descending = $true }, @{ Expression = 'Adim'; Descending = $true }, @{ Expression = 'Madde'; Descending = $true })

$rapor = [ordered]@{ v = 1; ts = (Get-Date).ToString('o', $inv); gun = $Gun; aday = $sirali.Count; kavramEnjekte = $enj.Count
    adaylar = @($sirali | ForEach-Object { [ordered]@{ dosya = $_.Dosya; baslik = $_.Baslik; oturum = $_.Oturum; gun = $_.Gun; adim = $_.Adim; madde = $_.Madde; kullanim = $_.Kullanim } }) }

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('# Skill adaylari')
[void]$sb.AppendLine('')
[void]$sb.AppendLine("> Makine-sahipli, TURETILMIS (beyin skill-aday, $((Get-Date).ToString('yyyy-MM-dd HH:mm'))). Elle duzenleme; her kosuda yeniden yazilir.")
[void]$sb.AppendLine("> Olcut: son $Gun gunde 3+ farkli oturuma ve 2+ farkli gune enjekte edilmis, liste iceren kavram notu (3+ numarali adim, 4+ madde ya da 'Adimlar' basligi; 'Ilgili notlar' sayilmaz). Numarali adim guclu, madde zayif yordam isaretidir.")
[void]$sb.AppendLine('> Skill otomatik acilmaz: secip `ai-skill-create` ile taslagi ac. "Kullanim" = sonradan acilma/anilma (beyin kullanim; -1 olculmedi).')
[void]$sb.AppendLine('')
if ($sirali.Count -eq 0) { [void]$sb.AppendLine("Aday yok ($($enj.Count) kavram enjekte edildi; hicbiri olcutu karsilamadi).") } else {
    [void]$sb.AppendLine('| Kavram | Oturum | Gun | Adim | Madde | Kullanim |')
    [void]$sb.AppendLine('| --- | ---: | ---: | ---: | ---: | ---: |')
    foreach ($a in $sirali) { [void]$sb.AppendLine("| [[concepts/$([IO.Path]::GetFileNameWithoutExtension($a.Dosya))|$($a.Baslik -replace '\|', '/')]] | $($a.Oturum) | $($a.Gun) | $($a.Adim) | $($a.Madde) | $($a.Kullanim) |") }
}
$hedef = Join-Path $p.Compiled 'skill-adaylari.md'
if (-not $KuruCalisma) { Write-BeyinText -Path $hedef -Text $sb.ToString() }
Write-BeyinMakbuz -Paths $p -Script 'skill-aday' -Outcome $(if ($KuruCalisma) { 'SKILL_ADAY_KURU' } else { 'SKILL_ADAY_OK' }) -DurationMs $sw.ElapsedMilliseconds -Note "gun=$Gun aday=$($sirali.Count) enjekte=$($enj.Count)"

if ($Json) { $rapor | ConvertTo-Json -Depth 5; exit 0 }
"SKILL ADAYLARI (son $Gun gun; $($enj.Count) kavram enjekte edildi; $($sw.ElapsedMilliseconds) ms)$(if ($KuruCalisma) { ' [KURU: dosya yazilmadi]' })"
if ($sirali.Count -eq 0) { "  aday yok" } else {
    foreach ($a in @($sirali | Select-Object -First 15)) { "  {0,-60} oturum {1,2}  gun {2,2}  adim {3,2}  madde {4,2}  kullanim {5}" -f $(if ($a.Baslik.Length -gt 60) { $a.Baslik.Substring(0, 57) + '...' } else { $a.Baslik }), $a.Oturum, $a.Gun, $a.Adim, $a.Madde, $a.Kullanim }
}
"  Rapor: 86-compiled/skill-adaylari.md"
exit 0
