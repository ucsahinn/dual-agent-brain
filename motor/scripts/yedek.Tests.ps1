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