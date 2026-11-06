# bekci-karar.ps1 - Bekci karar katmani (2026-10-31): canli ajan surecleri + kapatma karari.
#
# NEDEN: bekci 1.x oturum DOSYALARINI listeliyordu; dosyanin arkasinda canli surec olup olmadigi, ne kadar bellek tuttugu,
# son ne yaptigi ve kapatmanin guvenli olup olmadigi yazmiyordu. Bitmis kosularin olu iscilerine 'takim durdur' oneriyordu.
# Kullanici: "bekci calistiginda duzgun versin ki ona gore kapatayim emin olduklarimizi". Bu katman:
#   1) surec agacini bir kez okur (Win32_Process): pid, ebeveyn, ad, commit (PrivatePageCount), olusma zamani
#   2) oturum dosyasini CANLI sureciyle eslestirir (pid + ad + PID yeniden kullanim korumasi), ayni pid'e dusen
#      eski oturumlari tekler (Claude /clear ayni surecte yeni oturum acar)
#   3) her canli lider icin transkriptten son etkinligi okur (tur bitti mi, aracta mi) ve pano sahipligini bakar
#   4) saf karar islevi (Get-BekciKarar) ile GUVENLE KAPAT / BAK / DOKUNMA ve GEREKCE uretir
# Hicbir sureci kapatmaz; komutlar yalniz gosterilir (bekci.ps1 'kapat' grubunu panoya kopyalar).

function Get-BekciKarar {
    # Saf islev (test edilir). Girdi: @{ SessizDk; Tur ('bekliyor'|'arac'|'dusunce'|'yazi'|'yok'|''); KartlarAcik (int); Isci (bool);
    #   KosuCalisiyor (bool); EsikDk }. Donus: @{ Karar = 'kapat'|'bak'|'dokunma'; Neden }
    param([hashtable]$G)
    $dk = [double]$G.SessizDk; $esik = [double]$(if ($G.EsikDk) { $G.EsikDk } else { 120 }); $tur = [string]$G.Tur
    if ($G.Isci) {
        if ($G.KosuCalisiyor) { return @{ Karar = 'dokunma'; Neden = 'takım işçisi, koşu çalışıyor' } }
        return @{ Karar = 'bak'; Neden = 'koşusu bitmiş ama işçi süreci hâlâ yaşıyor (yetim olabilir)' }
    }
    if ($dk -lt 10) { return @{ Karar = 'dokunma'; Neden = "son $([int]$dk) dk içinde etkin" } }
    if ($tur -in @('arac', 'dusunce', 'yazi') -and $dk -lt 60) { return @{ Karar = 'dokunma'; Neden = 'bir iş sürüyor (araç/düşünce)' } }
    if ([int]$G.KartlarAcik -gt 0) { return @{ Karar = 'bak'; Neden = "panoda $([int]$G.KartlarAcik) açık kartın sahibi" } }
    if ($tur -in @('arac', 'dusunce', 'yazi')) { return @{ Karar = 'bak'; Neden = "$([int]$dk) dk'dır aynı işte: izin onayı bekliyor ya da takılmış olabilir, pencereye bak" } }
    if ($tur -eq 'bekliyor') {
        if ($dk -ge $esik) { return @{ Karar = 'kapat'; Neden = "turu bitmiş, $(Format-BekciSure $dk) sessiz, açık kartı yok" } }
        return @{ Karar = 'bak'; Neden = "turu bitmiş, $(Format-BekciSure $dk) sessiz (eşik $([int]$esik) dk): dönecek misin?" }
    }
    # transkript yok / okunamadi: kanit yok, guvenli demeyiz
    if ($dk -ge $esik) { return @{ Karar = 'bak'; Neden = "$(Format-BekciSure $dk) sessiz ama son durumu okunamadı (transkript yok)" } }
    return @{ Karar = 'dokunma'; Neden = 'son durumu okunamadı, yakın zamanda etkin' }
}
function Format-BekciSure([double]$Dk) {
    if ($Dk -lt 60) { return "$([int]$Dk) dk" }
    if ($Dk -lt 1440) { return ('{0:0.#} sa' -f ($Dk / 60)) }
    return ('{0:0.#} gün' -f ($Dk / 1440))
}
function Format-BekciMB([double]$MB) { if ($MB -ge 1024) { return ('{0:0.0} GB' -f ($MB / 1024)) }; return ('{0:0} MB' -f $MB) }

