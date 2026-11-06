# merkez-fare.ps1 - beyin merkez FARE katmani (merkez.ps1 dot-source eder).
#
# NEDEN (2026-11-06, kullanici istegi "terminal arayuzu tiklanabilir olsun"): panel yalniz klavyeyle
# kullaniliyordu. Win32 konsol girdisi (ReadConsoleInput + ENABLE_MOUSE_INPUT) ile sekme, satir ve alt
# cubuktaki tus ipuclari tiklanir, teker kaydirir. Windows Terminal (ConPTY) ve klasik konsolda calisir.
#
# GUVENLIK SINIRI: onay penceresi (modal) acikken fare olaylari YOK SAYILIR; onay, kod ve tehlikeli eylem
# yalniz klavyeyle teyit edilir (yanlislikla tiklama onay sayilmaz). Fare yalniz klavyedeki bir tusun
# yaptigini yapar: alt cubukta 'x' ipucuna tiklamak x'e basmakla aynidir ve ayni onay penceresini acar.
#
# Kapatma: beyin ayar BEYIN_MERKEZ_FARE kapali. Fare acikken metin secmek: Shift + surukle.

if (-not ('MerkezFare' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class MerkezFare {
    [StructLayout(LayoutKind.Explicit)]
    struct KAYIT {
        [FieldOffset(0)] public ushort Tur;
        [FieldOffset(4)] public int TusAsagi;
        [FieldOffset(4)] public short X;
        [FieldOffset(6)] public short Y;
        [FieldOffset(8)] public uint Dugme;
        [FieldOffset(12)] public uint Kontrol;
        [FieldOffset(16)] public uint Bayrak;
    }
    [DllImport("kernel32.dll", SetLastError = true)] static extern IntPtr GetStdHandle(int n);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool GetConsoleMode(IntPtr h, out uint m);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool SetConsoleMode(IntPtr h, uint m);
    [DllImport("kernel32.dll", SetLastError = true, EntryPoint = "PeekConsoleInputW")] static extern bool Peek(IntPtr h, [Out] KAYIT[] b, uint n, out uint r);
    [DllImport("kernel32.dll", SetLastError = true, EntryPoint = "ReadConsoleInputW")] static extern bool Oku(IntPtr h, [Out] KAYIT[] b, uint n, out uint r);
    static IntPtr h = IntPtr.Zero; static uint eski; static bool acik;
    public static int X, Y, Dugme, Bayrak, Teker;
    static bool bekleyen;
    public static void Tuket() { bekleyen = false; }
    public static bool Acik { get { return acik; } }
    public static bool Ac() {
        if (acik) return true;
        h = GetStdHandle(-10);
        if (h == IntPtr.Zero || h == new IntPtr(-1) || !GetConsoleMode(h, out eski)) return false;
        // +MOUSE_INPUT(0x10) +EXTENDED_FLAGS(0x80) -QUICK_EDIT(0x40) -VIRTUAL_TERMINAL_INPUT(0x200): fare MOUSE_EVENT kaydi olarak gelir
        uint m = (eski | 0x10u | 0x80u) & ~0x40u & ~0x200u;
        if (!SetConsoleMode(h, m)) return false;
        acik = true; return true;
    }
    public static void Kapat() { if (acik) { SetConsoleMode(h, eski); acik = false; } }
    // 0: bekleyen girdi yok · 1: basili tus bekliyor (Console.ReadKey okusun) · 2: fare olayi okundu (X/Y/Dugme/Bayrak/Teker)
    // Tus birakma, fare hareketi, dugme birakma, odak/menu/boyut olaylari tuketilip atlanir.
    public static int Bak() {
        if (!acik) return 0;
        if (bekleyen) return 2;   // okunmus ama islenmemis fare olayi: GirdiIsle Tuket() ile birakir
        var b = new KAYIT[1]; uint r;
        for (int i = 0; i < 256; i++) {
            if (!Peek(h, b, 1, out r) || r == 0) return 0;
            if (b[0].Tur == 1 && b[0].TusAsagi != 0) return 1;
            if (!Oku(h, b, 1, out r) || r == 0) return 0;
            if (b[0].Tur != 2) continue;
            int bayrak = (int)b[0].Bayrak, dugme = (int)(b[0].Dugme & 0xFFFF);
            if (bayrak == 1) continue;                    // MOUSE_MOVED
            if (bayrak == 0 && dugme == 0) continue;      // dugme birakildi
            X = b[0].X; Y = b[0].Y; Dugme = dugme; Bayrak = bayrak; Teker = (short)(b[0].Dugme >> 16);
            bekleyen = true; return 2;
        }
        return 0;
    }
}
'@
}

$script:fareHarita = $null
$rxFareAnsi = [regex]"$([char]27)\[[0-9;?]*[ -/]*[@-~]|$([char]27)\][^$([char]7)]*($([char]7)|$([char]27)\\)"
$rxFareGenis = [regex]'[ᄀ-ᅟ⺀-꓏가-힣豈-﫿︰-﹏＀-｠￠-￦]|[\uD83C-\uD83E][\uDC00-\uDFFF]'
function FareDuz([string]$s) { return $rxFareAnsi.Replace([string]$s, '') }
function FareKolon([string]$duz, [int]$ix) { $on = $duz.Substring(0, [Math]::Min($ix, $duz.Length)); return $on.Length + $rxFareGenis.Matches($on).Count }

function FareHaritaKur($L) {
    # Kare cizildikten sonra (isaretler henuz silinmeden): ekran satiri -> [sutun araligi -> secilebilir anahtar], sekme ciplerinin
    # ve alt cubuk ipuclarinin sutun araliklari. Isaret = SecKayit'in ESC[1000+n m'i; kaydirilan/kesilen satirin isareti zaten yoktur.
    $h = @{ Satir = @{}; Sekme = (New-Object System.Collections.Generic.List[object]); Alt = (New-Object System.Collections.Generic.List[object]); AltY = $L.Count - 1; Is = -1 }
    for ($y = 0; $y -lt $L.Count; $y++) {
        $ln = $L[$y]; if ($ln.IndexOf("$([char]27)[1") -lt 0) { continue }
        $ms = $rxFareIsaret.Matches($ln); if (-not $ms.Count) { continue }
        $par = New-Object System.Collections.Generic.List[object]
        foreach ($m in $ms) {
            $n = [int]$m.Groups[1].Value - 1000; if ($n -lt 0 -or $n -ge $script:secilebilir.Count) { continue }
            $par.Add(@{ X0 = (FareKolon (FareDuz $ln.Substring(0, $m.Index)) 1e9); Anahtar = [string]$script:secilebilir[$n].Anahtar })
        }
        for ($j = 0; $j -lt $par.Count; $j++) { $par[$j].X1 = $(if ($j + 1 -lt $par.Count) { $par[$j + 1].X0 } else { 100000 }) }
        if ($par.Count) { $par[0].X0 = 0; $h.Satir[$y] = $par }   # ilk parca satirin basindan baslar (cerceve dahil)
    }
    for ($y = 0; $y -lt [Math]::Min(3, $L.Count); $y++) {
        $duz = FareDuz $L[$y]; $bul = New-Object System.Collections.Generic.List[object]
        for ($i = 0; $i -lt $sekmeler.Count; $i++) {
            $et = "$($i + 1) $($sekmeAd[$sekmeler[$i]])"; $ix = $duz.IndexOf($et)
            if ($ix -ge 0) { $bul.Add(@{ Y = $y; X0 = (FareKolon $duz $ix); X1 = (FareKolon $duz ($ix + $et.Length)) + 1; Sekme = $sekmeler[$i] }) }
        }
        if ($bul.Count -ge 3) { $h.Sekme = $bul; break }
    }
    for ($y = 1; $y -lt [Math]::Min(6, $L.Count - 1); $y++) { if ((FareDuz $L[$y]).Contains('seni bekliyor')) { $h.Is = $y; break } }
    if ($script:altTuslar) {
        $duz = FareDuz $L[$L.Count - 1]; $bas = 0
        foreach ($t in @($script:altTuslar)) {
            $et = FareDuz $t; if (-not $et) { continue }
            $ix = $duz.IndexOf($et, $bas); if ($ix -lt 0) { continue }
            $h.Alt.Add(@{ X0 = (FareKolon $duz $ix); X1 = (FareKolon $duz ($ix + $et.Length)); Tus = ($et -split ' ', 2)[0] })
            $bas = $ix + $et.Length
        }
    }
    $script:fareHarita = $h
}

function FareTusTaklit([string]$Tus) {
    # Alt cubuktaki ipucu = o tusa basmak. Donus: TusIsle'nin donusu ($true: cik).
    switch ($Tus) {
        'Tab' { return (TusIsle (New-Object ConsoleKeyInfo ([char]9), ([ConsoleKey]::Tab), $false, $false, $false)) }
        '⏎'   { return (TusIsle (New-Object ConsoleKeyInfo ([char]13), ([ConsoleKey]::Enter), $false, $false, $false)) }
        '↑↓'  { return $false }
    }
    if ($Tus.Length -ne 1) { return $false }
    return (TusIsle (New-Object ConsoleKeyInfo ([char]$Tus), ([ConsoleKey]0), $false, $false, $false))
}

function FareSec([string]$Anahtar) {
    $script:secAnahtar[$script:sekmeAktif] = $Anahtar
    for ($i = 0; $i -lt $script:secilebilir.Count; $i++) { if ([string]$script:secilebilir[$i].Anahtar -eq $Anahtar) { $script:sec = $i; break } }
}

function FareIsle([int]$X, [int]$Y, [int]$Dugme, [int]$Bayrak, [int]$Teker) {
    # Donus $true: cik (alt cubuktaki 'q' tiklandi).
    $h = $script:fareHarita; if (-not $h) { return $false }
    if ($script:EylemVar -and $script:modal) { Mesaj 'onay penceresi açık: fareyle onaylanmaz · klavyeyle Y/N' $cWarn; return $false }
    if ($Bayrak -band 4) { $adim = $(if ($script:sekmeAktif -eq 'Olaylar') { 3 } else { 1 }); SecimKaydir $(if ($Teker -gt 0) { -$adim } else { $adim }); return $false }   # teker
    if (-not ($Dugme -band 3)) { return $false }
    $sag = [bool]($Dugme -band 2) -and -not ($Dugme -band 1)
    foreach ($s in $h.Sekme) { if ($Y -eq $s.Y -and $X -ge $s.X0 -and $X -lt $s.X1) { SekmeGec $s.Sekme; return $false } }
    if ($Y -eq $h.AltY) {
        foreach ($t in $h.Alt) { if ($X -ge $t.X0 -and $X -lt $t.X1) { return (FareTusTaklit $t.Tus) } }
        return $false
    }
    if ($Y -eq $h.Is -and $Y -ge 0) { SekmeGec 'Isler'; return $false }
    $an = ''; if ($h.Satir.ContainsKey($Y)) { foreach ($pc in $h.Satir[$Y]) { if ($X -ge $pc.X0 -and $X -lt $pc.X1) { $an = $pc.Anahtar; break } } }
    if ($an) {
        $zatenSecili = ([string]$script:secAnahtar[$script:sekmeAktif] -eq $an)
        FareSec $an
        if ($sag) { if ($script:EylemVar) { EylemMenusu } else { Kopyala (Secili) }; return $false }
        if ($zatenSecili -or ($Bayrak -band 2)) { Odak }   # ikinci tik / cift tik = Enter
    }
    return $false
}

function GirdiIsle {
    # Bekleyen butun girdiyi isler. Donus @{ Oldu; Cik }. Fare kapaliyken eski yol (KeyAvailable/ReadKey).
    # NOT: fare acikken [Console]::KeyAvailable CAGRILMAZ: .NET tus disi olaylari (fare) okuyup atar.
    $oldu = $false
    for ($i = 0; $i -lt 64; $i++) {
        $t = $(if ($script:FareVar -and [MerkezFare]::Acik) { [MerkezFare]::Bak() } elseif ([Console]::KeyAvailable) { 1 } else { 0 })
        if ($t -eq 0) { break }
        $once = $script:sekmeAktif; $oldu = $true; $script:lastFrame = ''
        if ($t -eq 1) { if (TusIsle ([Console]::ReadKey($true))) { return @{ Oldu = $true; Cik = $true } } }
        else {
            $ust = 0; try { $ust = [Console]::WindowTop } catch { }   # klasik konsolda tampon kaydirilmis olabilir; ConPTY'de 0
            $fx = [MerkezFare]::X; $fy = [int]([MerkezFare]::Y) - $ust; $fd = [MerkezFare]::Dugme; $fb = [MerkezFare]::Bayrak; $ft = [MerkezFare]::Teker
            [MerkezFare]::Tuket()
            if (FareIsle $fx $fy $fd $fb $ft) { return @{ Oldu = $true; Cik = $true } }
        }
        if ($script:sekmeAktif -ne $once) { break }   # yeni sekme cizilmeden kalan girdi eski secim listesine uygulanmasin
    }
    return @{ Oldu = $oldu; Cik = $false }
}
function GirdiBekliyor {
    if ($script:FareVar -and [MerkezFare]::Acik) { return ([MerkezFare]::Bak() -ne 0) }
    return [Console]::KeyAvailable
}
