import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-sandbox.nvim/lua/xyno_sandbox/init.lua',
  lines: [
    cm('--', r'──────────────────────────────────────────'),
    cm('--', r'init.lua — build a bubblewrap command line, or refuse'),
    cm('--', r'a read-only view of the machine with a few writable holes and a long denylist'),
    cm('--', r'──────────────────────────────────────────'),
    kv(r'role', r'policy and command builder: status(), wrap(), scrub_names(), readonly_paths(), setup()'),
    kv(r'language', r'Lua (Neovim 0.12+); the output is a bwrap argument vector, nothing is executed here'),
    kv(r'size', r'532 lines'),
    kv(r'platform', r'Linux with bwrap; everywhere else wrap() refuses'),
    kv(r'history', r'403b9b0 (2026-10-22), extracted from xynovim lua/config/agent_sandbox.lua'),
    ...sec(r'why this file exists'),
    ...para('--', r'A command-line coding agent run without permission prompts has all of your privileges. '
        r'The README states the author’s reaction in one sentence: they did not want that from '
        r'inside their editor, so they wrap it. This file is the wrapper. It does not start '
        r'anything. It turns a command, a project directory and a scratch directory into a longer '
        r'command that starts with bwrap and a long list of flags, or it returns nil and a reason. The '
        r'header of the file is the design brief.'),
    ...code('lua', r'lua/xyno_sandbox/init.lua · lines 1-9', r'''
-- Runs a command-line coding agent inside bubblewrap. The whole filesystem is
-- read-only except the project, a scratch dir, and the few paths the agent and
-- cargo must write.
-- Everything that would later run UNSANDBOXED (git hooks/config, agent
-- settings/hooks/plugins, direnv, editor task files, cargo config, the agent
-- binary) is read-only even inside the writable binds. Credential dirs/files
-- are hidden, credential env vars are stripped, pid/ipc/uts namespaces are
-- unshared, capabilities dropped, nested user namespaces disabled.
-- Network stays open (the model needs it).
'''),
    ...para('--', r'Security-sensitive code deserves a precise reading, so this page separates three things: '
        r'what the code does, what it does not do, and what the repository itself claims. The '
        r'repository is candid about the limits (it calls the result a denylist on a read-only '
        r'view, not a security boundary against a determined attacker), and this page stays inside '
        r'the same limits.'),
    ...sec(r'the origin in xynovim'),
    ...para('--', r'The module began as lua/config/agent_sandbox.lua in xynovim, where the agent was the 99 '
        r'plugin. The history of that file in xynovim reads as a sequence of hardening passes: the '
        r'first version arrived on 2026-10-09 (625b48d, 60cebad), ac38272 and 0494b52 added review '
        r'findings and field-test fixes, c4f2ace on 2026-10-12 was a second hardening pass with '
        r'directory-level locks, absent-path masks and workspace members, b65284f added a memory '
        r'directory, 98c9bb4 the security directory and a rename of the projects directory '
        r'handling, 3f868dd the .git mask, tailscale, secrets and empty files, 25086fd a chdir fix, '
        r'and 440d781 on 2026-10-16 made it fail closed when no sandbox backend exists. In the '
        r'extraction, 79bcfa5 rewrote the README and help text to describe the agent generically (it did not change this file), and '
        r'the README has a table that maps the xynovim option variables to the setup options.'),
    ...sec(r'the policy switches'),
    ...code('lua', r'lua/xyno_sandbox/init.lua · lines 11-29', r'''
-- Fails CLOSED. bubblewrap exists only on Linux, so without a working
-- backend (Windows, macOS, Linux without bwrap) wrap() refuses (nil, reason)
-- and the agent does not start. Two explicit booleans (0, "false", 1 do
-- not count) lead to an unsandboxed run:
--   setup({ sandbox = false })             deliberate OFF, even where bwrap works
--   setup({ allow_unsandboxed = true })    run anyway when NO backend exists
--                                          (never disables a working sandbox)
-- Linux+bwrap: sandboxed (only sandbox=false turns it off). No backend:
-- refused (sandbox=false or allow_unsandboxed=true: unsandboxed).
local M = {}

--- Policy switches. Read at every status()/wrap() call; only the booleans
--- `false` / `true` count (0, "false", 1, "true" do not).
M.config = {
  sandbox = true, -- false: deliberate opt-out, run unsandboxed even where bwrap works
  allow_unsandboxed = false, -- true: run unsandboxed when NO backend exists
  keymaps = false, -- false, or { status = "<lhs>" }
  commands = true,
}
'''),
    ...para('--', r'The header fixes the semantics of two booleans, and the code is written to match. '
        r'M.config is read on every status() and wrap() call, so the policy can change at run time. '
        r'Only the booleans false and true count; a string "false" or the number 0 never opts out. '
        r'The comparison further down is a strict equality with false for sandbox and with true for '
        r'allow_unsandboxed, which is the whole implementation of that sentence. The consequence is '
        r'the safe direction: a mistyped option leaves the sandbox on.'),
    ...sec(r'what is writable'),
    ...code('lua', r'lua/xyno_sandbox/init.lua · lines 31-45', r'''
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
'''),
    ...para('--', r'home is read once when the module loads, which is why the spec reloads the module for '
        r'each fake home. WRITABLE lists the places the agent and cargo must be able to write: the '
        r'agent’s state directories under .claude, its cache and state, and cargo’s registry, git '
        r'checkouts and the lock files of its package cache. The comment records the deliberate '
        r'omissions: the agent binary under .local/share, cargo’s bin directory and cargo’s config '
        r'file are not writable, since replacing them would run planted code later, outside the '
        r'sandbox. A path that does not exist is not bound at all.'),
    ...sec(r'what is locked even inside the writable binds'),
    ...code('lua', r'lua/xyno_sandbox/init.lua · lines 47-64', r'''
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
}
'''),
    ...para('--', r'This is the core idea of the module, stated in a comment: whatever the agent plants in '
        r'these places would run, or steer a tool, outside the sandbox later. So inside the '
        r'writable ~/.claude, the settings, hooks, commands, agents, skills, plugins, output '
        r'styles, IDE lock files, rules, chrome and security directories are bound back read-only. '
        r'Several lines carry the reason in a comment: the IDE lock files make the agent connect to '
        r'a local server, chrome-native-host is a shell script Chrome launches unsandboxed, and the '
        r'security directory holds a hook that imports from a Python environment, unsandboxed. '
        r'These comments are the field-test findings of the xynovim history.'),
    ...code('lua', r'lua/xyno_sandbox/init.lua · lines 66-69,79-83', r'''
-- Same dirs, but when ABSENT the agent could create them (a later unsandboxed
-- claude would load them: prompt injection), so mask them with an empty
-- read-only dir (leaves one empty dir behind in ~/.claude).
local HOME_MASK_IF_ABSENT = {
...
-- Ephemeral inside the sandbox: claude sources these before running commands.
local HOME_EPHEMERAL = {
  home .. "/.claude/shell-snapshots",
  home .. "/.claude/session-env",
}
'''),
    ...para('--', r'Read-only locks only help for things that exist. If one of these directories is absent, '
        r'the agent could create it, and a later unsandboxed run would load it as a prompt '
        r'injection. So the absent ones are masked: an empty read-only directory is mounted over '
        r'the path, and the comment admits the side effect, one empty directory left behind. The '
        r'ephemeral list is the opposite: shell snapshots and session environments are given a '
        r'private tmpfs, because the agent sources those files before running commands.'),
    ...code('lua', r'lua/xyno_sandbox/init.lua · lines 85-99,105-112', r'''
-- Project-relative auto-executing / tool-steering files (locked when present).
local PROJECT_READONLY = {
  ".gitmodules",
  ".envrc",
  ".mise.toml",
  ".tool-versions",
  ".nvim.lua",
  ".nvimrc",
  ".exrc",
  ".vscode/tasks.json",
  ".vscode/settings.json",
  ".cargo", -- whole dir: config.toml sets runner / linker / rustflags and runs on the next cargo build
  ".vscode", -- whole dir, so tasks.json cannot be swapped by renaming the parent
  ".mcp.json",
}
...
-- .git too: without one the agent ran `git init` and planted `core.fsmonitor = <cmd>` in
-- .git/config, which the user's next unsandboxed `git status` executed. (A later `git init`
-- needs `rmdir .git` first: the mask leaves an empty dir behind.)
local PROJECT_MASK_IF_ABSENT = { ".cargo", ".git" }
-- Project dir that is ALWAYS locked: read-only when present, otherwise masked
-- with an empty read-only dir (leaves one empty dir behind), because a planted
-- .claude/settings.local.json with hooks would run on the user's next claude.
local PROJECT_MASKED = ".claude"
'''),
    ...para('--', r'The same logic is applied to the project. Files that execute automatically or steer tools '
        r'(.gitmodules, .envrc, mise and tool-version files, editor task files, the vscode '
        r'directory, .cargo as a whole directory, .mcp.json) are locked when present. Members of a '
        r'workspace get .cargo and .envrc locked up to depth 3, because cargo reads .cargo/config '
        r'from every ancestor of the directory it runs in. At the project root, .cargo and .git are '
        r'created empty-and-read-only when absent. The comment on .git is the most vivid piece of '
        r'evidence in the file: without one the agent ran git init and planted core.fsmonitor in '
        r'.git/config, which the user’s next unsandboxed git status executed. The project .claude '
        r'directory is always locked, read-only when present and masked when absent, because a '
        r'planted settings.local.json with hooks would run on the user’s next agent start.'),
    ...para('--', r'Note the exact wording of what is locked: present files, and the few masked-when-absent '
        r'directories. A file such as .envrc that does not exist is not masked, and the README '
        r'lists that under residual risks.'),
    ...sec(r'what is hidden'),
    ...code('lua', r'lua/xyno_sandbox/init.lua · lines 114-119,138-154', r'''
-- Hidden (dirs: empty tmpfs, files: bound to /dev/null) when they exist.
-- This is a denylist on a read-only view of the whole filesystem, so it is
-- best effort: anything not listed is still readable, and the network is open.
local HIDDEN = {
  -- shell/CLI credentials
  "/.ssh", "/.gnupg", "/.aws", "/.azure", "/.gsutil", "/.boto", "/.docker", "/.kube",
...
  -- remote-control keys of other claude sessions / the claude daemon
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
}
'''),
    ...para('--', r'The hidden list is a denylist, and the comment on top says so in plain words: it is best '
        r'effort, anything not listed is still readable, and the network is open. Directories are '
        r'replaced with an empty tmpfs and files with an empty file. The entries are grouped by '
        r'what they protect: shell and CLI credentials, application secrets under .config, browser '
        r'profiles and mail, keyrings and password stores, other agent sessions and the history '
        r'file of every prompt. Globs cover shell and tool histories. The system list matters for a '
        r'different reason: the container and D-Bus sockets are root-equivalent when the user is in '
        r'a group such as docker, and /run/user/UID holds the gpg and ssh agent, the keyring, the '
        r'Wayland and the session bus sockets. The tailscale entry carries its own story in a '
        r'comment: its socket is mode 0666, tailscale status listed the peers and RunSSH was on.'),
    ...sec(r'the environment scrub'),
    ...code('lua', r'lua/xyno_sandbox/init.lua · lines 156-175', r'''
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
'''),
    ...para('--', r'Environment variables are stripped by name, and the three matching rules are visible: '
        r'names containing a secret-looking word, names that start with a known prefix, and an '
        r'exact list that includes the session bus and display variables and SSH_AUTH_SOCK. The '
        r'agent’s own authentication variables are special. They are kept only when the login is '
        r'not file based, because with a login file the agent never reads them and they are simply '
        r'secrets to strip.'),
    ...code('lua', r'lua/xyno_sandbox/init.lua · lines 181-212', r'''
--- Names to `--unsetenv`, computed from the live environment.
--- @param env? table<string,string> defaults to vim.fn.environ()
--- @param file_login? boolean defaults to: ~/.claude/.credentials.json exists
--- @return string[]
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
end
'''),
    ...para('--', r'scrub_names computes the list from the live environment, so only variables that actually '
        r'exist produce a flag. The matching is case-insensitive (the name is upper-cased), the '
        r'output is sorted so the command line is deterministic, and the optional arguments exist '
        r'for testing: the spec passes a fake environment and forces file_login either way. This is '
        r'a denylist of names. A secret in a variable called, say, MY_CREDS does not match any rule '
        r'and is passed through; the code makes no attempt to start from an empty environment.'),
    ...sec(r'finding the real git directories'),
    ...code('lua', r'lua/xyno_sandbox/init.lua · lines 214-248', r'''
--- Real gitdir (and shared commondir) behind a `.git` FILE ("gitdir: ..." of
--- worktrees, submodules and bare-repo layouts).
local function resolve_gitfile(dotgit, dir)
  local out = {}
  local f = io.open(dotgit, "r")
  if not f then
    return out
  end
  local line = f:read("l") or ""
  f:close()
  local gd = line:match("^gitdir:%s*(.-)%s*$")
  if not gd or gd == "" then
    return out
  end
  if not gd:match("^/") then
    gd = dir .. "/" .. gd
  end
  gd = vim.uv.fs_realpath(gd)
  if not gd then
    return out
  end
  out[#out + 1] = gd
  local cf = io.open(gd .. "/commondir", "r")
  if cf then
    local cd = cf:read("l")
    cf:close()
    if cd and cd ~= "" then
      cd = vim.uv.fs_realpath(cd:match("^/") and cd or (gd .. "/" .. cd))
      if cd then
        out[#out + 1] = cd
      end
    end
  end
  return out
end
'''),
    ...para('--', r'A .git file instead of a directory is how worktrees, submodules and some bare layouts '
        r'point at the real gitdir. resolve_gitfile reads the first line, accepts a gitdir: prefix, '
        r'resolves a relative path against the directory, takes the real path, and also follows the '
        r'commondir file, since a worktree’s hooks and config live in the shared directory. '
        r'Anything unreadable or empty gives an empty list instead of an error. The point of '
        r'resolving these is that locking the .git file alone would leave the real hooks directory '
        r'writable.'),
    ...code('lua', r'lua/xyno_sandbox/init.lua · lines 250-284', r'''
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
end
'''),
    ...para('--', r'git_paths scans the project and two levels below for .git entries, skipping target, '
        r'node_modules, .git and .cache. The README states the limit that follows: a nested .git '
        r'deeper than two levels is not locked.'),
    ...sec(r'the agent’s own transcript directory'),
    ...code('lua', r'lua/xyno_sandbox/init.lua · lines 290-300', r'''
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
'''),
    ...para('--', r'The agent names its project directory after the working directory with every '
        r'non-alphanumeric character turned into a dash. The function computes that name for the '
        r'project and for the current directory, each as given and resolved through realpath, '
        r'because the agent may see either. These directories are the only parts of '
        r'~/.claude/projects left writable, which matters for the memory directory logic below.'),
    ...sec(r'readonly_paths'),
    ...code('lua', r'lua/xyno_sandbox/init.lua · lines 303-323', r'''
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
'''),
    ...para('--', r'The function returns two lists: paths to re-bind read-only and absent paths to mask. When '
        r'the project is the home directory or the root, the project-relative locks are skipped '
        r'entirely: they would hit ~/.claude and ~/.cargo, the very binds the agent needs, and home '
        r'is not writable in that mode anyway.'),
    ...code('lua', r'lua/xyno_sandbox/init.lua · lines 341-349', r'''
  if not at_home then
    scan_members(project, 1)
  end
  for _, p in ipairs(HOME_READONLY) do
    lock(p)
  end
  for _, p in ipairs(vim.fn.glob(home .. "/.claude/projects/*/memory", true, true)) do
    lock(p) -- MEMORY.md auto-loads into the next unsandboxed session
  end
'''),
    ...code('lua', r'lua/xyno_sandbox/init.lua · lines 350-376', r'''
  -- Absent dirs to mask with an empty read-only tmpfs.
  local masks = member_masks
  -- This project's own memory dir, also while it does not exist yet (claude
  -- names it ~/.claude/projects/<path with every non-alphanumeric as "-">/memory
  -- from its cwd): otherwise the agent could plant a MEMORY.md that the next
  -- unsandboxed session loads. Needs ~/.claude (the mask is made inside it).
  if exists(home .. "/.claude") then
    for _, d in ipairs(own_project_dirs(project)) do
      local mem = d .. "/memory"
      if not seen[mem] and not exists(mem) then
        seen[mem] = true
        masks[#masks + 1] = mem
      end
    end
  end
  for _, rel in ipairs(at_home and {} or PROJECT_MASK_IF_ABSENT) do
    if not exists(project .. "/" .. rel) then
      masks[#masks + 1] = project .. "/" .. rel
    end
  end
  if at_home then
    -- (~/.claude is writable here: HOME_READONLY locks what must not change)
  elseif not exists(project .. "/" .. PROJECT_MASKED) then
    masks[#masks + 1] = project .. "/" .. PROJECT_MASKED
  else
    lock(project .. "/" .. PROJECT_MASKED)
  end
'''),
    ...para('--', r'Memory directories get special attention, because a MEMORY.md in the agent’s project '
        r'directory is loaded automatically by the next unsandboxed session. Existing ones are '
        r'locked, and this project’s own memory directory is masked while it does not exist yet, so '
        r'that it cannot be created and planted.'),
    ...sec(r'status: the fail-closed decision'),
    ...code('lua', r'lua/xyno_sandbox/init.lua · lines 385-401', r'''
--- How the agent would run here: { mode = "bwrap" } | { mode = "unsandboxed",
--- via = "sandbox=false" | "allow_unsandboxed", reason } | { mode = "refused", reason }.
function M.status()
  if M.config.sandbox == false then
    return { mode = "unsandboxed", via = "sandbox=false", reason = "sandbox = false" }
  end
  local linux = vim.fn.has("linux") == 1
  if linux and vim.fn.executable("bwrap") == 1 then
    return { mode = "bwrap" }
  end
  local reason = linux and "bwrap not found (install bubblewrap)"
    or ("no sandbox backend on " .. (vim.uv.os_uname().sysname or "this OS") .. ": bubblewrap exists only on Linux")
  if M.config.allow_unsandboxed == true then
    return { mode = "unsandboxed", via = "allow_unsandboxed", reason = reason }
  end
  return { mode = "refused", reason = reason }
end
'''),
    ...para('--', r'This 15-line function is the part of the file to read twice. If sandbox is exactly false '
        r'the mode is unsandboxed and the reason is the option. Otherwise, on Linux with a bwrap '
        r'executable, the mode is bwrap. Anything else builds a reason, either bwrap not found or '
        r'no backend on this system name, and the result is refused, unless allow_unsandboxed is '
        r'exactly true, in which case the result is unsandboxed via that option. Notice what is not '
        r'in the function: no attempt to run bwrap. Presence on the path is the test. If bwrap '
        r'exists but user namespaces are disabled, status says bwrap, the wrapped command is built, '
        r'and bwrap then fails when it starts; since the agent is the wrapped command, the failure '
        r'leaves the agent not running, so the outcome is still closed, but the one-line status '
        r'would have said sandboxed. The test helper sandbox_available checks this case by actually '
        r'running a wrapped true, which is how the suite skips on machines that restrict user '
        r'namespaces.'),
    ...sec(r'wrap: the command line'),
    ...code('lua', r'lua/xyno_sandbox/init.lua · lines 408-427', r'''
function M.wrap(cmd, project, tmp_dir)
  assert(type(tmp_dir) == "string" and tmp_dir ~= "", "xyno_sandbox.wrap: tmp_dir is required")
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
'''),
    ...para('--', r'The checks come first: tmp_dir is required, refused returns nil and the reason, and '
        r'unsandboxed returns the same table that was given. Only then does the real work start. '
        r'The bwrap options in the first block are the isolation floor. They are in a fixed order '
        r'that the layout spec asserts as a prefix:'),
    ...pt('--', r'--die-with-parent', r'the sandboxed process dies when Neovim does.'),
    ...pt('--', r'--new-session', r'no controlling terminal, which the comment ties to TIOCSTI keystroke injection. The spec '
        r'checks that opening /dev/tty fails inside.'),
    ...pt('--', r'--unshare-user and --disable-userns', r'no nested user namespaces, so no nested bwrap or unshare -r. The spec tries unshare and '
        r'bwrap inside and expects both to fail.'),
    ...pt('--', r'--unshare-pid', r'other processes are invisible, including /proc/PID/environ and /proc/PID/root. The spec '
        r'expects at most 12 pids in /proc.'),
    ...pt('--', r'--unshare-ipc, --unshare-uts and --unshare-cgroup-try', r'private IPC and hostname, and a private cgroup view where the kernel allows it (the try '
        r'form does not fail where it cannot).'),
    ...pt('--', r'--cap-drop ALL', r'no capabilities.'),
    ...pt('--', r'--ro-bind / /', r'the whole filesystem, read-only.'),
    ...pt('--', r'--dev, --proc, --tmpfs /tmp', r'private device nodes, a fresh proc, and a private /tmp. Whatever is in the host /tmp, '
        r'including X11 sockets, is not visible.'),
    ...para('--', r'There is no --unshare-net, because the model needs the network, and there is no '
        r'--clearenv or seccomp filter in this file. The spec for the network states the '
        r'consequence explicitly: loopback services are reachable, because the network namespace is '
        r'shared.'),
    ...code('lua', r'lua/xyno_sandbox/init.lua · lines 429-443', r'''
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
  end
'''),
    ...para('--', r'Unsetting variables comes next, then the writable binds. The writable list is the '
        r'project, then the scratch directory, then the fixed paths, each bound only if it exists. '
        r'If the project is the home directory or the root, it is not made writable, so starting '
        r'Neovim in $HOME does not give the agent a writable home. The spec checks that neither is '
        r'ever bound as the project.'),
    ...code('lua', r'lua/xyno_sandbox/init.lua · lines 445-469', r'''
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
'''),
    ...para('--', r'The order matters in bwrap, since later mounts sit on top of earlier ones: the hides come '
        r'after the writable binds so that a hide inside ~/.claude wins. The comment records a bug: '
        r'binding /dev/null over a hidden file gave EACCES because the bind is nodev, and an empty '
        r'regular file does not, so one temporary empty file is created and reused for all hidden '
        r'files. A hidden directory becomes an empty tmpfs. The spec confirms that a hidden '
        r'credential directory reads as empty and a hidden file reads as empty, not as missing.'),
    ...code('lua', r'lua/xyno_sandbox/init.lua · lines 471-481', r'''
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
'''),
    ...para('--', r'The agent’s user-level configuration file in home also holds the definitions of MCP '
        r'servers, which are commands that the next agent run would execute unsandboxed. The '
        r'sandbox is therefore given a private copy with mode 0600 bound over it. The agent works '
        r'normally, and anything it writes there is discarded. The spec checks that a write inside '
        r'hits only the copy. Note what this does not do: the copy is readable by the agent, with '
        r'whatever the real file contains.'),
    ...code('lua', r'lua/xyno_sandbox/init.lua · lines 483-505', r'''
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
  end

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
'''),
    ...para('--', r'The projects directory in ~/.claude is bound read-only as a whole, and the agent’s own '
        r'transcript directories are bound writable on top. The comment explains why this shape: a '
        r'bind mount point cannot be renamed, so a sequence such as moving the directory away and '
        r'creating a new one with a memory subdirectory cannot get around the memory mask. The spec '
        r'has a test for exactly that rename trick, listed under former known bugs. Then the '
        r'read-only locks and the masks are applied, with the masks restricted when the project is '
        r'home or the root.'),
    ...code('lua', r'lua/xyno_sandbox/init.lua · lines 512-517', r'''
  -- nvim's own cwd only when it is inside the project: from $HOME the agent started in $HOME, and
  -- a cwd outside the project (e.g. under /tmp, which is a tmpfs here) made bwrap fail on chdir
  local cwd = vim.uv.cwd()
  local inside = cwd and (cwd == project or project == "/" or cwd:sub(1, #project + 1) == project .. "/")
  vim.list_extend(a, { "--chdir", inside and cwd or project, "--" })
  return vim.list_extend(a, cmd)
'''),
    ...para('--', r'The last block chooses the working directory. It is Neovim’s own cwd if that lies inside '
        r'the project (a prefix check that includes the trailing slash, so a sibling directory '
        r'whose name starts with the project name does not count), otherwise the project root. The '
        r'comment says a cwd outside the project, for example under /tmp, which is a tmpfs inside '
        r'the sandbox, made bwrap fail at chdir. The command follows after the double dash.'),
    ...sec(r'setup and the thin public surface'),
    ...code('lua', r'lua/xyno_sandbox/init.lua · lines 520-531', r'''
--- Merge options and register the commands / keymaps.
--- @param opts? { sandbox?: boolean, allow_unsandboxed?: boolean, keymaps?: false|table, commands?: boolean }
function M.setup(opts)
  M.config = vim.tbl_extend("force", M.config, opts or {})
  require("xyno_sandbox.run").register(M.config)
end

--- Run `cmd` wrapped in a terminal split (see xyno_sandbox.run).
function M.run(cmd, opts)
  return require("xyno_sandbox.run").run(cmd, opts)
end

'''),
    ...para('--', r'setup merges the options with a shallow extend and registers the commands and the keymap '
        r'through run.lua; run is a forwarding function. The module stays free of UI.'),
    ...sec(r'what the code does and does not guarantee'),
    ...pt('--', r'It guarantees', r'that with sandbox at its default and bwrap on the path, the agent is started through a '
        r'command line that begins with bwrap and the flags above; that without bwrap, or on a '
        r'platform that is not Linux, nothing starts unless one of two strict booleans says so; and '
        r'that each explicitly unsandboxed run through run.lua warns.'),
    ...pt('--', r'It does not guarantee', r'that the filesystem outside the denylist is private (everything unlisted is readable), '
        r'that the network is closed (it is open), that loopback services are unreachable, that a '
        r'file the project lacks cannot be created, or that bwrap can actually create a namespace '
        r'on this machine.'),
    ...pt('--', r'Its own words', r'a denylist on a read-only view of the whole filesystem, with the network open, and not a '
        r'security boundary against a determined attacker. The README lists seven residual risks '
        r'and the spec checks that four of them stay documented.'),
    ...sec(r'tested by'),
    ...para('--', r'tests/sandbox_spec.lua builds the command against a fake home and also runs real commands '
        r'in a real sandbox; tests/failclosed_spec.lua pins the refusal without an OS gate (CI runs only on Linux); '
        r'tests/setup_spec.lua covers the surface in run.lua. See those pages.'),
    ...sec(r'history'),
    ...pt('--', r'403b9b0', r'2026-10-22: the module is added with the specs, the smoke test and the CI in the same '
        r'series (03b99f2).'),
    ...pt('--', r'79bcfa5', r'2026-10-22: the README and help text describe the agent generically; also pins lazy.nvim in CI and ports the fail-closed spec.'),
  ],
);
