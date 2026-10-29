# PS 5.1: same traversal, exception boundaries and file timestamps as Olc-Dizin.
# Keep this helper local to copcu; none of the deletion gates live here.
if (-not ('BeyinCopcuOlcumV1' -as [type])) {
    Add-Type -ErrorAction Stop -TypeDefinition @'
using System;
using System.IO;
using System.Collections.Generic;
using System.Diagnostics;
using System.Text;
using System.Threading.Tasks;
public sealed class BeyinCopcuOlcumV1 {
    public sealed class GitStatus {
        public bool Ok;
        public string Out = "";
        public int Kod = -1;
    }
    public static Dictionary<string, GitStatus> Statuses(string[] repos) {
        var results = new Dictionary<string, GitStatus>(StringComparer.OrdinalIgnoreCase);
        // Each repo gets exactly the original git status invocation. Bound child
        // concurrency; collect stdout and stderr asynchronously to avoid pipe stalls.
        for (int offset = 0; offset < repos.Length; offset += 4) {
            int count = Math.Min(4, repos.Length - offset);
            var processes = new Process[count];
            var stdout = new Task<string>[count];
            var stderr = new Task<string>[count];
            for (int k = 0; k < count; k++) {
                string repo = repos[offset + k];
                results[repo] = new GitStatus();
                try {
                    string quoted = "\"" + System.Text.RegularExpressions.Regex.Replace(repo, @"(\\+)$", "$1$1") + "\"";
                    var psi = new ProcessStartInfo("git", "-c core.quotepath=false -C " + quoted + " status --porcelain --ignored=matching -z");
                    psi.UseShellExecute = false;
                    psi.CreateNoWindow = true;
                    psi.RedirectStandardOutput = true;
                    psi.RedirectStandardError = true;
                    psi.StandardOutputEncoding = new UTF8Encoding(false);
                    psi.StandardErrorEncoding = new UTF8Encoding(false);
                    processes[k] = Process.Start(psi);
                    stdout[k] = processes[k].StandardOutput.ReadToEndAsync();
                    stderr[k] = processes[k].StandardError.ReadToEndAsync();
                } catch { }
            }
            for (int k = 0; k < count; k++) {
                var process = processes[k];
                if (process == null) continue;
                try {
                    string output = stdout[k].GetAwaiter().GetResult();
                    stderr[k].GetAwaiter().GetResult();
                    process.WaitForExit();
                    var result = results[repos[offset + k]];
                    result.Out = output;
                    result.Kod = process.ExitCode;
                    result.Ok = process.ExitCode == 0;
                } catch { }
                finally { process.Dispose(); }
            }
        }
        return results;
    }
    public long Bayt;
    public int Dosya;
    public DateTime Son = DateTime.MinValue;
    private static bool Forbidden(string dir, string[] forbidden) {
        foreach (string path in forbidden) {
            if (String.Equals(dir, path, StringComparison.OrdinalIgnoreCase) ||
                dir.StartsWith(path + "\\", StringComparison.OrdinalIgnoreCase)) return true;
        }
        return false;
    }
    private static bool SkipName(string name) {
        name = name.ToLowerInvariant();
        return name == "node_modules" || name == ".git" || name == "$recycle.bin" || name == "system volume information";
    }
    private static bool ValidateGit(string repo) {
        try {
            string quoted = "\"" + System.Text.RegularExpressions.Regex.Replace(repo, @"(\\+)$", "$1$1") + "\"";
            var psi = new ProcessStartInfo("git", "-c core.quotepath=false -C " + quoted + " rev-parse --git-dir");
            psi.UseShellExecute = false;
            psi.CreateNoWindow = true;
            psi.RedirectStandardOutput = true;
            psi.RedirectStandardError = true;
            psi.StandardOutputEncoding = new UTF8Encoding(false);
            using (var process = Process.Start(psi)) {
                var error = process.StandardError.ReadToEndAsync();
                string output = process.StandardOutput.ReadToEnd();
                error.GetAwaiter().GetResult();
                process.WaitForExit();
                return output.Length > 0;
            }
        } catch { return false; }
    }
    public static string[] ParallelRepositories(string root, string[] forbidden) {
        if (Forbidden(root, forbidden)) return new string[0];
        string git = Path.Combine(root, ".git");
        if ((Directory.Exists(git) || File.Exists(git)) && ValidateGit(root)) return new string[] { root };
        var children = new List<string>();
        try {
            foreach (DirectoryInfo info in new DirectoryInfo(root).EnumerateDirectories()) {
                if (SkipName(info.Name) || IsReparse(info)) continue;
                children.Add(info.FullName);
            }
        } catch { }
        // Partition only the first level: at most four readers, no unbounded
        // task tree. Merge in original stack traversal order, regardless of finish order.
        children.Reverse();
        var batches = new string[children.Count][];
        Parallel.For(0, children.Count, new ParallelOptions { MaxDegreeOfParallelism = 4 }, i => {
            batches[i] = Repositories(children[i], forbidden, null);
        });
        var result = new List<string>();
        foreach (var batch in batches) result.AddRange(batch);
        return result.ToArray();
    }
    private static bool IsReparse(DirectoryInfo info) {
        try {
            // Enumeration already supplies attributes. Keep legacy MAX_PATH
            // failures fail-closed instead of traversing previously skipped dirs.
            FileAttributes attrs = info.FullName.Length >= 248 ? File.GetAttributes(info.FullName) : info.Attributes;
            return (attrs & FileAttributes.ReparsePoint) != 0;
        } catch { return true; }
    }
    public static string[] AllowedChildren(string path, string[] allow, string[] prefixes, string[] skip) {
        var result = new List<string>();
        try { if ((File.GetAttributes(path) & FileAttributes.ReparsePoint) != 0) return result.ToArray(); }
        catch { return result.ToArray(); }
        var stack = new Stack<string>();
        stack.Push(path);
        while (stack.Count > 0) {
            string dir = stack.Pop();
            try {
                foreach (DirectoryInfo info in new DirectoryInfo(dir).EnumerateDirectories()) {
                    string child = info.FullName;
                    string name = info.Name.ToLowerInvariant();
                    if (Array.IndexOf(skip, name) >= 0) continue;
                    if (IsReparse(info)) continue;
                    string git = Path.Combine(child, ".git");
                    if (File.Exists(git) || Directory.Exists(git)) continue;
                    bool allowed = Array.IndexOf(allow, name) >= 0;
                    foreach (string prefix in prefixes) {
                        if (name.StartsWith(prefix) && name.Length > prefix.Length) { allowed = true; break; }
                    }
                    if (allowed) result.Add(child);
                    else stack.Push(child);
                }
            } catch { }
        }
        return result.ToArray();
    }
    public static string[] Repositories(string root, string[] forbidden, Func<string, bool> validate) {
        var result = new List<string>();
        var stack = new Stack<string>();
        stack.Push(root);
        while (stack.Count > 0) {
            string dir = stack.Pop();
            if (Forbidden(dir, forbidden)) continue;
            string git = Path.Combine(dir, ".git");
            if ((Directory.Exists(git) || File.Exists(git)) && (validate == null ? ValidateGit(dir) : validate(dir))) {
                result.Add(dir);
                continue;
            }
            try {
                foreach (DirectoryInfo info in new DirectoryInfo(dir).EnumerateDirectories()) {
                    string child = info.FullName;
                    if (SkipName(info.Name)) continue;
                    if (IsReparse(info)) continue;
                    stack.Push(child);
                }
            } catch { }
        }
        return result.ToArray();
    }
    public static BeyinCopcuOlcumV1 Measure(string path) {
        var result = new BeyinCopcuOlcumV1();
        var stack = new Stack<string>();
        stack.Push(path);
        while (stack.Count > 0) {
            string dir = stack.Pop();
            try {
                foreach (FileInfo info in new DirectoryInfo(dir).EnumerateFiles()) {
                    // PS 5.1 suppresses property-getter errors, then still counts
                    // the file. FindFirstFile metadata bypasses MAX_PATH errors;
                    // refresh long paths to preserve the original byte totals.
                    FileInfo measured = info;
                    if (info.FullName.Length >= 260) {
                        try { measured = new FileInfo(info.FullName); }
                        catch { result.Dosya++; continue; }
                    }
                    try { result.Bayt += measured.Length; } catch { }
                    result.Dosya++;
                    try { if (measured.LastWriteTime > result.Son) result.Son = measured.LastWriteTime; } catch { }
                }
                foreach (DirectoryInfo info in new DirectoryInfo(dir).EnumerateDirectories()) {
                    if (IsReparse(info)) continue;
                    stack.Push(info.FullName);
                }
            } catch { }
        }
        return result;
    }
}
'@
}
function Get-CopcuOlcum([string]$Yol) {
    return [BeyinCopcuOlcumV1]::Measure($Yol)
}
function Get-CopcuGitDurumlari {
    param([string[]]$Repolar)
    return [BeyinCopcuOlcumV1]::Statuses($Repolar)
}
function Get-CopcuAllowAltDizin {
    param([string]$Yol, [string[]]$Allow, [string[]]$Prefix, [string[]]$Atla)
    return [BeyinCopcuOlcumV1]::AllowedChildren($Yol, $Allow, $Prefix, $Atla)
}
function Get-CopcuRepolar {
    param([string[]]$Kok, [string[]]$Yasak, [Func[string,bool]]$Dogrula)
    foreach ($root in $Kok) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        $resolved = (Resolve-Path -LiteralPath $root).Path
        if ($Dogrula) { [BeyinCopcuOlcumV1]::Repositories($resolved, $Yasak, $Dogrula) }
        else { [BeyinCopcuOlcumV1]::ParallelRepositories($resolved, $Yasak) }
    }
}
