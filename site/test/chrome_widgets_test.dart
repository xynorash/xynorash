import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xnash_portfolio/data/projects.dart';
import 'package:xnash_portfolio/state/app_state.dart';
import 'package:xnash_portfolio/widgets/bufferline.dart';
import 'package:xnash_portfolio/widgets/neotree.dart';
import 'package:xnash_portfolio/widgets/statusline.dart';

import 'support.dart';

/// Rebuilds [child] on every state change (as the real shell does).
Widget host(AppState s, Widget Function() child) => MaterialApp(
      home: Scaffold(
        body: AnimatedBuilder(
          animation: s,
          builder: (_, _) => Column(children: [child()]),
        ),
      ),
    );

void main() {
  testWidgets('bufferline shows only open files; tap switches; x closes',
      (tester) async {
    final s = makeState();
    final a = idxOf('heaplens/README.md');
    final b = idxOf('xynovim/README.md');
    s.openBuffer(a);
    s.openBuffer(b);
    await tester.pumpWidget(host(s, () => Bufferline(state: s)));
    expect(find.text('welcome.md'), findsOneWidget);
    // two README.md tabs are disambiguated by their directory
    expect(find.text('heaplens/README.md'), findsOneWidget);
    expect(find.text('xynovim/README.md'), findsOneWidget);
    expect(find.text('about.md'), findsNothing); // not opened

    await tester.tap(find.text('heaplens/README.md'));
    await tester.pump();
    expect(s.bufferIndex, a);

    await tester.tap(find.text('\u{f00d}').at(1)); // close the heaplens tab
    await tester.pump();
    expect(s.openBuffers, isNot(contains(a)));
  });

  testWidgets('neotree: projects are directories; tap expands, tap opens',
      (tester) async {
    final s = makeState();
    await tester.pumpWidget(host(
        s, () => Expanded(child: NeoTree(state: s, onSelect: (_) {}))));
    for (final p in projectNames) {
      expect(find.textContaining(p, findRichText: true), findsOneWidget);
    }
    expect(s.expandedDirs, isEmpty);

    await tester.tap(find.textContaining('heaplens', findRichText: true));
    await tester.pump();
    expect(s.expandedDirs, contains('heaplens'));

    final readme = find.textContaining('README.md', findRichText: true);
    expect(readme, findsWidgets);
    await tester.tap(readme.first);
    await tester.pump();
    expect(s.buffer.fullPath, 'heaplens/README.md');
  });

  testWidgets('statusline shows mode, branch, path crumbs, theme',
      (tester) async {
    final s = makeState()..openBuffer(idxOf('heaplens/README.md'));
    await tester.pumpWidget(host(s, () => Statusline(state: s)));
    expect(find.text('NORMAL'), findsOneWidget);
    expect(find.textContaining('main'), findsOneWidget);
    expect(find.textContaining('heaplens › README.md', findRichText: true),
        findsOneWidget);
    expect(find.textContaining('aether'), findsOneWidget);
  });
}
