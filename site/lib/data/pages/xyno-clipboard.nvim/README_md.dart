import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-clipboard.nvim/README.md',
  summary: r'Neovim clipboard provider for tmux, SSH and herdr sessions: OSC 52 copy, local Wayland paste',
  repo: 'xyno-clipboard.nvim',
  fallbackStars: 0,
  fallbackPushed: '2026-10-22',
  lines: [
    heading(r'# xyno-clipboard.nvim'),
    blank,
    ...text(r'A Neovim clipboard provider for sessions whose yanks must reach another machine. Inside '
        r'tmux, over SSH or in a herdr pane, every copy is emitted as OSC 52, so the text lands on '
        r'the screen you are sitting at, and when a local Wayland clipboard exists it is kept in '
        r'sync and used for paste, so content copied in other apps still pastes. Everywhere else '
        r'the plugin does nothing and Neovim’s default detection stays in charge. Two Lua files, '
        r'153 lines of code, no dependencies.'),
    kv(r'language', r'Lua, Neovim 0.12+'),
    kv(r'platform', r'Linux only by design; setup() returns early elsewhere'),
    kv(r'size', r'2 modules (99 + 54 lines), 1 spec file with 11 tests'),
    kv(r'history', r'4 commits, all on 2026-10-22'),
    kv(r'origin', r'extracted from xynovim, lua/config/remote_clipboard.lua'),
    kv(r'license', r'MIT'),
    ...sec(r'the problem'),
    ...text(r'Yank in a terminal editor and you expect the text to be pasteable on the machine under '
        r'your hands. That is easy when the editor runs locally. It stops being easy in the '
        r'sessions the author actually works in: tmux, often over SSH. The README '
        r'states the author’s own constraint in two sentences: the default detection picks nothing '
        r'useful there, and a plain OSC 52 provider breaks pasting from other applications on a '
        r'Wayland desktop.'),
    ...sec(r'the idea'),
    ...text(r'OSC 52 is a terminal escape sequence that asks the terminal to put base64 text into the '
        r'system clipboard. Because it is just bytes in the output stream it can travel over SSH; per the '
        r'plugin’s header comment, inside tmux it becomes a tmux buffer that is rebroadcast to every '
        r'attached client. So copy always emits it. But paste cannot use the same trick well, '
        r'because an OSC 52 read is a query that many terminals never answer. So paste is '
        r'asymmetric: with a Wayland display and both wl-copy and wl-paste it reads the local '
        r'clipboard, and only without one does it fall back to the query.'),
    ...sec(r'the shape of the repository'),
    plain(r'xyno-clipboard.nvim/'),
    plain(r'├── lua/xyno_clipboard/'),
    plain(r'│   ├── init.lua                  setup(), status(), the provider'),
    plain(r'│   └── detect.lua                is this a remote-capable session?'),
    plain(r'├── tests/'),
    plain(r'│   ├── specs/clipboard_spec.lua  11 tests, all externals faked'),
    plain(r'│   ├── run.lua                   runner with xyno-os skips'),
    plain(r'│   ├── harness.lua               describe / it / hooks'),
    plain(r'│   └── helpers.lua               eq, ok, match, tmpdir'),
    plain(r'├── doc/xyno-clipboard.txt        :help page'),
    plain(r'├── .github/workflows/ci.yml      pinned Neovim, specs, helptags'),
    plain(r'├── README.md · LICENSE · .stylua.toml · .gitignore'),
    ...sec(r'a short tour'),
    ...text(r'- lua/xyno_clipboard/init.lua is the provider. setup() resets state, registers the status '
        r'command, gates on Linux, asks detect.lua for a reason, probes Wayland once and installs '
        r'vim.g.clipboard with cache_enabled = 0.'),
    ...text(r'- lua/xyno_clipboard/detect.lua answers one question, is this a remote-capable session. '
        r'Four environment variables first (TMUX, SSH_TTY, SSH_CONNECTION, HERDR_PANE_ID), then a '
        r'walk of up to 16 ancestor processes through /proc looking for a name that contains herdr.'),
    ...text(r'- tests/specs/clipboard_spec.lua pins all of it with fakes: a fake process tree, shell '
        r'stubs for wl-copy and wl-paste that record their arguments, and a recording replacement '
        r'for the stdlib osc52 module.'),
    ...text(r'- tests/run.lua, tests/harness.lua and tests/helpers.lua are a runner, a 180-line '
        r'describe/it framework and a few assertions, so the suite needs nothing but Neovim.'),
    ...text(r'- doc/xyno-clipboard.txt is the :help page with tags.'),
    ...text(r'- .github/workflows/ci.yml installs a pinned, checksum-verified Neovim 0.12.5, runs the '
        r'specs and builds the help tags.'),
    ...sec(r'installing'),
    ...code('markdown', r'README.md · lines 17-23', r'''
```lua
{
  "xynorash/xyno-clipboard.nvim",
  lazy = false, -- the provider should exist before the first yank
  opts = {},
}
```
'''),
    ...text(r'Setting lazy = false matters. The provider has to exist before the first yank, and a '
        r'plugin that loads on demand would miss it. The plugin sets no global keymaps and defines '
        r'no autocmds; it works through the normal plus and star registers, for example with '
        r'clipboard=unnamedplus.'),
    ...sec(r'options and the runtime switch'),
    ...code('markdown', r'README.md · lines 27-32', r'''
```lua
require("xyno_clipboard").setup({
  commands = true, -- register :XynoClipboardStatus
  osc52 = true,    -- emit OSC 52 on copy
})
```
'''),
    ...code('markdown', r'README.md · lines 34-34', r'''
`vim.g.xyno_clipboard_osc52 = false` stops the OSC 52 emit at runtime (the local Wayland copy still happens). No global keymaps are set; the plugin has no dependencies on other plugins.
'''),
    ...text(r'The options table has two entries. commands decides whether :XynoClipboardStatus exists '
        r'and osc52 whether copy emits the sequence at all. The same switch exists at runtime as '
        r'vim.g.xyno_clipboard_osc52 = false, read on every copy, for stopping the OSC 52 '
        r'emit at runtime without restarting (the local Wayland copy still happens). Only '
        r'the exact value false turns it off.'),
    ...sec(r'how it decides'),
    ...code('markdown', r'README.md · lines 51-51', r'''
The provider is installed only when `$TMUX`, `$SSH_TTY`, `$SSH_CONNECTION` or `$HERDR_PANE_ID` is set, or when an ancestor process (up to 16 levels, read from `/proc`) has a name containing `herdr`. Copy runs `wl-copy --sensitive --type text/plain` first when Wayland tools are present, then emits OSC 52. Paste uses `wl-paste --no-newline` in that case, otherwise an OSC 52 query that tmux or the terminal has to answer. Elsewhere nothing is installed.
'''),
    ...text(r'The order is the point. The environment variables are cheap and decide most sessions; the '
        r'/proc walk costs up to sixteen file reads and runs only when no variable has spoken. The '
        r'reason that fired is remembered and shown by :XynoClipboardStatus, along with the exact '
        r'provider name, so a surprising clipboard can be explained in one command. When the '
        r'session is not remote-capable, setup() records no tmux, ssh or herdr session detected and '
        r'installs nothing.'),
    ...sec(r'honest about platforms'),
    ...code('markdown', r'README.md · lines 53-56', r'''
## Platforms

- Linux: covered by the specs in this repository (`nvim -l tests/run.lua`).
- Windows and macOS: Linux only by design. `setup()` returns early without installing anything. In xynovim's own CI this module was skipped on both, so nothing about it is demonstrated there.
'''),
    ...text(r'Linux is covered by the specs in this repository. On Windows and macOS setup() returns at '
        r'the first gate, because the herdr detection reads /proc and because an OSC 52 paste would '
        r'replace native providers such as win32yank and pbcopy with a query many terminals never '
        r'answer. The README is careful not to claim more: in xynovim’s own CI the module was '
        r'skipped on both systems, so nothing about those is demonstrated.'),
    ...sec(r'where it came from'),
    ...code('markdown', r'README.md · lines 58-60', r'''
## Extracted from xynovim

This is the clipboard module of my Neovim config, [xynovim](https://github.com/xynorash/xynovim), published on its own. Differences: the provider is named `XynoClipboard`, the runtime switch is `vim.g.xyno_clipboard_osc52`, and `setup(opts)`, `status()` and `:XynoClipboardStatus` are new.
'''),
    ...text(r'It began as lua/config/remote_clipboard.lua in the xynovim config, added on 2026-09-02 in '
        r'the migration to a LazyVim base. Its history there is short and each step is a lesson: '
        r'the gate was reordered cheapest-first on 2026-09-03 (f35b4f6), the names were changed '
        r'when Omarchy support was removed on 2026-10-13 (e874f9f), and a Linux guard was added on '
        r'2026-10-16 (ff1c8fa) when the config began to run on Windows and macOS. When it was '
        r'published it kept the logic and changed the surface: the provider is called '
        r'XynoClipboard, the runtime switch is vim.g.xyno_clipboard_osc52, and setup(opts), '
        r'status() and the status command are new.'),
    ...sec(r'try it'),
    ...text(r'- Run the specs with nvim -l tests/run.lua. The last line is RESULT passed=N failed=N '
        r'skipped=N and the exit code is non-zero on any failure.'),
    ...text(r'- Inside tmux, run :XynoClipboardStatus to see which signal fired.'),
    ...text(r'- Open :help xyno-clipboard for the manual.'),
  ],
);
