import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-history.nvim/README.md',
  summary: r'Local History for Neovim: every throttled save snapshotted into private git refs',
  repo: 'xyno-history.nvim',
  fallbackStars: 0,
  fallbackPushed: '2026-10-22',
  lines: [
    heading(r'# xyno-history.nvim'),
    blank,
    ...text(r'Local History for Neovim. Every throttled save is snapshotted into private git refs, so a '
        r'deleted file, a git reset --hard or an edit by a tool that rewrote half your tree can be '
        r'recovered, with a picker and a diff, or with two plain git commands if the plugin is '
        r'gone. The real index, the stash and your branches are never touched. One Lua module of '
        r'844 lines, no dependencies except git.'),
    kv(r'language', r'Lua, Neovim 0.12+, git in PATH'),
    kv(r'storage', r'commits on refs/lochist/<encoded branch>; private index per Neovim process'),
    kv(r'commands', r':LocalHistory, :LocalHistoryRestore, :LocalHistoryPrune[!]'),
    kv(r'tests', r'65 specs against real git with injected faults, plus a lazy.nvim smoke test'),
    kv(r'history', r'3 commits, all on 2026-10-22; the module itself began on 2026-10-09 in xynovim'),
    kv(r'origin', r'extracted from xynovim, lua/config/local_history.lua'),
    ...sec(r'the problem'),
    ...text(r'undofile saves your undo tree per file. It does not help when the file is gone, when git '
        r'reset --hard moved the whole worktree, or when an agent or a formatter rewrote forty '
        r'files and you want yesterday’s version of one of them. JetBrains IDEs have a feature '
        r'named Local History for exactly this, and the README says the author still uses them. The README says it was inspired by that feature and that the plugin is an '
        r'independent project, not affiliated with JetBrains.'),
    ...sec(r'the idea'),
    ...text(r'Put the history where the tools for it already are. Git can hold a commit that nobody '
        r'checks out, on a ref that nobody lists unless asked. So each snapshot is a commit on '
        r'refs/lochist/<branch> whose tree is the whole worktree, built with git add -A into a '
        r'private index file, then write-tree, commit-tree and an update-ref that only succeeds if '
        r'nobody moved the ref meanwhile. Nothing in the user’s repository changes: no index write, '
        r'no stash, no branch. And because the data is ordinary git, recovery does not need the '
        r'plugin.'),
    ...sec(r'the shape of the repository'),
    plain(r'xyno-history.nvim/'),
    plain(r'├── lua/xyno_history/init.lua      the module: snapshot, refs, throttle, prune, commands'),
    plain(r'├── tests/'),
    plain(r'│   ├── history_spec.lua           65 tests, fake git, fake clock, child nvims'),
    plain(r'│   ├── e2e/init.lua               minimal init that loads the plugin with lazy.nvim'),
    plain(r'│   ├── e2e/smoke.lua              commands, :help, and a real :write'),
    plain(r'│   ├── run.lua                    headless runner with OS-aware skips'),
    plain(r'│   ├── harness.lua                describe / it / hooks'),
    plain(r'│   └── helpers.lua                assertions, temp dirs, waiting'),
    plain(r'├── doc/xyno-history.txt           :help xyno-history, 10 sections'),
    plain(r'├── .github/workflows/ci.yml       pinned Neovim, specs, pinned lazy.nvim, smoke'),
    plain(r'└── README.md · LICENSE · .gitignore'),
    ...sec(r'a tour of the module'),
    ...text(r'- Snapshots. snapshot() resolves the worktree, takes the per-repository state machine '
        r'through throttle, running, pending and trailing timer, then builds the tree and commits '
        r'it. It is asynchronous through vim.system and becomes synchronous under a five second '
        r'budget when Neovim exits.'),
    ...text(r'- Refs. A branch name is encoded (percent and slash escaped) so that foo and foo/bar '
        r'never clash as a file and a directory; a detached HEAD gets its own namespace; old-style '
        r'refs are migrated.'),
    ...text(r'- Safety. A private index per process, leftovers of dead processes cleaned, stale locks '
        r'removed after a minute, a watchdog on hung git, compare-and-swap with jittered retries.'),
    ...text(r'- Size. A 10 MB per-file cap and a 200 MB per-snapshot budget keep .git from growing by '
        r'accident; both can be changed or disabled.'),
    ...text(r'- Browse, restore, prune. A picker over the file’s snapshots, a vertical diff, a restore '
        r'into the buffer (undoable), and a prune that rewrites the chain with fast-import and then '
        r'runs git gc.'),
    ...sec(r'install'),
    ...code('markdown', r'README.md · lines 23-33', r'''
```lua
{
  "xynorash/xyno-history.nvim",
  event = "VeryLazy", -- setup() registers the autocmds and commands, so load it early
  opts = {},
  keys = {
    { "<leader>gH", "<cmd>LocalHistory<cr>", desc = "Local history (file)" },
    { "<leader>gR", "<cmd>LocalHistoryRestore<cr>", desc = "Local history restore" },
  },
}
```
'''),
    ...text(r'Load it early. setup registers the save autocmds and the commands, so a plugin that loads '
        r'only when a key is pressed would miss every save before that. The README says it '
        r'directly: do not load it only through keys. The keys in the example are conveniences; '
        r'alternatively keymaps = true in the options maps <leader>gH to :LocalHistory (the code maps '
        r'only the browse action).'),
    ...sec(r'options'),
    ...code('markdown', r'README.md · lines 41-48', r'''
```lua
{
  commands = true,        -- :LocalHistory, :LocalHistoryRestore, :LocalHistoryPrune
  keymaps = false,        -- false | true | { browse = lhs, restore = lhs, prune = lhs }
  max_bytes = nil,        -- per-file cap in bytes (nil: 10 MB; <= 0: no cap)
  max_total_bytes = nil,  -- cap of one snapshot (nil: 200 MB; <= 0: none)
}
```
'''),
    ...text(r'No global keymap is set unless asked. The two caps are in bytes, nil means the default '
        r'and a value of zero or less disables the cap.'),
    ...sec(r'commands'),
    ...code('markdown', r'README.md · lines 54-60', r'''
| Command | What it does |
| --- | --- |
| `:LocalHistory` | Pick a snapshot of the current file and diff against it in a vertical scratch buffer. |
| `:LocalHistoryRestore` | Pick a snapshot and replace the buffer text with it (buffer left modified, `u` undoes it; disk and index untouched). |
| `:LocalHistoryPrune[!] [N \| Nd]` | Keep the newest N snapshots per branch, or the last N days (default `30d`), then `git gc`. With `!`, collect every unreachable object (`--prune=now`). |

Lua: `require("xyno_history").snapshot({ path?, force?, label?, done? })`, `.browse()`, `.restore()`, `.prune(arg, now)`. See `:help xyno-history`.
'''),
    ...text(r'The restore command replaces the text of the buffer and leaves it modified, so u undoes '
        r'it and the disk and the index are untouched. Prune keeps the newest N snapshots per '
        r'branch, or the last N days (default 30d), always keeps at least the newest, and finishes '
        r'with git gc; the bang form collects every unreachable object.'),
    ...sec(r'how it works'),
    ...code('markdown', r'README.md · lines 64-64', r'''
Each snapshot is a commit on `refs/lochist/<branch>` whose tree is the whole worktree: untracked files included, `.gitignore` respected, `target/` left out. It is built with a private index file per Neovim process (`.git/lochist-index.<pid>`) and a compare-and-swap `update-ref`, so concurrent instances never overwrite each other. Saves are throttled to one snapshot per minute and the last save of a window is never lost (a trailing snapshot, and one more on exit). Files over `max_bytes` stay out, and the largest files of a snapshot are dropped beyond `max_total_bytes`.
'''),
    ...text(r'Two details in that paragraph are the heart of the design. The private index lets many '
        r'Neovims snapshot the same repository without fighting over index.lock. The '
        r'compare-and-swap update-ref lets them do so without overwriting each other. And the '
        r'throttle never loses the last save: there is a trailing snapshot at the end of the '
        r'window, and one more on exit.'),
    ...sec(r'recovering without the plugin'),
    ...code('markdown', r'README.md · lines 68-71', r'''
```sh
git log refs/lochist/main
git restore --source=refs/lochist/main --worktree -- path/to/file
```
'''),
    ...text(r'This is the promise that makes the storage choice safe. If the plugin is removed, nothing '
        r'is stranded in a private format. The snapshots stay in the repository until pruned.'),
    ...sec(r'platforms, stated carefully'),
    ...code('markdown', r'README.md · lines 77-79', r'''
- Linux: tested by the specs in this repository (`nvim -l tests/run.lua`, 65 tests, plus a lazy.nvim smoke test in CI). The specs use bash stubs and `kill -0`, so they run on Linux and macOS only.
- Windows: no evidence at all. In the original xynovim CI this code's spec was skipped on Windows, so nothing about it is demonstrated there.
- macOS: not tested here. In xynovim's CI the original spec was not skipped on macOS and ran in the one fully green macOS run; other macOS runs there were flaky or failed elsewhere, so I do not claim it works.
'''),
    ...text(r'The spec declares linux and macos because it uses bash stubs and kill -0. The README then '
        r'refuses to claim macOS: in xynovim’s CI the original spec was not skipped on macOS and '
        r'ran in the one fully green macOS run, but other macOS runs there were flaky or failed '
        r'elsewhere. Windows: no evidence at all.'),
    ...sec(r'where it came from'),
    ...text(r'The module began as lua/config/local_history.lua in xynovim on 2026-10-09 (8e212cf and '
        r'4fdd3fa, both wip commits). In the following days it was hardened by the review and '
        r'field-test commits: ac38272 and 0494b52, then b65284f on 2026-10-13 with the exit '
        r'snapshot, the per-process index, the size cap and prune; 7ac2a38 with the '
        r'build-after-parent fix for concurrent editors; five rounds of loop fixes through '
        r'2026-10-14; and 0247401 with the JetBrains positioning sentence. The extraction on '
        r'2026-10-22 kept the code and changed the namespace, the setup options and the git author '
        r'name.'),
    ...sec(r'try it'),
    ...text(r'- nvim -l tests/run.lua runs the 65 specs. Linux or macOS with bash, git and sleep.'),
    ...text(r'- XYNO_LAZY=/path/to/lazy.nvim nvim --headless -u tests/e2e/init.lua -c "luafile '
        r'tests/e2e/smoke.lua" runs the smoke test.'),
    ...text(r'- In a repository, save a file, then :LocalHistory.'),
  ],
);
