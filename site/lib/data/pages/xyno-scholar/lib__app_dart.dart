import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-scholar/lib/app.dart',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', 'app.dart — the root widget and the lock that picks the screen'),
    cm('//', 'no router, no navigation calls: the API key decides what is shown'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', 'MaterialApp configuration plus the unlock-or-workbench switch'),
    kv('language', 'Dart / Flutter, Riverpod ConsumerWidget'),
    kv('size', '24 lines, one class'),
    kv('history', 'one commit (7a200e7, the scaffold); untouched through 8 later commits'),
    kv('tested by', 'test/widget_test.dart, for the locked branch only'),
    ...sec('why this file exists'),
    ...para('//',
        'Every Flutter app needs one widget that owns the '
        'MaterialApp: the theme, the title and the first screen. '
        'In this project that widget has a second job that makes it '
        'more interesting than its length suggests. The app is '
        'bring-your-own-key. It cannot do anything useful until the '
        'visitor has pasted a Mistral key, and it must go back to '
        'that state if the key is rejected. app.dart is where that '
        'rule is turned into a screen choice.'),
    ...code('dart', 'lib/app.dart · the whole widget', r'''
class XynoScholarApp extends ConsumerWidget {
  const XynoScholarApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final apiKeyState = ref.watch(apiKeyProvider);

    return MaterialApp(
      title: 'Xyno Scholar',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: apiKeyState.isUnlocked
          ? const HomeScreen()
          : const KeyEntryScreen(),
    );
  }
}'''),
    ...sec('state-derived routing instead of navigation'),
    ...para('//',
        'The decision is one ternary on the home property. There is '
        'no Navigator.push to move from the unlock screen to the '
        'workbench and no route table. The key provider is watched, '
        'so when its state changes this build runs again and the '
        'MaterialApp is handed the other screen. The screen is a '
        'function of the state, which is how Riverpod apps are '
        'meant to be written, and it has a useful side effect: '
        'there is no way to reach the workbench without a key, '
        'because the workbench widget is not in the tree until '
        'the state says so.'),
    ...para('//',
        'It also removes a class of bug. With imperative '
        'navigation, every place that clears the key must remember '
        'to pop back to the lock screen, and every place that sets '
        'it must remember to push. Here three different code paths '
        'change the key and none of them mentions a screen.'),
    ...sec('the three transitions, and who triggers them'),
    ...para('//',
        'The locked-to-unlocked edge is the unlock screen’s submit '
        'handler. It clears any old error message, then hands the '
        'trimmed key to the controller:'),
    ...code('dart', 'lib/screens/key_entry_screen.dart · unlocking', r'''
  void _submit() {
    final key = _controller.text.trim();
    if (key.isEmpty) return;
    ref.read(keyRejectedMessageProvider.notifier).state = null;
    ref
        .read(apiKeyProvider.notifier)
        .setKey(key, rememberForSession: _remember);
  }'''),
    ...para('//',
        'The first way back is voluntary. The workbench’s app bar '
        'has an icon button whose tooltip is the localised “Forget '
        'key” string:'),
    ...code('dart', 'lib/screens/home_screen.dart · forgetting', r'''
          IconButton(
            icon: const Icon(LucideIcons.logOut),
            tooltip: s.forgetKey,
            onPressed: () => ref.read(apiKeyProvider.notifier).forget(),
          ),'''),
    ...para('//',
        'The second way back is involuntary, and it is the one '
        'worth understanding. When Mistral answers 401 or 403, the '
        'client throws ApiKeyRejectedException. The generation '
        'controller catches it, records the exception message in a '
        'provider, and forgets the key. It never navigates:'),
    ...code('dart', 'lib/providers/generation_provider.dart · rejection', r'''
    } on ApiKeyRejectedException catch (e) {
      ref.read(keyRejectedMessageProvider.notifier).state = e.message;
      ref.read(apiKeyProvider.notifier).forget();
      state = state.copyWith(isLoading: false, clearError: true);'''),
    ...para('//',
        'Follow the chain from a bad key. The relay returns '
        'Mistral’s 401 unchanged. mistral_client.dart throws. The '
        'provider records the message and calls forget. The key '
        'state becomes empty. app.dart rebuilds, isUnlocked is '
        'false, and KeyEntryScreen appears. That screen reads the '
        'message provider only to learn whether to show the rose '
        'banner; the text it prints is its own localised string '
        's.keyRejected, not the exception’s English message. '
        'Several files cooperate, and the only one that mentions '
        'screens is this one.'),
    ...sec('isUnlocked is a computed property'),
    ...code('dart', 'lib/providers/api_key_provider.dart · the predicate', r'''
  bool get isUnlocked => key != null && key!.isNotEmpty;'''),
    ...para('//',
        'The gate checks for a non-empty key, not for a valid one. '
        'Nothing in the client verifies a key before it is used. '
        'The first request is the verification, and a failure of '
        'that request is what sends the visitor back. The choice '
        'keeps the app free of a separate “test my key” call, at '
        'the cost of one wasted generation attempt on a typo.'),
    ...sec('a lock screen is not a security boundary'),
    ...para('//',
        'It is worth being precise about what this gate protects. '
        'It decides whether the workbench is built. It does not '
        'encrypt anything. The only secret in the app is the '
        'visitor’s own key, which lives in memory and, if the box '
        'was ticked, in sessionStorage. The notebook is stored '
        'separately through shared_preferences under the key '
        'xyno_scholar_notebook_v1 and does not depend on the lock. '
        'Forgetting the key therefore does not clear saved topics, '
        'and it does not clear the last generation result held by '
        'the generation provider either: Riverpod providers are not '
        'reset when the screen changes. The README presents the app '
        'as private and single-user, and for that threat model '
        'this is consistent. For a shared computer it would not be '
        'enough.'),
    ...sec('what the MaterialApp does not configure'),
    ...para('//',
        'Four omissions are visible from the constructor call, '
        'and a search of lib/ confirms each is absent everywhere.'),
    ...pt('//', 'no dark theme',
        'only theme is set, from AppTheme.light(). There is no '
        'darkTheme or themeMode, and the colour class defines a '
        'single light palette. The warm parchment look is the '
        'design, not a default.'),
    ...pt('//', 'no locale',
        'the app is bilingual, French by default, but it does not '
        'use Flutter’s localisation system. Language is a field on '
        'the preference block, and screens build an AppStrings '
        'object from it. MaterialApp therefore has no locale and '
        'no localisation delegates, which means framework-supplied '
        'strings (for example the default tooltips of some '
        'Material widgets) are not translated. This is an '
        'inference from the missing configuration, not something I '
        'observed on screen.'),
    ...pt('//', 'no routes',
        'no named routes, no onGenerateRoute, and no screen is '
        'pushed by this file. Elsewhere the Navigator is used only '
        'by showDialog for the BibTeX export dialog and by the '
        'close buttons of that dialog and of the notebook drawer, '
        'which call Navigator.of(context).pop().'),
    ...pt('//', 'a title that the HTML disagrees with',
        'title is Xyno Scholar, but web/index.html still carries '
        'the generator’s title xyno_scholar and the description “A '
        'new Flutter project.”. On Flutter web the app title is '
        'normally what the browser tab shows once the app is '
        'running, so the HTML values matter mostly before start-up '
        'and in link previews. That behaviour is from my '
        'knowledge of Flutter, not from this repository.'),
    ...sec('why a ConsumerWidget and not a stateful one'),
    ...para('//',
        'The widget has no local state, no controllers to dispose '
        'and no lifecycle. Its only input is one provider. '
        'ConsumerWidget is the Riverpod equivalent of a stateless '
        'widget with a WidgetRef, which is exactly the right size. '
        'The unlock screen, by contrast, is a ConsumerStatefulWidget '
        'because it owns a text controller and two booleans, and '
        'that is the correct place for that state.'),
    ...para('//',
        'The widget also watches the whole key state rather than a '
        'selected field. The state has two fields, the key and the '
        'remember flag, so a rebuild when only the flag changes '
        'costs one MaterialApp rebuild. A select would be a '
        'premature optimisation.'),
    ...sec('how it is tested'),
    ...para('//',
        'test/widget_test.dart pumps this widget inside a '
        'ProviderScope and asserts that the French unlock title is '
        'on screen. That covers the locked branch on a fresh '
        'container. Nothing tests the other branch, or the switch '
        'in either direction, so the behaviour described above is '
        'established by reading the code and by the app having been '
        'deployed, not by a test. A ProviderScope with an '
        'overridden key provider would make both directions short '
        'tests.'),
    ...sec('limits and what is next'),
    ...pt('//', 'no transition',
        'the screens swap instantly. An AnimatedSwitcher around '
        'the home value would soften the jump, at the price of '
        'the ternary no longer being the whole story.'),
    ...pt('//', 'state survives a lock',
        'preferences, the last response and the notebook list '
        'remain in their providers after a key is forgotten. Scoping '
        'or invalidating them on forget() would match the intent '
        'of the Forget key button more closely.'),
    ...pt('//', 'only the light branch is defined',
        'adding a dark palette would mean a second AppColors '
        'value and a darkTheme argument here.'),
    blank,
    link('→ github.com/XNash/xyno-scholar', 'https://github.com/XNash/xyno-scholar'),
  ],
);
