# bahcivan.ps1 - Ogrenme dongusunu kapatir: hangi kavram notu kullaniliyor,
# hangisi uyuyor, hangisi olu aday? Skill ve betik kullanimi da ayni bakisla.
#
# NEDEN: 109 kavramin %72'si yalniz index.md'den baglanti aliyordu ve hicbiri
# "hic ise yaradi mi" diye olculmuyordu. Makbuz (Faz 1A) 'retrieval'
# satirlariyla artik olculebiliyor: bir kavram bir oturuma enjekte edildiyse
# makbuzda adi gecer.
#
# SINIFLAR (kavram):
#   canli     >=1 enjeksiyon (makbuz) VEYA >=1 gelen baglanti (index.md ve
#             85-daylogs HARIC: diger kavramlar + 10/30/40/60/80 bolgeleri)
#   uyuyor    0 enjeksiyon, 0 baglanti, yas <= Gun
#   olu-aday  0/0, yas > Gun VE makbuz kapsami >= Gun. Kapsam yetersizse
#             "olu" karari VERILEMEZ (olcum yokken silmek korluk olur).
#
# Varsayilan KURU: rapor yazar, dokunmaz. -Uygula: olu adaylari
# 90-archive\86-compiled\concepts\ altina tasir, index.md satirini
# compiled.lock altinda cikarir, makbuz birakir (a=-1).
#
# Kullanim:
#   beyin bahcivan                  rapor (90 gun)
#   beyin bahcivan -Bolum kavram    yalniz kavramlar
#   beyin bahcivan-uygula           olu adaylari arsive tasi
#                                   (arsiv hedefi doluysa ATLANIR ve sebebi yazilir)
#   beyin bahcivan -Json            makine okunur (doktor bunu kullanir)

param(
    [string]$Vault = $(if ($env:BEYIN_VAULT) { $env:BEYIN_VAULT } else { Split-Path (Split-Path $PSScriptRoot -Parent) -Parent }),
    # NEDEN: -Gun 0 / negatif kapsam kapisini asiyordu (Min(0,x)=0, 0 -ge 0 = True -> 75 kavram
    # tek komutla arsive; olculdu). 0 ve negatif parametre baglamada SESLI reddedilir.
    [ValidateRange(1, 3650)][int]$Gun = 90,
    [ValidateSet('kavram', 'skill', 'betik', 'hepsi')][string]$Bolum = 'hepsi',
    [switch]$Uygula,
    [switch]$Json
)

$ErrorActionPreference = 'SilentlyContinue'
# NEDEN: $Vault ilk KONUMSAL parametre; fazladan bir konumsal arguman Vault'a baglanir, lib.ps1 sessizce
# yuklenemez ve betik bos/yanlis sonucla exit 0 verir (ayni desen makbuz.ps1'de olculdu). SESLI dus.
$vaultOk = $false
try { $vaultOk = [bool]($Vault -and (Test-Path -LiteralPath $Vault -PathType Container) -and (Test-Path -LiteralPath (Join-Path $Vault 'motor\hooks\lib.ps1') -PathType Leaf)) } catch { }
if (-not $vaultOk) { Write-Output "HATA: vault degil (motor\hooks\lib.ps1 yok): '$Vault'  - konumsal arguman -Vault'a baglanir; -Gun/-Bolum gibi adli parametre kullan"; exit 2 }
# NEDEN: 30 gunden kisa pencerede 'olu' karari anlamsizdir; -Uygula icin ek taban (rapor icin sinir yok).
if ($Uygula -and $Gun -lt 30) { Write-Output "HATA: arsivleme (-Uygula) icin -Gun >= 30 gerekir (verilen: $Gun). Rapor icin -Uygula'siz calistir."; exit 2 }
. (Join-Path $Vault 'motor\hooks\lib.ps1')
$p = Get-BeyinPaths -Vault $Vault
$inv = [Globalization.CultureInfo]::InvariantCulture
$simdi = Get-Date
$sw = [Diagnostics.Stopwatch]::StartNew()

