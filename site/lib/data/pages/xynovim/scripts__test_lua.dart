import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/scripts/test.lua',
  lines: [
    cm(r'--', '──────────────────────────────────────────'),
    cm(r'--', r'scripts/test.lua'),
    cm(r'--', r'the spec runner without bash'),
    cm(r'--', r'the same protocol as test.sh, written in Lua so it runs wherever Neovim does'),
    cm(r'--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'portable supervisor for the spec suite, used on Windows and on macOS (platforms.yml)'),
    kv(r'language', r'Lua, run as nvim --clean -l scripts/test.lua'),
    kv(r'size', r'294 lines, one commit (ff1c8fa, 2026-10-16)'),
    kv(r'exit status', r'0 all passed (skips allowed) · 1 any failure, timeout or crash · 2 usage or setup'),
    ...sec(r'why this file exists'),
    ...para(r'--', r'The suite needs a supervisor that starts a Neovim per spec file, limits its time and reads its result. On Linux that is test.sh. scripts/test.sh depends on bash, GNU timeout and process groups. The portable runner implements the same supervisor in Lua inside Neovim, which only needs the nvim binary the suite is testing anyway (its header says it runs wherever Neovim does, Windows included, no bash needed). Because nvim -l runs a script without a UI and without the user’s config, the supervisor itself is a plain process.'),
    blank,
    ...code('lua', r'scripts/test.lua · lines 1-19', r'''
-- Portable spec runner: the same job as scripts/test.sh, in Lua, so it runs
-- wherever Neovim does (Windows included, no bash needed).
--
--   nvim --clean -l scripts/test.lua [options] [pattern...]
--
--   pattern       only spec files whose path contains it (several = any of them)
--   --list        print the spec files and exit
--   --timeout N   hard timeout per spec file in seconds (default 120, or $TEST_TIMEOUT);
--                 a "-- xyno-timeout: N" line in a spec raises it for that file
--   -v            print the full output of every spec file, not only failures
--
-- Same isolation and protocol as test.sh: each spec file runs in its own
-- `nvim --headless -S tests/runner.lua` (XYNO_SPEC=<file>) with the checkout
-- linked as the config under a temp XDG_CONFIG_HOME, temp XDG_STATE_HOME /
-- XDG_CACHE_HOME / TMPDIR, the REAL plugin data dir (bootstrap first), and the
-- XYNO_RESULT line of the runner parsed. Exit status: 0 all passed (skips
-- allowed), 1 any failure / timeout / crash, 2 usage or setup. No coverage mode
-- (use test.sh --coverage on Linux).
local uv = vim.uv
'''),
    ...para(r'--', r'The header repeats the contract and ends with the one difference: there is no coverage mode, use test.sh --coverage on Linux.'),
    blank,
    ...sec(r'finding the repository and reading options'),
    ...code('lua', r'scripts/test.lua · lines 19-56', r'''
local uv = vim.uv

-- (print() goes to stderr under `nvim -l`)
local function out_line(s)
  io.stdout:write(s, "\n")
  io.stdout:flush()
end
local is_win = vim.fn.has("win32") == 1

local script = vim.fs.normalize(arg[0] or "scripts/test.lua")
local repo = vim.fs.dirname(vim.fs.dirname(vim.fn.fnamemodify(script, ":p")))

local timeout_s = tonumber(vim.env.TEST_TIMEOUT) or 120
local list, verbose, patterns = false, false, {}
do
  local i = 1
  while i <= #arg do
    local a = arg[i]
    if a == "--list" then
      list = true
    elseif a == "--timeout" then
      i = i + 1
      timeout_s = tonumber(arg[i])
      if not timeout_s then
        io.stderr:write("test.lua: --timeout needs seconds\n")
        os.exit(2)
      end
    elseif a == "-v" or a == "--verbose" then
      verbose = true
    elseif a:sub(1, 1) == "-" then
      io.stderr:write("test.lua: unknown option " .. a .. "\n")
      os.exit(2)
    else
      patterns[#patterns + 1] = a
    end
    i = i + 1
  end
end
'''),
    ...para(r'--', r'The repository root is derived from arg[0], the path of the script being run, by taking two dirnames. The option loop is the same shape as the shell one, with the same rejects: --timeout without a number, or an unknown dash option, exits 2. Note the comment about print: under nvim -l print goes to stderr, so the script defines out_line to write on stdout and flush, so that CI logs appear in order.'),
    blank,
    ...sec(r'selecting specs'),
    ...code('lua', r'scripts/test.lua · lines 58-87', r'''
local specs = {}
for name, kind in vim.fs.dir(repo .. "/tests") do
  if kind == "file" and name:match("_spec%.lua$") then
    local rel = "tests/" .. name
    local hit = #patterns == 0
    for _, p in ipairs(patterns) do
      hit = hit or rel:find(p, 1, true) ~= nil
    end
    if hit then
      specs[#specs + 1] = rel
    end
  end
end
table.sort(specs)

if list then
  out_line(table.concat(specs, "\n"))
  os.exit(0)
end
if #specs == 0 then
  io.stderr:write("test.lua: no spec file matches " .. table.concat(patterns, " ") .. "\n")
  os.exit(2)
end

local nvim = vim.v.progpath
local data = vim.fn.stdpath("data")
if not uv.fs_stat(data .. "/lazy/lazy.nvim") then
  io.stderr:write("test.lua: no plugins in " .. data .. "/lazy. Run scripts/bootstrap first\n")
  os.exit(2)
end
'''),
    ...para(r'--', r'Specs are listed with vim.fs.dir over tests/, filtered by the suffix _spec.lua, and a pattern is matched by a plain substring find (the fourth argument true turns off Lua patterns). The list is sorted, so the order is stable. The same checks as test.sh follow: no match is exit 2, and a data directory without lazy.nvim is exit 2 with the hint to bootstrap first.'),
    blank,
    ...sec(r'the isolated environment'),
    ...code('lua', r'scripts/test.lua · lines 99-130', r'''
local work = assert(uv.fs_mkdtemp((vim.env.TMPDIR or vim.env.RUNNER_TEMP or vim.fn.fnamemodify(vim.fn.tempname(), ":h")) .. "/xynotest.XXXXXX"))
work = vim.fs.normalize(work)
for _, d in ipairs({ "config", "state", "cache", "tmp" }) do
  vim.fn.mkdir(work .. "/" .. d, "p")
end
local lock_before = read(repo .. "/lazy-lock.json")

-- The checkout as <XDG_CONFIG_HOME>/nvim: a symlink, or a junction on Windows (no admin rights needed).
local link = work .. "/config/nvim"
if is_win then
  local r = vim.system({ "cmd", "/c", "mklink", "/J", (link:gsub("/", "\\")), (repo:gsub("/", "\\")) }, { text = true }):wait()
  if r.code ~= 0 then
    io.stderr:write("test.lua: mklink /J failed: " .. (r.stderr or r.stdout or "") .. "\n")
    os.exit(2)
  end
else
  assert(uv.fs_symlink(repo, link))
end

local prefix = "xynotest-" .. uv.os_getpid()
local env = {
  XDG_CONFIG_HOME = work .. "/config",
  XDG_STATE_HOME = work .. "/state",
  XDG_CACHE_HOME = work .. "/cache",
  XYNO_TEST_TMP = work .. "/tmp",
  TMPDIR = work .. "/tmp",
  XYNO_TMUX_PREFIX = prefix,
  XYNO_COV_ROOTS = work .. "/config/nvim:" .. repo,
}
if is_win then
  env.TEMP, env.TMP = work .. "/tmp", work .. "/tmp"
end
'''),
    ...para(r'--', r'Each run gets a work directory created with fs_mkdtemp under TMPDIR, RUNNER_TEMP (the GitHub Actions variable) or the Neovim temp dir, and four subfolders. The checkout becomes the config by a symlink, or on Windows by a junction made with cmd /c mklink /J, because a junction needs no administrator rights. The environment table mirrors test.sh: XDG state and cache and TMPDIR in the temporary folder, and on Windows TEMP and TMP too, since Windows programs do not look at TMPDIR. The data directory is not overridden here, it is whatever stdpath data says for the caller.'),
    blank,
    ...sec(r'cleanup and killing a process tree'),
    ...code('lua', r'scripts/test.lua · lines 132-154', r'''
local function cleanup()
  if not is_win and vim.fn.executable("tmux") == 1 then
    local pw = uv.os_get_passwd()
    local dir = (vim.env.TMUX_TMPDIR or "/tmp") .. "/tmux-" .. (pw and pw.uid or 0)
    if uv.fs_stat(dir) then
      for name in vim.fs.dir(dir) do
        if name:sub(1, #prefix) == prefix then
          vim.system({ "tmux", "-L", name, "kill-server" }):wait(5000)
          uv.fs_unlink(dir .. "/" .. name)
        end
      end
    end
  end
  vim.fn.delete(work, "rf")
end

local function kill_tree(obj)
  if is_win then
    vim.system({ "taskkill", "/T", "/F", "/PID", tostring(obj.pid) }):wait(10000)
  else
    pcall(obj.kill, obj, 9)
  end
end
'''),
    ...para(r'--', r'On Unix-like systems the cleanup function does the tmux sweep as test.sh does, matching sockets by the run’s pid prefix; on every system it deletes the work directory. kill_tree is the one place the two platforms really differ: on Windows taskkill /T /F kills the whole tree, elsewhere the process gets SIGKILL through the handle. The shell version kills a process group. Here only the direct process is killed, which is a visible difference between the two runners; the language servers of a killed Windows spec go with taskkill /T, the Unix ones are not reached by obj.kill.'),
    blank,
    ...sec(r'running one spec'),
    ...code('lua', r'scripts/test.lua · lines 170-206', r'''
for _, rel in ipairs(specs) do
  local head = {}
  local fh = io.open(repo .. "/" .. rel, "rb")
  if fh then
    for _ = 1, 15 do
      head[#head + 1] = fh:read("*l") or ""
    end
    fh:close()
  end
  local eff = timeout_s
  for _, l in ipairs(head) do
    local n = l:match("^%-%- xyno%-timeout: *(%d+)")
    if n and tonumber(n) > eff then
      eff = tonumber(n)
    end
  end

  local chunks, seen_at, done, code = {}, nil, false, nil
  local function on_data(_, d)
    if d then
      chunks[#chunks + 1] = d
      if not seen_at and d:find("XYNO_RESULT ", 1, true) then
        seen_at = uv.now()
      end
    end
  end
  local e = vim.tbl_extend("force", env, { XYNO_SPEC = repo .. "/" .. rel })
  local t0 = uv.now()
  local obj = vim.system({ nvim, "--headless", "-S", repo .. "/tests/runner.lua" }, {
    env = e,
    stdin = false,
    stdout = on_data,
    stderr = on_data,
    text = true,
  }, function(o)
    code, done = o.code, true
  end)
'''),
    ...para(r'--', r'The spec header is read for a xyno-timeout line with a Lua pattern, exactly as in the shell version. The child is started with vim.system, with stdin disabled and both output streams collected by one callback, which also notes the time of the first XYNO_RESULT. A completion callback records the exit code. It is an event-driven design where test.sh polls with kill -0.'),
    blank,
    ...code('lua', r'scripts/test.lua · lines 207-255', r'''
  local timed_out, hung = false, false
  while not done do
    vim.wait(500, function()
      return done
    end, 100)
    local now = uv.now()
    if not done and now - t0 > eff * 1000 then
      timed_out = true
      kill_tree(obj)
      vim.wait(10000, function()
        return done
      end, 100)
      break
    end
    -- the result line was printed but nvim does not exit: 30 s of grace, then it is killed
    if not done and seen_at and now - seen_at > 30000 then
      hung = true
      kill_tree(obj)
      vim.wait(10000, function()
        return done
      end, 100)
      break
    end
  end
  local secs = math.floor((uv.now() - t0) / 1000)
  local out = table.concat(chunks)
  local res
  for line in out:gmatch("[^\r\n]+") do
    if line:find("^XYNO_RESULT ") then
      res = line
    end
  end
  local status, p, f, s
  if timed_out then
    status, p, f, s = "TIMEOUT", 0, 1, 0
  elseif not res then
    status, p, f, s = "CRASH", 0, 1, 0
  else
    p, f, s = tonumber(res:match("passed=(%d+)")), tonumber(res:match("failed=(%d+)")), tonumber(res:match("skipped=(%d+)"))
    if hung then
      code = 0
    end
    if f > 0 or code ~= 0 then
      status = "FAIL"
      f = math.max(f, 1)
    else
      status = "PASS"
    end
  end
'''),
    ...para(r'--', r'The waiting loop calls vim.wait in 500 ms slices and applies the two limits: the overall limit for the file, after which the tree is killed and the status is TIMEOUT, and the 30-second grace after the result line, after which a hung process is killed but the result stands. Classification is the same as in test.sh: no result line is a CRASH, a failure count above zero or a non-zero exit is a FAIL, and a hung run counts as exit zero.'),
    blank,
    ...sec(r'reporting'),
    ...code('lua', r'scripts/test.lua · lines 256-294', r'''
  tot.passed, tot.failed, tot.skipped = tot.passed + p, tot.failed + f, tot.skipped + s
  out_line(("%-7s %s  %d passed, %d failed, %d skipped (%ds)"):format(status, rel, p, f, s, secs))
  if hung then
    out_line("    NOTE: nvim did not exit 30 s after the result line and was killed (the result above counts)")
  end
  if status ~= "PASS" then
    failed_files[#failed_files + 1] = rel
  end
  local lines = vim.split(out, "\r?\n")
  if verbose then
    for _, l in ipairs(lines) do
      out_line("    | " .. l)
    end
  else
    for _, l in ipairs(lines) do
      if l:find("^SKIP") or l:find("^FAIL") or l:find("^       ") then
        out_line("    " .. l)
      end
    end
    if status == "TIMEOUT" or status == "CRASH" then
      out_line(("    (%s, exit %s; last output)"):format(status, tostring(code)))
      for i = math.max(1, #lines - 15), #lines do
        out_line("    | " .. lines[i])
      end
    end
  end
  io.stdout:flush()
end

if read(repo .. "/lazy-lock.json") ~= lock_before then
  out_line("WARNING: lazy-lock.json changed during the run (git diff lazy-lock.json)")
end
cleanup()
out_line(("\ntotal: %d passed, %d failed, %d skipped in %ds"):format(tot.passed, tot.failed, tot.skipped, math.floor((uv.now() - t_all) / 1000)))
if #failed_files > 0 then
  out_line("failed: " .. table.concat(failed_files, " "))
  os.exit(1)
end
os.exit(0)
'''),
    ...para(r'--', r'The report prints the same one line per spec, the NOTE for hangs, and the SKIP, FAIL and detail lines (seven spaces) unless -v prints everything. A timeout or crash prints the last fifteen lines. The lockfile is compared as strings before and after. cleanup runs before the totals are printed, so the temp directory is removed before the final lines.'),
    blank,
    ...sec(r'who runs it'),
    ...para(r'--', r'Two jobs of .github/workflows/platforms.yml call it. The Windows job goes through scripts\test.ps1, which runs this file. The macOS job runs it directly with nvim --clean -l scripts/test.lua --timeout 240, and the comment in the workflow gives the reason: macOS has no GNU timeout for scripts/test.sh. So the portable runner is not only a Windows workaround; it is also what makes the suite run on a stock Mac.'),
    blank,
    ...sec(r'design decisions and trade-offs'),
    ...pt(r'--', r'one protocol, two implementations', r'the only contract between runner and spec is the XYNO_RESULT line and the SKIP/FAIL line prefixes, so the two supervisors can differ internally.'),
    ...pt(r'--', r'guarded by a spec', r'tests/scripts-portable_spec.lua reads scripts/test.lua as text, along with the PowerShell and shell scripts, to keep the portable scripts in step with the originals.'),
    ...pt(r'--', r'no coverage', r'scripts/coverage.lua lists files by shelling out to find (line 80), which only works on Unix-like systems; the runner header just says there is no coverage mode and to use test.sh --coverage on Linux.'),
    ...sec(r'history'),
    ...pt(r'--', r'ff1c8fa 2026-10-16', r'added with bootstrap.ps1, test.ps1 and the platforms workflow. The Windows runs that followed (6524272, cd602fd on 2026-10-21) changed specs and Lua modules, not this runner.'),
  ],
);
