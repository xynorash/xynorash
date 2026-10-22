import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/after/queries/rust/injections.scm',
  lines: [
    cm(';', '──────────────────────────────────────────'),
    cm(';', r'after/queries/rust/injections.scm — SQL inside Rust strings'),
    cm(';', r'a tree-sitter query that tells Neovim which strings are really SQL'),
    cm(';', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'inject the SQL language into sqlx query strings'),
    kv(r'language', r'tree-sitter query (S-expressions), extends the runtime query'),
    kv(r'size', r'50 lines, 2 commits (2026-10-09, 2026-10-13)'),
    kv(r'partner', r'queries/rust/injections.scm (the base this extends)'),
    kv(r'tested by', r'tests/snippets-completion-injections_spec.lua, injections.scm'),
    ...sec(r'why this file exists'),
    ...para(';', r'Rust code that talks to a database through sqlx contains SQL as plain string literals: sqlx::query!("SELECT id FROM users WHERE id = $1", id). To the Rust grammar that is just a string, so it is painted in the string colour, one colour for the whole statement. Tree-sitter has a feature for exactly this, called language injection. A query file named injections.scm tells the parser: this node contains text in another language, parse it with that language’s grammar. Once the SQL is injected, keywords, identifiers, parameters and strings inside the statement get their own SQL highlights, with no change to the Rust source.'),
    ...para(';', r'The file sits in after/queries/rust/, which Neovim searches after the runtime’s own queries. Its first line is what makes it an addition and not a replacement.'),
    ...code('scheme', r'after/queries/rust/injections.scm · lines 1-8', r'''
;; extends

; SQL inside sqlx: the macros (query!, query_as!, query_scalar!, query_unchecked!,
; ...) and the runtime functions (query, query_as, query_scalar, with or
; without a turbofish). Only string literals that start like a statement are
; injected, so bind arguments such as "alice" are left alone (the keyword must be
; a whole word, so "selection" is not SQL). The leading whitespace is
; [[:space:]]: \s does not match the newline of a multi-line string.
'''),
    ...para(';', r'The ";; extends" modeline tells Neovim to append these patterns to the existing rust injections instead of overriding them. The header comment states the three rules of the design: which macros and functions, a keyword test to decide which strings count as SQL, and a note about whitespace that is a lesson learned the hard way. The next two sections walk through the two patterns.'),
    ...sec(r'pattern 1: the macros'),
    ...code('scheme', r'after/queries/rust/injections.scm · lines 10-26', r'''
; sqlx::query!("...") / query_as!(Row, "...")
((macro_invocation
  macro: [
    (identifier) @_name
    (scoped_identifier
      name: (identifier) @_name)
  ]
  (token_tree
    [
      (string_literal
        (string_content) @injection.content)
      (raw_string_literal
        (string_content) @injection.content)
    ]))
  (#any-of? @_name "query" "query_as" "query_scalar" "query_unchecked" "query_as_unchecked" "query_scalar_unchecked")
  (#match? @injection.content "\\c^[[:space:]]*(select|insert|update|delete|with|create|alter|drop|replace|values|pragma|begin|commit|rollback|truncate|explain|vacuum|analyze|attach|detach|reindex|savepoint|release|set|show|grant|revoke|call|merge|lock)>")
  (#set! injection.language "sql"))'''),
    ...para(';', r'Reading it from the outside in. The pattern matches a macro_invocation, a node of Rust’s grammar for name!(...). The macro name can be a bare identifier (query!) or a scoped one (sqlx::query!), and in either case the last segment is captured as @_name. The leading underscore is tree-sitter’s convention for a capture used only in predicates: it will not be treated as a highlight.'),
    ...para(';', r'Inside the macro’s token_tree, the arguments, the pattern accepts a string_literal or a raw_string_literal and captures the string_content, the text between the quotes, as @injection.content. Capturing the content and not the whole literal keeps the quotes out of the SQL, so the SQL parser never sees them. The square brackets are an alternation: either of the two literal kinds. Because the literal is a direct child of the token tree, it matches the first string in any position, which covers query_as!(Row, "SELECT ..."), where the first argument is a type and the SQL comes second.'),
    blank,
    ...pt(';', r'#any-of? @_name ...', r'a whitelist of six names: query, query_as, query_scalar and the three _unchecked variants. All are sqlx’s macros. Other macros like println! or format! are never injected, which is the point.'),
    ...pt(';', r'#match? @injection.content ...', r'a regular expression test on the text. "\\c" at the start means ignore case (it is the Vim regex flag, the predicate uses Vim regular expressions), "^" anchors at the start of the string, [[:space:]]* allows leading whitespace and newlines, then one of thirty statement keywords, and finally ">" which in Vim regex is end of word. The end-of-word anchor is the 2026-10-13 fix mentioned in the header: "selection" no longer counts as SQL, because after "select" the word does not end.'),
    ...pt(';', r'#set! injection.language "sql"', r'the action. Once all predicates pass, the captured content is parsed as SQL.'),
    blank,
    ...sec(r'why a keyword test'),
    ...para(';', r'Without the #match? test, every string in every query! call would be treated as SQL, including bind arguments: query!("SELECT ... WHERE name = $1", "alice") would try to parse "alice" as a SQL statement and produce garbage highlights. The test is a cheap, local heuristic: a string that starts with a statement keyword is almost certainly a statement. The list started with 14 keywords (select, insert, update, delete, with, create, alter, drop, replace, values, pragma, begin, commit, truncate) in the first version. The commit of 2026-10-13 grew it to the 30 listed, adding rollback, explain, vacuum, analyze, attach, detach, reindex, savepoint, release, set, show, grant, revoke, call, merge and lock. A spec builds a call for each of the thirty, in three different letter cases, and requires every one to be injected.'),
    ...pt(';', r'case', r'\\c makes the match case-insensitive: select, SELECT and Select all inject. SQL is written in either case in the wild.'),
    ...pt(';', r'whitespace', r'the comment says that \s does not match the newline of a multi-line string in this regex flavour, so the class [[:space:]] is used. Multi-line strings that begin with a line break after the opening quote are common in sqlx code, and the spec covers the case of leading newlines.'),
    blank,
    ...sec(r'pattern 2: the runtime functions'),
    ...code('scheme', r'after/queries/rust/injections.scm · lines 28-50', r'''
; sqlx::query("...") / query_as::<_, Row>("...")
((call_expression
  function: [
    (identifier) @_name
    (scoped_identifier
      name: (identifier) @_name)
    (generic_function
      function: [
        (identifier) @_name
        (scoped_identifier
          name: (identifier) @_name)
      ])
  ]
  arguments: (arguments
    [
      (string_literal
        (string_content) @injection.content)
      (raw_string_literal
        (string_content) @injection.content)
    ]))
  (#any-of? @_name "query" "query_as" "query_scalar")
  (#match? @injection.content "\\c^[[:space:]]*(select|insert|update|delete|with|create|alter|drop|replace|values|pragma|begin|commit|rollback|truncate|explain|vacuum|analyze|attach|detach|reindex|savepoint|release|set|show|grant|revoke|call|merge|lock)>")
  (#set! injection.language "sql"))'''),
    ...para(';', r'sqlx also has plain functions: sqlx::query("SELECT ...") and sqlx::query_as::<_, Row>("SELECT ..."). The grammar sees those as call_expression nodes, not macro invocations, so a second pattern is needed with the same body. The function position takes three shapes: a bare name, a scoped name, or either of those wrapped in a generic_function when there is a turbofish (::<_, Row>). The name list is shorter than for macros, three names, because the functions have no _unchecked variants. The spec states this: "does not inject into the *_unchecked runtime functions (only the macros have them)". The keyword test and the injection action are identical.'),
    ...para(';', r'The duplication of the long keyword alternation in both patterns is the price of tree-sitter queries having no way to share a regular expression between patterns. If the list changes it has to change in both places; the spec checks both through the same helper, which would catch drift.'),
    ...sec(r'a known imprecision, recorded in a test'),
    ...para(';', r'The patterns match on the last path segment, so any macro or function named query is injected, whatever crate it belongs to. The spec says so openly, with a test named "known imprecision": other::query!("select 2") and my::inner::query!("select 2") are injected. The author chose this over resolving the crate, because a query file cannot know what a name resolves to, and a false positive here only means a string that really starts with a SQL keyword is highlighted as SQL.'),
    ...sec(r'what the second file is for'),
    ...para(';', r'There is a sibling, queries/rust/injections.scm, that replaces the base query. It exists because of what happened when this file first worked. On 2026-10-13 a field test with :Inspect showed that a SELECT inside query!("...") listed @string.rust twice. The reason: nvim-treesitter’s own rust injections parse the token_tree of every macro as Rust, so each sqlx macro got a Rust layer drawn over the SQL layer, and the Rust layer painted the string. The fix is in the base file, which skips the sqlx macros. The page for that file explains it. Together the two files are the whole feature: this one adds SQL, that one stops Rust from painting over it.'),
    ...sec(r'edge cases'),
    ...pt(';', r'format strings and concatenation', r'only direct string-literal arguments are matched. A statement built with concat! or stored in a constant is not injected.'),
    ...pt(';', r'query_file! and query_file_as!', r'not in the whitelist. Their argument is a path to a file, not SQL.'),
    ...pt(';', r'escapes', r'string_content is the raw text between the quotes. A SQL string with Rust escape sequences (\n inside a normal literal) is passed to the SQL parser with the backslash sequences in place; the SQL grammar will see them as odd tokens. How the SQL parser degrades on those sequences is not tested here.'),
    ...pt(';', r'the sql parser must be installed', r'the spec asserts that ensure_installed includes sql, and that the dadbod extra, lang.sql, is not enabled. Injection needs only the parser, not an LSP.'),
    ...sec(r'tests'),
    ...para(';', r'Eight tests in tests/snippets-completion-injections_spec.lua, in the block "injections.scm", walk through this file: that it extends the runtime query and parses without error; macros as bare or scoped identifiers with plain or raw strings; no nested Rust layer over the SQL; the runtime functions, also scoped and with a turbofish; no injection into _unchecked functions; the thirty keywords as whole words in any case; the fixture tests/fixtures/sql_and_routes.rs, including a multi-line query where the route strings and "ok" are not SQL; and the known imprecision.'),
    ...sec(r'history'),
    ...pt(';', r'527f350 (2026-10-09)', r'"Roadmap step 10 wip: rest extra, domain plugin, routes, sql injection, unsafe hl". The file is created at 48 lines with 14 keywords and a \\s prefix.'),
    ...pt(';', r'99acd7e (2026-10-13)', r'"Batch 4: editing and UI (... sqlx multi-line ...)". Swaps \\s for [[:space:]], adds the whole-word anchor, and grows the keyword list to 30. Two lines of comment explain the change.'),
  ],
);