function Get-BekciSurecAgaci {
    # Tek CIM okumasi. Donus: @{ Pid -> @{ Pid; Ebeveyn; Ad; Komut; CommitMB; WsMB; Olusma } ; Cocuk = @{ Pid -> [int[]] } }
    $h = @{}; $c = @{}
    foreach ($pr in @(Get-CimInstance Win32_Process -ErrorAction Stop)) {
        $id = [int]$pr.ProcessId
        $h[$id] = @{ Pid = $id; Ebeveyn = [int]$pr.ParentProcessId; Ad = [string]$pr.Name; Komut = [string]$pr.CommandLine
            CommitMB = [double]$pr.PrivatePageCount / 1MB; WsMB = [double]$pr.WorkingSetSize / 1MB; Olusma = $pr.CreationDate }
    }
    foreach ($s in $h.Values) { if (-not $c.ContainsKey($s.Ebeveyn)) { $c[$s.Ebeveyn] = New-Object System.Collections.Generic.List[int] }; $c[$s.Ebeveyn].Add($s.Pid) }
    return @{ Surec = $h; Cocuk = $c }
}
function Get-BekciAgacToplam($Agac, [int]$Kok) {
    # kok + butun torunlar: commit MB toplami ve surec sayisi (dongu korumali)
    $top = 0.0; $n = 0; $gor = @{}; $yigin = New-Object System.Collections.Generic.Stack[int]; $yigin.Push($Kok)
    while ($yigin.Count) {
        $x = $yigin.Pop(); if ($gor.ContainsKey($x)) { continue }; $gor[$x] = $true
        $s = $Agac.Surec[$x]; if (-not $s) { continue }
        $top += $s.CommitMB; $n++
        if ($Agac.Cocuk.ContainsKey($x)) { foreach ($k in $Agac.Cocuk[$x]) { if ($k -ne $x) { $yigin.Push($k) } } }
    }
    return @{ MB = $top; Surec = $n; Pidler = @($gor.Keys) }
}
function Get-BekciBellekGruplari($Agac, [hashtable]$AjanPid) {
    # Bellegi kim tutuyor: ajan agaclari (claude/codex ve altlari), sahipsiz node (ebeveyni olu), diger en buyuk uygulamalar.
    $sahip = @{}
    foreach ($ap in $AjanPid.Keys) { $t = Get-BekciAgacToplam $Agac ([int]$ap); foreach ($x in $t.Pidler) { $sahip[[int]$x] = [string]$AjanPid[$ap] } }
    $g = @{}
    foreach ($s in $Agac.Surec.Values) {
        $ad = $(if ($sahip.ContainsKey($s.Pid)) { "ajan:$($sahip[$s.Pid])" }
            elseif ($s.Ad -eq 'node.exe' -and -not $Agac.Surec.ContainsKey($s.Ebeveyn)) { 'sahipsiz-node' }
            else { $s.Ad -replace '\.exe$', '' })
        if (-not $g.ContainsKey($ad)) { $g[$ad] = @{ Ad = $ad; MB = 0.0; Surec = 0 } }
        $g[$ad].MB += $s.CommitMB; $g[$ad].Surec++
    }
    return @($g.Values | Sort-Object { - $_.MB })
}

