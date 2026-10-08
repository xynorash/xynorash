import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-scholar/lib/widgets/dialogs/bibtex_export_dialog.dart',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', 'bibtex_export_dialog.dart — from three suggestions to a file a reference manager reads'),
    cm('//', 'preview, copy, download'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', 'modal dialog that shows the bibliography as BibTeX with copy and download actions'),
    kv('language', 'Dart / Flutter'),
    kv('size', '114 lines'),
    kv('history', 'two commits: 7a200e7 (scaffold), 89a9c12 (icon package import)'),
    kv('depends on', 'bibtex_export.dart for text, web_download.dart for the file'),
    ...sec('why this dialog exists'),
    ...para('//',
        'The starter bibliography is only useful if it can leave '
        'the page. A student who likes a topic will want its three '
        'sources in Zotero, JabRef or a LaTeX project, and BibTeX is '
        'the lingua franca for that. The dialog makes the export '
        'a two-step affair on purpose: show the text first, then let '
        'the student either copy it or download it. Showing it '
        'matters because the content is machine-suggested and '
        'unverified; a student should be able to read what they are '
        'about to import.'),

    ...sec('the entry point does the work once'),
    ...code('dart', 'lib/widgets/dialogs/bibtex_export_dialog.dart · showBibtexExportDialog', r'''
Future<void> showBibtexExportDialog(
  BuildContext context, {
  required List<BibliographyEntry> entries,
  required String language,
  required String topicSlug,
}) {
  final content = bibtexForEntries(entries);
  return showDialog(
    context: context,
    builder: (context) => _BibtexDialog(
      content: content,
      language: language,
      topicSlug: topicSlug,
    ),
  );
}'''),
    ...para('//',
        'A top-level function, not a widget with a static method, '
        'is how callers use it (narrow_topic_view.dart passes the '
        'topic’s entries, the response language and a slug). The '
        'BibTeX string is built once, before the dialog opens, and '
        'passed down as a plain String. The private widget, '
        '_BibtexDialog, is therefore a StatelessWidget with no '
        'providers: it receives a value and displays it. That makes '
        'it trivially testable in principle and keeps the string from '
        'being regenerated on every rebuild, such as when the window '
        'resizes.'),
    ...para('//',
        'language is passed in rather than read from a provider, '
        'following the pattern of the narrow view: the dialog '
        'speaks the language of the topic that opened it, not of '
        'the sidebar’s current toggle. If the student switched the '
        'toggle after generating, the dialog would still use the '
        'topic’s language, which is consistent with the rest of the '
        'narrow view.'),

    ...sec('the layout: a bounded card with a scrolling text well'),
    ...code('dart', 'lib/widgets/dialogs/bibtex_export_dialog.dart · the text well', r'''
              Flexible(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: colors.parchment,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: colors.border),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      content,
                      style: AppTypography.mono(
                        fontSize: 12.5,
                        color: colors.ink,
                      ),
                    ),
                  ),
                ),
              ),'''),
    ...para('//',
        'The dialog is constrained to 640 by 560 pixels. The text well '
        'is Flexible, so it takes the remaining height inside the '
        'column, and its SingleChildScrollView handles overflow '
        'for long entries. The content is a SelectableText in '
        'JetBrains Mono at 12.5 px on a parchment well, so it reads '
        'like a code block and can be selected by hand. Monospace '
        'is practical here: the braces and indentation line up as '
        'they will in the .bib file. This is one of the three places '
        'the mono family is used.'),

    ...sec('copy and download'),
    ...code('dart', 'lib/widgets/dialogs/bibtex_export_dialog.dart · actions', r'''
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: content));
                      if (context.mounted) {
                        ScaffoldMessenger.of(
                          context,
                        ).showSnackBar(SnackBar(content: Text(s.copied)));
                      }
                    },'''),
    ...para('//',
        'The copy handler awaits the clipboard write and then checks '
        'context.mounted before using the context for the snack bar. '
        'That is the standard guard for a context used across an '
        'async gap; the same shape appears in the Save button '
        '(narrow_topic_view.dart) and the problématique copy button '
        '(problematique_callout.dart). The two copy buttons also '
        'share the confirmation string, s.copied.'),
    ...code('dart', 'lib/widgets/dialogs/bibtex_export_dialog.dart · download', r'''
                    onPressed: () =>
                        downloadTextFile('$topicSlug.bib', content),'''),
    ...para('//',
        'Download is a one-liner because the work is elsewhere. '
        'downloadTextFile (lib/services/web_download.dart) builds a '
        'Blob, points a temporary anchor at an object URL, clicks it '
        'and revokes the URL. The file name comes from the topic '
        'slug computed in narrow_topic_view.dart. The three buttons '
        'are ordered by weight: a quiet text button for Close, an '
        'outlined button for Copy all, and the amber elevated button '
        'for Download .bib, the primary action.'),

    ...sec('a consequence of going through dart:js_interop'),
    ...para('//',
        'web_download.dart imports dart:js_interop and package:web. '
        'This dialog imports that file, so the widget is web-only: '
        'dart:js_interop is available only when compiling for the '
        'web. That fits the project (Flutter Web, deployed to '
        'GitHub Pages with flutter build web) but it is a boundary '
        'worth stating.'),

    ...sec('what is tested'),
    ...para('//',
        'There is no test for the dialog or for the exporter '
        'it uses. test/ has three files: the Mistral client, the '
        'sanitiser and the unlock-screen widget test. The BibTeX '
        'text itself (key format, type mapping, brace escaping) is '
        'discussed on the bibliography_entry.dart page; this '
        'widget just frames it.'),

    ...sec('limits and what is next'),
    ...pt('//', 'web only',
        'conditional imports would let the dialog compile on other '
        'platforms with a different download strategy.'),
    ...pt('//', 'untested',
        'a widget test with a fake downloader would cover copy and '
        'save.'),
    ...pt('//', 'content is unverified',
        'the dialog carries no warning that the entries come from '
        'a language model; the tab it is launched from is named '
        '“Starter Bibliography”, which is the only cue.'),
    ...pt('//', 'one file per topic',
        'the download is always .bib with the topic slug; accented '
        'titles lose letters in the slug (see narrow_topic_view.dart).'),
    blank,
    link('→ github.com/XNash/xyno-scholar', 'https://github.com/XNash/xyno-scholar'),
  ],
);
