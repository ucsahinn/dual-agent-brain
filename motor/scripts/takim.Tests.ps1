# takim.Tests.ps1 - beyin takim sarmalayicisinin sozlesmesi (2026-10-12, takim modu).
#
# AgentChef'e bagimli DEGIL: sahte bir team-run.mjs aldigi argumanlari JSON olarak geri
# yazar ve 'plan'da kosu kaydini team-runs/<run>.json'a duser; boylece --state/--json
# enjeksiyonu, runId cozumleme, onay kapisi (start<-baslat, merge<-birlestir), tek
# kullanimlik onay, durdur->abort cevirisi ve takim.md turetimi motor olmadan dogrulanir.

$takimScript = Join-Path $PSScriptRoot 'takim.ps1'
$vault = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$powershell = (Get-Command powershell.exe -ErrorAction Stop).Source
. (Join-Path $vault 'motor\hooks\lib.ps1')

function New-SahteTeamRun {
    param([string]$Kok)
    New-Item -ItemType Directory -Force -Path (Join-Path $Kok 'scripts') | Out-Null
    $js = @'
import fs from "node:fs";
import path from "node:path";
const args = process.argv.slice(2);
const cmd = args[0];
if (cmd === "fail") { process.stderr.write(JSON.stringify({ ok: false, error: "sahte motor hatasi" }) + "\n"); process.exit(1); }
const g = (k) => { const i = args.indexOf(k); return i >= 0 ? args[i + 1] : null; };
const state = g("--state");
const run = g("--run") || "R-SAHTE";
if (state) {
  const dir = path.join(path.dirname(state), "team-runs");
  fs.mkdirSync(dir, { recursive: true });
  const f = path.join(dir, run + ".json");
  const durum = { plan: "planned", start: "running", collect: "collected", integrate: "integrated", verify: "verified", merge: "merged", abort: "aborted" }[cmd];
  if (durum) {
    const cur = fs.existsSync(f) ? JSON.parse(fs.readFileSync(f, "utf8")) : { schemaVersion: 1, runId: run, repoName: "proj", integrationBranch: "takim/" + run, workers: [{ taskId: "TASK-1", role: "docs_author", status: "planned" }] };
    cur.status = durum; cur.updatedAt = new Date().toISOString();
    if (cmd === "start") cur.workers.forEach(w => { w.status = "running"; w.pid = 4242; });
    fs.writeFileSync(f, JSON.stringify(cur, null, 2));
  }
}
process.stdout.write(JSON.stringify({ ok: true, echo: args, pane: process.env.AGENTCHEF_TEAM_PANE || null, optin: process.env.AGENTCHEF_TEAM_MODE || null }) + "\n");
'@
    [IO.File]::WriteAllText((Join-Path $Kok 'scripts\team-run.mjs'), $js, (New-Object Text.UTF8Encoding $false))
    # Get-BeyinAgentChefKok checkout'u coordination-board.mjs ile tanir; sahte kok onu da tasir.
    [IO.File]::WriteAllText((Join-Path $Kok 'scripts\coordination-board.mjs'), 'process.stdout.write("{\"ok\":true}\n");', (New-Object Text.UTF8Encoding $false))
}

function Invoke-Takim { param([string]$TestVault, [string[]]$A) & $powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $TestVault 'motor\scripts\takim.ps1') -Vault $TestVault @A 2>&1 | Out-String }
function Echo-Json([string]$Out) { return (($Out -split "`n" | Where-Object { $_ -like '{*' } | Select-Object -First 1) | ConvertFrom-Json) }

