import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/docs/PLAN_MACROS_DEPS.md',
  lines: [
    heading('# Next phase: macros and dependencies'),
    blank,
    ...text('docs/PLAN_MACROS_DEPS.md is the document that turned one complaint into a feature phase. The complaint: when a crate is added, its macros and features are not fully used. The page holds the measurements that located seven concrete gaps, the four-phase plan written on 2026-10-14, and, added after the implementation round, a status table that says item by item what is done, partial or not done. It is 105 lines, and it is the clearest example in the repository of the loop measure, plan, build, report what is missing.'),
    blank,
    kv('role', 'assessment, plan and status report for the macros and dependencies phase'),
    kv('language', 'Markdown with tables'),
    kv('size', '105 lines: status table, assessment, plan, risks'),
    kv('date', 'measured 2026-10-14 with rust-analyzer 1.99.0, status after the implementation round'),
    kv('outcome', '11 items done, 5 partial, 0 not done in the status table'),
    kv('code', 'lua/config/{crate_meta,crate_add,crate_features,crate_import,import_engine,macro_attrs,macro_tools,code_actions}.lua'),
    blank,
    ...sec('the question and the order of the file'),
    ...text('The opening paragraph states the question and notes that it has been answered, so the page now reads in an unusual order: the Status section comes first and the original assessment and plan follow it. A reader who wants to know what shipped reads the top; a reader who wants to know why reads on.'),
    ...code('markdown', r'docs/PLAN_MACROS_DEPS.md · lines 1-3', r'''
# Next phase: macros and dependencies

The question (answered by the implementation below, see Status): when a crate is added, its macros and features are not fully exploited. What is missing, and what do we build? This page holds the measurements and the plan; the README has the summary.'''),
    ...text('The status legend defines the three words so that a done is never a hope: done means implemented and covered by a spec that was run, partial means implemented with the stated gap, not done means not done. The acceptance column records what was actually run and nothing more.'),
    ...code('markdown', r'docs/PLAN_MACROS_DEPS.md · lines 7-7', r'''
Legend: **done** = implemented, covered by a spec that was run; **partial** = implemented with the stated gap; **not done**. Acceptance results are what was run, nothing more. The user-facing description is the README section "Macros and dependencies", the engineering notes are in [DETAILS.md](DETAILS.md#macros-and-dependencies).'''),
    ...sec('the assessment: what already worked'),
    ...text('The assessment was done on a throwaway crate with serde, clap, thiserror, anyhow, serde_json and tokio, edition 2024, using the real configuration. It starts with a list of what already worked, which prevented rebuilding things that existed. Derive and attribute macros expanded and hover resolved the clap-derived parse to its bounds; completion carried the import edit; import code actions existed for names in a dependency, including inside a derive; rust-analyzer recognised a new dependency within 10 seconds of Cargo.toml being written.'),
    ...code('markdown', r'docs/PLAN_MACROS_DEPS.md · lines 36-36', r'''
- **Derive and attribute macros expand.** Hover on the clap-derived `Cli::parse` resolves to `clap_builder::derive::Parser::parse` with its bounds; `#[derive(Serialize)]`, `#[derive(Error)]`, `#[tokio::main]` produce no diagnostics. Proc macros and build scripts are enabled (LazyVim's rust extra), so this is not a configuration problem.'''),
    ...code('markdown', r'docs/PLAN_MACROS_DEPS.md · lines 40-41', r'''
- **rust-analyzer recognises a new dependency within 10 s** of `Cargo.toml` being written from nvim (sampled every 3 s: hover on `rand::random` was empty at 6 s and resolved at 10 s).
- Built-in attributes complete: `#[cfg(` 24 items, `#[allow(` 1037 lints, `#[repr(` 16 items.'''),
    ...sec('the seven gaps'),
    ...text('The gap table is the pivot of the page. Each row has a number, a claim, the evidence from a probe, and the effect on the user. The numbering G1 to G7 is used later in the status table, in the plan items and in the README.'),
    ...bullet('G1', 'no completion inside helper-attribute arguments: #[serde(, #[arg(, #[command(, #[error(, #[tokio::main( returned zero items or only generic paths, never rename_all, short, long or flavor.'),
    ...bullet('G2', '#[derive( completion returned nothing in three contexts. The cause was not isolated; the table notes a possible rust-analyzer 1.99 regression.'),
    ...bullet('G3', 'a crate that is not yet a dependency cannot be imported. rand::random with rand absent gave no code action and, because experimental diagnostics are off, no diagnostic.'),
    ...bullet('G4', 'a missing crate feature is silent. With serde = 1 and no derive, rustc says cannot find derive macro Serialize, and none of the offered code actions enables the feature.'),
    ...bullet('G5', 'the clippy tier goes stale after a dependency is added. rust-analyzer resolved rand at 10 s, bacon-ls kept reporting the missing crate for the whole 61 s observed, until a FocusGained event restarted it.'),
    ...bullet('G6', 'ambiguous imports are not ranked. An unresolved Error gives eight actions in alphabetical order across anyhow, clap and std.'),
    ...bullet('G7', 'no signature help for macro_rules! arguments, and no view of what a derive generates beyond the expand command.'),
    ...code('markdown', r'docs/PLAN_MACROS_DEPS.md · lines 47-48', r'''
| G1 | **No completion inside the arguments of helper attributes** | `#[serde(` (container and field), `#[arg(`, `#[command(`, `#[error(`, `#[tokio::main(` all return 0 items or only generic crate paths (`core::`, `std::`, ...), never `rename_all`, `short`, `long`, `flavor`, ... | the macro "parameters from suggestions" I asked for do not exist |
| G2 | **`#[derive(` completion returns nothing** | 0 items in three contexts (`#[derive(`, `#[derive(Se`, `#[derive(Debug, C`); with a complete attribute `#[derive(Debug, )]` it returns item keywords. Cause not isolated (possibly a rust-analyzer 1.99 regression) | derive names, including `Serialize`, are typed from memory |'''),
    ...text('One paragraph below the table shuts a door deliberately. diagnostics.experimental would surface unresolved names in the instant tier, but gave 82 false errors on a real workspace (the evidence is in DETAILS), so G3 needs its own narrower check. That explains why the unknown-crate hint is a conservative treesitter scan against cargo metadata, std and local modules, with misses accepted and false hints not.'),
    ...code('markdown', r'docs/PLAN_MACROS_DEPS.md · lines 55-55', r'''
Not a gap: `diagnostics.experimental` would surface unresolved names in the instant tier but gave 82 false errors on a real workspace (see DETAILS), so G3 needs its own, narrower check.'''),
    ...sec('the plan, phase by phase'),
    ...bullet('Phase 0, stop the false errors', '0.1 restarts bacon-ls when Cargo.toml or Cargo.lock is saved (G5); 0.2 shows deps resolving in the statusline so a red error in that window is understood as transient.'),
    ...bullet('Phase 1, dependencies from the editor', 'an unknown-crate hint (G3), :CrateAdd with search, versions, downloads and feature descriptions, the missing-feature fix (G4) computed from the crate’s own source, and a feature explorer.'),
    ...bullet('Phase 2, macro depth', 'a data-driven blink.cmp source for attribute arguments (G1) with JSON schemas for ten crates, derive and attribute names (G2), macro call help (G7), a macro lens, and proc-macro health.'),
    ...bullet('Phase 3, the import engine', 'auto-import when there is exactly one candidate, ranked disambiguation with a remembered choice (G6), import from crates not yet dependencies, and organize imports.'),
    ...bullet('Phase 4, prove it', 'specs per item, a field test, and three new demo recordings.'),
    ...text('The Order of work section lists the sequence. The two items called the reported pain, 0.1 and 1.3, come first, with 3.1 and 3.2, and the macro depth items 2.3 to 2.5 come last.'),
    ...code('markdown', r'docs/PLAN_MACROS_DEPS.md · lines 94-97', r'''
1. 0.1, 1.3 (the reported pain, both small), 3.1, 3.2
2. 1.1, 1.2, 3.3
3. 2.1, 2.2
4. 2.3, 2.4, 2.5, 1.4, 3.4'''),
    ...sec('risks and decisions that were written down first'),
    ...text('The last section records the constraints before the code was written, and the shipped code follows them, which is how to read the status table. Network access is optional and everything degrades to a cache and a message. Attribute schemas are data with version ranges so that they can rot visibly. Auto-import applies only with exactly one candidate, as one undo step, and can be turned off. No custom language server is planned; everything is client side so it survives rust-analyzer updates. Non-goals include replacing rust-analyzer’s completion and editing Cargo.toml outside cargo add and feature toggles.'),
    ...code('markdown', r'docs/PLAN_MACROS_DEPS.md · lines 101-101', r'''
- **Network**: crates.io access must be optional; everything degrades to the local registry and a clear message, and results are cached.'''),
    ...sec('the status table, read critically'),
    ...text('The status table maps plan items to files and gives acceptance results. Five items are marked partial and each partial names its gap, which makes them the most useful rows. :CrateAdd offline falls back to cached searches only and cannot create a new workspace.dependencies entry. Attribute completion has no schema for leptos and offers keys while the feature that provides the derive is off. Macro call help was not verified on screen. Import from non-dependencies matches by crate name only, so Rng does not find rand. Phase 4 itself is partial: the probes are not turned into regression specs one to one, no field-test round was run for the phase at that moment, and the three demo tapes were not yet recorded.'),
    ...code('markdown', r'docs/PLAN_MACROS_DEPS.md · lines 11-12', r'''
| 0.1 Refresh the clippy tier on a saved manifest (G5) | done | `rust_restart.lua` | bacon-ls restarts 500 ms after the last save of a burst; `deps-freshness` runs it with a real rust-analyzer. The 61 s timeline probe was not re-run end to end. |
| 0.2 `deps resolving` status | done | `lsp_status.lua` | shown from the manifest save until rust-analyzer's quiescence (6 s / 120 s bounds); the 120 s ceiling is checked with a shimmed timer, not waited out live. |'''),
    ...text('The last caveats look stale against the rest of the repository. The Phase 4 row says no field-test round was run and none of the three demo tapes existed, yet docs/media/tapes now holds 11-add-crate.tape, 12-attributes.tape and 13-imports.tape, and the CHANGELOG has a section Fixed (macros and dependencies, field test), with commit b474307 (2026-10-15) titled Macros and dependencies: field test fixes. The status table was not updated after that, which is a small staleness in the document.'),
    ...text('The measured-cost line under the table is the performance receipt: headless startup median 26.03 ms in 20 runs against 24.5 ms before, with 4 of 61 plugins loaded at the end, unchanged.'),
    ...code('markdown', r'docs/PLAN_MACROS_DEPS.md · lines 28-28', r'''
Measured cost: headless startup median 26.03 ms (25.15 to 28.37, 20 runs) against 24.5 ms before; 4 of 61 plugins loaded at the end of startup, unchanged.'''),
    ...sec('design decisions'),
    ...bullet('Evidence before design', 'every gap has a measurement; every plan item names the gap it closes.'),
    ...bullet('Status written against the plan', 'the table repeats the plan numbering, so nothing can be dropped silently.'),
    ...bullet('Partial is a word with a definition', 'a partial item states exactly what is missing, in the same row.'),
    ...bullet('Failure of an assumption is recorded', 'G2 notes a cause not isolated; the later implementation did not rely on rust-analyzer’s derive completion and built its own.'),
    ...sec('how it is tested'),
    ...text('The phase has one spec per module, listed in tests/COVERAGE.md: crate-meta, deps-freshness, crate-add, crate-features, import-engine, crate-import, macro-attrs, macro-tools and macros-deps-flows. The last runs four cross-module flows on temp copies of fixtures with real cargo, crates.io and rust-analyzer; the network parts skip offline. The probe scripts that produced the assessment are in docs/assessment and are listed in its README.'),
    ...sec('history'),
    ...bullet('2026-10-14', '42558fa creates the file with the assessment, the plan and the probe scripts; b9363cd, the implementation commit, adds the status section.'),
    ...bullet('2026-10-22', 'f7b8cf0 moves the wording to the first person; no other commit has touched it.'),
    blank,
  ],
);
