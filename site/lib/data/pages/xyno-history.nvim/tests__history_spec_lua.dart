import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-history.nvim/tests/history_spec.lua',
  lines: [
    cm('--', r'──────────────────────────────────────────'),
    cm('--', r'history_spec.lua — a hermetic suite for a plugin that shells out to git'),
    cm('--', r'a fake git that hangs on command, a clock that jumps, child nvims that race'),
    cm('--', r'──────────────────────────────────────────'),
    kv(r'role', r'the only spec file: 65 tests'),
    kv(r'language', r'Lua, run with nvim -l tests/run.lua; Linux and macOS only'),
    kv(r'size', r'1,711 lines, about twice the size of the module it tests'),
    kv(r'needs', r'git, bash, sleep, kill -0'),
    kv(r'history', r'added in b6b25d9 (2026-10-22, Add specs, a headless runner and a lazy.nvim smoke test)'),
    ...sec(r'why this file exists'),
    ...para('--', r'This plugin lives on timing, concurrency and the failure modes of a child process. A test '
        r'suite that only checked the happy path would pass while the plugin lost a snapshot under '
        r'a race, or hung the editor at exit, or filled .git with a very large blob. The suite '
        r'therefore takes control of everything nondeterministic: git, the clock, the timers, the '
        r'process tree and the repository. The header states the approach in a few comment lines.'),
    ...code('lua', r'tests/history_spec.lua · lines 1-6', r'''
-- xyno_history (snapshots of the worktree on refs/lochist/*, the
-- :LocalHistory* commands).
-- Hermetic: temp repos, a private GIT_CONFIG_GLOBAL, a logging/fault-injecting
-- `git` wrapper first in PATH (hangs, failures, lock errors, delays), timers
-- and os.time are shimmed where the real thing would take a minute.
-- xyno-os: linux,macos (bash stubs, sleep, kill -0)
'''),
    ...para('--', r'The platform line is precise about why. The suite needs bash stubs, sleep and kill -0, so '
        r'the spec declares linux and macos, and tests/run.lua skips it on Windows with that '
        r'reason. The README draws the conclusion honestly: no evidence at all for Windows, and '
        r'macOS untested here.'),
    ...sec(r'a fake git that fails on request'),
    ...code('lua', r'tests/history_spec.lua · lines 38-63', r'''
-- the fake git: logs "<GIT_INDEX_FILE>\t<args>", then does what ctl/<subcommand> says
write(
  base .. "/bin/git",
  [[#!/bin/bash
d="$XYNO_FAKE"
if [ -n "$d" ] && [ -d "$d" ]; then
  printf '%s\t%s\n' "$GIT_INDEX_FILE" "$*" >> "$d/log"
  if [ -f "$d/$1" ]; then
    mode=$(head -n1 "$d/$1")
    case "$mode" in
      hang) echo $$ > "$d/$1.pid"; exec sleep 600 ;;
      fail) echo "fatal: injected failure" >&2; exit 128 ;;
      failonce) rm -f "$d/$1"; echo "fatal: injected failure" >&2; exit 128 ;;
      lockindex) echo "fatal: Unable to create '$GIT_INDEX_FILE.lock': File exists." >&2; exit 128 ;;
      lockonce:*) rm -f "$d/$1"; echo "fatal: Unable to create '${mode#lockonce:}': File exists." >&2; exit 128 ;;
      slowonce:*) rm -f "$d/$1"; echo $$ > "$d/$1.pid"; sleep "${mode#slowonce:}" ;;
      failif:*) case "$*" in *"${mode#failif:}"*) echo "fatal: injected failure" >&2; exit 128 ;; esac ;;
      slow:*) echo $$ > "$d/$1.pid"; sleep "${mode#slow:}" ;;
      snapindex) cp "$GIT_INDEX_FILE" "$d/index-before" 2>/dev/null ;;
    esac
  fi
fi
exec "]] .. REAL_GIT .. [[" "$@"
]]
)
vim.fn.setfperm(base .. "/bin/git", "rwxr-xr-x")
'''),
    ...para('--', r'This is the most inventive piece of the file. A bash script named git is written into a '
        r'temporary bin directory that comes first on PATH. It appends the index file and the '
        r'arguments of every call to a log, then looks for a control file named after the git '
        r'subcommand. The content of that file picks a behaviour: hang (record the pid and sleep '
        r'for ten minutes), fail, fail once, a lock error naming the index file, a lock error '
        r'naming a given path once, a slow command, a failure only when the arguments contain a '
        r'pattern, or a copy of the index taken before the command runs. Anything else, and every '
        r'case with no control file, execs the real git. So the plugin is exercised against real '
        r'git behaviour, with faults injected exactly where a test wants them, and the log makes '
        r'the order of calls assertable. GIT_CONFIG_GLOBAL points to a private config with a global '
        r'ignore file, so the global-ignore tests are repeatable, and GIT_CONFIG_NOSYSTEM stops the '
        r'system config from interfering.'),
    ...sec(r'a clock that can jump, timers that run fast'),
    ...code('lua', r'tests/history_spec.lua · lines 77-91', r'''
  local real_time, real_defer, real_new_timer = os.time, vim.defer_fn, uv.new_timer
  os.time = function(t)
    if t then
      return real_time(t)
    end
    return real_time() + time_offset
  end
  vim.defer_fn = function(fn, ms)
    deferred[#deferred + 1] = ms
    if scale_watchdog and ms == 30000 then
      ms = 300
    end
    return real_defer(fn, ms)
  end
  -- proxy: records start() timeouts, divides them by timer_scale when set
'''),
    ...code('lua', r'tests/history_spec.lua · lines 92-118', r'''
  uv.new_timer = function()
    local real = real_new_timer()
    -- only the timers of xyno_history/init.lua (vim.defer_fn makes timers too)
    local src = debug.getinfo(2, "S").source
    if not src:find("xyno_history/init.lua", 1, true) then
      return real
    end
    timer_news = timer_news + 1
    return setmetatable({ real = real }, {
      __index = function(self, k)
        return function(_, ...)
          local args = { ... }
          if k == "start" then
            timer_starts[#timer_starts + 1] = args[1]
            if timer_scale then
              args[1] = math.max(1, math.floor(args[1] / timer_scale))
            end
          end
          return self.real[k](self.real, unpack(args))
        end
      end,
    })
  end
  H._restore[#H._restore + 1] = function()
    os.time, vim.defer_fn, uv.new_timer = real_time, real_defer, real_new_timer
    for k, v in pairs(saved) do
      vim.env[k] = v
'''),
    ...para('--', r'The plugin throttles on os.time and arms timers of 60 seconds. The spec replaces os.time '
        r'with a function that adds an offset, so a test can move forward 59 seconds and then 60 '
        r'and observe the boundary. It wraps vim.defer_fn to record the requested delays and to '
        r'shorten the 30 second watchdog to 300 milliseconds, and it proxies uv.new_timer so that '
        r'the start delays are recorded and optionally divided by a scale. The proxy checks the '
        r'caller’s source file and only wraps timers created by xyno_history/init.lua, because '
        r'vim.defer_fn also creates timers and the test must not disturb them. The test of the '
        r'watchdog therefore asserts that the requested delay was 30000 even though it ran for 300; '
        r'the pending list at the end of the file admits that a real 30 second wait is not tested.'),
    ...sec(r'reaching into the module’s state'),
    ...code('lua', r'tests/history_spec.lua · lines 124-157', r'''
local function upv(fn, name, seen)
  seen = seen or {}
  if seen[fn] then
    return nil
  end
  seen[fn] = true
  local i = 1
  while true do
    local n, v = debug.getupvalue(fn, i)
    if not n then
      break
    end
    if n == name then
      return v
    end
    i = i + 1
  end
  i = 1
  while true do
    local n, v = debug.getupvalue(fn, i)
    if not n then
      break
    end
    if type(v) == "function" then
      local r = upv(v, name, seen)
      if r ~= nil then
        return r
      end
    end
    i = i + 1
  end
end
local function state(name)
  return upv(LH.snapshot, name)
'''),
    ...para('--', r'The module keeps its state in file-local variables, and a test sometimes needs to see '
        r'them, for example whether a timer is still referenced or whether the pending flag was '
        r'cleared. upv walks the upvalues of M.snapshot and of the functions it references, looking '
        r'for a variable by name. This is introspection through the debug library, and it ties the '
        r'tests to the names of the variables in init.lua, which is the cost of '
        r'not exporting test hooks from the plugin. reset_module_state clears those '
        r'tables between tests so that no test inherits another’s throttle.'),
    ...sec(r'repositories and synchronous snapshots'),
    ...code('lua', r'tests/history_spec.lua · lines 231-261', r'''
local function mkrepo(files)
  local dir = H.tmpdir()
  local root = uv.fs_realpath(dir) .. "/repo"
  vim.fn.mkdir(root, "p")
  G(root, "init", "-q", "-b", "main")
  for rel, text in pairs(files or { ["a.txt"] = "a\n" }) do
    write(root .. "/" .. rel, text)
  end
  G(root, "add", "-A")
  G(root, "commit", "-q", "-m", "init")
  return root
end

--- Synchronous snapshot: forced by default; returns the commit (nil when nothing changed or failed).
local function snap(root, opts)
  opts = vim.tbl_extend("force", { path = root, force = true }, opts or {})
  local called, commit = false, nil
  local user_done = opts.done
  opts.done = function(c)
    called, commit = true, c
    if user_done then
      user_done(c)
    end
  end
  LH.snapshot(opts)
  H.wait_for(function()
    return called
  end, 30000, "snapshot done callback")
  return commit
end

'''),
    ...para('--', r'mkrepo creates a repository in a temporary directory with one commit on a branch called '
        r'main, resolving the real path so that symlinked temp directories do not confuse '
        r'comparisons. snap wraps the asynchronous snapshot in a waiter: it forces the snapshot '
        r'unless the test says otherwise, passes a done callback, and waits for it up to 30 seconds '
        r'with the shared wait_for helper. The rest of the file then reads like sequential code.'),
    ...sec(r'the contract of the snapshot'),
    ...code('lua', r'tests/history_spec.lua · lines 483-520', r'''
  it("commits the whole worktree incl. untracked files; real index, stash, branches, HEAD, status untouched", function()
    local root = mkrepo({ ["a.txt"] = "a\n", ["b.txt"] = "b\n" })
    write(root .. "/a.txt", "a changed unstaged\n")
    write(root .. "/b.txt", "b staged\n")
    G(root, "add", "b.txt")
    write(root .. "/new.txt", "untracked\n")
    G(root, "stash", "push", "-q", "-m", "mine")
    write(root .. "/a.txt", "a changed again\n")
    write(root .. "/new.txt", "untracked\n")
    local before = {
      status = G(root, "status", "--porcelain"),
      head = G(root, "rev-parse", "HEAD"),
      stash = G(root, "stash", "list"),
      branches = G(root, "for-each-ref", "refs/heads", "refs/stash", "refs/tags"),
    }
    local c = snap(root)
    H.ok(c, "a commit")
    H.eq(c, tip(root, "refs/lochist/main"))
    H.eq(before.status, G(root, "status", "--porcelain"))
    H.eq(before.head, G(root, "rev-parse", "HEAD"))
    H.eq(before.stash, G(root, "stash", "list"))
    H.eq(before.branches, G(root, "for-each-ref", "refs/heads", "refs/stash", "refs/tags"))
    H.eq({ "refs/lochist/main" }, lochist_refs(root))
    H.eq("a changed again\n", blob(root, c, "a.txt"))
    H.eq("b\n", blob(root, c, "b.txt"))
    H.eq("untracked\n", blob(root, c, "new.txt"))
    H.eq(
      "xyno-history|lochist@xyno-history|xyno-history|lochist@xyno-history|autosave",
      G(root, "log", "-1", "--format=%an|%ae|%cn|%ce|%s", c)
    )
    -- label override + the parent chain
    write(root .. "/new.txt", "untracked 2\n")
    local c2 = snap(root, { label = "before 99 request" })
    H.ok(c2 and c2 ~= c)
    H.eq("before 99 request", subject(root, c2))
    H.eq(c, G(root, "rev-parse", c2 .. "^"))
  end)

'''),
    ...para('--', r'This test pins down the claim of the README that the user’s repository is untouched. It '
        r'stages one file, modifies another, stashes work, creates an untracked file and records '
        r'status, HEAD, stash list and the refs under heads, stash and tags. After the snapshot all '
        r'of those are compared and must be equal; the commit holds the changed, staged and '
        r'untracked contents; the only lochist ref is the one for main; the author, committer and '
        r'subject are the plugin’s own identity and autosave; and a second snapshot with a label '
        r'has the right subject and the first as parent.'),
    ...sec(r'throttle and the trailing timer'),
    ...code('lua', r'tests/history_spec.lua · lines 937-960', r'''
  it("a save inside the window arms ONE unref'd trailing timer for ~61 s that snapshots the last save's content", function()
    local root = mkrepo()
    H.ok(snap(root, { force = false }))
    local c1 = tip(root, "refs/lochist/main")
    timer_scale = 50
    local before_news = timer_news
    for i = 2, 4 do
      write(root .. "/a.txt", "save " .. i .. "\n")
      LH.snapshot({ path = root })
    end
    H.eq(1, timer_news - before_news, "one timer for three saves")
    H.eq(1, #timer_starts)
    H.ok(timer_starts[1] >= 59000 and timer_starts[1] <= 61000, "due in " .. timer_starts[1] .. " ms")
    H.eq(false, state("timers")[root].real:has_ref(), "unref'd, never keeps nvim alive")
    H.eq(c1, tip(root, "refs/lochist/main"))
    H.wait_for(function()
      return tip(root, "refs/lochist/main") ~= c1
    end, 15000, "trailing snapshot")
    H.eq("save 4\n", blob(root, "refs/lochist/main", "a.txt"))
    H.is_nil(state("timers")[root])
    H.is_nil(state("pending")[root])
    H.eq(2, count(root, "refs/lochist/main"))
  end)

'''),
    ...para('--', r'The trailing timer is tested with the clock and timer shims together. After a first '
        r'snapshot, three more saves in the window are made; the test asserts one timer was created '
        r'for three saves, that its delay lies between 59 and 61 seconds, that it is unreferenced '
        r'so it cannot keep Neovim alive, and that the tip has not moved. Then, with the scale set '
        r'to 50, the timer fires after a moment and the new tip contains the last save’s content, '
        r'the timer and pending entries are cleared, and exactly two snapshots exist.'),
    ...sec(r'compare-and-swap, as an assertion on the call log'),
    ...code('lua', r'tests/history_spec.lua · lines 1137-1169', r'''
  it("moves the ref with compare-and-swap (update-ref <ref> <new> <old>) and rebuilds the tree after reading the parent", function()
    local root = mkrepo()
    local c1 = snap(root)
    write(root .. "/a.txt", "two\n")
    local c2 = snap(root)
    local first, second
    for _, l in ipairs(fake_log()) do
      local args = l:match("^[^\t]*\t(update%-ref refs/lochist/main .*)$")
      if args then
        if not first then
          first = args
        else
          second = args
        end
      end
    end
    H.eq(("update-ref refs/lochist/main %s "):format(c1), first, "first: old value empty")
    H.eq(("update-ref refs/lochist/main %s %s"):format(c2, c1), second)
    -- order: the parent is read (rev-parse -q --verify ref) before add runs
    local ver, add
    for i, l in ipairs(fake_log()) do
      if not ver and l:find("rev-parse -q --verify refs/lochist/main", 1, true) then
        ver = i
      end
      if not add and l:find("\tadd ", 1, true) then
        add = i
      end
    end
    H.ok(ver and add and ver < add, "parent read before the tree is built")
  end)
end)

-- ------------------------------------------------------- 17. stale indexes
'''),
    ...para('--', r'The test of the CAS discipline reads the fake git’s log. The first update-ref names the '
        r'new commit and an empty old value, the second names the new commit and the previous one, '
        r'and the parent is read with rev-parse before add ever runs. The order of calls is the '
        r'proof of the fix from xynovim, where the tree used to be built before the parent was read.'),
    ...sec(r'real processes, real races'),
    ...code('lua', r'tests/history_spec.lua · lines 1251-1274', r'''
local function child(root, mode, env)
  local script = base .. "/child.lua"
  if not uv.fs_stat(script) then
    write(script, child_script)
  end
  local e = vim.tbl_extend("force", { XYNO_REPO = H.repo, XYNO_ROOT = root, XYNO_MODE = mode }, env or {})
  return vim.system(
    { vim.v.progpath, "--headless", "-u", "NONE", "-i", "NONE", "-n", "-c", "luafile " .. script },
    { env = e, text = true }
  )
end

describe("exit and concurrency (child nvim processes)", function()
  it("save then qa!: VimLeavePre records the final content with ONE snapshot and nvim exits quickly", function()
    local root = mkrepo()
    local t0 = uv.hrtime()
    local r = child(root, "pending"):wait(30000)
    local ms = (uv.hrtime() - t0) / 1e6
    H.eq(0, r.code, r.stderr)
    H.ok(ms < 4000, ("nvim took %d ms to exit"):format(ms))
    H.eq("final\n", blob(root, "refs/lochist/main", "f.txt"))
    H.eq(1, count(root, "refs/lochist/main"), "one synchronous snapshot")
    H.eq("autosave", subject(root, "refs/lochist/main"))
  end)
'''),
    ...code('lua', r'tests/history_spec.lua · lines 1291-1327', r'''
  it("6 concurrent nvims x 3 snapshots: compare-and-swap loses no snapshot, every reported commit is on the ref", function()
    -- NOTE: not "18 commits" strictly: a snapshot whose tree an earlier racer's commit already contains
    -- (it saw the file in its own `git add`) is a legitimate no-op (done(nil)), so the count depends on timing.
    local root = mkrepo()
    local procs = {}
    for id = 1, 6 do
      procs[id] = child(root, "concurrent", { XYNO_ID = tostring(id), XYNO_OUT = base .. "/out" .. id .. ".txt" })
    end
    for id, p in ipairs(procs) do
      local r = p:wait(100000)
      H.eq(0, r.code, ("child %d: %s%s"):format(id, r.stdout or "", r.stderr or ""))
    end
    local seen, nils = {}, 0
    for id = 1, 6 do
      local lines = vim.fn.readfile(base .. "/out" .. id .. ".txt")
      H.eq(3, #lines)
      for _, c in ipairs(lines) do
        if c == "nil" then
          nils = nils + 1
        else
          seen[c] = true
        end
      end
    end
    local n = count(root, "refs/lochist/main")
    H.eq(n, vim.tbl_count(seen), "every commit on the ref was reported by exactly one snapshot")
    H.ok(n >= 3 and n <= 18, "commits: " .. n .. " (no-ops: " .. nils .. ")")
    H.eq(18, n + nils, "each of the 18 snapshots either committed or found its content already recorded")
    H.eq("", G(root, "rev-list", "--merges", "refs/lochist/main"), "one linear chain")
    local files = names(root, "refs/lochist/main")
    H.eq(19, #files, "a.txt + all 18 files are in the tip: nothing was overwritten")
    fsck_clean(root)
  end)
end)

-- ------------------------------------------------ 21-22. browse and restore

'''),
    ...para('--', r'The exit and concurrency tests start child Neovim processes with vim.system and wait for '
        r'them. One saves, then quits with qa!, and the test asserts the exit took less than four '
        r'seconds, the final content is on the ref with a single synchronous snapshot, and the '
        r'subject is autosave. Another injects a slow commit-tree, quits while it is in flight, and '
        r'checks the git process was killed and the snapshot redone. The concurrency test starts '
        r'six Neovims that each make three snapshots in the same repository and checks that the '
        r'count of commits on the ref plus the number of no-op snapshots is 18, that every reported '
        r'commit is on the ref, that the history is one linear chain with no merges, that all 19 '
        r'files are present in the tip (nothing was overwritten) and that fsck is clean. The '
        r'comment inside shows careful reasoning: the exact number of commits is not asserted, '
        r'because a snapshot whose tree an earlier racer already recorded is legitimately a no-op.'),
    ...sec(r'the auto-save convention'),
    ...code('lua', r'tests/history_spec.lua · lines 1677-1701', r'''
describe("auto-save integration", function()
  it("User AutoSaveWritePost snapshots only when the buffer is no longer modified (a refused write leaves none)", function()
    local root = mkrepo()
    local buf = open_file(root, "a.txt")
    -- refused write (disk_guard): still modified -> no snapshot
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "unsaved" })
    H.eq(true, vim.bo[buf].modified)
    vim.api.nvim_exec_autocmds("User", { pattern = "AutoSaveWritePost", data = { saved_buffer = buf } })
    vim.wait(700)
    H.is_nil(tip(root, "refs/lochist/main"))
    H.eq(0, log_count("\tadd "))
    -- written: snapshot (content of the disk file)
    write(root .. "/a.txt", "on disk\n")
    vim.cmd("silent! checktime")
    vim.api.nvim_buf_call(buf, function()
      vim.cmd("silent! edit!")
    end)
    H.eq(false, vim.bo[buf].modified)
    vim.api.nvim_exec_autocmds("User", { pattern = "AutoSaveWritePost", data = { saved_buffer = buf } })
    H.wait_for(function() return tip(root, "refs/lochist/main") end, 15000, "snapshot")
    H.eq("on disk\n", blob(root, "refs/lochist/main", "a.txt"))
    -- no data / invalid buffer: no error
    H.ok(pcall(vim.api.nvim_exec_autocmds, "User", { pattern = "AutoSaveWritePost" }))
    H.ok(pcall(vim.api.nvim_exec_autocmds, "User", { pattern = "AutoSaveWritePost", data = { saved_buffer = 99999 } }))
  end)
'''),
    ...para('--', r'The final group simulates the user event of an auto-save plugin without installing one. A '
        r'modified buffer plus the event creates no snapshot and the fake git log has zero add '
        r'calls; after the file is written and the buffer reloaded, the same event makes a snapshot '
        r'of the disk content. Missing data and an invalid buffer must not raise. The comment calls '
        r'the refusing component disk_guard, the name of the module in xynovim; in the published '
        r'family it is xyno-guard.nvim.'),
    ...sec(r'what the suite says it did not verify'),
    ...code('lua', r'tests/history_spec.lua · lines 1706-1711', r'''
pending("picker UI (vim.ui.select with the real telescope/snacks picker)", "the tests drive vim.ui.select with a stub; the visual picker was not exercised")
pending("undo of :LocalHistoryRestore in a real interactive session", "only `u` through feedkeys in headless nvim is covered")
pending("the 30 s watchdog with a real 30 s wait", "the test shortens the 30000 ms defer to 300 ms and asserts the requested delay was 30000")
pending("the 60 s stale ref-lock rule against a lock aged exactly 60 s", "only a 120 s old (removed) and a fresh (kept) lock are tested")
pending("a repository with a submodule", "not tested; only nested repos with and without commits")
pending("thousands of snapshots (performance of log/prune)", "the largest history built is 120 commits")
'''),
    ...para('--', r'The file ends with pending entries, a feature of the harness that registers a named test '
        r'with a reason and counts it as skipped. They are an honest list: the real picker UI, undo '
        r'of a restore in an interactive session, the real 30 second watchdog, a lock aged exactly '
        r'60 seconds, a repository with a submodule, and thousands of snapshots. Each says what the '
        r'existing test does cover instead.'),
    ...sec(r'history'),
    ...pt('--', r'b6b25d9', r'2026-10-22: the spec, the runner, the helpers, the harness and the end-to-end files '
        r'arrive together.'),
  ],
);
