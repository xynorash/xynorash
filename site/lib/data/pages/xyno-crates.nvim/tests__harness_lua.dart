import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-crates.nvim/tests/harness.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'harness.lua — a describe/it framework in 177 lines'),
    cm('--', r'stdlib and vim only, tests run in order, skipping is an error with a type'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'the test framework every *_spec.lua file runs on'),
    kv(r'language', r'Lua (Neovim 0.12+)'),
    kv(r'size', r'177 lines'),
    kv(r'provides', r'describe, it, pending, before_each, after_each, skip'),
    kv(r'used by', r'tests/run.lua, which installs it and calls M.run()'),
    kv(r'origin', r'xynovim tests/harness.lua, added in cf2b8e1 (2026-10-13), nearly unchanged'),
    ...sec(r'why this file exists'),
    ...para('--', r'The specs of this plugin exercise autocommands, diagnostics, language clients and buffers, so they run inside Neovim. plenary.nvim’s busted runner is one way to do that. xynovim’s original harness had a comment, dropped in this copy, giving its reason for not using it: PlenaryBustedFile starts a nested nvim with its own minimal init, which would not load the config under test, and its runner cannot be given a hard timeout or a coverage hook. For a plugin repository the first reason does not apply, but the result is that the specs depend on no test library; the CI workflow fetches Neovim, the sibling plugins, a snacks.nvim checkout, lazy.nvim and a tree-sitter parser, and no test framework.'),
    blank,
    ...para('--', r'The file is the smallest thing that can do the job. The diff against xynovim’s copy is small: the runner is called tests/run.lua instead of tests/runner.lua in two places, and the paragraph about plenary was removed. Everything else, including the design below, is the original from xynovim’s test-infrastructure commit cf2b8e1 of 2026-10-13.'),
    blank,
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
    ...sec(r'the API in one screen'),
    ...para('--', r'install() defines the globals describe, it, pending, before_each, after_each and skip on _G, and resets the tree of groups. The specs are plain files that call those globals at load time; describe runs its function immediately (inside pcall, so a bug in a spec’s structure is reported with the group name) and registers the tests in a table. Nothing runs until M.run() walks the table. Tests execute in registration order, in one editor, because one spec file runs per nvim process: the header says so and concludes "so there is no isolation logic here". That is a trade the project makes on purpose: no per-test sandboxing, in exchange for cheap tests that can share an expensive fixture, and isolation at the granularity of the file, where the runner gives it for free.'),
    blank,
    ...sec(r'skip is an error of its own type'),
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
    ...para('--', r'A skip is raised with error() and a table whose metatable is a private SKIP sentinel; is_skip tests for it. Two properties follow. A skip can be called from anywhere, at any depth, inside helpers, without the helper having to return a flag. And a real error can never be confused with a skip, since no other code can construct the sentinel. level 0 keeps the position out of the message. This is the mechanism behind every "skips with a printed reason" in the README: no network, no cargo, no rust-analyzer, no snacks checkout, or a known platform issue. A skipped test is counted and printed with its reason, not hidden.'),
    blank,
    ...para('--', r'The runner also handles a skip at load time: if a spec file calls skip() before registering anything (say, a missing prerequisite for the whole file), tests/run.lua catches it and reports one SKIP for the file.'),
    blank,
    ...sec(r'running: hooks, timing, reporting'),
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
    ...para('--', r'report keeps three counters and prints one line per test: "ok  ", "FAIL" or "SKIP", the full name (group names joined with " > "), the skip reason in parentheses, and the time in brackets when it reaches a second. A failure prints the traceback indented by seven spaces. The format is stable on purpose, because tests/run.lua parses the final RESULT line of each child process.'),
    blank,
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
    ...para('--', r'Hooks are collected by walking up the parent chain: before_each hooks run outermost first, after_each hooks innermost first, which is the order that makes nested setup and teardown symmetrical. Both helpers are tiny, and the file does not try to be clever about it.'),
    blank,
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
    ...para('--', r'This is the loop. Pending items report a skip. Otherwise the before hooks run, then the test body under xpcall with a trace function, and then, always, the after hooks, even for a failure or a skip. The comment states the policy: "after_each always runs; its failure only counts when the test passed". A teardown error never hides the original failure, and a teardown error after a pass is still a failure, so cleanup bugs are not swallowed. Errors that are skips are recognised after that and reported as SKIP. The trace function (lines 70-86, not shown) strips the harness’s own frames from the traceback, so a failure points at the spec line, not at the framework.'),
    blank,
    ...sec(r'limits worth knowing'),
    ...pt('--', r'no nesting of tests', r'it() inside it() is not supported; the table only knows groups and tests.'),
    ...pt('--', r'no ordering control', r'tests run in registration order. The specs rely on it only to share a process, and each test builds its own temp directory.'),
    ...pt('--', r'state leaks within a file', r'because the whole file shares one nvim, a test that forgets to restore a stub affects the next. The specs answer this with a local stub() helper that records restore functions, executed in after_each in reverse order (crate-add_spec.lua lines 17-31).'),
    ...pt('--', r'no per-test timeout', r'a hung test hangs its file; the parent in tests/run.lua waits up to 600000 ms for each child process and then fails the file.'),
    ...sec(r'history'),
    ...pt('--', r'cf2b8e1, 2026-10-13', r'xynovim: "Test infrastructure: scripts/test.sh (per-file headless nvim, timeouts, isolation, coverage), tests/ harness, helpers, fixtures and specs, CI job, README Tests section".'),
    ...pt('--', r'9d33ca7, 2026-10-22', r'this repository: copied with the runner renamed. One commit, no later changes.'),
  ],
);
