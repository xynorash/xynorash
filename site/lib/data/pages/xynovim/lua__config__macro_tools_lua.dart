import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/lua/config/macro_tools.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'macro_tools.lua — help for the macros you call and the ones you write'),
    cm('--', r'a signature popup from macro_rules! arms, format-string hints,'),
    cm('--', r'a macro lens (:MacroExpand) and :ProcMacroStatus'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'three macro features that rust-analyzer does not give: call help, expansion lens, proc-macro health'),
    kv(r'language', r'Lua (Neovim 0.12: vim.uv, vim.system, vim.treesitter, vim.lsp client:request)'),
    kv(r'size', r'2455 lines, 3 commits (2026-10-14 to 2026-10-16)'),
    kv(r'commands', r'MacroExpand, MacroFormatFix, MacroSignature, ProcMacroStatus'),
    kv(r'shape', r'pure parts first (lexer, formats, matcher), UI after; the pure parts are table-tested'),
    kv(r'also lives in', r'xyno-macros.nvim, lua/xyno_macros/tools.lua (2515 lines)'),
    ...sec(r'why this file exists'),
    ...para('--', r'Macros are where Rust tooling goes blind. rust-analyzer expands them internally but gives little back to the person typing: calling a macro_rules! macro shows no signature, because a macro has no signature, only matcher arms; a wrong number of arguments to println! is reported as a rustc error after a build; and when a proc macro is not running, the editor just stops understanding the code around it. This file is the set of tools built to fill those three gaps: macro call help, a macro lens, and a proc-macro health report.'),
    ...para('--', r'The header states the layout and the rule that follows from it: the pure parts (a Rust token lexer, format string parsing, matcher compilation and matching) take strings and tables and are what tests/macro-tools_spec.lua drives table-wise, and the UI sits after them. A second rule is stated on the same line: everything that runs a program uses argv lists, and crate names that reach a path or a file are validated first.'),
    ...sec(r'a lexer that is only as exact as macro help needs'),
    ...para('--', r'Everything else stands on M.lex. It is not a Rust parser and does not try to be: it recognises strings (plain, raw with any number of hashes, byte and C strings), characters versus lifetimes, comments including nested block comments, numbers, identifiers (raw identifiers included) and delimited groups. Groups nest as tokens with kids. A group whose closer is missing, because the user is mid-typing, is kept with open = true and keeps the tokens it has, which is what every popup depends on.'),
    ...para('--', r'Tokens carry 0-based row and byte column positions with an exclusive end, binary-searched from a line-start table, and opts.row0 / col0 shift them so a lexed fragment reports positions in its buffer. Because all of the text work happens on one token format, the format-string checker, the call finder and the popup share it.'),
    ...code('lua', r'lua/config/macro_tools.lua · lines 116-143', r'''
      elseif c == '"' then
        local j = skip_string(i)
        kids[#kids + 1] = tok("str", i, j)
        i = j
      elseif c:find("[%a_\128-\255]") then
        local id = text:match("^[%w_\128-\255]+", i)
        local j = i + #id
        local nx = text:sub(j, j)
        if (id == "b" or id == "c") and nx == '"' then
          j = skip_string(j)
          kids[#kids + 1] = tok("str", i, j)
        elseif (id == "r" or id == "br" or id == "cr") and (nx == '"' or (nx == "#" and text:find('^#*"', j))) then
          local hashes = text:match("^#*", j)
          local body = j + #hashes + 1
          local a, b = text:find('"' .. hashes, body, true)
          j = a and (b + 1) or (n + 1)
          kids[#kids + 1] = tok("str", i, j)
        elseif id == "b" and nx == "'" then
          local a = text:find("'", j + 2 + (text:sub(j + 1, j + 1) == "\\" and 1 or 0), true)
          j = a and (a + 1) or (n + 1)
          kids[#kids + 1] = tok("lit", i, j)
        elseif id == "r" and nx == "#" and text:find("^#[%a_]", j) then
          j = j + #text:match("^#[%w_]+", j)
          kids[#kids + 1] = tok("id", i, j)
        else
          kids[#kids + 1] = tok("id", i, j)
        end
        i = j'''),
    ...para('--', r'The identifier branch is where the prefixes live: b" and c" are strings, r, br and cr followed by hashes and a quote are raw strings that end at a quote plus the same number of hashes, b followed by a quote is a byte literal, and r# followed by a letter is a raw identifier. Lifetimes and character literals are told apart by looking one or two characters past the apostrophe, including multi-byte characters.'),
    ...sec(r'format placeholders and sqlx binds'),
    ...para('--', r'The first user-visible feature is a hint when the count of arguments does not match the placeholders in a format string. M.parse_format reads the content of a literal and returns the number of {} slots that consume an argument, explicit indexes ({0}), named references ({name}), width and precision references ({:1$}, {:.*}) and the highest index used. Escaped braces are skipped, an unmatched brace makes the function return nil with a reason, because rustc reports those itself and the hint should stay silent on a string that is already an error.'),
    ...code('lua', r'lua/config/macro_tools.lua · lines 282-296', r'''
    if c == "{" and s:sub(p + 1, p + 1) == "{" then
      i = p + 2
    elseif c == "}" then
      if s:sub(p + 1, p + 1) ~= "}" then
        return nil, "unmatched }"
      end
      i = p + 2
    else
      local q = s:find("}", p + 1, true)
      if not q then
        return nil, "unmatched {"
      end
      local inner = s:sub(p + 1, q - 1)
      local arg, spec = inner:match("^([^:]*):?(.*)$")
      arg = vim.trim(arg)'''),
    ...code('lua', r'lua/config/macro_tools.lua · lines 307-322', r'''
      if spec:find(".*", 1, true) then
        info.implicit = info.implicit + 1
      end
      if arg == "" then
        info.implicit = info.implicit + 1
      elseif arg:find("^%d+$") then
        local ix = tonumber(arg)
        info.explicit[ix] = true
        info.max_explicit = math.max(info.max_explicit, ix)
      elseif arg:find("^[%a_][%w_]*$") then
        info.names[arg] = true
      end
      i = q + 1
    end
  end
  info.needs = math.max(info.implicit, info.max_explicit + 1)'''),
    ...para('--', r'A macro-to-argument-index table says where the format string sits. println, format, panic, todo and friends have it at index 0; write and writeln at 1 (after the writer); assert at 1, assert_eq and assert_ne at 2. The tracing and log macros (trace through error) are special: their fields come first, so the message is the first argument that is only a string literal. A qualified path is accepted only for the right crate (std/core for the standard macros, tracing/log for the others), so a user macro called println! in another module is not second-guessed.'),
    ...code('lua', r'lua/config/macro_tools.lua · lines 327-339', r'''
local FORMAT_AT = {
  println = 0, print = 0, eprintln = 0, eprint = 0, format = 0, format_args = 0, panic = 0,
  unreachable = 0, todo = 0, unimplemented = 0,
  write = 1, writeln = 1, assert = 1, debug_assert = 1,
  assert_eq = 2, assert_ne = 2, debug_assert_eq = 2, debug_assert_ne = 2,
}
-- tracing/log: fields first, the message is the first argument that is only a
-- string literal
local TRACING = { trace = true, debug = true, info = true, warn = true, error = true }
local SQLX_AT = {
  query = 0, query_unchecked = 0, query_scalar = 0, query_scalar_unchecked = 0,
  query_as = 1, query_as_unchecked = 1,
}'''),
    ...para('--', r'call_hints compares what the string needs with what is given. If more are needed than given, a "missing" hint is attached to the format string, marked fixable only when there are no named arguments (the fix appends todo!() and cannot invent a name). Otherwise each positional argument beyond the implicit count that no explicit index refers to is "unused", and each named argument never referenced is unused too.'),
    ...code('lua', r'lua/config/macro_tools.lua · lines 401-422', r'''
    local P, Nn = #fi.positional, #fi.named
    if fi.needs > P + Nn then
      local miss = fi.needs - P - Nn
      out[#out + 1] = vim.tbl_extend("force", range_of({ fi.fmt }), {
        kind = "missing",
        needs = fi.needs,
        given = P + Nn,
        add = miss,
        fixable = Nn == 0,
        message = ("format string needs %d argument%s, %d given"):format(fi.needs, fi.needs == 1 and "" or "s", P + Nn),
      })
    else
      for i = 0, P - 1 do
        if i >= fi.info.implicit and not fi.info.explicit[i] then
          out[#out + 1] = vim.tbl_extend("force", range_of(fi.positional[i + 1]), {
            kind = "unused",
            needs = fi.needs,
            given = P + Nn,
            message = "argument is never used by the format string",
          })
        end
      end'''),
    ...para('--', r'sqlx is handled in the same pass. For query!, query_as! and their scalar and unchecked variants, the SQL string is the first (or second, for query_as) argument, and sql_binds counts parameters: the highest $n for Postgres, otherwise the number of ? marks, after removing -- comments and quoted text. A mismatch with the number of arguments given produces an "sql" hint.'),
    ...code('lua', r'lua/config/macro_tools.lua · lines 460-471', r'''
function M.sql_binds(sql)
  sql = sql:gsub("%-%-[^\n]*", ""):gsub("'[^']*'", "''")
  local max = 0
  for d in sql:gmatch("%$(%d+)") do
    max = math.max(max, tonumber(d))
  end
  if max > 0 then
    return max
  end
  local _, q = sql:gsub("%?", "")
  return q
end'''),
    ...sec(r'hints as diagnostics, and :MacroFormatFix'),
    ...para('--', r'The hints are published as vim.diagnostic entries in their own namespace, at HINT severity with source "xynovim-macro" and the hint kind as the code, so they show as subtle marks and never as errors. They are refreshed 300 ms after edits (TextChanged, InsertLeave, BufWritePost), debounced through one libuv timer per buffer. Above 400,000 bytes the scan is skipped and the namespace reset, a plain cost cap on a lexer that rereads the whole buffer.'),
    ...code('lua', r'lua/config/macro_tools.lua · lines 500-523', r'''
function M.refresh_hints(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) or vim.bo[bufnr].filetype ~= "rust" then
    return
  end
  local text = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
  if #text > MAX_SCAN_BYTES then
    return vim.diagnostic.reset(ns, bufnr)
  end
  local ds = {}
  for _, h in ipairs(M.hints(text)) do
    ds[#ds + 1] = {
      lnum = h.sr,
      col = h.sc,
      end_lnum = h.er,
      end_col = h.ec,
      severity = vim.diagnostic.severity.HINT,
      source = "xynovim-macro",
      code = h.kind,
      message = h.message .. (h.fixable and " (:MacroFormatFix adds it)" or ""),
      user_data = { hint = h },
    }
  end
  vim.diagnostic.set(ns, bufnr, ds)
end'''),
    ...para('--', r'M.format_fix appends the missing arguments for the call around the cursor. It refreshes the hints, finds the fixable "missing" hint whose call spans the cursor line (innermost wins), and inserts todo!() as many times as needed after the last token of the call, not before a closing delimiter that sits alone on a line. If the call already ends in a comma it keeps the trailing comma.'),
    ...code('lua', r'lua/config/macro_tools.lua · lines 567-575', r'''
  local fill = {}
  for _ = 1, best.add do
    fill[#fill + 1] = "todo!()"
  end
  local text = table.concat(fill, ", ")
  text = best.trailing and (" " .. text .. ",") or (", " .. text)
  vim.api.nvim_buf_set_text(bufnr, best.lr, best.lc, best.lr, best.lc, { text })
  M.refresh_hints(bufnr)
  return best.add'''),
    ...sec(r'macro_rules!: reading arms and matching typed arguments'),
    ...para('--', r'For a macro_rules! macro the signature is its list of arms. parse_macro_def uses treesitter on the source of the definition: every macro_rule child gives a matcher text and the compiled structure of its matcher. compile turns tokens into elements: fragments ($name:kind), repetitions ($(...) sep? op), delimited groups and literal tokens.'),
    ...para('--', r'The interesting part is matching what the user has typed against each arm, with three possible answers: 2 means complete, 1 viable (more input could complete it) and 0 no. match_seq is a backtracking matcher over the element list. Fragments like ident, lifetime, block and tt consume one token; expr, ty, pat, path, stmt, item and meta consume a run of tokens, trying every length and keeping the best answer; vis may be empty or pub with an optional (crate) group. Repetitions try zero iterations first (unless +), then loop.'),
    ...code('lua', r'lua/config/macro_tools.lua · lines 718-732', r'''
match_seq = function(elems, ei, toks, ti, cont, budget)
  budget.n = budget.n - 1
  if budget.n < 0 then
    return 1
  end
  if ei > #elems then
    return cont(ti)
  end
  if ti > #toks then
    if rest_nullable(elems, ei) then
      return cont(ti)
    end
    return 1
  end
  local e, t = elems[ei], toks[ti]'''),
    ...code('lua', r'lua/config/macro_tools.lua · lines 807-836', r'''
  else -- rep
    local best = 0
    if e.op ~= "+" then
      best = match_seq(elems, ei + 1, toks, ti, cont, budget)
      if best == 2 then
        return 2
      end
    end
    local function iter(tj)
      return match_seq(e.inner, 1, toks, tj, function(tk)
        local r = match_seq(elems, ei + 1, toks, tk, cont, budget)
        if r == 2 or e.op == "?" or tk > #toks then
          return r
        end
        local nxt = tk
        if e.sep then
          if toks[tk] and same_tok(toks[tk], e.sep) then
            nxt = tk + 1
          else
            return r
          end
        end
        if nxt == tj then
          return r
        end
        return math.max(r, iter(nxt))
      end, budget)
    end
    return math.max(best, iter(ti))
  end'''),
    ...para('--', r'Three decisions keep this safe. A budget counter (20,000 steps in M.match_arm) turns a pathological matcher into "viable" instead of a hang; the spec "stays bounded on a pathological matcher" uses three adjacent $()* repetitions and 78 tokens and asserts it finishes in two seconds. run_ok stops a type or path run at tokens a type cannot contain, so the matcher does not swallow the whole call into one expr. And an unknown fragment kind takes one token. The test table covers vec! and a hand-made macro with five arms, including cases such as "1; 2; 3" which fits no arm.'),
    ...para('--', r'The result is shown by M.popup, which prints each arm as name!(matcher), marks the best arm with ">" and a PmenuSel line highlight, dims arms that cannot fit, adds a legend of the fragments of the best arm (or of all viable arms when the best arm has none, the empty arm of vec! for instance), and says "no arm fits the arguments typed so far" when nothing is viable. FRAGMENT_DOC gives each fragment kind a plain-English line, and a spec asserts every kind has one.'),
    ...sec(r'finding the definition: go-to-definition, not guessing'),
    ...para('--', r'The macro that is called may be a user macro, a dependency macro, or from the standard library. The file asks rust-analyzer: M.find_definition sends textDocument/definition at the macro name, reads the target file (an open buffer wins over disk, 3 MB cap), and parses the macro_definition at the returned range. That makes the popup work for exactly the macros rust-analyzer can resolve, including those in registry crates and the standard library, with no list kept here.'),
    ...code('lua', r'lua/config/macro_tools.lua · lines 1073-1092', r'''
  local client = ra_client(bufnr)
  local function fallback(reason)
    if FALLBACK[name] then
      return cb(M.parse_macro_def(FALLBACK[name], nil, nil, name), "built-in table")
    end
    cb(nil, reason)
  end
  if not client then
    return fallback("no rust-analyzer client")
  end
  local params = {
    textDocument = { uri = vim.uri_from_bufnr(bufnr) },
    position = { line = row, character = lsp_character(bufnr, row, col, client.offset_encoding or "utf-16") },
  }
  client:request("textDocument/definition", params, function(err, result)
    if err or not result or (vim.islist(result) and #result == 0) then
      return fallback("no definition found")
    end
    local loc = vim.islist(result) and result[1] or result
    local uri = loc.targetUri or loc.uri'''),
    ...para('--', r'When the answer is a proc macro (no matcher arms) or nothing at all, the function falls back to a tiny table, FALLBACK, holding the arms of vec, matches and dbg, for the case where the rust-src component is not installed. The location shown in the popup header is shortened: the home directory becomes ~ and anything up to /library/ is dropped, so a standard library macro shows a short path instead of a long toolchain one.'),
    ...sec(r'the signature popup'),
    ...para('--', r'M.signature is called on InsertCharPre for ( [ { and !, on every TextChangedI while the popup is open, and by <C-k> and :MacroSignature in manual mode. It takes at most 300 lines above the cursor, cuts the cursor line at the cursor, and asks M.context_before for the macro call the text ends in: the innermost open group that follows name!, or a bare name! just typed. A key per call position prevents asking again for the same macro while the user types arguments: the parsed definition is kept in sig.def and only the matching is redone, which is cheap.'),
    ...code('lua', r'lua/config/macro_tools.lua · lines 1205-1235', r'''
  if sig.key == key and sig.def then
    return render(sig.def, sig.where)
  end
  sig.key, sig.def = key, nil
  sig.seq = sig.seq + 1
  local seq = sig.seq
  local function request()
    if seq ~= sig.seq or not vim.api.nvim_buf_is_valid(bufnr) then
      return
    end
    M.find_definition(bufnr, ctx.id.sr, math.max(ctx.id.ec - 1, ctx.id.sc), ctx.name, function(def, where)
      if seq ~= sig.seq then
        return
      end
      if not def then
        if opts.manual then
          vim.notify(ctx.name .. "!: " .. tostring(where), vim.log.levels.INFO)
        end
        return close_popup()
      end
      sig.def, sig.where = def, where
      render(def, where)
    end)
  end
  -- rust-analyzer must have seen the typed `name!` before it can resolve it
  if opts.manual then
    request()
  else
    vim.defer_fn(request, 200)
  end
end'''),
    ...para('--', r'Two details are about timing. A sequence number discards answers from a stale request, and in automatic mode the request is delayed by 200 ms because rust-analyzer has to have seen the newly typed name! before it can resolve it; manual mode requests at once. In manual mode when the cursor is not in a macro call at all the function hands over to vim.lsp.buf.signature_help(), so <C-k> keeps its ordinary meaning outside macros.'),
    ...sec(r'snippets for macros rust-analyzer does not complete'),
    ...para('--', r'A small second blink source, registered by blink_opts as provider "macro_tools" with score_offset -1, offers six snippets: tokio::select! in three shapes (two branches, a shutdown loop, biased), matches! with and without a guard, and vec![value; len]. They exist because rust-analyzer completes a macro name but not the shape of its arms. The documentation preview strips the snippet placeholders so what you read is the final text.'),
    ...code('lua', r'lua/config/macro_tools.lua · lines 1241-1259', r'''
local SNIPPETS = {
  {
    label = "select!",
    filter = "select",
    detail = "tokio::select! with two branches",
    text = "tokio::select! {\n\t${1:res} = ${2:future} => ${3:handler},\n\t${4:other} = ${5:future2} => ${0:handler2},\n}",
  },
  {
    label = "select! (shutdown loop)",
    filter = "select",
    detail = "tokio::select! { cancelled => break, recv => ... }",
    text = "tokio::select! {\n\t_ = ${1:token}.cancelled() => break,\n\t${2:msg} = ${3:rx}.recv() => {\n\t\t${0:todo!()}\n\t}\n}",
  },
  {
    label = "select! (biased)",
    filter = "select",
    detail = "tokio::select! with biased; order",
    text = "tokio::select! {\n\tbiased;\n\t${1:res} = ${2:future} => ${3:handler},\n\t${4:other} = ${5:future2} => ${0:handler2},\n}",
  },'''),
    ...para('--', r'get_completions first asks config.ux.snippets_allowed(ctx), so nothing is offered after a dot or inside a string or a comment, and offers the snippets unguarded if that module cannot be loaded. In this repository that guard is richer than the one the plugin ships; see the last section.'),
    ...sec(r'the macro lens: :MacroExpand'),
    ...para('--', r':MacroExpand sends rust-analyzer/expandMacro for the position under the cursor and shows the result in a read-only vertical split with a rust filetype and treesitter highlighting. The window is a stack of levels so you can step into nested expansions and back: the winbar shows a breadcrumb (println! > format_args!), the line count, any note, up to three generated items, and the keys: <CR> to step in, <BS> to go back, gi to list items, q to close.'),
    ...para('--', r'Stepping is the clever part. rust-analyzer can only expand macro calls that are written in the source, positions in the expansion buffer mean nothing to it. So M.lens_step takes the call under the cursor in the expansion, builds a normalised key from its name and whitespace-stripped arguments (call_key), looks for the same call in the original source nearest to where the first expansion started, and expands that. If it finds none, it says that the call was generated by the expansion and cannot be expanded by rust-analyzer. That is an honest limit surfaced as a message rather than hidden.'),
    ...code('lua', r'lua/config/macro_tools.lua · lines 1571-1592', r'''
  local cur = vim.api.nvim_win_get_cursor(0)
  local text = table.concat(vim.api.nvim_buf_get_lines(lens.buf, 0, -1, false), "\n")
  local call = M.call_at(text, cur[1] - 1, cur[2])
  if not call then
    return vim.notify("no macro call under the cursor in the expansion", vim.log.levels.INFO)
  end
  local src = table.concat(vim.api.nvim_buf_get_lines(origin.bufnr, 0, -1, false), "\n")
  local found = M.find_same_call(src, call.key, origin.row)
  if not found then
    return vim.notify(
      ("%s! was generated by the expansion: rust-analyzer only expands macro calls written in the source"):format(call.name),
      vim.log.levels.INFO
    )
  end
  M.expand({
    bufnr = origin.bufnr,
    row = found.id.sr,
    col = found.id.sc + 1,
    push = true,
    step = true,
  })
end'''),
    ...para('--', r'request_expand does the protocol work. rust-analyzer answers -32801 or -32802 ("content modified") while it reloads after an edit, so the request is retried up to 8 times, 250 ms apart. Just after a reload it may answer null for a call it expands a moment later, so a nil answer can be retried too (a count passed by M.expand). And when rust-analyzer cannot run a proc macro it answers with text starting "Expansion had errors": the code turns that into a message pointing at :ProcMacroStatus instead of showing the error text as if it were an expansion.'),
    ...code('lua', r'lua/config/macro_tools.lua · lines 1636-1646', r'''
  ask = function()
    client:request("rust-analyzer/expandMacro", params, function(err, result)
      if err and (err.code == -32801 or err.code == -32802) and tries < 8 then
        tries = tries + 1
        return vim.defer_fn(ask, 250)
      end
      handle(err, result)
    end, bufnr)
  end
  ask()
end'''),
    ...para('--', r'M.expand has a fallback ladder. First the cursor’s own position, then, when the cursor is on a literal or identifier inside the arguments, the start of the enclosing macro_invocation (added in the review-fixes commit 19f974c), then the item’s derives and attribute macros when the cursor is on a struct or fn (item_macro_positions walks the attribute_item siblings, skips built-in attributes such as allow, cfg, inline and repr, and asks at the end of each derive name and attribute path), and as a last resort cargo expand.'),
    ...code('lua', r'lua/config/macro_tools.lua · lines 1833-1845', r'''
  local function request(cb)
    request_expand(bufnr, row, col, function(name, text)
      if name or (ask_row == row and ask_col == col) or opts.step then
        return cb(name, text)
      end
      request_expand(bufnr, ask_row, ask_col, function(n2, t2)
        if n2 then
          return cb(n2, t2)
        end
        cb(name, text or t2)
      end, 2)
    end, 2)
  end'''),
    ...para('--', r'cargo expand runs only when the cursor is actually on a macro (a call, an attribute, a macro definition), because it builds the crate. M.expand_argv derives the argument list from cargo metadata: --lib for the library root, --bin NAME for a binary, or --lib module::path for a file under the library source directory. The command runs through vim.system with an argv list, a 180 second timeout, and a stderr hint that suggests a nightly toolchain when the error mentions it. The lens labels this level FALLBACK so you never mistake it for rust-analyzer’s expansion.'),
    ...code('lua', r'lua/config/macro_tools.lua · lines 1727-1745', r'''
  local base = { "cargo", "expand", "--color", "never", "--manifest-path", manifest }
  local srcdir = lib and vim.fs.dirname(lib.src_path)
  if lib and file == lib.src_path then
    vim.list_extend(base, { "--lib" })
    return base, "the whole library crate"
  end
  if bin then
    vim.list_extend(base, { "--bin", bin.name })
    return base, "the whole binary crate"
  end
  if lib and srcdir and vim.startswith(file, srcdir .. "/") then
    local rel = file:sub(#srcdir + 2):gsub("%.rs$", ""):gsub("/mod$", "")
    local mod = rel:gsub("/", "::")
    if mod:find("^[%w_:]+$") then
      vim.list_extend(base, { "--lib", mod })
      return base, "module " .. mod
    end
  end
  return nil, "the file is not a target of the package"'''),
    ...sec(r':ProcMacroStatus'),
    ...para('--', r'When a proc macro does not run, the symptoms are scattered: red squiggles on valid code, derives that produce no impl, a server that seems to hang. :ProcMacroStatus collects the evidence in one scratch split. It lists the proc-macro crates of the dependency graph from cargo metadata (a crate with proc-macro = true under [lib]), whether a build artifact exists for each (searching target/ and target/rust-analyzer for debug and release, so, dylib and dll), the diagnostics in open buffers that are about macros, and what rust-analyzer says through rust-analyzer/analyzerStatus: whether procMacro.enable and procMacro.attributes.enable are on.'),
    ...code('lua', r'lua/config/macro_tools.lua · lines 1941-1953', r'''
  -- target/ is cargo's own; target/rust-analyzer is where rust-analyzer builds
  -- (cargo.targetDir = true in plugins/rustaceanvim.lua)
  for _, sub in ipairs({ "", "/rust-analyzer" }) do
    for _, profile in ipairs({ "debug", "release" }) do
      for _, ext in ipairs({ "so", "dylib", "dll" }) do
        if #vim.fn.glob(("%s%s/%s/deps/lib%s-*.%s"):format(target_dir, sub, profile, lib, ext), true, true) > 0 then
          return true
        end
      end
    end
  end
  return false
end'''),
    ...para('--', r'Diagnostics are selected by code (macro-error, proc-macro-disabled, unresolved-proc-macro, unresolved-macro-call, macro-def-error) or by message text. The report maps lines to actions: r rebuilds proc macros through :RustLsp rebuildProcMacros, R refreshes, q closes, <CR> jumps to a diagnostic or ignores the crate under the cursor, i picks a crate to ignore.'),
    ...para('--', r'Ignoring is the feature with consequences. A proc macro that is slow or crashes can be put in procMacro.ignored of the project-level rust-analyzer.toml, and the code edits that file. TOML is edited by hand-written code, without a parser, so the function is built around refusing: toml_ignore adds the crate to an existing [procMacro.ignored] table, replaces a previous entry for the same crate (including an array that spans lines, with a "not closed" error if it never ends), and returns nil with an instruction to edit by hand when the setting is written as a dotted key or an inline table. A last sanity check counts the [procMacro.ignored] headers and refuses unless there is exactly one.'),
    ...code('lua', r'lua/config/macro_tools.lua · lines 2085-2102', r'''
    elseif header == "procMacro.ignored" then
      if l:match("^%s*[\"']?" .. vim.pesc(crate) .. "[\"']?%s*=") then
        key_i = i
        key_j = i
        -- a multi-line array: the entry replaces every line up to the closing bracket
        local v = l:gsub("#.*$", "")
        if v:find("[", 1, true) and not v:find("]", 1, true) then
          key_j = nil
          for j = i + 1, #lines do
            if (lines[j]:gsub("#.*$", "")):find("]", 1, true) then
              key_j = j
              break
            end
          end
          if not key_j then
            return nil, "rust-analyzer.toml has an array for this crate that is not closed: fix it by hand"
          end
        end'''),
    ...code('lua', r'lua/config/macro_tools.lua · lines 2129-2140', r'''
  -- cheap sanity check in place of a TOML parser: the table must still be declared once
  local heads = 0
  for _, l in ipairs(lines) do
    local h = l:match("^%s*%[%s*([%w_.%s\"-]-)%s*%]")
    if h and h:gsub("%s", "") == "procMacro.ignored" then
      heads = heads + 1
    end
  end
  if heads ~= 1 then
    return nil, "rust-analyzer.toml has an unusual [procMacro.ignored] layout: add the crate by hand"
  end
  return out:sub(-1) == "\n" and out or (out .. "\n")'''),
    ...para('--', r'The write itself is careful in four ways. It reads and writes in binary mode so a Windows text mode does not rewrite line endings; it detects a CRLF file and converts back; it writes to a temporary file next to the real one and renames, resolving the real path first so a symlinked settings file stays a symlink; and it copies the existing file mode. The rename goes through fsutil.rename. All of that arrived in the review (19f974c) and the portability commit (ff1c8fa).'),
    ...code('lua', r'lua/config/macro_tools.lua · lines 2168-2186', r'''
  -- atomic (tmp + rename) onto the real file, so a symlinked settings file stays one
  local real = uv.fs_realpath(path) or path
  local tmp = ("%s.%d.tmp"):format(real, uv.os_getpid())
  local out, err = io.open(tmp, "wb")
  if not out then
    return nil, err
  end
  out:write(new)
  out:close()
  local st = uv.fs_stat(real)
  if st then
    pcall(uv.fs_chmod, tmp, st.mode % 4096)
  end
  local okr, rerr = require("config.fsutil").rename(tmp, real)
  if not okr then
    uv.fs_unlink(tmp)
    return nil, rerr
  end
  return path'''),
    ...sec(r'wiring: keys, commands and attach timing'),
    ...para('--', r'M.setup defines the four commands, one FileType autocmd that schedules the hint scan and re-schedules it on text changes in Rust buffers, InsertCharPre to open the popup when you type an opener, TextChangedI to refresh it, InsertLeave and BufLeave to close it, and LspAttach for the buffer keys. The keys are <leader>rx for :MacroExpand, <leader>rq for :ProcMacroStatus and insert-mode <C-k> for the macro popup.'),
    ...code('lua', r'lua/config/macro_tools.lua · lines 2358-2373', r'''
local function buf_keys(buf)
  local function map(mode, lhs, rhs, desc, force)
    local existing = vim.fn.maparg(lhs, mode, false, true)
    if not force and existing and existing.buffer == 1 and existing.desc and existing.desc ~= desc then
      return
    end
    vim.keymap.set(mode, lhs, rhs, { buffer = buf, desc = desc })
  end
  map("n", "<leader>rx", "<cmd>MacroExpand<cr>", "Expand macro under cursor (lens)")
  map("n", "<leader>rq", "<cmd>ProcMacroStatus<cr>", "Proc-macro status")
  -- the insert-mode <C-k> of LazyVim is vim.lsp.buf.signature_help: the macro
  -- popup first, that one when the cursor is not in a macro call
  map("i", "<C-k>", function()
    M.signature(buf, { manual = true })
  end, "Macro / signature help", true)
end'''),
    ...para('--', r'Timing is the point of the buf_keys function and its caller. LazyVim’s LSP keymaps are set again on every LspAttach, including <C-k> for signature help, so the maps are set 120 ms after attach, after them, and only when a rust-analyzer client is attached. A key that an existing buffer-local mapping with a different description already owns is left alone, except <C-k>, which is forced. The plugin spec waits for the VeryLazy event for the same reason: setup has to run after LazyVim has set its own maps so the buffer-local ones win.'),
    ...sec(r'the plugin spec'),
    ...para('--', r'lua/plugins/macro-tools.lua is twenty lines. It creates a one-shot autocmd on User VeryLazy that calls setup(), and returns a lazy spec for saghen/blink.cmp whose opts function delegates to blink_opts, which registers the provider and appends "macro_tools" to the default source list when that list is a table. Nothing is loaded until the first Rust buffer matters.'),
    ...sec(r'in xyno-macros.nvim'),
    ...para('--', r'The file was extracted on 2026-10-22 to lua/xyno_macros/tools.lua in ~/projects/xyno-plugins/xyno-macros.nvim (2515 lines, 60 more than here). The core is identical: lexer, formats, matcher, lens, report and TOML editing. What changed is the edge of the module.'),
    ...pt('--', r'dependencies', r'code_actions, crate_meta and fsutil come from xyno_rust.*. The plugin’s init refuses to start with one error line if xyno-rust.nvim or xyno-imports.nvim is missing.'),
    ...pt('--', r'keymaps are opt-in', r'here setup() always maps <leader>rx, <leader>rq and <C-k>. In the plugin they are off unless keymaps = true (or a table of left-hand sides, each may be false), and the defaults live in M.default_keymaps.'),
    ...pt('--', r'commands', r'split out as M.commands() and skipped with commands = false.'),
    ...pt('--', r'snippet guard', r'this file calls config.ux.snippets_allowed, which also rejects expression positions (call arguments, struct field initialisers, token trees) and unclosed calls such as call(a, be. The plugin defines its own M.snippets_allowed that only rejects a position after a dot, inside a string and inside a comment, and the user can replace it with the snippets_allowed option. So in the plugin, select! and matches! snippets are offered inside call arguments, where this configuration hides them. A spec in the plugin (commit 9ab48fb) pins the default guard.'),
    ...pt('--', r'proc-macro rebuild', r'here the r key runs vim.cmd("RustLsp rebuildProcMacros") unconditionally; the plugin checks that :RustLsp exists and warns that rebuilding needs rustaceanvim otherwise.'),
    ...pt('--', r'names', r'namespace xyno_macros_hints, diagnostic source xyno-macros, autocmd group xyno_macros, blink module xyno_macros.tools.'),
    ...sec(r'how it is tested'),
    ...para('--', r'tests/macro-tools_spec.lua (1035 lines) is split the same way as the file. The first half is pure and runs everywhere: the lexer (table of inputs), format placeholders, format and sqlx hints, hint diagnostics and :MacroFormatFix (including a call spanning lines), macro_rules parsing, arm matching (twenty cases over vec! and a five-arm macro), call context, popup text, the blink source (the snippets parse as snippets and nothing is offered after a dot), expansion helpers, the proc-macro report and the TOML edits.'),
    ...para('--', r'The second half, "live rust-analyzer", runs a real server on a copy of the deps-lab fixture and skips without one: expanding println!, a derive and #[tokio::main]; opening the split with its line count; stepping into a nested call and back; the popup for a user macro and for vec! from the standard library; the popup following typed arguments; cargo expand fallback and its refusal away from a macro; a literal inside the arguments; buffer-local keys; and writing the ignore setting from :ProcMacroStatus. The after_each hook stops every client, because a leftover rust-analyzer keeps building.'),
    ...sec(r'history'),
    ...pt('--', r'b9363cd 2026-10-14', r'"Macros and dependencies": the file is added at 2379 lines with its spec and lua/plugins/macro-tools.lua.'),
    ...pt('--', r'19f974c 2026-10-15', r'review fixes (94 changed lines): :MacroExpand asks at the enclosing call when the cursor is on a literal inside the arguments, toml_ignore handles multi-line arrays, comments after headers and a header-count sanity check, the settings write becomes atomic through tmp and rename, and the status line no longer claims 0 proc-macro crates when the status text has no graph.'),
    ...pt('--', r'ff1c8fa 2026-10-16', r'Windows and macOS: the home shortening uses os_homedir and normalised paths, the settings file is read and written in binary mode with CRLF kept, and the rename goes through fsutil.'),
    ...sec(r'rough edges worth knowing'),
    ...pt('--', r'timers', r'schedule_hints keeps one libuv timer per buffer in a table and never closes it, not even when the buffer is wiped. It is a small leak, one handle per Rust buffer ever opened.'),
    ...pt('--', r'hint cost', r'the scan lexes the whole buffer 300 ms after any text change; the 400,000 byte cap is the only brake.'),
  ],
);
