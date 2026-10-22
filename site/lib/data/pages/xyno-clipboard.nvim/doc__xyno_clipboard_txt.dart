import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-clipboard.nvim/doc/xyno-clipboard.txt',
  lines: [
    cm('--', r'──────────────────────────────────────────'),
    cm('--', r'xyno-clipboard.txt — the :help page'),
    cm('--', r'tags, a contents list and a section per public surface'),
    cm('--', r'──────────────────────────────────────────'),
    kv(r'role', r'Vim help file, :help xyno-clipboard'),
    kv(r'format', r'Neovim help syntax, textwidth 78, tags in asterisks'),
    kv(r'size', r'88 lines, 8 sections'),
    kv(r'built by', r'CI runs helptags doc, so a malformed tag fails the build'),
    kv(r'history', r'added with the README in c7f1b25 (2026-10-22, Add README and help)'),
    ...sec(r'why this file exists'),
    ...para('--', r'A Neovim plugin that is meant to be installed by strangers has to answer :help. The '
        r'README is for people on GitHub; this file is for the person inside the editor who typed '
        r':help xyno-clipboard. It repeats the README’s facts in the structure Vim users expect: a '
        r'heading line carrying the file tag, a numbered contents table whose entries link to '
        r'section tags, and one section for each thing a user can touch. Both documents were '
        r'written in the same commit, c7f1b25, and the two cover the same facts.'),
    ...sec(r'the header and contents'),
    ...code('text', r'doc/xyno-clipboard.txt · lines 1-13', r'''
*xyno-clipboard.txt*  Clipboard provider for sessions that reach another machine

==============================================================================
CONTENTS                                                *xyno-clipboard-contents*

  1. Introduction ........................................ |xyno-clipboard|
  2. Requirements ........................................ |xyno-clipboard-requirements|
  3. Setup and options ................................... |xyno-clipboard-setup|
  4. Commands ............................................ |xyno-clipboard-commands|
  5. Lua API ............................................. |xyno-clipboard-api|
  6. Keys ................................................ |xyno-clipboard-keys|
  7. How it works ........................................ |xyno-clipboard-how|
  8. Platforms ........................................... |xyno-clipboard-platforms|
'''),
    ...para('--', r'The first line carries the help tag and a one-line title: the asterisk-delimited word is '
        r'what makes :help xyno-clipboard.txt work after helptags has run. The dot leaders in the '
        r'contents are plain padding, and the pipe-delimited names are links to the section tags '
        r'defined below, which Vim follows with control-bracket. There is one tag per section, '
        r'named by a consistent prefix, xyno-clipboard-, so that a user can complete on the prefix.'),
    ...sec(r'the introduction states the contract'),
    ...code('text', r'doc/xyno-clipboard.txt · lines 15-22', r'''
==============================================================================
1. Introduction                                                  *xyno-clipboard*

xyno-clipboard installs a |g:clipboard| provider when Neovim runs inside tmux,
an SSH session or a herdr pane: every copy is emitted as OSC 52, so the yank
reaches the machine you sit at. Outside such a session it does nothing and the
default provider detection stays untouched.

'''),
    ...para('--', r'The sentence worth keeping is the last one: outside such a session it does nothing and '
        r'the default provider detection stays untouched. That is a promise about absence and it is '
        r'the thing a user most needs to know before enabling a plugin that replaces a clipboard '
        r'provider. It is true in the code because setup() returns before touching vim.g.clipboard '
        r'when the detection says nothing.'),
    ...sec(r'requirements, setup and the runtime variable'),
    ...code('text', r'doc/xyno-clipboard.txt · lines 23-46', r'''
==============================================================================
2. Requirements                                         *xyno-clipboard-requirements*

  - Neovim 0.12 or newer (uses `vim.ui.clipboard.osc52`).
  - Linux. On other systems setup() returns without installing anything.
  - Optional: `wl-copy` and `wl-paste` plus a `WAYLAND_DISPLAY`, so that
    content copied in other applications stays pasteable.

==============================================================================
3. Setup and options                                         *xyno-clipboard-setup*

>lua
    require("xyno_clipboard").setup({
      commands = true, -- register :XynoClipboardStatus
      osc52 = true,    -- emit OSC 52 on copy
    })
<
                                                          *g:xyno_clipboard_osc52*
Setting `vim.g.xyno_clipboard_osc52 = false` at any time stops the OSC 52
emit of the installed provider (the local Wayland copy still happens). The
variable is checked on every copy.

No global keymaps are set. The plugin has no dependencies on other plugins.

'''),
    ...para('--', r'Requirements are written as facts, not hopes: Neovim 0.12 because the module requires '
        r'vim.ui.clipboard.osc52, Linux because anything else returns, and Wayland tools as an '
        r'option. The variable gets its own tag, g:xyno_clipboard_osc52, so that :help '
        r'g:xyno_clipboard_osc52 lands on it. The code block in the setup section uses the Neovim '
        r'help fence for a Lua block, a greater-than sign followed by the language, closed by a '
        r'less-than sign, which makes the example highlighted in the help buffer. The sentence that '
        r'the variable is checked on every copy matches the code in init.lua, where the check sits '
        r'inside the returned copy function and not at setup.'),
    ...sec(r'commands and API'),
    ...code('text', r'doc/xyno-clipboard.txt · lines 47-63', r'''
==============================================================================
4. Commands                                               *xyno-clipboard-commands*

                                                          *:XynoClipboardStatus*
:XynoClipboardStatus    Notify whether the provider is active and why (which
                        of TMUX, SSH_TTY, SSH_CONNECTION, HERDR_PANE_ID or a
                        herdr ancestor process), or why it is inactive.

==============================================================================
5. Lua API                                                    *xyno-clipboard-api*

require("xyno_clipboard").setup({opts})                 *xyno_clipboard.setup()*
    Detect the session and install |g:clipboard| when it is remote-capable.

require("xyno_clipboard").status()                      *xyno_clipboard.status()*
    Returns a table `{ active = bool, reason = string|nil, skipped = string|nil }`.

'''),
    ...para('--', r'The command has a tag with its colon form and a description column aligned by hand. The '
        r'API section documents the return shape of status() exactly, including the nil cases: '
        r'active is a boolean, reason is a string when active, skipped is a string when inactive. '
        r'Those are the same fields the spec asserts with H.eq.'),
    ...sec(r'keys, how it works, platforms'),
    ...code('text', r'doc/xyno-clipboard.txt · lines 64-88', r'''
==============================================================================
6. Keys                                                      *xyno-clipboard-keys*

The plugin defines no keymaps and has none to suggest: it works through the
normal `"+` and `"*` registers, for example with `clipboard=unnamedplus`.

==============================================================================
7. How it works                                              *xyno-clipboard-how*

The session counts as remote-capable when `$TMUX`, `$SSH_TTY`,
`$SSH_CONNECTION` or `$HERDR_PANE_ID` is set, or when one of the up to 16
nearest ancestor processes has a name containing "herdr" (read from /proc,
only when no variable decided). Copy: optionally `wl-copy --sensitive --type
text/plain` (with `--primary` for the `*` register), then the OSC 52 emit.
Paste: `wl-paste --no-newline` when Wayland and both tools are present,
otherwise an OSC 52 query. The provider is installed with `cache_enabled = 0`
under the name `XynoClipboard`.

==============================================================================
8. Platforms                                              *xyno-clipboard-platforms*

Linux: covered by the specs in this repository. Windows and macOS: setup()
returns early by design; nothing is installed and nothing is tested there.

 vim:tw=78:ts=8:ft=help:norl:
'''),
    ...para('--', r'The Keys section is an unusual thing to include: it exists to say that there are none, '
        r'which is a statement a user wants to read before wondering which mapping to override. The '
        r'how-it-works section compresses the detection order and the copy and paste commands into '
        r'one paragraph, including the flag --primary for the star register and cache_enabled = 0. '
        r'The Platforms section ends with the sentence that on Windows and macOS nothing is tested, '
        r'which matches the README. The final line is the standard modeline, textwidth 78, tab stop '
        r'8, help filetype and no reflow of the text.'),
    ...sec(r'what to take from it'),
    ...pt('--', r'A help file is a test target too', r'CI runs helptags doc and quits, so a duplicate or malformed tag would fail there. The '
        r'workflow does not check the content; the content is kept consistent by being written '
        r'together with the README.'),
    ...pt('--', r'Docs follow code', r'each claim in the help (the 16-level bound, the register flags, the cache setting) can be '
        r'found in init.lua or detect.lua.'),
  ],
);
