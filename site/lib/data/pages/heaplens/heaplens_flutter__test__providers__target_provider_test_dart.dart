import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/heaplens_flutter/test/providers/target_provider_test.dart',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'target_provider_test.dart — who are we attached to, and when does that stop?'),
    cm('//', r'eight tests for the small notifier that remembers the attached process'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', r'pins when AttachedTargetNotifier sets and clears the attached target'),
    kv('language', r'Dart, flutter_test with a ProviderContainer'),
    kv('size', r'106 lines, 8 tests in 1 group'),
    kv('history', r'one commit, 1cfb7f9 (2026-07-19), the UI refresh'),
    kv('subject', r'lib/providers/target_provider.dart'),
    ...sec(r'what the notifier knows and does not know'),
    ...para('//', r'The control bar needs to show which process HeapLens is attached to, and to offer detach when there is one. That is the whole job of AttachedTargetNotifier, whose state is an AttachedTarget with a pid and a name, or null. The class doc explains a detail that shapes every test: the name cannot be derived from the daemon’s reply. The AttachResult response carries only ok and a message, so the name comes from the ProcessInfo the picker showed when the user chose the row. That is why setAttached exists as an explicit call.'),
    ...code('dart', r'heaplens_flutter/lib/providers/target_provider.dart · the class and its contract', r'''
/// Tracks the attached target across attach/detach/target-exit, Stage 7
/// §3/§4.4.
///
/// Attach is set explicitly by the picker (`setAttached`) once it observes
/// a successful `AttachResult` — the notifier itself only *listens* for the
/// ways a session ends (`DetachResult{ok:true}`, the unprompted
/// `TargetExited` push) and clears itself, following the same
/// automatic-wiring-in-`build()` pattern `GraphNotifier` uses for
/// `graphMessageProvider`.
class AttachedTargetNotifier extends Notifier<AttachedTarget?> {'''),
    ...para('//', r'So the notifier mixes two sources of truth. The picker sets the state, and the daemon’s replies and pushes can end it. The tests are mostly about the second half, because that is where the wrong clear would happen.'),
    ...sec(r'the harness'),
    ...code('dart', r'heaplens_flutter/test/providers/target_provider_test.dart · setUp', r'''
  group('AttachedTargetNotifier', () {
    late StreamController<ControlResponse> controller;
    late ProviderContainer container;

    setUp(() {
      controller = StreamController<ControlResponse>();
      container = ProviderContainer(
        overrides: [
          controlResponseProvider.overrideWith((ref) => controller.stream),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(controller.close);
      // Activate the notifier (and its ref.listen to controlResponseProvider).
      container.read(attachedTargetProvider);
    });'''),
    ...para('//', r'Same shape as the other provider tests: a StreamController<ControlResponse> overrides controlResponseProvider and the notifier is activated by a read. The comment spells out why the read is needed, the notifier subscribes to the stream in build(). Afterwards, tests push responses into the controller and await Future.delayed(Duration.zero) so the stream event is delivered before asserting.'),
    ...sec(r'set, and the three ways to clear'),
    ...code('dart', r'heaplens_flutter/test/providers/target_provider_test.dart · starts null; setAttached', r'''
    test('starts as null (nothing attached)', () {
      expect(container.read(attachedTargetProvider), isNull);
    });

    test('setAttached records the target explicitly (not derived from a response alone)', () {
      container.read(attachedTargetProvider.notifier).setAttached(
            const AttachedTarget(pid: 4242, name: 'target.exe'),
          );
      final state = container.read(attachedTargetProvider);
      expect(state?.pid, 4242);
      expect(state?.name, 'target.exe');
    });'''),
    ...para('//', r'The state starts null. After setAttached the pid and name are what the picker passed in. The title of the second test makes the same point as the class doc: the target is recorded explicitly, not derived from a response alone.'),
    ...code('dart', r'heaplens_flutter/test/providers/target_provider_test.dart · a successful DetachResult clears', r'''
    test('a successful DetachResult clears the attached target', () async {
      container.read(attachedTargetProvider.notifier).setAttached(
            const AttachedTarget(pid: 4242, name: 'target.exe'),
          );
      expect(container.read(attachedTargetProvider), isNotNull);

      controller.add(const DetachResultResponse(ok: true, message: 'detached'));
      await Future<void>.delayed(Duration.zero);

      expect(container.read(attachedTargetProvider), isNull);
    });'''),
    ...para('//', r'When the daemon confirms a detach with ok true, the state becomes null. This is the confirmed path.'),
    ...code('dart', r'heaplens_flutter/test/providers/target_provider_test.dart · a failed DetachResult does not', r'''
    test('a failed DetachResult does NOT clear the attached target', () async {
      container.read(attachedTargetProvider.notifier).setAttached(
            const AttachedTarget(pid: 4242, name: 'target.exe'),
          );

      controller.add(const DetachResultResponse(ok: false, message: 'writer thread did not stop'));
      await Future<void>.delayed(Duration.zero);

      expect(container.read(attachedTargetProvider)?.pid, 4242);
    });'''),
    ...para('//', r'When ok is false, the state must stay. The message used in the test is writer thread did not stop. If the notifier cleared its state anyway, the UI would claim no target is attached after the daemon reported that the detach failed. This is the test that justifies matching on DetachResultResponse(ok: true) in the source rather than on the type alone.'),
    ...code('dart', r'heaplens_flutter/test/providers/target_provider_test.dart · TargetExited for the tracked pid', r'''
    test('TargetExited for the currently-tracked pid clears it', () async {
      container.read(attachedTargetProvider.notifier).setAttached(
            const AttachedTarget(pid: 4242, name: 'target.exe'),
          );

      controller.add(const TargetExitedResponse(4242));
      await Future<void>.delayed(Duration.zero);

      expect(container.read(attachedTargetProvider), isNull);
    });'''),
    ...para('//', r'target_exited is the unprompted push for a process that has ended. If its pid is the tracked one, the state clears. No request was sent and none is needed.'),
    ...code('dart', r'heaplens_flutter/test/providers/target_provider_test.dart · TargetExited for a different pid', r'''
    test('TargetExited for a DIFFERENT pid than currently tracked is ignored', () async {
      container.read(attachedTargetProvider.notifier).setAttached(
            const AttachedTarget(pid: 4242, name: 'target.exe'),
          );

      // A stale push for some other/prior pid must not clobber current state.
      controller.add(const TargetExitedResponse(9999));
      await Future<void>.delayed(Duration.zero);

      expect(container.read(attachedTargetProvider)?.pid, 4242);
    });'''),
    ...para('//', r'The comment in the test and the one in the source say the same thing: a stale push for a pid we are not tracking, arriving just after switching away, must not clobber newer state. Picture attaching to process A, then to B, with A’s exit notice arriving late. The check is state?.pid == pid, and the test uses 9999 against 4242.'),
    ...code('dart', r'heaplens_flutter/test/providers/target_provider_test.dart · clear() is optimistic', r'''
    test('clear() optimistically clears without waiting for a DetachResult', () {
      container.read(attachedTargetProvider.notifier).setAttached(
            const AttachedTarget(pid: 4242, name: 'target.exe'),
          );
      container.read(attachedTargetProvider.notifier).clear();
      expect(container.read(attachedTargetProvider), isNull);
    });'''),
    ...para('//', r'The third way out is the UI itself. clear() is called right after the UI sends a detach request, without waiting for the answer. The source comment says this mirrors other UI-only toggles that favour immediate feedback, and that the confirmed DetachResult would then be a no-op. Together with the failed-detach test above, this exposes a trade-off worth naming: after clear(), a failed detach no longer has any state to preserve, so the optimistic and the pessimistic paths disagree. The tests pin each path separately and none covers the combination.'),
    ...sec(r'what must be ignored'),
    ...code('dart', r'heaplens_flutter/test/providers/target_provider_test.dart · other responses do not affect state', r'''
    test('ProcessListResponse/AttachResultResponse do not affect attached state', () async {
      container.read(attachedTargetProvider.notifier).setAttached(
            const AttachedTarget(pid: 4242, name: 'target.exe'),
          );

      controller.add(const ProcessListResponse([]));
      controller.add(const AttachResultResponse(ok: true, message: 'attached to pid 1'));
      await Future<void>.delayed(Duration.zero);

      expect(container.read(attachedTargetProvider)?.pid, 4242);
    });'''),
    ...para('//', r'A ProcessListResponse and an AttachResultResponse arrive while a target is tracked, and the pid must remain 4242. The two events are pushed back to back before a single await, so it also checks the listener copes with two events in the same turn. The source handles them with empty switch cases rather than a default, which makes the switch exhaustive over the sealed ControlResponse class: if a fifth response type is ever added, the compiler forces someone to decide what it does here.'),
    ...sec(r'a gap worth naming'),
    ...pt('//', r'a successful attach', r'nothing in this file simulates the user attaching to a second process while another is tracked. setAttached simply overwrites the state, and the pid check on TargetExited is the only protection against the old process’s exit.'),
    ...pt('//', r'who calls setAttached', r'the picker dialog does, after an ok attach result; that integration is exercised in process_picker_dialog_test.dart.'),
  ],
);
