import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynorash-pwsh/profile.ps1',
  lines: [
    cm('#', '──────────────────────────────────────────'),
    cm('#', r'profile.ps1 — the layer that makes the prompt alive'),
    cm('#', r'a theme hook, a vitals wrapper, completions, fonts and a banner'),
    cm('#', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'the project’s own logic inside the shell'),
    kv(r'language', r'PowerShell 7 (uses ?. and the `e escape)'),
    kv(r'size', r'121 lines, 2 commits (112 lines at birth, +11 −2 in the one fix)'),
    kv(r'loaded', r'first, before Microsoft.PowerShell_profile.ps1'),
    kv(r'interface', r'seven environment variables, XYNO_*'),
    kv(r'evidence', r'source, history, a PowerShell 7.5.3 harness on Linux'),
    ...sec(r'why this file exists'),
    ...para('#', r'A PowerShell session needs three things before the cockpit prompt can ' r'work: the theme must be initialised, the numbers on its second line ' r'(CPU, uptime, disks, IP, process count) must be computed by somebody, ' r'and the machine must have the font and tools the prompt draws with. ' r'The base profile, Microsoft.PowerShell_profile.ps1, does none of that ' r'by itself. It offers one hook and asks whether anybody wants to take ' r'it. This file is the somebody. The other files are either data ' r'(xynorash.omp.json, fastfetch/config.jsonc, fastfetch/xynorash.txt), ' r'inherited (the base profile, from Chris Titus Tech) or a one-shot ' r'installer (install.ps1). Everything specific to this project that runs ' r'on every shell start is in these 121 lines: the theme hook and prompt ' r'wrapper (lines 4-44), syntax colours, prediction, carapace completion, ' r'a Shift+Enter binding, a font bootstrap, a Windows Terminal font patch ' r'and the fastfetch banner. The sections follow that order.'),
    ...sec(r'who calls whom: the load order'),
    ...para('#', r'PowerShell 7 reads its profiles in a fixed order. Two of them live in ' r'the user’s PowerShell directory: profile.ps1, which applies to every ' r'host, and Microsoft.PowerShell_profile.ps1, which applies to the ' r'console host. The all-hosts file goes first, as the first comment of ' r'this file says, and the layering follows from that.'),
    ...code('powershell', r'profile.ps1 · lines 1-13, the contract and the hook', r'''
# User customizations — loaded before Microsoft.PowerShell_profile.ps1
# CTT profile calls Get-Theme_Override if it exists; otherwise falls back to cobalt2.

function Get-Theme_Override {
    $themePath = Join-Path (Split-Path $PROFILE) "xynorash.omp.json"
    if (Test-Path $themePath) {
        oh-my-posh init pwsh --config $themePath | Invoke-Expression
        Enable-KeyHandlers   # activates transient prompt on Enter
        $global:__xyno_omp = $function:prompt
        $global:__xyno_n   = 0
        $global:__xyno_cpu = [System.Diagnostics.PerformanceCounter]::new('Processor', '% Processor Time', '_Total')
        $null = $global:__xyno_cpu.NextValue()  # seed — first call always returns 0
        $env:XYNO_IS_ADMIN = if (([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { '1' } else { '' }'''),
    ...para('#', r'The relationship runs one way. This file cannot call anything in the ' r'base profile, because that has not run yet. The base profile can call ' r'anything defined here, and it does: it asks whether a command named ' r'Get-Theme_Override exists and, if so, hands control over ' r'(Microsoft.PowerShell_profile.ps1, lines 3-7). Defining a function ' r'with the agreed name is the whole extension mechanism; no file in the ' r'base is edited. Two consequences are easy to miss. Everything at the ' r'top level of this file runs before the base profile, so the fastfetch ' r'banner at the bottom prints before the theme has been initialised. And ' r'the comment on line 2 describes the upstream behaviour (a fallback to ' r'a theme called cobalt2), while the copy of the base profile in this ' r'repository falls back to xynorash.omp.json. The comment is stale; the ' r'code is right.'),
    ...sec(r'the hook, line by line'),
    ...para('#', r'The function starts with a guard: if the theme file is not beside the ' r'profile, nothing happens and PowerShell keeps its default prompt. A ' r'missing theme costs a plain prompt, never an error on every shell ' r'start. That is the first appearance of a rule this file follows ' r'everywhere: an absent optional dependency must degrade, not throw. ' r'Then four lines of state explain the shape of the wrapper:'),
    blank,
    ...pt('#', r'the init line', r'oh-my-posh prints a PowerShell script and Invoke-Expression evaluates ' r'it; the script installs the prompt function. It is the documented way ' r'to start oh-my-posh and the same pattern carapace uses below.'),
    ...pt('#', r'Enable-KeyHandlers', r'defined by the oh-my-posh init script. The comment says it activates ' r'the transient prompt on Enter, which collapses the cockpit to one ' r'symbol after each command.'),
    ...pt('#', r'$global:__xyno_omp', r'saves the prompt function oh-my-posh has just installed, so the ' r'wrapper can call it at the end. The vitals code decorates the prompt; ' r'it does not reimplement it.'),
    ...pt('#', r'the globals', r'all state is global with a __xyno_ prefix. The scriptblock assigned to ' r'prompt runs long after Get-Theme_Override has returned, so a local ' r'variable would be gone; a global survives, and the prefix avoids ' r'collisions.'),
    blank,
    ...para('#', r'Two more lines prepare numbers. The CPU counter is created and read ' r'once to seed it, because the first call to NextValue always returns 0 ' r'(a processor-time counter is a rate and needs two samples). The ' r'administrator check runs once and is exported as XYNO_IS_ADMIN, since ' r'a process cannot become elevated while it runs; the theme only tests ' r'whether the variable is non-empty.'),
    ...sec(r'the prompt wrapper: vitals at almost no cost'),
    ...para('#', r'A dashboard on every prompt is acceptable only if it is nearly free, ' r'because a slow prompt is felt on every Enter. So each vital is ' r'computed in the cheapest way available, and slow-changing ones are not ' r'computed every time.'),
    ...code('powershell', r'profile.ps1 · the wrapper, first half (trimmed)', r'''
$function:prompt = {
    $global:__xyno_n++
    # CPU — reads interval since last prompt, no WMI, no sleep
    $env:XYNO_CPU = [math]::Round($global:__xyno_cpu.NextValue())
    # Uptime — pure arithmetic, zero cost
    $s = [long]([System.Environment]::TickCount64 / 1000)
    $d = [int]($s / 86400); $h = [int](($s % 86400) / 3600); $m = [int](($s % 3600) / 60)
    $env:XYNO_UPTIME = if ($d -gt 0) { "${d}d ${h}h" } elseif ($h -gt 0) { "${h}h ${m}m" } else { "${m}m" }
    # Process count
    $env:XYNO_PROCS = (Get-Process -ErrorAction SilentlyContinue).Count'''),
    ...pt('#', r'CPU', r'the counter is read as the delta since its previous read, so the ' r'number is the average load since the last prompt: how hard the machine ' r'worked during the command you just ran, diluted by idle time before ' r'it. The comment names the rejected alternatives: WMI (a query per ' r'prompt) and a sleep (sampling twice with a pause, which adds latency ' r'to every Enter).'),
    ...pt('#', r'Uptime', r'Environment.TickCount64 is milliseconds since boot. The rest is ' r'integer arithmetic on that one number: no cmdlet, no process, no ' r'query. The comment says "zero cost" and the code agrees.'),
    ...pt('#', r'Process count', r'(Get-Process).Count on every prompt. It is the only enumeration that ' r'is not throttled, and nothing in the repository measures its cost; it ' r'is a candidate for the counter treatment disk and IP get.'),
    ...code('powershell', r'profile.ps1 · the wrapper, second half', r'''
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
    }
    $r = & $global:__xyno_omp
    $r -replace '(Loading personal and system profiles took \d+ms\.)',
                "`e[38;2;68;68;68m`$1`e[0m"
}'''),
    ...para('#', r'Disk and IP are refreshed on a counter, and the tests repay a close ' r'read. The condition is n % 5 -eq 1, not -eq 0. With -eq 0 the first ' r'refresh would come on the fifth prompt and the disk chips would be ' r'blank until then; with -eq 1 the very first prompt fills them (n is ' r'already 1 when the test runs), then prompts 6, 11, 16. The IP refresh ' r'falls on prompts 1, 21, 41. The code implies this was intended, since ' r'each chip hides itself while its variable is unset. The disk value is ' r'used space as a percentage of used plus free. The drive letters C and ' r'F are hard-coded, the most machine-specific code in the repository. ' r'Without an F drive the lookup returns nothing and the chip stays ' r'hidden. The mirror image is a flaw: when a drive that was present goes ' r'away, nothing clears the old value, so its last percentage stays on ' r'the prompt. The IP lookup asks for IPv4 unicast addresses, drops ' r'loopback (127.) and link-local (169.) and takes the first left. On ' r'failure it writes a question mark, so a broken lookup is visible ' r'instead of silently blank. Taking the first match has no notion of ' r'which adapter is the real one, so a machine with virtual adapters ' r'(WSL, Hyper-V, a VPN) may show the wrong address.'),
    ...sec(r'what the last lines do'),
    ...para('#', r'The wrapper ends by calling the saved prompt and post-processing its ' r'output. The replacement targets the sentence PowerShell 7 prints when ' r'loading profiles was slow, "Loading personal and system profiles took ' r'NNNms.", and wraps it in a true-colour escape for #444444 (68;68;68), ' r'the grey the theme uses for its separators. The intent is to quieten ' r'the message. The repository does not show how that sentence reaches ' r'the string the prompt returns, the only place the substitution can ' r'act, and nothing records that it fires. The -replace result is the ' r'scriptblock’s last value, so it becomes the prompt string.'),
    ...sec(r'the seven variables: a table in prose'),
    ...para('#', r'The contract between the two files is small enough to list. Each ' r'variable has one writer, here, and one reader, a text segment in ' r'xynorash.omp.json guarded by an if env test:'),
    blank,
    ...pt('#', r'XYNO_IS_ADMIN', r'once per session; read by the session segment, which adds a shield ' r'glyph after the user name.'),
    ...pt('#', r'XYNO_CPU', r'every prompt; read by the first vitals segment.'),
    ...pt('#', r'XYNO_UPTIME', r'every prompt; formatted as days and hours, hours and minutes, or ' r'minutes.'),
    ...pt('#', r'XYNO_PROCS', r'every prompt; the last chip on the line.'),
    ...pt('#', r'XYNO_DISK_C and XYNO_DISK_F', r'every fifth prompt, starting with the first.'),
    ...pt('#', r'XYNO_IP', r'every twentieth prompt, starting with the first.'),
    blank,
    ...para('#', r'Environment variables are the cheapest channel into a separate ' r'process: oh-my-posh inherits the session environment, so a value ' r'assigned in PowerShell is visible to it with no file or protocol. RAM ' r'and battery are not listed because oh-my-posh has built-in segments ' r'for them.'),
    ...sec(r'a bug confirmed by running: the uptime format'),
    ...para('#', r'The uptime arithmetic casts with [int], and a PowerShell [int] cast of ' r'a fractional number rounds to the nearest integer (halves go to the ' r'even neighbour); it does not truncate. Running lines 19-21 unchanged ' r'in PowerShell 7.5.3, with the number of seconds as input, shows what ' r'that does:'),
    plain(r'   3599 s  ->  1h 60m    (true: 59 minutes)'),
    plain(r'   5400 s  ->  2h 30m    (true: 1h 30m)'),
    plain(r'  86399 s  ->  1d 24h    (true: 23h 59m)'),
    plain(r' 129600 s  ->  2d 12h    (true: 1d 12h)'),
    ...para('#', r'Days and hours are wrong in the second half of every day and every ' r'hour, and the minutes can reach 60. The fix is a floor: [math]::Floor ' r'around each quotient. Nothing in the repository tests it, and it sits ' r'on the second line of every prompt.'),
    ...sec(r'colours: a block that is overridden'),
    ...code('powershell', r'profile.ps1 · PSReadLine colours', r'''
# Catppuccin Mocha syntax colors — overrides CTT defaults
Set-PSReadLineOption -Colors @{
    Command   = '#00E5FF'
    Parameter = '#AA00FF'
    Operator  = '#EE00FF'
    Variable  = '#E0E0FF'
    String    = '#00E5AA'
    Number    = '#FFAA00'
    Type      = '#AA00FF'
    Comment   = '#2D2D4A'
    Keyword   = '#EE00FF'
    Error     = '#FF4488'
}'''),
    ...para('#', r'Two things are wrong with the comment above this block, and both ' r'matter. None of these values is a Catppuccin Mocha colour; they are ' r'the XYNORASH palette (cyan #00E5FF, mint #00E5AA, violet #AA00FF, ' r'amber #FFAA00 and so on), so the name looks like a leftover from an ' r'earlier palette. And the block claims to override the base profile’s ' r'defaults, but the load order says the opposite. This file runs first. ' r'Microsoft.PowerShell_profile.ps1 then sets the same ten colour keys ' r'(lines 14-25 of that file) and nine of the ten values differ; only ' r'Command agrees at #00E5FF. Set-PSReadLineOption -Colors replaces ' r'values per key, so the base profile’s values are the ones that end up ' r'active. Loading the two blocks in that order into a real PSReadLine ' r'2.3.6 session and reading the options back confirms it: after this ' r'block Parameter is 38;2;170;0;255 (#AA00FF) and String 38;2;0;229;170 ' r'(#00E5AA); after the base profile’s block they are 38;2;0;229;170 and ' r'38;2;255;200;50 (#FFC832). The colours that actually show are ' r'therefore the ones in the base profile: Parameter #00E5AA, Operator ' r'#FFAA00, Variable #AA00FF, String #FFC832, Number #FF6432, Type ' r'#EE00EE, Comment #444466, Keyword #FF3296, Error #FF6432. This block ' r'is dead weight until the order is changed or one of the two is ' r'deleted. It is the one place where the layering leaks, and it is ' r'visible only by reading both files against the load order.'),
    ...sec(r'completion'),
    ...code('powershell', r'profile.ps1 · prediction and carapace', r'''
# Better completion — HistoryAndPlugin requires PSReadLine 2.2+
Set-PSReadLineOption -PredictionSource HistoryAndPlugin -ErrorAction SilentlyContinue

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
    ...para('#', r'The prediction line carries its own reason in the comment: ' r'HistoryAndPlugin needs PSReadLine 2.2 or newer. The silent error ' r'action means an older module simply loses the feature instead of ' r'failing the profile. Carapace has a history. The first version, in the ' r'init commit, called carapace by name: it set CARAPACE_BRIDGES and ' r'piped the output of carapace _carapace into Invoke-Expression. Under ' r'four minutes later (b9d3efd, 2026-06-07) the commit message explains ' r'the change: fall back to the winget packages directory when carapace ' r'is not on PATH, for "the first shell after install and machines ' r'without it". It does not spell out the mechanism. A likely one: winget ' r'updates PATH in the registry, but a terminal that was already running ' r'keeps the environment it started with, so its new tabs cannot see the ' r'new tool yet. The fix has three parts.'),
    blank,
    ...pt('#', r'the fast path', r'Get-Command carapace with the null-conditional ?.Source, so a missing ' r'command yields null instead of an error.'),
    ...pt('#', r'the fallback', r'search the WinGet packages directory for carapace.exe and keep only ' r'paths that match rsteube, the publisher in the package id. It is a ' r'recursive search, but it only runs when the fast path failed.'),
    ...pt('#', r'the guard', r'everything, including the assignment of CARAPACE_BRIDGES, moved inside ' r'if ($_carapace). With no carapace, nothing runs and nothing is ' r'half-configured.'),
    blank,
    ...para('#', r'Out-String is not decoration: piped as an array, the generated script ' r'would reach Invoke-Expression one line at a time and a multi-line ' r'construct would break. CARAPACE_BRIDGES asks carapace to borrow zsh, ' r'fish and bash completers for commands it has no native spec for; the ' r'comment puts the reach at over a thousand tools. The fastfetch block ' r'already had the same fallback search from the start, so the fix ' r'generalised an idea the file had.'),
    ...sec(r'fonts, installed from inside the profile'),
    ...code('powershell', r'profile.ps1 · font bootstrap and terminal setting (trimmed)', r'''
# ── Font bootstrap (runs once per machine, then skips fast) ──────────────────
$_fontFile = "$env:LOCALAPPDATA\Microsoft\Windows\Fonts\JetBrainsMonoNerdFont-Regular.ttf"
$_fontsDir = Join-Path (Split-Path $PROFILE) "fonts"
if (-not (Test-Path $_fontFile) -and (Test-Path $_fontsDir)) {
    New-Item -ItemType Directory -Force "$env:LOCALAPPDATA\Microsoft\Windows\Fonts" | Out-Null
    $reg = "HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"
    Get-ChildItem $_fontsDir -Filter "*.ttf" | ForEach-Object {
        $dest = "$env:LOCALAPPDATA\Microsoft\Windows\Fonts\$($_.Name)"
        Copy-Item $_.FullName $dest -Force
        Set-ItemProperty $reg "$($_.BaseName) (TrueType)" $dest -ErrorAction SilentlyContinue
    }
    Write-Host "JetBrainsMono NF installed — restart Windows Terminal to apply." -ForegroundColor Cyan
}
...
# ── Windows Terminal font (idempotent, safe on any machine) ──────────────────
$_wt = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
if ((Test-Path $_wt) -and (Get-Content $_wt -Raw) -notmatch 'JetBrainsMono NF') {
    try {
        $s = Get-Content $_wt -Raw | ConvertFrom-Json
        if (-not ($s.profiles.defaults | Get-Member font -ErrorAction SilentlyContinue)) {
            $s.profiles.defaults | Add-Member -MemberType NoteProperty -Name font `
                -Value ([PSCustomObject]@{ face = 'JetBrainsMono NF'; size = 11 }) -Force
        } else {
            $s.profiles.defaults.font.face = 'JetBrainsMono NF'
        }
        $s | ConvertTo-Json -Depth 20 | Set-Content $_wt -Encoding UTF8
    } catch {}
}'''),
    ...para('#', r'install.ps1 already installs the fonts, so why again? Likely because ' r'the profile directory is meant to be self-contained: install.ps1 ' r'copies the fonts into a fonts folder beside the profile (its step 4) ' r'and this bootstrap restores them from there. The README’s portability ' r'note points the same way; the repository does not state the reason. ' r'The guard checks only the Regular font file. If it is missing and the ' r'folder exists, all .ttf files are copied to the per-user fonts folder ' r'and registered under HKCU, which needs no administrator rights. The ' r'message tells the user to restart Windows Terminal to apply it. The ' r'terminal block is guarded three ways: the settings file must exist, ' r'its raw text must not already mention JetBrainsMono NF, and the edit ' r'sits in a try with an empty catch. The last is the most deliberate: ' r'this is cosmetic, and cosmetic code must not be able to break a shell. ' r'It has costs. The raw-text test reads the whole settings file on every ' r'shell start; any mention of the font anywhere, even in another ' r'profile, counts as done; and ConvertTo-Json cannot write comments ' r'back, so either the edit drops them or, if the parse fails, the empty ' r'catch swallows it. The file does not tell which. install.ps1 contains ' r'the same edit in step 5 with slightly different guards (it checks the ' r'actual property, not the text), and additionally sets ' r'scrollToBottomOnInput. There are two copies of the idea and neither ' r'calls the other.'),
    ...sec(r'the banner'),
    ...code('powershell', r'profile.ps1 · fastfetch on interactive sessions', r'''
# Fastfetch on interactive sessions only
if ($Host.Name -eq 'ConsoleHost' -and [Environment]::UserInteractive) {
    $ffConfig = Join-Path (Split-Path $PROFILE) "fastfetch\config.jsonc"
    $ffExe = (Get-Command fastfetch -ErrorAction SilentlyContinue)?.Source
    if (-not $ffExe) {
        $ffExe = Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\Fastfetch*" `
            -Recurse -Filter "fastfetch.exe" -ErrorAction SilentlyContinue |
            Select-Object -First 1 -ExpandProperty FullName
    }
    if ($ffExe) {
        Push-Location (Split-Path $ffConfig)
        try { & $ffExe --config $ffConfig } finally { Pop-Location }
    }
}'''),
    ...para('#', r'Three details carry the design. The guard asks for the console host ' r'and an interactive user, so scripts, CI jobs and editor-spawned shells ' r'never print a banner into their own output. The executable is found on ' r'PATH or, failing that, in the winget directory. And the call is ' r'wrapped in Push-Location and Pop-Location inside try and finally, from ' r'the config directory. The config names its logo with a bare relative ' r'path ("source": "xynorash.txt"), and the reason shows when the call is ' r'made from elsewhere: run from another directory with an absolute ' r'--config path, fastfetch 2.69.0 did not find xynorash.txt and printed ' r'its built-in distro logo instead. The finally restores the shell’s ' r'working directory even if fastfetch fails. Placed last in a file that ' r'loads first, the banner prints before the theme exists. The user sees ' r'system information, and then the first cockpit prompt appears under ' r'it.'),
    ...sec(r'how it was checked: a harness on Linux'),
    ...para('#', r'The repository has no tests and records no timings, so the pieces that ' r'can run off Windows were run. All three scripts parse without errors ' r'in PowerShell 7.5.3. Lines 4-44 were loaded unchanged except for one ' r'stand-in: the Windows-only performance counter became an object whose ' r'NextValue returns 7.4. With oh-my-posh 29.35.0 on the path and the ' r'theme beside a throw-away profile directory, Get-Theme_Override ' r'installed the wrapper, and three consecutive calls to prompt rendered ' r'the cockpit with CPU 7%, RAM 4%, uptime 24m, a question mark for the ' r'IP (Get-NetIPAddress does not exist on Linux, so the catch branch ' r'wrote its sentinel, which then persisted through calls 2 and 3) and 81 ' r'processes. The disk chips were absent, as designed, because there was ' r'no C drive. The oh-my-posh init script, run under both 29.35.0 and ' r'31.5.0, defines Enable-KeyHandlers and a prompt function, which is ' r'what lines 7-9 rely on. What could not be run: the performance ' r'counter, the administrator check (the Windows principal API throws off ' r'Windows), the registry and font code, the Windows Terminal edit, the ' r'fastfetch launch with a real Windows build, and the PATH situation ' r'behind the carapace fix.'),
    ...sec(r'what the file teaches'),
    ...pt('#', r'extend through the hook', r'the cockpit is added without editing the base profile, so the base can ' r'be refreshed from upstream and the extension survives.'),
    ...pt('#', r'keep data and presentation apart', r'this file computes, the theme formats, and seven environment variables ' r'are the whole interface.'),
    ...pt('#', r'pay for what changes', r'fast values every prompt, slow values on counters, constant values ' r'once.'),
    ...pt('#', r'degrade, do not throw', r'a missing optional piece removes a feature, never the shell.'),
    ...pt('#', r'run what you can', r'the uptime bug and the dead colour block were both invisible on a ' r'quick read and obvious once the code was executed.'),
    link(r'→ github.com/XNash/xynorash-pwsh', r'https://github.com/XNash/xynorash-pwsh'),
  ],
);
