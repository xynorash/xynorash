import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/Cargo.toml',
  lines: [
    cm('#', '──────────────────────────────────────────'),
    cm('#', 'Cargo.toml — one workspace, seven crates, one profile line'),
    cm('#', 'the manifest that holds the Rust half of HeapLens together'),
    cm('#', '──────────────────────────────────────────'),
    blank,
    kv('role', 'workspace manifest for every Rust crate in the repo'),
    kv('language', 'TOML (Cargo)'),
    kv('size', '29 lines · 7 members · 1 profile override'),
    kv('born', '2026-06-24, as 7 lines and two TODO comments'),
    kv('most important line', 'debug = true, under [profile.release]'),

    ...sec('what this file is for'),
    ...para('#',
        'HeapLens is not one program. It is a capture library that '
        'lives inside the observed process, a daemon that models the '
        'heap, a launcher, a hook DLL, an injector and a benchmark '
        'harness, plus a shared contract crate that all of them lean '
        'on. A Cargo workspace is what lets those pieces be separate '
        'crates with separate dependency lists while still building '
        'into one target directory against one Cargo.lock. The lock '
        'file is committed, which is the right call for a repo whose '
        'output is executables rather than a library.'),
    ...code('toml', 'Cargo.toml · the workspace table', r'''
[workspace]
resolver = "2"
members = [
    "crates/heaplens-protocol",
    "crates/heaplens-alloc",
    "crates/heaplens-daemon",
    "crates/heaplens-launcher",
    "crates/heaplens-hook",
    "crates/heaplens-injector",
    "crates/h1-harness",
    # TODO: heaplens-flutter (Stage 4)
]'''),
    ...para('#',
        'resolver = "2" is the feature resolver that edition-2021 '
        'crates get by default. A virtual workspace like this one '
        'has no root package to take an edition from, so Cargo '
        'expects the resolver to be stated, and this file states '
        'it from its first commit. No commit explains the choice '
        'beyond that. There is no [workspace.dependencies] table '
        'and no [workspace.package]: every crate states its own '
        'edition ("2021" everywhere) and its own versions. That is '
        'more repetition, and it has a visible cost, shown below in '
        'the dependency drift between crates.'),

    ...sec('the member list is a changelog'),
    ...para('#',
        'Reading git log --follow on this one file gives the '
        'architecture in the order it was discovered. Each entry is '
        'the first commit in which that crate appears in members.'),
    ...pt('#', '2026-06-24  a55f7c1',
        'protocol only. The initial manifest is seven lines, with '
        '“TODO: crates/heaplens-alloc” and “TODO: '
        'crates/heaplens-daemon” as comments. The contract crate '
        'goes first because the build spec says to build the '
        'contract, then the producer, then the consumer, then the '
        'UI.'),
    ...pt('#', '2026-07-01  8fc54a7, 23e20df',
        'alloc, then daemon, one TODO turned into a member per '
        'commit. This is the day Stage 2 and Stage 3 landed: 27 '
        'commits dated 2026-07-01, the first at 15:25 and the last '
        'at 17:36 local time.'),
    ...pt('#', '2026-07-08  43fc22e',
        'heaplens-launcher, in the same commit that adds '
        '[profile.release] and .gitignore. The commit message '
        'presents them together: a release-build launcher, and a '
        'profile fix found “verifying phi under cargo test '
        '--release”. They share a commit and a theme, a release '
        'build that behaves differently from a debug one, but not '
        'a cause.'),
    ...pt('#', '2026-07-13  b3a22c2',
        'heaplens-hook, the cdylib that Stage 7 injects, committed '
        'on the Stage 7 branch (the design doc calls it '
        'dev/phase_7). The order in the file is merge order, not '
        'date order: the injector is listed before the harness '
        'although it arrived three days later.'),
    ...pt('#', '2026-07-16  816c732',
        'h1-harness, the detection-latency measurement. A benchmark '
        'harness is a workspace member rather than a script so it '
        'can reuse heaplens-protocol types and be built with the '
        'same release profile it is measuring.'),
    ...pt('#', '2026-07-19  724695a',
        'heaplens-injector, arriving through the commit that ports '
        'Stage 7’s control protocol into the UI-refresh branch.'),
    blank,
    ...para('#',
        'Not a single crate has ever been removed from the list. The '
        'only deletion in the file’s history is a TODO comment '
        'turning into a real entry.'),

    ...sec('a fossil: the Stage 4 TODO'),
    ...para('#',
        'The last line of members is still a comment: heaplens-flutter, '
        'Stage 4. It was written on 2026-07-01 in 23e20df, copied '
        'from the daemon plan’s own template (the M3 plan in '
        'docs/superpowers/plans shows the identical line). It has '
        'never been true. The Flutter app lives in heaplens_flutter/, '
        'is built with the Flutter toolchain, and is not a Cargo '
        'package at all, so it can never become a member.'),
    ...para('#',
        'The label “Stage 4” is also out of step with the rest of '
        'the documentation, where the app is milestone M5. The '
        'Build Spec’s milestone list, written on the first day, '
        'already splits the daemon into M3 (ingest and graph) and '
        'M4 (anomalies, store, WebSocket), so the split is not the '
        'explanation. A plausible slip is counting the daemon as one '
        'stage, but no commit says. What is certain is that nobody '
        'tidied the comment in the following four weeks.'),

    ...sec('the profile override, and why it is a decision'),
    ...para('#',
        'Everything else in this file is bookkeeping. This is the '
        'part with a story. The comment sits at the point of use, '
        'and the Build Spec carries a longer account of the same '
        'finding; the comment is worth reading in full.'),
    ...code('toml', 'Cargo.toml · [profile.release] (trimmed)', r'''
[profile.release]
# φ resolves ownership from stack-frame symbol names (writer.rs's
# is_machinery_symbol / graph.rs's effective_site). Rust's default release
# profile omits debug info, so backtrace::resolve falls back to the nearest
# preceding *exported* symbol for any function without one — every internal
# call site (e.g. nested_alloc, leaf_alloc in the producer examples)
# resolves to whatever public symbol happens to sit before it in the
# binary (observed: all collapsed onto "wire_producer::main"), which
# destroys φ's function-name matching even though the frames themselves are
# correctly walked.
debug = true'''),
    ...para('#',
        'The setup: HeapLens infers who owns whom (the function φ) '
        'from the names of the functions on a call stack. The '
        'capture side records raw return addresses; the writer '
        'thread resolves them to names with backtrace::resolve '
        'inside the observed process. So the quality of the whole '
        'ownership graph depends on one thing nobody thinks about '
        'in a release build: whether the binary can name its own '
        'functions.'),
    blank,
    ...para('#', 'The symptom was silence, not an error:'),
    ...pt('#', 'what was observed',
        'verifying φ with cargo test --release produced no '
        'ownership edges at all. No crash, no warning, no failing '
        'assertion that pointed at the cause. The commit message for '
        '43fc22e calls it “silently zeroes out phi’s edges”.'),
    ...pt('#', 'why it looked like something else',
        'the branch had already produced inlining-related bugs in '
        'this area. The Build Spec records that this one '
        '“looked exactly like the earlier inlining-related bugs … '
        'but was a distinct and simpler root cause that subsumes '
        'it”. The comment above repeats the key point: '
        '#[inline(never)] on the producers’ allocation-site '
        'functions is still correct practice, and by itself does '
        'not fix this.'),
    ...pt('#', 'the mechanism',
        'without debug info, a lookup for an address inside a '
        'private function does not fail. It returns the nearest '
        'preceding exported symbol. So nested_alloc and leaf_alloc '
        'both came back as wire_producer::main. Every frame was '
        'walked correctly; every frame was then given the same '
        'wrong name; φ’s name matching saw a stack of identical '
        'entries and linked nothing.'),
    ...pt('#', 'the confirmation',
        'a live release-mode wire_producer run, before and after. '
        'Without the setting, distinct call sites vanished from the '
        'resolved names. With it, wire_producer::leaf_alloc and '
        'wire_producer::nested_alloc resolved correctly and '
        'distinctly. Changing one build setting and watching the '
        'symptom appear and disappear is what turns a hypothesis '
        'into a finding.'),
    blank,
    ...para('#',
        'A failure that produces plausible-looking output is the '
        'dangerous kind. A graph with no edges is a valid graph. '
        'Nothing in the pipeline could have objected, which is why '
        'the fix is a build-configuration line with a paragraph '
        'attached rather than a runtime check.'),

    ...sec('what debug = true does not do'),
    ...para('#',
        'The natural objection is performance: a tool whose whole '
        'design pressure is “the observed program must barely '
        'notice it” should not ship in a slower profile. The Build '
        'Spec answers this in its section on limitations. Debug '
        'info adds symbol-table data to the binary; it does not '
        'change opt-level, inlining or code generation, so the '
        'ring-buffer hot path is the same machine code either way. '
        'The cost is binary size, not speed. This is the same trade '
        'profilers, crash reporters and APM agents make on purpose.'),
    ...para('#',
        'No size difference has been measured here and nothing in '
        'the repo records one, so this page does not quote a number. '
        'What the file does show is how little else is configured: '
        'no opt-level, no lto, no codegen-units, no panic strategy, '
        'no strip. The release profile is Cargo’s default plus '
        'exactly one line, which keeps the claim easy to audit: the '
        'shipped configuration differs from stock release by '
        'symbols and nothing else.'),
    ...para('#',
        'The Spec adds a rule for later work: any benchmark must '
        'run against this exact profile so reported numbers describe '
        'the shipped build, not a stripped binary nobody delivered. '
        'The H1 harness follows it by construction:'),
    ...code('rust', 'crates/h1-harness/src/main.rs · which binaries it runs', r'''
    let daemon_exe = cwd.join("target/release/heaplens-daemon.exe");
    let workload_exe = cwd.join("target/release/examples/chaos_orphan.exe");'''),
    ...para('#',
        'Both paths are under target/release, so a workspace '
        'release build with debug = true is what the harness '
        'measures. The CSV was committed on 2026-07-16, eight days '
        'after the profile line, so it is consistent with that; the '
        'repo does not record the build command that produced it.'),

    ...sec('chapter two: the PDB has to travel with the exe'),
    ...para('#',
        'The profile line was necessary and, it turned out, not '
        'sufficient. On 2026-07-19 (9c4678e) the same symptom came '
        'back in a packaged build: edges vanished and the Hot and '
        'Orphan states never fired. The cause this time was not '
        'the compiler configuration but the delivery folder. On '
        'MSVC, debug info lives in a .pdb written next to the .exe, '
        'and dbghelp resolves a binary’s own functions only if '
        'that .pdb sits in the same directory. The packaged '
        'release had shipped executables without their PDBs.'),
    ...para('#',
        'The diagnostic detail is what makes this a good puzzle. '
        'Symbols from system DLLs, such as BaseThreadInitThunk, '
        'kept resolving fine, because Windows exports them without '
        'needing a local PDB. Only the program’s own functions '
        'collapsed. A partial failure like that looks like a race '
        'in the resolver. The commit records that three of three '
        'runs from an exe-plus-pdb layout resolved correctly, and '
        'three of three runs of the identical binary without its '
        'PDB collapsed. The requirement now lives where the next '
        'person packaging a release will read it:'),
    ...code('rust', 'crates/heaplens-alloc/src/writer.rs · run()', r'''
    // `.pdb` file be present next to its `.exe` at runtime — `dbghelp`
    // searches the executable's own directory. This was the actual cause of
    // a symbol-collapse bug that looked like a resolution race (every
    // address resolving to the same address or an unrelated symbol, system-
    // DLL exports like `BaseThreadInitThunk` unaffected since those don't
    // need a local `.pdb`): a packaged release build had shipped `.exe`
    // files without their matching `.pdb`s. Any packaging step for a
    // release build must ship both.'''),
    ...para('#',
        'So the complete rule is two lines long, and they live in '
        'two files: build with debug = true (this manifest), and '
        'ship the .pdb beside the .exe (a comment in writer.rs). '
        'The .gitignore excludes /dist/, so the packaging step '
        'itself is not in the repository, and the second half of '
        'the rule is enforced only by that comment and by '
        'whoever reads it.'),

    ...sec('the limit that no profile can fix'),
    ...para('#',
        'Everything above is about binaries HeapLens builds. The '
        'Stage 7 design document makes the uncomfortable follow-up '
        'point: when you inject into someone else’s process you do '
        'not control how it was compiled, and most real release '
        'binaries ship without debug info. For those targets φ '
        'degrades toward a graph of disconnected roots, and the '
        'design chooses to call that “a correct, legible '
        'degradation, not a bug to chase”. The design says capture, '
        'the memory map and size tracking keep working because they '
        'use sizes and counts rather than names. It also lists '
        'orphan timing and hot-cluster flags as unaffected, and the '
        'code says otherwise: anomaly.rs only marks a node orphan '
        'if it once had an owner, and only marks it hot if it has '
        'more than 32 outgoing edges, and both facts come from φ. '
        'The 9c4678e commit confirms the symptom: with every site '
        'collapsed, φ found no edges and Hot and Orphan never '
        'fired. This one line in Cargo.toml is the whole of what '
        'the project can do on its own side; the rest is a limit.'),

    ...sec('dependency drift the workspace does not prevent'),
    ...para('#',
        'Because each crate lists its own versions, they can '
        'disagree, and a few have moved since the plans were '
        'written. These come straight from the member manifests:'),
    ...pt('#', 'windows-sys',
        'the alloc plan specified version 0.59 with three feature '
        'flags; the final review pass of Stage 2 (ba1a066) removed '
        'it as unused because the writer opens the pipe through '
        'std::fs. It came back later at 0.61, and every '
        'Windows-facing crate now pins that with its own feature '
        'list. heaplens-alloc asks only for Win32_System_Threading, '
        'the home of the TlsAlloc and FlsAlloc calls.'),
    ...pt('#', 'tokio',
        'the daemon enables signal and process on top of the '
        'common set; the harness enables process and fs. Same '
        'major version, different surface.'),
    ...pt('#', 'rusqlite and tokio-tungstenite',
        'declared separately in the daemon and the harness, at the '
        'same versions (0.32 and 0.24). Cargo unifies them in the '
        'lock file, so nothing is built twice, but nothing forces '
        'them to stay equal either.'),
    blank,
    ...para('#',
        'A [workspace.dependencies] table would remove this class '
        'of drift. The code works without it; the point is that '
        'the choice is visible and cheap to change.'),
    ...code('toml', 'crates/heaplens-hook/Cargo.toml · the one cdylib', r'''
[lib]
name = "heaplens_hook"
crate-type = ["cdylib"]'''),
    ...para('#',
        'Two manifests show intent by what they omit. '
        'heaplens-protocol depends on serde and nothing else, with '
        'serde_json as a dev-dependency: the “data only, zero '
        'logic” promise of the build spec is enforced by what the '
        'manifest allows, so a thread or a socket cannot sneak into '
        'the contract crate without a visible change here. And the '
        'launcher’s binary is named HeapLens, not heaplens-launcher, '
        'because it is the executable a person double-clicks.'),

    ...sec('the one manifest oddity worth flagging'),
    ...para('#',
        'heaplens-alloc is the crate that gets linked into somebody '
        'else’s program. Its manifest lists iced, rand, ratatui and '
        'crossterm under [dependencies], not [dev-dependencies]. '
        'They arrived in 9693399, whose title says the TUI '
        '“replaces” the iced GUI while both example files remain in '
        'the tree. The shared module checkout_common.rs calls the '
        'GUI demo “parked”. A grep over the workspace shows where '
        'each one is really used: iced only in '
        'checkout_service_gui, ratatui and crossterm only in '
        'checkout_service_tui and the shared module, and rand in no '
        'Rust file at all.'),
    ...para('#',
        'It also cuts against the build spec’s own line about this '
        'crate, which says “No tokio here — the observed process '
        'must stay light”: iced is listed with its tokio feature '
        'switched on. The library source (src/) uses none of the '
        'four, so nothing suggests the observed process carries '
        'them at run time; I did not inspect a built binary. The '
        'cost is in the build graph.'),
    ...para('#',
        'Cargo builds every normal dependency for anyone who '
        'depends on the crate, examples or not. The visible effect '
        'is in the lock file: that single commit changed Cargo.lock '
        'by +4415 and −443 lines, in a file that now holds 4,865 '
        'lines and 485 package entries. Moving the four to '
        'dev-dependencies is the obvious cleanup. This is not '
        'asserted as a bug, since examples compile fine this '
        'way, only as a manifest that says more than the '
        'architecture intends.'),

    ...sec('limits, and what next'),
    ...pt('#', 'stale comment',
        'the Stage 4 TODO should either go or be rewritten to say '
        'the Flutter app is deliberately outside the workspace.'),
    ...pt('#', 'no shared dependency table',
        'see the drift above; low risk today with seven crates.'),
    ...pt('#', 'demo dependencies in the library crate',
        'see the previous section.'),
    ...pt('#', 'Windows only, implicitly',
        'nothing in this file says so; the platform constraint is '
        'carried by the crates (named pipes, windows-sys, MinHook), '
        'and a non-Windows cargo check is not a goal.'),
    blank,
    ...para('#',
        'What to take from it: the most valuable line in the file '
        'is the one with the longest comment. When a failure is '
        'silent and plausible, write the diagnosis next to the '
        'setting that cures it, and keep the claim narrow enough '
        'to be checked.'),
    blank,
    link('→ github.com/XNash/heaplens', 'https://github.com/XNash/heaplens'),
  ],
);
