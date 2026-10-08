/// Fuzzy score of [candidate] for [query] (lower is better), or null when
/// [query] is not a case-insensitive subsequence of it.
int? fuzzyScore(String query, String candidate) {
  final q = query.toLowerCase();
  final c = candidate.toLowerCase();
  var qi = 0;
  int? first;
  var gaps = 0;
  int? last;
  for (var ci = 0; ci < c.length && qi < q.length; ci++) {
    if (c[ci] == q[qi]) {
      first ??= ci;
      if (last != null) gaps += ci - last - 1;
      last = ci;
      qi++;
    }
  }
  return qi == q.length ? (first ?? 0) + gaps : null;
}

/// Returns indices of candidates whose characters contain `query` as a
/// case-insensitive subsequence, best match first. Empty query → all.
List<int> fuzzyRank(String query, List<String> candidates) {
  if (query.isEmpty) {
    return List.generate(candidates.length, (i) => i);
  }
  final q = query.toLowerCase();
  final scored = <(int, int)>[]; // (score, index)
  for (var i = 0; i < candidates.length; i++) {
    final c = candidates[i].toLowerCase();
    var qi = 0;
    int? first;
    var gaps = 0;
    int? last;
    for (var ci = 0; ci < c.length && qi < q.length; ci++) {
      if (c[ci] == q[qi]) {
        first ??= ci;
        if (last != null) gaps += ci - last - 1;
        last = ci;
        qi++;
      }
    }
    if (qi == q.length) {
      scored.add((first! + gaps, i));
    }
  }
  scored.sort((a, b) {
    final byScore = a.$1.compareTo(b.$1);
    return byScore != 0 ? byScore : a.$2.compareTo(b.$2);
  });
  return scored.map((s) => s.$2).toList();
}
