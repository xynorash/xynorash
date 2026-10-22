import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/queries/rust/injections.scm',
  lines: [
    cm(';', '──────────────────────────────────────────'),
    cm(';', r'queries/rust/injections.scm — a copy with one deliberate change'),
    cm(';', r'a base query that shadows nvim-treesitter’s so sqlx SQL stays SQL'),
    cm(';', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'base Rust injections: macros as Rust, doc comments, regexes'),
    kv(r'language', r'tree-sitter query (S-expressions); no extends line'),
    kv(r'size', r'100 lines, 1 commit (a3d33c8, 2026-10-13)'),
    kv(r'copied from', r'nvim-treesitter’s queries/rust/injections.scm'),
    kv(r'extended by', r'after/queries/rust/injections.scm'),
    kv(r'tested by', r'tests/snippets-completion-injections_spec.lua'),
    ...sec(r'why this file exists'),
    ...para(';', r'Its header explains it in one paragraph, and it is worth reading closely, because this is a rare case of an intentional fork of a plugin’s data file.'),
    ...code('scheme', r'queries/rust/injections.scm · lines 1-9', r'''
; Base of the rust injections: shadows nvim-treesitter's own queries/rust/injections.scm
; (this directory comes first on the runtimepath; the first file that does not
; extend becomes the base) and is a copy of it with ONE change: the first
; pattern, which parses every macro's token_tree as Rust, skips the sqlx query
; macros. Left in, that nested Rust layer painted the SQL string as @string on
; top of the SQL layer (same priority, drawn later), so `query!` SQL showed as
; one string colour although it was injected. The price: the other arguments of
; those macros (`Row` in query_as!) get no Rust highlighting. The SQL injection
; itself is in after/queries/rust/injections.scm.'''),
    ...sec(r'how Neovim picks query files'),
    ...para(';', r'Neovim collects every queries/rust/injections.scm on the runtime path, in runtime path order. A file whose first line is ";; extends" is added to the ones before it. The first file without that line becomes the base, and files after it extend it. The config directory comes before plugin directories on the path, so this file is found before nvim-treesitter’s own, and since it does not extend, it takes its place. The after/ directory comes last and extends the result. So the effective query is: this file, then the SQL patterns of after/queries/rust/injections.scm. nvim-treesitter’s original is not used at all, as long as this file exists.'),
    ...sec(r'the one change'),
    ...code('scheme', r'queries/rust/injections.scm · lines 11-21', r'''
(macro_invocation
  macro: [
    (scoped_identifier
      name: (_) @_macro_name)
    (identifier) @_macro_name
  ]
  (token_tree) @injection.content
  (#not-any-of? @_macro_name "slint" "html" "json" "xml"
    "query" "query_as" "query_scalar" "query_unchecked" "query_as_unchecked" "query_scalar_unchecked")
  (#set! injection.language "rust")
  (#set! injection.include-children))'''),
    ...para(';', r'This is the pattern that nvim-treesitter ships for macros, and it is the reason Rust code inside macro arguments is highlighted properly. The parser treats a macro’s token_tree as an opaque tree of tokens, so for println!("{}", x) or vec![a, b] the arguments would be flat. This pattern says: for every macro except the ones listed, parse the token_tree again as Rust, and include children so nested trees are covered. The result is that expressions inside macros get full Rust highlighting.'),
    ...para(';', r'The only edit is on lines 18 and 19 of the file: the exclusion list in #not-any-of?. Upstream excludes four names, slint, html, json and xml, which have their own pattern (below). The copy adds the six sqlx names after them. For those macros there is now no Rust layer at all.'),
    ...sec(r'the bug it fixes'),
    ...para(';', r'The nested layer was drawn over the SQL. A tree-sitter highlight comes from a language layer; when two layers cover the same text with the same priority, the later one wins. The Rust layer for the token_tree of query!("SELECT ...") saw a string_literal and gave it @string. The SQL layer saw the keywords and identifiers and gave them SQL captures. Same priority, the Rust one drawn later, and the whole statement came out in one string colour although it was injected. The spec records how it was found: running :Inspect on SELECT in a query! listed @string.rust twice. A headless test that checked captures at a position had passed, because the SQL layer was there too. What caught it was looking at the screen. The spec now has a test named "no nested Rust layer over the SQL string of a sqlx macro" that counts rust layers over the SQL region.'),
    ...sec(r'the price, stated honestly'),
    ...para(';', r'Skipping the Rust layer for these macros has a cost, and the header states it: the other arguments of those macros get no Rust highlighting. In query_as!(Row, "SELECT ..."), the word Row is just a token in an opaque tree, so it loses its type colour. The author accepted that, since the SQL string is the part that matters in those calls.'),
    ...para(';', r'There is another cost that the header does not mention, a maintenance one: this is a copy. When nvim-treesitter updates its rust injections (new embedded languages, a new regex pattern), this file does not follow. It will only get the changes if somebody notices and merges them by hand. The header promises "a copy with ONE change", which makes a comparison with the upstream file easy on an update, but I found nothing in the repository that automates it.'),
    ...sec(r'the rest of the file, as copied'),
    ...code('scheme', r'queries/rust/injections.scm · lines 23-48', r'''
(macro_invocation
  macro: [
    (scoped_identifier
      name: (_) @injection.language)
    (identifier) @injection.language
  ]
  (token_tree) @injection.content
  (#any-of? @injection.language "slint" "html" "json" "xml")
  (#offset! @injection.content 0 1 0 -1)
  (#set! injection.include-children))

(macro_definition
  (macro_rule
    left: (token_tree_pattern) @injection.content
    (#set! injection.language "rust")))

(macro_definition
  (macro_rule
    right: (token_tree) @injection.content
    (#set! injection.language "rust")))

([
  (line_comment)
  (block_comment)
] @injection.content
  (#set! injection.language "comment"))'''),
    blank,
    ...pt(';', r'embedded-language macros', r'the first pattern here is the mirror of the one above. If the macro is named slint, html, json or xml, the macro’s own name is used as the injection language, and #offset! trims one character from each end of the token tree so the surrounding brackets are not part of the embedded text.'),
    ...pt(';', r'macro_rules!', r'both sides of a macro_rules arm are parsed as Rust: the matcher (token_tree_pattern) and the transcriber (token_tree). Without them, the body of a declarative macro would be flat tokens.'),
    ...pt(';', r'comments', r'every line and block comment is injected with the comment language. That is the small parser that highlights TODO, FIXME and URLs inside comments, so it works in Rust too.'),
    blank,
    ...sec(r'regexes and re2c'),
    ...code('scheme', r'queries/rust/injections.scm · lines 50-59', r'''
(call_expression
  function: (scoped_identifier
    path: (identifier) @_regex
    (#any-of? @_regex "Regex" "RegexBuilder")
    name: (identifier) @_new
    (#eq? @_new "new"))
  arguments: (arguments
    (raw_string_literal
      (string_content) @injection.content))
  (#set! injection.language "regex"))
'''),
    ...para(';', r'The rest of the file is four variants of one idea: the argument of Regex::new, RegexBuilder::new, RegexSet::new and RegexSetBuilder::new is injected with the regex language, but only when it is a raw string (r"..." or r#"..."#). Raw strings are chosen because in a normal string every backslash of the regex would be doubled, and the regex parser would see the Rust escapes. Each of the four exists once for a plain path (Regex::new) and once for a path with a module prefix (regex::Regex::new), where the outer scoped_identifier nests another. The RegexSet forms take an array of raw strings, so they use array_expression.'),
    ...code('scheme', r'queries/rust/injections.scm · lines 98-100', r'''
((block_comment) @injection.content
  (#match? @injection.content "/\\*!([a-zA-Z]+:)?re2c")
  (#set! injection.language "re2c"))'''),
    ...para(';', r'The final pattern is a curiosity of the upstream file: a block comment that begins with /*!re2c, the marker of a re2c lexer specification embedded in Rust, is injected with the re2c language. It is copied unchanged.'),
    ...sec(r'tests'),
    ...para(';', r'The block "injections.scm" in tests/snippets-completion-injections_spec.lua covers the change: it checks that the file extends the runtime query and parses without error, and it contains the layer-counting test for sqlx macros. The comment above that test is the origin story of this file, citing the :Inspect observation and naming queries/rust/injections.scm as the fix.'),
    ...sec(r'history'),
    ...para(';', r'One commit, a3d33c8 of 2026-10-13, "Final loop round 2: remaining field test bugs (... sqlx SQL highlight ...)". The subject is a long list of fixes found by using the editor, and "sqlx SQL highlight" is this one. The same commit rewrote nothing in the after/ file; the two files were designed to work together, one removing the nested layer and one adding the SQL.'),
    ...sec(r'relation to the plugin split'),
    ...para(';', r'On 2026-10-22 the Rust tooling modules moved into standalone plugins under ~/projects/xyno-plugins. Query files are not among them: this one is about nvim-treesitter, not about cargo or rust-analyzer, and it stays in the configuration.'),
  ],
);
