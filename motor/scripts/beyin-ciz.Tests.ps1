Describe 'beyin-ciz ortak cizim katmani (1.5.0)' {
    BeforeAll { . (Join-Path $PSScriptRoot 'beyin-ciz.ps1') }
    It 'VisLen: ASCII, Turkce, CJK, vekil cift emoji ve ANSI karisimi' {
        VisLen 'abc' | Should Be 3
        VisLen 'çığöşü' | Should Be 6
        VisLen '漢字' | Should Be 4
        VisLen ('a' + [char]::ConvertFromUtf32(0x1F7E1) + 'b') | Should Be 4
        VisLen "$cOk✓$RS ok" | Should Be 4
    }
    It 'Cut genisligi asmaz, renk sifirlamasiyla biter, vekil cifti bolmez' {
        $e = [char]::ConvertFromUtf32(0x1F916)
        foreach ($w in 2..12) {
            $k = Cut ("ab$e$e$e" + 'cdefghij') $w
            (VisLen $k) | Should BeLessThan ($w + 1)
            $k.EndsWith("…$RS") | Should Be $true
            ((Strip $k) -match '[\uD800-\uDBFF](?![\uDC00-\uDFFF])') | Should Be $false
        }
        Cut 'kisa' 10 | Should Be 'kisa'
    }
    It 'Pad / PadL / HLine / Row / Cols tam genislik' {
        VisLen (Pad "$cText abc$RS" 10) | Should Be 10
        VisLen (PadL 'abc' 7) | Should Be 7
        foreach ($w in @(90, 120, 170, 210)) {
            VisLen (HLine $w "$cAccent BOLUM$RS" '├' '┤') | Should Be $w
            VisLen (Row 'x' $w) | Should Be $w
            VisLen (Row (Cols 'sol' 'sag uzun metin' $w ([int](($w - 4) / 2))) $w) | Should Be $w
        }
    }
    It 'Cards satirlari tam ic genislikte (1..6 kart, 86/116/166/206)' {
        foreach ($ic in @(86, 116, 166, 206)) {
            foreach ($n in 1..6) {
                $k = @(1..$n | ForEach-Object { @{ t = "K$_"; l = @('satir bir', 'iki') } })
                foreach ($ln in (Cards $k $ic)) { "$ic/$n=$(VisLen $ln)" | Should Be "$ic/$n=$ic" }
            }
        }
    }
    It 'cubuklar ve canli cizim istenen genislikte' {
        VisLen (Bar 0.5 10 $cOk) | Should Be 10
        VisLen (MiniBar 0.3 7 $cOk) | Should Be 7
        VisLen (GradBar 0.7 12 $rgbTeal $rgbOk) | Should Be 12
        VisLen (IsiBar 0.9 10) | Should Be 10
        VisLen (Tarama 6 3 $rgbOk) | Should Be 6
        VisLen (Spark ([double[]]@(1, 5, 2)) 12 $rgbAcc $rgbTeal) | Should Be 12
        (MiniBar 0.3 7 $cOk) | Should Not Match '░'
    }
    It 'Write-CizKare tam genislikteki satira ESC[K yazmaz, kisa satira yazar' {
        $L = New-Object System.Collections.Generic.List[string]; $L.Add((Row 'tam' 30)); $L.Add('kisa')
        $eski = [Console]::Out; $sw = New-Object IO.StringWriter; [Console]::SetOut($sw)
        try { $kare = Write-CizKare $L 30 '' } finally { [Console]::SetOut($eski) }
        $satirlar = $kare -split "`n"
        $satirlar[0] | Should Not Match ([regex]::Escape("$ESC[K"))
        $satirlar[1] | Should Match ([regex]::Escape("$ESC[K"))
    }
    It 'parlama: ilk gorulme parlamaz, imza degisince parlar, 2.5 sn sonra soner; yeni anahtar tohumdan sonra parlar' {
        $d = @{}; $t0 = Get-Date '2026-10-16 10:00:00'
        Set-CizFlas $d 'a' '1' $t0 | Should Be $false
        Get-CizFlasOran $d 'a' $t0 | Should Be 0
        Set-CizFlas $d 'a' '2' $t0 | Should Be $true
        (Get-CizFlasOran $d 'a' $t0.AddMilliseconds(500)) -gt 0 | Should Be $true
        Get-CizFlasOran $d 'a' $t0.AddSeconds(3) | Should Be 0
        Set-CizFlas $d 'yeni' 'x' $t0 $true | Should Be $true
    }
    It 'guvenli metin: BMP emoji guvenli simgeye, sifir genislikli karakter silinir, panel simgeleri korunur' {
        $g = Get-CizGuvenliMetin ('✎ a ' + [char]0x2705 + ' b ' + [char]0x26A0 + [char]0xFE0F + ' c ' + [char]0x2B50 + ' d' + [char]0x200D + 'e ✓ ✕')
        $g | Should Be '✎ a ✓ b ▲ c • de ✓ ✕'
        VisLen $g | Should Be $g.Length
    }
    It 'yumusak gecis hedefe yakinsar ve orada durur' {
        $d = @{}; Get-CizTween $d 'k' 0.2 | Should Be 0.2
        $v = 0; for ($i = 0; $i -lt 40; $i++) { $v = Get-CizTween $d 'k' 0.9 }
        $v | Should Be 0.9
    }
    It 'Set-CizZemin boya: sifirlama Aurora zeminini yeniden basar; kapali duz sifirlama' {
        Set-CizZemin 'boya'; $RS | Should Match '48;2;15;20;32'
        Set-CizZemin 'kapali'; $RS | Should Be "$ESC[0m"
    }
    It 'simge politikasi: panel dosyalarinda (yorumlar haric) yasak simge yok ve her karakter izin listesinde' {
        foreach ($ad in @('beyin-ciz.ps1', 'merkez.ps1', 'merkez-veri.ps1', 'merkez-balon.ps1', 'takim-izle.ps1')) {
            $f = Join-Path $PSScriptRoot $ad
            $tok = $null; $err = $null; [void][System.Management.Automation.Language.Parser]::ParseFile($f, [ref]$tok, [ref]$err)
            $kod = (@($tok | Where-Object { $_.Kind -ne 'Comment' } | ForEach-Object { $_.Text }) -join ' ')
            $kod = $kod -replace '\[regex\][^\r\n]*', '' -replace "'\[\\u[^']*'", ''   # yasak/izinli desen tanimlari ve -replace kaynak kumeleri
            $kotu = @($CizYasakRx.Matches($kod) | ForEach-Object { 'U+{0:X4}' -f [int][char]$_.Value })
            "$ad yasak: $($kotu -join ',')" | Should Be "$ad yasak: "
            $disari = @([regex]::Matches($kod, '[^\u0000-\u024F\u2000-\u206F\u2190-\u21FF\u2200-\u22FF\u2300-\u23CF\u2500-\u25FF\u2713\u2715\u270E\u2800-\u28FF\uD800-\uDFFF]') | ForEach-Object { 'U+{0:X4}' -f [int][char]$_.Value } | Select-Object -Unique)
            "$ad izinsiz: $($disari -join ',')" | Should Be "$ad izinsiz: "
        }
    }
    It 'ad cakismasi yok: beyin-ciz islevleri lib / merkez-veri / merkez-balon ile ayni adi tasimaz' {
        $ad = { param($f) $t = $null; $e = $null; $ast = [System.Management.Automation.Language.Parser]::ParseFile($f, [ref]$t, [ref]$e); @($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false) | ForEach-Object { $_.Name }) }
        $ciz = & $ad (Join-Path $PSScriptRoot 'beyin-ciz.ps1')
        foreach ($diger in @((Join-Path (Split-Path $PSScriptRoot -Parent) 'hooks\lib.ps1'), (Join-Path $PSScriptRoot 'merkez-veri.ps1'), (Join-Path $PSScriptRoot 'merkez-balon.ps1'))) {
            $ortak = @(& $ad $diger | Where-Object { $ciz -contains $_ })
            "$(Split-Path -Leaf $diger): $($ortak -join ',')" | Should Be "$(Split-Path -Leaf $diger): "
        }
    }
    It 'Get-CizToastMetni: XML 1.0 gecersiz kontrol karakterini siler, ozel karakteri kacirir, boyu sinirlar' {
        $g = Get-CizToastMetni ("a" + [char]1 + "<b>&'" + [char]0x1B + "[31m" + [char]0xB + "c" + [char]0xFFFE)
        $g | Should Be 'a&lt;b&gt;&amp;&apos;[31mc'
        { [xml]("<t>" + $g + "</t>") } | Should Not Throw
        Get-CizToastMetni ("x`ty`r`nz") | Should Be "x`ty`r`nz"
        (Get-CizToastMetni ('a' * 500) 220).Length | Should Be 220
        Get-CizToastMetni $null | Should Be ''
    }
}