function Get-BekciAdaylar {
    # Canli ajan surecleri + karar. Donus: @{ Adaylar = [pscustomobject[]]; Kapanmis = int; Agac; Hata }
    param([hashtable]$Paths, [int]$EsikDk = 120, [int]$Gun = 14)
    $r = @{ Adaylar = @(); Kapanmis = 0; Agac = $null; Hata = '' }
    try { $agac = Get-BekciSurecAgaci } catch { $r.Hata = "süreç listesi alınamadı: $($_.Exception.Message)"; return $r }
    $r.Agac = $agac
    $simdi = Get-Date
    # pano: acik kart sahipligi (owner.session) - oturum kimliginin ilk 8 karakteriyle eslesir
    $kartlar = @()
    try { if ($Paths.Board -and (Test-Path -LiteralPath $Paths.Board)) { $kartlar = @(((Get-Content -LiteralPath $Paths.Board -Raw -Encoding UTF8) | ConvertFrom-Json).tasks | Where-Object { $_ -and [string]$_.status -in @('todo', 'in_progress', 'review', 'blocked') }) } } catch { }
    # takim kosulari: hangisi calisiyor
    $kosuDurum = @{}
    try { foreach ($f in @(Get-ChildItem -LiteralPath $Paths.TeamRuns -Filter '*.json' -File -ErrorAction SilentlyContinue)) { try { $k = (Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8) | ConvertFrom-Json; if ($k.runId) { $kosuDurum[[string]$k.runId] = [string]$k.status } } catch { } } } catch { }
    $pidGor = @{}; $L = New-Object System.Collections.Generic.List[object]; $kapanmis = 0
    $balonVar = [bool](Get-Command Get-MerkezEtkinlik -ErrorAction SilentlyContinue)
    foreach ($f in @(Get-ChildItem -LiteralPath $Paths.Sessions -Filter '*.json' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)) {
        if ($f.LastWriteTime -lt $simdi.AddDays(-$Gun)) { continue }
        $o = $null; try { $o = (Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8) | ConvertFrom-Json } catch { continue }
        $spid = $(if ($o.PSObject.Properties['pid']) { [int]$o.pid } else { 0 })
        $s = $(if ($spid) { $agac.Surec[$spid] } else { $null })
        # PID yeniden kullanim korumasi: surec adi ajan olmali ve oturum dosyasindan SONRA olusmus olmamali
        $canli = [bool]($s -and $s.Ad -in @('claude.exe', 'codex.exe', 'node.exe') -and (-not $s.Olusma -or $s.Olusma -le $f.LastWriteTime.AddMinutes(1)))
        if (-not $canli) { $kapanmis++; continue }
        if ($pidGor.ContainsKey($spid)) { continue }   # ayni surecteki eski oturum (/clear): en yenisi yeter
        $pidGor[$spid] = $true
        $ajan = [string]$o.agent; $cwd = [string]$o.cwd
        $proje = ''; try { $proje = Get-BeyinProjectLeaf -Path $cwd -Paths $Paths } catch { }
        $sessiz = ($simdi - $f.LastWriteTime).TotalMinutes
        $tur = ''; $son = ''
        if ($balonVar -and $ajan -in @('claude', 'codex')) {
            try {
                $e = Get-MerkezEtkinlik -Ajan $ajan -OturumId $f.BaseName -Cwd $cwd
                if ($e -and $e.Ok) { $tur = [string]$e.Tur; $son = [string]$e.Metin; if ($e.Zaman) { $tn = ($simdi - [datetime]$e.Zaman).TotalMinutes; if ($tn -ge 0 -and $tn -lt $sessiz) { $sessiz = $tn } } }
                elseif ($e) { $tur = 'yok' }
            } catch { }
        }
        $kisa = $f.BaseName.Substring(0, [Math]::Min(8, $f.BaseName.Length))
        $kart = @($kartlar | Where-Object { $_.owner -and [string]$_.owner.session -and ([string]$_.owner.session).Contains($kisa) })
        $tkRun = $(if ($o.PSObject.Properties['takimRun']) { [string]$o.takimRun } else { '' })
        $tkKart = $(if ($o.PSObject.Properties['takimKart']) { [string]$o.takimKart } else { '' })
        $kd = $(if ($tkRun) { [string]$kosuDurum[$tkRun] } else { '' })
        $karar = Get-BekciKarar @{ SessizDk = $sessiz; Tur = $tur; KartlarAcik = $kart.Count; Isci = [bool]$tkRun; KosuCalisiyor = ($kd -in @('running', 'planned', 'paused')); EsikDk = $EsikDk }
        $t = Get-BekciAgacToplam $agac $spid
        $pane = $(if ($o.PSObject.Properties['herdrPane']) { [string]$o.herdrPane } else { '' })
        $L.Add([pscustomobject]@{
            Karar = $karar.Karar; Neden = $karar.Neden; Ajan = $ajan; Proje = $proje; Oturum = $f.BaseName; Pid = $spid
            BellekMB = [math]::Round($t.MB); AltSurec = $t.Surec - 1; SessizDk = [math]::Round($sessiz); Tur = $tur
            Son = $(if (Get-Command Protect-MerkezSatir -ErrorAction SilentlyContinue) { Protect-MerkezSatir $son 90 } else { $son.Substring(0, [Math]::Min(90, $son.Length)) })
            Kartlar = @($kart | ForEach-Object { [string]$_.id }); Takim = $(if ($tkRun) { "$tkRun/$tkKart ($kd)" } else { '' }); Pane = $pane
            Prompt = [int]$o.prompts
            Kapat = $(if ($tkRun -and $kd -in @('running', 'planned', 'paused')) { "beyin takim durdur $tkRun" } else { "taskkill /PID $spid /T /F" })
            Nazik = $(if ($tkRun) { '' } elseif ($ajan -eq 'codex') { "pencerede /exit$(if ($pane) { " (herdr $pane)" })" } else { "pencerede /exit$(if ($pane) { " (herdr $pane)" })" })
        })
    }
    $sira = @{ kapat = 0; bak = 1; dokunma = 2 }
    $r.Adaylar = @($L | Sort-Object @{ Expression = { $sira[$_.Karar] } }, @{ Expression = { - $_.BellekMB } })
    $r.Kapanmis = $kapanmis
    return $r
}