# --- Makbuz: enjeksiyon sayimi + kapsam --------------------------------------
$mk = @(Read-BeyinMakbuz -Paths $p -Gun $Gun)
$enjeksiyon = @{}
foreach ($m in $mk) {
    if ($m.script -ne 'retrieval') { continue }
    foreach ($c in @($m.concepts)) {
        if (-not $c) { continue }
        $slug = [IO.Path]::GetFileNameWithoutExtension([string]$c).ToLowerInvariant()
        if ($enjeksiyon.ContainsKey($slug)) { $enjeksiyon[$slug]++ } else { $enjeksiyon[$slug] = 1 }
    }
}
# KAPSAM = olcum kac gundur suruyor? Makbuz DOSYA adlarindan olculur (YYYY-MM-DD.jsonl; arsiv\YYYY-MM.jsonl
# icin ilk satirin ts'i), filtrelenmis kayitlardan DEGIL.
# NEDEN: Read-BeyinMakbuz ts < simdi-Gun kayitlari attigi icin en eski kalan kayit hep Gun gunden GENC
# kaliyor; Floor((simdi-ilkTs).TotalDays) en fazla Gun-1 -> kapsam 89/90'da takili kaliyor, olu karari
# HICBIR ZAMAN verilemiyor, doktor 'olu kavram' satiri kirmiziya donemiyordu (PS 5.1'de dogrulandi).
# Tarih bazli sayim (gun farki, saat yok) 90. gunde tam 90 verir. Bir "-KapsamGun" anahtari BILEREK yok:
# kapsam kapisi olcumsuz silmeye karsi tek fren; kullanici eliyle asilamamali.
$ilkTarih = $null
try {
    $mkDir = $p.Makbuz
    foreach ($f in @(Get-ChildItem -LiteralPath $mkDir -Filter '*.jsonl' -File -ErrorAction SilentlyContinue)) {
        if ($f.BaseName -cmatch '^\d{4}-\d{2}-\d{2}$') {
            $t = [datetime]::ParseExact($f.BaseName, 'yyyy-MM-dd', $inv)
            if ($null -eq $ilkTarih -or $t -lt $ilkTarih) { $ilkTarih = $t }
        }
    }
    # arsiv dosyasi tarih sirali katlanir (Compress-BeyinMakbuz): en eski dosyanin ilk satiri yeter
    foreach ($f in @(Get-ChildItem -LiteralPath (Join-Path $mkDir 'arsiv') -Filter '*.jsonl' -File -ErrorAction SilentlyContinue | Sort-Object Name | Select-Object -First 1)) {
        $sr = $null
        try {
            $sr = New-Object IO.StreamReader($f.FullName)
            while ($null -ne ($ln = $sr.ReadLine())) {
                if ([string]::IsNullOrWhiteSpace($ln)) { continue }
                $t = [datetime]::Parse([string](ConvertFrom-Json -InputObject $ln).ts, $inv).Date
                if ($null -eq $ilkTarih -or $t -lt $ilkTarih) { $ilkTarih = $t }
                break
            }
        } catch { } finally { if ($sr) { $sr.Dispose() } }
    }
} catch { }
$kapsamGun = if ($null -eq $ilkTarih) { 0 } else { [math]::Max(0, [math]::Min($Gun, [math]::Floor(($simdi.Date - $ilkTarih).TotalDays))) }
$kapsamYeterli = ($kapsamGun -ge $Gun)

# PS 5.1 TUZAGI: [ordered] sozlugune $od['k'] = v atamasi 'Argument types do not match'
# firlatabiliyor (int indeksleyici secimi). Duz hashtable kullanilir; sira onemsiz.
$sonuc = @{ ts = $simdi.ToString('o', $inv); gun = $Gun; kapsamGun = $kapsamGun; kapsamYeterli = $kapsamYeterli; makbuz = $mk.Count }

