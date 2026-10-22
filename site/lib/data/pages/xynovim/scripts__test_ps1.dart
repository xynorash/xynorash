import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/scripts/test.ps1',
  lines: [
    cm(r'#', '──────────────────────────────────────────'),
    cm(r'#', r'scripts/test.ps1'),
    cm(r'#', r'the spec suite from PowerShell'),
    cm(r'#', r'thirteen lines that hand everything to Lua'),
    cm(r'#', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'Windows entry point for the test suite'),
    kv(r'language', r'PowerShell 5.1 or 7'),
    kv(r'size', r'13 lines, one commit (ff1c8fa, 2026-10-16)'),
    kv(r'delegates to', r'scripts/test.lua, run with nvim --clean -l'),
    ...sec(r'why this file exists'),
    ...para(r'#', r'scripts/test.sh is a 199-line bash script that uses process groups, GNU timeout, tmux cleanup and sed. The portable runner is written in Lua (scripts/test.lua), which runs wherever Neovim runs, and this file is a thin PowerShell wrapper that finds nvim and hands everything to it.'),
    blank,
    ...code('powershell', r'scripts/test.ps1 · lines 1-13', r'''
# Portable entry for the spec suite on Windows (PowerShell 5.1 or 7): runs
# scripts/test.lua with Neovim, no bash needed. Same options as scripts/test.sh
# (pattern..., --list, --timeout N, -v), except --coverage.
#   scripts\test.ps1 [options] [pattern...]
# Needs the plugins in place first (scripts\bootstrap.ps1).
$nvim = Get-Command nvim -ErrorAction SilentlyContinue
if (-not $nvim) {
  [Console]::Error.WriteLine('test.ps1: nvim not found')
  exit 2
}
$lua = Join-Path $PSScriptRoot 'test.lua'
& $nvim.Source --clean -l $lua @args
exit $LASTEXITCODE
'''),
    ...sec(r'what each line does'),
    ...pt(r'#', r'the header', r'states the contract: same options as test.sh (patterns, --list, --timeout N, -v) with the exception of --coverage, and a reminder that the plugins have to be in place first, which is the job of scripts/bootstrap.ps1.'),
    ...pt(r'#', r'Get-Command nvim', r'if Neovim is not on PATH the script prints one line to stderr and exits 2. The code 2 is the same as in test.sh for usage and setup problems, so a CI step can tell a setup problem from a test failure (1).'),
    ...pt(r'#', r'--clean -l', r'the runner itself is started as a Lua script without any user configuration. It is a plain process manager: it launches one headless Neovim per spec file, which is where the real configuration is loaded. Running the manager clean keeps it from depending on the thing it tests.'),
    ...pt(r'#', r'@args and exit $LASTEXITCODE', r'every argument is passed through untouched, and the script exits with whatever the runner exits with, so exit status 0, 1 or 2 means the same as on Linux.'),
    ...sec(r'how it is checked'),
    ...para(r'#', r'tests/scripts-portable_spec.lua was added in the same commit and reads the scripts as text. Its description is that the Windows scripts mirror the shell ones; among other things it loops over scripts/bootstrap.ps1 and scripts/test.ps1 in one of its checks. That is a static guard against the two sets of scripts drifting apart. The real execution happens in the Windows job of the platforms workflow.'),
    blank,
    ...sec(r'history'),
    ...pt(r'#', r'ff1c8fa 2026-10-16', r'added together with scripts/test.lua, bootstrap.ps1 and the platforms workflow. It has not changed since.'),
  ],
);
