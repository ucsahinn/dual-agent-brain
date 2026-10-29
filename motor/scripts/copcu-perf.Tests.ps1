$helper = Join-Path $PSScriptRoot 'copcu-perf.ps1'
Describe 'Copcu exact directory measurements' {
    It 'collects exact ignored and untracked git statuses and fails closed on an invalid repo' {
        . $helper
        $repos = @()
        foreach ($name in @('repo one', ('repo-' + [char]0xF6))) {
            $root = Join-Path $TestDrive $name
            $null = New-Item -ItemType Directory -Path (Join-Path $root 'output') -Force
            & git -C $root init -q
            if ($LASTEXITCODE) { throw 'fixture git init failed' }
            [IO.File]::WriteAllText((Join-Path $root '.gitignore'), "output/`n")
            [IO.File]::WriteAllText((Join-Path $root 'output/stale.bin'), 'fixture')
            $repos += $root
        }
        $missing = Join-Path $TestDrive 'not-a-repo'
        $r = Get-CopcuGitDurumlari -Repolar @($repos + $missing)
        foreach ($repo in $repos) {
            $r[$repo].Ok | Should Be $true
            $r[$repo].Out.Contains("!! output/`0") | Should Be $true
            $r[$repo].Out.Contains("?? .gitignore`0") | Should Be $true
        }
        $r[$missing].Ok | Should Be $false
        $found = @(Get-CopcuRepolar -Kok @($TestDrive) -Yasak @())
        $found.Count | Should Be 2
        (@($found | Sort-Object) -join '|') | Should Be (@($repos | Sort-Object) -join '|')
    }
    It 'finds allowed descendants without entering nested repos or excluded directories' {
        . $helper
        $root = Join-Path $TestDrive 'allow-search'
        foreach ($rel in @('data/output/frames','nested/.git','nested/output','node_modules/output','.next/frames','.next-copy','render','ordinary/deep/frames')) {
            $null = New-Item -ItemType Directory -Path (Join-Path $root $rel) -Force
        }
        $r = @(Get-CopcuAllowAltDizin -Yol $root -Allow @('output','frames','render') -Prefix @('.next-') -Atla @('node_modules','.git','.next'))
        (@($r | ForEach-Object { $_.Substring($root.Length + 1).Replace('\','/') } | Sort-Object) -join ',') | Should Be '.next-copy,data/output,ordinary/deep/frames,render'
    }
    It 'discovers outer repositories while excluding forbidden roots and reparse descendants' {
        . $helper
        $root = Join-Path $TestDrive 'discovery'
        foreach ($rel in @('outer/.git','outer/nested/.git','forbidden/repo/.git','node_modules/repo/.git','invalid/.git','invalid/child/.git')) {
            $null = New-Item -ItemType Directory -Path (Join-Path $root $rel) -Force
        }
        $validate = [Func[string,bool]]{ param($path) (Split-Path -Leaf $path) -ne 'invalid' }
        $r = @(Get-CopcuRepolar -Kok @($root) -Yasak @((Join-Path $root 'forbidden')) -Dogrula $validate)
        $r.Count | Should Be 2
        (@($r | ForEach-Object { Split-Path -Leaf $_ } | Sort-Object) -join ',') | Should Be 'child,outer'
    }
    It 'counts hidden and nested files and keeps the newest file time' {
        . $helper
        $root = Join-Path $TestDrive 'olcum'
        $null = New-Item -ItemType Directory -Path (Join-Path $root 'nested') -Force
        [IO.File]::WriteAllBytes((Join-Path $root 'a.bin'), [byte[]](1,2,3))
        [IO.File]::WriteAllBytes((Join-Path $root 'nested/.hidden'), [byte[]](4,5))
        $old = [datetime]'2020-01-01T12:00:00'
        $new = [datetime]'2020-02-02T12:00:00'
        [IO.File]::SetLastWriteTime((Join-Path $root 'a.bin'), $old)
        [IO.File]::SetLastWriteTime((Join-Path $root 'nested/.hidden'), $new)
        $r = Get-CopcuOlcum $root
        $r.Bayt | Should Be 5
        $r.Dosya | Should Be 2
        $r.Son | Should Be $new
    }
    It 'returns the original empty measurement for an empty or missing directory' {
        . $helper
        $root = Join-Path $TestDrive 'empty'
        $null = New-Item -ItemType Directory -Path $root
        foreach ($path in @($root, (Join-Path $root 'missing'))) {
            $r = Get-CopcuOlcum $path
            $r.Bayt | Should Be 0
            $r.Dosya | Should Be 0
            $r.Son | Should Be ([datetime]::MinValue)
        }
    }
    It 'never measures or discovers repositories through a child junction' {
        . $helper
        $root = Join-Path $TestDrive 'junction-root'
        $outside = Join-Path $TestDrive 'junction-outside'
        $null = New-Item -ItemType Directory -Path $root
        $null = New-Item -ItemType Directory -Path (Join-Path $outside '.git') -Force
        [IO.File]::WriteAllBytes((Join-Path $outside 'keep.bin'), [byte[]](1,2,3,4))
        $link = Join-Path $root 'linked'
        $null = New-Item -ItemType Junction -Path $link -Target $outside -ErrorAction Stop
        try {
            $r = Get-CopcuOlcum $root
            $r.Bayt | Should Be 0
            $r.Dosya | Should Be 0
            @(Get-CopcuRepolar -Kok @($root) -Yasak @() -Dogrula ([Func[string,bool]]{ param($path) $true })).Count | Should Be 0
            Test-Path -LiteralPath (Join-Path $outside 'keep.bin') | Should Be $true
        } finally {
            # Delete only the junction itself; never recurse into its target.
            [IO.Directory]::Delete($link)
        }
    }
    It 'keeps legacy PS 5.1 counting and byte totals for a path over MAX_PATH' {
        . $helper
        $root = Join-Path $TestDrive 'long-file'
        $null = New-Item -ItemType Directory -Path $root
        $normal = Join-Path $root 'normal.bin'
        $long = Join-Path $root (('x' * 180) + '.bin')
        if ($long.Length -le 260) { $long = Join-Path $root (('x' * 240) + '.bin') }
        [IO.File]::WriteAllBytes($normal, [byte[]](1,2,3))
        [IO.File]::SetLastWriteTime($normal, [datetime]'2020-01-01')
        [IO.File]::WriteAllBytes(('\\?\' + $long), [byte[]](1,2,3,4,5))
        try {
            $r = Get-CopcuOlcum $root
            $r.Bayt | Should Be 3
            $r.Dosya | Should Be 2
            $r.Son | Should Be ([datetime]'2020-01-01')
        } finally { [IO.File]::Delete(('\\?\' + $long)) }
    }
}
