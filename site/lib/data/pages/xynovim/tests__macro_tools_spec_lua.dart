import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/tests/macro-tools_spec.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'macro-tools_spec.lua — reading macro_rules, format strings and proc-macro status without a compiler'),
    cm('--', r'a lexer, a placeholder counter and a matcher that decides which macro arm your arguments fit'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'spec for lua/config/macro_tools.lua: macro call help, format and sqlx hints, the macro lens (:MacroExpand) and :ProcMacroStatus'),
    kv(r'language', r'Lua spec, 1035 lines, 53 it() blocks, 12 describe() blocks'),
    kv(r'structure', r'the first half is pure and table driven; the live half runs a real rust-analyzer on a copy of deps-lab and skips without it'),
    kv(r'history', r'5 commits, 2026-10-14 to 2026-10-21'),
    ...sec(r'why this file exists'),
    ...para('--', r'Macros are where Rust is hardest to read. When you type vec![ you want to see which of its arms applies. When you write println! with two placeholders and one argument, you want a hint before rustc speaks. When you want to know what a derive generated, you want the expansion. macro_tools does these jobs in Lua: it lexes Rust token trees, parses macro_rules! matchers, matches typed arguments against arms, counts format placeholders, and talks to rust-analyzer for expansions. The header splits the spec in two halves and says why: the parts that need no server are pure and tested by tables; the live half tests the integration.'),
    ...code('lua', r'tests/macro-tools_spec.lua · lines 1-6', r'''
-- config.macro_tools: macro call help (signature popup from macro_rules!
-- matcher arms, format-string / sqlx hints, snippets), the macro lens
-- (:MacroExpand) and :ProcMacroStatus.
-- The first half is pure and table-driven (lexer, placeholder counting,
-- matcher parsing and matching, report text). The "live" half runs a real
-- rust-analyzer on a copy of the deps-lab fixture and skips without it.'''),
    ...sec(r'a lexer for token trees'),
    ...para('--', r'The first block checks tokens of a set of snippets, marks a group that is not closed yet and keeps its tokens (the user is mid-typing), reports 0-based positions and shifts them with row0 and col0, and string_content drops the quotes and the braces of \u escapes. An unfinished macro call is the normal state of the input, so the lexer is written to survive it.'),
    ...sec(r'format placeholders and hints'),
    ...para('--', r'Counting placeholders in a format string is a table: each case gives a string and the expected count, and malformed strings are refused because rustc reports those. The hints then compare placeholders with arguments for println!, format! and sqlx query macros. The position test fixes what is highlighted: a missing argument covers the format string, an unused argument covers the argument.'),
    ...code('lua', r'tests/macro-tools_spec.lua · lines 179-183', r'''
  it("positions: the missing hint covers the format string, the unused one the argument", function()
    local h = mt.hints('fn f() {\n    println!("{} {}", a);\n    println!("{}", a, b);\n}')
    H.eq({ 1, 13, 1, 20 }, { h[1].sr, h[1].sc, h[1].er, h[1].ec })
    H.eq({ 2, 22, 2, 23 }, { h[2].sr, h[2].sc, h[2].er, h[2].ec })
  end)'''),
    ...sec(r'hints that can fix themselves'),
    ...para('--', r':MacroFormatFix adds the missing arguments as todo!(), with and without a trailing comma, and fixes a call that spans lines. The test puts a call with three placeholders and one argument on one line and a call with two placeholders and an argument followed by a comma on another. The first fix gives a, todo!(), todo!() and the second gives a, todo!(), keeping the trailing comma. The hint diagnostics of the namespace are empty afterwards. Away from a problem the command does nothing.'),
    ...code('lua', r'tests/macro-tools_spec.lua · lines 202-211', r'''
  it("adds the missing arguments, with and without a trailing comma", function()
    local buf = scratch({ "fn f() {", '    println!("{} {} {}", a);', '    println!("{} {}", a,);', "}" })
    vim.api.nvim_win_set_cursor(0, { 2, 6 })
    H.eq(2, mt.format_fix(buf))
    H.eq('    println!("{} {} {}", a, todo!(), todo!());', vim.api.nvim_buf_get_lines(buf, 1, 2, false)[1])
    vim.api.nvim_win_set_cursor(0, { 3, 6 })
    H.eq(1, mt.format_fix(buf))
    H.eq('    println!("{} {}", a, todo!(),);', vim.api.nvim_buf_get_lines(buf, 2, 3, false)[1])
    H.eq(0, #vim.diagnostic.get(buf, { namespace = mt.ns }))
  end)'''),
    ...sec(r'matching arms'),
    ...para('--', r'The matcher gets a macro_rules definition of vec and of a synthetic mix macro with five arms: an at-rule, a pattern with a fat arrow, a braced key-value form, an item form and a form with types and lifetimes. The cases give the typed text and the arm that must be best, with a result per arm: 2 is a full match, 1 a prefix that could still become one, 0 impossible. For example vec given 0; 10 selects arm 2, vec given 1; 2; 3 selects nothing, and mix given pub struct Foo; and struct Foo; both select arm 4. That is the logic of the popup that highlights the arm that fits while you type.'),
    ...code('lua', r'tests/macro-tools_spec.lua · lines 278-312', r'''
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
  end'''),
    ...sec(r'bounded on hostile input'),
    ...para('--', r'Matching with repetitions can be exponential. The test defines a macro with three consecutive repetitions of expression fragments and feeds 78 tokens, requiring that matching takes under two seconds. An editor feature that can hang the editor is worse than no feature, so the test is a performance contract.'),
    ...code('lua', r'tests/macro-tools_spec.lua · lines 314-320', r'''
  it("stays bounded on a pathological matcher", function()
    local def = mt.parse_macro_def("macro_rules! p { ($($a:expr)* $($b:expr)* $($c:expr)*) => {}; }", nil, nil, "p")
    local toks = mt.lex(("a b c d e f g h i j k l m n o p q r s t u v w x y z "):rep(3))
    local t0 = vim.uv.hrtime()
    mt.match_arms(def, toks)
    H.ok((vim.uv.hrtime() - t0) / 1e9 < 2, "matching took too long")
  end)'''),
    ...sec(r'popup, blink source and snippets'),
    ...para('--', r'The popup text marks the matching arm and explains its fragments with a legend, says when no arm fits, and has an explanation for every fragment kind. The blink source registers the provider and offers select!, matches! and vec![x; n]; it never offers anything after a dot; and every snippet body parses as a snippet.'),
    ...sec(r'expansion and proc-macro status'),
    ...para('--', r'Pure helpers cover the generated items with labels and rows, finding the generated item of a symbol, finding the call under a position and the same call in the source, and building the cargo expand command for the file target. ProcMacroStatus reads the crates and the settings of analyzerStatus, tells which diagnostics are about macros that were not expanded, names the proc macros a crate exports, renders the report with action targets, and writes procMacro.ignored into the project rust-analyzer.toml (or .rust-analyzer.toml when that is the file the project has); odd crate names and unreadable forms are refused, leaving the file alone.'),
    ...sec(r'the live half'),
    ...para('--', r'With a real rust-analyzer, :MacroExpand expands println!, a derive and #[tokio::main] and opens a read-only rust split with the line count; it steps into a nested call and back with a breadcrumb; for a derive it lists the generated items and jumps to the symbol under the cursor; the popup for a user macro_rules! highlights the arm that fits; vec! is found in the standard library with its arms; the popup follows the typed arguments and closes again; hints follow real edits. Where rust-analyzer expands nothing it falls back to cargo expand, labelled, and does not run it for a cursor that is not on a macro. A literal inside the arguments expands that call, not the crate. Keys are buffer-local on a rust-analyzer buffer and avoid the taken ones.'),
    ...sec(r'history'),
    blank,
    ...pt('--', r'b9363cd (2026-10-14)', r'created. 19f974c (2026-10-15) :: review fixes.'),
    ...pt('--', r'9641d08 (2026-10-16), d3e1442, 35a9ad7 (2026-10-21)', r'Windows and macOS; the last one names run 39668277143 and the live part of this spec on macOS.'),
  ],
);
