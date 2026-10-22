import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/tests/agent-sandbox_spec.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'agent-sandbox_spec.lua — attacking the bubblewrap wrapper'),
    cm('--', r'59 tests that build the command, then run hostile shell scripts inside it'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'security spec for lua/config/agent_sandbox.lua, the wrapper around the claude CLI used by 99'),
    kv(r'language', r'Lua spec, 1229 lines, 59 it() blocks, 13 describe() blocks'),
    kv(r'platform', r'Linux only (the first lines carry an xyno-os: linux header)'),
    kv(r'needs', r'bwrap that can create a user namespace for the behavioural tests; the structural ones need only the binary'),
    kv(r'history', r'9 commits, 2026-10-13 to 2026-10-16'),
    ...sec(r'why this file exists'),
    ...para('--', r'The 99 agent runs with all permission prompts off, so the sandbox is the only barrier between a prompt-injected agent and the rest of the home directory. A sandbox that is wrong is worse than none, because it gives confidence. So this spec does two kinds of work. Structure tests build the wrapped command and assert which bwrap arguments are present or absent. Behaviour tests then run real shell commands inside bwrap and check what could and could not be done. The header says which is which: structure tests use a fake home, behaviour tests also run against a fake home, never the real one.'),
    ...code('lua', r'tests/agent-sandbox_spec.lua · lines 1-8', r'''
-- lua/config/agent_sandbox.lua: the bubblewrap wrapper around `claude` (99).
-- Structure tests build the wrapped command against a FAKE $HOME (the module
-- reads os_homedir() once at load, so it is reloaded per fake home); the
-- behavioural tests run real commands inside bwrap against that same fake
-- home, never against the real one. No rust-analyzer needed.
-- xyno-os: linux (bubblewrap exists only on Linux; the fail-closed refusal is tested in agent-failclosed on every platform)
local H = require("xynotest.helpers")
local harness = require("xynotest.harness")'''),
    ...sec(r'a fake HOME that the module believes'),
    ...para('--', r'agent_sandbox reads os_homedir() once, at load. To test it against a controlled home, load_for(home) sets HOME, clears package.loaded, requires the module again, restores HOME and puts the original module back. fake_home creates the directory under ~/.cache rather than /tmp, because, as its comment says, the sandbox hides /tmp. It creates ~/.claude inside it, since bwrap needs it as the parent of the masks, and registers the directory for cleanup. Each test gets the real binary and a world of its own making.'),
    ...code('lua', r'tests/agent-sandbox_spec.lua · lines 35-47, 59-69', r'''
local function fake_home(opts)
  local base = vim.uv.os_homedir() .. "/.cache"
  mkdir(base)
  local dir = assert(vim.uv.fs_mkdtemp(base .. "/xyno-sandbox-spec-XXXXXX"))
  H._dirs[#H._dirs + 1] = dir
  dir = vim.uv.fs_realpath(dir)
  if not (opts or {}).no_claude then
    mkdir(dir .. "/.claude") -- bwrap needs it as the parent of the ~/.claude/<x> masks
  end
  return dir
end

--- Run `fn`; if it fails, report the test as skipped with `reason` (a confirmed
...
--- agent_sandbox loaded as if $HOME were `home`.
local function load_for(home)
  local old = vim.uv.os_getenv("HOME")
  vim.uv.os_setenv("HOME", home)
  package.loaded[MOD] = nil
  local m = require(MOD)
  vim.uv.os_setenv("HOME", old)
  package.loaded[MOD] = real_mod
  return m
end
'''),
    ...sec(r'reading a command as a sequence'),
    ...para('--', r'The wrapped command is a list of strings. Whether it contains a given flag with a given operand is a question about consecutive elements, so the spec defines find_seq, expect_seq and expect_no_seq. hidden_file asks a subtler question: is a file hidden by binding an empty regular file over it? The comment records a finding, that /dev/null gave EACCES, so hiding uses a private empty file whose name ends in .empty.'),
    ...code('lua', r'tests/agent-sandbox_spec.lua · lines 80-112', r'''
local function find_seq(a, ...)
  local seq = { ... }
  for i = 1, #a - #seq + 1 do
    local hit = true
    for j = 1, #seq do
      if a[i + j - 1] ~= seq[j] then
        hit = false
        break
      end
    end
    if hit then
      return i
    end
  end
end

local function expect_seq(a, ...)
  H.ok(find_seq(a, ...), "missing in wrapped command: " .. table.concat({ ... }, " "))
end

local function expect_no_seq(a, ...)
  H.not_ok(find_seq(a, ...), "unexpected in wrapped command: " .. table.concat({ ... }, " "))
end

--- Hidden files are bound to an empty regular file (/dev/null gave EACCES): is `p` bound from one?
local function hidden_file(a, p)
  for i = 1, #a - 2 do
    if a[i] == "--ro-bind" and a[i + 2] == p then
      return a[i + 1] ~= "/dev/null" and a[i + 1]:match("%.empty$") ~= nil
    end
  end
  return false
end'''),
    ...sec(r'running a script inside the sandbox'),
    ...para('--', r'sb() builds the wrapped command for a bash script, skips unless H.need_sandbox() passes, runs it with HOME set to the fake home, and returns the result and the temp dir. out() joins stdout and stderr so assertion messages show everything. An after_each restores every environment variable that a test changed, in reverse order, and puts the real module back.'),
    ...code('lua', r'tests/agent-sandbox_spec.lua · lines 120-148', r'''
local function sb(m, home, script, project, opts)
  H.need_sandbox()
  local tmp = H.tmpdir()
  local cmd = wrap(m, { "bash", "-c", script }, project, tmp)
  local env = { HOME = home }
  for k, v in pairs((opts or {}).env or {}) do
    env[k] = v
  end
  local r = vim.system(cmd, { cwd = project, text = true, env = env }):wait((opts or {}).timeout or 60000)
  return r, tmp
end

local function out(r)
  return (r.stdout or "") .. (r.stderr or "")
end

after_each(function()
  for i = #env_restore, 1, -1 do
    local e = env_restore[i]
    vim.uv.os_setenv(e[1], e[2] or "")
    if e[2] == nil then
      vim.uv.os_unsetenv(e[1])
    end
  end
  env_restore = {}
  package.loaded[MOD] = real_mod
end)

-- ------------------------------------------------------------ 1, 17: opt-out'''),
    ...sec(r'opt-out rules'),
    ...para('--', r'The opt-out block repeats the fail-closed rules of agent-failclosed_spec.lua, but with bwrap in the picture. Setting PATH to a directory that does not exist removes bwrap, and wrap() must then return nil with a reason naming bwrap. With allow_unsandboxed = true and no bwrap, the same table comes back and the status says unsandboxed via allow_unsandboxed. The key case for security is the next one: allow_unsandboxed alone never disables a working bwrap. It is for machines that have no sandbox, not for turning one off. Only sandbox = false does that, and it wins over a working bwrap.'),
    ...code('lua', r'tests/agent-sandbox_spec.lua · lines 175-199, 219-229', r'''
  it("refuses (nil, reason) when bwrap is not executable and nothing is set", function()
    no_bwrap()
    with_g("xynovim_99_sandbox", nil, function()
      with_g("xynovim_99_allow_unsandboxed", nil, function()
        local cmd = { "claude", "--version" }
        local got, reason = real_mod.wrap(cmd, "/tmp", "/tmp")
        H.eq(nil, got)
        H.ok(tostring(reason):find("bwrap", 1, true), "reason names bwrap: " .. tostring(reason))
        H.eq("refused", real_mod.status().mode)
      end)
    end)
  end)

  it("allow_unsandboxed = true runs unsandboxed when there is no backend", function()
    no_bwrap()
    with_g("xynovim_99_sandbox", nil, function()
      with_g("xynovim_99_allow_unsandboxed", true, function()
        local cmd = { "claude", "--version" }
        H.ok(real_mod.wrap(cmd, "/tmp", "/tmp") == cmd, "the same table comes back")
        local st = real_mod.status()
        H.eq("unsandboxed", st.mode)
        H.eq("allow_unsandboxed", st.via)
      end)
    end)
  end)
...
  it("allow_unsandboxed alone never disables a working bwrap", function()
    if vim.fn.executable("bwrap") ~= 1 or vim.fn.has("linux") ~= 1 then
      return harness.skip("bwrap not found")
    end
    with_g("xynovim_99_sandbox", nil, function()
      with_g("xynovim_99_allow_unsandboxed", true, function()
        H.eq("bwrap", real_mod.status().mode)
        H.eq("bwrap", real_mod.wrap({ "true" }, H.tmpdir(), H.tmpdir())[1])
      end)
    end)
  end)'''),
    ...sec(r'Windows and macOS are simulated here'),
    ...para('--', r'The test for a platform with no bubblewrap replaces vim.fn.has so that has("linux") answers 0 and checks that wrap refuses, the reason mentions Linux, and a bwrap on PATH makes no difference. The replacement is restored before the assertion is re-raised.'),
    ...code('lua', r'tests/agent-sandbox_spec.lua · lines 231-253', r'''
  it("a platform without bubblewrap (has('linux') == 0, e.g. Windows or macOS) refuses even with a bwrap on PATH", function()
    local real_has = vim.fn.has
    vim.fn.has = function(f)
      if f == "linux" then
        return 0
      end
      return real_has(f)
    end
    local ok, err = pcall(function()
      with_g("xynovim_99_sandbox", nil, function()
        with_g("xynovim_99_allow_unsandboxed", nil, function()
          local st = real_mod.status()
          H.eq("refused", st.mode)
          H.ok(st.reason:find("Linux", 1, true), st.reason)
          local got, reason = real_mod.wrap({ "claude" }, "/tmp", "/tmp")
          H.eq(nil, got)
          H.ok(reason, "a reason comes with the refusal")
        end)
      end)
    end)
    vim.fn.has = real_has
    assert(ok, err)
  end)'''),
    ...sec(r'secrets leave the environment'),
    ...para('--', r'Names that look like secrets are removed with --unsetenv. The test sets a sentinel XYNO_SPEC_SENTINEL_TOKEN and a harmless variable, builds the command, and requires --unsetenv for every name returned by scrub_names and none for the harmless one. A second test goes all the way: GITHUB_TOKEN is set to ghp_sentinel in the parent, and the script printing gh=${GITHUB_TOKEN-unset} must print gh=unset while a harmless variable survives as kept.'),
    ...code('lua', r'tests/agent-sandbox_spec.lua · lines 461-487', r'''
  it("emits --unsetenv for every scrub name", function()
    if vim.fn.executable("bwrap") ~= 1 then
      return harness.skip("bwrap not found")
    end
    setenv("XYNO_SPEC_SENTINEL_TOKEN", "s3cret")
    setenv("XYNO_SPEC_HARMLESS", "ok")
    local m = load_for(fake_home())
    local a = wrap(m, { "true" }, H.tmpdir(), H.tmpdir())
    local names = m.scrub_names()
    H.has(names, "XYNO_SPEC_SENTINEL_TOKEN")
    H.not_ok(contains(names, "XYNO_SPEC_HARMLESS"))
    for _, n in ipairs(names) do
      expect_seq(a, "--unsetenv", n)
    end
    expect_no_seq(a, "--unsetenv", "XYNO_SPEC_HARMLESS")
  end)

  it("really unsets a sentinel GITHUB_TOKEN inside the sandbox", function()
    H.need_sandbox()
    setenv("GITHUB_TOKEN", "ghp_sentinel")
    setenv("XYNO_SPEC_KEEP", "kept")
    local home = fake_home()
    local m = load_for(home)
    local r = sb(m, home, 'echo "gh=${GITHUB_TOKEN-unset} keep=${XYNO_SPEC_KEEP-unset}"', H.tmpdir())
    H.eq(0, r.code, out(r))
    H.match(r.stdout, "gh=unset keep=kept", true)
  end)'''),
    ...sec(r'credentials are hidden, not denied'),
    ...para('--', r'A long table of hidden directories (.ssh, .gnupg, .aws, .kube, browser profiles, password managers and more) is checked against the command. The behaviour test then proves the effect: inside the sandbox the .ssh listing, .netrc, .bash_history, the Claude daemon directory and the prompt history all have size zero, while the real secret file outside is untouched. Hidden means empty, so tools that expect the path do not crash.'),
    ...code('lua', r'tests/agent-sandbox_spec.lua · lines 582-596', r'''
  it("really hides credentials inside the sandbox (dir empty, file empty)", function()
    H.need_sandbox()
    local home = populated()
    local m = load_for(home)
    local r = sb(
      m, home,
      'echo "ssh=[$(ls -A "$HOME/.ssh" | wc -l)] netrc=[$(cat "$HOME/.netrc" 2>/dev/null | wc -c)] hist=[$(cat "$HOME/.bash_history" 2>/dev/null | wc -c)] '
        .. 'daemon=[$(ls -A "$HOME/.claude/daemon" | wc -l)] prompts=[$(cat "$HOME/.claude/history.jsonl" 2>/dev/null | wc -c)]"',
      H.tmpdir()
    )
    H.eq(0, r.code, out(r))
    H.match(r.stdout, "ssh=[0] netrc=[0] hist=[0] daemon=[0] prompts=[0]", true)
    -- the real files are untouched
    H.eq("s", vim.fn.readfile(home .. "/.ssh/secret")[1])
  end)'''),
    ...sec(r'the claude.json copy'),
    ...para('--', r'The ~/.claude.json file has to be writable for the CLI, but a write must never reach the real file. The wrapper binds a private copy with mode 600 over it. The test finds the --bind pair in the command, asserts that the source is not the real file, compares the content, and checks the mode with bit.band. The behaviour test writes {"planted":true} from inside and shows that the real file still says orig.'),
    ...code('lua', r'tests/agent-sandbox_spec.lua · lines 602-642', r'''
  it("is replaced by a private 0600 copy bound over it", function()
    if vim.fn.executable("bwrap") ~= 1 then
      return harness.skip("bwrap not found")
    end
    local home = fake_home()
    write(home .. "/.claude.json", '{"mcpServers":{}}\n')
    local a = wrap(load_for(home), { "true" }, H.tmpdir(), H.tmpdir())
    local copy
    for j = 1, #a - 2 do
      if a[j] == "--bind" and a[j + 2] == home .. "/.claude.json" then
        copy = a[j + 1]
      end
    end
    H.ok(copy, "no --bind <copy> ~/.claude.json")
    H.ok(copy ~= home .. "/.claude.json")
    H.eq({ '{"mcpServers":{}}' }, vim.fn.readfile(copy))
    H.eq(tonumber("600", 8), bit.band(vim.uv.fs_stat(copy).mode, tonumber("777", 8)))
    vim.fn.delete(copy)
  end)

  it("is not bound when ~/.claude.json does not exist", function()
    if vim.fn.executable("bwrap") ~= 1 then
      return harness.skip("bwrap not found")
    end
    local home = fake_home()
    local a = wrap(load_for(home), { "true" }, H.tmpdir(), H.tmpdir())
    for j = 1, #a - 2 do
      H.not_ok(a[j] == "--bind" and a[j + 2] == home .. "/.claude.json")
    end
  end)

  it("a write inside the sandbox hits only the copy", function()
    H.need_sandbox()
    local home = fake_home()
    write(home .. "/.claude.json", '{"orig":true}\n')
    local m = load_for(home)
    local r = sb(m, home, 'echo \'{"planted":true}\' > "$HOME/.claude.json" && cat "$HOME/.claude.json"', H.tmpdir())
    H.eq(0, r.code, out(r))
    H.match(r.stdout, "planted", true)
    H.eq({ '{"orig":true}' }, vim.fn.readfile(home .. "/.claude.json"))
  end)'''),
    ...sec(r'the project is writable, but its .git is not'),
    ...para('--', r'The behaviour block builds a fake home with .ssh, .aws, a real .bashrc and .profile and a git project from the basic fixture. The first test proves the central deal of the sandbox: the project accepts writes and the home does not. The second proves the commit barrier: the script edits a file, runs git add, tries to commit, and tries to plant a pre-commit hook. The test requires a Read-only file system error, rc=1 for the hook, the commit count unchanged at one, and no hook file on disk. The agent can edit your code, but it cannot commit or install hooks that would run unsandboxed later.'),
    ...code('lua', r'tests/agent-sandbox_spec.lua · lines 924-960', r'''
describe("sandbox behaviour", function()
  --- A fake home plus a git project, the module loaded for it.
  local function env()
    H.need_sandbox()
    local home = fake_home()
    for _, d in ipairs({ ".config/autostart", ".config/systemd/user", ".claude", ".ssh", ".aws" }) do
      mkdir(home .. "/" .. d)
    end
    write(home .. "/.bashrc", "# real\n")
    write(home .. "/.profile", "# real\n")
    write(home .. "/.ssh/id_rsa", "PRIVATE\n")
    write(home .. "/.aws/credentials", "SECRET\n")
    local project = H.fixture("basic", { git = true })
    return home, load_for(home), project
  end

  it("keeps the project writable and the home read-only", function()
    local home, m, project = env()
    local r = sb(m, home, 'echo ok > inside.txt && cat inside.txt && ! touch "$HOME/xyno-sandbox-probe"', project)
    H.eq(0, r.code, out(r))
    H.eq("ok", vim.trim(vim.fn.readfile(project .. "/inside.txt")[1]))
    H.eq(0, vim.fn.filereadable(home .. "/xyno-sandbox-probe"))
  end)

  it("cannot commit: .git is read-only", function()
    local home, m, project = env()
    local r = sb(
      m, home,
      "echo change >> src/lib.rs; git add -A 2>&1; git -c user.name=t -c user.email=t@t commit -m x 2>&1; "
        .. "echo hook > .git/hooks/pre-commit 2>&1; echo rc=$?",
      project
    )
    H.match(out(r), "Read-only file system", true)
    H.match(r.stdout, "rc=1", true, "a hook cannot be planted: " .. out(r))
    H.eq(1, tonumber(H.git(project, "rev-list", "--count", "HEAD")))
    H.eq(0, vim.fn.filereadable(project .. "/.git/hooks/pre-commit"))
  end)'''),
    ...sec(r'escape attempts'),
    ...para('--', r'One test lists writes that an attacker would try for persistence: shell rc files, autostart, systemd user units, /etc/cron.d, the cron spool, and a symlink in the project that points to .bashrc. The helper fail runs a command and prints WROTE only if it succeeded. The test requires done on stdout, no WROTE, and the real .bashrc and .profile still containing the original line. The next test tries /proc/self/root and /proc/1/root writes, mount, unshare in two forms, and a nested bwrap, with the same oracle.'),
    ...code('lua', r'tests/agent-sandbox_spec.lua · lines 962-999', r'''
  it("blocks writes to shell rc files, autostart, systemd and cron, and symlink tricks", function()
    local home, m, project = env()
    local script = table.concat({
      'fail() { if "$@" 2>/dev/null; then echo "WROTE: $*"; fi; }',
      'fail sh -c \'echo x >> "$HOME/.bashrc"\'',
      'fail sh -c \'echo x >> "$HOME/.profile"\'',
      'fail sh -c \'echo x > "$HOME/.config/autostart/evil.desktop"\'',
      'fail sh -c \'echo x > "$HOME/.config/systemd/user/evil.service"\'',
      "fail sh -c 'echo x > /etc/cron.d/evil'",
      "fail sh -c 'echo x > /var/spool/cron/evil'",
      'ln -s "$HOME/.bashrc" link-to-bashrc',
      "fail sh -c 'echo x > link-to-bashrc'",
      "echo done",
    }, "\n")
    local r = sb(m, home, script, project)
    H.match(r.stdout, "done", true, out(r))
    H.no_match(r.stdout, "WROTE", true, out(r))
    H.eq({ "# real" }, vim.fn.readfile(home .. "/.bashrc"))
    H.eq({ "# real" }, vim.fn.readfile(home .. "/.profile"))
  end)

  it("blocks /proc/self/root and /proc/1/root writes, mount, unshare, nested bwrap", function()
    local home, m, project = env()
    local script = table.concat({
      'fail() { if "$@" 2>/dev/null; then echo "WROTE: $*"; fi; }',
      'fail sh -c \'echo x > "/proc/self/root$HOME/.bashrc"\'',
      'fail sh -c \'echo x > "/proc/1/root$HOME/.bashrc"\'',
      "fail mount -t tmpfs none /mnt",
      "fail unshare -r true",
      "fail unshare -U true",
      "fail bwrap --ro-bind / / true",
      "echo done",
    }, "\n")
    local r = sb(m, home, script, project)
    H.match(r.stdout, "done", true, out(r))
    H.no_match(r.stdout, "WROTE", true, out(r))
    H.eq({ "# real" }, vim.fn.readfile(home .. "/.bashrc"))
  end)'''),
    ...sec(r'process and device view'),
    ...para('--', r'Only a handful of pids may be visible (the test requires between 1 and 12). ~/.ssh and ~/.aws read as empty, a docker socket is invisible, and /run/user/UID has no entries. There is no controlling tty, which blocks the TIOCSTI keystroke injection trick: opening /dev/tty must fail.'),
    ...code('lua', r'tests/agent-sandbox_spec.lua · lines 1001-1027', r'''
  it("shows only a handful of pids", function()
    local home, m, project = env()
    local r = sb(m, home, "ls /proc | grep -c '^[0-9][0-9]*$'", project)
    H.eq(0, r.code, out(r))
    local n = tonumber(vim.trim(r.stdout))
    H.ok(n and n >= 1 and n <= 12, "visible pids: " .. tostring(r.stdout))
  end)

  it("makes ~/.ssh and ~/.aws empty, the docker socket and /run/user/UID invisible", function()
    local home, m, project = env()
    local script = table.concat({
      'echo "ssh=$(cat "$HOME/.ssh/id_rsa" 2>/dev/null | wc -c) aws=$(cat "$HOME/.aws/credentials" 2>/dev/null | wc -c)"',
      "[ -S /run/docker.sock ] && echo DOCKER-VISIBLE",
      "echo run_user=$(ls -A /run/user/" .. uid .. " 2>/dev/null | wc -l)",
    }, "\n")
    local r = sb(m, home, script, project)
    H.eq(0, r.code, out(r))
    H.match(r.stdout, "ssh=0 aws=0", true)
    H.no_match(r.stdout, "DOCKER-VISIBLE", true)
    H.match(r.stdout, "run_user=0", true)
  end)

  it("has no controlling tty (TIOCSTI blocked)", function()
    local home, m, project = env()
    local r = sb(m, home, "(exec 3</dev/tty) 2>/dev/null && echo HAS-TTY || echo no-tty", project)
    H.match(r.stdout, "no-tty", true, out(r))
  end)'''),
    ...sec(r'project memory'),
    ...para('--', r'Claude stores per-project memory under ~/.claude/projects/<mangled path>/memory. A planted MEMORY.md there would be read by later, unsandboxed sessions: a persistence channel. The test tries to create, plant, rename and symlink that directory, and to replace the project directory by a symlink, while insisting that the transcript file next to it stays writable, because the CLI needs that. The former-bug test checks the rename trick, creating other projects, and moving the project directory itself.'),
    ...code('lua', r'tests/agent-sandbox_spec.lua · lines 1063-1090', r'''
describe("project memory directory", function()
  it("cannot be created, planted, renamed or symlinked, while transcripts stay writable", function()
    H.need_sandbox()
    local home = fake_home()
    mkdir(home .. "/.claude")
    local m = load_for(home)
    local base = H.tmpdir()
    mkdir(base .. "/proj")
    local project = vim.uv.fs_realpath(base .. "/proj")
    local d = home .. "/.claude/projects/" .. project:gsub("[^%w]", "-")
    local script = table.concat({
      'd="' .. d .. '"',
      'fail() { if "$@" 2>/dev/null; then echo "WROTE: $*"; fi; }',
      'fail mkdir -p "$d/memory/sub"',
      'fail sh -c \'echo planted > "$d/memory/MEMORY.md"\'',
      'fail mv "$d/memory" "$d/memory-moved"',
      'fail sh -c \'mkdir /tmp/x && mv /tmp/x "$d/memory2" && mv "$d/memory2" "$d/memory"\'',
      'fail ln -sfn /tmp "$d/memory"',
      'fail sh -c \'rm -rf "$d" && ln -s /tmp "$d"\'',
      'echo transcript > "$d/s.jsonl" && echo transcript-ok',
    }, "\n")
    local r = sb(m, home, script, project)
    H.match(r.stdout, "transcript-ok", true, out(r))
    H.no_match(r.stdout, "WROTE", true, out(r))
    H.eq({ "transcript" }, vim.fn.readfile(d .. "/s.jsonl"))
    H.eq({}, vim.fn.glob(d .. "/memory/*", true, true))
    H.eq(0, vim.fn.filereadable(d .. "/memory/MEMORY.md"))
  end)'''),
    ...sec(r'fresh machines'),
    ...para('--', r'A wrapper that works only on the author machine would be a trap. One test runs the sandbox with no ~/.claude at all and requires the script to run, using the no_claude option of fake_home.'),
    ...code('lua', r'tests/agent-sandbox_spec.lua · lines 1120-1127', r'''
  it("wrap works when ~/.claude does not exist (fresh machine)", function()
    H.need_sandbox()
    local home = fake_home({ no_claude = true })
    local m = load_for(home)
    local r = sb(m, home, "echo alive", H.tmpdir())
    H.eq(0, r.code, out(r))
    H.match(r.stdout, "alive", true)
  end)'''),
    ...sec(r'the network is a documented residual risk'),
    ...para('--', r'The sandbox shares the network namespace. The test does not hide that: it opens real listeners on 127.0.0.1 and ::1, and requires that both are reachable from inside while the user bus at /run/user/UID is hidden. A comment in the test says README claims ::1 is not reachable, but with a real listener it is. A residual risk that is measured is better than one that is assumed.'),
    ...code('lua', r'tests/agent-sandbox_spec.lua · lines 1161-1185', r'''
  it("reaches loopback listeners (documented residual; ::1 too, the netns is shared) but not /run/user/UID", function()
    H.need_sandbox()
    local srv, port = listener("127.0.0.1")
    H.ok(srv, "could not listen on 127.0.0.1")
    local srv6, port6 = listener("::1")
    local home = fake_home()
    local m = load_for(home)
    local script = table.concat({
      "(exec 3<>/dev/tcp/127.0.0.1/" .. port .. ") 2>/dev/null && echo v4=reachable || echo v4=blocked",
      port6 and ("(exec 3<>/dev/tcp/::1/" .. port6 .. ") 2>/dev/null && echo v6=reachable || echo v6=blocked") or "echo v6=nolistener",
      "[ -e /run/user/" .. uid .. "/bus ] && echo bus=visible || echo bus=hidden",
    }, "\n")
    local r = sb(m, home, script, H.tmpdir())
    srv:close()
    if srv6 then
      srv6:close()
    end
    H.eq(0, r.code, out(r))
    H.match(r.stdout, "v4=reachable", true)
    H.match(r.stdout, "bus=hidden", true)
    if srv6 then
      -- README says ::1 is not reachable; with a real listener it is (shared network namespace)
      H.match(r.stdout, "v6=reachable", true)
    end
  end)'''),
    ...sec(r'skipping that explains itself'),
    ...para('--', r'Two tests in the headless block prove the skip logic that every behavioural test depends on. With PATH emptied, sandbox_available returns false with bwrap not found, and need_sandbox raises a skip, not an error. With a fake bwrap script that prints No permissions to create a new namespace and exits 1, the reason is bwrap cannot create a sandbox here followed by the message. This is the CI container case.'),
    ...code('lua', r'tests/agent-sandbox_spec.lua · lines 1191-1212', r'''
  it("sandbox_available reports why when bwrap is missing, and need_sandbox skips", function()
    setenv("PATH", "/nonexistent-xyno-path")
    local ok, why = H.sandbox_available()
    H.eq(false, ok)
    H.match(why, "bwrap not found", true)
    local pok, err = pcall(H.need_sandbox)
    H.not_ok(pok)
    H.ok(harness.is_skip(err), "need_sandbox raises a skip, not an error")
    H.match(err.reason, "bwrap not found", true)
  end)

  it("need_sandbox skips with the bwrap message when a user namespace cannot be created", function()
    -- a fake bwrap that fails like a CI container without userns
    local bin = H.tmpdir()
    write(bin .. "/bwrap", "#!/bin/sh\necho 'bwrap: No permissions to create a new namespace' >&2\nexit 1\n")
    vim.uv.fs_chmod(bin .. "/bwrap", tonumber("755", 8))
    setenv("PATH", bin .. ":" .. vim.uv.os_getenv("PATH"))
    local ok, why = H.sandbox_available()
    H.eq(false, ok)
    H.match(why, "bwrap cannot create a sandbox here", true)
    H.match(why, "No permissions to create a new namespace", true)
  end)'''),
    ...sec(r'the last test reads the README'),
    ...para('--', r'The final test calls H.docs_text() and requires four sentences about residual risks: the credentials file must stay readable, everything unlisted under HOME is readable, loopback services are reachable, and nested .git deeper than 2 levels is not locked. If the documentation stops saying so, the suite fails. The limitations are part of the contract.'),
    ...code('lua', r'tests/agent-sandbox_spec.lua · lines 1217-1229', r'''
describe("README residual-risk claims", function()
  it("documents the residual risks that cannot be tested mechanically", function()
    local text = H.docs_text()
    for _, claim in ipairs({
      "`~/.claude/.credentials.json` must stay readable",
      "everything unlisted under `$HOME` is readable",
      "loopback services",
      "nested `.git` deeper than 2 levels is not locked",
    }) do
      H.has(text, claim)
    end
  end)
end)'''),
    ...sec(r'known bugs as assertions'),
    ...para('--', r'The helper known_bug runs a function and, if it fails, skips the test with KNOWN BUG and the first line of the error. The suite stores the correct behaviour as an assertion, so a confirmed bug stays visible, and when the bug is fixed the test simply passes. The describe block "former known bugs" is the list of those that were fixed by the final loop rounds (98c9bb4, 3f868dd, 25086fd).'),
    ...code('lua', r'tests/agent-sandbox_spec.lua · lines 49-58', r'''
local function known_bug(reason, fn)
  local ok, err = pcall(fn)
  if not ok then
    if harness.is_skip(err) then
      error(err, 0)
    end
    harness.skip("KNOWN BUG: " .. reason .. " | " .. tostring(err):gsub("\n.*", ""))
  end
end
'''),
    ...sec(r'history'),
    blank,
    ...pt('--', r'b2fee5c (2026-10-13)', r'created with the 22-spec suite.'),
    ...pt('--', r'98c9bb4, 3f868dd, 25086fd (2026-10-13 and 2026-10-14)', r'field test fixes; their messages list "99 sandbox security dir and projects rename", ".git mask/tailscale/secrets/empty files/home project", "sandbox chdir".'),
    ...pt('--', r'440d781 (2026-10-16)', r'fail-closed, 92 lines added here.'),
    ...pt('--', r'ff1c8fa, 9641d08 (2026-10-16)', r'Linux-only header and realpath fixes for other platforms.'),
  ],
);
