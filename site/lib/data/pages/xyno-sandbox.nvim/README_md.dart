import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-sandbox.nvim/README.md',
  summary: r'Runs a CLI coding agent inside bubblewrap and refuses to start it without a sandbox',
  repo: 'xyno-sandbox.nvim',
  fallbackStars: 0,
  fallbackPushed: '2026-10-22',
  lines: [
    heading(r'# xyno-sandbox.nvim'),
    blank,
    ...text(r'A Neovim plugin that runs a command-line coding agent inside a bubblewrap sandbox and '
        r'refuses to start it without one. Linux only. The filesystem becomes read-only except the '
        r'project and a scratch directory, credential directories are hidden, secret-looking '
        r'environment variables are stripped, and anything that would later run outside the sandbox '
        r'(git hooks, editor task files, direnv, cargo config, the agent’s own settings) is locked. '
        r'Where no sandbox can be created, the agent does not start. That fail-closed default is '
        r'the point.'),
    kv(r'language', r'Lua, Neovim 0.12+'),
    kv(r'platform', r'Linux with bwrap and unprivileged user namespaces'),
    kv(r'size', r'2 modules (532 + 69 lines), 59 sandbox specs and 14 more'),
    kv(r'history', r'5 commits, all on 2026-10-22; the module began on 2026-10-09 in xynovim'),
    kv(r'origin', r'extracted from xynovim, lua/config/agent_sandbox.lua'),
    kv(r'honest about', r'a denylist, not a security boundary against a determined attacker; the network is open'),
    ...sec(r'the problem'),
    ...text(r'Command-line coding agents that run without permission prompts have all of your '
        r'privileges: your SSH keys, your cloud credentials, your shell startup files. The author '
        r'did not want that from inside their editor, so they wrap the agent. The README’s one-line '
        r'summary of the answer: the filesystem is read-only except the project and a scratch '
        r'directory, credentials are hidden, secret environment variables are stripped, and '
        r'anything that would later run outside the sandbox is locked read-only.'),
    ...sec(r'the idea'),
    ...text(r'Make the dangerous thing structurally hard instead of asking the agent to behave. A '
        r'single function, wrap(cmd, project, tmp_dir), prefixes the command with bwrap and a long '
        r'list of flags: a read-only bind of the whole filesystem, a private /dev, /proc and /tmp, '
        r'new user, pid, ipc, uts and cgroup namespaces, no nested user namespaces, no '
        r'capabilities, no controlling terminal. Then it layers the policy on top: writable holes '
        r'for the project, the scratch directory and a few cache paths; read-only re-binds for '
        r'everything an agent could plant to attack its future self; empty replacements for '
        r'credentials. And a status function with two strict booleans decides whether any of this '
        r'happens at all.'),
    ...sec(r'the part that matters most: failing closed'),
    ...code('markdown', r'README.md · lines 7-7', r'''
Command-line coding agents that run without permission prompts have all of your privileges. I did not want that from inside my editor, so I wrap them: the filesystem is read-only except the project and a scratch directory, credentials are hidden, secret environment variables are stripped, and anything that would later run outside the sandbox (git hooks, editor task files, direnv, cargo config, the agent's own settings) is locked read-only. Where no sandbox can be created, the agent does not start. That fail-closed default is the point of the plugin.
'''),
    ...text(r'status() has three outcomes. With Linux and bwrap on PATH the answer is bwrap, and only '
        r'sandbox = false turns it off. With no backend (Windows, macOS, Linux without bwrap) the '
        r'answer is refused and wrap() returns nil and a reason. With no backend and '
        r'allow_unsandboxed = true, or with sandbox = false anywhere, the answer is unsandboxed, '
        r'and :XynoSandboxRun warns on every such run. The values must be the exact booleans: 0, 1, '
        r'the string false and the string true do nothing. A mistake in the configuration therefore '
        r'leaves the sandbox on, or the agent unstarted, and never the reverse.'),
    ...code('markdown', r'README.md · lines 44-53', r'''
Only the booleans `false` and `true` count. `0`, `1`, `"false"` and `"true"` do not opt out.

| Situation | Result |
| --- | --- |
| Linux with `bwrap` | sandboxed (only `sandbox = false` turns it off) |
| No backend (Windows, macOS, Linux without `bwrap`) | refused: `wrap()` returns `nil, reason` |
| No backend and `allow_unsandboxed = true` | runs unsandboxed |
| `sandbox = false` anywhere | runs unsandboxed |

Every explicitly unsandboxed run through `:XynoSandboxRun` or `run()` warns.
'''),
    ...sec(r'the shape of the repository'),
    plain(r'xyno-sandbox.nvim/'),
    plain(r'├── lua/xyno_sandbox/'),
    plain(r'│   ├── init.lua                 policy, scrub list, locks, hides, status(), wrap()'),
    plain(r'│   └── run.lua                  terminal launcher, :XynoSandboxStatus, :XynoSandboxRun'),
    plain(r'├── tests/'),
    plain(r'│   ├── sandbox_spec.lua         59 tests: the command line, then real escape attempts'),
    plain(r'│   ├── failclosed_spec.lua      the refusal, written without an OS gate'),
    plain(r'│   ├── setup_spec.lua           options, commands, keymap, run()'),
    plain(r'│   ├── e2e/smoke.lua            lazy.nvim loads it; commands and API exist'),
    plain(r'│   ├── run.lua · harness.lua · helpers.lua'),
    plain(r'├── doc/xyno-sandbox.txt         :help xyno-sandbox'),
    plain(r'├── .github/workflows/ci.yml     pinned Neovim, bubblewrap, specs, pinned lazy.nvim, smoke'),
    plain(r'└── README.md · LICENSE · .stylua.toml · .gitignore'),
    ...sec(r'a tour'),
    ...text(r'- init.lua is a policy written as data and a function that compiles it. The tables at the '
        r'top (WRITABLE, HOME_READONLY, HOME_MASK_IF_ABSENT, PROJECT_READONLY, HIDDEN, the three '
        r'environment rules) are the policy; readonly_paths, scrub_names and wrap turn it into '
        r'flags.'),
    ...text(r'- run.lua is the only file that talks to the user: it refuses with one error line, warns '
        r'on unsandboxed runs, opens a terminal split and registers the two commands.'),
    ...text(r'- sandbox_spec.lua tests twice over: it asserts the exact argument vector against a fake '
        r'home, and it runs real scripts inside real bwrap that try to write a shell rc, plant a '
        r'git hook, mount a filesystem, run unshare, or rename a directory.'),
    ...text(r'- failclosed_spec.lua points PATH at a nonexistent directory to simulate a machine without bubblewrap, so the '
        r'refusal is tested on Linux, macOS and Windows alike.'),
    ...sec(r'install and options'),
    ...code('markdown', r'README.md · lines 19-29', r'''
```lua
{
  "xynorash/xyno-sandbox.nvim",
  cmd = { "XynoSandboxStatus", "XynoSandboxRun" },
  opts = {},
  -- no dependencies on other plugins
  keys = {
    { "<leader>as", "<Cmd>XynoSandboxStatus<CR>", desc = "Sandbox status" },
  },
}
```
'''),
    ...code('markdown', r'README.md · lines 35-42', r'''
```lua
require("xyno_sandbox").setup({
  sandbox = true,            -- false: deliberate opt-out, run unsandboxed even where bwrap works
  allow_unsandboxed = false, -- true: run unsandboxed when NO backend exists (never disables a working sandbox)
  keymaps = false,           -- false, or { status = "<lhs>" }; no global keymap is set by default
  commands = true,           -- register :XynoSandboxStatus and :XynoSandboxRun
})
```
'''),
    ...text(r'The plugin loads on the commands, sets no global keymap, and has no dependencies. Options '
        r'are read at every status() and wrap() call, so changing the configuration at run time '
        r'takes effect immediately.'),
    ...sec(r'the API'),
    ...code('markdown', r'README.md · lines 77-86', r'''
### Wrapping an agent command

```lua
local cmd = { "my-agent", "--some-flag", "..." } -- any agent command
local wrapped, err = require("xyno_sandbox").wrap(cmd, project_root, scratch_dir)
if not wrapped then
  error("sandbox: " .. tostring(err), 0) -- fail closed
end
vim.system(wrapped, { cwd = project_root })
```
'''),
    ...text(r'The wrapper returns an argument vector and never runs anything, so it can be used with '
        r'vim.system, jobstart or a test. The README’s example is the intended pattern for '
        r'fail-closed integration: if wrap returns nil, raise an error and start nothing.'),
    ...sec(r'residual risks, in the author’s words'),
    ...code('markdown', r'README.md · lines 102-112', r'''
## Residual risks

It is a denylist on a read-only view of the whole filesystem, with the network open (the model needs it). It is not a security boundary against a determined attacker.

- the agent's credential file under its config directory in `$HOME` must stay readable and writable (token refresh), so an agent can read that token.
- everything unlisted under `$HOME` is readable.
- loopback services and abstract sockets are reachable.
- cargo's `registry/src` and `git` are writable, so your own cargo may later build planted code.
- a nested `.git` deeper than 2 levels is not locked.
- files the project lacks (`.envrc`, `.vscode/tasks.json`, `rust-toolchain.toml`, `bacon.toml`) can be created inside the project.
- masks leave empty directories behind (for example an empty `.cargo`, or an empty memory directory in the agent's config directory).
'''),
    ...text(r'This list is the most important part of the README, and it is reproduced by a spec: four '
        r'of the claims are asserted to stay in the docs. Read it as the boundary of the guarantee. '
        r'The sandbox raises the cost of a careless or manipulated agent doing damage; it is not a '
        r'defence against a determined attacker with network access and a readable home directory.'),
    ...sec(r'platform status, carefully'),
    ...code('markdown', r'README.md · lines 116-119', r'''
- Linux: the specs in this repository run on Linux (`nvim -l tests/run.lua`); that is the only platform where the sandbox works and the only one I claim.
- Windows and macOS: there is no bubblewrap, so `wrap()` refuses and nothing starts. In the original xynovim CI the sandbox spec is skipped on both by design, and the refusal was exercised by a separate spec there. `tests/failclosed_spec.lua` ports that refusal check without an OS gate, but this repository's CI only runs on Linux, so on Windows and macOS it is not run here.
- Windows guards from the source stay in place (the module loads without a user id).
- Sandbox specs that need a working user namespace skip with a message on machines that restrict them.
'''),
    ...text(r'The README claims Linux only. For Windows and macOS it explains the refusal and also what '
        r'is not demonstrated: the fail-closed spec is a port that runs on any platform, but this '
        r'repository’s CI runs only on Linux, so it has not been run on the other two here.'),
    ...sec(r'where it came from'),
    ...text(r'The module began as lua/config/agent_sandbox.lua in xynovim, where the sandbox wrapped '
        r'the 99 agent plugin. The commit subjects of that file read as a record of field-test findings: the '
        r'first versions on 2026-10-09, a second hardening pass with directory-level locks and '
        r'masks for absent paths on 2026-10-12, a memory directory and a security directory on '
        r'2026-10-13 (in three commits that also added the .git mask, tailscale and secrets), a chdir fix on 2026-10-14, and finally, on 2026-10-16, the change '
        r'that made it fail closed when no backend exists. On 2026-10-22 it was published as '
        r'xyno-sandbox.nvim; the same day 79bcfa5 made the descriptions generic and ported the '
        r'fail-closed spec, and c85b701 pinned Neovim by version and checksum in CI.'),
    ...sec(r'try it'),
    ...text(r'- :XynoSandboxStatus shows how an agent would run here.'),
    ...text(r'- :XynoSandboxRun bash opens a shell in the sandbox in a terminal split, where the '
        r'project is writable and the rest of the home directory is not.'),
    ...text(r'- nvim -l tests/run.lua runs every spec file, each in its own headless Neovim.'),
  ],
);
