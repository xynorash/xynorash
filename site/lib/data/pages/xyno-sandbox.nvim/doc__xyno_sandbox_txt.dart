import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-sandbox.nvim/doc/xyno-sandbox.txt',
  lines: [
    cm('--', r'──────────────────────────────────────────'),
    cm('--', r'xyno-sandbox.txt — the :help page'),
    cm('--', r'shorter than the README, and honest about what it leaves out'),
    cm('--', r'──────────────────────────────────────────'),
    kv(r'role', r'Vim help file, :help xyno-sandbox'),
    kv(r'format', r'Neovim help syntax, textwidth 78'),
    kv(r'size', r'147 lines, 8 sections'),
    kv(r'asserted by', r'the README residual-risk spec reads this file together with the README'),
    kv(r'history', r'added in d8f2ed9 (2026-10-22, Add README and help); amended in 79bcfa5'),
    ...sec(r'why this file exists'),
    ...para('--', r'The reference for someone inside the editor. It has eight sections and states the same policy in the language of options '
        r'and tags. Like the README, it begins with the claim that matters; the risks come second to last, before a short platforms section.'),
    ...sec(r'introduction and requirements'),
    ...code('text', r'doc/xyno-sandbox.txt · lines 1-31', r'''
*xyno-sandbox.txt*  Run a coding agent inside a bubblewrap sandbox, or not at all

==============================================================================
CONTENTS                                                  *xyno-sandbox-contents*

  1. Introduction ............................ |xyno-sandbox|
  2. Requirements ............................ |xyno-sandbox-requirements|
  3. Setup and options ....................... |xyno-sandbox-setup|
  4. Commands ................................ |xyno-sandbox-commands|
  5. Lua API ................................. |xyno-sandbox-api|
  6. How it works ............................ |xyno-sandbox-how|
  7. Residual risks .......................... |xyno-sandbox-risks|
  8. Platforms ............................... |xyno-sandbox-platforms|

==============================================================================
1. Introduction                                                  *xyno-sandbox*

xyno-sandbox.nvim wraps a command-line coding agent in bubblewrap (`bwrap`)
and refuses to start it without a sandbox. The filesystem is read-only except
the project and a scratch directory, credentials are hidden, secret
environment variables are stripped, and files that would later run outside the
sandbox are locked read-only. The network stays open.

The policy knows the config, cache and state directories of one agent CLI,
but |wrap()| takes any command.

==============================================================================
2. Requirements                                         *xyno-sandbox-requirements*

  - Neovim 0.12 or newer
  - Linux with `bwrap` on $PATH and unprivileged user namespaces
'''),
    ...para('--', r'The introduction is a short statement of the guarantee and of its limit in the same '
        r'breath: the filesystem read-only except the project and a scratch directory, credentials '
        r'hidden, secrets stripped, files that would run later locked, and the network stays open. '
        r'The second paragraph was reworded in 79bcfa5, from a policy written for one named agent '
        r'to this: the policy knows the directories of one agent CLI, but wrap takes any command. '
        r'Requirements list Neovim 0.12, Linux with bwrap on PATH and unprivileged user namespaces, '
        r'and no other plugin.'),
    ...sec(r'options as tags'),
    ...code('text', r'doc/xyno-sandbox.txt · lines 32-60', r'''
  - no other plugin

==============================================================================
3. Setup and options                                          *xyno-sandbox-setup*

>lua
    require("xyno_sandbox").setup({
      sandbox = true,
      allow_unsandboxed = false,
      keymaps = false,
      commands = true,
    })
<
                                                          *xyno-sandbox-sandbox*
sandbox                 boolean, default true
    `false` is the deliberate opt-out: the agent runs unsandboxed even where
    bwrap works. Only the boolean `false` counts.

                                                *xyno-sandbox-allow_unsandboxed*
allow_unsandboxed       boolean, default false
    `true` lets the agent run unsandboxed when NO backend exists (Windows,
    macOS, Linux without bwrap). It never disables a working sandbox. Only the
    boolean `true` counts.

                                                         *xyno-sandbox-keymaps*
keymaps                 false or table, default false
    No global keymap is set by default. `{ status = "<lhs>" }` maps normal mode
    <lhs> to the status message.

'''),
    ...para('--', r'Each option has a tag of its own, so :help xyno-sandbox-allow_unsandboxed works, and each '
        r'description repeats the strictness rule: only the boolean counts. The allow_unsandboxed '
        r'entry states the scope exactly, for Windows, macOS and Linux without bwrap, and adds that '
        r'it never disables a working sandbox.'),
    ...sec(r'commands and the API'),
    ...code('text', r'doc/xyno-sandbox.txt · lines 61-122', r'''
                                                        *xyno-sandbox-commands-opt*
commands                boolean, default true
    Register |:XynoSandboxStatus| and |:XynoSandboxRun|.

Mapping from xynovim: `vim.g.xynovim_99_sandbox = false` is
`setup({ sandbox = false })` and `vim.g.xynovim_99_allow_unsandboxed = true`
is `setup({ allow_unsandboxed = true })`.

==============================================================================
4. Commands                                                *xyno-sandbox-commands*

                                                          *:XynoSandboxStatus*
:XynoSandboxStatus      Show how an agent would run here: sandboxed,
                        unsandboxed (and why) or refused (and why).

                                                             *:XynoSandboxRun*
:XynoSandboxRun {cmd} [args...]
                        Run the command in a terminal split, wrapped. The
                        project is the current directory. Without a sandbox it
                        prints a one-line error and starts nothing. Every
                        explicitly unsandboxed run warns.

==============================================================================
5. Lua API                                                     *xyno-sandbox-api*

                                                                     *status()*
require("xyno_sandbox").status()
    Returns `{ mode = "bwrap" }`, `{ mode = "unsandboxed", via, reason }` or
    `{ mode = "refused", reason }`. `via` is "sandbox=false" or
    "allow_unsandboxed".

                                                                       *wrap()*
require("xyno_sandbox").wrap({cmd}, {project}, {tmp_dir})
    Returns the wrapped command (a string list), or `nil, reason` when
    refused. When explicitly unsandboxed the same {cmd} table is returned.
    {project} and {tmp_dir} are writable inside the sandbox. The agent starts
    in Neovim's current directory when that is inside {project}, otherwise in
    {project}.

                                                                        *run()*
require("xyno_sandbox").run({cmd}, {opts})
    What |:XynoSandboxRun| does. {opts} may hold `project` and `tmp_dir`.
    Returns the job id, or nil when nothing was started.

                                                                *scrub_names()*
require("xyno_sandbox").scrub_names({env}, {file_login})
    Names of the environment variables that are removed.

                                                             *readonly_paths()*
require("xyno_sandbox").readonly_paths({project})
    Returns the paths bound read-only on top of the writable binds, and the
    absent directories masked with an empty read-only directory.

==============================================================================
6. How it works                                                 *xyno-sandbox-how*

`bwrap` gets a read-only bind of `/`, private /dev, /proc and /tmp, new user,
pid, ipc, uts and cgroup namespaces, nested user namespaces disabled, all
capabilities dropped and no controlling terminal. The project, the scratch
directory and a few agent and cargo cache paths are writable. Git directories,
`.cargo`, `.envrc`, `.vscode`, the agent's project directory and the agent settings, hooks, skills
and memory are read-only (or masked with an empty read-only directory when
'''),
    ...para('--', r'The commands and Lua API sections document the two commands and the five functions (status, wrap, run, scrub_names, readonly_paths; setup is under options). The '
        r'wrap entry specifies the return convention that makes fail-closed integration possible: a '
        r'wrapped command, or nil and a reason, and the same table when explicitly unsandboxed. run '
        r'returns the job id or nil when nothing was started.'),
    ...sec(r'how it works and the risks'),
    ...code('text', r'doc/xyno-sandbox.txt · lines 123-147', r'''
absent). Credential directories and files are replaced by empty ones.
Environment variables that look like secrets are removed.

==============================================================================
7. Residual risks                                              *xyno-sandbox-risks*

It is a denylist on a read-only view of the filesystem with the network open.

  - the agent's credential file under its config directory must stay readable
    and writable.
  - everything unlisted under `$HOME` is readable.
  - loopback services and abstract sockets are reachable.
  - cargo's `registry/src` and `git` are writable.
  - a nested `.git` deeper than 2 levels is not locked.
  - masks leave empty directories behind.

==============================================================================
8. Platforms                                               *xyno-sandbox-platforms*

Linux is the only platform where the sandbox works, and the specs in this
repository run there. On Windows and macOS there is no bubblewrap: |wrap()|
refuses and nothing starts, unless `allow_unsandboxed` or `sandbox = false`
is set.

 vim:tw=78:ts=8:ft=help:norl:
'''),
    ...para('--', r'The how-it-works paragraph is the README’s compressed into a block of lines. The residual '
        r'risks list is shorter than the README’s: six bullets against seven. The README adds that '
        r'files the project lacks (.envrc, .vscode/tasks.json, rust-toolchain.toml, bacon.toml) can '
        r'be created inside the project; the help file does not repeat it. The spec that reads both '
        r'files together would pass if that sentence were removed from the README alone, because it '
        r'does not assert it. The platforms section ends the file in two sentences.'),
    ...sec(r'history'),
    ...pt('--', r'd8f2ed9', r'2026-10-22: added with the README.'),
    ...pt('--', r'79bcfa5', r'2026-10-22: three passages were reworded to be agent-neutral: the introduction sentence '
        r'about whose directories the policy knows, the how-it-works list (the agent’s project '
        r'directory replaces a named directory) and the credential-file bullet of the residual '
        r'risks.'),
  ],
);
