import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-scholar/lib/widgets/sidebar/sidebar.dart',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', 'sidebar.dart — the dock that holds the form'),
    cm('//', 'five cards, one pinned action bar, one button with no arguments'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', 'left-hand dock: the five preference cards plus the Generate button'),
    kv('language', 'Dart / Flutter, ConsumerWidget'),
    kv('size', '81 lines'),
    kv('history', '4 commits, all on 2026-08-06: 7a200e7, 89a9c12, c1b3d71, ebafa0f'),
    kv('reads', 'preferenceBlockProvider (language only), generationProvider (loading flag)'),
    kv('writes', 'nothing itself; calls generationProvider.notifier.generate()'),
    ...sec('why this file exists'),
    ...para('//',
        'The left column of Xyno Scholar is a form, and a form needs a '
        'frame: something that decides the order of the controls, '
        'keeps them reachable, and owns the single action that turns '
        'them into a request. That is all this file does. It holds no '
        'state of its own and builds no control itself; the controls '
        'are five separate card widgets in the same directory '
        '(field_selector_card, excluded_fields_card, '
        'level_selector_card, scope_tone_mood_card and '
        'free_text_panel_card), all sitting on the shared '
        'sidebar_card.dart shell.'),
    ...para('//',
        'The doc comment on the class states the intent in one '
        'sentence: a docked, fixed-width left sidebar containing every '
        'preference panel, each kept as its own visually distinct '
        'card, plus the generate action. “Fixed-width” is a promise '
        'this file does not keep by itself; the width is imposed by '
        'its parent, lib/screens/home_screen.dart (420 px on a wide '
        'screen), and this file simply fills what it is given.'),

    ...sec('the five cards, in a fixed order'),
    ...code('dart', 'lib/widgets/sidebar/sidebar.dart · the scroll region (trimmed)', r'''
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FieldSelectorCard(),
                  SizedBox(height: 16),
                  ExcludedFieldsCard(),
                  SizedBox(height: 16),
                  LevelSelectorCard(),
                  SizedBox(height: 16),
                  ScopeToneMoodCard(),
                  SizedBox(height: 16),
                  FreeTextPanelCard(),
                ],
              ),
            ),
          ),'''),
    ...para('//',
        'The order reads like a sentence: which disciplines to '
        'combine, which themes to keep out, how demanding the result '
        'should be, what kind of answer and in what voice, and last '
        'any specific angle. The code does not explain the order, so '
        'this is a reading rather than a recorded decision. One thing '
        'the order does imply is that the free-text box, the only '
        'optional input (its title in strings.dart ends with '
        '“(optionnel)” / “(optional)”), sits at the bottom, below '
        'everything that has a default.'),
    ...para('//',
        'That matters because of the defaults in '
        'lib/models/preference_block.dart: History, Catholic theology '
        'and Art history, licence level, neutral tone, broad scope, '
        'curious mood, French. Every card starts in a valid state, so '
        'pressing Generate without touching anything is a legal '
        'request. Nothing in this file validates the form, because '
        'nothing in the form can be invalid: the one rule that could '
        'be broken, “at least one field”, is refused earlier, by the '
        'controller in preference_providers.dart, and surfaced as a '
        'hint in the field card.'),
    ...pt('//', 'spacing is the dock’s job',
        'SidebarCard sets no margin (the app theme gives Card a zero '
        'margin), so the 16 px gaps between cards are the '
        'SizedBox(height: 16) spacers here. Changing the rhythm of '
        'the whole column is a one-file edit.'),
    ...pt('//', 'the Column is const',
        'all five cards have const constructors, so the whole '
        'subtree is a compile-time constant. When Sidebar rebuilds '
        '(it watches two providers) Flutter meets identical widget '
        'instances and does not rebuild the cards; each card watches '
        'the preference provider on its own. That is general Flutter '
        'behaviour; the code does not comment on it, so I read the '
        'const as deliberate rather than certain.'),

    ...sec('one scroll region, one pinned bar'),
    ...code('dart', 'lib/widgets/sidebar/sidebar.dart · the action bar (trimmed)', r'''
          Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            decoration: BoxDecoration(
              color: colors.parchment,
              border: Border(top: BorderSide(color: colors.border)),
            ),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon('''),
    ...para('//',
        'The bar is the second child of the outer Column, after an '
        'Expanded scroll view, so it takes its natural height at the '
        'bottom and the scroll area takes everything else. The '
        'practical reason is visible in the catalog: the field card '
        'alone can list 22 fields in five categories (see '
        'lib/models/field_catalog.dart), and the free-text card adds '
        'suggestions and four example chips. Without a pinned bar the '
        'user would have to scroll to the end of the form to find '
        'the one button that matters.'),
    ...para('//',
        'The bar has the same parchment fill as the column and the '
        'page behind it, and is separated only by a one pixel top '
        'border in the theme’s border colour. The scrolling cards '
        'are clipped at that hairline; there is no shadow, and the '
        'app theme sets card elevation to 0. Padding is 20 px on the '
        'sides to line up with the cards above, 12 px on top and '
        '20 px below.'),

    ...sec('the button'),
    ...code('dart', 'lib/widgets/sidebar/sidebar.dart · onPressed, icon and label', r'''
                onPressed: generation.isLoading
                    ? null
                    : () => ref.read(generationProvider.notifier).generate(),
                icon: generation.isLoading
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colors.amberOn,
                        ),
                      )
                    : const Icon(LucideIcons.sparkles, size: 18),
                label: Text(
                  generation.isLoading ? s.generating : s.generateButton,
                ),'''),
    ...para('//',
        'Three things about this button are deliberate and worth '
        'noticing. First, the call has no arguments. generate() on '
        'the controller (lib/providers/generation_provider.dart) '
        'reads the preference block, the free text and the API key '
        'from their providers itself. The sidebar never gathers '
        'values from the cards, and the cards never hand anything '
        'upward: the form is state, not a set of callbacks, so the '
        'same call could be made from anywhere else in the app.'),
    ...para('//',
        'Second, the button disables itself by setting onPressed to '
        'null while a request is in flight, which Material then '
        'draws in its disabled style. That makes a double submit '
        'impossible from this entry point without any extra guard '
        'in the controller. Third, the spinner is drawn in amberOn, '
        'the foreground colour for text on amber. The theme '
        '(app_theme.dart) paints every ElevatedButton amber with an '
        'amberOn foreground, and the palette comment in '
        'app_colors.dart names amber the “warm accent — primary '
        'actions”, so the spinner stays legible against the same '
        'fill the label uses. This is the only filled amber button in '
        'the sidebar, which reads as “this is the action; the cards '
        'are only inputs”.'),
    ...para('//',
        'The strings come from AppStrings, built from '
        'prefs.language, so the label is “Générer des sujets” or '
        '“Generate topics” and, while busy, “Génération en cours…” or '
        '“Generating…”. That is why the file watches the preference '
        'block at all: the only field it reads from it is language.'),

    ...sec('a label added and removed within 25 minutes'),
    ...para('//',
        'This file has a short history and part of it is a small '
        'lesson in coupling. The scaffold commit 7a200e7 '
        '(2026-08-06 09:41 UTC) shipped the static label shown '
        'above. At 10:28 UTC commit c1b3d71, “Switch Cerebras '
        'integration to zai-glm-4.7 with streaming”, replaced it '
        'with a live counter: its message says the loading states in '
        'the output panel, the sidebar generate button and the refine '
        'button “now show a live ‘Receiving… N characters’ '
        'indicator instead of a static label”, driven by a '
        'streamedChars field on the generation state. At 10:52 UTC '
        'commit ebafa0f, “Replace Cerebras integration with Google '
        'Gemini”, removed it again; its message says it dropped the '
        'SSE and streaming-chunk code entirely and that the loading '
        'states are “back to a plain indeterminate spinner + static '
        'status text”.'),
    ...para('//',
        'After that the file never changed again. The later commits '
        'that swapped Gemini for Mistral behind a Cloudflare Worker '
        'relay (98e7e48 at 12:19 UTC, b3d2b1c at 12:54 UTC) did not '
        'touch the sidebar. That is the useful result: the parts of '
        'the UI that depended only on generic state (isLoading) '
        'survived three different backends in under three hours '
        '(Cerebras, Gemini, Mistral), and the only piece that depended on a backend '
        'detail (a streamed character count) was the piece that had '
        'to be deleted. The commit between them, 89a9c12, is '
        'unrelated to behaviour: it changed one import line, from '
        'package:lucide_icons to package:lucide_icons_flutter, '
        'because the old package subclassed an IconData class that '
        'newer Flutter made final and broke the web build in CI.'),

    ...sec('what the sidebar watches, and what that costs'),
    ...code('dart', 'lib/widgets/sidebar/sidebar.dart · build()', r'''
    final prefs = ref.watch(preferenceBlockProvider);
    final generation = ref.watch(generationProvider);
    final colors = context.colors;
    final s = AppStrings(prefs.language);'''),
    ...para('//',
        'Both watches are coarse. The sidebar frame rebuilds on every '
        'chip tap (any field of the block changes the object) and '
        'again when a response arrives, although it needs only the '
        'language string and one boolean. Because the five cards are '
        'const, the rebuild is the Column, the bar and the button: '
        'cheap. A select() on language and isLoading would be more '
        'precise; nothing suggests it has mattered, and I would not '
        'call this a defect, only a place where the code is simpler '
        'than it could be.'),
    ...para('//',
        'There is one behaviour here that is easy to miss. isLoading '
        'is set for refinements as well as for generation: the '
        'refine method in the controller sets isLoading and '
        'isRefining together. This file reads only isLoading, so '
        'while a refinement runs the Generate button also shows its '
        'spinner and “Generating…”. The Refine tab '
        '(lib/widgets/output/tabs/refine_tab.dart) reads both flags '
        'and shows its spinner only when both are true. Two buttons, '
        'one shared flag, two readings: the effect is that neither '
        'entry point can start a request while the other is running, '
        'and that only the button the user actually pressed '
        'explains itself.'),

    ...sec('where the dock sits'),
    ...para('//',
        'On a screen at least 900 px wide, home_screen.dart gives '
        'the Sidebar a 420 px column with a right border, beside the '
        'output panel. Below 900 px it becomes a SizedBox of height '
        '640 at the top of a single scrolling page, with the output '
        'panel beneath it; the scroll region and the pinned bar then '
        'live inside that 640 px box. Those two numbers are '
        'constants in the screen file, not here, and the '
        'home_screen page covers them. One consequence belongs to '
        'this page: a search of lib/ finds no ensureVisible, '
        'animateTo or ScrollController, so on a narrow screen a '
        'finished generation appears below the dock without the page '
        'scrolling to it.'),

    ...sec('what is tested'),
    ...para('//',
        'Nothing in test/ builds the sidebar. The only widget test, '
        'test/widget_test.dart, pumps the app and checks that the '
        'unlock screen shows the French sentence “Entrez votre clé '
        'API Mistral”, so it never reaches this widget. The '
        'behaviour here is exercised only by hand.'),

    ...sec('limits and what is next'),
    ...pt('//', 'a magic height on mobile',
        'the 640 px box is a guess that fits typical phones; a '
        'LayoutBuilder or a bottom sheet would adapt.'),
    ...pt('//', 'no scroll to results',
        'on a narrow screen the user must find the output '
        'themselves.'),
    ...pt('//', 'coarse watches',
        'a select on two values would stop needless frame '
        'rebuilds.'),
    ...pt('//', 'one flag, two meanings',
        'a loading spinner on Generate during a refine is accurate '
        'about “busy” and misleading about “what”.'),
    ...pt('//', 'no test',
        'a widget test that taps the button with a fake '
        'MistralClient would pin the disable-while-loading '
        'behaviour.'),
    blank,
    link('→ github.com/XNash/xyno-scholar', 'https://github.com/XNash/xyno-scholar'),
  ],
);
