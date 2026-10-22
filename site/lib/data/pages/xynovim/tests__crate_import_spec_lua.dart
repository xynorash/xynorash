import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/tests/crate-import_spec.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'crate-import_spec.lua — importing from a crate you have not added yet'),
    cm('--', r'the async source that fills gaps in the import engine, and the add-then-import path'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'spec for lua/config/crate_import.lua, with the import engine and crate_add action wiring'),
    kv(r'language', r'Lua spec, 408 lines, 14 it() blocks, 5 describe() blocks'),
    kv(r'hermetic', r'everything except the last test; that one adds a real crate to a copy of the no-deps-lab fixture'),
    kv(r'needs', r'network, cargo and rust-analyzer for the last test only'),
    kv(r'history', r'2 commits: b9363cd (2026-10-14), d3e1442 (2026-10-21)'),
    ...sec(r'why this file exists'),
    ...para('--', r'Typing Uuid in a crate that has no uuid dependency leaves rust-analyzer with nothing to offer for an import. crate_import registers a source with the import engine that asks crates.io and proposes uuid::Uuid as an add-crate candidate. If the user accepts it, the crate is added, the module waits until rust-analyzer has reloaded the project and offers the import, and then applies exactly that import. The header lists three parts: the async source, the add-and-wait path, and the action wiring in crate_add.'),
    ...code('lua', r'tests/crate-import_spec.lua · lines 1-5', r'''
-- config.crate_import: import from crates that are not dependencies yet (the
-- async import-engine source, the add-and-wait path, crate_add's action wiring).
-- Hermetic except the last test: that one adds a real crate from crates.io to a
-- copy of the no-deps-lab fixture, waits for the real rust-analyzer and builds;
-- it skips without network, cargo or rust-analyzer.'''),
    ...sec(r'the stub helper'),
    ...para('--', r'Almost the whole file is hermetic through a tiny stub(t, k, v) helper that replaces a field of a module table and registers a restore function, which an after_each runs. Stubbing at module level instead of through mocks of the network means each test says what is replaced, and the real code runs around it.'),
    ...code('lua', r'tests/crate-import_spec.lua · lines 14-22', r'''
local function stub(t, k, v)
  local orig = t[k]
  t[k] = v
  restores[#restores + 1] = function()
    t[k] = orig
  end
end

after_each(function()'''),
    ...sec(r'gap filling only'),
    ...para('--', r'The source must never compete with the language server. The first test stubs the search function with one that raises must not search, and calls the source with rust-analyzer candidates in place. The result must be an empty list. The next tests are about the forms of the name: a lowercase name which is a crate on crates.io becomes the crate itself as an add-crate candidate; a path head with an underscore also tries the dashed crate name; an item name finds crates whose name equals or contains it, by downloads, labelled as guesses; very short names never produce guesses, and neither do crates that are already dependencies; offline or failing lookups give no candidates and no error.'),
    ...code('lua', r'tests/crate-import_spec.lua · lines 57-62', r'''
  it("fills gaps only: nothing when rust-analyzer offered candidates", function()
    stub(cm, "search_async", function()
      error("must not search")
    end)
    H.eq({}, ask("Uuid", { local_candidates = { { path = "uuid::Uuid" } } }))
  end)'''),
    ...sec(r'the engine does not wait for a slow source'),
    ...para('--', r'A source can be slow. The engine has source_wait_ms; the test registers a source that never calls back, sets the limit to 300 ms, and stubs the code-action request to answer at once. resolve must still return a result, and well inside three seconds. Registering a source returns an unregister function, which the test calls so that the dead source does not leak into later tests.'),
    ...code('lua', r'tests/crate-import_spec.lua · lines 199-221', r'''
  it("a slow source does not hold resolve() beyond source_wait_ms", function()
    local un = E.register_source(function(_, _, cb) end, { async = true })
    stub(E.config, "source_wait_ms", 300)
    stub(ca, "request", function(_, _, _, cb)
      vim.schedule(function()
        cb({}, nil)
      end)
    end)
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "fn main() { Foo; }" })
    local t0, res = vim.uv.now(), nil
    E.resolve("Foo", {
      bufnr = buf,
      cb = function(r)
        res = r
      end,
    })
    H.wait_for(function()
      return res
    end, 8000, "resolve")
    un()
    H.ok(vim.uv.now() - t0 < 3000)
  end)'''),
    ...sec(r'add, wait, apply'),
    ...para('--', r'The add-and-import test replaces three functions: the add itself, the candidate lookup and the application. The lookup is called every poll interval and answers with someone else’s candidate (std::fmt::Debug) for the first two polls and then with three candidates, uuid::fmt::Uuid, uuid::Uuid and other::Uuid. The test requires that the crate that was added is uuid, that the applied candidate is uuid::Uuid (the candidate of the crate that was added, not other::Uuid and not the fmt path), that polling happened at least three times, and that the message says imported uuid::Uuid. The position passed to the lookup must be row 1, column 13, asserted in the stub.'),
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
    ...sec(r'bounded waiting'),
    ...para('--', r'Waiting for a language server to reload cannot be unbounded. With reload_timeout_ms set to 150 ms and a lookup that never offers anything, the callback must be called with false and a message containing did not offer an import. The crate stays added. The next tests make a failed add stop there, check that an invalid crate name never reaches cargo, and that a name without an import (a path head) only adds.'),
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
    ...sec(r'wiring and the real run'),
    ...para('--', r'One test checks that the Add crate X command of the in-process server calls add_and_import, so both entry points share a path. The last test, Uuid from nothing, searches, adds the crate to a copy of the no-deps-lab fixture, waits for the real rust-analyzer, imports and runs cargo build; it skips without network, cargo or rust-analyzer.'),
    ...sec(r'history'),
    blank,
    ...pt('--', r'b9363cd (2026-10-14)', r'created with the macros and dependencies work (dependency freshness, crate add, import engine). Note that dc846f6 of the same day fixed the import engine use-index fallback.'),
    ...pt('--', r'd3e1442 (2026-10-21)', r'Windows and macOS run 39647013043 fixes.'),
  ],
);
