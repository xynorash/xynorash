import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-clipboard.nvim/tests/run.lua',
  lines: [
    cm('--', r'──────────────────────────────────────────'),
    cm('--', r'run.lua — the test entry point, nvim -l tests/run.lua'),
    cm('--', r'discovers specs, skips by platform, prints a RESULT line, sets the exit code'),
    cm('--', r'──────────────────────────────────────────'),
    kv(r'role', r'headless runner for every tests/specs/*_spec.lua'),
    kv(r'language', r'Lua, run with nvim -l'),
    kv(r'size', r'63 lines'),
    kv(r'history', r'added in 46a5b14, RESULT prefix added in b162212 (both 2026-10-22)'),
    ...sec(r'why this file exists'),
    ...para('--', r'A plugin test suite needs one command that works the same on a laptop and in CI. Here '
        r'that is nvim -l tests/run.lua, which runs a Lua file in Neovim’s headless mode with no '
        r'user config. The file has to do four things: make the plugin loadable, hand the specs '
        r'their helpers, run them, and turn the outcome into an exit code. In xynovim the same job '
        r'was done by tests/runner.lua and a shell script that started one nvim per spec file; this '
        r'runner puts all specs in one process.'),
    ...sec(r'making the plugin loadable'),
    ...code('lua', r'tests/run.lua · lines 6-13', r'''
-- and is skipped whole on other platforms.
local root = vim.fs.dirname(vim.fs.dirname(debug.getinfo(1, "S").source:sub(2)))
root = vim.fn.fnamemodify(root, ":p"):gsub("/$", "")
vim.opt.runtimepath:prepend(root)
package.path = root .. "/lua/?.lua;" .. root .. "/lua/?/init.lua;" .. package.path
package.preload["xynotest.helpers"] = function()
  return dofile(root .. "/tests/helpers.lua")
end
'''),
    ...para('--', r'The root is computed from the location of the running script, two directories up, and '
        r'prepended to runtimepath and to package.path, so require("xyno_clipboard") resolves to '
        r'the checkout and not to anything installed. The helpers are registered as a preload under '
        r'the name xynotest.helpers, which is why the spec starts with require("xynotest.helpers"): '
        r'the specs never need a path to the test directory.'),
    ...sec(r'OS-aware skipping'),
    ...code('lua', r'tests/run.lua · lines 15-39', r'''
local harness = dofile(root .. "/tests/harness.lua")

local function platform()
  return vim.fn.has("win32") == 1 and "windows" or vim.fn.has("mac") == 1 and "macos" or "linux"
end

local function os_skip_reason(path)
  local n = 0
  for line in io.lines(path) do
    n = n + 1
    local list = line:match("^%-%- xyno%-os: *([%a,]+)")
    if list then
      for name in list:gmatch("[^,]+") do
        if name == platform() then
          return nil
        end
      end
      return ("needs %s, this is %s"):format(list:gsub(",", " or "), platform())
    end
    if n >= 15 then
      break
    end
  end
end

'''),
    ...para('--', r'os_skip_reason looks at the first 15 lines of a spec for a header of the form xyno-os, '
        r'followed by a comma-separated list of platforms. If the current platform is in the list, '
        r'the spec runs; otherwise the function returns a reason string that names what is needed '
        r'and what this is. platform() answers windows, macos or linux in that order of checks. The '
        r'clipboard spec declares linux, so on another system it is reported as SKIP with the '
        r'reason and the run still exits zero. This is the same mechanism xynovim introduced in '
        r'ff1c8fa (2026-10-16), the commit that added OS-aware skips and the portable runner.'),
    ...sec(r'running'),
    ...code('lua', r'tests/run.lua · lines 40-63', r'''
local specs = #arg > 0 and arg or vim.fn.glob(root .. "/tests/specs/*_spec.lua", true, true)
local total = { passed = 0, failed = 0, skipped = 0 }
for _, spec in ipairs(specs) do
  local why = os_skip_reason(spec)
  if why then
    print(("SKIP %s (%s)"):format(vim.fs.basename(spec), why))
    total.skipped = total.skipped + 1
  else
    harness.install()
    local ok, err = xpcall(dofile, debug.traceback, spec)
    if not ok then
      print("FAIL loading " .. spec .. "\n" .. tostring(err))
      total.failed = total.failed + 1
    else
      local n = harness.run(print)
      for k, v in pairs(n) do
        total[k] = total[k] + v
      end
    end
  end
end
require("xynotest.helpers").cleanup()
print(("RESULT passed=%d failed=%d skipped=%d"):format(total.passed, total.failed, total.skipped))
os.exit(total.failed > 0 and 1 or 0)
'''),
    ...para('--', r'Each spec is loaded with dofile under xpcall, so a spec that fails to load counts as a '
        r'failure and its traceback is printed instead of aborting the run. Between specs '
        r'harness.install is called, so every file starts with fresh describe and it globals. After '
        r'the last spec the temp directories made by the helpers are cleaned and the final line is '
        r'printed. The line begins with RESULT because b162212 changed it: a prefix makes the '
        r'summary easy to find with grep among the per-test lines. The exit code is 1 on any '
        r'failure and 0 otherwise, and that code is all CI looks at.'),
    ...sec(r'limits'),
    ...pt('--', r'No timeout', r'the runner has none of its own; the workflow bounds the job at 10 minutes.'),
    ...pt('--', r'No test filter', r'spec files may be listed on the command line, but not single tests.'),
  ],
);
