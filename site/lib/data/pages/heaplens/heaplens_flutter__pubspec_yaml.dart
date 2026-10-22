import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/heaplens_flutter/pubspec.yaml',
  lines: [
    cm('#', '──────────────────────────────────────────'),
    cm('#', r'pubspec.yaml — four dependencies, one platform'),
    cm('#', r'the manifest of a UI that was deliberately kept small'),
    cm('#', '──────────────────────────────────────────'),
    blank,
    kv('role', r'package manifest for heaplens_flutter'),
    kv('language', r'YAML'),
    kv('size', r'94 lines, mostly the generated explanatory comments'),
    kv('history', r'one commit: 56d5e41 (2026-07-06), never edited since'),
    kv('sdk', r'Dart ^3.12.1, flutter_riverpod ^2.5.0, fl_chart ^0.69.0'),
    ...sec(r'the whole decision, in thirty lines'),
    ...code('ini', 'heaplens_flutter/pubspec.yaml · lines 1-1, 5-5, 19-22, 30-32, 36-41, 43-45, 52-52, 58-63', r'''
name: heaplens_flutter
...
publish_to: 'none' # Remove this line if you wish to publish to pub.dev
...
version: 1.0.0+1

environment:
  sdk: ^3.12.1
...
dependencies:
  flutter:
    sdk: flutter
...
  cupertino_icons: ^1.0.8

  flutter_riverpod: ^2.5.0
  web_socket_channel: ^2.4.0
  vector_math: ^2.1.4
  fl_chart: ^0.69.0
...
dev_dependencies:
  flutter_test:
    sdk: flutter
...
  flutter_lints: ^6.0.0
...
flutter:

  # The following line ensures that the Material Icons font is
  # included with your application, so that you can use the icons in
  # the material Icons class.
  uses-material-design: true'''),
    ...para('#',
        r'Almost all of the file is boilerplate that flutter create '
        r'wrote and that I left standing. The lines above are the '
        r'ones that carry a decision. The scaffold commit message '
        r'says which: it adds flutter_riverpod, web_socket_channel, '
        r'vector_math and fl_chart per locked decisions on state '
        r'management and on hand-written models with no code '
        r'generation, and it fixes the target at the Dart VM and '
        r'Windows desktop only.'),
    ...sec(r'what each dependency is for'),
    ...pt('#', r'flutter_riverpod ^2.5.0',
        r'all state. Every provider file in lib/providers uses it. '
        r'The code uses StateProvider for the small toggles (paused, '
        r'selection, view mode, the three filters) and '
        r'Notifier/NotifierProvider for anything with behaviour (the '
        r'graph, the attached target, the target diagnosis). The '
        r'caret range allows 2.x releases from 2.5.0 up.'),
    ...pt('#', r'web_socket_channel ^2.4.0',
        r'the daemon connection. It is imported in exactly one file, '
        r'lib/providers/ws_provider.dart, which keeps socket '
        r'concerns out of the widgets.'),
    ...pt('#', r'vector_math ^2.1.4',
        r'positions and velocities in the force layout. Imported by '
        r'lib/simulation/force_layout.dart and by '
        r'lib/widgets/graph_canvas.dart, and by the force layout '
        r'test.'),
    ...pt('#', r'fl_chart ^0.69.0',
        r'the size-over-time sparkline in node_detail.dart, its only '
        r'importer. A single small line chart is the whole use of a '
        r'charting library.'),
    ...sec(r'the dependency that nothing uses'),
    ...para('#',
        r'cupertino_icons is in the list because flutter create put '
        r'it there. A search of lib/ and test/ finds no reference to '
        r'it, so it looks like a leftover dependency. Removing it '
        r'would be a one-line change. It is the one line in the '
        r'manifest that reads as scaffold default rather than '
        r'decision.'),
    ...sec(r'what is missing, on purpose'),
    ...pt('#', r'assets and fonts',
        r'the flutter section has only uses-material-design: true; '
        r'the assets and fonts blocks are still the commented '
        r'generator examples. The theme file says why for fonts: no '
        r'custom font is bundled, because a system font used '
        r'consistently reads more intentional than an inconsistently '
        r'applied downloaded one. Consolas is the monospace family '
        r'and the code falls back to Cascadia Code and then the '
        r'generic monospace.'),
    ...pt('#', r'publishing',
        r'publish_to: none is set, which is the right setting for an '
        r'application that is not a pub.dev package.'),
    ...pt('#', r'description',
        r'still reads A new Flutter project. It is metadata that '
        r'shows up nowhere a user would look, and it shares its fate '
        r'with the README.'),
    ...pt('#', r'version',
        r'1.0.0+1, the generator default; the app has no release '
        r'process in this directory that would bump it.'),
    ...sec(r'the platform choice, and what it does to the manifest'),
    ...para('#',
        r'Because the target is only the Dart VM on Windows, the '
        r'manifest has no web configuration, no platform '
        r'conditionals, and no JS-compatible alternatives. The '
        r'reason is in the scaffold commit message: the daemon sends '
        r'pointers and timestamps as 64-bit values in JSON numbers, '
        r'and the commit cites the protocol crate’s documented seam '
        r'note as the reason web is out. Choosing the Dart VM means '
        r'an int is a real 64-bit integer, so the models can use '
        r'plain int fields and the app never needs a big-integer '
        r'package. That is why the dependency list has no bignum or '
        r'JSON-codegen entry: the platform decision removed the need '
        r'for them.'),
    ...sec(r'the SDK constraint'),
    ...para('#',
        r'environment: sdk: ^3.12.1 lets the code use current Dart '
        r'syntax without caveats. You can see it in the source: '
        r'switch statements with pattern cases such as case '
        r'DetachResultResponse(ok: true) and case '
        r'TargetExitedResponse(:final pid) in target_provider.dart, '
        r'record typedefs such as the sparkline sample typedef in '
        r'node_detail.dart, and wildcard parameters written as (_, '
        r'_) in the diagnostics provider test. None of those would '
        r'compile on an older SDK, so the constraint is a real '
        r'floor, not a default.'),
    ...sec(r'how it is tested'),
    ...para('#',
        r'A manifest has no unit test of its own. flutter_test comes '
        r'from the SDK, and flutter_lints is wired up by '
        r'analysis_options.yaml, which includes the flutter ruleset. '
        r'The check that matters is that flutter pub get resolves, '
        r'and pubspec.lock records the result of that resolution, '
        r'committed next to this file.'),
    ...sec(r'history'),
    ...pt('#', r'56d5e41 (2026-07-06)',
        r'the scaffold commit. The message names the four additions '
        r'and the platform decision. Nothing has touched the file '
        r'since, which means the whole of the app, through the UI '
        r'refresh of 2026-07-19, fit inside these four dependencies.'),
  ],
);
