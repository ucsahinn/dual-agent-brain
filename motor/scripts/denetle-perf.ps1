# Only denetle uses these helpers; shared lib.ps1 remains unchanged.
if (-not ('BeyinDenetleVektorV1' -as [type])) {
    Add-Type -ErrorAction Stop -TypeDefinition @'
using System;
using System.Collections.Generic;
public sealed class BeyinDenetleVektorV1 {
    public int A;
    public int B;
    public double Cos;
    public static BeyinDenetleVektorV1[] Pairs(float[] all, int n, int dim, double threshold) {
        var result = new List<BeyinDenetleVektorV1>();
        for (int i = 0; i < n - 1; i++) {
            for (int j = i + 1; j < n; j++) {
                double acc = 0.0;
                for (int k = 0; k < dim; k++) {
                    // PowerShell multiplies Singles as Doubles. Preserve summation order.
                    acc += (double)all[i * dim + k] * (double)all[j * dim + k];
                }
                if (acc >= threshold) result.Add(new BeyinDenetleVektorV1 { A=i, B=j, Cos=Math.Round(acc, 3) });
            }
        }
        return result.ToArray();
    }
}
'@
}
function Get-DenetimVektorCiftleri {
    param([hashtable]$Index, [double]$MinCos = 0.80, [int]$EnFazla = 200)
    $sonuc = New-Object System.Collections.Generic.List[object]
    try {
        if (-not $Index -or $Index.N -lt 2) { return @() }
        foreach ($pair in [BeyinDenetleVektorV1]::Pairs($Index.All, $Index.N, $Index.Dim, $MinCos)) {
            $sonuc.Add([pscustomobject]@{ A = [string]$Index.Meta.items[$pair.A].slug; B = [string]$Index.Meta.items[$pair.B].slug; Cos = $pair.Cos })
        }
    } catch { }
    return @($sonuc.ToArray() | Sort-Object Cos -Descending | Select-Object -First $EnFazla)
}

# Per-run raw-token cache: the canonical tokenizer still decides every distinct
# token. No persistent cache, no new stemming/stop-word rules, same per-text set.
$script:DenetimKelimeCache = [Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
function Get-DenetimKelimeler {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return @() }
    $temiz = [regex]::Replace($Text.ToLowerInvariant(), '[^\p{L}\p{Nd}]+', ' ')
    $set = @{}
    foreach ($w in ($temiz -split '\s+')) {
        if ($w.Length -lt 4) { continue }
        if (-not $script:DenetimKelimeCache.ContainsKey($w)) {
            $script:DenetimKelimeCache[$w] = @(Get-BeyinKelimeler -Text $w)
        }
        $terms = $script:DenetimKelimeCache[$w]
        foreach ($kok in $terms) { if ($kok) { $set[[string]$kok] = $true } }
    }
    return @($set.psbase.Keys)
}