# =============================================================================
# KAVRAM
# =============================================================================
if ($Bolum -in @('kavram', 'hepsi')) {
    $conceptDir = Join-Path $p.Compiled 'concepts'
    $idxF = Join-Path $p.Compiled 'index.md'
    $idxRaw = if (Test-Path -LiteralPath $idxF) { Get-Content -LiteralPath $idxF -Raw -Encoding UTF8 } else { '' }
    $kavramlar = @(Get-ChildItem -LiteralPath $conceptDir -Filter '*.md' -File -ErrorAction SilentlyContinue)

    # Gelen baglanti haritasi: her wikilink hedefinin son parcasi -> sayi.
    # Kaynaklar: diger kavram notlari + 10/30/40/60/80. index.md ve 85-daylogs HARIC
    # (index her kavrami listeler, daylog kavramin uretildigi yerdir: ikisi de
    # "kullanim" kaniti degil).
    $gelen = @{}
    # OLCUM YOKSA OLU KARARI VERILEMEZ - BU SATIR ICIN DE (2026-09-18 denetimi).
    # Eskiden kaynak not okunamazsa `catch { continue }` sessizce geciyordu.
    # O dosyadaki her [[concepts/x]] baglantisi $gelen'e hic girmiyor, yani
    # gercekten linklenen YASAYAN bir kavram 'olu-aday' cikip -Uygula ile
    # arsivlenebiliyordu. Dosyanin kendisi 30 satirini "kapsam yetmezse olu
    # karari verme" kapisini kurmaya harciyor; bu satir o ilkeden vazgeciyordu.
    $kaynakOkunamayan = New-Object System.Collections.Generic.List[string]
    $kaynakKlasor = @($conceptDir) + @('10-command-center', '30-projects', '40-knowledge', '60-decisions', '80-memory' | ForEach-Object { Join-Path $Vault $_ })
    $rxLink = [regex]'\[\[([^\]\|#]+)'
    # MAKINE BAKIMLI BOLUM "KULLANIM" KANITI DEGILDIR (2.3, bagla.ps1).
    # bagla her kavram notuna en yakin kardeslerini "## Ilgili notlar" bolumunde
    # wikilink olarak yazar. O kenarlar burada sayilirsa HER not gelen baglanti
    # alir, hicbir not bir daha 'uyuyor'/'olu aday' gorunmez ve bu olcum - onunla
    # birlikte doktor'un 'olu kavram' satiri - SESSIZCE korlesir. index.md ve
    # 85-daylogs neden haricse bu bolum de ayni sebeple haric: makinenin kendi
    # urettigi kenar, insanin o notu kullandiginin kaniti degil.
    $rxMakineBolum = $script:BeyinIlgiliBolumRx   # TEK KAYNAK: lib.ps1 (noktali I varyanti dahil)
    $rxMakineOpt = $script:BeyinRxCIMS
    foreach ($k in $kaynakKlasor) {
        if (-not (Test-Path -LiteralPath $k)) { continue }
        foreach ($f in @(Get-ChildItem -LiteralPath $k -Filter '*.md' -File -Recurse -ErrorAction SilentlyContinue)) {
            if ($f.Name -eq 'index.md' -and $f.DirectoryName -eq $p.Compiled) { continue }
            $txt = ''
            try { $txt = [IO.File]::ReadAllText($f.FullName) }
            catch { $kaynakOkunamayan.Add($f.Name); continue }
            if ($f.DirectoryName -eq $conceptDir) { $txt = [regex]::Replace($txt, $rxMakineBolum, '', $rxMakineOpt) }
            $kendi = [IO.Path]::GetFileNameWithoutExtension($f.Name).ToLowerInvariant()
            foreach ($mm in $rxLink.Matches($txt)) {
                $hedef = $mm.Groups[1].Value.Trim().Replace('\', '/')
                $hedef = $hedef.Split('/')[-1]
                if ($hedef.EndsWith('.md')) { $hedef = $hedef.Substring(0, $hedef.Length - 3) }
                $hedef = $hedef.ToLowerInvariant()
                if (-not $hedef -or $hedef -eq $kendi) { continue }   # kendine baglanti sayilmaz
                if ($gelen.ContainsKey($hedef)) { $gelen[$hedef]++ } else { $gelen[$hedef] = 1 }
            }
        }
    }

    $rxCreated = [regex]'(?m)^created:\s*"?([0-9T:\.\-Z\+]+)"?'
    $liste = New-Object System.Collections.Generic.List[object]
    foreach ($f in $kavramlar) {
        $slug = [IO.Path]::GetFileNameWithoutExtension($f.Name).ToLowerInvariant()
        $olus = $f.CreationTime
        # $bas ONCE SIFIRLANIR: okuma duserse eski deger kalirdi ve
        # 'created:' BIR ONCEKI NOTTAN okunup yas yanlis hesaplaniyordu.
        $bas = ''
        try {
            $bas = [IO.File]::ReadAllText($f.FullName)
            $mC = $rxCreated.Match($bas)
            if ($mC.Success) { $olus = [datetime]::Parse($mC.Groups[1].Value, $inv, [Globalization.DateTimeStyles]::RoundtripKind).ToLocalTime() }
        } catch { }
        $yas = [math]::Floor(($simdi - $olus).TotalDays)
        $enj = if ($enjeksiyon.ContainsKey($slug)) { $enjeksiyon[$slug] } else { 0 }
        $lnk = if ($gelen.ContainsKey($slug)) { $gelen[$slug] } else { 0 }
        $idxVar = ($idxRaw.IndexOf("[[concepts/$slug", [StringComparison]::OrdinalIgnoreCase) -ge 0)
        $sinif = if ($enj -ge 1 -or $lnk -ge 1) { 'canli' }
                 elseif ($yas -le $Gun) { 'uyuyor' }
                 elseif ($kapsamYeterli) { 'olu-aday' }
                 else { 'uyuyor' }   # kapsam yetersiz: olu karari verilemez
        $liste.Add([pscustomobject]@{ slug = $slug; dosya = $f.Name; sinif = $sinif; enjeksiyon = $enj; baglanti = $lnk; yasGun = $yas; indekste = $idxVar; bayt = $f.Length })
    }
    $canli   = @($liste | Where-Object { $_.sinif -eq 'canli' })
    $uyuyor  = @($liste | Where-Object { $_.sinif -eq 'uyuyor' })
    $oluAday = @($liste | Where-Object { $_.sinif -eq 'olu-aday' })
    # PS 5.1 TUZAGI: hashtable literali ICINDE 'Where-Object' boru hatti 'Argument types
    # do not match' firlatiyor (olculdu). Degerler once degiskene alinir.
    $oluSlug = @($oluAday | ForEach-Object { $_.slug })
    $idxYok  = @($liste | Where-Object { $_.indekste -eq $false } | ForEach-Object { $_.slug })
    $listeArr = @($liste.ToArray())
    $sonuc['kavram'] = @{ toplam = $liste.Count; canli = $canli.Count; uyuyor = $uyuyor.Count; oluAday = $oluSlug; indeksteOlmayan = $idxYok; liste = $listeArr }

    # --- UYGULA ---------------------------------------------------------------
    $tasinan = New-Object System.Collections.Generic.List[object]
    # ATLAMA SESSIZ OLAMAZ (2026-09-17, bagimsiz denetim - F1).
    # Onceki surum arsiv hedefi doluysa `continue` diyordu: rapor "OLU ADAYLAR:
    # <slug>" yaziyor, hemen altinda "TASINDI: 0 not" cikiyor, makbuz files:[]
    # oluyor ve HICBIR YERDE sebep gecmiyordu. O not sonsuza dek olu aday kalir
    # ve her gece sessizce atlanir. Kalip arsivle.ps1'den alindi:
    # "ATLANDI (hedefte var): <dosya>". Arsiv kopyasinin UZERINE YAZILMAZ -
    # atlamayi SOYLEMEK yeterli; hangi kopyanin dogru oldugu insan karari.
    $atlanan = New-Object System.Collections.Generic.List[string]
    # ARSIVLEME KAPISI: kaynak notlardan biri okunamadiysa gelen-baglanti
    # olcumu EKSIKTIR ve 'olu' karari kanitsizdir. Rapor yine basilir, ama
    # hicbir sey tasinmaz.
    if ($Uygula -and $kaynakOkunamayan.Count -gt 0) {
        $sonuc['arsivlemeReddi'] = "$($kaynakOkunamayan.Count) kaynak not okunamadi - gelen baglanti olcumu eksik"
        Write-BeyinLog -Vault $Vault -Message "bahcivan: ARSIVLEME REDDEDILDI - $($kaynakOkunamayan.Count) kaynak not okunamadi ($(($kaynakOkunamayan | Select-Object -First 3) -join ', ')); olu karari kanitsiz olurdu"
    }
    if ($Uygula -and $oluAday.Count -gt 0 -and $kapsamYeterli -and $kaynakOkunamayan.Count -eq 0) {
        $arsivDir = Join-Path $Vault '90-archive\86-compiled\concepts'
        New-Item -ItemType Directory -Force -Path $arsivDir | Out-Null
        $lock = Join-Path $p.ScrState 'compiled.lock'
        $idxOnce = Measure-BeyinDosya -Path $idxF
        $idxYazildi = $false
        $idxHata = ''
        foreach ($k in $oluAday) {
            $kaynak = Join-Path $conceptDir $k.dosya
            $hedef  = Join-Path $arsivDir $k.dosya
            if (Test-Path -LiteralPath $hedef) { $atlanan.Add("hedefte var: $($k.dosya)"); continue }
            try {
                Move-Item -LiteralPath $kaynak -Destination $hedef -ErrorAction Stop
                $tasinan.Add(@{ p = ('86-compiled/concepts/' + $k.dosya); b = [long]$k.bayt; a = -1 })
            } catch {
                # Eskiden bu catch de BOSTU: tasinamayan not hicbir yerde gorunmuyordu.
                $atlanan.Add("tasinamadi: $($k.dosya) - $($_.Exception.Message)")
            }
        }
        if ($tasinan.Count -gt 0) {
            try {
                Invoke-BeyinWithLock -LockPath $lock -TimeoutSeconds 45 -Action {
                    $raw = Get-Content -LiteralPath $idxF -Raw -Encoding UTF8
                    # SON BOS ELEMAN ATILIR (2026-09-17, bagimsiz denetim - F2).
                    # "...\n" ile biten bir dosyada -split son elemani BOS uretir;
                    # ($kalan -join "`n") + "`n" o bos elemani bir satir sonuna
                    # cevirip sona bir tane daha ekliyordu. Olculdu: index.md son
                    # baytlari her kosuda 0a -> 0a 0a -> 0a 0a 0a; yani her gece
                    # kosusu sahte bir git diff satiri uretiyordu. Artik sondaki
                    # bos eleman dusulur ve dosya TEK sonlandirici ile biter:
                    # ikinci kosu hicbir bayt eklemez.
                    $satirlar = @($raw -split "`r?`n")
                    $sonIdx = $satirlar.Count - 1
                    if ($sonIdx -ge 0 -and [string]$satirlar[$sonIdx] -eq '') { $sonIdx-- }
                    $kalan = New-Object System.Collections.Generic.List[string]
                    for ($i = 0; $i -le $sonIdx; $i++) {
                        $ln = [string]$satirlar[$i]
                        $at = $false
                        foreach ($t in $tasinan) {
                            $s2 = [IO.Path]::GetFileNameWithoutExtension(([string]$t.p).Split('/')[-1])
                            if ($ln.IndexOf("[[concepts/$s2", [StringComparison]::OrdinalIgnoreCase) -ge 0) { $at = $true; break }
                        }
                        if (-not $at) { $kalan.Add($ln) }
                    }
                    Write-BeyinText -Path $idxF -Text (($kalan -join "`n") + "`n")
                }
                $idxYazildi = $true
            } catch {
                # ESKIDEN BOS CATCH: kilit alinamadi ya da yazim dustu, akis
                # yine de devam edip index girdisini basari sayiyordu. Sonuc:
                # notlar 90-archive'a gitmis ama index.md hala [[concepts/...]]
                # diye listeliyor - ve o index HER OTURUM ACILISINDA enjekte
                # ediliyor, yani kirik wikilink dogrudan modele gidiyor. Ne
                # stdout, ne engine.log, ne makbuz bunu soyluyordu.
                $idxYazildi = $false
                $idxHata = $_.Exception.Message
                $atlanan.Add("index.md GUNCELLENEMEDI: $idxHata")
                Write-BeyinLog -Vault $Vault -Message "bahcivan: index.md guncellenemedi ($idxHata) - $($tasinan.Count) not tasindi ama indekste HALA listeleniyor; duzeltmek icin: beyin derle"
            }
            if ($idxYazildi) {
                $tasinan.Add(@{ p = '86-compiled/index.md'; b = $idxOnce; a = (Measure-BeyinDosya -Path $idxF) })
            }
        }
        $sonuc['tasinan'] = @($tasinan | Where-Object { $_.a -eq -1 } | ForEach-Object { $_.p })
        $sonuc['atlanan'] = @($atlanan.ToArray())
        Write-BeyinLog -Vault $Vault -Message "bahcivan: $(@($sonuc.tasinan).Count) olu kavram 90-archive'a tasindi, $($atlanan.Count) atlandi (kapsam $kapsamGun/$Gun gun)"
    }
}

# =============================================================================
# SKILL  (gecis sayimi: daylog + engine.log'da adi gecmesi = CAGRI DEGIL, iz)
# =============================================================================
if ($Bolum -in @('skill', 'hepsi')) {
    $adlar = @{}
    foreach ($d in @((Join-Path $Vault 'motor\skills'), (Join-Path $env:USERPROFILE '.agents\skills'))) {
        if (-not (Test-Path -LiteralPath $d)) { continue }
        foreach ($k in @(Get-ChildItem -LiteralPath $d -Directory -ErrorAction SilentlyContinue)) { if ($k.Name -notlike '.*') { $adlar[$k.Name] = $true } }
    }
    $metinler = New-Object System.Collections.Generic.List[string]
    $sinirTarih = $simdi.AddDays(-$Gun)
    foreach ($f in @(Get-ChildItem -LiteralPath $p.Daylogs -Filter '*.md' -File -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -ge $sinirTarih })) {
        try { $metinler.Add([IO.File]::ReadAllText($f.FullName)) } catch { }
    }
    foreach ($lf in @('engine.log', 'engine.1.log')) {
        $lp = Join-Path $p.ScrState $lf
        if (Test-Path -LiteralPath $lp) { try { $metinler.Add([IO.File]::ReadAllText($lp)) } catch { } }
    }
    $butun = $metinler -join "`n"
    $skillListe = New-Object System.Collections.Generic.List[object]
    foreach ($ad in ($adlar.Keys | Sort-Object)) {
        $n = [regex]::Matches($butun, '(?<![\w-])' + [regex]::Escape($ad) + '(?![\w-])', $script:BeyinRxCI).Count
        $sinifS = if ($n -ge 1) { 'iz var' } else { 'iz yok' }
        $skillListe.Add([pscustomobject]@{ skill = $ad; gecis = $n; sinif = $sinifS })
    }
    $izVarSay = @($skillListe | Where-Object { $_.gecis -ge 1 }).Count
    $skillArr = @($skillListe.ToArray())
    $sonuc['skill'] = @{ toplam = $skillListe.Count; izVar = $izVarSay; not = 'gecis = adin daylog/engine.log icinde gecmesi; CAGRI KANITI DEGIL'; liste = $skillArr }
}

