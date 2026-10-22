import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-rust.nvim/tests/rust-tasks-tools_spec.lua',
  lines: [
    cm('--', r'──────────────────────────────────────────'),
    cm('--', r'tests/rust-tasks-tools_spec.lua — the exact command line behind every row of every picker'),
    cm('--', r':RustTargets, :RustTools, :ActJob, :RustNew and the doctests runner, with the terminal faked'),
    cm('--', r'──────────────────────────────────────────'),
    blank,
    kv(r'role', r'spec for lua/xyno_rust/rust_tasks.lua (277 lines)'),
    kv(r'language', r'Lua, run by tests/run.lua'),
    kv(r'size', r'757 lines, 36 tests in 8 describe blocks'),
    kv(r'real', r'cargo (metadata, new), a fixture crate, git init, the yaml parser for :ActJob'),
    kv(r'faked', r'Snacks.picker, Snacks.terminal, vim.ui.select and vim.ui.input, sometimes vim.system'),
    kv(r'fixtures', r'tests/fixtures/rust-tasks-tools-all, tests/fixtures/act-workflow.yml'),
    kv(r'origin', r'xynovim tests/rust-tasks-tools_spec.lua, 2026-10-13 (b2fee5c)'),
    ...sec(r'why this file exists'),
    ...para('--', r'rust_tasks.lua turns a Cargo workspace into things you can run: a picker of every target '
        r'with the right cargo subcommand, a picker of workspace tools (timings, bloat, machete, '
        r'deny, audit, tree -d, llvm-cov), a command that runs the GitHub Actions job under the '
        r'cursor with act, a cargo new wrapper, and a doctest runner. Nearly all of it is argument '
        r'lists. The value of the module is that the argument list is correct: the right package, '
        r'the right target selector, the context flags of :RustContext in the right place, and '
        r'nothing that cargo would take for an option.'),
    ...para('--', r'A wrong argument list does not fail the picker. It fails later, in a terminal, with a '
        r'cargo error. So the spec compares the cmd of each item with the exact table, element by '
        r'element. The pickers and the terminal are not exercised: the spec replaces Snacks.picker '
        r'with a function that records the options and Snacks.terminal with one that records the '
        r'call. What a picker row does is run item.cmd in a terminal at the workspace root, so the '
        r'command line plus the terminal arguments are the whole observable behaviour.'),
    ...sec(r'the module’s contract in one table'),
    ...code('lua', r'lua/xyno_rust/rust_tasks.lua · lines 70-77', r'''
-- target kind -> { label, cargo subcommand words, target selector flag }
local ACTIONS = {
  bin = { { "run", "run", "--bin" }, { "test", "test", "--bin" }, { "build", "build", "--bin" } },
  example = { { "run", "run", "--example" }, { "build", "build", "--example" } },
  test = { { "test", "test", "--test" } },
  bench = { { "bench", "bench", "--bench" } },
  lib = { { "test", "test", "--lib" }, { "doc-test", "test", "--doc" }, { "build", "build", "--lib" } },
}
'''),
    ...code('lua', r'lua/xyno_rust/rust_tasks.lua · lines 107-119', r'''
      for _, a in ipairs(ACTIONS[kind] or {}) do
        local cmd = { "cargo", a[2], "-p", p.name }
        if kind == "lib" then
          cmd[#cmd + 1] = a[3]
        else
          vim.list_extend(cmd, { a[3], t.name })
        end
        vim.list_extend(cmd, ctx_flags(root))
        items[#items + 1] = {
          text = ("%s  %s %s (%s)"):format(a[1], kind, t.name, p.name),
          cmd = cmd,
        }
      end
'''),
    ...para('--', r'Each target kind has a list of { label, cargo subcommand, selector flag }. A bin gets '
        r'run, test and build with --bin; an example gets run and build with --example; a test '
        r'target gets test with --test; a bench gets bench with --bench; a lib has no name '
        r'argument, it gets --lib or --doc. The package is always selected with -p, which is what '
        r'makes the same code work in a workspace with many crates. Then the flags of the stored '
        r'context are appended.'),
    ...sec(r'the preamble: how the stubs work'),
    ...code('lua', r'tests/rust-tasks-tools_spec.lua · lines 12-30', r'''

local restores = {}

--- Replace t[k] by v until the end of the test.
local function stub(t, k, v)
  local orig = t[k]
  t[k] = v
  restores[#restores + 1] = function()
    t[k] = orig
  end
end

local function unstub_all()
  for i = #restores, 1, -1 do
    pcall(restores[i])
  end
  restores = {}
end

'''),
    ...para('--', r'The header says it directly: Snacks.picker, Snacks.terminal, vim.ui and vim.system are '
        r'stubbed where the spec only needs to see what would run, and real cargo is used for '
        r'metadata and cargo new. Three things are worth noticing.'),
    ...pt('--', r'H.fake_snacks() before require("xyno_rust").setup()', r'a global Snacks with a picker and a terminal table exists before the plugin loads, so '
        r'that deps.snacks() finds it without a real snacks.nvim. The test machine and CI have none.'),
    ...pt('--', r'stub and unstub_all', r'every replacement is recorded with its original and put back in reverse order by '
        r'after_each. A test that stubs rc.get, vim.system or vim.ui.select cannot affect the next. '
        r'The same hook wipes all buffers and changes the directory back to HOME.'),
    ...pt('--', r'real setup()', r'the commands exist because the real setup() created them, not because the spec defined '
        r'them. If setup() ever stops calling rust_tasks.setup, the first test fails.'),
    ...para('--', r'The helper functions are small but each encodes a decision.'),
    ...pt('--', r'with_ctx', r'replaces rust_context.get, so a test chooses the stored context (nil means the default, '
        r'all features) without touching the state file in stdpath("state").'),
    ...pt('--', r'capture_picker', r'records the options table the module passes to Snacks.picker. All assertions about '
        r'titles, items and confirm are made on that table.'),
    ...pt('--', r'capture_term', r'records open and get calls. get returns whatever the test says is the existing terminal, '
        r'open returns a fake terminal object with buf_valid and a close that stores its argument. '
        r'That object is what lets a test see which terminals were closed.'),
    ...pt('--', r'fake_metadata', r'answers cargo metadata with a Lua table encoded as JSON and passes every other command to '
        r'the real vim.system. The comment gives the reason: the LSP clients use vim.system too.'),
    ...pt('--', r'item', r'finds the picker row whose text starts with a prefix, and fails with the list of texts if '
        r'none does, so a wrong prefix prints what was there.'),
    ...sec(r'the commands'),
    ...para('--', r'Four commands with a description each. nargs is "0" for three of them and "?" for '
        r'RustNew, because the crate name is optional. The strings are compared in full.'),
    ...sec(r':RustTargets errors'),
    ...para('--', r'Two refusals. Outside a crate (a temp directory with a note.txt, no Cargo.toml above): '
        r'exactly one WARN no Cargo.toml found and no picker. A broken Cargo.toml (the text "this '
        r'is not toml" under [package]): exactly one ERROR whose text starts with cargo metadata '
        r'failed: and contains Cargo.toml, so cargo’s own stderr reaches the user. Both tests check '
        r'that the picker was not opened, with H.is_nil on the captured options.'),
    ...sec(r':RustTargets items'),
    ...code('lua', r'tests/rust-tasks-tools_spec.lua · lines 201-222', r'''
  it("builds run/test/build + samply + flamegraph for a bin, run/build for an example, test, bench, and the lib trio", function()
    local opts = targets_for_all(nil)
    local t = vim.tbl_map(function(i)
      return i.text
    end, opts.items)
    table.sort(t)
    H.eq({
      "bench  bench bn (rtt_all)",
      "build  bin tool (rtt_all)",
      "build  example ex (rtt_all)",
      "build  lib rtt_all (rtt_all)",
      "doc-test  lib rtt_all (rtt_all)",
      "flamegraph  bin tool (rtt_all)",
      "run  bin tool (rtt_all)",
      "run  example ex (rtt_all)",
      "samply  bin tool (rtt_all)",
      "test  bin tool (rtt_all)",
      "test  lib rtt_all (rtt_all)",
      "test  test it (rtt_all)",
    }, t)
    H.eq("text", opts.format)
  end)
'''),
    ...para('--', r'This is the table test of the module. The fixture rtt_all has a lib, a bin named tool, an '
        r'example ex, an integration test it and a bench bn, with features default = [a], a and b. '
        r'Twelve rows are expected, sorted for comparison: bench, three builds, doc-test, '
        r'flamegraph, two runs, three tests, samply. Two of them exist only for bins, samply and '
        r'flamegraph, which are the profiling entries and are not in the ACTIONS table: the module '
        r'adds them before it walks that table.'),
    ...para('--', r'Kinds. proc-macro, rlib, cdylib, staticlib and dylib are all treated as libs, so each of '
        r'the five produces exactly three rows (test, doc-test, build) with --lib or --doc and no '
        r'name. The test feeds fake metadata with five targets and asserts all fifteen command '
        r'lines. The second test asserts the selector flags of the default context: -p rtt_all, '
        r'--bin tool, and --all-features at the end.'),
    ...para('--', r'A stored context. With all = false, no_default = true, features = { "b" } and a target, '
        r'every command gets --no-default-features, --features b, --target x86_64-unknown-linux-gnu '
        r'in that order. The lib rows keep --lib and --doc.'),
    ...sec(r'the profiling rows'),
    ...code('lua', r'tests/rust-tasks-tools_spec.lua · lines 270-282', r'''
  it("the samply item builds with the profiling profile, then records the binary (shellescaped)", function()
    H.need_posix("the samply item is `sh -c` on POSIX and a cmd.exe line on Windows")
    local opts, dir = targets_for_all(nil)
    local meta = vim.json.decode(
      vim.system({ "cargo", "metadata", "--format-version", "1", "--no-deps" }, { cwd = dir, text = true }):wait().stdout
    )
    local build = { "cargo", "build", "--profile", "profiling", "-p", "rtt_all", "--bin", "tool", "--all-features" }
    local expected = table.concat(vim.tbl_map(vim.fn.shellescape, build), " ")
      .. " && samply record "
      .. vim.fn.shellescape(meta.target_directory .. "/profiling/tool")
    H.eq({ "sh", "-c", expected }, item(opts, "samply  bin tool (rtt_all)").cmd)
  end)

'''),
    ...para('--', r'samply: build with the profiling profile (the comment in the module says it is release '
        r'plus debug symbols, from ~/.cargo/config.toml), then record the binary. The command is { '
        r'"sh", "-c", line } where every word of the build is passed through shellescape. The '
        r'expected string is built in the test with the same function plus the real '
        r'target_directory read from cargo metadata. The test skips on Windows with the reason that '
        r'the item is sh -c on POSIX and a cmd.exe line there.'),
    ...para('--', r'The next test uses fake metadata with a target directory containing an apostrophe and a '
        r'binary named my bin. The command must still be sh, -c and a line that contains ’my bin’ '
        r'quoted and the quoted samply record path. This is the case where naive string '
        r'concatenation would break, and the one where a path read from cargo’s own output becomes '
        r'shell text.'),
    ...code('lua', r'tests/rust-tasks-tools_spec.lua · lines 302-311', r'''

  it("the flamegraph item replaces --all-features by --features <non-default features, sorted>", function()
    local opts = targets_for_all(nil)
    H.eq(
      { "cargo", "flamegraph", "--profile", "profiling", "-p", "rtt_all", "--bin", "tool", "--features", "a,b" },
      item(opts, "flamegraph").cmd
    )
  end)

  it("the flamegraph item keeps the target flag and leaves a feature-list context alone", function()
'''),
    ...para('--', r'flamegraph. cargo flamegraph has no --all-features, so the module removes it and spells '
        r'out the features of the package: every key of the package’s feature table except default, '
        r'sorted, joined by commas. The fixture gives a,b. A context with all = true and a target '
        r'keeps the target and still gets the feature list; a context with an explicit list of '
        r'features is left alone and yields --features b. A package without features gets no '
        r'--features at all (the test passes vim.empty_dict() so that it encodes as {} and not []).'),
    ...sec(r'the picker and the terminal'),
    ...para('--', r'The title is "Cargo targets - " plus rc.describe(ctx). The default gives all features, '
        r'host target. A stored context gives features: a,b | target: wasm32-unknown-unknown. The '
        r'confirm function closes the picker (one close call), runs the item in a terminal with cwd '
        r'= the workspace root, and does nothing but close when the item is nil. That is a user '
        r'pressing escape.'),
    ...code('lua', r'tests/rust-tasks-tools_spec.lua · lines 396-417', r'''
  it("looks the finished terminal of the same cmd up without creating one", function()
    local term, it, dir = confirm_first(nil)
    H.eq(1, #term.gets)
    H.eq(it.cmd, term.gets[1].cmd)
    H.eq({ cwd = dir, create = false }, term.gets[1].opts)
  end)

  it("a DIFFERENT command closes the previous run's terminal too (no extra split per command)", function()
    local dir = open_all()
    with_ctx(nil)
    local cap = capture_picker()
    local term = capture_term(nil)
    vim.cmd("RustTools")
    cap.opts.confirm({ close = function() end }, cap.opts.items[1])
    cap.opts.confirm({ close = function() end }, cap.opts.items[2])
    H.eq(2, #term.opened)
    H.eq({ buf = true }, term.terms[1].closed, "the first command's terminal was closed")
    H.is_nil(term.terms[2].closed)
    cap.opts.confirm({ close = function() end }, cap.opts.items[3])
    H.eq({ buf = true }, term.terms[2].closed)
    H.eq(dir, term.opened[3].opts.cwd)
  end)
'''),
    ...para('--', r'The group named term goes through :RustTools confirm. A run opens Snacks.terminal at the '
        r'bottom with auto_close = false, which keeps output on the screen after the command exits, '
        r'and with the workspace root as cwd. It first looks up a finished terminal of the same '
        r'command without creating one. A different command closes the previous run’s terminal, so '
        r'repeated runs do not stack splits; the second terminal is not closed until the third '
        r'command runs. An existing terminal for the same command is closed with { buf = true }, '
        r'which wipes its buffer, before the new one opens.'),
    ...para('--', r'In the module the comment says a different command used to open one more split each time, '
        r'because only an identical command was found. The test was added in the same round of '
        r'fixes (98c9bb4, 2026-10-13).'),
    ...sec(r':RustNew'),
    ...para('--', r'Naming and type. With a name, the command asks vim.ui.select for bin or lib with the '
        r'prompt Crate type, and never asks for the name (the stub of vim.ui.input raises if '
        r'called). It runs real cargo new in a temp directory, opens src/main.rs (or src/lib.rs for '
        r'lib), and notifies created <dir>/<name>. These are the only tests that really create '
        r'crates.'),
    ...para('--', r'The refusals. Without a name it asks vim.ui.input with the prompt New crate name: ; an '
        r'empty name and a cancelled input do nothing, and the directory stays empty. A name '
        r'starting with a dash is refused with an ERROR before the type question, because cargo '
        r'would read it as an option; the select stub raises if reached. A cancelled type question '
        r'creates nothing. A name that already exists fails inside cargo and the ERROR carries '
        r'cargo’s message (the test looks for already exists).'),
    ...sec(r':RustTools'),
    ...para('--', r'The nine tools in order. The expected table is written out in full, with the context '
        r'flags (--features a --target ...) on the three build-like entries: timings, both bloat '
        r'entries and the coverage report. The other five have fixed command lines. After the list '
        r'the test confirms the fourth row and checks that machete runs in the workspace root.'),
    ...code('lua', r'tests/rust-tasks-tools_spec.lua · lines 589-604', r'''
  it("deny: check all runs the licence check only when the crate has a deny.toml", function()
    H.need_rust()
    local opts, dir = tools(nil)
    H.eq("deny: check all (no deny.toml: licenses skipped)", opts.items[6].text)
    H.eq({ "cargo", "deny", "check", "advisories", "bans", "sources" }, opts.items[6].cmd)
    unstub_all()
    vim.fn.writefile({ "[licenses]" }, dir .. "/deny.toml")
    with_ctx(nil)
    local cap = capture_picker()
    vim.cmd("RustTools")
    local opts2 = H.ok(cap.opts, "picker was not opened")
    H.eq("deny: check all", opts2.items[6].text)
    H.eq({ "cargo", "deny", "check" }, opts2.items[6].cmd)
    vim.fn.delete(dir .. "/deny.toml")
  end)

'''),
    ...para('--', r'Two cases that came from field tests of the original configuration. Without a deny.toml, '
        r'cargo deny check would fail every dependency on an empty licence allow list, so the '
        r'module runs check advisories bans sources and says so in the row text. With a deny.toml '
        r'the plain check comes back. The test writes the file between two calls and removes it '
        r'afterwards. The second test calls the picker twice and expects identical flags: the '
        r'module copies the command table row before extending it (vim.deepcopy), so flags cannot '
        r'accumulate across calls.'),
    ...sec(r':ActJob'),
    ...code('lua', r'tests/rust-tasks-tools_spec.lua · lines 650-668', r'''
  local function goto_line(pat)
    for i, l in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do
      if l:find(pat, 1, true) then
        vim.api.nvim_win_set_cursor(0, { i, 6 })
        return i
      end
    end
    error("no line with " .. pat)
  end

  it("runs `act -j <job> -W <file>` for the job under the cursor in the git root", function()
    local repo, file = open_workflow()
    local term = capture_term(nil)
    goto_line("runs-on:") -- a key inside job `smoke`
    vim.cmd("ActJob")
    H.eq(1, #term.opened)
    H.eq({ "act", "-j", "smoke", "-W", file }, term.opened[1].cmd)
    H.eq(repo, term.opened[1].opts.cwd)
  end)
'''),
    ...para('--', r':ActJob finds the job under the cursor by walking up the yaml tree to a block mapping '
        r'pair whose grandparent key is jobs. The fixture is an 18-line workflow with a CI name, a '
        r'permissions block, and a job called smoke. The test puts the cursor on runs-on and '
        r'expects { "act", "-j", "smoke", "-W", file } with the cwd set to the repository root, '
        r'which is the directory with .git (the helper runs git init).'),
    ...para('--', r'A cursor on a step deep inside the job finds the same job. A file with two jobs gives the '
        r'right one by line. Outside any git repository the cwd falls back to the current '
        r'directory. On the first line (name: CI) and on the contents: read of the permissions '
        r'block the command warns that the cursor is not inside a job under jobs: and opens '
        r'nothing. start_yaml skips the test if the yaml parser is not installed; CI builds it from '
        r'a pinned commit.'),
    ...sec(r'doctests'),
    ...code('lua', r'tests/rust-tasks-tools_spec.lua · lines 726-738', r'''
describe("rust_tasks.doctests", function()
  it("runs cargo test --doc --workspace + the context flags in the workspace root", function()
    H.need_rust()
    with_ctx({ all = false, features = { "b" } })
    local dir = open_all()
    local term = capture_term(nil)
    tasks.doctests()
    H.eq(1, #term.opened)
    H.eq({ "cargo", "test", "--doc", "--workspace", "--features", "b" }, term.opened[1].cmd)
    H.eq(dir, term.opened[1].opts.cwd)
    H.eq(false, term.opened[1].opts.auto_close)
  end)

'''),
    ...para('--', r'cargo test --doc --workspace plus the context flags, in the workspace root, in a terminal '
        r'that does not auto-close. Defaults to --all-features, and without a crate it warns. The '
        r'comment in the module says why the command exists: neotest with nextest cannot run '
        r'doctests.'),
    ...sec(r'what it does not cover'),
    ...pt('--', r'Snacks itself', r'a real picker or terminal never runs here, so layout, preview and the actual window '
        r'position are not checked. The test checks the arguments handed to Snacks.'),
    ...pt('--', r'tools that are not installed', r'the rows are listed whether or not cargo-deny, cargo-bloat, machete or llvm-cov exist. '
        r'Running a row is not tested, only its command.'),
    ...pt('--', r'Windows samply path', r'the cmd.exe form in samply_cmd is never asserted, the test skips there.'),
    ...sec(r'history'),
    ...pt('--', r'b2fee5c, 2026-10-13', r'xynovim: the suite of 22 feature specs; this one comes with it.'),
    ...pt('--', r'98c9bb4, 2026-10-13', r'the different-command terminal test is added with the fix.'),
    ...pt('--', r'f31e013, 2026-10-14', r'deny: the no-deny.toml row and its test.'),
    ...pt('--', r'25086fd, 2026-10-14', r'RustTools flags: the build-like entries get the context flags (the test title changes '
        r'from only coverage to the builds).'),
    ...pt('--', r'9641d08 and the two Windows and macOS rounds of 2026-10-21', r'portability: realpath temp dirs, and skips with reasons for the failures that were not diagnosed.'),
    ...pt('--', r'7c1d2d9, 2026-10-22', r'this repository: namespace, H.fake_snacks and a real setup() at the top of the file.'),
  ],
);
