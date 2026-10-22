import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynorash-pwsh/xynorash.omp.json',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'xynorash.omp.json — the cockpit as data'),
    cm('//', r'three blocks, fifty segments, nine colours'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'the prompt theme: layout, colours and every segment'),
    kv(r'language', r'JSON (oh-my-posh config, schema version 4)'),
    kv(r'size', r'374 lines, 3 blocks, 50 segments, 9 colours'),
    kv(r'history', r'2 commits, 370 lines at birth, +6 −2 in the fix'),
    kv(r'reads', r'SSH_CLIENT and seven XYNO_* variables'),
    kv(r'written by', r'profile.ps1, in the prompt wrapper'),
    kv(r'tested', r'by hand, on a real machine'),
    ...sec(r'why this file exists'),
    ...para('//', r'This is the whole look of the prompt, as data. oh-my-posh reads it, asks each segment for its text and colour, and prints the result before every command. Nothing in it is executed by PowerShell: it is a description of what the prompt should show. That separation is the point. profile.ps1 decides when and how numbers are computed, and this file decides where they appear and what colour they get. The two never call each other. They share only the names of environment variables, and a segment that finds its variable unset prints nothing.'),
    ...para('//', r'The file is 374 lines for a prompt that is three lines tall, because oh-my-posh wants one JSON object per segment and the project has 50 of them: 5 in the first block, 41 in the second, 4 in the third. Most of the length is a single repeated shape, the language detector, which is why this page spends its time on the five shapes that matter and treats the rest as a table.'),
    ...sec(r'the header: what kind of prompt this is'),
    ...code('json', r'xynorash.omp.json · lines 2-7', r'''
  "$schema": "https://raw.githubusercontent.com/JanDeDobbeleer/oh-my-posh/main/themes/schema.json",
  "version": 4,
  "final_space": true,
  "blank_line_before_prompt": true,
  "disable_notice": true,
  "shell_integration": true,'''),
    ...para('//', r'version 4 is the schema version of the oh-my-posh configuration format; $schema gives editors the URL to validate against. final_space leaves a space after the last segment so typed text does not touch the prompt symbol. blank_line_before_prompt puts an empty line between one command’s output and the next prompt, which is what keeps three-line prompts from running into each other. disable_notice silences the update notice oh-my-posh would otherwise print into the middle of the prompt. shell_integration turns on oh-my-posh’s shell-integration option; the file does not say which terminal features it is meant for.'),
    ...sec(r'the transient prompt'),
    ...code('json', r'xynorash.omp.json · lines 8-15', r'''
  "transient_prompt": {
    "foreground": "#00E5AA",
    "foreground_templates": [
      "{{ if gt .Code 0 }}#FF6432{{ end }}"
    ],
    "background": "transparent",
    "template": "{{ if gt .Code 0 }}✗{{ else }}❯{{ end }} "
  },'''),
    ...para('//', r'After a command is submitted, oh-my-posh redraws the old prompt using this block instead of the three blocks below. The template is the entire policy: a cross when the exit code is above zero, a chevron otherwise, both followed by a space. The colour follows the same test through foreground_templates, so the default green #00E5AA turns orange #FF6432 for a failure. The background is transparent so the terminal’s own background shows through. The result is a history in which every finished command is one symbol wide and a failure is visible at a glance. The transient prompt needs a key handler to work in PowerShell; profile.ps1 installs it by calling Enable-KeyHandlers right after oh-my-posh init.'),
    ...sec(r'block 1: identity and location'),
    ...code('json', r'xynorash.omp.json · lines 17-35', r'''
    {
      "type": "prompt",
      "alignment": "left",
      "segments": [
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
    ...para('//', r'A block is a group of segments printed together; all three here are left aligned, and the second and third set newline so they stack. The first segment prints the box corner and an operating-system icon, and the only icon configured is the one for windows, which is what the project is for. The session segment is a single template with three conditions. If SSH_CLIENT is set it prints a marker, in amber. It prints the user name in pink. If XYNO_IS_ADMIN is set it adds a shield glyph. It prints a dim @ and the host name. SSH_CLIENT is set by the OpenSSH server; XYNO_IS_ADMIN is not a Windows variable but one set by profile.ps1 once at start-up, because a process cannot change elevation while it runs. This is the first of many places where the theme reads a value that the profile computed.'),
    ...code('json', r'xynorash.omp.json · lines 36-47', r'''
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
    ...para('//', r'The path segment uses the agnoster_short style: a short form that keeps the leaf folder whole and abbreviates the ones above. max_depth of 3 limits it to three folders, and truncation_symbol shows the cut as …/ so a deep directory never takes over the line.'),
    ...sec(r'the git segment: colour as state'),
    ...code('json', r'xynorash.omp.json · lines 48-60', r'''
        {
          "type": "git",
          "style": "plain",
          "foreground": "#AA00FF",
          "foreground_templates": [
            "{{ if gt .Working.Changed 0 }}#FFAA00{{ end }}",
            "{{ if and (eq .Working.Changed 0) (gt .Staging.Changed 0) }}#00E5AA{{ end }}"
          ],
          "template": "▸  {{ .HEAD }}{{ if gt .Ahead 0 }} ⇡{{ .Ahead }}{{ end }}{{ if gt .Behind 0 }} ⇣{{ .Behind }}{{ end }}{{ if gt .Working.Changed 0 }} <#FF6432>~{{ .Working.Changed }}</>{{ end }}{{ if gt .Staging.Changed 0 }} <#FF3296>+{{ .Staging.Changed }}</>{{ end }}{{ if gt .Working.Untracked 0 }} <#FF3296>?{{ .Working.Untracked }}</>{{ end }}{{ if gt .StashCount 0 }} <#FFC832>󰆓{{ .StashCount }}</>{{ end }} ",
          "properties": {
            "fetch_status": true
          }
        },'''),
    ...para('//', r'fetch_status is on, which makes oh-my-posh ask git for the working-tree and staging counts the template uses; without it .Working.Changed and friends would be empty. The colour chain in foreground_templates is read in order and the first template that outputs a colour wins. Amber when there are unstaged changes. Green when the working tree is clean and something is staged. When both fail the static foreground, violet #AA00FF, applies. The text template builds the line from the branch (.HEAD) and then optional pieces, each wrapped in if gt N 0 so it vanishes at zero: ahead and behind arrows, ~ for modified, + for staged, ? for untracked, a glyph for stashes. A clean repository therefore shows only its branch name.'),
    ...para('//', r'The segment closes with a literal dim ▸ in its own text segment (lines 61-66). Every segment on the second line does the same with a trailing ▸ inside its own template, which makes the line read as a chain of fields.'),
    ...sec(r'block 2: the language detectors'),
    ...code('json', r'xynorash.omp.json · lines 69-85', r'''
    {
      "type": "prompt",
      "alignment": "left",
      "newline": true,
      "segments": [
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
        },'''),
    ...para('//', r'The second block opens with a vertical bar so the three lines look like one frame, then lists the detectors. A detector is an oh-my-posh segment type (rust, java, dotnet, flutter, dart, node, python, go and so on). It appears only when the current directory holds a project of that kind, for example a Cargo.toml for rust, and then shows the tool’s version through .Full. There are 32 of them, from rust to buf. They are listed in a deliberate order: rust, java, dotnet, flutter and dart come first and have their own colours (orange, yellow, violet, green, green), and from node onward every detector is cyan #00E5FF.'),
    ...code('json', r'xynorash.omp.json · lines 86-91', r'''
        {
          "type": "java",
          "style": "plain",
          "foreground": "#FFC832",
          "template": " ☕ {{ .Full }} ▸"
        },'''),
    ...para('//', r'The shape never varies: a type, style plain, a foreground, and a template of the form space, glyph, space, .Full, space, ▸. Because plain-style segments have no background or powerline separators, adding a language costs seven lines and no design decision. Whether 32 detectors cost anything at run time is not something this file can show; what it shows is the cost in length.'),
    ...sec(r'the vitals segments'),
    ...code('json', r'xynorash.omp.json · lines 272-277', r'''
        {
          "type": "text",
          "style": "plain",
          "foreground": "#FFAA00",
          "template": "{{ if env \"XYNO_CPU\" }} 󰍛 {{ env \"XYNO_CPU\" }}% ▸{{ end }}"
        },'''),
    ...para('//', r'The vitals are a different shape from the detectors. A text segment prints no version; its template is an if env test around an environment variable. The pattern is the same for CPU (XYNO_CPU), the two disks (XYNO_DISK_C and XYNO_DISK_F), uptime (XYNO_UPTIME), the IP address (XYNO_IP) and the process count (XYNO_PROCS), each in its own colour. profile.ps1 writes those variables in the prompt wrapper, so every segment reads state that is at most one prompt old. When the variable is absent the segment is empty and the line closes up, which is how the theme still works on a machine where the profile has not loaded.'),
    ...code('json', r'xynorash.omp.json · lines 278-283', r'''
        {
          "type": "sysinfo",
          "style": "plain",
          "foreground": "#FFAA00",
          "template": " 󰘚 {{ .PhysicalPercentUsed | printf \"%.0f\" }}% ▸"
        },'''),
    ...para('//', r'Memory is the one vital that oh-my-posh computes itself. The sysinfo segment exposes PhysicalPercentUsed and the template rounds it with printf %.0f to a whole number. The choice to use the built-in here and an environment variable for CPU is not explained in the file; the profile’s comment on its CPU reading says it avoids WMI and avoids sleeping, which is the constraint that made CPU a custom value.'),
    ...sec(r'battery: the segment that broke'),
    ...code('json', r'xynorash.omp.json · lines 296-311', r'''
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
    ...para('//', r'This is the segment that the second fix changed. It used to compare .State with strings, and in oh-my-posh v29 .State is an enum, so the template raised an error at run time. The commit message that records the fix says so in those words. The replacement uses .Icon, which the segment fills from the four icon properties: one for charged, one for charging, one for discharging, and one for not charging. display_error is false, so a desktop that has no battery shows nothing instead of an error. The colour has a single exception: below 20 percent the foreground becomes orange. Both discharging and not-charging map to the same glyph; the diff shows that and does not explain it.'),
    ...sec(r'block 3: the input line'),
    ...code('json', r'xynorash.omp.json · lines 332-371', r'''
    {
      "type": "prompt",
      "alignment": "left",
      "newline": true,
      "segments": [
        {
          "type": "text",
          "style": "plain",
          "foreground": "#00E5FF",
          "template": "╰─ "
        },
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
        }
      ]'''),
    ...para('//', r'The last line has four parts. The closing corner. The command duration, which the executiontime segment prints only when the command took at least 500 ms (threshold) and formats in the austin style, so a quick command leaves no clutter. The clock, with a Go date layout, Mon 02 Jan  15:04, which prints something like Mon 07 Jun  23:41 as the README shows. And the exit symbol, a chevron or a cross with the same colour test as the transient prompt, always enabled so that it also shows after a successful command. The prompt symbol is therefore defined twice, in the live prompt and in the transient one, with identical logic, so the live line and the line it collapses into agree.'),
    ...sec(r'the palette'),
    ...para('//', r'There are nine distinct foreground colours in the file. Cyan #00E5FF is the workhorse, on 32 segments. Green #00E5AA appears on 4 and marks success. Violet #AA00FF, amber #FFAA00 and magenta #EE00EE appear on 3 each. Orange #FF6432 appears on 2 and marks trouble: a failed command, a low battery, a changed file, a slow command. One each go to a dark grey #444 for the separator, a yellow #FFC832 and a pink #FF3296. The same values appear in profile.ps1 (the syntax colours) and, in decimal form, in fastfetch/config.jsonc, which is why the three tools look like one product.'),
    ...sec(r'design decisions and trade-offs'),
    ...pt('//', r'data over code', r'nothing here runs PowerShell. A theme that only reads environment variables works under any shell that oh-my-posh supports, and the PowerShell-specific work lives in one file.'),
    ...pt('//', r'plain style everywhere', r'no powerline backgrounds, so no font-dependent separators beyond the glyphs in the templates themselves, and colour carries all the meaning.'),
    ...pt('//', r'guarded templates', r'every custom vital is wrapped in if env, so a missing producer is invisible rather than ugly.'),
    ...pt('//', r'repetition accepted', r'32 near-identical detector objects are the price of a format with no loops. The alternative would be generating the file, which would add a build step to a repository that has none.'),
    ...sec(r'edge cases'),
    ...pt('//', r'no profile.ps1', r'the six custom vitals are empty and the line shows memory, battery and detectors.'),
    ...pt('//', r'no battery', r'display_error false hides the segment cleanly.'),
    ...pt('//', r'not a git repository', r'the git segment has no content and prints nothing; the trailing ▸ segment still prints, so a stray separator remains after the path.'),
    ...pt('//', r'narrow terminal', r'the second block can grow very long in a repository that triggers several detectors; the file sets no wrapping or truncation for it.'),
    ...sec(r'how it is tested'),
    ...para('//', r'There is no test in the repository. Oh-my-posh itself can print a prompt from a configuration, which is how this file would be checked by hand, and the history shows it was: the battery template error is the kind of failure that only appears when the segment is rendered on a real machine. A change worth testing next would be a render with every XYNO_ variable unset, to confirm the claim above that the theme degrades to the built-in segments.'),
    ...sec(r'history'),
    ...pt('//', r'3690dee', r'2026-06-07 23:48, init: core XYNORASH configuration. The file arrives at 370 lines.'),
    ...pt('//', r'b9d3efd', r'2026-06-07 23:52, fix: resilient carapace lookup + battery template error. +6 −2 in this file: the battery template and its icon properties. Merged as 791cf8c at 23:53. The file is 374 lines since.'),
  ],
);
