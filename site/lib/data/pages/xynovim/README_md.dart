import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/README.md',
  summary: 'Neovim 0.12 for Rust on LazyVim: two-tier diagnostics, debugger, tests, git safety net, 1805 passing checks',
  repo: 'xynovim',
  fallbackStars: 0,
  fallbackPushed: '2026-10-22',
  lines: [
    heading('# xynovim'),
    blank,
    ...text('xynovim is the Neovim configuration I use to write Rust, built on LazyVim and inspired by the JetBrains tools I still use. Its README is the front door of the repository: what you get, how to install it, a screenshot tour of every workflow, the keys, the commands, the evidence for each platform claim, and a map of the tree. This page walks through that README against the repository as it stands on 2026-10-22, after the largest single day of work in its history: the Rust-specific code was extracted into nine standalone plugins, the Island Dark colour scheme and the agent sandbox were reworked, Windows and macOS were added to CI, and a website with six guides was published.'),
    blank,
    kv('role', 'repository front page and map of the whole tree'),
    kv('language', 'Markdown, describing Lua (Neovim 0.12), Python, bash and PowerShell'),
    kv('size', '442 lines of README; 148 commits since 2026-08-17'),
    kv('tree', 'lua/config 27 files, lua/plugins 27 files, 38 spec files, 61 locked plugins'),
    kv('tests', '1805 passing, 32 skipped with a reason, 0 failing (my Linux machine)'),
    kv('licence', 'Apache-2.0 for xynovim; MIT for the nine xyno-*.nvim plugins'),
    kv('site', 'https://xynorash.github.io/xynovim/'),
    blank,
    ...sec('what the README promises'),
    ...text('The README opens with one sentence of positioning, and every word of it is something a reader can check in the repository. It says the configuration is personal, for Rust, built on LazyVim, inspired by JetBrains tools, and that it has a test suite you can run yourself. The last claim is the unusual one, and a large part of the README (and of this tree) exists to back it up.'),
    ...code('markdown', r'README.md · lines 5-5', r'''
**A personal Neovim configuration for Rust, built on LazyVim and inspired by JetBrains' tools. Instant diagnostics, a debugger and test UI, a git safety net, and a test suite you can run yourself.**'''),
    ...text('Right under the banner sits the three-line quick start. The design choice is that there is exactly one thing to type after cloning: scripts/bootstrap.sh. The README explains further down why it is a script and not a plain Lazy restore, and it warns in the same breath that the clone replaces your current configuration.'),
    ...code('markdown', r'README.md · lines 22-25', r'''
```sh
git clone https://github.com/xynorash/xynovim ~/.config/nvim
~/.config/nvim/scripts/bootstrap.sh
```'''),
    ...text('The four bullets under What you get are the whole pitch in short form: two diagnostic tiers, an IDE-like debugger and test runner, a safety net (Local History snapshots plus the sandboxed agent), and treesitter everywhere. The fifth is the one with a number in it, 1805 passing checks across 38 spec files. That number is not typed by hand on the website: scripts/build-site.py reads it from the README badge so the two cannot drift, and tests/site_spec.lua fails when they disagree.'),
    ...sec('the tour of the tree'),
    ...text('The Layout block at the bottom of the README is a map of the repository. This section follows it directory by directory, because each directory is a decision about where a kind of knowledge lives. The excerpt is the block itself.'),
    ...code('markdown', r'README.md · lines 421-438', r'''
lua/config/    options, keymaps, autocmds, remote clipboard, statusline/UX helpers, local_history, disk_guard, rust_context/nav/tasks/routes/assist/restart, egui_new, rust_new, lsp_status, lazy, agent_sandbox, crate_meta/crate_add/crate_features/crate_import, import_engine, macro_attrs, macro_tools, code_actions
lua/xynovim/   :checkhealth xynovim
snippets/       rust.json (registered with blink)
data/          macro_attrs/*.json: attribute schemas (serde, clap, thiserror, tokio, ...) for the completion inside `#[...(`
lua/plugins/   one spec per concern (bacon-ls, rustaceanvim, ninety-nine, auto-save, dap, gitsigns, telescope, island-theme, …)
colors/        island-dark colourscheme entry point
lua/island/    Island Dark: init.lua (mapping), palette.lua (generated)
lua/lualine/   island-dark lualine theme
tools/         icls2nvim.py (converts a JetBrains .icls you supply into the palette)
scripts/       bootstrap.sh and bootstrap.ps1 (fresh-install two-step restore, prerequisite check), test.sh (spec runner), test.lua and test.ps1 (the same runner without bash), coverage.lua (coverage report), build-site.py (builds the website), make-share-images.sh (the share cards)
tests/         *_spec.lua, harness.lua, helpers.lua, runner.lua, coverage_hook.lua, fixtures/ (see Tests)
Makefile       make test / make coverage
plugin/after/  transparency, unsafe highlight
after/ftplugin/ Rust buffer settings (plain `'`, comment spelling)
queries/       base rust injections (copy of nvim-treesitter's minus the sqlx macros)
after/queries/ treesitter query extensions (sqlx SQL injection)
.github/       CI: bootstrap, lockfile check, startup smoke test, spec suite; the platforms workflow runs bootstrap, startup and the suite on Windows and macOS; the pages workflow publishes the website to gh-pages
site/          the website's source (index.html, guides/, assets/, 404.html, ...), see site/README.md'''),
    ...bullet('init.lua', 'two lines. It requires config.lazy and nothing else, and its one comment says it bootstraps lazy.nvim, LazyVim and the plugins. All behaviour lives in modules instead of the entry file.'),
    ...bullet('lua/config/', '27 files and 16,796 lines, by far the biggest directory. It holds options, keymaps, autocmds, the remote clipboard, the statusline and UX helpers, Local History, the disk guard, the rust_* family (context, nav, tasks, routes, assist, restart, new), egui_new, lsp_status, lazy, agent_sandbox, the crate_* family, import_engine, macro_attrs, macro_tools and code_actions. Almost every feature in the tour below is one of these modules.'),
    ...bullet('lua/plugins/', '27 files and 1,894 lines. LazyVim loads every file in it as plugin specs, so this is one spec per concern: bacon-ls, rustaceanvim, ninety-nine, auto-save, dap, gitsigns, telescope, island-theme and so on. A spec is short because the behaviour it configures lives in lua/config.'),
    ...bullet('lua/island/ and lua/lualine/', 'the Island Dark theme. lua/island/init.lua maps a palette to highlight groups, lua/island/palette.lua is generated, and lua/lualine has the matching statusline theme. Together with colors/island-dark.lua (the :colorscheme entry point) this is the theme, and tools/icls2nvim.py is the converter that produces the palette from a scheme export you supply.'),
    ...bullet('lua/xynovim/', 'the :checkhealth xynovim provider, 138 lines, which reports what each missing tool would cost.'),
    ...bullet('data/macro_attrs/', 'ten JSON attribute schemas (serde, clap, thiserror, tokio, strum, derive_more, sqlx, utoipa, schemars, bon) that drive completion inside #[serde(, #[arg( and friends. The .gitignore ignores data/ except this folder, so the schemas ship while any other local data stays out.'),
    ...bullet('snippets/, queries/, after/, plugin/after/', 'rust.json snippets for blink, base treesitter injections (a copy of nvim-treesitter’s minus the sqlx macros), after/queries for the sqlx SQL injection, after/ftplugin for Rust buffer settings, and two small after-load scripts for transparency and unsafe highlighting.'),
    ...bullet('scripts/', 'bootstrap.sh and bootstrap.ps1 (fresh-install restore and prerequisite check), test.sh, test.lua and test.ps1 (three ways to run the suite), coverage.lua, provision.lua, build-site.py and make-share-images.sh.'),
    ...bullet('tests/', 'the *_spec.lua files, harness.lua, helpers.lua, runner.lua, coverage_hook.lua and fixtures/ with small Cargo crates. tests/COVERAGE.md maps each feature to its spec.'),
    ...bullet('.github/', 'ci.yml (Ubuntu), platforms.yml (Windows and macOS), pages.yml (publishes the website to gh-pages) and ci/diag-lsp.lua, a print-only diagnostic of which language clients attach to a fresh crate.'),
    ...bullet('site/ and _site/', 'the website source and its built output, with guides under site/guides/ and a plugins page under site/plugins/.'),
    ...bullet('docs/', 'DETAILS.md, HISTORY.md, KNOWN_ISSUES.md, PLAN_MACROS_DEPS.md, TESTING.md, the assessment/ probe scripts and media/ with 15 numbered recordings and the tapes that produce them.'),
    ...bullet('demo/netwatch', 'a small, realistic Rust crate (library, CLI, unit and integration tests, features) that is the target of every screenshot and video, and a good place to try the config.'),
    ...text('Also in the root: lazy-lock.json (61 pinned plugins), lazyvim.json (the enabled LazyVim extras), a Makefile with two targets, stylua.toml (two-space indent, 120 columns), spell/en.utf-8.add for the Rust word list, LICENSE and CHANGELOG.md.'),
    ...code('json', r'lazyvim.json · lines 2-20', r'''
  "extras": [
    "lazyvim.plugins.extras.ai.claudecode",
    "lazyvim.plugins.extras.coding.mini-surround",
    "lazyvim.plugins.extras.coding.neogen",
    "lazyvim.plugins.extras.dap.core",
    "lazyvim.plugins.extras.editor.inc-rename",
    "lazyvim.plugins.extras.editor.navic",
    "lazyvim.plugins.extras.editor.neo-tree",
    "lazyvim.plugins.extras.editor.overseer",
    "lazyvim.plugins.extras.lang.git",
    "lazyvim.plugins.extras.lang.json",
    "lazyvim.plugins.extras.lang.markdown",
    "lazyvim.plugins.extras.lang.rust",
    "lazyvim.plugins.extras.lang.toml",
    "lazyvim.plugins.extras.lang.yaml",
    "lazyvim.plugins.extras.test.core",
    "lazyvim.plugins.extras.ui.treesitter-context",
    "lazyvim.plugins.extras.util.rest"
  ],'''),
    ...sec('the nine plugins that were extracted'),
    ...text('The newest section of the README is Plugins. On 2026-10-22 the original parts of the configuration were published as standalone plugins, each in its own repository under github.com/xynorash, each tagged v0.1.0, each MIT licensed. The README says so in one paragraph, and then splits them into four standalone plugins and a Rust toolkit with xyno-rust.nvim as the base.'),
    ...code('markdown', r'README.md · lines 56-56', r'''
These are the original parts of my config that I extracted into standalone plugins, so anyone can use them without the rest of xynovim. All nine are public, tagged `v0.1.0` with a release, and install with lazy.nvim. The plugins are MIT licensed; xynovim itself stays Apache-2.0. Linux is the platform I test on; each README states what is and is not verified on Windows and macOS. The [plugins page](https://xynorash.github.io/xynovim/plugins/) has the install order, one complete lazy.nvim spec for the Rust toolkit and the questions I expect.'''),
    ...code('markdown', r'README.md · lines 60-63', r'''
- [xyno-history.nvim](https://github.com/xynorash/xyno-history.nvim): Local History, every throttled save snapshotted into private git refs.
- [xyno-sandbox.nvim](https://github.com/xynorash/xyno-sandbox.nvim): runs a command-line coding agent in bubblewrap and refuses to start it without one (Linux only).
- [xyno-clipboard.nvim](https://github.com/xynorash/xyno-clipboard.nvim): an OSC 52 clipboard provider for tmux, SSH and herdr (Linux only).
- [xyno-guard.nvim](https://github.com/xynorash/xyno-guard.nvim): keeps auto-save away from dependency sources and files changed on disk.'''),
    ...code('markdown', r'README.md · lines 67-71', r'''
- [xyno-rust.nvim](https://github.com/xynorash/xyno-rust.nvim): Cargo context, targets, routes, navigation, server restart handling and a statusline indicator.
- [xyno-new.nvim](https://github.com/xynorash/xyno-new.nvim): new Rust binary, library, workspace and egui projects; needs xyno-rust.nvim.
- [xyno-imports.nvim](https://github.com/xynorash/xyno-imports.nvim): auto-import, ranked choice and organize imports; needs xyno-rust.nvim.
- [xyno-crates.nvim](https://github.com/xynorash/xyno-crates.nvim): crates.io search, crate add, features and crate import; needs xyno-rust.nvim and xyno-imports.nvim.
- [xyno-macros.nvim](https://github.com/xynorash/xyno-macros.nvim): macro attribute completion, signature help and `:MacroExpand`; needs xyno-rust.nvim and xyno-imports.nvim.'''),
    ...text('The dependency lines carry the install order. xyno-new.nvim and xyno-imports.nvim need xyno-rust.nvim. xyno-crates.nvim and xyno-macros.nvim need both xyno-rust.nvim and xyno-imports.nvim. The four standalone ones need nothing from the toolkit. The standalone repositories each have between 3 and 5 commits, all dated 2026-10-22 in the local clones, and the commit subjects of xyno-rust.nvim read like an extraction in steps: the modules, then specs with a headless runner and a smoke test, then a README, help file and CI workflow.'),
    ...text('One sentence in the README keeps the extraction honest, and it is easy to skim past.'),
    ...code('markdown', r'README.md · lines 73-73', r'''
xynovim still carries its own in-tree copies of this code; the plugins are the same code under another namespace.'''),
    ...text('That is the state of the tree: grepping lua/ and init.lua for xyno- finds no reference to any of the nine plugins, and lazy-lock.json does not pin them. xynovim keeps running on its own lua/config modules (crate_add, import_engine, macro_tools, rust_new, agent_sandbox, local_history, disk_guard and the rest), while the plugins are the same code under another namespace, for people who want one piece without the rest of the configuration. docs/DETAILS.md adds the caveat that the site spec does not fetch the plugin READMEs, so a change in a plugin repository is not noticed until the page is edited.'),
    ...bullet('xyno-rust.nvim', 'Cargo context, targets, routes, navigation, server restart handling and a statusline indicator. In xynovim these are rust_context, rust_tasks, rust_routes, rust_nav, rust_restart and lsp_status.'),
    ...bullet('xyno-new.nvim', 'new Rust binary, library, workspace and egui projects; in xynovim, rust_new and egui_new.'),
    ...bullet('xyno-imports.nvim', 'auto-import, ranked choice and organize imports; in xynovim, import_engine.'),
    ...bullet('xyno-crates.nvim', 'crates.io search, crate add, features and crate import; in xynovim, crate_meta, crate_add, crate_features and crate_import.'),
    ...bullet('xyno-macros.nvim', 'macro attribute completion, signature help and :MacroExpand; in xynovim, macro_attrs and macro_tools with the data/macro_attrs schemas.'),
    ...bullet('xyno-sandbox.nvim', 'runs a command-line coding agent in bubblewrap and refuses to start it without one; in xynovim, agent_sandbox. Linux only.'),
    ...bullet('xyno-guard.nvim', 'keeps auto-save away from dependency sources and files changed on disk; in xynovim, disk_guard.'),
    ...bullet('xyno-history.nvim', 'Local History, every throttled save snapshotted into private git refs; in xynovim, local_history.'),
    ...bullet('xyno-clipboard.nvim', 'an OSC 52 clipboard provider for tmux, SSH and herdr; in xynovim, remote_clipboard. Linux only.'),
    ...text('The right-hand halves of those bullets are my mapping from the plugin descriptions in the README to the module names in lua/config, not a claim the README makes in those words. The module names are real files; whether each plugin is a line-for-line copy is something the README only says in general terms (the same code under another namespace).'),
    ...sec('the diagnostics tier, the centrepiece'),
    ...text('The first screenshot section is the reason the repository exists. rust-analyzer reports type errors from its own memory as you type, in about 0.01 to 0.15 seconds. bacon-ls then runs clippy against a hardlinked shadow of the workspace on every buffer change, at a median of about 0.56 seconds, so lints appear before you save. The README keeps the explanation to one paragraph and puts the evidence in docs/DETAILS.md, including the reason diagnostics.experimental stays off (on a 196-file axum and sqlx workspace it produced 82 false errors, against none with it off).'),
    ...code('markdown', r'README.md · lines 79-79', r'''
rust-analyzer's own diagnostics appear as you type (type errors in about 0.01 to 0.15 s). [bacon-ls](https://github.com/crisidev/bacon-ls) runs clippy against a hardlinked shadow of your workspace on every buffer change (about 0.56 s median), so lints show up before you save. Each message shows its first line plus the source; the full text is one `<leader>cd` away.'''),
    ...text('Two features make the two tiers behave as one tool. The first is :RustContext, which stores the chosen Cargo features and build target per workspace and applies them to both rust-analyzer and bacon-ls, so the tiers never disagree. The README demonstrates it with the demo crate, where ssr and csr are mutually exclusive: with every feature on, both tiers report the conflict; choosing only ssr clears it in both.'),
    ...code('markdown', r'README.md · lines 139-139', r'''
Cargo features and the build target are chosen per project and applied to **both** rust-analyzer and bacon-ls, so the two tiers never disagree. In the demo `ssr` and `csr` are mutually exclusive: with all features on, both tiers report the conflict; choosing only `ssr` makes it go away in both.'''),
    ...text('The second is the supervision layer. A rust-analyzer or bacon-ls that dies used to stay dead, so the statusline now says RA stopped or clippy stopped and the server is restarted. After a Cargo.toml or Cargo.lock save, bacon-ls is restarted 500 ms after the last write and the statusline shows deps resolving until rust-analyzer finishes reloading. Both behaviours are described in the README’s Macros and dependencies section and specified in docs/DETAILS.md.'),
    ...sec('the rest of the tour'),
    ...bullet('Treesitter, visibly', 'sticky scope from treesitter-context, text objects such as vaf, sqlx SQL injected into strings, and the :Inspect and :InspectTree views as proof.'),
    ...bullet('Refactoring (leader r)', 'every rust-analyzer command that rustaceanvim exposes has a key under leader r, discoverable with which-key: extract variable, function, constant and module, inline, structural search and replace, join lines, move item, expand macro, view HIR and MIR, explain error code.'),
    ...bullet('Tests and coverage', 'neotest with the rustaceanvim adapter and cargo-nextest for a summary tree, and cargo-llvm-cov coverage in the gutter (leader tc runs it, leader tg toggles the signs).'),
    ...bullet('Debugging', 'nvim-dap with codelldb, a dap-ui layout sized for Rust’s long type names, and lldb’s Rust formatters loaded automatically so a String shows as text and not as raw memory. A panic stops at the panicking frame.'),
    ...bullet('Git and a safety net', 'lazygit with delta, diffview, mergiraf as a merge driver, and Local History: every save writes the whole worktree, untracked files included, as a commit under refs/lochist using a private index. Deleted files and a git reset --hard become recoverable without touching your index, stash or branches.'),
    ...bullet('Island Dark', 'the colour scheme is generated by tools/icls2nvim.py from a scheme export that is not distributed. Contrast was checked against WCAG targets and lifted where the export was too dim; floats and the completion menu stay solid on a transparent editor.'),
    ...code('markdown', r'README.md · lines 153-153', r'''
lazygit (with `delta`), diffview for diffs, merge conflicts and file history, `mergiraf` as a syntax-aware merge driver, and **Local History**: every save (manual or auto-save, throttled) also writes the whole worktree, untracked files included, as a commit under `refs/lochist/` using a private index. Deleted files and `git reset --hard` become recoverable without touching your real index, stash or branches. `:LocalHistory` browses and diffs, `:LocalHistoryRestore` restores, `:LocalHistoryPrune` cleans up.'''),
    ...sec('the agent sandbox'),
    ...text('The only section with no screenshots is the AI agent, and the README says why: the sandbox has no UI and a real request needs an account. The 99 plugin is wired to the Claude Code provider, whose command line includes a flag that skips permission prompts, so the configuration refuses to run it outside bubblewrap. The paragraph is long because the rules are precise. Without bwrap (Windows, macOS, Linux without it) 99 refuses to start a request and says why. Two booleans override that, and each warns on every request.'),
    ...code('markdown', r'README.md · lines 175-175', r'''
[99](https://github.com/ThePrimeagen/99) with the Claude Code provider is wired in (`<leader>9`), and its `claude --dangerously-skip-permissions` runs inside **bubblewrap**, which exists only on Linux, so the agent **only runs where a sandbox exists** (Linux with `bwrap`; WSL2 with `bwrap` is the route on Windows, not tested here). Without one (Windows, macOS, Linux without `bwrap`) 99 **refuses** to start a request and says why. Two explicit booleans override that, and either one warns on every request: `vim.g.xynovim_99_sandbox = false` turns the sandbox off on purpose (even where `bwrap` works), `vim.g.xynovim_99_allow_unsandboxed = true` runs the agent anyway only when there is no backend (it never disables a working sandbox); `0`, `"false"` or `1` count as nothing. The `<leader>9P` provider picker only accepts the guarded Claude Code provider under the same rule (the other CLIs would run with no sandbox or checkpoint). Where `bwrap` works: the filesystem is read-only except the project and Claude's own state, credentials and agent sockets are hidden, `.git/hooks`, `.git/config` and Claude's settings are locked read-only, the environment is scrubbed of tokens, and every request is preceded by a Local History snapshot with auto-save paused. It is a seatbelt, not a jail: the network stays open (details in [docs/DETAILS.md](docs/DETAILS.md)). There are no screenshots: the sandbox has no UI, and a real request needs an account.'''),
    ...text('The history behind this is in CHANGELOG.md. The first version of agent_sandbox.wrap returned the command unchanged when no backend existed, so the permission-skipping agent ran with the user’s full privileges and no message. Commit 440d781 on 2026-10-16 made it fail closed (status returns bwrap, unsandboxed or refused), and the agent-failclosed spec checks the refusal on every platform. The README states the limit plainly: it is a seatbelt, not a jail, because the network stays open.'),
    ...sec('install, and why a script'),
    ...text('The Install section is a table of evidence before it is a list of commands. The three platform rows (Linux, Windows, macOS) each cite GitHub Actions run numbers, and the macOS row says in bold that it is not reliably green. That wording was the result of a deliberate commit, 196c8af, which made the README, the site and the repository description say only what the platforms and ci runs show.'),
    ...code('markdown', r'README.md · lines 189-189', r'''
Linux-only by design, so nothing of it works on Windows or macOS: the **99 agent sandbox** (bubblewrap; without a backend 99 refuses to start, see [The AI agent, sandboxed](#the-ai-agent-sandboxed)), the remote clipboard, the **tmux-based** and bash-stub test tooling (`scripts/test.sh`, `--coverage`; use `scripts/test.lua` or `scripts/test.ps1` elsewhere) and the **mold** linker setup (a Linux speed-up; `mold` and `clang` are optional anyway).'''),
    ...text('Below the table come the prerequisites in three tiers: required to bring the config up (nvim 0.12, git, curl, tar, unzip, gcc, the tree-sitter CLI, gzip, node and npm), required for the Rust workflow (cargo, rustup with clippy and llvm-tools, rust-analyzer), and installed by Mason (bacon-ls at 0.31.0 or newer, codelldb, taplo, wgsl-analyzer, marksman, lua-language-server and others). Optional tools each cost only their own feature. The Windows instructions use winget and a junction, so no administrator rights are needed.'),
    ...code('markdown', r'README.md · lines 200-203', r'''
```sh
git clone https://github.com/xynorash/xynovim ~/.config/nvim   # or ln -s <checkout> ~/.config/nvim
~/.config/nvim/scripts/bootstrap.sh
```'''),
    ...text('The paragraph that follows explains why the script exists at all, and it is the best piece of reasoning in the README. On an empty plugin directory, lazy.nvim installs in several rounds, rewriting lazy-lock.json after each, so the pins of plugins discovered later were dropped and those plugins landed on their newest commit. The script installs, puts the original lockfile back, restores, and fails if the lockfile differs afterwards; CI then runs git diff --exit-code lazy-lock.json.'),
    ...code('yaml', r'.github/workflows/ci.yml · lines 35-39', r'''
      - name: Restore plugins from the lockfile
        run: scripts/bootstrap.sh

      - name: Lockfile unchanged
        run: git diff --exit-code lazy-lock.json'''),
    ...sec('keys and commands'),
    ...text('Keys you will use is a single table, one row per prefix, because which-key shows the rest. The leader r row is the longest, since it carries both the rust-analyzer commands and the dependency commands added later (rA add crate, rG enable the missing feature, rI import name, rO organize imports, rx expand macro, rq proc-macro status). The Commands paragraph then lists every user command: :RustContext, :RustTargets, :RustTools, :RustNew and its four variants, :EguiNew, :RustRoutes, :RustRestart, :CrateAdd, :CrateFeatures, :ImportName, :ImportForget, :ImportOrganize, :MacroAttrs, :MacroExpand, :MacroSignature, :MacroFormatFix, :ProcMacroStatus, :ActJob, the three :LocalHistory commands, :ColorblindDiagnostics and :checkhealth xynovim.'),
    ...code('markdown', r'README.md · lines 225-232', r'''
| `<leader>d…` | debugger: `db` breakpoint, `dc` continue, `dr` / `dR` debuggables (file / workspace), `du` dap-ui |
| `<leader>t…` | tests: `tt` file, `tr` nearest, `tT` all, `ts` summary, `to` output, `tw` watch, `tD` doc-tests, `tc` run coverage, `tg` toggle coverage signs |
| `<leader>g…` | git: `gg` lazygit, `gv` diffview, `gV` branch vs origin, `gF` file history, `gH` local history |
| `<leader>c…` | `cd` diagnostic float, `cj` split / join (treesj), `cI` / `cO` incoming / outgoing call trees, `cn` doc comment stub |
| `<leader>9…` | the 99 agent: `9v` vibe, `9s` search, `9o` last interaction, `9x` stop |
| `<leader>H`, `<C-e>`, `<M-1..4>` | harpoon: add file, menu, jump |
| `<leader>uO`, `uB`, `uu` | toggle editor transparency, colour-blind diagnostics, undotree |
| dashboard `b`, `i`, `w`, `e` | new Rust binary, library, workspace, egui project |'''),
    ...text('A design point from docs/DETAILS.md explains why some of those keys are buffer-local. keymaps.lua parks hidden not-bound stubs on every global leader r key, and the keymaps-global spec allows no other global one, so rA, rG, rI, rO, rx and rq are set per Rust buffer after rust-analyzer attaches.'),
    ...sec('macros and dependencies'),
    ...text('This section is the user-facing description of a phase that started as an assessment. The README’s opening sentence names four problems: no completion inside #[serde(, no use for a crate that is not a dependency yet, a missing derive feature that nothing points at, and a stale cannot find crate error after cargo add. docs/PLAN_MACROS_DEPS.md has the measurements and the seven gaps (G1 to G7), and docs/assessment/ has the probe scripts.'),
    ...code('markdown', r'README.md · lines 240-240', r'''
Adding a crate used to leave its macros and features half used: no completion inside `#[serde(`, no `use` for a crate that is not a dependency yet, a missing `derive` feature that nothing pointed at, a stale `cannot find crate` error after `cargo add`. The assessment (measured on a crate with serde, clap, thiserror, anyhow and tokio; probes in [docs/assessment/](docs/assessment/)) and the seven gaps it found are in [docs/PLAN_MACROS_DEPS.md](docs/PLAN_MACROS_DEPS.md), together with what of the plan is done. Everything runs in nvim on top of rust-analyzer, `cargo` and treesitter; no extra language server.'''),
    ...text('The section is mostly a table of keys against behaviour, followed by paragraphs for dependency resolution, auto-import, import from crates that are not dependencies, attribute schemas and limits. Auto-import is the most carefully bounded: the setting vim.g.xynovim_auto_import takes ask (the default), single or off, and several candidates are never guessed at.'),
    ...code('markdown', r'README.md · lines 257-257', r'''
**Auto-import**. `vim.g.xynovim_auto_import` (set before the first Rust buffer): `"ask"` (default) asks (a yes/no dialog that stays until answered; never in a headless nvim) when exactly one `Import X` exists for an unresolved name after `InsertLeave`, a save or a paste; `"single"` applies it as one undo step with a one-line note; `"off"` never. Several candidates are never guessed at: `:ImportName` ranks them (used in this file, then in the module, then in the crate, the derive or attribute context, the return type, dependency order, the prelude) and remembers your choice in `stdpath("state")/xynovim/imports.json`.'''),
    ...text('The Limits paragraph is worth reading as a model of honest documentation. It lists what the feature does not do (a glob import silences the unknown-crate hint for the whole file; files over 20000 lines get no hint; serde keys are offered while its derive feature is off; a guess can miss) and ends by saying the pickers and key presses were not driven in a real terminal.'),
    ...sec('new projects'),
    ...text('Three dashboard entries and four commands create Rust projects: a binary (key b, :RustNewBin), a library (key i, :RustNewLib), a workspace (key w, :RustNewWorkspace) and a member (:RustNewMember). cargo has no one-step workspace command, so the workspace is built by the config, and the README shows the exact layout it writes.'),
    ...code('markdown', r'README.md · lines 316-326', r'''
```
my-ws/
  Cargo.toml        [workspace] resolver = "3", members = ["crates/*"]
                    [workspace.package] version = "0.1.0", edition = "2024"
                    [workspace.dependencies] (empty)
  .gitignore        /target
  crates/
    my-ws-app/
      Cargo.toml    version.workspace = true, edition.workspace = true
      src/main.rs   (src/lib.rs for a library)
```'''),
    ...text('The edition is read once per session from a throwaway cargo new, never hard-coded, and the resolver is 3 for edition 2024 and newer. On failure everything the run created is removed again. The egui flow follows the same pattern against the current emilk/eframe_template ZIP, cached with its ETag, with the template’s toolchain pin deliberately deleted because a pin makes rustup download a toolchain without rust-analyzer.'),
    ...sec('tests: run them yourself'),
    ...text('The test section gives the commands and the contract. Each spec file runs in its own headless Neovim with the full config and a hard timeout, against a temporary config, state and cache; only the installed plugins are reused. A missing tool makes a spec skip with a message and never fail.'),
    ...code('markdown', r'README.md · lines 374-379', r'''
```sh
scripts/test.sh                  # everything (or: make test)
scripts/test.sh routes smoke     # only spec files whose path contains one of the words
scripts/test.sh --list           # the spec files, nothing run
scripts/test.sh --coverage       # also a per-file line-coverage report
```'''),
    ...bullet('Honest counts', 'the numbers are from my Linux machine, and the README gives the Ubuntu CI figures next to them (run 39695896272: 1749 passed, 76 skipped, 0 failed) so the two are not confused.'),
    ...bullet('One spec per feature area', 'startup and options, the theme, every leader r command, :RustContext, Local History, the sandbox and the 99 guard, both diagnostic tiers, debugger and tests, git and lint tooling, snippets and injections, UI helpers, health and bootstrap, README claims and the website.'),
    ...bullet('Coverage', 'about 86 percent of the repo’s own Lua before the macros and dependencies modules were added, with the explicit caveat that it has not been re-run since and the denominator is estimated.'),
    ...bullet('Claims are tested', 'tests/test-infra-readme-claims_spec.lua exists so that statements this README makes, such as counts and flags, are checked and cannot silently rot.'),
    ...sec('the demo project, recordings and website'),
    ...text('demo/netwatch is the fixed target of every screenshot, so a recording can be regenerated after any change by docs/media/record.sh, which copies the crate to a temporary directory, warms the build and replays a vhs tape in a real terminal. That requires vhs, ttyd, chromium, ffmpeg and a Nerd Font. The website is a static page with no external requests, built by scripts/build-site.py into _site and published by pages.yml as a single orphan commit on gh-pages.'),
    ...code('markdown', r'README.md · lines 395-398', r'''
```sh
docs/media/record.sh            # everything
docs/media/record.sh 05-tests   # one tape
```'''),
    ...text('Just before the Layout block the README has an Acknowledgements section, a paragraph thanking JetBrains and stating that xynovim is independent, not affiliated, not competing. The wording was settled in two commits on 2026-10-22, 7d2f382 (Acknowledgements: thank JetBrains) and 0247401 (Positioning: a personal project inspired by JetBrains, not a competitor), and the CHANGELOG records that the project’s older “goes after” and “closing the gap” phrasing was removed from the pitch, history headings and comments without changing any fact.'),
    ...sec('design decisions in how the README is written'),
    ...bullet('Every number has a source', 'counts come from a measured run, platform claims cite run ids, and the website takes its numbers from the README, so there is one place to correct.'),
    ...bullet('Limits sit next to features', 'the Platforms section lists what is not demonstrated on Windows and macOS (Local History has no Windows evidence at all) instead of a vague caveat.'),
    ...bullet('Nothing is mocked', 'the opening of the repository says all screenshots and videos were recorded from the real config on the demo crate, and the tape pipeline is in the tree to prove it.'),
    ...bullet('The README is the overview', 'engineering notes, measurements and the long history live in docs/ (DETAILS, HISTORY, KNOWN_ISSUES, PLAN_MACROS_DEPS, TESTING), each of which has its own page in this explorer.'),
    ...sec('how it is tested'),
    ...text('The README is covered by a spec of its own. tests/test-infra-readme-claims_spec.lua checks claims the README and CHANGELOG make about the test infrastructure, the CHANGELOG records a bug found there (README plugin count, bug 8 in tests/COVERAGE.md), and tests/site_spec.lua checks that the numbers on the website equal the numbers in the README and that the directory holds as many spec files as the badge says. The platforms table is not tested at all; it is a statement about GitHub Actions runs, and the only check is that a person looked at the runs.'),
    ...sec('history'),
    ...bullet('2026-08-17', 'initial commit 1c496fd: a minimal Neovim config for Rust, Node, PowerShell and Flutter plus 99, from scratch, on Windows.'),
    ...bullet('2026-09-02', 'eabb22a migrated to a LazyVim-based config on Linux (Omarchy and Arch). The Windows lineage lives on the windows-legacy branch.'),
    ...bullet('2026-09-03', 'the project was renamed xynovim in 5e60f65 and the README rewritten (07993a4).'),
    ...bullet('2026-10-14', '0b0eee8 replaced the long README with a showcase of screenshots and videos from the real config, and split the engineering notes into docs/.'),
    ...bullet('2026-10-16', 'the website went up (94ff2dc) and the agent sandbox became fail closed (440d781).'),
    ...bullet('2026-10-22', 'Rust code extracted into nine plugins; positioning, acknowledgements and counts reworked; the README was last changed in 764702c (site: plugin specs, README, DETAILS and CHANGELOG).'),
    ...text('The README has 83 commits of its own in git log. The shape of that history is the real lesson of the page: it grew from a command list into a document that carries evidence, and most later README commits are about making a claim smaller or more exact, not bigger.'),
    blank,
  ],
);
