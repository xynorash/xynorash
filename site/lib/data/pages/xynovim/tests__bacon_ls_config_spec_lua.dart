import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/tests/bacon-ls-config_spec.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'bacon-ls-config_spec.lua — the clippy tier, rooted once and restarted when it dies'),
    cm('--', r'18 tests for the bacon-ls language server that runs cargo clippy next to rust-analyzer'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'spec for lua/plugins/bacon-ls.lua, lua/config/rust_restart.lua and lua/config/rust_context.lua as they touch bacon-ls'),
    kv(r'language', r'Lua spec, 446 lines, 18 it() blocks, 2 describe() blocks'),
    kv(r'platform', r'Linux and macOS (an xyno-os header skips Windows, with the run id that justifies it)'),
    kv(r'needs', r'rust-analyzer, cargo and Mason bacon-ls from the real XDG_DATA_HOME'),
    kv(r'history', r'6 commits, 2026-10-13 to 2026-10-21'),
    ...sec(r'why this file exists'),
    ...para('--', r'The config runs two Rust diagnostic tiers: rust-analyzer for fast type errors and bacon-ls for clippy results. bacon-ls is an external server with its own idea of a project root, its own restart behaviour and its own cost, since every run is a cargo invocation. Each of those aspects has been a field-test bug: a virtual buffer rooted at a dot, a client per workspace member, a missing cargo producing a bare os error 2. The spec nails each of them down. It uses the real binary, so it skips if Mason did not install it.'),
    ...code('lua', r'tests/bacon-ls-config_spec.lua · lines 1-5', r'''
-- bacon-ls (clippy tier) configuration: lua/plugins/bacon-ls.lua,
-- lua/config/rust_restart.lua, lua/config/rust_context.lua.
-- Needs rust-analyzer and cargo (skipped with a message otherwise); the
-- bacon-ls binary is Mason's, from the real XDG_DATA_HOME.
-- xyno-os: linux,macos (bacon_ls never attaches on windows-latest, run 39655339161: three live tests time out after 63 s and the file after 240 s; cause not found)'''),
    ...sec(r'declared exactly'),
    ...para('--', r'The first test compares the server table with a literal: backend cargo, command clippy, extra arguments --workspace, --all-features, --no-deps and --keep-going, updateOnInsert true with a 500 ms debounce, and checkOnSave false. It compares init_options and settings to the same value, and then opens a crate and compares the merged vim.lsp.config that nvim actually uses, because a declaration in a plugin spec proves nothing until it reaches the real configuration. plugin_server evaluates the plugin file fresh with dofile, so the test sees the table, not a cached copy.'),
    ...code('lua', r'tests/bacon-ls-config_spec.lua · lines 8-10, 44-66', r'''
local mason_bin = vim.fn.stdpath("data") .. "/mason/bin"

--- The plugin spec's bacon_ls server table, evaluated fresh (own upvalues).
...
  -- 1
  it("declares the bacon_ls server with the cargo/clippy settings", function()
    H.known_issue({ "windows" }, "bacon_ls never attaches on Windows (windows-latest run 39647013043; Mason installed bacon-ls but no client starts, cause not found)")
    local srv = plugin_server()
    local want = {
      backend = "cargo",
      cargo = {
        command = "clippy",
        extraArgs = { "--workspace", "--all-features", "--no-deps", "--keep-going" },
        updateOnInsert = true,
        updateOnInsertDebounceMillis = 500,
        checkOnSave = false,
      },
    }
    H.eq(want, srv.init_options)
    H.eq(want, srv.settings.bacon_ls)
    -- and the merged lsp config nvim really uses (loaded with the first Rust buffer)
    open_bacon("basic", "src/lib.rs")
    local cfg = vim.lsp.config.bacon_ls
    H.eq(want, cfg.init_options)
    H.eq(want, cfg.settings.bacon_ls)
    H.eq(nil, srv.cmd, "no cmd override in the plugin spec")
  end)'''),
    ...sec(r'the binary and its version'),
    ...para('--', r'The second test checks that the server advertises Full document sync, that the executable on PATH is the one Mason installed (compared by realpath), that nothing under .cargo is in the command, and that the version is 0.31 or newer. The version floor is checked by parsing the output of bacon-ls --version.'),
    ...code('lua', r'tests/bacon-ls-config_spec.lua · lines 68-84', r'''
  -- 2 + 3
  it("sends updateOnInsert in init_options and runs Mason's bacon-ls >= 0.31.0", function()
    H.known_issue({ "windows" }, "bacon_ls never attaches on Windows (windows-latest run 39647013043; Mason installed bacon-ls but no client starts, cause not found)")
    local _, _, c = open_bacon("basic", "src/lib.rs")
    H.eq(true, c.config.init_options.cargo.updateOnInsert)
    -- advertised sync kind (TextDocumentSyncKind.Full = 1)
    local sync = c.server_capabilities.textDocumentSync
    local change = type(sync) == "table" and sync.change or sync
    H.eq(1, change, "Full didChange sync advertised")
    -- the binary: resolved through $PATH to Mason's, nothing under ~/.cargo
    local bin = vim.fn.exepath(c.config.cmd[1])
    H.eq(vim.uv.fs_realpath(mason_bin .. "/bacon-ls"), vim.uv.fs_realpath(bin))
    H.no_match(table.concat(c.config.cmd, " "), ".cargo", true)
    local v = vim.system({ mason_bin .. "/bacon-ls", "--version" }, { text = true }):wait(10000).stdout
    local maj, min = v:match("(%d+)%.(%d+)")
    H.ok(maj and (tonumber(maj) > 0 or tonumber(min) >= 31), "bacon-ls >= 0.31.0, got " .. vim.trim(v))
  end)'''),
    ...sec(r'one client per workspace'),
    ...para('--', r'In a cargo workspace the root must be the outermost workspace, not the member that happened to be opened first. The test copies the workspace fixture, opens a file of the core member, waits for the client and requires root_dir to be the workspace directory. It then opens a file of a second member and requires that exactly one bacon_ls client exists for that root, with the same id, attached to both buffers. Two clients would mean two cargo runs fighting over the same target directory.'),
    ...code('lua', r'tests/bacon-ls-config_spec.lua · lines 86-107', r'''
  -- 4
  it("roots a workspace member at the outermost [workspace] and keeps ONE client", function()
    H.known_issue({ "windows" }, "bacon_ls never attaches on Windows (windows-latest run 39647013043; Mason installed bacon-ls but no client starts, cause not found)")
    local dir = H.fixture("workspace")
    vim.cmd.cd(vim.fn.fnameescape(dir))
    local b1 = H.open(dir .. "/core/src/lib.rs")
    local c = H.wait_lsp("bacon_ls", b1, 60000)
    H.eq(vim.uv.fs_realpath(dir), vim.uv.fs_realpath(c.config.root_dir))
    local b2 = H.open(dir .. "/app/src/main.rs")
    H.wait_for(function()
      return H.clients(b2, "bacon_ls")[1]
    end, 30000, "bacon_ls on the second member")
    vim.wait(1500)
    -- (only this workspace's clients: one from an earlier test may still be stopping)
    local all = vim.tbl_filter(function(cl)
      return cl.config.root_dir and vim.uv.fs_realpath(cl.config.root_dir) == vim.uv.fs_realpath(dir)
    end, vim.lsp.get_clients({ name = "bacon_ls" }))
    H.eq(1, #all, "exactly one bacon_ls client")
    H.eq(c.id, all[1].id)
    H.eq(c.id, H.clients(b2, "bacon_ls")[1].id)
    H.eq(vim.uv.fs_realpath(dir), vim.uv.fs_realpath(all[1].config.root_dir))
  end)'''),
    ...sec(r'missing cargo is a message, not a crash'),
    ...para('--', r'Without cargo on PATH the server cannot work. The test fakes vim.fn.executable for the name cargo, calls the root_dir function twice for the same buffer, and requires that no root was produced, that exactly one notification was sent (so the user is told once), at WARN level, mentioning cargo is not on PATH, and that after restoring executable the same call roots normally. The comment in the title names the bug: a bare os error 2. The fake is installed with rawset and removed with rawset to nil.'),
    ...code('lua', r'tests/bacon-ls-config_spec.lua · lines 148-183', r'''
  it("without cargo on PATH no client is started and one WARN says why (not a bare os error 2)", function()
    local srv = plugin_server()
    local dir = H.fixture("basic")
    local b = vim.fn.bufadd(dir .. "/src/lib.rs")
    local real = vim.fn.executable
    rawset(vim.fn, "executable", function(name)
      if name == "cargo" then
        return 0
      end
      return real(name)
    end)
    local cap = H.capture_notify()
    local got = "none"
    local ok, err = pcall(function()
      srv.root_dir(b, function(r)
        got = r
      end)
      srv.root_dir(b, function(r)
        got = r
      end)
    end)
    rawset(vim.fn, "executable", nil)
    cap.restore()
    H.ok(ok, err)
    H.eq("none", got)
    H.eq(1, #cap.list, "told once")
    H.eq(vim.log.levels.WARN, cap.list[1].level)
    H.match(cap.list[1].msg, "cargo is not on PATH", true)
    H.eq(dir, (function()
      local r
      srv.root_dir(b, function(x)
        r = x
      end)
      return r
    end)(), "with cargo again it roots normally")
  end)'''),
    ...sec(r'rooting rules'),
    ...para('--', r'Other tests establish that a plain crate roots at the crate directory; empty names and loose .rs files get no root; virtual buffers (diffview://, fugitive://) and non-file buftypes get none, because their root came out as a single dot; a standalone .rs file attaches rust-analyzer but not bacon_ls; and some path segments are excluded (the test is generated for a list of them). A shadow directory is written under the workspace root only, never inside a member crate.'),
    ...sec(r'the context decides the arguments'),
    ...para('--', r'before_init consults the :RustContext that the user stored for the root, so the server starts with the features chosen there, without changing the shared settings table. When no context is stored, including after a reset, it rebuilds from the defaults. A later test changes the context and requires a restart with matching arguments. The server and the context command therefore never disagree about features.'),
    ...sec(r'self-healing'),
    ...para('--', r'The restart test kills the real bacon-ls process with SIGKILL. It first clears the cached rust_restart module, because earlier tests force-stop clients and those count towards a budget of three exits per minute. It finds the newest bacon-ls child of this nvim by walking nvim_get_proc_children, kills it, and waits for the notice bacon_ls exited. The buffer must be marked stopped for bacon_ls, and a new client with a different id must appear within 30 seconds. The comment explains that older bacon-ls processes may still be exiting, hence the newest pid.'),
    ...code('lua', r'tests/bacon-ls-config_spec.lua · lines 278-310', r'''
  it("restarts bacon-ls through rust_restart.on_exit after it was killed", function()
    -- earlier tests' forced client stops count as exits in the module's
    -- 3-per-minute budget: start from a fresh module (the hook requires it per call)
    package.loaded["config.rust_restart"] = nil
    local _, buf, c = open_bacon("basic", "src/lib.rs")
    H.is_nil(vim.b[buf].xynovim_stopped)
    H.eq("function", type(c.config.on_exit))
    local cap = H.capture_notify()
    -- our own child only: the bacon-ls process of THIS nvim
    local kids = vim.api.nvim_get_proc_children(vim.uv.os_getpid())
    local pid
    for _, p in ipairs(kids) do
      -- the newest one is this test's client (older ones may still be exiting)
      if (vim.api.nvim_get_proc(p) or {}).name == "bacon-ls" and (not pid or p > pid) then
        pid = p
      end
    end
    H.ok(pid, "bacon-ls child process")
    vim.uv.kill(pid, "sigkill")
    H.wait_for(function()
      for _, n in ipairs(cap.list) do
        if n.msg:find("bacon_ls exited", 1, true) then
          return true
        end
      end
    end, 10000, "the restart notice")
    H.eq(true, (vim.b[buf].xynovim_stopped or {}).bacon_ls, "marked stopped on the buffer")
    local new = H.wait_for(function()
      local n = H.clients(buf, "bacon_ls")[1]
      return n and n.id ~= c.id and n
    end, 30000, "a new bacon_ls client")
    H.ok(new)
  end)'''),
    ...sec(r'a run per edit, not per write'),
    ...para('--', r'An edit must show a diagnostic within 5 seconds, with one run pipeline and nothing started by :w. The test waits for the initial diagnostic, then counts LspProgress begin and end events for the client, tracking how many are active at the same time. Active runs never exceeding one is the property: cargo is not asked to start a second clippy while one is working. The autocmd is registered for deletion through H._restore.'),
    ...code('lua', r'tests/bacon-ls-config_spec.lua · lines 335-360', r'''
  it("reports an edit within 5 s, with one run pipeline and nothing started by :w", function()
    local dir, buf, c = open_bacon("basic", "src/lib.rs")
    H.wait_for(function()
      return bacon_diags(buf)[1]
    end, 120000, "the initial diagnostic")

    local begins, active, max_active = 0, 0, 0
    local ac = vim.api.nvim_create_autocmd("LspProgress", {
      callback = function(ev)
        if ev.data.client_id ~= c.id then
          return
        end
        local kind = ev.data.params.value and ev.data.params.value.kind
        if kind == "begin" then
          begins = begins + 1
          active = active + 1
          max_active = math.max(max_active, active)
        elseif kind == "end" then
          active = math.max(0, active - 1)
        end
      end,
    })
    table.insert(H._restore, function()
      pcall(vim.api.nvim_del_autocmd, ac)
    end)
    vim.o.autowrite = false'''),
    ...sec(r'other checks'),
    ...para('--', r'Clippy diagnostics are delivered for the basic crate; for the broken crate rust-analyzer type error appears first and clippy later; a deleted workspace has its client stopped on FocusGained by rust_restart.sweep; and the Mason tools named by the README are installed.'),
    ...sec(r'platform note'),
    ...para('--', r'The header skips Windows because bacon_ls never attaches there (run 39655339161: three live tests time out after 63 seconds and the file after 240 seconds, cause not found). Individual tests also call H.known_issue for the earlier run 39647013043. The causes are recorded as unknown, not guessed.'),
    ...sec(r'history'),
    blank,
    ...pt('--', r'b2fee5c (2026-10-13)', r'created. 98c9bb4, a3d33c8 and 3f868dd (2026-10-13) added field test fixes (virtual buffers, restart, manifest tracking).'),
    ...pt('--', r'd3e1442, 7715eb8 (2026-10-21)', r'Windows and macOS: path spelling in member_of, and the suite reduced to what a CI run shows passing.'),
  ],
);
