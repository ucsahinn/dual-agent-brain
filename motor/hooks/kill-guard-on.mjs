#!/usr/bin/env node
// kill-guard-on.mjs - Kill guard ON FILTRESI (BB5, 2026-10-06).
//
// NEDEN: PreToolUse her Bash cagrisinda kosar. PowerShell acilisi bu makinede
// ~430-450 ms (olculdu); koruma kancasi dogrudan PowerShell olunca her komuta
// ~550 ms ekliyordu. Bu filtre node ile (~60-100 ms) yalniz desen arar; desen
// yoksa hemen 0 ile cikar, varsa asil korumayi (pre-tool-use.ps1, launcher
// uzerinden) ayni stdin ile cagirir ve onun engel kararini (exit 2 + stderr) iletir.
//
// FAIL-OPEN: her hata, zaman asimi ya da bos girdi -> exit 0. stderr'e yalniz
// engel gerekcesi yazilir. Kurulum: ~\.beyin\kill-guard-on.mjs (kur.ps1 kopyalar).
import { spawnSync } from "node:child_process";
import { join } from "node:path";
import { homedir } from "node:os";

const DESEN = /taskkill|tskill|pkill|killall|stop-process|spps|wmic|\bkill(?=\s)|approvals|korunan-pid/i;
const ajan = process.argv.includes("--codex") ? "codex" : "claude";
const parcalar = [];
let bitti = false;

function cik(kod) { if (!bitti) { bitti = true; process.exit(kod); } }
setTimeout(() => cik(0), 3000).unref();

process.stdin.on("error", () => cik(0));
process.stdin.on("data", (d) => { parcalar.push(d); if (parcalar.reduce((n, b) => n + b.length, 0) > 1048576) cik(0); });
process.stdin.on("end", () => {
  try {
    if (process.env.BEYIN_CHILD === "1" || process.env.BEYIN_KILL_GUARD === "kapali") return cik(0);
    const ham = Buffer.concat(parcalar).toString("utf8");
    if (!ham || !DESEN.test(ham)) return cik(0);
    const launcher = join(homedir(), ".beyin", "beyin-launcher.ps1");
    const r = spawnSync("powershell", ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", launcher, "-Hook", "pre-tool-use", "-Agent", ajan],
      { input: ham, encoding: "utf8", timeout: 9000, windowsHide: true });
    if (r.status === 2) {
      process.stderr.write((r.stderr || "").trim() || "[Beyin kill guard] ENGELLENDI");
      return cik(2);
    }
    return cik(0);
  } catch {
    return cik(0);
  }
});
