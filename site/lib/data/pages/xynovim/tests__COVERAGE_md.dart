import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/tests/COVERAGE.md',
  lines: [
    heading('# Feature coverage matrix'),
    blank,
    ...text('tests/COVERAGE.md answers a different question from a coverage percentage. It does not count lines. It lists every feature of the configuration, names the spec file that exercises it, notes how real that test is (a real rust-analyzer, a stubbed picker, a fake git wrapper), and then lists, with a reason each, the features that have no test or only a partial one. It ends with the bugs the specs themselves found. It is 87 lines, and it is the honest half of the claim that the configuration has a test suite.'),
    blank,
    kv('role', 'map from feature to spec, with the untested features and their reasons'),
    kv('language', 'Markdown tables'),
    kv('size', '87 lines; three tables: matrix, untested features, bugs found'),
    kv('rows', '37 rows in the matrix, 19 rows in the untested table, 8 bugs'),
    kv('specs', '38 files in tests/'),
    kv('created', 'b2fee5c, 2026-10-13, touched by 12 commits in total'),
    blank,
    ...sec('what the file claims at the top'),
    ...code('markdown', r'tests/COVERAGE.md · lines 1-8', r'''
# Feature coverage matrix

Which spec exercises which feature of the config, and what is not tested (with the reason).
Line coverage is a different measure (`scripts/test.sh --coverage`); this table is about features.
Counts are from the last full run: 1744 passed, 0 failed, 23 skipped (36 spec files). Skips are
`pending` entries or tests that need something this machine lacks (not testable here). A bug a spec
finds is written as an assertion of the correct behaviour (skipped while it reproduces); the ones
found so far are fixed (listed at the end).'''),
    ...text('The header separates two measures. Line coverage is produced by scripts/test.sh with --coverage; this table is about features. It also states how to read skips: pending entries, or tests that need something the machine lacks. And it promises that a bug a spec finds is written as an assertion of the correct behaviour and skipped while it reproduces.'),
    ...text('One line of that header is stale, and it should be said plainly. It still reads counts from an older run: 1744 passed, 0 failed, 23 skipped across 36 spec files. The README, docs/TESTING.md and the website say 38 spec files and 1805 passing, 32 skipped. The table below the header is current to the macros, egui, Rust project and website work, but the numbers were not refreshed.'),
    ...sec('the matrix'),
    ...text('The matrix has three columns: area with the files it covers, the spec, and notes. The notes are where the file earns its trust, because they say how much of the claim is real. A few rows show the range.'),
    ...code('markdown', r'tests/COVERAGE.md · lines 12-14', r'''
| Startup, options, lazy.nvim setup, lockfile, extras, small plugin specs (news, scrolling, telescope, ghost text, codelens, harpoon, navigation), remote clipboard (`config/{options,lazy,remote_clipboard}.lua`, `lazyvim.json`) | `startup-and-options` | fresh-startup facts come from child nvims |
| Clean startup, harness proof | `smoke` | |
| Test helpers | `harness` | |'''),
    ...text('The first rows are cheap ones: a smoke test that the configuration starts cleanly, a spec for the test helpers themselves. Then comes the Island Dark theme, whose colours are written out literally and whose converter is tested on a synthetic scheme file rebuilt from the palette, and the global and Rust keymaps, where the notes say a real rust-analyzer answers for some keys and the rest are stubbed.'),
    ...code('markdown', r'tests/COVERAGE.md · lines 15-17', r'''
| Island Dark theme (`colors/`, `lua/island/*`, `plugin/after/*`, `tools/icls2nvim.py`, lualine theme) | `theme-island` | colours written out literally; converter tested on a synthetic `.icls` rebuilt from the palette; load time printed, not asserted |
| Global keymaps (`config/keymaps.lua`, diffview/coverage/99/harpoon/dap keys, which-key groups, key uniqueness) | `keymaps-global` | |
| Rust keymaps (`<leader>r*`, `rust_assist.lua`, `rust_nav.lua`, `after/ftplugin/rust.lua`) | `keymaps-rust` | real rust-analyzer for rv, rh, rw, rT, ru, rl; the rest stubbed |'''),
    ...code('markdown', r'tests/COVERAGE.md · lines 29-30', r'''
| Provider picker `<leader>9P` cannot leave the guarded provider | `agent-99-guard` | no real provider CLI |
| Portable runner (`scripts/test.lua`, `scripts/test.ps1`), `xyno-os` headers, `scripts/bootstrap.ps1`, `platforms.yml` | `scripts-portable` | the PowerShell scripts and the workflow only run in the platforms workflow (Windows, macOS) |'''),
    ...bullet('Diagnostics tiers', 'bacon-ls-config checks the clippy tier configuration; server-supervision-statusline kills real servers with kill -9 and SIGTERM and checks the loop guard.'),
    ...bullet('Debugger and tests', 'dap-neotest-coverage opens real codelldb sessions; rust-tasks-tools does one real llvm-cov run.'),
    ...bullet('Agent', 'agent-sandbox runs real bwrap; agent-failclosed checks the refusal without a backend on every OS; agent-99-guard has no real claude request.'),
    ...bullet('Local History', 'the matrix row for local-history says fake git wrapper, shimmed timers.'),
    ...bullet('Macros and dependencies', 'crate-meta, deps-freshness, crate-add, crate-features, import-engine, crate-import, macro-attrs, macro-tools and macros-deps-flows, with real cargo and real rust-analyzer on temp copies of fixtures; network parts skip offline.'),
    ...bullet('New project flows', 'rust-new runs the real cargo offline in temp directories and checks the dashboard at several terminal sizes; egui-new uses a fake template over file:// and a local HTTP server.'),
    ...bullet('Website', 'site builds the site into a temp directory and checks head tags, links, anchors, CSP, alt texts, README numbers, size budgets, contrast and the workflow, but it cannot see a browser.'),
    ...text('Notice that the notes never say tested and leave it at that. The Notes column says what was stubbed: pickers, vim.ui.select, the git binary, a template server. A reader decides how much trust a green test deserves.'),
    ...sec('the second table: features without a test'),
    ...text('The second heading is Features without a test, or only partly tested, and it is the most unusual part of the file. Each row gives a feature and a reason, and the reasons fall into a few families.'),
    ...code('markdown', r'tests/COVERAGE.md · lines 54-57', r'''
| A real 99 request to claude | needs a real claude session and network (`agent-99-guard`, pending) |
| lazy.nvim bootstrap clone when missing | needs network and an empty data dir (the script text is checked) |
| Fresh install through `bootstrap.sh` | only with `XYNO_TEST_NETWORK=1` (passed once there, not in the default suite) |
| A real GitHub Actions run | needs a push; the workflow is checked by text, actionlint and zizmor |'''),
    ...bullet('Needs a live account or network', 'a real 99 request to claude, a real GitHub Actions run, the lazy.nvim bootstrap clone, a fresh install through bootstrap.sh (passed once with XYNO_TEST_NETWORK=1).'),
    ...bullet('Lives outside the repo', 'the global git config (mergiraf, delta, zdiff3, rerere), the cargo profile for profiling, real samply, flamegraph and act runs.'),
    ...bullet('Needs a pty or mouse', 'Snacks and telescope pickers, interactive confirmations, mouse clicks on codelens, narrow terminals, the macro and dependency pickers driven for real.'),
    ...bullet('Documented limits', 'crate guesses that do not match by name (Rng does not find rand), serde keys offered while its derive feature is off.'),
    ...bullet('Cannot be set up', 'the vim.v.exiting branch of the restart handler, two real workspaces through rustaceanvim, a lock aged exactly 60 s.'),
    ...code('markdown', r'tests/COVERAGE.md · lines 58-58', r'''
| `shellcheck` on the scripts, `stylua --check` | shellcheck passes on `scripts/*.sh` and `docs/media/*.sh`; stylua reports drift in 61 files since the macros and dependencies work, 16 before (informational) |'''),
    ...text('The shellcheck row is a good example of precise wording: shellcheck passes on the scripts, and stylua reports drift in 61 files since the macros and dependencies work (16 before), shown as informational. The matrix does not hide that the formatter is not clean.'),
    ...sec('the third table: bugs found by the specs'),
    ...text('The last table keeps the score of the suite. Eight bugs were found by writing the specs themselves, all fixed in the final loop round 1, and each now has the spec that asserts the correct behaviour.'),
    ...code('markdown', r'tests/COVERAGE.md · lines 78-87', r'''
| # | Bug | Spec that now covers it |
| --- | --- | --- |
| 1 | `rust_nav.goto_super`: an empty definition list gave no WARN | `keymaps-rust` |
| 2 | `rust_routes.collect` skipped `target`, `.git`, ... only at the root | `rust-routes` |
| 3 | `rust_context.apply` for a second workspace reached no client | `rust-context` |
| 4 | `agent_sandbox`: renaming the parent of the masked memory dir; `wrap` without `~/.claude` | `agent-sandbox` |
| 5 | cargo-deny diagnostics on `Cargo.lock` on the wrong line | `git-lint-supply-chain` |
| 6 | `lsp_status`: dead `b:xynovim_bacon` test; the edit counter restarted after `:edit!` | `server-supervision-statusline` |
| 7 | `scripts/test.sh --timeout` without a value exited 1, not 2 | `test-infra-readme-claims` |
| 8 | README plugin count | `test-infra-readme-claims` |'''),
    ...text('They are small and concrete: goto_super with an empty definition list gave no warning; routes collection skipped target and .git only at the root; a second workspace reached no client; the sandbox masked-memory directory broke when its parent was renamed; cargo-deny diagnostics on Cargo.lock landed on the wrong line; a dead status test in lsp_status and an edit counter that restarted after an edit; test.sh --timeout with no value exited 1 where 2 is the convention; and the README plugin count was wrong. Bug 8 is a sign the claims spec works: it found a mistake in documentation, not code.'),
    ...sec('design decisions'),
    ...bullet('Features, not lines', 'line coverage tells you what ran; this tells you what is believed to work and why.'),
    ...bullet('Say what was stubbed', 'the notes column is mandatory in spirit; a row without one would claim more than it proves.'),
    ...bullet('An explicit not tested list', 'omissions are written down with reasons so that nobody assumes coverage.'),
    ...bullet('Bugs found by specs are listed', 'the table is a record of the suite paying for itself.'),
    ...sec('edge cases and gaps'),
    ...bullet('Stale numbers in the header', 'the counts at the top predate the latest specs and were not refreshed in the same commits that changed the README.'),
    ...bullet('Platform skips are not in the matrix', 'the whole-file xyno-os skips on Windows and macOS are described in docs/KNOWN_ISSUES.md, not here.'),
    ...bullet('Plugin repositories', 'this matrix lists specs under tests/ and does not mention the nine xyno plugins; commit subjects in the plugin repositories (for example xyno-rust.nvim and xyno-sandbox.nvim) mention specs and a CI workflow of their own.'),
    ...sec('how it is tested'),
    ...text('The file is checked by the claims spec: tests/test-infra-readme-claims_spec.lua asserts things the README and docs say about the infrastructure, and bug 8 shows this working. The matrix is not machine-checked row by row; nothing fails if a spec is renamed and the matrix is not updated, which is the weakness of any hand-kept table.'),
    ...sec('history'),
    ...bullet('2026-10-13', 'b2fee5c creates it with the first 22 feature specs; 98c9bb4 (final loop round 1) records the bugs found.'),
    ...bullet('2026-10-14', 'f31e013, 25086fd and b9363cd extend it for rounds 4 and 5 and the macros phase.'),
    ...bullet('2026-10-15 to 16', 'ddc51eb, b020526, 0cfb739 add egui; d163480 adds the Rust project flows; 94ff2dc the website.'),
    ...bullet('2026-10-21 and 22', 'a2e0d5a for the platform work, 0da94f4 for the removed Dark.icls.'),
    blank,
  ],
);
