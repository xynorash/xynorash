import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-imports.nvim/tests/harness.lua',
  lines: [
    cm(r'''--''', r'''──────────────────────────────────────────'''),
    cm(r'''--''', r'''harness.lua — a test framework you can read in one sitting'''),
    cm(r'''--''', r'''describe, it, hooks, skip and a trace that hides its own frames'''),
    cm(r'''--''', r'''──────────────────────────────────────────'''),
    blank,
    kv(r'''role''', r'''minimal busted-style framework for the spec files'''),
    kv(r'''language''', r'''Lua, stdlib and vim only'''),
    kv(r'''size''', r'''177 lines; the xynovim original is 180'''),
    kv(r'''api''', r'''describe, it, before_each, after_each, pending, skip'''),
    kv(r'''origin''', r'''xynovim tests/harness.lua, cf2b8e1 on 2026-10-13'''),
    ...sec(r'''why this file exists'''),
    ...para(r'''--''', r'''The specs need nested groups, per-test hooks, skipping with a reason and one line of output per test. The original comment in xynovim, dropped in the copy, gave the reason for not using plenary busted: its file runner starts a nested nvim with its own minimal init, which would not load the config, and it could not be given the hard timeout or the coverage hook. The consequence here is that the suite needs no test dependency: the workflow fetches Neovim, the sibling plugin, and lazy.nvim for the smoke test, and nothing for the specs themselves.'''),
    blank,
    ...para(r'''--''', r'''The file is a near copy. The only differences from the xynovim version are the runner name in a comment and in the traceback filter, tests/runner.lua becoming tests/run.lua, and the removed plenary note. It first appears here in 45d98cb on 2026-10-22.'''),
    blank,
    ...sec(r'''the whole API in the header'''),
    ...code('lua', r'tests/harness.lua · lines 1-10', r'''
-- Tiny describe/it framework for the spec files (stdlib + vim only). One spec
-- file runs per nvim process (tests/run.lua), so there is no isolation
-- logic here: tests run in registration order, in the one editor.
--
--   describe(name, fn)        group; fn runs at load time and registers tests
--   it(name, fn)              a test; any error fails it
--   before_each / after_each  hooks of the enclosing describe (outer first / last)
--   pending(name, reason)     a registered but skipped test
--   skip(reason)              callable from a test or hook: counts as skipped
--'''),

    ...para(r'''--''', r'''The header is the documentation. One thing in it carries the design: one spec file per Neovim process, no isolation logic, tests run in registration order in the one editor. All the hard parts of isolation are solved by the runner starting a fresh process, which lets the harness be this small.'''),
    blank,
    ...sec(r'''skip is an error with a type'''),
    ...para(r'''--''', r'''A skip has to leave a test from anywhere, including a helper three calls deep and a before_each hook. The simplest way to do that in Lua is to raise an error, so skip() raises a table with a private metatable. is_skip() tells it from a real failure by the metatable, so no real error can be confused with a skip and no skip can be swallowed as a failure. The reason travels in the table, and error level 0 stops Lua from prepending a position to it.'''),
    blank,
    ...code('lua', r'tests/harness.lua · lines 13-13, 21-23, 25-27', r'''
local SKIP = {}
...
function M.skip(reason)
  error(setmetatable({ reason = reason or "skipped" }, SKIP), 0)
end
...
local function is_skip(e)
  return type(e) == "table" and getmetatable(e) == SKIP
end'''),

    ...para(r'''--''', r'''The same mechanism skips a whole file: a skip raised while the spec is being loaded is caught by tests/run.lua, which prints one SKIP line for the file. helpers.need_rust, need_parser, need_os and known_issue all end in this call.'''),
    blank,
    ...sec(r'''installing the globals'''),
    ...para(r'''--''', r'''install() creates the root group and defines describe, it, pending, before_each, after_each and skip as globals, so spec files read as plain busted. describe runs its function at once, under pcall, with the current group switched to the new one, so nested its register into the right parent. If the function throws while registering, the error is rethrown with the group name, which makes a typo in a spec easy to find.'''),
    blank,
    ...code('lua', r'tests/harness.lua · lines 30-46', r'''
function M.install()
  root = new_group("", nil)
  cur = root
  _G.describe = function(name, fn)
    local g = new_group(name, cur)
    table.insert(cur.items, g)
    local prev = cur
    cur = g
    local ok, err = pcall(fn)
    cur = prev
    if not ok then
      error("describe '" .. name .. "': " .. tostring(err), 0)
    end
  end
  _G.it = function(name, fn)
    table.insert(cur.items, { name = name, fn = fn, group = cur })
  end'''),

    ...sec(r'''tracebacks without the harness frames'''),
    ...para(r'''--''', r'''A failure is reported with a traceback, but the traceback of an error inside a test would be mostly harness and runner lines. trace() builds it with debug.traceback and filters out any line mentioning tests/harness.lua, tests/run.lua or the C frame of xpcall. A table error is rendered with vim.inspect, so a helper that raises a structured error still prints something useful. A skip passes through untouched.'''),
    blank,
    ...code('lua', r'tests/harness.lua · lines 70-86', r'''
local function trace(e)
  if is_skip(e) then
    return e
  end
  local tb = debug.traceback(type(e) == "table" and vim.inspect(e) or tostring(e), 2)
  local keep = {}
  for l in tb:gmatch("[^\n]+") do
    if
      not l:find("tests/harness.lua", 1, true)
      and not l:find("tests/run.lua", 1, true)
      and not l:find("[C]: in function 'xpcall'", 1, true)
    then
      keep[#keep + 1] = l
    end
  end
  return table.concat(keep, "\n")
end'''),

    ...sec(r'''running: hooks, order, and the after_each guarantee'''),
    ...para(r'''--''', r'''The run walks the tree. For each test it collects before hooks outer first (by building the chain from the root down) and after hooks inner first (by walking up). The test body runs under xpcall with the trace handler. The detail that matters: after_each runs even when the test failed, because tests leave state behind, such as stubs, buffers and LSP clients, and a failing test must not poison the next. If the test passed and the hook failed, the hook failure becomes the test failure.'''),
    blank,
    ...code('lua', r'tests/harness.lua · lines 151-156', r'''
        local t0 = vim.uv.hrtime()
        local name = full_name(item)
        local ok, err = run_hooks(befores(item.group))
        if ok then
          ok, err = xpcall(item.fn, trace)
        end'''),

    ...sec(r'''the output format'''),
    ...para(r'''--''', r'''report() prints "ok  ", "FAIL" or "SKIP" followed by the full name, group names joined with " > ". A skip appends its reason in parentheses. Tests taking a second or more get their time appended. A failure is followed by its detail, indented. That is all a CI log needs: one line per test, a grep for FAIL, a reason for each skip. The counts are returned to tests/run.lua, which prints the RESULT line.'''),
    blank,
    ...code('lua', r'tests/harness.lua · lines 106-122', r'''
  local function report(kind, name, detail, secs)
    n[kind] = n[kind] + 1
    local label = ({ passed = "ok  ", failed = "FAIL", skipped = "SKIP" })[kind]
    local line = ("%s %s"):format(label, name)
    if kind == "skipped" and detail then
      line = line .. " (" .. detail .. ")"
    end
    if secs and secs >= 1 then
      line = line .. (" [%.1fs]"):format(secs)
    end
    out(line)
    if kind == "failed" and detail then
      for l in tostring(detail):gmatch("[^\n]+") do
        out("       " .. l)
      end
    end
  end'''),

    ...sec(r'''design decisions and trade-offs'''),
    ...pt(r'''--''', r'''Registration order''', r'''tests run in the order written. There is no randomisation, so a hidden dependency between tests would not be found by this suite, only by reading.'''),
    ...pt(r'''--''', r'''No test isolation inside a file''', r'''a test that leaves a command or an autocommand defined affects the next. The specs compensate with explicit after_each cleanup, which init_spec.lua shows in full.'''),
    ...pt(r'''--''', r'''Pending is separate from skip''', r'''pending registers a skipped test at load time with a reason; skip decides at run time.'''),
    ...pt(r'''--''', r'''No async support''', r'''a test waits with helpers (wait_for), which pumps the event loop with vim.wait; the harness itself is synchronous.'''),
    ...sec(r'''history'''),
    ...pt(r'''--''', r'''cf2b8e1 2026-10-13''', r'''in xynovim: "Test infrastructure: scripts/test.sh ..., tests/ harness, helpers, fixtures and specs".'''),
    ...pt(r'''--''', r'''ff1c8fa 2026-10-16''', r'''in xynovim: portable runner and OS-aware skips (the commit message names both).'''),
    ...pt(r'''--''', r'''45d98cb 2026-10-22''', r'''copied here with the runner name changed.'''),
  ],
);
