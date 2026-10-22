import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-rust.nvim/tests/rust-routes_spec.lua',
  lines: [
    cm('--', r'──────────────────────────────────────────'),
    cm('--', r'tests/rust-routes_spec.lua — every way a route can be written, and a few that cannot'),
    cm('--', r'the scanner, the directory walk and the picker of :RustRoutes, tested without LSP or cargo'),
    cm('--', r'──────────────────────────────────────────'),
    blank,
    kv(r'role', r'main spec for lua/xyno_rust/rust_routes.lua (150 lines)'),
    kv(r'language', r'Lua, run by tests/run.lua'),
    kv(r'size', r'455 lines, 26 tests in 5 describe blocks'),
    kv(r'needs', r'the tree-sitter rust parser (tests skip with a message without it); no cargo, no rust-analyzer'),
    kv(r'stands in for', r'snacks.nvim, replaced by a table with a picker function'),
    kv(r'origin', r'xynovim tests/rust-routes_spec.lua, first written 2026-10-13 (b2fee5c)'),
    ...sec(r'why this file exists'),
    ...para('--', r':RustRoutes is a small feature with a lot of surface. It has to read three different '
        r'dialects of route registration (axum and actix method calls, actix, rocket and poem '
        r'attributes), skip the directories that hold generated or foreign code, parse many files '
        r'quickly, and show a picker whose rows have a precise format. All of that is done by one '
        r'tree-sitter query plus a loop, and the failure mode of such code is not a crash but a '
        r'wrong list. A route missing from the picker looks exactly like a route that does not '
        r'exist.'),
    ...para('--', r'So this spec does two jobs. It pins what the scanner recognises, with one test per shape '
        r'and per boundary. And it pins what the scanner refuses to recognise: nest, web::resource '
        r'and macro-built routes are written down as known non-features, so that a future change '
        r'which starts handling them has to change a test on purpose.'),
    ...para('--', r'The smaller tests/routes_spec.lua checks the same scanner on one fixture file. This one '
        r'works from strings written inside the tests, because every case is clearer when the input '
        r'and the expected rows sit next to each other.'),
    ...sec(r'the module in one screen'),
    ...code('lua', r'lua/xyno_rust/rust_routes.lua · lines 8-21', r'''
local METHODS = { "get", "post", "put", "delete", "patch", "head", "options", "trace", "connect", "route" }

local QUERY = [[
((call_expression
   function: (field_expression field: (field_identifier) @_f)
   arguments: (arguments . (string_literal (string_content) @path) . (_) @handler))
 (#eq? @_f "route"))

(attribute_item
  (attribute
    [(identifier) @verb
     (scoped_identifier name: (identifier) @verb)]
    arguments: (token_tree . (string_literal (string_content) @path))))
]]
'''),
    ...para('--', r'The query has two alternatives. The first matches a call whose method name is route and '
        r'whose first argument is a string literal followed by anything: that covers .route("/p", '
        r'get(h)) of axum and cfg.route("/p", web::get().to(h)) of actix. The second matches an '
        r'attribute item whose name is a plain identifier or the last part of a scoped path, with a '
        r'token tree that starts with a string. Everything else in this spec follows from those two '
        r'patterns and from the filtering in scan_source and collect.'),
    ...sec(r'the preamble of the spec'),
    ...para('--', r'Three choices stand out.'),
    ...pt('--', r'require("xyno_rust").setup()', r'the spec runs the real public setup once so that :RustRoutes exists with its real '
        r'definition. The command test at the top reads it back from nvim_get_commands, so it is '
        r'the plugin that is under test, not a command the spec defined.'),
    ...pt('--', r'ts_describe', r'a describe that adds a before_each calling H.need_parser("rust"). The command test does '
        r'not need a parser, the scanner tests do. The wrapper keeps the guard in one place instead '
        r'of repeating it in every test. It was introduced in this repository; the xynovim original '
        r'ran in a configuration where the bootstrap script installed the parsers first (the commit '
        r'fc2062a there, 2026-10-14, made the suite pass on a clean machine by provisioning them).'),
    ...pt('--', r'summary', r'maps an item to the string "KIND /path detail". Most assertions compare a list of such '
        r'strings, so a failure prints a readable diff instead of a table of tables.'),
    ...sec(r'the command'),
    ...para('--', r'The only test that does not need a parser. nargs is the string "0": the command takes no '
        r'arguments. The description is compared word for word, since it is what :command and a '
        r'command palette show.'),
    ...sec(r'scan_source: the result shape'),
    ...code('lua', r'tests/rust-routes_spec.lua · lines 59-78', r'''
  it("returns {path, kind, detail, row, col} sorted by row, 0-based position of the string content", function()
    local src = table.concat({
      'fn app() -> Router {', -- row 0
      '    Router::new().route("/b", get(b))', -- row 1
      '}',
      '#[get("/a")]', -- row 3
      'async fn a() {}',
    }, "\n")
    local items = scan(src)
    H.eq(2, #items)
    H.eq({ path = "/b", kind = "ROUTE", detail = "get(b)", row = 1, col = 25 }, items[1])
    H.eq({ path = "/a", kind = "GET", detail = "a", row = 3, col = 7 }, items[2])
    -- the position points at the first char of the content, after the quote
    local line = vim.split(src, "\n")[items[1].row + 1]
    H.eq("/b", line:sub(items[1].col + 1, items[1].col + 2))
    local line2 = vim.split(src, "\n")[items[2].row + 1]
    H.eq("/a", line2:sub(items[2].col + 1, items[2].col + 2))
    H.eq(true, items[1].row <= items[2].row)
  end)

'''),
    ...para('--', r'This test fixes the exact table that every consumer builds on: path, kind, detail, row, '
        r'col. A ROUTE has the handler expression as its detail, an attribute route has the '
        r'upper-cased verb as its kind and the name of the next function as its detail.'),
    ...para('--', r'The position is the interesting part. row is 0-based and col is the 0-based column of the '
        r'first character inside the quotes, not of the quote itself. For the line '
        r'Router::new().route("/b", get(b)) with four spaces of indent, the quote is at column 24 '
        r'and col is 25. The test reads the source line back and takes two characters at col, '
        r'expecting exactly the path, so a future off-by-one is caught by content and not by a '
        r'magic number. The same check is done for the attribute route.'),
    ...para('--', r'Later, collect turns this into the picker position as { row + 1, col }: a 1-based line '
        r'and the same column.'),
    ...para('--', r'The next test, sorting, mixes both forms in one source (an attribute route, a .route '
        r'call, another attribute route) and expects them back in source order. The title admits '
        r'that a truly out-of-order input is impossible to write, so it mixes the forms instead.'),
    ...sec(r'scan_source: the method-call dialects'),
    ...pt('--', r'chained methods', r'.route("/p", get(h).delete(g)) is one ROUTE and the handler expression is the whole of '
        r'get(h).delete(g). The picker therefore shows every method registered on the path in one '
        r'row; it does not split them.'),
    ...pt('--', r'multi-line handlers', r'a handler spread over lines is squeezed: gsub("%s+", " ") in the module. The expected '
        r'text is "get(h) .delete(g) .post( k)", which is ugly and honest: whitespace becomes one '
        r'space, nothing else is cleaned. Two negative matches check that no newline or tab and no '
        r'double space remain.'),
    ...pt('--', r'actix', r'web::get().to(h) and any(h2) are accepted because the query only requires a string as the '
        r'first argument and anything after it.'),
    ...sec(r'scan_source: attribute dialects'),
    ...para('--', r'Two tests. The first walks the ten words the module accepts (get, post, put, delete, '
        r'patch, head, options, trace, connect and route) and checks that each yields the '
        r'upper-cased word as kind and the function name as detail. The word route is in the list, '
        r'so #[route("/d", method = "GET")] of actix is a generic attribute and is reported as '
        r'ROUTE. (The module has METHODS = the ten words; the comment above the query lists the '
        r'supported shapes.)'),
    ...para('--', r'The second is a field sample of four ecosystems in one source: actix-web with a scoped '
        r'attribute, rocket with a path parameter in angle brackets, poem where an unrelated '
        r'#[handler] attribute appears first, and the generic route attribute. The expected rows '
        r'are listed in source order, and #[handler] and its function are not in them: its argument '
        r'list has no string, so the query never matches it.'),
    ...code('lua', r'tests/rust-routes_spec.lua · lines 151-170', r'''
  it("gives detail '?' when the attribute is not followed by a function", function()
    local src = '#[get("/s")]\nstruct S;\n#[post("/e")]\n'
    H.eq({ "GET /s ?", "POST /e ?" }, summary(scan(src)))
  end)

  it("resolves the fn name through several stacked attributes", function()
    local src = table.concat({
      '#[get("/x")]',
      "#[allow(clippy::unused_async)]",
      '#[tracing::instrument]',
      "async fn h() {}",
    }, "\n")
    H.eq({ "GET /x h" }, summary(scan(src)))
  end)

  it("takes the last identifier of a scoped attribute as the verb", function()
    H.eq({ "GET /p h" }, summary(scan('#[actix_web::get("/p")]\nfn h() {}')))
    H.eq({ "DELETE /p h" }, summary(scan('#[a::b::delete("/p")]\nfn h() {}')))
  end)

'''),
    ...pt('--', r'not an HTTP verb', r'derive, cfg, tokio::main, test, allow and, the sneaky one, #[cfg(feature = "get")] '
        r'produce nothing. The last case has a string in its token tree and the word get in it, and '
        r'it still must not match, because the attribute name is cfg.'),
    ...pt('--', r'no function after the attribute', r'#[get("/s")] on a struct, and #[post("/e")] at the end of the file, give the detail "?". '
        r'The route is still listed: finding the path is more valuable than naming a handler.'),
    ...pt('--', r'stacked attributes', r'#[get("/x")] followed by two more attributes still resolves the function h. The module '
        r'walks over next sibling attribute items until it hits a function_item.'),
    ...pt('--', r'scoped names', r'the last identifier is the verb, so actix_web::get and a::b::delete both work.'),
    ...sec(r'scan_source: robustness'),
    ...code('lua', r'tests/rust-routes_spec.lua · lines 171-181', r'''
  it("returns {} for an empty string and never raises on junk", function()
    H.eq({}, scan(""))
    local ok, res = pcall(scan, "}}} ((( .route( #[get( \"")
    H.ok(ok, "scan_source raised on garbage")
    H.eq("table", type(res))
    -- junk is not turned into a route
    for _, r in ipairs(res) do
      H.eq("string", type(r.path))
    end
  end)

'''),
    ...para('--', r'Two robustness guarantees.'),
    ...para('--', r'An empty string gives an empty list, and a pile of unbalanced punctuation does not raise. '
        r'Tree-sitter always produces some tree, so garbage gives a tree with error nodes. The test '
        r'does not require an empty result for the junk, only that the call returns and that every '
        r'returned path is a string.'),
    ...para('--', r'The second test replaces vim.treesitter.get_string_parser with a function that raises, '
        r'restores it, and expects the result to be {} without an error escaping. This covers a '
        r'machine where the parser is missing at the moment of the call. The first lines of '
        r'scan_source wrap the parser creation in pcall for exactly this.'),
    ...para('--', r'Note the order in the test: the original function is restored before the assertions run. '
        r'If the assertions fail, the global is already clean.'),
    ...sec(r'scan_source: what it does not do'),
    ...para('--', r'The test title is blunt: it does not recognise nest, web::resource or macro-built routes. '
        r'The comments inside the test give the reasons. web::resource("/res") has the path as an '
        r'argument of resource, not route; its inner .route has a non-string first argument. '
        r'routes![index, about] and my_route!("/m", h) are macros whose token trees are not parsed '
        r'as calls.'),
    ...para('--', r'The module has no code that combines path prefixes, so a route mounted with .nest("/api", '
        r'api_router()) is not reported with its prefix, and the sub-router is not followed. '
        r'Writing this down as a test means the limit is a documented behaviour and not an accident.'),
    ...sec(r'collect: walking the workspace'),
    ...code('lua', r'tests/rust-routes_spec.lua · lines 246-256', r'''
      kind = "ROUTE",
      route = "/m",
      detail = "get(m)",
      rel = "src/main.rs",
    }, m)
    local g = by["src/api/users.rs"][1]
    H.eq("GET /g  g  src/api/users.rs", g.text)
    H.eq({ 1, 7 }, g.pos) -- row + 1 (1-based line), col as the scanner gives it
    H.eq(root .. "/src/api/users.rs", g.file)
  end)

'''),
    ...para('--', r'The first test builds a tree under a temp directory. It puts routes in src/main.rs and '
        r'src/api/users.rs, the same route in target, .git, node_modules and bacon-ls-live, the '
        r'same text in a .txt and a .md file, a lib.rs with no route, and a lookalike.rs whose only '
        r'content is a comment that mentions get("/nope") but contains neither .route( nor #[.'),
    ...para('--', r'The expected result is exactly two files. Every excluded file is excluded for a different '
        r'reason, and the test would fail with a different extra row for each one: skipped '
        r'directory, wrong extension, nothing to find, pre-filter.'),
    ...para('--', r'The full item is compared with H.eq: text is the picker line, file is the absolute path, '
        r'pos is { 1, 17 } for the main.rs route (1-based line, column of the content), and kind, '
        r'route, detail and rel are the pieces that format() uses.'),
    ...code('lua', r'tests/rust-routes_spec.lua · lines 257-270', r'''
  it("skips target/.git/node_modules/bacon-ls-live below the root too (workspace members)", function()
    local root = H.tmpdir()
    local good = '#[get("/g")]\nasync fn g() {}\n'
    write(root .. "/crates/a/src/lib.rs", good)
    for _, d in ipairs({ "target", ".git", "node_modules", "bacon-ls-live" }) do
      write(root .. "/crates/a/" .. d .. "/x.rs", good)
    end
    local rels = vim.tbl_map(function(i)
      return i.rel
    end, R.collect(root))
    table.sort(rels)
    H.eq({ "crates/a/src/lib.rs" }, rels)
  end)

'''),
    ...para('--', r'This is the regression that has the best story in the file. The module comment says dir '
        r'is the path relative to root, nested target/ too. Vim’s vim.fs.dir passes its skip '
        r'callback the path of the directory relative to the root, for example crates/a/target, and '
        r'the SKIP table is keyed by bare names. The module therefore applies vim.fs.basename '
        r'before the lookup. In xynovim this test first existed as a known-bug skip: on 2026-10-13 '
        r'it caught nested directories being scanned and called require("xynotest.harness").skip '
        r'with a message. The same day, in the round of fixes of 98c9bb4, the module was corrected '
        r'and the test became a plain H.eq.'),
    ...para('--', r'The pre-filter is a plain-text search for .route( or #[ before any parsing. The test '
        r'checks it from both sides: r.route("/a", h) is parsed, r.route ("/b", h) with a space is '
        r'not, and a #[get] file is. The consequence is documented and accepted: unusual formatting '
        r'that the formatter would not produce is not found.'),
    ...para('--', r'Depth: a file twelve path components deep is listed, a file thirteen components deep is '
        r'not. The walk passes depth = 12 to vim.fs.dir. The test builds both paths from one helper '
        r'so the difference is exactly one directory. The last test of the group checks that a '
        r'workspace with only fn main() gives {}.'),
    ...sec(r'pick: the picker without snacks.nvim'),
    ...para('--', r'The group replaces the global Snacks right before each call with a table whose picker '
        r'function records its options. The comment in the code says why it is done only right '
        r'before pick(): vim.cmd.edit lets the real Snacks load itself, and the stub must not be in '
        r'the way of that. after_each puts the original back.'),
    ...code('lua', r'tests/rust-routes_spec.lua · lines 344-358', r'''
  it("warns 'no Cargo.toml found' outside a crate and opens no picker", function()
    local dir = H.tmpdir()
    write(dir .. "/lone.rs", '#[get("/x")]\nfn h() {}\n')
    vim.cmd.edit(vim.fn.fnameescape(dir .. "/lone.rs"))
    -- a Cargo.toml in a parent of the temp dir would make this test meaningless
    if #vim.fs.find("Cargo.toml", { upward = true, path = dir }) > 0 then
      H.skip_file("a Cargo.toml exists above the temp dir")
    end
    stub_snacks()
    local cap = H.capture_notify()
    R.pick()
    cap.restore()
    H.eq({ { msg = "no Cargo.toml found", level = vim.log.levels.WARN } }, cap.list)
    H.eq(0, #picked)
  end)
'''),
    ...para('--', r'Two negative paths, both exact. Outside a crate, the command notifies no Cargo.toml found '
        r'at WARN and opens no picker, and the test skips itself if some parent of the temp '
        r'directory happens to hold a Cargo.toml, since the result would then be meaningless. In a '
        r'crate with no routes, the message is the INFO text no routes found (.route("/p", ..) or '
        r'#[get("/p")]), which doubles as a hint of what is searched.'),
    ...para('--', r'The positive path. Two files, two routes, one picker. The title is Routes, preview is '
        r'file and the items are the collected rows. The spec also asserts that the notification '
        r'list is empty, so no stray message appears, and that each item file is two directory '
        r'levels below the crate root.'),
    ...code('lua', r'tests/rust-routes_spec.lua · lines 398-415', r'''

  it("format() returns 4 chunks: kind padded to 7 (Keyword), route (String), detail (Function), rel (Comment)", function()
    local dir = crate({ ["src/main.rs"] = 'fn a(){ r.route("/m", get(m)); }\n' })
    vim.cmd.edit(vim.fn.fnameescape(dir .. "/src/main.rs"))
    stub_snacks()
    R.pick()
    local p = H.ok(picked[1], "picker was not opened")
    local chunks = p.format(p.items[1])
    H.eq({
      { "ROUTE  ", "Keyword" },
      { "/m  ", "String" },
      { "get(m)  ", "Function" },
      { "src/main.rs", "Comment" },
    }, chunks)
    H.eq(7, #chunks[1][1])
    H.eq({ "GET    ", "Keyword" }, p.format({ kind = "GET", route = "/", detail = "d", rel = "r" })[1])
  end)
end)
'''),
    ...para('--', r'format() is a function of the item and returns four chunks: the kind padded to seven '
        r'characters with the highlight group Keyword, the route plus two spaces in String, the '
        r'detail plus two spaces in Function, and the relative path in Comment. The padding is '
        r'asserted by length, 7, and again with a short kind (GET plus four spaces). This is the '
        r'visible column layout of the picker.'),
    ...sec(r'the verification crate'),
    ...para('--', r'The last group is titled “README verification” and builds a scratch '
        r'crate with an actix attribute, two axum routes (one with chained methods and a {id} '
        r'parameter in the new axum syntax), and a #[get] with an extra #[allow] below it. The '
        r'expected rows contain the 1-based line of each route: 3, 8, 9 and 12. The expected strings include the 1-based line of each route (pos[1]).'),
    ...sec(r'what was left behind in the extraction'),
    ...para('--', r'In xynovim the spec ended with a describe for the <leader>rN keymap. It started a fake '
        r'LspAttach client and checked that the key was mapped buffer-locally once rust-analyzer '
        r'attached. This plugin does not own a rust-analyzer attach handler, and its keys are '
        r'opt-in and set by FileType. That block was dropped here, and the corresponding behaviour '
        r'is covered by tests/init_spec.lua (the keymaps group). The file went from 494 lines to '
        r'455.'),
    ...para('--', r'Also new here: the explicit setup() call and the parser guard.'),
    ...sec(r'history'),
    ...pt('--', r'b2fee5c, 2026-10-13', r'xynovim: test suite of 22 feature specs; this file arrives with 494 lines.'),
    ...pt('--', r'98c9bb4, 2026-10-13', r'the known-bug skip for nested target and .git directories becomes a real assertion after the fix.'),
    ...pt('--', r'25086fd, 2026-10-14', r'the keymap block now tests that the buffer-local mapping, not the global stub, is absent '
        r'before attach and present after.'),
    ...pt('--', r'fc2062a, 2026-10-14', r'CI made to pass on a clean machine; the very-lazy helper replaces a raw doautocmd.'),
    ...pt('--', r'9641d08, 2026-10-16', r'first Windows and macOS runs: the spec helper that writes fixture files switches to '
        r'binary mode (wb), one of the Windows and macOS fixes of that commit.'),
    ...pt('--', r'7c1d2d9, 2026-10-22', r'this repository: namespace renamed, setup() called, ts_describe added, the keymap block removed.'),
  ],
);
