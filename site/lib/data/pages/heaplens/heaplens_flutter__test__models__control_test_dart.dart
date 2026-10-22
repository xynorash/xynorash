import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/heaplens_flutter/test/models/control_test.dart',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'control_test.dart — the other direction: UI to daemon'),
    cm('//', r'twelve small tests for the attach/detach control-channel models'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', r'pins the JSON for control requests and the parsing of control responses'),
    kv('language', r'Dart, flutter_test unit tests'),
    kv('size', r'104 lines, 12 tests in 4 groups'),
    kv('history', r'one commit, 1cfb7f9 (2026-07-19), the UI refresh that introduced the process picker'),
    kv('wire source', r'crates/heaplens-protocol/src/control.rs'),
    kv('sibling', r'test/models/contract_test.dart, which this file copies in style'),
    ...sec(r'what is being pinned'),
    ...para('//', r'Stage 7 gave the UI a control channel alongside the graph stream: list the running processes, attach to one by pid, detach, and learn when the target exits. lib/models/control.dart is the Dart mirror of the Rust enum in control.rs, three request classes and four response classes. This file tests that mirror. The header comment says it follows contract_test.dart in style: small tests, one assertion cluster each, expected values spelled out as literals.'),
    ...sec(r'requests: the JSON the daemon will read'),
    ...code('dart', r'heaplens_flutter/test/models/control_test.dart · ControlRequest.toJson', r'''
  group('ControlRequest.toJson', () {
    test('ListProcessesRequest', () {
      expect(const ListProcessesRequest().toJson(), {'type': 'list_processes'});
    });

    test('AttachTargetRequest carries pid', () {
      expect(const AttachTargetRequest(4242).toJson(), {'type': 'attach_target', 'pid': 4242});
    });

    test('DetachTargetRequest', () {
      expect(const DetachTargetRequest().toJson(), {'type': 'detach_target'});
    });
  });'''),
    ...para('//', r'Each request is checked against an exact map. Equality on a Map in expect is structural, so the tests fail if a key is renamed, a key is added by mistake, or the type tag changes. AttachTargetRequest(4242) must produce exactly {type: attach_target, pid: 4242}. The other two carry only their tag. The wire format is the contract with the daemon, whose Rust enum is tagged by type with snake_case names (serde attributes in control.rs), so the tag strings and field names must match exactly.'),
    blank,
    ...para('//', r'Notice that every request is built with const. The requests are immutable value types with const constructors in control.dart.'),
    ...sec(r'responses: four shapes, one dispatcher'),
    ...code('dart', r'heaplens_flutter/test/models/control_test.dart · process_list', r'''
  group('ControlResponse.fromJson', () {
    test('process_list', () {
      final resp = ControlResponse.fromJson({
        'type': 'process_list',
        'processes': [
          {'pid': 1, 'name': 'a.exe', 'arch': 'x64'},
          {'pid': 2, 'name': 'b.exe', 'arch': 'x86'},
        ],
      });
      expect(resp, isA<ProcessListResponse>());
      final list = (resp as ProcessListResponse).processes;
      expect(list, hasLength(2));
      expect(list[0].pid, 1);
      expect(list[1].arch, 'x86');
    });'''),
    ...para('//', r'ControlResponse.fromJson dispatches on the type field, the same dispatch-on-tag pattern used for graph messages. The process list test checks the type, the length, and then two fields from two different entries (the pid of the first and the arch of the second), enough to prove the list is parsed element by element rather than shared or truncated. One of the two entries is x86, so the arch field is exercised with more than one value.'),
    ...code('dart', r'heaplens_flutter/test/models/control_test.dart · attach_result ok and failure', r'''
    test('attach_result ok', () {
      final resp = ControlResponse.fromJson({'type': 'attach_result', 'ok': true, 'message': 'attached to pid 4242'});
      expect(resp, isA<AttachResultResponse>());
      final r = resp as AttachResultResponse;
      expect(r.ok, isTrue);
      expect(r.message, 'attached to pid 4242');
    });

    test('attach_result failure carries the daemon message verbatim', () {
      final resp = ControlResponse.fromJson({
        'type': 'attach_result',
        'ok': false,
        'message': 'cannot open process 999999999 — access denied, or the process does not exist.',
      });
      final r = resp as AttachResultResponse;
      expect(r.ok, isFalse);
      expect(r.message, contains('access denied'));
    });'''),
    ...para('//', r'The attach tests are about the message. A successful attach returns ok true with text like attached to pid 4242. The failure case uses a real-looking daemon message, cannot open process 999999999, access denied or the process does not exist, and the test asserts the text is carried through verbatim (contains access denied). The model must not rewrite or classify it: the daemon is the one that knows why an attach failed, and the picker dialog shows that string to the user as is.'),
    ...code('dart', r'heaplens_flutter/test/models/control_test.dart · detach_result and target_exited', r'''
    test('detach_result', () {
      final resp = ControlResponse.fromJson({'type': 'detach_result', 'ok': true, 'message': 'detached'});
      expect(resp, isA<DetachResultResponse>());
      expect((resp as DetachResultResponse).ok, isTrue);
    });

    test('target_exited carries the pid', () {
      final resp = ControlResponse.fromJson({'type': 'target_exited', 'pid': 777});
      expect(resp, isA<TargetExitedResponse>());
      expect((resp as TargetExitedResponse).pid, 777);
    });'''),
    ...para('//', r'target_exited is different in kind. The model docs describe it as an unprompted push, sent when the daemon notices the attached process has exited, not a reply to any request. The test is minimal, it only checks the pid, but the type matters downstream: target_provider clears the attached target when it arrives.'),
    ...sec(r'failing loudly on an unknown type'),
    ...code('dart', r'heaplens_flutter/test/models/control_test.dart · unknown type', r'''
    test('unknown type throws FormatException rather than silently misparsing', () {
      expect(
        () => ControlResponse.fromJson({'type': 'something_new'}),
        throwsA(isA<FormatException>()),
      );
    });'''),
    ...para('//', r'Unlike NodeStateDto.fromWire, which defaults, an unknown response type throws a FormatException. The test title gives the reason: rather than silently misparsing. A message with an unrecognised tag is a protocol disagreement, so it must surface instead of being quietly turned into some other response. The expected exception type is stated precisely, throwsA(isA<FormatException>()), so a generic crash from a bad cast would not satisfy it.'),
    ...sec(r'the routing guard'),
    ...code('dart', r'heaplens_flutter/test/models/control_test.dart · wireTypes', r'''
  group('ControlResponse.wireTypes', () {
    test('lists exactly the four recognized tags', () {
      expect(
        ControlResponse.wireTypes,
        containsAll(['process_list', 'attach_result', 'detach_result', 'target_exited']),
      );
      expect(ControlResponse.wireTypes, hasLength(4));
    });

    test('does not overlap with GraphMessage tags', () {
      // Regression guard for the dispatch-before-parse design in
      // ws_provider.dart: if this ever collided with "snapshot"/"diff", the
      // "check wireTypes first" routing would silently misroute graph
      // messages to the control parser.
      expect(ControlResponse.wireTypes, isNot(contains('snapshot')));
      expect(ControlResponse.wireTypes, isNot(contains('diff')));
    });
  });'''),
    ...para('//', r'Both message families share one websocket connection. The WS layer therefore has to decide, before parsing, whether a frame is a control response or a graph message. ControlResponse.wireTypes is the list it checks first. This group has two tests with two different jobs.'),
    blank,
    ...pt('//', r'exactly four', r'containsAll plus hasLength(4). If someone adds a fifth response class to the switch in fromJson but forgets the list, the routing sends that message to the graph parser, which throws on the unknown type. The count catches the omission in one direction, and a new tag added only to the list is caught by the length check.'),
    ...pt('//', r'no overlap', r'the list must not contain snapshot or diff. The comment calls it a regression guard for the dispatch-before-parse design in ws_provider.dart: if a control tag ever collided with a graph tag, the check-wireTypes-first rule would silently misroute graph messages.'),
    ...para('//', r'One gap worth noting: the overlap test checks only snapshot and diff, not stats, which GraphMessage.fromJson also recognises. A control tag named stats would slip through this test. Nothing in the repo does that today.'),
    ...sec(r'how this relates to the rest'),
    ...para('//', r'This file only proves the models are right in isolation. The behaviour built on them, requesting the process list over a real stream, handling an attach result, clearing state on target_exited, is tested in test/providers/ws_provider_test.dart, and the dialog that shows the list is tested in test/widgets/process_picker_dialog_test.dart. Keeping the parsing tests separate means a failure there points at the JSON, not at provider logic.'),
  ],
);
