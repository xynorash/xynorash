import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/crates/heaplens-protocol/tests/frame_multi.rs',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'frame_multi.rs — three frames, one push, strict order'),
    cm('//', r'the opposite of a partial read: a burst that must be split back apart'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', r'checks the decoder yields each frame in order and then stops'),
    kv('language', r'Rust integration test'),
    kv('size', r'46 lines, 1 test (design note id T5)'),
    kv('history', r'added 2026-06-24 (b269610); touched again for the Option-returning '
              r'encoders'),
    kv('exercises', r'all three encoders and all three Frame variants'),
    ...sec(r'the property being pinned'),
    ...para('//',
        r'frame_partial.rs checks that a frame can arrive in pieces. This '
        r'file checks the reverse: that several frames arriving glued '
        r'together are separated correctly. On a real pipe both happen. '
        r'When the producer’s writer thread connects, it writes a '
        r'HANDSHAKE first and then SYMBOLS and EVENTS frames as soon as '
        r'its first batch is flushed, and a single 4,096-byte read on the '
        r'daemon side can contain the tail of one frame, whole small '
        r'frames, and the head of the next.'),
    blank,
    ...para('//',
        r'The decoder is designed so that push appends and next returns '
        r'one frame at a time. The caller’s loop, in the daemon’s '
        r'ingest.rs, is for frame in decoder.by_ref(). The contract this '
        r'test fixes is that the loop sees every frame, in wire order, and '
        r'terminates when the buffer holds no complete frame.'),
    ...sec(r'the test'),
    ...code('rust', 'crates/heaplens-protocol/tests/frame_multi.rs · three_frames_in_one_push', r'''
use heaplens_protocol::{AllocEvent, EventKind, Frame, FrameDecoder,
                        encode_events, encode_handshake, encode_symbols};

#[test]
fn three_frames_in_one_push() {
    let event = AllocEvent::new(
        EventKind::Alloc, 0x1000_0000_0001, 0, 128, 8, 42_000_000, [0u64; 16], 0,
    );
    let f1 = encode_handshake(99, "multi-test");
    let f2 = encode_events(&[event]).expect("well under u16::MAX");
    let f3 = encode_symbols(&[(0x7fff_1234_5678, "some::symbol", false)]).expect("well under u16::MAX");

    let mut combined = Vec::new();
    combined.extend_from_slice(&f1);
    combined.extend_from_slice(&f2);
    combined.extend_from_slice(&f3);

    let mut dec = FrameDecoder::new();
    dec.push(&combined);

    match dec.next().expect("frame 1") {
        Frame::Handshake { pid, name } => {
            assert_eq!(pid, 99);
            assert_eq!(name, "multi-test");
        }
        other => panic!("frame 1 wrong variant: {other:?}"),
    }

    match dec.next().expect("frame 2") {
        Frame::Events(events) => {
            assert_eq!(events.len(), 1);
            assert_eq!(events[0], event);
        }
        other => panic!("frame 2 wrong variant: {other:?}"),
    }

    match dec.next().expect("frame 3") {
        Frame::Symbols(syms) => {
            assert_eq!(syms.len(), 1);
            assert_eq!(syms[0], (0x7fff_1234_5678, "some::symbol".to_owned(), false));
        }
        other => panic!("frame 3 wrong variant: {other:?}"),
    }

    assert!(dec.next().is_none());
}'''),
    ...para('//',
        r'The three frames are deliberately different kinds, one of each. '
        r'A handshake for pid 99 named multi-test, an EVENTS frame holding '
        r'one Alloc event, and a SYMBOLS frame with one entry. They are '
        r'concatenated into one Vec<u8>, pushed once, and then the test '
        r'calls dec.next() four times.'),
    blank,
    ...para('//',
        r'Calls one to three each unwrap with expect("frame N") and match '
        r'on the variant. The second assertion on each is on content, not '
        r'just type: the pid and the name, the single event equal to the '
        r'original, the tuple (0x7fff_1234_5678, "some::symbol", false) in '
        r'the symbols list. The fourth call must be None. That last line '
        r'is what proves the decoder stops cleanly and does not '
        r'manufacture a frame out of leftover state or a zero-length '
        r'remainder.'),
    blank,
    ...para('//',
        r'Notice the false in the symbol tuple. It is the is_machinery '
        r'flag that the wire format gained on 2026-07-08. The tests in '
        r'this directory were updated in the same commit as the format '
        r'change (43fc22e touched frame_multi.rs, frame_partial.rs, '
        r'frame_resync.rs and frame_roundtrip.rs), which is exactly the '
        r'cost of changing a wire format and the reason the tests are '
        r'written against the public encoders: when the byte layout '
        r'changed, only the literal arguments needed editing, not any '
        r'hand-built byte arrays.'),
    ...sec(r'why one of each kind'),
    ...para('//',
        r'A test with three events frames would pass with a decoder that '
        r'only understood EVENTS. Using one of each exercises the '
        r'decoder’s dispatch on the type byte (0x00, 0x01, 0x02) in a '
        r'single stream, and, more subtly, it exercises the transitions '
        r'between frames of different shape: after a variable-length '
        r'symbols payload the decoder must land exactly on the next '
        r'header. Here the symbols frame is last, so the boundary being '
        r'tested is handshake-to-events and events-to-symbols.'),
    blank,
    ...para('//',
        r'The handshake is first, mirroring the protocol’s rule from the '
        r'Build Spec that "HANDSHAKE is the first frame sent after the '
        r'pipe connects". The decoder itself does not enforce an order; it '
        r'is the daemon’s ingest loop that treats a Handshake as the '
        r'signal that a target has connected.'),
    ...sec(r'what it does not cover'),
    ...pt('//',
        r'Bursts mixed with partial tails',
        r'the whole combined buffer is pushed at once. There is no case '
        r'where the burst ends in half a frame. frame_partial.rs and the '
        r'probe described in that page’s notes cover the partial tail '
        r'separately.'),
    ...pt('//',
        r'Repeated frames of one kind',
        r'events_round_trip_multiple in frame_roundtrip.rs covers many '
        r'events inside one frame, but no test in this crate has two '
        r'EVENTS frames in a row. The loop in the daemon depends on that '
        r'constantly.'),
    ...pt('//',
        r'Ordering under reconnect',
        r'the decoder is created per connection in ingest.rs, so '
        r'cross-connection ordering is not the decoder’s problem.'),
    ...sec(r'a note on the iterator style'),
    ...para('//',
        r'The test reads dec.next() directly rather than looping, which '
        r'makes each expectation explicit and gives a named failure '
        r'message per frame. Production code uses the iterator in a for '
        r'loop. Both rely on the same design choice made in commit '
        r'c0f6c52: next is a thin wrapper over a private poll(), so the '
        r'Iterator impl and direct calls are the same code path and the '
        r'test is testing what the daemon runs.'),
    ...sec(r'related'),
    ...pt('//',
        r'frame.rs',
        r'the wire format and the decoder.'),
    ...pt('//',
        r'frame_partial.rs',
        r'bytes arriving late rather than early.'),
    ...pt('//',
        r'frame_roundtrip.rs',
        r'each frame type on its own, plus the size limits.'),
    blank,
    link('→ github.com/xynorash/heaplens · crates/heaplens-protocol/tests/frame_multi.rs',
        'https://github.com/xynorash/heaplens/blob/master/crates/heaplens-protocol/tests/frame_multi.rs'),
  ],
);
