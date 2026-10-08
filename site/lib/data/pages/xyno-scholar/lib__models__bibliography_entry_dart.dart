import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-scholar/lib/models/bibliography_entry.dart',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', 'bibliography_entry.dart — one suggested source, held with suspicion'),
    cm('//', 'six strings, no identifier to hallucinate, three ways to check'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', 'one entry of a topic’s starter bibliography'),
    kv('language', 'Dart'),
    kv('size', '37 lines'),
    kv('history', 'one commit, 7a200e7 (2026-08-06); unchanged since'),
    kv('type values', 'book | article | primary_source'),
    kv('consumers', 'the bibliography tab, the BibTeX exporter, and NarrowTopic.toJson'),
    ...sec('why this file exists'),
    ...para('//',
        'A topic is only useful to a student if they can start '
        'reading. So a narrow topic carries three starting sources, and '
        'this class is one of them. It is also where the project’s '
        'honesty about language models is most concentrated, because '
        'a model asked for books will sometimes produce a book that '
        'does not exist. Look at what the class contains, and at what '
        'it conspicuously lacks.'),
    ...code('dart', 'lib/models/bibliography_entry.dart · the fields', r'''
class BibliographyEntry {
  final String authors;
  final String year;
  final String title;
  final String publication;
  final String type; // book | article | primary_source
  final String relevance;'''),

    ...sec('what is absent: no DOI, no ISBN, no URL'),
    ...para('//',
        'There is no field for a link or an identifier. That is '
        'consistent with the prompt’s sixth rule, “Every subject must '
        'name REAL, VERIFIABLE events, works, people, or documents. '
        'Never invent anecdotes or fabricate references, titles, or '
        'names”, and with the tab’s name, “Starter Bibliography”. '
        'My reading is that the schema offers the model nothing '
        'to fabricate beyond ordinary bibliographic text, and that '
        'verification is handed to the reader through search links '
        'instead (see bibliography_tab.dart). The repository does '
        'not state this reasoning; the code is simply consistent '
        'with it. A model can invent a plausible title, but it '
        'cannot invent a DOI that resolves.'),

    ...sec('every field is a string, including the year'),
    ...para('//',
        'year is a String although it usually looks like a number. '
        'The prompt’s schema says "year": string, and the parser '
        'makes it robust either way:'),
    ...code('dart', 'lib/models/bibliography_entry.dart · fromJson', r'''
      authors: json['authors']?.toString() ?? '',
      year: json['year']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      publication: json['publication']?.toString() ?? '',
      type: json['type']?.toString() ?? 'book',
      relevance: json['relevance']?.toString() ?? '','''),
    ...para('//',
        'If the model returns 1976 as a JSON number instead of '
        '“1976”, toString() converts it and nothing throws. As text, '
        'the year can also be what sources really have: a range, an '
        'approximation, a century. The default for type is ‘book’, '
        'so a missing type reads as the commonest case rather than '
        'as an error. The type is a free string with a comment, not '
        'an enum, so an unexpected value such as ‘thesis’ survives '
        'parsing and is dealt with by each consumer.'),

    ...sec('three consumers, three treatments of type'),
    ...para('//',
        'The UI shows it as a localized chip, with the raw string '
        'as the fallback for unknown values:'),
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
        'The BibTeX exporter maps it to an entry type and, with it, '
        'to a different field for the same ‘publication’ string:'),
    ...code('dart', 'lib/services/bibtex_export.dart · _entryType and field choice', r'''
String _entryType(String type) => switch (type) {
  'book' => 'book',
  'article' => 'article',
  'primary_source' => 'misc',
  _ => 'misc',
};'''),
    ...code('dart', 'lib/services/bibtex_export.dart · where publication goes', r'''
    case 'book':
      buffer.writeln('  publisher = {${_bibtexEscape(entry.publication)}},');
      break;
    case 'article':
      buffer.writeln('  journal = {${_bibtexEscape(entry.publication)}},');
      break;
    default:
      buffer.writeln('  howpublished = {${_bibtexEscape(entry.publication)}},');
      buffer.writeln('  note = {Primary source},');'''),
    ...para('//',
        'This is why publication is a single field: its meaning is '
        'decided by type. For a book it is a publisher, for an article '
        'a journal, for a primary source a place of conservation, and '
        'the exporter files it under publisher, journal or '
        'howpublished accordingly. An unknown type falls into the '
        '‘misc’ branch together with primary sources, and so inherits '
        'the ‘Primary source’ note, which would be wrong for, say, a '
        'thesis. The third consumer, NarrowTopic.toJson, passes all '
        'six fields through unchanged for the notebook and for '
        'refine.'),

    ...sec('a consequence for citation keys'),
    ...para('//',
        'The exporter builds a citation key from the first word of '
        'authors, the digits of year and the entry’s position in '
        'the list. Tracing the code for the three entries in the '
        'test data (Author A 2001, Author B 2002, Author C 2003) '
        'gives Author2001, Author20021 and Author20032: the index '
        'is appended directly after the year, so later keys read like '
        'five-digit years. They are unique, which is what BibTeX '
        'needs, but not pretty. And because the prompt does not say '
        'in which order author names are written, a model that '
        'writes “Georges Duby” instead of “Duby, Georges” produces a '
        'key that starts with a given name. That is an inference '
        'from reading _citationKey, not a tested behaviour.'),

    ...sec('what the tests prove'),
    ...para('//',
        'The narrow and refine tests in test/mistral_client_test.dart '
        'build three entries, one of each type (book, article, '
        'primary_source), and check that three entries arrive. That '
        'pins the parser for the happy path and nothing more: there '
        'is no test file for the exporter or for the type mapping.'),

    ...sec('limits and what is next'),
    ...pt('//', 'unverified by construction',
        'the model’s sources are suggestions; the app offers search '
        'links, not confirmation.'),
    ...pt('//', 'type is a free string',
        'an enum with an explicit unknown case would keep unknown '
        'types out of the primary-source branch of the exporter.'),
    ...pt('//', 'unstructured authors',
        'one string for all authors; BibTeX wants “Family, Given and '
        'Family, Given”, which the app does not enforce.'),
    ...pt('//', 'key format',
        'a separator between the year and the index would make '
        'collisions readable.'),
    blank,
    link('→ github.com/XNash/xyno-scholar', 'https://github.com/XNash/xyno-scholar'),
  ],
);
