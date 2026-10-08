import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/CHANGELOG.md',
  lines: [
    heading('# CHANGELOG.md'),
    blank,
    ...text('The longest file in the repository, and the one that '
        'holds the evidence. It runs to 478 lines and about 3,900 '
        'words, against 759 lines of Lua for the whole '
        'configuration. Almost every number in the README (5.6 s '
        'down to 0.9 s, 28.7 ms down to about 18 ms, a median of '
        '0.56 s) is first written down here, together with what '
        'was measured, on what, and how the result was checked. '
        'It is not a list of release notes. It is the lab notebook '
        'of a configuration that was debugged like a program.'),
    blank,
    kv('role', 'history of the config and the evidence behind it'),
    kv('format', 'Markdown, newest section first, 9 headed sections'),
    kv('size', '478 lines, about 3,900 words, 30 KB'),
    kv('versions', '0.1.0 to 1.4.1; no git tags exist, headings only'),
    kv('span', '2026-08-17 to 2026-09-04, edited by 17 commits'),
    kv('habit', '17 of the repo’s 20 non-merge commits touch it'),

    ...sec('why a configuration keeps a changelog this long'),
    ...text('The README says it in one sentence: “Every notable '
        'change is documented in CHANGELOG.md, including what was '
        'verified and how.” The second half of that sentence is '
        'the unusual part. A typical changelog says what changed. '
        'This one says what was true before, why, what was done, '
        'and what test showed the change had worked. The word '
        '“verified” appears 25 times in it, “measured” four '
        'times, and “root cause” in one spelling or another five '
        'times.'),
    ...text('The habit is also visible in the git history. Of the '
        '27 commits in the repository, 7 are merges of pull '
        'requests. Of the other 20, 17 edit this file in the same '
        'commit as the change they describe. The three that do '
        'not are the initial commit (the file did not exist yet), '
        'the one-line rename to xynovim (5e60f65) and a README '
        'tweak (9fff81e). So there is no gap between code and '
        'record: if a behaviour changed, the explanation was '
        'written in the same breath.'),
    ...text('The same duplication shows up in the Lua. The comment '
        'above updateOnInsertDebounceMillis in '
        'lua/plugins/bacon-ls.lua repeats the measurements from '
        'the 1.4.0 entry below. The split seems deliberate: the '
        'changelog is where the experiment is described, the '
        'comment is where the conclusion sits next to the line it '
        'justifies. That is an inference from the two texts, not '
        'something either of them states.'),

    ...sec('anatomy of an entry'),
    ...text('Entries are not terse. The good ones follow the same '
        'four beats: a bold symptom, the root cause, the change, '
        'and the check. Here is the first bullet of the 1.2.0 '
        'entry:'),
    ...code('md', 'CHANGELOG.md · 1.2.0, the first Fixed bullet (trimmed)', r'''
- **99 responses were always empty — root cause: relative `tmp_dir` resolved
  differently by each side of the pipeline.** 99 resolves `tmp_dir` against
  nvim's cwd, but claude (agentic, working on project files) resolves the same
  relative `TEMP_FILE` path against the project directory. Launching
  `nvim Projects/foo/` from `~` meant claude faithfully wrote every answer to
  `Projects/foo/tmp/99-*` while 99 read the empty placeholder in `~/tmp/99-*`
  — generation worked the whole time; the completed responses were found
  sitting unread on disk.'''),
    ...text('Read it as a small case study. The symptom (“always '
        'empty”) points at generation, and the natural next move '
        'is to tinker with prompts, models or flags. The entry '
        'records that generation worked the whole time and the '
        'answers were sitting on disk in the wrong place. The '
        'next bullet in the same entry says how that was '
        'discovered: the plugin’s logger was silently discarding '
        'everything, because its file path only takes effect when '
        '`type = "file"` is set, and “this log was what exposed '
        'the tmp_dir mismatch.” The order of discovery matters: '
        'first make the failure observable, then fix it. The '
        'entry also keeps a dead end. It says an earlier '
        'same-day attempt with a relative ./tmp path “never '
        'pushed” fixed one case and broke another, and was '
        'superseded.'),
    ...text('The 1.2.0 entry closes with its own evidence: the fix '
        'was verified end to end twice, once with the working '
        'directory inside the project and once at the home '
        'directory, “mimicking the real launch shape”. The '
        'config that resulted lives in lua/plugins/ninety-nine.lua, '
        'and its comments are a compressed version of this '
        'paragraph.'),

    ...sec('the shape of the file'),
    ...text('Reading from the top, the file has three eras with '
        'very different densities.'),
    ...bullet('lines 5 to 245, versions 1.4.1 down to 1.0.0',
        'the LazyVim era on Linux. Six releases between '
        '2026-09-02 and 2026-09-04, 241 lines, 50 percent of the '
        'file. Each has a date.'),
    ...bullet('lines 246 to 430, “Unreleased — Windows lineage”',
        '185 lines, 39 percent of the file, with no version '
        'number. It records the nine commits of 2026-08-18 on the '
        'earlier from-scratch Windows config. More below.'),
    ...bullet('lines 431 to 478, versions 0.2.0 and 0.1.0',
        'the two oldest releases, 48 lines. Neither has a date '
        'in its heading; 0.1.0 is labelled “initial commit”.'),
    ...text('The heading vocabulary (Added, Changed, Fixed, '
        'Removed, and an Unreleased section) is the familiar '
        'Keep a Changelog convention, though the file never cites '
        'it. Two headings are the author’s own: “Verified” (used '
        'in 1.4.0 and, as “Verified (no code change)”, in the '
        'Windows block) and “Docs” (1.4.1). Verified is the '
        'interesting one. It exists for results that changed '
        'nothing in the code but changed what is known: the '
        'ESLint server resolves ESLint from the project’s own '
        'node_modules and silently does nothing without a local '
        'install. A bullet in 1.3.0 does the same in spirit '
        'under Added: blink.cmp was checked and is on its native '
        'Rust fuzzy matcher, because “the Lua fallback '
        'downgrade is silent”.'),
    ...text('Another trace of how the file was built: inside the '
        'Windows block the same heading repeats. “Changed” '
        'appears three times, “Added” three times and “Fixed” '
        'twice. Several commits put their own sections above the '
        'earlier ones instead of merging into one list, so the '
        'repeats preserve the order in which the work happened, '
        'newest first.'),

    ...sec('how the version numbers came about'),
    ...text('There are no git tags in the repository, on the remote '
        'either, and no compare links in the file. The versions '
        'exist only as headings, and the history of the headings '
        'is itself informative.'),
    ...bullet('0.1.0',
        'the initial commit, 2026-08-17. The CHANGELOG did not '
        'exist then; it was created under two hours later in 3dacffb '
        'with an [Unreleased] section on top of a 0.1.0 section '
        'that described the first push after the fact.'),
    ...bullet('0.2.0',
        'a label put on yesterday’s work. When 77d80a2 added the '
        'nvim-lightbulb entry on 2026-08-18 at 12:57, it inserted '
        'a “## [0.2.0]” line below the new text, which turned the '
        '3dacffb entry (auto-save, clippy, inlay hints, the '
        'mason-lspconfig fix) into a release and let the new text '
        'stay Unreleased.'),
    ...bullet('Unreleased, Windows lineage',
        'the pile that grew for the rest of 2026-08-18 and was '
        'never numbered. When the rewrite to LazyVim happened, '
        'the commit eabb22a wrote 1.0.0 above it and renamed its '
        'heading to “Unreleased — Windows lineage, superseded by '
        '1.0.0 on this branch”.'),
    ...bullet('1.0.0 to 1.4.1',
        'one new heading per behaviour-changing commit: 1.0.0 '
        '(eabb22a), 1.1.0 (3ec11c4), 1.2.0 (07993a4), 1.3.0 '
        '(f35b4f6), 1.4.0 (0715b98), 1.4.1 (6aeebfd). The docs '
        'fix 77149b8 three minutes after 1.4.1 added a Docs '
        'section to 1.4.1 and did not create 1.4.2.'),
    ...text('The numbers therefore track working sessions more than '
        'semantic versioning: 1.4.0 is mostly bug fixes yet bumps '
        'the minor number, and 1.1.0 and 1.2.0 are about half an hour '
        'apart. That is a reading of the headings, not a claim '
        'the file makes. For a personal configuration with no '
        'consumers, a number is a bookmark for “this state was '
        'checked”, and that is how it is used here.'),

    ...sec('1.0.0, 2026-09-02: a lineage switch, not an edit'),
    ...code('md', 'CHANGELOG.md · 1.0.0, Changed (trimmed)', r'''
- **Migrated the whole config from the from-scratch Windows setup to a
  LazyVim-based config on Linux (Omarchy/Arch).** This is a platform lineage
  switch, not an incremental edit — the previous tree (everything under
  `lua/config/plugins/`, the nvim-cmp/mason wiring in `lsp.lua`, and the
  Windows-specific `bootstrap-device.ps1`) is replaced by the LazyVim starter
  (v8) layout with custom specs under `lua/plugins/`. The old Windows config
  remains untouched on the `master` branch.'''),
    ...text('The commit behind it, eabb22a, touches 40 files with '
        '1,147 insertions and 1,273 deletions: more lines removed '
        'than added. The entry is careful about what survived '
        'unchanged. 99 keeps the same provider, model, effort '
        'flag and five keymaps; only its source changes, from a '
        'local clone to the GitHub repository, and the keymaps '
        'gain which-key descriptions. auto-save.lua and harpoon '
        'were carried over. Everything LazyVim already ships '
        '(telescope, treesitter, conform, autopairs, toggleterm, '
        'lualine) was deleted from the config instead of being '
        'migrated, and the “Removed” list says so by name, along '
        'with the PowerShell and Flutter wiring: “this machine’s '
        'config is currently scoped to Rust.”'),
    ...text('The same entry lists what is new: the Omarchy desktop '
        'integration files (theme hot-reload, the 20 pre-loaded '
        'themes, transparency, a remote-aware clipboard) and two '
        'tiny LazyVim tweaks. The commit message repeats a detail '
        'that has since gone stale: that the old config “stays on '
        'master”. See the section on disagreements below.'),

    ...sec('1.1.0 and 1.2.0, 2026-09-03: the morning after'),
    ...text('1.1.0 (3ec11c4, 07:05) is the entry that introduces '
        'bacon-ls. Its design decision is recorded as a '
        'constraint: updateOnInsert must live in init_options, '
        'not only in settings, because the server needs it at '
        'initialize time to advertise Full didChange sync. '
        'Verification is headless and end to end: a clippy-only '
        'lint (needless_return) published on open, and a type '
        'error typed into a modified, unsaved buffer surfacing '
        'as “mismatched types” with zero saves.'),
    ...text('Two parts of the entry age interestingly. It records '
        'that Mason’s bacon package failed to produce a binary, '
        'so bacon 3.25 came from pacman while bacon-ls 0.29.0 '
        'came from Mason; by 1.4.1 neither is true, because the '
        'server is a local build and the bacon binary is not '
        'needed at all. And it says the didSave proxy in '
        'auto-save.lua is “no longer load-bearing for '
        'diagnostics (bacon-ls listens to didChange, not '
        'didSave)”. The comment now in auto-save.lua says the '
        'opposite about the same server: bacon-ls relies on '
        'didSave to restore its shadow-workspace hardlinks, and '
        '1.4.0’s second patch is about how it handles didSave. '
        'Understanding of the server improved between entries, '
        'and the changelog shows the earlier belief instead of '
        'editing it away.'),
    ...text('1.2.0 (07993a4, 07:37) is the 99 entry quoted above, '
        'plus a rewrite of the README to describe this config '
        'instead of the LazyVim starter text, and blink '
        'completion for the prompt buffer via saghen/blink.compat.'),

    ...sec('1.3.0, 2026-09-03: two pipelines, one bug'),
    ...text('This is the entry the rest of the project hangs on. '
        'It is also the one with the most numbers.'),
    ...code('md', 'CHANGELOG.md · 1.3.0, the first Fixed bullet (trimmed)', r'''
- **Slow, churning diagnostics ("checking (0%)" rows stacked for minutes).**
  Root cause: two clippy pipelines — `checkOnSave` runs (triggered by the ~1s
  auto-save) racing `updateOnInsert` shadow runs — cancelling each other and
  serializing on cargo's build-dir file lock, with `--all-targets` doubling
  every run's scope. Fixed: `checkOnSave = false` (single pipeline),
  `--all-targets` dropped, debounce 500→800ms. Measured 5.6s → 0.8–0.9s
  edit-to-diagnostic on a warmed project. A/B testing also proved
  `updateOnInsert` must stay on: without it bacon-ls advertises no document
  sync (Neovim ignores its late dynamic registration) and diagnostics never
  refresh at all.'''),
    ...text('Three separate findings are packed into that bullet. '
        'The first is a diagnosis: the slowness had two causes at '
        'once, a second trigger and a doubled workload, and '
        'removing either alone would have looked like progress. '
        'The second is a number: 5.6 s to 0.8–0.9 s, roughly six '
        'times. The third is a negative result that protects the '
        'fix: turning updateOnInsert off, the obvious way to '
        'remove a pipeline, breaks the server entirely, which is '
        'why the comment in bacon-ls.lua says it “MUST be set '
        'in init_options” and “must stay ON”, and records the '
        'worst case it observed: “marker diagnostic never arrived '
        'in 300s”.'),
    ...text('A note on the “500→800ms”. The first version of '
        'lua/plugins/bacon-ls.lua (3ec11c4) sets no debounce at '
        'all, so the 500 is presumably the server’s own default. '
        'That is an inference from the file; the entry does not '
        'say. What is certain is that 1.4.0 moves the setting '
        'back to 500 explicitly, for a reason the changelog '
        'gives: the 800 had been compensating for a bug.'),
    ...text('The rest of 1.3.0 is a list of things found by '
        'looking at what the editor does in the background:'),
    ...bullet('the vim.cmd monkey-patch is gone',
        'auto-save’s didSave workaround matched the plugin’s '
        'internal command string, so an upstream rename would '
        'have broken it silently, and it added a metatable '
        'indirection to every vim.cmd call in the session. It '
        'was replaced by the plugin’s own User AutoSaveWritePost '
        'event. The verification line is specific: didSave still '
        'reaches both LSP clients and BufWritePre is still '
        'suppressed.'),
    ...bullet('transparency survives :colorscheme',
        'the highlight overrides were applied only at startup; '
        'they are now re-applied on every ColorScheme event in a '
        'cleared augroup.'),
    ...bullet('startup 28.7 ms to about 18 ms, and no background work',
        'a harpoon keys function was force-loading the plugin '
        'and plenary on every start; 99, telescope and '
        'blink.compat now load on their keymaps; the update '
        'checker (commented in lua/config/lazy.lua as “~6-10ms”) '
        'and four remote-plugin providers are off. The entry '
        'does not say how startup was timed, so treat the two '
        'figures as one machine’s before and after. The README '
        'page walks through the items.'),
    ...bullet('an `== 1` that was missing',
        'the theme hot-reload tested vim.fn.exists("syntax_on") '
        'as if it were a boolean. In Lua, 0 is truthy, so the '
        'branch always ran. A one-line bug in a language where '
        'zero is true, now compared explicitly:'),
    ...code('lua', 'lua/plugins/omarchy-theme-hotreload.lua · the fixed test', r'''
-- vim.fn.exists returns 0/1, and 0 is truthy in Lua -
-- must compare, or this branch always runs
if vim.fn.exists("syntax_on") == 1 then
  vim.cmd("syntax reset")
end'''),
    ...text('The same entry also adds the pieces that make the two '
        'diagnostic tiers possible and records their evidence: '
        'rust-analyzer’s native diagnostics re-enabled alongside '
        'clippy (“measured 155–235ms warm (real keystrokes, '
        'clean-state probes)”), cargo.targetDir = true so '
        'rust-analyzer’s build-script runs stop contending with '
        'terminal cargo commands for the build-directory lock, '
        'and clippy --no-deps. Outside the repository it '
        'documents ~/.cargo/config.toml: the mold linker via '
        'clang (linking verified through readelf) and '
        'profile.dev.debug set to line-tables-only, with the '
        'caveat that existing projects rebuild once after the '
        'debuginfo change.'),

    ...sec('1.4.0, 2026-09-04: the bug that was upstream'),
    ...text('About five and a half hours after 1.3.0 (f35b4f6 at '
        '19:54, 0715b98 at 01:18) the work reaches a different '
        'kind of problem: even with one pipeline, bacon_ls could '
        'stay stuck on “checking…” with stale diagnostics. The '
        'root cause was not in this repository.'),
    ...code('md', 'CHANGELOG.md · 1.4.0, the first Fixed bullet (trimmed)', r'''
- **bacon_ls stuck on "checking…" with stale diagnostics — root-caused to an
  upstream bacon-ls 0.29.0 bug and fixed in a locally patched build**
  ...
  its debounce task even after the sleep has elapsed — at that point the task
  IS the in-flight cargo run, so any keystroke or auto-save `didSave` killed
  the run silently: progress tokens leaked (begin, never end → the immortal
  stacked "checking" rows), the cargo child died mid-check, and the last run
  of every typing burst was murdered ~200ms in by auto-save (debounce 1000ms
  vs run start at 800ms) leaving diagnostics stale.'''),
    ...text('The mechanism rewards slow reading. A debounce task '
        'sleeps, then does its work. Cancelling it during the '
        'sleep is correct. Cancelling it after the sleep is not '
        'a cancel of the timer but a cancel of the work, because '
        'the work runs inside the same task. Once the cargo '
        'child dies mid-check, the LSP progress token that began '
        'with “begin” never receives its “end”, so the '
        'client shows it forever. The arithmetic in the '
        'parenthesis explains why it happened every time: '
        'auto-save fires 1000 ms after the last keystroke, the '
        'run started 800 ms after it, and the save’s didSave '
        'therefore landed 200 ms into the run, in the final run '
        'of every burst. With the abort bug fixed the 800 ms is '
        'no longer needed; the entry says it was “compensating '
        'for” the bug without spelling out how. At 500 ms the '
        'same save lands 500 ms into the run instead of 200 ms. '
        'That arithmetic is mine, not the entry’s, and once runs '
        'can no longer be killed the exact timing stops '
        'mattering.'),
    ...text('The entry lists three patches. Patch 1 makes a started '
        'run un-abortable and routes superseded runs through '
        'CancelRunning, which closes tokens properly. Patch 2 '
        'fixes a save inside the debounce window skipping the '
        'check altogether when checkOnSave is off: only cancel '
        'the pending live trigger if a save-run will replace '
        'it. Patch 3 handles closing a dirty buffer. Orphaned '
        'diagnostics stayed behind (and the entry says they '
        'could even crash Neovim 0.12’s underline handler on '
        'reopen via out-of-range lines), and cargo replayed '
        'stale warnings because the hardlink restore moved the '
        'shadow file’s mtime backwards, so cargo judged the '
        'crate fresh. The fix restores by copy so the mtime is '
        'new and a real re-check happens.'),
    ...text('The measurement that retires the old setting is in the '
        'same entry:'),
    ...code('md', 'CHANGELOG.md · 1.4.0, Changed', r'''
- `updateOnInsertDebounceMillis` 800 → **500**. Measured on a warm 3-crate
  workspace: edit-to-clippy-diagnostic = debounce + ~60ms, and 500ms coalesces
  an 18-keystroke burst into exactly 1 cargo spawn, same as 800 (300ms spawned
  18 — churn). The 800ms choice was compensating for the now-fixed abort bug.
  Median edit→diagnostic: 0.56s warm.'''),
    ...text('This is a small experiment written as a paragraph: '
        'a model (latency is debounce plus about 60 ms), a '
        'workload (one 18-keystroke burst), three settings, and '
        'a count of cargo spawns for each. 300 ms is rejected '
        'because it spawned 18 runs; 500 and 800 both spawned '
        'one, so the smaller wins. The last sentence closes the '
        'loop on the earlier change.'),
    ...text('The verification block is the most detailed one in '
        'the file, and it is worth quoting because of its range:'),
    ...code('md', 'CHANGELOG.md · 1.4.0, Verified (trimmed)', r'''
- 35-check headless E2E suite (`~/.bacon-e2e/`: harness + tiny-crate,
  3-crate-workspace, and randomized 120-op soak batteries): lint/syntax/type
  errors appear and clear unsaved; cfg(test) exclusion documented; cross-crate
  errors propagate (1.0s) and clear; serde derive + macro-expansion errors map
  to the right file; Cargo.toml dep edits flow through the shadow; dirty
  close/reopen cycles; cancellation storms and hostile didSave timings — zero
  leaked progress tokens everywhere, bacon-ls RSS 9.5MB after 120-op soak, no
  stray cargo processes.'''),
    ...text('Functional cases (errors appear and clear), edge cases '
        '(macros, derive, Cargo.toml edits), the very bug being '
        'fixed (cancellation storms, hostile save timings), and '
        'the resource cost of the fix (RSS after a soak, stray '
        'processes). The suite lives outside the repository, in '
        'the author’s home directory, so only its description is '
        'reviewable here. The entry ends with an integration '
        'check on the real LazyVim config with the real '
        'auto-save: 0.71 s for the clippy tier and 0.68 s for the '
        '“error tier”. That second number sits awkwardly beside '
        '1.3.0’s 155–235 ms for native diagnostics, and the '
        'entry does not say whether it is the same probe. It is '
        'left unreconciled here, too.'),

    ...sec('1.4.1, 2026-09-04: making the fix mergeable'),
    ...code('md', 'CHANGELOG.md · 1.4.1, Changed (trimmed)', r'''
- The three bacon-ls fixes were **upstreamed as
  [crisidev/bacon-ls#139](https://github.com/crisidev/bacon-ls/pull/139)**.
  The local binary now builds from upstream 0.30.0 + that branch
  (`~/.local/src/bacon-ls-upstream`) instead of the 0.29.0 fork. The
  run-abort fix was reworked to add no struct field (the debounce task drops
  its own handle after its sleep rather than tracking a generation counter),
  keeping the `BackendRuntime` `large_enum_variant` size lint quiet — upstream
  CI runs `cargo clippy --all-targets`.'''),
    ...text('This is the point where a private patch becomes a '
        'contribution, and the entry shows what that costs. The '
        'generation counter that 1.4.0 used needed a new field '
        'on a struct, and the entry’s reason for redoing it is '
        'that a field would set off the large_enum_variant size '
        'lint on BackendRuntime, which upstream CI enforces. So '
        'the fix was redone: '
        'the debounce task forgets its own handle once the '
        'sleep is over, which makes a later abort() able to '
        'cancel only a task that is still sleeping. Behaviour is '
        'identical, the 35-check suite passes against the '
        'field-free build, and upstream’s 124 tests pass '
        '(including a new restore_copy test). The instruction '
        'for the future is stated in the entry and repeated in '
        'the Lua: drop the cmd override once #139 merges. Three '
        'minutes later 77149b8 corrects the README: bacon-ls '
        'comes from the local build, and the bacon binary is '
        'not needed by the cargo backend.'),

    ...sec('a bug that took four commits in an afternoon'),
    ...text('The densest stretch of the history is 2026-08-18, '
        'between 14:17 and 15:21, in the Windows lineage. Four '
        'commits, one chain of causes. Each entry in the file '
        'explains why the previous fix had not been enough.'),
    ...bullet('9a170c2, 14:17',
        'two findings. The inline error text was invisible: '
        'rose-pine’s own DiagnosticVirtualText groups set '
        'foreground equal to background (with a blend), and the extmark was '
        'confirmed drawn through nvim_buf_get_extmarks, so the '
        'text was there but the same colour as its background. '
        'And diagnostics seemed to need :w, when really '
        'update_in_insert defaults to false, so they only '
        'redrew on InsertLeave, and Esc always precedes :w.'),
    ...bullet('3ab52cd, 14:38',
        'diagnostics still did not refresh without a save. Root '
        'cause, with evidence: noautocmd = true on the '
        'autosave, added so autosaves would not format, '
        'suppresses all autocmds, including the LSP client’s '
        'BufWritePost-triggered didSave. Confirmed directly: a '
        'noautocmd write sends zero LSP notifications; a normal '
        'write sends didSave. The fix wrapped vim.cmd.'),
    ...bullet('6d1e9c9, 14:45',
        'still needed to leave insert mode. TextChanged only '
        'fires for edits outside insert mode; its insert-mode '
        'sibling TextChangedI was missing. Verified with '
        'InsertLeave never firing at all: the diagnostic '
        'appeared in about 1.5 s. The entry notes that the '
        'debounce cancels and reschedules on every trigger, so '
        'there is no save flood while typing, which it says was '
        '“confirmed by reading auto-save.nvim’s own source”.'),
    ...bullet('df3c5ae, 15:21',
        'the fix from 3ab52cd broke lazy.nvim. Replacing vim.cmd '
        'with a plain function removed its dot-call forms, so '
        'vim.cmd.helptags(...) threw “attempt to index field '
        '‘cmd’ (a function value)”, which surfaced in a live '
        'session in lazy’s own help-update routine. vim.cmd is a '
        'callable table, and a function has no fields. The '
        'repair is a proper setmetatable proxy that forwards '
        'indexing to the original and intercepts only the string '
        'call.'),
    ...text('The story has an epilogue sixteen days later. The '
        'metatable proxy was still a monkey-patch, and 1.3.0 '
        'removed it for the plugin’s supported event. The '
        'earlier entries were not rewritten when that happened; '
        'both are in the file. Read in order, they show a fix '
        'being refined three times: found by experiment, '
        'repaired after it broke something else, and finally '
        'replaced by an interface the plugin promises to keep.'),
    ...code('lua', 'lua/plugins/auto-save.lua · where the story ended up', r'''
    -- auto-save.nvim fires its own `User AutoSaveWritePost` autocmd AFTER
    -- the (noautocmd) write completes, with the buffer in data.saved_buffer
    -- - a supported hook, so send didSave from there. (This replaced an
    -- earlier vim.cmd proxy that pattern-matched the plugin's internal
    -- command string; the User event survives plugin refactors, the string
    -- match didn't.)'''),

    ...sec('the Windows lineage block'),
    ...text('A reader opening the file at line 246 meets 185 lines '
        'about a configuration that no longer exists on main: '
        'nvim-cmp, mason-lspconfig, flutter-tools, a PowerShell '
        'bootstrap script. They are kept, and the 1.0.0 entry '
        'points back to them. The branch windows-legacy holds '
        'that code (its tip, 9fff81e, is the last commit before '
        'the migration). The block records five pieces of work '
        'on 2026-08-18, each with its own piece of reasoning:'),
    ...bullet('lualine (28fab99, 15:38)',
        'the “stuck” mode indicator that was being read was '
        'Neovim’s own showmode echo, which is uncoloured and only '
        'redraws on certain events. A statusline plugin with '
        'theme auto and globalstatus replaced it, verified by '
        'checking that the per-mode highlight groups resolve to '
        'different backgrounds and that the rendered statusline '
        'switches from NORMAL to VISUAL.'),
    ...bullet('islands-dark (99bdcbc, 15:55)',
        'a colorscheme ported from RustRover. The entry checks '
        'the claim behind the name: JetBrains’ Islands is a UI '
        'chrome redesign, not a palette, confirmed from its own '
        'announcement, and the editor colours are still '
        'Darcula-derived. Rather than guess hex values the '
        'author exported the scheme as .icls and read the real '
        'values (background #191a1c, foreground #bcbec4, '
        'keywords #cf8e6d, and so on), then confirmed Normal '
        'resolves to them byte for byte.'),
    ...bullet('OneDrive sync (da7b95d, 16:03)',
        'the repo moved to a synced folder and a directory '
        'junction took its place, chosen over symlinks because '
        'junctions need no admin rights. Move-Item failed first, '
        'and the cause is a good fact: Windows locks a directory '
        'while any process’s working directory points into it, '
        'and two live nvim processes plus the shell session doing '
        'the move were doing that.'),
    ...bullet('bootstrap-device.ps1 (e9bb0af, 16:16)',
        'a one-shot bootstrap for a clean machine. Every step is '
        'idempotent, two steps are deliberately manual because '
        'they are credential flows (the OneDrive sign-in and '
        'claude auth login), and the testing is described with '
        'unusual care: parsed with the PowerShell parser before '
        'running, run end to end on the real machine where every '
        'step took its skip path, and the overwrite-confirmation '
        'logic tested only against throwaway fake paths, with '
        'the note that it was not exercised on the real config '
        '“to avoid any risk to it”.'),
    ...bullet('nvim-lightbulb and ESLint (77d80a2, 12:57)',
        'the lightbulb sign was verified against a real ESLint '
        'install and flat config in a test project, and the '
        'discovery that the ESLint language server does nothing '
        'without a project-local ESLint is the “Verified (no '
        'code change)” entry.'),

    ...sec('what “verified” means in this file'),
    ...text('Reading all the entries together, the evidence comes in '
        'recognisable kinds, roughly from strongest to weakest.'),
    ...bullet('an end-to-end run of the real thing',
        'a real visual-mode request to 99 in two launch '
        'directories; a real ESLint violation through the LSP; '
        'a real clippy lint and a real unsaved type error '
        'through bacon-ls.'),
    ...bullet('a measurement with a stated condition',
        '“warm”, “3-crate workspace”, “18-keystroke burst”, '
        '“median”. The conditions are what make the numbers '
        'usable.'),
    ...bullet('an instrumented probe',
        'counting notifications on the client, listing '
        'extmarks, evaluating the statusline, reading hex '
        'values from highlight groups, checking linkage with '
        'readelf.'),
    ...bullet('the dependency’s source',
        'the changelog twice notes that a claim comes from '
        'reading the plugin: mason-lspconfig’s handlers option '
        'no longer exists (0.2.0, which means the custom '
        'rust-analyzer handlers “were silently never called”), '
        'and auto-save.nvim’s debounce semantics.'),
    ...bullet('mechanism and documentation, flagged as such',
        'for update_in_insert the entry says it is “verified by '
        'mechanism/docs rather than a headless repro”.'),
    ...text('That last category is the honest one. Twice the file '
        'states what headless automation cannot do. For '
        'lualine: startinsert does not perform a real mode '
        'transition without an attached UI (vim.fn.mode() stays '
        '“n”), so insert-mode text could not be checked the same '
        'way, although the mechanism is identical for all '
        'modes. For update_in_insert: the live-while-typing '
        'behaviour could not be reproduced headlessly. A '
        'changelog that says what it did not prove is more '
        'believable about what it did.'),
    ...code('md', 'CHANGELOG.md · Windows lineage, the lualine caveat (trimmed)', r'''
  actual mode change (`normal! v`) evaluated via `nvim_eval_statusline`. Insert-mode text
  couldn't be verified the same way — `startinsert` doesn't perform a real mode transition
  in headless Neovim without an attached UI (confirmed separately: `vim.fn.mode()` stays
  `"n"` after it), the same category of headless-simulation limitation noted elsewhere in
  this log — but the underlying mechanism (lualine's `mode` component reads
  `vim.fn.mode()` on every redraw) is identical for all modes, so this isn't a gap in the
  fix, just in what headless automation can simulate.'''),


    ...sec('where the file and the repository disagree'),
    ...text('The changelog is history, so the older entries are '
        'allowed to describe things that no longer exist. A few '
        'places go further than history and are simply stale or '
        'inconsistent.'),
    ...bullet('the old branch is called master here',
        'the 1.0.0 entry and the eabb22a commit message say the '
        'old Windows config stays on master. The README links '
        'the windows-legacy branch, and the remote lists exactly '
        'two branches, main and windows-legacy, with '
        'windows-legacy at 9fff81e. Nothing in the clone shows '
        'when or why the branch got its new name.'),
    ...bullet('1.0.0 describes rustaceanvim.lua as it was',
        'clippy as the on-save check command and push '
        'diagnostics with style lints. Today’s file has neither: '
        '1.1.0 removed both blocks, and 1.3.0 re-enabled '
        'diagnostics without the style lints. Anyone checking '
        '1.0.0 against HEAD will find it wrong, because the '
        'entries are meant to be read forward.'),
    ...bullet('didSave', 'see the 1.1.0 section above.'),
    ...bullet('the patched build’s location',
        '1.4.0 gives ~/.local/src/bacon-ls-0.29.0-patched; '
        '1.4.1 and the Lua give ~/.local/src/bacon-ls-upstream.'),
    ...bullet('two latency numbers',
        '1.3.0’s 155–235 ms and 1.4.0’s “error tier 0.68s”, as '
        'discussed above.'),

    ...sec('limits of the record'),
    ...bullet('evidence lives outside the repo',
        'the 35-check suite (~/.bacon-e2e/), the patched source '
        '(~/.local/src/bacon-ls-upstream), the cargo config and '
        'bacon prefs are all in the author’s home directory. The '
        'entries describe them; the repository cannot reproduce '
        'them.'),
    ...bullet('one machine',
        'every figure comes from the author’s one Linux machine. '
        'None is a benchmark run with repeated trials, and none '
        'comes with variance.'),
    ...bullet('no hashes, no dates finer than a day',
        'the file does not cite commits, and its dates are '
        'calendar days. The mapping to commits in this page was '
        'recovered from git log and the diffs of CHANGELOG.md.'),
    ...bullet('a few headings carry no date',
        '0.1.0 and 0.2.0, and the Unreleased Windows block.'),
    ...bullet('it records, it does not test',
        'the repository contains no test directory or CI '
        'configuration. The changelog’s verification claims '
        'cannot be re-run from a clone.'),

    ...sec('what to take from it'),
    ...bullet('write the symptom, the cause, the change, the check',
        'in that order. The cause is what the next person '
        'needs, and the check is what makes the entry believable.'),
    ...bullet('record the dead ends',
        'the ./tmp attempt in 1.2.0, the 800 ms debounce in '
        '1.4.0, the vim.cmd proxy in df3c5ae. They are cheap to '
        'write and they stop someone repeating them.'),
    ...bullet('state the limits of your own testing',
        'headless Neovim cannot enter insert mode; the entry '
        'says so, and says why that is not a hole in the fix.'),
    ...bullet('put the version bump in the commit',
        '17 of 20 commits carry their own explanation, which is '
        'why the history can be reconstructed from the file '
        'afterwards.'),
    blank,
    link('→ github.com/XNash/xynovim', 'https://github.com/XNash/xynovim'),
  ],
);
