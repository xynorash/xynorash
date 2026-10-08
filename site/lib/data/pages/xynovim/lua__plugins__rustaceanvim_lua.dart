import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/lua/plugins/rustaceanvim.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', 'rustaceanvim.lua — rust-analyzer, tuned instead of defaulted'),
    cm('--', 'the instant half of a two-tier diagnostics design'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv('role', 'overrides rust-analyzer’s settings inside LazyVim’s lang.rust extra'),
    kv('language', 'Lua (a lazy.nvim spec that overrides mrcjkb/rustaceanvim opts)'),
    kv('size', '38 lines: 26 of code, 12 of comment'),
    kv('history', '3 commits: 2026-09-02, then twice on 2026-09-03 (07:05 and 19:54)'),
    kv('measured', 'instant tier 155-235 ms warm; clippy tier 0.56 s median warm'),
    ...sec('why this file exists'),
    ...para('--',
        r'LazyVim’s lang.rust extra is the Rust setup of this config. '
        r'CHANGELOG 1.0.0 lists what it brings: rustaceanvim, '
        r'rust-analyzer, crates.nvim and codelldb, all via Mason. That '
        r'replaced a hand-rolled lsp.lua of the earlier Windows lineage. '
        r'The extra supplies defaults, so this file holds the '
        r'opinions: which rust-analyzer features run, what they cost, '
        r'and how they share a machine with cargo in a terminal.'),
    blank,
    ...para('--',
        r'The mechanism is plain lazy.nvim. A spec that names the same '
        r'plugin as the extra, mrcjkb/rustaceanvim, has its opts merged '
        r'into the extra’s. The path server.default_settings then '
        r'["rust-analyzer"] is the table that rustaceanvim hands to '
        r'rust-analyzer as its configuration. Everything this page '
        r'discusses is a key inside that one table.'),
    ...code('lua', 'lua/plugins/rustaceanvim.lua · the shape of the override (trimmed)', r'''
return {
  "mrcjkb/rustaceanvim",
  opts = {
    server = {
      default_settings = {
        ["rust-analyzer"] = {
          ...
        },
      },
    },
  },
}'''),

    ...sec('three versions of the same 38 lines'),
    ...para('--',
        r'The file is short, but it has been rewritten twice in two '
        r'days, and the changes are the design. In order:'),
    blank,
    cm('--', '  2026-09-02 23:42  eabb22a  1.0.0, the migration'),
    cm('--', '    check = clippy with --no-deps (clippy on save);'),
    cm('--', '    diagnostics on, with styleLints; inlay hints;'),
    cm('--', '    imports; completion. 39 lines.'),
    cm('--', '  2026-09-03 07:05  3ec11c4  1.1.0, bacon-ls arrives'),
    cm('--', '    check and diagnostics blocks deleted: the extra disables'),
    cm('--', '    them and bacon-ls now owns clippy. Hints, imports and'),
    cm('--', '    completion stay.'),
    cm('--', '  2026-09-03 19:54  f35b4f6  1.3.0, two tiers'),
    cm('--', '    diagnostics = { enable = true } back, without styleLints;'),
    cm('--', '    cargo.targetDir = true added. 38 lines.'),
    blank,
    ...para('--',
        r'The first version asked rust-analyzer to do everything. Its '
        r'comment, still readable in git history, explained clippy as '
        r'“the full lint set (what RustRover’s inspections roughly '
        r'correspond to)” and added “--no-deps keeps saves fast”. That '
        r'is clippy on save, driven by rust-analyzer. The second '
        r'version removed the check and diagnostics blocks entirely '
        r'because bacon-ls took over live clippy (lua/plugins/'
        r'bacon-ls.lua), and, in CHANGELOG 1.1.0’s words, the old '
        r'blocks “would fight the extra’s disables”. The third '
        r'version put a deliberately smaller piece back.'),

    ...sec('the instant tier'),
    ...code('lua', 'lua/plugins/rustaceanvim.lua · diagnostics', r'''
          -- Two diagnostic tiers: rust-analyzer's NATIVE diagnostics are
          -- computed in-memory as you type (no cargo run) - instant type
          -- errors, unresolved names, typos. Clippy depth still comes from
          -- bacon-ls ~1s later (see bacon-ls.lua). checkOnSave stays off
          -- (the extra disables it) so no cargo pipeline is duplicated;
          -- overlap is only visual: a type error may briefly show from both
          -- sources. styleLints stay off - that's clippy's job.
          diagnostics = { enable = true },'''),
    ...para('--',
        r'This is the design in seven lines of comment and one line of '
        r'code. There are two kinds of Rust feedback and they come from '
        r'different machinery:'),
    ...pt('--', 'type-level errors',
        r'unresolved names, type mismatches, typos. rust-analyzer '
        r'knows these from its own in-memory model of the code, so '
        r'it can report them with no cargo process at all.'),
    ...pt('--', 'lints',
        r'“is this good Rust?” needs clippy, which needs a cargo run '
        r'against real files. That is bacon-ls’s job, with the shadow '
        r'workspace trick on lua/plugins/bacon-ls.lua.'),
    blank,
    ...para('--',
        r'Putting each kind of check on the cheapest machinery that can '
        r'do it gives a pair of latencies instead of one, and the '
        r'CHANGELOG measured both:'),
    blank,
    cm('--', '  tier       source                       edit to diagnostic'),
    cm('--', '  ---------  ---------------------------  ------------------'),
    cm('--', '  instant    rust-analyzer, in memory     155-235 ms warm'),
    cm('--', '  depth      bacon-ls, clippy on shadow   0.56 s median warm'),
    cm('--', '  before     two clippy pipelines racing  5.6 s'),
    blank,
    ...para('--',
        r'The 155-235 ms figure is from CHANGELOG 1.3.0 and carries its '
        r'method in a parenthesis: “real keystrokes, clean-state '
        r'probes”. The other two are discussed on the bacon-ls page. '
        r'Neither is a benchmark of the editor; they are the kind of '
        r'number that tells you whether the feature feels live.'),
    blank,
    ...para('--',
        r'Three decisions inside the comment deserve attention.'),
    ...pt('--', 'checkOnSave stays off',
        r'rust-analyzer’s own on-save check would be a second cargo '
        r'pipeline next to bacon-ls. The comment records that the extra '
        r'already disables it, so this file adds nothing for it and '
        r'avoids repeating the mistake of the first design.'),
    ...pt('--', 'duplicate display is accepted',
        r'“a type error may briefly show from both sources.” The '
        r'alternative was to suppress one source and risk showing '
        r'nothing in a gap. A duplicated message is a cosmetic flaw; a '
        r'missing one is a correctness flaw, and the config chooses '
        r'the cosmetic one on purpose.'),
    ...pt('--', 'styleLints stay off',
        r'the 1.0.0 version had styleLints = { enable = true }. It '
        r'was dropped because style is what clippy is for and bacon-ls '
        r'provides it. The current file simply does not mention '
        r'styleLints, so rust-analyzer’s default applies.'),

    ...sec('a separate target directory'),
    ...code('lua', 'lua/plugins/rustaceanvim.lua · targetDir', r'''
          -- Separate target dir for rust-analyzer's own cargo runs (build
          -- scripts, proc-macros) so they never contend for the build-dir
          -- file lock with terminal `cargo run`/`cargo test`.
          cargo = { targetDir = true },'''),
    ...para('--',
        r'Turning checkOnSave off removed rust-analyzer’s clippy runs, '
        r'but not all of its cargo use: it still runs build scripts and '
        r'proc-macro builds to understand the code. Cargo guards its '
        r'build directory with a file lock, so two cargo processes on '
        r'one target directory wait for each other (cargo’s familiar '
        r'“blocking waiting for file lock on build directory”). If '
        r'rust-analyzer is mid-build when you type cargo test in a '
        r'terminal, one of them stalls.'),
    blank,
    ...para('--',
        r'targetDir = true gives rust-analyzer its own subdirectory '
        r'(CHANGELOG 1.3.0: “rust-analyzer’s build-script runs use '
        r'their own target subdir”), so the two never share a lock. '
        r'It is the same lesson as the bacon-ls work applied one more '
        r'time: when two tools share one resource they share its lock, '
        r'and “why is cargo waiting?” is the first question to ask. '
        r'The trade-off is disk and first-run time, since the second '
        r'directory builds its own copy of whatever rust-analyzer '
        r'needs. The notes do not quantify that cost, so that part is '
        r'my inference.'),

    ...sec('inlay hints'),
    ...code('lua', 'lua/plugins/rustaceanvim.lua · inlayHints', r'''
          -- RustRover-style inline type/lifetime annotations.
          inlayHints = {
            closureReturnTypeHints = { enable = "with_block" },
            lifetimeElisionHints = { enable = "skip_trivial", useParameterNames = true },
            expressionAdjustmentHints = { enable = "never" },
          },'''),
    ...para('--',
        r'Inlay hints are the grey annotations rust-analyzer draws '
        r'inside the code. The goal in the comment is to match what '
        r'RustRover shows, and each of the three settings narrows a '
        r'noisy default to its useful core.'),
    ...pt('--', 'closureReturnTypeHints = "with_block"',
        r'show the return type of a closure only when the closure has '
        r'a block body, where the type is not visible at a glance. '
        r'The earlier Windows config used "always", which annotates '
        r'every one-liner closure too.'),
    ...pt('--', 'lifetimeElisionHints = "skip_trivial"',
        r'show the lifetimes the compiler infers, but skip the '
        r'trivial cases. useParameterNames = true prefers parameter '
        r'names over numbered placeholders (my reading of the '
        r'rust-analyzer option).'),
    ...pt('--', 'expressionAdjustmentHints = "never"',
        r'implicit adjustments such as automatic borrows and '
        r'derefs are not drawn. The notes record no reason; the '
        r'setting is written out, which suggests it was deliberate.'),
    blank,
    ...para('--',
        r'The older lsp.lua also enabled typeHints, bindingModeHints '
        r'and parameterHints by hand; the current file sets none of '
        r'those, and leaves them at whatever the extra and '
        r'rust-analyzer default to. Whether hints are displayed at all '
        r'is not decided here either: the older config had an '
        r'LspAttach autocmd turning them on for every client that '
        r'supports them, and lua/config/autocmds.lua has no such '
        r'autocmd now, so I infer that the switch is left to LazyVim.'),

    ...sec('imports and completion'),
    ...code('lua', 'lua/plugins/rustaceanvim.lua · imports, completion', r'''
          -- Completion niceties: auto-import granularity + fill call args.
          imports = {
            granularity = { group = "module" },
            prefix = "self",
          },
          completion = {
            callable = { snippets = "fill_arguments" },
            fullFunctionSignatures = { enable = true },
          },'''),
    ...pt('--', 'imports.granularity.group = "module"',
        r'when rust-analyzer adds a use for you, it merges new '
        r'imports per module instead of adding one line each. '
        r'CHANGELOG 1.0.0 calls this “module-grouped auto-imports”.'),
    ...pt('--', 'imports.prefix = "self"',
        r'the form of the inserted paths: module-relative, with a '
        r'self:: prefix where the path starts with a module. This is '
        r'my reading of the rust-analyzer option, not a claim '
        r'the repo documents.'),
    ...pt('--', 'completion.callable.snippets = "fill_arguments"',
        r'accepting a completion for a function inserts the call with '
        r'its arguments as tab-stops, “fill-arguments completion '
        r'snippets” in the changelog.'),
    ...pt('--', 'completion.fullFunctionSignatures',
        r'completion items show the full function signature (CHANGELOG '
        r'1.0.0: “full function signatures”).'),
    blank,
    ...para('--',
        r'These four lines are ergonomics, not performance, and they '
        r'have not moved since the migration commit. They are what '
        r'survived all three versions of the file, which is a fair '
        r'sign that they are preferences and not workarounds.'),

    ...sec('what lives outside this file'),
    ...para('--',
        r'Two Rust build-speed settings are not in this repo at all. '
        r'CHANGELOG 1.3.0 and the README document them '
        r'because they live in ~/.cargo/config.toml:'),
    ...pt('--', 'mold via clang',
        r'a faster linker. The changelog says linking was verified '
        r'with readelf, and the README says it links “several times '
        r'faster”, benefiting every clippy, test and run cycle.'),
    ...pt('--', 'profile.dev.debug = "line-tables-only"',
        r'backtraces keep file and line, but the heavyweight '
        r'debuginfo is not generated. Existing projects full-rebuild '
        r'once after this change. The README’s caution matters for '
        r'anyone using the codelldb debugger from the extra: set full '
        r'debug info per project when you need it.'),
    blank,
    ...para('--',
        r'They belong on this page because they act on the same loop, '
        r'every cargo invocation that rust-analyzer, bacon-ls and the '
        r'terminal all trigger. They are outside the repo because '
        r'~/.cargo/config.toml is a user-level file, so the repo can '
        r'only describe it. If you clone this config, those two '
        r'settings do not come with it.'),

    ...sec('how it was checked'),
    ...para('--',
        r'The record is in the changelog and not in a test file. For '
        r'this file the claims are:'),
    ...pt('--', 'instant tier',
        r'measured at 155-235 ms warm with real keystrokes and '
        r'clean-state probes (1.3.0). My reading of “clean-state” is a '
        r'probe that starts with no diagnostics showing, so the first '
        r'one to appear is attributable to the edit.'),
    ...pt('--', 'no pipeline duplicated',
        r'checkOnSave remains off (1.3.0), so the sub-second clippy '
        r'numbers on the bacon-ls page still hold after the instant '
        r'tier was added.'),
    ...pt('--', 'targetDir',
        r'described as removing contention with terminal cargo '
        r'commands. The notes do not include a before-and-after '
        r'measurement for it; it is a design fix for a known cause '
        r'rather than a tuned number.'),

    ...sec('limits'),
    ...pt('--', 'a visible overlap',
        r'the same type error can appear from rust-analyzer first and '
        r'from bacon-ls after it. This is the known and accepted cost.'),
    ...pt('--', 'tests are not covered by the live clippy tier',
        r'bacon-ls runs without --all-targets (see its page), so '
        r'there is no live clippy depth inside test code while '
        r'typing.'),
    ...pt('--', 'one extra, one machine',
        r'the settings assume the lang.rust extra’s defaults. If the '
        r'extra changes how it treats diagnostics, the comment “the '
        r'extra disables it” is the line to re-verify.'),
    ...pt('--', 'no hints reason recorded',
        r'expressionAdjustmentHints and imports.prefix have no '
        r'rationale in the commit messages or the changelog.'),
    blank,
    ...para('--',
        r'What this file demonstrates is the habit rather than the '
        r'settings. Every setting is the answer to a question the '
        r'notes pose: which tool is cheapest for this kind of '
        r'feedback, and who else is contending for the same resource. '
        r'The file ended a line shorter than it began while the '
        r'measured behaviour improved.'),
    blank,
    link('→ github.com/XNash/xynovim', 'https://github.com/XNash/xynovim'),
  ],
);
