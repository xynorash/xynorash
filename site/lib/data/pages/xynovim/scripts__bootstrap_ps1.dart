import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/scripts/bootstrap.ps1',
  lines: [
    cm(r'#', '──────────────────────────────────────────'),
    cm(r'#', r'scripts/bootstrap.ps1'),
    cm(r'#', r'bootstrap.sh for Windows'),
    cm(r'#', r'same three steps, a junction instead of a symlink, hashes instead of cmp'),
    cm(r'#', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'first-run installer on Windows'),
    kv(r'language', r'PowerShell, written for both 5.1 and 7'),
    kv(r'size', r'114 lines, one commit (ff1c8fa, 2026-10-16)'),
    kv(r'mirrors', r'scripts/bootstrap.sh'),
    ...sec(r'why this file exists'),
    ...para(r'#', r'The Linux bootstrap is a bash script that uses readlink, cmp, diff, mktemp and ln. This second script does the same three steps in PowerShell, using Get-FileHash, Copy-Item and a temporary file instead. It was added in one commit, ff1c8fa on 2026-10-16, together with the platforms workflow and the portable test runner, as part of the Windows and macOS portability work.'),
    blank,
    ...para(r'#', r'The header says it plainly: the same three steps as bootstrap.sh, with a pointer to that file for why there are two install rounds. It then lists the differences it knows about: Neovim’s Windows defaults for the config directory, no unzip or gzip because Mason uses PowerShell and tar on Windows, and no automatic installation of prerequisites, only a printed list of what is missing and how to get it.'),
    blank,
    ...code('powershell', r'scripts/bootstrap.ps1 · lines 1-16', r'''
# Bootstrap this config on a fresh Windows machine (PowerShell 5.1 or 7) so the
# plugins end up on exactly the commits in lazy-lock.json. The same three steps
# as scripts/bootstrap.sh (read its header for why there are two install rounds):
#   1. `Lazy! install` clones everything (the lockfile is rewritten, ignored);
#   2. the original lockfile is put back, then `Lazy! restore`;
#   3. scripts/provision.lua downloads the treesitter parsers and Mason tools.
# lazy-lock.json is left exactly as it was; the script fails if it is not.
#
# Usage: scripts\bootstrap.ps1          (config = the checkout this lives in)
# Env:   XDG_CONFIG_HOME / XDG_DATA_HOME are honoured, else Neovim's Windows
#        defaults (%LOCALAPPDATA%\nvim and \nvim-data).
#        BOOTSTRAP_SKIP_PREREQS=1 skips the prerequisite check.
# Not run through winget/scoop for you: it prints what is missing and how to
# install it. Compare with bootstrap.sh: no unzip/gzip here (Mason uses
# PowerShell and tar on Windows).
$ErrorActionPreference = 'Continue'
'''),
    ...sec(r'finding and linking the config directory'),
    ...code('powershell', r'scripts/bootstrap.ps1 · lines 18-47', r'''
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$lock = Join-Path $repo 'lazy-lock.json'

# nvim reads the config from $XDG_CONFIG_HOME\nvim, else %LOCALAPPDATA%\nvim.
if ($env:XDG_CONFIG_HOME) { $cfgRoot = $env:XDG_CONFIG_HOME } else { $cfgRoot = $env:LOCALAPPDATA }
$cfg = Join-Path $cfgRoot 'nvim'

function Get-RealPath([string]$p) {
  $item = Get-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue
  if (-not $item) { return $null }
  if ($item.Target) { return (Resolve-Path -LiteralPath ($item.Target | Select-Object -First 1)).Path.TrimEnd('\') }
  return $item.FullName.TrimEnd('\')
}

if (-not (Test-Path -LiteralPath $cfg)) {
  New-Item -ItemType Directory -Force -Path $cfgRoot | Out-Null
  # a junction needs no administrator rights (a symlink does)
  & cmd.exe /c mklink /J "$cfg" "$repo" | Out-Null
  if ($LASTEXITCODE -ne 0) {
    Write-Error "bootstrap: could not create the junction $cfg -> $repo"
    exit 1
  }
  Write-Host "bootstrap: linked $cfg -> $repo"
}
$real = Get-RealPath $cfg
if ($real -ne $repo.TrimEnd('\')) {
  [Console]::Error.WriteLine("bootstrap: $cfg is not this checkout ($repo).")
  [Console]::Error.WriteLine("  link it first:  cmd /c mklink /J `"$cfg`" `"$repo`"   (move the existing directory away first)")
  exit 1
}
'''),
    ...para(r'#', r'On Linux the script refuses to create the link. Here it creates one if the target path does not exist at all. That is a difference between the two scripts: the junction created with cmd /c mklink /J needs no administrator rights, which the comment points out (a symlink does). If something already exists at the path, the script compares real paths instead and refuses on a mismatch, telling the user to move the old directory away first.'),
    blank,
    ...para(r'#', r'Get-RealPath exists because a junction is a reparse point. If the item has a Target, the function resolves it and trims the trailing backslash; otherwise it returns the full name. Comparing a trimmed path with a trimmed path avoids a false mismatch from a trailing separator. The XDG variable is honoured first, then %LOCALAPPDATA%, which matches the header’s statement of Neovim’s Windows defaults.'),
    blank,
    ...sec(r'prerequisites with instructions'),
    ...code('powershell', r'scripts/bootstrap.ps1 · lines 49-83', r'''
# Prerequisites: tool, how to install it.
if ($env:BOOTSTRAP_SKIP_PREREQS -ne '1') {
  $missing = @()
  $needs = [ordered]@{
    'nvim'     = 'winget install Neovim.Neovim   (or scoop install neovim)'
    'git'      = 'winget install Git.Git   (or scoop install git)'
    'curl'     = 'curl.exe ships with Windows 10 and later'
    'tar'      = 'tar.exe (bsdtar) ships with Windows 10 and later'
    'node'     = 'winget install OpenJS.NodeJS.LTS   (or scoop install nodejs-lts)'
    'npm'      = 'comes with Node.js'
    'cargo'    = 'winget install Rustlang.Rustup   (or https://rustup.rs)'
    'rustup'   = 'winget install Rustlang.Rustup   (or https://rustup.rs)'
  }
  foreach ($tool in $needs.Keys) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) { $missing += "$tool  ->  $($needs[$tool])" }
  }
  # tree-sitter parsers are compiled: any C compiler nvim-treesitter knows will do
  $cc = $false
  foreach ($c in 'gcc', 'cc', 'clang', 'cl', 'zig') { if (Get-Command $c -ErrorAction SilentlyContinue) { $cc = $true; break } }
  if (-not $cc) { $missing += 'a C compiler (gcc, clang, cl or zig)  ->  winget install zig.zig   (or scoop install gcc; or Visual Studio Build Tools)' }
  # rustup ships a rust-analyzer proxy even when the component is absent
  $ra = Get-Command rust-analyzer -ErrorAction SilentlyContinue
  if (-not $ra) {
    $missing += 'rust-analyzer  ->  rustup component add rust-analyzer'
  } else {
    & rust-analyzer --version *> $null
    if ($LASTEXITCODE -ne 0) { $missing += 'rust-analyzer (installed as a rustup proxy only)  ->  rustup component add rust-analyzer' }
  }
  if ($missing.Count -gt 0) {
    [Console]::Error.WriteLine('bootstrap: missing prerequisites:')
    foreach ($m in $missing) { [Console]::Error.WriteLine("  - $m") }
    [Console]::Error.WriteLine('Install them (or set BOOTSTRAP_SKIP_PREREQS=1 to go on anyway) and rerun.')
    exit 1
  }
}
'''),
    ...para(r'#', r'The prerequisites are an ordered hashtable from tool name to a sentence that says how to install it: winget or scoop commands, or the note that curl.exe and tar.exe ship with Windows 10 and later. A report that includes the fix is more useful than a list of names. The C compiler is handled as a set of alternatives (gcc, cc, clang, cl or zig), because nvim-treesitter accepts any of them, and the rust-analyzer check repeats the rustup proxy trap from the shell version: Get-Command finds the proxy, so the script runs rust-analyzer --version and looks at the exit code.'),
    blank,
    ...sec(r'the three steps and the comparison'),
    ...code('powershell', r'scripts/bootstrap.ps1 · lines 85-114', r'''
$orig = [IO.Path]::GetTempFileName()
try {
  Copy-Item -LiteralPath $lock -Destination $orig -Force
  $origHash = (Get-FileHash -LiteralPath $orig -Algorithm SHA256).Hash

  Write-Host 'bootstrap: step 1/3, Lazy! install'
  & nvim --headless '+Lazy! install' +qa
  if ($LASTEXITCODE -ne 0) { Write-Error "bootstrap: Lazy! install failed (exit $LASTEXITCODE)"; exit 1 }
  Copy-Item -LiteralPath $orig -Destination $lock -Force

  Write-Host 'bootstrap: step 2/3, Lazy! restore'
  & nvim --headless '+Lazy! restore' +qa
  if ($LASTEXITCODE -ne 0) { Write-Error "bootstrap: Lazy! restore failed (exit $LASTEXITCODE)"; exit 1 }

  Write-Host 'bootstrap: step 3/3, treesitter parsers and Mason tools (LazyVim downloads them lazily on a first start)'
  $prov = (Join-Path $repo 'scripts\provision.lua') -replace '\\', '/'
  & nvim --headless "+luafile $prov" +qa
  if ($LASTEXITCODE -ne 0) { Write-Error "bootstrap: provision.lua failed (exit $LASTEXITCODE)"; exit 1 }

  # compared by hash of the bytes: core.autocrlf=true can rewrite the line endings of the checkout
  if ((Get-FileHash -LiteralPath $lock -Algorithm SHA256).Hash -eq $origHash) {
    Write-Host 'bootstrap: done, lazy-lock.json unchanged.'
  } else {
    [Console]::Error.WriteLine('bootstrap: lazy-lock.json changed during restore (some plugin is not on its pinned commit).')
    Copy-Item -LiteralPath $orig -Destination $lock -Force
    exit 1
  }
} finally {
  Remove-Item -LiteralPath $orig -Force -ErrorAction SilentlyContinue
}
'''),
    ...para(r'#', r'Every native command is followed by an explicit LASTEXITCODE check, because PowerShell does not turn a failing program into an exception (the script sets ErrorActionPreference to Continue at the top and decides by itself what is fatal). Three small details are worth noting.'),
    blank,
    ...pt(r'#', r'Get-FileHash', r'the lockfile is compared by SHA-256 of its bytes. The comment gives the reason: core.autocrlf=true can rewrite line endings in a Windows checkout, so a text comparison would see changes that are not changes. The repository also pins line endings in .gitattributes, see that page.'),
    ...pt(r'#', r'forward slashes for luafile', r'the provision.lua path has its backslashes replaced with / before it goes into the +luafile argument, so the Ex command does not read them as escapes.'),
    ...pt(r'#', r'try / finally', r'the temporary file made by GetTempFileName is removed in a finally block, the PowerShell equivalent of the EXIT trap in the shell version.'),
    ...sec(r'differences worth knowing'),
    ...pt(r'#', r'creation of the link', r'shell: refuse and explain. PowerShell: create a junction when the path is absent, refuse when it points elsewhere.'),
    ...pt(r'#', r'lockfile identity', r'shell: cmp. PowerShell: SHA-256 hash, because of CRLF conversion.'),
    ...pt(r'#', r'failure reporting', r'shell: set -e does most of it. PowerShell: explicit checks and Write-Error plus exit 1 after each nvim call.'),
    ...sec(r'how it is tested'),
    ...para(r'#', r'The portable script spec, tests/scripts-portable_spec.lua, was added in the same commit, and the Windows job in .github/workflows/platforms.yml runs the bootstrap and the suite on a windows-latest runner. Whether a given line works on a given PowerShell is therefore checked by CI, not by reading.'),
    blank,
    ...sec(r'history'),
    ...pt(r'#', r'ff1c8fa 2026-10-16', r'added with the platforms workflow and test.lua.'),
    ...pt(r'#', r'6524272 2026-10-21', r'the Windows run fixes (the .exe suffix and drive-letter case) touched the Lua modules and specs, not this file; the script itself has not changed since it was added.'),
  ],
);
