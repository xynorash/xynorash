import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/lua/config/rust_nav.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'rust_nav.lua — two navigation moves rust-analyzer has no single request for'),
    cm('--', r'go to the trait method you implement, and read/write usages inside one file'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'goto_super (<leader>ru) and local_usages (<leader>rl)'),
    kv(r'language', r'Lua; Neovim LSP client API plus treesitter'),
    kv(r'size', r'103 lines, 5 commits (b64aa27, 98c9bb4, a3d33c8, f31e013, 0247401)'),
    kv(r'talks to', r'rust-analyzer only: textDocument/definition and textDocument/documentHighlight'),
    kv(r'also lives in', r'xyno-rust.nvim as lua/xyno_rust/rust_nav.lua, byte-identical'),
    ...sec(r'why this file exists'),
    ...para('--', r'Two features that people from the JetBrains IDEs reach for have no one-to-one LSP request. The first is "go to super method": standing in a method inside impl Display for Foo, jump to the declaration of fmt in the trait. The second is usage grouping by kind: of all the places a symbol appears in the current file, which ones read it and which ones write it. This file builds each from the LSP requests that do exist plus a little treesitter. The header comment is honest about the origin of the ideas: Ctrl+U in the JetBrains IDEs and usage-type grouping there. The last commit to touch the file, 0247401 (2026-10-22, "Positioning: a personal project inspired by JetBrains, not a competitor"), is the one that reworded both doc comments: before it they named RustRover’s Go to super method and its usage-type grouping, after it they say the same idea exists in the JetBrains IDEs.'),
    ...para('--', r'Both functions are bound in lua/config/keymaps.lua in the Rust key group: <leader>ru "Go to super method (trait item)" and <leader>rl "Usages in file (R/W)". The file has no setup() and no commands; it is a table of two functions that the keymaps require lazily.'),
    ...sec(r'finding the client'),
    ...code('lua', r'lua/config/rust_nav.lua · lines 1-6', r'''
-- Rust navigation helpers that rust-analyzer has no single request for.
local M = {}

local function ra_client(buf)
  return vim.lsp.get_clients({ bufnr = buf, name = "rust-analyzer" })[1]
end'''),
    ...para('--', r'Both features need rust-analyzer specifically, not any attached client, because bacon-ls is also attached to Rust buffers in this config, and the code wants the answers of rust-analyzer in particular. The helper asks for the first client with that name attached to the buffer. It returns nil if there is none.'),
    ...sec(r'goto_super, part 1: walk up the syntax tree'),
    ...code('lua', r'lua/config/rust_nav.lua · lines 8-27', r'''
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
  end'''),
    ...para('--', r'The algorithm is: from the node under the cursor, climb to the nearest function_item; from there climb to the nearest impl_item; ask that impl for its trait field. If the impl has no trait field it is an inherent impl (impl Foo { ... }) and there is no super method, so the user gets "not a trait impl method". A treesitter field is the right tool here: it is how the Rust grammar marks the Trait in impl Trait for Type, and it is nil for the inherent form.'),
    ...para('--', r'One thing the code does that is easy to overlook: the two failure conditions are merged. If there is no rust-analyzer client attached, the message is also "not inside a function", which is not what is wrong. The cursor may be in a function and the server may simply not be running. This is a small wart in the user-facing text, not a logic bug, since the function still returns without doing harm.'),
    ...sec(r'goto_super, part 2: land on the right identifier'),
    ...code('lua', r'lua/config/rust_nav.lua · lines 28-41', r'''
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
    textDocument = vim.lsp.util.make_text_document_params(buf),
    position = { line = row, character = col },
  }'''),
    ...para('--', r'The trait in an impl header is not always a bare name. fmt::Display is a scoped_type_identifier whose last part is in the name field; From<T> is a generic_type whose name is in the type field. The loop peels these wrappers until it reaches a type_identifier, using the field name that matches the node kind, and it stops without crashing (break) if a wrapper has no such field. The position handed to the server is the start of that identifier. This is the motive for sending textDocument/definition on the trait name rather than on the method: asking the server for the definition of the method inside the impl would just return the impl itself.'),
    ...sec(r'goto_super, part 3: the request and the landing'),
    ...code('lua', r'lua/config/rust_nav.lua · lines 42-67', r'''
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
  end, buf)'''),
    ...para('--', r'The response shape of textDocument/definition is either a single Location, a list of locations, or a list of LocationLinks, and an empty list means not found. The code reduces all of these to one location: a list gives its first entry, anything else is taken as it is. The comment records the bug this replaced: the older idiom (islist and res[1] or res) returned the empty list itself when there was no result, because res[1] of an empty list is nil, so the and/or chain fell through to res, which is the empty (but truthy) list. The fix was made in a3d33c8 (2026-10-13), whose message lists "goto_super doc comments".'),
    ...para('--', r'The trait definition is then shown with vim.lsp.util.show_document, focusing the window, and the cursor is moved onto the method. This is a textual search: it looks for fn followed by the method name with word boundaries, starting at the cursor, wrapping. Why not use the server again? Because textDocument/definition on the trait gives the trait’s position, not the method’s, and the method inside it is found by searching the buffer the user has just been taken to.'),
    ...para('--', r'The loop is the part that came from field testing. The standard library’s Display trait has documentation above fmt that contains the text "fn fmt", so the first search hit is a comment. The code therefore checks, by line text, whether the line starts with a comment marker (// or /*) or a star-continued block comment, and if it does it searches again, up to 50 times, stopping early when the search finds nothing. The comment in the file explains why it is by line text and not by treesitter: the freshly shown buffer has no parser attached yet, so get_node() returned nil and the first match was always kept. Finally zz centres the line.'),
    ...sec(r'local_usages: reads and writes in this file'),
    ...code('lua', r'lua/config/rust_nav.lua · lines 70-101', r'''
--- Reads/writes of the symbol under the cursor in this file, labelled
--- [R]/[W], in the quickfix list (same idea as usage-type grouping in the JetBrains IDEs).
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
  end, buf)
end'''),
    ...para('--', r'textDocument/documentHighlight is the request that editors use to highlight the other occurrences of the word under the cursor. The LSP spec gives each highlight an optional kind: 1 for text, 2 for read, 3 for write. rust-analyzer fills those in, which is what lets the quickfix list label each line [R] or [W] ([T] for plain text). The result is turned into quickfix items with the file position, sorted by line number, and the list is opened with copen under the title "usages (this file)".'),
    ...para('--', r'The default label has a history. In commit f31e013 (2026-10-14) the fallback for a missing kind changed from 1 to 3, with the comment "rust-analyzer sends no kind on the declaration (let x): that is a write". Before, a declaration was labelled [T], text; afterwards it is [W]. The spec states it explicitly: "rust-analyzer sends no kind on a declaration: labelled [W], not [T]".'),
    ...para('--', r'Note what the function does when there is no client: it returns with no message at all. goto_super says something in the same situation (the misleading text above), local_usages says nothing. The two functions were written separately and the behaviours were never aligned. On an empty result, local_usages tells the user "no usages in this file" at INFO level, and an error from the server gets the same message.'),
    ...sec(r'design decisions and trade-offs'),
    ...pt('--', r'quickfix, not a picker', r'results go to the quickfix list rather than a Snacks picker. That keeps the feature independent of the picker plugin and makes the list navigable with the quickfix commands the user already knows, at the price of a window that takes space.'),
    ...pt('--', r'search instead of a second LSP request', r'finding the method inside the trait with a Vim search is less exact than a query on the server, but it is one line, needs no extra request, and the comment-skipping loop handles the case that actually occurred.'),
    ...pt('--', r'no setup', r'nothing is registered at load. The module costs nothing until a key is pressed.'),
    ...sec(r'the same file in xyno-rust.nvim'),
    ...para('--', r'Extracted on 2026-10-22 into xyno-rust.nvim (lua/xyno_rust/rust_nav.lua). A diff of the two files is empty: the code is identical, line for line, including the comments. The plugin and this config therefore hold two copies of the same functions until the config is switched to load the plugin.'),
    ...sec(r'how it is tested'),
    ...para('--', r'tests/keymaps-rust_spec.lua (75 it() blocks) covers both. The goto_super test is a real end-to-end run against rust-analyzer: it presses <leader>ru, waits up to 30 seconds for the cursor to land on the trait’s fn area, and checks that the current line matches "fn area(&self) -> f64;". The local_usages test, numbered 22, stubs the server’s answer with three highlights of kinds read, write and text and checks the quickfix title, the item count, the sort order, the [W]/[T]/[R] prefixes, the 1-based column and that a quickfix window is open. It then repeats the call with a highlight without a kind, to lock in the [W] default.'),
    ...sec(r'history'),
    ...pt('--', r'b64aa27 · 2026-10-09', r'wip-s7a: the first version of the file.'),
    ...pt('--', r'98c9bb4 · 2026-10-13', r'Final loop round 1: field test and spec findings.'),
    ...pt('--', r'a3d33c8 · 2026-10-13', r'Final loop round 2: goto_super and doc comments, and the fix for the empty-list result.'),
    ...pt('--', r'f31e013 · 2026-10-14', r'Final loop round 4: the declaration default changed from text to write.'),
    ...pt('--', r'0247401 · 2026-10-22', r'Positioning: a personal project inspired by JetBrains, not a competitor; both doc comments reworded from RustRover to the JetBrains IDEs.'),
  ],
);
