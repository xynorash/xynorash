import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xnash_portfolio/state/app_state.dart';
import 'package:xnash_portfolio/widgets/editor.dart';

import 'support.dart';

Widget host(AppState s) => MaterialApp(
      home: Scaffold(
        body: AnimatedBuilder(
          animation: s,
          builder: (_, _) => EditorPane(state: s),
        ),
      ),
    );

void main() {
  testWidgets('renders welcome buffer content', (tester) async {
    final s = makeState();
    await tester.pumpWidget(host(s));
    expect(
      find.textContaining('Solving problems at the edge of impossible.',
          findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('renders heaplens content and fallback stats line',
      (tester) async {
    final s = makeState();
    s.openBuffer(idxOf('heaplens/README.md'));
    await tester.pumpWidget(host(s));
    // the banner's second line is short enough to render unwrapped
    final banner = s.buffer.lines[1].spans.map((x) => x.text).join();
    expect(find.textContaining(banner.trim(), findRichText: true),
        findsOneWidget);
    s.handleKey('G'); // stats line is appended at the bottom of the buffer
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('★ 0', findRichText: true), findsOneWidget);
    expect(find.textContaining('last push 2026-07-28', findRichText: true),
        findsOneWidget);
  });
}
