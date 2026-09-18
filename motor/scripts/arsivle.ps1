# arsivle.ps1 - Eski gunluk loglari arsive tasir.
#
# Neden gerekli: gunluk loglarin frontmatter'i `retention: "review-90d"` diyor.
# Bunu isleten bir mekanizma olmadan o alan bos bir vaat. Bu betik vaadi
# yerine getirir.
#
# Guvenlik kurali: bir gunluk log yalnizca DERLENMIS (final) ise tasinir.
# Derlenmemis log tasinirsa icindeki bilgi hic kavram notuna donusmez.
#
# Varsayilan olarak KURU CALISMA (dry-run): ne yapacagini yazar, dokunmaz.
# Gercekten tasimak icin -Uygula ver.

param(
    # TASINABILIRLIK (2026-09-10): vault yolu artik GOMULU DEGIL.
    # Oncelik: -Vault parametresi > BEYIN_VAULT ortam degiskeni > betigin kendi
    # konumundan turetme (<vault>\motor\scripts\<bu betik>.ps1 oldugu icin
    # iki seviye yukarisi vault'tur). Boylece motor baska bir makinede, baska
    # bir kullanici adiyla ve baska bir vault konumunda TEK SATIR DEGISMEDEN
    # calisir. Gomulu yol ayni zamanda depoya kisisel veri sizdiriyordu.
    [string]$Vault = $(if ($env:BEYIN_VAULT) { $env:BEYIN_VAULT } else { Split-Path (Split-Path $PSScriptRoot -Parent) -Parent }),
    [int]$GunSayisi = 90,
    [switch]$Uygula
)

$ErrorActionPreference = 'SilentlyContinue'
# VAULT KAPISI (2026-09-17 bagimsiz denetimi - A1). $Vault bu betikte ILK
# bildirilen parametredir, yani 0. KONUM ona aittir: 'beyin <komut> ZZZ' gibi
# ciplak birakilan bir konumsal deger buraya baglaniyordu. lib.ps1 o yoldan
# yuklenemiyor, $ErrorActionPreference = 'SilentlyContinue' hatayi yutuyor ve
# betik HICBIR SEY YAPMADAN 'basariyla' cikiyordu (olculdu). Ayni kapi
# niyet/al/ayar/guncelle dahil 14 komutta zaten vardi; burada eksikti.
$vaultOk = $false
try { $vaultOk = [bool]($Vault -and (Test-Path -LiteralPath $Vault -PathType Container) -and (Test-Path -LiteralPath (Join-Path $Vault 'motor\hooks\lib.ps1') -PathType Leaf)) } catch { }
if (-not $vaultOk) { Write-Output "HATA: vault degil (motor\hooks\lib.ps1 yok): '$Vault'  - konumsal arguman -Vault'a baglanir; gun sayisi icin -GunSayisi <n> kullan"; exit 2 }
. (Join-Path $Vault 'motor\hooks\lib.ps1')
$p = Get-BeyinPaths -Vault $Vault

$hedef = Join-Path $Vault '90-archive\85-daylogs'
$seen  = Get-BeyinSeenMap -Paths $p
$seenDetay = Get-BeyinSeenDetail -Paths $p   # final boyutu: sonradan buyumus gun derlenmeyi bekliyor
$sinir = (Get-Date).AddDays(-$GunSayisi).ToString('yyyy-MM-dd')

$all = @(Get-ChildItem -LiteralPath $p.Daylogs -Filter '*.md' -File -ErrorAction SilentlyContinue |
         Where-Object { $_.Name -cmatch '^\d{4}-\d{2}-\d{2}\.md$' } |
         Sort-Object Name)

$tasinacak = New-Object System.Collections.Generic.List[object]
$atlanan   = New-Object System.Collections.Generic.List[string]

foreach ($f in $all) {
    if ($f.BaseName -ge $sinir) { continue }                       # yeterince eski degil
    $durum = if ($seen.ContainsKey($f.Name)) { $seen[$f.Name] } else { 'derlenmedi' }
    if ($durum -ne 'final') {
        $atlanan.Add("$($f.BaseName) ($durum)")
        continue
    }
    # FINAL AMA BUYUMUS (2026-09-16): final damgasindan sonra blok eklenmis; once
    # derlenmeli (Get-BeyinPendingDaylogs yeniden secer), arsive sonra.
    if ($seenDetay.ContainsKey($f.Name) -and $seenDetay[$f.Name].Bayt -gt 0 -and $f.Length -gt $seenDetay[$f.Name].Bayt) {
        $atlanan.Add("$($f.BaseName) (final sonrasi buyudu, derleme bekliyor)")
        continue
    }
    $tasinacak.Add($f)
}

"Sinir tarihi      : $sinir ($GunSayisi gun)"
"Toplam gunluk log : $($all.Count)"
"Tasinacak         : $($tasinacak.Count)"
"Atlanan (derlenmemis): $($atlanan.Count)$(if ($atlanan.Count) { ' -> ' + ($atlanan -join ', ') })"
''

if ($tasinacak.Count -eq 0) {
    'Tasinacak dosya yok.'
    exit 0
}

if (-not $Uygula) {
    'KURU CALISMA - hicbir dosya tasinmadi. Gercekten tasimak icin -Uygula ekle.'
    foreach ($f in $tasinacak) { "  $($f.Name) -> 90-archive\85-daylogs\" }
    exit 0
}

New-Item -ItemType Directory -Force -Path $hedef | Out-Null
$ok = 0
$mkFiles = New-Object System.Collections.Generic.List[object]
foreach ($f in $tasinacak) {
    $dest = Join-Path $hedef $f.Name
    if (Test-Path -LiteralPath $dest) {
        "  ATLANDI (hedefte var): $($f.Name)"
        continue
    }
    try {
        $mkOnce = $f.Length
        Move-Item -LiteralPath $f.FullName -Destination $dest -ErrorAction Stop
        "  tasindi: $($f.Name)"
        $ok++
        $mkFiles.Add(@{ p = ('85-daylogs/' + $f.Name); b = $mkOnce; a = -1 })
    } catch {
        "  HATA: $($f.Name) - $($_.Exception.Message)"
    }
}
Write-BeyinLog -Vault $Vault -Message "arsivle: $ok gunluk log 90-archive'a tasindi"
# Eski makbuz dosyalarini da katla (90 gun): makbuz dizini sonsuza dek buyumesin.
$mkKat = Compress-BeyinMakbuz -Paths $p -OlderThanDays $GunSayisi
Write-BeyinMakbuz -Paths $p -Script 'arsivle' -Outcome $(if ($ok -eq $tasinacak.Count) { 'ARSIV_OK' } else { 'ARSIV_KISMI' }) `
    -Files @($mkFiles.ToArray()) -Note "$ok/$($tasinacak.Count) gunluk log tasindi, $mkKat makbuz dosyasi katlandi"
''
"$ok dosya tasindi."
