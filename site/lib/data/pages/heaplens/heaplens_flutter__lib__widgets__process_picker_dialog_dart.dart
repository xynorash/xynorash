import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/heaplens_flutter/lib/widgets/process_picker_dialog.dart',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'process_picker_dialog.dart — choosing what to watch'),
    cm('//', r'list, filter, attach, and surface the daemon’s own words'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', r'the "Attach to process" dialog (Stage 7, Step 4)'),
    kv('language', r'Dart / Flutter (ConsumerStatefulWidget in a Dialog)'),
    kv('size', r'219 lines; one commit (1cfb7f9, 2026-07-19)'),
    kv('tested by', r'test/widgets/process_picker_dialog_test.dart (4 tests)'),
    kv('talks to', r'wsConnectionProvider, controlResponseProvider, attachedTargetProvider'),
    ...sec(r'why this file exists'),
    ...para('//',
        r'Until Stage 7 a program had to opt in to being watched: it '
        r'linked the HeapLens allocator and connected to the daemon '
        r'itself. Process attachment reverses that. The user picks a '
        r'running process and HeapLens reaches into it. This dialog is '
        r'the picking. The design document is specific about its job: '
        r'"request ListProcesses, render the list, send AttachTarget on '
        r'selection, surface attach-failure messages from §3.3 verbatim, '
        r'show ‘target process exited’ per §4.4".'),
    blank,
    ...para('//',
        r'Its class comment turns that into a contract: request the '
        r'list on open, let the user pick, send AttachTarget, and then '
        r'surface the result. Success "closes the dialog and records the '
        r'attached target"; failure "stays open and shows the daemon’s '
        r'own message text verbatim, not a generic ‘failed.’" The word '
        r'verbatim is the point of the file.'),
    ...sec(r'why verbatim matters'),
    ...para('//',
        r'The refusal reasons come from the injector, a separate '
        r'process. Section 3.3 of the design lists the checks it makes '
        r'before touching the target: architecture match, access '
        r'rights, whether the process is still running. Each failure '
        r'has a specific message, for example "target is a 32-bit '
        r'process; this build of HeapLens is 64-bit and cannot attach". '
        r'In 864167e the author verified that the chain really '
        r'delivers them: the injector writes the reason to stderr, the '
        r'daemon captures it into AttachResult.message, and the UI '
        r'renders it. The commit says this was "confirmed live against '
        r'Windows Defender (a real protected process), whose exact '
        r'refusal reason appeared in both the dialog and the '
        r'verbose-log panel".'),
    blank,
    ...para('//',
        r'The Dart side keeps its end of that chain honest. The test '
        r'uses a realistic message, "cannot open process 999999999 — '
        r'access denied, or the process does not exist.", feeds it as '
        r'a failed AttachResult, and asserts that the error widget is '
        r'on screen, the text contains "access denied", the dialog '
        r'is still open and nothing was recorded as attached.'),
    ...sec(r'disabled, not hidden'),
    ...code('dart', 'heaplens_flutter/lib/widgets/process_picker_dialog.dart · the list tile', r'''
                            final p = filtered[i];
                            final attachable = p.arch == 'x64';
                            return ListTile(
                              key: Key('processPickerItem_${p.pid}'),
                              enabled: attachable && !_attaching,
                              title: Text(p.name),
                              subtitle: Text(
                                attachable
                                    ? 'pid ${p.pid} · ${p.arch}'
                                    : 'pid ${p.pid} · ${p.arch} — this build of HeapLens is 64-bit and cannot attach',
                              ),
                              onTap: attachable ? () => _attach(p) : null,
                            );'''),
    ...para('//',
        r'A 32-bit process, or one whose architecture the daemon could '
        r'not determine, is shown, greyed, with the reason in its '
        r'subtitle. The class comment gives the intent: it is '
        r'"surfaced *before* the user wastes a click on a target that '
        r'would only fail at attach time". The rule on ProcessInfo is '
        r'that only "x64" is attachable, and it is applied twice, in the '
        r'tile and again at the top of _attach, which returns early for '
        r'any other arch. In my reading the second check is defence in '
        r'depth: a future change to the tile could not turn into an '
        r'attach on a process that is not known to be 64-bit.'),
    ...sec(r'listening before sending'),
    ...code('dart', 'heaplens_flutter/lib/widgets/process_picker_dialog.dart · _attach', r'''
  Future<void> _attach(ProcessInfo process) async {
    if (process.arch != 'x64' || _attaching) return;
    setState(() {
      _attaching = true;
      _error = null;
    });

    // Start listening for the reply *before* sending, so a very fast daemon
    // reply can't arrive and be missed between the send and the listen.
    final replyFuture = _listenOnce<AttachResultResponse>();
    ref.read(wsConnectionProvider).sendRequest(AttachTargetRequest(process.pid));
    final resp = await replyFuture;
    if (!mounted) return;

    if (resp == null) {
      setState(() {
        _attaching = false;
        _error = 'No response from daemon (timed out).';
      });
      return;
    }
    if (resp.ok) {
      ref.read(attachedTargetProvider.notifier).setAttached(
            AttachedTarget(pid: process.pid, name: process.name),
          );
      if (mounted) Navigator.of(context).pop();
      return;
    }
    setState(() {
      _attaching = false;
      _error = resp.message;
    });
  }'''),
    ...para('//',
        r'Several small decisions are in that method.'),
    ...pt('//', r'one attach at a time',
        r'the _attaching flag guards re-entry and also disables every '
        r'tile (enabled: attachable && !_attaching), and a '
        r'LinearProgressIndicator shows while it is set. Because '
        r'control messages carry no request ids, this single-flight '
        r'rule is what makes matching a reply to its request by type '
        r'safe; see models/control.dart.'),
    ...pt('//', r'subscribe, then send',
        r'the order of the two calls is documented and tested. '
        r'Subscribing after sending would leave a window in which a fast '
        r'reply is missed.'),
    ...pt('//', r'the name is carried from the picker',
        r'the daemon’s AttachResult does not echo the process name, only '
        r'ok and a message. The picker already knows the name, so it is '
        r'passed to setAttached. The doc comment in target_provider.dart '
        r'explains this: the name "has nowhere else to come from".'),
    ...pt('//', r'mounted checks',
        r'the await can outlive the dialog, so the code checks mounted '
        r'before touching state or the Navigator.'),
    ...sec(r'a wait with a deadline, and the timer that leaked'),
    ...code('dart', 'heaplens_flutter/lib/widgets/process_picker_dialog.dart · _listenOnce', r'''
  Future<T?> _listenOnce<T extends ControlResponse>() async {
    final completer = Completer<T?>();
    late final ProviderSubscription<AsyncValue<ControlResponse>> sub;
    sub = ref.listenManual<AsyncValue<ControlResponse>>(controlResponseProvider, (previous, next) {
      next.whenData((resp) {
        if (resp is T && !completer.isCompleted) {
          completer.complete(resp);
        }
      });
    });
    final timer = Timer(const Duration(seconds: 10), () {
      if (!completer.isCompleted) completer.complete(null);
    });
    final result = await completer.future;
    timer.cancel();
    sub.close();
    return result;
  }'''),
    ...para('//',
        r'The method is generic over the response type, so one helper '
        r'serves any control reply. It resolves with the first '
        r'matching response or with null after ten seconds, so a '
        r'daemon that crashed mid-attach cannot leave the dialog '
        r'spinning forever.'),
    blank,
    ...para('//',
        r'The doc comment on this method records a false start, which '
        r'is the most useful part of the file. The first version used '
        r'Future.any([completer.future, Future.delayed(...)]). It '
        r'worked, but Future.any does not cancel the losing branch, so '
        r'the Future.delayed timer kept running for the full ten '
        r'seconds after a fast, successful reply. The callback was a '
        r'no-op by then, but "it leaked a live platform timer for 10s '
        r'past every successful attach, caught by flutter test’s ‘Timer '
        r'still pending after widget tree disposed’ check". The '
        r'replacement uses an explicit Timer that is cancelled in '
        r'the success path. It is a good example of a test framework '
        r'catching a resource leak that no user would ever see.'),
    ...sec(r'the list: request, filter, sort'),
    ...para('//',
        r'On open, initState calls _requestList, which clears the '
        r'state and sends ListProcessesRequest. The reply is consumed '
        r'by a ref.listen in build that sets _processes when a '
        r'ProcessListResponse arrives and the widget is mounted. While '
        r'_processes is null the dialog shows a spinner, an empty '
        r'result shows "No matching processes", and the Refresh icon '
        r'repeats the request. The filter box matches case-insensitive '
        r'name substrings or the pid as text, and the list is sorted '
        r'by lower-case name on each build.'),
    blank,
    ...para('//',
        r'Two limits show up when reading this against the connection '
        r'layer. First, sendRequest in ws_provider.dart drops a request '
        r'while the socket is down. If the dialog is opened during a '
        r'reconnect, the list request is lost and the spinner stays '
        r'until the user presses Refresh, because the list request, '
        r'unlike the attach request, has no timeout. Second, the '
        r'design document (Step 4) asks the picker to "show the '
        r'attach-time-clock note per §1.4", the one-line note that an '
        r'injected session sees allocations only from attach time '
        r'forward. I could not find that note anywhere in lib/. Both '
        r'are readings of the code, not observed behaviour.'),
    ...sec(r'how it is tested'),
    ...para('//',
        r'process_picker_dialog_test.dart builds a fake '
        r'GraphMessageConnection whose WsFrames records every frame '
        r'sent, overrides wsConnectionProvider with it and '
        r'controlResponseProvider with a broadcast controller, and '
        r'opens the dialog from a button. The file header calls it a '
        r'"partial" acceptance gate for Stage 7 Step 4: "the rest is a '
        r'manual run against a real daemon+target". The four tests:'),
    ...pt('//', r'open and list',
        r'the frames sent are exactly [{"type":"list_processes"}], the '
        r'list is absent while loading, and appears with two processes '
        r'after a ProcessListResponse.'),
    ...pt('//', r'x86 disabled',
        r'the tile for legacy32.exe is disabled and the text "64-bit '
        r'and cannot attach" is on screen.'),
    ...pt('//', r'success',
        r'selecting target.exe sends list_processes then '
        r'{"type":"attach_target","pid":111}; an ok reply closes the '
        r'dialog and attachedTargetProvider holds pid 111 and name '
        r'target.exe.'),
    ...pt('//', r'failure',
        r'the error widget shows the daemon text, the list stays, and '
        r'nothing is attached.'),
    blank,
    ...para('//',
        r'One note from the test helper: it deliberately avoids '
        r'pumpAndSettle, with the comment that the indeterminate '
        r'CircularProgressIndicator "animates forever and would make '
        r'pumpAndSettle time out". Two bounded pumps are enough. A '
        r'similar subtlety is in the control bar test: a fake '
        r'connection must use a never-closing stream, because an '
        r'empty stream completes at once, which would trigger the '
        r'reconnect path and clear the very send function the test '
        r'needs.'),
    ...sec(r'limits'),
    ...pt('//', r'no process search beyond name and pid',
        r'there is no grouping by executable, no path, no memory column.'),
    ...pt('//', r'no cancel for an attach in flight',
        r'the Cancel button pops the dialog; it does not abort an '
        r'attach already sent to the daemon.'),
    ...pt('//', r'message text is not interpreted',
        r'by design. The UI shows whatever the daemon says.'),
    blank,
    link('→ github.com/XNash/heaplens', 'https://github.com/XNash/heaplens'),
  ],
);