# =============================================================================
# BETIK  (makbuz bazinda)
# =============================================================================
if ($Bolum -in @('betik', 'hepsi')) {
    # UC SINIF (2026-09-17, bagimsiz denetim - F6).
    # Eski iki desen ('(_OK$|^OK$|^ENJEKSIYON$)' ve 'HATA|ISTISNA|KIMLIK')
    # BAHCIVAN_UYGULANDI, COMPILE_BUTCE, COPCU_RAPOR, TOPLA_KUYRUK gibi butun bir
    # outcome ailesini IKISINE DE sokmuyordu: o kosular tabloda ne basarili ne
    # hata sayiliyor, sutunlar kosu sayisini tutmuyordu. Simdi her kosu TAM BIR
    # sinifa duser (basarili + isYok + hata = kosu):
    #   hata   - gercekten basarisiz (HATA/ISTISNA/KIMLIK/COKTU/BOZUK/...)
    #   isYok  - kostu ama is yoktu / engellendi / ertelendi (RAPOR, KURU, BOS,
    #            BUTCE, KUYRUK, MESGUL, *_YOK, GUNCEL, ...)
    #   basarili - geri kalani (gercekten is yapilmis kosu)
    # SIRALAMA ONEMLI: 'AL_HATA_CLI_YOK' hem HATA hem *_YOK deseni tasir; once
    # hataya bakilir. -cmatch KULLANILIR (-match DEGIL): outcome'lar ASCII BUYUK
    # harftir ve tr-TR'de kultur duyarli IgnoreCase 'I' harfini bozar.
    $rxBHata  = 'HATA|ISTISNA|KIMLIK|COKTU|BASARISIZ|BOZUK|GECERSIZ|YAZILAMADI|GERI_ALINDI'
    $rxBIsYok = 'RAPOR$|KURU$|_BOS$|BUTCE$|KUYRUK|MESGUL$|_YOK$|GUNCEL$|KAYNAK_VAULT$|BASLATILDI$|ISYOK$|ENGELLENDI$|ATLANDI$'
    $betikListe = New-Object System.Collections.Generic.List[object]
    foreach ($g in @($mk | Group-Object script | Sort-Object Count -Descending)) {
        $son = ($g.Group | Sort-Object ts -Descending | Select-Object -First 1).ts
        $bHata  = @($g.Group | Where-Object { [string]$_.outcome -cmatch $rxBHata }).Count
        $bIsYok = @($g.Group | Where-Object { -not ([string]$_.outcome -cmatch $rxBHata) -and ([string]$_.outcome -cmatch $rxBIsYok) }).Count
        $bOk    = $g.Count - $bHata - $bIsYok
        $bButce = ($g.Group | Measure-Object -Property budget -Sum).Sum
        $bSon = try { ([datetime]::Parse($son, $inv)).ToString('MM-dd HH:mm', $inv) } catch { '' }
        $betikListe.Add([pscustomobject]@{ betik = $g.Name; kosu = $g.Count; basarili = $bOk; isYok = $bIsYok; hata = $bHata; butce = $bButce; son = $bSon })
    }
    $betikArr = @($betikListe.ToArray())
    $sonuc['betik'] = @{ toplam = $betikListe.Count; liste = $betikArr }
}

