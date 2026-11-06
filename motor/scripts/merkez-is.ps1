param(
    [Parameter(Mandatory = $true)][string]$Vault,
    [Parameter(Mandatory = $true)][string]$IsId,
    [switch]$Gorunur,
    [Parameter(ValueFromRemainingArguments = $true)][string[]]$Arg = @()
)
# merkez-is.ps1 - Beyin MERKEZ is kosucusu (2026-10-31).
# Merkez bir eylemi (koşuyu doğrula, kartı kapat, aktarımı kapat, teşhis düzelt) kendisi BEKLEMEZ: bu kosucuyu ya gorunur bir
# Windows Terminal sekmesinde (uzun takim adimlari: ciktiyi kullanici izler) ya da gizli olarak baslatir. Kosucu `beyin <arg>`
# komutunu calistirir ve sonucu .state\merkez-isler\<IsId>.json dosyasina yazar; merkez o dosyayi okuyup sonucu gosterir.
# Arguman listesi merkez tarafinda beyaz listeden gecmistir (Test-MerkezEylemArgv); burada YENIDEN denetlenir (dosyayi dogrudan
# cagiran baska biri icin). Kosucu onay URETMEZ: insan onayi merkezin kendi surecinde, gercek tus basisiyla yazilir.
$ErrorActionPreference = 'Continue'
. (Join-Path $Vault 'motor\hooks\lib.ps1')
. (Join-Path $PSScriptRoot 'merkez-eylem.ps1')
$p = Get-BeyinPaths -Vault $Vault
$dir = Get-MerkezIsDizin -Paths $p
if ($IsId -notmatch '^[A-Za-z0-9-]{6,64}$') { exit 2 }
$f = Join-Path $dir "$IsId.json"
$inv = [Globalization.CultureInfo]::InvariantCulture
function Yaz($o) { try { Write-BeyinText -Path $f -Text (ConvertTo-Json -InputObject $o -Compress -Depth 4) } catch { } }
$kayit = [ordered]@{ v = 1; id = $IsId; argv = @($Arg); durum = 'calisiyor'; pid = $PID; basladi = (Get-Date).ToString('o', $inv); bitti = ''; kod = $null; son = @(); gorunur = [bool]$Gorunur }
if (-not (Test-MerkezEylemArgv -Argv $Arg)) {
    $kayit.durum = 'reddedildi'; $kayit.kod = 2; $kayit.son = @('komut beyaz listede degil'); $kayit.bitti = (Get-Date).ToString('o', $inv); Yaz $kayit
    exit 2
}
Yaz $kayit
$beyin = Get-MerkezBeyinCli
$cikis = New-Object System.Collections.Generic.List[string]
$kod = 1
try {
    if ($Gorunur) {
        try { $Host.UI.RawUI.WindowTitle = "beyin $($Arg -join ' ')" } catch { }
        Write-Host "▶ beyin $($Arg -join ' ')" -ForegroundColor Cyan
        Write-Host ''
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $beyin @Arg 2>&1 | ForEach-Object { $s = "$_"; $cikis.Add($s); if ($cikis.Count -gt 400) { $cikis.RemoveAt(0) }; Write-Host $s }
    } else {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $beyin @Arg 2>&1 | ForEach-Object { $s = "$_"; $cikis.Add($s); if ($cikis.Count -gt 400) { $cikis.RemoveAt(0) } }
    }
    $kod = $LASTEXITCODE
} catch { $cikis.Add("HATA: $($_.Exception.Message)"); $kod = 1 }
$kayit.durum = $(if ($kod -eq 0) { 'tamam' } else { 'hata' })
$kayit.kod = $kod
$kayit.son = @($cikis | Where-Object { "$_".Trim() -and "$_".Trim() -notmatch '^[\[\]{},"]+$' } | Select-Object -Last 12 | ForEach-Object { Protect-MerkezEylemMetin $_ 300 })
$kayit.bitti = (Get-Date).ToString('o', $inv)
Yaz $kayit
try { Write-BeyinMakbuz -Paths $p -Script 'merkez' -Outcome $(if ($kod -eq 0) { 'EYLEM_OK' } else { 'EYLEM_HATA' }) -Agent 'merkez' -Reason 'merkez' -Note ("$($Arg -join ' ') exit=$kod") } catch { }
if ($Gorunur) {
    Write-Host ''
    if ($kod -eq 0) { Write-Host "✓ bitti (kod 0). Merkez sonucu gösteriyor; bu sekmeyi kapatabilirsin." -ForegroundColor Green }
    else { Write-Host "✕ çıkış kodu $kod. Çıktı yukarıda; merkez de son satırları gösteriyor." -ForegroundColor Red }
    Write-Host 'Kapatmak için bir tuşa bas…' -ForegroundColor DarkGray
    try { [void][Console]::ReadKey($true) } catch { Start-Sleep -Seconds 30 }
}
exit $kod
