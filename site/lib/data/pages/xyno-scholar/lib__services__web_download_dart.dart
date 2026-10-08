import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-scholar/lib/services/web_download.dart',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', 'web_download.dart — saving a file with no server'),
    cm('//', '16 lines: a Blob, an object URL and a click nobody sees'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', 'triggers a browser file download from a string held in memory'),
    kv('language', 'Dart, using dart:js_interop and package:web (browser only)'),
    kv('size', '16 lines, 1 function'),
    kv('caller', 'lib/widgets/dialogs/bibtex_export_dialog.dart'),
    kv('tests', 'none'),
    ...sec('the problem'),
    ...para('//',
        'The app is a static site, so there is no server route that '
        'could answer a request with a file and a Content-Disposition '
        'header. Yet the BibTeX dialog needs a Download button that '
        'saves a .bib file with a name of the app’s choosing. The '
        'only way to do that without a backend is to manufacture the '
        'file in the browser: put the text in a Blob, give the Blob a '
        'temporary address, and make the browser follow a link to it '
        'that is marked as a download. Those steps are the function '
        'below, and they are the standard recipe for it.'),
    ...sec('the whole function'),
    ...code('dart', 'lib/services/web_download.dart', r'''
/// Triggers a browser download of [content] as a text file named [filename].
void downloadTextFile(String filename, String content) {
  final blobParts = <JSAny>[content.toJS].toJS;
  final blob = web.Blob(blobParts, web.BlobPropertyBag(type: 'text/plain'));
  final url = web.URL.createObjectURL(blob);
  final anchor = web.document.createElement('a') as web.HTMLAnchorElement
    ..href = url
    ..download = filename;
  web.document.body?.appendChild(anchor);
  anchor.click();
  anchor.remove();
  web.URL.revokeObjectURL(url);
}'''),
    ...sec('step by step'),
    ...pt('//', '1. a JavaScript array of strings',
        'a Blob is built from a list of parts. Dart’s String is not a '
        'JavaScript string, so content.toJS converts it, and a list '
        'of JSAny values has a toJS extension that converts the list '
        'into a JavaScript array. This is the cost of '
        'dart:js_interop: values crossing the boundary are converted '
        'explicitly, and the compiler checks the types.'),
    ...pt('//', '2. the Blob',
        'web.Blob wraps the parts, and the options object sets the '
        'type to text/plain. Browsers write strings into a Blob as '
        'UTF-8, so French accents in titles and authors survive. The '
        'MIME type is plain text, not a BibTeX-specific type, so the '
        'browser has no special handler to launch and simply saves '
        'it.'),
    ...pt('//', '3. an address for the Blob',
        'createObjectURL returns a temporary blob: URL that points at '
        'the in-memory data and is valid for this document only. '
        'Nothing is uploaded; the URL never leaves the browser.'),
    ...pt('//', '4. a link that downloads',
        'an anchor element is created and given the Blob URL as its '
        'destination. The download attribute is what turns a '
        'navigation into a save and supplies the file name. The '
        'cascade operator sets both properties on the cast element in '
        'one expression.'),
    ...pt('//', '5. append, click, remove',
        'the anchor is attached to the body, clicked from code and '
        'removed again. It is never visible. Attaching it first is '
        'the conventional safeguard, because some browsers only '
        'honour a click on an element that is in the document. The '
        'body is accessed with a null-aware call, so if there were no '
        'body the append would be skipped instead of throwing.'),
    ...pt('//', '6. release the memory',
        'revokeObjectURL tells the browser it can free the Blob that '
        'the URL kept alive. Calling it in the same function, '
        'immediately after click, is common practice. The repository '
        'has no test of other browsers, so I cannot say it was '
        'checked outside one.'),
    ...sec('where the file name comes from'),
    ...para('//',
        'The function trusts its filename argument, and the argument '
        'is built from model output: the dialog passes the topic’s '
        'slug with .bib added. The slug comes from '
        'narrow_topic_view.dart, which lowercases the topic title, '
        'removes every character outside lowercase letters, digits, '
        'whitespace and hyphen, trims it and turns runs of whitespace '
        'into single hyphens; if nothing is left it falls back to '
        'xyno-scholar-topic. A title that tried to include a path '
        'separator or an odd character would therefore lose it before '
        'reaching the download attribute. The safety lives in the '
        'caller, and this function would pass through whatever it was '
        'given.'),
    ...sec('why it is a separate file'),
    ...para('//',
        'Two things made the function worth isolating. It is the '
        'second of exactly two places where package:web appears in '
        'the app (the other is session_storage.dart), so the browser '
        'dependency is confined and every other file is plain Dart. '
        'And its caller needs one idea only: give me a file name and '
        'text. The dialog reads like a normal Flutter widget with no '
        'JavaScript types in sight.'),
    ...para('//',
        'The cost is that the function cannot be exercised by an '
        'ordinary Dart VM test, since the interop types have no '
        'implementation outside a browser. There is no test for it, '
        'and the nearest check is a person clicking the button.'),
    ...sec('what it does not handle'),
    ...pt('//', 'large files',
        'the content is built entirely in memory. For three '
        'bibliography entries, a few hundred bytes, this is '
        'irrelevant.'),
    ...pt('//', 'other file types',
        'the MIME type is hard-coded to text/plain. A caller that '
        'wanted a binary or a typed download would need a parameter.'),
    ...pt('//', 'failure reporting',
        'if the browser blocks the download there is no signal. The '
        'function returns nothing and the dialog shows no '
        'confirmation after the download button, unlike the copy '
        'button, which shows a snackbar.'),
    ...pt('//', 'history',
        'one commit, the scaffold (7a200e7). The Cerebras, Gemini and '
        'Mistral rewrites never touched it, which is the benefit of '
        'keeping provider logic far from browser logic.'),
    blank,
    link('→ github.com/XNash/xyno-scholar', 'https://github.com/XNash/xyno-scholar'),
  ],
);
