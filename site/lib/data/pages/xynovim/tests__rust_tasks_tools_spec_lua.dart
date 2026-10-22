import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/tests/rust-tasks-tools_spec.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'rust-tasks-tools_spec.lua — what would run, checked as a command line'),
    cm('--', r'pickers and terminals stubbed so the spec reads the argv, plus an lcov coverage backend that places real signs'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'spec for lua/config/rust_tasks.lua (:RustTargets, :RustTools, :ActJob, :RustNew, doctests) and lua/plugins/coverage.lua'),
    kv(r'language', r'Lua spec, 1124 lines, 51 it() blocks, 1 pending, 13 describe() blocks'),
    kv(r'method', r'Snacks.picker, Snacks.terminal, vim.ui and vim.system are stubbed where the spec needs only to see what would run; real cargo for metadata and cargo new; one end-to-end coverage run'),
    kv(r'history', r'7 commits, 2026-10-13 to 2026-10-21'),
    ...sec(r'why this file exists'),
    ...para('--', r'The Rust task layer is made of commands that put a command line in a terminal: run this binary, test this package, profile with samply, record coverage. A command line built from a context (workspace features, target, profile) is a function from inputs to strings, and that is the contract worth testing. The header says what is stubbed and what is real, and the stubs are chosen so the spec can read the argv.'),
    ...code('lua', r'tests/rust-tasks-tools_spec.lua · lines 1-6', r'''
-- config.rust_tasks (:RustTargets, :RustTools, :ActJob, :RustNew, doctests) and
-- lua/plugins/coverage.lua (<leader>tc, nvim-coverage opts, lcov backend).
-- Snacks.picker / Snacks.terminal / vim.ui / vim.system are stubbed where the
-- spec only needs to see what would run; real cargo is used for metadata,
-- `cargo new` and the one end-to-end coverage run.
local H = require("xynotest.helpers")'''),
    ...sec(r'the target list as data'),
    ...para('--', r':RustTargets lists what cargo metadata says. For a package with a bin, an example, an integration test, a benchmark and a library, the test builds a fixture and compares the sorted list of item texts with an exact list of twelve strings: bench, build for bin, example and lib, doc-test for the lib, flamegraph and samply for the bin, run for bin and example, test for bin, lib and the integration test. Proc-macro, rlib, cdylib, staticlib and dylib targets count as libs. The command of each item selects package and target by name, appends --all-features for the default context, and a stored context appends its flags and target.'),
    ...code('lua', r'tests/rust-tasks-tools_spec.lua · lines 200-221', r'''
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
  end)'''),
    ...sec(r'profiling items'),
    ...para('--', r'The samply item builds with the profiling profile and then records the binary. Because the argument could contain odd characters, the whole line is made of shell-escaped words joined with &&, wrapped in sh -c. The test builds the expected string itself, with the target directory from cargo metadata, and compares the command table. It is skipped on Windows, where the item is a cmd.exe line instead. A separate test uses odd directory names and checks the shell escaping. The flamegraph item replaces --all-features with --features followed by the sorted non-default features, keeps a target flag, leaves a feature-list context alone, and adds no features argument for a package without any.'),
    ...code('lua', r'tests/rust-tasks-tools_spec.lua · lines 269-280, 302-308', r'''
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
...
  it("the flamegraph item replaces --all-features by --features <non-default features, sorted>", function()
    local opts = targets_for_all(nil)
    H.eq(
      { "cargo", "flamegraph", "--profile", "profiling", "-p", "rtt_all", "--bin", "tool", "--features", "a,b" },
      item(opts, "flamegraph").cmd
    )
  end)'''),
    ...sec(r'the terminal'),
    ...para('--', r'Confirming an item closes the picker and runs the command in a bottom terminal at the workspace root. The terminal keeps open after exit, a finished terminal of the same command is looked up without creating a new one, and a different command closes the previous run terminal so there is no extra split per command, and an existing terminal is closed and its buffer wiped before reopening.'),
    ...sec(r':RustNew and :ActJob'),
    ...para('--', r':RustNew with a name asks the crate type, creates a bin crate, or a lib with --lib that opens src/lib.rs; without a name it asks New crate name:; an empty or cancelled input does nothing; a name starting with a dash is refused because cargo would take it as an option; a cancelled type question creates nothing; and a failure shows the first stderr as an ERROR. (The newer :RustNewBin family is tested in rust-new_spec.lua.) :ActJob runs act -j <job> -W <file> for the job under the cursor in the git root, also when the cursor is on a step deep inside the job, picks the right job in a file with several, uses the cwd as the root without a .git, and warns outside jobs:.'),
    ...sec(r':RustTools'),
    ...para('--', r'The tools list has nine entries with their commands. The builds (timings, bloat, coverage) get the context flags. deny check all runs the licence check only when the crate has a deny.toml. Repeated calls do not accumulate flags on the coverage entry, and outside a crate it warns.'),
    ...sec(r'the coverage run'),
    ...para('--', r'The leader t c function runs cargo llvm-cov with nextest, the workspace, --ignore-run-fail, and lcov output to target/lcov.info, then the context flags. The test sets a context with features a and a target, opens the workspace, replaces vim.system by a recorder, and requires the exact argument list, the workspace root as cwd, text mode, and the first notification coverage: running followed by the command. Without nextest the word nextest is left out. On exit 0 the coverage is loaded and shown, and says where it came from; failing tests (nextest and cargo test wording) give a warning that the report is still written, while loading and showing still happen; zero failed gives no warning; and a non-zero exit is an ERROR with the last 600 characters of stderr and loads nothing. The macOS run known issue is recorded with the run number.'),
    ...code('lua', r'tests/rust-tasks-tools_spec.lua · lines 813-829', r'''
  it("runs cargo llvm-cov nextest with the lcov output + context flags in the workspace root", function()
    H.need_rust()
    local fn = tc()
    with_ctx({ all = false, features = { "a" }, target = "x86_64-unknown-linux-gnu" })
    local dir = open_all()
    local n = H.capture_notify()
    local cap = harness(true)
    fn()
    local expected = {
      "cargo", "llvm-cov", "nextest", "--workspace", "--ignore-run-fail", "--lcov", "--output-path", "target/lcov.info",
      "--features", "a", "--target", "x86_64-unknown-linux-gnu",
    }
    H.eq(expected, cap.sys.cmd)
    H.eq(dir, cap.sys.opts.cwd)
    H.eq(true, cap.sys.opts.text)
    H.eq("coverage: running " .. table.concat(expected, " "), n.list[1].msg)
  end)'''),
    ...sec(r'the lcov backend'),
    ...para('--', r'The plugin replaces nvim-coverage grcov-based Rust backend by lcov. The tests state: coverage_file is target/lcov.info in the root; a missing file is an INFO hint, not an error; and a test writes an lcov file for a fixture, loads it with :Coverage, and requires four signs on lines 1, 2, 3 and 9, all named coverage_covered. CoverageSummary must show a float containing Total and 100% with the path shortened to fit. Missed lines are marked uncovered. The plugin is lazy on the seven Coverage commands and the three keys.'),
    ...code('lua', r'tests/rust-tasks-tools_spec.lua · lines 1022-1054', r'''
  it("loads target/lcov.info: signs are placed on the covered lines and CoverageSummary shows 100%", function()
    load_plugin()
    local dir = H.fixture("rust-tasks-tools-cov")
    vim.cmd.cd(vim.fn.fnameescape(dir))
    local buf = H.open(dir .. "/src/lib.rs")
    write_lcov(dir, { { 1, 1 }, { 2, 1 }, { 3, 1 }, { 9, 1 } })
    vim.cmd("Coverage") -- load + place
    local s = placed(buf)
    H.eq(4, #s)
    local lines = vim.tbl_map(function(x)
      return x.lnum
    end, s)
    table.sort(lines)
    H.eq({ 1, 2, 3, 9 }, lines)
    for _, x in ipairs(s) do
      H.eq("coverage_covered", x.name)
    end
    vim.cmd("CoverageSummary")
    local text
    H.wait_for(function()
      for _, w in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_get_config(w).relative ~= "" then
          local t = table.concat(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(w), 0, -1, false), "\n")
          if t:find("Total", 1, true) then
            text = t
            return true
          end
        end
      end
    end, 5000, "the summary float")
    H.match(text, "100%%")
    H.match(text, "lib.rs", true) -- the path is shortened to fit the column
  end)'''),
    ...sec(r'one real run'),
    ...para('--', r'The end-to-end test runs cargo llvm-cov for real, writes target/lcov.info and places the signs; it is optional and slow. The last block has one pending entry: the profiling profile lives in ~/.cargo/config.toml, outside the repository, and the samply and flamegraph items only pass --profile profiling.'),
    ...sec(r'history'),
    blank,
    ...pt('--', r'b2fee5c (2026-10-13)', r'created. 98c9bb4 (2026-10-13), f31e013, 25086fd (2026-10-14) :: field test rounds.'),
    ...pt('--', r'9641d08 (2026-10-16)', r'Windows drive letters. d3e1442, 7715eb8 (2026-10-21) :: path spelling and the reduction of the Windows and macOS suites.'),
  ],
);
