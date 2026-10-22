import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/docs/TESTING.md',
  lines: [
    heading('# Testing'),
    blank,
    ...text('docs/TESTING.md is the manual of the test suite. It is 22 lines and the whole file is dense: the commands, what each spec run does and does not touch, how to write a spec with the home-made framework, which fixtures exist, how many specs and tests there are right now, what the coverage tool does and how CI uses it. It is the long form of the README section Tests: run them yourself, and it is the file to read before adding a spec.'),
    blank,
    kv('role', 'how the headless suite runs and how to write a spec'),
    kv('language', 'Markdown'),
    kv('size', '22 lines, about 8 KB'),
    kv('counts', '38 spec files, 1837 tests, 1805 pass, 32 skipped with a reason, 0 fail (my Linux machine)'),
    kv('runtime', 'about 10 minutes; slowest file keymaps-global at 40 to 80 seconds'),
    kv('runners', 'scripts/test.sh (bash), scripts/test.lua and scripts/test.ps1 (portable)'),
    blank,
    ...sec('the commands'),
    ...code('sh', r'docs/TESTING.md · lines 8-12', r'''
scripts/test.sh                 # or: make test
scripts/test.sh routes smoke    # only spec files whose path contains one of the words
scripts/test.sh --list          # the spec files, nothing run
scripts/test.sh --coverage      # also a per-file line-coverage report (make coverage)
scripts/test.sh --timeout 300 -v'''),
    ...text('The runner is a script, not a plenary invocation, and it takes words: any word after the command selects the spec files whose path contains it, so routes and smoke runs two files. --list prints the files without running, --coverage adds a line-coverage report, --timeout overrides the per-file limit. Make has two targets, test and coverage, that forward ARGS to it.'),
    ...sec('what runs and how it is isolated'),
    ...text('Each tests/*_spec.lua runs in its own headless nvim with the full configuration and a hard timeout of 120 seconds by default, so a hanging file is killed, counted as failed, and the suite goes on. The exit status is 0 for no failure (skips allowed), 1 for a failure, timeout or crash, and 2 when nothing matched or setup is missing.'),
    ...bullet('Isolation', 'the config is this checkout through a temporary XDG_CONFIG_HOME; state, cache and TMPDIR are temporary and removed at the end, so shada, undo files, lsp.log and Local History of the specs never touch yours. XDG_DATA_HOME is the real one so installed plugins are reused and nothing is installed. A fresh machine runs scripts/bootstrap.sh first; without plugins the script says so and exits 2.'),
    ...bullet('Cleanup', 'temp crates, language servers, spawned jobs and tmux servers (private sockets named xynotest-pid-star) are removed by the helpers at the end of each file and again by the script, which signals each nvim process group.'),
    ...bullet('Lockfile watch', 'the script warns if lazy-lock.json changed during the run, and CI checks it before and after.'),
    ...sec('writing a spec'),
    ...text('The framework is small and deliberate. The file explains why plenary’s busted runner was not used: PlenaryBustedFile starts a nested nvim with its own minimal init, which would not load this configuration, and it cannot carry the timeout or the coverage hook. So tests/harness.lua provides describe, it, before_each, after_each, pending and skip.'),
    ...code('markdown', r'docs/TESTING.md · lines 18-18', r'''
- **Writing a spec**: `tests/<name>_spec.lua` with `describe` / `it` / `before_each` / `after_each` / `pending` / `skip(reason)` (a small framework in `tests/harness.lua`; plenary's busted was not used because `PlenaryBustedFile` starts a nested nvim with its own minimal init, which would not load this config, and cannot carry the timeout or the coverage hook). `local H = require("xynotest.helpers")` (a private name: `tests.helpers` collides with other plugins' `lua/tests/`) gives assertions (`eq ok not_ok is_nil match no_match has throws`), `wait_for(pred, ms, msg)`, `wait_lsp(name, bufnr)`, `feed(keys)`, `open(path)` (also fires `User VeryLazy`, which never fires headless), `clients()`, `diagnostics(source)`, `messages()`, `capture_notify()`, `fixture(name, {git=true})` / `open_fixture(name, rel)` (a private copy of a fixture in a temp dir), `git(dir, ...)`, `sandbox_sh(script, project)` (a bash script inside the 99 sandbox wrapper), `tmux(args)`, `spawn(cmd)`, `tmpdir()`, `cleanup()`. `H.need_rust()`, `H.need_sandbox()`, `H.need_tmux()` (in a test or `before_each`) and `H.skip_file(reason)` skip with an explicit message when the tool is missing or unusable; `XYNO_TEST_SKIP_RUST=1` forces the Rust ones to skip.'''),
    ...text('The helpers module is required under a private name, xynotest.helpers, because tests.helpers collides with other plugins that ship a lua/tests directory. It gives assertions (eq, ok, not_ok, is_nil, match, no_match, has, throws), wait_for, wait_lsp, feed, open (which also fires User VeryLazy, which never fires headless), diagnostics, messages, capture_notify, fixture, git, sandbox_sh, tmux, spawn and tmpdir. Tools that may be missing are handled by H.need_rust, H.need_sandbox, H.need_tmux and H.skip_file, which skip with an explicit message; XYNO_TEST_SKIP_RUST=1 forces the Rust ones to skip.'),
    ...bullet('Timeouts', 'a spec that needs more than the default says so in a header comment in its first 15 lines; keymaps-global asks for 400 seconds.'),
    ...bullet('OS headers', 'a spec with an xyno-os header in its first lines is skipped whole on that OS with its reason, and counts as 0 passed, 1 skipped.'),
    ...bullet('Known bugs', 'a bug a spec finds is written as an assertion of the correct behaviour and skipped while it reproduces, so it begins to pass when the bug is fixed.'),
    ...sec('fixtures'),
    ...code('markdown', r'docs/TESTING.md · lines 19-19', r'''
- **Fixtures** (`tests/fixtures/`, committed, copied per test): `basic` (lib + bin + integration test + trait + one clippy finding), `workspace` (two members, a path dependency, features `ssr`/`csr` with a `compile_error!` when both are on), `broken` (type error), `no-deps-lab` (a crate without dependencies and an unresolved `Uuid`), `deps-lab` (serde with `derive`, clap, anyhow, serde_json, thiserror and tokio, with derive and attribute macros in `main.rs`; the base of the dependency and macro specs), `deps-lab-nofeature` (the same with serde declared without its `derive` feature), `keymaps-rust-crate` (the small crate the keymap specs open), `standalone.rs` (no Cargo.toml), `sql_and_routes.rs` (sqlx strings and axum/actix routes).'''),
    ...text('Fixtures are small committed crates copied per test, so a spec can break one without affecting the next. basic has a library, a binary, an integration test, a trait and one clippy finding. workspace has two members, a path dependency and features ssr and csr with a compile_error when both are on, which is the crate the RustContext demo uses. broken has a type error. no-deps-lab and deps-lab, with its no-feature variant, are the base of the dependency and macro specs. The directory also holds fixtures for rust-tasks-tools and plain files for the sql and routes specs.'),
    ...sec('the counts, and why three numbers disagree'),
    ...text('Line 20 lists every spec by area and gives the current numbers. It is careful to say the counts are machine-dependent. The figures are from my Linux machine, which has debug set to true in its cargo config, a cargo bin directory and no pwsh. A fresh Linux run of the same commit gave 1766 passed, 31 skipped; the Ubuntu CI run 39695896272 gave 1749 passed, 76 skipped, 0 failed, the extra skips being the codelldb real-debug specs, the cargo-bin spec and the no-pwsh ones.'),
    ...text('The same line states what the skips are: pending entries (a real claude request, interactive pickers, the network install) and known bugs written as assertions of the correct behaviour. On Windows and macOS, startup-and-options and rust-analyzer-config do not run at all, because they read /proc and start a Python HTTP server; the line says that the portable part of them is untested there.'),
    ...sec('coverage and CI'),
    ...text('Coverage is a hand-built line collector: tests/coverage_hook.lua is a debug.sethook line collector using only the standard library, loaded with --cmd so that it sees the config’s own startup and coroutines, and scripts/coverage.lua merges the dumps. The denominator is estimated from the source text, so the file calls the percentages a guide. The last full figure was 86.4 percent before the macros and dependencies modules, and a covered run is slower because the hook switches the LuaJIT compiler off. Under coverage 9 more tests skip, because the rust-analyzer ones hang with the line hook.'),
    ...code('markdown', r'docs/TESTING.md · lines 22-22', r'''
- **CI**: the `ci` workflow runs `scripts/bootstrap.sh`, then `scripts/test.sh`, then the lockfile check again. rust-analyzer is installed there, so the Rust specs run; where a tool is missing its specs skip.'''),
    ...sec('design decisions'),
    ...bullet('One process per file', 'a crash or a hang is contained and attributed; the price is startup time repeated 38 times.'),
    ...bullet('Real tools over mocks', 'specs use real cargo, rust-analyzer, bwrap, tmux and git where available and skip when a tool is absent. Stubs exist too: docs/DETAILS.md says the specs stub vim.ui.select and the pickers.'),
    ...bullet('Private temp state, real plugins', 'the suite is hermetic about your files but reuses the plugin install, to stay fast.'),
    ...bullet('Home-made framework', 'chosen because it must carry timeouts, coverage and the real config; the harness has a spec of its own (harness_spec.lua).'),
    ...sec('edge cases handled'),
    ...bullet('Exit hang', 'an early version hung at exit because of a bufferline tabline; the fix and a result line printed before cleanup arrived in b2fee5c.'),
    ...bullet('Tmux sockets', 'private socket names make cleanup targeted.'),
    ...bullet('User namespaces', 'scripts/test.sh was not run under a CI runner that restricts them; sandbox specs skip there.'),
    ...sec('how it is tested'),
    ...text('The suite tests itself. harness_spec.lua checks the framework, and test-infra-readme-claims_spec.lua exercises scripts/test.sh for real with a throwaway fake repository, along with scripts/coverage.lua, the runner, the hook, the Makefile and the claims README and CHANGELOG make. scripts-portable_spec.lua checks the portable runner and the OS headers. Bug 7 in tests/COVERAGE.md came from this: scripts/test.sh with a timeout and no value exited 1 instead of 2.'),
    ...sec('history'),
    ...bullet('2026-10-13', 'b2fee5c lands the suite itself: 22 feature specs (1011 tests), the feature matrix, the per-spec timeout and the exit-hang fix. The testing text was then part of the README.'),
    ...bullet('2026-10-14', '0b0eee8 creates docs/TESTING.md in the docs split.'),
    ...bullet('2026-10-16', 'ff1c8fa adds the portable runner and OS-aware skips.'),
    ...bullet('2026-10-22', 'the counts are re-measured: bd7201a then 2d4445e (1805 passing, 32 skipped).'),
    blank,
  ],
);
