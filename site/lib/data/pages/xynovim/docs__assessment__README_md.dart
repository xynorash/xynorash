import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/docs/assessment/README.md',
  lines: [
    heading('# Assessment probes'),
    blank,
    ...text('docs/assessment/README.md is the index card of five headless Lua scripts. They are the instruments behind the measurements in PLAN_MACROS_DEPS.md: scripts that drive a real rust-analyzer through Neovim against a throwaway crate and print what they see. The README is 23 lines and does three things. It states how the scripts are run, it pins the exact test crate they need, and it tells you which script measures which gap.'),
    blank,
    kv('role', 'index and setup instructions for the probe scripts'),
    kv('language', 'Markdown, with a TOML snippet'),
    kv('size', '23 lines, next to 5 scripts of 26 to 56 lines each'),
    kv('measured', '2026-10-14, rust-analyzer 1.99.0, edition 2024'),
    kv('outputs', 'lines prefixed T:, ACT and COMPL'),
    kv('created', '42558fa, 2026-10-14, together with the plan'),
    blank,
    ...sec('why probes and not specs'),
    ...text('The macros and dependencies phase began with a question that could not be answered by reading code: what does rust-analyzer do when you complete inside a helper attribute, or add a dependency, or hit an ambiguous name? The only way to know was to ask a live server. These scripts are the asking, written once and kept, so that the numbers in the plan can be reproduced. They live in docs/assessment and not in tests/, and the scripts print observations: none of them contains an assertion.'),
    ...code('markdown', r'docs/assessment/README.md · lines 3-3', r'''
Headless scripts behind the measurements in [../PLAN_MACROS_DEPS.md](../PLAN_MACROS_DEPS.md). They drive a real rust-analyzer through nvim and print `T:` / `ACT` / `COMPL` lines. They expect to run as `nvim --headless -S <script>` with the working directory set to a throwaway crate like this one (edition 2024):'''),
    ...text('The sentence is a contract. The scripts expect to run as nvim headless with a script argument, from the root of a throwaway crate. They need the real configuration, since the point is how this configuration behaves, and they print three kinds of lines: T for timings, ACT for code actions, COMPL for completion items.'),
    ...sec('the test crate'),
    ...text('The README gives the dependency set the probes assume, and it is chosen to include the families the phase later wrote schemas for: serde and clap with derive, thiserror and anyhow for errors, serde_json, and tokio with macros.'),
    ...code('toml', r'docs/assessment/README.md · lines 6-12', r'''
[dependencies]
anyhow = "1"
clap = { version = "4", features = ["derive"] }
serde = { version = "1", features = ["derive"] }
serde_json = "1"
thiserror = "2"
tokio = { version = "1", features = ["macros", "rt-multi-thread"] }'''),
    ...text('It adds in prose that src/main.rs must derive Serialize, Deserialize, Error and Parser and use #[serde(...)], #[arg(...)], #[error(...)] and #[tokio::main]. That crate is also, in spirit, the deps-lab fixture that the later specs use under tests/fixtures. The README does not say the fixture was copied from it, and the script paths in the table assume you build it yourself, so the claim stops there.'),
    ...sec('the table of scripts'),
    ...code('markdown', r'docs/assessment/README.md · lines 17-23', r'''
| Script | What it measures |
| --- | --- |
| `dep-recognition-timeline.lua` | adds `rand = "0.9"` to `Cargo.toml` in nvim and samples both diagnostic tiers and hover every 3 s |
| `import-and-completion.lua` | import code actions for unresolved names, completion items with auto-import edits, derive completion |
| `attribute-completion.lua` | completion inside `#[derive(`, `#[cfg(`, `#[allow(`, `#[repr(` |
| `attribute-arguments.lua` | completion inside `#[serde(`, `#[arg(`, `#[command(`, `#[error(` |
| `completion-and-actions.lua` | a wider first sweep (path completion, auto-import items, code actions) |'''),
    ...bullet('dep-recognition-timeline.lua', 'adds rand = 0.9 to Cargo.toml in nvim and samples both diagnostic tiers and hover every three seconds. Its subject matches gap G5 in the plan: rust-analyzer resolved the crate in 10 s while bacon-ls stayed red. A separate page in this explorer walks through it.'),
    ...bullet('import-and-completion.lua', 'import code actions for unresolved names, completion items with auto-import edits, derive completion. Its subject matter matches G2 (derive completion returned nothing) and G6 (the eight Error actions in alphabetical order) in the plan; the README does not say which script produced which gap.'),
    ...bullet('attribute-completion.lua', 'completion inside #[derive(, #[cfg(, #[allow(, #[repr(. The plan records that built-in attributes complete (24 items for cfg, 1037 lints for allow, 16 for repr).'),
    ...bullet('attribute-arguments.lua', 'completion inside #[serde(, #[arg(, #[command(, #[error(. Matches G1 in the plan.'),
    ...bullet('completion-and-actions.lua', 'a wider sweep over path completion, auto-import items and code actions.'),
    ...sec('design decisions'),
    ...bullet('Scripts, not screenshots', 'each claim in the plan can be re-run and produce the same kind of line.'),
    ...bullet('The version is pinned in the text', 'measured with rust-analyzer 1.99.0 and this config on 2026-10-14, because a later server may behave differently; the plan itself suspects a regression in the derive completion.'),
    ...bullet('Throwaway crate', 'the probes edit files and write Cargo.toml, so they should never run in a real project.'),
    ...bullet('Output you can grep', 'T, ACT and COMPL prefixes make results easy to diff between runs.'),
    ...sec('edge cases and limits'),
    ...bullet('No assertions', 'a probe cannot fail; it can only print an unexpected value. The status table in the plan lists, as not done, turning the probes into regression specs one to one.'),
    ...bullet('Time-dependent', 'the timeline script waits real seconds for servers, up to 60 s for rust-analyzer to attach.'),
    ...bullet('Environment-bound', 'the scripts are not run by CI and nothing in the suite checks that they still run.'),
    ...sec('how it is tested'),
    ...text('They are not tested. The follow-up specs (crate-add, import-engine, macro-attrs, macros-deps-flows and others) cover the same ground with assertions on fixtures, and the Phase 4 row of the status table in PLAN_MACROS_DEPS.md says the probes were not turned into regression specs one to one.'),
    ...sec('history'),
    ...bullet('2026-10-14', '42558fa adds the README and the five scripts in the same commit as the plan. No later commit has touched this directory.'),
    blank,
  ],
);
