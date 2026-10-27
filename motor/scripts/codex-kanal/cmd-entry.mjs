// A nonstandard CMD shim still receives literal argv, including a trailing '-'.
// Encoding the complete PowerShell invocation avoids -File parameter binding.
import { spawn } from 'node:child_process';
import { join } from 'node:path';
const [launcher, ...args] = process.argv.slice(2);
if (!launcher || !/\.cmd$/i.test(launcher)) process.exit(64);
const literal = value => "'" + value.replaceAll("'", "''") + "'";
const code = `[Console]::InputEncoding = New-Object Text.UTF8Encoding $false; [Console]::OutputEncoding = New-Object Text.UTF8Encoding $false; $OutputEncoding = [Console]::OutputEncoding; & ${literal(launcher)} @(${args.map(literal).join(',')}); exit $LASTEXITCODE`;
const child = spawn(join(process.env.SystemRoot || 'C:\\Windows', 'System32/WindowsPowerShell/v1.0/powershell.exe'),
  ['-NoProfile', '-NonInteractive', '-EncodedCommand', Buffer.from(code, 'utf16le').toString('base64')], { stdio: 'inherit', windowsHide: true });
child.on('error', () => process.exit(70));
child.on('exit', code => process.exit(code ?? 70));
