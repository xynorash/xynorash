import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/docs/DETAILS.md',
  lines: [
    heading('# xynovim in detail'),
    blank,
    ...text('docs/DETAILS.md is the reference behind the README: for each setting it says why it is what it is, what was measured and, in bold, what was not verified. The README is the overview with screenshots; this file is where a reader goes to find out why checkOnSave is off, why a hardlinked shadow directory exists, or why a keybinding is buffer-local. It is 159 lines, but most lines are a paragraph long, and it has been edited 17 times since it was split out of the README on 2026-10-14.'),
    blank,
    kv('role', 'engineering notes: reasons, measurements and unverified claims'),
    kv('language', 'Markdown'),
    kv('size', '159 lines, 11 headed sections from Rust and the 99 agent to the website'),
    kv('origin', 'split out of the README in 0b0eee8 (2026-10-14)'),
    kv('updated', 'last in 764702c (2026-10-22), which added the xyno plugins section; the Website section came with 94ff2dc on 2026-10-16'),
    blank,
    ...sec('why this file exists'),
    ...text('Until 2026-10-14 the README carried everything: the roadmap, the feature notes, the measurements. Commit 0b0eee8 turned the README into a showcase of screenshots and videos recorded from the real configuration and moved the engineering text here. The opening paragraph says so, and also points at the git history for the old step-by-step wish list, which later became docs/HISTORY.md.'),
    ...code('markdown', r'docs/DETAILS.md · lines 3-3', r'''
Engineering notes behind the README: why each setting is what it is, what was measured and what was **not** verified. The README is the overview; this file is the reference. (The old step-by-step wish list this config was built from is in the git history before the "README: showcase" commit.)'''),
    ...text('The split follows a rule the repository applies everywhere: a claim lives once, where it is checked. The README says what you get; this file says what was measured; docs/KNOWN_ISSUES.md says what was left alone; tests/COVERAGE.md says which spec checks it.'),
    ...sec('two-tier diagnostics, in numbers'),
    ...text('The first bullets of the Rust section explain the centrepiece of the repository. The instant tier is rust-analyzer’s own in-memory diagnostics, measured at 0.01 to 0.15 seconds warm, and in practice that means type errors such as E0308. Unresolved names (E0425, E0599, E0432) come from the depth tier about 0.6 seconds later, because the setting that would make rust-analyzer report them was measured and rejected.'),
    ...code('markdown', r'docs/DETAILS.md · lines 13-13', r'''
  - The only overlap is visual: a type error can briefly show from both sources.'''),
    ...text('That rejection is the best-documented decision in the file. On a copy of a real 196-file axum and sqlx workspace that builds cleanly, one sweep per setting, turning diagnostics.experimental.enable on gave 82 false errors (74 E0282 and 8 E0277) plus 6 inactive-cfg hints, against 0 with it off. On a small std-only crate it did surface the unresolved-name errors in 0.01 to 0.15 seconds, so the file concedes the trade is real and says only that the false-positive rate is not acceptable.'),
    ...text('The depth tier is bacon-ls running clippy against a hardlinked shadow of the workspace under target/bacon-ls-live, with a 500 ms debounce, on every buffer change. Two settings look wrong to a newcomer and the text defends both. checkOnSave is off because with a one-second auto-save it was a second cargo pipeline racing the live one: the runs cancelled each other and serialised on cargo’s build-dir lock, measured at 5.6 seconds edit to diagnostic with both pipelines against sub-second with one. updateOnInsert must stay on because without it bacon-ls advertises no document sync and diagnostics never refresh. That sequence is also the story of CHANGELOG 1.3.0.'),
    ...text('The bacon-ls fixes are upstream. The bullet on line 15 records that the local patched build and its cmd override are gone: Mason’s bacon-ls at 0.31.0 or newer carries the three fixes merged as crisidev/bacon-ls#139.'),
    ...sec('supervision, freshness and external changes'),
    ...text('The server supervision bullet is the longest in the file and shows how many ways a language server can be wrong while looking alive. A dead rust-analyzer or bacon-ls used to stay dead because the restart commands need a live client. Now the statusline says RA stopped or clippy stopped, the server restarts after 0.5 s, at most three times a minute, then gives up with an error; a graceful exit is left alone. clippy failed replaces a false clippy ok when cargo cannot run (a broken manifest, a cyclic dependency), because bacon-ls ends such a run normally and only sends a window/showMessage error.'),
    ...bullet('clippy stale', 'counts text changes through nvim_buf_attach instead of TextChanged, because it stayed up for good after an auto-save while typing: a write bumps b:changedtick too. The fix was checked by typing with auto-save on and watching the status settle.'),
    ...bullet('External changes', 'bacon-ls hardlinks the workspace once and re-syncs only the files nvim reports, so sed -i, a git checkout or an agent rewriting files left clippy checking old content. On FocusGained, debounced 300 ms, bacon-ls restarts when a watched buffer was reloaded from disk or git HEAD moved.'),
    ...bullet('Workspace root', 'bacon-ls roots at the outermost Cargo.toml with a [workspace] table, because the nearest-manifest root made the shadow hold only the member and cargo failed.'),
    ...bullet('Debugger', 'the Rust configs prompt with a default of the cargo target directory plus debug and the binary name taken from cargo metadata; every codelldb launch loads lldb’s Rust formatters from the rustc sysroot so a String shows as text. Full debuginfo is required for the Local scope: line-tables-only and limited show no locals.'),
    ...text('Dependency freshness, added in October, extends the same supervision. Saving Cargo.toml or Cargo.lock restarts bacon-ls 500 ms after the last write and the statusline shows deps resolving until rust-analyzer reports quiescence, with a 6 second bound when it never went busy and a 120 second ceiling. The text says the ceiling is checked with a shimmed timer, not waited out live, and that is repeated in the Not verified bullet.'),
    ...sec('the 99 agent'),
    ...text('The 99 section is short and records settings that look arbitrary until you know the failure behind them. The first is the origin of CHANGELOG 1.2.0: tmp_dir must be an absolute path, because 99 resolves a relative path against nvim’s working directory while the agent resolves it against the project.'),
    ...code('markdown', r'docs/DETAILS.md · lines 31-32', r'''
- `tmp_dir` **must be an absolute path** (here: `~/.cache/nvim/99`). 99 resolves a relative tmp_dir against nvim's cwd, but claude resolves the same relative TEMP_FILE against the project it's working in — launch nvim from outside the project and every response comes back empty because the answer lands where 99 never reads.
- The logger needs `type = "file"` for `path` to take effect; the plugin README's example omits it and logs silently go nowhere. Logs land at `~/.local/state/nvim/99.log` (see CHANGELOG.md).'''),
    ...text('The sandbox bullet (line 33) is the specification of the fail-closed behaviour. status() returns bwrap, unsandboxed or refused; wrap() returns nil and a reason when refused; the guarded provider then notifies the reason, completes the request as failed and starts nothing, with no snapshot and no auto-save change. The deliberate off switch is vim.g.xynovim_99_sandbox set to false; the other boolean, vim.g.xynovim_99_allow_unsandboxed, only counts when no backend exists. Only real booleans count, and every unsandboxed request warns. It also records that macOS sandbox-exec is deprecated and not implemented here. The tests are agent-sandbox, agent-failclosed and agent-99-guard.'),
    ...code('markdown', r'docs/DETAILS.md · lines 36-44', r'''
| Keymap | Action |
| --- | --- |
| `<leader>9s` | Search (results → quickfix) |
| `<leader>9v` / `<leader>9vv` (visual) | Vibe / replace selection |
| `<leader>9o` | Open last interaction |
| `<leader>9l` | View logs |
| `<leader>9c` / `<leader>9x` | Clear previous / stop all requests |
| `<leader>9w` / `<leader>9W` | Worker search / set work |
| `<leader>9m` / `<leader>9P` | Select model / provider (telescope) |'''),
    ...sec('editor behaviour'),
    ...text('The auto-save bullet is where data safety is argued. Auto-save fires after about a second including while typing, and a User AutoSaveWritePost hook does two jobs: it joins the undo block, because the mid-insert write closed it and one undo then reverted only the last stretch typed after a pause, and it re-sends textDocument/didSave so servers that act on save still do. The disk guard refuses to write dependency and std sources (buffers under the cargo registry, cargo git and rustup are nomodifiable) and refuses to write over a file that changed on disk, comparing the recorded mtime before the save and again just before the write. The spec is auto-save-disk-guard.'),
    ...code('markdown', r'docs/DETAILS.md · lines 50-50', r'''
- Format-on-save off globally (`vim.g.autoformat = false`), relative numbers off.'''),
    ...text('The Editing and UI bullets are the result of a field-test batch (batch 4). Three are worth naming. A single quote is typed plainly in Rust buffers because mini.pairs paired it after an ampersand or a less-than sign and turned a lifetime into broken syntax. Diagnostic virtual text shows the first line plus the source, because clippy sends about 14 lines, and a problem both tiers report is shown once, preferring rust-analyzer. blink.cmp hides snippets after a dot and inside strings and comments, because a friendly-snippets entry outranked rust-analyzer’s postfix completion.'),
    ...sec('theme: generated, and lifted for legibility'),
    ...text('The Theme section is dense with numbers and states the provenance in its first paragraph: Island Dark is my own scheme exported from RustRover, the export is not distributed, only the generated palette. The Generated bullet explains that tools/icls2nvim.py parses colours, bold, italic and underline effects and the base-attribute inheritance, and writes lua/island/palette.lua.'),
    ...code('markdown', r'docs/DETAILS.md · lines 71-71', r'''
- **Theme plugins**: Island Dark is set unconditionally in `lua/plugins/island-theme.lua`; no theme-switching machinery or extra colourscheme plugins are kept. Only the plugins LazyVim itself specs (tokyonight, catppuccin) remain as install fallbacks.'''),
    ...text('The Legibility lifts bullet is the reason the theme is not a faithful port. A contrast review computed WCAG ratios from the loaded highlight groups against targets of 4.5 to 1 for body text and 3 to 1 for secondary. Comments (4.0 to 1) and doc comments (3.8 to 1) were mixed toward white just far enough to reach 4.5; line numbers use a lighter scheme colour at 3.5 because the scheme’s own is 2.0; git modified moved from 2.7 to 7.2. The cursorline stays a subtle band at 1.20 to 1, which the Not verified bullet admits is by design. lift() in lua/island/init.lua does the mixing, and theme-island is the spec.'),
    ...sec('macros and dependencies: how it is built'),
    ...text('This section is the design record for the October phase. The decisions are architectural and the bullets give reasons.'),
    ...bullet('Client side only', 'no custom language server. The two code-action sources are tiny in-process LSP clients with a cmd function and no process that declare only codeAction and executeCommand, so the lightbulb and the code-action key see them like any other client and nothing is monkey-patched.'),
    ...bullet('argv lists everywhere', 'cargo, git and curl are started with a table, never a shell string, and crate, feature and package names from the network or files are validated before they reach an argument list.'),
    ...bullet('The missing-feature map', 'computed from the crate’s own source: the name is looked up in lib.rs and the modules it declares behind cfg(feature) gates and resolved through the features table, so no per-crate rule is written by hand.'),
    ...bullet('Import from a non-dependency', 'only fills gaps; crates.io is searched by crate name, so the names are guesses and labelled so; add-and-import runs cargo add, then polls rust-analyzer every second for up to 60 s.'),
    ...bullet('Buffer-local keys', 'keymaps.lua parks hidden not-bound stubs on every global leader r key, so rA, rG, rI, rO, rx and rq are set per Rust buffer after rust-analyzer attaches. The two modules start from User VeryLazy autocmds, not virtual lazy.nvim specs, because two virtual specs counted as plugins (63 against the 61 in the lockfile).'),
    ...code('markdown', r'docs/DETAILS.md · lines 88-89', r'''
- **Measured**: headless startup, 20 runs, cwd `/tmp`, no file argument: min 25.15, median 26.03, max 28.37 ms against 24.0 to 25.2 ms (mean 24.5) above; 4 of 61 plugins loaded, as before. `crate_meta`, `crate_features` and `macro_attrs` load at startup (about 1.2 ms in total); `crate_add`, `crate_import`, `import_engine` and `macro_tools` load at `VeryLazy` or on use. Deferring the first three to `VeryLazy` would remove that 1.2 ms (not done). Real runs against crates.io, `cargo` and rust-analyzer 1.99: `Uuid` in a crate with no dependencies is added and imported and `cargo check` passes; serde without `derive` is fixed by the action and `cargo check --offline` passes; `#[serde(` completes `rename_all` and `camelCase`; an ambiguous `Error` is left alone by auto-import until `std::io::Error` is remembered (`macros-deps-flows` spec, on temp copies of the fixtures).
- **Not verified**: the snacks pickers and key presses driven in a real terminal (the specs stub `vim.ui.select` and the pickers), the `ask` prompt, the 120 s "deps resolving" ceiling in a live session, `<leader>rI` / `<leader>rG` interactively, `stylua --check` is not clean (Mason's stylua reports drift in 61 files under `lua/` and `tests/`, the new modules and specs among them (it was 16 files before this work); nothing was reformatted to keep the diff reviewable), a field-test round, the demo recordings of the plan (phase 4). Residual: `#[serde(` keys are offered while the `derive` feature is off; "(guess)" candidates miss crates whose name is unrelated to the item (`Rng` does not find `rand`); the 14 orphan rust-analyzer processes the test runs left were killed by pid.'''),
    ...sec('new projects and egui'),
    ...text('The New Rust projects bullets give the reasoning for building a workspace by hand: cargo new makes one package. The root manifest is generated from the edition found by running cargo new in a temporary directory once per session, never hard-coded, with resolver 3 from edition 2024; the member is made with cargo new and only its version and edition keys are rewritten to workspace inheritance. On failure only what the run itself created is removed. The dashboard thresholds are formulas of the entry count, measured with 14 entries in tmux.'),
    ...text('The egui section is about hygiene, because the program downloads and unpacks an archive. Entries are listed first and absolute or parent paths are refused, the unpacked size is capped at 300 MB, symlinks are rejected and exactly one top-level directory is required; the cache stores the ETag with its URL and is used only for the same URL. The final bullet explains the deleted toolchain pin.'),
    ...code('markdown', r'docs/DETAILS.md · lines 114-115', r'''
- Remote-plugin providers (python3/ruby/perl/node) disabled — nothing uses them.
- 99's request cache (`~/.cache/nvim/99`) is pruned of week-old files on load.'''),
    ...sec('performance and layout'),
    ...text('The Performance choices list gives the startup figure with its method: 20 headless runs from /tmp, 24.0 to 25.2 ms, mean 24.5, with 4 of 61 plugins loaded. It carries its own correction, since an earlier 35 ms figure was taken on a busier machine and is probably load. Later in the same file the macros phase is measured against it: median 26.03 ms in 20 runs. The long-form layout block repeats the README layout, and the final two sections describe the nine plugins and the website.'),
    ...bullet('The xyno plugins', 'the section says outright that descriptions and install snippets are copied from each plugin README, not invented, and that the in-tree copies of the code in xynovim have not been replaced by the plugins.'),
    ...bullet('Website', 'numbers on the page are placeholders filled by scripts/build-site.py from the README; the policy is a strict content security policy with no external requests; deployment is a force-pushed orphan commit on gh-pages.'),
    ...sec('edge cases the notes mention'),
    ...bullet('Large files', 'a Rust file over 1.5 MB gets Snacks bigfile treatment (no LSP) and so does one with an average line length over 1000.'),
    ...bullet('Offline', 'the crate_meta bullet describes the crates.io client as cached on disk and offline tolerant, with functions that return a result and an error instead of raising for network or tool problems.'),
    ...bullet('Taplo', 'its failed to fetch catalog line in lsp.log is not silenced, because taplo fetches before it reads settings.'),
    ...sec('how it is tested'),
    ...text('DETAILS.md is the place that names the specs. The ones it cites most often are keymaps-global, rust-analyzer-config, bacon-ls-config, server-supervision-statusline, auto-save-disk-guard, agent-sandbox, theme-island, rust-new and egui-new, and for the macros phase crate-meta, crate-add, crate-features, import-engine, crate-import, macro-attrs, macro-tools and macros-deps-flows. Some of its claims are checked by tests/test-infra-readme-claims_spec.lua. The unverified parts are named, not tested.'),
    ...sec('history'),
    ...bullet('2026-10-14', '0b0eee8 creates the file from the README; b9363cd adds the macros and dependencies section.'),
    ...bullet('2026-10-15', 'ddc51eb adds the New egui project section.'),
    ...bullet('2026-10-16', '94ff2dc adds the Website section and d163480 the New Rust projects section; 0cfb739 changes the egui text for the removed toolchain pin.'),
    ...bullet('2026-10-22', 'the plugins section arrives in 764702c, which is also the last commit to touch the file.'),
    blank,
  ],
);
