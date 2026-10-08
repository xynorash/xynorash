import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:xnash_portfolio/keymap/dispatcher.dart';
import 'package:xnash_portfolio/services/github_stats.dart';
import 'package:xnash_portfolio/state/app_state.dart';
import 'package:xnash_portfolio/theme/theme_controller.dart';
import 'package:xnash_portfolio/widgets/telescope.dart';
import 'package:xnash_portfolio/widgets/whichkey.dart';

AppState makeState() => AppState(
      theme: ThemeController(load: () => null, save: (_) {}),
      github: GithubStats(
          client: MockClient((_) async => http.Response('nope', 403))),
    );

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
    await tester.tap(find.text('find project'));
    await tester.pump();
    expect(s.mode, UiMode.finder);
  });

  testWidgets('telescope filters and enter opens buffer', (tester) async {
    final s = makeState();
    s.openFinder();
    s.finderType('rash');
    await tester.pumpWidget(host(s, TelescopeOverlay(state: s)));
    expect(find.textContaining('xynorash.ps1', findRichText: true),
        findsOneWidget);
    expect(find.textContaining('xynovim.lua', findRichText: true),
        findsNothing);
    s.handleKey('Enter');
    await tester.pump();
    expect(s.bufferIndex, 4);
    expect(s.mode, UiMode.normal);
  });

  testWidgets('telescope rows are clickable', (tester) async {
    final s = makeState();
    s.openFinder();
    await tester.pumpWidget(host(s, TelescopeOverlay(state: s)));
    await tester.tap(
        find.textContaining('about.md', findRichText: true));
    await tester.pump();
    expect(s.buffer.fileName, 'about.md');
  });
}
