import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-scholar/pubspec.yaml',
  lines: [
    cm('#', '──────────────────────────────────────────'),
    cm('#', 'pubspec.yaml — 27 lines of configuration in a 101-line file'),
    cm('#', 'the dependency list is the architecture, seen from outside'),
    cm('#', '──────────────────────────────────────────'),
    blank,
    kv('role', 'package manifest: identity, SDK range, dependencies'),
    kv('language', 'YAML (pub)'),
    kv('size', '101 lines, of which 27 are configuration'),
    kv('resolved by', 'pubspec.lock (554 lines), requires Flutter 3.35.0 or newer'),
    kv('edited', 'twice: scaffold (7a200e7), then one dependency swap (89a9c12)'),
    ...sec('how to read it'),
    ...para('#',
        'Roughly three quarters of this file is comments and blank '
        'lines, the boilerplate that flutter create writes: '
        'explanations of version numbers, of asset and font sections, '
        'of the lints package. Only 27 lines are live configuration. '
        'The useful way to read it is to ignore the comments and '
        'treat the live lines as a bill of materials: every package '
        'named here is a decision, and the cheapest way to understand '
        'the app’s shape is to ask what each one is for and where in '
        'the code it is used. The counts below come from searching '
        'the import lines in lib/ and test/.'),
    ...sec('identity and constraints'),
    ...code('ini', 'pubspec.yaml · identity', r'''
name: xyno_scholar
description: "A new Flutter project."
publish_to: 'none' # Remove this line if you wish to publish to pub.dev
version: 1.0.0+1'''),
    ...pt('#', 'name: xyno_scholar',
        'the package name. It is not decorative: the tests import the '
        'app by it, as '
        'package:xyno_scholar/services/mistral_client.dart, so '
        'renaming it means editing every test import.'),
    ...pt('#', 'description',
        'still the default, “A new Flutter project.” The same default '
        'sits in web/index.html as the page’s meta description and '
        'the title is the package name. Both are cosmetic leftovers '
        'from the scaffold.'),
    ...pt('#', 'publish_to: none',
        'keeps the app from being published to pub.dev by accident. '
        'The comment beside it is the generator’s own and was left in '
        'place.'),
    ...pt('#', 'version: 1.0.0+1',
        'never bumped. No release process exists, which fits an app '
        'that deploys from every push to main.'),
    ...code('ini', 'pubspec.yaml · the SDK range', r'''
environment:
  sdk: ^3.9.2'''),
    ...para('#',
        'The Dart constraint is a caret on 3.9.2, meaning at least '
        '3.9.2 and below 4.0.0. The lock file derives a Flutter floor '
        'from it: flutter must be at least 3.35.0, and that is the '
        'number the README gives as its requirement (stable channel, '
        '3.35 or newer). The CI workflow does not pin a version at '
        'all; it uses whatever stable is, which is how commit 89a9c12 '
        'found that the newest stable at that time was too new for '
        'one of the dependencies below.'),
    ...sec('the dependency list'),
    ...code('ini', 'pubspec.yaml · dependencies', r'''
  flutter_riverpod: ^2.6.1
  http: ^1.2.2
  flutter_markdown: ^0.7.4+3
  markdown: ^7.3.1
  google_fonts: ^6.2.1
  shared_preferences: ^2.3.3
  lucide_icons_flutter: ^3.1.15
  url_launcher: ^6.3.1
  html_unescape: ^2.0.0
  web: ^1.1.0
  uuid: ^4.5.1'''),
    ...para('#',
        'All eleven are caret constraints, and pubspec.lock fixes '
        'what each resolved to. Going down the list, with the '
        'resolved version and the files that actually import it:'),
    ...pt('#', 'flutter_riverpod 2.6.1',
        'all application state. Imported by 20 files in lib/ and by '
        'the widget test. The four providers in lib/providers/ define '
        'the state (API key, preferences, generation, notebook) and '
        'the screens and widgets read it. The caret range keeps the '
        'app on the 2.x line, whose Notifier and AsyncNotifier '
        'classes the providers use, together with StateProvider for '
        'the small pieces of state.'),
    ...pt('#', 'http 1.6.0',
        'the HTTP client. Used by exactly one library file, '
        'lib/services/mistral_client.dart, and by the test through '
        'package:http/testing.dart, whose MockClient is what lets all '
        'eight client tests run without a network.'),
    ...pt('#', 'flutter_markdown 0.7.7+1 and markdown 7.3.1',
        'both imported by a single file, '
        'lib/widgets/common/markdown_text.dart, the shared renderer '
        'for every piece of model-written prose. The markdown package '
        'supplies the GitHub-flavoured extension set; '
        'flutter_markdown draws the result.'),
    ...pt('#', 'google_fonts 6.3.3',
        'used only in lib/theme/app_typography.dart. The README notes '
        'that Fraunces, Inter and JetBrains Mono are fetched from '
        'Google’s font CDN at runtime, so the app needs a connection '
        'for its typography.'),
    ...pt('#', 'shared_preferences 2.5.5',
        'imported once, in the notebook provider. On the web its '
        'implementation package, shared_preferences_web 2.4.3, is in '
        'the lock file; I take it to use the browser’s localStorage, '
        'which is a different kind of storage from the sessionStorage '
        'the API key may use.'),
    ...pt('#', 'lucide_icons_flutter 3.1.15',
        'the icon set, imported by 16 files. This line is the one '
        'that was edited after the scaffold; see below.'),
    ...pt('#', 'url_launcher 6.3.2',
        'three importers: the unlock screen’s link to '
        'console.mistral.ai, the markdown renderer’s link handler, '
        'and the bibliography tab.'),
    ...pt('#', 'html_unescape 2.0.0',
        'two importers, and both are defences against the same '
        'problem: lib/services/sanitize.dart decodes HTML entities in '
        'everything the model returns, and the markdown renderer does '
        'it again before drawing.'),
    ...pt('#', 'web 1.1.1',
        'the browser APIs, via package:web. Exactly two files import '
        'it: session_storage.dart for sessionStorage and '
        'web_download.dart for the BibTeX file download. Everything '
        'browser-specific is confined to those two small files.'),
    ...pt('#', 'uuid 4.6.0',
        'one importer: the notebook provider, which gives every saved '
        'topic a random version-4 identifier.'),
    ...sec('the dependency that is not used'),
    ...pt('#', 'cupertino_icons 1.0.9',
        'declared in the scaffold with the comment about iOS-style '
        'icons, but no file in lib/ or test/ refers to it. A search '
        'for the word Cupertino across both directories returns '
        'nothing. It is harmless dead weight from the generator, and '
        'a candidate for deletion.'),
    ...para('#',
        'The opposite check is as informative. There is no networking '
        'package other than http, no state package other than '
        'Riverpod, no code generator and no router. The app has two '
        'screens switched by a boolean, so it needs no routing '
        'package; its only persistence is two browser storages, so it '
        'needs no database. The short list is a sign of restraint.'),
    ...sec('the one edit that mattered'),
    ...code('ini', 'pubspec.yaml · the icon package after the fix', r'''
  lucide_icons_flutter: ^3.1.15'''),
    ...para('#',
        'The scaffold depended on lucide_icons ^0.257.0. Commit '
        '89a9c12 replaced it. Its message explains why: the old '
        'package, last published in 2023, subclassed Flutter’s '
        'IconData, which later stable releases made a final class; CI '
        'on Flutter stable 3.44.8 then failed with an error saying '
        'that IconData cannot be extended outside its library. The '
        'new package, lucide_icons_flutter, offers the same '
        'LucideIcons names and composes IconData instead of '
        'subclassing it. The change was a one-line edit here, a '
        'lockfile entry, and a changed import in 16 Dart files.'),
    ...para('#',
        'The lesson recorded in the commit is about unmaintained '
        'packages as a time bomb: a dependency can be perfectly '
        'correct on the day it is added and stop compiling when the '
        'SDK underneath it moves. It is also the reason a lock file '
        'is committed. pubspec.lock is tracked in git, so the app '
        'builds the same dependency versions every time, and the only '
        'thing allowed to drift between builds is the Flutter SDK '
        'itself.'),
    ...sec('dev dependencies and Flutter settings'),
    ...code('ini', 'pubspec.yaml · development and Flutter sections', r'''
dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^5.0.0
flutter:
  uses-material-design: true'''),
    ...para('#',
        'flutter_test supplies testWidgets and the matchers the tests '
        'use; flutter_lints is activated by analysis_options.yaml, '
        'which includes package:flutter_lints/flutter.yaml. '
        'uses-material-design bundles the Material icon font, and '
        'that is the whole flutter section: there are no assets and '
        'no custom fonts declared, which is consistent with the fonts '
        'being fetched at runtime and the icons coming from a '
        'package.'),
    ...sec('what a hiring manager might ask'),
    ...pt('#', 'why so few packages',
        'because each one is a future upgrade and a future break; the '
        'one break that happened (the icon package) came from the one '
        'package that was unmaintained.'),
    ...pt('#', 'where is the secret',
        'there is none. The manifest declares no environment '
        'configuration and no key handling package. The Mistral key '
        'is typed at runtime, held in memory, and optionally mirrored '
        'to sessionStorage through the two small files that import '
        'package:web.'),
    ...pt('#', 'where is the backend',
        'there is none in the Flutter package. The one server-side '
        'piece is the relay in worker/, which has its own '
        'configuration and no dependencies.'),
    ...sec('limits'),
    ...pt('#', 'the description and version are placeholders',
        'a reviewer reading the manifest sees default text, and the '
        'real description is in README.md.'),
    ...pt('#', 'caret ranges everywhere',
        'with a committed lock file the build is stable, but a pub '
        'upgrade will move everything within its range.'),
    ...pt('#', 'flutter_markdown is a single point of use',
        'every piece of AI-written prose passes through one file and '
        'one package, so a change of renderer would be a one-file '
        'job, and so would a security fix to link handling.'),
    blank,
    link('→ github.com/XNash/xyno-scholar', 'https://github.com/XNash/xyno-scholar'),
  ],
);
