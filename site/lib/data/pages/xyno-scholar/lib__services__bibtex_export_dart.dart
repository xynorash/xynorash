import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-scholar/lib/services/bibtex_export.dart',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', 'bibtex_export.dart — from a model’s bibliography to a .bib file'),
    cm('//', '53 lines that decide what a citation key looks like'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', 'turns starter-bibliography entries into BibTeX text'),
    kv('language', 'Dart, pure (one model import, no I/O)'),
    kv('size', '53 lines, 4 functions'),
    kv('maps', 'book to @book, article to @article, everything else to @misc'),
    kv('used by', 'lib/widgets/dialogs/bibtex_export_dialog.dart'),
    kv('tests', 'none'),
    ...sec('why this file exists'),
    ...para('//',
        'The end product of a session in this app is a narrow topic: '
        'a title, a research question, an outline and a starter '
        'bibliography of three sources. A student will take those '
        'sources into a reference manager or a LaTeX document, and '
        'the format both understand is BibTeX. This file is the '
        'bridge. It takes the typed BibliographyEntry objects the '
        'model produced and returns text that can be pasted into a '
        '.bib file or downloaded as one, from the export dialog.'),
    ...para('//',
        'The bibliography is the most valuable and the most dangerous '
        'part of the output. Valuable because finding sources is the '
        'hard part of choosing a topic. Dangerous because the system '
        'prompt can only ask the model to name real, verifiable '
        'works; nothing checks them. The export is therefore a '
        'convenience for leads that still have to be verified, and '
        'the file does not pretend to do more than format them.'),
    ...sec('what goes in'),
    ...para('//',
        'A BibliographyEntry (lib/models/bibliography_entry.dart) has '
        'six string fields: authors, year, title, publication, type '
        'and relevance. The type is one of three values defined by '
        'the schema in the system prompt: book, article or '
        'primary_source. BibTeX has a wide vocabulary of entry types; '
        'the file picks the smallest set that fits those three.'),
    ...code('dart', 'lib/services/bibtex_export.dart · type mapping', r'''
String _entryType(String type) => switch (type) {
  'book' => 'book',
  'article' => 'article',
  'primary_source' => 'misc',
  _ => 'misc',
};'''),
    ...para('//',
        'A switch expression with a default arm: unknown types fall '
        'back to misc, which is the BibTeX type with no required '
        'fields, so nothing the model invents can make an entry '
        'invalid. The explicit primary_source arm is redundant with '
        'the default and exists for the reader, who can see the '
        'intended mapping without working out what the wildcard '
        'covers.'),
    ...sec('the fields and the one that changes meaning'),
    ...code('dart', 'lib/services/bibtex_export.dart · bibtexForEntry (trimmed)', r'''
  final key = _citationKey(entry, index);
  final type = _entryType(entry.type);
  final buffer = StringBuffer('@$type{$key,\n');
  buffer.writeln('  author = {${_bibtexEscape(entry.authors)}},');
  buffer.writeln('  title = {${_bibtexEscape(entry.title)}},');
  buffer.writeln('  year = {${_bibtexEscape(entry.year)}},');
  switch (type) {
    case 'book':
      buffer.writeln('  publisher = {${_bibtexEscape(entry.publication)}},');
    case 'article':
      buffer.writeln('  journal = {${_bibtexEscape(entry.publication)}},');
    default:
      buffer.writeln('  howpublished = {${_bibtexEscape(entry.publication)}},');
      buffer.writeln('  note = {Primary source},');
  }
  buffer.write('}');'''),
    ...para('//',
        'Author, title and year are written the same way for every '
        'type. The model’s single publication field changes role with '
        'the type: it is the publisher for a book, the journal for an '
        'article, and a free-text howpublished for anything else, '
        'together with a note saying Primary source. That mapping is '
        'the point of the file. BibTeX’s book type expects author, '
        'title, publisher and year; its article type expects author, '
        'title, journal and year; misc expects nothing. By routing '
        'publication into the right slot, each entry carries the '
        'fields its type requires whenever the model supplied them.'),
    ...para('//',
        'The relevance field, the model’s one-sentence explanation of '
        'why the source matters, is not exported. It is useful in the '
        'interface and meaningless in a bibliography database.'),
    ...para('//',
        'There is a small side effect. The switch above runs on the '
        'already-mapped type, and every unknown type was mapped to '
        'misc first. The misc branch always writes the Primary source '
        'note, so a type the model invented would be labelled a '
        'primary source.'),
    ...sec('escaping braces'),
    ...code('dart', 'lib/services/bibtex_export.dart · _bibtexEscape', r'''
String _bibtexEscape(String value) =>
    value.replaceAll('{', '(').replaceAll('}', ')');'''),
    ...para('//',
        'BibTeX values are delimited by braces, so a stray brace '
        'inside a title can unbalance an entry and make the parser '
        'reject the file from that point on. The function does not '
        'try to escape; it swaps braces for parentheses, which cannot '
        'break the structure. It is lossy: a title written with '
        'braces to protect capitalisation would lose them. But the '
        'failure it prevents is far worse than the loss, because a '
        'single bad entry from a model could make a whole exported '
        'file unreadable. Running it on a title written as L{a} '
        'naissance du Purgatoire gives L(a) naissance du Purgatoire.'),
    ...para('//',
        'It does only that. Characters that are special in LaTeX, '
        'such as the ampersand, the percent sign and the underscore, '
        'are left as the model wrote them, and since the exported '
        'file is plain text the user sees them as is. Whether they '
        'cause a problem depends on the bibliography style in use.'),
    ...sec('the citation key'),
    ...code('dart', 'lib/services/bibtex_export.dart · _citationKey', r'''
String _citationKey(BibliographyEntry entry, int index) {
  final firstAuthorWord = entry.authors
      .split(RegExp(r'[,\s]+'))
      .firstWhere((w) => w.isNotEmpty, orElse: () => 'ref');
  final slug = firstAuthorWord.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
  final year = entry.year.replaceAll(RegExp(r'[^0-9]'), '');
  final base = '${slug.isEmpty ? 'ref' : slug}${year.isEmpty ? '' : year}';
  return base.isEmpty ? 'ref$index' : '$base${index > 0 ? index : ''}';
}'''),
    ...para('//',
        'A BibTeX entry needs a unique key, the handle used in a '
        'LaTeX citation command. The convention here is the first '
        'word of the authors string, stripped to letters and digits, '
        'followed by the digits of the year, with the entry’s '
        'position appended from the second entry onward. I ran the '
        'function on a few inputs to see what that produces.'),
    plain('   Le Goff, Jacques / 1985   at position 0  ->  Le1985'),
    plain('   Jacques Le Goff / c. 1985 at position 1  ->  Jacques19851'),
    plain('   Émile Mâle / 1898         at position 3  ->  mile18983'),
    plain('   (empty authors, empty year) at position 2 ->  ref2'),
    ...para('//',
        'Four observations. The first form, surname first and a '
        'comma, gives the right key only because of the comma: split '
        'on commas and whitespace, the first token is Le, not Le '
        'Goff. The second form, given name first, yields the given '
        'name as the key. The prompt does not say which order the '
        'authors string should use, so the quality of keys depends on '
        'what the model happens to write. Third, the character class '
        'keeps only ASCII letters and digits, so an initial like É is '
        'dropped, not folded: the key is mile and not Emile. For an '
        'app whose default language is French that matters; '
        'lib/services/field_detection.dart contains an accent-folding '
        'helper, but it is private to that file and is not reused '
        'here. Fourth, a year such as c. 1985 contributes its digits '
        'to the key while the year field keeps the original text.'),
    ...para('//',
        'The position suffix is what keeps keys unique: the first '
        'entry has no suffix, later ones get their zero-based index. '
        'It guarantees distinct keys for entries with the same author '
        'and year, which is the common clash. It is not a proof of '
        'uniqueness for contrived inputs where one key is a prefix of '
        'another.'),
    ...para('//',
        'One branch is unreachable: the final return tests whether '
        'the base is empty, but the base always begins with ref when '
        'the author slug is empty, so it can never be empty. Both '
        'paths would have produced ref followed by the index, so the '
        'dead branch is harmless.'),
    ...sec('assembling the file'),
    ...code('dart', 'lib/services/bibtex_export.dart · bibtexForEntries', r'''
String bibtexForEntries(List<BibliographyEntry> entries) {
  return entries
      .asMap()
      .entries
      .map((e) => bibtexForEntry(e.value, index: e.key))
      .join('\n\n');
}'''),
    ...para('//',
        'asMap().entries is the idiomatic way to get an index '
        'alongside each element in Dart, and the entries are '
        'separated by a blank line. The output ends without a '
        'trailing newline. Every field line ends with a comma, '
        'including the last, which BibTeX parsers generally accept.'),
    ...sec('where it is called'),
    ...para('//',
        'lib/widgets/dialogs/bibtex_export_dialog.dart calls '
        'bibtexForEntries once, when the dialog opens, and shows the '
        'text in a selectable, scrollable monospace box. Three '
        'buttons sit under it: Close, Copy all, which puts the text '
        'on the clipboard, and a download button that calls '
        'downloadTextFile with the topic’s slug plus the .bib '
        'extension (see lib/services/web_download.dart). The slug is '
        'built in narrow_topic_view.dart from the topic title and '
        'falls back to xyno-scholar-topic when the title yields '
        'nothing.'),
    ...sec('testing and honest limits'),
    ...para('//',
        'There is no test for this file. The behaviour above came '
        'from reading and from running the functions by hand. Given '
        'that the output format is the contract with other programs, '
        'it would be worth pinning with three tests: one entry of '
        'each type, a title with braces, and the key for a '
        'surname-first and a given-name-first author.'),
    ...pt('//', 'authors are one string',
        'BibTeX separates multiple authors with the word and; the '
        'prompt does not ask the model to use it, so a multi-author '
        'string may be read as one long name.'),
    ...pt('//', 'no identifiers',
        'there is no DOI, ISBN or URL field in the model schema, so '
        'there is nothing to export.'),
    ...pt('//', 'years are free text',
        'the year field is copied as is, including values like c. '
        '1985 that a strict BibTeX style may not accept.'),
    ...pt('//', 'keys lose accents',
        'see above; sharing one folding helper between this file and '
        'the field detector would fix it.'),
    ...pt('//', 'references are unverified',
        'the file formats whatever the model said. A fabricated '
        'source exports as cleanly as a real one.'),
    blank,
    link('→ github.com/XNash/xyno-scholar', 'https://github.com/XNash/xyno-scholar'),
  ],
);
