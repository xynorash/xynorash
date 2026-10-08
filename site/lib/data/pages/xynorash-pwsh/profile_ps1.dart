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
    kv(r'evidence', r'source, commit diffs, documented PowerShell rules'),
    ...sec(r'why this file exists'),
    ...para('#', r'A PowerShell session needs three things before the cockpit prompt can ' r'work. The theme has to be initialised. The numbers on its second line ' r'(CPU, uptime, disks, IP, process count) have to be computed by ' r'somebody. And the machine has to have the font and the tools the ' r'prompt draws with. The base profile, Microsoft.PowerShell_profile.ps1, ' r'does none of that by itself. It only offers one hook and asks whether ' r'anybody wants to take it. This file is the somebody. The other files ' r'in the repository are either data (xynorash.omp.json, ' r'fastfetch/config.jsonc, fastfetch/xynorash.txt), inherited (the base ' r'profile, from Chris Titus Tech) or a one-shot installer (install.ps1). ' r'Everything that has to run on every shell start and is specific to ' r'this project is in these 121 lines: the theme hook and prompt wrapper ' r'(lines 4-44), syntax colours, prediction, carapace completion, a ' r'Shift+Enter binding, a font bootstrap, a Windows Terminal font patch ' r'and the fastfetch banner. The sections below follow that order.'),
    ...sec(r'who calls whom: the load order'),
    ...para('#', r'PowerShell 7 reads its profiles in a fixed order. Of the four, two ' r'live in the user’s PowerShell directory: profile.ps1, which applies to ' r'every host, and Microsoft.PowerShell_profile.ps1, which applies to the ' r'console host. The all-hosts file goes first. The first comment of this ' r'file says so in one line, and everything about the repository’s ' r'layering follows from it.'),
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
    ...para('#', r'The relationship runs one way. This file cannot call anything defined ' r'in the base profile, because that has not run yet. The base profile ' r'can call anything defined here, and it does: it asks whether a command ' r'named Get-Theme_Override exists and, if so, hands control over (see ' r'Microsoft.PowerShell_profile.ps1, lines 3-7). Defining a function with ' r'the agreed name is the whole extension mechanism. No file in the base ' r'is edited to add the cockpit. Two consequences are easy to miss. ' r'First, everything at the top level of this file runs before the base ' r'profile does, so the fastfetch banner at the bottom of the file prints ' r'before the theme has even been initialised; the prompt is born after ' r'the banner. Second, the comment on line 2 describes the upstream ' r'behaviour (a fallback to a theme called cobalt2), but the copy of the ' r'base profile in this repository falls back to xynorash.omp.json ' r'instead. The comment is stale; the code is right.'),
    ...sec(r'the hook, line by line'),
    ...para('#', r'The function starts with a guard. If the theme file is not beside the ' r'profile, the function does nothing and PowerShell keeps its default ' r'prompt. A missing theme costs a plain prompt, never an error on every ' r'shell start. That is the first appearance of a rule this file follows ' r'everywhere: an optional dependency that is absent must degrade, not ' r'throw. Then four lines of state. They explain the shape of the ' r'wrapper:'),
    blank,
    ...pt('#', r'the init line', r'oh-my-posh prints a PowerShell script on standard output and ' r'Invoke-Expression evaluates it. The script installs the prompt ' r'function. This is the documented way to start oh-my-posh and the same ' r'pattern carapace uses further down.'),
    ...pt('#', r'Enable-KeyHandlers', r'defined by the oh-my-posh init script. The comment on the line says it ' r'activates the transient prompt on Enter, which is what collapses the ' r'three-line cockpit to a single symbol after each command.'),
    ...pt('#', r'$global:__xyno_omp', r'saves the prompt function oh-my-posh has just installed, so the ' r'wrapper can call it at the end. The vitals code decorates the prompt; ' r'it does not reimplement it.'),
    ...pt('#', r'the globals', r'every piece of state is global and carries a __xyno_ prefix. The ' r'scriptblock assigned to prompt runs long after Get-Theme_Override has ' r'returned, so a local variable would be gone by then. A global ' r'survives, and the prefix keeps it from colliding with anything the ' r'user types.'),
    blank,
    ...para('#', r'Two more lines prepare the numbers the wrapper will publish. The CPU ' r'counter is created once and read once to seed it. The comment on the ' r'second line explains why: the first call to NextValue always returns ' r'0, because a processor-time counter is a rate and a rate needs two ' r'samples. And the administrator check runs once and is exported as ' r'XYNO_IS_ADMIN, because a process cannot become elevated while it is ' r'running. Computing it per prompt would be wasted work; the theme’s ' r'session segment only tests whether the variable is non-empty.'),
    ...sec(r'the prompt wrapper: vitals at almost no cost'),
    ...para('#', r'The point of the wrapper is that a dashboard on every prompt is only ' r'acceptable if the dashboard is nearly free. A slow prompt is felt on ' r'every Enter. So each vital is computed in the cheapest way the ' r'platform offers, and the slow-changing ones are not computed every ' r'time.'),
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
    ...pt('#', r'CPU', r'the counter is read as the delta since its previous read. Because it ' r'is read once per prompt, the number is the average load since the last ' r'prompt: how hard the machine worked during the command you just ran, ' r'diluted by any idle time before it. The comment names the two ' r'alternatives that were rejected: WMI (a query per prompt) and a sleep ' r'(sample twice with a pause, which adds latency to every Enter). The ' r'first reading is the average over the remainder of startup, since the ' r'counter was seeded while the profile was still loading.'),
    ...pt('#', r'Uptime', r'Environment.TickCount64 is milliseconds since boot. The rest is ' r'integer arithmetic on that one number: no cmdlet, no process, no ' r'query. The comment says "zero cost" and the code agrees.'),
    ...pt('#', r'Process count', r'(Get-Process).Count, evaluated on every prompt. It is the only ' r'enumeration that is not throttled, and nothing in the repository ' r'measures what it costs. It is a candidate for the same counter ' r'treatment that disk and IP get.'),
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
    ...para('#', r'Disk and IP are refreshed on a counter, and the tests are worth ' r'reading closely. The condition is n % 5 -eq 1, not -eq 0. With -eq 0 ' r'the first refresh would happen on the fifth prompt and the disk ' r'segments would be blank until then. With -eq 1 the very first prompt ' r'fills them (n is already 1 by the time the test runs), then prompts 6, ' r'11, 16 and so on. The same reasoning gives the IP refresh on prompts ' r'1, 21, 41. The code implies this was intended, since each segment ' r'hides itself while its variable is unset. The disk value is used space ' r'as a percentage of used plus free. The drive letters C and F are ' r'hard-coded, which makes this the most machine-specific piece of code ' r'in the repository. On a machine without an F drive the lookup returns ' r'nothing, the if skips the assignment and the theme’s segment stays ' r'hidden. The mirror image is a flaw: when a drive that was present goes ' r'away, nothing clears the old value, so its last percentage stays on ' r'the prompt. The IP lookup asks for IPv4 unicast addresses, drops ' r'loopback (127.) and link-local (169.) and takes the first that is ' r'left. On failure it writes a question mark, so a broken lookup is ' r'visible instead of silently blank. Taking the first match has no ' r'notion of which adapter is the real one, and a machine with virtual ' r'adapters (WSL, Hyper-V, a VPN) may show the wrong address. The code ' r'makes no attempt to prefer a physical interface.'),
    ...sec(r'what the last lines do'),
    ...para('#', r'The wrapper ends by calling the saved prompt and post-processing its ' r'output. The replacement targets the sentence that PowerShell 7 prints ' r'when loading profiles was slow: "Loading personal and system profiles ' r'took NNNms." and wraps it in a true-colour escape for #444444 ' r'(68;68;68), the same dark grey the theme uses for its separators. The ' r'intent is to quieten the message. What the repository does not show is ' r'how that sentence reaches the string returned by the prompt, which is ' r'the only place the substitution can act, and no test or comment ' r'records that it fires. The -replace result is the scriptblock’s last ' r'value, so it becomes the prompt string. The whole interface to the ' r'theme is therefore: the wrapper sets environment variables, the saved ' r'prompt runs oh-my-posh, and oh-my-posh reads them back with its env ' r'template function.'),
    ...sec(r'the seven variables: a table in prose'),
    ...para('#', r'The contract between the two files is small enough to list. Each ' r'variable has exactly one writer, here, and exactly one reader, a text ' r'segment in xynorash.omp.json guarded by an if env test:'),
    blank,
    ...pt('#', r'XYNO_IS_ADMIN', r'once per session; read by the session segment, which adds a shield ' r'glyph after the user name.'),
    ...pt('#', r'XYNO_CPU', r'every prompt; read by the first vitals segment.'),
    ...pt('#', r'XYNO_UPTIME', r'every prompt; formatted as days and hours, hours and minutes, or ' r'minutes.'),
    ...pt('#', r'XYNO_PROCS', r'every prompt; the last chip on the line.'),
    ...pt('#', r'XYNO_DISK_C and XYNO_DISK_F', r'every fifth prompt, starting with the first.'),
    ...pt('#', r'XYNO_IP', r'every twentieth prompt, starting with the first.'),
    blank,
    ...para('#', r'Environment variables are the cheapest channel into a separate ' r'process: oh-my-posh is an external program that inherits the session ' r'environment, so a value assigned in PowerShell is visible to it with ' r'no file or protocol. RAM and battery are not in the list because ' r'oh-my-posh has built-in segments for them.'),
    ...sec(r'a bug found by reading: the uptime format'),
    ...para('#', r'The uptime arithmetic casts with [int], and a PowerShell [int] cast of ' r'a fractional number rounds to the nearest integer (halves go to the ' r'even neighbour); it does not truncate. Read against that rule the code ' r'shows a skew. For an uptime of 129,600 seconds (1.5 days) the day ' r'count is [int] of 1.5, which is 2, and the hour count is exactly 12, ' r'so the prompt would print 2d 12h where 1d 12h is true. The same ' r'happens with hours in the second half of every hour: 1h 40m is 6,000 ' r'seconds, the hour value is [int] of 1.67, which is 2, and the minutes ' r'are 40, giving 2h 40m. Days and hours are therefore wrong in the ' r'second half of every day and every hour, and minutes are rounded to ' r'the nearest one, so they can reach 60. Fixing it takes a floor: ' r'[math]::Floor around each quotient. This is a finding from reading the ' r'code and from PowerShell’s documented cast behaviour; the repository ' r'has no test for it and it was not observed on a machine, so it stays ' r'on the list of things to confirm.'),
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
    ...para('#', r'Two things are wrong with the comment above this block, and both ' r'matter. None of these values is a Catppuccin Mocha colour; they are ' r'the XYNORASH palette (cyan #00E5FF, mint #00E5AA, violet #AA00FF, ' r'amber #FFAA00 and so on), so the name looks like a leftover from an ' r'earlier palette. And the block claims to override the base profile’s ' r'defaults, but the load order says the opposite. This file runs first. ' r'Microsoft.PowerShell_profile.ps1 then sets the same ten colour keys ' r'(lines 14-25 of that file) and nine of the ten values differ; only ' r'Command agrees at #00E5FF. Set-PSReadLineOption -Colors replaces ' r'values per key, so the base profile’s values are the ones that end up ' r'active. The colours that actually show are therefore the ones in the ' r'base profile: Parameter #00E5AA, Operator #FFAA00, Variable #AA00FF, ' r'String #FFC832, Number #FF6432, Type #EE00EE, Comment #444466, Keyword ' r'#FF3296, Error #FF6432. This block is dead weight until the order is ' r'changed or one of the two is deleted. It is the one place where the ' r'layering leaks, and it is visible only by reading both files against ' r'the load order.'),
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
    ...para('#', r'The prediction line carries its own reason in the comment: ' r'HistoryAndPlugin needs PSReadLine 2.2 or newer. The silent error ' r'action means an older module simply loses the feature instead of ' r'failing the profile. Carapace is the interesting part, because of its ' r'history. The first version, in the init commit, called carapace by ' r'name: it set CARAPACE_BRIDGES and piped the output of carapace ' r'_carapace into Invoke-Expression. Under four minutes later (commit ' r'b9d3efd, 2026-06-07) the commit message explains the change: fall back ' r'to the winget packages directory when carapace is not on PATH, to ' r'handle "the first shell after install and machines without it". The ' r'commit does not spell out the mechanism. A likely one, from how ' r'Windows environments work: winget updates PATH in the registry, but a ' r'terminal that was already running keeps the environment it started ' r'with, so tabs it opens cannot see the new tool yet. The fix has three ' r'parts.'),
    blank,
    ...pt('#', r'the fast path', r'Get-Command carapace with the null-conditional ?.Source, so a missing ' r'command yields null instead of an error.'),
    ...pt('#', r'the fallback', r'search the WinGet packages directory for carapace.exe and keep only ' r'paths that match rsteube, the publisher in the package id. It is a ' r'recursive search, but it only runs when the fast path failed.'),
    ...pt('#', r'the guard', r'everything, including the assignment of CARAPACE_BRIDGES, moved inside ' r'if ($_carapace). With no carapace, nothing runs and nothing is ' r'half-configured.'),
    blank,
    ...para('#', r'Out-String is not decoration. Piped as an array, the generated script ' r'would reach Invoke-Expression one line at a time, and a multi-line ' r'construct would break. Out-String joins it into a single string first. ' r'CARAPACE_BRIDGES asks carapace to borrow zsh, fish and bash completers ' r'for commands it has no native spec for; the comment in the file puts ' r'the reach at over a thousand tools. The fastfetch block already had ' r'the same fallback search from the start; the carapace fix generalised ' r'an idea the file had.'),
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
    ...para('#', r'install.ps1 already installs the fonts, so why does the profile do it ' r'again? Likely because the profile directory is meant to be ' r'self-contained: install.ps1 copies the fonts into a fonts folder ' r'beside the profile (step 4), and this bootstrap restores them from ' r'there. The README’s portability note ("all config files live in the ' r'PowerShell profile directory") points the same way; the repository ' r'does not state the reason. The guard checks only the Regular font ' r'file. If it is missing and the folder exists, all .ttf files are ' r'copied to the per-user fonts folder and registered under HKCU, which ' r'needs no administrator rights. The message tells the user to restart ' r'Windows Terminal to apply it. The terminal block is guarded three ' r'ways. The settings file has to exist, its raw text must not already ' r'mention JetBrainsMono NF, and the whole edit sits in a try with an ' r'empty catch. The last guard is the most deliberate: this is cosmetic, ' r'and cosmetic code must not be able to break a shell. It has costs. The ' r'raw-text test reads the whole settings file on every shell start. Any ' r'mention of the font anywhere in the file, including in some other ' r'profile, counts as done. And writing the file back through ' r'ConvertTo-Json cannot reproduce comments, so either the edit drops ' r'them or, if the parse fails, the empty catch swallows it; the file ' r'does not tell which. install.ps1 contains the same edit in step 5 with ' r'slightly different guards (it checks the actual property, not the ' r'text), and additionally sets scrollToBottomOnInput. There are two ' r'copies of the idea and neither calls the other.'),
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
    ...para('#', r'Three details carry the design. The guard asks for the console host ' r'and an interactive user, so scripts, CI jobs and editor-spawned shells ' r'never print a banner into their own output. The executable is found on ' r'PATH or, failing that, in the winget directory. And the call is ' r'wrapped in Push-Location and Pop-Location inside try and finally, with ' r'the location set to the config directory. The config refers to its ' r'logo with a bare relative name (fastfetch/config.jsonc, "source": ' r'"xynorash.txt"), which is the likely reason the call is made from that ' r'folder. The finally guarantees the shell’s own working directory is ' r'restored even if fastfetch fails. Placed last in a file that loads ' r'first, the banner prints before the theme exists. The user sees system ' r'information, and then the first cockpit prompt appears under it.'),
    ...sec(r'how it is checked, and what is not'),
    ...para('#', r'There are no tests here, and no timings are recorded anywhere in the ' r'repository. What protects the shell is a habit that can be read ' r'straight off the code: every optional dependency is looked up before ' r'use, every lookup has a silent fallback, and every cosmetic side ' r'effect is wrapped so it cannot take the shell down. What nothing ' r'covers is the correctness of the numbers; the uptime rounding above is ' r'what that costs.'),
    ...sec(r'what the file teaches'),
    ...pt('#', r'extend through the hook', r'the cockpit is added without editing the base profile, so the base can ' r'be refreshed from upstream and the extension survives.'),
    ...pt('#', r'keep data and presentation apart', r'this file computes; the theme formats; seven environment variables are ' r'the whole interface.'),
    ...pt('#', r'pay for what changes', r'fast values every prompt, slow values on counters, constant values ' r'once.'),
    ...pt('#', r'degrade, do not throw', r'a missing optional piece removes a feature, never the shell.'),
    ...pt('#', r'check what you believe', r'two comments here (the palette name and the override claim) describe a ' r'state the code no longer has; the load order exposes it.'),
    link(r'→ github.com/XNash/xynorash-pwsh', r'https://github.com/XNash/xynorash-pwsh'),
  ],
);
