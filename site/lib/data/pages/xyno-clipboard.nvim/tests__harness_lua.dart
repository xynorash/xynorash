import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-clipboard.nvim/tests/harness.lua',
  lines: [
    cm('--', r'──────────────────────────────────────────'),
    cm('--', r'harness.lua — a 180-line describe/it framework with no dependencies'),
    cm('--', r'because the real one would start a nested nvim without the plugin'),
    cm('--', r'──────────────────────────────────────────'),
    kv(r'role', r'describe, it, pending, skip, before_each, after_each, and a runner that prints one line per test'),
    kv(r'language', r'Lua (stdlib and vim only)'),
    kv(r'size', r'180 lines'),
    kv(r'used by', r'tests/run.lua, which loads it with dofile'),
    kv(r'history', r'added in 46a5b14 (2026-10-22, Add specs and CI)'),
    ...sec(r'why this file exists'),
    ...para('--', r'The top comment names the alternative and rejects it, and the note is only in this copy. '
        r'Plenary’s busted runs each spec through PlenaryBustedFile, which starts a nested nvim '
        r'with its own minimal init, which would not load this config, so the process that runs the '
        r'tests would not have the repository on its runtimepath unless extra work is done, and the '
        r'runner could not be given a hard timeout or a coverage hook. The author wrote a framework '
        r'whose contract is listed in the header comment, and kept it to 180 lines. The framework came from the xynovim config, where tests/harness.lua was added in '
        r'cf2b8e1 (2026-10-13) together with a per-file runner, and was copied into each extracted '
        r'plugin. The copies are not byte-identical: the xyno-history, xyno-macros and several '
        r'sibling repositories carry one version, xyno-guard and xyno-sandbox slightly edited ones, '
        r'and this repository’s copy is the one that still holds the original comments.'),
    ...code('lua', r'tests/harness.lua · lines 1-14', r'''
-- Tiny describe/it framework for the spec files (stdlib + vim only). One spec
-- file runs per nvim process (tests/runner.lua), so there is no isolation
-- logic here: tests run in registration order, in the one editor.
--
--   describe(name, fn)        group; fn runs at load time and registers tests
--   it(name, fn)              a test; any error fails it
--   before_each / after_each  hooks of the enclosing describe (outer first / last)
--   pending(name, reason)     a registered but skipped test
--   skip(reason)              callable from a test or hook: counts as skipped
--
-- Plenary's busted was not used: PlenaryBustedFile starts a nested nvim with
-- its own minimal init, which would not load this config, and its runner
-- cannot be given our hard timeout or the coverage hook.
local M = {}
'''),
    ...sec(r'installing the globals'),
    ...code('lua', r'tests/harness.lua · lines 15-60', r'''

local SKIP = {}
local root -- { name = "", tests = {}, children = {}, before = {}, after = {} }
local cur

local function new_group(name, parent)
  return { name = name, parent = parent, items = {}, before = {}, after = {} }
end

function M.skip(reason)
  error(setmetatable({ reason = reason or "skipped" }, SKIP), 0)
end

local function is_skip(e)
  return type(e) == "table" and getmetatable(e) == SKIP
end
M.is_skip = is_skip

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
end
'''),
    ...para('--', r'M.install builds a fresh root group and publishes six globals: describe, it, pending, '
        r'before_each, after_each and skip. A group is a plain table holding items, before hooks '
        r'and after hooks, with a parent pointer. describe runs its function immediately under '
        r'pcall, so the registrations happen at load time and a syntax or runtime error while a '
        r'spec is being defined is re-raised with the group name attached. it does not run '
        r'anything; it only appends a record. This split between registration and execution is why '
        r'the hooks can see the whole tree.'),
    ...para('--', r'Skipping is implemented with a sentinel. skip raises an error whose value is a table with '
        r'a private metatable; is_skip recognises it. The effect is that skip works from inside a '
        r'test or a hook, unwinds through any depth of helper functions, and is counted as skipped, '
        r'not failed.'),
    ...sec(r'names and tracebacks'),
    ...code('lua', r'tests/harness.lua · lines 62-89', r'''
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
      and not l:find("tests/runner.lua", 1, true)
      and not l:find("[C]: in function 'xpcall'", 1, true)
    then
      keep[#keep + 1] = l
    end
  end
  return table.concat(keep, "\n")
end
'''),
    ...para('--', r'full_name joins group names with a greater-than sign so that every output line identifies '
        r'its test. trace is the quiet part of the file. It takes a traceback and drops the lines '
        r'that belong to the harness itself, so a failing assertion shows the frames of the spec '
        r'and the code under test and not the framework. It filters tests/harness.lua, the C frame '
        r'for xpcall, and tests/runner.lua. That last name is a leftover from xynovim, where the '
        r'entry point was tests/runner.lua. Here the entry point is tests/run.lua, so its frames '
        r'are not removed (line 82 of this file, and the comment on line 2). The sibling '
        r'repositories fixed both spots to say run.lua. The leftover is harmless, since it only '
        r'adds a line or two to a traceback.'),
    ...sec(r'hooks'),
    ...code('lua', r'tests/harness.lua · lines 91-99', r'''
local function run_hooks(list, ...)
  for _, fn in ipairs(list) do
    local ok, e = xpcall(fn, trace, ...)
    if not ok then
      return false, e
    end
  end
  return true
end
'''),
    ...para('--', r'Hooks run under xpcall with the same trace function. The helper stops at the first '
        r'failing hook and returns its error, which is what makes a failing before_each fail its '
        r'test without running the body.'),
    ...sec(r'the runner'),
    ...code('lua', r'tests/harness.lua · lines 101-125', r'''
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
  end
'''),
    ...para('--', r'M.run takes an output function, defaulting to a flushed write to standard output, and '
        r'returns counts. report formats lines as ok, FAIL or SKIP followed by the full name. Skip '
        r'reasons go in parentheses, a duration is appended only when it reaches one second, and a '
        r'failure prints its detail indented below. The flush matters in CI, because a hang would '
        r'otherwise leave the log empty.'),
    ...code('lua', r'tests/harness.lua · lines 127-145', r'''
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
'''),
    ...para('--', r'The two collectors walk the group chain: before hooks are gathered from the outermost '
        r'group inward, after hooks from the innermost outward, which is the order every '
        r'busted-style framework uses.'),
    ...code('lua', r'tests/harness.lua · lines 147-177', r'''
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
'''),
    ...para('--', r'walk executes the tree in registration order. The part that deserves a second look is the '
        r'handling of after_each. It always runs, even when the test failed, so temp directories '
        r'and fakes are always cleaned; but its failure only counts when the test itself passed, so '
        r'a cleanup problem cannot hide the original error. Timing uses vim.uv.hrtime. A skipped '
        r'test reports through the same sentinel check, so a skip raised in a before hook skips the '
        r'test.'),
    ...sec(r'design decisions'),
    ...pt('--', r'No isolation', r'the header (line 2) says one spec file runs per nvim process, which was true of the '
        r'xynovim runner; here run.lua loads every spec file into the same nvim, calling install '
        r'before each one so each file gets a fresh root. Isolation between tests is the specs’ own '
        r'job, via hooks.'),
    ...pt('--', r'Plain output', r'one line per test and a final RESULT line from run.lua. CI needs nothing more than the '
        r'exit code, and a human reads the lines.'),
    ...pt('--', r'No parallelism, no filtering by name', r'a spec file can be named on the command line, and that is the granularity.'),
    ...sec(r'history'),
    ...pt('--', r'cf2b8e1', r'2026-10-13 in xynovim: the original harness, with its runner.'),
    ...pt('--', r'46a5b14', r'2026-10-22: added to this repository with the first specs.'),
  ],
);
