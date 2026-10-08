import 'package:flutter_test/flutter_test.dart';
import 'package:xnash_portfolio/data/projects.dart';

void main() {
  test('buffers in spec order', () {
    expect(kBuffers.map((b) => b.fileName).toList(), [
      'welcome.md',
      'heaplens.rs',
      'xynovim.lua',
      'xyno_scholar.dart',
      'xynorash.ps1',
      'xyno_arch.sh',
      'about.md',
    ]);
  });

  test('project buffers carry repo + fallbacks', () {
    final projects = kBuffers.where((b) => b.repo != null);
    expect(projects.length, 5);
    for (final b in projects) {
      expect(b.fallbackStars, greaterThanOrEqualTo(0));
      expect(b.fallbackPushed, isNotEmpty);
      expect(b.lines.length, greaterThan(30));
    }
  });

  test('no empty spans', () {
    for (final b in kBuffers) {
      for (final l in b.lines) {
        for (final s in l.spans) {
          expect(s.text, isNotEmpty, reason: '${b.fileName} has an empty span');
        }
      }
    }
  });
}
