import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/tests/dap-neotest-coverage_spec.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'dap-neotest-coverage_spec.lua — debugging, testing and coverage as one spec'),
    cm('--', r'57 tests from file-local helpers to a real codelldb session that stops in rust_panic'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'spec for lua/plugins/dap.lua, rustaceanvim.lua, coverage.lua and the extras in lazyvim.json (dap.core, test.core, editor.overseer)'),
    kv(r'language', r'Lua spec, 1440 lines, 57 it() blocks, 6 pending, 14 describe() blocks'),
    kv(r'real parts', r'one codelldb session at the end, skipped without codelldb; one llvm-cov run is in rust-tasks-tools_spec'),
    kv(r'history', r'8 commits, 2026-10-13 to 2026-10-21'),
    ...sec(r'why this file exists'),
    ...para('--', r'Debugging Rust is where a lot of tools meet: nvim-dap, the codelldb adapter that Mason installs, rustaceanvim debuggables, neotest with nextest, overseer for tasks, and a coverage tool. Every connection point can break without a message. This spec sets out what has to hold, in layers: what the plugin spec declares, what the pure helpers do given temp Cargo crates, what the user keys do with stubbed prompts, and finally a real debug session that has to stop where it should.'),
    ...code('lua', r'tests/dap-neotest-coverage_spec.lua · lines 1-12', r'''
-- lua/plugins/dap.lua, lua/plugins/rustaceanvim.lua, lua/plugins/coverage.lua,
-- lazyvim.json (dap.core, test.core, editor.overseer extras).
--
-- The helpers of dap.lua are file-local, so they are reached through what the
-- plugin spec exposes: the mason-nvim-dap `codelldb` handler (it installs
-- dap.configurations.rust and the on_config listener), the <leader>dR key
-- function and the dap-ui opts. `fresh()` loads a private copy of the spec file
-- (own closures, own sysroot cache); the lazy-registered one is used where the
-- wiring itself is under test. Cargo crates are written into temp dirs at run
-- time; the interactive prompts (vim.fn.input, vim.ui.select) are stubbed.
-- One real codelldb session runs at the end (skipped without codelldb).
local H = require("xynotest.helpers")'''),
    ...sec(r'reaching file-local functions'),
    ...para('--', r'dap.lua keeps its helpers local. A spec must not change that for testability, so the header explains the trick: reach the helpers through what the plugin spec exposes, namely the mason-nvim-dap codelldb handler (it installs dap.configurations.rust and the on_config listener), the leader d R key function and the dap-ui opts. fresh() loads a private copy of the spec file so each test has its own closures and its own sysroot cache. The tests use the lazy-registered one where the wiring itself is under test.'),
    ...sec(r'exactly three configurations'),
    ...para('--', r'The handler test starts with a stale entry in dap.configurations.rust, calls the real handler, and requires exactly three: LLDB: Launch, LLDB: Launch (args) and Rust: run current package binary (args prompt). Each is type codelldb, request launch, sourceLanguages rust, stopOnEntry false and console integratedTerminal. It also requires that the default adapter was registered and that the on_config listener exists. A neighbouring test makes sure the Rust list does not leak into c and cpp.'),
    ...code('lua', r'tests/dap-neotest-coverage_spec.lua · lines 127-148', r'''
  it("replaces dap.configurations.rust with exactly the three Rust configs (lazy-registered handler)", function()
    dap_available()
    local p = require("lazy.core.config").plugins["mason-nvim-dap.nvim"]
    H.ok(p and type(p.opts.handlers.codelldb) == "function", "mason-nvim-dap opts.handlers.codelldb")
    local dap = require("dap")
    dap.configurations.rust = { { name = "stale" } }
    p.opts.handlers.codelldb(codelldb_cfg())
    local cfgs = dap.configurations.rust
    H.eq(3, #cfgs)
    H.eq({ "LLDB: Launch", "LLDB: Launch (args)", "Rust: run current package binary (args prompt)" }, vim.tbl_map(function(c)
      return c.name
    end, cfgs))
    for _, c in ipairs(cfgs) do
      H.eq("codelldb", c.type)
      H.eq("launch", c.request)
      H.eq({ "rust" }, c.sourceLanguages)
      H.eq(false, c.stopOnEntry)
      H.eq("integratedTerminal", c.console)
    end
    H.ok(dap.adapters.codelldb, "default_setup registered the codelldb adapter")
    H.ok(dap.listeners.on_config["xynovim_rust_lldb"], "on_config listener installed")
  end)'''),
    ...sec(r'the third configuration builds first'),
    ...para('--', r'Config 3 runs the binary of the package that owns the current file. Its program function runs cargo build, which can take a long time, and the test splits two cases: outside a coroutine it blocks; inside a coroutine (how nvim-dap calls it) it must yield, so the UI is not frozen, and resume later with the path. The test runs program() in a coroutine, requires that it is suspended after the first resume and not finished, waits up to 60 seconds, and then compares the result with the target directory of cargo metadata plus debug/copkg and the Windows suffix, and checks that the file exists.'),
    ...code('lua', r'tests/dap-neotest-coverage_spec.lua · lines 222-243', r'''
  it("config 3: inside a coroutine the build yields (UI not blocked) and resumes with the path", function()
    dap_available()
    local dir = bin_crate("copkg")
    edit(dir .. "/src/main.rs")
    local _, cfgs = fresh_setup()
    local c = by_name(cfgs, "Rust: run current package binary (args prompt)")
    capture()
    local result, finished
    local co = coroutine.create(function()
      result = c.program()
      finished = true
    end)
    local ok, err = coroutine.resume(co)
    H.ok(ok, tostring(err))
    H.not_ok(finished, "program() yielded instead of blocking")
    H.eq("suspended", coroutine.status(co))
    H.wait_for(function()
      return finished
    end, 60000, "the coroutine build to finish")
    H.eq(cargo_meta(dir).target_directory .. "/debug/copkg" .. EXE, result)
    H.ok(vim.uv.fs_stat(result))
  end)'''),
    ...sec(r'choosing the binary'),
    ...para('--', r'current_binary is tested through observable effects: the default program of config 1 and the working directory of config 3. The rules: the package containing the buffer file; a bin named like the package wins; a package without a bin is skipped; the longest directory match wins for nested packages; with no file, the workspace root package or the first package with a bin; and a fallback when there is none. The case in the excerpt makes a lib-only package open and expects the first package that has a bin, a, with that package as the working directory.'),
    ...code('lua', r'tests/dap-neotest-coverage_spec.lua · lines 302-310', r'''
  it("a package without a bin is skipped: the file's own package is not chosen, the first package with a bin is", function()
    dap_available()
    local dir = workspace()
    local target = cargo_meta(dir).target_directory
    local _, cfgs = fresh_setup()
    edit(dir .. "/libonly/src/lib.rs")
    H.eq(target .. "/debug/a" .. EXE, default_for(cfgs))
    H.eq(dir .. "/a", cwd_of(cfgs))
  end)'''),
    ...sec(r'failures are visible'),
    ...para('--', r'No package with a bin gives an ERROR notification and dap.ABORT; a failing cargo build gives cargo build failed: with stderr and ABORT; an invalid Cargo.toml gives no binary and no error; cargo exiting 0 with invalid JSON gives nil, not an error. A failure to find the binary is never turned into running something else.'),
    ...sec(r'the pretty printers'),
    ...para('--', r'Rust values in lldb are unreadable without the helper script that ships with the toolchain. The config finds it through rustc --print sysroot and adds a command script import to the initCommands of every Rust codelldb config, with a breakpoint on rust_panic last. The tests say what must be: the sysroot lookup is cached (once across calls), a failing rustc or a toolchain without lldb_lookup.py is cached as missing, and the listener adds exactly those two commands, keeps existing initCommands with the import first, does not duplicate an import that is already present, is idempotent, leaves other adapters and languages alone and is registered under xynovim_rust_lldb.'),
    ...code('lua', r'tests/dap-neotest-coverage_spec.lua · lines 511-547', r'''
  it("adds the lldb_lookup.py import first and the rust_panic breakpoint last, nothing else", function()
    dap_available()
    local script = sysroot_script()
    if not vim.uv.fs_stat(script) then
      H.skip_file("this toolchain ships no lldb_lookup.py")
    end
    local _, _, listener = fresh_setup()
    local out = listener(rust())
    H.eq({ 'command script import "' .. script .. '"', "breakpoint set -n rust_panic" }, out.initCommands)
    for _, c in ipairs(out.initCommands) do
      H.no_match(c, "lldb_commands", true)
    end
  end)

  it("keeps existing initCommands (import inserted at position 1, panic breakpoint appended)", function()
    dap_available()
    local script = sysroot_script()
    if not vim.uv.fs_stat(script) then
      H.skip_file("this toolchain ships no lldb_lookup.py")
    end
    local _, _, listener = fresh_setup()
    local out = listener(rust({ initCommands = { "settings set x y", "log enable lldb all" } }))
    H.eq({
      'command script import "' .. script .. '"',
      "settings set x y",
      "log enable lldb all",
      "breakpoint set -n rust_panic",
    }, out.initCommands)
  end)

  it("does not add the import when an initCommand already mentions lldb_lookup.py", function()
    dap_available()
    local _, _, listener = fresh_setup()
    local mine = 'command script import "/somewhere/lldb_lookup.py"'
    local out = listener(rust({ initCommands = { mine } }))
    H.eq({ mine, "breakpoint set -n rust_panic" }, out.initCommands)
  end)'''),
    ...sec(r'dap-ui and keys'),
    ...para('--', r'The dap-ui tests state the layout: wrap on, sidebar elements and sizes, a bottom panel, and the sidebar width formula max(40, min(60, floor(columns * 0.35))). The UI stays open when the session terminates, because the output would otherwise live only in the hidden dap-terminal. The leader d R key lists bins and examples of all packages plus the current file runnables, merged and deduped, starts rustaceanvim.dap.start, and a test checks that the rustaceanvim internals it uses exist in the locked version. Pausing: codelldb fills the thread list only on a stop, so a running session with no known threads asks for them and pauses the first.'),
    ...code('lua', r'tests/dap-neotest-coverage_spec.lua · lines 870-891', r'''
  it("a running session with no known threads asks for them and pauses the first (codelldb fills them only on a stop)", function()
    local dap = require("dap")
    local pauses, reqs = {}, {}
    local orig_pause, orig_session = dap.pause, dap.session
    dap.pause = function(...)
      pauses[#pauses + 1] = { ... }
    end
    dap.session = function()
      return {
        threads = {},
        request = function(_, cmd, _, cb)
          reqs[#reqs + 1] = cmd
          cb(nil, { threads = { { id = 7, name = "main" } } })
        end,
      }
    end
    local ok, err = pcall(key_fn())
    dap.pause, dap.session = orig_pause, orig_session
    H.ok(ok, tostring(err))
    H.eq({ "threads" }, reqs)
    H.eq({ { 7 } }, pauses)
  end)'''),
    ...sec(r'neotest, overseer and coverage'),
    ...para('--', r'lazyvim.json must enable the extras; neotest must use the rustaceanvim adapter, nextest is used when installed, and the leader t D key runs cargo test --doc --workspace in a terminal, because neotest with nextest cannot see doctests (a test verifies this and checks that the README documents the key). Coverage honours :RustContext: the default context passes --all-features, a stored context passes its features, default switch and target through, and the :RustTools coverage entry carries the same flags.'),
    ...sec(r'the real session'),
    ...para('--', r'The last block starts codelldb for real against a crate built into a temp dir. It checks that config 1 with the program prompt answered by the built binary and config 3 both stop in rust_panic with the locals of the check frame, that a breakpoint in main stops with its locals and then continues into rust_panic, and that both leader d R and leader d r stop in rust_panic with the same locals.'),
    ...code('lua', r'tests/dap-neotest-coverage_spec.lua · lines 1301-1322', r'''
  it("configs 1 and 3 stop in rust_panic with the locals of the check frame", function()
    need()
    local s0 = session()
    vim.cmd("only")
    local _, cfgs = (function()
      local p = require("lazy.core.config").plugins["mason-nvim-dap.nvim"]
      p.opts.handlers.codelldb(codelldb_cfg())
      return nil, require("dap").configurations.rust
    end)()
    local dap = require("dap")
    -- config 1: program prompt answered with the built binary
    stub_input(s0.bin)
    dap.run(vim.deepcopy(by_name(cfgs, "LLDB: Launch")))
    assert_panic_stop(stopped())
    release()
    -- config 3: builds the current package, args prompt answered empty
    stub_input("")
    capture()
    dap.run(vim.deepcopy(by_name(cfgs, "Rust: run current package binary (args prompt)")))
    assert_panic_stop(stopped())
    release()
  end)'''),
    ...sec(r'what is not tested, said out loud'),
    ...para('--', r'Six pending entries close the file with a reason each: interactive prompts with a real terminal, multi-bin workspaces in a real debug session, narrow terminals, clicking a Debug codelens, threads that panic, and lldb-dap as the adapter. Three of them say README: untested. A list of known gaps in the test file itself is more useful than a promise of full coverage.'),
    ...sec(r'history'),
    blank,
    ...pt('--', r'b2fee5c (2026-10-13)', r'created.'),
    ...pt('--', r'98c9bb4, 3f868dd, 25086fd (2026-10-13 and 2026-10-14)', r'field test fixes (dap-ui console and breakpoint signs, dP pause).'),
    ...pt('--', r'fc2062a (2026-10-14)', r'CI on a clean machine.'),
    ...pt('--', r'6524272, cd602fd (2026-10-21)', r'Windows and macOS runs: the .exe suffix and drive letter case, which is why EXE appears at the top.'),
  ],
);
