import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/tests/import-engine_spec.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'import-engine_spec.lua — missing imports fixed by ranking, with a memory and an undo step'),
    cm('--', r'scoring, decisions and memory as pure tables; the editor flow against a fake rust-analyzer; acceptance on the real one'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'spec for lua/config/import_engine.lua, the engine behind auto-import, :ImportName and organize-imports'),
    kv(r'language', r'Lua spec, 816 lines, 46 it() blocks, 10 describe() blocks, 400 second timeout'),
    kv(r'layers', r'pure functions, project memory in a temp state file, scan and flow against a fake client, real rust-analyzer on deps-lab'),
    kv(r'history', r'5 commits, 2026-10-14 to 2026-10-21'),
    ...sec(r'why this file exists'),
    ...para('--', r'Rust has many items with the same name: Error is in std::io, std::fmt, std::error, anyhow and thiserror. Plain rust-analyzer offers all of them as separate import actions and you pick. The import engine goes further: it ranks the candidates using the evidence of the project, decides whether to import automatically, asks when it is not sure, remembers what you chose for this project and name, and applies several imports as a single undo step. A feature that edits your code on its own needs strict tests of the rule that it must not guess. This spec is built in four layers so that most of the logic is tested without any server. The header lists them.'),
    ...code('lua', r'tests/import-engine_spec.lua · lines 1-6', r'''
-- xyno-timeout: 400
-- config.import_engine: pure scoring/decision/parsing (table driven, no
-- server), the project memory (temp state file), the scan and the auto-import
-- flow against a FAKE rust-analyzer client (hermetic), and the acceptance
-- cases against the real rust-analyzer on the deps-lab fixture (skipped
-- without rust-analyzer, cargo or the registry crates).'''),
    ...sec(r'the timeout line'),
    ...para('--', r'The very first line is -- xyno-timeout: 400. scripts/test.sh reads such a line from the first 15 lines of a spec and uses it instead of the default 120 seconds, so a spec with a slow layer, here the real rust-analyzer, can say so itself without raising the limit for the whole suite.'),
    ...code('lua', r'tests/import-engine_spec.lua · lines 1-1', r'''
-- xyno-timeout: 400'''),
    ...sec(r'ranking by evidence'),
    ...para('--', r'The scoring tests build candidates from path strings and compare the order. Inside #[derive( the derive macro of a proc-macro crate wins, so thiserror::Error is first, and the reasons list mentions derive macro. A use in this file outweighs a use in siblings, which outweighs a use in the crate; the test spells the arithmetic out in its messages: two uses in the crate (4) beat one in a sibling (3), and a file use (4) loses against two sibling uses (6). Trait positions prefer traits. Standard-library items that a dependency shadows, and core twins of std, are penalised: with anyhow in the dependencies the order is anyhow::Error, std::error::Error, core::error::Error. Ties are broken by dependency order and then by path, and candidates that need a new crate come last.'),
    ...code('lua', r'tests/import-engine_spec.lua · lines 97-122, 139-142', r'''
describe("scoring", function()
  local ERR = cands("std::error::Error", "std::fmt::Error", "std::io::Error", "thiserror::Error", "anyhow::Error")
  local deps = { anyhow = 1, thiserror = 2 }

  it("ranks the derive macro of a proc-macro crate first inside #[derive(", function()
    local ranked = E.rank(ERR, { ctx = { derive = true }, dep_index = deps, proc_macro = { thiserror = true } })
    H.eq("thiserror::Error", ranked[1].path)
    H.match(table.concat(ranked[1].why, ";"), "derive macro", true)
  end)

  it("ranks std::io::Error first for a fn returning io::Result", function()
    local ctx = E.parse_return("io::Result<()>")
    local ranked = E.rank(ERR, { ctx = { error = true, ret = ctx }, dep_index = deps })
    H.eq("std::io::Error", ranked[1].path)
  end)

  it("weights use in this file over siblings over the crate", function()
    local a, b = unpack(cands("x::Thing", "y::Thing"))
    local function best(uses)
      return E.rank({ a, b }, { uses = uses })[1].path
    end
    H.eq("y::Thing", best({ file = { "y::Thing" } }))
    H.eq("x::Thing", best({ crate = { "x::Thing", "x::Thing" }, sibling = { "y::Thing" } }), "2x crate (4) beats 1x sibling (3)")
    H.eq("y::Thing", best({ crate = { "x::Thing" }, sibling = { "y::Thing" } }))
    H.eq("x::Thing", best({ file = { "y::Thing" }, sibling = { "x::Thing", "x::Thing" } }), "file 4 vs sibling 6: sibling wins")
  end)
...
  it("penalises std items a dependency shadows, and core twins of std", function()
    local ranked = E.rank(cands("std::error::Error", "anyhow::Error", "core::error::Error"), { dep_index = { anyhow = 1 } })
    H.eq({ "anyhow::Error", "std::error::Error", "core::error::Error" }, paths(ranked))
  end)'''),
    ...sec(r'decisions: never guess'),
    ...para('--', r'decide(mode, candidates, remembered) returns an action. The tests state the policy. One candidate in single mode applies; in ask mode it asks; when off it does nothing. Several candidates in single mode never guess: the action is pick, and no candidates is none. A remembered choice wins over ambiguity, but only if it is still offered; if the remembered path is gone, the engine falls back to pick; and in ask mode a memory still asks. A candidate that needs a new crate is never taken automatically.'),
    ...code('lua', r'tests/import-engine_spec.lua · lines 160-183', r'''
describe("decisions", function()
  local one = cands("serde::Serialize")
  local many = cands("std::fmt::Error", "std::io::Error")
  it("takes a single candidate in 'single' mode, asks in 'ask', does nothing when off", function()
    H.eq("apply", E.decide("single", one).act)
    H.eq("ask", E.decide("ask", one).act)
    H.eq("off", E.decide("off", one).act)
  end)
  it("never guesses between several candidates", function()
    H.eq("pick", E.decide("single", many).act)
    H.eq("none", E.decide("single", {}).act)
  end)
  it("lets a remembered choice win over ambiguity, only if it is still offered", function()
    local d = E.decide("single", many, "std::io::Error")
    H.eq("apply", d.act)
    H.eq("std::io::Error", d.cand.path)
    H.eq("pick", E.decide("single", many, "gone::Error").act)
    H.eq("ask", E.decide("ask", many, "std::io::Error").act)
  end)
  it("does not take a crate-adding candidate automatically", function()
    local c = cands("rand::Rng")
    c[1].add_crate = true
    H.eq("pick", E.decide("single", c).act)
  end)'''),
    ...sec(r'memory that survives and tolerates corruption'),
    ...para('--', r'Choices are stored per project and name in a state file, which the spec redirects to a temp directory in a before_each. They persist, survive a restart (reload_memory re-reads the file), can be forgotten per name or per project, and are refused when the names or paths are not plain identifiers, also when they come from the file. A corrupt state file must not break the engine: the test writes not json, reloads, expects no memory and expects a new remember to succeed.'),
    ...code('lua', r'tests/import-engine_spec.lua · lines 224-229', r'''
  it("survives a corrupt state file", function()
    write(E.state_file, "{not json")
    E.reload_memory()
    H.is_nil(E.remembered("/p", "A"))
    H.ok(E.remember("/p", "A", "x::A"))
  end)'''),
    ...sec(r'the scan finds names nothing declares'),
    ...para('--', r'The syntax scan reads the buffer with treesitter and finds the names that nothing declares or imports, skipping generics, the prelude, locals and use lines. It skips buffers above max_lines, since whole-buffer reads on each edit freeze huge files. It finds names inside #[derive(...)], but not prelude derives or qualified ones, ignores macro definitions, and can use the unresolved-name diagnostics of either tier.'),
    ...sec(r'the flow against a fake rust-analyzer'),
    ...para('--', r'fake_server replaces the code-action source for a buffer with a table of name to candidate paths. The first test imports Serializer in single mode, checks that the first line is use serde::Serializer;, that exactly one note imported serde::Serializer was shown, and that one undo restores the original buffer. The second joins two imports of one run into one undo step. In the excerpt the buffer is the whole fixture, so the comparison before and after undo covers every line.'),
    ...code('lua', r'tests/import-engine_spec.lua · lines 411-440', r'''
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

  it("joins several imports of one run into one undo step", function()
    need_ts()
    local buf = rust_buffer({ "fn main() {", "    let _a: Alpha = x();", "    let _b: Beta = y();", "}" })
    fake_server(buf, { Alpha = { "one::Alpha" }, Beta = { "two::Beta" } })
    local before = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    H.eq(2, run_sync(buf, 0, 3, { mode = "single" }))
    local t = text(buf)
    H.match(t, "use one::Alpha;", true)
    H.match(t, "use two::Beta;", true)
    vim.api.nvim_buf_call(buf, function()
      vim.cmd("silent undo")
    end)
    H.eq(before, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
  end)'''),
    ...sec(r'triggers'),
    ...para('--', r'The auto-import triggers after InsertLeave and a save, debounced, and not again after an undo. The test sets the mode to single, shortens the debounce to 80 ms, simulates typing, fires InsertLeave, waits up to 15 seconds for the first line to become the import, undoes and runs TextChanged, waits 800 ms and requires that the import is not redone. The undone import must stay undone, otherwise the engine would fight the user. This test is a known issue on macOS, with the run number and the 17 second timeout in the reason.'),
    ...code('lua', r'tests/import-engine_spec.lua · lines 512-533', r'''
  it("triggers after InsertLeave and a save, debounced, and not again after an undo", function()
    H.known_issue({ "macos" }, "timing on the macos-latest runner (run 39647013043: auto import after InsertLeave timed out at 17 s; passes on Linux and Windows)")
    need_ts()
    vim.g.xynovim_auto_import = "single"
    E.config.debounce = 80
    H.very_lazy() -- setup() of the engine (autocmds)
    local buf = rust_buffer(SRC)
    fake_server(buf, { Serializer = { "serde::Serializer" } })
    -- the buffer was just loaded: simulate typing the line
    vim.api.nvim_buf_set_lines(buf, 1, 2, false, { "    let _s: Serializer = make();" })
    vim.api.nvim_exec_autocmds("InsertLeave", { buffer = buf })
    H.wait_for(function()
      return vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] == "use serde::Serializer;"
    end, 15000, "auto import after InsertLeave")
    -- undo: the name must not come back by itself
    vim.api.nvim_buf_call(buf, function()
      vim.cmd("silent undo")
      vim.cmd("doautocmd TextChanged")
    end)
    vim.wait(800)
    H.ok(not text(buf):find("use serde::Serializer;", 1, true), "an undone import is not redone")
  end)'''),
    ...sec(r'the real rust-analyzer'),
    ...para('--', r'The acceptance block opens deps-lab. The scenario for single mode: remove the import of Serialize, add a free-standing function returning Result<(), Error>, wait for rust-analyzer to show the diagnostic and then run the engine. It must import exactly one name, Serialize, which rust-analyzer merges into the existing use serde::Deserialize line as use serde::{Deserialize, Serialize};, leave Error alone because it is ambiguous, say imported serde::Serialize, and undo in one step. Another test shows the memory: without it the ambiguous Error is not touched; after E.remember(root, Error, std::io::Error) and a reload of the memory file, single mode applies use std::io::Error;.'),
    ...code('lua', r'tests/import-engine_spec.lua · lines 669-693, 712-727', r'''
  it("'single' imports Serialize, leaves Error alone, in one undo step", function()
    local _, buf = lab()
    local lines = lab_lines()
    -- Serialize is no longer imported; a free-standing `Error` is ambiguous
    lines[2] = "use serde::Deserialize;"
    vim.list_extend(lines, { "", "fn lonely() -> Result<(), Error> {", "    Ok(())", "}" })
    set_and_wait(buf, lines, 9, 16, 25, "^Import `serde::Serialize`")
    local before = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local cap = H.capture_notify()
    local n = run_sync(buf, 0, #lines - 1, { mode = "single" })
    local t = text(buf)
    H.eq(1, n, "exactly one import: " .. t)
    -- rust-analyzer merges it into the existing `use serde::Deserialize;`
    H.match(t, "use serde::{Deserialize, Serialize};", true)
    H.no_match(t, "use std::io::Error", true)
    H.no_match(t, "Error;", true)
    local notes = vim.tbl_map(function(c)
      return c.msg
    end, cap.list)
    H.has(notes, "imported serde::Serialize")
    vim.api.nvim_buf_call(buf, function()
      vim.cmd("silent undo")
    end)
    H.eq(before, vim.api.nvim_buf_get_lines(buf, 0, -1, false), "one undo restores the buffer")
  end)
...
  it("remembers an explicit choice across a restart and 'single' then applies it", function()
    local dir, buf = lab()
    local lines = lab_lines()
    vim.list_extend(lines, { "", "fn lonely() -> Result<(), Error> {", "    Ok(())", "}" })
    local row = #lines - 3
    set_and_wait(buf, lines, row, 26, 31, "^Import `std::io::Error`")
    local before = text(buf)
    H.eq(0, run_sync(buf, 0, #lines - 1, { mode = "single" }), "ambiguous without a memory")
    H.eq(before, text(buf))
    local root = cm.root(dir)
    E.remember(root, "Error", "std::io::Error")
    E.reload_memory() -- restart: read imports.json again
    H.eq("std::io::Error", E.remembered(root, "Error"))
    H.eq(1, run_sync(buf, 0, #lines - 1, { mode = "single" }))
    H.match(text(buf), "use std::io::Error;", true)
  end)'''),
    ...sec(r'other real checks'),
    ...para('--', r'thiserror::Error is ranked first inside a derive and std::io::Error for an io::Result function; organize-imports is one undo step; paste imports in single mode. Review fixes: the default ask_key never blocks without a UI, and ImportName with a remembered choice keeps the other candidates in ranked order.'),
    ...sec(r'sources'),
    ...para('--', r'The engine accepts extra sources (crate_import is one): a source adds candidates, remembered choices win, a source candidate is applied through its own apply function, and :ImportName shows the ranked list with reasons and remembers the pick. See crate-import_spec.lua for the source that suggests uncommitted crates.'),
    ...sec(r'history'),
    blank,
    ...pt('--', r'b9363cd (2026-10-14)', r'created with the macros and dependencies work. dc846f6 the same day fixed the use-index fallback that walked no directories without ripgrep.'),
    ...pt('--', r'19f974c, b474307 (2026-10-15)', r'review and field test fixes.'),
    ...pt('--', r'9641d08 (2026-10-16), d3e1442 (2026-10-21)', r'Windows and macOS runs: path spelling in member_of, and the macOS timing skip.'),
  ],
);
