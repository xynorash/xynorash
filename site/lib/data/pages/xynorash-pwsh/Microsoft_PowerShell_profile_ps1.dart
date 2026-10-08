import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynorash-pwsh/Microsoft.PowerShell_profile.ps1',
  lines: [
    cm('#', '──────────────────────────────────────────'),
    cm('#', r'Microsoft.PowerShell_profile.ps1 — the base layer'),
    cm('#', r'Chris Titus Tech’s profile, re-coloured and pointed at the XYNORASH theme'),
    cm('#', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'the base profile: shell habits, aliases and the hook for the theme'),
    kv(r'origin', r'Chris Titus Tech’s PowerShell profile (credited on line 1)'),
    kv(r'language', r'PowerShell 7'),
    kv(r'size', r'194 lines, 1 commit (unchanged since init)'),
    kv(r'loaded', r'second, after profile.ps1'),
    kv(r'what is Nash’s', r'the palette, the theme path, the layering around it'),
    ...sec(r'why this file exists, and whose it is'),
    ...para('#', r'The first line of this file is a credit: "Chris Titus Tech’s ' r'PowerShell profile". The Update-Profile function in it points at ' r'github.com/ChrisTitusTech/powershell-profile, which is where the file ' r'comes from. It supplies what a fresh PowerShell lacks: a set of short ' r'commands for files, processes and git, a better key map for ' r'PSReadLine, zoxide and Terminal-Icons. This project did not write that ' r'toolbox, and the page will not pretend otherwise. What this repository ' r'adds sits around it, and the interesting question is how it is ' r'attached. The evidence for what was customised is thin, because the ' r'history is a single commit with the file already in its final form. ' r'Two things are visibly the project’s: the colour values, which are the ' r'XYNORASH palette (they match xynorash.omp.json and ' r'fastfetch/config.jsonc), and the theme path, which names ' r'xynorash.omp.json. Everything else could be the original; the ' r'repository cannot tell. The file is named ' r'Microsoft.PowerShell_profile.ps1 because that is the name PowerShell 7 ' r'gives to the current-user, current-host profile. install.ps1 copies it ' r'into the directory that contains $PROFILE, which is how it comes to ' r'run at all.'),
    ...sec(r'the layering'),
    ...code('powershell', r'Microsoft.PowerShell_profile.ps1 · lines 1-9', r'''
### Chris Titus Tech's PowerShell profile

if (Get-Command 'Get-Theme_Override' -ErrorAction SilentlyContinue) {
    Get-Theme_Override
} else {
    oh-my-posh init pwsh --config (Join-Path (Split-Path $PROFILE) "xynorash.omp.json") | Invoke-Expression
}
zoxide init --cmd z powershell | Out-String | Invoke-Expression
Import-Module -Name Terminal-Icons'''),
    ...para('#', r'Three files cooperate, in a fixed order. profile.ps1 loads first and ' r'defines a function called Get-Theme_Override. This file loads second ' r'and, on lines 3-7, asks whether that function exists. If it does, the ' r'function runs and the full cockpit is built. If it does not, the else ' r'branch initialises oh-my-posh directly with the same ' r'xynorash.omp.json. Either way the theme on screen is the same. A ' r'reason for splitting the work this way is visible in a function ' r'further down. Update-Profile downloads the upstream version of this ' r'file straight over $Profile. Anything edited here is one command away ' r'from being overwritten. Putting the project’s own code in profile.ps1, ' r'which upstream never touches, means the base can be refreshed whenever ' r'the author likes and the cockpit survives. That is the likely purpose ' r'of the hook. The fallback branch also shows how the design degrades. ' r'Without profile.ps1 the wrapper never runs, so none of the XYNO_ ' r'variables exist. Every vitals segment in the theme is guarded by an if ' r'env test, so those segments render nothing, and the prompt keeps its ' r'first line, the RAM and battery chips, and the timing line. The ' r'failure mode of a missing layer is a smaller prompt, not a broken one. ' r'This follows from reading the two files together; it was not observed ' r'running.'),
    ...sec(r'zoxide and Terminal-Icons'),
    ...para('#', r'Lines 8 and 9 start two things. zoxide init defines the z command (the ' r'name comes from --cmd z) and its interactive variant zi, and learns ' r'directories as you use them. Terminal-Icons adds file-type icons to ' r'directory listings, and it is the reason the Nerd Font matters outside ' r'the prompt. Unlike profile.ps1, neither line is guarded. If zoxide or ' r'the module is missing, every shell start prints an error. The ' r'discipline of "look before you use" that profile.ps1 follows ' r'everywhere does not extend here, and the reason is probably that this ' r'is inherited code written for a machine on which install steps have ' r'run. install.ps1 is what makes that assumption true: it installs ' r'zoxide through winget and Terminal-Icons from the gallery before the ' r'profile ever runs.'),
    ...sec(r'colours, and which file wins'),
    ...code('powershell', r'Microsoft.PowerShell_profile.ps1 · PSReadLine colours', r'''
# History & Colors
Set-PSReadLineOption -PredictionViewStyle ListView -Colors @{
    Command   = '#00E5FF'
    Parameter = '#00E5AA'
    Operator  = '#FFAA00'
    Variable  = '#AA00FF'
    String    = '#FFC832'
    Number    = '#FF6432'
    Type      = '#EE00EE'
    Comment   = '#444466'
    Keyword   = '#FF3296'
    Error     = '#FF6432'
}'''),
    ...para('#', r'These ten values are the XYNORASH palette applied to syntax ' r'highlighting: commands in cyan, parameters in mint, strings in yellow, ' r'numbers in orange, keywords in pink, errors in orange (they reuse the ' r'orange of numbers). The same hexadecimal values appear as foreground ' r'colours in xynorash.omp.json, so what you type and the prompt above it ' r'share one palette. profile.ps1 sets the same ten keys earlier (its ' r'lines 46-58, under a comment that wrongly calls them Catppuccin Mocha ' r'and claims they override this file). Since this file runs second and ' r'Set-PSReadLineOption -Colors replaces per key, these values are the ' r'active ones, and nine of the ten differ from the earlier block. In ' r'practice this is the file where the editing colours are decided. The ' r'ListView prediction style set on line 14 is also here; the prediction ' r'source, HistoryAndPlugin, is set in profile.ps1 and the two settings ' r'combine.'),
    ...sec(r'keys'),
    ...code('powershell', r'Microsoft.PowerShell_profile.ps1 · key bindings', r'''
#KeyBinds
Set-PSReadLineKeyHandler -Key UpArrow -Function HistorySearchBackward
Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward
Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete
Set-PSReadLineKeyHandler -Chord 'Ctrl+d' -Function DeleteChar
Set-PSReadLineKeyHandler -Chord 'Ctrl+w' -Function BackwardDeleteWord
Set-PSReadLineKeyHandler -Chord 'Alt+d' -Function DeleteWord
Set-PSReadLineKeyHandler -Chord 'Ctrl+LeftArrow' -Function BackwardWord
Set-PSReadLineKeyHandler -Chord 'Ctrl+RightArrow' -Function ForwardWord
Set-PSReadLineKeyHandler -Chord 'Ctrl+z' -Function Undo
Set-PSReadLineKeyHandler -Chord 'Ctrl+y' -Function Redo'''),
    ...pt('#', r'Up and Down', r'HistorySearchBackward and Forward: they search history for commands ' r'that start with what is already typed, instead of stepping through ' r'everything. Type "git" and press Up to cycle through earlier git ' r'commands.'),
    ...pt('#', r'Tab', r'MenuComplete shows candidates as a navigable menu rather than cycling ' r'through them one at a time. Together with carapace, which attaches ' r'descriptions to flags and subcommands, this is what makes completion ' r'browsable.'),
    ...pt('#', r'Ctrl+d, Ctrl+w, Alt+d', r'delete the character, the word before the cursor and the word after ' r'it, which are the readline habits from other shells.'),
    ...pt('#', r'Ctrl+Left and Ctrl+Right', r'move by word.'),
    ...pt('#', r'Ctrl+z and Ctrl+y', r'undo and redo while editing a line.'),
    blank,
    ...para('#', r'profile.ps1 adds one more binding, Shift+Enter for a newline that does ' r'not submit. Together they make PSReadLine behave closer to an editor.'),
    ...sec(r'the update function, and a trust boundary'),
    ...code('powershell', r'Microsoft.PowerShell_profile.ps1 · Update-Profile and the WinUtil launchers', r'''
# Functions
function Update-Profile {
    Invoke-WebRequest -Uri https://github.com/ChrisTitusTech/powershell-profile/raw/main/Microsoft.PowerShell_profile.ps1 -OutFile $Profile
    Write-Host "Updated PowerShell Profile" -ForegroundColor Green
}
...
function winutil {
    Invoke-RestMethod https://christitus.com/win | Invoke-Expression
}

function winutildev {
    Invoke-RestMethod https://christitus.com/windev | Invoke-Expression
}'''),
    ...para('#', r'Update-Profile is the reason for the layering, and it is also the ' r'sharpest edge in the file: it overwrites the customised copy with the ' r'upstream copy, taking the project’s palette and its fallback theme ' r'path with it. Re-running install.ps1 restores them, because the ' r'installer copies this file from the repository with -Force. The ' r'cockpit itself keeps working throughout, since the hook lives in ' r'profile.ps1. The two launchers below it, winutil and winutildev, ' r'download a script from christitus.com and run it with ' r'Invoke-Expression. Counting every use of that cmdlet across the ' r'repository gives six: four evaluate the output of a locally installed ' r'binary (oh-my-posh in two places, zoxide, carapace), and two evaluate ' r'code fetched from the network. The first four are the documented way ' r'those tools start. The last two are a deliberate convenience that ' r'trusts the remote host on every call, which is worth knowing before ' r'typing them.'),
    ...sec(r'file and directory utilities'),
    ...code('powershell', r'Microsoft.PowerShell_profile.ps1 · touch, mkcd and trash', r'''
# File / Directory Utilities
function touch ($File) {
    if (Test-Path $File) {
        (Get-Item $File).LastWriteTime = Get-Date
    } else {
        New-Item $File -ItemType File | Out-Null
    }
}

function mkcd ($Path) {
    New-Item -Path $Path -ItemType Directory -Force | Out-Null
    Set-Location -Path $Path
}

function trash ($Path) {
    if (Test-Path $Path -PathType Container) {
        [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory($Path,'OnlyErrorDialogs','SendToRecycleBin')
    } else {
        [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($Path,'OnlyErrorDialogs','SendToRecycleBin')
    }
}'''),
    ...para('#', r'Each function replaces a Unix command that is awkward in PowerShell, ' r'and each makes one decision worth noting.'),
    blank,
    ...pt('#', r'touch', r'updates the timestamp if the file exists, otherwise creates it empty. ' r'Out-Null keeps the creation from printing a file listing.'),
    ...pt('#', r'mkcd', r'creates a directory and enters it. The -Force on New-Item makes it ' r'succeed when the directory already exists, so it works as "go there, ' r'making it if needed".'),
    ...pt('#', r'trash', r'moves to the Recycle Bin through the VisualBasic FileSystem API, with ' r'a different method for directories and for files. It is the only ' r'function that deletes anything, and the deletion is reversible; it is ' r'not listed in Show-Help.'),
    ...pt('#', r'ff', r'recursive file search by name, printing full paths.'),
    ...pt('#', r'head', r'always ten lines. The parameter list has no count, so there is no way ' r'to ask for another number.'),
    ...pt('#', r'sed', r'a literal find-and-replace over a file. The name promises more than ' r'the body does: Replace is a plain string replace, not a regular ' r'expression, and the file is read whole and rewritten.'),
    ...pt('#', r'which', r'prints the Source of a command.'),
    ...pt('#', r'pgrep, pkill, k9', r'find a process by name, stop it with -Force, and the shorter name for ' r'the second.'),
    ...sec(r'git shortcuts'),
    ...code('powershell', r'Microsoft.PowerShell_profile.ps1 · git shortcuts', r'''
# Git Shortcuts
function gs { git status }
function ga { git add . }
function gp { git push }
function gpush { git push }
function gpull { git pull }
function gcl { git clone $args }
function g { __zoxide_z github }

function gcom {
    git add .
    git commit -m "$args"
}

function lazyg {
    git add .
    git commit -m "$args"
    git push
}

function docs {
    Set-Location -Path ([Environment]::GetFolderPath("MyDocuments"))
}'''),
    ...para('#', r'The group is deliberately small and covers the most common path: ' r'status, add everything, commit, push, pull, clone. g jumps to a ' r'directory by asking zoxide for the best match to "github": it calls ' r'zoxide’s internal function __zoxide_z, so it only works once zoxide ' r'has seen such a directory and only if the init on line 8 ran. lazyg is ' r'the one worth a warning. It runs add, commit and push as three ' r'consecutive statements. In a PowerShell function a failing native ' r'command does not stop the next statement, so a commit that fails ' r'(nothing to commit, a hook rejects it) is followed by a push anyway. ' r'The message is joined from $args without quotes, so lazyg fix the ' r'thing works without quoting the message. gp and gpush are synonyms, ' r'and ga is git add . - all of it, which is the right choice for a ' r'personal repository and a poor one in a shared tree.'),
    ...sec(r'uptime'),
    ...para('#', r'The profile defines its own uptime command on lines 96-98. It builds a ' r'time span from the current date minus a value read from Get-CimClass ' r'on Win32_OperatingSystem. Read closely this looks wrong: Get-CimClass ' r'returns the class definition, not an instance, and the boot time is a ' r'property of the instance, which Get-CimInstance returns. If so the ' r'command prints nothing meaningful. This is a reading, not an ' r'observation. It is worth checking, and it would also be easy to fix. ' r'The prompt does not depend on it: the vitals line computes its own ' r'uptime from TickCount64 in profile.ps1.'),
    ...sec(r'the help screen'),
    ...code('powershell', r'Microsoft.PowerShell_profile.ps1 · Show-Help (first lines)', r'''
function Show-Help {
    $title    = $PSStyle.Foreground.BrightMagenta
    $section  = $PSStyle.Foreground.BrightBlue
    $command  = $PSStyle.Foreground.BrightGreen
    $desc     = $PSStyle.Foreground.BrightWhite
    $accent   = $PSStyle.Foreground.BrightYellow
    $dim      = $PSStyle.Foreground.BrightBlack
    $reset    = $PSStyle.Reset

    Write-Host @"
${title}󰘳 PowerShell Profile Help${reset}
${dim}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${reset}

${section}󰊢 Update${reset}
  ${command}Update-Profile${reset}  ${accent}→${reset} ${desc}Updates the profile from a remote repository.${reset}

${section}󰊢 Git Shortcuts${reset}
${dim}────────────────────────────────────────────────────${reset}
  ${command}g${reset}                  ${accent}→${reset} ${desc}Changes to the GitHub directory${reset}
  ${command}ga${reset}                 ${accent}→${reset} ${desc}git add .${reset}'''),
    ...para('#', r'Show-Help is a small piece of design in the same visual language as ' r'the prompt. It takes six colours from the $PSStyle table, puts them in ' r'variables with role names (title, section, command, desc, accent, dim) ' r'and writes the whole screen as one here-string that interpolates them. ' r'Naming colours by role means the screen can be recoloured by changing ' r'six lines. xynorash.omp.json does the opposite and repeats hex ' r'literals; cyan alone appears 32 times. Two gaps are visible in the ' r'help text itself. It does not list trash or la, and five of the lines ' r'(grep, k9, pgrep, pkill and unzip) are indented four spaces where the ' r'others use two, so the columns drift. They are cosmetic, and they show ' r'that the help is maintained by hand next to the functions it ' r'describes, not generated from them.'),
    ...sec(r'limits'),
    ...pt('#', r'Inherited unevenly', r'nothing in the repository marks which parts are upstream and which are ' r'edited, because the history begins with the file in its final state. A ' r'diff against upstream is the only way to separate them.'),
    ...pt('#', r'Unguarded dependencies', r'zoxide, Terminal-Icons and oh-my-posh are called without existence ' r'checks; they rely on install.ps1 having run.'),
    ...pt('#', r'Overwrite risk', r'Update-Profile replaces the whole file.'),
    ...pt('#', r'Remote execution', r'winutil and winutildev trust a remote script on every call.'),
    ...pt('#', r'Hand-maintained helpers', r'uptime (above) and the help text are kept by hand and have drifted ' r'from what the functions do.'),
    ...pt('#', r'No tests', r'like the rest of the repository, this file is exercised only by using ' r'it.'),
    ...sec(r'what it teaches'),
    ...para('#', r'The useful lesson is architectural, and it is visible in three lines ' r'at the top. A configuration that wraps someone else’s work should plug ' r'in at the one point they provide, not edit their file. The profile you ' r'can refresh from upstream and the layer you own are then two different ' r'files, and the cost of that choice is a hook name (Get-Theme_Override) ' r'that both files must agree on.'),
    link(r'→ github.com/ChrisTitusTech/powershell-profile', r'https://github.com/ChrisTitusTech/powershell-profile'),
    link(r'→ github.com/XNash/xynorash-pwsh', r'https://github.com/XNash/xynorash-pwsh'),
  ],
);
