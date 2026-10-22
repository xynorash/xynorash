import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-history.nvim/lua/xyno_history/init.lua',
  lines: [
    cm('--', r'──────────────────────────────────────────'),
    cm('--', r'init.lua — a Local History kept inside git, on refs nobody else uses'),
    cm('--', r'snapshots of the whole worktree with a private index, written with compare-and-swap'),
    cm('--', r'──────────────────────────────────────────'),
    kv(r'role', r'the whole plugin: snapshot(), browse(), restore(), prune(), setup()'),
    kv(r'language', r'Lua (Neovim 0.12+), shells out to git through vim.system'),
    kv(r'size', r'844 lines, the largest file of the repository'),
    kv(r'storage', r'commits on refs/lochist/<encoded branch>, a private index .git/lochist-index.<pid>'),
    kv(r'history', r'6dfb326 (2026-10-22), extracted from xynovim lua/config/local_history.lua (first commit '
        r'8e212cf, 2026-10-09)'),
    ...sec(r'why this file exists'),
    ...para('--', r'The README states the motivation in two sentences: undofile does not survive a deleted '
        r'file, a git reset --hard, or an edit made by a tool that rewrote half the tree. A '
        r'snapshot of the whole worktree on every save does, and it can live inside git without '
        r'touching the index, the stash or any branch. This file is that idea made reliable. Almost '
        r'every line of it exists because something went wrong once: a lock left by a killed git, '
        r'two Neovims racing for one ref, a hundred thousand untracked files freezing the editor, a '
        r'build directory that was not supposed to be snapshotted. The comments name them.'),
    ...code('lua', r'lua/xyno_history/init.lua · lines 1-27', r'''
-- xyno-history: a Local History for Neovim, inspired by the JetBrains feature of that name (not affiliated
-- with JetBrains). Every (throttled) save also writes the
-- whole worktree - untracked files included, .gitignore respected, target/
-- excluded - as a commit on refs/lochist/<key>, using a private index file
-- so the real index/stash/branches are never touched. Survives what
-- undofile can't: deleted files, `git reset --hard`, edits made by an agent.
--
-- <key> is the branch with "%" -> "%25" and "/" -> "%2F" (so refs/lochist/foo
-- and refs/lochist/foo%2Fbar can never collide as file vs directory), or
-- "%detached-<short HEAD sha>" for a detached HEAD ("%" never starts an encoded
-- branch, so the two cannot clash). Old-style refs (refs/lochist/<raw branch>,
-- refs/lochist/detached) are no longer written. Old-style refs containing a
-- "/" are renamed to the encoded form on first use (they could block new
-- branches); the old "detached" ref is left alone and still read by
-- :LocalHistory.
-- Saves inside the throttle window are not lost: one trailing snapshot is
-- scheduled for the end of the window (and one more on exit if still pending
-- or still in flight: the running git is killed and the snapshot redone
-- synchronously).
-- Every nvim process uses its own index file (.git/lochist-index.<pid>), so
-- concurrent instances never fight over one index.lock; leftovers of dead
-- processes are cleaned up (the newest seeds the next one, so the first
-- `git add -A` stays incremental). Untracked files over
-- the max_bytes option (default 10 MB, <= 0 disables the cap) are
-- left out, and so are the largest files of a snapshot beyond
-- the max_total_bytes option (default 200 MB: thirty files just under the
-- per-file cap would add about 285 MB to .git). :LocalHistoryPrune trims old snapshots.
'''),
    ...para('--', r'The header is a specification. Every throttled save becomes a commit whose tree is the '
        r'entire worktree, untracked files included, .gitignore respected and the build directory '
        r'excluded, using a private index so that the user’s real index, stash and branches are '
        r'never touched. The plugin is described there as inspired by the JetBrains feature of the '
        r'same name and not affiliated with it, a sentence that was added in xynovim by 0247401 and '
        r'that the extracted repository’s README repeats.'),
    ...sec(r'the origin in xynovim'),
    ...para('--', r'The module began as lua/config/local_history.lua in xynovim. Its first commits are '
        r'8e212cf and 4fdd3fa (2026-10-09, both titled wip), then ac38272 and 0494b52 (review and '
        r'field-test fixes), and the history after that reads like a log of the failure modes the '
        r'code handles: b65284f (2026-10-13) added the exit snapshot, the per-process index, the '
        r'size cap and pruning; 7ac2a38 made the tree get built after the parent is read and '
        r'rebuilt on a compare-and-swap retry, so that concurrent Neovims do not leave a stale tip; '
        r'the five Final loop rounds on 2026-10-13 and 2026-10-14 added big tracked files, stat '
        r'slices, an anchored target path, the snapshot budget, and the throttle fixes. The '
        r'extraction changed the namespace, the setup options and the git author name, which the '
        r'README says.'),
    ...sec(r'state and tuning constants'),
    ...code('lua', r'lua/xyno_history/init.lua · lines 39-52', r'''
local THROTTLE_S = 60
local FAIL_BACKOFF_S = 10
local EXIT_BUDGET_MS = 5000
local MAX_BYTES = 10 * 1024 * 1024
local MAX_TOTAL_BYTES = 200 * 1024 * 1024
local last = {} ---@type table<string, number> time of the last SUCCESSFUL snapshot
local failed = {} ---@type table<string, number> time of the last failed one
local running = {} ---@type table<string, boolean>
local runs = {} ---@type table<string, { dead: boolean, child: vim.SystemObj? }>
local indexes = {} ---@type table<string, string> root -> this process's index file
local prepared = {} ---@type table<string, boolean>
local warned = {} ---@type table<string, boolean> notify-once keys
local timers = {} ---@type table<string, uv.uv_timer_t>
local deadline ---@type number? set (hrtime ms) only during the synchronous exit snapshot
'''),
    ...para('--', r'All state is file-local tables keyed by the repository root: last is the time of the last '
        r'successful snapshot, failed the last failure, running and runs the in-flight one, indexes '
        r'this process’s index file, prepared and migrated the once-per-session work, warned the '
        r'notify-once keys, timers the trailing-edge timers. Keying by root is what lets one Neovim '
        r'edit files in two repositories without them interfering. The constants are the policy: '
        r'one snapshot per 60 seconds, a 10 second backoff after a failure, a 5 second budget at '
        r'exit, 10 MB per file and 200 MB per snapshot. deadline is set only during the synchronous '
        r'exit snapshot, and its presence switches the whole git layer from asynchronous to '
        r'blocking.'),
    ...sec(r'one wrapper around git'),
    ...code('lua', r'lua/xyno_history/init.lua · lines 54-78', r'''
--- `run` (optional) lets a caller abandon the chain: once run.dead is set the
--- callback never fires, and run.child is the git process to kill.
local function git(args, root, env, cb, raw, run)
  local cmd = vim.list_extend({ "git" }, args)
  local function done(o)
    cb(o.code == 0 and (raw and (o.stdout or "") or vim.trim(o.stdout or "")) or nil, o)
  end
  if deadline then
    local left = deadline - vim.uv.hrtime() / 1e6
    if left <= 0 then
      return cb(nil, { code = 124, stderr = "exit budget exhausted" })
    end
    return done(vim.system(cmd, { cwd = root, env = env, text = true }):wait(math.floor(left)))
  end
  local child = vim.system(cmd, { cwd = root, env = env, text = true }, function(o)
    vim.schedule(function()
      if not (run and run.dead) then
        done(o)
      end
    end)
  end)
  if run then
    run.child = child
  end
end
'''),
    ...para('--', r'Every git call in a snapshot goes through this function. In the normal case it uses '
        r'vim.system with a callback and reschedules the result onto the main loop, which keeps the '
        r'editor responsive. The run object is the cancellation handle: once run.dead is set the '
        r'callback never fires, and run.child is the process to kill. In the exit case, where '
        r'deadline is set, the same call becomes a blocking wait with the remaining time, and if '
        r'the time is gone it returns a synthetic result with code 124. The one wrapper is why the '
        r'same chain of steps works both asynchronously and at exit without being written twice. '
        r'Output is trimmed unless raw is requested, and a non-zero exit gives nil, so callers test '
        r'for nil rather than for exit codes.'),
    ...code('lua', r'lua/xyno_history/init.lua · lines 80-94', r'''
--- Abandon the snapshot chain of `root`: no further callbacks, git child killed.
local function abort(root, wait)
  local run = runs[root]
  if not run then
    return
  end
  run.dead = true
  runs[root] = nil
  if run.child then
    pcall(run.child.kill, run.child, 9)
    if wait then
      pcall(run.child.wait, run.child, 1000)
    end
  end
end
'''),
    ...para('--', r'abort kills the child with signal 9 and optionally waits up to a second for it. It is '
        r'called from the watchdog and from the exit handler. warn_once is a small convenience that '
        r'every notice goes through, so a problem is reported once per key and not on every save.'),
    ...sec(r'refs, and how branch names are encoded'),
    ...code('lua', r'lua/xyno_history/init.lua · lines 103-118', r'''
local function encode(branch)
  return (branch:gsub("[%%/]", { ["%"] = "%25", ["/"] = "%2F" }))
end

--- cb(ref, legacy_ref?) : the ref to write and, for a detached HEAD, the
--- old-style shared "detached" ref (read-only).
local function ref_for(root, cb)
  git({ "symbolic-ref", "--short", "-q", "HEAD" }, root, nil, function(branch)
    if branch then
      return cb("refs/lochist/" .. encode(branch))
    end
    git({ "rev-parse", "--short=12", "-q", "--verify", "HEAD" }, root, nil, function(sha)
      cb("refs/lochist/%detached-" .. (sha or "none"), sha and "refs/lochist/detached" or nil)
    end)
  end)
end
'''),
    ...para('--', r'The ref for a branch is refs/lochist/ plus the branch name with percent and slash '
        r'escaped. The header explains why: git stores refs as files, so a ref for foo and a ref '
        r'for foo/bar would be a file and a directory of the same name and could not both exist. '
        r'Escaping the slash makes every branch a plain file, and escaping the percent first keeps '
        r'the encoding reversible. A detached HEAD gets refs/lochist/%detached- followed by 12 '
        r'characters of the commit id; since an encoded branch never starts with a percent sign, '
        r'the two namespaces cannot collide. The comment says the old-style names are no longer '
        r'written, and the function still returns the legacy detached ref as a second, read-only '
        r'value so that history made by older versions stays visible.'),
    ...code('lua', r'lua/xyno_history/init.lua · lines 137-141,155-167', r'''
local function migrate(root, cb)
  if migrated[root] then
    return cb()
  end
  migrated[root] = true
...
    local input = table.concat(cmds, "\n") .. "\n"
    -- one transaction; if the target already exists (create fails) nothing moves
    local function run()
      local cmd = { "git", "update-ref", "--stdin" }
      if deadline then
        vim.system(cmd, { cwd = root, stdin = input, text = true }):wait(2000)
        return cb()
      end
      vim.system(cmd, { cwd = root, stdin = input, text = true }, function()
        vim.schedule(cb)
      end)
    end
    run()
'''),
    ...para('--', r'migrate renames old directory-like refs to the encoded form once per repository per '
        r'session, with one git update-ref --stdin transaction of create and delete pairs. If a '
        r'target already exists, the create fails and nothing moves, which is the property the spec '
        r'tests with a pre-existing encoded target. Under the exit deadline the transaction runs '
        r'synchronously.'),
    ...sec(r'throttling: leading edge, trailing edge, backoff'),
    ...code('lua', r'lua/xyno_history/init.lua · lines 182-212', r'''
--- Earliest time a non-forced snapshot of `root` may start.
local function next_ok(root)
  return math.max((last[root] or 0) + THROTTLE_S, (failed[root] or 0) + FAIL_BACKOFF_S)
end

-- Arm (once) the trailing-edge timer for `root`. It is unref'd so it never
-- keeps nvim alive, and does nothing if the repo vanished meanwhile.
local function arm(root)
  if timers[root] then
    return
  end
  local wait_ms = math.max(1000, (next_ok(root) - os.time()) * 1000 + 500)
  local t = assert(vim.uv.new_timer())
  timers[root] = t
  t:unref()
  t:start(
    wait_ms,
    0,
    vim.schedule_wrap(function()
      if timers[root] ~= t then
        return
      end
      stop_timer(root)
      if vim.uv.fs_stat(root .. "/.git") then
        M.snapshot({ path = root, force = true, retried = true })
      else
        last[root] = nil
      end
    end)
  )
end
'''),
    ...para('--', r'A snapshot of a large worktree costs real work, so saves are throttled to one a minute. '
        r'The naive version of a throttle loses the last save of a burst, and that is the thing the '
        r'author did not accept: the module arms one trailing timer per repository for when the '
        r'window ends. next_ok is the earliest time a non-forced snapshot may start, the later of '
        r'the throttle and the failure backoff. The timer is unref’d, so it can never keep Neovim '
        r'alive, and it re-checks that it is still the current timer and that the repository still '
        r'exists. On firing it calls snapshot with force and retried, so the trailing snapshot '
        r'cannot itself schedule another. The test for this in the spec asserts that one save '
        r'inside the window arms exactly one unref’d timer for about 61 seconds that captures the '
        r'last save’s content.'),
    ...sec(r'preparing the repository: excludes and stale indexes'),
    ...code('lua', r'lua/xyno_history/init.lua · lines 234-237,261-279', r'''
  local want = { "/target/" }
  for _, c in ipairs(vim.list_extend(vim.fn.glob(root .. "/*/Cargo.toml", true, true), vim.fn.glob(root .. "/*/*/Cargo.toml", true, true))) do
    want[#want + 1] = "/" .. vim.fs.dirname(c):sub(#root + 2) .. "/target/"
  end
...
  local seed, seed_t = nil, -1
  local stale = {}
  for _, p in ipairs(vim.fn.glob(gitdir .. "/lochist-index*", true, true)) do
    local base = p:gsub("%.lock$", "")
    local pid = base:match("lochist%-index%.(%d+)$")
    if base ~= mine and not (pid and pid_alive(tonumber(pid))) then
      stale[#stale + 1] = p
      local st = base == p and vim.uv.fs_stat(p) or nil
      if st and st.mtime.sec > seed_t then
        seed, seed_t = p, st.mtime.sec
      end
    end
  end
  if seed and not vim.uv.fs_stat(mine) then
    vim.uv.fs_copyfile(seed, mine)
  end
  for _, p in ipairs(stale) do
    os.remove(p)
  end
'''),
    ...para('--', r'prepare runs once per repository per session, and does two jobs. First, it keeps the '
        r'build directory out. It writes anchored lines such as /target/ into .git/info/exclude, '
        r'for the root and for workspace members up to two levels deep (found by globbing for '
        r'Cargo.toml). The comment explains the bug that forced the anchoring: a bare target/ '
        r'matches at any depth and used to hide src/target/mod.rs from git status, from git add and '
        r'from the snapshots. An older unanchored line is migrated, and the user’s own line for the '
        r'root is respected. Using info/exclude, not core.excludesFile, matters too: it is additive '
        r'to .gitignore and to the user’s global ignore file, where setting core.excludesFile would '
        r'replace the latter.'),
    ...para('--', r'Second, it cleans up after dead processes. Each Neovim has its own index file named with '
        r'its pid, so concurrent instances never fight over one lock. The scan lists every '
        r'lochist-index file, skips this process’s own and any whose pid is still alive (a signal-0 '
        r'kill), and removes the rest, remembering the newest as a seed. If our index does not '
        r'exist yet, the seed is copied into it, so that the first git add -A in a new session is '
        r'incremental instead of reading the entire tree. The shared index of the old version is '
        r'removed in the same pass.'),
    ...sec(r'stale locks'),
    ...code('lua', r'lua/xyno_history/init.lua · lines 282-290', r'''
--- A stale lock (killed git) older than a minute: remove it. `err` is git's stderr.
local function clear_stale_lock(err)
  local lock = (err or ""):match("Unable to create '([^']-%.lock)'")
  local st = lock and vim.uv.fs_stat(lock)
  if st and os.time() - st.mtime.sec > 60 then
    return os.remove(lock) ~= nil
  end
  return false
end
'''),
    ...para('--', r'A git killed in the middle of a write can leave an index.lock or a ref lock behind. '
        r'clear_stale_lock takes git’s own stderr, extracts the path from the message Unable to '
        r'create ... .lock, and removes the file only if it is older than a minute, so a lock held '
        r'by a live process is left alone. lock_error recognises the two shapes of such failures. '
        r'The spec has tests for both a stale lock that is removed and a fresh one that stays.'),
    ...sec(r'size caps'),
    ...code('lua', r'lua/xyno_history/init.lua · lines 296-306', r'''
local function size_cap()
  local v = M.config.max_bytes
  if v == nil then
    return MAX_BYTES
  end
  v = tonumber(v)
  if v == nil then
    return MAX_BYTES -- not a number: keep the default cap rather than silently lifting it
  end
  return v > 0 and v or nil
end
'''),
    ...para('--', r'Two options are read through small functions that encode the contract of the option. A '
        r'nil per-file cap means 10 MB; a number of zero or less disables it; and a value that is '
        r'not a number keeps the default rather than silently lifting the cap, which the comment '
        r'justifies. The total budget is read similarly. The default of 200 MB is explained in the '
        r'header: thirty files just under the per-file cap would add about 285 MB to .git.'),
    ...code('lua', r'lua/xyno_history/init.lua · lines 323-341,360-376', r'''
local function big_untracked(root, run, cb)
  local cap = size_cap()
  if not cap then
    return cb({})
  end
  git({ "ls-files", "-o", "-m", "--exclude-standard", "-z" }, root, nil, function(out)
    local big = {}
    local kept = {} -- files under the per-file cap: { rel, size }
    local files = vim.split(out or "", "\0", { plain = true })
    -- one fs_stat per listed file: 100k untracked files froze the editor for ~0.5 to 1s
    -- in one go, so a slice of STAT_SLICE files per event-loop turn (not on exit, where
    -- `deadline` is set and nothing may be left for later)
    local function step(from)
      local to = deadline and #files or math.min(from + STAT_SLICE - 1, #files)
      for i = from, to do
        local rel = files[i]
        local st = rel ~= "" and vim.uv.fs_stat(root .. "/" .. rel) or nil
        if st and st.type == "file" and st.size > cap and #big < 2000 then
          big[#big + 1] = rel
...
      -- the snapshot as a whole: leave out the largest files until it fits the budget
      local budget, total = total_cap(), 0
      for _, f in ipairs(kept) do
        total = total + f[2]
      end
      if budget and total > budget then
        table.sort(kept, function(a, b)
          if a[2] ~= b[2] then
            return a[2] > b[2]
          end
          return a[1] > b[1]
        end)
        for _, f in ipairs(kept) do
          if total <= budget or #big >= 2000 then
            break
          end
          total = total - f[2]
'''),
    ...para('--', r'big_untracked answers which files must stay out. It lists untracked and modified files '
        r'with git ls-files -o -m, NUL-separated so that odd names survive, and stats them. Two '
        r'details are worth knowing. The stat loop works in slices of 2000 files per event-loop '
        r'turn, because 100 thousand untracked files froze the editor for half a second to a second '
        r'in one go; under the exit deadline everything runs in one pass because nothing may be '
        r'left for later. And after the per-file pass the function applies the total budget by '
        r'sorting the kept files by size, largest first, and dropping them until the sum fits, with '
        r'a notice for each. Modified tracked files count as well, because each snapshot of a '
        r'changed large file would add its whole size to .git while an unchanged tracked file is '
        r'the same blob as in HEAD. The lists are capped at 2000 entries so that the git pathspec '
        r'list stays bounded.'),
    ...sec(r'committing with compare-and-swap'),
    ...code('lua', r'lua/xyno_history/init.lua · lines 415-431,434-446', r'''
              g({ "update-ref", ref, c, parent or "" }, env, function(_, uo)
                if uo.code == 0 then
                  return finish(c, true)
                end
                clear_stale_lock(uo.stderr)
                if n < 10 then
                  if deadline then
                    return attempt(n + 1)
                  end
                  return vim.defer_fn(function()
                    attempt(n + 1)
                  end, math.random(30, 150)) -- jitter: racers must not retry in lockstep
                end
                migrated[root] = nil -- retry the old-ref migration next time
                vim.notify("local history: update-ref failed: " .. vim.trim(uo.stderr or ""), vim.log.levels.WARN)
                finish()
              end)
...
          build(function(t)
            tree = t
            if not parent then
              return commit()
            end
            g({ "rev-parse", parent .. "^{tree}" }, env, function(prev_tree)
              if prev_tree == tree then
                finish(nil, true) -- nothing changed since the last snapshot
              else
                commit()
              end
            end)
          end)
'''),
    ...para('--', r'This is the heart of the correctness story. attempt reads the current tip of the ref, '
        r'then builds the tree, then commits and moves the ref with git update-ref ref new old. The '
        r'old value is the one read at the start (an empty string when there was no parent), so git '
        r'only moves the ref if nobody else moved it in the meantime. If two Neovims race, one '
        r'fails, clears a stale lock if that was the reason, waits a random 30 to 150 milliseconds '
        r'so the racers do not retry in lockstep, and tries again up to ten times, rebuilding the '
        r'tree on top of the new parent. The tree is built after the parent is read, which is the '
        r'fix from xynovim commit 7ac2a38: a stale tree built before another instance’s newer '
        r'commit could otherwise land on top of it. When the tree is identical to the parent’s '
        r'tree, nothing is committed and finish is called as a success with no commit, so a save '
        r'with no change leaves no snapshot. After ten failures, the migration is reset to be '
        r'retried and the user gets one warning.'),
    ...sec(r'snapshot: the entry point'),
    ...code('lua', r'lua/xyno_history/init.lua · lines 463-481,489-515', r'''
  if running[root] then
    -- A forced snapshot must not be dropped: retry once the running one ends
    -- (it gets 30 seconds at most, see the watchdog below).
    if opts.force then
      vim.defer_fn(function()
        M.snapshot(opts)
      end, 500)
    else
      -- only note it: finish() arms the timer once `last` is set. Armed here, the timer used the
      -- previous snapshot's age and forced one about 1 s later (a second commit within the throttle)
      pending[root] = true
    end
    return
  end
  if not opts.force and os.time() < next_ok(root) then
    pending[root] = true
    arm(root)
    return
  end
...
  local function finish(commit, ok)
    if finished then
      return
    end
    finished = true
    running[root] = nil
    if runs[root] == run then
      runs[root] = nil
    end
    if ok then
      last[root] = os.time()
      failed[root] = nil
      if pending[root] then
        arm(root)
      end
    else
      failed[root] = os.time()
      -- one retry of the unrecorded save once the backoff is over
      if not deadline and not opts.retried then
        pending[root] = true
        arm(root)
      end
    end
    if opts.done then
      opts.done(commit)
    end
  end
'''),
    ...para('--', r'snapshot is a state machine over the flags. No root, no snapshot; a running snapshot '
        r'makes a forced request retry after 500 milliseconds and a plain one note that something '
        r'is pending; inside the throttle window the request is recorded and the timer armed. The '
        r'comment about the pending case holds a bug fix: arming the timer straight away used the '
        r'previous snapshot’s age and forced a second commit about a second later, within the '
        r'throttle, so now the timer is armed by finish once last has been updated. finish is '
        r'idempotent and carries the bookkeeping: success updates last and clears failed and arms '
        r'the timer if saves are pending, while failure records the failure and schedules one retry '
        r'unless it was a retry or we are exiting.'),
    ...para('--', r'A hung git must not disable history for the repository until restart, so there is a 30 '
        r'second watchdog that aborts the chain and finishes it. The spec checks that it kills the '
        r'child, clears the running state and fires done only once.'),
    ...code('lua', r'lua/xyno_history/init.lua · lines 530-545', r'''
  g({ "rev-parse", "--absolute-git-dir", "--path-format=absolute", "--git-path", "info/exclude" }, nil, function(out)
    local gitdir, exclude = unpack(vim.split(out or "", "\n", { plain = true }))
    if not gitdir or not exclude then
      return finish()
    end
    local index = gitdir .. "/lochist-index." .. vim.uv.os_getpid()
    indexes[root] = index
    prepare(root, gitdir, exclude)
    os.remove(index .. ".lock") -- ours alone: a leftover of a killed git
    local env = {
      GIT_INDEX_FILE = index,
      GIT_AUTHOR_NAME = "xyno-history",
      GIT_AUTHOR_EMAIL = "lochist@xyno-history",
      GIT_COMMITTER_NAME = "xyno-history",
      GIT_COMMITTER_EMAIL = "lochist@xyno-history",
    }
'''),
    ...para('--', r'The first git call resolves the absolute git directory and the path of info/exclude in '
        r'one invocation, which also works for linked worktrees, where the gitdir is not under the '
        r'root. The environment given to every following call sets GIT_INDEX_FILE to this process’s '
        r'private index and sets author and committer identities to xyno-history, so the snapshot '
        r'commits never depend on the user’s git configuration and are recognisable in git log.'),
    ...code('lua', r'lua/xyno_history/init.lua · lines 546-556,578-590', r'''
    big_untracked(root, run, function(big)
      -- --ignore-errors: a nested repo without commits ("adding embedded
      -- repository") makes plain `add -A` abort and index nothing; with it the
      -- rest is indexed, that repo is skipped, and git exits 1 (tolerated).
      local add = { "add", "-A", "--ignore-errors" }
      if #big > 0 then
        vim.list_extend(add, { "--", "." })
        for _, rel in ipairs(big) do
          add[#add + 1] = ":(exclude,literal)" .. rel
        end
      end
...
      local function build(cb)
        add_all(1, cb)
      end
      local function go()
        commit_tree(root, build, env, opts, g, finish)
      end
      if #big > 0 and vim.uv.fs_stat(index) then
        -- indexed while it was still small: drop the stale copy
        local rm = { "rm", "--cached", "-r", "-q", "-f", "--ignore-unmatch", "--" }
        g(vim.list_extend(rm, big), env, go)
      else
        go()
      end
'''),
    ...para('--', r'The build step is git add -A with --ignore-errors, with a comment that explains why: a '
        r'nested repository without commits makes a plain add abort and index nothing, while with '
        r'the flag the rest is indexed and git exits with 1, which is tolerated. Big files are '
        r'excluded through exclude pathspecs with the literal magic, and if a file was indexed '
        r'while small and has since grown, it is dropped from the private index with git rm '
        r'--cached before the add. Then write-tree produces the tree. Lock errors from the add are '
        r'retried once after clearing the leftover index lock, and a lasting error produces one '
        r'notice and ends the attempt.'),
    ...sec(r'browsing and restoring'),
    ...code('lua', r'lua/xyno_history/init.lua · lines 610-611,617-627', r'''
      local args = vim.list_extend({ "log" }, refs)
      vim.list_extend(args, { "--format=%H%x09%ar%x09%s", "-n", "100", "--diff-filter=d", "--", rel })
...
        vim.ui.select(items, {
          prompt = "Local history: " .. rel,
          format_item = function(l)
            local _, age, msg = unpack(vim.split(l, "\t", { plain = true }))
            return ("%s  %s"):format(age, msg)
          end,
        }, function(choice)
          if choice then
            cb({ root = root, rel = rel, file = file, hash = vim.split(choice, "\t", { plain = true })[1] })
          end
        end)
'''),
    ...para('--', r'pick lists the snapshots that touched the current file: git log over the existing lochist '
        r'refs (the branch ref and, for a detached HEAD, the legacy one), the latest 100, with '
        r'--diff-filter=d so that snapshots in which the file was deleted are not offered, limited '
        r'to the path. The list is shown with vim.ui.select as the age and the message, so any '
        r'picker the user has installed becomes the interface.'),
    ...code('lua', r'lua/xyno_history/init.lua · lines 649-655,672-677', r'''
      vim.cmd("diffthis")
      vim.cmd("vertical new")
      vim.bo.buftype, vim.bo.bufhidden, vim.bo.swapfile = "nofile", "wipe", false
      vim.api.nvim_buf_set_lines(0, 0, -1, false, lines_of(content))
      vim.bo.filetype = vim.filetype.match({ filename = s.file }) or ""
      vim.api.nvim_buf_set_name(0, ("%s@%s"):format(s.rel, s.hash:sub(1, 8)))
      vim.cmd("diffthis")
...
        if ans ~= "Restore" or not vim.api.nvim_buf_is_valid(buf) then
          return
        end
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines_of(content))
        vim.notify(("restored %s from %s (buffer modified, not saved)"):format(s.rel, s.hash:sub(1, 8)))
      end)
'''),
    ...para('--', r'browse opens the chosen version in a vertical scratch buffer of type nofile and runs '
        r'diffthis on both windows; the buffer is named path@hash and gets the file’s filetype for '
        r'highlighting. restore asks to confirm, then replaces the lines of the buffer, leaving it '
        r'modified and not saved: u undoes it, the index and the disk are untouched. The design '
        r'choice is to restore into the buffer and not into the file, so the restore is itself '
        r'reversible and no history is needed to undo a restore.'),
    ...sec(r'pruning without losing the tips'),
    ...code('lua', r'lua/xyno_history/init.lua · lines 696-699,733-750,762-770', r'''
  local days, keep = arg:match("^(%d+)d$"), arg:match("^(%d+)$")
  if not ((days or keep) and tonumber(days or keep) > 0) then
    return vim.notify("usage: :LocalHistoryPrune [N | Nd]  (keep the newest N snapshots per branch, or N days)", vim.log.levels.WARN)
  end
...
        local stream = {}
        for i = n, 1, -1 do
          local c = commits[i]
          local from = i < n and "from :" .. (n - i) .. "\n" or ""
          vim.list_extend(stream, {
            ("commit refs/xyno-history-prune\nmark :%d\ncommitter xyno-history <lochist@xyno-history> %d +0000\ndata %d\n%s\n%sM 040000 %s \"\"\n"):format(
              n - i + 1, c.ct, #c.msg, c.msg, from, c.t
            ),
          })
        end
        local tip = sgit({ "fast-import", "--quiet" }, table.concat(stream)) and sgit({ "rev-parse", "refs/xyno-history-prune" })
        if tip and sgit({ "update-ref", ref, tip, commits[1].h }) then
          dropped = dropped + #commits - n
        else
          vim.notify("local history: could not prune " .. ref, vim.log.levels.WARN)
        end
        sgit({ "update-ref", "-d", "refs/xyno-history-prune" })
      end
...
  vim.system({ "git", "gc", "--quiet", now and "--prune=now" or "--prune=1.hour.ago" }, { cwd = root, text = true }, function(o)
    vim.schedule(function()
      vim.notify(
        o.code == 0 and ("local history: pruned, git gc done" .. (now and "" or " (objects younger than an hour: next gc, or :LocalHistoryPrune!)"))
          or "local history: git gc failed: " .. vim.trim(o.stderr or ""),
        o.code == 0 and vim.log.levels.INFO or vim.log.levels.WARN
      )
    end)
  end)
'''),
    ...para('--', r'Pruning has to forget old commits, but git commits are a linked list, so removing the old '
        r'ones means rewriting the chain. The function lists each ref’s commits, decides how many '
        r'newest ones to keep (a count, or a number of days, and always at least one), then '
        r'recreates just those kept commits through one git fast-import, each with its original '
        r'tree, message and date but without the parent that is now cut off. The ref is moved to '
        r'the new tip with update-ref with the old tip as the expected value, so a ref that moved '
        r'meanwhile makes the prune fail safely, and the temporary ref is deleted. Finally git gc '
        r'runs asynchronously, with --prune=1.hour.ago by default, because collecting younger '
        r'objects could take a snapshot being written right now; the bang form uses --prune=now. '
        r'The spec covers N and Nd, the usage error for 0, 0d, -1 and text, a ref that moved '
        r'meanwhile, and the bang form freeing the space of a big deleted blob.'),
    ...sec(r'setup: events, exit, commands, keys'),
    ...code('lua', r'lua/xyno_history/init.lua · lines 778-794', r'''
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "AutoSaveWritePost",
    callback = function(ev)
      local buf = ev.data and ev.data.saved_buffer
      -- still modified: the write was refused (a save guard refused it)
      if buf and vim.api.nvim_buf_is_valid(buf) and not vim.bo[buf].modified then
        M.snapshot({ path = vim.api.nvim_buf_get_name(buf) })
      end
    end,
  })
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = group,
    callback = function(ev)
      M.snapshot({ path = ev.file })
    end,
  })
'''),
    ...para('--', r'Two events produce snapshots. A plain write goes through BufWritePost. The auto-save '
        r'integration listens for the AutoSaveWritePost user event and snapshots only if the buffer '
        r'is no longer modified: a refused write, which is how xyno-guard.nvim reports a skipped '
        r'save, leaves the buffer modified, so no snapshot is made of a save that did not happen. '
        r'The README says the auto-save plugin is optional and the two plugins agree on that '
        r'convention without depending on each other.'),
    ...code('lua', r'lua/xyno_history/init.lua · lines 798-818', r'''
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function()
      for _, root in ipairs(vim.tbl_keys(timers)) do
        stop_timer(root)
      end
      deadline = vim.uv.hrtime() / 1e6 + EXIT_BUDGET_MS
      local roots = vim.deepcopy(pending)
      for root in pairs(runs) do
        roots[root] = true
      end
      for root in pairs(roots) do
        abort(root, true)
        running[root] = nil
        if vim.uv.fs_stat(root .. "/.git") then
          pcall(M.snapshot, { path = root, force = true })
        end
      end
      pending = {}
      deadline = nil
    end,
'''),
    ...para('--', r'At exit the module drops the timers and then, for each repository that has an unrecorded '
        r'save or a snapshot in flight, it aborts the running chain (killing its git) and redoes '
        r'the snapshot synchronously under the 5 second deadline. That is the only way to keep the '
        r'last save of the session, since an asynchronous chain would die with Neovim. The spec '
        r'runs real child Neovim processes to prove that quitting after a save records the final '
        r'content with exactly one snapshot, that the exit is quick, and that an in-flight slow git '
        r'is killed.'),
    ...code('lua', r'lua/xyno_history/init.lua · lines 831-841', r'''
  local km = M.config.keymaps
  if km then
    -- true: <leader>gH browses; a table maps action ("browse", "restore", "prune") to a lhs
    local maps = km == true and { browse = "<leader>gH" } or km
    local rhs = { browse = "<cmd>LocalHistory<cr>", restore = "<cmd>LocalHistoryRestore<cr>", prune = "<cmd>LocalHistoryPrune<cr>" }
    for action, lhs in pairs(maps) do
      if rhs[action] and lhs then
        vim.keymap.set("n", lhs, rhs[action], { desc = "Local history: " .. action })
      end
    end
  end
'''),
    ...para('--', r'Commands are optional, keymaps are off by default, and keymaps = true maps only the '
        r'browse action; a table maps any of the three actions to the keys the user chooses. '
        r'Nothing is mapped without being asked for.'),
    ...sec(r'design decisions in one place'),
    ...pt('--', r'Git is the storage', r'no database, no custom format. The snapshots are ordinary commits, so git log, git '
        r'restore --source, push --mirror and fsck work on them, and the README gives the two '
        r'commands to recover without the plugin.'),
    ...pt('--', r'Private index', r'the real index, stash and branches are never touched, and each process has its own file.'),
    ...pt('--', r'Compare-and-swap', r'concurrency is solved by the ref update, not by a lock the plugin invents.'),
    ...pt('--', r'Everything has a bound', r'60 seconds, 10 retries, 30 seconds for a hung git, 5 seconds at exit, 2000 files per '
        r'slice, 2000 skipped files.'),
    ...pt('--', r'Warn once', r'every notice has a key.'),
    ...sec(r'a small inconsistency'),
    ...para('--', r'The body of pick, lines 604 to 631, is not re-indented inside the migrate call that wraps it, so the nesting is visible only by counting end keywords. It does not change '
        r'behaviour. The repository has no stylua configuration file.'),
    ...sec(r'how it is tested'),
    ...para('--', r'tests/history_spec.lua has 65 tests that run against temporary repositories with a git '
        r'wrapper that logs calls and injects hangs, failures, lock errors and delays. See that '
        r'page.'),
    ...sec(r'history'),
    ...pt('--', r'6dfb326', r'2026-10-22, Add the history module: worktree snapshots on private git refs.'),
  ],
);
