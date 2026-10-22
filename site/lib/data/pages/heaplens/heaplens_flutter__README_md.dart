import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/heaplens_flutter/README.md',
  lines: [
    heading(r'# heaplens_flutter'),
    blank,
    ...text(
        r'This is the README that flutter create writes into every '
        r'new project, and it is still the README of the Flutter '
        r'app. It was generated on 2026-07-06 in the scaffold commit '
        r'and never edited. The document that describes HeapLens is '
        r'the repository README one level up; this file describes '
        r'nothing about HeapLens at all. A page about it is still '
        r'worth having, because it is the front door to a directory '
        r'with a lot of real work behind it, and because the stub is '
        r'a small piece of evidence about how the app was built.'),
    blank,
    kv('role', r'the untouched flutter create stub for the UI package'),
    kv('language', r'Markdown'),
    kv('size', r'17 lines, one commit: 56d5e41 (2026-07-06), never edited since'),
    kv('real README', r'heaplens/README.md at the repository root'),
    kv('app', r'heaplens_flutter: Flutter, Windows desktop target only'),
    ...sec(r'what the file says'),
    ...code('ini', 'heaplens_flutter/README.md · lines 1-3, 5-7', r'''
# heaplens_flutter

A new Flutter project.
...
## Getting Started

This project is a starting point for a Flutter application.'''),
    ...text(
        r'That is the whole message: a title, a sentence that is no '
        r'longer true, and a Getting Started section whose three '
        r'links point at the Flutter codelab. Nothing in it is wrong '
        r'in a harmful way, it is just not about this program. Every '
        r'claim in it describes the day before the first commit that '
        r'added code.'),
    ...sec(r'why I left it alone'),
    ...text(
        r'I would rather say this plainly than dress it up. The '
        r'scaffold commit is a chore commit, and the message says '
        r'what it did: flutter create with --platforms=windows, a '
        r'sibling of crates/ in the same repository history, plus '
        r'four dependencies. After that, every commit that touched '
        r'this directory went to lib/ and test/, where the actual '
        r'design decisions live, and the stub was never revisited. '
        r'The Flutter app was documented elsewhere: in the commit '
        r'messages, in the long doc comments at the top of each Dart '
        r'file, and in the M5 build plan under '
        r'docs/superpowers/plans, which was committed in 9ac04cd on '
        r'2026-07-06 together with the captured test fixtures.'),
    ...text(
        r'The consequence is that someone who opens heaplens_flutter '
        r'on its own gets the wrong first impression, and that is '
        r'the honest gap this page records. The rest of this page '
        r'does the job the README should do: it tells you what is in '
        r'the directory and where to read next, using only things '
        r'the source shows.'),
    ...sec(r'what the directory contains'),
    ...bullet(r'lib/main.dart',
        r'the shell: ProviderScope, the dark theme, and a ControlBar '
        r'over a status banner over the graph or the map, an '
        r'insights panel, and the right rail. It also owns the '
        r'roughly 30 Hz physics ticker.'),
    ...bullet(r'lib/models/',
        r'hand-written wire models (node, graph diff, control '
        r'channel, target diagnosis). The scaffold commit records '
        r'the decision: hand-written models, no codegen.'),
    ...bullet(r'lib/providers/',
        r'Riverpod state. ws_provider.dart owns the sockets, '
        r'graph_provider.dart owns the node map, and a set of small '
        r'providers hold UI state: paused, selection, view mode, '
        r'filters, the attached target, and the derived target '
        r'diagnosis.'),
    ...bullet(r'lib/simulation/',
        r'force_layout.dart, the physics that gives nodes positions. '
        r'It shares the vector_math dependency with the graph '
        r'canvas.'),
    ...bullet(r'lib/widgets/ and lib/theme/',
        r'everything that draws: graph canvas, memory map, control '
        r'bar, right rail, node detail, process picker, and the '
        r'shared building blocks and palette.'),
    ...bullet(r'lib/insights/',
        r'insight_rules.dart, the rules behind the insights panel.'),
    ...bullet(r'lib/debug/',
        r'the opt-in diagnostic overlay.'),
    ...bullet(r'test/',
        r'tests for models, providers, simulation and widgets, plus '
        r'test/fixtures, which holds real captured wire messages and '
        r'a PROVENANCE.md saying how they were captured.'),
    ...bullet(r'windows/',
        r'the Windows runner. It is the only platform folder; there '
        r'is no web/ or android/.'),
    ...sec(r'the one design constraint the scaffold commit records'),
    ...text(
        r'The scaffold commit message ends with a decision that '
        r'explains why this directory has only a windows/ platform '
        r'folder. It says the app is targeted at the Dart VM and '
        r'Windows desktop only, never web, and gives the reason as '
        r'u64-as-JSON-number safety, pointing at a seam note in the '
        r'protocol crate’s diff.rs. In other words: the daemon’s '
        r'pointers and timestamps are 64-bit integers sent as plain '
        r'JSON numbers, and Dart compiled to JavaScript would round '
        r'any integer above 2^53. On the Dart VM an int is 64 bits '
        r'wide and the problem does not exist. That is a decision '
        r'about the whole app, and it lives in a commit message '
        r'rather than in a README, which is exactly why this stub is '
        r'a gap.'),
    ...text(
        r'You can see the same decision from the other side in the '
        r'tests. The contract test reads the captured fixtures with '
        r'dart:io and asserts a node pointer of 1599777467168 and '
        r'exact timestamps. Those values are well inside 2^53, so '
        r'the test does not itself prove the VM-only claim; what it '
        r'pins is that the Dart models decode the real wire shape '
        r'field for field.'),
    ...sec(r'how the app is put together, in one paragraph'),
    ...text(
        r'A WebSocket stream of graph messages (snapshot, diff, and '
        r'a once-a-second stats message) is exposed as a Riverpod '
        r'provider. Two independent listeners consume it: the graph '
        r'provider, which mutates a node map in place and bumps a '
        r'revision number, and a small orchestrator in main.dart, '
        r'which forwards the same messages to the force layout so '
        r'nodes get positions. The comment in main.dart explains why '
        r'there are two: the node map is mutated in place and cannot '
        r'be diffed after the fact. The widgets read the node map '
        r'for facts and the layout for positions. Pause is '
        r'implemented by dropping messages in both listeners, not by '
        r'queueing them. A diagnosis provider reads stats plus the '
        r'node map and tells the user, in words, why an empty or '
        r'edgeless graph looks the way it does.'),
    ...sec(r'how to run it, as far as the files show'),
    ...text(
        r'The repository has no run script for the app. What the '
        r'files do show: the M5 build plan lists flutter analyze, '
        r'flutter test and flutter run -d windows as its gates, '
        r'pubspec.yaml pins the Dart SDK to ^3.12.1, the app has a '
        r'Windows runner, the debug overlay is switched on with a '
        r'--dart-define flag named HEAPLENS_DEBUG_OVERLAY, and the '
        r'tests read fixtures by the relative path test/fixtures, so '
        r'they have to be run from the heaplens_flutter directory. '
        r'The plan notes the same thing about the working directory.'),
    ...sec(r'what a better README would hold'),
    ...bullet(r'purpose',
        r'one sentence: the UI for the HeapLens daemon, showing an '
        r'ownership graph of live allocations.'),
    ...bullet(r'platform',
        r'Windows desktop, and why not web (the u64 note above).'),
    ...bullet(r'connection',
        r'which WebSocket address and which control channel the app '
        r'expects, which today you can only learn from '
        r'ws_provider.dart.'),
    ...bullet(r'layout',
        r'the directory list in this page.'),
    ...bullet(r'testing',
        r'that fixtures are real captures and one field is '
        r'hand-edited, with a pointer to '
        r'test/fixtures/PROVENANCE.md.'),
    ...text(
        r'That is five short paragraphs, and every fact on the list can '
        r'be found in the source. The stub has not been replaced; the '
        r'git history shows no commit that touched it after the '
        r'scaffold.'),
    ...sec(r'history'),
    ...bullet(r'56d5e41 (2026-07-06)',
        r'chore(flutter): scaffold heaplens_flutter. The only commit '
        r'that touches this file.'),
    ...bullet(r'9ac04cd (2026-07-06)',
        r'the M5 build plan and the captured contract fixtures, the '
        r'first commit that documents anything about the app.'),
    ...bullet(r'1cfb7f9 (2026-07-19)',
        r'the UI refresh: top-ribbon control bar, insights panel, '
        r'right rail, process picker and the XYNORASH theme. By then '
        r'the app had its own look and still had this README.'),
  ],
);
