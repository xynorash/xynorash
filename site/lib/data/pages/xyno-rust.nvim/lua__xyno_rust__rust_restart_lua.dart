import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-rust.nvim/lua/xyno_rust/rust_restart.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'rust_restart.lua - a supervisor for two language servers'),
    cm('--', r'restart the dead, refresh the stale, never orphan a process'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'keeps rust-analyzer and bacon-ls alive and in sync with the disk'),
    kv(r'language', r'Lua (libuv timers, LSP lifecycle, process signals)'),
    kv(r'size', r'486 lines; the longest-lived ancestor in xynovim, from be73b6c (2026-10-12) to ff1c8fa (2026-10-16)'),
    kv(r'command', r':RustRestart'),
    kv(r'autocmds', r'FileChangedShellPost, VimLeavePre, BufWritePost, User AutoSaveWritePost, FocusGained, LspAttach (group xyno_rust_restart)'),
    kv(r'tested by', r'tests/server-supervision-statusline_spec.lua (1,122 lines, shared with lsp_status)'),
    ...sec(r'why this file exists'),
    ...para('--', r'The header lists six situations (bullets) in which a Rust setup with two servers can quietly stop telling the truth; the comments in the file mark several of them as field-test findings, and each bullet maps to a mechanism below.'),
    ...code('lua', r'lua/xyno_rust/rust_restart.lua · lines 1-23', r'''
-- Keeps the two Rust servers alive and fresh.
--   * A server that dies (kill -9, OOM, a crash) is restarted automatically,
--     at most 3 times a minute, and shows as "RA stopped" / "clippy stopped"
--     in the statusline until it is back (lsp_status.lua). Neither
--     `:RustAnalyzer restart` nor `:lsp restart` can revive a dead client.
--   * :RustRestart restarts both by hand (also when one is already dead).
--   * bacon-ls hardlinks the workspace into a shadow once and re-syncs only
--     the files nvim reports, so an atomic replace from outside (`sed -i`,
--     `git checkout`/`pull`, an agent rewriting files) leaves clippy checking
--     the old content. On FocusGained, bacon-ls is restarted when a Rust or
--     Cargo file open in nvim was reloaded from disk, or the git HEAD of its
--     workspace moved, or its Cargo.toml changed on disk.
--   * A Cargo.toml or Cargo.lock SAVED from nvim (BufWritePost or auto-save's
--     AutoSaveWritePost) restarts bacon-ls 500 ms after the last save of a burst: it keeps
--     reporting "cannot find crate" for a dependency just added until restarted (measured
--     minutes), and its shadow workspace holds the old manifest. The statusline shows
--     "deps resolving" meanwhile (lsp_status.deps_begin). A `cargo add` in a terminal
--     reaches the same restart through the FocusGained path above (manifest mtime).
--     Loop guard: the restart records the new manifest mtime, so the next FocusGained does
--     not restart again; bacon-ls writes buffer text only into its shadow, never to the
--     workspace, so the restart cannot trigger another save.
--   * bacon-ls clients whose workspace directory no longer exists are stopped.
local M = {}'''),
    ...para('--', r'The first bullet is about death. A server killed with kill -9, or by the OOM killer, leaves a dead client behind and the header states why the usual commands do not help: neither :RustAnalyzer restart nor :lsp restart can revive a dead client. The next bullets are about staleness. bacon-ls hardlinks the workspace into a shadow copy once and re-syncs only the files Neovim reports, so a change from outside (sed -i, git checkout, an agent rewriting files) leaves clippy checking the old content. Another is about dependencies: after a save of Cargo.toml bacon-ls goes on reporting "cannot find crate" for a dependency just added, the header says “measured minutes”. The last bullet covers cleaning up clients for directories that no longer exist.'),
    ...sec(r'bookkeeping tables'),
    ...code('lua', r'lua/xyno_rust/rust_restart.lua · lines 25-32', r'''
local starts = {} -- name -> os.time() of the automatic restarts in the last minute
local disk_changed = false
local heads = {} -- workspace root -> git HEAD signature when last looked at
local manifests = {} -- workspace root -> Cargo.toml mtime when last looked at
local lives = {} -- workspace root -> identity of target/bacon-ls-live when last looked at
local locks = {} -- workspace root -> Cargo.lock signature (kept while clippy is not failed)
local swept = {} -- client ids stopped by sweep(): their exit is not a crash
local SERVER_EXES = { ["rust-analyzer"] = true, ["bacon-ls"] = true }'''),
    ...para('--', r'The module state is six tables keyed by name or workspace root: restart timestamps in the last minute, a disk-changed flag, the git HEAD signature, the manifest mtime, the identity of target/bacon-ls-live and the Cargo.lock signature. Nothing is persisted. The swept table has a purpose that shows up in on_exit: clients the module stopped on purpose must not be mistaken for crashes.'),
    ...sec(r'starting what died'),
    ...code('lua', r'lua/xyno_rust/rust_restart.lua · lines 38-59', r'''
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
    ...para('--', r'start is asymmetrical on purpose. For bacon-ls it goes through vim.lsp.enable, and the comment records a trap: enabling an already enabled config is a no-op, so a bacon-ls that died stayed dead in headless nvim (the field test’s kill -9). If no client is left, the config is first disabled and then enabled, which re-attaches the buffers. For rust-analyzer the module asks rustaceanvim (rustaceanvim.lsp.start) per buffer that lost its client, and returns quietly when rustaceanvim is not installed, because this module never configures the servers itself.'),
    ...sec(r'on_exit: restart with a leash'),
    ...code('lua', r'lua/xyno_rust/rust_restart.lua · lines 61-103', r'''
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
          local flags = vim.b[b].xyno_rust_stopped or {}
          flags[name] = true
          vim.b[b].xyno_rust_stopped = flags
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
    ...para('--', r'on_exit(name) returns the callback the user wires into the server config, as the README shows. A clean exit (code 0 and signal 0: a graceful stop, :lsp restart, quitting Neovim) and a swept client are ignored. Otherwise the callback runs in a fast event, where most of the API is off limits, so it reads the attached buffers immediately (they are detached on the next tick) and does the rest in vim.schedule. It sets the buffer variable xyno_rust_stopped for each buffer, which is what turns the statusline into "RA stopped"; it does nothing more while Neovim is exiting; and it applies the leash: the timestamps of automatic restarts in the last 60 seconds are kept, and when three restarts are already recorded in that window, the next exit makes the module give up with an ERROR that names the exit code and signal and says :RustRestart tries again. Otherwise it records the time, warns that the server exited and is restarting, and starts it 500 ms later, because the dead client is only dropped from the client list a tick afterwards. This is the “at most 3 times a minute” rule of the header and the README: three automatic restarts are allowed in a 60-second window.'),
    ...sec(r'the shadow problem'),
    ...code('lua', r'lua/xyno_rust/rust_restart.lua · lines 118-160', r'''
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
end'''),
    ...para('--', r'The signatures are cheap fingerprints of the disk. git_head returns the commit that HEAD points to, or the HEAD text itself when detached, reading files rather than calling git. The comment on packed refs is honest about the limit: with packed refs only a branch switch shows. manifest_sig uses the mtime of Cargo.toml and deliberately not Cargo.lock: cargo and rust-analyzer create and rewrite the lock on their own, which had restarted bacon-ls for nothing. live_sig takes the inode and birth time of target/bacon-ls-live, because a cargo clean deletes the directory and bacon-ls recreates it with the same path and another identity.'),
    ...code('lua', r'lua/xyno_rust/rust_restart.lua · lines 161-193', r'''
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
      if not require("xyno_rust.lsp_status").bacon_failed(c.id) then
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
    ...para('--', r'check_shadow runs on a save. It restarts bacon-ls in two cases that both came from field tests: target/bacon-ls-live was wiped under a running bacon-ls (which then never reported a new error while the status said clippy ok), and Cargo.lock was repaired or deleted while clippy has failed, where the shadow kept the bad hardlinked lock. The second condition is watched only in the failed state because cargo rewrites the lock itself all the time. Note the guard root:sub(1, 1) == "/": only absolute POSIX paths are checked, which is the reason the README says that on Windows these parts do nothing.'),
    ...sec(r'manifest saved'),
    ...code('lua', r'lua/xyno_rust/rust_restart.lua · lines 239-277', r'''
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
  require("xyno_rust.lsp_status").deps_begin(root, buf)
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
    ...para('--', r'manifest_saved is the "deps resolving" half. On a save of Cargo.toml or Cargo.lock below a server root it tells lsp_status to show the transient state, and restarts bacon-ls once per burst: a libuv timer is stopped and re-armed on each save, so ten saves in a row cause one restart 500 ms after the last. Just before restarting it records the manifest mtimes it is about to react to, so the next FocusGained does not restart again. This is the loop guard from the header, and the header adds the argument for why it cannot loop: bacon-ls writes buffer text only into its shadow, never to the workspace, so the restart cannot trigger another save.'),
    ...sec(r'focus: what changed while Neovim was in the background'),
    ...code('lua', r'lua/xyno_rust/rust_restart.lua · lines 279-312', r'''
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
        require("xyno_rust.lsp_status").deps_begin(root) -- cargo add in a terminal: same transient as a save
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
    ...para('--', r'refresh runs 300 ms after FocusGained (debounced by another timer). It sweeps dead workspaces, revives bacon-ls for a Rust buffer whose manifest is back after being away, runs checktime so unmodified buffers reload, and then looks for reasons to restart: the git HEAD moved, or the Cargo.toml mtime differs from the remembered one (a cargo add in a terminal), which also starts the deps resolving display, since it is the same transient. A vanished manifest is sweep’s business, not a reason to restart every client (the comment says so). The disk_changed flag is set by FileChangedShellPost for relevant files (.rs, .toml, .lock under a bacon-ls root), which is how "a buffer was reloaded from disk" is detected.'),
    ...sec(r'leaving without orphans'),
    ...code('lua', r'lua/xyno_rust/rust_restart.lua · lines 327-376', r'''
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
    ...para('--', r'Two VimLeavePre cases, both measured. A rust-analyzer or bacon-ls that has not answered initialize never completes the shutdown handshake when Neovim quits right after opening a file, and was left behind with PPID 1; the comment says it was seen under load, 1 of 40 quits. kill_uninitialised stops those and kills them with SIGKILL, finding the pids as children of this Neovim by executable name, since vim.lsp.rpc exposes no pid. The second: a server stopped with SIGSTOP does not act on SIGTERM, so resume_servers sends SIGCONT first (harmless for a running one, skipped on Windows). kill_survivors is the same idea for :RustRestart: after a delay (3 s by default) any listed process still alive under the same name gets SIGKILL, and its exit lets on_exit start a fresh one.'),
    ...sec(r'the manual command'),
    ...code('lua', r'lua/xyno_rust/rust_restart.lua · lines 378-400', r'''
function M.restart()
  require("xyno_rust.lsp_status").deps_clear()
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
    vim.b[b].xyno_rust_stopped = nil
  end
  vim.notify("restarting rust-analyzer and bacon-ls")
end'''),
    ...para('--', r':RustRestart clears the deps state, sweeps, schedules the survivors for SIGKILL and restarts each server by the route that works for its state: RustAnalyzer restart if a client exists, otherwise start; lsp restart bacon_ls if a client exists, otherwise start. The stopped flags are cleared so the statusline recovers at once.'),
    ...sec(r'setup'),
    ...code('lua', r'lua/xyno_rust/rust_restart.lua · lines 403-448', r'''
function M.setup(opts)
  local group = vim.api.nvim_create_augroup("xyno_rust_restart", { clear = true })

  if not (opts and opts.commands == false) then
    vim.api.nvim_create_user_command("RustRestart", M.restart, {
      desc = "Restart rust-analyzer and bacon-ls (also when one has died)",
    })
  end

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
  })

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
  })'''),
    ...para('--', r'One augroup, cleared on every setup call. The save autocommand listens to BufWritePost for every file and to the User event AutoSaveWritePost, which an auto-save plugin fires; for that event it takes the saved buffer from ev.data.saved_buffer. The comment above it explains the cost model: a save is cheap to hook, two stats per client, and it catches a project directory moved or deleted under a running Neovim where FocusGained may never fire (tmux has focus-events off by default).'),
    ...sec(r'design decisions and trade-offs'),
    ...pt('--', r'timestamps instead of counters', r'the three-in-a-minute window is a filtered list, so old crashes expire without a timer.'),
    ...pt('--', r'fingerprints instead of file watchers', r'mtimes, inodes and HEAD are compared on events Neovim already has (focus, save). Nothing watches the file system, so nothing runs at idle.'),
    ...pt('--', r'kill is the last resort', r'graceful restart first, SIGKILL only for processes that are still alive after a delay and still have the same name.'),
    ...pt('--', r'POSIX only for the shadow logic', r'the absolute-path guards make the shadow checks inert on Windows; the README says so.'),
    ...sec(r'how it is tested'),
    ...para('--', r'The spec has four describe blocks for this module: "setup and on_exit", ":RustRestart and sweep", "VimLeavePre kill of servers that never initialised" and "FocusGained refresh". The README states what is missing: the original specs killed live bacon-ls and rust-analyzer processes (kill -9, SIGSTOP, repeated quick kills), and those were not ported, so this repository has no real-process spec for the restart logic.'),
    ...sec(r'history'),
    ...para('--', r'be73b6c (2026-10-12) created the supervision ("auto-restart of dead servers, :RustRestart, FocusGained refresh"). Round 1 to 5 of the field tests (98c9bb4, a3d33c8, 3f868dd, f31e013, 25086fd, 2026-10-13 and 14) added the RustRestart SIGKILL, the bacon-ls restart on Cargo.toml tracking, the sweep on save and the shadow restart. b9363cd (2026-10-14) added the deps_begin calls and ff1c8fa (2026-10-16) the portability guards. Copied into this repository in c1c7958 with the group renamed xyno_rust_restart.'),
  ],
);
