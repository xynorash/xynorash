import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-sandbox.nvim/tests/setup_spec.lua',
  lines: [
    cm('--', r'──────────────────────────────────────────'),
    cm('--', r'setup_spec.lua — options, commands, keymap and run()'),
    cm('--', r'the surface of the plugin, including the refusal as a user would see it'),
    cm('--', r'──────────────────────────────────────────'),
    kv(r'role', r'specs for setup(), the two commands, the keymap and run()'),
    kv(r'language', r'Lua'),
    kv(r'size', r'115 lines, 10 tests in 3 groups'),
    kv(r'requires', r'bwrap only for the last test, which skips without it'),
    kv(r'history', r'added in 03b99f2 (2026-10-22, Add specs, a smoke test and CI)'),
    ...sec(r'why this file exists'),
    ...para('--', r'The big sandbox spec tests the command builder. This one tests what a user touches: the '
        r'defaults, the commands, the keymap, the status message and the launcher. It is the place '
        r'where the behaviour that is visible in the editor, a notification, a split, a job id, is '
        r'pinned.'),
    ...code('lua', r'tests/setup_spec.lua · lines 1-11', r'''
-- setup(), the commands, the keymap and run().
local H = require("xynotest.helpers")
local sb = require("xyno_sandbox")

local saved = vim.deepcopy(sb.config)
after_each(function()
  sb.config = vim.deepcopy(saved)
  pcall(vim.api.nvim_del_user_command, "XynoSandboxStatus")
  pcall(vim.api.nvim_del_user_command, "XynoSandboxRun")
  pcall(vim.keymap.del, "n", "<leader>zs")
end)
'''),
    ...para('--', r'Every test starts from a deep copy of the configuration taken at load, and after each '
        r'test the commands and the keymap that setup may have registered are deleted, in pcall so '
        r'that a test that did not register them does not fail the cleanup. That is the isolation: '
        r'the module is a singleton, and its state lives in config and in the global command table.'),
    ...sec(r'defaults and registration'),
    ...code('lua', r'tests/setup_spec.lua · lines 13-43', r'''
describe("setup", function()
  it("keeps defaults without options: sandboxed policy, no keymaps, commands on", function()
    H.eq(true, sb.config.sandbox)
    H.eq(false, sb.config.allow_unsandboxed)
    H.eq(false, sb.config.keymaps)
    H.eq(true, sb.config.commands)
  end)

  it("registers :XynoSandboxStatus and :XynoSandboxRun", function()
    sb.setup({})
    H.eq(2, vim.fn.exists(":XynoSandboxStatus"))
    H.eq(2, vim.fn.exists(":XynoSandboxRun"))
  end)

  it("commands = false registers no commands", function()
    sb.setup({ commands = false })
    H.eq(0, vim.fn.exists(":XynoSandboxStatus"))
  end)

  it("sets no global keymap by default and maps status only when asked", function()
    sb.setup({})
    H.eq("", vim.fn.maparg("<leader>zs", "n"))
    sb.setup({ keymaps = { status = "<leader>zs" } })
    H.ok(vim.fn.maparg("<leader>zs", "n", false, true).lhs, "keymap set")
  end)

  it("sandbox = false and allow_unsandboxed are read by status()", function()
    sb.setup({ sandbox = false })
    H.eq("sandbox=false", sb.status().via)
  end)
end)
'''),
    ...para('--', r'The defaults are asserted value by value: sandbox true, allow_unsandboxed false, keymaps '
        r'false, commands true. Registration is checked with vim.fn.exists, where 2 means the '
        r'command is defined. commands = false registers nothing. The keymap test checks the '
        r'absence of a mapping before it asks for one, and then checks the mapping through maparg, '
        r'so a leftover from an earlier test cannot make it pass. The last test shows that setup '
        r'merges the option into the policy that status reads.'),
    ...sec(r'the status message'),
    ...code('lua', r'tests/setup_spec.lua · lines 45-55', r'''
describe(":XynoSandboxStatus", function()
  it("notifies one line that says refused, sandboxed or unsandboxed", function()
    sb.setup({})
    local got = H.capture_notify(function()
      vim.cmd("XynoSandboxStatus")
    end)
    H.eq(1, #got)
    H.match(got[1][1], "xyno-sandbox: ", true)
    H.ok(got[1][1]:find("sandboxed") or got[1][1]:find("refused") or got[1][1]:find("UNSANDBOXED"), got[1][1])
  end)
end)
'''),
    ...para('--', r'The command must produce exactly one notification, with the plugin’s prefix and one of '
        r'the three words: sandboxed, refused or UNSANDBOXED. The assertion accepts any of the '
        r'three because the test runs on any machine; the exact wording is covered elsewhere.'),
    ...sec(r'run()'),
    ...code('lua', r'tests/setup_spec.lua · lines 57-81', r'''
describe("run()", function()
  local function no_bwrap()
    local old = vim.env.PATH
    vim.env.PATH = "/nonexistent-xyno-path"
    return function()
      vim.env.PATH = old
    end
  end

  it("refuses with a one-line error and starts no job when no sandbox exists", function()
    sb.setup({})
    local restore = no_bwrap()
    local wins = #vim.api.nvim_list_wins()
    local job
    local got = H.capture_notify(function()
      job = sb.run({ "true" }, { project = H.tmpdir(), tmp_dir = H.tmpdir() })
    end)
    restore()
    H.eq(nil, job)
    H.eq(1, #got)
    H.eq(vim.log.levels.ERROR, got[1][2])
    H.match(got[1][1], "refused to start true", true)
    H.no_match(got[1][1], "stack traceback", true)
    H.eq(wins, #vim.api.nvim_list_wins(), "no terminal split was opened")
  end)
'''),
    ...para('--', r'This is the user-facing refusal. PATH is emptied for the duration of the call and '
        r'restored right after, the number of windows is recorded, and run is called with a scratch '
        r'project and tmp directory. The test then asserts that no job was started, that exactly '
        r'one notification was shown with the ERROR level, that the text says refused to start '
        r'true, that it carries no stack traceback, and that the window count did not change, which '
        r'proves that no terminal split was opened.'),
    ...code('lua', r'tests/setup_spec.lua · lines 83-101', r'''
  it("rejects an empty command", function()
    local got = H.capture_notify(function()
      H.eq(nil, sb.run({}))
    end)
    H.eq(vim.log.levels.ERROR, got[1][2])
  end)

  it("sandbox = false runs the command in a terminal and warns", function()
    sb.setup({ sandbox = false })
    local job
    local got = H.capture_notify(function()
      job = sb.run({ "echo", "hello" }, { project = H.tmpdir(), tmp_dir = H.tmpdir() })
    end)
    H.ok(job and job > 0, "job started")
    H.eq(vim.log.levels.WARN, got[1][2])
    H.match(got[1][1], "WITHOUT a sandbox", true)
    vim.fn.jobwait({ job }, 5000)
    vim.cmd("silent! bwipeout!")
  end)
'''),
    ...para('--', r'An empty command table is rejected with an error. The unsandboxed path starts a real '
        r'terminal job running echo, asserts that a positive job id came back, that the '
        r'notification is a WARN containing WITHOUT a sandbox, waits for the job and wipes the '
        r'buffer.'),
    ...code('lua', r'tests/setup_spec.lua · lines 103-114', r'''
  it("runs a command inside a real sandbox when bwrap works", function()
    H.need_sandbox()
    sb.setup({})
    local project, tmp = H.tmpdir(), H.tmpdir()
    local prev = vim.fn.chdir(project)
    local job = sb.run({ "bash", "-c", "echo hi > made-inside.txt" }, { project = project, tmp_dir = tmp })
    vim.fn.chdir(prev)
    H.ok(job and job > 0, "job started")
    H.eq(0, vim.fn.jobwait({ job }, 20000)[1])
    H.eq(1, vim.fn.filereadable(project .. "/made-inside.txt"))
    vim.cmd("silent! bwipeout!")
  end)
'''),
    ...para('--', r'The last test is the only one here that needs a working sandbox. It calls need_sandbox, '
        r'which skips the test with a message when bwrap is missing or cannot create a namespace on '
        r'this machine. Then it changes the directory to a fresh project, runs bash -c echo hi '
        r'inside the sandbox, waits for the job, and asserts exit code 0 and that the file exists '
        r'in the project. It is the one end-to-end proof that a wrapped command really runs and '
        r'that the project is writable.'),
    ...sec(r'history'),
    ...pt('--', r'03b99f2', r'2026-10-22: the specs, the smoke test and the CI arrive together.'),
  ],
);
