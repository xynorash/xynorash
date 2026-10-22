import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/lua/config/local_history.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'local_history.lua — every save also lands in a private git history of the whole worktree'),
    cm('--', r'refs/lochist/<branch>, a per-process index, a throttle with a trailing edge, and a bounded snapshot on exit'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'automatic local history: snapshots, browse, restore, prune'),
    kv(r'language', r'Lua; drives the git CLI asynchronously through vim.system'),
    kv(r'size', r'818 lines, 12 commits (8e212cf on 2026-10-09 to 0247401 on 2026-10-22)'),
    kv(r'commands', r'LocalHistory (key <leader>gH) · LocalHistoryRestore · LocalHistoryPrune[!] [N | Nd]'),
    kv(r'storage', r'refs/lochist/<encoded branch> in the repo itself, one commit per snapshot'),
    kv(r'knobs', r'vim.g.xynovim_lochist_max_bytes (10 MB) · vim.g.xynovim_lochist_max_total_bytes (200 MB)'),
    kv(r'also lives in', r'xyno-history.nvim (lua/xyno_history/init.lua, 844 lines): same engine, options table, own refs and author names'),
    ...sec(r'why this file exists'),
    ...para('--', r'Neovim’s undofile keeps the undo tree of a buffer, and it is good at that. It cannot bring back a file that was deleted, a worktree that git reset --hard overwrote, or the state of a project before an agent rewrote forty files. The header says what this module is for: "Local history, inspired by the JetBrains feature of that name". Every throttled save also writes the entire worktree, untracked files included, the .gitignore respected and target/ excluded, as a commit on a private ref, using a private index file so that "the real index/stash/branches are never touched". It "survives what undofile can’t: deleted files, git reset --hard, edits made by an agent".'),
    ...para('--', r'The choice to use git as the storage engine shapes everything. Git already knows how to store a tree of files compactly (identical content is one blob), it is on every machine that runs this editor, and it can show, diff and garbage-collect what it stores. The cost is that the module has to drive a command-line tool from an editor without ever blocking it, and has to cope with the many ways git can fail at the wrong moment: locks, concurrent editors, huge files, repositories nested inside repositories. Most of the 818 lines are those coping mechanisms.'),
    ...para('--', r'The wording of the first line changed in the last commit that touches the file, 0247401 on 2026-10-22 ("Positioning: a personal project inspired by JetBrains, not a competitor"); the feature is described as inspired by, not as a clone of, the JetBrains one.'),
    ...sec(r'how history is addressed: branch-encoded refs'),
    ...code('lua', r'lua/config/local_history.lua · lines 1-26', r'''
-- Local history, inspired by the JetBrains feature of that name: every (throttled) save also writes the
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
-- vim.g.xynovim_lochist_max_bytes (default 10 MB, <= 0 disables the cap) are
-- left out, and so are the largest files of a snapshot beyond
-- vim.g.xynovim_lochist_max_total_bytes (default 200 MB: thirty files just under the
-- per-file cap would add about 285 MB to .git). :LocalHistoryPrune trims old snapshots.'''),
    ...para('--', r'The header documents the design of the ref names in detail. A snapshot is a commit on refs/lochist/<key>, where the key is the branch name with % written as %25 and / written as %2F. The reason is a git limitation: refs are files in a directory tree, so refs/lochist/foo and refs/lochist/foo/bar cannot both exist (one would be a file and a directory at once). Encoding the slash removes the collision. A detached HEAD gets the key %detached-<short sha>, and since a percent sign never starts an encoded branch, the two forms cannot clash either. Older versions wrote raw branch names; the header says that old-style refs with a slash are renamed to the encoded form on first use, because "they could block new branches", and that the old shared detached ref is left alone and still read by :LocalHistory.'),
    ...para('--', r'The second half of the header describes behaviour that the rest of the file implements: saves inside the throttle window are not lost, because one trailing snapshot is scheduled for the end of the window and one more on exit; every nvim process uses its own index file, so concurrent instances never fight over one index.lock, and the leftovers of dead processes are cleaned up while the newest one seeds the next, "so the first git add -A stays incremental"; and two size caps keep .git from growing without bound.'),
    ...sec(r'state and the git runner'),
    ...code('lua', r'lua/config/local_history.lua · lines 29-68', r'''
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
...
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
end'''),
    ...para('--', r'The constants say what the policy is: at most one snapshot per repository per 60 seconds, a 10 second backoff after a failure, a 5 second budget for the exit snapshot, a 10 MB cap per file and 200 MB per snapshot. The tables remember, per repository root, the time of the last successful snapshot and of the last failed one, whether a snapshot is running, a handle to the running chain, this process’s index file, whether the repository has been prepared, which warnings were already shown, and the trailing-edge timers. One value is global: deadline is set only during the synchronous exit snapshot.'),
    ...para('--', r'git() is the only place that starts a process, and it has two modes. Normally the call is asynchronous: vim.system with a callback, whose result is delivered through vim.schedule so that callers run in a safe context, and an optional run handle that lets a caller abandon the whole chain: once run.dead is set the callback never fires, and run.child is the process to kill. When deadline is set (the exit snapshot) every call becomes synchronous with a wait of the remaining budget, and when the budget is gone it fabricates a result with code 124 and the message "exit budget exhausted", which is the exit code the timeout command uses. The callback always receives a trimmed string on success (or the raw output when asked) and nil on failure, with the full result as a second argument; the code in the rest of the file relies on this convention.'),
    ...sec(r'refs, encoding and migration'),
    ...code('lua', r'lua/config/local_history.lua · lines 93-146', r'''
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
...
local function migrate(root, cb)
  if migrated[root] then
    return cb()
  end
  migrated[root] = true
  git({ "for-each-ref", "--format=%(refname) %(objectname)", "refs/lochist" }, root, nil, function(out)
    local cmds = {}
    for _, l in ipairs(vim.split(out or "", "\n", { plain = true })) do
      local name, sha = l:match("^refs/lochist/(%S+) (%x+)$")
      if name and name:find("/", 1, true) then
        local new = "refs/lochist/" .. encode(name)
        -- encode() also escapes "%" in the name, matching what a branch of that name gets
        vim.list_extend(cmds, { ("create %s %s"):format(new, sha), ("delete refs/lochist/%s %s"):format(name, sha) })
      end
    end
    if #cmds == 0 then
      return cb()
    end
    local input = table.concat(cmds, "\n") .. "\n"
    -- one transaction; if the target already exists (create fails) nothing moves'''),
    ...para('--', r'encode is the percent-escaping of the branch. ref_for asks git symbolic-ref for the branch and falls back to the short sha of HEAD for a detached head, returning the legacy ref as a second value in that case so that the browser can still read it. existing filters a list of refs down to those that exist. migrate runs once per repository and session: it lists all refs under refs/lochist, picks those whose names contain a slash, and renames each to the encoded form in a single git update-ref --stdin transaction in which a create and a delete are paired. The comment has the important property: "one transaction; if the target already exists (create fails) nothing moves". On exit the same command runs synchronously, as the deadline check shows.'),
    ...sec(r'the throttle and its trailing edge'),
    ...code('lua', r'lua/config/local_history.lua · lines 172-202', r'''
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
end'''),
    ...para('--', r'The throttle is the answer to a real tension: auto-save writes about once a second while typing, and a git snapshot of a worktree is far too heavy for that. next_ok computes the earliest time the next unforced snapshot may start: the later of last success plus 60 seconds and last failure plus 10 seconds. A save that arrives earlier is not discarded. It marks the repository pending and arms a timer for the end of the window (at least a second, 500 ms past the deadline). The timer is unref’d so it never keeps Neovim alive, it checks that it is still the current timer for that repository when it fires, and when it fires it takes a forced snapshot, with retried = true so that a failure does not re-arm forever. If the repository disappeared meanwhile, the timer just forgets the last time. This is the trailing edge: the final state of a burst of edits is always recorded, one minute after the first save at the latest.'),
    ...sec(r'the private index and the target exclude'),
    ...code('lua', r'lua/config/local_history.lua · lines 214-248', r'''
local function prepare(root, gitdir, exclude)
  if prepared[root] then
    return
  end
  prepared[root] = true
  local mine = indexes[root]
  local lines = vim.uv.fs_stat(exclude) and vim.fn.readfile(exclude) or {}
  -- Anchored: a bare `target/` matched at any depth and hid `src/target/mod.rs` from git
  -- status, `git add -A` and the snapshots. The root and the workspace members (depth <= 2)
  -- get their own line; the unanchored line of an older version is migrated.
  local want = { "/target/" }
  for _, c in ipairs(vim.list_extend(vim.fn.glob(root .. "/*/Cargo.toml", true, true), vim.fn.glob(root .. "/*/*/Cargo.toml", true, true))) do
    want[#want + 1] = "/" .. vim.fs.dirname(c):sub(#root + 2) .. "/target/"
  end
  local have, changed = {}, false
  for i, l in ipairs(lines) do
    if l == "target/" then
      lines[i], changed = "/target/", true
    end
    have[lines[i]] = true
    if lines[i]:match("^/target/?$") or lines[i] == "target" then
      have["/target/"] = true -- the user's own line already covers the root
    end
  end
  for _, w in ipairs(want) do
    if not have[w] then
      have[w] = true
      lines[#lines + 1] = w
      changed = true
    end
  end
  if changed then
    vim.fn.mkdir(vim.fs.dirname(exclude), "p")
    pcall(vim.fn.writefile, lines, exclude)
  end'''),
    ...para('--', r'prepare runs once per repository and session and does three jobs, each documented. First, it keeps build output out of the snapshots through .git/info/exclude, which the comment explains is additive to both the .gitignore and the user’s global ignore, unlike setting core.excludesFile, which would replace them. The entries are anchored (/target/ and the same for each workspace member up to depth 2), because an earlier version wrote a bare target/ that "matched at any depth and hid src/target/mod.rs from git status, git add -A and the snapshots"; the code migrates the old unanchored line, and it does not add a line if the user already has their own that covers the root. Second, it removes the shared index of older versions. Third, it handles the per-process index files, named lochist-index.<pid>: any whose pid is no longer alive (checked with signal 0) is stale. The newest stale one is copied to become this process’s starting index, so that the first git add -A has little to do, and all stale ones are deleted. A .lock leftover is not used as a seed.'),
    ...sec(r'keeping .git small: size caps'),
    ...code('lua', r'lua/config/local_history.lua · lines 286-383', r'''
local function size_cap()
  local v = vim.g.xynovim_lochist_max_bytes
  if v == nil then
    return MAX_BYTES
  end
  v = tonumber(v)
  if v == nil then
    return MAX_BYTES -- not a number: keep the default cap rather than silently lifting it
  end
  return v > 0 and v or nil
end

--- Per-snapshot budget for the files that pass the per-file cap (nil: no budget).
local function total_cap()
  local v = tonumber(vim.g.xynovim_lochist_max_total_bytes)
  if v == nil then
    return MAX_TOTAL_BYTES
  end
  return v > 0 and v or nil
end
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
          big[#big + 1] = f[1]
          warn_once(
            "big:" .. root .. "/" .. f[1],
            ("local history: skipping %s (%.0f MB; the snapshot is over %.0f MB, vim.g.xynovim_lochist_max_total_bytes)"):format(
              f[1],
              f[2] / 1048576,
              budget / 1048576
            ),
            vim.log.levels.INFO
          )
        end
      end
      cb(big)
    end
    step(1)
  end, true, run)
end'''),
    ...para('--', r'Two failure stories are in these lines. clear_stale_lock handles a killed git: when git’s error message names a .lock file older than a minute, the file is removed. lock_error recognises the shapes of the message. size_cap and total_cap read the two settings with care: an unset value means the default; a value that is not a number also keeps the default, with the comment "rather than silently lifting it"; a number at or below zero lifts the cap, which is the documented way to turn it off.'),
    ...para('--', r'big_untracked lists the files to leave out. git ls-files -o -m --exclude-standard gives the untracked and modified files (the comment explains why modified tracked files count: "each snapshot of a changed large file would add its whole size to .git", while an unchanged tracked file is the same blob as in HEAD). Each is stat’ed, in slices of 2000 files per event-loop turn, because a hundred thousand untracked files made a single pass freeze the editor for about half a second to a second; on exit, when the deadline is set, the slicing is off, since nothing may be left for later. A file over the per-file cap is skipped with an INFO message, once per file. The remaining files are then added up, and if the total exceeds the 200 MB budget the largest files are dropped, largest first with ties broken by name, until it fits. The list of skipped files is capped at 2000 entries. The header gives the reason for the budget with a number: thirty files just under the per-file cap would add about 285 MB to .git.'),
    ...sec(r'committing under concurrency'),
    ...code('lua', r'lua/config/local_history.lua · lines 385-442', r'''
--- Second half of a snapshot: commit the tree from `build(cb)` on top of the
--- branch's lochist ref. The ref moves with a compare-and-swap, so concurrent
--- nvims never overwrite each other's snapshot: on a mismatch or a lock the
--- parent is read again and the tree rebuilt (it is built after the parent is
--- read, so a stale tree cannot land on top of another instance's newer one).
local function commit_tree(root, build, env, opts, g, finish)
  migrate(root, function()
    ref_for(root, function(ref)
      local function attempt(n)
        g({ "rev-parse", "-q", "--verify", ref }, env, function(parent)
          local tree
          local function commit()
            local args = { "commit-tree", tree, "-m", opts.label or "autosave" }
            if parent then
              vim.list_extend(args, { "-p", parent })
            end
            g(args, env, function(c)
              if not c then
                return finish()
              end
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
            end)
          end
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
        end)
      end
      attempt(1)
    end)
  end)
end'''),
    ...para('--', r'commit_tree is the second half of a snapshot, and the heart of the file’s correctness. It uses git’s plumbing: read the current tip of the branch’s ref (the parent), build a tree, compare it with the parent’s tree, write a commit with commit-tree, and move the ref with update-ref using the old value as a compare-and-swap. The order is the subtle part, and the commit 7ac2a38 (2026-10-13) is named for it: "build the tree after reading the parent, rebuild on CAS retry (no stale tip with concurrent nvims)". Two editors working in one repository could otherwise each read a parent, build a tree from their own view of the disk and then race. Because the tree is built after the parent is read, and rebuilt on every retry, a stale tree cannot land on top of another instance’s newer snapshot.'),
    ...para('--', r'If the tree equals the parent’s tree, nothing is committed and the snapshot counts as successful ("nothing changed since the last snapshot"). If update-ref fails because of a mismatch or a lock, the stale lock is cleared if it is old, and the attempt repeats up to ten times with a random 30 to 150 ms pause so that racing instances do not retry in lockstep; during the exit snapshot the retry is immediate. After ten failures the migration flag is reset (so the old-ref migration is retried next time), a warning shows the git error, and the snapshot finishes as failed.'),
    ...sec(r'snapshot: the state machine'),
    ...code('lua', r'lua/config/local_history.lua · lines 467-583', r'''
  if not opts.force and os.time() < next_ok(root) then
    pending[root] = true
    arm(root)
    return
  end
  pending[root] = nil
  stop_timer(root)
  running[root] = true
  local run = { dead = false }
  runs[root] = run
  local finished = false
  --- @param ok? boolean the snapshot was taken or nothing had changed
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
...
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
      local function add_all(tries, cb)
        g(add, env, function(_, o)
          if o.code ~= 0 and o.code ~= 1 then
            if lock_error(o.stderr) and tries < 2 then
              os.remove(index .. ".lock")
              clear_stale_lock(o.stderr)
              return add_all(tries + 1, cb)
            end
            if lock_error(o.stderr) then
              warn_once("lock:" .. root, "local history: git lock error, snapshots skipped: " .. vim.trim(o.stderr or ""))
            end
            return finish()
          end
          g({ "write-tree" }, env, function(tree)
            if not tree then
              return finish()
            end
            cb(tree)
          end)
        end)
      end
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
    end)
  end)
end'''),
    ...para('--', r'M.snapshot is the entry point for every trigger. It finds the repository root of the path, and then decides what to do with the request: if one is already running for that root, a forced request is retried 500 ms later and an ordinary one only sets the pending flag (the comment records a bug: arming the timer there used the previous snapshot’s age and forced a second commit about a second later, within the throttle, so the timer is armed in finish() instead, once last is set); if the throttle window has not elapsed, it sets pending and arms the timer; otherwise it starts. A snapshot has a run handle, a finished flag that makes finish() idempotent, and a 30 second watchdog (not during exit): "A hung git must not disable history for this repo until restart: kill it". finish() records the success time and clears the failure, re-arms the timer if saves were pending, or records the failure time and arranges one retry of the unrecorded save after the backoff, and finally calls the optional done callback.'),
    ...para('--', r'The pipeline itself is: ask git for the absolute git directory and the path of info/exclude (which also works in a linked worktree, where .git is a file; a spec group named "linked worktree" covers it); name this process’s index file; prepare the repository; remove any leftover lock of our own index; set GIT_INDEX_FILE and a fixed author and committer identity in the environment; compute the list of oversized files; then add everything with git add -A --ignore-errors, excluding the big files with :(exclude,literal) pathspecs, building the tree with write-tree, and calling commit_tree. The comment on --ignore-errors explains it: a nested repository without commits ("adding embedded repository") makes a plain add abort and index nothing, while with the flag the rest is indexed, that repo is skipped, and git exits with 1, which is tolerated. A lock error gets one cleanup and retry, and a second one gets a single warning. And if a file that was indexed while small has since become big, it is removed from the private index first with git rm --cached.'),
    ...sec(r'choosing and restoring a snapshot'),
    ...code('lua', r'lua/config/local_history.lua · lines 632-670', r'''
--- Pick an earlier snapshot of the current file and diff against it.
function M.browse()
  pick(function(s)
    git({ "show", s.hash .. ":" .. s.rel }, s.root, nil, function(content)
      if not content then
        return vim.notify("file did not exist in that snapshot", vim.log.levels.WARN)
      end
      vim.cmd("diffthis")
      vim.cmd("vertical new")
      vim.bo.buftype, vim.bo.bufhidden, vim.bo.swapfile = "nofile", "wipe", false
      vim.api.nvim_buf_set_lines(0, 0, -1, false, lines_of(content))
      vim.bo.filetype = vim.filetype.match({ filename = s.file }) or ""
      vim.api.nvim_buf_set_name(0, ("%s@%s"):format(s.rel, s.hash:sub(1, 8)))
      vim.cmd("diffthis")
    end, true)
  end)
end

--- Pick a snapshot and replace the current buffer's text with that version.
--- Never touches the git index; the buffer is left modified (undo with `u`).
function M.restore()
  local buf = vim.api.nvim_get_current_buf()
  pick(function(s)
    git({ "show", s.hash .. ":" .. s.rel }, s.root, nil, function(content)
      if not content then
        return vim.notify("file did not exist in that snapshot", vim.log.levels.WARN)
      end
      vim.ui.select({ "Restore", "Cancel" }, {
        prompt = ("Replace %s with snapshot %s? (undo with u)"):format(s.rel, s.hash:sub(1, 8)),
      }, function(ans)
        if ans ~= "Restore" or not vim.api.nvim_buf_is_valid(buf) then
          return
        end
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines_of(content))
        vim.notify(("restored %s from %s (buffer modified, not saved)"):format(s.rel, s.hash:sub(1, 8)))
      end)
    end, true)
  end)
end'''),
    ...para('--', r'pick finds the repository and the file’s path relative to it, migrates, finds the ref and legacy ref that exist, and asks git log over them for up to 100 commits that touched this file, excluding deletions (--diff-filter=d), formatted as hash, relative age and message separated by tabs. The user picks from a vim.ui.select list showing age and message. browse then shows that version with git show hash:path in a new scratch buffer next to the current one, sets the file type from the file name, names the buffer path@hash8, and turns on diff mode in both windows. restore asks for confirmation and replaces the buffer text, leaving the buffer modified: "Never touches the git index; the buffer is left modified (undo with u)". A snapshot in which the file did not exist yields the message "file did not exist in that snapshot". One visible formatting oddity: the body of the migrate callback inside pick is not indented (lines 594 to 621), probably a leftover of how stylua treated the nesting; it has no effect on behaviour.'),
    ...sec(r'pruning'),
    ...code('lua', r'lua/config/local_history.lua · lines 695-740', r'''
  local function sgit(args, stdin)
    local o = vim.system(vim.list_extend({ "git" }, args), { cwd = root, text = true, stdin = stdin }):wait(60000)
    return o.code == 0 and vim.trim(o.stdout or "") or nil, o
  end
  local cutoff = days and os.time() - tonumber(days) * 86400
  local dropped, total = 0, 0
  for _, ref in ipairs(vim.split(sgit({ "for-each-ref", "--format=%(refname)", "refs/lochist" }) or "", "\n", { plain = true })) do
    local log = ref ~= "" and sgit({ "log", ref, "--format=%H%x09%T%x09%ct%x09%s" }) or nil
    if log then
      local commits = {} -- newest first
      for _, l in ipairs(vim.split(log, "\n", { plain = true })) do
        local h, t, ct, msg = l:match("^(%x+)\t(%x+)\t(%d+)\t(.*)$")
        if h then
          commits[#commits + 1] = { h = h, t = t, ct = tonumber(ct), msg = msg }
        end
      end
      local n = #commits
      if keep then
        n = math.min(n, tonumber(keep))
      else
        n = 0
        for _, c in ipairs(commits) do
          n = n + (c.ct >= cutoff and 1 or 0)
        end
      end
      n = math.max(n, 1)
      total = total + #commits
      if n < #commits then
        local stream = {}
        for i = n, 1, -1 do
          local c = commits[i]
          local from = i < n and "from :" .. (n - i) .. "\n" or ""
          vim.list_extend(stream, {
            ("commit refs/xynovim-prune\nmark :%d\ncommitter xynovim <lochist@xynovim> %d +0000\ndata %d\n%s\n%sM 040000 %s \"\"\n"):format(
              n - i + 1, c.ct, #c.msg, c.msg, from, c.t
            ),
          })
        end
        local tip = sgit({ "fast-import", "--quiet" }, table.concat(stream)) and sgit({ "rev-parse", "refs/xynovim-prune" })
        if tip and sgit({ "update-ref", ref, tip, commits[1].h }) then
          dropped = dropped + #commits - n
        else
          vim.notify("local history: could not prune " .. ref, vim.log.levels.WARN)
        end
        sgit({ "update-ref", "-d", "refs/xynovim-prune" })
      end'''),
    ...para('--', r'History that is never trimmed grows forever. :LocalHistoryPrune [N | Nd] keeps the newest N snapshots per branch, or those from the last N days, and the default is 30d. At least the newest snapshot always stays (n = math.max(n, 1)). The interesting part is how a cut is made: a git commit chain cannot simply lose its old end, because every commit points to its parent. So the kept commits are re-created without the cut-off parent, in one git fast-import stream that writes them in order, oldest first, on a temporary ref, with the original commit time and message and the original tree; then the branch’s ref is moved onto the new tip using the old tip as the expected value. The author name in the stream is "xynovim <lochist@xynovim>" and the temporary ref is refs/xynovim-prune, which is deleted afterwards. That frees nothing by itself, so the function finishes with git gc, with --prune=1.hour.ago by default, or --prune=now with the bang form (the comment explains the difference: every unreachable object, also younger ones and other tools’ dangling commits, and a snapshot being written right now). The messages tell the user which of the cases happened.'),
    ...sec(r'setup: what triggers a snapshot'),
    ...code('lua', r'lua/config/local_history.lua · lines 763-806', r'''
function M.setup()
  local group = vim.api.nvim_create_augroup("xynovim_local_history", { clear = true })
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "AutoSaveWritePost",
    callback = function(ev)
      local buf = ev.data and ev.data.saved_buffer
      -- still modified: the write was refused (see config/disk_guard.lua)
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
  -- Exit: drop timers; take one bounded synchronous snapshot per repo that
  -- still has an unrecorded save OR a snapshot in flight (that one's git is
  -- killed first: the async chain would die with nvim).
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
  })'''),
    ...para('--', r'Three triggers. A user event AutoSaveWritePost fires after auto-save writes (it writes with noautocmd, so BufWritePost does not fire for it, as disk_guard.lua also notes), and the handler snapshots only when the buffer is no longer modified: if it still is, "the write was refused (see config/disk_guard.lua)", so there is nothing new on disk. An ordinary BufWritePost covers :w. And VimLeavePre does the exit work: stop all timers, set the deadline to five seconds from now, and for every repository that has an unrecorded save pending or a snapshot in flight, abort the chain (killing the git process and waiting up to a second for it) and take a forced snapshot, synchronously. The header says why the running one is redone and not awaited: the asynchronous chain would die with Neovim. All of that is inside the budget, so quitting is never held up for more than about five seconds. The three commands follow. The key <leader>gH for :LocalHistory is defined in keymaps.lua (line 210).'),
    ...sec(r'design decisions and trade-offs'),
    ...pt('--', r'git as the store', r'free compaction and tooling, at the cost of a lot of process management. The file keeps the user’s own repository history clean by living under a separate ref namespace and a private index, and keeps the user’s worktree untouched by never running checkout or reset.'),
    ...pt('--', r'snapshots are of the whole worktree', r'not per file. That makes restoring a deleted file or a whole state possible, and the size caps are what make it affordable.'),
    ...pt('--', r'throttle with a trailing edge', r'the cost of at most one snapshot a minute is that history has a one-minute granularity; the benefit is that the last state of every burst is guaranteed to be captured.'),
    ...pt('--', r'every failure has a backoff and a single warning', r'warn_once keys include the file or the repository, so a problem is reported once per session, not on every save.'),
    ...pt('--', r'private per-process index', r'no lock contention between editors, at the cost of a stale-file cleanup and the seed-copy trick.'),
    ...sec(r'what differs in xyno-history.nvim'),
    ...para('--', r'The standalone plugin (lua/xyno_history/init.lua, extracted on 2026-10-22) is the same engine with the edges of a library. A diff shows: a rewritten header that introduces it as "xyno-history: a Local History for Neovim, inspired by the JetBrains feature of that name (not affiliated with JetBrains)"; the two size settings move from vim.g globals to a config table (M.config with commands, keymaps, max_bytes and max_total_bytes) merged by setup(opts), and the info messages name the setup option instead of the global; the git identity, the augroup and the temporary prune ref are renamed (xyno-history, refs/xyno-history-prune); the comment about the disk guard becomes the neutral "a save guard refused it"; and setup(opts) defines the three commands only when commands is true, and can map keys, either <leader>gH for browse, or a table that maps browse, restore and prune to keys of the caller’s choice. The snapshot, ref, throttle, prune and exit logic is identical. One consequence: the plugin writes its commits under the author xyno-history, while this config writes xynovim.'),
    ...sec(r'how it is tested'),
    ...para('--', r'tests/local-history_spec.lua (64 it() blocks and 6 pending entries) has a describe for each concern: wiring, snapshot, refs, excludes, the size cap, the whole-snapshot budget, tracked files and the cap, nested repositories, a linked worktree, content, throttle and timers, locks and failures, stale index files, exit and concurrency (which uses child nvim processes), :LocalHistory, :LocalHistoryRestore, :LocalHistoryPrune, the bang form with nothing to drop, and integrations.'),
    ...sec(r'history'),
    ...pt('--', r'8e212cf and 4fdd3fa · 2026-10-09', r'wip-s5a and wip-s5b: the first versions.'),
    ...pt('--', r'ac38272 · 2026-10-09', r'Fix review findings: sandbox hardening, local history, 99 guard.'),
    ...pt('--', r'0494b52 · 2026-10-12', r'Field test fixes: sandbox hardening, local history, nav/search, debug; docs.'),
    ...pt('--', r'b65284f · 2026-10-13', r'Batch 3: data safety (local history exit snapshot, per-process index, size cap, prune).'),
    ...pt('--', r'7ac2a38 · 2026-10-13', r'Local history: build the tree after reading the parent, rebuild on CAS retry.'),
    ...pt('--', r'98c9bb4, a3d33c8, 3f868dd · 2026-10-13', r'Final loop rounds 1 to 3: tracked big files and prune, stat slices, anchored local history target.'),
    ...pt('--', r'f31e013 and 25086fd · 2026-10-14', r'Final loop rounds 4 and 5: the snapshot budget, the throttle fix.'),
    ...pt('--', r'0247401 · 2026-10-22', r'Positioning: the comments now say inspired by the JetBrains feature.'),
  ],
);
