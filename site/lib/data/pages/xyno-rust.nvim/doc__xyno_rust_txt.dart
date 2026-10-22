import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-rust.nvim/doc/xyno-rust.txt',
  lines: [
    cm('"', '──────────────────────────────────────────'),
    cm('"', r'doc/xyno-rust.txt - the :help page'),
    cm('"', r'ten numbered sections, tags for every command and module'),
    cm('"', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'Vim help file: :help xyno-rust'),
    kv(r'format', r'Vim help syntax, modeline tw=78, with *tags* and |links|'),
    kv(r'size', r'326 lines, added in 6947749 (2026-10-22, "Add README, help file and CI workflow")'),
    kv(r'sections', r'introduction, requirements, setup, commands, keymaps, Lua API, wiring, how it works, platforms, license'),
    ...sec(r'why this file exists'),
    ...text(r'A README is read once, on GitHub; a help file is read forever, from inside the editor, with :help. For a plugin that is a library for other plugins the help file has a second job: it is the API reference. The README carries the same facts, but the help file is the one that is installed with the plugin, and searchable offline. Its first line is the standard header, the file name between asterisks followed by a one-line description.'),
    ...code('text', r'doc/xyno-rust.txt · lines 1-17', r'''
*xyno-rust.txt*  Rust project plumbing for Neovim: Cargo context, targets, routes, server handling

                              xyno-rust.nvim

==============================================================================
CONTENTS                                                      *xyno-rust-contents*

  1. Introduction ............................. |xyno-rust|
  2. Requirements ............................. |xyno-rust-requirements|
  3. Setup and options ........................ |xyno-rust-setup|
  4. Commands ................................. |xyno-rust-commands|
  5. Keymaps .................................. |xyno-rust-keymaps|
  6. Lua API .................................. |xyno-rust-api|
  7. Wiring it to the language servers ........ |xyno-rust-wiring|
  8. How it works ............................. |xyno-rust-how|
  9. Platforms ................................ |xyno-rust-platforms|
 10. License and origin ....................... |xyno-rust-license|'''),
    ...sec(r'the contents table is a set of links'),
    ...text(r'Every entry in the table of contents is a |tag| that points at a section anchor on the right-hand side of the section title, such as *xyno-rust-setup* or *xyno-rust-api*. Typing :help xyno-rust-wiring jumps straight to the part that explains how to hook rust-analyzer and bacon-ls up. The commands have their own tags (*:RustContext*, *:RustTargets*, *:RustTools*, *:RustRoutes*, *:RustNew*, *:ActJob*, *:RustRestart*), so :help :RustRoutes works as with any built-in command. Each module has one too: *xyno_rust.rust_context* and the others.'),
    ...sec(r'introduction and requirements'),
    ...code('text', r'doc/xyno-rust.txt · lines 20-42', r'''
1. INTRODUCTION                                                      *xyno-rust*

xyno-rust.nvim is the shared base of my Rust setup. It holds:

  - a per-project Cargo context (features and target) that rust-analyzer and
    bacon-ls can both follow (|xyno_rust.rust_context|),
  - a Cargo targets and tools picker, `cargo new`, and `act` for the GitHub
    Actions job under the cursor (|xyno_rust.rust_tasks|),
  - an HTTP route picker for axum, actix and rocket projects
    (|xyno_rust.rust_routes|),
  - go to super method and reads/writes of a symbol in the file
    (|xyno_rust.rust_nav|),
  - restart handling for rust-analyzer and bacon-ls (|xyno_rust.rust_restart|),
  - a readiness indicator for the statusline (|xyno_rust.lsp_status|),
  - helpers other plugins build on: |xyno_rust.code_actions|,
    |xyno_rust.crate_meta| and |xyno_rust.fsutil|.

The Cargo context and the tools picker are inspired by the Cargo tool window
of the JetBrains IDEs, which I still use. This plugin is independent and not
affiliated with JetBrains.

Each module can be required on its own; setup() only wires the commands and
autocommands.'''),
    ...text(r'The introduction lists the modules as bullets that are links to their API entries. It also keeps the attribution sentence of the README: the Cargo context and the tools picker are inspired by the Cargo tool window of the JetBrains IDEs, and the plugin is independent and not affiliated with them. The last paragraph says what setup() is for: it only wires commands and autocommands, every module can be required on its own. That is the sentence that tells a plugin author they can use the library without the commands.'),
    ...code('text', r'doc/xyno-rust.txt · lines 45-62', r'''
2. REQUIREMENTS                                              *xyno-rust-requirements*

  - Neovim 0.12 or newer.
  - `cargo` in $PATH for everything that reads a workspace.
  - rust-analyzer started through |vim.lsp| (for example by rustaceanvim) for
    |xyno_rust.rust_nav|, |xyno_rust.code_actions| and the live parts of
    |xyno_rust.rust_context|.
  - The tree-sitter `rust` parser for |:RustRoutes| and |xyno_rust.rust_nav|;
    the `yaml` parser for |:ActJob|.
  - snacks.nvim (picker and terminal) for |:RustContext|, |:RustTargets|,
    |:RustTools|, |:RustRoutes| and the terminal runs. Without it those
    commands print one error line and do nothing else.
  - Optional external tools, only for the entries that call them: `rustup`,
    `samply`, `cargo-flamegraph`, `cargo-bloat`, `cargo-machete`,
    `cargo-deny`, `cargo-audit`, `cargo-llvm-cov`, `act`, `curl` (crates.io
    client in |xyno_rust.crate_meta|), bacon-ls.

No other plugin is required.'''),
    ...text(r'The requirements are listed by what needs them. rust-analyzer is needed for navigation, code actions and the live part of the context, not for loading; the tree-sitter rust parser for routes and navigation; yaml for ActJob; snacks for the pickers, with the failure mode written out (one error line). curl is mentioned because the crates.io client in crate_meta uses it.'),
    ...sec(r'setup, commands and keys'),
    ...code('text', r'doc/xyno-rust.txt · lines 67-93', r'''
>lua
    require("xyno_rust").setup({
      commands = true, -- :RustContext :RustTargets :RustTools :ActJob :RustNew
                       -- :RustRoutes :RustRestart
      keymaps = false, -- false | true | { context = lhs, targets = lhs, ... }
      modules = {
        context = true, -- xyno_rust.rust_context
        tasks = true,   -- xyno_rust.rust_tasks
        routes = true,  -- xyno_rust.rust_routes
        status = true,  -- xyno_rust.lsp_status (autocommands)
        restart = true, -- xyno_rust.rust_restart (autocommands)
      },
    })
<

                                                              *xyno-rust-opts*
commands    boolean, default true. Define the user commands. The
            autocommands of the status and restart modules are set either way.
keymaps     false (default): no key is set. true: the defaults of
            |xyno-rust-keymaps|. A table maps the named actions to the keys
            you give; only the listed actions are mapped, `false` skips one.
            The keys are buffer-local, in Rust buffers.
modules     Switch single modules off. A module that is off defines no
            command and no autocommand.

setup() needs Neovim 0.12; on an older one it prints one error line and does
nothing. Calling it again replaces the autocommands.'''),
    ...text(r'The options block is a runnable example with comments that name the module each switch controls, followed by a definition list in the style of the Vim documentation: option name, type and default, then the description. It states the precise behaviour that is easy to get wrong: with commands = false the autocommands of the status and restart modules are set either way, a module that is off defines no command and no autocommand, and setup() prints one error line on a Neovim older than 0.12 and does nothing else. Calling it again replaces the autocommands.'),
    ...code('text', r'doc/xyno-rust.txt · lines 98-127', r'''
                                                                  *:RustContext*
:RustContext            Pick Cargo features (multi-select with <Tab>), then a
                        target; applies it to the running rust-analyzer and
                        bacon-ls and stores it per workspace.
:RustContext show       Print the context of the current workspace.
:RustContext reset      Forget the stored choice (all features, host target).

                                                                  *:RustTargets*
:RustTargets            Pick a target of the workspace (bin, example, test,
                        bench, lib) and run, test, build, bench, profile it in
                        a bottom terminal. Honours |:RustContext|.

                                                                    *:RustTools*
:RustTools              Pick a workspace tool: timings, bloat, machete, deny,
                        audit, duplicate versions, coverage summary.

                                                                    *:RustRoutes*
:RustRoutes             Pick an HTTP route (axum `.route("/p", ..)`, actix and
                        rocket `#[get("/p")]`) and jump to it.

                                                                     *:RustNew*
:RustNew [name]         `cargo new` (bin or lib) in the current directory and
                        open the new crate.

                                                                      *:ActJob*
:ActJob                 Run the GitHub Actions job under the cursor with `act`.

                                                                  *:RustRestart*
:RustRestart            Restart rust-analyzer and bacon-ls, also when one of
                        them has died.'''),
    ...text(r'The command section is a column layout where each command has a right-aligned tag. The wording of the entries matches the README table, and it adds the sentence that matters for the targets picker: it honours :RustContext.'),
    ...code('text', r'doc/xyno-rust.txt · lines 130-142', r'''
5. KEYMAPS                                                      *xyno-rust-keymaps*

No key is set by default. With `keymaps = true`, buffer-local in Rust files:

    context       <leader>rF   |:RustContext|
    targets       <leader>rX   |:RustTargets|
    tools         <leader>rZ   |:RustTools|
    routes        <leader>rN   |:RustRoutes|
    goto_super    <leader>ru   |xyno_rust.rust_nav|
    local_usages  <leader>rl   |xyno_rust.rust_nav|
    doctests      <leader>tD   |xyno_rust.rust_tasks|

Or define them in the lazy.nvim spec with `ft = "rust"` (see the README).'''),
    ...text(r'The keymap table is aligned in three columns: the action name you use in the keymaps table, the default key, and where the action goes. The last line tells the user the alternative, to define the keys in the lazy.nvim spec with ft = "rust".'),
    ...sec(r'the Lua API reference'),
    ...code('text', r'doc/xyno-rust.txt · lines 145-175', r'''
6. LUA API                                                          *xyno-rust-api*

All modules are under `xyno_rust`. Functions that can wait come in pairs,
`name_async(..., cb)` and a blocking `name(...)`.

xyno_rust                                                           *xyno_rust*
    setup({opts})                    see |xyno-rust-setup|
    defaults                         the default options table
    default_keymaps                  action name -> default lhs

xyno_rust.fsutil                                              *xyno_rust.fsutil*
    rename({tmp}, {dest})            uv.fs_rename that retries on Windows
                                     (sharing violations); returns what
                                     fs_rename returns
    slash({path})                    forward slashes (Windows only)

xyno_rust.rust_context                                  *xyno_rust.rust_context*
    root({path}?)                    workspace root of a path (default: the
                                     current buffer); nil outside a crate
    get({root})                      stored context or nil
    apply({root}, {ctx}?)            store {ctx} (nil resets), push it into the
                                     running servers, notify
    pick()                           the |:RustContext| picker
    reset()                          |:RustContext| reset
    describe({ctx}?)                 "features: ssr,csr | target: ..."
    ra_cargo({ctx}?)                 `rust-analyzer.cargo` settings table
    cargo_flags({ctx}?)              {"--all-features", ...} for cargo
    bacon_args({ctx}?)               extraArgs for bacon-ls
    canon({path})                    one spelling of a root (Windows)
    A context is { all = boolean, no_default = boolean, features = string[],
    target = string? }. Nothing stored means all features, host target. The'''),
    ...text(r'The API section is the reference for people writing their own plugins on top. Each module has a heading with its tag at the right margin and then its functions with parameters in braces and optional ones marked with a question mark, as in the help files of Neovim itself. The note on the context table is the data model in one sentence: a context is { all, no_default, features, target }, nothing stored means all features and the host target, and the state lives in stdpath("state") under rust-context.json, written under a lock file and renamed into place.'),
    ...code('text', r'doc/xyno-rust.txt · lines 216-248', r'''
xyno_rust.code_actions                                  *xyno_rust.code_actions*
    request({bufnr}, {range}, {opts}, {cb})
    request_wait({bufnr}, {range}, {opts})
    wait_for({bufnr}, {range}, {spec}, {opts})
    filter({list}, {spec})
    apply({action}, {opts})  apply_async({action}, {cb}, {opts})
    apply_all({actions}, {opts})  resolve_async({action}, {cb}, {opts})
    clients({bufnr})  client_name
    Positions are 0-based { row, col } with a byte column. An action is
    { title, kind, is_preferred, edit, command, data, raw, client_id,
    client_name, bufnr }.

xyno_rust.crate_meta                                      *xyno_rust.crate_meta*
    metadata({root}, {opts}) metadata_async({root}, {cb}, {opts})
    invalidate({root}?)  normalize({raw}, {root})
    dependencies({meta}, {filter})  member_of({meta}, {path})  root({path}?)
    registry_dir({name}, {version}?)  source_dir({root}, {name}, {version}?)
    read_manifest({dir})  read_lib({dir})  parse_features({toml})
    info({name}, {opts}) info_async  search({query}, {opts}) search_async
    index_path({name})  parse_index({text})
    valid_name  valid_version  compare_versions
    is_known_path_head({root}, {name}, {opts}?)
    exec({argv}, {opts}, {cb}?)  config  std_crates
    The crates.io client uses curl with an argument list, caches on disk
    under `stdpath("cache")/xyno-rust/crates` and tolerates being offline.
    `config` holds the timeouts, TTLs, URLs, user agent and cache directory.

xyno_rust.deps                                                  *xyno_rust.deps*
    snacks()                         the snacks.nvim table, or nil after one
                                     error line

Buffer variable: `vim.b.xyno_rust_stopped` is a table { [server name] = true }
on the buffers of a server that exited; |xyno_rust.lsp_status| reads it.'''),
    ...text(r'The two library modules are documented with the conventions that make them predictable. For code_actions, positions are 0-based row and column with a byte column, and an action is a table of known fields. For crate_meta the paragraph says that the client uses curl with an argument list, caches on disk, tolerates being offline and keeps its configuration in a config table. The section ends with the buffer variable vim.b.xyno_rust_stopped, which is the one piece of shared state between rust_restart (which writes it) and lsp_status (which reads it).'),
    ...sec(r'wiring, internals and platforms'),
    ...code('text', r'doc/xyno-rust.txt · lines 251-292', r'''
7. WIRING IT TO THE LANGUAGE SERVERS                           *xyno-rust-wiring*

The modules do not configure rust-analyzer or bacon-ls. With rustaceanvim:
>lua
    vim.g.rustaceanvim = {
      server = {
        on_exit = function(...)
          return require("xyno_rust.rust_restart").on_exit("rust-analyzer")(...)
        end,
        settings = function(root, default_settings)
          local settings = require("rustaceanvim.config.server").load_rust_analyzer_settings(
            root,
            { default_settings = vim.deepcopy(default_settings) }
          )
          local ctx = require("xyno_rust.rust_context")
          local cargo = ctx.ra_cargo(ctx.get(ctx.root(root and (root .. "/x"))))
          if cargo then
            local ra = settings["rust-analyzer"]
            ra.cargo = vim.tbl_extend("force", ra.cargo or {}, cargo)
          end
          return settings
        end,
      },
    }
<
For bacon-ls, `on_exit` is the same with "bacon_ls", and `before_init`
rebuilds the arguments from the stored context:
>lua
    before_init = function(params, config)
      local rc = require("xyno_rust.rust_context")
      local ctx = rc.get(rc.root((config.root_dir or vim.uv.cwd()) .. "/x"))
      local s = vim.deepcopy(bacon_ls_settings) -- your own defaults
      s.cargo.extraArgs = rc.bacon_args(ctx)
      params.initializationOptions = s
      config.settings = config.settings or {}
      config.settings.bacon_ls = s
    end,
<
The statusline component, with lualine:
>lua
    lualine_x = { require("xyno_rust.lsp_status").component }
<'''),
    ...text(r'Section 7 holds the three snippets a user has to copy: the rustaceanvim server block, the bacon-ls before_init, and the lualine component. The >lua and < markers are the Vim help way of marking a code block with a language for syntax highlighting. The wiring is intentionally not in code anywhere: the modules do not configure the servers, and the help file is where that boundary is explained.'),
    ...code('text', r'doc/xyno-rust.txt · lines 294-318', r'''
8. HOW IT WORKS                                                   *xyno-rust-how*

The context is a small JSON file per workspace root. |:RustContext| writes
it, sends `workspace/didChangeConfiguration` to the rust-analyzer clients that
serve the workspace, asks rustaceanvim to reload, and restarts bacon-ls so
both see the same features and target. The root is the one `cargo
locate-project --workspace` reports, with a text walk to the outermost
`[workspace]` when cargo cannot answer.

|xyno_rust.lsp_status| reacts to LspProgress, `experimental/serverStatus`,
`window/showMessage` and text changes; nothing polls while idle, except the
timers of the "deps resolving" state (6 s grace, 120 s ceiling).
|xyno_rust.rust_restart| restarts a server after a crash, bacon-ls after a
save of Cargo.toml or Cargo.lock, a moved git HEAD or a manifest changed on
disk, and stops bacon-ls clients whose workspace is gone.

==============================================================================
9. PLATFORMS                                                  *xyno-rust-platforms*

Linux: tested by the specs in this repository (`nvim -l tests/run.lua`).
Windows and macOS: not tested in this repository. See the README for what the
CI of the original configuration showed. Linux and macOS only by design: in
|xyno_rust.rust_restart| the shadow-workspace checks, the orphan-buffer check
and the root lookup accept only absolute paths that start with "/", so they do
nothing on Windows, and the SIGCONT before quit is skipped there.'''),
    ...text(r'"How it works" gives the mechanism in two paragraphs: the context file, didChangeConfiguration, the reload and bacon-ls restart, cargo locate-project with a text walk fallback, the event sources of the status component, and the exceptions to "nothing polls": the 6 second grace and 120 second ceiling of the deps resolving state. The platform section is more blunt than the README. It says Linux is tested by the specs in this repository, Windows and macOS are not tested here, and that in rust_restart the shadow-workspace checks, the orphan-buffer check and the root lookup accept only absolute paths that start with a slash, so they do nothing on Windows, and the SIGCONT before quit is skipped there.'),
    ...sec(r'things to know when reading it next to the README'),
    ...bullet(r'same content, different job', r'the README is a tour, the help file is a reference; the tables overlap on purpose.'),
    ...bullet(r'one phrase differs', r'the help file says "Linux and macOS only by design" for the restart module’s shadow checks, while the README says macOS is untested here. Both are in the text; the code only checks for a leading slash.'),
    ...bullet(r'no tags file in this repository', r'doc/tags is not committed to xyno-rust.nvim (the sibling plugins xyno-crates.nvim and xyno-imports.nvim commit one), so the tags have to be generated by whoever installs the plugin (for example with :helptags).'),
    ...sec(r'history'),
    ...text(r'The file was added with the README in 6947749 (2026-10-22). It has no ancestor in xynovim, which has no doc/ directory; this one was written for the plugin, and the last line is the standard modeline vim:tw=78:ts=8:ft=help:norl:.'),
  ],
);
