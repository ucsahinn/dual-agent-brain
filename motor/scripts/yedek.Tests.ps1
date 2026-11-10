# yedek.Tests.ps1 - beyin yedek dagiticisi (2026-11-10): brain-cli basarisizsa motorun kendi yedegine duser.
Describe 'beyin yedek: brain-cli basarisizliginda yerli yedege dusus (2026-11-10)' {
    BeforeAll {
        $script:kaynak = [IO.File]::ReadAllText((Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'kurulum\beyin.ps1'))
        $i = $script:kaynak.IndexOf("& node `$cli backup --target `$vault --apply")
        $script:parca = $(if ($i -ge 0) { $script:kaynak.Substring($i, [Math]::Min(900, $script:kaynak.Length - $i)) } else { '' })
    }
    It 'brain-cli cagrisi var ve cikis kodu saklaniyor' {
        $script:parca | Should Not BeNullOrEmpty
        $script:parca | Should Match '\$cliKod = \$LASTEXITCODE'
    }
    It 'sifir olmayan kodda yedek.ps1 cagriliyor' {
        $script:parca | Should Match 'if \(\$cliKod -ne 0\)'
        $script:parca | Should Match "Cagir 'yedek\.ps1'"
    }
    It 'yerli yedek .state klasorlerini haric tutar' {
        [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'yedek.ps1')) | Should Match "\`$HARIC_AD\s+=\s+@\('\.state'\)"
    }
}

Describe 'beyin yedek: brain-cli backup-* budamasi (2026-11-10)' {
    BeforeAll {
        $kaynak = [IO.File]::ReadAllText((Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'kurulum\beyin.ps1'))
        $bas = $kaynak.IndexOf('        $tut = 5')
        $son = $kaynak.IndexOf('exit $cliKod', $bas)
        $script:blok = $(if ($bas -ge 0 -and $son -gt $bas) { $kaynak.Substring($bas, $son - $bas) } else { '' })
        function script:Yeni-Kok([string[]]$Tam, [string[]]$Yarim) {
            $k = Join-Path ([IO.Path]::GetTempPath()) ('beyin-buda-' + [guid]::NewGuid().ToString('N'))
            foreach ($n in $Tam) { $d = Join-Path $k ".brain\backups\$n"; New-Item -ItemType Directory -Force -Path $d | Out-Null; Set-Content (Join-Path $d 'manifest.json') '{}' }
            foreach ($n in $Yarim) { New-Item -ItemType Directory -Force -Path (Join-Path $k ".brain\backups\$n") | Out-Null }
            New-Item -ItemType Directory -Force -Path (Join-Path $k '.brain\backups\beyin-2026-01-01T00-00-00') | Out-Null
            return $k
        }
        function script:Kos([string]$Kok, [object[]]$Gecen) {
            $vault = $Kok; $a = [pscustomobject]@{ Gecen = $Gecen }
            & ([scriptblock]::Create($script:blok)) | Out-Null
            @(Get-ChildItem (Join-Path $Kok '.brain\backups') -Directory | ForEach-Object Name | Sort-Object)
        }
    }
    It 'budama blogu bulunuyor' { $script:blok | Should Match 'manifest\.json' }
    It 'en yeni N tam yedegi tutar, yarim ve beyin-* klasorlerine dokunmaz' {
        $k = Yeni-Kok -Tam @('backup-2026-01-01', 'backup-2026-01-02', 'backup-2026-01-03', 'backup-2026-01-04') -Yarim @('backup-2026-01-05')
        try {
            $kalan = Kos $k @('-tut', '2')
            ($kalan -join ',') | Should Be 'backup-2026-01-03,backup-2026-01-04,backup-2026-01-05,beyin-2026-01-01T00-00-00'
        } finally { Remove-Item $k -Recurse -Force }
    }
    It '-Tut 0 budamayi kapatir' {
        $k = Yeni-Kok -Tam @('backup-2026-01-01', 'backup-2026-01-02', 'backup-2026-01-03') -Yarim @()
        try { (Kos $k @('-tut', '0')).Count | Should Be 4 } finally { Remove-Item $k -Recurse -Force }
    }
    It 'varsayilan 5 tutar' {
        $k = Yeni-Kok -Tam @(1..7 | ForEach-Object { "backup-2026-01-0$_" }) -Yarim @()
        try { (Kos $k @()).Count | Should Be 6 } finally { Remove-Item $k -Recurse -Force }
    }
}