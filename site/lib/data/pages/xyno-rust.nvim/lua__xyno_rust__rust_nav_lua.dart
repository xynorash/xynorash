import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-rust.nvim/lua/xyno_rust/rust_nav.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'rust_nav.lua - two jumps rust-analyzer has no single request for'),
    cm('--', r'go to super method, and read/write usages in this file'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'navigation helpers on top of rust-analyzer requests and tree-sitter'),
    kv(r'language', r'Lua'),
    kv(r'size', r'103 lines; ancestor b64aa27 "wip-s7a" (2026-10-09) in xynovim'),
    kv(r'keys', r'<leader>ru, <leader>rl (opt-in through keymaps = true)'),
    kv(r'tested by', r'tests/rust-nav_spec.lua (318 lines)'),
    ...sec(r'why this file exists'),
    ...para('--', r'The comments in the file compare two features to the JetBrains IDEs: go to the super method (from a method in a trait impl to the same method in the trait) and usages in the file labelled read or write. rust-analyzer can answer both, but not in one request: it has a definition request and a document highlight request, and the glue between your cursor and those requests is what this file is.'),
    ...sec(r'go to super method'),
    ...code('lua', r'lua/xyno_rust/rust_nav.lua · lines 1-39', r'''
-- Rust navigation helpers that rust-analyzer has no single request for.
local M = {}

local function ra_client(buf)
  return vim.lsp.get_clients({ bufnr = buf, name = "rust-analyzer" })[1]
end

--- Go to super method (same idea as Ctrl+U in the JetBrains IDEs): from a method inside
--- `impl Trait for T`, jump to the same method in the trait definition.
function M.goto_super()
  local buf = vim.api.nvim_get_current_buf()
  local client = ra_client(buf)
  local node = vim.treesitter.get_node()
  while node and node:type() ~= "function_item" do
    node = node:parent()
  end
  if not (client and node) then
    return vim.notify("not inside a function", vim.log.levels.WARN)
  end
  local impl = node:parent()
  while impl and impl:type() ~= "impl_item" do
    impl = impl:parent()
  end
  local trait = impl and impl:field("trait")[1]
  if not trait then
    return vim.notify("not a trait impl method", vim.log.levels.WARN)
  end
  -- Land on the trait's own identifier: `fmt::Display`, `From<T>` -> `Display`, `From`.
  while trait:type() ~= "type_identifier" do
    local nxt = trait:field(trait:type() == "generic_type" and "type" or "name")[1]
    if not nxt then
      break
    end
    trait = nxt
  end
  local name = vim.treesitter.get_node_text(node:field("name")[1], buf)
  local row, col = trait:start()
  local params = {
    textDocument = vim.lsp.util.make_text_document_params(buf),'''),
    ...para('--', r'The cursor must be inside a function that is inside an impl with a trait field; otherwise the user gets one of two warnings ("not inside a function", "not a trait impl method"). The tree-sitter nodes are climbed with plain parent loops. The interesting move is where the definition request is sent: not at the method, which would return the method itself, but at the trait name in the impl header. A trait can be written fmt::Display or From<T>; the loop descends through scoped identifiers (field name) and generic types (field type) until it reaches a type_identifier, so the request lands on Display or From. The cursor position of that node is what goes to textDocument/definition.'),
    ...code('lua', r'lua/xyno_rust/rust_nav.lua · lines 40-70', r'''
    position = { line = row, character = col },
  }
  client:request("textDocument/definition", params, function(err, res)
    -- a list (first entry) or a single Location; `{}` is "not found" (the
    -- `islist and res[1] or res` form returned the empty list itself)
    local loc = res
    if type(res) == "table" and vim.islist(res) then
      loc = res[1]
    end
    if err or not loc then
      return vim.notify("trait definition not found", vim.log.levels.WARN)
    end
    vim.lsp.util.show_document(loc, client.offset_encoding, { focus = true })
    -- skip doc comments that mention `fn name` (std's Display::fmt has them first)
    local pat = "\\<fn\\s\\+" .. name .. "\\>"
    vim.fn.search(pat, "cw")
    -- (by line text: the freshly shown buffer has no treesitter parser yet, so
    -- get_node() was nil and the first match was always kept)
    for _ = 1, 50 do
      if not vim.api.nvim_get_current_line():match("^%s*/[/*]") and not vim.api.nvim_get_current_line():match("^%s*%*") then
        break
      end
      if vim.fn.search(pat, "w") == 0 then
        break
      end
    end
    vim.cmd("normal! zz")
  end, buf)
end

--- Reads/writes of the symbol under the cursor in this file, labelled'''),
    ...para('--', r'The response handler has three comments that each record a bug. A response can be a list or a single Location, and the older one-liner returned the empty list itself for no result; the handler now takes res[1] only for lists and treats a missing location as not found. After show_document the cursor is on the trait, and the code searches for fn followed by the method name with Vim regex search. Doc comments of std traits mention fn name before the real declaration (Display::fmt has them first), so the loop up to fifty iterations skips results whose line starts with a comment marker. The second comment explains why it checks the line text instead of asking tree-sitter: the freshly shown buffer has no parser yet, so get_node() was nil and the first match was always accepted. Finally normal! zz centres the match. In xynovim the single-Location fix and a first tree-sitter based comment skip arrived in 98c9bb4 (2026-10-13); a3d33c8 (2026-10-13, subject mentions "goto_super doc comments") replaced that with the line-text check; and f31e013 (2026-10-14) changed the default kind for a missing documentHighlight kind from 1 to 3.'),
    ...sec(r'usages in this file'),
    ...code('lua', r'lua/xyno_rust/rust_nav.lua · lines 72-100', r'''
function M.local_usages()
  local buf = vim.api.nvim_get_current_buf()
  local client = ra_client(buf)
  if not client then
    return
  end
  local params = vim.lsp.util.make_position_params(0, client.offset_encoding)
  client:request("textDocument/documentHighlight", params, function(err, res)
    if err or not res or #res == 0 then
      return vim.notify("no usages in this file", vim.log.levels.INFO)
    end
    -- rust-analyzer sends no kind on the declaration (`let x`): that is a write
    local kind = { [1] = "T", [2] = "R", [3] = "W" }
    local items = {}
    for _, h in ipairs(res) do
      local lnum = h.range.start.line + 1
      items[#items + 1] = {
        bufnr = buf,
        lnum = lnum,
        col = h.range.start.character + 1,
        text = ("[%s] %s"):format(kind[h.kind or 3], vim.trim(vim.api.nvim_buf_get_lines(buf, lnum - 1, lnum, false)[1] or "")),
      }
    end
    table.sort(items, function(a, b)
      return a.lnum < b.lnum
    end)
    vim.fn.setqflist({}, " ", { title = "usages (this file)", items = items })
    vim.cmd("copen")
  end, buf)'''),
    ...para('--', r'documentHighlight is the LSP request behind "highlight the other uses of this symbol". Its answer carries a kind: 1 text, 2 read, 3 write. The code maps them to T, R and W, with one non-obvious default noted in the comment: rust-analyzer sends no kind on the declaration, as in let x, and a declaration is a write, so a missing kind is treated as 3. Items are sorted by line, each shows [R], [W] or [T] and the trimmed line text, and they are placed in the quickfix list with the title "usages (this file)" before :copen. Using quickfix instead of a picker keeps it dependency free: this module does not need snacks at all.'),
    ...sec(r'design notes'),
    ...pt('--', r'no snacks, no module state', r'rust_nav has no setup() and does not use snacks (or deps.lua), so it needs nothing but a rust-analyzer client.'),
    ...pt('--', r'async requests', r'both functions use client:request with a callback and the buffer number, so waiting for the server does not block the editor.'),
    ...pt('--', r'first rust-analyzer client', r'ra_client takes the first client named rust-analyzer attached to the buffer.'),
    ...sec(r'how it is tested'),
    ...para('--', r'tests/rust-nav_spec.lua (318 lines) starts one real rust-analyzer for the file (its header says so, and that the tests are arranged so none depends on rust-analyzer timing) and needs the tree-sitter rust parser; it skips with a message without them. Cases include a doc comment mentioning fn area before the method being skipped, the doc-comment skip not depending on a parser (the std Display::fmt field-test case), the real-server jump from impl Shape for Square to the trait fn area, and the declaration being labelled [W] and not [T].'),
    ...sec(r'history'),
    ...para('--', r'b64aa27 (2026-10-09) introduced the file. 98c9bb4 (2026-10-13), a3d33c8 (2026-10-13) and f31e013 (2026-10-14) are the field-test rounds that appear in the history, and 0247401 (2026-10-22) reworded the JetBrains references. Copied unchanged into this repository in c1c7958.'),
  ],
);
