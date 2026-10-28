. (Join-Path $PSScriptRoot 'lib.ps1')
Describe 'Single-shot devir closure is independent of the host shell identity' {
    foreach ($hostAgent in @('claude','codex')) {
        It "closes the owned Codex devir and refreshes its view from a $hostAgent host" {
            $before=$env:BEYIN_AGENT
            try {
                $env:BEYIN_AGENT=$hostAgent
                $p=Get-BeyinPaths -Vault (Join-Path $TestDrive ([guid]::NewGuid().ToString('N')))
                New-Item -ItemType Directory -Force (Join-Path $p.Vault '10-command-center') | Out-Null
                $h=Add-BeyinHandoff -Paths $p -Metin 'single-shot fixture' -Kime codex -Kind devir -FromAgent codex -GorunumYok
                $null=Update-BeyinAktarimlarMd -Paths $p
                (Close-BeyinHandoff -Paths $p -Id $h.Id -DoneBy 'single-shot consumed') | Should Be $true
                $r=Get-BeyinHandoff -Paths $p -Id $h.Id
                $r.status | Should Be tamam
                $r.a2aStatus | Should Be completed
                $view=[IO.File]::ReadAllText((Join-Path $p.Vault '10-command-center/aktarimlar.md'))
                $open=[regex]::Match($view,'(?ms)^## Acik \(\d+\)(.*?)(?=^## Kapali)').Groups[1].Value
                $open | Should Not Match ([regex]::Escape($h.Id))
                $view | Should Match '## Kapali \(son 1\)'
            } finally { $env:BEYIN_AGENT=$before }
        }
    }
    It 'keeps recipient checks for questions, explicit actors, and cross-agent devir records' {
        $before=$env:BEYIN_AGENT
        try {
            $env:BEYIN_AGENT='claude'
            $p=Get-BeyinPaths -Vault (Join-Path $TestDrive 'recipient')
            $question=Add-BeyinHandoff -Paths $p -Metin 'question fixture' -Kime codex -FromAgent claude -GorunumYok
            (Close-BeyinHandoff -Paths $p -Id $question.Id) | Should Be $false
            $cross=Add-BeyinHandoff -Paths $p -Metin 'cross fixture' -Kime codex -Kind devir -FromAgent claude -GorunumYok
            (Close-BeyinHandoff -Paths $p -Id $cross.Id) | Should Be $false
            $owned=Add-BeyinHandoff -Paths $p -Metin 'own fixture' -Kime codex -Kind devir -FromAgent codex -GorunumYok
            (Close-BeyinHandoff -Paths $p -Id $owned.Id -Agent claude) | Should Be $false
        } finally { $env:BEYIN_AGENT=$before }
    }
}
