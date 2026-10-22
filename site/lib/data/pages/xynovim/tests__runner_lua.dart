import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/tests/runner.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'runner.lua — one spec file, one nvim, the whole config loaded'),
    cm('--', r'the 107-line entry point that scripts/test.sh starts once per spec'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'per-spec entry point: preload helpers, honour OS headers, run the harness, print one result line'),
    kv(r'language', r'Lua, run with nvim --headless -S tests/runner.lua'),
    kv(r'size', r'107 lines, 3 commits: 2026-10-13 (two) and 2026-10-16'),
    kv(r'input', r'XYNO_SPEC=<spec file>, set by scripts/test.sh'),
    kv(r'output', r'ok/FAIL/SKIP per test, then XYNO_RESULT passed=N failed=N skipped=N'),
    ...sec(r'why this file exists'),
    ...para('--', r'The test suite of this configuration does not test a library. It tests an editor that has to start with all of its plugins, so the unit under test is a whole running Neovim. runner.lua is the small program that turns such an nvim into a test process. scripts/test.sh launches one headless nvim per spec file with XYNO_SPEC pointing at the spec, the full config loads as it would for a user, and this file takes over once the editor is up. It was added in the first test commit, cf2b8e1 (2026-10-13, "Test infrastructure: scripts/test.sh (per-file headless nvim, timeouts, isolation, coverage)"), together with the harness, the helpers and the coverage hook.'),
    ...para('--', r'The header comment states the whole contract in six lines: one spec per process, one line per test, a final XYNO_RESULT line that the shell script parses, and an exit code that is 0 only when nothing failed.'),
    ...code('lua', r'tests/runner.lua · lines 1-6', r'''
-- Runs ONE spec file inside this nvim (the full config is loaded). Started by
-- scripts/test.sh as
--   nvim --headless -S tests/runner.lua      with XYNO_SPEC=<spec file>
-- Output: one line per test (ok / FAIL / SKIP) and a final
--   XYNO_RESULT passed=N failed=N skipped=N
-- line that scripts/test.sh parses. Exit code is 0 only without failures.'''),
    ...sec(r'wiring the helpers in under a private name'),
    ...para('--', r'Specs do local H = require("xynotest.helpers"). The prefix is deliberate, and the comment above the loop gives the reason: a module called tests.helpers would also match other plugins that ship a lua/tests/ directory, because lazy.nvim loader runs before package.path is consulted. Instead of putting tests/ on the path, the runner registers package.preload entries that dofile the two files from the repo. The repo root is derived from the runner own location with two dirname calls, so the suite works from any checkout path.'),
    ...code('lua', r'tests/runner.lua · lines 11-18', r'''
local repo = vim.fs.dirname(vim.fs.dirname(debug.getinfo(1, "S").source:sub(2)))
-- "tests.*" would also match other plugins' lua/tests/ modules (lazy's loader
-- runs before package.path), so the helpers live under a private name.
for _, name in ipairs({ "helpers", "harness" }) do
  package.preload["xynotest." .. name] = function()
    return dofile(repo .. "/tests/" .. name .. ".lua")
  end
end'''),
    ...para('--', r'There is a second platform detail on top. Windows may have no HOME, and several specs read HOME, so the runner fills it from vim.uv.os_homedir() before anything else. That line arrived with the Windows and macOS work (ff1c8fa, 2026-10-16).'),
    ...code('lua', r'tests/runner.lua · lines 7-10', r'''
local spec = assert(vim.env.XYNO_SPEC, "XYNO_SPEC not set")
if vim.fn.has("win32") == 1 and (vim.env.HOME or "") == "" then
  vim.env.HOME = vim.uv.os_homedir() -- Windows has USERPROFILE; several specs read $HOME
end'''),
    ...sec(r'finish: result first, cleanup second'),
    ...para('--', r'finish() is the one exit door. The order of its steps is the interesting part. The XYNO_RESULT line is written and flushed before cleanup runs. The comment explains why: a cleanup that hangs, for example a language server that does not die, must not turn a finished spec into a timeout. test.sh gives the process a grace period after the result line and then kills it, so the verdict has already been delivered by then.'),
    ...para('--', r'After the result, cleanup runs inside pcall: helpers.cleanup stops LSP clients, kills jobs and tmux servers and deletes temp dirs. If coverage is on (XYNO_COV_OUT set and the hook installed the global), the coverage dump is written next. Finally cquit 1 on any failure, qa! otherwise. cquit gives a real non-zero exit status, which :q would not.'),
    ...code('lua', r'tests/runner.lua · lines 20-38', r'''
local function finish(n)
  -- The result goes out first: a cleanup that hangs (a language server that does
  -- not die) must not turn a finished spec into a timeout; test.sh gives the
  -- process a grace period after the result line, then kills it.
  io.stdout:write(("XYNO_RESULT passed=%d failed=%d skipped=%d\n"):format(n.passed, n.failed, n.skipped))
  io.stdout:flush()
  local ok, helpers = pcall(function()
    return package.loaded["xynotest.helpers"]
  end)
  if ok and helpers then
    pcall(helpers.cleanup)
  end
  if vim.env.XYNO_COV_OUT and _G.__xyno_cov then
    pcall(_G.__xyno_cov.dump, vim.env.XYNO_COV_OUT)
  end
  if n.failed > 0 then
    vim.cmd("cquit 1")
  else
    vim.cmd("qa!")'''),
    ...sec(r'operating-system headers'),
    ...para('--', r'The platforms work added a small declarative mechanism. A spec can put a line like the following in its first 15 lines and the runner will skip the whole file on any other OS with the stated reason, printed as a SKIP line, instead of letting it fail. Only the first 15 lines are scanned, which keeps the cost trivial and prevents a stray comment further down from being read as a header. The list is comma separated, the parenthesised text becomes the reason, and the reason is reformatted into a sentence of the form needs linux or macos, this is windows.'),
    ...code('lua', r'tests/runner.lua · lines 47-68', r'''
--- A spec may declare where it can run in a header line (first 15 lines):
---   -- xyno-os: linux,macos (why it cannot run elsewhere)
--- On any other platform the whole file is skipped with that reason, printed as a SKIP line.
local function os_skip_reason()
  local n = 0
  for line in io.lines(spec) do
    n = n + 1
    local list, why = line:match("^%-%- xyno%-os: *([%a,]+) *(.*)$")
    if list then
      for os_name in list:gmatch("[^,]+") do
        if os_name == platform() then
          return nil
        end
      end
      why = why:gsub("^%((.*)%)$", "%1")
      return ("needs %s, this is %s%s"):format(list:gsub(",", " or "), platform(), why ~= "" and (": " .. why) or "")
    end
    if n >= 15 then
      break
    end
  end
end'''),
    ...sec(r'main: load the spec, count the outcomes'),
    ...para('--', r'main() installs the harness globals (describe, it and friends), checks the OS header, and then dofiles the spec inside xpcall with a traceback. Three outcomes are distinguished. A skip raised at load time through helpers.skip_file is recognised by harness.is_skip and reported as a one-file SKIP. Any other error while loading is reported as FAIL loading <spec> with the traceback indented, as one failed test, so a syntax error in a spec can never look like a pass. Otherwise harness.run() executes the registered tests and its counts go to finish.'),
    ...code('lua', r'tests/runner.lua · lines 70-92', r'''
local function main()
  local harness = require("xynotest.harness")
  harness.install()
  local why = os_skip_reason()
  if why then
    io.stdout:write(("SKIP %s (%s)\n"):format(vim.fs.basename(spec), why))
    return finish({ passed = 0, failed = 0, skipped = 1 })
  end
  -- A spec may bail out at load time with helpers.skip_file(reason).
  local ok, err = xpcall(dofile, debug.traceback, spec)
  if not ok then
    if harness.is_skip(err) then
      io.stdout:write(("SKIP %s (%s)\n"):format(vim.fs.basename(spec), err.reason))
      return finish({ passed = 0, failed = 0, skipped = 1 })
    end
    io.stdout:write("FAIL loading " .. spec .. "\n")
    for l in tostring(err):gmatch("[^\n]+") do
      io.stdout:write("       " .. l .. "\n")
    end
    return finish({ passed = 0, failed = 1, skipped = 0 })
  end
  finish(harness.run())
end'''),
    ...sec(r'when it starts'),
    ...para('--', r'The runner is sourced with -S before the config has finished starting, so it cannot run the tests directly. It registers a one-shot VimEnter autocmd and then uses vim.schedule, which means the tests start only after the config own VimEnter work is done. The comment says it plainly: the config VimEnter work must be done before a test looks at it. Any error escaping main is printed as FAIL runner and the process ends with cquit 2, a different code from a test failure, so scripts/test.sh can tell a broken runner from a failing spec.'),
    ...code('lua', r'tests/runner.lua · lines 94-107', r'''
-- The config's own VimEnter work must be done before a test looks at it.
vim.api.nvim_create_autocmd("VimEnter", {
  once = true,
  callback = function()
    vim.schedule(function()
      local ok, e = xpcall(main, debug.traceback)
      if not ok then
        io.stdout:write("FAIL runner: " .. tostring(e) .. "\n")
        io.stdout:flush()
        vim.cmd("cquit 2")
      end
    end)
  end,
})'''),
    ...sec(r'design decisions'),
    blank,
    ...pt('--', r'One process per file', r'a spec can leave LSP clients, global options, autocmds and buffers behind. Giving every file its own nvim means the only isolation logic needed is process exit, and tests/harness.lua says so itself: there is no isolation logic there.'),
    ...pt('--', r'Counts are printed, not returned', r'the output contract is text so that test.sh, the CI log and a human reading a terminal all see the same thing.'),
    ...pt('--', r'Skips are first class', r'SKIP is a third outcome next to ok and FAIL. A machine without bwrap, tmux or rust-analyzer still gets an honest green run, and the reason is on the line.'),
    ...sec(r'how it is tested'),
    ...para('--', r'harness_spec.lua exercises the helpers rather than this file, and smoke_spec.lua is the proof that the runner plus the config start clean: if the runner did not wait for VimEnter, its checks on messages and the colourscheme would fail. scripts-portable_spec.lua covers the xyno-os header handling. The runner itself is tested by every other spec running through it.'),
    ...sec(r'history'),
    blank,
    ...pt('--', r'cf2b8e1 (2026-10-13)', r'created with scripts/test.sh, the harness and the first specs.'),
    ...pt('--', r'b2fee5c (2026-10-13)', r'the 22 feature specs commit; its message lists "per-spec timeout, exit-hang fix (bufferline tabline at cleanup), result line before cleanup", which is the ordering in finish().'),
    ...pt('--', r'ff1c8fa (2026-10-16)', r'"Windows and macOS: portability fixes, PowerShell bootstrap, portable test runner, OS-aware skips, platforms workflow". This commit added the HOME fallback and the xyno-os header handling (the diff adds both).'),
  ],
);
