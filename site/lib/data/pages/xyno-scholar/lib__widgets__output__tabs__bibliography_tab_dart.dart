import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-scholar/lib/widgets/output/tabs/bibliography_tab.dart',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', 'bibliography_tab.dart — three starting sources, each one click from a real search'),
    cm('//', 'the app does not vouch for the citations; it makes them cheap to check'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', 'second tab of a narrow topic: the starter bibliography, as cards with search links'),
    kv('language', 'Dart / Flutter, StatelessWidget + one private button widget'),
    kv('size', '148 lines'),
    kv('history', '2 commits, 7a200e7 (scaffold) and 89a9c12 (icon package import)'),
    kv('data', 'List<BibliographyEntry> from NarrowTopic.starterBibliography'),
    kv('links to', 'Google Scholar, JSTOR, WorldCat (search pages, not the works)'),
    ...sec('the problem this tab has to solve'),
    ...para('//',
        'A research assistant that hands a student a reading list '
        'has a trust problem built in. The list comes from a '
        'language model, and language models are known to produce '
        'citations that look right and do not exist. The system '
        'prompt in lib/services/mistral_client.dart knows it: rule '
        '6 says every subject must name “REAL, VERIFIABLE events, '
        'works, people, or documents” and “Never invent anecdotes '
        'or fabricate references, titles, or names”. A rule in a '
        'prompt is a request, though, not a guarantee, and the '
        'bibliography is where a failure would hurt most, since a '
        'student may go and look for the book.'),
    ...para('//',
        'This file is the app’s answer on the display side. It '
        'does not try to decide which citations are real. It makes '
        'each of the three entries one click away from a search '
        'in a catalogue that would know: Google Scholar, JSTOR '
        'and WorldCat. If the book exists, the search finds it. If '
        'it does not, the student finds out in seconds, from a '
        'source other than the model.'),

    ...sec('what the model is asked for'),
    ...para('//',
        'The prompt’s schema gives each entry six string fields: '
        'authors, year, title, publication, type (one of book, '
        'article or primary_source) and relevance. Narrow mode '
        'asks for exactly three entries, and the refine request '
        'repeats that requirement. The schema deliberately has no '
        'URL and no DOI field. That absence is a design choice, '
        'whether or not it was a conscious one: a model asked for '
        'links will produce plausible links, and a plausible link '
        'that leads nowhere is worse than none. By asking only for '
        'facts a human can check, the app can build every link '
        'itself, from fields it controls. The repository does not '
        'state this reasoning, so treat it as a reading of the '
        'schema.'),
    ...code('dart', 'lib/models/bibliography_entry.dart · tolerant parsing', r'''
      authors: json['authors']?.toString() ?? '',
      year: json['year']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      publication: json['publication']?.toString() ?? '',
      type: json['type']?.toString() ?? 'book','''),
    ...para('//',
        'Parsing is deliberately forgiving: every field goes '
        'through toString(), so a model that returns the year as a '
        'number (1998 instead of "1998") still parses, and a '
        'missing field becomes an empty string rather than an '
        'exception. The one default that is not empty is type, '
        'which falls back to book. The cost of that forgiveness '
        'shows up in the widget, as the limits section explains.'),

    ...sec('three search links built with Uri.https'),
    ...code('dart', 'lib/widgets/output/tabs/bibliography_tab.dart · the link builders', r'''
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
        'Each builder uses Uri.https with a queryParameters map '
        'instead of gluing a string together. Dart percent-encodes '
        'the values, so a title with an ampersand, a quotation mark, '
        'an accent or a colon cannot break out of the query or '
        'change what is being asked. That is not decoration. These '
        'strings come from a model and are shown to a person who '
        'will click; a hand-built URL would be a place where a '
        'stray character turns a search into something else.'),
    ...para('//',
        'The three builders differ in what they send. Google '
        'Scholar gets authors and title in one query, which is how '
        'people search for a known work there. JSTOR and WorldCat '
        'get the title alone. The code gives no reason for the '
        'difference. A plausible one, offered as a guess, is that '
        'the model’s author strings (“Georges Duby”, “Duby, G.”, '
        '“Duby et al.”) are inconsistent, and a catalogue’s title '
        'index is more forgiving than its author index, while '
        'Scholar’s full-text ranking uses both. The endpoint paths '
        'are what the code uses; I did not test that each site '
        'still answers on them.'),
    ...pt('//', 'Scholar',
        'broadest; finds articles, books, citations and often a '
        'link to a full text.'),
    ...pt('//', 'JSTOR',
        'journals and book chapters in the humanities, a natural '
        'target for the fields the app defaults to.'),
    ...pt('//', 'WorldCat',
        'library holdings, the right check for a book and for which '
        'library has it.'),
    blank,

    ...sec('the type badge'),
    ...code('dart', 'lib/widgets/output/tabs/bibliography_tab.dart · _typeLabel', r'''
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
        'This is a four-line localisation of a three-value enum '
        'carried as a string. The language is the topic’s language, '
        'passed down from the response, not the toggle in the app '
        'bar. The ‘article’ branch picks the same word in both '
        'languages, which makes the ternary redundant but keeps the '
        'three cases parallel. The default branch returns the raw '
        'value, so if the model sends a type outside the schema, '
        'say “thesis”, the badge shows that word untranslated '
        'instead of failing.'),
    ...para('//',
        'The type matters outside this file, too. '
        'lib/services/bibtex_export.dart maps book to a BibTeX '
        'book, article to article and primary_source (and anything '
        'else) to misc, and reads the publication field as the '
        'publisher, the journal or the howpublished note '
        'accordingly. That is worth knowing here because the '
        'publication string is a single field whose meaning '
        'depends on the type, while this tab shows it the same '
        'way for all three.'),

    ...sec('the card'),
    ...code('dart', 'lib/widgets/output/tabs/bibliography_tab.dart · title and badge (trimmed)', r'''
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
                      backgroundColor: colors.amber.withValues(alpha: 0.14),'''),
    ...para('//',
        'Each entry is a raised white block (surfaceRaised, a 10 px '
        'radius, a one pixel border, 16 px padding, 14 px between '
        'cards): the same hand-built recipe the outline tab and the '
        'notebook drawer use. The title is set in the serif face, '
        'Fraunces, as an item to read; the type is an amber chip, '
        'compact density, at 11 px, to be glanced at. Amber is the '
        'accent the app uses for emphasis, here against the teal '
        'used for the interactive chips elsewhere. One more '
        'decision sits in the structure: the title is wrapped in '
        'Expanded so that a long title wraps and pushes the chip '
        'neither off the card nor over the text.'),
    ...code('dart', 'lib/widgets/output/tabs/bibliography_tab.dart · the meta line and the relevance note', r'''
                Text(
                  '${entry.authors} · ${entry.year} · ${entry.publication}',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: colors.inkMuted),
                ),
                const SizedBox(height: 10),
                MarkdownText(entry.relevance),'''),
    ...para('//',
        'Authors, year and publication are joined with a middle dot '
        'on one muted line, the classic bibliographic shorthand. '
        'The relevance note, the model’s sentence on why this '
        'source matters for this topic, goes through MarkdownText '
        '(lib/widgets/common/markdown_text.dart) because the prompt '
        'allows light Markdown in “relevance notes”. That widget '
        'also unescapes HTML entities as a safety net, which pairs '
        'with the sanitiser run on every response in the client.'),

    ...sec('the link buttons'),
    ...code('dart', 'lib/widgets/output/tabs/bibliography_tab.dart · the private button', r'''
    return OutlinedButton.icon(
      onPressed: () => launchUrl(uri, mode: LaunchMode.externalApplication),
      icon: Icon(icon, size: 14),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        visualDensity: VisualDensity.compact,
      ),
    );'''),
    ...para('//',
        'A private _LinkButton keeps the three buttons identical: '
        'an outlined button with an icon (graduationCap for '
        'Scholar, library for JSTOR, archive for WorldCat), a '
        '12 px label and compact density. launchUrl with '
        'LaunchMode.externalApplication opens the search outside '
        'the app; on the web build that means a new browser tab, so '
        'the student does not lose their topic page. This tab sends '
        'nothing anywhere until a link is clicked, and what then '
        'leaves is the entry’s own title and authors, sent to the '
        'site the user chose.'),
    ...para('//',
        'All three links appear on every entry, whatever its type. '
        'A primary source (a papal letter, a chronicle) is unlikely '
        'to be found by title on JSTOR, and a journal article does '
        'not live in a library catalogue. Choosing the links by '
        'type would be a small switch; the code shows all three, '
        'and lets the user decide.'),

    ...sec('where it is wired'),
    ...para('//',
        'NarrowTopicView in lib/widgets/output/narrow_topic_view.dart '
        'creates the tab as the second child of a TabBarView inside '
        'a fixed 620 px box, wrapped in its own scroll view, and '
        'passes topic.starterBibliography and the response’s '
        'language. The same list also feeds the Export BibTeX '
        'button in that file, so what the student sees as three '
        'cards and what they can copy into a reference manager are '
        'one data set. The tab’s label comes from AppStrings: '
        '“Bibliographie de départ” or “Starter Bibliography”. The '
        'word “starter” can be read as the app’s own hedge: three '
        'sources are a way in, not a survey.'),

    ...sec('what changed over time'),
    ...para('//',
        'The file has two commits, both on 2026-08-06. 7a200e7 '
        '(09:41 UTC) is the scaffold and contains the whole design '
        'described here. 89a9c12 (09:58 UTC) changes the icon '
        'import to lucide_icons_flutter. Nothing about the links '
        'or the card layout changed through the three backend '
        'swaps, which is the intended outcome of a design whose '
        'inputs are six strings.'),

    ...sec('what is tested'),
    ...para('//',
        'The tab has no test. What is tested is its input: in '
        'test/mistral_client_test.dart the narrow-scope case '
        'builds three entries of types book, article and '
        'primary_source and asserts that '
        'starterBibliography has length 3. The URL builders are '
        'pure functions and would be easy to test, for instance '
        'that a title containing “&” and “é” round-trips through '
        'Uri.queryParameters, but the functions are private to the '
        'library, so a test would first need them made public or '
        'marked visible for testing.'),

    ...sec('limits and what is next'),
    ...pt('//', 'empty fields leave stray separators',
        'because missing values parse to empty strings, an entry '
        'without a year renders as “Author ·  · Publisher”; the '
        'line is not assembled from non-empty parts.'),
    ...pt('//', 'the app cannot tell if a source is real',
        'it only makes checking easy. A search that returns '
        'nothing is a signal, not a verdict, since the title may '
        'be correct in another language or edition.'),
    ...pt('//', 'one query shape per site',
        'no quoting of the title, so a short or common title can '
        'return noise; wrapping it in quotation marks is a '
        'one-character change per builder.'),
    ...pt('//', 'links not chosen by type',
        'primary sources get the same three buttons as books.'),
    ...pt('//', 'fixed visible count',
        'the prompt demands exactly three; the widget would render '
        'any number.'),
    blank,
    link('→ github.com/XNash/xyno-scholar', 'https://github.com/XNash/xyno-scholar'),
  ],
);
