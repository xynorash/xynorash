import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-sandbox.nvim/lua/xyno_sandbox/run.lua',
  lines: [
    cm('--', r'──────────────────────────────────────────'),
    cm('--', r'run.lua — the user-facing half: describe, run in a terminal split, commands'),
    cm('--', r'refuses with one error line; warns on every explicitly unsandboxed run'),
    cm('--', r'──────────────────────────────────────────'),
    kv(r'role', r'the terminal launcher, the two user commands and the optional keymap'),
    kv(r'language', r'Lua'),
    kv(r'size', r'69 lines'),
    kv(r'loaded by', r'init.lua: setup() calls register, run() forwards here'),
    kv(r'history', r'403b9b0 (2026-10-22)'),
    ...sec(r'why this file exists'),
    ...para('--', r'init.lua decides and builds; this file talks to the user. The split exists so that the '
        r'policy module has no UI in it and can be called from any code, while everything that '
        r'notifies, opens a window or registers a command lives here. In xynovim the call to wrap was '
        r'made from lua/plugins/ninety-nine.lua; this file is the generic launcher that the extracted plugin adds. The first comment says '
        r'what it holds.'),
    ...code('lua', r'lua/xyno_sandbox/run.lua · lines 1-6', r'''
-- Commands, keymaps and the terminal launcher of xyno-sandbox.
local M = {}

local function notify(msg, level)
  vim.notify("xyno-sandbox: " .. msg, level or vim.log.levels.INFO)
end
'''),
    ...sec(r'describing the state in one line'),
    ...code('lua', r'lua/xyno_sandbox/run.lua · lines 8-17', r'''
--- One-line description of how an agent would run here.
function M.describe()
  local st = require("xyno_sandbox").status()
  if st.mode == "bwrap" then
    return "sandboxed (bubblewrap)"
  elseif st.mode == "unsandboxed" then
    return "UNSANDBOXED (" .. st.via .. "): " .. st.reason
  end
  return "refused: " .. st.reason
end
'''),
    ...para('--', r'describe turns the result of status() into a sentence. The wording is chosen for clarity '
        r'under stress: the sandboxed case is quiet, the unsandboxed case is in capitals with the '
        r'way it was chosen (the option name) and the reason, and the refused case says refused and '
        r'why. The status command and the keymap both print this. The setup spec checks that '
        r'exactly one notification is produced and that it contains one of the three words.'),
    ...sec(r'run: the single place where an agent can start'),
    ...code('lua', r'lua/xyno_sandbox/run.lua · lines 19-34', r'''
--- Start `cmd` (string[]) inside the sandbox in a terminal split. Refuses with
--- a one-line error notification when no sandbox is available and no explicit
--- opt-out is set; warns on every explicitly unsandboxed run.
--- @param cmd string[]
--- @param opts? { project?: string, tmp_dir?: string }
--- @return integer? job id
function M.run(cmd, opts)
  opts = opts or {}
  if type(cmd) ~= "table" or #cmd == 0 then
    notify("no command given", vim.log.levels.ERROR)
    return nil
  end
  local sandbox = require("xyno_sandbox")
  local project = opts.project or vim.uv.cwd()
  local tmp_dir = opts.tmp_dir or (vim.fn.stdpath("cache") .. "/xyno-sandbox")
  vim.fn.mkdir(tmp_dir, "p")
'''),
    ...para('--', r'The function validates the command first: it must be a non-empty table, otherwise an '
        r'error notification and nil. The project defaults to Neovim’s cwd and the scratch '
        r'directory to a folder in Neovim’s cache path, which is created on the spot. Then the one '
        r'important call is made: sandbox.wrap. Everything that follows depends on its result.'),
    ...code('lua', r'lua/xyno_sandbox/run.lua · lines 35-40', r'''
  local wrapped, err = sandbox.wrap(cmd, project, tmp_dir)
  if not wrapped then
    local hint = ". Set allow_unsandboxed = true in setup() to run it anyway."
    notify("refused to start " .. cmd[1] .. ": " .. tostring(err) .. hint, vim.log.levels.ERROR)
    return nil
  end
'''),
    ...para('--', r'When wrap returns nil, run notifies an error that names the command, the reason and the '
        r'way out, and returns nil. No window has been opened and no job created, which the spec '
        r'asserts by counting windows before and after and by checking that the message contains no '
        r'stack traceback. The hint in the message mentions allow_unsandboxed, which is the option '
        r'that applies to the no-backend case; sandbox = false is not mentioned, so the deliberate '
        r'opt-out is something the user has to know about.'),
    ...code('lua', r'lua/xyno_sandbox/run.lua · lines 41-43', r'''
  if sandbox.status().mode == "unsandboxed" then
    notify("running " .. cmd[1] .. " WITHOUT a sandbox (" .. sandbox.status().reason .. ")", vim.log.levels.WARN)
  end
'''),
    ...para('--', r'An explicit opt-out is never silent. If the status is unsandboxed, whichever option '
        r'caused it, a warning is shown naming the command and the reason before the terminal '
        r'opens. The spec checks that the level is WARN and that the text says WITHOUT a sandbox.'),
    ...code('lua', r'lua/xyno_sandbox/run.lua · lines 44-50', r'''
  vim.cmd("botright new")
  local job = vim.fn.jobstart(wrapped, { term = true })
  if job <= 0 then
    notify("could not start " .. cmd[1], vim.log.levels.ERROR)
    return nil
  end
  return job
'''),
    ...para('--', r'Only now does the launcher open a bottom split and start the wrapped command as a '
        r'terminal job. A job id that is not positive is reported as an error. The terminal is the '
        r'interface: the agent is an interactive program and gets a real pty. The agent talks to a '
        r'pty created by the terminal job, and the --new-session flag from init.lua keeps it from '
        r'having Neovim’s controlling terminal.'),
    ...sec(r'registering the surface'),
    ...code('lua', r'lua/xyno_sandbox/run.lua · lines 53-67', r'''
function M.register(cfg)
  if cfg.commands then
    vim.api.nvim_create_user_command("XynoSandboxStatus", function()
      notify(M.describe())
    end, { desc = "Show how an agent would run (bubblewrap, unsandboxed or refused)" })
    vim.api.nvim_create_user_command("XynoSandboxRun", function(c)
      M.run(c.fargs)
    end, { nargs = "+", complete = "shellcmd", desc = "Run a command inside the bubblewrap sandbox" })
  end
  if type(cfg.keymaps) == "table" and cfg.keymaps.status then
    vim.keymap.set("n", cfg.keymaps.status, function()
      notify(M.describe())
    end, { desc = "Sandbox status" })
  end
end
'''),
    ...para('--', r'The commands are optional through the commands option. XynoSandboxStatus prints the '
        r'description. XynoSandboxRun takes one or more arguments, with shell command completion, '
        r'and splits them on whitespace, which is what the README warns about with its '
        r'backslash-space note; it passes the argument list straight to run, so there is no shell '
        r'involved and no quoting trouble beyond the split. The keymap exists only if keymaps is a '
        r'table with a status entry, and it is a normal-mode map to the same description. Nothing '
        r'is mapped by default.'),
    ...sec(r'design notes'),
    ...pt('--', r'One entry point for starting', r'any code that wants to start an agent calls run or wraps with wrap and starts it itself; '
        r'the README shows both. Only through these paths is the policy applied. A job started some '
        r'other way is not covered by this plugin.'),
    ...pt('--', r'Errors as messages', r'refusals are notifications with a level, not Lua errors, so a keymap press never produces '
        r'a stack trace. The spec has an explicit no-traceback assertion.'),
    ...pt('--', r'The wrapper is returned, not run', r'wrap hands back an argument vector, so a caller can use vim.system, jobstart or a test.'),
    ...sec(r'tested by'),
    ...para('--', r'tests/setup_spec.lua, the run() group: a refusal with no sandbox, an empty command, the '
        r'unsandboxed warning, and a real sandboxed command that writes a file in the project.'),
    ...sec(r'history'),
    ...pt('--', r'403b9b0', r'2026-10-22, Add the bubblewrap sandbox wrapper, together with init.lua.'),
  ],
);
