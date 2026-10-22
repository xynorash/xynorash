import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/heaplens_flutter/analysis_options.yaml',
  lines: [
    cm('#', '──────────────────────────────────────────'),
    cm('#', r'analysis_options.yaml — the lints I never overrode'),
    cm('#', r'the generated file, kept exactly as generated'),
    cm('#', '──────────────────────────────────────────'),
    blank,
    kv('role', r'analyzer and linter configuration for heaplens_flutter'),
    kv('language', r'YAML'),
    kv('size', r'28 lines, one active line'),
    kv('history', r'one commit: 56d5e41 (2026-07-06), never edited since'),
    kv('ruleset', r'package:flutter_lints/flutter.yaml'),
    ...sec(r'the one line that does anything'),
    ...code('ini', 'heaplens_flutter/analysis_options.yaml · lines 10-12, 23-25', r'''
include: package:flutter_lints/flutter.yaml

linter:
...
  rules:
    # avoid_print: false  # Uncomment to disable the `avoid_print` rule
    # prefer_single_quotes: true  # Uncomment to enable the `prefer_single_quotes` rule'''),
    ...para('#',
        r'The file has one active instruction: include the '
        r'recommended Flutter lint set. The linter rules block is '
        r'empty, and both commented examples (avoid_print and '
        r'prefer_single_quotes) are still comments. Every other line '
        r'is the explanatory header that flutter create writes.'),
    ...sec(r'why it stayed this short'),
    ...para('#',
        r'The evidence that the project never fought its linter is '
        r'in the tree. No rule is switched off in this file, and a '
        r'search of lib/ and test/ finds no ignore or '
        r'ignore_for_file comment; the only hit for the word ignore '
        r'is the title of a test about a TargetExited push for the '
        r'wrong pid. The defaults were enough for the code as '
        r'written.'),
    ...para('#',
        r'A related decision is visible in the commit history. One '
        r'post-merge commit, cd348b6 (2026-07-21), says that '
        r'right_rail.dart needed a GraphStats arm added to two '
        r'switches after a merge introduced that variant, and that '
        r'this was caught by flutter analyze. That is the analyzer '
        r'doing a job the compiler would also do, since Dart 3 '
        r'checks switch exhaustiveness on sealed types, but the '
        r'commit message credits the analyzer, which is how the '
        r'check is run in practice.'),
    ...sec(r'what the ruleset does and does not buy'),
    ...pt('#', r'catches',
        r'missing const constructors, unused imports and variables, '
        r'and non-exhaustive '
        r'switches over the sealed message types.'),
    ...pt('#', r'does not catch',
        r'anything about behaviour. Some bugs in the history were '
        r'behavioural, such as a banner blaming missing debug symbols '
        r'for an orphan problem (ead62bb, 2026-07-22), and lints say '
        r'nothing about those. Tests and the DebugOverlay are the '
        r'tools that address that class of bug.'),
    ...pt('#', r'is deliberately not stricter',
        r'the file enables no extra rules (the avoid_print and '
        r'prefer_single_quotes examples are still commented out), so '
        r'the project runs on the standard set and nothing stricter.'),
    ...sec(r'edge cases'),
    ...para('#',
        r'The include line only works if flutter_lints is '
        r'resolvable, and it is: pubspec.yaml lists flutter_lints '
        r'^6.0.0 under dev_dependencies. If it were removed, the '
        r'analyzer would report an unresolved include at the top of '
        r'this file, not at any Dart file, which is a confusing '
        r'place to see it. Keeping the two lines in the two files in '
        r'step is the only maintenance this file needs.'),
    ...sec(r'how it is exercised'),
    ...para('#',
        r'There is no test for this file. It is exercised every time '
        r'flutter analyze runs. The commit messages show that being '
        r'part of the routine: cd348b6 reports a catch by flutter '
        r'analyze, and the one-line include is why that catch '
        r'arrives with the standard rule names.'),
    ...sec(r'history'),
    ...pt('#', r'56d5e41 (2026-07-06)',
        r'scaffold commit; it is the only commit that has touched '
        r'this file. The 28 lines have been the same through all the '
        r'later work on the UI.'),
  ],
);
