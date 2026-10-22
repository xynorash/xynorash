import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-new.nvim/tests/harness.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'tests/harness.lua — describe and it in 177 lines'),
    cm('--', r'a framework small enough to read before trusting it'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'describe / it / before_each / after_each / pending / skip'),
    kv(r'language', r'Lua; stdlib and vim only, installed as globals by tests/run.lua'),
    kv(r'design', r'one spec file per Neovim process: tests run in order, in one editor'),
    kv(r'reports', r'ok / FAIL / SKIP with timings of one second or more'),
    ...sec(r'why this file exists'),
    ...para('--', r'The header spells out the economy: one spec file runs per nvim process, so there is no isolation logic here. Tests run in registration order, in the one editor. The harness has no parallelism, random order or filtering, and the runner gives each spec file a fresh process instead of isolating tests inside one.'),
    ...code('lua', r'tests/harness.lua · lines 1-11', r'''
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
local M = {}'''),
    ...sec(r'the skip mechanism'),
    ...code('lua', r'tests/harness.lua · lines 13-28', r'''
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
M.is_skip = is_skip'''),
    ...para('--', r'A skip is an error whose value is a table with a private metatable. skip(reason) raises it with level 0; is_skip recognises it by the metatable, so no string matching is involved and no user error can be mistaken for a skip. This lets a skip happen anywhere: in a test, in a hook (need_cargo in before_each), or at load time in the spec’s top level, where tests/run.lua catches it and marks the whole file skipped.'),
    ...sec(r'installing the globals'),
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
    ...para('--', r'install builds a root group and publishes six globals (describe, it, pending, before_each, after_each, skip). describe runs its function immediately under pcall, so registration happens at load, and a failure inside it is rethrown with the group name. it only records the test. A test is a record with a name, a function and its group; a group has items, before hooks and after hooks. Nothing runs until run() walks the tree, which is why before_each can be declared after the tests in a file and still apply.'),
    ...sec(r'readable failures'),
    ...code('lua', r'tests/harness.lua · lines 69-86', r'''
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
end'''),
    ...para('--', r'The traceback printed for a failed test drops the lines that belong to the harness and the runner, so what remains is the spec’s own frames. A table error value is rendered with vim.inspect. The filter looks for the file paths tests/harness.lua and tests/run.lua, plus the xpcall C frame.'),
    ...sec(r'hooks and the order they run'),
    ...code('lua', r'tests/harness.lua · lines 124-142', r'''
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
  end'''),
    ...code('lua', r'tests/harness.lua · lines 144-172', r'''
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
  end'''),
    ...para('--', r'befores collects hooks from the outermost group inward, afters from the innermost outward: the usual nesting. A test runs: before hooks, the body, then after hooks, always, even if the body failed. If a before hook fails the body is skipped but the after hooks still run, which matters here because the specs’ after_each restores PATH, vim.g, stubs and the working directory. The comment in the code adds a rule: an after_each failure counts only when the test itself passed, so a failing test is not buried by a second error from cleanup.'),
    ...para('--', r'Timing is measured with vim.uv.hrtime and shown only for one second or more; the code prints a duration only at one second or more. A pending test is registered and reported as a skip with its reason, a way to keep a known gap visible.'),
    ...sec(r'why not plenary or busted'),
    ...para('--', r'The file does not argue the point. What it shows is the alternative: 177 lines, no dependencies, and its own skip semantics. What it lacks, such as filtering and parallel runs, the runner page lists.'),
    ...sec(r'history'),
    ...para('--', r'Added in 1de2687 on 2026-10-22 with the specs.'),
  ],
);
