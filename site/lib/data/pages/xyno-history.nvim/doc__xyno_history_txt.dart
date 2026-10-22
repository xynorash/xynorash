import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-history.nvim/doc/xyno-history.txt',
  lines: [
    cm('--', r'──────────────────────────────────────────'),
    cm('--', r'xyno-history.txt — the :help page'),
    cm('--', r'ten sections, from the idea to how to recover without the plugin'),
    cm('--', r'──────────────────────────────────────────'),
    kv(r'role', r'Vim help file, :help xyno-history'),
    kv(r'format', r'Neovim help syntax, textwidth 78'),
    kv(r'size', r'182 lines, 10 sections'),
    kv(r'checked by', r'tests/e2e/smoke.lua builds the tags and opens :help xyno-history and xyno-history-api'),
    kv(r'history', r'added in 40b8c53 (2026-10-22, Add README, help file and CI workflow)'),
    ...sec(r'why this file exists'),
    ...para('--', r'The module has three commands, four options, a public Lua API and a storage format. The '
        r'README gives the tour; the help file is the reference that a user opens while working. Its '
        r'contents list has ten entries, covering both someone using the commands and someone who '
        r'may need to recover data by hand.'),
    ...sec(r'introduction, requirements, options'),
    ...code('text', r'doc/xyno-history.txt · lines 1-66', r'''
*xyno-history.txt*  Local History for Neovim: snapshots of the worktree in private git refs

                          xyno-history.nvim

==============================================================================
CONTENTS                                                    *xyno-history-contents*

  1. Introduction ............................. |xyno-history|
  2. Requirements ............................. |xyno-history-requirements|
  3. Setup and options ........................ |xyno-history-setup|
  4. Commands ................................. |xyno-history-commands|
  5. Keymaps .................................. |xyno-history-keymaps|
  6. Lua API .................................. |xyno-history-api|
  7. How it works ............................. |xyno-history-how|
  8. Recovering without the plugin ............ |xyno-history-recover|
  9. Platforms ................................ |xyno-history-platforms|
 10. License and origin ....................... |xyno-history-license|

==============================================================================
1. INTRODUCTION                                                    *xyno-history*

xyno-history.nvim takes a snapshot of the whole worktree on every save and
keeps it in private git refs (refs/lochist/<branch>). Deleted files,
`git reset --hard` and edits that |undo| cannot bring back stay recoverable.
The real index, the stash and the branches are never touched.

The idea is inspired by the Local History of JetBrains IDEs, which I still use.
This plugin is independent and not affiliated with JetBrains.

==============================================================================
2. REQUIREMENTS                                            *xyno-history-requirements*

  - Neovim 0.12 or newer.
  - `git` in $PATH. Files must live in a git worktree (a `.git` is found
    upward from the file).
  - Optional: an auto-save plugin that fires `User AutoSaveWritePost` with
    `data.saved_buffer` (auto-save.nvim does). Plain |:write| is always
    covered through |BufWritePost|.

==============================================================================
3. SETUP AND OPTIONS                                            *xyno-history-setup*

>lua
    require("xyno_history").setup({
      commands = true,        -- register :LocalHistory, :LocalHistoryRestore, :LocalHistoryPrune
      keymaps = false,        -- false | true | { browse = lhs, restore = lhs, prune = lhs }
      max_bytes = nil,        -- per-file cap in bytes; nil = 10 MB; <= 0 = no cap
      max_total_bytes = nil,  -- budget of one snapshot; nil = 200 MB; <= 0 = none
    })
<

                                                            *xyno-history-opts*
commands          boolean, default true. Register the user commands.
keymaps           false (default): no global keymap is set. true maps
                  `<leader>gH` to |:LocalHistory|. A table maps each of
                  "browse", "restore" and "prune" to the left-hand side you
                  give. See |xyno-history-keymaps|.
max_bytes         Untracked or modified files bigger than this are left out
                  of a snapshot (one INFO notice per file). Default 10 MB.
max_total_bytes   When the files that passed the per-file cap still add up to
                  more than this, the largest are left out until it fits.
                  Default 200 MB.

setup() registers the autocommands (|BufWritePost|, `User AutoSaveWritePost`,
|VimLeavePre|) in the group `xyno_history`. Calling it again replaces them.

'''),
    ...para('--', r'The introduction names the three things the plugin brings back: deleted files, git reset '
        r'--hard, and edits that undo cannot recover. It says in one sentence what is never '
        r'touched, the real index, the stash and the branches. The JetBrains acknowledgement is '
        r'repeated here, as in the README. Requirements say that a git worktree is found by '
        r'searching upward for a .git, and that the auto-save integration is optional, with plain '
        r'write always covered through BufWritePost. The options block is a table of the four '
        r'settings with the exact meaning of nil and zero.'),
    ...sec(r'commands and keymaps'),
    ...code('text', r'doc/xyno-history.txt · lines 67-108', r'''
==============================================================================
4. COMMANDS                                                *xyno-history-commands*

                                                                *:LocalHistory*
:LocalHistory           Pick a snapshot of the current file (newest first,
                        up to 100, "<age>  <message>") and diff against it in
                        a vertical scratch buffer.

                                                         *:LocalHistoryRestore*
:LocalHistoryRestore    Pick a snapshot and replace the current buffer's text
                        with that version after a confirmation. The file on
                        disk and the index are untouched; the buffer is left
                        modified (undo with `u`).

                                                           *:LocalHistoryPrune*
:LocalHistoryPrune[!] [N | Nd]
                        Drop old snapshots of every branch of the current
                        repository. `N` keeps the newest N per branch, `Nd`
                        keeps the last N days (default 30d). The newest
                        snapshot always stays. Unreachable objects older than
                        an hour are then collected with `git gc`. With [!]
                        every unreachable object is collected (`--prune=now`),
                        also younger ones and other tools' dangling commits.

==============================================================================
5. KEYMAPS                                                  *xyno-history-keymaps*

No keymap is set by default. With lazy.nvim, define them in the plugin spec:
>lua
    {
      "xynorash/xyno-history.nvim",
      event = "VeryLazy",
      opts = {},
      keys = {
        { "<leader>gH", "<cmd>LocalHistory<cr>", desc = "Local history (file)" },
        { "<leader>gR", "<cmd>LocalHistoryRestore<cr>", desc = "Local history restore" },
      },
    }
<
Or let setup() map them: `keymaps = true` or
`keymaps = { browse = "<leader>gH", restore = "<leader>gR" }`.

'''),
    ...para('--', r'Each command has its own tag, so :help :LocalHistoryPrune works. The keymap section shows '
        r'both ways of binding keys: through the plugin manager’s keys, and through the keymaps '
        r'option, and it explains that true maps only the browse action.'),
    ...sec(r'the Lua API, argument by argument'),
    ...code('text', r'doc/xyno-history.txt · lines 109-139', r'''
==============================================================================
6. LUA API                                                       *xyno-history-api*

All functions are in the module `xyno_history`.

setup({opts})                                          *xyno_history.setup()*
    See |xyno-history-setup|.

snapshot({opts})                                    *xyno_history.snapshot()*
    Snapshot the worktree that contains `opts.path` (default: the current
    buffer). Fields of {opts}:
      path     string   a file or directory inside the worktree
      force    boolean  ignore the 60 s throttle window
      label    string   commit message (default "autosave")
      done     fun(commit?: string)  called once; `commit` is nil when nothing
               changed or the snapshot failed
    A non-forced call inside the throttle window is not lost: one trailing
    snapshot runs when the window ends.

browse()                                              *xyno_history.browse()*
    What |:LocalHistory| does.

restore()                                            *xyno_history.restore()*
    What |:LocalHistoryRestore| does.

prune({arg}, {now})                                    *xyno_history.prune()*
    What |:LocalHistoryPrune| does; {arg} is "N" or "Nd", {now} the bang.

config                                               *xyno_history.config*
    The options table; setup() merges its argument into it.

'''),
    ...para('--', r'This section documents snapshot() field by field: path, force, label (default autosave) '
        r'and done, which is called once and receives nil when nothing changed or the snapshot '
        r'failed. The last sentence of that entry is the contract of the throttle, that a '
        r'non-forced call inside the window is not lost. prune takes the argument and the bang, and '
        r'config is described as the table that setup merges into. The spec uses exactly these '
        r'fields: the done callback is how snap in the spec waits for the asynchronous work.'),
    ...sec(r'how it works, and the numbers'),
    ...code('text', r'doc/xyno-history.txt · lines 140-156', r'''
==============================================================================
7. HOW IT WORKS                                                *xyno-history-how*

A snapshot is a commit on `refs/lochist/<key>` whose tree is the whole
worktree: untracked files included, `.gitignore` and the global ignore file
respected, `target/` (the root and workspace members) excluded through
`.git/info/exclude`. It is built with `git add -A` into a private index file
(`.git/lochist-index.<pid>`, one per Neovim process), then `write-tree`,
`commit-tree` and a compare-and-swap `update-ref`, so concurrent Neovim
instances never overwrite each other's snapshot.

<key> is the branch name with `%` written as `%25` and `/` as `%2F`, or
`%detached-<short sha>` for a detached HEAD. Saves are throttled to one
snapshot per 60 seconds; a failed snapshot is retried once after 10 seconds. A
git that hangs is killed after 30 seconds. On exit, a pending or in-flight
snapshot is taken synchronously within a 5 second budget.

'''),
    ...para('--', r'The section is a compact statement of the algorithm and its constants: sixty seconds of '
        r'throttle, one retry after ten seconds, thirty seconds before a hung git is killed, five '
        r'seconds at exit. Three of the four are constants at the top of init.lua; the 30 seconds is a literal in the snapshot watchdog. It also states the '
        r'branch-key encoding so that a user who looks at refs/lochist/ understands the names with '
        r'percent signs.'),
    ...sec(r'recovering without the plugin'),
    ...code('text', r'doc/xyno-history.txt · lines 157-175', r'''
==============================================================================
8. RECOVERING WITHOUT THE PLUGIN                           *xyno-history-recover*

Without the plugin, the snapshots are plain git:
>
    git log refs/lochist/main
    git restore --source=refs/lochist/main --worktree -- path/to/file
<
They stay in the repository until pruned. `git push --mirror` would transfer
them, so push explicit refs if you do not want that.

==============================================================================
9. PLATFORMS                                                *xyno-history-platforms*

Linux: tested by the specs in this repository (`nvim -l tests/run.lua`).
Windows: no evidence. The original spec was skipped there.
macOS: not tested in this repository. See the README for what the original
configuration's CI showed.

'''),
    ...para('--', r'This section exists because the storage is the selling point. It gives the two git '
        r'commands, warns that git push --mirror would transfer the lochist refs and suggests '
        r'pushing explicit refs, and ends with the platform statement of the README in short form. '
        r'The final section gives the licence and the origin.'),
    ...sec(r'history'),
    ...pt('--', r'40b8c53', r'2026-10-22: added with the README and the workflow.'),
  ],
);
