# pano.Tests.ps1 - beyin pano sarmalayicisinin sozlesmesi (2026-10-04, plan #13/#14).
#
# AgentChef'e bagimli DEGIL: sahte bir coordination-board.mjs aldigi argumanlari JSON
# olarak geri yazar; boylece --state/--json enjeksiyonu, koordinator varsayilani,
# hata gecisi ve pano.md turetimi AgentChef kurulu olmadan da dogrulanir.
# Okuma katmani (Get-BeyinPanoDurum) gercek sema v3 ornegiyle test edilir.

$panoScript = Join-Path $PSScriptRoot 'pano.ps1'
$vault = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$powershell = (Get-Command powershell.exe -ErrorAction Stop).Source
. (Join-Path $vault 'motor\hooks\lib.ps1')

function New-SahteAgentChef {
    param([string]$Kok)
    New-Item -ItemType Directory -Force -Path (Join-Path $Kok 'scripts') | Out-Null
    # .mjs = ESM: require() yok, import kullanilir (ilk surum require ile exit 1 veriyordu).
    $js = @'
import fs from "node:fs";
const args = process.argv.slice(2);
const cmd = args[0];
if (cmd === "fail") { process.stderr.write(JSON.stringify({ ok: false, error: "sahte hata" }) + "\n"); process.exit(1); }
const stateIdx = args.indexOf("--state");
const state = stateIdx >= 0 ? args[stateIdx + 1] : null;
if (state && (cmd === "init" || cmd === "create")) {
  const cur = fs.existsSync(state) ? JSON.parse(fs.readFileSync(state, "utf8")) : { schemaVersion: 3, revision: 0, tasks: [] };
  if (cmd === "create") {
    const g = (k) => { const i = args.indexOf(k); return i >= 0 ? args[i + 1] : null; };
    cur.tasks.push({ id: g("--id"), title: g("--title"), ownerCoordinator: g("--owner-coordinator"), status: "todo",
      owner: g("--owner-agent") ? { agent: g("--owner-agent"), session: g("--owner-session") } : null,
      writeScope: g("--write-repo") ? { repo: g("--write-repo"), paths: (g("--write-paths") || "").split(",").filter(Boolean) } : null,
      leaseUntil: null, brief: null, evidence: [], handoffs: [], reports: [] });
  }
  fs.writeFileSync(state, JSON.stringify(cur, null, 2));
}
process.stdout.write(JSON.stringify({ ok: true, echo: args }) + "\n");
'@
    [IO.File]::WriteAllText((Join-Path $Kok 'scripts\coordination-board.mjs'), $js, (New-Object Text.UTF8Encoding $false))
}

