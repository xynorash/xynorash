import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-macros.nvim/lua/xyno_macros/tools.lua',
  lines: [
    cm('--', r'──────────────────────────────────────────'),
    cm('--', r'tools.lua — seeing macros: a lexer, a matcher, a lens, a health report'),
    cm('--', r'the pure parts first, then the UI that wraps them'),
    cm('--', r'──────────────────────────────────────────'),
    kv(r'role', r'macro call help, format hints, snippets, :MacroExpand and :ProcMacroStatus'),
    kv(r'language', r'Lua (Neovim 0.12+), tree-sitter rust, rust-analyzer, optional cargo-expand'),
    kv(r'size', r'2,515 lines, the largest file in the repository'),
    kv(r'layout', r'lexer, format strings, diagnostics, macro_rules matcher, popup, snippets, lens, '
        r'proc-macro report, setup'),
    kv(r'history', r'b9854b7 (2026-10-22); in xynovim lua/config/macro_tools.lua since b9363cd (2026-10-14)'),
    ...sec(r'why this file exists'),
    ...para('--', r'A macro call hides what it expands to and which arm of a macro_rules! definition it matches. '
        r'This module makes macros inspectable at four points: while writing a call (which arm of '
        r'the macro could this match?), while writing a format string (do the placeholders and the '
        r'arguments line up?), after the fact (what does this expand to?) and in project health '
        r'(which proc-macro crates exist, which failed to expand, which are slow enough to be '
        r'ignored?). The header lists them.'),
    ...code('lua', r'lua/xyno_macros/tools.lua · lines 1-14', r'''
-- Macro tools:
--   * macro call help: signature popup for macro_rules! calls (the matcher arms
--     of the definition, found with go-to-definition), format-string and sqlx
--     bind hints, blink snippets for select!/matches!/vec![x; n]
--   * macro lens: :MacroExpand (rust-analyzer/expandMacro in a read-only split,
--     nested stepping, generated items, cargo expand fallback)
--   * proc-macro health: :ProcMacroStatus
--
-- Layout: the pure parts first (lexer, format strings, matcher), then the UI.
-- The pure parts take strings and tables and are what tests/tools_spec.lua
-- drives table-wise. Everything that runs a program uses argv lists; crate
-- names that reach a path or a file are validated first.
local M = {}

'''),
    ...para('--', r'The last paragraph of that header is the architecture. The file is ordered so that the '
        r'pure parts come first and the UI last, and it says why: the pure parts take strings and '
        r'tables and are what tests/tools_spec.lua drives table by table. The final sentence is a '
        r'security note that is easy to miss: everything that runs a program uses argument lists, '
        r'and crate names that reach a path or a file are validated first.'),
    ...sec(r'origin'),
    ...para('--', r'The module began in xynovim as lua/config/macro_tools.lua, added on 2026-10-14 in '
        r'b9363cd, with a review-fix commit the next day (19f974c) and the Windows and macOS '
        r'portability commit of 2026-10-16 (ff1c8fa). In the extraction the README lists the '
        r'differences: the namespace, setup taking options, keys that are opt-in, the blink.cmp '
        r'provider registered through blink_opts, a built-in snippet guard, and a notice instead of '
        r'an error when :RustLsp does not exist.'),
    ...sec(r'a Rust lexer that is exactly as exact as needed'),
    ...code('lua', r'lua/xyno_macros/tools.lua · lines 24-40', r'''
-- ===================================================================== lexer
-- A Rust token lexer that is only as exact as macro help needs: strings (raw,
-- byte, c), chars vs lifetimes, comments, numbers, groups. Groups nest; a
-- group that is not closed (the text ends while typing) has open = true.
--
-- token = { t = "id"|"lit"|"str"|"life"|"p"|"group", s = text, sr, sc, er, ec }
-- (0-based row, byte col, end exclusive); a group adds d = "(" | "[" | "{",
-- kids, open, and cr, cc = the position of its closing delimiter.

local PUNCT3 = { ["..="] = true, ["..."] = true, ["<<="] = true, [">>="] = true }
local PUNCT2 = {}
for _, p in ipairs({ "=>", "::", "->", "..", "==", "!=", "<=", ">=", "&&", "||", "+=", "-=", "*=", "/=", "%=", "^=", "&=", "|=", "<<", ">>" }) do
  PUNCT2[p] = true
end
local CLOSER = { ["("] = ")", ["["] = "]", ["{"] = "}" }

--- Tokens of `text`. opts.row0 / opts.col0 shift the reported positions (the
'''),
    ...para('--', r'The lexer does not try to be rustc. It knows strings (raw, byte, c), chars versus '
        r'lifetimes, comments, numbers and groups, and nothing else. A group that is not closed '
        r'because the user is still typing is marked open, which is the one property the whole '
        r'signature feature depends on: the innermost open group is the macro call being written. '
        r'Positions are 0-based rows and byte columns, with an offset option for text taken from '
        r'the middle of a buffer. The comment spells out the token shape.'),
    ...code('lua', r'lua/xyno_macros/tools.lua · lines 236-250', r'''
function M.split_args(kids)
  local args, cur = {}, {}
  for _, t in ipairs(kids) do
    if is_p(t, ",") then
      args[#args + 1] = cur
      cur = {}
    else
      cur[#cur + 1] = t
    end
  end
  if #cur > 0 then
    args[#args + 1] = cur
  end
  return args
end
'''),
    ...para('--', r'Small helpers sit on top. string_content strips quotes and, for non-raw strings, removes '
        r'\u{...} escapes, because their braces are not placeholders. split_args divides a group at '
        r'top-level commas and ignores a trailing comma. each_call visits every name!(...) in a '
        r'token list, nested calls included, and recovers the first segment of a path like '
        r'a::b::name!. These three functions are used by every feature below.'),
    ...sec(r'format strings: counting placeholders'),
    ...code('lua', r'lua/xyno_macros/tools.lua · lines 280-284,329-330', r'''
function M.parse_format(s)
  local info = { count = 0, implicit = 0, explicit = {}, names = {}, max_explicit = -1 }
  local i = 1
  while true do
    local p = s:find("[{}]", i)
...
  info.needs = math.max(info.implicit, info.max_explicit + 1)
  return info
'''),
    ...para('--', r'parse_format reads the content of a format string and counts what the arguments must '
        r'supply: implicit placeholders, explicit indexes, named references and the width and '
        r'precision arguments written as name$ or .*. Doubled braces are escapes. A malformed '
        r'string returns nil and a reason, and the doc comment gives the reason for giving up: '
        r'rustc reports those itself. The result carries needs, the number of arguments the string '
        r'requires.'),
    ...code('lua', r'lua/xyno_macros/tools.lua · lines 334-339', r'''
local FORMAT_AT = {
  println = 0, print = 0, eprintln = 0, eprint = 0, format = 0, format_args = 0, panic = 0,
  unreachable = 0, todo = 0, unimplemented = 0,
  write = 1, writeln = 1, assert = 1, debug_assert = 1,
  assert_eq = 2, assert_ne = 2, debug_assert_eq = 2, debug_assert_ne = 2,
}
'''),
    ...para('--', r'FORMAT_AT is a table from macro name to the position of the format string among its '
        r'arguments: print! and format! at 0, write! and assert! at 1, assert_eq! at 2. The tracing '
        r'and log macros are different, because their fields come first, so the format string is '
        r'the first argument that is only a string literal. The path must be absent or one of the '
        r'known crates, so a user macro called println! in another crate is not analysed.'),
    ...code('lua', r'lua/xyno_macros/tools.lua · lines 404-418', r'''
local function call_hints(call)
  local out = {}
  local fi = M.format_info(call)
  if fi then
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
'''),
    ...para('--', r'call_hints compares the needed count with what is given. Too few arguments gives a hint '
        r'of kind missing, with the number to add and a fixable flag that is true when no named '
        r'arguments are present (it is not clear where to put them). Too many gives unused hints, '
        r'for positional arguments that no placeholder refers to and for named arguments that are '
        r'never named in the string. The sqlx macros get the same treatment with SQL: the highest '
        r'$n for Postgres or the count of ? for MySQL and SQLite is compared with the arguments '
        r'after the query.'),
    ...code('lua', r'lua/xyno_macros/tools.lua · lines 467-471', r'''
function M.sql_binds(sql)
  sql = sql:gsub("%-%-[^\n]*", ""):gsub("'[^']*'", "''")
  local max = 0
  for d in sql:gmatch("%$(%d+)") do
    max = math.max(max, tonumber(d))
'''),
    ...para('--', r'sql_binds first removes comments introduced by two dashes and replaces quoted text with '
        r'empty quotes, so that a question mark or dollar sign inside a string literal is not '
        r'counted.'),
    ...sec(r'diagnostics and the fix'),
    ...code('lua', r'lua/xyno_macros/tools.lua · lines 507-514,540-548', r'''
function M.refresh_hints(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) or vim.bo[bufnr].filetype ~= "rust" then
    return
  end
  local text = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
  if #text > MAX_SCAN_BYTES then
    return vim.diagnostic.reset(ns, bufnr)
  end
...
  t:start(
    300,
    0,
    vim.schedule_wrap(function()
      if vim.api.nvim_buf_is_valid(bufnr) then
        M.refresh_hints(bufnr)
      end
    end)
  )
'''),
    ...para('--', r'The hints are published as HINT-severity diagnostics in their own namespace, with the '
        r'source xyno-macros and the code equal to the hint kind, and a note in the message when '
        r':MacroFormatFix can repair it. A buffer larger than 400 KB is skipped (and its hints '
        r'cleared), which is the bound on the scan. schedule_hints keeps one libuv timer per buffer '
        r'and restarts it on each change, so the scan runs 300 milliseconds after the last edit.'),
    ...code('lua', r'lua/xyno_macros/tools.lua · lines 574-580', r'''
  local fill = {}
  for _ = 1, best.add do
    fill[#fill + 1] = "todo!()"
  end
  local text = table.concat(fill, ", ")
  text = best.trailing and (" " .. text .. ",") or (", " .. text)
  vim.api.nvim_buf_set_text(bufnr, best.lr, best.lc, best.lr, best.lc, { text })
'''),
    ...para('--', r'format_fix finds the missing-argument hint that contains the cursor line (the innermost '
        r'one wins when calls nest), then appends the right number of todo!() arguments right after '
        r'the last token, not before a closing delimiter on its own line, and keeps a trailing '
        r'comma if the call had one. It returns the number added and refreshes the hints. The '
        r'placeholder it appends is todo!().'),
    ...sec(r'macro_rules! arms: the matcher'),
    ...code('lua', r'lua/xyno_macros/tools.lua · lines 619-626,640-641', r'''
local function compile(toks)
  local out, i = {}, 1
  while i <= #toks do
    local t = toks[i]
    local nx = toks[i + 1]
    if is_p(t, "$") and nx and nx.t == "id" and is_p(toks[i + 2], ":") and toks[i + 3] and toks[i + 3].t == "id" then
      out[#out + 1] = { k = "frag", name = nx.s, spec = toks[i + 3].s }
      i = i + 4
...
        out[#out + 1] = { k = "rep", inner = compile(nx.kids), sep = sep, op = o }
        i = j
'''),
    ...para('--', r'compile turns the matcher tokens of an arm into elements: a fragment ($name:kind), a '
        r'repetition ($( ... ) sep op), a nested group, or a literal token. This is the '
        r'macro_rules! grammar, and nothing more.'),
    ...code('lua', r'lua/xyno_macros/tools.lua · lines 660-673', r'''
local function nullable(e)
  if e.k == "rep" then
    if e.op ~= "+" then
      return true
    end
    for _, x in ipairs(e.inner) do
      if not nullable(x) then
        return false
      end
    end
    return true
  end
  return e.k == "frag" and e.spec == "vis"
end
'''),
    ...para('--', r'Two questions need an answer before matching. nullable says whether an element can match '
        r'nothing: a star or a question mark repetition, a plus repetition of nullable elements, or '
        r'a vis fragment. rest_nullable asks the same of the tail of an arm. They matter because a '
        r'call whose arguments are not finished yet still fits an arm if what is missing could be '
        r'empty.'),
    ...code('lua', r'lua/xyno_macros/tools.lua · lines 725-738', r'''
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
'''),
    ...para('--', r'match_seq is the matcher, a backtracking search with three outcomes rather than two: 2 '
        r'for a complete match, 1 for viable (the typed prefix could still be completed), 0 for no. '
        r'That third state is what makes a signature popup possible, since a call is almost always '
        r'incomplete. Each recursive call decrements a shared budget, and when the budget runs out '
        r'the answer is viable, never no.'),
    ...code('lua', r'lua/xyno_macros/tools.lua · lines 786-789,799-803', r'''
    if RUN[spec] then
      local best, depth = 0, 0
      for len = 1, #toks - ti + 1 do
        local tk = toks[ti + len - 1]
...
        if not run_ok(spec, tk, depth) then
          break
        end
        local r = match_seq(elems, ei + 1, toks, ti + len, cont, budget)
        if r > best then
'''),
    ...para('--', r'The expression-like fragments (expr, ty, pat, path, stmt, item, meta) have no length, so '
        r'the matcher tries every run length and keeps the best result. run_ok limits which tokens '
        r'a run may contain: a type or path cannot contain a string or a brace group, an expression '
        r'cannot contain a semicolon or a fat arrow, and a comma outside any nesting ends it. Angle '
        r'brackets are counted for types so that HashMap<K, V> is one run.'),
    ...code('lua', r'lua/xyno_macros/tools.lua · lines 847-851', r'''
function M.match_arm(elems, toks)
  return match_seq(elems, 1, toks, 1, function(ti)
    return ti == #toks + 1 and 2 or 0
  end, { n = 20000 })
end
'''),
    ...para('--', r'match_arm starts the search with a budget of 20,000 steps. match_arms runs every arm and '
        r'picks the first complete one as best, else the first viable one. The spec ends its '
        r'matching group with a pathological macro of three adjacent repetitions fed seventy-eight '
        r'tokens and asserts that it finishes within two seconds.'),
    ...sec(r'reading the definition'),
    ...para('--', r'def_of_node reads a macro_definition node with the tree-sitter grammar: the name, and for '
        r'each rule the left side, whose text becomes the display string (whitespace collapsed) and '
        r'whose tokens are compiled. parse_macro_def finds a definition either by position or by '
        r'name. A table of fallbacks for vec!, matches! and dbg! covers the case where the '
        r'definition cannot be found because the rust-src component is not installed.'),
    ...sec(r'the call context'),
    ...code('lua', r'lua/xyno_macros/tools.lua · lines 947-949,966-981', r'''
function M.context_before(text, opts)
  local toks = M.lex(text, opts)
  local chain = {} -- open groups, outermost first, with the token list they sit in
...
  for depth = #chain, 1, -1 do
    local link = chain[depth]
    local k = link.index
    local sib = link.list
    if is_p(sib[k - 1], "!") and sib[k - 2] and sib[k - 2].t == "id" then
      local id = sib[k - 2]
      local path
      if is_p(sib[k - 3], "::") and sib[k - 4] and sib[k - 4].t == "id" then
        local j = k - 4
        while is_p(sib[j - 1], "::") and sib[j - 2] and sib[j - 2].t == "id" do
          j = j - 2
        end
        path = sib[j].s
      end
      return { name = id.s, path = path, id = id, group = link.group, innermost = depth == #chain }
    end
'''),
    ...para('--', r'context_before takes the text before the cursor and finds the macro call being written. '
        r'It follows the chain of open groups, outermost first, and looks at each one for a '
        r'preceding ! and identifier. It also handles the case where only name! has been typed with '
        r'nothing after it. The result says whether this macro is the innermost open group, which '
        r'decides if the popup should show: the popup follows the call the cursor is in, not an '
        r'outer one.'),
    ...sec(r'the popup'),
    ...code('lua', r'lua/xyno_macros/tools.lua · lines 990-1001', r'''
function M.popup(name, def, toks, extra)
  local m = M.match_arms(def, toks or {})
  local lines, marks = {}, {}
  local any = false
  for i, arm in ipairs(def.arms) do
    local close = ({ ["("] = ")", ["["] = "]", ["{"] = "}" })[arm.delim]
    local body = arm.matcher == "" and "" or (" " .. arm.matcher .. " ")
    local viable = m.results[i] >= 1
    any = any or viable
    lines[#lines + 1] = (i == m.best and "> " or "  ") .. name .. "!" .. arm.delim .. body .. close
    marks[#marks + 1] = { line = #lines, best = i == m.best, viable = viable }
  end
'''),
    ...para('--', r'popup renders the arms, one line each, marks the best with a > and records which arms are '
        r'still viable so that the window can dim the others. A legend lists the fragments of the '
        r'best arm with a plain-language explanation from FRAGMENT_DOC (expr is an expression, tt '
        r'is one token tree). When the best arm has no fragments, as with the empty arm of vec!, '
        r'the legend shows every viable arm’s. A format macro adds a line about placeholders and '
        r'arguments, and if no arm fits the popup says so.'),
    ...sec(r'finding the definition through the language server'),
    ...code('lua', r'lua/xyno_macros/tools.lua · lines 1082-1086,1109-1115', r'''
    if FALLBACK[name] then
      return cb(M.parse_macro_def(FALLBACK[name], nil, nil, name), "built-in table")
    end
    cb(nil, reason)
  end
...
    local def = M.parse_macro_def(src, range.start.line, range.start.character)
    if not def or #def.arms == 0 then
      return fallback("not a macro_rules! macro (a proc macro has no matcher arms)")
    end
    local home = vim.fs.normalize(vim.uv.os_homedir() or "")
    local short = vim.fs.normalize(fname):gsub("^" .. vim.pesc(home), "~"):gsub("^.*/library/", "")
    cb(def, ("%s:%d"):format(short, def.row + 1))
'''),
    ...para('--', r'find_definition asks rust-analyzer for textDocument/definition at the macro name, reads '
        r'the file (an open buffer wins over the disk, files over 3 MB are refused), and parses the '
        r'macro. Every failure path falls back to the built-in table when the name is vec, matches '
        r'or dbg, and otherwise reports a reason: no client, no definition, cannot read, or not a '
        r'macro_rules! macro, which the message explains by saying a proc macro has no matcher '
        r'arms. The path shown is shortened: the home directory becomes a tilde and everything up '
        r'to library/ is cut, which leaves a readable path for a std macro.'),
    ...code('lua', r'lua/xyno_macros/tools.lua · lines 1199-1214', r'''
  local key = ("%d:%d:%d:%s"):format(bufnr, ctx.id.sr, ctx.id.sc, ctx.name)
  local function render(def, where)
    if sig.key ~= key then
      return
    end
    local view = M.popup(ctx.name, def, toks, extra_lines(ctx, toks))
    local head = ctx.name .. "!" .. (where and ("  " .. where) or "")
    table.insert(view.lines, 1, head)
    for _, mk in ipairs(view.marks) do
      mk.line = mk.line + 1
    end
    open_popup(view.lines, view.marks)
  end
  if sig.key == key and sig.def then
    return render(sig.def, sig.where)
  end
'''),
    ...para('--', r'signature ties it together. It lexes up to 300 lines before the cursor, finds the context '
        r'and builds a key from the buffer, the position of the name and the name. A sequence '
        r'number discards stale answers when the user types faster than the server responds. If the '
        r'definition for this key is cached it renders at once, otherwise it requests it, deferred '
        r'by 200 milliseconds in automatic mode so that rust-analyzer has seen the name just typed. '
        r'In manual mode, from :MacroSignature or the key, it asks immediately and reports why '
        r'nothing shows. The signature_help fallback is the reason the insert-mode key is useful: '
        r'when the cursor is not in a macro call, it falls through to the language server’s own '
        r'signature help.'),
    ...sec(r'snippets'),
    ...code('lua', r'lua/xyno_macros/tools.lua · lines 1248-1254', r'''
local SNIPPETS = {
  {
    label = "select!",
    filter = "select",
    detail = "tokio::select! with two branches",
    text = "tokio::select! {\n\t${1:res} = ${2:future} => ${3:handler},\n\t${4:other} = ${5:future2} => ${0:handler2},\n}",
  },
'''),
    ...para('--', r'The snippet source covers macro forms that rust-analyzer does not complete: '
        r'tokio::select! with two branches, a shutdown loop and a biased variant, matches! with and '
        r'without a guard, and vec![x; n]. They are plain LSP snippets with placeholders.'),
    ...code('lua', r'lua/xyno_macros/tools.lua · lines 1295-1301,1311-1317', r'''
function M.snippets_allowed(ctx)
  if type(M.config.snippets_allowed) == "function" then
    return M.config.snippets_allowed(ctx)
  end
  local before = ctx.line:sub(1, ctx.cursor[2])
  if before:match("[^%.]%.[%w_]*$") then
    return false
...
    local behind = t:find("literal$") and erow == ctx.cursor[1] - 1 and ecol <= ctx.cursor[2]
    if (t:find("string") or t:find("comment")) and not behind then
      return false
    end
    node = node:parent()
  end
  return true
'''),
    ...para('--', r'snippets_allowed decides where they may appear. The default is deliberately small: not '
        r'after a dot, so no method-call confusion, and not inside a string or comment, found by '
        r'walking the tree-sitter ancestors, with one correction, that a literal ends at its '
        r'closing quote so the cursor behind it counts as outside. The README admits that it does '
        r'not carry over the original configuration’s own expression-node check, and the last '
        r'commit, 9ab48fb, added specs for the default guard for exactly that reason. The user can '
        r'replace the function through setup.'),
    ...code('lua', r'lua/xyno_macros/tools.lua · lines 1353-1360', r'''
  opts.sources.providers.macro_tools = {
    name = "Macro",
    module = "xyno_macros.tools",
    score_offset = -1,
  }
  if type(opts.sources.default) == "table" and not vim.tbl_contains(opts.sources.default, "macro_tools") then
    table.insert(opts.sources.default, "macro_tools")
  end
'''),
    ...para('--', r'blink_opts registers the provider at a slightly negative score offset, so snippets rank '
        r'below real completions, and adds it to the default source list only when that list is a '
        r'table. A configuration where sources.default is a function is left alone, and the '
        r'snippets silently do not appear; the README does not mention this case.'),
    ...sec(r'the lens: reading an expansion'),
    ...code('lua', r'lua/xyno_macros/tools.lua · lines 1662-1665,1672-1677', r'''
    -- rust-analyzer answers with this text when a proc macro cannot run
    if result.expansion:find("^Expansion had errors") then
      return cb(nil, "rust-analyzer could not expand it: " .. vim.trim((result.expansion:gsub("^Expansion had errors:%s*", ""))) .. " (see :ProcMacroStatus)")
    end
...
      if err and (err.code == -32801 or err.code == -32802) and tries < 8 then
        tries = tries + 1
        return vim.defer_fn(ask, 250)
      end
      handle(err, result)
    end, bufnr)
'''),
    ...para('--', r'request_expand asks rust-analyzer for rust-analyzer/expandMacro at a position. Three '
        r'details come from observation of the server. Right after a reload it may answer null for '
        r'a call it expands a moment later, so a null result can be retried every 300 milliseconds. '
        r'The LSP error codes for content modified (-32801 and -32802) are retried up to eight '
        r'times at 250 milliseconds. And an expansion that begins with Expansion had errors is '
        r'converted into an error message that points the user to :ProcMacroStatus.'),
    ...code('lua', r'lua/xyno_macros/tools.lua · lines 1751-1756,1771-1777', r'''
      if k == "lib" or k == "proc-macro" then
        lib = lib or t
      elseif k == "bin" then
        if t.src_path == file then
          bin = t
        end
...
  if lib and srcdir and vim.startswith(file, srcdir .. "/") then
    local rel = file:sub(#srcdir + 2):gsub("%.rs$", ""):gsub("/mod$", "")
    local mod = rel:gsub("/", "::")
    if mod:find("^[%w_:]+$") then
      vim.list_extend(base, { "--lib", mod })
      return base, "module " .. mod
    end
'''),
    ...para('--', r'When rust-analyzer expands nothing, :MacroExpand falls back to cargo expand. expand_argv '
        r'works out the narrowest invocation: the library target when the file is its root, a '
        r'binary target when the file is its source, or --lib with a module path computed from the '
        r'file’s location when the file lies under the library’s source directory, and otherwise an '
        r'error that the file is not a target of the package. The module path is only used if it '
        r'consists of identifier characters and colons.'),
    ...para('--', r'The fallback checks that cargo-expand is installed, asks cargo metadata for the workspace '
        r'member, builds the argument list, and runs it with a three-minute timeout through '
        r'vim.system with an argv list, never a shell. A failure that mentions nightly or -Z '
        r'produces a message that says cargo expand needs a nightly toolchain. The output becomes a '
        r'level of the lens stack, labelled FALLBACK so the user knows what they are reading.'),
    ...sec(r'the proc-macro report'),
    ...code('lua', r'lua/xyno_macros/tools.lua · lines 1927-1933', r'''
local MACRO_CODES = {
  ["macro-error"] = true,
  ["proc-macro-disabled"] = true,
  ["unresolved-proc-macro"] = true,
  ["unresolved-macro-call"] = true,
  ["macro-def-error"] = true,
}
'''),
    ...para('--', r'macro_diagnostics selects the diagnostics that are about macros that did not expand: five '
        r'known rust-analyzer codes, plus a loose match on messages containing proc macro, macro '
        r'expansion or not expanded.'),
    ...para('--', r'parse_analyzer_status reads rust-analyzer’s analyzerStatus text: each Crate line begins a '
        r'record, and Is a proc macro crate sets a flag on the current record. It also picks out '
        r'the procMacro enable settings from the configuration dump.'),
    ...code('lua', r'lua/xyno_macros/tools.lua · lines 1990-2003', r'''
function M.proc_macro_crates(meta, target_dir)
  local cm = require("xyno_rust.crate_meta")
  local out = {}
  for _, p in ipairs(meta.packages) do
    local toml = p.dir and cm.read_manifest(p.dir)
    if toml and (toml:match("%[lib%].-\nproc[-_]macro%s*=%s*true") or toml:match("%[lib%]\nproc[-_]macro%s*=%s*true")) then
      out[#out + 1] = {
        name = p.name,
        version = p.version,
        member = p.is_member,
        dir = p.dir,
        built = dylib_built(target_dir, p.name),
      }
    end
'''),
    ...para('--', r'dylib_built asks whether a proc-macro crate has been compiled, by globbing for '
        r'lib<name>-*.so, dylib or dll under target, and under target/rust-analyzer where '
        r'rust-analyzer builds when its own target directory is enabled, for both profiles. '
        r'proc_macro_crates lists the packages whose manifest declares proc-macro = true in the lib '
        r'table, members first, and attaches the built flag. This is how the report can say that a '
        r'crate has not been built.'),
    ...sec(r'editing a TOML file without a TOML parser'),
    ...code('lua', r'lua/xyno_macros/tools.lua · lines 2105-2108,2141-2143', r'''
  if #items == 0 then
    items = { '"*"' } -- every macro of the crate
  end
  local entry = ('"%s" = [%s]'):format(crate, table.concat(items, ", "))
...
    elseif l:match("^%s*procMacro%.ignored") or (header == "procMacro" and l:match("^%s*ignored%s*=")) then
      return nil, "rust-analyzer.toml sets procMacro.ignored in a form that is not edited automatically: add the crate by hand"
    end
'''),
    ...para('--', r'toml_ignore adds a crate to [procMacro.ignored] in rust-analyzer.toml. The design is '
        r'conservative. It scans lines, tracks the current table header, and finds an existing '
        r'entry for the crate, including a multi-line array. If the file sets the option in a form '
        r'it does not understand, a dotted key or an inline table, it refuses and returns a message '
        r'telling the user to add the crate by hand. It does not guess.'),
    ...code('lua', r'lua/xyno_macros/tools.lua · lines 2163-2173', r'''
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
'''),
    ...para('--', r'After editing, a sanity check counts the headers named procMacro.ignored and refuses the '
        r'result unless there is exactly one. It returns a text that ends in a newline. The writer, '
        r'ignore_proc_macro, saves atomically (a temporary file and a rename) onto the real path, '
        r'so a symlinked settings file stays one, as its comment says, and prefers '
        r'.rust-analyzer.toml when that is the file that exists.'),
    ...sec(r'the report window'),
    ...code('lua', r'lua/xyno_macros/tools.lua · lines 2295-2300', r'''
  map("r", function()
    if vim.fn.exists(":RustLsp") ~= 2 then
      return vim.notify("ProcMacroStatus: rebuilding proc macros needs rustaceanvim (:RustLsp)", vim.log.levels.WARN)
    end
    vim.cmd("RustLsp rebuildProcMacros")
  end, "Rebuild proc macros")
'''),
    ...para('--', r'The report is a scratch buffer with a handful of keys: q closes, r runs RustLsp '
        r'rebuildProcMacros (and says so if rustaceanvim is not there), R refreshes, i picks a '
        r'crate to ignore, and Enter acts on the line under the cursor, ignoring a crate or jumping '
        r'to a diagnostic. All maps are buffer-local with nowait.'),
    ...code('lua', r'lua/xyno_macros/tools.lua · lines 2376-2384', r'''
    client:request("rust-analyzer/analyzerStatus", { textDocument = { uri = vim.uri_from_bufnr(src) } }, function(e, text)
      if not e and type(text) == "string" then
        data.status = M.parse_analyzer_status(text)
        local pmc = vim.tbl_filter(function(c)
          return c.proc_macro
        end, data.status.crates)
        -- a count of 0 would contradict the list below when the status text has no crate graph
        data.server = #pmc == 0 and ("rust-analyzer " .. client.name)
          or ("rust-analyzer %s; %d proc-macro crate%s in this file's crates"):format(client.name, #pmc, #pmc == 1 and "" or "s")
'''),
    ...para('--', r'proc_macro_status gathers the pieces asynchronously: cargo metadata for the crates and '
        r'the target directory, the macro diagnostics from the whole session, the ignored list from '
        r'the project, and the analyzer status from the server. If no server is attached it still '
        r'draws the report and says so. One comment shows attention to a detail: a count of zero '
        r'proc-macro crates would contradict the list below it when the status text has no crate '
        r'graph, so the server line then omits the count.'),
    ...sec(r'setup: keys and autocmds'),
    ...code('lua', r'lua/xyno_macros/tools.lua · lines 2411-2417', r'''
  map("n", keymaps.expand, "<cmd>MacroExpand<cr>", "Expand macro under cursor (lens)")
  map("n", keymaps.status, "<cmd>ProcMacroStatus<cr>", "Proc-macro status")
  -- an LSP config may bind insert-mode <C-k> to vim.lsp.buf.signature_help: the macro
  -- popup first, that one when the cursor is not in a macro call
  map("i", keymaps.signature, function()
    M.signature(buf, { manual = true })
  end, "Macro / signature help", true)
'''),
    ...para('--', r'Keys are buffer-local, and set in an LspAttach callback that waits 120 milliseconds, '
        r'because LSP configurations may set keys such as <C-k> again on every attach, and these '
        r'must come after them. The map helper does not override an existing buffer-local map with '
        r'a different description, except for the insert-mode key, which is forced: the macro popup '
        r'first, and the server’s signature help as the fallback.'),
    ...code('lua', r'lua/xyno_macros/tools.lua · lines 2449-2455,2464-2472', r'''
  local group = vim.api.nvim_create_augroup("xyno_macros", { clear = true })
  vim.api.nvim_create_autocmd("FileType", {
    group = group,
    pattern = "rust",
    callback = function(ev)
      schedule_hints(ev.buf)
      vim.api.nvim_create_autocmd({ "TextChanged", "InsertLeave", "BufWritePost" }, {
...
  vim.api.nvim_create_autocmd("InsertCharPre", {
    group = group,
    callback = function(ev)
      if vim.bo[ev.buf].filetype ~= "rust" or not ra_client(ev.buf) then
        return
      end
      local ch = vim.v.char
      if ch == "(" or ch == "[" or ch == "{" or ch == "!" then
        vim.schedule(function()
'''),
    ...para('--', r'setup stores the keymap table, registers the commands, and creates one augroup. FileType '
        r'rust schedules a hint scan and adds the buffer-local autocmds that rescan after changes. '
        r'InsertCharPre calls the popup when the typed character is an opening bracket or a bang. '
        r'TextChangedI refreshes an open popup. InsertLeave and BufLeave close it. The last loop '
        r'catches buffers that were already open when setup ran. One small thing to know: the '
        r'FileType callback adds new buffer-local autocmds to the shared group every time it fires, '
        r'so a buffer whose filetype event fires twice can carry duplicates; the code does not '
        r'guard against it.'),
    ...sec(r'design decisions'),
    ...pt('--', r'Three-valued matching', r'complete, viable, impossible. A call being typed is never complete, so a boolean matcher '
        r'would show nothing.'),
    ...pt('--', r'Budgets everywhere', r'the matcher steps, the scan size, the retry counts and the cargo-expand timeout are all bounded.'),
    ...pt('--', r'Server first, fallbacks after', r'rust-analyzer for definitions and expansions, tables for std macros, cargo expand for '
        r'what the server cannot expand.'),
    ...pt('--', r'Refuse rather than guess', r'the TOML editor, the module path of cargo expand and the macro-path checks all decline when unsure.'),
    ...sec(r'tested by'),
    ...para('--', r'tests/tools_spec.lua: tables for the lexer, placeholders, hints, arm matching, call '
        r'context, popup, expansion helpers and the report, then a live group against a real '
        r'rust-analyzer.'),
    ...sec(r'history'),
    ...pt('--', r'b9854b7', r'2026-10-22, Add the xyno_macros modules.'),
    ...pt('--', r'9ab48fb', r'2026-10-22: specs for the default snippet guard, with the README and help noting the blink.cmp pin.'),
  ],
);
