import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-rust.nvim/tests/server-supervision-statusline_spec.lua',
  lines: [
    cm('--', r'──────────────────────────────────────────'),
    cm('--', r'tests/server-supervision-statusline_spec.lua — a language server dies, and the editor must notice'),
    cm('--', r'restart after a crash, a loop guard, sweeping dead workspaces, FocusGained refresh, the status text'),
    cm('--', r'──────────────────────────────────────────'),
    blank,
    kv(r'role', r'spec for lua/xyno_rust/rust_restart.lua (486 lines) and lua/xyno_rust/lsp_status.lua (344 lines)'),
    kv(r'language', r'Lua, run by tests/run.lua'),
    kv(r'size', r'1122 lines, 45 tests in 5 groups'),
    kv(r'platform', r'linux only (the header line xyno-os: linux, POSIX signals and /proc on server processes)'),
    kv(r'real', r'git (init, commit, checkout), temp directories, real autocmds and buffers'),
    kv(r'faked', r'every LSP client, vim.lsp.get_clients, vim.cmd, vim.lsp.enable, vim.notify, vim.uv.kill, '
        r'rustaceanvim.lsp'),
    kv(r'origin', r'the first half of xynovim tests/server-supervision-statusline_spec.lua (1470 lines there)'),
    ...sec(r'why this file exists'),
    ...para('--', r'Two servers analyse Rust in the background, rust-analyzer and bacon-ls, and both can '
        r'disappear without a word: killed by the system out of memory, crashed, left pointing at a '
        r'directory that was moved. A statusline that keeps saying clippy ok for a dead server is '
        r'worse than none. rust_restart.lua keeps them alive and fresh and lsp_status.lua says what '
        r'state they are in. The header comment of rust_restart.lua lists what it promises: a '
        r'server that dies is restarted at most three times a minute and shows as RA stopped or '
        r'clippy stopped until it is back; :RustRestart restarts both by hand; bacon-ls is '
        r'restarted when files changed under it from outside the editor, when git HEAD moved, when '
        r'Cargo.toml or Cargo.lock was saved, or when its directory vanished; and uninitialised '
        r'servers are killed at quit.'),
    ...para('--', r'Every sentence of that promise involves time, processes or the file system, which is the '
        r'worst material for tests. The spec solves it by never running a language server at all. A '
        r'fake client is a Lua table with an id, a name, a root, attached buffers and a stop '
        r'function, and install_stubs replaces the places where the modules look for clients. '
        r'Everything below runs in milliseconds, apart from the waits that mirror the module’s own '
        r'500 ms delay, and the result does not depend on rust-analyzer or bacon-ls being installed.'),
    ...sec(r'what is missing, and the README says so'),
    ...para('--', r'The original spec in xynovim had a sixth group, live servers, that started real '
        r'rust-analyzer and bacon-ls processes and killed them: kill -9 of both, SIGSTOP-ed hung '
        r'servers, repeated quick kills, FocusGained restarts. It is the last 320 lines of the '
        r'1470. This repository does not carry it. The commit that records the decision is dbb2c0e '
        r'(2026-10-22, Document the supervision cases that were not ported), and the README says '
        r'the restart and sweep logic has no real-process spec here. The header of this file says '
        r'the same in three lines. Read this page with that in mind: it checks every decision the '
        r'code makes, and none of the real system calls it makes.'),
    ...sec(r'the preamble'),
    ...code('lua', r'tests/server-supervision-statusline_spec.lua · lines 7-17', r'''
local H = require("xyno_rust_test.helpers")

-- (the original config called this at startup)
require("xyno_rust.lsp_status").setup()

local RR_GROUP, LS_GROUP = "xyno_rust_restart", "xyno_rust_lsp_status"

local function fresh_restart()
  package.loaded["xyno_rust.rust_restart"] = nil
  local rr = require("xyno_rust.rust_restart")
  rr.setup()
'''),
    ...para('--', r'The version gate in the header is xyno-os: linux. tests/run.lua reads the first fifteen '
        r'lines of every spec for it and prints SKIP with the reason on any other system, so the '
        r'file does not run on Windows or macOS. The README says the same about xynovim’s CI.'),
    ...para('--', r'fresh_restart reloads the module by clearing package.loaded and calling setup again. The '
        r'module keeps state in upvalues (the restart times per server, the remembered git HEADs '
        r'and manifest stamps), so a clean module per test is how the tests stay independent.'),
    ...code('lua', r'tests/server-supervision-statusline_spec.lua · lines 20-48', r'''

-- ------------------------------------------------------------------ stubs

--- Replaces vim.lsp.get_clients / get_client_by_id (fake clients only, for
--- the names the fakes use), vim.cmd (records and swallows `lsp restart` and
--- RustAnalyzer), vim.lsp.enable, vim.notify and rustaceanvim.lsp.start.
local stub
local function install_stubs()
  local s = {
    fakes = {},
    cmds = {},
    redraws = 0,
    notes = {},
    enabled = {},
    disabled = {},
    ra_starts = {},
    ra_cmds = {},
  }
  local o = {
    get_clients = vim.lsp.get_clients,
    get_client_by_id = vim.lsp.get_client_by_id,
    cmd = vim.cmd,
    enable = vim.lsp.enable,
    notify = vim.notify,
    ra = package.loaded["rustaceanvim.lsp"],
  }
  vim.lsp.get_clients = function(f)
    f = f or {}
    local out = {}
'''),
    ...para('--', r'install_stubs is the heart of the spec. It builds one table of recordings and replaces, '
        r'in this order: vim.lsp.get_clients and get_client_by_id (answering only from the fake '
        r'clients, with the real filters name and bufnr), vim.cmd (recording every string and '
        r'swallowing lsp restart and RustAnalyzer), vim.lsp.enable, vim.notify, and '
        r'package.loaded["rustaceanvim.lsp"]. restore puts the originals back. Counting redraws is '
        r'done with debug.getinfo inside the stub of vim.cmd.redrawstatus: only calls that come '
        r'from lsp_status.lua or rust_restart.lua count, so a redraw caused by Neovim itself does '
        r'not pollute the number.'),
    ...para('--', r'A fake client also repairs its own world: a bacon_ls fake whose root exists but has no '
        r'Cargo.toml gets one written, because sweep treats a root without a manifest as gone and '
        r'the test of a living client would otherwise be killed by the very logic under test.'),
    ...sec(r'setup and on_exit'),
    ...para('--', r'The command and the events. The group must hold exactly BufWritePost, '
        r'FileChangedShellPost, FocusGained, LspAttach, User and VimLeavePre. Comparing the whole '
        r'set with H.eq fails on an added event as well as a missing one.'),
    ...code('lua', r'tests/server-supervision-statusline_spec.lua · lines 224-256', r'''
  it("a clean exit (code 0, signal 0) does nothing", function()
    local b = scratch_buf()
    local c = fake_client(s, { name = "bacon_ls", bufs = { b } })
    require("xyno_rust.rust_restart").on_exit("bacon_ls")(0, 0, c.id)
    vim.wait(800, function()
      return false
    end, 50)
    H.eq({}, s.notes)
    H.eq({}, s.enabled)
    H.eq(0, s.redraws)
    H.is_nil(vim.b[b].xyno_rust_stopped)
  end)

  it("an abnormal exit flags the buffers, redraws, warns and restarts bacon_ls after 500 ms", function()
    local b = scratch_buf()
    local c = fake_client(s, { name = "bacon_ls", bufs = { b } })
    local t0 = vim.uv.hrtime()
    require("xyno_rust.rust_restart").on_exit("bacon_ls")(101, 0, c.id)
    H.wait_for(function()
      return vim.b[b].xyno_rust_stopped
    end, 2000, "stopped flag")
    H.eq({ bacon_ls = true }, vim.b[b].xyno_rust_stopped)
    H.ok(s.redraws >= 1, "statusline redrawn")
    H.eq({ { msg = "bacon_ls exited (code 101, signal 0); restarting", level = vim.log.levels.WARN } }, s.notes)
    H.eq({}, s.enabled, "not restarted yet")
    H.wait_for(function()
      return #s.enabled > 0
    end, 3000, "vim.lsp.enable('bacon_ls')")
    H.eq({ "bacon_ls" }, s.enabled)
    local ms = (vim.uv.hrtime() - t0) / 1e6
    H.ok(ms >= 450, "restart is delayed by ~500 ms, was " .. ms)
  end)

'''),
    ...para('--', r'The core test: a clean exit (code 0, signal 0) does nothing at all, no flag, no note, no '
        r'enable, no redraw, after waiting 800 ms to be sure nothing is scheduled. An abnormal exit '
        r'(code 101) flags the buffer with xyno_rust_stopped = { bacon_ls = true }, redraws the '
        r'statusline, warns with the exact text bacon_ls exited (code 101, signal 0); restarting, '
        r'and calls vim.lsp.enable only about half a second later; the test checks the elapsed time '
        r'is at least 450 ms. The delay exists because the module comment says the dead client is '
        r'only dropped from the client list a tick later.'),
    ...code('lua', r'lua/xyno_rust/rust_restart.lua · lines 80-102', r'''
      end
      vim.cmd.redrawstatus()
      if vim.v.exiting ~= vim.NIL then
        return
      end
      local now = os.time()
      starts[name] = vim.tbl_filter(function(t)
        return now - t < 60
      end, starts[name] or {})
      if #starts[name] >= 3 then
        return vim.notify(
          ("%s keeps exiting (code %s, signal %s); giving up. :RustRestart tries again."):format(name, code, signal),
          vim.log.levels.ERROR
        )
      end
      table.insert(starts[name], now)
      vim.notify(("%s exited (code %s, signal %s); restarting"):format(name, code, signal), vim.log.levels.WARN)
      -- the dead client is only dropped from the client list a tick later
      vim.defer_fn(function()
        start(name, bufs)
      end, 500)
    end)
  end
'''),
    ...para('--', r'Here is the code the last test pins. The loop guard is a list of timestamps per server '
        r'name, filtered to the last 60 seconds. Three entries mean give up: an ERROR that says the '
        r'server keeps exiting and that :RustRestart tries again. Otherwise the time is recorded, '
        r'the warning is shown and the restart is deferred 500 ms.'),
    ...para('--', r'Three further tests. A rust-analyzer exit restarts through rustaceanvim only for buffers '
        r'that lack a client by the time the restart runs, so a buffer whose replacement client '
        r'came back in between is not started twice. A signalled exit (code 0, signal 15) counts as '
        r'abnormal. And the guard: four exits in a row give three WARN notes and then the ERROR '
        r'with the exact text, only three enable calls, and the status stays clippy stopped once '
        r'the dead client is removed.'),
    ...para('--', r'The guard is per server name. Four bacon_ls exits exhaust it, and a rust-analyzer exit '
        r'right after still gets a warning and a restart. Without the per-name table a flapping '
        r'clippy server would stop rust-analyzer from being revived.'),
    ...sec(r'sweep and :RustRestart'),
    ...para('--', r'sweep stops bacon_ls clients whose root_dir is gone, and also those whose root lost only '
        r'its Cargo.toml. The comment of the second test gives the symptom: the status stayed '
        r'clippy ok for a project that had been moved away. The stop is forced (stopped is true) '
        r'and the live client is left alone.'),
    ...para('--', r'A save sweeps too, through BufWritePost and through the User event AutoSaveWritePost of '
        r'the auto-save plugin, so a moved project is noticed without waiting for FocusGained. The '
        r'loop runs the same assertions for both triggers.'),
    ...code('lua', r'tests/server-supervision-statusline_spec.lua · lines 380-398', r'''
  it("a save restarts bacon-ls once target/bacon-ls-live was recreated (cargo clean: clippy stayed 'ok' and blind)", function()
    local d = H.tmpdir()
    fake_client(s, { name = "bacon_ls", root = d })
    vim.fn.mkdir(d .. "/target/bacon-ls-live/shadow", "p")
    local save = function()
      vim.api.nvim_exec_autocmds("BufWritePost", { modeline = false })
    end
    save()
    save()
    H.eq(0, has_cmd(s, "lsp restart bacon_ls"), "same directory: nothing to do")
    vim.fn.delete(d .. "/target", "rf")
    save()
    H.eq(0, has_cmd(s, "lsp restart bacon_ls"), "gone and not yet recreated: nothing to compare")
    vim.fn.mkdir(d .. "/target/bacon-ls-live/shadow", "p")
    save()
    H.eq(1, has_cmd(s, "lsp restart bacon_ls"), "recreated: restart")
    save()
    H.eq(1, has_cmd(s, "lsp restart bacon_ls"), "once")
  end)
'''),
    ...para('--', r'A cargo clean deletes target and, with it, the directory bacon-ls keeps its shadow '
        r'workspace in; clippy then looks fine and sees nothing. The module notes the identity of '
        r'target/bacon-ls-live and restarts bacon-ls once after a save when it was recreated. The '
        r'test steps through four states and counts lsp restart bacon_ls calls: the same directory '
        r'twice gives none, deleted and not yet recreated gives none (nothing to compare), '
        r'recreated gives one, and a further save still one.'),
    ...para('--', r'Cargo.lock has a more subtle rule. A lock rewritten by cargo is cargo’s business, so no '
        r'restart while clippy is fine. Only when clippy has failed does a repaired or deleted lock '
        r'restart bacon-ls. The test replaces lsp_status.bacon_failed with a function that checks '
        r'the id and returns a variable, and restores it after the pcall so a failure cannot leak '
        r'the stub.'),
    ...para('--', r'A client stopped by sweep exits with SIGTERM, and that is not a crash. The module '
        r'remembers swept client ids and ignores their exit; the test checks there is no exited '
        r'warning and no restart.'),
    ...sec(r'kill at quit'),
    ...code('lua', r'tests/server-supervision-statusline_spec.lua · lines 507-534', r'''
  it("stops the uninitialised clients and SIGKILLs this nvim's server children of that name; initialised ones are left", function()
    local rr = require("xyno_rust.rust_restart")
    local killed = {}
    local orig_kill, orig_pids = vim.uv.kill, rr.server_pids
    vim.uv.kill = function(pid, sig)
      killed[#killed + 1] = { pid, sig }
      return 0
    end
    rr.server_pids = function()
      return { [111] = "rust-analyzer", [222] = "bacon-ls" }
    end
    local ra = fake_client(s, { name = "rust-analyzer" })
    local bc = fake_client(s, { name = "bacon_ls", root = H.tmpdir() })
    ra.initialized = false
    bc.initialized = true
    local ok, e = pcall(rr.kill_uninitialised)
    vim.uv.kill, rr.server_pids = orig_kill, orig_pids
    H.ok(ok, tostring(e))
    H.eq(true, ra.stopped, "stopped with force")
    H.is_nil(bc.stopped)
    H.eq({ { 111, "sigkill" } }, killed)
    -- and the exit of the stopped one is no crash to restart from
    rr.on_exit("rust-analyzer")(nil, 9, ra.id)
    vim.wait(700, function()
      return false
    end, 20)
    H.eq({}, s.ra_starts)
  end)
'''),
    ...para('--', r'At VimLeavePre a server that never finished initialising can survive Neovim as an orphan. '
        r'The module stops uninitialised clients and sends SIGKILL to this Neovim’s children whose '
        r'name matches. The test replaces vim.uv.kill and rust_restart.server_pids so that no '
        r'process is touched: rust-analyzer uninitialised is stopped and killed, bacon_ls '
        r'initialised is left, and the exit of the stopped one afterwards does not restart anything.'),
    ...para('--', r'The second test says what is sent first: SIGCONT to all of this Neovim’s server children, '
        r'because a SIGSTOP-ed server cannot die from a signal and was orphaned at quit. The third '
        r'says nothing is killed when every client is initialised.'),
    ...sec(r'FocusGained refresh'),
    ...para('--', r'This group needs real git. repo makes a directory with one commit through H.git_init. '
        r'focus fires FocusGained in the module’s own group; attach fires LspAttach so the module '
        r'remembers the HEAD and manifest of that root at the moment the client attached.'),
    ...para('--', r'The tests then change the world and focus again. A new commit moves HEAD and restarts '
        r'bacon-ls once, and another focus does not restart again because the new HEAD is now '
        r'remembered. A second attach must not overwrite the remembered HEAD. Before the commit the '
        r'module has run checktime and not restarted, which is the baseline. A reloaded .rs, .toml '
        r'or .lock buffer under the root restarts; other file types and files outside the root do '
        r'not; a Cargo.toml changed on disk restarts (the comment: a repaired manifest left clippy '
        r'failed).'),
    ...para('--', r'git_head is tested at its edges. A symbolic HEAD follows the ref file. A detached HEAD is '
        r'the sha itself, and a checkout --detach to the same commit is no move, while a new commit '
        r'is. When the ref file is missing, as with packed refs, the HEAD text itself is the '
        r'signature, and a branch switch from packed-a to packed-b shows. Outside a plain git '
        r'directory nothing is noticed and the test says so.'),
    ...sec(r'lsp_status: the text on the statusline'),
    ...para('--', r'lsp_status registers handlers by wrapping what the client already has (the test calls '
        r'this once per client and checks that the original is still called), and a few autocmds. '
        r'The fixtures: ra_client builds a rust-analyzer fake with an original serverStatus '
        r'handler; progress fires an LspProgress; server_status calls the wrapped handler directly.'),
    ...para('--', r'The whole life of the rust-analyzer text. RA starting before anything is known. RA '
        r'Indexing 0% then 42% from progress. RA loading when the server reports quiescent false. '
        r'RA error, RA ready (warn) and RA ready from health. The text follows the data exactly, so '
        r'a change of wording fails here.'),
    ...para('--', r'Several progress tokens: the newest wins, a message is used when there is no title, a '
        r'percentage is appended, working is the default, and when one ends another is picked.'),
    ...code('lua', r'tests/server-supervision-statusline_spec.lua · lines 917-935', r'''
  it("bacon(): clippy stopped / running / failed / stale / ok", function()
    local b = scratch_buf()
    vim.b[b].xyno_rust_stopped = { bacon_ls = true }
    H.eq("clippy stopped", status.bacon(b))
    vim.b[b].xyno_rust_stopped = nil

    local seen = {}
    local c = fake_client(s, {
      name = "bacon_ls",
      bufs = { b },
      handlers = {
        ["window/showMessage"] = function(_, r)
          seen[#seen + 1] = r
        end,
      },
    })
    attach(c, b)
    H.eq("clippy ok", status.bacon(b))
    progress(c, "r1", { kind = "begin", title = "checking" })
'''),
    ...para('--', r'bacon(): clippy stopped if the buffer flag is set, clippy ok for an attached client, '
        r'clippy running while a run is in progress, clippy failed after an error message from '
        r'window/showMessage until the next run begins (running wins over failed), and clippy stale '
        r'when the buffer was edited after the last finished run began. An edit during a run is not '
        r'covered by it.'),
    ...para('--', r'When the last run finished with errors on screen it says how many: clippy 2E. Warnings do '
        r'not count. The test sets diagnostics in the namespace of the client and clears them.'),
    ...para('--', r'Stale counts edits, not changedtick. The module attaches to the buffer with '
        r'nvim_buf_attach, so a :write, which changes changedtick, does not make clippy stale. A '
        r'reload from disk (checktime, what FocusGained does) is an edit. The next test checks that '
        r'this survives :edit!, which detaches the buffer, so the first edit after it is stale '
        r'again.'),
    ...para('--', r'The component joins the parts with " | " and gives an empty string where neither server '
        r'applies: RA ready | clippy ok, then clippy ok alone, then RA stopped | clippy stopped '
        r'from the buffer flags.'),
    ...code('lua', r'tests/server-supervision-statusline_spec.lua · lines 1063-1075', r'''
  it("is event driven: no timers or polling, nothing scheduled at idle", function()
    local src = table.concat(vim.fn.readfile(H.repo .. "/lua/xyno_rust/lsp_status.lua"), "\n")
    H.no_match(src, "new_timer", true)
    H.no_match(src, "timer_start", true)
    -- the one exception: "deps resolving" arms a 6 s grace and a 120 s ceiling timer
    -- (deps_begin), only while a manifest is being resolved
    local _, defers = src:gsub("defer_fn", "")
    H.eq(2, defers, "defer_fn only in deps_begin")
    H.no_match(src, "setInterval", true)
    local events = {}
    for _, a in ipairs(vim.api.nvim_get_autocmds({ group = LS_GROUP })) do
      events[a.event] = true
    end
'''),
    ...para('--', r'The sentence at the top of lsp_status says it is event driven, and this test enforces it '
        r'by reading the source: no new_timer, no timer_start, no setInterval, exactly two defer_fn '
        r'(the grace and ceiling timers of deps_begin, armed only while a manifest is being '
        r'resolved), and the autocmd group has exactly LspAttach, LspProgress, TextChanged, '
        r'TextChangedI and BufWipeout. After a round of events the number of Neovim timers is '
        r'unchanged.'),
    ...para('--', r'TextChanged redraws only when bacon-ls is attached to that buffer, since only then '
        r'staleness can change what is shown. A script with no workspace is RA detached rather than '
        r'RA error, based on the text Failed to discover workspace in the server message; any other '
        r'error stays RA error.'),
    ...sec(r'trade-offs'),
    ...pt('--', r'reading the source in a test', r'the event-driven test greps lsp_status.lua. It is a blunt instrument, but a timer is the '
        r'exact thing that would be added by someone fixing a stale display the easy way, and the '
        r'test makes that a decision.'),
    ...pt('--', r'fake clients', r'the fakes implement only what the modules call. If the modules start calling another '
        r'method of the client, the fake fails with a nil call and the test must be updated.'),
    ...pt('--', r'real time in a few tests', r'waits of 150 to 1100 ms exist because the modules use real deferred calls. They make the '
        r'file slower, not flaky, since each wait polls for the expected state.'),
    ...sec(r'history'),
    ...pt('--', r'be73b6c, 2026-10-12', r'xynovim: server supervision introduced with Rust workflow robustness.'),
    ...pt('--', r'b2fee5c, 2026-10-13', r'the spec starts with the suite of 22 specs.'),
    ...pt('--', r'98c9bb4, 2026-10-13', r'field-test round 1: the diff adds tests mentioning the clippy 2E text, edit counting after :edit! and RA detached for a script. The swept-client test appears in 3f868dd (2026-10-13), and a SIGCONT test in 25086fd (2026-10-14).'),
    ...pt('--', r'a3d33c8 to 25086fd, 2026-10-13 to 2026-10-14', r'further rounds on the same two modules (the commit subjects name sweep on save, the '
        r'bacon-ls shadow restart and SIGCONT at quit).'),
    ...pt('--', r'ff1c8fa, 2026-10-16', r'the file gains the xyno-os: linux line for the portable runner.'),
    ...pt('--', r'7c1d2d9, 2026-10-22', r'this repository: namespace renamed to xyno_rust, the live servers group dropped.'),
    ...pt('--', r'dbb2c0e, 2026-10-22', r'the README states what the dropped group used to cover.'),
  ],
);