$sonuc['sureMs'] = $sw.ElapsedMilliseconds
# Son rapor (canli/doktor icin) - yalniz ozet, liste degil
try {
    $ozet = @{ ts = $sonuc.ts; gun = $Gun; kapsamGun = $kapsamGun; kapsamYeterli = $kapsamYeterli }
    if ($sonuc.ContainsKey('kavram')) { $ozet['kavram'] = @{ toplam = $sonuc.kavram.toplam; canli = $sonuc.kavram.canli; uyuyor = $sonuc.kavram.uyuyor; oluAday = @($sonuc.kavram.oluAday) } }
    if ($sonuc.ContainsKey('tasinan')) { $ozet['tasinan'] = @($sonuc.tasinan) }
    Write-BeyinText -Path (Join-Path $p.ScrState 'bahcivan-son.json') -Text (ConvertTo-Json -InputObject $ozet -Compress -Depth 5)
} catch { }
# OUTCOME ISIN GERCEKTEN YAPILIP YAPILMADIGINI SOYLER (2026-09-17, denetim - F6b).
# Onceki surum -Uygula verildiginde KOSULSUZ 'BAHCIVAN_UYGULANDI' yaziyordu.
# Olculdu: kapsam kapisinin ENGELLEDIGI bir kosu bile outcome:"BAHCIVAN_UYGULANDI",
# files:[] yaziyor; makbuza bakan "uygulandi" goruyor, oysa hicbir not tasinmadi.
$bhTasinanSay = $(if ($sonuc.ContainsKey('tasinan')) { @($sonuc.tasinan).Count } else { 0 })
$bhOutcome = if (-not $Uygula) { 'BAHCIVAN_RAPOR' }
             elseif ($sonuc.ContainsKey('arsivlemeReddi')) { 'BAHCIVAN_OLCUM_EKSIK' }
             elseif ($bhTasinanSay -gt 0) { 'BAHCIVAN_UYGULANDI' }
             elseif (-not $kapsamYeterli) { 'BAHCIVAN_KAPSAM_YOK' }
             else { 'BAHCIVAN_ISYOK' }
