import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/crates/heaplens-protocol/src/lib.rs',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'lib.rs — nine lines that define the project’s public vocabulary'),
    cm('//', r'four modules, flat re-exports, and a rule about adding enum variants'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', r'crate root of heaplens-protocol; the only import path other crates use'),
    kv('language', r'Rust'),
    kv('size', r'9 lines, no logic'),
    kv('history', r'3 commits: scaffold, flat re-exports (2026-06-24), control module '
              r'(2026-07-19)'),
    kv('depended on by', r'heaplens-alloc, heaplens-daemon, heaplens-hook, h1-harness'),
    ...sec(r'what is in it'),
    ...code('rust', 'crates/heaplens-protocol/src/lib.rs · the whole file', r'''
pub mod event;
pub mod frame;
pub mod diff;
pub mod control;

pub use event::{AllocEvent, EventKind};
pub use frame::{Frame, FrameDecoder, encode_events, encode_handshake, encode_symbols};
pub use diff::{GraphMessage, NodeDto, NodeState};
pub use control::{ControlRequest, ControlResponse, ProcessInfo};'''),
    ...para('//',
        r'Four public modules, then four pub use lines that lift the '
        r'important names to the crate root. There is no code in the file, '
        r'which is the point. The Build Spec calls this crate "pure data + '
        r'(de)serialization", and its root file reads like a table of '
        r'contents: event (the 168-byte record), frame (the binary wire '
        r'format), diff (the JSON the UI consumes) and control (the '
        r'JSON requests the UI sends, and the replies and pushes it '
        r'gets back).'),
    ...sec(r'why the names are re-exported flat'),
    ...para('//',
        r'The modules stay pub mod, so a caller can still write '
        r'heaplens_protocol::frame::FrameDecoder. Nobody does. The commit '
        r'that added the re-exports (207db8d, 2026-06-24, "lib.rs '
        r're-exports flat public API") came after the decoder and the JSON '
        r'types existed but before any other crate did. The Stage 1 design '
        r'note states the intent: "All public API addressable as '
        r'heaplens_protocol::AllocEvent etc."'),
    blank,
    ...para('//',
        r'The payoff is visible in every consumer. These are the actual '
        r'import lines in the workspace, one per crate:'),
    blank,
    cm('//', r'heaplens-alloc  writer.rs   use heaplens_protocol::{AllocEvent, encode_events,'),
    cm('//', r'                              encode_handshake, encode_symbols};'),
    cm('//', r'heaplens-alloc  lib.rs      use heaplens_protocol::EventKind;'),
    cm('//', r'heaplens-daemon ingest.rs   use heaplens_protocol::{Frame, FrameDecoder};'),
    cm('//', r'heaplens-daemon graph.rs    use heaplens_protocol::{AllocEvent, EventKind,'),
    cm('//', r'                              GraphMessage, NodeDto, NodeState};'),
    cm('//', r'heaplens-daemon server.rs   use heaplens_protocol::{ControlRequest,'),
    cm('//', r'                              ControlResponse, GraphMessage};'),
    cm('//', r'heaplens-daemon procs.rs    use heaplens_protocol::ProcessInfo;'),
    cm('//', r'heaplens-hook   lib.rs      use heaplens_protocol::EventKind;'),
    cm('//', r'h1-harness      main.rs     use heaplens_protocol::{GraphMessage, NodeState};'),
    blank,
    ...para('//',
        r'Notice who imports what. The allocator side imports the binary '
        r'vocabulary only (events, encoders). The daemon imports both '
        r'vocabularies. The hook DLL, which captures allocations in a '
        r'foreign process, imports a single enum. Nobody on the allocator '
        r'side imports GraphMessage and nobody in the UI imports anything '
        r'from Rust at all. The module split in this file is the boundary '
        r'line the Build Spec draws in its table of units: the allocator '
        r'"must NOT know about" graphs, ownership or rendering, and the '
        r'type names it can reach are the enforcement.'),
    ...sec(r'the dependency picture'),
    cm('//', r'                  heaplens-protocol   (serde only)'),
    cm('//', r'                  ^       ^       ^       ^'),
    cm('//', r'                  |       |       |       |'),
    cm('//', r'         heaplens-alloc  daemon  hook  h1-harness'),
    cm('//', r'                  ^                |'),
    cm('//', r'                  +----------------+   hook also links alloc'),
    blank,
    ...para('//',
        r'That diagram is read straight from the crates’ Cargo.toml files: '
        r'alloc, daemon, hook and h1-harness each list heaplens-protocol '
        r'by path; hook additionally lists heaplens-alloc. The protocol '
        r'crate lists no workspace crate at all, so a cycle is impossible '
        r'and a change here is the only way two units can come to disagree '
        r'about the wire.'),
    blank,
    ...para('//',
        r'The Build Spec states the rule this layout serves: "If a change '
        r'is needed in how two units talk, it changes the contract in one '
        r'place. No unit parses another unit’s private structures." The UI '
        r'side of the same rule is invariant 10, "Flutter knows only '
        r'JSON". The flat export list is what makes the first half '
        r'checkable: grep for heaplens_protocol:: and you have every place '
        r'the contract is touched.'),
    ...sec(r'growing the API: control arrives'),
    ...para('//',
        r'The last change to the file was commit 724695a on 2026-07-19, '
        r'which added pub mod control and one pub use line when the Stage '
        r'7 control protocol was ported in. It is the only edit to this '
        r'file since the first day. That tells you something about the '
        r'design: the crate grew by adding a module and exporting it, not '
        r'by reshaping what was already there. The older modules did '
        r'change afterwards, but through their own files, not through this '
        r'one: the pages for event.rs and frame.rs list those format '
        r'changes.'),
    ...sec(r'the rule the project had to learn about enums'),
    ...para('//',
        r'Exporting enums like Frame, GraphMessage and ControlResponse has '
        r'a cost that the compiler does not fully check. The Build Spec’s '
        r'cross-cutting rules (section 7) record it, added in commit '
        r'91a41f6 on 2026-07-17 after the third occurrence: when a variant '
        r'is added to GraphMsg, GraphMessage or Frame, every match '
        r'elsewhere in the test suite with a catch-all arm has to be '
        r'audited by hand. The Spec says this "has silently broken a real '
        r'test three times": first with Symbols, then with a '
        r'control-target variant, then with Handshake forwarding in '
        r'cross_process_wire.rs.'),
    blank,
    ...para('//',
        r'The mechanism is simple and nasty. A test written when the enum '
        r'had fewer cases uses a wildcard arm whose fallback is often '
        r'"break" or "treat as disconnect". A new variant is neither '
        r'malformed nor end of stream, but it lands in that arm, and the '
        r'test fails or hangs for a reason unrelated to what it was '
        r'testing. The compiler rejects a non-exhaustive match, but it '
        r'cannot object to a wildcard that was exhaustive on purpose. The '
        r'commit message says it plainly: "Cheap insurance against the '
        r'fourth instance."'),
    blank,
    ...para('//',
        r'You can see the other, healthier pattern in this crate’s own '
        r'tests. They match on a Frame with an explicit arm for the '
        r'expected variant and a final other => panic!("wrong variant: '
        r'{other:?}"). That arm cannot silently swallow a surprise; it '
        r'names it. The same discipline shows in the daemon’s ingest loop, '
        r'whose match on Frame lists all three variants and has no '
        r'wildcard.'),
    ...sec(r'limits'),
    ...pt('//',
        r'no versioning',
        r'the crate is 0.1.0 and the workspace builds everything together, '
        r'so there is no compatibility story across versions. That is fine '
        r'for a single-repository system and would not be for an installed '
        r'producer talking to a separately updated daemon.'),
    ...pt('//',
        r'a wide crate root',
        r'the root exports thirteen names. That is small now. If it grows, '
        r'the flat list is the first thing that will want grouping.'),
    ...pt('//',
        r'control has no direct test here',
        r'see the control.rs page; the wire tags for requests and replies '
        r'are pinned from the Flutter side.'),
    blank,
    link('→ github.com/xynorash/heaplens · crates/heaplens-protocol/src/lib.rs',
        'https://github.com/xynorash/heaplens/blob/master/crates/heaplens-protocol/src/lib.rs'),
  ],
);
