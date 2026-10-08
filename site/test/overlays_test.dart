import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xnash_portfolio/keymap/dispatcher.dart';
import 'package:xnash_portfolio/state/app_state.dart';
import 'package:xnash_portfolio/widgets/telescope.dart';
import 'package:xnash_portfolio/widgets/whichkey.dart';

import 'support.dart';

Widget host(AppState s, Widget child) => MaterialApp(
      home: Scaffold(
        body: AnimatedBuilder(animation: s, builder: (_, _) => child),
      ),
    );

void main() {
  testWidgets('whichkey row opens finder', (tester) async {
    final s = makeState();
    s.openWhichKey();
    await tester.pumpWidget(host(s, WhichKeyOverlay(state: s)));
    await tester.tap(find.text('find file'));
    await tester.pump();
    expect(s.mode, UiMode.finder);
  });

  testWidgets('telescope shows names with their directories; enter opens',
      (tester) async {
    final s = makeState();
    s.openFinder();
    s.finderType('xynorash');
    await tester.pumpWidget(host(s, TelescopeOverlay(state: s)));
    expect(find.textContaining('README.md', findRichText: true),
        findsWidgets);
    expect(find.textContaining('xynorash-pwsh', findRichText: true),
        findsWidgets);
    s.handleKey('Enter');
    await tester.pump();
    expect(s.buffer.project, 'xynorash-pwsh');
    expect(s.mode, UiMode.normal);
  });

  testWidgets('telescope rows are clickable', (tester) async {
    final s = makeState();
    s.openFinder();
    await tester.pumpWidget(host(s, TelescopeOverlay(state: s)));
    await tester.tap(find.textContaining('about.md', findRichText: true));
    await tester.pump();
    expect(s.buffer.fileName, 'about.md');
  });

  testWidgets('telescope caps the visible rows and reports the total',
      (tester) async {
    final s = makeState();
    s.openFinder();
    await tester.pumpWidget(host(s, TelescopeOverlay(state: s)));
    final total = s.finderResults.length;
    expect(find.textContaining('$total/', findRichText: true), findsOneWidget);
    final shown = AppState.finderRows;
    expect(s.finderResults.take(shown).length, lessThanOrEqualTo(shown));
  });
}
