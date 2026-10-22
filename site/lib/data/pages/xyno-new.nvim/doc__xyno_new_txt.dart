import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-new.nvim/doc/xyno-new.txt',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'doc/xyno-new.txt — the :help file'),
    cm('--', r'ten sections, 24 tags, every command and option reachable from :help'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'Vim help for xyno-new.nvim: :help xyno-new'),
    kv(r'format', r'Vim help text, 216 lines, tw=78, tags in *asterisks*, links in |bars|'),
    kv(r'checked by', r'tests/e2e/smoke.lua runs :help on nine of its tags'),
    kv(r'generated', r'doc/tags is not committed (it is in .gitignore)'),
    ...sec(r'why a help file when there is a README'),
    ...para('--', r'A help file can be opened without leaving Neovim. Once the tags in doc/ are generated (the smoke test runs helptags itself; doc/tags is git-ignored), :help :RustNewWorkspace finds the command. The two files carry the same facts in different shapes: the README sells and tours, the help file looks things up.'),
    ...sec(r'the header and the table of contents'),
    ...code('text', r'doc/xyno-new.txt · lines 1-19', r'''
*xyno-new.txt*  New Rust projects from inside Neovim: binary, library, workspace, egui

                               xyno-new.nvim

==============================================================================
CONTENTS                                                       *xyno-new-contents*

  1. Introduction ............................. |xyno-new|
  2. Requirements ............................. |xyno-new-requirements|
  3. Setup and options ........................ |xyno-new-setup|
  4. Commands ................................. |xyno-new-commands|
  5. Keymaps .................................. |xyno-new-keymaps|
  6. Dashboard entries ........................ |xyno-new-dashboard|
  7. Lua API .................................. |xyno-new-api|
  8. How it works ............................. |xyno-new-how|
  9. Platforms ................................ |xyno-new-platforms|
 10. License and origin ....................... |xyno-new-license|

=============================================================================='''),
    ...para('--', r'The first line is the file tag *xyno-new.txt* with a one-line title; the second block is a centred name. A row of equals signs starts each section, as in Neovim’s own help. The table of contents uses dotted leaders to a |link| for each of the ten sections, each of which has its own tag on the heading line (*xyno-new-requirements*, *xyno-new-setup*, and so on) right-aligned against column 78 as a tag line should be. The dotted leaders are plain text; Vim does not generate them.'),
    ...sec(r'sections one and two: what and what you need'),
    ...code('text', r'doc/xyno-new.txt · lines 20-41', r'''
1. INTRODUCTION                                                       *xyno-new*

xyno-new.nvim creates new Rust projects without leaving Neovim: a binary, a
library, a workspace whose members inherit `version` and `edition`, a member
for an existing workspace, and an egui app from the current eframe_template.
Every command asks for what it needs, applies cargo's name rules before
anything is created, leaves nothing behind when a step fails and opens the new
project.

==============================================================================
2. REQUIREMENTS                                            *xyno-new-requirements*

  - Neovim 0.12 or newer.
  - xyno-rust.nvim (required): |xyno_rust.rust_context| finds the workspace of
    |:RustNewMember|. If it is missing, |xyno_new.setup()| prints one error
    line and defines nothing.
  - `cargo` in $PATH. `git` is optional (`git init -b main` for a workspace and
    for |:EguiNew|, and the defaults of the author prompts).
  - For |:EguiNew|: `curl`, `unzip` (on Windows `tar`), network access for the
    first download (the ZIP is cached with its ETag and used offline), and
    `rustc` for the minimum-version warning.
  - snacks.nvim is optional: the dashboard entries and `egui_build_after_new`.'''),
    ...para('--', r'Section 1 is a paragraph that says what it creates and what each command guarantees: it asks, applies cargo’s name rules before anything is created, leaves nothing behind when a step fails and opens the new project. Section 2 names the requirements. Its first bullet links |xyno_rust.rust_context| and its tag is defined in xyno-rust.nvim’s own help file; with both plugins installed the link jumps there. The bullet also states what happens without xyno-rust.nvim: one error line, nothing defined.'),
    ...sec(r'section 3: options as tags'),
    ...code('text', r'doc/xyno-new.txt · lines 44-66', r'''
3. SETUP AND OPTIONS                                             *xyno-new-setup*

                                                              *xyno_new.setup()*
>lua
    require("xyno_new").setup({
      commands = true,
      keymaps = false,
      projects_dir = nil,
      egui_template = nil,
      egui_build_after_new = nil,
    })
<
Returns true, or false after one error notification when Neovim is older than
0.12 or xyno-rust.nvim is missing.

                                                        *xyno-new-opt-commands*
commands ~
    boolean, default true. Define |:RustNewBin|, |:RustNewLib|,
    |:RustNewWorkspace|, |:RustNewMember| and |:EguiNew|.

                                                        *xyno-new-opt-keymaps*
keymaps ~
    false, true or a table, default false. See |xyno-new-keymaps|.'''),
    ...para('--', r'The setup block uses the code-block convention of Neovim’s help: a line ending with >lua opens a block, indented code follows, and a line with a single < closes it (the lua after the angle bracket names the language for highlighting). Every option has its own tag of the form *xyno-new-opt-NAME* and its entry written as “name ~” (a heading line in help syntax, ending in a tilde), then an indented description with type, default and the vim.g variable it is stored in.'),
    ...code('text', r'doc/xyno-new.txt · lines 68-84', r'''
                                                    *xyno-new-opt-projects_dir*
projects_dir ~
    string, default nil. The parent directory offered by the prompts. Without
    it: ~/projects when that exists, else the current directory. Stored in
    `vim.g.xyno_new_projects_dir`.

                                                   *xyno-new-opt-egui_template*
egui_template ~
    table, default nil: `{ repo = "emilk/eframe_template", ref = "main",
    base_url = "https://github.com" }`; give the keys you want to change.
    `base_url` must be an https://, http:// or file:// URL. Stored in
    `vim.g.xyno_new_egui_template`.

                                              *xyno-new-opt-egui_build_after_new*
egui_build_after_new ~
    boolean, default nil. true: run `cargo build` in a snacks.nvim terminal
    after |:EguiNew|. Stored in `vim.g.xyno_new_egui_build_after_new`.'''),
    ...para('--', r'Two of these show how options map to code: projects_dir and egui_build_after_new are stored in vim.g.xyno_new_projects_dir and vim.g.xyno_new_egui_build_after_new, and egui_template takes “the keys you want to change”, because the code merges over the defaults with vim.tbl_extend. The help file also spells out a limit that egui.lua enforces in its config validation: base_url must be an https://, http:// or file:// URL.'),
    ...sec(r'section 4: commands'),
    ...code('text', r'doc/xyno-new.txt · lines 89-127', r'''
                                                                *:RustNewBin*
:RustNewBin [name]
    `cargo new --bin --vcs git`. Asks for the name (the argument is used when
    it is valid) and the parent directory, then switches to the project and
    opens `src/main.rs`.

                                                                *:RustNewLib*
:RustNewLib [name]
    The same with `--lib` and `src/lib.rs`. A name with hyphens shows the crate
    identifier it will have in Rust code.

                                                          *:RustNewWorkspace*
:RustNewWorkspace [name]
    Asks for the workspace name, the parent directory, the kind of the first
    member and its name. Writes `Cargo.toml` (`[workspace]`, `members =
    ["crates/*"]`, `[workspace.package]` with `version` and the edition your
    cargo uses for new projects, an empty `[workspace.dependencies]`) and
    `.gitignore`, creates the member with `cargo new --vcs none` so that it
    inherits version and edition, and runs `git init -b main` (no commit).
    Asks first when the parent lies in another workspace's members or in a git
    work tree.

                                                              *:RustNewMember*
:RustNewMember [name]
    Adds a binary or library crate to the workspace of the current buffer (or
    the current directory). Refuses a name that clashes with a member or a
    directory that exists.

                                                                  *:EguiNew*
:EguiNew [name]
    Downloads the current eframe_template as a ZIP, asks for the crate name,
    author name, author e-mail (both may be empty) and the parent directory,
    and personalises it: crate name, authors, window and page title, the web
    build file names. Nothing from the template is executed. Its
    `rust-toolchain` file is never copied; `rust-version` stays and a warning
    says when `rustc` is older.

A cancelled prompt ends the command silently. Only one project is created at a
time.'''),
    ...para('--', r'Each command has a tag with its colon (*:RustNewBin*), so :help :RustNewBin works, and a short usage line followed by an indented paragraph. The workspace entry is the most detailed because it lists exactly what is written: Cargo.toml with [workspace], members = ["crates/*"], [workspace.package] with version and the edition your cargo uses, an empty [workspace.dependencies], and .gitignore; then the member created with cargo new --vcs none so it inherits; then git init -b main without a commit. The help also states the interaction rule that applies to every command: a cancelled prompt ends silently and only one project is created at a time.'),
    ...sec(r'sections five and six: keymaps and the dashboard'),
    ...code('text', r'doc/xyno-new.txt · lines 132-142', r'''
No global keymap is set by default. With `keymaps = true`, in normal mode:

    <leader>rnb    |:RustNewBin|
    <leader>rni    |:RustNewLib|
    <leader>rnw    |:RustNewWorkspace|
    <leader>rnm    |:RustNewMember|
    <leader>rne    |:EguiNew|

A table maps only the actions you list (`bin`, `lib`, `workspace`, `member`,
`egui`) to the keys you choose; false skips one. The defaults are in
`require("xyno_new").default_keymaps`.'''),
    ...code('text', r'doc/xyno-new.txt · lines 147-166', r'''
                                                       *xyno_new.dashboard_keys()*
require("xyno_new").dashboard_keys({keys})
    Inserts four entries into a list of snacks.nvim dashboard keys, in place,
    and returns the list: `b` New Rust Binary, `i` New Rust Library, `w` New
    Rust Workspace, `e` New egui Project. The egui entry goes right before
    "Quit" (or last), the other three right before it. Calling it twice adds
    nothing twice; an existing key `e` is respected. Opt-in: nothing happens
    unless you call it. >lua
    {
      "folke/snacks.nvim",
      opts = function(_, opts)
        opts.dashboard = opts.dashboard or {}
        opts.dashboard.preset = opts.dashboard.preset or {}
        opts.dashboard.preset.keys =
          require("xyno_new").dashboard_keys(opts.dashboard.preset.keys or {})
      end,
    }
<
The entries run the commands, so the plugin has to be loaded when they are
pressed (list the commands in lazy.nvim's `cmd`, or use `lazy = false`).'''),
    ...para('--', r'The keymaps section is a literal table of five rows, then the rule for table forms: a table maps only the actions you list (bin, lib, workspace, member, egui) and false skips one. The dashboard section is tagged *xyno_new.dashboard_keys()*, the form in which function tags are written in Neovim’s help (the parentheses are part of the tag), and it ends with a warning that matters in practice: the entries run commands, so the plugin has to be loaded when they are pressed, via lazy.nvim’s cmd or lazy = false. The same sentence is in the README; it is repeated here because this is where a user with a dead dashboard entry will look.'),
    ...sec(r'sections seven to ten'),
    ...code('text', r'doc/xyno-new.txt · lines 171-187', r'''
    xyno_new            setup(opts), dashboard_keys(keys?), defaults,
                        default_keymaps
    xyno_new.rust       setup(), new_project(kind, name?),
                        new_workspace(name?), new_member(name?), running(),
                        name, lib_note, first_line, parse_edition, resolver,
                        workspace_toml, inherit, workspace_info,
                        add_member_path, layout, nesting_warning,
                        cargo_edition(), reset_edition(),
                        create_project(p, cb), create_workspace(p, cb),
                        create_member(p, cb)
    xyno_new.egui       setup(), new(name?), create(p, cb), validate_name,
                        cargo_name, check_author, format_author,
                        edit_cargo_toml, edit_cargo_lock, readme, config(),
                        default_parent(), expand_dir(s), parse_version,
                        check_rust_version(dir, done?) and the other pure text
                        functions
    xyno_new.dashboard  keys(keys?), rust_entries, egui_entry'''),
    ...para('--', r'The Lua API section is a two-column list of module and public functions. It mirrors the README table, and shares its limit: it is hand-written, so it can drift from the code. The names listed for xyno_new.rust and xyno_new.egui are the ones a script can reasonably call, including the creators that take no prompts (create_project, create_workspace, create_member, create) and the pure text functions. Section 8 summarises the design in one paragraph, argv lists, coroutines, pure edits, the cached edition and the resolver rule.'),
    ...code('text', r'doc/xyno-new.txt · lines 201-216', r'''
9. PLATFORMS                                                  *xyno-new-platforms*

Linux: tested by the specs in this repository with a real cargo. Windows: the
Windows branches of the original code are kept (`tar` instead of `unzip`) but
unverified; the specs were skipped whole on Windows in xynovim's CI. macOS: the
specs ran in xynovim's CI, whose macOS runs were not stable overall, so I do not
claim it works.

==============================================================================
10. LICENSE AND ORIGIN                                         *xyno-new-license*

MIT, Copyright (c) 2026 Xynorash. These modules come from xynovim
(https://github.com/xynorash/xynovim), my Neovim configuration for Rust, and
are an independent plugin.

 vim:tw=78:ts=8:ft=help:norl:'''),
    ...para('--', r'Section 9 gives the platform status without rounding up: Linux tested by the specs here with a real cargo; Windows branches kept but unverified, and specs skipped whole on Windows in xynovim’s CI; macOS specs run in xynovim’s CI whose runs were not stable overall, so no claim is made. Section 10 gives the licence and the origin. The file ends with the modeline vim:tw=78:ts=8:ft=help:norl:, which sets the text width, the tab stop, the filetype and non-right-to-left for anyone opening the file for editing.'),
    ...sec(r'how it stays correct'),
    ...para('--', r'The smoke test regenerates doc/tags and then runs :help on xyno-new, xyno-new-setup, xyno-new-api, :RustNewBin, :RustNewLib, :RustNewWorkspace, :RustNewMember, :EguiNew and xyno_new.dashboard_keys(), so a deleted or misspelled tag fails CI. It does not check that the documented defaults equal the code defaults, nor that every function listed in the API section exists. Those two statements are the only ones in the help file that CI cannot catch if they drift.'),
    ...sec(r'history'),
    ...para('--', r'Added in 5f7578c on 2026-10-22 with the README and the CI workflow, as the third commit of the repository.'),
  ],
);
