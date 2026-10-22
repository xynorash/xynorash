import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynorash-pwsh/README.md',
  summary: 'A neon three-line PowerShell cockpit: oh-my-posh theme, live vitals, carapace completion, one-command install',
  repo: 'xynorash-pwsh',
  fallbackStars: 0,
  fallbackPushed: '2026-06-07',
  lines: [
    heading('# XYNORASH PowerShell'),
    blank,
    ...text(r'A terminal environment for PowerShell 7 on Windows. Every prompt is three lines: who and where you are, a line of live machine vitals, and the line you type on. After you press Enter the whole block collapses to a single symbol so the scrollback stays readable. The repository holds no compiled code: it is one oh-my-posh theme, two PowerShell profiles, a fastfetch banner, a bundled Nerd Font and an installer that puts it all where PowerShell looks.'),
    blank,
    kv(r'language', r'PowerShell 7 · JSON (oh-my-posh theme) · JSONC (fastfetch)'),
    kv(r'platform', r'Windows 10/11, PowerShell 7+, Windows Terminal recommended'),
    kv(r'files', r'8 text files and 4 fonts; 912 lines added in the first commit'),
    kv(r'history', r'5 commits, all on 2026-06-07 between 23:48 and 23:53 (+0300)'),
    kv(r'tests', r'none; the repository has no spec files and no CI'),
    kv(r'licence', r'none in the tree'),
    kv(r'pages', r'one per source file, listed in the tour below'),

    ...sec(r'what you are looking at'),
    ...text(r'This is a dotfiles repository for a shell, written to be cloned and installed in one step. The idea fits in a sentence: make the terminal feel like a cockpit instead of a blank line. Everything that makes it feel that way is configuration, so the interesting questions are about how the pieces are layered, which piece owns which job, and what happens when a piece is missing. This page tours the tree, then the install flow, then the three designs that carry the project: the prompt, the vitals and the completion.'),
    blank,
    ...text(r'The upstream README, which this page does not repeat, lists the features as bullet points: a three-line prompt, a palette of neon cyan, magenta, amber and green on near-black, live vitals, git status, a transient prompt, admin and SSH indicators, carapace completions, language runtimes and fastfetch. Each of those is checked against the code below, and where the code says something different the code wins.'),

    ...sec(r'the tree'),
    ...text(r'git ls-files lists 12 tracked paths:'),
    blank,
    plain(r'  .gitignore'),
    plain(r'  Microsoft.PowerShell_profile.ps1'),
    plain(r'  README.md'),
    plain(r'  fastfetch/config.jsonc'),
    plain(r'  fastfetch/xynorash.txt'),
    plain(r'  fonts/JetBrainsMonoNerdFont-Bold.ttf'),
    plain(r'  fonts/JetBrainsMonoNerdFont-BoldItalic.ttf'),
    plain(r'  fonts/JetBrainsMonoNerdFont-Italic.ttf'),
    plain(r'  fonts/JetBrainsMonoNerdFont-Regular.ttf'),
    plain(r'  install.ps1'),
    plain(r'  profile.ps1'),
    plain(r'  xynorash.omp.json'),
    blank,
    ...text(r'Read the tree as four layers. The installer (install.ps1) runs once and only copies. The two profiles run on every shell start: Microsoft.PowerShell_profile.ps1 is the base and profile.ps1 is the project’s own logic. The theme (xynorash.omp.json) is data that oh-my-posh renders. The banner (fastfetch/config.jsonc and xynorash.txt) is data that fastfetch renders. The fonts are payload, so that the glyphs the theme draws with exist on the machine. .gitignore is four lines.'),
    blank,
    ...bullet(r'install.ps1', r'143 lines. Installs four winget packages and two PowerShell modules, registers four fonts, copies the configuration, patches Windows Terminal. Its page walks the five steps.'),
    ...bullet(r'profile.ps1', r'121 lines. The theme hook, the vitals wrapper, syntax colours, prediction, carapace, fonts and the banner. Loaded first.'),
    ...bullet(r'Microsoft.PowerShell_profile.ps1', r'194 lines. The base layer, credited in its first line to Chris Titus Tech. Aliases, key handlers, utilities, and the call that hands control to the theme hook.'),
    ...bullet(r'xynorash.omp.json', r'374 lines. Three blocks, 50 segments, the palette and the transient prompt.'),
    ...bullet(r'fastfetch/config.jsonc', r'131 lines. The module list and colours of the banner.'),
    ...bullet(r'fastfetch/xynorash.txt', r'32 lines of 24-bit-colour ASCII art, 13,087 bytes.'),
    ...bullet(r'fonts/', r'four JetBrainsMono Nerd Font weights: Regular, Bold, Italic, BoldItalic.'),

    ...sec(r'the install flow'),
    ...text(r'The README’s quick start is three commands. The first lifts the execution policy for the current user, because a freshly installed Windows refuses to run unsigned scripts. The second and third are a clone and a run.'),
    ...code('powershell', r'README.md · lines 18-26', r'''
# Allow script execution (once per machine)
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser

# Clone and run
git clone https://github.com/XNash/xynorash-pwsh.git
cd xynorash-pwsh
.\install.ps1
```

Open a new PowerShell tab. Done.'''),
    ...text(r'install.ps1 does not install from the network what it can ship. It ships the fonts as files in the clone and installs the tools through winget, by exact package id, so that re-running the script does not reinstall anything. The package table is the first thing the script declares.'),
    ...code('powershell', r'install.ps1 · lines 32-37, the four tools', r'''
$packages = @(
    @{ Id = 'JanDeDobbeleer.OhMyPosh'; Name = 'oh-my-posh' },
    @{ Id = 'Fastfetch-cli.Fastfetch'; Name = 'fastfetch'  },
    @{ Id = 'rsteube.Carapace';        Name = 'carapace'   },
    @{ Id = 'ajeetdsouza.zoxide';      Name = 'zoxide'     }
)'''),
    ...text(r'The script then walks five numbered steps, each printed as a heading in the output: tools, PowerShell modules (Terminal-Icons and PSReadLine), fonts, config files and Windows Terminal. The copy step is the one that defines the architecture of the whole repository, because it fixes where every file ends up.'),
    ...code('powershell', r'install.ps1 · lines 91-104, what lands in the profile directory', r'''
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
    ...text(r'Three things follow. The installer copies, it does not link, so editing the repository after install changes nothing until the script is run again. Everything lands in one directory, Split-Path $PROFILE, and the profiles find their neighbours with the same expression, which is why the README can say the setup is self-contained. And the fonts are copied twice: once into the per-user Windows font directory and once into the profile directory, which is the directory profile.ps1 looks in for its own font bootstrap.'),
    ...text(r'The last step edits Windows Terminal’s settings.json. It sets the font face to JetBrainsMono NF and, if the key is missing, enables scrollToBottomOnInput. The edit is guarded and idempotent, and a failure is a warning rather than an abort.'),
    ...code('powershell', r'install.ps1 · lines 128-136', r'''
        } else {
            Write-Ok "Windows Terminal already configured"
        }
    } catch {
        Write-Warn "Could not update Windows Terminal settings: $_"
    }
} else {
    Write-Warn "Windows Terminal not found — install it from the Microsoft Store, then re-run"
}'''),

    ...sec(r'load order: who calls whom'),
    ...text(r'PowerShell 7 reads the all-hosts profile (profile.ps1) before the current-host profile (Microsoft.PowerShell_profile.ps1). The project uses that order as a plug-in mechanism. The base profile, written by someone else, asks one question: does a command named Get-Theme_Override exist? The project’s profile defines it. No line of the base has to be changed to add the cockpit.'),
    ...code('powershell', r'Microsoft.PowerShell_profile.ps1 · lines 3-9', r'''
