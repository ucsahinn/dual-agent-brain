# maliyet.ps1 - Iki ajanin jeton kullanimi ve API esdegeri maliyet (BB1, 2026-10-06).
#
# NEDEN (AgentSpace token cost dersi): hangi proje/oturum ne kadar is yakiyor,
# oturum basina sabit yuk ne, hangi oturumlar 200K baglami asip tazelenmeliydi -
# bunlar olculmeden "pahali mi" sorusu tahminle cevaplaniyordu.
#
# KAYNAK: Claude Code transkriptleri (assistant message.usage, message.id ile
# tekil) ve Codex rollout'lari (token_count kumulatif sayaci; son deger eksi
# onceki olcum). Ikisi de RESMI OLMAYAN bicim: taninmayan satir sayilir ve
# raporda "olcemedim" diye gorunur, tahmin uretilmez. Dolar = API ESDEGERI
# (motor\scripts\fiyat.json); abonelikte gercek fatura bu degildir.
#
# ARTIMLI: dosya basina bayt ofseti .state\maliyet\durum.json'da. Ilk kosu son
# 35 gunu tarar (Claude ~2 GB, bir kerelik); sonrakiler yalniz yeni satirlari.
# Birikim gunluk: .state\maliyet\gun\YYYY-MM-DD.json. Hicbir nota yazmaz.
#
# Kullanim:
#   beyin maliyet            son 7 gun raporu (once artimli tarama)
#   beyin maliyet 30         son 30 gun
#   beyin maliyet -Json      makine okunur ozet
#   beyin maliyet -YalnizTara  rapor yok (gece gorevi)

param(
    [string]$Vault = $(if ($env:BEYIN_VAULT) { $env:BEYIN_VAULT } else { Split-Path (Split-Path $PSScriptRoot -Parent) -Parent }),
    [int]$Gun = 7,
    [switch]$Json,
    [switch]$YalnizTara
)

$ErrorActionPreference = 'Stop'
$vaultOk = $false
try { $vaultOk = [bool]($Vault -and (Test-Path -LiteralPath (Join-Path $Vault 'motor\hooks\lib.ps1'))) } catch { }
if (-not $vaultOk) { Write-Output "HATA: vault degil (motor\hooks\lib.ps1 yok): '$Vault'"; exit 2 }
. (Join-Path $Vault 'motor\hooks\lib.ps1')
$p = Get-BeyinPaths -Vault $Vault
$sw = [Diagnostics.Stopwatch]::StartNew()
if ($Gun -lt 1) { $Gun = 1 }; if ($Gun -gt 90) { $Gun = 90 }
$inv = [Globalization.CultureInfo]::InvariantCulture
$kok = Join-Path $p.ScrState 'maliyet'
$gunDir = Join-Path $kok 'gun'
New-Item -ItemType Directory -Force -Path $gunDir | Out-Null
$BUYUK_BAGLAM = 200000

