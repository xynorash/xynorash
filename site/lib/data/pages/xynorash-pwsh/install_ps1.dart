import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynorash-pwsh/install.ps1',
  lines: [
    cm('#', '──────────────────────────────────────────'),
    cm('#', r'install.ps1 — five steps from a bare Windows to the cockpit'),
    cm('#', r'tools, modules, fonts, config files, terminal; run it twice and nothing breaks'),
    cm('#', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'one-shot, re-runnable bootstrap for a Windows machine'),
    kv(r'language', r'PowerShell 7 (#Requires -Version 7), strict mode, errors stop'),
    kv(r'size', r'143 lines, 1 commit (added 13 seconds after the init commit)'),
    kv(r'steps', r'[1/5] tools · [2/5] modules · [3/5] fonts · [4/5] config · [5/5] terminal'),
    kv(r'touches', r'winget, CurrentUser modules, per-user fonts, profile dir, WT'),
    ...sec(r'why this file exists'),
    ...para('#', r'The init commit of this repository already contained a complete ' r'configuration: the theme, the profile, the fastfetch files and four ' r'font files. What it could not do was get any of it onto a second ' r'machine, because the configuration depends on four programs, two ' r'PowerShell modules, a Nerd Font and a terminal setting that nobody had ' r'installed yet. install.ps1 is the missing half. It was committed 13 ' r'seconds after the init commit (2026-06-07, 23:48:58 then 23:49:11), ' r'with a message that states the contract: install the tools, the ' r'modules and the fonts, copy the config files to the right place, ' r'configure Windows Terminal, and make every step idempotent so that it ' r'is "safe to re-run on any machine". That last sentence is the design. ' r'A bootstrap script is run in bad conditions: halfway through a failed ' r'network, on a machine that already has some of the tools, by someone ' r'who is not sure whether it ran. The script is written so that running ' r'it again is the answer to all of those.'),
    ...sec(r'the opening: say what is required, then fail loudly'),
    ...code('powershell', r'install.ps1 · lines 1-28', r'''
#Requires -Version 7
<#
.SYNOPSIS
    Bootstrap the XYNORASH PowerShell environment on any Windows machine.
.DESCRIPTION
    Installs all required tools (oh-my-posh, fastfetch, carapace, zoxide),
    PowerShell modules (Terminal-Icons, PSReadLine), JetBrainsMono NF fonts,
    and copies all config files to the correct locations.
    Run once per machine. Safe to re-run — all steps are idempotent.
.EXAMPLE
    Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
    .\install.ps1
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo       = $PSScriptRoot
$profileDir = Split-Path $PROFILE

function Write-Step($msg) { Write-Host "  -> $msg" -ForegroundColor Cyan    }
function Write-Ok($msg)   { Write-Host "  v  $msg" -ForegroundColor Green   }
function Write-Warn($msg) { Write-Host "  !  $msg" -ForegroundColor Yellow  }

Write-Host ""
Write-Host "  XYNORASH PowerShell Setup" -ForegroundColor Magenta
Write-Host "  ─────────────────────────────────────────" -ForegroundColor DarkMagenta
Write-Host ""'''),
    ...para('#', r'Four decisions are visible before any work begins.'),
    blank,
    ...pt('#', r'#Requires -Version 7', r'on Windows PowerShell 5.1 the script stops at line 1 with a clear ' r'message, before it has touched anything. The profile files use ' r'PowerShell 7 syntax (the ?. operator, the `e escape), so installing ' r'them under 5.1 would only leave a broken setup behind.'),
    ...pt('#', r'Set-StrictMode -Version Latest', r'reading a variable that was never set, or a property that does not ' r'exist, becomes an error instead of an empty value. The Windows ' r'Terminal step below is written around exactly this: it tests whether a ' r'property exists before reading it.'),
    ...pt('#', r'$ErrorActionPreference = ’Stop’', r'any PowerShell error ends the script. Combined with strict mode this ' r'is "fail closed": a half-configured machine is worse than a script ' r'that stopped and said where.'),
    ...pt('#', r'$repo = $PSScriptRoot', r'the script finds its own files relative to itself, so it works from ' r'any current directory, and it must be run as a file, not pasted into a ' r'console, since PSScriptRoot is empty there. $profileDir comes from ' r'Split-Path $PROFILE, so the install target follows the real PowerShell ' r'7 profile location, even if Documents is redirected.'),
    blank,
    ...para('#', r'The three small output functions use ASCII markers: an arrow for a ' r'step, a lowercase v for done, an exclamation mark for a warning. The ' r'installer’s output must be readable before the Nerd Font is installed, ' r'which is why the glyphs the rest of the project depends on are not ' r'used here. The banner uses box-drawing characters from the ordinary ' r'Unicode range, which every terminal font has. That is an inference ' r'from the choice of characters; the file does not comment on it.'),
    ...sec(r'step 1: tools'),
    ...code('powershell', r'install.ps1 · winget packages', r'''
# ── 1. winget packages ────────────────────────────────────────────────────────

$packages = @(
    @{ Id = 'JanDeDobbeleer.OhMyPosh'; Name = 'oh-my-posh' },
    @{ Id = 'Fastfetch-cli.Fastfetch'; Name = 'fastfetch'  },
    @{ Id = 'rsteube.Carapace';        Name = 'carapace'   },
    @{ Id = 'ajeetdsouza.zoxide';      Name = 'zoxide'     }
)

Write-Host "  [1/5] Tools" -ForegroundColor DarkCyan
foreach ($pkg in $packages) {
    $found = winget list --id $pkg.Id --exact 2>$null | Select-String $pkg.Id
    if ($found) {
        Write-Ok "$($pkg.Name) already installed"
    } else {
        Write-Step "Installing $($pkg.Name)..."
        winget install $pkg.Id --accept-source-agreements --accept-package-agreements --silent 2>&1 | Out-Null
        Write-Ok "$($pkg.Name) installed"
    }
}'''),
    ...para('#', r'The data is separated from the loop. Four tools live in an array of ' r'small hashtables, package id and display name, so adding a fifth tool ' r'is one line. The ids are winget’s: JanDeDobbeleer.OhMyPosh, ' r'Fastfetch-cli.Fastfetch, rsteube.Carapace and ajeetdsouza.zoxide. ' r'Idempotence here is a query. winget list --id X --exact asks whether ' r'the package is already installed, and the script only installs if the ' r'answer is empty. The agreement flags and --silent make the install ' r'non-interactive, so the script can run unattended. The weak point is ' r'on line 46. The install command’s output and errors are both discarded ' r'with 2>&1 | Out-Null, and the next line prints "installed" ' r'unconditionally. The script never reads the exit code of winget (a ' r'search for LASTEXITCODE finds nothing in any of the .ps1 files), and ' r'PowerShell does not turn a native program’s failure into an exception ' r'by itself. A failed download would still print a green line. The check ' r'that would fix it is one line after the install. Missing winget ' r'altogether is handled differently, and better: the command is not ' r'found, which is an error, and with the Stop preference the script ends ' r'there. The ids matter beyond this file. profile.ps1 searches the ' r'WinGet packages directory for carapace.exe in a path that matches ' r'rsteube, and for a folder matching Fastfetch*, when those tools are ' r'not yet on PATH. Those search patterns are the package ids from this ' r'array. As far as I understand winget, it names each package folder ' r'after its id, so the installer and the profile agree on a name without ' r'a shared constant.'),
    ...sec(r'step 2: modules'),
    ...code('powershell', r'install.ps1 · PowerShell modules', r'''
# ── 2. PowerShell modules ─────────────────────────────────────────────────────

Write-Host ""
Write-Host "  [2/5] PowerShell modules" -ForegroundColor DarkCyan
$modules = @('Terminal-Icons', 'PSReadLine')
foreach ($mod in $modules) {
    if (Get-Module -ListAvailable -Name $mod -ErrorAction SilentlyContinue) {
        Write-Ok "$mod already available"
    } else {
        Write-Step "Installing module $mod..."
        Install-Module $mod -Scope CurrentUser -Force -SkipPublisherCheck -ErrorAction Stop
        Write-Ok "$mod installed"
    }
}'''),
    ...para('#', r'The same shape as step 1, with the query and install written in ' r'PowerShell cmdlets. -Scope CurrentUser needs no administrator rights, ' r'and -Force with -SkipPublisherCheck keeps the call from stopping to ' r'ask. Here -ErrorAction Stop is written out explicitly, although the ' r'global preference already says it; the repetition is harmless. ' r'PSReadLine is on the list although PowerShell 7 bundles a copy, so for ' r'most users the check finds it and prints "already available". The ' r'entry matters only on a machine whose PSReadLine is missing or too old ' r'for HistoryAndPlugin, which profile.ps1 says needs 2.2 or newer. The ' r'check tests for presence, not for version, so an old copy still counts ' r'as available.'),
    ...sec(r'step 3: fonts'),
    ...code('powershell', r'install.ps1 · per-user font install', r'''
# ── 3. Fonts ──────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "  [3/5] Fonts" -ForegroundColor DarkCyan
$fontsDest = "$env:LOCALAPPDATA\Microsoft\Windows\Fonts"
$reg = 'HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'
New-Item -ItemType Directory -Force $fontsDest | Out-Null

foreach ($ttf in Get-ChildItem (Join-Path $repo 'fonts') -Filter '*.ttf') {
    $dest = Join-Path $fontsDest $ttf.Name
    if (Test-Path $dest) {
        Write-Ok "Font $($ttf.BaseName) already registered"
    } else {
        Copy-Item $ttf.FullName $dest -Force
        Set-ItemProperty $reg "$($ttf.BaseName) (TrueType)" $dest -ErrorAction SilentlyContinue
        Write-Ok "Font $($ttf.BaseName) installed"
    }
}'''),
    ...para('#', r'Windows installs fonts for all users by writing into the system fonts ' r'folder, which needs administrator rights. This script avoids that. It ' r'copies each .ttf into the user’s own fonts folder under LOCALAPPDATA ' r'and registers it with a value under HKCU, in the same Fonts key ' r'Windows reads for per-user fonts. No elevation is needed, which is why ' r'the whole installer can run as a normal user. Two details are easy to ' r'pass over. The registry value name is built from the file’s base name ' r'plus (TrueType); it is a label for the entry. The name that matters to ' r'Windows Terminal is the font’s internal family name, and that one can ' r'be read from the file itself. Opening the name table of each of the ' r'four files gives the same family name, JetBrainsMono NF (with styles ' r'Regular, Italic, Bold and Bold Italic), even though the files are ' r'called JetBrainsMonoNerdFont-*.ttf. That is the exact string ' r'install.ps1 later writes into Windows Terminal, and bundling the files ' r'guarantees that a font with exactly that family name exists. The ' r'repository does not say whether this was the reason for bundling them. ' r'The idempotence test is Test-Path on the destination file. That means ' r'"already registered" is a statement about the file, not the registry. ' r'The registry write has -ErrorAction SilentlyContinue, so if it failed ' r'once, a later run sees the copied file, prints "already registered" ' r'and never retries. It is a small hole in an otherwise careful design.'),
    ...sec(r'step 4: config files'),
    ...code('powershell', r'install.ps1 · copy into the profile directory', r'''
# ── 4. Config files ───────────────────────────────────────────────────────────

Write-Host ""
Write-Host "  [4/5] Config files  ->  $profileDir" -ForegroundColor DarkCyan
New-Item -ItemType Directory -Force $profileDir | Out-Null

foreach ($f in @('profile.ps1', 'Microsoft.PowerShell_profile.ps1', 'xynorash.omp.json')) {
    Copy-Item (Join-Path $repo $f) (Join-Path $profileDir $f) -Force
    Write-Ok $f
}

$ffDest = Join-Path $profileDir 'fastfetch'
New-Item -ItemType Directory -Force $ffDest | Out-Null
Copy-Item (Join-Path $repo 'fastfetch\*') $ffDest -Recurse -Force
Write-Ok 'fastfetch/'

$fontsDirDest = Join-Path $profileDir 'fonts'
New-Item -ItemType Directory -Force $fontsDirDest | Out-Null
Copy-Item (Join-Path $repo 'fonts\*') $fontsDirDest -Force
Write-Ok 'fonts/'
'''),
    ...para('#', r'Three files go straight into the profile directory (profile.ps1, ' r'Microsoft.PowerShell_profile.ps1, xynorash.omp.json), the fastfetch ' r'folder goes into a fastfetch subfolder, and the fonts are copied again ' r'into a fonts subfolder. The last copy is the one that explains the ' r'design. profile.ps1 has its own font bootstrap that looks for fonts ' r'beside the profile, so the profile directory ends up carrying ' r'everything it needs, as the README says in its Portability section. ' r'This step is a copy, not a link. That has an advantage here: the ' r'profile directory lives outside the repository, and a profile that ' r'depended on a link into a moved or deleted checkout would break the ' r'shell. The cost is that the repository and the live copy can diverge, ' r'and the direction of authority is one-way. The copies use -Force with ' r'no backup, so an existing Microsoft.PowerShell_profile.ps1 on the ' r'machine, or local edits to an earlier installed copy, are replaced ' r'without a trace. Compare how xyno-arch/install.sh treats the same ' r'problem: it moves a file it would overwrite to a .bak-timestamp name ' r'first. This installer chose the simpler path, and that makes ' r'"idempotent" mean "converges to the same end state", not "preserves ' r'what you did".'),
    ...sec(r'step 5: Windows Terminal'),
    ...code('powershell', r'install.ps1 · the terminal font', r'''
# ── 5. Windows Terminal ───────────────────────────────────────────────────────

Write-Host ""
Write-Host "  [5/5] Windows Terminal" -ForegroundColor DarkCyan
$wt = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
if (Test-Path $wt) {
    try {
        $s = Get-Content $wt -Raw | ConvertFrom-Json
        $alreadySet = ($s.profiles.defaults.PSObject.Properties.Name -contains 'font') -and
                      ($s.profiles.defaults.font.face -eq 'JetBrainsMono NF')
        if (-not $alreadySet) {
            if (-not ($s.profiles.defaults | Get-Member font -ErrorAction SilentlyContinue)) {
                $s.profiles.defaults | Add-Member -MemberType NoteProperty -Name font `
                    -Value ([PSCustomObject]@{ face = 'JetBrainsMono NF'; size = 11 }) -Force
            } else {
                $s.profiles.defaults.font.face = 'JetBrainsMono NF'
            }
            if (-not ($s.PSObject.Properties.Name -contains 'scrollToBottomOnInput')) {
                $s | Add-Member -MemberType NoteProperty -Name scrollToBottomOnInput -Value $true -Force
            }
            $s | ConvertTo-Json -Depth 20 | Set-Content $wt -Encoding UTF8
            Write-Ok "Font set to JetBrainsMono NF, scrollToBottomOnInput enabled"
        } else {
            Write-Ok "Windows Terminal already configured"
        }
    } catch {
        Write-Warn "Could not update Windows Terminal settings: $_"
    }
} else {
    Write-Warn "Windows Terminal not found — install it from the Microsoft Store, then re-run"
}'''),
    ...para('#', r'This is the most defensive block in the file, and it is clear why: it ' r'edits a file that belongs to another program and that the user ' r'probably also edits by hand.'),
    blank,
    ...pt('#', r'the path', r'the stable Windows Terminal package’s settings.json. If that file is ' r'missing the script warns and moves on (Preview builds and unpackaged ' r'installs keep their settings elsewhere, so they take the warning path, ' r'as far as I know).'),
    ...pt('#', r'the strict-mode dance', r'lines 114-115 test PSObject.Properties.Name for the font property ' r'before they read its face. With strict mode on, reading a missing ' r'property would throw; the -and short-circuit keeps that from ' r'happening. Line 123 does the same for scrollToBottomOnInput.'),
    ...pt('#', r'the write', r'parse with ConvertFrom-Json, add the font object (face and size 11) if ' r'absent or fix the face if present, write back with ConvertTo-Json ' r'-Depth 20. The depth matters: the default depth is shallower than a ' r'real settings file, and deeper objects would be silently flattened to ' r'strings.'),
    ...pt('#', r'the extra setting', r'scrollToBottomOnInput is turned on, which keeps the view at the prompt ' r'when typing. Only the installer does this, not the profile’s copy of ' r'the block.'),
    ...pt('#', r'the net', r'the whole thing is in a try, and the catch prints "Could not update ' r'Windows Terminal settings" with the error, so a failure becomes a ' r'warning, not an abort.'),
    blank,
    ...para('#', r'Round-tripping a settings file through ConvertTo-Json cannot reproduce ' r'comments or the author’s formatting, a trade for avoiding a ' r'hand-written JSON patcher. The profile.ps1 version of the same edit ' r'swallows failures silently; this one at least says what happened.'),
    ...sec(r'history'),
    ...pt('#', r'3690dee', r'2026-06-07 23:48:58, "init: core XYNORASH configuration": the ' r'configuration, no installer.'),
    ...pt('#', r'be3650d', r'23:49:11, "feat: add portable install.ps1 bootstrap": this file in its ' r'final 143 lines.'),
    ...pt('#', r'b7e4667', r'23:49:46, "feat: portable auto-install bootstrap": a merge of that ' r'commit back into main under the GitHub no-reply identity. Its body, ' r'"Adds install.ps1 — one-shot idempotent bootstrap for any Windows ' r'machine.", is the only extra text.'),
    blank,
    ...para('#', r'The file has not changed since. The fixes that followed (b9d3efd and ' r'its merge 791cf8c) touched profile.ps1 and the theme. The defects ' r'found next were in the profile (an assumption that a freshly installed ' r'tool is on PATH) and in a battery template, not in the installer.'),
    ...sec(r'what is not covered'),
    ...pt('#', r'Windows PowerShell 5.1', r'rejected by #Requires; the 5.1 profile directory is never configured.'),
    ...pt('#', r'Exit codes', r'winget failures are invisible (above).'),
    ...pt('#', r'Unusual terminals', r'Preview or unpackaged Windows Terminal, other terminals; only the ' r'stable package path is known to the script.'),
    ...pt('#', r'Overwrites', r'existing profile files are replaced with -Force and no backup.'),
    ...pt('#', r'A fully offline machine', r'nothing is cached; every tool comes from winget and the module ' r'gallery.'),
    ...pt('#', r'Tests', r'none. The script’s guarantees are read off its structure, and the ' r'commit message’s claim of idempotence has not been checked by a second ' r'run recorded anywhere in the repository.'),
    ...sec(r'what it teaches'),
    ...pt('#', r'query, then act', r'every step asks whether the work is done before doing it; that is what ' r'makes running it twice safe.'),
    ...pt('#', r'put the risk where it can be seen', r'the risky edit (another program’s settings) is the one wrapped in a ' r'try with a visible warning.'),
    ...pt('#', r'fail closed', r'strict mode and the Stop preference turn a typo into an error at the ' r'line that caused it.'),
    ...pt('#', r'state the contract in the header', r'the .SYNOPSIS block says what it installs and that it is safe to ' r're-run, and the body is structured to be able to keep that promise.'),
    link(r'→ github.com/XNash/xynorash-pwsh', r'https://github.com/XNash/xynorash-pwsh'),
  ],
);
