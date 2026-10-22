import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/lua/config/rust_assist.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'rust_assist.lua — seven replacements for rustaceanvim flows that broke here'),
    cm('--', r'each function exists because a field test found a specific failure'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'wrappers around rustaceanvim / rust-analyzer commands, bound in keymaps.lua'),
    kv(r'language', r'Lua; rustaceanvim internals, LSP extension requests, Snacks'),
    kv(r'size', r'276 lines, 6 commits (8779a6e on 2026-10-12 to 25086fd on 2026-10-14)'),
    kv(r'functions', r'ssr · workspace_symbol · explain_error · open_docs · syntax_tree · rename_file · move_item'),
    kv(r'bound to', r'<leader>rs, rw/rW, re, rd/rE, rS, <leader>cR, <A-j>/<A-k>'),
    kv(r'also lives in', r'nowhere: no xyno-*.nvim plugin carries it, it stays in the config'),
    ...sec(r'why this file exists'),
    ...para('--', r'The first two lines of the file are its whole charter: "Replacements for rustaceanvim commands whose own keymap flow is broken or unhelpful on nvim 0.12 / this setup (keys in keymaps.lua, group <leader>r)". rustaceanvim exposes many rust-analyzer features as :RustLsp subcommands, and the config wants all of them on keys. For a handful, calling the subcommand straight from a key did not work in this setup: the input prompt returned too late, a parse error produced a raw traceback, a nil value was treated as a URL, a snippet was expanded where plain text was meant. Each function in this file replaces one of those with the same feature minus the failure.'),
    ...para('--', r'It was created in the commit 8779a6e on 2026-10-12, whose title is "Batch 2: keys that did nothing (ssr, rw/rW, re, rM, ri, rS, rd/rE), terminals keep output, coverage with failing tests, tD doctests". The list in parentheses is the list of functions here. The three rounds that followed (the "Final loop" commits on 2026-10-13 and 2026-10-14) added the cases that real use turned up. Every doc comment in the file says which key it serves and what was wrong, so the file reads as a log of workarounds, and this page follows that order.'),
    ...sec(r'a prompt helper'),
    ...code('lua', r'lua/config/rust_assist.lua · lines 5-12', r'''
--- Prompt, then hand the answer to `cb` (vim.ui.input is async with Snacks).
local function ask(prompt, cb)
  vim.ui.input({ prompt = prompt }, function(q)
    if q and q ~= "" then
      cb(q)
    end
  end)
end'''),
    ...para('--', r'This is the common piece. vim.ui.input is asynchronous when Snacks replaces it with a floating input: the function returns immediately and the answer arrives in a callback. Code that was written for a synchronous prompt and reads the result right after the call sees nothing. ask() shapes everything around the callback and drops the cases that mean "cancelled": a nil answer (Escape) and an empty string.'),
    ...sec(r'ssr: structural search and replace'),
    ...code('lua', r'lua/config/rust_assist.lua · lines 14-58', r'''
--- <leader>rs: rustaceanvim reads the query right after vim.ui.input returns,
--- which is before Snacks' async input has an answer. Prompt here instead.
--- Visual: leave visual mode first so '< and '> hold the selection.
function M.ssr(visual)
  local l1, l2
  if visual then
    vim.cmd("normal! \27")
    l1, l2 = vim.fn.line("'<"), vim.fn.line("'>")
  end
  ask("SSR query (pattern ==>> replacement): ", function(q)
    -- rustaceanvim raises a raw traceback (ssr.lua:16) for a query without the arrow
    if not q:find("==>>", 1, true) then
      return vim.notify("SSR query needs `pattern ==>> replacement`", vim.log.levels.WARN)
    end
    local cmd = { cmd = "RustLsp", args = { "ssr", q } }
    if visual then
      cmd.range = { l1, l2 }
    end
    -- rust-analyzer's parse error (`nonsense ==>>`) reaches rustaceanvim's handler, which
    -- error()s inside a scheduled callback (traceback): intercept the reply for this request
    local ok, ra = pcall(require, "rustaceanvim.rust_analyzer")
    local orig = ok and ra.buf_request
    if orig then
      ra.buf_request = function(bufnr, method, params, handler, ...)
        return orig(bufnr, method, params, function(err, res, ctx, ...)
          if err then
            return vim.notify("SSR: " .. tostring(err.message or err), vim.log.levels.WARN)
          end
          -- a query that matches nothing answers an empty edit: say so
          if not res or (vim.tbl_isempty(res.changes or {}) and vim.tbl_isempty(res.documentChanges or {})) then
            return vim.notify("SSR: no matches", vim.log.levels.INFO)
          end
          return handler(err, res, ctx, ...)
        end, ...)
      end
    end
    local ran, e = pcall(vim.api.nvim_cmd, cmd, {})
    if orig then
      ra.buf_request = orig
    end
    if not ran then
      error(e, 0)
    end
  end)
end'''),
    ...para('--', r'SSR (structural search and replace) takes a query of the form pattern ==>> replacement. There are three separate failures behind this function, and each has its own line of defence.'),
    ...pt('--', r'the prompt timing', r'rustaceanvim reads the query right after vim.ui.input returns, which is before the async input has an answer. So this function prompts first and then runs the :RustLsp command with the query already in the arguments.'),
    ...pt('--', r'the missing arrow', r'a query without ==>> makes rustaceanvim raise a raw traceback (the comment pins it to ssr.lua line 16). The guard is a plain find for the arrow, and a WARN that shows the expected shape.'),
    ...pt('--', r'the parse error and the empty result', r'rust-analyzer answers a malformed query (the comment’s example is "nonsense ==>>") with an error that reaches a handler in rustaceanvim, which calls error() inside a scheduled callback. The fix is the most unusual idea in the file: for the duration of the one command, replace ra.buf_request, rustaceanvim’s request function, with a wrapper whose handler intercepts the reply. An error becomes a WARN notification "SSR: <message>"; an edit with no changes and no documentChanges, which is how rust-analyzer says "your pattern matched nothing", becomes an INFO "SSR: no matches"; anything else is passed on to the original handler. Afterwards the original function is put back, and the pcall around nvim_cmd guarantees the restore happens even when the command fails, after which the error is re-raised with level 0 so that its text stays clean.'),
    ...para('--', r'In visual mode the function first leaves visual mode with normal! and the escape character (the \27 in the string), because the marks ’< and ’> are only updated when visual mode ends, and then passes the line range to the command. The scheme of "patch a module function for one call and restore it" is fragile in general, since another request made in the same window would get the wrapped function too, but here the window is the one synchronous nvim_cmd call.'),
    ...sec(r'workspace_symbol: ask once, search one word'),
    ...code('lua', r'lua/config/rust_assist.lua · lines 60-92', r'''
--- <leader>rw / rW: rustaceanvim's own prompt asks twice when no query is
--- given, so ask once here. Results land in the quickfix list.
function M.workspace_symbol(deps)
  -- RustLsp only exists in a Rust buffer: from the quickfix list, a picker or
  -- a terminal run it in a Rust window of this tab.
  local win = vim.api.nvim_get_current_win()
  if vim.bo.filetype ~= "rust" then
    win = nil
    for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      if vim.bo[vim.api.nvim_win_get_buf(w)].filetype == "rust" then
        win = w
        break
      end
    end
    if not win then
      return vim.notify("workspace symbol: no Rust window in this tab", vim.log.levels.WARN)
    end
  end
  ask("Symbol query: ", function(q)
    -- RustLsp splits its arguments on whitespace: the first word is the query ("Square area" became
    -- "Squarearea" when the blanks were stripped, and found nothing)
    local word = q:match("%S+")
    if not word then
      return
    end
    if word ~= vim.trim(q) then
      vim.notify("workspace symbol: only one word is searched (" .. word .. ")", vim.log.levels.INFO)
    end
    vim.api.nvim_win_call(win, function()
      vim.api.nvim_cmd({ cmd = "RustLsp", args = { "workspaceSymbol", word }, bang = deps }, {})
    end)
  end)
end'''),
    ...para('--', r'There are two lessons here. First, the :RustLsp command only exists in a buffer with a Rust file type, so if the key is pressed from the quickfix list, a picker or a terminal, the function looks for a window in the current tab that shows a Rust buffer and runs the command inside that window with nvim_win_call. With none, it says "no Rust window in this tab" instead of failing with an unknown-command error. Second, the comment records a field-test finding: the command splits its arguments on whitespace, so the query "Square area" had been collapsed into "Squarearea" and found nothing. The function therefore searches only the first word, and tells the user so with an INFO message when more was typed. The deps argument becomes the bang: <leader>rW calls it with true, which in rustaceanvim widens the search to dependencies.'),
    ...sec(r'explain_error: rustc --explain in a float'),
    ...code('lua', r'lua/config/rust_assist.lua · lines 94-123', r'''
--- <leader>re: rustaceanvim only explains rustc (flycheck) diagnostics, which
--- are off here. Take the E-code from any diagnostic on the line (the
--- rust-analyzer ones carry `code`, clippy/bacon ones only have it in the
--- message) and show `rustc --explain` in a float.
function M.explain_error()
  local lnum = vim.api.nvim_win_get_cursor(0)[1] - 1
  local code
  for _, d in ipairs(vim.diagnostic.get(0, { lnum = lnum })) do
    code = code or tostring(d.code or ""):match("^E%d%d%d%d$") or d.message:match("E%d%d%d%d")
  end
  if not code then
    return vim.notify("no E0000 error code in the diagnostics on this line", vim.log.levels.INFO)
  end
  vim.system({ "rustc", "--explain", code }, { text = true }, function(o)
    vim.schedule(function()
      if o.code ~= 0 then
        return vim.notify("rustc --explain " .. code .. " failed:\n" .. (o.stderr or ""), vim.log.levels.ERROR)
      end
      Snacks.win({
        text = vim.split(o.stdout, "\n"),
        ft = "markdown",
        title = " " .. code .. " ",
        width = 0.7,
        height = 0.8,
        border = "rounded",
        wo = { wrap = true, conceallevel = 2 },
      })
    end)
  end)
end'''),
    ...para('--', r'rustaceanvim’s own explainError only works on rustc diagnostics from flycheck, and this config switches flycheck off (bacon-ls runs clippy instead). So the diagnostics on screen come from two different servers, and only some carry the error number in a field. The function scans every diagnostic on the cursor’s line: rust-analyzer’s have the E-code in d.code; clippy and bacon ones only have it inside the message, so it falls back to a pattern match on the text. Its first hit wins (code or ... is a short-circuit chain). If there is none: an INFO message that spells the shape of what it looked for, E0000.'),
    ...para('--', r'The explanation itself is the output of rustc --explain E0xxx, which is markdown. It is run with vim.system asynchronously, so a slow rustc cannot freeze the editor, and the result is shown in a Snacks window that is 70 percent wide and 80 percent high, rounded, with markdown highlighting, wrapped lines and conceallevel 2 so that the markdown markers are hidden. A non-zero exit becomes an ERROR notification that includes stderr, for instance when the toolchain does not know the code. The callback of vim.system runs in a fast context, so everything that touches the UI is wrapped in vim.schedule.'),
    ...sec(r'open_docs: do not treat vim.NIL as a URL'),
    ...code('lua', r'lua/config/rust_assist.lua · lines 125-145', r'''
--- <leader>rd / rE: rustaceanvim's handler treats the `vim.NIL` that
--- rust-analyzer answers for an undocumented item as a URL and throws.
function M.open_docs()
  local ra = require("rustaceanvim.rust_analyzer")
  local client = ra.get_active_rustaceanvim_clients(0)[1]
  if not client then
    return
  end
  ra.buf_request(0, "experimental/externalDocs", vim.lsp.util.make_position_params(0, client.offset_encoding or "utf-8"), function(_, res)
    if type(res) ~= "table" then
      return vim.notify("no documentation for the item under the cursor", vim.log.levels.INFO)
    end
    local loc = res["local"] ~= nil and res["local"] ~= vim.NIL and tostring(res["local"]) or nil
    local url = (loc and vim.uv.fs_stat(vim.uri_to_fname(loc))) and loc or (res.web ~= vim.NIL and res.web and tostring(res.web))
    if url then
      require("rustaceanvim.config.internal").tools.open_url(url)
    else
      vim.notify("no documentation for the item under the cursor", vim.log.levels.INFO)
    end
  end)
end'''),
    ...para('--', r'This is the clearest example of a small bug with a small fix. rust-analyzer’s experimental/externalDocs answers with a table that has a local and a web link, or with JSON null for an item without documentation. JSON null becomes vim.NIL in Lua, a truthy userdata value, and rustaceanvim’s handler took it for a URL and threw. The replacement sends the same request, treats any non-table as "nothing to show", and for a table prefers the local documentation (the generated cargo doc file) if the file really exists on disk, and falls back to the web link, each guarded against vim.NIL. It still opens the result with rustaceanvim’s own open_url, so the user’s browser setting is respected. If neither exists the user sees the INFO message, and silently returns when no rustaceanvim client is attached to the buffer. The spec has the order spelled out: "the local docs file is preferred when it exists, else the web URL".'),
    ...sec(r'syntax_tree: pretty-printing one long JSON line'),
    ...code('lua', r'lua/config/rust_assist.lua · lines 147-206', r'''
--- Indented JSON (vim.json.encode has no indent option).
local function pretty(v, ind, out)
  ind = ind or ""
  local t = type(v)
  if t ~= "table" then
    out[#out + 1] = vim.json.encode(v)
  elseif vim.islist(v) then
    if #v == 0 or type(v[1]) ~= "table" then -- scalars (positions): one line
      out[#out + 1] = vim.json.encode(v)
    else
      out[#out + 1] = "[\n"
      for i, x in ipairs(v) do
        out[#out + 1] = ind .. "  "
        pretty(x, ind .. "  ", out)
        out[#out + 1] = i < #v and ",\n" or "\n"
      end
      out[#out + 1] = ind .. "]"
    end
  else
    local keys = vim.tbl_keys(v)
    table.sort(keys)
    if #keys == 0 then
      out[#out + 1] = "{}"
    else
      out[#out + 1] = "{\n"
      for i, k in ipairs(keys) do
        out[#out + 1] = ("%s  %s: "):format(ind, vim.json.encode(k))
        pretty(v[k], ind .. "  ", out)
        out[#out + 1] = i < #keys and ",\n" or "\n"
      end
      out[#out + 1] = ind .. "}"
    end
  end
  return out
end

--- <leader>rS: newer rust-analyzer answers viewSyntaxTree with one long JSON
--- line; pretty-print it into a json scratch split.
function M.syntax_tree()
  local ra = require("rustaceanvim.rust_analyzer")
  local client = ra.get_active_rustaceanvim_clients(0)[1]
  if not client then
    return
  end
  local params = vim.lsp.util.make_range_params(0, client.offset_encoding or "utf-8")
  ra.buf_request(0, "rust-analyzer/viewSyntaxTree", params, function(err, result)
    if err or result == nil then
      return vim.notify("rust-analyzer: " .. ((err and err.message) or "viewSyntaxTree failed"), vim.log.levels.ERROR)
    end
    local ok, tree = pcall(vim.json.decode, result)
    local text = ok and table.concat(pretty(tree, "", {})) or result -- older servers: plain text
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(text, "\n"))
    vim.bo[buf].filetype = ok and "json" or "rust"
    vim.bo[buf].modifiable = false
    vim.cmd("vsplit")
    vim.api.nvim_win_set_buf(0, buf)
    vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = buf })
  end)
end'''),
    ...para('--', r'A newer rust-analyzer answers viewSyntaxTree with the whole tree as a single line of JSON, which is unreadable in a buffer. Neovim’s vim.json.encode has no indent option, so the file writes its own pretty printer. It is a compact recursive function that appends to an output array of strings (cheaper than concatenating): a non-table is encoded as is; a list of scalars (the positions) stays on one line; a list of tables puts one element per line; an object sorts its keys, which makes the output stable between runs, and writes one key per line. Empty objects become {}.'),
    ...para('--', r'syntax_tree tries to decode the answer as JSON. On success it shows the pretty text with the json file type; on failure (older servers answer in plain text) it shows the raw string with the rust file type, so both generations of server work, and a spec test is named for each ("a plain-text answer (older servers) is shown with filetype rust"). The buffer is a scratch buffer created with nvim_create_buf(false, true), made non-modifiable, put in a vertical split, and q closes it.'),
    ...sec(r'rename_file: refuse to overwrite'),
    ...code('lua', r'lua/config/rust_assist.lua · lines 208-227', r'''
--- <leader>cR: Snacks' rename (fs rename) overwrote an existing destination: ask for the
--- name here (same prompt and default), refuse when it exists, then let Snacks do the rest.
function M.rename_file()
  local from = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ":p")
  local root = vim.fs.normalize(vim.fn.getcwd(0))
  if from:find(root, 1, true) ~= 1 then
    root = vim.fs.dirname(from)
  end
  local extra = from:sub(#root + 2)
  vim.ui.input({ prompt = "New File Name: ", default = extra, completion = "file" }, function(value)
    if not value or value == "" or value == extra then
      return
    end
    local to = vim.fs.normalize(root .. "/" .. value)
    if vim.uv.fs_stat(to) then
      return vim.notify("Rename: " .. to .. " already exists", vim.log.levels.ERROR)
    end
    Snacks.rename.rename_file({ from = from, to = to })
  end)
end'''),
    ...para('--', r'A file rename is a destructive operation when the destination exists: Snacks’ rename moved the file over it. This function repeats Snacks’ prompt (same text, same default of the path relative to the working directory) and adds the one check that was missing: if the destination already exists, show an ERROR and do nothing. When the file is not under the working directory, the root falls back to the file’s own directory so the default stays a short name. The actual work, including the language-server file-rename notifications, is still done by Snacks.rename.rename_file. The key it serves has a story in keymaps.lua: the Rust extra rebinds <leader>cR to a code action and LazyVim binds it to the Snacks rename, so keymaps.lua sets this one buffer-locally and sets it again when bacon-ls attaches later. The commit that introduced the guard (3f868dd, 2026-10-13) calls it "cR overwrite guard".'),
    ...sec(r'move_item: plain text, not a snippet'),
    ...code('lua', r'lua/config/rust_assist.lua · lines 229-274', r'''
--- <A-j>/<A-k>: `experimental/moveItem` answers snippet edits whose text is NOT
--- escaped (only the `$0` cursor marker is meant), and rustaceanvim expanded them as
--- snippets: `$e` in a macro_rules item became empty and auto-save wrote it. The edits
--- are applied as plain text here, only the first `$0` marker is dropped (it places
--- the cursor, same arithmetic as rustaceanvim's move_item.lua).
--- @param direction "Up"|"Down"
function M.move_item(direction)
  local ok, ra = pcall(require, "rustaceanvim.rust_analyzer")
  if not ok or #ra.get_active_rustaceanvim_clients(0) == 0 then
    return
  end
  local client = ra.get_active_rustaceanvim_clients(0)[1]
  local params = vim.lsp.util.make_range_params(0, client.offset_encoding or "utf-8")
  params.direction = direction
  ra.buf_request(0, "experimental/moveItem", params, function(_, edits, ctx)
    if not edits or #edits == 0 or not vim.api.nvim_buf_is_valid(ctx.bufnr) then
      return
    end
    local cursor = { edits[1].range.start.line }
    local prev
    for _, e in ipairs(edits) do
      if e.insertTextFormat == 2 and e.newText then
        local at = e.newText:find("$0", 1, true)
        if not cursor[2] then
          if prev then
            cursor[1] = cursor[1]
              + math.max(0, e.range.start.line - prev.range["end"].line - 1)
              - (prev.range.start.line == e.range.start.line and 1 or 0)
          end
          local lines = vim.split(e.newText:sub(1, at or #e.newText), "\n")
          cursor[1] = cursor[1] + #lines
          if at then
            cursor[2] = (#lines == 1 and e.range.start.character or 0) + #lines[#lines] - 1
          end
        end
        if at then
          e.newText = e.newText:sub(1, at - 1) .. e.newText:sub(at + 2)
        end
      end
      e.insertTextFormat = nil
      prev = e
    end
    vim.lsp.util.apply_text_edits(edits, ctx.bufnr, client.offset_encoding or "utf-8")
    pcall(vim.api.nvim_win_set_cursor, 0, { math.max(1, cursor[1]), cursor[2] or 0 })
  end)
end'''),
    ...para('--', r'This is the most intricate function and the bug it fixes was a data-loss bug, so the comment is specific. experimental/moveItem returns text edits marked as snippets (insertTextFormat 2). Snippet syntax gives special meaning to $ followed by a name, but rust-analyzer only means the $0 cursor marker, and sends all other text unescaped. rustaceanvim expanded the edits as snippets, so in a macro_rules item the fragment $e was treated as an empty snippet variable and removed from the text, and because auto-save is on the broken text was written to disk. The comment’s own words: "$e in a macro_rules item became empty and auto-save wrote it".'),
    ...para('--', r'The replacement applies the edits as plain text through vim.lsp.util.apply_text_edits, after removing the first $0 marker (two characters), and uses the marker to put the cursor where the server meant it. The cursor arithmetic follows rustaceanvim’s own move_item.lua, as the comment says: the line starts at the first edit’s start line; for each snippet edit it adds the lines of the text up to the marker, corrects for a gap or an overlap with the previous edit, and the column is the character offset of the marker (relative to the edit’s start only if the text up to it has a single line). Setting insertTextFormat to nil on each edit turns it into an ordinary text edit. The final set_cursor is in a pcall, and clamps the line to at least 1, so that an odd answer from the server can never raise an error after the text was already edited.'),
    ...sec(r'design decisions and trade-offs'),
    ...pt('--', r'replace the behaviour, keep the engine', r'every function still asks rustaceanvim or Snacks for the real work: the :RustLsp command, ra.buf_request, open_url, Snacks.rename. Only the broken edge is rewritten. This keeps the file short and keeps rustaceanvim’s updates (the server start, the client lookup) effective.'),
    ...pt('--', r'document the failure next to the fix', r'every comment says which key, what rustaceanvim did and what happened. If an upstream release fixes one of them, the comment says exactly what to test before deleting the function.'),
    ...pt('--', r'coupling to internals', r'rustaceanvim.rust_analyzer, rustaceanvim.config.internal and the position of the failure (ssr.lua:16) are not a public API. The price is that a rustaceanvim update can break these; the benefit is that the specs run the real server (several are marked "real rust-analyzer") and would catch it.'),
    ...pt('--', r'no setup, no commands', r'the module registers nothing. The keys are in keymaps.lua, buffer-local and set on LspAttach of rust-analyzer.'),
    ...sec(r'how it is tested'),
    ...para('--', r'All of it is under tests/keymaps-rust_spec.lua (75 it() blocks), whose test names are numbered after the behaviours. Number 8 is SSR (a missing arrow is refused with a notice, a parse error gives a WARN, no matches says "SSR: no matches", the visual variant passes the range, two of them against a real rust-analyzer); 12 is the syntax tree (a nomodifiable json buffer, q closes it, plain-text answers, an error answer); 13 and 15 are open_docs; 17 is explain_error (code from d.code, code from the message, no code, a failing rustc); 18 is workspace_symbol (asks once, searches the first word and says so, runs in a Rust window from the quickfix window, results land in the quickfix list); and the move_item and rename_file behaviours have their own numbered cases in the same file.'),
    ...sec(r'history'),
    ...pt('--', r'8779a6e · 2026-10-12', r'Batch 2: keys that did nothing. The file is created with ssr, workspace_symbol, explain_error, open_docs and syntax_tree.'),
    ...pt('--', r'98c9bb4 · 2026-10-13', r'Final loop round 1: "normal-mode rM/rk" and the other findings.'),
    ...pt('--', r'a3d33c8 · 2026-10-13', r'Final loop round 2: "SSR errors" are in the commit message.'),
    ...pt('--', r'3f868dd · 2026-10-13', r'Final loop round 3: "moveItem plain text", "cR overwrite guard".'),
    ...pt('--', r'f31e013 · 2026-10-14', r'Final loop round 4: "SSR no matches".'),
    ...pt('--', r'25086fd · 2026-10-14', r'Final loop round 5: "rw word" (the single-word workspace symbol search).'),
  ],
);
