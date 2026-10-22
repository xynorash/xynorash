import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/lua/config/rust_routes.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'rust_routes.lua — :RustRoutes, the HTTP endpoint list of a Rust web project'),
    cm('--', r'pure treesitter, no language server: scan every .rs file for axum and attribute routes'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'route picker for axum / actix-web / rocket / poem-style projects'),
    kv(r'language', r'Lua with a treesitter query for Rust; Snacks.picker for the UI'),
    kv(r'size', r'142 lines, 3 commits (527f350, 98c9bb4, 0247401)'),
    kv(r'command', r':RustRoutes, mapped to <leader>rN in the Rust key group'),
    kv(r'also lives in', r'xyno-rust.nvim (lua/xyno_rust/rust_routes.lua), with a Snacks guard and a commands option'),
    ...sec(r'why this file exists'),
    ...para('--', r'A web service is organised by its routes: which URL reaches which handler. In a Rust project they are scattered. With axum a route is a method call in a builder chain; with actix-web, rocket and poem-style frameworks it is an attribute above a function. No language-server request answers "list the endpoints", so the module does it by reading syntax. The header says what it is: an HTTP route picker, "inspired by the Endpoints tool window of the JetBrains IDEs, minimal", "Pure treesitter, no LSP". It was added in the commit 527f350 on 2026-10-09 (the roadmap step 10 work in progress, together with the SQL injection queries and unsafe highlighting).'),
    ...para('--', r'The three shapes it understands are listed in the header and each has a comment line of example code: a .route("/users/{id}", get(show).delete(remove)) call for axum, with actix’s web::get().to(h) form as a handler expression; an attribute like #[get("/users")] on an async fn for actix-web, rocket and poem-style frameworks; and the fully-qualified attribute #[actix_web::post("/users")].'),
    ...sec(r'the treesitter query'),
    ...code('lua', r'lua/config/rust_routes.lua · lines 8-21', r'''
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
]]'''),
    ...para('--', r'There are two patterns in one query. The first matches a method call whose method name is route and whose argument list begins with a string literal followed by exactly one more argument. The dots are treesitter anchors: the string must be the first argument, and the handler must come immediately after it. The captured string content is the path and the second argument is the handler expression. The #eq? predicate on a captured underscore name filters by method name without exposing it as an output.'),
    ...para('--', r'The second pattern matches an attribute item whose name is either a plain identifier (get) or the last segment of a scoped path (actix_web::post), and whose first argument inside the attribute’s token tree is a string literal. The alternation brackets give both forms the same capture name, verb. This pattern is deliberately generous: it matches any attribute that begins with a string, with a string as its first argument (the first one the spec exercises is an attribute that is not an HTTP verb), and the Lua side filters by verb. The list METHODS above holds the HTTP verbs plus route, so the filter happens against a short, fixed vocabulary.'),
    ...sec(r'scan_source: turn a string into route records'),
    ...code('lua', r'lua/config/rust_routes.lua · lines 23-75', r'''
--- Parse `src` and return { { path, kind, detail, row, col } ... } (row 0-based).
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
        local name = nxt and nxt:type() == "function_item" and vim.treesitter.get_node_text(nxt:field("name")[1], src)
        local row, col = cap.path:start()
        out[#out + 1] = {
          path = vim.treesitter.get_node_text(cap.path, src),
          kind = verb:upper(),
          detail = name or "?",
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
end'''),
    ...para('--', r'The function takes a source string, not a buffer. That is a decision that makes everything downstream testable and cheap: the parser is made with get_string_parser, so no buffer is created, no file type detection runs, and a missing Rust grammar is a pcall failure that returns an empty list instead of an error. The spec checks that case ("returns {} when the parser cannot be created") and that junk input never raises.'),
    ...para('--', r'Each match is flattened into a capture table, taking the last node when a capture matched several. Then there are two kinds of record. If the match has a verb it is an attribute route. The verb is checked against METHODS, which drops attributes such as derive-like ones that happen to start with a string. The function that the route belongs to is found by walking up from the verb to the enclosing attribute_item, then moving along its siblings past any further stacked attributes (a handler often has #[get("/x")] followed by #[tracing::instrument]) until the next named node, which must be a function_item for its name to be used; otherwise the detail is "?". The record keeps the upper-cased verb as kind, the function name as detail, and the 0-based row and column of the path string.'),
    ...para('--', r'If the match has a handler capture instead, it is a .route() call. The kind is the fixed word ROUTE and the detail is the handler expression, with all runs of whitespace squeezed into single spaces, so a handler expression spread over several lines shows as one line. That keeps the picker row to one line, and the comment lists three forms it is expected to display: get(show).delete(remove), web::get().to(h), any(h). Results are sorted by row so that attribute routes and method-call routes of one file appear in source order, which the spec tests by mixing both kinds.'),
    ...para('--', r'There are known blind spots, and the spec states them honestly in a test named "does not recognise nest, web::resource or macro-built routes". A router mounted with nest("/api", ...) is not followed and prefixes are not joined; so the path shown is the path as written in that file.'),
    ...sec(r'collect: walk the workspace'),
    ...code('lua', r'lua/config/rust_routes.lua · lines 77-112', r'''
local SKIP = { target = true, [".git"] = true, node_modules = true, ["bacon-ls-live"] = true }

--- Every route in the workspace's .rs files.
function M.collect(root)
  local items = {}
  for name, type in vim.fs.dir(root, {
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
end'''),
    ...para('--', r'vim.fs.dir with a depth of 12 walks the tree under the project root. The skip callback is the interesting line. vim.fs.dir calls it with the path of each directory relative to the root, and only descends into it if the callback returns true. The first version tested the whole relative path against the SKIP set, which only works for a directory at the top. The fix in 98c9bb4 (2026-10-13), visible in the commit’s diff, takes the basename first, with the comment that the path is relative to the root so that a nested target/ directory in a workspace member is skipped as well. Without it, a nested target/ directory of a workspace member would not be skipped and its contents would be walked. The four skipped names are target, .git, node_modules and bacon-ls-live (the last is a directory name that the config treats as bacon-ls output).'),
    ...para('--', r'Reading a file is plain io.open; then a cheap pre-filter: the text must contain a literal .route( or #[ before it is handed to the parser. string.find with the plain flag is a cheap literal search, while parsing is the expensive part. The pre-filter lets most files of a large workspace skip the parser, and the spec tests it ("pre-filter: only files containing ’.route(’ or ’#[’ are parsed"). The items carry everything the picker needs: the display text, the absolute file, the position as { line 1-based, column 0-based }, and the parts again for custom formatting. The spec checks that the walk stops after depth 12 ("walks to depth 12 and no further").'),
    ...sec(r'pick: the UI'),
    ...code('lua', r'lua/config/rust_routes.lua · lines 114-140', r'''
function M.pick()
  local root = require("config.rust_context").root()
  if not root then
    return vim.notify("no Cargo.toml found", vim.log.levels.WARN)
  end
  local items = M.collect(root)
  if #items == 0 then
    return vim.notify("no routes found (.route(\"/p\", ..) or #[get(\"/p\")])", vim.log.levels.INFO)
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
end

function M.setup()
  vim.api.nvim_create_user_command("RustRoutes", M.pick, { desc = "Pick an axum/actix/rocket route in the workspace" })
end'''),
    ...para('--', r'The root comes from rust_context.root(), the module that finds the workspace via cargo, so :RustRoutes works from any file in the workspace; without a Cargo.toml it warns "no Cargo.toml found". Zero routes is not an error: the user gets an INFO message that shows the two shapes the scanner looks for, which doubles as documentation. The picker shows four colour-coded columns: the kind padded to 7 characters in the Keyword group (so GET, POST, ROUTE and the longer verbs line up), the route in String, the handler in Function and the relative file in Comment, with a file preview. Selecting a row jumps to the file at the route’s position, because every item carries file and pos.'),
    ...sec(r'what differs in xyno-rust.nvim'),
    ...para('--', r'Extracted on 2026-10-22 as lua/xyno_rust/rust_routes.lua. The scanning code is identical. A diff shows three changes: root comes from xyno_rust.rust_context instead of config.rust_context; pick() first asks require("xyno_rust.deps").snacks() for the picker and returns quietly if Snacks is not installed, where this version uses the global Snacks directly and would raise an error without it; and setup(opts) accepts opts.commands = false to skip defining :RustRoutes. These are the changes a library needs and an in-config file does not: it must not assume the host has Snacks, and must let the user define their own command. The config here has not been switched to the plugin yet, so both copies exist.'),
    ...sec(r'how it is tested'),
    ...para('--', r'tests/rust-routes_spec.lua (27 it() blocks) has one describe per function: the command definition, scan_source (the three-route fixture, the sort by row, chained methods, whitespace squeezing, actix handler forms, stacked attributes, scoped verbs, "?" for an attribute not followed by a function, junk input, no parser, and the documented blind spots), collect (skips including the nested ones, the pre-filter, the depth limit, empty workspaces), pick (no Cargo.toml, no routes, the picker options and the four-chunk formatting) and the <leader>rN mapping when rust-analyzer attaches. A final test builds a mixed-style scratch crate and checks four routes by verb, handler and line, which is the claim the README makes.'),
    ...sec(r'history'),
    ...pt('--', r'527f350 · 2026-10-09', r'Roadmap step 10 wip: rest extra, domain plugin, routes, sql injection, unsafe hl. The file is created at 142 lines.'),
    ...pt('--', r'98c9bb4 · 2026-10-13', r'Final loop round 1: the nested target/ skip (SKIP is tested on the basename).'),
    ...pt('--', r'0247401 · 2026-10-22', r'Positioning: the header changed from "RustRover’s Endpoints tool window" to "inspired by the Endpoints tool window of the JetBrains IDEs".'),
  ],
);