# --- tek kopya -------------------------------------------------------------
$mtx = New-Object System.Threading.Mutex($false, ('Global\BeyinMaliyet-' + (Get-BeyinSessionKey -SessionId $Vault)))
$alindi = $false
try { $alindi = $mtx.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { $alindi = $true }
if (-not $alindi) { Write-Output 'maliyet: baska bir tarama suruyor, cikiliyor (kod 3).'; exit 3 }

function Oku-Json([string]$f) {
    if (-not (Test-Path -LiteralPath $f)) { return $null }
    try { return (Get-Content -LiteralPath $f -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { return $null }
}
function Hash-Yap($o) {
    # PSCustomObject -> ic ice hashtable (PS 5.1'de -AsHashtable yok)
    $h = @{}
    if ($null -eq $o) { return $h }
    foreach ($pr in $o.PSObject.Properties) {
        $v = $pr.Value
        if ($v -is [System.Management.Automation.PSCustomObject]) { $h[$pr.Name] = Hash-Yap $v } else { $h[$pr.Name] = $v }
    }
    return $h
}
function Gun-Anahtari([string]$Ts, [datetime]$Yedek) {
    if ($Ts) { try { return ([datetimeoffset]::Parse($Ts, $inv)).ToLocalTime().ToString('yyyy-MM-dd') } catch { } }
    return $Yedek.ToString('yyyy-MM-dd')
}

$durumYol = Join-Path $kok 'durum.json'
$durum = Hash-Yap (Oku-Json $durumYol)
if (-not $durum.dosyalar) { $durum = @{ v = 1; dosyalar = @{} } }
$tablo = Get-BeyinFiyatTablosu -Paths $p
$gunler = @{}   # 'yyyy-MM-dd' -> hashtable anahtar -> toplam
function Gun-Al([string]$g) {
    if (-not $gunler.ContainsKey($g)) {
        $h = Hash-Yap (Oku-Json (Join-Path $gunDir "$g.json"))
        if (-not $h.k) { $h = @{ v = 1; k = @{} } }
        $gunler[$g] = $h
    }
    return $gunler[$g]
}
function Ekle([string]$g, [string]$anahtar, [hashtable]$d) {
    $gn = Gun-Al $g
    if (-not $gn.k.ContainsKey($anahtar)) { $gn.k[$anahtar] = @{ in = 0.0; out = 0.0; cw5 = 0.0; cw1h = 0.0; cr = 0.0; n = 0; usd = 0.0; fiyatsiz = 0; maxctx = 0.0; buyukN = 0; buyukUsd = 0.0; ilkctx = 0.0 } }
    $t = $gn.k[$anahtar]
    foreach ($a in @('in', 'out', 'cw5', 'cw1h', 'cr', 'usd', 'buyukUsd')) { $t[$a] = [double]$t[$a] + [double]$d[$a] }
    foreach ($a in @('n', 'fiyatsiz', 'buyukN')) { $t[$a] = [int]$t[$a] + [int]$d[$a] }
    if ([double]$d.maxctx -gt [double]$t.maxctx) { $t.maxctx = [double]$d.maxctx }
    if ([double]$d.ilkctx -gt 0 -and [double]$t.ilkctx -le 0) { $t.ilkctx = [double]$d.ilkctx }
}

# --- 1) tarama -------------------------------------------------------------
$sinir = (Get-Date).AddDays(-35)
$taranan = 0; $yeniKayit = 0; $taninmayan = 0; $hatali = 0
foreach ($kaynak in @(Get-BeyinTranscriptRoots)) {
    if (-not (Test-Path -LiteralPath $kaynak.Path)) { continue }
    $dosyalar = @(Get-ChildItem -LiteralPath $kaynak.Path -Filter $kaynak.Filter -File -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -ge $sinir })
    foreach ($f in $dosyalar) {
        $ad = $f.FullName
        $eski = $durum.dosyalar[$ad]
        if ($eski -and [long]$eski.size -eq $f.Length) { continue }
        $off = $(if ($eski) { [long]$eski.off } else { 0 })
        $r = Measure-BeyinTranscriptUsage -Path $ad -Agent $kaynak.Agent -Offset $off -SonId $(if ($eski) { [string]$eski.sonId } else { '' })
        $taranan++
        if (-not $r.Ok) { $hatali++; continue }
        $taninmayan += [int]$r.Taninmayan
        $cwd = $(if ($r.Cwd) { $r.Cwd } elseif ($eski) { [string]$eski.cwd } else { '' })
        $proje = $(if ($cwd) { Get-BeyinProjectLeaf -Path $cwd -Paths $p } else { '' }); if (-not $proje) { $proje = '-' }
        # Alt ajan transkripti ust oturuma yazilir (subagents\<id>.jsonl -> <oturum>).
        $sid = $(if ($r.SessionId) { $r.SessionId } elseif ($eski) { [string]$eski.sid } else { [IO.Path]::GetFileNameWithoutExtension($ad) })
        $yeni = @{ off = $r.Offset; size = $f.Length; sonId = $r.SonId; cwd = $cwd; sid = $sid; model = $(if ($r.Model) { $r.Model } elseif ($eski) { [string]$eski.model } else { '' }) }
        if ($kaynak.Agent -eq 'claude') {
            $ilk = ($off -eq 0)
            foreach ($k in $r.Kayitlar) {
                $usd = Get-BeyinUsdTahmini -Tablo $tablo -Model $k.Model -In $k.In -Out $k.Out -Cw5 $k.Cw5 -Cw1h $k.Cw1h -Cr $k.Cr -Fast $k.Fast
                $buyuk = ([double]$k.Ctx -gt $BUYUK_BAGLAM)
                Ekle (Gun-Anahtari $k.Ts $f.LastWriteTime) "claude|$proje|$sid|$($k.Model)" @{
                    in = $k.In; out = $k.Out; cw5 = $k.Cw5; cw1h = $k.Cw1h; cr = $k.Cr; n = 1
                    usd = $(if ($null -ne $usd) { $usd } else { 0 }); fiyatsiz = $(if ($null -eq $usd) { 1 } else { 0 })
                    maxctx = $k.Ctx; buyukN = $(if ($buyuk) { 1 } else { 0 }); buyukUsd = $(if ($buyuk -and $null -ne $usd) { $usd } else { 0 })
                    ilkctx = $(if ($ilk) { $k.Ctx } else { 0 }) }
                $ilk = $false; $yeniKayit++
            }
        } else {
            $yeni.top = $(if ($eski -and $eski.top) { $eski.top } else { $null })
            if ($r.CodexToplam) {
                $onc = $yeni.top
                $d = @{ In = [double]$r.CodexToplam.In; Cr = [double]$r.CodexToplam.Cr; Out = [double]$r.CodexToplam.Out }
                if ($onc -and [double]$d.In -ge [double]$onc.In -and [double]$d.Out -ge [double]$onc.Out) {
                    $d = @{ In = $d.In - [double]$onc.In; Cr = [math]::Max(0, $d.Cr - [double]$onc.Cr); Out = $d.Out - [double]$onc.Out }
                }
                $model = $(if ($yeni.model) { $yeni.model } else { 'codex' })
                if (($d.In + $d.Out + $d.Cr) -gt 0) {
                    $usd = Get-BeyinUsdTahmini -Tablo $tablo -Model $model -In $d.In -Out $d.Out -Cw5 0 -Cw1h 0 -Cr $d.Cr
                    Ekle (Gun-Anahtari $r.CodexTs $f.LastWriteTime) "codex|$proje|$sid|$model" @{
                        in = $d.In; out = $d.Out; cw5 = 0; cw1h = 0; cr = $d.Cr; n = 1
                        usd = $(if ($null -ne $usd) { $usd } else { 0 }); fiyatsiz = $(if ($null -eq $usd) { 1 } else { 0 })
                        maxctx = 0; buyukN = 0; buyukUsd = 0; ilkctx = 0 }
                    $yeniKayit++
                }
                $yeni.top = @{ In = [double]$r.CodexToplam.In; Cr = [double]$r.CodexToplam.Cr; Out = [double]$r.CodexToplam.Out }
            }
        }
        $durum.dosyalar[$ad] = $yeni
    }
}
# Durumu ONCE gunluk birikime, SONRA ofsete yaz: kesilirse ayni satir iki kez
# sayilabilir ama hic kaybolmaz (ofset ileri gitmeden birikim yazilmis olur).
foreach ($g in $gunler.Keys) { Write-BeyinText -Path (Join-Path $gunDir "$g.json") -Text (ConvertTo-Json -InputObject $gunler[$g] -Depth 6 -Compress) }
# 35 gunden eski dosya kayitlarini durumdan dus (buyumesin).
$canli = @{}
foreach ($ad in @($durum.dosyalar.Keys)) { if (Test-Path -LiteralPath $ad) { $canli[$ad] = $durum.dosyalar[$ad] } }
$durum.dosyalar = $canli
Write-BeyinText -Path $durumYol -Text (ConvertTo-Json -InputObject $durum -Depth 6 -Compress)

# --- 2) rapor --------------------------------------------------------------
$bugun = (Get-Date).Date
$satirlar = New-Object System.Collections.Generic.List[object]
for ($i = $Gun - 1; $i -ge 0; $i--) {
    $g = $bugun.AddDays(-$i).ToString('yyyy-MM-dd')
    $gn = Gun-Al $g
    foreach ($a in $gn.k.Keys) {
        $par = $a.Split('|'); $t = $gn.k[$a]
        $satirlar.Add([pscustomobject]@{ Gun = $g; Ajan = $par[0]; Proje = $par[1]; Oturum = $par[2]; Model = $par[3]
            In = [double]$t.in; Out = [double]$t.out; Cw = [double]$t.cw5 + [double]$t.cw1h; Cr = [double]$t.cr; N = [int]$t.n
            Usd = [double]$t.usd; Fiyatsiz = [int]$t.fiyatsiz; MaxCtx = [double]$t.maxctx; BuyukN = [int]$t.buyukN; BuyukUsd = [double]$t.buyukUsd; IlkCtx = [double]$t.ilkctx })
    }
}
function Jeton([double]$x) { if ($x -ge 1e9) { '{0:N1}G' -f ($x / 1e9) } elseif ($x -ge 1e6) { '{0:N1}M' -f ($x / 1e6) } elseif ($x -ge 1e3) { '{0:N0}K' -f ($x / 1e3) } else { '{0:N0}' -f $x } }
function Usd([double]$x) { '${0:N2}' -f $x }

$cl = @($satirlar | Where-Object { $_.Ajan -eq 'claude' })
$cx = @($satirlar | Where-Object { $_.Ajan -eq 'codex' })
$clUsd = ($cl | Measure-Object -Property Usd -Sum).Sum; if (-not $clUsd) { $clUsd = 0 }
$cxTok = ($cx | ForEach-Object { $_.In + $_.Out + $_.Cr } | Measure-Object -Sum).Sum; if (-not $cxTok) { $cxTok = 0 }
$cxUsd = ($cx | Measure-Object -Property Usd -Sum).Sum; if (-not $cxUsd) { $cxUsd = 0 }
$oturumlar = @($cl | Group-Object Oturum | ForEach-Object {
    [pscustomobject]@{ Oturum = $_.Name; Proje = $_.Group[0].Proje; Usd = ($_.Group | Measure-Object -Property Usd -Sum).Sum
        MaxCtx = ($_.Group | Measure-Object -Property MaxCtx -Maximum).Maximum; IlkCtx = ($_.Group | Measure-Object -Property IlkCtx -Maximum).Maximum
        BuyukUsd = ($_.Group | Measure-Object -Property BuyukUsd -Sum).Sum; N = ($_.Group | Measure-Object -Property N -Sum).Sum } })
$ilkler = @($oturumlar | Where-Object { $_.IlkCtx -gt 0 })
$sabit = $(if ($ilkler.Count) { ($ilkler | Measure-Object -Property IlkCtx -Average).Average } else { 0 })
$buyukOt = @($oturumlar | Where-Object { $_.MaxCtx -gt $BUYUK_BAGLAM })
$buyukUsd = ($oturumlar | Measure-Object -Property BuyukUsd -Sum).Sum; if (-not $buyukUsd) { $buyukUsd = 0 }

$ozet = [ordered]@{ v = 1; ts = (Get-Date).ToString('o', $inv); gun = $Gun; claudeUsd = [math]::Round($clUsd, 2); codexJeton = [int64]$cxTok
    codexUsd = [math]::Round($cxUsd, 2); claudeOturum = $oturumlar.Count; sabitYukJeton = [int64]$sabit; buyukBaglamOturum = $buyukOt.Count
    buyukBaglamUsd = [math]::Round($buyukUsd, 2); taninmayan = $taninmayan; hataliDosya = $hatali; taranan = $taranan; yeniKayit = $yeniKayit
    fiyatTarihi = [string]$tablo.Tarih; ms = $sw.ElapsedMilliseconds }
Write-BeyinText -Path (Join-Path $kok 'son.json') -Text (ConvertTo-Json -InputObject $ozet -Compress)
Write-BeyinMakbuz -Paths $p -Script 'maliyet' -Outcome $(if ($hatali -gt 0 -or $taninmayan -gt 0) { 'MALIYET_KISMI' } else { 'MALIYET_OK' }) `
    -DurationMs $sw.ElapsedMilliseconds -Note "taranan=$taranan yeni=$yeniKayit taninmayan=$taninmayan hatali=$hatali"
try { $mtx.ReleaseMutex() } catch { }

if ($YalnizTara) { "maliyet: $taranan dosya tarandi, $yeniKayit yeni kayit, taninmayan $taninmayan ($([int]$sw.Elapsed.TotalSeconds) sn)"; exit 0 }
if ($Json) { ConvertTo-Json -InputObject $ozet -Compress; exit 0 }

"MALIYET - son $Gun gun (API esdegeri; abonelikte gercek fatura degildir; fiyatlar $($tablo.Tarih))"
""
"Gun          Claude      Claude cagri  Codex jeton"
foreach ($g in @($satirlar | Group-Object Gun | Sort-Object Name)) {
    $gc = @($g.Group | Where-Object { $_.Ajan -eq 'claude' }); $gx = @($g.Group | Where-Object { $_.Ajan -eq 'codex' })
    "{0}   {1,-10}  {2,-12}  {3}" -f $g.Name, (Usd (($gc | Measure-Object -Property Usd -Sum).Sum)), (($gc | Measure-Object -Property N -Sum).Sum), (Jeton (($gx | ForEach-Object { $_.In + $_.Out + $_.Cr } | Measure-Object -Sum).Sum))
}
"Toplam       $(Usd $clUsd)" + $(if ($cxUsd -gt 0) { " - Codex $(Usd $cxUsd)" } else { " - Codex $(Jeton $cxTok) jeton (fiyat yok)" })
""
"Projeler (Claude, en pahali 8):"
foreach ($pr in @($cl | Group-Object Proje | ForEach-Object { [pscustomobject]@{ Ad = $_.Name; Usd = ($_.Group | Measure-Object -Property Usd -Sum).Sum } } | Sort-Object Usd -Descending | Select-Object -First 8)) {
    "  {0,-28} {1}" -f $pr.Ad, (Usd $pr.Usd)
}
""
"En pahali oturumlar:"
foreach ($o in @($oturumlar | Sort-Object Usd -Descending | Select-Object -First 5)) {
    "  {0}  {1,-22} {2,-9} {3} cagri, en buyuk baglam {4}" -f $o.Oturum.Substring(0, [math]::Min(8, $o.Oturum.Length)), $o.Proje, (Usd $o.Usd), $o.N, (Jeton $o.MaxCtx)
}
""
"Oturum basi sabit yuk (ilk cagri baglami, ortalama): $(Jeton $sabit) jeton ($($ilkler.Count) oturum)"
if ($buyukOt.Count) {
    "200K baglami asan oturum: $($buyukOt.Count) - bu cagrilarin maliyeti $(Usd $buyukUsd). Bu oturumlar /compact ya da yeni oturumla tazelenmeliydi."
} else { "200K baglami asan oturum yok." }
if ($cx.Count) { "Codex notu: sayac kumulatif; bir oturumun ILK olcumu o ana kadarki toplamin tamamini olcum gunune yazar (ilk taramada eski gunler sisik gorunur)." }
if ($taninmayan -gt 0 -or $hatali -gt 0) { "OLCEMEDIM: $taninmayan satir taninmayan bicimde, $hatali dosya okunamadi (bu kisim toplama girmedi)." }
"($taranan dosya tarandi, $yeniKayit yeni kayit, $([int]$sw.Elapsed.TotalSeconds) sn)"
