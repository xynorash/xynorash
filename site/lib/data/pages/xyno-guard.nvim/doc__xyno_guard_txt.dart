import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-guard.nvim/doc/xyno-guard.txt',
  lines: [
    cm('--', r'──────────────────────────────────────────'),
    cm('--', r'xyno-guard.txt — the :help page'),
    cm('--', r'precise about what each function guarantees'),
    cm('--', r'──────────────────────────────────────────'),
    kv(r'role', r'Vim help file, :help xyno-guard'),
    kv(r'format', r'Neovim help syntax, textwidth 78'),
    kv(r'size', r'137 lines, 8 sections'),
    kv(r'checked by', r'CI runs helptags and then asks Neovim to open :help xyno-guard'),
    kv(r'history', r'added in 37ca0c1 (2026-10-22, Add README, help page and CI); amended in 9c3e9ec'),
    ...sec(r'why this file exists'),
    ...para('--', r'A guard plugin is only useful if its user can tell exactly what it will and will not do. '
        r'The help page is where the author pins that down in the vocabulary of the editor: tags a '
        r'user can jump to, function signatures with {argument} notation, and the Neovim option '
        r'names in single quotes. It repeats what the README says and adds the precise API '
        r'descriptions that the README’s table only hints at.'),
    ...sec(r'header, contents, introduction'),
    ...code('text', r'doc/xyno-guard.txt · lines 1-39', r'''
*xyno-guard.txt*  Keep auto-save away from files it must never write

                                                                  *xyno-guard*

==============================================================================
CONTENTS                                                 *xyno-guard-contents*

  1. Introduction ........................ |xyno-guard-intro|
  2. Requirements ........................ |xyno-guard-requirements|
  3. Setup ............................... |xyno-guard-setup|
  4. Options ............................. |xyno-guard-options|
  5. Commands and keys ................... |xyno-guard-commands|
  6. API ................................. |xyno-guard-api|
  7. How it works ........................ |xyno-guard-how|
  8. Platforms ........................... |xyno-guard-platforms|

==============================================================================
1. INTRODUCTION                                             *xyno-guard-intro*

xyno-guard keeps auto-save away from files it must never write:

  - dependency and standard-library sources (`~/.cargo/registry`,
    `~/.cargo/git`, `~/.rustup`, and `$CARGO_HOME` / `$RUSTUP_HOME`), which
    are opened nomodifiable and readonly (buffers already loaded when
    `setup()` runs are locked too);
  - files that changed on disk behind the buffer's back (`git checkout`, a
    formatter in another pane, `sed -i`): the save is skipped and one
    warning is shown, instead of nvim's blocking W12 prompt;
  - deleted files, which auto-save must not recreate;
  - buffers that are not plain files, or are readonly.

It also writes the other modified buffers after an LSP edit that touched
files besides the current one (rename, file rename, code actions).

It works with any auto-save plugin that accepts a `condition` function. The
`AutoSaveWritePre` / `AutoSaveWritePost` hooks (|xyno-guard-how|) are the
user events of okuuva/auto-save.nvim.

Extracted from xynovim: https://github.com/xynorash/xynovim
'''),
    ...para('--', r'The introduction lists four things the guard keeps auto-save away from, and a fifth, '
        r'writing the other modified buffers after an LSP edit that touched other files. The '
        r'parenthesis on the first bullet was added by 9c3e9ec, the last commit, when buffers '
        r'already loaded at setup began to be locked as well: the doc and the README and the code '
        r'and a new spec all changed in one commit. The '
        r'last paragraph is honest about a coupling: the Pre and Post hooks are user events of '
        r'okuuva/auto-save.nvim, so the pattern names belong to that plugin.'),
    ...sec(r'setup and options'),
    ...code('text', r'doc/xyno-guard.txt · lines 48-71', r'''
==============================================================================
3. SETUP                                                     *xyno-guard-setup*

With lazy.nvim, wired to okuuva/auto-save.nvim: >lua

  {
    "okuuva/auto-save.nvim",
    event = { "InsertLeave", "TextChanged", "TextChangedI" },
    dependencies = { "xynorash/xyno-guard.nvim" },
    opts = function()
      require("xyno_guard").setup()
      return { condition = require("xyno_guard").can_save }
    end,
  }
<
`setup()` must run before buffers matter, and it is safe to call again.

==============================================================================
4. OPTIONS                                                 *xyno-guard-options*

`setup({opts})` takes a table. There are no options yet: the argument is
accepted so that later versions can add some. No keymaps are set (the plugin
defines none) and no commands are registered.

'''),
    ...para('--', r'The setup example is the lazy.nvim spec from the README, set apart with the greater-than '
        r'marker that Neovim help uses for a code block. The line after it makes a precise '
        r'statement: setup must run before buffers matter, and may be called again. The options '
        r'section says that setup takes a table with no options yet, so that later versions can add '
        r'some; the two sentences about no keymaps and no commands remove two questions a user '
        r'would ask.'),
    ...sec(r'commands, keys and the API'),
    ...code('text', r'doc/xyno-guard.txt · lines 73-107', r'''
5. COMMANDS AND KEYS                                      *xyno-guard-commands*

None. The guard works through autocmds (group `xyno_guard`) and the functions
in |xyno-guard-api|. A key for writing everything that may be written: >lua

  vim.keymap.set("n", "<leader>W", require("xyno_guard").save_all)
<
==============================================================================
6. API                                                         *xyno-guard-api*

                                                            *xyno-guard.setup()*
setup([{opts}])
    Install the autocmds (group `xyno_guard`) and record the disk state of the
    buffers that are already loaded.

                                                         *xyno-guard.can_save()*
can_save({buf})
    May buffer {buf} be written now? Use it as the auto-save plugin's
    `condition`. Returns false for non-file and readonly buffers, dependency
    sources, deleted files, and files whose mtime differs from the one
    recorded when the buffer was read or written (one warning per change).
    Returns true for a buffer that was never read or written by this nvim (it
    records the current state instead).

                                                    *xyno-guard.is_dependency()*
is_dependency({name})
    Is the file {name} below `~/.cargo/registry`, `~/.cargo/git`, `~/.rustup`,
    `$CARGO_HOME/registry`, `$CARGO_HOME/git` or `$RUSTUP_HOME`? The match is
    case-insensitive on Windows and macOS.

                                                         *xyno-guard.save_all()*
save_all()
    Write every loaded, modified, modifiable file buffer for which
    |xyno-guard.can_save()| is true. It uses a plain `:write` (events fire).

'''),
    ...para('--', r'There are no commands. The API section is the most valuable part of the file, because '
        r'each signature says what is returned in which case. can_save is described as false for '
        r'non-file and readonly buffers, dependency sources, deleted files, and files whose mtime '
        r'differs from the recorded one, with one warning per change, and true for a buffer never '
        r'read or written by this Neovim, which records the current state instead. That last '
        r'sentence documents the benefit-of-the-doubt branch of the code. is_dependency lists the '
        r'six roots and says the match is case-insensitive on Windows and macOS. save_all says it '
        r'uses a plain :write so events fire, which is the reason it does not use noautocmd.'),
    ...sec(r'how it works'),
    ...code('text', r'doc/xyno-guard.txt · lines 109-126', r'''
7. HOW IT WORKS                                                 *xyno-guard-how*

  - |BufReadPost|, |BufWritePost|, |BufFilePost| and |FileChangedShellPost|
    record the file's mtime in `b:xyno_guard_stamp`.
  - `can_save()` compares it with the disk before every save.
  - auto-save checks its `condition` when the event fires but writes up to a
    second later. So on `User AutoSaveWritePre` the guard checks again and, for
    a refused write, sets 'buftype' to "nowrite" (the write then fails
    harmlessly); `User AutoSaveWritePost` restores it. A listener of
    `AutoSaveWritePost` can tell a refused write: the buffer is still
    'modified'.
  - |FileChangedShell| never prompts: an unmodified buffer is reloaded (or
    asked about when 'autoread' is off), a modified or deleted one is left
    alone with one warning. Detecting the change is nvim's job (|:checktime|).
  - After the first |LspAttach|, `vim.lsp.util.apply_workspace_edit` is wrapped:
    when the edit touches a file other than the current buffer, `save_all()`
    runs once the edit is applied.

'''),
    ...para('--', r'Five bullets, one per mechanism, with the help links to the Neovim events (BufReadPost, '
        r'FileChangedShell, LspAttach, :checktime) so a reader can follow them. The third bullet '
        r'gives the nowrite trick in a sentence and says how the Post event restores the option. '
        r'The fourth makes the division of labour explicit: detecting the change is Neovim’s job '
        r'and the guard only answers the prompt.'),
    ...sec(r'platforms'),
    ...code('text', r'doc/xyno-guard.txt · lines 128-137', r'''
8. PLATFORMS                                              *xyno-guard-platforms*

Linux: tested by the specs in this repository. Windows and macOS: the
original spec for this code in xynovim was not among the files its platforms
workflow skipped there, and that workflow passed; the specs of this repository
have not been run on either, so treat both as unverified. Path comparison is
case-insensitive and slash-normalised on both. The `~/.cargo` and `~/.rustup`
roots are Rust-specific.

vim:tw=78:ts=8:ft=help:norl:
'''),
    ...para('--', r'The platform section is a model of calibrated claims. Linux is tested here. For Windows '
        r'and macOS it says the original spec in xynovim was not among the files its platforms '
        r'workflow skipped and that workflow passed, that the specs in this repository were not run '
        r'on either, and that readers should treat both as unverified. Path comparison is stated as '
        r'case-insensitive and slash-normalised there, and the Rust-specific roots are noted last.'),
    ...sec(r'history'),
    ...pt('--', r'37ca0c1', r'2026-10-22: added together with the README and the CI workflow.'),
    ...pt('--', r'9c3e9ec', r'2026-10-22: one parenthesis added to the first bullet, about buffers already loaded when '
        r'setup runs.'),
  ],
);
