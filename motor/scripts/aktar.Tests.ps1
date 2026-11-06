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

Describe 'stale handoff maintenance in a temporary vault' {
    It 'previews age and missing targets, then closes with reasons without deleting history' {
        . (Join-Path $vault 'motor/hooks/lib.ps1')
        $tv=New-AktarVault;$tp=Get-BeyinPaths -Vault $tv
        try {
            $ids=@()
            foreach($name in @('old','missing','fresh')){
                $r=Add-BeyinHandoff -Paths $tp -Metin $name -Kime claude -FromAgent codex -GorunumYok
                $ids+= $r.Id;$h=Get-BeyinHandoff $tp $r.Id
                if($name -eq 'old'){$h.ts=[datetime]::UtcNow.AddDays(-4).ToString('o')}
                if($name -eq 'missing'){$h|Add-Member -NotePropertyName toProjectPath -NotePropertyValue (Join-Path $tv 'missing-project') -Force}
                $null=Set-BeyinHandoff $tp $h
            }
            $dry=Invoke-Aktar $tv codex @('-Bayat','3')
            $dry.Kod | Should Be 0
            $dry.Metin | Should Match 'yas';$dry.Metin | Should Match 'hedef klasoru yok'
            @(Get-BeyinHandoffListe $tp).Count | Should Be 3
            $apply=Invoke-Aktar $tv codex @('-Bayat','3','-Uygula')
            $apply.Kod | Should Be 0
            @(Get-BeyinHandoffListe $tp).Count | Should Be 1
            @(Get-BeyinHandoffListe $tp -Hepsi).Count | Should Be 3
            (Get-BeyinHandoff $tp $ids[0]).doneBy | Should Match 'bayat.*yas'
            (Get-BeyinHandoff $tp $ids[1]).doneBy | Should Match 'hedef klasoru yok'
            (Get-BeyinHandoff $tp $ids[2]).status | Should Be acik
        } finally {Remove-Item -LiteralPath $tv -Recurse -Force}
    }
}

