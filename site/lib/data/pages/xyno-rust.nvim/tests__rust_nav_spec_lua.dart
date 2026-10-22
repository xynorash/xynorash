import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-rust.nvim/tests/rust-nav_spec.lua',
  lines: [
    cm('--', r'──────────────────────────────────────────'),
    cm('--', r'tests/rust-nav_spec.lua — jumping to the trait, listing usages, without trusting the '
        r'server’s timing'),
    cm('--', r'one real rust-analyzer for the smoke checks, stubbed answers for everything with a rule in it'),
    cm('--', r'──────────────────────────────────────────'),
    blank,
    kv(r'role', r'spec for lua/xyno_rust/rust_nav.lua (103 lines): goto_super and local_usages'),
    kv(r'language', r'Lua, run by tests/run.lua'),
    kv(r'size', r'318 lines, 12 tests (one nested describe for local_usages)'),
    kv(r'needs', r'rust-analyzer on PATH and the tree-sitter rust parser; skips with a message without them'),
    kv(r'fixture', r'tests/fixtures/nav-crate (55 lines of Rust: a trait, four impls, a main, a test module)'),
    kv(r'origin', r'the <leader>ru and <leader>rl blocks of xynovim tests/keymaps-rust_spec.lua'),
    ...sec(r'why this file exists'),
    ...para('--', r'rust_nav.lua holds the two features that rust-analyzer has no single request for. '
        r'goto_super asks "which trait method does this impl method implement?" and answers by '
        r'finding the trait name in the impl header with tree-sitter, asking the server for its '
        r'definition and then searching for the right fn in the file it lands in. local_usages asks '
        r'for document highlights of the symbol under the cursor and turns them into a quickfix '
        r'list labelled read, write or text. Both are glue between three moving parts (tree-sitter, '
        r'an LSP reply, Neovim window state), which is exactly where small assumptions turn into '
        r'wrong cursor positions.'),
    ...para('--', r'The spec is shaped by one decision, written in its header: one real rust-analyzer session '
        r'is shared by the tests, and the rest of the behaviour is checked with stubs of the client '
        r'request, restored after each test, so that no test depends on rust-analyzer timing. A '
        r'server that is still indexing answers "not found" to a perfectly good request. A test '
        r'that depends on that answer is a flaky test. So the cases with rules in them get a canned '
        r'reply, and only two tests (one per feature) talk to the real server.'),
    ...sec(r'the module’s two entry points'),
    ...code('lua', r'lua/xyno_rust/rust_nav.lua · lines 7-30', r'''

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
'''),
    ...sec(r'the fixture'),
    ...code('lua', r'tests/fixtures/nav-crate/src/main.rs · lines 1-27', r'''
use std::fmt;

pub trait Shape {
    fn area(&self) -> f64;
}

pub struct Square(pub f64);

impl Shape for Square {
    fn area(&self) -> f64 {
        self.0 * self.0
    }
}

pub struct Wrapper(pub i32);

impl fmt::Display for Wrapper {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.0)
    }
}

impl From<i32> for Wrapper {
    fn from(v: i32) -> Self {
        Wrapper(v)
    }
}
'''),
    ...para('--', r'Every case in the spec is a place in this file. Square implements the crate’s own trait '
        r'(line 9), Wrapper implements fmt::Display with a scoped path (line 17) and From<i32> with '
        r'a generic argument (line 23), Wrapper also has a plain inherent impl (line 29), and main '
        r'binds total on line 41, using it once on line 43. Line 1 is a use, outside any function.'),
    ...sec(r'the shared session'),
    ...pt('--', r'stub', r'replaces t[k] by v with rawset and records an undo closure. after_each runs the closures '
        r'in reverse order. This is how stubs of the client, of vim.treesitter.get_node and of '
        r'vim.notify disappear between tests even when a test fails half way.'),
    ...pt('--', r'session', r'the first call needs rust-analyzer and the parser (H.need_rust, H.need_parser), opens the '
        r'nav-crate fixture, starts the tree-sitter highlighter on it and starts a real '
        r'rust-analyzer client through H.start_ra. Later calls reuse the same S table, close extra '
        r'windows, make the buffer current again and re-parse it. The comment says why: the tree '
        r'must follow the buffer reset of after_each because get_node does not reparse.'),
    ...pt('--', r'find', r'puts the cursor at the top and runs a very-nomagic search with the "cw" flags; it asserts '
        r'that the pattern was found, so a changed fixture fails loudly at the line that moved.'),
    ...pt('--', r'remember and reset_buffer', r'save the original lines on the first test and write them back after each one, so a test '
        r'can edit the buffer without poisoning the next. The modified flag is cleared too, so the '
        r'shared buffer never prompts.'),
    ...code('lua', r'tests/rust-nav_spec.lua · lines 78-96', r'''
describe("rust_nav", function()
  before_each(function()
    session()
    remember()
  end)

  local function stub_definition(reply)
    local seen = {}
    local orig = S.client.request
    stub(S.client, "request", function(self, method, params, cb, ...)
      if method ~= "textDocument/definition" and method ~= "textDocument/documentHighlight" then
        return orig(self, method, params, cb, ...) -- semantic tokens etc. stay real
      end
      seen[#seen + 1] = { method = method, params = params }
      cb(reply and reply.err, reply and reply.res)
      return true, 1
    end)
    return seen
  end
'''),
    ...para('--', r'The setup of a test is sensible: skip without the tools, get the session, remember the '
        r'buffer. The stub_definition helper is the centre of the spec. It wraps S.client.request. '
        r'For textDocument/definition and textDocument/documentHighlight it records the call and '
        r'immediately invokes the callback with the canned error and result; every other method is '
        r'passed through to the real request function. The comment says why: semantic tokens and '
        r'similar requests stay real, so the client keeps working. It returns the list of calls it '
        r'has seen, which later tests inspect to learn what the module asked for.'),
    ...sec(r'goto_super: the refusals'),
    ...code('lua', r'tests/rust-nav_spec.lua · lines 98-112', r'''
  it("outside a function: WARN 'not inside a function'", function()
    local n = notifications()
    find("use std::fmt")
    nav.goto_super()
    H.eq({ { msg = "not inside a function", level = vim.log.levels.WARN } }, n)
  end)

  it("inside a plain impl: WARN 'not a trait impl method'", function()
    local n = notifications()
    local l = find("pub fn plain")
    vim.api.nvim_win_set_cursor(0, { l + 1, 8 })
    nav.goto_super()
    H.eq({ { msg = "not a trait impl method", level = vim.log.levels.WARN } }, n)
  end)

'''),
    ...para('--', r'Four ways to get nothing, each with its own message and level.'),
    ...pt('--', r'outside a function', r'the cursor is on the use line. The module walks up from get_node for a function_item and '
        r'finds none: WARN not inside a function.'),
    ...pt('--', r'a plain impl', r'the cursor is inside Wrapper::plain. There is a function and an impl, but '
        r'impl:field("trait") is empty: WARN not a trait impl method.'),
    ...pt('--', r'no definition', r'the server answers nil: WARN trait definition not found.'),
    ...pt('--', r'an empty list', r'the server answers {} and the module still says trait definition not found. This pins the '
        r'bug fix of 98c9bb4 (history below): the old expression res[1] or res returned the empty '
        r'list itself, which is truthy.'),
    ...para('--', r'Cursor positions are l + 1 and column 8: one line below the fn signature, inside the '
        r'body, which is where a user would be when asking for the super method. All four compare '
        r'the whole notification list with H.eq, so an extra message also fails the test.'),
    ...sec(r'goto_super: asking for the right identifier'),
    ...code('lua', r'tests/rust-nav_spec.lua · lines 131-145', r'''
  it("fmt::Display (scoped path) and From<i32> (generic type) ask for the trait identifier", function()
    local function ask_at(fn_pat, trait_pat, word)
      local l = find(fn_pat)
      vim.api.nvim_win_set_cursor(0, { l + 1, 8 })
      local seen = stub_definition({ res = nil })
      nav.goto_super()
      H.eq("textDocument/definition", seen[1].method)
      local tl = find(trait_pat)
      local want = lines()[tl]:find(word, 1, true) - 1
      H.eq({ line = tl - 1, character = want }, seen[1].params.position, word)
    end
    ask_at("fn fmt(&self", "impl fmt::Display", "Display")
    ask_at("fn from(v", "impl From<i32>", "From")
    ask_at("fn area(&self) -> f64 {", "impl Shape for Square", "Shape")
  end)
'''),
    ...para('--', r'The server needs a position, and the position must be on the trait’s own name. The module '
        r'walks down from the trait node of the impl header until it reaches a type_identifier: '
        r'through a scoped_type_identifier by name for fmt::Display, through a generic_type by type '
        r'for From<i32>. The test runs three cases through one helper and asserts the request: the '
        r'method is textDocument/definition, and the position is the line of the impl header and '
        r'the character index of the bare word (Display, From, Shape) found in that line.'),
    ...para('--', r'The table of three is the point. A plain name works by accident in any implementation. '
        r'The two harder shapes are the ones where asking at the start of the node would land on '
        r'fmt, or on the angle brackets.'),
    ...sec(r'goto_super: where the cursor ends up'),
    ...para('--', r'The server is replaced by a location in a generated 150-line file whose trait is at line '
        r'100. The cursor must end on line 102, the line with fn area, the line must contain fn '
        r'area, and the window must be centred: winline within one row of half the window height. '
        r'That is the zz at the end of goto_super.'),
    ...code('lua', r'tests/rust-nav_spec.lua · lines 176-198', r'''
  it("a doc comment mentioning `fn area` before the method is skipped", function()
    local dir = H.tmpdir()
    local file = dir .. "/doc.rs"
    vim.fn.writefile({
      "pub trait Shape {",
      "    /// Call it as `fn area(&self)` to get the area.",
      "    /// See also fn area elsewhere.",
      "    fn area(&self) -> f64;",
      "}",
    }, file)
    local l = find("fn area(&self) -> f64 {")
    vim.api.nvim_win_set_cursor(0, { l + 1, 8 })
    stub_definition({
      res = { {
        uri = vim.uri_from_fname(file),
        range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 5 } },
      } },
    })
    nav.goto_super()
    H.eq(file, vim.api.nvim_buf_get_name(0))
    H.eq(4, vim.api.nvim_win_get_cursor(0)[1], "landed on the doc comment, not the method")
    vim.cmd("bwipeout!")
  end)
'''),
    ...para('--', r'Doc comments. In the generated file the words "fn area" appear in two doc comment lines '
        r'before the real declaration. A plain search lands on the first. The module searches again '
        r'while the current line looks like a comment, up to 50 times, and the test expects line 4.'),
    ...code('lua', r'tests/rust-nav_spec.lua · lines 200-216', r'''
  it("the doc-comment skip does not depend on a treesitter parser (field test: std's Display::fmt, `///` line)", function()
    local dir = H.tmpdir()
    local file = dir .. "/nots.rs"
    vim.fn.writefile({
      "pub trait Shape {",
      "    /// Formats like `fn area(&self)` does.",
      "    // fn area is also mentioned here",
      "    /* fn area */",
      "    fn area(&self) -> f64;",
      "}",
    }, file)
    local l = find("fn area(&self) -> f64 {")
    vim.api.nvim_win_set_cursor(0, { l + 1, 8 })
    -- a freshly shown buffer has no parser yet: get_node() gave nil and the first match stuck
    local orig_get_node = vim.treesitter.get_node
    stub(vim.treesitter, "get_node", function(...)
      if vim.api.nvim_buf_get_name(0) == file then
'''),
    ...para('--', r'The sibling test is named after the field test that found the bug. std’s Display::fmt has '
        r'a /// line mentioning fn fmt before the method. The first fix asked tree-sitter whether '
        r'the match was inside a comment, but a freshly shown buffer has no parser yet, so get_node '
        r'returned nil and the first match was always kept. The module now tests the line text '
        r'instead (a prefix of //, /* or *). To prove it, this test stubs vim.treesitter.get_node '
        r'to return nil for the file and uses three kinds of comment line, expecting line 5. The code carries the comment “by line text” for the same reason.'),
    ...sec(r'goto_super against a real server'),
    ...para('--', r'One test, the only real round trip: from the method in impl Shape for Square to fn area; '
        r'in the trait. The comment in it says the real server answers "not found" while the crate '
        r'loads, so the test asks again inside H.wait_for for up to 90 seconds, and each attempt '
        r'waits 1.5 seconds for the cursor to land on the trait line. It ends by matching the '
        r'current line. This is the check that the stubs have not drifted from what rust-analyzer '
        r'actually returns.'),
    ...sec(r'local_usages'),
    ...code('lua', r'tests/rust-nav_spec.lua · lines 248-266', r'''
  describe("local_usages", function()
    local function range(l, c)
      return { start = { line = l, character = c }, ["end"] = { line = l, character = c + 1 } }
    end

    it("quickfix 'usages (this file)' with [R]/[W]/[T], sorted by line, copen", function()
      local l = find("let total")
      vim.api.nvim_win_set_cursor(0, { l, 8 })
      stub_definition({
        res = {
          { range = range(l + 1, 28), kind = 2 }, -- read: println line
          { range = range(l - 1, 8), kind = 3 }, -- write: the let
          { range = range(l, 5), kind = 1 }, -- text (name_wrdx line)
        },
      })
      vim.fn.setqflist({}, "r")
      nav.local_usages()
      local qf = vim.fn.getqflist({ title = true, items = true })
      H.eq("usages (this file)", qf.title)
'''),
    ...para('--', r'The stubbed reply contains three highlights out of order, with kinds 2 (read), 3 (write), '
        r'1 (text). The quickfix title must be usages (this file); the three items must be sorted '
        r'by line, which gives write first, text second, read third; their texts must begin with '
        r'the labels [W], [T] and [R] and the trimmed source line; the buffer number must be the '
        r'nav buffer and the first column 9 (0-based 8 plus one).'),
    ...code('lua', r'tests/rust-nav_spec.lua · lines 289-299', r'''
    it("no usages: INFO 'no usages in this file', no quickfix", function()
      local n = notifications()
      vim.fn.setqflist({}, "r")
      for _, res in ipairs({ {}, false }) do
        n[1] = nil
        stub_definition({ res = res })
        nav.local_usages()
        H.eq({ { msg = "no usages in this file", level = vim.log.levels.INFO } }, n)
      end
      H.eq(0, #vim.fn.getqflist())
    end)
'''),
    ...para('--', r'A highlight without a kind is labelled [W], not [T]. rust-analyzer sends no kind for the '
        r'declaration in let x, and the comment says that is a write. The default in the module is '
        r'kind[h.kind or 3]. The same test closes by checking that copen opened a quickfix window.'),
    ...para('--', r'Empty means informational, not a warning: both {} and false give INFO no usages in this '
        r'file and leave the quickfix list empty. n[1] = nil clears the capture between the two '
        r'cases.'),
    ...para('--', r'The real-server test waits up to 60 seconds for a quickfix with the right title and '
        r'expects exactly two items for total, each labelled [T], [R] or [W], the second one a read '
        r'in the println line. The pattern is deliberately loose for the first, since the label of '
        r'a declaration is the server’s business; only the usage must be [R].'),
    ...sec(r'design decisions'),
    ...pt('--', r'stubs where there is a rule, a real server where there is a contract', r'the cursor, the labels and the sorting are the plugin’s own rules and run with canned '
        r'replies in milliseconds. One test per feature keeps the contract with the server honest.'),
    ...pt('--', r'every test checks the notification list whole', r'the count of messages is part of the behaviour.'),
    ...pt('--', r'the state is repaired after each test', r'a shared session is fast (rust-analyzer starts once) and the price is the after_each that '
        r'restores buffer, windows, stubs and quickfix.'),
    ...sec(r'a stale comment'),
    ...para('--', r'Line 2 of the file says the shared session is on tests/fixtures/keymaps-rust-crate. That '
        r'is the name from xynovim. The fixture this repository ships and the spec opens is '
        r'tests/fixtures/nav-crate. The behaviour is right; only the comment is out of date.'),
    ...sec(r'history'),
    ...pt('--', r'b2fee5c, 2026-10-13', r'xynovim: the tests exist as blocks of tests/keymaps-rust_spec.lua, driving the code '
        r'through the <leader>ru and <leader>rl mappings.'),
    ...pt('--', r'98c9bb4, 2026-10-13', r'goto_super: a definition reply of {} no longer counts as a hit, and doc comments that '
        r'mention fn name are skipped using tree-sitter.'),
    ...pt('--', r'a3d33c8, 2026-10-13', r'the skip is rewritten to read the line text, because the freshly shown buffer had no '
        r'parser (the stub of get_node in this file reproduces that).'),
    ...pt('--', r'f31e013, 2026-10-14', r'local_usages: a highlight without a kind is a write, [W], not text, [T].'),
    ...pt('--', r'7c1d2d9, 2026-10-22', r'this repository: the tests are split out of the keymap spec, call the module functions '
        r'directly, and use the nav-crate fixture.'),
  ],
);
