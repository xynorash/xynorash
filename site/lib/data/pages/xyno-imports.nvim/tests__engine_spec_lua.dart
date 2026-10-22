import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-imports.nvim/tests/engine_spec.lua',
  lines: [
    cm(r'''--''', r'''──────────────────────────────────────────'''),
    cm(r'''--''', r'''engine_spec.lua — 46 cases from arithmetic to a real rust-analyzer'''),
    cm(r'''--''', r'''pure functions, a fake language server, then the real one'''),
    cm(r'''--''', r'''──────────────────────────────────────────'''),
    blank,
    kv(r'''role''', r'''specs of engine.lua: ranking, memory, scanning, the whole flow'''),
    kv(r'''language''', r'''Lua, run by tests/run.lua with the tiny harness'''),
    kv(r'''size''', r'''820 lines, 46 test cases in 10 describe blocks'''),
    kv(r'''layers''', r'''table-driven pure, temp-file memory, buffers, fake server, real server'''),
    kv(r'''skips''', r'''tree-sitter parser, rust-analyzer, cargo and the registry crates, each with a printed reason'''),
    ...sec(r'''why this file exists'''),
    ...para(r'''--''', r'''The engine is almost entirely asynchronous editor glue, and the failure modes are the kind you only see on a slow day: a name imported twice, an import landing on the wrong line, a prompt over text you are typing. The spec is layered so that most of the engine is tested without a language server and the parts that need one are tested against both a stand-in and the real thing. The header lists the layers in order of cost.'''),
    blank,
    ...code('lua', r'tests/engine_spec.lua · lines 1-5', r'''
-- xyno_imports.engine: pure scoring/decision/parsing (table driven, no
-- server), the project memory (temp state file), the scan and the auto-import
-- flow against a FAKE rust-analyzer client (hermetic), and the acceptance
-- cases against the real rust-analyzer on the deps-lab fixture (skipped
-- without rust-analyzer, cargo or the registry crates).'''),

    ...para(r'''--''', r'''The spec came from xynovim, where it was tests/import-engine_spec.lua (816 lines, five commits from b9363cd to d3e1442). Here it is 820 lines, in 45d98cb on 2026-10-22, with the requires renamed and the xyno_rust modules in place of config.*.'''),
    blank,
    ...sec(r'''setup and teardown: leave nothing behind'''),
    ...para(r'''--''', r'''One spec file runs in one Neovim, so state leaks between tests unless it is cleaned. stub() replaces a field of a table and records the way back; after_each walks the list in reverse and restores. The state file points at a temp directory, memory is reloaded, the debounce and mode are put back, buffers are wiped, and every LSP client is stopped, with a comment giving the reason: one rust-analyzer per real-server test would pile up.'''),
    blank,
    ...code('lua', r'tests/engine_spec.lua · lines 11-11, 23-26, 28-41', r'''
local restores = {}
...
before_each(function()
  stub(E, "state_file", H.tmpdir() .. "/state/imports.json")
  E.reload_memory()
end)
...
after_each(function()
  for i = #restores, 1, -1 do
    pcall(restores[i])
  end
  restores = {}
  E.reload_memory()
  E.config.debounce = saved_debounce
  vim.g.xyno_auto_import = saved_mode
  pcall(vim.cmd, "silent! %bwipeout!")
  -- one rust-analyzer per real-server test: stop it so they do not pile up
  for _, c in ipairs(vim.lsp.get_clients()) do
    pcall(c.stop, c, true)
  end
end)'''),

    ...sec(r'''scoring as a table of expectations'''),
    ...para(r'''--''', r'''The first layers are pure. The scoring block builds a list of Error candidates from five crates and ranks them under different facts, each test naming a rule. It does not assert numbers except where the number is the point. The one that is the point: a use of std::io::Read and std::io::Write in the file gives std::io::Error exactly 2 * 4 * 0.5, two uses of the same module at the file weight and the near factor. Note the test asserts the arithmetic as an expression, so the weights it depends on are visible.'''),
    blank,
    ...code('lua', r'tests/engine_spec.lua · lines 104-108, 127-132', r'''
  it("ranks the derive macro of a proc-macro crate first inside #[derive(", function()
    local ranked = E.rank(ERR, { ctx = { derive = true }, dep_index = deps, proc_macro = { thiserror = true } })
    H.eq("thiserror::Error", ranked[1].path)
    H.match(table.concat(ranked[1].why, ";"), "derive macro", true)
  end)
...
  it("counts uses of the same module as weaker evidence", function()
    local ranked = E.rank(cands("std::io::Error", "std::fmt::Error"), { uses = { file = { "std::io::Read", "std::io::Write" } } })
    H.eq("std::io::Error", ranked[1].path)
    local score = ranked[1].score
    H.eq(2 * 4 * 0.5, score)
  end)'''),

    ...para(r'''--''', r'''The test "weights use in this file over siblings over the crate" is a four-line table of facts with the intended winner written in the failure message ("2x crate (4) beats 1x sibling (3)"). That is the technique throughout: when the asserted outcome is the result of an arithmetic comparison, the message states the arithmetic. A failing run explains itself.'''),
    blank,
    ...para(r'''--''', r'''Two cases guard determinism rather than preference: ties break by dependency order and then by path, and candidates that need a new crate rank last with the reason "not a dependency yet" in their reasons. The picker prints those reasons, so the test is also a test of what the user reads.'''),
    blank,
    ...sec(r'''the memory spec: defensive by example'''),
    ...para(r'''--''', r'''Four cases: a choice survives a restart (simulated by reload_memory, which forgets the in-memory copy and reads the file again), forget removes one name or a project and returns the count, a name or path that is not a plain identifier is refused both on the way in and on the way back from disk, and a corrupt state file is survivable. The refusal case writes a file containing "x::Bad; rm -rf" and a name with a space and then asserts that only the good entry comes back.'''),
    blank,
    ...sec(r'''scanners on real buffers'''),
    ...para(r'''--''', r'''From here every test calls need_ts(), which skips with "tree-sitter rust parser not installed" when the parser is missing. rust_buffer() writes a path-only crate into a temp directory and opens it, so cm.root finds a real Cargo.toml. The scan case packs the rules into one buffer: a use line, a local struct, a generic parameter, a prelude type and two unknown names, and expects exactly HashMap and Instant, at the exact row and column of HashMap. Separate cases pin the max_lines guard, derive names (Serialize is found, Debug and the qualified serde::Deserialize are not), macro definitions, and diagnostics from either tier.'''),
    blank,
    ...code('lua', r'tests/engine_spec.lua · lines 256-270, 289-299', r'''
  it("finds names nothing declares or imports, not generics, prelude, locals or use lines", function()
    need_ts()
    local buf = rust_buffer({
      "use std::fmt::Display;",
      "struct Local;",
      "fn f<T: Clone>(x: T, h: HashMap<u8, Local>) -> Option<Display> {",
      "    let _ = Instant::now();",
      "    None",
      "}",
    })
    local found = E.scan_syntax(buf, 0, 5)
    H.eq({ "HashMap", "Instant" }, names(found))
    H.eq(2, found[1].row)
    H.eq(#"fn f<T: Clone>(x: T, h: ", found[1].col)
  end)
...
  it("ignores names inside a macro definition", function()
    need_ts()
    local buf = rust_buffer({
      "macro_rules! make {",
      "    () => { let _x: Widget = Widget::new(); };",
      "}",
      "fn f() { let _y: Gadget; }",
    })
    local found = E.unresolved(buf, 0, 3)
    H.eq({ "Gadget" }, names(found))
  end)'''),

    ...para(r'''--''', r'''The diagnostic case creates a vim.diagnostic by hand with a message of the failed-to-resolve kind and then a second diagnostic reading "unresolved import" to prove that one is excluded. The scanner is tested against messages, not against a server, which keeps this layer deterministic.'''),
    blank,
    ...sec(r'''a fake rust-analyzer'''),
    ...para(r'''--''', r'''The flow tests need a language server that answers code action requests, but starting a real one costs seconds and needs a toolchain. fake_server stubs the clients function with a table that looks like a client: its request method reads the name under the requested range and answers with Import titles and a workspace edit that inserts the use line at 0:0. It returns a counter, so tests can assert that no request was even sent. This is the most reusable idea in the file.'''),
    blank,
    ...code('lua', r'tests/engine_spec.lua · lines 356-389', r'''
local function fake_server(buf, answers)
  local seen = { requests = 0 }
  local client = {
    id = 4242,
    name = "rust-analyzer",
    offset_encoding = "utf-16",
    request = function(_, method, params, cb)
      seen.requests = seen.requests + 1
      local line = vim.api.nvim_buf_get_lines(buf, params.range.start.line, params.range.start.line + 1, false)[1] or ""
      local name = line:sub(params.range.start.character + 1, params.range["end"].character)
      local result = {}
      for _, path in ipairs(answers[name] or {}) do
        result[#result + 1] = {
          title = "Import `" .. path .. "`",
          kind = "quickfix",
          edit = {
            changes = {
              [vim.uri_from_bufnr(buf)] = {
                { range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 0 } }, newText = "use " .. path .. ";\n" },
              },
            },
          },
        }
      end
      vim.schedule(function()
        cb(nil, result)
      end)
    end,
  }
  stub(ca, "clients", function()
    return { client }
  end)
  return seen
end'''),

    ...para(r'''--''', r'''run_sync wraps the asynchronous run with a done callback and H.wait_for, so a test can read like straight-line code and fail with a timeout message ("import run") instead of hanging.'''),
    blank,
    ...sec(r'''the flow cases'''),
    ...para(r'''--''', r'''The single-mode cases pin the contract in the README: one candidate is imported in one undo step with a one-line note; several imports of one run share a single undo step; an ambiguous name is left alone; a remembered choice resolves the ambiguity; mode off, a non-modifiable buffer and a macro definition send no request at all.'''),
    blank,
    ...code('lua', r'tests/engine_spec.lua · lines 412-426, 443-450', r'''
  it("'single' imports the one candidate: one undo step, a one-line note", function()
    need_ts()
    local buf = rust_buffer(SRC)
    fake_server(buf, { Serializer = { "serde::Serializer" } })
    local cap = H.capture_notify()
    local before = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local n = run_sync(buf, 0, 2, { mode = "single" })
    H.eq(1, n)
    H.eq("use serde::Serializer;", vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1])
    H.eq("imported serde::Serializer", cap.list[#cap.list].msg)
    vim.api.nvim_buf_call(buf, function()
      vim.cmd("silent undo")
    end)
    H.eq(before, vim.api.nvim_buf_get_lines(buf, 0, -1, false), "one undo restores the buffer")
  end)
...
  it("leaves an ambiguous name alone, in 'single' mode", function()
    need_ts()
    local buf = rust_buffer(SRC)
    fake_server(buf, { Serializer = { "serde::Serializer", "other::Serializer" } })
    local before = text(buf)
    H.eq(0, run_sync(buf, 0, 2, { mode = "single" }))
    H.eq(before, text(buf))
  end)'''),

    ...para(r'''--''', r'''The ask cases are about manners. The prompt is stubbed through E.ask_key, the seam the engine leaves for specs. A no is cached: the second run does not prompt again. A different project key accepts. And outside the current buffer in normal mode it never prompts: the test opens another buffer with enew and asserts that the prompt was never called.'''),
    blank,
    ...code('lua', r'tests/engine_spec.lua · lines 478-497', r'''
  it("'ask' prompts, applies on yes, and a dismissal is cached for the session", function()
    need_ts()
    local buf = rust_buffer(SRC)
    fake_server(buf, { Serializer = { "serde::Serializer" } })
    local asked = {}
    stub(E, "ask_key", function(cand)
      asked[#asked + 1] = cand.path
      return #asked > 1
    end)
    local before = text(buf)
    H.eq(0, run_sync(buf, 0, 2, { mode = "ask" }))
    H.eq(before, text(buf), "dismissed: nothing changed")
    H.eq(0, run_sync(buf, 0, 2, { mode = "ask" }))
    H.eq(1, #asked, "the dismissal is cached, no second prompt")
    -- a fresh project key (forget does not exist for dismissals of other roots): accept path
    local buf2 = rust_buffer({ "fn main() {", "    let _s: Other = make();", "}" })
    fake_server(buf2, { Other = { "x::Other" } })
    H.eq(1, run_sync(buf2, 0, 2, { mode = "ask" }))
    H.match(text(buf2), "use x::Other;", true)
  end)'''),

    ...para(r'''--''', r'''The trigger case drives the real autocommands: it sets a short debounce, calls setup, simulates typing by setting a line and firing InsertLeave, waits for the use line to appear, undoes, fires TextChanged, waits 800 ms and asserts the import did not come back. That is the undo guard, tested by its symptom. It is also the one case marked with H.known_issue for macOS, with the CI run number and the timing in the reason.'''),
    blank,
    ...sec(r'''resolve, sources and the picker'''),
    ...para(r'''--''', r'''The sources case registers a source that returns a crate-adding candidate and a malformed path ("bad path;"), resolves, and checks that the server candidates rank first, the crate-adding one last, the malformed one is gone, and the result is not unambiguous. After a remembered choice the result is unambiguous with y::Rng. After unregistering, two candidates remain, and a non-identifier name yields an empty list. One test covers register, validate, rank, remember and unregister.'''),
    blank,
    ...para(r'''--''', r'''The picker case stubs E.select, the second seam, and picks the second item. It asserts that y::Rng is listed first because the file already uses a sibling of it (y::Other), that the formatted item shows the reasons, and that the picked x::Rng was applied and remembered with a one-line note.'''),
    blank,
    ...sec(r'''the real server'''),
    ...para(r'''--''', r'''The last describe blocks run against rust-analyzer on tests/fixtures/deps-lab, a small binary crate with anyhow, clap, serde, serde_json, thiserror and tokio. lab() skips unless Rust is available and cargo metadata works offline, then starts the server and waits for it. set_and_wait() edits the buffer and waits until rust-analyzer actually offers the wanted import, which removes the race between the edit and the server noticing it.'''),
    blank,
    ...para(r'''--''', r'''The cases are the acceptance tests of the README. Single mode imports Serialize, merged into the existing use serde::{Deserialize, Serialize};, leaves the ambiguous Error alone, and one undo restores the buffer. thiserror::Error ranks first inside #[derive( and std::io::Error for a function returning std::io::Result, with return type in the reasons. A remembered choice survives a restart and then single applies it. Organize turns scattered use lines into use std::{fmt, io::{Read, Write}}; drops an unused HashMap and undoes in one step. And a paste imports HashMap.'''),
    blank,
    ...sec(r'''a regression test with a story'''),
    ...para(r'''--''', r'''The final describe block is called import engine review fixes. Its second case builds six Error candidates, remembers the fifth, shows the picker and checks that the remembered one is first and the rest keep ranked order, comparing against an independent resolve with the remembered candidate filtered out. It exists because of the LuaJIT sort bug described in 19f974c; with the old comparator the rest came out scrambled.'''),
    blank,
    ...code('lua', r'tests/engine_spec.lua · lines 780-783', r'''
  it("the default ask_key never blocks without a UI", function()
    H.eq(0, #vim.api.nvim_list_uis())
    H.eq(false, E.ask_key({ path = "serde::Serialize" }, "Serialize"))
  end)'''),

    ...para(r'''--''', r'''The first case there is the other half of that commit: with no UI attached, ask_key must return false instead of waiting for a key nobody can press.'''),
    blank,
    ...sec(r'''limits'''),
    ...pt(r'''--''', r'''Fake server edits at 0:0''', r'''the stand-in always inserts at the top of the file. Merging into an existing group is rust-analyzer behaviour and is only covered by the real-server cases.'''),
    ...pt(r'''--''', r'''Timing''', r'''several waits are generous (15 to 120 seconds); the 120-second waits are in the real-server cases.'''),
    ...pt(r'''--''', r'''No Windows or macOS evidence here''', r'''the OS notes in the README quote xynovim CI runs, not this repository.'''),
    ...sec(r'''history'''),
    ...pt(r'''--''', r'''b9363cd 2026-10-14''', r'''original spec enters xynovim with the engine.'''),
    ...pt(r'''--''', r'''19f974c, b474307 2026-10-15''', r'''review and field-test fixes add the regression cases.'''),
    ...pt(r'''--''', r'''9641d08, d3e1442 2026-10-16 and 10-21''', r'''Windows and macOS fixes and the known-issue skips.'''),
    ...pt(r'''--''', r'''45d98cb 2026-10-22''', r'''added here, 820 lines.'''),
  ],
);