Describe 'beyin takim sarmalayicisi (2026-10-12)' {
    BeforeEach {
        $script:kok = Join-Path $TestDrive ('ac-' + [guid]::NewGuid().ToString('N').Substring(0, 6))
        New-SahteTeamRun -Kok $script:kok
        $script:tv = Join-Path $TestDrive ('vault-' + [guid]::NewGuid().ToString('N').Substring(0, 6))
        New-Item -ItemType Directory -Force -Path (Join-Path $script:tv 'motor\hooks'), (Join-Path $script:tv 'motor\scripts\.state'), (Join-Path $script:tv '10-command-center') | Out-Null
        Copy-Item (Join-Path $vault 'motor\hooks\lib.ps1') (Join-Path $script:tv 'motor\hooks\lib.ps1')
        Copy-Item $takimScript (Join-Path $script:tv 'motor\scripts\takim.ps1')
        Copy-Item (Join-Path $PSScriptRoot 'takim-izle.ps1') (Join-Path $script:tv 'motor\scripts\takim-izle.ps1')
        Set-Content -Path (Join-Path $script:tv '.beyin-version') -Value '1.0.0'
        $env:BEYIN_AGENTCHEF_KOK = $script:kok
        $env:BEYIN_TAKIM_PANEL = 'off'   # testler Windows Terminal sekmesi ACMAZ
        $env:AGENTCHEF_TEAM_PANE = $null
    }
    AfterEach { $env:BEYIN_AGENTCHEF_KOK = $null; $env:BEYIN_TAKIM_PANEL = $null; $env:AGENTCHEF_TEAM_PANE = $null }

    It 'isci paneli: start motorun ham sekmesini kapatir (AGENTCHEF_TEAM_PANE=off), motor modunda dokunmaz; izle argv guvenli; off modunda sekme acmaz' {
        $tp = Get-BeyinPaths -Vault $script:tv
        $argv = Get-BeyinTakimPanelArgv -Paths $tp -RunId 'R-7' -TaskId 'TASK-1' -Role 'docs_author'
        ($argv -join ' ') | Should Match 'takim-izle\.ps1'
        $argv[($argv.IndexOf('-Run') + 1)] | Should Be 'R-7'
        $argv[($argv.IndexOf('-Kart') + 1)] | Should Be 'TASK-1'
        (($argv -join ' ') -match ';') | Should Be $false
        $null = Invoke-Takim $script:tv @('plan', '--run', 'R-7')
        $null = Add-BeyinOnay -Paths $tp -TaskId 'R-7' -Kanal 'sohbet' -Tur 'baslat'
        $o = Invoke-Takim $script:tv @('start', '--run', 'R-7')
        $LASTEXITCODE | Should Be 0
        (Echo-Json $o).pane | Should Be 'off'
        $s = Open-BeyinTakimPanel -Paths $tp -RunId 'R-7'
        $s.Ok | Should Be $true
        $s.Acilan | Should Be 0
        $o2 = Invoke-Takim $script:tv @('izle', 'R-7')
        $LASTEXITCODE | Should Be 0
        $o2 | Should Match 'BEYIN_TAKIM_PANEL=off'
        # motor modu: motorun kendi izleyicisi kalir, env'e dokunulmaz
        $env:BEYIN_TAKIM_PANEL = 'motor'
        $null = Invoke-Takim $script:tv @('plan', '--run', 'R-8')
        $null = Add-BeyinOnay -Paths $tp -TaskId 'R-8' -Kanal 'sohbet' -Tur 'baslat'
        $o3 = Invoke-Takim $script:tv @('start', '--run', 'R-8')
        $LASTEXITCODE | Should Be 0
        (Echo-Json $o3).pane | Should Be $null
    }

    It '--state ve --json otomatik eklenir; plan sonrasi takim.md turetilir ve kosuyu listeler' {
        $out = Invoke-Takim $script:tv @('plan', '--repo', 'C:\x', '--run', 'R-1')
        $LASTEXITCODE | Should Be 0
        $j = Echo-Json $out
        ($j.echo -contains '--state') | Should Be $true
        ($j.echo -contains '--json') | Should Be $true
        $j.echo[($j.echo.IndexOf('--state') + 1)] | Should Be (Join-Path $script:tv 'motor\scripts\.state\board.json')
        $md = Join-Path $script:tv '10-command-center\takim.md'
        (Test-Path -LiteralPath $md) | Should Be $true
        $icerik = Get-Content -LiteralPath $md -Raw -Encoding UTF8
        $icerik | Should Match 'R-1'
        $icerik | Should Match 'baslat bekliyor'
    }

    It 'ikinci konumsal runId --run bicimine cevrilir; durdur abort olur; node hatasi aynen gecer (exit 1)' {
        $null = Invoke-Takim $script:tv @('plan', '--run', 'R-2')
        $out = Invoke-Takim $script:tv @('durdur', 'R-2')
        $LASTEXITCODE | Should Be 0
        $j = Echo-Json $out
        $j.echo[0] | Should Be 'abort'
        $j.echo[($j.echo.IndexOf('--run') + 1)] | Should Be 'R-2'
        ($j.echo -contains '--reason') | Should Be $true   # motor --reason ister; durdur varsayilan neden verir (2026-10-14)
        $err = Invoke-Takim $script:tv @('fail')
        $LASTEXITCODE | Should Be 1
        $err | Should Match 'sahte motor hatasi'
    }

    It 'start onaysiz exit 5 ve node cagrilmaz; baslat onayiyla gecer; onay tek kullanimlik; merge birlestir ister' {
        $null = Invoke-Takim $script:tv @('plan', '--run', 'R-3')
        $o1 = Invoke-Takim $script:tv @('start', '--run', 'R-3')
        $k1 = $LASTEXITCODE
        $tp = Get-BeyinPaths -Vault $script:tv
        $null = Add-BeyinOnay -Paths $tp -TaskId 'R-3' -Kanal 'sohbet' -Tur 'baslat'
        $o2 = Invoke-Takim $script:tv @('start', '--run', 'R-3')
        $k2 = $LASTEXITCODE
        $o3 = Invoke-Takim $script:tv @('start', '--run=R-3')
        $k3 = $LASTEXITCODE
        $k1 | Should Be 5
        $o1 | Should Match "baslat R-3"
        ($o1 -match '"echo"') | Should Be $false
        $k2 | Should Be 0
        $o2 | Should Match '"echo"'
        $k3 | Should Be 5
        # merge: birlestir onayi ayri dosya; baslat onayi merge'u ACMAZ
        $null = Add-BeyinOnay -Paths $tp -TaskId 'R-3' -Kanal 'sohbet' -Tur 'baslat'
        $o4 = Invoke-Takim $script:tv @('merge', 'R-3')
        $k4 = $LASTEXITCODE
        $null = Add-BeyinOnay -Paths $tp -TaskId 'R-3' -Kanal 'sohbet' -Tur 'birlestir'
        $o5 = Invoke-Takim $script:tv @('merge', 'R-3')
        $k5 = $LASTEXITCODE
        $k4 | Should Be 5
        $o4 | Should Match 'birlestir R-3'
        $k5 | Should Be 0
        (Get-BeyinOnay -Paths $tp -TaskId 'R-3' -Tur 'birlestir') | Should Be $null
        # makbuz izi
        $mk = @(Read-BeyinMakbuz -Paths $tp -Gun 1 | Where-Object { $_.script -eq 'takim' })
        @($mk | Where-Object { $_.outcome -eq 'ONAY_YOK' }).Count | Should Be 3   # start x2 + merge x1
        @($mk | Where-Object { $_.outcome -eq 'ONAY_KULLANILDI' }).Count | Should Be 2
    }

    It 'terminal onay kanali etkilesimsiz kabukta reddedilir (exit 5); kosu yoksa exit 2' {
        $null = Invoke-Takim $script:tv @('plan', '--run', 'R-4')
        $o = 'x' | & $powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $script:tv 'motor\scripts\takim.ps1') -Vault $script:tv baslat R-4 2>&1 | Out-String
        $LASTEXITCODE | Should Be 5
        $o | Should Match 'etkilesimli terminalde'
        $o2 = 'x' | & $powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $script:tv 'motor\scripts\takim.ps1') -Vault $script:tv birlestir R-YOK 2>&1 | Out-String
        $LASTEXITCODE | Should Be 2
        $o2 | Should Match 'kosu yok'
    }

    It 'deneysel opt-in: sarmalayici AGENTCHEF_TEAM_MODE=experimental verir, ortamdaki farkli degere dokunmaz' {
        $onceki = $env:AGENTCHEF_TEAM_MODE
        try {
            $env:AGENTCHEF_TEAM_MODE = $null
            $o = Invoke-Takim $script:tv @('doctor')
            $o | Should Match '"optin":\s*"experimental"'
            $env:AGENTCHEF_TEAM_MODE = 'off'
            $o2 = Invoke-Takim $script:tv @('doctor')
            $o2 | Should Match '"optin":\s*"off"'
        } finally { $env:AGENTCHEF_TEAM_MODE = $onceki }
    }
    It 'durum (argumansiz) motoru cagirmadan dosyadan ozetler; motor yokken komutlar exit 2' {
        $null = Invoke-Takim $script:tv @('plan', '--run', 'R-5')
        $tp = Get-BeyinPaths -Vault $script:tv
        $null = Add-BeyinOnay -Paths $tp -TaskId 'R-5' -Kanal 'sohbet' -Tur 'baslat'
        $null = Invoke-Takim $script:tv @('start', '--run', 'R-5')
        $o = Invoke-Takim $script:tv @('durum')
        $LASTEXITCODE | Should Be 0
        $o | Should Match 'R-5 \[running\]'
        $o | Should Match 'TASK-1 docs_author \[running\] pid 4242'
        ($o -match '"echo"') | Should Be $false
        Remove-Item -LiteralPath (Join-Path $script:kok 'scripts\team-run.mjs') -Force
        $o2 = Invoke-Takim $script:tv @('status', '--run', 'R-5')
        $LASTEXITCODE | Should Be 2
        $o2 | Should Match 'AgentChef bulunamadi'
    }
}

