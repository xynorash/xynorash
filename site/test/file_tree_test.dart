import 'package:flutter_test/flutter_test.dart';
import 'package:xnash_portfolio/data/authoring.dart';
import 'package:xnash_portfolio/data/projects.dart';
import 'package:xnash_portfolio/models/project.dart';
import 'package:xnash_portfolio/state/file_tree.dart';

Buffer page(String path) => makePage(path, lines: [cm('#', 'x')]);

void main() {
  final pages = [
    page('welcome.md'),
    page('proj/README.md'),
    page('proj/src/zeta.rs'),
    page('proj/src/Alpha.rs'),
    page('proj/docs/guide.md'),
    page('proj/Cargo.toml'),
    page('proj/src/util/mod.rs'),
    page('about.md'),
  ];

  test('top level keeps first-seen order; files and dirs nest by path', () {
    final root = buildTree(pages);
    expect(root.children.map((c) => c.name), ['welcome.md', 'proj', 'about.md']);
    final proj = root.children[1];
    expect(proj.isDir, isTrue);
    expect(proj.path, 'proj');
  });

  test('below the top level: README first among files, dirs before files', () {
    final proj = buildTree(pages).children[1];
    expect(proj.children.map((c) => c.name),
        ['docs', 'src', 'README.md', 'Cargo.toml']);
    final src = proj.children.firstWhere((c) => c.name == 'src');
    expect(src.children.map((c) => c.name), ['util', 'Alpha.rs', 'zeta.rs']);
  });

  test('visibleRows hides collapsed directories and draws guides', () {
    final root = buildTree(pages);
    expect(visibleRows(root, {}).length, 3);
    final rows = visibleRows(root, {'proj', 'proj/src'});
    final names = rows.map((r) => r.node.name).toList();
    expect(names, containsAllInOrder(['proj', 'docs', 'src', 'util']));
    expect(names, isNot(contains('mod.rs'))); // util still collapsed
    final alpha = rows.firstWhere((r) => r.node.name == 'Alpha.rs');
    expect(alpha.depth, 2);
    expect(alpha.guides, [true, true]); // proj and src have later siblings
  });

  test('page indices point back into the list', () {
    final root = buildTree(pages);
    final about = root.children.last;
    expect(pages[about.bufferIndex!].fileName, 'about.md');
  });

  test('ancestorsOf', () {
    expect(ancestorsOf('a/b/c.rs'), ['a', 'a/b']);
    expect(ancestorsOf('top.md'), isEmpty);
  });

  test('every real page path is unique, rooted at a known project', () {
    final seen = <String>{};
    for (final b in kBuffers) {
      expect(seen.add(b.fullPath), isTrue, reason: 'duplicate ${b.fullPath}');
      final p = b.project;
      if (p != null) expect(kProjectOrder, contains(p), reason: b.fullPath);
    }
  });
}
