import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-imports.nvim/tests/run.lua',
  lines: [
    cm(r'''--''', r'''──────────────────────────────────────────'''),
    cm(r'''--''', r'''run.lua — nvim -l tests/run.lua'''),
    cm(r'''--''', r'''one process to supervise, one headless nvim per spec'''),
    cm(r'''--''', r'''──────────────────────────────────────────'''),
    blank,
    kv(r'''role''', r'''spec runner and its own entry point'''),
    kv(r'''language''', r'''Lua, run with nvim -l'''),
    kv(r'''size''', r'''101 lines'''),
    kv(r'''modes''', r'''no argument: run every spec in a child; with a file: run it here'''),
    kv(r'''exit''', r'''0 only without failures; prints RESULT passed=N failed=N skipped=N'''),
    ...sec(r'''why this file exists'''),
    ...para(r'''--''', r'''Two requirements pull in opposite directions. Specs want to share one Neovim for speed within a file, and they want to be isolated from each other so a stub, a command or an LSP client from one cannot leak into the next. The answer is the unit of isolation being the file: the parent process loops over tests/*_spec.lua and starts one headless Neovim per spec, and the same script, given a file, becomes that child. It descends from tests/runner.lua in xynovim (107 lines, ff1c8fa) and is 101 lines here.'''),
    blank,
    ...sec(r'''setting up the runtime path'''),
    ...para(r'''--''', r'''Both modes begin by preparing the editor. Swap files are off. The plugin directory is prepended to the runtime path, so require finds xyno_imports. The sibling dependency is appended: XYNO_RUST_DIR if set, otherwise a checkout named xyno-rust.nvim next to this one. An optional XYNO_TEST_RTP is appended too, which is how CI supplies a directory containing the compiled tree-sitter parser.'''),
    blank,
    ...code('lua', r'tests/run.lua · lines 7-7, 11-25', r'''
local here = vim.fs.dirname(debug.getinfo(1, "S").source:sub(2))
...
vim.o.swapfile = false
vim.opt.rtp:prepend(repo)
-- the plugin this one builds on: XYNO_RUST_DIR, else a sibling checkout
local rust = vim.env.XYNO_RUST_DIR
if not rust or rust == "" then
  rust = vim.fs.dirname(repo) .. "/xyno-rust.nvim"
end
vim.opt.rtp:append(rust)
if vim.env.XYNO_TEST_RTP and vim.env.XYNO_TEST_RTP ~= "" then
  vim.opt.rtp:append(vim.env.XYNO_TEST_RTP) -- e.g. a directory holding parser/rust.so
end

if not spec then
  local files = vim.fn.glob(repo .. "/tests/*_spec.lua", true, true)
  table.sort(files)'''),

    ...para(r'''--''', r'''The dependency is located by convention rather than configuration, which matches how the author lays out the repositories side by side under one directory. Without the sibling, requiring its modules fails; the README’s test section names XYNO_RUST_DIR for a checkout elsewhere.'''),
    blank,
    ...sec(r'''the parent: one child per spec'''),
    ...para(r'''--''', r'''Without an argument the script globs the specs, sorts them for a stable order and runs each through vim.system with the same Neovim binary (vim.v.progpath), the same script and the file as argument, with a 10 minute wait. Output is forwarded as it comes back, and each child RESULT line is parsed into totals. A child that exits non-zero without printing RESULT, a crash or a hang, counts as one failure, so the exit code can never be 0 when something went wrong silently.'''),
    blank,
    ...code('lua', r'tests/run.lua · lines 23-23, 38-39', r'''
if not spec then
...
  os.exit(total.failed > 0 and 1 or 0)
end'''),

    ...sec(r'''the child: preload, header, run'''),
    ...para(r'''--''', r'''With a file argument the script makes the harness and helpers available under the names the specs use. package.preload entries map xyno_imports_test.helpers and .harness to dofile of the files in tests/, so a spec says require("xyno_imports_test.helpers") and gets the file without a rock or a path trick. The prefix avoids colliding with any other module called helpers.'''),
    blank,
    ...code('lua', r'tests/run.lua · lines 41-47', r'''
package.path = repo .. "/lua/?.lua;" .. repo .. "/lua/?/init.lua;" .. package.path
for _, name in ipairs({ "helpers", "harness" }) do
  package.preload["xyno_imports_test." .. name] = function()
    return dofile(repo .. "/tests/" .. name .. ".lua")
  end
end
'''),

    ...para(r'''--''', r'''finish() prints the RESULT line before cleanup, calls helpers.cleanup in pcall to remove temp directories, jobs and LSP clients, clears messages and quits: cquit 1 on failures, qa! otherwise. The order is deliberate: if cleanup hangs, the result is already on stdout.'''),
    blank,
    ...code('lua', r'tests/run.lua · lines 48-57', r'''
local function finish(n)
  io.stdout:write(("RESULT passed=%d failed=%d skipped=%d\n"):format(n.passed, n.failed, n.skipped))
  io.stdout:flush()
  local helpers = package.loaded["xyno_imports_test.helpers"]
  if helpers then
    pcall(helpers.cleanup)
  end
  pcall(vim.cmd, "messages clear")
  vim.cmd(n.failed > 0 and "cquit 1" or "qa!")
end'''),

    ...sec(r'''a spec can say where it runs'''),
    ...para(r'''--''', r'''os_skip_reason reads the first fifteen lines of the spec for a header of the form xyno-os: linux,macos followed by a reason in parentheses. If the current OS is not in the list, the whole file is skipped with one line before it loads. It matters for specs whose setup would itself fail on, say, Windows, and it keeps the reason next to the file instead of in the runner. Neither current spec carries the header, but the mechanism is there from xynovim, where ff1c8fa introduced it.'''),
    blank,
    ...code('lua', r'tests/run.lua · lines 61-80', r'''
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

    ...sec(r'''loading and running'''),
    ...para(r'''--''', r'''The spec is loaded with dofile under xpcall with debug.traceback. A skip raised during loading, for instance a need_os at the top of a file, becomes a SKIP for the file. Any other load error prints "FAIL loading" with the traceback and counts as one failure, so a syntax error in a spec shows up as a failure and not as silently zero tests. Otherwise the harness runs and its counts go to finish.'''),
    blank,
    ...code('lua', r'tests/run.lua · lines 89-100', r'''
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
end'''),

    ...sec(r'''trade-offs'''),
    ...pt(r'''--''', r'''Sequential''', r'''the specs run one after another. Total time is the sum, but there are two files and shared state is not a concern.'''),
    ...pt(r'''--''', r'''Regex-parsed totals''', r'''the parent reads RESULT lines out of text instead of a structured channel. Simple, and the text is also what a human reads.'''),
    ...pt(r'''--''', r'''No filter''', r'''you can run one file but not one test; the filter would be a grep of the output.'''),
    ...sec(r'''history'''),
    ...pt(r'''--''', r'''cf2b8e1 2026-10-13''', r'''in xynovim, the first runner with scripts/test.sh.'''),
    ...pt(r'''--''', r'''ff1c8fa 2026-10-16''', r'''in xynovim, the portable runner (tests/runner.lua) with OS-aware skips.'''),
    ...pt(r'''--''', r'''45d98cb 2026-10-22''', r'''this version: renamed, reduced and pointed at xyno-rust.nvim.'''),
  ],
);