Describe 'beyin pano sarmalayicisi' {
    BeforeEach {
        $script:kok = Join-Path $TestDrive ('ac-' + [guid]::NewGuid().ToString('N').Substring(0, 6))
        New-SahteAgentChef -Kok $script:kok
        $script:testVault = Join-Path $TestDrive ('vault-' + [guid]::NewGuid().ToString('N').Substring(0, 6))
        # gercek motoru kullanan sahte vault: lib + pano + bos state klasoru
        New-Item -ItemType Directory -Force -Path (Join-Path $script:testVault 'motor\hooks'), (Join-Path $script:testVault 'motor\scripts\.state'), (Join-Path $script:testVault '10-command-center') | Out-Null
        Copy-Item (Join-Path $vault 'motor\hooks\lib.ps1') (Join-Path $script:testVault 'motor\hooks\lib.ps1')
        Copy-Item $panoScript (Join-Path $script:testVault 'motor\scripts\pano.ps1')
        Set-Content -Path (Join-Path $script:testVault '.beyin-version') -Value '1.0.0'
        $env:BEYIN_AGENTCHEF_KOK = $script:kok
    }
    AfterEach { $env:BEYIN_AGENTCHEF_KOK = $null }

    It '--state ve --json otomatik eklenir; create koordinatoru varsayilandan alir' {
        $out = & $powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $script:testVault 'motor\scripts\pano.ps1') -Vault $script:testVault create --id TASK-1 --title 'deneme' 2>&1 | Out-String
        $LASTEXITCODE | Should Be 0
        $j = ($out -split "`n" | Where-Object { $_ -like '{*' } | Select-Object -First 1) | ConvertFrom-Json
        # Pester 3.4'te 'Should Contain' DOSYA icerigi iddiasidir; dizi icin -contains.
        ($j.echo -contains '--state') | Should Be $true
        ($j.echo -contains '--json') | Should Be $true
        ($j.echo -contains '--owner-coordinator') | Should Be $true
        $j.echo[($j.echo.IndexOf('--owner-coordinator') + 1)] | Should Be 'leadership_coordinator'
        $j.echo[($j.echo.IndexOf('--state') + 1)] | Should Be (Join-Path $script:testVault 'motor\scripts\.state\board.json')
    }

    It '-Koordinator kisa adi tamamlar, gecersiz adi reddeder (exit 2)' {
        $out = & $powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $script:testVault 'motor\scripts\pano.ps1') -Vault $script:testVault -Koordinator qa create --id TASK-2 --title 'qa' 2>&1 | Out-String
        $j = ($out -split "`n" | Where-Object { $_ -like '{*' } | Select-Object -First 1) | ConvertFrom-Json
        $j.echo[($j.echo.IndexOf('--owner-coordinator') + 1)] | Should Be 'qa_coordinator'
        $out2 = & $powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $script:testVault 'motor\scripts\pano.ps1') -Vault $script:testVault -Koordinator yok create --id TASK-3 --title 'x' 2>&1 | Out-String
        $LASTEXITCODE | Should Be 2
        $out2 | Should Match 'gecersiz koordinator'
    }

    It 'mutasyon sonrasi pano.md turetilir ve acik karti listeler; node hatasi aynen gecer (exit 1)' {
        & $powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $script:testVault 'motor\scripts\pano.ps1') -Vault $script:testVault create --id TASK-9 --title 'turev' --owner-agent codex --write-repo Beyin --write-paths motor/x.ps1 2>&1 | Out-Null
        $md = Join-Path $script:testVault '10-command-center\pano.md'
        (Test-Path -LiteralPath $md) | Should Be $true
        (Get-Content -LiteralPath $md -Raw -Encoding UTF8) | Should Match 'TASK-9'
        (Get-Content -LiteralPath $md -Raw -Encoding UTF8) | Should Match 'Beyin: motor/x.ps1'
        $err = & $powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $script:testVault 'motor\scripts\pano.ps1') -Vault $script:testVault fail 2>&1 | Out-String
        $LASTEXITCODE | Should Be 1
        $err | Should Match 'sahte hata'
    }

    It 'Get-BeyinPanoDurum acik kartlari sayar ve bu projeye yazanlari ayirir' {
        $p = Get-BeyinPaths -Vault $script:testVault
        $state = @{ schemaVersion = 3; revision = 2; tasks = @(
            @{ id = 'TASK-A'; title = 'a'; status = 'in_progress'; owner = @{ agent = 'codex'; session = 's' }; writeScope = @{ repo = 'Beyin'; paths = @('motor/a.ps1') }; leaseUntil = '2030-01-01T00:00:00Z'; brief = 'x'; evidence = @() },
            @{ id = 'TASK-B'; title = 'b'; status = 'todo'; owner = $null; writeScope = @{ repo = 'ornek-proje'; paths = @('src/x.ts') }; leaseUntil = $null; brief = $null; evidence = @() },
            @{ id = 'TASK-C'; title = 'c'; status = 'done'; owner = $null; writeScope = $null; leaseUntil = $null; brief = $null; evidence = @() }
        ) } | ConvertTo-Json -Depth 6
        [IO.File]::WriteAllText($p.Board, $state, (New-Object Text.UTF8Encoding $false))
        $d = Get-BeyinPanoDurum -Paths $p -Proje 'beyin'
        $d.Acik | Should Be 2
        $d.Surecte | Should Be 1
        @($d.BuProje).Count | Should Be 1
        $d.BuProje[0].id | Should Be 'TASK-A'
        $d.Satir | Should Match '^Pano: 2 acik, 1 bu projede \(TASK-A codex/in_progress\)\.$'
    }
}
