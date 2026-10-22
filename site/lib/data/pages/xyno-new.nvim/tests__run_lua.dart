import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-new.nvim/tests/run.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'tests/run.lua — a test runner in 101 lines'),
    cm('--', r'one headless Neovim per spec, an OS header, and a RESULT line CI can sum'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'runs tests/*_spec.lua, each in its own nvim process, and totals them'),
    kv(r'language', r'Lua, run as `nvim -l tests/run.lua [spec]`'),
    kv(r'env', r'XYNO_RUST (path to xyno-rust.nvim), XYNO_TEST_RTP (extra runtimepath)'),
    kv(r'contract', r'prints ok / FAIL / SKIP per test and RESULT passed=N failed=N skipped=N'),
    kv(r'origin', r'smaller sibling of xynovim’s scripts/test.lua (added in ff1c8fa, 2026-10-16)'),
    ...sec(r'why this file exists'),
    ...para('--', r'This plugin keeps its tests dependency-free (the README lists no test dependency beyond Neovim, xyno-rust.nvim and, for some specs, cargo, curl, unzip, python3): a 177-line describe/it harness and this 101-line runner, both plain Lua. xynovim’s Windows and macOS commit (ff1c8fa) added a portable runner, scripts/test.lua at 294 lines, to that repository. It has a per-file hard timeout (default 120 seconds) that a “-- xyno-timeout: N” header in a spec can raise. The “-- xyno-os:” header is documented in xynovim’s tests/runner.lua. This 101-line runner keeps the OS header and drops the timeout machinery.'),
    ...sec(r'two modes in one file'),
    ...code('lua', r'tests/run.lua · lines 7-10, 23-38', r'''
local here = vim.fs.dirname(debug.getinfo(1, "S").source:sub(2))
local repo = vim.fs.dirname(vim.fs.normalize(vim.fn.fnamemodify(here, ":p")))
local spec = arg and arg[1]

...
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
  os.exit(total.failed > 0 and 1 or 0)'''),
    ...para('--', r'The same script plays two roles, chosen by whether it was given a spec path. Without an argument it is the parent: it globs tests/*_spec.lua, sorts the list, and runs each file as a child process with vim.v.progpath (the very Neovim running the parent, not whatever nvim is on PATH), waiting up to ten minutes. With an argument it is the child and runs that one spec in itself.'),
    ...para('--', r'Process isolation is the main design decision. The specs open buffers, create user commands, start language servers, stub vim.ui and change the working directory; a spec that leaves a mess cannot contaminate the next one, and a hang costs only that child. The child’s stdout is copied through, and the parent extracts the three counters from the RESULT line with a pattern per key. If a child dies with a non-zero code without printing RESULT, it counts as one failure, so a crash can never look like a pass.'),
    ...sec(r'setting up the child'),
    ...code('lua', r'tests/run.lua · lines 11-22, 41-46', r'''
vim.o.swapfile = false
vim.opt.rtp:prepend(repo)
-- xyno-rust.nvim (rust_context, fsutil): XYNO_RUST names its checkout, else the sibling directory
local rust = vim.env.XYNO_RUST
if not rust or rust == "" then
  rust = vim.fs.dirname(repo) .. "/xyno-rust.nvim"
end
vim.opt.rtp:prepend(rust)
if vim.env.XYNO_TEST_RTP and vim.env.XYNO_TEST_RTP ~= "" then
  vim.opt.rtp:append(vim.env.XYNO_TEST_RTP) -- e.g. a directory holding parser/rust.so
end

...
package.path = repo .. "/lua/?.lua;" .. repo .. "/lua/?/init.lua;" .. rust .. "/lua/?.lua;" .. rust .. "/lua/?/init.lua;" .. package.path
for _, name in ipairs({ "helpers", "harness" }) do
  package.preload["xyno_new_test." .. name] = function()
    return dofile(repo .. "/tests/" .. name .. ".lua")
  end
end'''),
    ...para('--', r'The repository goes first on the runtimepath, then xyno-rust.nvim: XYNO_RUST names it explicitly, and otherwise the sibling directory next to the checkout is assumed, which is the layout of a developer who cloned both. package.path is extended too, because the specs run through dofile and Lua’s own require must find xyno_new and xyno_rust. The helpers and the harness are registered in package.preload under the names xyno_new_test.helpers and xyno_new_test.harness, so specs say require("xyno_new_test.helpers") and never need a path.'),
    ...sec(r'an OS header the runner understands'),
    ...code('lua', r'tests/run.lua · lines 59-80', r'''
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
    ...para('--', r'A spec may say in its first fifteen lines which systems it can run on: a comment of the form xyno-os: linux,macos followed by a parenthesised reason. Both Rust and egui specs carry one, because they write sh stubs of cargo and rely on file mode bits. The runner compares against windows, macos or linux (decided with vim.fn.has) and, when the spec is not meant for this system, prints SKIP with the reason and counts one skipped. The reason text is part of the output, so a skip is never silent. The same header exists in xynovim’s specs and runner.'),
    ...sec(r'finishing cleanly'),
    ...code('lua', r'tests/run.lua · lines 48-57, 89-101', r'''
local function finish(n)
  io.stdout:write(("RESULT passed=%d failed=%d skipped=%d\n"):format(n.passed, n.failed, n.skipped))
  io.stdout:flush()
  local helpers = package.loaded["xyno_new_test.helpers"]
  if helpers then
    pcall(helpers.cleanup)
  end
  pcall(vim.cmd, "messages clear")
  vim.cmd(n.failed > 0 and "cquit 1" or "qa!")
end
...
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
    ...para('--', r'finish prints the RESULT line, calls the helper’s cleanup (temp directories, jobs, language server clients), clears the message history, and leaves with qa! or, when anything failed, cquit 1 so the exit code is non-zero. A failure while loading the spec file is reported as FAIL loading with the traceback and counts as one failure. A skip raised by a spec at load time is caught with harness.is_skip and reported as a SKIP of the whole file.'),
    ...sec(r'what the runner does not do'),
    ...pt('--', r'No parallelism', r'specs run one after another.'),
    ...pt('--', r'An ignored header', r'rust-new_spec.lua and egui-new_spec.lua start with “-- xyno-timeout: 300”, a header xynovim’s runner honours, but this runner reads only xyno-os. Its one timeout is the fixed 600000 ms in the wait call on line 28, so the header is documentation here.'),
    ...pt('--', r'No test filtering by name', r'you pick files, not tests.'),
    ...pt('--', r'No output format beyond text', r'a CI system parses the final line.'),
    ...sec(r'history'),
    ...para('--', r'Added in 1de2687 (2026-10-22) with the harness, the helpers, the four specs and the smoke test. The three-commit history of the repository does not show the earlier iterations; those are in xynovim.'),
  ],
);
