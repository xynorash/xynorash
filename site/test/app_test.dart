import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xnash_portfolio/app.dart';
import 'package:xnash_portfolio/widgets/telescope.dart';

void main() {
  testWidgets('shell renders chrome and reacts to vim keys', (tester) async {
    await tester.pumpWidget(const XnashApp());
    await tester.pump();

    expect(find.text('welcome.md'), findsWidgets); // bufferline + tree
    expect(find.text('NORMAL'), findsOneWidget);

    // On the dashboard, "1" opens the first project's README as a tab.
    await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
    await tester.pump();
    expect(find.textContaining('README.md'), findsWidgets);

    // Space f → telescope
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.pump();
    expect(find.byType(TelescopeOverlay), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.byType(TelescopeOverlay), findsNothing);
  });
}