if (Get-Command 'Get-Theme_Override' -ErrorAction SilentlyContinue) {
    Get-Theme_Override
} else {
    oh-my-posh init pwsh --config (Join-Path (Split-Path $PROFILE) "xynorash.omp.json") | Invoke-Expression
}
zoxide init --cmd z powershell | Out-String | Invoke-Expression
Import-Module -Name Terminal-Icons'''),
    ...text(r'Note the else branch. In the copy of the base profile that this repository ships, the fallback is also the XYNORASH theme. The comment at the top of profile.ps1 still says that the fallback is cobalt2, which does not match the fallback in the copy shipped here. The behaviour is right; the comment is stale. The pages for the two profiles go into the details.'),

    ...sec(r'the prompt design'),
    ...text(r'The theme is xynorash.omp.json, an oh-my-posh configuration at schema version 4. Its top-level switches say what kind of prompt it is.'),
    ...code('json', r'xynorash.omp.json · lines 3-7', r'''
  "version": 4,
  "final_space": true,
  "blank_line_before_prompt": true,
  "disable_notice": true,
  "shell_integration": true,'''),
    ...text(r'Then come three blocks, each a left-aligned prompt; the second and third carry "newline": true, which is what stacks them into three lines. The first block draws the box corner and the identity. The second draws a vertical bar, the language runtimes and the vitals. The third draws the closing corner, the command duration, the clock and the prompt symbol. The box-drawing characters at the left edge of each line make the three lines read as one frame.'),
    blank,
    ...bullet(r'block 1, identity and location', r'5 segments: os (the Windows glyph is the only icon configured), session, path, git, and a dim separator. The path segment uses the agnoster_short style with a maximum depth of 3 and a truncation symbol, so a deep directory does not eat the line.'),
    ...bullet(r'block 2, runtimes and vitals', r'41 segments. 32 are language detectors (rust, java, dotnet, flutter, dart, node, python, go and 24 more, ending in bazel and buf); one is the vertical bar and the other eight are CPU, memory, two disks, battery, uptime, IP and process count.'),
    ...bullet(r'block 3, input line', r'4 segments: the closing corner, executiontime with a threshold of 500 ms, the time, and the exit symbol.'),
    blank,
    ...text(r'The git segment is the most elaborate template in the file. Its colour changes with the repository state through foreground_templates, and its text is assembled from optional pieces, each printed only when its number is above zero.'),
    ...code('json', r'xynorash.omp.json · lines 52-55, git colour by state', r'''
          "foreground_templates": [
            "{{ if gt .Working.Changed 0 }}#FFAA00{{ end }}",
            "{{ if and (eq .Working.Changed 0) (gt .Staging.Changed 0) }}#00E5AA{{ end }}"
          ],'''),
    ...text(r'Read the logic: amber when there are working-tree changes, green when the tree is clean but something is staged, and the default purple otherwise. Inside the template, ahead and behind show as arrows, modified files as ~N, staged files as +N, untracked files as ?N and stashes as a count with a glyph. Every piece is hidden at zero, so a clean repository shows only the branch.'),
    ...text(r'The session segment carries the two indicators the upstream README calls “shown only when relevant”.'),
    ...code('json', r'xynorash.omp.json · line 34, SSH and admin indicators', r'''
          "template": "{{ if env \"SSH_CLIENT\" }}<#FFAA00>󰢩 </>{{ end }}<#FF3296>{{ .UserName }}</>{{ if env \"XYNO_IS_ADMIN\" }}<#FF4488> 󰒃</>{{ end }}<#555>@</>{{ .HostName }} "'''),
    ...text(r'The SSH marker keys on the SSH_CLIENT environment variable, set by the OpenSSH server. The admin marker keys on XYNO_IS_ADMIN, which is not a Windows variable at all: it is set once by profile.ps1. That is the seam between the two files, and it is the pattern used for every dynamic value below.'),

    ...sec(r'the transient prompt'),
    ...text(r'A three-line cockpit is helpful when you are about to type and a nuisance in the scrollback. The theme asks oh-my-posh for a transient prompt, which redraws the previous prompt in a short form once a command has been submitted.'),
    ...code('json', r'xynorash.omp.json · lines 8-15', r'''
  "transient_prompt": {
    "foreground": "#00E5AA",
    "foreground_templates": [
      "{{ if gt .Code 0 }}#FF6432{{ end }}"
    ],
    "background": "transparent",
    "template": "{{ if gt .Code 0 }}✗{{ else }}❯{{ end }} "
  },'''),
    ...text(r'The collapsed prompt is one symbol: a green chevron for success and an orange cross for a non-zero exit code. The live third line of the cockpit uses the same test with the same two colours (lines 363-366), so the finished history reads as a column of chevrons with the failures marked. For the transient prompt to work in PowerShell, oh-my-posh needs a key handler on Enter; profile.ps1 enables it with Enable-KeyHandlers on the line after the init, which is the reason the hook does not just call oh-my-posh init and stop.'),

    ...sec(r'the vitals design'),
    ...text(r'The second line shows CPU, memory, two disks, battery, uptime, IP address and process count. Two of these (memory and battery) come from oh-my-posh’s own segments. The other six are text segments that print an environment variable, and profile.ps1 is what fills them. The theme and the profile never call each other; they meet in the environment.'),
    ...code('json', r'xynorash.omp.json · lines 272-277, a vitals segment', r'''
        {
          "type": "text",
          "style": "plain",
          "foreground": "#FFAA00",
          "template": "{{ if env \"XYNO_CPU\" }} 󰍛 {{ env \"XYNO_CPU\" }}% ▸{{ end }}"
        },'''),
    ...text(r'The template is guarded with if env, so before the variable exists the segment prints nothing rather than a half-drawn label. This is what makes the theme safe to load on a machine that does not have profile.ps1: the line shows the memory and battery segments and the language detectors, and the six custom vitals are simply absent.'),
    ...text(r'The numbers come from a wrapper around the prompt function. The wrapper keeps a counter and uses it to spread the costs: the CPU reading, the uptime arithmetic and the process count run every prompt, disks every fifth prompt, the IP address every twentieth.'),
    ...code('powershell', r'profile.ps1 · lines 24-38, cadence by cost', r'''
            # Disk — refresh every 5 prompts
            if ($global:__xyno_n % 5 -eq 1) {
                $dc = Get-PSDrive C -ErrorAction SilentlyContinue
                if ($dc) { $env:XYNO_DISK_C = [math]::Round($dc.Used / ($dc.Used + $dc.Free) * 100) }
                $df = Get-PSDrive F -ErrorAction SilentlyContinue
                if ($df) { $env:XYNO_DISK_F = [math]::Round($df.Used / ($df.Used + $df.Free) * 100) }
            }
            # IP — refresh every 20 prompts
            if ($global:__xyno_n % 20 -eq 1) {
                try {
                    $env:XYNO_IP = (Get-NetIPAddress -AddressFamily IPv4 -Type Unicast -ErrorAction Stop |
                        Where-Object { $_.IPAddress -notmatch '^(127\.|169\.)' } |
                        Select-Object -First 1).IPAddress
                } catch { $env:XYNO_IP = '?' }
            }'''),
    ...text(r'The remainder is a rule of thumb made executable: a value that changes by the second is read every time, a value that changes by the hour is read when the counter says so. The modulo is tested against 1, so the first prompt after start reads everything immediately so every value exists from the first prompt. A missing drive F does not break the line, because the variable is only set when the drive exists and the segment is hidden without it. The IP lookup has the only try/catch in the wrapper and falls back to a question mark.'),
    ...text(r'The drive letters are the one place where the configuration is tied to its author’s machine: profile.ps1 reads drives C and F, and fastfetch/config.jsonc shows C:\ and F:\ with the same hard-coded folders. A machine without F: shows only C in the prompt, because the segment is hidden when the variable is unset.'),

    ...sec(r'the completion design'),
    ...text(r'There are two layers of completion. PSReadLine supplies prediction from history and from plugins, with the syntax colours the project overrides in the same file. Carapace supplies annotated completions for flags, subcommands and argument values of a very large number of command-line tools; the README’s “1000+” is the carapace project’s own claim, not something this repository measures.'),
    ...code('powershell', r'profile.ps1 · lines 63-74, locating carapace', r'''
