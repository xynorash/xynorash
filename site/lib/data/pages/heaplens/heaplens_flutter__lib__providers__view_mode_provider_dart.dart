import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/heaplens_flutter/lib/providers/view_mode_provider.dart',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'view_mode_provider.dart — graph or map, one enum'),
    cm('//', r'twelve lines that choose the center of the screen'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', r'which center-panel view is shown'),
    kv('language', r'Dart / Riverpod'),
    kv('size', r'12 lines, one commit: 0309d9e (2026-07-06)'),
    kv('written by', r'control_bar.dart and target_status_banner.dart'),
    kv('read by', r'main.dart'),
    ...sec(r'the whole file'),
    ...code('dart', 'heaplens_flutter/lib/providers/view_mode_provider.dart · lines 3-12', r'''
/// Which center-panel widget is currently shown. Read by `main.dart` (Task
/// 9) to decide between the force-directed graph canvas and the memory-map
/// treemap-style view (`memory_map.dart`, Task 7 — not yet built on this
/// branch). This task only defines and exposes the enum/provider; the
/// control bar's toggle button writes to it.
enum ViewMode { graph, memoryMap }

/// Current view mode, toggled by the control bar. Defaults to [ViewMode.graph]
/// since that's the only view implemented so far on this branch.
final viewModeProvider = StateProvider<ViewMode>((ref) => ViewMode.graph);'''),
    ...para('//',
        r'An enum with two values and a StateProvider that starts on '
        r'graph. The comment is a snapshot of the state of the '
        r'branch on the day it was written: the memory map was '
        r'described as Task 7, not yet built on this branch, and the '
        r'graph canvas as the only view implemented so far. Both are '
        r'history now; the memory map exists and main.dart switches '
        r'on the enum.'),
    ...sec(r'how the switch is consumed'),
    ...code('dart', 'heaplens_flutter/lib/main.dart · lines 278-281', r'''
                                    child: switch (viewMode) {
                                      ViewMode.graph => GraphCanvas(layout: layout),
                                      ViewMode.memoryMap => const MemoryMap(),
                                    },'''),
    ...para('//',
        r'This is the exhaustive form: a Dart switch expression over '
        r'the enum, one arm per value, no default. Adding a third '
        r'mode would make main.dart fail to compile until its arm is '
        r'written, which is the property you want from an enum that '
        r'picks a screen. The widgets are swapped, not hidden, so '
        r'the inactive view is not built and not painting, and the '
        r'force layout it was reading from lives on in its own '
        r'provider.'),
    ...sec(r'the second writer'),
    ...code('dart', 'heaplens_flutter/lib/widgets/target_status_banner.dart · lines 79-86', r'''
              if (showMapViewAction)
                TextButton(
                  key: const Key('switchToMapViewButton'),
                  onPressed: () {
                    ref.read(viewModeProvider.notifier).state = ViewMode.memoryMap;
                  },
                  child: const Text('Switch to Map view'),
                ),'''),
    ...para('//',
        r'The control bar’s segmented toggle is the writer the '
        r'comment describes. The banner added another in the target '
        r'diagnostics work: when the diagnosis says the graph has no '
        r'edges, is unsymbolized, or is mostly orphaned, the banner '
        r'offers a Switch to Map view button. The reason is built '
        r'into the banner’s message text: allocation sizes and '
        r'growth are still available in the Map view, which needs no '
        r'ownership edges to be useful. A graph with no edges is a '
        r'field of unconnected dots; the address-ordered grid is the '
        r'honest view for that case.'),
    ...sec(r'design notes'),
    ...pt('//', r'why a provider',
        r'the toggle is in the ribbon and the consumer is the shell. '
        r'Two widgets far apart in the tree share a value with no '
        r'plumbing.'),
    ...pt('//', r'why an enum',
        r'a bool called isMap would read fine today, and a third '
        r'view would force a rename. The enum costs nothing and '
        r'makes the switch exhaustive.'),
    ...pt('//', r'not persisted',
        r'the app always starts in the graph view.'),
    ...pt('//', r'selection survives',
        r'switching views does not clear the selection, so a node '
        r'picked in the map is still selected on return to the '
        r'graph.'),
    ...sec(r'how it is tested'),
    ...para('//',
        r'widget_test.dart has the integration test, named view-mode '
        r'toggle swaps the center widget between GraphCanvas and '
        r'MemoryMap: it asserts GraphCanvas is present and MemoryMap '
        r'is absent by default, flips the provider, asserts the '
        r'reverse, and flips back. control_bar_test.dart checks the '
        r'toggle writes the provider. target_status_banner_test.dart '
        r'has the case no-edges banner offers a Switch to Map view '
        r'action that updates viewModeProvider: it asserts the '
        r'provider starts at ViewMode.graph and moves.'),
    ...sec(r'history'),
    ...pt('//', r'0309d9e (2026-07-06)',
        r'feat(flutter): control_bar. Adds the enum and the provider '
        r'with the pause and filter providers. The message calls it '
        r'the view-mode segmented button. The file has not been '
        r'touched since.'),
  ],
);
