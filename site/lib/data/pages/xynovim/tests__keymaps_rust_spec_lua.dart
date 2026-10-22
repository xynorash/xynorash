import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/tests/keymaps-rust_spec.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'keymaps-rust_spec.lua — thirty-five numbered behaviours of the Rust key layer'),
    cm('--', r'one real rust-analyzer session shared by the whole file, and stubs of the editor API for everything that should not depend on its timing'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'spec for the Rust keys in lua/config/keymaps.lua, rust_assist.lua, rust_nav.lua and after/ftplugin/rust.lua'),
    kv(r'language', r'Lua spec, 1558 lines, 75 it() blocks, 11 describe() blocks'),
    kv(r'fixture', r'tests/fixtures/keymaps-rust-crate (its build artifacts were removed from the repo twice, in 670058d and cfe8c06)'),
    kv(r'real parts', r'rv, rh, rw, rT, ru and rl run against the real rust-analyzer; the rest is stubbed'),
    kv(r'history', r'9 commits, 2026-10-13 to 2026-10-14'),
    ...sec(r'why this file exists'),
    ...para('--', r'The leader r group is the interface to rust-analyzer: refactor actions, extract variable and function, inline, structural search and replace, join lines, open docs, explain error, workspace symbol search, toggling tests in references, jumping from a trait impl method to the trait, listing local usages. Every one of those is a thin function over a language server request, and each has quirks which were found in the field: SSR with no match must not raise a traceback, moveItem must not eat dollar signs, a doc comment before a method must not be mistaken for the method. The test names carry numbers from 1 to 35, the items of the checklist, and the file proves them one by one. The header explains the plan.'),
    ...code('lua', r'tests/keymaps-rust_spec.lua · lines 1-4', r'''
-- Rust keymaps (keymaps.lua), rust_assist.lua, rust_nav.lua, after/ftplugin/rust.lua.
-- One real rust-analyzer session on tests/fixtures/keymaps-rust-crate is shared by
-- the tests; the rest of the behaviour is checked with stubs of the editor API
-- (restored in after_each) so no test depends on rust-analyzer's timing.'''),
    ...sec(r'one session for the whole file'),
    ...para('--', r'Starting rust-analyzer for each test would make the file take minutes and the results depend on timing. The helper session() starts it once on the fixture, waits for the client, and waits until the scheduled maps exist (leader c R must have the description Rename File, which is the proof the attach block ran), then keeps the table S for every later test. The after_each puts the buffer back to its original content, so tests can edit it freely. A parse call at the start of each use makes sure the tree is current after the reset. Everything that does not need the real answer replaces the editor API with a stub for the duration of one test, restoring on after_each.'),
    ...code('lua', r'tests/keymaps-rust_spec.lua · lines 8-35', r'''
local undo = {}

--- Replace t[k] by v until after_each.
local function stub(t, k, v)
  local old = rawget(t, k)
  undo[#undo + 1] = function()
    rawset(t, k, old)
  end
  rawset(t, k, v)
end

local function session()
  H.need_rust()
  if S then
    vim.cmd("only")
    vim.api.nvim_set_current_buf(S.buf)
    -- the tree must follow the buffer reset of after_each (get_node does not reparse)
    vim.treesitter.get_parser(S.buf, "rust"):parse(true)
    return S
  end
  local dir, buf = H.open_fixture("keymaps-rust-crate")
  local client = H.wait_lsp("rust-analyzer", buf)
  H.wait_for(function()
    return vim.api.nvim_buf_call(buf, function()
      return vim.fn.maparg("<leader>cR", "n", false, true).desc == "Rename File"
        and vim.fn.maparg("<leader>ca", "n", false, true).desc ~= nil
    end)
  end, 15000, "the scheduled rust maps")'''),
    ...sec(r'stubs that read like a specification'),
    ...para('--', r'capture_rustlsp records calls of vim.cmd.RustLsp; capture_nvim_cmd intercepts the table form used by ssr and workspace symbols; answer_input answers vim.ui.input and records the prompt; notifications captures vim.notify and registers its own restore. With these a test can say what is sent and what is shown without a language server.'),
    ...code('lua', r'tests/keymaps-rust_spec.lua · lines 61-110', r'''
end
local function reset_buffer()
  if ORIGINAL then
    vim.api.nvim_buf_set_lines(S.buf, 0, -1, false, ORIGINAL)
    vim.bo[S.buf].modified = false
  end
end

--- Capture `vim.cmd.RustLsp(...)` calls.
local function capture_rustlsp()
  local calls = {}
  stub(vim.cmd, "RustLsp", function(arg)
    calls[#calls + 1] = arg
  end)
  return calls
end

--- Capture `vim.api.nvim_cmd({cmd = "RustLsp", ...})` calls (ssr, workspaceSymbol).
local function capture_nvim_cmd()
  local calls = {}
  local orig = vim.api.nvim_cmd
  stub(vim.api, "nvim_cmd", function(c, o)
    if type(c) == "table" and c.cmd == "RustLsp" then
      calls[#calls + 1] = c
      return ""
    end
    return orig(c, o)
  end)
  return calls
end

local function notifications()
  local cap = H.capture_notify()
  undo[#undo + 1] = cap.restore
  return cap.list
end

--- Answer vim.ui.input with `answer`; records the prompt.
local function answer_input(answer)
  local seen = {}
  stub(vim.ui, "input", function(opts, cb)
    seen[#seen + 1] = opts.prompt
    cb(answer)
  end)
  return seen
end

after_each(function()
  for i = #undo, 1, -1 do
    pcall(undo[i])'''),
    ...sec(r'the attach block'),
    ...para('--', r'The first group tests how the maps arrive. There is exactly one LspAttach autocmd in the group xynovim_rust_keymaps; it acts only for rust-analyzer (bacon_ls and taplo get no maps); maps are set after vim.schedule, not synchronously; they are buffer-local, there is no global leader r a, and every map in normal and visual modes has a description. A map set for a buffer that was wiped before the schedule runs is skipped without error. The which-key group name rust is added buffer-locally under pcall.'),
    ...code('lua', r'tests/keymaps-rust_spec.lua · lines 146-180', r'''
  it("1. xynovim_rust_keymaps has an LspAttach autocmd", function()
    local acs = vim.api.nvim_get_autocmds({ group = "xynovim_rust_keymaps", event = "LspAttach" })
    H.eq(1, #acs)
  end)

  it("1. acts only for rust-analyzer (no maps for bacon_ls / taplo)", function()
    for _, name in ipairs({ "bacon_ls", "taplo" }) do
      local b = fake_attach(name)
      vim.wait(300, function()
        return false
      end)
      H.not_ok(has_map(b, "<leader>ra"), name .. " must not get the rust maps")
      H.not_ok(has_map(b, "<leader>cR"), name .. " must not get <leader>cR")
    end
  end)

  it("2. maps are set after vim.schedule, buffer-local, with a desc", function()
    local b = fake_attach("rust-analyzer")
    H.not_ok(has_map(b, "<leader>ra"), "not set synchronously")
    H.wait_for(function()
      return has_map(b, "<leader>ra")
    end, 2000, "scheduled maps")
    local m = vim.api.nvim_buf_call(b, function()
      return vim.fn.maparg("<leader>ra", "n", false, true)
    end)
    H.eq("Refactor actions", m.desc)
    local global = vim.fn.maparg("<leader>ra", "n", false, true)
    H.ok(global.buffer ~= 1, "no global <leader>ra")
    -- every rust map carries a description
    for _, mode in ipairs({ "n", "x" }) do
      for _, km in ipairs(vim.api.nvim_buf_get_keymap(b, mode)) do
        H.ok(km.desc and km.desc ~= "", "map without desc: " .. km.lhs)
      end
    end
  end)'''),
    ...sec(r'the actions'),
    ...para('--', r'Refactor actions (leader r a, normal and visual) call code_action with context.only set to refactor. Extract variable, function and constant filter by title and exist in both modes; extract module is visual only and matches Extract module; inline matches the title with ^Inline [^m] so that Inline macro is not picked. The visual map tests also check that the visual variant leaves visual mode and passes the marks of the selection.'),
    ...code('lua', r'tests/keymaps-rust_spec.lua · lines 305-317', r'''
  it("3. <leader>ra (n, x) calls code_action with context.only = {'refactor'}", function()
    local got
    stub(vim.lsp.buf, "code_action", function(o)
      got = o
    end)
    for _, mode in ipairs({ "n", "x" }) do
      got = nil
      local m = mp("<leader>ra", mode)
      H.eq("Refactor actions", m.desc)
      m.callback()
      H.eq({ "refactor" }, got.context.only)
    end
  end)'''),
    ...sec(r'SSR without tracebacks'),
    ...para('--', r'Structural search and replace asks for a query. An empty answer does nothing. A query without the ==>> separator produces a WARN that explains the pattern ==>> replacement form instead of a traceback from rustaceanvim: the test answers nonsense ==>, calls ra.ssr(), requires zero RustLsp calls, one notification at WARN and the expected wording. Two more tests with the real rust-analyzer check that a query it cannot parse gives a WARN and that a query that matches nothing says SSR: no matches.'),
    ...code('lua', r'tests/keymaps-rust_spec.lua · lines 438-448', r'''
  it("8. a query without `==>>` is refused with a notice instead of a rustaceanvim traceback", function()
    local ra = require("config.rust_assist")
    local calls = capture_nvim_cmd()
    local n = notifications()
    answer_input("nonsense ==>")
    ra.ssr()
    H.eq(0, #calls)
    H.eq(1, #n)
    H.eq(vim.log.levels.WARN, n[1].level)
    H.match(n[1].msg, "pattern ==>> replacement", true)
  end)'''),
    ...sec(r'moving an item as plain text'),
    ...para('--', r'Alt-j and Alt-k send experimental/moveItem. The language server answers with a snippet edit in which a dollar sign has a meaning. If the result was inserted through the snippet engine, a Rust macro pattern such as $e:expr would be expanded into nothing. The test stubs buf_request to answer with the text ($e:expr) => { $e + $e$0 }; and requires that the buffer keeps both dollar-e occurrences and removes only the final $0 marker, and that the requests sent were Down and Up. The unescaped answer is imitated from rust-analyzer; this was a field test finding (3f868dd, moveItem plain text).'),
    ...code('lua', r'tests/keymaps-rust_spec.lua · lines 557-577', r'''
  it("<A-j>/<A-k> send experimental/moveItem and apply the edits as plain text (`$e` is kept)", function()
    session()
    remember()
    local ra = require("rustaceanvim.rust_analyzer")
    local sent = {}
    stub(ra, "buf_request", function(_, method, params, handler)
      sent[#sent + 1] = { method, params.direction }
      -- unescaped snippet edit like rust-analyzer's: `$e` and the `$0` marker
      handler(nil, {
        { range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 3 } },
          newText = "($e:expr) => { $e + $e$0 };", insertTextFormat = 2 },
      }, { bufnr = S.buf, client_id = S.client.id })
    end)
    vim.api.nvim_buf_set_lines(S.buf, 0, -1, false, { "aaa", "bbb" })
    mp("<A-j>").callback()
    H.eq("($e:expr) => { $e + $e };", lines()[1])
    H.eq("bbb", lines()[2])
    mp("<A-k>").callback()
    H.eq({ { "experimental/moveItem", "Down" }, { "experimental/moveItem", "Up" } }, sent)
    reset_buffer()
  end)'''),
    ...sec(r'rust_assist and rust_nav'),
    ...para('--', r'rust_assist covers the syntax tree viewer (pretty-printed JSON with sorted keys, a nomodifiable scratch buffer, q closes the split, an older plain-text answer shown with the rust filetype, an error answer notifying with ERROR), open docs (local docs file preferred, then the web URL, otherwise INFO), explain error (the E-code from d.code or from the message, with a failing rustc --explain producing ERROR), and workspace symbol (asks once, searches the first word and says so). The excludeTests toggle test proves with the real server that references of used go from 2 to 3 when tests are included.'),
    ...para('--', r'rust_nav jumps from a trait impl method to the trait definition. Its tests are mostly warnings: outside a function, in a plain impl, and when no definition is found; fmt::Display and From<i32> ask for the trait identifier; the cursor lands on fn area and is centred; a doc comment mentioning fn area before the method is skipped, and the skip does not depend on a treesitter parser (field test: the std Display fmt, a /// line). The first of these is typical: it puts the cursor on a use line and requires exactly one WARN, not inside a function.'),
    ...code('lua', r'tests/keymaps-rust_spec.lua · lines 1115-1121', r'''
  it("21. outside a function: WARN 'not inside a function'", function()
    local n = notifications()
    find("use std::fmt")
    mp("<leader>ru").callback()
    H.eq({ { msg = "not inside a function", level = vim.log.levels.WARN } }, n)
  end)
'''),
    ...sec(r'the quote that pairs wrongly'),
    ...para('--', r'In Rust an apostrophe is often a lifetime. The ftplugin makes the insert-mode apostrophe a plain quote, buffer-local. The test types x: &’a str and then a changed line x: Foo<’b> and requires the exact text each time, so no stray closing quote is left behind by mini.pairs. A related test covers the double quote after an odd number of backslashes. Spell checking is limited to comments through the highlights query, the shipped spellfile contains Rust words like Vec, tokio, usize and impl, and the apostrophe map exists only in Rust buffers.'),
    ...code('lua', r'tests/keymaps-rust_spec.lua · lines 1408-1414', r'''
  it("29. typing &'a str leaves no stray closing quote", function()
    local buf = scratch("rust")
    H.feed("ix: &'a str<Esc>")
    H.eq("x: &'a str", vim.api.nvim_buf_get_lines(buf, 0, -1, false)[1])
    H.feed("ccx: Foo<'b><Esc>")
    H.eq("x: Foo<'b>", vim.api.nvim_buf_get_lines(buf, 0, -1, false)[1])
  end)'''),
    ...sec(r'history'),
    blank,
    ...pt('--', r'b2fee5c (2026-10-13)', r'created.'),
    ...pt('--', r'98c9bb4, a3d33c8, 3f868dd (2026-10-13)', r'final loop rounds 1 to 3.'),
    ...pt('--', r'f31e013, 25086fd (2026-10-14)', r'rounds 4 and 5, among them "rl label" and "escaped quote pairing" and "Rust spellfile".'),
    ...pt('--', r'fc2062a, 0b0eee8, b9363cd (2026-10-14)', r'CI, README and the macros and dependencies work, which touched the key lists.'),
  ],
);
