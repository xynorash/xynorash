import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynorash-pwsh/fastfetch/config.jsonc',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'fastfetch/config.jsonc — the banner that opens every tab'),
    cm('//', r'26 modules, 8 palette colours, one 150-column logo'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'the fastfetch configuration shown on each interactive start'),
    kv(r'format', r'JSONC (a comment line, then JSON) against fastfetch’s schema'),
    kv(r'size', r'131 lines, 1 commit (unchanged since init)'),
    kv(r'modules', r'26 modules and 6 blank separators, 32 lines in all'),
    kv(r'palette', r'the prompt’s colours, written as decimal SGR triples'),
    kv(r'checked', r'run with fastfetch 2.40.4, 2.56.0 and 2.69.0 on Linux'),
    ...sec(r'why this file exists'),
    ...para('//', r'The prompt shows the machine as it is right now, one chip at a time. ' r'Fastfetch is its counterpart: a full snapshot printed once, when a tab ' r'opens. The same facts appear in both places (uptime, process count, ' r'CPU and RAM use, the C and F drives), but they serve different ' r'questions. The prompt answers "is anything wrong at this moment?"; the ' r'banner answers "what machine, what shell, what terminal and what font ' r'am I in?". Every choice in the file serves one idea: the banner should ' r'look like part of the same cockpit. The colours are the prompt’s ' r'colours, the bars are drawn with the same family of block characters, ' r'the keys carry Nerd Font glyphs, and the logo is the project’s own ' r'mark. profile.ps1 launches it on interactive starts only (see that ' r'page for the guards).'),
    ...sec(r'how it is started, and why that matters'),
    ...para('//', r'The profile runs fastfetch --config on this file after changing into ' r'this folder. The reason shows in the first block of the file:'),
    ...code('json', r'fastfetch/config.jsonc · the logo', r'''
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
    ...para('//', r'The logo is a type raw, with a source that is a bare file name, ' r'xynorash.txt. A relative path is resolved against the current working ' r'directory, not against the config file. To check, fastfetch 2.69.0 was ' r'run with an absolute --config pointing at this file and the working ' r'directory set to /tmp: it did not find the logo and printed its ' r'built-in distro logo instead, with the info beside it. Run from this ' r'folder, it used xynorash.txt. That is exactly why profile.ps1 wraps ' r'the call in Push-Location and Pop-Location. The coupling is invisible ' r'in both files unless you read them together. The declared size is 150 ' r'by 32, and the file measures exactly that: 32 rows, each 150 visible ' r'columns wide once the colour escapes are removed (see ' r'fastfetch/xynorash.txt). The padding adds one column on the left and ' r'two on the right, so the information column would start 153 columns ' r'in. The module list has 32 entries as well (26 modules and 6 blank ' r'separators), which would line the two columns up row for row if every ' r'module printed a line. That coincidence suggests a side-by-side layout ' r'was intended.'),
    ...sec(r'what the experiment showed about the layout'),
    ...para('//', r'The schema describes the logo types plainly. raw is an "image file ' r'rendered as a raw binary string"; file-raw is a "text file, printed as ' r'is". This config uses raw for a text file full of colour escapes. Run ' r'in a terminal 220 columns wide, in all three versions tried (2.40.4, ' r'2.56.0 and 2.69.0), the raw logo was printed above the module list: 70 ' r'lines in total. Changing only the type to file-raw in 2.69.0 put the ' r'modules beside the logo, 36 lines in total; the two older versions ' r'printed 69 lines for file-raw, the height of the stacked layout. That ' r'is an observation about three Linux builds. The Windows build the ' r'author uses may behave differently, and the repository has no ' r'screenshot to settle it. What can be said is that the stacked layout ' r'makes the banner about twice as tall as the side-by-side one, and that ' r'the file-raw type is the one the schema documents for text.'),
    ...sec(r'the display block'),
    ...code('json', r'fastfetch/config.jsonc · separator, colours and bars', r'''
  "display": {
    "separator": "  →  ",
    "color": {
      "keys": "38;2;170;0;255",
      "title": "38;2;0;229;255"
    },
    "bar": {
      "width": 20,
      "char": { "elapsed": "█", "total": "░" },
      "border": { "left": "▐", "right": "▌" }
    }
  },'''),
    ...pt('//', r'separator', r'an arrow with two spaces on each side, in place of the default colon.'),
    ...pt('//', r'color', r'keys in violet (170;0;255) and titles in cyan (0;229;255). These are ' r'SGR fragments: the text after 38;2; is red, green and blue in decimal, ' r'the same palette as the prompt’s #AA00FF and #00E5FF.'),
    ...pt('//', r'bar', r'twenty cells, filled with a full block and emptied with a light shade, ' r'closed by half-block borders. On Linux the CPU% line rendered as a ' r'20-cell bar followed by (5%), so the pieces do what the file says.'),
    blank,
    ...para('//', r'Every module below sets its own keyColor, which the schema says ' r'overrides display.color.keys. The global key colour is therefore never ' r'used by any module. It is harmless, and redundant.'),
    ...sec(r'the title and the system block'),
    ...code('json', r'fastfetch/config.jsonc · title, separator and the first group', r'''
  "modules": [
    {
      "type": "title",
      "color": {
        "user": "38;2;0;229;255",
        "at":   "38;2;100;100;180",
        "host": "38;2;170;0;255"
      }
    },
    {
      "type": "separator",
      "string": "─────────────────────────────────"
    },

    { "type": "os",       "key": "󰍲  OS",     "keyColor": "38;2;170;0;255" },
    { "type": "kernel",   "key": "󰍛  Kernel", "keyColor": "38;2;170;0;255" },
    { "type": "host",     "key": "󰒋  Board",  "keyColor": "38;2;170;0;255", "format": "{2}" },
    { "type": "uptime",   "key": "󰅐  Uptime", "keyColor": "38;2;0;229;255" },
    { "type": "packages", "key": "󰏗  Pkgs",   "keyColor": "38;2;0;229;255" },
    { "type": "processes","key": "󰄹  Procs",  "keyColor": "38;2;0;229;255" },
    "break",'''),
    ...para('//', r'The title module splits user, at-sign and host into three colours: ' r'cyan, a muted blue (100;100;180, the only colour in the file with no ' r'counterpart in the theme) and violet. The separator is a line of ' r'box-drawing dashes. After it come six modules in two colours, violet ' r'for the machine identity (OS, kernel, board) and cyan for things that ' r'change (uptime, packages, processes). "break" is a bare string, not a ' r'module: it prints an empty line and is what groups the output. The ' r'Board key uses the host module with the format {2}, which the schema ' r'defines as the product name. The label is an interpretation of that ' r'field, not a different module.'),
    ...sec(r'hardware and graphics'),
    ...code('json', r'fastfetch/config.jsonc · CPU, memory modules, GPU, display', r'''
    { "type": "cpu",    "key": "󰍛  CPU",     "keyColor": "38;2;255;170;0" },
    {
      "type": "physicalMemory",
      "key": "󰍛  DDR",
      "keyColor": "38;2;255;170;0",
      "format": "{2} {5}-{3}"
    },
    {
      "type": "gpu",
      "key": "󰢮  GPU",
      "keyColor": "38;2;255;100;50",
      "detectionType": "auto"
    },
    { "type": "display",  "key": "󰍹  Display","keyColor": "38;2;255;100;50" },
    "break",'''),
    ...para('//', r'CPU and memory modules are amber, GPU and display are orange, and ' r'further down the graphics APIs (Vulkan and OpenGL) are pink. The ' r'physicalMemory format "{2} {5}-{3}" uses placeholders defined by ' r'fastfetch’s schema: field 2 is the size, 5 the type (DDR4, DDR5) and 3 ' r'the maximum speed, so a module prints as something like "16 GiB ' r'DDR5-5600" under the key DDR. The gpu module sets detectionType to ' r'auto. The current schema and source call that option detectionMethod, ' r'with auto as its first and default value, so against today’s fastfetch ' r'the key is unrecognised and harmless. Validating the whole file ' r'against the schema flags exactly this key. It also flags three module ' r'names (physicalMemory, openGL, cpuUsage) that the schema spells in ' r'lower case; fastfetch accepts them at run time, since the CPU% line ' r'printed.'),
    ...sec(r'live usage'),
    ...code('json', r'fastfetch/config.jsonc · CPU usage and memory', r'''
    {
      "type": "cpuUsage",
      "key": "󰍛  CPU%",
      "keyColor": "38;2;0;229;255",
      "percent": { "type": 3 }
    },
    {
      "type": "memory",
      "key": "󰍛  RAM ",
      "keyColor": "38;2;170;0;255",
      "format": "{4} {1} / {2}",
      "percent": { "type": 2 }
    },'''),
    ...code('json', r'fastfetch/config.jsonc · disks and volume', r'''
    {
      "type": "disk",
      "key": "󰋊  C:\\ ",
      "keyColor": "38;2;238;0;238",
      "folders": "C:\\",
      "percent": { "type": 2 }
    },
    {
      "type": "disk",
      "key": "󰋊  F:\\ ",
      "keyColor": "38;2;238;0;238",
      "folders": "F:\\",
      "percent": { "type": 2 }
    },
    {
      "type": "sound",
      "key": "󰕾  Vol ",
      "keyColor": "38;2;0;229;170",
      "format": "{6} {4}",
      "percent": { "type": 3 }
    },'''),
    ...para('//', r'The percent.type values are the schema’s: 2 draws a bar and 3 draws a ' r'bar and the number. Memory uses format "{4} {1} / {2}", where field 4 ' r'is the percentage bar, 1 the used size and 2 the total, so the line ' r'reads bar, used, total. Swap repeats the same format. On Linux these ' r'rendered as a 20-cell bar followed by 770.71 MiB / 15.72 GiB. Two ' r'modules are tied to the author’s machine. The disk modules name their ' r'folder, C:\ and F:\, in the Windows form. On Linux neither printed ' r'anything, so a missing folder yields no line rather than an error (a ' r'behaviour of the Linux build; the Windows build was not run). The pair ' r'mirrors the C: and F: chips in the prompt, and they have the same ' r'single-machine assumption. The sound module takes {6} and {4}: the ' r'volume bar and the volume percentage. Nine of the 22 labelled modules ' r'reuse one glyph (U+F035B) as their key icon: Kernel, Shell, Term, ' r'Font, CPU, DDR, OpenGL, CPU% and RAM. It looks like a memory-chip ' r'glyph, apt for a few of them and generic for the rest.'),
    ...sec(r'the last two blocks'),
    ...code('json', r'fastfetch/config.jsonc · media and colour swatches', r'''
    {
      "type": "media",
      "key": "󰝚  Now",
      "keyColor": "38;2;255;200;50",
      "format": "{3}  {1}"
    },
    "break",

    { "type": "colors", "paddingLeft": 1, "symbol": "circle" },
    { "type": "colors", "paddingLeft": 1, "symbol": "block" }
  ]'''),
    ...para('//', r'The media module shows what is playing, in yellow; its format "{3}  ' r'{1}" prints field 3 (artist) and then field 1 (the combined name), and ' r'was not exercised here. The two colors modules print the terminal’s ' r'palette as circles and as blocks, so a glance at the banner shows how ' r'the terminal renders its colours.'),
    ...sec(r'what a Linux run printed'),
    ...para('//', r'Not every module has data on every machine. On Linux (a virtual ' r'machine with no GPU and no Windows folders) the run printed the title, ' r'OS, kernel, uptime, packages, processes, shell, terminal, CPU, CPU ' r'usage, RAM and swap, and silently skipped the rest: board, font, DDR, ' r'GPU, display, Vulkan, OpenGL, the two disks, volume and media. The ' r'blank "break" lines stayed, so the output has empty runs where the ' r'skipped groups were. Nothing errored. That quiet degradation is a ' r'property of fastfetch, and it means the config can be copied to a ' r'machine with different hardware without editing.'),
    ...sec(r'limits'),
    ...pt('//', r'layout', r'with type raw the logo stacked above the information in every Linux ' r'build tried; a side-by-side layout needs a different type (file-raw ' r'worked in 2.69.0) or a change that was not tested on Windows.'),
    ...pt('//', r'width', r'a 150-column logo plus padding needs a very wide terminal to sit ' r'beside the information, and the repository records no minimum width ' r'and no small-logo fallback.'),
    ...pt('//', r'height', r'stacked, the banner is about 70 lines on a small machine and longer on ' r'a full one, on every new tab.'),
    ...pt('//', r'machine-specific', r'the F:\ disk, the Windows paths, the module choice.'),
    ...pt('//', r'cost', r'fastfetch is a native process started on every interactive shell; its ' r'time is not measured anywhere in the repository.'),
    ...pt('//', r'no screenshot', r'the README does not show the banner.'),
    ...sec(r'history and what it teaches'),
    ...para('//', r'One commit, 3690dee, 2026-06-07 23:48:58: the file has not changed ' r'since. What it shows is a principle worth copying: make a secondary ' r'tool speak the same visual language as the primary one. The palette is ' r'the shared asset, repeated in three notations (hex in the theme and ' r'PSReadLine, SGR decimals here), and the cost of that repetition is ' r'that the three copies must be edited together. The other lesson is ' r'that the coupling between this file and the profile (a relative path ' r'and a working directory) is easy to break by "tidying" one of them, ' r'and worth a comment in both.'),
    link(r'→ github.com/XNash/xynorash-pwsh', r'https://github.com/XNash/xynorash-pwsh'),
  ],
);
