import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/tests/macros-deps-flows_spec.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'macros-deps-flows_spec.lua — four journeys through the macros-and-dependencies features, with nothing stubbed'),
    cm('--', r'from a missing name or a missing feature to a crate that builds'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'cross-module flows of the macros-and-dependencies phase, each on a temp copy of a fixture'),
    kv(r'language', r'Lua spec, 296 lines, 4 it() blocks, 4 describe() blocks, 600 second timeout'),
    kv(r'real parts', r'crates.io, cargo add, rust-analyzer and cargo check, as each flow needs them'),
    kv(r'fixtures', r'no-deps-lab, deps-lab-nofeature, deps-lab'),
    kv(r'history', r'2 commits: b9363cd (2026-10-14), d3e1442 (2026-10-21)'),
    ...sec(r'why this file exists'),
    ...para('--', r'The unit specs for crate_add, crate_import, crate_features, macro_attrs and import_engine each test one module with its neighbours replaced. They cannot catch the failure where each module is right and the seams between them are not. This spec exists for the seams. The header lists the four flows, and says the key rule: the real modules are wired together and none of the modules under test is stubbed. Every flow ends with cargo check, because the point of every feature here is that the code builds afterwards.'),
    ...code('lua', r'tests/macros-deps-flows_spec.lua · lines 1-14', r'''
-- xyno-timeout: 600
-- Cross-module flows of the macros-and-dependencies phase, each on a temp copy
-- of a fixture with the real modules wired together (no stubs of the modules
-- under test):
--   (a) a name no dependency offers -> "Add crate and import" -> builds
--       (no-deps-lab; real crates.io, cargo add, rust-analyzer, cargo check)
--   (b) serde without `derive` -> "Enable feature" -> builds
--       (deps-lab-nofeature; the diagnostic is hand-made like bacon-ls writes it)
--   (c) attribute completion inside #[serde( after (b), accepting a key and its value (deps-lab-nofeature, real cargo metadata)
--   (d) an ambiguous `Error` is left alone by auto-import until a choice is
--       remembered, then imported and builds (deps-lab, real rust-analyzer)
-- Each flow skips with a message without the tool or network it needs.
local H = require("xynotest.helpers")
local E = require("config.import_engine")'''),
    ...sec(r'shared scaffolding'),
    ...para('--', r'before_each redirects the import engine memory file to a temp dir and reloads it; after_each restores the stubs in reverse order, reloads the memory, invalidates crate_meta caches and wipes all buffers. cargo_check runs cargo check --quiet with its own target dir in a temp folder, optionally --offline, with a long timeout, so a flow does not share build artifacts with the fixture.'),
    ...code('lua', r'tests/macros-deps-flows_spec.lua · lines 25-60', r'''
  restores[#restores + 1] = function()
    t[k] = orig
  end
end

before_each(function()
  stub(E, "state_file", H.tmpdir() .. "/state/imports.json")
  E.reload_memory()
end)

after_each(function()
  for i = #restores, 1, -1 do
    pcall(restores[i])
  end
  restores = {}
  E.reload_memory()
  cm.invalidate()
  pcall(vim.cmd, "silent! %bwipeout!")
end)

local function read(path)
  local f = assert(io.open(path, "r"))
  local t = f:read("*a")
  f:close()
  return t
end

local function text(buf)
  return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
end

local function cargo_check(dir, offline)
  local argv = { "cargo", "check", "--quiet", "--target-dir", H.tmpdir() }
  if offline then
    table.insert(argv, 3, "--offline")
  end'''),
    ...sec(r'flow (a): a name nothing offers'),
    ...para('--', r'Uuid in a crate that has no dependencies. The test copies no-deps-lab, opens main.rs, waits for rust-analyzer and calls the import engine resolve for Uuid. rust-analyzer offers nothing, so the only candidate comes from crates.io, and the test requires a candidate with the path uuid::Uuid flagged as add_crate and as a guess. It then replaces the engine select function, the picker seam that :ImportName uses, with one that chooses that candidate, runs the add-and-import path for real (cargo add, rust-analyzer reload, apply) and ends with cargo check. The test is a known issue on Windows and skips with a message when crates.io is unreachable or the Rust tools are missing.'),
    ...code('lua', r'tests/macros-deps-flows_spec.lua · lines 72-111', r'''
describe("flow (a): unknown crate -> add crate and import -> builds", function()
  it("Uuid in a crate without dependencies", function()
    H.known_issue({ "windows" }, "live rust-analyzer flow fails or hangs on Windows (windows-latest run 39647013043; cause not diagnosed)")
    H.need_rust()
    if not cm.info("uuid", { index_only = true }) then
      return skip("crates.io is not reachable")
    end
    local dir = H.fixture("no-deps-lab")
    vim.cmd.cd(vim.fn.fnameescape(dir))
    local buf = H.open(dir .. "/src/main.rs")
    H.wait_lsp("rust-analyzer", buf)
    ci.setup()
    -- the picker's list: rust-analyzer offers nothing, crates.io guesses do
    local res
    E.resolve("Uuid", {
      bufnr = buf,
      cb = function(r)
        res = r
      end,
    })
    H.wait_for(function()
      return res
    end, 60000, "resolve")
    local cand
    for _, c in ipairs(res.candidates) do
      if c.path == "uuid::Uuid" then
        cand = c
      end
    end
    H.ok(cand and cand.add_crate and cand.guess, "the guess is offered: " .. vim.inspect(names(res.candidates)))
    -- the choice goes through the picker seam (what :ImportName does)
    stub(E, "select", function(items, _, on_choice)
      for _, it in ipairs(items) do
        if it.path == "uuid::Uuid" then
          return on_choice(it)
        end
      end
      on_choice(nil)
    end)
    local cap = H.capture_notify()'''),
    ...sec(r'flow (b): serde without derive'),
    ...para('--', r'The deps-lab-nofeature fixture derives Serialize without the derive feature. derive_buffer attaches the in-process feature client to a buffer of main.rs and sets a diagnostic by hand, with the message cannot find derive macro Serialize in this scope and source bacon-ls, because bacon-ls is not running in this test. The flow requests the code actions for the range, finds the single Enable feature derive of serde, applies it, and requires serde = { version = "1", features = ["derive"] } in Cargo.toml and a passing offline cargo check. It is the same acceptance as in crate-features_spec.lua, deliberately repeated here so that the whole chain is run in one place.'),
    ...code('lua', r'tests/macros-deps-flows_spec.lua · lines 163-177', r'''
describe("flow (b): serde without derive -> enable the feature -> builds", function()
  it("the action edits Cargo.toml, cargo check passes", function()
    local dir = nofeature()
    local buf, lnum = derive_buffer(dir)
    stub(ca, "client_name", cf.client_name)
    local list = ca.request_wait(buf, { start = { lnum, 0 }, ["end"] = { lnum, 1 } }, {})
    local hits = ca.filter(list, { title = "Enable feature `derive` of `serde`", plain = true })
    H.eq(1, #hits, vim.inspect(names(list)))
    local ok, err = ca.apply(hits[1], { timeout = 60000 })
    H.eq(true, ok, tostring(err))
    H.match(read(dir .. "/Cargo.toml"), 'serde = { version = "1", features = ["derive"] }', true)
    local r = cargo_check(dir, true)
    H.eq(0, r.code, (r.stderr or ""):sub(-1500))
  end)
end)'''),
    ...sec(r'flow (c): attribute completion after the fix'),
    ...para('--', r'The test first applies the feature fix of flow (b), then replaces a #[serde(...)] line with an empty #[serde()] and asks the macro_attrs completion at the cursor inside the parentheses, after invalidating the metadata caches and loading real cargo metadata (the comment says that before the metadata is loaded the answer is guessed from Cargo.toml). rename_all must be offered. Its item is a snippet; expanding it gives #[serde(rename_all = "")] with the cursor inside the quotes; the values menu offered inside the quotes must contain camelCase; accepting it gives #[serde(rename_all = "camelCase")]. A comment in the test records a design fact: the schema is offered by dependency and derive on the item, not by crate features, so the keys are listed even while the derive feature is off; the feature fix is what makes the attribute compile.'),
    ...code('lua', r'tests/macros-deps-flows_spec.lua · lines 179-249', r'''
describe("flow (c): attribute completion on a crate whose feature was just enabled", function()
  it("#[serde( after the feature fix: the keys, accepting rename_all and then camelCase", function()
    local dir = nofeature()
    local buf, lnum = derive_buffer(dir)
    -- an empty #[serde()] on the struct, cursor inside the parentheses
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local arow
    for i = lnum + 2, #lines do
      if lines[i]:find("#[serde(", 1, true) then
        arow = i
        break
      end
    end
    H.ok(arow, "the struct has a #[serde(...)] line")
    lines[arow] = "#[serde()]"
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    local col = #"#[serde("
    local function labels()
      cm.invalidate()
      -- real metadata first: before it has loaded the source guesses from Cargo.toml
      -- and cannot tell that serde's derive feature is off
      H.ok(cm.metadata(dir), "cargo metadata")
      local items = ma.items(buf, arow, col)
      return vim.tbl_map(function(i)
        return i.label
      end, items), items
    end
    -- (the schema is offered by dependency + derive on the item, not by the crate's
    -- features: the keys are also listed while serde's derive feature is off; the
    -- feature fix is what makes the attribute compile)
    -- (b): enable the feature, as the code action does
    stub(ca, "client_name", cf.client_name)
    local list = ca.request_wait(buf, { start = { lnum, 0 }, ["end"] = { lnum, 1 } }, {})
    local hits = ca.filter(list, { title = "Enable feature `derive` of `serde`", plain = true })
    H.eq(1, #hits)
    H.eq(true, (ca.apply(hits[1], { timeout = 60000 })))
    local after, items = labels()
    H.ok(vim.tbl_contains(after, "rename_all"), "serde keys are offered: " .. table.concat(after, " "))
    -- accept rename_all: a snippet with the cursor inside the quotes
    local item
    for _, it in ipairs(items) do
      if it.label == "rename_all" then
        item = it
      end
    end
    H.eq(vim.lsp.protocol.InsertTextFormat.Snippet, item.insertTextFormat)
    vim.api.nvim_set_current_buf(buf)
    vim.api.nvim_win_set_cursor(0, { arow, col })
    vim.cmd("startinsert")
    vim.snippet.expand(item.insertText)
    H.eq('#[serde(rename_all = "")]', vim.api.nvim_buf_get_lines(buf, arow - 1, arow, false)[1])
    -- the values menu inside the quotes, accept camelCase
    local cur = vim.api.nvim_win_get_cursor(0)
    local values = ma.items(buf, cur[1], cur[2])
    local value
    for _, it in ipairs(values) do
      if it.label == "camelCase" then
        value = it
      end
    end
    H.ok(value, "the values of rename_all are offered inside the quotes: " .. table.concat(vim.tbl_map(function(i)
      return i.label
    end, values), " "))
    vim.snippet.stop()
    vim.api.nvim_put({ value.insertText }, "c", false, true)
    vim.cmd("stopinsert")
    H.eq('#[serde(rename_all = "camelCase")]', vim.api.nvim_buf_get_lines(buf, arow - 1, arow, false)[1])
  end)
end)

-- ----------------------------------------------------------------------- (d)'''),
    ...sec(r'flow (d): the ambiguous Error'),
    ...para('--', r'The last flow is the one with the most interesting contract. It copies deps-lab, opens main.rs and waits for rust-analyzer, then appends a function lonely() returning Result<(), Error> to the buffer. It asks rust-analyzer for the quickfix actions at the Error and waits up to 12 seconds until the std::io::Error import is among them. Then it runs the auto-import in single mode. With several candidates and no memory it must import nothing and leave no use std::io::Error in the text. After the project remembers the choice, which is what :ImportName does after a pick, a second run imports one name and the text has use std::io::Error;. The test then saves the file and runs cargo check offline: it must return 0.'),
    ...code('lua', r'tests/macros-deps-flows_spec.lua · lines 251-296', r'''
describe("flow (d): an ambiguous Error import with a remembered choice", function()
  it("auto-import leaves Error alone, then applies the remembered std::io::Error, builds", function()
    H.need_rust()
    local dir = H.fixture("deps-lab")
    if not cm.metadata(dir) then
      return skip("registry lacks the deps-lab crates offline")
    end
    vim.cmd.cd(vim.fn.fnameescape(dir))
    local buf = H.open(dir .. "/src/main.rs")
    H.wait_lsp("rust-analyzer", buf)
    local lines = vim.fn.readfile(dir .. "/src/main.rs")
    vim.list_extend(lines, { "", "#[allow(dead_code)]", "fn lonely() -> Result<(), Error> {", "    Ok(())", "}" })
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    local row = #lines - 3 -- the `fn lonely` line, 0-based
    local ecol = lines[row + 1]:find("Error", 1, true) - 1
    local hits = ca.wait_for(buf, { start = { row, ecol }, ["end"] = { row, ecol + 5 } }, { kind = "quickfix", title = "^Import `std::io::Error`" }, { timeout = 120000, only = { "quickfix" } })
    H.ok(#hits > 0, "rust-analyzer offers the std::io::Error import")
    vim.api.nvim_buf_call(buf, function()
      vim.cmd("let &undolevels = &undolevels")
    end)
    local function run()
      local done, n
      E.run(buf, 0, #lines - 1, {
        mode = "single",
        done = function(c)
          done, n = true, c
        end,
      })
      H.wait_for(function()
        return done
      end, 60000, "import run")
      return n
    end
    -- several candidates and no memory: never guessed
    H.eq(0, run())
    H.no_match(text(buf), "use std::io::Error", true)
    -- the project remembers a choice (what :ImportName does after a pick)
    local root = cm.root(dir .. "/src/main.rs")
    E.remember(root, "Error", "std::io::Error")
    H.eq(1, run())
    H.match(text(buf), "use std::io::Error;", true)
    vim.cmd("silent write")
    local r = cargo_check(dir, true)
    H.eq(0, r.code, (r.stderr or ""):sub(-1500))
  end)
end)'''),
    ...sec(r'trade-offs'),
    blank,
    ...pt('--', r'Slow on purpose', r'the timeout is 600 seconds in the header. These flows are the only tests that combine network, cargo and a language server, and a slow clean machine needs room.'),
    ...pt('--', r'Skip, never fake', r'every missing ingredient produces a skip with a reason, so a green run on a machine without the registry is not a claim about the flows.'),
    ...sec(r'history'),
    blank,
    ...pt('--', r'b9363cd (2026-10-14)', r'created in the macros and dependencies commit.'),
    ...pt('--', r'd3e1442 (2026-10-21)', r'Windows and macOS run 39647013043 fixes: member_of compares one path spelling.'),
  ],
);
