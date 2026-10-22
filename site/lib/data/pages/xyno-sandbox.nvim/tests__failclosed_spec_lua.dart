import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-sandbox.nvim/tests/failclosed_spec.lua',
  lines: [
    cm('--', r'──────────────────────────────────────────'),
    cm('--', r'failclosed_spec.lua — the refusal, tested on every platform'),
    cm('--', r'four tests, 54 lines, no OS gate, no bwrap needed'),
    cm('--', r'──────────────────────────────────────────'),
    kv(r'role', r'proves the fail-closed property of status() and wrap()'),
    kv(r'language', r'Lua on the repo harness'),
    kv(r'size', r'54 lines, 4 tests in 1 describe group'),
    kv(r'requires', r'nothing: it points PATH at a nonexistent directory to simulate a machine without bwrap'),
    kv(r'history', r'ported from xynovim in 79bcfa5 (2026-10-22, Describe the agent generically, pin lazy.nvim '
        r'in CI, port the fail-closed spec)'),
    ...sec(r'why this file exists'),
    ...para('--', r'The sandbox is the point of this plugin, and a sandbox that silently turns itself off is '
        r'worse than none. The central promise is therefore a negative one: where no sandbox can be '
        r'built, the agent does not start. A positive test cannot show that; it has to be '
        r'demonstrated by taking the backend away. This is the spec that does it, and it is '
        r'deliberately the smallest and most portable file in the suite. The comment at the top is '
        r'the whole design of the test.'),
    ...code('lua', r'tests/failclosed_spec.lua · lines 1-4', r'''
-- The wrapper fails closed on every platform. No OS gate: where there is no
-- backend (Windows, macOS, or Linux without bwrap) wrap() must refuse. The
-- "no backend" case is forced everywhere by emptying PATH, so it runs on
-- Linux too.
'''),
    ...para('--', r'In xynovim the corresponding refusal was exercised by a separate spec, tests/agent-failclosed_spec.lua, added in ff1c8fa on '
        r'2026-10-16 (the fail-closed change itself is 440d781, same day), because the big sandbox spec is skipped on '
        r'Windows and macOS by design. The README of this repository says so and says what this '
        r'port does and does not change: the check runs without an OS gate, but this repository’s '
        r'CI runs only on Linux, so on Windows and macOS it is not run here.'),
    ...sec(r'restoring what the test breaks'),
    ...code('lua', r'tests/failclosed_spec.lua · lines 5-18', r'''
local H = require("xynotest.helpers")
local sb = require("xyno_sandbox")

local saved = vim.deepcopy(sb.config)
local old_path = vim.env.PATH
after_each(function()
  sb.config = vim.deepcopy(saved)
  vim.env.PATH = old_path
end)

local function no_backend()
  vim.env.PATH = "/nonexistent-xyno-path"
end

'''),
    ...para('--', r'The spec keeps a deep copy of the module configuration and the original PATH, and '
        r'restores both after every test. Pointing PATH at a missing directory is meant to work on every platform (CI here runs only on Linux): '
        r'status() calls vim.fn.executable for bwrap, which searches PATH, so a PATH that points at '
        r'a directory that does not exist makes bwrap unfindable on a machine that has it, and '
        r'makes the check meaningful on Linux as well as on macOS and Windows. The name no_backend '
        r'says what the helper simulates.'),
    ...sec(r'the four tests'),
    ...code('lua', r'tests/failclosed_spec.lua · lines 19-28', r'''
describe("without a backend", function()
  it("loads and answers on this platform (" .. H.os .. ")", function()
    H.eq("function", type(sb.status))
    H.eq("function", type(sb.wrap))
  end)

  it("status() is refused when bwrap cannot be found", function()
    no_backend()
    H.eq("refused", sb.status().mode)
  end)
'''),
    ...para('--', r'The first test is an existence check: the module loads on this platform and exposes '
        r'status and wrap as functions. It names the platform in the test title through H.os, so a '
        r'log from any machine says where it ran. The second removes the backend and asserts that '
        r'the mode is refused.'),
    ...code('lua', r'tests/failclosed_spec.lua · lines 30-35', r'''
  it("wrap() returns nil plus a reason", function()
    no_backend()
    local got, reason = sb.wrap({ "agent" }, vim.uv.cwd(), vim.uv.cwd())
    H.eq(nil, got)
    H.ok(type(reason) == "string" and reason ~= "", "a reason comes with the refusal")
  end)
'''),
    ...para('--', r'The third asserts the shape of the refusal: the wrapped command is nil and the second '
        r'return value is a non-empty string. A nil without a reason would make the failure '
        r'invisible to a caller that prints it.'),
    ...code('lua', r'tests/failclosed_spec.lua · lines 37-53', r'''
  it("only the two explicit booleans lead to an unsandboxed run", function()
    no_backend()
    local cmd = { "agent" }
    for _, v in ipairs({ 0, 1, "false", "true" }) do
      sb.config.sandbox = v
      sb.config.allow_unsandboxed = v
      H.eq("refused", sb.status().mode, vim.inspect(v))
    end
    sb.config.sandbox = false
    sb.config.allow_unsandboxed = false
    H.ok(sb.wrap(cmd, vim.uv.cwd(), vim.uv.cwd()) == cmd, "sandbox = false returns the command")
    H.eq("unsandboxed", sb.status().mode)
    sb.config.sandbox = true
    sb.config.allow_unsandboxed = true
    H.ok(sb.wrap(cmd, vim.uv.cwd(), vim.uv.cwd()) == cmd, "allow_unsandboxed returns the command")
    H.eq("allow_unsandboxed", sb.status().via)
  end)
'''),
    ...para('--', r'The fourth test is the one that checks the strictness of the opt-outs. With no backend, '
        r'it sets both options to each of 0, 1, the string false and the string true, and for every '
        r'value the mode must still be refused. Only after that does it set the real booleans: '
        r'sandbox false must return the very same command table (compared with == so that it is the '
        r'same table, not a copy), with mode unsandboxed, and allow_unsandboxed true must return '
        r'the same table with the via field set to allow_unsandboxed.'),
    ...sec(r'what this test proves, and what it does not'),
    ...para('--', r'It proves that, with no backend, no value of either option other than the two exact '
        r'booleans yields an unsandboxed run; that the refusal carries a reason; and that the two '
        r'documented opt-outs work and are recorded in status. It does not prove the other '
        r'strictness claim, that with a working bwrap the string false or the number 0 for sandbox '
        r'leaves the sandbox on; that follows from the strict comparison in init.lua and is covered '
        r'in the big spec by the tests named only the booleans count and allow_unsandboxed alone '
        r'never disables a working bwrap. It also does not prove that bwrap works: it never runs a '
        r'wrapped command.'),
    ...sec(r'history'),
    ...pt('--', r'79bcfa5', r'2026-10-22: the spec arrives in the commit that also pins lazy.nvim in CI and rewrites '
        r'the README and help text to describe the agent generically.'),
  ],
);
