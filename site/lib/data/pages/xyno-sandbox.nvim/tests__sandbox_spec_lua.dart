import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-sandbox.nvim/tests/sandbox_spec.lua',
  lines: [
    cm('--', r'──────────────────────────────────────────'),
    cm('--', r'sandbox_spec.lua — two ways to test a sandbox: read the command, run the command'),
    cm('--', r'a fake $HOME, argument-vector assertions, and real attempts to escape'),
    cm('--', r'──────────────────────────────────────────'),
    kv(r'role', r'the main spec: structure tests of the bwrap command and behaviour tests inside real bwrap'),
    kv(r'language', r'Lua on the repo harness; Linux only'),
    kv(r'size', r'1,232 lines, 59 tests in 13 top-level describe groups'),
    kv(r'needs', r'bwrap and unprivileged user namespaces for the behaviour tests; they skip otherwise'),
    kv(r'history', r'added in 03b99f2 (2026-10-22); two small edits in 79bcfa5'),
    ...sec(r'why this file exists'),
    ...para('--', r'How do you test a wrapper whose job is to stop things from happening? The suite answers '
        r'in two layers, and the header of the file says so. Structure tests build the wrapped '
        r'command against a fake home directory and assert on the argument vector: this flag is '
        r'present, that bind precedes this one, nothing binds the home directory. Behaviour tests '
        r'then run real commands inside real bwrap, against the same fake home, and try to do the '
        r'forbidden thing: write to a shell rc file, plant a hook, rename a directory, mount a '
        r'filesystem. A structure test proves the policy was written down; a behaviour test proves '
        r'that the kernel enforces it.'),
    ...code('lua', r'tests/sandbox_spec.lua · lines 1-9', r'''
-- lua/xyno_sandbox/init.lua: the bubblewrap wrapper around a coding agent.
-- Structure tests build the wrapped command against a FAKE $HOME (the module
-- reads os_homedir() once at load, so it is reloaded per fake home); the
-- behavioural tests run real commands inside bwrap against that same fake
-- home, never against the real one. No rust-analyzer needed.
-- Linux only: bubblewrap exists only on Linux.
local H = require("xynotest.helpers")
if H.os ~= "linux" then
  H.skip_file("needs linux, this is " .. H.os .. ": bubblewrap exists only on Linux")
'''),
    ...para('--', r'The header says the structure tests use a fake home, that the behaviour tests never touch '
        r'the real one, and that no rust-analyzer is needed. The platform guard on the next lines '
        r'skips the whole file on anything but Linux with a reason that says why, so the file loads '
        r'without error on Windows and macOS and reports a skip instead of a failure.'),
    ...sec(r'a fake home on the real filesystem'),
    ...code('lua', r'tests/sandbox_spec.lua · lines 38-50', r'''
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
'''),
    ...para('--', r'The module reads the home directory once at load time, so each test that needs a '
        r'different home reloads the module. fake_home creates a unique directory under the real '
        r'~/.cache, not under /tmp, and the comment gives the reason: the sandbox mounts a private '
        r'tmpfs over /tmp, so a fake home placed there would be invisible inside. The directory is '
        r'registered for cleanup, resolved through realpath, and gets a .claude folder unless told '
        r'otherwise, since bwrap needs it as the parent of the masks.'),
    ...code('lua', r'tests/sandbox_spec.lua · lines 63-72', r'''
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
    ...para('--', r'load_for(home) sets HOME, unloads the module, requires it again so that it captures the '
        r'fake home, restores HOME, and puts the original module back in package.loaded. This is '
        r'the seam that makes a security tool testable without touching the real home.'),
    ...sec(r'the known-bug convention'),
    ...code('lua', r'tests/sandbox_spec.lua · lines 52-61', r'''
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
    ...para('--', r'known_bug runs a test body and, if it fails, reports the test as skipped with the reason, '
        r'keeping the assertion of the correct behaviour in place. It is a way to record a '
        r'confirmed defect without turning the suite red and without deleting the test that will '
        r'pass when it is fixed. The skip message starts with KNOWN BUG so that the runner’s output '
        r'lists it. In the file as it stands the helper is defined but no test calls it. The '
        r'xynovim commit 98c9bb4 says in its message that known-bug skips became assertions, and '
        r'the group named former known bugs holds such tests.'),
    ...sec(r'reading a command line'),
    ...code('lua', r'tests/sandbox_spec.lua · lines 83-107', r'''
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
'''),
    ...para('--', r'find_seq looks for a consecutive run of arguments inside the wrapped command. That is the '
        r'right primitive for bwrap, where meaning lives in pairs and triples such as --ro-bind SRC '
        r'DEST, and a test must not pass because a path appears somewhere unrelated. expect_seq and '
        r'expect_no_seq wrap it with readable failure messages. hidden_file checks the specific '
        r'detail that a hidden file is bound read-only from a file that ends in .empty and not from '
        r'/dev/null.'),
    ...sec(r'running a command in the sandbox'),
    ...code('lua', r'tests/sandbox_spec.lua · lines 123-134', r'''
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

'''),
    ...para('--', r'sb builds the wrapped command for a script and runs it with vim.system. It calls '
        r'need_sandbox first, so every behaviour test skips with a message on a machine that cannot '
        r'create the namespace. The environment passed to the child has HOME set to the fake home. '
        r'Everything the script prints is returned for assertions.'),
    ...sec(r'the opt-out group'),
    ...code('lua', r'tests/sandbox_spec.lua · lines 215-233', r'''
  it("sandbox = false is the explicit opt-out and wins over a working bwrap", function()
    with_g("sandbox", false, function()
      H.eq("unsandboxed", real_mod.status().mode)
      H.eq("sandbox=false", real_mod.status().via)
    end)
  end)

  it("allow_unsandboxed alone never disables a working bwrap", function()
    if vim.fn.executable("bwrap") ~= 1 or vim.fn.has("linux") ~= 1 then
      return harness.skip("bwrap not found")
    end
    with_g("sandbox", nil, function()
      with_g("allow_unsandboxed", true, function()
        H.eq("bwrap", real_mod.status().mode)
        H.eq("bwrap", real_mod.wrap({ "true" }, H.tmpdir(), H.tmpdir())[1])
      end)
    end)
  end)

'''),
    ...para('--', r'Two of the opt-out tests, shown, state the asymmetry the plugin depends on. sandbox = '
        r'false wins over a working bwrap. allow_unsandboxed alone never disables one: with bwrap '
        r'present and only that option set, status is bwrap and the wrapped command begins with '
        r'bwrap. The tests before them cover the refusal and the strict booleans; the one after '
        r'covers a platform that is not Linux, simulated by replacing vim.fn.has so that linux '
        r'answers 0 even with bwrap on the path, and expects a refusal whose reason mentions Linux.'),
    ...sec(r'the layout test'),
    ...code('lua', r'tests/sandbox_spec.lua · lines 261-281', r'''
describe("wrapped command layout", function()
  it("starts with the fixed isolation flags and ends with --chdir <cwd> -- <cmd>", function()
    if vim.fn.executable("bwrap") ~= 1 then
      return harness.skip("bwrap not found")
    end
    local home = fake_home()
    local m = load_for(home)
    local project, tmp = H.tmpdir(), H.tmpdir()
    local cwd = project .. "/sub"
    mkdir(cwd)
    local a = wrap(m, { "echo", "hi there" }, project, tmp, cwd)
    local prefix = {
      "bwrap", "--die-with-parent", "--new-session", "--unshare-user", "--disable-userns", "--unshare-pid",
      "--unshare-ipc", "--unshare-uts", "--unshare-cgroup-try", "--cap-drop", "ALL", "--ro-bind", "/", "/",
      "--dev", "/dev", "--proc", "/proc", "--tmpfs", "/tmp",
    }
    H.eq(prefix, vim.list_slice(a, 1, #prefix))
    local n = #a
    H.eq({ "--chdir", cwd, "--", "echo", "hi there" }, vim.list_slice(a, n - 4, n))
  end)

'''),
    ...para('--', r'The most literal test in the file asserts the whole fixed prefix of the command, from '
        r'bwrap through the private /tmp, in order, and the tail: --chdir, the directory, a double '
        r'dash and the command with its arguments intact (including a space inside an argument). '
        r'The order is part of the contract because later mounts sit on top of earlier ones. The '
        r'next test covers the chdir rule with a sibling directory that shares the project’s name '
        r'prefix, which must not count as inside the project.'),
    ...sec(r'behaviour: what the agent cannot do'),
    ...code('lua', r'tests/sandbox_spec.lua · lines 951-964', r'''
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
  end)

'''),
    ...para('--', r'The commit test is the clearest demonstration of a design consequence: with .git '
        r'read-only, the agent cannot commit, cannot stage, and cannot plant a hook. The script '
        r'appends to a source file, runs git add and git commit, and tries to write a pre-commit '
        r'hook. The assertions: the output contains Read-only file system, the hook write fails '
        r'(rc=1), the repository still has exactly one commit, and the hook file does not exist. '
        r'This is the price of locking git directories, and it is in the README only implicitly '
        r'(git directories are read-only). A user who wants the agent to commit has to do it '
        r'outside the sandbox.'),
    ...code('lua', r'tests/sandbox_spec.lua · lines 965-1003', r'''
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
  end)

'''),
    ...para('--', r'Two tests attack the filesystem. The first tries to append to shell startup files, write '
        r'into autostart and systemd user directories, write to cron locations, and follow a '
        r'symlink created in the project that points at the real shell rc. The second tries to '
        r'reach the same file through /proc/self/root and /proc/1/root, mount a tmpfs, create user '
        r'namespaces with unshare, and run a nested bwrap. Each attempt is run through a small '
        r'function that prints WROTE if it succeeded, and the assertion is that the word never '
        r'appears and the real file still has its original contents. The attacks are the ones the '
        r'flags are there for, which makes the tests a mapping from flag to threat: --unshare-pid '
        r'and the read-only root answer the proc trick, and --disable-userns answers unshare and '
        r'nested bwrap.'),
    ...code('lua', r'tests/sandbox_spec.lua · lines 1004-1031', r'''
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
  end)

'''),
    ...para('--', r'Visibility tests complete the picture. The number of pids in /proc must be between 1 and '
        r'12. The fake ssh key and aws credentials read as zero bytes, the docker socket is not a '
        r'socket, and /run/user/UID is empty. And opening /dev/tty must fail, which is the check '
        r'for the new session.'),
    ...sec(r'the memory directory'),
    ...code('lua', r'tests/sandbox_spec.lua · lines 1066-1095', r'''
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
  end)
end)

'''),
    ...para('--', r'This test attacks the most intricate protection in the module. Under the agent’s projects '
        r'directory, the script tries to create a memory subdirectory with a file in it, to rename '
        r'the memory directory, to bring in a directory from /tmp under that name, to replace it '
        r'with a symlink, and to delete the whole project directory and replace it with a symlink. '
        r'All of those must fail, while writing a transcript file in the same directory must '
        r'succeed. The point of the combination is that the agent keeps working and cannot plant '
        r'the one file that a later, unsandboxed session would load automatically.'),
    ...code('lua', r'tests/sandbox_spec.lua · lines 1096-1121', r'''
describe("former known bugs", function()
  it("renaming ~/.claude/projects/<name> cannot be used to plant memory/MEMORY.md", function()
    H.need_sandbox()
    local home = fake_home()
    local m = load_for(home)
    local base = H.tmpdir()
    mkdir(base .. "/proj")
    local project = vim.uv.fs_realpath(base .. "/proj")
    local d = home .. "/.claude/projects/" .. project:gsub("[^%w]", "-")
    local script = table.concat({
      'd="' .. d .. '"',
      'mv "$d" "$d-moved" 2>/dev/null && echo MOVED',
      'mkdir -p "$d/memory" 2>/dev/null',
      'echo planted > "$d/memory/MEMORY.md" 2>/dev/null && echo PLANTED',
      -- other projects' transcripts are read-only too
      'mkdir -p "' .. home .. '/.claude/projects/other" 2>/dev/null && echo OTHER-CREATED',
      'echo ok',
    }, "\n")
    local r = sb(m, home, script, project)
    H.match(r.stdout, "ok", true, out(r))
    H.no_match(r.stdout, "MOVED", true, out(r))
    H.no_match(r.stdout, "PLANTED", true, out(r))
    H.no_match(r.stdout, "OTHER-CREATED", true, out(r))
    H.eq(0, vim.fn.filereadable(d .. "/memory/MEMORY.md"), "MEMORY.md planted in the real ~/.claude")
    H.eq(0, vim.fn.isdirectory(d .. "-moved"))
  end)
'''),
    ...para('--', r'The group named former known bugs holds the regression test for the rename trick, a case '
        r'that once worked: renaming the project’s directory aside and creating a new one with a '
        r'memory file. The fix, described in the comment inside init.lua, is that a bind mount '
        r'point cannot be renamed. The test also asserts that other projects’ directories cannot be '
        r'created.'),
    ...sec(r'environment and the private copy'),
    ...code('lua', r'tests/sandbox_spec.lua · lines 481-490', r'''
  it("really unsets a sentinel GITHUB_TOKEN inside the sandbox", function()
    H.need_sandbox()
    setenv("GITHUB_TOKEN", "ghp_sentinel")
    setenv("XYNO_SPEC_KEEP", "kept")
    local home = fake_home()
    local m = load_for(home)
    local r = sb(m, home, 'echo "gh=${GITHUB_TOKEN-unset} keep=${XYNO_SPEC_KEEP-unset}"', H.tmpdir())
    H.eq(0, r.code, out(r))
    H.match(r.stdout, "gh=unset keep=kept", true)
  end)
'''),
    ...para('--', r'A sentinel token in the environment of the test is unset inside, and an unrelated '
        r'variable survives. That one test is the behavioural proof of the scrub; the structure '
        r'test before it asserts one unsetenv flag per scrubbed name.'),
    ...code('lua', r'tests/sandbox_spec.lua · lines 636-646', r'''
  it("a write inside the sandbox hits only the copy", function()
    H.need_sandbox()
    local home = fake_home()
    write(home .. "/.claude.json", '{"orig":true}\n')
    local m = load_for(home)
    local r = sb(m, home, 'echo \'{"planted":true}\' > "$HOME/.claude.json" && cat "$HOME/.claude.json"', H.tmpdir())
    H.eq(0, r.code, out(r))
    H.match(r.stdout, "planted", true)
    H.eq({ '{"orig":true}' }, vim.fn.readfile(home .. "/.claude.json"))
  end)
end)
'''),
    ...para('--', r'The private copy of the agent’s user config: the script overwrites the file with a '
        r'planted JSON and reads it back, so inside the sandbox the plant is visible, and the '
        r'assertion afterwards is that the real file still holds the original JSON.'),
    ...sec(r'what the path tests pin down'),
    ...code('lua', r'tests/sandbox_spec.lua · lines 702-724', r'''
  it("locks existing PROJECT_READONLY entries only", function()
    local m = load_for(fake_home())
    local project = H.tmpdir()
    local present = {
      ".gitmodules", ".envrc", ".mise.toml", ".tool-versions", ".nvim.lua", ".nvimrc", ".exrc",
      ".vscode/tasks.json", ".vscode/settings.json", ".mcp.json",
    }
    for _, p in ipairs(present) do
      write(project .. "/" .. p)
    end
    mkdir(project .. "/.cargo")
    local ro = set((m.readonly_paths(project)))
    for _, p in ipairs(present) do
      H.ok(ro[project .. "/" .. p], p)
    end
    H.ok(ro[project .. "/.cargo"])
    H.ok(ro[project .. "/.vscode"], "the whole .vscode dir")
    local empty = H.tmpdir()
    local ro2 = m.readonly_paths(empty)
    for _, p in ipairs(ro2) do
      H.no_match(p, empty .. "/.", true)
    end
  end)
'''),
    ...code('lua', r'tests/sandbox_spec.lua · lines 775-785', r'''
  it("masks an absent project/.git (a planted core.fsmonitor ran unsandboxed), locks a present one", function()
    local home = fake_home()
    local m = load_for(home)
    local project = H.tmpdir()
    local ro, masks = m.readonly_paths(project)
    H.has(masks, project .. "/.git")
    mkdir(project .. "/.git")
    ro, masks = m.readonly_paths(project)
    H.not_ok(contains(masks, project .. "/.git"))
    H.ok(set(ro)[project .. "/.git"])
  end)
'''),
    ...para('--', r'These two structure tests encode the rules from init.lua: only existing project-relative '
        r'entries are locked, so an empty project produces no project-relative locks at all; the '
        r'whole .vscode and .cargo directories are included; and an absent .git is masked while a '
        r'present one is locked. The second records the reason in its title: a planted '
        r'core.fsmonitor ran unsandboxed.'),
    ...sec(r'the network, stated as a fact'),
    ...code('lua', r'tests/sandbox_spec.lua · lines 1153-1191', r'''
describe("network", function()
  local function listener(host)
    local srv = vim.uv.new_tcp()
    local ok = srv:bind(host, 0)
    if not ok or not srv:listen(8, function() end) then
      srv:close()
      return nil
    end
    return srv, srv:getsockname().port
  end

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
  end)
end)

-- ------------------------------------------------------------ 18: CI skipping
'''),
    ...para('--', r'Instead of hiding the open network, the suite tests it. It starts real listeners on '
        r'127.0.0.1 and on ::1, runs a script inside the sandbox that connects to them, and asserts '
        r'that both are reachable, while the user session bus socket is not. The comment before the '
        r'last assertion is worth reading: it says that the README says ::1 is not reachable, but '
        r'with a real listener it is, since the network namespace is shared. The README in this '
        r'repository does not say that today; it lists loopback services as reachable, so the '
        r'comment is stale, and the test is right.'),
    ...sec(r'docs as an asserted contract'),
    ...code('lua', r'tests/sandbox_spec.lua · lines 1220-1232', r'''
describe("README residual-risk claims", function()
  it("documents the residual risks that cannot be tested mechanically", function()
    local text = H.docs_text()
    for _, claim in ipairs({
      "credential file under its config directory in `$HOME` must stay readable",
      "everything unlisted under `$HOME` is readable",
      "loopback services",
      "nested `.git` deeper than 2 levels is not locked",
    }) do
      H.has(text, claim)
    end
  end)
end)
'''),
    ...para('--', r'The last group reads README.md and the help file together and checks that four '
        r'residual-risk claims are still stated: the credential file that must stay readable, '
        r'everything unlisted under home being readable, loopback services, and the shallow nested '
        r'.git. A documentation edit that quietly removes a warning fails the suite. The README '
        r'states three more risks that this test does not pin.'),
    ...sec(r'what the suite does not do'),
    ...para('--', r'It does not test on macOS or Windows, where the sandbox does not exist. It does not '
        r'attempt a kernel-level escape, and it says nothing about bubblewrap itself. It cannot '
        r'show that an unlisted secret under home is safe, because it is not. The skip messages of '
        r'the behaviour tests are what make the suite honest on a machine with restricted '
        r'namespaces: a green run there means the structure tests passed and the behaviour tests '
        r'did not run.'),
    ...sec(r'history'),
    ...pt('--', r'03b99f2', r'2026-10-22, Add specs, a smoke test and CI.'),
    ...pt('--', r'79bcfa5', r'2026-10-22: two small edits as part of describing the agent generically: the first '
        r'comment no longer names a specific agent, and the documentation claim that is asserted '
        r'reads credential file under its config directory in the home directory must stay readable '
        r'instead of naming the agent’s credentials file.'),
  ],
);
