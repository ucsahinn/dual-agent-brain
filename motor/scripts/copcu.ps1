# copcu.ps1 - Disk copcusu: git repolarindaki YOK SAYILAN / IZLENMEYEN ve
# adiyla "uretilmis cikti" oldugu belli klasorleri bulur, olcer, raporlar.
# -Uygula ile KALICI siler (kullanici karari: varsayilan rapor, -Uygula kalici;
# -CopKutusu geri donusum kutusunu DENER).
#
# -CopKutusu GARANTI DEGILDIR (2026-09-17, bagimsiz denetim - F10).
# Silme, Windows kabugunun SendToRecycleBin yolundan gecer
# ([Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory). Kabuk su
# durumlarda dosyayi GERI DONUSUM KUTUSUNA KOYMADAN KALICI SILER:
#   - klasor, o birimin geri donusum kutusu KOTASINDAN buyukse
#   - o birimde geri donusum kutusu kapaliysa (NukeOnDelete)
#   - hedef AG ya da CIKARILABILIR birimdeyse
# Ustelik 'OnlyErrorDialogs' normalde cikacak "kaliciya silinsin mi?" uyari
# diyalogunu BASTIRIR. copcu'nun kendi esigi -MinMB 50, yani adaylar tam da
# kotayi asma ihtimali yuksek olan sinifta. Bu yuzden -CopKutusu "kutuya atar"
# diye KOSULSUZ soz vermez: silmeden once kota/kutu durumu olculup UYARILIR,
# silmeden sonra bos alan farki ile kutuya gidip gitmedigi kontrol edilir.
#
# NEDEN: disk %6 bos kaldi (60/931 GB). Olculen cop ~67 GB: render kareleri,
# .next-* kopyalari, output/.cache. Hepsi git'in zaten yok saydigi
# klasorler - yani hicbiri commit'te degil, hicbiri kaynak degil.
#
# KAPILAR (-Uygula icin HEPSI birden saglanmali):
#   1. git status --ignored=matching cikisinda yok sayilan (!!) ya da izlenmeyen (??)
#   2. klasor adi ALLOWLIST'te (frames, output, .cache, .next-* ...); '.next' DEGIL
#   3. son degisiklik > 24 saat once (su an uretilen bir sey silinmesin)
#   4. yasak kok DISINDA (vault, ~\.claude, ~\.codex, ~\.beyin, ~\.agents)
#   5. ReparsePoint (junction/symlink) DEGIL - ne kendisi ne repo kokunden itibaren HERHANGI
#      bir atasi (junction icine inilmez: hedef repo DISINDA olabilir)
#   6. bir git reposunun ALTINDA ve O reponun: ic ice baska bir repoya (.git iceren dizin)
#      ait degil (git rev-parse --show-toplevel == dis repo) ve dis repoda izlenen dosya yok
#   7. boyut >= MinMB
# Ayrica: <repo>\.claude\worktrees\* (git'te KAYITLI, 14 gunden eski ve TEMIZ; git status
#         hatasi = temiz DEGIL) -> git worktree remove (--force yok);
#         motor\scripts\.state\*.tmp-* ve *.yedek-* (7 gunden eski) -> sil.
# git ciktisi UTF-8 okunur (Git-Calistir): Turkce adli klasorler de olculur.
#
# Kullanim:
#   beyin copcu                 rapor (Desktop + Documents)
#   beyin copcu -MinMB 10
#   beyin copcu -Kok D:\work
#   beyin copcu-uygula          KALICI siler (kapilardan gecenleri)
#   beyin copcu-uygula -CopKutusu   geri donusum kutusunu DENER (kota/kapali kutu/
#                                   ag birimi durumunda KALICI silinebilir - uyarir)

param(
    [string]$Vault = $(if ($env:BEYIN_VAULT) { $env:BEYIN_VAULT } else { Split-Path (Split-Path $PSScriptRoot -Parent) -Parent }),
    [string[]]$Kok = @(),
    [switch]$Uygula,
    [switch]$CopKutusu,
    [int]$MinMB = 50,
    [switch]$Json
)

$ErrorActionPreference = 'SilentlyContinue'
# NEDEN: $Vault ilk KONUMSAL parametre; `copcu.ps1 D:\work` gibi bir cagri D:\work'u Vault sanir,
# lib.ps1 sessizce yuklenemez (EAP SilentlyContinue) ve betik yanlis/bos sonucla exit 0 verir
# (ayni desen makbuz.ps1'de olculdu). Vault gercek vault degilse (motor\hooks\lib.ps1 yok) SESLI dus.
$vaultOk = $false
try { $vaultOk = [bool]($Vault -and (Test-Path -LiteralPath $Vault -PathType Container) -and (Test-Path -LiteralPath (Join-Path $Vault 'motor\hooks\lib.ps1') -PathType Leaf)) } catch { }
if (-not $vaultOk) { Write-Output "HATA: vault degil (motor\hooks\lib.ps1 yok): '$Vault'  - konumsal arguman -Vault'a baglanir; kok icin -Kok <dizin> kullan"; exit 2 }
. (Join-Path $Vault 'motor\hooks\lib.ps1')
$p = Get-BeyinPaths -Vault $Vault
$inv = [Globalization.CultureInfo]::InvariantCulture
$simdi = Get-Date
$sw = [Diagnostics.Stopwatch]::StartNew()

