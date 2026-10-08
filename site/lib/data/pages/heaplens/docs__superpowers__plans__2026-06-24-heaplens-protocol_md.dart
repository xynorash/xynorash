import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/docs/superpowers/plans/2026-06-24-heaplens-protocol.md',
  lines: [
    heading('# heaplens-protocol Implementation Plan'),
    blank,
    ...text('The first of five plans: twelve tasks, each with the '
        'files it touches, the code to write, the command that '
        'proves it works, and the exact commit message to use. '
        'The repository’s history shows it being followed, and '
        'shows the four places where reality improved on it.'),
    blank,
    kv('role', 'task-by-task build plan for Stage 1 (the contract crate)'),
    kv('date', '2026-06-24, in the first commit (a55f7c1)'),
    kv('size', '1,130 lines · 12 tasks · 1 acceptance checklist'),
    kv('executed', '21:17 to 21:44 the same evening, 16 commits'),
    kv('companion', 'specs/2026-06-24-heaplens-protocol-design.md'),

    ...sec('what kind of document this is'),
    ...text('The Build Spec says what to build. The Stage 1 '
        'design spec says how to resolve the ambiguous parts. '
        'This plan says what to type, in what order, and how to '
        'know each step worked. It is written for an executor who '
        'will not ask questions, and the header says so:'),
    ...code('markdown', 'docs/superpowers/plans/2026-06-24-heaplens-protocol.md · header (trimmed)', r'''
> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
Steps use checkbox (`- [ ]`) syntax for tracking.'''),
    ...text('Below the header sit a goal, an architecture '
        'paragraph and a tech stack (Rust 2021, serde, '
        'serde_json as a dev-dependency only). Then a file map '
        'in table form: every file the stage creates, with its '
        'responsibility, so the executor knows the whole shape '
        'before starting. The design spec is referred to as the '
        'authority: “all decisions locked there; do not '
        're-derive them”.'),

    ...sec('anatomy of a task'),
    ...text('Every task follows one pattern. Files to create or '
        'modify, then numbered steps with checkboxes, then a '
        'verification command with its expected output, then the '
        'commit. The verification step is written out, not left '
        'implied:'),
    ...code('markdown', 'docs/superpowers/plans/2026-06-24-heaplens-protocol.md · Task 2, Step 2', r'''
- [ ] **Step 2: Run tests — verify they pass**
cargo test -p heaplens-protocol event
test event::tests::t1_size_of_alloc_event ... ok
test event::tests::t2_round_trip ... ok'''),
    ...text('Three properties make this format work for an '
        'autonomous executor. Each step has a binary outcome, so '
        'the executor cannot wander. The expected output is '
        'stated, so “it compiled” cannot pass for “it works”. And '
        'the commit message is given, so the history stays '
        'readable as a diary of the plan.'),
    ...text('The last property is checkable. Comparing the twelve '
        'commit messages in the plan with the repository’s log, '
        'eleven match to the character. Task 1 became “chore: '
        'init workspace + heaplens-protocol scaffold” in a55f7c1, '
        'Task 4 became “feat(protocol): FrameDecoder two-state '
        'machine (NeedLength/NeedBody)” in ca4e501, Task 10 became '
        '“test(protocol): T6 resync after absurd length prefix” in '
        'ea9b3b2. Only the closing task differs: the plan says '
        '“chore(protocol): clippy clean, Stage 1 complete” and the '
        'repository has “fix(protocol): clippy clean”. That is an '
        'unusually close match between plan and history.'),
    ...text('Four more commits are not in the plan at all. They '
        'are the review:'),
    ...bullet('c688dd7, 21:21',
        'the commit title asks for a “distinguishable kind byte”. '
        'The round-trip test used EventKind::Alloc, whose byte '
        'value is zero; an all-zero buffer already holds a zero '
        'kind byte, so a bug that dropped or zeroed the kind '
        'would pass (that reading is mine; the commit has no '
        'body). The test now uses Realloc (value 2), which '
        'cannot be mistaken for empty memory.'),
    ...bullet('c360b17 and f53785c, 21:23 and 21:24',
        'the encoders cast lengths with “as u32” and “as u16”, '
        'which truncate silently. Both are replaced with checked '
        'try_from conversions.'),
    ...bullet('fb8a4fc, 21:28',
        'NodeDto and GraphMessage get an Eq derive the plan had '
        'left out.'),
    blank,
    ...text('That is sixteen commits in twenty-seven minutes: '
        'twelve from the plan, four from review, interleaved '
        'with the tasks rather than saved for the end. The '
        'cadence suggests review ran after each task, not after '
        'the whole stage.'),

    ...sec('the casts the plan wrote and review removed'),
    ...text('The plan’s encoder code, as written, narrows a '
        'usize to a u32 with a bare cast:'),
    ...code('rust', 'docs/superpowers/plans/2026-06-24-heaplens-protocol.md · Task 3 (trimmed)', r'''
    buf.extend_from_slice(&(payload_len as u32).to_le_bytes());'''),
    ...text('A cast like that wraps on overflow and produces a '
        'frame header that lies about its length, which is the '
        'exact kind of corruption the decoder then has to survive. '
        'The repaired version fails loudly where the value is '
        'built:'),
    ...code('rust', 'crates/heaplens-protocol/src/frame.rs · encode_handshake (trimmed)', r'''
u32::try_from(payload_len).expect("handshake payload exceeds u32::MAX")'''),
    ...text('Later work went one step further for the two '
        'encoders whose count field is a u16: they now return an '
        'Option so a writer thread can drop an oversized batch '
        'instead of panicking (fa3fe78). It is the same lesson '
        'applied three times at three levels of urgency.'),

    ...sec('the test that outsmarted the plan'),
    ...text('The best finding on this page is arithmetic, derived here '
        'from the plan’s own test bytes and not stated in any '
        'commit. '
        'The plan’s decoder resyncs one byte at a time whenever '
        'the length prefix is zero or above the 8 MiB cap:'),
    ...code('markdown', 'docs/superpowers/plans/2026-06-24-heaplens-protocol.md · Task 4 decoder (trimmed)', r'''
                    if length == 0 || length > MAX_FRAME_LEN {
                        // Untrustworthy length prefix — resync one byte at a time
                        self.buf.drain(0..1);
                        continue; // loop: try again from next byte
                    }'''),
    ...text('T6 sandwiches junk between two valid frames:'),
    ...code('markdown', 'docs/superpowers/plans/2026-06-24-heaplens-protocol.md · Task 10, T6 junk', r'''
    let junk: Vec<u8> = {
        let mut j = Vec::new();
        j.extend_from_slice(&u32::MAX.to_le_bytes()); // absurd length
        j.extend_from_slice(&[0xAA, 0xBB, 0xCC]);    // padding noise
        j
    };'''),
    ...text('Follow the decoder along the junk. The bytes after '
        'the first valid frame are FF FF FF FF AA BB CC, and then '
        'the second frame starts with its own length, 107 for one '
        '104-byte event plus the type byte and count, which is '
        '6B 00 00 00. Reading four bytes at each one-byte slide:'),
    plain('  FF FF FF FF   4294967295   over the cap, drop one byte'),
    plain('  FF FF FF AA   2868903935   over the cap, drop one byte'),
    plain('  FF FF AA BB   3148546047   over the cap, drop one byte'),
    plain('  FF AA BB CC   3434851071   over the cap, drop one byte'),
    plain('  AA BB CC 6B   1808579498   over the cap, drop one byte'),
    plain('  BB CC 6B 00   7064763      under 8,388,608: accepted'),
    blank,
    ...text('The last window is not a frame boundary. It is the '
        'tail of the junk glued to the first two bytes of the real '
        'length. But 7,064,763 is under the cap, so the decoder '
        'believes a seven-megabyte frame has begun and waits for '
        'a body that never arrives. The real second frame is '
        'swallowed. The plan’s own T6 would have failed against '
        'the plan’s own decoder.'),
    ...text('That is what happened in the repository, in the '
        'same shape: the T6 commit (ea9b3b2, 21:41) is the one '
        'that rewrote the decoder. It added the plausibility '
        'check on type and length, whose comment says it rejects '
        'implausible length prefixes “without waiting for the '
        'full body to arrive”. With the check, the window above '
        'carries type byte 00, a handshake, whose length may not '
        'exceed 65,546, so it is rejected and sliding continues. '
        'The next window slips under that range and needs a second '
        'test, described in the footnote below, before the decoder '
        'reaches the true boundary. The adversarial test earned its '
        'place by finding what the simple rule could not.'),
    ...text('A footnote on today’s numbers. With the event now '
        '168 bytes the second frame’s length is 171 (AB 00 00 00), '
        'and the sliding windows differ. I replayed them by hand '
        'against the shipped decoder, with a throwaway script and '
        'not by running the Rust test. The windows up to BB CC AB '
        '00 are over the cap. The one after, CC AB 00 00, reads as '
        '43,980, under the cap, and its type byte is 00, a '
        'handshake. A handshake may be 11 to 65,546 bytes, so the '
        'length-and-type check accepts it. What rejects it is the '
        'second layer, the handshake cross-check: a handshake’s '
        'length must equal 11 plus the name length stored 13 bytes '
        'in, and in the test those bytes are zero, so the decoder '
        'expects 11. The same replay says the 104-byte window '
        'after BB CC 6B 00, CC 6B 00 00 (27,596), also needs that '
        'cross-check. The defence does not depend on which accident '
        'the bytes produce, but it does depend on both layers.'),

    ...sec('test-first, or test-with?'),
    ...text('The plan is not uniform about test-driven '
        'development, and the difference between it and its '
        'successors is instructive. Task 2’s first step is '
        'titled “Write T1 + T2 failing tests inline”, but the '
        'code block under it contains both the types and the '
        'tests, and the next step says “verify they pass”. The '
        'daemon’s M3 plan, written a week later, does it the '
        'strict way: its graph tests come first, and the step '
        'says to run them and expect a compile error, because '
        '“this confirms the tests are real”.'),
    ...text('For a data-definition crate the looser form is '
        'defensible: there is no behaviour to fail until the '
        'type exists. It also means the first stage’s tests '
        'were not demonstrated red before green. The ones that '
        'did go red, T6 especially, did so by accident, which '
        'is why they were so useful.'),

    ...sec('what the plan predicted about clippy, and what happened'),
    ...text('Task 12 lists lints the author expected, among them '
        'a missing Default for FrameDecoder, which the plan notes '
        'is already implemented. The lints that actually fired, '
        'recorded in c0f6c52, were different:'),
    ...bullet('should_implement_trait',
        'a method named next on a type that is not an Iterator. '
        'The fix is the right one: FrameDecoder implements '
        'Iterator, with the real work in a method called poll. '
        'The daemon relies on it: its ingest loop reads “for '
        'frame in decoder.by_ref()”.'),
    ...bullet('manual_range_contains',
        'a handwritten bounds check replaced by '
        '(11..=MAX_HANDSHAKE_LEN).contains(&length).'),
    ...bullet('manual_is_multiple_of',
        'a remainder test replaced by .is_multiple_of().'),
    blank,
    ...text('The stage ends on a checklist that includes a '
        'dependency audit, because the contract crate’s purity '
        'is a requirement and not a hope:'),
    ...code('markdown', 'docs/superpowers/plans/2026-06-24-heaplens-protocol.md · acceptance checklist (trimmed)', r'''
- [ ] `cargo build` passes
- [ ] `cargo test -p heaplens-protocol` — all 7 test groups pass (T1–T7)
- [ ] `cargo clippy -p heaplens-protocol -- -D warnings` — zero warnings
- [ ] `AllocEvent::SIZE == 104` enforced by const assert at compile time'''),

    ...sec('how the plan aged'),
    ...text('Unlike the Stage 3 plan, which gained a '
        'post-implementation notes section, this plan was not '
        'updated after execution. Its record of the work is the '
        'git log. Three of its facts are now false: the event is '
        '168 bytes and not 104; the decoder has the plausibility '
        'layer; and the encoders return Option. None of that '
        'makes it a bad plan. It means a plan is a launch '
        'document and not a maintained one, and the code and tests '
        'are what to trust.'),
    ...text('What it demonstrates well is the shape. A plan '
        'that is explicit enough to execute without questions, '
        'carries its own verification and commit messages, and '
        'points at a design document for every decision, can be '
        'run in half an hour and audited afterwards from the '
        'log.'),

    ...sec('limits, and what to take from it'),
    ...bullet('the plan contains the final code',
        'which is what lets it be executed quickly, and also '
        'means mistakes in the plan become mistakes in the '
        'repository until a review catches them. Four of the '
        'sixteen commits are such catches.'),
    ...bullet('review was not recorded',
        'the repository shows the fixes, not the reviewer. Who '
        'or what found the cast issue is not stated; only what '
        'changed and when.'),
    ...bullet('rule of thumb',
        'if a test is meant to pin one behaviour, make it '
        'adversarial enough that a simple implementation fails it. '
        'T6 did, and the decoder is better for it.'),
    blank,
    link('→ github.com/XNash/heaplens', 'https://github.com/XNash/heaplens'),
  ],
);
