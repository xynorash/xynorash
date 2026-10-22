import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/tests/routes_spec.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'routes_spec.lua — the smallest feature spec in the suite'),
    cm('--', r'16 lines, one assertion about the route scanner'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'checks rust_routes.scan_source on the sql_and_routes.rs fixture, with no LSP'),
    kv(r'language', r'Lua spec, 16 lines, 1 it() blocks, 1 describe() blocks'),
    kv(r'size', r'16 lines'),
    kv(r'sibling', r'rust-routes_spec.lua covers the rest of :RustRoutes'),
    ...sec(r'why this file exists'),
    ...para('--', r':RustRoutes lists the HTTP routes of a Rust web project. The scanning part is a pure function over source text that uses treesitter, so it can be tested without rust-analyzer, without a project and without a picker. This spec is the smallest check of that function: feed it a fixture and compare the paths.'),
    ...code('lua', r'tests/routes_spec.lua · lines 1-4', r'''
-- :RustRoutes scanner on the sql_and_routes.rs fixture (treesitter, no LSP).
local H = require("xynotest.helpers")

describe("rust_routes.scan_source", function()'''),
    ...sec(r'what the test does'),
    ...para('--', r'It reads tests/fixtures/sql_and_routes.rs from disk, calls require("config.rust_routes").scan_source(src), collects the path field of every returned route and sorts them. The expected list is /health twice and /users/:id. The fixture (its first line calls it strings the sqlx SQL injection and the route picker look at, with no crate) has an axum Router with .route("/users/:id", ...) and .route("/health", ...) and an attribute route #[get("/health")]; that is why /health appears twice. Sorting makes the comparison independent of discovery order.'),
    ...code('lua', r'tests/routes_spec.lua · lines 5-16', r'''
  it("finds axum .route() calls and actix attribute routes", function()
    local f = assert(io.open(H.fixtures .. "/sql_and_routes.rs"))
    local src = f:read("*a")
    f:close()
    local paths = {}
    for _, r in ipairs(require("config.rust_routes").scan_source(src)) do
      paths[#paths + 1] = r.path
    end
    table.sort(paths)
    H.eq({ "/health", "/health", "/users/:id" }, paths)
  end)
end)'''),
    ...sec(r'design notes'),
    blank,
    ...pt('--', r'Plain file read', r'the test uses io.open on H.fixtures instead of opening the file in a buffer, so it checks the scanner, not the editor.'),
    ...pt('--', r'No stubbing', r'the header says treesitter, no LSP; the scanner is called directly.'),
    ...pt('--', r'Shared fixture', r'the same file also serves the SQL injection tests in snippets-completion-injections_spec.lua (line 532).'),
    ...sec(r'where the rest is tested'),
    ...para('--', r'rust-routes_spec.lua (490 lines) also reads this fixture (line 34) and covers the rest of the feature; this file is the quick check. It has one commit, cf2b8e1 (2026-10-13).'),
  ],
);
