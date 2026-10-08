import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-scholar/lib/screens/home_screen.dart',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', 'home_screen.dart — the workbench: controls on the left, results on the right'),
    cm('//', 'one Scaffold, one breakpoint, and the places the key and the language live'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', 'main screen after unlock: app bar, preference sidebar, output panel, notebook drawer'),
    kv('language', 'Dart / Flutter, Riverpod ConsumerWidget'),
    kv('size', '135 lines'),
    kv('history', 'two commits: 7a200e7 (scaffold), 89a9c12 (icon package swap, one import line)'),
    kv('breakpoint', '900 px; sidebar fixed at 420 px; output capped at 1080 px'),
    ...sec('why this screen is shaped this way'),
    ...para('//',
        'The app has one job: take a set of preferences, produce '
        'output, let the student iterate. That suggests a two-pane '
        'layout where the controls never leave the screen, so that '
        'changing one setting and pressing Generate again is a '
        'single glance and a single click. The Sidebar widget '
        '(sidebar.dart) owns the controls and their Generate button; '
        'OutputPanel (output_panel.dart) owns everything that comes '
        'back. HomeScreen does almost nothing except decide where '
        'they sit and what surrounds them.'),

    ...sec('the app bar: logo, language, notebook, forget key'),
    ...code('dart', 'lib/screens/home_screen.dart · the actions', r'''
        actions: [
          _LanguageToggle(currentLanguage: prefs.language),
          const SizedBox(width: 8),
          Builder(
            builder: (context) => IconButton(
              icon: const Icon(LucideIcons.bookMarked),
              tooltip: s.notebookTitle,
              onPressed: () => Scaffold.of(context).openEndDrawer(),
            ),
          ),
          IconButton(
            icon: const Icon(LucideIcons.logOut),
            tooltip: s.forgetKey,
            onPressed: () => ref.read(apiKeyProvider.notifier).forget(),
          ),'''),
    ...para('//',
        'Three controls and each has a reason. The language toggle is '
        'here and nowhere else (the unlock screen has none). The '
        'notebook button opens the end drawer; it is wrapped in a '
        'Builder because HomeScreen.build creates the Scaffold, so '
        'the context it has is above the Scaffold and '
        'Scaffold.of(context) would not find it. The Builder '
        'hands the button a context that is below. And the log-out icon, '
        'tooltipped with the “Forget key” string, calls '
        'apiKeyProvider.notifier.forget(), which clears the key and '
        'any sessionStorage copy. Nothing navigates: state changes, '
        'app.dart rebuilds, and the unlock screen replaces this one.'),
    ...para('//',
        'Tooltips carry the icon-only buttons’ meaning, and they are '
        'localised, because they come from AppStrings. The notebook '
        'and key icons are the only two interactive things in the bar '
        'besides the language toggle, so there is no overflow menu.'),

    ...sec('one breakpoint, two layouts'),
    ...code('dart', 'lib/screens/home_screen.dart · constants', r'''
const _mobileBreakpoint = 900.0;
const _sidebarWidth = 420.0;'''),
    ...para('//',
        'The body is a LayoutBuilder that compares the available '
        'width (not the device size) with 900. Below it, the page '
        'becomes a single scrolling column; at or above it, a row.'),
    ...code('dart', 'lib/screens/home_screen.dart · wide layout', r'''
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: _sidebarWidth,
                decoration: BoxDecoration(
                  border: Border(right: BorderSide(color: colors.border)),
                ),
                child: const Sidebar(),
              ),
              Expanded(
                child: SingleChildScrollView('''),
    ...para('//',
        'In the wide layout the two panes scroll independently: '
        'the Sidebar has its own internal scroll view with a pinned '
        'Generate bar (see sidebar.dart), and the right-hand '
        'SingleChildScrollView scrolls the results. The output is '
        'centred in a ConstrainedBox capped at 1080 px so long '
        'lines of prose stay at a readable measure on a large '
        'monitor. A 420 px fixed sidebar is generous for chip '
        'rows and level descriptions; at the 900 px breakpoint it '
        'leaves 480 px for the output, less 32 px of padding on '
        'each side.'),
    ...code('dart', 'lib/screens/home_screen.dart · narrow layout', r'''
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(height: 640, child: const Sidebar()),
                  Container(height: 1, color: colors.border),'''),
    ...para('//',
        'The narrow layout stacks the same two widgets. The honest '
        'part is the 640: the sidebar is given a fixed height of '
        '640 logical pixels, presumably so it can keep its '
        'scrollable list and its docked Generate button inside a '
        'parent that is itself a scroll view, which would otherwise '
        'hand it unbounded height. The cost is a scroll inside a scroll on a phone: '
        'the page scrolls, and so does the boxed sidebar. And the '
        'output panel sits below it, so after pressing Generate a '
        'phone user has to scroll down to see anything arrive. '
        'There is no auto-scroll to the results.'),

    ...sec('the language toggle'),
    ...code('dart', 'lib/screens/home_screen.dart · _LanguageToggle', r'''
    return SegmentedButton<String>(
      segments: const [
        ButtonSegment(value: 'fr', label: Text('FR')),
        ButtonSegment(value: 'en', label: Text('EN')),
      ],
      selected: {currentLanguage},
      showSelectedIcon: false,
      onSelectionChanged: (selection) => ref
          .read(preferenceBlockProvider.notifier)
          .setLanguage(selection.first),'''),
    ...para('//',
        'The labels are the language codes, not translated words, '
        'which is the right call for a language switch: it must be '
        'readable by someone who does not read the current language. '
        'The code ‘fr’ or ‘en’ is stored in PreferenceBlock.language, '
        'so it is also the language the next generation request '
        'asks the model to write in (rule 7 of the system prompt). '
        'The selected segment is tinted with the same teal at 16 per '
        'cent alpha as the scope control in the sidebar, set in the '
        'widget’s own ButtonStyle because the theme has no '
        'segmentedButtonTheme.'),
    blank,
    ...para('//',
        'What the toggle changes and what it does not: it changes '
        'the sidebar, the app bar, the notebook drawer and the '
        'broad-topic cards immediately, because those read '
        'prefs.language. It does not re-translate content already '
        'generated. A generated narrow topic keeps its own '
        'language, because NarrowTopicView takes the language from '
        'the response (response.language), so its buttons and tab '
        'labels stay in the language the topic was written in until the '
        'student generates again.'),

    ...sec('the notebook drawer and the screen as a state machine'),
    ...para('//',
        'HomeScreen declares endDrawer: const NotebookDrawer(), and '
        'that is the whole integration; the drawer reads its own '
        'provider (see notebook_drawer.dart). The screen watches only '
        'preferenceBlockProvider, for the language and nothing '
        'else, so a generation finishing does not rebuild it; '
        'the Sidebar and OutputPanel watch generationProvider '
        'themselves. That separation is the reason the file can '
        'stay at 135 lines: it holds layout, not state.'),

    ...sec('what is tested'),
    ...para('//',
        'Nothing in test/ pumps HomeScreen. The single widget test '
        'stops at the unlock screen. The breakpoint, the Builder '
        'trick, the 640 px box and the language toggle are all '
        'verified only by running the app.'),

    ...sec('limits and what is next'),
    ...pt('//', 'fixed 640 px sidebar on mobile',
        'a nested scroll and a hard-coded height; a bottom sheet or '
        'tabs would suit a phone better.'),
    ...pt('//', 'no scroll to results',
        'on the stacked layout a finished generation appears below '
        'the fold.'),
    ...pt('//', 'one breakpoint',
        'there is no tablet-specific layout between 900 and the '
        'wide view.'),
    ...pt('//', 'toggle does not translate output',
        'existing topics stay in their original language by design '
        'or by omission; the code does not say which.'),
    blank,
    link('→ github.com/XNash/xyno-scholar', 'https://github.com/XNash/xyno-scholar'),
  ],
);
