import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-imports.nvim/doc/xyno-imports.txt',
  lines: [
    heading(r'''xyno-imports.txt: the :help file'''),
    blank,
    ...text(r'''A Vim help file is documentation that lives inside the editor, found with :help and linked by tags. This one is 161 lines, nine numbered sections, and it is the reference the README points at. It was added with the README and the CI workflow in 9373a52 on 2026-10-22.'''),
    blank,
    kv(r'''role''', r'''in-editor reference: :help xyno-imports'''),
    kv(r'''format''', r'''Vim help, tw=78, ft=help; tags generated into doc/tags'''),
    kv(r'''sections''', r'''9, with a contents block of links'''),
    kv(r'''checked by''', r'''tests/e2e/smoke.lua runs :help on six tags'''),
    ...sec(r'''why a help file for a plugin with a README'''),
    ...text(r'''A README is read on GitHub before installing. A help file is read inside Neovim and ships with the installed version of the plugin. For a plugin whose behaviour depends on a mode, a global variable and a table of tuning numbers, the second reader matters: someone who just saw an Import prompt and wants to know why it did not appear for another name should be able to type :help xyno-imports-mode.'''),
    blank,
    ...text(r'''The help file and the README overlap on purpose, and they differ in what each gains by being short or long. The README has the install block, a longer platforms section and the extraction story; the help file has the API table and the contents block. When they disagree, the code wins, and the page for engine.lua is written from the code.'''),
    blank,
    ...sec(r'''the contents block and the tags'''),
    ...text(r'''The first lines declare the main tag and a contents block. In Vim help, a word between asterisks is a tag you can jump to, and a word between pipes is a link to one. The header line carries the first tag, and every section heading ends with its own tag at the right margin.'''),
    blank,
    ...code('text', r'doc/xyno-imports.txt · lines 1-1, 6-16', r'''
*xyno-imports.txt*  Imports without the menu for Rust: auto-import, ranked choice, organize
...
CONTENTS                                                    *xyno-imports-contents*

  1. Introduction ............................. |xyno-imports|
  2. Requirements ............................. |xyno-imports-requirements|
  3. Setup and options ........................ |xyno-imports-setup|
  4. Commands ................................. |xyno-imports-commands|
  5. Keymaps .................................. |xyno-imports-keymaps|
  6. Lua API .................................. |xyno-imports-api|
  7. How it works ............................. |xyno-imports-how|
  8. Platforms ................................ |xyno-imports-platforms|
  9. License and origin ....................... |xyno-imports-license|'''),

    ...text(r'''Eighteen tags are defined, one per section plus the commands and API entries, including :ImportName, :ImportForget and :ImportOrganize for the commands, xyno_imports.setup() and xyno_imports.engine for the API, and xyno-imports-mode and xyno-imports-config for the two things people ask about most. The smoke test checks six of them with :help, so a renamed tag fails CI instead of becoming a dead link.'''),
    blank,
    ...sec(r'''section 3: setup, mode and config'''),
    ...text(r'''The setup block repeats the defaults in a code block. In Vim help, a line that ends in > opens a code block and a line with only < closes it, and the optional lua after the > names the language for highlighting. The mode subsection uses a hanging-indent table because the three modes need a sentence each.'''),
    blank,
    ...code('text', r'doc/xyno-imports.txt · lines 45-45, 53-53', r'''
>lua
...
Safe to call again.'''),

    ...code('text', r'doc/xyno-imports.txt · lines 56-56, 65-65', r'''
`mode` decides what happens to a name that resolves to nothing, after
...
Several candidates are never guessed at: use |:ImportName|.'''),

    ...text(r'''The sentence worth rereading is the last: several candidates are never guessed at. It is the plugin policy in a line, and it matches decide() in engine.lua, where only a single candidate or a remembered choice can turn into an action.'''),
    blank,
    ...sec(r'''section 3 again: the numbers'''),
    ...text(r'''The config table lists the seven tuning numbers with defaults and one-phrase meanings. They are the same values as M.config in engine.lua, and init.lua only overwrites keys that exist there. Two of them have reasons worth knowing. max_lines exists because the tree-sitter scan reads the whole buffer on every edit; it came from a field test in xynovim (b474307). retries and retry_ms exist because rust-analyzer answers ContentModified while it re-analyses, which is exactly when an InsertLeave scan asks.'''),
    blank,
    ...code('text', r'doc/xyno-imports.txt · lines 71-78', r'''
  debounce         600    ms between the last change and the scan
  max_names        8      names looked at per scan
  retries          5      retries of a "content modified" code action request
  retry_ms         400
  organize_rounds  30
  max_lines        20000  the scan reads the whole buffer per edit: skipped
                          above this
  source_wait_ms   4000   how long `resolve()` waits for asynchronous sources'''),

    ...sec(r'''section 4 and 5: commands and keymaps'''),
    ...text(r'''Each command has its own tag so :help :ImportName works. :ImportName says the choice is remembered and "wins from then on (picker order, single auto-import)": two separate effects of one stored value. :ImportOrganize is described as the merge, normalize and remove-unused assists applied in one undo step. The keymaps section is short and firm: no global keymap is set, keymaps = true maps two keys buffer-locally in Rust files, and a table maps only the actions listed, with false skipping one, with a worked example.'''),
    blank,
    ...code('text', r'doc/xyno-imports.txt · lines 101-101, 107-107', r'''
No global keymap is set. `keymaps = true` maps, buffer-local in Rust files:
...
one): `{ import = "<leader>ci", organize = false }`.'''),

    ...sec(r'''section 6: the Lua API'''),
    ...text(r'''The API table is the list of functions meant for other code. Reading it next to engine.lua shows what is public by promise and what is only public by accident: M.flatten_use, M.use_paths, M.scan_syntax and others are reachable in Lua but not listed. resolve is described with its result fields, name, candidates, best, remembered, choice, unambiguous and root, and with the rule that ctx.cb makes it asynchronous. register_source gets the shape of a candidate and the two guarantees that matter to a source author: its candidates rank last and are never applied automatically.'''),
    blank,
    ...code('text', r'doc/xyno-imports.txt · lines 116-116, 131-131', r'''
resolve({name}, {ctx})      ranked candidates of a name:
...
config                      the tuning table (|xyno-imports-config|)'''),

    ...sec(r'''sections 7 to 9: how it works, platforms, origin'''),
    ...text(r'''The how-it-works section is an eight-line paragraph that names every input to the ranking: the use lines of the file, sibling modules and crate, the context of the name, the order of the dependencies, and the penalty for a crate not yet a dependency. It also names the state file path and the undo guard, the two things people stumble on. The platforms section is a three-row table that says what the repository can show: Linux tested here, Windows with guards kept but no evidence from this repository, macOS with a known timing issue in xynovim CI.'''),
    blank,
    ...text(r'''The last section is licence and origin in two lines, MIT, Copyright (c) 2026 Xynorash, extracted from xynovim. The modeline in the final line, vim:tw=78:ts=8:ft=help:norl:, tells Vim to treat the file as help even if it is opened outside the doc directory.'''),
    blank,
    ...code('text', r'doc/xyno-imports.txt · lines 161-161', r'''
 vim:tw=78:ts=8:ft=help:norl:'''),

    ...sec(r'''limits of this file'''),
    ...bullet(r'''doc/tags is generated''', r'''the smoke test runs helptags for the doc directory before the :help checks; the repository does not rely on a committed tags file for CI.'''),
    ...bullet(r'''Some details are README only''', r'''the extraction story, the longer platform notes and the install block are not in the help file.'''),
    ...bullet(r'''Public-by-promise''', r'''the API list is a promise, not enforced. Nothing prevents using M.score or M.decide, and the README lists them too.'''),
    ...sec(r'''history'''),
    ...bullet(r'''9373a52 2026-10-22''', r'''"Add README, help file and CI workflow": the file arrives with 161 lines and has not changed since.'''),
  ],
);
