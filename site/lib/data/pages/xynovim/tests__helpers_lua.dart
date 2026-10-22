import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/tests/helpers.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'helpers.lua — the toolbox every spec starts with'),
    cm('--', r'assertions, waiting, fixtures, processes, probes and a cleanup that cannot hang'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'shared test helpers: local H = require("xynotest.helpers")'),
    kv(r'language', r'Lua, 539 lines'),
    kv(r'history', r'created 2026-10-13 (cf2b8e1), reshaped by the Windows and macOS runs of 2026-10-16 to 2026-10-21'),
    kv(r'groups', r'assertions, waiting, editor, tool probes, skipping, temp dirs, fixtures, processes, cleanup'),
    ...sec(r'why this file exists'),
    ...para('--', r'There are some 45 spec files, and nearly all of them need the same things: an equality check that prints both sides, a way to wait for a language server, a private copy of a Cargo project to mess up, a way to start tmux without touching the real one, and a way to skip politely when a tool is missing. helpers.lua holds all of that, so a spec reads as a list of facts. The header is a table of contents of the API, which the code then follows in order.'),
    ...code('lua', r'tests/helpers.lua · lines 1-19', r'''
-- Utilities for spec files. `local H = require("xynotest.helpers")`.
--
-- Assertions   H.eq H.ok H.not_ok H.is_nil H.match H.no_match H.has H.throws
-- Waiting      H.wait_for(pred, timeout_ms, msg) H.wait_lsp(name, bufnr, ms)
-- Editor       H.feed(keys) H.open(path) H.clients() H.diagnostics(source)
--              H.messages() H.clear_messages() H.capture_notify()
-- Fixtures     H.fixture(name, {git=true}) H.open_fixture(name, rel) H.git(...)
-- Processes    H.sandbox_sh(script, project) H.tmux(...) H.spawn(cmd)
-- Skipping     H.skip_file(reason) H.need_rust() H.need_sandbox() H.need_tmux()
--              H.need_os({ "linux", "macos" }, reason) H.need_posix(reason)
--              and, in a spec's first 15 lines, `-- xyno-os: linux (reason)` (tests/runner.lua)
-- Cleanup      H.cleanup() (the runner calls it at the end; registered
--              resources are temp dirs, jobs, tmux sockets, LSP clients)
local harness = require("xynotest.harness")

local H = {}
local repo = vim.fs.dirname(vim.fs.dirname(debug.getinfo(1, "S").source:sub(2)))
H.repo = repo
H.fixtures = repo .. "/tests/fixtures"'''),
    ...sec(r'assertions that print both sides'),
    ...para('--', r'H.eq compares with vim.deep_equal and on failure prints expected and actual through vim.inspect on two lines, with an optional message prefix. The error level is 2 so the traceback points at the spec line, not at the helper. On Windows the comparison has a second chance: if the plain comparison fails, both sides are canonicalised and compared again. canon() rewrites backslashes to slashes and lower-cases the drive letter, and it also does so for drive paths embedded in a longer message, which matters for text like "coverage loaded (D:\x\y)". This was added after the first full Windows runs, because Windows spells one path several ways (D:\a, D:/a, d:/a) and tests of path-producing code should not be about spelling.'),
    ...code('lua', r'tests/helpers.lua · lines 23-59', r'''
local function fail(msg, level)
  error(msg, (level or 1) + 1)
end

-- Windows spells one path several ways (D:\\a, D:/a, d:/a): compare the
-- canonical form (forward slashes, lower-case drive letter) there.
local function canon(v)
  if type(v) == "string" then
    if v:find("%f[%a]%a:[/\\]") then
      -- also drive paths embedded in a message ("coverage loaded (D:\\x\\y)")
      return (v:gsub("\\", "/"):gsub("%f[%a](%a):/", function(d)
        return d:lower() .. ":/"
      end))
    end
    return v
  elseif type(v) == "table" then
    local t = {}
    for k, x in pairs(v) do
      t[k] = canon(x)
    end
    return t
  end
  return v
end

function H.eq(expected, actual, msg)
  local same = vim.deep_equal(expected, actual)
  if not same and vim.fn.has("win32") == 1 then
    same = vim.deep_equal(canon(expected), canon(actual))
  end
  if not same then
    fail(
      ("%sexpected %s\n  actual   %s"):format(msg and (msg .. ": ") or "", vim.inspect(expected), vim.inspect(actual)),
      2
    )
  end
end'''),
    ...para('--', r'The rest are small and uniform: ok and not_ok, is_nil, match and no_match for Lua patterns (with a plain flag for literal text), has for list membership or substring, and throws for expected errors with an optional pattern. Every failure message includes the value, so a CI log can be read without a rerun.'),
    ...code('lua', r'tests/helpers.lua · lines 94-125', r'''
function H.has(container, item, msg)
  local found = false
  if type(container) == "string" then
    found = container:find(item, 1, true) ~= nil
  else
    for _, v in ipairs(container) do
      if vim.deep_equal(v, item) then
        found = true
        break
      end
    end
  end
  if not found then
    fail(
      (msg and (msg .. ": ") or "") .. ("%s does not contain %s"):format(vim.inspect(container), vim.inspect(item)),
      2
    )
  end
end

--- fn must raise an error (matching `pat`, a Lua pattern, when given).
function H.throws(fn, pat)
  local ok, e = pcall(fn)
  if ok then
    fail("expected an error, none raised", 2)
  end
  if pat and not tostring(e):find(pat) then
    fail(("error %q does not match %q"):format(tostring(e), pat), 2)
  end
end

-- ------------------------------------------------------------------ waiting'''),
    ...sec(r'waiting without sleeping'),
    ...para('--', r'H.wait_for wraps vim.wait with a 20 ms poll so the event loop keeps running while the predicate is polled. It returns the predicate value, which lets a test write local d = H.wait_for(function() return find_diagnostic() end, 60000, "an E0308 diagnostic") and use d afterwards. On timeout it fails with timed out waiting for followed by the message you gave it, so the failure names the awaited thing, not just a number of milliseconds.'),
    ...code('lua', r'tests/helpers.lua · lines 127-139', r'''
--- Wait until pred() is truthy (vim.wait, the event loop keeps running).
--- Returns its value; raises `msg` on timeout.
function H.wait_for(pred, timeout_ms, msg)
  local value
  local done = vim.wait(timeout_ms or 5000, function()
    value = pred()
    return value and true or false
  end, 20)
  if not done then
    fail("timed out waiting for " .. (msg or "condition"), 2)
  end
  return value
end'''),
    ...sec(r'probes: is the tool really there'),
    ...para('--', r'The three probe functions answer yes or a reason. rust_available is more careful than checking PATH: it honours XYNO_TEST_SKIP_RUST, requires cargo, requires rust-analyzer, and then runs rust-analyzer --version, because rustup installs a proxy named rust-analyzer that exits non-zero when the component is not installed. sandbox_available does not just look for bwrap. It asks the config own agent_sandbox module to wrap the command true and then runs the wrapped command, because bwrap can exist and still be unable to create a sandbox (for example in an unprivileged container). The reason string says so.'),
    ...code('lua', r'tests/helpers.lua · lines 238-272', r'''

--- Both rust-analyzer (a real one, not rustup's proxy stub) and cargo work.
function H.rust_available()
  if vim.env.XYNO_TEST_SKIP_RUST == "1" then
    return false, "XYNO_TEST_SKIP_RUST=1"
  end
  if vim.fn.executable("cargo") ~= 1 then
    return false, "cargo not found"
  end
  if vim.fn.executable("rust-analyzer") ~= 1 then
    return false, "rust-analyzer not found"
  end
  if vim.system({ "rust-analyzer", "--version" }):wait(10000).code ~= 0 then
    return false, "rust-analyzer is only a rustup proxy (rustup component add rust-analyzer)"
  end
  return true
end

function H.sandbox_available()
  if vim.fn.executable("bwrap") ~= 1 then
    return false, "bwrap not found"
  end
  local dir = H.tmpdir()
  local prev = vim.fn.chdir(dir)
  local cmd, err = require("config.agent_sandbox").wrap({ "true" }, dir, dir)
  vim.fn.chdir(prev)
  if not cmd then
    return false, err
  end
  local r = vim.system(cmd, { cwd = dir }):wait(10000)
  if r.code ~= 0 then
    return false, "bwrap cannot create a sandbox here: " .. vim.trim(r.stderr or "")
  end
  return true
end'''),
    ...sec(r'skipping with a reason'),
    ...para('--', r'need_os, known_issue, need_posix and skip_file are layered on harness.skip. known_issue is the interesting one: it skips on listed platforms, always prints the reason, and its doc comment says such a failure is listed in docs/KNOWN_ISSUES.md. The platform work uses it to keep Windows and macOS green only for what a CI run showed passing, without hiding what is not. H.os and H.is_win are computed once from vim.fn.has.'),
    ...code('lua', r'tests/helpers.lua · lines 282-327', r'''
H.bash = vim.uv.fs_stat("/usr/bin/bash") and "/usr/bin/bash" or vim.fn.exepath("bash")

--- "linux", "macos" or "windows".
H.os = vim.fn.has("win32") == 1 and "windows" or vim.fn.has("mac") == 1 and "macos" or "linux"
H.is_win = H.os == "windows"

--- Skip the test (or, at load time, the file) unless this platform is in `list`.
function H.need_os(list, reason)
  if not vim.tbl_contains(list, H.os) then
    harness.skip(("needs %s, this is %s: %s"):format(table.concat(list, " or "), H.os, reason))
  end
end

--- Skip the test on the platforms in `list`: a failure seen in a CI run that is
--- not diagnosed or fixed yet. Always names the reason; listed in docs/KNOWN_ISSUES.md.
function H.known_issue(list, reason)
  if vim.tbl_contains(list, H.os) then
    harness.skip(("known issue on %s: %s"):format(H.os, reason))
  end
end

--- Skip on Windows (shell scripts, chmod bits, signals, symlinks without privileges).
function H.need_posix(reason)
  H.need_os({ "linux", "macos" }, reason)
end

function H.skip_file(reason)
  harness.skip(reason)
end

local function need(probe)
  local ok, why = probe()
  if not ok then
    harness.skip(why)
  end
end
function H.need_rust()
  need(H.rust_available)
end
function H.need_sandbox()
  need(H.sandbox_available)
end
function H.need_tmux()
  need(H.tmux_available)
end
'''),
    ...sec(r'temp directories and fixtures'),
    ...para('--', r'H.tmpdir creates a unique directory under XYNO_TEST_TMP (or the system temp dir), registers it in H._dirs so cleanup removes it, and on non-Linux platforms returns the realpath: macOS /var is /private/var and cargo prints the latter, Windows has 8.3 short names. H.fixture copies a directory from tests/fixtures into a fresh temp dir, with cp -a on Linux and a recursive libuv copy elsewhere (BSD cp lacks --no-preserve and Windows has no cp), and optionally makes it a git repository with one commit. H.open_fixture additionally cds into the copy and opens a file. The rule is that a test never touches the committed fixture.'),
    ...code('lua', r'tests/helpers.lua · lines 369-382, 408-454', r'''
function H.tmpdir()
  local base = vim.env.XYNO_TEST_TMP
  if not base or base == "" then
    base = vim.fs.dirname(vim.fn.tempname())
  end
  local dir = assert(vim.uv.fs_mkdtemp(base .. "/spec-XXXXXX"))
  H._dirs[#H._dirs + 1] = dir
  if H.os ~= "linux" then
    -- one spelling of the path: macOS /var is /private/var (cargo prints the
    -- latter), Windows has short 8.3 names and backslashes
    dir = vim.fs.normalize(vim.uv.fs_realpath(dir) or dir)
  end
  return dir
end
...
function H.copy_tree(src, dest)
  local st = assert(vim.uv.fs_lstat(src))
  if st.type == "directory" then
    vim.fn.mkdir(dest, "p")
    for name in vim.fs.dir(src) do
      H.copy_tree(src .. "/" .. name, dest .. "/" .. name)
    end
  elseif st.type == "link" then
    assert(vim.uv.fs_symlink(assert(vim.uv.fs_readlink(src)), dest))
  else
    assert(vim.uv.fs_copyfile(src, dest))
  end
end

--- Copy tests/fixtures/<name> (a crate directory or a single .rs file) into a
--- fresh temp dir. Returns the path of the copy (directory, or file path).
--- opts.git = true makes the crate a git repository with one commit.
function H.fixture(name, opts)
  opts = opts or {}
  local src = H.fixtures .. "/" .. name
  local dir = H.tmpdir()
  if H.os == "linux" then
    local r = run({ "cp", "-a", "--no-preserve=ownership", src, dir .. "/" })
    assert(r.code == 0, "copying fixture " .. name .. ": " .. (r.stderr or ""))
  else
    H.copy_tree(src, dir .. "/" .. name) -- BSD cp lacks --no-preserve, Windows has no cp
  end
  local dest = dir .. "/" .. name
  if opts.git then
    H.git_init(vim.fn.isdirectory(dest) == 1 and dest or dir)
  end
  return dest
end

--- Copy a fixture, cd into the crate, open `rel` (default src/main.rs or the
--- file itself). Returns dir, bufnr.
function H.open_fixture(name, rel, opts)
  local dest = H.fixture(name, opts)
  if vim.fn.isdirectory(dest) == 1 then
    vim.cmd.cd(vim.fn.fnameescape(dest))
    return dest, H.open(dest .. "/" .. (rel or "src/main.rs"))
  end
  vim.cmd.cd(vim.fn.fnameescape(vim.fs.dirname(dest)))
  return vim.fs.dirname(dest), H.open(dest)
end

--- Run a bash script inside the 99 sandbox wrapper (config.agent_sandbox)'''),
    ...sec(r'git with a fixed identity'),
    ...para('--', r'H.git passes user.name, user.email and commit.gpgsign=false on the command line, so it works on a CI machine with no git identity and on a developer machine with signing configured. A failing git command raises with the command, the exit code and stderr. git_init makes a repository with branch main and one commit.'),
    ...code('lua', r'tests/helpers.lua · lines 389-406', r'''
--- Run git in `dir` with a fixed identity; returns trimmed stdout, raises on failure.
function H.git(dir, ...)
  local cmd = { "git", "-c", "user.name=t", "-c", "user.email=t@t", "-c", "commit.gpgsign=false", ... }
  local r = run(cmd, { cwd = dir })
  if r.code ~= 0 then
    error(("git %s failed (%d): %s"):format(table.concat({ ... }, " "), r.code, r.stderr), 2)
  end
  return vim.trim(r.stdout)
end

--- git init + one commit of everything in `dir`.
function H.git_init(dir)
  H.git(dir, "init", "-q", "-b", "main")
  H.git(dir, "add", "-A")
  H.git(dir, "commit", "-q", "-m", "init")
  return dir
end
'''),
    ...sec(r'processes: sandbox, spawn, tmux'),
    ...para('--', r'sandbox_sh runs a bash script inside the real agent sandbox wrapper with a given project directory writable. It first calls need_sandbox, so a test that uses it skips cleanly where bwrap does not work, and it switches the working directory because wrap() uses nvim cwd, which the 99 plugin sets to the project. spawn registers a background process for cleanup. tmux runs tmux on a private socket named after the pid or XYNO_TMUX_PREFIX, so a spec can never attach to or kill the real tmux server.'),
    ...code('lua', r'tests/helpers.lua · lines 456-483', r'''
function H.sandbox_sh(script, project, opts)
  H.need_sandbox()
  local tmp = H.tmpdir()
  -- wrap() runs the command in nvim's cwd, which 99 sets to the project
  local prev = vim.fn.chdir(project)
  local cmd = assert(require("config.agent_sandbox").wrap({ "bash", "-c", script }, project, tmp))
  vim.fn.chdir(prev)
  return run(cmd, vim.tbl_extend("force", { cwd = project }, opts or {}))
end

--- Start a background process (killed by cleanup). Returns the vim.SystemObj.
function H.spawn(cmd, opts)
  local obj = vim.system(cmd, opts or {})
  H._jobs[#H._jobs + 1] = obj
  return obj
end

--- Run tmux on a private socket (one per call site key); the server is killed
--- by cleanup. First argument may be a socket-name suffix table {sock="x"}.
function H.tmux(args, sock)
  H.need_tmux()
  sock = ("%s-%s"):format(vim.env.XYNO_TMUX_PREFIX or ("xynotest-" .. vim.uv.os_getpid()), sock or "main")
  H._tmux[sock] = true
  local cmd = { "tmux", "-L", sock }
  vim.list_extend(cmd, args)
  return run(cmd)
end
'''),
    ...sec(r'cleanup that cannot hang'),
    ...para('--', r'The cleanup function is where field experience shows. It runs registered restore callbacks, then drops the bufferline tabline and wipes all buffers without autocmds before waiting for anything. The comment explains: bufferline recomputes its tabline, quadratic in the buffer count, on every event while LSP clients are waited for; a spec with many buffers spun for minutes and nvim never exited. After that it stops LSP clients (waiting at most 2 seconds), kills tmux servers and spawned jobs, returns to the home directory, and deletes temp dirs. One more detail: the agent sandbox leaves an empty memory directory under ~/.claude/projects/<mangled dir>, and cleanup removes what a spec temp dir caused, with rmdir only, so a directory with anything in it stays. The comment says 33 of them had accumulated in the real directory during a field test.'),
    ...code('lua', r'tests/helpers.lua · lines 485-539', r'''
function H.cleanup()
  for _, fn in ipairs(H._restore) do
    pcall(fn)
  end
  H._restore = {}
  -- bufferline recomputes its tabline (quadratic in the buffer count) on every
  -- event while the LSP clients are waited for: a spec that had listed many
  -- buffers then spun for minutes and nvim never got to exit. Drop the tabline
  -- and the buffers (without autocmds) before anything waits.
  pcall(function()
    vim.o.showtabline = 0
    vim.o.tabline = ""
    vim.cmd("noautocmd silent! %bwipeout!")
  end)
  pcall(function()
    for _, c in ipairs(vim.lsp.get_clients()) do
      c:stop(true)
    end
    vim.wait(2000, function()
      return #vim.lsp.get_clients() == 0
    end, 20)
  end)
  for sock in pairs(H._tmux) do
    pcall(function()
      vim.system({ "tmux", "-L", sock, "kill-server" }):wait(5000)
    end)
  end
  H._tmux = {}
  for _, j in ipairs(H._jobs) do
    pcall(function()
      j:kill(15)
      j:wait(2000)
    end)
  end
  H._jobs = {}
  pcall(vim.cmd, "silent! %bwipeout!")
  pcall(vim.cmd, "cd " .. vim.fn.fnameescape(vim.env.HOME or "/"))
  for _, d in ipairs(H._dirs) do
    -- agent_sandbox.wrap() leaves an empty ~/.claude/projects/<dir>/memory
    -- behind (the mask's mount point): remove what a spec's temp dir caused
    -- (rmdir only: a directory with anything in it stays)
    local name = (vim.uv.fs_realpath(d) or d):gsub("[^%w]", "-")
    local proj = vim.uv.os_homedir() .. "/.claude/projects/" .. name
    -- (also the ones of a project below the temp dir, e.g. <dir>/basic: field test, the
    -- sandbox specs had left 33 of them in the real ~/.claude/projects)
    for _, p in ipairs(vim.list_extend({ proj }, vim.fn.glob(proj .. "-*", true, true))) do
      vim.uv.fs_rmdir(p .. "/memory")
      vim.uv.fs_rmdir(p)
    end
    vim.fn.delete(d, "rf")
  end
  H._dirs = {}
end

return H'''),
    ...sec(r'trade-offs'),
    blank,
    ...pt('--', r'Helpers know about the config', r'sandbox_available and sandbox_sh call config.agent_sandbox directly. The suite and the config are one repo and test the real wrapper, so this coupling is intended.'),
    ...pt('--', r'Everything is best effort at the end', r'cleanup is wrapped in pcall at every step. A failure to kill a job must not hide a test result, and the runner prints the result before cleanup anyway.'),
    ...sec(r'how it is tested'),
    ...para('--', r'harness_spec.lua covers deep eq, wait_for, feed, capture_notify, fixture copying, git repositories and cleanup removing its temp dirs, and the sandbox wrapper test at its end checks the project stays writable while the rest of the disk is read-only. The Windows tolerance in eq has no dedicated test in that file; it is exercised by the specs that run in the platforms workflow.'),
  ],
);
