import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xnash_portfolio/data/projects.dart';
import 'package:xnash_portfolio/widgets/dashboard.dart';

import 'support.dart';

void main() {
  testWidgets('dashboard lists projects as directories and opens them',
      (tester) async {
    final s = makeState();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AnimatedBuilder(
          animation: s,
          builder: (_, _) => Dashboard(state: s),
        ),
      ),
    ));
    for (final p in projectNames) {
      expect(find.text('$p/'), findsOneWidget);
    }
    expect(find.text('find file'), findsOneWidget);
    await tester.tap(find.text('${projectNames[1]}/'));
    await tester.pump();
    expect(s.buffer.fullPath, '${projectNames[1]}/README.md');
    expect(s.expandedDirs, contains(projectNames[1]));
  });

  test('welcome-buffer shortcuts: digits open projects, a, t', () {
    final s = makeState();
    s.handleKey('2');
    expect(s.buffer.fullPath, '${projectNames[1]}/README.md');
    s.openBuffer(0);
    s.handleKey('a');
    expect(s.buffer.fileName, 'about.md');
    s.openBuffer(0);
    s.handleKey('t');
    expect(s.themeController.name, isNot('aether'));
  });
}
