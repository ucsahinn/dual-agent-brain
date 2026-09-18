# zamanli-kos.ps1 - Zamanlayicidan gelen kosularin sarmalayicisi.
#
# NEDEN: gece kosan bir gorev kimseye soramaz. Bu sarmalayici (1) kosuyu
# [zamanlayici] etiketiyle loglar, (2) model gerektiren komutlarda ONCE
# kimligi kontrol eder (claude auth status / codex login status; butce
# harcamaz) - kimlik yoksa makbuz KIMLIK_YOK birakir ve sessizce cikar,
# (3) makbuzlarin kaynagini 'zamanlayici' olarak isaretler (BEYIN_KAYNAK),
# (4) cikis kodu ve sureyi makbuza yazar.
#
# Kullanim (zamanlayici bunu cagirir):
#   beyin zamanli derle
#   beyin zamanli topla-uygula 3

param(
    # PS 5.1: [Parameter(Mandatory)] ile birlikte param varsayilaninda $PSScriptRoot BOS
    # geliyor (olculdu: 'Cannot bind argument to parameter Path because it is an empty
    # string'). Vault govdede cozulur, Komut elle dogrulanir.
    [string]$Vault = '',
    [string]$Komut = '',
    [string[]]$Arg = @()
)
if (-not $Vault) { $Vault = if ($env:BEYIN_VAULT) { $env:BEYIN_VAULT } else { Split-Path (Split-Path $PSScriptRoot -Parent) -Parent } }
if (-not $Komut) { Write-Output 'Kullanim: zamanli-kos.ps1 -Komut <komut> [-Arg ...]'; exit 1 }
# NEDEN: $Vault ilk KONUMSAL parametre; `-Arg -MinMB 10` gibi bir cagrida '10' Vault'a baglanir, lib.ps1
# sessizce yuklenemez (olculdu). Vault gercek vault degilse SESLI dus (firlatmaz; kod 2).
$vaultOk = $false
try { $vaultOk = [bool]($Vault -and (Test-Path -LiteralPath $Vault -PathType Container) -and (Test-Path -LiteralPath (Join-Path $Vault 'motor\hooks\lib.ps1') -PathType Leaf)) } catch { }
if (-not $vaultOk) { Write-Output "HATA: vault degil (motor\hooks\lib.ps1 yok): '$Vault'"; exit 2 }

$ErrorActionPreference = 'SilentlyContinue'
. (Join-Path $Vault 'motor\hooks\lib.ps1')
$p = Get-BeyinPaths -Vault $Vault
$sw = [Diagnostics.Stopwatch]::StartNew()
$env:BEYIN_KAYNAK = 'zamanlayici'
$dispatcher = Join-Path $env:USERPROFILE '.beyin\beyin.ps1'
$komutTam = ($Komut + $(if ($Arg.Count) { ' ' + ($Arg -join ' ') } else { '' })).Trim()

Write-BeyinLog -Vault $Vault -Message "[zamanlayici] basladi: $komutTam"

# Sonsuz dongu korumasi: zamanli -> zamanli
if ($Komut -eq 'zamanli') { Write-BeyinLog -Vault $Vault -Message '[zamanlayici] HATA: zamanli kendini cagiramaz'; exit 1 }

