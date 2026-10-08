import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-scholar/lib/widgets/output/narrow_topic_view.dart',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', 'narrow_topic_view.dart — the finished page for one worked-out topic'),
    cm('//', 'headline, pitch, level notes, actions, problématique, four tabs'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', 'renders a NarrowTopic: the deep-dive result and every refinement of it'),
    kv('language', 'Dart / Flutter, Riverpod ConsumerWidget'),
    kv('size', '153 lines'),
    kv('history', 'two commits: 7a200e7 (scaffold), 89a9c12 (icon package import)'),
    kv('inputs', 'topic, fieldsCovered and language, all passed in by OutputPanel'),
    ...sec('what it composes'),
    ...para('//',
        'This is where the data model from lib/models turns into a '
        'page. The order of elements down the column is the '
        'argument the page makes. First the title, then the pitch '
        '(what the topic is), then, only after a refine, a teal '
        'box saying what changed. Then the level notes (how it is '
        'calibrated to the chosen academic level), then two '
        'buttons, then the problématique callout (the single '
        'sentence to take away), and last a tabbed area holding '
        'the supporting material: intersection analysis, '
        'bibliography, outline, and the refine controls.'),
    ...code('dart', 'lib/widgets/output/narrow_topic_view.dart · the head of the page', r'''
        Text(topic.title, style: Theme.of(context).textTheme.displaySmall),
        const SizedBox(height: 12),
        MarkdownText(topic.pitch),
        const SizedBox(height: 10),
        if (topic.refinementSummary != null &&
            topic.refinementSummary!.trim().isNotEmpty)
          Container('''),
    ...para('//',
        'The refinement summary is conditional twice over: the '
        'field must be non-null and non-blank. The two guards cover '
        'a missing key (NarrowTopic.fromJson turns it into null) '
        'and an empty string. A refined topic thus announces itself '
        'with a short teal-tinted note, rendered as markdown, above '
        'the level notes.'),

    ...sec('the two actions and their colours'),
    ...code('dart', 'lib/widgets/output/narrow_topic_view.dart · Save to Notebook', r'''
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.success,
                foregroundColor: colors.successOn,
              ),
              onPressed: () async {
                await ref.read(notebookProvider.notifier).save(topic);
                if (context.mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text(s.savedToNotebook)));
                }
              },'''),
    ...para('//',
        'The Save button is green, and it is the only thing in the '
        'app that is green: a search for colors.success finds this '
        'one use. That is the colour system doing what '
        'app_colors.dart says, reserving one hue for one act. '
        'Every other control on the page is amber, teal or neutral. The handler awaits the provider’s write, then checks '
        'context.mounted before showing a snack bar saying the topic '
        'was saved. Each save adds a new entry, so pressing it twice '
        'keeps two copies (see notebook_entry.dart).'),
    ...code('dart', 'lib/widgets/output/narrow_topic_view.dart · Export BibTeX', r'''
            OutlinedButton.icon(
              onPressed: () => showBibtexExportDialog(
                context,
                entries: topic.starterBibliography,
                language: language,
                topicSlug: _slug.isEmpty ? 'xyno-scholar-topic' : _slug,
              ),'''),
    ...para('//',
        'Export BibTeX is outlined, a lower visual weight than Save; '
        'presumably the student is more likely to keep the topic than '
        'to export its three sources. Note where it sits: the button is '
        'in the page header, not in the Bibliography tab it relates '
        'to, so the action works whichever tab is showing.'),

    ...sec('the slug, and what it does to accents'),
    ...code('dart', 'lib/widgets/output/narrow_topic_view.dart · _slug', r'''
  String get _slug => topic.title
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\s-]'), '')
      .trim()
      .replaceAll(RegExp(r'\s+'), '-');'''),
    ...para('//',
        'The slug becomes the .bib file name. The pipeline lowercases, '
        'deletes everything that is not an ASCII letter, digit, '
        'space or hyphen, trims, and turns runs of whitespace into '
        'hyphens. Tracing it for a French title shows its limit: '
        'the regular expression deletes accented letters instead of '
        'transliterating them, so ‘Les vitraux de la cathédrale de '
        'Chartres’ becomes les-vitraux-de-la-cathdrale-de-chartres. '
        'In a French-first app that is a visible blemish in a '
        'file name. A title with no ASCII letters at all (Greek, '
        'say) produces an empty slug, which is what the fallback in '
        'the export call is for: ‘xyno-scholar-topic’. The slug is '
        'derived by reading the code; there is no test.'),

    ...sec('the tabs: a fixed height with nested scrolling'),
    ...code('dart', 'lib/widgets/output/narrow_topic_view.dart · the tab structure', r'''
        DefaultTabController(
          length: 4,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [
                  Tab(text: s.tabIntersection),
                  Tab(text: s.tabBibliography),
                  Tab(text: s.tabOutline),
                  Tab(text: s.tabRefine),
                ],
              ),
              SizedBox(
                height: 620,
                child: TabBarView('''),
    ...para('//',
        'Four tabs. My reading of the order: Intersection first, '
        'because the first question about a topic that is supposed to '
        'sit across several fields is whether it really does; then '
        'the sources; then the plan; then Refine, the tab that '
        'changes the topic, last. isScrollable with start alignment '
        'keeps the labels left-aligned and lets them scroll rather '
        'than squash on a narrow screen.'),
    blank,
    ...para('//',
        'TabBarView needs a bounded height, and the page it lives '
        'in is an unbounded scroll view, so the code gives it a '
        'fixed SizedBox of 620 pixels, with each tab’s content in its '
        'own SingleChildScrollView. The consequence is a scroll '
        'inside a scroll: a long bibliography scrolls within the tab '
        'while the page scrolls around it, and a short outline leaves '
        'blank space under it. 620 is a magic number that the code does '
        'not explain; it is tall enough for typical content, and '
        'I take it to be a compromise rather than a measurement.'),

    ...sec('language travels with the topic'),
    ...para('//',
        'The view takes language as a constructor argument and builds '
        'its own AppStrings from it, rather than reading the '
        'preference provider. OutputPanel passes response.language, '
        'the language the model reports having written in. The '
        'result is coherent for a single generation (a French topic '
        'gets French buttons and labels) but it means the FR/EN '
        'toggle does not restyle this page after the fact, and that '
        'a model which reports its language as, say, ‘French’ '
        'instead of ‘fr’ would get English chrome, because '
        'AppStrings tests exactly ‘fr’. Neither is exercised by a '
        'test.'),

    ...sec('what is tested'),
    ...para('//',
        'The view itself is untested; what it displays is the '
        'NarrowTopic parsed in test/mistral_client_test.dart. The '
        'slug, the conditional summary and the tab wiring are '
        'checked by using the app.'),

    ...sec('limits and what is next'),
    ...pt('//', 'accents vanish from file names',
        'transliterating é to e, or using a package for slugs, '
        'would keep names readable.'),
    ...pt('//', 'fixed 620 px tab area',
        'nested scrolling; an IndexedStack or a column of sections '
        'would avoid the fixed height.'),
    ...pt('//', 'export lives in the header',
        'a second entry point on the bibliography tab would put it '
        'next to what it exports.'),
    ...pt('//', 'language trusted from the reply',
        'the model’s self-reported language selects the interface '
        'strings.'),
    blank,
    link('→ github.com/XNash/xyno-scholar', 'https://github.com/XNash/xyno-scholar'),
  ],
);
