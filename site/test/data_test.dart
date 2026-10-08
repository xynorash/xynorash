import 'package:flutter_test/flutter_test.dart';
import 'package:xnash_portfolio/data/interim_pages.dart';
import 'package:xnash_portfolio/data/projects.dart';

void main() {
  test('welcome first, about last, projects in between in project order', () {
    expect(kBuffers.first.fileName, 'welcome.md');
    expect(kBuffers.last.fileName, 'about.md');
    final order = [
      for (final b in kBuffers)
        if (b.project != null) kProjectOrder.indexOf(b.project!),
    ];
    expect(order, everyElement(greaterThanOrEqualTo(0)));
    final sorted = [...order]..sort();
    expect(order, sorted);
  });

  test('every project has a README with a summary and repo stats', () {
    expect(projectNames, kProjectOrder);
    for (final p in projectNames) {
      final readme = kBuffers.singleWhere((b) => b.fullPath == '$p/README.md');
      expect(readme.repo, isNotNull, reason: p);
      expect(readme.summary, isNotEmpty, reason: p);
      expect(readme.fallbackPushed, isNotEmpty, reason: p);
      expect(readme.lines.length, greaterThan(100), reason: p);
    }
  });

  test('only README pages carry repo stats', () {
    for (final b in kBuffers.where((b) => b.repo != null)) {
      expect(b.fileName, 'README.md');
    }
  });

  test('paths are unique and ids match paths', () {
    final seen = <String>{};
    for (final b in kBuffers) {
      expect(seen.add(b.fullPath), isTrue, reason: b.fullPath);
      expect(b.fileName, b.fullPath.split('/').last);
    }
  });

  test('no empty spans anywhere', () {
    for (final b in kBuffers) {
      for (final l in b.lines) {
        for (final s in l.spans) {
          expect(s.text, isNotEmpty, reason: '${b.fullPath} has an empty span');
        }
      }
    }
  });

  test('every project page has a banner and an outline', () {
    // (temporary placeholders are exempt until real pages replace them)
    final interim = {for (final b in kInterimPages) b.fullPath};
    for (final b in kBuffers
        .where((b) => b.project != null && !interim.contains(b.fullPath))) {
      expect(b.lines.length, greaterThan(10), reason: b.fullPath);
      expect(b.outline, isNotEmpty, reason: b.fullPath);
    }
  });
}
