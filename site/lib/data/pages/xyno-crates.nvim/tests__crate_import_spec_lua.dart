import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-crates.nvim/tests/crate-import_spec.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'crate-import_spec.lua — a source that must never guess in silence'),
    cm('--', r'14 tests: candidate rules, a fake polling loop, and one real "Uuid from nothing"'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'spec for lua/xyno_crates/crate_import.lua and its wiring in crate_add'),
    kv(r'language', r'Lua on tests/harness.lua'),
    kv(r'size', r'408 lines, 14 tests in 5 groups'),
    kv(r'hermetic', r'all but the last test; crates.io and the import engine are stubbed'),
    kv(r'live', r'the last test: real crates.io, real rust-analyzer, real cargo check; skips without them'),
    kv(r'history', r'xynovim tests/crate-import_spec.lua (b9363cd, 2026-10-14); 20 changed lines at the extraction'),
    ...sec(r'why this file exists'),
    ...para('--', r'crate_import.lua has two kinds of behaviour. The source decides what to propose, which is pure decision logic over a few network answers. The add-and-wait path is a small state machine over time: poll, wait, apply, give up. Both can be tested without a network if the three seams are stubs: cm.metadata_async, cm.info_async and cm.search_async for the first, and the engine’s candidates_at and apply_candidate for the second. This spec does exactly that, then adds one test that uses everything for real.'),
    blank,
    ...code('lua', r'tests/crate-import_spec.lua · lines 30-54', r'''
--- Run the source and wait for its answer.
local function ask(name, ctx)
  local got
  ci.source(name, ctx or {}, function(list)
    got = list
  end)
  H.wait_for(function()
    return got
  end, 5000, "the source's answer")
  return got
end

local function paths(list)
  return vim.tbl_map(function(c)
    return c.path
  end, list)
end

local function no_meta()
  stub(cm, "metadata_async", function(_, cb)
    vim.schedule(function()
      cb(nil, "stubbed")
    end)
  end)
end'''),
    ...para('--', r'ask() calls the source and waits for its callback (5 seconds at most), paths() projects candidates to their path strings, no_meta() answers the metadata call with a scheduled nil. The scheduling matters: real answers arrive asynchronously, and a stub that calls the callback inline would test a different control flow.'),
    blank,
    ...sec(r'the source rules, one test each'),
    ...code('lua', r'tests/crate-import_spec.lua · lines 56-90', r'''
describe("crate_import.source", function()
  it("fills gaps only: nothing when rust-analyzer offered candidates", function()
    stub(cm, "search_async", function()
      error("must not search")
    end)
    H.eq({}, ask("Uuid", { local_candidates = { { path = "uuid::Uuid" } } }))
  end)

  it("a lowercase name that is a crate on crates.io: the crate itself, as an add-crate candidate", function()
    no_meta()
    local asked = {}
    stub(cm, "info_async", function(name, cb)
      asked[#asked + 1] = name
      vim.schedule(function()
        cb(name == "rand" and { name = "rand", newest = "0.9.1" } or nil, "not found")
      end)
    end)
    local out = ask("rand", { root = "/x" })
    H.eq({ "rand" }, paths(out))
    H.eq({ "rand" }, asked)
    H.ok(out[1].add_crate and out[1].crate == "rand" and not out[1].guess)
    H.match(out[1].note, "rand 0.9.1", true)
  end)

  it("a path head with an underscore also tries the dashed crate name", function()
    no_meta()
    stub(cm, "info_async", function(name, cb)
      vim.schedule(function()
        cb(name == "serde-json" and { name = "serde-json", newest = "1.0.0" } or nil, "not found")
      end)
    end)
    local out = ask("serde_json")
    H.eq({ "serde_json" }, paths(out))
    H.eq("serde_json", out[1].crate)
  end)'''),
    ...para('--', r'First, "fills gaps only": search_async is stubbed to raise an error, and the source must answer {} without calling it when local candidates exist. Second, a lowercase name yields the crate itself: the stub index knows rand 0.9.1, the result is exactly { "rand" }, it is marked add_crate and not guess, and the note mentions "rand 0.9.1". Third, serde_json is looked up as serde_json first and as serde-json second, and the candidate is named serde_json.'),
    blank,
    ...code('lua', r'tests/crate-import_spec.lua · lines 92-132', r'''
  it("an item name: crates whose name equals or contains it, by downloads, labelled as guesses", function()
    no_meta()
    stub(cm, "search_async", function(q, cb)
      H.eq("uuid", q)
      vim.schedule(function()
        cb({
          { name = "uuid-simd", version = "0.8.0", downloads = 5 },
          { name = "uuid", version = "1.10.0", downloads = 900 },
          { name = "unrelated", version = "1.0.0", downloads = 99999 },
          { name = "-uuid", version = "1.0.0", downloads = 1 }, -- would be an argv flag
          { name = "my_uuid_x", version = "1.0.0", downloads = 50 },
        })
      end)
    end)
    local out = ask("Uuid")
    H.eq({ "uuid::Uuid", "my_uuid_x::Uuid", "uuid_simd::Uuid" }, paths(out))
    for _, c in ipairs(out) do
      H.ok(c.guess and c.add_crate and type(c.apply) == "function")
      H.match(c.note, "guess", true)
    end
  end)

  it("never guesses for very short names, never for a crate that is already a dependency", function()
    no_meta()
    stub(cm, "search_async", function()
      error("must not search")
    end)
    H.eq({}, ask("Ab"))
    local root = H.tmpdir()
    stub(cm, "metadata_async", function(_, cb)
      vim.schedule(function()
        cb({ dependencies = { { name = "uuid", kind = "normal", member = "m" } } })
      end)
    end)
    stub(cm, "search_async", function(_, cb)
      vim.schedule(function()
        cb({ { name = "uuid", version = "1", downloads = 1 } })
      end)
    end)
    H.eq({}, ask("Uuid", { root = root }))
  end)'''),
    ...para('--', r'The guess test is the best story in the file. The search stub returns five hits: uuid-simd with 5 downloads, uuid with 900, unrelated with 99999 downloads, "-uuid" with 1 (the comment says "would be an argv flag") and my_uuid_x with 50. The expected result is uuid::Uuid, my_uuid_x::Uuid, uuid_simd::Uuid: the unrelated crate is excluded for not containing the name, even with the most downloads; the dashed crate is excluded as unsafe; the rest are sorted by downloads. Every candidate has guess, add_crate and an apply function, and its note contains the word "guess". The next test locks the two silences: no search for a name shorter than three characters, and none for a crate that is already a dependency.'),
    blank,
    ...sec(r'the add-and-import state machine'),
    ...code('lua', r'tests/crate-import_spec.lua · lines 231-268', r'''
  it("adds the crate, polls until rust-analyzer offers the import, applies the one of that crate", function()
    local buf = setup_buf()
    stub(ci.config, "poll_ms", 20)
    local added
    stub(cadd, "add_direct", function(_, name, cb)
      added = name
      vim.schedule(function()
        cb(true, "added")
      end)
    end)
    local polls, applied = 0, nil
    stub(E, "candidates_at", function(_, pos, cb)
      polls = polls + 1
      H.eq({ 1, 13 }, { pos.row, pos.col })
      vim.schedule(function()
        if polls < 3 then
          return cb({ E.candidate("std::fmt::Debug") }) -- someone else's, not the crate's
        end
        cb({ E.candidate("uuid::fmt::Uuid"), E.candidate("uuid::Uuid"), E.candidate("other::Uuid") })
      end)
    end)
    stub(E, "apply_candidate", function(_, cand, cb)
      applied = cand.path
      cb(true)
    end)
    local done, ok, msg
    ci.add_and_import(buf, { crate = "uuid", name = "Uuid", path = "uuid::Uuid" }, function(a, b)
      done, ok, msg = true, a, b
    end)
    H.wait_for(function()
      return done
    end, 5000, "add and import")
    H.eq("uuid", added)
    H.eq(true, ok, tostring(msg))
    H.eq("uuid::Uuid", applied)
    H.ok(polls >= 3)
    H.match(msg, "imported uuid::Uuid", true)
  end)'''),
    ...para('--', r'The test fakes add_direct (success), candidates_at (the wrong crate twice, then the right one with three candidates) and apply_candidate, shrinks poll_ms to 20, and runs add_and_import for the name Uuid on a three-line buffer. It asserts the position handed to the engine, { row 1, col 13 }, which proves the extmark tracked the right occurrence of Uuid, outside the use lines; at least three polls; the crate passed to add_direct; and that the applied path is uuid::Uuid, the exact-path candidate, not uuid::fmt::Uuid and not other::Uuid.'),
    blank,
    ...code('lua', r'tests/crate-import_spec.lua · lines 270-293', r'''
  it("gives up after the bounded wait, the crate stays added", function()
    local buf = setup_buf()
    stub(ci.config, "poll_ms", 20)
    stub(ci.config, "reload_timeout_ms", 150)
    stub(cadd, "add_direct", function(_, _, cb)
      vim.schedule(function()
        cb(true, "added")
      end)
    end)
    stub(E, "candidates_at", function(_, _, cb)
      vim.schedule(function()
        cb({})
      end)
    end)
    local done, ok, msg
    ci.add_and_import(buf, { crate = "uuid", name = "Uuid" }, function(a, b)
      done, ok, msg = true, a, b
    end)
    H.wait_for(function()
      return done
    end, 5000, "timeout")
    H.eq(false, ok)
    H.match(msg, "did not offer an import", true)
  end)'''),
    ...para('--', r'The give-up test sets reload_timeout_ms to 150 ms and answers candidates_at with an empty list for ever. The callback must receive false and a message containing "did not offer an import". The comment in the module says the crate stays added, and the production code is built that way, but this test does not assert it: it checks only the message. The tests that follow cover a failed add that stops the flow, an invalid crate name that never reaches cargo, and a bare path head that only adds.'),
    blank,
    ...code('lua', r'tests/crate-import_spec.lua · lines 345-359', r'''
describe("crate_add's action uses the same path", function()
  it("the 'Add crate X' command of the in-process server calls add_and_import", function()
    local buf = vim.api.nvim_create_buf(true, false)
    local got
    stub(ci, "add_and_import", function(b, spec)
      got = { b, spec.crate, spec.name }
    end)
    local srv = cadd.server({})
    srv.request("workspace/executeCommand", { command = "xyno.crateAdd", arguments = { { name = "rand", bufnr = buf } } }, function() end)
    H.eq({ buf, "rand", nil }, got)
    got = nil
    srv.request("workspace/executeCommand", { command = "xyno.crateAdd", arguments = { { name = "--git", bufnr = buf } } }, function() end)
    H.is_nil(got, "a flag-like name is refused")
  end)
end)'''),
    ...para('--', r'The last hermetic group connects crate_add to crate_import. It calls cadd.server({}) to get the in-process server table, sends executeCommand for the add command with a plausible name and expects add_and_import to receive the buffer, the crate and a nil name; then sends the name --git and expects nothing to be called: "a flag-like name is refused". This is the test that pins the "one add path" comment in crate_add.lua.'),
    blank,
    ...sec(r'the real one'),
    ...code('lua', r'tests/crate-import_spec.lua · lines 361-381', r'''
describe("real: Uuid from nothing", function()
  it("search, add the crate, wait for rust-analyzer, import, cargo build", function()
    H.known_issue({ "windows" }, "live rust-analyzer flow fails or hangs on Windows (windows-latest run 39647013043; cause not diagnosed)")
    H.need_rust()
    local info = cm.info("uuid", { index_only = true })
    if not info then
      return skip("crates.io is not reachable")
    end
    local dir = H.fixture("no-deps-lab")
    vim.cmd.cd(vim.fn.fnameescape(dir))
    local buf = H.open(dir .. "/src/main.rs")
    H.start_ra(buf, dir)
    ci.setup()
    local res
    E.resolve("Uuid", {
      bufnr = buf,
      cb = function(r)
        res = r
      end,
    })
    H.wait_for(function()'''),
    ...para('--', r'"real: Uuid from nothing" copies the no-deps-lab fixture, starts a real rust-analyzer on it (H.start_ra, the line that replaced H.wait_lsp at the extraction), registers the source, asks the engine to resolve the name Uuid and waits up to a minute. It finds uuid::Uuid among the candidates and asserts that it is marked add_crate and guess: the label survives the full path.'),
    blank,
    ...code('lua', r'tests/crate-import_spec.lua · lines 392-407', r'''
    local done, ok, msg
    E.apply_candidate(buf, cand, function(a, b)
      done, ok, msg = true, a, b
    end)
    H.wait_for(function()
      return done
    end, 120000, "add and import")
    H.eq(true, ok, tostring(msg))
    local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
    H.match(text, "use uuid::Uuid;", true)
    local toml = table.concat(vim.fn.readfile(dir .. "/Cargo.toml"), "\n")
    H.match(toml, "uuid", true)
    vim.cmd("silent write")
    local r = vim.system({ "cargo", "check", "--quiet", "--target-dir", H.tmpdir() }, { cwd = dir, text = true }):wait(170000)
    H.eq(0, r.code, (r.stderr or ""):sub(-1500))
  end)'''),
    ...para('--', r'Then it applies the candidate and waits up to two minutes for add, load and import. The text of the buffer must contain use uuid::Uuid;, Cargo.toml must mention uuid, and after writing the file cargo check --quiet in the fixture directory must exit with 0. On Windows the test is a known issue with the CI run number; without network, cargo or rust-analyzer it skips with a reason. It is slow on purpose, the only test in the file that touches the world.'),
    blank,
    ...sec(r'what the spec cannot show'),
    ...pt('--', r'the real engine ordering', r'the group "the import engine with the source" checks that resolve() lists guesses after rust-analyzer’s candidates, labelled, and that sources = false skips them; a slow source is cut off by source_wait_ms. These belong to xyno-imports.nvim as much as to this plugin.'),
    ...pt('--', r'a user who edits during the wait', r'the extmark checks (name edited away, edited meanwhile) have no dedicated test here; they are exercised only by reading the code.'),
    ...sec(r'history'),
    ...pt('--', r'b9363cd, 2026-10-14', r'added in xynovim with crate_import.lua; touched once more there, in the Windows/macOS round d3e1442 (2026-10-21).'),
    ...pt('--', r'9d33ca7, 2026-10-22', r'copied here with new requires, the command id xyno.crateAdd, and H.start_ra for the live test.'),
  ],
);
