import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/crates/heaplens-protocol/tests/frame_resync.rs',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'frame_resync.rs — the test that rewrote the decoder'),
    cm('//', r'seven bytes of junk between two good frames, and a fake header hiding '
              r'in them'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', r'proves the decoder recovers from a corrupt length prefix'),
    kv('language', r'Rust integration test'),
    kv('size', r'51 lines, 1 test (design note id T6)'),
    kv('history', r'added with ea9b3b2 on 2026-06-24, in the same commit as the decoder '
              r'rewrite it demanded'),
    kv('replayed', r'run against the decoder from ca4e501, this test fails'),
    ...sec(r'the scenario'),
    ...code('rust', 'crates/heaplens-protocol/tests/frame_resync.rs · setup: two good frames around junk', r'''
#[test]
fn resync_after_absurd_length_prefix() {
    // Two valid frames sandwiching junk with an absurd length prefix.
    // The junk bytes must not prevent either valid frame from decoding.
    let event = AllocEvent::new(
        EventKind::Dealloc, 0x5555_0000_0001, 0, 64, 8, 1, [0u64; 16], 0,
    );
    let valid1 = encode_handshake(1, "before-junk");
    let valid2 = encode_events(&[event]).expect("well under u16::MAX");

    // Junk: a u32 length prefix of 0xFF_FF_FF_FF (> MAX_FRAME_LEN = 8 MiB),
    // followed by a few bytes. The decoder must drain one byte at a time until
    // it resyncs onto valid2's length prefix.
    let junk: Vec<u8> = {
        let mut j = Vec::new();
        j.extend_from_slice(&u32::MAX.to_le_bytes()); // absurd length
        j.extend_from_slice(&[0xAA, 0xBB, 0xCC]);    // padding noise
        j
    };

    let mut combined = Vec::new();
    combined.extend_from_slice(&valid1);
    combined.extend_from_slice(&junk);
    combined.extend_from_slice(&valid2);

    let mut dec = FrameDecoder::new();
    dec.push(&combined);'''),
    ...para('//',
        r'Frame one is a handshake for pid 1 named before-junk. Frame two '
        r'is an EVENTS frame holding a Dealloc event. Between them sits '
        r'junk made of a u32 length prefix of 0xFFFFFFFF, far above the '
        r'decoder’s 8 MiB cap (MAX_FRAME_LEN), followed by three padding '
        r'bytes 0xAA, 0xBB, 0xCC. Everything is pushed in a single call. '
        r'The test then asserts that the first frame decodes, the second '
        r'frame decodes after the decoder has slid past the junk, and '
        r'nothing is left over.'),
    blank,
    ...para('//',
        r'The scenario models a realistic way a stream goes wrong on '
        r'a local pipe: a producer that died mid-write, or a reconnect '
        r'that left the decoder half-way through a frame. (The page for '
        r'frame.rs notes that ingest.rs creates a fresh decoder per '
        r'connection, so ordinary reconnects do not reach this path.) '
        r'The design note '
        r'records the decision the test pins: when the length prefix is '
        r'untrustworthy (zero, or above the cap), "do NOT skip by it"; '
        r'drop one byte and try again.'),
    ...sec(r'the assertions'),
    ...code('rust', 'crates/heaplens-protocol/tests/frame_resync.rs · recovery', r'''
// First valid frame decodes before the junk
match dec.next().expect("frame 1 (before junk)") {
    Frame::Handshake { pid, name } => {
        assert_eq!(pid, 1);
        assert_eq!(name, "before-junk");
    }
    other => panic!("frame 1 wrong variant: {other:?}"),
}

// Second valid frame decodes after the decoder resyncs past the junk
match dec.next().expect("frame 2 (after junk)") {
    Frame::Events(events) => {
        assert_eq!(events.len(), 1);
        assert_eq!(events[0], event);
    }
    other => panic!("frame 2 wrong variant: {other:?}"),
}

assert!(dec.next().is_none());'''),
    ...para('//',
        r'The first match proves the junk did not damage the frame before '
        r'it. The second, labelled "frame 2 (after junk)", is the one that '
        r'matters: it proves that after consuming the junk the decoder '
        r'lands on the start of the next real frame. The final '
        r'dec.next().is_none() shows there are no phantom frames from the '
        r'leftovers.'),
    blank,
    ...para('//',
        r'The wording of the failure messages is deliberate. If the test '
        r'fails, it says which frame was lost, and the name of the second '
        r'one describes the exact hazard: a frame after junk.'),
    ...sec(r'the trap inside seven bytes'),
    ...para('//',
        r'This is the story behind the file. The first decoder, from '
        r'commit ca4e501, followed the simplest design: read four bytes as '
        r'a length; if it is zero or above 8 MiB, drop one byte and look '
        r'again; otherwise trust it and wait for that many bytes. The T6 '
        r'test was written next, and it failed. Replaying that: the tree '
        r'of ea9b3b2 with src/frame.rs reverted to the ca4e501 decoder, in '
        r'a scratch directory, dies at the second expect, "frame 2 (after '
        r'junk)", at tests/frame_resync.rs line 42 of that version.'),
    blank,
    ...para('//',
        r'The reason is in the bytes. The decoder slides one byte at a '
        r'time through the junk, and the real EVENTS frame follows the '
        r'junk. At that commit AllocEvent::SIZE was still 104, so the real '
        r'frame’s length was 107, the byte 6B followed by three zeros. '
        r'Each window the old decoder sees:'),
    blank,
    cm('//', r'offset  window bytes   as u32 (LE)    length-only check'),
    cm('//', r'------  -------------  -------------  -----------------------------'),
    cm('//', r'  0     FF FF FF FF    4,294,967,295  reject, above 8 MiB'),
    cm('//', r'  1     FF FF FF AA    2,868,903,935  reject'),
    cm('//', r'  2     FF FF AA BB    3,148,546,047  reject'),
    cm('//', r'  3     FF AA BB CC    3,434,851,071  reject'),
    cm('//', r'  4     AA BB CC 6B    1,808,579,498  reject'),
    cm('//', r'  5     BB CC 6B 00    7,064,763      ACCEPT: a fake header'),
    cm('//', r'  6     CC 6B 00 00    27,596         (would also pass)'),
    cm('//', r'  7     6B 00 00 00    107            the real frame'),
    blank,
    ...para('//',
        r'At offset 5, the last two junk bytes followed by the first two '
        r'bytes of the real frame’s length read as 7,064,763. That is '
        r'under the 8 MiB cap (8,388,608), so a length-only decoder '
        r'accepts it, enters NeedBody, and waits for 7,064,767 bytes that '
        r'will never arrive, because the real frame is only 111 bytes. The '
        r'real frame is swallowed into a body that never completes, and '
        r'the test’s second expect fails. The values in the table are '
        r'arithmetic on the test’s own bytes (the junk is fixed, the '
        r'length is 3 plus one 104-byte event), and the failure of the '
        r'old decoder is what the replay shows.'),
    blank,
    ...para('//',
        r'The fix, in the same commit, taught the decoder to judge a '
        r'header by length and type together (is_plausible_header) and to '
        r'cross-check handshake lengths against their embedded name '
        r'length. At offset 5 the type byte is 0x00, so the window is '
        r'judged as a handshake, and 7,064,763 is far outside the '
        r'handshake range of 11 to 65,546. At offset 6, 27,596 is inside '
        r'that range, but the cross-check expects 11 + name_len with '
        r'name_len read as 0, which is 11, so it rejects it. One more '
        r'drop, and the window at offset 7 is a valid events header: type '
        r'0x01, length 107 = 3 + 104.'),
    blank,
    ...para('//',
        r'The file as it stands today has the same bytes but a 168-byte '
        r'event, so the real length is 171 (AB 00 00 00) and the trap '
        r'shifts by one: BB CC AB 00 is 11,259,067 and is rejected by '
        r'the cap alone, while CC AB 00 00 is 0xABCC = 43,980, which only '
        r'the handshake cross-check stops. The test is a regression for '
        r'the mechanism at either size, which is why it is worth '
        r'having the junk sit directly against a real frame.'),
    ...sec(r'what the lesson is'),
    ...para('//',
        r'Test the failure you fear with bytes that are adjacent to real '
        r'data. The junk here is not random noise: its last byte combined '
        r'with the genuine frame’s first bytes is what built the fake '
        r'header. A test with junk padded by zeros, or junk followed by a '
        r'frame whose length bytes happen not to line up, would have '
        r'passed the naive decoder. This one fails because the author put '
        r'real frames on both sides and looked at what the sliding window '
        r'actually sees.'),
    blank,
    ...para('//',
        r'It is also a good example of a test driving a design. The commit '
        r'is titled "test(protocol): T6 resync after absurd length '
        r'prefix", yet its stat shows 51 new lines of test against 81 '
        r'changed lines in src/frame.rs: the plausibility function, the '
        r'per-type length ranges, the handshake cross-check and the '
        r'resync-from-byte-one rule for bodies that fail to decode.'),
    ...sec(r'what it does not cover'),
    ...pt('//',
        r'junk that looks like a symbols header',
        r'type 0x02 accepts any length of at least 3, so there is no '
        r'arithmetic to reject a fake SYMBOLS header. No test builds one.'),
    ...pt('//',
        r'a corrupt body with a good length',
        r'the decoder re-scans from the next byte if decode_payload fails, '
        r'but no test feeds it a frame with a valid header and an invalid '
        r'payload (a handshake whose name_len disagrees with its length, '
        r'say).'),
    ...pt('//',
        r'large junk',
        r'resync costs O(n) per dropped byte, so it is quadratic in the '
        r'amount of junk. Measured in a scratch crate: 64 KiB of 0xFF in '
        r'one push took 21 to 26 ms, and 128 KiB took 143 to 147 ms. The '
        r'test’s junk is seven bytes.'),
    ...sec(r'related'),
    ...pt('//',
        r'frame.rs',
        r'the plausibility rules this test forced.'),
    ...pt('//',
        r'frame_partial.rs',
        r'bytes that are late rather than wrong.'),
    blank,
    link('→ github.com/xynorash/heaplens · crates/heaplens-protocol/tests/frame_resync.rs',
        'https://github.com/xynorash/heaplens/blob/master/crates/heaplens-protocol/tests/frame_resync.rs'),
  ],
);
