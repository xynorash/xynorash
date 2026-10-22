import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-guard.nvim/README.md',
  summary: r'Keeps auto-save away from dependency sources, files changed on disk and deleted files',
  repo: 'xyno-guard.nvim',
  fallbackStars: 0,
  fallbackPushed: '2026-10-22',
  lines: [
    heading(r'# xyno-guard.nvim'),
    blank,
    ...text(r'Auto-save is wonderful until it writes the wrong thing. xyno-guard.nvim is the guard you '
        r'put in front of the write: it keeps auto-save out of dependency and standard-library '
        r'sources, refuses to overwrite a file that changed on disk behind the buffer’s back, will '
        r'not recreate a file that was deleted, and after an LSP rename or code action it writes '
        r'the other files the edit touched, so disk and undo stay consistent. One Lua file, 258 '
        r'lines, no dependencies, works with any auto-save plugin that accepts a condition function.'),
    kv(r'language', r'Lua, Neovim 0.12+'),
    kv(r'shape', r'one module with four public functions and one autocmd group'),
    kv(r'size', r'258 lines of plugin code, 797 lines of specs'),
    kv(r'tests', r'40 it() blocks (the README says 39), the auto-save ones skip when the plugin is absent'),
    kv(r'history', r'4 commits, all on 2026-10-22'),
    kv(r'origin', r'extracted from xynovim, lua/config/disk_guard.lua'),
    ...sec(r'the problem'),
    ...text(r'The README’s own words are the best statement of it. Using auto-save all day while '
        r'writing Rust, three things kept going wrong: a debounced save landing in '
        r'~/.cargo/registry or the standard library sources that were only being read, a save '
        r'overwriting a file that git checkout or a formatter had just changed on disk, and Neovim '
        r'stopping at a blocking W12 prompt, Do you really want to write to it, that swallowed '
        r'keystrokes. None of these is exotic. All three are the result of an automatic action that '
        r'does not know what you know.'),
    ...sec(r'the idea'),
    ...text(r'Ask before every write, and ask twice. can_save(buf) is a predicate: it returns false for '
        r'buffers with a buftype (non-file) and readonly buffers, for dependency sources, for deleted files and for files '
        r'whose modification time no longer matches the one recorded when the buffer was last read '
        r'or written. It is passed to the auto-save plugin as its condition. But auto-save checks '
        r'the condition when the event fires and writes up to a second later, so the guard listens '
        r'to the plugin’s Pre event and checks again; if the answer changed it flips the buffer to '
        r'nowrite so the write fails harmlessly. The result is that the last check happens as close '
        r'to the write as the plugin allows.'),
    ...sec(r'the shape of the repository'),
    plain(r'xyno-guard.nvim/'),
    plain(r'├── lua/xyno_guard/init.lua       the guard: stamps, roots, autocmds, wrapper'),
    plain(r'├── tests/'),
    plain(r'│   ├── guard_spec.lua            40 tests, some with a real auto-save plugin'),
    plain(r'│   ├── run.lua                   headless runner, finds auto-save.nvim'),
    plain(r'│   ├── harness.lua               describe / it / hooks'),
    plain(r'│   └── helpers.lua               assertions, temp dirs, waiting, notify capture'),
    plain(r'├── doc/xyno-guard.txt            :help xyno-guard'),
    plain(r'├── .github/workflows/ci.yml     pinned Neovim, pinned auto-save.nvim, specs, help check'),
    plain(r'└── README.md · LICENSE · .stylua.toml · .gitignore'),
    ...sec(r'a short tour'),
    ...text(r'- lua/xyno_guard/init.lua records a stamp per buffer, knows the dependency roots '
        r'(~/.cargo/registry, ~/.cargo/git, ~/.rustup and the CARGO_HOME and RUSTUP_HOME variants), '
        r'decides in can_save, writes with save_all, and installs one augroup in setup. It also '
        r'wraps vim.lsp.util.apply_workspace_edit once, on the first LspAttach.'),
    ...text(r'- tests/guard_spec.lua fakes cargo with temp directories, fakes a language server with a '
        r'table of functions, and, when auto-save.nvim is present, drives it with real events and '
        r'real timers.'),
    ...text(r'- tests/run.lua looks for the auto-save plugin in XYNO_GUARD_AUTOSAVE_DIR or '
        r'tests/deps/auto-save.nvim, and sets a flag the spec reads to decide whether to skip.'),
    ...text(r'- .github/workflows/ci.yml checks out one exact commit of auto-save.nvim so that the '
        r'integration tests run in CI.'),
    ...sec(r'install'),
    ...code('markdown', r'README.md · lines 18-28', r'''
```lua
{
  "okuuva/auto-save.nvim",
  event = { "InsertLeave", "TextChanged", "TextChangedI" },
  dependencies = { "xynorash/xyno-guard.nvim" },
  opts = function()
    require("xyno_guard").setup()
    return { condition = require("xyno_guard").can_save }
  end,
}
```
'''),
    ...text(r'setup() is called in opts so that the autocmds exist before auto-save does anything, and '
        r'the condition is the public can_save function. Without lazy.nvim, the same two calls do '
        r'the same job with whatever plugin you use.'),
    ...sec(r'the four functions'),
    ...code('markdown', r'README.md · lines 44-47', r'''
| `setup(opts?)` | installs the autocmds (group `xyno_guard`) and records the buffers already loaded |
| `can_save(buf)` | may this buffer be written now? Use it as the auto-save `condition` |
| `is_dependency(name)` | is this file below `~/.cargo/registry`, `~/.cargo/git`, `~/.rustup`, `$CARGO_HOME/{registry,git}` or `$RUSTUP_HOME`? |
| `save_all()` | writes every modified file buffer that `can_save` allows |
'''),
    ...text(r'setup installs the autocmds and records buffers that are already loaded; can_save is the '
        r'predicate; is_dependency is the path test; save_all writes every modified file buffer the '
        r'guard allows. There are no options yet: the argument exists so that a later version can '
        r'add some without breaking callers. There are no keymaps and no commands. If you want a '
        r'key for save_all, the README shows one line.'),
    ...sec(r'how it works'),
    ...code('markdown', r'README.md · lines 59-63', r'''
- The file's mtime is recorded when a buffer is read or written (`BufReadPost`, `BufWritePost`, `BufFilePost`, `FileChangedShellPost`). `can_save()` compares it with the disk; on a mismatch the save is skipped and you get one warning per change (`:w!` keeps your buffer, `:e!` takes the disk version). A deleted file is not recreated.
- Dependency and standard-library buffers are opened nomodifiable and readonly. Buffers that were already loaded when `setup()` runs are locked the same way, but a plugin that loads late (the install above loads it on the first auto-save event) cannot lock a file before that, so use `event = "VeryLazy"` if you open dependency sources right at startup. `:set modifiable` lets you edit one on purpose, and it is still never auto-saved.
- auto-save checks its condition when the event fires but writes up to a second later. With okuuva/auto-save.nvim the guard checks again on `User AutoSaveWritePre` and turns a refused write into a harmless one; a listener of `AutoSaveWritePost` can tell by the buffer still being `modified`.
- `FileChangedShell` never prompts: unmodified buffers are reloaded, modified or deleted ones are left alone with a warning.
- After an LSP edit that touches files other than the current one (rename, file rename, code actions) the other modified buffers are written, so disk and undo stay consistent.
'''),
    ...text(r'Read the five bullets as five hazards. The stamp handles files that change while a buffer '
        r'is open. The dependency lock handles files you should not edit. The recheck on '
        r'AutoSaveWritePre handles the debounce window. FileChangedShell handles the moment Neovim '
        r'would otherwise ask you a question. And the workspace-edit wrapper handles multi-file '
        r'refactors.'),
    ...sec(r'honest about its limits'),
    ...code('markdown', r'README.md · lines 67-69', r'''
- Linux: tested by the specs in this repository (`nvim --headless --clean -l tests/run.lua`, 39 tests).
- Windows and macOS: the original spec for this code in xynovim was not among the files its platforms workflow skipped there, and that workflow passed. The specs of this repository have not been run on either, so I treat both as unverified. The path handling is case-insensitive on both.
- The `~/.cargo` and `~/.rustup` roots are Rust-specific; other languages' dependency directories are not covered.
'''),
    ...text(r'The README says plainly that the Windows and macOS runs of the original spec in xynovim '
        r'passed but the specs of this repository have not been run there, and that the cargo and '
        r'rustup roots are specific to Rust. A late-loading plugin cannot lock a dependency file '
        r'before it loads; the README documents the workaround of loading on VeryLazy, which came '
        r'with the last commit, 9c3e9ec.'),
    ...sec(r'where it came from'),
    ...text(r'It started as lua/config/disk_guard.lua in xynovim. The history there is three commits: '
        r'b65284f (2026-10-13) added the disk guard, dependency buffers and save after multi-file '
        r'edits as part of a data-safety batch; 3f868dd (2026-10-13) fixed can_save for non-file '
        r'buffers after field testing; ff1c8fa (2026-10-16) made the code portable to Windows and '
        r'macOS. The extraction on 2026-10-22 renamed it xyno_guard, added the setup(opts) shape, '
        r'and wrote the README, the help page and the CI.'),
    ...sec(r'try it'),
    ...text(r'- nvim --headless --clean -l tests/run.lua runs the suite. Clone okuuva/auto-save.nvim '
        r'into tests/deps/auto-save.nvim first, or set XYNO_GUARD_AUTOSAVE_DIR, to include the '
        r'integration tests.'),
    ...text(r'- :help xyno-guard is the manual.'),
  ],
);