# Model gerektiren komutlar: kimlik on kontrolu (butce harcamaz)
$script:kimlikBelirsiz = ''
$modelGerekir = @('derle', 'derle-zorla', 'compile', 'topla-uygula', 'derin')
if ($modelGerekir -contains $Komut.ToLowerInvariant()) {
    # TAVAN 60 sn: varsayilan 20 sn soguk baslangicta yetmiyor. Olculdu
    # (2026-09-18): etkilesimli kosuda 'claude auth status' 543-729 ms, ama
    # 03:00'teki zamanlanmis kosuda 20 sn asildi. Burasi kanca yolu degil,
    # tavan sikintisi yok.
    $auth = Test-BeyinModelAuth -Paths $p -TimeoutSeconds 60
    if (-not $auth.Ok -and $auth.Kesin) {
        # Oturum GERCEKTEN yok: modeli cagirmak bosuna butce yakar.
        Write-BeyinLog -Vault $Vault -Message "[zamanlayici] $komutTam ATLANDI: kimlik yok ($($auth.Detay)) - gece kosusu butce yakmadi"
        Write-BeyinMakbuz -Paths $p -Script 'zamanli' -Outcome 'KIMLIK_YOK' -Reason $Komut -DurationMs $sw.ElapsedMilliseconds -Note "${komutTam}: $($auth.Detay)"
        # NEDEN: eskiden exit 0 -> Gorev Zamanlayici 0x0, doktor YESIL, kimse fark etmiyordu.
        exit 3
    }
    if (-not $auth.Ok) {
        # KONTROL SONUCLANMADI (zaman asimi / hata / ayristirilamayan cikti).
        #
        # NEDEN YINE DE DENIYORUZ (2026-09-18, ilk gercek gece kosusunda
        # olculdu): kimlik on kontrolu bir OPTIMIZASYONDUR - kimlik yokken
        # bosuna model cagirmamak icin var. Kontrolun KENDISI sonuclanmadiginda
        # isi ATLAMAK, gecenin tek islevini sessizce iptal etmek demektir.
        # Gerceklesen buydu: 'derle' ve 'topla-uygula' 0x3 KIMLIK_YOK ile dustu,
        # oysa oturum ACIKTI ve sadece kontrol soguk baslangicta gecikmisti.
        # Isin kendi hata yolu kimlik/kota durumunu zaten ele aliyor
        # (KOTA/LIMIT ve [KIMLIK] desenlerinde butce GERI VERILIYOR), yani
        # denemenin maliyeti yok; atlamanin maliyeti gecenin tamami.
        Write-BeyinLog -Vault $Vault -Message "[zamanlayici] ${komutTam}: kimlik kontrolu sonuclanmadi ($($auth.Detay)) - is YINE DE deneniyor"
        $script:kimlikBelirsiz = [string]$auth.Detay
    }
}

$cikti = ''
$kod = 0
try {
    $cikti = (& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $dispatcher $Komut @Arg 2>&1 | Out-String)
    $kod = $LASTEXITCODE
} catch { $cikti = $_.Exception.Message; $kod = 1 }
if ($null -eq $kod) { $kod = 1 }
$kod = [int]$kod
# NEDEN: sarmalayici son bos-olmayan satiri aliyordu; gecmis-toparla 'Sonuc: ...' satirindan SONRA
# 'Kontrol: git -C "<mutlak yol>" ...' ipucunu basiyor -> makbuz notu sonuc yerine mutlak kullanici yolu
# tasiyordu (makbuz 2026-09-16 03:26). Once bir SONUC satiri aranir ('Sonuc:' ya da GOM_OK / COMPILE_OK
# gibi buyuk harfli sonuc kodu; -cmatch: tr-TR buyuk/kucuk harf tuzagina girmesin), yoksa son satir.
$satirlar = @($cikti -split "`r?`n" | Where-Object { $_.Trim() })
$sonuclar = @($satirlar | Where-Object { $_ -cmatch '^\s*(Sonuc:|[A-Z][A-Z0-9]*_[A-Z0-9_]+(\s|$))' })
$son = if ($sonuclar.Count) { [string]$sonuclar[-1] } elseif ($satirlar.Count) { [string]$satirlar[-1] } else { '' }
$son = $son.Trim()
if ($son.Length -gt 200) { $son = $son.Substring(0, 200) }
$sn = [math]::Round($sw.ElapsedMilliseconds / 1000.0, 1)
Write-BeyinLog -Vault $Vault -Message "[zamanlayici] bitti: $komutTam (kod=$kod, $sn sn) $son"
Write-BeyinMakbuz -Paths $p -Script 'zamanli' -Outcome $(if ($kod -eq 0) { 'ZAMANLI_OK' } else { 'ZAMANLI_HATA' }) -Reason $Komut -DurationMs $sw.ElapsedMilliseconds -Note "$komutTam kod=${kod}: $son"
# NEDEN: her durumda exit 0 -> Gorev Zamanlayici hep 0x0 gosteriyor, doktor'un LastTaskResult kontrolu
# yapisal olarak hic tetiklenmiyordu; betik duzeyi hatalar (ZAMANLI_HATA) yalniz makbuzda kaliyordu.
# Cocugun kodu aynen doner (firlatmaz). RestartCount yok, MultipleInstances=IgnoreNew -> tekrar firtinasi olmaz.
exit $kod
