import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-macros.nvim/tests/tools_spec.lua',
  lines: [
    cm('--', r'──────────────────────────────────────────'),
    cm('--', r'tools_spec.lua — pure functions in tables, then a real rust-analyzer'),
    cm('--', r'58 tests; the second half skips where rust-analyzer is not available'),
    cm('--', r'──────────────────────────────────────────'),
    kv(r'role', r'the spec of the macro tools: lexer, format hints, matcher, popup, lens, report'),
    kv(r'language', r'Lua on the repo harness'),
    kv(r'size', r'1,089 lines, 58 it() blocks (some registered by loops over case tables)'),
    kv(r'needs', r'tree-sitter rust for the matcher; rust-analyzer, cargo and registry crates for the live half'),
    kv(r'history', r'added in 08b2e8f (2026-10-22); the snippet-guard group added in 9ab48fb'),
    ...sec(r'why this file exists'),
    ...para('--', r'The module under test is a stack: a lexer, then format-string and matcher logic built on '
        r'it, then a UI that calls a language server. Tests for the top of the stack need a server '
        r'and minutes; tests for the bottom need nothing. The spec splits at exactly that line and '
        r'the header says so: the first half is pure and table-driven, the second half runs a real '
        r'rust-analyzer on a copy of the deps-lab fixture and skips without it.'),
    ...code('lua', r'tests/tools_spec.lua · lines 1-6', r'''
-- xyno_macros.tools: macro call help (signature popup from macro_rules!
-- matcher arms, format-string / sqlx hints, snippets), the macro lens
-- (:MacroExpand) and :ProcMacroStatus.
-- The first half is pure and table-driven (lexer, placeholder counting,
-- matcher parsing and matching, report text). The "live" half runs a real
-- rust-analyzer on a copy of the deps-lab fixture and skips without it.
'''),
    ...sec(r'keeping the editor quiet'),
    ...code('lua', r'tests/tools_spec.lua · lines 22-41', r'''
local function quiet(fn)
  local saved = vim.o.eventignore
  vim.o.eventignore = "FileType"
  local ok, a = pcall(fn)
  vim.o.eventignore = saved
  if not ok then
    error(a, 0)
  end
  return a
end

local function scratch(lines)
  return quiet(function()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(buf)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].filetype = "rust"
    return buf
  end)
end
'''),
    ...para('--', r'Specs create many Rust buffers, and each FileType event would start hint scanning and '
        r'other autocmds. quiet runs a function with eventignore set to FileType and restores it '
        r'even on error; scratch builds a Rust buffer inside it, then sets the filetype. This is a '
        r'test-only technique; the pcall and the re-raise with level 0 keep the original message.'),
    ...sec(r'the lexer as a table'),
    ...code('lua', r'tests/tools_spec.lua · lines 52-70', r'''
describe("lexer", function()
  local cases = {
    { 'println!("a, b", x)', { "id", "p", "group" } },
    { 'r#"a "quoted" {}"# x', { "str", "id" } },
    { "b'x' 'a 'static '\\n' '\\''", { "lit", "life", "life", "lit", "lit" } },
    { "a /* c /* nested */ */ b // line\n c", { "id", "id", "id" } },
    { "1..2 1.5 x.0", { "lit", "p", "lit", "lit", "id", "p", "lit" } },
    { 'vec![1, "a]b", (2)]', { "id", "p", "group" } },
    { "r#type =>", { "id", "p" } },
  }
  for _, c in ipairs(cases) do
    it("tokens of " .. c[1]:gsub("\n", " "), function()
      local kinds = vim.tbl_map(function(t)
        return t.t
      end, mt.lex(c[1]))
      H.eq(c[2], kinds)
    end)
  end

'''),
    ...para('--', r'Each row is a source string and the sequence of token kinds it must produce. The rows are '
        r'the hard cases of Rust: a raw string with quotes inside, a character literal against a '
        r'lifetime against a static lifetime, nested block comments, a range against a float '
        r'against a tuple field, a string with a bracket inside a group, and a raw identifier. They '
        r'are the reasons the lexer exists as its own thing, and each test is named after its '
        r'source string.'),
    ...sec(r'arm matching as a table'),
    ...code('lua', r'tests/tools_spec.lua · lines 278-321', r'''
describe("arm matching", function()
  local vec = mt.parse_macro_def(VEC, nil, nil, "vec")
  local mix = mt.parse_macro_def(VEC, nil, nil, "mix")

  --- { def, typed arguments (the text after the opening delimiter), arm that must be best (index) or nil, results }
  local cases = {
    { vec, "", 1, { 2, 1, 1 } },
    { vec, "1", 3, { 0, 1, 2 } },
    { vec, "1,", 3, { 0, 0, 2 } },
    { vec, "1, 2, 3", 3, { 0, 0, 2 } },
    { vec, "1, 2, 3,", 3, { 0, 0, 2 } },
    { vec, "0; ", 2, { 0, 1, 0 } },
    { vec, "0; 10", 2, { 0, 2, 0 } },
    { vec, "foo(1, 2), bar", 3, { 0, 0, 2 } },
    { vec, "vec![1, 2]; 3", 2, { 0, 2, 0 } },
    { vec, "1; 2; 3", nil, { 0, 0, 0 } },
    { mix, "@one x", 1, { 2, 0, 0, 0, 0 } },
    { mix, "a => x y z", 2, { 0, 2, 0, 0, 0 } },
    { mix, "a =>", 2, { 0, 2, 0, 0, 0 } },
    { mix, "{ a: 1, b: 2 }", 3, { 0, 0, 2, 0, 0 } },
    { mix, "{ a: 1,", 3, { 0, 0, 1, 0, 0 } },
    { mix, "pub struct Foo;", 4, { 0, 0, 0, 2, 0 } },
    { mix, "struct Foo;", 4, { 0, 0, 0, 2, 0 } },
    { mix, "Vec<u8>, 'a, 5", 5, { 0, 0, 0, 0, 2 } },
    { mix, "HashMap<K, V>, 'a", 5, { 0, 0, 0, 0, 1 } },
    { mix, "u8, 'a, -1", 5, { 0, 0, 0, 0, 2 } },
  }
  for _, c in ipairs(cases) do
    it(("%s! given %q"):format(c[1].name, c[2]), function()
      local toks = mt.lex(c[2])
      local m = mt.match_arms(c[1], toks)
      H.eq(c[4], m.results, "per-arm result")
      H.eq(c[3], m.best, "best arm")
    end)
  end

  it("stays bounded on a pathological matcher", function()
    local def = mt.parse_macro_def("macro_rules! p { ($($a:expr)* $($b:expr)* $($c:expr)*) => {}; }", nil, nil, "p")
    local toks = mt.lex(("a b c d e f g h i j k l m n o p q r s t u v w x y z "):rep(3))
    local t0 = vim.uv.hrtime()
    mt.match_arms(def, toks)
    H.ok((vim.uv.hrtime() - t0) / 1e9 < 2, "matching took too long")
  end)
end)
'''),
    ...para('--', r'The matching table is the specification of the three-valued matcher. Each row is a macro, '
        r'the typed arguments, the arm that must be best and the result per arm. For vec!, typing '
        r'nothing makes the empty arm complete and the others viable; typing 1 makes the third arm '
        r'complete; 0; with nothing after makes the second arm viable and 0; 10 makes it complete; '
        r'the nested vec![1, 2]; 3 is complete for the repeat arm. A second macro called mix '
        r'exercises matcher features: a literal prefix, a fat arrow, a brace group, visibility that '
        r'is optional, types with generics, lifetimes and negative literals. The rows with 1 are '
        r'the incomplete calls that make a popup possible. The last test feeds a pathological '
        r'matcher, three adjacent repetitions, seventy-eight tokens, and requires it to finish '
        r'within two seconds.'),
    ...sec(r'the live half'),
    ...code('lua', r'tests/tools_spec.lua · lines 684-697', r'''
local function open_lab()
  H.need_rust()
  local dir, buf = H.open_fixture("deps-lab", "src/main.rs")
  local f = assert(io.open(dir .. "/src/main.rs", "a"))
  f:write(USER_MACROS)
  f:close()
  vim.cmd("edit!")
  buf = vim.api.nvim_get_current_buf()
  vim.bo[buf].filetype = "rust"
  mt.setup({ keymaps = true })
  H.start_ra(buf, dir)
  H.wait_lsp("rust-analyzer", buf)
  return dir, buf
end
'''),
    ...para('--', r'open_lab appends a block of user-defined macros to the fixture, opens it, starts a real '
        r'rust-analyzer for it, waits until the client is attached, and enables the keymaps. '
        r'H.need_rust skips the whole group when rust-analyzer or cargo is missing.'),
    ...code('lua', r'tests/tools_spec.lua · lines 710-745', r'''
local function expand_when_ready(buf, row, col, timeout)
  local name, text
  local ok, err = pcall(H.wait_for, function()
    local done
    name, text = nil, nil
    mt.request_expand(buf, row, col, function(n, t)
      name, text, done = n, t, true
    end)
    vim.wait(5000, function()
      return done
    end, 20)
    -- "proc-macro not yet built": rust-analyzer is still building them
    return name
  end, timeout or 120000, "rust-analyzer expandMacro")
  if not ok then
    error(err .. " (last answer: " .. tostring(text) .. ")", 0)
  end
  return name, text
end

--- find_definition until rust-analyzer resolves it (not the built-in table).
local function definition_when_ready(buf, row, col, name)
  local def, where
  H.wait_for(function()
    local done
    def, where = nil, nil
    mt.find_definition(buf, row, col, name, function(d, w)
      def, where, done = d, w, true
    end)
    vim.wait(5000, function()
      return done
    end, 20)
    return def and where ~= "built-in table"
  end, 60000, "definition of " .. name .. " (last: " .. tostring(where) .. ")")
  return def, where
end
'''),
    ...para('--', r'Two helpers solve the same problem. rust-analyzer needs time to load a workspace and to '
        r'build proc macros, so a request made too early returns nothing. expand_when_ready asks '
        r'again until it gets a name back, waiting up to two minutes, and reports the last answer '
        r'if it gives up; definition_when_ready does the same for the definition of a macro and '
        r'insists that the answer came from the server and not from the built-in table.'),
    ...code('lua', r'tests/tools_spec.lua · lines 747-760', r'''
describe("live rust-analyzer", function()
  it("expands println!, a derive and #[tokio::main]", function()
    H.known_issue({ "windows", "macos" }, "live rust-analyzer flow fails or hangs on Windows (run 39647013043) and macOS (macos-latest run 39668277143: the file timed out after 240 s in :MacroExpand)")
    local _, buf = open_lab()
    local row, col = find(buf, 'println!("{} {:?}"')
    local name, text = expand_when_ready(buf, row, col + 2)
    H.eq("println!", name)
    H.match(text, "format_args_nl!", true)

    row, col = find(buf, "Serialize, Deserialize")
    name, text = expand_when_ready(buf, row, col + 2)
    H.eq("Serialize", name)
    H.match(text, "impl _serde::Serialize for Item", true)

'''),
    ...para('--', r'The first live test expands println!, a derive and #[tokio::main] and checks the names '
        r'and fragments of the text: format_args_nl for println, impl _serde::Serialize for Item '
        r'for the derive. It begins with a line worth reading: known_issue skips the test on '
        r'Windows and macOS and the reason gives the CI run numbers where it failed or hung. The '
        r'README repeats those numbers in its Platforms section.'),
    ...code('lua', r'tests/tools_spec.lua · lines 998-1040', r'''
  it(":ProcMacroStatus lists the workspace proc-macro crates and writes the ignore setting", function()
    H.known_issue({ "windows", "macos" }, "live rust-analyzer flow fails or hangs on Windows (run 39647013043) and macOS (macos-latest run 39668277143: the file timed out after 240 s in :MacroExpand)")
    local dir, buf = open_lab()
    local cm = require("xyno_rust.crate_meta")
    local meta = cm.metadata(dir)
    if not meta then
      H.skip_file("cargo metadata failed (registry not populated?)")
    end
    local crates = mt.proc_macro_crates(meta, dir .. "/target")
    local names = vim.tbl_map(function(c)
      return c.name
    end, crates)
    H.has(names, "serde_derive")
    H.has(names, "thiserror-impl")
    H.has(names, "tokio-macros")
    local row, col = find(buf, "tokio::main")
    expand_when_ready(buf, row, col + 8)
    vim.cmd("ProcMacroStatus")
    H.wait_for(function()
      return vim.api.nvim_buf_get_name(0):find("proc%-macro%-status")
    end, 30000, "the status buffer")
    local text = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
    H.match(text, "serde_derive", true)
    H.match(text, "Macros not expanded", true)
    H.match(text, "rust-analyzer", true)
    vim.cmd("normal q")
    -- the ignore action writes the project setting
    H.ok(mt.ignore_proc_macro(dir, "tokio-macros", { "main", "test" }))
    H.eq('[procMacro.ignored]\n"tokio-macros" = ["main", "test"]\n', read(dir .. "/rust-analyzer.toml"))
    -- rust-analyzer reads that file itself: its config dump shows the setting
    local client = H.clients(buf, "rust-analyzer")[1]
    local status
    H.wait_for(function()
      local r = client:request_sync("rust-analyzer/analyzerStatus", { textDocument = vim.lsp.util.make_text_document_params(buf) }, 20000, buf)
      status = r and r.result
      return status and status:find("procMacro_ignored", 1, true)
    end, 60000, "procMacro_ignored in rust-analyzer's config (rust-analyzer.toml)")
  end)
end)

-- The default snippet guard replaces the original configuration's own
-- expression-node check: it only knows "after a dot", "in a string" and "in a
-- comment".
'''),
    ...para('--', r'The last live test ties the report to the editor. It reads the real cargo metadata, lists '
        r'the proc-macro crates and checks that serde_derive, thiserror-impl and tokio-macros are '
        r'there; expands a tokio::main to give the server something to know; runs :ProcMacroStatus '
        r'and waits for its buffer; asserts that the text names serde_derive, the heading Macros '
        r'not expanded and rust-analyzer. Then it uses the ignore action to write a '
        r'rust-analyzer.toml and asserts the exact text, and finally asks rust-analyzer’s own '
        r'configuration dump whether procMacro_ignored shows up, which proves the server read the '
        r'file the plugin wrote.'),
    ...sec(r'the snippet guard'),
    ...code('lua', r'tests/tools_spec.lua · lines 1041-1089', r'''
describe("tools.snippets_allowed (default)", function()
  local function ctx_for(line, col)
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { line })
    vim.bo[buf].filetype = "rust"
    return { line = line, cursor = { 1, col or #line }, bufnr = buf }
  end

  local function has_parser()
    return (pcall(vim.treesitter.language.add, "rust"))
  end

  after_each(function()
    mt.config.snippets_allowed = nil
  end)

  it("is allowed at the start of a statement", function()
    H.eq(true, mt.snippets_allowed(ctx_for("    ")))
    H.eq(true, mt.snippets_allowed(ctx_for("    let x = ma")))
  end)

  it("is refused after a dot", function()
    H.eq(false, mt.snippets_allowed(ctx_for("    foo.ma")))
    H.eq(false, mt.snippets_allowed(ctx_for("    foo.")))
  end)

  it("is allowed after a range operator (not a method call)", function()
    H.eq(true, mt.snippets_allowed(ctx_for("    let r = 0..ma")))
  end)

  it("is refused inside a string and a comment", function()
    if not has_parser() then
      return skip("no rust tree-sitter parser")
    end
    local c = ctx_for('let s = "ab", 9;', 11)
    vim.treesitter.get_parser(c.bufnr, "rust"):parse()
    H.eq(false, mt.snippets_allowed(c))
    local d = ctx_for("// note ma")
    vim.treesitter.get_parser(d.bufnr, "rust"):parse()
    H.eq(false, mt.snippets_allowed(d))
  end)

  it("a configured function decides instead", function()
    mt.config.snippets_allowed = function()
      return false
    end
    H.eq(false, mt.snippets_allowed(ctx_for("    ")))
  end)
end)
'''),
    ...para('--', r'These tests were added by the last commit of the repository, 9ab48fb, together with a '
        r'comment that states their purpose: the default guard replaces the original '
        r'configuration’s own expression-node check, and it only knows after a dot, in a string and '
        r'in a comment. The tests pin that: allowed at the start of a statement and after let x =, '
        r'refused after a dot, allowed after a range operator, refused inside a string and a '
        r'comment when a parser exists, and replaced entirely when the user gives a function.'),
    ...sec(r'what the suite shows, and what it admits'),
    ...para('--', r'Everything that is tested without a server is tested thoroughly; the two live groups are '
        r'conditional on the machine. The suite also states, in known_issue, that two of the three '
        r'platforms have not run the live half successfully.'),
    ...sec(r'history'),
    ...pt('--', r'08b2e8f', r'2026-10-22, Add specs, a headless runner and a lazy.nvim smoke test.'),
    ...pt('--', r'9ab48fb', r'2026-10-22, Pin blink.cmp to 1.x in the docs, spec the default snippet guard.'),
  ],
);