# Carapace — annotated completions (flags, subcommands, argument values) for 1000+ CLI tools
$_carapace = (Get-Command carapace -ErrorAction SilentlyContinue)?.Source
if (-not $_carapace) {
    $_carapace = Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages" `
        -Recurse -Filter 'carapace.exe' -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -match 'rsteube' } |
        Select-Object -First 1 -ExpandProperty FullName
}
if ($_carapace) {
    $env:CARAPACE_BRIDGES = 'zsh,fish,bash'
    & $_carapace _carapace | Out-String | Invoke-Expression
}'''),
    ...text(r'The shape of this block is a lesson in why it was rewritten. In the first version, the two lines were an unconditional environment variable and a call to carapace, which fails on the first shell after winget installs it, because that shell’s PATH was captured before the install. The fix looks on PATH first, then falls back to the winget package directory, and only configures completion if something was found. The use of ?. means the file needs PowerShell 7, which the installer’s #Requires -Version 7 line already enforces.'),
    ...text(r'CARAPACE_BRIDGES asks carapace to borrow completers from zsh, fish and bash for commands it has no native definition for.'),

    ...sec(r'the banner'),
    ...text(r'The last thing profile.ps1 does is run fastfetch, but only in a real interactive console. The logo is a 32-line text file, read raw, so its ANSI escapes are passed through to the terminal.'),
    ...code('json', r'fastfetch/config.jsonc · lines 5-15', r'''
  "logo": {
    "type": "raw",
    "source": "xynorash.txt",
    "width": 150,
    "height": 32,
    "padding": {
      "top": 1,
      "left": 1,
      "right": 2
    }
  },'''),
    ...text(r'The source is the relative name xynorash.txt, which fastfetch resolves against the current directory. That is why the profile does Push-Location into the fastfetch folder, runs fastfetch in a try block and always pops again in finally. The logo itself is coloured with 24-bit escape sequences: the first eleven rows are one cyan, the next seven carry an escape per character, and the last fourteen shade from blue through violet to magenta, the same two hues as the prompt.'),
    ...text(r'The module list is a tour of the machine, grouped by colour: operating system, kernel, board, uptime, packages and processes in cyan and violet; shell, terminal and font in green; CPU, memory modules, GPU and display in amber and orange; Vulkan and OpenGL in pink; then bars for CPU, RAM, swap, two disks and volume; the media player; and two rows of colour swatches.'),

    ...sec(r'the palette'),
    ...text(r'The same few colours repeat across the theme, the syntax colours and the banner, and that repetition is what makes three different tools look like one product. Counting the foreground colours in the theme gives cyan #00E5FF 32 times, green #00E5AA 4, violet #AA00FF 3, amber #FFAA00 3, magenta #EE00EE 3, orange #FF6432 2, and one each of a dark grey, a yellow and a pink. The syntax-highlighting block in profile.ps1 reuses cyan for commands, violet for parameters and green for strings. The banner’s key colours are the same RGB values written in the decimal form fastfetch wants (170;0;255 is #AA00FF).'),

    ...sec(r'edge cases the code handles'),
    ...bullet(r'theme file missing', r'Get-Theme_Override tests for the file and does nothing if it is absent. The prompt stays the default.'),
    ...bullet(r'carapace not on PATH', r'second lookup in the winget package folder, then silence if neither is found.'),
    ...bullet(r'fastfetch not on PATH', r'the same two-step lookup, and no banner if neither is found.'),
    ...bullet(r'non-interactive host', r'the banner only runs when $Host.Name is ConsoleHost and the session is interactive, so scripts launched with the profile loaded do not print a logo.'),
    ...bullet(r'font already installed', r'checked by the existence of one file, then skipped, so the registry is not touched on every start.'),
    ...bullet(r'Windows Terminal missing or unreadable', r'a warning in the installer and a silent catch in the profile.'),
    ...bullet(r'battery on a desktop', r'display_error is false, so a machine without a battery shows no error where the segment would have been.'),
    ...bullet(r'drive F absent', r'segment hidden, no error, as above.'),

    ...sec(r'a bug that the history records'),
    ...text(r'The battery segment first used .State as a string and compared it with the words Charging and Full. The second commit’s message says why that broke: in oh-my-posh v29 .State is an enum, not a string, and the template failed with an error that began “unable to create text based on template”. The fix replaced the comparison with the segment’s own Icon plus four icon properties.'),
    ...code('json', r'xynorash.omp.json · lines 303-310, after the fix', r'''
          "template": " {{ .Icon }} {{ .Percentage }}% ▸",
          "properties": {
            "display_error": false,
            "charged_icon": "󰁹",
            "charging_icon": "󰂄",
            "discharging_icon": "󰁺",
            "not_charging_icon": "󰁺"
          }'''),
    ...text(r'Both discharging and not-charging use the same low-battery glyph, which is a choice the diff shows and the commit does not explain. The two fixes (carapace and battery) went into one commit, and the commit message describes both as failures seen at run time.'),

    ...sec(r'how it is tested'),
    ...text(r'It is not. There is no spec file, no Pester test and no CI workflow in the tree. The evidence of verification is the history: a fix commit that corrects two defects both of which only appear on a real Windows box (a PATH captured before an install, a template error specific to one oh-my-posh version). For a project made of configuration that is a plain statement of the situation, and the page for each file lists what a test would need to cover.'),

    ...sec(r'history'),
    ...text(r'Five commits, all within five minutes of each other on 2026-06-07 (times +0300). Two of them are merge commits.'),
    blank,
    ...bullet(r'3690dee 23:48:58', r'init: core XYNORASH configuration. 912 insertions across 11 files: the README, both profiles, the theme, the banner, the ignore file and the four fonts. No installer yet.'),
    ...bullet(r'be3650d 23:49:11', r'feat: add portable install.ps1 bootstrap. install.ps1 in its final 143 lines.'),
    ...bullet(r'b7e4667 23:49:46', r'merge of be3650d into main, titled feat: portable auto-install bootstrap, with the body “Adds install.ps1 — one-shot idempotent bootstrap for any Windows machine.”'),
    ...bullet(r'b9d3efd 23:52:42', r'fix: resilient carapace lookup + battery template error. +17 −4 over profile.ps1 and xynorash.omp.json.'),
    ...bullet(r'791cf8c 23:53:11', r'the same fix merged into main, with the same title, with parents b7e4667 and b9d3efd.'),
    blank,
    ...text(r'The author lines show two identities: the commits made locally carry XNash, the merge commits carry Xynorash, which is the GitHub no-reply form. Nothing has changed since. The project is a small, finished-feeling artefact with one weekend’s worth of history compressed into five minutes by the commit clock.'),

    ...sec(r'checking the README against the code'),
    ...text(r'Each claim in the upstream README was compared with the file that implements it. Most hold exactly; three deserve a note.'),
    blank,
    ...bullet(r'holds: three-line prompt', r'three blocks with newline true on the second and third.'),
    ...bullet(r'holds: transient prompt', r'a transient_prompt block and Enable-KeyHandlers in the hook.'),
    ...bullet(r'holds: live vitals', r'CPU, memory, two disks, uptime, IP and process count are all produced as the README lists.'),
    ...bullet(r'holds: git status', r'branch, ahead and behind, staged, modified, untracked and stash are all in the git template.'),
    ...bullet(r'holds: admin and SSH', r'the two conditions in the session template.'),
    ...bullet(r'holds: install.ps1 table', r'the tools and modules and the font match the packages array and the modules array.'),
    ...bullet(r'note: the README layout sample', r'shows the vitals line without the battery segment and with the IP masked as 192.168.1.x. The real second line also prints the battery when one exists, and the language detectors come first.'),
    ...bullet(r'note: “Language runtimes”', r'the README lists seven examples and says “and more”; the theme defines 32 detectors.'),
    ...bullet(r'note: Fastfetch “on every new tab”', r'the code limits it to the console host in an interactive session, which is what a new tab is, but excludes scripts.'),
    ...bullet(r'note: .gitignore', r'ignores Modules/, *.log, .DS_Store and Thumbs.db. Nothing named Modules/ exists in the tree, and the profile never writes one.'),
    ...bullet(r'note: clone URL', r'the README clones from github.com/XNash/xynorash-pwsh, an older account name; the repository this page documents is xynorash/xynorash-pwsh.'),

    ...sec(r'limits and honest edges'),
    ...bullet(r'Windows only', r'every path is a Windows path, the installer needs winget, and the font and terminal steps use the registry and a Windows Terminal package id.'),
    ...bullet(r'no uninstall', r'there is no script to undo the copy, the registry entries or the Windows Terminal edit.'),
    ...bullet(r'copy, not link', r'edits to the repository do not reach the shell until install.ps1 is run again.'),
    ...bullet(r'drive letters', r'C and F are hard-coded in two files.'),
    ...bullet(r'a stale comment', r'profile.ps1 line 2 names a fallback theme the shipped base profile no longer uses.'),
    ...bullet(r'no licence file', r'the fonts and the base profile come from other projects, so a reader reusing the repository should check those terms themselves.'),

    ...sec(r'what to take from it'),
    ...text(r'The project is small, and what is worth copying is a way of arranging a shell, not any single line. Keep the theme as data and push every computed value through environment variables, so the theme never needs to know how a number was made. Spend the cost of expensive vitals on a counter. Let an optional dependency be absent without an error. Hook into someone else’s profile through a function name they already check for. And when a tool is installed and used in one session, look for it in the place the installer put it, not only on PATH.'),
    ...text(r'The pages that follow explain one file each: install.ps1, profile.ps1, Microsoft.PowerShell_profile.ps1, xynorash.omp.json, the two fastfetch files and .gitignore.'),
  ],
);
