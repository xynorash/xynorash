import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/tests/harness.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'harness.lua — a 180-line describe/it framework, written instead of using plenary'),
    cm('--', r'groups, hooks, skips and a traceback that hides its own frames'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'the test framework behind every spec: describe, it, pending, before_each, after_each, skip'),
    kv(r'language', r'Lua, stdlib plus vim only'),
    kv(r'size', r'180 lines, 1 commit (cf2b8e1, 2026-10-13)'),
    kv(r'loaded as', r'package.preload["xynotest.harness"] by tests/runner.lua'),
    ...sec(r'why a new framework at all'),
    ...para('--', r'The header comment gives the reason in two sentences, and it is the whole argument. Plenary busted is not used because PlenaryBustedFile starts a nested nvim with its own minimal init, which would not load this configuration, and its runner cannot be given the hard timeout or the coverage hook. A configuration test suite must run inside the configuration. So the framework is a few dozen lines that run in the nvim that is already there. The file also says what it leaves out: one spec file runs per nvim process, so there is no isolation logic, and tests run in registration order, in the one editor.'),
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
local M = {}'''),
    ...sec(r'the registration API'),
    ...para('--', r'install() creates a root group and publishes five globals: describe, it, pending, before_each and after_each, plus skip. describe runs its function immediately, at load time, with cur pointing at the new group, so everything registered inside lands in the right place; the function runs under pcall and an error is re-raised with the group name prefixed, which makes a typo in a spec point at the describe block that contains it. It only appends records to tables. Nothing runs until run() is called.'),
    ...code('lua', r'tests/harness.lua · lines 33-60', r'''
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
    ...sec(r'skip is an error with a type'),
    ...para('--', r'skip(reason) raises a table whose metatable is a private SKIP sentinel. Because it travels as an ordinary Lua error, it can be raised from anywhere: a test body, a hook, a helper such as need_rust, or at file level through helpers.skip_file. is_skip lets the runner and the reporter recognise it and count it as skipped instead of failed. A hook that skips skips the test it belongs to.'),
    ...code('lua', r'tests/harness.lua · lines 20-31', r'''
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
    ...sec(r'readable failures'),
    ...para('--', r'When a test fails, the error is passed through trace(), which builds a debug.traceback and then drops every line that mentions tests/harness.lua or tests/runner.lua or the xpcall C frame. What the person reading a failure sees is the spec frames and the helper that raised, not the framework. Tables are shown with vim.inspect, so a failure raised with a table value is not printed as an address. Names are the full path of the nested describe names joined with a greater-than sign, so every test line in the log is unique and greppable.'),
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
end'''),
    ...sec(r'hooks: outer first, outer last'),
    ...para('--', r'before_each hooks of the enclosing groups run outermost first, after_each hooks run innermost first and, importantly, always run, even when the test failed or skipped. A failure in an after_each only matters if the test itself passed, so the first failure is the one reported. This is the right shape for specs that create temp dirs, stub vim.notify or install autocmds in a before_each and undo them afterwards.'),
    ...code('lua', r'tests/harness.lua · lines 91-100, 127-146', r'''
local function run_hooks(list, ...)
  for _, fn in ipairs(list) do
    local ok, e = xpcall(fn, trace, ...)
    if not ok then
      return false, e
    end
  end
  return true
end

...
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
    ...sec(r'run: walk, time, report'),
    ...para('--', r'walk() visits items in order. A group recurses; a pending item is reported as skipped with its reason; a test runs its befores, the body under xpcall with the filtering trace, then its afters, and the elapsed time is measured with vim.uv.hrtime. report() prints ok, FAIL or SKIP, appends the reason to a skip, appends the time only when it is at least one second, which keeps the log quiet and highlights slow tests, and indents failure detail by seven spaces. Counts are returned for the runner to turn into the XYNO_RESULT line.'),
    ...code('lua', r'tests/harness.lua · lines 109-125, 147-176', r'''
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
...
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
  walk(root)'''),
    ...sec(r'decisions and trade-offs'),
    blank,
    ...pt('--', r'No parallelism, no random order', r'tests in a file may build on one editor state, deliberately, which is cheaper than rebuilding the world for each test. The cost is that a spec has to clean up after itself, which is what after_each is for.'),
    ...pt('--', r'Skips instead of failures for missing tools', r'pending and skip let a machine without a tool stay green while the output still says what was not tested.'),
    ...pt('--', r'A tiny surface', r'there is no assertion library here. Assertions live in helpers.lua so that the framework stays free of config knowledge.'),
    ...sec(r'how it is tested'),
    ...para('--', r'harness_spec.lua tests the helpers, and the "harness proof" is smoke_spec.lua. The harness itself is covered by every spec that passes through it. test-infra-readme-claims_spec.lua also loads the harness in process (it requires xynotest.harness) to check what the documentation says about it.'),
    ...sec(r'history'),
    blank,
    ...pt('--', r'cf2b8e1 (2026-10-13)', r'the only commit that touched the file. It arrived with scripts/test.sh, runner.lua and the helpers in the "Test infrastructure" commit, and has not needed a change since: the later work (Windows and macOS, sandbox fail-closed) went into helpers.lua and runner.lua.'),
  ],
);
