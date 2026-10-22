import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/tests/rust-routes_spec.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'rust-routes_spec.lua — a route list from treesitter, with axum, actix, rocket and poem'),
    cm('--', r'what the scanner finds, what it deliberately does not, and how deep the walk goes'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'spec for lua/config/rust_routes.lua: treesitter scanner, workspace walk, picker and the leader r N map'),
    kv(r'language', r'Lua spec, 490 lines, 27 it() blocks, 6 describe() blocks'),
    kv(r'needs', r'no LSP and no cargo'),
    kv(r'history', r'5 commits, 2026-10-13 to 2026-10-16'),
    ...sec(r'why this file exists'),
    ...para('--', r'In a web service, the question where is this endpoint defined is asked often and answered by grep, which does not know about axum builder chains or attribute macros. :RustRoutes lists the routes of the workspace in a picker and jumps to them. The scanner must be exact about what it recognises, because a router listing that lies is worse than none. The header says the scope: treesitter scanner, workspace walk, picker and the map, with no LSP and no cargo. The routes_spec.lua file is the quick check of one fixture; this is the full spec.'),
    ...code('lua', r'tests/rust-routes_spec.lua · lines 1-3', r'''
-- :RustRoutes (lua/config/rust_routes.lua): treesitter scanner, workspace walk,
-- picker and the <leader>rN map. No LSP and no cargo needed.
local H = require("xynotest.helpers")'''),
    ...sec(r'the shape of an item'),
    ...para('--', r'Every route is a table with path, kind, detail, row and col, sorted by row. The kind is the upper-cased verb for attribute routes and ROUTE for builder calls. The position is the 0-based position of the string content (not the quote), so a jump lands on the path. Axum .route calls with chained methods are ROUTE and the detail is the handler expression, whitespace squeezed to single spaces for multi-line chains. Attribute routes use the next function name as the detail, resolved through several stacked attributes, or ? when no function follows. The last identifier of a scoped attribute is the verb, so actix_web::post becomes POST.'),
    ...sec(r'frameworks'),
    ...para('--', r'One test lists the attribute styles together: actix with a scoped post, rocket with a get and a path parameter, poem with a plain get, and the generic route attribute with a method key. An unrelated attribute such as handler is ignored. The expected summary is explicit lines of verb, path and function: POST /a create, GET /b/<id> rocket_get, GET /c poem_get and ROUTE /d generic. Actix web::get().to(h) and any(h) handlers are listed as ROUTE.'),
    ...code('lua', r'tests/rust-routes_spec.lua · lines 100-119', r'''
  it("handles actix, rocket and poem style attributes", function()
    local src = table.concat({
      '#[actix_web::post("/a")]',
      "async fn create() {}",
      '#[get("/b/<id>")]',
      "fn rocket_get(id: u32) {}",
      '#[handler]',
      "fn poem_unrelated() {}",
      '#[get("/c")]',
      "async fn poem_get() -> String { String::new() }",
      '#[route("/d", method = "GET")]',
      "async fn generic() {}",
    }, "\n")
    H.eq({
      "POST /a create",
      "GET /b/<id> rocket_get",
      "GET /c poem_get",
      "ROUTE /d generic",
    }, summary(scan(src)))
  end)'''),
    ...sec(r'what is not recognised, and the test says so'),
    ...para('--', r'nest, web::resource and macro-built routes are not listed. The test feeds a router with nest, an actix service config using web::resource with an inner .route whose first argument is not a string, and a Rocket routes! macro plus a custom route macro, and requires an empty list. The comment explains the actix case: web::resource produces nothing, and the inner .route call has a non-string first argument. A scanner that documents its gaps by test makes the gaps part of the contract rather than a surprise.'),
    ...code('lua', r'tests/rust-routes_spec.lua · lines 181-197', r'''
  it("does not recognise nest, web::resource or macro-built routes", function()
    local src = table.concat({
      "fn app() -> Router {",
      '    Router::new().nest("/api", api_router())',
      "}",
      "fn cfg(c: &mut web::ServiceConfig) {",
      '    c.service(web::resource("/res").route(web::get().to(h)));',
      "}",
      "fn m() { routes![index, about]; my_route!(\"/m\", h); }",
    }, "\n")
    local items = scan(src)
    -- web::resource("/res") produces nothing; its inner .route(...) has a
    -- non-string first argument, so nothing is listed at all
    H.eq({}, items)
    H.eq({}, scan('fn a(){ Router::new().nest("/api", sub); }'))
  end)
end)'''),
    ...sec(r'robustness'),
    ...para('--', r'An empty string and junk return an empty list and never raise; when the parser cannot be created, the result is empty; the pre-filter parses only files that contain .route( or #[, to keep a large workspace fast.'),
    ...sec(r'the walk'),
    ...para('--', r'collect walks .rs files, skips target, .git, node_modules and bacon-ls-live (at the root and below, for workspace members), and fills the item fields. The depth test builds two files, one with exactly 12 path components and one with 13 below an extra directory, and requires that only the first is listed, so the limit is 12 and no further. A workspace without routes gives an empty list.'),
    ...code('lua', r'tests/rust-routes_spec.lua · lines 272-290', r'''
  it("walks to depth 12 and no further", function()
    local root = H.tmpdir()
    local function deep(n)
      local parts = {}
      for i = 1, n - 1 do
        parts[i] = "d" .. i
      end
      parts[#parts + 1] = "f.rs"
      return table.concat(parts, "/")
    end
    local src = '#[get("/deep")]\nfn f() {}\n'
    write(root .. "/" .. deep(12), src)
    write(root .. "/x/" .. deep(12), src) -- 13 components
    local rels = vim.tbl_map(function(i)
      return i.rel
    end, R.collect(root))
    H.has(rels, deep(12))
    H.eq(1, #rels, "a file below depth 12 was listed: " .. vim.inspect(rels))
  end)'''),
    ...sec(r'picker and key'),
    ...para('--', r'pick warns no Cargo.toml found outside a crate and opens no picker; notifies INFO when the crate has no routes; opens a Snacks picker titled Routes with the items and a file preview. The format function returns four chunks: kind padded to 7 columns (Keyword highlight), the route (String), the detail (Function) and the relative path (Comment). The leader r N key maps to :RustRoutes buffer-locally when rust-analyzer attaches. The last block builds a mixed-style scratch crate used to verify the README and requires four routes with the right verbs, handlers and lines.'),
    ...sec(r'history'),
    blank,
    ...pt('--', r'b2fee5c (2026-10-13)', r'created. 98c9bb4 (2026-10-13) and 25086fd (2026-10-14) :: field test rounds.'),
    ...pt('--', r'fc2062a (2026-10-14)', r'CI on a clean machine. 9641d08 (2026-10-16) :: Windows drive letter.'),
  ],
);