if ($Uygula -or $Bolum -eq 'hepsi') {
    Write-BeyinMakbuz -Paths $p -Script 'bahcivan' -Outcome $bhOutcome `
        -Files @($(if ($sonuc.ContainsKey('tasinan')) { $tasinan.ToArray() } else { @() })) -DurationMs $sw.ElapsedMilliseconds `
        -Note "kapsam $kapsamGun/$Gun gun$(if ($sonuc.ContainsKey('kavram')) { ", kavram canli=$($sonuc.kavram.canli) uyuyor=$($sonuc.kavram.uyuyor) olu-aday=$(@($sonuc.kavram.oluAday).Count)" })$(if ($sonuc.ContainsKey('atlanan') -and @($sonuc.atlanan).Count) { ", atlanan $(@($sonuc.atlanan).Count)" })"
}

if ($Json) { ConvertTo-Json -InputObject $sonuc -Depth 6; exit 0 }

# =============================================================================
# RAPOR
# =============================================================================
"BAHCIVAN  $($simdi.ToString('yyyy-MM-dd HH:mm', $inv))  |  pencere: $Gun gun  |  makbuz kapsami: $kapsamGun/$Gun gun$(if (-not $kapsamYeterli) { '  << OLU KARARI VERILEMEZ (olcum penceresi dolmadi)' })"
''
if ($sonuc.ContainsKey('kavram')) {
    $k = $sonuc.kavram
    "KAVRAM  toplam $($k.toplam)  |  canli $($k.canli)  |  uyuyor $($k.uyuyor)  |  olu-aday $(@($k.oluAday).Count)"
    if (@($k.indeksteOlmayan).Count) { "  indekste olmayan: $(@($k.indeksteOlmayan).Count) -> beyin derle" }
    $enCok = @($k.liste | Where-Object { $_.enjeksiyon -gt 0 } | Sort-Object enjeksiyon -Descending | Select-Object -First 8)
    if ($enCok.Count) {
        ''; '  EN COK ENJEKTE EDILEN'
        foreach ($x in $enCok) { "    {0,3}x  {1}  (baglanti {2}, {3} gun)" -f $x.enjeksiyon, $x.slug, $x.baglanti, $x.yasGun }
    }
    if (@($k.oluAday).Count) {
        ''; "  OLU ADAYLAR (0 enjeksiyon, 0 baglanti, >$Gun gun)"
        foreach ($x in @($k.liste | Where-Object { $_.sinif -eq 'olu-aday' } | Sort-Object yasGun -Descending)) { "    $($x.slug)  ($($x.yasGun) gun)" }
        if (-not $Uygula) { ''; '  Arsive tasimak icin: beyin bahcivan-uygula' }
    }
    if ($sonuc.ContainsKey('tasinan')) { ''; "  TASINDI: $(@($sonuc.tasinan).Count) not -> 90-archive/86-compiled/concepts/" }
    if ($sonuc.ContainsKey('atlanan') -and @($sonuc.atlanan).Count) {
        "  ATLANDI: $(@($sonuc.atlanan).Count) not (arsiv kopyasinin uzerine YAZILMADI)"
        foreach ($x in @($sonuc.atlanan)) { "    ATLANDI ($x)" }
    }
    $uyuyanlar = @($k.liste | Where-Object { $_.sinif -eq 'uyuyor' } | Sort-Object yasGun -Descending | Select-Object -First 6)
    if ($uyuyanlar.Count) {
        ''; "  UYUYAN (0/0, en eski 6 / $($k.uyuyor))"
        foreach ($x in $uyuyanlar) { "    $($x.slug)  ($($x.yasGun) gun)" }
    }
    ''
}
if ($sonuc.ContainsKey('skill')) {
    $s = $sonuc.skill
    "SKILL   toplam $($s.toplam)  |  iz var $($s.izVar)  |  iz yok $($s.toplam - $s.izVar)   ($($s.not))"
    $izsiz = @($s.liste | Where-Object { $_.gecis -eq 0 } | ForEach-Object { $_.skill })
    if ($izsiz.Count) { "  iz yok: $($izsiz -join ', ')" }
    ''
}
if ($sonuc.ContainsKey('betik')) {
    "BETIK   (makbuz, son $Gun gun)"
    if ($sonuc.betik.toplam) { ($sonuc.betik.liste | Format-Table -AutoSize | Out-String -Width 200).TrimEnd() } else { '  (makbuz yok)' }
    ''
}
"($($sonuc.sureMs) ms)"
