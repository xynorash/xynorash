import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynorash-pwsh/xynorash.omp.json',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'xynorash.omp.json — the prompt, written as data'),
    cm('//', r'three blocks, fifty segments, eleven colours and a contract with the profile'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'the oh-my-posh theme: what the prompt looks like'),
    kv(r'format', r'oh-my-posh JSON config, format version 4'),
    kv(r'size', r'374 lines, 3 blocks, 50 segments (5 + 41 + 4)'),
    kv(r'palette', r'11 distinct colour literals, 64 uses, no variables'),
    kv(r'history', r'2 commits: 370 lines at birth, +4 net in the battery fix'),
    kv(r'checked', r'rendered with oh-my-posh 29.0.0, 29.35.0, 31.5.0 (Linux)'),
    ...sec(r'why this file exists'),
    ...para('//', r'A prompt is the one piece of interface you see after every command, so ' r'this theme tries to answer the questions you would otherwise type a ' r'command to ask: where am I, what state is the repository in, what is ' r'this project written in, is the machine healthy, how long did that ' r'take and did it work. The answers are split over three lines by how ' r'often they change. The README draws the result:'),
    ...code('text', r'README.md · the layout sketch', r'''
╭─ 󰍲 user@host ~/path/here ▸  main ~2 +1 ▸
│  󰍛 12% ▸ 󰘚 47% ▸ 󰋊 C:48% ▸ 󰋊 F:27% ▸ ⬆ 1d 4h ▸ 󰩟 192.168.1.x ▸ 󰄹 312 ▸
╰─ Mon 07 Jun  23:41 ❯'''),
    ...para('//', r'Line one is identity and place. Line two is context and vitals: ' r'language versions for the project you are in, then the machine. Line ' r'three is the input line, with timing, the clock and the success ' r'symbol. After Enter the whole thing collapses to one glyph (the ' r'transient prompt), so scrollback stays a list of commands. Everything ' r'is declarative. The theme contains no code; it is a list of segments, ' r'each with a type, a colour and a template. The only imperative part is ' r'in profile.ps1, which computes the numbers oh-my-posh has no built-in ' r'segment for and hands them over as XYNO_ environment variables. This ' r'file is the other half of that contract. The page also records an ' r'experiment. The theme was rendered with the oh-my-posh binary itself ' r'(its print command, versions 29.0.0, 29.35.0 and 31.5.0 on Linux, with ' r'the XYNO_ variables set by hand and small throw-away git repositories ' r'as the working directory). The Windows-only pieces (the battery chip, ' r'the Windows icon) could not be exercised, but most of the rest could, ' r'and the results change a few claims a reader would otherwise take on ' r'trust.'),
    ...sec(r'the top of the file'),
    ...code('json', r'xynorash.omp.json · lines 2-15', r'''
  "$schema": "https://raw.githubusercontent.com/JanDeDobbeleer/oh-my-posh/main/themes/schema.json",
  "version": 4,
  "final_space": true,
  "blank_line_before_prompt": true,
  "disable_notice": true,
  "shell_integration": true,
  "transient_prompt": {
    "foreground": "#00E5AA",
    "foreground_templates": [
      "{{ if gt .Code 0 }}#FF6432{{ end }}"
    ],
    "background": "transparent",
    "template": "{{ if gt .Code 0 }}✗{{ else }}❯{{ end }} "
  },'''),
    ...pt('//', r'$schema and version', r'the schema URL gives editors completion; version 4 is the ' r'config-format version, not the program’s. The battery fix names ' r'oh-my-posh v29 as the engine in use.'),
    ...pt('//', r'shell_integration', r'documented as FinalTerm OSC sequences. The rendered prompt does begin ' r'with OSC 133 marks (ESC ] 133 ; D ; 0, then ESC ] 133 ; A), which let ' r'a terminal that understands them know where each prompt starts.'),
    ...pt('//', r'transient_prompt', r'what a finished prompt is replaced with: a mint arrow, or an orange ' r'cross when the exit code was above zero. One template serves both ' r'cases, and the foreground has a template of its own for the failure ' r'colour.'),
    blank,
    ...para('//', r'Two other keys, blank_line_before_prompt and disable_notice, are ' r'covered under "keys that do nothing" below.'),
    ...sec(r'line one: identity and place'),
    ...code('json', r'xynorash.omp.json · os and session segments', r'''
        {
          "type": "os",
          "style": "plain",
          "foreground": "#AA00FF",
          "template": "╭─ {{ .Icon }} ",
          "properties": {
            "windows": "󰍲"
          }
        },
        {
          "type": "session",
          "style": "plain",
          "foreground": "#00E5AA",
          "template": "{{ if env \"SSH_CLIENT\" }}<#FFAA00>󰢩 </>{{ end }}<#FF3296>{{ .UserName }}</>{{ if env \"XYNO_IS_ADMIN\" }}<#FF4488> 󰒃</>{{ end }}<#555>@</>{{ .HostName }} "
        },'''),
    ...para('//', r'Every segment uses the plain style: no powerline arrows, no background ' r'fills. The colours do the work and the separators are literal ' r'characters in the templates (▸ between chips, ╭─ │ ╰─ down the left ' r'edge), which keeps the prompt legible on any background and easy to ' r'copy from scrollback. The os segment prints the box-drawing corner ' r'that opens the prompt and then the operating-system icon. The session ' r'segment is the busiest template in the block: an SSH glyph if ' r'SSH_CLIENT exists, the user name in hot pink, a shield if ' r'XYNO_IS_ADMIN is set, a grey @, then the host name. Each marker ' r'appears only when it is relevant, so a normal local session shows ' r'nothing extra and an elevated or remote one is hard to miss. With ' r'XYNO_IS_ADMIN=1 set by hand, the rendered prompt did show the shield ' r'after the user name.'),
    ...code('json', r'xynorash.omp.json · path segment', r'''
        {
          "type": "path",
          "style": "plain",
          "foreground": "#00E5FF",
          "template": "{{ .Path }} ",
          "properties": {
            "style": "agnoster_short",
            "max_depth": 3,
            "folder_separator_icon": "/",
            "truncation_symbol": "…/"
          }
        },'''),
    ...para('//', r'The agnoster_short style with a depth of 3 keeps the first folder, an ' r'elision marker and the last three folders. A deep directory rendered ' r'as tmp/../scratchpad/pwsh_work/tr_clean. Note the two dots: the ' r'truncation_symbol set here (…/) is not what the engine used, the first ' r'hint that the property is not recognised. The folder separator is a ' r'plain slash, which is the documented default, so that line is a no-op.'),
    ...sec(r'the git chip, and the experiment that broke it'),
    ...code('json', r'xynorash.omp.json · git segment (trimmed)', r'''
        {
          "type": "git",
          "style": "plain",
          "foreground": "#AA00FF",
          "foreground_templates": [
            "{{ if gt .Working.Changed 0 }}#FFAA00{{ end }}",
            "{{ if and (eq .Working.Changed 0) (gt .Staging.Changed 0) }}#00E5AA{{ end }}"
          ],
... {{ if gt .Working.Changed 0 }} <#FF6432>~{{ .Working.Changed }}</>{{ end }}{{ if gt .Staging.Changed 0 }} <#FF3296>+{{ .Staging.Changed }}</>{{ end }} ...
          "properties": {
            "fetch_status": true
          }
        },'''),
    ...para('//', r'The design is good. The chip is violet; with unstaged work it turns ' r'amber; when everything that changed is staged it turns mint. Counts ' r'show only when non-zero: commits ahead and behind, modified files, ' r'staged files, untracked files, the stash. The second colour test ' r'spells out that the working tree must be clean, so it does not rely on ' r'the order in which the tests are tried. It does not work as written. ' r'The README sketch shows ~2 +1, but in the rendering experiment those ' r'indicators and the colour change never appeared. A repository with one ' r'modified file and another with one staged file both rendered a violet ' r'chip with only the branch name; only the untracked count (?1, in hot ' r'pink) and the stash count showed. A probe template pointed at the same ' r'repositories gives the reason, one line each:'),
    plain(r'changed=true modified=1 staged=false/0 gt=no     (one modified file)'),
    plain(r'changed=false modified=0 staged=true/1 gt=no     (one staged file)'),
    ...para('//', r'The probe printed .Working.Changed, .Working.Modified, ' r'.Staging.Changed, .Staging.Modified and the result of gt ' r'.Working.Changed 0. Changed is a boolean, not a count: it prints true ' r'or false, and a boolean is never greater than zero. The documentation ' r'says the same (the boolean "if the status contains changes or not") ' r'and puts the counts in Modified, Added, Deleted, Untracked and ' r'Unmerged. All three engine versions behaved identically. It is the ' r'same family of mistake as the battery bug below: a template that ' r'assumes a field’s type. The fix is small: use the boolean as the ' r'condition for the colours and print .Working.Modified and ' r'.Staging.Modified for the numbers. Until then the amber and mint ' r'states and the ~ and + counters are dead code, and the README should ' r'not promise them.'),
    ...sec(r'line two: the language chips'),
    ...code('json', r'xynorash.omp.json · the first two language chips', r'''
        {
          "type": "text",
          "style": "plain",
          "foreground": "#00E5FF",
          "template": "│ "
        },
        {
          "type": "rust",
          "style": "plain",
          "foreground": "#FF6432",
          "template": " 󱘗 {{ .Full }} ▸"
        },
        {
          "type": "java",
          "style": "plain",
          "foreground": "#FFC832",
          "template": " ☕ {{ .Full }} ▸"
        },'''),
    ...para('//', r'Line two opens with a cyan bar and 32 language segments. Each detects ' r'its project files in the current directory and, if it finds them, runs ' r'the toolchain to read a version and prints it with {{ .Full }}. ' r'Elsewhere it prints nothing, so the line stays short. A directory with ' r'a Cargo.toml, a package.json and a main.go rendered an orange Rust ' r'chip (1.97.0), then cyan Node (22.22.0) and Go (1.24.7) chips, each ' r'with its icon. Five segments have colours of their own (Rust orange, ' r'Java yellow, .NET violet, Flutter and Dart mint); the other 27 share ' r'cyan. Chips are chained with a leading space and a trailing ▸, so any ' r'combination reads as one list. Two defects came out of the checks.'),
    blank,
    ...pt('//', r'eleven chips have no icon', r'elixir, erlang, julia, perl, scala, ocaml, quasar, elm, v, bazel and ' r'buf have templates that start with two spaces and go straight to {{ ' r'.Full }}. The Elixir chip, rendered with a stand-in elixir command, ' r'printed two spaces and 1.16.0, with a blank where the glyph belongs. ' r'Every icon that survived in the repository is in the supplementary ' r'private-use range (U+F0000 and above, the Material Design set of Nerd ' r'Fonts 3); none is in the older range U+E000 to U+F8FF, where Devicons ' r'and the Powerline symbols live. That fits a copy or generation step ' r'that dropped the older range and kept the rest. The repository does ' r'not record the cause.'),
    ...pt('//', r'three chips do not exist', r'erlang, scala and elm are not segment types in the oh-my-posh source ' r'and schema that were checked. A directory with elm.json, build.sbt and ' r'rebar.config and stand-in commands on the path rendered no Erlang, ' r'Scala or Elm chip while the Elixir control did (only a Java chip ' r'appeared beside it). Unknown types are skipped without a message.'),
    ...code('json', r'xynorash.omp.json · a chip with no icon', r'''
        {
          "type": "elixir",
          "style": "plain",
          "foreground": "#00E5FF",
          "template": "  {{ .Full }} ▸"
        },'''),
    ...para('//', r'The git branch icon, by contrast, is not missing: the engine prepends ' r'it to the head value, and the rendered chip began with the Powerline ' r'branch glyph (U+E0A0).'),
    ...sec(r'line two: the vitals'),
    ...code('json', r'xynorash.omp.json · CPU, RAM and the two disks', r'''
        {
          "type": "text",
          "style": "plain",
          "foreground": "#FFAA00",
          "template": "{{ if env \"XYNO_CPU\" }} 󰍛 {{ env \"XYNO_CPU\" }}% ▸{{ end }}"
        },
        {
          "type": "sysinfo",
          "style": "plain",
          "foreground": "#FFAA00",
          "template": " 󰘚 {{ .PhysicalPercentUsed | printf \"%.0f\" }}% ▸"
        },
        {
          "type": "text",
          "style": "plain",
          "foreground": "#EE00EE",
          "template": "{{ if env \"XYNO_DISK_C\" }} 󰋊 C:{{ env \"XYNO_DISK_C\" }}% ▸{{ end }}"
        },
        {
          "type": "text",
          "style": "plain",
          "foreground": "#EE00EE",
          "template": "{{ if env \"XYNO_DISK_F\" }} 󰋊 F:{{ env \"XYNO_DISK_F\" }}% ▸{{ end }}"
        },'''),
    ...para('//', r'This is where the theme meets profile.ps1. CPU, disk, uptime, IP and ' r'process count are text segments whose template is a single conditional ' r'on an environment variable. If the variable is absent the chip renders ' r'nothing and takes no space, so a missing profile layer removes chips ' r'and breaks nothing. Rendered with no XYNO_ variables at all, line two ' r'was the cyan bar plus the RAM chip, and lines one and three were ' r'unaffected. With the variables set by hand, line two matched the ' r'README sketch: 12%, 4%, C:48%, F:27%, ⬆ 1d 4h, an IP and 312 ' r'processes. Uptime, IP and process count follow the same pattern ' r'further down the file. RAM is the exception because it has its own ' r'segment: sysinfo exposes PhysicalPercentUsed, formatted with printf to ' r'zero decimals. The split follows cost, as far as the code shows: what ' r'the engine can read for free (memory, battery) stays in the theme; ' r'what needs a counter, a delta or a throttle (CPU, uptime, disks, IP, ' r'processes) is computed in the profile. The drive letters are in the ' r'template text, so the F: chip is specific to the author’s machine; ' r'elsewhere the variable never gets set and the chip is hidden.'),
    ...sec(r'the battery bug, and its fix'),
    ...code('json', r'xynorash.omp.json · battery segment', r'''
        {
          "type": "battery",
          "style": "plain",
          "foreground": "#FFAA00",
          "foreground_templates": [
            "{{ if lt .Percentage 20 }}#FF6432{{ end }}"
          ],
          "template": " {{ .Icon }} {{ .Percentage }}% ▸",
          "properties": {
            "display_error": false,
            "charged_icon": "󰁹",
            "charging_icon": "󰂄",
            "discharging_icon": "󰁺",
            "not_charging_icon": "󰁺"
          }
        },'''),
    ...para('//', r'The first version, in the init commit, chose its icon inside the ' r'template by comparing the state with strings: if it equals Charging ' r'show one glyph, else if it equals Full another, else a third. It ' r'failed on every prompt with the engine’s "unable to create text based ' r'on template". The commit message of b9d3efd (2026-06-07, 23:52) gives ' r'the cause: .State is an enum in oh-my-posh v29, not a string. The ' r'documentation agrees that .State is a struct with a .String function. ' r'The fix moves the decision out of the template into the segment’s own ' r'properties. The engine already knows how to turn a state into an icon: ' r'set charged_icon, charging_icon, discharging_icon and ' r'not_charging_icon, print {{ .Icon }}, and the template never compares ' r'types. The threshold colouring stayed, a foreground template that ' r'makes the chip orange below 20 percent. Two limits. Discharging and ' r'not-charging share the same low-battery glyph, so the icon shows the ' r'state and the number carries the level. And the segment could not be ' r'exercised here, since it needs Windows; display_error is false (also ' r'the documented default) and the Linux runs, on a machine with no ' r'battery, rendered no battery chip.'),
    ...sec(r'line three: time, clock and result'),
    ...code('json', r'xynorash.omp.json · timing, clock and exit symbol', r'''
        {
          "type": "executiontime",
          "style": "plain",
          "foreground": "#FF6432",
          "template": "{{ .FormattedMs }} ",
          "properties": {
            "threshold": 500,
            "style": "austin"
          }
        },
        {
          "type": "time",
          "style": "plain",
          "foreground": "#EE00EE",
          "template": "{{ .CurrentDate | date \"Mon 02 Jan  15:04\" }} "
        },
        {
          "type": "exit",
          "style": "plain",
          "foreground": "#00E5AA",
          "foreground_templates": [
            "{{ if gt .Code 0 }}#FF6432{{ end }}"
          ],
          "template": "{{ if gt .Code 0 }}✗{{ else }}❯{{ end }} ",
          "properties": {
            "always_enabled": true
          }
        }'''),
    ...para('//', r'The execution-time segment is invisible for fast commands: a 500 ms ' r'threshold and the austin format. Rendered with 65,432 ms it printed 1m ' r'5.432s in orange; at 200 ms it printed nothing. (Both settings are the ' r'documented defaults, so they are written out for clarity.) The clock ' r'uses a Go time layout with two spaces before the hour. The exit ' r'segment is always_enabled, so the arrow shows on success too, and a ' r'foreground template turns it into an orange cross when the code is ' r'above zero: a mint arrow for status 0 and an orange cross for status 1 ' r'in the rendered output. The same condition is written again in the ' r'transient prompt at the top of the file; the two copies are kept in ' r'step by hand.'),
    ...sec(r'eleven colours, sixty-four uses'),
    ...para('//', r'The theme never defines a colour once. Counting every literal gives ' r'cyan #00E5FF 32 times, mint #00E5AA 6, orange #FF6432 6, amber #FFAA00 ' r'5, hot pink #FF3296 4, violet #AA00FF 3, magenta #EE00EE 3, yellow ' r'#FFC832 2, and single uses of #FF4488 (the admin shield), #555 (the @) ' r'and #444 (the separators). It reads as a system: cyan marks structure ' r'and neutral information, amber marks metrics, violet and pink mark ' r'identity and git, mint means fine and orange means attention (though ' r'orange also colours Rust and the timer, which blunts the signal a ' r'little). The same values are repeated in profile.ps1’s colour block, ' r'in the base profile’s colour block and, as decimal red-green-blue ' r'triples, in fastfetch/config.jsonc. The schema supports a palette ' r'table with named references and this theme does not use it, so ' r'changing the scheme means editing about sixty places in this file ' r'alone.'),
    ...sec(r'keys that do nothing'),
    ...para('//', r'Comparing the file with the engine’s published JSON schema and source ' r'at the time of writing (not the exact build the author had in June) ' r'turns up three entries that are not recognised:'),
    blank,
    ...pt('//', r'blank_line_before_prompt', r'not a top-level property. The rendered prompt starts with its ' r'shell-integration marks and no blank line of its own.'),
    ...pt('//', r'disable_notice', r'not a property of the current schema either. The schema has an upgrade ' r'section instead, whose notice option defaults to false.'),
    ...pt('//', r'truncation_symbol', r'not a property of the path segment, which is why the elision appears ' r'as two dots, the engine’s default.'),
    blank,
    ...para('//', r'Unrecognised keys are ignored, so none of this breaks the prompt. It ' r'does mean the lines read as if they configure something they do not, ' r'and a schema-aware editor would flag them.'),
    ...sec(r'history, and what is not checked'),
    ...pt('//', r'3690dee', r'2026-06-07, "init: core XYNORASH configuration": the whole theme, 370 ' r'lines.'),
    ...pt('//', r'b9d3efd', r'2026-06-07 23:52, merged as 791cf8c: the battery template, four lines ' r'more.'),
    blank,
    ...para('//', r'The battery bug is the only defect the author found himself, within ' r'four minutes of the first commit, by using the prompt. There are no ' r'tests in the repository; the experiment above is the only evidence ' r'that the theme works, and it ran on Linux. It confirmed the XYNO_ ' r'contract, the language chips, the timer, the exit symbol and the ' r'transient prompt, and it found the git defect. It could not check the ' r'Windows icon, the battery chip, or what the glyphs look like in the ' r'real font. The picture on the author’s screen was never compared with ' r'the README sketch.'),
    ...sec(r'what it teaches'),
    ...pt('//', r'keep the engine dumb', r'the theme has no logic of its own; the profile computes, the theme ' r'prints, and a missing producer removes a chip instead of breaking the ' r'line.'),
    ...pt('//', r'check types, not intentions', r'both real defects here (battery state, git change counts) are ' r'templates that assume a field’s type. Printing the field in a probe ' r'template takes one command and settles it.'),
    ...pt('//', r'sketches are not screenshots', r'the README layout is a drawing of what was intended, and its git ' r'indicators do not render.'),
    ...pt('//', r'make failures loud', r'eleven missing icons and three non-existent chips survived because ' r'every failure mode of this file is silent.'),
    link(r'→ github.com/XNash/xynorash-pwsh', r'https://github.com/XNash/xynorash-pwsh'),
  ],
);