if (-not $Kok -or $Kok.Count -eq 0) { $Kok = @((Join-Path $env:USERPROFILE 'Desktop'), (Join-Path $env:USERPROFILE 'Documents')) }

# Allowlist: TAM AD eslesmesi (kucuk harf) + '.next-*' oneki. '.next' ve 'node_modules' ASLA.
$ALLOW = @('frames', 'renders', 'render', 'output', 'outputs', 'test-results', 'playwright-report',
           'coverage', '__pycache__', '.pytest_cache', 'tmp', 'temp', '.cache', 'dist-tmp', 'out-tmp')
$ALLOW_PREFIX = @('.next-')
$ATLA_INIS = @('node_modules', '.git', '.next')   # icine inilmez (cok buyuk / uretim onbellegi)

$vaultTam = try { (Resolve-Path -LiteralPath $Vault).Path.TrimEnd('\') } catch { $Vault.TrimEnd('\') }
# DIKKAT: PS degisken adlari buyuk/kucuk harf duyarsiz - $yasak adli yerel bool ile carpismasin.
$YASAK_KOKLER = @($vaultTam) + @('.claude', '.codex', '.beyin', '.agents' | ForEach-Object { Join-Path $env:USERPROFILE $_ })

function Yasak-Mi([string]$Yol) {
    foreach ($y in $YASAK_KOKLER) { if ($Yol -eq $y -or $Yol.StartsWith($y + '\', [StringComparison]::OrdinalIgnoreCase)) { return $true } }
    return $false
}
function Allow-Mi([string]$Ad) {
    $a = $Ad.ToLowerInvariant()
    if ($ALLOW -contains $a) { return $true }
    foreach ($px in $ALLOW_PREFIX) { if ($a.StartsWith($px) -and $a.Length -gt $px.Length) { return $true } }
    return $false
}
function Reparse-Mi([string]$Yol) {
    try { return (([IO.File]::GetAttributes($Yol) -band [IO.FileAttributes]::ReparsePoint) -ne 0) } catch { return $true }
}
function Reparse-AtaMi([string]$Kok, [string]$Yol) {
    # NEDEN: kapi 5 yalniz adayin KENDISINE bakiyordu. `.gitignore: data/` + `data` -> ..\outside
    # junction'inda copcu junction'in icine inip repo DISINDAKI 'output'u siliyordu (scratch
    # repoda yeniden uretildi: outside\output exists=False). Kok'ten adaya kadar HER parca
    # (aday dahil) kontrol edilir; okunamayan parca da reparse sayilir (Reparse-Mi hatada $true).
    $k = $Kok.TrimEnd('\')
    if (-not $Yol.StartsWith($k + '\', [StringComparison]::OrdinalIgnoreCase)) { return (Reparse-Mi $Yol) }
    foreach ($parca in $Yol.Substring($k.Length + 1).Split('\')) {
        if (-not $parca) { continue }
        $k = Join-Path $k $parca
        if (Reparse-Mi $k) { return $true }
    }
    return $false
}
function CopKutusu-Durum([string]$Yol) {
    # F10: bu yol icin geri donusum kutusu GERCEKTEN kullanilacak mi?
    # Donus: @{ Bilinen; Kalici; MaxMB; Sebep }
    #   Kalici=$true -> kutu kullanilmaz, silme KALICI olur
    #   MaxMB >= 0   -> kutu kotasi (MB); bundan buyuk klasor kaliciya gider
    # Her sey en iyi cabayla okunur; okunamazsa Bilinen=$false doner ve
    # cagiran "bilmiyoruz" der - sessizce "kutuya gider" DEMEZ.
    $r = @{ Bilinen = $false; Kalici = $false; MaxMB = -1; Sebep = '' }
    try {
        $kok = [IO.Path]::GetPathRoot($Yol)
        if (-not $kok) { return $r }
        if ($kok.StartsWith('\\')) { $r.Bilinen = $true; $r.Kalici = $true; $r.Sebep = 'ag yolu (UNC)'; return $r }
        $harf = $kok.TrimEnd('\')
        $vol = $null
        try { $vol = Get-CimInstance -ClassName Win32_Volume -Filter "DriveLetter='$harf'" -ErrorAction Stop } catch { }
        if (-not $vol) { return $r }
        # DriveType: 2 = cikarilabilir, 4 = ag
        if ([int]$vol.DriveType -eq 4) { $r.Bilinen = $true; $r.Kalici = $true; $r.Sebep = 'ag birimi'; return $r }
        if ([int]$vol.DriveType -eq 2) { $r.Bilinen = $true; $r.Kalici = $true; $r.Sebep = 'cikarilabilir birim'; return $r }
        $g = ([string]$vol.DeviceID) -replace '^\\\\\?\\Volume', '' -replace '\\$', ''
        if (-not $g) { return $r }
        foreach ($kk in @("HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\BitBucket\Volume\$g",
                          'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\BitBucket')) {
            $pr = $null
            try { $pr = Get-ItemProperty -LiteralPath $kk -ErrorAction Stop } catch { continue }
            if (-not $pr) { continue }
            $r.Bilinen = $true
            if ($pr.PSObject.Properties['NukeOnDelete'] -and [int]$pr.NukeOnDelete -eq 1) {
                $r.Kalici = $true; $r.Sebep = 'geri donusum kutusu kapali (NukeOnDelete)'; return $r
            }
            if ($pr.PSObject.Properties['MaxCapacity'] -and [int]$pr.MaxCapacity -ge 0) { $r.MaxMB = [int]$pr.MaxCapacity; return $r }
        }
    } catch { }
    return $r
}
function Git-Calistir([string[]]$GitArg) {
    # NEDEN: PS 5.1 `& git` ciktisini [Console]::OutputEncoding ile cozer (temiz surecte cp437,
    # tr-TR konsolda cp857); git -z ise ham UTF-8 basar. 'ölçüm\output' gibi Turkce adli yok
    # sayilan klasorler bozuk adla gelip Test-Path'te bulunamiyor, sessizce olculmuyordu (olculdu).
    # Burada git UTF-8 okunur; cikis kodu da $LASTEXITCODE tuzagi olmadan guvenilir doner:
    # git HATA verdiyse Ok=$false - bos cikti hicbir yerde 'temiz' sayilmaz.
    $r = @{ Ok = $false; Out = ''; Kod = -1 }
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = 'git'
        $psi.Arguments = ((@('-c', 'core.quotepath=false') + @($GitArg)) | ForEach-Object {
            if ($_ -match '[\s"]') { '"' + (($_ -replace '(\\*)"', '$1$1\"') -replace '(\\+)$', '$1$1') + '"' } else { $_ } }) -join ' '
        $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
        $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
        $psi.StandardOutputEncoding = New-Object System.Text.UTF8Encoding($false)
        $psi.StandardErrorEncoding = New-Object System.Text.UTF8Encoding($false)
        $pr = [System.Diagnostics.Process]::Start($psi)
        $tErr = $pr.StandardError.ReadToEndAsync()   # stderr eszamansiz: iki boru ayni anda dolunca kilitlenmesin
        $out = $pr.StandardOutput.ReadToEnd()
        $pr.WaitForExit()
        $r.Out = $out; $r.Kod = $pr.ExitCode; $r.Ok = ($pr.ExitCode -eq 0)
    } catch { }
    return $r
}
function Git-UstRepo([string]$Yol) {
    # Adayin ait oldugu reponun koku (git rev-parse --show-toplevel), '\' ile; hata -> ''.
    $u = Git-Calistir @('-C', $Yol, 'rev-parse', '--show-toplevel')
    if (-not $u.Ok) { return '' }
    return ([string]$u.Out).Trim().Replace('/', '\').TrimEnd('\')
}
function Izlenen-Var([string]$Repo, [string]$Rel) {
    # Dis repo bu yolun altinda izlenen dosya goruyor mu? git hatasi = 'var' (tutucu).
    $lf = Git-Calistir @('-C', $Repo, 'ls-files', '-z', '--', (':(literal)' + $Rel.Replace('\', '/')))
    return ((-not $lf.Ok) -or (([string]$lf.Out).Length -gt 0))
}
function Olc-Dizin([string]$Yol) {
    # Bayt + dosya sayisi + en yeni mtime. Reparse alt dizinlere INMEZ (disari sayilmasin).
    $bayt = [long]0; $n = 0; $son = [datetime]::MinValue
    $yigin = New-Object System.Collections.Generic.Stack[string]
    $yigin.Push($Yol)
    while ($yigin.Count -gt 0) {
        $d = $yigin.Pop()
        try {
            foreach ($f in [IO.Directory]::EnumerateFiles($d)) {
                try { $fi = New-Object IO.FileInfo($f); $bayt += $fi.Length; $n++; if ($fi.LastWriteTime -gt $son) { $son = $fi.LastWriteTime } } catch { }
            }
            foreach ($sd in [IO.Directory]::EnumerateDirectories($d)) {
                if (Reparse-Mi $sd) { continue }
                $yigin.Push($sd)
            }
        } catch { }
    }
    return @{ Bayt = $bayt; Dosya = $n; Son = $son }
}
function Bul-AllowAltDizin([string]$Yol) {
    # Yok sayilan bir dizinin icinde allowlist adli alt dizinleri arar (derinlik sinirsiz).
    $bulunan = New-Object System.Collections.Generic.List[string]
    # NEDEN: kokun kendisi junction ise icine inmek repo DISINA cikmaktir (olculdu: data -> ..\outside).
    if (Reparse-Mi $Yol) { return $bulunan }
    $yigin = New-Object System.Collections.Generic.Stack[string]
    $yigin.Push($Yol)
    while ($yigin.Count -gt 0) {
        $d = $yigin.Pop()
        try {
            foreach ($sd in [IO.Directory]::EnumerateDirectories($d)) {
                $ad = Split-Path -Leaf $sd
                if ($ATLA_INIS -contains $ad.ToLowerInvariant()) { continue }
                if (Reparse-Mi $sd) { continue }
                # NEDEN: '?? vendor/' altinda BASKA bir git reposu olabilir (vendor\nested\.git); onun
                # COMMIT'LI output/ klasoru dis repoya gore 'untracked' gorunuyordu (scratch repoda
                # yeniden uretildi). .git iceren dizin (dosya ya da klasor: worktree'de .git bir
                # DOSYADIR) ic ice repodur - icine INILMEZ, kendisi de aday olmaz.
                if (Test-Path -LiteralPath (Join-Path $sd '.git')) { continue }
                if (Allow-Mi $ad) { $bulunan.Add($sd); continue }   # allow dizinin icine daha inmeye gerek yok
                $yigin.Push($sd)
            }
        } catch { }
    }
    return $bulunan
}

# --- 1) Repolari bul (derinlik sinirsiz; node_modules/.git icine inilmez) --------
$repolar = New-Object System.Collections.Generic.List[string]
foreach ($k in $Kok) {
    if (-not (Test-Path -LiteralPath $k)) { continue }
    $yigin = New-Object System.Collections.Generic.Stack[string]
    $yigin.Push((Resolve-Path -LiteralPath $k).Path)
    while ($yigin.Count -gt 0) {
        $d = $yigin.Pop()
        if (Yasak-Mi $d) { continue }
        if (Test-Path -LiteralPath (Join-Path $d '.git')) {
            # GERCEK repo mu? (~\Desktop\.git bos bir klasor olarak duruyordu - olculdu; git onu
            # tanimiyor ama Test-Path evet diyor ve tum masaustu tek 'repo' sanilip atlaniyordu.)
            $gd = ''
            try { $gd = (& git -C $d rev-parse --git-dir 2>$null | Select-Object -First 1) } catch { }
            if ($gd) { $repolar.Add($d); continue }   # ic ice repo aranmaz
        }
        try {
            foreach ($sd in [IO.Directory]::EnumerateDirectories($d)) {
                $ad = (Split-Path -Leaf $sd).ToLowerInvariant()
                if ($ad -in @('node_modules', '.git', '$recycle.bin', 'system volume information')) { continue }
                if (Reparse-Mi $sd) { continue }
                $yigin.Push($sd)
            }
        } catch { }
    }
}

# --- 2) Her repo: git status --ignored=matching -> adaylar ---------------------
$adaylar = New-Object System.Collections.Generic.List[object]
$worktreeler = New-Object System.Collections.Generic.List[object]
$gorulen = @{}
foreach ($repo in $repolar) {
    $g = Git-Calistir @('-C', $repo, 'status', '--porcelain', '--ignored=matching', '-z')
    if (-not $g.Ok -or -not $g.Out) { continue }   # git hatasi ya da bos: bu repoda aday yok
    $cikti = [string]$g.Out
    $repoAd = Split-Path -Leaf $repo
    $adayYollar = New-Object System.Collections.Generic.List[object]
    foreach ($kayit in ($cikti -split "`0")) {
        if ($kayit.Length -lt 4) { continue }
        $durum = $kayit.Substring(0, 2); $rel = $kayit.Substring(3).TrimEnd('/')
        if ($durum -ne '!!' -and $durum -ne '??') { continue }
        $tam = Join-Path $repo ($rel.Replace('/', '\'))
        if (-not (Test-Path -LiteralPath $tam -PathType Container)) { continue }
        # NEDEN: junction/symlink'e (kendisi ya da atasi) hic dokunulmaz, icine de inilmez (hedef repo
        # DISINDA); .git iceren dizin ic ice repodur - aday olmaz, icine inilmez (bkz. Bul-AllowAltDizin).
        if (Reparse-AtaMi $repo $tam) { continue }
        if (Test-Path -LiteralPath (Join-Path $tam '.git')) { continue }
        $ad = Split-Path -Leaf $tam
        if (Allow-Mi $ad) { $adayYollar.Add(@{ Yol = $tam; Durum = $durum }) }
        elseif ($ATLA_INIS -notcontains $ad.ToLowerInvariant()) {
            foreach ($alt in (Bul-AllowAltDizin $tam)) { $adayYollar.Add(@{ Yol = $alt; Durum = $durum }) }
        }
    }
    foreach ($a in $adayYollar) {
        $yol = [string]$a.Yol
        if ($gorulen.ContainsKey($yol.ToLowerInvariant())) { continue }
        $gorulen[$yol.ToLowerInvariant()] = $true
        $olc = Olc-Dizin $yol
        $mb = [math]::Round($olc.Bayt / 1MB, 1)
        if ($mb -lt $MinMB) { continue }
        # NEDEN: -Kok sondaki '\' ile verilip (sekme tamamlama ekler) o kok reponun kendisiyse Resolve-Path
        # cizgiyi koruyor (olculdu: EndsWith('\')=True) ve $rel ilk karakterini kaybediyordu ('proj\output' ->
        # 'roj\output'): Izlenen-Var yanlis yolu sorup bos donuyor, 'izlenen' kapisi rapor ve -Uygula
        # asamalarinda sessizce geciyor, yol sutunu/makbuz da bozuk yaziliyordu. Reparse-AtaMi/Git-UstRepo
        # zaten TrimEnd yapiyor; burasi da ayni normalize edilmis uzunlugu kullanir.
        $rel = $yol.Substring($repo.TrimEnd('\').Length + 1)
        $reparse = Reparse-AtaMi $repo $yol
        $yasakMi = Yasak-Mi $yol
        $taze = ($olc.Son -gt $simdi.AddHours(-24))
        # NEDEN (kapi 6, ic ice repo): aday baska bir reponun (vendor\nested) icindeyse git'in 'untracked'
        # dedigi sey o reponun COMMIT'LI klasoru olabilir. Ust repo dis repo degilse ya da dis repo bu
        # yolda izlenen dosya goruyorsa aday silinemez. (Yalniz MinMB'yi gecenlere sorulur: git cagrisi.)
        $baskaRepo = -not [string]::Equals((Git-UstRepo $yol), $repo.TrimEnd('\'), [StringComparison]::OrdinalIgnoreCase)
        $izlenen = if ($baskaRepo) { $false } else { Izlenen-Var $repo $rel }
        $kapilar = New-Object System.Collections.Generic.List[string]
        if ($reparse)   { $kapilar.Add('reparse') }
        if ($yasakMi)   { $kapilar.Add('yasak-kok') }
        if ($taze)      { $kapilar.Add('24s-taze') }
        if ($baskaRepo) { $kapilar.Add('baska-repo') }
        if ($izlenen)   { $kapilar.Add('izlenen') }
        $adaylar.Add([pscustomobject]@{
            proje    = $repoAd
            yol      = $rel
            tamYol   = $yol
            repoYol  = $repo
            durum    = $(if ($a.Durum -eq '!!') { 'ignored' } else { 'untracked' })
            MB       = $mb
            dosya    = $olc.Dosya
            sonYazim = $(if ($olc.Son -gt [datetime]::MinValue) { $olc.Son.ToString('yyyy-MM-dd', $inv) } else { '-' })
            engel    = $(if ($kapilar.Count) { $kapilar -join ',' } else { '' })
            silinebilir = ($kapilar.Count -eq 0)
        })
    }

    # Worktree'ler: <repo>\.claude\worktrees\*  (14 gun + temiz)
    $wtKok = Join-Path $repo '.claude\worktrees'
    if (Test-Path -LiteralPath $wtKok) {
        # NEDEN: `git status` HATA verince (tasinmis ana repo, budanmis .git\worktrees\<ad>, bozuk gitdir
        # isaretcisi) cikti bos geliyor ve eski kod bunu 'temiz' sayip --force + Remove-Item ile siliyordu
        # (olculdu: exit=128, temiz=True). Artik: git basarisiz = TEMIZ DEGIL; git'in kayitli worktree
        # listesinde olmayan dizin silinmez; yas icin dizinin kendi mtime'i degil (alt dosya duzenlemesi
        # ust klasor mtime'ini degistirmez) icindeki en yeni dosya yazimi.
        $kayitli = @{}
        $wl = Git-Calistir @('-C', $repo, 'worktree', 'list', '--porcelain')
        if ($wl.Ok) {
            foreach ($ln in ([string]$wl.Out -split "`n")) {
                if ($ln.StartsWith('worktree ')) { $kayitli[$ln.Substring(9).Trim().Replace('/', '\').TrimEnd('\').ToLowerInvariant()] = $true }
            }
        }
        foreach ($wt in @(Get-ChildItem -LiteralPath $wtKok -Directory -ErrorAction SilentlyContinue)) {
            $olc = Olc-Dizin $wt.FullName
            $sonYazim = if ($olc.Son -gt $wt.LastWriteTime) { $olc.Son } else { $wt.LastWriteTime }
            $eski = ($sonYazim -lt $simdi.AddDays(-14))
            $kayit = $kayitli.ContainsKey($wt.FullName.TrimEnd('\').ToLowerInvariant())
            $temiz = $false
            if ($kayit -and -not (Reparse-Mi $wt.FullName)) {
                $st = Git-Calistir @('-C', $wt.FullName, 'status', '--porcelain')
                $temiz = ($st.Ok -and [string]::IsNullOrWhiteSpace($st.Out))
            }
            $worktreeler.Add([pscustomobject]@{ proje = $repoAd; worktree = $wt.Name; tamYol = $wt.FullName; repoYol = $repo; MB = [math]::Round($olc.Bayt / 1MB, 1); gun = [int]($simdi - $sonYazim).TotalDays; temiz = $temiz; kayitli = $kayit; silinebilir = ($temiz -and $eski -and $kayit) })
        }
    }
}

# --- 3) Motor durum artiklari (7 gun) ---------------------------------------------
$artiklar = @(Get-ChildItem -LiteralPath $p.ScrState -File -Recurse -ErrorAction SilentlyContinue |
              Where-Object { ($_.Name -like '*.tmp-*' -or $_.Name -like '*.yedek-*') -and $_.LastWriteTime -lt $simdi.AddDays(-7) })

$toplamMB = [math]::Round((($adaylar | Measure-Object -Property MB -Sum).Sum), 1)
$silinebilirMB = [math]::Round((($adaylar | Where-Object { $_.silinebilir } | Measure-Object -Property MB -Sum).Sum), 1)
$surucu = try { (Get-PSDrive -Name ($env:SystemDrive.TrimEnd(':')) -ErrorAction Stop) } catch { $null }
$bosGBonce = if ($surucu) { [math]::Round($surucu.Free / 1GB, 1) } else { -1 }

# --- 4) UYGULA -------------------------------------------------------------------
$silinen = New-Object System.Collections.Generic.List[object]
$hatalar = New-Object System.Collections.Generic.List[string]
$eylem = if ($CopKutusu) { 'geri donusum kutusuna tasindi' } else { 'silindi' }
$kutuNot = New-Object System.Collections.Generic.List[string]
if ($Uygula) {
    if ($CopKutusu) {
        Add-Type -AssemblyName Microsoft.VisualBasic
        # F10: SILMEDEN ONCE olc - hangi birimde ne kadar silinecek, kutu ne diyor?
        $kokMB = @{}
        foreach ($x in @(@($adaylar | Where-Object { $_.silinebilir }) + @($worktreeler | Where-Object { $_.silinebilir }))) {
            $kk = ''
            try { $kk = [IO.Path]::GetPathRoot([string]$x.tamYol) } catch { }
            if (-not $kk) { continue }
            if (-not $kokMB.ContainsKey($kk)) { $kokMB[$kk] = [double]0 }
            $kokMB[$kk] = $kokMB[$kk] + [double]$x.MB
        }
        foreach ($kk in @($kokMB.Keys)) {
            $d = CopKutusu-Durum $kk
            $mb = [math]::Round($kokMB[$kk], 1)
            if ($d.Kalici) {
                $kutuNot.Add("UYARI: $kk - geri donusum kutusu KULLANILMIYOR ($($d.Sebep)); $mb MB KALICI silinecek")
            } elseif ($d.MaxMB -ge 0 -and $mb -gt $d.MaxMB) {
                $kutuNot.Add("UYARI: $kk - silinecek $mb MB, kutu kotasi $($d.MaxMB) MB; kotayi asan KALICI silinir")
            } elseif (-not $d.Bilinen) {
                $kutuNot.Add("NOT: $kk - geri donusum kutusu kotasi okunamadi; -CopKutusu GARANTI DEGIL")
            }
        }
        foreach ($n in $kutuNot) { $n }
    }
    foreach ($a in @($adaylar | Where-Object { $_.silinebilir })) {
        # SON KAPI: silme aninda yeniden dogrula (rapor ile uygulama arasinda degisen olmasin)
        if (-not (Test-Path -LiteralPath $a.tamYol -PathType Container)) { continue }
        # NEDEN: yalniz adayin kendisi degil, repo kokunden itibaren HER atasi (junction icine inme).
        if (Reparse-AtaMi $a.repoYol $a.tamYol) { $hatalar.Add("reparse (kendisi ya da atasi), atlandi: $($a.tamYol)"); continue }
        if (Yasak-Mi $a.tamYol) { $hatalar.Add("yasak kok, atlandi: $($a.tamYol)"); continue }
        if (-not (Allow-Mi (Split-Path -Leaf $a.tamYol))) { $hatalar.Add("allowlist disi, atlandi: $($a.tamYol)"); continue }
        # NEDEN (ic ice repo): silme aninda git'e yeniden sor - aday hala DIS reponun altinda mi, izlenen dosya var mi?
        if (-not [string]::Equals((Git-UstRepo $a.tamYol), $a.repoYol.TrimEnd('\'), [StringComparison]::OrdinalIgnoreCase)) { $hatalar.Add("baska repo altinda, atlandi: $($a.tamYol)"); continue }
        if (Izlenen-Var $a.repoYol $a.yol) { $hatalar.Add("izlenen dosya iceriyor, atlandi: $($a.tamYol)"); continue }
        # NEDEN: makbuz yolu -Kok profil disindayken (D:\work) Substring ile bozuluyor ya da firlatiyordu
        # ('~/tput', ArgumentOutOfRange - olculdu) ve silinen klasor 'silinemedi' diye kaydediliyordu.
        # Yol lib'in ConvertTo-BeyinMakbuzYol'uyla ONCEDEN hesaplanir; try yalniz silmeyi sarar.
        $mkYol = ConvertTo-BeyinMakbuzYol -Paths $p -Path $a.tamYol
        $silindi = $false
        try {
            if ($CopKutusu) {
                [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory($a.tamYol, 'OnlyErrorDialogs', 'SendToRecycleBin')
            } else {
                Remove-Item -LiteralPath $a.tamYol -Recurse -Force -ErrorAction Stop
            }
            $silindi = $true
        } catch { $hatalar.Add("silinemedi: $($a.tamYol) - $($_.Exception.Message)") }
        if ($silindi) { $silinen.Add(@{ p = $mkYol; b = [long]($a.MB * 1MB); a = -1 }) }
    }
    foreach ($w in @($worktreeler | Where-Object { $_.silinebilir })) {
        # NEDEN: eski kod `worktree remove --force` basarisiz olsa da Remove-Item -Recurse -Force ile
        # siliyordu. Artik: silme aninda status yeniden (git hatasi = kirli), --force YOK (git kirli ya da
        # izlenmeyen dosya gorurse reddeder), Remove-Item yalniz git basarili olup dizin hala duruyorsa;
        # -CopKutusu'nda kalan da geri donusum kutusuna gider.
        if (-not (Test-Path -LiteralPath $w.tamYol -PathType Container)) { continue }
        $st = Git-Calistir @('-C', $w.tamYol, 'status', '--porcelain')
        if (-not $st.Ok -or -not [string]::IsNullOrWhiteSpace($st.Out)) { $hatalar.Add("worktree temiz degil ya da git hatasi, atlandi: $($w.tamYol)"); continue }
        $mkYol = ConvertTo-BeyinMakbuzYol -Paths $p -Path $w.tamYol
        $wr = Git-Calistir @('-C', $w.repoYol, 'worktree', 'remove', $w.tamYol)
        if (-not $wr.Ok) { $hatalar.Add("worktree remove basarisiz (kod $($wr.Kod)), atlandi: $($w.tamYol)"); continue }
        $silindi = $true
        if (Test-Path -LiteralPath $w.tamYol) {
            try {
                if ($CopKutusu) { [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory($w.tamYol, 'OnlyErrorDialogs', 'SendToRecycleBin') }
                else { Remove-Item -LiteralPath $w.tamYol -Recurse -Force -ErrorAction Stop }
            } catch { $silindi = $false; $hatalar.Add("worktree kaldirildi ama dizin silinemedi: $($w.tamYol) - $($_.Exception.Message)") }
        }
        if ($silindi) { $silinen.Add(@{ p = $mkYol; b = [long]($w.MB * 1MB); a = -1 }) }
    }
    # MOTOR DURUM ARTIKLARI (2026-09-17, bagimsiz denetim - F9).
    # Eski satir: `foreach ($f in $artiklar) { try { Remove-Item ... } catch { } }`
    #   (a) -CopKutusu verilse bile Remove-Item (KALICI) cagriliyordu - ustteki iki
    #       silme yolu cop kutusunu onurlandiriyor, bu onurlandirmiyordu;
    #   (b) silinenler $silinen listesine EKLENMIYOR, yani ne makbuz files[]'inde
    #       ne 'silindi N' satirinda gorunuyorlardi;
    #   (c) hata yutuluyordu.
    # Ucu de giderildi.
    $artikSilinen = 0
    foreach ($f in $artiklar) {
        if (-not (Test-Path -LiteralPath $f.FullName -PathType Leaf)) { continue }
        $mkYol = ConvertTo-BeyinMakbuzYol -Paths $p -Path $f.FullName
        $mkBayt = [long]$f.Length
        try {
            if ($CopKutusu) {
                [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($f.FullName, 'OnlyErrorDialogs', 'SendToRecycleBin')
            } else {
                Remove-Item -LiteralPath $f.FullName -Force -ErrorAction Stop
            }
            $silinen.Add(@{ p = $mkYol; b = $mkBayt; a = -1 })
            $artikSilinen++
        } catch {
            $hatalar.Add("motor artigi silinemedi: $($f.FullName) - $($_.Exception.Message)")
        }
    }
}
$bosGBsonra = if ($Uygula -and $surucu) { try { [math]::Round((Get-PSDrive -Name ($env:SystemDrive.TrimEnd(':'))).Free / 1GB, 1) } catch { -1 } } else { $bosGBonce }

# --- 5) Kayit: copcu-son.json + makbuz ---------------------------------------------
$silinenMB = [math]::Round((($silinen | ForEach-Object { $_.b } | Measure-Object -Sum).Sum / 1MB), 1)
$bosFarkGB = if ($Uygula -and $bosGBonce -ge 0 -and $bosGBsonra -ge 0) { [math]::Round($bosGBsonra - $bosGBonce, 1) } else { 0 }
# NEDEN: gercek makbuz 'silindi 7 / 53794.1 MB, bos 76.7 -> 76.7 GB' diyordu ve -CopKutusu kaydedilmedigi
# icin bos alanin neden artmadigi anlasilamiyordu. Mod (copKutusu) makbuza/ozete yazilir; cop kutusunda
# bosaltma hatirlatilir, kalici silmede bos alan silinenin yarisi kadar bile artmadiysa acik uyari.
$uyari = ''
if ($Uygula -and $silinen.Count -gt 0) {
    if ($CopKutusu) {
        $uyari = ' - DIKKAT: yer acmak icin geri donusum kutusunu bosalt'
        # F10 SONRASI OLCU: kutuya giden dosya diskte yer KAPLAMAYA DEVAM EDER.
        # Bos alan silinenin yarisi kadar ARTTIYSA kabuk dosyalari kutuya
        # koymamis, KALICI silmis demektir - bu sessiz kalmamali.
        if ($bosGBonce -ge 0 -and $bosGBsonra -ge 0 -and ($bosFarkGB * 1024) -ge ($silinenMB / 2)) {
            $uyari = ' - DIKKAT: bos alan silinen kadar ARTTI; kutuya GITMEMIS, KALICI silinmis olabilir'
        }
    }
    elseif ($bosGBonce -ge 0 -and $bosGBsonra -ge 0 -and ($bosFarkGB * 1024) -lt ($silinenMB / 2)) { $uyari = ' - DIKKAT: bos alan beklendigi kadar artmadi' }
}
$ozet = @{
    ts = $simdi.ToString('o', $inv); kok = @($Kok); repo = $repolar.Count; aday = $adaylar.Count
    toplamMB = $toplamMB; silinebilirMB = $silinebilirMB; bosGB = $bosGBsonra; bosFarkGB = $bosFarkGB
    uygulandi = [bool]$Uygula; copKutusu = [bool]$CopKutusu
    silinen = $silinen.Count; silinenMB = $silinenMB
    worktree = $worktreeler.Count; artik = $artiklar.Count
    artikSilinen = $(if ($Uygula) { $artikSilinen } else { 0 }); sureMs = $sw.ElapsedMilliseconds
}
try { Write-BeyinText -Path (Join-Path $p.ScrState 'copcu-son.json') -Text (ConvertTo-Json -InputObject $ozet -Compress -Depth 4) } catch { }
Write-BeyinMakbuz -Paths $p -Script 'copcu' -Outcome $(if ($Uygula) { $(if ($hatalar.Count) { 'COPCU_KISMI' } else { 'COPCU_UYGULANDI' }) } else { 'COPCU_RAPOR' }) `
    -Files @($silinen.ToArray()) -DurationMs $sw.ElapsedMilliseconds `
    -Note "$($repolar.Count) repo, $($adaylar.Count) aday, $toplamMB MB (silinebilir $silinebilirMB MB)$(if ($Uygula) { ", $eylem $($silinen.Count) / $silinenMB MB, bos $bosGBonce -> $bosGBsonra GB$uyari" })"
if ($Uygula) { Write-BeyinLog -Vault $Vault -Message "copcu: $($silinen.Count) klasor $eylem ($silinenMB MB), $($hatalar.Count) hata, bos alan $bosGBonce -> $bosGBsonra GB$uyari" }

if ($Json) {
    [pscustomobject]@{ ozet = $ozet; adaylar = @($adaylar | Select-Object proje, yol, durum, MB, dosya, sonYazim, engel, silinebilir); worktreeler = @($worktreeler | Select-Object proje, worktree, MB, gun, temiz, kayitli, silinebilir); artik = $artiklar.Count; hatalar = @($hatalar) } |
        ConvertTo-Json -Depth 5
    exit 0
}

# --- 6) RAPOR ---------------------------------------------------------------------
"COPCU  $($simdi.ToString('yyyy-MM-dd HH:mm', $inv))  |  $($repolar.Count) repo tarandi  |  kok: $($Kok -join ', ')  |  esik: $MinMB MB$(if ($Uygula) { '  |  UYGULANDI' } else { '  |  KURU CALISMA' })"
"Bos alan: $bosGBonce GB$(if ($Uygula) { " -> $bosGBsonra GB" })"
''
if ($adaylar.Count -eq 0) { "Aday yok (>= $MinMB MB, allowlist adli, yok sayilan/izlenmeyen klasor bulunamadi)." }
else {
    "ADAYLAR ($($adaylar.Count))  toplam $toplamMB MB  |  kapilardan gecen (silinebilir) $silinebilirMB MB"
    ($adaylar | Sort-Object MB -Descending | Select-Object proje, yol, durum, MB, dosya, sonYazim, engel, silinebilir | Format-Table -AutoSize | Out-String -Width 220).TrimEnd()
    ''
    'PROJE BAZINDA'
    foreach ($g in ($adaylar | Group-Object proje | Sort-Object { ($_.Group | Measure-Object -Property MB -Sum).Sum } -Descending)) {
        "  {0,-28} {1,10:0.0} MB  ({2} klasor)" -f $g.Name, (($g.Group | Measure-Object -Property MB -Sum).Sum), $g.Count
    }
}
''
if ($worktreeler.Count) {
    "WORKTREE'LER ($($worktreeler.Count))  [git'te kayitli + 14 gun + temiz -> kaldirilir]"
    ($worktreeler | Select-Object proje, worktree, MB, gun, temiz, kayitli, silinebilir | Format-Table -AutoSize | Out-String -Width 200).TrimEnd()
    ''
}
if ($artiklar.Count) {
    "MOTOR ARTIGI: $($artiklar.Count) dosya (*.tmp-*, *.yedek-*; 7 gunden eski)$(if ($Uygula) { " -> $artikSilinen $eylem (makbuza yazildi)" } else { " -> -Uygula ile $eylem, makbuza yazilir" })"
    ''
}
if ($Uygula) {
    "$($eylem.ToUpperInvariant()): $($silinen.Count) klasor, $silinenMB MB$uyari"
    foreach ($s in $silinen) { "  $($s.p)" }
    if ($hatalar.Count) { ''; "HATA/ATLANDI ($($hatalar.Count)):"; foreach ($h in $hatalar) { "  $h" } }
} else {
    "Kalici silmek icin:  beyin copcu-uygula"
    "Geri donusum kutusunu DENEMEK icin:  beyin copcu-uygula -CopKutusu"
    "  (GARANTI DEGIL: kota asilirsa, kutu kapaliysa (NukeOnDelete) ya da hedef ag/cikarilabilir"
    "   birimdeyse Windows kabugu KALICI siler. -CopKutusu bunu silmeden once olcup uyarir.)"
    "Kapilar: allowlist ad + ignored/untracked + 24 saatten eski + dis repo altinda (ic ice repo/izlenen degil) + reparse degil (atalari dahil) + yasak kok disinda."
}
# 'Sonuc:' satiri: zamanli-kos makbuz notu icin bu satiri secer (son satir '(N sn)' anlamsizdi).
"Sonuc: $($repolar.Count) repo, $($adaylar.Count) aday, $toplamMB MB (silinebilir $silinebilirMB MB)$(if ($Uygula) { ", $eylem $($silinen.Count) / $silinenMB MB, bos $bosGBonce -> $bosGBsonra GB" })"
"($([math]::Round($sw.ElapsedMilliseconds / 1000.0, 1)) sn)"
