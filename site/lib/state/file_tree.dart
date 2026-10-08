import '../models/project.dart';

/// A node of the explorer tree: a directory or a page (file).
class TreeNode {
  final String name;

  /// Full path from the tree root, e.g. `heaplens/crates/heaplens-alloc`.
  final String path;

  /// Index into the page list for files; null for directories.
  final int? bufferIndex;
  final List<TreeNode> children = [];

  TreeNode(this.name, this.path, {this.bufferIndex});

  bool get isDir => bufferIndex == null;
}

/// One visible row of the tree with its drawing context.
class TreeRow {
  final TreeNode node;
  final int depth;

  /// For each ancestor level, whether that ancestor has later siblings
  /// (draw a `│` guide) — plus [isLast] for this row's own connector.
  final List<bool> guides;
  final bool isLast;
  const TreeRow(this.node, this.depth, this.guides, this.isLast);
}

/// Builds the directory tree from page paths. Top-level order follows the
/// order in which paths first appear; below the top level, directories come
/// first, then files, both alphabetical (case-insensitive).
TreeNode buildTree(List<Buffer> buffers) {
  final root = TreeNode('', '');
  for (var i = 0; i < buffers.length; i++) {
    final parts = buffers[i].fullPath.split('/');
    var cur = root;
    for (var d = 0; d < parts.length; d++) {
      final isFile = d == parts.length - 1;
      final path = parts.sublist(0, d + 1).join('/');
      if (isFile) {
        cur.children.add(TreeNode(parts[d], path, bufferIndex: i));
      } else {
        var next = cur.children.where((c) => c.isDir && c.name == parts[d]);
        if (next.isEmpty) {
          final n = TreeNode(parts[d], path);
          cur.children.add(n);
          cur = n;
        } else {
          cur = next.first;
        }
      }
    }
  }
  void sortBelow(TreeNode n, int depth) {
    if (depth >= 1) {
      n.children.sort((a, b) {
        if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
        // README first among the files of a directory.
        final ra = a.name.toLowerCase() == 'readme.md';
        final rb = b.name.toLowerCase() == 'readme.md';
        if (ra != rb) return ra ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    }
    for (final c in n.children) {
      if (c.isDir) sortBelow(c, depth + 1);
    }
  }

  sortBelow(root, 0);
  return root;
}

/// Flattens the tree into the rows currently visible given [expanded].
List<TreeRow> visibleRows(TreeNode root, Set<String> expanded) {
  final rows = <TreeRow>[];
  void walk(TreeNode n, int depth, List<bool> guides) {
    for (var i = 0; i < n.children.length; i++) {
      final c = n.children[i];
      final last = i == n.children.length - 1;
      rows.add(TreeRow(c, depth, List.of(guides), last));
      if (c.isDir && expanded.contains(c.path)) {
        walk(c, depth + 1, [...guides, !last]);
      }
    }
  }

  walk(root, 0, const []);
  return rows;
}

/// All ancestor directory paths of [path] (`a/b/c.rs` -> `a`, `a/b`).
List<String> ancestorsOf(String path) {
  final parts = path.split('/');
  return [
    for (var i = 1; i < parts.length; i++) parts.sublist(0, i).join('/'),
  ];
}
