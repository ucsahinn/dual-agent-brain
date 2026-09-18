# beyin-launcher.ps1 - Beyin hafiza motoru kanca baslatici.
#
# ORTAK BEYIN: hem Claude Code hem Codex bu launcher uzerinden AYNI motoru
# cagirir ve AYNI vault'a yazar. Fark yalnizca -Agent etiketi; gunluk log
# blogunda hangi ajanin urettigi gorunur.
#
# Codex ile Claude Code'un kanca sozlesmesi birebir ayni:
#   - hooks.json / settings.json ayni sekil: { hooks: { SessionStart: [ { hooks: [...] } ] } }
#   - stdin payload alanlari ayni: session_id, transcript_path, cwd, hook_event_name
#   - baglam enjeksiyonu ayni: stdout'a
#     {"hookSpecificOutput":{"hookEventName":"...","additionalContext":"..."}}
#
# NEDEN VAR: vault yolunu her iki ajanin ayarinda tekrar tekrar gomulu tutmak
# kirilgandi. Vault tasinirsa her klasordeki her oturum basarisiz kancalarla
# acilirdi. Yol TEK yerde cozulur (asagidaki Get-BeyinVaultYolu).
# Vault yoksa SESSIZCE exit 0 - kurulu olmayan bir motor hicbir oturumu bozmaz.
#
# BU DOSYANIN KAYNAGI: <vault>\kurulum\beyin-launcher.ps1
# Buraya (~\.beyin\) kur.ps1 tarafindan KOPYALANIR; ~\.claude\hooks\ altinda ise
# Codex icin buraya yonlendiren bir SIM durur (beyin-launcher-sim.ps1). Elle duzenleme;
# bir sonraki kurulum uzerine yazar. Kaynagi duzenle, sonra 'beyin kur'.
#
# Kullanim:
#   Claude Code (~/.claude/settings.json):
#     powershell ... -File "<bu dosya>" -Hook session-start
#   Codex (~/.codex/hooks.json):
#     powershell ... -File "<bu dosya>" -Hook session-start -Agent codex

param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('session-start', 'prompt-counter', 'session-end', 'pre-compact')]
    [string]$Hook,

    [ValidateSet('claude', 'codex')]
    [string]$Agent = 'claude'
)

$ErrorActionPreference = 'SilentlyContinue'

function Get-BeyinVaultYolu {
    # Vault yolu cozum sirasi. Ilk bulunan kazanir:
    #
    #   1. BEYIN_VAULT ortam degiskeni
    #      Hem gecici gecersiz kilma hem KILL SWITCH: var olmayan bir yola
    #      ayarlarsan iki ajandaki tum kancalar sessizce devre disi kalir.
    #
    #   2. ~\.beyin\vault.txt
    #      Kurulumun yazdigi kayit. Vault'u baska bir diske tasidiginda YALNIZ
    #      bu dosyayi guncellersin; iki ajanin ayarina dokunmak gerekmez.
    #      Bu onemli: ~/.codex/hooks.json her kanca tanimini SHA-256 ile
    #      hash'ler ve degisen kanca /hooks ile yeniden onaylanana kadar
    #      SESSIZCE atlanir. O dosyaya dokunmamak icin yol buradan okunur.
    #
    #   3. ~\Documents\Beyin
    #      Varsayilan konum (kurulum yapilmamis ama vault elle konmussa).
    if ($env:BEYIN_VAULT) { return $env:BEYIN_VAULT }

    $kayit = Join-Path $env:USERPROFILE '.beyin\vault.txt'
    if (Test-Path -LiteralPath $kayit) {
        try {
            $y = (Get-Content -LiteralPath $kayit -Raw -Encoding UTF8).Trim()
            if ($y) { return $y }
        } catch { }
    }

    return (Join-Path $env:USERPROFILE 'Documents\Beyin')
}

# SESSIZLIK KURULU OLMAYAN ICINDIR, BOZULAN ICIN DEGIL (2026-09-18).
# Eskiden her iki durum da sifir sinyalle `exit 0` idi. "Motor kurulu degil"
# icin bu DOGRU (kurulmamis bir makinede gurultu yapmamali). Ama vault.txt
# VARSA motor kuruludur; o yolun erisilemez olmasi (harici/ag disk bagli
# degil, klasor tasinmis) bir ARIZADIR ve eski haliyle her oturum hafizasiz
# aciliyor, hicbir yerde tek satir iz kalmiyordu.
#
# KILL SWITCH KORUNUYOR: BEYIN_VAULT ortam degiskeni var olmayan bir yola
# ayarlanarak motoru susturmak BELGELENMIS yontemdir - o durumda iz birakmayiz.
#
# Iz vault'a yazilamaz (vault zaten yok); ~\.beyin yanina yazilir. Bu yol
# kanca yolundadir: tek satir, tavanli, try/catch icinde, cikis her zaman 0.
function Write-LauncherIz {
    param([string]$Mesaj)
    try {
        $kok = Join-Path $env:USERPROFILE '.beyin'
        if (-not (Test-Path -LiteralPath $kok)) { return }
        $f = Join-Path $kok 'launcher-hata.log'
        # 64 KB tavan: buyuyen bir hata logu kendisi soruna donusmesin.
        if ((Test-Path -LiteralPath $f) -and ((Get-Item -LiteralPath $f).Length -gt 65536)) {
            Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue
        }
        $satir = '{0}  [{1}/{2}] {3}' -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'), $Agent, $Hook, $Mesaj
        [System.IO.File]::AppendAllText($f, $satir + [Environment]::NewLine, (New-Object System.Text.UTF8Encoding $false))
    } catch { }
}

$vault = Get-BeyinVaultYolu
if (-not (Test-Path -LiteralPath $vault)) {
    # Kayit VAR ama yol yok -> ariza. Kayit da yoksa -> kurulu degil, sessiz.
    $kayitVar = Test-Path -LiteralPath (Join-Path $env:USERPROFILE '.beyin\vault.txt')
    if ($kayitVar -and -not $env:BEYIN_VAULT) {
        Write-LauncherIz "vault yolu ERISILEMEZ: '$vault' (kayit ~\.beyin\vault.txt'te var) - bu oturum hafizasiz acildi"
    }
    exit 0
}

$target = Join-Path $vault "motor\hooks\$Hook.ps1"
if (-not (Test-Path -LiteralPath $target)) {
    # Vault var ama kanca betigi yok: yarim/bozuk kurulum. Bu HIC sessiz
    # kalmamali - vault yerinde oldugu icin kullanici motoru calisiyor sanir.
    Write-LauncherIz "kanca betigi YOK: '$target' - kurulum yarim (duzeltme: beyin kur)"
    exit 0
}

# Motor bu degiskenlerden baglami ogrenir:
#   BEYIN_AGENT - hangi ajan (Get-BeyinAgent); gunluk log blok basligina isler
#   BEYIN_VAULT - kanca alt sureclerine yol devri; yukarida zaten ayarliysa
#                 degeri korunur (kill switch bozulmasin)
$env:BEYIN_AGENT = $Agent
if (-not $env:BEYIN_VAULT) { $env:BEYIN_VAULT = $vault }

# Kancalar stdin'den payload okur; bu surecin stdin'i oldugu gibi devrediliyor.
& $target
exit 0