Describe 'aktar -Topla (2026-11-06): teslim edilmis, yetim ve bayat aktarimlar tek seferde' {
    It 'kurallar: yetim isci devri, yerine yenisi gelen devir, bayat devir, teslim edilmis soru/yanit kapanir; taze ya da gorulmemis kalir' {
        . (Join-Path $vault 'motor/hooks/lib.ps1')
        $tv = New-AktarVault; $tp = Get-BeyinPaths -Vault $tv
        try {
            $yap = {
                param($ad, $kind, $kime, $kimden, $proje, [double]$gun, [bool]$teslim)
                $r = Add-BeyinHandoff -Paths $tp -Metin "$ad metni" -Kime $kime -FromAgent $kimden -Proje $proje -Kind $kind -GorunumYok
                $h = Get-BeyinHandoff $tp $r.Id; $h.ts = [datetime]::UtcNow.AddDays(-$gun).ToString('o'); $null = Set-BeyinHandoff $tp $h
                if ($teslim) { $d = Join-Path $tp.ScrState "handoff-teslim\oturum-$ad"; New-Item -ItemType Directory -Force -Path $d | Out-Null; New-Item -ItemType File -Path (Join-Path $d $r.Id) | Out-Null }
                return $r.Id
            }
            $id = [ordered]@{
                yetim         = & $yap 'yetim' 'devir' 'codex' 'codex' 'TASK-ABC' 0.1 $false
                eskiDevir     = & $yap 'eskiDevir' 'devir' 'codex' 'codex' 'p' 2 $false
                yeniDevir     = & $yap 'yeniDevir' 'devir' 'codex' 'codex' 'p' 1 $false
                bayatDevir    = & $yap 'bayatDevir' 'devir' 'claude' 'claude' 'q' 8 $false
                gorulduEski   = & $yap 'gorulduEski' 'soru' 'claude' 'codex' 'p' 4 $true
                gorulmediEski = & $yap 'gorulmediEski' 'soru' 'claude' 'codex' 'p' 4 $false
                cokEski       = & $yap 'cokEski' 'soru' 'codex' 'claude' 'p' 15 $false
                yanit         = & $yap 'yanit' 'yanit' 'codex' 'claude' 'p' 0.2 $true
                taze          = & $yap 'taze' 'soru' 'codex' 'claude' 'p' 1 $true
            }
            $kuru = Invoke-Aktar $tv codex @('-Topla')
            $kuru.Kod | Should Be 0
            $kuru.Metin | Should Match '6 kapatilacak, 3 kalacak'
            $kuru.Metin | Should Match 'KURU'
            @(Get-BeyinHandoffListe $tp).Count | Should Be 9
            $uy = Invoke-Aktar $tv codex @('-Topla', '-Uygula')
            $uy.Kod | Should Be 0
            $uy.Metin | Should Match 'kapandi: 6'
            foreach ($k in @('yetim', 'eskiDevir', 'bayatDevir', 'gorulduEski', 'cokEski', 'yanit')) { (Get-BeyinHandoff $tp $id[$k]).status | Should Be 'tamam'; (Get-BeyinHandoff $tp $id[$k]).doneBy | Should Match 'topla' }
            foreach ($k in @('yeniDevir', 'gorulmediEski', 'taze')) { (Get-BeyinHandoff $tp $id[$k]).status | Should Be 'acik' }
            (Get-BeyinHandoff $tp $id.yetim).doneBy | Should Match 'yetim'
            (Get-BeyinHandoff $tp $id.eskiDevir).doneBy | Should Match 'yeni devir'
            @(Get-BeyinHandoffListe $tp -Hepsi).Count | Should Be 9   # gecmis silinmez
            (Invoke-Aktar $tv codex @('-Topla', '-Kime', 'claude')).Kod | Should Be 2   # celisen bayrak reddedilir
        } finally { Remove-Item -LiteralPath $tv -Recurse -Force }
    }
    It 'isci worktree''si ve gecici klasor devir yazmaz (kaynakta kesilir)' {
        . (Join-Path $vault 'motor/hooks/lib.ps1')
        Test-BeyinDevirsizKonum -Proje 'TASK-DOC2-IZIN' | Should Be $true
        Test-BeyinDevirsizKonum -Proje '_integration' | Should Be $true
        $kok = Join-Path ([IO.Path]::GetPathRoot([IO.Path]::GetTempPath())) 'ornek-kok'
        Test-BeyinDevirsizKonum -Yol (Join-Path $kok '.agentchef-worktrees\R20261031-a71d\TASK-1') | Should Be $true
        Test-BeyinDevirsizKonum -Yol (Join-Path ([IO.Path]::GetTempPath()) 'x20-https-www') | Should Be $true
        Test-BeyinDevirsizKonum -Yol (Join-Path $kok 'ornek-proje') -Proje 'ornek-proje' | Should Be $false
        Test-BeyinDevirsizKonum -Proje 'task-list' | Should Be $false
        (Get-Content (Join-Path $vault 'motor\scripts\flush.ps1') -Raw) | Should Match 'Test-BeyinDevirsizKonum -Yol \$ProjectPath'
    }
}

