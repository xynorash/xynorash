import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-macros.nvim/README.md',
  summary: r'Rust macro help in Neovim: attribute and derive completion from schemas, macro_rules! '
        r'signature help, :MacroExpand',
  repo: 'xyno-macros.nvim',
  fallbackStars: 0,
  fallbackPushed: '2026-10-22',
  lines: [
    heading(r'# xyno-macros.nvim'),
    blank,
    ...text(r'Rust macro help in Neovim. Completion inside helper attributes and derives '
        r'(#[serde(...)], #[arg(...)], #[derive(...)]) from small JSON schemas for ten crates, a '
        r'signature popup for macro_rules! calls that shows which arm your arguments fit, '
        r'format-string and sqlx bind hints, :MacroExpand in a read-only split with stepping into '
        r'nested calls, and :ProcMacroStatus for the proc-macro crates and the macros that did not '
        r'expand. About 4,400 lines of Lua, 10 schemas, 103 test blocks.'),
    kv(r'language', r'Lua, Neovim 0.12+, tree-sitter rust'),
    kv(r'needs', r'xyno-rust.nvim, xyno-imports.nvim, rust-analyzer, cargo; blink.cmp optional'),
    kv(r'data', r'10 crates: serde, clap, tokio, sqlx, thiserror, derive_more, strum, bon, schemars, utoipa'),
    kv(r'size', r'attrs.lua 1,846 lines, tools.lua 2,515 lines, init.lua 71 lines'),
    kv(r'tests', r'103 it() blocks in 3 spec files plus a lazy.nvim smoke test'),
    kv(r'history', r'4 commits, all on 2026-10-22; the modules began on 2026-10-14 in xynovim'),
    kv(r'origin', r'extracted from xynovim, lua/config/macro_attrs.lua and macro_tools.lua'),
    ...sec(r'the problem'),
    ...text(r'rust-analyzer returns nothing inside #[serde(...)] or #[arg(...)], so the keys and the '
        r'enumerated values (rename_all = "camelCase") are typed from memory. A proc-macro that is '
        r'slow or broken shows up only as a missing expansion. And while you write a call to a '
        r'macro_rules! macro you do not see its arms. The author’s own sentence is the best '
        r'summary: this plugin completes those attributes from small schemas per crate, shows the '
        r'arms of a macro_rules! while you write a call, expands the macro under the cursor, and '
        r'lists the proc-macro crates and the macros rust-analyzer could not expand. The README '
        r'also says the macro expansion view and the macro-aware completion are inspired by what '
        r'the JetBrains Rust tooling does with macros, and that this is an independent project.'),
    ...sec(r'the ideas'),
    ...text(r'- Completion is data. A schema is a JSON file for one crate: attributes, the keys they '
        r'take, the kinds of the values, which item each applies to, which keys conflict, which '
        r'need others, and the version since which a key exists. No Lua knowledge of serde lives in '
        r'the code.'),
    ...text(r'- Completion is context. A schema is used only when the workspace member depends on the '
        r'crate, the resolved version fits the range, and the helper is in scope, because a derive '
        r'that brings it is on the item. Where no schema exists, the keys the project and the '
        r'dependency’s own sources already write are offered by frequency.'),
    ...text(r'- Macro help is a matcher. The arms of a macro_rules! definition are compiled, and the '
        r'typed arguments are matched against them with three outcomes (complete, still possible, '
        r'impossible), so a half-typed call highlights the arm it is heading for.'),
    ...text(r'- Everything is bounded. Files, bytes, lines, retries and matcher steps all have named '
        r'limits, and nothing in the completion path waits for cargo.'),
    ...sec(r'the shape of the repository'),
    plain(r'xyno-macros.nvim/'),
    plain(r'├── lua/xyno_macros/'),
    plain(r'│   ├── init.lua      setup(), the dependency check, blink_opts()'),
    plain(r'│   ├── attrs.lua     attribute and derive completion (1,846 lines)'),
    plain(r'│   └── tools.lua     lexer, hints, matcher, popup, lens, proc-macro report (2,515 lines)'),
    plain(r'├── data/macro_attrs/'),
    plain(r'│   ├── README.md     the schema format'),
    plain(r'│   └── serde, clap, tokio, sqlx, thiserror, derive_more, strum, bon, schemars, utoipa .json'),
    plain(r'├── tests/'),
    plain(r'│   ├── attrs_spec.lua · tools_spec.lua · init_spec.lua'),
    plain(r'│   ├── e2e/init.lua · e2e/smoke.lua      lazy.nvim loads it with its two dependencies'),
    plain(r'│   ├── run.lua · harness.lua · helpers.lua · fixtures/deps-lab'),
    plain(r'├── doc/xyno-macros.txt                   :help xyno-macros'),
    plain(r'├── .github/workflows/ci.yml              pinned Neovim, plugins, blink.cmp, tree-sitter parser'),
    plain(r'└── README.md · LICENSE · .stylua.toml · .gitignore'),
    ...sec(r'requirements, stated honestly'),
    ...code('markdown', r'README.md · lines 13-23', r'''
## Requirements

- Neovim 0.12+
- [xyno-rust.nvim](https://github.com/xynorash/xyno-rust.nvim) (modules `crate_meta`, `code_actions`, `fsutil`, `rust_context`)
- [xyno-imports.nvim](https://github.com/xynorash/xyno-imports.nvim) (the import of an accepted derive goes through its engine)
- rust-analyzer started through `vim.lsp` (I use [rustaceanvim](https://github.com/mrcjkb/rustaceanvim)); the proc-macro rebuild key of the status window uses its `:RustLsp`
- `cargo` in `$PATH` (workspace and dependency metadata); `cargo-expand` is the fallback of `:MacroExpand` where rust-analyzer expands nothing
- the tree-sitter `rust` parser
- optional: [blink.cmp](https://github.com/Saghen/blink.cmp) for the completion sources (attributes, derives, snippets)

`setup()` checks the two plugins and shows one error line, not a Lua error, if one is missing.
'''),
    ...text(r'The two plugin dependencies are the cost of the extraction: the cargo metadata, '
        r'code-action and file helpers live in xyno-rust.nvim, and the import engine in '
        r'xyno-imports.nvim. setup() checks for them and shows one error line, not a Lua error, if '
        r'one is missing; the smoke test verifies it.'),
    ...sec(r'install'),
    ...code('markdown', r'README.md · lines 27-46', r'''
```lua
{
  "xynorash/xyno-macros.nvim",
  dependencies = { "xynorash/xyno-rust.nvim", "xynorash/xyno-imports.nvim" },
  ft = "rust",
  cmd = { "MacroExpand", "MacroFormatFix", "MacroSignature", "ProcMacroStatus", "MacroAttrs" },
  opts = {},
  keys = {
    { "<leader>rx", "<cmd>MacroExpand<cr>", ft = "rust", desc = "Expand macro under cursor" },
    { "<leader>rq", "<cmd>ProcMacroStatus<cr>", ft = "rust", desc = "Proc-macro status" },
  },
},
{
  "saghen/blink.cmp",
  version = "1.*", -- blink.cmp 2.x needs saghen/blink.lib too; the sources are written against 1.x
  opts = function(_, opts)
    return require("xyno_macros").blink_opts(opts)
  end,
},
```
'''),
    ...text(r'The blink.cmp spec is where the plugin is wired in: blink_opts adds two providers, one '
        r'for attributes and derives and one for snippets. The text under the example is unusually '
        r'frank. Because the blink spec requires xyno_macros when blink starts, the plugin loads at '
        r'startup, and blink.cmp is pinned to 1.* because 2.x refuses to load without another '
        r'library and the sources were only tried against 1.x. That sentence was added by the last '
        r'commit, 9ab48fb.'),
    ...sec(r'options'),
    ...code('markdown', r'README.md · lines 56-63', r'''
```lua
{
  commands = true,         -- :MacroAttrs :MacroExpand :MacroFormatFix :MacroSignature :ProcMacroStatus
  keymaps = false,         -- false | true | { expand = lhs|false, status = lhs|false, signature = lhs|false }
  snippets_allowed = nil,  -- function(ctx) -> boolean: where the select!/matches!/vec! snippets may appear
  attrs = {},              -- tuning of the attribute completion, see below
}
```
'''),
    ...code('markdown', r'README.md · lines 73-75', r'''
```lua
opts = function(_, opts) return require("xyno_macros").blink_opts(opts) end
```
'''),
    ...text(r'No global key unless asked: keymaps = true maps the expand key, the status key and an '
        r'insert-mode key, buffer-local in Rust buffers that have a rust-analyzer client. The '
        r'snippet guard is a function you can replace, and the README says what the default does '
        r'not do: it does not carry over the original configuration’s own expression-node check.'),
    ...sec(r'commands'),
    ...code('markdown', r'README.md · lines 79-87', r'''
## Commands

| Command | What it does |
| --- | --- |
| `:MacroExpand` | Expand the macro under the cursor (rust-analyzer's `expandMacro`) in a read-only split. `<CR>` steps into the macro call under the cursor, `<BS>` goes back, `gi` lists the generated items, `q` closes. Falls back to `cargo expand` where rust-analyzer expands nothing. |
| `:MacroFormatFix` | Append the missing arguments (`todo!()`) of the format macro call at the cursor. |
| `:MacroSignature` | Show the matcher arms of the `macro_rules!` call at the cursor (found with go-to-definition), plus format-string and sqlx bind hints. The popup also opens by itself after `(`, `[`, `{` or `!` in insert mode. |
| `:ProcMacroStatus` | List the proc-macro crates of the workspace, the macros that were not expanded, and rust-analyzer's view. In the window: `r` rebuilds proc macros, `R` refreshes, `i` or `<CR>` on a crate writes it to `procMacro.ignored` in `rust-analyzer.toml`, `<CR>` on a diagnostic jumps to it, `q` closes. |
| `:MacroAttrs` | Show what the attribute completion sees at the cursor (attribute, target, schemas, where the dependencies came from), for finding out why a completion is missing. |
'''),
    ...text(r'Five commands cover the surface. :MacroAttrs is the one meant for debugging: it tells you '
        r'why a completion is missing.'),
    ...sec(r'the data'),
    ...code('markdown', r'README.md · lines 91-91', r'''
One JSON file per crate in `data/macro_attrs/` (serde, clap, tokio, sqlx, thiserror, derive_more, strum, bon, schemars, utoipa), format in [data/macro_attrs/README.md](data/macro_attrs/README.md). A schema is used only when the workspace member depends on the crate, within the version range of the file, and when the helper attribute is in scope (a derive that brings it is on the item, or the attribute macro is named or imported). A project overrides or adds schemas with `.xyno-macros/attrs/*.json` in the workspace root. For dependency crates without a schema, keys that the workspace and the crate's own sources already write inside that attribute are offered, by frequency. `#[derive(` completes the built-in derives and the derive macros found in the dependencies' proc-macro sources; accepting one that is not imported asks the xyno-imports engine for the `use`.
'''),
    ...text(r'The schema format has its own page in data/macro_attrs/README.md, and a project can '
        r'override or add schemas without touching the plugin.'),
    ...sec(r'how it works'),
    ...code('markdown', r'README.md · lines 95-95', r'''
A small lexer reads the attribute from its `#[` to the cursor (strings, nesting, `key = value` entries) and says which key or value is being typed. The buffer is then parsed with the attribute repaired (closing quote and brackets appended) so tree-sitter can say what it is attached to. Dependencies come from cargo metadata once cached, from a scan of `Cargo.toml` until then, and never block. The macro tools use a lexer for Rust tokens, find the `macro_rules!` definition through the language server, and match the call against its arms.
'''),
    ...sec(r'platforms, carefully'),
    ...code('markdown', r'README.md · lines 99-101', r'''
- Linux: tested by the specs in this repository (`nvim -l tests/run.lua`): the lexer, schema, matcher and report logic table-wise, plus cases against a real rust-analyzer on a small fixture crate where rust-analyzer, cargo and the registry crates are available (they skip with a printed reason otherwise). The completion-menu specs need blink.cmp and skip without it.
- Windows: the guards of the original code are kept, but I have no evidence for them from this repository. In xynovim's CI the Windows job passed overall (run 39673715062) while the live rust-analyzer flows, including the live part of the macro tool specs, failed or hung there as a known issue; I do not claim the live part works on Windows.
- macOS: nothing tested here. In xynovim's CI the live part of the macro tool specs hung on macOS in one run (39668277143, passed in earlier ones) and the rust-analyzer import spec of the attribute completion timed out; the macOS runs were not stable, so I do not claim it works.
'''),
    ...text(r'The README declines to claim Windows and macOS. It cites the CI run numbers where the '
        r'live rust-analyzer flows failed or hung, and says the macOS runs were not stable. The '
        r'spec marks those tests as known issues on those platforms.'),
    ...sec(r'where it came from'),
    ...text(r'The modules began in xynovim on 2026-10-14 in b9363cd, as config.macro_attrs and '
        r'config.macro_tools, in the commit that also added dependency freshness, crate add and the '
        r'import engine. A review-fix commit followed (19f974c, 2026-10-15), then Windows and macOS '
        r'fixes (ff1c8fa on 2026-10-16 and 6524272 on 2026-10-21). The extraction renamed the '
        r'namespace, made setup take options, made the keys opt-in, registered the blink.cmp '
        r'sources through blink_opts, read the schema directory from the plugin directory, renamed '
        r'the project override directory to .xyno-macros/attrs, and added a built-in snippet guard.'),
    ...sec(r'try it'),
    ...text(r'- Open a Rust file with serde in the dependencies, type #[derive(Serialize)] on a struct, '
        r'then #[serde( on a field and watch the menu.'),
    ...text(r'- Call a macro_rules! macro and type its arguments to see the popup pick an arm.'),
    ...text(r'- :MacroExpand on a println!; Enter steps into nested calls, Backspace goes back.'),
    ...text(r'- nvim -l tests/run.lua runs the specs (xyno-rust.nvim and xyno-imports.nvim as siblings '
        r'or via XYNO_RUST_DIR and XYNO_IMPORTS_DIR).'),
  ],
);