Describe 'AgentChef kesfi (2026-10-14): Belgeler/kod klasorleri, git origin guveni, yazar yolu yok' {
    It 'source\repos altindaki agentchef bulunur; origin baska depoyu gosteren agentchef-kopya elenir; hicbiri yoksa Yol bos' {
        $ev = Join-Path $TestDrive ('ev-' + [guid]::NewGuid().ToString('N').Substring(0, 6))
        $eskiEv = $env:USERPROFILE; $eskiAyar = $env:BEYIN_AGENTCHEF_KOK
        try {
            $env:USERPROFILE = $ev; $env:BEYIN_AGENTCHEF_KOK = (Join-Path $ev 'yok-agentchef')   # makinedeki gercek ayari ez; gecersiz ayar taramayi durdurmamali
            New-Item -ItemType Directory -Force -Path (Join-Path $ev '.beyin') | Out-Null
            $yap = { param($k, $surum, $origin) New-Item -ItemType Directory -Force -Path (Join-Path $k 'scripts'), (Join-Path $k '.git') | Out-Null
                Set-Content -LiteralPath (Join-Path $k 'scripts\coordination-board.mjs') -Value '//' -Encoding ASCII
                Set-Content -LiteralPath (Join-Path $k 'package.json') -Value ('{"name":"agentchef","version":"' + $surum + '"}') -Encoding ASCII
                Set-Content -LiteralPath (Join-Path $k '.git\config') -Value ("[remote ""origin""]`n`turl = $origin") -Encoding ASCII }
            $yok = Get-BeyinAgentChefKok
            ([string]$yok.Yol).StartsWith($ev) | Should Be $false   # Belgeler/Masaustu Windows yollari sahte evden bagimsiz; gercek bir klon bulunabilir
            (Get-BeyinAgentChefYokMesaji -Kok $yok) | Should Match 'github.com/ucsahinn/agentchef'
            & $yap (Join-Path $ev 'source\repos\agentchef') '1.7.1' 'https://github.com/ucsahinn/agentchef.git'
            & $yap (Join-Path $ev 'agentchef-kopya') '9.9.9' 'https://example.invalid/baska-depo.git'
            Remove-Item -LiteralPath (Join-Path $ev '.beyin\agentchef-kok.txt') -Force -ErrorAction SilentlyContinue
            $k = Get-BeyinAgentChefKok
            $k.Yol | Should Be (Join-Path $ev 'source\repos\agentchef')
            $k.Kaynak | Should Be 'tarama'
            (Get-BeyinAgentChefKok).Kaynak | Should Be 'onbellek'
        } finally { $env:USERPROFILE = $eskiEv; $env:BEYIN_AGENTCHEF_KOK = $eskiAyar }
    }
}

