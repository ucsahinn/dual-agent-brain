# PID yeniden kullanimi regresyonu (2026-11-26): kayittaki pid'li surec yasiyor diye isci canli sayilmamali.
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here 'lib.ps1')

Describe 'Test-BeyinPidSahibi' {
    It 'kayittan once baslamis yasayan sureci sahibi sayar' {
        Test-BeyinPidSahibi -ProcessId $PID -Baslangic ((Get-Date).AddMinutes(5).ToString('o')) | Should Be $true
    }
    It 'kayittan cok sonra baslamis sureci (PID yeniden kullanimi) sahibi saymaz' {
        Test-BeyinPidSahibi -ProcessId $PID -Baslangic ((Get-Date).AddDays(-10).ToString('o')) | Should Be $false
    }
    It 'baslangic yoksa yalniz varliga bakar' {
        Test-BeyinPidSahibi -ProcessId $PID -Baslangic $null | Should Be $true
    }
    It 'okunamayan baslangic metninde varliga duser' {
        Test-BeyinPidSahibi -ProcessId $PID -Baslangic 'tarih-degil' | Should Be $true
    }
    It 'olmayan ya da gecersiz pid canli degildir' {
        Test-BeyinPidSahibi -ProcessId 0 -Baslangic $null | Should Be $false
        Test-BeyinPidSahibi -ProcessId 2147483000 -Baslangic $null | Should Be $false
    }
    It 'onbellekteki surec nesnesini kullanir' {
        $onb = @{ Surecler = @{ 4242 = [pscustomobject]@{ StartTime = (Get-Date).AddDays(-1) } } }
        Test-BeyinPidSahibi -ProcessId 4242 -Baslangic ((Get-Date).ToString('o')) -Onbellek $onb | Should Be $true
        Test-BeyinPidSahibi -ProcessId 4242 -Baslangic ((Get-Date).AddDays(-3).ToString('o')) -Onbellek $onb | Should Be $false
        Test-BeyinPidSahibi -ProcessId 999 -Baslangic $null -Onbellek $onb | Should Be $false
    }
}
