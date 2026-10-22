import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-scholar/lib/widgets/output/tabs/bibliography_tab.dart',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'bibliography_tab.dart — three books, each one a search away'),
    cm('//', r'cards for the starter reading list, with links that search, not link'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'second tab of a narrow topic: the starter bibliography'),
    kv(r'language', r'Dart / Flutter, a stateless widget and a private button'),
    kv(r'size', r'148 lines, 2 commits'),
    kv(r'input', r'List of BibliographyEntry and a language code, nothing else'),
    kv(r'outputs', r'one card per entry; three outbound searches per card'),
    kv(r'history', r'7a200e7 (2026-08-06 09:41), 89a9c12 (09:58)'),

    ...sec(r'why this file exists'),
    ...para('//',
        r'A research topic is only useful if you can start reading. The '
        r'model is asked for a starter bibliography with every narrow '
        r'topic: mistral_client.dart’s refine instruction even states '
        r'the shape, “exactly 3 starterBibliography entries”. This '
        r'widget is where those entries become something you can '
        r'act on. It turns each one into a card and gives it three '
        r'ways out, Google Scholar, JSTOR and WorldCat.'),
    blank,
    ...para('//',
        r'The interesting decision is in the first twelve lines. The '
        r'links are not links to the works. They are searches.'),

    ...sec(r'the three search links'),
    ...code('dart', r'lib/widgets/output/tabs/bibliography_tab.dart · lines 9-19', r'''
Uri _googleScholarUri(BibliographyEntry e) => Uri.https(
  'scholar.google.com',
  '/scholar',
  {'q': '${e.authors} ${e.title}'},
);

Uri _jstorUri(BibliographyEntry e) =>
    Uri.https('www.jstor.org', '/action/doBasicSearch', {'Query': e.title});

Uri _worldcatUri(BibliographyEntry e) =>
    Uri.https('search.worldcat.org', '/search', {'q': e.title});'''),
    ...para('//',
        r'Each function builds a URL to a search results page. Google '
        r'Scholar gets the authors and the title joined by a space, '
        r'which narrows a common title to the right author. JSTOR and '
        r'WorldCat get the title alone. Uri.https takes the query as a '
        r'map and percent-encodes it, so accents, quotes and '
        r'ampersands in a French title cannot break the address. That '
        r'is the reason to use the constructor rather than gluing a '
        r'string together.'),
    blank,
    ...para('//',
        r'Why search rather than link? The file does not say, so this is '
        r'my reading. The entries come from a language model, and a '
        r'model can produce a plausible reference that does not exist, or '
        r'get a year or a publisher wrong. A direct link would claim the '
        r'work exists. A search link claims only that this is worth '
        r'looking up, and lets the three catalogues answer. It also '
        r'needs no URL from the model, which the model could invent.'),
    blank,
    ...para('//',
        r'Notice what is left out. The year and the publication are not '
        r'in any query. That is probably deliberate, since a wrong year '
        r'would hide the right result, but nothing in the code '
        r'records the reason.'),

    ...sec(r'the type label'),
    ...code('dart', r'lib/widgets/output/tabs/bibliography_tab.dart · lines 21-29', r'''
String _typeLabel(String type, String language) {
  final fr = language == 'fr';
  return switch (type) {
    'book' => fr ? 'Livre' : 'Book',
    'article' => fr ? 'Article' : 'Article',
    'primary_source' => fr ? 'Source primaire' : 'Primary source',
    _ => type,
  };
}'''),
    ...para('//',
        r'The model is told to answer with one of three type strings. The '
        r'comment in the model class lists them: book, article, '
        r'primary_source. The switch translates them for the chip. Two '
        r'details. The fallback arm, _ => type, shows an unknown value '
        r'as it came, so a model that invents a fourth type produces an '
        r'ugly chip, not a crash. And the article line has a ternary '
        r'whose two branches are the same word, which is correct '
        r'(article is the same in both languages) but reads like a '
        r'leftover; a plain string would say the same thing. The model '
        r'class also defaults a missing type to book, so a response '
        r'with no type gets a Book chip.'),

    ...sec(r'the widget'),
    ...code('dart', r'lib/widgets/output/tabs/bibliography_tab.dart · lines 61-91', r'''
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        entry.title,
                        style: AppTypography.serif(
                          fontSize: 16,
                          color: colors.ink,
                        ),
                      ),
                    ),
                    Chip(
                      label: Text(
                        _typeLabel(entry.type, language),
                        style: const TextStyle(fontSize: 11),
                      ),
                      backgroundColor: colors.amber.withValues(alpha: 0.14),
                      side: BorderSide(
                        color: colors.amber.withValues(alpha: 0.4),
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${entry.authors} · ${entry.year} · ${entry.publication}',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: colors.inkMuted),
                ),'''),
    ...para('//',
        r'A card is a column. The top row has the title in the serif '
        r'face at 16 pixels, which gives it the feel of a book spine, '
        r'and an amber chip with the type on the right. The title sits '
        r'in an Expanded so a long title wraps instead of pushing the '
        r'chip off the card. Under it, one muted line holds '
        r'authors, year and publication, separated by middle dots. The '
        r'card’s own container, with the raised surface colour, the '
        r'10-pixel radius and the border, is built a few lines above.'),
    blank,
    ...code('dart', r'lib/widgets/output/tabs/bibliography_tab.dart · lines 92-115', r'''
                const SizedBox(height: 10),
                MarkdownText(entry.relevance),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _LinkButton(
                      label: 'Google Scholar',
                      icon: LucideIcons.graduationCap,
                      uri: _googleScholarUri(entry),
                    ),
                    _LinkButton(
                      label: 'JSTOR',
                      icon: LucideIcons.library,
                      uri: _jstorUri(entry),
                    ),
                    _LinkButton(
                      label: 'WorldCat',
                      icon: LucideIcons.archive,
                      uri: _worldcatUri(entry),
                    ),
                  ],
                ),'''),
    ...para('//',
        r'The relevance line, the sentence that says why this book '
        r'belongs on this topic, goes through MarkdownText. That is the '
        r'shared renderer for every generated prose field (its own '
        r'doc comment lists relevance among them), so bold and italics '
        r'in a model answer render properly. The buttons are in a Wrap '
        r'so that on a narrow screen the third drops to a second line. '
        r'The button labels are plain strings, not in l10n/strings.dart: '
        r'they are proper names, the same in both languages.'),

    ...sec(r'the button, and where it goes'),
    ...code('dart', r'lib/widgets/output/tabs/bibliography_tab.dart · lines 136-147', r'''
  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: () => launchUrl(uri, mode: LaunchMode.externalApplication),
      icon: Icon(icon, size: 14),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        visualDensity: VisualDensity.compact,
      ),
    );
  }'''),
    ...para('//',
        r'launchUrl with LaunchMode.externalApplication opens the '
        r'search outside the app. On the web build that is a new '
        r'browser tab, which matters here: the user keeps the topic '
        r'open and does not lose their place. The Future that '
        r'launchUrl returns is ignored, so a blocked pop-up produces '
        r'no message. The same call and mode are used for links in '
        r'markdown_text.dart, so the app opens every outside link in '
        r'the same way.'),

    ...sec(r'edge cases'),
    ...pt('//', r'empty fields',
        r'every field in BibliographyEntry.fromJson falls back to an '
        r'empty string. A card with an empty title would search '
        r'for nothing, and with empty authors the Google Scholar query '
        r'begins with a space. Neither crashes.'),
    ...pt('//', r'fewer than three entries',
        r'the widget maps whatever list it gets, so zero entries '
        r'draw an empty column. It does not enforce the three.'),
    ...pt('//', r'no state',
        r'the widget is stateless; there is nothing to dispose and '
        r'nothing to lose on a rebuild.'),

    ...sec(r'how it is tested'),
    ...para('//',
        r'There is no widget test for this file. test/widget_test.dart '
        r'has a single test, that the unlock screen shows on first '
        r'run. What is tested is the data side: '
        r'test/mistral_client_test.dart parses a narrow response, so '
        r'the BibliographyEntry objects this widget receives are '
        r'covered up to the model class. The layout and the three URLs '
        r'are checked only by looking.'),

    ...sec(r'where it is used'),
    ...para('//',
        r'narrow_topic_view.dart puts it in the second tab, between '
        r'Intersection and Outline, passing topic.starterBibliography '
        r'and the language. The tab body is wrapped in a '
        r'SingleChildScrollView by the caller, which is why this '
        r'widget has no scrolling of its own.'),

    ...sec(r'history'),
    ...pt('//', r'7a200e7, 2026-08-06 09:41',
        r'the scaffold commit, with the whole widget in place.'),
    ...pt('//', r'89a9c12, 2026-08-06 09:58',
        r'“Fix web build: replace unmaintained lucide_icons with '
        r'lucide_icons_flutter”. Seventeen minutes later the import '
        r'changed to the maintained package; the icon names did not.'),
  ],
);
