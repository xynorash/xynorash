import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/crates/heaplens-protocol/tests/frame_partial.rs',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'frame_partial.rs — the pipe hands you bytes, not messages'),
    cm('//', r'one 175-byte frame, delivered 175 times, must decode exactly once'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', r'proves "incomplete is never an error" in the frame decoder'),
    kv('language', r'Rust integration test'),
    kv('size', r'39 lines, 1 test (design note id T4)'),
    kv('history', r'added 2026-06-24 in commit 07c9f7f; two later one-line edits (43fc22e, '
              r'fa3fe78)'),
    kv('exercises', r'FrameDecoder::push, FrameDecoder::next, encode_events'),
    ...sec(r'the property being pinned'),
    ...para('//',
        r'A named pipe in byte mode is a stream. A single write by the '
        r'producer can arrive in several reads, and the daemon reads into '
        r'a 4,096-byte buffer. That second number is the one to stare at: '
        r'a full writer batch is 64 events, which on the wire is 4 + 3 + '
        r'64 x 168 = 10,759 bytes, so in production a full EVENTS frame '
        r'cannot fit in one read. It always arrives in at least three '
        r'pieces. Partial delivery is therefore not an edge case the '
        r'decoder might meet someday; it is the ordinary case for the '
        r'busiest frame type.'),
    blank,
    ...para('//',
        r'The Stage 1 design note puts the requirement in one line: '
        r'"Incomplete is never an error." Fewer bytes than needed returns '
        r'None and changes nothing, and the next push resumes exactly '
        r'where it left off. This test is the proof, taken to the extreme: '
        r'deliver the frame one byte at a time.'),
    ...sec(r'the test'),
    ...code('rust', 'crates/heaplens-protocol/tests/frame_partial.rs · single_frame_fed_one_byte_at_a_time', r'''
use heaplens_protocol::{AllocEvent, EventKind, Frame, FrameDecoder, encode_events};

#[test]
fn single_frame_fed_one_byte_at_a_time() {
    let mut stack = [0u64; 16];
    stack[0] = 0x7fff_cafe_babe_0001;
    let event = AllocEvent::new(
        EventKind::Realloc,
        0x0000_3000_0000_0010,
        0x0000_2fff_ffff_fff0,
        256,
        16,
        5_000_000_000,
        stack,
        1,
    );
    let encoded = encode_events(&[event]).expect("well under u16::MAX");

    let mut dec = FrameDecoder::new();
    let mut frames_seen = 0usize;
    let mut result: Option<Frame> = None;

    for byte in &encoded {
        dec.push(std::slice::from_ref(byte));
        while let Some(frame) = dec.next() {
            frames_seen += 1;
            result = Some(frame);
        }
    }

    assert_eq!(frames_seen, 1, "expected exactly one frame");
    match result.expect("frame should have decoded") {
        Frame::Events(events) => {
            assert_eq!(events.len(), 1);
            assert_eq!(events[0], event);
        }
        other => panic!("wrong variant: {other:?}"),
    }
}'''),
    ...para('//',
        r'The setup builds one Realloc event with a recognisable stack[0] '
        r'(0x7fff_cafe_babe_0001), encodes it as an EVENTS frame, and then '
        r'loops over the encoded bytes. For each byte it pushes a one-byte '
        r'slice (std::slice::from_ref(byte), no allocation per byte), then '
        r'drains the decoder with while let Some(frame) = dec.next(). It '
        r'counts frames seen and keeps the last one.'),
    blank,
    ...para('//',
        r'Two assertions follow. frames_seen must be exactly 1, which is '
        r'stronger than "the frame eventually appears": it rules out a '
        r'decoder that emits a phantom frame on partial data or '
        r'double-decodes. And the single frame must be an Events variant '
        r'holding one event equal to the original, so the content survived '
        r'being assembled from 175 pieces. The match with panic!("wrong '
        r'variant: {other:?}") is the idiom the whole test directory uses, '
        r'because Frame derives Debug but not PartialEq.'),
    ...sec(r'what happens at each byte'),
    ...para('//',
        r'It is worth walking the decoder through those 175 pushes, '
        r'because each range of byte counts lands in a different branch of '
        r'poll() in frame.rs.'),
    blank,
    cm('//', r'bytes buffered   decoder state / branch                  result'),
    cm('//', r'--------------   -------------------------------------   ------'),
    cm('//', r'1 .. 3           NeedLength, fewer than 4 bytes          None'),
    cm('//', r'4                NeedLength, 4 bytes: length is read      None'),
    cm('//', r'                 and judged, type byte not yet here'),
    cm('//', r'5                NeedLength, header complete and          state becomes'),
    cm('//', r'                 plausible (type 0x01, 171 = 3 + 168)     NeedBody{175}'),
    cm('//', r'6 .. 174         NeedBody, buf shorter than total         None'),
    cm('//', r'175              NeedBody, buf.len() == total             Some(Events)'),
    blank,
    ...para('//',
        r'The special case at four bytes is the interesting one. It exists '
        r'because of the T6 resync work on the same day (commit ea9b3b2): '
        r'once the decoder started judging a header by length and type '
        r'together, it needed five bytes, but it still has to reject an '
        r'absurd length as early as possible. So with exactly four bytes '
        r'buffered it checks the length alone, drains a byte if the length '
        r'is already impossible, and otherwise returns None with the '
        r'comment "valid-looking length, no type byte yet". If that branch '
        r'wrongly drained a byte when the length was fine, a '
        r'one-byte-at-a-time feed would eat the start of the frame and '
        r'this test would fail.'),
    ...sec(r'what it does not cover, and what a probe shows'),
    ...para('//',
        r'This test feeds one frame. It does not feed a stream of several '
        r'frames cut at random points, and it never splits a frame inside '
        r'the payload of a SYMBOLS or HANDSHAKE (only an EVENTS frame is '
        r'used). A probe in a scratch crate, not part of the repo, tests '
        r'whether the property generalises: a handshake split at every '
        r'possible byte position, 0 through its full length, produced '
        r'exactly one frame each time, and never before the last byte '
        r'arrived. A second probe pushed a complete EVENTS frame and then '
        r'the first 50 bytes of another; the decoder returned the first, '
        r'returned None for the second, and returned it correctly once the '
        r'remaining bytes were pushed, so a partial trailing frame is '
        r'retained rather than dropped.'),
    blank,
    ...para('//',
        r'The test also does not time anything. Feeding one byte at a time '
        r'is cheap here, but each call goes through poll(), so a decoder '
        r'that re-scanned the whole buffer on every push would pass this '
        r'test and still be slow. The decoder does not do that: in '
        r'NeedBody it compares buf.len() to total and returns.'),
    ...sec(r'why the file is this small'),
    ...para('//',
        r'The design note assigned it an identifier (T4) and a single '
        r'sentence of acceptance: "Single frame fed one byte at a time → '
        r'exactly one Frame produced with correct contents". It was '
        r'committed in 07c9f7f on 2026-06-24, the first of the frame tests '
        r'to land (T4 went in before T3, the round-trip file). It has been '
        r'edited twice since, each time by a single line. Commit 43fc22e '
        r'on 2026-07-08 widened the stack array from 8 to 16 entries. '
        r'Commit fa3fe78 on 2026-07-22 added .expect("well under '
        r'u16::MAX") to the encode_events call once the encoder began '
        r'returning Option. That second one-line diff is the only trace in '
        r'this file of the writer-thread panic story told on the frame.rs '
        r'page.'),
    ...sec(r'related'),
    ...pt('//',
        r'frame.rs',
        r'the decoder this test drives, and the two-state machine it '
        r'exercises.'),
    ...pt('//',
        r'frame_multi.rs',
        r'the opposite shape: many frames delivered in a single push.'),
    ...pt('//',
        r'frame_resync.rs',
        r'what the decoder does when the bytes are not just late but '
        r'wrong.'),
    blank,
    link('→ github.com/xynorash/heaplens · crates/heaplens-protocol/tests/frame_partial.rs',
        'https://github.com/xynorash/heaplens/blob/master/crates/heaplens-protocol/tests/frame_partial.rs'),
  ],
);
