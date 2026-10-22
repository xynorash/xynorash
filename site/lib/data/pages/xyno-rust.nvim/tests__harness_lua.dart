import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-rust.nvim/tests/harness.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'harness.lua - a describe/it framework in 177 lines'),
    cm('--', r'because a Neovim plugin should not need a test runner to be tested'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'minimal BDD framework for the specs'),
    kv(r'language', r'Lua (stdlib and vim only)'),
    kv(r'size', r'177 lines'),
    kv(r'api', r'describe, it, before_each, after_each, pending, skip'),
    kv(r'used by', r'tests/run.lua, which installs it before loading each spec'),
    ...sec(r'why this file exists'),
    ...para('--', r'The specs read like any busted or plenary spec (describe, it, before_each) but depend on nothing. The header gives the working model: one spec file runs per nvim process, so there is no isolation logic, and tests run in registration order in the one editor. Because run.lua starts a fresh Neovim per spec file, the framework itself needs no isolation code.'),
    ...code('lua', r'tests/harness.lua · lines 1-15', r'''
-- Tiny describe/it framework for the spec files (stdlib + vim only). One spec
-- file runs per nvim process (tests/run.lua), so there is no isolation
-- logic here: tests run in registration order, in the one editor.
--
--   describe(name, fn)        group; fn runs at load time and registers tests
--   it(name, fn)              a test; any error fails it
--   before_each / after_each  hooks of the enclosing describe (outer first / last)
--   pending(name, reason)     a registered but skipped test
--   skip(reason)              callable from a test or hook: counts as skipped
--
local M = {}

local SKIP = {}
local root -- { name = "", tests = {}, children = {}, before = {}, after = {} }
local cur'''),
    ...sec(r'skip as an exception'),
    ...code('lua', r'tests/harness.lua · lines 17-28', r'''
local function new_group(name, parent)
  return { name = name, parent = parent, items = {}, before = {}, after = {} }
end

function M.skip(reason)
  error(setmetatable({ reason = reason or "skipped" }, SKIP), 0)
end

local function is_skip(e)
  return type(e) == "table" and getmetatable(e) == SKIP
end
M.is_skip = is_skip'''),
    ...para('--', r'Skipping is implemented as an error with a private metatable. skip(reason) raises a table whose metatable is the SKIP sentinel, level 0 so no position is prepended. is_skip recognises it by metatable, so nothing a test does by accident, even raising a table with a reason field, can be confused with a skip. The same mechanism works at three levels: inside a test (that test is skipped), inside a hook, and at the top of a spec file (the whole file is skipped, as run.lua handles). It is what lets a spec say "no rust-analyzer here" in one line.'),
    ...sec(r'registering'),
    ...code('lua', r'tests/harness.lua · lines 30-57', r'''
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
  end
  _G.pending = function(name, reason)
    table.insert(cur.items, { name = name, group = cur, pending = reason or "pending" })
  end
  _G.before_each = function(fn)
    table.insert(cur.before, fn)
  end
  _G.after_each = function(fn)
    table.insert(cur.after, fn)
  end
  _G.skip = M.skip
end'''),
    ...para('--', r'install defines the globals for the spec about to load, with a root group and a cursor to the group being filled. describe creates a child group, runs its function immediately under pcall (registration happens at load time) and rethrows any error with the group name so a typo in a describe body points at the right block. it only records the test. pending records one with a reason, which is reported as skipped. before_each and after_each attach to the current group.'),
    ...sec(r'readable failures'),
    ...code('lua', r'tests/harness.lua · lines 59-96', r'''
local function full_name(t)
  local parts = { t.name }
  local g = t.group
  while g and g.name ~= "" do
    table.insert(parts, 1, g.name)
    g = g.parent
  end
  return table.concat(parts, " > ")
end

-- Traceback without the harness's own frames.
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
end

local function run_hooks(list, ...)
  for _, fn in ipairs(list) do
    local ok, e = xpcall(fn, trace, ...)
    if not ok then
      return false, e
    end
  end
  return true
end'''),
    ...para('--', r'full_name joins the group names with " > ". The trace function builds a traceback for a failing test but drops the lines that belong to the harness and the runner, so the first line of a failure is the line in the spec. Hooks run under xpcall with that same function and the first failing hook stops the chain.'),
    ...sec(r'the run loop'),
    ...code('lua', r'tests/harness.lua · lines 124-175', r'''
  local function befores(g)
    local list, chain = {}, {}
    while g do
      table.insert(chain, 1, g)
      g = g.parent
    end
    for _, x in ipairs(chain) do
      vim.list_extend(list, x.before)
    end
    return list
  end
  local function afters(g)
    local list = {}
    while g do
      vim.list_extend(list, g.after)
      g = g.parent
    end
    return list
  end

  local function walk(g)
    for _, item in ipairs(g.items) do
      if item.items then
        walk(item)
      elseif item.pending then
        report("skipped", full_name(item), item.pending)
      else
        local t0 = vim.uv.hrtime()
        local name = full_name(item)
        local ok, err = run_hooks(befores(item.group))
        if ok then
          ok, err = xpcall(item.fn, trace)
        end
        -- after_each always runs; its failure only counts when the test passed
        local aok, aerr = run_hooks(afters(item.group))
        if ok and not aok then
          ok, err = false, aerr
        end
        local secs = (vim.uv.hrtime() - t0) / 1e9
        if ok then
          report("passed", name, nil, secs)
        elseif is_skip(err) then
          report("skipped", name, err.reason, secs)
        else
          report("failed", name, err, secs)
        end
      end
    end
  end
  walk(root)
  return n
end'''),
    ...para('--', r'befores collects hooks from the outermost group inward and afters from the innermost outward, the usual nesting. The walk is depth first in registration order. Each test is timed with hrtime; times of a second or more are appended to the line, so slow tests announce themselves. The details worth noticing: after_each always runs, even when the test failed, but its failure only counts when the test itself passed, so cleanup problems do not hide the real failure; a skip inside the test is reported as SKIP with the reason, not as a failure; and failures print their detail indented under the line.'),
    ...code('lua', r'tests/harness.lua · lines 98-122', r'''
--- Run everything registered; print one line per test. Returns counts.
function M.run(out)
  out = out or function(s)
    io.stdout:write(s, "\n")
    io.stdout:flush()
  end
  local n = { passed = 0, failed = 0, skipped = 0 }

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
    ...para('--', r'The output is one line per test: ok, FAIL or SKIP, then the name. The runner reads the results from these lines.'),
    ...sec(r'trade-offs'),
    ...pt('--', r'no isolation between tests', r'state leaks inside a file, so specs reset what they touch in before_each and after_each (helpers.lua holds the shared cleanup).'),
    ...pt('--', r'no focus or filter', r'selecting a test means running its file; there is no -t pattern.'),
    ...pt('--', r'errors are strings', r'no assertion library; the specs use the helpers (H.eq and friends) which raise plain errors with messages.'),
    ...sec(r'history'),
    ...para('--', r'Added in 7c1d2d9 (2026-10-22) with the specs; in xynovim it comes from the test infrastructure commit cf2b8e1 (2026-10-13).'),
  ],
);
