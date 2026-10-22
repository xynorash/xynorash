import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynorash-pwsh/fastfetch/config.jsonc',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'fastfetch/config.jsonc — the banner'),
    cm('//', r'what the machine prints when a tab opens'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'the banner: which facts, what colours, which logo'),
    kv(r'language', r'JSONC (fastfetch configuration)'),
    kv(r'size', r'131 lines, 1 commit, never changed'),
    kv(r'modules', r'26 modules plus 6 breaks'),
    kv(r'logo', r'raw file xynorash.txt, 150 by 32'),
    kv(r'run by', r'profile.ps1, last thing in the profile'),
    ...sec(r'why this file exists'),
    ...para('//', r'fastfetch prints a logo beside a list of facts about the machine. This file is the list: which facts, in what order, with which labels and colours, and which logo. It is the only configuration the project ships for fastfetch, and profile.ps1 runs the program against it at the end of every interactive start. The config is JSONC, JSON with comments, and its first line is one: a one-line title, XYNORASH theme.'),
    ...sec(r'the logo block'),
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
    ...para('//', r'type raw means the source is a text file whose bytes are printed as they are, escape sequences included, rather than one of fastfetch’s built-in distribution logos. The source is the bare name xynorash.txt, with no directory. The profile deals with that by changing into the fastfetch folder before it runs the program and changing back afterwards in a finally block, which is the reason the relative name works. Width and height give the size of the art in cells, 150 by 32; the companion file has 32 lines. The padding puts one blank row above, one column to the left and two columns between the art and the text.'),
    ...sec(r'display: separator, colours and bars'),
    ...code('json', r'fastfetch/config.jsonc · lines 17-28', r'''
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
    ...para('//', r'The separator between a label and its value is two spaces, an arrow and two spaces. The two colour keys are written as raw SGR parameters, 38;2;R;G;B being the escape for a 24-bit foreground: keys are 170,0,255, the violet #AA00FF of the prompt, and title is 0,229,255, the cyan #00E5FF. Every colour in this file is the decimal form of a palette value used in xynorash.omp.json, which is how a banner and a prompt from two different programs read as one design. The bar block defines what a percentage looks like: 20 cells wide, filled with a full block, the rest with a light shade, framed by a left and a right half-block.'),
    ...sec(r'the modules, in order'),
    ...code('json', r'fastfetch/config.jsonc · lines 30-49', r'''
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
    { "type": "processes","key": "󰄹  Procs",  "keyColor": "38;2;0;229;255" },'''),
    ...para('//', r'modules is an ordered list and the order is the output order. The title prints user, an at-sign and host, each in its own colour; the separator module draws a rule of 33 box-drawing dashes under it. Then the identity group: operating system, kernel, board, uptime, packages, processes. Each entry names a module type, a key label that starts with a Nerd Font glyph, and a keyColor. The host entry sets format to {2}, which picks the third field of the host module’s output instead of printing all of them; the file does not say which field that is. The string break inserts a blank line, and the groups are separated that way.'),
    ...code('json', r'fastfetch/config.jsonc · lines 52-71', r'''
    { "type": "shell",    "key": "󰍛  Shell", "keyColor": "38;2;0;229;170" },
    { "type": "terminal", "key": "󰍛  Term",  "keyColor": "38;2;0;229;170" },
    { "type": "font",     "key": "󰍛  Font",  "keyColor": "38;2;0;229;170" },
    "break",

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
    ...para('//', r'The second group is the software environment in green: shell, terminal, font. The third is hardware in amber and orange: CPU, then physical memory with the format {2} {5}-{3}, which uses the module’s fields positionally in the same way, then the GPU with detectionType auto, and the display. Colour here encodes the group: amber for the CPU side, orange for the GPU side. The fourth group, in pink, asks for Vulkan and OpenGL.'),
    ...code('json', r'fastfetch/config.jsonc · lines 77-117', r'''
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
    },
    {
      "type": "swap",
      "key": "󰾴  Swap",
      "keyColor": "38;2;170;0;255",
      "format": "{4} {1} / {2}",
      "percent": { "type": 2 }
    },
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
    ...para('//', r'The next group is live usage, as bars. cpuUsage uses percent type 3 and memory and swap use type 2; the format {4} {1} / {2} puts the bar first, then used, then total. Both disks and the volume follow. The disk entries name their folder, C:\ and F:\, as a JSON-escaped backslash, which is the fastfetch way to pick which drive to report. This is the one place where the file assumes the author’s machine: the F drive is hard-coded, and profile.ps1 reads the same two drives for the prompt. On a computer without an F: drive the entry has nothing to report.'),
    ...code('json', r'fastfetch/config.jsonc · lines 120-129', r'''
    {
      "type": "media",
      "key": "󰝚  Now",
      "keyColor": "38;2;255;200;50",
      "format": "{3}  {1}"
    },
    "break",

    { "type": "colors", "paddingLeft": 1, "symbol": "circle" },
    { "type": "colors", "paddingLeft": 1, "symbol": "block" }'''),
    ...para('//', r'The last group is the media player, formatted with {3} and {1}, and then two rows of colour swatches, one drawn with circles and one with blocks, a common way to show off a terminal palette.'),
    ...sec(r'design decisions'),
    ...pt('//', r'colour as grouping', r'key colours differ between groups (cyan and violet, green, amber, orange, pink), so the eye can find a group without reading labels.'),
    ...pt('//', r'glyph labels', r'every key starts with a Nerd Font icon, which is why the font is bundled and installed by the same project. Several keys reuse the same CPU glyph, so the glyph is decoration here rather than information.'),
    ...pt('//', r'bars instead of numbers', r'a bar shows a quantity at a glance, and the config sets its size once for all of them.'),
    ...sec(r'edge cases'),
    ...pt('//', r'missing module data', r'a module that finds nothing prints nothing; the config has no fallback text.'),
    ...pt('//', r'non-Windows', r'the drive entries and the Windows-style keys would not mean anything on Linux; the project does not target it.'),
    ...pt('//', r'narrow terminal', r'the logo is declared 150 columns wide, so a window narrower than that will wrap the art; the file has no condition for it.'),
    ...sec(r'how it is tested'),
    ...para('//', r'Not by any spec. fastfetch can print the configuration with its own command and the schema line on line 3 lets an editor validate the keys while writing. The history has no fix for this file.'),
    ...sec(r'history'),
    ...para('//', r'One commit: 3690dee, 2026-06-07 23:48, init: core XYNORASH configuration. 131 lines, unchanged since.'),
  ],
);