Describe 'kosu paneli saglik (2026-10-14): gozetmen nabzi ve cizim bekcisi' {
    BeforeAll {
        $ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'takim-izle.ps1'), [ref]$null, [ref]$null)
        $fn = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'GozetmenDurmus' }, $true) | Select-Object -First 1
        . ([scriptblock]::Create($fn.Extent.Text))
    }
    It 'nabzi taze gozetmen durmus sayilmaz; eski nabiz + olu pid sahipsiz kosudur; canli pid sahipsiz degildir' {
        $taze = (Get-Date).ToUniversalTime().ToString('o'); $eski = (Get-Date).ToUniversalTime().AddMinutes(-5).ToString('o')
        GozetmenDurmus ([pscustomobject]@{ supervisor = [pscustomobject]@{ pid = 999999; heartbeatAt = $taze } }) | Should Be $false
        GozetmenDurmus ([pscustomobject]@{ supervisor = [pscustomobject]@{ pid = $null; heartbeatAt = $eski } }) | Should Be $true
        GozetmenDurmus ([pscustomobject]@{ supervisor = [pscustomobject]@{ pid = $PID; heartbeatAt = $eski } }) | Should Be $false
        GozetmenDurmus ([pscustomobject]@{ supervisor = [pscustomobject]@{ pid = $null; heartbeatAt = $null } }) | Should Be $true
        GozetmenDurmus ([pscustomobject]@{ supervisor = $null }) | Should Be $false
    }
    It 'cizim hatalari yutulmaz: bekci ve rozet ana dongude, try/catch ile susturulmus cizim kalmadi' {
        $src = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'takim-izle.ps1') -Raw -Encoding UTF8
        $src | Should Match 'CizimSonuc \{ RenderRun \$tick \}'
        $src | Should Match 'CizimSonuc \{ Render \$tick \}'
        $src | Should Not Match 'try \{ RenderRun \$tick \} catch \{ \}'
        $src | Should Match 'GÖZETMEN DURDU'
    }
}

