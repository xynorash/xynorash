import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/crates/heaplens-protocol/src/frame.rs',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'frame.rs — framing a byte stream so it can survive damage'),
    cm('//', r'three typed frames, one streaming decoder, and a resync rule that '
              r'earned its place'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', r'wire format between the allocator’s writer thread and the daemon'),
    kv('language', r'Rust, std only'),
    kv('size', r'289 lines; tests in five files under tests/'),
    kv('history', r'9 commits, 2026-06-24 to 2026-07-22'),
    kv('public surface', r'Frame, FrameDecoder, encode_handshake, encode_events, encode_symbols'),
    ...sec(r'the problem'),
    ...para('//',
        r'The producer and the daemon talk over a Windows named pipe '
        r'opened in byte mode. A byte stream has no message boundaries: '
        r'one write on the sending side may arrive as three reads, and '
        r'three writes may arrive as one. The daemon therefore cannot just '
        r'read a struct off the pipe. It needs a framing layer that (a) '
        r'says where one message ends and the next begins, (b) says what '
        r'kind of message it is, and (c) keeps working when the stream is '
        r'not as clean as the happy path assumes.'),
    blank,
    ...para('//',
        r'The Build Spec (section 3.2) fixes the shape: a length-prefixed, '
        r'typed frame, little-endian throughout, and "a streaming '
        r'FrameDecoder for the daemon that yields Frame values from a byte '
        r'stream (handles partial reads)". This file is the realisation of '
        r'that sentence, plus three things the spec did not anticipate: a '
        r'decoder that can find its feet again after garbage, encoders '
        r'that refuse to silently truncate, and a per-symbol flag added '
        r'two weeks later, in the ownership-inference fix.'),
    ...sec(r'the wire format'),
    cm('//', r'frame   = [u32 length][u8 type][payload]       all little-endian'),
    cm('//', r'length  = bytes that follow the length field = 1 + payload.len()'),
    cm('//', r' '),
    cm('//', r'0x00 HANDSHAKE  [u64 pid][u16 name_len][name, UTF-8]'),
    cm('//', r'                length = 11 + name_len'),
    cm('//', r'0x01 EVENTS     [u16 count][AllocEvent x count]'),
    cm('//', r'                length = 3 + count * 168'),
    cm('//', r'0x02 SYMBOLS    [u16 count] then per symbol:'),
    cm('//', r'                [u64 addr][u16 name_len][name][u8 is_machinery]'),
    cm('//', r'                length = 3 + sum(11 + name_len)'),
    blank,
    ...para('//',
        r'Two real examples from the tests: the handshake for the name '
        r'"before-junk" (11 bytes) is 4 + 11 + 11 = 26 bytes on the wire, '
        r'and an EVENTS frame holding one event is 4 + 3 + 168 = 175. A '
        r'writer batch of 64 events is 4 + 3 + 64 x 168 = 10,759 bytes.'),
    blank,
    ...para('//',
        r'The length does not include itself, and that detail matters '
        r'later: it is why the decoder needs to look at five bytes, not '
        r'four, before it can judge a header.'),
    ...sec(r'the Frame enum'),
    ...code('rust', 'crates/heaplens-protocol/src/frame.rs · Frame', r'''
use crate::event::AllocEvent;

#[derive(Debug)]
pub enum Frame {
    Handshake { pid: u64, name: String },
    Events(Vec<AllocEvent>),
    /// (addr, resolved name, is_machinery) — `is_machinery` is true when the
    /// writer classified this address as part of the shared instrumentation
    /// chain (capture/record/allocator shims/std alloc internals) rather
    /// than genuine caller code. See writer.rs's classification prefix set.
    Symbols(Vec<(u64, String, bool)>),
}'''),
    ...para('//',
        r'Three variants, and only Debug is derived, not PartialEq or '
        r'Clone. That is why the tests compare frames with a match and '
        r'panic with {other:?} in the fall-through arm instead of '
        r'assert_eq!.'),
    blank,
    ...para('//',
        r'The is_machinery boolean in Symbols is the youngest piece of the '
        r'wire format. It was added in commit 43fc22e on 2026-07-08, the '
        r'same commit that widened AllocEvent::stack from 8 to 16. The '
        r'writer thread classifies every resolved name (is it part of the '
        r'allocator plumbing or the user’s code?) and ships the answer '
        r'next to the name, so the daemon can find a node’s real call site '
        r'without hard-coding any knowledge of the standard library. The '
        r'cost was a format change: one trailing byte per symbol, with no '
        r'version field to announce it. Producer and daemon are built from '
        r'one Cargo workspace, so this has been cheap, but it is a '
        r'lock-step upgrade, not a negotiated one.'),
    ...sec(r'encoders: no truncating casts'),
    ...code('rust', 'crates/heaplens-protocol/src/frame.rs · encode_handshake', r'''
/// Encode a HANDSHAKE frame.
/// Wire: [u32 length][0x00][u64 pid][u16 name_len][name UTF-8]
/// length = 1 + 8 + 2 + name.len()
pub fn encode_handshake(pid: u64, name: &str) -> Vec<u8> {
    let name_bytes = name.as_bytes();
    let payload_len = 1 + 8 + 2 + name_bytes.len();
    let mut buf = Vec::with_capacity(4 + payload_len);
    buf.extend_from_slice(&u32::try_from(payload_len).expect("handshake payload exceeds u32::MAX").to_le_bytes());
    buf.push(0x00);
    buf.extend_from_slice(&pid.to_le_bytes());
    buf.extend_from_slice(&u16::try_from(name_bytes.len()).expect("name exceeds 65535 bytes").to_le_bytes());
    buf.extend_from_slice(name_bytes);
    buf
}'''),
    ...para('//',
        r'The first draft of these functions wrote (payload_len as '
        r'u32).to_le_bytes(). Later the same day, commit c360b17 replaced '
        r'every such cast with u32::try_from(...).expect(...), and f53785c '
        r'caught the one it had missed inside the encode_symbols loop. The '
        r'reasoning is the usual one for a protocol: an as cast truncates '
        r'silently, so a 70,000-byte name would be written with a length '
        r'field of 4,464 and the decoder would then misframe everything '
        r'after it. A panic with a message is a better failure than a '
        r'stream that is wrong from that byte on.'),
    blank,
    ...para('//',
        r'The handshake carries the process id as u64 and the name as '
        r'UTF-8 with a u16 length. The encoder computes the payload length '
        r'first and reserves 4 + payload_len bytes, so building a frame is '
        r'one allocation. Encoders run on the writer thread, never on the '
        r'allocation hot path, so they are allowed to allocate.'),
    ...sec(r'the u16::MAX bug, and why the fix has two layers'),
    ...code('rust', 'crates/heaplens-protocol/src/frame.rs · encode_events', r'''
/// Encode an EVENTS frame.
/// Wire: [u32 length][0x01][u16 count][AllocEvent × count]
/// length = 1 + 2 + count * AllocEvent::SIZE
///
/// Returns `None` if `events.len()` exceeds `u16::MAX` (65,535) — the
/// count field's genuine wire-format width, shared with the decoder
/// (`FrameDecoder::decode_events` also reads it as a `u16`), not just an
/// internal type choice. Defense in depth, not the real fix: the actual
/// producer-side defect this guards against — a writer-thread panic here,
/// confirmed 2026-07-22 under sustained 12-thread injection load — was
/// root-caused to `ring::drain_all` having no cap on how many events a
/// single call could pull into a batch, structurally fixed there (see its
/// doc comment) so a batch reaching anywhere near this limit should now be
/// impossible in practice. This `Option` return exists so that if it ever
/// happens anyway — a future caller with different batching assumptions,
/// a bug reintroduced elsewhere — the writer thread can degrade (log and
/// drop that batch) instead of panicking and taking clean detach down
/// with it (a panicked writer thread never reaches `mark_writer_stopped`,
/// which is exactly what broke `request_writer_stop_and_wait` here).
pub fn encode_events(events: &[AllocEvent]) -> Option<Vec<u8>> {
    let count = u16::try_from(events.len()).ok()?;
    let payload_len = 1 + 2 + events.len() * AllocEvent::SIZE;
    let mut buf = Vec::with_capacity(4 + payload_len);
    buf.extend_from_slice(&u32::try_from(payload_len).expect("events payload exceeds u32::MAX").to_le_bytes());
    buf.push(0x01);
    buf.extend_from_slice(&count.to_le_bytes());
    for ev in events {
        buf.extend_from_slice(ev.as_bytes());
    }
    Some(buf)
}'''),
    ...para('//',
        r'The doc comment on encode_events is the longest in the file '
        r'because it records an incident. On 2026-07-22 a writer thread '
        r'panicked with "events count exceeds u16::MAX" under sustained '
        r'load from 12 injected threads. The chain, from commit fa3fe78: '
        r'ring::drain_all had no cap, so a writer that fell behind could '
        r'sweep up to N threads x 65,535 events into one batch; that blew '
        r'past the writer’s intended 64-event batch and past the u16 count '
        r'field; the expect panicked; and a panicked writer never reaches '
        r'mark_writer_stopped, which is what request_writer_stop_and_wait '
        r'waits for, so clean detach broke. A bug in frame encoding '
        r'surfaced as a failed detach three modules away.'),
    blank,
    ...para('//',
        r'The real fix is structural and lives in ring.rs: drain_all now '
        r'takes a maximum, and the writer passes its remaining batch room, '
        r'so an oversized batch cannot be built at all. But the comment is '
        r'honest that this function is "defense in depth, not the real '
        r'fix". It now returns Option<Vec<u8>>: None if the count does not '
        r'fit in a u16, and the writer logs and drops that one batch '
        r'instead of dying. The principle is to make the impossible case '
        r'unrepresentable at the source and also make it survivable at the '
        r'sink. The test that pins the boundary is in '
        r'tests/frame_roundtrip.rs and checks both sides: u16::MAX events '
        r'still encode, one more returns None.'),
    ...code('rust', 'crates/heaplens-protocol/src/frame.rs · encode_symbols', r'''
/// Encode a SYMBOLS frame.
/// Wire: [u32 length][0x02][u16 count]([u64 addr][u16 name_len][name UTF-8][u8 is_machinery] × count)
///
/// Returns `None` if `symbols.len()` exceeds `u16::MAX` — same defense-in-
/// depth rationale as `encode_events`; see its doc comment. In practice
/// this list is bounded by distinct newly-seen addresses per batch (at
/// most `BATCH_CAP` events' worth of stack frames), far under the limit,
/// but the count field is the same wire-format width for the same shared-
/// with-the-decoder reason.
pub fn encode_symbols(symbols: &[(u64, &str, bool)]) -> Option<Vec<u8>> {
    let count = u16::try_from(symbols.len()).ok()?;
    let payload_body: usize = symbols.iter().map(|(_, n, _)| 8 + 2 + n.len() + 1).sum();
    let payload_len = 1 + 2 + payload_body;
    let mut buf = Vec::with_capacity(4 + payload_len);
    buf.extend_from_slice(&u32::try_from(payload_len).expect("symbols payload exceeds u32::MAX").to_le_bytes());
    buf.push(0x02);
    buf.extend_from_slice(&count.to_le_bytes());
    for (addr, name, is_machinery) in symbols {
        let name_bytes = name.as_bytes();
        buf.extend_from_slice(&addr.to_le_bytes());
        buf.extend_from_slice(&u16::try_from(name_bytes.len()).expect("symbol name exceeds 65535 bytes").to_le_bytes());
        buf.extend_from_slice(name_bytes);
        buf.push(u8::from(*is_machinery));
    }
    Some(buf)
}'''),
    ...para('//',
        r'encode_symbols has the same shape and the same Option return. It '
        r'computes payload_body with an iterator sum so the buffer is '
        r'sized exactly, then writes addr, name length, name bytes and the '
        r'is_machinery byte per symbol. The doc comment notes that in '
        r'practice the list is bounded by the number of newly seen '
        r'addresses in one batch, far below the limit.'),
    ...sec(r'the decoder is a two-state machine'),
    ...code('rust', 'crates/heaplens-protocol/src/frame.rs · state and entry point', r'''
enum DecoderState {
    NeedLength,
    NeedBody { total: usize },
}

pub struct FrameDecoder {
    state: DecoderState,
    buf:   Vec<u8>,
}

impl FrameDecoder {
    pub fn new() -> Self {
        FrameDecoder { state: DecoderState::NeedLength, buf: Vec::new() }
    }

    pub fn push(&mut self, bytes: &[u8]) {
        self.buf.extend_from_slice(bytes);
    }'''),
    ...para('//',
        r'The decoder owns a Vec<u8> buffer and a state: NeedLength '
        r'(waiting for a header) or NeedBody { total } (a header has been '
        r'accepted and total bytes are required). push just appends. All '
        r'the work happens when the caller asks for the next frame. The '
        r'original design note '
        r'(docs/superpowers/specs/2026-06-24-heaplens-protocol-design.md) '
        r'explains the split: the length prefix is the only fixed-size '
        r'field, so the machine splits on it and reads the type byte '
        r'inside the body step, which removes length - 1 arithmetic from '
        r'the state transition. The shipped code departs from that note in '
        r'one place, described below: after the resync rewrite the type '
        r'byte is read in NeedLength too, because the plausibility check '
        r'needs it.'),
    blank,
    ...para('//',
        r'The central rule is the one the doc comment states: incomplete '
        r'is never an error. If fewer bytes are buffered than needed, the '
        r'decoder returns None and changes nothing, so the next push '
        r'resumes exactly where it left off. tests/frame_partial.rs feeds '
        r'one frame one byte at a time to prove it.'),
    blank,
    ...para('//',
        r'The public interface is the Iterator trait, but the real work is '
        r'a private poll(). Commit c0f6c52 ("clippy clean") renamed the '
        r'original public next into poll and added the Iterator impl to '
        r'satisfy clippy’s should_implement_trait lint. Because next '
        r'returns None when the decoder is starved, not when the stream is '
        r'over, the iterator is, in effect, not fused: the daemon pushes '
        r'more bytes and iterates again. Here is the caller, from the '
        r'daemon’s ingest loop:'),
    ...code('rust', 'crates/heaplens-daemon/src/ingest.rs · caller in the daemon (trimmed)', r'''
let mut decoder = FrameDecoder::new();
let mut buf = vec![0u8; 4096];
let mut handshook_pid: Option<u64> = None;

loop {
    match server.read(&mut buf).await {
        Ok(0) => {
            info!("client disconnected");
            if let Some(pid) = handshook_pid {
                let _ = tx.send(GraphMsg::TargetDisconnected { pid });
            }
            break;
        }
        Ok(n) => {
            decoder.push(&buf[..n]);
            for frame in decoder.by_ref() {'''),
    ...para('//',
        r'Two details in that excerpt carry weight. The read buffer is '
        r'4,096 bytes, so the decoder is fed in small slices and its '
        r'internal buffer stays small. And the decoder is created inside '
        r'the accept loop, after server.connect(), so every new client '
        r'gets a fresh one. A frame cut in half by a disconnect cannot '
        r'contaminate the next connection, which means the resync '
        r'machinery below is defense for a stream that is already corrupt, '
        r'not something exercised by ordinary reconnects.'),
    ...sec(r'resync: finding the next frame boundary'),
    ...code('rust', 'crates/heaplens-protocol/src/frame.rs · poll(): NeedLength', r'''
fn poll(&mut self) -> Option<Frame> {
    loop {
        match self.state {
            DecoderState::NeedLength => {
                if self.buf.len() < 5 {
                    if self.buf.len() < 4 {
                        return None;
                    }
                    let length = u32::from_le_bytes(self.buf[0..4].try_into().unwrap());
                    if length == 0 || length > MAX_FRAME_LEN {
                        self.buf.drain(0..1);
                        continue;
                    }
                    return None; // valid-looking length, no type byte yet
                }

                let length = u32::from_le_bytes(self.buf[0..4].try_into().unwrap());
                let ftype  = self.buf[4];

                if !Self::is_plausible_header(length, ftype) {
                    self.buf.drain(0..1);
                    continue;
                }

                // For Handshake frames, the length is uniquely determined by the
                // name_len field (length = 11 + name_len).  If we have enough
                // bytes buffered to read name_len (15 bytes total: 4+1+8+2), cross-
                // check it to reject accidental matches in junk data.
                if ftype == 0x00 && self.buf.len() >= 15 {
                    let name_len =
                        u16::from_le_bytes(self.buf[13..15].try_into().unwrap()) as u32;
                    if length != 11 + name_len {
                        self.buf.drain(0..1);
                        continue;
                    }
                }

                let total = 4 + length as usize;
                self.state = DecoderState::NeedBody { total };
            }'''),
    ...para('//',
        r'If the header at the front of the buffer does not look like a '
        r'frame, the decoder does not give up and does not skip by the '
        r'claimed length, since a corrupt length is exactly what cannot be '
        r'trusted. It drops one byte and tries again, sliding forward '
        r'until something that looks like a header lines up. The first '
        r'check is cheap: a length of zero, or above MAX_FRAME_LEN (8 '
        r'MiB), is rejected at once. With only four bytes buffered that is '
        r'all it can judge, so it waits for the fifth.'),
    blank,
    ...para('//',
        r'With five bytes it asks is_plausible_header, which is where the '
        r'format’s structure turns into a filter:'),
    ...code('rust', 'crates/heaplens-protocol/src/frame.rs · is_plausible_header', r'''
/// Returns true if (length, ftype) looks like a real frame header.
fn is_plausible_header(length: u32, ftype: u8) -> bool {
    if length == 0 || length > MAX_FRAME_LEN {
        return false;
    }
    match ftype {
        // Handshake: length = 1(tag) + 8(pid) + 2(name_len) + name_len
        // Minimum length with no payload tag (the tag is counted differently)...
        // Actually wire layout: length field does NOT include itself (4 bytes).
        // The 4-byte length field covers the entire rest: type byte + payload.
        // Handshake payload after type byte: pid(8) + name_len_field(2) + name
        // So length = 1 + 8 + 2 + name_len = 11 + name_len, range [11, 65546].
        0x00 => (11..=MAX_HANDSHAKE_LEN).contains(&length),
        // Events: length = 1(type) + 2(count) + count * SIZE = 3 + count * SIZE
        // Valid lengths: 3, 3+SIZE, 3+2*SIZE, ...
        0x01 => {
            length >= 3
                && (length - 3).is_multiple_of(AllocEvent::SIZE as u32)
        }
        // Symbols: length = 1 + 2 + variable, minimum 3 bytes
        0x02 => length >= 3,
        _ => false,
    }
}'''),
    ...para('//',
        r'Only three type bytes are valid out of 256. For each type the '
        r'length has to fit that type’s arithmetic. A handshake length '
        r'must be between 11 and 65,546 (MAX_HANDSHAKE_LEN: 1 + 8 + 2 + '
        r'65,535). An events length must be 3 plus a whole number of '
        r'168-byte records, so roughly one random length in 168 passes. A '
        r'symbols length only has to be at least 3, because symbol names '
        r'are variable-length and there is no arithmetic to check; that is '
        r'the weakest filter of the three and it comes up again under '
        r'limits.'),
    blank,
    ...para('//',
        r'The comment block under the handshake arm is unedited thinking: '
        r'"Minimum length with no payload tag (the tag is counted '
        r'differently)... Actually wire layout: length field does NOT '
        r'include itself". It was written in the same commit as the logic '
        r'and never tidied. It is a small, honest artefact of working the '
        r'arithmetic out in place, and the conclusion it reaches (length '
        r'is 11 + name_len, range 11 to 65,546) is correct.'),
    blank,
    ...para('//',
        r'A handshake gets one more cross-check. Its length is fully '
        r'determined by its name_len field (length = 11 + name_len), so '
        r'once 15 bytes are buffered the decoder compares the two and '
        r'rejects a mismatch. The comment says it exists "to reject '
        r'accidental matches in junk data". The next section shows the '
        r'accident it was written for.'),
    ...sec(r'the test that forced all of this'),
    ...code('rust', 'crates/heaplens-protocol/tests/frame_resync.rs · T6: the junk', r'''
// Junk: a u32 length prefix of 0xFF_FF_FF_FF (> MAX_FRAME_LEN = 8 MiB),
// followed by a few bytes. The decoder must drain one byte at a time until
// it resyncs onto valid2's length prefix.
let junk: Vec<u8> = {
    let mut j = Vec::new();
    j.extend_from_slice(&u32::MAX.to_le_bytes()); // absurd length
    j.extend_from_slice(&[0xAA, 0xBB, 0xCC]);    // padding noise
    j
};'''),
    ...para('//',
        r'The first version of the decoder, in commit ca4e501, was the '
        r'simple one from the design note: if length is zero or above 8 '
        r'MiB, drop a byte; otherwise wait for length bytes and decode or '
        r'skip. Then the T6 test was written (commit ea9b3b2, "resync '
        r'after absurd length prefix"): a valid handshake, then seven '
        r'bytes of junk starting with a length of 0xFFFFFFFF, then a valid '
        r'events frame. The same commit rewrote the decoder into the '
        r'plausibility-checking version in this file.'),
    blank,
    ...para('//',
        r'A replay shows why. Taking the tree of commit ea9b3b2 with '
        r'frame.rs reverted to the ca4e501 decoder and running the T6 test '
        r'against it fails at the second expect, "frame 2 (after junk)" '
        r'(tests/frame_resync.rs, line 42 of that version). Working the '
        r'bytes by hand explains it. The old decoder slides one byte at a '
        r'time through the junk and accepts the first four-byte window '
        r'whose value is nonzero and at most 8 MiB. At that commit '
        r'AllocEvent::SIZE was still 104, so the real events frame began '
        r'with the length 107 (bytes 6B 00 00 00). The window BB CC 6B 00 '
        r'reads as 7,064,763, just under the 8 MiB cap, and the old '
        r'decoder would accept it, switch to NeedBody, and wait for about '
        r'7 MB that never come, swallowing the real events frame. (With '
        r'today’s 168-byte event the length byte is 0xAB and the trap '
        r'moves one byte later: BB CC AB 00 is 11,259,067 and is rejected, '
        r'but CC AB 00 00 is 0xABCC = 43,980, legal under 8 MiB.) Either '
        r'way, the junk and the real frame’s own length byte conspire to '
        r'make a fake header just before the real one.'),
    blank,
    ...para('//',
        r'With the new rules the fake window dies. Take today’s numbers: '
        r'the type byte after CC AB 00 00 is 0x00 (a handshake), 43,980 is '
        r'within the handshake range, and then the cross-check rejects it, '
        r'because the bytes where a name_len would sit are zero and 43,980 '
        r'is not 11. The decoder drops one more byte, sees length 171 with '
        r'type 0x01 and a length that is 3 plus one 168-byte event, and '
        r'decodes the frame. This is the whole case for typed '
        r'plausibility: a bare length check is not enough when the junk '
        r'can land next to a real header.'),
    ...sec(r'when the header is fine but the body is not'),
    ...code('rust', 'crates/heaplens-protocol/src/frame.rs · poll(): NeedBody', r'''
    DecoderState::NeedBody { total } => {
        if self.buf.len() < total {
            return None; // incomplete — not an error
        }
        let frame_bytes: Vec<u8> = self.buf.drain(0..total).collect();
        self.state = DecoderState::NeedLength;

        let ftype   = frame_bytes[4];
        let payload = &frame_bytes[5..];

        match Self::decode_payload(ftype, payload) {
            Some(frame) => return Some(frame),
            None => {
                // Payload failed to decode despite valid-looking header —
                // resync from byte 1 of what we thought was the frame start.
                let mut prepend = frame_bytes[1..].to_vec();
                prepend.extend_from_slice(&self.buf);
                self.buf = prepend;
                continue;
            }
        }
    }
}'''),
    ...para('//',
        r'Once a header is accepted and enough bytes are buffered, the '
        r'frame is drained into its own Vec and decoded. If decode_payload '
        r'returns None, the decoder does not discard the whole frame, even '
        r'though a valid-looking length was trusted a moment ago. The '
        r'comment says it all: "resync from byte 1 of what we thought was '
        r'the frame start". It rebuilds the buffer as frame_bytes[1..] '
        r'followed by whatever was already waiting, and goes round the '
        r'loop again.'),
    blank,
    ...para('//',
        r'That differs from the Stage 1 design note, which says malformed '
        r'content with a trustworthy length drains total bytes and resets. '
        r'The code is more paranoid, and the reason reads as follows (an '
        r'inference; the comment does not spell it out): a header that '
        r'passed the plausibility filter may itself be a coincidence in '
        r'junk, in which case the real frame boundary is somewhere inside '
        r'the bytes just consumed and skipping them would lose it. '
        r'Re-scanning from the next byte costs time on bad input and loses '
        r'nothing on good input.'),
    ...sec(r'decoding the payloads'),
    ...code('rust', 'crates/heaplens-protocol/src/frame.rs · decode_events', r'''
fn decode_events(payload: &[u8]) -> Option<Frame> {
    // payload: [u16 count][AllocEvent × count]
    if payload.len() < 2 {
        return None;
    }
    let count = u16::from_le_bytes(payload[0..2].try_into().unwrap()) as usize;
    if payload.len() != 2 + count * AllocEvent::SIZE {
        return None;
    }
    let mut events = Vec::with_capacity(count);
    for i in 0..count {
        let start = 2 + i * AllocEvent::SIZE;
        let ev = AllocEvent::from_bytes(&payload[start..start + AllocEvent::SIZE])?;
        events.push(ev);
    }
    Some(Frame::Events(events))
}'''),
    ...para('//',
        r'Each decoder returns Option<Frame> and treats any inconsistency '
        r'as None. decode_events requires the payload length to equal 2 + '
        r'count * SIZE exactly, then slices the events out and hands each '
        r'to AllocEvent::from_bytes. decode_handshake requires 10 + '
        r'name_len exactly and valid UTF-8. Exact-length checks are what '
        r'make a mis-framed body detectable.'),
    ...code('rust', 'crates/heaplens-protocol/src/frame.rs · decode_symbols', r'''
fn decode_symbols(payload: &[u8]) -> Option<Frame> {
    // payload: [u16 count]([u64 addr][u16 name_len][name UTF-8][u8 is_machinery] × count)
    if payload.len() < 2 {
        return None;
    }
    let count  = u16::from_le_bytes(payload[0..2].try_into().unwrap()) as usize;
    let mut cursor = 2usize;
    let mut syms   = Vec::with_capacity(count);
    for _ in 0..count {
        if cursor + 10 > payload.len() {
            return None;
        }
        let addr     = u64::from_le_bytes(payload[cursor..cursor + 8].try_into().unwrap());
        let name_len = u16::from_le_bytes(payload[cursor + 8..cursor + 10].try_into().unwrap()) as usize;
        cursor += 10;
        if cursor + name_len + 1 > payload.len() {
            return None;
        }
        let name = std::str::from_utf8(&payload[cursor..cursor + name_len]).ok()?.to_owned();
        cursor += name_len;
        let is_machinery = payload[cursor] != 0;
        cursor += 1;
        syms.push((addr, name, is_machinery));
    }
    Some(Frame::Symbols(syms))
}'''),
    ...para('//',
        r'decode_symbols is the odd one out. It walks the payload with a '
        r'cursor, checking before each read that enough bytes remain, but '
        r'at the end it does not check that the cursor reached the end of '
        r'the payload. Trailing bytes are ignored. Taken with the weak '
        r'plausibility rule for type 0x02, that makes SYMBOLS the frame '
        r'type most likely to accept something that is not one. In normal '
        r'operation this cannot matter, since the sender is the repo’s own '
        r'encoder, but a hardening pass on the decoder would start here.'),
    ...sec(r'what is covered, and by which file'),
    ...pt('//',
        r'frame_roundtrip.rs',
        r'every frame type survives encode then decode, plus the u16 '
        r'boundary (see that page).'),
    ...pt('//',
        r'frame_partial.rs',
        r'one frame fed one byte at a time yields exactly one frame.'),
    ...pt('//',
        r'frame_multi.rs',
        r'three frames in one push come out in order, then None.'),
    ...pt('//',
        r'frame_resync.rs',
        r'the T6 test above.'),
    ...pt('//',
        r'daemon tests',
        r'ingest_loopback.rs round-trips frames through this decoder, and '
        r'cross_process_wire.rs runs the real wire_producer example over '
        r'the named pipe into it.'),
    ...sec(r'limits, measured and read'),
    ...code('rust', 'crates/heaplens-protocol/src/frame.rs · the constants and a stale comment', r'''
const MAX_FRAME_LEN: u32 = 8 * 1024 * 1024; // 8 MiB

// Per-type maximum payload sizes, used to reject implausible length prefixes
// during resync without waiting for the full body to arrive.
//   Handshake (0x00): 1 tag + 8 pid + 2 name_len + 65535 name  = 65546
//   Events    (0x01): 1 tag + 2 count + 65535 * AllocEvent::SIZE (≈6.6 MiB, but capped by MAX_FRAME_LEN)
//   Symbols   (0x02): 1 tag + 2 count + 65535 * (8+2+65535+1) (> MAX_FRAME_LEN — no extra cap needed)
const MAX_HANDSHAKE_LEN: u32 = 1 + 8 + 2 + 65535; // 65546'''),
    ...para('//',
        r'The size comment above is stale: "Events (0x01): 1 tag + 2 count '
        r'+ 65535 * AllocEvent::SIZE (about 6.6 MiB, but capped by '
        r'MAX_FRAME_LEN)". That was true when SIZE was 104 (65,535 x 104 '
        r'is about 6.5 MiB). With SIZE at 168 the full-count figure is '
        r'65,535 x 168 = 11,009,880 bytes, about 10.5 MiB, which exceeds '
        r'the 8 MiB cap. So the encoder will happily produce a frame, for '
        r'any count up to 65,535, that the decoder will never accept: the '
        r'largest EVENTS frame whose length is at most MAX_FRAME_LEN holds '
        r'49,932 events (3 + 49,932 x 168 = 8,388,579; one more event '
        r'crosses 8,388,608). Running it in a scratch crate confirms that '
        r'49,932 events encode and decode in one frame (about 10 ms to '
        r'decode). Feeding the decoder 49,933 events, whose length field '
        r'is 8,388,747, had not finished after 20 seconds when it was '
        r'stopped: the first header is over the cap, so the decoder drops '
        r'one byte at a time from an 8 MiB buffer, which is the quadratic '
        r'cost below at work. The boundary test in frame_roundtrip.rs encodes '
        r'exactly u16::MAX events, a frame far above MAX_FRAME_LEN, and '
        r'only asserts that it is Some, so no test pins the mismatch, and '
        r'nothing can reach it today because the writer batches at 64.'),
    blank,
    ...para('//',
        r'Resync cost is quadratic in the amount of junk. Each dropped '
        r'byte is a Vec::drain(0..1), which shifts the rest of the buffer. '
        r'In release-mode runs on a Linux sandbox (not a benchmark, only '
        r'the shape; repeated twice, with the same pattern), pushing 0xFF '
        r'junk through the decoder in one call took about 1 ms for 16 KiB, '
        r'3 ms for 32 KiB, 21 to 26 ms for 64 KiB and 143 to 147 ms for '
        r'128 KiB: each doubling of the junk costs three to eight times '
        r'as much. Fed in '
        r'4,096-byte chunks, the way ingest.rs does it, 128 KiB took 2 to '
        r'4 ms because the buffer never grows. The daemon’s small read '
        r'size is what keeps this harmless; a caller that pushed megabytes '
        r'at once would find out.'),
    blank,
    ...para('//',
        r'A bogus but plausible header makes the decoder wait for up to 8 '
        r'MiB of further bytes before it can reject it, and everything '
        r'that arrives in that window is consumed as that frame’s body. '
        r'For EVENTS and HANDSHAKE the filters make this unlikely, and for '
        r'SYMBOLS they do not. There is no checksum, no magic number and '
        r'no version byte. The format is built for a trusted local pipe '
        r'whose failure mode is a producer that exits mid-write, and that '
        r'is the failure it handles.'),
    ...sec(r'timeline'),
    ...pt('//',
        r'2026-06-24',
        r'eb5d33b Frame enum and the three encoders; c360b17 and f53785c '
        r'replace truncating casts; ca4e501 first decoder; ea9b3b2 the '
        r'plausibility rewrite forced by T6; c0f6c52 Iterator impl.'),
    ...pt('//',
        r'2026-07-08',
        r'43fc22e adds the is_machinery byte to every symbol.'),
    ...pt('//',
        r'2026-07-22',
        r'fa3fe78 turns encode_events and encode_symbols into '
        r'Option-returning functions and caps the batch at its source.'),
    blank,
    link('→ github.com/xynorash/heaplens · crates/heaplens-protocol/src/frame.rs',
        'https://github.com/xynorash/heaplens/blob/master/crates/heaplens-protocol/src/frame.rs'),
  ],
);
