import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-rust.nvim/README.md',
  repo: 'xyno-rust.nvim',
  summary: r'Rust plumbing for Neovim: one Cargo context for rust-analyzer and bacon-ls, targets, routes, supervision, statusline',
  fallbackStars: 0,
  fallbackPushed: '2026-10-22',
  lines: [
    heading(r'# xyno-rust.nvim'),
    blank,
    ...text(r'Rust project plumbing for Neovim. One Cargo context (features and target) that rust-analyzer and bacon-ls both obey. A picker for every target and tool of the workspace. A route picker for web services found with tree-sitter alone. Jumps that rust-analyzer has no single request for. A supervisor that brings a dead server back, and a statusline that tells you whether the squiggles you are looking at are fresh. It is also the shared base of three sibling plugins, xyno-crates.nvim, xyno-imports.nvim and xyno-new.nvim, which borrow its modules as a library.'),
    kv(r'language', r'Lua (Neovim 0.12+)'),
    kv(r'shape', r'11 modules, 3,134 lines in lua/; 9 specs with 226 test cases, a headless runner, a lazy.nvim smoke test'),
    kv(r'origin', r'extracted from xynovim, a personal Neovim configuration for Rust'),
    kv(r'history', r'4 commits on 2026-10-22 (09:20 and 10:37 +03:00); the code itself was written in xynovim between 2026-10-09 and 2026-10-21'),
    kv(r'license', r'MIT'),
    ...sec(r'the problem this plugin exists for'),
    ...text(r'A Rust project in an editor is two servers, not one. rust-analyzer gives you types, completion and navigation. bacon-ls runs clippy in the background and gives you the lints as you type. Both of them run cargo, and both of them must agree on which features are enabled and which target is built. If they do not, a crate with mutually exclusive features gets bogus errors from whichever server was told the wrong thing. The first module of this plugin, rust_context, exists to keep one answer per workspace, and everything else grew around the same daily frictions: run the binary, find the handler of a route, restart the server that was killed, know whether clippy has caught up with your last edit.'),
    ...text(r'The second reason is that a long Neovim configuration eventually contains good libraries that nothing else can use. These modules lived in the author’s own Neovim configuration, xynovim, from 2026-10-09 until they were moved out on 2026-10-22. Many comments in the code record a specific bug or field-test finding.'),
    ...sec(r'what you get'),
    ...bullet(r':RustContext', r'multi-select Cargo features with Tab, pick a target from the installed rustup targets, and the choice is pushed into the running rust-analyzer, bacon-ls is restarted with matching arguments, and the choice is stored per workspace.'),
    ...bullet(r':RustTargets', r'every bin, example, test, bench and lib of the workspace, with run, test, build, bench, doc-test and two profiling rows (samply, flamegraph) for each binary, all carrying the features and target of the context, in a bottom terminal that stays open.'),
    ...bullet(r':RustTools', r'build timings, cargo-bloat by crate and by function, machete, deny, audit, duplicate versions and a coverage summary.'),
    ...bullet(r':RustRoutes', r'an axum, actix-web or rocket route picker that works from syntax alone and jumps to the string literal of the path.'),
    ...bullet(r'go to super method, usages in this file', r'from impl Trait for T to the trait method; reads and writes labelled in the quickfix list.'),
    ...bullet(r':RustRestart and automatic restarts', r'a crashed server is restarted at most three times a minute; bacon-ls is restarted when Cargo.toml changes, git HEAD moves or target/ is cleaned; servers that never finished initialising are killed at quit (VimLeavePre), and stopped ones are resumed with SIGCONT first.'),
    ...bullet(r'a statusline component', r'"deps resolving | RA indexing 42% | clippy stale" and its relatives.'),
    ...bullet(r'a toolkit for other plugins', r'code_actions (rust-analyzer code actions as data), crate_meta (cargo metadata, registry sources, a crates.io client), fsutil, deps.'),
    ...sec(r'install'),
    ...code('lua', r'README.md · lazy.nvim spec', r'''
{
  "xynorash/xyno-rust.nvim",
  dependencies = { "folke/snacks.nvim" }, -- pickers and terminals
  ft = "rust",
  cmd = { "RustContext", "RustTargets", "RustTools", "RustRoutes", "RustNew", "RustRestart", "ActJob" },
  opts = {},
  keys = {
    { "<leader>rF", "<cmd>RustContext<cr>", ft = "rust", desc = "Cargo features / target" },
    { "<leader>rX", "<cmd>RustTargets<cr>", ft = "rust", desc = "Cargo targets: run / test / bench" },
    { "<leader>rZ", "<cmd>RustTools<cr>", ft = "rust", desc = "Cargo tools" },
    { "<leader>rN", "<cmd>RustRoutes<cr>", ft = "rust", desc = "HTTP routes" },
    { "<leader>ru", function() require("xyno_rust.rust_nav").goto_super() end, ft = "rust", desc = "Go to super method" },
    { "<leader>rl", function() require("xyno_rust.rust_nav").local_usages() end, ft = "rust", desc = "Usages in file (R/W)" },
    { "<leader>tD", function() require("xyno_rust.rust_tasks").doctests() end, ft = "rust", desc = "Doctests" },
  },
}'''),
    ...text(r'Load it on ft = "rust" or on one of its commands. If you want a crashed server to be restarted in every session, load it on VeryLazy instead, because the supervision starts with setup(). snacks.nvim is a soft dependency: without it, the picker commands print one error line and nothing else.'),
    ...sec(r'the tour: every file in this repository'),
    ...text(r'The tree below is the whole project. Each entry has a page in this site, in the same place in the explorer.'),
    plain(r'xyno-rust.nvim/'),
    plain(r'├── lua/xyno_rust/'),
    plain(r'│   ├── init.lua            setup(): commands, module switches, opt-in keymaps'),
    plain(r'│   ├── deps.lua            finds snacks.nvim or fails with one line'),
    plain(r'│   ├── fsutil.lua          rename that survives Windows, slash()'),
    plain(r'│   ├── rust_context.lua    the per-workspace features and target'),
    plain(r'│   ├── rust_tasks.lua      targets, tools, :RustNew, :ActJob, doctests'),
    plain(r'│   ├── rust_routes.lua     axum / actix / rocket routes from tree-sitter'),
    plain(r'│   ├── rust_nav.lua        go to super method, usages with R/W labels'),
    plain(r'│   ├── lsp_status.lua      the statusline: RA state, clippy state, deps'),
    plain(r'│   ├── rust_restart.lua    the supervisor of the two servers'),
    plain(r'│   ├── code_actions.lua    code actions as data (library)'),
    plain(r'│   └── crate_meta.lua      cargo metadata, sources, crates.io (library)'),
    plain(r'├── doc/xyno-rust.txt       the :help file'),
    plain(r'├── tests/'),
    plain(r'│   ├── run.lua             one headless nvim per spec file'),
    plain(r'│   ├── harness.lua         describe / it in 177 lines'),
    plain(r'│   ├── *_spec.lua          nine specs, 226 test cases'),
    plain(r'│   └── e2e/smoke.lua       installs the plugin through lazy.nvim'),
    plain(r'└── .github/workflows/ci.yml  pinned Neovim, parsers built from commits'),
    blank,
    ...text(r'The reading order that makes sense is the dependency order. fsutil and deps are the two leaves. rust_context is the heart: rust_tasks, rust_routes, crate_meta and rust_restart all call into it. lsp_status and rust_restart are two halves of the supervision story, one drawing the state and one changing it. code_actions and crate_meta are the libraries the other plugins stand on.'),
    ...sec(r'how the pieces fit'),
    plain(r'  :RustContext ──► rust_context ──► rust-analyzer  (didChangeConfiguration)'),
    plain(r'                       │          └─► bacon-ls      (lsp restart, new extraArgs)'),
    plain(r'                       ▼'),
    plain(r'         rust_tasks, bacon_args: the same flags for every cargo call'),
    blank,
    plain(r'  server dies ─► rust_restart.on_exit ─► xyno_rust_stopped ─► lsp_status "RA stopped"'),
    plain(r'  Cargo.toml saved ─► rust_restart.manifest_saved ─► lsp_status.deps_begin'),
    plain(r'                                                   └─► lsp restart bacon_ls'),
    blank,
    ...text(r'The glue is deliberately thin. The modules never configure rust-analyzer or bacon-ls. You wire two callbacks (on_exit, and settings or before_init) in the configuration of your LSP plugin, as the help file shows for rustaceanvim, and everything else is autocommands and commands. The code restarts bacon-ls through vim.lsp.enable and :lsp restart.'),
    ...sec(r'wiring it to the servers, in twenty lines'),
    ...text(r'This is the only configuration the plugin asks of you. It is taken from the author’s own setup with rustaceanvim and is not run by the specs here. Two callbacks: on_exit gives the supervisor the death of the server, and settings makes rust-analyzer start with the stored context instead of the defaults.'),
    ...code('lua', r'README.md · wiring with rustaceanvim', r'''
vim.g.rustaceanvim = {
  server = {
    on_exit = function(...)
      return require("xyno_rust.rust_restart").on_exit("rust-analyzer")(...)
    end,
    settings = function(root, default_settings)
      local settings = require("rustaceanvim.config.server").load_rust_analyzer_settings(
        root,
        { default_settings = vim.deepcopy(default_settings) }
      )
      local ctx = require("xyno_rust.rust_context")
      local cargo = ctx.ra_cargo(ctx.get(ctx.root(root and (root .. "/x"))))
      if cargo then
        local ra = settings["rust-analyzer"]
        ra.cargo = vim.tbl_extend("force", ra.cargo or {}, cargo)
      end
      return settings
    end,
  },
}'''),
    ...text(r'Read it as three decisions. First, the context is read at server start through ctx.get(ctx.root(...)), so a workspace you configured yesterday starts with yesterday’s features. Second, it extends the settings loaded by rustaceanvim and does not replace them: tbl_extend with force touches only the cargo table. Third, on_exit is a function that returns the callback for a name, so the same supervisor serves rust-analyzer and, with the name bacon_ls, the clippy tier. For bacon-ls, before_init rebuilds extraArgs from rc.bacon_args, which is --workspace, the context flags, --no-deps and --keep-going.'),
    ...sec(r'options and keys'),
    ...text(r'setup() takes three options. commands (default true) defines :RustContext, :RustTargets, :RustTools, :ActJob, :RustNew, :RustRoutes and :RustRestart. keymaps (default false) is false, true, or a table of action names to keys; with true the keys are buffer-local in Rust files: leader-r then F for the context, X for targets, Z for tools, N for routes, u for go to super method, l for usages in the file, and leader-t D for doctests. modules lets you switch off context, tasks, routes, status and restart one by one; a module that is off defines no command and no autocommand. No global key is ever set by default: the plugin would rather be quiet than collide with your leader mappings.'),
    ...sec(r'the dependency map'),
    ...text(r'Nothing here has a hard dependency. The optional ones are named by the entries that need them: rustup for the target list, samply and cargo-flamegraph for the profiling rows, cargo-bloat, cargo-machete, cargo-deny, cargo-audit and cargo-llvm-cov for the tools picker, act for :ActJob, curl for the crates.io client, bacon-ls for the second server. The one thing you must define yourself is a cargo profile called profiling, for example inheriting release with debug = true in ~/.cargo/config.toml, because the profile rows of :RustTargets build with it.'),
    ...sec(r'ideas worth stealing'),
    ...bullet(r'one source of truth, written safely', r'the state file is written aside and renamed, under a lock file, because eight Neovim instances applying twenty contexts each once kept 79 of 160 entries (rust_context).'),
    ...bullet(r'ask cargo, then fall back', r'the workspace root comes from cargo locate-project and only from a text walk when cargo cannot answer.'),
    ...bullet(r'fingerprints, not watchers', r'the supervisor compares mtimes, inodes and the git HEAD on focus and on save; nothing polls (rust_restart, lsp_status).'),
    ...bullet(r'trust nothing from a dependency', r'files are read only if they are regular and under 2 MiB, names and versions are validated before they reach argv or paths, curl gets an argv list (crate_meta).'),
    ...bullet(r'a test seam instead of a mock framework', r'M.exec, M.clients and M.client_name are public so specs replace one function (crate_meta, code_actions).'),
    ...bullet(r'a test runner you can read in one sitting', r'run.lua and harness.lua together are 272 lines.'),
    ...sec(r'where it came from'),
    ...text(r'xyno-rust.nvim was extracted on 2026-10-22 from xynovim, the author’s Neovim configuration, whose first commit is dated 2026-08-17. In xynovim the modules lived in lua/config as rust_context.lua, rust_tasks.lua and so on. rust_context first appears on 2026-10-09 in a work-in-progress commit (f5936dc); rust_nav (b64aa27), rust_tasks (025f7a6), lsp_status (bdd0225) and rust_routes (527f350) arrive the same day. The supervision, with its auto-restart and :RustRestart, is be73b6c on 2026-10-12. Then came five commits titled “Final loop round 1” to “round 5” on 2026-10-13 and 2026-10-14 (98c9bb4, a3d33c8, 3f868dd, f31e013, 25086fd), whose subjects list the bugs they closed, among them: cargo locate-project root, the rust-context lock, the sweep on save, the bacon-ls shadow restart, SIGKILL for hung servers. code_actions and crate_meta were written together on 2026-10-14 (6e1b567) for the dependency and macro features. Windows and macOS portability followed on 2026-10-16 and 2026-10-21.'),
    ...text(r'The extraction itself is four commits in this repository, all on 2026-10-22. c1c7958 adds the eleven modules, 7c1d2d9 the specs, the runner and the smoke test, 6947749 the README, help file and CI workflow, and dbb2c0e a README section that says which specs were not ported. The code is the same as in xynovim apart from the namespace (config.* became xyno_rust.*), setup() taking options, the picker and terminal calls checking that snacks.nvim is there, and a few renamed identifiers.'),
    ...sec(r'honest edges'),
    ...bullet(r'linux is the tested platform', r'the specs here run on Linux in CI. The Windows guards are kept but not proven by this repository; macOS is untested here.'),
    ...bullet(r'the live bacon-ls specs were not ported', r'the original suite killed real servers with kill -9 and SIGSTOP. Those cases are not here, so the restart and sweep logic has no real-process spec in this repository.'),
    ...bullet(r'the route picker sees literal strings only', r'a path built from a constant or a nested router prefix is not composed.'),
    ...bullet(r'is_known_path_head is a heuristic', r'it is not name resolution, and says so in its comment.'),
    ...sec(r'tests and CI'),
    ...text(r'nvim -l tests/run.lua runs every spec in its own headless Neovim and prints one line per test. Specs that need cargo, rust-analyzer or a tree-sitter parser skip with a message when it is missing. CI builds Neovim v0.12.5 (checksum verified), rust-analyzer, and the rust and yaml parsers from pinned commits, runs the specs, then installs the plugin through a pinned lazy.nvim and runs the smoke test.'),
    ...sec(r'acknowledgements and licence'),
    ...text(r'The Cargo context and the tools picker are inspired by the Cargo tool window of the JetBrains IDEs, and, according to the header of rust_routes.lua, the route picker by their Endpoints tool window; this is an independent project and not affiliated with JetBrains. MIT, Copyright (c) 2026 Xynorash.'),
  ],
);
