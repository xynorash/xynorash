import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/crates/heaplens-protocol/Cargo.toml',
  lines: [
    cm('#', '──────────────────────────────────────────'),
    cm('#', r'Cargo.toml — a contract crate with one real dependency'),
    cm('#', r'serde for the JSON half, nothing at all for the binary half'),
    cm('#', '──────────────────────────────────────────'),
    blank,
    kv('role', r'manifest for heaplens-protocol, the shared contract crate'),
    kv('language', r'TOML'),
    kv('size', r'10 lines, unchanged since the first commit (a55f7c1, 2026-06-24)'),
    kv('dependencies', r'serde 1 (derive); dev: serde_json 1'),
    ...sec(r'the whole file'),
    ...code('toml', 'crates/heaplens-protocol/Cargo.toml · the manifest', r'''
[package]
name = "heaplens-protocol"
version = "0.1.0"
edition = "2021"

[dependencies]
serde = { version = "1", features = ["derive"] }

[dev-dependencies]
serde_json = "1"'''),
    ...para('#',
        r'There is almost nothing here, and the shortness is deliberate. '
        r'The Stage 1 design note lists the crate’s dependencies in the '
        r'section on workspace layout and then adds a sentence that '
        r'doubles as the rule: "No other dependencies. No tokio, '
        r'backtrace, or windows-sys in this crate." Everything in the '
        r'manifest is a decision about what this crate refuses to be.'),
    ...sec(r'serde, with derive and nothing else'),
    ...para('#',
        r'serde is here for exactly two files. diff.rs and control.rs are '
        r'the JSON half of the contract and derive Serialize and '
        r'Deserialize for their types. The binary half, event.rs and '
        r'frame.rs, does not use serde at all; frames are built and parsed '
        r'by hand with to_le_bytes and slicing, because the layout has to '
        r'be exact to the byte. So the same crate holds a hand-rolled wire '
        r'format and a derive-driven one, side by side, because the Build '
        r'Spec gives it one job: "Define shared data types and wire '
        r'formats."'),
    blank,
    ...para('#',
        r'The feature list is only derive. There is no std-less mode, no '
        r'alloc feature juggling, and serde_json is not a normal '
        r'dependency. The crate emits no JSON text by itself; the daemon’s '
        r'server.rs does the serde_json::to_string call. Keeping the '
        r'serialiser out of the contract means the contract does not '
        r'choose the transport.'),
    ...sec(r'why serde_json is a dev-dependency'),
    ...para('#',
        r'The design note is explicit: serde_json as dev-dependency only. '
        r'diff.rs requires only the serde derive to compile. serde_json '
        r'appears in tests/diff_json.rs, where it turns a message into a '
        r'string and back into a generic Value so the tests can assert on '
        r'keys, types and absent fields. That choice puts the JSON '
        r'library’s compile cost on the test run and not on the protocol '
        r'crate’s own build. (The daemon and h1-harness do depend on '
        r'serde_json, but for their own reasons, declared in their own '
        r'manifests.)'),
    blank,
    ...para('#',
        r'This matters most for heaplens-alloc and heaplens-hook, which '
        r'link the protocol crate into a process that did not ask for any '
        r'of it. The less this manifest drags in, the less ends up in '
        r'someone else’s address space. Binary sizes were not measured; '
        r'what the manifest guarantees is that the contract itself adds '
        r'one crate (plus serde’s own derive machinery at build time) to '
        r'that process’s dependency tree.'),
    ...sec(r'what is not here'),
    cm('#', r'no tokio           the contract does no I/O and has no async'),
    cm('#', r'no backtrace       symbol resolution is the allocator’s job'),
    cm('#', r'no windows-sys     nothing in the contract is Windows-specific'),
    cm('#', r'no thiserror/anyhow  there is no error type; decoders return Option'),
    cm('#', r'no workspace deps  protocol depends on no other crate in the repo'),
    blank,
    ...para('#',
        r'Each absence has a counterpart elsewhere. tokio lives in the '
        r'daemon, where named pipes and WebSockets need it. backtrace and '
        r'the Windows thread-local APIs live in heaplens-alloc. The '
        r'decoders return Option, never Result, which matches the '
        r'project’s stance that malformed input is skipped, not reported.'),
    ...sec(r'how it compares with its neighbour'),
    ...para('#',
        r'Put this manifest next to crates/heaplens-alloc/Cargo.toml and '
        r'the contrast is the lesson. The protocol manifest has not '
        r'changed since the day it was written. The alloc manifest has '
        r'four commits. It started with windows-sys 0.59 (for pipe and '
        r'file APIs), dropped it on 2026-07-01 in the final review fixes '
        r'of the Stage 2 work, regained windows-sys 0.61 with only the '
        r'Threading feature on 2026-07-21 (the commit that replaced '
        r'thread_local! with raw TlsAlloc/FlsAlloc), and on 2026-07-28 '
        r'grew iced, rand, ratatui and crossterm for the demo programs. '
        r'Keeping the contract crate this small is what let it be the '
        r'stable thing the other crates moved around.'),
    ...sec(r'what the first commit contained'),
    ...para('#',
        r'Commit a55f7c1 ("chore: init workspace + heaplens-protocol '
        r'scaffold", 2026-06-24) created this manifest together with the '
        r'workspace Cargo.toml, whose only member was this crate (the '
        r'other two were TODO comments), three empty source files '
        r'(diff.rs, event.rs, frame.rs) and a three-line lib.rs. The same '
        r'commit carried the Build Spec, the UML diagrams, the Stage 1 '
        r'plan and the Stage 1 design note. So the manifest was written '
        r'after the design had been argued out on paper, and it never '
        r'needed a second edit. The lock file from that commit resolves '
        r'to a small set of crates: serde, serde_core, serde_derive, '
        r'serde_json and their proc-macro helpers (syn, quote, '
        r'proc-macro2, unicode-ident), plus itoa, memchr and zmij.'),
    ...sec(r'limits'),
    ...pt('#',
        r'edition 2021 and version 0.1.0',
        r'copied across crates. No MSRV is declared. The frame decoder '
        r'uses u32::is_multiple_of, a recent standard-library addition, so '
        r'a toolchain old enough to lack it would not build the crate; the '
        r'manifest does not say which toolchain is required.'),
    ...pt('#',
        r'no license, description or repository fields',
        r'the manifest is for in-workspace use, not for publishing.'),
    ...pt('#',
        r'path dependencies everywhere',
        r'consumers refer to the crate by path, so versioning is moot '
        r'until something is published.'),
    blank,
    link('→ github.com/xynorash/heaplens · crates/heaplens-protocol/Cargo.toml',
        'https://github.com/xynorash/heaplens/blob/master/crates/heaplens-protocol/Cargo.toml'),
  ],
);
