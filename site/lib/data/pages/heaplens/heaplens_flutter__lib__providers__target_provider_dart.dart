import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/heaplens_flutter/lib/providers/target_provider.dart',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'target_provider.dart — who am I attached to?'),
    cm('//', r'state that the daemon never tells the client, and the two ways it ends'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', r'tracks the attached process across attach, detach and target exit'),
    kv('language', r'Dart / Riverpod'),
    kv('size', r'73 lines, 8 tests in test/providers/target_provider_test.dart'),
    kv('history', r'one commit: 1cfb7f9 (2026-07-19)'),
    kv('written by', r'process_picker_dialog.dart (setAttached), control_bar.dart (clear)'),
    ...sec(r'why this file exists'),
    ...para('//',
        r'The UI refresh added a process picker, a way to choose a '
        r'running program and attach to it, and with it a question '
        r'the earlier app never had: what is the attached target '
        r'right now? The ribbon needs to show its name and pid, the '
        r'Detach button needs to know whether to appear, and the '
        r'empty states need to know whether to tell the user to '
        r'attach. Several widgets need the answer, none of them owns '
        r'it, so it is a provider.'),
    ...sec(r'the value, and why the name is carried by hand'),
    ...code('dart', 'heaplens_flutter/lib/providers/target_provider.dart · lines 7-20', r'''
/// The currently-attached target, as far as this Flutter client knows.
///
/// `name` is carried along from the [ProcessInfo] the picker showed at
/// selection time, purely for display — the daemon's `AttachResult` reply
/// doesn't echo it back (only `ok`/`message`, see
/// `heaplens_protocol::control::ControlResponse`), so it has nowhere else
/// to come from.
@immutable
class AttachedTarget {
  final int pid;
  final String name;

  const AttachedTarget({required this.pid, required this.name});
}'''),
    ...para('//',
        r'AttachedTarget is an immutable pid and name. The comment '
        r'explains an awkward fact: the name is carried from the '
        r'process list entry the picker showed at selection time, '
        r'purely for display, because the daemon’s reply to an '
        r'attach request carries only ok and a message. The '
        r'protocol’s ControlResponse has nowhere to put a name. This '
        r'is the cost of a thin protocol and I preferred paying it '
        r'in the client over widening the protocol for a label.'),
    ...sec(r'who sets state, and who clears it'),
    ...code('dart', 'heaplens_flutter/lib/providers/target_provider.dart · lines 31-52', r'''
class AttachedTargetNotifier extends Notifier<AttachedTarget?> {
  @override
  AttachedTarget? build() {
    ref.listen<AsyncValue<ControlResponse>>(controlResponseProvider, (previous, next) {
      next.whenData((resp) {
        switch (resp) {
          case DetachResultResponse(ok: true):
            state = null;
          case TargetExitedResponse(:final pid):
            // Only clear if it's *our* tracked target — a stale push for a
            // pid we're not currently tracking (e.g. arriving just after we
            // already switched away from it) must not clobber newer state.
            if (state?.pid == pid) state = null;
          case ProcessListResponse():
          case AttachResultResponse():
          case DetachResultResponse():
            break;
        }
      });
    });
    return null;
  }'''),
    ...para('//',
        r'The state has one explicit setter and three ways to end. '
        r'The notifier only listens for the endings: a DetachResult '
        r'with ok true, and the unprompted TargetExited push. '
        r'Setting is left to the picker, which calls setAttached '
        r'after it sees AttachResult with ok true. The comment calls '
        r'this the same automatic-wiring-in-build pattern '
        r'GraphNotifier uses for the graph message stream. It is '
        r'consistent, and it keeps the notifier from guessing, from '
        r'a bare response, which target a request was for.'),
    ...code('dart', 'heaplens_flutter/lib/widgets/process_picker_dialog.dart · lines 75-79', r'''
    if (resp.ok) {
      ref.read(attachedTargetProvider.notifier).setAttached(
            AttachedTarget(pid: process.pid, name: process.name),
          );
      if (mounted) Navigator.of(context).pop();'''),
    ...para('//',
        r'The picker’s half is the few lines above: only after a '
        r'reply with ok true does it record the pid and name it '
        r'already holds, and then it closes the dialog. Back in the '
        r'notifier, every case of the switch is spelled out and the '
        r'three that do nothing say so with an empty arm that '
        r'breaks, the Dart 3 way of keeping an exhaustive switch '
        r'honest. Add a response type to the protocol and this file '
        r'stops compiling until someone decides what it means for '
        r'attach state.'),
    ...sec(r'the stale-push rule'),
    ...para('//',
        r'The TargetExited arm has the one comment in the file that '
        r'describes a race. A push can arrive for a pid we are not '
        r'tracking, for example just after the user has already '
        r'switched away from it, and the code clears state only if '
        r'state?.pid equals the pid in the push. A late message '
        r'about a previous target must not wipe out the newer one. '
        r'The test for this is the one named TargetExited for a '
        r'DIFFERENT pid than currently tracked is ignored: it '
        r'attaches 4242, pushes an exit for 9999, and asserts 4242 '
        r'survives.'),
    ...sec(r'optimistic clear'),
    ...code('dart', 'heaplens_flutter/lib/providers/target_provider.dart · lines 61-73', r'''
  /// Optimistically clears local state right after sending `DetachTarget`,
  /// without waiting for the daemon's reply — mirrors how `paused_provider`
  /// and other UI-only toggles in this app favor immediate feedback; the
  /// `DetachResult{ok:true}` listener above is what actually confirms it
  /// and would be a no-op if this already cleared it.
  void clear() {
    state = null;
  }
}

final attachedTargetProvider = NotifierProvider<AttachedTargetNotifier, AttachedTarget?>(
  AttachedTargetNotifier.new,
);'''),
    ...para('//',
        r'clear is called by the Detach button right after it sends '
        r'DetachTarget, without waiting for the reply. The comment '
        r'compares this to the other UI toggles in the app that '
        r'favor immediate feedback, and says the DetachResult '
        r'listener is the real confirmation and becomes a no-op if '
        r'the state is already null. The cost is that if the daemon '
        r'refuses to detach, the UI has already forgotten the '
        r'target. The failed-detach test pins only the listener '
        r'side: a DetachResult with ok false does not clear on its '
        r'own. The optimistic path trades a possible lie in the '
        r'failure case for a button that responds at once.'),
    ...sec(r'edge cases'),
    ...pt('//', r'reconnect',
        r'nothing here listens to the connection status. If the '
        r'socket drops and returns, the attached target stays in '
        r'state, and the daemon’s view is not re-asked.'),
    ...pt('//', r'attach while attached',
        r'setAttached overwrites. Whether the daemon permits a '
        r'second attach is its business; the client simply shows the '
        r'latest success.'),
    ...pt('//', r'process list',
        r'ProcessListResponse and AttachResultResponse arms '
        r'deliberately do nothing, covered by the test named for '
        r'exactly those two.'),
    ...pt('//', r'lifetime',
        r'a plain NotifierProvider with no autoDispose, so the state '
        r'lives as long as the app.'),
    ...sec(r'how it is tested'),
    ...para('//',
        r'Eight tests, all driven by a StreamController of '
        r'ControlResponse overriding controlResponseProvider. They '
        r'check the null start, that setAttached records pid 4242 '
        r'and the name target.exe, that a successful detach clears, '
        r'that a failed detach does not, that an exit for the '
        r'tracked pid clears, that an exit for a different pid is '
        r'ignored, that clear works without a reply, and that a '
        r'process list or an attach result does not touch the state. '
        r'The widget tests for the control bar and picker cover the '
        r'writers.'),
    ...sec(r'history'),
    ...pt('//', r'1cfb7f9 (2026-07-19)',
        r'the UI refresh. The message says the provider exists for '
        r'the picker and control bar to share attach state. It is '
        r'the file’s only commit.'),
  ],
);