Describe 'ajan tespiti ve vault ici hedef suzgeci (2026-10-08)' {
    It 'Codex kabugundan (CODEX_SESSION_ID, BEYIN_AGENT yok) gonderen codex etiketlenir; CLAUDECODE claude' {
        . (Join-Path $vault 'motor\hooks\lib.ps1')
        $eski = @{}
        foreach ($ad in @('BEYIN_AGENT', 'CLAUDECODE', 'CODEX_SESSION_ID', 'CODEX_THREAD_ID', 'CODEX_MANAGED_BY_NPM', 'CODEX_MANAGED_BY_BUN', 'CODEX_MANAGED_BY_PNPM', 'CODEX_MANAGED_PACKAGE_ROOT', 'CODEX_SANDBOX')) {
            $eski[$ad] = [Environment]::GetEnvironmentVariable($ad); [Environment]::SetEnvironmentVariable($ad, $null)
        }
        try {
            $env:CODEX_SESSION_ID = 'x'; $a = Get-BeyinAgent
            $env:CODEX_SESSION_ID = $null; $env:CLAUDECODE = '1'; $b = Get-BeyinAgent
            $env:CLAUDECODE = $null; $c = Get-BeyinAgent
            $env:CODEX_SESSION_ID = 'x'; $env:BEYIN_AGENT = 'claude'; $d = Get-BeyinAgent
        } finally { foreach ($ad in $eski.Keys) { [Environment]::SetEnvironmentVariable($ad, $eski[$ad]) } }
        "$a|$b|$c|$d" | Should Be 'codex|claude|claude|claude'
    }
    It '-Hedef verilmis mesaj vault icindeki oturuma (KonumProje Beyin) dusmez; hedefsiz duser' {
        . (Join-Path $vault 'motor\hooks\lib.ps1')
        $tv = New-AktarVault
        $tp = Get-BeyinPaths -Vault $tv
        try {
            $h1 = Add-BeyinHandoff -Paths $tp -Metin 'proje-a icin' -Kime 'claude' -Proje 'x' -HedefProje 'proje-a' -FromAgent 'codex' -GorunumYok
            $h2 = Add-BeyinHandoff -Paths $tp -Metin 'herkese' -Kime 'claude' -Proje 'x' -FromAgent 'codex' -GorunumYok
            $vaultta = @(Get-BeyinHandoffAcik -Paths $tp -Kime 'claude' -Proje '' -KonumProje 'Beyin' | ForEach-Object { [string]$_.id })
            $projeA = @(Get-BeyinHandoffAcik -Paths $tp -Kime 'claude' -Proje 'proje-a' -KonumProje 'proje-a' | ForEach-Object { [string]$_.id })
        } finally { Remove-Item -LiteralPath $tv -Recurse -Force -ErrorAction SilentlyContinue }
        ($vaultta -contains $h1.Id) | Should Be $false
        ($vaultta -contains $h2.Id) | Should Be $true
        ($projeA -contains $h1.Id) | Should Be $true
    }
}

