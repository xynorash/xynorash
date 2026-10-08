import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/docs/superpowers/specs/2026-06-24-heaplens-protocol-design.md',
  lines: [
    heading('# Stage 1 Design — heaplens-protocol'),
    blank,
    ...text('The design review for the smallest crate in the '
        'workspace and the one every other crate depends on. It '
        'does not restate the Build Spec. It records the decisions '
        'the Build Spec left open, each with the reason, so the '
        'code that follows is a transcription and not a guess.'),
    blank,
    kv('role', 'Stage 1 design spec: decisions not fixed by the Build Spec'),
    kv('date', '2026-06-24, in the repository’s first commit (a55f7c1)'),
    kv('size', '285 lines · 7 sections · 7 named tests'),
    kv('scope', 'workspace bootstrap and heaplens-protocol only'),
    kv('followed by', 'the Stage 1 plan, then 16 commits in 27 minutes'),

    ...sec('where this sits in the process'),
    ...text('HeapLens was built in a loop that the filenames in '
        'docs/superpowers make visible. For each stage there is a '
        'spec (decisions) and a plan (tasks), written before the '
        'code. This is the first spec, and the only one of its '
        'kind in the repo: later stages put their decisions '
        'straight into a plan. It states its own relationship to '
        'the master document in its second line:'),
    ...code('markdown', 'docs/superpowers/specs/2026-06-24-heaplens-protocol-design.md · header', r'''
**Scope:** Cargo workspace bootstrap + `heaplens-protocol` crate only.
**Source of truth:** `docs/HeapLens_Build_Spec.md` §2–3.'''),
    ...text('The Build Spec says what the protocol is. This '
        'document says how to implement it in the places where '
        'there is more than one defensible answer: constructors, '
        'unsafe blocks, what a decoder does with garbage, whether '
        'unknown JSON fields are errors. These are the questions '
        'that, left open, get decided silently by whoever types '
        'the code, and are then discovered months later.'),
    ...text('Scope is fenced hard. The last section’s acceptance '
        'criteria say nothing from Stage 2 or later may be present, '
        'and the dependency list is a single sentence: no tokio, '
        'no backtrace, no windows-sys in this crate. The contract '
        'crate stays pure by manifest.'),
    ...code('markdown', 'docs/superpowers/specs/2026-06-24-heaplens-protocol-design.md · §1 dependencies', r'''
[dependencies]
serde = { version = "1", features = ["derive"] }

[dev-dependencies]
serde_json = "1"'''),

    ...sec('event.rs: three small decisions about unsafe'),
    ...text('AllocEvent is a plain repr(C) struct that has to '
        'cross a pipe as raw bytes, so it needs two pieces of '
        'unsafe: view it as bytes, and read it back from bytes. '
        'The spec turns each into a documented decision.'),
    ...text('The constructor. AllocEvent::new is “the canonical '
        'constructor”, and the spec says Stage 2 must use it and '
        'must never use struct-literal syntax, because only the '
        'constructor guarantees the two padding bytes are zero. '
        'The reason is stated carefully, as a contract concern '
        'and not a soundness one:'),
    ...code('markdown', 'docs/superpowers/specs/2026-06-24-heaplens-protocol-design.md · as_bytes', r'''
    // SAFETY: AllocEvent is repr(C) with an explicit `_pad` field, so there
    // is no implicit compiler padding — all SIZE bytes belong to initialized
    // fields. The lifetime of the returned slice is tied to &self.
    // (Separately, AllocEvent::new zero-initializes `_pad` for deterministic,
    // leak-free wire output — a contract concern, not a soundness one.)'''),
    ...text('That parenthesis separates two arguments that are '
        'often blurred. Making the padding an explicit field is '
        'what makes viewing the struct as bytes sound: there are '
        'no uninitialised bytes to expose. Zeroing that field is '
        'a separate property, about what ends up on the wire, so '
        'that identical events produce identical bytes and no '
        'stale memory leaks out of the process.'),
    ...text('The read. from_bytes takes a slice that came off a '
        'pipe, which is guaranteed only to be aligned to one byte, '
        'while the struct contains u64 fields that want eight. '
        'The spec’s answer is an unaligned read, with the reason '
        'written into the SAFETY comment:'),
    ...code('markdown', 'docs/superpowers/specs/2026-06-24-heaplens-protocol-design.md · from_bytes', r'''
    // SAFETY: length checked above; read_unaligned makes no alignment
    // assumption about the incoming byte buffer.'''),
    ...text('The final code carries the same reasoning in its own '
        'SAFETY comments. It is a good example of what a design '
        'spec is for: nothing about this would fail a test on '
        'x86-64, where unaligned loads are tolerated. It is '
        'correct by construction rather than by luck.'),
    ...code('rust', 'crates/heaplens-protocol/src/event.rs · as_bytes', r'''
        // SAFETY: AllocEvent is repr(C) with an explicit `_pad` field, so
        // there is no implicit compiler padding — all SIZE bytes belong to
        // initialized fields. Lifetime is tied to &self.'''),
    ...text('A last small decision: a compile-time assertion that '
        'the size equals the SIZE constant, written first in the '
        'listing so it is the first thing a reader sees. Changing '
        'the layout without changing the constant stops the build.'),

    ...sec('frame.rs: a decoder designed around two kinds of wrong'),
    ...text('The decoder reads a byte stream that can arrive in '
        'any chunking and might be corrupted. The spec’s central '
        'idea is that “wrong” comes in two kinds that need '
        'different responses, and it puts them in a table with a '
        'warning that they “must not be conflated”:'),
    ...code('markdown', 'docs/superpowers/specs/2026-06-24-heaplens-protocol-design.md · two skip mechanisms (cells)', r'''
| Cause | Action |
| Untrustworthy `length` prefix (`0` or `> MAX_FRAME_LEN`) |
| Malformed content (trustworthy length) |'''),
    ...text('If the length prefix is garbage, nothing after it '
        'can be trusted, so the decoder slides forward one byte '
        'and tries to find a header again. If the prefix is '
        'plausible but the body is bad, the frame boundary is '
        'still known, so the decoder skips exactly that frame and '
        'carries on. Confusing the two either loses good frames '
        '(skipping by a bad length) or never recovers (sliding '
        'one byte through a long, valid, malformed frame).'),
    ...text('A third rule completes the picture. A buffer that '
        'merely does not contain enough bytes yet is neither '
        'case: “incomplete is never an error”, returning nothing '
        'and changing nothing. The structure that makes this '
        'natural is a two-state machine split on the single '
        'fixed-size field, the four-byte length. The spec notes '
        'a bonus: this removes a “length minus one” from the state '
        'transition, a place off-by-one errors breed.'),
    ...text('The length cap is justified with a number, not an '
        'adjective:'),
    ...code('markdown', 'docs/superpowers/specs/2026-06-24-heaplens-protocol-design.md · MAX_FRAME_LEN', r'''
const MAX_FRAME_LEN: u32 = 8 * 1024 * 1024; // 8 MiB;'''),
    ...text('The 6.6 KB is 3 header bytes plus 64 events of 104 '
        'bytes. With the record now at 168 bytes the same batch is '
        'about 10.7 KB; the cap is still generous by a factor of '
        'several hundred.'),

    ...sec('the spec that was not enough'),
    ...text('Here is the instructive part. The spec’s resync '
        'rule is only the length check. It was implemented in '
        'ca4e501 at 21:25; the round-trip, partial-read and '
        'multi-frame tests followed at 21:30. Then the test '
        'written to pin the rule, T6 (an absurd length prefix '
        'sandwiched between two valid frames), arrived at 21:41 in '
        'a commit that also rewrote the decoder: 81 lines changed '
        'in frame.rs against 51 in the test.'),
    ...text('What it added was a plausibility check on every '
        'header, and the comment it left says why. The comment '
        'implies the failure: a junk-derived length below the cap '
        'would otherwise send the decoder off waiting for a body '
        'that never completes.'),
    ...code('rust', 'crates/heaplens-protocol/src/frame.rs · is_plausible_header (trimmed)', r'''
    fn is_plausible_header(length: u32, ftype: u8) -> bool {
        if length == 0 || length > MAX_FRAME_LEN {
            return false;
        }
        match ftype {
            0x00 => (11..=MAX_HANDSHAKE_LEN).contains(&length),
            0x01 => {
                length >= 3
                    && (length - 3).is_multiple_of(AllocEvent::SIZE as u32)
            }
            0x02 => length >= 3,
            _ => false,
        }
    }'''),
    ...text('An events frame has length 3 plus a multiple of the '
        'record size, so random bytes pass that test about one '
        'time in the record size. Handshake frames get a second '
        'cross-check, comparing the length field with the name '
        'length inside the payload. The original comment in the '
        'T6 commit explains it as rejecting implausible lengths '
        '“during resync without waiting for the full body to '
        'arrive”.'),
    ...text('That is the shape of a good design-then-test loop. '
        'The design said what to do; the adversarial test showed '
        'the rule was necessary but not sufficient; the code '
        'grew a stricter layer; the stricter layer is now part of '
        'the contract. Nothing in the spec was wrong, only '
        'incomplete, and it is incomplete in exactly the place '
        'the test was written to look.'),

    ...sec('diff.rs: leniency, and a platform fence'),
    ...text('Two decisions here read like footnotes and have '
        'long consequences.'),
    ...bullet('no deny_unknown_fields',
        'deliberate. Internal tagging interacts badly with it in '
        'some serde versions, and rejecting unknown fields would '
        'make the contract brittle against additions that are '
        'compatible. The protocol has since grown a Stats message '
        'and a control channel, and NodeDto itself has not needed '
        'a field change.'),
    ...bullet('u64 as JSON numbers',
        'safe for the Dart VM, where int is 64-bit and jsonDecode '
        'keeps pointer-sized values intact, but “not safe under '
        'dart2js / Flutter web”, where int becomes an IEEE-754 '
        'double and values above 2^53 are silently corrupted. The '
        'spec gives the escape hatch: if the project ever targets '
        'web, ptr, id and ts must become strings.'),
    blank,
    ...text('The second decision carried through to the UI. The '
        'M5 plan locks “Dart VM / Flutter Windows desktop only — '
        'never Flutter web”, citing diff.rs’s seam note, and a Dart '
        'test is dedicated to 64-bit precision (65f1c0b). A '
        'platform limitation was written down in Stage 1, cited '
        'in Stage 5, and tested. That is the chain you want for '
        'any constraint that is silent when violated.'),
    ...text('One caution about leniency: it covers unknown '
        'fields. It does not cover unknown message types. The '
        'Dart client’s message parser throws a FormatException on '
        'a “type” it does not recognise, so adding a message kind '
        'is compatible for the Rust deserialiser and a '
        'coordinated change for the app.'),

    ...sec('the test inventory is derived from the decisions'),
    ...text('Section 6 lists seven tests, T1 to T7, and closes '
        'with a line that maps decisions to tests. This is the '
        'bridge between spec and plan, and it is worth copying:'),
    ...code('markdown', 'docs/superpowers/specs/2026-06-24-heaplens-protocol-design.md · §6 coverage (re-wrapped)', r'''
T2 exercises `read_unaligned` + `_pad` invariant.
T4 proves the incomplete-is-not-an-error path.'''),
    ...bullet('T1, T2',
        'the size, and a round-trip with deliberately awkward '
        'values: a pointer above 2^32, stack_len below the array '
        'length with zeroed trailing slots, a non-zero old_ptr.'),
    ...bullet('T3',
        'every frame type round-trips, including multiple events '
        'and multiple symbols.'),
    ...bullet('T4',
        'one frame fed a byte at a time yields exactly one frame. '
        'This is the “incomplete is not an error” rule in a test.'),
    ...bullet('T5',
        'three frames in one push come out in order.'),
    ...bullet('T6',
        'the resync case, which, as above, grew the decoder.'),
    ...bullet('T7',
        'the JSON shapes. It parses the output back into a '
        'generic value and asserts on keys, not on a substring '
        'match, so reordering fields cannot cause a false pass or '
        'a false failure.'),
    blank,
    ...text('The acceptance criteria that end the document are '
        'four lines, each checkable by a command:'),
    ...code('markdown', 'docs/superpowers/specs/2026-06-24-heaplens-protocol-design.md · §7 (trimmed)', r'''
- `cargo build` and `cargo test` pass with zero failures.
- `cargo clippy -- -D warnings` is clean.
- The crate contains no behavioral logic: no threads, no I/O,
- Nothing from Stage 2+ (heaplens-alloc, heaplens-daemon, heaplens-flutter) is present.'''),

    ...sec('what the code did next'),
    ...text('The crate that came out of this spec has grown in '
        'ways the spec could not have predicted, and the seams '
        'held:'),
    ...bullet('104 to 168 bytes',
        'sixteen stack frames instead of eight, one constant '
        'changed (see the Build Spec page).'),
    ...bullet('encoders return Option',
        'encode_events and encode_symbols now return None when '
        'the count would overflow the 16-bit field, instead of '
        'panicking. A writer-thread panic under load had broken '
        'clean detach (fa3fe78). Stage 1’s own review fixes '
        '(c360b17, f53785c) had already replaced unchecked '
        '“as u32” casts with try_from.'),
    ...bullet('a trailing byte on each symbol',
        'is_machinery, added with the φ rework.'),
    ...bullet('new messages',
        'control.rs (ControlRequest, ControlResponse, '
        'ProcessInfo) and the Stats variant of GraphMessage.'),
    blank,
    ...text('The crate has 16 test functions today, in the '
        'unit tests of event.rs and the five files under tests/.'),

    ...sec('limits, and what to take from it'),
    ...bullet('specification by prose is not machine-checked',
        'the spec contains full code listings that were copied '
        'into the repository, and nothing verifies that the '
        'document and the code still agree. The size constant is '
        'the exception: the compiler checks it.'),
    ...bullet('the leniency rule has an unwritten edge',
        'unknown message types are not lenient on the Dart side, '
        'as above.'),
    ...bullet('little-endian only',
        'the format is documented as little-endian throughout and '
        'the code never byte-swaps; the project targets Windows '
        'on x86-64 only, so the assumption is not exercised.'),
    blank,
    ...text('The portable lesson: when you design a wire format, '
        'write down the two or three decisions that look '
        'cosmetic and are not (padding, alignment, what to do '
        'with garbage) and tie each to a test. They are the ones '
        'a later change will break quietly.'),
    blank,
    link('→ github.com/XNash/heaplens', 'https://github.com/XNash/heaplens'),
  ],
);
