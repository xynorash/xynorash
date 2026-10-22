import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/lua/config/code_actions.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'code_actions.lua — textDocument/codeAction as data'),
    cm('--', r'ask rust-analyzer, normalise, filter, apply: with no menu in between'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'programmatic code-action client for features that apply one specific action'),
    kv(r'language', r'Lua; Neovim LSP client API (client:request, vim.lsp.util.apply_workspace_edit)'),
    kv(r'size', r'336 lines, 1 commit (6e1b567, 2026-10-14)'),
    kv(r'exports', r'clients · request · filter · resolve_async · apply_async · apply · apply_all · request_wait · wait_for'),
    kv(r'callers', r'crate_import.lua, import_engine.lua, macro_tools.lua (clients), referred to by crate_add.lua'),
    kv(r'also lives in', r'xyno-rust.nvim as lua/xyno_rust/code_actions.lua, byte-identical'),
    ...sec(r'why this file exists'),
    ...para('--', r'Neovim’s own vim.lsp.buf.code_action shows a menu. That is the right UI for a person and the wrong one for a feature that already knows which fix it wants: "add the missing import", "add this crate to Cargo.toml", "enable this feature". Those features need to find one specific rust-analyzer action, with no menu, and apply it, and sometimes to wait until the server has analysed the file well enough to offer it. The header says it in one line: textDocument/codeAction "as data", for features that want to find and apply one specific rust-analyzer action without a menu (auto-import, "Add crate", "Enable feature"): "request, normalise, filter, apply, wait". Those five verbs are the file’s structure, and this page follows them.'),
    ...para('--', r'It came in with the commit 6e1b567 on 2026-10-14, titled "Macros and deps: foundation modules (crate_meta, code_actions) and fixtures". The word foundation is accurate: crate_import.lua and import_engine.lua require it as ca, and macro_tools.lua uses its clients() function in several places. It has no setup() and defines no commands and no keymaps; it is a library.'),
    ...sec(r'conventions and the normalised action'),
    ...code('lua', r'lua/config/code_actions.lua · lines 1-26', r'''
-- textDocument/codeAction as data, for features that want to find and apply
-- one specific rust-analyzer action without a menu (auto-import, "Add crate",
-- "Enable feature"): request, normalise, filter, apply, wait.
--
-- Positions are 0-based { row, col } with a byte column (nvim_win_get_cursor
-- minus one on the row). A range is { start = pos, ["end"] = pos }; a bare pos
-- is an empty range; nil is the cursor.
--
-- action = { title, kind, is_preferred, edit, command, data, raw, client_id,
--            client_name, bufnr }
local M = {}

M.client_name = "rust-analyzer"

-- ServerCancelled / ContentModified: rust-analyzer's "I was busy changing
-- state, ask again"
local RETRY_CODES = { [-32801] = true, [-32802] = true }

local function retryable(err)
  return type(err) == "table" and (RETRY_CODES[err.code] or tostring(err.message or ""):lower():find("content modified", 1, true)) and true or false
end

--- The rust-analyzer clients of a buffer. Specs replace this to fake a server.
function M.clients(bufnr)
  return vim.lsp.get_clients({ bufnr = bufnr, name = M.client_name })
end'''),
    ...para('--', r'The header fixes the conventions once so that every caller agrees. Positions are 0-based { row, col } with a byte column, which is what nvim_win_get_cursor gives minus one on the row. A range is a table with start and end, a bare position means an empty range at that point, and nil means the cursor. The normalised action table lists the fields every caller can rely on: title, kind, is_preferred, edit, command, data, the raw original, and the client id and name and buffer it came from.'),
    ...para('--', r'The two retry codes are LSP’s ServerCancelled (-32802) and ContentModified (-32801) as defined in the protocol; the comment translates them into what they mean for rust-analyzer: "I was busy changing state, ask again". retryable() also accepts any error whose message contains "content modified" in any case, because not every error arrives with the numeric code. The expression ends with and true or false so the function always returns a boolean, never the table value from RETRY_CODES.'),
    ...para('--', r'M.clients is separated into a public function with a pointed doc comment: "Specs replace this to fake a server." That is the testing seam of the whole file: tests substitute one function and get a rust-analyzer that answers however the test wants, without launching a real server. M.client_name is a field for the same reason (and so that a different server could be targeted).'),
    ...sec(r'request: ask every client, report errors separately'),
    ...code('lua', r'lua/config/code_actions.lua · lines 28-137', r'''
local function lsp_pos(bufnr, pos, enc)
  local line = vim.api.nvim_buf_get_lines(bufnr, pos[1], pos[1] + 1, false)[1] or ""
  local col = math.min(pos[2], #line)
  local ok, ch = pcall(vim.str_utfindex, line, enc, col, false)
  return { line = pos[1], character = ok and ch or col }
end

local function to_range(bufnr, range)
  if not range then
    local c = vim.api.nvim_win_get_cursor(0)
    range = { c[1] - 1, c[2] }
  end
  if range.start then
    return range.start, range["end"] or range.start
  end
  return range, range
end
...
function M.request(bufnr, range, opts, cb)
  opts = opts or {}
  bufnr = bufnr == 0 and vim.api.nvim_get_current_buf() or bufnr
  local clients = M.clients(bufnr)
  if #clients == 0 then
    return vim.schedule(function()
      cb({}, { { code = -1, message = "no " .. M.client_name .. " client attached" } })
    end)
  end
  local from, to = to_range(bufnr, range)
  local list, errs, left = {}, {}, #clients
  for _, client in ipairs(clients) do
    local enc = client.offset_encoding or "utf-16"
    local diags = {}
    for _, d in ipairs(opts.diagnostics or {}) do
      diags[#diags + 1] = lsp_diagnostic(bufnr, d, enc)
    end
    local params = {
      textDocument = { uri = vim.uri_from_bufnr(bufnr) },
      range = { start = lsp_pos(bufnr, from, enc), ["end"] = lsp_pos(bufnr, to, enc) },
      context = {
        diagnostics = diags,
        only = opts.only,
        triggerKind = opts.trigger == "automatic" and 2 or 1,
      },
    }
    client:request("textDocument/codeAction", params, function(err, result)
      if err then
        errs[#errs + 1] = err
      end
      for _, item in ipairs(result or {}) do
        local a = normalize(item, client, bufnr)
        if a then
          list[#list + 1] = a
        end
      end
      left = left - 1
      if left == 0 then
        cb(list, #errs > 0 and errs or nil)
      end
    end, bufnr)
  end
end'''),
    ...para('--', r'The excerpt shows the position helpers and the request body, with the pieces between them (diagnostic conversion and normalisation) described below. lsp_pos converts a byte column to the unit the server negotiated. Lines are looked up in the buffer, the column is clamped to the line length, and vim.str_utfindex turns the byte offset into a UTF-16, UTF-32 or UTF-8 index according to the client’s offset_encoding, with a pcall so that a bad offset falls back to the byte column instead of raising. This is the unglamorous detail that makes the feature correct on lines with non-ASCII characters: the code falls back to utf-16 when the client names no encoding, so a raw byte offset would land inside the wrong character after an accented letter or an emoji.'),
    ...para('--', r'The structure of request is a small fan-out and join. The callback style is deliberate: cb(list, errs) is called exactly once, after all clients have answered, counted by a left counter. With no rust-analyzer client attached, the callback is still asynchronous (vim.schedule) and receives an empty list plus a synthetic error "no rust-analyzer client attached", so callers handle one control flow in all cases. The second argument carries raw LSP errors, nil if there were none. The doc comment spells out why this matters: a caller can tell "nothing to offer" from "rust-analyzer was busy". An empty list with no error is a real answer; an empty list with a ContentModified error means ask again.'),
    ...para('--', r'The context is built from the options. opts.only restricts action kinds, opts.trigger switches the LSP trigger kind from invoked (1) to automatic (2), and opts.diagnostics passes diagnostics at the position so that quickfix-kind actions, which rust-analyzer ties to a specific diagnostic, are offered. Those diagnostics are Neovim diagnostics, and the helper lsp_diagnostic converts them: if the diagnostic came from an LSP server it reuses the original LSP object stored in user_data (so its data field survives, which some servers need to produce the fix), otherwise it builds a range, message, severity, code and source from the Neovim fields.'),
    ...para('--', r'normalise drops a disabled action (item.disabled), turns the string form of command into a table, and fills the stable shape: title, kind (default empty string), is_preferred (default false), edit, command, data, the raw item, client id and name, and buffer. A CodeAction with an edit and a bare Command both end up as the same record, which is what filter and apply rely on.'),
    ...sec(r'filter: pick the one you mean'),
    ...code('lua', r'lua/config/code_actions.lua · lines 141-168', r'''
local function kind_matches(kind, want)
  return kind == want or vim.startswith(kind, want .. ".")
end

--- spec = { kind = "quickfix" | { "quickfix", "refactor" }, title = lua
--- pattern, plain = bool (title is a literal), preferred = true }
function M.filter(list, spec)
  spec = spec or {}
  local kinds = type(spec.kind) == "string" and { spec.kind } or spec.kind
  return vim.tbl_filter(function(a)
    if kinds then
      local hit = false
      for _, k in ipairs(kinds) do
        hit = hit or kind_matches(a.kind, k)
      end
      if not hit then
        return false
      end
    end
    if spec.title and not a.title:find(spec.title, 1, spec.plain) then
      return false
    end
    if spec.preferred and not a.is_preferred then
      return false
    end
    return true
  end, list)
end'''),
    ...para('--', r'The filter has three optional criteria that all must hold. The kind follows the LSP hierarchy: "refactor" also matches "refactor.rewrite" because kind_matches accepts the exact kind or the kind followed by a dot, but "refactor" does not match "refactorx". The title is a Lua pattern, or a plain literal when spec.plain is true; that flag is passed straight through as the fourth argument of string.find, which is why literal titles with punctuation (an import path such as use std::fmt) are safe. The preferred flag keeps only the actions the server marks as the preferred fix.'),
    ...sec(r'resolve and apply'),
    ...code('lua', r'lua/config/code_actions.lua · lines 176-243', r'''
--- Resolve a lazily filled action (rust-analyzer sends the edit only on
--- codeAction/resolve). cb(action) or cb(nil, err); retries "content
--- modified" for up to `timeout` ms.
function M.resolve_async(action, cb, opts)
  opts = opts or {}
  if action.edit or action.command or not action.data then
    return vim.schedule(function()
      cb(action)
    end)
  end
  local client = client_of(action)
  if not client then
    return vim.schedule(function()
      cb(nil, "client is gone")
    end)
  end
  local deadline = vim.uv.now() + (opts.timeout or 10000)
  local function attempt()
    client:request("codeAction/resolve", action.raw, function(err, result)
      if err then
        if retryable(err) and vim.uv.now() < deadline then
          return vim.defer_fn(attempt, 200)
        end
        return cb(nil, err.message or "resolve failed")
      end
      local r = normalize(result or action.raw, client, action.bufnr)
      cb(r or action)
    end, action.bufnr)
  end
  attempt()
end

--- Apply an action: resolve, then its edit, then its command. cb(ok, err).
--- opts.join = true joins the edit to the previous undo step.
function M.apply_async(action, cb, opts)
  opts = opts or {}
  M.resolve_async(action, function(a, err)
    if not a then
      return cb(false, err)
    end
    local client = client_of(a)
    if a.edit then
      local enc = client and client.offset_encoding or "utf-16"
      if opts.join then
        pcall(vim.api.nvim_buf_call, a.bufnr or 0, function()
          vim.cmd("silent! undojoin")
        end)
      end
      local ok, e = pcall(vim.lsp.util.apply_workspace_edit, a.edit, enc)
      if not ok then
        return cb(false, tostring(e))
      end
    end
    if a.command and a.command.command then
      if not client then
        return cb(false, "client is gone")
      end
      client:request("workspace/executeCommand", {
        command = a.command.command,
        arguments = a.command.arguments,
      }, function(cerr)
        cb(not cerr, cerr and (cerr.message or "command failed") or nil)
      end, a.bufnr)
      return
    end
    cb(true)
  end, opts)
end'''),
    ...para('--', r'rust-analyzer returns many code actions without their edit, to keep the menu fast, and fills the edit in only when asked with codeAction/resolve. resolve_async handles that: an action that already has an edit or a command, or has no data to resolve with, is returned as is (still asynchronously, so the caller never sees two different timings); a resolve for an action whose client has gone returns "client is gone"; otherwise the raw action is sent to the server. If the answer is a retryable error and the deadline (10 seconds by default) has not passed, it tries again after 200 ms with vim.defer_fn, which is how it rides out rust-analyzer’s reloads after an edit. Any other error ends in the callback with the server’s message.'),
    ...para('--', r'apply_async follows the order the LSP specification gives for a CodeAction: first the edit, then the command. A workspace edit goes through vim.lsp.util.apply_workspace_edit with the client’s offset encoding, in a pcall so a bad edit reports failure through the callback instead of throwing. The command goes to workspace/executeCommand. When opts.join is set, the edit is preceded by "silent! undojoin" in the action’s buffer, again inside a pcall so a refusal cannot raise; this lets several actions be stacked into one undo step. Note that applying the edit goes through the same apply_workspace_edit that disk_guard.lua wraps, so a multi-file action from here is also followed by a save of the touched buffers.'),
    ...sec(r'blocking wrappers: await, apply, apply_all'),
    ...code('lua', r'lua/config/code_actions.lua · lines 247-285', r'''
local function await(start, timeout_ms)
  local done, r1, r2
  start(function(a, b)
    done, r1, r2 = true, a, b
  end)
  if not vim.wait(timeout_ms, function()
    return done
  end, 10) then
    return nil, "timed out"
  end
  return r1, r2
end

--- Blocking apply: true, or false + error.
function M.apply(action, opts)
  opts = opts or {}
  local ok, err = await(function(cb)
    M.apply_async(action, cb, opts)
  end, (opts.timeout or 10000) + 5000)
  return ok == true, err
end

--- Apply several actions as ONE undo step (undojoin between the edits of the
--- current buffer). Actions are applied in order and each one's edit must still
--- fit the buffer the earlier ones changed: pass non-overlapping actions, or
--- re-request between steps. Returns the number applied and the first error.
function M.apply_all(actions, opts)
  local n, first_err = 0, nil
  for i, a in ipairs(actions) do
    local o = vim.tbl_extend("force", opts or {}, { join = i > 1 })
    local ok, err = M.apply(a, o)
    if not ok then
      first_err = first_err or err
      break
    end
    n = n + 1
  end
  return n, first_err
end'''),
    ...para('--', r'Every asynchronous function has a blocking sibling built on one tiny primitive. await runs a function that takes a callback and polls with vim.wait every 10 ms until the callback fires; if it does not within the timeout it returns nil plus "timed out". The blocking form exists because the import and crate features are written as straight-line scripts ("find the action, apply it, then continue"), and also because specs can assert on the state right after the call. The timeout for apply is the resolve timeout plus five seconds of headroom, so the inner deadline always fires first with a better message.'),
    ...para('--', r'apply_all applies a list as one undo step by passing join = true for every action but the first. The doc comment is frank about the limit: actions are applied in order and each one’s edit must still fit the buffer the earlier ones changed, so the caller has to pass non-overlapping actions or request again between steps. It stops at the first failure and returns the number applied together with that error, which keeps a partial result visible instead of hiding it.'),
    ...sec(r'waiting for rust-analyzer'),
    ...code('lua', r'lua/config/code_actions.lua · lines 289-334', r'''
--- Blocking request that retries while rust-analyzer answers "content
--- modified" (it does so while it reloads after an edit). Returns list, err
--- (err = the last LSP error message when the retries ran out).
function M.request_wait(bufnr, range, opts)
  opts = opts or {}
  local deadline = vim.uv.now() + (opts.timeout or 10000)
  local list, errs
  repeat
    list, errs = await(function(cb)
      M.request(bufnr, range, opts, cb)
    end, 15000)
    if errs ~= nil and type(errs) ~= "table" then
      return {}, tostring(errs or "request failed")
    end
    local busy = false
    for _, e in ipairs(errs or {}) do
      busy = busy or retryable(e)
    end
    if not busy then
      break
    end
    vim.wait(200)
  until vim.uv.now() >= deadline
  if errs and #(list or {}) == 0 then
    return list or {}, tostring(errs[1].message or "request failed")
  end
  return list or {}, nil
end

--- Poll until an action matching `spec` (see filter) is offered, e.g. an
--- "Import" that only appears once rust-analyzer has analysed the file.
--- Returns the matching list (possibly empty after `timeout`).
function M.wait_for(bufnr, range, spec, opts)
  opts = opts or {}
  local deadline = vim.uv.now() + (opts.timeout or 30000)
  local hits = {}
  repeat
    local list = M.request_wait(bufnr, range, opts)
    hits = M.filter(list, spec)
    if #hits > 0 then
      break
    end
    vim.wait(opts.interval or 500)
  until vim.uv.now() >= deadline
  return hits
end'''),
    ...para('--', r'There are two levels of patience. request_wait retries one request while the server answers with a retryable error: it asks, and if any error is ContentModified it sleeps 200 ms and asks again until the deadline (10 seconds by default). A non-table error value, which is what await returns when it timed out ("timed out"), ends the loop immediately with an empty list and that text. If errors remain after the loop and there is nothing in the list, the first error’s message is returned; if the list is non-empty, errors are dropped and the actions are returned with a nil error, so a partial answer is better than none.'),
    ...para('--', r'wait_for is the second level: it repeats request_wait until the filter matches something, sleeping half a second (opts.interval) between rounds, for up to 30 seconds. The doc comment gives the reason with an example: an "Import" action only appears once rust-analyzer has analysed the file, and that can take a while on a cold start. An empty result after the timeout is a normal return and not an error, so a caller that gives up simply sees no hits.'),
    ...sec(r'design decisions and trade-offs'),
    ...pt('--', r'data in, data out', r'everything returns plain tables with a documented shape, so the import engine, the crate importer and the macro tools can filter, sort and show the candidates in their own pickers. The menu of vim.lsp.buf.code_action is never involved.'),
    ...pt('--', r'async first, sync wrappers second', r'the primitives take callbacks and never block; the blocking forms are thin layers over await. A feature that must stay responsive can use the first set and a script can use the second.'),
    ...pt('--', r'errors are values', r'request reports raw errors beside the list, resolve and apply report (ok, message). Nothing throws across the module boundary except through pcall-guarded edits that become messages.'),
    ...pt('--', r'a seam for tests', r'M.clients and M.client_name. The result is that no spec needs a real server for the logic: the specs of the callers swap M.clients (and the documented client table shape) and check how their code reacts.'),
    ...pt('--', r'uncapped retry loops are avoided', r'every loop has a deadline taken from vim.uv.now(), so a server that never finishes loading cannot freeze the editor forever; the worst cases are 10 s for a request and 30 s for wait_for, 15 s per single await.'),
    ...sec(r'the same file in xyno-rust.nvim'),
    ...para('--', r'xyno-rust.nvim carries this module as lua/xyno_rust/code_actions.lua. The two files are byte-identical (a diff is empty), because the module only uses the Neovim API and has no config.* requires to rename. Extracted on 2026-10-22, with the config still loading its own copy.'),
    ...sec(r'how it is tested'),
    ...para('--', r'There is no spec named for code_actions itself. It is exercised through its callers: tests/crate-import_spec.lua, tests/import-engine_spec.lua, tests/crate-features_spec.lua, tests/crate-meta_spec.lua, tests/macro-attrs_spec.lua and tests/macros-deps-flows_spec.lua all mention it, and tests/COVERAGE.md lists it. A search found no direct unit test for the retry loops, so their coverage is not described beyond that.'),
    ...sec(r'history'),
    ...pt('--', r'6e1b567 · 2026-10-14', r'Macros and deps: foundation modules (crate_meta, code_actions) and fixtures. Created in full and never changed since: git log --follow shows exactly one commit.'),
  ],
);
