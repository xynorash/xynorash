import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/tests/local-history_spec.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'local-history_spec.lua — a safety net made of git refs, attacked with a lying git'),
    cm('--', r'snapshots that never touch your index, throttle and watchdog timers on a fake clock, locks, crashes and six concurrent editors'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'spec for lua/config/local_history.lua (snapshots on refs/lochist/*, the :LocalHistory commands) and its 99 integration'),
    kv(r'language', r'Lua spec, 1743 lines, 64 it() blocks, 6 pending, 19 describe() blocks'),
    kv(r'platform', r'Linux and macOS (an xyno-os header: bash stubs, sleep, kill -0)'),
    kv(r'method', r'temp repos, a private GIT_CONFIG_GLOBAL, a logging and fault-injecting git wrapper first in PATH, shimmed timers and os.time'),
    kv(r'history', r'9 commits, 2026-10-13 to 2026-10-21'),
    ...sec(r'why this file exists'),
    ...para('--', r'Local history is the answer to the question of what to do when an editor, a formatter or an agent destroys uncommitted work. Every save (throttled) records the whole worktree, including untracked files, as a commit on a ref under refs/lochist/, one chain per branch, without touching the index, the stash, HEAD, the branches or the status. The agent integration takes a forced snapshot labelled before 99 request before every agent request. A feature whose purpose is to be there when things go wrong has to be correct when git itself fails: hangs, lock files, concurrent processes, a crash while quitting. So the spec cannot use the happy path. Its header says that it is hermetic, uses temp repos and a private global git config, puts a fake git first in PATH that logs every call and can hang or fail on command, and replaces timers and os.time where the real thing would take a minute.'),
    ...code('lua', r'tests/local-history_spec.lua · lines 1-6', r'''
-- config/local_history.lua (snapshots of the worktree on refs/lochist/*, the
-- :LocalHistory* commands) and its 99 integration (plugins/ninety-nine.lua).
-- Hermetic: temp repos, a private GIT_CONFIG_GLOBAL, a logging/fault-injecting
-- `git` wrapper first in PATH (hangs, failures, lock errors, delays), timers
-- and os.time are shimmed where the real thing would take a minute.
-- xyno-os: linux,macos (bash stubs, sleep, kill -0)'''),
    ...sec(r'the lying git'),
    ...para('--', r'Everything depends on the wrapper in front of git, a bash script written into the temp base directory. It appends one line per call (the index file in use, a tab, the arguments) to a log, and then looks for a control file named after the subcommand. The first line of that file is the mode: hang writes the pid and sleeps for 600 seconds; fail exits 128 with an injected failure; failonce does so once; lockindex and lockonce print the Unable to create lock message git prints; slow and slowonce sleep; failif fails only when the arguments contain a string. In every other case it execs the real git. Tests then ask the log what happened. The same block shims os.time so that a test can move the clock. time_offset moves the clock forward, timer_scale shortens a timer, and deferred records the delays that were requested, so that a test can assert the real delay of 30000 ms while having waited only 300 ms.'),
    ...code('lua', r'tests/local-history_spec.lua · lines 41-65, 80-93', r'''
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
...
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
  -- proxy: records start() timeouts, divides them by timer_scale when set'''),
    ...sec(r'a snapshot changes nothing but the ref'),
    ...para('--', r'The core promise is tested with a repo in a hard state: a staged file, an unstaged change, an untracked file and a stash entry. The test records status, HEAD, the stash list and the branch refs, takes a snapshot, and compares all of them with the saved values. Then it reads the blobs from the commit and finds the worktree content: a.txt as changed again, b.txt as b (the stash had taken the staged change), and the untracked new.txt. The commit has the author and committer xynovim and the message autosave, and a second snapshot with a label has the right subject and the first as its parent.'),
    ...code('lua', r'tests/local-history_spec.lua · lines 465-501', r'''
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
      "xynovim|lochist@xynovim|xynovim|lochist@xynovim|autosave",
      G(root, "log", "-1", "--format=%an|%ae|%cn|%ce|%s", c)
    )
    -- label override + the parent chain
    write(root .. "/new.txt", "untracked 2\n")
    local c2 = snap(root, { label = "before 99 request" })
    H.ok(c2 and c2 ~= c)
    H.eq("before 99 request", subject(root, c2))
    H.eq(c, G(root, "rev-parse", c2 .. "^"))
  end)'''),
    ...sec(r'a private index'),
    ...para('--', r'git add needs an index. Using the real one would disturb a user staging area, so snapshots use GIT_INDEX_FILE=.git/lochist-index.<pid>. The test refreshes the real index, remembers its bytes and its mtime in seconds and nanoseconds, takes a snapshot, and requires both unchanged. It then walks the git log of the wrapper and requires that every add, write-tree and commit-tree call ran with the private index, and that all three ran.'),
    ...code('lua', r'tests/local-history_spec.lua · lines 503-525', r'''
  it("uses a private index (GIT_INDEX_FILE=.git/lochist-index.<pid>), the real .git/index is not modified", function()
    local root = mkrepo({ ["a.txt"] = "a\n" })
    write(root .. "/new.txt", "n\n")
    G(root, "status", "--porcelain") -- refreshes the real index first
    local real = root .. "/.git/index"
    local bytes, st = read(real), uv.fs_stat(real)
    H.ok(snap(root))
    H.eq(bytes, read(real), "real index content")
    local st2 = uv.fs_stat(real)
    H.eq(st.mtime.sec, st2.mtime.sec)
    H.eq(st.mtime.nsec, st2.mtime.nsec)
    local mine = root .. "/.git/lochist-index." .. uv.os_getpid()
    H.ok(uv.fs_stat(mine) and uv.fs_stat(mine).size > 0, "private index exists")
    local seen = {}
    for _, l in ipairs(fake_log()) do
      local idx, args = l:match("^(.-)\t(%S+)")
      if args == "add" or args == "write-tree" or args == "commit-tree" then
        H.eq(mine, idx, args .. " must run with the private index")
      end
      seen[args or ""] = true
    end
    H.ok(seen.add and seen["write-tree"] and seen["commit-tree"], "add, write-tree, commit-tree ran")
  end)'''),
    ...sec(r'refs, excludes and size limits'),
    ...para('--', r'Branch names with slashes and percent signs are encoded so foo and foo/bar do not collide as files; a detached HEAD uses refs/lochist/%detached-<12 char sha>; legacy refs are renamed once, and a pre-existing target aborts the whole rename without losing anything. The target directories are excluded through anchored lines in .git/info/exclude (src/target/mod.rs stays), an older unanchored line is migrated, and a user exclude is not duplicated. Untracked files over a cap (10 MB by default, vim.g.xynovim_lochist_max_bytes) are left out with one notice; the size check runs in slices across event loop turns, so the test with many files still finds a big file in the last slice; a modified tracked file over the cap is left out too, since its blob would add its size each time. A total budget of 200 MB by default leaves the largest files out until the snapshot fits.'),
    ...sec(r'throttle and timers'),
    ...para('--', r'THROTTLE_S is 60. The test takes one snapshot, changes a file, moves the clock to 59 seconds and saves: the state records a pending snapshot and a trailing timer, and after 300 ms the ref still points to the first commit. At 60 seconds the next snapshot runs, and running it cancels the trailing timer and the pending flag. Further tests: a save inside the window arms one unref’d trailing timer of about 61 seconds that snapshots the content of the last save; a forced snapshot ignores the window; after a failure the retry waits behind a 10 second backoff with only one retry; a forced snapshot that finds another running retries after 500 ms instead of being dropped.'),
    ...code('lua', r'tests/local-history_spec.lua · lines 901-917', r'''
  it("THROTTLE_S=60: a non-forced save 59 s after the last snapshot waits, at 60 s it runs", function()
    local root = mkrepo()
    H.ok(snap(root, { force = false }))
    local c1 = tip(root, "refs/lochist/main")
    write(root .. "/a.txt", "v2\n")
    time_offset = 59
    LH.snapshot({ path = root })
    H.eq(true, state("pending")[root])
    H.ok(state("timers")[root], "trailing timer armed")
    vim.wait(300)
    H.eq(c1, tip(root, "refs/lochist/main"), "no commit inside the window")
    time_offset = 60
    local c2 = snap(root, { force = false })
    H.ok(c2 and c2 ~= c1, "runs once the window is over")
    H.is_nil(state("timers")[root], "running a snapshot cancels the trailing timer")
    H.is_nil(state("pending")[root])
  end)'''),
    ...sec(r'a hung git'),
    ...para('--', r'The watchdog test makes git add hang, starts a forced snapshot, waits for the pid file of the hung process and checks it is alive and the running state set. It then waits for the callback, asserts that the requested watchdog delay was 30000 ms, that done received nil, that the hung git process was killed, that the running state and run record are cleared, and after 600 ms that done was called exactly once. Last, it removes the hang and checks the next snapshot works. A pending entry at the end admits the limit: the test shortens the 30000 ms defer to 300 ms.'),
    ...code('lua', r'tests/local-history_spec.lua · lines 1024-1046', r'''
  it("the 30 s watchdog aborts a hung git (kills the child), clears the running state, done fires once", function()
    local root = mkrepo()
    scale_watchdog = true
    fake("add", "hang")
    local calls = 0
    local commit
    LH.snapshot({ path = root, force = true, done = function(c) calls, commit = calls + 1, c end })
    local pid = wait_pidfile("add")
    H.ok(pid_alive(pid), "git is hanging")
    H.eq(true, state("running")[root])
    H.wait_for(function() return calls > 0 end, 10000, "watchdog")
    H.has(deferred, 30000, "watchdog armed for 30 s")
    H.is_nil(commit)
    H.wait_for(function() return not pid_alive(pid) end, 5000, "hung git killed")
    H.is_nil(state("running")[root])
    H.is_nil(state("runs")[root])
    vim.wait(600)
    H.eq(1, calls, "finish() is idempotent: done called once")
    -- history works again
    scale_watchdog = false
    os.remove(ctl .. "/add")
    H.ok(snap(root), "next snapshot runs")
  end)'''),
    ...sec(r'locks and compare-and-swap'),
    ...para('--', r'Its own leftover index.lock is removed before add; a ref lock older than 60 seconds named in git stderr is removed, and a fresh one stays; a stale lock named by a failing git add is cleared and add retried; a lasting lock error notifies once. update-ref failing after 10 jittered attempts warns and does not count as a snapshot. The ordering test reads the fake git log to prove the safe protocol: the ref is moved with update-ref ref new old, the first time with an empty old value, the second time with the first commit, and the parent is read with rev-parse before add runs, so the tree is built after the parent is known.'),
    ...code('lua', r'tests/local-history_spec.lua · lines 1119-1148', r'''
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
  end)'''),
    ...sec(r'six editors at once'),
    ...para('--', r'The concurrency test starts six child nvim processes, each taking three snapshots of the same repository, with ids and output files in the environment. All must exit 0 within 100 seconds. The assertions are what compare-and-swap promises: every commit on the ref was reported by exactly one snapshot; the number of commits is between 3 and 18 because a snapshot whose tree an earlier commit already contains is a legitimate no-op (the comment in the test explains this); commits plus no-ops equal 18; the history is one linear chain with no merges; the tip contains a.txt and all 18 files, so nothing was overwritten; and git fsck is clean.'),
    ...code('lua', r'tests/local-history_spec.lua · lines 1273-1305', r'''
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
  end)'''),
    ...sec(r'exit and crashes'),
    ...para('--', r'Child nvims also cover saving then qa!: VimLeavePre records the final content with one snapshot and nvim exits quickly; quitting while a snapshot is in flight kills the running git and redoes it synchronously. Stale index files of dead pids, their .lock files and the old shared index are deleted, the new one is seeded from the newest, and a live pid is spared.'),
    ...sec(r'the commands'),
    ...para('--', r':LocalHistory lists the snapshots of the current file newest first with age and message, in a vertical scratch diff; lists at most 100; leaves out the snapshots in which the file was deleted; warns outside a worktree and informs when there is no history. :LocalHistoryRestore replaces the buffer text without saving, leaves disk and the index alone, and cancel changes nothing; a snapshot without the file warns. :LocalHistoryPrune keeps the newest N per branch or the last N days (default 30d) and always keeps the newest; rejects 0, 0d, -1 and text; says nothing to prune; fails safely when a ref moved meanwhile; and the bang form runs git gc --prune=now and frees the space of a big deleted blob, even when there was nothing to drop. History is data in git, so the tests check that fsck is clean after pruning and that trees, messages and dates are unchanged.'),
    ...sec(r'documentation as tests'),
    ...para('--', r'Two tests check README promises by running them: snapshots accumulate until pruned, update-ref -d resets, they show in git log --all and push --mirror transfers them; and git restore --source=refs/lochist/<branch> --worktree -- <path> recovers a file without touching the index.'),
    ...sec(r'the integrations'),
    ...para('--', r'User AutoSaveWritePost snapshots only when the buffer is no longer modified, so a refused write by the disk guard leaves none. The 99 guard takes a forced snapshot labelled before 99 request before every request, throttle or not. See auto-save-disk-guard_spec.lua and agent-99-guard_spec.lua.'),
    ...sec(r'what is not tested'),
    ...para('--', r'Six pending entries list it: the visual picker (tests drive vim.ui.select with a stub), undo of the restore in a real interactive session, the 30 second watchdog with a real wait, the 60 second stale lock rule at exactly 60 s, a repository with a submodule, and thousands of snapshots (the largest history built is 120 commits).'),
    ...sec(r'history'),
    blank,
    ...pt('--', r'b2fee5c (2026-10-13)', r'created with the suite. 98c9bb4, a3d33c8, 3f868dd (2026-10-13) added anchored local history target, stat slices and tracked big files and prune from field tests.'),
    ...pt('--', r'f31e013, 25086fd (2026-10-14)', r'snapshot budget, throttle fix.'),
    ...pt('--', r'ff1c8fa (2026-10-16)', r'Linux and macOS header. 7025437 (2026-10-16) :: explicit sandbox opt-out in checkpoint tests. cd602fd (2026-10-21) :: BSD-safe sed stub.'),
  ],
);
