import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/tests/harness_spec.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'harness_spec.lua — the helpers, tested'),
    cm('--', r'75 lines that prove the toolbox works before anything relies on it'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'unit tests for helpers.lua: eq, wait_for, feed, capture_notify, fixtures, git, cleanup, sandbox wrapper'),
    kv(r'language', r'Lua spec, 75 lines, 8 it() blocks, 2 describe() blocks'),
    kv(r'needs', r'nothing for the first six; bwrap for the last (it skips otherwise)'),
    kv(r'history', r'created 2026-10-13 (cf2b8e1), touched again by the platform work'),
    ...sec(r'why a spec for the test helpers'),
    ...para('--', r'Every other spec trusts H. If H.eq silently passed everything, every other test would be green and worth nothing. This spec is the smallest possible insurance: it checks that the helpers do what their one-line docs claim, using only the editor itself. Note what it does not need: no Rust tooling, no language server (its first comment says so).'),
    ...code('lua', r'tests/harness_spec.lua · lines 1-2', r'''
-- The test helpers themselves (no Rust tooling needed).
local H = require("xynotest.helpers")'''),
    ...sec(r'eq must be able to fail'),
    ...para('--', r'The first test checks both directions of an assertion: equal nested tables pass, and unequal ones make H.throws see an error that mentions expected. Testing the failure path of an assertion is the point. An assertion that cannot fail is the commonest hidden bug in a test suite.'),
    ...code('lua', r'tests/harness_spec.lua · lines 4-10', r'''
describe("helpers", function()
  it("deep-compares in eq", function()
    H.eq({ 1, { a = 2 } }, { 1, { a = 2 } })
    H.throws(function()
      H.eq({ 1 }, { 2 })
    end, "expected")
  end)'''),
    ...sec(r'waiting: success value and timeout message'),
    ...para('--', r'wait_for is checked from both ends. The predicate returns false twice and a truthy value on the third call, which proves it is polled and its value returned. A predicate that never succeeds, with a 50 ms limit, must raise an error containing timed out waiting for never, which proves the message you pass is the one you see in a log.'),
    ...code('lua', r'tests/harness_spec.lua · lines 12-23', r'''
  it("wait_for returns the value and times out with a message", function()
    local n = 0
    H.eq(
      3,
      H.wait_for(function()
        n = n + 1
        return n >= 3 and n
      end, 1000)
    )
    H.throws(function()
      H.wait_for(function() end, 50, "never")
    end, "timed out waiting for never")'''),
    ...sec(r'feed and notifications'),
    ...para('--', r'H.feed types keys through mappings: a fresh buffer, ihello<Esc>, then the buffer lines must be exactly hello. capture_notify swaps vim.notify, records message and level into list, and restore must put the original function back, which the test checks by identity. This second check matters because specs that forget to restore leak a stub into later tests of the same file.'),
    ...code('lua', r'tests/harness_spec.lua · lines 25-38', r'''

  it("feed types keys through mappings", function()
    vim.cmd("enew!")
    H.feed("ihello<Esc>")
    H.eq({ "hello" }, vim.api.nvim_buf_get_lines(0, 0, -1, false))
  end)

  it("captures notifications and restores vim.notify", function()
    local orig = vim.notify
    local cap = H.capture_notify()
    vim.notify("x", vim.log.levels.WARN)
    H.eq({ { msg = "x", level = vim.log.levels.WARN } }, cap.list)
    cap.restore()
    H.ok(vim.notify == orig)'''),
    ...sec(r'fixtures and git'),
    ...para('--', r'Fixtures are copied to private dirs: two copies of basic must have different paths and both contain src/lib.rs, the workspace fixture contains core/Cargo.toml, broken has src/main.rs, and standalone.rs works as a single-file fixture. H.fixture with git = true produces a repository on branch main with a clean status. Those assertions are the contract that the Rust specs rely on: never edit the committed fixture, always a copy.'),
    ...code('lua', r'tests/harness_spec.lua · lines 40-56', r'''

  it("copies fixtures into private temp dirs", function()
    local a, b = H.fixture("basic"), H.fixture("basic")
    H.ok(a ~= b)
    H.eq(1, vim.fn.filereadable(a .. "/src/lib.rs"))
    H.eq(1, vim.fn.filereadable(H.fixture("workspace") .. "/core/Cargo.toml"))
    H.eq(1, vim.fn.filereadable(H.fixture("broken") .. "/src/main.rs"))
    H.eq(1, vim.fn.filereadable(H.fixture("standalone.rs")))
  end)

  it("makes git repositories", function()
    local dir = H.fixture("basic", { git = true })
    H.eq("main", H.git(dir, "rev-parse", "--abbrev-ref", "HEAD"))
    H.eq("", H.git(dir, "status", "--porcelain"))
  end)

  it("removes its temp dirs in cleanup", function()'''),
    ...sec(r'cleanup removes its directories'),
    ...para('--', r'The cleanup test creates a tmpdir, sees that it exists, calls H.cleanup() directly, and checks that it is gone. It calls the real function, not a mock, so this is also a check that cleanup runs to the end without an error when there is little to clean.'),
    ...code('lua', r'tests/harness_spec.lua · lines 58-63', r'''
    H.eq(1, vim.fn.isdirectory(dir))
    H.cleanup()
    H.eq(0, vim.fn.isdirectory(dir))
  end)
end)
'''),
    ...sec(r'the sandbox wrapper'),
    ...para('--', r'The last block checks the property that matters most for the agent sandbox: the project stays writable and the rest of the disk is read-only. The script writes inside.txt in the project and then asserts with ! touch that creating a file in HOME fails; the test then checks from outside that inside.txt exists and the probe file does not. It runs through H.sandbox_sh, which skips when bwrap is unusable. The deeper security assertions live in agent-sandbox_spec.lua; this one only proves the helper that those specs use.'),
    ...code('lua', r'tests/harness_spec.lua · lines 66-75', r'''
    local project = H.fixture("basic")
    local r = H.sandbox_sh(
      "echo ok > inside.txt && ! touch " .. vim.fn.shellescape(vim.env.HOME) .. "/xyno-sandbox-probe",
      project
    )
    H.eq(0, r.code, r.stderr)
    H.eq(1, vim.fn.filereadable(project .. "/inside.txt"))
    H.eq(0, vim.fn.filereadable(vim.env.HOME .. "/xyno-sandbox-probe"))
  end)
end)'''),
    ...sec(r'history'),
    blank,
    ...pt('--', r'cf2b8e1 (2026-10-13)', r'created with the harness and helpers; the file has no later commit.'),
  ],
);
