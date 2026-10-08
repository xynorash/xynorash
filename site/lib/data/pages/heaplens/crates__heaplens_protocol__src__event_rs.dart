import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/crates/heaplens-protocol/src/event.rs',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'event.rs — the 168-byte record every allocation becomes'),
    cm('//', r'one fixed-size repr(C) struct is the whole capture vocabulary'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', r'the unit of capture; the payload of every EVENTS frame'),
    kv('language', r'Rust, repr(C), zero dependencies'),
    kv('size', r'141 lines, 4 unit tests'),
    kv('layout', r'168 bytes, 8-byte aligned, no implicit padding'),
    kv('history', r'4 commits, 2026-06-24 to 2026-07-08'),
    ...sec(r'why this file exists'),
    ...para('//',
        r'Every call that reaches the global allocator becomes exactly one '
        r'AllocEvent: an allocation, a free, or a realloc. This struct is '
        r'the only thing that travels from the hot path inside the '
        r'observed process (heaplens-alloc, record()) to the writer '
        r'thread, and from the writer thread across the named pipe to the '
        r'daemon. Everything downstream, the ownership graph, the anomaly '
        r'sweep, the UI, is derived from a stream of these records.'),
    blank,
    ...para('//',
        r'The central decision is to make that record a flat, fixed-size, '
        r'plain-old-data struct rather than an enum with variable payloads '
        r'or a serialized format. Two consequences are visible elsewhere '
        r'in the repo. ring.rs can allocate the whole per-thread ring as '
        r'one flat array (Layout::array::<AllocEvent>(CAP)) and never '
        r'touch the allocator again. And frame.rs can validate an EVENTS '
        r'frame by arithmetic alone: the payload must be exactly 2 + count '
        r'* AllocEvent::SIZE bytes, no parsing required.'),
    blank,
    ...para('//',
        r'The crate this lives in is deliberately data only. The Build '
        r'Spec (sections 1.1 and 3) says the protocol crate has "zero '
        r'behavior": no threads, no I/O, no logic beyond '
        r'(de)serialization. event.rs is the purest part of that: a '
        r'struct, one enum, a constructor and two unsafe byte views.'),
    ...sec(r'the layout, byte by byte'),
    cm('//', r'offset  size  field       meaning'),
    cm('//', r'------  ----  ----------  ------------------------------------'),
    cm('//', r'   0      1   kind        0 Alloc, 1 Dealloc, 2 Realloc'),
    cm('//', r'   1      1   stack_len   how many entries of stack are valid'),
    cm('//', r'   2      2   _pad        explicit padding, always zero'),
    cm('//', r'   4      4   align       layout.align() of the allocation'),
    cm('//', r'   8      8   ptr         address returned (or freed)'),
    cm('//', r'  16      8   old_ptr     previous address, Realloc only'),
    cm('//', r'  24      8   size        bytes requested'),
    cm('//', r'  32      8   ts_nanos    monotonic ns since process start'),
    cm('//', r'  40    128   stack       16 raw instruction pointers'),
    cm('//', r'------  ----  ----------  ------------------------------------'),
    cm('//', r'total  168'),
    blank,
    ...para('//',
        r'The offsets follow from repr(C) field order with natural '
        r'alignment; the Build Spec lists the same offsets (@0, @1, @2, '
        r'@4, @8, @16, @24, @32, @40) for the original 104-byte version. '
        r'The header before the stack is 40 bytes, and 16 pointers of 8 '
        r'bytes add 128, which is where 168 comes from.'),
    ...code('rust', 'crates/heaplens-protocol/src/event.rs · the struct (trimmed)', r'''
#[repr(C)]
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub struct AllocEvent {
    pub kind:      u8,
    pub stack_len: u8,
    pub _pad:      [u8; 2],
    pub align:     u32,
    pub ptr:       u64,
    pub old_ptr:   u64,
    pub size:      u64,
    pub ts_nanos:  u64,
...
    pub stack:     [u64; 16],
}'''),
    ...para('//',
        r'Two choices here are worth reading closely. First, kind is a '
        r'plain u8, not an EventKind. The enum next to it has a from_u8 '
        r'that returns Option, which suggests the reason (the code does '
        r'not state it): these bytes arrive over a pipe, and a repr(u8) '
        r'enum holding an undeclared discriminant is undefined behaviour '
        r'the moment it is read. Keeping the field a u8 and validating on '
        r'use means a corrupt byte is a value you can match on, not UB. '
        r'The daemon’s main loop does exactly that: it matches ev.kind '
        r'against the literals 0, 1 and 2 and has a final arm, _ => {}, '
        r'that ignores everything else.'),
    blank,
    ...para('//',
        r'Second, the padding is an explicit field. The comment inside '
        r'as_bytes spells out why: with repr(C) and a named _pad there is '
        r'no implicit compiler padding, so every one of the 168 bytes '
        r'belongs to an initialised field and viewing the struct as bytes '
        r'is sound. Implicit padding would be uninitialised memory, and '
        r'reading it as u8 is the classic way to make a zero-copy view '
        r'unsound.'),
    ...sec(r'constructing one'),
    ...code('rust', 'crates/heaplens-protocol/src/event.rs · new()', r'''
impl AllocEvent {
    pub const SIZE: usize = 168;

    #[allow(clippy::too_many_arguments)]
    pub fn new(
        kind:      EventKind,
        ptr:       u64,
        old_ptr:   u64,
        size:      u64,
        align:     u32,
        ts_nanos:  u64,
        stack:     [u64; 16],
        stack_len: u8,
    ) -> Self {
        AllocEvent {
            kind: kind as u8,
            stack_len,
            _pad: [0, 0],
            align,
            ptr,
            old_ptr,
            size,
            ts_nanos,
            stack,
        }
    }'''),
    ...para('//',
        r'AllocEvent::new is the one blessed constructor, and the reason '
        r'is the line _pad: [0, 0]. The comment on as_bytes is careful to '
        r'separate two concerns: soundness (guaranteed by the explicit '
        r'field) and determinism (guaranteed by new zeroing it, so the '
        r'wire output never leaks whatever happened to be in a stack '
        r'slot). The Stage 1 design note is explicit that producers must '
        r'never use struct-literal syntax for this type.'),
    blank,
    ...para('//',
        r'The signature takes the EventKind enum and converts with kind as '
        r'u8, so the write side is typed while the read side stays raw. It '
        r'also takes eight arguments, which is why clippy needed an allow. '
        r'A builder would be one more layer on a path that must not '
        r'allocate, so the plain argument list reads as the cheap option '
        r'(an inference; the code does not discuss it).'),
    ...sec(r'two unsafe blocks, both justified in place'),
    ...code('rust', 'crates/heaplens-protocol/src/event.rs · as_bytes / from_bytes', r'''
pub fn as_bytes(&self) -> &[u8] {
    // SAFETY: AllocEvent is repr(C) with an explicit `_pad` field, so
    // there is no implicit compiler padding — all SIZE bytes belong to
    // initialized fields. Lifetime is tied to &self.
    // (AllocEvent::new zero-initializes `_pad` for deterministic, leak-free
    // wire output — a contract concern, not a soundness one.)
    unsafe {
        std::slice::from_raw_parts(self as *const AllocEvent as *const u8, Self::SIZE)
    }
}

pub fn from_bytes(buf: &[u8]) -> Option<AllocEvent> {
    if buf.len() < Self::SIZE {
        return None;
    }
    // SAFETY: length checked above; read_unaligned makes no alignment
    // assumption about the incoming byte buffer.
    Some(unsafe { (buf.as_ptr() as *const AllocEvent).read_unaligned() })
}'''),
    ...para('//',
        r'as_bytes returns a slice over the struct itself: no copy, no '
        r'allocation, lifetime tied to the borrow. encode_events in '
        r'frame.rs uses it to append each event to the outgoing frame '
        r'(buf.extend_from_slice(ev.as_bytes())), and the writer thread '
        r'is its caller. from_bytes goes the other '
        r'way and uses read_unaligned, and the comment says why: the input '
        r'is a byte slice from the wire, guaranteed only one-byte '
        r'alignment, while AllocEvent contains u64 fields and wants eight. '
        r'A normal pointer read at an unaligned address is undefined '
        r'behaviour on the abstract machine even where the hardware '
        r'tolerates it.'),
    blank,
    ...para('//',
        r'There is an asymmetry to be aware of. Frame headers are written '
        r'with explicit to_le_bytes, but the event body is the in-memory '
        r'image of the struct. That makes the event payload native-endian '
        r'by construction. On this project (Windows, x86_64, '
        r'little-endian) the two agree; the Build Spec asks for the '
        r'little-endian assumption to be stated rather than hidden, and '
        r'this is where it is baked in.'),
    ...sec(r'the compile-time size check'),
    ...code('rust', 'crates/heaplens-protocol/src/event.rs · SIZE and the assertion', r'''
const _: () = assert!(core::mem::size_of::<AllocEvent>() == AllocEvent::SIZE);

impl AllocEvent {
    pub const SIZE: usize = 168;'''),
    ...para('//',
        r'SIZE is a hand-maintained constant and the assertion makes the '
        r'compiler check it. If a field is added or resized and SIZE is '
        r'not updated, the crate stops compiling, which is much better '
        r'than a daemon that decodes every EVENTS frame as garbage at run '
        r'time. The unit test t1_size_of_alloc_event repeats the number as '
        r'a literal 168, a second tripwire written in a different place, '
        r'so that changing the constant requires touching the test too.'),
    blank,
    ...para('//',
        r'This is not hypothetical. When the stack grew, SIZE went from '
        r'104 to 168 in commit 43fc22e, and the diff shows the constant, '
        r'the array types and the t1 literals all changing together. The '
        r'compiler caught nothing because nothing was inconsistent; the '
        r'two tripwires were just there to make sure it stayed that way.'),
    ...sec(r'the day eight frames were not enough'),
    ...code('rust', 'crates/heaplens-protocol/src/event.rs · the doc comment on stack', r'''
/// Raw, unfiltered instruction pointers from the capture point downward.
/// 16 frames (up from 8): the zeroed-allocation path (`vec![0u8; n]`,
/// the idiom used throughout this project's producers) inserts 6+
/// non-inlined std frames between the shared instrumentation and the
/// real call site, so 8 frames can contain zero user frames. Consumers
/// (daemon-side phi matching, symbol display) locate the real call site
/// by classifying frames via the writer-resolved SYMBOLS frame, not by
/// a fixed index — see heaplens-daemon's graph.rs `effective_site`.
pub stack:     [u64; 16],'''),
    ...para('//',
        r'The original spec had stack: [u64; 8]. On 2026-07-08 commit '
        r'43fc22e ("fix(phi): function-name-granularity ownership '
        r'inference") widened it to 16 as one of four layered bugs that '
        r'were stopping ownership inference from ever producing a single '
        r'real edge. The doc comment above is the post-mortem, written '
        r'where the next reader will trip over it.'),
    blank,
    ...para('//',
        r'The mechanism: a raw backtrace starts inside the instrumentation '
        r'(capture_stack, then record, then the allocator method) and '
        r'walks outward. With vec![0u8; n] the standard library adds more '
        r'frames, because HeapLensAlloc implements alloc, dealloc and '
        r'realloc but not alloc_zeroed, so std falls back to its default '
        r'alloc_zeroed which then calls alloc. The tests in writer.rs list '
        r'core::alloc::global::GlobalAlloc::alloc_zeroed among the frames '
        r'classified as machinery, which is consistent with that picture. '
        r'Six or more non-inlined std frames sat between the '
        r'instrumentation and the user function, so an eight-entry window '
        r'could hold no user frame at all, and the ownership inference had '
        r'nothing to match.'),
    blank,
    ...para('//',
        r'The rejected alternative is named in the comment: consumers must '
        r'not locate the call site by a fixed index. The capture.rs doc '
        r'comment gives the reason, that the depth of std frames varies by '
        r'allocation API, so any constant skip count would be wrong for '
        r'some path. Instead the writer classifies each resolved frame as '
        r'machinery or not and ships that flag in the SYMBOLS frame (the '
        r'third element of each Symbols tuple in frame.rs), and the daemon '
        r'takes the first frame that is not machinery '
        r'(effective_site_index in graph.rs). Capture stays dumb and '
        r'cheap; judgment moves off the hot path.'),
    blank,
    ...para('//',
        r'The price is arithmetic you can check against the constants. '
        r'Each event grows from 104 to 168 bytes, a 61.5 percent increase. '
        r'The length field of a 64-event EVENTS frame (type byte, count '
        r'and events, 3 + n x SIZE) goes from 3 + 64 x 104 = 6,659 '
        r'to 3 + 64 x 168 = 10,755; the 64 matches the writer’s '
        r'BATCH_CAP. The 65,536-slot per-thread ring '
        r'in ring.rs goes from 65,536 x 104 = 6,815,744 bytes (6.5 MiB) to '
        r'65,536 x 168 = 11,010,048 bytes (10.5 MiB) for every thread that '
        r'allocates.'),
    blank,
    ...para('//',
        r'The same commit message names the other three bugs, and they '
        r'make a good checklist for how a feature can be broken in layers: '
        r'the Frame::Symbols the writer sent was being discarded by the '
        r'daemon, matching was done on instruction addresses instead of '
        r'function names, and the __rust_alloc shims, which are namespaced '
        r'under the consuming binary, were not being classified as '
        r'machinery. Fixing any one alone would have left the graph empty.'),
    ...sec(r'what the tests pin'),
    ...code('rust', 'crates/heaplens-protocol/src/event.rs · unit tests', r'''
#[test]
fn t1_size_of_alloc_event() {
    assert_eq!(core::mem::size_of::<AllocEvent>(), 168);
    assert_eq!(AllocEvent::SIZE, 168);
}

#[test]
fn t2_round_trip() {
    let mut stack = [0u64; 16];
    stack[0] = 0x0000_7fff_dead_beef;
    stack[1] = 0x0000_7fff_cafe_babe;
    stack[2] = 0x0000_7fff_1234_5678;

    let original = AllocEvent::new(
        EventKind::Realloc,
        0x0000_2000_0000_0010,
        0x0000_1fff_ffff_fff0,
        0x0000_0000_0001_0000,
        16,
        9_999_999_999,
        stack,
        3,
    );

    let bytes = original.as_bytes();
    assert_eq!(bytes.len(), AllocEvent::SIZE);

    let decoded = AllocEvent::from_bytes(bytes).expect("from_bytes failed");
    assert_eq!(decoded, original);
}

#[test]
fn t2_from_bytes_too_short() {
    let short = [0u8; 10];
    assert!(AllocEvent::from_bytes(&short).is_none());
}

#[test]
fn eventkind_from_u8() {
    assert_eq!(EventKind::from_u8(0), Some(EventKind::Alloc));
    assert_eq!(EventKind::from_u8(1), Some(EventKind::Dealloc));
    assert_eq!(EventKind::from_u8(2), Some(EventKind::Realloc));
    assert_eq!(EventKind::from_u8(3), None);
    assert_eq!(EventKind::from_u8(255), None);
}'''),
    ...para('//',
        r'Each test is there for a reason. t1 is the literal-size '
        r'tripwire. t2_round_trip is chosen with care: it uses Realloc so '
        r'the kind byte is not zero (commit c688dd7 changed it from Alloc '
        r'for exactly that, so a round trip that dropped the kind would be '
        r'visible), a non-zero old_ptr, a size of exactly 2^16, and a stack '
        r'with only three of sixteen entries set and stack_len = 3, so the '
        r'thirteen trailing zeros must also survive. The design note asked '
        r'for at least one u64 above 2^32; ptr here is '
        r'0x0000_2000_0000_0010, about 2^45.'),
    blank,
    ...para('//',
        r't2_from_bytes_too_short feeds ten bytes and expects None, which '
        r'is the only validation from_bytes does. eventkind_from_u8 checks '
        r'the three valid values and two invalid ones, 3 and 255. '
        r'Running the crate for this page (cargo test -p '
        r'heaplens-protocol --offline, on a Linux sandbox) gives a green '
        r'protocol suite: 16 tests, 4 of them in this file.'),
    ...sec(r'limits and things to know'),
    ...pt('//',
        r'no version or magic',
        r'the struct has no version byte, so a producer and a daemon '
        r'built with different SIZE values disagree silently, and the '
        r'symptom would be frames that mostly fail the length '
        r'arithmetic in frame.rs and get stepped over one byte at a time '
        r'(an inference from the decoder), not a clear error. The flip side '
        r'is that the Stage 7 design doc could promise "No wire schema '
        r'change" for injection: the injected hook sends the same '
        r'records as every cooperative producer.'),
    ...pt('//',
        r'no validation of contents',
        r'from_bytes accepts any bit pattern of the right length. kind is '
        r'not checked against 0 to 2 and stack_len is not clamped to 16. '
        r'Reading the daemon: graph.rs walks 0..stack_len and indexes '
        r'stack[i], so a corrupt stack_len above 16 would be an '
        r'out-of-range index. The pipe is local and the producer is this '
        r'repo’s own writer, so this is a trust-boundary note, not a known '
        r'failure.'),
    ...pt('//',
        r'addresses are process-local',
        r'the Build Spec (section 4.6) says the instruction pointers are '
        r'only meaningful inside the observed process, where the platform '
        r'symbolizer can resolve them. That is why symbol resolution '
        r'happens in the writer thread and ships names, rather than the '
        r'daemon resolving addresses later.'),
    ...pt('//',
        r'fixed stack cost',
        r'all 128 bytes of stack are always sent, even when stack_len is '
        r'3. Uniform slots buy the flat ring and the arithmetic '
        r'validation; the price is bandwidth on shallow stacks.'),
    ...pt('//',
        r'single architecture',
        r'64-bit fields throughout and native-endian bodies. The project '
        r'targets Windows x86_64 only.'),
    ...sec(r'related pages'),
    ...pt('//',
        r'frame.rs',
        r'wraps these records in typed, length-prefixed frames and decodes '
        r'them back from a byte stream.'),
    ...pt('//',
        r'heaplens-alloc/src/ring.rs',
        r'the per-thread ring whose slots are exactly this struct.'),
    ...pt('//',
        r'heaplens-alloc/src/capture.rs',
        r'fills stack and ts_nanos without allocating.'),
    ...pt('//',
        r'heaplens-alloc/src/writer.rs',
        r'classifies frames as machinery so the 16-frame window can be '
        r'interpreted.'),
    blank,
    link('→ github.com/xynorash/heaplens · crates/heaplens-protocol/src/event.rs',
        'https://github.com/xynorash/heaplens/blob/master/crates/heaplens-protocol/src/event.rs'),
  ],
);