Describe 'kosu paneli bildirimi (2026-10-14): yalniz sonradan olusan olaylar' {
    BeforeAll {
        $ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'takim-izle.ps1'), [ref]$null, [ref]$null)
        foreach ($ad in @('KosuOlaylari', 'OlaylariBildir')) {
            $fn = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $ad }.GetNewClosure(), $true) | Select-Object -First 1
            . ([scriptblock]::Create($fn.Extent.Text))
        }
    }
    It 'ilk cizim sessiz; sonra biten isci, kota ve onay bekleyen durum bir kez bildirilir' {
        $script:gonderilen = New-Object System.Collections.Generic.List[string]
        function Bildir([string]$baslik, [string]$metin) { $script:gonderilen.Add($metin) }
        $script:olayGoruldu = $null
        $rr = [pscustomobject]@{ runId = 'R-1'; status = 'running'; workers = @([pscustomobject]@{ taskId = 'TASK-A'; status = 'running' }, [pscustomobject]@{ taskId = 'TASK-B'; status = 'finished' }) }
        OlaylariBildir $rr $false
        $script:gonderilen.Count | Should Be 0
        $rr.workers[0].status = 'paused_limit'
        OlaylariBildir $rr $false
        $script:gonderilen.Count | Should Be 1
        $script:gonderilen[0] | Should Match 'TASK-A kota'
        OlaylariBildir $rr $false
        $script:gonderilen.Count | Should Be 1
        $rr.status = 'verified'
        OlaylariBildir $rr $false
        $script:gonderilen[1] | Should Match 'birlestir R-1'
        OlaylariBildir $rr $true
        $script:gonderilen[2] | Should Match 'gözetmen durdu'
        OlaylariBildir $rr $false
        OlaylariBildir $rr $true
        $script:gonderilen.Count | Should Be 4
        $script:gonderilen[3] | Should Match 'gözetmen durdu'
    }
    It 'BEYIN_BILDIRIM ayari dogrulanir' {
        . (Join-Path (Split-Path $PSScriptRoot -Parent) 'hooks\lib.ps1')
        (Test-BeyinAyarDeger -Ad 'BEYIN_BILDIRIM' -Deger 'kapali').Ok | Should Be $true
        (Test-BeyinAyarDeger -Ad 'BEYIN_BILDIRIM' -Deger 'belki').Ok | Should Be $false
    }
}
