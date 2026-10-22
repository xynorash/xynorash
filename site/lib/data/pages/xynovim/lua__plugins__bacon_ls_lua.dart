import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/lua/plugins/bacon-ls.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', 'bacon-ls.lua — clippy while you type, not after you save'),
    cm('--', 'one pipeline, a measured debounce, a patched server that is now upstream'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv('role', 'configures the bacon-ls language server: clippy diagnostics for unsaved buffers'),
    kv('language', 'Lua (a lazy.nvim spec that overrides nvim-lspconfig options)'),
    kv('size', '119 lines (63 until 2026-10-09)'),
    kv('history', '17 commits; 4 in the first 24 hours (2026-09-03 07:05 to 2026-09-04 07:25), the rest through 2026-10-22'),
    kv('upstream', 'crisidev/bacon-ls pull request 139, filed from this work'),
    kv('measured', '5.6 s to 0.8-0.9 s edit-to-diagnostic, then 0.56 s median, warm'),
    ...sec('why this file exists'),
    ...para('--',
        r'In Rust there are two kinds of feedback. rust-analyzer can say '
        r'“this does not type-check” from memory, almost at once. Clippy '
        r'says “this is not good Rust”, and it can only say it by running '
        r'cargo. The CHANGELOG entry that introduced this file (1.1.0, '
        r'2026-09-03) names the goal as “the always-on '
        r'inspections known from the JetBrains IDEs”: feedback while typing, with no save in between. '
        r'This file is how that goal is met on the clippy side, and the '
        r'rest of this page is the story of making it actually fast.'),
    blank,
    ...para('--',
        r'The file does not start a server or install anything. It '
        r'supplies options to one entry, servers.bacon_ls, in '
        r'nvim-lspconfig’s opts, the way LazyVim expects overrides to '
        r'be written. The header comment used to call the older backend a fallback configured in ~/.config/bacon/prefs.toml; it now says that backend is not configured or used. The role itself is handed over in '
        r'lua/config/options.lua, which sets '
        r'vim.g.lazyvim_rust_diagnostics = "bacon-ls". Per the comment '
        r'next to that line, the lang.rust extra reads it and disables '
        r'rust-analyzer’s own checkOnSave and diagnostics so nothing is '
        r'reported twice. '
        r'The other half of the design lives in rustaceanvim.lua, which '
        r'turns rust-analyzer’s cheap in-memory diagnostics back on as an '
        r'instant first tier.'),

    ...sec('what bacon-ls does with an unsaved buffer'),
    ...para('--',
        r'The header comment is the best description of the mechanism, '
        r'and it is worth reading as the specification of this file. The '
        r'first half says which of the two backends is in use. The second '
        r'half is the trick that makes unsaved buffers checkable at all.'),
    ...code('lua', 'lua/plugins/bacon-ls.lua · lines 1-14', r'''
-- bacon-ls 0.29+ has a native "cargo" backend that runs clippy itself and
-- pushes diagnostics - no bacon process or .bacon-locations export needed
-- (the older "bacon" backend would need the `bacon` binary and its own
-- prefs; it is not configured or used here).
--
-- updateOnInsert is the always-on part: bacon-ls mirrors the workspace
-- into a hardlinked shadow under target/bacon-ls-live/, writes dirty buffers
-- into it on every didChange, and runs clippy against the shadow - so
-- diagnostics update as you type, before any save. It MUST be set in
-- init_options (not settings): the server needs it at initialize-time to
-- advertise Full didChange sync - and it must stay ON: without it the server
-- advertises no static sync at all and Neovim ignores its late dynamic
-- registration, so saves/changes never reach it and diagnostics never
-- refresh (measured: marker diagnostic never arrived in 300s).'''),
    ...para('--',
        r'The problem the shadow solves: cargo reads files from disk, and '
        r'a buffer you are still editing is not on disk. So the server '
        r'keeps a second copy of the workspace under '
        r'target/bacon-ls-live/, built from hardlinks. On every '
        r'didChange it writes the dirty buffer into that shadow and runs '
        r'clippy against the shadow. The writes go to the shadow, not to '
        r'the real file, so cargo sees the code as it is in the editor '
        r'right now while the file on disk stays as last saved.'),
    blank,
    ...para('--',
        r'The older “bacon” backend is not in use. It needed a running '
        r'bacon process exporting a .bacon-locations file, and it only '
        r'reacted to saves. CHANGELOG 1.1.0 notes it was still set up '
        r'globally in ~/.config/bacon/prefs.toml (a [jobs.bacon-ls] '
        r'clippy job) as “a verified-working fallback”, and 1.4.1 '
        r'corrects the README: the cargo backend does not need the bacon '
        r'binary at all.'),

    ...sec('the settings object'),
    ...code('lua', 'lua/plugins/bacon-ls.lua · the shared settings table (trimmed)', r'''
local bacon_ls_settings = {
  backend = "cargo",
  cargo = {
    command = "clippy",
    -- no --all-targets: it doubles every run's scope (bin + test targets);
    -- clippy-on-tests can run manually/CI instead. --no-deps: don't re-lint
    -- dependency crates after their recompilation. --keep-going: a crate that fails to
    -- build no longer hides the diagnostics of the independent ones.
    extraArgs = { "--workspace", "--all-features", "--no-deps", "--keep-going" },
    updateOnInsert = true,
    ...
  },
}'''),
    ...para('--',
        r'Everything that matters is in one local table, and the '
        r'table is used twice. The spec at the bottom of the file passes '
        r'the same bacon_ls_settings variable as init_options and as '
        r'settings.bacon_ls. Because it is the same table, the two '
        r'cannot drift apart. That matters because the next section is '
        r'about a setting that has to reach the server by the right '
        r'route, and a copy of the table that disagreed with the other '
        r'would be hard to spot.'),
    blank,
    ...para('--',
        r'extraArgs is subtractive on purpose. The first version of the '
        r'file (commit 3ec11c4) ran clippy with --workspace '
        r'--all-targets --all-features. About thirteen hours later, in '
        r'f35b4f6, --all-targets is gone and --no-deps is in:'),
    ...pt('--', '--workspace',
        r'lint every member crate, not just the one the buffer belongs '
        r'to. The 1.4.0 verification includes a three-crate workspace '
        r'where an error in one crate must surface and clear across '
        r'crates (1.0 s).'),
    ...pt('--', '--all-features',
        r'kept from the first version so feature-gated code is checked '
        r'too.'),
    ...pt('--', '--no-deps',
        r'when a dependency is recompiled, do not re-lint it (the '
        r'comment in the file: “don’t re-lint dependency crates after '
        r'their recompilation”).'),
    ...pt('--', '--keep-going',
        r'added in 3f868dd (2026-10-13, “Final loop round 3”). The '
        r'comment gives the effect: a crate that fails to build no longer '
        r'hides the diagnostics of the independent ones in the workspace.'),
    ...pt('--', 'no --all-targets',
        r'the comment in the file says it doubles every run’s scope '
        r'(binary targets plus test targets). The cost is that test code '
        r'is not linted live; the same comment leaves that to a manual '
        r'run or CI. CHANGELOG 1.4.0 records that the cfg(test) '
        r'exclusion was checked and is documented.'),

    ...sec('the server needs to hear about updateOnInsert at the handshake'),
    ...para('--',
        r'Both the header comment and CHANGELOG 1.3.0 describe an '
        r'experiment rather than an assumption. The question was whether '
        r'updateOnInsert could be turned off to simplify things. A/B '
        r'testing answered it:'),
    ...pt('--', 'with updateOnInsert on',
        r'the server advertises Full didChange sync in its response to '
        r'initialize, so Neovim sends every edit.'),
    ...pt('--', 'with updateOnInsert off',
        r'the server advertises no static document sync at all. Per the '
        r'comment, Neovim ignores its late dynamic registration, so '
        r'saves and changes never reach the server and diagnostics '
        r'never refresh. The test used a marker diagnostic, and it '
        r'never arrived in 300 seconds.'),
    blank,
    ...para('--',
        r'That second case is the interesting one, because from the '
        r'user’s side it is silent: the diagnostics simply stop '
        r'refreshing, with no error to point at. It is also why the '
        r'option has to '
        r'be in init_options rather than only in settings: initialize is '
        r'the one moment where the server decides what to advertise, and '
        r'settings are only delivered afterwards, when the server pulls '
        r'them with workspace/configuration. The spec carries both, with '
        r'a comment saying which is which:'),
    ...code('lua', 'lua/plugins/bacon-ls.lua · the spec (trimmed)', r'''
return {
  "neovim/nvim-lspconfig",
  opts = {
    servers = {
      bacon_ls = {
        ...
        init_options = bacon_ls_settings,
        ...
        -- Also answered to the server's workspace/configuration pull.
        settings = { bacon_ls = bacon_ls_settings },
      },
    },
  },
}'''),

    ...sec('one pipeline, not two'),
    ...para('--',
        r'The first working configuration was miserable: diagnostics '
        r'took seconds, and “checking (0%)” progress rows stacked up '
        r'for minutes. Instead of tuning by feel, the 1.3.0 work looked '
        r'for the cause, and the CHANGELOG states it precisely. Two '
        r'clippy pipelines were running:'),
    ...pt('--', 'pipeline A',
        r'checkOnSave runs. Auto-save writes the file about a second '
        r'after typing stops (see auto-save.lua), and that save '
        r'triggered a run.'),
    ...pt('--', 'pipeline B',
        r'updateOnInsert shadow runs, started by edits.'),
    blank,
    ...para('--',
        r'They cancelled each other, and because both ultimately invoke '
        r'cargo, they serialised on cargo’s build-directory file lock. '
        r'On top of that, --all-targets doubled the scope of every run. '
        r'The fix was to delete a pipeline:'),
    ...code('lua', 'lua/plugins/bacon-ls.lua · checkOnSave', r'''
    -- OFF deliberately: with ~1s auto-save, checkOnSave is a second run
    -- pipeline racing the updateOnInsert one - runs cancel each other and
    -- serialize on cargo's build-dir lock, stacking "checking (0%)" progress
    -- rows for ages. Single pipeline measured 0.8-0.9s edit-to-diagnostic
    -- vs 5.6s with both pipelines on.
    checkOnSave = false,'''),
    ...para('--',
        r'The number to remember is 5.6 s against 0.8-0.9 s, measured '
        r'edit-to-diagnostic on a warmed project, with the same code and '
        r'the same machine. The commit message for f35b4f6 (2026-09-03, '
        r'19:54) gives the whole change as “checkOnSave off, no '
        r'--all-targets, 800ms debounce”. A pipeline is not free just '
        r'because it is idle most of the time: the cost showed up '
        r'when the two collided, which was every typing burst followed '
        r'by an auto-save.'),

    ...sec('the debounce: 500, then 800, then 500'),
    ...para('--',
        r'updateOnInsertDebounceMillis is how long the server waits '
        r'after the last edit before spawning cargo. The value has a '
        r'three-step history that is a small lesson in itself:'),
    blank,
    cm('--', '  when              value  why'),
    cm('--', '  ----------------  -----  --------------------------------'),
    cm('--', '  start             500    the plugin’s own default (named in'),
    cm('--', '                           the f35b4f6 comment)'),
    cm('--', '  09-03 19:54       800    chosen for churn: “roughly halves the'),
    cm('--', '                           spawn/cancel churn”, +0.3 s latency'),
    cm('--', '  09-04 01:18       500    measured: same coalescing, faster'),
    blank,
    ...code('lua', 'lua/plugins/bacon-ls.lua · the debounce comment', r'''
    -- Measured (multi-crate ws, warm): edit-to-clippy-diagnostic is
    -- debounce + ~60ms, and any debounce >= the typing cadence coalesces a
    -- burst into exactly 1 cargo spawn (500 and 800 both spawned 1 for an
    -- 18-keystroke burst; 300 spawned 18). 500ms is the sweet spot: 0.56s
    -- median latency, no extra churn. The old 800ms was compensating for
    -- the abort bug fixed upstream in 0.31.0.
    updateOnInsertDebounceMillis = 500,'''),
    ...para('--',
        r'Read the measurements as a model. Latency is the debounce plus '
        r'about 60 ms of clippy on a warm three-crate workspace, so '
        r'800 ms gives roughly 0.86 s (the 0.8-0.9 s from the previous '
        r'section) and 500 ms gives roughly 0.56 s (the reported '
        r'median). The churn side is a counting experiment: an '
        r'18-keystroke burst produced 18 cargo spawns at 300 ms and '
        r'exactly 1 at 500 ms and at 800 ms. Since a 300 ms debounce '
        r'spawned on every keystroke and 500 ms did not, the '
        r'typing in the test must have had gaps between those two '
        r'values; that is an inference from the result, not something '
        r'the notes spell out.'),
    blank,
    ...para('--',
        r'The last sentence of the comment is the real finding. 800 ms '
        r'had looked like a win for less churn, but the comment says it '
        r'was compensating for the upstream abort bug (next section). '
        r'A plausible mechanism is that fewer spawns meant fewer '
        r'runs exposed to being killed. Once runs could no longer be '
        r'killed by a keystroke, the compensation was just 300 ms of '
        r'extra latency. The value returned to the plugin’s default, '
        r'but now with evidence behind it, which is why the line stays '
        r'explicit in the file.'),

    ...sec('when the tool is the bug'),
    ...para('--',
        r'With one pipeline and a sane debounce, one symptom remained: '
        r'sometimes the “checking…” row never went away and the '
        r'diagnostics were stale. CHANGELOG 1.4.0 traces the cause to '
        r'upstream bacon-ls 0.29.0 and explains it step by step. '
        r'Upstream keeps a debounce task. The task sleeps for the '
        r'debounce period, and when it wakes up it runs cargo inside '
        r'that same task. On every new edit or save notification, '
        r'upstream calls abort() on the previous task, whether or not '
        r'its sleep is over. If the sleep is over, the task is no longer '
        r'waiting. It is the in-flight clippy run, and abort() kills '
        r'it.'),
    blank,
    cm('--', '  The arithmetic of the bug, with 800 ms debounce and ~1 s auto-save:'),
    blank,
    cm('--', '  last keystroke        run starts            auto-save writes'),
    cm('--', '  t0 ------------------ t0 + 800 ms --------- t0 + 1000 ms'),
    cm('--', '       debounce sleep        |<-- clippy running -->|'),
    cm('--', '                             this task is the run   |'),
    cm('--', '                                        didSave -> abort()'),
    cm('--', '                             run killed 200 ms in, token never ends'),
    blank,
    ...para('--',
        r'The CHANGELOG’s phrasing is “the last run of every typing '
        r'burst was murdered ~200ms in by auto-save (debounce 1000ms vs '
        r'run start at 800ms)”. That is why the bug was so '
        r'reproducible in practice: the setup of an '
        r'auto-save debounce of 1000 ms and a bacon-ls debounce of '
        r'800 ms, was an almost perfect machine for hitting the race '
        r'once per burst. The consequences were three things at once:'),
    ...pt('--', 'leaked progress tokens',
        r'the run had sent an LSP progress “begin” and died before the '
        r'“end”, so the editor showed an immortal “checking…” row, one '
        r'more stacked on top of the last for every killed run.'),
    ...pt('--', 'a dead cargo child',
        r'the cargo child died mid-check (the changelog’s words), so '
        r'that run could not publish its results.'),
    ...pt('--', 'stale diagnostics',
        r'the final run of a burst is the one that matters, and it was '
        r'the one that was killed.'),

    ...sec('three fixes on one branch'),
    ...para('--',
        r'The fix was made in a local build of bacon-ls first, and then '
        r'reshaped so it could be sent upstream. The 1.4.0 '
        r'entry lists three patches; the comment in the spec summarises '
        r'them in one sentence each.'),
    blank,
    ...pt('--', 'patch 1, runs cannot be aborted once started',
        r'a run becomes un-abortable once it has started, and a '
        r'superseded run is cancelled through CancelRunning, which '
        r'closes its progress token properly, so every begin gets its '
        r'end. (1.4.0 built this with a generation counter; the rework '
        r'in the next section removes the counter.)'),
    ...pt('--', 'patch 2, a save inside the debounce window',
        r'with checkOnSave off, didSave used to cancel the still-pending '
        r'live trigger and nothing replaced it, so the check was '
        r'skipped. This is not an exotic case: auto-save also saves '
        r'immediately on BufLeave and FocusLost, right after an edit. '
        r'The patch only cancels a pending trigger when a save-run will '
        r'actually replace it.'),
    ...pt('--', 'patch 3, closing a dirty buffer',
        r'two problems at once. The diagnostics computed for content '
        r'that no longer exists stayed visible, and the notes add that '
        r'they could even crash Neovim 0.12’s underline handler on '
        r'reopen via out-of-range lines. And cargo replayed stale '
        r'warnings: restoring the shadow file by hardlink moved its '
        r'mtime backwards, so cargo judged the crate fresh and replayed '
        r'the dirty build’s cached warnings. The patch clears that '
        r'file’s diagnostics, restores the shadow entry by copy (a '
        r'fresh mtime, hence a real re-check) and schedules one more '
        r'live run to re-truth the state.'),
    blank,
    ...para('--',
        r'Patch 3 is where the hardlink design shows its one weakness. '
        r'A hardlink shares the original file’s inode, and with it the '
        r'timestamps, and the changelog’s explanation depends on cargo '
        r'judging freshness by mtime. The fix, as described, uses a '
        r'real copy for the restored entry, where a new mtime is '
        r'required.'),

    ...sec('fitting the patch to the maintainers'),
    ...para('--',
        r'The 1.4.0 patch (installed at ~/.cargo/bin/bacon-ls from a '
        r'0.29.0 fork in ~/.local/src/bacon-ls-0.29.0-patched) worked. '
        r'About six hours later, on the same day (01:18 to 07:25), '
        r'1.4.1 replaced it with something different, and the reason is '
        r'a nice piece of engineering manners. The generation counter '
        r'was a new struct field, and the commit message for 6aeebfd '
        r'says the rework keeps the BackendRuntime large_enum_variant '
        r'size lint quiet, which implies the counter version did not. '
        r'Upstream CI runs cargo clippy --all-targets. A correct fix '
        r'that fails the maintainer’s CI is not a contribution. So the '
        r'run-abort fix was reworked to add no field at all: the '
        r'debounce task simply '
        r'drops its own handle once its sleep is over, so a later '
        r'abort() can only ever cancel a trigger that is still '
        r'sleeping, and in-flight runs are superseded through '
        r'CancelRunning.'),
    blank,
    ...para('--',
        r'The same entry reports the verification after the rework: '
        r'behaviour identical, the full 35-check end-to-end suite '
        r'passing against the field-free build, and upstream’s own 124 '
        r'tests passing, including a new restore_copy test. The branch '
        r'was filed as crisidev/bacon-ls pull request 139 and the local '
        r'binary now builds from upstream 0.30.0 plus that branch, in '
        r'~/.local/src/bacon-ls-upstream. The spec’s cmd override '
        r'documents all of this in the one place a future reader will '
        r'look:'),
    ...code('lua', 'lua/plugins/bacon-ls.lua · lines 48-51 (the override is gone)', r'''
      bacon_ls = {
        -- Uses Mason's bacon-ls (>= 0.31.0). The run-abort / stale-diagnostics
        -- fixes we needed were merged upstream as crisidev/bacon-ls#139 and
        -- shipped in 0.31.0, so the old local patched-build `cmd` override
        -- (~/.cargo/bin/bacon-ls) is gone.'''),
    ...para('--',
        r'The excerpt above is the comment that replaced the override. '
        r'Until 2026-10-09 the spec carried a cmd pointing at '
        r'~/.cargo/bin/bacon-ls, a locally patched build, with a long '
        r'comment that stated the cause, named the other two bugs, gave '
        r'the pull request number and ended with the exit condition '
        r'“Drop this cmd override once it merges”. That is exactly what '
        r'happened: 9b46e71 (2026-10-09, “Roadmap step 1: drop dead '
        r'bacon-ls cmd override”) deleted the override once upstream '
        r'0.31.0 shipped the fix, and the file now uses Mason’s '
        r'binary. A private fork was a tracked, temporary patch, and '
        r'the comment is why it could be removed without archaeology. '
        r'The 0715b98 version of the comment had said “drop once the '
        r'fix lands upstream (>0.29.0)”, and the 6aeebfd version pointed '
        r'at the real pull request.'),

    ...sec('how the fix was proved'),
    ...para('--',
        r'Nothing in this repo runs the verification: the suite lives '
        r'outside it, in ~/.bacon-e2e/, so what follows rests on '
        r'CHANGELOG 1.4.0 and the commit message of 0715b98 and not on '
        r'a test in this repository. They describe a headless end-to-end '
        r'harness with three batteries: a tiny crate, a three-crate '
        r'workspace, and a randomised 120-operation soak. The 35 checks '
        r'cover:'),
    ...pt('--', 'live edits',
        r'lint, syntax and type errors appear and clear in a buffer '
        r'that is never saved.'),
    ...pt('--', 'cross-crate behaviour',
        r'an error in one crate propagates to the others in 1.0 s and '
        r'clears again.'),
    ...pt('--', 'macros and derives',
        r'serde derive and macro-expansion errors map to the right '
        r'file.'),
    ...pt('--', 'manifest edits',
        r'Cargo.toml dependency changes flow through the shadow.'),
    ...pt('--', 'buffer lifecycle',
        r'dirty close and reopen cycles, which correspond to patch 3 (an inference; the changelog does not map them).'),
    ...pt('--', 'hostile timing',
        r'cancellation storms and didSave timings chosen to hurt, which '
        r'correspond to patches 1 and 2 (an inference; the changelog lists the checks '
        r'but does not map them).'),
    blank,
    cm('--', '  result                                          figure'),
    cm('--', '  ----------------------------------------------  -------'),
    cm('--', '  leaked progress tokens, any battery             0'),
    cm('--', '  bacon-ls resident memory after the 120-op soak  9.5 MB'),
    cm('--', '  stray cargo processes afterwards                none'),
    cm('--', '  full stack, real LazyVim config, real auto-save'),
    cm('--', '    “clippy tier”                                 0.71 s'),
    cm('--', '    “error tier”                                  0.68 s'),
    blank,
    ...para('--',
        r'That last pair is worth a second look. The notes call them '
        r'the clippy tier and the error tier and do not define the '
        r'second one. And 0.71 s is slightly worse than the 0.56 s '
        r'median from the micro-benchmark, with no explanation given. '
        r'A reasonable reading is that the full stack adds the '
        r'editor’s own handling on top of the server’s time, but that '
        r'is a guess.'),

    ...sec('every number in one place'),
    ...para('--',
        r'The measurements are scattered across comments, commit '
        r'messages and two CHANGELOG entries. Collected, with where '
        r'each one is recorded (CL is CHANGELOG):'),
    blank,
    cm('--', '  measurement                                value    where'),
    cm('--', '  -----------------------------------------  -------  ------'),
    cm('--', '  edit to diagnostic, two pipelines racing   5.6 s    CL 1.3.0'),
    cm('--', '  edit to diagnostic, one pipeline, 800 ms   0.8-0.9  CL 1.3.0'),
    cm('--', '  rust-analyzer instant tier, warm           155-235  CL 1.3.0'),
    cm('--', '                                             ms'),
    cm('--', '  clippy run on a warm 3-crate workspace     ~60 ms   CL 1.4.0'),
    cm('--', '  median edit to diagnostic, 500 ms, warm    0.56 s   CL 1.4.0'),
    cm('--', '  spawns for an 18-keystroke burst:'),
    cm('--', '    300 ms debounce                          18       CL 1.4.0'),
    cm('--', '    500 ms debounce                          1        CL 1.4.0'),
    cm('--', '    800 ms debounce                          1        CL 1.4.0'),
    cm('--', '  cross-crate error propagates               1.0 s    CL 1.4.0'),
    cm('--', '  full stack, real auto-save: clippy tier    0.71 s   CL 1.4.0'),
    cm('--', '  full stack, real auto-save: error tier     0.68 s   CL 1.4.0'),
    cm('--', '  marker diagnostic without updateOnInsert   never    CL 1.3.0'),
    cm('--', '                                             (300 s)'),
    cm('--', '  auto-save debounce / old server debounce   1000 /   file'),
    cm('--', '                                             800 ms   comments'),
    cm('--', '  E2E checks / soak operations               35 / 120 CL 1.4.0'),
    cm('--', '  leaked progress tokens / stray processes   0 / none CL 1.4.0'),
    cm('--', '  bacon-ls resident memory after soak        9.5 MB   CL 1.4.0'),
    cm('--', '  upstream test suite, passing               124      CL 1.4.1'),
    blank,
    ...para('--',
        r'Two caveats apply to the whole table. Everything is warm: a '
        r'cold cargo cache is not measured anywhere in the notes. And '
        r'the figures come from one machine and a small workspace, '
        r'recorded by the author in the CHANGELOG, not produced by a '
        r'script in this repository that a reader could re-run.'),

    ...sec('how the file grew'),
    cm('--', '  09-03 07:05  3ec11c4  32 lines. cargo backend, clippy with'),
    cm('--', '                        --workspace --all-targets --all-features,'),
    cm('--', '                        updateOnInsert in init_options + settings.'),
    cm('--', '  09-03 19:54  f35b4f6  checkOnSave off, --all-targets dropped,'),
    cm('--', '                        --no-deps added, debounce 800, and the'),
    cm('--', '                        “must stay ON” comment from the A/B test.'),
    cm('--', '  09-04 01:18  0715b98  cmd override to the patched 0.29.0 build;'),
    cm('--', '                        debounce 800 back to 500, with evidence.'),
    cm('--', '  09-04 07:25  6aeebfd  rebuilt on upstream 0.30.0 + pull request'),
    cm('--', '                        139; comment rewritten; exit condition.'),
    cm('--', '  10-09        9b46e71  cmd override dropped: Mason 0.31.0+.'),
    cm('--', '  10-09        f5936dc  root_dir and before_init (RustContext).'),
    cm('--', '  10-12        be73b6c  on_exit restart; skip registry/rustup.'),
    cm('--', '  10-13        98c9bb4  no client for virtual buffers; cargo check.'),
    cm('--', '  10-13        3f868dd  --keep-going; URI-scheme buffers (diffview).'),
    cm('--', '  10-16        ff1c8fa  Windows drive-letter roots accepted.'),
    blank,
    ...para('--',
        r'The file doubled in size in 24 hours, from 32 lines to 63, and '
        r'almost all of the growth is comment: 40 of the 62 non-blank '
        r'lines of the 6aeebfd version are comment. It is a configuration file whose '
        r'job is to keep the reasons next to the numbers. The code part '
        r'gained three settings (checkOnSave, the debounce, cmd) and '
        r'lost one argument; what changed far more is how much is '
        r'known about each line.'),

    ...sec('October: root_dir, before_init and on_exit'),
    ...para('--',
        r'The spec grew four functions that have nothing to do with '
        r'latency and everything to do with not misbehaving. Their '
        r'comments are long and specific, so this section follows them.'),
    ...code('lua', 'lua/plugins/bacon-ls.lua · lines 53-92 (root_dir)', r'''
        -- One client per Cargo WORKSPACE, rooted at the outermost manifest
        -- with a [workspace] table (config.rust_context.root), not at the
        -- nearest Cargo.toml: bacon-ls mirrors its root into a shadow, so a
        -- member-rooted shadow lacks the workspace manifest and the sibling
        -- path dependencies and cargo fails ("believes it's in a workspace
        -- when it's not"). Paths under the cargo registry/git checkouts and
        -- rustup (what `gd` into a dependency or std opens) get no client at
        -- all: each ships its own Cargo.toml and would be a root of its own,
        -- compiled by clippy with target/ written into ~/.cargo. With no
        -- root found the client is not started, so a standalone solo.rs
        -- without a crate no longer attaches and spams cargo errors;
        -- rust-analyzer's detached-file mode is a separate client and is
        -- unaffected.
        root_dir = function(bufnr, on_dir)
          local name = vim.api.nvim_buf_get_name(bufnr)
          -- no client for virtual buffers (diffview://, fugitive://, 99-prompt ...): the root of
          -- diffview:// came out as "." and started a second client that outlived Diffview
          if name == "" or name:match("^%w[%w+.-]*://") or vim.bo[bufnr].buftype ~= "" then
            return
          end'''),
    ...pt('--', 'outermost workspace root (f5936dc, 2026-10-09)',
        r'root_dir asks config.rust_context.root for the root of the file. '
        r'The comment explains the choice: the shadow mirrors the root, so '
        r'rooting at a member crate loses the workspace manifest and the '
        r'sibling path dependencies, and cargo fails. One client per '
        r'workspace, not per crate.'),
    ...pt('--', 'dependency sources (be73b6c, 2026-10-12)',
        r'paths under /.cargo/registry/, /.cargo/git/ and /.rustup/ get no '
        r'client. Going to definition into a dependency or std opens such '
        r'a file; each ships its own Cargo.toml and would become a root of '
        r'its own, compiled by clippy with target/ written into ~/.cargo. '
        r'The same list of roots is used by the disk guard of the '
        r'auto-save page.'),
    ...pt('--', 'virtual buffers (3f868dd, 2026-10-13)',
        r'names with a URI scheme or a non-empty buftype get nothing. The '
        r'comment records the symptom: the root of diffview:// came out as '
        r'“.” and started a second client that outlived Diffview. A '
        r'drive-letter check (^%a:[/\\]) for Windows absolute roots was '
        r'added in ff1c8fa (2026-10-16).'),
    ...pt('--', 'no cargo (98c9bb4, 2026-10-13)',
        r'if cargo is not executable, no client starts and one WARN says '
        r'why. Without the check the client died with a bare “No such '
        r'file or directory (os error 2)”. The module-level no_cargo_told '
        r'flag makes the warning appear once per session.'),
    ...code('lua', 'lua/plugins/bacon-ls.lua · lines 93-116', r'''
        -- A crashed server is restarted (rust_restart.lua).
        on_exit = function(...)
          return require("config.rust_restart").on_exit("bacon_ls")(...)
        end,
        -- Match the per-project Cargo context (:RustContext) so both
        -- diagnostic tiers see the same features/target. Settings reach the
        -- server in two ways, init_options (initialize) and the
        -- workspace/configuration pull, so patch both. Always rebuilt from
        -- the defaults (also with no stored context): after
        -- `:RustContext reset` the restarted client must not keep the
        -- previous context's args.
        before_init = function(params, config)
          local rc = require("config.rust_context")
          local ctx = rc.get(rc.root((config.root_dir or vim.uv.cwd()) .. "/x"))
          local s = vim.deepcopy(bacon_ls_settings)
          s.cargo.extraArgs = rc.bacon_args(ctx)
          params.initializationOptions = s
          -- in place: the client already holds a reference to this table
          config.settings = config.settings or {}
          config.settings.bacon_ls = s
        end,
        -- Also answered to the server's workspace/configuration pull.
        settings = { bacon_ls = bacon_ls_settings },'''),
    ...pt('--', 'on_exit',
        r'a crashed server is handed to config.rust_restart (be73b6c), '
        r'which supervises restarts. See that module’s page.'),
    ...pt('--', 'before_init',
        r'the shared settings table is deep-copied per client and its '
        r'extraArgs replaced by rust_context.bacon_args(ctx), so the '
        r'features and target chosen with :RustContext reach clippy '
        r'too. The table is rebuilt from the defaults every time, '
        r'because after :RustContext reset a restarted client must not '
        r'keep the previous context’s arguments. This is why the “same '
        r'table cannot drift” argument earlier on this page is now '
        r'slightly weaker: the table is the starting point, no longer the '
        r'final value.'),

    ...sec('how it is tested'),
    ...para('--',
        r'tests/bacon-ls-config_spec.lua exists for this file. Its cases '
        r'include: the server is declared with the cargo and clippy '
        r'settings; updateOnInsert is sent in init_options and the Mason '
        r'binary of at least 0.31.0 is used; a workspace member is rooted '
        r'at the outermost [workspace] with exactly one client; plain '
        r'crates root at the crate directory while empty names and loose '
        r'.rs files get none; diffview and fugitive buffers get no '
        r'client; without cargo no client starts and one WARN is shown; '
        r'a standalone .rs file attaches rust-analyzer but not bacon_ls; '
        r'dependency directories start nothing; before_init uses the '
        r'stored :RustContext and rebuilds from defaults after a reset; a '
        r'killed server is restarted through rust_restart.on_exit; and '
        r'several end-to-end cases (clippy diagnostics arrive, a broken '
        r'crate shows the rust-analyzer error first and clippy later, an '
        r'edit is reported within 5 s with one pipeline and nothing '
        r'started by :w, changing :RustContext features restarts with '
        r'matching args).'),

    ...sec('limits, and what is next'),
    ...pt('--', 'it needs bacon-ls 0.31.0 or newer',
        r'the spec trusts Mason to install a version that contains the '
        r'upstream fixes. The test “sends updateOnInsert in init_options '
        r'and runs Mason’s bacon-ls >= 0.31.0” is the check; an older '
        r'binary would bring the abort bug back.'),
    ...pt('--', 'tests are not linted live',
        r'no --all-targets means cfg(test) code and test targets get '
        r'no clippy feedback while typing. This is documented and '
        r'deliberate, and it is a real gap.'),
    ...pt('--', 'one workspace was measured',
        r'every latency figure is warm, on a small workspace '
        r'(three crates in the CHANGELOG wording). A cold build, or a '
        r'workspace with hundreds of crates, is not covered by the '
        r'notes, and --workspace means every edit re-checks the '
        r'workspace.'),
    ...pt('--', 'duplicated type errors',
        r'a type error can appear from both rust-analyzer and bacon-ls '
        r'for a moment. The decision, recorded in rustaceanvim.lua, '
        r'was to accept the visual overlap rather than suppress one '
        r'source.'),

    ...sec('what to take from it'),
    ...pt('--', 'subtract before you tune',
        r'the 5.6 s to 0.9 s win came from deleting a pipeline and an '
        r'argument, not from a clever setting.'),
    ...pt('--', 'keep the experiment next to the value',
        r'“measured: marker diagnostic never arrived in 300s” is worth '
        r'more than any amount of “must stay on”.'),
    ...pt('--', 'read the tool',
        r'the stacked “checking…” rows were first blamed on two '
        r'pipelines, which was partly true. What remained turned out to '
        r'be a lifecycle bug in the server, found by following the '
        r'symptom into its source.'),
    ...pt('--', 'fix it where it lives',
        r'a private patch fixed one editor; a pull request shaped to '
        r'upstream’s CI could fix everyone’s. The spec file says '
        r'exactly when to delete the override.'),
    blank,
    link('→ github.com/xynorash/xynovim', 'https://github.com/xynorash/xynovim'),
    link('→ crisidev/bacon-ls pull request 139', 'https://github.com/crisidev/bacon-ls/pull/139'),
  ],
);
