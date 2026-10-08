import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-scholar/lib/widgets/output/output_panel.dart',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', 'output_panel.dart — one widget that decides what the right-hand side says'),
    cm('//', 'error, spinner, welcome, clarifying question, broad menu or narrow topic'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', 'the right-column switchboard: maps generation state to the widget to show'),
    kv('language', 'Dart / Flutter, Riverpod ConsumerWidget'),
    kv('size', '141 lines; OutputPanel, _ResponseContent, _EmptyState'),
    kv('history', 'four commits: 7a200e7, 89a9c12 (icon package), c1b3d71 (streaming text), ebafa0f (streaming removed)'),
    kv('reads', 'generationProvider (loading, error, response) and preferenceBlockProvider (language)'),
    ...sec('why it exists'),
    ...para('//',
        'Generation is asynchronous, can fail, can return a menu or a '
        'topic, and can come with a question. Rather than letting '
        'each child decide whether to show itself, one widget reads '
        'the state and chooses. That keeps BroadTopicsList and '
        'NarrowTopicView ignorant of loading and errors: they receive '
        'finished data and render it.'),

    ...sec('the top-level decision'),
    ...code('dart', 'lib/widgets/output/output_panel.dart · OutputPanel.build', r'''
        if (generation.error != null)
          StatusBanner(
            message: generation.error!,
            onDismiss: () => ref.read(generationProvider.notifier).clearError(),
          ),
        if (generation.isLoading && generation.response == null)
          Padding('''),
    ...code('dart', 'lib/widgets/output/output_panel.dart · the three-way choice', r'''
        else if (generation.response == null)
          _EmptyState(strings: s)
        else
          _ResponseContent(strings: s),'''),
    ...para('//',
        'Two independent things are happening. The error banner is '
        'an additive element above everything: it is a separate '
        'if, not part of the chain, so an error can appear over '
        'the previous results, the spinner or the welcome state. '
        'Below it is a mutually exclusive chain: loading with '
        'nothing yet, no response yet, or a response.'),
    blank,
    ...para('//',
        'The condition is generation.isLoading && generation.response '
        '== null. The spinner takes over the panel only on the very '
        'first generation. After a response exists, a new request '
        'leaves the old results on screen and shows progress in '
        'the places where the user pressed the button: the '
        'sidebar’s Generate button turns into a spinner (see '
        'sidebar.dart), and the Refine button shows its own (see '
        'refine_tab.dart). That is a deliberate-looking choice: '
        'the old topic remains readable and copyable while its '
        'replacement is thought about, at the price that nothing in '
        'the panel itself says that a refresh is under way.'),

    ...sec('what the loading text used to say'),
    ...para('//',
        'The spinner label today is s.generating, “Generating…”. For '
        'the 24 minutes between two commits on 2026-08-06 it said more. The streaming '
        'commit (c1b3d71, 10:28 UTC) changed this label to a '
        'conditional: the string “Connecting to Cerebras…” until the '
        'first chunk arrived, then “Receiving… N characters” with N '
        'counting up. It was wired the same way into the Generate '
        'button and the Refine button. Changing the provider to '
        'Gemini removed streaming (ebafa0f, 10:52 UTC) and with it '
        'the three conditionals, and the commit message describes '
        'the result as “a plain indeterminate spinner + static '
        'status text”. Nothing else in this file changed in either '
        'commit, which is a sign the panel was written so that its '
        'loading text is a swap-in string and not a structure.'),

    ...sec('the clarifying question, and why it is an additive banner'),
    ...code('dart', 'lib/widgets/output/output_panel.dart · _ResponseContent', r'''
        if (response.clarifyingQuestion != null &&
            response.clarifyingQuestion!.trim().isNotEmpty)
          Container(
            margin: const EdgeInsets.only(bottom: 18),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: colors.amber.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colors.amber.withValues(alpha: 0.4)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(LucideIcons.helpCircle, size: 18, color: colors.amber),
                const SizedBox(width: 10),
                Expanded(child: MarkdownText(response.clarifyingQuestion!)),'''),
    ...para('//',
        'This block is the UI half of rule 3 of the system prompt: '
        'when the user’s free text implies a field they did not '
        'select, the model must ask exactly one short question but '
        '“must STILL provide usable topic options in the same '
        'response. Never return a bare question with nothing else.” '
        'Because the question and the topics arrive together, the '
        'banner sits above the results rather than replacing them. '
        'The user sees a prompt in amber and a full set of cards '
        'below it, and can answer by adding the field in the sidebar '
        'and regenerating, or ignore it. The text is run through '
        'MarkdownText, since the question is a model-written prose '
        'field. The guard checks for null and for a blank string, '
        'presumably because a model with nothing to ask may return '
        'the empty string rather than null.'),

    ...sec('picking between broad and narrow'),
    ...para('//',
        'Below the banner, the same chain described on the '
        'generation_response.dart page chooses a view: the narrow '
        'topic if scope is narrow and the topic is present, else the '
        'broad list if non-empty, else the empty state. The narrow '
        'view receives response.language and response.fieldsCovered; '
        'the broad list reads the language from preferences. Which '
        'language a widget follows is thus not uniform: the narrow '
        'view and its dialog follow the response, everything else '
        'follows the toggle.'),

    ...sec('the empty state, used twice'),
    ...code('dart', 'lib/widgets/output/output_panel.dart · _EmptyState (excerpt)', r'''
            Icon(LucideIcons.compass, size: 44, color: colors.inkMuted),
            const SizedBox(height: 16),
            Text(
              strings.emptyStateTitle,
              style: Theme.of(context).textTheme.headlineMedium,
            ),'''),
    ...para('//',
        'A compass icon and “Ready to explore” appear before the '
        'first generation. The same widget is also the fallback when '
        'a response has neither a narrow topic nor any broad ones, '
        'so a valid-but-empty reply from the model is shown as the '
        'welcome state with no error. One more detail: the English '
        'body text says “Adjust your preferences on the left”, '
        'which is accurate on the wide layout and wrong on the '
        'stacked mobile layout below 900 px, where the sidebar is '
        'above the panel.'),

    ...sec('what is tested'),
    ...para('//',
        'Nothing in test/ pumps this widget. The state machine, the '
        'clarifying banner and the fallback to the empty state are '
        'verified by running the app against the real model. The '
        'model classes it consumes are covered by the client tests '
        '(broad, narrow, refine), so the data side is pinned and '
        'the presentation is not.'),

    ...sec('limits and what is next'),
    ...pt('//', 'no busy indicator over stale results',
        'during a second generation the panel gives no sign of '
        'work; a thin progress bar at the top would.'),
    ...pt('//', 'silent empty replies',
        'an empty valid response renders the welcome state without '
        'a message.'),
    ...pt('//', 'mixed language sources',
        'some children follow response.language and others follow '
        'the toggle.'),
    ...pt('//', 'English-only errors',
        'the banner prints whatever message the controller set, in '
        'English.'),
    blank,
    link('→ github.com/XNash/xyno-scholar', 'https://github.com/XNash/xyno-scholar'),
  ],
);
