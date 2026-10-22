import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-macros.nvim/doc/xyno-macros.txt',
  lines: [
    cm('--', r'──────────────────────────────────────────'),
    cm('--', r'xyno-macros.txt — the :help page'),
    cm('--', r'ten sections; every command has a tag; checked by eight :help calls in the smoke test'),
    cm('--', r'──────────────────────────────────────────'),
    kv(r'role', r'Vim help file, :help xyno-macros'),
    kv(r'format', r'Neovim help syntax, textwidth 78'),
    kv(r'size', r'205 lines, 10 sections'),
    kv(r'checked by', r'tests/e2e/smoke.lua opens eight of its tags with :help'),
    kv(r'history', r'added in 7ffb48e (2026-10-22, Add README, help file and CI workflow); blink.cmp pin added '
        r'in 9ab48fb'),
    ...sec(r'why this file exists'),
    ...para('--', r'A plugin with five commands, a data format and an integration with a completion engine '
        r'needs a reference more than a tour. This file is organized around what a user looks up: '
        r'the commands (each with a tag of its own), the keys, the options, the Lua API and the '
        r'blink.cmp integration. It repeats what the README says in the form :help expects.'),
    ...sec(r'commands'),
    ...code('text', r'doc/xyno-macros.txt · lines 98-129', r'''
4. COMMANDS                                                    *xyno-macros-commands*

                                                                *:MacroExpand*
:MacroExpand
    Expand the macro under the cursor (rust-analyzer/expandMacro) in a
    read-only split. <CR> steps into the macro call under the cursor, <BS>
    goes back, `gi` lists the generated items, `q` closes. Falls back to
    `cargo expand` where rust-analyzer expands nothing.

                                                              *:MacroFormatFix*
:MacroFormatFix
    Append the missing arguments (`todo!()`) of the format macro call at the
    cursor.

                                                              *:MacroSignature*
:MacroSignature
    Show the matcher arms of the `macro_rules!` call at the cursor, and the
    format-string and sqlx bind hints. The popup also opens after `(`, `[`,
    `{` or `!` in insert mode.

                                                             *:ProcMacroStatus*
:ProcMacroStatus
    List the proc-macro crates of the workspace, the macros that were not
    expanded and rust-analyzer's view. In the window: `r` rebuilds the proc
    macros, `R` refreshes, `i` or <CR> on a crate writes it to
    `procMacro.ignored` in `rust-analyzer.toml`, <CR> on a diagnostic jumps
    to it, `q` closes.

                                                                 *:MacroAttrs*
:MacroAttrs
    Show what the attribute completion sees at the cursor: attribute, target,
    schemas, where the dependencies came from. For a missing completion.
'''),
    ...para('--', r'Each command’s tag is its colon name, so :help :MacroExpand works, and the smoke test '
        r'opens exactly those tags. The descriptions carry the keys that act inside windows: Enter '
        r'steps into a call in the expansion lens, Backspace goes back, gi lists the generated '
        r'items; in the proc-macro status window r rebuilds, R refreshes, i or Enter ignores a '
        r'crate. These are the facts a user cannot guess and might otherwise find only by reading '
        r'tools.lua.'),
    ...sec(r'completion data'),
    ...code('text', r'doc/xyno-macros.txt · lines 145-153', r'''
==============================================================================
6. COMPLETION DATA                                                  *xyno-macros-data*

One JSON file per crate in `data/macro_attrs/` of the plugin directory (the
format is in `data/macro_attrs/README.md`). A schema applies when the
workspace member depends on the crate, the version is in the range of the file
and the helper is in scope. A project adds or overrides schemas with
`.xyno-macros/attrs/*.json` in the workspace root; |:MacroAttrs| lists broken
files.
'''),
    ...para('--', r'The data section is short on purpose: the format has its own README, and the section '
        r'states the three conditions under which a schema applies (a dependency, a version in '
        r'range, a helper in scope), where a project adds or overrides, and that :MacroAttrs lists '
        r'broken files.'),
    ...sec(r'the Lua API'),
    ...code('text', r'doc/xyno-macros.txt · lines 155-177', r'''
==============================================================================
7. LUA API                                                          *xyno-macros-api*

                                                       *xyno_macros.blink_opts()*
require("xyno_macros").blink_opts({opts})   see |xyno-macros-blink|

                                                            *xyno_macros.attrs*
`require("xyno_macros.attrs")`:
  items({bufnr}, {row}, {col})    the completion items at a position
  shipped()                       crate -> shipped schema file
  schemas({root}?)                shipped schemas with the project's applied
  on_derive_accepted              hook `fn(name, info)` called when a derive
                                  that is not imported was accepted; replace
                                  it to plug in another import
  config                          |xyno-macros-config|

                                                            *xyno_macros.tools*
`require("xyno_macros.tools")`:
  expand(), format_fix(), signature({buf}, {opts}), proc_macro_status()
                                  what the commands call
  lex({text})                     Rust token lexer used by the macro help
  snippets_allowed({ctx})         the snippet guard (|xyno-macros-setup|)

'''),
    ...para('--', r'The API section lists what other code can call: blink_opts, the attrs functions items, '
        r'shipped and schemas, the on_derive_accepted hook that can be replaced to plug in a '
        r'different import mechanism, the config table, and the tools functions behind the '
        r'commands. The smoke test relies on blink_opts, the lexer and the attrs functions listed '
        r'here.'),
    ...sec(r'how it works, platforms'),
    ...code('text', r'doc/xyno-macros.txt · lines 178-198', r'''
==============================================================================
8. HOW IT WORKS                                                      *xyno-macros-how*

A small lexer reads the attribute from its `#[` to the cursor and says which
key or value is being typed. The buffer is parsed with the attribute repaired
so tree-sitter can say what it is attached to. Dependencies come from cargo
metadata once cached and from a scan of `Cargo.toml` until then; nothing
blocks. The macro tools lex Rust tokens, find the `macro_rules!` definition
through the language server and match the call against its arms.

==============================================================================
9. PLATFORMS                                                  *xyno-macros-platforms*

  Linux    tested by the specs of this repository; the completion-menu specs
           need blink.cmp and skip without it
  Windows  the guards of the original code are kept; no evidence from this
           repository; in xynovim's CI the live rust-analyzer flows, among
           them the macro tool specs, failed or hung there
  macOS    nothing tested here; the live macro tool specs hung once in
           xynovim's CI and the macOS runs were not stable

'''),
    ...para('--', r'The how-it-works paragraph is the README’s in seven lines. The platforms block is a table '
        r'in text form, a form help files use well: Linux tested, Windows with no evidence, macOS '
        r'with nothing tested and the history of instability.'),
    ...sec(r'the blink.cmp note'),
    ...para('--', r'The last commit, 9ab48fb, added a short paragraph to the blink.cmp section: pin blink.cmp '
        r'to 1.* because 2.x refuses to load without saghen/blink.lib, and note that the spec loads '
        r'xyno-macros when blink.cmp starts, so the plugin is not lazy-loaded by filetype or '
        r'command. It sits in the blink.cmp section of the help file.'),
    ...sec(r'history'),
    ...pt('--', r'7ffb48e', r'2026-10-22: added with the README and the workflow.'),
    ...pt('--', r'9ab48fb', r'2026-10-22: the blink.cmp pin, five added lines in the help file.'),
  ],
);
