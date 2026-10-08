import '../../models/project.dart';
import '../authoring.dart';

final Buffer xynorashPwshBuffer = Buffer(
  id: 'xynorash-pwsh',
  fileName: 'xynorash.ps1',
  icon: '\u{ebc7}',
  filetype: 'powershell',
  repo: 'xynorash-pwsh',
  summary: 'PowerShell 7 cockpit · live-vitals prompt',
  fallbackStars: 0,
  fallbackPushed: '2026-06-07',
  lines: [
    cm('#', '──────────────────────────────────────────'),
    cm('#', 'xynorash-pwsh — a cockpit for PowerShell 7'),
    cm('#', 'gamer/dev/hacker terminal for Windows Terminal'),
    cm('#', '──────────────────────────────────────────'),
    blank,
    kv('shell', 'PowerShell 7+ on Windows 10/11'),
    kv('prompt', 'oh-my-posh with a 374-line custom theme'),
    kv('palette', 'neon cyan · magenta · amber on near-black'),
    kv('install', 'one command, safe to re-run'),

    ...sec('what the prompt is for'),
    plain('╭─ 󰪞 user@host ~/path ▸  main ~2 +1 ▸'),
    plain('│  󰍛 12% ▸  47% ▸ 󰋊 C:48% ▸ ⬆ 1d 4h ▸ 󰩟 192.168.1.x'),
    plain('╰─ Mon 07 Jun  23:41 ❯'),
    blank,
    ...para('#',
        'A prompt is the one piece of UI you see after every '
        'command, so it should answer the questions you would '
        'otherwise type a command to ask: where am I, what branch '
        'and in what state, is the machine healthy, how long did '
        'that take, did it succeed. Three lines split those by '
        'how often they change — identity and git on top, '
        'system vitals in the middle, timing and the input line '
        'at the bottom.'),
    blank,
    ...para('#',
        'The tension is that rich prompts get slow, and a slow '
        'prompt is worse than none because you feel it on every '
        'Enter. Most of the engineering here is making a '
        'dashboard cost almost nothing.'),

    ...sec('vitals without the lag'),
    ...para('#',
        'oh-my-posh renders the prompt but is not a good place to '
        'poll the system. So the profile wraps the prompt '
        'function, computes the numbers cheaply, and passes them '
        'to the theme as environment variables the template just '
        'prints:'),
    ...code('powershell', 'profile.ps1 (trimmed)', r'''
$global:__xyno_cpu = [System.Diagnostics.PerformanceCounter]::new(
    'Processor', '% Processor Time', '_Total')
$null = $global:__xyno_cpu.NextValue()  # seed: first read is 0

$function:prompt = {
    $global:__xyno_n++
    # CPU: interval since last prompt, no WMI, no sleep
    $env:XYNO_CPU = [math]::Round($global:__xyno_cpu.NextValue())
    # Uptime: pure arithmetic, zero cost
    $s = [long]([System.Environment]::TickCount64 / 1000)
    # Disk: refresh every 5 prompts
    if ($global:__xyno_n % 5 -eq 1) {
        $dc = Get-PSDrive C -ErrorAction SilentlyContinue
        if ($dc) { $env:XYNO_DISK_C =
            [math]::Round($dc.Used / ($dc.Used + $dc.Free) * 100) }
    }
    # IP: refresh every 20 prompts
    if ($global:__xyno_n % 20 -eq 1) { ... }
    & $global:__xyno_omp
}'''),
    ...pt('#', 'CPU',
        'a PerformanceCounter is read as the delta since the '
        'previous read — which, polled from the prompt, is '
        '“CPU use since your last command”. It must be seeded once '
        'because its first value is always zero, and it avoids '
        'WMI, whose startup cost would show on every prompt.'),
    ...pt('#', 'uptime',
        'TickCount64 plus integer division; no system call worth '
        'the name.'),
    ...pt('#', 'disk and IP',
        'they barely change, so they refresh on a counter: disk '
        'every 5th prompt, IP every 20th. Cost is amortised '
        'rather than paid each time.'),
    ...pt('#', 'wrapping, not replacing',
        'the theme’s own prompt function is saved and called at '
        'the end, so oh-my-posh still does all rendering; this '
        'only feeds it data.'),
    ...para('#',
        'On the theme side, each vital is a text segment that '
        'prints only if its variable exists, so a missing value '
        'removes the segment instead of printing a blank:'),
    ...code('json', 'xynorash.omp.json (excerpt)', r'''
{
  "type": "text",
  "style": "plain",
  "foreground": "#FFAA00",
  "template": "{{ if env \"XYNO_CPU\" }} 󰍛 {{ env \"XYNO_CPU\" }}% ▸{{ end }}"
},
{
  "type": "sysinfo",
  "foreground": "#FFAA00",
  "template": " 󰘚 {{ .PhysicalPercentUsed | printf \"%.0f\" }}% ▸"
}'''),
    ...para('#',
        'RAM comes from oh-my-posh’s built-in sysinfo segment; CPU, '
        'disks, uptime, IP and process count come from the '
        'profile, where they can be computed as deltas or '
        'refreshed on a counter. Deciding which side each metric '
        'belongs on is the design.'),

    ...sec('information that appears only when it matters'),
    ...para('#',
        'A fixed prompt of everything would be noise. The theme '
        'uses conditions so segments earn their space: SSH and '
        'admin markers appear only in those sessions, the battery '
        'only on a laptop (and turns orange-red under 20 %), execution '
        'time only past 500 ms, and git colours itself by state.'),
    ...code('json', 'xynorash.omp.json · git segment (excerpt)', r'''
"foreground_templates": [
  "{{ if gt .Working.Changed 0 }}#FFAA00{{ end }}",
  "{{ if and (eq .Working.Changed 0) (gt .Staging.Changed 0) }}#00E5AA{{ end }}"
],
"template": "▸  {{ .HEAD }}{{ if gt .Ahead 0 }} ⇡{{ .Ahead }}{{ end }} …"'''),
    ...para('#',
        'Amber means unstaged work, green means everything '
        'changed is staged, and counts are shown only when '
        'non-zero — so a clean repo is quiet and a dirty one is '
        'impossible to miss. Over thirty language segments '
        '(Rust, Go, Python, Node, Java, .NET, Flutter, Dart, Zig '
        'and more) work the same way: each detects its own '
        'project files and shows its version only inside one.'),
    blank,
    ...para('#',
        'The transient prompt completes the idea. After you press '
        'Enter, the three-line cockpit collapses to one symbol — '
        '❯ in green, or ✗ in orange if the command failed — so '
        'scrollback is a clean list of commands instead of a wall '
        'of repeated dashboards, while the live prompt still '
        'shows everything.'),
    ...code('json', 'xynorash.omp.json · transient_prompt', r'''
"transient_prompt": {
  "foreground": "#00E5AA",
  "foreground_templates": ["{{ if gt .Code 0 }}#FF6432{{ end }}"],
  "background": "transparent",
  "template": "{{ if gt .Code 0 }}✗{{ else }}❯{{ end }} "
}'''),

    ...sec('layered on a base profile, not forked'),
    ...para('#',
        'The base is Chris Titus Tech’s popular PowerShell '
        'profile, which brings a large set of sensible aliases '
        'and helpers. Copying and editing it would freeze me at '
        'one upstream version; so the customisation sits '
        'beside it and plugs into the one extension point it '
        'offers:'),
    ...code('powershell', 'Microsoft.PowerShell_profile.ps1', r'''
if (Get-Command 'Get-Theme_Override' -ErrorAction SilentlyContinue) {
    Get-Theme_Override
} else {
    oh-my-posh init pwsh --config (Join-Path (Split-Path $PROFILE) "xynorash.omp.json") | Invoke-Expression
}'''),
    ...para('#',
        'My profile.ps1 defines Get-Theme_Override, and the base '
        'calls it if it exists, falling back to a plain theme '
        'init if not. Either way the same theme loads, and the '
        'base file stays a clean upstream copy I can refresh. '
        'The same thinking explains the next two pieces: they '
        'guard themselves so running on a fresh or half-set-up '
        'machine never throws.'),

    ...sec('completion and keys'),
    ...code('powershell', 'profile.ps1 · carapace', r'''
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
    ...para('#',
        'Carapace gives annotated completions — flags, '
        'subcommands, argument values — for over a thousand '
        'tools, and CARAPACE_BRIDGES lets it borrow zsh, fish and '
        'bash completers for tools it has no native spec for. '
        'The fallback search covers the moment right after winget '
        'installs it, when the current session’s PATH has not '
        'refreshed yet — looking in the package directory makes '
        'the first launch work without a restart.'),
    blank,
    ...para('#',
        'PSReadLine adds prediction in a list view, history '
        'search on the arrow keys, Ctrl-based word movement and '
        'undo/redo, and Shift+Enter to insert a newline without '
        'submitting. Its syntax colours use the same neon '
        'palette as the prompt, so command, parameter, string '
        'and error colours match what the prompt is already '
        'doing.'),

    ...sec('an installer you can run twice'),
    ...para('#',
        'install.ps1 is five visible steps — tools, PowerShell '
        'modules, fonts, config files, Windows Terminal — and '
        'each says what it did. Installs check whether the work '
        'is already done first, which makes re-running the '
        'fix for a broken setup rather than a hazard:'),
    ...code('powershell', 'install.ps1 (excerpt)', r'''
$packages = @(
    @{ Id = 'JanDeDobbeleer.OhMyPosh'; Name = 'oh-my-posh' },
    @{ Id = 'Fastfetch-cli.Fastfetch'; Name = 'fastfetch'  },
    @{ Id = 'rsteube.Carapace';        Name = 'carapace'   },
    @{ Id = 'ajeetdsouza.zoxide';      Name = 'zoxide'     }
)
foreach ($pkg in $packages) {
    $found = winget list --id $pkg.Id --exact 2>$null |
        Select-String $pkg.Id
    if ($found) {
        Write-Ok "$($pkg.Name) already installed"
    } else {
        Write-Step "Installing $($pkg.Name)..."
        winget install $pkg.Id --silent ...
    }
}'''),
    ...para('#',
        'Fonts are the awkward part. A Nerd Font must be '
        'installed for the glyphs to render, and installing a '
        'font without admin rights means copying to the per-user '
        'fonts folder and registering it in the current user’s '
        'registry. The profile does this once, only if the font '
        'file is missing, and then patches Windows Terminal’s '
        'settings to use it:'),
    ...code('powershell', 'profile.ps1 · font bootstrap (trimmed)', r'''
$reg = "HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"
Get-ChildItem $_fontsDir -Filter "*.ttf" | ForEach-Object {
    $dest = "$env:LOCALAPPDATA\Microsoft\Windows\Fonts\$($_.Name)"
    Copy-Item $_.FullName $dest -Force
    Set-ItemProperty $reg "$($_.BaseName) (TrueType)" $dest
}

if ((Test-Path $_wt) -and
    (Get-Content $_wt -Raw) -notmatch 'JetBrainsMono NF') {
    $s = Get-Content $_wt -Raw | ConvertFrom-Json
    $s.profiles.defaults | Add-Member -MemberType NoteProperty `
        -Name font -Force `
        -Value ([PSCustomObject]@{ face = 'JetBrainsMono NF'; size = 11 })
    $s | ConvertTo-Json -Depth 20 | Set-Content $_wt -Encoding UTF8
}'''),
    ...para('#',
        'The Windows Terminal edit is guarded three ways: the '
        'settings file must exist, the font must not already be '
        'configured, and the whole block is wrapped in a '
        'try/catch that ignores failure. A cosmetic improvement '
        'must never be able to break someone’s terminal.'),
    blank,
    ...para('#',
        'Fastfetch runs only in an interactive console host — '
        'checked by host name and UserInteractive — so scripts, '
        'CI and editors that spawn a shell never print a banner '
        'into their output. It locates the binary on PATH or, '
        'failing that, in the winget package directory, and '
        'changes into its own config folder for the call and '
        'always restores the location in a finally block.'),

    ...sec('what I would stress about it'),
    ...para('#',
        'It is a configuration project, so correctness here '
        'means “does not hurt the host”: guards around every '
        'optional dependency, idempotent installs, no system-wide '
        'changes beyond winget packages and a per-user font, and '
        'a prompt whose cost is bounded by design rather than '
        'by hoping the machine is fast.'),
    blank,
    plain(r'git clone https://github.com/XNash/xynorash-pwsh.git'),
    plain(r'.\install.ps1   # fonts, tools, config — one command'),
    blank,
    link('→ github.com/XNash/xynorash-pwsh',
        'https://github.com/XNash/xynorash-pwsh'),
  ],
);
