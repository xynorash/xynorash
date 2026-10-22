import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-rust.nvim/tests/routes_spec.lua',
  lines: [
    cm('--', r'──────────────────────────────────────────'),
    cm('--', r'tests/routes_spec.lua — one fixture, three routes, no LSP'),
    cm('--', r'the smallest spec in the repo, and the first line of defence for :RustRoutes'),
    cm('--', r'──────────────────────────────────────────'),
    blank,
    kv(r'role', r'smoke spec for the route scanner (rust_routes.scan_source)'),
    kv(r'language', r'Lua, run by the repo’s own runner (nvim -l tests/run.lua)'),
    kv(r'size', r'20 lines, 1 test, 1 commit in this repo (7c1d2d9)'),
    kv(r'needs', r'the tree-sitter rust parser; skips with a message without it'),
    kv(r'covers', r'axum .route() calls and actix style attribute routes'),
    ...sec(r'why this file exists'),
    ...para('--', r':RustRoutes lists the HTTP routes of a crate in a picker. It does that without '
        r'rust-analyzer: lua/xyno_rust/rust_routes.lua parses every .rs file with the tree-sitter '
        r'rust grammar and runs one query that matches two shapes of source, a .route("/path", '
        r'handler) method call and a #[get("/path")] style attribute. A tree-sitter query is easy '
        r'to break silently. If the grammar renames a node, or the query is edited a little too '
        r'eagerly, the picker does not crash. It just lists fewer routes, or none, and nothing '
        r'complains. This spec exists so that failure is loud.'),
    ...para('--', r'The file is deliberately tiny. It asks the one question that matters most: given a '
        r'realistic piece of Rust, does scan_source return the paths a human would read off the '
        r'page? The long, edge-case-by-edge-case coverage lives in tests/rust-routes_spec.lua (455 '
        r'lines, 26 tests). This file is the canary that stays readable at a glance.'),
    ...sec(r'the whole spec'),
    ...code('lua', r'tests/routes_spec.lua · lines 1-20', r'''
-- :RustRoutes scanner on the sql_and_routes.rs fixture (treesitter, no LSP).
local H = require("xyno_rust_test.helpers")

describe("rust_routes.scan_source", function()
  before_each(function()
    H.need_parser("rust")
  end)

  it("finds axum .route() calls and actix attribute routes", function()
    local f = assert(io.open(H.fixtures .. "/sql_and_routes.rs"))
    local src = f:read("*a")
    f:close()
    local paths = {}
    for _, r in ipairs(require("xyno_rust.rust_routes").scan_source(src)) do
      paths[#paths + 1] = r.path
    end
    table.sort(paths)
    H.eq({ "/health", "/health", "/users/:id" }, paths)
  end)
end)
'''),
    ...sec(r'what the fixture contains'),
    ...para('--', r'The input is tests/fixtures/sql_and_routes.rs, 18 lines. Two pieces of it are routes and '
        r'one piece is a decoy.'),
    ...code('lua', r'tests/fixtures/sql_and_routes.rs · lines 11-18', r'''
#[get("/health")]
async fn health() -> &'static str {
    "ok"
}

fn app() -> Router {
    Router::new().route("/users/:id", get(user)).route("/health", get(health))
}
'''),
    ...pt('--', r'line 11', r'#[get("/health")] above async fn health. An attribute route: the verb is get, the path is '
        r'the first string in the attribute.'),
    ...pt('--', r'line 17', r'Router::new().route("/users/:id", get(user)).route("/health", get(health)). Two chained '
        r'.route calls on one line. The scanner must report both, not stop at the first.'),
    ...pt('--', r'lines 3-8', r'two sqlx queries with SQL strings. They are the decoy. The first lines of the fixture say '
        r'it is shared with the sqlx SQL injection check of the original configuration (the comment '
        r'on line 1 mentions both), so it carries strings that look like code to a careless '
        r'scanner. None of them is a route, and none may appear in the result.'),
    ...para('--', r'Note the path /users/:id. That is a colon-style path parameter. The scanner does not '
        r'interpret the path at all, it returns the text of the string literal, so /users/{id} (the '
        r'newer axum style shown in the header comment of rust_routes.lua) would pass through the '
        r'same way.'),
    ...sec(r'reading the assertion'),
    ...para('--', r'The test reads the fixture from disk, passes the text to scan_source and keeps only the '
        r'path field of each result. Then it sorts them and compares with H.eq against { "/health", '
        r'"/health", "/users/:id" }.'),
    ...para('--', r'Three details are worth reading closely.'),
    ...pt('--', r'sorted before comparing', r'scan_source itself sorts by row, but the spec does not depend on that. It sorts the paths '
        r'so that the order of the two sources of /health (the attribute on line 11 and the .route '
        r'on line 17) cannot matter. Ordering is tested elsewhere, in rust-routes_spec.lua.'),
    ...pt('--', r'/health appears twice', r'The attribute route and the .route call are two matches in different places that happen to share a path. A scanner that de-duplicated by path would return two '
        r'entries and this test would fail. The spec therefore also pins that nothing is merged.'),
    ...pt('--', r'only paths are checked', r'kind, detail, row and col are not asserted here. Keeping the assertion to one field is '
        r'what makes the test short and hard to break for unrelated reasons.'),
    ...sec(r'the guard in before_each'),
    ...code('lua', r'tests/routes_spec.lua · lines 5-7', r'''
  before_each(function()
    H.need_parser("rust")
  end)
'''),
    ...para('--', r'H.need_parser("rust") calls vim.treesitter.language.add("rust"). If that does not return '
        r'true the helper calls harness.skip with the text "tree-sitter rust parser not installed", '
        r'and the runner prints SKIP instead of FAIL. The scanner has nothing to scan without the '
        r'grammar, so a missing parser is a property of the machine, not a bug of the plugin. In CI '
        r'the parser is built from a pinned commit of tree-sitter-rust (the TS_RUST_SHA variable of '
        r'.github/workflows/ci.yml), so on the pipeline this spec is expected to run, not skip.'),
    ...sec(r'where it came from'),
    ...para('--', r'The test was written in xynovim on 2026-10-13 (cf2b8e1, the commit that introduced the '
        r'whole tests/ directory with scripts/test.sh). There it required config.rust_routes and '
        r'the helper module xynotest.helpers, and it had no parser guard. When the module was '
        r'extracted into this plugin (7c1d2d9, 2026-10-22) three things changed: the helper '
        r'namespace became xyno_rust_test.helpers, the module under test became '
        r'xyno_rust.rust_routes, and the before_each with need_parser was added. The assertion '
        r'itself, the fixture and the expected list are unchanged.'),
    ...para('--', r'The fixture was copied across as is. Its first comment still talks about the sqlx SQL '
        r'injection, a feature that belongs to xynovim and not to this plugin, so the comment '
        r'describes a wider purpose than the file now has here.'),
    ...sec(r'what this spec does not prove'),
    ...pt('--', r'ordering', r'no assertion on the order of results. See rust-routes_spec.lua for the sort by row.'),
    ...pt('--', r'the picker', r'nothing here opens Snacks.picker. The :RustRoutes command and the format of a picker row '
        r'are tested in rust-routes_spec.lua with a stand-in for snacks.nvim.'),
    ...pt('--', r'directory walking', r'scan_source takes a string. The walk through the workspace, with its skip list and depth '
        r'limit, is collect() and is tested elsewhere.'),
    ...pt('--', r'the exact grammar version', r'the CI parser is pinned, so a grammar change cannot reach this test by surprise. A local '
        r'parser of another version might.'),
    ...sec(r'how to run it alone'),
    ...para('--', r'nvim -l tests/run.lua tests/routes_spec.lua runs the file in the current process. Without '
        r'an argument the runner starts one headless Neovim per spec file and sums the RESULT '
        r'lines. With a parser outside the runtimepath, XYNO_TEST_RTP=/dir/with/parser points the '
        r'runner at a directory holding parser/rust.so.'),
  ],
);
