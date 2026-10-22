import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/tests/agent-99-guard_spec.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'agent-99-guard_spec.lua — the checkpoint, the auto-save lock and the sandbox gate around 99'),
    cm('--', r'46 tests for the Guarded provider: nothing runs before a snapshot, nothing runs unsandboxed by accident'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'spec for lua/plugins/ninety-nine.lua: lazy loading, keys, setup args and the Guarded provider'),
    kv(r'language', r'Lua spec, 1005 lines, 46 it() blocks, 1 pending, 10 describe() blocks'),
    kv(r'isolation', r'skips itself unless stdpath("cache") is a temp dir created by scripts/test.sh'),
    kv(r'no network', r'no real claude request is ever made (the one pending test says so)'),
    kv(r'history', r'9 commits, 2026-10-13 to 2026-10-21'),
    ...sec(r'why this file exists'),
    ...para('--', r'99 is the agent plugin of this configuration. The plugin is configured to use the Claude Code provider, and the configuration wraps that provider in a Guarded one with three jobs. First, take a local-history snapshot of the buffer before the agent starts, so that anything the agent does can be rolled back. Second, switch auto-save off while a request is in flight, so that half-written agent edits are not saved behind your back. Third, run the agent only inside the sandbox, or refuse. These jobs are about ordering and about not leaking state, which is exactly what mocks and counters can test. The header makes the scope clear: lazy loading, keys, config, and the Guarded provider, with no real claude request.'),
    ...code('lua', r'tests/agent-99-guard_spec.lua · lines 1-3', r'''
-- lua/plugins/ninety-nine.lua: lazy loading, keys, config (tmp_dir pruning,
-- setup args) and the Guarded provider (snapshot, auto-save counter, sandbox).
-- No real claude request is made (see the pending test at the end).'''),
    ...sec(r'a spec that refuses to run on your real cache'),
    ...para('--', r'The plugin prunes its tmp_dir in stdpath("cache")/99 when it loads. A test that creates old files there must never do so in a real cache. So at load time the spec compares stdpath("cache") with XYNO_TEST_TMP and calls H.skip_file unless the cache is inside the temp area made by scripts/test.sh. The prune test files are created before 99 first loads, because the plugin prunes once, and touch() backdates them with fs_utime.'),
    ...code('lua', r'tests/agent-99-guard_spec.lua · lines 5-31', r'''

-- This spec writes into stdpath("cache")/99: only ever in the temp dirs of
-- scripts/test.sh, never in the real cache.
local test_tmp = vim.env.XYNO_TEST_TMP
local cache = vim.fn.stdpath("cache")
if not test_tmp or test_tmp == "" or not vim.startswith(vim.fs.normalize(cache), vim.fs.normalize(vim.fs.dirname(test_tmp)) .. "/") then
  H.skip_file("run through scripts/test.sh (stdpath('cache') must be a temp dir, got " .. cache .. ")")
end

local tmp_dir = cache .. "/99"
local DAY = 24 * 3600

-- Files for the prune test, created BEFORE 99 first loads (the plugin config
-- prunes once, when it runs).
local function touch(path, age_days, content)
  vim.fn.writefile({ content or "x" }, path)
  local t = os.time() - age_days * DAY
  assert(vim.uv.fs_utime(path, t, t))
end
vim.fn.mkdir(tmp_dir .. "/olddir", "p")
touch(tmp_dir .. "/old.txt", 8)
touch(tmp_dir .. "/fresh.txt", 1)
touch(tmp_dir .. "/olddir/inner-old.txt", 30)
do
  local t = os.time() - 30 * DAY
  assert(vim.uv.fs_utime(tmp_dir .. "/olddir", t, t))
end'''),
    ...sec(r'test doubles written by hand'),
    ...para('--', r'fake_claude replaces the real Claude provider make_request with a recorder: it counts calls, stores observers and contexts, and records the order of events so a test can see that snapshot precedes claude. new_observer and new_context implement the callback shape the plugin uses, with an on_complete that returns orig-return, so forwarding of the return value can be checked. start() opens an unnamed buffer to avoid snapshots and a repository, and calls the Guarded make_request.'),
    ...code('lua', r'tests/agent-99-guard_spec.lua · lines 354-405', r'''
local function autosave()
  return require("auto-save")
end

-- Replace Claude.make_request by a fake that records its calls. Returns
-- rec = { n, observers = {}, contexts = {}, order = {} }, restore().
local function fake_claude(behaviour)
  local rec = { n = 0, observers = {}, contexts = {} }
  local restore = patch(claude(), {
    make_request = function(_, query, context, observer)
      rec.n = rec.n + 1
      rec.observers[rec.n] = observer
      rec.contexts[rec.n] = context
      rec.order[#rec.order + 1] = "claude"
      if behaviour then
        return behaviour(rec, query, context, observer)
      end
      return "result" .. rec.n
    end,
  })
  rec.order = {}
  return rec, restore
end

local function new_observer()
  local obs = { completed = {} }
  obs.on_start = function() end
  obs.on_stdout = function() end
  obs.on_stderr = function() end
  obs.on_complete = function(status, text)
    obs.completed[#obs.completed + 1] = { status, text }
    return "orig-return"
  end
  return obs
end

local function new_context()
  local ctx = { cancelled = 0 }
  ctx.cancel = function(self)
    self.cancelled = self.cancelled + 1
  end
  return ctx
end

-- Start a request through the Guarded provider.
local function start(rec_ctx, obs)
  obs = obs or new_observer()
  local ctx = rec_ctx or new_context()
  vim.cmd("enew!") -- unnamed buffer: no snapshot, no repo
  local res = guarded():make_request("q", ctx, obs)
  return ctx, obs, res
end'''),
    ...sec(r'the snapshot comes first'),
    ...para('--', r'The central test opens the basic fixture as a git repository, wraps local_history.snapshot to record when it is called and when its done callback fires, and calls make_request. The assertions say what the product promises: the snapshot is the first event, no request has started (rec.n is 0) because the agent must wait for the checkpoint, and after the snapshot completes the request starts; the snapshot was for the buffer path, forced, with the label before 99 request. At the end the test inspects the git refs under refs/lochist for a commit with that subject. So the checkpoint is verified at the level of git objects, not just at a call. The test runs on Linux only, with a reason printed: it timed out on macos-latest in run 38912021512 and the cause was not diagnosed.'),
    ...code('lua', r'tests/agent-99-guard_spec.lua · lines 446-492', r'''
  it("takes a forced 'before 99 request' snapshot of the buffer path before the request starts", function()
    H.need_os({ "linux" }, "times out waiting for the snapshot commit on macos-latest (run 38912021512), cause not diagnosed")
    local dir = H.open_fixture("basic", "src/main.rs", { git = true })
    local lh = require("config.local_history")
    local order, snap = {}, nil
    local orig = lh.snapshot
    patch(lh, {
      snapshot = function(opts)
        order[#order + 1] = "snapshot"
        snap = opts
        return orig(vim.tbl_extend("force", opts, {
          done = function(c)
            order[#order + 1] = "done"
            if opts.done then
              opts.done(c)
            end
          end,
        }))
      end,
    })
    local buf_path = vim.api.nvim_buf_get_name(0)
    -- Claude.make_request records "claude" in rec.order; snapshot must precede it
    guarded():make_request("q", new_context(), new_observer())
    H.eq("snapshot", order[1])
    H.eq(0, rec.n, "the agent must wait for the checkpoint")
    H.wait_for(function()
      return rec.n == 1
    end, 20000, "the request to start after the snapshot")
    H.eq("done", order[2], "claude started before the snapshot finished")
    H.eq("claude", rec.order[1])
    H.eq(buf_path, snap.path)
    H.eq(true, snap.force)
    H.eq("before 99 request", snap.label)
    rec.observers[1].on_complete("success", "")

    H.wait_for(function()
      local refs = H.git(dir, "for-each-ref", "--format=%(refname)", "refs/lochist")
      if refs == "" then
        return false
      end
      for ref in refs:gmatch("[^\n]+") do
        if H.git(dir, "log", "-1", "--format=%s", ref) == "before 99 request" then
          return true
        end
      end
    end, 20000, "refs/lochist commit 'before 99 request'")
  end)'''),
    ...sec(r'a cancel before the checkpoint finishes starts nothing'),
    ...para('--', r'The checkpoint has a fallback timer, so its done callback can be called more than once. The second test stubs snapshot to capture the callbacks. After make_request nothing is started and auto-save is off; calling done once starts the agent; calling it again must not start it twice. A second request is cancelled before its checkpoint finishes: auto-save is released at once, and when its done finally fires, the request must stay unstarted.'),
    ...code('lua', r'tests/agent-99-guard_spec.lua · lines 494-521', r'''
  it("starts the agent only from the checkpoint's done callback; a cancel before that never starts it", function()
    H.open_fixture("basic", "src/main.rs", { git = true })
    local lh = require("config.local_history")
    local dones = {}
    patch(lh, {
      snapshot = function(opts)
        dones[#dones + 1] = opts.done
      end,
    })
    local ctx = new_context()
    guarded():make_request("q", ctx, new_observer())
    H.eq(0, rec.n, "started before the checkpoint finished")
    H.eq(false, autosave().enabled(), "in flight while waiting")
    dones[1]("deadbeef")
    H.eq(1, rec.n)
    dones[1]("again") -- a late fallback timer must not start it twice
    H.eq(1, rec.n)
    rec.observers[1].on_complete("success", "")
    H.eq(true, autosave().enabled())

    local ctx2 = new_context()
    guarded():make_request("q", ctx2, new_observer())
    H.eq(1, rec.n)
    ctx2.cancel(ctx2)
    H.eq(true, autosave().enabled(), "cancel released")
    dones[2]()
    H.eq(1, rec.n, "a cancelled request was started anyway")
  end)'''),
    ...sec(r'release exactly once'),
    ...para('--', r'Auto-save is a shared resource, so the plugin counts requests in flight. The test starts two requests, checks that auto-save stays off, completes the first twice (a duplicate completion) and shows that the duplicate must not release the second one, and that auto-save turns on only when the second ends, with as_on_calls equal to 1. Other tests in the same group cover on_complete forwarding, a synchronous throw from the provider (released and re-raised), cancel with and without on_complete, cancel that throws, auto-save that the user switched on or off meanwhile, and the observer wrapper keeping the original methods.'),
    ...code('lua', r'tests/agent-99-guard_spec.lua · lines 523-544', r'''
  it("the first request turns auto-save off, a second leaves it off, release happens once each", function()
    H.eq(true, autosave().enabled())
    start()
    H.eq(false, autosave().enabled())
    start()
    H.eq(false, autosave().enabled())
    rec.observers[1].on_complete("success", "")
    H.eq(false, autosave().enabled(), "turned on while a request is still in flight")
    rec.observers[1].on_complete("success", "") -- duplicate: must not release the second request
    H.eq(false, autosave().enabled(), "a duplicate completion released another request")
    rec.observers[2].on_complete("success", "")
    H.eq(true, autosave().enabled())
    H.eq(1, as_on_calls)
  end)

  it("releases on on_complete and forwards to the original observer", function()
    local _, obs = start()
    H.eq(false, autosave().enabled())
    local ret = rec.observers[1].on_complete("success", "text")
    H.eq("orig-return", ret)
    H.eq({ { "success", "text" } }, obs.completed)
    H.eq(true, autosave().enabled())'''),
    ...sec(r'the gate without a sandbox'),
    ...para('--', r'This block removes bwrap by setting PATH to a directory that does not exist, which gives the same refusal as Windows and macOS. The before_each also stubs vim.notify. The first test is the contract: make_request returns nil, nothing was spawned, auto-save was not touched (its off function was never called), on_complete is called once with failed and a text naming xynovim_99_allow_unsandboxed, and one ERROR notification was shown. Failing before taking the auto-save lock matters: a refused request must not leave a lock held. The next test makes sure of exactly that, by showing that a later request with the opt-in still toggles auto-save.'),
    ...code('lua', r'tests/agent-99-guard_spec.lua · lines 799-860', r'''
describe("Guarded.make_request without a sandbox backend", function()
  local rec, restore_claude, notes, restore_notify, saved_path

  before_each(function()
    vim.g.xynovim_99_sandbox = nil
    vim.g.xynovim_99_allow_unsandboxed = nil
    saved_path = vim.env.PATH
    vim.env.PATH = "/nonexistent-xyno-path" -- no bwrap (the same refusal as Windows / macOS)
    rec, restore_claude = fake_claude()
    autosave().on()
    notes = {}
    restore_notify = patch(vim, {
      notify = function(msg, level)
        notes[#notes + 1] = { msg = msg, level = level }
      end,
    })
  end)

  after_each(function()
    vim.env.PATH = saved_path
    restore_notify()
    restore_claude()
    for _, fn in ipairs(H._restore) do
      pcall(fn)
    end
    H._restore = {}
    vim.g.xynovim_99_sandbox = nil
    vim.g.xynovim_99_allow_unsandboxed = nil
    autosave().on()
  end)

  it("refuses: nothing is spawned, on_complete('failed') names the opt-in, auto-save is untouched", function()
    local off_calls = 0
    local as = autosave()
    local orig_off = as.off
    patch(as, {
      off = function(...)
        off_calls = off_calls + 1
        return orig_off(...)
      end,
    })
    local _, obs, res = start()
    H.is_nil(res)
    H.eq(0, rec.n)
    H.eq(0, off_calls)
    H.eq(true, as.enabled())
    H.eq(1, #obs.completed)
    H.eq("failed", obs.completed[1][1])
    H.has(obs.completed[1][2], "xynovim_99_allow_unsandboxed")
    H.eq(1, #notes)
    H.eq(vim.log.levels.ERROR, notes[1].level)
  end)

  it("does not leak the in-flight token: a later request with the opt-in still toggles auto-save", function()
    start()
    vim.g.xynovim_99_allow_unsandboxed = true
    local _, _, res = start()
    H.eq("result1", res)
    H.eq(false, autosave().enabled())
    rec.observers[1].on_complete("success", "")
    H.eq(true, autosave().enabled())
  end)'''),
    ...sec(r'allow_unsandboxed warns every time'),
    ...para('--', r'The remaining tests of the block check that the opt-in runs the request and warns on every request, not only the first, that sandbox = false warns too, and that _build_command raises instead of returning an unwrapped command, so no code path can quietly build an unsandboxed one.'),
    ...sec(r'the provider picker cannot bypass the guard'),
    ...para('--', r'99 ships a provider picker bound to leader 9P. Choosing another provider would swap the guarded one for an unguarded one. The test enumerates every provider the picker lists, selects each that is not the Claude provider, and requires that the active provider is still the guarded one, that the number of refusal notifications equals the number of other providers, and that no Provider set message announced a switch that did not happen.'),
    ...code('lua', r'tests/agent-99-guard_spec.lua · lines 903-938', r'''
describe("provider picker (<leader>9P)", function()
  local pickers, cap

  before_each(function()
    vim.g.xynovim_99_sandbox = nil
    vim.g.xynovim_99_allow_unsandboxed = nil
    require("99").set_provider(guarded())
    pickers = require("99.extensions.pickers")
    cap = H.capture_notify()
  end)

  after_each(function()
    cap.restore()
    vim.g.xynovim_99_sandbox = nil
    vim.g.xynovim_99_allow_unsandboxed = nil
    require("99").set_provider(guarded())
  end)

  it("refuses every provider but the guarded one, spawning nothing", function()
    local g = guarded()
    local info = pickers.get_providers()
    H.ok(#info.names >= 2, "no other providers listed")
    for _, name in ipairs(info.names) do
      if info.lookup[name] ~= claude() then
        pickers.on_provider_selected(name, info.lookup)
        H.ok(require("99").get_provider() == g, name .. " replaced the guarded provider")
      end
    end
    local refused = vim.tbl_filter(function(n)
      return type(n.msg) == "string" and n.msg:find("only the guarded", 1, true)
    end, cap.list)
    H.eq(#info.names - 1, #refused)
    H.eq(0, #vim.tbl_filter(function(n)
      return type(n.msg) == "string" and n.msg:find("Provider set", 1, true)
    end, cap.list), "the picker announced a switch that did not happen")
  end)'''),
    ...para('--', r'Then the opt-out rules: with sandbox = false another provider is accepted, but wrapped (its inner provider is recorded in _xyno_inner). allow_unsandboxed does not unlock providers while a working sandbox exists, and only unlocks them where no backend exists. The last test in this block covers a provider chosen under the opt-in that is refused per request once the opt-in is revoked, and warns while it is active.'),
    ...code('lua', r'tests/agent-99-guard_spec.lua · lines 940-967', r'''
  it("allows another provider with the explicit opt-out", function()
    vim.g.xynovim_99_sandbox = false
    local info = pickers.get_providers()
    local other = info.lookup.OpenCodeProvider
    H.ok(other, "OpenCodeProvider not listed")
    pickers.on_provider_selected("OpenCodeProvider", info.lookup)
    H.ok(require("99").get_provider()._xyno_inner == other)
  end)

  it("allow_unsandboxed does not unlock providers while a working sandbox exists", function()
    if vim.fn.has("linux") ~= 1 or vim.fn.executable("bwrap") ~= 1 then
      return
    end
    vim.g.xynovim_99_allow_unsandboxed = true
    local info = pickers.get_providers()
    pickers.on_provider_selected("OpenCodeProvider", info.lookup)
    H.ok(require("99").get_provider() == guarded())
  end)

  it("allow_unsandboxed unlocks providers when there is no backend", function()
    local saved = vim.env.PATH
    vim.env.PATH = "/nonexistent-xyno-path"
    vim.g.xynovim_99_allow_unsandboxed = true
    local info = pickers.get_providers()
    pickers.on_provider_selected("OpenCodeProvider", info.lookup)
    vim.env.PATH = saved
    H.ok(require("99").get_provider()._xyno_inner == info.lookup.OpenCodeProvider)
  end)'''),
    ...sec(r'the pending test'),
    ...para('--', r'One test is registered with pending and a reason: a real 99 request end to end is not verified, because it needs a real claude session and network. It is better to list what is not tested than to leave it out.'),
    ...code('lua', r'tests/agent-99-guard_spec.lua · lines 896-899', r'''
pending(
  "a real 99 request end to end (claude, sandbox, response applied)",
  "not verified in the README: needs a real claude session and network"
)'''),
    ...sec(r'trade-offs'),
    blank,
    ...pt('--', r'Many small tests of a counter', r'auto-save locking has several edge cases (duplicate completion, cancel after completion, cancel that throws). Each has its own test, so a failure names the bug.'),
    ...pt('--', r'Real git for the checkpoint', r'the snapshot test uses a real repository and the local history refs, because this is the property users rely on to roll back an agent.'),
    ...sec(r'history'),
    blank,
    ...pt('--', r'b2fee5c (2026-10-13)', r'created with the 22-spec suite.'),
    ...pt('--', r'98c9bb4 (2026-10-13)', r'field test and spec findings, including "checkpoint before agent start".'),
    ...pt('--', r'440d781 (2026-10-16)', r'fail-closed; 99 lines added to this spec.'),
    ...pt('--', r'7025437 (2026-10-16)', r'checkpoint and argument tests use the explicit sandbox opt-out because CI has no bwrap.'),
    ...pt('--', r'cd602fd, a2e0d5a, af6ca87, 35a9ad7 (2026-10-21)', r'platform fixes; the last one names run 39668277143 and path forms in this spec on Windows.'),
  ],
);
