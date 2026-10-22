import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/CHANGELOG.md',
  lines: [
    heading('# Changelog'),
    blank,
    ...text('CHANGELOG.md is 956 lines long and records, for every change to the configuration, what was wrong, what was measured and how the fix was checked. It is more than twice as long as the README (442 lines), and the shorter documents (README, docs/DETAILS.md, docs/KNOWN_ISSUES.md) repeat many of its facts in condensed form. This page reads it from the top: the unreleased work of 2026-10-22 first, then the numbered releases down to 0.1.0 on 2026-08-17.'),
    blank,
    kv('role', 'chronological record of changes, newest first'),
    kv('language', 'Markdown, Keep a Changelog layout with sections Added, Changed, Fixed, Removed'),
    kv('size', '956 lines, 12 numbered sections plus an Unreleased block and a pre-1.0 Windows lineage'),
    kv('span', '2026-08-17 (0.1.0) to 2026-10-22 (Unreleased)'),
    kv('releases', '1.8.0 (2026-10-13), 1.7.0, 1.6.0 (2026-10-12), 1.5.0 (2026-10-09), 1.4.x, 1.3.0, 1.2.0, 1.1.0, 1.0.0 (2026-09-02), 0.2.0, 0.1.0'),
    blank,
    ...sec('how the file is organised'),
    ...text('The header is two lines and a promise. The format is the one from keepachangelog.com, but the content departs from it in a useful way: entries are not one-liners. A typical entry names the symptom, the root cause, the fix, the measurement and what was not verified. That habit is visible from the very first lines.'),
    ...code('markdown', r'CHANGELOG.md · lines 1-5', r'''
# Changelog

All notable changes to this config are documented here.

## [Unreleased]'''),
    ...text('Below the Unreleased heading the entries are not grouped by version because the repository has not tagged a release since 1.8.0 on 2026-10-13. Everything since, including the macros and dependencies phase, the egui and Rust project flows, the website, the Windows and macOS work and the plugin extraction, sits in Unreleased. The Unreleased block is about 150 lines long (lines 5 to 156), so the most recent work was recorded under one heading and not split into versions.'),
    ...sec('the unreleased block, newest first'),
    ...text('The top entries are all dated 2026-10-22 and are about the plugins page, the counts, the voice of the documentation, website discoverability and positioning. They are written as short dated paragraphs, not nested lists. The first is the extraction of the nine plugins, seen from the website side.'),
    ...code('markdown', r'CHANGELOG.md · lines 7-7', r'''
- Plugins page, 2026-10-22: the nine published xyno plugins (history, sandbox, clipboard, guard, rust, new, imports, crates, macros; MIT, `v0.1.0`) are on the website: a Plugins section on the home page (nine cards, a dependency diagram, a copyable lazy.nvim snippet and the platform status of each) and `plugins/` (table, install order, one complete lazy.nvim spec for the Rust toolkit, a section per plugin, a FAQ, JSON-LD, share card `assets/og-plugins.png`). README has a Plugins section, `docs/DETAILS.md` a note. The wording is taken from the plugin READMEs: Linux tested, the sandbox and the clipboard provider Linux only, Windows and macOS not verified. The test figures were measured again with the whole suite on my Linux machine afterwards (1805 passing, 32 skipped, 0 failing, 38 spec files). Verified by `tests/site_spec.lua` (structure, JSON-LD, links, snippets are valid Lua and list their dependencies, wording); not verified: the plugin READMEs are not fetched by the spec, and xynovim still uses its own in-tree copies of the code.'''),
    ...text('The second entry corrects the figures. The README and docs/TESTING.md said 1795 passing, 31 skipped, 0 failing across 38 spec files when that entry was written (commit bd7201a); the later commit 2d4445e re-measured with the plugin specs and the README now says 1805 and 32, while this line is unchanged. The changelog states where they come from: the whole suite measured on my Linux machine, with the Ubuntu CI figures left unchanged.'),
    ...code('markdown', r'CHANGELOG.md · lines 8-8', r'''
- Counts, 2026-10-22: the test figures in the README and docs/TESTING.md (1795 passing, 31 skipped, 0 failing, 38 spec files) were measured by the whole suite on my Linux machine; the Ubuntu CI figures stay as they were.'''),
    ...text('The licence note is not in the changelog; it is in the commit history (724c508, keeping xynovim under Apache-2.0 with MIT for the plugins) and is covered by the LICENSE page of this explorer. The changelog does record the removal of tools/Dark.icls, which is why the Island Dark palette is generated from a file you supply yourself.'),
    ...code('markdown', r'CHANGELOG.md · lines 11-11', r'''
- Removed `tools/Dark.icls`: my scheme export is no longer distributed, only the palette generated from it (`lua/island/palette.lua`, same content). `tools/icls2nvim.py` stays as a converter for a scheme file you supply (without an input it prints a message and exits 1). The specs use a small synthetic `.icls` rebuilt from the palette.'''),
    ...text('The Positioning and Acknowledgements entries record wording decisions. The acknowledgements entries end with the words Text only, and the positioning entry says the facts and the history stay as they were. Naming what a change did not touch recurs in the file.'),
    ...sec('platforms: claims follow evidence'),
    ...text('Two entries explain the Windows and macOS work, and the second is the more important one. The first, written while the work was in progress and now the last of the two in the file, refuses to claim anything.'),
    ...code('markdown', r'CHANGELOG.md · lines 17-17', r'''
- Windows and macOS (in progress, nothing here is claimed as working until a `platforms` run shows it, see the run ids below when they exist). Code: PATH separator and `CARGO_HOME` in `options.lua`; bacon-ls accepts drive-letter roots; `disk_guard` compares normalized, case-folded paths; `.exe` for the debugger binary and the profiling run; `rust_restart` strips `.exe` and skips SIGCONT on Windows; `remote_clipboard` is Linux only; EguiNew unpacks with `tar` when `unzip` is missing on Windows; the manifest writers read and write binary (CRLF kept); `fsutil.rename` retries on Windows; `rust_context` canonicalizes roots; `health` skips unzip/gzip/mold/clang/bwrap on Windows and accepts any C compiler; lazy bootstrap does not wait for a key without a UI. Scripts: `scripts/bootstrap.ps1`, `scripts/test.lua` (`nvim --clean -l`, the runner of `test.sh` without bash) and `scripts/test.ps1`. Tests: `-- xyno-os:` header and `H.need_os` / `H.need_posix` skips with a printed reason, portable fixture copy, specs `agent-failclosed` and `scripts-portable`. CI: `.github/workflows/platforms.yml` (windows-latest, macos-latest; Neovim v0.12.5 pinned by URL and sha256).'''),
    ...text('The later entry replaces hope with run numbers: Windows green in several runs, macOS green once and not reliably, and README, website and repository description reduced to what those runs show. The same restraint shows in the iteration entry above it, where specs that failed for undiagnosed reasons skip with a printed reason and are listed in docs/KNOWN_ISSUES.md.'),
    ...code('markdown', r'CHANGELOG.md · lines 15-15', r'''
- Platforms, wording: README (Install, Platforms), the website (install section, limitations) and the repository description now say only what the `platforms` and `ci` runs show. Windows: run 39673715062 green (bootstrap.ps1, headless start, 1077 passed, 0 failed, 87 skipped; 10 of 38 spec files skipped whole), green in 3 of the last 4 runs (39660597368, 39663956677, 39673715062; 39668277143 failed on spec path assertions, fixed). macOS: not reliably green, green once (39663956677: 1431 passed, 0 failed, 73 skipped), red in 39660597368, 39668277143 and 39673715062 (a treesitter parser failed to compile during the plugin restore). Linux: `ci` run 39673715029, 1724 passed, 0 failed, 76 skipped. Still unverified: Local History, startup options, project creation and live rust-analyzer flows on Windows, codelldb on both, everything the 99 sandbox does off Linux (it refuses to start).'''),
    ...sec('the sandbox fails closed'),
    ...text('The security fix in Unreleased is worth quoting. The agent is started with a flag that skips Claude Code permission prompts, so the only thing between it and the user’s home directory is the sandbox. Before the fix, a missing sandbox backend meant the command ran unchanged. The entry names the old behaviour first.'),
    ...code('markdown', r'CHANGELOG.md · lines 20-20', r'''
- Agent sandbox fails closed. Without a working sandbox backend (Windows, macOS, Linux without `bwrap`) `agent_sandbox.wrap` returned the command unchanged, so `claude --dangerously-skip-permissions` ran with the user's full privileges and no message. Now `agent_sandbox.status()` gives `bwrap` / `unsandboxed` / `refused`, `wrap()` returns `nil, reason` when refused, and `Guarded.make_request` refuses before the snapshot, the auto-save toggle and the spawn (error notification, `on_complete("failed")`). `vim.g.xynovim_99_sandbox = false` stays the deliberate off switch, the new `vim.g.xynovim_99_allow_unsandboxed = true` permits an unsandboxed run only when there is no backend; only booleans count; every unsandboxed request warns. The module no longer needs a uid at load (`os_get_passwd` may fail off Linux). Specs `agent-sandbox` and `agent-99-guard` cover the matrix (the no-backend case runs on Linux by stripping PATH and by stubbing `has("linux")`); README, DETAILS, KNOWN_ISSUES and the site say Linux-only. Known: the other 99 providers (`<leader>9P`) are not wrapped.'''),
    ...text('The fix is commit 440d781 on 2026-10-16: agent_sandbox.status() returns one of three values, wrap() returns nil and a reason when refused, and the guarded provider refuses before taking the snapshot, pausing auto-save or spawning anything. A second entry, directly above, closes a related gap: the provider picker could swap in a stock provider that runs its command line with no sandbox at all, so it now accepts only the guarded one unless one of two explicit booleans is set.'),
    ...code('markdown', r'CHANGELOG.md · lines 19-19', r'''
- The 99 provider picker (`<leader>9P`) could swap in a stock provider (OpenCode, Cursor, Kiro, Gemini) that runs its CLI with no sandbox, checkpoint or auto-save guard. `_99.set_provider` and the picker now refuse anything but the guarded provider unless `vim.g.xynovim_99_sandbox = false` or `vim.g.xynovim_99_allow_unsandboxed = true`. `provision.lua` retries Mason packages whose install was aborted (codelldb failed the `ci` run 39635190559). The undiagnosed macOS/Windows skips and the whole-file macOS skips are listed in docs/TESTING.md.'''),
    ...sec('website, recordings and new project flows'),
    ...bullet('Website, 2026-10-16', 'the official site was added in 94ff2dc and deployed from an orphan commit on gh-pages; the entry records the pages run and the pages-build-deployment run ids so a reader can check.'),
    ...bullet('New Rust projects', 'dashboard entries b, i and w and the commands :RustNewBin, :RustNewLib, :RustNewWorkspace and :RustNewMember (commit d163480). The workspace is built by the config because cargo has no one-step command for it.'),
    ...bullet('Dashboard sizes', 'with 14 entries the layouts clipped, so the thresholds became formulas of the entry count: tall 2n+11 rows, header n+12, none below; every entry is visible from 80x18 up.'),
    ...bullet('egui toolchain', ':EguiNew stopped enforcing the template’s toolchain pin (commit 0cfb739) and gained a minimum-version check; the code that coped with the pin was removed, and the entries about it above are labelled as history.'),
    ...sec('macros and dependencies'),
    ...text('The next block, Added (macros and dependencies), lists the modules of the October 14 phase one by one. The entries are short and each names a file, so they double as an index of lua/config.'),
    ...code('markdown', r'CHANGELOG.md · lines 37-40', r'''
- Dependency freshness: saving `Cargo.toml` / `Cargo.lock` from nvim restarts bacon-ls 500 ms after the last save (it kept a stale `cannot find crate` error for minutes) and the statusline shows `deps resolving` until rust-analyzer has reloaded (6 s when it never went busy, 120 s ceiling). `config/rust_restart.lua`, `config/lsp_status.lua`.
- `config/crate_meta.lua` (cached `cargo metadata`, registry sources, a small crates.io client with sparse index and search, all argv lists, names validated) and `config/code_actions.lua` (find and apply one rust-analyzer code action without a menu).
- `config/crate_add.lua`: a hint on a path whose first segment is no dependency with the action "Add crate `x`", `:CrateAdd [query]` / `<leader>rA` (crates.io search with features and their descriptions, target package / `--dev` / `--build`, then `cargo add` and the import that triggered it).
- `config/crate_features.lua`: the action "Enable feature `derive` of `serde`" / `<leader>rG` for `cannot find derive macro / attribute / macro / function X`, found from the crate's own source and `[features]`; `:CrateFeatures [crate]` feature explorer with toggling.'''),
    ...text('The same phase has three more blocks: Fixed (review), Fixed (field test) and Changed. The pattern repeats across the file. A feature lands, a review pass finds problems, a field test finds more, and each round gets its own heading, which is why headings such as final loop round 5 exist: they mark the order in which bugs were found.'),
    ...sec('releases 1.8.0 to 1.5.0: the field-test loop'),
    ...text('The 1.8.0 section (2026-10-13) closes the fresh-install problem. The entry is a small research report: it reproduces the failure with empty XDG directories, states the cause after reading lazy.nvim’s code and confirming by experiment, and gives the recipe that worked.'),
    ...code('markdown', r'CHANGELOG.md · lines 157-168', r'''
## [1.8.0] — 2026-10-13

### Fixed (field test batch 5: fresh install, CI and docs)
- Fresh install did not reproduce `lazy-lock.json` (bug 28). Reproduced with
  empty XDG dirs and a clone: after `Lazy! restore` 6 of 79 plugins sat on newer
  commits and the lockfile was rewritten. Cause (lazy's code read, behaviour
  confirmed by experiments): the first install round only knows the plugins of
  the user spec and writes the lockfile with those, dropping the pins of the
  ones found in later rounds (LazyVim's extras). `Lazy! install`, original
  lockfile back, `Lazy! restore` ended with an identical lockfile (twice);
  restoring a second time without putting the lockfile back did not help.
- New `scripts/bootstrap.sh`: checks git, curl, tar, unzip, gcc, npm, node,'''),
    ...text('That entry is the origin of scripts/bootstrap.sh, which the README now explains in a paragraph. It also shows the second property of this file: the count of 6 of 79 plugins here is not the one the README gives today (5 of 79 in the first fresh-install tests, with kulala as a sixth until a later fix, and 61 locked after 18 theme-only plugins were dropped), and the README carries the later wording. The changelog keeps what was true when written.'),
    ...text('Release 1.7.0 holds field-test batches 2 to 4, which fix keys that did nothing, data safety (Local History exit snapshot, per-process index, size cap, prune) and editing and UI. The Removed block at line 146, still under Unreleased, records the end of Omarchy support after the Island Dark decision of 1.6.0, down to the renamed clipboard provider and the new option name.'),
    ...code('markdown', r'CHANGELOG.md · lines 146-155', r'''
### Removed
- All Omarchy support. Deleted `lua/plugins/omarchy-theme-hotreload.lua`, the
  `lua/plugins/theme.lua` symlink, `lua/plugins/all-themes.lua` (18 colourscheme
  plugins that only Omarchy themes used) and the `theme.lua` loadfile guard in
  `lua/config/lazy.lua`; `vim.g.xynovim_follow_omarchy` is gone and Island Dark
  is set unconditionally. The 18 plugins are dropped from `lazy-lock.json`
  (tokyonight and catppuccin stay: LazyVim specs them). The remote clipboard
  provider is now `XynovimRemoteClipboard` and its OSC 52 opt-out is
  `vim.g.xynovim_remote_clipboard_osc52` (was `omarchy_remote_clipboard_osc52`).
  Older entries below keep their Omarchy wording as history.'''),
    ...text('Release 1.6.0 itself changed the theme: Island Dark became the permanent colourscheme with transparency as the default, and the entry ends with its own verification statement, including what was not verified.'),
    ...code('markdown', r'CHANGELOG.md · lines 289-300', r'''
## [1.6.0] — 2026-10-12

### Changed
- Theme: Island Dark (my own "Dark" scheme, parent Darcula) is now
  the permanent colourscheme. `tools/icls2nvim.py` converts `tools/Dark.icls` to
  `lua/island/palette.lua`; `lua/island/init.lua`, `colors/island-dark.lua` and a
  lualine theme map it to UI, Treesitter, LSP semantic (`org.rust.*`) and plugin
  groups. Omarchy's theme spec and hot-reload no longer override it (set
  `vim.g.xynovim_follow_omarchy = true` to follow Omarchy again). Transparency
  stays the default; new `<leader>uO` toggle. Verified headless (49 colour checks
  against an independent parse of the `.icls`, real rust-analyzer tokens) and in
  tmux (24-bit SGR); not verified with a live Omarchy theme switch.'''),
    ...text('Release 1.5.0 (2026-10-09) carries the review findings that hardened the sandbox, Local History and the 99 guard, and the Roadmap step 11 additions: the claudecode extra, a lualine readiness component, a right-click Rust menu, an opt-in colour-blind diagnostic palette and :checkhealth xynovim.'),
    ...code('markdown', r'CHANGELOG.md · lines 398-410', r'''
## [1.5.0] — 2026-10-09

### Fixed
- Review findings: agent sandbox now keeps `.git/hooks`, `.git/config` and
  `~/.claude` settings/hooks read-only and hides more credential paths and
  variables; local history retries forced snapshots, times out hung git and
  reports `update-ref` failures; 99 guard restores auto-save on a synchronous
  throw; npm installed and checked by `:checkhealth xynovim` (markdownlint
  ENOENT); README startup time, log path, `:ClaudeCode`, kulala keys and
  layout corrected.

### Added
- Roadmap step 11: LazyVim extra `ai.claudecode`, a lualine rust-analyzer /'''),
    ...sec('releases 1.4.x to 1.1.0: the bacon-ls story'),
    ...text('The September 2026 releases are one continuous investigation into a single tool. 1.1.0 (2026-09-03) adds live-as-you-type Rust diagnostics through bacon-ls, which is how the project’s centrepiece began.'),
    ...code('markdown', r'CHANGELOG.md · lines 645-656', r'''
## [1.1.0] — 2026-09-03

### Added
- **Live-as-you-type Rust diagnostics via bacon-ls** — the always-on
  inspections known from the JetBrains IDEs. `vim.g.lazyvim_rust_diagnostics = "bacon-ls"` in
  `options.lua` hands the diagnostics role to bacon-ls (LazyVim's rust extra
  disables rust-analyzer's own checkOnSave/diagnostics to avoid duplicates);
  rust-analyzer keeps completion, goto/references, hover, inlay hints, and
  code actions. New `lua/plugins/bacon-ls.lua` configures bacon-ls 0.29's
  native **cargo backend**: clippy (`--workspace --all-targets
  --all-features`) run by the server itself, with `updateOnInsert = true` —
  it mirrors the workspace into a hardlinked shadow under'''),
    ...text('1.3.0 fixes the first performance problem: two clippy pipelines were cancelling each other and serialising on cargo’s build-dir lock. The measured result is in the entry, 5.6 s down to 0.8 to 0.9 s from edit to diagnostic on a warmed project, together with an A/B test that proved updateOnInsert had to stay on.'),
    ...code('markdown', r'CHANGELOG.md · lines 549-559', r'''
## [1.3.0] — 2026-09-03

### Fixed
- **Slow, churning diagnostics ("checking (0%)" rows stacked for minutes).**
  Root cause: two clippy pipelines — `checkOnSave` runs (triggered by the ~1s
  auto-save) racing `updateOnInsert` shadow runs — cancelling each other and
  serializing on cargo's build-dir file lock, with `--all-targets` doubling
  every run's scope. Fixed: `checkOnSave = false` (single pipeline),
  `--all-targets` dropped, debounce 500→800ms. Measured 5.6s → 0.8–0.9s
  edit-to-diagnostic on a warmed project. A/B testing also proved
  `updateOnInsert` must stay on: without it bacon-ls advertises no document'''),
    ...text('1.4.0 (2026-09-04) then finds that bacon-ls itself aborts its debounce task even after the sleep has elapsed, killing the in-flight cargo run and leaking progress tokens. The fix was a locally patched build.'),
    ...code('markdown', r'CHANGELOG.md · lines 504-515', r'''
## [1.4.0] — 2026-09-04

### Fixed
- **bacon_ls stuck on "checking…" with stale diagnostics — root-caused to an
  upstream bacon-ls 0.29.0 bug and fixed in a locally patched build**
  (`~/.local/src/bacon-ls-0.29.0-patched`, installed at `~/.cargo/bin/bacon-ls`,
  wired via `cmd` override in `lua/plugins/bacon-ls.lua`). Upstream `abort()`s
  its debounce task even after the sleep has elapsed — at that point the task
  IS the in-flight cargo run, so any keystroke or auto-save `didSave` killed
  the run silently: progress tokens leaked (begin, never end → the immortal
  stacked "checking" rows), the cargo child died mid-check, and the last run
  of every typing burst was murdered ~200ms in by auto-save (debounce 1000ms'''),
    ...text('1.4.1 sends the three fixes upstream as crisidev/bacon-ls#139 and rebuilds on 0.30.0. docs/HISTORY.md records that #139 was merged on 2026-09-10 and shipped in bacon-ls 0.31.0 on 2026-09-20, and that its 2026-10-09 reality check found the local override pointing at binaries that did not exist and removed the override in lua/plugins/bacon-ls.lua.'),
    ...code('markdown', r'CHANGELOG.md · lines 483-492', r'''
## [1.4.1] — 2026-09-04

### Changed
- The three bacon-ls fixes were **upstreamed as
  [crisidev/bacon-ls#139](https://github.com/crisidev/bacon-ls/pull/139)**.
  The local binary now builds from upstream 0.30.0 + that branch
  (`~/.local/src/bacon-ls-upstream`) instead of the 0.29.0 fork. The
  run-abort fix was reworked to add no struct field (the debounce task drops
  its own handle after its sleep rather than tracking a generation counter),
  keeping the `BackendRuntime` `large_enum_variant` size lint quiet — upstream'''),
    ...text('Release 1.2.0 sits between them and is a different kind of bug: every 99 response came back empty because 99 and Claude Code resolved a relative tmp_dir against different directories. The entry explains that generation had worked the whole time and the answers were sitting unread on disk, and the fix is an absolute path.'),
    ...code('markdown', r'CHANGELOG.md · lines 607-619', r'''
## [1.2.0] — 2026-09-03

### Fixed
- **99 responses were always empty — root cause: relative `tmp_dir` resolved
  differently by each side of the pipeline.** 99 resolves `tmp_dir` against
  nvim's cwd, but claude (agentic, working on project files) resolves the same
  relative `TEMP_FILE` path against the project directory. Launching
  `nvim Projects/foo/` from `~` meant claude faithfully wrote every answer to
  `Projects/foo/tmp/99-*` while 99 read the empty placeholder in `~/tmp/99-*`
  — generation worked the whole time; the completed responses were found
  sitting unread on disk. Fixed by making `tmp_dir` absolute
  (`~/.cache/nvim/99`), unambiguous for both sides and cwd-independent; safe
  outside claude's cwd because ClaudeCodeProvider passes'''),
    ...sec('1.0.0 and the Windows lineage'),
    ...text('1.0.0 (2026-09-02) is the pivot of the whole history: the from-scratch Windows config is replaced by a LazyVim-based config on Linux. The entry calls it a platform lineage switch, not an incremental edit.'),
    ...code('markdown', r'CHANGELOG.md · lines 678-690', r'''
## [1.0.0] — 2026-09-02

### Changed
- **Migrated the whole config from the from-scratch Windows setup to a
  LazyVim-based config on Linux (Omarchy/Arch).** This is a platform lineage
  switch, not an incremental edit — the previous tree (everything under
  `lua/config/plugins/`, the nvim-cmp/mason wiring in `lsp.lua`, and the
  Windows-specific `bootstrap-device.ps1`) is replaced by the LazyVim starter
  (v8) layout with custom specs under `lua/plugins/`. The old Windows config
  remains untouched on the `master` branch.
- **Rust tooling: hand-rolled `lsp.lua` → LazyVim's `lang.rust` extra**
  (rustaceanvim + rust-analyzer + crates.nvim + codelldb via Mason), plus a new
  `lua/plugins/rustaceanvim.lua` override: clippy (`--no-deps`) as the on-save'''),
    ...text('Note a disagreement. This entry says the old Windows config remains on the master branch, while the README says the previous config lives on the windows-legacy branch. Only one of them can describe the repository today, and the changelog entry is the older text.'),
    ...text('Under 1.0.0 sit entries labelled Unreleased, Windows lineage, superseded by 1.0.0 on this branch. They are the final entries of the old line, such as replacing setup-onedrive-link.ps1 with a full device bootstrap, kept so the history of the earlier tree is not lost.'),
    ...code('markdown', r'CHANGELOG.md · lines 724-730', r'''
## [Unreleased — Windows lineage, superseded by 1.0.0 on this branch]

### Changed
- **`setup-onedrive-link.ps1` replaced by `bootstrap-device.ps1` — a full autonomous
  device bootstrap, not just a link script.** Meant to be run from an elevated shell
  directly off GitHub (`irm .../bootstrap-device.ps1 | iex`) on a clean machine, or one
  with an existing config to replace. Every dependency this config actually needs is'''),
    ...sec('0.2.0 and 0.1.0: where it started'),
    ...text('The two oldest sections describe the initial config. 0.1.0 is the first push of 2026-08-17 (commit 1c496fd): a minimal Neovim configuration for Rust, Node and TypeScript, PowerShell and Flutter, plus the 99 plugin on Claude Code.'),
    ...code('markdown', r'CHANGELOG.md · lines 939-945', r'''
## [0.1.0] — initial commit

First push. Bootstrapped from scratch (inspired by, not cloned from, ThePrimeagen's
init.lua), scoped to Rust / Node+TypeScript / PowerShell / Flutter+Dart plus 99 on
Claude Code.

- lazy.nvim, Telescope, Treesitter + treesitter-context (lua, vim, vimdoc, query, rust,'''),
    ...text('0.2.0 adds the first IDE-like touches: background auto-save (with the okuuva fork because the original plugin is unmaintained since 2024-05) and styled inline diagnostics. The auto-save entry already shows the later style of the file, with a stated verification.'),
    ...code('markdown', r'CHANGELOG.md · lines 909-915', r'''
## [0.2.0]

### Added
- `auto-save.nvim` (`okuuva` fork — the original `Pocco81/auto-save.nvim` has been
  unmaintained since 2024-05) for background auto-save, as in the JetBrains IDEs. Configured with
  `noautocmd = true` so debounced autosaves don't also trigger format-on-save; only a
  manual `:w`/`<leader>f` formats. Verified: an intentionally mis-formatted file survives'''),
    ...sec('design decisions in the file itself'),
    ...bullet('Newest first', 'the reader who wants to know what changed lately never scrolls; the reader who wants the origin of a behaviour searches for the file name or the symptom.'),
    ...bullet('Root causes, not symptoms', 'entries such as bacon_ls stuck on checking and 99 responses always empty are written as small postmortems and make the later documents shorter.'),
    ...bullet('Verified and not verified', 'many entries end by saying what was run (headless checks, tmux, a real rust-analyzer) and what was not (a live Omarchy theme switch, a real terminal for pickers).'),
    ...bullet('History is kept, not rewritten', 'superseded entries stay, with a note that they are history (egui toolchain, Omarchy wording), so the file records how decisions changed.'),
    ...bullet('Not a release log', 'most entries describe a day of work, not a tagged artefact; the version headings are checkpoints.'),
    ...sec('how it is tested'),
    ...text('The changelog is not parsed by a spec of its own, but claims about it are checked. tests/test-infra-readme-claims_spec.lua asserts statements the README and CHANGELOG make about the test infrastructure, and tests/site_spec.lua checks that the README, which the changelog supports, agrees with the website. The staleness of numbers inside old entries is intentional and is not tested.'),
    ...sec('history'),
    ...bullet('2026-08-17', 'CHANGELOG.md first appears in 3dacffb, the same day as the initial commit, together with the IDE-like diagnostics, auto-save and the 99 model bump.'),
    ...bullet('2026-10-13', '1.8.0, the last numbered release.'),
    ...bullet('2026-10-22', '9723a11 (Changelog: record the positioning and SEO work), 764702c (Site: plugin specs, README, DETAILS and CHANGELOG) and 2d4445e (Counts: re-measured with the plugin specs) are the latest edits.'),
    blank,
  ],
);
