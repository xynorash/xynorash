import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-crates.nvim/tests/run.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'run.lua — nvim -l tests/run.lua'),
    cm('--', r'one headless Neovim per spec file, a RESULT line per child, an exit code for CI'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'spec runner and orchestrator, both parent and child in one file'),
    kv(r'language', r'Lua, run with nvim -l (no config, no plugins)'),
    kv(r'size', r'104 lines'),
    kv(r'inputs', r'XYNO_RUST_DIR, XYNO_IMPORTS_DIR, XYNO_TEST_RTP, optional spec path'),
    kv(r'output', r'ok / FAIL / SKIP per test, then RESULT passed=N failed=N skipped=N'),
    kv(r'history', r'xynovim had tests/runner.lua + scripts/test.sh (cf2b8e1, 2026-10-13); this is a merged rewrite (9d33ca7)'),
    ...sec(r'why this file exists'),
    ...para('--', r'xynovim’s test runner was two files: scripts/test.sh, a shell script that started one nvim --headless per spec with a hard timeout, an isolated state/cache/tmp and the real plugin install, and tests/runner.lua, which ran one spec inside that nvim and printed an XYNO_RESULT line for the script to parse. A plugin repository has no config to load, so most of that machinery is not needed. run.lua is the same idea shrunk to what remains and put into one Lua file, so there is no shell script to port to other platforms: Neovim itself is the only interpreter. The result line also lost the XYNO_ prefix.'),
    blank,
    ...para('--', r'The file plays both roles, selected by its first argument. Without one it is the parent: it finds every tests/*_spec.lua, runs each in its own child process, adds up the totals and sets the exit code. With a file it is the child: it runs exactly that spec in the current process. That is why the header says "each in its own headless nvim (child processes of this one)".'),
    blank,
    ...code('lua', r'tests/run.lua · lines 1-9', r'''
-- Spec runner:  nvim -l tests/run.lua [spec file ...]
-- Without arguments every tests/*_spec.lua runs, each in its own headless nvim
-- (child processes of this one). With a file, that spec runs in this process.
-- Output: one line per test (ok / FAIL / SKIP) and a final
--   RESULT passed=N failed=N skipped=N
-- line. Exit code is 0 only without failures.
local here = vim.fs.dirname(debug.getinfo(1, "S").source:sub(2))
local repo = vim.fs.dirname(vim.fs.normalize(vim.fn.fnamemodify(here, ":p")))
local spec = arg and arg[1]'''),
    ...sec(r'setting up the runtime path'),
    ...code('lua', r'tests/run.lua · lines 11-24', r'''
vim.o.swapfile = false
vim.cmd("filetype plugin on") -- an interactive nvim has it on; `nvim -l` does not
vim.opt.rtp:prepend(repo)
-- the plugins this one builds on: XYNO_RUST_DIR / XYNO_IMPORTS_DIR, else sibling checkouts
for _, dep in ipairs({ { "XYNO_RUST_DIR", "xyno-rust.nvim" }, { "XYNO_IMPORTS_DIR", "xyno-imports.nvim" } }) do
  local dir = vim.env[dep[1]]
  if not dir or dir == "" then
    dir = vim.fs.dirname(repo) .. "/" .. dep[2]
  end
  vim.opt.rtp:append(dir)
end
if vim.env.XYNO_TEST_RTP and vim.env.XYNO_TEST_RTP ~= "" then
  vim.opt.rtp:append(vim.env.XYNO_TEST_RTP) -- e.g. a directory holding parser/rust.so
end'''),
    ...para('--', r'The plugin under test is put first in the runtimepath, so require("xyno_crates") finds this checkout. Its two dependencies are appended: XYNO_RUST_DIR and XYNO_IMPORTS_DIR if set (the CI workflow sets them to shallow clones in RUNNER_TEMP), otherwise sibling directories of the repository, which is where a developer who keeps all the xyno plugins side by side already has them. XYNO_TEST_RTP adds one more directory, intended to hold parser/rust.so, since the tree-sitter scan needs the Rust parser and nvim -l loads no plugin manager to provide it. The line before the loop, filetype plugin on, has its own comment: nvim -l does not turn it on, and without it the FileType autocommands that the plugin relies on would never fire.'),
    blank,
    ...sec(r'the parent: one process per file'),
    ...code('lua', r'tests/run.lua · lines 26-42', r'''
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
    ...para('--', r'The parent sorts the files for a stable order, then for each starts vim.v.progpath, the same nvim binary, with -l and itself plus the spec as arguments, and waits up to ten minutes. The child’s stdout and stderr are echoed through, so a developer sees the per-test lines as they finish. The totals come from a pattern on the child’s RESULT line, one match per counter. If the child exited non-zero and printed no RESULT line at all, which means it crashed or was killed before it could report, the file counts as one failure. A child that says RESULT and exits 1 is not counted twice: its failures are already in its line. The final line has the same format as a child’s, so tools that read the last RESULT line work on both. Exit code 1 happens only if something failed; skips never fail the run.'),
    blank,
    ...para('--', r'Why one process per file? The modules guard their setup() with did_setup, the in-process language servers are registered once, and tests install stubs on shared module tables. A fresh process per file gives each spec a clean world, which is the isolation the harness refuses to provide itself.'),
    blank,
    ...sec(r'the child: preload, header check, run'),
    ...code('lua', r'tests/run.lua · lines 44-60', r'''
package.path = repo .. "/lua/?.lua;" .. repo .. "/lua/?/init.lua;" .. package.path
for _, name in ipairs({ "helpers", "harness" }) do
  package.preload["xyno_crates_test." .. name] = function()
    return dofile(repo .. "/tests/" .. name .. ".lua")
  end
end

local function finish(n)
  io.stdout:write(("RESULT passed=%d failed=%d skipped=%d\n"):format(n.passed, n.failed, n.skipped))
  io.stdout:flush()
  local helpers = package.loaded["xyno_crates_test.helpers"]
  if helpers then
    pcall(helpers.cleanup)
  end
  pcall(vim.cmd, "messages clear")
  vim.cmd(n.failed > 0 and "cquit 1" or "qa!")
end'''),
    ...para('--', r'package.path gets the repository’s lua/ directory, and the two test modules are registered with package.preload under the private prefix xyno_crates_test. The prefix is the lesson of a comment in the xynovim original: a module called tests.helpers would also match another plugin’s lua/tests/ directory, because a plugin manager’s loader can run before package.path. The specs say require("xyno_crates_test.helpers") and always get this repository’s file.'),
    blank,
    ...para('--', r'finish() prints the RESULT line first and cleans up afterwards. xynovim’s version explained why in a comment this copy lost: a cleanup that hangs (a language server that does not die) must not turn a finished spec into a timeout. Here the cleanup is pcall-protected, messages are cleared, and the exit is "cquit 1" for a failure or "qa!". cquit 1 gives the process exit status 1 for CI.'),
    blank,
    ...code('lua', r'tests/run.lua · lines 62-83', r'''
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
    ...para('--', r'A spec may restrict its platforms in a header comment: -- xyno-os: linux,macos (reason). The runner reads at most the first 15 lines, matches the list, and if the current OS is not in it returns the sentence "needs linux or macos, this is windows: reason" and the file is skipped before it loads. The mechanism came from xynovim’s cross-platform runs (ff1c8fa, 2026-10-16). None of the five spec files in this repository uses the header today; instead a few tests call H.known_issue({ "windows" }, ...) from tests/helpers.lua, which skips one test with a reason that names the CI run.'),
    blank,
    ...code('lua', r'tests/run.lua · lines 85-104', r'''
local harness = require("xyno_crates_test.harness")
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
    ...para('--', r'The last part loads the harness, installs the globals, honours the OS header, and runs the spec file under xpcall with debug.traceback. A load error is reported as "FAIL loading <file>" with the traceback indented, as a skip when a spec calls skip() at file level, and otherwise the harness runs the registered tests and finish() reports its counts.'),
    blank,
    ...sec(r'environment variables, in one place'),
    ...pt('--', r'XYNO_RUST_DIR, XYNO_IMPORTS_DIR', r'where the dependencies are, default next to this repository.'),
    ...pt('--', r'XYNO_TEST_RTP', r'one extra runtimepath entry, for parser/rust.so.'),
    ...pt('--', r'XYNO_SNACKS_DIR', r'read by crate-add_spec.lua for the real-picker test; skipped when absent. The runner does not touch it.'),
    ...pt('--', r'XYNO_LAZY', r'read only by tests/e2e/init.lua, not by this file.'),
    ...sec(r'how this file is tested'),
    ...para('--', r'It is not, directly: it is the thing that runs the tests, and it fails loudly when it breaks. The CI step "Specs" runs it with nvim -l tests/run.lua and a pinned Neovim, and a broken runner shows up as a failed job with no RESULT line. The one place with a behaviour that the specs could not catch by themselves is the "crash counts as a failure" branch; it exists because a child that dies before its finish() would otherwise silently add nothing.'),
    blank,
  ],
);
