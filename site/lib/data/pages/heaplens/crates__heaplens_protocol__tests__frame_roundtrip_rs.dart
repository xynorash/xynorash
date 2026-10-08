import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/crates/heaplens-protocol/tests/frame_roundtrip.rs',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'frame_roundtrip.rs — encode, decode, compare, and the day it grew a '
              r'boundary test'),
    cm('//', r'five tests, one of them a regression for a thread that died under load'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', r'every frame type survives encode then decode; the u16 count limit '
              r'fails soft'),
    kv('language', r'Rust integration test'),
    kv('size', r'101 lines, 5 tests (design note id T3 plus a 2026-07-22 regression)'),
    kv('history', r'7573f0e (2026-06-24), 43fc22e (2026-07-08), fa3fe78 (2026-07-22)'),
    kv('exercises', r'encode_handshake, encode_events, encode_symbols, FrameDecoder'),
    ...sec(r'the idea of a round-trip test'),
    ...para('//',
        r'The simplest property of a codec is that decode(encode(x)) == x. '
        r'It catches the bugs that matter most in a wire format: a field '
        r'written in one order and read in another, a length computed '
        r'wrongly, a byte of padding counted on one side only. This file '
        r'is that property for each of the three frame types, written '
        r'against the public API (the names the crate exports at its '
        r'root), so it tests what the writer and the daemon actually call.'),
    blank,
    ...para('//',
        r'Because Frame derives only Debug, the assertions do not compare '
        r'whole frames. Each test matches on the variant, then compares '
        r'the pieces, and uses a panic with the {other:?} of the '
        r'unexpected frame in the fall-through arm so a failure prints '
        r'what arrived instead.'),
    ...sec(r'the handshake'),
    ...code('rust', 'crates/heaplens-protocol/tests/frame_roundtrip.rs · helper and handshake_round_trip', r'''
use heaplens_protocol::{
    AllocEvent, EventKind, Frame, FrameDecoder,
    encode_events, encode_handshake, encode_symbols,
};

fn make_decoder_with(bytes: &[u8]) -> FrameDecoder {
    let mut d = FrameDecoder::new();
    d.push(bytes);
    d
}

#[test]
fn handshake_round_trip() {
    let encoded = encode_handshake(12345, "test-process");
    let mut dec = make_decoder_with(&encoded);
    match dec.next().expect("expected a frame") {
        Frame::Handshake { pid, name } => {
            assert_eq!(pid, 12345);
            assert_eq!(name, "test-process");
        }
        other => panic!("wrong variant: {other:?}"),
    }
    assert!(dec.next().is_none());
}'''),
    ...para('//',
        r'make_decoder_with is a two-line helper that creates a '
        r'FrameDecoder and pushes a byte slice. The handshake test encodes '
        r'pid 12345 and the name test-process, decodes, and checks both '
        r'fields, then checks that the decoder is empty with '
        r'dec.next().is_none(). That last line appears in every test in '
        r'the file and matters more than it looks: an encoder that wrote a '
        r'trailing byte too many would leave the decoder with a stray '
        r'byte, and a later push would be mis-framed; asserting "nothing '
        r'left" is how a length bug shows up in the test where it was '
        r'introduced.'),
    blank,
    ...para('//',
        r'Probes in a scratch crate (not part of the repo) go beyond the '
        r'cases the file covers: an empty name encodes to 15 bytes and '
        r'decodes back; a name of 65,535 bytes, the u16 maximum, encodes '
        r'to 65,550 bytes and decodes; and a name with Cyrillic and '
        r'Japanese characters (21 bytes for 9 characters) survives, so '
        r'lengths are in bytes, not characters, on both sides.'),
    ...sec(r'many events in one frame'),
    ...code('rust', 'crates/heaplens-protocol/tests/frame_roundtrip.rs · sample_event and events_round_trip_multiple', r'''
fn sample_event(n: u64) -> AllocEvent {
    let mut stack = [0u64; 16];
    stack[0] = 0x7fff_0000_0000_0000 + n;
    AllocEvent::new(EventKind::Alloc, 0x2000_0000_0000 + n, 0, 64 + n, 8, 1_000_000 + n, stack, 1)
}

#[test]
fn events_round_trip_multiple() {
    let events = vec![sample_event(1), sample_event(2), sample_event(3)];
    let encoded = encode_events(&events).expect("well under u16::MAX");
    let mut dec = make_decoder_with(&encoded);
    match dec.next().expect("expected a frame") {
        Frame::Events(decoded) => {
            assert_eq!(decoded.len(), 3);
            assert_eq!(decoded[0], events[0]);
            assert_eq!(decoded[1], events[1]);
            assert_eq!(decoded[2], events[2]);
        }
        other => panic!("wrong variant: {other:?}"),
    }
    assert!(dec.next().is_none());
}'''),
    ...para('//',
        r'sample_event(n) derives every field from n: the pointer is '
        r'0x2000_0000_0000 + n, the size is 64 + n, the timestamp is '
        r'1_000_000 + n, and stack[0] is 0x7fff_0000_0000_0000 + n. The '
        r'test builds events 1, 2 and 3, encodes them in a single frame, '
        r'and compares each decoded event with its original by index. '
        r'Because every event differs in every field, a decoder that '
        r'reversed the order, repeated the first event, or dropped a field '
        r'would fail on a specific assertion.'),
    blank,
    ...para('//',
        r'The tests use no random data. Fixed, distinct values make a '
        r'failure reproducible and the message readable. The value of '
        r'stack_len is 1 in all three, so a decoder that mishandled '
        r'variable stack depths would not be caught here; the event.rs '
        r'unit tests cover that, with a stack_len of 3 and thirteen '
        r'trailing zeros.'),
    ...sec(r'the regression: when the encoder became fallible'),
    ...code('rust', 'crates/heaplens-protocol/tests/frame_roundtrip.rs · the u16 boundary', r'''
/// Regression for the writer-thread panic found under sustained 12-thread
/// injection load (2026-07-22): `encode_events`/`encode_symbols` used to
/// `.expect()` the `u16` count conversion, panicking the writer thread on an
/// oversized batch and breaking clean detach (a panicked writer never calls
/// `mark_writer_stopped`). The real fix is capping `ring::drain_all` so a
/// batch can never structurally reach this size — this test covers the
/// defense-in-depth boundary itself: given a batch that does exceed
/// `u16::MAX` (however that came to be), encoding must fail gracefully
/// (`None`), never panic.
#[test]
fn encode_events_returns_none_instead_of_panicking_when_over_u16_max() {
    let event = sample_event(1);
    let oversized: Vec<AllocEvent> = std::iter::repeat(event)
        .take(u16::MAX as usize + 1)
        .collect();
    assert_eq!(encode_events(&oversized), None, "must fail gracefully, not panic");

    // One under the limit still encodes fine — confirms the boundary is
    // exactly u16::MAX, not off-by-one in either direction.
    let at_limit: Vec<AllocEvent> = std::iter::repeat(event)
        .take(u16::MAX as usize)
        .collect();
    assert!(encode_events(&at_limit).is_some(), "exactly u16::MAX must still encode");
}

#[test]
fn encode_symbols_returns_none_instead_of_panicking_when_over_u16_max() {
    let oversized: Vec<(u64, &str, bool)> = std::iter::repeat((0x1234u64, "sym", false))
        .take(u16::MAX as usize + 1)
        .collect();
    assert_eq!(encode_symbols(&oversized), None, "must fail gracefully, not panic");
}'''),
    ...para('//',
        r'This is the part of the file with a story. On 2026-07-22, under '
        r'sustained load from 12 injected threads, the writer thread '
        r'inside the target process panicked with "events count exceeds '
        r'u16::MAX". The doc comment on the test says the rest: '
        r'encode_events and encode_symbols used to call .expect() on the '
        r'conversion of the item count to a u16, so an oversized batch '
        r'panicked the writer thread, and "a panicked writer never calls '
        r'mark_writer_stopped", which broke clean detach. The page for '
        r'frame.rs tells the full chain.'),
    blank,
    ...para('//',
        r'The real fix was in ring::drain_all, which now takes a cap so '
        r'that a batch cannot be built that large. This test covers the '
        r'other layer, the one the comment calls "the defense-in-depth '
        r'boundary itself": given a batch that does exceed u16::MAX, '
        r'however that came to be, encoding must fail gracefully, with '
        r'None, and never panic.'),
    blank,
    ...para('//',
        r'The two halves of the test are the lesson. The first builds '
        r'65,536 copies of one event (u16::MAX + 1) and asserts that '
        r'encode_events returns None. The second builds exactly u16::MAX '
        r'and asserts that it still encodes. The comment says why: '
        r'"confirms the boundary is exactly u16::MAX, not off-by-one in '
        r'either direction". A test that only checked the failing side '
        r'would pass for a broken encoder that rejected everything over, '
        r'say, 60,000. A boundary test needs a point on each side.'),
    blank,
    ...para('//',
        r'The sibling test, '
        r'encode_symbols_returns_none_instead_of_panicking_when_over_u16_max, '
        r'covers the same limit for the SYMBOLS frame with 65,536 copies '
        r'of (0x1234, "sym", false). It only checks the failing side; '
        r'there is no at-limit case for symbols.'),
    blank,
    ...para('//',
        r'There are two layers of defence and two layers of test. The '
        r'cause (an unbounded drain) is tested in heaplens-alloc, in the '
        r'ring tests '
        r'drain_all_stops_at_the_cap_leaving_the_rest_for_next_call and '
        r'drain_all_cap_can_stop_mid_ring_across_multiple_producers. The '
        r'consequence (an encoder that cannot panic) is tested here. If '
        r'someone removed the cap in ring.rs, the first would catch it; if '
        r'someone replaced the Option with an expect again, this one '
        r'would.'),
    ...sec(r'what can still panic'),
    ...para('//',
        r'The Option return covers the count, not the lengths. In '
        r'frame.rs, encode_handshake still calls expect on the name length '
        r'("name exceeds 65535 bytes") and encode_symbols still calls '
        r'expect on each symbol name’s length. The handshake name is the '
        r'executable’s file stem, which is short in practice. Each symbol '
        r'name is a demangled function path, and a pathological one over '
        r'65,535 bytes would still panic the writer thread. No test covers '
        r'either. This comes from reading the encoders, not from observing '
        r'a failure; it is the same class of risk as the one this '
        r'regression fixed, left in a place that is unlikely to be '
        r'reached.'),
    ...sec(r'symbols'),
    ...code('rust', 'crates/heaplens-protocol/tests/frame_roundtrip.rs · symbols_round_trip_multiple', r'''
#[test]
fn symbols_round_trip_multiple() {
    let syms: Vec<(u64, &str, bool)> = vec![
        (0x7fff_dead_0001, "alloc::vec::Vec::push", true),
        (0x7fff_dead_0002, "std::collections::HashMap::insert", false),
        (0x7fff_dead_0003, "my_crate::foo::bar", false),
    ];
    let encoded = encode_symbols(&syms).expect("well under u16::MAX");
    let mut dec = make_decoder_with(&encoded);
    match dec.next().expect("expected a frame") {
        Frame::Symbols(decoded) => {
            assert_eq!(decoded.len(), 3);
            assert_eq!(decoded[0], (syms[0].0, syms[0].1.to_owned(), syms[0].2));
            assert_eq!(decoded[1], (syms[1].0, syms[1].1.to_owned(), syms[1].2));
            assert_eq!(decoded[2], (syms[2].0, syms[2].1.to_owned(), syms[2].2));
        }
        other => panic!("wrong variant: {other:?}"),
    }
    assert!(dec.next().is_none());
}'''),
    ...para('//',
        r'Three symbols with the flag set differently: the first, '
        r'alloc::vec::Vec::push, is marked machinery (true), the other two '
        r'are not. This is the test that pins the is_machinery byte added '
        r'to the format on 2026-07-08: if the encoder wrote the flag but '
        r'the decoder read it from the wrong offset, or applied the first '
        r'flag to all, the three comparisons would diverge. Each element '
        r'is compared as a tuple against its source, with the &str '
        r'converted by to_owned() because the decoded form holds Strings.'),
    blank,
    ...para('//',
        r'The names are chosen to look like real symbols (std paths and a '
        r'crate path), but the test does not exercise anything about their '
        r'content. A zero-length name and a name with multi-byte '
        r'characters are the cases a round-trip test for a variable-length '
        r'field normally adds. For symbols they were not probed; for the '
        r'handshake they were (above), and an empty events frame and an '
        r'empty symbols frame also decode, as Events(0) and Symbols(0). '
        r'None of those are pinned in the repo.'),
    ...sec(r'history in three lines'),
    ...pt('//',
        r'7573f0e, 2026-06-24',
        r'T3, the three original round-trips.'),
    ...pt('//',
        r'43fc22e, 2026-07-08',
        r'symbols gain the is_machinery boolean and the event stack grows '
        r'to 16; the test literals change with them.'),
    ...pt('//',
        r'fa3fe78, 2026-07-22',
        r'the two Option-returning tests and the .expect(...) calls on the '
        r'encoders added.'),
    ...sec(r'related'),
    ...pt('//',
        r'frame.rs',
        r'the encoders and decoder under test, and the incident behind the '
        r'regression.'),
    ...pt('//',
        r'heaplens-alloc/src/ring.rs',
        r'where the real fix for the oversized batch lives, and its tests.'),
    blank,
    link('→ github.com/xynorash/heaplens · crates/heaplens-protocol/tests/frame_roundtrip.rs',
        'https://github.com/xynorash/heaplens/blob/master/crates/heaplens-protocol/tests/frame_roundtrip.rs'),
  ],
);
