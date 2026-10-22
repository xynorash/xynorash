import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/scripts/coverage.lua',
  lines: [
    cm(r'--', '──────────────────────────────────────────'),
    cm(r'--', r'scripts/coverage.lua'),
    cm(r'--', r'a line-coverage report in 115 lines'),
    cm(r'--', r'with the caveat printed in its own header'),
    cm(r'--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'merges coverage dumps into a per-file table'),
    kv(r'language', r'Lua, run as nvim -l scripts/coverage.lua <repo> <dump dir>'),
    kv(r'size', r'115 lines, one commit (cf2b8e1, 2026-10-13)'),
    kv(r'input', r'*.json dumps written by tests/coverage_hook.lua, one per spec file'),
    kv(r'output', r'one row per Lua file under lua, colors, plugin and after, then TOTAL'),
    ...sec(r'why this file exists'),
    ...para(r'--', r'The suite is large (the b2fee5c commit message counts 1011 tests) and needs a way to say which parts of the configuration the specs actually run. The solution here is small and has no external dependency: a hook records which lines execute inside each spec’s Neovim, a dump file is written at exit, and this script merges the dumps and prints a table. test.sh --coverage ties them together.'),
    blank,
    ...code('lua', r'scripts/coverage.lua · lines 1-7', r'''
-- Per-file line coverage of the repo's own Lua modules.
--   nvim -l scripts/coverage.lua <repo> <dir with *.json dumps>
-- (scripts/test.sh --coverage runs it.) The dumps come from
-- tests/coverage_hook.lua: the lines that executed. The denominator is an
-- ESTIMATE of the executable lines, read from the source text: blank lines,
-- comments (also --[[ ]] blocks), lines of only `end`, `else`, `)`, `}` and
-- long-string bodies are not counted. Treat the percentages as a guide.
'''),
    ...para(r'--', r'The header is explicit about the limits. The numerator (lines executed) is measured, but the denominator is an estimate read from source text. The words are Treat the percentages as a guide, and it is the right way to read the output.'),
    blank,
    ...sec(r'merging the dumps'),
    ...code('lua', r'scripts/coverage.lua · lines 8-28', r'''
local repo, dir = arg[1], arg[2]
if not repo or not dir then
  io.stderr:write("usage: nvim -l scripts/coverage.lua <repo> <dump dir>\n")
  os.exit(2)
end

-- union of all dumps: rel -> { [line] = true }
local hit = {}
for _, name in ipairs(vim.fn.glob(dir .. "/*.json", false, true)) do
  local f = io.open(name)
  local ok, data = pcall(vim.json.decode, f:read("*a"))
  f:close()
  if ok then
    for rel, lines in pairs(data) do
      hit[rel] = hit[rel] or {}
      for _, l in ipairs(lines) do
        hit[rel][l] = true
      end
    end
  end
end
'''),
    ...para(r'--', r'The script takes the repository and the directory of dumps as arguments and exits 2 with a usage line if either is missing. Each dump is a JSON object from relative path to a list of line numbers. They are decoded in a pcall, so a dump that was truncated by a killed process is skipped instead of aborting the report. The union across all dumps is kept as a set per file: a line counts once no matter how many specs ran it.'),
    blank,
    ...sec(r'estimating executable lines'),
    ...code('lua', r'scripts/coverage.lua · lines 30-77', r'''
--- Set of executable line numbers (estimate, see header).
local function executable(path)
  local set, n = {}, 0
  local in_block, in_long = false, false
  local ln = 0
  for line in io.lines(path) do
    ln = ln + 1
    local s = line
    if in_block then
      if s:find("%]%]") then
        in_block = false
      end
      s = ""
    elseif in_long then
      if s:find("%]%]") then
        in_long = false
      end
      s = ""
    else
      if s:match("^%s*%-%-%[%[") then
        in_block = not s:find("%]%]")
        s = ""
      else
        s = s:gsub("%-%-.*$", "") -- comment tail (a `--` inside a string is rare here)
        -- a line that opens a long string: the line counts, the body does not
        local a = s:find("%[%[")
        if a and not s:find("%]%]", a + 2) then
          in_long = true
        end
      end
    end
    local t = s:gsub("%s+", "")
    -- only closers / `else` / `end` / `do` / `then` / bare braces
    if
      t ~= ""
      and not t:match("^[%)%}%]%,;]*$")
      and not t:match("^[%)%}%]%,;]*end[%)%}%]%,;]*$")
      and t ~= "else"
      and t ~= "do"
      and t ~= "then"
      and t ~= "return"
    then
      set[ln] = true
      n = n + 1
    end
  end
  return set, n
end
'''),
    ...para(r'--', r'The function reads a file line by line, with two states, in_block for --[[ ]] comments and in_long for the body of a [[ ]] string, which are blanked out. Other lines have their comment tail removed with a pattern and then all whitespace removed, leaving a skeleton. A line is not counted if the skeleton is empty, consists only of closers (a closing paren, brace or bracket with commas), is only end with closers, or is exactly else, do, then or return. A line that opens a long string counts, and its body does not. The comment admits the known flaw: a double dash inside a string literal is treated as the start of a comment.'),
    blank,
    ...para(r'--', r'The consequence of this approach is direction-less error, not bias in one direction: some lines that cannot execute are counted, a few that can are dropped. For a table by file that is used to find untested modules, that is enough.'),
    blank,
    ...sec(r'choosing the files and printing'),
    ...code('lua', r'scripts/coverage.lua · lines 79-97', r'''
local files = {}
local p = io.popen(("cd %q && find lua colors plugin after -name '*.lua' 2>/dev/null | sort"):format(repo))
for l in p:lines() do
  files[#files + 1] = l
end
p:close()

local rows, tot_exec, tot_hit = {}, 0, 0
for _, rel in ipairs(files) do
  local set, n = executable(repo .. "/" .. rel)
  local h = 0
  for l in pairs(hit[rel] or {}) do
    if set[l] then
      h = h + 1
    end
  end
  rows[#rows + 1] = { rel = rel, hit = h, n = n }
  tot_exec, tot_hit = tot_exec + n, tot_hit + h
end
'''),
    ...para(r'--', r'The file list comes from find over lua, colors, plugin and after, run through io.popen with a quoted cd. The report therefore depends on find and sort being available, so it works only on Unix-like systems; test.lua’s header says it has no coverage mode and points to test.sh --coverage on Linux. Rows keep the hit count for lines that are in the executable set only, so a hit on a line the estimator discarded is not counted twice.'),
    blank,
    ...code('lua', r'scripts/coverage.lua · lines 99-115', r'''
local width = 0
for _, r in ipairs(rows) do
  width = math.max(width, #r.rel)
end
print("Line coverage (lines executed by the specs; executable lines estimated)")
for _, r in ipairs(rows) do
  local pct = r.n > 0 and (100 * r.hit / r.n) or 100
  print(("  %-" .. width .. "s  %3d/%-4d %5.1f%%"):format(r.rel, r.hit, r.n, pct))
end
print(
  ("  %-" .. width .. "s  %3d/%-4d %5.1f%%"):format(
    "TOTAL",
    tot_hit,
    tot_exec,
    tot_exec > 0 and 100 * tot_hit / tot_exec or 100
  )
)
'''),
    ...para(r'--', r'Column width is computed from the longest path so the table lines up. A file with no executable lines shows 100 percent, which avoids a division by zero and an alarming zero for an empty module. The total is computed from the sums, not by averaging the percentages, so it is weighted by file size.'),
    blank,
    ...sec(r'how it fits the test suite'),
    ...para(r'--', r'tests/runner.lua dumps the hook’s data when XYNO_COV_OUT is set, which test.sh sets per spec file when --coverage is on. The dump directory is a subfolder of the temporary work dir and is deleted when the run ends, after this script has printed the table.'),
    blank,
    ...sec(r'history'),
    ...pt(r'--', r'cf2b8e1 2026-10-13', r'added with the test infrastructure; it has not changed since.'),
  ],
);
