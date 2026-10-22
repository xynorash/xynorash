import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/lua/config/rust_restart.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'rust_restart.lua — keep the two Rust servers alive, and fresh'),
    cm('--', r'crash restarts, stale-shadow restarts, manifest restarts, clean exits, :RustRestart'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'supervision of rust-analyzer and bacon-ls: restart on crash, on disk change, on manifest save'),
    kv(r'language', r'Lua; LSP client lifecycle, libuv timers and signals, git HEAD reading'),
    kv(r'size', r'483 lines, 8 commits (be73b6c on 2026-10-12 to ff1c8fa on 2026-10-16)'),
    kv(r'command', r':RustRestart'),
    kv(r'talks to', r'lsp_status.lua (flags in, deps_begin/deps_clear out), plugins/bacon-ls.lua (on_exit)'),
    kv(r'also lives in', r'xyno-rust.nvim (lua/xyno_rust/rust_restart.lua): renamed identifiers plus a commands option'),
    ...sec(r'why this file exists'),
    ...para('--', r'The header of the file is a list of six situations, each of which was a real failure found by running the setup, and the module is the sum of the answers. A server that dies (kill -9, the OOM killer, a crash) used to stay dead: "Neither :RustAnalyzer restart nor :lsp restart can revive a dead client". bacon-ls keeps a hardlinked copy of the workspace (a shadow) and re-syncs only the files Neovim reports, so a file replaced from outside by sed -i, git checkout or an agent leaves clippy checking old content. A dependency added to Cargo.toml is unknown to bacon-ls for minutes ("measured minutes", says the comment). A project deleted under a running editor leaves a client for nothing. Servers that never finished starting were orphaned when Neovim quit. And a SIGSTOPped server ignored shutdown.'),
    ...para('--', r'It started in be73b6c on 2026-10-12 ("Rust workflow robustness: bacon-ls workspace root, server supervision, dap formatters/panic stop") and grew through the "Final loop" rounds as the field tests found new cases. Most of the file is therefore guards against loops: restarts that cause a save that causes a restart, a restart on every focus, a restart for a file cargo itself rewrote.'),
    ...sec(r'state and starting a server'),
    ...code('lua', r'lua/config/rust_restart.lua · lines 25-59', r'''
local starts = {} -- name -> os.time() of the automatic restarts in the last minute
local disk_changed = false
local heads = {} -- workspace root -> git HEAD signature when last looked at
local manifests = {} -- workspace root -> Cargo.toml mtime when last looked at
local lives = {} -- workspace root -> identity of target/bacon-ls-live when last looked at
local locks = {} -- workspace root -> Cargo.lock signature (kept while clippy is not failed)
local swept = {} -- client ids stopped by sweep(): their exit is not a crash
local SERVER_EXES = { ["rust-analyzer"] = true, ["bacon-ls"] = true }

local function bacon_clients()
  return vim.lsp.get_clients({ name = "bacon_ls" })
end

--- Start rust-analyzer for the rust buffers that lost it, bacon-ls for all
--- buffers that match its root_dir.
local function start(name, bufs)
  if name == "bacon_ls" then
    -- enable() of an already enabled config is a no-op, so a bacon-ls that died stayed
    -- dead in headless nvim (the field test's kill -9): off and on re-attaches the buffers
    if #bacon_clients() == 0 then
      vim.lsp.enable("bacon_ls", false)
    end
    vim.lsp.enable("bacon_ls")
    return
  end
  local ok, lsp = pcall(require, "rustaceanvim.lsp")
  if not ok then
    return
  end
  for _, b in ipairs(bufs) do
    if vim.api.nvim_buf_is_valid(b) and #vim.lsp.get_clients({ bufnr = b, name = "rust-analyzer" }) == 0 then
      lsp.start(b)
    end
  end
end'''),
    ...para('--', r'Each state table is a memory of "what I saw last time", keyed by workspace root: the git HEAD, the Cargo.toml mtime, the identity of the bacon-ls shadow directory, the Cargo.lock signature; plus the list of automatic restart times (for rate limiting) and the set of client ids stopped on purpose. Comparing the remembered value to the current one is how the module notices change without a file watcher.'),
    ...para('--', r'The two servers are started in two different ways, which is why start() has two branches. bacon-ls is a native vim.lsp config, so starting it means vim.lsp.enable("bacon_ls"); but the comment records a trap: enabling an already enabled config does nothing, so a bacon-ls that had died stayed dead in a headless Neovim during the kill -9 field test. If there are no clients, the function turns the config off and on again, which re-attaches the buffers. rust-analyzer belongs to rustaceanvim, so for each Rust buffer that has lost its client the function calls rustaceanvim.lsp.start(buf), inside a pcall on the require so it is a no-op without the plugin.'),
    ...sec(r'on_exit: restart after a crash, but not forever'),
    ...code('lua', r'lua/config/rust_restart.lua · lines 61-103', r'''
--- on_exit callback for a server: records "stopped" on its buffers and
--- restarts it after an abnormal exit (graceful stops, `:lsp restart` and
--- quitting nvim exit with code 0 and signal 0 and are left alone).
function M.on_exit(name)
  return function(code, signal, client_id)
    if (code == 0 and signal == 0) or swept[client_id] then
      return
    end
    -- runs in a fast event: read the buffers now (they are detached on the
    -- next tick), do the rest scheduled
    local client = vim.lsp.get_client_by_id(client_id)
    local bufs = vim.tbl_keys(client and client.attached_buffers or {})
    vim.schedule(function()
      for _, b in ipairs(bufs) do
        if vim.api.nvim_buf_is_valid(b) then
          local flags = vim.b[b].xynovim_stopped or {}
          flags[name] = true
          vim.b[b].xynovim_stopped = flags
        end
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
end'''),
    ...para('--', r'on_exit is a factory: given a server name it returns the callback that the server config installs. plugins/bacon-ls.lua line 95 does it for bacon_ls with require("config.rust_restart").on_exit("bacon_ls")(...). The callback receives the process exit code and signal. A clean exit (both zero) is ignored, which covers :lsp restart, a graceful stop and quitting Neovim, none of which should trigger a restart. A client in the swept set is ignored too: the module stopped it on purpose.'),
    ...para('--', r'The comment explains the first subtlety: the callback runs in a fast event, where most of the API is forbidden, and the client’s buffers are detached on the next tick, so the buffer list is read immediately and everything else is scheduled. In the scheduled part the buffers get a "stopped" flag (the buffer variable that lsp_status.lua turns into "RA stopped" or "clippy stopped"). Then three guards decide whether to restart. If Neovim is exiting (v:exiting is no longer null), do nothing. If the server has already been restarted three times in the last 60 seconds, give up with an ERROR that tells the user how to try again by hand; this is the circuit breaker that stops a server that crashes on start from being restarted in a tight loop. Otherwise record the time, warn, and start again after 500 ms, because, as the comment says, the dead client is only dropped from the client list a tick later.'),
    ...sec(r'sweep: servers for projects that are gone'),
    ...code('lua', r'lua/config/rust_restart.lua · lines 105-116', r'''
--- Stop bacon-ls clients whose workspace directory is gone, or whose root
--- lost its Cargo.toml (moved away: the status stayed `clippy ok`); a deleted
--- crate would otherwise keep its client and shadow forever.
function M.sweep()
  for _, c in ipairs(bacon_clients()) do
    local root = c.config.root_dir
    if root and not (vim.uv.fs_stat(root) and vim.uv.fs_stat(root .. "/Cargo.toml")) then
      swept[c.id] = true
      c:stop(true)
    end
  end
end'''),
    ...para('--', r'Two stat calls per client. A client whose root directory vanished, or whose Cargo.toml is gone, is stopped with force, and its id is added to swept so that on_exit does not treat the resulting exit as a crash and bring it back. The comment mentions the symptom that motivated the second half of the test: when a project was moved away the status stayed "clippy ok".'),
    ...sec(r'noticing change on disk without a watcher'),
    ...code('lua', r'lua/config/rust_restart.lua · lines 118-193', r'''
--- HEAD of the git repo holding `root`: the branch's commit, or the HEAD
--- file itself when detached. nil outside a plain git directory.
local function git_head(root)
  local git = vim.fs.find(".git", { upward = true, path = root, type = "directory" })[1]
  if not git then
    return nil
  end
  local function read(f)
    local fh = io.open(f)
    if not fh then
      return nil
    end
    local t = fh:read("*a")
    fh:close()
    return vim.trim(t)
  end
  local head = read(git .. "/HEAD")
  local ref = head and head:match("^ref: (.+)$")
  if not ref then
    return head
  end
  return read(git .. "/" .. ref) or head -- packed refs: only a branch switch shows
end

--- mtime of the root's Cargo.toml ("-" when absent). Not Cargo.lock: cargo/rust-analyzer
--- create and rewrite it on their own, which restarted bacon-ls for nothing.
local function manifest_sig(root)
  local st = vim.uv.fs_stat(root .. "/Cargo.toml")
  return st and (st.mtime.sec .. "." .. st.mtime.nsec) or "-"
end

--- Inode and birth time of the root's target/bacon-ls-live ("-" when absent): a `cargo clean`
--- deletes it and bacon-ls then recreates it, with the same path but another identity.
local function live_sig(root)
  local st = vim.uv.fs_stat(root .. "/target/bacon-ls-live")
  return st and (st.ino .. ":" .. (st.birthtime and (st.birthtime.sec .. "." .. st.birthtime.nsec) or "")) or "-"
end

local function lock_sig(root)
  local st = vim.uv.fs_stat(root .. "/Cargo.lock")
  return st and (st.size .. ":" .. st.mtime.sec .. "." .. st.mtime.nsec) or "-"
end

--- On a save: restart bacon-ls when its in-memory shadow no longer matches the disk.
---  * `cargo clean` wiped target/bacon-ls-live under a running bacon-ls, which then never
---    reported a new error again while the status said `clippy ok` (field test).
---  * Cargo.lock was repaired/deleted while clippy has `failed`: the shadow kept the bad
---    hardlinked lock. (Watched only in that state: cargo rewrites the lock itself.)
function M.check_shadow()
  local restart = false
  for _, c in ipairs(bacon_clients()) do
    local root = c.config.root_dir
    if root and root:sub(1, 1) == "/" then
      local live = live_sig(root)
      if live ~= "-" and lives[root] and lives[root] ~= live then
        restart = true
      end
      lives[root] = live ~= "-" and live or lives[root]
      local lock = lock_sig(root)
      if not require("config.lsp_status").bacon_failed(c.id) then
        locks[root] = lock
      elseif locks[root] == nil then
        locks[root] = lock
      elseif locks[root] ~= lock then
        locks[root] = lock
        restart = true
      end
    end
  end
  if restart then
    lives, locks = {}, {}
    vim.cmd("lsp restart bacon_ls")
    vim.notify("bacon-ls restarted (target/ was cleaned or Cargo.lock changed)", vim.log.levels.INFO)
  end
  return restart
end'''),
    ...para('--', r'There are four signatures, and each is chosen carefully. The git HEAD is read by hand from the .git directory rather than by running git: HEAD holds either a ref name or a commit; if it is a ref, the file for that ref is read, and if the ref file is missing (packed refs) the HEAD text itself is used, with the honest comment that then "only a branch switch shows". The Cargo.toml signature is the modification time, with the explanation of what it is deliberately not: Cargo.lock, because cargo and rust-analyzer create and rewrite it on their own, "which restarted bacon-ls for nothing". The shadow signature is the inode plus birth time of target/bacon-ls-live: cargo clean deletes the directory and bacon-ls recreates it at the same path, so the path alone cannot show it, but the identity changes. The lock signature is size plus mtime.'),
    ...para('--', r'check_shadow, run on saves, restarts bacon-ls in two cases and the comment says what field-test failure each protects against. When the shadow directory has a different identity from last time, a cargo clean wiped it under a running server, which "never reported a new error again while the status said clippy ok". When Cargo.lock changed while clippy is in the failed state, the shadow kept the bad hardlinked lock. The lock is watched only in the failed state, because "cargo rewrites the lock itself": outside it, the module just keeps the latest signature so that the next failure compares against a fresh one. Note the use of bacon_failed from lsp_status.lua, the only place where this module reads that module’s state. After a restart the remembered tables are cleared, so the new run starts clean.'),
    ...sec(r'a saved manifest: restart once per burst'),
    ...code('lua', r'lua/config/rust_restart.lua · lines 239-277', r'''
local manifest_timer

--- A Cargo.toml / Cargo.lock was saved from nvim: show "deps resolving" and restart bacon-ls
--- once per burst of saves (500 ms debounce). Returns whether `file` was such a manifest.
function M.manifest_saved(file, buf)
  local base = file and vim.fs.basename(file)
  if base ~= "Cargo.toml" and base ~= "Cargo.lock" then
    return false
  end
  local root = server_root(file)
  if not root then
    return false
  end
  require("config.lsp_status").deps_begin(root, buf)
  if manifest_timer then
    manifest_timer:stop()
  else
    manifest_timer = assert(vim.uv.new_timer())
  end
  manifest_timer:start(
    500,
    0,
    vim.schedule_wrap(function()
      if #bacon_clients() == 0 then
        return
      end
      -- what we are about to restart for is already seen: FocusGained must not restart again
      for _, c in ipairs(bacon_clients()) do
        local r = c.config.root_dir
        if r then
          manifests[r] = manifest_sig(r)
        end
      end
      lives, locks = {}, {}
      vim.cmd("lsp restart bacon_ls")
    end)
  )
  return true
end'''),
    ...para('--', r'This function connects two modules. When a Cargo.toml or Cargo.lock is saved from Neovim and some server has a workspace root above it (server_root looks at bacon-ls first, then rust-analyzer), it first tells the statusline to show "deps resolving" via deps_begin, then (re)arms a single timer for 500 ms. Each further save restarts the timer, so a burst of saves, which auto-save can produce, restarts bacon-ls once, 500 ms after the last one. The timer callback marks the new manifest mtime as already seen before restarting. That is the loop guard that the header names: "the restart records the new manifest mtime, so the next FocusGained does not restart again", and the header adds the second half of the guard, that bacon-ls writes buffer text only into its shadow, never into the workspace, so the restart cannot trigger another save.'),
    ...sec(r'FocusGained: the world changed while you were away'),
    ...code('lua', r'lua/config/rust_restart.lua · lines 279-312', r'''
local function refresh()
  M.sweep()
  -- the manifest was away (deleted, a checkout without it) and is back: the sweep had stopped
  -- the client and nothing re-enabled it; only :RustRestart or reopening the buffer did
  if #bacon_clients() == 0 and orphan_rust_buffer() then
    start("bacon_ls")
  end
  vim.cmd("silent! checktime") -- reloads unmodified buffers; FileChangedShellPost marks them
  local moved = false
  for _, c in ipairs(bacon_clients()) do
    local root = c.config.root_dir
    local head = root and git_head(root)
    if head and heads[root] and heads[root] ~= head then
      moved = true
    end
    if root then
      heads[root] = head
      -- a Cargo.toml repaired from outside: "clippy failed" stayed until the next edit
      local sig = manifest_sig(root)
      -- (a vanished manifest is sweep()'s business, not a reason to restart every client)
      if sig ~= "-" and manifests[root] and manifests[root] ~= sig then
        moved = true
        require("config.lsp_status").deps_begin(root) -- cargo add in a terminal: same transient as a save
      end
      manifests[root] = sig
    end
  end
  if disk_changed or moved then
    disk_changed = false
    if #bacon_clients() > 0 then
      vim.cmd("lsp restart bacon_ls")
    end
  end
end'''),
    ...para('--', r'When you come back to the editor after running git pull, cargo add or an agent in another window, nothing in Neovim knows. refresh() is the answer, run 300 ms after FocusGained (a debounced timer, below). In order: sweep dead workspaces; if the manifest has come back for a project whose client the sweep had stopped, start bacon-ls again; run :checktime, which reloads the unmodified buffers whose files changed and marks each one through FileChangedShellPost (the autocmd sets disk_changed when the file is a relevant Rust or Cargo file); compare the git HEAD of every workspace with the remembered one; compare the manifest mtime. Any of these means the shadow is stale and bacon-ls is restarted once. A manifest change also calls deps_begin, so that a cargo add in a terminal produces the same "deps resolving" transient as a save. The comment on the vanished manifest is a restraint rule: a missing Cargo.toml is the sweep’s job, "not a reason to restart every client".'),
    ...sec(r'quitting without leaving orphans'),
    ...code('lua', r'lua/config/rust_restart.lua · lines 314-376', r'''
--- pid -> name of the Rust servers that are children of this nvim.
function M.server_pids()
  local out = {}
  for _, pid in ipairs(vim.api.nvim_get_proc_children(vim.uv.os_getpid())) do
    local p = vim.api.nvim_get_proc(pid)
    local name = p and p.name:gsub("%.exe$", "") -- Windows names carry the .exe
    if p and SERVER_EXES[name] then
      out[pid] = name
    end
  end
  return out
end

--- SIGKILL the processes of `pids` that are still alive after `ms`. A server
--- that hangs or was SIGSTOPped never answers the shutdown request and a
--- stopped process does not act on SIGTERM either, so a graceful restart
--- alone left it in place; its exit then lets the supervision above start a
--- fresh one.
function M.kill_survivors(pids, ms)
  vim.defer_fn(function()
    for pid, name in pairs(pids) do
      local p = vim.api.nvim_get_proc(pid)
      if p and p.name:gsub("%.exe$", "") == name then
        vim.uv.kill(pid, "sigkill")
      end
    end
  end, ms or 3000)
end

--- VimLeavePre: a rust-analyzer or bacon-ls that has not answered `initialize` yet
--- never gets (or answers) the shutdown handshake when nvim quits right after
--- opening a file, and was left behind with PPID 1 (field test, seen under load,
--- 1 of 40 quits). Those are stopped and SIGKILLed here; initialised servers
--- shut down through nvim's own exit path.
function M.kill_uninitialised()
  local exes = {}
  for _, name in ipairs({ "rust-analyzer", "bacon_ls" }) do
    for _, c in ipairs(vim.lsp.get_clients({ name = name })) do
      if not c.initialized then
        swept[c.id] = true
        pcall(c.stop, c, true)
        exes[name == "bacon_ls" and "bacon-ls" or name] = true
      end
    end
  end
  -- (vim.lsp.rpc exposes no pid: the servers are this nvim's children, by name)
  for pid, name in pairs(M.server_pids()) do
    if exes[name] then
      vim.uv.kill(pid, "sigkill")
    end
  end
end

--- VimLeavePre: a SIGSTOPped server does not act on the SIGTERM/shutdown of nvim's exit and was
--- orphaned (state T, PPID 1). SIGCONT lets it handle them (harmless for a running one).
function M.resume_servers()
  if vim.fn.has("win32") == 1 then -- no SIGSTOP / SIGCONT there
    return
  end
  for pid in pairs(M.server_pids()) do
    vim.uv.kill(pid, "sigcont")
  end
end'''),
    ...para('--', r'Three process-level problems are handled here, each with a field-test number in its comment. vim.lsp.rpc does not expose the server’s pid, so server_pids() finds the servers as the children of this Neovim process whose executable name is rust-analyzer or bacon-ls (with a .exe suffix stripped for Windows); the comment states the workaround: "the servers are this nvim’s children, by name". kill_survivors waits (3 seconds by default) and then SIGKILLs whichever of those processes is still alive and still has the same name. The name check guards against the pid being reused by an unrelated process in the meantime. The comment says why a graceful restart is not enough: a hung server never answers the shutdown request and a stopped one does not act on SIGTERM; its exit then lets the supervision above start a new one.'),
    ...para('--', r'On VimLeavePre, kill_uninitialised handles a server that has not yet answered initialize, which "never gets (or answers) the shutdown handshake when nvim quits right after opening a file, and was left behind with PPID 1 (field test, seen under load, 1 of 40 quits)". It marks them swept, so the exit is not mistaken for a crash, force-stops them and kills them. The servers that did initialise shut down through Neovim’s own exit path. resume_servers, also on VimLeavePre, sends SIGCONT to every server child first: a SIGSTOPped server does not act on the SIGTERM or the shutdown at exit and was orphaned in state T. SIGCONT is harmless for a running one and is skipped on Windows, which has no such signals. The order in the autocmd is resume first, then kill, which matters: a stopped process must be continued before anything else can happen to it.'),
    ...sec(r':RustRestart and the autocmds'),
    ...code('lua', r'lua/config/rust_restart.lua · lines 378-424', r'''
function M.restart()
  require("config.lsp_status").deps_clear()
  M.sweep()
  M.kill_survivors(M.server_pids())
  local buf = vim.api.nvim_get_current_buf()
  local bufs = vim.tbl_filter(function(b)
    return vim.api.nvim_buf_is_loaded(b) and vim.bo[b].filetype == "rust"
  end, vim.api.nvim_list_bufs())
  if #vim.lsp.get_clients({ name = "rust-analyzer" }) > 0 then
    pcall(vim.cmd.RustAnalyzer, "restart")
  elseif vim.bo[buf].filetype == "rust" or #bufs > 0 then
    start("rust-analyzer", bufs)
  end
  if #bacon_clients() > 0 then
    vim.cmd("lsp restart bacon_ls")
  else
    start("bacon_ls")
  end
  for _, b in ipairs(bufs) do
    vim.b[b].xynovim_stopped = nil
  end
  vim.notify("restarting rust-analyzer and bacon-ls")
end

function M.setup()
  local group = vim.api.nvim_create_augroup("xynovim_rust_restart", { clear = true })

  vim.api.nvim_create_user_command("RustRestart", M.restart, {
    desc = "Restart rust-analyzer and bacon-ls (also when one has died)",
  })

  vim.api.nvim_create_autocmd("FileChangedShellPost", {
    group = group,
    callback = function(ev)
      if relevant(vim.api.nvim_buf_get_name(ev.buf)) then
        disk_changed = true
      end
    end,
  })

  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function()
      M.resume_servers()
      M.kill_uninitialised()
    end,
  })'''),
    ...para('--', r':RustRestart is the manual escape hatch and is written to work from any state. It clears any "deps resolving" wait, sweeps, and schedules the SIGKILL of survivors (so a hung server cannot block the restart). If a rust-analyzer client exists it uses rustaceanvim’s :RustAnalyzer restart (in a pcall); otherwise, if there is a Rust buffer anywhere, it starts rust-analyzer from scratch; bacon-ls is restarted with :lsp restart when running, or started from scratch when dead. It then clears the "stopped" flag on every Rust buffer and notifies. This is the command that the give-up message of on_exit points at.'),
    ...code('lua', r'lua/config/rust_restart.lua · lines 426-481', r'''
  -- A project directory moved or deleted under a running nvim: bacon-ls recreated
  -- <old path>/target/bacon-ls-live on the next edit and the status said `clippy ok` until
  -- FocusGained (tmux has focus-events off by default). A save is cheap to hook: two stats per client.
  vim.api.nvim_create_autocmd({ "BufWritePost", "User" }, {
    group = group,
    pattern = { "*", "AutoSaveWritePost" },
    callback = function(ev)
      if ev.event == "User" and ev.match ~= "AutoSaveWritePost" then
        return
      end
      if #bacon_clients() > 0 then
        M.sweep()
        M.check_shadow()
      end
      local buf = ev.event == "User" and ev.data and ev.data.saved_buffer or ev.buf
      if buf and vim.api.nvim_buf_is_valid(buf) then
        M.manifest_saved(vim.api.nvim_buf_get_name(buf), buf)
      end
    end,
  })

  local timer
  vim.api.nvim_create_autocmd("FocusGained", {
    group = group,
    callback = function()
      if #bacon_clients() == 0 and not orphan_rust_buffer() then
        return
      end
      if timer then
        timer:stop()
      else
        timer = assert(vim.uv.new_timer())
      end
      timer:start(
        300,
        0,
        vim.schedule_wrap(function()
          refresh()
        end)
      )
    end,
  })

  -- remember the HEAD bacon-ls started on
  vim.api.nvim_create_autocmd("LspAttach", {
    group = group,
    callback = function(ev)
      local c = vim.lsp.get_client_by_id(ev.data.client_id)
      local root = c and c.name == "bacon_ls" and c.config.root_dir
      if root and heads[root] == nil then
        heads[root] = git_head(root) or false
        manifests[root] = manifest_sig(root)
      end
    end,
  })
end'''),
    ...para('--', r'The save hook is a single autocmd on two events: the ordinary BufWritePost and the user event AutoSaveWritePost, which is needed because auto-save writes with noautocmd and so BufWritePost never fires for it (the same reason is given in disk_guard.lua). A trick in the registration deserves attention: the pattern list { "*", "AutoSaveWritePost" } serves both events, and a guard at the top of the callback drops any user event that is not AutoSaveWritePost. The buffer is the event’s buffer for a normal save and ev.data.saved_buffer for the user event. Every save sweeps and checks the shadow (two stats per client, per the comment) and then asks manifest_saved whether it was a manifest. The motive in the comment is that tmux has focus events off by default, so FocusGained alone would let the status say "clippy ok" for a deleted project until the next focus.'),
    ...para('--', r'The FocusGained hook returns at once when there is nothing to supervise (no bacon-ls client and no Rust buffer waiting for one), and otherwise arms a 300 ms debounce timer, so a flurry of focus events becomes one refresh. The LspAttach hook records the starting git HEAD and manifest signature for each new bacon-ls root, only the first time, so the first FocusGained does not misread the state at startup as a change; a repository with no .git directory is remembered as false.'),
    ...sec(r'design decisions and trade-offs'),
    ...pt('--', r'poll on events, not on a timer', r'there is no periodic check. Every check hangs on an event that already happens: a save, a focus, an exit, an attach.'),
    ...pt('--', r'signatures, not file watchers', r'mtime, inode, size and the HEAD file are compared with remembered values. A watcher would catch more, at the price of a handle per project and platform differences; a stat is portable and cheap.'),
    ...pt('--', r'every automatic action has a brake', r'three crashes in a minute stop the restarts; the manifest restart is debounced; the manifest mtime is recorded before the restart; the sweeps mark ids; Cargo.lock is watched only after a failure.'),
    ...pt('--', r'the sibling module holds the display', r'this file decides and acts, lsp_status.lua shows. They share one buffer variable and two function calls.'),
    ...sec(r'what differs in xyno-rust.nvim'),
    ...para('--', r'The standalone copy (lua/xyno_rust/rust_restart.lua, extracted on 2026-10-22) changes names and one option. The buffer variable is xyno_rust_stopped (this config writes xynovim_stopped), the augroup is xyno_rust_restart, the requires point at xyno_rust.lsp_status and xyno_rust.rust_context, and setup(opts) skips defining :RustRestart when opts.commands is false while still installing the supervision autocmds. The supervision logic is the same. The two copies cannot be mixed, since each reads and writes its own flag name.'),
    ...sec(r'a portability observation'),
    ...para('--', r'Several checks in this file only accept a root or file name that starts with a slash: root:sub(1, 1) == "/" in check_shadow (line 170), in orphan_rust_buffer (lines 217 and 219) and in server_root (line 232). On Windows, paths begin with a drive letter, so those branches would never match there. The file was touched by the Windows and macOS portability commit (ff1c8fa), which changed the process-name handling for the .exe suffix and the SIGCONT skip, but these absolute-path tests were left as they are. This page describes what the code does; whether Windows behaviour is intended to be covered here is not stated in the file.'),
    ...sec(r'how it is tested'),
    ...para('--', r'tests/server-supervision-statusline_spec.lua (57 it() blocks) covers this module in four describes: setup and on_exit (the describe titles are in the file; their individual cases are not listed here), :RustRestart and the sweep, the VimLeavePre kill of servers that never initialised, and the FocusGained refresh. Its lsp_status sections drive the other half of the pair.'),
    ...sec(r'history'),
    ...pt('--', r'be73b6c · 2026-10-12', r'Rust workflow robustness: bacon-ls workspace root, server supervision. Creates the file.'),
    ...pt('--', r'98c9bb4 · 2026-10-13', r'Final loop round 1: "RustRestart SIGKILL".'),
    ...pt('--', r'a3d33c8 · 2026-10-13', r'Final loop round 2: "bacon-ls restart and Cargo.toml tracking", "quit during LSP start".'),
    ...pt('--', r'3f868dd · 2026-10-13', r'Final loop round 3: "bacon-ls virtual buffers/keep-going/manifest restart".'),
    ...pt('--', r'f31e013 · 2026-10-14', r'Final loop round 4: "sweep on save".'),
    ...pt('--', r'25086fd · 2026-10-14', r'Final loop round 5: "bacon-ls shadow restart", "SIGCONT at quit".'),
    ...pt('--', r'b9363cd · 2026-10-14', r'Macros and dependencies: the deps_begin hooks for the dependency indicator.'),
    ...pt('--', r'ff1c8fa · 2026-10-16', r'Windows and macOS: .exe suffix and signal handling.'),
  ],
);
