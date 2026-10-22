import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-rust.nvim/lua/xyno_rust/lsp_status.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'lsp_status.lua - is the analysis I am looking at current?'),
    cm('--', r'an event-driven statusline for rust-analyzer and bacon-ls'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'readiness indicator: "RA ready | clippy ok", "RA indexing 42% | clippy stale", "deps resolving"'),
    kv(r'language', r'Lua'),
    kv(r'size', r'344 lines; ancestor bdd0225 (2026-10-09, "Roadmap step 11 wip: status, UX, health, CI, hygiene")'),
    kv(r'public', r'component(), rust_analyzer(buf), bacon(buf), deps(buf), bacon_failed(id), deps_begin(root, buf), deps_clear(root), setup()'),
    kv(r'tested by', r'tests/server-supervision-statusline_spec.lua'),
    ...sec(r'why this file exists'),
    ...para('--', r'Two servers, two different kinds of "not ready". rust-analyzer is starting, indexing or ready, and it carries a health that can be warning or error. bacon-ls runs clippy in the background after edits, so what is on screen may be fresh, running, failed, or older than your last keystroke. A developer who sees a red squiggle needs to know whether it is real or merely stale, and one who sees nothing needs to know whether that means the code is clean or the server is still thinking. The comment at the top of the file is a specification, and the rest is its implementation.'),
    ...code('lua', r'lua/xyno_rust/lsp_status.lua · lines 1-21', r'''
-- Server-readiness indicator for the statusline: rust-analyzer (starting /
-- indexing N% / ready, plus its health) and bacon-ls (clippy running / failed
-- / stale / fresh). Purely event driven (LspProgress, experimental/serverStatus,
-- window/showMessage, TextChanged) - nothing runs at idle. The one exception is
-- "deps resolving" (below), which arms a grace timer and a 120 s ceiling while it is shown.
--
-- rustaceanvim handles experimental/serverStatus itself but keeps no state, so
-- the client's handler is wrapped once on attach. bacon-ls reports each clippy
-- run as $/progress; "stale" means the buffer's text changed after the last
-- finished run started, i.e. the clippy diagnostics on screen predate your
-- edit. Edits are counted with nvim_buf_attach (not b:changedtick, which a
-- write also bumps: every auto-save would have left "stale" up for good). When cargo cannot run at all (broken manifest, cyclic
-- dependency) bacon-ls ends the run normally and only sends an error
-- window/showMessage: that is "failed". "stopped" is a server that exited
-- (rust_restart.lua records it and restarts it).
-- "deps resolving" is shown from the save of a Cargo.toml/Cargo.lock (rust_restart.lua calls
-- deps_begin) until rust-analyzer's workspace load finishes: during that window the new
-- dependency is unknown to both servers and a red "cannot find crate" is transient. It ends
-- at the first quiescent=true report after a busy one, 6 s after the write when rust-analyzer
-- never went busy (nothing to reload), at 120 s, on a restart or when the buffer is wiped.
local M = {}'''),
    ...para('--', r'The header sentence that shapes the design is the second: purely event driven, nothing runs at idle. The one exception, a timer for "deps resolving", is bounded (a grace period and a ceiling).'),
    ...sec(r'the state model'),
    ...code('lua', r'lua/xyno_rust/lsp_status.lua · lines 23-60', r'''
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
end'''),
    ...para('--', r'State is kept per client id: the progress tokens in flight, the newest token, rust-analyzer health, the quiescent flag and the last message, whether the last bacon-ls run failed, and a pair of tick tables. Edits are counted by hand, with nvim_buf_attach callbacks on on_lines and on_reload, instead of reading b:changedtick. The header gives the reason: a write also bumps changedtick, so with auto-save every save would have left stale showing for good. The counter only grows, and the comment explains that too: after :edit! the buffer is detached, a counter that restarted from zero would hide "stale" for the next N edits, so on_detach only clears the counting flag and the number survives.'),
    ...sec(r'rust-analyzer text'),
    ...code('lua', r'lua/xyno_rust/lsp_status.lua · lines 68-108', r'''
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
  local flags = vim.b[bufnr].xyno_rust_stopped
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
    ...para('--', r'The function maps state to a short string. No state yet means "RA starting"; a loading workspace (quiescent false) or progress in flight shows the progress title and percentage ("RA Indexing 42%"); a settled server shows "RA ready", "RA ready (warn)" or "RA error". A stopped server (see rust_restart) shows "RA stopped" even though no client exists, which is why the check reads the buffer variable xyno_rust_stopped. One special case is documented in the code: a standalone script or lone .rs file makes rust-analyzer report an error "Failed to discover workspace", which is not a failure, so the label becomes "RA detached".'),
    ...sec(r'clippy text'),
    ...code('lua', r'lua/xyno_rust/lsp_status.lua · lines 110-139', r'''
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
    ...para('--', r'Priority order: running (a progress token is open), failed, stale, then the result. Stale is an inequality: the edit counter now is greater than the counter remembered for this buffer when the last finished run started. Note that the remembered value is the one at the start of the run, not at the end (see the LspProgress handler below), because the run saw the buffer as it was when it began. The last case was a bug fix recorded in a comment: "ok" used to mean "finished", also with errors on screen, so the function now counts ERROR diagnostics in the bacon-ls namespace and shows clippy 3E instead of clippy ok.'),
    ...sec(r'deps resolving'),
    ...para('--', r'Adding a dependency in Cargo.toml and saving makes both servers briefly report "cannot find crate" for code that uses it, until rust-analyzer has reloaded the workspace. The header calls the red “cannot find crate” transient, and the statusline shows “deps resolving” for that window. rust_restart calls deps_begin when a manifest is saved.'),
    ...code('lua', r'lua/xyno_rust/lsp_status.lua · lines 141-193', r'''
--- Whether some rust-analyzer client that covers `root` is idle (quiescent) right now.
local function ra_idle(root)
  local any = false
  for _, c in ipairs(vim.lsp.get_clients({ name = "rust-analyzer" })) do
    local r = require("xyno_rust.fsutil").slash(c.config and c.config.root_dir)
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
end'''),
    ...para('--', r'deps_begin records a pending resolution per workspace root with a unique token, and checks whether rust-analyzer is already busy. Two timers: after 6 seconds, if rust-analyzer never went busy and is idle (or no server exists), the wait ends, which covers a save that changed nothing the server had to reload; and after 120 seconds the wait ends no matter what. The alive function compares tokens, so a timer from an earlier save cannot clear the state of a later one. The natural end comes from the status handler: the first quiescent = true after a busy report.'),
    ...code('lua', r'lua/xyno_rust/lsp_status.lua · lines 195-230', r'''
--- "deps resolving" while a manifest below which `bufnr`'s file lives is being resolved.
function M.deps(bufnr)
  if next(deps) == nil then
    return nil
  end
  local name = require("xyno_rust.fsutil").slash(vim.api.nvim_buf_get_name(bufnr or 0))
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
    local r = require("xyno_rust.fsutil").slash(client.config and client.config.root_dir)
    if not r or root:sub(1, #r + 1) == r .. "/" or r:sub(1, #root + 1) == root .. "/" or r == root then
      if quiescent == false then
        d.busy = true
      elseif quiescent == true and d.busy then
        M.deps_clear(root)
      end
    end
  end
end

--- Combined lualine string ("" hides the component outside Rust buffers).
function M.component()
  local parts = {}
  for _, f in ipairs({ M.deps, M.rust_analyzer, M.bacon }) do
    parts[#parts + 1] = f()
  end
  return table.concat(parts, " | ")
end'''),
    ...para('--', r'The "deps resolving" text only shows in buffers whose file lives below the pending root. component joins deps, rust_analyzer and bacon with a separator and skips the empty ones; outside Rust buffers all three return nil and the component is an empty string, which lets lualine hide it.'),
    ...sec(r'hooking the servers'),
    ...code('lua', r'lua/xyno_rust/lsp_status.lua · lines 235-283', r'''
  vim.api.nvim_create_autocmd("LspAttach", {
    group = group,
    callback = function(ev)
      local client = vim.lsp.get_client_by_id(ev.data.client_id)
      if not client then
        return
      end
      -- a restarted/attached server is no longer "stopped"
      local flags = vim.b[ev.buf].xyno_rust_stopped
      if flags and flags[client.name] then
        flags[client.name] = nil
        vim.b[ev.buf].xyno_rust_stopped = flags
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
    ...para('--', r'On LspAttach the module does three things. It clears the stopped flag for the client that just attached, so a restarted server stops being "stopped". For bacon-ls it initialises the tick table, starts counting edits for the buffer and wraps window/showMessage once: an error message (type 1, the comment quotes "cargo exited with exit status: 101") sets failed, because when cargo cannot run at all, bacon-ls ends the run normally and only sends this message. For rust-analyzer it wraps experimental/serverStatus once. The header says why: rustaceanvim handles that notification itself but keeps no state. Both wrappers call the original handler afterwards, so nothing that rustaceanvim or Neovim does with the message is lost.'),
    ...code('lua', r'lua/xyno_rust/lsp_status.lua · lines 296-331', r'''
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
  })'''),
    ...para('--', r'LspProgress feeds the token table. An end removes the token and, once the last token of bacon-ls is gone, publishes the begin-time edit counters as the new baseline: the finished run saw every buffer as of its begin. A begin on bacon-ls clears the failed flag and snapshots the counters of all attached buffers. TextChanged only triggers a redraw when bacon-ls is attached to the buffer; stale itself is computed when drawn. Every path ends in redraw, which schedules redrawstatus so the update happens outside the callback.'),
    ...sec(r'trade-offs'),
    ...pt('--', r'wrapping handlers', r'patching client.handlers is invasive but there is no other hook: rustaceanvim does not expose the status, so the module wraps once per client (the wrapped flag) and delegates.'),
    ...pt('--', r'counting edits by hand', r'costs two callbacks per buffer; it avoids the changedtick-after-write trap.'),
    ...pt('--', r'strings, not highlights', r'the component returns plain text so any statusline can use it; the README shows lualine_x = { require("xyno_rust.lsp_status").component }.'),
    ...sec(r'how it is tested'),
    ...para('--', r'The cases live in tests/server-supervision-statusline_spec.lua (1,122 lines, shared with rust_restart). The README is honest about the boundary: the live bacon-ls half of the original specs was not ported, so what is exercised here is the describe block "lsp_status (fake clients)", not a real clippy run.'),
    ...sec(r'history'),
    ...para('--', r'bdd0225 (2026-10-09) introduced it. be73b6c (2026-10-12) added "clippy stale/failed/stopped status". 98c9bb4 (2026-10-13) fixed statusline findings, 25086fd (2026-10-14) added bacon_failed, b9363cd (2026-10-14) added the deps_begin machinery, ff1c8fa (2026-10-16) the path slashes. Copied into this repository in c1c7958 with the group renamed xyno_rust_lsp_status and the flag xyno_rust_stopped.'),
  ],
);
