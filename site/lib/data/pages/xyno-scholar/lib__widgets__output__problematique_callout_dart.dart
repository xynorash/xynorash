import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-scholar/lib/widgets/output/problematique_callout.dart',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', 'problematique_callout.dart — the one dark block on a cream page'),
    cm('//', 'the research question, set as a pull quote with a copy button'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', 'displays NarrowTopic.problematique prominently and lets the student copy it'),
    kv('language', 'Dart / Flutter, Riverpod ConsumerWidget (ref unused)'),
    kv('size', '64 lines'),
    kv('history', 'two commits: 7a200e7 (scaffold), 89a9c12 (icon package import)'),
    kv('inputs', 'problematique (plain text) and language'),
    ...sec('why it gets its own widget'),
    ...para('//',
        'A problématique is the central research question of a '
        'piece of academic work: the tension the whole argument is '
        'built to resolve. The system prompt names it in its rule for '
        'the memoire level: “focused methodology built around one '
        'precise, tractable problématique”, and the narrow schema '
        'has a field for it. If a student leaves the app with one '
        'sentence, it is plausibly this one. The callout '
        'exists so that the sentence is impossible to miss on the '
        'page, and easy to take away.'),

    ...sec('the only inverted block in the UI'),
    ...code('dart', 'lib/widgets/output/problematique_callout.dart · the container and the text', r'''
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: colors.ink,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            problematique,
            style: AppTypography.serif(
              style: FontStyle.italic,
              weight: FontWeight.w500,
              fontSize: 19,
              color: colors.parchment,
            ).copyWith(height: 1.5),
          ),'''),
    ...para('//',
        'Everything else on the page is dark text on a light '
        'surface. Here the background is the ink colour itself and '
        'the text is parchment. That inversion is the whole '
        'trick: with no new colour added, the block stands out '
        'against the rest of the output. The type is Fraunces '
        'italic at weight 500 and 19 px with a 1.5 line height, '
        'which the typography file describes as the style of “the '
        'problématique quote” (see app_typography.dart). The padding '
        'is 22, larger than the 14 to 18 px used on most cards, and '
        'the radius 12 matches the cards. Parchment on ink works out '
        'at 13.2 to 1 contrast by my calculation from the hex values, '
        'the same figure as the body text on the page.'),
    ...para('//',
        'The text is a plain Text, not MarkdownText. A question '
        'rendered through markdown could acquire emphasis the '
        'model did not mean, and the prompt’s formatting rules do not '
        'list the problématique among the prose fields that may use '
        'markdown. A model that includes asterisks anyway would show '
        'them.'),

    ...sec('copy, with an acknowledgement'),
    ...code('dart', 'lib/widgets/output/problematique_callout.dart · the copy action', r'''
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: colors.parchment),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: problematique));
                if (context.mounted) {'''),
    ...para('//',
        'The button is a TextButton whose foreground is overridden '
        'to parchment, because the theme’s text buttons are teal '
        'and teal on near-black would be about 2 to 1 by my '
        'calculation, too dim to read. It is right-aligned '
        'under the quote, like the Deep Dive button on the broad cards. '
        'The handler awaits Clipboard.setData and then, guarded by '
        'context.mounted, shows a snack bar with s.copied: “Copied to '
        'clipboard.” The same guard-and-snackbar shape appears in the '
        'BibTeX dialog and the Save button.'),
    ...para('//',
        'The label comes from AppStrings(language): “Copier la '
        'problématique” or “Copy problématique”. The English keeps the '
        'French word, which the whole app does for this term.'),

    ...sec('small code smell: a ConsumerWidget that never reads ref'),
    ...para('//',
        'The class extends ConsumerWidget and takes a WidgetRef in '
        'build, but it never uses it. A plain StatelessWidget '
        'would do, and the import of flutter_riverpod exists only for '
        'the base class. It is harmless, a sign the file was '
        'written from a template, and the one place in the widget '
        'directory where the base class is heavier than the code '
        'needs. Because the language arrives as a constructor '
        'argument rather than from a provider, the widget is also '
        'testable without a ProviderScope once that is changed.'),

    ...sec('what is tested'),
    ...para('//',
        'No test covers the callout. Its input is NarrowTopic.problematique, '
        'which the narrow and refine tests assert in a mock ('
        '‘A problematique.’ and ‘A refined problematique.’) only as '
        'parsed strings.'),

    ...sec('limits and what is next'),
    ...pt('//', 'long questions',
        'there is no maximum height or line limit; a model that '
        'returns a paragraph would fill the block.'),
    ...pt('//', 'copy only',
        'no way to edit the question or to add it to the notebook '
        'separately from the whole topic.'),
    ...pt('//', 'unused ref',
        'StatelessWidget would be the honest base class.'),
    blank,
    link('→ github.com/XNash/xyno-scholar', 'https://github.com/XNash/xyno-scholar'),
  ],
);
