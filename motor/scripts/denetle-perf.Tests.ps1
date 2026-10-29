$vault = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $vault 'motor/hooks/lib.ps1')
$helper = Join-Path $PSScriptRoot 'denetle-perf.ps1'
Describe 'Denetle exact fast computations' {
    It 'keeps vector threshold before rounding and the existing PowerShell tie sorting' {
        . $helper
        $v = @{ N = 3; Dim = 2; All = [single[]](1,0, 0.80001,0, 0.79999,0); Meta = @{ items = @(@{slug='a'},@{slug='b'},@{slug='c'}) } }
        $r = @(Get-DenetimVektorCiftleri -Index $v -MinCos 0.8 -EnFazla 200)
        $r.Count | Should Be 1
        $r[0].A | Should Be 'a'
        $r[0].B | Should Be 'b'
        $r[0].Cos | Should Be 0.8
        $v.All = [single[]](1,0, 1,0, 1,0)
        $r = @(Get-DenetimVektorCiftleri -Index $v -MinCos 0.8 -EnFazla 2)
        ($r | ForEach-Object { $_.A + $_.B }) -join ',' | Should Be 'bc,ac'
    }
    It 'matches existing tokenization including Turkish letters, suffixes, stop words and repetition' {
        . $helper
        foreach ($culture in @('tr-TR','en-US')) {
            $saved = [Threading.Thread]::CurrentThread.CurrentCulture
            try {
                [Threading.Thread]::CurrentThread.CurrentCulture = $culture
                foreach ($text in @('İÇİN için ICIN indeksleri motorun motoru plugin domain', 'abc 1234 bağları notlari notlari Тест 日本語', '', 'GÜNCEL güncel guncel')) {
                    $expected = @(Get-BeyinKelimeler -Text $text | Sort-Object) -join '|'
                    (@(Get-DenetimKelimeler -Text $text | Sort-Object) -join '|') | Should Be $expected
                }
            } finally { [Threading.Thread]::CurrentThread.CurrentCulture = $saved }
        }
    }
    It 'matches canonical vector results across dimensions, thresholds and truncation' {
        . $helper
        $rng = New-Object Random 1729
        $all = New-Object single[] 84
        for ($i = 0; $i -lt $all.Length; $i++) { $all[$i] = ($rng.NextDouble() - 0.5) }
        $items = @(0..11 | ForEach-Object { @{slug=('note-' + $_)} })
        $v = @{ N=12; Dim=7; All=$all; Meta=@{items=$items} }
        $saved = $script:BeyinVecCache
        try {
            $script:BeyinVecCache = $v
            foreach ($threshold in @(0.0, 0.3, 0.8)) {
                foreach ($limit in @(1, 5, 200)) {
                    $expected = @(Get-BeyinVektorCiftleri -Paths @{} -MinCos $threshold -EnFazla $limit) | ConvertTo-Json -Compress
                    $actual = @(Get-DenetimVektorCiftleri -Index $v -MinCos $threshold -EnFazla $limit) | ConvertTo-Json -Compress
                    $actual | Should Be $expected
                }
            }
        } finally { $script:BeyinVecCache = $saved }
    }
    It 'does not merge dotted-I raw tokens with cached ASCII stop words' {
        . $helper
        foreach ($text in @('yeni', ('yen' + [char]0x130))) {
            $expected = @(Get-BeyinKelimeler -Text $text) -join '|'
            (@(Get-DenetimKelimeler -Text $text) -join '|') | Should Be $expected
        }
    }
    It 'returns actual string terms when keys shadows a hashtable member' {
        . $helper
        foreach ($case in @(
            @{ Text = 'alpha keys omega'; Expected = 'alpha|keys|omega' },
            @{ Text = 'alpha keysler omega'; Expected = 'alpha|keys|omega' },
            @{ Text = 'alpha keysin omega'; Expected = 'alpha|keysin|omega' }
        )) {
            (@(Get-BeyinKelimeler -Text $case.Text | Sort-Object) -join '|') | Should Be $case.Expected
            (@(Get-DenetimKelimeler -Text $case.Text | Sort-Object) -join '|') | Should Be $case.Expected
        }
    }
}
