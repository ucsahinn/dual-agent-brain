# aktar.Tests.ps1 - Ajanlar arasi aktarim CLI'i (2026-10-07 denetimi). Gecici vault'ta calisir;
# gercek ajanlara mesaj GITMEZ (BEYIN_VAULT gecici klasore, BEYIN_AGENT ile kimlik).
$vault = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$powershell = Join-Path $PSHOME 'powershell.exe'

function New-AktarVault {
    $tv = Join-Path $env:TEMP ('beyin-aktar-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Force -Path (Join-Path $tv 'motor\hooks'), (Join-Path $tv 'motor\scripts\.state'), (Join-Path $tv '10-command-center') | Out-Null
    Copy-Item (Join-Path $vault 'motor\hooks\lib.ps1') (Join-Path $tv 'motor\hooks\lib.ps1')
    Copy-Item (Join-Path $vault 'motor\scripts\aktar.ps1') (Join-Path $tv 'motor\scripts\aktar.ps1')
    Set-Content -Path (Join-Path $tv '.beyin-version') -Value '1.2.0'
    return $tv
}
# Aktar'i alt surecte calistirir; stdout HAM BAYT olarak yakalanir (kodlama dogrulamasi icin).
function Invoke-Aktar([string]$Tv, [string]$Ajan, [string[]]$Arg) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $powershell
    $q = { param($s) '"' + ($s -replace '"', '\"') + '"' }
    $psi.Arguments = '-NoProfile -ExecutionPolicy Bypass -File ' + (& $q (Join-Path $Tv 'motor\scripts\aktar.ps1')) + ' -Vault ' + (& $q $Tv) + ' ' + (($Arg | ForEach-Object { & $q $_ }) -join ' ')
    $psi.UseShellExecute = $false; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true; $psi.CreateNoWindow = $true
    $psi.EnvironmentVariables['BEYIN_AGENT'] = $Ajan
    $psi.EnvironmentVariables['BEYIN_VAULT'] = $Tv
    $pr = [System.Diagnostics.Process]::Start($psi)
    $ms = New-Object System.IO.MemoryStream
    $pr.StandardOutput.BaseStream.CopyTo($ms)
    $null = $pr.StandardError.ReadToEnd()
    $pr.WaitForExit()
    $bayt = $ms.ToArray()
    return @{ Kod = $pr.ExitCode; Bayt = $bayt; Metin = [Text.Encoding]::UTF8.GetString($bayt) }
}
function Id-Bul([string]$Metin) { return ([regex]::Match($Metin, '\d{8}T\d{6}-[a-f0-9]{4}')).Value }

Describe 'beyin aktar CLI (2026-10-07)' {
    It 'bos metin + gonderim bayragi sessizce liste basmaz: HATA, exit 2' {
        $tv = New-AktarVault
        try { $r = Invoke-Aktar $tv 'claude' @('-Kime', 'codex') } finally { Remove-Item -LiteralPath $tv -Recurse -Force -ErrorAction SilentlyContinue }
        $r.Kod | Should Be 2
        $r.Metin | Should Match 'gonderilecek metin bos'
    }
    It 'Turkce karakterler yonlendirilmis ciktida UTF-8 (g-breve = C4 9F)' {
        $tv = New-AktarVault
        $tr = 'deneme ' + [char]0x11F + [char]0xFC + [char]0x15F + [char]0x131 + [char]0xF6 + [char]0xE7 + ' ' + [char]0x130
        try {
            $null = Invoke-Aktar $tv 'claude' @($tr, '-Kime', 'codex')
            $l = Invoke-Aktar $tv 'codex' @()
        } finally { Remove-Item -LiteralPath $tv -Recurse -Force -ErrorAction SilentlyContinue }
        $hex = [BitConverter]::ToString($l.Bayt)
        $hex | Should Match 'C4-9F'
        $l.Metin.Contains($tr) | Should Be $true
    }
    It '-Yanit: yalniz acik ve bu ajana yazilmis soruya; gecerli yanit soruyu kapatir' {
        $tv = New-AktarVault
        try {
            $s = Id-Bul (Invoke-Aktar $tv 'claude' @('soru bir', '-Kime', 'codex')).Metin
            $yanlisAjan = Invoke-Aktar $tv 'claude' @('kendi soruma yanit', '-Yanit', $s)
            $dogru = Invoke-Aktar $tv 'codex' @('yanit bir', '-Yanit', $s)
            $kapali = Invoke-Aktar $tv 'codex' @('ikinci yanit', '-Yanit', $s)
        } finally { Remove-Item -LiteralPath $tv -Recurse -Force -ErrorAction SilentlyContinue }
        $yanlisAjan.Kod | Should Be 2
        $yanlisAjan.Metin | Should Match 'yanitini o ajan verir'
        $dogru.Kod | Should Be 0
        $dogru.Metin | Should Match 'kapatildi'
        $kapali.Kod | Should Be 2
        $kapali.Metin | Should Match 'zaten kapali'
    }
    It '-Bekle: yanit baskasi tarafindan once kapatilmis olsa da bulunur (exit 0)' {
        $tv = New-AktarVault
        try {
            $s = Id-Bul (Invoke-Aktar $tv 'codex' @('soru', '-Kime', 'claude')).Metin
            $y = Id-Bul (Invoke-Aktar $tv 'claude' @('yanit metni', '-Yanit', $s)).Metin
            $null = Invoke-Aktar $tv 'codex' @('-Tamam', $y)
            $b = Invoke-Aktar $tv 'codex' @('-Bekle', $s, '-Sure', '10')
        } finally { Remove-Item -LiteralPath $tv -Recurse -Force -ErrorAction SilentlyContinue }
        $b.Kod | Should Be 0
        $b.Metin | Should Match 'YANIT \(claude'
    }
    It 'celisen bayraklar reddedilir: -Bekle+-Yanit, -VeBekle+devir' {
        $tv = New-AktarVault
        try {
            $a = Invoke-Aktar $tv 'claude' @('x', '-Yanit', '20991231T000000-aaaa', '-Bekle', '20991231T000000-aaaa')
            $b = Invoke-Aktar $tv 'claude' @('x devir metni', '-Kime', 'claude', '-Tur', 'devir', '-VeBekle')
        } finally { Remove-Item -LiteralPath $tv -Recurse -Force -ErrorAction SilentlyContinue }
        $a.Kod | Should Be 2
        $b.Kod | Should Be 2
    }
    It 'maske kisaltmadan ONCE: 600 sinirinda kalan anahtar ham olarak saklanmaz' {
        $tv = New-AktarVault
        $sir = 'ghp_' + ('A' * 36)
        $metin = ('x' * 590) + ' ' + $sir + ' son'
        try {
            $r = Invoke-Aktar $tv 'claude' @($metin, '-Kime', 'codex')
            $ham = (Get-ChildItem (Join-Path $tv 'motor\scripts\.state\handoff') -Filter '*.json' | ForEach-Object { [IO.File]::ReadAllText($_.FullName) }) -join ''
        } finally { Remove-Item -LiteralPath $tv -Recurse -Force -ErrorAction SilentlyContinue }
        $r.Kod | Should Be 0
        $ham.Contains('ghp_AAAA') | Should Be $false
        $r.Metin | Should Match 'kisaltildi'
    }
}
