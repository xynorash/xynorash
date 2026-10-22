import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/tests/coverage_hook.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'coverage_hook.lua — line coverage from debug.sethook, no dependencies'),
    cm('--', r'a 94-line collector loaded before the config so it sees startup too'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'records which lines of the repo own Lua files ran'),
    kv(r'language', r'Lua (LuaJIT debug hook)'),
    kv(r'size', r'94 lines, 1 commit (cf2b8e1, 2026-10-13)'),
    kv(r'loaded by', r'nvim --cmd luafile tests/coverage_hook.lua, only for scripts/test.sh --coverage'),
    kv(r'consumer', r'scripts/coverage.lua, which turns the JSON dump into a per-file report'),
    ...sec(r'why this file exists'),
    ...para('--', r'Coverage answers a question the feature matrix in tests/COVERAGE.md cannot: which lines of lua/, colors/, plugin/ and after/ were never executed by any spec. There is no coverage tool for Neovim Lua that is a single file with no install step, so this one is built from the debug library. The header documents the contract: it is loaded with --cmd so it is active before the config starts, so startup code is counted too; it needs XYNO_COV_ROOTS, the path prefixes under which the repo is visible; and the first match is stripped to get a repo-relative name.'),
    ...code('lua', r'tests/coverage_hook.lua · lines 1-13', r'''
-- Line-coverage collector (debug.sethook, stdlib only). Loaded with
-- `nvim --cmd 'luafile tests/coverage_hook.lua'` so it is active before the
-- config starts. Records which lines of the repo's own Lua files (lua/,
-- colors/, plugin/, after/) ran; tests/runner.lua dumps a JSON file at exit and
-- scripts/coverage.lua reports. Needs XYNO_COV_ROOTS (colon-separated path
-- prefixes under which the repo is visible; the first match is stripped to get
-- the repo-relative name).
--
-- Costs: a line hook disables LuaJIT's compiler for hooked code, so a covered
-- run is several times slower. Coroutines get their own hook (coroutine.create
-- and coroutine.wrap are wrapped). Code run in a separate nvim process (child
-- nvims) is not seen.
local roots = {}'''),
    ...sec(r'which files count'),
    ...para('--', r'classify() decides per chunk source whether to record it. Chunks that do not begin with @ (strings, loadstring) are ignored. A path must sit under one of the roots, and its relative path must start with lua/, colors/, plugin/ or after/ and end in .lua. So plugin code downloaded by lazy.nvim, the Neovim runtime and the tests themselves are not counted. The result for each source is cached in a table, including the negative result, because the hook runs for every line and must be cheap.'),
    ...code('lua', r'tests/coverage_hook.lua · lines 13-37', r'''
local roots = {}
for p in (vim.env.XYNO_COV_ROOTS or ""):gmatch("[^:]+") do
  roots[#roots + 1] = p:gsub("/+$", "") .. "/"
end

local getinfo = debug.getinfo
local files = {} -- rel -> { [line] = true }
local cache = {} -- source -> rel | false

local function classify(src)
  if src:sub(1, 1) ~= "@" then
    return false
  end
  local path = src:sub(2)
  for _, r in ipairs(roots) do
    if path:sub(1, #r) == r then
      local rel = path:sub(#r + 1)
      if rel:match("^lua/") or rel:match("^colors/") or rel:match("^plugin/") or rel:match("^after/") then
        return rel:match("%.lua$") and rel or false
      end
      return false
    end
  end
  return false
end'''),
    ...sec(r'the hook'),
    ...para('--', r'The hook runs on every executed line. It reads the source of level 2, looks it up in the cache, and, if it is a repo file, sets files[rel][line] = true. The table of sets means executing a line a million times costs the same as once, and the output is a set of lines per file rather than a count.'),
    ...code('lua', r'tests/coverage_hook.lua · lines 39-54', r'''
local function hook(_, line)
  local src = getinfo(2, "S").source
  local rel = cache[src]
  if rel == nil then
    rel = classify(src)
    cache[src] = rel
  end
  if rel then
    local f = files[rel]
    if not f then
      f = {}
      files[rel] = f
    end
    f[line] = true
  end
end'''),
    ...sec(r'coroutines'),
    ...para('--', r'A hook set with debug.sethook applies only to the current coroutine. Much of an editor config runs inside coroutines (lazy.nvim, async plugin code), so the file wraps coroutine.create to set the hook on each new coroutine and redefines coroutine.wrap on top of it. The wrap replacement resumes the coroutine and, if it failed, rethrows the error message without a position, which matches the behaviour of the original wrap.'),
    ...code('lua', r'tests/coverage_hook.lua · lines 56-73', r'''
local co_create = coroutine.create
coroutine.create = function(fn)
  local co = co_create(fn)
  debug.sethook(co, hook, "l")
  return co
end
coroutine.wrap = function(fn)
  local co = coroutine.create(fn)
  return function(...)
    local r = { coroutine.resume(co, ...) }
    if not r[1] then
      error(r[2], 0)
    end
    return unpack(r, 2)
  end
end

debug.sethook(hook, "l")'''),
    ...sec(r'dump'),
    ...para('--', r'The dump function writes one JSON object, repo file to sorted list of lines, with keys sorted for stable diffs, using %q to quote names. runner.lua calls it in finish() when XYNO_COV_OUT is set, after the result line. It is exported as the global __xyno_cov so the runner can reach it without a require.'),
    ...code('lua', r'tests/coverage_hook.lua · lines 75-94', r'''
local M = {}
--- Write the lines seen so far to `path` as {"rel/file.lua":[1,2,...],...}.
function M.dump(path)
  local parts = {}
  for rel, lines in pairs(files) do
    local ls = {}
    for l in pairs(lines) do
      ls[#ls + 1] = l
    end
    table.sort(ls)
    parts[#parts + 1] = ("%q:[%s]"):format(rel, table.concat(ls, ","))
  end
  table.sort(parts)
  local f = assert(io.open(path, "w"))
  f:write("{", table.concat(parts, ","), "}\n")
  f:close()
end

_G.__xyno_cov = M
return M'''),
    ...sec(r'costs and limits'),
    ...para('--', r'The header states them honestly. A line hook disables the LuaJIT compiler for hooked code, so a covered run is several times slower, which is why coverage is opt-in and scripts/test.sh describes --coverage as several times slower. Code that runs in a separate nvim process, a child nvim started by a spec, is not seen. The result is a lower bound for lines executed, not a measure of assertions: a line can run without anything checking it.'),
    ...sec(r'history'),
    blank,
    ...pt('--', r'cf2b8e1 (2026-10-13)', r'created with the test infrastructure; it is the only commit that touches the file.'),
  ],
);
