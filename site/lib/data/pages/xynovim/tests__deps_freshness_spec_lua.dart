import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/tests/deps-freshness_spec.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'deps-freshness_spec.lua — a new dependency must not leave a stale error behind'),
    cm('--', r'Cargo.toml saved, bacon-ls restarted, "deps resolving" in the statusline until rust-analyzer has finished'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'spec for rust_restart.manifest_saved and the deps status of lsp_status'),
    kv(r'language', r'Lua spec, 354 lines, 12 it() blocks, 3 describe() blocks'),
    kv(r'structure', r'fake clients and stubs first, real servers on a copy of deps-lab last'),
    kv(r'needs', r'the last test needs Rust tools, bacon-ls and crates.io (it fetches rand)'),
    kv(r'history', r'b9363cd (2026-10-14), d3e1442 (2026-10-21)'),
    ...sec(r'why this file exists'),
    ...para('--', r'The header calls it phase 0 of docs/PLAN_MACROS_DEPS.md. The problem: you add rand = "0.9" to Cargo.toml and the file still shows a clippy error saying that crate rand cannot be found, because the clippy server computed its answer before the manifest changed and nothing told it to run again. The error is false, and it stays until something restarts the server. The fix in the config is a restart of bacon-ls, debounced, when a manifest is saved; the user needs to know that the state is in flux, so the statusline says deps resolving until rust-analyzer finishes loading the workspace. The spec covers the restart rules, the status rules, and finally the whole thing with real servers.'),
    ...code('lua', r'tests/deps-freshness_spec.lua · lines 1-5', r'''
-- Phase 0 of docs/PLAN_MACROS_DEPS.md: a dependency added to Cargo.toml must not leave a
-- stale "cannot find crate" clippy error behind (rust_restart.manifest_saved) and the
-- statusline says "deps resolving" until rust-analyzer's workspace load is over (lsp_status).
-- The first two blocks use fake clients and stubs (no servers); the last one runs the real
-- servers on a copy of tests/fixtures/deps-lab (skipped without the Rust tools or crates.io).'''),
    ...sec(r'restart rules with fake clients'),
    ...para('--', r'Two groups are named in the module: xynovim_rust_restart and xynovim_lsp_status. fresh_restart reloads the restart module so each test starts from clean counters. The tests fire autocmd events by name instead of saving real files.'),
    ...code('lua', r'tests/deps-freshness_spec.lua · lines 8-16', r'''
pcall(function()
  require("lazy").load({ plugins = { "nvim-lspconfig" } })
end)

local RR_GROUP, LS_GROUP = "xynovim_rust_restart", "xynovim_lsp_status"

local function fresh_restart()
  package.loaded["config.rust_restart"] = nil
  local rr = require("config.rust_restart")'''),
    ...para('--', r'A BufWritePost of Cargo.toml must show deps resolving on the crate buffer at once, no restart yet because of the debounce, then exactly one restart within 3 seconds. Auto-save writes with noautocmd, so the same must happen from the User AutoSaveWritePost event with a saved buffer (for Cargo.lock too). A burst of four saves 100 ms apart is one restart, not four. Other files and manifests outside every server workspace restart nothing. Both of the first tests are known issues on Windows (bacon_ls never attaches there).'),
    ...code('lua', r'tests/deps-freshness_spec.lua · lines 148-160, 173-182', r'''
  it("BufWritePost of Cargo.toml: one debounced restart and 'deps resolving' on the crate's buffers", function()
    H.known_issue({ "windows" }, "bacon_ls never attaches on Windows (windows-latest run 39647013043; Mason installed bacon-ls but no client starts, cause not found)")
    local mb, rb = buf_of(d .. "/Cargo.toml"), buf_of(d .. "/src/main.rs")
    fire("BufWritePost", RR_GROUP, nil, mb)
    H.eq("deps resolving", require("config.lsp_status").deps(rb))
    H.eq(0, s.restarts(), "debounced: nothing at once")
    H.wait_for(function()
      return s.restarts() > 0
    end, 3000, "restart after the Cargo.toml save")
    settle(900)
    H.eq(1, s.restarts())
    H.ok(bacon)
  end)
...
  it("a burst of saves is one restart (500 ms debounce)", function()
    H.known_issue({ "windows" }, "bacon_ls never attaches on Windows (windows-latest run 39647013043; Mason installed bacon-ls but no client starts, cause not found)")
    local mb = buf_of(d .. "/Cargo.toml")
    for _ = 1, 4 do
      fire("BufWritePost", RR_GROUP, nil, mb)
      settle(100)
    end
    settle(1200)
    H.eq(1, s.restarts())
  end)'''),
    ...sec(r'the loop guard'),
    ...para('--', r'Restarting makes the server touch files, and focus changes ask the editor to check files on disk. The loop guard test fires LspAttach for the bacon client, rewrites Cargo.toml on disk, fires BufWritePost, waits for the single restart, then fires FocusGained, waits 1.2 seconds and requires that the restarts are still 1. A neighbouring test shows the opposite: a Cargo.toml changed on disk by cargo add in a terminal does restart on focus and shows deps resolving.'),
    ...code('lua', r'tests/deps-freshness_spec.lua · lines 193-205', r'''
  it("loop guard: FocusGained after the save's restart does not restart again", function()
    H.known_issue({ "windows" }, "bacon_ls never attaches on Windows (windows-latest run 39647013043; Mason installed bacon-ls but no client starts, cause not found)")
    local mb = buf_of(d .. "/Cargo.toml")
    fire("LspAttach", RR_GROUP, { client_id = bacon.id })
    vim.fn.writefile({ "[package]", 'name = "t"', 'version = "0.1.1"' }, d .. "/Cargo.toml")
    fire("BufWritePost", RR_GROUP, nil, mb)
    H.wait_for(function()
      return s.restarts() == 1
    end, 3000)
    fire("FocusGained", RR_GROUP)
    settle(1200)
    H.eq(1, s.restarts())
  end)'''),
    ...sec(r'the status never sticks'),
    ...para('--', r'A status that never clears would be worse than a stale error. The tests of the second block say when deps resolving is shown and when it ends: it shows from the write and survives a quiescent report that precedes the reload; ends at the next quiescent report; a rust-analyzer that was already loading ends at its quiescence; it ends on :RustRestart and when the manifest buffer is wiped; and only buffers under the root show it. The grace test: a rust-analyzer that never goes busy releases the status after 6 seconds, checked by waiting up to 9 seconds for it to vanish.'),
    ...code('lua', r'tests/deps-freshness_spec.lua · lines 265-271', r'''
  it("never sticks: rust-analyzer that never goes busy releases it after the 6 s grace", function()
    server_status(true)
    status.deps_begin(d)
    H.wait_for(function()
      return not shown()
    end, 9000, "grace expiry")
  end)'''),
    ...sec(r'the real thing'),
    ...para('--', r'The last test runs the scenario of the user. It needs rust tools, bacon-ls and an internet connection to fetch rand. It opens a copy of deps-lab main.rs, waits until the statusline component reads RA ready | clippy ok (up to 3 minutes), adds a line using rand::random, writes, and waits until bacon-ls reports the false error naming rand. Then it adds rand = "0.9" to Cargo.toml and writes, records the time, and requires: the status shows deps resolving right after the write; the bacon_ls client id changes within 8 seconds; the stale error is gone within 8 seconds from the save; and deps resolving finally ends with rust-analyzer quiescence.'),
    ...code('lua', r'tests/deps-freshness_spec.lua · lines 299-354', r'''
  it("adding rand to Cargo.toml: the stale 'cannot find crate' clippy error is gone within 8 s, status says deps resolving meanwhile", function()
    H.need_rust()
    if vim.fn.executable("bacon-ls") ~= 1 then
      skip("bacon-ls not found")
    end
    if not online() then
      skip("crates.io not reachable (rand must be fetched)")
    end
    local dir, main = H.open_fixture("deps-lab", "src/main.rs")
    local status = require("config.lsp_status")
    H.wait_for(function()
      return status.component() == "RA ready | clippy ok"
    end, 180000, "ready; is " .. status.component())
    local function bacon_msgs()
      local t = {}
      for _, dg in ipairs(vim.diagnostic.get(main)) do
        if dg.source == "bacon-ls" then
          t[#t + 1] = dg.message
        end
      end
      return table.concat(t, "\n")
    end
    local lines = vim.api.nvim_buf_get_lines(main, 0, -1, false)
    for i, l in ipairs(lines) do
      if l:find("Ok(())", 1, true) then
        table.insert(lines, i, "    let _r: u8 = rand::random();")
        break
      end
    end
    vim.api.nvim_buf_set_lines(main, 0, -1, false, lines)
    vim.cmd("silent write")
    H.wait_for(function()
      return bacon_msgs():find("rand", 1, true) ~= nil
    end, 90000, "the stale 'cannot find crate rand' error; component " .. status.component())

    local old = H.clients(nil, "bacon_ls")[1]
    vim.cmd("edit " .. vim.fn.fnameescape(dir .. "/Cargo.toml"))
    vim.api.nvim_buf_set_lines(0, -1, -1, false, { 'rand = "0.9"' })
    vim.cmd("silent write")
    local t0 = vim.uv.now()
    vim.cmd.buffer(main)
    H.eq("deps resolving", status.deps(main), "shown right after the write")
    H.match(status.component(), "deps resolving", true)
    H.wait_for(function()
      local c = H.clients(nil, "bacon_ls")[1]
      return c and c.id ~= old.id
    end, 8000, "bacon-ls restarted by the Cargo.toml save")
    H.wait_for(function()
      return bacon_msgs():find("cannot find module or crate `rand`", 1, true) == nil
    end, 8000, "the stale error gone")
    H.ok(vim.uv.now() - t0 <= 8000, "within 8 s")
    H.wait_for(function()
      return status.deps(main) == nil
    end, 120000, "deps resolving ends with rust-analyzer's quiescence; " .. status.component())
  end)
end)'''),
    ...sec(r'design notes'),
    blank,
    ...pt('--', r'Events named, files not saved', r'the first two blocks use fake clients and fire events; speed and determinism come from not touching real servers.'),
    ...pt('--', r'Time budgets as assertions', r'the 8-second promise is written into the test, so a slow restart is a failure and not a flaky observation.'),
    ...sec(r'history'),
    blank,
    ...pt('--', r'b9363cd (2026-10-14)', r'created in the macros and dependencies commit.'),
    ...pt('--', r'd3e1442 (2026-10-21)', r'Windows and macOS run 39647013043: known_issue skips for the missing bacon_ls attach.'),
  ],
);
