import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/tests/snippets-completion-injections_spec.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'snippets-completion-injections_spec.lua — snippets, a quiet completion menu and SQL inside Rust strings'),
    cm('--', r'seven snippets that must expand, a guard against snippet noise after a dot, and a treesitter query that recognises SQL'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'spec for snippets/rust.json, ux.snippets_allowed, the blink provider wiring, no-ghost-text and after/queries/rust/injections.scm and the parsers of domain.lua'),
    kv(r'language', r'Lua spec, 602 lines, 26 it() blocks, 6 describe() blocks'),
    kv(r'needs', r'no rust-analyzer: buffers are opened with FileType autocmds ignored so no LSP client starts'),
    kv(r'history', r'3 commits, 2026-10-13 to 2026-10-14'),
    ...sec(r'why this file exists'),
    ...para('--', r'Three small features share this file because they share a mechanism: what the completion menu and the highlighter do with Rust text depends on where in the syntax tree the cursor is. Snippets must appear at a statement start and not after a dot or inside a string. Ghost text must be off. And the highlighter must know that the string inside query!( is SQL. All three are decided by treesitter nodes and a few configuration values, which can be tested without any language server. The header says the buffers are opened in a way that starts no client.'),
    ...code('lua', r'tests/snippets-completion-injections_spec.lua · lines 1-6', r'''
-- Snippets, completion guard and SQL injections: snippets/rust.json,
-- lua/config/ux.lua (snippets_allowed), lua/plugins/editing-ui.lua (blink
-- provider wiring), lua/plugins/no-ghost-text.lua, after/queries/rust/injections.scm
-- and lua/plugins/domain.lua (parsers). No rust-analyzer needed: the buffers
-- are opened with FileType autocmds ignored, so no LSP client starts.
local H = require("xynotest.helpers")'''),
    ...sec(r'the seven snippets'),
    ...para('--', r'The snippet file is valid JSON with exactly seven snippets, each with a prefix, a body that is a non-empty list of strings, and a non-empty description. A table in the spec fixes names and prefixes. The bodies must be the documented ones, and a third test expands each body with vim.snippet.expand and checks that it is a valid LSP snippet with its defaults filled in. A snippet that does not parse would only fail when a user triggered it.'),
    ...code('lua', r'tests/snippets-completion-injections_spec.lua · lines 177-197', r'''
  it("is valid JSON with exactly the 7 snippets, each with prefix, body (array) and description", function()
    local ok, data = pcall(vim.json.decode, read(H.repo .. "/snippets/rust.json"))
    H.ok(ok, "invalid JSON: " .. tostring(data))
    local names = vim.tbl_keys(data)
    table.sort(names)
    local want = vim.tbl_keys(NAMES)
    table.sort(want)
    H.eq(want, names)
    for name, prefix in pairs(NAMES) do
      local s = data[name]
      H.eq(prefix, s.prefix, name .. " prefix")
      H.eq("table", type(s.body), name .. " body")
      H.ok(#s.body >= 1, name .. " body is a non-empty array")
      H.ok(vim.islist(s.body), name .. " body is a list")
      for _, line in ipairs(s.body) do
        H.eq("string", type(line))
      end
      H.eq("string", type(s.description), name .. " description")
      H.ok(s.description ~= "", name .. " description is not empty")
    end
  end)'''),
    ...sec(r'the completion menu'),
    ...para('--', r'blink.cmp picks up the snippets in stdpath config by default, so no search_paths field is set; revalidating the merged blink options must raise no Unexpected field warning; the snippets provider has should_show_items wired to ux.snippets_allowed; and ghost text is disabled in insert mode and in the cmdline. In a Rust buffer the menu offers testmod and not tmod (rust-analyzer own tmod outranked the snippet), ttest expands to the Tokio test snippet, and the friendly-snippets if is offered at the start of a statement but not after x.'),
    ...sec(r'where a snippet may appear'),
    ...para('--', r'snippets_allowed is the guard. It is false right after a dot and true after a range operator; the examples in the test are ok.if|, x.i| and x.| (false), and let _ = 0..i| and if| (true). It is false inside strings, raw strings, line comments and block comments and true in plain code; true just behind the closing quote on the same line; false in expression positions (call arguments, struct literals, macro token trees) and true in a block inside them; true when treesitter get_node errors; and true in a non-Rust buffer without string or comment nodes. The rule favours showing a snippet when the guard cannot tell, because hiding useful snippets is a worse failure than showing a useless one.'),
    ...code('lua', r'tests/snippets-completion-injections_spec.lua · lines 355-362', r'''
  it("is false right after a `.` and true after a `..` range", function()
    H.eq(false, allowed("ok.if|"))
    H.eq(false, allowed("x.i|"))
    H.eq(false, allowed("x.|"))
    H.eq(true, allowed("let _ = 0..i|"))
    H.eq(true, allowed("if|"))
  end)
'''),
    ...sec(r'SQL in strings'),
    ...para('--', r'injections.scm extends the runtime query of the Rust parser. The tests cover which strings count. All six sqlx macros, query, query_as, query_scalar and the three unchecked variants, are covered both bare and as sqlx::query!, with a plain string and with a raw string; the SQL regions found must be exactly the string text. Runtime calls query, query_as and query_scalar are injected too, also scoped and with a turbofish, but the unchecked runtime functions are not, because only the macros have them. A nested Rust layer over the SQL string was removed (it painted @string on top of the SQL highlights, a field finding).'),
    ...code('lua', r'tests/snippets-completion-injections_spec.lua · lines 426-437', r'''
  it("injects SQL into the string of the sqlx macros (identifier or scoped, plain or raw string)", function()
    local macros = { "query", "query_as", "query_scalar", "query_unchecked", "query_as_unchecked", "query_scalar_unchecked" }
    for _, m in ipairs(macros) do
      for _, prefix in ipairs({ "", "sqlx::" }) do
        local first = m == "query" and "" or "Row, "
        local call = prefix .. m .. "!(" .. first
        H.eq({ "select 1" }, sql_regions(body(call .. '"select 1");')), call .. '"..."')
        H.eq({ "select 2" }, sql_regions(body(call .. 'r#"select 2"#);')), call .. 'r#"..."#')
      end
    end
  end)
'''),
    ...sec(r'only real SQL'),
    ...para('--', r'The keyword test is the clever one. It takes a list of 30 SQL keywords, makes calls whose first string starts with the keyword in three different cases (lower, upper, capitalised) and requires that the injected regions are exactly those strings. Then it lists what must not be injected: not sql here, selection, settings and set_x (a keyword that is only the prefix of a word), the empty string and blanks. The bind argument next to a statement stays alone, a multi-line statement with a leading newline is kept whole, and leading spaces and tabs are allowed.'),
    ...code('lua', r'tests/snippets-completion-injections_spec.lua · lines 499-530', r'''
  it("injects only strings starting with a SQL keyword as a whole word (any case, leading whitespace/newlines)", function()
    local kws = vim.split(
      "select insert update delete with create alter drop replace values pragma begin commit rollback truncate explain vacuum analyze attach detach reindex savepoint release set show grant revoke call merge lock",
      " "
    )
    H.eq(30, #kws)
    local calls, want = {}, {}
    for i, kw in ipairs(kws) do
      local text = (i % 3 == 0 and kw:upper()) or (i % 3 == 1 and kw) or (kw:sub(1, 1):upper() .. kw:sub(2))
      calls[#calls + 1] = 'query("' .. text .. ' x");'
      want[#want + 1] = text .. " x"
    end
    table.sort(want)
    H.eq(want, sql_regions(body(table.concat(calls, "\n    "))))

    -- not SQL: bind arguments, prose, a keyword that is only a prefix of a word
    H.eq({}, sql_regions(body('query("not sql here");')))
    H.eq({}, sql_regions(body('query("selection");')))
    H.eq({}, sql_regions(body('query("settings");')))
    H.eq({}, sql_regions(body('query("set_x");')))
    H.eq({}, sql_regions(body('query("");')))
    H.eq({}, sql_regions(body('query("   ");')))
    -- the bind argument "alice" next to the statement is left alone
    H.eq({ "select 1" }, sql_regions(body('query!("select 1", "alice");')))
    H.eq({ "select $1" }, sql_regions(body('query_as!(User, "select $1", "alice");')))

    -- leading newline/indent, multi-line statement
    local multi = "\n        UPDATE users\n        SET name = $1\n        WHERE id = $2"
    local got = sql_regions(body('query("' .. multi .. '");'))
    H.eq({ multi }, got)
    H.eq({ "  \tselect 1" }, sql_regions(body('query("  \tselect 1");')))
  end)'''),
    ...sec(r'a documented imprecision'),
    ...para('--', r'The last injection test is named known imprecision. The query is by name, not by crate, so other::query!("select 2") and my::inner::query("select 2") are injected too. The test asserts the behaviour that exists, so the limit is recorded and a change to it would be noticed. The fixture sql_and_routes.rs also serves routes_spec.lua and rust-routes_spec.lua; here it gives SQL children for the query! string and for a multi-line query string.'),
    ...code('lua', r'tests/snippets-completion-injections_spec.lua · lines 543-547', r'''
  it("known imprecision: any macro or function named query is injected (other::query!(\"select 2\"))", function()
    H.eq({ "select 2" }, sql_regions(body('other::query!("select 2");')))
    H.eq({ "select 2" }, sql_regions(body('other::query("select 2");')))
    H.eq({ "select 2" }, sql_regions(body('my::inner::query!("select 2");')))
  end)'''),
    ...sec(r'parsers and extras'),
    ...para('--', r'rust, sql, wgsl, toml, yaml, markdown, json and http parsers are installed and ensure_installed includes sql and wgsl; the lang.sql extra (dadbod) is not enabled; and treesitter-context with three lines and the navic breadcrumb configuration load without errors.'),
    ...sec(r'history'),
    blank,
    ...pt('--', r'b2fee5c (2026-10-13)', r'created.'),
    ...pt('--', r'a3d33c8 (2026-10-13)', r'"sqlx SQL highlight" from the second field test round.'),
    ...pt('--', r'f31e013 (2026-10-14)', r'"no snippets in expressions", "http conceal" and other leftovers.'),
  ],
);
