import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/tests/server-supervision-statusline_spec.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'server-supervision-statusline_spec.lua — language servers die, hang and get stale, and the editor has to notice'),
    cm('--', r'fake clients for rules, a real kill -9 and SIGSTOP for the proof'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'spec for lua/config/rust_restart.lua (supervision), lsp_status.lua (statusline) and the lualine component'),
    kv(r'language', r'Lua spec, 1470 lines, 57 it() blocks, 6 describe() blocks'),
    kv(r'platform', r'Linux only (POSIX signals and /proc on language server processes)'),
    kv(r'runtime', r'the live half takes minutes: run it with scripts/test.sh --timeout 600'),
    kv(r'history', r'8 commits, 2026-10-13 to 2026-10-16'),
    ...sec(r'why this file exists'),
    ...para('--', r'rust-analyzer and bacon-ls are processes, and processes die: out of memory, a panic, a user killing the wrong pid, a laptop suspended mid-run. An editor that shows ok in the statusline while its server is dead is lying, and one that restarts a crashing server in a loop is a nuisance. rust_restart supervises the servers and lsp_status draws their state. The header says the first half is deterministic (fake LSP clients and stubs, no servers), and the second half runs real servers on scratch crates and kills them.'),
    ...code('lua', r'tests/server-supervision-statusline_spec.lua · lines 1-6', r'''
-- rust_restart.lua (server supervision), lsp_status.lua (statusline) and the
-- lualine component. The first half uses fake LSP clients and stubs
-- (deterministic, no servers); the second half ("live") runs rust-analyzer and
-- bacon-ls on scratch crates and kills them (skipped without the Rust tools).
-- The live half takes a few minutes: run it with `scripts/test.sh --timeout 600`.
-- xyno-os: linux (POSIX signals and /proc on language server processes)'''),
    ...sec(r'a clean exit is not a crash'),
    ...para('--', r'The first rules: a clean exit (code 0, signal 0) does nothing. An abnormal exit flags the buffers as stopped, redraws the statusline, warns with the exact message bacon_ls exited (code 101, signal 0); restarting, and restarts the server through vim.lsp.enable after about 500 ms. The test records timing: it requires that nothing was enabled immediately, that the enable happens within three seconds, and that the delay was at least 450 ms. A signalled exit with SIGTERM counts as abnormal even though the code is 0.'),
    ...code('lua', r'tests/server-supervision-statusline_spec.lua · lines 240-258', r'''
  it("an abnormal exit flags the buffers, redraws, warns and restarts bacon_ls after 500 ms", function()
    local b = scratch_buf()
    local c = fake_client(s, { name = "bacon_ls", bufs = { b } })
    local t0 = vim.uv.hrtime()
    require("config.rust_restart").on_exit("bacon_ls")(101, 0, c.id)
    H.wait_for(function()
      return vim.b[b].xynovim_stopped
    end, 2000, "stopped flag")
    H.eq({ bacon_ls = true }, vim.b[b].xynovim_stopped)
    H.ok(s.redraws >= 1, "statusline redrawn")
    H.eq({ { msg = "bacon_ls exited (code 101, signal 0); restarting", level = vim.log.levels.WARN } }, s.notes)
    H.eq({}, s.enabled, "not restarted yet")
    H.wait_for(function()
      return #s.enabled > 0
    end, 3000, "vim.lsp.enable('bacon_ls')")
    H.eq({ "bacon_ls" }, s.enabled)
    local ms = (vim.uv.hrtime() - t0) / 1e6
    H.ok(ms >= 450, "restart is delayed by ~500 ms, was " .. ms)
  end)'''),
    ...sec(r'a loop guard'),
    ...para('--', r'Three automatic restarts are allowed in 60 seconds. The fourth exit gives an ERROR, keeps the statusline at stopped and does not restart. The test fakes four exits, collects four notifications, requires WARN for the first three and the ERROR text bacon_ls keeps exiting (code 2, signal 0); giving up. :RustRestart tries again., waits a second to prove no fourth restart, requires exactly three enables, and then requires the statusline text clippy stopped. The guard is per server name, so a crashing bacon-ls cannot block rust-analyzer.'),
    ...code('lua', r'tests/server-supervision-statusline_spec.lua · lines 290-315', r'''
  it("gives up after 3 automatic restarts in 60 s: ERROR on the 4th, status stays 'stopped'", function()
    local b = scratch_buf()
    local c = fake_client(s, { name = "bacon_ls", bufs = { b } })
    local on_exit = require("config.rust_restart").on_exit("bacon_ls")
    for i = 1, 4 do
      on_exit(2, 0, c.id)
      H.wait_for(function()
        return #s.notes >= i
      end, 2000, "notification " .. i)
    end
    for i = 1, 3 do
      H.eq(vim.log.levels.WARN, s.notes[i].level)
    end
    H.eq({
      msg = "bacon_ls keeps exiting (code 2, signal 0); giving up. :RustRestart tries again.",
      level = vim.log.levels.ERROR,
    }, s.notes[4])
    vim.wait(1000, function()
      return false
    end, 50)
    H.eq(3, #s.enabled, "three restarts, none for the 4th exit")
    -- no client any more (fakes still hold the dead one: drop it) -> stopped
    s.fakes = {}
    vim.api.nvim_set_current_buf(b)
    H.eq("clippy stopped", require("config.lsp_status").bacon(b))
  end)'''),
    ...sec(r'sweeping servers whose project is gone'),
    ...para('--', r'A server whose root directory vanished, or whose root lost its Cargo.toml, is stopped on sweep (otherwise the status stays clippy ok forever). Saves also sweep, so a moved project is noticed without FocusGained; recreating target/bacon-ls-live (after a cargo clean) restarts bacon-ls; a repaired or deleted Cargo.lock restarts it only while clippy has failed; and the exit of a client that the sweep itself stopped is not a crash, so no warning and no restart.'),
    ...sec(r'quitting'),
    ...para('--', r'Servers that were never initialised cannot be stopped politely. VimLeavePre stops uninitialised clients and sends SIGKILL to this nvim server children of that name, and leaves initialised ones alone. The SIGSTOP case was a field finding: servers that were stopped by a signal were orphaned at quit. The fix is to send SIGCONT first, tested with a replaced kill function and server_pids that records one pid and requires exactly the signal sigcont for it.'),
    ...code('lua', r'tests/server-supervision-statusline_spec.lua · lines 539-554', r'''
  it("VimLeavePre sends SIGCONT to this nvim's server children first (SIGSTOPped servers were orphaned at quit)", function()
    local rr = require("config.rust_restart")
    local sent = {}
    local orig_kill, orig_pids = vim.uv.kill, rr.server_pids
    vim.uv.kill = function(pid, sig)
      sent[#sent + 1] = { pid, sig }
      return 0
    end
    rr.server_pids = function()
      return { [111] = "rust-analyzer" }
    end
    local ok, e = pcall(vim.api.nvim_exec_autocmds, "VimLeavePre", { group = "xynovim_rust_restart", modeline = false })
    vim.uv.kill, rr.server_pids = orig_kill, orig_pids
    H.ok(ok, tostring(e))
    H.eq({ { 111, "sigcont" } }, sent)
  end)'''),
    ...sec(r'focus'),
    ...para('--', r'After a focus change the editor checks files on disk. FocusGained sweeps, runs checktime, restarts bacon-ls when a .rs, .toml or .lock buffer under its root was reloaded, debounces to one run, and notices a new commit through the git HEAD: git_head follows a ref: line to the ref file, a detached HEAD is the sha, packed-refs is the fallback and outside a plain git directory HEAD changes are not noticed. A new commit moves HEAD and restarts; no change does not restart. A Cargo.toml changed on disk restarts on focus too.'),
    ...code('lua', r'tests/server-supervision-statusline_spec.lua · lines 678-699', r'''
  it("a new commit moves HEAD and restarts bacon_ls; no change does not", function()
    local d = repo()
    local c = fake_client(s, { name = "bacon_ls", root = d })
    attach(c)
    focus()
    H.wait_for(function()
      return has_cmd(s, "silent! checktime") > 0
    end, 3000)
    settle()
    H.eq(0, has_cmd(s, "lsp restart bacon_ls"), "no change, no restart")
    H.git(d, "commit", "-q", "--allow-empty", "-m", "two")
    attach(c) -- a second attach must not overwrite the remembered HEAD
    focus()
    H.wait_for(function()
      return has_cmd(s, "lsp restart bacon_ls") > 0
    end, 3000, "restart after the commit")
    -- the new HEAD is now remembered: another focus does not restart again
    s.cmds = {}
    focus()
    settle()
    H.eq(0, has_cmd(s, "lsp restart bacon_ls"))
  end)'''),
    ...sec(r'the statusline states'),
    ...para('--', r'lsp_status builds the text from client state. rust-analyzer: nothing without a client, RA stopped with the flag, starting, a progress text with a percentage, loading, error, warn, ready, and RA detached for a standalone script (Failed to discover workspace) while other errors stay RA error. bacon: clippy stopped, running, failed, stale or ok. The tests tell the whole sequence with a fake client: ok after attach; running between begin and end; failed after an Error showMessage until the next run begins; an Info message does not fail it; running wins over failed; an edit after the last run began is stale; a run that began after the edit covers it; an edit during a run is not covered by that run.'),
    ...code('lua', r'tests/server-supervision-statusline_spec.lua · lines 920-965', r'''
  it("bacon(): clippy stopped / running / failed / stale / ok", function()
    local b = scratch_buf()
    vim.b[b].xynovim_stopped = { bacon_ls = true }
    H.eq("clippy stopped", status.bacon(b))
    vim.b[b].xynovim_stopped = nil

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
    H.eq("clippy running", status.bacon(b))
    progress(c, "r1", { kind = "end" })
    H.eq("clippy ok", status.bacon(b))
    -- an error message: failed (original handler still called), until the next run begins
    c.handlers["window/showMessage"](nil, { type = vim.lsp.protocol.MessageType.Error, message = "cargo exited: 101" }, {}, {})
    H.eq(1, #seen)
    H.eq("clippy failed", status.bacon(b))
    -- an info message does not fail it
    progress(c, "r2", { kind = "begin", title = "checking" })
    H.eq("clippy running", status.bacon(b), "running wins over failed")
    progress(c, "r2", { kind = "end" })
    H.eq("clippy ok", status.bacon(b), "next run cleared the failure")
    c.handlers["window/showMessage"](nil, { type = vim.lsp.protocol.MessageType.Info, message = "hi" }, {}, {})
    H.eq("clippy ok", status.bacon(b))
    -- an edit after the last finished run began: stale
    vim.api.nvim_buf_set_lines(b, 0, -1, false, { "edit" })
    H.eq("clippy stale", status.bacon(b))
    -- the next run began after the edit: it covers it
    progress(c, "r3", { kind = "begin", title = "checking" })
    progress(c, "r3", { kind = "end" })
    H.eq("clippy ok", status.bacon(b))
    -- an edit DURING a run is not covered by it
    progress(c, "r4", { kind = "begin", title = "checking" })
    vim.api.nvim_buf_set_lines(b, 0, -1, false, { "edit again" })
    progress(c, "r4", { kind = "end" })
    H.eq("clippy stale", status.bacon(b))
  end)'''),
    ...sec(r'numbers on screen'),
    ...para('--', r'A finished run with errors on screen says how many, clippy 2E, and not clippy ok; warnings do not count. Stale counts edits through nvim_buf_attach and not the changedtick, so :write is not an edit, while a reload from disk (what FocusGained does) is. Edit counting survives :edit!, which detaches the buffer.'),
    ...code('lua', r'tests/server-supervision-statusline_spec.lua · lines 967-1013', r'''
  it("a finished run with errors on screen says how many ('clippy 2E'), not 'clippy ok'", function()
    local b = scratch_buf()
    local c = fake_client(s, { name = "bacon_ls", bufs = { b } })
    attach(c, b)
    progress(c, "r1", { kind = "begin", title = "checking" })
    progress(c, "r1", { kind = "end" })
    H.eq("clippy ok", status.bacon(b))
    local ns = vim.lsp.diagnostic.get_namespace(c.id)
    local E, W = vim.diagnostic.severity.ERROR, vim.diagnostic.severity.WARN
    vim.diagnostic.set(ns, b, {
      { lnum = 0, col = 0, message = "e1", severity = E },
      { lnum = 0, col = 0, message = "e2", severity = E },
      { lnum = 0, col = 0, message = "w", severity = W },
    })
    H.eq("clippy 2E", status.bacon(b))
    vim.diagnostic.set(ns, b, { { lnum = 0, col = 0, message = "w", severity = W } })
    H.eq("clippy ok", status.bacon(b), "warnings do not count")
    vim.diagnostic.reset(ns, b)
  end)

  it("stale counts edits (nvim_buf_attach), not changedtick: :write does not leave it stale", function()
    local dir = H.tmpdir()
    local file = dir .. "/notes.txt"
    vim.fn.writefile({ "one" }, file)
    vim.cmd("edit " .. vim.fn.fnameescape(file))
    local b = vim.api.nvim_get_current_buf()
    local c = fake_client(s, { name = "bacon_ls", bufs = { b } })
    attach(c, b)
    progress(c, "r1", { kind = "begin", title = "checking" })
    progress(c, "r1", { kind = "end" })
    vim.api.nvim_buf_set_lines(b, 0, -1, false, { "two" })
    H.eq("clippy stale", status.bacon(b))
    progress(c, "r2", { kind = "begin", title = "checking" })
    progress(c, "r2", { kind = "end" })
    H.eq("clippy ok", status.bacon(b))
    local tick = vim.b[b].changedtick
    vim.cmd("write")
    H.ok(vim.b[b].changedtick >= tick)
    H.eq("clippy ok", status.bacon(b), "a write is not an edit")
    -- a reload from disk (checktime, what FocusGained does) counts as an edit
    vim.fn.writefile({ "three" }, file)
    without_fakes(s, function()
      vim.cmd("checktime")
    end)
    H.eq("three", vim.api.nvim_buf_get_lines(b, 0, 1, false)[1])
    H.eq("clippy stale", status.bacon(b), "a reload counts as an edit")
  end)'''),
    ...sec(r'no polling'),
    ...para('--', r'The statusline is event driven. The test reads the source of lsp_status.lua and requires that it contains neither new_timer, timer_start nor setInterval, and that defer_fn occurs exactly twice (the exception, in deps_begin, for the deps resolving grace and ceiling). It requires the autocmd events of the group to be exactly LspAttach, LspProgress, TextChanged, TextChangedI and BufWipeout, and that exercising the component creates no vim timer.'),
    ...code('lua', r'tests/server-supervision-statusline_spec.lua · lines 1086-1108', r'''
  it("is event driven: no timers or polling, nothing scheduled at idle", function()
    local src = table.concat(vim.fn.readfile(H.repo .. "/lua/config/lsp_status.lua"), "\n")
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
    H.eq({ LspAttach = true, LspProgress = true, TextChanged = true, TextChangedI = true, BufWipeout = true }, events)
    local before = #vim.fn.timer_info()
    local b = scratch_buf()
    local c = ra_client(b, function() end)
    attach(c, b)
    progress(c, "x", { kind = "begin", title = "Indexing", percentage = 1 })
    progress(c, "x", { kind = "end" })
    vim.api.nvim_exec_autocmds("TextChanged", { group = LS_GROUP, buffer = b, modeline = false })
    H.eq(before, #vim.fn.timer_info(), "no vim timers created")
  end)'''),
    ...sec(r'the live half'),
    ...para('--', r'On a scratch crate with real rust-analyzer and bacon-ls: the status sequence from starting through loading to ready, stale after a typing and running again, then ok; typing with auto-save on settles on clippy ok and not stale; sed -i on an open file followed by FocusGained restarts bacon-ls and the new error appears; files not open that change without a HEAD move are not noticed; a new commit restarts; a broken manifest gives clippy failed and the repair gives clippy ok; deleting a crate removes the client after FocusGained; SIGTERM is abnormal and restarts the server; four quick kills end at clippy stopped and :RustRestart revives it; and :RustRestart revives SIGSTOPped hung servers with new pids. The central test kills both with SIGKILL.'),
    ...code('lua', r'tests/server-supervision-statusline_spec.lua · lines 1378-1397', r'''
  it("kill -9 of both servers: 'RA stopped | clippy stopped', then both back with new pids and ok + clippy diagnostics", function()
    vim.cmd.buffer(buf)
    fresh_restart()
    local ra_old, bc_old = ra(), bacon()
    local pids = { ra = pid(ra_old), bc = pid(bc_old) }
    H.ok(pids.ra and pids.bc, "client pids")
    H.ok(pids.ra ~= pids.bc)
    vim.uv.kill(pids.ra, "sigkill")
    vim.uv.kill(pids.bc, "sigkill")
    H.wait_for(function()
      return comp() == "RA stopped | clippy stopped"
    end, 15000, "'RA stopped | clippy stopped'; is " .. comp())
    wait_ready("both servers back; is " .. comp())
    local ra_new, bc_new = ra(), bacon()
    H.ok(ra_new.id ~= ra_old.id and bc_new.id ~= bc_old.id, "new clients")
    H.ok(pid(ra_new) ~= pids.ra and pid(bc_new) ~= pids.bc, "new pids")
    H.wait_for(function()
      return #bacon_diags(bc_new) > 0
    end, 90000, "clippy diagnostics from the new bacon-ls")
  end)'''),
    ...sec(r'history'),
    blank,
    ...pt('--', r'b2fee5c (2026-10-13)', r'created. 98c9bb4, a3d33c8, 3f868dd (2026-10-13), f31e013, 25086fd (2026-10-14) :: field test rounds; 25086fd names SIGCONT at quit.'),
    ...pt('--', r'b9363cd (2026-10-14)', r'deps resolving in the statusline. ff1c8fa (2026-10-16) :: the Linux-only header.'),
  ],
);
