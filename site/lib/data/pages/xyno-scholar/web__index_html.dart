import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-scholar/web/index.html',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'index.html — the 38-line doorway into a Flutter app'),
    cm('//', r'a template with one placeholder that the deploy fills in'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'the HTML shell that loads the compiled Flutter app'),
    kv(r'language', r'HTML, 38 lines, the stock Flutter web template'),
    kv(r'history', r'1 commit: 7a200e7 (2026-08-06 09:41), never edited'),
    kv(r'placeholder', r'$FLUTTER_BASE_HREF, replaced by flutter build --base-href'),
    kv(r'served at', r'/xyno-scholar/ on GitHub Pages'),

    ...sec(r'why this file exists'),
    ...para('//',
        r'A Flutter web app draws everything itself on a canvas, so the '
        r'page around it is almost empty. This file is that page: a '
        r'head with a few tags and a body that holds one script. '
        r'flutter create generated it with the project, and the '
        r'scaffold commit added it unchanged. It is worth a page '
        r'because it is where an app that runs in a browser meets the '
        r'address it is served from, and because the lines it still '
        r'has from the template tell you what was never customised.'),

    ...sec(r'the base href'),
    ...code('html', r'web/index.html · lines 14-17', r'''
    This is a placeholder for base href that will be replaced by the value of
    the `--base-href` argument provided to `flutter build`.
  -->
  <base href="$FLUTTER_BASE_HREF">'''),
    ...para('//',
        r'The most important line in the file. The base tag tells the '
        r'browser what every relative URL in the page is relative to. '
        r'The app is not served from the root of a domain. GitHub '
        r'Pages puts a project at /<repository>/, so the files live '
        r'under /xyno-scholar/. Written as a literal, the '
        r'script would be looked up at /flutter_bootstrap.js and fail. '
        r'The file therefore holds a placeholder, and the build '
        r'swaps it:'),
    blank,
    ...code('yaml', r'.github/workflows/deploy.yml · line 33', r'''
        run: flutter build web --release --base-href "/xyno-scholar/"'''),
    ...para('//',
        r'The value in the workflow is a leading and trailing slash '
        r'around the repository name. The comment above the tag '
        r'says why: the path “has to start and end with a slash”. '
        r'That is also why running the app locally works with no '
        r'change: without the argument, Flutter fills in the default '
        r'root. The two files are a pair: if the repository was '
        r'renamed, the one line in deploy.yml would have to change '
        r'with it, and this file would not.'),
    blank,
    ...para('//',
        r'The same mechanism makes every other relative path in the '
        r'file work from the subpath: the manifest, the icons, the '
        r'favicon and the bootstrap script, none of them with a '
        r'leading slash.'),

    ...sec(r'the head'),
    ...code('html', r'web/index.html · lines 19-33', r'''
  <meta charset="UTF-8">
  <meta content="IE=Edge" http-equiv="X-UA-Compatible">
  <meta name="description" content="A new Flutter project.">

  <!-- iOS meta tags & icons -->
  <meta name="mobile-web-app-capable" content="yes">
  <meta name="apple-mobile-web-app-status-bar-style" content="black">
  <meta name="apple-mobile-web-app-title" content="xyno_scholar">
  <link rel="apple-touch-icon" href="icons/Icon-192.png">

  <!-- Favicon -->
  <link rel="icon" type="image/png" href="favicon.png"/>

  <title>xyno_scholar</title>
  <link rel="manifest" href="manifest.json">'''),
    ...para('//',
        r'Going through it:'),
    blank,
    ...pt('//', r'charset UTF-8',
        r'needed here more than for most apps, because the interface '
        r'and the content are in French by default (the preference '
        r'block starts with language fr), with accents everywhere.'),
    ...pt('//', r'X-UA-Compatible IE=Edge',
        r'a leftover from the days of Internet Explorer. It does '
        r'nothing in a modern browser, and Flutter web does not '
        r'support that browser.'),
    ...pt('//', r'the iOS tags',
        r'let the page be added to an iPhone home screen as an app: '
        r'a status bar style and the touch icon icons/Icon-192.png.'),
    ...pt('//', r'favicon and manifest',
        r'favicon.png, and manifest.json, which lists four icons, '
        r'two normal and two maskable, at 192 and 512 pixels. All of '
        r'those files are in the repository under web/.'),

    ...sec(r'the body'),
    ...code('html', r'web/index.html · lines 35-38', r'''
<body>
  <script src="flutter_bootstrap.js" async></script>
</body>
</html>'''),
    ...para('//',
        r'The whole body is a single script tag. flutter_bootstrap.js '
        r'is not in the repository: flutter build generates it, and it '
        r'loads the engine and the compiled app, then starts it. async '
        r'lets the browser carry on parsing while it downloads. '
        r'Nothing else needs to be here, because Flutter appends its '
        r'own element to the body when it starts.'),

    ...sec(r'what was never changed'),
    ...para('//',
        r'The file is the template, so three strings are still the '
        r'ones flutter create wrote from the project name: '
        r'the page title is xyno_scholar, the iOS app title is '
        r'xyno_scholar, and the description reads “A new Flutter '
        r'project.” The Dart side has the real name. lib/app.dart sets '
        r'the MaterialApp title to “Xyno Scholar”. As I understand '
        r'Flutter web, that title is applied to the document once '
        r'the app has started, so a person sees the nice name in '
        r'the tab. What still shows the underscored name is anything '
        r'that reads the HTML without running the app: a link '
        r'preview, a search result, the title during load, and the '
        r'name of an iPhone home-screen shortcut.'),
    blank,
    ...para('//',
        r'The same holds for web/manifest.json, written in the same '
        r'commit: its name and short_name are xyno_scholar, its '
        r'description is the same default sentence, and its '
        r'background and theme colour are #0175C2, the blue of the '
        r'Flutter template, not the app’s teal and parchment '
        r'palette. An installed copy would show that blue in its '
        r'splash and title bar.'),
    blank,
    ...pt('//', r'a missing lang attribute',
        r'the html tag has none, while the app’s default language is '
        r'French. It would matter to a screen reader or to translation '
        r'prompts in a browser, but the app is drawn on a canvas, '
        r'where those tools see very little anyway.'),
    ...pt('//', r'no viewport tag',
        r'there is no meta viewport in the file. I did not test '
        r'phones; Flutter may add what it needs itself at start-up.'),

    ...sec(r'what it is not'),
    ...para('//',
        r'It is not where the app’s logic, API key or styling '
        r'live. The key entry screen, the Mistral relay and the '
        r'sidebar are Dart. This is the one HTML file, and the '
        r'less it holds the better, because Flutter regenerates '
        r'its tooling around it on upgrades. A project that edits it '
        r'for a loading spinner or an analytics tag is signing up '
        r'to merge changes later; this one has not touched it.'),

    ...sec(r'how it is tested'),
    ...para('//',
        r'It is not tested by itself. The deploy workflow builds the '
        r'site on every push to main, and a wrong base href would '
        r'show as a blank page on GitHub Pages rather than as a '
        r'failed build. The test folder has no browser test. I '
        r'did not run the build here.'),

    ...sec(r'history'),
    ...pt('//', r'7a200e7, 2026-08-06 09:41',
        r'the scaffold commit created web/index.html with the rest of '
        r'the Flutter project. Nine minutes later cb25af9 (09:50) '
        r'added the GitHub Pages workflow whose --base-href '
        r'argument this file depends on. The page has not changed in '
        r'any of the nine commits since.'),
  ],
);
