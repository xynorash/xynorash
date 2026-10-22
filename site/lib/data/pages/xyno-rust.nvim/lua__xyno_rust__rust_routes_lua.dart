import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-rust.nvim/lua/xyno_rust/rust_routes.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'rust_routes.lua - the endpoints of a web service, found with tree-sitter'),
    cm('--', r'no language server, no running app'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'HTTP route picker for axum, actix-web, rocket and poem-style attributes'),
    kv(r'language', r'Lua with an embedded tree-sitter query'),
    kv(r'size', r'150 lines; ancestor lua/config/rust_routes.lua (527f350, 2026-10-09)'),
    kv(r'command', r':RustRoutes'),
    kv(r'tested by', r'tests/routes_spec.lua and tests/rust-routes_spec.lua'),
    ...sec(r'why this file exists'),
    ...para('--', r'Web frameworks in Rust register routes in code, not in a table. In axum a route is an expression, .route("/users/{id}", get(show).delete(remove)); in actix-web and rocket it is an attribute, #[get("/users")] above a function. To answer "where is POST /users handled?" the usual tools are grep or the memory of the author. The header comment says what this does instead: a picker of every route in the workspace that jumps to its definition, pure tree-sitter, no LSP, inspired by the Endpoints tool window of the JetBrains IDEs, minimal. The decision to avoid rust-analyzer matters: routes are syntax, so the answer needs neither a loaded workspace nor a finished build, and works while the server is still indexing.'),
    ...sec(r'the query'),
    ...code('lua', r'lua/xyno_rust/rust_routes.lua · lines 6-23', r'''
local M = {}

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

--- Parse `src` and return { { path, kind, detail, row, col } ... } (row 0-based).'''),
    ...para('--', r'The query has two alternatives. The first matches a call whose function is a field expression named route (that is, a method call .route(...)) with a string literal as the first argument and any expression as the second: the path is captured as @path and the handler expression as @handler. The #eq? predicate on the helper capture @_f restricts it to the method name route, so no other two-argument method call matches. The second alternative matches an attribute item whose name is a plain identifier or the last segment of a scoped path (so both #[get("/x")] and #[actix_web::post("/x")]) and whose token tree starts with a string literal. The attribute can be any attribute at this point; the filter by verb happens in Lua, against the METHODS list.'),
    ...sec(r'scan_source'),
    ...code('lua', r'lua/xyno_rust/rust_routes.lua · lines 24-49', r'''
function M.scan_source(src)
  local ok, parser = pcall(vim.treesitter.get_string_parser, src, "rust")
  if not ok then
    return {}
  end
  local tree = parser:parse()[1]
  local query = vim.treesitter.query.parse("rust", QUERY)
  local out = {}
  for _, match in query:iter_matches(tree:root(), src, 0, -1) do
    local cap = {}
    for id, nodes in pairs(match) do
      cap[query.captures[id]] = nodes[#nodes]
    end
    if cap.verb then
      -- attribute: only HTTP verbs, and the route belongs to the fn that follows
      local verb = vim.treesitter.get_node_text(cap.verb, src)
      if vim.list_contains(METHODS, verb) then
        local fn = cap.verb
        while fn and fn:type() ~= "attribute_item" do
          fn = fn:parent()
        end
        local nxt = fn and fn:next_named_sibling()
        while nxt and nxt:type() == "attribute_item" do
          nxt = nxt:next_named_sibling()
        end
        local name = nxt and nxt:type() == "function_item" and vim.treesitter.get_node_text(nxt:field("name")[1], src)'''),
    ...para('--', r'scan_source takes source text rather than a path, which is why the specs can feed it strings. It builds a string parser for rust, wrapped in pcall: if the tree-sitter rust parser is not installed the function returns an empty list instead of raising. For each match the captures are collected (taking the last node of each capture, as iter_matches yields lists), and attribute matches are accepted only when the verb is in METHODS (get, post, put, delete, patch, head, options, trace, connect and the generic route). That check is what keeps #[derive("...")]-like attributes with a string from becoming routes. The route belongs to the function that follows the attribute: the code climbs to the attribute_item, then skips over further attribute items (a handler often has several), and takes the name of the next function_item.'),
    ...code('lua', r'lua/xyno_rust/rust_routes.lua · lines 55-81', r'''
          row = row,
          col = col,
        }
      end
    elseif cap.handler then
      local row, col = cap.path:start()
      out[#out + 1] = {
        path = vim.treesitter.get_node_text(cap.path, src),
        kind = "ROUTE",
        -- `get(show).delete(remove)` / `web::get().to(h)` / `any(h)`, whitespace squeezed
        detail = (vim.treesitter.get_node_text(cap.handler, src):gsub("%s+", " ")),
        row = row,
        col = col,
      }
    end
  end
  table.sort(out, function(a, b)
    return a.row < b.row
  end)
  return out
end

local SKIP = { target = true, [".git"] = true, node_modules = true, ["bacon-ls-live"] = true }

--- Every route in the workspace's .rs files.
function M.collect(root)
  local items = {}'''),
    ...para('--', r'Each result is a table of path, kind, detail, row and column. For an attribute the kind is the verb in upper case and the detail is the function name (or ?). For a .route call the kind is ROUTE and the detail is the handler expression with whitespace squeezed to single spaces, so a multi-line get(show).delete(remove) fits in one picker line. Results are sorted by row.'),
    ...sec(r'walking the workspace'),
    ...code('lua', r'lua/xyno_rust/rust_routes.lua · lines 83-123', r'''
    depth = 12,
    skip = function(dir)
      return not SKIP[vim.fs.basename(dir)] -- dir is the path relative to root: nested target/ too
    end,
  }) do
    if type == "file" and name:match("%.rs$") then
      local file = root .. "/" .. name
      local f = io.open(file)
      local src = f and f:read("*a")
      if f then
        f:close()
      end
      -- cheap pre-filter before parsing
      if src and (src:find(".route(", 1, true) or src:find("#[", 1, true)) then
        for _, r in ipairs(M.scan_source(src)) do
          items[#items + 1] = {
            text = ("%s %s  %s  %s"):format(r.kind, r.path, r.detail, name),
            file = file,
            pos = { r.row + 1, r.col },
            kind = r.kind,
            route = r.path,
            detail = r.detail,
            rel = name,
          }
        end
      end
    end
  end
  return items
end

function M.pick()
  local root = require("xyno_rust.rust_context").root()
  if not root then
    return vim.notify("no Cargo.toml found", vim.log.levels.WARN)
  end
  local items = M.collect(root)
  if #items == 0 then
    return vim.notify("no routes found (.route(\"/p\", ..) or #[get(\"/p\")])", vim.log.levels.INFO)
  end
  local Snacks = require("xyno_rust.deps").snacks()'''),
    ...para('--', r'The SKIP set is target, .git, node_modules and bacon-ls-live; the last name is not explained in the file, but both walking specs create a bacon-ls-live directory next to target, .git and node_modules and assert it is skipped. The comment inside skip notes a subtlety of vim.fs.dir: the argument is the path relative to the root, so basename is compared to catch a nested target/ too. Depth is limited to 12. The cheap pre-filter (the comment says “cheap pre-filter before parsing”) is the performance decision: a file is parsed only when its text contains .route( or #[, so a large workspace of files that register nothing is read but never parsed.'),
    ...sec(r'picking'),
    ...code('lua', r'lua/xyno_rust/rust_routes.lua · lines 114-140', r'''
function M.pick()
  local root = require("xyno_rust.rust_context").root()
  if not root then
    return vim.notify("no Cargo.toml found", vim.log.levels.WARN)
  end
  local items = M.collect(root)
  if #items == 0 then
    return vim.notify("no routes found (.route(\"/p\", ..) or #[get(\"/p\")])", vim.log.levels.INFO)
  end
  local Snacks = require("xyno_rust.deps").snacks()
  if not Snacks then
    return
  end
  Snacks.picker({
    title = "Routes",
    items = items,
    format = function(item)
      return {
        { ("%-7s"):format(item.kind), "Keyword" },
        { item.route .. "  ", "String" },
        { item.detail .. "  ", "Function" },
        { item.rel, "Comment" },
      }
    end,
    preview = "file",
  })
end'''),
    ...para('--', r'pick finds the workspace root through rust_context.root, reports "no Cargo.toml found" or "no routes found" with the two shapes it understands, and otherwise opens a snacks picker with a custom formatter: the kind in the Keyword highlight padded to seven columns, the route as a String, the detail as a Function and the relative file as a Comment, with the file preview enabled. The item carries pos as row plus one and the column of the string literal, so confirming a route lands on the path string.'),
    ...sec(r'limits visible in the code'),
    ...para('--', r'The query sees literal strings only. A route built with a constant, a nest() prefix or a macro will not be listed, and a nested router shows the path as written inside the nested router, not the full URL. Nothing in the code tries to compose prefixes, and this page does not claim it does. A rocket routes! macro is not matched either.'),
    ...sec(r'how it is tested'),
    ...para('--', r'tests/routes_spec.lua (20 lines) and tests/rust-routes_spec.lua (455 lines) feed scan_source and collect with source text and fixture trees. The header of rust-routes_spec says no LSP and no cargo are needed but the tree-sitter rust parser is; the parser tests skip with a message when it is not installed, and one case checks that scan_source returns an empty list when the parser cannot be created; CI builds it from a pinned commit of tree-sitter-rust.'),
    ...sec(r'history'),
    ...para('--', r'The first version appeared in xynovim in 527f350 (2026-10-09, "Roadmap step 10 wip: rest extra, domain plugin, routes, sql injection, unsafe hl"), 142 lines. The only later change before the extraction was in the first field-test round (98c9bb4, 2026-10-13), and 0247401 (2026-10-22) reworded the header. Copied into this repository in c1c7958.'),
  ],
);
