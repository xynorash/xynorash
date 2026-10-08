import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-scholar/analysis_options.yaml',
  lines: [
    cm('#', '──────────────────────────────────────────'),
    cm('#', 'analysis_options.yaml — the lint configuration nobody overrode'),
    cm('#', 'two live lines, twenty-six lines of generator comments'),
    cm('#', '──────────────────────────────────────────'),
    blank,
    kv('role', 'configures the Dart analyzer and linter for the whole package'),
    kv('language', 'YAML'),
    kv('size', '28 lines, 1 include, 0 custom rules'),
    kv('history', 'one commit (7a200e7, the scaffold); never edited'),
    kv('enforced by', 'the editor and flutter analyze; not by CI'),
    ...sec('what the file actually says'),
    ...para('#',
        'Strip the comments and the configuration is a single '
        'include and an empty rules map. Everything else is the '
        'template that flutter create writes, including the '
        'pointers to dart.dev and the example rules that are '
        'commented out. Nothing in it was adapted to the project, '
        'which is itself informative: it was accepted as generated.'),
    ...code('ini', 'analysis_options.yaml · the one live line', r'''
include: package:flutter_lints/flutter.yaml'''),
    ...para('#',
        'The comment above it in the file explains the intent in its '
        'own words: the line “activates a set of recommended lints '
        'for Flutter apps, packages, and plugins designed to '
        'encourage good coding practices.” The linter block that '
        'follows is the other half of the file, and it is empty:'),
    ...code('ini', 'analysis_options.yaml · the empty rules map', r'''
linter:
  rules:
    # avoid_print: false  # Uncomment to disable the `avoid_print` rule
    # prefer_single_quotes: true  # Uncomment to enable the `prefer_single_quotes` rule'''),
    ...para('#',
        'Two rules are named as examples, one to relax and one to '
        'tighten. Neither is acted on. The project neither turns '
        'off a recommended rule nor adds a stricter one.'),
    ...sec('where the rules really come from'),
    ...para('#',
        'The include points at a file inside a package, so the rule '
        'list lives in flutter_lints, not here. The package is '
        'declared as a development dependency, and the lock file '
        'fixes the exact versions that supply the rules:'),
    ...code('ini', 'pubspec.yaml · the dependency', r'''
  flutter_lints: ^5.0.0'''),
    ...code('ini', 'pubspec.lock · the resolved versions (trimmed)', r'''
  flutter_lints:
    dependency: "direct dev"
...
    version: "5.0.0"
...
  lints:
    dependency: transitive
...
    version: "5.1.1"'''),
    ...para('#',
        'The lock file resolves flutter_lints to 5.0.0 and marks '
        'the plain lints package as a transitive dependency, '
        'resolved to 5.1.1. The practical meaning is '
        'reproducibility: anyone who '
        'runs flutter pub get with this lock file gets the same '
        'rule set, so a warning seen in one editor is the warning '
        'seen in another. I do not have the contents of those '
        'packages in this environment, so I do not list the rules '
        'here. The package documentation is the place to read them.'),
    ...sec('does the code live up to it?'),
    ...para('#',
        'The repository cannot show analyzer output, and Flutter is '
        'not available here to run it. What can be checked is '
        'whether the code carries the marks of a codebase that '
        'was written with the analyzer switched on.'),
    ...pt('#', 'no suppressions',
        'a search of lib/ and test/ finds no ignore comments. In '
        'a codebase of 46 library files and 4,280 lines, every '
        'lint that fired was either obeyed or never fired.'),
    ...pt('#', 'no print calls',
        'the same search finds no print statement. The example rule '
        'avoid_print, named in the file, has nothing to complain '
        'about. The app reports problems through exception types '
        'and state, not the console.'),
    ...pt('#', 'keys on widgets',
        'the root widget declares its constructor with a key '
        'parameter and a const modifier, the shape the Flutter '
        'lint set asks for. See the constructor of XynoScholarApp in '
        'lib/app.dart.'),
    ...pt('#', 'current API names',
        'lib/screens/key_entry_screen.dart builds translucent '
        'colours with withValues(alpha: ...), and a search finds '
        'no use of the older withOpacity. This is consistent with '
        'someone reading analyzer hints, but it is circumstantial.'),
    ...sec('why CI never sees this file'),
    ...para('#',
        'A lint configuration only matters if something runs it. '
        'The deploy workflow has these two steps between checking '
        'out the code and uploading the artifact:'),
    ...code('yaml', '.github/workflows/deploy.yml · what CI runs', r'''
      - name: Install dependencies
        run: flutter pub get

      - name: Build web
        run: flutter build web --release --base-href "/xyno-scholar/"'''),
    ...para('#',
        'There is no flutter analyze and no flutter test. The '
        'analysis options therefore apply in the editor and in a '
        'manual run, and a lint violation or a failing test cannot '
        'stop a push to main from being deployed. For a private, '
        'single-user app that was scaffolded, moved across three AI '
        'providers and deployed in a little over three hours, that is a '
        'defensible trade. It does mean the guarantees of this '
        'file are advisory.'),
    ...sec('what a stricter version could add'),
    ...para('#',
        'These are suggestions, none verified against this '
        'codebase, listed from cheapest to most opinionated:'),
    ...bullet('analyze in CI',
        'add flutter analyze as a workflow step ahead of the build. '
        'It turns every existing lint into a gate for free.'),
    ...bullet('test in CI',
        'add flutter test. The three test files are described on '
        'their own pages; the widget test may need a browser '
        'platform, as discussed there.'),
    ...bullet('stricter typing',
        'the analyzer language section can switch on strict '
        'casts, strict inference and strict raw types. The one '
        'real defect in this project’s history, the sanitiser '
        'returning a map with lost type arguments, was a '
        'type-system problem of that family. I did not run these '
        'modes, so I cannot say whether they would have '
        'flagged it.'),
    ...bullet('prefer_single_quotes',
        'the example in the file. The code already reads as '
        'single-quoted, so enabling it would mostly document the '
        'house style; I did not count the exceptions.'),
    ...sec('limits'),
    ...pt('#', 'generated, not designed',
        'nothing here records a decision. If a lint is being '
        'ignored in practice, it is because the defaults are '
        'permissive, not because someone chose that.'),
    ...pt('#', 'no analyzer exclusions',
        'there is no exclude list, so generated files would be '
        'analysed. The project has no code generation, so this '
        'has never mattered.'),
    blank,
    link('→ github.com/XNash/xyno-scholar', 'https://github.com/XNash/xyno-scholar'),
  ],
);
