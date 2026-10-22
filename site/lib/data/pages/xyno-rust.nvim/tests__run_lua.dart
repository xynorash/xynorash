import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-rust.nvim/tests/run.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'run.lua - the whole test runner in ninety-five lines'),
    cm('--', r'one headless Neovim per spec, a RESULT line, an exit code'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'entry point of the test suite'),
    kv(r'language', r'Lua, executed with nvim -l'),
    kv(r'usage', r'nvim -l tests/run.lua  [spec file]'),
    kv(r'size', r'95 lines, added in 7c1d2d9 (2026-10-22); the idea comes from cf2b8e1 (2026-10-13) in xynovim'),
    ...sec(r'why this file exists'),
    ...para('--', r'A plugin test suite for Neovim has an unusual constraint: the code under test is the editor. A spec that opens buffers, starts a fake language server or defines autocommands leaves all of that behind, and the next spec inherits it. The runner’s answer is the most blunt and the most reliable one: every spec file gets a fresh Neovim process. The header says it in the first lines.'),
    ...code('lua', r'tests/run.lua · lines 1-15', r'''
-- Spec runner:  nvim -l tests/run.lua [spec file ...]
-- Without arguments every tests/*_spec.lua runs, each in its own headless nvim
-- (child processes of this one). With a file, that spec runs in this process.
-- Output: one line per test (ok / FAIL / SKIP) and a final
--   RESULT passed=N failed=N skipped=N
-- line. Exit code is 0 only without failures.
local here = vim.fs.dirname(debug.getinfo(1, "S").source:sub(2))
local repo = vim.fs.dirname(vim.fs.normalize(vim.fn.fnamemodify(here, ":p")))
local spec = arg and arg[1]

vim.o.swapfile = false
vim.opt.rtp:prepend(repo)
if vim.env.XYNO_TEST_RTP and vim.env.XYNO_TEST_RTP ~= "" then
  vim.opt.rtp:append(vim.env.XYNO_TEST_RTP) -- e.g. a directory holding parser/rust.so
end'''),
    ...sec(r'parent mode and child mode'),
    ...code('lua', r'tests/run.lua · lines 17-33', r'''
if not spec then
  local files = vim.fn.glob(repo .. "/tests/*_spec.lua", true, true)
  table.sort(files)
  local total = { passed = 0, failed = 0, skipped = 0 }
  for _, f in ipairs(files) do
    local r = vim.system({ vim.v.progpath, "-l", repo .. "/tests/run.lua", f }, { text = true }):wait(600000)
    io.stdout:write(r.stdout or "", r.stderr or "")
    for k in pairs(total) do
      total[k] = total[k] + (tonumber((r.stdout or ""):match("RESULT[^\n]-" .. k .. "=(%d+)")) or 0)
    end
    if r.code ~= 0 and not (r.stdout or ""):find("RESULT", 1, true) then
      total.failed = total.failed + 1
    end
  end
  io.stdout:write(("RESULT passed=%d failed=%d skipped=%d\n"):format(total.passed, total.failed, total.skipped))
  os.exit(total.failed > 0 and 1 or 0)
end'''),
    ...para('--', r'With no argument the process is the parent. It globs tests/*_spec.lua, sorts the files so output is stable, and runs each one as a child of this same binary (vim.v.progpath, so the Neovim that started the runner is the Neovim that runs the specs) with a ten minute timeout per file. It prints each child’s output once that child has finished (it waits on the process) and sums the passed, failed and skipped counts by parsing each child’s RESULT line. A child that exited non-zero without printing a RESULT line is counted as one failure. The final line has the same format, and the exit code is 1 on any failure.'),
    ...para('--', r'With an argument the same file is the child: it runs that one spec in the current process. Running a single spec while developing is therefore nvim -l tests/run.lua tests/rust-nav_spec.lua.'),
    ...sec(r'setup of a child'),
    ...code('lua', r'tests/run.lua · lines 35-40', r'''
package.path = repo .. "/lua/?.lua;" .. repo .. "/lua/?/init.lua;" .. package.path
for _, name in ipairs({ "helpers", "harness" }) do
  package.preload["xyno_rust_test." .. name] = function()
    return dofile(repo .. "/tests/" .. name .. ".lua")
  end
end'''),
    ...para('--', r'The module path is set up by hand so no plugin manager is involved: the repository lua directory is added to package.path, and the test support modules are registered in package.preload under the namespace xyno_rust_test, loading the files with dofile. The specs therefore write require("xyno_rust_test.helpers") and get tests/helpers.lua without that directory being on the runtimepath. The first lines of the file (11 to 15) also prepend the repository to the runtimepath, turn swap files off, and append XYNO_TEST_RTP, the hook the CI uses to supply the compiled parsers.'),
    ...sec(r'skipping by platform'),
    ...code('lua', r'tests/run.lua · lines 53-74', r'''
--- A spec may declare where it can run in a header line (first 15 lines):
---   -- xyno-os: linux,macos (why it cannot run elsewhere)
local function os_skip_reason()
  local current = vim.fn.has("win32") == 1 and "windows" or vim.fn.has("mac") == 1 and "macos" or "linux"
  local n = 0
  for line in io.lines(spec) do
    n = n + 1
    local list, why = line:match("^%-%- xyno%-os: *([%a,]+) *(.*)$")
    if list then
      for os_name in list:gmatch("[^,]+") do
        if os_name == current then
          return nil
        end
      end
      why = why:gsub("^%((.*)%)$", "%1")
      return ("needs %s, this is %s%s"):format(list:gsub(",", " or "), current, why ~= "" and (": " .. why) or "")
    end
    if n >= 15 then
      break
    end
  end
end'''),
    ...para('--', r'A spec may declare, in its first fifteen lines, a header comment of the form xyno-os with a list of operating systems and a reason. The runner reads that header before it loads the spec and, if the current system is not in the list, prints one SKIP line and finishes without running anything. The message is built to say why: "needs linux or macos, this is windows: the reason". This is the mechanism behind the README statement that some specs are skipped whole on some platforms. In this repository the supervision and statusline spec carries such a header (xyno-os: linux, with the reason POSIX signals and /proc on language server processes), and Linux is the only platform CI runs.'),
    ...sec(r'running and finishing'),
    ...code('lua', r'tests/run.lua · lines 42-51', r'''
local function finish(n)
  io.stdout:write(("RESULT passed=%d failed=%d skipped=%d\n"):format(n.passed, n.failed, n.skipped))
  io.stdout:flush()
  local helpers = package.loaded["xyno_rust_test.helpers"]
  if helpers then
    pcall(helpers.cleanup)
  end
  pcall(vim.cmd, "messages clear")
  vim.cmd(n.failed > 0 and "cquit 1" or "qa!")
end'''),
    ...code('lua', r'tests/run.lua · lines 76-95', r'''
local harness = require("xyno_rust_test.harness")
harness.install()
local why = os_skip_reason()
if why then
  io.stdout:write(("SKIP %s (%s)\n"):format(vim.fs.basename(spec), why))
  return finish({ passed = 0, failed = 0, skipped = 1 })
end
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
finish(harness.run())'''),
    ...para('--', r'finish prints the RESULT line, flushes stdout, asks the helpers module to clean up (pcall, since it may never have loaded), clears messages and leaves with qa! or cquit 1. The exit code of the child is the signal the parent uses. The ordering at the bottom is careful: harness.install() defines describe and it as globals before the spec is loaded; the OS check runs; then the spec is executed under xpcall with a traceback. A load error that is a skip (a spec calling skip at the top level when cargo or a parser is missing) becomes a SKIP line, and any other load error prints FAIL loading with the indented traceback and counts as one failure. Only then does harness.run() execute the registered tests.'),
    ...sec(r'design decisions'),
    ...pt('--', r'process per file', r'the cost is one Neovim start-up per file, the benefit is that no spec can poison another.'),
    ...pt('--', r'output is the protocol', r'the RESULT line is plain text, so a human, CI and the parent runner read the same thing.'),
    ...pt('--', r'no dependencies', r'no plenary, no busted: the framework is harness.lua and the runner is this file.'),
    ...pt('--', r'skips are first class', r'a missing tool is not a failure, but it is always printed.'),
    ...sec(r'history'),
    ...para('--', r'The runner has related ancestors in xynovim: scripts/test.sh and the tests harness added in cf2b8e1 (2026-10-13, "per-file headless nvim, timeouts, isolation, coverage"). In xynovim, ff1c8fa (2026-10-16, subject mentions "portable test runner, OS-aware skips") added scripts/test.lua, which is the closest ancestor of this runner. In this repository the namespace of the preloaded modules is xyno_rust_test.'),
  ],
);
