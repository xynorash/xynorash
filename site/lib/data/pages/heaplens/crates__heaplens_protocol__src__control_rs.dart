import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/crates/heaplens-protocol/src/control.rs',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'control.rs — telling the daemon which process to watch'),
    cm('//', r'three requests, four responses, and one push the daemon sends '
              r'unprompted'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', r'client-to-daemon control channel for the process picker and '
              r'attach/detach'),
    kv('language', r'Rust with serde derive'),
    kv('size', r'46 lines, added in one commit on 2026-07-19'),
    kv('carried on', r'the same WebSocket as the graph stream, distinguished by a type tag'),
    kv('mirrored by', r'heaplens_flutter/lib/models/control.dart'),
    ...sec(r'why this file exists'),
    ...para('//',
        r'For most of the project, HeapLens could only watch programs that '
        r'had been rebuilt with HeapLensAlloc as their global allocator. '
        r'Stage 7 added the ability to attach to a running process by '
        r'injecting a hook DLL into it (heaplens-hook, driven by '
        r'heaplens-injector). Attaching needs a conversation: the UI has '
        r'to ask for a list of processes, pick one, request the attach, '
        r'learn whether it worked, and later find out if the target has '
        r'gone away. This file is the vocabulary of that conversation.'),
    blank,
    ...para('//',
        r'The design document (docs/stage7-injection-design.md, section '
        r'3.1) puts the picker in Flutter and the process enumeration in '
        r'the daemon, and gives the reason: the daemon already has Win32 '
        r'access and already holds the WebSocket, so Flutter stays "a pure '
        r'UI/rendering layer, consistent with its role everywhere else in '
        r'the system". The document proposed "a small addition to that '
        r'message enum, not a new channel". What shipped is slightly '
        r'different, and arguably cleaner: separate ControlRequest and '
        r'ControlResponse enums with their own tags, travelling on the '
        r'same connection.'),
    ...sec(r'the types'),
    ...code('rust', 'crates/heaplens-protocol/src/control.rs · ProcessInfo and ControlRequest', r'''
use serde::{Deserialize, Serialize};

/// A process the picker can offer as an attach target.
/// Field names are the wire contract — Flutter mirrors them verbatim.
#[derive(Serialize, Deserialize, Clone, Debug, PartialEq, Eq)]
pub struct ProcessInfo {
    pub pid: u32,
    pub name: String,
    /// "x64", "x86", or "unknown" — `OpenProcess` can legitimately fail for
    /// protected/elevated processes the daemon has no rights to query;
    /// "unknown" is reported rather than dropping the process from the list.
    pub arch: String,
}

/// Client → daemon control requests, sent as WS text frames on the same
/// connection graph snapshots/diffs are sent on.
///
/// Serializes with an inline `"type"` tag:
///   `{ "type": "list_processes" }`
///   `{ "type": "attach_target", "pid": 1234 }`
///   `{ "type": "detach_target" }`
#[derive(Serialize, Deserialize, Clone, Debug, PartialEq, Eq)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum ControlRequest {
    ListProcesses,
    AttachTarget { pid: u32 },
    DetachTarget,
}'''),
    ...para('//',
        r'Requests go from the UI to the daemon and are tiny. They '
        r'serialise with an inline type tag, so the three messages are '
        r'exactly { "type": "list_processes" }, { "type": "attach_target", '
        r'"pid": 1234 } and { "type": "detach_target" }. The serde '
        r'attribute is tag = "type" with rename_all = "snake_case", and '
        r'unit variants such as ListProcesses serialise with no other '
        r'fields. The Dart side writes the same strings by hand in '
        r'toJson(), and the Flutter tests pin them (control_test.dart '
        r'asserts the map for each request, ws_provider_test.dart asserts '
        r'the exact JSON string ’{"type":"attach_target","pid":4242}’).'),
    blank,
    ...para('//',
        r'ProcessInfo is what the picker shows. The arch field is a '
        r'String, not an enum, and the doc comment explains the choice. '
        r'OpenProcess can legitimately fail for protected or elevated '
        r'processes the daemon has no rights to query, and the contract '
        r'says "unknown" is reported rather than dropping the process from '
        r'the list. In procs.rs the enumeration (CreateToolhelp32Snapshot) '
        r'never fails the whole call because one probe failed. The Dart '
        r'mirror then treats "unknown" like "x86": only "x64" is '
        r'known-safe for a 64-bit build. A string keeps the daemon free to '
        r'report a value the UI has never heard of.'),
    ...code('rust', 'crates/heaplens-protocol/src/control.rs · ControlResponse', r'''
/// Daemon → client control responses, sent as WS text frames alongside
/// `GraphMessage` snapshots/diffs (distinguished by their own `"type"` tag,
/// so a lenient client can `match` on either shape from the same stream).
///
/// `ProcessList`/`AttachResult`/`DetachResult` are replies to a specific
/// `ControlRequest`. `TargetExited` is different in kind — an unprompted
/// push, broadcast to every connected client the moment the daemon detects
/// the attached target process has exited (§4.4), the same way graph diffs
/// are pushed rather than polled.
#[derive(Serialize, Deserialize, Clone, Debug, PartialEq, Eq)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum ControlResponse {
    ProcessList { processes: Vec<ProcessInfo> },
    AttachResult { ok: bool, message: String },
    DetachResult { ok: bool, message: String },
    TargetExited { pid: u32 },
}'''),
    ...para('//',
        r'There are four responses and they are not all the same kind of '
        r'thing. ProcessList, AttachResult and DetachResult are replies: '
        r'each answers one request. TargetExited is an unprompted push. '
        r'The doc comment says it is "broadcast to every connected client '
        r'the moment the daemon detects the attached target process has '
        r'exited (section 4.4), the same way graph diffs are pushed rather '
        r'than polled". In the daemon (main.rs) that is a send on a '
        r'broadcast channel, and every WebSocket task forwards it, so two '
        r'open UIs both learn that the target died.'),
    blank,
    ...para('//',
        r'Both result variants carry ok: bool and a message: String. The '
        r'message is meant to be shown. The design document’s validation '
        r'section lists the sentences: architecture mismatch gives "target '
        r'is a 32-bit process; this build of HeapLens is 64-bit and cannot '
        r'attach", an access failure gives "access denied — try running '
        r'HeapLens as Administrator". The protocol does not model errors '
        r'as an enum because the UI’s only job with them is to display '
        r'them.'),
    blank,
    ...para('//',
        r'Serialising every variant in a scratch crate shows the real '
        r'strings. The three requests are {"type":"list_processes"}, '
        r'{"type":"attach_target","pid":1234} and '
        r'{"type":"detach_target"}. The replies come out as '
        r'{"type":"attach_result","ok":false,"message":"access denied"}, '
        r'{"type":"target_exited","pid":9} and '
        r'{"type":"process_list","processes":[{"pid":4,"name":"System","arch":"unknown"}]}. '
        r'A request with a missing field, such as {"type":"attach_target"} '
        r'with no pid, fails with serde’s `missing field pid`. The same '
        r'scratch run probed the strictness of the request side: an '
        r'unknown tag fails with "unknown variant `nope`, expected one of '
        r'`list_processes`, `attach_target`, `detach_target`"; a pid sent '
        r'as the string "5", as -5 or as 4294967296 is rejected as not a '
        r'u32; but extra fields are ignored, so '
        r'{"type":"list_processes","pid":5} parses as a plain '
        r'ListProcesses. As in diff.rs there is no deny_unknown_fields.'),
    ...sec(r'one connection, two vocabularies'),
    ...para('//',
        r'GraphMessage (diff.rs) and ControlResponse flow in the same '
        r'direction over the same socket, so the receiving side has to '
        r'tell them apart. They are distinguished by their tag values: '
        r'snapshot, diff and stats on one side, process_list, '
        r'attach_result, detach_result and target_exited on the other. The '
        r'Dart ControlResponse even exposes the list (static const '
        r'wireTypes) so the WebSocket layer can decide which parser to '
        r'hand a frame to before attempting either.'),
    blank,
    ...para('//',
        r'The tag rules differ on purpose or by accident, and it is worth '
        r'knowing which: GraphMessage uses rename_all = "lowercase", this '
        r'file uses "snake_case". For today’s single-word GraphMessage '
        r'variants they agree. For the multi-word variants here they would '
        r'not, and the snake_case choice is what yields attach_result '
        r'rather than attachresult. If someone copies a derive line '
        r'between the two files, the Dart parsers will stop recognising '
        r'messages without any Rust error.'),
    blank,
    ...para('//',
        r'On the receiving end in the daemon, a text frame that does not '
        r'parse as a ControlRequest is logged with a warning and ignored; '
        r'there is no error reply. That makes the exactness of these tags '
        r'matter more than it looks. The commit that ported this protocol '
        r'(724695a, 2026-07-19) describes the state before it: server.rs '
        r'"discarded the WS receive half entirely, so '
        r'ListProcesses/AttachTarget/DetachTarget requests went into the '
        r'void and the picker spun forever". The failure mode of a '
        r'mismatched tag today is the same silence.'),
    ...code('rust', 'crates/heaplens-daemon/src/server.rs · how the daemon answers (trimmed)', r'''
async fn handle_control_request(req: ControlRequest, target_tx: &mpsc::UnboundedSender<TargetCmd>) -> ControlResponse {
    match req {
        ControlRequest::ListProcesses => {
            let (reply, rx) = oneshot::channel();
            if target_tx.send(TargetCmd::ListProcesses { reply }).is_err() {
                return ControlResponse::ProcessList { processes: Vec::new() };
            }
            ControlResponse::ProcessList { processes: rx.await.unwrap_or_default() }
        }
        ControlRequest::AttachTarget { pid } => {
            let (reply, rx) = oneshot::channel();
            if target_tx.send(TargetCmd::Attach { pid, reply }).is_err() {'''),
    ...para('//',
        r'The handler is a thin translation layer. It forwards each '
        r'request to the graph task over a channel together with a '
        r'one-shot reply sender, then maps the outcome to a '
        r'ControlResponse. The graph task is the single owner of both '
        r'graph and attach-session state (the comment points at section '
        r'3.4), so there is no shared lock to get wrong, and the await '
        r'only blocks the one client’s own task even though attach can '
        r'take seconds while the injector runs.'),
    ...sec(r'how it got here'),
    ...para('//',
        r'The whole file arrived in commit 724695a, "port Stage 7 control '
        r'protocol from feat/stage7-injection", on 2026-07-19. Two '
        r'branches had diverged from the same base: one had the new UI '
        r'with an Attach button and a process-picker dialog but no daemon '
        r'support, the other had the daemon-side control protocol but not '
        r'the UI. The port was selective and Rust-only. The commit message '
        r'records the check that made it safe to do without touching '
        r'Flutter: the existing Dart control.dart, target_provider.dart '
        r'and process_picker_dialog.dart "already matched the wire '
        r'contract exactly (verified byte-for-byte against '
        r'ControlRequest/ControlResponse’s ’type’ tags before porting), so '
        r'they just started working".'),
    blank,
    ...para('//',
        r'That is the contract idea paying off. Two pieces of code written '
        r'on different branches met in the middle because the only thing '
        r'they shared was a handful of strings, and those strings were '
        r'written down once.'),
    ...sec(r'what pins it, and what does not'),
    ...para('//',
        r'The Rust crate has no test for this file. There is no '
        r'control_json.rs next to diff_json.rs. The wire shapes are pinned '
        r'from the Dart side (control_test.dart, ws_provider_test.dart, '
        r'process_picker_dialog_test.dart), which asserts the exact JSON '
        r'the UI sends and parses the exact tags it receives. That is a '
        r'real guard against drift on the Dart half, but a rename on the '
        r'Rust half would compile and pass every Rust test. A symmetrical '
        r'Rust test in the style of diff_json.rs, serialising each variant '
        r'and asserting the tag and field names, would close it.'),
    ...sec(r'limits'),
    ...pt('//',
        r'pid widths',
        r'here pid is u32, which is the Windows process id width. The '
        r'HANDSHAKE frame (frame.rs) and Stats.target_pid (diff.rs) carry '
        r'it as u64. The daemon converts with a cast when it raises '
        r'TargetExited (main.rs: pid as u32). Harmless for real Windows '
        r'pids, but there are two widths for one concept.'),
    ...pt('//',
        r'no error taxonomy',
        r'ok plus a free-text message is enough for display, not for '
        r'programmatic recovery.'),
    ...pt('//',
        r'no request ids',
        r'replies are matched to requests by type, not by an id. Two '
        r'overlapping requests from one client would be ambiguous. The UI '
        r'flow (open the picker, list, attach) is sequential, so this does '
        r'not bite.'),
    ...pt('//',
        r'single target',
        r'the contract has no notion of several attached targets. The '
        r'design document states that scope (single target, graph cleared '
        r'on switch) explicitly.'),
    ...pt('//',
        r'unknown message handling',
        r'unrecognised control text is dropped silently on the daemon '
        r'side, as above.'),
    blank,
    link('→ github.com/xynorash/heaplens · crates/heaplens-protocol/src/control.rs',
        'https://github.com/xynorash/heaplens/blob/master/crates/heaplens-protocol/src/control.rs'),
  ],
);
