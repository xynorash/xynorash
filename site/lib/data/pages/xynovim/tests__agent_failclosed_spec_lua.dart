import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/tests/agent-failclosed_spec.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'agent-failclosed_spec.lua — no sandbox, no agent'),
    cm('--', r'the 119-line spec that runs on every OS and proves the 99 agent refuses to start unsandboxed'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'fail-closed contract of config.agent_sandbox and the guarded 99 provider, on Linux, macOS and Windows'),
    kv(r'language', r'Lua spec, 119 lines, 5 it() blocks, 2 describe() blocks'),
    kv(r'needs', r'nothing: it checks the refusal, so it must not need a backend'),
    kv(r'size', r'119 lines, 2 commits (created in ff1c8fa, changed in 7025437)'),
    kv(r'counterpart', r'agent-sandbox_spec.lua tests the bwrap command itself, on Linux only'),
    ...sec(r'why this file exists'),
    ...para('--', r'The 99 plugin runs the claude CLI with --dangerously-skip-permissions against your code. The protection is a bubblewrap sandbox around that process, and bubblewrap exists only on Linux. The original wrapper had an escape hatch: when no sandbox was available, the agent simply ran unsandboxed. The commit 440d781 (2026-10-16, "Agent sandbox fails closed when no sandbox backend is available") reversed that default: with no backend, wrap() now returns nil plus a reason, and the provider reports a failed request without spawning anything. This spec is the proof, and it is deliberately the one that runs in the Windows and macOS CI job, where the right answer is always "refused". The header says exactly this.'),
    ...code('lua', r'tests/agent-failclosed_spec.lua · lines 1-4', r'''
-- The 99 agent sandbox fails closed, on EVERY platform. This is the spec that
-- runs on Windows and macOS in the platforms workflow (bubblewrap exists only
-- on Linux, so there the answer must be "refused"); agent-sandbox_spec.lua
-- (Linux only) tests the bwrap command itself.'''),
    ...sec(r'the two switches'),
    ...para('--', r'The module has two explicit booleans in vim.g. xynovim_99_sandbox = false is a deliberate opt-out that works even where bwrap does. xynovim_99_allow_unsandboxed = true lets the agent run where no backend exists. The spec needs to flip them and restore them, so it defines with_g, which saves the old value, sets the new one, runs a function under pcall, restores, and only then re-raises. neutral() clears both switches, so a test about the default behaviour is not affected by the global state of the editor it runs in.'),
    ...code('lua', r'tests/agent-failclosed_spec.lua · lines 9-21', r'''
local function with_g(name, value, fn)
  local old = vim.g[name]
  vim.g[name] = value
  local ok, err = pcall(fn)
  vim.g[name] = old
  assert(ok, err)
end

local function neutral(fn)
  with_g("xynovim_99_sandbox", nil, function()
    with_g("xynovim_99_allow_unsandboxed", nil, fn)
  end)
end'''),
    ...sec(r'what the machine can do'),
    ...para('--', r'native_backend is true only when the platform is Linux and bwrap is executable. Every expectation in the file is parametrised by it: bwrap where a backend exists, refused where not. That is how one file can run unchanged on three operating systems and still make a strong claim on each.'),
    ...code('lua', r'tests/agent-failclosed_spec.lua · lines 23-35', r'''
local native_backend = vim.fn.has("linux") == 1 and vim.fn.executable("bwrap") == 1

describe("agent_sandbox without a backend", function()
  it("loads and answers on this platform (" .. H.os .. ")", function()
    H.eq("function", type(sandbox.status))
    H.eq("function", type(sandbox.wrap))
  end)

  it("status() is bwrap only on Linux with bwrap, else refused", function()
    neutral(function()
      H.eq(native_backend and "bwrap" or "refused", sandbox.status().mode)
    end)
  end)'''),
    ...sec(r'the refusal has a reason'),
    ...para('--', r'On a machine without a backend, wrap() must return a nil command and a non-empty string reason. On a non-Linux OS the reason must mention Linux, so the message that reaches the user explains why instead of failing mysteriously. The test skips on Linux hosts with bwrap, since there the case cannot arise; the has("linux") = 0 variant is covered by a test in agent-sandbox_spec.lua that fakes vim.fn.has.'),
    ...code('lua', r'tests/agent-failclosed_spec.lua · lines 37-50', r'''
  it("a platform without a backend refuses and wrap() returns nil plus a reason", function()
    if native_backend then
      return skip("a bwrap backend exists here (the has('linux') = 0 case is in agent-sandbox_spec)")
    end
    neutral(function()
      local cmd = { "claude", "--dangerously-skip-permissions" }
      local got, reason = sandbox.wrap(cmd, vim.uv.cwd(), vim.uv.cwd())
      H.is_nil(got)
      H.ok(type(reason) == "string" and reason ~= "", "a reason comes with the refusal")
      if H.os ~= "linux" then
        H.has(reason, "Linux")
      end
    end)
  end)'''),
    ...sec(r'only real booleans opt out'),
    ...para('--', r'This is the security-relevant test. Lua and Vim script disagree about truthiness: 0, 1, "false" and "true" all look plausible as a user setting. The test sets both switches to each of those four values and requires the status to stay at the default (bwrap or refused). Only the boolean false in sandbox, and only the boolean true in allow_unsandboxed, change anything. After that it checks the two real opt-outs: sandbox = false returns the very same command table and the status becomes unsandboxed, and where there is no backend allow_unsandboxed = true does the same with via = allow_unsandboxed. A mistyped config can therefore never switch the protection off by accident.'),
    ...code('lua', r'tests/agent-failclosed_spec.lua · lines 52-73', r'''
  it("only the two explicit booleans lead to an unsandboxed run", function()
    local cmd = { "claude" }
    for _, v in ipairs({ 0, 1, "false", "true" }) do
      with_g("xynovim_99_sandbox", v, function()
        with_g("xynovim_99_allow_unsandboxed", v, function()
          H.eq(native_backend and "bwrap" or "refused", sandbox.status().mode, vim.inspect(v))
        end)
      end)
    end
    with_g("xynovim_99_sandbox", false, function()
      H.ok(sandbox.wrap(cmd, vim.uv.cwd(), vim.uv.cwd()) == cmd, "sandbox = false returns the command")
      H.eq("unsandboxed", sandbox.status().mode)
    end)
    if not native_backend then
      with_g("xynovim_99_sandbox", nil, function()
        with_g("xynovim_99_allow_unsandboxed", true, function()
          H.ok(sandbox.wrap(cmd, vim.uv.cwd(), vim.uv.cwd()) == cmd, "allow_unsandboxed returns the command")
          H.eq("allow_unsandboxed", sandbox.status().via)
        end)
      end)
    end
  end)'''),
    ...sec(r'the guarded provider'),
    ...para('--', r'The second describe checks the integration point. The 99 plugin has a provider override named Guarded. The test loads the plugin through lazy (and skips if it is not installed), takes the override from the plugin state, and calls make_request with a stub observer. vim.notify and vim.system are replaced by recorders. After the call it requires that nothing was spawned, exactly one completion was delivered, its status is failed, its text mentions xynovim_99_allow_unsandboxed (so the message tells you how to opt in), and an ERROR-level notification was shown. The test restores both stubs before asserting, so a failing assertion cannot leave the editor with a fake vim.system.'),
    ...code('lua', r'tests/agent-failclosed_spec.lua · lines 76-118', r'''
describe("the 99 provider", function()
  it("is guarded: make_request refuses where no sandbox exists", function()
    local ok, _99 = pcall(require, "99")
    if not ok then
      return skip("99 is not installed (run the bootstrap)")
    end
    if native_backend then
      return skip("a bwrap backend exists here (the refusal is tested in agent-99-guard_spec)")
    end
    local lazy = require("lazy")
    lazy.load({ plugins = { "99" } })
    local Guarded = _99.__get_state().provider_override
    neutral(function()
      local notes, done = {}, {}
      local orig_notify = vim.notify
      vim.notify = function(msg, level)
        notes[#notes + 1] = { msg, level }
      end
      local spawned = false
      local orig_system = vim.system
      vim.system = function(...)
        spawned = true
        return orig_system(...)
      end
      local ok2, err = pcall(function()
        Guarded:make_request("q", { cancel = function() end }, {
          on_start = function() end,
          on_stdout = function() end,
          on_stderr = function() end,
          on_complete = function(status, text)
            done[#done + 1] = { status, text }
          end,
        })
      end)
      vim.notify, vim.system = orig_notify, orig_system
      assert(ok2, err)
      H.eq(false, spawned, "nothing was spawned")
      H.eq(1, #done)
      H.eq("failed", done[1][1])
      H.has(done[1][2], "xynovim_99_allow_unsandboxed")
      H.eq(vim.log.levels.ERROR, notes[1][2])
    end)
  end)'''),
    ...sec(r'trade-offs'),
    blank,
    ...pt('--', r'Safety over convenience', r'on macOS and Windows the agent does not run at all unless the user sets allow_unsandboxed. The spec makes sure this stays so.'),
    ...pt('--', r'Tests that skip are explicit', r'each skip names the other spec that holds the case it cannot reach (agent-sandbox_spec for has("linux") = 0, agent-99-guard_spec for the Linux refusal).'),
    ...sec(r'history'),
    blank,
    ...pt('--', r'440d781 (2026-10-16)', r'the fail-closed commit. Its diffstat adds 99 lines to agent-99-guard_spec.lua and 92 to agent-sandbox_spec.lua; this file followed.'),
    ...pt('--', r'ff1c8fa (2026-10-16)', r'Windows and macOS portability, the platforms workflow that runs this spec.'),
    ...pt('--', r'7025437 (2026-10-16)', r'"the checkpoint and argument tests run with the explicit sandbox opt-out (CI has no bwrap)": the other specs now use the opt-out this file defines the rules for.'),
  ],
);
