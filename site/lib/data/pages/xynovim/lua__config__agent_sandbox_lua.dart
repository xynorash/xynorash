import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/lua/config/agent_sandbox.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'agent_sandbox.lua — a bubblewrap cage for an agent that runs with --dangerously-skip-permissions'),
    cm('--', r'read-only world, hidden credentials, scrubbed environment, and a refusal when no cage exists'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'wraps the command line of the 99 agent (claude) in bubblewrap, or refuses to start it'),
    kv(r'language', r'Lua; builds a bwrap argv, reads the filesystem and the environment'),
    kv(r'size', r'511 lines, 11 commits (625b48d on 2026-10-09 to 440d781 on 2026-10-16)'),
    kv(r'exports', r'status() · wrap(cmd, project, tmp_dir) · scrub_names(env, file_login) · readonly_paths(project)'),
    kv(r'used by', r'lua/plugins/ninety-nine.lua (lines 105, 115, 224)'),
    kv(r'policy switches', r'vim.g.xynovim_99_sandbox = false · vim.g.xynovim_99_allow_unsandboxed = true'),
    kv(r'also lives in', r'xyno-sandbox.nvim (lua/xyno_sandbox/init.lua): same wrap(), options table instead of vim.g, plus run.lua'),
    ...sec(r'why this file exists'),
    ...para('--', r'The 99 plugin in this config launches claude with --dangerously-skip-permissions, which means the agent can read, write and execute anything the user can. The first lines of the file state the answer in one sentence: wrap it in bubblewrap, so that "the whole filesystem is read-only except the project, 99’s tmp dir, and the few paths claude/cargo must write". Everything else in the file is a list of consequences of taking that sentence seriously: what has to stay writable, what must be locked even inside the writable parts, what to hide, what to strip from the environment, and what to do on a machine where bubblewrap does not exist.'),
    ...para('--', r'The file is almost all data. The first part of the file is named lists with a comment explaining each group, and the logic that turns them into bwrap arguments comes after them. That structure is deliberate: a security policy that can be read as a list can be reviewed as a list. And the spec (tests/agent-sandbox_spec.lua, 59 tests) checks the lists against reality by running real sandboxes and trying a set of attacks (listed under tests that attack).'),
    ...para('--', r'It grew by hardening passes. Its history is a sequence of commits named after what a field test found: sandbox hardening (ac38272 and 0494b52), a second hardening pass with dir-level locks, absent-path masks and member crates (c4f2ace), the Final loop commits with the .git mask, tailscale, secrets, empty files, home project, sandbox chdir (3f868dd and 25086fd), and finally 440d781 on 2026-10-16, "Agent sandbox fails closed when no sandbox backend is available".'),
    ...sec(r'the contract in the header'),
    ...code('lua', r'lua/config/agent_sandbox.lua · lines 1-20', r'''
-- 99 launches `claude --dangerously-skip-permissions` with the user's full
-- privileges. Wrap it in bubblewrap. The whole filesystem is read-only except
-- the project, 99's tmp dir, and the few paths claude/cargo must write.
-- Everything that would later run UNSANDBOXED (git hooks/config, claude
-- settings/hooks/plugins, direnv, editor task files, cargo config, the claude
-- binary) is read-only even inside the writable binds. Credential dirs/files
-- are hidden, credential env vars are stripped, pid/ipc/uts namespaces are
-- unshared, capabilities dropped, nested user namespaces disabled.
-- Network stays open (the model needs it).
--
-- Fails CLOSED. bubblewrap exists only on Linux, so without a working
-- backend (Windows, macOS, Linux without bwrap) wrap() refuses (nil, reason)
-- and 99 does not start a request. Two explicit booleans (0, "false", 1 do
-- not count) lead to an unsandboxed run, which warns on every request:
--   vim.g.xynovim_99_sandbox = false            deliberate OFF, even where bwrap works
--   vim.g.xynovim_99_allow_unsandboxed = true   run anyway when NO backend exists
--                                               (never disables a working sandbox)
-- Linux+bwrap: sandboxed (only sandbox=false turns it off). No backend:
-- refused (sandbox=false or allow_unsandboxed=true: unsandboxed).
local M = {}'''),
    ...para('--', r'Read the header as a threat model. The agent starts with the user’s full privileges, so the sandbox has four layers: a read-only view of the filesystem with a few writable holes; read-only re-locks inside those holes for everything that would later run outside the sandbox (git hooks and config, claude settings, hooks and plugins, direnv, editor task files, cargo config, the claude binary itself); hiding of credentials and stripping of credential variables; and process isolation (pid, ipc and uts namespaces unshared, capabilities dropped, nested user namespaces disabled). The network stays open, because the model needs it, and the comment says so plainly.'),
    ...para('--', r'The second paragraph is the 2026-10-16 change. bubblewrap only exists on Linux, so on Windows, macOS, and a Linux without bwrap there is no backend. The earlier behaviour was to run the agent unsandboxed; the header now says the module "Fails CLOSED": wrap() refuses with (nil, reason) and 99 does not start the request. Only two explicit booleans lead to an unsandboxed run, and the comment is careful about how strictly they are read: "0, "false", 1 do not count". The values must be the Lua booleans false and true. sandbox = false is a deliberate opt-out, valid even where bwrap works. allow_unsandboxed = true only applies when there is no backend, and "never disables a working sandbox".'),
    ...sec(r'writable holes and read-only locks'),
    ...code('lua', r'lua/config/agent_sandbox.lua · lines 22-55', r'''
local home = vim.uv.os_homedir()
local pwd = vim.uv.os_get_passwd() -- uid is -1 or the call fails on Windows
local uid = pwd and pwd.uid or -1

-- Writable inside the sandbox (when they exist). Deliberately NOT here:
-- ~/.local/share/claude (the claude binary), ~/.cargo/bin, ~/.cargo/config.toml.
local WRITABLE = {
  home .. "/.claude", -- sessions/projects/todos/cache/...; exec-ish parts re-locked below
  home .. "/.cache/claude",
  home .. "/.local/state/claude",
  home .. "/.cargo/registry",
  home .. "/.cargo/git",
  home .. "/.cargo/.package-cache", -- cargo's download locks (files)
  home .. "/.cargo/.package-cache-mutate",
}
...
-- Re-bound read-only on top of the writable binds when they exist. Whatever an
-- agent planted here would run (or steer a tool) outside the sandbox later.
local HOME_READONLY = {
  home .. "/.claude/settings.json",
  home .. "/.claude/settings.local.json",
  home .. "/.claude/CLAUDE.md",
  home .. "/.claude/keybindings.json",
  home .. "/.claude/hooks",
  home .. "/.claude/commands",
  home .. "/.claude/agents",
  home .. "/.claude/skills",
  home .. "/.claude/plugins",
  home .. "/.claude/output-styles",
  home .. "/.claude/ide", -- IDE lock files make claude connect to a local server
  home .. "/.claude/rules",
  home .. "/.claude/chrome", -- chrome-native-host is a shell script Chrome launches unsandboxed
  home .. "/.claude/security", -- the security-guidance hook imports from agent-sdk-venv here, unsandboxed
}'''),
    ...para('--', r'The home directory and its uid are read once at load. WRITABLE lists the seven paths inside the home that claude and cargo must be able to write: claude’s sessions and projects directory, its cache and state, and the cargo registry, git checkouts and the two package-cache lock files. The comment on top lists what is deliberately not there: the claude binary (~/.local/share/claude), ~/.cargo/bin and ~/.cargo/config.toml. If an agent could replace the claude binary or put a program in cargo’s bin directory, the user would run it unsandboxed the next time. The writable directory ~/.claude is a compromise: it must be writable for sessions, so the parts of it that act like code are re-bound read-only on top of the writable bind, which is the next list.'),
    ...para('--', r'HOME_READONLY names them: settings and local settings, CLAUDE.md, keybindings, hooks, commands, agents, skills, plugins, output styles, rules, and three with a reason in the margin. ~/.claude/ide, because IDE lock files make claude connect to a local server; ~/.claude/chrome, because chrome-native-host is a shell script Chrome launches unsandboxed; ~/.claude/security, because the security-guidance hook imports from a python venv there, unsandboxed. Every entry is a place where a file written by the agent would be run or obeyed later, outside the cage.'),
    ...sec(r'directories that do not exist yet'),
    ...code('lua', r'lua/config/agent_sandbox.lua · lines 57-103', r'''
-- Same dirs, but when ABSENT the agent could create them (a later unsandboxed
-- claude would load them: prompt injection), so mask them with an empty
-- read-only dir (leaves one empty dir behind in ~/.claude).
local HOME_MASK_IF_ABSENT = {
  home .. "/.claude/hooks",
  home .. "/.claude/commands",
  home .. "/.claude/agents",
  home .. "/.claude/skills",
  home .. "/.claude/rules",
  home .. "/.claude/output-styles",
  home .. "/.claude/security",
}
...
-- Locked in workspace members (depth <= 3) too: cargo reads .cargo/config from
-- every ancestor of the directory it runs in; direnv reads the nearest .envrc.
local MEMBER_READONLY = { ".cargo", ".envrc" }
-- Created empty-and-read-only when absent at the project root (leaves an empty
-- .cargo dir behind): a planted .cargo/config.toml is the one that bites.
-- .git too: without one the agent ran `git init` and planted `core.fsmonitor = <cmd>` in
-- .git/config, which the user's next unsandboxed `git status` executed. (A later `git init`
-- needs `rmdir .git` first: the mask leaves an empty dir behind.)
local PROJECT_MASK_IF_ABSENT = { ".cargo", ".git" }
-- Project dir that is ALWAYS locked: read-only when present, otherwise masked
-- with an empty read-only dir (leaves one empty dir behind), because a planted
-- .claude/settings.local.json with hooks would run on the user's next claude.
local PROJECT_MASKED = ".claude"'''),
    ...para('--', r'A read-only bind only works on a path that exists. If ~/.claude/hooks is absent, the agent could create it, and a later unsandboxed claude would load the hooks it planted, which the comment calls prompt injection. So the absent ones are masked: a tmpfs is mounted over the path and remounted read-only, which leaves one empty directory behind in ~/.claude (the comment states this side effect each time it comes up). HOME_MASK_IF_ABSENT lists seven of the fourteen read-only paths, those that are directories claude would load on its own.'),
    ...para('--', r'The project-relative lists work the same way. PROJECT_READONLY holds the files that auto-execute or steer tools: .gitmodules, .envrc, mise and tool-versions files, .nvim.lua, .nvimrc, .exrc, the VS Code tasks and settings, the whole .cargo directory ("config.toml sets runner / linker / rustflags and runs on the next cargo build"), .vscode as a whole (so tasks.json cannot be swapped by renaming its parent), and .mcp.json. MEMBER_READONLY extends .cargo and .envrc to workspace members up to depth 3, because "cargo reads .cargo/config from every ancestor of the directory it runs in; direnv reads the nearest .envrc". The masks for an absent .cargo and .git are the sharp ones. The comment tells the story of .git: without one the agent ran git init and planted core.fsmonitor = <cmd> in .git/config, which the user’s next unsandboxed git status executed. The price is spelled out too: a later git init needs rmdir .git first. And .claude in the project is always locked or masked, because a planted .claude/settings.local.json with hooks would run on the user’s next claude.'),
    ...sec(r'hiding credentials'),
    ...code('lua', r'lua/config/agent_sandbox.lua · lines 105-145', r'''
-- Hidden (dirs: empty tmpfs, files: bound to /dev/null) when they exist.
-- This is a denylist on a read-only view of the whole filesystem, so it is
-- best effort: anything not listed is still readable, and the network is open.
local HIDDEN = {
...
  "/.claude/daemon", "/.claude/sessions",
  -- every prompt typed in any project (readable, and it was writable too)
  "/.claude/history.jsonl",
}
-- Globs under $HOME (shell and tool histories).
local HIDDEN_GLOBS = { "/.*_history*", "/.lesshst", "/.config/fish/fish_history" }
-- Absolute system paths: container/dbus sockets are root-equivalent (the user
-- is in group docker) or reach other services; /run/user holds the gpg/ssh
-- agent, keyring, wayland and session-bus sockets.
local HIDDEN_SYSTEM = {
  "/run/user/" .. uid,
  "/run/docker.sock", "/run/docker", "/run/containerd", "/run/podman", "/run/libvirt",
  "/run/dbus", "/run/snapd.socket", "/run/snapd-snap.socket",
  -- tailscaled.sock is mode 0666: `tailscale status` listed the peers and RunSSH was on
  "/run/tailscale", "/run/seatd.sock",
}'''),
    ...para('--', r'The comment above HIDDEN is a candid statement about what kind of protection this is: "This is a denylist on a read-only view of the whole filesystem, so it is best effort: anything not listed is still readable, and the network is open." The list covers shell and cloud credentials (.ssh, .gnupg, .aws, .azure, .docker, .kube, tokens and netrc files, cargo credentials), the configuration directories of tools that hold logins (gh, rclone, gcloud, 1Password, Bitwarden and others), browser profiles and mail, keyrings and password stores, and two entries about claude itself: the daemon and sessions directories ("remote-control keys of other claude sessions") and history.jsonl, "every prompt typed in any project (readable, and it was writable too)".'),
    ...para('--', r'HIDDEN_GLOBS covers shell and tool histories by pattern, and HIDDEN_SYSTEM covers absolute paths: the container and dbus sockets are root-equivalent when the user is in the docker group, and /run/user/<uid> holds the gpg and ssh agent, keyring, wayland and session-bus sockets. One entry has its reason in the margin: tailscaled.sock is mode 0666, and "tailscale status listed the peers and RunSSH was on", a field-test discovery that went into the 3f868dd commit ("tailscale" is in its message).'),
    ...sec(r'scrubbing the environment'),
    ...code('lua', r'lua/config/agent_sandbox.lua · lines 147-203', r'''
-- Environment scrub: any variable whose name contains one of these ...
local ENV_CONTAINS = {
  "TOKEN", "SECRET", "PASSWORD", "PASSWD", "API_KEY", "APIKEY", "CREDENTIAL", "PRIVATE_KEY",
  "ACCESS_KEY", "AUTH_SOCK", "AGENT_INFO", "PASSPHRASE", "ASKPASS",
}
-- ... or starts with one of these ...
local ENV_PREFIX = {
  "AWS_", "AZURE_", "GOOGLE_", "GCP_", "GCLOUD_", "DOCKER_", "KUBE", "GH_", "GITHUB_", "GITLAB_",
  "NPM_", "CARGO_REGISTR", "VAULT_", "OPENAI_", "STRIPE_",
}
-- ... or is exactly one of these (session bus / display access).
local ENV_EXACT = {
  DATABASE_URL = true, DBUS_SESSION_BUS_ADDRESS = true, DISPLAY = true, WAYLAND_DISPLAY = true,
  XAUTHORITY = true, SSH_AUTH_SOCK = true, GPG_AGENT_INFO = true, KUBECONFIG = true,
  MYSQL_PWD = true, SSHPASS = true, -- not a "PASSWORD" by name; a bare PWD would also be the cwd
}
-- Variables claude itself authenticates with. Kept only when login is NOT
-- file based (no ~/.claude/.credentials.json); with file-based login claude
-- never reads them, so they are just secrets to strip.
local ENV_CLAUDE_AUTH = { "ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN", "CLAUDE_CODE_OAUTH_TOKEN" }
...
function M.scrub_names(env, file_login)
  env = env or vim.fn.environ()
  if file_login == nil then
    file_login = exists(home .. "/.claude/.credentials.json")
  end
  local keep = {}
  if not file_login then
    for _, v in ipairs(ENV_CLAUDE_AUTH) do
      keep[v] = true
    end
  end
  local out = {}
  for name in pairs(env) do
    local u = name:upper()
    local hit = ENV_EXACT[u] or false
    for _, s in ipairs(ENV_CONTAINS) do
      hit = hit or u:find(s, 1, true) ~= nil
    end
    for _, s in ipairs(ENV_PREFIX) do
      hit = hit or u:sub(1, #s) == s
    end
    if hit and not keep[name] then
      out[#out + 1] = name
    end
  end
  table.sort(out)
  return out
end'''),
    ...para('--', r'Files are one way credentials reach an agent; environment variables are the other, and they are often the more dangerous one because they carry live tokens. scrub_names builds the list of names to unset from the live environment, using three rules: a name that contains a secret-like word (TOKEN, SECRET, PASSWORD, API_KEY, PRIVATE_KEY, AUTH_SOCK and so on), a name that begins with a cloud or service prefix (AWS_, GITHUB_, OPENAI_, KUBE, NPM_ and others, including CARGO_REGISTR as a prefix of the registry-token variables), and an exact list for session bus and display access (DISPLAY, WAYLAND_DISPLAY, SSH_AUTH_SOCK, DATABASE_URL, MYSQL_PWD). A comment on the exact list explains an omission: SSHPASS and MYSQL_PWD are "not a PASSWORD by name; a bare PWD would also be the cwd".'),
    ...para('--', r'There is a subtle exemption, written in the comment on ENV_CLAUDE_AUTH. The variables claude authenticates with are kept only when login is not file based; with a ~/.claude/.credentials.json present, claude never reads them, so they are just secrets to strip. The function takes env and file_login as optional parameters, defaulting to the real environment and the real file, which is what makes it testable (’hits names containing a secret-ish word’, ’keeps the claude auth variables with a non-file login and scrubs them with a file login’). Matching is on the upper-cased name, the result is sorted, and PATH, HOME and LANG are untouched, as one test asserts.'),
    ...sec(r'git directories, including the ones behind a .git file'),
    ...code('lua', r'lua/config/agent_sandbox.lua · lines 241-275', r'''
local SCAN_SKIP = { target = true, node_modules = true, [".git"] = true, [".cache"] = true }

--- Every `.git` (dir or file) in the project and 2 levels below (submodules,
--- nested checkouts) plus the real gitdirs behind `.git` files.
--- @return string[]
local function git_paths(project)
  local out, seen = {}, {}
  local function add(p)
    if not seen[p] and exists(p) then
      seen[p] = true
      out[#out + 1] = p
    end
  end
  local function scan(dir, depth)
    local dotgit = dir .. "/.git"
    local st = vim.uv.fs_stat(dotgit)
    if st then
      if st.type == "file" then
        for _, p in ipairs(resolve_gitfile(dotgit, dir)) do
          add(p)
        end
      end
      add(dotgit)
    end
    if depth < 2 then
      for name, t in vim.fs.dir(dir) do
        if t == "directory" and not SCAN_SKIP[name] then
          scan(dir .. "/" .. name, depth + 1)
        end
      end
    end
  end
  scan(project, 0)
  return out
end'''),
    ...para('--', r'Locking .git read-only is not enough when .git is a file. In a git worktree, a submodule or a bare-repo layout, .git is a text file that says gitdir: <path>, and the real repository, and the shared common directory behind it, live elsewhere. resolve_gitfile reads that line, makes a relative path absolute against the directory that holds the file, takes the real path, and adds the commondir if there is one. It returns nothing for an unreadable file, an empty file, a file without a gitdir line or a gitdir that does not resolve, and accepts an absolute gitdir (the spec has a test with an absolute gitdir, a garbage .git file and a gitdir that does not exist). git_paths then finds every .git in the project and two levels below it, skipping target, node_modules, .git itself and .cache, so submodules and nested checkouts are covered. All of those become read-only binds, so the agent can edit files but cannot commit, a fact one sandbox test checks: "cannot commit: .git is read-only".'),
    ...sec(r'the one project directory that stays writable inside ~/.claude'),
    ...code('lua', r'lua/config/agent_sandbox.lua · lines 277-292', r'''
--- ~/.claude/projects/<name> of this project: claude names it after its cwd
--- (every non-alphanumeric character as "-"), project root and cwd, real and
--- as given. These are the only parts of ~/.claude/projects left writable.
--- @return string[]
local function own_project_dirs(project)
  local cwd = vim.uv.cwd() or project
  local out, seen = {}, {}
  for _, d in ipairs({ project, cwd, vim.uv.fs_realpath(project) or project, vim.uv.fs_realpath(cwd) or cwd }) do
    local dir = home .. "/.claude/projects/" .. d:gsub("[^%w]", "-")
    if not seen[dir] then
      seen[dir] = true
      out[#out + 1] = dir
    end
  end
  return out
end'''),
    ...para('--', r'claude keeps a transcript of each session in ~/.claude/projects/<name>, where the name is the working directory with every non-alphanumeric character replaced by a dash. The agent needs write access to its own transcript directory and to nobody else’s. own_project_dirs computes the name from four spellings (the project root, nvim’s cwd, and the real path of each), de-duplicated. These are the only parts of ~/.claude/projects that are left writable; everything else there is read-only, including other projects’ transcripts and, importantly, their memory directories.'),
    ...sec(r'readonly_paths: assembling the locks'),
    ...code('lua', r'lua/config/agent_sandbox.lua · lines 294-340', r'''
--- Paths re-bound read-only on top of the writable binds.
--- @param project string
--- @return string[] ro, string[] masks  masks: absent dirs to cover with an empty read-only tmpfs
function M.readonly_paths(project)
  local ro = git_paths(project)
  local seen = {}
  for _, p in ipairs(ro) do
    seen[p] = true
  end
  local function lock(p)
    if not seen[p] and exists(p) then
      seen[p] = true
      ro[#ro + 1] = p
    end
  end
  -- Started in $HOME (or /): the project-relative locks would hit ~/.claude and ~/.cargo, the
  -- writable binds claude needs; $HOME is not writable here anyway.
  local at_home = project == home or project == "/"
  for _, rel in ipairs(at_home and {} or PROJECT_READONLY) do
    lock(project .. "/" .. rel)
  end
  local member_masks = {}
  local function scan_members(dir, depth)
    for name, t in vim.fs.dir(dir) do
      if t == "directory" and not SCAN_SKIP[name] and name:sub(1, 1) ~= "." then
        local d = dir .. "/" .. name
        for _, rel in ipairs(MEMBER_READONLY) do
          lock(d .. "/" .. rel)
        end
        if exists(d .. "/Cargo.toml") and not exists(d .. "/.cargo") then
          member_masks[#member_masks + 1] = d .. "/.cargo"
        end
        if depth < 3 then
          scan_members(d, depth + 1)
        end
      end
    end
  end
  if not at_home then
    scan_members(project, 1)
  end
  for _, p in ipairs(HOME_READONLY) do
    lock(p)
  end
  for _, p in ipairs(vim.fn.glob(home .. "/.claude/projects/*/memory", true, true)) do
    lock(p) -- MEMORY.md auto-loads into the next unsandboxed session
  end'''),
    ...para('--', r'This function is the policy compiled. It starts from the git paths, then adds in order: the project-relative read-only files, the member directories’ .cargo and .envrc (found by a depth-limited walk that skips hidden and generated directories), the home read-only list, and every existing ~/.claude/projects/*/memory directory ("MEMORY.md auto-loads into the next unsandboxed session"). It returns two lists: paths to bind read-only, and absent paths to mask. Among the masks: member crates that have a Cargo.toml but no .cargo, this project’s own memory directory even though it does not exist yet (so a MEMORY.md cannot be planted for the next session), the absent project .git, .cargo and .claude, and the absent ~/.claude directories.'),
    ...para('--', r'The at_home flag is a careful special case. When Neovim was started in $HOME or in /, the project-relative locks and masks would hit ~/.claude and ~/.cargo, the very directories claude needs writable, and the home directory is not made writable in that case anyway. So project-relative entries are skipped there, and the spec has two tests about it: "a project that is $HOME gets no project-relative locks or masks" and the variant that keeps the ~/.claude masks.'),
    ...sec(r'status: deciding what kind of run this is'),
    ...code('lua', r'lua/config/agent_sandbox.lua · lines 376-392', r'''
--- How the agent would run here: { mode = "bwrap" } | { mode = "unsandboxed",
--- via = "sandbox=false" | "allow_unsandboxed", reason } | { mode = "refused", reason }.
function M.status()
  if vim.g.xynovim_99_sandbox == false then
    return { mode = "unsandboxed", via = "sandbox=false", reason = "vim.g.xynovim_99_sandbox = false" }
  end
  local linux = vim.fn.has("linux") == 1
  if linux and vim.fn.executable("bwrap") == 1 then
    return { mode = "bwrap" }
  end
  local reason = linux and "bwrap not found (install bubblewrap)"
    or ("no sandbox backend on " .. (vim.uv.os_uname().sysname or "this OS") .. ": bubblewrap exists only on Linux")
  if vim.g.xynovim_99_allow_unsandboxed == true then
    return { mode = "unsandboxed", via = "allow_unsandboxed", reason = reason }
  end
  return { mode = "refused", reason = reason }
end'''),
    ...para('--', r'status() is the small function that makes the fail-closed rule explicit. It returns one of three modes. If the global sandbox is exactly false, the mode is unsandboxed via sandbox=false, whatever the platform. Otherwise, on Linux with bwrap on the path, it is bwrap. Otherwise there is no backend, and the reason says which case it is (bwrap not found, with an install hint, or no backend on this OS because bubblewrap exists only on Linux). Then, only if allow_unsandboxed is exactly true, the mode is unsandboxed via allow_unsandboxed; if not, refused. The platform check uses has("linux") rather than looking for a bwrap binary alone, and the spec pins the consequence: "a platform without bubblewrap (has(linux) == 0, e.g. Windows or macOS) refuses even with a bwrap on PATH". Another spec, tests/agent-failclosed_spec.lua, is written to run on Windows and macOS in the platforms workflow, where the right answer is always "refused".'),
    ...sec(r'wrap, part 1: the fixed isolation flags'),
    ...code('lua', r'lua/config/agent_sandbox.lua · lines 394-434', r'''
--- @param cmd string[] command to wrap
--- @param project string project root (writable)
--- @param tmp_dir string 99's tmp dir (writable)
--- @return string[]? wrapped command (the same table when explicitly unsandboxed); nil when refused
--- @return string? reason
function M.wrap(cmd, project, tmp_dir)
  assert(type(tmp_dir) == "string" and tmp_dir ~= "", "agent_sandbox.wrap: tmp_dir is required")
  local st = M.status()
  if st.mode == "refused" then
    return nil, st.reason
  elseif st.mode == "unsandboxed" then
    return cmd
  end
  -- The ~/.claude/<x> masks need the dir (bwrap cannot mkdir parents on the
  -- read-only root), and a fresh machine has none until claude first runs.
  vim.fn.mkdir(home .. "/.claude", "p")
  local a = {
    "bwrap", "--die-with-parent",
    "--new-session", -- no controlling tty: TIOCSTI keystroke injection
    "--unshare-user", "--disable-userns", -- no nested bwrap / unshare -r
    "--unshare-pid", -- other processes (/proc/PID/environ, /proc/PID/root) invisible
    "--unshare-ipc", "--unshare-uts", "--unshare-cgroup-try",
    "--cap-drop", "ALL",
    "--ro-bind", "/", "/", "--dev", "/dev", "--proc", "/proc", "--tmpfs", "/tmp",
  }

  for _, v in ipairs(M.scrub_names()) do
    vim.list_extend(a, { "--unsetenv", v })
  end

  -- Never make $HOME or / writable just because nvim was started there.
  local rw = { tmp_dir }
  if project ~= home and project ~= "/" then
    table.insert(rw, 1, project)
  end
  vim.list_extend(rw, WRITABLE)
  for _, p in ipairs(rw) do
    if exists(p) then
      vim.list_extend(a, { "--bind", p, p })
    end
  end'''),
    ...para('--', r'wrap asserts that a temp directory was given, asks status, and returns early for the two non-bwrap modes: nil plus the reason when refused, the unchanged command when explicitly unsandboxed. For the sandbox itself, it first creates ~/.claude, since the masks inside it need the directory and bwrap cannot create parents on a read-only root; a fresh machine has none until claude first runs. Then it builds the argument list. The fixed flags are each justified in a comment or by their name: --die-with-parent so the sandbox does not outlive Neovim; --new-session so there is no controlling tty, which blocks TIOCSTI keystroke injection; --unshare-user with --disable-userns so there are no nested bwrap or unshare -r; --unshare-pid so other processes (their environ and root) are invisible; ipc, uts and cgroup (the last with -try); all capabilities dropped; the whole filesystem bound read-only; a fresh /dev and /proc; and an empty tmpfs on /tmp. The environment scrub follows, one --unsetenv per name. The writable set is the project (never $HOME or /, even if Neovim was started there), the tmp directory, and the WRITABLE list, each bound only if it exists.'),
    ...sec(r'wrap, part 2: hiding, the claude.json copy and the transcript directory'),
    ...code('lua', r'lua/config/agent_sandbox.lua · lines 436-484', r'''
  -- After the writable binds: hides inside ~/.claude must sit on top of it.
  -- A hidden file reads as empty: /dev/null bound there gave EACCES (the bind is nodev),
  -- an empty regular file does not.
  local empty
  local function hide(p)
    local st = vim.uv.fs_stat(p)
    if st then
      if st.type ~= "directory" and not empty then
        empty = vim.fn.tempname() .. ".empty"
        vim.fn.writefile({}, empty)
      end
      vim.list_extend(a, st.type == "directory" and { "--tmpfs", p } or { "--ro-bind", empty, p })
    end
  end
  for _, p in ipairs(HIDDEN_SYSTEM) do
    hide(p)
  end
  for _, p in ipairs(HIDDEN) do
    hide(home .. p)
  end
  for _, g in ipairs(HIDDEN_GLOBS) do
    for _, p in ipairs(vim.fn.glob(home .. g, true, true)) do
      hide(p)
    end
  end

  -- ~/.claude.json holds user-scope mcpServers (= commands the next claude
  -- runs unsandboxed). Give the sandbox a private COPY: it works, but nothing
  -- it writes reaches the real file.
  local cj = home .. "/.claude.json"
  if exists(cj) then
    local copy = vim.fn.tempname() .. ".claude.json"
    if vim.uv.fs_copyfile(cj, copy) then
      vim.uv.fs_chmod(copy, tonumber("600", 8))
      vim.list_extend(a, { "--bind", copy, cj })
    end
  end

  -- ~/.claude/projects is read-only except this project's own transcript dir:
  -- a bind mount point cannot be renamed, so `mv projects/<name> ...; mkdir -p
  -- projects/<name>/memory` cannot get round the memory mask (other projects'
  -- transcripts and memory are read-only too).
  local projects = home .. "/.claude/projects"
  vim.fn.mkdir(projects, "p")
  vim.list_extend(a, { "--ro-bind", projects, projects })
  for _, d in ipairs(own_project_dirs(project)) do
    vim.fn.mkdir(d, "p")
    vim.list_extend(a, { "--bind", d, d })
  end'''),
    ...para('--', r'The order of the binds matters in bubblewrap, and the comment says it: the hides come after the writable binds because hides inside ~/.claude must sit on top of them. A hidden directory becomes an empty tmpfs; a hidden file is bound over with an empty regular file. The comment documents a failed first attempt: binding /dev/null there gave EACCES because that bind is nodev, and an empty regular file does not. The empty file is created once, lazily.'),
    ...para('--', r'~/.claude.json gets special treatment because it holds user-scope MCP servers, which are commands the next claude would run unsandboxed. Giving the sandbox a private copy, with mode 0600, bound over the original means claude still works and sees its configuration, but nothing it writes reaches the real file; the spec has three tests (a private 0600 copy bound over it, not bound when the file does not exist, and "a write inside the sandbox hits only the copy"). Then ~/.claude/projects is bound read-only as a whole and only this project’s directories are bound writable on top. The comment gives the reason for the shape: a bind mount point cannot be renamed, so mv projects/<name> followed by mkdir -p projects/<name>/memory cannot be used to get round the memory mask. There is a test named "renaming ~/.claude/projects/<name> cannot be used to plant memory/MEMORY.md" in the group "former known bugs".'),
    ...sec(r'wrap, part 3: locks, masks and the working directory'),
    ...code('lua', r'lua/config/agent_sandbox.lua · lines 486-509', r'''
  local ro, masks = M.readonly_paths(project)
  for _, p in ipairs(ro) do
    vim.list_extend(a, { "--ro-bind", p, p })
  end
  for _, p in ipairs(masks) do
    -- project-relative masks (.cargo, .claude) would hit $HOME's own when the
    -- project is $HOME; the ones inside ~/.claude are safe either way
    if (project ~= home and project ~= "/") or p:find(home .. "/.claude/", 1, true) == 1 then
      vim.list_extend(a, { "--tmpfs", p, "--remount-ro", p })
    end
  end
  for _, p in ipairs(HOME_EPHEMERAL) do
    if exists(p) then
      vim.list_extend(a, { "--tmpfs", p })
    end
  end

  -- nvim's own cwd only when it is inside the project: from $HOME the agent started in $HOME, and
  -- a cwd outside the project (e.g. under /tmp, which is a tmpfs here) made bwrap fail on chdir
  local cwd = vim.uv.cwd()
  local inside = cwd and (cwd == project or project == "/" or cwd:sub(1, #project + 1) == project .. "/")
  vim.list_extend(a, { "--chdir", inside and cwd or project, "--" })
  return vim.list_extend(a, cmd)
end'''),
    ...para('--', r'The last part applies readonly_paths: read-only binds for the locked paths, then for each mask an empty tmpfs remounted read-only. One guard sits in the masks loop: project-relative masks would hit $HOME’s own .cargo and .claude when the project is $HOME, but the ones inside ~/.claude are safe either way. The ephemeral directories, shell-snapshots and session-env (claude sources these before running commands) get a private tmpfs. The final lines choose the working directory. Neovim’s own cwd is used only when it is inside the project; otherwise the agent starts in the project root. The comment gives the field-test reason: a cwd outside the project, for instance under /tmp, which is a tmpfs inside the sandbox, "made bwrap fail on chdir". The wrapped command is the bwrap argument list followed by -- and the original command.'),
    ...sec(r'design decisions and trade-offs'),
    ...pt('--', r'fail closed', r'the default answer on a machine without a sandbox is no, with a reason, and the only ways to get a yes are two named switches with strict boolean checks. Before that commit wrap() returned the command unwrapped whenever bwrap was not executable; the commit changed that case to a refusal (nil plus a reason).'),
    ...pt('--', r'denylist on a read-only view', r'the other design would be an allowlist with an empty root and explicit read binds. That would restrict reads much more tightly, but the file does not say why it was not chosen; the likely cost is that compilers and tools that read system files would need every path listed. That is an inference, not something the repository states. The file states the chosen trade-off in its own comment, and a spec group named README residual-risk claims checks the documented residual risks (’documents the residual risks that cannot be tested mechanically’).'),
    ...pt('--', r'lock the code-like parts of the writable directories', r'the writable holes are where the agent works, so they are also where it can plant things for later. Each lock names the later unsandboxed consumer that it protects.'),
    ...pt('--', r'masks that leave an empty directory', r'the cost of the mask technique is visible: an empty directory is left behind. The comments admit it every time instead of hiding it.'),
    ...pt('--', r'tests that attack', r'the sandbox behaviour tests run real bwrap and try shell rc files, autostart, systemd and cron, symlink tricks, /proc/self/root writes, mount, unshare, nested bwrap, TIOCSTI, and reading ~/.ssh and the docker socket.'),
    ...sec(r'the same module in xyno-sandbox.nvim'),
    ...para('--', r'On 2026-10-22 the module was extracted as lua/xyno_sandbox/init.lua in xyno-sandbox.nvim. The wrapping logic is the same, and a diff shows where it differs. The header is rewritten for any command-line coding agent ("Runs a command-line coding agent inside bubblewrap") instead of naming 99 and claude. The two policy switches move from globals to an options table: M.config = { sandbox = true, allow_unsandboxed = false, keymaps = false, commands = true } merged by M.setup(opts), with the same strict boolean reading; the status text says "sandbox = false" instead of the global name. The assertion message is renamed. And the plugin adds what the config does not have in this file: M.setup, M.run, and a run.lua module that defines :XynoSandboxStatus and :XynoSandboxRun, picks a default scratch directory, refuses with a hint ("Set allow_unsandboxed = true in setup() to run it anyway"), warns on every unsandboxed run and starts the wrapped command in a terminal split. In this config the integration is in plugins/ninety-nine.lua instead: it calls wrap() from the provider’s build-command function and errors with "99 sandbox: <reason>" if it returns nil, and make_request checks status() first and fails before anything starts (no snapshot, no auto-save toggle, no process).'),
    ...sec(r'how it is tested'),
    ...para('--', r'Three specs. tests/agent-sandbox_spec.lua (59 tests, Linux only) covers the opt-out rules, the layout of the wrapped command (fixed flags first, --chdir and the command last), scrub_names, the environment scrub in the wrapper, hidden credentials (including tests that really run inside the sandbox and look for empty directories), the ~/.claude.json copy, readonly_paths, the sandbox behaviour with escape attempts, the project memory directory, former known bugs, the network ("reaches loopback listeners (documented residual)"), a headless skip when bwrap or user namespaces are unavailable, and README residual-risk claims. tests/agent-failclosed_spec.lua (5 tests) runs on every platform and checks that the answer without a backend is refused. tests/agent-99-guard_spec.lua (57 tests including skips in a local run) is the third spec file with agent in its name; its cases are about the 99 integration and are not covered here.'),
    ...sec(r'what the sandbox does not promise'),
    ...para('--', r'Taken from the file’s own comments and the spec: HIDDEN is a denylist, so anything not listed stays readable; the network is open, and the network spec records that loopback listeners are reachable (a documented residual); a sandboxed agent can still edit anything in the project except the locked paths, and the locks only cover what the lists name. The fail-closed rule decides whether the agent starts; once started under bwrap, the guarantees are limited to these lists and flags. Nothing here is a claim of complete containment.'),
    ...sec(r'history'),
    ...pt('--', r'625b48d and 60cebad · 2026-10-09', r'wip-s5c, then Roadmap step 5: local history snapshots, undotree key, guarded + sandboxed 99.'),
    ...pt('--', r'ac38272 · 2026-10-09', r'Fix review findings: sandbox hardening, local history, 99 guard.'),
    ...pt('--', r'0494b52 and c4f2ace · 2026-10-12', r'Field test fixes and a second hardening pass: dir-level locks, absent-path masks, member crates.'),
    ...pt('--', r'b65284f · 2026-10-13', r'Batch 3: data safety, with the sandbox memory directory.'),
    ...pt('--', r'98c9bb4, a3d33c8, 3f868dd · 2026-10-13', r'Final loop rounds 1 to 3: the 99 sandbox security directory and projects rename, checkpoint before agent start, and the .git mask, tailscale, secrets, empty files and home project.'),
    ...pt('--', r'25086fd · 2026-10-14', r'Final loop round 5: sandbox chdir.'),
    ...pt('--', r'440d781 · 2026-10-16', r'Agent sandbox fails closed when no sandbox backend is available.'),
  ],
);