Describe 'beyin aktar CLI (2026-10-07)' {
    It 'closes a sparse briefing when its board card advances' {
        . (Join-Path $vault 'motor/hooks/lib.ps1')
        $tv = New-AktarVault
        $tp = Get-BeyinPaths -Vault $tv
        try {
            $id = '20261028T205426-3333'
            $notice = [pscustomobject]@{ v=2; id=$id; ts='2026-10-28T20:54:26Z'; from=@{agent='pano';project='fixture'}; to='claude'; kind='brifing'; ref='TASK-1@review@fixture'; status='acik'; question='Review fixture' }
            (Set-BeyinHandoff $tp $notice).Ok | Should Be $true
            Write-BeyinText -Path $tp.Board -Text '{"tasks":[{"id":"TASK-1","status":"in_progress"}]}'
            (Sync-BeyinPanoBrifing -Paths $tp).Kapanan | Should Be 1
            $saved = Get-BeyinHandoff $tp $id
            $saved.status | Should Be tamam
            $saved.doneBy | Should Be 'pano (kart ilerledi)'
            [string]::IsNullOrWhiteSpace($saved.doneTs) | Should Be $false
        } finally { Remove-Item -LiteralPath $tv -Recurse -Force -ErrorAction SilentlyContinue }
    }
    It 'closes a legacy channel notice without optional state or receipt fields' {
        . (Join-Path $vault 'motor/hooks/lib.ps1')
        $tv = New-AktarVault
        $tp = Get-BeyinPaths -Vault $tv
        try {
            $id = '20261028T205426-3332'
            $notice = [pscustomobject]@{ v=2; id=$id; ts='2026-10-28T20:54:26Z'; from=@{agent='codex';project='fixture'}; to='claude'; kind='bilgi'; status='acik'; question='Kanal fixture completed' }
            (Set-BeyinHandoff $tp $notice).Ok | Should Be $true
            $denied = Invoke-Aktar $tv codex @('-Tamam',$id)
            $denied.Kod | Should Be 2
            $read = Read-BeyinHandoff -Paths $tp -Id $id -Agent claude
            [string]::IsNullOrWhiteSpace($read.readTs) | Should Be $false
            $closed = Invoke-Aktar $tv claude @('-Tamam',$id)
            $closed.Kod | Should Be 0
            $saved = Get-BeyinHandoff $tp $id
            $saved.status | Should Be tamam
            $saved.a2aStatus | Should Be completed
            $saved.doneBy | Should Be claude
            [string]::IsNullOrWhiteSpace($saved.doneTs) | Should Be $false
            $again = Invoke-Aktar $tv claude @('-Tamam',$id)
            $again.Kod | Should Be 0
            (Get-BeyinHandoff $tp $id).doneTs | Should Be $saved.doneTs
        } finally { Remove-Item -LiteralPath $tv -Recurse -Force -ErrorAction SilentlyContinue }
    }
    It 'only the recipient can close a handoff through Tamam' {
        $tv = New-AktarVault
        try {
            $sent = Invoke-Aktar $tv codex @('recipient close fixture','-Kime','claude')
            $id = Id-Bul $sent.Metin
            $denied = Invoke-Aktar $tv codex @('-Tamam',$id)
            $denied.Kod | Should Be 2
            $allowed = Invoke-Aktar $tv claude @('-Tamam',$id)
            $allowed.Kod | Should Be 0
        } finally { Remove-Item -LiteralPath $tv -Recurse -Force -ErrorAction SilentlyContinue }
    }
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

Describe 'beyin aktar dinle (2026-10-19): canli uyandirma - yeni aktarim 5 sn icinde tek satir' {
    It 'Claude''a adresli yeni aktarim 5 sn icinde AKTAR satiri olarak duser; Codex''e gideni basmaz; kacis temizlenir, tam metin basilmaz' {
        $kaynak = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
        $fx = Join-Path ([IO.Path]::GetTempPath()) ('dinle-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path (Join-Path $fx 'motor\hooks'), (Join-Path $fx 'motor\scripts') | Out-Null
        Copy-Item (Join-Path $kaynak 'motor\hooks\lib.ps1') (Join-Path $fx 'motor\hooks')
        Copy-Item (Join-Path $PSScriptRoot 'aktar.ps1'), (Join-Path $PSScriptRoot 'aktar-dinle.ps1') (Join-Path $fx 'motor\scripts')
        $cikti = Join-Path $fx 'dinle.out'; $proc = $null; $previousAgent = $env:BEYIN_AGENT
        try {
            $env:BEYIN_AGENT = 'claude'
            $proc = Start-Process powershell.exe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $fx 'motor\scripts\aktar-dinle.ps1'), '-Vault', $fx, '-Kime', 'claude', '-Sure', '40') -RedirectStandardOutput $cikti -WindowStyle Hidden -PassThru
            $sw = [Diagnostics.Stopwatch]::StartNew()
            while ($sw.Elapsed.TotalSeconds -lt 15 -and -not ((Test-Path $cikti) -and (Get-Content $cikti -Raw -Encoding UTF8) -match 'dinleniyor')) { Start-Sleep -Milliseconds 100 }
            (Get-Content $cikti -Raw -Encoding UTF8) | Should Match 'dinleniyor'
            $uzun = 'ilk-satir ' + ([string][char]27) + '[2J ' + ('x' * 400) + ' GIZLI-SON'
            & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $fx 'motor\scripts\aktar.ps1') -Vault $fx -Metin 'codex icin' -Kime codex | Out-Null
            $sw.Restart()
            & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $fx 'motor\scripts\aktar.ps1') -Vault $fx -Metin $uzun -Kime claude | Out-Null
            $gonder = $sw.Elapsed.TotalSeconds
            while ($sw.Elapsed.TotalSeconds -lt ($gonder + 5) -and -not ((Get-Content $cikti -Raw -Encoding UTF8) -match 'AKTAR ')) { Start-Sleep -Milliseconds 100 }
            $gecikme = $sw.Elapsed.TotalSeconds - $gonder
            $out = Get-Content $cikti -Raw -Encoding UTF8
            $out | Should Match 'AKTAR \d{8}T\d{6}-\w+ \| claude'
            ($gecikme -lt 5) | Should Be $true
            $out | Should Not Match 'codex icin'
            $out.IndexOf([char]27) | Should Be -1
            $out | Should Not Match 'GIZLI-SON'
        } finally {
            $env:BEYIN_AGENT = $previousAgent
            if ($proc -and -not $proc.HasExited) { Stop-Process -Id $proc.Id -Force }
            Remove-Item -LiteralPath $fx -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    It 'dagitici: "beyin aktar dinle" aktarim GONDERMEZ, dinleyiciye gider (eski hatada "dinle" metinli kayit yaziliyordu)' {
        $dag = Get-Content (Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'kurulum\beyin.ps1') -Raw
        $dag | Should Match "eq 'dinle'"
        $dag | Should Match "Cagir 'aktar-dinle.ps1'"
    }
}
