import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/lua/config/lsp_status.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'lsp_status.lua — are the Rust servers ready, and can I trust the red squiggles?'),
    cm('--', r'one statusline string for rust-analyzer, bacon-ls and "deps resolving"'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'event-driven server-readiness state, rendered by lualine'),
    kv(r'language', r'Lua; LSP handlers, LspProgress/LspAttach autocmds, nvim_buf_attach'),
    kv(r'size', r'344 lines, 6 commits (bdd0225 on 2026-10-09 to ff1c8fa on 2026-10-16)'),
    kv(r'states', r'RA starting / loading / ready / ready (warn) / error / detached / stopped; clippy running / failed / stale / ok / NE / stopped; deps resolving'),
    kv(r'consumed by', r'lua/plugins/lualine.lua (component), rust_restart.lua (deps_begin, deps_clear, bacon_failed)'),
    kv(r'also lives in', r'xyno-rust.nvim (lua/xyno_rust/lsp_status.lua), with renamed identifiers only'),
    ...sec(r'why this file exists'),
    ...para('--', r'A Rust workflow here has two language servers in every buffer. rust-analyzer does the navigation, types and its own diagnostics; bacon-ls runs clippy in the background and publishes lints. Both are slow in different ways. For the first minute of a session rust-analyzer is loading the workspace and its diagnostics are incomplete. bacon-ls reports a clippy result that is only true for the text as it was when the run started. Both facts matter to anyone reading the squiggles, and neither is visible by default. This file turns them into a short string in the statusline: "RA ready | clippy ok", "RA indexing 42% | clippy running", "clippy stale".'),
    ...para('--', r'The header comment states the design rule first: the module is "purely event driven (LspProgress, experimental/serverStatus, window/showMessage, TextChanged) - nothing runs at idle". The one exception is the "deps resolving" indicator, which arms a six-second grace timer and a 120-second ceiling while it is visible. The file grew by accretion from the first version in bdd0225 ("Roadmap step 11 wip: status, UX, health, CI, hygiene", 2026-10-09) through field-test fixes to the dependency indicator added by b9363cd (2026-10-14).'),
    ...sec(r'the state it keeps'),
    ...code('lua', r'lua/config/lsp_status.lua · lines 23-66', r'''
local DEPS_GRACE_MS, DEPS_TIMEOUT_MS = 6000, 120000
---@type table<string, { buf: integer?, busy: boolean, token: table }>
local deps = {} -- workspace root -> pending resolution

---@type table<integer, { tokens: table<string, table>, last: string?, health: string?, quiescent: boolean?, message: string?, failed: boolean?, begin_ticks: table<integer, integer>?, ticks: table<integer, integer>?, wrapped: boolean? }>
local state = {}

local function st(id)
  state[id] = state[id] or { tokens = {} }
  return state[id]
end

--- buf -> number of text changes seen since the buffer was first attached.
--- Only ever grows: the remembered tick of the last clippy run is compared to
--- it, and a counter that restarted at 0 after `:edit!` (which detaches the
--- buffer) hid "stale" for the next N edits.
---@type table<integer, integer>
local edits = {}
---@type table<integer, boolean>
local counting = {}

local function count_edits(buf)
  if counting[buf] then
    return
  end
  counting[buf] = true
  edits[buf] = edits[buf] or 0
  local function bump()
    edits[buf] = (edits[buf] or 0) + 1
  end
  vim.api.nvim_buf_attach(buf, false, {
    on_lines = bump,
    on_reload = bump,
    on_detach = function()
      counting[buf] = nil
    end,
  })
end

local function redraw()
  vim.schedule(function()
    vim.cmd.redrawstatus()
  end)
end'''),
    ...para('--', r'There are three tables. state is keyed by LSP client id and holds, for one client, the open progress tokens, which one is the newest, the health and quiescent flags from rust-analyzer’s status report, a failed flag for bacon-ls, and two maps of edit counters. deps is keyed by workspace root and holds a pending "deps resolving" wait. edits counts text changes per buffer.'),
    ...para('--', r'The edit counter is a good example of a bug turned into a rule. The comment on it records two earlier mistakes. The natural tool, b:changedtick, is bumped by a write as well as by an edit, so every auto-save left "stale" on the screen forever; that is why the counter is built with nvim_buf_attach, which only fires for text changes (on_lines and on_reload). And the counter is never reset: after :edit! the buffer is detached, a counter that restarted at zero hid "stale" for the next N edits, because the remembered tick of the last clippy run would be larger than the new count. So the counter only ever grows, and counting[buf] is cleared on detach so that re-attaching is possible without losing the number. redraw() is scheduled because statusline redraws cannot be requested from inside a fast event.'),
    ...sec(r'the rust-analyzer string'),
    ...code('lua', r'lua/config/lsp_status.lua · lines 68-108', r'''
--- "Indexing 42%" / "Fetching" for the newest progress item of a client.
local function progress_text(s)
  local p = s.last and s.tokens[s.last]
  if not p then
    return nil
  end
  local text = p.title or p.message or "working"
  if p.percentage then
    text = text .. " " .. p.percentage .. "%"
  end
  return text
end

--- True when the server `name` exited under this buffer (see rust_restart.lua).
local function stopped(bufnr, name)
  local flags = vim.b[bufnr].xynovim_stopped
  return flags ~= nil and flags[name] == true
end

function M.rust_analyzer(bufnr)
  local c = vim.lsp.get_clients({ bufnr = bufnr or 0, name = "rust-analyzer" })[1]
  if not c then
    return stopped(bufnr or 0, "rust-analyzer") and "RA stopped" or nil
  end
  local s = st(c.id)
  local busy = progress_text(s)
  if s.quiescent == nil then
    return "RA " .. (busy or "starting")
  elseif not s.quiescent or busy then
    return "RA " .. (busy or "loading")
  elseif s.health == "error" then
    -- a standalone script (rust-script, a lone .rs): no workspace to load is not a failure
    if (s.message or ""):find("Failed to discover workspace", 1, true) then
      return "RA detached"
    end
    return "RA error"
  elseif s.health == "warning" then
    return "RA ready (warn)"
  end
  return "RA ready"
end'''),
    ...para('--', r'This is a small decision tree over what the server has said. If no rust-analyzer client is attached to the buffer, the answer is nil (hide it) unless a flag says the server exited under this buffer, in which case it is "RA stopped". The flag is a buffer variable that rust_restart.lua writes and this file reads, which is how the supervision module and the display communicate without requiring each other at load time. With a client: if it has never sent a status report, the state is "starting", suffixed with the newest progress title when there is one. Once reports exist, a quiescent value of false, or any open progress item, means "loading" or the item itself (for instance "Indexing 42%"). A quiescent server is "ready"; health error becomes "RA error" and health warning "RA ready (warn)".'),
    ...para('--', r'There is one special case, explained in a comment. When the buffer is a standalone script (rust-script, a lone .rs file) there is no workspace to load, and rust-analyzer reports an error whose message contains "Failed to discover workspace". That is not a failure of the setup, so it is shown as "RA detached". The check is a plain-text find on the message, the only signal the server gives.'),
    ...sec(r'the bacon-ls string'),
    ...code('lua', r'lua/config/lsp_status.lua · lines 110-139', r'''
--- Whether the last bacon-ls run of client `id` failed (cargo exited with an error).
function M.bacon_failed(id)
  return st(id).failed == true
end

function M.bacon(bufnr)
  local c = vim.lsp.get_clients({ bufnr = bufnr or 0, name = "bacon_ls" })[1]
  if not c then
    return stopped(bufnr or 0, "bacon_ls") and "clippy stopped" or nil
  end
  local s = st(c.id)
  if next(s.tokens) then
    return "clippy running"
  elseif s.failed then
    return "clippy failed"
  end
  local buf = bufnr and bufnr ~= 0 and bufnr or vim.api.nvim_get_current_buf()
  local seen = s.ticks and s.ticks[buf]
  if seen and (edits[buf] or 0) > seen then
    return "clippy stale"
  end
  -- "ok" meant "finished", also with errors on screen: say how many
  local ERROR = vim.diagnostic.severity.ERROR
  local has_ns, ns = pcall(vim.lsp.diagnostic.get_namespace, c.id)
  local errors = has_ns and vim.api.nvim_buf_is_valid(buf) and vim.diagnostic.count(buf, { namespace = ns, severity = ERROR })[ERROR] or 0
  if errors > 0 then
    return ("clippy %dE"):format(errors)
  end
  return "clippy ok"
end'''),
    ...para('--', r'The bacon-ls order is: any open progress token means "clippy running" (bacon-ls reports each run as $/progress); a failed flag means "clippy failed"; then the staleness test; then the result. The staleness test compares two numbers. When a run begins, the handler (below) stores for every attached buffer the current edit count in begin_ticks, and when the run ends it commits them as ticks. If the buffer’s edit count is now larger than the tick of the last finished run, the clippy diagnostics on screen are older than the text, which is exactly "stale". The last step says how many errors are on screen. The comment states the motive: "ok" had meant "finished", also with errors on screen, which made a green word sit beside red lines. The count is of ERROR-severity diagnostics in bacon-ls’s own namespace, looked up in a pcall since the namespace may not exist yet. M.bacon_failed(id) is the public read of the failed flag; rust_restart.lua calls it at line 177.'),
    ...sec(r'"deps resolving": a transient that must never stick'),
    ...code('lua', r'lua/config/lsp_status.lua · lines 141-221', r'''
--- Whether some rust-analyzer client that covers `root` is idle (quiescent) right now.
local function ra_idle(root)
  local any = false
  for _, c in ipairs(vim.lsp.get_clients({ name = "rust-analyzer" })) do
    local r = require("config.fsutil").slash(c.config and c.config.root_dir)
    if not r or root:sub(1, #r + 1) == r .. "/" or r:sub(1, #root + 1) == root .. "/" or r == root then
      any = true
      if state[c.id] == nil or state[c.id].quiescent ~= true then
        return false
      end
    end
  end
  return any
end

--- Ends the pending resolution of `root` (all of them without argument).
function M.deps_clear(root)
  if root then
    deps[root] = nil
  else
    deps = {}
  end
  redraw()
end

--- A Cargo.toml/Cargo.lock under `root` was saved: show "deps resolving" until
--- rust-analyzer has reloaded the workspace. Never sticks: see the header.
---@param root string workspace root
---@param buf integer? the manifest buffer (its wipe ends the wait)
function M.deps_begin(root, buf)
  local token = {}
  local busy = false
  for _, c in ipairs(vim.lsp.get_clients({ name = "rust-analyzer" })) do
    if state[c.id] and state[c.id].quiescent == false then
      busy = true -- already loading: its next quiescent=true is the end
    end
  end
  deps[root] = { buf = buf, busy = busy, token = token }
  local function alive()
    return deps[root] and deps[root].token == token
  end
  vim.defer_fn(function()
    if alive() and not deps[root].busy and (ra_idle(root) or #vim.lsp.get_clients({ name = "rust-analyzer" }) == 0) then
      M.deps_clear(root)
    end
  end, DEPS_GRACE_MS)
  vim.defer_fn(function()
    if alive() then
      M.deps_clear(root)
    end
  end, DEPS_TIMEOUT_MS)
  redraw()
end

--- "deps resolving" while a manifest below which `bufnr`'s file lives is being resolved.
function M.deps(bufnr)
  if next(deps) == nil then
    return nil
  end
  local name = require("config.fsutil").slash(vim.api.nvim_buf_get_name(bufnr or 0))
  for root in pairs(deps) do
    if name:sub(1, #root + 1) == root .. "/" then
      return "deps resolving"
    end
  end
  return nil
end

--- rust-analyzer reported its status: ends the waits it has finished.
local function deps_status(client, quiescent)
  for root, d in pairs(deps) do
    local r = require("config.fsutil").slash(client.config and client.config.root_dir)
    if not r or root:sub(1, #r + 1) == r .. "/" or r:sub(1, #root + 1) == root .. "/" or r == root then
      if quiescent == false then
        d.busy = true
      elseif quiescent == true and d.busy then
        M.deps_clear(root)
      end
    end
  end
end'''),
    ...para('--', r'When you add a dependency to Cargo.toml and save, for a while both servers do not know the new crate. Code that uses it shows a red "cannot find crate" that is wrong and disappears by itself. The header explains the indicator: "deps resolving" appears from the save of a Cargo.toml or Cargo.lock until rust-analyzer’s workspace load finishes, so the user knows the red is transient. rust_restart.lua calls deps_begin on those saves (lines 252 and 301 there).'),
    ...para('--', r'A status line that says "busy" and then never says "idle" is worse than none, so the header lists the five ways the wait ends: at the first quiescent=true report after a busy one; six seconds after the write when rust-analyzer never went busy (nothing needed reloading, the common case for a save that changed only a comment); at 120 seconds regardless; on a restart (deps_clear is called there); or when the manifest buffer is wiped. Look at how deps_begin implements that. It records busy as true if some client is already not quiescent, because then its next quiescent=true is the end. It stores a fresh token table, and both timers close over it; alive() checks that the wait for this root is still the one that was started. So a later save, which replaces deps[root] with a new token, makes the older timers harmless without any cancellation. The grace timer clears the wait only if the wait never went busy and the covering rust-analyzer is idle or absent.'),
    ...para('--', r'The ancestry test is repeated in ra_idle and deps_status: a client covers a root if the client’s root is a prefix of the root, the root is a prefix of the client’s (a workspace member inside a bigger workspace, or the other way round), or they are equal. Both sides are passed through fsutil.slash, which is the reason that module exists on Windows; a client with no root_dir counts as covering everything. M.deps(bufnr) is the display side: the string appears only for buffers whose file lives below a root that is pending.'),
    ...sec(r'wiring: handlers and autocmds'),
    ...code('lua', r'lua/config/lsp_status.lua · lines 223-283', r'''
--- Combined lualine string ("" hides the component outside Rust buffers).
function M.component()
  local parts = {}
  for _, f in ipairs({ M.deps, M.rust_analyzer, M.bacon }) do
    parts[#parts + 1] = f()
  end
  return table.concat(parts, " | ")
end

function M.setup()
  local group = vim.api.nvim_create_augroup("xynovim_lsp_status", { clear = true })

  vim.api.nvim_create_autocmd("LspAttach", {
    group = group,
    callback = function(ev)
      local client = vim.lsp.get_client_by_id(ev.data.client_id)
      if not client then
        return
      end
      -- a restarted/attached server is no longer "stopped"
      local flags = vim.b[ev.buf].xynovim_stopped
      if flags and flags[client.name] then
        flags[client.name] = nil
        vim.b[ev.buf].xynovim_stopped = flags
      end
      if client.name == "bacon_ls" then
        local s = st(client.id)
        s.ticks = s.ticks or {}
        count_edits(ev.buf)
        s.ticks[ev.buf] = s.ticks[ev.buf] or edits[ev.buf]
        if not s.wrapped then
          s.wrapped = true
          local orig = client.handlers["window/showMessage"] or vim.lsp.handlers["window/showMessage"]
          client.handlers["window/showMessage"] = function(err, result, ctx, config)
            -- type 1 = Error: "cargo exited with exit status: 101: ..."
            if result and result.type == vim.lsp.protocol.MessageType.Error then
              s.failed = true
              redraw()
            end
            if orig then
              return orig(err, result, ctx, config)
            end
          end
        end
      elseif client.name == "rust-analyzer" and not st(client.id).wrapped then
        local s = st(client.id)
        s.wrapped = true
        local orig = client.handlers["experimental/serverStatus"] or vim.lsp.handlers["experimental/serverStatus"]
        client.handlers["experimental/serverStatus"] = function(err, result, ctx, config)
          if result then
            s.health, s.quiescent, s.message = result.health, result.quiescent, result.message
            deps_status(client, result.quiescent)
            redraw()
          end
          if orig then
            return orig(err, result, ctx, config)
          end
        end
      end
    end,
  })'''),
    ...para('--', r'M.component() joins the three parts that are not nil, with " | ". A nil result assigns nothing to parts[#parts + 1], so it is skipped, and outside a Rust buffer the result is the empty string, and lualine.lua uses that: its cond hides the component whenever component() returns "". The component lives at the front of the lualine_x section.'),
    ...para('--', r'The LspAttach handler does three jobs. It clears the "stopped" flag for the server that has just attached, so a restarted server is no longer reported as stopped. For bacon-ls it starts the edit counter for the buffer and gives it an initial tick, then wraps the client’s window/showMessage handler once (s.wrapped guards against wrapping again for a second buffer). The wrapper marks the run as failed when an Error-type message arrives, whose example text is in the comment: "cargo exited with exit status: 101". This is the one way bacon-ls tells you the manifest is broken: per the header, when cargo cannot run at all the server ends the run normally and only sends an error message. Then it calls the original handler, so the user still sees the message. For rust-analyzer it wraps experimental/serverStatus the same way. The header gives the reason: rustaceanvim handles that notification itself but keeps no state, so wrapping once on attach is the way to read it without replacing it. The wrapper stores health, quiescent and message, tells the dependency tracker, redraws and delegates.'),
    ...code('lua', r'lua/config/lsp_status.lua · lines 285-342', r'''
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = group,
    callback = function(ev)
      for root, d in pairs(deps) do
        if d.buf == ev.buf then
          M.deps_clear(root)
        end
      end
    end,
  })

  vim.api.nvim_create_autocmd("LspProgress", {
    group = group,
    callback = function(ev)
      local client = vim.lsp.get_client_by_id(ev.data.client_id)
      if not (client and (client.name == "rust-analyzer" or client.name == "bacon_ls")) then
        return
      end
      local s = st(client.id)
      local token, v = tostring(ev.data.params.token), ev.data.params.value
      if v.kind == "end" then
        s.tokens[token] = nil
        if s.last == token then
          s.last = next(s.tokens)
        end
        -- the finished run saw every buffer as of its begin
        if client.name == "bacon_ls" and not next(s.tokens) and s.begin_ticks then
          s.ticks = s.begin_ticks
        end
      else
        if v.kind == "begin" and client.name == "bacon_ls" then
          s.failed = false
          s.begin_ticks = {}
          for b in pairs(client.attached_buffers) do
            s.begin_ticks[b] = edits[b] or 0
          end
        end
        local p = s.tokens[token] or {}
        p.title = v.title or p.title
        p.message = v.message or p.message
        p.percentage = v.percentage or p.percentage
        s.tokens[token] = p
        s.last = token
      end
      redraw()
    end,
  })

  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    group = group,
    callback = function(ev)
      -- "stale" is derived from the edit counter when drawn
      if #vim.lsp.get_clients({ bufnr = ev.buf, name = "bacon_ls" }) > 0 then
        redraw()
      end
    end,
  })
end'''),
    ...para('--', r'LspProgress is a native Neovim event and is the engine of the progress display. Each event carries a token and a value of kind begin, report or end. For begin and report the module merges title, message and percentage into a record per token (keeping old values when a report omits them) and remembers the newest token as last. For end it deletes the token and, if it was the newest one, falls back to whatever token is left. When the last bacon-ls token ends, the begin_ticks captured at the start of that run become the committed ticks: "the finished run saw every buffer as of its begin". A new bacon-ls run also resets failed to false, so a fixed manifest clears "clippy failed" without any other action. The last autocmd only schedules a redraw on edits in buffers that have bacon-ls attached, because the "stale" word is computed at draw time from the counter and just needs a refresh.'),
    ...sec(r'design decisions and trade-offs'),
    ...pt('--', r'wrap the handler, do not replace it', r'both wrappers call the handler that was there before (the client’s own or the global default). The statusline learns about the server without changing what the server’s owner does with the same message.'),
    ...pt('--', r'counters instead of timestamps', r'staleness is a comparison of two integers. An integer comparison says "the text changed after the run started" without involving any clock.'),
    ...pt('--', r'strings, not highlights', r'each function returns a plain string. The unit tests can assert on text, and the component needs no theme knowledge.'),
    ...pt('--', r'timers only for the one thing that needs them', r'event-driven everywhere except "deps resolving", where a missing event (RA never going busy) would leave the indicator up. The two timers are the guard against that, and the token makes them safe against overlapping saves.'),
    ...sec(r'what differs in xyno-rust.nvim'),
    ...para('--', r'The plugin copy (lua/xyno_rust/lsp_status.lua, extracted on 2026-10-22) is the same code with renamed identifiers. A diff shows only these changes: the buffer variable xynovim_stopped is xyno_rust_stopped, the augroup xynovim_lsp_status is xyno_rust_lsp_status, and the fsutil requires point at xyno_rust.fsutil. The behaviour is identical. Because the buffer variable has a different name on each side, the two copies cannot be mixed: the config’s rust_restart.lua writes xynovim_stopped, which only the config’s lsp_status reads.'),
    ...sec(r'how it is tested'),
    ...para('--', r'tests/server-supervision-statusline_spec.lua (57 it() blocks) has a section "lsp_status (fake clients)" that drives the module with fake clients and LspProgress events, and a section "live servers" that runs the real rust-analyzer and bacon-ls. The same file covers rust_restart.lua: its on_exit handling, :RustRestart and the sweep, the VimLeavePre kill and the FocusGained refresh.'),
    ...sec(r'history'),
    ...pt('--', r'bdd0225 · 2026-10-09', r'Roadmap step 11 wip: status, UX, health, CI, hygiene. First version.'),
    ...pt('--', r'be73b6c · 2026-10-12', r'Rust workflow robustness: bacon-ls workspace root, server supervision, dap formatters/panic stop. The "stopped" state is read from the flag that rust_restart.lua sets.'),
    ...pt('--', r'98c9bb4 · 2026-10-13', r'Final loop round 1: the commit message lists "statusline".'),
    ...pt('--', r'25086fd · 2026-10-14', r'Final loop round 5: includes "bacon-ls shadow restart".'),
    ...pt('--', r'b9363cd · 2026-10-14', r'Macros and dependencies: dependency freshness, and with it the deps resolving indicator.'),
    ...pt('--', r'ff1c8fa · 2026-10-16', r'Windows and macOS: the fsutil.slash calls.'),
  ],
);
